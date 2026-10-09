/* USER CODE BEGIN Header */
// SPDX-License-Identifier: AGPL-3.0-or-later
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Прошивка вузла Silken Net (Стан Нульового Лагу + DID + Directed Mesh)
  * @processor      : STM32WLE5CC (node board, UFQFPN48; the bench runs the same image on the
  *                  STM32WLE5JC inside LoRa-E5 — same core and radio, pins differ, 03_01 Pinout)
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
#include "../common/lora_phy.h"      // [FW.61] базлайн модуляції raw-LoRa P2P (One-Home)
#include "../common/cad_sniff.h"     // [ARCH.26 L3] CAD-нюх + PANIC-преамбула (One-Home)
#include "../common/tx_defer.h"      // [FW.10] зимовий кенозис TX: Should_Defer_TX (One-Home)
#include "../common/acoustic_ledger.h" // [ARCH.102] ледж акустики: споживає лише доставлене (One-Home)
#include "../common/ota_seal.h"       // [FW.23] Ed25519-печатка OTA: розбір трейлера + вердикт (One-Home з host-тестами)
#include "../common/ota_rerequest_wire.h" // [FW.27-B · FW.68] зойк 0x55: розкладка й будівники (One-Home з Королевою й host-тестами)

// Підключаємо низькорівневий драйвер радіо (Radio Middleware)
#include "radio.h"
// [FW.61] Шов базлайну модуляції у драйвер (потребує radio.h — тому тут,
// а не поруч із pure-заголовками вище; сам lora_phy.h лишається pure).
#include "../common/lora_phy_apply.h"
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
// [FW.23] Трейлер печатки OTA (маркер 0x9B, 6 сегментів підпису + версія) — формат і
// константи живуть у ../common/ota_seal_wire.h, перевірка — у ../common/ota_seal.h.
#define OTA_MISMATCH_RESET_THRESHOLD 3       // [FW.53] N поспіль чужих total → відпустити мертву кампанію
// Мітка помилки mruby VM на дроті: [panic:0|status:11=vm_error|growth:00000].
// [FW.29] Було 0xFF — після FW.29-маски (&~0x80) ставало 0x7F =
// status=3 + growth_points 31 → бекенд (×2) карбував 62 бали за КОЖЕН error-пакет.
// 0x60 переживає маску незмінним і чесно каже: довіри нема, емісії нема.
// [SLASH-1] status=3 — це НАШ софт-збій, не tamper: бекенд декодує його як
// vm_error → firmware_fault (ops-тріаж); фізичний tamper — PANIC_FLAG, не статус-біти.
#define BIO_STATUS_VM_ERROR       0x60
#define VCAP_LISTEN_THRESHOLD     2800       // Поріг напруги для прослуховування ефіру (мВ)
// [FW.49 S1] delta_t — wall-секунди з RTC-календаря (LSE йде у STOP2);
// заморожений HAL_GetTick міряв лише active-час → m(delta_t) ≈ максимум
// у ВСІХ дерев → over-mint Proof-of-Growth. Guard-пороги дельти:
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
// мусить пережити reset (RAM-слід згорів би разом зі стеком). Гасить його
// wire-винос: три best-effort постріли event-кадру 0x57 (device_event.h),
// після третього Фаза 5 пише DR0[10]=0; доти — sticky, видимий і SWD'ом.
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

// ⚖️ [FW.23, founder 2026-10-05/06] ПУБЛІЧНИЙ Ed25519-ключ печатки OTA кластера. Окрема
// Protected Flash сторінка 125 (0x0803E800, одразу після per-device key-сторінки 124),
// бо ключ — per-КЛАСТЕР, тоді як LoRa AES-key — per-DEVICE: заміна стирає СВОЮ сторінку,
// не чіпаючи per-device ключі. Сторінка 125 = канонічний «буфер росту key-блоку»
// (03_01 §2.3). Factory Flashing пише публічний ключ пари, чий seed =
// HKDF-SHA256(master, salt="cluster:<id>", info="silken-ota-ed25519-v1"); приватний
// ключ вузла не покидає бекенд. Доти тут лежав симетричний K_ota (magic "KOTA"), і
// витягнутий вузол підписував контракт для всього кластера; новий magic — версія
// формату: стара прошивка не прочитає ключ як K_ota, нова — K_ota як ключ.
// Якщо magic відсутній — ota_seal_pubkey_valid=0: вузол НЕ застосує жоден OTA (fail-
// safe — без ключа нема як довести походження). НЕ Error_Handler() (телеметрія
// й Lorenz працюють без нього). Канон: docs/03_06 §4.
#define FLASH_OTA_KEY_ADDR        0x0803E800UL  // Сторінка 125 — за per-device key-сторінкою
#define FLASH_OTA_PUBKEY_MAGIC    0x4B505542UL  // "KPUB" — OTA seal public key magic marker

// [FW.2 гейт (в), двоключова модель] Cluster control-plane ключ (KEYB) —
// спільний AES-128 всього кластера для ВСЬОГО, що не є телеметрією/panic:
// downlink-broadcast Королеви (0x99/0x9B/0x9C — один TX на
// всіх → один ключ by construction) + uplink-запити 0x55/0x56 (Королева
// читає їх сама, session-ключів вона не тримає — 03_05 §3.1). Телеметрія й
// panic натомість їдуть CCM'ом на per-device session-ключі (KEYL вище).
// Сторінка 125 = cluster-membership (KPUB+KEYB): переїзд дерева між
// кластерами стирає/пише ЛИШЕ її, per-device identity (стор. 124) живе.
// Зсув +40, не +36: KPUB займає 36 Б, а WL програмує Flash 64-бітними
// doubleword'ами — старт KEYB у другій половині недописаного dw
// спричинив би ECC-fault при фабричному -w32. Деривація —
// HKDF(master, "cluster:<id>", "silken-aes-128-broadcast-key") — дзеркало
// HardwareKeyService.derive_broadcast_key; ротація = re-provision (як
// ключ печатки OTA; FW.17-ратчет цього ключа СВІДОМО не торкається). Канон: 03_05 §2.1
// flip-checklist (в) + §3.1.
#define FLASH_BCAST_KEY_ADDR      (FLASH_OTA_KEY_ADDR + 40)  // після KPUB (36 Б) + dw-паддінг
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
uint8_t acoustic_events = 0;           // З HW.30 (пʼєзо зрізано) не інкрементується — 0; CCM-байт віддає wire-rev2.2 — реалізація FW.66 (03_05 §2.1)
uint32_t last_wakeup_timestamp = 0;    // Час попереднього пробудження
uint32_t delta_t_seconds = 0;          // Швидкість заряду іоністора (Метаболізм)
uint32_t tree_did = 0;                 // Decentralized Identity (Гаманець Дерева)

// [SEC.10] Лічильник panic-кадрів — пакується у DR0[31:16] поряд з
// acoustic_events у DR0[7:0]; решта бітів DR0 — за картою 03_01 §2, тут не
// дублюється (дубль уже раз протух і заходив на чужий біт). Сторожовий пес
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

uint8_t ota_vm_error_streak       = 0;   // [SEC.20] DR0[9:8]-persist: N поспіль bytecode-збоїв → fallback
uint8_t canary_tripped            = 0;   // [SEC.21] DR0[10]-persist: слід __stack_chk_fail з минулого втілення
uint8_t canary_evt_shots          = 0;   // [SEC.21] залишок 0x57-пострілів (RAM — живе крізь STOP2)
uint16_t canary_evt_seq           = 0;   // [SEC.21] per-boot seq 0x57 (дедуп Rails SETNX)
// [SEC.20] Wire-звіт contract-стану (fw_report.h): рахується раз на boot у
// contract-select. Дефолт = legacy C-image константа (semantic=0) — чесна
// деградація, доки KV/contract не оглянуті.
uint16_t fw_contract_report       = FIRMWARE_VERSION_ID;

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

// [FW.23] Ed25519-печатка OTA — 64-байтний підпис, що надходить після тіла прошивки
// у 7-ми 16-байтних LoRa-блоках з маркером 0x9B: seg 1..6 несуть підпис (11 байт на
// блок, seg 6 — 9 байт + PAD), seg 7 — version_id (BE). Бітмаска
// ota_seal_segments_received: біти 0..5 = печатка, біт 6 = версія. Усі 7 блоків
// (== OTA_SEAL_ALL_RECEIVED 0x7F) ⇒ є і підпис, і version_id, що входить у підписане.
uint8_t  received_ota_seal[OTA_SEAL_SIG_BYTES] = {0};
uint8_t  ota_seal_segments_received = 0;        // Bitmask seg 1..6 + version (біт 6)
uint32_t received_ota_version = 0;              // [FW.23] version_id з seg_idx=7 (частина підписаного)

// [FW.23] Публічний Ed25519-ключ печатки OTA кластера (слот "KPUB", стор. 125).
// Завантажується з Protected Flash через Load_Ota_Seal_Pubkey() при boot.
// ota_seal_pubkey_valid==0 (не provisioned) ⇒ жоден OTA не застосовується (fail-safe).
uint8_t  ota_seal_pubkey[OTA_SEAL_PUBKEY_BYTES] = {0};
uint8_t  ota_seal_pubkey_valid = 0;

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
// state (як soldier_unix_ts): гине з SRAM у RTC-only сні (клас Standby, 00_07 FW.54) / VBAT-loss і
// відновлюється наступним маяком (≤15 хв) — RTC DR і Flash-KV не потрібні
// (бюджет DR повний, 03_01 §2). Гейт INERT: фліп = bench WUT-армінг
// (SEC.15/FW.49); математика вікон/слотів — common/tdma_schedule.h.
#ifndef ARCH26_TDMA_ENABLED
#define ARCH26_TDMA_ENABLED       0
#endif
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
// [FW.61] Власних LORA_PANIC_{SF,BW,CR,TX_POWER} тут БІЛЬШЕ НЕМА — PANIC їде
// базлайном `lora_phy.h` і відрізняється від звичайного TX рівно ОДНИМ
// аргументом: преамбулою. Доти це була окрема четвірка, яка дорівнювала
// канону ВИПАДКОВО, і саме вона робила «часткове відновлення» схожим на повне
// (`firmware`-скіл гоча #1, нога «в»).
static uint32_t g_last_cad_sniff_wall = 0u;  // RAM-only маркер (як g_tdma_schedule)
volatile uint8_t g_cad_activity = 0u;        // ставить OnCadDone; читач = bench
                                             // WUT-цикл «нюх-замість-RX» (RUNBOOK)
#endif

// [FW.8] CMD_SET_THRESHOLDS (0x9A) — пер-деревні Z-пороги Лоренца. З
// downlink-ревізії (03_05 §2.5, 2026-09-29) — адресна команда під CCM
// сесійним ключем цього вузла (../common/downlink_ccm.h), тіло 8 Б:
//   [z_min_x100:s16le][z_max_x100:s16le][z_opt_x100:s16le]
//   [species_id:u8][config_version:u8]
// Цілісність несе MIC (CRC старого каркаса знято); розпаковка й інваріанти —
// Lorenz_Thresholds_From_Wire (../common/lorenz_thresholds.h).
//
// ⚫ СТАТУС: FW.8 поглинуто гілкою (Б) 2026-10-06 (00_07 FW.66) — фліпу не буде,
// тракт знімає реалізація (Б); доти він тут як є. Приймач — спільний CCM-шлях адресних
// команд (секція 1.14: вікно відкриває, КЕНОЗИС застосовує) за гейтом
// `FW8_PARSER_ENABLED`, за замовчуванням ВИМКНЕНИЙ. Відправник у Rails —
// Downlink::ThresholdBand за ENV-гейтом FW8_THRESHOLDS_DOWNLINK_ENABLED
// (default off; порядок «ПІСЛЯ фліпу» ⚖️ 2026-09-29 — історія ECB-ери, 03_04 §5.3).
//
// ПРИЧИНА defer: із 20 RTC Backup Register'ів (DR0..DR19) після FW.2
// freeze-contract (DR15 → CCM Frame Counter) вільний лише DR7 (FW.54) — одне
// 32-бітне слово, а 8-байтний body порогів туди не вміщається без Flash-KV. Повна розкладка
// — SSOT 03_01 §2 (Canonical Backup Map), тут НЕ дублюємо.
//
// Альтернативи відкинуто:
//   • Flash sector — 2 KB на 8 байт, wear ~10k erase × at-most-daily re-send
//     дає 27 років, але erase ~30 мс блокує LoRa RX → конфлікт з anti-pingpong
//     RX-вікном після TX. Механічна підстава лишається чинною.
//     ⛔ Друга підстава — «на TRL-6 нічого не змінює, всі види на однакових
//     firmware-defaults» — СПРОСТОВАНА власними сідами (`db/seeds.rb`: сосна
//     `critical_z_min` 5.0, дуб 8.0/40.0 проти firmware-дефолтів 2.0/45.0).
//     Не відроджувати її як аргумент відкладення: види РОЗХОДЯТЬСЯ вже сьогодні.
//   • RAM-only з re-send щодня × 100k дерев = ~5% всього NB-IoT downlink
//     заради no-op feature. Чесніше відкласти.
//
// ВІДНОВЛЕННЯ: єдиний вільний регістр (DR7) тіла не вміщає, тож FW.8
// повертається через Flash-KV overflow (03_01 §2.3), а не звільнений регістр.
// Persist-логіка ✅ host-готова: ../common/lorenz_thresholds.h — Save/Load на
// ключах 0x10/0x11 (порвана/невалідна пара → дефолти; power-cut тести у
// test_flash_kv.c). Mount KV + HAL_FLASH глю ✅ написано (секція FW.17 нижче,
// спільний гейт `FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED`). Wiring
// Save/Load ✅ написано за цим же гейтом: boot-restore після mount'а,
// КЕНОЗИС-write по dirty-флагу прийнятого 0x9A. Фліпу `FW8_PARSER_ENABLED 1`
// не буде (FW.8 ⚫ 2026-10-06) — цей тракт знімає реалізація (Б).
#ifndef FW8_PARSER_ENABLED
#define FW8_PARSER_ENABLED                0  // ⚫ FW.8 — не фліпати (див. блок вище)
#endif
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
// 🟡 СТАТУС: гілка ВИМКНЕНА (FW17_RATCHET_ENABLED 0) — фліп після FW.2 CCM
// (grace закриває MIC аплінку — #error нижче). 0x9E приходить лише спільним
// CCM-шляхом адресних команд (03_05 §2.5, секція 1.14): MIC сесійним ключем
// цього вузла + DID + DLFC, тож, маючи кластерний KEYB, ротацію більше не
// підробити. Другий передзамок — Flash-KV mount: ключ перемикається лише
// ПІСЛЯ запису версії (Key_Ratchet_Commit), тож без KV вузол не ротується
// взагалі — лишається на старому ключі, а бекенд тримає grace.
// Канон: 03_05 §3.8; реєстр KV-ключів — 03_01 §2.3.1.
#include "../common/key_ratchet.h"
#include "../common/flash_kv.h"

#ifndef FW17_RATCHET_ENABLED
#define FW17_RATCHET_ENABLED   0      // 🟡 фліп після FW.2 CCM + KV mount (bench)
#endif
#define FW17_KV_KEY_VERSION    0x13u  // Flash-KV: [rsv:16 | version:16] — версія в молодших бітах (03_01 §2.3.1)

// [ARCH.28 шлях A] Flash-KV журнал: сторінки 122-123 (freeze-contract
// 03_01 §2.3; ключ OTA тому переїхав на сторінку 125 — первісний 0x0803D000
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

// [FW.54] Ціль сну — Standby з RTC на LSE без утримання SRAM2 (⚖️ founder 2026-10-05; 03_01 §1.10,
// 02_03 §9.8). До фліпу прошивка спить у STOP2. Фліп чекає ТРЬОХ речей, а не стенда лише:
//   (1) ⚖️ RAM-стану FW.54 — у Standby гине весь SRAM, тож RAM-only лічильники пробуджень
//       (wakeups_since_*, ota_silent_wakeups) і soldier_unix_ts щопробудження стартували б з нуля:
//       grace холодного старту не дораховувався б ніколи, і прохання синхронізації (0x56) замовкло б
//       (живий набір групи C — 03_01 §2.3.1);
//   (2) пін-мапи ключів навантажень (.ioc, 00_07 FW.46) — без неї Standby_Load_Pulls порожній;
//   (3) виміряного сну на стенді (RUNBOOK 3.1).
// #ifndef — щоб compile-lane hal_check_ccm збирав гілку `-DFW54_STANDBY_ENABLED=1` проти WL-HAL.
#ifndef FW54_STANDBY_ENABLED
#define FW54_STANDBY_ENABLED  0  // 🟡 фліп — три умови вище (00_07 FW.54)
#endif
#include "../common/standby_wake.h"
#if FW54_STANDBY_ENABLED
static uint8_t soldier_woke_from_standby = 0;   // споживач — відновлення за ⚖️ RAM-стану (умова 1)
static void Standby_Load_Pulls(void)
{
    // Кожен ключ навантаження → HAL_PWREx_EnableGPIOPullDown(PWR_GPIO_<порт>, PWR_GPIO_BIT_<n>):
    // у Standby GPIO рівня не тримає, ключ тримає лише pull PWR. Пін-мапа — .ioc (00_07 FW.46, умова 2).
}
static void Standby_Pull_Config(void)        { HAL_PWREx_EnablePullUpPullDownConfig(); }   // APC = 1
static void Standby_No_Sram_Retention(void)  { HAL_PWREx_DisableSRAMRetention(); }        // RRS = 0
static void Standby_Clear_Wakeup(void)       { __HAL_PWR_CLEAR_FLAG(PWR_FLAG_WU); }
static void Standby_Enter_Hw(void)           { HAL_PWR_EnterSTANDBYMode(); }
static const SilkenStandbyOps g_standby_ops = {
    Standby_Load_Pulls, Standby_Pull_Config, Standby_No_Sram_Retention, Standby_Clear_Wakeup, Standby_Enter_Hw
};
#endif
// [FW.17] Ратчет живий лише з CCM: в ECB-ері LoRa-шар знімає Королева, Rails
// ключа вузла не бачить, тож grace ротації не закрилось би ніколи, а 0x9E
// перевидавався б на кожному poll'і (03_05 §3.8).
#if FW17_RATCHET_ENABLED && !FW2_CCM_ENABLED
#error "[FW.17] FW17_RATCHET_ENABLED потребує FW2_CCM_ENABLED"
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

// [FW.2 гейт (в), двоключова модель] Cluster control-plane ключ (KEYB,
// стор. 125) — амбієнтний ECB-ключ ОБОХ ер: RX-decrypt усього downlink'а +
// TX 0x55/0x56 (Королева читає їх сама — session-ключів вона не тримає).
// CCM-ера: телеметрія й panic беруть session (aes_key) всередині
// Soldier_Build_CCM_LoRa_Packet. ECB-ера: на KEYB їде й вона — ECB-шар знімає
// Королева своїм єдиним ключем, а конвеєр кладе їй у KEYL-слот саме значення
// KEYB. До 2026-09-28 бойовий білд брав амбієнтом KEYL, тож пара, провіжнута
// конвеєром, не мала звʼязку взагалі. Ціна — +17 Б .bss бойового білда.
// Канон: 03_05 §3.1.
uint32_t bcast_key[4] = {0};
uint8_t  bcast_key_is_fallback = 0; // 1 = KEYB-слот порожній → живемо на KEYL
                                    // (bench-плата, прошита до KEYB-ери)

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
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
#ifndef FW20_MESH_RELAY_ENABLED
#define FW20_MESH_RELAY_ENABLED 0
#endif
// [FW.17 · 03_05 §2.5] Приймач адресних команд Rails → Солдат (0x9A · 0x9E)
// — лише CCM сесійним ключем цього вузла; ECB-шлях їх не приймає
// взагалі (живий приймач під кластерним KEYB = підробка на весь кластер).
// Живий, коли живий бодай один опкод; DLFC — Flash-KV 0x12 (секція 1.14).
#define DL_CCM_RX_ENABLED (FW8_PARSER_ENABLED || FW17_RATCHET_ENABLED)
// [SEC.20] Anti-rollback — перший НЕ-gated споживач journal Flash-KV: база
// (ops+mount+compact) мусить жити НЕЗАЛЕЖНО від фліп-гейтів фіч (OTA живий завжди).
#define SEC20_OTA_ANTIROLLBACK_ENABLED 1
// [SEC.20 · ARCH.28] Один вираз бази журналу на ТРИ сайти — оголошення,
// mount, compact. Новий споживач Flash-KV дописується СЮДИ, а не в окремий
// сайт: сайт, що відстав, мовчки лишить журнал без ущільнення, і після
// ~254 APPLY high-water замерзне — анти-rollback обернеться на replay-downgrade.
#define FLASH_KV_BASE_ENABLED (FW17_RATCHET_ENABLED || FW8_PARSER_ENABLED || DL_CCM_RX_ENABLED || FW2_CCM_ENABLED || FW20_MESH_RELAY_ENABLED || SEC20_OTA_ANTIROLLBACK_ENABLED)
#if SEC20_OTA_ANTIROLLBACK_ENABLED && !FLASH_KV_BASE_ENABLED
#error "[SEC.20] anti-rollback живе на журналі Flash-KV — FLASH_KV_BASE_ENABLED мусить містити SEC20_OTA_ANTIROLLBACK_ENABLED"
#endif
#if DL_CCM_RX_ENABLED && !FLASH_KV_BASE_ENABLED
#error "[FW.17] DLFC адресних команд живе на журналі Flash-KV — FLASH_KV_BASE_ENABLED мусить містити DL_CCM_RX_ENABLED"
#endif
#include "../common/beacon_dedup.h"

#if FW20_MESH_RELAY_ENABLED
static BeaconDedup beacon_dedup; // RAM-кеш журналу; істина — Flash-KV 0x20
#endif

#if FLASH_KV_BASE_ENABLED
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
#endif // FLASH_KV_BASE_ENABLED

#if FW17_RATCHET_ENABLED
static void MX_CRYP_Init(void); // повний прототип нижче — потрібен re-key'ю

static uint16_t lora_key_version        = 0; // RAM-копія; істина — Flash-KV 0x13
static uint16_t lora_key_target_version = 0; // ціль 0x9E, що чекає на коміт
static uint8_t  lora_key_version_dirty  = 0; // коміт у КЕНОЗИСІ, не під RX-вікном

// Персист для Key_Ratchet_Commit: версія — у Flash-KV 0x13 (03_01 §2.3.1).
static int Soldier_Persist_Key_Version(void *ctx, uint16_t version)
{
    (void)ctx;
    return FlashKv_Put32(&soldier_kv, FW17_KV_KEY_VERSION, (uint32_t)version);
}

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
    MX_CRYP_Init(); // амбієнт лишається KEYB; K_v бере лише CCM-скоуп (MX_CRYP_Init_CCM ставить pKey явно)
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

// =====================================================================
// === 1.12. FW.27-B · FW.68 Magic Re-Request — голос Солдата у бік Королеви ===
// =====================================================================
// Розкладка зойку 0x55 і будівники (тіло · сентинел печатки) — спільні з Королевою й
// host-тестами: ../common/ota_rerequest_wire.h. Коли саме зойкати — Фаза 4.5.

// =====================================================================
// === 1.13. FW.23 Печатка OTA (Ed25519) перед Flash ====================
// =====================================================================
// Розбір трейлера — Ota_Seal_Parse_Chunk (../common/ota_seal_wire.h); вердикт
// фіналізації (CRC32 · magic "RITE" · Ed25519-печатка ключем кластера) —
// Ota_Seal_Try_Finalize (../common/ota_seal.h). Обидва pure і спільні з host-тестом
// (firmware/test/test_soldier_logic.c), тож тест судить цей код, а не копію.
// ⚖️ founder 2026-10-05/06: печатка асиметрична — вузол тримає лише публічний ключ;
// доти тут жили HMAC-трейлер і K_ota, однакові на кожному вузлі кластера.

// [FW.23] Повне скидання збірки OTA — тіло, печатка, версія, лічильники.
// Єдине джерело: і deadlock-guard (чужий total), і успіх/відмова фіналізації
// кличуть його, щоб жодне поле (зокрема received_ota_version) не лишилось
// «брудним» між кампаніями.
static void Reset_Ota_Assembly(void) {
    memset(ota_chunk_received, 0, sizeof(ota_chunk_received));
    memset(received_ota_seal, 0, sizeof(received_ota_seal));
    received_ota_version       = 0;
    ota_chunks_received        = 0;
    ota_bytes_received         = 0;
    ota_total_chunks           = 0;
    ota_seal_segments_received = 0;
    ota_last_chunk_rx_tick     = 0;
    ota_total_mismatch_streak  = 0;
}

// =====================================================================
// === 1.14. [FW.17 · 03_05 §2.5] Адресні команди Rails → Солдат (CCM) ===
// =====================================================================
// 0x9A пороги Лоренца (FW.8) · 0x9E ротація ключа (FW.17) підписує Rails
// сесійним ключем САМЕ цього вузла; кадр і його відкриття —
// ../common/downlink_ccm{,_open}.h. Два такти, як у ратчета:
//   RX-вікно — лише відкриття (MIC, DID, DLFC); стан не змінюється;
//   КЕНОЗИС  — зміст, потім дія, і лише після її успіху DLFC у Flash-KV
//              (⚖️ 2026-09-29, at-least-once): невалідне тіло лічильника не
//              палить, а струм, що зник між дією й DLFC, дає повтор, не втрату.
#if DL_CCM_RX_ENABLED
#include "../common/downlink_ccm_open.h"

static uint32_t dl_last_dlfc   = 0; // RAM-кеш; істина — Flash-KV 0x12 (0 = жодної)
static uint8_t  dl_cmd_pending = 0; // відкрито у вікні, чекає КЕНОЗИСУ
static uint8_t  dl_cmd_op      = 0;
static uint32_t dl_cmd_dlfc    = 0;
static uint32_t dl_dlfc_settle = 0; // DLFC команди, чий ефект ще не в журналі; 0 = немає
static uint8_t  dl_cmd_body[DL_CCM_BODY_MAX];

static void MX_CRYP_Restore_From_CCM(void);

// Опкод, чий приймач у цій збірці живий; решту кадрів навіть не відкриваємо.
static uint8_t Soldier_Dl_Opcode_Live(uint8_t op)
{
    return (uint8_t)((FW8_PARSER_ENABLED   && op == DL_CCM_OP_THRESHOLDS) ||
                     (FW17_RATCHET_ENABLED && op == DL_CCM_OP_ROTATE_KEY));
}

// RX-вікно: відкрити кадр сесійним ключем (KEYL / K_v). Відмова будь-якого
// роду — чужий DID, підробка, повтор — мовчить, як ефірний шум.
static void Soldier_Dl_Cmd_Receive(const uint8_t *frame, uint16_t len)
{
    if (len == 0u || !Soldier_Dl_Opcode_Live(frame[0])) return;
    uint32_t dlfc = 0;
    DlCcmResult r = Dl_Ccm_Open(&hcryp, aes_key, frame, len, tree_did,
                                dl_last_dlfc, dl_cmd_body, &dlfc);
    MX_CRYP_Restore_From_CCM(); // ECB + KEYB назад (гоча 1), і на відмові теж
    if (r != DL_CCM_OK) return;
    dl_cmd_op      = frame[0];
    dl_cmd_dlfc    = dlfc;
    dl_cmd_pending = 1;
}

// DLFC у журнал — ПІСЛЯ того, як ефект команди вже записано (at-least-once,
// ⚖️ founder 2026-09-29, 03_05 §2.5). Струм, що зник між ними, лишає команду
// неспожитою, і перевиданий Rails той самий кадр застосується ще раз: обидві
// команди ідемпотентні, тож повтор нешкідливий, а втрата — ні. Невдалий запис
// DLFC — те саме: RAM-кеш не рухається, повтор прийметься.
static void Soldier_Dl_Persist_Dlfc(uint32_t dlfc)
{
    if (FlashKv_Put32(&soldier_kv, DL_CCM_KV_KEY_DLFC, dlfc)) dl_last_dlfc = dlfc;
}

// Для 0x9E і 0x9A ефект комітять блоки FW.17 / FW.8 нижче в КЕНОЗИСІ, тож DLFC
// чекає їхнього успіху тут і пишеться лише з їхньої гілки успіху.
static void Soldier_Dl_Settle_Dlfc(void)
{
    if (dl_dlfc_settle == 0u) return;
    Soldier_Dl_Persist_Dlfc(dl_dlfc_settle);
    dl_dlfc_settle = 0u;
}

// КЕНОЗИС, першою дією. 0x9E і 0x9A лише виставляють dirty — блоки FW.17 і
// FW.8 нижче в цьому ж КЕНОЗИСІ комітять їх звичним шляхом і лише тоді
// записують DLFC (Soldier_Dl_Settle_Dlfc).
static void Soldier_Dl_Cmd_Commit(void)
{
    if (!dl_cmd_pending) return;
    dl_cmd_pending = 0;
    if (!soldier_kv_mounted) return; // без журналу DLFC немає й дії

    switch (dl_cmd_op) {
#if FW17_RATCHET_ENABLED
    case DL_CCM_OP_ROTATE_KEY: {
        uint16_t target = Dl_Cmd_Rotate_Target(dl_cmd_body);
        // replay / rollback / runaway-стрибок — як ефірний шум
        if (Key_Ratchet_Steps(lora_key_version, target) == 0u) return;
        lora_key_target_version = target;
        lora_key_version_dirty  = 1;
        dl_dlfc_settle          = dl_cmd_dlfc;
        return;
    }
#endif
#if FW8_PARSER_ENABLED
    case DL_CCM_OP_THRESHOLDS: {
        LorenzThresholds t;
        if (!Lorenz_Thresholds_From_Wire(dl_cmd_body, &t)) return;
        lorenz_z_min_x100       = t.z_min_x100;
        lorenz_z_max_x100       = t.z_max_x100;
        lorenz_z_opt_x100       = t.z_opt_x100;
        lorenz_species_id       = t.species_id;
        lorenz_config_version   = t.config_version;
        lorenz_thresholds_dirty = 1;
        dl_dlfc_settle          = dl_cmd_dlfc;
        return;
    }
#endif
    default:
        return;
    }
}
#endif // DL_CCM_RX_ENABLED

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
static void MX_IWDG_Init(void); // Ініціалізація IWDG
static void MX_RNG_Init(void);
static void MX_RTC_Init(void);
static void MX_SUBGHZ_Init(void);
static void MX_CRYP_Init(void); // Ініціалізація шифрування

/* USER CODE BEGIN PFP */
void Trigger_Emergency_LoRa_TX(void);
void Write_OTA_Contract_To_Flash(const uint8_t* data, uint16_t size);

// [FW.1 + ARCH.42] Завантаження LoRa AES-128 ключа з Protected Flash Sector.
// Викликається в main() ПЕРЕД MX_CRYP_Init().
static void Load_AES_Key(void);

// [FW.2 (в)] Cluster control-plane KEYB — викликається в main() ПІСЛЯ
// Load_AES_Key (fallback читає K0) і ПЕРЕД MX_CRYP_Init (амбієнт = bcast).
static void Load_Broadcast_Key(void);

// [SEC.11 / FW.30] Завантаження Lorenz K_seed з Protected Flash Sector.
// Викликається в main() при ініціалізації. K_seed використовується для
// cold-start деривації (x₀,y₀,z₀) через HMAC-SHA256.
static void Load_Lorenz_Seed(void);
static void Load_Ota_Seal_Pubkey(void);  // [FW.23] Прочитати публічний ключ печатки OTA з Flash
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
  Load_Broadcast_Key(); // [FW.2 (в)] Cluster-plane KEYB (після KEYL — fallback читає aes_key)
  Load_Lorenz_Seed();  // [SEC.11 / FW.30] Завантажити K_seed для cold-start Lorenz derivation
  Load_Ota_Seal_Pubkey(); // [FW.23] Публічний ключ Ed25519-печатки OTA кластера ("KPUB")
  Load_Node_Role();    // [ARCH.27] Завантажити роль вузла (Soldier/Provisioner) з Flash
  MX_CRYP_Init(); // Вмикаємо апаратний AES (амбієнт = bcast_key в обох ерах)

#if defined(CCM_SELFTEST)
  // [FW.2] POST: бенч-атестація CCM-двигуна на реальному кремнії. Результат у
  // g_ccm_selftest_failed (читати через SWD): 0 → кремній == OpenSSL == backend
  // → дозволено flip FW2_CCM_ENABLED; >0 → HAL/endianness/errata → CCM не вмикати.
  // KAT-вектори: firmware/common/ccm_kat_vectors.h (єдине джерело, спільне з host).
  g_ccm_selftest_failed = Ccm_Run_Self_Test(&hcryp, NULL);
  MX_CRYP_Init(); // бойова конфігурація (ECB, 32B) ПЕРЕД sym-KAT — саме її він і міряє
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
#if FW54_STANDBY_ENABLED
  // [FW.54] Пробудження зі Standby — це reset: відрізняє його лише C1SBF (+ цілий маркер DR19,
  // standby_wake.h). Знімаємо прапорець одразу, інакше reset пін-ом прочитався б пробудженням.
  soldier_woke_from_standby = Silken_Wake_From_Standby(
      (uint8_t)(__HAL_PWR_GET_FLAG(PWR_FLAG_SB) != 0U),
      (uint8_t)(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR19) == LORENZ_STATE_MAGIC));
  __HAL_PWR_CLEAR_FLAG(PWR_FLAG_SB);
#endif

  // 2. Відновлюємо пам'ять з RTC (якщо було перезавантаження)
  // [SEC.10/SEC.20] DR0: [panic:16 | rsv:6 | vm_err_streak:2 | acoustic:8].
  // При cold-boot DR0 == 0 → лічильник пересіємо з HRNG нижче, щоб уникнути
  // колізії з nonce'ами Redis від попереднього втілення вузла.
  {
      uint32_t dr0_raw = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR0);
      acoustic_events     = (uint8_t)(dr0_raw & 0xFFu);
      panic_frame_counter = (uint16_t)((dr0_raw >> PANIC_COUNTER_DR0_SHIFT) & PANIC_COUNTER_MASK);
      // [SEC.20] Streak bytecode-збоїв переживає STOP2 у DR0[9:8] (RAM-only
      // згорів би щоцикл у RTC-only сні — клас Standby, 00_07 FW.54). Cold-boot DR0=0 → streak=0 природно.
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
  // DID виводиться з кремнію детерміновано, тож колізії ловить фабрика
  // DB-unique-перевіркою ще до поля, а не HRNG на борту.
  // DID==0 неможливий (did_derive.h): бекенд відкидає нульовий DID в обох ерах (ARCH.54).
  tree_did = Did_Derive_From_Uid(*(uint32_t*)(0x1FFF7590),
                                 *(uint32_t*)(0x1FFF7594),
                                 *(uint32_t*)(0x1FFF7598));

#if FLASH_KV_BASE_ENABLED
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
#if DL_CCM_RX_ENABLED
  // [FW.17 · 03_05 §2.5] Останній прийнятий DLFC: запису немає (свіжий журнал
  // re-provision, новий чип) → 0, і перша команда відкривається з DLFC 1;
  // mount-fail → приймач живий, але КЕНОЗИС без журналу нічого не застосує.
  if (soldier_kv_mounted) {
      uint32_t v = 0;
      if (FlashKv_Get32(&soldier_kv, DL_CCM_KV_KEY_DLFC, &v)) dl_last_dlfc = v;
  }
#endif

  // [FW.49 S1] Найперший старт (DR1 == 0) НЕ засіюється тут: guard
  // Silken_Wall_Delta_Seconds трактує last==0 як cold-start → сентинел
  // «не виміряно» (DELTA_T_UNKNOWN_S, ARCH.102) для першого циклу,
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
  Radio.SetChannel(LORA_PHY_FREQ_HZ); // 868.2 МГц — raw-LoRa P2P (lora_phy.h)

  // [FW.61] Базлайн модуляції. ⛔ Не прибирати як «драйвер і так дефолтить»:
  // `RadioInit` ставить лише таймери/IRQ і `SUBGRF_SetTxParams(RFO_LP, 0, …)`
  // — тобто низькопотужний PA на 0 дБм; SF/BW/CR/преамбулу/CRC не чіпає ніхто.
  // Доти єдиний `SetTxConfig` жив у panic-шляху ЗА гейтом ARCH.26 (у бойовій
  // збірці нуль), тож базлайн не існував як стан — повертати не було куди.
  // Порядок TX→RX навмисний: обидва виклики ділять одну пару структур драйвера,
  // і останній лишає чіп готовим слухати; довжину payload'у `RadioSend`
  // переписує на кожен кадр. Дім номіналів — 03_05 §2.1.
  Lora_Phy_Apply_Sync_Word();
  Lora_Phy_Apply_Tx(LORA_PHY_TX_POWER_DBM_SOLDIER, LORA_PHY_PREAMBLE_SYMBOLS);
  Lora_Phy_Apply_Rx(LORA_PHY_RX_CONTINUOUS_SOLDIER);

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
    // wall_now == 0 (HAL-збій) → гілка «назад» чи cold-start guard'а → сентинел ↓.
    // [ARCH.102] Guard'и віддають СЕНТИНЕЛ «не виміряно», а не «нейтральні» 60 с:
    // ті 60 мапились у `metabolic_health` = 1.0, тобто відмова виміряти мінтила
    // МАКСИМУМ балів. Дім значення й підстави — `bio_contracts/bio_contract.rb`.
    uint32_t current_time = Wall_Seconds_Now();
    delta_t_seconds = Silken_Wake_Delta_Seconds(current_time, &last_wakeup_timestamp,
                                                DELTA_T_UNKNOWN_S,
                                                DELTA_T_MAX_PLAUSIBLE_S);

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

    // Байт 7: акустичний слот (з HW.30 лічильник завжди 0; ECB-кадр лишається як є — CCM-байт віддає wire-rev2.2, реалізація FW.66).
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
    // TTL = 3 стрибки; thr_invalid з HW.30 завжди 0 (ECB-кадр лишається як є; CCM-біти віддає wire-rev2.2, реалізація FW.66),
    // тож байт бітово ідентичний старому чистому TTL.
    lora_payload[11] = Ttl_Byte_Pack(DEFAULT_TTL, 0u);

    // [FIX: Firmware Version] Байти 12-13: версія прошивки (big-endian).
    // Дозволяє серверу знати яка прошивка на кожному дереві, для OTA targeting.
    // [SEC.20] Байти 12..13 = contract-звіт (fw_report.h), НЕ C-image
    // константа: semantic-біт відрізняє нову семантику від legacy-прошивок.
    lora_payload[12] = (uint8_t)(fw_contract_report >> 8);
    lora_payload[13] = (uint8_t)(fw_contract_report & 0xFF);

    // =========================================================================
    // ФАЗА 3: ПЛАВКА (Запуск Ruby та Атрактора Лоренца)
    // [SEC.11 / FW.30] Єдина сигнатура: calculate_state(x, y, z, temp, acoustic, delta_t_s, vcap_mv, z_min, z_max)
    // Warm path: (x,y,z) з RTC DR16-DR18 (FW.6 state continuation).
    // Cold path: (x₀,y₀,z₀) з K_seed via HKDF/HMAC (SEC.11 seed derivation).
    // delta_t_s/vcap_mv у mruby: EMA-згладжені після прогріву (FW.49-S1 wired);
    // до прогріву — delta_t СЕНТИНЕЛ (DELTA_T_UNKNOWN_S), vcap nominal 3300
    // (03_01 §13.3). Дві різні відповіді на дві різні відсутності: метаболізм
    // не виміряно взагалі → GP=0, а шина живлення стабілізована BQ25570.
    // =========================================================================

    // [E.63 (г)] КОНТРАКТ «wire = вхід GP»: одне число на обидва споживачі —
    // сатуроване до wire-u16 EMA (чи сентинел до прогріву) йде і в mruby
    // metabolic_health, і у wire-байти 20..21. Обчислюється ДО гілкування:
    // VM_ERROR-кадр (mruby скип) теж мусить нести чесне поточне значення,
    // а не залишок минулого циклу.
    // [ARCH.102] До прогріву EMA метаболізм НЕ виміряно — і це сентинел, а не
    // baseline: `BASELINE_DELTA_T_S` тут давав GP = максимум на кожному вузлі,
    // що ще не набрав `EMA_WARMUP_CYCLES` зразків.
    uint32_t delta_t_for_lorenz = Silken_Wake_Lorenz_Delta_T(EMA_Is_Warmed_Up(), EMA_Get_DeltaT_Sec(),
                                                             DELTA_T_UNKNOWN_S);
    uint16_t vcap_for_lorenz    = EMA_Is_Warmed_Up() ? EMA_Get_Vcap_Mv()
                                                     : 3300u;  // nominal (NOMINAL_VCAP_MV; reserved)
#if FW2_CCM_ENABLED
    wire_ema_delta_t_s = (uint16_t)delta_t_for_lorenz;
#endif

    if (grace_hello) {
      // [ARCH.41-C] Лоренц відкладено до першого beacon'а: cold-start
      // деривація від застарілого epoch_day отруїла б RTC-ланцюг траєкторії.
      // lorenz_state_valid лишається 0 → стан у RTC не пишеться; після синку
      // перша деривація піде з ПРАВИЛЬНОЇ доби — серверу не доведеться
      // вгадувати кандидатів. ⚠️ [FW.66] Але серверу, що має хвіст цього дерева,
      // доба не допоможе: він не ре-якориться (біта cold-start на дроті немає) —
      // docs/03_04 §7.3 (в).
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
          // [SEC.11 / FW.30] Єдиний виклик calculate_state (9 аргументів з FW.8).
          // Повертає [payload_byte, x_final, y_final, z_final].
          // [E.63] delta_t_for_lorenz/vcap_for_lorenz обчислені над гілкуванням
          // Фази 3 (контракт «wire = вхід GP» — те саме сатуроване число йде
          // у wire-байти 20..21). delta_t живить growth_points напряму
          // (metabolic_health, 03_04 §4.3); β лишається фіксованим (BASE_BETA) —
          // стара FW.5 β-перетурбація реверсована.
          mrb_value args[9];
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
          // [FW.8] Смуга, ЧИННА на пристрої. Глобалки міняють лише парсер 0x9A і
          // boot-restore з Flash-KV — обидва під FW8_PARSER_ENABLED, тож доставка
          // і споживання вмикаються ОДНИМ фліпом, а бойова збірка шле дефолти
          // (= BioContract::CRITICAL_Z_MIN/MAX) навіть із залишком порогів у KV.
          double band[2];
          Lorenz_Band_Args(lorenz_z_min_x100, lorenz_z_max_x100, band);
          args[7] = mrb_float_value(mrb, band[0]);
          args[8] = mrb_float_value(mrb, band[1]);

          mrb_value ruby_result = mrb_funcall_argv(mrb, mrb_top_self(mrb),
              mrb_intern_lit(mrb, "calculate_state"), 9, args);

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

    // [FW.10] Зимовий кенозис передачі: при лютому морозі (нижче −15°C, строге `<`)
    // ESR іоністора різко зростає — LoRa TX при кволій напрузі (<4.0В) може кинути
    // ксилему у брауноут. Краще промовчати й зберегти тепло: пропускаємо
    // Фази 4–4.5 і одразу падаємо у Кенозис. Предикат і його стеля (Vcap-половина
    // у полі вироджена, ARCH.99) — tx_defer.h.
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
        // [FW.61] Чужий кадр відлітає цілком (16 Б @ SF9 ≈ 165 мс + запас) —
        // лише тоді власний Send: інакше він переписав би буфер, з якого модем
        // ще читає.
        HAL_Delay(Lora_Phy_Send(mesh_relay_payload, 16, LORA_PHY_PREAMBLE_SYMBOLS));
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
        HAL_Delay(Lora_Phy_Send(encrypted_payload, 16, LORA_PHY_PREAMBLE_SYMBOLS));
        // Cooldown НЕ чіпаємо: grace-hello летить КОЖНЕ пробудження навмисно
        // (замість телеметрії — Королеві потрібен uplink для OTA-рефлексу);
        // cooldown належить сплячому drift-watchdog'у (0x56 ПОВЕРХ телеметрії).
    } else {
        // [ARCH.102] Прапорець спільний для обох збірок: у CCM-гілці передача
        // умовна (білд кадру може не вдатись), у ECB — безумовна, а лічильник
        // мусить споживатись рівно там, де кадр справді пішов.
        uint8_t telemetry_sent = 0u;
#if FW2_CCM_ENABLED
        // [FW.2] Wire-rev2.1: телеметрія = 30B CCM замість 16B ECB. Джерела —
        // ті САМІ живі значення, що вже лягли в lora_payload (байт-парність
        // семантики): сирий vcap_voltage (wire завжди носив сирий, EMA — то
        // їжа Лоренца), dt_wire із сатурацією 0xFFFF, StatusByte після
        // FW.29-маски, acoustic з ARCH.41-B sentinel-логікою. mesh_ctrl =
        // [TTL:4|fw_low:4] (розкладка 03_05 §2.1; low-nibble версії — 16-епох
        // ротація через OTA-config). thr_invalid і fauna-біти з HW.30 завжди 0
        // (у wire-rev2.2 біти thr_invalid займуть reset_cause · time_uncertain · voc_attempt, а fauna-біти стануть резервом, FW.66). Збій збірки (HAL
        // захрип) → мовчимо цей цикл: 16B-фолбек у CCM-ері Королева однаково
        // дропне (atomic-cutover), то був би спалений airtime, не телеметрія.
        uint8_t ccm_air[FW2_CCM_AIR_PACKET_LEN];
        uint8_t ccm_mesh_ctrl = (uint8_t)(((DEFAULT_TTL & FW2_MESH_TTL_MASK)
                                           << FW2_MESH_TTL_SHIFT) |
                                          (FIRMWARE_VERSION_ID & FW2_MESH_FW_NIBBLE_MASK));
        uint8_t ccm_diag = Pack_FW2_Diag(0u, 0u, 0u, fc_hiwater_degraded);
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
                                             BME280 (HW.32) → wire-rev2.2 (FW.66)
                                             переносить його в байт 11 */
                                          Fw_Report_To_Vpd(fw_contract_report),
                                          Soldier_Pack_Gossip_Ts_Byte(soldier_unix_ts),
                                          wire_ema_delta_t_s /* [E.63 (г)] = вхід GP */,
                                          ccm_air) == HAL_OK) {
            HAL_Delay(Lora_Phy_Send(ccm_air, FW2_CCM_AIR_PACKET_LEN, LORA_PHY_PREAMBLE_SYMBOLS));
            telemetry_sent = 1u;
        }
#else
        HAL_CRYP_Encrypt(&hcryp, (uint32_t*)lora_payload, 4, (uint32_t*)encrypted_payload, 1000);
        // [FW.61] Чекаємо, доки кадр відлетить: наступна команда радіо тут —
        // `Radio.Rx` Фази 4.5, і посеред ефіру вона обриває телеметрію.
        HAL_Delay(Lora_Phy_Send(encrypted_payload, 16, LORA_PHY_PREAMBLE_SYMBOLS));
        telemetry_sent = 1u;
#endif

        // [ARCH.102] Спожити рівно СТІЛЬКИ, скільки поїхало на дріт. Віднімання,
        // не обнулення: між знімком і передачею лічильник не росте (з HW.30
        // інкременту немає взагалі), але віднімання лишається правдивим і
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
            // Телеметрія вже відлетіла цілком (Send вище дочекався свого ефіру).
            HAL_CRYP_Encrypt(&hcryp, (uint32_t*)sync_plain, 4, (uint32_t*)encrypted_payload, 1000);
            HAL_Delay(Lora_Phy_Send(encrypted_payload, 16, LORA_PHY_PREAMBLE_SYMBOLS));
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
        // Попередній кадр уже відлетів цілком (кожен Send дочікує свого ефіру).
        HAL_CRYP_Encrypt(&hcryp, (uint32_t*)evt_plain, 4, (uint32_t*)encrypted_payload, 1000);
        HAL_Delay(Lora_Phy_Send(encrypted_payload, 16, LORA_PHY_PREAMBLE_SYMBOLS));
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
                // [FW.2 · FW.17] Розрізнення за довжиною ДО будь-якого декрипту
                // (ungated — вірно в обох ерах): 16 Б — ECB-кадри Королеви на
                // KEYB (маяк / OTA / печатка / mesh); будь-яка інша — лише
                // адресна команда під сесійним ключем цього вузла (03_05 §2.5,
                // секція 1.14), а решта (30-Б CCM-кадр сусіда тощо) гине там же:
                // не та довжина для опкоду або чужий DID. 30-Б кадр, прогнаний
                // ECB'ом, давав ~1/256 шанс хибно зійтися на 0x99/0x9B і отруїти
                // ota_buffer/печатку. CCM-телеметрію Солдат свідомо НЕ
                // ретранслює: mesh-TTL живе у шифртексті — рішення відкладено
                // до ARCH.26 (03_05 §2.1 «Відкриті спостереження»).
                if (incoming_lora_size != 16) {
#if DL_CCM_RX_ENABLED
                    Soldier_Dl_Cmd_Receive((const uint8_t*)incoming_lora_payload,
                                           incoming_lora_size);
#endif
                    break; // один пакет за пробудження (re-request Фази 4.5 живий)
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
                            // Після `break` нижче — кінець прийому (Radio.Standby), а сон радіо —
                            // на вході у Фазу 5: кадр мусить відлетіти ДО обох.
                            HAL_Delay(Lora_Phy_Send(encrypted_payload, BEACON_PLAINTEXT_SIZE,
                                                    LORA_PHY_PREAMBLE_SYMBOLS));
                            Beacon_Dedup_Mark(&beacon_dedup,
                                              Beacon_Dedup_Gen(beacon_ts));
                        }
                    }
#endif
                    // Один RX-пакет за пробудження (FW.52 ADR) — спати.
                    break;
                }

                // [FW.17 · 03_05 §2.5] Адресних команд (0x9A · 0x9E) на
                // 16-байтному ECB-шляху НЕМАЄ і не повертати: живий приймач під
                // кластерним KEYB дав би будь-кому з вкраденою платою командувати
                // кожним вузлом. Їх несе лише CCM-кадр (гілка довжини ≠ 16 вище).

                // Сценарій А1: [FW.23] Ed25519-печатка OTA (0x9B) — 7 LoRa-блоків
                // після тіла прошивки: 6 несуть 64-байтний підпис, 7-й — version_id
                // над (bytecode || version_id_be || total_chunks_be).
                if (decrypted_rx_payload[0] == OTA_SEAL_MARKER) {
                    // [FW.68] Трейлер чужої кампанії (total ≠ total нашого збирання тіла) —
                    // шум: інакше він мовчки перезаписав би печатку, і чесне тіло дістало б REJECT.
                    if (!Ota_Seal_Block_Belongs((const uint8_t*)decrypted_rx_payload,
                                                incoming_lora_size, ota_total_chunks)) {
                        break;
                    }
                    const uint8_t segs_before = ota_seal_segments_received;
                    int rc = Ota_Seal_Parse_Chunk((const uint8_t*)decrypted_rx_payload,
                                                  incoming_lora_size,
                                                  received_ota_seal,
                                                  &received_ota_version,
                                                  &ota_seal_segments_received);
                    // rc=1 ⇒ печатка/версія лягли на місце; rc=0 ⇒ не наш marker
                    // (сюди ми б не зайшли); rc=-1 ⇒ невалідна (size/seg_idx) —
                    // мовчки відкидаємо, як ефірний шум.
                    (void)rc;
                    // Новий блок печатки — теж нове слово: лічильник тиші в нуль (FW.27-B).
                    if (ota_seal_segments_received != segs_before) ota_silent_wakeups = 0;

                    // [FW.23] Печатка могла прийти ПІСЛЯ останнього чанка тіла —
                    // тоді саме вона довершує OTA. Якщо тіло вже зібране й тепер є
                    // всі 7 трейлер-блоків → фіналізуємо тут (дзеркало 0x99-гілки).
                    uint16_t data_len = 0;
                    OtaFinalizeVerdict verdict = Ota_Seal_Try_Finalize(
                        ota_buffer, ota_bytes_received,
                        ota_chunks_received, ota_total_chunks,
                        ota_seal_segments_received,
                        ota_seal_pubkey, ota_seal_pubkey_valid,
                        received_ota_version, received_ota_seal,
                        &data_len);

                    // [SEC.20] Печатка довела справжність, але не свіжість:
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
                    // заході OTA-вікна. Ціна: блоки печатки, що прийшли ДО
                    // першого чанка тіла, теж гинуть (00_07 FW.68).
                    if (ota_total_chunks == 0) {
                        memset(received_ota_seal, 0, sizeof(received_ota_seal));
                        received_ota_version = 0;
                        ota_seal_segments_received = 0;
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
                        // (Королева шле тіло → потім печатку). Ota_Seal_Try_Finalize
                        // дає WAIT, якщо ще нема всіх 7 трейлер-блоків — тоді НІЧОГО
                        // не чіпаємо: зібране тіло чекає, а фіналізацію довершить
                        // 0x9B-гілка, коли долетить остання печатка. Запис у Flash і
                        // ребут — лише коли magic і Ed25519-печатка розчинились.
                        uint16_t data_len = 0;
                        OtaFinalizeVerdict verdict = Ota_Seal_Try_Finalize(
                            ota_buffer, ota_bytes_received,
                            ota_chunks_received, ota_total_chunks,
                            ota_seal_segments_received,
                            ota_seal_pubkey, ota_seal_pubkey_valid,
                            received_ota_version, received_ota_seal,
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
                            // стираємо magic у RAM-bytecode. Прибирання, не захист:
                            // boot контракт бере лише з Flash, а .bss скидається;
                            // захищає те, що запис у Flash стоїть лише за APPLY.
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
                // panic сусідів стають 30B (гинуть на RX-guard вище до
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
        // Кінець прийому. Вікно — лише програмний таймер (RxTimeout у Солдата
        // NULL, апаратний тайм-аут ≈ 65 с), а Set_Sleep радіо приймає ЛИШЕ зі
        // Standby (RM0461 Rev 11 §4.8.3) — без цього сон Фази 5 не спрацював би й
        // радіо слухало б далі (4.82 мА), а FW.27-B нижче передавав би з того ж буфера.
        Radio.Standby();

        // =====================================================================
        // [FW.27-B · FW.68] Magic Re-Request: Солдат подає голос про пропуски
        // =====================================================================
        // Збирання відкрите — бракує чанків тіла АБО, за повного тіла, блоків печатки, —
        // а вухо цього пробудження не почуло нового слова: ще одна тиха ніч у
        // лічильник. Десята (≈5 хв wall при циклі 26-32 с) — і Солдат стріляє зойком
        // (бітмап тіла або сентинел печатки з маскою). Королева зойк лише ЗАПИСУЄ, а
        // блоки віддає рефлекс-пострілом на наступні кадри цього дерева — по одному за
        // пробудження, у вухо, що вже слухає (⚖️ FW.68, 03_02 §5.1.3).
        const OtaReqKind req_kind = Ota_Req_Kind(ota_total_chunks, ota_chunks_received,
                                                 ota_seal_segments_received);
        if (Ota_Req_Silence_Due(req_kind, (uint8_t)(ota_last_chunk_rx_tick != 0),
                                &ota_silent_wakeups)) {
            uint8_t req_payload[OTA_REQ_PACKET_SIZE] = {0};

            uint8_t any_missing = (req_kind == OTA_REQ_BODY)
                ? Ota_Req_Build_Body(tree_did, ota_total_chunks, ota_chunk_received,
                                     sizeof(ota_chunk_received), req_payload)
                : Ota_Req_Build_Seal(tree_did, ota_seal_segments_received, req_payload);
            if (any_missing) {
                uint8_t encrypted_req[OTA_REQ_PACKET_SIZE] = {0};
                // Шифруємо запит (1 AES-128-ECB block = 16 байт = 4 слова, post-ARCH.42)
                HAL_CRYP_Encrypt(&hcryp, (uint32_t*)req_payload, 4,
                                  (uint32_t*)encrypted_req, 1000);
                // Далі Фаза 5 гасить радіо (Radio.Sleep) — зойк мусить відлетіти ДО.
                HAL_Delay(Lora_Phy_Send(encrypted_req, OTA_REQ_PACKET_SIZE,
                                        LORA_PHY_PREAMBLE_SYMBOLS));
                // Лічильник у нуль: Королева віддаватиме борг по блоку на наступних
                // кадрах; блок, що загубиться, перепитає наступна десята тиха ніч.
                ota_silent_wakeups = 0;
            }
        }
    }

    phase5_kenosis:
    // =========================================================================
    // ФАЗА 5: КЕНОЗИС (Абсолютний сон та збереження)
    // =========================================================================
    // [FW.54] Радіо спить на КОЖНОМУ шляху входу сюди: мороз (FW.10) стрибає
    // повз приймач, за vcap ≤ VCAP_LISTEN_THRESHOLD приймача немає зовсім, а
    // зойк OTA (FW.27-B) після TX лишає радіо в STDBY_RC — 0.7 мА проти 140 нА
    // сну (DS13105 Табл. 28). Set_Sleep приймається лише зі Standby (RM0461 Rev 11
    // §4.8.3), тож сюди радіо приходить у STDBY_RC (кінець прийому, TX_DONE,
    // стартова конфігурація) або вже сплячим (HAL будить його імпульсом NSS). Між
    // цим рядком і входом у сон радіо не будити; обидва правила стереже
    // `make -C firmware/test standby_wake`.
    Radio.Sleep();
#if DL_CCM_RX_ENABLED
    // [FW.17] Прийнята у вікні команда — першою: її ефект мусить устигнути в
    // блоки FW.17 / FW.8 нижче в цьому ж КЕНОЗИСІ (секція 1.14).
    Soldier_Dl_Cmd_Commit();
#endif
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

#if FW17_RATCHET_ENABLED
    // [FW.17] Ротація комітиться саме тут, у КЕНОЗИСІ: erase/program не сміє
    // лягти під LoRa RX-вікно (03_01 §2.3). Key_Ratchet_Commit пише версію
    // ПЕРШ ніж перемкнути ключ, тож перший кадр новим ключем означає, що boot
    // уже відтворить новий, — і бекенд закриває Dual-Key Grace саме на ньому.
    // Запис не вдався → вузол лишається на старому ключі, який бекенд у grace
    // ще тримає, і наступний КЕНОЗИС повторить. Power-cut після запису, до
    // перемикання, безпечний: boot відтворить ratchet^target(K0).
    if (lora_key_version_dirty && soldier_kv_mounted) {
        uint8_t key_bytes[KEY_RATCHET_KEY_LEN];
        Key_Ratchet_Words_To_Bytes(aes_key, key_bytes);
        if (Key_Ratchet_Commit(key_bytes, &lora_key_version, lora_key_target_version,
                               tree_did, Soldier_Persist_Key_Version, NULL)) {
            Key_Ratchet_Bytes_To_Words(key_bytes, aes_key);
            // [FW.2 (в)] Ратчет ротує ЛИШЕ session (KEYL): MX_CRYP_Init
            // повертає амбієнт = bcast_key, тож downlink НЕ глухне від ротації
            // (двоключова розв'язка); новий K_v застосує наступний
            // MX_CRYP_Init_CCM. KEYB ратчет НЕ торкається — його ротація =
            // re-provision (як ключ печатки OTA).
            MX_CRYP_Init();
            lora_key_version_dirty = 0;
            Soldier_Dl_Settle_Dlfc(); // ефект уже в журналі — тепер і DLFC
        }
    }
#endif
#if FW8_PARSER_ENABLED
    // [FW.8] Прийняті 0x9A-пороги — у Flash-KV у тій самій безпечній фазі.
    // Невалідну конфігурацію Save не пише взагалі; power-cut між парою
    // ключів лікує перевидача з бекенду за доказом зі статусу (ADR у
    // lorenz_thresholds.h).
    if (lorenz_thresholds_dirty && soldier_kv_mounted) {
        LorenzThresholds t;
        t.z_min_x100     = lorenz_z_min_x100;
        t.z_max_x100     = lorenz_z_max_x100;
        t.z_opt_x100     = lorenz_z_opt_x100;
        t.species_id     = lorenz_species_id;
        t.config_version = lorenz_config_version;
        if (Lorenz_Thresholds_Save(&soldier_kv, &t)) {
            lorenz_thresholds_dirty = 0;
            Soldier_Dl_Settle_Dlfc(); // ефект уже в журналі — тепер і DLFC
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
#if FLASH_KV_BASE_ENABLED
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

#if FW54_STANDBY_ENABLED
    // [FW.54] Ціль: Standby. Не повертається — наступне пробудження йде через reset у main().
    Silken_Standby_Enter(&g_standby_ops);
#else
    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
    HAL_ResumeTick();

    // [FIX: AUDIT Energy] Відновлюємо периферію після пробудження
    HAL_RNG_Init(&hrng);
    __HAL_RCC_AES_CLK_ENABLE();
    HAL_CRYP_Init(&hcryp);
#endif

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
    //    тримає піковий струм). Брауноут ловить радіо й посеред TX/RX, а Set_Sleep
    //    приймається ЛИШЕ зі Standby (RM0461 Rev 11 §4.8.3) — тож спершу Standby
    //    (без затримки, безпечний у перериванні).
    Radio.Standby();
    Radio.Sleep();

    // 5. Падаємо у глибокий сон (Кома), поки напруга не підніметься знову
#if FW54_STANDBY_ENABLED
    // [FW.54] У Standby — ще нижчий струм; стан уже в DR (кроки 1–3), продовження — через reset.
    Silken_Standby_Enter(&g_standby_ops);
#else
    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
#endif
}

// =========================================================================
// АПАРАТНИЙ РЕФЛЕКС ПАНІКИ (Tamper Detection)
// =========================================================================
// З HW.30 (2026-09-29, пʼєзо зрізано) викликача немає: транспорт лишено як
// можливого носія сигналу реального часу (HW.52, далекий горизонт).
// ⛔ Прибирається лише разом із присудом HW.52.
void Trigger_Emergency_LoRa_TX(void)
{
    // [FW.61] Преамбула, з якою кадр ПІДЕ, — одна змінна і для SetTxConfig
    // («останній зойк» ARCH.26 її подовжує), і для очікування кінця ефіру.
    uint16_t panic_preamble = LORA_PHY_PREAMBLE_SYMBOLS;
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
    uint8_t panic_diag = Pack_FW2_Diag(0u, 0u, 0u, fc_hiwater_degraded);
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

    // 3. TTL = 5, щоб пакет вижив довше і точно дійшов; верхні 5 біт
    //    (бітфілд ttl_byte.h) з HW.30 — нуль, як у звичайному пакеті
    panic_payload[11] = Ttl_Byte_Pack(PANIC_TTL, 0u);

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
    // зловить. Контекст: main-loop — блокуючий SetTxConfig/HAL_Delay
    // безпечні; НЕ кликати цю функцію з ISR.
    panic_preamble = Cad_Panic_Preamble_Symbols(
        EMA_Get_Vcap_Mv(), CAD_PANIC_PREAMBLE_VCAP_MIN_MV,
        Cad_Preamble_Symbols_For_Ms(CAD_PANIC_PREAMBLE_MS,
                                    CAD_T_SYM_SF9_BW125_US));
    Lora_Phy_Apply_Tx(LORA_PHY_TX_POWER_DBM_SOLDIER, panic_preamble);
#endif
    // 5. [FW.61] Шлемо й чекаємо ЦІЛИЙ кадр — з тією преамбулою, що пішла в
    // SetTxConfig. ⛔ Сталої паузи замість цього часу не ставити: кадр летить
    // ≥ 165 мс (а з «останнім зойком» — секунди преамбули), і відновлення
    // SetTxConfig та Radio.Sleep нижче посеред ефіру обривають зойк.
#if FW2_CCM_ENABLED
    // Збій збірки (HAL захрип) → мовчимо: підроблений/битий зойк гірший за
    // тишу, а L1-Королева все одно слухає наступне пробудження.
    if (panic_built == HAL_OK) {
        HAL_Delay(Lora_Phy_Send(panic_air, FW2_CCM_AIR_PACKET_LEN, panic_preamble));
    }
#else
    HAL_Delay(Lora_Phy_Send(encrypted_panic, 16, panic_preamble));
#endif

#if ARCH26_CAD_ENABLED
    // Обов'язкове відновлення дефолтної преамбули (дисципліна
    // Restore_ECB_Mode): липкі ~973 симв на наступному звичайному TX
    // мовчки з'їли б ~40× airtime і енергобюджет циклу.
    // [FW.61] Відновлюється ПОВНИЙ набір із базлайну, а не один аргумент із
    // шести: решта п'ять і далі проходили б повз, і правильними вони були
    // лише тому, що дорівнювали канону випадково.
    Lora_Phy_Apply_Tx(LORA_PHY_TX_POWER_DBM_SOLDIER, LORA_PHY_PREAMBLE_SYMBOLS);
#endif

    // 6. Примусово присипляємо радіо, щоб не садити батарею
    Radio.Sleep();
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
// Записується при Factory Flashing через SWD — factory:execute: `-e` сторінки
//   ключів + `-w32` цілими doubleword-ами (docs/03_06 §2, STEP 2 d).
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

// [FW.2 гейт (в)] Завантаження cluster control-plane ключа (KEYB, стор. 125).
// НЕ Error_Handler(): відсутній KEYB — законна bench-плата, прошита до
// KEYB-ери, вона деградує до односхемної поведінки на KEYL і чесно
// позначає це прапорцем. Fail-open тут безпечний, бо fallback-ключ — той
// самий, на якому такий кластер і живе; конвеєр пише обидва слоти в
// будь-якій ері (command_builder), тож у полі прапорець мусить бути 0. Патерн — Load_Ota_Seal_Pubkey (fail-open + valid-флаг),
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

// [FW.23] Завантаження публічного Ed25519-ключа печатки OTA кластера з Protected Flash.
// Flash layout на FLASH_OTA_KEY_ADDR (0x0803E800, сторінка 125):
//   [FLASH_OTA_PUBKEY_MAGIC:4]["KPUB"][pub[0]:4]...[pub[7]:4] = 4 + 32 = 36 байт
// Якщо magic відсутній/стертий (зокрема старий "KOTA" — симетричний ключ, який ця
// прошивка свідомо не читає) або ключ нульовий — ota_seal_pubkey_valid=0: печатка
// не пройде ⇒ жоден OTA не запишеться (fail-safe; без ключа походження не довести).
// НЕ Error_Handler() — телеметрія й Lorenz працюють без нього; лише OTA-канал
// лишається замкненим до provisioning. Байтовий порядок — BE-слова → байти, як пише
// FactoryFlashing::CommandBuilder (`block_words`) з 64-hex публічного ключа.
static void Load_Ota_Seal_Pubkey(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_OTA_KEY_ADDR;

    // 1. Magic — чи публічний ключ записано при provisioning кластера
    if (flash_ptr[0] != FLASH_OTA_PUBKEY_MAGIC) {
        ota_seal_pubkey_valid = 0;
        return;
    }

    // 2. Ключ — BE-слова → байти, як пише фабрика; нульовий (magic є, ключа нема —
    //    зіпсований провіжн) ⇒ invalid. Розпак — common/ota_seal.h, пін наскрізь.
    ota_seal_pubkey_valid = (uint8_t)Ota_Seal_Pubkey_From_Words(&flash_ptr[1], ota_seal_pubkey);
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

    // RTC Backup тримає float32 — звуження свідоме, і сервер мусить робити
    // те саме (`SilkenNet::Attractor.as_rtc_state`, FW.66): толерансом це не
    // покрити — хаос підсилює різницю за кілька кадрів (docs/03_04 §5).
    *x0 = (float)dx;
    *y0 = (float)dy;
    *z0 = (float)dz;
}

// Функція конфігурації апаратного AES (Створюється автоматично CubeMX)
// Post-ARCH.42 Variant B (2026-05-23): LoRa-канал на AES-128 (вибір; SE = SE050 — 03_05 §3.7).
// FW.2 target — `CRYP_AES_CCM` 30B wire-rev2.1 двофазним WL-флоу (B0 +
// HAL_CRYP_Encrypt + GenerateAuthTAG — lora_ccm.h); bench верифікує кремній
// проти OpenSSL (ccm_selftest, RM0461 §27.4).
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType = CRYP_DATATYPE_32B;
  hcryp.Init.KeySize = CRYP_KEYSIZE_128B; // ARCH.42 Variant B — AES-128 LoRa (вибір; SE = SE050 — 03_05 §3.7)
  // [FW.2 гейт (в)] Амбієнтний ECB обох ер = cluster-plane (KEYB): RX-decrypt
  // downlink'а Королеви + TX 0x55/0x56, а в ECB-ері — і телеметрія. Session
  // (aes_key) живе ЛИШЕ всередині CCM-скоупа (MX_CRYP_Init_CCM → Restore
  // повертає сюди). 03_05 §3.1.
  hcryp.Init.pKey = bcast_key;
  hcryp.Init.Algorithm = CRYP_AES_ECB;    // ECB transitional → TARGET: CRYP_AES_CCM (FW.2)
  HAL_CRYP_Init(&hcryp);
}

// ============================================================================
// [FW.2 / ARCH.42 Variant B] AES-128-CCM 30-byte LoRa packet (wire-rev2.1) — freeze-contract
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
#endif

#if FW2_CCM_ENABLED || DL_CCM_RX_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
// Гігієна після CCM: ECB-контекст назад (дисципліна Restore_ECB_Mode) і
// жодного висячого вказівника у Init — B0/Header жили на стеку викликача.
// Width-unit'и ОБОВ'ЯЗКОВО назад у WORD: MX_CRYP_Init їх не чіпає, а
// production-ECB передає Size у словах — липкий BYTE зламав би decrypt.
// [FW.2 (в)] Вкладений MX_CRYP_Init повертає й КЛЮЧ: session (aes_key)
// скоупований CCM-фазою, амбієнт знову cluster-plane (bcast_key) — RX-вікно
// Фази 4.5 декриптує downlink Королеви правильним ключем автоматично.
// [FW.17] Кличе й відкриття адресної команди (секція 1.14) — у тому числі
// в ECB-ері, звідси ширший гейт, ніж у MX_CRYP_Init_CCM.
static void MX_CRYP_Restore_From_CCM(void)
{
    hcryp.Init.B0              = NULL;
    hcryp.Init.Header          = NULL;
    hcryp.Init.HeaderSize      = 0;
    hcryp.Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_WORD;
    hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_WORD;
    MX_CRYP_Init();
}
#endif

#if FW2_CCM_ENABLED || defined(HAL_MOCK_CCM_ENABLED)
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
//   diag       — Pack_FW2_Diag(0, 0, 0, fc_hiwater_degraded): thr_invalid і
//                fauna-біти з HW.30 завжди 0 (у wire-rev2.2 thr_invalid-біти несуть нові поля, fauna — резерв, FW.66)
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
    // [SEC.41] Насичений інкремент — справді насичений: на вичерпанні 24-бітного
    // простору TX відмовляє (лічильник не рухаємо), доки re-provision не відкриє
    // нову епоху nonce свіжим журналом (docs/03_05 §2.1; ратчет FW.17 якоря 0x14
    // не скидає). Доти тут стояв перехід через нуль, і після нього кожен cold
    // start повторював nonce під тим самим KEYL.
    uint32_t next_fc;
    if (!Fw2_Next_Frame_Counter(fc, &next_fc)) return HAL_ERROR;

    // [FW.2 TRL-7] Сторожа межі (інваріант I-HW, fc_hiwater.h): за
    // дисципліни КЕНОЗИС-advance (запас MARGIN) сюди не заходимо ніколи —
    // це останній рубіж, коли Flash відмовляв багато циклів поспіль.
    // Energy-gate: один dw-program дозволяємо лише при заряді, якого
    // вистачає й на RX-вікно (vcap_mv — мВ, конверсія на боці викликача).
    // ⚠️ [ARCH.99] Задум, не поле: vcap_mv — мВ VDDA (≈3300 > 2800), тож до
    // живого Vcap-каналу (00_07 FW.50) гейт пропускає ЗАВЖДИ — ще один
    // вироджений сайт на цій шині (03_01 §1.4).
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
