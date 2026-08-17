/* USER CODE BEGIN Header */
// SPDX-License-Identifier: AGPL-3.0-or-later
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

// [FW.2] Бенч-атестація CCM-двигуна (POST). Компілюється ЛИШЕ у CCM_SELFTEST-збірці
// (у бойовій прошивці вимкнено). Header-only, сам підтягує lora_ccm.h.
#if defined(CCM_SELFTEST)
#include "../common/ccm_selftest.h"
// [ARCH.42] + POST транзитних шляхів ARCH.42 (ECB LoRa / CBC CoAP):
// ловить DataType/endianness-клас (DATATYPE_32B word-swap), невидимий для
// host-тестів і symmetric mesh-обміну, але фатальний для OpenSSL-бекенду.
#include "../common/sym_selftest.h"
volatile int g_ccm_selftest_failed = -1;  // читати через SWD: 0 = PASS (silicon == OpenSSL == backend)
volatile int g_sym_selftest_failed = -1;  // читати через SWD: 0 = PASS (ECB-128 + CBC-256 KAT)
#endif
#include <mruby/irep.h>
#include <mruby/array.h>
#include <math.h>     // [FW.6] isfinite() для валідації RTC Lorenz state
// [SEC.11 / FW.30] Pure-C HMAC-SHA256 деривація cold-start
// стану Лоренца — повний parity з backend SeedDerivation (без mbedTLS).
#include "../common/lorenz_seed.h"
#include "../common/ttl_byte.h"   // [FW.18b] бітфілд байта 11: [thr_invalid:5|TTL:3]
#include "did_derive.h"           // [FW.54 Вісь 2] DID = f(UID), recompute на boot
#include "../common/adc_convert.h" // [FW.50] VREFINT-калібровані мВ (One-Home з host-тестами)
#include "../common/wall_time.h"   // [FW.49] wall-clock guards + civil-інверсія (One-Home)
#include "../common/stack_canary.h" // [SEC.21] сів вартової канарки (One-Home з host-тестами)
#include "../common/fw_report.h"    // [SEC.20] wire-звіт contract-стану (байти 12..13 / CCM vpd)
#include "../common/mpu_regions.h"  // [SEC.21] MPU NX-stack/RO-code розкладка (draft)
#include "../common/device_event.h" // [SEC.21] uplink 0x57 device-event (canary-слід → Rails)
#include "../common/tdma_schedule.h" // [ARCH.26 L2] розклад синхронних вікон з маяка (One-Home)
#include "../common/cad_sniff.h"     // [ARCH.26 L3] CAD-нюх + PANIC-преамбула (One-Home)
#include "../common/tx_defer.h"      // [FW.10] зимовий кенозис TX: Should_Defer_TX (One-Home)
#include "../common/acoustic_ledger.h" // [ARCH.102] ледж акустики: споживає лише доставлене (One-Home)

// Підключаємо скомпільовану нейромережу TinyML.
// Якщо реальної моделі ще немає (модель ще не #include'нута → fallback; docs/03_03 §4) на
// IP-friendly stub з контрактом (Run_Inference signature, TENSOR_ARENA_SIZE,
// NUM_CLASSES) — це дозволяє make size-check / arm-none-eabi-size verify
// RAM-budget без розкриття IP моделі.
#if defined(__has_include) && __has_include("silken_net_audio_model.h")
#  include "silken_net_audio_model.h"
#else
#  include "silken_net_audio_model_stub.h"
#  warning "TinyML: silken_net_audio_model.h absent — using stub fallback (Run_Inference undefined; baseline normally committed, FW.4)"
#endif

// [FW.25] Акустичний DSP-фронтенд: 512-семпловий кадр → 40 log-mel ознак (Path B).
#include "../common/logmel.h"

// Підключаємо низькорівневий драйвер радіо (Radio Middleware)
#include "radio.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
#define MRUBY_CONTRACT_FLASH_ADDR 0x0803F000 // Адреса для OTA оновлень
// Версія C-ОБРАЗУ (compile-time; жива лише у CCM mesh_ctrl fw-nibble).
// ⚠️ bytecode-OTA її НЕ міняє — contract-версію на дріт несе fw_contract_report
// (байти 12..13, семантика common/fw_report.h; SEC.20).
#define FIRMWARE_VERSION_ID       0x0001

// [FIX: AUDIT MISRA] Іменовані константи замість магічних чисел
#define OTA_MARKER                0x99       // Маркер OTA-пакета (перший байт)
#define OTA_HEADER_SIZE           5          // [0x99][index:2][total:2]
#define MIN_OTA_PACKET_SIZE       6          // OTA_HEADER_SIZE + 1 байт даних мінімум
#define HMAC_TRAILER_MARKER       0x9B       // [FW.23] Маркер печатки OTA
#define HMAC_TRAILER_HEADER_SIZE  5          // [FW.23] [0x9B][seg_idx:2 BE][total:2 BE]
#define HMAC_TRAILER_SEG_BYTES    11         // [FW.23] Байт печатки на один LoRa-чанк
#define HMAC_TAG_BYTES            32         // [FW.23] HMAC-SHA256 = 32 байти істини
#define HMAC_TRAILER_TOTAL_SEGS   3          // [FW.23] 3 LoRa-чанки несуть 32-байтну печатку
#define HMAC_VERSION_SEG_IDX      4          // [FW.23] seg_idx=4 несе version_id (вхід HMAC)
#define OTA_TRAILER_TOTAL_CHUNKS  4          // [FW.23] 3 печатки + 1 версія
#define OTA_TRAILER_ALL_RECEIVED  0x0Fu      // [FW.23] bitmask: seg 1/2/3 + version
#define OTA_REQ_MARKER            0x55       // [FW.27-B] Маркер зойку «повтори, Королево» (Soldier→Queen)
#define OTA_REQ_HEADER_SIZE       7          // [FW.27-B] [0x55][DID:4][total_chunks:2 BE]
#define OTA_REQ_BITMAP_MAX_BYTES  9          // [FW.27-B] 16 - 7 header = 9 байт ⇒ ≤72 чанки на один зойк
#define OTA_REQ_PACKET_SIZE       16         // [FW.27-B] Один AES блок (16 байт fixed, post-ARCH.42 LoRa AES-128), як у телеметрії
// [FW.27-B] «5 хв тиші» → подати голос про пропуски. Лічимо ТИХІ ПРОБУДЖЕННЯ
// з відкритим вухом (Фаза 4.5), а не мілісекунди: HAL_GetTick заморожений у
// STOP2, тож tick-різниця міряла активний час і запізнювала зойк у ~6-15×.
// 10 пробуджень × цикл 26-32 с ≈ інтент «5 хв» (03_02 §5.1.3); EXTI-шторм
// (часті пробудження) лише пришвидшує — вухо й так відкривалось частіше.
#define OTA_REREQUEST_SILENT_WAKEUPS  10u    // [FW.27-B] тихих пробуджень до re-request
#define OTA_MISMATCH_RESET_THRESHOLD 3       // [FW.53] N поспіль чужих total → відпустити мертву кампанію
// Мітка помилки mruby VM на дроті: [panic:0|status:11=vm_error|growth:00000].
// [FW.29] Було 0xFF — після FW.29-маски (&~0x80) ставало 0x7F =
// status=3 + growth_points 31 → бекенд (×2) карбував 62 бали за КОЖЕН error-пакет.
// 0x60 переживає маску незмінним і чесно каже: довіри нема, емісії нема.
// [SLASH-1] status=3 — це НАШ софт-збій, не tamper: бекенд декодує його як
// vm_error → firmware_fault (ops-тріаж), справжня пилка кричить PANIC_FLAG'ом.
#define BIO_STATUS_VM_ERROR       0x60
#define VCAP_LISTEN_THRESHOLD     2800       // Поріг напруги для прослуховування ефіру (мВ)
// [FW.49 S1] delta_t — wall-секунди з RTC-календаря (LSE йде у STOP2);
// заморожений HAL_GetTick міряв лише active-час → m(delta_t) ≈ максимум
// у ВСІХ дерев → over-mint Proof-of-Growth. Guard-пороги дельти:
#define BASELINE_DELTA_T_S        60u        // нейтральний baseline (= mruby BASELINE_DELTA_T_S)
// [ARCH.102] «Метаболізм не виміряно» — сентинел, дзеркало mruby
// Attractor::DELTA_T_UNKNOWN_S. Нуль секунд між пробудженнями не є інтервалом
// перезаряду в жодному прочитанні, тож значення вільне. Guard-и wall-time і
// непрогріта EMA віддають САМЕ його: доти вони віддавали baseline 60, який
// mruby мапить у growth_points = МАКСИМУМ (див. bio_contract.rb).
#define DELTA_T_UNKNOWN_S         0u
#define DELTA_T_MAX_PLAUSIBLE_S   604800u    // 7 діб: довше = стрибок епохи (перший sync) / wrap
#define LORA_RX_TIMEOUT_MS        500        // Таймаут прийому LoRa (мс)
#define LORA_RX_LOOP_MS           600        // Максимальний час очікування пакета (мс)
#define TX_JITTER_MAX_MS          500        // Максимальна рандомізована затримка TX (мс)
#define PANIC_TTL                 5          // TTL для екстрених пакетів
#define DEFAULT_TTL               3          // Стандартний TTL для пакетів
#define PANIC_FLAG_BIT            0x80       // [FW.29] Bit 7 of StatusByte: panic disambiguation

// [SEC.10] Frame Counter anti-replay для panic packets.
// Кенозис лічильника: панічна плоть несе монотонне число у байтах 14..15
// (BE), а Королева бачить його як nonce. Сервер рубає replay через Redis SETNX.
// Сторожовий пес вмирає при cold boot — перший boot після VBAT-loss заново
// сіє лічильник з HRNG (range 0x0001..0xFFFF), щоб після відродження старі
// nonce'и Redis не закрили нову трансляцію.
#define PANIC_COUNTER_DR0_SHIFT   16          // DR0[31:16] = panic_frame_counter (uint16)
#define PANIC_COUNTER_MASK        0xFFFFu
// [SEC.20] DR0[9:8] = ota_vm_error_streak (0..3): N поспіль bytecode-збоїв →
// auto-fallback на embedded baseline. Vacant-байт DR0[15:11] (§2.3.2), DR7 цілий.
#define OTA_VM_ERR_STREAK_DR0_SHIFT 8
#define OTA_VM_ERR_STREAK_MASK      0x03u
#define SEC20_VM_ERROR_FALLBACK_N   3u
// [SEC.21] DR0[10] = canary_tripped: __stack_chk_fail лишає слід перед
// перевтіленням — переписаний кадр стека то потенційний слід атаки, він
// мусить пережити reset (RAM-слід згорів би разом зі стеком). Гаситиме
// майбутній wire-винос (event-кадр 0x57, 00_07 SEC.21); до того — sticky,
// читається SWD'ом на bench.
#define CANARY_TRIP_DR0_SHIFT       10
#define CANARY_TRIP_MASK            0x01u
// [FW.54 guard] DR0 bit-map compile-time non-overlap: panic[31:16] | rsv[15:11] |
// canary[10] | vm_err_streak[9:8] | acoustic[7:0]. Нова фіча, що вкраде слот
// (§2.3.2 vacant [15:11] або DR7), впаде ТУТ на компіляції — не тихо перекриє
// money-path-лічильник у полі.
_Static_assert(
    (((uint32_t)PANIC_COUNTER_MASK     << PANIC_COUNTER_DR0_SHIFT)     & 0xFFu) == 0u &&
    (((uint32_t)OTA_VM_ERR_STREAK_MASK << OTA_VM_ERR_STREAK_DR0_SHIFT) & 0xFFu) == 0u &&
    (((uint32_t)CANARY_TRIP_MASK       << CANARY_TRIP_DR0_SHIFT)       & 0xFFu) == 0u &&
    (((uint32_t)PANIC_COUNTER_MASK     << PANIC_COUNTER_DR0_SHIFT)     &
     ((uint32_t)OTA_VM_ERR_STREAK_MASK << OTA_VM_ERR_STREAK_DR0_SHIFT)) == 0u &&
    (((uint32_t)CANARY_TRIP_MASK       << CANARY_TRIP_DR0_SHIFT)       &
     (((uint32_t)PANIC_COUNTER_MASK     << PANIC_COUNTER_DR0_SHIFT) |
      ((uint32_t)OTA_VM_ERR_STREAK_MASK << OTA_VM_ERR_STREAK_DR0_SHIFT))) == 0u,
    "DR0 bit-map collision — panic[31:16]/canary[10]/vm_streak[9:8]/acoustic[7:0] перетнулись; ревізувати 03_01 §2");
#define PANIC_COUNTER_MAX         0xFFFFu     // Saturating maximum
#define PANIC_COUNTER_PAD_HI      14          // panic_payload[14] = counter MSB
#define PANIC_COUNTER_PAD_LO      15          // panic_payload[15] = counter LSB

// [FW.1 + ARCH.42 Variant B, 2026-05-23] Flash-based LoRa AES-128 key provisioning.
// Per-device unique key derived via HKDF-SHA256 on backend with info
// "silken-aes-128-lora-key" (HardwareKeyService.derive_lora_key). 16 bytes
// (4 × uint32_t). Узгоджено з SE050 Secure Element Slot 0 (AES-128 LoRa вибір,
// не SE-constraint). See docs/03_05 §3.7 (SE), §3.1 + docs/03_06 §2 (HKDF protocol).
//
// Factory Flashing writes lora_key to protected Flash sector 0x0803E000 via SWD
// (STM32CubeProgrammer). Magic marker "KEYL" guards against unprovisioned chips.
#define FLASH_KEY_ADDR            0x0803E000UL  // Protected Flash sector for LoRa AES-128 key
#define FLASH_KEY_WORDS           4             // 4 × uint32_t = 16 bytes = 128 bits (ARCH.42)
#define FLASH_KEY_MAGIC           0x4B45594CUL  // "KEYL" — LoRa key magic (post-ARCH.42; was "SKEY")

// [SEC.11 / FW.30] Flash-based Lorenz K_seed provisioning — per-device secret seed
// for HKDF-derived (x₀,y₀,z₀) cold start. Stored in the same Protected Flash Sector
// right after the AES key: [MAGIC:4][lora_key:16] | [SEED_MAGIC:4][seed[0]:4]...[seed[7]:4]
// = 20 + 36 = 56 bytes total before role byte (post-ARCH.42 layout, was 4+32=36 for AES-256).
// Factory Flashing writes K_seed via HardwareKeyService.provision (HKDF-SHA256).
// See docs/03_06 §3 for full protocol design.
#define FLASH_SEED_ADDR           (FLASH_KEY_ADDR + 20)  // After LoRa key (4 magic + 16 key = 20 bytes)
#define FLASH_SEED_WORDS          8             // 8 × uint32_t = 32 bytes
#define FLASH_SEED_MAGIC          0x4C534544UL  // "LSED" — Lorenz Seed magic marker
// EPOCH_SECONDS видалено [FW.30]: epoch_day тепер рахує
// lorenz_seed.h (SILKEN_EPOCH_SECONDS) — One-Home, без дубля константи.

// [FW.23] Flash-based OTA HMAC key (K_ota) provisioning — per-cluster 256-bit
// HMAC-SHA256 ключ для dual-gate автентифікації OTA-байткоду. Окрема Protected
// Flash сторінка 125 (0x0803E800, одразу після per-device key-сторінки 124),
// бо K_ota — per-КЛАСТЕР (broadcast), тоді як LoRa AES-key — per-DEVICE:
// польова заміна K_ota стирає СВОЮ сторінку, не чіпаючи per-device ключі.
// Сторінка 125 = канонічний «буфер росту key-блоку» (03_01 §2.3); первісна
// адреса 0x0803D000 колідувала з freeze-contract Flash-KV регіоном
// (сторінки 122-123) — mount KV стер би K_ota. Factory Flashing пише
// HKDF-SHA256(master, salt="cluster:<id>", info="silken-ota-hmac-v1") через SWD.
// Якщо magic відсутній — ota_hmac_key_valid=0: вузол НЕ застосує жоден OTA (fail-
// safe — без ключа нема як довести походження). НЕ Error_Handler() (телеметрія
// й Lorenz працюють без K_ota). Канон: docs/03_06 §4.
#define FLASH_OTA_KEY_ADDR        0x0803E800UL  // Сторінка 125 — за per-device key-сторінкою
#define FLASH_OTA_KEY_WORDS       8             // 8 × uint32_t = 32 bytes = 256-bit HMAC key
#define FLASH_OTA_KEY_MAGIC       0x4B4F5441UL  // "KOTA" — OTA HMAC key magic marker

// [FW.2 гейт (в), двоключова модель] Cluster control-plane ключ (KEYB) —
// спільний AES-128 всього кластера для ВСЬОГО, що не є телеметрією/panic:
// downlink-broadcast Королеви (0x99/0x9A/0x9B/0x9C/0x9D/0x9E — один TX на
// всіх → один ключ by construction) + uplink-запити 0x55/0x56 (Королева
// читає їх сама, session-ключів вона не тримає — 03_05 §3.1). Телеметрія й
// panic натомість їдуть CCM'ом на per-device session-ключі (KEYL вище).
// Сторінка 125 = cluster-membership (KOTA+KEYB): переїзд дерева між
// кластерами стирає/пише ЛИШЕ її, per-device identity (стор. 124) живе.
// Зсув +40, не +36: K_ota займає 36 Б, а WL програмує Flash 64-бітними
// doubleword'ами — старт KEYB у другій половині недописаного dw
// спричинив би ECC-fault при фабричному -w32. Деривація —
// HKDF(master, "cluster:<id>", "silken-aes-128-broadcast-key") — дзеркало
// HardwareKeyService.derive_broadcast_key; ротація = re-provision (як
// K_ota; FW.17-ратчет цього ключа СВІДОМО не торкається). Канон: 03_05 §2.1
// flip-checklist (в) + §3.1.
#define FLASH_BCAST_KEY_ADDR      (FLASH_OTA_KEY_ADDR + 40)  // після K_ota (36 Б) + dw-паддінг
#define FLASH_BCAST_KEY_WORDS     4             // 4 × uint32_t = 16 bytes = AES-128
#define FLASH_BCAST_KEY_MAGIC     0x4B455942UL  // "KEYB" — cluster broadcast/control key

// [ARCH.27] Node Role Differentiation — плоть і кров mesh-розшарування.
// Один і той самий бінарник прошивки тече венами Солдата та Провідника;
// роль розрізняється єдиним 32-бітним словом у тій самій Protected Flash
// сторінці одразу після K_seed (теж під WRPROT). Magic-слово саме служить
// носієм ролі — без додаткового sentinel-байту. Сторінка не provisioned
// або корумпована → fallback на ROLE_SOLDIER (безпечний дефолт).
//
// Layout (post-ARCH.42 Variant B):
//   [LORA_KEY_MAGIC:4][AES_KEY:16] | [SEED_MAGIC:4][K_SEED:32] | [ROLE_WORD:4]
//   ^FLASH_KEY_ADDR (0x0803E000)     ^FLASH_SEED_ADDR (+20)      ^FLASH_ROLE_ADDR (+56)
// Total: 4 + 16 + 4 + 32 + 4 = 60 bytes (was 4+32+4+32+4 = 76 before ARCH.42).
#define FLASH_ROLE_ADDR           (FLASH_KEY_ADDR + 56)  // After K_seed (20 LoRa key block + 36 seed block = 56 bytes)
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
// [FW.1 + ARCH.42 Variant B, 2026-05-23] LoRa AES-128 key — завантажується з
// Protected Flash Sector при boot. Factory Flashing записує per-device ключ
// (HKDF-SHA256 з info "silken-aes-128-lora-key") на адресу FLASH_KEY_ADDR через
// SWD. Формат Flash: [FLASH_KEY_MAGIC:4][key[0]:4]...[key[3]:4] = 20 байт
// (post-ARCH.42; було 36 байт для AES-256).
// Якщо ключ не provisioned — Error_Handler() (пристрій не може працювати без ключа).
// Hardcoded значення нижче — ТІЛЬКИ для ініціалізації змінної до виклику Load_AES_Key().
uint32_t aes_key[4] = {0};   // 16 bytes = AES-128 (ARCH.42 LoRa-вибір; SE = SE050 — 03_05 §3.7)

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
// acoustic_events у DR0[7:0] (DR0[15:10] резервовано). Сторожовий пес
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
uint8_t ml_event_id = 0;          // Результат: 0-Тиша, 1-Вітер, 2-Кавітація, 3-Пилка, 4-Фауна
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
// 03_03 §5 (CRITICAL зони).
//
// SSOT для розташування RTC регістрів: 03_01 §2 (Soldier RTC Backup Map).
// DR13/DR14 тримають ці два пороги TinyML; повна розкладка — там, не дублюємо.
#define TINYML_DEFAULT_WARNING       0.60f
#define TINYML_DEFAULT_CRITICAL      0.85f
#define TINYML_THRESHOLD_MIN_VALID   0.01f
#define TINYML_THRESHOLD_MAX_VALID   0.99f
#define TINYML_WARNING_ESCALATION    3   // 3× WARNING поспіль → ескалація CRITICAL

float   tinyml_warning_threshold  = TINYML_DEFAULT_WARNING;
float   tinyml_critical_threshold = TINYML_DEFAULT_CRITICAL;
uint8_t ota_vm_error_streak       = 0;   // [SEC.20] DR0[9:8]-persist: N поспіль bytecode-збоїв → fallback
uint8_t canary_tripped            = 0;   // [SEC.21] DR0[10]-persist: слід __stack_chk_fail з минулого втілення
uint8_t canary_evt_shots          = 0;   // [SEC.21] залишок 0x57-пострілів (RAM — живе крізь STOP2)
uint16_t canary_evt_seq           = 0;   // [SEC.21] per-boot seq 0x57 (дедуп Rails SETNX)
// [SEC.20] Wire-звіт contract-стану (fw_report.h): рахується раз на boot у
// contract-select. Дефолт = legacy C-image константа (semantic=0) — чесна
// деградація, доки KV/contract не оглянуті.
uint16_t fw_contract_report       = FIRMWARE_VERSION_ID;
uint8_t warning_counter           = 0;   // Послідовні WARNING-події між cold-boot;
                                          // SRAM зберігається в STOP2, скидається
                                          // лише при VBAT-loss / IWDG / NVIC reset.

// [FW.42] Vcap guard для fauna acoustic sampling.
//
// SSOT — docs/03_03 §10.3 + docs/00_07 FW.42.
//
// Один fauna-сеанс (5 с моноліт @ 16 кГц = 156 послідовних MFCC+INT8
// inference вікон) коштує ~78 мДж: ~16 мДж wait + ~62 мДж активного CPU
// при ~12 мА протягом ~1.56 с. Це **імпульсне** навантаження ~40 мВт,
// яке просаджує EDLC. Якщо сесія стартує при V_cap, близькому до
// VBAT_OK ON (~3.4 V), просадка може кинути напругу нижче порогу
// Buck'а посеред інференсу → reset. Тому fauna sampling запускається
// лише коли V_cap ≥ FAUNA_VCAP_MIN_MV (margin ~1.1 V над VBAT_OK ON).
//
// Цей блок — **freeze-contract helper**: викликається з fauna-pathway,
// яку FW.4 (Run_Inference) вже споживає — виклик живий нижче, у гарячій петлі.
// До того моменту функція компілюється і покрита host-тестами, тож
// активація — це 2 рядки виклику у TinyML гілці без додаткової роботи.
//
// Backend-симетрія (опційно, post-FW.4): метрика
// `fauna_skipped_low_vcap_total` у Prometheus → Grafana панель
// "Fauna skip rate per cluster" → дерева з skip rate > 50% мають
// деградований EBFC або зимовий період.
#define FAUNA_VCAP_MIN_MV  4500u   // мВ — мін. V_cap для безпечного сеансу

uint8_t fauna_skipped_low_vcap = 0; // saturating uint8 counter (SRAM)

// КОНТРАКТ call-site: vcap_mv — МІЛІВОЛЬТИ (adc_convert.h). Зараз це
// VDDA-проксі (≈3300, стеля VREFINT-тракту < 4500) ⇒ guard fail-CLOSED:
// brownout неможливий, fauna свідомо спить до живого Vcap-каналу з
// дільником (FW.50 hardware; повний EDLC 5500 > поріг) — розгейт залізом,
// не зниженням порогу. Tripwire-тест:
// test_fw42_raw_adc_range_always_skips_fail_closed.
static uint8_t Fauna_Should_Sample(uint16_t vcap_mv)
{
    if (vcap_mv >= FAUNA_VCAP_MIN_MV) return 1;
    if (fauna_skipped_low_vcap < 255) fauna_skipped_low_vcap++;
    return 0;
}

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

// [FW.27-B] Magic Re-Request: tick останнього прийнятого OTA-чанку.
// 0 = ніколи не чули OTA (чекаємо першої проповіді) — лишається маркером
// «вже чули»; саму тишу міряє ota_silent_wakeups (tick мертвий у STOP2).
uint32_t ota_last_chunk_rx_tick = 0;

// [FW.27-B] Лічильник пробуджень із відкритим вухом БЕЗ нового OTA-слова.
// Скидається кожним прийнятим чанком (0x99/0x9B) і після відправленого
// зойку (даємо Королеві стільки ж часу на ретрансляцію). SRAM: переживає
// STOP2, гине разом із OTA-буфером при VBAT-loss — узгоджено.
uint8_t ota_silent_wakeups = 0;

// [FW.53] Сторожовий лічильник зміни кампанії: якщо Солдат
// застряг із недозібраною прошивкою (total=X), а Королева вже проповідує
// нову (total=Y), стара пам'ять блокувала б нове слово ДОВІКУ (reset був
// лише при завершенні збірки). N поспіль чужих total → жертовно стираємо
// стару незавершену кампанію і відкриваємось новій.
uint8_t ota_total_mismatch_streak = 0;

// [FW.23] HMAC-печатка OTA — 32-байтне свідчення істини, яке надходить
// після тіла прошивки у 4-х 16-байтних LoRa-чанках з маркером 0x9B.
// Збираємо посегментно: seg_idx=1 → bytes[0..10], seg_idx=2 → bytes[11..21],
// seg_idx=3 → bytes[22..31] + 1 байт PAD, seg_idx=4 → version_id (BE). Бітмаска
// ota_hmac_segments_received: біти 0/1/2 = печатка, біт 3 = версія. Усі 4 чанки
// (== OTA_TRAILER_ALL_RECEIVED 0x0F) ⇒ маємо і печатку, і version_id, потрібний
// як вхід HMAC — повний підпис готовий до перевірки двома брамами у Phase 4.5.
uint8_t  received_hmac_tag[HMAC_TAG_BYTES] = {0};
uint8_t  ota_hmac_segments_received = 0;        // Bitmask seg 1/2/3 + version (біт 3)
uint32_t received_ota_version = 0;              // [FW.23] version_id з seg_idx=4 (вхід HMAC)

// [FW.23] K_ota — per-cluster 256-bit HMAC ключ для OTA dual-gate.
// Завантажується з Protected Flash через Load_Ota_Hmac_Key() при boot.
// ota_hmac_key_valid==0 (не provisioned) ⇒ жоден OTA не застосовується (fail-safe).
uint8_t  ota_hmac_key[32] = {0};
uint8_t  ota_hmac_key_valid = 0;

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
// 16-байтний відкритий текст (після AES-128-ECB decrypt, post-ARCH.42):
//   [0x9C][unix_ts_be:u32][резерв:0×4][TTL][магія 'B'][padding:0×5]
// Солдат дивиться на байт 0 розшифрованого RX-payload — відрізняється від
// OTA (0x99), телеметрії (починається з DID, ніколи не 0x9C) та текстового
// CMD:. Маяк споживаємо локально (дрейф RTC); Провідник може понести його
// далі — mesh-relay з anti-storm журналом (FW.20-S2, гейт нижче).
#define BEACON_MARKER             0x9C
#define BEACON_MAGIC_BYTE         0x42  // 'B'
#define BEACON_PLAINTEXT_SIZE     16
// [FW.20-S2] Біт 7 байту 9: 1 = маяк прямо від Королеви (authoritative),
// 0 = relay-маяк через Провідника або легасі-формат. TTL фактично займає
// нижні 7 біт (max 127); Королева транслює TTL=2 (1 relay-хоп).
#define BEACON_AUTH_FLAG          0x80
#define BEACON_TTL_MASK           0x7F

// [FW.20-S1] Солдатські UTC-секунди як єдине джерело істини + локальний tick
// останньої синхронізації для розрахунку дрейфу. Використовується
// Derive_Cold_Start_State() для детермінованого epoch_day (точно як у
// бекенді SilkenNet::SeedDerivation). Без синхронізованого значення
// фолбек на застарілу RTC-date-апроксимацію.
volatile uint32_t soldier_unix_ts            = 0;
volatile uint32_t soldier_unix_ts_local_tick = 0;

// [ARCH.26 L2] Кеш TDMA-розкладки з байтів 5..8 маяка. RAM-only derived
// state (як soldier_unix_ts): гине з SRAM у RTC-only STOP2 / VBAT-loss і
// відновлюється наступним маяком (≤15 хв) — RTC DR і Flash-KV не потрібні
// (бюджет DR повний, 03_01 §2). Гейт INERT: фліп = bench WUT-армінг
// (SEC.15/FW.49); математика вікон/слотів — common/tdma_schedule.h.
#define ARCH26_TDMA_ENABLED       0
#if ARCH26_TDMA_ENABLED
static TdmaSchedule g_tdma_schedule = {0u, 0u, 0u, 0u};
#endif

// [ARCH.26 L3] CAD-нюх Провідника + PANIC extended-preamble. Політика —
// 03_01 §1.9; енерго-double-bind — 02_03 §9.10: async-зловлення несумісне
// з чистим EBFC (нюх ≥ одиниці Дж/добу проти харвесту ~1.3), тому нюх =
// привілей surplus-Провідника (ARCH.27, роль-гейт у cad_sniff.h), а
// EBFC-відправник мінімізує СВІЙ бік — преамбула 4 с ≈ 0.6 Дж («останній
// зойк», ~23% EDLC) за дворівневим Vcap-гейтом (FW.42-патерн; поріг 4500 >
// стелі VREFINT-тракту → до FW.50 extended-half чесно fail-closed).
// Гейт INERT (окремий від L2 — фліпи незалежні): фліп = bench WUT-армінг
// @ T_sniff + PPK2 CAD-профіль (00_07 ARCH.26). OnCadDone стрельне лише
// після реєстрації RadioEvents_t на HAL-фазі (FW.46, доля OnRxDone).
#ifndef ARCH26_CAD_ENABLED
#define ARCH26_CAD_ENABLED        0  // 🟡 фліп = bench (compile-lane: -D через hal_check_ccm)
#endif
#if ARCH26_CAD_ENABLED
// Модуляція PANIC-TX = Scenario C (02_03 §9.8): SF9 / BW125 / CR4-5 / +14 дБм.
// Semtech SetTxConfig LoRa-кодування: bandwidth 0 = 125 кГц, coderate 1 = 4/5.
#define LORA_PANIC_TX_POWER_DBM   14
#define LORA_PANIC_BW_125K        0u
#define LORA_PANIC_SF             9u
#define LORA_PANIC_CR_4_5         1u
static uint32_t g_last_cad_sniff_wall = 0u;  // RAM-only маркер (як g_tdma_schedule)
volatile uint8_t g_cad_activity = 0u;        // ставить OnCadDone; читач = bench
                                             // WUT-цикл «нюх-замість-RX» (RUNBOOK)
#endif

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
// ПРИЧИНА defer: усі 20 RTC Backup Register'и (DR0..DR19) зайняті — після
// FW.2 freeze-contract навіть DR15 пішов під CCM Frame Counter; вільного слоту
// немає, а 8-байтний body порогів нікуди покласти без Flash-KV. Повна розкладка
// — SSOT 03_01 §2 (Canonical Backup Map), тут НЕ дублюємо.
//
// Альтернативи відкинуто:
//   • Flash sector — 2 KB на 8 байт, wear ~10k erase × at-most-daily re-send
//     дає 27 років, але erase ~30 мс блокує LoRa RX → конфлікт з anti-pingpong
//     RX-вікном після TX. Не виправдано для feature, що на TRL-6 нічого не
//     змінює (всі 5 видів зараз використовують ті самі firmware-defaults).
//   • RAM-only з re-send щодня × 100k дерев = ~5% всього NB-IoT downlink
//     заради no-op feature. Чесніше відкласти.
//
// ВІДНОВЛЕННЯ: вільних RTC-регістрів не лишилось (DR15 → FW.2), тож FW.8
// повертається через Flash-KV overflow (03_01 §2.3), а не звільнений регістр.
// Persist-логіка ✅ host-готова: ../common/lorenz_thresholds.h — Save/Load на
// ключах 0x10/0x11 (порвана/невалідна пара → дефолти; power-cut тести у
// test_flash_kv.c). Mount KV + HAL_FLASH глю ✅ написано (секція FW.17 нижче,
// спільний гейт `FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED`). Wiring
// Save/Load ✅ написано за цим же гейтом: boot-restore після mount'а,
// КЕНОЗИС-write по dirty-флагу прийнятого 0x9A. Лишається bench: фліп
// `FW8_PARSER_ENABLED 1` + верифікація HAL-глю на кремнії.
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

// [FW.8] Save/Load порогів поверх Flash-KV (ключі 0x10/0x11) — One-Home
// ../common/lorenz_thresholds.h; дефолти там дзеркалять LORENZ_DEFAULT_*.
#include "../common/lorenz_thresholds.h"

#if FW8_PARSER_ENABLED
static uint8_t lorenz_thresholds_dirty = 0; // прийнятий 0x9A → Save у КЕНОЗИСІ
#endif

// CRC-16/CCITT-FALSE — One-Home у common/silken_crc.h [FW.53]
// (спільний з Queen та host-тестами; дзеркало OtaPackagerService.crc16_ccitt).
#include "../common/silken_crc.h"

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
    uint16_t expected_crc = Silken_Crc16_Ccitt(body, CMD_THRESHOLDS_BODY_SIZE);
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
// [FW.17] Hash-Ratchet ротація LoRa-ключа (CMD_ROTATE_KEY 0x9E)
// =========================================================================
// Ключ ніколи не летить ефіром: кадр каже лише «дожени версію N», обидва
// кінці синхронно деривують K_{v+1} (NIST SP 800-108 HMAC-KDF; One-Home:
// ../common/key_ratchet.h ↔ Cryptography::KeyRatchet, golden-KAT parity у
// test_key_ratchet.c). Persist — ЛИШЕ версія у Flash-KV (ключ 0x13): журнал
// append-only не сміє тримати ключового матеріалу; boot re-derive
// K_current = ratchet^v(K0 з Protected Flash).
//
// 🟡 СТАТУС: гілка ВИМКНЕНА (FW17_RATCHET_ENABLED 0) — фліп ЛИШЕ після
// FW.2 CCM: ECB-downlink без MAC не сміє командувати ротацією (підроблений
// 0x9E двигає версію вперед → desync → вузол глухне для бекенда; Dual-Key
// Grace страхує лише авторизовану ротацію). Другий передзамок — Flash-KV
// mount (нижче): без persist'у версії VBAT-loss повертає вузол на K0, поки
// бекенд на K_v. Канон: 03_05 §3.8; реєстр KV-ключів — 03_01 §2.3.1.
#include "../common/key_ratchet.h"
#include "../common/flash_kv.h"

#define FW17_RATCHET_ENABLED   0      // 🟡 фліп після FW.2 CCM + KV mount (bench)
#define FW17_KV_KEY_VERSION    0x13u  // Flash-KV: [version:16 | rsv:16] (03_01 §2.3.1)

// [ARCH.28 шлях A] Flash-KV журнал: сторінки 122-123 (freeze-contract
// 03_01 §2.3; K_ota тому переїхав на сторінку 125 — первісний 0x0803D000
// колідував із цим регіоном). Mount спільний для споживачів FW.17 (версія
// ratchet'а), FW.8 (Z-пороги, ../common/lorenz_thresholds.h) та FW.2
// (FC high-water, ../common/fc_hiwater.h) — його вмикає будь-який із флагів.
#define FLASH_KV_BASE_ADDR     0x0803D000UL
#define FLASH_KV_FIRST_PAGE    122u
#define FLASH_KV_PAGE_DWS      256u   // 2 КБ / 8 Б на dw-елемент

// [FW.2] Гейт усієї CCM-гілки (сама гілка — секція внизу файла). Define
// живе тут, бо KV-mount спільний: FC high-water (TRL-7 монотонна межа,
// політика 03_05 §2.1) їде у Flash-KV ключем 0x14 і мусить вмикати mount.
// #ifndef — щоб CI compile-варіант міг зібрати гілку `-DFW2_CCM_ENABLED=1`
// проти справжнього WL-HAL, не чіпаючи бойового дефолту 0.
#ifndef FW2_CCM_ENABLED
#define FW2_CCM_ENABLED  0  // freeze-contract — flip після HAL verification (RUNBOOK §2)
#endif
#include "../common/fc_hiwater.h"

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
// Прототип: тіло живе у freeze-contract секції внизу файла, а call-sites
// (Фаза 4 TX + Trigger_Emergency_LoRa_TX) — вище за течією.
int Soldier_Build_CCM_LoRa_Packet(
    uint32_t did, uint16_t vcap_mv, int8_t temp_c, uint8_t acoustic,
    uint16_t delta_t_s, uint8_t status_byte, uint8_t mesh_ctrl,
    uint16_t device_z, uint8_t diag, uint8_t vpd_index, uint8_t gossip_ts_lsb,
    uint16_t ema_delta_t_s,
    uint8_t out_packet[FW2_CCM_AIR_PACKET_LEN]);
#endif

#if FW2_CCM_ENABLED
static uint32_t fc_hiwater_cache    = 0; // RAM-кеш межі; істина — Flash-KV 0x14
static uint8_t  fc_hiwater_degraded = 0; // TX перетнув межу, Flash мовчить —
                                         // діагностика; wire-транспорту поки
                                         // нема (PAD повний — патерн FW.42)
#endif

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
// [FW.2 гейт (в), двоключова модель] Cluster control-plane ключ (KEYB,
// стор. 125) — амбієнтний ECB-ключ CCM-ери: RX-decrypt всього downlink'а +
// TX 0x55/0x56 (Королева читає їх сама — session-ключів вона не тримає).
// Телеметрія й panic беруть session (aes_key) всередині
// Soldier_Build_CCM_LoRa_Packet. За гейтом: бойовий .bss ECB-ери незмінний
// (+17 Б лише з фліпом). Канон: 03_05 §2.1 flip-checklist (в).
uint32_t bcast_key[4] = {0};
uint8_t  bcast_key_is_fallback = 0; // 1 = KEYB-слот порожній → живемо на KEYL
                                    // (bench-плата, прошита до KEYB-ери)

// [E.63 (г)] Wire-байти 20..21: EMA-delta_t, ЯК він пішов у metabolic_health
// цього циклу (контракт «wire = вхід GP» — Фаза 3 виставляє ДО гілкування,
// VM_ERROR-кадр несе чесне поточне значення). Panic-шлях шле 0 (не-homeostasis,
// recompute скипається бекендом).
static uint16_t wire_ema_delta_t_s = 0;
#endif

// [FW.20-S2 4/5] Гейт повного mesh-relay Time Beacon'а: Провідник несе далі
// й relay'ні маяки (auth=0), шторм гасить журнал поколінь у Flash-KV 0x20
// (../common/beacon_dedup.h — політика й чому Flash, не SRAM). Фліп ЛИШЕ
// після bench-верифікації Flash-KV HAL-глю (та сама умова, що FW.17/FW.8):
// без журналу дедуп тримається тільки на auth-біті (2-hop стеля, NULL-гілка
// Soldier_Try_Relay_Time_Beacon). Королева вже транслює TTL=2 (03_02 §5а).
#define FW20_MESH_RELAY_ENABLED 0
// [SEC.20] Anti-rollback — перший НЕ-gated споживач journal Flash-KV: база
// (ops+mount) мусить жити НЕЗАЛЕЖНО від фліп-гейтів фіч (OTA живий завжди).
#define SEC20_OTA_ANTIROLLBACK_ENABLED 1
#include "../common/beacon_dedup.h"

#if FW20_MESH_RELAY_ENABLED
static BeaconDedup beacon_dedup; // RAM-кеш журналу; істина — Flash-KV 0x20
#endif

#if FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED || FW2_CCM_ENABLED || FW20_MESH_RELAY_ENABLED || SEC20_OTA_ANTIROLLBACK_ENABLED
// Збірка при фліпі: + ../common/flash_kv.c (як test_flash_kv). Тут — реальні
// залізні примітиви; host-тести ганяють ту саму журнальну логіку на RAM-моці
// з fault-injection (power-cut посеред compact), HAL-глю верифікує bench.
static uint64_t Soldier_KvReadDw(void *io, uint32_t byte_off)
{
    (void)io;
    return *(const uint64_t *)(FLASH_KV_BASE_ADDR + byte_off);
}

static int Soldier_KvProgramDw(void *io, uint32_t byte_off, uint64_t v)
{
    (void)io;
    HAL_FLASH_Unlock();
    HAL_StatusTypeDef st = HAL_FLASH_Program(FLASH_TYPEPROGRAM_DOUBLEWORD,
                                             FLASH_KV_BASE_ADDR + byte_off, v);
    HAL_FLASH_Lock();
    return st == HAL_OK;
}

static int Soldier_KvErasePage(void *io, uint8_t page)
{
    (void)io;
    FLASH_EraseInitTypeDef erase = {0};
    uint32_t page_error = 0;
    erase.TypeErase = FLASH_TYPEERASE_PAGES;
    erase.Page      = FLASH_KV_FIRST_PAGE + page;
    erase.NbPages   = 1;
    HAL_FLASH_Unlock();
    HAL_StatusTypeDef st = HAL_FLASHEx_Erase(&erase, &page_error);
    HAL_FLASH_Lock();
    return st == HAL_OK;
}

static const FlashKvOps soldier_kv_ops = {
    Soldier_KvReadDw, Soldier_KvProgramDw, Soldier_KvErasePage
};
static FlashKv soldier_kv;
static uint8_t soldier_kv_mounted = 0;
#endif // FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED || FW2_CCM_ENABLED || FW20_MESH_RELAY_ENABLED || SEC20_OTA_ANTIROLLBACK_ENABLED

#if FW17_RATCHET_ENABLED
static void MX_CRYP_Init(void); // повний прототип нижче — потрібен re-key'ю

static uint16_t lora_key_version       = 0; // RAM-копія; істина — Flash-KV 0x13
static uint8_t  lora_key_version_dirty = 0; // запис у КЕНОЗИСІ, не під RX-вікном

// Boot-restore: версія з Flash-KV → K_current = ratchet^v(K0). Викликати
// ПІСЛЯ Load_AES_Key (K0 вже у aes_key) і ПІСЛЯ генерації tree_did (DID =
// Context у KDF). Mount-fail / порожній KV → лишаємось на K0: target у 0x9E
// абсолютний, тож бекендова команда дожене вузол при наступному downlink'у.
static void FW17_Restore_Key_Version(uint32_t did)
{
    uint32_t stored = 0;
    if (!soldier_kv_mounted) return;
    if (!FlashKv_Get32(&soldier_kv, FW17_KV_KEY_VERSION, &stored)) return;

    lora_key_version = (uint16_t)(stored & 0xFFFFu);
    if (lora_key_version == 0) return;

    uint8_t key_bytes[KEY_RATCHET_KEY_LEN];
    Key_Ratchet_Words_To_Bytes(aes_key, key_bytes);
    Key_Ratchet_Apply(key_bytes, lora_key_version, did);
    Key_Ratchet_Bytes_To_Words(key_bytes, aes_key);
    MX_CRYP_Init(); // CRYP тепер на K_v — інакше Королеву не почуємо
}
#endif // FW17_RATCHET_ENABLED

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
// Сторожовий пес часу: коли тиша від останнього beacon'а перевищує
// TIME_SYNC_DRIFT_THRESHOLD_WAKEUPS (≈12 год пробуджень — tick мертвий у
// STOP2, wall-квант = пробудження), Солдат подає голос — uplink LoRa-плейн
// з опкодом 0x56, щоб Королева повторила beacon. Cooldown (≈1 год
// пробуджень) запобігає спаму при тривалій тиші Королеви.
//
// SSOT для опкодів: 03_01 §4.5а Downlink Opcode Map. 0x56 — uplink-діапазон
// поряд з 0x55 (FW.27-B OTA Re-Request); 0x9C beacon — downlink і не
// перетинається. Магія 'S' у байті 10 — миттєва дезамбігвація з 0x55 magic 'R'.
//
// Вшито у hot path обабіч ФАЗИ 4: cold-boot hello (ARCH.41-C — 0x56 ЗАМІСТЬ
// телеметрії у grace-вікні, щоциклово) та warm-зойк watchdog'а (0x56 ПОВЕРХ
// телеметрії, cooldown-гейт). Mesh-relay маяка між Солдатами — RX-гілка
// Сценарію 0 за гейтом FW20_MESH_RELAY_ENABLED (фліп = bench Flash-KV HAL).
#define SYNC_REQ_MARKER                  0x56       // [FW.20-S2] Uplink: «Королево, час!»
#define SYNC_REQ_MAGIC_BYTE              0x53       // [FW.20-S2] 'S' = sync — у байті 10
#define SYNC_REQ_PACKET_SIZE             16         // Один AES-128-ECB блок (post-ARCH.42)
// Час-пороги — у ПРОБУДЖЕННЯХ, не мілісекундах: HAL_GetTick заморожений у
// STOP2, tick-різниця міряла лише active-час (~2-5 с/цикл) і розтягувала
// інтервали у ~6-15× wall (та сама пастка, що FW.27-B тиша). Цикл 26-32 с
// (IWDG-вікно) → пробудження і є wall-квант Солдата.
#define TIME_SYNC_DRIFT_THRESHOLD_WAKEUPS 1440u     // ≈12 год без beacon'а → панікуємо
#define TIME_SYNC_REQUEST_COOLDOWN_WAKEUPS 120u     // ≈1 год між повторними зойками
#define TIME_SYNC_COLD_BOOT_GRACE_WAKEUPS  20u      // ≈10 хв після boot перш ніж панікувати
                                                    // (Soldier ще чекає першого beacon'а)
#define SOLDIER_NOMINAL_CYCLE_S          30u        // номінал циклу для wire-конверсії wakeups→сек
#define TIME_SYNC_REQ_PAD_BYTES          5          // [11..15] — резерв під майбутні поля

// Wall-кванти Солдата (SRAM: переживають STOP2, гинуть з VBAT — і це
// правильно: cold-boot перезапускає grace). Сатуруються, не обертаються.
uint16_t wakeups_since_boot         = 0; // [ARCH.41-C] grace-вікно cold-boot
uint16_t wakeups_since_sync         = 0; // тиша від останнього beacon'а (drift-watchdog)
uint16_t wakeups_since_sync_request = 0; // cooldown зойків 0x56
uint8_t  sync_request_ever          = 0; // 0 = ще не просили (перший зойк без cooldown)

// Чи варто Солдату просити re-broadcast beacon'а? (wall-кванти = пробудження)
// Інваріанти:
//   1. Якщо ще не отримували жодного beacon'а (soldier_unix_ts == 0):
//      - Перші TIME_SYNC_COLD_BOOT_GRACE_WAKEUPS — терпимо тишу,
//        Королева могла ще не вийти на TX-вікно.
//      - Після grace — просимо.
//   2. Якщо отримували beacon, але тиша вже ≈12 год пробуджень → просимо.
//   3. Cooldown: якщо вже просили <≈1 год пробуджень тому — не спамимо ефір.
// Повертає 1 (треба просити) або 0 (мовчати).
static uint8_t Soldier_Should_Request_Time_Sync(void)
{
    // Cooldown guard: перше прохання (sync_request_ever == 0) проходить завжди.
    if (sync_request_ever &&
        wakeups_since_sync_request < TIME_SYNC_REQUEST_COOLDOWN_WAKEUPS) {
        return 0;
    }

    if (soldier_unix_ts == 0) {
        // Cold-boot: ще ніколи не чули beacon'а. Дочекаємося grace.
        return (wakeups_since_boot >= TIME_SYNC_COLD_BOOT_GRACE_WAKEUPS) ? 1 : 0;
    }

    // Warm: тиша від останнього beacon'а у пробудженнях.
    return (wakeups_since_sync >= TIME_SYNC_DRIFT_THRESHOLD_WAKEUPS) ? 1 : 0;
}

// Приблизні секунди тиші від останнього beacon'а (0 якщо ще не чули) —
// wire-поле 0x56 для масштабу дрейфу у Grafana: wakeups × номінал циклу.
// Точність ±20% (цикл 26-32 с) — для алерту «не чув Королеву Y годин» досить.
static uint32_t Soldier_Seconds_Since_Last_Sync(void)
{
    if (soldier_unix_ts == 0) return 0;
    return (uint32_t)wakeups_since_sync * SOLDIER_NOMINAL_CYCLE_S;
}

// Збираємо 16-байтний uplink-плейн «панічний sync-запит» / cold-boot hello
// (ARCH.41-C — той самий wire, hello шле secs_since_sync=0). Wire-формат:
//
//   Byte 0     : SYNC_REQ_MARKER (0x56)
//   Byte 1..4  : DID big-endian
//   Byte 5..8  : secs_since_sync big-endian (uint32; 0 = ніколи не чули)
//   Byte 9     : TTL (PANIC_TTL=5 — пакет повинен пробитися через mesh)
//   Byte 10    : SYNC_REQ_MAGIC_BYTE ('S' = 0x53) — миттєва дезамбігвація
//                від 0x55 OTA_REQ (де байт 10 не визначений)
//   Byte 11..12: vcap_mv big-endian [ARCH.41-C] — здоров'я EDLC у hello
//                (бекенд бачить заряд навіть коли телеметрія відкладена)
//   Byte 13..15: PAD = 0 (резерв під майбутні поля: pkt_seq, last_known_ts, ...)
//
// Перед TX обгортаємо в AES-128-ECB як звичайний LoRa-пакет (post-ARCH.42).
static void Build_Time_Sync_Request_Payload(uint8_t* out, uint32_t did,
                                              uint32_t secs_since_sync,
                                              uint16_t vcap_mv)
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
    out[11] = (uint8_t)(vcap_mv >> 8);
    out[12] = (uint8_t)(vcap_mv & 0xFFu);
    for (uint8_t i = 13; i < SYNC_REQ_PACKET_SIZE; i++) out[i] = 0;
}

// =========================================================================
// [ARCH.41-B] Sentinel «час невідомий» в acoustic-байті
// =========================================================================
// Поки Солдат не чув жодного beacon'а (soldier_unix_ts == 0), його epoch_day
// після VBAT-loss застарілий (RTC default 2000-01-01) — сервер ловив би DCI
// false-positive. Повний пакет тоді несе 0xFE замість лічильника, а Лоренц
// на ОБОХ сторонах рахується з acoustic=0 (дзеркало: TelemetryUnpackerService
// нейтралізує 0xFE→0 ДО DCI). 0xFF лишається легальною FW.22-сатурацією;
// реальні 0xFE притискаються до 0xFD, щоб лічильник ніколи не імітував
// sentinel. Канон: 03_04 §2.1.
#define ACOUSTIC_TIME_UNCERTAIN_SENTINEL  0xFEu

static uint8_t Soldier_Acoustic_Wire_Value(uint8_t snapshot, uint8_t time_uncertain)
{
    if (time_uncertain) return ACOUSTIC_TIME_UNCERTAIN_SENTINEL;
    if (snapshot == ACOUSTIC_TIME_UNCERTAIN_SENTINEL) return 0xFDu;
    return snapshot;
}

// =========================================================================
// [FW.20-S2] Mesh-Relay: голос Королеви через Провідника (per-hop drift)
// =========================================================================
// Кенозис маяка: Солдати поза прямою радіозоною Королеви ніколи не чують
// її голосу. Провідник (ARCH.27, роль PROV у Protected Flash) — еліта рою
// з надлишком vcap — приймає маяк, додає до `unix_ts` секунди, що минули
// від RX до власного TX (per-hop drift compensation), декрементує TTL,
// гасить authoritativeness-біт і ретранслює.
//
// Два режими anti-storm (вибирає аргумент `dedup`):
//   • dedup == NULL (KV не змонтовано / гейт off): ретранслюємо лише прямі
//     маяки Королеви (auth=1) — 2-hop стеля, шторм-безпечно конструкцією.
//   • dedup != NULL: повний mesh — auth=0 теж relay-able, а обсяг шторму
//     гасить журнал поколінь (Flash-KV 0x20, beacon_dedup.h): ≤1
//     ретрансляція на покоління на Провідника. TTL обмежує лише глибину.
//     Це глушить і подвійний маяк Королеви (15-хв такт + reflex-перемотка
//     на зойк 0x56), і луну Провідник↔Провідник при TTL≥3.
//
// Вшито у RX-гілку Сценарію 0 за гейтом FW20_MESH_RELAY_ENABLED (фліп =
// bench-верифікація Flash-KV HAL). Сторожовий пес часу (drift-monitor)
// закриває розрив для не-PROV Солдатів через панічний sync request.
//
// Wire-формат relayed beacon (16 байт ECB plaintext, дзеркало Queen):
//   Byte 0     : BEACON_MARKER (0x9C)
//   Byte 1..4  : unix_ts_be — original_ts + (now_tick - rx_tick)/1000 (sec)
//   Byte 5..8  : TDMA слот-розкладка (ARCH.26 L2, wire-дім 03_02 §5а.2а) —
//                копіюємо as-is: Провідник ретранслює розклад, не переписує
//   Byte 9     : [auth=0 | TTL_decremented:7] — auth-біт ОБОВ'ЯЗКОВО гасимо
//   Byte 10    : BEACON_MAGIC_BYTE ('B' = 0x42)
//   Byte 11..15: padding — копіюємо as-is (зараз 0; майбутні поля переживуть
//                hop без втрати, якщо Королева почне їх писати)
//
// SSOT для опкодів: 03_01 §4.5а; для wire-формату маяка/байту 9: 03_02 §5а.

// Sanity cap: hold-час від RX до relay-TX не повинен перевищувати 1 годину.
// Більший — означає що Провідник був зайнятий OTA / IWDG-шторм / зависнув
// у RX-вікні; ретранслювати такий «застарілий час» = шкодити синхронізації
// рою. Дроп — безпечніший за обман.
#define BEACON_RELAY_MAX_HOP_DELAY_SEC   3600UL
#define BEACON_RELAY_MIN_TTL             2u   // TTL=1 не підлягає relay (decrement → 0)
#define BEACON_FRAME_SIZE                16u  // Розмір AES блоку (128-bit fixed; post-ARCH.42 AES-128 LoRa)

// Атомарне рішення «ретранслювати чи ні» з явною причиною дропу.
// Готові точки для майбутніх Prometheus counters (`silkennet_beacon_relay_*_total`)
// при інтеграції у hot path — поки що host-тести різнять reason'и.
typedef enum {
    BEACON_RELAY_OK = 0,                  // out_plain заповнено, шли його далі
    BEACON_RELAY_NOT_PROVISIONER,         // Звичайний Солдат — не наша справа
    BEACON_RELAY_BAD_FRAME,               // Wrong marker або magic — не beacon
    BEACON_RELAY_NULL_TS,                 // unix_ts == 0 — Королева ще не знала часу
    BEACON_RELAY_NOT_AUTHORITATIVE,       // relay-маяк без dedup-журналу — auth-гейт
    BEACON_RELAY_TTL_EXHAUSTED,           // TTL у нижніх 7 бітах < MIN_TTL (=2)
    BEACON_RELAY_HOP_TOO_LONG,            // Hold-delay > MAX_HOP_DELAY_SEC
    BEACON_RELAY_DUPLICATE                // Покоління вже несли — журнал 0x20
} BeaconRelayResult;

// Спроба зібрати ретрансльований маяк з drift-компенсацією.
//
// Параметри:
//   in_plain   — оригінальний 16-байтний beacon plaintext (після ECB decrypt)
//   role       — g_node_role (ROLE_SOLDIER або ROLE_PROVISIONER)
//   in_rx_tick — HAL_GetTick() у момент прийому маяка (мс)
//   now_tick   — HAL_GetTick() зараз, перед TX (мс)
//   dedup      — журнал поколінь (NULL → auth-гейт, 2-hop режим).
//                ЧИТАЄТЬСЯ тут; Mark — справа викликача ПІСЛЯ Radio.Send
//                (невідправлене покоління не випалюється з журналу).
//   out_plain  — буфер ≥16 байт під вихідний beacon plaintext.
//                Модифікується ВИКЛЮЧНО при поверненні BEACON_RELAY_OK.
//
// Drift-формула: relayed_ts = original_ts + (now_tick - in_rx_tick)/1000.
// 32-бітне віднімання тіків wrap-safe для unsigned (раз у 49.7 днів) —
// стандартна C modular arithmetic.
//
// Викликач:
//     BeaconRelayResult r = Soldier_Try_Relay_Time_Beacon(...);
//     if (r == BEACON_RELAY_OK) { AES-ECB encrypt + Radio.Send(16 bytes);
//                                 Beacon_Dedup_Mark(...); }
//     else                       { reason'ом логується для діагностики; }
static BeaconRelayResult Soldier_Try_Relay_Time_Beacon(
    const uint8_t*     in_plain,
    uint8_t            role,
    uint32_t           in_rx_tick,
    uint32_t           now_tick,
    const BeaconDedup* dedup,
    uint8_t*           out_plain)
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

    // Guard 4: Anti-storm без журналу — лише прямі маяки Королеви (auth=1).
    // З журналом auth=0 relay-able (повний mesh) — шторм гасить Guard 7.
    uint8_t in_byte9 = in_plain[9];
    if (dedup == NULL && !(in_byte9 & BEACON_AUTH_FLAG))
        return BEACON_RELAY_NOT_AUTHORITATIVE;

    // Guard 5: TTL у нижніх 7 бітах має бути ≥ 2 (decrement не дасть 0).
    uint8_t in_ttl = in_byte9 & BEACON_TTL_MASK;
    if (in_ttl < BEACON_RELAY_MIN_TTL)          return BEACON_RELAY_TTL_EXHAUSTED;

    // Guard 6: Sanity cap — hold-delay не перевищує 1 год.
    uint32_t hold_sec = (now_tick - in_rx_tick) / 1000u;
    if (hold_sec > BEACON_RELAY_MAX_HOP_DELAY_SEC) return BEACON_RELAY_HOP_TOO_LONG;

    // Guard 7: Покоління вже несли (подвійний маяк Королеви у межах такту,
    // луна іншого Провідника) — мовчимо. Останнім: DUPLICATE означає
    // «поніс би, якби не журнал» — чесна метрика придушеного шторму.
    if (dedup != NULL && Beacon_Dedup_Seen(dedup, Beacon_Dedup_Gen(orig_ts)))
        return BEACON_RELAY_DUPLICATE;

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

// =====================================================================
// === 1.10г. FW.20-S2 — Gossip-Piggyback (5 з 5) ======================
// =====================================================================
// Найдешевший канал часо-синхронізації: «голос Королеви через сусіда».
// Доповнення до beacon-relay (він — окремий TX Провідника; тут нуль
// airtime): ми вшиваємо 1 байт `unix_ts & 0xFFu` у звичайний
// telemetry-uplink — байт PAD позиції 14 normal-плейту (НЕ панічного, де
// байт 14..15 уже зайнятий лічильником SEC.10). FW.29 PANIC_FLAG_BIT у
// StatusByte (байт 10 біт 7) — однозначний дезамбігватор: бекенд читає
// gossip-байт лише коли panic_flag == 0.
//
// Кенозис байта: один октет несе «ц.с.» — церковнослов'янське «нинішня
// година» — що дозволяє сусіднім Солдатам, які чують uplink одне одного
// (1-hop без mesh-relay), уточнити свій soldier_unix_ts на ±128 секунд
// без участі Королеви. Гібрид з beacon-relay (FW.20-S2 #3) дає 3-хоповий
// reach без нового RTC регістра.
//
// Trade-off freeze-контракту:
//   + 1 байт payload — нульова вартість airtime (вже передавали 0 у PAD)
//   + 1-hop gossip сягає сусідів, до яких не доходить Queen beacon
//   + Не потребує дозволу TX (це side-effect telemetry, що і так буде)
//   - Точність ±128 сек — недостатньо для TDMA (ARCH.26 потребує ±10 мс),
//     достатньо для FW.30 cold-start `epoch_day = unix_ts / 86400` (24-год
//     гранулярність) і для freshness-перевірки (HMAC nonce window).
//   - Receiver має знати approx-таймштамп (свій soldier_unix_ts ± дрейф
//     <128 сек) щоб реконструювати full ts — тобто це **уточнення** local
//     drift'у, а не cold-start sync. Cold-start Soldier і досі чекає
//     beacon (FW.20 §1) або relay (FW.20-S2 #3).
//
// Wire-формат gossip-байта у normal-telemetry plaintext (ECB-блок 16 B):
//   Byte 0..3   DID
//   Byte 4..5   vcap_mv
//   Byte 6      temp
//   Byte 7      acoustic
//   Byte 8..9   delta_t
//   Byte 10     StatusByte (PANIC_FLAG_BIT==0 — це гарантія normal-frame'у)
//   Byte 11     TTL
//   Byte 12..13 firmware_version_id
//   Byte 14     [FW.20-S2#5] gossip_ts_lsb = (soldier_unix_ts & 0xFFu)  ← НОВЕ
//   Byte 15     PAD (резерв)
//
// Активація потребує: (а) hot-path виклик `Soldier_Pack_Gossip_Ts_Byte` у
// Phase 2 для normal-plaintext'у (1 рядок), (b) RX-гілка для застосування
// gossip'у — тільки коли source-Soldier також має recent beacon (потребує
// додаткового біта в payload або довіри до сусіда у тому ж кластері), (c)
// бекенд `TelemetryUnpackerService` буде ігнорувати байт 14 — він вже
// інертний у production (PAD=0). НЕ ламає FW.22 (acoustic) і SEC.10 (panic
// counter живе у byte 14..15 ЛИШЕ для panic_payload, normal буде використано).
#define GOSSIP_TS_PAYLOAD_OFFSET   14u   // байт 14 у normal-telemetry plaintext
#define GOSSIP_TS_MAX_DRIFT_SEC    127u  // ±128 секунд window (bytewise unwrap)

// Витягує LSB з unix_ts для embed'у у telemetry. Якщо Солдат ще не чув
// beacon (`unix_ts == 0`) — повертаємо 0 (бекенд інтерпретує як «no fresh
// gossip»). Чисто арифметична функція без побічних ефектів.
static inline uint8_t Soldier_Pack_Gossip_Ts_Byte(uint32_t unix_ts)
{
    return (uint8_t)(unix_ts & 0xFFu);
}

// Уточнюємо local_ts на основі gossip'у від сусіда. Інваріант: ми ВЖЕ маємо
// approximate ts (last beacon або попередній gossip), і drift від тоді не
// перевищує GOSSIP_TS_MAX_DRIFT_SEC. Якщо local_ts == 0 — Солдат у cold-boot
// і не довіряє байту gossip (треба beacon). Повертаємо refined_ts:
//
//   candidate_low = (local_ts & ~0xFFu) | gossip_lsb
//   if candidate_low > local_ts + 127u  → відкот на 256 (gossip був раніше
//                                          у попередньому 256-сек вікні)
//   if candidate_low + 127u < local_ts  → стрибок на 256 (gossip — у наступному)
//   else                                → candidate_low = refined
//
// Wrap-safe для unsigned modular arithmetic. Якщо різниця >127 в обидві
// сторони після вибору вікна — gossip недостовірний (стрибок >128 сек =
// сусід має ще старіший дрейф), повертаємо local_ts без змін.
static uint32_t Soldier_Try_Apply_Gossip_Ts(uint32_t local_ts, uint8_t gossip_lsb)
{
    if (local_ts == 0) return 0;  // cold-boot: gossip недостатньо

    uint32_t base       = local_ts & ~((uint32_t)0xFFu);
    uint32_t candidate  = base | (uint32_t)gossip_lsb;

    // Вибираємо найближчу кандидатку у 3 сусідніх 256-сек вікнах:
    // [base-256], [base], [base+256]. Беремо ту, що ближче до local_ts.
    uint32_t cand_prev  = candidate - 256u;
    uint32_t cand_next  = candidate + 256u;

    int32_t  diff_curr  = (int32_t)(candidate - local_ts);
    int32_t  diff_prev  = (int32_t)(cand_prev - local_ts);
    int32_t  diff_next  = (int32_t)(cand_next - local_ts);

    int32_t  abs_curr   = (diff_curr < 0) ? -diff_curr : diff_curr;
    int32_t  abs_prev   = (diff_prev < 0) ? -diff_prev : diff_prev;
    int32_t  abs_next   = (diff_next < 0) ? -diff_next : diff_next;

    uint32_t refined    = candidate;
    int32_t  best_abs   = abs_curr;
    if (abs_prev < best_abs) { refined = cand_prev; best_abs = abs_prev; }
    if (abs_next < best_abs) { refined = cand_next; best_abs = abs_next; }

    // Якщо навіть найближча кандидатка >127 сек від local — gossip undefined.
    if ((uint32_t)best_abs > GOSSIP_TS_MAX_DRIFT_SEC) return local_ts;
    return refined;
}

// Експоненціальне ковзне середнє для delta_t (швидкість метаболізму EBFC)
// та vcap (заряд іоністора). Зменшує ADC-/RTC-шум приблизно в 3× перед
// тим, як ці сигнали потраплять до mruby-контракту ([E.63] метаболізм).
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
// [E.63] delta_t → growth_points напряму у mruby (метаболічна m(delta_t),
// 03_04 §4.3); β більше не збурюється. vcap reserved (FW.50 raw-ADC).
static inline uint32_t EMA_Get_DeltaT_Sec(void) { return ema_delta_t_x100 / 100u; }
static inline uint16_t EMA_Get_Vcap_Mv  (void) { return (uint16_t)(ema_vcap_x10 / 10u); }

// Прапорець "фільтр прогрівся" — true після ≥ EMA_WARMUP_CYCLES зразків.
// До того споживач (mruby calculate_state) має використовувати raw-значення.
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

// Production-visibility counter (saturating uint8) для випадків, коли
// TinyML_Apply_Thresholds() відкинув OTA payload — або через NaN/out-of-range
// окремого порогу, або через інверсію warn ≥ crit. Embedded LOG_ERR на
// headless STM32 марний, тому замість printf — лічильник, який backend може
// piggybacked'ити на телеметрію і будувати Grafana panel
// "OTA threshold inversion rate per Soldier". Скидається на 0 тільки при
// VBAT loss / cold-boot (SRAM ініціалізується нулями).
//
// Wiring до телеметрії ✅ [FW.18b]: верхні 5 біт байта 11 (TTL-байт) —
// бітфілд [thr_invalid:5 | TTL:3], One-Home ../common/ttl_byte.h; wire-кап
// 31 (RAM-сатурація лишається @255 для GDB/SEGGER-діагностики).
uint8_t tinyml_threshold_invalid_count = 0;

// Перевірка пари: гарантує warning < critical, інакше дефолти на обидва.
// Зберігає інваріант зон (SILENCE < WARNING < CRITICAL) навіть при частково
// корумпованому RTC або злочинно сформованому OTA payload.
//
// Side-effect: інкрементує tinyml_threshold_invalid_count, якщо raw input
// не пройшов валідацію (NaN/out-of-range) АБО пара інвертована.
static inline void TinyML_Apply_Thresholds(float warn_raw, float crit_raw,
                                            float* warn_out, float* crit_out) {
    float w = TinyML_Validate_Threshold(warn_raw, TINYML_DEFAULT_WARNING);
    float c = TinyML_Validate_Threshold(crit_raw, TINYML_DEFAULT_CRITICAL);

    // Детектуємо fallback: NaN != NaN (true), out-of-range raw → w != warn_raw.
    // Інверсія детектується окремо через !(w < c).
    uint8_t warn_rejected = (w != warn_raw);
    uint8_t crit_rejected = (c != crit_raw);
    uint8_t inverted      = !(w < c);

    if (warn_rejected || crit_rejected || inverted) {
        if (tinyml_threshold_invalid_count < 255) {
            tinyml_threshold_invalid_count++;
        }
    }

    if (inverted) {
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
// Wire-формат (16 байт plaintext, 1× AES-128-ECB блок, post-ARCH.42):
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
//   [1..2] seg_idx (big-endian, 1..4)
//   [3..4] total_chunks тіла прошивки (big-endian, для перехресної перевірки)
//   seg 1..3: [5..15] hmac_segment[11 байт] (3×11 = 33; 11-й байт seg=3 = PAD)
//   seg 4:    [5..8] version_id (big-endian) + [9..15] PAD
//
// Прийняті 4 чанки ⇒ ota_hmac_segments_received == OTA_TRAILER_ALL_RECEIVED
// (0b1111 = 0x0F): received_hmac_tag[0..31] повний + *version_out заповнено.
// Викликаючий код приходить до двох брам перед впуском прошивки у Flash:
//   Брама 1: magic у RAM-bytecode = 0x45544952 ("RITE") — швидкий привратник
//   Брама 2: HMAC-SHA256(K_ota, bytecode || version_id_be || total_chunks_be)
//            == received_hmac_tag (constant-time, без шепоту таймінгу)
//
// Version_id їде окремим чанком (seg 4), бо у 16-байтну печатку-сегмент він не
// влазить, а без нього Солдат не може перерахувати HMAC (3.4б). Чиста pure-
// функція для host-тестів.
// Повертає:
//   1 = чанк з валідним marker та seg_idx у [1..4], печатка/версія лягли на місце
//   0 = чанк не є печаткою (caller може спробувати інший marker)
//   -1 = чанк має marker 0x9B, але невалідний (seg_idx поза [1..4] / size < 16)
static int Parse_HMAC_Trailer_Chunk(const uint8_t* chunk,
                                     uint16_t       chunk_size,
                                     uint8_t        tag_out[HMAC_TAG_BYTES],
                                     uint32_t*      version_out,
                                     uint8_t*       segments_received_inout) {
    if (chunk == NULL || tag_out == NULL || version_out == NULL ||
        segments_received_inout == NULL)                                    return -1;
    if (chunk_size < HMAC_TRAILER_HEADER_SIZE + HMAC_TRAILER_SEG_BYTES)      return -1;
    if (chunk[0] != HMAC_TRAILER_MARKER)                                     return 0;

    uint16_t seg_idx = ((uint16_t)chunk[1] << 8) | chunk[2];
    if (seg_idx < 1 || seg_idx > OTA_TRAILER_TOTAL_CHUNKS)                   return -1;

    if (seg_idx == HMAC_VERSION_SEG_IDX) {
        // seg 4: version_id (big-endian) у байтах [5..8].
        *version_out = ((uint32_t)chunk[HMAC_TRAILER_HEADER_SIZE]     << 24) |
                       ((uint32_t)chunk[HMAC_TRAILER_HEADER_SIZE + 1] << 16) |
                       ((uint32_t)chunk[HMAC_TRAILER_HEADER_SIZE + 2] <<  8) |
                       ((uint32_t)chunk[HMAC_TRAILER_HEADER_SIZE + 3]);
        *segments_received_inout |= (uint8_t)(1u << (HMAC_VERSION_SEG_IDX - 1));
        return 1;
    }

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
// Caller обчислює expected_hmac через pure-C silken_sha256.h (FW.30 — mbedTLS
// не потрібен). Тут тестуємо саме гейт-логіку.
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

// [FW.23] Вердикт фіналізації OTA — серце дуал-гейту, чиста pure-функція для
// host-тестів (жодного звернення до глобалок чи HAL: усе через параметри).
//
// Чому окремий вердикт, а не запис прямо: тіло (0x99) і печатка (0x9B) приходять
// РІЗНИМИ кадрами й у будь-якому порядку — Королева шле тіло, ПОТІМ печатку, але
// Солдат спить між пробудженнями, тож останнім може завершитись будь-що. Раніше
// перевірка стріляла по завершенню ТІЛА і скидала збірку — печатка, що приходила
// пізніше, гинула, і OTA ніколи не застосовувався. Тепер обидві гілки кличуть цей
// вердикт; APPLY настає лише коли зібрано і тіло, і всі 4 трейлер-чанки.
//
//   WAIT   — ще не все (тіло АБО печатка/версія) → викликач НІЧОГО не чіпає
//   APPLY  — обидві брами + CRC + K_ota → викликач пише у Flash і ребутає
//   REJECT — зібрано повністю, але CRC/брама/ключ впали → жертовний wipe + reset
//
// HMAC-вхід дзеркалить backend OtaPackagerService: тіло (без 4-байтного CRC-
// хвоста) ‖ version_id_be(4) ‖ total_chunks_be(2). *data_len_out — довжина тіла.
typedef enum {
    OTA_FINALIZE_WAIT = 0,
    OTA_FINALIZE_APPLY,
    OTA_FINALIZE_REJECT
} OtaFinalizeVerdict;

static OtaFinalizeVerdict OTA_Try_Finalize(const uint8_t* buf,
                                           uint16_t       bytes_received,
                                           uint16_t       chunks_received,
                                           uint16_t       total_chunks,
                                           uint8_t        segments_received,
                                           const uint8_t* k_ota,
                                           uint8_t        k_ota_valid,
                                           uint32_t       version_id,
                                           const uint8_t  received_tag[HMAC_TAG_BYTES],
                                           uint16_t*      data_len_out) {
    if (buf == NULL || received_tag == NULL || data_len_out == NULL) return OTA_FINALIZE_REJECT;

    // Ще не зібрано тіло або не прийшли всі 4 трейлер-чанки — чекаємо мовчки.
    if (total_chunks == 0 || chunks_received < total_chunks)         return OTA_FINALIZE_WAIT;
    if (segments_received != OTA_TRAILER_ALL_RECEIVED)               return OTA_FINALIZE_WAIT;

    // Зібрано все, але тіло коротше за CRC-хвіст — це не прошивка.
    if (bytes_received <= 4)                                         return OTA_FINALIZE_REJECT;

    uint16_t data_len = (uint16_t)(bytes_received - 4u);
    *data_len_out = data_len;

    // CRC32 (ISO 3309) над тілом; останні 4 байти потоку — очікувана сума (BE).
    uint32_t expected_crc = ((uint32_t)buf[data_len] << 24) |
                            ((uint32_t)buf[data_len + 1] << 16) |
                            ((uint32_t)buf[data_len + 2] << 8)  |
                            (uint32_t)buf[data_len + 3];
    uint32_t crc = 0xFFFFFFFFu;
    for (uint16_t ci = 0; ci < data_len; ci++) {
        crc ^= buf[ci];
        for (uint8_t bit = 0; bit < 8; bit++) {
            crc = (crc & 1u) ? ((crc >> 1) ^ 0xEDB88320u) : (crc >> 1);
        }
    }
    crc = ~crc;
    if (crc != expected_crc)                                        return OTA_FINALIZE_REJECT;

    // Без K_ota походження не довести — fail-safe (краще не оновитись, ніж лжеслово).
    if (!k_ota_valid)                                               return OTA_FINALIZE_REJECT;

    // Брама 2: HMAC-SHA256(K_ota, тіло ‖ version_be ‖ total_be) проти received_tag.
    // Тіло (~1 КБ) живе у buf; 6-байтний хвіст стрімимо окремо (Concat) — без +1 КБ стека.
    uint8_t suffix[6];
    suffix[0] = (uint8_t)(version_id >> 24);
    suffix[1] = (uint8_t)(version_id >> 16);
    suffix[2] = (uint8_t)(version_id >> 8);
    suffix[3] = (uint8_t)(version_id & 0xFFu);
    suffix[4] = (uint8_t)(total_chunks >> 8);
    suffix[5] = (uint8_t)(total_chunks & 0xFFu);

    uint8_t expected_hmac[HMAC_TAG_BYTES];
    Silken_Hmac_Sha256_Concat(k_ota, 32u, buf, data_len, suffix, sizeof(suffix), expected_hmac);

    if (OTA_Verify_Dual_Gate(buf, data_len, expected_hmac, received_tag) != 1) {
        return OTA_FINALIZE_REJECT;
    }
    return OTA_FINALIZE_APPLY;
}

// [FW.23] Повне скидання збірки OTA — тіло, печатка, версія, лічильники.
// Єдине джерело: і deadlock-guard (чужий total), і успіх/відмова фіналізації
// кличуть його, щоб жодне поле (зокрема received_ota_version) не лишилось
// «брудним» між кампаніями.
static void Reset_Ota_Assembly(void) {
    memset(ota_chunk_received, 0, sizeof(ota_chunk_received));
    memset(received_hmac_tag, 0, sizeof(received_hmac_tag));
    received_ota_version       = 0;
    ota_chunks_received        = 0;
    ota_bytes_received         = 0;
    ota_total_chunks           = 0;
    ota_hmac_segments_received = 0;
    ota_last_chunk_rx_tick     = 0;
    ota_total_mismatch_streak  = 0;
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
    uint16_t expected_crc = Silken_Crc16_Ccitt(body, CMD_AUDIO_THRESHOLDS_BODY_SIZE);
    uint16_t received_crc = (uint16_t)body[CMD_AUDIO_THRESHOLDS_BODY_SIZE]
                          | ((uint16_t)body[CMD_AUDIO_THRESHOLDS_BODY_SIZE + 1] << 8);
    if (expected_crc != received_crc)                                      return 0;

    int16_t warn_x100    = (int16_t)((uint16_t)body[0] | ((uint16_t)body[1] << 8));
    int16_t crit_x100    = (int16_t)((uint16_t)body[2] | ((uint16_t)body[3] << 8));
    // Range invariants (decoded values × 100, тож range [1..99] = [0.01..0.99])
    if (warn_x100 < 1   || warn_x100 > 99)                                 return 0;
    if (crit_x100 < 1   || crit_x100 > 99)                                 return 0;

    float warn_raw = (float)warn_x100 / 100.0f;
    float crit_raw = (float)crit_x100 / 100.0f;

    // TinyML_Apply_Thresholds робить додатковий sanitize (NaN/inversion → defaults)
    TinyML_Apply_Thresholds(warn_raw, crit_raw, warn_out, crit_out);

    if (version_out) *version_out = body[4];  // config_version (байт 4 body)
    return 1;
}

// === 2. РУДА СВІДОМОСТІ (Байт-код mruby) ===
// Скомпільований скрипт Атрактора Лоренца (`bio_contracts/bio_contract.rb`).
// [FW.46] Викарбуваний mrbc у build-час → committed-дзеркало `lorenz_bytecode[]`,
// drift-gated. Регенерація: tools/firmware/gen_bytecode.sh · гейт: check_bytecode.py
#include "../common/lorenz_bytecode.h"
#include "../common/flash_ota.h"  // [FW.52-г] OTA contract blob writer (host-tested logic)
#include "../common/ota_antirollback.h"  // [SEC.20] версійний anti-rollback приплив (Flash-KV 0x15)

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
void Write_OTA_Contract_To_Flash(const uint8_t* data, uint16_t size);

// [FW.1 + ARCH.42] Завантаження LoRa AES-128 ключа з Protected Flash Sector.
// Викликається в main() ПЕРЕД MX_CRYP_Init().
static void Load_AES_Key(void);

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
// [FW.2 (в)] Cluster control-plane KEYB — викликається в main() ПІСЛЯ
// Load_AES_Key (fallback читає K0) і ПЕРЕД MX_CRYP_Init (амбієнт = bcast).
static void Load_Broadcast_Key(void);
#endif

// [SEC.11 / FW.30] Завантаження Lorenz K_seed з Protected Flash Sector.
// Викликається в main() при ініціалізації. K_seed використовується для
// cold-start деривації (x₀,y₀,z₀) через HMAC-SHA256.
static void Load_Lorenz_Seed(void);
static void Load_Ota_Hmac_Key(void);  // [FW.23] Прочитати K_ota з Flash
static void Load_Node_Role(void);  // [ARCH.27] Прочитати роль вузла з Flash

// [SEC.11 / FW.30] Деривація початкового стану Лоренца при cold-start
// (VBAT loss → DR19 != LORENZ_STATE_MAGIC). Використовує K_seed з Flash
// + epoch_day (UTC unix_time / 86400). Дзеркало firmware/test/test_seed_derivation.c.
static void Derive_Cold_Start_State(float *x0, float *y0, float *z0);
static uint32_t Wall_Seconds_Now(void);          // [FW.49 S1] RTC-календар → unix-секунди
static void Wall_Calendar_Set(uint32_t unix_ts); // [FW.49 S1] beacon-UTC → RTC-календар
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

// [FW.52-г] Запис зібраного OTA-байткоду у contract-сторінку Flash, щоб boot
// magic-check (RITE @ MRUBY_CONTRACT_FLASH_ADDR) завантажив його наступним reset'ом.
// Чиста логіка (erase + dw-program + power-cut-safety: magic-dw ОСТАННІМ) живе у
// flash_ota.c (host-тести test_flash_ota.c, 8/8). Тут — лише HAL-фаза (HAL_FLASH),
// що компілюється/виконується на STM32 bench. MRUBY_CONTRACT_FLASH_ADDR=0x0803F000
// = сторінка OTA_CONTRACT_PAGE (126).
static int Ota_Hal_Erase(void *io, uint8_t page)
{
    (void)io;
    FLASH_EraseInitTypeDef ei = { .TypeErase = FLASH_TYPEERASE_PAGES, .Page = page, .NbPages = 1 };
    uint32_t page_err = 0;
    HAL_FLASH_Unlock();
    HAL_StatusTypeDef st = HAL_FLASHEx_Erase(&ei, &page_err);
    HAL_FLASH_Lock();
    return (st == HAL_OK && page_err == 0xFFFFFFFFu) ? 1 : 0;
}

static int Ota_Hal_Program(void *io, uint32_t byte_off, uint64_t v)
{
    (void)io;
    HAL_FLASH_Unlock();
    HAL_StatusTypeDef st = HAL_FLASH_Program(FLASH_TYPEPROGRAM_DOUBLEWORD,
                                             MRUBY_CONTRACT_FLASH_ADDR + byte_off, v);
    HAL_FLASH_Lock();
    return (st == HAL_OK) ? 1 : 0;
}

static uint64_t Ota_Hal_Read(void *io, uint32_t byte_off)
{
    (void)io;
    return *(const volatile uint64_t *)(MRUBY_CONTRACT_FLASH_ADDR + byte_off);
}

static const FlashKvOps g_ota_flash_ops = { Ota_Hal_Read, Ota_Hal_Program, Ota_Hal_Erase };

// Тіло forward-declared (вище) Write_OTA_Contract_To_Flash. На host-тестах
// soldier-логіки натомість лінкується порожній hal_mock-стаб (main.c не
// компілюється на хості) — реальний запис іде лише на MCU.
void Write_OTA_Contract_To_Flash(const uint8_t *data, uint16_t size)
{
    Flash_Write_Contract(&g_ota_flash_ops, (void *)0, data, size);
}

// [FW.46 Шлях A] Прототипи radio-колбеків для events-реєстрації в main():
// тіла живуть унизу файла (ISR-зона), Semtech-драйвер кличе їх через таблицю.
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr);
#if ARCH26_CAD_ENABLED
void OnCadDone(bool channelActivityDetected);  // ARCH.26 L3 — гейт дзеркалить дефініцію `OnCadDone` + реєстрацію
#endif

// [SEC.21] MPU: NX-stack + RO-code (розкладка/математика — mpu_regions.h).
// #ifndef — щоб hal_check_ccm міг зібрати гілку `-DSEC21_MPU_ENABLED=1`
// проти справжнього CMSIS, не чіпаючи бойового дефолту 0. АКТИВАЦІЯ (реальний
// MemManage-trap) bench-gated: QEMU mps2 MPU не моделює вірогідно.
#ifndef SEC21_MPU_ENABLED
#define SEC21_MPU_ENABLED 0
#endif
#if SEC21_MPU_ENABLED
static void Silken_Mpu_Apply(void)
{
    MpuRegionWord regions[3];
    Mpu_Build_Region_Table(regions);
    MPU->CTRL = 0u; // програмуємо з вимкненим MPU
    for (uint32_t i = 0; i < 3u; i++) {
        MPU->RBAR = regions[i].rbar; // VALID-біт несе номер регіону
        MPU->RASR = regions[i].rasr;
    }
    // PRIVDEFENA — фонова мапа периферії/System (код повністю privileged);
    // HFNMIENA=0 — у HardFault/NMI MPU спить: canary-варта пише TAMP без trap'а.
    MPU->CTRL = MPU_CTRL_PRIVDEFENA_Msk | MPU_CTRL_ENABLE_Msk;
    SCB->SHCSR |= SCB_SHCSR_MEMFAULTENA_Msk; // окремий вектор (тіло — board-freeze .ioc)
    __DSB();
    __ISB();
}
#endif

// [SEC.21] Власна варта канарки замість newlib'ової. Strong-символи цього TU
// перекривають libc_a-stack_protector.o (архів лінкується ліниво — member не
// витягується, конфлікту немає). Дефолт newlib: guard = 0x00000000 (.bss,
// __stack_chk_init ніхто не кличе) і fail → abort → вічний wfi-hang без сліду.
// Компайл-тайм значення guard'а живе лише до HRNG-сіву в main().
uintptr_t __stack_chk_guard = CANARY_GUARD_LAST_RESORT;

__attribute__((noreturn)) void __stack_chk_fail(void)
{
    // Канарка мертва — кадр стека переписано (LoRa-RX/AT-парсери жують
    // untrusted байти ДО MIC-чеку; це потенційний слід атаки). Стеку більше
    // не віримо: мінімум рухів, прямі регістри без HAL-хендлів.
    // DBP ідемпотентно (fail міг статись до main-init), слід у DR0[10],
    // негайне перевтілення — замість hang'у чекати ласки Сторожового Пса.
    SET_BIT(PWR->CR1, PWR_CR1_DBP);
    TAMP->BKP0R |= ((uint32_t)CANARY_TRIP_MASK << CANARY_TRIP_DR0_SHIFT);
    NVIC_SystemReset();
    for (;;) { } // недосяжно: заспокоює noreturn-аналіз
}

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

  // [SEC.21] Сіємо вартову канарку з теплового шуму — якнайраніше, ДО того
  // як парсери торкнуться першого untrusted-байта. main() не повертається
  // (вічний цикл Фаз), тож зміна guard'а посеред власного кадру безпечна —
  // epilogue-звірка main'а не настане ніколи.
  {
      uint32_t canary_r = 0;
      if (HAL_RNG_GenerateRandomNumber(&hrng, &canary_r) != HAL_OK) canary_r = 0;
      __stack_chk_guard = Canary_Guard_Derive(
          canary_r, HAL_GetTick() ^ (uint32_t)(uintptr_t)&canary_r);
  }

#if SEC21_MPU_ENABLED
  Silken_Mpu_Apply(); // [SEC.21] NX-stack + RO-code (draft; активація bench)
#endif

  Load_AES_Key();  // [FW.1] Завантажити per-device ключ з Flash ПЕРЕД ініціалізацією CRYP
#if FW2_CCM_ENABLED
  Load_Broadcast_Key(); // [FW.2 (в)] Cluster-plane KEYB (після KEYL — fallback читає aes_key)
#endif
  Load_Lorenz_Seed();  // [SEC.11 / FW.30] Завантажити K_seed для cold-start Lorenz derivation
  Load_Ota_Hmac_Key(); // [FW.23] Завантажити K_ota для OTA dual-gate (per-cluster HMAC)
  Load_Node_Role();    // [ARCH.27] Завантажити роль вузла (Soldier/Provisioner) з Flash
  MX_CRYP_Init(); // Вмикаємо апаратний AES (CCM-ера: амбієнт = bcast_key; ECB-ера: aes_key)

#if defined(CCM_SELFTEST)
  // [FW.2] POST: бенч-атестація CCM-двигуна на реальному кремнії. Результат у
  // g_ccm_selftest_failed (читати через SWD): 0 → кремній == OpenSSL == backend
  // → дозволено flip FW2_CCM_ENABLED; >0 → HAL/endianness/errata → CCM не вмикати.
  // KAT-вектори: firmware/common/ccm_kat_vectors.h (єдине джерело, спільне з host).
  g_ccm_selftest_failed = Ccm_Run_Self_Test(&hcryp, NULL);
  // [ARCH.42] POST транзитних шляхів: ECB-128 (LoRa) + CBC-256 (CoAP)
  // проти NIST SP 800-38A. FAIL тут = DataType/endianness-конфіг CRYP видає
  // НЕ-OpenSSL байти (DATATYPE_32B word-swap) → бекенд бачив би сміття;
  // лік — CRYP_DATATYPE_8B. Після POST відновлюємо бойовий ECB-контекст.
  g_sym_selftest_failed = Sym_Run_Self_Test(&hcryp, NULL);
  MX_CRYP_Init();
#endif

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
  // [SEC.10/SEC.20] DR0: [panic:16 | rsv:6 | vm_err_streak:2 | acoustic:8].
  // При cold-boot DR0 == 0 → лічильник пересіємо з HRNG нижче, щоб уникнути
  // колізії з nonce'ами Redis від попереднього втілення вузла.
  {
      uint32_t dr0_raw = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR0);
      acoustic_events     = (uint8_t)(dr0_raw & 0xFFu);
      panic_frame_counter = (uint16_t)((dr0_raw >> PANIC_COUNTER_DR0_SHIFT) & PANIC_COUNTER_MASK);
      // [SEC.20] Streak bytecode-збоїв переживає STOP2 у DR0[9:8] (RAM-only
      // згорів би щоцикл у RTC-only сні). Cold-boot DR0=0 → streak=0 природно.
      ota_vm_error_streak = (uint8_t)((dr0_raw >> OTA_VM_ERR_STREAK_DR0_SHIFT) & OTA_VM_ERR_STREAK_MASK);
      // [SEC.21] Слід канарки з минулого втілення: sticky до wire-виносу.
      // Cold-boot DR0=0 → чисто природно. Слід є → заряджаємо 3 постріли
      // 0x57 (LoRa губить кадри; повтори в наступних циклах best-effort).
      canary_tripped = (uint8_t)((dr0_raw >> CANARY_TRIP_DR0_SHIFT) & CANARY_TRIP_MASK);
      if (canary_tripped) canary_evt_shots = 3u;
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
  // [FW.21] 3 слоти: DR8, DR9, DR11 (DR10/DR12 — EMA). Повна розкладка — 03_01 §2.
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
  // обидва на дефолти, гарантуючи інваріант зон. SSOT: 03_03 §5 (CRITICAL зони).
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
  // ДЕРИВАЦІЯ DECENTRALIZED IDENTITY (DID)
  // =========================================================================
  // [FW.54 Вісь 2] Ім'я дерева детерміноване: f(96-біт кремнієвого паспорта),
  // recompute на кожному boot — зберігати нічого (DR7 звільнено, 03_01 §2).
  // VBAT-loss більше не сиротить identity/гаманець; фабрика (SEC.3) деривує
  // той самий DID з UID по SWD ще до прошивки — однопрохідний провіженінг.
  // Стара схема UID⊕random (з FW.24-fallback'ом) жила в DR7 і гинула разом
  // з ним; колізії тепер ловить фабрика DB-unique-перевіркою, не HRNG.
  // DID==0 неможливий (did_derive.h) — нуль ефіру належить Королеві-Сентінель.
  tree_did = Did_Derive_From_Uid(*(uint32_t*)(0x1FFF7590),
                                 *(uint32_t*)(0x1FFF7594),
                                 *(uint32_t*)(0x1FFF7598));

#if FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED || FW2_CCM_ENABLED || FW20_MESH_RELAY_ENABLED || SEC20_OTA_ANTIROLLBACK_ENABLED
  // [ARCH.28] Mount Flash-KV (сторінки 122-123). Невдача (обидві сторінки
  // биті) → mounted=0: споживачі живуть на дефолтах/K0 — деградація, не смерть.
  soldier_kv_mounted = FlashKv_Mount(&soldier_kv, &soldier_kv_ops, NULL,
                                     FLASH_KV_PAGE_DWS);
#endif
#if FW20_MESH_RELAY_ENABLED
  // [FW.20-S2 4/5] Журнал поколінь маяка з Flash: без нього (mount-fail)
  // relay падає на NULL-гілку (auth-гейт, 2-hop) — шторм-безпечно завжди.
  if (soldier_kv_mounted) {
      Beacon_Dedup_Load(&soldier_kv, &beacon_dedup);
  }
#endif
#if FW2_CCM_ENABLED
  // [FW.2 TRL-7] Кеш межі FC: один Get32 на boot, далі Load_Frame_Counter
  // та КЕНОЗИС працюють з RAM-кешем (Flash читається лише тут).
  if (soldier_kv_mounted) {
      fc_hiwater_cache = Fc_Hiwater_Load(&soldier_kv);
  }
#endif
#if FW8_PARSER_ENABLED
  // [FW.8] Boot-restore Z-порогів: Load жене збережене через ті самі
  // інваріанти, що парсер 0x9A; нічого валідного → t = firmware-дефолти
  // (ідентичні поточним глобалкам, тож безумовне застосування безпечне).
  if (soldier_kv_mounted) {
      LorenzThresholds t;
      Lorenz_Thresholds_Load(&soldier_kv, &t);
      lorenz_z_min_x100     = t.z_min_x100;
      lorenz_z_max_x100     = t.z_max_x100;
      lorenz_z_opt_x100     = t.z_opt_x100;
      lorenz_species_id     = t.species_id;
      lorenz_config_version = t.config_version;
  }
#endif
#if FW17_RATCHET_ENABLED
  // [FW.17] ПІСЛЯ Load_AES_Key (K0) і DID-блоку (Context KDF): якщо KV має
  // версію — доганяємо K_current і ре-ініціалізуємо CRYP.
  FW17_Restore_Key_Version(tree_did);
#endif

  // [FW.49 S1] Найперший старт (DR1 == 0) НЕ засіюється тут: guard
  // Silken_Wall_Delta_Seconds трактує last==0 як cold-start → нейтральний
  // baseline для першого циклу (чесніше за майже-нульову tick-дельту),
  // а Phase 1 сама виставить wall-маркер.

  // 3. Калібрування АЦП (Встановлюємо абсолютний фізичний нуль)
  HAL_ADCEx_Calibration_Start(&hadc);

  // 4. Ініціалізація низькорівневого радіодрайвера.
  // [FW.46 Шлях A] Events-таблиця (static — Semtech-драйвер тримає вказівник
  // довше за цей скоуп): реальний драйвер кличе колбеки ЧЕРЕЗ неї — з NULL
  // вухо OnRxDone (беакон/OTA/downlink) і вердикт OnCadDone (ARCH.26 CAD-нюх)
  // не стрельнули б ніколи. Поля, яких Солдат не слухає, — NULL (драйвер
  // перевіряє перед викликом).
  static RadioEvents_t radio_events;
  radio_events.RxDone  = OnRxDone;
#if ARCH26_CAD_ENABLED
  // ARCH.26 L3: реєстрація йде ЛИШЕ з дефініцією `OnCadDone` — інакше ungated-референс
  // gated-функції зривав би лінк повного .elf на FW.46 board-freeze день (той самий,
  // що фліпає гейт). Gate off → CadDone лишається NULL (static zero-init), драйвер її не кличе.
  radio_events.CadDone = OnCadDone;
#endif
  Radio.Init(&radio_events);
  Radio.SetChannel(868000000); // Налаштовуємо на 868 МГц

  // 5. Вибір контракту: Перевіряємо, чи є в Flash-пам'яті оновлений код
  const uint32_t* flash_check = (const uint32_t*)MRUBY_CONTRACT_FLASH_ADDR;
  if (*flash_check == 0x45544952) { // "RITE" у little-endian (ознака mruby байткоду)
      current_lorenz_bytecode = (uint8_t*)MRUBY_CONTRACT_FLASH_ADDR;
  } else {
      current_lorenz_bytecode = (uint8_t*)lorenz_bytecode;
  }

  // [SEC.20] Wire-звіт contract-стану: спалений приплив (0x15) при зниклому
  // "RITE" = сигнатура auto-fallback — саме той факт, що інакше розчинявся б
  // у здоровій baseline-телеметрії. Rails бачить його з кожного кадру.
  fw_contract_report = Fw_Report_Compose(
      soldier_kv_mounted,
      soldier_kv_mounted ? Ota_Version_Load(&soldier_kv) : 0u,
      *flash_check == 0x45544952u,
      FIRMWARE_VERSION_ID);

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

    // Wall-кванти Солдата: одне пробудження = один тік цих лічильників
    // (tick заморожений у STOP2 — пробудження і є наш годинник; сатурація
    // проти wrap). Скидання: wakeups_since_sync — beacon RX; _request — зойк.
    if (wakeups_since_boot < 0xFFFFu)         wakeups_since_boot++;
    if (wakeups_since_sync < 0xFFFFu)         wakeups_since_sync++;
    if (wakeups_since_sync_request < 0xFFFFu) wakeups_since_sync_request++;

    // =========================================================================
    // ФАЗА 1: ЗБІР ФІЗИЧНИХ ДАНИХ (Нульова ентропія)
    // =========================================================================

    // 1. Метаболізм (Час) — [FW.49 S1] wall-секунди з RTC-календаря, НЕ tick:
    // SysTick заморожений у STOP2, тож tick-різниця міряла лише active-час
    // (~секунди) → m(delta_t) ≈ максимум у всіх → over-mint. Guard-и дельти
    // (cold-start / зсув назад / стрибок епохи при першому sync) — wall_time.h.
    // wall_now == 0 (HAL-збій) → cold-start гілка guard'а → baseline.
    // [ARCH.102] Guard'и віддають СЕНТИНЕЛ «не виміряно», а не «нейтральні» 60 с:
    // ті 60 мапились у `metabolic_health` = 1.0, тобто відмова виміряти мінтила
    // МАКСИМУМ балів. Дім значення й підстави — `bio_contracts/bio_contract.rb`.
    uint32_t current_time = Wall_Seconds_Now();
    delta_t_seconds = Silken_Wall_Delta_Seconds(current_time, last_wakeup_timestamp,
                                                DELTA_T_UNKNOWN_S,
                                                DELTA_T_MAX_PLAUSIBLE_S);
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
        // [FW.50, рішення founder 2026-06-12] VREFINT + заводська каліброванка
        // → справжні мВ VDDA. Це ПРОКСІ заряду (≈3300, поки buck тримає; сідає
        // лише при брауноуті) — без нього сирий відлік ~1500 < 2800 тримав
        // вухо RX-вікна зачиненим НАЗАВЖДИ (OTA/mesh/time-sync глухі на
        // кремнії). Реальний Vcap іоністора — окремий канал + дільник
        // (hardware-гейт 👤: Adc_Raw_To_Mv, номінали — 02_03).
        uint16_t vrefint_raw = HAL_ADC_GetValue(&hadc);
        vcap_voltage = Adc_Vdda_Mv(vrefint_raw,
                                   *(volatile const uint16_t*)ADC_VREFINT_CAL_ADDR);
    }
    HAL_ADC_Stop(&hadc);

    // [FW.21] Оновлюємо фільтр пульсу (delta_t / vcap) — стан живе в RTC DR10-12,
    // зчитано в Phase 0 (BOOT). delta_t чесний лише після FW.49 (wall-clock);
    // vcap — VDDA-проксі мВ до живого Vcap-каналу (FW.50 bench).
    // [ARCH.102] Не годуємо фільтр НЕвиміром: інакше EMA «прогрівається» на
    // сентинелі й починає віддавати число, за яким виміру не стояло — тобто
    // фабрикація повертається на крок пізніше, вже під виглядом згладженої.
    if (delta_t_seconds != DELTA_T_UNKNOWN_S) {
        EMA_Update(delta_t_seconds, vcap_voltage);
    }

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

            // 5. Запускаємо "Свідомість" (Шаховий розтин звуку) — Path B (FW.25, 03_03 §3.4).
            //    Сирий кадр → 40 log-mel ознак (Compute_LogMel) → INT8-інференс.
            //    [FW.4 closed] silken_net_audio_model.h приземлено (self-owned baseline
            //    ESC-50; stub лишається fallback'ом через __has_include у шапці файлу).
            float logmel_features[LOGMEL_N_MELS];
            Compute_LogMel(audio_buffer, logmel_features);
            ml_event_id = Run_Inference(logmel_features, &ml_confidence);

            // [FW.18] Dual-Threshold Decision Logic (заміна hardcoded 0.80).
            // Пороги завантажуються з RTC DR13/DR14 на boot з валідацією
            // [TINYML_THRESHOLD_MIN_VALID..MAX_VALID]; OTA може оновити їх
            // через CMD-фреймворк (deferred, спільно з FW.8). SILENCE/WARNING/
            // CRITICAL зони — див. 03_03 §5 (CRITICAL зони design).
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

    // [FW.28] Атомарне хапання звуку: замикаємо вікно між ISR та пакуванням
    // на один міг. Жоден крик ксилеми не розчиниться між читанням і обнуленням —
    // переривання вимкнені рівно на два рядки, а потім одразу відчиняються.
    // [ARCH.102] Знімок БЕЗ обнулення. Обнуляє лише УСПІШНА передача телеметрії
    // (нижче, Фаза 4) — доти лічильник тут скидався на КОЖНОМУ проході, тобто
    // (а) на дроті він завжди був 0 або 1, хоч і σ-таблиця `03_04`, і бекендні
    // пороги писалися під семантику «подій за інтервал»; (б) події, зафіксовані
    // в циклі, який відклав TX по морозу (`Should_Defer_TX`) або відправив
    // grace-hello замість телеметрії, ЗНИКАЛИ безслідно. Тепер незʼїдений
    // залишок доживає до Кенозису й лягає в DR0 разом із рештою стану.
    __disable_irq();
    uint8_t acoustic_snapshot = acoustic_events;
    __enable_irq();

    // [ARCH.41-B/C] Час невідомий: ні beacon'а від народження (cold-boot після
    // VBAT-loss, або Королева ще мовчить). У grace-вікні (C) шлемо hello 0x56
    // замість телеметрії зі застарілим epoch_day; після grace (B) телеметрія
    // йде, але з sentinel 0xFE в acoustic і Лоренцом від acoustic=0.
    uint8_t time_uncertain = (soldier_unix_ts == 0u) ? 1u : 0u;
    // Grace — у пробудженнях (tick мертвий у STOP2: 10 хв tick-grace тривали б
    // ~1-2 год wall, відкладаючи телеметрію у стільки ж разів).
    uint8_t grace_hello = (time_uncertain &&
                           wakeups_since_boot < TIME_SYNC_COLD_BOOT_GRACE_WAKEUPS) ? 1u : 0u;

    // Байт 7: Відлуння ксилеми (Відфільтровані TinyML).
    // [FW.22] saturating uint8: значення вже у [0..255] — затискати нічого.
    // [ARCH.41-B] sentinel-підміна при невідомому часі (реальний лічильник
    // цього пробудження жертвується — час важливіший за один відлік).
    lora_payload[7] = Soldier_Acoustic_Wire_Value(acoustic_snapshot, time_uncertain);

    // Байти 8-9: час перезаряду (с). [FW.49] Wall-дельти бувають добами
    // (зимовий голод) — wire-поле uint16, тож сатуруємо: 0xFFFF = «≥18.2 год»
    // (wrap збрехав би бекенду, 200000 с → 3392 с).
    uint32_t dt_wire = (delta_t_seconds > 0xFFFFu) ? 0xFFFFu : delta_t_seconds;
    lora_payload[8] = (uint8_t)(dt_wire >> 8);
    lora_payload[9] = (uint8_t)(dt_wire & 0xFF);

    // Байт 11 [FW.18b]: бітфілд [thr_invalid:5 | TTL:3] (../common/ttl_byte.h).
    // TTL = 3 стрибки; верхні 5 біт — saturating лічильник відкинутих
    // OTA-порогів (03_03 §5.4), wire-кап 31. За нульового лічильника байт
    // бітово ідентичний старому чистому TTL.
    lora_payload[11] = Ttl_Byte_Pack(DEFAULT_TTL, tinyml_threshold_invalid_count);

    // [FIX: Firmware Version] Байти 12-13: версія прошивки (big-endian).
    // Дозволяє серверу знати яка прошивка на кожному дереві, для OTA targeting.
    // [SEC.20] Байти 12..13 = contract-звіт (fw_report.h), НЕ C-image
    // константа: semantic-біт відрізняє нову семантику від legacy-прошивок.
    lora_payload[12] = (uint8_t)(fw_contract_report >> 8);
    lora_payload[13] = (uint8_t)(fw_contract_report & 0xFF);

    // =========================================================================
    // ФАЗА 3: ПЛАВКА (Запуск Ruby та Атрактора Лоренца)
    // [SEC.11 / FW.30] Єдина сигнатура: calculate_state(x, y, z, temp, acoustic, delta_t_s, vcap_mv)
    // Warm path: (x,y,z) з RTC DR16-DR18 (FW.6 state continuation).
    // Cold path: (x₀,y₀,z₀) з K_seed via HKDF/HMAC (SEC.11 seed derivation).
    // delta_t_s/vcap_mv у mruby: EMA-згладжені після прогріву (FW.49-S1 wired);
    // до прогріву — delta_t СЕНТИНЕЛ (DELTA_T_UNKNOWN_S), vcap nominal 3300
    // (03_01 §13.3). Дві різні відповіді на дві різні відсутності: метаболізм
    // не виміряно взагалі → GP=0, а шина живлення стабілізована BQ25570.
    // =========================================================================

    // [E.63 (г)] КОНТРАКТ «wire = вхід GP»: одне число на обидва споживачі —
    // сатуроване до wire-u16 EMA (чи baseline до прогріву) йде і в mruby
    // metabolic_health, і у wire-байти 20..21. Обчислюється ДО гілкування:
    // VM_ERROR-кадр (mruby скип) теж мусить нести чесне поточне значення,
    // а не залишок минулого циклу.
    // [ARCH.102] До прогріву EMA метаболізм НЕ виміряно — і це сентинел, а не
    // baseline: `BASELINE_DELTA_T_S` тут давав GP = максимум на кожному вузлі,
    // що ще не набрав `EMA_WARMUP_CYCLES` зразків.
    uint32_t delta_t_for_lorenz = DELTA_T_UNKNOWN_S;
    uint16_t vcap_for_lorenz    = 3300u;     // nominal (NOMINAL_VCAP_MV; reserved)
    if (EMA_Is_Warmed_Up()) {
        uint32_t ema_s = EMA_Get_DeltaT_Sec();
        delta_t_for_lorenz = (ema_s > 0xFFFFu) ? 0xFFFFu : ema_s;
        vcap_for_lorenz    = EMA_Get_Vcap_Mv();
    }
#if FW2_CCM_ENABLED
    wire_ema_delta_t_s = (uint16_t)delta_t_for_lorenz;
#endif

    if (grace_hello) {
      // [ARCH.41-C] Лоренц відкладено до першого beacon'а: cold-start
      // деривація від застарілого epoch_day отруїла б RTC-ланцюг траєкторії.
      // lorenz_state_valid лишається 0 → стан у RTC не пишеться; після синку
      // перша деривація піде з ПРАВИЛЬНОЇ доби — серверу не доведеться
      // вгадувати кандидатів.
    } else if (mrb) {
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
          // [E.63] delta_t_for_lorenz/vcap_for_lorenz обчислені над гілкуванням
          // Фази 3 (контракт «wire = вхід GP» — те саме сатуроване число йде
          // у wire-байти 20..21). delta_t живить growth_points напряму
          // (metabolic_health, 03_04 §4.3); β лишається фіксованим (BASE_BETA) —
          // стара FW.5 β-перетурбація реверсована.
          mrb_value args[7];
          args[0] = mrb_float_value(mrb, (double)lorenz_x);
          args[1] = mrb_float_value(mrb, (double)lorenz_y);
          args[2] = mrb_float_value(mrb, (double)lorenz_z);
          args[3] = mrb_fixnum_value((int8_t)lora_payload[6]); // Температура
          // [ARCH.41-B] sentinel ⇒ Лоренц рахується з acoustic=0 на ОБОХ
          // сторонах (сервер нейтралізує 0xFE→0 до DCI) — інакше 0xFE=254
          // штовхав би σ у clamp і спотворював біостатус.
          args[4] = mrb_fixnum_value(time_uncertain ? 0 : lora_payload[7]); // Акустика
          args[5] = mrb_fixnum_value((mrb_int)delta_t_for_lorenz); // [E.63] delta_t → growth_points
          args[6] = mrb_fixnum_value((mrb_int)vcap_for_lorenz);    // [E.63] vcap (reserved)

          mrb_value ruby_result = mrb_funcall_argv(mrb, mrb_top_self(mrb),
              mrb_intern_lit(mrb, "calculate_state"), 7, args);

          if (!mrb->exc && mrb_array_p(ruby_result) && RARRAY_LEN(ruby_result) == 4) {
              // Витягуємо payload_byte та оновлений стан траєкторії
              lora_payload[10] = (uint8_t)mrb_fixnum(mrb_ary_entry(ruby_result, 0));
              lorenz_x = (float)mrb_float(mrb_ary_entry(ruby_result, 1));
              lorenz_y = (float)mrb_float(mrb_ary_entry(ruby_result, 2));
              lorenz_z = (float)mrb_float(mrb_ary_entry(ruby_result, 3));
              ota_vm_error_streak = 0; // [SEC.20] успіх — ланцюг збоїв обірвано
          } else {
              // Помилка mruby або невалідний результат — чесний VM_ERROR
              // (бекенд: vm_error → firmware_fault, НЕ вандалізм)
              lora_payload[10] = BIO_STATUS_VM_ERROR;
              lorenz_state_valid = 0; // Скидаємо для наступного циклу
              if (mrb->exc) mrb->exc = NULL;
              // [SEC.20] N поспіль bytecode-збоїв → OTA-версія стабільно бита.
              // Стираємо contract-сторінку (magic зникне) → наступний boot падає
              // на вбудований baseline: «не карати жертву» на firmware-рівні —
              // замість вічного vm_error вузол сам відкочується на робочу версію.
              // Лічимо ЛИШЕ цей, bytecode-exec, збій — не no-seed/OOM нижче
              // (fallback їх не лікує, лише зітер би валідний OTA даремно).
              if (ota_vm_error_streak < OTA_VM_ERR_STREAK_MASK) ota_vm_error_streak++;
              if (ota_vm_error_streak >= SEC20_VM_ERROR_FALLBACK_N) {
                  Ota_Hal_Erase((void *)0, OTA_CONTRACT_PAGE);
                  ota_vm_error_streak = 0;
                  // NVIC_SystemReset зберігає DR0 (не VBAT-loss) → персистимо
                  // streak=0 ЯВНО, інакше boot прочитав би старе значення й
                  // erase-нув би передчасно ще раз. Canary-слід [10] бережемо.
                  HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
                      ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
                      ((uint32_t)(canary_tripped & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT) |
                      (uint32_t)acoustic_events);
                  NVIC_SystemReset();
              }
          }
      } else {
          // [SEC.11 / FW.30] Ні RTC state, ні K_seed не доступні.
          // Пристрій не provisioned або Flash пошкоджений.
          lora_payload[10] = BIO_STATUS_VM_ERROR;
      }

      mrb_gc_arena_restore(mrb, arena_idx);

      // [FW.55] Детерміністичне прибирання: VM живе вічно (один mrb_open на
      // життя), тож сміття викликів копичилось би до GC-порогу (~2×live) —
      // на 64КБ SRAM це майже стеля, і доля купи залежала б від reactive
      // OOM→GC→retry. Повний GC тут — субмілісекунди раз на пробудження:
      // купа повертається до живого мінімуму ще ДО сну. Зловлено фіт-гейтом
      // QEMU-ноги (03_01 §12.7).
      mrb_full_gc(mrb);
    } else {
      // Якщо VM не запустилася при старті через нестачу пам'яті
      lora_payload[10] = BIO_STATUS_VM_ERROR;
    }

    // [FW.29] Clear PANIC_FLAG_BIT in normal packets — bit 7 is reserved for panic only
    lora_payload[10] &= ~PANIC_FLAG_BIT;

    // =========================================================================
    // ФАЗА 4: ПЕРЕДАЧА ДАНИХ (AES-128 LoRa post-ARCH.42 + Mesh)
    // =========================================================================

    // [FW.10] Зимовий кенозис передачі: при лютому морозі (-15°C і нижче) ESR
    // іоністора різко зростає — LoRa TX при кволій напрузі (<4.0В) може кинути
    // ксилему у брауноут. Краще промовчати й зберегти тепло: пропускаємо
    // Фази 4–4.5 і одразу падаємо у Кенозис.
    {
        int8_t packed_temp = (int8_t)lora_payload[6];
        if (Should_Defer_TX(packed_temp, vcap_voltage)) {
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

    // 2-3. Шифруємо і відправляємо. [ARCH.41-C] У grace-вікні замість
    // телеметрії летить hello 0x56 (DID + Vcap + TIME_REQ): Королева
    // відповість маяком (перемотка last_beacon_time), а OTA-рефлекс живе —
    // він стріляє на БУДЬ-ЯКИЙ валідний RX ще до розбору маркера. Вікно
    // слухання (Фаза 4.5) спільне — маяк буде почуто цим же пробудженням.
    if (grace_hello) {
        uint8_t hello_plain[SYNC_REQ_PACKET_SIZE];
        Build_Time_Sync_Request_Payload(hello_plain, tree_did,
                                        0u /* ніколи не чули */, vcap_voltage);
        HAL_CRYP_Encrypt(&hcryp, (uint32_t*)hello_plain, 4, (uint32_t*)encrypted_payload, 1000);
        Radio.Send(encrypted_payload, 16);
        // Cooldown НЕ чіпаємо: grace-hello летить КОЖНЕ пробудження навмисно
        // (замість телеметрії — Королеві потрібен uplink для OTA-рефлексу);
        // cooldown належить сплячому drift-watchdog'у (0x56 ПОВЕРХ телеметрії).
    } else {
        // [ARCH.102] Прапорець спільний для обох збірок: у CCM-гілці передача
        // умовна (білд кадру може не вдатись), у ECB — безумовна, а лічильник
        // мусить споживатись рівно там, де кадр справді пішов.
        uint8_t telemetry_sent = 0u;
#if FW2_CCM_ENABLED
        // [FW.2] Wire-rev2: телеметрія = 28B CCM замість 16B ECB. Джерела —
        // ті САМІ живі значення, що вже лягли в lora_payload (байт-парність
        // семантики): сирий vcap_voltage (wire завжди носив сирий, EMA — то
        // їжа Лоренца), dt_wire із сатурацією 0xFFFF, StatusByte після
        // FW.29-маски, acoustic з ARCH.41-B sentinel-логікою. mesh_ctrl =
        // [TTL:4|fw_low:4] (розкладка 03_05 §2.1; low-nibble версії — 16-епох
        // ротація через OTA-config). fauna-біти (0,0) до FW.4 fauna-pivot
        // (FW.42 ставить їх при вживленні call-site'а). Збій збірки (HAL
        // захрип) → мовчимо цей цикл: 16B-фолбек у CCM-ері Королева однаково
        // дропне (atomic-cutover), то був би спалений airtime, не телеметрія.
        uint8_t ccm_air[FW2_CCM_AIR_PACKET_LEN];
        uint8_t ccm_mesh_ctrl = (uint8_t)(((DEFAULT_TTL & FW2_MESH_TTL_MASK)
                                           << FW2_MESH_TTL_SHIFT) |
                                          (FIRMWARE_VERSION_ID & FW2_MESH_FW_NIBBLE_MASK));
        uint8_t ccm_diag = Pack_FW2_Diag(tinyml_threshold_invalid_count,
                                         0u, 0u, fc_hiwater_degraded);
        if (Soldier_Build_CCM_LoRa_Packet(tree_did, vcap_voltage,
                                          (int8_t)lora_payload[6],
                                          lora_payload[7],
                                          (uint16_t)dt_wire,
                                          lora_payload[10],
                                          ccm_mesh_ctrl,
                                          Pack_FW2_Device_Z(lorenz_z, lorenz_state_valid),
                                          ccm_diag,
                                          /* [SEC.20] vpd-байт тимчасово несе
                                             contract-звіт [rev:1|id7] до
                                             BME280 (HW.32) → rev3 віддасть
                                             чесні окремі поля */
                                          Fw_Report_To_Vpd(fw_contract_report),
                                          Soldier_Pack_Gossip_Ts_Byte(soldier_unix_ts),
                                          wire_ema_delta_t_s /* [E.63 (г)] = вхід GP */,
                                          ccm_air) == HAL_OK) {
            Radio.Send(ccm_air, FW2_CCM_AIR_PACKET_LEN);
            telemetry_sent = 1u;
        }
#else
        HAL_CRYP_Encrypt(&hcryp, (uint32_t*)lora_payload, 4, (uint32_t*)encrypted_payload, 1000);
        Radio.Send(encrypted_payload, 16);
        telemetry_sent = 1u;
#endif

        // [ARCH.102] Спожити рівно СТІЛЬКИ, скільки поїхало на дріт. Віднімання,
        // не обнулення: між знімком і передачею лічильник не росте (інкремент
        // живе у Фазі 1.5 того ж проходу), але віднімання лишається правдивим і
        // тоді, коли це зміниться. Незʼїдений залишок доживає до наступного TX.
        //
        // Гард несе ВАРІАНТ ЗБІРКИ, а не поточну гілку: під `FW2_CCM_ENABLED`
        // передача умовна (пак може віддати не HAL_OK), тож лічильник не сміє
        // з'їстися на кадрі, що НЕ поїхав. У живій ECB-збірці `Radio.Send`
        // безумовний, отже прапорець тут завжди 1 — саме це й бачить cppcheck,
        // аналізуючи одну конфігурацію. Прибрати гард не можна: він оживає рівно
        // тоді, коли CCM знімуть зі стенда, а дублювати виклик у обидві гілки
        // означало б два доми одного споживання.
        // cppcheck-suppress knownConditionTrueFalse
        if (telemetry_sent) {
            __disable_irq();
            acoustic_events = Acoustic_Ledger_Consume(acoustic_events, acoustic_snapshot);
            __enable_irq();
        }

        // [FW.20-S2 3/5] Сторожовий пес часу подає голос: ≈12 год пробуджень
        // без голосу Королеви → зойк 0x56 ПОВЕРХ телеметрії (перший — одразу,
        // далі cooldown ≈1 год). Королева перемотує такт маяка → re-sync цим
        // же пробудженням (вікно Фази 4.5 нижче вже відкрите). Пасивний шлях
        // сам не гарантує: вухо 600 мс/цикл проти 15-хв такту ловить маяк у
        // середньому раз на ~12 год — впритул до порога watchdog'а. У grace-
        // вікні сюди не потрапляємо (гілка hello вище), а після нього при
        // німому часі зойк і є rate-limited продовженням hello.
        if (Soldier_Should_Request_Time_Sync()) {
            uint8_t sync_plain[SYNC_REQ_PACKET_SIZE];
            Build_Time_Sync_Request_Payload(sync_plain, tree_did,
                                            Soldier_Seconds_Since_Last_Sync(),
                                            vcap_voltage);
            HAL_Delay(100); // радіо ще випромінює телеметрію (як mesh-relay)
            HAL_CRYP_Encrypt(&hcryp, (uint32_t*)sync_plain, 4, (uint32_t*)encrypted_payload, 1000);
            Radio.Send(encrypted_payload, 16);
            wakeups_since_sync_request = 0; // мітка зойка — cooldown пішов
            sync_request_ever = 1;
        }
    }

    // [SEC.21] Слід канарки → ефір: 0x57 ПОВЕРХ телеметрії (патерн
    // drift-watchdog'а 0x56), по одному пострілу на пробудження, всього 3.
    // Після третього слід гаситься — Phase 5 понесе DR0[10]=0; Королева
    // читає кадр сама (транзишн-ключ, дзеркало 0x55/0x56) → ring → Rails.
    if (canary_evt_shots > 0u) {
        uint8_t evt_plain[DEVICE_EVT_PACKET_SIZE];
        Device_Event_Build(evt_plain, tree_did, DEVICE_EVT_CANARY_TRIP,
                           0u /* arg — резерв (PC/LR-фрагмент) */,
                           ++canary_evt_seq, vcap_voltage);
        HAL_Delay(100); // пауза після попереднього TX (як mesh-relay)
        HAL_CRYP_Encrypt(&hcryp, (uint32_t*)evt_plain, 4, (uint32_t*)encrypted_payload, 1000);
        Radio.Send(encrypted_payload, 16);
        if (--canary_evt_shots == 0u) canary_tripped = 0;
    }

    // =========================================================================
    // ФАЗА 4.5: ЕНЕРГОЕФЕКТИВНИЙ СЛУХ (Directed Mesh & OTA)
    // =========================================================================

    // Слухаємо ефір ТІЛЬКИ якщо ми багаті на енергію (напруга > 2.8В)
    if (vcap_voltage > VCAP_LISTEN_THRESHOLD) {
#if ARCH26_CAD_ENABLED
        // [ARCH.26 L3] Нюх Провідника: кожні CAD_SNIFF_PERIOD_S — мс-CAD.
        // Host-half wiring: справжня економія (нюх-ЗАМІСТЬ-повного-RX у
        // WUT-циклі, g_cad_activity як воротар вуха) — bench; тут глю
        // під тим самим vcap-гейтом, що й вухо, яке нюх відкриває.
        if (Cad_Sniff_Due((uint8_t)(g_node_role == ROLE_PROVISIONER),
                          Wall_Seconds_Now(), g_last_cad_sniff_wall,
                          CAD_SNIFF_PERIOD_S_DEFAULT)) {
            g_cad_activity = 0u;
            Radio.StartCad();                 // вердикт прийде в OnCadDone
            g_last_cad_sniff_wall = Wall_Seconds_Now();
        }
#endif
        lora_rx_flag = 0;
        Radio.Rx(LORA_RX_TIMEOUT_MS);

        uint32_t rx_start_time = HAL_GetTick();
        while((HAL_GetTick() - rx_start_time) < LORA_RX_LOOP_MS) {
            if(lora_rx_flag == 1) {
                // [FW.2] Чужий формат ефіру гине ДО декрипту (ungated — вірно
                // в обох ерах): усі легальні кадри Солдата = рівно 16B ECB
                // (beacon/OTA/печатка/CMD/mesh). 28B CCM-кадр сусіда, прогнаний
                // ECB'ом, давав ~1/256 шанс хибно зійтися на 0x99/0x9B і
                // отруїти ota_buffer/печатку. CCM-телеметрію Солдат свідомо НЕ
                // ретранслює: mesh-TTL живе у шифртексті — рішення відкладено
                // до ARCH.26 (03_05 §2.1 «Відкриті спостереження»).
                if (incoming_lora_size != 16) {
                    break; // не наш формат — спати (re-request Фази 4.5 живий)
                }

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
                        wakeups_since_sync         = 0; // голос Королеви — тиша скінчилась
                        // [FW.49 S1] UTC у RTC-календар: wall-clock стає
                        // абсолютним — delta_t/epoch_day переживають STOP2
                        // без tick-екстраполяції (вона лишається фолбеком).
                        Wall_Calendar_Set(beacon_ts);
                    }

                    // [FW.20-S2] Зчитуємо authoritativeness прапорець з байту 9
                    // (біт 7). 1 = пряма трансляція від Королеви; 0 = relay
                    // або легасі-маяк (попередня прошивка слала TTL=1 чисто).
                    // Логіки арбітражу між двома маяками ще НЕ додано —
                    // це повний FW.20-S2; зараз лише фіксуємо у RAM, щоб
                    // upper layers (CAD relay) могли консультуватись.
                    time_source_authoritative =
                        (decrypted_rx_payload[9] & BEACON_AUTH_FLAG) ? 1 : 0;

#if ARCH26_TDMA_ENABLED
                    // [ARCH.26 L2] Байти 5..8 — слот-розкладка синхронних
                    // вікон. Parse fail-closed (нулі/сміття → disabled);
                    // наступне вікно = Tdma_Next_Window_Start(&g_tdma_schedule,
                    // Wall_Seconds_Now()) → вхід для WUT-армінгу (bench).
                    (void)Tdma_Parse_Beacon_Bytes(&decrypted_rx_payload[5],
                                                  &g_tdma_schedule);
#endif

#if FW20_MESH_RELAY_ENABLED
                    // [FW.20-S2 4/5] Провідник несе голос далі. Енергогейт
                    // успадковано: ця гілка живе лише при vcap > LISTEN-
                    // порога, а роль PROV — еліта з надлишком (ARCH.27).
                    // Mark — RAM одразу після TX; запис 0x20 у Flash — у
                    // КЕНОЗИСІ (program не сміє лягати під RX-вікно).
                    if (beacon_ts != 0) {
                        uint8_t  relay_plain[BEACON_PLAINTEXT_SIZE];
                        uint32_t relay_now = HAL_GetTick();
                        BeaconRelayResult rr = Soldier_Try_Relay_Time_Beacon(
                            decrypted_rx_payload, g_node_role,
                            relay_now, relay_now,
                            soldier_kv_mounted ? &beacon_dedup : NULL,
                            relay_plain);
                        if (rr == BEACON_RELAY_OK) {
                            HAL_CRYP_Encrypt(&hcryp, (uint32_t*)relay_plain, 4,
                                             (uint32_t*)encrypted_payload, 1000);
                            Radio.Send(encrypted_payload, BEACON_PLAINTEXT_SIZE);
                            Beacon_Dedup_Mark(&beacon_dedup,
                                              Beacon_Dedup_Gen(beacon_ts));
                        }
                    }
#endif
                    // Один RX-пакет за пробудження (FW.52 ADR) — спати.
                    break;
                }

                // Сценарій 1: [FW.8] CMD_SET_THRESHOLDS (0x9A) — Z-пороги Лоренца.
                // 🟡 Deferred TRL-7. Парсер `Soldier_Handle_CMD_SET_THRESHOLDS`
                // залишено + 12 host-тестів як freeze-контракт wire-формату,
                // але в production-цикл ВИМКНЕНО (`FW8_PARSER_ENABLED 0`).
                // Деталі — у блоці-преамбулі біля визначення макроса.
                // Бекенд `OtaPackagerService.build_threshold_config_block` —
                // лише class method, у downlink pipeline не передається
                // (свідомий defer: на TRL-6 усі види на дефолтах — re-send
                // щодня був би no-op за ~5% downlink-бюджету).
                // Boot-restore і КЕНОЗИС-write написані за цим же гейтом —
                // активація = лише фліп `FW8_PARSER_ENABLED 1` (bench).
#if FW8_PARSER_ENABLED
                if (decrypted_rx_payload[0] == CMD_SET_THRESHOLDS_MARKER &&
                    incoming_lora_size >= CMD_THRESHOLDS_FRAME_SIZE) {
                    if (Soldier_Handle_CMD_SET_THRESHOLDS(decrypted_rx_payload,
                                                          incoming_lora_size)) {
                        lorenz_thresholds_dirty = 1; // Flash-KV — у КЕНОЗИСІ
                    }
                    // Незалежно від результату парсингу — не ретранслюємо (TTL=1)
                    break;
                }
#endif

                // Сценарій 1б: [FW.17] CMD_ROTATE_KEY (0x9E) — Hash-Ratchet
                // ротація LoRa-ключа. 🟡 Вимкнено до FW.2 CCM (деталі — у
                // преамбулі FW17_RATCHET_ENABLED). Невалідний кадр / replay /
                // rollback / runaway-стрибок Advance мовчки відкидає — стан
                // (ключ + версія) незмінний, як ефірний шум.
#if FW17_RATCHET_ENABLED
                if (decrypted_rx_payload[0] == CMD_ROTATE_KEY_MARKER &&
                    incoming_lora_size >= CMD_ROTATE_KEY_FRAME_SIZE) {
                    uint16_t rotate_target = 0;
                    if (Key_Ratchet_Parse_Cmd((const uint8_t*)decrypted_rx_payload,
                                              incoming_lora_size, &rotate_target)) {
                        uint8_t key_bytes[KEY_RATCHET_KEY_LEN];
                        Key_Ratchet_Words_To_Bytes(aes_key, key_bytes);
                        if (Key_Ratchet_Advance(key_bytes, &lora_key_version,
                                                rotate_target, tree_did)) {
                            Key_Ratchet_Bytes_To_Words(key_bytes, aes_key);
                            // [FW.2 (в)] Ратчет ротує ЛИШЕ session (KEYL):
                            // MX_CRYP_Init повертає амбієнт = bcast_key, тож
                            // downlink НЕ глухне від ротації (двоключова
                            // розв'язка); новий K_v застосує наступний
                            // MX_CRYP_Init_CCM. KEYB ратчет НЕ торкається —
                            // його ротація = re-provision (як K_ota).
                            MX_CRYP_Init();             // re-key контексту
                            lora_key_version_dirty = 1; // Flash-KV — у КЕНОЗИСІ
                        }
                    }
                    // Не ретранслюємо (TTL=1) — слово адресоване цьому Солдату
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

                // Сценарій А1: [FW.23] HMAC-печатка OTA (0x9B) — 4 LoRa-чанки
                // після тіла прошивки: 3 несуть 32-байтну печатку, 4-й — version_id
                // над (bytecode || version_id_be || total_chunks_be).
                if (decrypted_rx_payload[0] == HMAC_TRAILER_MARKER) {
                    int rc = Parse_HMAC_Trailer_Chunk((const uint8_t*)decrypted_rx_payload,
                                                       incoming_lora_size,
                                                       received_hmac_tag,
                                                       &received_ota_version,
                                                       &ota_hmac_segments_received);
                    // rc=1 ⇒ печатка/версія лягли на місце; rc=0 ⇒ не наш marker
                    // (сюди ми б не зайшли); rc=-1 ⇒ невалідна (size/seg_idx) —
                    // мовчки відкидаємо, як ефірний шум.
                    (void)rc;

                    // [FW.23] Печатка могла прийти ПІСЛЯ останнього чанка тіла —
                    // тоді саме вона довершує OTA. Якщо тіло вже зібране й тепер є
                    // всі 4 трейлер-чанки → фіналізуємо тут (дзеркало 0x99-гілки).
                    uint16_t data_len = 0;
                    OtaFinalizeVerdict verdict = OTA_Try_Finalize(
                        ota_buffer, ota_bytes_received,
                        ota_chunks_received, ota_total_chunks,
                        ota_hmac_segments_received,
                        ota_hmac_key, ota_hmac_key_valid,
                        received_ota_version, received_hmac_tag,
                        &data_len);

                    // [SEC.20] Dual-gate довів справжність, але не свіжість:
                    // старе валідно-підписане слово (replay/downgrade) чекає
                    // тієї ж жертви лжемагії, що й крипто-відмова — bio_contract
                    // тече лише вперед.
                    if (verdict == OTA_FINALIZE_APPLY &&
                        !Ota_Version_Is_Fresh(&soldier_kv, soldier_kv_mounted, received_ota_version)) {
                        verdict = OTA_FINALIZE_REJECT;
                    }
                    if (verdict == OTA_FINALIZE_APPLY) {
                        Write_OTA_Contract_To_Flash(ota_buffer, data_len);
                        Ota_Version_Commit(&soldier_kv, soldier_kv_mounted, received_ota_version);
                        NVIC_SystemReset();
                    } else if (verdict == OTA_FINALIZE_REJECT) {
                        if (ota_bytes_received >= 4) {
                            ota_buffer[0] = 0;
                            ota_buffer[1] = 0;
                            ota_buffer[2] = 0;
                            ota_buffer[3] = 0;
                        }
                        Reset_Ota_Assembly();
                    }
                    // WAIT: тіло ще не зібране — печатка чекає на свої чанки тіла.
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

                    // [FIX: AUDIT] Валідація: total_chunks не повинно змінюватися між пакетами.
                    // [FW.53] ...але мертва кампанія не має права блокувати живу:
                    // N поспіль чужих total → стираємо незавершену збірку (deadlock-захист).
                    if (ota_total_chunks != 0 && incoming_total != ota_total_chunks) {
                        if (++ota_total_mismatch_streak >= OTA_MISMATCH_RESET_THRESHOLD) {
                            Reset_Ota_Assembly();  // [FW.23] повне скидання (вкл. version/streak)
                        }
                        break; // Цей чанк ігноруємо; наступні почнуть нову збірку
                    }
                    ota_total_mismatch_streak = 0;

                    // [FW.23] При першому чанку нового OTA-вікна стираємо
                    // стару печатку з пам'яті — нова прошивка прийде з новою
                    // істиною. Печатка-чанки (0x9B) можуть надходити у будь-
                    // якому порядку, тому обнуляємо саме на світанку, а не на
                    // заході OTA-вікна.
                    if (ota_total_chunks == 0) {
                        memset(received_hmac_tag, 0, sizeof(received_hmac_tag));
                        received_ota_version = 0;
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
                        // [FW.27-B] Солдат пам'ятає, що чув голос Королеви:
                        // tick = маркер «вже чули», лічильник тиші — в нуль.
                        // Достатньо тихих пробуджень — і він озветься
                        // перепитати про пропуски.
                        ota_last_chunk_rx_tick = HAL_GetTick();
                        ota_silent_wakeups = 0;

                        // [FW.23] Останній чанк ТІЛА міг прийти раніше за печатку
                        // (Королева шле тіло → потім печатку). OTA_Try_Finalize дає
                        // WAIT, якщо ще нема всіх 4 трейлер-чанків — тоді НІЧОГО не
                        // чіпаємо: зібране тіло чекає, а фіналізацію довершить 0x9B-
                        // гілка, коли долетить остання печатка. Запис у Flash і
                        // ребут — лише коли обидві брами (magic + HMAC) розчинились.
                        uint16_t data_len = 0;
                        OtaFinalizeVerdict verdict = OTA_Try_Finalize(
                            ota_buffer, ota_bytes_received,
                            ota_chunks_received, ota_total_chunks,
                            ota_hmac_segments_received,
                            ota_hmac_key, ota_hmac_key_valid,
                            received_ota_version, received_hmac_tag,
                            &data_len);

                        // [SEC.20] Свіжість поверх справжності — див. 0x9B-гілку.
                        if (verdict == OTA_FINALIZE_APPLY &&
                            !Ota_Version_Is_Fresh(&soldier_kv, soldier_kv_mounted, received_ota_version)) {
                            verdict = OTA_FINALIZE_REJECT;
                        }
                        if (verdict == OTA_FINALIZE_APPLY) {
                            Write_OTA_Contract_To_Flash(ota_buffer, data_len);
                            Ota_Version_Commit(&soldier_kv, soldier_kv_mounted, received_ota_version);
                            NVIC_SystemReset();
                        } else if (verdict == OTA_FINALIZE_REJECT) {
                            // Жертовне знищення лжемагії: CRC/брама/ключ впали —
                            // стираємо magic у RAM-bytecode, щоб частково записаний
                            // OTA не воскрес при наступному boot через корумпований
                            // RAM. Рій більший за один Солдат: слово спокусника не
                            // повинне жити в його плоті.
                            if (ota_bytes_received >= 4) {
                                ota_buffer[0] = 0;
                                ota_buffer[1] = 0;
                                ota_buffer[2] = 0;
                                ota_buffer[3] = 0;
                            }
                            Reset_Ota_Assembly();
                        }
                        // OTA_FINALIZE_WAIT: тіло зібране, печатка ще летить — чекаємо.
                    }
                }
#if !FW2_CCM_ENABLED
                // Сценарій Б: Mesh Естафета (Чужі дані на 16 байт)
                // [FW.2 (в)] CCM-ера ховає естафету ЗА ГЕЙТ: телеметрія й
                // panic сусідів стають 28B (гинуть на RX-guard вище до
                // декрипту), а session-ключі per-device — чужий кадр однаково
                // нечитний. 16B тут лишився б тільки легасі/чужий ефір —
                // релей сміття марнує мДж. Star-only = свідома ціна фліпа
                // (ARCH.43 резолюція «прийняти на поточному TRL»); mesh
                // повертається лише з addressing-шаром ARCH.43.
                else if (incoming_lora_size == 16) {
                    // [FW.18b] Байт 11 — бітфілд: живість пакета = лише
                    // нижні 3 біти TTL, верхні 5 — лічильник origin-Солдата
                    // (інакше чужий ненульовий лічильник = вічний релей).
                    uint8_t incoming_ttl = Ttl_Byte_Ttl(decrypted_rx_payload[11]);

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
                        // [FW.21] Перевіряємо всі 3 слоти кешу пліток
                        uint8_t is_known_did = 0;
                        for(int i = 0; i < MESH_DID_CACHE_SIZE; i++) {
                            if (recent_mesh_dids[i] == incoming_did) {
                                is_known_did = 1;
                                break;
                            }
                        }

                        // Якщо пакет ще "живий", І ми його ще не пересилали
                        if (!is_known_did) {
                            // Зменшуємо TTL (лічильник origin'а — недоторканий)
                            decrypted_rx_payload[11] = Ttl_Byte_Decrement(decrypted_rx_payload[11]);

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
#endif // !FW2_CCM_ENABLED — Сценарій Б (естафета) живе лише в ECB-еру

                break; // Виходимо з циклу
            }
            HAL_IWDG_Refresh(&hiwdg);
        }
        Radio.Sleep(); // Вимикаємо приймач

        // =====================================================================
        // [FW.27-B] Magic Re-Request: Солдат подає голос про пропуски
        // =====================================================================
        // Якщо OTA-вікно відкрите (>0 чанків лежить у пам'яті, але < total),
        // а вухо цього пробудження не почуло нового слова — ще одна тиха ніч
        // у лічильник. Десята (≈5 хв wall при циклі 26-32 с) — і Солдат
        // стріляє в ефір зойком [0x55][DID:4][total:2 BE][bitmap:9], а
        // Королева повторює лише те, чого бракує. Власний jitter
        // (TX_JITTER_MAX_MS) розводить голоси сусідніх дерев у часі.
        if (ota_total_chunks > 0 &&
            ota_chunks_received < ota_total_chunks &&
            ota_last_chunk_rx_tick != 0) {

            if (ota_silent_wakeups < 255u) ota_silent_wakeups++;

            if (ota_silent_wakeups >= OTA_REREQUEST_SILENT_WAKEUPS) {
                uint8_t req_payload[OTA_REQ_PACKET_SIZE] = {0};

                uint8_t any_missing = Build_OTA_ReRequest_Payload(tree_did,
                                                                   ota_total_chunks,
                                                                   ota_chunk_received,
                                                                   sizeof(ota_chunk_received),
                                                                   req_payload);
                if (any_missing) {
                    uint8_t encrypted_req[OTA_REQ_PACKET_SIZE] = {0};
                    // Шифруємо запит (1 AES-128-ECB block = 16 байт = 4 слова, post-ARCH.42)
                    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)req_payload, 4,
                                      (uint32_t*)encrypted_req, 1000);
                    Radio.Send(encrypted_req, OTA_REQ_PACKET_SIZE);
                    // Лічильник у нуль — даємо Королеві стільки ж тихих
                    // пробуджень на ретрансляцію перед наступним зойком.
                    ota_silent_wakeups = 0;
                }
            }
        }
    }

    phase5_kenosis:
    // =========================================================================
    // ФАЗА 5: КЕНОЗИС (Абсолютний сон та збереження)
    // =========================================================================
    // [SEC.10/SEC.20] DR0: [panic:16 | rsv:6 | vm_err_streak:2 | acoustic:8]
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
        ((uint32_t)(canary_tripped & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT) |
        ((uint32_t)(ota_vm_error_streak & OTA_VM_ERR_STREAK_MASK) << OTA_VM_ERR_STREAK_DR0_SHIFT) |
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
    // [FW.21] 3 слоти (DR8, DR9, DR11); DR10/DR12 — EMA. Повна розкладка — 03_01 §2
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
    // прочитали). Це робиться, щоб OTA-set значення (CMD_SET_AUDIO_THRESHOLDS
    // 0x9D — жива гілка) пережили STOP2 та повне знеструмлення RTC ⇒ при
    // VBAT-loss RTC обнуляється, на boot Apply_Thresholds() повертає
    // дефолти, і ці дефолти знову персистяться для наступного циклу.
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR13, float_to_uint32(tinyml_warning_threshold));
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR14, float_to_uint32(tinyml_critical_threshold));

#if FW17_RATCHET_ENABLED
    // [FW.17] Версія ratchet'а — у Flash-KV саме тут, у КЕНОЗИСІ: erase/
    // program не сміє лягти під LoRa RX-вікно (03_01 §2.3). Power-cut між
    // re-key (RAM) і цим записом безпечний: boot повернеться на стару
    // версію, а бекендовий Dual-Key Grace ще тримає старий ключ — наступний
    // 0x9E (абсолютний target) дожене.
    if (lora_key_version_dirty && soldier_kv_mounted) {
        if (FlashKv_Put32(&soldier_kv, FW17_KV_KEY_VERSION,
                          (uint32_t)lora_key_version)) {
            lora_key_version_dirty = 0;
        }
    }
#endif
#if FW8_PARSER_ENABLED
    // [FW.8] Прийняті 0x9A-пороги — у Flash-KV у тій самій безпечній фазі.
    // Невалідну конфігурацію Save не пише взагалі; power-cut між парою
    // ключів лікується наступним daily re-send (ADR у lorenz_thresholds.h).
    if (lorenz_thresholds_dirty && soldier_kv_mounted) {
        LorenzThresholds t;
        t.z_min_x100     = lorenz_z_min_x100;
        t.z_max_x100     = lorenz_z_max_x100;
        t.z_opt_x100     = lorenz_z_opt_x100;
        t.species_id     = lorenz_species_id;
        t.config_version = lorenz_config_version;
        if (Lorenz_Thresholds_Save(&soldier_kv, &t)) {
            lorenz_thresholds_dirty = 0;
        }
    }
#endif
#if FW2_CCM_ENABLED
    // [FW.2 TRL-7] Проактивне просування межі FC — у тій самій безпечній
    // фазі. Наступний TX підбирається до межі ближче ніж на MARGIN →
    // один dw-program ставить її на STRIDE уперед, і сторожа у Build_CCM
    // лишається мертвим кодом. fc_now == 0 — CCM у цьому втіленні ще не
    // передавав (магія DR15 не зведена), межі нічого не загрожує.
    if (soldier_kv_mounted) {
        uint32_t fc_now = Unpack_FW2_Frame_Counter(
            HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR15));
        if (fc_now != 0 &&
            Fc_Hiwater_Should_Advance(fc_hiwater_cache, fc_now + 1u) &&
            Fc_Hiwater_Advance(&soldier_kv, Fc_Hiwater_Target(fc_now),
                               &fc_hiwater_cache)) {
            fc_hiwater_degraded = 0; // межа знову попереду всіх переданих
        }
    }
#endif
#if FW20_MESH_RELAY_ENABLED
    // [FW.20-S2 4/5] Журнал поколінь маяка — у тій самій безпечній фазі.
    // Відмова запису не критична: dirty лишається, RAM-копія тримає дедуп
    // до сну, power-cut коштує однієї зайвої ретрансляції після ребуту.
    if (soldier_kv_mounted) {
        Beacon_Dedup_Persist(&soldier_kv, &beacon_dedup);
    }
#endif
#if FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED || FW2_CCM_ENABLED || FW20_MESH_RELAY_ENABLED || SEC20_OTA_ANTIROLLBACK_ENABLED
    // [ARCH.28] Ущільнення журналу — спільне для всіх KV-споживачів, лише
    // у цій безпечній фазі (після TX, перед сном; erase ~десятки мс не
    // сміє лягти під LoRa RX-вікно). [SEC.20] version-hiwater пише 0x15 щоразу
    // на OTA APPLY — без compact сторінка переповниться (~254 APPLY), Put32
    // замерзне приплив і Get32 віддаватиме стару версію → replay-downgrade.
    if (soldier_kv_mounted && FlashKv_NeedsCompact(&soldier_kv, 8)) {
        FlashKv_Compact(&soldier_kv);
    }
#endif

    // [FIX: AUDIT Energy] Вимикаємо периферію перед STOP2 для мінімального споживання.
    // Без де-ініціалізації ці модулі тягнуть мікроампери навіть у STOP2.
    // [FW.46] RCC-гейт криптоблока на WL зветься AES, не CRYP (F4/F7-стиль
    // __HAL_RCC_CRYP_CLK_* у WL-HAL не існує — зловив HAL compile-lane).
    HAL_RNG_DeInit(&hrng);
    __HAL_RCC_AES_CLK_DISABLE();

    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
    HAL_ResumeTick();

    // [FIX: AUDIT Energy] Відновлюємо периферію після пробудження
    HAL_RNG_Init(&hrng);
    __HAL_RCC_AES_CLK_ENABLE();
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
// payload лишається не-const: сигнатуру диктує callback-контракт радіо
// (Semtech RadioEvents_t.RxDone, uint8_t*) — const зламав би тип реєстрації.
// cppcheck-suppress constParameterCallback
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr)
{
    // [FIX: AUDIT] size > 0 && size <= buffer: виправлено off-by-one (було size < 255)
    if (size > 0 && size <= sizeof(incoming_lora_payload)) {
        // Знімаємо volatile-мантію для memcpy: лише ISR пише у цей буфер,
        // і головний цикл не торкнеться його, поки не побачить lora_rx_flag.
        memcpy((void*)incoming_lora_payload, payload, size);
        incoming_lora_size = size;
        lora_rx_flag = 1;
    }
}

#if ARCH26_CAD_ENABLED
// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС НЮХУ (Ніс Провідника) — ARCH.26 L3
// =========================================================================
// bool диктує callback-контракт Semtech RadioEvents_t.CadDone (як OnRxDone
// вище); інертний до реєстрації events-таблиці на HAL-фазі (FW.46).
void OnCadDone(bool channelActivityDetected)
{
    g_cad_activity = Cad_Should_Open_Rx((uint8_t)channelActivityDetected);
}
#endif

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
        ((uint32_t)(canary_tripped & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT) |
        ((uint32_t)(ota_vm_error_streak & OTA_VM_ERR_STREAK_MASK) << OTA_VM_ERR_STREAK_DR0_SHIFT) |
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
#if FW2_CCM_ENABLED
    // [FW.2] Panic їде тим САМИМ CCM-потоком, що телеметрія: FC у нонсі =
    // anti-replay для ВСІХ кадрів (03_05 §2.1 — SEC.10 DR0[31:16]-лічильник
    // звільнено фліпом), а MIC не дає зліпити зойк із чужих байтів. Поля
    // дзеркалять legacy-паніку (нулі vcap/temp/dt — ECB-кадр теж їх не ніс),
    // acoustic=0xFF = код паніки, + чесний device_z поточного стану.
    uint8_t panic_air[FW2_CCM_AIR_PACKET_LEN];
    uint8_t panic_mesh_ctrl = (uint8_t)(((PANIC_TTL & FW2_MESH_TTL_MASK)
                                         << FW2_MESH_TTL_SHIFT) |
                                        (FIRMWARE_VERSION_ID & FW2_MESH_FW_NIBBLE_MASK));
    uint8_t panic_diag = Pack_FW2_Diag(tinyml_threshold_invalid_count,
                                       0u, 0u, fc_hiwater_degraded);
    int panic_built = Soldier_Build_CCM_LoRa_Packet(tree_did,
                          0u /* vcap: legacy-parity */, 0 /* temp */,
                          0xFFu /* акустика: код паніки */, 0u /* dt */,
                          FW2_STATUS_PANIC_BIT, panic_mesh_ctrl,
                          Pack_FW2_Device_Z(lorenz_z, lorenz_state_valid),
                          panic_diag, 0x00,
                          Soldier_Pack_Gossip_Ts_Byte(soldier_unix_ts),
                          0u /* ema: panic ≠ homeostasis, recompute скип */,
                          panic_air);
#else
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

    // 3. TTL = 5, щоб пакет вижив довше і точно дійшов; верхні 5 біт —
    //    лічильник FW.18b (бітфілд ttl_byte.h, як у звичайному пакеті)
    panic_payload[11] = Ttl_Byte_Pack(PANIC_TTL, tinyml_threshold_invalid_count);

    // [SEC.10] Лічильник panic-кадрів у байтах PAD 14..15 (BE).
    // Бекенд читає `pad_data[2..3].unpack1("n")` як nonce для SETNX.
    panic_payload[PANIC_COUNTER_PAD_HI] = (uint8_t)(panic_frame_counter >> 8);
    panic_payload[PANIC_COUNTER_PAD_LO] = (uint8_t)(panic_frame_counter & 0xFFu);

    // [SEC.10] Персистимо новий лічильник у DR0 НЕГАЙНО, до того як
    // PVD-брауноут або soft-reset встигне поглинути нас перед Phase 5.
    // [SEC.20] Зберігаємо й vm_err_streak[9:8] — інакше panic-запис обнуляв би
    // лічильник bytecode-збоїв (DR0-мапа §2 дотримана на ВСІХ трьох write).
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
        ((uint32_t)(canary_tripped & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT) |
        ((uint32_t)(ota_vm_error_streak & OTA_VM_ERR_STREAK_MASK) << OTA_VM_ERR_STREAK_DR0_SHIFT) |
        (uint32_t)acoustic_events);

    // 4. Шифруємо AES-128 (post-ARCH.42) і миттєво вистрілюємо
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)panic_payload, 4, (uint32_t*)encrypted_panic, 1000);
#endif

#if ARCH26_CAD_ENABLED
    // [ARCH.26 L3] «Останній зойк»: преамбула довша за період нюху
    // Провідника (гарантія T_pre > T_sniff — 02_03 §9.10), щоб PANIC
    // ловили й поза зоною Королеви. Дворівневий Vcap-гейт (EMA-оцінка
    // заряду, DR12): нижче порога — дефолтні 8 симв, бо brownout ПОСЕРЕД
    // преамбули = не вилетіло НІЧОГО, а короткий зойк Королева (L1) ще
    // зловить. Контекст: main-loop Path-B (EXTI лише ставить
    // vibration_detected) — блокуючий SetTxConfig/HAL_Delay безпечні;
    // НЕ кликати цю функцію з ISR.
    Radio.SetTxConfig(MODEM_LORA, LORA_PANIC_TX_POWER_DBM, 0u,
                      LORA_PANIC_BW_125K, LORA_PANIC_SF, LORA_PANIC_CR_4_5,
                      Cad_Panic_Preamble_Symbols(
                          EMA_Get_Vcap_Mv(), CAD_PANIC_PREAMBLE_VCAP_MIN_MV,
                          Cad_Preamble_Symbols_For_Ms(CAD_PANIC_PREAMBLE_MS,
                                                      CAD_T_SYM_SF9_BW125_US)),
                      false, true, false, 0u, false, 0u);
#endif
#if FW2_CCM_ENABLED
    // Збій збірки (HAL захрип) → мовчимо: підроблений/битий зойк гірший за
    // тишу, а L1-Королева все одно слухає наступне пробудження.
    if (panic_built == HAL_OK) {
        Radio.Send(panic_air, FW2_CCM_AIR_PACKET_LEN);
    }
#else
    Radio.Send(encrypted_panic, 16);
#endif

    // 5. Мікро-пауза, щоб радіомодуль встиг фізично випромінити пакет
    HAL_Delay(100);

#if ARCH26_CAD_ENABLED
    // Обов'язкове відновлення дефолтної преамбули (дисципліна
    // Restore_ECB_Mode): липкі ~973 симв на наступному звичайному TX
    // мовчки з'їли б ~40× airtime і енергобюджет циклу.
    Radio.SetTxConfig(MODEM_LORA, LORA_PANIC_TX_POWER_DBM, 0u,
                      LORA_PANIC_BW_125K, LORA_PANIC_SF, LORA_PANIC_CR_4_5,
                      CAD_PREAMBLE_DEFAULT_SYMBOLS,
                      false, true, false, 0u, false, 0u);
#endif

    // 6. Примусово присипляємо радіо, щоб не садити батарею
    Radio.Sleep();
}

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС DMA (Буфер звуку заповнено)
// =========================================================================
// Перекриття слабкого символа HAL: тип сигнатури фіксований прототипом
// HAL_ADC_ConvCpltCallback (const зламав би це перекриття); параметр `hadc`
// тінює глобальний CubeMX-handle і тут не використовується.
// cppcheck-suppress constParameterPointer
// cppcheck-suppress shadowVariable
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc)
{
    // Ця функція викликається апаратно, коли DMA запише 512-й байт.
    // Вона миттєво виводить процесор зі стану SLEEP для аналізу.
    (void)hadc;
    audio_ready = 1;
}

// =========================================================================
// [FW.1 + ARCH.42 Variant B, 2026-05-23] ЗАВАНТАЖЕННЯ LoRa AES-128 КЛЮЧА
// З PROTECTED FLASH SECTOR
// =========================================================================
// Формат Flash-регіону на FLASH_KEY_ADDR (0x0803E000) — post-ARCH.42:
//   [0] FLASH_KEY_MAGIC (0x4B45594C = "KEYL") — маркер provisioned LoRa-ключа
//   [1..4] aes_key[0..3] — 4 × uint32_t = 128 bits AES-128 key
//
// Загальний розмір регіону = 4 + 16 = 20 байт (раніше 4 + 32 = 36 байт для AES-256).
//
// Якщо magic відсутній або ключ нульовий — пристрій не provisioned,
// Error_Handler() викликає software reset. Пристрій не може працювати
// без валідного ключа (BLOCKER-1 mitigation).
//
// Записується при Factory Flashing через SWD:
//   STM32CubeProgrammer --write key_payload.bin 0x0803E000
// Ключ деривується на backend: HKDF-SHA256(master_key, device_uid, "silken-aes-128-lora-key")
// — info-string відрізняється від CoAP-каналу (Gateway) "silken-aes-256-device-key"
// для domain separation. Див. docs/03_05 §3.1 + docs/03_06 §2 для повного протоколу.
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

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
// [FW.2 гейт (в)] Завантаження cluster control-plane ключа (KEYB, стор. 125).
// НЕ Error_Handler(): відсутній KEYB — законна bench-плата, прошита до
// KEYB-ери, вона деградує до односхемної поведінки (амбієнт = KEYL, як
// ECB-ера) і чесно позначає це прапорцем. Fail-open тут безпечний, бо
// fallback-ключ — той самий, на якому такий кластер і живе; фабрика
// CCM-ери пише обидва слоти (command_builder), тож у полі прапорець
// мусить бути 0. Патерн — Load_Ota_Hmac_Key (fail-open + valid-флаг),
// НЕ Load_AES_Key (fatal). Порядок у main() несучий: виклик ПЕРЕДУЄ
// FW17_Restore_Key_Version — fallback бере K0, ратчений session не сміє
// текти в амбієнт. Канон: 03_05 §2.1 (в) + §3.1.
static void Load_Broadcast_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_BCAST_KEY_ADDR;
    uint32_t key_or = 0;

    if (flash_ptr[0] == FLASH_BCAST_KEY_MAGIC) {
        for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
            key_or |= flash_ptr[1 + i];
        }
    }

    if (key_or != 0) {
        for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
            bcast_key[i] = flash_ptr[1 + i];
        }
        bcast_key_is_fallback = 0;
        return;
    }

    // Magic відсутній або ключ нульовий → fallback на session (KEYL).
    for (int i = 0; i < FLASH_BCAST_KEY_WORDS; i++) {
        bcast_key[i] = aes_key[i];
    }
    bcast_key_is_fallback = 1;
}
#endif

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

// [FW.23] Завантаження K_ota (per-cluster OTA HMAC key) з Protected Flash.
// Flash layout на FLASH_OTA_KEY_ADDR (0x0803E800, сторінка 125):
//   [FLASH_OTA_KEY_MAGIC:4]["KOTA"][k_ota[0]:4]...[k_ota[7]:4] = 4 + 32 = 36 байт
// Якщо magic відсутній/стертий або ключ нульовий — ota_hmac_key_valid=0:
// dual-gate ніколи не пройде Браму 2 ⇒ жоден OTA не запишеться (fail-safe;
// без ключа походження не довести). НЕ Error_Handler() — телеметрія й Lorenz
// працюють без K_ota; лише OTA-канал лишається замкненим до provisioning.
// Байтовий порядок дзеркалить backend OtaHmacKeyService (raw HKDF output, BE
// слова → байти), щоб Silken_Hmac_Sha256 видав ідентичний backend'у digest.
static void Load_Ota_Hmac_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_OTA_KEY_ADDR;

    // 1. Magic — чи K_ota записано при provisioning кластера
    if (flash_ptr[0] != FLASH_OTA_KEY_MAGIC) {
        ota_hmac_key_valid = 0;
        return;
    }

    // 2. Ключ не нульовий (magic є, але ключ порожній — corrupted provisioning)
    uint32_t key_or = 0;
    for (int i = 0; i < FLASH_OTA_KEY_WORDS; i++) {
        key_or |= flash_ptr[1 + i];
    }
    if (key_or == 0) {
        ota_hmac_key_valid = 0;
        return;
    }

    // 3. Копіюємо K_ota з Flash у RAM (big-endian byte order — як backend HMAC key)
    for (int i = 0; i < FLASH_OTA_KEY_WORDS; i++) {
        uint32_t word = flash_ptr[1 + i];
        ota_hmac_key[i * 4 + 0] = (uint8_t)(word >> 24);
        ota_hmac_key[i * 4 + 1] = (uint8_t)(word >> 16);
        ota_hmac_key[i * 4 + 2] = (uint8_t)(word >> 8);
        ota_hmac_key[i * 4 + 3] = (uint8_t)(word & 0xFF);
    }
    ota_hmac_key_valid = 1;
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
// [FW.30] Knuth-hash плейсхолдер + approx_days (Y*365+M*30 —
// без високосних) замінено повним контрактом SilkenNet::SeedDerivation:
//   epoch_day → HMAC-SHA256(K_seed, "init|" || epoch_day_be8) → signed-unit-float.
// Реалізація — pure-C silken_sha256.h / lorenz_seed.h, спільна з host-тестами;
// parity проти OpenSSL доведено у test_seed_derivation.c. mbedTLS для FW.30
// більше не потрібен (TODO закрито).
//
// epoch_day, пріоритетно:
//   1. soldier_unix_ts — UTC від Queen-маяка (FW.20), drift-компенсований
//      локальними тіками → збіг з backend-кандидатами today/yesterday (ARCH.41).
//      Саме цей шлях обіцяв коментар біля soldier_unix_ts, але стара
//      реалізація його ігнорувала.
//   2. Фолбек до першого маяка: RTC-календар через days_from_civil (точна
//      громадянська арифметика). RTC-default після VBAT-loss = 2000-01-01 →
//      epoch_day 10957 — бекенд тримає його кандидатом
//      FIRMWARE_RTC_DEFAULT_EPOCH_DAY у ARCH.41 time-sync recovery.
// [FW.49 S1] Єдине джерело wall-секунд: free-running RTC-календар (LSE йде
// у STOP2, на відміну від замороженого SysTick). До першого time-sync
// календар біжить від RTC-default 2000-01-01 — дельтам (delta_t) цього
// досить; абсолютним він стає, коли beacon-UTC записується у календар
// (Wall_Calendar_Set нижче). 0 = HAL-читання не вдалось (чесна відмова —
// викликачі мають baseline/fallback гілки). Кремнієва верифікація
// (LSE bring-up + MX_RTC_Init clock-tree) — bench, RUNBOOK §4.
static uint32_t Wall_Seconds_Now(void)
{
    RTC_TimeTypeDef t = {0};
    RTC_DateTypeDef d = {0};
    if (HAL_RTC_GetTime(&hrtc, &t, RTC_FORMAT_BIN) != HAL_OK) return 0u;
    // GetDate ОБОВ'ЯЗКОВО після GetTime — HAL розкриває shadow-регістри парою.
    if (HAL_RTC_GetDate(&hrtc, &d, RTC_FORMAT_BIN) != HAL_OK) return 0u;
    return Silken_Unix_From_Calendar((int32_t)d.Year + 2000, d.Month, d.Date,
                                     t.Hours, t.Minutes, t.Seconds);
}

// [FW.49 S1] Beacon-UTC → RTC-календар: відтепер wall-clock абсолютний, і
// epoch_day (SEC.11) переживає будь-який STOP2 без tick-екстраполяції.
// Best-effort: невдача запису не фатальна — legacy-шлях (unix_ts + tick)
// лишається фолбеком у Derive_Cold_Start_State.
static void Wall_Calendar_Set(uint32_t unix_ts)
{
    int32_t year; uint32_t month, day, hh, mm, ss;
    Silken_Civil_From_Unix(unix_ts, &year, &month, &day, &hh, &mm, &ss);
    if (year < 2000 || year > 2099) return; // RTC STM32 — 2000-based вікно

    RTC_TimeTypeDef t = {0};
    RTC_DateTypeDef d = {0};
    t.Hours = (uint8_t)hh; t.Minutes = (uint8_t)mm; t.Seconds = (uint8_t)ss;
    d.Year  = (uint8_t)(year - 2000); d.Month = (uint8_t)month; d.Date = (uint8_t)day;
    d.WeekDay = RTC_WEEKDAY_MONDAY; // RTC вимагає валідне поле; для unix-математики байдуже
    if (HAL_RTC_SetTime(&hrtc, &t, RTC_FORMAT_BIN) != HAL_OK) return;
    (void)HAL_RTC_SetDate(&hrtc, &d, RTC_FORMAT_BIN);
}

static void Derive_Cold_Start_State(float *x0, float *y0, float *z0)
{
    uint64_t epoch_day;
    uint32_t wall_now = Wall_Seconds_Now();

    if (wall_now != 0u && (Silken_Wall_Is_Utc(wall_now) || soldier_unix_ts == 0u)) {
        // Календар — головний timebase (sync пише його у Wall_Calendar_Set).
        // Незсинхований 2000-default дає epoch_day 10957+ — рівно той
        // кандидат, який бекенд тримає у Mitigation A (ARCH.41 recovery).
        epoch_day = Silken_Epoch_Day_From_Unix(wall_now);
    } else if (soldier_unix_ts != 0u) {
        // Sync був, але календар не взяв UTC (Set не вдався) — legacy
        // tick-екстраполяція (заморожена у STOP2 — відома вада; сервер
        // тримає кандидатів, 03_04 Mitigation A).
        uint32_t now_ts = soldier_unix_ts +
            ((HAL_GetTick() - soldier_unix_ts_local_tick) / 1000u);
        epoch_day = Silken_Epoch_Day_From_Unix(now_ts);
    } else {
        // Календар нечитабельний і синку не було: RTC-default кандидат —
        // бекенд упізнає його серед epoch_day-кандидатів recovery.
        epoch_day = 10957u; // 2000-01-01 (FIRMWARE_RTC_DEFAULT_EPOCH_DAY)
    }

    double dx = 0.0, dy = 0.0, dz = 0.0;
    Silken_Derive_Initial_State(lorenz_seed, epoch_day, &dx, &dy, &dz);

    // RTC Backup тримає float32 — звуження свідоме: біт-parity деривації
    // живе на рівні double; downstream-толеранс — FW.31 / docs/03_04.
    *x0 = (float)dx;
    *y0 = (float)dy;
    *z0 = (float)dz;
}

// Функція конфігурації апаратного AES (Створюється автоматично CubeMX)
// Post-ARCH.42 Variant B (2026-05-23): LoRa-канал на AES-128 (вибір; SE = SE050 — 03_05 §3.7).
// FW.2 target — `CRYP_AES_CCM` 28B wire-rev2 двофазним WL-флоу (B0 +
// HAL_CRYP_Encrypt + GenerateAuthTAG — lora_ccm.h); bench верифікує кремній
// проти OpenSSL (ccm_selftest, RM0461 §27.4).
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType = CRYP_DATATYPE_32B;
  hcryp.Init.KeySize = CRYP_KEYSIZE_128B; // ARCH.42 Variant B — AES-128 LoRa (вибір; SE = SE050 — 03_05 §3.7)
#if FW2_CCM_ENABLED
  // [FW.2 гейт (в)] Амбієнтний ECB CCM-ери = cluster-plane (KEYB): RX-decrypt
  // downlink'а Королеви + TX 0x55/0x56. Session (aes_key) живе ЛИШЕ всередині
  // CCM-скоупа (MX_CRYP_Init_CCM → Restore повертає сюди). 03_05 §2.1 (в).
  hcryp.Init.pKey = bcast_key;
#else
  hcryp.Init.pKey = aes_key;              // односхемна ECB-ера: один ключ на все
#endif
  hcryp.Init.Algorithm = CRYP_AES_ECB;    // ECB transitional → TARGET: CRYP_AES_CCM (FW.2)
  HAL_CRYP_Init(&hcryp);
}

// ============================================================================
// [FW.2 / ARCH.42 Variant B] AES-128-CCM 28-byte LoRa packet — freeze-contract
// ============================================================================
// Гілка вмикається `#define FW2_CCM_ENABLED 1` після hardware bench
// атестації CCM-двигуна (ccm_selftest KAT) на STM32WLE5JC. До flip — функції
// нижче не викликаються з production cycle (Build_LoRa_Payload + ECB
// продовжує жити), але host-тести у `firmware/test/test_ccm.c` верифікують
// логіку через mock HAL CCM (libcrypto-backed, той самий двофазний shape).
//
// Структура пакета, packing helpers, та RTC_BKP_DR15 layout — SSOT у
// `firmware/common/lora_ccm.h`. Тут лише: (a) CRYP_AES_CCM реконфігурація,
// (b) HAL_CRYPEx виклик, (c) RTC FC management через HAL_RTCEx_BKUPRead/Write.
#include "../common/lora_ccm.h"

// FW2_CCM_ENABLED визначений угорі, біля Flash-KV гейтів — FC high-water
// (TRL-7) вмикає спільний KV-mount, тож define мусить жити до нього.

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
// Reconfigure hcryp для CCM-режиму — WL-ІСТИННИЙ двофазний флоу (знахідка
// 2026-07-03: HAL_CRYPEx_AESCCM_Encrypt/Decrypt у WL-HAL НЕ існують, то
// F4/F7/L4-API; shape-дім — lora_ccm.h). Нонс живе всередині B0-блоку
// (Build_CCM_B0), AAD — окремим Header; Size обох фаз — у БАЙТАХ
// (DataWidthUnit=BYTE), DataType=8B — байтопотік без word-swap
// двозначностей (32B-swap клас ловить ccm_selftest KAT на bench).
// Після CCM-операції ОБОВ'ЯЗКОВО MX_CRYP_Init() (ECB restore) + занулити
// B0/Header — інакше в Init лишаються вказівники на мертвий стек-фрейм.
static void MX_CRYP_Init_CCM(uint32_t *b0_4w, uint32_t *aad_2w)
{
    hcryp.Init.Algorithm       = CRYP_AES_CCM;
    hcryp.Init.DataType        = CRYP_DATATYPE_8B;
    // [FW.2 гейт (в)] CCM = session per-device (KEYL): телеметрія/panic — то
    // money-path, ізольований per-device; амбієнт-ECB натомість живе на
    // cluster-plane KEYB (MX_CRYP_Init). Явний pKey тут ОБОВ'ЯЗКОВИЙ —
    // успадкований амбієнт дав би bcast_key, і Rails (per-DID lookup)
    // MIC-fail'ив би кожен кадр.
    hcryp.Init.pKey            = aes_key;
    hcryp.Init.B0              = b0_4w;
    hcryp.Init.Header          = aad_2w;
    hcryp.Init.HeaderSize      = FW2_CCM_AAD_LEN;
    hcryp.Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_BYTE;
    hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_BYTE;
    HAL_CRYP_Init(&hcryp);
}

// Гігієна після CCM: ECB-контекст назад (дисципліна Restore_ECB_Mode) і
// жодного висячого вказівника у Init — B0/Header жили на стеку викликача.
// Width-unit'и ОБОВ'ЯЗКОВО назад у WORD: MX_CRYP_Init їх не чіпає, а
// production-ECB передає Size у словах — липкий BYTE зламав би decrypt.
// [FW.2 (в)] Вкладений MX_CRYP_Init повертає й КЛЮЧ: session (aes_key)
// скоупований CCM-фазою, амбієнт знову cluster-plane (bcast_key) — RX-вікно
// Фази 4.5 декриптує downlink Королеви правильним ключем автоматично.
static void MX_CRYP_Restore_From_CCM(void)
{
    hcryp.Init.B0              = NULL;
    hcryp.Init.Header          = NULL;
    hcryp.Init.HeaderSize      = 0;
    hcryp.Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_WORD;
    hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_WORD;
    MX_CRYP_Init();
}

// Load / Save Frame Counter to RTC_BKP_DR15.
// Returns the current FC (post-load, post-reseed if cold-boot).
static uint32_t Load_Frame_Counter(void)
{
    uint32_t packed = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR15);
    uint32_t fc = Unpack_FW2_Frame_Counter(packed);
    if (fc == 0) {
        // Холодний старт після втрати VBAT: вічна пам'ять стерта, магія DR15
        // згасла. Першим словом озивається Flash-якір [FW.2 TRL-7]: межа з
        // KV-ключа 0x14 строго вища за все, що цей вузол будь-коли передав
        // (інваріант I-HW, fc_hiwater.h) → рестарт з неї монотонний без
        // жодної ентропії. Floor законний ЛИШЕ разом з негайним просуванням
        // межі (атомарність: повторний brownout до наступного КЕНОЗИСУ
        // інакше стартував би з того самого floor і повторив nonce).
#if FW2_CCM_ENABLED
        uint32_t floor_fc = fc_hiwater_cache;
        if (floor_fc != 0 && soldier_kv_mounted &&
            Fc_Hiwater_Advance(&soldier_kv, Fc_Hiwater_Target(floor_fc),
                               &fc_hiwater_cache)) {
            fc = floor_fc; // перший TX = floor+1 > усіх переданих
            HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR15, Pack_FW2_Frame_Counter(fc));
            return fc;
        }
#endif
        // Якоря нема (перше втілення / Flash відмовив) → пересіваємо
        // рівномірно-випадковим зерном — стара імовірнісна політика, чесна
        // деградація (MEDIUM): docs/03_05 §2.1 (КАНОНІЧНЕ ДЖЕРЕЛО — FW.2
        // FC/nonce). HRNG з трьома спробами; кволого HAL_GetTick fallback
        // НЕМАЄ — на холодному старті tick дрібний і вгадуваний,
        // кластеризується між cold-boot'ами того ж вузла (саме там і
        // причаївся б повтор nonce).
        uint32_t hrng_word = 0;
        for (int i = 0; i < 3 && hrng_word == 0; i++) {
            if (HAL_RNG_GenerateRandomNumber(&hrng, &hrng_word) != HAL_OK) hrng_word = 0;
        }
        // Остання межа, лише якщо HRNG зовсім мертвий: підмішуємо per-device DID,
        // щоб зерно різнилося між вузлами (ламає крос-девайс кластеризацію);
        // залишковий ризик повтору приймаємо свідомо (див. SSOT).
        if (hrng_word == 0) hrng_word = tree_did ^ HAL_GetTick();
        fc = Reseed_FW2_Frame_Counter(hrng_word);
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR15, Pack_FW2_Frame_Counter(fc));
    }
    return fc;
}

static void Save_Frame_Counter(uint32_t fc_24bit)
{
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR15, Pack_FW2_Frame_Counter(fc_24bit));
}

// Зібрати повний 30-байтний CCM LoRa-пакет (wire-rev2.1) та просунути
// лічильник кадрів. Успіх: out_packet[0..29] — готовий до ефіру, HAL_OK.
// Збій HAL_CRYPEx: повертає HAL_ERROR — TX заборонено, лічильник не рухаємо.
//
// Нові поля rev2/rev2.1 (джерела на боці викликача при фліп-вшиванні):
//   device_z   — Pack_FW2_Device_Z(lorenz_z, lorenz_state_valid): сирий Z
//                для FW.31 numeric DCI (сентинель NONE коли Лоренц спав)
//   diag       — Pack_FW2_Diag(tinyml_threshold_invalid_count, fauna_mode,
//                fauna_skip, fc_hiwater_degraded)
//   vpd_index  — 0x00 до приходу BME280 (HW.32)
//   gossip_ts_lsb — Soldier_Pack_Gossip_Ts_Byte(soldier_unix_ts): їде у
//                cleartext-AAD, сусіди читають без ключа (FW.20-S2 #5)
//   ema_delta_t_s — [E.63 (г)] wire_ema_delta_t_s: САМЕ те число, що пішло
//                у metabolic_health цього циклу (контракт «wire = вхід GP»)
int Soldier_Build_CCM_LoRa_Packet(
    uint32_t did, uint16_t vcap_mv, int8_t temp_c, uint8_t acoustic,
    uint16_t delta_t_s, uint8_t status_byte, uint8_t mesh_ctrl,
    uint16_t device_z, uint8_t diag, uint8_t vpd_index, uint8_t gossip_ts_lsb,
    uint16_t ema_delta_t_s,
    uint8_t out_packet[FW2_CCM_AIR_PACKET_LEN])
{
    uint32_t fc = Load_Frame_Counter();
    // Насичений інкремент: magic DR15 (0x46) живий, значення у 24-бітному вікні.
    // Нуль обходимо — він би вбив magic-перевірку при наступному boot.
    uint32_t next_fc = (fc + 1u) & FW2_FC_VALUE_MASK;
    if (next_fc == 0u) next_fc = FW2_FC_HRNG_MIN;

    // [FW.2 TRL-7] Сторожа межі (інваріант I-HW, fc_hiwater.h): за
    // дисципліни КЕНОЗИС-advance (запас MARGIN) сюди не заходимо ніколи —
    // це останній рубіж, коли Flash відмовляв багато циклів поспіль.
    // Energy-gate: один dw-program дозволяємо лише при заряді, якого
    // вистачає й на RX-вікно (vcap_mv — мВ, конверсія на боці викликача).
    // Відмова → TX усе одно (телеметрія дорожча за теоретичний replay),
    // але інваріант чесно позначається втраченим до наступного advance.
    // (Гейт окремий від HAL_MOCK_CCM_ENABLED: host-мок живе без Flash-KV.)
#if FW2_CCM_ENABLED
    if (fc_hiwater_cache != 0 && next_fc >= fc_hiwater_cache) {
        if (!soldier_kv_mounted || vcap_mv < VCAP_LISTEN_THRESHOLD ||
            !Fc_Hiwater_Advance(&soldier_kv, Fc_Hiwater_Target(next_fc),
                                &fc_hiwater_cache)) {
            fc_hiwater_degraded = 1;
        }
    }
#endif

    // Word-aligned плоть: STM32 CRYP HAL споживає uint32_t* — байтові
    // масиви на стеку такого вирівнювання не обіцяють. Розмір — заокруглення
    // ВГОРУ до слова (rev2.1: PT=14 Б → 4 слова; цілочисельне /4 дало б 3
    // і зрізало б хвіст EMA-поля).
    uint32_t aad_w[FW2_CCM_AAD_LEN / 4];
    uint32_t b0_w[FW2_CCM_B0_LEN / 4];
    uint32_t pt_w[(FW2_CCM_PLAINTEXT_LEN + 3u) / 4];
    uint32_t ct_w[(FW2_CCM_PLAINTEXT_LEN + 3u) / 4];
    uint32_t tag_w[4]; // 16B: WL HAL пише повний блок, MIC = перші 8 байт

    Build_CCM_AAD(did, gossip_ts_lsb, next_fc, (uint8_t *)aad_w);
    Build_CCM_B0(did, next_fc, (uint8_t *)b0_w); // нонс живе всередині B0
    Pack_CCM_Sensor_Payload(vcap_mv, temp_c, acoustic, delta_t_s,
                            status_byte, mesh_ctrl,
                            device_z, diag, vpd_index, ema_delta_t_s,
                            (uint8_t *)pt_w);

    // Двофазний WL-флоу: payload-фаза → тег-фаза (invocation shape — lora_ccm.h).
    MX_CRYP_Init_CCM(b0_w, aad_w);
    int status = HAL_CRYP_Encrypt(&hcryp, pt_w, FW2_CCM_PLAINTEXT_LEN, ct_w, 1000);
    if (status == HAL_OK) {
        status = HAL_CRYPEx_AESCCM_GenerateAuthTAG(&hcryp, tag_w, 1000);
    }
    // Відновлюємо ECB-режим негайно — LoRa control-frames чекають свого ключа.
    MX_CRYP_Restore_From_CCM();
    if (status != HAL_OK) {
        return HAL_ERROR; // Збій шифрування — лічильник кадрів не просуваємо.
    }

    // Складаємо пакет до ефіру: AAD-заголовок || шифротекст || MIC-печатка.
    memcpy(&out_packet[0], aad_w, FW2_CCM_AAD_LEN);
    memcpy(&out_packet[FW2_CCM_AAD_LEN], ct_w, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&out_packet[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN],
           tag_w, FW2_CCM_MIC_LEN);

    Save_Frame_Counter(next_fc);
    return HAL_OK;
}
#endif // FW2_CCM_ENABLED || HAL_MOCK_CCM_ENABLED

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
