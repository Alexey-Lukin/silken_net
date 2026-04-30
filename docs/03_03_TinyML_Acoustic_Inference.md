# 03_03: TinyML Акустичний Інференс (Аналіз звуку пилки/кавітації)

---

## 🎯 Мета

Задокументувати повний аудіо-пайплайн Edge AI вузла **Soldier**: від апаратного переривання (п'єзодиск → вібрація) через збір сигналу ADC/DMA у буфер RAM, нормалізацію у float, до запуску нейромережевого інференсу та прийняття рішення (кавітація / бензопила / тиша). Цей документ є SSOT для всіх команд, що будують на результатах TinyML: EwsAlert pipeline (03_05), Payload Packing (03_01), та backend TelemetryUnpackerService (04_02).

> **Критична залежність:** `lora_payload[7]` (байт акустичних подій) та `lora_payload[10]` (bio-contract byte) залежать від результату TinyML. Блокування TinyML → порушення Proof of Growth Pipeline → зупинка мінтингу SCC.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — модель інтегрована, DMA налаштовано; `Run_Inference()` закоментована
- **Пов'язані модулі:**
  - Життєвий Цикл Прошивки та DMA → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)
  - Прошивка Шлюзу Королеви → [`03_02_Queen_Gateway_Firmware`](03_02_Queen_Gateway_Firmware)
  - mruby Атрактор Лоренца → [`03_04_mruby_Lorenz_Attractor`](03_04_mruby_Lorenz_Attractor)
  - Апаратний AES-256 та Безпека → [`03_05_Hardware_AES256_and_Security`](03_05_Hardware_AES256_and_Security)
  - Моделі Даних та Сутності → [`04_01_Data_Models_and_Entities`](04_01_Data_Models_and_Entities)

---

| Компонент | Стан |
|-----------|------|
| **Piezoelectric EXTI trigger** | ✅ Реалізовано (`HAL_GPIO_EXTI_Callback`, GPIO_PIN_0) |
| **TIM2 metronome (16 kHz DMA clock)** | ✅ Реалізовано (`MX_TIM2_Init`) |
| **ADC DMA mode (512 samples)** | ✅ Реалізовано (`HAL_ADC_Start_DMA`) |
| **CPU SLEEP під час DMA** | ✅ Реалізовано (`HAL_PWR_EnterSLEEPMode` + WFI) |
| **DMA Complete ISR (`audio_ready`)** | ✅ Реалізовано (`HAL_ADC_ConvCpltCallback`) |
| **Memory barrier (`__DMB()`)** | ✅ Реалізовано (між DMA write та CPU read) |
| **12-bit → float нормалізація** | ✅ Реалізовано (`/ 4095.0f`) |
| **`Run_Inference()` виклик** | 🔴 BLOCKER — **закоментовано** (`main.c:355` — `// ml_event_id = Run_Inference(...)`) |
| **`silken_net_audio_model.h`** | 🔴 BLOCKER — **відсутній у репозиторії** |
| **Tensor Arena (SRAM budget)** | 🔴 BLOCKER — розмір невідомий з коду (визначений у `.h`) |
| **DSP preprocessing (FFT/MFCC)** | 🟡 ВІДСУТНІЙ — тільки лінійна нормалізація |
| **Confidence threshold (0.80)** | 🟡 OPEN — хардкодований, не налаштовується |
| **Decision: Cavitation → acoustic_events++** | ✅ Реалізовано (але мертве: inference закоментована) |
| **Decision: Chainsaw → Emergency LoRa TX** | ✅ Реалізовано (але мертве: inference закоментована) |
| **Host-based tests для аудіо-пайплайну** | ✅ Реалізовано (`firmware/test/test_tinyml_pipeline.c`, 25 тестів) |

---

## 🛑 Блокери

### 🔴 BLOCKER-1: `Run_Inference()` — Виклик інференсу закоментовано

**Статус:** Відкрито. Критичний. TinyML фактично не працює.

**Файл:** `firmware/soldier/main.c:355`

```c
// 5. Запускаємо "Свідомість" (Шаховий розтин звуку)
// ml_event_id = Run_Inference(audio_buffer, &ml_confidence);
```

**Вплив:**
1. `ml_event_id` завжди `0` (ініціалізовано як глобальна змінна), `ml_confidence` завжди `0.0`.
2. Перевірка `if (ml_confidence > 0.80)` **завжди false** → жодна акустична класифікація ніколи не спрацює.
3. Кавітація (`ml_event_id == 2`) ніколи не записується в `acoustic_events`.
4. Тривога бензопили (`ml_event_id == 3`) ніколи не викликає `Trigger_Emergency_LoRa_TX()`.
5. `lora_payload[7]` (acoustic byte) завжди `0` — дані в хмарі є артефактом, не реальними вимірами.

**Причина (guesstimate):** Функція `Run_Inference()` оголошена в `silken_net_audio_model.h`, який відсутній у репо (BLOCKER-2). Закоментування — тимчасовий workaround для компіляції.

**Необхідна дія:**
- Додати `silken_net_audio_model.h` до репозиторію (BLOCKER-2).
- Розкоментувати `ml_event_id = Run_Inference(audio_buffer, &ml_confidence);`.
- Провести smoke-тест: запустити з тестовим сигналом, перевірити `ml_event_id` та `ml_confidence`.

**Блокує:** Весь TinyML пайплайн, EwsAlert (03_05), Proof of Growth (05_02).

---

### 🔴 BLOCKER-2: `silken_net_audio_model.h` відсутній у репозиторії

**Статус:** Відкрито. Критичний. Репозиторій не компілюється з TinyML.

**Файл:** `firmware/soldier/main.c:21`

```c
// Підключаємо скомпільовану нейромережу TinyML
#include "silken_net_audio_model.h"
```

**Вплив:**
1. `Run_Inference()`, `TENSOR_ARENA_SIZE`, та всі константи моделі визначені виключно в цьому файлі.
2. Без нього неможливо знати: розмір Tensor Arena, сигнатуру функції інференсу, кількість шарів, тип квантизації.
3. SSOT для Edge AI є неповним — Wiki не може зафіксувати ключові параметри.
4. Будь-який розробник, що клонує репо, отримає помилку компіляції в режимі з TinyML.

**Необхідна дія:**
- Закомітити `silken_net_audio_model.h` у `firmware/soldier/` (якщо модель не є комерційною таємницею).
- Або надати stub-версію з реальними константами (`TENSOR_ARENA_SIZE`, `NUM_CLASSES` тощо) для документування.
- Документувати архітектуру моделі в цій Wiki (кількість шарів, тип: TFLite/X-CUBE-AI, розмір).

**Блокує:** Компіляція firmware, повнота SSOT, будь-яка OTA оновлення моделі.

---

### 🔴 BLOCKER-3: Tensor Arena — розмір SRAM під час інференсу невідомий

**Статус:** Відкрито. Критичний для планування RAM-бюджету.

**Вплив:**
1. `TENSOR_ARENA_SIZE` визначений у `silken_net_audio_model.h` (відсутній).
2. STM32WLE5JC має лише **64 KB SRAM**. Аудіо-буфери вже займають ~3.1 KB:
   - `raw_audio_buffer[512]` → **1024 B**
   - `audio_buffer[512]` → **2048 B**
   - Разом: **3072 B** (4.7% SRAM)
3. Tensor Arena типово займає **8–32 KB** для моделей класифікації аудіо на CMSIS-NN.
4. Якщо Tensor Arena + аудіо-буфери + решта heap/stack перевищать 64 KB → **Stack Overflow → HardFault → IWDG reset**.

**Розрахунок залишкового SRAM:**

| Сегмент | Розмір |
|---------|--------|
| `raw_audio_buffer[512]` (uint16_t) | 1 024 B |
| `audio_buffer[512]` (float) | 2 048 B |
| LoRa/OTA/Mesh буфери (з 03_01) | ~1 800 B |
| mruby VM heap | ~4 096 B |
| **Разом відомих змінних** | **~9 000 B** |
| **Залишок для Tensor Arena** | **~54 000 B** |
| **Залишок мінус типовий stack (8 KB)** | **~46 000 B** |

Теоретично достатньо, але без фактичного значення `TENSOR_ARENA_SIZE` — ризик реальний.

**Необхідна дія:**
- Отримати та зафіксувати `TENSOR_ARENA_SIZE` з `silken_net_audio_model.h`.
- Провести Memory Map аналіз (`arm-none-eabi-size firmware.elf`) та задокументувати результат.
- Якщо Tensor Arena > 32 KB → розглянути зменшення `ota_buffer[1024]` (1 KB → 512 B) або зменшення аудіо-вікна.

**Блокує:** Безпечна робота системи, SRAM planning, OTA updates.

---

### ✅ BLOCKER-4: Host-based тести для TinyML аудіо-пайплайну (Реалізовано)

**Статус:** Виправлено. `firmware/test/test_tinyml_pipeline.c` додано з 25 тестами.

**Покриття:**
- Audio normalization (boundary values: 0, 2047, 4095, full 512-element buffer)
- Confidence threshold (0.80): below, exactly at, just above, max 1.0
- All 4 event classes: silence (no action), wind (no action), cavitation (acoustic_events++), chainsaw (Emergency TX)
- Acoustic events saturation (FW.12/FW.22): uint8 cap at 255
- Vibration race condition guard (FW.11): NVIC-level read-and-clear atomicity
- Multi-cycle accumulation: 10 consecutive cavitations, mixed events

**Залишкові обмеження:**
- Mock `Run_Inference()` — тести перевіряють decision logic, не саму нейромережу
- Реальний ISR timing та DMA race conditions не тестуються в host-based середовищі
- `HAL_ADC_Start_DMA` return code (`HAL_BUSY`) не тестується

**Закриває:** TRL 7 checklist item #5, FW.15 (частково)

---

### 🟡 BLOCKER-5: Відсутній DSP крок — тільки лінійна нормалізація

**Статус:** Відкрито. Архітектурне обмеження.

**Файл:** `firmware/soldier/main.c:350-353`

```c
// 4. Швидко переводимо 12-бітні RAW-дані у Float для TinyML
for(int i = 0; i < 512; i++) {
    audio_buffer[i] = (float)raw_audio_buffer[i] / 4095.0f; // Нормалізація 0.0 - 1.0
}
```

**Поточний пайплайн:** `ADC raw (12-bit) → linear normalization [0.0, 1.0] → model input`

**Проблема:**
1. Відсутній FFT / MFCC (Mel-frequency cepstral coefficients) — стандартний підхід для аудіо-класифікації.
2. Модель отримує сирий time-domain сигнал замість частотних ознак.
3. Без частотного аналізу складно відрізнити шум бензопили (2–8 kHz) від кавітаційних мікротріщин (5–20 kHz) та вітру (< 1 kHz).
4. Ефективність класифікації залежить від того, чи `silken_net_audio_model.h` реалізує DSP внутрішньо (наприклад, перший шар — STFT), що невідомо без файлу (BLOCKER-2).

**Розрахунок тривалості вікна:**
- 512 семплів × (1 / 16 000 Hz) = **32 мс** вікно
- Для бензопили (F0 ~ 100 Hz) → 32 мс = 3.2 повних цикли (достатньо для виявлення)
- Для кавітації (broadband noise) → 32 мс достатньо для енергетичного детектора

**Необхідна дія (за пріоритетом):**
1. Перевірити, чи `silken_net_audio_model.h` включає DSP preprocessing (CMSIS-DSP FFT → MFCC).
2. Якщо ні — додати `arm_rfft_fast_f32()` (CMSIS-DSP) перед `audio_buffer[]` для отримання 256-point spectrum.
3. Задокументувати фактичну архітектуру моделі у Wiki.

**Блокує:** Точність класифікації, особливо у польових умовах з фоновим шумом.

---

### 🟡 BLOCKER-6: Хардкодований поріг впевненості `0.80`

**Статус:** 🤖 Дизайн дворівневої системи порогів завершений (див. нижче). Реалізація — наступний цикл.

**Файл:** `firmware/soldier/main.c:357`

```c
if (ml_confidence > 0.80) {
```

**Проблема:**
1. Поріг 80% хардкодований у Flash. Зміна вимагає повної перекомпіляції та перепрошивки.
2. Неможливо дистанційно налаштувати (через OTA), що критично для польових умов (різні типи лісу, шум, сезони).
3. Відсутня градація: при `ml_confidence = 0.79` → ніякої дії, при `0.81` → повна тривога. Немає "попереднього сигналу" при 0.50–0.79.

**Необхідна дія:**
- Додати `confidence_threshold` до `lora_payload` або OTA-конфігурації.
- Або зберігати поріг у RTC Backup регістрі (оновлюється через OTA-команду).
- Розглянути дворівневий поріг: `WARNING_THRESHOLD (0.60)` → лічильник події; `CRITICAL_THRESHOLD (0.85)` → Emergency TX.

#### 🤖 Дизайн Dual-Threshold System (FW.18)

**Архітектура: два рівні реагування замість бінарного "так/ні"**

```
                    ┌──────────────────────────────────────────────────┐
                    │              ml_confidence                      │
                    │                                                  │
  0.0 ─────────────┼─── SILENCE ZONE ──────────────── 0.60 ──────────┤
                    │   (no action, normal noise)      │              │
                    │                                   ▼              │
                    │                           WARNING ZONE           │
                    │                    (0.60 ≤ confidence < 0.85)    │
                    │                    → acoustic_events++           │
                    │                    → warning_counter++           │
                    │                    → NO Emergency TX             │
                    │                                   │              │
                    │                                   0.85 ─────────┤
                    │                                   ▼              │
                    │                           CRITICAL ZONE          │
                    │                      (confidence ≥ 0.85)         │
                    │                    → acoustic_events++           │
                    │                    → Trigger_Emergency_LoRa_TX() │
                    │                    → IMMEDIATE action            │
                    └──────────────────────────────────────────────────┘
```

**Firmware змінні (RTC Backup Domain — зберігаються при STOP2):**

```c
// Зберігання у RTC Backup Registers (updateable via OTA CMD)
// RTC_BKP_DR6 = WARNING_THRESHOLD  (float as uint32: default 0x3F19999A = 0.60)
// RTC_BKP_DR7 = CRITICAL_THRESHOLD (float as uint32: default 0x3F59999A = 0.85)

// Runtime variables
uint8_t warning_counter = 0;       // Лічильник WARNING-подій між TX
#define WARNING_ESCALATION_COUNT 3  // Після 3 WARNING поспіль → downgrade до CRITICAL
```

**Логіка рішення (замість поточного `if (ml_confidence > 0.80)`):**

```c
float warning_threshold  = uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR6));
float critical_threshold = uint32_to_float(HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR7));

// Fallback якщо RTC порожній (cold start без OTA)
if (warning_threshold < 0.01f || warning_threshold > 0.99f)  warning_threshold  = 0.60f;
if (critical_threshold < 0.01f || critical_threshold > 0.99f) critical_threshold = 0.85f;

if (ml_confidence >= critical_threshold) {
    // === CRITICAL ZONE ===
    if (ml_event_id == 2) {  // Кавітація
        if (acoustic_events < 255) acoustic_events++;  // FW.22 saturating
    }
    if (ml_event_id == 3) {  // Бензопила / вандалізм
        Trigger_Emergency_LoRa_TX();   // НЕГАЙНИЙ panic TX, PANIC_TTL=5
    }
    warning_counter = 0;  // Reset — ми вже відреагували

} else if (ml_confidence >= warning_threshold) {
    // === WARNING ZONE ===
    if (ml_event_id == 2 || ml_event_id == 3) {
        if (acoustic_events < 255) acoustic_events++;  // Рахуємо, але не паніка

        warning_counter++;
        if (warning_counter >= WARNING_ESCALATION_COUNT) {
            // 3+ послідовних WARNING → ескалація в CRITICAL
            // (ймовірно реальна загроза, модель не впевнена через шум)
            if (ml_event_id == 3) {
                Trigger_Emergency_LoRa_TX();  // Ескальований alarm
            }
            warning_counter = 0;
        }
    }
} else {
    // === SILENCE ZONE ===
    warning_counter = 0;  // Reset при нормі
}
```

**OTA-оновлення порогів (через CoAP CMD downlink):**

```c
// Queen → Soldier OTA command: CMD_SET_THRESHOLDS
// Payload: [CMD_ID:1][WARNING:4][CRITICAL:4] = 9 байт
case CMD_SET_THRESHOLDS:
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR6, payload_as_uint32(warning_val));
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR7, payload_as_uint32(critical_val));
    break;
```

**Backend mirror (для серверного аналізу):**

```ruby
# app/services/telemetry_unpacker_service.rb — оновити decision matrix:
# acoustic_events > 0 && acoustic_events < 255 → WARNING-рівень подій (кавітація/шум)
# acoustic_events == 255 → saturated, ймовірна CRITICAL ситуація
# EwsAlert створюється лише при Emergency TX (panic_payload[7] = 0xFF)
```

**Maпінг подій на Payload та Backend (оновлена таблиця):**

| Подія | `ml_event_id` | `ml_confidence` | Зона | Дія firmware | Backend ефект |
|-------|:------------:|:---------------:|------|-------------|---------------|
| Тиша | 0 | будь-яка | SILENCE | Нічого | `acoustic_events == 0` |
| Вітер | 1 | будь-яка | будь-яка | Нічого | `acoustic_events == 0` |
| Кавітація | 2 | < 0.60 | SILENCE | Нічого | — |
| Кавітація | 2 | 0.60–0.84 | **WARNING** | `acoustic_events++` | `TelemetryLog#acoustic_events > 0` |
| **Кавітація** | **2** | **≥ 0.85** | **CRITICAL** | `acoustic_events++` | `TelemetryLog` + вищий пріоритет |
| Пилка | 3 | < 0.60 | SILENCE | Нічого | — |
| Пилка | 3 | 0.60–0.84 | **WARNING** | `acoustic_events++`, ескалація після 3× | Ескальований `EwsAlert` |
| **Пилка** | **3** | **≥ 0.85** | **CRITICAL** | `Trigger_Emergency_LoRa_TX()` | `EwsAlert(severity: :critical)` |

**Переваги dual-threshold:**

1. **Менше false positives:** Шум/вітер з confidence 0.65 не викликає паніку — лише лічильник
2. **Ескалація:** 3 послідовні WARNING → CRITICAL навіть без високої confidence (персистентна загроза)
3. **OTA-tune:** Для тропічного лісу (більше фонового шуму) → WARNING=0.70, CRITICAL=0.90
4. **Audit trail:** Backend бачить градацію (acoustic_events від 1 до 254 = warning; 255 = saturated/critical)
5. **RTC Backup:** Пороги зберігаються при STOP2 sleep — не потрібна Flash-перепрошивка

**Тести (додати до `test_tinyml_pipeline.c`):**

- `test_warning_threshold_below` — confidence 0.59 → no action
- `test_warning_threshold_at` — confidence 0.60 → acoustic_events++ (WARNING)
- `test_critical_threshold_below` — confidence 0.84 → acoustic_events++ but no Emergency TX
- `test_critical_threshold_at` — confidence 0.85 → Emergency TX (CRITICAL)
- `test_warning_escalation` — 3× WARNING → Emergency TX
- `test_warning_counter_reset` — SILENCE → warning_counter = 0
- `test_rtc_threshold_update` — OTA CMD → RTC DR6/DR7 оновлені
- `test_rtc_cold_start_defaults` — empty RTC → fallback 0.60/0.85

**Блокує:** Гнучкість налаштування в польових умовах, адаптивний моніторинг.

---

### ✅ BLOCKER-7: Накопичення `acoustic_events` — ВИРІШЕНО (FW.22)

**Статус:** ✅ Вирішено (Сесія 18).

**Рішення:** Тип змінено з `uint16_t` на `uint8_t` із saturating increment:
```c
uint8_t acoustic_events = 0;           // [FW.22] Saturating uint8_t
// ...
if (acoustic_events < 255) acoustic_events++;  // Saturating increment
// ...
lora_payload[7] = (uint8_t)acoustic_events;    // Direct assignment (no clamping needed)
```

8 host-based unit tests підтверджують: нуль, нормальне значення, 254→255, 255 залишається 255, ramp to max, repeated at max, packing.

Backend warning для `acoustic_events == 255` реалізовано в `TelemetryUnpackerService` (Сесія 15).

**Блокує:** Коректність даних кавітації, точність backend-аналізу.

---

## 🎵 1. Апаратна Платформа та Тригер

### 1.1 Мікроконтролер

**MCU:** STM32WLE5JC — ARM Cortex-M4 @ 48 MHz + інтегрований SX1262 LoRa трансивер

| Характеристика | Значення |
|----------------|----------|
| Ядро | ARM Cortex-M4 з FPU |
| Тактова частота | 48 MHz |
| Flash | 256 KB |
| SRAM | 64 KB |
| Споживання (STOP2) | 2.1 µA |

### 1.2 Тригер: П'єзодиск (Вібраційне Переривання)

Аудіо-пайплайн активується **виключно** при фізичній вібрації дерева, зафіксованій п'єзодиском:

```c
// ISR: GPIO_PIN_0 → встановлює прапорець
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
  if(GPIO_Pin == GPIO_PIN_0)
  {
    vibration_detected = 1;
  }
}
```

**Логіка фільтрації:** Якщо `vibration_detected == 0` на момент Phase 1.5 → аудіо-цикл повністю пропускається → STM32 не витрачає енергію на семплінг у тиші.

**[FIX FW.11] Атомарне зчитування `vibration_detected` — NVIC-ізоляція:** Щоб запобігти race condition між ISR та головним циклом (ISR може виставити прапорець між перевіркою `if (vib)` та `vib = 0`), використовується NVIC-рівнева ізоляція:

```c
// Вимикаємо лише п'єзо-переривання — SysTick, LoRa та DMA callbacks продовжують працювати
HAL_NVIC_DisableIRQ(EXTI0_IRQn);
uint8_t vib = vibration_detected;
vibration_detected = 0;
HAL_NVIC_EnableIRQ(EXTI0_IRQn);

if (vib) { /* запустити аудіо-пайплайн */ }
```

Перевага над `__disable_irq()`: блокується лише конкретна EXTI0 лінія п'єзодиска, менший ризик пропуску радіо-пакетів при mesh relay. Тести: `firmware/test/test_tinyml_pipeline.c` — 3 тести для vibration race condition guard.

**Фізичний сенс:** П'єзодиск фіксує механічні вібрації деревини. Бензопила → характерна вібрація частотою 50–200 Hz (обертання ланцюга). Кавітаційний колапс у ксилемі → ультразвукові мікроімпульси 10–100 µs.

### 1.3 Периферія TinyML

| HAL Handle | Периферія | Роль у TinyML пайплайні |
|------------|-----------|-------------------------|
| `hadc` | ADC (12-bit SAR) | Оцифровка звуку з п'єзодиска |
| `htim2` | TIM2 (32-bit timer) | Метроном DMA: задає частоту семплінгу 16 kHz |

---

## 🎙️ 2. Параметри Збору Аудіо (Audio Acquisition)

### 2.1 Технічні Параметри

| Параметр | Значення | Джерело |
|----------|----------|---------|
| **Частота дискретизації** | **16 kHz** | `htim2` метроном (коментар `main.c:55`) |
| **Розмір вікна** | **512 семплів** | `HAL_ADC_Start_DMA(..., 512)` |
| **Тривалість вікна** | **32 мс** | 512 / 16 000 Hz |
| **Роздільність АЦП** | **12-бітна** | STM32 ADC (0–4095) |
| **Формат сирих даних** | `uint16_t[512]` | `raw_audio_buffer[512]` |
| **Формат нормалізованих даних** | `float[512]` | `audio_buffer[512]` |
| **RAM для сирого буфера** | **1 024 B** | 512 × 2 байти |
| **RAM для float буфера** | **2 048 B** | 512 × 4 байти |
| **Разом RAM аудіо** | **3 072 B** | 4.7% від 64 KB SRAM |

### 2.2 DMA-Семплінг: CPU-Free Acquisition

```
П'єзодиск → ADC Channel → DMA → raw_audio_buffer[512] → ISR → audio_ready=1
                                       ↑
                           CPU у режимі SLEEP (WFI)
                           Spoживання: ~1 mA vs ~12 mA active
```

**Послідовність запуску:**

```c
// 1. Скидаємо прапорці
vibration_detected = 0;
audio_ready = 0;

// 2. Запускаємо TIM2 (метроном) та ADC у режимі DMA
HAL_TIM_Base_Start(&htim2);
HAL_ADC_Start_DMA(&hadc, (uint32_t*)raw_audio_buffer, 512);

// 3. CPU входить у SLEEP (WFI) — DMA працює автономно
HAL_SuspendTick();
while (!audio_ready) {
    __disable_irq();
    if (!audio_ready) {
        HAL_PWR_EnterSLEEPMode(PWR_MAINREGULATOR_ON, PWR_SLEEPENTRY_WFI);
    }
    __enable_irq();
}
HAL_ResumeTick();

// 4. Memory barrier: CPU гарантовано бачить свіжі дані від DMA
__DMB();
```

**Чому `__disable_irq()` + `WFI` + `__enable_irq()`?**
Класичний паттерн уникнення пропуску wake-event: якщо ISR `HAL_ADC_ConvCpltCallback` спрацює між перевіркою `while (!audio_ready)` та виконанням `WFI`, то без `__disable_irq()` IRQ вже оброблено до входу в SLEEP — CPU не отримає нового переривання і залишиться у SLEEP до наступного будь-якого IRQ, пропустивши конкретний сигнал готовності аудіо. Паттерн гарантує, що пропущений `audio_ready=1` буде виявлено одразу після `__enable_irq()`, а не чекати наступного зовнішнього переривання.

### 2.3 ISR: DMA Complete Callback

```c
// Апаратний рефлекс: викликається коли DMA записав 512-й семпл
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc)
{
    // Одна атомарна операція запису → виводить CPU зі SLEEP через pending IRQ
    audio_ready = 1;
}
```

---

## ⚙️ 3. Передобробка (DSP Preprocessing)

### 3.1 Поточний Стан: Тільки Лінійна Нормалізація

**Поточна реалізація** після завершення DMA:

```c
// 4. Швидко переводимо 12-бітні RAW-дані у Float для TinyML
for(int i = 0; i < 512; i++) {
    audio_buffer[i] = (float)raw_audio_buffer[i] / 4095.0f; // Нормалізація 0.0 - 1.0
}
```

**Перетворення:** `ADC[i] ∈ [0, 4095]` → `audio_buffer[i] ∈ [0.0, 1.0]`

**Жодного частотного аналізу:** Відсутні FFT, MFCC, Mel-bank, window function (Hann/Hamming). Модель отримує сирий time-domain сигнал. Чи є DSP preprocessing всередині `silken_net_audio_model.h` — невідомо (BLOCKER-2).

### 3.2 Стандартний Пайплайн для Аудіо-класифікації (Reference)

| Крок | Алгоритм | CMSIS-DSP функція |
|------|----------|-------------------|
| Window function | Hann (зменшує спектральний витік) | `arm_mult_f32()` з precomputed coeffs |
| FFT | 512-point Real FFT | `arm_rfft_fast_f32()` |
| Magnitude | `|Re| + j|Im|` → magnitude | `arm_cmplx_mag_f32()` |
| Mel filterbank | 40 фільтрів 0–8 kHz | Custom implementation |
| Log | `log(energy + 1e-6)` | `arm_vlog_f32()` |
| MFCC | DCT type-II | `arm_dct4_f32()` |

**Час виконання FFT 512-point @ 48 MHz Cortex-M4 з FPU:** ~1.1 мс (за даними CMSIS-DSP benchmarks).

### 3.3 Загальний час DSP (оцінка)

| Операція | Час @ 48 MHz |
|----------|--------------|
| DMA fill (512 semples @ 16kHz) | 32.0 мс |
| Нормалізація (поточна) | ~0.05 мс |
| FFT 512-point (якщо додати) | ~1.1 мс |
| MFCC (якщо додати) | ~3.0 мс |
| **Разом (поточний стан)** | **~32.05 мс** |
| **Разом (з FFT+MFCC)** | **~36.1 мс** |

---

## 🧠 4. Архітектура Моделі (TinyML Inference)

### 4.1 Фреймворк

**Очікуваний фреймворк:** TensorFlow Lite for Microcontrollers (TFLM) або ST X-CUBE-AI.
**Джерело:** `#include "silken_net_audio_model.h"` (файл відсутній — BLOCKER-2).

### 4.2 Класи Виходу (Output Classes)

Визначено в `firmware/soldier/main.c:85`:

```c
uint8_t ml_event_id = 0;  // Результат: 0-Тиша, 1-Вітер, 2-Кавітація, 3-Пилка
```

| Class ID | Назва | Фізичний сенс | Частотна характеристика |
|----------|-------|---------------|------------------------|
| **0** | Тиша (Silence) | Фоновий шум нижче порогу | < 40 dB SPL |
| **1** | Вітер (Wind) | Аеродинамічна вібрація крони | 0.1–2 kHz, широкосмуговий |
| **2** | Кавітація (Cavitation) | Мікроколапси бульбашок у ксилемі при водному стресі | 5–20 kHz, імпульсний |
| **3** | Пилка/Вандалізм (Chainsaw/Tamper) | Бензопила або механічне пошкодження | 2–8 kHz, циклічний |

### 4.3 Tensor Arena (SRAM Budget) — Оцінка

> ⚠️ Точні значення невідомі через відсутність `silken_net_audio_model.h` (BLOCKER-2). Наступні дані — типові значення для схожих архітектур.

| Параметр | Типова оцінка | Примітка |
|----------|---------------|---------|
| Tensor Arena Size | **8–16 KB** | Для CNN 1D або MobileNetV1 tiny (INT8) |
| Model Size (Flash) | **32–64 KB** | INT8 квантована модель |
| Input tensor | `float32[512]` або `int8[512]` | Залежить від квантизації |
| Output tensor | `float32[4]` або `int8[4]` | Softmax ймовірності 4 класів |
| Тип моделі (очікуваний) | CNN 1D + Softmax | Стандарт для keyword spotting |

**Очікувана архітектура (для 32ms, 16kHz, 4 класи, time-domain вхід):**
```
Input(512) → Conv1D(32, k=3) → MaxPool → Conv1D(64, k=3) → GlobalAvgPool → Dense(4) → Softmax
```

### 4.4 Сигнатура функції інференсу (очікувана)

```c
// Оголошення в silken_net_audio_model.h (недоступний)
// Очікувана сигнатура:
uint8_t Run_Inference(float* input_buffer, float* confidence);

// Виклик у main.c (закоментований — BLOCKER-1):
// ml_event_id = Run_Inference(audio_buffer, &ml_confidence);
```

| Параметр | Тип | Зміст |
|----------|-----|-------|
| `input_buffer` | `float*` | 512 нормалізованих семплів [0.0, 1.0] |
| `confidence` | `float*` | Ймовірність найбільш впевненого класу [0.0, 1.0] |
| Повернене значення | `uint8_t` | Class ID: 0=Silence, 1=Wind, 2=Cavitation, 3=Chainsaw |

### 4.5 Latency Estimation @ 48 MHz Cortex-M4

| Крок | Час |
|------|-----|
| Нормалізація (512 операцій) | ~0.05 мс |
| Conv1D шар 1 (оцінка) | ~5–15 мс |
| Conv1D шар 2 (оцінка) | ~3–8 мс |
| Dense + Softmax | ~0.5 мс |
| **Загальний Inference Latency** | **~8–24 мс** |
| **З DSP (FFT + MFCC)** | **~12–28 мс** |

---

## ⚡ 5. Логіка Прийняття Рішень (Decision Logic)

### 5.1 Повний Потік від `audio_ready = 1` до Рішення

```
DMA ConvCplt ISR: audio_ready = 1
        ↓
Main Loop: if (audio_ready == 1)
        ↓
HAL_ADC_Stop_DMA() + HAL_TIM_Base_Stop()      ← Зупинка конвеєра
        ↓
for i in [0..511]: audio_buffer[i] = raw[i] / 4095.0f   ← Нормалізація
        ↓
[BLOCKER-1: ЗАКОМЕНТОВАНО]
ml_event_id = Run_Inference(audio_buffer, &ml_confidence) ← Інференс
        ↓
if (ml_confidence > 0.80)                     ← Поріг 80%
    │
    ├── ml_event_id == 2 (Кавітація)
    │       └── acoustic_events++              ← Лічильник для батчу
    │
    └── ml_event_id == 3 (Пилка/Вандалізм)
            └── Trigger_Emergency_LoRa_TX()    ← НЕГАЙНИЙ TX без сну
```

### 5.2 Маппінг на Payload та Backend

```c
// Phase 2: Bit-Pack
lora_payload[7] = (uint8_t)(acoustic_events & 0xFF); // Byte 7: Acoustic Events
// ...
acoustic_events = 0; // Скидаємо лічильник після пакування
```

| Подія | `ml_event_id` | `ml_confidence` | Дія firmware | Backend ефект |
|-------|--------------|-----------------|--------------|---------------|
| Тиша | 0 | будь-яка | Нічого | `lora_payload[7] == 0` |
| Вітер | 1 | будь-яка | Нічого | `lora_payload[7] == 0` |
| Вітер | 1 | > 0.80 | Нічого | `lora_payload[7] == 0` |
| Кавітація | 2 | ≤ 0.80 | Нічого | `lora_payload[7] == 0` |
| **Кавітація** | **2** | **> 0.80** | **`acoustic_events++`** | **`TelemetryLog#acoustic_events > 0`** |
| Пилка | 3 | ≤ 0.80 | Нічого | `lora_payload[7] == 0` |
| **Пилка/Вандалізм** | **3** | **> 0.80** | **`Trigger_Emergency_LoRa_TX()`** | **`EwsAlert` тривога** |

### 5.3 Emergency LoRa TX (Реакція на Бензопилу)

```c
void Trigger_Emergency_LoRa_TX(void)
{
    uint8_t panic_payload[16] = {0};
    uint8_t encrypted_panic[16] = {0};

    // Байти 0-3: DID дерева (ідентифікатор)
    panic_payload[0] = (uint8_t)(tree_did >> 24);
    panic_payload[1] = (uint8_t)(tree_did >> 16);
    panic_payload[2] = (uint8_t)(tree_did >> 8);
    panic_payload[3] = (uint8_t)(tree_did & 0xFF);

    // Байт 7: 0xFF — маркер паніки (максимальна тривога)
    panic_payload[7] = 0xFF;

    // Байт 11: PANIC_TTL = 5 (стандартний TTL = 3 стрибки)
    panic_payload[11] = PANIC_TTL; // 5 стрибків замість стандартних 3

    // AES-256-ECB шифрування + негайна відправка
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)panic_payload, 4, (uint32_t*)encrypted_panic, 1000);
    Radio.Send(encrypted_panic, 16);

    HAL_Delay(100); // Час фізичного випромінювання
    Radio.Sleep();  // Економія енергії
}
```

**Ключові відмінності panic-пакета від стандартного:**

| Параметр | Стандартний пакет | Panic пакет |
|----------|------------------|-------------|
| TTL | `DEFAULT_TTL = 3` | `PANIC_TTL = 5` |
| Байт 7 | `acoustic_events & 0xFF` | `0xFF` (маркер паніки) |
| Timing | Після засипання + jitter | Негайно |
| Відправляється | Через Phase 4 (з jitter) | Через `Trigger_Emergency_LoRa_TX()` позачергово |
| Backend | `TelemetryLog` | `EwsAlert` (критичний) |

---

## 💾 6. Бюджет Пам'яті (Memory Audit)

### 6.1 SRAM-бюджет TinyML компонентів

| Змінна | Тип | Розмір | Призначення |
|--------|-----|--------|-------------|
| `raw_audio_buffer[512]` | `uint16_t` | **1 024 B** | Сирі 12-бітні семпли від ADC/DMA |
| `audio_buffer[512]` | `float` | **2 048 B** | Нормалізований float input для TinyML |
| `ml_event_id` | `uint8_t` | 1 B | Клас виходу (0–3) |
| `ml_confidence` | `float` | 4 B | Ймовірність (0.0–1.0) |
| `audio_ready` | `volatile uint8_t` | 1 B | Прапорець DMA complete |
| **Tensor Arena** | (невідомо) | **~8–16 KB** | SRAM для TFLM runtime |
| **Разом TinyML** | | **~11–19 KB** | З урахуванням Tensor Arena |

### 6.2 Загальний SRAM-бюджет Soldier (відомі змінні)

| Сегмент | Розмір |
|---------|--------|
| AES key (`aes_key[8]`) | 32 B |
| LoRa payloads (2 × 16 B) | 32 B |
| Mesh relay buffer (16 B) | 16 B |
| Mesh DID cache (8 × 4 B) | 32 B |
| raw_audio_buffer[512] | 1 024 B |
| audio_buffer[512] | 2 048 B |
| OTA buffer (1024 B) | 1 024 B |
| OTA chunk map (256 B) | 256 B |
| Incoming LoRa buffer (256 B) | 256 B |
| Decrypted RX buffer (256 B) | 256 B |
| mruby VM heap (~4 KB) | 4 096 B |
| Tensor Arena (оцінка) | ~12 288 B |
| Stack (оцінка) | ~4 096 B |
| **Разом (оцінка)** | **~25 KB** |
| **Залишок (з 64 KB)** | **~39 KB** |

> ⚠️ Точний розмір Tensor Arena невідомий. Потрібна верифікація через `arm-none-eabi-size`.

---

## 🔗 7. Інтеграція з Іншими Модулями

### 7.1 Вихід TinyML → Payload Byte 7

```
TinyML Inference → ml_event_id → acoustic_events counter
                                         ↓
                               lora_payload[7] = (uint8_t)(acoustic_events & 0xFF)
                                         ↓
                               AES-256-ECB encrypt → Radio.Send
                                         ↓
                               Queen decrypts → CIFO Cache → CoAP PUT
                                         ↓
                               TelemetryUnpackerService → TelemetryLog#acoustic_events
                                         ↓
                               LorenzAttractorService (acoustic input z=acoustic_events)
```

### 7.2 Вихід TinyML → EwsAlert (Клас 3)

```
ml_event_id == 3 (Chainsaw) + ml_confidence > 0.80
        ↓
Trigger_Emergency_LoRa_TX() [panic_payload[7] = 0xFF, TTL=5]
        ↓
Queen (CIFO cache: byte[7] = 0xFF → critical priority eviction)
        ↓
TelemetryUnpackerService detects acoustic_events = 255
        ↓
EwsAlertCreatorService → EwsAlert(severity: :critical, event_type: :chainsaw_detected)
        ↓
NotificationWorker → WebSocket / SMS / PagerDuty alert
```

### 7.3 TinyML та mruby Lorenz Attractor

```c
// Phase 3: після TinyML → Lorenz Attractor
args[2] = mrb_fixnum_value(lora_payload[7]); // Акустика → аттрактор

// У bio_contract.rb:
// calculate_state(chaos_seed, temperature, acoustic_events)
// → Lorenz перераховується з акустичним збуренням
// → bio_status byte → lora_payload[10]
```

TinyML-результат безпосередньо впливає на Lorenz Attractor — акустичні події є третім вхідним параметром для математики гомеостазу.

---

## 📋 8. Верифікація TRL 7 — Чеклист

> Для переходу з TRL 6 → TRL 7 необхідно виконати всі пункти.

| # | Критерій | Статус |
|---|----------|--------|
| 1 | `silken_net_audio_model.h` закоміщено в репозиторій | 🔴 Відкрито |
| 2 | `Run_Inference()` розкоментовано та функціонує | 🔴 Відкрито |
| 3 | `TENSOR_ARENA_SIZE` задокументовано з реального файлу | 🔴 Відкрито |
| 4 | Memory Map верифіковано (`arm-none-eabi-size`) | 🔴 Відкрито |
| 5 | Host-based тести TinyML pipeline додані | ✅ Реалізовано (`test_tinyml_pipeline.c`, 25 тестів) |
| 6 | Smoke-тест: class 2 → `acoustic_events++` верифіковано | 🔴 Відкрито |
| 7 | Smoke-тест: class 3 → `Trigger_Emergency_LoRa_TX()` верифіковано | 🔴 Відкрито |
| 8 | Confidence threshold конфігурується (не хардкод) | 🟡 Дизайн завершено (BLOCKER-6 dual-threshold 🤖). Реалізація — наступний цикл |
| 9 | DSP preprocessing задокументовано (чи є FFT в моделі) | 🟡 Відкрито |
| 10 | `acoustic_events` overflow захист реалізовано | ✅ Реалізовано (FW.22: `uint8_t` + saturating increment, 8 тестів) |

---

## 🔬 OTA Model Format та Federated Learning Pipeline

### Формат Моделі — TFLite (єдиний допустимий)

**Критичне обмеження:** STM32WLE5JC (ARM Cortex-M4, C/C++) **не може** виконувати Ruby/Python артефакти (`.marshal`, `.pkl`, `.h5`). Єдиний допустимий формат для OTA-оновлення моделі:

| Формат | Розширення | Допустимість | Причина |
|--------|-----------|-------------|---------|
| **TensorFlow Lite FlatBuffer** | `.tflite` | ✅ Єдиний | Бінарний, виконується TFLM runtime на Cortex-M4 |
| TensorFlow Lite C-array | `.h` / `.cc` | ✅ Альтернативний | Скомпільований масив `const unsigned char model[]` — вбудовується у firmware |
| X-CUBE-AI (STM) | `.c` / `.h` | ⚠️ Можливий | Проприєтарний ST; краща оптимізація для STM32, але vendor lock-in |
| Ruby Marshal | `.marshal` | ❌ Заборонено | MCU не має Ruby VM |
| Python Pickle | `.pkl` | ❌ Заборонено | MCU не має Python runtime |
| ONNX | `.onnx` | ❌ Заборонено | Немає ONNX runtime для 64 KB SRAM |

### Квантизація — INT8 (обов'язкова)

Модель **обов'язково** повинна використовувати **INT8 post-training quantization** для розгортання на STM32WLE5JC:

- **Float32 модель:** ~50-100 KB (перевищує SRAM бюджет)
- **INT8 модель:** ~12-25 KB (вписується в Tensor Arena 8-32 KB)
- **Втрата точності:** типово < 1-2% для аудіо-класифікації (допустимо)
- **Інструмент:** `tf.lite.TFLiteConverter` з `tf.lite.Optimize.DEFAULT` + representative dataset

### Federated Learning Pipeline (Архітектура, Post-TRL 8)

Тренування моделі **не може** відбуватися в Rails. Потрібен окремий ML-мікросервіс:

```
MaintenanceRecord (ground truth labels: "chainsaw confirmed" / "false positive")
       │
       ▼
Python ML Microservice (FastAPI + Celery / або Vertex AI Pipeline)
       │ 1. Fetch labeled audio features з PostgreSQL
       │ 2. Fine-tune TensorFlow/Keras модель
       │ 3. INT8 quantization → .tflite
       │ 4. Валідація на hold-out тесті (accuracy > threshold)
       │
       ▼
Rails: ActiveStorage upload .tflite → TinyMlModel.create!(binary_payload: ...)
       │ SHA-256 integrity check
       │
       ▼
OtaPackagerService → 512-byte chunks → OtaTransmissionWorker → Queen → Soldiers
```

**Ключові обмеження:**
- Rails **лише** приймає готовий `.tflite` через API, зберігає в ActiveStorage, рахує SHA-256
- Тренування виконується **поза** Rails (Python, GPU-сервер або хмарний ML pipeline)
- `TinyMlModel` AR модель зберігає: `binary_payload`, `payload_size`, `binary_sha256`, `model_version`, `quantization_type` (`:int8`)
- OTA chunk format: `[0x99][index:2][total:2][bytecode:11]` — AES-256-CBC, pacing 60ms

**Статус:** Не реалізовано. Post-TRL 8. Залежить від BLOCKER-1 (Run_Inference) та BLOCKER-2 (model.h).

---

## 📚 Пов'язані Ресурси

- **[03_01 Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA)** — загальний lifecycle Soldier, фази 0-5, Watchdog
- **[03_04 mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor)** — як `acoustic_events` впливає на атрактор
- **[03_05 Hardware AES256 and Security](03_05_Hardware_AES256_and_Security)** — шифрування panic-пакетів EwsAlert
- **[04_01 Data Models and Entities](04_01_Data_Models_and_Entities)** — модель `TelemetryLog`, поле `acoustic_events`
- **[04_02 Business Logic and Services](04_02_Business_Logic_and_Services)** — `TelemetryUnpackerService`, `EwsAlertCreatorService`
- **`firmware/soldier/main.c`** — реалізація Phase 1.5 (рядки 316–365) та ISR (рядки 731–737)
- **`firmware/soldier/silken_net_audio_model.h`** — ⚠️ відсутній (BLOCKER-2)
- **CMSIS-DSP Documentation** — `arm_rfft_fast_f32`, `arm_cmplx_mag_f32`
- **TensorFlow Lite for Microcontrollers** — https://www.tensorflow.org/lite/microcontrollers
