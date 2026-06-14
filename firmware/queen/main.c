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
// [HRNG-IV] Pure, host-testable CoAP-batch fallback-IV derivation (coap_fallback_iv_word)
#include "coap_iv.h"
// [FW.53] CRC16-CCITT One-Home — перевірка CoAP-OTA чанків від Rails
#include "../common/silken_crc.h"
// [FW.3] Байтовий AT-токенайзер + транзакції (pure, host-tested)
#include "at_engine.h"
// [FW.56] CoAP PDU будує хост: SIM7070G — UDP-труба, не CoAP-стек
#include "coap_pdu.h"
// [FW.3/FW.56] Повна CoAP-PUT розмова з модемом (pure-оркестратор)
#include "sim7070_coap.h"

#include "uart_rx_ring.h"
#include "ota_window.h"   // [FW.52б] воскресіння OTA-вікна запізнілою печаткою
// [L1 QATT] Розкладка підписаного батч-конверта (pure, host-tested) — 03_05 §2.2
#include "../common/queen_attest.h"
// [L1 QATT] Ed25519 (Monocypher, pinned submodule — 03_01 §12.5): голос Королеви
#include "monocypher-ed25519.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
// OTA Downlink Constants (CoAP → Queen RAM assembly)
#define OTA_MARKER            0x99   // Маркер OTA-пакета (перший байт)
#define OTA_HEADER_SIZE       5      // LoRa-шар (Queen→Soldier): [0x99][index:2][total:2]
#define OTA_CRC_SIZE          2      // CRC16-CCITT в кінці CoAP-чанка
#define AES_BLOCK_SIZE        16     // AES block size (128-bit fixed; рівне для AES-128 і AES-256)
#define MAX_OTA_CHUNK_PAYLOAD 512    // Максимальний розмір байткоду в одному CoAP-чанку
// [FW.53] CoAP-шар (Rails→Queen) отримав явний len:
//   [0x99][index:2 BE][total:2 BE][len:2 BE][bytecode:len][crc16:2 BE]
// Стара довжино-вгадувальна формула (inner_aligned - 16 - 7) при zero-padding
// 0..15 байт СИСТЕМАТИЧНО обрізала 1..16 байт кожного чанка (повний 512B →
// 500B) — збірка була зламана by construction. Явний len + CRC16-перевірка
// (раніше CRC16 від бекенду взагалі ігнорувався!) закривають клас помилок.
#define OTA_COAP_HEADER_SIZE  7      // [0x99][index:2][total:2][len:2]
#define OTA_COAP_MIN_FRAME    (OTA_COAP_HEADER_SIZE + 1 + OTA_CRC_SIZE)  // 10

// [FW.23] HMAC-трейлер OTA — backend пакує 32-байтну печатку HMAC-SHA256
// у 3× 16-байтні LoRa-чанки + 4-й чанк з version_id, усі з маркером 0x9B.
// Королева — лише гонець: власної верифікації не робить, бо довіра прокладена
// end-to-end від бекенду до плоті Солдата.
#define HMAC_TRAILER_MARKER       0x9B
#define HMAC_TRAILER_HEADER_SIZE  5
#define HMAC_TRAILER_TOTAL_SEGS   3          // 3 чанки печатки (seg_idx 1..3)
#define OTA_TRAILER_TOTAL_CHUNKS  4          // + 1 чанк version_id (seg_idx 4)
#define OTA_TRAILER_ALL_RECEIVED  0x0Fu      // bitmask: 3 печатки + версія

// [FW.27-B] Magic Re-Request — крик Солдата у бік Королеви:
//   [0x55][DID:4][total_chunks:2 BE][bitmap:9] = один 16-байтний ECB-блок.
// Королева пам'ятає (DID, missing_bitmap) через cmd_dedup_ring 5 хв і
// вдруге не озивається. Озвучує лише пропущені чанки — не цілий wave.
#define OTA_REQ_MARKER             0x55
#define OTA_REQ_HEADER_SIZE        7
#define OTA_REQ_BITMAP_MAX_BYTES   9
#define OTA_REQ_PACKET_SIZE        16

// [ARCH.41-C / FW.20-S2] SYNC_REQ — зойк «Королево, час!» (дзеркало
// soldier/main.c freeze-contract): [0x56][DID:4][secs_since_sync:4][TTL]
// ['S'][vcap_mv:2][pad:3]. Шлеться у cold-boot grace-вікні (hello) або
// сторожовим псом дрейфу. Відповідь — негайна перемотка маяка.
#define SYNC_REQ_MARKER            0x56
#define SYNC_REQ_MAGIC_BYTE        0x53  /* 'S' */

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

// [PLAN 2.11 → FW.3] Starlink/LTE таймінги. Starlink DTC RTT 600–2400 мс,
// LTE-M 100–500 мс. Двигун (at_engine.h) — early-exit: латентність дорівнює
// реальній відповіді, дедлайни лише страхують тишу.
#define AT_INTERBYTE_TIMEOUT_MS  150     // [FW.3] пауза між байтами = «модем дослухав»
#define AT_INIT_BUDGET_MS        2000    // [FW.3] бюджет на одну init-команду
#define COAP_CONV_BUDGET_MS      15000   // [FW.3] повна розмова NEW→SEND→NMI→DEL (< вікно IWDG)
#define COAP_MAX_RETRIES         3       // [FW.9] Maximum CoAP send retry attempts
#define COAP_SERVER_HOST  "api.silkennet.com"  // [FW.56] CCOAPNEW хоче IP → CDNSGIP цього хоста
#define COAP_SERVER_PORT  5683

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
//   [BEACON_MARKER 0x9C][unix_ts_be:u32][резерв: 0x00 × 4][AUTH|TTL][магія 'B':1][padding 0x00 × 5]
// Солдат дивиться на байт 0 розшифрованого RX — відрізняється від OTA (0x99),
// телеметрії (починається з DID) та текстового CMD:. Маяк лунає приблизно раз на
// 15 хвилин у звичайному циклі скидання + одразу після кожного зрізаного конверта
// (щоб свіжий серверний час одразу йшов униз по рою). TTL=2 — Провідник може
// понести голос на 1 хоп далі (FW.20-S2 mesh-relay): TTL задає лише ГЛИБИНУ,
// обсяг луни гасить журнал поколінь Солдата (beacon_dedup.h, ≤1 ретрансляція
// на покоління на Провідника) — глибше TTL = рішення founder'а, тепер шторм-безпечне.
#define BEACON_MARKER              0x9C
#define BEACON_TTL                 2                    // 1 relay-хоп (03_02 §5а)
#define BEACON_MAGIC_BYTE          'B'                  // 0x42
// [FW.20-S2] Authoritativeness flag — біт 7 байту 9. Королева є єдиним
// authoritative джерелом часу (1); relay-маяки Провідників транслюють
// з 0. TTL фактично у нижніх 7 бітах.
#define BEACON_AUTH_FLAG           0x80
#define BEACON_BYTE9_AUTHORITATIVE ((uint8_t)(BEACON_AUTH_FLAG | BEACON_TTL))
#define TIME_BEACON_INTERVAL_MS    900000U              // 15 хвилин

// [FW.1] Flash-based AES key provisioning — per-device unique key via HKDF.
// Factory Flashing writes device_key to protected Flash sector 0x0803E000
// via SWD (STM32CubeProgrammer). Key is derived from master_key via HKDF-SHA256
// on the backend (HardwareKeyService.derive_device_key).
// See docs/03_06 §2 for full protocol design.
// [ARCH.42 Variant B, 2026-05-23] Two protected Flash slots: LoRa AES-128 key
// (per-Soldier lookup) + CoAP AES-256 key (Queen↔Rails magistral).
//   FLASH_KEY_ADDR     → LoRa AES-128 key (16 bytes, magic "KEYL")
//   FLASH_COAP_KEY_ADDR → CoAP AES-256 key (32 bytes, magic "KEYC") — slot after K_seed
// Узгоджено з SE050 Secure Element (03_05 §3.7): Slot 0 (AES-128 LoRa), Queen Protected Flash
// (AES-256 CoAP — без SE constraint, бо CoAP канал не проходить через SE).
#define FLASH_KEY_ADDR            0x0803E000UL  // Protected Flash sector for LoRa AES-128 key
#define FLASH_KEY_WORDS           4             // 4 × uint32_t = 16 bytes = 128 bits (ARCH.42)
#define FLASH_KEY_MAGIC           0x4B45594CUL  // "KEYL" — LoRa key magic (post-ARCH.42; was "SKEY")

// [ARCH.42] Окремий CoAP AES-256 key — завантажується Load_CoAP_Key() при boot
// з цього Protected Flash slot ([KEYC][32B], який пише CommandBuilder бекенду).
// М'який fallback: dev/sim без KEYC лишаються з нулями (не Error_Handler, на
// відміну від LoRa-ключа; виявлення — бекенд decrypt-метрика).
#define FLASH_COAP_KEY_ADDR       0x0803E040UL  // [KEYC][aes_coap:32] — дзеркало CommandBuilder FLASH_COAP_KEY_ADDR
#define FLASH_COAP_KEY_WORDS      8             // 8 × uint32_t = 32 bytes = 256 bits CoAP
#define FLASH_COAP_KEY_MAGIC      0x4B455943UL  // "KEYC" — CoAP key magic

// [L1 QATT] Ed25519-сім'я голосу Королеви — слот одразу після KEYC-блоку (4+32).
// Сім'я ГЕНЕРУЄТЬСЯ на фабричному хості (SecureRandom), НЕ HKDF-від-master:
// бекенд НЕ МОЖЕ її вивести — інакше backend-compromise підробляв би підпис,
// і рунг L1 не захищав би від того, від чого заявлений (канон: 05_02 ladder).
#define FLASH_ED25519_SEED_ADDR   0x0803E064UL  // [EDSK][seed:32]
#define FLASH_ED25519_SEED_WORDS  8             // 8 × uint32_t = 32 bytes seed
#define FLASH_ED25519_SEED_MAGIC  0x4544534BUL  // "EDSK" — Ed25519 seed magic
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
uint32_t aes_key[4] = {0};   // 16 bytes = AES-128 LoRa (SE = SE050 — 03_05 §3.7)

// [ARCH.42] CoAP AES-256 key — для batch flush Queen↔Rails (AES-256-CBC).
// Завантажується з FLASH_COAP_KEY_ADDR при boot (Load_CoAP_Key; HKDF info
// "silken-aes-256-device-key", пише CommandBuilder при Factory Flashing).
// Не прошито → лишається нулями (м'який fallback, не цеглить dev/sim-плати).
uint32_t coap_key[8] __attribute__((unused)) = {0};  // 32 bytes = AES-256 CoAP magistral

// [L1 QATT] Голос Королеви (рунг L1 драбини довіри — канон 05_02): секрет і
// pubkey деривуються при boot із Flash-сім'ї (Load_Ed25519_Seed). ready == 0
// (сім'я не прошита) → батчі летять legacy-форматом [IV][ct] — старий флот
// і dev-плати живуть без жодних змін.
static uint8_t ed25519_secret[64];
static uint8_t ed25519_pub[32] __attribute__((unused));  // знадобиться provisioning-діагностиці
static uint8_t ed25519_ready = 0;

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

    // Валідація uid_len: ненульова і в межах буфера призначення. uid_len — uint8_t
    // (≤255), а QUEEN_UID_MAX_LEN (32) ≪ 2 КБ Flash-сторінки, тож межа буфера
    // зв'язує першою (попередня перевірка `(5+uid_len)>2048` була завжди-хибною).
    if (uid_len == 0 || uid_len >= QUEEN_UID_MAX_LEN) {
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

// [FW.3] Один AT-двигун на Королеву: токенайзер переживає транзакції, бо
// URC (+CCOAPNMI, +CDNSGIP) вільні лунати і після фінала попередньої команди.
static AtEngine at_engine_state;

// [FW.3] Circular-DMA RX: кільце слухає модем БЕЗПЕРЕРВНО — байти і URC, що
// прилітають поза вікном читання (запізнілий +CCOAPNMI, RDY після ребуту
// модема), більше не вмирають в ORE. Розмір з запасом: найдовша лінія —
// +CCOAPNMI з hex-PDU відповіді (AT_LINE_MAX), решта — короткі фінали.
#define UART_RX_RING_SIZE 512u
static uint8_t           uart_rx_buf[UART_RX_RING_SIZE];
static UartRxRing        uart_rx_ring;
static volatile uint32_t uart_rx_wraps;   // TC-переривання = повний оберт кільця
static DMA_HandleTypeDef hdma_usart1_rx;
static char     coap_server_ip[16];     // [FW.56] CDNSGIP-кеш (CCOAPNEW хоче IP, не домен)
static uint16_t coap_mid;               // [FW.56] CoAP Message-ID наших PUT'ів

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

// =========================================================================
// [ARCH.35] Flash Ring Buffer — overflow tier CIFO (W25Q32JV SPI NOR)
// =========================================================================
// CIFO переповнюється за ~30 хв @100 Soldiers без uplink'а — евікшн мовчки
// губить телеметрію лісу. Ring (../common/flash_ring.{h,c}, host-тестований
// NOR-мок + power-cut) дає ~197k слотів буфера: спіл евікшнів і провалених
// flush'ів, drain FIFO при відновленні uplink'а (06_08 §1.2 L1 two-tier).
//
// 🟡 СТАТУС: ВИМКНЕНО (ARCH35_RING_ENABLED 0) — W25Q32 ще не в Queen BOM
// (02_05 §2.1 row 16 «Заплановано») і SPI-периферія не розведена; фліп =
// board-freeze (.ioc: MX_SPI1_Init + CS-пін) + bench; збірка при фліпі:
// + ../common/flash_ring.c (як test_flash_ring). Драйвер слотує
// 21-байтний wire-запис батча БІТОВО як Flush_Cache_To_Rails — спіл/дрейн
// не перекодовують. Семантика at-least-once: power-cut може повторити
// доставку (бекенд толерує дубль), але не губить.
#include "../common/flash_ring.h"

#define ARCH35_RING_ENABLED  0   // 🟡 фліп після BOM + board-freeze (bench)

#if ARCH35_RING_ENABLED
// --- SPI-глю W25Q32JV (datasheet cmd set) -------------------------------
// MX_SPI1_Init + W25Q32_CS_* пін — board-freeze фаза (.ioc), як HAL-глю
// FW.46: тут лише протокол. PP (0x02) програмує В МЕЖАХ 256-байтної
// сторінки (wrap!) → Ring_Program ріже chunk'и по page-межах.
extern SPI_HandleTypeDef hspi1;

#define W25_CMD_WREN   0x06u
#define W25_CMD_PP     0x02u
#define W25_CMD_READ   0x03u
#define W25_CMD_SE     0x20u
#define W25_CMD_RDSR   0x05u
#define W25_PAGE_SIZE  256u
#define W25_SPI_TO_MS  100u
#define W25_ERASE_TO_MS 400u  // typ ~45 мс, max 400 мс (datasheet)

static int W25_Xfer_Begin(uint8_t cmd, uint32_t addr, int with_addr)
{
    uint8_t hdr[4] = { cmd, (uint8_t)(addr >> 16), (uint8_t)(addr >> 8),
                       (uint8_t)addr };
    W25Q32_CS_LOW();
    return HAL_SPI_Transmit(&hspi1, hdr, with_addr ? 4u : 1u,
                            W25_SPI_TO_MS) == HAL_OK;
}

static int W25_Wait_Busy(uint32_t timeout_ms)
{
    uint32_t start = HAL_GetTick();
    for (;;) {
        uint8_t sr = 0;
        if (!W25_Xfer_Begin(W25_CMD_RDSR, 0, 0)) { W25Q32_CS_HIGH(); return 0; }
        int ok = HAL_SPI_Receive(&hspi1, &sr, 1, W25_SPI_TO_MS) == HAL_OK;
        W25Q32_CS_HIGH();
        if (!ok) return 0;
        if ((sr & 0x01u) == 0u) return 1; // WIP=0 — готовий
        if (HAL_GetTick() - start > timeout_ms) return 0;
    }
}

static int W25_Write_Enable(void)
{
    if (!W25_Xfer_Begin(W25_CMD_WREN, 0, 0)) { W25Q32_CS_HIGH(); return 0; }
    W25Q32_CS_HIGH();
    return 1;
}

static int Ring_Ops_Read(void *io, uint32_t addr, uint8_t *buf, uint32_t len)
{
    (void)io;
    if (!W25_Xfer_Begin(W25_CMD_READ, addr, 1)) { W25Q32_CS_HIGH(); return 0; }
    int ok = HAL_SPI_Receive(&hspi1, buf, (uint16_t)len, W25_SPI_TO_MS) == HAL_OK;
    W25Q32_CS_HIGH();
    return ok;
}

static int Ring_Ops_Program(void *io, uint32_t addr, const uint8_t *buf,
                            uint32_t len)
{
    (void)io;
    while (len > 0u) {
        uint32_t chunk = W25_PAGE_SIZE - (addr % W25_PAGE_SIZE);
        if (chunk > len) chunk = len;
        if (!W25_Write_Enable()) return 0;
        if (!W25_Xfer_Begin(W25_CMD_PP, addr, 1)) { W25Q32_CS_HIGH(); return 0; }
        int ok = HAL_SPI_Transmit(&hspi1, (uint8_t *)buf, (uint16_t)chunk,
                                  W25_SPI_TO_MS) == HAL_OK;
        W25Q32_CS_HIGH();
        if (!ok || !W25_Wait_Busy(W25_SPI_TO_MS)) return 0;
        addr += chunk; buf += chunk; len -= chunk;
    }
    return 1;
}

static int Ring_Ops_Erase(void *io, uint16_t sector)
{
    (void)io;
    if (!W25_Write_Enable()) return 0;
    if (!W25_Xfer_Begin(W25_CMD_SE, (uint32_t)sector * FLASH_RING_SECTOR_SIZE,
                        1)) { W25Q32_CS_HIGH(); return 0; }
    W25Q32_CS_HIGH();
    return W25_Wait_Busy(W25_ERASE_TO_MS);
}

static const FlashRingOps queen_ring_ops = {
    Ring_Ops_Read, Ring_Ops_Program, Ring_Ops_Erase
};
static FlashRing queen_ring;
static uint8_t   queen_ring_mounted = 0;
// Скільки ring-записів зараз перелито у CIFO і чекає підтвердження
// доставки (consume — лише після send_success: power-cut → дубль, не втрата).
static uint8_t   ring_inflight = 0;

// Слот CIFO → 21-байтний wire-запис (бітове дзеркало пакувальника
// Flush_Cache_To_Rails: DID:4 BE + |RSSI| + payload:16).
static void Ring_Serialize_Slot(const EdgeCache *slot, uint8_t out[FLASH_RING_RECORD_SIZE])
{
    out[0] = (uint8_t)(slot->uid >> 24);
    out[1] = (uint8_t)(slot->uid >> 16);
    out[2] = (uint8_t)(slot->uid >> 8);
    out[3] = (uint8_t)(slot->uid & 0xFFu);
    out[4] = (uint8_t)(-(int16_t)slot->rssi);
    memcpy(&out[5], slot->payload, 16);
}

static void Ring_Deserialize_Slot(const uint8_t rec[FLASH_RING_RECORD_SIZE], EdgeCache *slot)
{
    slot->uid = ((uint32_t)rec[0] << 24) | ((uint32_t)rec[1] << 16) |
                ((uint32_t)rec[2] << 8)  | (uint32_t)rec[3];
    slot->rssi = (int8_t)(-(int16_t)rec[4]);
    slot->snr  = 0; // SNR не їде у wire-записі — лише evict-tiebreaker, 0 чесний
    memcpy(slot->payload, &rec[5], 16);
    slot->is_active = 2; // 2 = перелитий з ring'а (flash-копія ще не consumed)
}
#endif // ARCH35_RING_ENABLED

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

// [HRNG-IV] Monotonic per-boot CoAP-flush counter — mixed into the HRNG-fallback
// CBC IV (coap_fallback_iv_word) so successive fallback IVs stay unique within a
// boot even if HAL_GetTick() barely advances between flushes.
static uint32_t coap_flush_seq = 0;

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
// Печатка приходить через CoAP downlink як 4 LoRa-готові 16-байтні блоки
// з маркером 0x9B (3 печатки + version_id). Королева — лише гонець: тримає
// plaintext-блоки і знову викидає їх в ефір у тому ж broadcast loop, що й 0x99
// чанки. Власної перевірки не чинить — істина народжується між бекендом і
// Солдатом. pending_ota_hmac_chunks[seg-1][0..15] = розшифрований 16-байтний
// LoRa-блок. hmac_segments_received = bitmask (біти 0/1/2 = печатка, біт 3 =
// версія) ⇒ всі 4 == OTA_TRAILER_ALL_RECEIVED (0x0F).
uint8_t  pending_ota_hmac_chunks[OTA_TRAILER_TOTAL_CHUNKS][16] = {{0}};
uint8_t  hmac_segments_received = 0;
uint8_t  current_hmac_seg_idx   = 0;     // Хто з 4-х трейлер-чанків зараз летить в ефір
uint8_t  hmac_broadcast_phase   = 0;     // 0 = bytecode-фаза; 1 = фаза печатки/версії

// [FW.20] UTC-секунди від сервера як єдине джерело істини, отримані через
// конверт CoAP TIME_SYNC. queen_unix_ts == 0 означає "ніколи не синхронізовано" —
// у цьому стані маяки до Солдатів придушені, щоб не навчати ліс хибній епосі.
volatile uint32_t queen_unix_ts          = 0;
volatile uint32_t queen_unix_ts_local_tick = 0;  // HAL_GetTick() в момент синхронізації

// =========================================================================
// [FW.20-Q2] SOLDIER CMD RELAY — черга Soldier-bound команд (0x9A, 0x9E)
// =========================================================================
// Королева-гонець для командних кадрів спільного каркаса: CoAP downlink від
// Rails → soldier_cmd_queue → рефлекторний постріл услід за uplink'ом Солдата
// (його єдине вікно слуху ~500 мс після власного TX; періодичний маяк летить
// у глухий ліс — ADR у soldier_cmd_queue.h). Повтори нешкідливі: 0x9E —
// forward-only ratchet, 0x9A — ідемпотентний; ACK 0x9E = Dual-Key Grace на
// бекенді (03_05 §3.8).
//
// 🟡 СТАТУС: ВИМКНЕНО (FW20_Q2_CMD_RELAY_ENABLED 0) — дзеркало Soldier-гейтів
// FW17_RATCHET_ENABLED / FW8_PARSER_ENABLED: ECB-downlink без MAC не сміє
// командувати ротацією, а на спільному транзит-ключі командний broadcast
// чули б усі Солдати (per-device адресація = CCM-крипто). Фліп — разом із
// FW.2 CCM + Soldier-гілками. Логіка черги pure (host-тести
// test_soldier_cmd_queue.c); канон — 03_02 §5б.
#include "soldier_cmd_queue.h"

#define FW20_Q2_CMD_RELAY_ENABLED  0   // 🟡 фліп разом із FW.2 CCM (bench)

#if FW20_Q2_CMD_RELAY_ENABLED
static SoldierCmdQueue soldier_cmd_queue;
#endif

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_SUBGHZ_Init(void);
static void MX_CRYP_Init(void); // Ініціалізація шифрування
static void MX_IWDG_Init(void); // [PLAN 2.6] Independent Watchdog — auto-recovery from HardFault
static void MX_USART1_RX_DMA_Init(void); // [FW.3] circular-DMA вухо модема

/* USER CODE BEGIN PFP */
// Функції-обгортки для роботи з модемом та транзитом
static AtTxResult SIM7070_Transact(const char* command, uint32_t budget_ms);
void Process_And_Cache_Data(uint32_t uid, const uint8_t* payload, int8_t rssi, int8_t snr);
void Flush_Cache_To_Rails(void);
// [СИНХРОНІЗОВАНО з Rails]: Обробка вхідних CoAP-команд від сервера
static uint32_t djb2_hash(const char* str, uint8_t len);
static uint32_t djb2_hash_bytes(const uint8_t* buf, uint8_t len);
uint8_t Cmd_Dedup_Check(uint32_t hash);
void Handle_CoAP_Command(uint8_t* payload, uint16_t len);
// [FW.1] Завантаження LoRa AES-128 ключа з Protected Flash Sector (post-ARCH.42).
static void Load_AES_Key(void);
// [ARCH.42] Завантаження CoAP AES-256 ключа (KEYC; м'який fallback — нулі).
static void Load_CoAP_Key(void);
// [L1 QATT] Ed25519-сім'я голосу Королеви (EDSK; відсутня → legacy-батчі).
static void Load_Ed25519_Seed(void);
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
  MX_USART1_RX_DMA_Init(); // [FW.3] кільце слухає модем з першої секунди
  MX_SUBGHZ_Init();
  Load_AES_Key();        // [FW.1] Завантажити per-device ключ з Flash ПЕРЕД ініціалізацією CRYP
  Load_CoAP_Key();       // [ARCH.42] CoAP AES-256 магістраль (KEYC; м'який fallback — нулі)
  Load_Ed25519_Seed();   // [L1 QATT] Голос Королеви (EDSK; відсутній → legacy-батчі)
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

#if ARCH35_RING_ENABLED
  // [ARCH.35] Mount overflow-ring'а: mount-scan відновлює head/tail/count
  // з in-band заголовків секторів (жодних RTC-покажчиків — переживає і
  // VBAT-loss). Відмова → tier вимкнений, CIFO живе як раніше (деградація,
  // не смерть); телеметрію про це повезе Queen Sentinel health-байт.
  queen_ring_mounted = FlashRing_Mount(&queen_ring, &queen_ring_ops, NULL,
                                       FLASH_RING_W25Q32_SECTORS);
#endif

  // 3. Ініціалізація модему SIM7070G
  // [FW.3] Response-driven: кожна команда чекає фінал (OK/ERROR), а не сліпий
  // delay. Провал не фатальний — модем міг ще прокидатись; flush-розмова
  // повторить усе зі свіжим бюджетом. ATE0 глушить ехо (токенайзер його
  // переживає, але ефір чистіший).
  (void)SIM7070_Transact("ATE0\r\n", AT_INIT_BUDGET_MS);
  (void)SIM7070_Transact("AT\r\n", AT_INIT_BUDGET_MS);
  (void)SIM7070_Transact("AT+CNMP=38\r\n", AT_INIT_BUDGET_MS);

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
  (void)SIM7070_Transact("AT+CPSMS=1,,,\"00100001\",\"00000000\"\r\n", AT_INIT_BUDGET_MS);

  // AT+CEDRXS=<mode>,<AcT>,<Requested_eDRX>:
  //   mode=1 → enable eDRX, AcT=5 → LTE Cat M1
  //   eDRX="0010" → 20.48 sec (paging window — короткий для downlink-сприйнятливості)
  (void)SIM7070_Transact("AT+CEDRXS=1,5,\"0010\"\r\n", AT_INIT_BUDGET_MS);

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

#if FW20_Q2_CMD_RELAY_ENABLED
        // =========================================================================
        // [FW.20-Q2] РЕФЛЕКТОРНИЙ ПОСТРІЛ КОМАНДИ (0x9A / 0x9E)
        // =========================================================================
        // Солдат, чий голос щойно прозвучав, слухає ефір ~500 мс — один
        // командний постріл (60 мс) перед OTA-чанком вміщається з запасом.
        // Команда першою: ротація ключа (FW.17) важливіша за чанк прошивки.
        {
            uint8_t cmd_plain[SOLDIER_CMD_BLOCK_SIZE];
            uint8_t cmd_cipher[SOLDIER_CMD_BLOCK_SIZE];
            if (Soldier_Cmd_Queue_Next(&soldier_cmd_queue, cmd_plain)) {
                HAL_CRYP_Encrypt(&hcryp, (uint32_t*)cmd_plain, 4,
                                 (uint32_t*)cmd_cipher, 1000);
                Radio.Send(cmd_cipher, SOLDIER_CMD_BLOCK_SIZE);
                HAL_Delay(60);  // PHY доказує пакет перед наступним TX/RX
            }
        }
#endif

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
                    // [FW.23] Тіло прошивки відлунало; якщо всі 4 трейлер-чанки
                    // (печатка + версія) зібрані — ставимо їх замість крапки.
                    if (hmac_segments_received == OTA_TRAILER_ALL_RECEIVED) {
                        hmac_broadcast_phase = 1;
                        current_hmac_seg_idx = 0;
                    } else {
                        // Без печатки/версії Солдат не зможе відрізнити істинне
                        // слово від спокусника ⇒ замикаємо вікно. Солдат сам подасть
                        // голос (re-request) або очне CoAP-розпорядження зверху
                        // воскресить новий цикл.
                        current_ota_chunk_idx = 0;
                        // [PLAN 2.5]: Гасимо OTA-прапор, інакше Королева
                        // безкінечно проповідуватиме той самий заповіт у пустоту.
                        ota_is_active = 0;
                    }
                }
            } else if (hmac_broadcast_phase == 1 &&
                       current_hmac_seg_idx < OTA_TRAILER_TOTAL_CHUNKS) {
                // [FW.23] Кладемо в ефір вже готовий 16-байтний трейлер-блок
                // (печатка seg 1..3 або version_id seg 4). Backend сформував його;
                // Королева повторює буква в букву — AES-encrypt + Radio.Send,
                // не торкаючись жодного байту (печатку не можна підправляти).
                memcpy(ota_chunk, pending_ota_hmac_chunks[current_hmac_seg_idx], 16);
                HAL_CRYP_Encrypt(&hcryp, (uint32_t*)ota_chunk, 4,
                                  (uint32_t*)encrypted_ota, 1000);
                Radio.Send(encrypted_ota, 16);
                HAL_Delay(60);

                current_hmac_seg_idx++;
                if (current_hmac_seg_idx >= OTA_TRAILER_TOTAL_CHUNKS) {
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

        // [ARCH.41-C] Зойк «Королево, час!» — hello cold-boot Солдата
        // (grace-вікно) чи сторожовий пес дрейфу. Не телеметрія — у літопис
        // не лягає. Відповідь: перемотка last_beacon_time → маяк стрельне на
        // цьому ж обороті циклу (~60 мс ефіру). Дедуп не потрібен: перемотка
        // ідемпотентна, маяк і так максимум один на оборот; без власного часу
        // (queen_unix_ts==0) Broadcast_Time_Beacon сам змовчить.
        if (decrypted_payload[0] == SYNC_REQ_MARKER &&
            decrypted_payload[10] == SYNC_REQ_MAGIC_BYTE) {
            last_beacon_time = HAL_GetTick() - TIME_BEACON_INTERVAL_MS - 1u;
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
// payload не-const: сигнатуру диктує callback-контракт радіо
// (Semtech RadioEvents_t.RxDone, uint8_t*) — const зламав би тип реєстрації.
// cppcheck-suppress constParameterPointer
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
void Process_And_Cache_Data(uint32_t uid, const uint8_t* payload, int8_t rssi, int8_t snr)
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

#if ARCH35_RING_ENABLED
        // [ARCH.35] Витіснений запис більше не гине мовчки — спіл у ring.
        // Перелитий слот (is_active==2) не дублюємо: його flash-копія ще
        // unconsumed і повернеться наступним drain'ом — лише знімаємо з
        // inflight-обліку, щоб consume після send_success її не списав.
        if (queen_ring_mounted) {
            if (forest_cache[evict_idx].is_active == 2u) {
                if (ring_inflight > 0u) ring_inflight--;
            } else {
                uint8_t rec[FLASH_RING_RECORD_SIZE];
                Ring_Serialize_Slot(&forest_cache[evict_idx], rec);
                (void)FlashRing_Append(&queen_ring, rec); // відмова = старий лосс-шлях
            }
        }
#endif
        forest_cache[evict_idx].uid = uid;
        memcpy(forest_cache[evict_idx].payload, payload, 16);
        forest_cache[evict_idx].rssi = rssi;
        forest_cache[evict_idx].snr  = snr;
        // Свіжий LoRa-запис — НЕ перелитий з ring'а (1, не успадковане 2):
        // інакше fail-спіл «почистив би» його як уже-збережений у флеші.
        forest_cache[evict_idx].is_active = 1;
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
        // [FW.46] RCC-блок криптоядра на WL зветься AES, не CRYP (F4-стиль
        // __HAL_RCC_CRYP_* у WL-HAL не існує — зловив HAL compile-lane).
        __HAL_RCC_AES_FORCE_RESET();
        __HAL_RCC_AES_RELEASE_RESET();
        hcryp.Init.Algorithm = CRYP_AES_ECB;
        hcryp.Init.KeySize   = CRYP_KEYSIZE_128B;
        hcryp.Init.pKey      = aes_key;
        hcryp.Init.pInitVect = NULL;
        if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
            NVIC_SystemReset();
        }
    }
}

// [FW.3] UART-клей під чистий AT-двигун (at_engine.h). Еволюція у три кроки:
// (1) стара схема читала 128 байт «до упору» — кожен обмін коштував увесь
// timeout; (2) побайтовий HAL_UART_Receive — early-exit, але глухота поза
// викликом (ORE губив запізнілі URC); (3) тепер — circular-DMA кільце
// (uart_rx_ring.h, host-тестоване): залізо пише завжди, ми лише знімаємо.
// Владар дедлайну — UartAtIo; протокол — pure-хедери (test_at_engine.c).
typedef struct { uint32_t deadline_tick; } UartAtIo;

// [FW.3] Ініціалізація вуха: DMA1_Channel1 ← DMAMUX(USART1_RX), circular,
// побайтово. При HAL-вендорингу (CubeMX) NVIC/handler переїдуть у *_it.c.
static void MX_USART1_RX_DMA_Init(void)
{
    __HAL_RCC_DMAMUX1_CLK_ENABLE();
    __HAL_RCC_DMA1_CLK_ENABLE();

    hdma_usart1_rx.Instance                 = DMA1_Channel1;
    hdma_usart1_rx.Init.Request             = DMA_REQUEST_USART1_RX;
    hdma_usart1_rx.Init.Direction           = DMA_PERIPH_TO_MEMORY;
    hdma_usart1_rx.Init.PeriphInc           = DMA_PINC_DISABLE;
    hdma_usart1_rx.Init.MemInc              = DMA_MINC_ENABLE;
    hdma_usart1_rx.Init.PeriphDataAlignment = DMA_PDATAALIGN_BYTE;
    hdma_usart1_rx.Init.MemDataAlignment    = DMA_MDATAALIGN_BYTE;
    hdma_usart1_rx.Init.Mode                = DMA_CIRCULAR;
    hdma_usart1_rx.Init.Priority            = DMA_PRIORITY_LOW;
    if (HAL_DMA_Init(&hdma_usart1_rx) != HAL_OK) Error_Handler();
    __HAL_LINKDMA(&huart1, hdmarx, hdma_usart1_rx);

    HAL_NVIC_SetPriority(DMA1_Channel1_IRQn, 1, 0);
    HAL_NVIC_EnableIRQ(DMA1_Channel1_IRQn);

    Uart_Ring_Init(&uart_rx_ring, uart_rx_buf, (uint16_t)UART_RX_RING_SIZE);
    uart_rx_wraps = 0u;
    if (HAL_UART_Receive_DMA(&huart1, uart_rx_buf, (uint16_t)UART_RX_RING_SIZE) != HAL_OK)
        Error_Handler();
}

// Повний оберт кільця (TC). Half-transfer не потрібен — позицію пера дає NDTR.
// cppcheck-suppress constParameterPointer // сигнатура weak-override фіксована HAL'ом
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart == &huart1) uart_rx_wraps++;
}

void DMA1_Channel1_IRQHandler(void)
{
    HAL_DMA_IRQHandler(&hdma_usart1_rx);
}

// Консистентний знімок продюсера: wraps двічі довкола NDTR — TC між
// читаннями неможливо не помітити. Залишкову IRQ-латентність гасить
// монотонний clamp усередині Uart_Ring_Advance (див. uart_rx_ring.h).
static uint32_t Uart_Ring_Sync(void)
{
    uint32_t w1, w2;
    uint16_t nd;
    do {
        w1 = uart_rx_wraps;
        nd = (uint16_t)__HAL_DMA_GET_COUNTER(&hdma_usart1_rx);
        w2 = uart_rx_wraps;
    } while (w1 != w2);
    return Uart_Ring_Advance(&uart_rx_ring, w2, nd);
}

// [FW.3] Свіжий старт розмови: викинути хвости ПОПЕРЕДНІХ обмінів (пізній
// "OK" від таймаутнутого DEL годину тому НЕ сміє підтвердити нову команду).
// Всередині розмови НЕ викликати — запізнілий +CCOAPNMI з валідним MID =
// легітимна доставка, її якраз і ловимо.
static void Uart_Rx_Drain_Stale(void)
{
    uint8_t b;
    (void)Uart_Ring_Sync();
    while (Uart_Ring_Pop(&uart_rx_ring, &b)) { /* зів'яле листя */ }
}

// cppcheck-suppress constParameterCallback // сигнатура AtByteSource спільна: host-модем мутує свій io
static int Uart_At_Source(void *io, uint8_t *b)
{
    const UartAtIo *u = (const UartAtIo *)io;
    uint32_t silence_deadline = HAL_GetTick() + AT_INTERBYTE_TIMEOUT_MS;
    for (;;) {
        if ((int32_t)(HAL_GetTick() - u->deadline_tick) >= 0) return 0;
        (void)Uart_Ring_Sync();
        if (Uart_Ring_Pop(&uart_rx_ring, b)) return 1;
        // міжбайтова тиша = «модем дослухав» (семантика старого читання)
        if ((int32_t)(HAL_GetTick() - silence_deadline) >= 0) return 0;
    }
}

static int Uart_At_Sink(void *io, const uint8_t *bytes, uint16_t n)
{
    (void)io;
    return HAL_UART_Transmit(&huart1, (uint8_t *)bytes, n, 1000) == HAL_OK;
}

// Команда → фінал (OK/ERROR/+CME) у межах бюджету. URC дорогою ігноруються —
// для URC-розмов є Sim7070_Resolve_Host / Sim7070_Coap_Put.
static AtTxResult SIM7070_Transact(const char* command, uint32_t budget_ms)
{
    UartAtIo io = { HAL_GetTick() + budget_ms };
    At_Engine_Reset(&at_engine_state);
    Uart_Rx_Drain_Stale(); // init-шлях: відповідь мусить належати ЦІЙ команді
    if (HAL_UART_Transmit(&huart1, (uint8_t*)command, strlen(command), 1000) != HAL_OK) {
        return AT_TX_TIMEOUT;
    }
    AtTransact t;
    At_Transact_Init(&t, NULL);
    return At_Transact_Run(&at_engine_state, &t, Uart_At_Source, &io);
}

// =========================================================================
// ПАКЕТНЕ ВІДПРАВЛЕННЯ ЧЕРЕЗ CoAP (Бінарний масив поверх UDP)
// =========================================================================
void Flush_Cache_To_Rails(void)
{
    uint16_t offset = 0;
    uint8_t  packed_count = 0;   // [FW.51] скільки слотів увійшло в цей батч

    // Пакуємо весь кеш у щільний бінарний масив (21 байт на запис).
    // [FW.51] Слоти тут НЕ звільняємо — лише рахуємо; кеш чистимо аж після
    // підтвердженого send (наприкінці). Інакше провал CoAP (LTE-діра, retry
    // вичерпано) мовчки знищив би вже-зібрану телеметрію лісу: слоти вільні,
    // а дані ще нікуди не дійшли.
    for(int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if(forest_cache[i].is_active) {
            if ((size_t)(offset + 21) > sizeof(binary_batch_buffer)) break;
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

            packed_count++;  // [FW.51] слот лишається активним до успіху send
        }
    }

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

    // [HRNG-IV] Bump the per-boot flush counter so a HRNG-fallback IV (below) is
    // unique across flushes; queen_unix_ts adds cross-reboot uniqueness.
    coap_flush_seq++;

    hrng.Instance = RNG;
    HAL_RNG_Init(&hrng);

    for (uint8_t i = 0U; i < 4U; i++) {
        if (HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK) {
            /* [HRNG-IV] HRNG failed → derive a UNIQUE fallback IV word. NOT a CSPRNG:
               unique across device (uid_hash) / reboot (queen_unix_ts) / flush
               (coap_flush_seq), but predictable — acceptable here because the CoAP
               batch has no chosen-plaintext vector (03_05 §HRNG Fallback). Derivation lives
               in coap_iv.h (pure → host-tested in firmware/test/test_encryption.c). */
            batch_iv[i] = coap_fallback_iv_word(i, HAL_GetTick(),
                                                djb2_hash(queen_uid, strlen(queen_uid)),
                                                queen_unix_ts, coap_flush_seq);
        }
    }

    HAL_RNG_DeInit(&hrng);

    // 3. Перемикаємо CRYP на CoAP context (post-ARCH.42 Variant B):
    //    AES-256-CBC + coap_key[8] + batch_iv. Після CoAP-операції Restore_ECB_Mode()
    //    повертає LoRa context (CRYP_KEYSIZE_128B + aes_key[4] + ECB).
    hcryp.Init.Algorithm = CRYP_AES_CBC;
    hcryp.Init.KeySize   = CRYP_KEYSIZE_256B;   // CoAP AES-256 (без SE constraint)
    hcryp.Init.pKey      = coap_key;            // 8 × uint32_t = 32 bytes (Load_CoAP_Key @boot з FLASH_COAP_KEY_ADDR)
    hcryp.Init.pInitVect = batch_iv;
    HAL_CRYP_Init(&hcryp);

    // 4. Шифруємо батч. Довжина в 32-бітних словах = padded_size / 4.
    //    Буфер [L1 QATT]: [prefix-зона][header 9][IV 16][ct][sig 64] — один
    //    static-конверт (розкладка: common/queen_attest.h, канон 03_05 §2.2).
    //    IV+ct лягають на свої зсуви ОДРАЗУ — legacy і signed шляхи ділять
    //    ті самі байти, різняться лише вікном payload'а.
    // [FIX: AUDIT CRITICAL] static, не стек: ~2.2KB при 64KB RAM і глибокому
    // call chain — переповнення стеку.
    static uint8_t batch_attest_buffer[QATT_BUFFER_SIZE] __attribute__((aligned(4)));
    memcpy(batch_attest_buffer + QATT_IV_OFFSET, batch_iv, QATT_IV_LEN);
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)binary_batch_buffer, padded_size / 4,
                     (uint32_t*)(batch_attest_buffer + QATT_CT_OFFSET), 2000);

    // [FIX FW.16 → FW.3] CRYP назад у LoRa-ECB ОДРАЗУ після CBC-шифрування:
    // модемна розмова попереду довга, а вікно чужого CRYP-режиму має бути
    // нульовим — інакше наступні HAL_CRYP_Decrypt() LoRa-пакетів жували б CBC.
    Restore_ECB_Mode();

    // [L1 QATT] Голос Королеви: header → право-вирівняний префікс домену+UID →
    // Ed25519 над prefix‖header‖IV‖ct (encrypt-then-sign), підпис лягає хвостом.
    // Бекенд верифікує проти HardwareKey.ed25519_public_key_hex ДО decrypt.
    // Сім'я не прошита (ready==0) чи UID битий → legacy [IV][ct], як завжди.
    const uint8_t *coap_payload = batch_attest_buffer + QATT_IV_OFFSET;
    uint16_t total_size         = (uint16_t)(QATT_IV_LEN + padded_size);
    if (ed25519_ready) {
        Qatt_Write_Header(batch_attest_buffer + QATT_HDR_OFFSET,
                          Get_Current_Unix_Ts(), coap_flush_seq);
        uint16_t prefix_len = Qatt_Compose_Prefix(batch_attest_buffer,
                                                  QATT_HDR_OFFSET, queen_uid);
        if (prefix_len != 0u) {
            // Software-Ed25519 на M4 — десятки–сотні мс: годуємо пса ДО підпису.
            HAL_IWDG_Refresh(&hiwdg);
            const uint8_t *msg = batch_attest_buffer + QATT_HDR_OFFSET - prefix_len;
            size_t msg_len = (size_t)prefix_len + QATT_HEADER_LEN
                           + QATT_IV_LEN + padded_size;
            crypto_ed25519_sign(batch_attest_buffer + QATT_CT_OFFSET + padded_size,
                                ed25519_secret, msg, msg_len);
            coap_payload = batch_attest_buffer + QATT_HDR_OFFSET;
            total_size   = (uint16_t)(QATT_HEADER_LEN + QATT_IV_LEN
                                      + padded_size + QATT_SIG_LEN);
        }
    }

    // [FW.56] SIM7070G — UDP-труба, не CoAP-стек: PDU (CON PUT
    // /telemetry/batch/<uid> + батч) будуємо самі, модем шле його hex'ом.
    // Доставка = відповідь сервера 2.xx у +CCOAPNMI з нашим MID — НЕ
    // транспортний OK. Уся розмова — pure-оркестратор sim7070_coap.h,
    // host-тестований на скриптованому модемі.
    // [FW.3] Один drain на РОЗМОВУ (не на retry!): хвости минулих флешів
    // геть, але запізнілий +CCOAPNMI цієї ж розмови (MID той самий між
    // retry) лишається законним підтвердженням доставки.
    Uart_Rx_Drain_Stale();

    if (coap_server_ip[0] == '\0') {
        // CCOAPNEW приймає IP → одна CDNSGIP-резолюція, кеш на життя boot'а.
        UartAtIo dns_io = { HAL_GetTick() + COAP_CONV_BUDGET_MS };
        Sim7070Io dns_m = { Uart_At_Source, Uart_At_Sink, &dns_io };
        if (!Sim7070_Resolve_Host(&dns_m, &at_engine_state, COAP_SERVER_HOST,
                                  coap_server_ip, sizeof coap_server_ip)) {
            coap_server_ip[0] = '\0';
            return; // [FW.51] слоти живі — наступний флеш повторить і DNS
        }
    }

    static uint8_t coap_pdu_buf[sizeof(batch_attest_buffer) + 64];
    coap_mid++;
    uint16_t pdu_len = Coap_Build_Put(coap_pdu_buf, sizeof coap_pdu_buf, coap_mid,
                                      "telemetry", "batch", queen_uid,
                                      coap_payload, total_size);
    if (pdu_len == 0u) return; // не зібрався PDU — слоти живі (FW.51)

    uint8_t send_success = 0;
    for (uint8_t retry = 0; retry < COAP_MAX_RETRIES && !send_success; retry++) {
        // Розмова вкладається у COAP_CONV_BUDGET_MS < вікно IWDG — пес ситий.
        HAL_IWDG_Refresh(&hiwdg);
        UartAtIo io = { HAL_GetTick() + COAP_CONV_BUDGET_MS };
        Sim7070Io m = { Uart_At_Source, Uart_At_Sink, &io };
        send_success = (uint8_t)Sim7070_Coap_Put(&m, &at_engine_state,
                                                 coap_server_ip, COAP_SERVER_PORT,
                                                 coap_pdu_buf, pdu_len, coap_mid);
    }

    // [FW.51] Звільняємо кеш ЛИШЕ після підтвердженого send. Якщо всі retry
    // впали — слоти лишаються активними, наступний флеш повторить спробу
    // (дедуплікація Process_And_Cache_Data оновить ті самі DID найсвіжішими
    // даними, тож лишок не застаріє). Чистимо лише запаковані слоти (перші
    // packed_count активних): якщо пакування обірвалось по місткості буфера,
    // решта мусить пережити флеш.
    if (send_success) {
        uint8_t cleared = 0;
        for (int i = 0; i < CACHE_MAX_ENTRIES && cleared < packed_count; i++) {
            if (forest_cache[i].is_active) {
                forest_cache[i].is_active = 0;
                cleared++;
            }
        }
        cache_count -= cleared;

#if ARCH35_RING_ENABLED
        // [ARCH.35] Uplink живий: (1) durable-списуємо ring-записи, що
        // були перелиті в ЦЕЙ доставлений батч (consume лише після
        // send_success — power-cut дає дубль, не втрату); (2) drain-refill:
        // тягнемо найстаріші недоставлені у звільнені слоти CIFO — наступний
        // flush повезе їх існуючою машинерією (FW.51-семантика збережена).
        if (queen_ring_mounted) {
            if (ring_inflight > 0u) {
                (void)FlashRing_Consume(&queen_ring, ring_inflight);
                ring_inflight = 0;
            }
            uint8_t rec[FLASH_RING_RECORD_SIZE];
            while (cache_count < CACHE_MAX_ENTRIES &&
                   FlashRing_Count(&queen_ring) > ring_inflight &&
                   FlashRing_Read_Tail(&queen_ring, ring_inflight, rec)) {
                for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
                    if (!forest_cache[i].is_active) {
                        Ring_Deserialize_Slot(rec, &forest_cache[i]);
                        cache_count++;
                        ring_inflight++;
                        break;
                    }
                }
            }
        }
#endif
    }
#if ARCH35_RING_ENABLED
    else if (queen_ring_mounted) {
        // [ARCH.35] Retry вичерпано (LTE-діра): спіл свіжих записів у ring
        // звільняє RAM під нову годину телеметрії — дані чекають у флеші
        // (раніше FW.51 тримав їх у RAM, і евікшни губили нове). Перелиті
        // (is_active==2) не дублюємо — їхні flash-копії ще unconsumed.
        // Відмова Append (ring помер) → слот лишається в CIFO, як до ARCH.35.
        uint8_t spilled = 0;
        for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
            if (forest_cache[i].is_active == 2u) {
                forest_cache[i].is_active = 0;
                spilled++;
            } else if (forest_cache[i].is_active) {
                uint8_t rec[FLASH_RING_RECORD_SIZE];
                Ring_Serialize_Slot(&forest_cache[i], rec);
                if (FlashRing_Append(&queen_ring, rec)) {
                    forest_cache[i].is_active = 0;
                    spilled++;
                }
            }
        }
        cache_count -= spilled;
        ring_inflight = 0;
    }
#endif
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
//     - [0x9E][len_le:2 = 4][target_version:u16le][crc16] → CMD_ROTATE_KEY (FW.17)
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
        const char* p = (char*)inner_payload + 4;
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
        // [FW.53] Формат дешифрованого пакета (after FW.20 envelope strip):
        //   [0x99][chunk_index:2 BE][total_chunks:2 BE][len:2 BE][bytecode:len][crc16:2 BE]
        // Явний len замість вгадування довжини з CBC zero-padding (стара формула
        // обрізала 1..16 байт КОЖНОГО чанка), CRC16 від бекенду тепер
        // ПЕРЕВІРЯЄТЬСЯ (раніше — німо ігнорувався).
        //
        // Після збирання всіх чанків — встановлюємо ota_is_active = 1,
        // і головний цикл автоматично починає LoRa-бродкаст на Солдатів.

        // [MISRA C] Мінімальна довжина: header(7) + 1 байт коду + crc16(2) = 10
        if (inner_aligned < OTA_COAP_MIN_FRAME) return;

        // Витягуємо chunk_index, total_chunks, payload_len (big-endian)
        uint16_t chunk_index  = ((uint16_t)inner_payload[1] << 8) | inner_payload[2];
        uint16_t total_chunks = ((uint16_t)inner_payload[3] << 8) | inner_payload[4];
        uint16_t payload_len  = ((uint16_t)inner_payload[5] << 8) | inner_payload[6];

        // [MISRA C] Захист від невалідних заголовків
        if (total_chunks == 0) return;

        // [FIX: AUDIT] Захист від chunk_index >= OTA_MAX_CHUNKS (переповнення bitmap)
        if (chunk_index >= OTA_MAX_CHUNKS) return;

        // Брехливий або порожній len: межі диктує бекендів MAX_OTA_CHUNK_PAYLOAD,
        // а повний кадр (header + len + crc) мусить вміститись у дешифроване.
        if (payload_len == 0 || payload_len > MAX_OTA_CHUNK_PAYLOAD) return;
        uint32_t frame_len = (uint32_t)OTA_COAP_HEADER_SIZE + payload_len + OTA_CRC_SIZE;
        if (frame_len > inner_aligned) return;

        // CRC16-CCITT над header+bytecode проти хвостових 2 байтів (BE) —
        // дзеркало OtaPackagerService.crc16_ccitt. Біт, що збрехав у LTE/Starlink
        // транзиті, вмирає тут, а не у Flash Солдата.
        uint16_t expected_crc = Silken_Crc16_Ccitt(inner_payload,
                                                   (uint16_t)(OTA_COAP_HEADER_SIZE + payload_len));
        uint16_t received_crc = ((uint16_t)inner_payload[OTA_COAP_HEADER_SIZE + payload_len] << 8)
                              | inner_payload[OTA_COAP_HEADER_SIZE + payload_len + 1];
        if (expected_crc != received_crc) return;

        // Обчислюємо зсув у RAM-буфері
        uint32_t offset = (uint32_t)chunk_index * (uint32_t)MAX_OTA_CHUNK_PAYLOAD;

        // [MISRA C] Перевірка меж буфера: запобігаємо переповненню від зловмисних пакетів
        if (offset + payload_len > sizeof(pending_ota_bytecode)) return;

        // [FW.53] Світанок нової кампанії: pending_ota_size
        // раніше лише ріс (max-трек) і переживав попередню прошивку — менша
        // нова збірка успадковувала б хвости старої, total_chunks рахувався б
        // від химери, і Солдати діставали б зіпсуте слово (вічний CRC-fail).
        // Idle-стан збирання (порожній bitmap) → розмір починає життя з нуля.
        if (ota_chunk_bitmap == 0 && ota_chunks_received == 0) {
            pending_ota_size = 0;
        }

        // [FIX: AUDIT CRITICAL] Дедуплікація OTA-чанків.
        uint16_t chunk_bit = (uint16_t)(1U << chunk_index);
        if (ota_chunk_bitmap & chunk_bit) {
            // Дублікат — дані вже є в RAM, просто ігноруємо
            return;
        }

        // Копіюємо байткод у відповідну позицію RAM-буфера
        memcpy(pending_ota_bytecode + offset, &inner_payload[OTA_COAP_HEADER_SIZE], payload_len);

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
    // wire (по знятті envelope): seg 1..3 [0x9B][seg_idx:2 BE][total:2 BE][hmac_seg:11];
    // seg 4 [0x9B][0x0004][total:2 BE][version_id:4 BE][PAD:7]. Кладемо цілий
    // 16-байтний LoRa-блок у пам'ять, щоб під час reflex-broadcast викинути його
    // в ефір буква в букву (без re-pack, без re-encrypt header). Backend → Soldier:
    // істина живе між ними двома, Королева її не торкається.
    else if (inner_aligned >= 16 && inner_payload[0] == HMAC_TRAILER_MARKER) {
        uint16_t seg_idx = ((uint16_t)inner_payload[1] << 8) | inner_payload[2];
        if (seg_idx < 1 || seg_idx > OTA_TRAILER_TOTAL_CHUNKS) return;
        // Беремо перші 16 байт inner_payload — готовий до повторної проповіді блок.
        memcpy(pending_ota_hmac_chunks[seg_idx - 1], inner_payload, 16);
        hmac_segments_received |= (uint8_t)(1u << (seg_idx - 1));

        // [FW.52б] Запізніла печатка: тіло вже відлунало і вікно згасло
        // (§5.X.6 п.2), а цей сегмент щойно довершив трейлер → воскрешаємо
        // вікно одразу у фазу печатки. Анти-проповідь [PLAN 2.5] збережена;
        // Солдати з частковим тілом знову почуті (re-request живий).
        if (Ota_Late_Trailer_Resurrects(hmac_segments_received,
                                        OTA_TRAILER_ALL_RECEIVED,
                                        ota_is_active, pending_ota_size,
                                        ota_chunk_bitmap, ota_chunks_received)) {
            hmac_broadcast_phase = 1;
            current_hmac_seg_idx = 0;
            ota_is_active        = 1;
        }
    }
    // [FW.20-Q2] Soldier-bound команди спільного каркаса (0x9A
    // CMD_SET_THRESHOLDS [FW.8], 0x9E CMD_ROTATE_KEY [FW.17]) → черга
    // рефлекторних пострілів (валідатор + дедуп + бюджет —
    // soldier_cmd_queue.h). Невалідний кадр черга мовчки відкидає — як
    // Солдат відкинув би, тільки без витрачених пострілів в ефір.
#if FW20_Q2_CMD_RELAY_ENABLED
    else if (inner_aligned > 0 &&
             (inner_payload[0] == SOLDIER_CMD_MARKER_THRESHOLDS ||
              inner_payload[0] == SOLDIER_CMD_MARKER_ROTATE_KEY)) {
        Soldier_Cmd_Queue_Push(&soldier_cmd_queue, inner_payload, inner_aligned);
    }
#endif
}

// =========================================================================
// [FW.1 + ARCH.42 Variant B, 2026-05-23] ЗАВАНТАЖЕННЯ LoRa AES-128 КЛЮЧА
// З PROTECTED FLASH SECTOR
// =========================================================================
// Формат Flash-регіону на FLASH_KEY_ADDR (0x0803E000) — post-ARCH.42:
//   [0] FLASH_KEY_MAGIC (0x4B45594C = "KEYL") — маркер LoRa-ключа
//   [1..4] aes_key[0..3] — 4 × uint32_t = 128 bits LoRa AES-128 key
// Загальний розмір регіону = 4 + 16 = 20 байт (було 4 + 32 = 36 для AES-256).
// CoAP AES-256 ключ для Queen↔Rails — окремий FLASH_COAP_KEY_ADDR slot (Load_CoAP_Key @boot).
//
// Якщо magic відсутній або ключ нульовий — пристрій не provisioned,
// Error_Handler() викликає software reset. Пристрій не може працювати
// без валідного ключа (BLOCKER-1 mitigation).
//
// Записується при Factory Flashing через SWD:
//   STM32CubeProgrammer --write key_payload.bin 0x0803E000
// Ключ деривується на backend: HKDF-SHA256(master_key, device_uid, "silken-aes-128-lora-key") [post-ARCH.42]
// Див. docs/03_06 §2 для повного протоколу.
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
// [ARCH.42 — закриває давній TODO] ЗАВАНТАЖЕННЯ CoAP AES-256 КЛЮЧА
// =========================================================================
// CommandBuilder (бекенд) ВЖЕ пише [KEYC][32B] на FLASH_COAP_KEY_ADDR для
// шлюзів — а прошивка досі не читала: coap_key лишався нулями, і жоден
// батч фабрично прошитої Королеви бекенд не зміг би розшифрувати.
// М'який fallback (НЕ Error_Handler, на відміну від LoRa-ключа): dev/sim
// плати без KEYC живуть як раніше; виявлення — бекендова decrypt-метрика.
static void Load_CoAP_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_COAP_KEY_ADDR;
    if (flash_ptr[0] != FLASH_COAP_KEY_MAGIC) return;  // не прошито — нулі лишаються
    uint32_t key_or = 0;
    for (int i = 0; i < FLASH_COAP_KEY_WORDS; i++) key_or |= flash_ptr[1 + i];
    if (key_or == 0) return;                           // битий provisioning
    for (int i = 0; i < FLASH_COAP_KEY_WORDS; i++) coap_key[i] = flash_ptr[1 + i];
}

// =========================================================================
// [L1 QATT] ЗАВАНТАЖЕННЯ Ed25519-СІМ'Ї ГОЛОСУ КОРОЛЕВИ
// =========================================================================
// [EDSK][seed:32] @ FLASH_ED25519_SEED_ADDR. Word→BE-байти РІВНО як
// Load_Lorenz_Seed (FW.30-конвенція): CommandBuilder пише hex-слова через
// `-w32`, тож на LE Cortex-M4 наївний memcpy перевернув би кожне слово —
// і деривований pubkey не зійшовся б із зареєстрованим на бекенді.
// crypto_ed25519_key_pair ВИТИРАЄ seed-копію (контракт Monocypher) —
// Flash недоторканий. Magic відсутній → ready = 0 → Flush шле
// legacy-формат: старий флот не ламається ні на байт.
static void Load_Ed25519_Seed(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_ED25519_SEED_ADDR;
    if (flash_ptr[0] != FLASH_ED25519_SEED_MAGIC) return;

    uint32_t seed_or = 0;
    for (int i = 0; i < FLASH_ED25519_SEED_WORDS; i++) seed_or |= flash_ptr[1 + i];
    if (seed_or == 0) return;                          // битий provisioning

    uint8_t seed[32];
    for (int i = 0; i < FLASH_ED25519_SEED_WORDS; i++) {
        uint32_t word = flash_ptr[1 + i];
        seed[i * 4 + 0] = (uint8_t)(word >> 24);
        seed[i * 4 + 1] = (uint8_t)(word >> 16);
        seed[i * 4 + 2] = (uint8_t)(word >> 8);
        seed[i * 4 + 3] = (uint8_t)(word & 0xFFu);
    }

    crypto_ed25519_key_pair(ed25519_secret, ed25519_pub, seed);  // seed wiped тут
    ed25519_ready = 1;
}

// =========================================================================
// ІНІЦІАЛІЗАЦІЯ КРИПТОГРАФІЇ
// =========================================================================
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType = CRYP_DATATYPE_32B;
  // Post-ARCH.42 Variant B (2026-05-23): LoRa-канал на AES-128 (вибір; SE = SE050 — 03_05 §3.7).
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
// Шлях розшифровування Королеви — дзеркало `Soldier_Build_CCM_LoRa_Packet`.
// Замкнено (`#define FW2_CCM_ENABLED 0`) до bench-атестації `CRYP_AES_CCM` HAL
// на кремнії. Host-тести у `firmware/test/test_ccm.c` верифікують через
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

// Розшифрувати 28-байтний CCM LoRa-пакет (wire-rev2) від Солдата.
// Повертає HAL_OK і заповнює:
//   *out_did, *out_fc           — з відкритого AAD (DID + FC24)
//   out_sensor[12]              — розшифрований сенсорний payload
// (gossip-байт AAD[4] Королеві не потрібен — вона має власний LTE-час;
//  він адресований Солдатам-сусідам і їде у CoAP-chunk як є.)
// Якщо MIC не б'ється, формат кривий або HAL захрип — повертає HAL_ERROR;
// ловець зобов'язаний дропнути пакет: ні ретрансляції, ні бекенду.
//
// Монотонність FC тут НЕ перевіряється — ця варта стоїть на Rails
// (`Cryptography::LoraCcm` + Redis SETNX per-DID). Queen-side dedup
// через `recent_mesh_dids` — майбутня ітерація при LoRa-штормах.
int Queen_Parse_CCM_LoRa_Packet(const uint8_t in_packet[FW2_CCM_AIR_PACKET_LEN],
                                uint32_t *out_did, uint32_t *out_fc,
                                uint8_t out_sensor[FW2_CCM_PLAINTEXT_LEN])
{
    if (!in_packet || !out_did || !out_fc || !out_sensor) return HAL_ERROR;

    uint32_t did =
        ((uint32_t)in_packet[0] << 24) | ((uint32_t)in_packet[1] << 16) |
        ((uint32_t)in_packet[2] << 8)  | (uint32_t)in_packet[3];
    uint8_t  gossip = in_packet[4];
    uint32_t fc =
        ((uint32_t)in_packet[5] << 16) | ((uint32_t)in_packet[6] << 8) |
        (uint32_t)in_packet[7];

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, gossip, fc, aad);

    // HAL_CRYPEx_AESCCM_Decrypt потребує одного буфера: шифротекст || MIC-тег.
    uint8_t ct_and_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    memcpy(ct_and_tag, &in_packet[8], FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN);

    MX_CRYP_Init_CCM_Decrypt(nonce, aad);
    int status = HAL_CRYPEx_AESCCM_Decrypt(&hcryp, ct_and_tag, FW2_CCM_PLAINTEXT_LEN,
                                           out_sensor, 1000);
    MX_CRYP_Init(); // Повертаємо ECB-режим: LoRa control-frames чекають свого ключа.

    if (status != HAL_OK) return HAL_ERROR;

    *out_did = did;
    *out_fc  = fc;
    return HAL_OK;
}
#endif // FW2_CCM_ENABLED || HAL_MOCK_CCM_ENABLED

// =========================================================================
// [PLAN 2.6] INDEPENDENT WATCHDOG (IWDG) — AUTO-RECOVERY FROM HANG
// =========================================================================
// Без Сторожового Пса Королева може зависнути назавжди при HardFault або
// глухому AT-діалозі з SIM7070G. Солдат вже давно під охороною (~26 с);
// тепер і Королева отримує рівноцінного варту.
// Формула таймауту: (Reload × Prescaler) / LSI = (3328 × 256) / 32000 ≈ 26.6 с.
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
//   [0x9C][unix_ts_be:u32][резерв:0×4][AUTH|TTL][магія 'B'][pad:0×5]
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
    // біт = TTL (BEACON_TTL=2 — Провідник несе на 1 хоп далі). Соціолог-
    // Солдат зчитує біт 7 у time_source_authoritative для mesh-арбітрації.
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
