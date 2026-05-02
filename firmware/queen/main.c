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
// OTA Downlink Constants (CoAP → Queen RAM assembly)
#define OTA_MARKER            0x99   // Маркер OTA-пакета (перший байт)
#define OTA_HEADER_SIZE       5      // [0x99][index:2][total:2]
#define OTA_CRC_SIZE          2      // CRC16-CCITT в кінці чанка
#define OTA_OVERHEAD          (OTA_HEADER_SIZE + OTA_CRC_SIZE)  // 7 байт
#define AES_BLOCK_SIZE        16     // AES-256 block size
#define MAX_OTA_CHUNK_PAYLOAD 512    // Максимальний розмір байткоду в одному CoAP-чанку
#define OTA_FULL_CHUNK_THRESH (MAX_OTA_CHUNK_PAYLOAD + OTA_CRC_SIZE) // 514: поріг повного чанка
#define MIN_OTA_ALIGNED       (AES_BLOCK_SIZE + OTA_OVERHEAD)        // 23: мінімальний aligned

// [FIX: AUDIT MISRA] Іменовані константи замість магічних чисел
#define LORA_RX_INFINITE      0xFFFFFF  // Нескінченний таймаут прийому LoRa
#define FLUSH_INTERVAL_MS     3600000   // Інтервал скидання кешу (1 година)
#define FLUSH_JITTER_MAX_MS   60000    // Максимальний джиттер для десинхронізації (0-60 секунд)
#define RNG_FALLBACK_XOR_MASK 0xA5A5A5A5UL // XOR-маска для fallback-ентропії при відмові HRNG
#define FLUSH_HEADROOM        5         // Кількість вільних слотів до примусового скидання
#define QUEEN_HEALTH_GP_MAX   63        // Максимальне значення growth_points
#define OTA_MAX_CHUNKS        16        // 8192 / 512 = максимальна кількість OTA-чанків

// [PLAN 2.4] Queen UID — read from dedicated Flash region instead of hardcoding.
// This allows unified firmware binary to be flashed on any Queen node.
// At provisioning time, the backend writes the unique UID to this Flash address
// via SWD/JTAG (e.g., ST-Link: `st-flash write uid.bin 0x0803F800`).
// Flash page 127 (last 2KB page on STM32WLE5JC with 256KB Flash).
#define QUEEN_UID_FLASH_ADDR  0x0803F800UL
#define QUEEN_UID_MAX_LEN     32         // Max UID string length including null terminator
#define QUEEN_UID_MAGIC       0x51554944UL // "QUID" — magic marker for provisioned UID

// [PLAN 2.11] Starlink/LTE adaptive timeouts
// Starlink DTC latency: 600–2400 ms (variable). LTE-M: 100–500 ms.
// Fixed 1000 ms is insufficient for Starlink worst case.
#define COAP_BASE_TIMEOUT_MS  2000       // Base timeout for CoAP session setup
#define COAP_SEND_TIMEOUT_MS  5000       // Timeout for data send (includes Starlink worst case)
#define COAP_MAX_RETRIES      3          // [FW.9] Maximum CoAP send retry attempts
#define UART_RX_BUF_SIZE      128        // [FW.9] UART RX buffer for modem response parsing

// [FW.1] Flash-based AES key provisioning — per-device unique key via HKDF.
// Factory Flashing writes device_key to protected Flash sector 0x0803E000
// via SWD (STM32CubeProgrammer). Key is derived from master_key via HKDF-SHA256
// on the backend (HardwareKeyService.derive_device_key).
// See docs/03_05 §3.4а for full protocol design.
#define FLASH_KEY_ADDR            0x0803E000UL  // Protected Flash sector for AES-256 key
#define FLASH_KEY_WORDS           8             // 8 × uint32_t = 32 bytes = 256 bits
#define FLASH_KEY_MAGIC           0x534B4559UL  // "SKEY" — magic marker for provisioned key
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
UART_HandleTypeDef huart1;  // Інтерфейс для модему SIM7070G (LTE-M / Starlink)
SUBGHZ_HandleTypeDef hsubghz;
CRYP_HandleTypeDef hcryp; // Апаратний криптопроцесор AES
RNG_HandleTypeDef hrng;   // Апаратний генератор випадкових чисел (HRNG)
IWDG_HandleTypeDef hiwdg; // [PLAN 2.6] Independent Watchdog для auto-recovery

/* USER CODE BEGIN PV */

// =========================================================================
// === 0. КЛЮЧІ ОХОРОНИ (Trading Post) ===
// =========================================================================
// [FW.1] AES-256 key — завантажується з Protected Flash Sector при boot.
// Factory Flashing записує per-device ключ (HKDF-SHA256) на адресу FLASH_KEY_ADDR
// через SWD. Формат Flash: [FLASH_KEY_MAGIC:4][key[0]:4]...[key[7]:4] = 36 байт.
// Якщо ключ не provisioned — Error_Handler() (пристрій не може працювати без ключа).
// Ініціалізація нулями — значення перезаписується Load_AES_Key() перед MX_CRYP_Init().
uint32_t aes_key[8] = {0};

// Унікальний ідентифікатор цієї Королеви.
// [PLAN 2.4] Replaced hardcoded "QUEEN-001" with Flash-based UID.
// At boot, reads UID from dedicated Flash page (0x0803F800).
// If Flash is not provisioned (magic != "QUID"), falls back to default
// to prevent bricking an unprovisioned device.
// Provisioning: write [magic:4][uid_len:1][uid_string:N] to QUEEN_UID_FLASH_ADDR via SWD.
static char queen_uid[QUEEN_UID_MAX_LEN];

// [PLAN 2.4] Read Queen UID from Flash provisioning region.
// Returns 1 if provisioned UID found, 0 if using fallback.
static uint8_t Read_Queen_UID_From_Flash(void)
{
    const uint32_t* flash_ptr = (const uint32_t*)QUEEN_UID_FLASH_ADDR;

    // Check magic marker. Unprogrammed Flash reads as 0xFFFFFFFF,
    // which won't match QUEEN_UID_MAGIC ("QUID" = 0x51554944).
    if (flash_ptr[0] != QUEEN_UID_MAGIC) {
        // Not provisioned — generate unique fallback from STM32 hardware UID
        // (96-bit unique ID at 0x1FFF7590). Last 4 bytes → 8 hex chars.
        // Each physical MCU gets a distinct ID even without provisioning.
        const uint32_t* hw_uid = (const uint32_t*)0x1FFF7590UL;
        snprintf(queen_uid, QUEEN_UID_MAX_LEN, "UNPROV-%08lX",
                 (unsigned long)hw_uid[2]);
        return 0;
    }

    // Read UID length (byte 4) and string (bytes 5+)
    const uint8_t* byte_ptr = (const uint8_t*)QUEEN_UID_FLASH_ADDR;
    uint8_t uid_len = byte_ptr[4];

    // Validate uid_len is within safe bounds for both the destination buffer
    // and the Flash provisioning region (2KB page = 2048 bytes, header = 5 bytes).
    if (uid_len == 0 || uid_len >= QUEEN_UID_MAX_LEN || (5U + uid_len) > 2048U) {
        const uint32_t* hw_uid = (const uint32_t*)0x1FFF7590UL;
        snprintf(queen_uid, QUEEN_UID_MAX_LEN, "UNPROV-%08lX",
                 (unsigned long)hw_uid[2]);
        return 0;
    }

    memcpy(queen_uid, &byte_ptr[5], uid_len);
    queen_uid[uid_len] = '\0';
    return 1;
}

// =========================================================================
// === 1. ПАМ'ЯТЬ КОРОЛЕВИ (Прийом Даних) ===
// =========================================================================
volatile uint8_t lora_rx_flag = 0;      // Прапорець: 1 - пакет спіймано
// [FIX: AUDIT] volatile — записуються в OnRxDone ISR, читаються в main loop
volatile uint8_t incoming_lora_payload[16]; // Сирий 16-байтний зашифрований пакет
uint8_t decrypted_payload[16];          // Розшифрований пакет від Солдата
volatile int8_t current_rssi = 0;       // Рівень сигналу

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
// [FIX: AUDIT] Бітова карта для захисту від дублікатів OTA-чанків.
// Без неї повторна доставка чанка (ACK loss) збільшує ota_chunks_received
// і може спровокувати передчасну активацію бродкасту з неповними даними.
// 16 біт достатньо для 8192/512 = 16 максимальних чанків.
uint16_t ota_chunk_bitmap = 0;

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_SUBGHZ_Init(void);
static void MX_CRYP_Init(void); // Ініціалізація шифрування
static void MX_IWDG_Init(void); // [PLAN 2.6] Independent Watchdog — auto-recovery from HardFault

/* USER CODE BEGIN PFP */
// Функції-обгортки для роботи з модемом та транзитом
void SIM7070_SendATCommand(char* command, uint32_t delay_ms);
void Process_And_Cache_Data(uint32_t uid, uint8_t* payload, int8_t rssi);
void Flush_Cache_To_Rails(void);
// [СИНХРОНІЗОВАНО з Rails]: Обробка вхідних CoAP-команд від сервера
static uint32_t djb2_hash(const char* str, uint8_t len);
uint8_t Cmd_Dedup_Check(uint32_t hash);
void Handle_CoAP_Command(uint8_t* payload, uint16_t len);
// [FW.1] Завантаження AES-256 ключа з Protected Flash Sector.
static void Load_AES_Key(void);
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
  Load_AES_Key();        // [FW.1] Завантажити per-device ключ з Flash ПЕРЕД ініціалізацією CRYP
  MX_CRYP_Init();        // Вмикаємо апаратний модуль AES (використовує aes_key, вже завантажений)
  MX_IWDG_Init();        // [PLAN 2.6] Watchdog: auto-reset ~26 sec after hang

  /* USER CODE BEGIN 2 */

  // 0. Read unique Queen UID from Flash provisioning region
  // [PLAN 2.4] Must be done before any CoAP communication that uses queen_uid
  Read_Queen_UID_From_Flash();

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

  // [HW.10] Power Saving Mode (PSM) + Extended DRX (eDRX) для NB-IoT/LTE-M.
  // Знижує idle-споживання з ~10 мкА (SIM7000G baseline) до ~3 мкА (SIM7070G PSM)
  // між hourly CoAP flush-циклами. Налаштування узгоджене з 02_05.
  //
  // AT+CPSMS=<mode>,,,<TAU>,<Active-Time>:
  //   mode=1 → enable PSM
  //   TAU="00100001" → 1 hour
  //     Per 3GPP TS 24.008 §10.5.7.4a (T3412 extended timer):
  //     bits 8-6 (MSB) = unit  → 001 = "1 hour"
  //     bits 5-1       = value → 00001 = 1
  //     => 1 × 1 hour = 1 hour TAU (узгоджено з hourly CoAP flush cycle)
  //   Active="00000000" → 0 sec (no active window after RX → одразу в PSM)
  //     Per 3GPP §10.5.7.3 (T3324):
  //     bits 8-6 unit=000 (2s), bits 5-1 value=00000 → 0 × 2s = 0 sec
  SIM7070_SendATCommand("AT+CPSMS=1,,,\"00100001\",\"00000000\"\r\n", 1000);

  // AT+CEDRXS=<mode>,<AcT>,<Requested_eDRX>:
  //   mode=1 → enable eDRX, AcT=5 → LTE Cat M1
  //   eDRX="0010" → 20.48 sec (paging window — короткий для downlink-сприйнятливості)
  SIM7070_SendATCommand("AT+CEDRXS=1,5,\"0010\"\r\n", 1000);

  // 4. Відкриваємо вуха: Королева переходить у режим безперервного слухання
  Radio.Rx(LORA_RX_INFINITE);

  /* USER CODE END 2 */

  uint32_t last_flush_time = HAL_GetTick();

  // [FIX: Thundering Herd] Джиттер для десинхронізації скидання кешу.
  // Після одночасного перезавантаження (blackout) кожна Королева отримує
  // випадкове зміщення (0 — FLUSH_JITTER_MAX_MS), розмазуючи трафік по часу.
  uint32_t current_jitter = 0;
  {
      uint32_t rng_val = 0;
      hrng.Instance = RNG;
      if (HAL_RNG_Init(&hrng) == HAL_OK) {
          if (HAL_RNG_GenerateRandomNumber(&hrng, &rng_val) != HAL_OK) {
              // [PLAN 2.7] Improved fallback: XOR tick with UID hash for less predictable jitter
              uint32_t uid_hash = djb2_hash(queen_uid, strlen(queen_uid));
              rng_val = HAL_GetTick() ^ uid_hash ^ RNG_FALLBACK_XOR_MASK;
          }
          HAL_RNG_DeInit(&hrng);
      } else {
          uint32_t uid_hash = djb2_hash(queen_uid, strlen(queen_uid));
          rng_val = HAL_GetTick() ^ uid_hash ^ RNG_FALLBACK_XOR_MASK;
      }
      current_jitter = rng_val % (FLUSH_JITTER_MAX_MS + 1);
  }

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    // [PLAN 2.6] Kick the watchdog — prevents auto-reset during normal operation.
    // If firmware hangs (e.g., SIM7070G AT blocking), IWDG expires after ~26 sec → NVIC_SystemReset.
    HAL_IWDG_Refresh(&hiwdg);

    // =========================================================================
    // ФАЗА ОЧІКУВАННЯ ТА ОБРОБКИ РАДІОЕФІРУ
    // =========================================================================

    // Якщо апаратне переривання OnRxDone спіймало пакет від Солдата
    if (lora_rx_flag == 1)
    {
        // 1. РОЗШИФРОВУЄМО ПАКЕТ
        // Розшифровуємо 4 слова (16 байт) апаратним модулем
        // (void*) cast strips volatile — safe: lora_rx_flag serializes ISR→main access.
        HAL_CRYP_Decrypt(&hcryp, (uint32_t*)(void*)incoming_lora_payload, 4, (uint32_t*)decrypted_payload, 1000);

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
                // [PLAN 2.5]: Reset OTA broadcast flag after full cycle to prevent infinite loop.
                // Without this, Queen broadcasts OTA chunks forever after first update.
                ota_is_active = 0;
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
        Radio.Rx(LORA_RX_INFINITE);
    }

    // =========================================================================
    // СКИДАННЯ КЕШУ НА СЕРВЕР (GCCS Batching -> UDP/CoAP)
    // =========================================================================
    // Відправляємо пакет даних, якщо кеш заповнений майже повністю (залишилось 5 вільних слотів)
    // АБО пройшло достатньо часу (FLUSH_INTERVAL_MS + джиттер для десинхронізації)
    if (cache_count >= (CACHE_MAX_ENTRIES - FLUSH_HEADROOM) || (HAL_GetTick() - last_flush_time > FLUSH_INTERVAL_MS + current_jitter)) {
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
                queen_health[10] = (cache_count < QUEEN_HEALTH_GP_MAX) ? cache_count : QUEEN_HEALTH_GP_MAX;
                Process_And_Cache_Data(0, queen_health, 0); // RSSI=0 (локальний пакет)
            }
            Flush_Cache_To_Rails();
            last_flush_time = HAL_GetTick(); // Оновлюємо таймер

            // [FIX: Thundering Herd] Перегенеровуємо джиттер після кожного flush,
            // щоб навіть при однаковому стартовому зміщенні
            // наступні цикли не синхронізувались.
            {
                uint32_t rng_val = 0;
                hrng.Instance = RNG;
                if (HAL_RNG_Init(&hrng) == HAL_OK) {
                    if (HAL_RNG_GenerateRandomNumber(&hrng, &rng_val) != HAL_OK) {
                        // [PLAN 2.7] Improved fallback with UID hash
                        uint32_t uid_hash = djb2_hash(queen_uid, strlen(queen_uid));
                        rng_val = HAL_GetTick() ^ uid_hash ^ RNG_FALLBACK_XOR_MASK;
                    }
                    HAL_RNG_DeInit(&hrng);
                } else {
                    uint32_t uid_hash = djb2_hash(queen_uid, strlen(queen_uid));
                    rng_val = HAL_GetTick() ^ uid_hash ^ RNG_FALLBACK_XOR_MASK;
                }
                current_jitter = rng_val % (FLUSH_JITTER_MAX_MS + 1);
            }
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
        // (void*) cast removes volatile qualifier for HAL function — safe because
        // ISR is sole writer and main loop does not read until lora_rx_flag is set.
        memcpy((void*)incoming_lora_payload, payload, 16);
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
// [FIX FW.16]: Безпечне відновлення AES-256-ECB після CBC операцій.
// Після CBC шифрування/дешифрування ОБОВ'ЯЗКОВО повертаємо ECB для LoRa.
// Якщо HAL_CRYP_Init зависне (hardware defect) — RCC reset + retry.
// Якщо і після RCC reset невдача — NVIC_SystemReset (повний перезапуск MCU),
// бо без робочого AES Королева не може дешифрувати пакети від Солдатів.
// =========================================================================
static void Restore_ECB_Mode(void)
{
    hcryp.Init.Algorithm = CRYP_AES_ECB;
    hcryp.Init.pInitVect = NULL;
    if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
        __HAL_RCC_CRYP_FORCE_RESET();
        __HAL_RCC_CRYP_RELEASE_RESET();
        hcryp.Init.Algorithm = CRYP_AES_ECB;
        hcryp.Init.pInitVect = NULL;
        if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
            NVIC_SystemReset();
        }
    }
}

// [FW.9] UART RX buffer for modem response parsing
static uint8_t uart_rx_buf[UART_RX_BUF_SIZE];

// [FW.9] Send AT command and wait for OK/ERROR response instead of blind delay.
// Returns: 1 = OK received, 0 = ERROR or timeout
static uint8_t SIM7070_SendATCommand_WithResponse(const char* command, uint32_t timeout_ms)
{
    memset(uart_rx_buf, 0, UART_RX_BUF_SIZE);
    HAL_UART_Transmit(&huart1, (uint8_t*)command, strlen(command), 1000);

    // Read response with timeout
    HAL_StatusTypeDef status = HAL_UART_Receive(&huart1, uart_rx_buf, UART_RX_BUF_SIZE - 1, timeout_ms);

    // Check for OK in response (even if timeout due to partial read)
    if (status == HAL_OK || status == HAL_TIMEOUT) {
        // Search for "OK" in received data
        for (uint8_t i = 0; i < UART_RX_BUF_SIZE - 1 && uart_rx_buf[i] != '\0'; i++) {
            if (uart_rx_buf[i] == 'O' && uart_rx_buf[i+1] == 'K') return 1;
        }
        // Search for "ERROR"
        for (uint8_t i = 0; i < UART_RX_BUF_SIZE - 5 && uart_rx_buf[i] != '\0'; i++) {
            if (uart_rx_buf[i] == 'E' && uart_rx_buf[i+1] == 'R' &&
                uart_rx_buf[i+2] == 'R' && uart_rx_buf[i+3] == 'O' &&
                uart_rx_buf[i+4] == 'R') return 0;
        }
    }
    return 0; // Timeout without OK
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
            /* [PLAN 2.7] Improved HRNG fallback: combine multiple entropy sources
               to reduce IV predictability when HRNG fails.
               HAL_GetTick() alone is predictable (~1ms resolution).
               XOR with: device UID hash, loop index scaling, and bit-shifted tick
               to create a less predictable fallback IV.
               For i ∈ {0,1,2,3}: tick >> {0,8,16,24} extracts different byte regions. */
            uint32_t tick = HAL_GetTick();
            uint32_t uid_hash = djb2_hash(queen_uid, strlen(queen_uid));
            batch_iv[i] = tick ^ (uid_hash << i) ^ ((uint32_t)i * RNG_FALLBACK_XOR_MASK)
                        ^ (tick >> (8U * i));
        }
    }

    HAL_RNG_DeInit(&hrng);

    // 3. Оновлюємо IV у конфігурації крипто-модуля та переініціалізуємо
    hcryp.Init.pInitVect = batch_iv;
    HAL_CRYP_Init(&hcryp);

    // 4. Шифруємо батч. Довжина в 32-бітних словах = padded_size / 4.
    //    Буфер: IV (16 байт) + зашифровані дані
    // [FIX: AUDIT CRITICAL] Переміщено з стеку в static.
    // 2064 байти на стеку при 64KB RAM — ризик переповнення стеку.
    // STM32 default stack = 1-4KB, а ця функція може бути викликана з глибокого call chain.
    static uint8_t encrypted_batch_buffer[2048 + 16];
    memcpy(encrypted_batch_buffer, batch_iv, 16); // Prepend IV як заголовок пакета
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)binary_batch_buffer, padded_size / 4,
                     (uint32_t*)(encrypted_batch_buffer + 16), 2000);

    uint16_t total_size = 16 + padded_size; // IV (16) + зашифровані дані

    // [PLAN 2.11] CoAP send with adaptive timeouts for Starlink DTC.
    // Starlink worst-case RTT: 600–2400 ms. Original 1000 ms CCOAPNEW + 2000 ms
    // CCOAPSEND timeouts were insufficient → silent data loss.
    // Increased to 2000 ms / 5000 ms to cover worst-case Starlink latency.
    //
    // TODO [PLAN 2.9]: Add retry with exponential backoff once interrupt-driven
    // UART RX is implemented (AT-blind issue 2.3). Without UART response parsing
    // we cannot detect send failure, so retry logic would be dead code.

    // [FW.9] CoAP send with retry logic — parse modem response instead of blind delay
    uint8_t send_success = 0;
    for (uint8_t retry = 0; retry < COAP_MAX_RETRIES && !send_success; retry++) {
        // Refresh watchdog before each attempt
        HAL_IWDG_Refresh(&hiwdg);

        // Open CoAP session
        if (!SIM7070_SendATCommand_WithResponse("AT+CCOAPNEW=\"coap://api.silkennet.com:5683\"\r\n",
                                                 COAP_BASE_TIMEOUT_MS)) {
            continue; // Session open failed, retry
        }

        // Build and send hex-encoded batch
        snprintf(at_tx_buffer, sizeof(at_tx_buffer),
                 "AT+CCOAPSEND=0,2,\"telemetry/batch/%s\",%d,\"",
                 queen_uid, total_size * 2);
        HAL_UART_Transmit(&huart1, (uint8_t*)at_tx_buffer, strlen(at_tx_buffer), 100);

        char hex_byte[3];
        for (int i = 0; i < total_size; i++) {
            snprintf(hex_byte, sizeof(hex_byte), "%02x", encrypted_batch_buffer[i]);
            HAL_UART_Transmit(&huart1, (uint8_t*)hex_byte, 2, 10);
        }
        HAL_UART_Transmit(&huart1, (uint8_t*)"\"\r\n", 3, 100);

        // Wait for modem send confirmation with response parsing
        HAL_IWDG_Refresh(&hiwdg);

        // Read modem response instead of blind HAL_Delay
        memset(uart_rx_buf, 0, UART_RX_BUF_SIZE);
        HAL_StatusTypeDef rx_status = HAL_UART_Receive(&huart1, uart_rx_buf, UART_RX_BUF_SIZE - 1, COAP_SEND_TIMEOUT_MS);

        if (rx_status == HAL_OK || rx_status == HAL_TIMEOUT) {
            for (uint8_t j = 0; j < UART_RX_BUF_SIZE - 1 && uart_rx_buf[j] != '\0'; j++) {
                if (uart_rx_buf[j] == 'O' && uart_rx_buf[j+1] == 'K') {
                    send_success = 1;
                    break;
                }
            }
        }

        HAL_IWDG_Refresh(&hiwdg);

        // Close CoAP session
        SIM7070_SendATCommand("AT+CCOAPDEL=0\r\n", 500);
    }

    // [FIX FW.16: ECB Restoration with error recovery]
    // Flush_Cache_To_Rails() переключає CRYP на CBC для шифрування батча.
    // Якщо не повернути ECB, всі наступні HAL_CRYP_Decrypt() для LoRa-пакетів
    // від Солдатів будуть використовувати CBC замість ECB → сміття → втрата даних.
    Restore_ECB_Mode();
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
        // [FIX FW.16] Відновлюємо ECB перед виходом (з error recovery)
        Restore_ECB_Mode();
        return;
    }
    HAL_CRYP_Decrypt(&hcryp, (uint32_t*)(payload + 16), aligned / 4,
                     (uint32_t*)cmd_decrypt_buf, 2000);

    // 4. [FIX FW.16] Відновлюємо ECB для LoRa-трафіку (з error recovery)
    Restore_ECB_Mode();

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

    } else if (cmd_decrypt_buf[0] == OTA_MARKER) {
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

        // [FIX: AUDIT] Захист від chunk_index >= OTA_MAX_CHUNKS (переповнення bitmap)
        if (chunk_index >= OTA_MAX_CHUNKS) return;

        // [MISRA C] Захист від overflow при малому aligned (underflow на uint16_t)
        // MIN_OTA_ALIGNED = AES_BLOCK_SIZE (16) + OTA_HEADER_SIZE (5) + OTA_CRC_SIZE (2) = 23
        if (aligned < MIN_OTA_ALIGNED) return;

        // Розрахунок довжини чистого байткоду (без заголовка, CRC, AES-padding):
        // aligned — повна довжина розшифрованих даних (вирівняна по AES-блоку).
        // Останній AES-блок може бути padding → гарантована корисна довжина = aligned - AES_BLOCK_SIZE.
        // Backend пакує до MAX_OTA_CHUNK_PAYLOAD байт коду + OTA_CRC_SIZE у чанк.
        // Якщо guaranteed >= OTA_FULL_CHUNK_THRESH → повний чанк, payload = MAX_OTA_CHUNK_PAYLOAD.
        // Інакше → неповний/останній чанк: payload = guaranteed - OTA_OVERHEAD.
        uint16_t guaranteed = aligned - AES_BLOCK_SIZE;
        uint16_t payload_len = (guaranteed >= OTA_FULL_CHUNK_THRESH)
                             ? MAX_OTA_CHUNK_PAYLOAD
                             : (guaranteed - OTA_OVERHEAD);

        // Обчислюємо зсув у RAM-буфері
        uint32_t offset = (uint32_t)chunk_index * (uint32_t)MAX_OTA_CHUNK_PAYLOAD;

        // [MISRA C] Перевірка меж буфера: запобігаємо переповненню від зловмисних пакетів
        if (offset + payload_len > sizeof(pending_ota_bytecode)) return;

        // [FIX: AUDIT CRITICAL] Дедуплікація OTA-чанків.
        // Без цієї перевірки повторна доставка чанка (ACK loss + retransmit)
        // збільшує ota_chunks_received і може спровокувати передчасну активацію
        // бродкасту з неповними даними → "вічний ребут" Солдатів.
        uint16_t chunk_bit = (uint16_t)(1U << chunk_index);
        if (ota_chunk_bitmap & chunk_bit) {
            // Дублікат — дані вже є в RAM, просто ігноруємо
            return;
        }

        // Копіюємо байткод у відповідну позицію RAM-буфера
        memcpy(pending_ota_bytecode + offset, &cmd_decrypt_buf[OTA_HEADER_SIZE], payload_len);

        // Оновлюємо стан збирання
        ota_total_expected_chunks = total_chunks;
        ota_chunk_bitmap |= chunk_bit;  // Маркуємо чанк як отриманий
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
            ota_chunk_bitmap = 0;
            current_ota_chunk_idx = 0;
            ota_is_active = 1;  // 🚀 Запускаємо бродкаст на ліс!
        }
    }
}

// =========================================================================
// [FW.1] ЗАВАНТАЖЕННЯ AES-256 КЛЮЧА З PROTECTED FLASH SECTOR
// =========================================================================
// Формат Flash-регіону на FLASH_KEY_ADDR (0x0803E000):
//   [0] FLASH_KEY_MAGIC (0x534B4559 = "SKEY") — маркер provisioned ключа
//   [1..8] aes_key[0..7] — 8 × uint32_t = 256 bits AES-256 key
//
// Якщо magic відсутній або ключ нульовий — пристрій не provisioned,
// Error_Handler() викликає software reset. Пристрій не може працювати
// без валідного ключа (BLOCKER-1 mitigation).
//
// Записується при Factory Flashing через SWD:
//   STM32CubeProgrammer --write key_payload.bin 0x0803E000
// Ключ деривується на backend: HKDF-SHA256(master_key, device_uid, "silkennet-v1-aes256")
// Див. docs/03_05 §3.4а для повного протоколу.
static void Load_AES_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_KEY_ADDR;

    // 1. Перевірка magic marker — чи ключ записаний при provisioning
    if (flash_ptr[0] != FLASH_KEY_MAGIC) {
        // Flash не provisioned (0xFFFFFFFF або стертий).
        // Пристрій не може шифрувати/дешифрувати без ключа.
        Error_Handler();
        return;  // unreachable (Error_Handler resets), але для static analysis
    }

    // 2. Перевірка що ключ не нульовий (magic є, але ключ порожній — corrupted provisioning)
    uint32_t key_or = 0;
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        key_or |= flash_ptr[1 + i];
    }
    if (key_or == 0) {
        // Magic записано, але ключ = 0x00...00 — невалідний стан
        Error_Handler();
        return;
    }

    // 3. Копіюємо ключ з Flash у RAM (aes_key використовується MX_CRYP_Init)
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        aes_key[i] = flash_ptr[1 + i];
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

// =========================================================================
// [PLAN 2.6] INDEPENDENT WATCHDOG (IWDG) — AUTO-RECOVERY FROM HANG
// =========================================================================
// Without IWDG, Queen hangs forever on HardFault or SIM7070G AT-command blocking.
// Soldier already has IWDG (~26 sec recovery). This brings Queen to parity.
// Timeout formula: (Reload × Prescaler) / LSI_freq = (3328 × 256) / 32000 ≈ 26.6 seconds.
static void MX_IWDG_Init(void)
{
  hiwdg.Instance = IWDG;
  hiwdg.Init.Prescaler = IWDG_PRESCALER_256;  // LSI 32 kHz / 256 = 125 Hz tick
  hiwdg.Init.Window = IWDG_WINDOW_DISABLE;
  hiwdg.Init.Reload = 3328;                    // 3328 / 125 ≈ 26.6 sec timeout
  if (HAL_IWDG_Init(&hiwdg) != HAL_OK) {
    Error_Handler();
  }
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
