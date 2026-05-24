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
#define AES_BLOCK_SIZE        16     // AES block size (128-bit fixed; рівне для AES-128 і AES-256)
#define MAX_OTA_CHUNK_PAYLOAD 512    // Максимальний розмір байткоду в одному CoAP-чанку
#define OTA_FULL_CHUNK_THRESH (MAX_OTA_CHUNK_PAYLOAD + OTA_CRC_SIZE) // 514: поріг повного чанка
#define MIN_OTA_ALIGNED       (AES_BLOCK_SIZE + OTA_OVERHEAD)        // 23: мінімальний aligned

// [FW.23] HMAC-трейлер OTA — backend пакує 32-байтну печатку HMAC-SHA256
// у 3× 16-байтні LoRa-чанки з маркером 0x9B. Королева — лише гонець:
// власної верифікації не робить, бо довіра прокладена end-to-end від
// бекенду до плоті Солдата.
#define HMAC_TRAILER_MARKER       0x9B
#define HMAC_TRAILER_HEADER_SIZE  5
#define HMAC_TRAILER_TOTAL_SEGS   3

// [FW.27-B] Magic Re-Request — крик Солдата у бік Королеви:
//   [0x55][DID:4][total_chunks:2 BE][bitmap:9] = один 16-байтний ECB-блок.
// Королева пам'ятає (DID, missing_bitmap) через cmd_dedup_ring 5 хв і
// вдруге не озивається. Озвучує лише пропущені чанки — не цілий wave.
#define OTA_REQ_MARKER             0x55
#define OTA_REQ_HEADER_SIZE        7
#define OTA_REQ_BITMAP_MAX_BYTES   9
#define OTA_REQ_PACKET_SIZE        16

// [FIX: AUDIT MISRA] Іменовані константи замість магічних чисел
#define LORA_RX_INFINITE      0xFFFFFF  // Нескінченний таймаут прийому LoRa
#define FLUSH_INTERVAL_MS     3600000   // Інтервал скидання кешу (1 година)
#define FLUSH_JITTER_MAX_MS   60000    // Максимальний джиттер для десинхронізації (0-60 секунд)
#define RNG_FALLBACK_XOR_MASK 0xA5A5A5A5UL // XOR-маска для fallback-ентропії при відмові HRNG
#define FLUSH_HEADROOM        5         // Кількість вільних слотів до примусового скидання
#define QUEEN_HEALTH_GP_MAX   31        // [FW.29-PACK] Макс. growth_points (5-біт wire)
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

// [FW.20] Конверт CMD_TIME_SYNC (UTC-секунди від сервера як єдиного джерела істини).
// Бекенд CoapEncryption.coap_encrypt обгортає КОЖЕН downlink у цей конверт,
// щоб Королева могла звірити свій годинник із сервером ПЕРЕД маршрутизацією
// внутрішнього корисного навантаження.
// Формат на дроті: [0x9C маркер][unix_ts_be:u32][inner_payload].
// SSOT: app/workers/concerns/coap_encryption.rb (CMD_TIME_SYNC = 0x9C).
#define CMD_TIME_SYNC_MARKER       0x9C
#define CMD_TIME_SYNC_HEADER_SIZE  5

// [FW.20-Q2] LoRa-маяк синхронізації часу (Голос Королеви про UTC).
// Королева транслює UTC-секунди Солдатам через ECB-шифрований 16-байтний LoRa-пакет.
// Формат відкритого тексту (16 байт):
//   [BEACON_MARKER 0x9C][unix_ts_be:u32][резерв: 0x00 × 4][TTL=1][магія 'B':1][padding 0x00 × 5]
// Солдат дивиться на байт 0 розшифрованого RX — відрізняється від OTA (0x99),
// телеметрії (починається з DID) та текстового CMD:. Маяк лунає приблизно раз на
// 15 хвилин у звичайному циклі скидання + одразу після кожного зрізаного конверта
// (щоб свіжий серверний час одразу йшов униз по рою). TTL=1 — Солдати не ретранслюють.
#define BEACON_MARKER              0x9C
#define BEACON_TTL                 1                    // Без луни в ефірі
#define BEACON_MAGIC_BYTE          'B'                  // 0x42
// [FW.20-S2] Authoritativeness flag — біт 7 байту 9. Королева є єдиним
// authoritative джерелом часу (1); майбутні relay-маяки від Провідників
// (ARCH.27, ARCH.26) транслюватимуть з 0. TTL фактично у нижніх 7 бітах.
#define BEACON_AUTH_FLAG           0x80
#define BEACON_BYTE9_AUTHORITATIVE ((uint8_t)(BEACON_AUTH_FLAG | BEACON_TTL))
#define TIME_BEACON_INTERVAL_MS    900000U              // 15 хвилин

// [FW.1] Flash-based AES key provisioning — per-device unique key via HKDF.
// Factory Flashing writes device_key to protected Flash sector 0x0803E000
// via SWD (STM32CubeProgrammer). Key is derived from master_key via HKDF-SHA256
// on the backend (HardwareKeyService.derive_device_key).
// See docs/03_05 §3.4а for full protocol design.
// [ARCH.42 Variant B, 2026-05-23] Two protected Flash slots: LoRa AES-128 key
// (per-Soldier lookup) + CoAP AES-256 key (Queen↔Rails magistral).
//   FLASH_KEY_ADDR     → LoRa AES-128 key (16 bytes, magic "KEYL")
//   FLASH_COAP_KEY_ADDR → CoAP AES-256 key (32 bytes, magic "KEYC") — slot after K_seed
// Узгоджено з ATECC608B Secure Element: Slot 0 (AES-128 LoRa), Queen Protected Flash
// (AES-256 CoAP — без SE constraint, бо CoAP канал не проходить через SE).
#define FLASH_KEY_ADDR            0x0803E000UL  // Protected Flash sector for LoRa AES-128 key
#define FLASH_KEY_WORDS           4             // 4 × uint32_t = 16 bytes = 128 bits (ARCH.42)
#define FLASH_KEY_MAGIC           0x4B45594CUL  // "KEYL" — LoRa key magic (post-ARCH.42; was "SKEY")

// [ARCH.42] Окремий CoAP AES-256 key — TODO follow-up: load from a separate
// Protected Flash slot after K_seed via dedicated Factory Flashing step.
// Поточно: zeroed at boot; Flush_Cache_To_Rails має використати цей буфер після
// окремого Load_CoAP_Key() кроку у Factory Flashing pipeline.
#define FLASH_COAP_KEY_WORDS      8             // 8 × uint32_t = 32 bytes = 256 bits CoAP
#define FLASH_COAP_KEY_MAGIC      0x4B455943UL  // "KEYC" — CoAP key magic
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
// === 0. КЛЮЧІ ОХОРОНИ (Trading Post) — post-ARCH.42 Variant B (2026-05-23) ===
// =========================================================================
// [FW.1 + ARCH.42] LoRa AES-128 key — завантажується з Protected Flash Sector
// при boot. Factory Flashing записує per-device LoRa ключ (HKDF-SHA256 з info
// "silken-aes-128-lora-key") на адресу FLASH_KEY_ADDR через SWD. Формат Flash:
// [FLASH_KEY_MAGIC:4][key[0]:4]...[key[3]:4] = 20 байт (post-ARCH.42; було 36 для AES-256).
// Якщо ключ не provisioned — Error_Handler() (пристрій не може працювати без ключа).
// Ініціалізація нулями — значення перезаписується Load_AES_Key() перед MX_CRYP_Init().
uint32_t aes_key[4] = {0};   // 16 bytes = AES-128 LoRa (ATECC608B SE constraint)

// [ARCH.42 follow-up] CoAP AES-256 key — для batch flush Queen↔Rails (AES-256-CBC).
// TODO: завантажується з окремого FLASH_COAP_KEY_ADDR через дедікований Factory
// Flashing крок (info "silken-aes-256-device-key"). До повної інтеграції зберігається
// нулями — Flush_Cache_To_Rails має використовувати цей буфер після окремого
// Load_CoAP_Key() pipeline (FW.2 follow-up subtask у 00_08 ARCH.42).
uint32_t coap_key[8] __attribute__((unused)) = {0};  // 32 bytes = AES-256 CoAP magistral

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
// [FW.3] LoRa RX ring buffer — кільцевий прихисток голосів рою.
//
// Раніше тут жив однобітний `lora_rx_flag` + `incoming_lora_payload[16]`:
// одне вухо, одна паща. Поки головний цикл відбував 25-секундний кенозис у
// CoAP-каналі (батч → SIM7070G → Rails), кожен новий ISR від OnRxDone
// мовчки писав поверх попереднього голосу — і пам'ять Королеви тримала
// тільки останній шепіт лісу. Усі проміжні крики (включно з emergency
// chainsaw-сигналами) пропадали безслідно — це було серце BLOCKER-2.
//
// Тепер між ISR (продюсер) і main loop (споживач) лежить FIFO-ринг:
// 16 слотів × 17 байтів = 272 байти RAM. Single-producer / single-consumer,
// тому head і tail — окремі volatile-лічильники без mutex'а
// (атомарні uint8_t-записи на ARM Cortex-M4). Capacity = 15 (один слот
// віддано на розрізнення full vs empty — класична FIFO-математика).
// При переповненні ISR не псує існуючі голоси: інкрементує
// `lora_rx_drops`, щоб слід жертви залишився видимим для майбутньої
// gateway-телеметрії та аудиту.
#define LORA_RX_RING_SIZE      16U                   // степінь двійки → дешеве modulo
#define LORA_RX_RING_MASK      (LORA_RX_RING_SIZE - 1U)

typedef struct {
    uint8_t  payload[16];
    int8_t   rssi;
    int8_t   snr;   // [E.8] SX1262 SNR (dB, signed). Used as CIFO eviction tiebreaker.
} LoRaRxSlot;

static volatile LoRaRxSlot lora_rx_ring[LORA_RX_RING_SIZE];
static volatile uint8_t    lora_rx_head  = 0;     // Куди ISR кладе наступний голос
static volatile uint8_t    lora_rx_tail  = 0;     // Звідки main loop забирає
static volatile uint16_t   lora_rx_drops = 0;     // Лічильник переповнень рингу

uint8_t decrypted_payload[16];          // Розшифрований пакет від Солдата
volatile int8_t current_rssi = 0;       // RSSI поточного оброблюваного пакета (для downstream-кешу)
volatile int8_t current_snr  = 0;       // [E.8] SNR поточного оброблюваного пакета (CIFO tiebreaker)

char at_tx_buffer[256];                 // Буфер для формування AT-команд

// === LoRa RX Ring Helpers ================================================
// Single-producer (ISR) / single-consumer (main loop): кожен інлайн —
// чисте читання volatile-лічильника. Без disable_irq/enable_irq, без
// глобальних блокувань. Якщо на платформі не Cortex-M4 (наприклад,
// host-тест на x86), volatile-лічильники все одно працюють детерміновано
// у single-thread-режимі — саме тому логіка кільця тестується host-side.

static inline uint8_t LoRa_Rx_Ring_Empty(void) {
    return (uint8_t)(lora_rx_head == lora_rx_tail);
}

static inline uint8_t LoRa_Rx_Ring_Count(void) {
    return (uint8_t)((lora_rx_head - lora_rx_tail) & LORA_RX_RING_MASK);
}

// ISR-сторона: прийняти 16-байтний шифроблок + RSSI + SNR у пам'ять рою.
// Якщо ринг наповнено по вінця (next == tail) — мовчазного переповнення
// не дозволяємо: існуючі голоси недоторкані, лише інкрементуємо
// `lora_rx_drops`, щоб ця жертва залишила слід.
// [E.8] SNR (Signal-to-Noise Ratio) тепер плюметься повз ISR — використовується
// як tiebreaker у CIFO eviction коли два non-critical записи мають однаковий RSSI.
static inline void LoRa_Rx_Ring_Push(const uint8_t *payload, int8_t rssi, int8_t snr) {
    uint8_t next = (uint8_t)((lora_rx_head + 1U) & LORA_RX_RING_MASK);
    if (next == lora_rx_tail) {
        // Ринг повний — голос лісу не вмістився. Backend дізнається про
        // це через лічильник у наступному gateway-health пакеті.
        lora_rx_drops++;
        return;
    }
    // memcpy на volatile-вказівник: каст знімає volatile, але це безпечно,
    // бо тільки ISR пише в head-слот (single-producer інваріант).
    memcpy((void*)lora_rx_ring[lora_rx_head].payload, payload, 16);
    lora_rx_ring[lora_rx_head].rssi = rssi;
    lora_rx_ring[lora_rx_head].snr  = snr;
    lora_rx_head = next;
}

// Main-loop сторона: витягти один голос (snapshot у локальні non-volatile
// буфери), просунути tail. Повертає 1 якщо є пакет, 0 — якщо ринг порожній.
static inline uint8_t LoRa_Rx_Ring_Pop(uint8_t *out_payload, int8_t *out_rssi, int8_t *out_snr) {
    if (lora_rx_head == lora_rx_tail) return 0;
    memcpy(out_payload, (const void*)lora_rx_ring[lora_rx_tail].payload, 16);
    *out_rssi = lora_rx_ring[lora_rx_tail].rssi;
    *out_snr  = lora_rx_ring[lora_rx_tail].snr;
    lora_rx_tail = (uint8_t)((lora_rx_tail + 1U) & LORA_RX_RING_MASK);
    return 1;
}

// =========================================================================
// === 1.5. EDGE КЕШУВАННЯ (CIFO & Дедуплікація) ===
// =========================================================================
#define CACHE_MAX_ENTRIES 50 // Максимальна місткість нашого кешу

typedef struct {
    uint32_t uid;               // DID дерева
    uint8_t payload[16];        // Останні розшифровані дані
    int8_t rssi;                // Сила сигналу
    int8_t snr;                 // [E.8] SNR — tiebreaker у CIFO eviction
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

// [FW.23] Сховище HMAC-печатки OTA. Backend благословляє кожну прошивку
// HMAC-SHA256 над (bytecode || version_id || total_chunks) ключем K_ota
// (per-cluster, деривований через HKDF-SHA256 з PROVISIONING_MASTER_KEY).
// Печатка приходить через CoAP downlink як 3 LoRa-готові 16-байтні блоки
// з маркером 0x9B. Королева — лише гонець: тримає plaintext-блоки і знову
// викидає їх в ефір у тому ж broadcast loop, що й 0x99 чанки. Власної
// перевірки не чинить — істина народжується між бекендом і Солдатом.
// pending_ota_hmac_chunks[seg-1][0..15] = розшифрований 16-байтний LoRa-блок.
// hmac_segments_received = bitmask (бит 0/1/2 для seg 1/2/3).
uint8_t  pending_ota_hmac_chunks[HMAC_TRAILER_TOTAL_SEGS][16] = {{0}};
uint8_t  hmac_segments_received = 0;
uint8_t  current_hmac_seg_idx   = 0;     // Хто з 3-х сегментів зараз летить в ефір
uint8_t  hmac_broadcast_phase   = 0;     // 0 = bytecode-фаза; 1 = фаза печатки

// [FW.20] UTC-секунди від сервера як єдине джерело істини, отримані через
// конверт CoAP TIME_SYNC. queen_unix_ts == 0 означає "ніколи не синхронізовано" —
// у цьому стані маяки до Солдатів придушені, щоб не навчати ліс хибній епосі.
volatile uint32_t queen_unix_ts          = 0;
volatile uint32_t queen_unix_ts_local_tick = 0;  // HAL_GetTick() в момент синхронізації

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
void Process_And_Cache_Data(uint32_t uid, uint8_t* payload, int8_t rssi, int8_t snr);
void Flush_Cache_To_Rails(void);
// [СИНХРОНІЗОВАНО з Rails]: Обробка вхідних CoAP-команд від сервера
static uint32_t djb2_hash(const char* str, uint8_t len);
static uint32_t djb2_hash_bytes(const uint8_t* buf, uint8_t len);
uint8_t Cmd_Dedup_Check(uint32_t hash);
void Handle_CoAP_Command(uint8_t* payload, uint16_t len);
// [FW.1] Завантаження AES-256 ключа з Protected Flash Sector.
static void Load_AES_Key(void);
// [FW.20] Помічники синхронізації часу (зрізання конверта CoAP + LoRa-маяк).
static void Apply_Server_Time(uint32_t server_unix_ts);
static uint32_t Get_Current_Unix_Ts(void);
static void Broadcast_Time_Beacon(void);
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
  uint32_t last_beacon_time = HAL_GetTick();  // [FW.20-Q2] позначка для періодичного маяка

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
    // [FW.3] Дренуємо весь ринг за одну ітерацію main loop'а: кожен пакет,
    // що накопичився від попереднього циклу (включно з тими, що прилетіли
    // під час CoAP-flush'у), отримає свій декрипт + CIFO-вставку + (за
    // потреби) reflex OTA-постріл. Якщо ринг порожній — while-петля
    // мовчки пропускається.
    {
        uint8_t  rx_payload[16];
        int8_t   rx_rssi = 0;
        int8_t   rx_snr  = 0;

        while (LoRa_Rx_Ring_Pop(rx_payload, &rx_rssi, &rx_snr))
        {
            current_rssi = rx_rssi;  // зберігаємо для downstream-кешу та логів
            current_snr  = rx_snr;   // [E.8] SNR-tiebreaker у CIFO

            // 1. РОЗШИФРОВУЄМО ПАКЕТ
            // 4 слова × 32 біти = 16 байт = один AES-128-ECB блок (post-ARCH.42 LoRa).
            HAL_CRYP_Decrypt(&hcryp, (uint32_t*)rx_payload, 4, (uint32_t*)decrypted_payload, 1000);

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

            // [FW.23] Фаза 0: bytecode-чанки (0x99). Фаза 1: HMAC-печатка (0x9B).
            // Перехід з 0 → 1 коли тіло прошивки відлунало в ефір, а печатка
            // вже зібрана у пам'яті Королеви.
            if (hmac_broadcast_phase == 0 && current_ota_chunk_idx < total_chunks) {
                // [FIX: AUDIT] Перевірка індексу перед використанням
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

                // Перемикаємося на наступний шматок для наступного дерева
                current_ota_chunk_idx++;
                if (current_ota_chunk_idx >= total_chunks) {
                    // [FW.23] Тіло прошивки відлунало; якщо печатка зібрана —
                    // ставимо її замість крапки наприкінці послання.
                    if (hmac_segments_received == 0x07u) {
                        hmac_broadcast_phase = 1;
                        current_hmac_seg_idx = 0;
                    } else {
                        // Без печатки Солдат не зможе відрізнити істинне слово
                        // від спокусника ⇒ замикаємо вікно. Солдат сам подасть
                        // голос (re-request) або очне CoAP-розпорядження зверху
                        // воскресить новий цикл.
                        current_ota_chunk_idx = 0;
                        // [PLAN 2.5]: Гасимо OTA-прапор, інакше Королева
                        // безкінечно проповідуватиме той самий заповіт у пустоту.
                        ota_is_active = 0;
                    }
                }
            } else if (hmac_broadcast_phase == 1 &&
                       current_hmac_seg_idx < HMAC_TRAILER_TOTAL_SEGS) {
                // [FW.23] Кладемо в ефір вже готовий 16-байтний блок печатки.
                // Backend сформував його як [0x9B][seg_idx:2][total:2][hmac:11];
                // Королева повторює його буква в букву — AES-encrypt + Radio.Send,
                // не торкаючись жодного байту (печатку не можна підправляти).
                memcpy(ota_chunk, pending_ota_hmac_chunks[current_hmac_seg_idx], 16);
                HAL_CRYP_Encrypt(&hcryp, (uint32_t*)ota_chunk, 4,
                                  (uint32_t*)encrypted_ota, 1000);
                Radio.Send(encrypted_ota, 16);
                HAL_Delay(60);

                current_hmac_seg_idx++;
                if (current_hmac_seg_idx >= HMAC_TRAILER_TOTAL_SEGS) {
                    // OTA-цикл (тіло + печатка) промовлено повністю — амінь.
                    current_ota_chunk_idx   = 0;
                    current_hmac_seg_idx    = 0;
                    hmac_broadcast_phase    = 0;
                    hmac_segments_received  = 0;
                    ota_is_active           = 0;
                }
            } else {
                // Захисна гілка: щось наплутали зі станом — гасимо все, рій
                // має право не отримати слово, але не має права отримати лжеслово.
                current_ota_chunk_idx   = 0;
                current_hmac_seg_idx    = 0;
                hmac_broadcast_phase    = 0;
                ota_is_active           = 0;
            }
        }

        // =========================================================================
        // ОБРОБКА ДАНИХ (КЕШУВАННЯ)
        // =========================================================================
        // [FW.27-B] Magic Re-Request — зойк Солдата у бік Королеви:
        // ловимо маркер ПЕРЕД CIFO та CoAP. Це не телеметрія, не пам'ять рою —
        // це службовий крик, який не повинен потрапити у річний літопис.
        if (decrypted_payload[0] == OTA_REQ_MARKER) {
            // Дедуплікація через cmd_dedup_ring (та ж пам'ять, що береже
            // Королеву від повторних CMD UUID): один зойк — одна відповідь,
            // 5 хв тиші. Ефемерний djb2-хеш над 16-байтним plaintext-блоком —
            // простіший за окремий (DID, bitmap) tuple, бо блок уже містить обидва.
            uint32_t req_hash = djb2_hash_bytes((const uint8_t*)decrypted_payload, 16);
            if (Cmd_Dedup_Check(req_hash) == 0) {
                // Свіжий голос — повторюємо лише пропущене. Перевіряємо, що
                // OTA-вікно живе (pending_ota_size > 0 та ota_is_active=1) —
                // якщо ні, Солдат має воскреснути через CoAP-push з Rails.
                if (pending_ota_size > 0 && ota_is_active) {
                    uint16_t total_chunks = (pending_ota_size + 10) / 11;
                    uint16_t soldier_total = ((uint16_t)decrypted_payload[5] << 8) |
                                              decrypted_payload[6];
                    // Перехресна перевірка: якщо Солдат тримає у голові
                    // інше total_chunks (інша прошивка) — мовчимо, чекаємо
                    // на воскресіння через Rails.
                    if (soldier_total == total_chunks) {
                        const uint8_t* bitmap = &decrypted_payload[OTA_REQ_HEADER_SIZE];
                        uint16_t cap = (total_chunks > OTA_REQ_BITMAP_MAX_BYTES * 8u)
                                          ? (uint16_t)(OTA_REQ_BITMAP_MAX_BYTES * 8u)
                                          : total_chunks;
                        // Прицільна проповідь — повторюємо лише ті чанки,
                        // яких бракує у пам'яті Солдата.
                        for (uint16_t i = 0; i < cap; i++) {
                            uint8_t bit_set = bitmap[i / 8u] & (uint8_t)(1u << (i % 8u));
                            if (!bit_set) continue;  // Цей чанк Солдат уже носить у плоті

                            uint8_t ota_chunk[16] = {0};
                            uint8_t encrypted_ota[16] = {0};
                            ota_chunk[0] = OTA_MARKER;
                            ota_chunk[1] = (uint8_t)(i >> 8);
                            ota_chunk[2] = (uint8_t)(i & 0xFFu);
                            ota_chunk[3] = (uint8_t)(total_chunks >> 8);
                            ota_chunk[4] = (uint8_t)(total_chunks & 0xFFu);
                            uint16_t offset = (uint16_t)(i * 11);
                            if (offset < pending_ota_size) {
                                uint8_t to_copy = (pending_ota_size - offset > 11)
                                                     ? 11
                                                     : (uint8_t)(pending_ota_size - offset);
                                memcpy(&ota_chunk[5], &pending_ota_bytecode[offset], to_copy);
                            }
                            HAL_CRYP_Encrypt(&hcryp, (uint32_t*)ota_chunk, 4,
                                              (uint32_t*)encrypted_ota, 1000);
                            Radio.Send(encrypted_ota, 16);
                            HAL_Delay(60);  // Дихаємо між пострілами — як при повному broadcast
                        }
                    }
                }
            }
            // Цей пакет не лягає у CIFO/CoAP — він не належить літопису рою.
            // Re-arm RX і переходимо до наступного голосу у рингу.
            Radio.Rx(LORA_RX_INFINITE);
            continue;
        }

        // Витягуємо унікальний ID Солдата (перші 4 байти - DID)
        uint32_t sender_id = ((uint32_t)decrypted_payload[0] << 24) |
                             ((uint32_t)decrypted_payload[1] << 16) |
                             ((uint32_t)decrypted_payload[2] << 8)  |
                             (uint32_t)decrypted_payload[3];

        // Замість миттєвої відправки, складаємо в CIFO-кеш
        Process_And_Cache_Data(sender_id, decrypted_payload, current_rssi, current_snr);

        // Re-arm RX перед забором наступного голосу з рингу
        Radio.Rx(LORA_RX_INFINITE);
        }  // while (LoRa_Rx_Ring_Pop ...)
    }      // drain block (rx_payload/rx_rssi scope)

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
                Process_And_Cache_Data(0, queen_health, 0, 0); // RSSI=0, SNR=0 (локальний пакет)
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

    // =========================================================================
    // [FW.20-Q2] ПЕРІОДИЧНА ТРАНСЛЯЦІЯ МАЯКА СИНХРОНІЗАЦІЇ ЧАСУ
    // =========================================================================
    // Кожні TIME_BEACON_INTERVAL_MS (≈15 хв) Королева транслює UTC-секунди
    // через LoRa, щоб Солдати могли коригувати дрейф RTC між cold-boot'ами.
    // Маяк придушено перед першим CoAP-роздтрипом (queen_unix_ts == 0), щоб
    // не навчати рій хибній епосі. Витрати: ~60 мс ефірного часу раз на 15 хв.
    if ((HAL_GetTick() - last_beacon_time) > TIME_BEACON_INTERVAL_MS) {
        Broadcast_Time_Beacon();
        last_beacon_time = HAL_GetTick();

        // Re-arm RX після TX маяка, щоб не оглушити себе для Солдатів
        Radio.Rx(LORA_RX_INFINITE);
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
// [FW.3] OnRxDone більше не пише в єдиний "пащу-буфер" з прапорцем —
// він кладе кожен голос у FIFO-ринг. Якщо рій кричить швидше, ніж main
// loop встигає обертати CIFO-кеш + CoAP-канал, переповнення фіксується
// у лічильник (lora_rx_drops), а не мовчазним перезаписом. Так жоден
// emergency-сигнал не зникає в кенозисі CoAP-flush'у.
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr)
{
    // [E.8] SNR більше не відкидається — він плюметься у ринг і використовується
    // як tiebreaker у CIFO eviction (Process_And_Cache_Data) коли два non-critical
    // записи мають однаковий RSSI. Нижчий SNR = шумніший канал = preferred to evict.

    // Очікуємо рівно 16 байт (повний зашифрований AES блок; post-ARCH.42 LoRa AES-128)
    if (size != 16) return;

    // [FIX: RSSI Truncation] SX1262 може повернути RSSI < -128.
    // Clamp до int8_t діапазону перед приведенням, щоб запобігти
    // overflow (наприклад, -130 → 126, що б отруїло CIFO eviction).
    if (rssi < -128) rssi = -128;
    if (rssi > 127)  rssi = 127;

    LoRa_Rx_Ring_Push(payload, (int8_t)rssi, snr);
}

// =========================================================================
// ЛОГІКА КЕШУ (Дедуплікація та CIFO)
// =========================================================================
// [E.8] CIFO eviction тепер враховує і RSSI, і SNR. RSSI — primary key (сила
// сигналу = відстань / preposition). SNR — tiebreaker для випадків, коли
// два кандидати мають ОДНАКОВИЙ RSSI: нижчий SNR = шумніший канал = пакет
// прийшов через інтерференцію → preferred for eviction. Це покращує якість
// кешу під час grueling LoRa-collision storms (емерджентний rain-attenuation,
// сусідні шлюзи на тому ж SF).
void Process_And_Cache_Data(uint32_t uid, uint8_t* payload, int8_t rssi, int8_t snr)
{
    // 1. ДЕДУПЛІКАЦІЯ: Шукаємо, чи є вже це дерево в кеші
    for(int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if(forest_cache[i].is_active && forest_cache[i].uid == uid) {
            // Оновлюємо дані на найсвіжіші (бо дерево могло надіслати новий статус)
            memcpy(forest_cache[i].payload, payload, 16);
            forest_cache[i].rssi = rssi;
            forest_cache[i].snr  = snr;
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
                forest_cache[i].snr  = snr;
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
    // [E.8] При рівному RSSI tiebreaker — нижчий SNR (шумніший канал → evict).
    else {
        int best_evict_idx = -1;
        int8_t best_evict_rssi = 127;
        int8_t best_evict_snr  = 127;

        int fallback_idx = 0;
        int8_t fallback_rssi = 127;
        int8_t fallback_snr  = 127;

        for(int i = 0; i < CACHE_MAX_ENTRIES; i++) {
            // [FIX: AUDIT] Перевіряємо is_active щоб не порівнювати неініціалізовані RSSI
            if (!forest_cache[i].is_active) continue;

            // [FW.29-PACK] bio_status з байта 10: біти [6:5] (status:2),
            // після того як FW.29 PANIC_FLAG_BIT займає бит 7. Старий `>> 6`
            // видавав bits [7:6], що тихо демотувало status=2/3 у
            // нормальних пакетах через `lora_payload[10] &= ~PANIC_FLAG_BIT`.
            uint8_t bio_status = (forest_cache[i].payload[10] >> 5) & 0x03;

            // Абсолютний fallback — найгірший RSSI (з SNR tiebreaker) серед усіх
            if (forest_cache[i].rssi < fallback_rssi ||
                (forest_cache[i].rssi == fallback_rssi && forest_cache[i].snr < fallback_snr)) {
                fallback_rssi = forest_cache[i].rssi;
                fallback_snr  = forest_cache[i].snr;
                fallback_idx  = i;
            }

            // Перевага: витісняємо некритичне (homeostasis, status=0) з найгіршим RSSI
            // [E.8] При рівному RSSI — нижчий SNR (шумніший канал) виграє конкурс на eviction.
            if (bio_status == 0 &&
                (forest_cache[i].rssi < best_evict_rssi ||
                 (forest_cache[i].rssi == best_evict_rssi && forest_cache[i].snr < best_evict_snr))) {
                best_evict_rssi = forest_cache[i].rssi;
                best_evict_snr  = forest_cache[i].snr;
                best_evict_idx  = i;
            }
        }

        int evict_idx = (best_evict_idx >= 0) ? best_evict_idx : fallback_idx;

        forest_cache[evict_idx].uid = uid;
        memcpy(forest_cache[evict_idx].payload, payload, 16);
        forest_cache[evict_idx].rssi = rssi;
        forest_cache[evict_idx].snr  = snr;
    }
}

// =========================================================================
// [FIX FW.16 + ARCH.42]: Безпечне відновлення CRYP_KEYSIZE_128B + AES-128-ECB + LoRa aes_key після CBC операцій (CoAP-канал використовує CRYP_KEYSIZE_256B + coap_key).
// Після CBC шифрування/дешифрування ОБОВ'ЯЗКОВО повертаємо ECB для LoRa.
// Якщо HAL_CRYP_Init зависне (hardware defect) — RCC reset + retry.
// Якщо і після RCC reset невдача — NVIC_SystemReset (повний перезапуск MCU),
// бо без робочого AES Королева не може дешифрувати пакети від Солдатів.
// =========================================================================
static void Restore_ECB_Mode(void)
{
    // Post-ARCH.42 (2026-05-23): restore LoRa context — CRYP_KEYSIZE_128B + aes_key (16 bytes).
    // Без цього restore LoRa decrypt буде ламатися (KeySize залишилось 256B + coap_key з CBC сесії).
    hcryp.Init.Algorithm = CRYP_AES_ECB;
    hcryp.Init.KeySize   = CRYP_KEYSIZE_128B;
    hcryp.Init.pKey      = aes_key;
    hcryp.Init.pInitVect = NULL;
    if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
        __HAL_RCC_CRYP_FORCE_RESET();
        __HAL_RCC_CRYP_RELEASE_RESET();
        hcryp.Init.Algorithm = CRYP_AES_ECB;
        hcryp.Init.KeySize   = CRYP_KEYSIZE_128B;
        hcryp.Init.pKey      = aes_key;
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

    // 3. Перемикаємо CRYP на CoAP context (post-ARCH.42 Variant B):
    //    AES-256-CBC + coap_key[8] + batch_iv. Після CoAP-операції Restore_ECB_Mode()
    //    повертає LoRa context (CRYP_KEYSIZE_128B + aes_key[4] + ECB).
    hcryp.Init.Algorithm = CRYP_AES_CBC;
    hcryp.Init.KeySize   = CRYP_KEYSIZE_256B;   // CoAP AES-256 (без SE constraint)
    hcryp.Init.pKey      = coap_key;            // 8 × uint32_t = 32 bytes (TODO: load from FLASH_COAP_KEY_ADDR)
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

// [FW.27-B] Length-strict DJB2 для двійкових пакетів (re-request-зойки
// можуть нести 0x00 байти всередині). На відміну від звичайного djb2_hash,
// НЕ зупиняється на NUL-байті — слухає всі `len` байт до кінця, щоб
// (DID, total, missing_bitmap) усі вплелися у пам'ять Королеви. Без цього
// два різні bitmap'и звучали б для неї однією піснею (бо total_chunks
// BE-upper байт = 0 для total<256), і другий зойк затих би в дедуплікації.
static uint32_t djb2_hash_bytes(const uint8_t* buf, uint8_t len)
{
    uint32_t h = 5381;
    for (uint8_t i = 0; i < len; i++) {
        h = ((h << 5) + h) + buf[i];
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
//   Відкритий текст (post-FW.20): [0x9C][unix_ts_be:4][inner_payload]
//   inner_payload може бути одним з:
//     - "CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<UUID>"  → актуатор
//     - [0x99][chunk_idx:2][total:2][bytecode][CRC]      → OTA-чанк байткоду
//     - [0x9A][len_le:2][body:10]                         → CMD_SET_THRESHOLDS
// Приклад: CMD:OPEN:60:42:a1b2c3d4-e5f6-7890-abcd-ef1234567890
//
// [FW.20] Бекенд `CoapEncryption` тепер ЗАВЖДИ обгортає inner_payload у
// конверт CMD_TIME_SYNC: [0x9C маркер][unix_ts_be:4]. Королева зрізає
// конверт, оновлює власний RTC (UTC від сервера як єдиного джерела істини),
// потім маршрутизує inner_payload через існуючу логіку (CMD: / 0x99 / 0x9A).
//
// [OTA Downlink]: OtaTransmissionWorker формує payload (після зрізання конверта):
//   [0x99][chunk_index:2][total_chunks:2][bytecode:≤512][CRC:2]
void Handle_CoAP_Command(uint8_t* payload, uint16_t len)
{
    // Мінімум: IV (16 байт) + один AES-блок (16 байт) = 32 байти
    if (len < 32 || len > (CMD_DECRYPT_BUF_SIZE + 16)) return;

    // 1. Витягуємо IV з перших 16 байтів пейлоада
    uint32_t cmd_iv[4];
    memcpy(cmd_iv, payload, 16);

    // 2. Перемикаємо CRYP на CoAP context (post-ARCH.42 Variant B):
    //    AES-256-CBC + coap_key + cmd_iv. Restore_ECB_Mode() далі поверне LoRa context.
    hcryp.Init.Algorithm = CRYP_AES_CBC;
    hcryp.Init.KeySize   = CRYP_KEYSIZE_256B;   // CoAP AES-256 (без SE constraint)
    hcryp.Init.pKey      = coap_key;            // 8 × uint32_t = 32 bytes
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
    // 5. [FW.20] Зрізаємо конверт CMD_TIME_SYNC: [0x9C][ts_be:4][inner_payload]
    // =========================================================================
    // Бекенд CoAPEncryption обгортає КОЖЕН downlink у цей конверт, щоб Королева
    // могла звірити свій RTC із серверним UTC ПЕРЕД маршрутизацією inner_payload.
    // Без конверта (legacy / спотворений пакет) маршрутизуємо as-is для
    // зворотної сумісності під час cutover'а (буде посилено після rollout'у).
    uint8_t* inner_payload = cmd_decrypt_buf;
    uint16_t inner_aligned = aligned;

    if (aligned >= CMD_TIME_SYNC_HEADER_SIZE && cmd_decrypt_buf[0] == CMD_TIME_SYNC_MARKER) {
        // Витягуємо unix_ts (big-endian uint32) з байтів 1..4
        uint32_t server_unix_ts = ((uint32_t)cmd_decrypt_buf[1] << 24) |
                                  ((uint32_t)cmd_decrypt_buf[2] << 16) |
                                  ((uint32_t)cmd_decrypt_buf[3] << 8)  |
                                  (uint32_t)cmd_decrypt_buf[4];

        // Оновлюємо Королевський RTC + запам'ятовуємо авторитетний UTC для маяків.
        // Apply_Server_Time персистить ts у нашому queen_unix_ts кеші — періодична
        // beacon-трансляція використає це значення коли транслюватиме час Солдатам.
        Apply_Server_Time(server_unix_ts);

        // Маршрутизуємо inner_payload (пропускаємо 5-байтний конверт)
        inner_payload = cmd_decrypt_buf + CMD_TIME_SYNC_HEADER_SIZE;
        inner_aligned = (uint16_t)(aligned - CMD_TIME_SYNC_HEADER_SIZE);

        // Якщо конверт без inner-пейлоада (серверний "ping") — нічого більше не робимо
        if (inner_aligned == 0) return;
    }

    // =========================================================================
    // 6. Маршрутизація за маркером: CMD (актуатор), 0x99 (OTA), 0x9A (thresholds)
    // =========================================================================
    if (inner_aligned >= 4 && strncmp((char*)inner_payload, "CMD:", 4) == 0) {
        // ── Гілка актуаторних команд ──────────────────────────────────

        // 6. Знаходимо idempotency_token (після 3-ї ':' від позиції +4)
        char* p = (char*)inner_payload + 4;
        uint16_t scanned = 4;
        uint8_t colons = 0;
        while (scanned < inner_aligned && *p && colons < 3) {
            if (*p++ == ':') colons++;
            scanned++;
        }
        if (colons < 3 || *p == '\0') return;

        // 7. 🛡️ Idempotency: хешуємо токен і перевіряємо кільцевий буфер
        if (Cmd_Dedup_Check(djb2_hash(p, UUID_STR_LEN)) == 1) {
            return; // Дублікат — ACK відправляємо, але команду НЕ виконуємо вдруге
        }

        // 8. Команда валідна та унікальна — передаємо на виконання актуатору
        // (Логіка виконання залежить від конкретного пристрою: клапан, сирена тощо)

    } else if (inner_aligned > 0 && inner_payload[0] == OTA_MARKER) {
        // ── Гілка OTA Downlink: збирання прошивки від Rails у RAM ─────
        // Архітектурний міст: Backend CoAP downlink → pending_ota_bytecode[] → LoRa broadcast
        //
        // Формат дешифрованого пакета (after FW.20 envelope strip):
        //   [0x99][chunk_index:2 BE][total_chunks:2 BE][bytecode:≤512][CRC:2]
        //
        // Після збирання всіх чанків — встановлюємо ota_is_active = 1,
        // і головний цикл автоматично починає LoRa-бродкаст на Солдатів.

        // [MISRA C] Мінімальна довжина: 1 маркер + 2 index + 2 total + 1 байт коду = 6
        if (inner_aligned < 6) return;

        // Витягуємо chunk_index та total_chunks (big-endian)
        uint16_t chunk_index  = ((uint16_t)inner_payload[1] << 8) | inner_payload[2];
        uint16_t total_chunks = ((uint16_t)inner_payload[3] << 8) | inner_payload[4];

        // [MISRA C] Захист від невалідних заголовків
        if (total_chunks == 0) return;

        // [FIX: AUDIT] Захист від chunk_index >= OTA_MAX_CHUNKS (переповнення bitmap)
        if (chunk_index >= OTA_MAX_CHUNKS) return;

        // [MISRA C] Захист від overflow при малому aligned (underflow на uint16_t)
        // MIN_OTA_ALIGNED = AES_BLOCK_SIZE (16) + OTA_HEADER_SIZE (5) + OTA_CRC_SIZE (2) = 23
        if (inner_aligned < MIN_OTA_ALIGNED) return;

        // Розрахунок довжини чистого байткоду (без заголовка, CRC, AES-padding):
        // inner_aligned — повна довжина розшифрованих даних (вирівняна по AES-блоку).
        // Останній AES-блок може бути padding → гарантована корисна довжина = inner_aligned - AES_BLOCK_SIZE.
        // Backend пакує до MAX_OTA_CHUNK_PAYLOAD байт коду + OTA_CRC_SIZE у чанк.
        // Якщо guaranteed >= OTA_FULL_CHUNK_THRESH → повний чанк, payload = MAX_OTA_CHUNK_PAYLOAD.
        // Інакше → неповний/останній чанк: payload = guaranteed - OTA_OVERHEAD.
        uint16_t guaranteed = inner_aligned - AES_BLOCK_SIZE;
        uint16_t payload_len = (guaranteed >= OTA_FULL_CHUNK_THRESH)
                             ? MAX_OTA_CHUNK_PAYLOAD
                             : (guaranteed - OTA_OVERHEAD);

        // Обчислюємо зсув у RAM-буфері
        uint32_t offset = (uint32_t)chunk_index * (uint32_t)MAX_OTA_CHUNK_PAYLOAD;

        // [MISRA C] Перевірка меж буфера: запобігаємо переповненню від зловмисних пакетів
        if (offset + payload_len > sizeof(pending_ota_bytecode)) return;

        // [FIX: AUDIT CRITICAL] Дедуплікація OTA-чанків.
        uint16_t chunk_bit = (uint16_t)(1U << chunk_index);
        if (ota_chunk_bitmap & chunk_bit) {
            // Дублікат — дані вже є в RAM, просто ігноруємо
            return;
        }

        // Копіюємо байткод у відповідну позицію RAM-буфера
        memcpy(pending_ota_bytecode + offset, &inner_payload[OTA_HEADER_SIZE], payload_len);

        // Оновлюємо стан збирання
        ota_total_expected_chunks = total_chunks;
        ota_chunk_bitmap |= chunk_bit;  // Маркуємо чанк як отриманий
        ota_chunks_received++;

        // Відстежуємо максимальний розмір зібраного байткоду
        if (offset + payload_len > pending_ota_size) {
            pending_ota_size = (uint16_t)(offset + payload_len);
        }

        // ── Перевірка завершення збирання: усі чанки отримано? ────────
        if (ota_chunks_received >= ota_total_expected_chunks) {
            ota_chunks_received = 0;
            ota_total_expected_chunks = 0;
            ota_chunk_bitmap = 0;
            current_ota_chunk_idx = 0;
            ota_is_active = 1;  // 🚀 Запускаємо бродкаст на ліс!
        }
    }
    // [FW.23] HMAC-печатка OTA (0x9B) — Королева приймає її як гонець:
    // wire (по знятті envelope): [0x9B][seg_idx:2 BE][total:2 BE][hmac_seg:11].
    // Кладемо цілий 16-байтний LoRa-блок у пам'ять, щоб під час reflex-broadcast
    // викинути його в ефір буква в букву (без re-pack, без re-encrypt header).
    // Backend → Soldier: істина живе між ними двома, Королева її не торкається.
    else if (inner_aligned >= 16 && inner_payload[0] == HMAC_TRAILER_MARKER) {
        uint16_t seg_idx = ((uint16_t)inner_payload[1] << 8) | inner_payload[2];
        if (seg_idx < 1 || seg_idx > HMAC_TRAILER_TOTAL_SEGS) return;
        // Беремо перші 16 байт inner_payload — готовий до повторної проповіді блок.
        memcpy(pending_ota_hmac_chunks[seg_idx - 1], inner_payload, 16);
        hmac_segments_received |= (uint8_t)(1u << (seg_idx - 1));
    }
    // [FW.20-Q2] CMD_SET_THRESHOLDS (0x9A) chunks для Солдатів ставляться в
    // soldier_cmd_queue (спільну з періодичним beacon TX) — implementation-шлях
    // використовує той самий LoRa-broadcast pipeline що й OTA-чанки.
}

// =========================================================================
// [FW.1 + ARCH.42 Variant B, 2026-05-23] ЗАВАНТАЖЕННЯ LoRa AES-128 КЛЮЧА
// З PROTECTED FLASH SECTOR
// =========================================================================
// Формат Flash-регіону на FLASH_KEY_ADDR (0x0803E000) — post-ARCH.42:
//   [0] FLASH_KEY_MAGIC (0x4B45594C = "KEYL") — маркер LoRa-ключа
//   [1..4] aes_key[0..3] — 4 × uint32_t = 128 bits LoRa AES-128 key
// Загальний розмір регіону = 4 + 16 = 20 байт (було 4 + 32 = 36 для AES-256).
// CoAP AES-256 ключ для Queen↔Rails — окремий FLASH_COAP_KEY_ADDR slot (TODO).
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
  // Post-ARCH.42 Variant B (2026-05-23): LoRa-канал на AES-128 (ATECC608B SE constraint).
  // CoAP-канал (Queen→Rails) залишається AES-256-CBC — динамічна re-init в
  // Flush_Cache_To_Rails на CRYP_KEYSIZE_256B + coap_key, потім restore назад.
  hcryp.Init.KeySize = CRYP_KEYSIZE_128B;
  hcryp.Init.pKey = aes_key;              // LoRa AES-128 (4 × uint32_t = 16 bytes)
  // ECB для LoRa-трафіку між Королевою та Солдатами (одиночні 16-байтні блоки).
  // Батч до сервера шифрується CBC динамічно в Flush_Cache_To_Rails (з coap_key),
  // команди від сервера дешифруються CBC динамічно в Handle_CoAP_Command (з coap_key),
  // після чого CRYP відновлюється до ECB + KeySize_128B + aes_key (SEC.8 Restoration).
  // FW.2 target — `CRYP_AES_CCM` 24B packet + 8B MIC (потребує hardware bench).
  hcryp.Init.Algorithm = CRYP_AES_ECB;
  HAL_CRYP_Init(&hcryp);
}

// ============================================================================
// [FW.2 / ARCH.42 Variant B] AES-128-CCM 24-byte LoRa packet — freeze-contract
// ============================================================================
// Queen decrypt path. Symmetric до Soldier `Soldier_Build_CCM_LoRa_Packet`.
// Gated `#define FW2_CCM_ENABLED 0` до hardware bench для `CRYP_AES_CCM` HAL
// верифікації. Host-тести у `firmware/test/test_ccm.c` верифікують через
// mock HAL CCM (libcrypto-backed).
//
// SSOT для packet layout та packing helpers — `firmware/common/lora_ccm.h`.
#include "../common/lora_ccm.h"

#define FW2_CCM_ENABLED  0  // freeze-contract — flip після HAL verification

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
// Reconfigure hcryp для CCM-режиму (LoRa decrypt). Викликається перед
// HAL_CRYPEx_AESCCM_Decrypt; після завершення слід викликати `MX_CRYP_Init()`
// для повернення у дефолтний ECB-режим LoRa control frame relay.
static void MX_CRYP_Init_CCM_Decrypt(uint8_t *nonce_12b, uint8_t *aad_8b)
{
    hcryp.Init.Algorithm  = CRYP_AES_CCM;
    hcryp.Init.pInitVect  = (uint32_t*)nonce_12b;
    hcryp.Init.Header     = aad_8b;
    hcryp.Init.HeaderSize = FW2_CCM_AAD_LEN;
    HAL_CRYP_Init(&hcryp);
}

// Parse a 24-byte CCM LoRa packet. On success returns HAL_OK and fills:
//   *out_did, *out_fc            — from AAD
//   out_sensor[8]                — decrypted sensor payload
// On MIC failure, malformed input, or HAL error returns HAL_ERROR and
// caller MUST drop the packet (do not relay, do not forward to backend).
//
// FC monotonic enforcement is NOT done here — keep that policy on Rails
// (`Cryptography::LoraCcm` + Redis SETNX per-DID). Queen-side dedup
// could be added in a follow-up using `recent_mesh_dids` if needed for
// mesh storms.
int Queen_Parse_CCM_LoRa_Packet(const uint8_t in_packet[FW2_CCM_AIR_PACKET_LEN],
                                uint32_t *out_did, uint32_t *out_fc,
                                uint8_t out_sensor[FW2_CCM_PLAINTEXT_LEN])
{
    if (!in_packet || !out_did || !out_fc || !out_sensor) return HAL_ERROR;

    uint32_t did =
        ((uint32_t)in_packet[0] << 24) | ((uint32_t)in_packet[1] << 16) |
        ((uint32_t)in_packet[2] << 8)  | (uint32_t)in_packet[3];
    uint32_t fc =
        ((uint32_t)in_packet[4] << 24) | ((uint32_t)in_packet[5] << 16) |
        ((uint32_t)in_packet[6] << 8)  | (uint32_t)in_packet[7];

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, fc, aad);

    // HAL_CRYPEx_AESCCM_Decrypt expects single input buffer = ciphertext || tag.
    uint8_t ct_and_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    memcpy(ct_and_tag, &in_packet[8], FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN);

    MX_CRYP_Init_CCM_Decrypt(nonce, aad);
    int status = HAL_CRYPEx_AESCCM_Decrypt(&hcryp, ct_and_tag, FW2_CCM_PLAINTEXT_LEN,
                                           out_sensor, 1000);
    MX_CRYP_Init(); // Restore LoRa ECB context for control frame relay.

    if (status != HAL_OK) return HAL_ERROR;

    *out_did = did;
    *out_fc  = fc;
    return HAL_OK;
}
#endif // FW2_CCM_ENABLED || HAL_MOCK_CCM_ENABLED

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

// =========================================================================
// [FW.20] СИНХРОНІЗАЦІЯ ЧАСУ: ЗАСТОСУВАННЯ СЕРВЕРНОГО ЧАСУ + LoRa-МАЯК
// =========================================================================
// Apply_Server_Time зберігає UTC-секунди від сервера (єдине джерело істини)
// у volatile-кеш + запам'ятовує HAL_GetTick() в момент синхронізації, щоб
// Get_Current_Unix_Ts міг екстраполювати скільки секунд минуло від
// останнього серверного downlink.
//
// Бекенд CoapEncryption обгортає КОЖЕН downlink у [0x9C][ts_be:4] envelope —
// це відбувається на кожному CoAP-роздтрипі (актуатор-команда, OTA-чанк, ping
// тощо), тому queen_unix_ts оновлюється з періодичністю хвилин у нормальному
// режимі.
static void Apply_Server_Time(uint32_t server_unix_ts)
{
    queen_unix_ts            = server_unix_ts;
    queen_unix_ts_local_tick = HAL_GetTick();
}

// Поточні UTC-секунди = остання синхронізація + локальні tick'и, що минули.
// Повертає 0 (ще не синхронізовано) якщо Apply_Server_Time не викликався.
// HAL_GetTick розгортається кожні ~49.7 діб; різниця uint32, тому overflow
// неявно безпечний для розрахунку дельти.
static uint32_t Get_Current_Unix_Ts(void)
{
    if (queen_unix_ts == 0) return 0;
    uint32_t elapsed_ms = HAL_GetTick() - queen_unix_ts_local_tick;
    return queen_unix_ts + (elapsed_ms / 1000U);
}

// Транслюємо 16-байтний маяк синхронізації часу через LoRa (ECB-encrypted),
// макет відкритого тексту:
//   [0x9C][unix_ts_be:u32][резерв:0×4][TTL=1][магія 'B'][pad:0×5]
// Придушено якщо queen_unix_ts == 0 (щоб не навчати Солдатів хибній епосі
// до нашого першого CoAP-роздтрипа). Кожен маяк коштує ~50–60 мс ефірного часу.
static void Broadcast_Time_Beacon(void)
{
    uint32_t now = Get_Current_Unix_Ts();
    if (now == 0) return;  // Ще не синхронізовано — нічого авторитетного транслювати

    uint8_t plaintext[16] = {0};
    uint8_t ciphertext[16] = {0};

    plaintext[0] = BEACON_MARKER;
    plaintext[1] = (uint8_t)(now >> 24);
    plaintext[2] = (uint8_t)(now >> 16);
    plaintext[3] = (uint8_t)(now >> 8);
    plaintext[4] = (uint8_t)(now & 0xFFu);
    // байти 5..8 зарезервовано під майбутню розкладку TDMA-слотів (ARCH.26)
    // [FW.20-S2] Байт 9: біт 7 = authoritativeness (Королева=1), нижні 7
    // біт = TTL (поточний BEACON_TTL=1, без ретрансляції). Соціолог-Солдат
    // зчитує цей біт у time_source_authoritative для майбутньої mesh-арбітрації.
    plaintext[9]  = BEACON_BYTE9_AUTHORITATIVE;
    plaintext[10] = (uint8_t)BEACON_MAGIC_BYTE;
    // байти 11..15 = 0x00 (padding до 16-байтного AES-блоку)

    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)plaintext, 4, (uint32_t*)ciphertext, 1000);
    Radio.Send(ciphertext, 16);
    HAL_Delay(60);  // Даємо PHY час фізично випромінити пакет перед re-arm RX
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
