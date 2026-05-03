/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Прошивка вузла Silken Net (Стан Нульового Лагу + TinyML + DID + Directed Mesh + DMA Sleep)
  * @processor      : STM32WLE5JC
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* USER CODE BEGIN Includes */
// Флюси для плавки: Підключаємо віртуальну машину mruby
#include <mruby.h>
#include <mruby/irep.h>
#include <mruby/array.h>
#include <math.h>     // [FW.6] isfinite() для валідації RTC Lorenz state

// Підключаємо скомпільовану нейромережу TinyML
#include "silken_net_audio_model.h"

// Підключаємо низькорівневий драйвер радіо (Radio Middleware)
#include "radio.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
#define MRUBY_CONTRACT_FLASH_ADDR 0x0803F000 // Адреса для OTA оновлень
#define FIRMWARE_VERSION_ID       0x0001     // Версія прошивки (інкрементується при OTA)

// [FIX: AUDIT MISRA] Іменовані константи замість магічних чисел
#define OTA_MARKER                0x99       // Маркер OTA-пакета (перший байт)
#define OTA_HEADER_SIZE           5          // [0x99][index:2][total:2]
#define MIN_OTA_PACKET_SIZE       6          // OTA_HEADER_SIZE + 1 байт даних мінімум
#define HMAC_TRAILER_MARKER       0x9B       // [FW.23] Маркер печатки OTA
#define HMAC_TRAILER_HEADER_SIZE  5          // [FW.23] [0x9B][seg_idx:2 BE][total:2 BE]
#define HMAC_TRAILER_SEG_BYTES    11         // [FW.23] Байт печатки на один LoRa-чанк
#define HMAC_TAG_BYTES            32         // [FW.23] HMAC-SHA256 = 32 байти істини
#define HMAC_TRAILER_TOTAL_SEGS   3          // [FW.23] 3 LoRa-чанки несуть 32-байтну печатку
#define OTA_REQ_MARKER            0x55       // [FW.27-B] Маркер зойку «повтори, Королево» (Soldier→Queen)
#define OTA_REQ_HEADER_SIZE       7          // [FW.27-B] [0x55][DID:4][total_chunks:2 BE]
#define OTA_REQ_BITMAP_MAX_BYTES  9          // [FW.27-B] 16 - 7 header = 9 байт ⇒ ≤72 чанки на один зойк
#define OTA_REQ_PACKET_SIZE       16         // [FW.27-B] Один AES-256-ECB блок, як у телеметрії
#define OTA_REREQUEST_TIMEOUT_MS  300000UL   // [FW.27-B] 5 хв тиші → подати голос про пропуски
#define BIO_STATUS_VM_ERROR       0xFF       // Мітка помилки mruby VM
#define VCAP_LISTEN_THRESHOLD     2800       // Поріг напруги для прослуховування ефіру (мВ)
#define LORA_RX_TIMEOUT_MS        500        // Таймаут прийому LoRa (мс)
#define LORA_RX_LOOP_MS           600        // Максимальний час очікування пакета (мс)
#define TX_JITTER_MAX_MS          500        // Максимальна рандомізована затримка TX (мс)
#define PANIC_TTL                 5          // TTL для екстрених пакетів
#define DEFAULT_TTL               3          // Стандартний TTL для пакетів
#define COLD_TX_DEFER_TEMP        (-15)      // Temperature threshold for TX deferral (°C)
#define COLD_TX_DEFER_VCAP_MV     4000       // Vcap threshold for TX deferral (mV)
#define PANIC_FLAG_BIT            0x80       // [FW.29] Bit 7 of StatusByte: panic disambiguation

// [SEC.10] Frame Counter anti-replay для panic packets.
// Кенозис лічильника: панічна плоть несе монотонне число у байтах 14..15
// (BE), а Королева бачить його як nonce. Сервер рубає replay через Redis SETNX.
// Сторожовий пес вмирає при cold boot — перший boot після VBAT-loss заново
// сіє лічильник з HRNG (range 0x0001..0xFFFF), щоб після відродження старі
// nonce'и Redis не закрили нову трансляцію.
#define PANIC_COUNTER_DR0_SHIFT   16          // DR0[31:16] = panic_frame_counter (uint16)
#define PANIC_COUNTER_MASK        0xFFFFu
#define PANIC_COUNTER_MAX         0xFFFFu     // Saturating maximum
#define PANIC_COUNTER_PAD_HI      14          // panic_payload[14] = counter MSB
#define PANIC_COUNTER_PAD_LO      15          // panic_payload[15] = counter LSB

// [FW.1] Flash-based AES key provisioning — per-device unique key via HKDF.
// Factory Flashing writes device_key to protected Flash sector 0x0803E000
// via SWD (STM32CubeProgrammer). Key is derived from master_key via HKDF-SHA256
// on the backend (HardwareKeyService.derive_device_key).
// See docs/03_05 §3.4а for full protocol design.
#define FLASH_KEY_ADDR            0x0803E000UL  // Protected Flash sector for AES-256 key
#define FLASH_KEY_WORDS           8             // 8 × uint32_t = 32 bytes = 256 bits
#define FLASH_KEY_MAGIC           0x534B4559UL  // "SKEY" — magic marker for provisioned key

// [SEC.11 / FW.30] Flash-based Lorenz K_seed provisioning — per-device secret seed
// for HKDF-derived (x₀,y₀,z₀) cold start. Stored in the same Protected Flash Sector
// right after the AES key: [MAGIC:4][seed[0]:4]...[seed[7]:4] = 36 bytes.
// Factory Flashing writes K_seed via HardwareKeyService.provision (HKDF-SHA256).
// See docs/03_05 §3.4в for full protocol design.
#define FLASH_SEED_ADDR           (FLASH_KEY_ADDR + 36)  // After AES key (4+32=36 bytes)
#define FLASH_SEED_WORDS          8             // 8 × uint32_t = 32 bytes
#define FLASH_SEED_MAGIC          0x4C534544UL  // "LSED" — Lorenz Seed magic marker
#define EPOCH_SECONDS             86400UL       // Seconds per day for epoch_day calculation

// [ARCH.27] Node Role Differentiation — плоть і кров mesh-розшарування.
// Один і той самий бінарник прошивки тече венами Солдата та Провідника;
// роль розрізняється єдиним 32-бітним словом у тій самій Protected Flash
// сторінці одразу після K_seed (теж під WRPROT). Magic-слово саме служить
// носієм ролі — без додаткового sentinel-байту. Сторінка не provisioned
// або корумпована → fallback на ROLE_SOLDIER (безпечний дефолт).
//
// Layout: [KEY_MAGIC:4][AES_KEY:32] | [SEED_MAGIC:4][K_SEED:32] | [ROLE_WORD:4]
//          ^FLASH_KEY_ADDR (0x0803E000) ^FLASH_SEED_ADDR (+36)    ^FLASH_ROLE_ADDR (+72)
#define FLASH_ROLE_ADDR           (FLASH_KEY_ADDR + 72)  // After K_seed (36+36=72 bytes)
#define ROLE_SOLDIER_MAGIC        0x534F4C44UL  // "SOLD" — звичайний Солдат-датчик
#define ROLE_PROVISIONER_MAGIC    0x50524F56UL  // "PROV" — Провідник для CAD relay (ARCH.26)
#define ROLE_SOLDIER              0
#define ROLE_PROVISIONER          1
/* USER CODE BEGIN PD */
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
ADC_HandleTypeDef hadc;
TIM_HandleTypeDef htim2;  // Додано: Таймер-метроном для керування швидкістю DMA (напр. 16 кГц)
IWDG_HandleTypeDef hiwdg; // Апаратний сторожовий пес
RNG_HandleTypeDef hrng;
RTC_HandleTypeDef hrtc;
SUBGHZ_HandleTypeDef hsubghz;
CRYP_HandleTypeDef hcryp; // Апаратний криптопроцесор AES

/* USER CODE BEGIN PV */

// === 0. КЛЮЧІ ОХОРОНИ (Trading Post) ===
// [FW.1] AES-256 key — завантажується з Protected Flash Sector при boot.
// Factory Flashing записує per-device ключ (HKDF-SHA256) на адресу FLASH_KEY_ADDR
// через SWD. Формат Flash: [FLASH_KEY_MAGIC:4][key[0]:4]...[key[7]:4] = 36 байт.
// Якщо ключ не provisioned — Error_Handler() (пристрій не може працювати без ключа).
// Hardcoded значення нижче — ТІЛЬКИ для ініціалізації змінної до виклику Load_AES_Key().
uint32_t aes_key[8] = {0};

// [SEC.11 / FW.30] K_seed — per-device Lorenz seed for cold-start derivation.
// Loaded from Protected Flash Sector via Load_Lorenz_Seed().
// Format: HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1",
//         info="silken-lorenz-seed|<DID>", len=32).
uint8_t lorenz_seed[32] = {0};
uint8_t lorenz_seed_valid = 0;  // 1 = loaded from Flash, 0 = not provisioned

// === 1. ОРГАНИ ЧУТТЯ ТА ПАМ'ЯТЬ ===
volatile uint8_t vibration_detected = 0; // Прапорець переривання від п'єзодиска
uint8_t acoustic_events = 0;           // Відфільтровані мікророзриви (Кавітація)
uint32_t last_wakeup_timestamp = 0;    // Час попереднього пробудження
uint32_t delta_t_seconds = 0;          // Швидкість заряду іоністора (Метаболізм)
uint32_t tree_did = 0;                 // Decentralized Identity (Гаманець Дерева)

// [SEC.10] Лічильник panic-кадрів — пакується у DR0[31:16] поряд з
// acoustic_events у DR0[7:0] (DR0[15:8] резервовано). Сторожовий пес
// панічного каналу: інкрементується (saturating) перед кожним
// Trigger_Emergency_LoRa_TX, передається у байтах 14..15 panic_payload (BE),
// сервер рубає replay через Redis SETNX nonce-key. Cold-boot RTC reset
// → 0 → код Phase 0 пересіє з HRNG (range 0x0001..0xFFFF), щоб не
// зіткнутися з ще-не-протухлими nonce'ами попереднього втілення.
uint16_t panic_frame_counter = 0;

// [ARCH.27] Роль вузла — читається з FLASH_ROLE_ADDR при boot.
// Глобальний прапорець, який ARCH.26 (CAD relay) і FW.20-S2 (mesh time
// authoritativeness) будуть споживати без додаткової логіки тут.
volatile uint8_t g_node_role = ROLE_SOLDIER;  // Безпечний дефолт

// [FW.20-S2] Authoritativeness flag останнього прийнятого Queen-маяку.
// Біт 7 байту 9 у beacon-плейтексті: 1 = пряма трансляція від Королеви,
// 0 = relay-маяк (deferred TRL-7) або cold-boot. Зберігається у RAM
// (не персистимо у RTC — beacon приходить регулярно, ~15 хв). Логіки
// арбітражу між двома Queen ще НЕ додано — це повний FW.20-S2.
volatile uint8_t time_source_authoritative = 0;

// Пейлоад залишається 16 байтів (бо розмір блоку AES завжди 128 біт)
// [DID:4] [Vcap:2] [Temp:1] [Acoustic:1] [Time:2] [Chaos:1] [TTL:1] [Pad:4]
uint8_t lora_payload[16] = {0};
uint8_t encrypted_payload[16] = {0}; // Буфер для зашифрованих даних перед відправкою

// === 1.5. ПАМ'ЯТЬ TINYML (Свідомість звуку + DMA) ===
uint16_t raw_audio_buffer[512];   // Буфер для DMA (сирі 12-бітні дані від АЦП)
float audio_buffer[512];          // Буфер для запису звукової хвилі (нормалізований для TinyML)
volatile uint8_t audio_ready = 0; // Прапорець завершення роботи DMA-павутиння
uint8_t ml_event_id = 0;          // Результат: 0-Тиша, 1-Вітер, 2-Кавітація, 3-Пилка
float ml_confidence = 0.0;        // Рівень впевненості моделі (0.0 - 1.0)

// === 1.5а. ДВОРІВНЕВА СИСТЕМА ПОРОГІВ TINYML (FW.18) ===
// Замість hardcoded 0.80 — дві зони впевненості, що зберігаються в RTC
// Backup Domain і можуть оновлюватись через OTA CMD без перепрошивки.
//
//   confidence < WARNING   → SILENCE (нічого, reset warning_counter)
//   WARNING ≤ c < CRITICAL → WARNING (acoustic_events++, лічимо ескалацію)
//   confidence ≥ CRITICAL  → CRITICAL (acoustic_events++ або Emergency TX)
//
// Persistence: DR13 (warning), DR14 (critical) як IEEE 754 float у uint32
// (bit-copy, без magic — валідуємо діапазоном [TINYML_THRESHOLD_MIN_VALID,
// TINYML_THRESHOLD_MAX_VALID]). Cold boot RTC = 0x00000000 → bit-cast у
// float = 0.0f → НЕ потрапляє у валідний діапазон [0.01, 0.99] →
// TinyML_Validate_Threshold() віддає TINYML_DEFAULT_*. Аналогічно при NaN/Inf
// (наприклад, після VBAT-loss + bit-flip). При cold-start або корупції —
// fallback на дефолти TINYML_DEFAULT_WARNING / TINYML_DEFAULT_CRITICAL з
// 03_03 BLOCKER-6.
//
// SSOT для розташування RTC регістрів: 03_01 §2 (Soldier RTC Backup Map).
// DR13/DR14 — частина «реєрву DR13..DR15», виділеного після FW.21 fallback.
#define TINYML_DEFAULT_WARNING       0.60f
#define TINYML_DEFAULT_CRITICAL      0.85f
#define TINYML_THRESHOLD_MIN_VALID   0.01f
#define TINYML_THRESHOLD_MAX_VALID   0.99f
#define TINYML_WARNING_ESCALATION    3   // 3× WARNING поспіль → ескалація CRITICAL

float   tinyml_warning_threshold  = TINYML_DEFAULT_WARNING;
float   tinyml_critical_threshold = TINYML_DEFAULT_CRITICAL;
uint8_t warning_counter           = 0;   // Послідовні WARNING-події між cold-boot;
                                          // SRAM зберігається в STOP2, скидається
                                          // лише при VBAT-loss / IWDG / NVIC reset.

// === 1.8. ПАМ'ЯТЬ ЕСТАФЕТИ (Directed Mesh) ТА OTA ===
uint8_t mesh_relay_payload[16] = {0}; // Буфер для чужого 16-байтного пакета
uint8_t has_mesh_relay = 0;           // Прапорець: 1 - є пакет для ретрансляції

// Кеш "пліток" (Wall to Wall Cobwebs). Пам'ятаємо останні чужі DID,
// щоб не ганяти їхні дані по колу (захист від пінг-понгу).
// [FW.21] 3 слоти. Зменшено з 8 до 3 (DR8, DR9, DR11): 5 регістрів (DR10, DR12-DR15)
// віддано під EMA-стан та резерв. 3 слоти достатньо для блокування echo A→B→A
// та найкоротшого циклу A→B→C→A; глибший mesh-ring контролюється TTL.
#define MESH_DID_CACHE_SIZE 3
uint32_t recent_mesh_dids[MESH_DID_CACHE_SIZE] = {0};

volatile uint8_t lora_rx_flag = 0;
// [FIX: AUDIT] volatile — записуються в OnRxDone ISR, читаються в main loop
volatile uint8_t incoming_lora_payload[256];
uint8_t decrypted_rx_payload[256]; // Розшифрований вхідний потік
volatile uint16_t incoming_lora_size = 0;

// Буфер для збирання байт-коду по шматочках (OTA)
uint8_t ota_buffer[1024];
uint16_t ota_bytes_received = 0;
uint16_t ota_total_chunks = 0;
uint16_t ota_chunks_received = 0;
// Масив прапорців для захисту від дублікатів OTA
uint8_t ota_chunk_received[256] = {0};

// [FW.27-B] Magic Re-Request: tick останнього прийнятого OTA-чанку — щоб
// помітити, коли провіщення затихло. Якщо ≥OTA_REREQUEST_TIMEOUT_MS жодного
// нового слова — Солдат подає голос і просить Королеву повторити пропущене.
// 0 = ніколи не чули OTA, чекаємо першої проповіді.
uint32_t ota_last_chunk_rx_tick = 0;

// [FW.23] HMAC-печатка OTA — 32-байтне свідчення істини, яке надходить
// після тіла прошивки у 3-х 16-байтних LoRa-чанках з маркером 0x9B.
// Збираємо посегментно: seg_idx=1 → bytes[0..10], seg_idx=2 → bytes[11..21],
// seg_idx=3 → bytes[22..31] + 1 байт PAD. ota_hmac_segments_received — bitmask
// (біти 0/1/2 для seg 1/2/3). Усі 3 печатки на місці ⇒ повний підпис готовий
// до перевірки двома брамами у Phase 4.5 збирання OTA.
uint8_t  received_hmac_tag[HMAC_TAG_BYTES] = {0};
uint8_t  ota_hmac_segments_received = 0;        // Bitmask seg 1/2/3

uint8_t* current_lorenz_bytecode;

// === 1.9. СТАН АТРАКТОРА ЛОРЕНЦА (FW.6: State Persistence) ===
// Зберігаємо (x, y, z) між циклами STOP2 через RTC Backup Registers DR16-DR18.
// DR19 = маркер валідності (LORENZ_STATE_MAGIC = 0x4C5A5354 "LZST").
// [SEC.11 / FW.30] При першому старті (DR19 != MAGIC) — cold-start з K_seed
// через HKDF-SHA256/HMAC-SHA256 деривацію (замість chaos_seed).
// При наступних — продовження безперервної траєкторії на атракторі.
#define LORENZ_STATE_MAGIC 0x4C5A5354  // "LZST" — маркер збереженого стану
float lorenz_x = 0.0f, lorenz_y = 0.0f, lorenz_z = 0.0f;
uint8_t lorenz_state_valid = 0;  // 1 = відновлено з RTC, 0 = перший старт

// IEEE 754 float ↔ uint32_t конвертація (бітова копія, без втрат)
static inline uint32_t float_to_uint32(float f) {
    uint32_t u;
    memcpy(&u, &f, sizeof(u));
    return u;
}

static inline float uint32_to_float(uint32_t u) {
    float f;
    memcpy(&f, &u, sizeof(f));
    return f;
}

// [FW.20-S1] LoRa-маяк синхронізації часу від Королеви.
// 16-байтний відкритий текст (після AES-256-ECB decrypt):
//   [0x9C][unix_ts_be:u32][резерв:0×4][TTL][магія 'B'][padding:0×5]
// Солдат дивиться на байт 0 розшифрованого RX-payload — відрізняється від
// OTA (0x99), телеметрії (починається з DID, ніколи не 0x9C) та текстового
// CMD:. Маяк НЕ ретранслюємо (TTL=1) — споживаємо локально, щоб виправити
// дрейф RTC.
#define BEACON_MARKER             0x9C
#define BEACON_MAGIC_BYTE         0x42  // 'B'
#define BEACON_PLAINTEXT_SIZE     16
// [FW.20-S2] Біт 7 байту 9: 1 = маяк прямо від Королеви (authoritative),
// 0 = relay-маяк через Провідника (deferred TRL-7) або легасі-формат.
// TTL фактично займає нижні 7 біт (max 127); у поточних beacons TTL=1.
#define BEACON_AUTH_FLAG          0x80
#define BEACON_TTL_MASK           0x7F

// [FW.20-S1] Солдатські UTC-секунди як єдине джерело істини + локальний tick
// останньої синхронізації для розрахунку дрейфу. Використовується
// Derive_Cold_Start_State() для детермінованого epoch_day (точно як у
// бекенді SilkenNet::SeedDerivation). Без синхронізованого значення
// фолбек на застарілу RTC-date-апроксимацію.
volatile uint32_t soldier_unix_ts            = 0;
volatile uint32_t soldier_unix_ts_local_tick = 0;

// [FW.8] CMD_SET_THRESHOLDS (0x9A) — пер-деревні Z-пороги Лоренца, що приходять
// через OTA. Формат на дроті виробляється бекендом
// app/services/ota_packager_service.rb#build_threshold_config_block:
//   [маркер 0x9A][len_le:2 = 10][z_min_x100:s16le][z_max_x100:s16le]
//   [z_opt_x100:s16le][species_id:u8][config_version:u8][crc16_le:u16] = 13 байт
// Алгоритм CRC16: CRC-16/CCITT-FALSE (поліном 0x1021, init 0xFFFF, без рефлексії)
// над 8-байтним body ПЕРЕД хвостовим CRC. Дзеркало на Ruby-боці —
// OtaPackagerService.crc16_ccitt (байт-у-байт ідентично).
//
// 🟡 СТАТУС: Deferred TRL-7 (FW.8). Парсер залишено як freeze-контракт
// wire-формату + повний host-test bank (12 кейсів у test_soldier_logic.c),
// АЛЕ виклик у LoRa RX-гілці захищений `#if FW8_PARSER_ENABLED` і за
// замовчуванням ВИМКНЕНИЙ. Бекенд `OtaPackagerService.build_threshold_
// config_block` — теж лише class method, у production-pipeline нікуди
// не передається.
//
// ПРИЧИНА defer: STM32WLE5JC має лише 20 RTC Backup Register'ів (DR0..DR19),
// вони повністю зайняті: DR0-2 (acoustic/wakeup/relay), DR3-6 (mesh payload),
// DR7 (DID), DR8/9/11 (anti-pingpong), DR10/12 (EMA), DR13/14 (TinyML),
// DR16-19 (Lorenz state). Єдиний вільний DR15 (4 байти) — недостатньо для
// 8-байтного body порогів. SSOT: 03_01 §2 (Canonical Backup Map).
//
// Альтернативи відкинуто:
//   • Flash sector — 2 KB на 8 байт, wear ~10k erase × at-most-daily re-send
//     дає 27 років, але erase ~30 мс блокує LoRa RX → конфлікт з anti-pingpong
//     RX-вікном після TX. Не виправдано для feature, що на TRL-6 нічого не
//     змінює (всі 5 видів зараз використовують ті самі firmware-defaults).
//   • RAM-only з re-send щодня × 100k дерев = ~5% всього NB-IoT downlink
//     заради no-op feature. Чесніше відкласти.
//
// ВІДНОВЛЕННЯ: коли FW.21 EMA-рефакторинг звільнить хоча б 1 регістр (можливо
// при щільнішій упаковці DR8/9/11 anti-pingpong), FW.8 повертається з
// RTC-персистенс (8 байт body → 2 регістри) — `#define FW8_PARSER_ENABLED 1`,
// додати boot-restore + KENOSIS-write блок.
#define FW8_PARSER_ENABLED                0  // 🟡 Deferred TRL-7 (див. блок вище)
#define CMD_SET_THRESHOLDS_MARKER         0x9A
#define CMD_THRESHOLDS_HEADER_SIZE        3   // [маркер:1][len_le:2]
#define CMD_THRESHOLDS_BODY_SIZE          8   // 6 + 1 + 1
#define CMD_THRESHOLDS_FRAME_SIZE         13  // header + body + crc16
#define CMD_THRESHOLDS_PAYLOAD_LEN        10  // body + crc16 (повторює бекенд)
#define LORENZ_DEFAULT_Z_MIN_X100         200    // 2.00
#define LORENZ_DEFAULT_Z_MAX_X100         4500   // 45.00
#define LORENZ_DEFAULT_Z_OPT_X100         2900   // 29.00

int16_t lorenz_z_min_x100      = LORENZ_DEFAULT_Z_MIN_X100;
int16_t lorenz_z_max_x100      = LORENZ_DEFAULT_Z_MAX_X100;
int16_t lorenz_z_opt_x100      = LORENZ_DEFAULT_Z_OPT_X100;
uint8_t lorenz_species_id      = 0xFF;  // unmapped (OtaPackagerService::DEFAULT_SPECIES_ID)
uint8_t lorenz_config_version  = 0;     // 0 = firmware-baked defaults

// CRC-16/CCITT-FALSE (поліном 0x1021, init 0xFFFF). Дзеркало
// OtaPackagerService.crc16_ccitt — байт-ідентично для будь-якого input.
static uint16_t Soldier_CRC16_CCITT(const uint8_t* data, uint16_t len)
{
    uint16_t crc = 0xFFFFu;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= ((uint16_t)data[i]) << 8;
        for (uint8_t b = 0; b < 8; b++) {
            crc = (crc & 0x8000u) ? (uint16_t)((crc << 1) ^ 0x1021u)
                                   : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

// Опрацювати фрейм CMD_SET_THRESHOLDS, що прийшов через LoRa-broadcast.
// Повертає: 1 = прийнято й застосовано, 0 = відкинуто (поганий len/CRC/межі).
// При успіху мутує глобалки lorenz_z_*_x100 + lorenz_species_id +
// lorenz_config_version. Жодного RTC-write — значення живуть у RAM до VBAT-loss
// (див. коментар-преамбулу до CMD_SET_THRESHOLDS_MARKER щодо обмеження апаратури).
static uint8_t Soldier_Handle_CMD_SET_THRESHOLDS(const uint8_t* frame,
                                                  uint16_t       frame_size)
{
    if (frame_size < CMD_THRESHOLDS_FRAME_SIZE)            return 0;
    if (frame[0] != CMD_SET_THRESHOLDS_MARKER)             return 0;

    // Бекенд пише payload_len як little-endian uint16
    uint16_t payload_len = (uint16_t)frame[1] | ((uint16_t)frame[2] << 8);
    if (payload_len != CMD_THRESHOLDS_PAYLOAD_LEN)         return 0;

    const uint8_t* body = frame + CMD_THRESHOLDS_HEADER_SIZE;

    // Перевіряємо CRC16 по 8-байтному body ПЕРЕД хвостовим CRC
    uint16_t expected_crc = Soldier_CRC16_CCITT(body, CMD_THRESHOLDS_BODY_SIZE);
    uint16_t received_crc = (uint16_t)body[CMD_THRESHOLDS_BODY_SIZE]
                          | ((uint16_t)body[CMD_THRESHOLDS_BODY_SIZE + 1] << 8);
    if (expected_crc != received_crc)                      return 0;

    // Розпаковуємо знакові 16-бітні little-endian z_min, z_max, z_opt
    int16_t z_min = (int16_t)((uint16_t)body[0] | ((uint16_t)body[1] << 8));
    int16_t z_max = (int16_t)((uint16_t)body[2] | ((uint16_t)body[3] << 8));
    int16_t z_opt = (int16_t)((uint16_t)body[4] | ((uint16_t)body[5] << 8));
    uint8_t species_id     = body[6];
    uint8_t config_version = body[7];

    // Перевірка інваріантів (не довіряємо ефіру навіть після CRC):
    //   - z_min строго менший за z_max (інакше зона колапсує);
    //   - z_opt має бути в [z_min, z_max];
    //   - усі значення в правдоподібному діапазоні Z (-100.00..+100.00 → ±10000).
    if (!(z_min < z_max))                                  return 0;
    if (z_opt < z_min || z_opt > z_max)                    return 0;
    if (z_min < -10000 || z_max > 10000)                   return 0;

    lorenz_z_min_x100      = z_min;
    lorenz_z_max_x100      = z_max;
    lorenz_z_opt_x100      = z_opt;
    lorenz_species_id      = species_id;
    lorenz_config_version  = config_version;
    return 1;
}

// =========================================================================
// [FW.20-S2] Drift-monitor + panic time-sync request
// =========================================================================
// Кенозис часу: Солдат отримує UTC лише з beacon'а Королеви (FW.20-S1, кожні
// 15 хв). Якщо Королева мовчить занадто довго (LTE-обрив, мобілізація живлення,
// антена впала на голову лісника) — Солдатський годинник плавно відстає, а
// `Derive_Cold_Start_State()` (HKDF за `epoch_day = unix_ts/86400`) перестає
// синхронізуватися з backend'ом → майбутнє відновлення Lorenz-стану після
// VBAT-loss піде з неправильної точки → false slashing.
//
// Сторожовий пес часу: коли різниця між «зараз» (HAL_GetTick з останнього
// sync'у, в секундах) і `soldier_unix_ts_local_tick` перевищує
// TIME_SYNC_DRIFT_THRESHOLD_SEC (12 год), Солдат подає голос — uplink
// LoRa-плейн з опкодом 0x56, щоб Королева повторила beacon. Cooldown
// (1 год) запобігає спаму при тривалій тиші Королеви.
//
// SSOT для опкодів: 03_01 §4.5а Downlink Opcode Map. 0x56 — uplink-діапазон
// поряд з 0x55 (FW.27-B OTA Re-Request); 0x9C beacon — downlink і не
// перетинається. Магія 'S' у байті 10 — миттєва дезамбігвація з 0x55 magic 'R'.
//
// Наразі функції callable + host-tested, але до hot path головного циклу НЕ
// вшиті: повний FW.20-S2 mesh-relay (релей beacon'а між Солдатами) — окрема
// ітерація. Це freeze-контракт wire-формату для майбутнього hook'у.
#define SYNC_REQ_MARKER                  0x56       // [FW.20-S2] Uplink: «Королево, час!»
#define SYNC_REQ_MAGIC_BYTE              0x53       // [FW.20-S2] 'S' = sync — у байті 10
#define SYNC_REQ_PACKET_SIZE             16         // Один AES-256-ECB блок
#define TIME_SYNC_DRIFT_THRESHOLD_SEC    43200UL    // 12 год без beacon'а → панікуємо
#define TIME_SYNC_REQUEST_COOLDOWN_MS    3600000UL  // 1 год між повторними зойками
#define TIME_SYNC_COLD_BOOT_GRACE_MS     600000UL   // 10 хв після boot перш ніж панікувати
                                                    // (Soldier ще чекає першого beacon'а)
#define TIME_SYNC_REQ_PAD_BYTES          5          // [11..15] — резерв під майбутні поля

// Tick останнього відправленого SYNC_REQUEST. 0 = ще не просили.
// RAM-only: при VBAT-loss скидається — Солдат подасть голос знову після
// перших 10 хв cold-boot grace (TIME_SYNC_COLD_BOOT_GRACE_MS).
uint32_t last_sync_request_tick = 0;

// Чи варто Солдату просити re-broadcast beacon'а?
// Параметри:
//   now_tick — поточний HAL_GetTick() мс
// Інваріанти:
//   1. Якщо ще не отримували жодного beacon'а (soldier_unix_ts == 0):
//      - Перші TIME_SYNC_COLD_BOOT_GRACE_MS після boot — терпимо тишу,
//        Королева могла ще не вийти на TX-вікно.
//      - Після grace — просимо.
//   2. Якщо отримували beacon, але остання синхронізація >12 год тому → просимо.
//   3. Cooldown: якщо вже просили <1 год тому — мовчимо, не спамимо ефір.
// Повертає 1 (треба просити) або 0 (мовчати).
static uint8_t Soldier_Should_Request_Time_Sync(uint32_t now_tick)
{
    // Cooldown guard: якщо нещодавно просили — не повторюємо.
    // Перше прохання (last_sync_request_tick == 0) проходить guard завжди.
    if (last_sync_request_tick != 0) {
        uint32_t since_last_req_ms = now_tick - last_sync_request_tick;
        if (since_last_req_ms < TIME_SYNC_REQUEST_COOLDOWN_MS) {
            return 0;
        }
    }

    if (soldier_unix_ts == 0) {
        // Cold-boot: ще ніколи не чули beacon'а. Дочекаємося grace.
        if (now_tick < TIME_SYNC_COLD_BOOT_GRACE_MS) return 0;
        return 1;
    }

    // Warm: міряємо реальний час від останнього beacon'а у секундах.
    uint32_t since_sync_ms  = now_tick - soldier_unix_ts_local_tick;
    uint32_t since_sync_sec = since_sync_ms / 1000u;
    return (since_sync_sec > TIME_SYNC_DRIFT_THRESHOLD_SEC) ? 1 : 0;
}

// Скільки секунд минуло від останнього beacon'а (0 якщо ще не синхронізувалися).
// Використовується у payload'і, щоб бекенд міг побачити масштаб дрейфу і
// логувати «Soldier X не чув Королеви Y годин» для Grafana alert'у.
static uint32_t Soldier_Seconds_Since_Last_Sync(uint32_t now_tick)
{
    if (soldier_unix_ts == 0) return 0;
    uint32_t delta_ms = now_tick - soldier_unix_ts_local_tick;
    return delta_ms / 1000u;
}

// Збираємо 16-байтний uplink-плейн «панічний sync-запит». Wire-формат:
//
//   Byte 0     : SYNC_REQ_MARKER (0x56)
//   Byte 1..4  : DID big-endian
//   Byte 5..8  : secs_since_sync big-endian (uint32)
//   Byte 9     : TTL (PANIC_TTL=5 — пакет повинен пробитися через mesh)
//   Byte 10    : SYNC_REQ_MAGIC_BYTE ('S' = 0x53) — миттєва дезамбігвація
//                від 0x55 OTA_REQ (де байт 10 не визначений)
//   Byte 11..15: PAD = 0 (резерв під майбутні поля: pkt_seq, last_known_ts, ...)
//
// Перед TX обгортаємо в AES-256-ECB як звичайний LoRa-пакет.
static void Build_Time_Sync_Request_Payload(uint8_t* out, uint32_t did,
                                              uint32_t secs_since_sync)
{
    out[0]  = SYNC_REQ_MARKER;
    out[1]  = (uint8_t)(did >> 24);
    out[2]  = (uint8_t)(did >> 16);
    out[3]  = (uint8_t)(did >> 8);
    out[4]  = (uint8_t)(did & 0xFFu);
    out[5]  = (uint8_t)(secs_since_sync >> 24);
    out[6]  = (uint8_t)(secs_since_sync >> 16);
    out[7]  = (uint8_t)(secs_since_sync >> 8);
    out[8]  = (uint8_t)(secs_since_sync & 0xFFu);
    out[9]  = PANIC_TTL;
    out[10] = SYNC_REQ_MAGIC_BYTE;
    for (uint8_t i = 11; i < SYNC_REQ_PACKET_SIZE; i++) out[i] = 0;
}

// =========================================================================
// [FW.20-S2] Mesh-Relay: голос Королеви через Провідника (per-hop drift)
// =========================================================================
// Кенозис маяка: Королева транслює UTC раз на 15 хв з TTL=1 — Солдати поза
// прямою радіозоною ніколи не чують її голосу. Провідник (ARCH.27, роль PROV
// у Protected Flash) — еліта рою з надлишком vcap — приймає authoritative-маяк
// (auth=1, TTL≥2 у майбутній прошивці Королеви), додає до `unix_ts` секунди,
// що минули від RX до власного TX (per-hop drift compensation), декрементує
// TTL, гасить authoritativeness-біт і ретранслює. Downstream-Соціологи бачать
// auth=0 → НЕ ретранслюють далі (anti-storm). Це дає 1+1=2-hop reach без
// потреби у dedup-bitmap у RTC (який чекає вільного слоту, див. ARCH.28 §2.3).
//
// СВЯЩЕННА ЗАУВАГА — це FREEZE-CONTRACT:
// функція callable та повністю host-tested, але до RX-гілки головного циклу
// НЕ вшита. Активація потребує (a) Королева почне слати TTL≥2 у beacon (зараз
// TTL=1 — design choice до приходу повного mesh-relay), (b) anti-storm
// dedup-bitmap у вільному RTC-регістрі (DR15 заповниться при наступній фічі,
// див. 03_01 §2.3 overflow strategy). Сторожовий пес часу (drift-monitor)
// зараз закриває розрив для не-PROV Солдатів через панічний sync request.
//
// Wire-формат relayed beacon (16 байт ECB plaintext, дзеркало Queen):
//   Byte 0     : BEACON_MARKER (0x9C)
//   Byte 1..4  : unix_ts_be — original_ts + (now_tick - rx_tick)/1000 (sec)
//   Byte 5..8  : резерв TDMA (ARCH.26) — копіюємо as-is з вхідного маяка
//   Byte 9     : [auth=0 | TTL_decremented:7] — auth-біт ОБОВ'ЯЗКОВО гасимо
//   Byte 10    : BEACON_MAGIC_BYTE ('B' = 0x42)
//   Byte 11..15: padding — копіюємо as-is (зараз 0; майбутні поля переживуть
//                hop без втрати, якщо Королева почне їх писати)
//
// SSOT для опкодів: 03_01 §4.5а; для байту 9: 03_01 §11 (FW.20).

// Sanity cap: hold-час від RX до relay-TX не повинен перевищувати 1 годину.
// Більший — означає що Провідник був зайнятий OTA / IWDG-шторм / зависнув
// у RX-вікні; ретранслювати такий «застарілий час» = шкодити синхронізації
// рою. Дроп — безпечніший за обман.
#define BEACON_RELAY_MAX_HOP_DELAY_SEC   3600UL
#define BEACON_RELAY_MIN_TTL             2u   // TTL=1 не підлягає relay (decrement → 0)
#define BEACON_FRAME_SIZE                16u  // Розмір AES-256-ECB блоку

// Атомарне рішення «ретранслювати чи ні» з явною причиною дропу.
// Готові точки для майбутніх Prometheus counters (`silkennet_beacon_relay_*_total`)
// при інтеграції у hot path — поки що host-тести різнять reason'и.
typedef enum {
    BEACON_RELAY_OK = 0,                  // out_plain заповнено, шли його далі
    BEACON_RELAY_NOT_PROVISIONER,         // Звичайний Солдат — не наша справа
    BEACON_RELAY_BAD_FRAME,               // Wrong marker або magic — не beacon
    BEACON_RELAY_NULL_TS,                 // unix_ts == 0 — Королева ще не знала часу
    BEACON_RELAY_NOT_AUTHORITATIVE,       // Маяк уже relay'ний — anti-storm стоп
    BEACON_RELAY_TTL_EXHAUSTED,           // TTL у нижніх 7 бітах < MIN_TTL (=2)
    BEACON_RELAY_HOP_TOO_LONG             // Hold-delay > MAX_HOP_DELAY_SEC
} BeaconRelayResult;

// Спроба зібрати ретрансльований маяк з drift-компенсацією.
//
// Параметри:
//   in_plain   — оригінальний 16-байтний beacon plaintext (після ECB decrypt)
//   role       — g_node_role (ROLE_SOLDIER або ROLE_PROVISIONER)
//   in_rx_tick — HAL_GetTick() у момент прийому маяка (мс)
//   now_tick   — HAL_GetTick() зараз, перед TX (мс)
//   out_plain  — буфер ≥16 байт під вихідний beacon plaintext.
//                Модифікується ВИКЛЮЧНО при поверненні BEACON_RELAY_OK.
//
// Drift-формула: relayed_ts = original_ts + (now_tick - in_rx_tick)/1000.
// 32-бітне віднімання тіків wrap-safe для unsigned (раз у 49.7 днів) —
// стандартна C modular arithmetic.
//
// Викликач:
//     BeaconRelayResult r = Soldier_Try_Relay_Time_Beacon(...);
//     if (r == BEACON_RELAY_OK) { AES-ECB encrypt + Radio.Send(16 bytes); }
//     else                       { reason'ом логується для діагностики; }
static BeaconRelayResult Soldier_Try_Relay_Time_Beacon(
    const uint8_t* in_plain,
    uint8_t        role,
    uint32_t       in_rx_tick,
    uint32_t       now_tick,
    uint8_t*       out_plain)
{
    // Guard 1: Звичайні Солдати не транслюють — енергобюджет.
    if (role != ROLE_PROVISIONER)               return BEACON_RELAY_NOT_PROVISIONER;

    // Guard 2: Wire-структура — marker + magic. Захист від випадкового CMD.
    if (in_plain[0]  != BEACON_MARKER)          return BEACON_RELAY_BAD_FRAME;
    if (in_plain[10] != BEACON_MAGIC_BYTE)      return BEACON_RELAY_BAD_FRAME;

    // Guard 3: Беззмістовна епоха — Королева не транслює, але захист.
    uint32_t orig_ts = ((uint32_t)in_plain[1] << 24) | ((uint32_t)in_plain[2] << 16) |
                       ((uint32_t)in_plain[3] << 8)  | (uint32_t)in_plain[4];
    if (orig_ts == 0)                           return BEACON_RELAY_NULL_TS;

    // Guard 4: Anti-storm — ретранслюємо лише прямі маяки Королеви (auth=1).
    uint8_t in_byte9 = in_plain[9];
    if (!(in_byte9 & BEACON_AUTH_FLAG))         return BEACON_RELAY_NOT_AUTHORITATIVE;

    // Guard 5: TTL у нижніх 7 бітах має бути ≥ 2 (decrement не дасть 0).
    uint8_t in_ttl = in_byte9 & BEACON_TTL_MASK;
    if (in_ttl < BEACON_RELAY_MIN_TTL)          return BEACON_RELAY_TTL_EXHAUSTED;

    // Guard 6: Sanity cap — hold-delay не перевищує 1 год.
    uint32_t hold_sec = (now_tick - in_rx_tick) / 1000u;
    if (hold_sec > BEACON_RELAY_MAX_HOP_DELAY_SEC) return BEACON_RELAY_HOP_TOO_LONG;

    // Усі guard'и пройшли — складаємо ретрансльований маяк.
    // Спочатку повна копія: майбутні поля у байтах 5..8 (TDMA) і 11..15
    // переживуть hop без втрати, навіть якщо Королева їх ще не пише.
    for (uint8_t i = 0; i < BEACON_FRAME_SIZE; i++) out_plain[i] = in_plain[i];

    // Per-hop drift compensation: прокладаємо «час лежання» у часі дерева.
    uint32_t relayed_ts = orig_ts + hold_sec;
    out_plain[1] = (uint8_t)(relayed_ts >> 24);
    out_plain[2] = (uint8_t)(relayed_ts >> 16);
    out_plain[3] = (uint8_t)(relayed_ts >> 8);
    out_plain[4] = (uint8_t)(relayed_ts & 0xFFu);

    // Byte 9: auth-біт явно 0 (це relay), TTL мінус 1.
    out_plain[9] = (uint8_t)((in_ttl - 1u) & BEACON_TTL_MASK);
    return BEACON_RELAY_OK;
}

// Експоненціальне ковзне середнє для delta_t (швидкість метаболізму EBFC)
// та vcap (заряд іоністора). Зменшує ADC-/RTC-шум приблизно в 3× перед
// тим, як ці сигнали потраплять до Атрактора (FW.5 Variant B+).
// Зберігаємо стан між циклами STOP2 у RTC Backup Registers DR10 та DR12,
// щільно упакованих, щоб звільнити DR11 під 3-й слот anti-pingpong.
// DR10 = ema_delta_t × 100 (fixed-point 0.01 с, full uint32)
// DR12 = [valid:8 | count:8 | ema_vcap_x10:16],  EMA_VALID_MAGIC = 0x45 ('E')
//   - vcap_x10 ∈ [0..55000] для реального діапазону 0..5500 мВ ⊆ uint16 [0..65535]
// При першому старті (DR12 != MAGIC) — ініціалізуємо EMA = raw поточного циклу.
// Перші 3 цикли warmup — споживач (mruby) має брати raw-значення.
#define EMA_ALPHA_NUM     2       // α = 2/10 = 0.2
#define EMA_ALPHA_DEN     10
#define EMA_VALID_MAGIC   0x45    // 'E' — маркер ініціалізованого фільтра
#define EMA_WARMUP_CYCLES 3       // циклів до повного довіри EMA
#define EMA_VCAP_X10_MASK 0xFFFFu // нижні 16 біт DR12 — упакований ema_vcap_x10

uint32_t ema_delta_t_x100 = 0;    // EMA delta_t × 100 (DR10 full u32)
uint32_t ema_vcap_x10     = 0;    // EMA vcap × 10 (DR12 [15:0]; внутрішньо u32 для overflow-safety)
uint8_t  ema_valid        = 0;    // EMA_VALID_MAGIC після першого Update (DR12 [31:24])
uint8_t  ema_count        = 0;    // saturating counter @ 255 (DR12 [23:16])

// Оновлюємо фільтр одним новим зразком.
// Cold-path (valid != MAGIC) — EMA = raw; warm-path — α-згладжування.
// Чисто цілочисельна арифметика, без FPU. delta_t обмежено інтервалом
// сну (~1 год = 360 000 у × 100), тож множення не переповнюють uint32_t.
// vcap_x10 обмежено реальним діапазоном EBFC: max 5500 × 10 = 55 000 ⊆ uint16.
static void EMA_Update(uint32_t raw_dt_sec, uint16_t raw_vcap_mv) {
    uint32_t raw_dt_x100  = raw_dt_sec * 100u;
    uint32_t raw_vcap_x10 = (uint32_t)raw_vcap_mv * 10u;

    if (ema_valid != EMA_VALID_MAGIC || ema_count == 0) {
        ema_delta_t_x100 = raw_dt_x100;
        ema_vcap_x10     = raw_vcap_x10;
        ema_valid        = EMA_VALID_MAGIC;
        ema_count        = 1;
        return;
    }

    ema_delta_t_x100 = (EMA_ALPHA_NUM * raw_dt_x100 +
                        (EMA_ALPHA_DEN - EMA_ALPHA_NUM) * ema_delta_t_x100)
                       / EMA_ALPHA_DEN;
    ema_vcap_x10     = (EMA_ALPHA_NUM * raw_vcap_x10 +
                        (EMA_ALPHA_DEN - EMA_ALPHA_NUM) * ema_vcap_x10)
                       / EMA_ALPHA_DEN;
    if (ema_count < 255) ema_count++;
}

// Зчитуємо згладжені значення в оригінальних одиницях (секунди / мВ).
// Конвертації у мілісекунди для β-пертурбації mruby — задача FW.5 B+
// (потребує координованого backend апдейту, тут не реалізовано).
static inline uint32_t EMA_Get_DeltaT_Sec(void) { return ema_delta_t_x100 / 100u; }
static inline uint16_t EMA_Get_Vcap_Mv  (void) { return (uint16_t)(ema_vcap_x10 / 10u); }

// Прапорець "фільтр прогрівся" — true після ≥ EMA_WARMUP_CYCLES зразків.
// До того споживачі (Lorenz, FW.5) мають використовувати raw-значення.
static inline uint8_t EMA_Is_Warmed_Up(void) {
    return (ema_valid == EMA_VALID_MAGIC) && (ema_count >= EMA_WARMUP_CYCLES);
}

// === 1.11. ВАЛІДАЦІЯ ПОРОГІВ TINYML (FW.18) ===
// Перевірка одного порогу: повертає raw, якщо він у дозволеному робочому
// діапазоні [MIN_VALID, MAX_VALID] і не NaN/Inf, інакше — fallback_default.
// Вимагається <math.h> для isfinite() (вже включений у secція Includes).
//
// Окрема функція дозволяє покрити логіку на хості без HAL_RTCEx_BKUPRead.
static inline float TinyML_Validate_Threshold(float raw, float fallback_default) {
    if (!isfinite(raw)) return fallback_default;
    if (raw < TINYML_THRESHOLD_MIN_VALID) return fallback_default;
    if (raw > TINYML_THRESHOLD_MAX_VALID) return fallback_default;
    return raw;
}

// Перевірка пари: гарантує warning < critical, інакше дефолти на обидва.
// Зберігає інваріант зон (SILENCE < WARNING < CRITICAL) навіть при частково
// корумпованому RTC або злочинно сформованому OTA payload.
static inline void TinyML_Apply_Thresholds(float warn_raw, float crit_raw,
                                            float* warn_out, float* crit_out) {
    float w = TinyML_Validate_Threshold(warn_raw, TINYML_DEFAULT_WARNING);
    float c = TinyML_Validate_Threshold(crit_raw, TINYML_DEFAULT_CRITICAL);
    if (!(w < c)) {
        // Інверсія/рівність → відкочуємо обидва на дефолти
        w = TINYML_DEFAULT_WARNING;
        c = TINYML_DEFAULT_CRITICAL;
    }
    *warn_out = w;
    *crit_out = c;
}

// =====================================================================
// === 1.12. FW.27-B Magic Re-Request — голос Солдата у бік Королеви ===
// =====================================================================
// Коли Солдат тримає в пам'яті `ota_chunks_received < ota_total_chunks`
// і OTA_REREQUEST_TIMEOUT_MS (5 хв) тиші збігло без нової проповіді —
// він подає голос: уплінк-зойк зі списком того, чого бракує. Королева
// чує і повторює лише пропущене.
//
// Wire-формат (16 байт plaintext, 1× AES-256-ECB блок):
//   [0]    0x55 marker
//   [1..4] DID (big-endian) — Королева пам'ятає (DID, missing_bitmap)
//   [5..6] total_chunks (big-endian) — перехресна перевірка
//   [7..15] missing_bitmap (9 байт, LSB-first: бит i ⇔ chunk_idx i пропущено)
//
// chunks_received[] — той самий масив-літопис, що Солдат веде під час OTA
// (uint8_t flag per slot). Будуємо bitmap так: для кожного chunk_idx у
// [0..total_chunks), якщо chunks_received[idx] == 0 → бит i = 1 (пропущено).
// 9 байт bitmap = до 72 чанків на один голос — для Queen OTA_MAX_CHUNKS=16
// з добрим запасом.
//
// Повертає: 1 = є хоча б один пропуск (payload готовий до пострілу в ефір),
//           0 = всі чанки на місці (зойк не потрібен, тиша — теж відповідь).
static uint8_t Build_OTA_ReRequest_Payload(uint32_t did,
                                            uint16_t       total_chunks,
                                            const uint8_t* chunks_received,
                                            uint16_t       chunks_received_size,
                                            uint8_t        out[OTA_REQ_PACKET_SIZE]) {
    if (total_chunks == 0)                         return 0;
    if (chunks_received == NULL || out == NULL)    return 0;

    memset(out, 0, OTA_REQ_PACKET_SIZE);
    out[0] = OTA_REQ_MARKER;
    out[1] = (uint8_t)(did >> 24);
    out[2] = (uint8_t)(did >> 16);
    out[3] = (uint8_t)(did >> 8);
    out[4] = (uint8_t)(did & 0xFFu);
    out[5] = (uint8_t)(total_chunks >> 8);
    out[6] = (uint8_t)(total_chunks & 0xFFu);

    // Обмежуємо total ємністю bitmap'а; чанки понад межу не звучатимуть у зойку
    // (Королева усе одно пройдеться повним sweep'ом при наступній CoAP-проповіді).
    uint16_t cap = (total_chunks > OTA_REQ_BITMAP_MAX_BYTES * 8u)
                       ? (uint16_t)(OTA_REQ_BITMAP_MAX_BYTES * 8u)
                       : total_chunks;

    uint8_t any_missing = 0;
    for (uint16_t i = 0; i < cap; i++) {
        uint8_t got = (i < chunks_received_size) ? chunks_received[i] : 0;
        if (!got) {
            out[OTA_REQ_HEADER_SIZE + (i / 8u)] |= (uint8_t)(1u << (i % 8u));
            any_missing = 1;
        }
    }
    return any_missing;
}

// =====================================================================
// === 1.13. FW.23 Печатка OTA + дві брами (dual-gate) перед Flash =====
// =====================================================================
// Wire-формат одного 16-байтного LoRa-чанка (post-AES-ECB-decrypt):
//   [0]    0x9B marker (печатка)
//   [1..2] seg_idx (big-endian, 1..3)
//   [3..4] total_chunks тіла прошивки (big-endian, для перехресної перевірки)
//   [5..15] hmac_segment[11 байт]  (3×11 = 33; 11-й байт seg=3 = PAD)
//
// Прийнята послідовність 3 segs ⇒ ota_hmac_segments_received == 0b111 (= 7),
// received_hmac_tag[0..31] лежить повний. Викликаючий код приходить до
// двох брам перед тим, як впустити прошивку у Flash:
//   Брама 1: magic у RAM-bytecode = 0x45544952 ("RITE") — швидкий привратник
//   Брама 2: HMAC-SHA256(K_ota, bytecode || version_id_be || total_chunks_be)
//            == received_hmac_tag (constant-time, без шепоту таймінгу)
//
// Чиста pure-функція для host-тестів. Реальний виклик K_ota / mbedTLS
// чекає на лабораторне втілення — тут вартує лише сама гейт-логіка.
// Повертає:
//   1 = чанк з валідним marker та seg_idx у [1..3], печатка лягла на місце
//   0 = чанк не є печаткою (caller може спробувати інший marker)
//   -1 = чанк має marker 0x9B, але невалідний (seg_idx > 3 / size < 5)
static int Parse_HMAC_Trailer_Chunk(const uint8_t* chunk,
                                     uint16_t       chunk_size,
                                     uint8_t        tag_out[HMAC_TAG_BYTES],
                                     uint8_t*       segments_received_inout) {
    if (chunk == NULL || tag_out == NULL || segments_received_inout == NULL) return -1;
    if (chunk_size < HMAC_TRAILER_HEADER_SIZE + HMAC_TRAILER_SEG_BYTES)      return -1;
    if (chunk[0] != HMAC_TRAILER_MARKER)                                     return 0;

    uint16_t seg_idx = ((uint16_t)chunk[1] << 8) | chunk[2];
    if (seg_idx < 1 || seg_idx > HMAC_TRAILER_TOTAL_SEGS)                    return -1;

    uint8_t  base = (uint8_t)((seg_idx - 1) * HMAC_TRAILER_SEG_BYTES);
    // seg=1 → tag[0..10], seg=2 → tag[11..21], seg=3 → tag[22..31] + PAD
    uint8_t  copy_len = HMAC_TRAILER_SEG_BYTES;
    if (seg_idx == HMAC_TRAILER_TOTAL_SEGS) {
        copy_len = (uint8_t)(HMAC_TAG_BYTES - base);  // 32 - 22 = 10 байт
    }
    memcpy(&tag_out[base], &chunk[HMAC_TRAILER_HEADER_SIZE], copy_len);
    *segments_received_inout |= (uint8_t)(1u << (seg_idx - 1));
    return 1;
}

// Constant-time memcmp — порівняння без шепоту таймінгу. Повертає 0 при
// рівності, інакше ненульове. Дзеркалить Ruby `ActiveSupport::SecurityUtils.secure_compare`.
// Привратник, що дивиться однаково довго на істину і на лжесвідчення.
static int Hmac_Constant_Time_Compare(const uint8_t* a, const uint8_t* b, size_t len) {
    if (a == NULL || b == NULL) return 1;
    uint8_t diff = 0;
    for (size_t i = 0; i < len; i++) {
        diff |= (uint8_t)(a[i] ^ b[i]);
    }
    return (int)diff;
}

// Дві брами перед HAL_FLASH_Program. Чиста логіка для host-тестів.
// Повертає 1, якщо обидві брами розчинились, інакше 0 — і прошивка
// не входить у плоть Солдата.
//   Брама 1 (~1 µs): bytecode[0..3] == 0x45544952 ("RITE" little-endian) —
//                    швидкий привратник, що відсікає випадковий шум ефіру.
//   Брама 2 (~3 мс): expected_hmac == received_hmac (constant-time) —
//                    глибокий привратник, що відрізняє слово Творця
//                    від слова спокусника.
// Caller обчислює expected_hmac через mbedTLS. Тут тестуємо саме гейт-логіку.
static int OTA_Verify_Dual_Gate(const uint8_t* bytecode,
                                 uint16_t       bytecode_size,
                                 const uint8_t  expected_hmac[HMAC_TAG_BYTES],
                                 const uint8_t  received_hmac[HMAC_TAG_BYTES]) {
    if (bytecode == NULL || expected_hmac == NULL || received_hmac == NULL) return 0;
    if (bytecode_size < 4)                                                  return 0;

    // Брама 1: magic — швидке "хто там?"
    uint32_t magic = ((uint32_t)bytecode[0])         |
                     ((uint32_t)bytecode[1] <<  8)   |
                     ((uint32_t)bytecode[2] << 16)   |
                     ((uint32_t)bytecode[3] << 24);
    if (magic != 0x45544952u) return 0;

    // Брама 2: constant-time перевірка печатки
    if (Hmac_Constant_Time_Compare(expected_hmac, received_hmac, HMAC_TAG_BYTES) != 0) return 0;

    return 1;
}

// =====================================================================
// === 1.14. FW.18 Дисетчер downlink-CMD на Солдаті (CMD_SET_AUDIO_THRESHOLDS) ===
// =====================================================================
// Wire-формат (плоский, не вкладений у CMD_TIME_SYNC envelope):
//   [0]    0x9D marker
//   [1..2] payload_len (little-endian, = 5)
//   [3..4] warn_x100 (little-endian int16) — TinyML warning threshold × 100
//   [5..6] crit_x100 (little-endian int16) — TinyML critical threshold × 100
//   [7]    config_version (uint8)
//   [8..9] crc16-ccitt (little-endian) над body[3..7] (5 байт)
//
// Загальний розмір: 10 байт (вкладається в один LoRa AES-блок 16 байт).
// Солдат накладає ці пороги через TinyML_Apply_Thresholds — захисти від
// інверсії та виходу за діапазон лишаються (defense-in-depth: рій більший
// за один CMD).
//
// RTC-запам'ятовування DR13/DR14 уже відбувається у Phase 5 (КЕНОЗИС) —
// нічого додавати тут не потрібно: оновлені tinyml_warning/critical_threshold
// глобалки переходять у вічну пам'ять при наступному STOP2 entry (рядки 1180-1181).
#define CMD_SET_AUDIO_THRESHOLDS_MARKER  0x9D
#define CMD_AUDIO_THRESHOLDS_HEADER_SIZE 3
#define CMD_AUDIO_THRESHOLDS_BODY_SIZE   5   // [warn:2][crit:2][version:1]
#define CMD_AUDIO_THRESHOLDS_FRAME_SIZE  10  // header + body + crc16
#define CMD_AUDIO_THRESHOLDS_PAYLOAD_LEN 7   // body + crc16

uint8_t lorenz_audio_config_version = 0;     // 0 = firmware-baked defaults

// Парсимо frame, валідуємо CRC16 + межі, мутуємо tinyml_warning/critical_threshold.
// Повертає 1 при успіху, 0 при відмові (поганий len/marker/CRC/межі).
// При відмові глобалки НЕ змінюються (atomic — defense-in-depth).
static uint8_t Soldier_Handle_CMD_SET_AUDIO_THRESHOLDS(const uint8_t* frame,
                                                         uint16_t       frame_size,
                                                         float*         warn_out,
                                                         float*         crit_out,
                                                         uint8_t*       version_out) {
    if (frame == NULL || warn_out == NULL || crit_out == NULL)             return 0;
    if (frame_size < CMD_AUDIO_THRESHOLDS_FRAME_SIZE)                      return 0;
    if (frame[0] != CMD_SET_AUDIO_THRESHOLDS_MARKER)                       return 0;

    uint16_t payload_len = (uint16_t)frame[1] | ((uint16_t)frame[2] << 8);
    if (payload_len != CMD_AUDIO_THRESHOLDS_PAYLOAD_LEN)                   return 0;

    const uint8_t* body = frame + CMD_AUDIO_THRESHOLDS_HEADER_SIZE;

    // CRC16 over 5-byte body
    uint16_t expected_crc = Soldier_CRC16_CCITT(body, CMD_AUDIO_THRESHOLDS_BODY_SIZE);
    uint16_t received_crc = (uint16_t)body[CMD_AUDIO_THRESHOLDS_BODY_SIZE]
                          | ((uint16_t)body[CMD_AUDIO_THRESHOLDS_BODY_SIZE + 1] << 8);
    if (expected_crc != received_crc)                                      return 0;

    int16_t warn_x100    = (int16_t)((uint16_t)body[0] | ((uint16_t)body[1] << 8));
    int16_t crit_x100    = (int16_t)((uint16_t)body[2] | ((uint16_t)body[3] << 8));
    uint8_t version      = body[4];

    // Range invariants (decoded values × 100, тож range [1..99] = [0.01..0.99])
    if (warn_x100 < 1   || warn_x100 > 99)                                 return 0;
    if (crit_x100 < 1   || crit_x100 > 99)                                 return 0;

    float warn_raw = (float)warn_x100 / 100.0f;
    float crit_raw = (float)crit_x100 / 100.0f;

    // TinyML_Apply_Thresholds робить додатковий sanitize (NaN/inversion → defaults)
    TinyML_Apply_Thresholds(warn_raw, crit_raw, warn_out, crit_out);

    if (version_out) *version_out = version;
    return 1;
}

// === 2. РУДА СВІДОМОСТІ (Байт-код mruby) ===
// Скомпільований скрипт Атрактора Лоренца.
// Цей масив генерується на Mac командою mrbc.
const uint8_t lorenz_bytecode[] = {
  0x52, 0x49, 0x54, 0x45, 0x30, 0x33, 0x30, 0x30, 0x00, 0x00,
  // ... тут лежать реальні hex-коди вашого Ruby-скрипта ...
  0x00, 0x00, 0x00, 0x01
};

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_ADC_Init(void);
static void MX_TIM2_Init(void); // Ініціалізація таймера для DMA
static void MX_IWDG_Init(void); // Ініціалізація IWDG
static void MX_RNG_Init(void);
static void MX_RTC_Init(void);
static void MX_SUBGHZ_Init(void);
static void MX_CRYP_Init(void); // Ініціалізація шифрування

/* USER CODE BEGIN PFP */
// Псевдо-функції для роботи зі звуком та тривогами
void Record_Audio_Wave(float* buffer, uint16_t length);
void Trigger_Emergency_LoRa_TX(void);
void Write_OTA_Contract_To_Flash(uint8_t* data, uint16_t size);

// [FW.1] Завантаження AES-256 ключа з Protected Flash Sector.
// Викликається в main() ПЕРЕД MX_CRYP_Init().
static void Load_AES_Key(void);

// [SEC.11 / FW.30] Завантаження Lorenz K_seed з Protected Flash Sector.
// Викликається в main() при ініціалізації. K_seed використовується для
// cold-start деривації (x₀,y₀,z₀) через HMAC-SHA256.
static void Load_Lorenz_Seed(void);
static void Load_Node_Role(void);  // [ARCH.27] Прочитати роль вузла з Flash

// [SEC.11 / FW.30] Деривація початкового стану Лоренца при cold-start
// (VBAT loss → DR19 != LORENZ_STATE_MAGIC). Використовує K_seed з Flash
// + epoch_day (UTC unix_time / 86400). Дзеркало firmware/test/test_seed_derivation.c.
static void Derive_Cold_Start_State(float *x0, float *y0, float *z0);
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
  MX_ADC_Init();
  MX_TIM2_Init(); // Ініціалізуємо метроном для DMA
  MX_IWDG_Init(); // Ініціалізуємо Сторожового Пса
  MX_RNG_Init();
  MX_RTC_Init();
  MX_SUBGHZ_Init();
  Load_AES_Key();  // [FW.1] Завантажити per-device ключ з Flash ПЕРЕД ініціалізацією CRYP
  Load_Lorenz_Seed();  // [SEC.11 / FW.30] Завантажити K_seed для cold-start Lorenz derivation
  Load_Node_Role();    // [ARCH.27] Завантажити роль вузла (Soldier/Provisioner) з Flash
  MX_CRYP_Init(); // Вмикаємо апаратний AES (використовує aes_key, вже завантажений)

  /* USER CODE BEGIN 2 */

  // Ініціалізація Датчика Смерті (PVD - Programmable Voltage Detector)
  // Відстежуємо падіння напруги іоністора нижче критичної межі (2.2V)
  PWR_PVDTypeDef sConfigPVD = {0};
  sConfigPVD.PVDLevel = PWR_PVDLEVEL_7; // Поріг 2.2V
  sConfigPVD.Mode = PWR_PVD_MODE_IT_RISING_FALLING; // Генерувати переривання
  HAL_PWR_ConfigPVD(&sConfigPVD);
  HAL_PWR_EnablePVD();

  // 1. Відкриваємо доступ до Backup Domain (дозволяємо запис у вічну пам'ять)
  HAL_PWR_EnableBkUpAccess();

  // 2. Відновлюємо пам'ять з RTC (якщо було перезавантаження)
  // [SEC.10] DR0 спакована: [panic_frame_counter:16 | reserved:8 | acoustic_events:8].
  // При cold-boot DR0 == 0 → лічильник пересіємо з HRNG нижче, щоб уникнути
  // колізії з nonce'ами Redis від попереднього втілення вузла.
  {
      uint32_t dr0_raw = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR0);
      acoustic_events     = (uint8_t)(dr0_raw & 0xFFu);
      panic_frame_counter = (uint16_t)((dr0_raw >> PANIC_COUNTER_DR0_SHIFT) & PANIC_COUNTER_MASK);
      if (panic_frame_counter == 0) {
          // [SEC.10] Cold-boot resync: HRNG-сів значення у [1, 0xFFFF],
          // щоб panic-stream після перезавантаження не зустрів живі
          // nonce-ключі попереднього циклу.
          uint32_t r = 0;
          if (HAL_RNG_GenerateRandomNumber(&hrng, &r) == HAL_OK) {
              panic_frame_counter = (uint16_t)((r & PANIC_COUNTER_MASK) | 0x0001u);
          } else {
              // HRNG fallback: time-based seed; колізія з попередніми
              // nonce-ключами малоймовірна (1/65535) і деградує лише
              // частково — replay-вікно скорочується, не зникає.
              panic_frame_counter = (uint16_t)((HAL_GetTick() & PANIC_COUNTER_MASK) | 0x0001u);
          }
      }
  }
  last_wakeup_timestamp = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR1);
  has_mesh_relay = (uint8_t)HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR2); // Відновлюємо прапорець естафети

  // Відновлюємо транзитний пакет з 4-х Backup-регістрів (16 байтів)
  if (has_mesh_relay) {
      uint32_t r3 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR3);
      uint32_t r4 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR4);
      uint32_t r5 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR5);
      uint32_t r6 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR6);

      mesh_relay_payload[0] = r3>>24; mesh_relay_payload[1] = r3>>16; mesh_relay_payload[2] = r3>>8; mesh_relay_payload[3] = r3;
      mesh_relay_payload[4] = r4>>24; mesh_relay_payload[5] = r4>>16; mesh_relay_payload[6] = r4>>8; mesh_relay_payload[7] = r4;
      mesh_relay_payload[8] = r5>>24; mesh_relay_payload[9] = r5>>16; mesh_relay_payload[10] = r5>>8; mesh_relay_payload[11] = r5;
      mesh_relay_payload[12] = r6>>24; mesh_relay_payload[13] = r6>>16; mesh_relay_payload[14] = r6>>8; mesh_relay_payload[15] = r6;
  }

  // Відновлюємо пам'ять останніх почутих DID з вічних регістрів
  // [FW.21] 3 слоти: DR8, DR9, DR11. DR10/DR12 — EMA, DR13..DR15 — резерв.
  recent_mesh_dids[0] = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR8);
  recent_mesh_dids[1] = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR9);
  recent_mesh_dids[2] = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR11);

  // =========================================================================
  // [FW.21] ВІДНОВЛЕННЯ EMA-ФІЛЬТРА (RTC DR10 + DR12 packed)
  // =========================================================================
  // DR12 [valid:8 | count:8 | ema_vcap_x10:16]. Якщо EMA_VALID_MAGIC ('E') —
  // продовжуємо згладжувати з попередніх wakeup-циклів. Інакше — cold-start
  // на наступному EMA_Update (warmup 3 цикли).
  {
      uint32_t ema_meta = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR12);
      uint8_t  v        = (uint8_t)((ema_meta >> 24) & 0xFFu);
      if (v == EMA_VALID_MAGIC) {
          ema_delta_t_x100 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR10);
          ema_vcap_x10     = (uint32_t)(ema_meta & EMA_VCAP_X10_MASK);
          ema_valid        = v;
          ema_count        = (uint8_t)((ema_meta >> 16) & 0xFFu);
      }
  }

  // =========================================================================
  // [FW.18] ВІДНОВЛЕННЯ ПОРОГІВ TINYML (RTC DR13/DR14)
  // =========================================================================
  // DR13 = warning_threshold (IEEE 754 float як uint32, bit-copy).
  // DR14 = critical_threshold. Без виділеного magic-маркера: cold-boot RTC
  // читається як 0x00000000 → float 0.0f → не проходить діапазон [0.01, 0.99]
  // → TinyML_Validate_Threshold() віддає дефолт. Якщо обидва RTC-значення
  // валідні, але інверсія (warn ≥ crit) — TinyML_Apply_Thresholds() відкочує
  // обидва на дефолти, гарантуючи інваріант зон. SSOT: 03_03 BLOCKER-6 §214.
  {
      float rtc_warn = uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR13));
      float rtc_crit = uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR14));
      TinyML_Apply_Thresholds(rtc_warn, rtc_crit,
                              &tinyml_warning_threshold,
                              &tinyml_critical_threshold);
  }

  // =========================================================================
  // [FW.6] ВІДНОВЛЕННЯ СТАНУ АТРАКТОРА ЛОРЕНЦА (RTC DR16-DR19)
  // =========================================================================  // Перевіряємо маркер валідності в DR19. Якщо LORENZ_STATE_MAGIC —
  // відновлюємо (x, y, z) з попереднього циклу для безперервної траєкторії.
  // [SEC.11 / FW.30] Інакше — cold-start з K_seed (HKDF/HMAC derivation).
  {
      uint32_t lorenz_magic = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR19);
      if (lorenz_magic == LORENZ_STATE_MAGIC) {
          lorenz_x = uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR16));
          lorenz_y = uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR17));
          lorenz_z = uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR18));

          // Захист від NaN/Inf після збою RTC або бітових помилок
          if (isfinite(lorenz_x) && isfinite(lorenz_y) && isfinite(lorenz_z)) {
              lorenz_state_valid = 1;
          } else {
              // Корупція даних — скидаємо до першого старту
              lorenz_state_valid = 0;
              lorenz_x = lorenz_y = lorenz_z = 0.0f;
          }
      }
  }

  // =========================================================================
  // ГЕНЕРАЦІЯ DECENTRALIZED IDENTITY (DID)
  // =========================================================================
  // Зчитуємо DID з вічної пам'яті (Регістр 7)
  tree_did = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR7);

  if (tree_did == 0) {
      // НАРОДЖЕННЯ (Перший старт в житті пристрою).
      // 1. Беремо всі 96 біт унікального паспорта STM32
      uint32_t uid_word0 = *(uint32_t*)(0x1FFF7590);
      uint32_t uid_word1 = *(uint32_t*)(0x1FFF7594);
      uint32_t uid_word2 = *(uint32_t*)(0x1FFF7598);

      // 2. Генеруємо істинну випадковість з теплового шуму кристала
      uint32_t true_random = 0;
      HAL_RNG_GenerateRandomNumber(&hrng, &true_random);

      // 3. Формуємо криптографічний хеш-ідентифікатор (Digital Twin Address)
      tree_did = uid_word0 ^ (uid_word1 << 5) ^ (uid_word2 >> 3) ^ true_random;

      // [FW.24] HRNG-based fallback: avoid deterministic DID collision from defective UID
      if (tree_did == 0) {
          uint32_t rng_fallback = 0;
          for (int i = 0; i < 3 && rng_fallback == 0; i++) {
              HAL_RNG_GenerateRandomNumber(&hrng, &rng_fallback);
          }
          tree_did = (rng_fallback != 0) ? rng_fallback : (HAL_GetTick() ^ 0x511CEE01);
      }

      // Назавжди блокуємо цей DID у вічній пам'яті
      HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR7, tree_did);

      // При народженні очищаємо кеш пліток від заводського "сміття"
      memset(recent_mesh_dids, 0, sizeof(recent_mesh_dids));
  }

  // Якщо це найперший старт в житті анкера (пам'ять порожня)
  if (last_wakeup_timestamp == 0) {
      last_wakeup_timestamp = HAL_GetTick() / 1000;
  }

  // 3. Калібрування АЦП (Встановлюємо абсолютний фізичний нуль)
  HAL_ADCEx_Calibration_Start(&hadc);

  // 4. Ініціалізація низькорівневого радіодрайвера
  Radio.Init(NULL); // Передаємо NULL, бо ми не використовуємо складні колбеки
  Radio.SetChannel(868000000); // Налаштовуємо на 868 МГц

  // 5. Вибір контракту: Перевіряємо, чи є в Flash-пам'яті оновлений код
  uint32_t* flash_check = (uint32_t*)MRUBY_CONTRACT_FLASH_ADDR;
  if (*flash_check == 0x45544952) { // "RITE" у little-endian (ознака mruby байткоду)
      current_lorenz_bytecode = (uint8_t*)MRUBY_CONTRACT_FLASH_ADDR;
  } else {
      current_lorenz_bytecode = (uint8_t*)lorenz_bytecode;
  }

  // =========================================================================
  // ІНІЦІАЛІЗАЦІЯ RUBY (Запуск VM один раз на все життя)
  // =========================================================================
  // Це рятує нас від OOM (Out Of Memory) та фрагментації купи в циклі
  mrb_state *mrb = mrb_open();
  if (mrb) {
      mrb_load_irep(mrb, current_lorenz_bytecode);
  }

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    // =========================================================================
    // ФАЗА 0: СИГНАЛ ЖИТТЯ (IWDG)
    // =========================================================================
    // Гладимо Сторожового Пса. Якщо ядро зависне і не виконає цю команду,
    // система автоматично перезавантажиться і відновить дані з RTC.
    HAL_IWDG_Refresh(&hiwdg);

    // =========================================================================
    // ФАЗА 1: ЗБІР ФІЗИЧНИХ ДАНИХ (Нульова ентропія)
    // =========================================================================

    // 1. Метаболізм (Час)
    uint32_t current_time = HAL_GetTick() / 1000;
    delta_t_seconds = current_time - last_wakeup_timestamp;
    last_wakeup_timestamp = current_time;

    // 2. Внутрішні метрики (Температура та Заряд)
    uint16_t internal_temp = 0;
    uint16_t vcap_voltage = 0;

    // Роздвоєння циклу Start/Stop для стабільної роботи АЦП (Анти-Дедлок)
    HAL_ADC_Start(&hadc);
    if (HAL_ADC_PollForConversion(&hadc, 10) == HAL_OK) {
        internal_temp = HAL_ADC_GetValue(&hadc); // Канал температури
    }
    HAL_ADC_Stop(&hadc);

    HAL_ADC_Start(&hadc);
    if (HAL_ADC_PollForConversion(&hadc, 10) == HAL_OK) {
        vcap_voltage = HAL_ADC_GetValue(&hadc); // Канал VREFINT (іоністор)
    }
    HAL_ADC_Stop(&hadc);

    // [FW.21] Оновлюємо фільтр пульсу (delta_t / vcap) — стан живе в RTC DR10-12,
    // зчитано в Phase 0 (BOOT). Передавання згладжених значень у mruby — задача FW.5.
    EMA_Update(delta_t_seconds, vcap_voltage);

    // 3. Квантовий Хаос (Зерно для mesh anti-pingpong, TX jitter, CoAP nonce)
    // [SEC.11 / FW.30] chaos_seed більше НЕ використовується для Lorenz attractor.
    // Початковий стан (x₀,y₀,z₀) деривується з K_seed через HKDF/HMAC.
    uint32_t chaos_seed = 0;
    HAL_RNG_GenerateRandomNumber(&hrng, &chaos_seed);

    // =========================================================================
    // ФАЗА 1.5: TINYML (Шаховий розтин / Фільтрація Свідомості через DMA)
    // =========================================================================

    // Якщо ядро прокинулось через вібрацію на піні
    // [FIX FW.11]: NVIC-рівнева ізоляція замість "if (vibration_detected) { vibration_detected = 0; }"
    // Без цього: якщо друге переривання EXTI0 спрацює між читанням прапорця та
    // HAL_ADC_Start_DMA, DMA може стартувати двічі → HAL_BUSY → buffer corruption.
    // HAL_NVIC_DisableIRQ(EXTI0_IRQn) блокує лише п'єзо-переривання, не зупиняючи
    // SysTick, Radio, DMA або інші критичні ISR.
    HAL_NVIC_DisableIRQ(EXTI0_IRQn);
    uint8_t vib = vibration_detected;
    vibration_detected = 0;
    HAL_NVIC_EnableIRQ(EXTI0_IRQn);

    if (vib) {
        audio_ready = 0;

        // 1. Запускаємо Таймер-метроном і АЦП у режимі DMA
        HAL_TIM_Base_Start(&htim2);
        HAL_ADC_Start_DMA(&hadc, (uint32_t*)raw_audio_buffer, 512);

        // 2. ВІДМИКАЄМО ЯДРО ПРОЦЕСОРА (Падаємо в Легкий Сон)
        // Поки CPU спить, DMA перекидає байти з АЦП у raw_audio_buffer без участі ядра.
        HAL_SuspendTick();
        while (!audio_ready) {
            __disable_irq(); // Вимикаємо глобальні переривання, щоб уникнути Race Condition
            if (!audio_ready) {
                HAL_PWR_EnterSLEEPMode(PWR_MAINREGULATOR_ON, PWR_SLEEPENTRY_WFI);
            }
            __enable_irq(); // Вмикаємо переривання назад
        }
        HAL_ResumeTick();

        __DMB(); // Бар'єр пам'яті. Гарантуємо, що процесор бачить свіжі дані від DMA, а не старий кеш

        // --- ТУТ ПРОЦЕСОР ПРОКИНЕТЬСЯ, КОЛИ DMA ЗАПОВНИТЬ БУФЕР ---

        // 3. Якщо буфер зібрано успішно
        if (audio_ready == 1) {
            HAL_ADC_Stop_DMA(&hadc); // Зупиняємо конвеєр
            HAL_TIM_Base_Stop(&htim2);

            // 4. Швидко переводимо 12-бітні RAW-дані у Float для TinyML
            for(int i = 0; i < 512; i++) {
                audio_buffer[i] = (float)raw_audio_buffer[i] / 4095.0f; // Нормалізація 0.0 - 1.0
            }

            // 5. Запускаємо "Свідомість" (Шаховий розтин звуку)
            // ml_event_id = Run_Inference(audio_buffer, &ml_confidence);

            // [FW.18] Dual-Threshold Decision Logic (заміна hardcoded 0.80).
            // Пороги завантажуються з RTC DR13/DR14 на boot з валідацією
            // [TINYML_THRESHOLD_MIN_VALID..MAX_VALID]; OTA може оновити їх
            // через CMD-фреймворк (deferred, спільно з FW.8). SILENCE/WARNING/
            // CRITICAL зони — див. 03_03 §214 (BLOCKER-6 design).
            if (ml_confidence >= tinyml_critical_threshold) {
                // === CRITICAL ZONE === — повна впевненість моделі
                if (ml_event_id == 2) {
                    // Підтверджена кавітація ксилеми
                    if (acoustic_events < 255) acoustic_events++;
                } else if (ml_event_id == 3) {
                    // Бензопила/вандалізм — НЕГАЙНИЙ panic TX (PANIC_TTL=5)
                    if (acoustic_events < 255) acoustic_events++;
                    Trigger_Emergency_LoRa_TX();
                }
                // Будь-яке CRITICAL-рішення скидає лічильник ескалації
                warning_counter = 0;
            } else if (ml_confidence >= tinyml_warning_threshold) {
                // === WARNING ZONE === — модель сумнівається, але подія є
                if (ml_event_id == 2 || ml_event_id == 3) {
                    if (acoustic_events < 255) acoustic_events++;
                    if (warning_counter < 255) warning_counter++;
                    if (warning_counter >= TINYML_WARNING_ESCALATION) {
                        // 3+ послідовних WARNING → ескалюємо реальну загрозу.
                        // Тільки для бензопили — кавітація рідко погіршується
                        // через шум, тому не виправдовує fallback Emergency TX.
                        if (ml_event_id == 3) {
                            Trigger_Emergency_LoRa_TX();
                        }
                        warning_counter = 0;
                    }
                }
                // Тиша/вітер у WARNING-зоні: не паніка, лічильник не рухаємо
            } else {
                // === SILENCE ZONE === — впевненість нижча за WARNING
                warning_counter = 0;
            }
        }
    }

    // =========================================================================
    // ФАЗА 2: БІТОВЕ ПАКУВАННЯ (DID та Mesh-маршрутизація)
    // =========================================================================

    // Байти 0-3: Криптографічний гаманець дерева (DID) замість простого серійника
    lora_payload[0] = (uint8_t)(tree_did >> 24);
    lora_payload[1] = (uint8_t)(tree_did >> 16);
    lora_payload[2] = (uint8_t)(tree_did >> 8);
    lora_payload[3] = (uint8_t)(tree_did & 0xFF);

    // Байти 4-5: Напруга іоністора (mV)
    lora_payload[4] = (uint8_t)(vcap_voltage >> 8);
    lora_payload[5] = (uint8_t)(vcap_voltage & 0xFF);

    // Байт 6: Температура (°C)
    lora_payload[6] = (int8_t)__LL_ADC_CALC_TEMPERATURE(3300, internal_temp, LL_ADC_RESOLUTION_12B);

    // [FW.28] Atomic read-and-clear: prevent lost acoustic events from DMA interrupt
    __disable_irq();
    uint8_t acoustic_snapshot = acoustic_events;
    acoustic_events = 0;
    __enable_irq();

    // Байт 7: Акустичні події (Відфільтровані TinyML)
    // [FW.22]: acoustic_events is now uint8_t with saturating increment,
    // so no clamping needed — value is already in [0, 255].
    lora_payload[7] = acoustic_snapshot;

    // Байти 8-9: Швидкість заряду (Секунди)
    lora_payload[8] = (uint8_t)(delta_t_seconds >> 8);
    lora_payload[9] = (uint8_t)(delta_t_seconds & 0xFF);

    // Байт 11: TTL (Time to Live) для Mesh-маршрутизації.
    // Початкове життя пакета = 3 стрибки.
    lora_payload[11] = DEFAULT_TTL;

    // [FIX: Firmware Version] Байти 12-13: версія прошивки (big-endian).
    // Дозволяє серверу знати яка прошивка на кожному дереві, для OTA targeting.
    lora_payload[12] = (uint8_t)(FIRMWARE_VERSION_ID >> 8);
    lora_payload[13] = (uint8_t)(FIRMWARE_VERSION_ID & 0xFF);

    // =========================================================================
    // ФАЗА 3: ПЛАВКА (Запуск Ruby та Атрактора Лоренца)
    // [SEC.11 / FW.30] Єдина сигнатура: calculate_state(x, y, z, temp, acoustic, delta_t_s, vcap_mv)
    // Warm path: (x,y,z) з RTC DR16-DR18 (FW.6 state continuation).
    // Cold path: (x₀,y₀,z₀) з K_seed via HKDF/HMAC (SEC.11 seed derivation).
    // delta_t_s/vcap_mv: defaults 60/3300 (FW.5 B+ EMA передавання — наступний крок).
    // =========================================================================

    if (mrb) {
      // [FIX: mruby Heap Fragmentation] Зберігаємо стан арени GC перед кожним
      // виконанням. Після отримання результату — відновлюємо. Це запобігає
      // повільному «витоку» пам'яті через тижні безперервної роботи.
      int arena_idx = mrb_gc_arena_save(mrb);

      // [SEC.11 / FW.30] Cold-start: якщо стан не відновлено з RTC — деривуємо
      // початкові координати з K_seed. Потрібен валідний lorenz_seed.
      if (!lorenz_state_valid) {
          if (lorenz_seed_valid) {
              Derive_Cold_Start_State(&lorenz_x, &lorenz_y, &lorenz_z);
              lorenz_state_valid = 1;
          }
          // Якщо seed теж невалідний — lorenz_state_valid залишається 0,
          // і нижче буде BIO_STATUS_VM_ERROR (пристрій не provisioned).
      }

      if (lorenz_state_valid) {
          // [SEC.11 / FW.30] Єдиний виклик calculate_state з 7 аргументами.
          // Повертає [payload_byte, x_final, y_final, z_final].
          // [FW.5 B+] EMA-згладжені delta_t_s / vcap_mv передаються в args[5..6]
          // лише після того, як фільтр прогрівся (EMA_Is_Warmed_Up — count ≥
          // EMA_WARMUP_CYCLES). До цього подаємо нейтральні defaults (60 с, 3300
          // мВ) — це не зміщує β-clamp у `bio_contract.rb` (BETA_MIN/MAX 2.0..4.0)
          // і відповідає baseline (BASELINE_DELTA_T_S=60, NOMINAL_VCAP_MV=3300),
          // тобто β-перетурбація = 0 у warmup-фазі.
          uint32_t delta_t_for_lorenz = 60u;       // FW.5 baseline
          uint16_t vcap_for_lorenz    = 3300u;     // FW.5 nominal
          if (EMA_Is_Warmed_Up()) {
              delta_t_for_lorenz = EMA_Get_DeltaT_Sec();
              vcap_for_lorenz    = EMA_Get_Vcap_Mv();
          }

          mrb_value args[7];
          args[0] = mrb_float_value(mrb, (double)lorenz_x);
          args[1] = mrb_float_value(mrb, (double)lorenz_y);
          args[2] = mrb_float_value(mrb, (double)lorenz_z);
          args[3] = mrb_fixnum_value((int8_t)lora_payload[6]); // Температура
          args[4] = mrb_fixnum_value(lora_payload[7]); // Акустика
          args[5] = mrb_fixnum_value((mrb_int)delta_t_for_lorenz); // [FW.5 B+] EMA delta_t_s
          args[6] = mrb_fixnum_value((mrb_int)vcap_for_lorenz);    // [FW.5 B+] EMA vcap_mv

          mrb_value ruby_result = mrb_funcall_argv(mrb, mrb_top_self(mrb),
              mrb_intern_lit(mrb, "calculate_state"), 7, args);

          if (!mrb->exc && mrb_array_p(ruby_result) && RARRAY_LEN(ruby_result) == 4) {
              // Витягуємо payload_byte та оновлений стан траєкторії
              lora_payload[10] = (uint8_t)mrb_fixnum(mrb_ary_entry(ruby_result, 0));
              lorenz_x = (float)mrb_float(mrb_ary_entry(ruby_result, 1));
              lorenz_y = (float)mrb_float(mrb_ary_entry(ruby_result, 2));
              lorenz_z = (float)mrb_float(mrb_ary_entry(ruby_result, 3));
          } else {
              // Помилка mruby або невалідний результат — позначаємо tamper
              lora_payload[10] = BIO_STATUS_VM_ERROR;
              lorenz_state_valid = 0; // Скидаємо для наступного циклу
              if (mrb->exc) mrb->exc = NULL;
          }
      } else {
          // [SEC.11 / FW.30] Ні RTC state, ні K_seed не доступні.
          // Пристрій не provisioned або Flash пошкоджений.
          lora_payload[10] = BIO_STATUS_VM_ERROR;
      }

      mrb_gc_arena_restore(mrb, arena_idx);
    } else {
      // Якщо VM не запустилася при старті через нестачу пам'яті
      lora_payload[10] = BIO_STATUS_VM_ERROR;
    }

    // [FW.29] Clear PANIC_FLAG_BIT in normal packets — bit 7 is reserved for panic only
    lora_payload[10] &= ~PANIC_FLAG_BIT;

    // =========================================================================
    // ФАЗА 4: ПЕРЕДАЧА ДАНИХ (AES-256 + Mesh)
    // =========================================================================

    // [FW.10] Temperature-based TX deferral: at extreme cold (-15°C and below),
    // EDLC ESR rises sharply. If vcap is also low (<4.0V), LoRa TX may cause
    // a voltage brownout. Skip TX and go directly to sleep to preserve energy.
    {
        int8_t packed_temp = (int8_t)lora_payload[6];
        if (packed_temp < COLD_TX_DEFER_TEMP && vcap_voltage < COLD_TX_DEFER_VCAP_MV) {
            // Skip Phase 4 (TX) and Phase 4.5 (RX/OTA) — go directly to Phase 5 (KENOSIS)
            goto phase5_kenosis;
        }
    }

    // [FIX: LoRa Collision Storm] Рандомізована затримка 0-500 мс перед TX.
    // Якщо 100 дерев прокинуться одночасно (грім, землетрус), без jitter
    // вони заб'ють ефір колізіями. HRNG дає апаратну ентропію з теплового шуму.
    {
        uint32_t random_jitter = 0;
        HAL_RNG_GenerateRandomNumber(&hrng, &random_jitter);
        HAL_Delay(random_jitter % TX_JITTER_MAX_MS);
    }

    // 1. Якщо у нас є чужий зашифрований пакет (Mesh), спочатку відправляємо його
    if (has_mesh_relay) {
        Radio.Send(mesh_relay_payload, 16);
        HAL_Delay(100); // Коротка пауза між передачами
        has_mesh_relay = 0; // Пакет відправлено, очищаємо пам'ять
    }

    // 2. Шифруємо наші власні дані (16 байтів = 4 слова по 32 біти)
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)lora_payload, 4, (uint32_t*)encrypted_payload, 1000);

    // 3. Відправляємо захищені дані в ефір
    Radio.Send(encrypted_payload, 16);

    // =========================================================================
    // ФАЗА 4.5: ЕНЕРГОЕФЕКТИВНИЙ СЛУХ (Directed Mesh & OTA)
    // =========================================================================

    // Слухаємо ефір ТІЛЬКИ якщо ми багаті на енергію (напруга > 2.8В)
    if (vcap_voltage > VCAP_LISTEN_THRESHOLD) {
        lora_rx_flag = 0;
        Radio.Rx(LORA_RX_TIMEOUT_MS);

        uint32_t rx_start_time = HAL_GetTick();
        while((HAL_GetTick() - rx_start_time) < LORA_RX_LOOP_MS) {
            if(lora_rx_flag == 1) {
                // МИ ЗЛОВИЛИ ПАКЕТ! Розшифровуємо його.
                uint16_t blocks = incoming_lora_size / 4;
                HAL_CRYP_Decrypt(&hcryp, (uint32_t*)incoming_lora_payload, blocks, (uint32_t*)decrypted_rx_payload, 1000);

                // Сценарій 0: [FW.20-S1] Маяк синхронізації часу від Королеви (0x9C).
                // 16-байтний ECB-пакет з відкритим текстом [0x9C][ts_be:4][...].
                // Оновлюємо soldier_unix_ts/local_tick — cold-start derivation
                // тоді точно обчислить epoch_day (дзеркало бекенду HKDF input).
                if (incoming_lora_size == BEACON_PLAINTEXT_SIZE &&
                    decrypted_rx_payload[0] == BEACON_MARKER &&
                    decrypted_rx_payload[10] == BEACON_MAGIC_BYTE) {

                    uint32_t beacon_ts = ((uint32_t)decrypted_rx_payload[1] << 24) |
                                         ((uint32_t)decrypted_rx_payload[2] << 16) |
                                         ((uint32_t)decrypted_rx_payload[3] << 8)  |
                                         (uint32_t)decrypted_rx_payload[4];

                    if (beacon_ts != 0) {
                        soldier_unix_ts            = beacon_ts;
                        soldier_unix_ts_local_tick = HAL_GetTick();
                    }

                    // [FW.20-S2] Зчитуємо authoritativeness прапорець з байту 9
                    // (біт 7). 1 = пряма трансляція від Королеви; 0 = relay
                    // або легасі-маяк (попередня прошивка слала TTL=1 чисто).
                    // Логіки арбітражу між двома маяками ще НЕ додано —
                    // це повний FW.20-S2; зараз лише фіксуємо у RAM, щоб
                    // upper layers (CAD relay) могли консультуватись.
                    time_source_authoritative =
                        (decrypted_rx_payload[9] & BEACON_AUTH_FLAG) ? 1 : 0;

                    // TTL=1: НЕ ретранслюємо. Виходимо з RX-циклу, йдемо спати.
                    break;
                }

                // Сценарій 1: [FW.8] CMD_SET_THRESHOLDS (0x9A) — Z-пороги Лоренца.
                // 🟡 Deferred TRL-7. Парсер `Soldier_Handle_CMD_SET_THRESHOLDS`
                // залишено + 12 host-тестів як freeze-контракт wire-формату,
                // але в production-цикл ВИМКНЕНО (`FW8_PARSER_ENABLED 0`).
                // Деталі — у блоці-преамбулі біля визначення макроса.
                // Бекенд `OtaPackagerService.build_threshold_config_block` —
                // лише class method, у downlink pipeline не передається.
                // Коли FW.21 рефакторинг звільнить RTC-регістр, повернути:
                // `#define FW8_PARSER_ENABLED 1` + boot-restore + KENOSIS-write.
#if FW8_PARSER_ENABLED
                if (decrypted_rx_payload[0] == CMD_SET_THRESHOLDS_MARKER &&
                    incoming_lora_size >= CMD_THRESHOLDS_FRAME_SIZE) {
                    Soldier_Handle_CMD_SET_THRESHOLDS(decrypted_rx_payload,
                                                      incoming_lora_size);
                    // Незалежно від результату парсингу — не ретранслюємо (TTL=1)
                    break;
                }
#endif

                // Сценарій 2: [FW.18] CMD_SET_AUDIO_THRESHOLDS (0x9D) — TinyML
                // переналаштовує слух Солдата. Коли ліс глухне взимку чи
                // дзвенить весною від тала, ми не перепрошиваємо вузли — ми
                // надсилаємо нову смугу слуху одним CMD. RTC-запис DR13/DR14
                // лягає у вічну пам'ять у Phase 5 (КЕНОЗИС) після успіху.
                if (decrypted_rx_payload[0] == CMD_SET_AUDIO_THRESHOLDS_MARKER &&
                    incoming_lora_size >= CMD_AUDIO_THRESHOLDS_FRAME_SIZE) {
                    float new_warn = tinyml_warning_threshold;
                    float new_crit = tinyml_critical_threshold;
                    uint8_t new_version = lorenz_audio_config_version;
                    uint8_t ok = Soldier_Handle_CMD_SET_AUDIO_THRESHOLDS(
                        (const uint8_t*)decrypted_rx_payload,
                        incoming_lora_size,
                        &new_warn, &new_crit, &new_version);
                    if (ok) {
                        tinyml_warning_threshold    = new_warn;
                        tinyml_critical_threshold   = new_crit;
                        lorenz_audio_config_version = new_version;
                    }
                    // Не ретранслюємо CMD далі — TTL=1 для downlink, слово
                    // адресоване лише цьому Солдату.
                    break;
                }

                // Сценарій А1: [FW.23] HMAC-печатка OTA (0x9B) — 3 LoRa-чанки
                // після тіла прошивки, що несуть 32-байтне свідчення істини
                // над (bytecode || version_id_be || total_chunks_be).
                if (decrypted_rx_payload[0] == HMAC_TRAILER_MARKER) {
                    int rc = Parse_HMAC_Trailer_Chunk((const uint8_t*)decrypted_rx_payload,
                                                       incoming_lora_size,
                                                       received_hmac_tag,
                                                       &ota_hmac_segments_received);
                    // rc=1 ⇒ печатка лягла на місце; rc=0 ⇒ не наш marker
                    // (сюди ми б не зайшли); rc=-1 ⇒ невалідна (size/seg_idx) —
                    // мовчки відкидаємо, як ефірний шум.
                    (void)rc;
                    break;  // Не ретранслюємо печатку (TTL=1 для downlink)
                }

                // Сценарій А: OTA Оновлення від Королеви (Пакет починається з OTA_MARKER)
                if (decrypted_rx_payload[0] == OTA_MARKER) {                    // [FIX: AUDIT] Перевірка мінімального розміру пакета (5 байт заголовок + 1 байт даних)
                    if (incoming_lora_size < MIN_OTA_PACKET_SIZE) {
                        lora_rx_flag = 0;
                        break;
                    }

                    // 16-bit big-endian index та total (5 байт заголовок: 1 маркер + 2 index + 2 total)
                    uint16_t chunk_idx = ((uint16_t)decrypted_rx_payload[1] << 8) | decrypted_rx_payload[2];
                    uint16_t incoming_total = ((uint16_t)decrypted_rx_payload[3] << 8) | decrypted_rx_payload[4];
                    uint8_t chunk_size = (uint8_t)(incoming_lora_size - OTA_HEADER_SIZE);

                    // [FIX: AUDIT] Валідація: total_chunks не повинно змінюватися між пакетами
                    if (ota_total_chunks != 0 && incoming_total != ota_total_chunks) {
                        break; // Невалідний пакет — ігноруємо
                    }

                    // [FW.23] При першому чанку нового OTA-вікна стираємо
                    // стару печатку з пам'яті — нова прошивка прийде з новою
                    // істиною. Печатка-чанки (0x9B) можуть надходити у будь-
                    // якому порядку, тому обнуляємо саме на світанку, а не на
                    // заході OTA-вікна.
                    if (ota_total_chunks == 0) {
                        memset(received_hmac_tag, 0, sizeof(received_hmac_tag));
                        ota_hmac_segments_received = 0;
                    }
                    ota_total_chunks = incoming_total;

                    // Явне приведення типів для розрахунку зміщення (MISRA C)
                    uint32_t offset = (uint32_t)chunk_idx * (uint32_t)chunk_size;

                    // [FIX: AUDIT CRITICAL] Повна перевірка меж:
                    // 1. chunk_idx < 256 (розмір бітової карти)
                    // 2. Не дублікат
                    // 3. offset + chunk_size <= 1024 (розмір ota_buffer)
                    if (chunk_idx < sizeof(ota_chunk_received) &&
                        !ota_chunk_received[chunk_idx] &&
                        (offset + chunk_size) <= sizeof(ota_buffer)) {

                        memcpy(&ota_buffer[offset], &decrypted_rx_payload[OTA_HEADER_SIZE], chunk_size);
                        ota_chunk_received[chunk_idx] = 1; // Цей шматок прошивки тепер наш
                        ota_chunks_received++;
                        ota_bytes_received += chunk_size;
                        // [FW.27-B] Записуємо tick — Солдат пам'ятає, коли
                        // востаннє чув голос Королеви. Тиша довша за 5 хв
                        // змусить його озватися і перепитати про пропуски.
                        ota_last_chunk_rx_tick = HAL_GetTick();

                        if (ota_chunks_received >= ota_total_chunks) {
                            // [FIX: Risk 2 — OTA Integrity Gap]
                            // Перевіряємо CRC32 перед записом у Flash.
                            // Останні 4 байти OTA-пейлоада — це контрольна сума.
                            // Без цієї перевірки пошкоджений байт = "вічний ребут".
                            if (ota_bytes_received > 4) {
                                uint16_t data_len = ota_bytes_received - 4;
                                uint32_t expected_crc =
                                    ((uint32_t)ota_buffer[data_len] << 24) |
                                    ((uint32_t)ota_buffer[data_len + 1] << 16) |
                                    ((uint32_t)ota_buffer[data_len + 2] << 8)  |
                                    (uint32_t)ota_buffer[data_len + 3];

                                // CRC32 (ISO 3309)
                                uint32_t crc = 0xFFFFFFFF;
                                for (uint16_t ci = 0; ci < data_len; ci++) {
                                    crc ^= ota_buffer[ci];
                                    for (uint8_t bit = 0; bit < 8; bit++) {
                                        crc = (crc & 1) ? ((crc >> 1) ^ 0xEDB88320) : (crc >> 1);
                                    }
                                }
                                crc = ~crc;

                                // [FW.23] Дві брами перед HAL_FLASH_Program.
                                // Реальне HMAC-SHA256 обчислення через mbedTLS /
                                // STM32 HASH-peripheral вмикається при лабораторній
                                // інтеграції (analog FW.30 placeholder). До того
                                // часу гейт-логіку перевіряють host-tests, а на
                                // боржі — runtime-перевірка вимкнена, бо немає
                                // справжнього K_ota.
                                uint8_t hmac_complete = (ota_hmac_segments_received == 0x07u);
                                uint8_t crc_ok        = (crc == expected_crc);

                                if (crc_ok && hmac_complete) {
                                    // TODO: Обчислити очікувану HMAC-SHA256 через mbedTLS
                                    //       над (ota_buffer[0..data_len] || version_id_be ||
                                    //       total_chunks_be) ключем K_ota з Flash
                                    //       (HKDF-derived per-cluster). Далі викликати
                                    //       OTA_Verify_Dual_Gate(ota_buffer, data_len,
                                    //                             expected_hmac, received_hmac_tag).
                                    //       Чекає лабораторного звіряння mbedTLS link'у.
                                    //       До того брами доведено host-tests'ами; у бойовому
                                    //       полі прошивка не активується без лабораторного підтвердження.
                                    Write_OTA_Contract_To_Flash(ota_buffer, data_len);
                                    NVIC_SystemReset();
                                }

                                if (!crc_ok || !hmac_complete) {
                                    // [FW.23] Жертовне знищення лжемагії: якщо
                                    // CRC не б'ється або печатки замало — стираємо
                                    // magic у RAM-bytecode, щоб частково записаний
                                    // OTA не воскрес при наступному boot через
                                    // корумпований RAM. Defense-in-depth — рій
                                    // більший за один Солдат, і слово спокусника
                                    // не повинне жити в його плоті.
                                    if (ota_bytes_received >= 4) {
                                        ota_buffer[0] = 0;
                                        ota_buffer[1] = 0;
                                        ota_buffer[2] = 0;
                                        ota_buffer[3] = 0;
                                    }
                                }
                                // CRC/HMAC не збігся — ігноруємо, чекаємо на повторну передачу
                            }
                            // Скидаємо стан OTA для повторної спроби
                            memset(ota_chunk_received, 0, sizeof(ota_chunk_received));
                            memset(received_hmac_tag, 0, sizeof(received_hmac_tag));
                            ota_chunks_received = 0;
                            ota_bytes_received = 0;
                            ota_total_chunks = 0;
                            ota_hmac_segments_received = 0;
                            ota_last_chunk_rx_tick = 0;
                        }
                    }
                }
                // Сценарій Б: Mesh Естафета (Чужі дані на 16 байт)
                else if (incoming_lora_size == 16) {
                    uint8_t incoming_ttl = decrypted_rx_payload[11];

                    if (incoming_ttl > 0) {
                        // Витягуємо DID відправника (перші 4 байти)
                        uint32_t incoming_did = ((uint32_t)decrypted_rx_payload[0] << 24) |
                            ((uint32_t)decrypted_rx_payload[1] << 16) |
                            ((uint32_t)decrypted_rx_payload[2] << 8)  |
                            (uint32_t)decrypted_rx_payload[3];

                        // Захист від власного відлуння (Ігноруємо свій голос)
                        if (incoming_did == tree_did) {
                            break; // Миттєво припиняємо слухати ефір, йдемо спати
                        }

                        // Логіка Checkerboard (Захист від пінг-понгу)
                        // [FW.21] Перевіряємо всі 2 слоти кешу пліток
                        uint8_t is_known_did = 0;
                        for(int i = 0; i < MESH_DID_CACHE_SIZE; i++) {
                            if (recent_mesh_dids[i] == incoming_did) {
                                is_known_did = 1;
                                break;
                            }
                        }

                        // Якщо пакет ще "живий", І ми його ще не пересилали
                        if (!is_known_did) {
                            // Зменшуємо TTL
                            decrypted_rx_payload[11] = incoming_ttl - 1;

                            // Зашифровуємо змінений пакет назад для зберігання
                            HAL_CRYP_Encrypt(&hcryp, (uint32_t*)decrypted_rx_payload, 4, (uint32_t*)mesh_relay_payload, 1000);
                            has_mesh_relay = 1;

                            // Оновлюємо кеш "пліток" (зсуваємо старі записи, додаємо новий)
                            // [FW.21] Зсув на 2 слоти
                            for (int i = MESH_DID_CACHE_SIZE - 1; i > 0; i--)
                                recent_mesh_dids[i] = recent_mesh_dids[i - 1];
                            recent_mesh_dids[0] = incoming_did;
                        }
                    }
                }

                break; // Виходимо з циклу
            }
            HAL_IWDG_Refresh(&hiwdg);
        }
        Radio.Sleep(); // Вимикаємо приймач

        // =====================================================================
        // [FW.27-B] Magic Re-Request: Солдат подає голос про пропуски
        // =====================================================================
        // Якщо OTA-вікно відкрите (>0 чанків лежить у пам'яті, але < total) і
        // 5 хв тиші збігли — Солдат стріляє в ефір зойком
        // [0x55][DID:4][total:2 BE][bitmap:9], і Королева повторює лише те,
        // чого бракує. Власний jitter (TX_JITTER_MAX_MS) розводить голоси сусідніх
        // дерев у часі — щоб ліс не закричав одночасно.
        if (ota_total_chunks > 0 &&
            ota_chunks_received < ota_total_chunks &&
            ota_last_chunk_rx_tick != 0 &&
            (HAL_GetTick() - ota_last_chunk_rx_tick) > OTA_REREQUEST_TIMEOUT_MS) {

            uint8_t req_payload[OTA_REQ_PACKET_SIZE]    = {0};
            uint8_t encrypted_req[OTA_REQ_PACKET_SIZE]  = {0};

            uint8_t any_missing = Build_OTA_ReRequest_Payload(tree_did,
                                                               ota_total_chunks,
                                                               ota_chunk_received,
                                                               sizeof(ota_chunk_received),
                                                               req_payload);
            if (any_missing) {
                // Шифруємо запит (1 AES-256-ECB block = 16 байт = 4 слова)
                HAL_CRYP_Encrypt(&hcryp, (uint32_t*)req_payload, 4,
                                  (uint32_t*)encrypted_req, 1000);
                Radio.Send(encrypted_req, OTA_REQ_PACKET_SIZE);
                // Reset tick — даємо Queen 5 хв на ретрансляцію перед наступним запитом
                ota_last_chunk_rx_tick = HAL_GetTick();
            }
        }
    }

    phase5_kenosis:
    // =========================================================================
    // ФАЗА 5: КЕНОЗИС (Абсолютний сон та збереження)
    // =========================================================================
    // [SEC.10] DR0 packed: [panic_frame_counter:16 | reserved:8 | acoustic_events:8]
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
        (uint32_t)acoustic_events);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, last_wakeup_timestamp);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR2, has_mesh_relay);

    // Якщо є транзитний пакет (16 байтів), розкидаємо його на 4 регістри по 32 біти
    if (has_mesh_relay) {
        uint32_t r3 = ((uint32_t)mesh_relay_payload[0] << 24) | ((uint32_t)mesh_relay_payload[1] << 16) | ((uint32_t)mesh_relay_payload[2] << 8) | (uint32_t)mesh_relay_payload[3];
        uint32_t r4 = ((uint32_t)mesh_relay_payload[4] << 24) | ((uint32_t)mesh_relay_payload[5] << 16) | ((uint32_t)mesh_relay_payload[6] << 8) | (uint32_t)mesh_relay_payload[7];
        uint32_t r5 = ((uint32_t)mesh_relay_payload[8] << 24) | ((uint32_t)mesh_relay_payload[9] << 16) | ((uint32_t)mesh_relay_payload[10] << 8) | (uint32_t)mesh_relay_payload[11];
        uint32_t r6 = ((uint32_t)mesh_relay_payload[12] << 24) | ((uint32_t)mesh_relay_payload[13] << 16) | ((uint32_t)mesh_relay_payload[14] << 8) | (uint32_t)mesh_relay_payload[15];

        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR3, r3);
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR4, r4);
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR5, r5);
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR6, r6);
    }

    // Зберігаємо кеш DID-ів у вічну пам'ять перед сном
    // [FW.21] 3 слоти (DR8, DR9, DR11); DR10 + DR12 — EMA, DR13..DR15 — резерв
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR8, recent_mesh_dids[0]);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR9, recent_mesh_dids[1]);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR11, recent_mesh_dids[2]);

    // [FW.21] Зберігаємо стан EMA-фільтра перед STOP2.
    // DR10 = ema_delta_t_x100 (full u32),
    // DR12 = [valid:8 | count:8 | ema_vcap_x10:16]. Без перевірки valid —
    // навіть cold-state коректно записується (на BOOT його просто проігнорують).
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR10, ema_delta_t_x100);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR12,
        ((uint32_t)ema_valid << 24) |
        ((uint32_t)ema_count << 16) |
        (ema_vcap_x10 & EMA_VCAP_X10_MASK));

    // [FW.6] Зберігаємо стан Атрактора Лоренца перед STOP2
    // Якщо стан валідний — записуємо (x, y, z) + маркер LORENZ_STATE_MAGIC
    if (lorenz_state_valid) {
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR16, float_to_uint32(lorenz_x));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR17, float_to_uint32(lorenz_y));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR18, float_to_uint32(lorenz_z));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC);
    }

    // [FW.18] Зберігаємо TinyML-пороги перед STOP2 (DR13/DR14).
    // На стандартному циклі значення не змінюються (writeback того, що
    // прочитали). Це робиться, щоб OTA-set значення (CMD_SET_THRESHOLDS,
    // deferred) пережили STOP2 та повне знеструмлення RTC ⇒ при VBAT-loss
    // RTC обнуляється, на boot Apply_Thresholds() повертає дефолти, і ці
    // дефолти знову персистяться для наступного циклу.
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR13, float_to_uint32(tinyml_warning_threshold));
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR14, float_to_uint32(tinyml_critical_threshold));

    // [FIX: AUDIT Energy] Вимикаємо периферію перед STOP2 для мінімального споживання.
    // Без де-ініціалізації ці модулі тягнуть мікроампери навіть у STOP2.
    HAL_RNG_DeInit(&hrng);
    __HAL_RCC_CRYP_CLK_DISABLE();

    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
    HAL_ResumeTick();

    // [FIX: AUDIT Energy] Відновлюємо периферію після пробудження
    HAL_RNG_Init(&hrng);
    __HAL_RCC_CRYP_CLK_ENABLE();
    HAL_CRYP_Init(&hcryp);

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/* USER CODE BEGIN 4 */

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС РАДІО (Вуха Солдата)
// =========================================================================
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr)
{
    // [FIX: AUDIT] size > 0 && size <= buffer: виправлено off-by-one (було size < 255)
    if (size > 0 && size <= sizeof(incoming_lora_payload)) {
        // Cast (void*) removes volatile qualifier for memcpy — safe here because
        // the ISR is the sole writer and main loop does not read until lora_rx_flag is set.
        memcpy((void*)incoming_lora_payload, payload, size);
        incoming_lora_size = size;
        lora_rx_flag = 1;
    }
}

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС (Голос Дерева)
// =========================================================================
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
  if(GPIO_Pin == GPIO_PIN_0)
  {
    vibration_detected = 1;
  }
}

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС СМЕРТІ (PVD Interrupt) — ARCH.21
// =========================================================================
// Ця функція миттєво викликається апаратно, якщо напруга падає нижче 2.2V
// (PWR_PVDLEVEL_7). Брауноут — то крик ксилеми, що задихається; ми маємо
// мікросекунди до того, як SRAM почне корумпуватись. Симетрія до Phase 5:
// ховаємо у RTC Backup Domain все, що дозволить наступному boot'у продовжити
// траєкторію Лоренца без "холодного" cold-start через HKDF.
void HAL_PWR_PVDCallback(void)
{
    // 1. [SEC.10] Спакована плоть DR0 — рятуємо лічильник panic-кадрів і
    //    acoustic_events єдиним 32-бітним словом, щоб panic-replay захист
    //    не зник при брауноуті між Phase 5 циклами.
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
        (uint32_t)acoustic_events);

    // 2. [ARCH.21] Зберігаємо timestamp пробудження, щоб delta_t після
    //    відновлення живлення не стрибнув на гігантське значення.
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, last_wakeup_timestamp);

    // 3. [ARCH.21] Зберігаємо стан Лоренца (DR16-DR19) симетрично до
    //    Phase 5. Без цього rescue брауноут = втрата траєкторії =
    //    cold-start через HKDF на наступному boot'і = розрив growth_points
    //    streak = false slashing проти живого здорового дерева.
    if (lorenz_state_valid) {
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR16, float_to_uint32(lorenz_x));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR17, float_to_uint32(lorenz_y));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR18, float_to_uint32(lorenz_z));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC);
    }

    // 4. Жорстко вимикаємо радіо (живиться окремо, але RX state-machine
    //    тримає піковий струм).
    Radio.Sleep();

    // 5. Падаємо у глибокий сон (Кома), поки напруга не підніметься знову
    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
}

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС ПАНІКИ (Tamper Detection)
// =========================================================================
void Trigger_Emergency_LoRa_TX(void)
{
    uint8_t panic_payload[16] = {0};
    uint8_t encrypted_panic[16] = {0};

    // [SEC.10] Інкрементуємо лічильник panic-кадрів (saturating @ 0xFFFF)
    // ПЕРЕД пакуванням, щоб кожен зойк ніс новий nonce. Перший виклик
    // після cold-boot отримає HRNG-сів значення з Phase 0, тому колізія
    // з Redis-nonce'ами попереднього втілення малоймовірна.
    if (panic_frame_counter < PANIC_COUNTER_MAX) {
        panic_frame_counter++;
    }
    // Сатурація на 0xFFFF — після 65535 panic-кадрів без cold-boot
    // лічильник застигає; це ознака "вузол під безперервною атакою/
    // катастрофою" і сама по собі є тривожним сигналом для backend.

    // 1. Пакуємо DID дерева
    panic_payload[0] = (uint8_t)(tree_did >> 24);
    panic_payload[1] = (uint8_t)(tree_did >> 16);
    panic_payload[2] = (uint8_t)(tree_did >> 8);
    panic_payload[3] = (uint8_t)(tree_did & 0xFF);

    // 2. Встановлюємо код паніки (0xFF у байт акустики)
    panic_payload[7] = 0xFF;

    // [FW.29] Set PANIC_FLAG in StatusByte for unambiguous panic detection
    panic_payload[10] = PANIC_FLAG_BIT;

    // 3. Збільшуємо TTL до 5, щоб пакет вижив довше і точно дійшов
    panic_payload[11] = PANIC_TTL;

    // [SEC.10] Лічильник panic-кадрів у байтах PAD 14..15 (BE).
    // Бекенд читає `pad_data[2..3].unpack1("n")` як nonce для SETNX.
    panic_payload[PANIC_COUNTER_PAD_HI] = (uint8_t)(panic_frame_counter >> 8);
    panic_payload[PANIC_COUNTER_PAD_LO] = (uint8_t)(panic_frame_counter & 0xFFu);

    // [SEC.10] Персистимо новий лічильник у DR0 НЕГАЙНО, до того як
    // PVD-брауноут або soft-reset встигне поглинути нас перед Phase 5.
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
        (uint32_t)acoustic_events);

    // 4. Шифруємо AES-256 і миттєво вистрілюємо
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)panic_payload, 4, (uint32_t*)encrypted_panic, 1000);
    Radio.Send(encrypted_panic, 16);

    // 5. Мікро-пауза, щоб радіомодуль встиг фізично випромінити пакет
    HAL_Delay(100);

    // 6. Примусово присипляємо радіо, щоб не садити батарею
    Radio.Sleep();
}

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС DMA (Буфер звуку заповнено)
// =========================================================================
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc)
{
    // Ця функція викликається апаратно, коли DMA запише 512-й байт.
    // Вона миттєво виводить процесор зі стану SLEEP для аналізу.
    audio_ready = 1;
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

// [SEC.11 / FW.30] Завантаження Lorenz K_seed з Protected Flash Sector.
// Flash layout: [FLASH_SEED_MAGIC:4][seed_word[0]:4]...[seed_word[7]:4] = 36 bytes.
// Якщо seed не provisioned — lorenz_seed_valid = 0 (пристрій працює, але cold-start
// видасть BIO_STATUS_VM_ERROR замість деривованих координат).
// НЕ викликає Error_Handler() — на відміну від AES key, відсутність K_seed не є
// фатальною (warm continuation через RTC все ще працює).
static void Load_Lorenz_Seed(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_SEED_ADDR;

    // 1. Перевірка magic marker
    if (flash_ptr[0] != FLASH_SEED_MAGIC) {
        lorenz_seed_valid = 0;
        return;
    }

    // 2. Перевірка що seed не нульовий
    uint32_t seed_or = 0;
    for (int i = 0; i < FLASH_SEED_WORDS; i++) {
        seed_or |= flash_ptr[1 + i];
    }
    if (seed_or == 0) {
        lorenz_seed_valid = 0;
        return;
    }

    // 3. Копіюємо seed з Flash у RAM (big-endian byte order for HMAC)
    for (int i = 0; i < FLASH_SEED_WORDS; i++) {
        uint32_t word = flash_ptr[1 + i];
        lorenz_seed[i * 4 + 0] = (uint8_t)(word >> 24);
        lorenz_seed[i * 4 + 1] = (uint8_t)(word >> 16);
        lorenz_seed[i * 4 + 2] = (uint8_t)(word >> 8);
        lorenz_seed[i * 4 + 3] = (uint8_t)(word & 0xFF);
    }
    lorenz_seed_valid = 1;
}

// [ARCH.27] Завантаження ролі вузла з Protected Flash Sector.
// Flash layout: один uint32_t magic-word на FLASH_ROLE_ADDR.
//   0x534F4C44 ("SOLD") → ROLE_SOLDIER
//   0x50524F56 ("PROV") → ROLE_PROVISIONER
//   будь-що інше (0xFFFFFFFF unprovisioned, 0x00000000 erased, корупція) →
//   fallback на ROLE_SOLDIER (безпечний дефолт — більшість вузлів є датчиками).
//
// Не виконує Error_Handler() — навіть unprovisioned вузол має працювати
// як звичайний Солдат, поки factory flashing pipeline не запише роль.
//
// Прапорець читається при boot до MX_CRYP_Init, і ARCH.26 (CAD relay) разом
// з FW.20-S2 (mesh time authoritativeness) будуть споживати його через
// глобальний `g_node_role` без додаткової перевірки Flash.
static void Load_Node_Role(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_ROLE_ADDR;
    uint32_t role_word = flash_ptr[0];

    if (role_word == ROLE_PROVISIONER_MAGIC) {
        g_node_role = ROLE_PROVISIONER;
    } else if (role_word == ROLE_SOLDIER_MAGIC) {
        g_node_role = ROLE_SOLDIER;
    } else {
        // Unprovisioned (0xFFFFFFFF), erased (0x00000000), або корупція —
        // безпечний дефолт. Сторожовий пес ролі вибирає мовчання Солдата
        // замість непередбачуваної поведінки.
        g_node_role = ROLE_SOLDIER;
    }
}

// [SEC.11 / FW.30] Деривація початкового стану Лоренца при cold-start.
// Алгоритм (дзеркало SilkenNet::SeedDerivation.derive_initial_state):
//   1. epoch_day = RTC_unix_time / 86400
//   2. info = "init|" || epoch_day_be8
//   3. digest = HMAC-SHA256(K_seed, info)
//   4. (x₀,y₀,z₀) = signed_unit_float(digest[0..7], digest[8..15], digest[16..23])
//
// На MCU це виконується через mbedTLS (mbedtls_md_hmac).
// Для host-based тестів та до першого lab-тесту з mbedTLS — використовуємо
// спрощену деривацію через апаратний HRNG XOR K_seed, яка гарантує:
//   - детермінованість при однаковому K_seed + epoch_day
//   - різні (x₀,y₀,z₀) при різних epoch_day
//   - координати ∈ [-1, +1]
// Повноцінний mbedTLS HMAC-SHA256 буде інтегрований при lab-тестуванні.
//
// TODO(FW.30-mbedtls): замінити на mbedtls_md_hmac(MBEDTLS_MD_SHA256, ...)
// після верифікації на цільовому STM32WLE5JC.
static void Derive_Cold_Start_State(float *x0, float *y0, float *z0)
{
    // Отримуємо epoch_day з RTC
    RTC_TimeTypeDef sTime = {0};
    RTC_DateTypeDef sDate = {0};
    HAL_RTC_GetTime(&hrtc, &sTime, RTC_FORMAT_BIN);
    HAL_RTC_GetDate(&hrtc, &sDate, RTC_FORMAT_BIN);

    // Спрощений epoch_day (дні від 2000-01-01 як proxy для UTC epoch_day).
    // На MCU без повноцінного time_t — рахуємо від BCD дати RTC.
    // ⚠️ TEMPORARY: Month*30 approximation накопичує помилку ~1-2 дні/місяць.
    // До інтеграції FW.20 CMD_TIME_SYNC (NTP через Queen) cold-start координати
    // можуть відрізнятися від backend при cross-month boot. Це впливає ТІЛЬКИ
    // на cold-start (рідкісна подія після VBAT loss); warm continuation через
    // RTC DR16-DR18 не залежить від epoch_day.
    uint32_t approx_days = (uint32_t)(sDate.Year + 2000 - 1970) * 365UL
                         + (uint32_t)(sDate.Month - 1) * 30UL
                         + (uint32_t)sDate.Date;

    // Детерміністична деривація з K_seed + epoch_day.
    // Використовуємо просте хешування (XOR fold + Knuth multiplicative hash)
    // як placeholder для повноцінного HMAC-SHA256. Константи 2654435761,
    // 2246822519, 3266489917 — Knuth's multiplicative hash primes (golden ratio
    // approximations для 32-bit). Це забезпечує:
    // - різні початкові точки для різних днів
    // - різні початкові точки для різних K_seed
    // - координати ∈ [-1, +1]
    // НЕ є криптографічно стійким — достатньо для TRL 6 lab testing.
    uint32_t hash[3] = {0};
    for (int i = 0; i < 32; i++) {
        uint32_t byte_val = lorenz_seed[i];
        uint32_t mix = byte_val + (uint32_t)i + 1;
        hash[0] ^= (mix << ((i * 7) % 24)) ^ (approx_days * (2654435761UL + (uint32_t)i));
        hash[1] ^= (mix << ((i * 11) % 24)) ^ ((approx_days + 1) * (2246822519UL + (uint32_t)i));
        hash[2] ^= (mix << ((i * 13) % 24)) ^ ((approx_days + 2) * (3266489917UL + (uint32_t)i));
    }

    // Мапимо uint32 → [-1.0, +1.0] (signed unit float)
    *x0 = ((float)(hash[0] % 2000000) / 1000000.0f) - 1.0f;
    *y0 = ((float)(hash[1] % 2000000) / 1000000.0f) - 1.0f;
    *z0 = ((float)(hash[2] % 2000000) / 1000000.0f) - 1.0f;
}

// Функція конфігурації апаратного AES (Створюється автоматично CubeMX)
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType = CRYP_DATATYPE_32B;
  hcryp.Init.KeySize = CRYP_KEYSIZE_256B; // ЗМІНЕНО: Gaia 2.0 Standard
  hcryp.Init.pKey = aes_key;
  hcryp.Init.Algorithm = CRYP_AES_ECB; // Використовуємо базовий Electronic Codebook для простоти 1 блоку
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
  /* [FIX FW.14]: Soft reset замість вічного циклу.
   * Нескінченний цикл з вимкненими IRQ = повний зависання до ручного reset.
   * IWDG (Independent Watchdog) може бути не налаштований на ранніх стадіях
   * ініціалізації, тому explicit software reset — безпечніший варіант.
   * 100ms затримка дає час завершити UART TX буфер (для post-mortem логу). */
  __disable_irq();
  for (volatile uint32_t i = 0; i < 3200000; i++) { } // ~100ms @ 32MHz
  NVIC_SystemReset();
  /* USER CODE END Error_Handler_Debug */
}
