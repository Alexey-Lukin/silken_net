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

// === 1.10. ЗГЛАДЖУВАЧ ПУЛЬСУ (FW.21: EMA Persistence) ===
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
  acoustic_events = (uint16_t)HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR0);
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
  // =========================================================================
  // Перевіряємо маркер валідності в DR19. Якщо LORENZ_STATE_MAGIC —
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
          // [FW.21] EMA значення (delta_t_ms / vcap_mv) ще НЕ передаються в mruby.
          // Поки що передаємо defaults (60 с, 3300 мВ). Задача FW.5 B+: передавання
          // EMA-згладжених значень через args[5..6].
          mrb_value args[7];
          args[0] = mrb_float_value(mrb, (double)lorenz_x);
          args[1] = mrb_float_value(mrb, (double)lorenz_y);
          args[2] = mrb_float_value(mrb, (double)lorenz_z);
          args[3] = mrb_fixnum_value((int8_t)lora_payload[6]); // Температура
          args[4] = mrb_fixnum_value(lora_payload[7]); // Акустика
          args[5] = mrb_fixnum_value(60);   // delta_t_s default (FW.5 B+ TODO: EMA_Get_DeltaT_Sec())
          args[6] = mrb_fixnum_value(3300); // vcap_mv default (FW.5 B+ TODO: EMA_Get_Vcap_Mv())

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

                // Сценарій А: OTA Оновлення від Королеви (Пакет починається з OTA_MARKER)
                if (decrypted_rx_payload[0] == OTA_MARKER) {
                    // [FIX: AUDIT] Перевірка мінімального розміру пакета (5 байт заголовок + 1 байт даних)
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
                        ota_chunk_received[chunk_idx] = 1; // Маркуємо шматок як отриманий
                        ota_chunks_received++;
                        ota_bytes_received += chunk_size;

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

                                if (crc == expected_crc) {
                                    Write_OTA_Contract_To_Flash(ota_buffer, data_len);
                                    NVIC_SystemReset();
                                }
                                // CRC не збігся — ігноруємо, чекаємо на повторну передачу
                            }
                            // Скидаємо стан OTA для повторної спроби
                            memset(ota_chunk_received, 0, sizeof(ota_chunk_received));
                            ota_chunks_received = 0;
                            ota_bytes_received = 0;
                            ota_total_chunks = 0;
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
    }

    phase5_kenosis:
    // =========================================================================
    // ФАЗА 5: КЕНОЗИС (Абсолютний сон та збереження)
    // =========================================================================
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0, acoustic_events);
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
// АПАРАТНИЙ РЕФЛЕКС СМЕРТІ (PVD Interrupt)
// =========================================================================
// Ця функція миттєво викликається апаратно, якщо напруга падає нижче 2.2V
void HAL_PWR_PVDCallback(void)
{
    // 1. Немає часу на математику. Терміново ховаємо дані у вічну пам'ять!
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0, acoustic_events);

    // 2. Жорстко вимикаємо всі периферійні пристрої (Радіо)
    Radio.Sleep();

    // 3. Падаємо у глибокий сон (Кома), поки напруга не підніметься знову
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
    // Для DCI парності з backend потрібен UTC unix epoch / 86400 —
    // це буде скориговано через FW.20 CMD_TIME_SYNC.
    uint32_t approx_days = (uint32_t)(sDate.Year + 2000 - 1970) * 365UL
                         + (uint32_t)(sDate.Month - 1) * 30UL
                         + (uint32_t)sDate.Date;

    // Детерміністична деривація з K_seed + epoch_day.
    // Використовуємо просте хешування (XOR fold + rotation) як placeholder
    // для повноцінного HMAC-SHA256. Це забезпечує:
    // - різні початкові точки для різних днів
    // - різні початкові точки для різних K_seed
    // - координати ∈ [-1, +1]
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
