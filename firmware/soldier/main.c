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
// Секретний 256-бітний ключ мережі Silken Net (Gaia 2.0 Standard)
uint32_t aes_key[8] = {0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
                       0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D};

// === 1. ОРГАНИ ЧУТТЯ ТА ПАМ'ЯТЬ ===
volatile uint8_t vibration_detected = 0; // Прапорець переривання від п'єзодиска
uint16_t acoustic_events = 0;          // Відфільтровані мікророзриви (Кавітація)
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

// === 1.8. ПАМ'ЯТЬ ЕСТАФЕТИ (Directed Mesh) ТА OTA ===
uint8_t mesh_relay_payload[16] = {0}; // Буфер для чужого 16-байтного пакета
uint8_t has_mesh_relay = 0;           // Прапорець: 1 - є пакет для ретрансляції

// Кеш "пліток" (Wall to Wall Cobwebs). Пам'ятаємо останні 3 чужі DID,
// щоб не ганяти їхні дані по колу (захист від пінг-понгу).
uint32_t recent_mesh_dids[3] = {0, 0, 0};

volatile uint8_t lora_rx_flag = 0;
uint8_t incoming_lora_payload[256];
uint8_t decrypted_rx_payload[256]; // Розшифрований вхідний потік
uint16_t incoming_lora_size = 0;

// Буфер для збирання байт-коду по шматочках (OTA)
uint8_t ota_buffer[1024];
uint16_t ota_bytes_received = 0;
uint8_t ota_total_chunks = 0;
uint8_t ota_chunks_received = 0;
// Масив прапорців для захисту від дублікатів OTA
uint8_t ota_chunk_received[256] = {0};

uint8_t* current_lorenz_bytecode;

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
  MX_CRYP_Init(); // Вмикаємо апаратний AES

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

  // Відновлюємо пам'ять останніх 3-х почутих DID
  recent_mesh_dids[0] = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR8);
  recent_mesh_dids[1] = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR9);
  recent_mesh_dids[2] = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR10);

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

      // Гарантуємо, що DID ніколи не дорівнює 0
      if (tree_did == 0) tree_did = 0x511CEE01;

      // Назавжди блокуємо цей DID у вічній пам'яті
      HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR7, tree_did);

      // При народженні очищаємо кеш пліток від заводського "сміття"
      recent_mesh_dids[0] = 0;
      recent_mesh_dids[1] = 0;
      recent_mesh_dids[2] = 0;
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

    // 3. Квантовий Хаос (Зерно для Атрактора)
    uint32_t chaos_seed = 0;
    HAL_RNG_GenerateRandomNumber(&hrng, &chaos_seed);

    // =========================================================================
    // ФАЗА 1.5: TINYML (Шаховий розтин / Фільтрація Свідомості через DMA)
    // =========================================================================

    // Якщо ядро прокинулось через вібрацію на піні
    if (vibration_detected) {
        vibration_detected = 0;
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

            if (ml_confidence > 0.80) {
                if (ml_event_id == 2) {
                    // Це підтверджена кавітація ксилеми!
                    acoustic_events++;
                } else if (ml_event_id == 3) {
                    // Тривога: Аномальна вібрація (Бензопила / Вандалізм)
                    Trigger_Emergency_LoRa_TX();
                }
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

    // Байт 7: Акустичні події (Відфільтровані TinyML)
    lora_payload[7] = (uint8_t)(acoustic_events & 0xFF);

    // Байти 8-9: Швидкість заряду (Секунди)
    lora_payload[8] = (uint8_t)(delta_t_seconds >> 8);
    lora_payload[9] = (uint8_t)(delta_t_seconds & 0xFF);

    // Байт 11: TTL (Time to Live) для Mesh-маршрутизації.
    // Початкове життя пакета = 3 стрибки.
    lora_payload[11] = 3;

    // Обнуляємо лічильник після архівації
    acoustic_events = 0;

    // =========================================================================
    // ФАЗА 3: ПЛАВКА (Запуск Ruby та Атрактора Лоренца)
    // =========================================================================

    if (mrb) {
      mrb_value args[3];
      args[0] = mrb_fixnum_value(chaos_seed);
      args[1] = mrb_fixnum_value((int8_t)lora_payload[6]); // Температура (Зимовий щит)
      args[2] = mrb_fixnum_value(lora_payload[7]); // Акустика

      mrb_value ruby_result = mrb_funcall_argv(mrb, mrb_top_self(mrb), mrb_intern_lit(mrb, "calculate_state"), 3, args);

      // Байт 10: Біо-Контракт (Токеноміка)
      lora_payload[10] = (uint8_t)mrb_fixnum(ruby_result);
    } else {
      // Якщо VM не запустилася при старті через нестачу пам'яті
      lora_payload[10] = 0xFF;
    }

    // =========================================================================
    // ФАЗА 4: ПЕРЕДАЧА ДАНИХ (AES-256 + Mesh)
    // =========================================================================

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
    if (vcap_voltage > 2800) {
        lora_rx_flag = 0;
        Radio.Rx(500);

        uint32_t rx_start_time = HAL_GetTick();
        while((HAL_GetTick() - rx_start_time) < 600) {
            if(lora_rx_flag == 1) {
                // МИ ЗЛОВИЛИ ПАКЕТ! Розшифровуємо його.
                uint16_t blocks = incoming_lora_size / 4;
                HAL_CRYP_Decrypt(&hcryp, (uint32_t*)incoming_lora_payload, blocks, (uint32_t*)decrypted_rx_payload, 1000);

                // Сценарій А: OTA Оновлення від Королеви (Пакет починається з 0x99)
                if (decrypted_rx_payload[0] == 0x99) {
                    uint8_t chunk_idx = decrypted_rx_payload[1];
                    ota_total_chunks = decrypted_rx_payload[2];
                    uint8_t chunk_size = incoming_lora_size - 3;

                    // Явне приведення типів для розрахунку зміщення (MISRA C)
                    uint16_t offset = (uint16_t)chunk_idx * (uint16_t)chunk_size;

                    // Броня пам'яті та захист від дублікатів
                    if (!ota_chunk_received[chunk_idx] && (offset + chunk_size) <= sizeof(ota_buffer)) {
                        memcpy(&ota_buffer[offset], &decrypted_rx_payload[3], chunk_size);
                        ota_chunk_received[chunk_idx] = 1; // Маркуємо шматок як отриманий
                        ota_chunks_received++;
                        ota_bytes_received += chunk_size;

                        if (ota_chunks_received >= ota_total_chunks) {
                            Write_OTA_Contract_To_Flash(ota_buffer, ota_bytes_received);
                            NVIC_SystemReset();
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
                        uint8_t is_known_did = 0;
                        for(int i = 0; i < 3; i++) {
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
                            recent_mesh_dids[2] = recent_mesh_dids[1];
                            recent_mesh_dids[1] = recent_mesh_dids[0];
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
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR8, recent_mesh_dids[0]);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR9, recent_mesh_dids[1]);
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR10, recent_mesh_dids[2]);

    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
    HAL_ResumeTick();

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
    if (size < 255) {
        memcpy(incoming_lora_payload, payload, size);
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

    // 3. Збільшуємо TTL до 5, щоб пакет вижив довше і точно дійшов
    panic_payload[11] = 5;

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
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}
