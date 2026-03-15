/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Прошивка вузла КОРОЛЕВА (LoRa RX -> CIFO Cache -> Binary Batch CoAP -> Starlink/LTE)
  * @processor      : STM32WLE5JC
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* USER CODE BEGIN Includes */
#include <stdio.h>
#include <string.h>

// Підключаємо низькорівневий драйвер радіо (Radio Middleware)
#include "radio.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
UART_HandleTypeDef huart1;  // Інтерфейс для модему SIM7070G (LTE-M / Starlink)
SUBGHZ_HandleTypeDef hsubghz;
CRYP_HandleTypeDef hcryp; // Апаратний криптопроцесор AES
RNG_HandleTypeDef hrng;   // Апаратний генератор випадкових чисел (HRNG)

/* USER CODE BEGIN PV */

// =========================================================================
// === 0. КЛЮЧІ ОХОРОНИ (Trading Post) ===
// =========================================================================
// Секретний 256-бітний ключ мережі Silken Net (Gaia 2.0 Standard).
// МАЄ БУТИ ІДЕНТИЧНИМ ключу, зашитому в усіх Солдатах.
uint32_t aes_key[8] = {0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
                       0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D};

// Унікальний ідентифікатор цієї Королеви (прошивається індивідуально).
// Використовується як третій сегмент CoAP URI-Path: /telemetry/batch/<QUEEN_UID>
// Дозволяє серверу ідентифікувати шлюз навіть при зміні IP (Starlink NAT).
const char queen_uid[] = "QUEEN-001";

// =========================================================================
// === 1. ПАМ'ЯТЬ КОРОЛЕВИ (Прийом Даних) ===
// =========================================================================
volatile uint8_t lora_rx_flag = 0;      // Прапорець: 1 - пакет спіймано
uint8_t incoming_lora_payload[16];      // Сирий 16-байтний зашифрований пакет
uint8_t decrypted_payload[16];          // Розшифрований пакет від Солдата
int8_t current_rssi = 0;                // Рівень сигналу

char at_tx_buffer[256];                 // Буфер для формування AT-команд

// =========================================================================
// === 1.5. EDGE КЕШУВАННЯ (CIFO & Дедуплікація) ===
// =========================================================================
#define CACHE_MAX_ENTRIES 50 // Максимальна місткість нашого кешу

typedef struct {
    uint32_t uid;               // DID дерева
    uint8_t payload[16];        // Останні розшифровані дані
    int8_t rssi;                // Сила сигналу
    uint8_t is_active;          // 1 - якщо слот зайнятий
} EdgeCache;

EdgeCache forest_cache[CACHE_MAX_ENTRIES];
uint8_t cache_count = 0;

// ЗБІЛЬШЕНО ЕФЕКТИВНІСТЬ (Drifting Ice):
// Замість 8192 байтів текстового JSON використовуємо компактний бінарний буфер
// 50 записів по 21 байту = всього 1050 байтів.
uint8_t binary_batch_buffer[2048];

// =========================================================================
// === 1.6. ДЕДУПЛІКАЦІЯ КОМАНД АКТУАТОРІВ (Idempotency Ring Buffer) ===
// =========================================================================
// [СИНХРОНІЗОВАНО з Rails]: ActuatorCommand.idempotency_token (UUID)
// Формат CoAP команди від сервера: CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<UUID>
// Королева зберігає DJB2-хеші останніх N токенів у кільцевому буфері,
// щоб ігнорувати повтори коли ACK загубився і воркер повторив відправку.
//
// Бюджет RAM: 16 × 4 = 64 байти (хеші) + 2 байти (індекси) + 96 байт (буфер) = 162 байти
#define CMD_DEDUP_SIZE 16             // Місткість кільцевого буфера хешів
#define UUID_STR_LEN   36            // Довжина UUID рядка (8-4-4-4-12 з дефісами)

uint32_t cmd_dedup_ring[CMD_DEDUP_SIZE]; // Кільцевий буфер DJB2-хешів
uint8_t  cmd_dedup_idx  = 0;            // Поточна позиція запису
uint8_t  cmd_dedup_used = 0;            // Кількість заповнених слотів (≤ CMD_DEDUP_SIZE)

// Єдиний буфер для дешифровки вхідних CoAP-команд (розділяємо з LoRa тільки поза ISR)
// 544 байти: достатньо для CMD-команд (≤96 байт) та OTA-чанків (≤528 байт = 512 payload + 5 header + 2 CRC + padding)
#define CMD_DECRYPT_BUF_SIZE 544
uint8_t cmd_decrypt_buf[CMD_DECRYPT_BUF_SIZE];

// =========================================================================
// === 2. БУНКЕР OTA-ОНОВЛЕНЬ (Передача нових контрактів) ===
// =========================================================================
// Прапорець: 1 — якщо ми зараз в процесі роздачі нової прошивки лісу.
// Починає з 0: OTA-бродкаст неактивний, поки Королева не отримає всі чанки
// від Rails-бекенду через CoAP downlink і не складе їх у pending_ota_bytecode.
uint8_t ota_is_active = 0;
uint16_t current_ota_chunk_idx = 0;

// Динамічний RAM-буфер для збирання OTA-байткоду з Rails через Handle_CoAP_Command.
// Королева отримує 512-байтні чанки від сервера і складає їх сюди.
// Після прийому всіх чанків — автоматично запускає LoRa-бродкаст на Солдатів.
uint8_t pending_ota_bytecode[8192];
uint16_t pending_ota_size = 0;

// Стан збирання OTA-чанків від бекенду (CoAP downlink → RAM assembly)
uint16_t ota_total_expected_chunks = 0;  // Загальна кількість чанків (з заголовка пакета)
uint16_t ota_chunks_received = 0;        // Скільки чанків вже отримано

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_SUBGHZ_Init(void);
static void MX_CRYP_Init(void); // Ініціалізація шифрування

/* USER CODE BEGIN PFP */
// Функції-обгортки для роботи з модемом та транзитом
void SIM7070_SendATCommand(char* command, uint32_t delay_ms);
void Process_And_Cache_Data(uint32_t uid, uint8_t* payload, int8_t rssi);
void Flush_Cache_To_Rails(void);
// [СИНХРОНІЗОВАНО з Rails]: Обробка вхідних CoAP-команд від сервера
static uint32_t djb2_hash(const char* str, uint8_t len);
uint8_t Cmd_Dedup_Check(uint32_t hash);
void Handle_CoAP_Command(uint8_t* payload, uint16_t len);
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */
/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */
  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/
  HAL_Init();
  SystemClock_Config();

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_USART1_UART_Init(); // UART для розмови з SIM7070G (115200 baud)
  MX_SUBGHZ_Init();
  MX_CRYP_Init();        // Вмикаємо апаратний модуль AES

  /* USER CODE BEGIN 2 */

  // 1. Ініціалізація низькорівневого радіо
  Radio.Init(NULL);
  Radio.SetChannel(868000000); // 868 МГц (Європа / Україна)

  // 2. Ініціалізація Кешу нулями
  memset(forest_cache, 0, sizeof(forest_cache));
  // [СИНХРОНІЗОВАНО з Rails]: Ініціалізація кільцевого буфера дедуплікації команд
  memset(cmd_dedup_ring, 0, sizeof(cmd_dedup_ring));

  // 3. Ініціалізація модему SIM7070G
  // Перевіряємо зв'язок та налаштовуємо режим (LTE-M / NB-IoT)
  SIM7070_SendATCommand("AT\r\n", 500);
  SIM7070_SendATCommand("AT+CNMP=38\r\n", 1000);

  // 4. Відкриваємо вуха: Королева переходить у режим безперервного слухання
  // 0xFFFFFF = нескінченний таймаут
  Radio.Rx(0xFFFFFF);

  /* USER CODE END 2 */

  uint32_t last_flush_time = HAL_GetTick();

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    // =========================================================================
    // ФАЗА ОЧІКУВАННЯ ТА ОБРОБКИ РАДІОЕФІРУ
    // =========================================================================

    // Якщо апаратне переривання OnRxDone спіймало пакет від Солдата
    if (lora_rx_flag == 1)
    {
        // 1. РОЗШИФРОВУЄМО ПАКЕТ
        // Розшифровуємо 4 слова (16 байт) апаратним модулем
        HAL_CRYP_Decrypt(&hcryp, (uint32_t*)incoming_lora_payload, 4, (uint32_t*)decrypted_payload, 1000);

        // =========================================================================
        // РЕФЛЕКТОРНИЙ ПОСТРІЛ (OTA BROADCAST)
        // Солдат прямо зараз (після відправки) слухає ефір рівно 500 мс.
        // Ми маємо блискавично вистрілити шматком нової прошивки йому у відповідь.
        // =========================================================================
        if (ota_is_active) {
            uint8_t ota_chunk[16] = {0};
            uint8_t encrypted_ota[16] = {0};

            // В один 16-байтний пакет влазить 11 байт чистого коду (5 байтів - заголовок: 1 маркер + 2 index + 2 total)
            uint16_t total_chunks = (pending_ota_size + 10) / 11;

            // [FIX: AUDIT] Перевірка індексу перед використанням
            if (current_ota_chunk_idx < total_chunks) {
                // Формуємо заголовок (0x99 = маркер OTA-пакета, 16-bit big-endian index/total)
                ota_chunk[0] = 0x99;
                ota_chunk[1] = (uint8_t)(current_ota_chunk_idx >> 8);
                ota_chunk[2] = (uint8_t)(current_ota_chunk_idx & 0xFF);
                ota_chunk[3] = (uint8_t)(total_chunks >> 8);
                ota_chunk[4] = (uint8_t)(total_chunks & 0xFF);

                // Копіюємо до 11 байт коду в пакет
                uint16_t offset = current_ota_chunk_idx * 11;
                // [FIX: AUDIT CRITICAL] Перевірка на підтікання (offset >= pending_ota_size)
                if (offset < pending_ota_size) {
                    uint8_t bytes_to_copy = (pending_ota_size - offset > 11) ? 11 : (uint8_t)(pending_ota_size - offset);
                    memcpy(&ota_chunk[5], &pending_ota_bytecode[offset], bytes_to_copy);
                }

                // Шифруємо цей шматок коду
                HAL_CRYP_Encrypt(&hcryp, (uint32_t*)ota_chunk, 4, (uint32_t*)encrypted_ota, 1000);

                // СТРІЛЯЄМО В ЕФІР
                Radio.Send(encrypted_ota, 16);

                // Даємо радіомодулю час фізично передати пакет (бл. 50-60 мс)
                HAL_Delay(60);
            }

            // Перемикаємося на наступний шматок для наступного дерева
            current_ota_chunk_idx++;
            if (current_ota_chunk_idx >= total_chunks) {
                current_ota_chunk_idx = 0;
                // Якщо маємо оновити ліс лише один раз, розкоментувати:
                // ota_is_active = 0;
            }
        }

        // =========================================================================
        // ОБРОБКА ДАНИХ (КЕШУВАННЯ)
        // =========================================================================
        // Витягуємо унікальний ID Солдата (перші 4 байти - DID)
        uint32_t sender_id = ((uint32_t)decrypted_payload[0] << 24) |
                             ((uint32_t)decrypted_payload[1] << 16) |
                             ((uint32_t)decrypted_payload[2] << 8)  |
                             (uint32_t)decrypted_payload[3];

        // Замість миттєвої відправки, складаємо в CIFO-кеш
        Process_And_Cache_Data(sender_id, decrypted_payload, current_rssi);

        // Очищаємо прапорець і знову відкриваємо вуха
        lora_rx_flag = 0;
        Radio.Rx(0xFFFFFF);
    }

    // =========================================================================
    // СКИДАННЯ КЕШУ НА СЕРВЕР (GCCS Batching -> UDP/CoAP)
    // =========================================================================
    // Відправляємо пакет даних, якщо кеш заповнений майже повністю (залишилось 5 вільних слотів)
    // АБО пройшло достатньо часу (наприклад, 1 година = 3 600 000 мс)
    if (cache_count >= (CACHE_MAX_ENTRIES - 5) || (HAL_GetTick() - last_flush_time > 3600000)) {
        if (cache_count > 0) {
            // [FIX: Queen Health Blind Spot]
            // Перед скиданням кешу додаємо власний пакет здоров'я Королеви.
            // DID=0 — зарезервований sentinel, backend розпізнає як gateway health.
            // Це дозволяє серверу бачити стан шлюзу (температура, рівень сигналу CSQ)
            // без окремого протоколу.
            {
                uint8_t queen_health[16] = {0};
                // DID = 0x00000000 (sentinel — "це Королева, не дерево")
                // Bytes 4-5: Тік як proxy для uptime (wraps кожні ~65 секунд при /1000)
                uint16_t uptime_sec = (uint16_t)(HAL_GetTick() / 1000);
                queen_health[4] = (uint8_t)(uptime_sec >> 8);
                queen_health[5] = (uint8_t)(uptime_sec & 0xFF);
                // Byte 7: Кількість дерев у кеші (навантаження на шлюз)
                queen_health[7] = cache_count;
                // Byte 10: Status = homeostasis (0), growth_points = cache_count (proxy for health)
                queen_health[10] = (cache_count < 63) ? cache_count : 63;
                Process_And_Cache_Data(0, queen_health, 0); // RSSI=0 (локальний пакет)
            }
            Flush_Cache_To_Rails();
            last_flush_time = HAL_GetTick(); // Оновлюємо таймер
        }
    }

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/* USER CODE BEGIN 4 */

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС РАДІО (Вуха Королеви)
// =========================================================================
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr)
{
    // Очікуємо рівно 16 байт (повний зашифрований блок AES-256)
    if (size == 16)
    {
        memcpy(incoming_lora_payload, payload, 16);
        // [FIX: RSSI Truncation] SX1262 може повернути RSSI < -128.
        // Clamp до int8_t діапазону перед приведенням, щоб запобігти
        // overflow (наприклад, -130 → 126, що б отруїло CIFO eviction).
        if (rssi < -128) rssi = -128;
        if (rssi > 127) rssi = 127;
        current_rssi = (int8_t)rssi;
        lora_rx_flag = 1; // Сигналізуємо головному циклу
    }
}

// =========================================================================
// ЛОГІКА КЕШУ (Дедуплікація та CIFO)
// =========================================================================
void Process_And_Cache_Data(uint32_t uid, uint8_t* payload, int8_t rssi)
{
    // 1. ДЕДУПЛІКАЦІЯ: Шукаємо, чи є вже це дерево в кеші
    for(int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if(forest_cache[i].is_active && forest_cache[i].uid == uid) {
            // Оновлюємо дані на найсвіжіші (бо дерево могло надіслати новий статус)
            memcpy(forest_cache[i].payload, payload, 16);
            forest_cache[i].rssi = rssi;
            return;
        }
    }

    // 2. ВСТАВКА: Якщо є вільне місце в кеші
    if(cache_count < CACHE_MAX_ENTRIES) {
        for(int i = 0; i < CACHE_MAX_ENTRIES; i++) {
            if(!forest_cache[i].is_active) {
                forest_cache[i].uid = uid;
                memcpy(forest_cache[i].payload, payload, 16);
                forest_cache[i].rssi = rssi;
                forest_cache[i].is_active = 1;
                cache_count++;
                return;
            }
        }
    }
    // 3. CIFO (Priority-Aware Eviction): Кеш повний, витісняємо з розумом.
    // [FIX: CIFO Blind Spot] Стара логіка завжди викидала дерево з найгіршим RSSI,
    // але саме це дерево може бути на межі зони пожежі (критичний статус).
    // Нова логіка: спочатку шукаємо некритичне (status=0) дерево з найгіршим RSSI.
    // Якщо ВСІ записи критичні — використовуємо fallback на абсолютно найгірший RSSI.
    else {
        int best_evict_idx = -1;
        int8_t best_evict_rssi = 127;

        int fallback_idx = 0;
        int8_t fallback_rssi = 127;

        for(int i = 0; i < CACHE_MAX_ENTRIES; i++) {
            // [FIX: AUDIT] Перевіряємо is_active щоб не порівнювати неініціалізовані RSSI
            if (!forest_cache[i].is_active) continue;

            // bio_status з байта 10 пейлоада: біти [7:6]
            uint8_t bio_status = (forest_cache[i].payload[10] >> 6) & 0x03;

            // Абсолютний fallback — найгірший RSSI серед усіх
            if (forest_cache[i].rssi < fallback_rssi) {
                fallback_rssi = forest_cache[i].rssi;
                fallback_idx = i;
            }

            // Перевага: витісняємо некритичне (homeostasis, status=0) з найгіршим RSSI
            if (bio_status == 0 && forest_cache[i].rssi < best_evict_rssi) {
                best_evict_rssi = forest_cache[i].rssi;
                best_evict_idx = i;
            }
        }

        int evict_idx = (best_evict_idx >= 0) ? best_evict_idx : fallback_idx;

        forest_cache[evict_idx].uid = uid;
        memcpy(forest_cache[evict_idx].payload, payload, 16);
        forest_cache[evict_idx].rssi = rssi;
    }
}

// =========================================================================
// ПАКЕТНЕ ВІДПРАВЛЕННЯ ЧЕРЕЗ CoAP (Бінарний масив поверх UDP)
// =========================================================================
void Flush_Cache_To_Rails(void)
{
    uint16_t offset = 0;

    // Пакуємо весь кеш у щільний бінарний масив (21 байт на запис)
    for(int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if(forest_cache[i].is_active) {
            if ((offset + 21) > sizeof(binary_batch_buffer)) break;
            // Копіюємо 4 байти DID (великоендіанний формат мережі)
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 24);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 16);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid >> 8);
            binary_batch_buffer[offset++] = (uint8_t)(forest_cache[i].uid & 0xFF);

            // Копіюємо 1 байт RSSI. Інвертуємо знак (наприклад, -85 дБм стає 85).
            // [FIX: AUDIT] Використовуємо (int16_t) приведення для запобігання UB
            // при rssi == -128 (abs(-128) не вміщується в int8_t).
            binary_batch_buffer[offset++] = (uint8_t)(-(int16_t)forest_cache[i].rssi);

            // Копіюємо 16 байтів розшифрованого фізичного Payload'у
            memcpy(&binary_batch_buffer[offset], forest_cache[i].payload, 16);
            offset += 16;

            // Звільняємо слот
            forest_cache[i].is_active = 0;
        }
    }
    cache_count = 0;

    if (offset == 0) return;

    // =========================================================================
    // ШИФРУВАННЯ БАТЧА AES-256-CBC
    // Усуває ECB-вразливість: однакові блоки телеметрії більше не дають
    // однаковий шифротекст. Сервер очікує формат: [IV:16][Зашифровані дані: N*16]
    // =========================================================================

    // 1. Вирівнювання до розміру AES-блоку (16 байт) нульовим padding.
    //    Сервер (TelemetryUnpackerService) ігнорує неповні 21-байтні чанки.
    uint16_t padded_size = ((offset + 15) / 16) * 16;
    if (padded_size > sizeof(binary_batch_buffer)) padded_size = sizeof(binary_batch_buffer);
    memset(binary_batch_buffer + offset, 0, padded_size - offset);

    // 2. Генеруємо криптографічно безпечний IV через апаратний RNG (HRNG).
    //    "Wu-Wei" підхід: ініціалізація RNG безпосередньо перед генерацією IV,
    //    де-ініціалізація одразу після — нульове споживання в режимі сну.
    //    Це запобігає атакам на передбачуваність CBC (CVE-pattern: predictable IV),
    //    зберігаючи мінімальне енергоспоживання для автономної роботи в лісі.
    uint32_t batch_iv[4];

    hrng.Instance = RNG;
    HAL_RNG_Init(&hrng);

    for (uint8_t i = 0U; i < 4U; i++) {
        if (HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK) {
            /* Fallback: якщо HRNG не відповідає — XOR tick з індексом,
               щоб шлюз не зависав у лісі без зв'язку. */
            batch_iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL);
        }
    }

    HAL_RNG_DeInit(&hrng);

    // 3. Оновлюємо IV у конфігурації крипто-модуля та переініціалізуємо
    hcryp.Init.pInitVect = batch_iv;
    HAL_CRYP_Init(&hcryp);

    // 4. Шифруємо батч. Довжина в 32-бітних словах = padded_size / 4.
    //    Буфер: IV (16 байт) + зашифровані дані
    uint8_t encrypted_batch_buffer[2048 + 16];
    memcpy(encrypted_batch_buffer, batch_iv, 16); // Prepend IV як заголовок пакета
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)binary_batch_buffer, padded_size / 4,
                     (uint32_t*)(encrypted_batch_buffer + 16), 2000);

    uint16_t total_size = 16 + padded_size; // IV (16) + зашифровані дані

    // Ініціалізація CoAP сесії (UDP)
    SIM7070_SendATCommand("AT+CCOAPNEW=\"coap://api.silkennet.com:5683\"\r\n", 1000);

    // 1. Початок команди.
    // URI-Path: /telemetry/batch/<queen_uid> — сервер ідентифікує шлюз за UID,
    // а не за IP, що вирішує проблему Starlink NAT та динамічних адрес.
    snprintf(at_tx_buffer, sizeof(at_tx_buffer),
             "AT+CCOAPSEND=0,2,\"telemetry/batch/%s\",%d,\"",
             queen_uid, total_size * 2);
    HAL_UART_Transmit(&huart1, (uint8_t*)at_tx_buffer, strlen(at_tx_buffer), 100);

    // 2. Перетворюємо зашифрований буфер у Hex-рядок на льоту і відправляємо в модем
    char hex_byte[3];
    for (int i = 0; i < total_size; i++) {
        snprintf(hex_byte, sizeof(hex_byte), "%02x", encrypted_batch_buffer[i]);
        HAL_UART_Transmit(&huart1, (uint8_t*)hex_byte, 2, 10);
    }

    // 3. Завершуємо команду (Закриваємо лапки і імітуємо натискання Enter)
    HAL_UART_Transmit(&huart1, (uint8_t*)"\"\r\n", 3, 100);

    // Чекаємо, поки модем надішле дані через ефір та отримає UDP ACK від сервера
    HAL_Delay(2000);

    // Закриваємо CoAP сесію, звільняючи ресурси модему
    SIM7070_SendATCommand("AT+CCOAPDEL=0\r\n", 500);

    // [FIX: CRITICAL — ECB Restoration]
    // Flush_Cache_To_Rails() переключає CRYP на CBC для шифрування батча.
    // Якщо не повернути ECB, всі наступні HAL_CRYP_Decrypt() для LoRa-пакетів
    // від Солдатів будуть використовувати CBC замість ECB → сміття → втрата даних
    // до наступного перезавантаження Королеви.
    hcryp.Init.Algorithm = CRYP_AES_ECB;
    hcryp.Init.pInitVect = NULL;
    HAL_CRYP_Init(&hcryp);
}

// =========================================================================
// ДРАЙВЕР СТІЛЬНИКОВОГО МОДЕМУ (SIM7070G)
// =========================================================================
// Проста обгортка для відправки AT-команд через UART
void SIM7070_SendATCommand(char* command, uint32_t delay_ms)
{
    HAL_UART_Transmit(&huart1, (uint8_t*)command, strlen(command), 1000);
    HAL_Delay(delay_ms); // Чекаємо на відповідь (OK)
}

// =========================================================================
// 🛡️ ДЕДУПЛІКАЦІЯ КОМАНД АКТУАТОРІВ (Idempotency)
// =========================================================================
// [СИНХРОНІЗОВАНО з Rails]: ActuatorCommandWorker відправляє payload формату:
//   CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<IDEMPOTENCY_TOKEN>
// Якщо ACK загубився, воркер повторить відправку з тим самим токеном.

// DJB2 хеш — швидкий, 0 алокацій, достатня ентропія для 16-слотного буфера.
// Колізія UUID практично неможлива при 2^32 просторі та ≤16 активних записах.
static uint32_t djb2_hash(const char* str, uint8_t len)
{
    uint32_t h = 5381;
    for (uint8_t i = 0; i < len && str[i] != '\0'; i++) {
        h = ((h << 5) + h) + (uint8_t)str[i]; // h * 33 + c
    }
    return h;
}

// Перевіряє наявність хешу в кільцевому буфері та зберігає новий.
// Повертає: 0 = новий (виконувати), 1 = дублікат (ігнорувати)
uint8_t Cmd_Dedup_Check(uint32_t hash)
{
    uint8_t count = cmd_dedup_used < CMD_DEDUP_SIZE ? cmd_dedup_used : CMD_DEDUP_SIZE;
    for (uint8_t i = 0; i < count; i++) {
        if (cmd_dedup_ring[i] == hash) return 1;
    }
    cmd_dedup_ring[cmd_dedup_idx] = hash;
    cmd_dedup_idx = (cmd_dedup_idx + 1) % CMD_DEDUP_SIZE;
    if (cmd_dedup_used < CMD_DEDUP_SIZE) cmd_dedup_used++;
    return 0;
}

// =========================================================================
// ОБРОБКА CoAP-КОМАНД ВІД СЕРВЕРА (Downlink)
// =========================================================================
// [СИНХРОНІЗОВАНО з Rails]: ActuatorCommandWorker формує payload:
//   [IV:16][AES-256-CBC зашифровані дані]
//   Відкритий текст: CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<IDEMPOTENCY_TOKEN>
// Приклад: CMD:OPEN:60:42:a1b2c3d4-e5f6-7890-abcd-ef1234567890
//
// [OTA Downlink]: OtaTransmissionWorker формує payload:
//   [IV:16][AES-256-CBC зашифровані дані]
//   Відкритий текст: [0x99][chunk_index:2][total_chunks:2][bytecode:≤512][CRC:2]
//   Цей шлях з'єднує Backend CoAP downlink → RAM assembly → LoRa broadcast на Солдатів.
void Handle_CoAP_Command(uint8_t* payload, uint16_t len)
{
    // Мінімум: IV (16 байт) + один AES-блок (16 байт) = 32 байти
    if (len < 32 || len > (CMD_DECRYPT_BUF_SIZE + 16)) return;

    // 1. Витягуємо IV з перших 16 байтів пейлоада
    uint32_t cmd_iv[4];
    memcpy(cmd_iv, payload, 16);

    // 2. Перемикаємо CRYP на CBC для дешифрування команди
    hcryp.Init.Algorithm = CRYP_AES_CBC;
    hcryp.Init.pInitVect = cmd_iv;
    HAL_CRYP_Init(&hcryp);

    // 3. Дешифруємо шифротекст (після IV)
    uint16_t ciphertext_len = len - 16;
    uint16_t aligned = ((ciphertext_len + 15) / 16) * 16;
    if (aligned > CMD_DECRYPT_BUF_SIZE) {
        // Відновлюємо ECB перед виходом
        hcryp.Init.Algorithm = CRYP_AES_ECB;
        hcryp.Init.pInitVect = NULL;
        HAL_CRYP_Init(&hcryp);
        return;
    }
    HAL_CRYP_Decrypt(&hcryp, (uint32_t*)(payload + 16), aligned / 4,
                     (uint32_t*)cmd_decrypt_buf, 2000);

    // 4. Відновлюємо ECB для LoRa-трафіку між Королевою та Солдатами
    hcryp.Init.Algorithm = CRYP_AES_ECB;
    hcryp.Init.pInitVect = NULL;
    HAL_CRYP_Init(&hcryp);

    cmd_decrypt_buf[CMD_DECRYPT_BUF_SIZE - 1] = '\0';

    // =========================================================================
    // 5. Маршрутизація за маркером: CMD (актуатор) або 0x99 (OTA downlink)
    // =========================================================================
    if (strncmp((char*)cmd_decrypt_buf, "CMD:", 4) == 0) {
        // ── Гілка актуаторних команд ──────────────────────────────────

        // 6. Знаходимо idempotency_token (після 3-ї ':' від позиції +4)
        char* p = (char*)cmd_decrypt_buf + 4;
        uint8_t colons = 0;
        while (*p && colons < 3) { if (*p++ == ':') colons++; }
        if (colons < 3 || *p == '\0') return;

        // 7. 🛡️ Idempotency: хешуємо токен і перевіряємо кільцевий буфер
        if (Cmd_Dedup_Check(djb2_hash(p, UUID_STR_LEN)) == 1) {
            return; // Дублікат — ACK відправляємо, але команду НЕ виконуємо вдруге
        }

        // 8. Команда валідна та унікальна — передаємо на виконання актуатору
        // (Логіка виконання залежить від конкретного пристрою: клапан, сирена тощо)

    } else if (cmd_decrypt_buf[0] == 0x99) {
        // ── Гілка OTA Downlink: збирання прошивки від Rails у RAM ─────
        // Архітектурний міст: Backend CoAP downlink → pending_ota_bytecode[] → LoRa broadcast
        //
        // Формат дешифрованого пакета:
        //   [0x99][chunk_index:2 BE][total_chunks:2 BE][bytecode:≤512][CRC:2]
        //
        // Після збирання всіх чанків — встановлюємо ota_is_active = 1,
        // і головний цикл автоматично починає LoRa-бродкаст на Солдатів.

        // [MISRA C] Мінімальна довжина: 1 маркер + 2 index + 2 total + 1 байт коду = 6
        if (aligned < 6) return;

        // Витягуємо chunk_index та total_chunks (big-endian)
        uint16_t chunk_index  = ((uint16_t)cmd_decrypt_buf[1] << 8) | cmd_decrypt_buf[2];
        uint16_t total_chunks = ((uint16_t)cmd_decrypt_buf[3] << 8) | cmd_decrypt_buf[4];

        // [MISRA C] Захист від невалідних заголовків
        if (total_chunks == 0) return;

        // Розрахунок довжини чистого байткоду (без заголовка, CRC, AES-padding):
        // aligned — повна довжина розшифрованих даних (вирівняна по AES-блоку).
        // Останній 16-байтний блок може бути padding → гарантована корисна довжина = aligned - 16.
        // Backend пакує до 512 байт коду + 2 байти CRC у чанк.
        // Якщо (aligned - 16) >= 514 (512 payload + 2 CRC) → повний чанк, payload = 512.
        // Інакше → неповний/останній чанк: payload = (aligned - 16) - 5 (header) - 2 (CRC).
        uint16_t payload_len = (aligned - 16 >= 514) ? 512 : (aligned - 16 - 7);

        // [MISRA C] Захист від overflow при малому aligned (underflow на uint16_t)
        if (aligned < 23) return;  // Мінімум: 16 (AES block) + 5 (header) + 2 (CRC) = 23

        // Обчислюємо зсув у RAM-буфері
        uint32_t offset = (uint32_t)chunk_index * 512U;

        // [MISRA C] Перевірка меж буфера: запобігаємо переповненню від зловмисних пакетів
        if (offset + payload_len > sizeof(pending_ota_bytecode)) return;

        // Копіюємо байткод у відповідну позицію RAM-буфера
        memcpy(pending_ota_bytecode + offset, &cmd_decrypt_buf[5], payload_len);

        // Оновлюємо стан збирання
        ota_total_expected_chunks = total_chunks;
        ota_chunks_received++;

        // Відстежуємо максимальний розмір зібраного байткоду
        if (offset + payload_len > pending_ota_size) {
            pending_ota_size = (uint16_t)(offset + payload_len);
        }

        // ── Перевірка завершення збирання: усі чанки отримано? ────────
        // Якщо так — скидаємо лічильники і запускаємо LoRa-бродкаст.
        // Головний цикл (if (ota_is_active)) автоматично почне роздачу
        // чанків Солдатам через "Рефлекторний постріл" після кожного RX.
        if (ota_chunks_received >= ota_total_expected_chunks) {
            ota_chunks_received = 0;
            ota_total_expected_chunks = 0;
            current_ota_chunk_idx = 0;
            ota_is_active = 1;  // 🚀 Запускаємо бродкаст на ліс!
        }
    }
}

// =========================================================================
// ІНІЦІАЛІЗАЦІЯ КРИПТОГРАФІЇ
// =========================================================================
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType = CRYP_DATATYPE_32B;
  // Активовано стандарт Gaia 2.0 (256-бітне шифрування)
  hcryp.Init.KeySize = CRYP_KEYSIZE_256B;
  hcryp.Init.pKey = aes_key;
  // ECB для LoRa-трафіку між Королевою та Солдатами (одиночні 16-байтні блоки).
  // Батч до сервера шифрується CBC динамічно в Flush_Cache_To_Rails,
  // команди від сервера дешифруються CBC динамічно в Handle_CoAP_Command,
  // після чого CRYP відновлюється до ECB.
  hcryp.Init.Algorithm = CRYP_AES_ECB;
  HAL_CRYP_Init(&hcryp);
}

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}
