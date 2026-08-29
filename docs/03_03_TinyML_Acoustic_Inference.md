# 03_03: TinyML Акустичний Інференс (Аналіз звуку пилки/кавітації)

---

## 🎯 Мета

Задокументувати повний аудіо-пайплайн Edge AI вузла **Soldier**: від апаратного переривання (п'єзодиск → вібрація) через збір сигналу ADC/DMA у буфер RAM, нормалізацію у float, до запуску нейромережевого інференсу та прийняття рішення (кавітація / бензопила / тиша). Цей документ є SSOT для всіх команд, що будують на результатах TinyML: EwsAlert pipeline (03_05), Payload Packing (03_01), та backend TelemetryUnpackerService (04_02).

> **Критична залежність:** `lora_payload[7]` (байт акустичних подій) та `lora_payload[10]` (bio-contract byte) залежать від результату TinyML. Блокування TinyML → порушення Proof of Growth Pipeline → зупинка мінтингу SCC.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — DSP Path B зафіксовано + **self-owned baseline приземлено** (`FW.4`, 2026-06-12): `Run_Inference` розкоментовано, `silken_net_audio_model.h` (INT8 forward-pass, §4.1), arena виміряно (§4.3). Відкриті: ARM `arm-none-eabi-size` на повному `.elf` (`FW.26`, після board-freeze) + threshold-visibility Grafana (`FW.18b`, їде з S2.2) → [`00_07 §03a`](00_07_Action_Plan_Tracker); сам confidence threshold закрито (`FW.18` → §🗄️).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Soldier lifecycle, DMA audio (Phase 1.5), DR13/14 thresholds |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Queen (EwsAlert relay) |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | `acoustic_events` → атрактор Лоренца |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Шифрування panic-пакетів EwsAlert |
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | `TelemetryLog.acoustic_events` |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `TelemetryUnpackerService`, `AlertDispatchService` |
| `firmware/soldier/main.c` · `silken_net_audio_model.h` (self-owned baseline, `FW.4`) · `_stub.h` (fallback) | Phase 1.5 + ISR; INT8 forward-pass інференс приземлено; партнерська модель — опційний апгрейд |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Статус** (SSOT): FW.4 ✅ baseline landed (machine half; ARM-size + bench residual) · FW.18b threshold · FW.25 DSP Path B |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Апаратна Платформа та Тригер](#-1-апаратна-платформа-та-тригер)
- [2. Параметри Збору Аудіо (Audio Acquisition)](#-2-параметри-збору-аудіо-audio-acquisition)
- [3. Передобробка (DSP Preprocessing)](#-3-передобробка-dsp-preprocessing)
- [4. Архітектура Моделі (TinyML Inference)](#-4-архітектура-моделі-tinyml-inference)
- [5. Логіка Прийняття Рішень (Decision Logic)](#-5-логіка-прийняття-рішень-decision-logic)
- [6. Бюджет Пам'яті (Memory Audit)](#-6-бюджет-памяті-memory-audit)
- [7. Інтеграція з Іншими Модулями](#-7-інтеграція-з-іншими-модулями)
- [8. Верифікація TRL 7 — Чеклист](#-8-верифікація-trl-7--чеклист)
- [10. Mongabay Pivot — 5-й клас «Fauna Activity» та біорізноманіття як D-MRV сигнал](#-10-mongabay-pivot--5-й-клас-fauna-activity-та-біорізноманіття-як-d-mrv-сигнал)
- [11. OTA Model Format та Federated Learning Pipeline](#-11-ota-model-format-та-federated-learning-pipeline)
<!-- TOC:AUTO:END -->

---

## 🎵 1. Апаратна Платформа та Тригер

### 1.1 Мікроконтролер

**MCU:** STM32WLE5JC — ARM Cortex-M4 @ 48 MHz + інтегрований SX1262 LoRa трансивер

| Характеристика | Значення |
|----------------|----------|
| Ядро | ARM Cortex-M4 **без FPU** (сімейство STM32WL його не має — слово "FPU" відсутнє у DS13105/RM0461; увесь float — software `__aeabi_*`, ABI `-mfloat-abi=soft`) |
| Тактова частота | 48 MHz |
| Flash | 256 KB |
| SRAM | 64 KB |
| Споживання (STOP2) | 300 nA (RTC-only — [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)) |

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

Перевага над `__disable_irq()`: блокується лише конкретна EXTI0 лінія п'єзодиска, менший ризик пропуску радіо-пакетів при mesh relay. Тести: `firmware/test/test_tinyml_pipeline.c` — host-тести для vibration race-condition guard (`make -C firmware/test tinyml`).

**Фізичний сенс:** П'єзодиск фіксує механічні вібрації деревини. Бензопила → характерна вібрація частотою 50–200 Hz (обертання ланцюга). Кавітаційний колапс у ксилемі → ультразвукові мікроімпульси 10–100 µs.

> **⚠️ Wakeup-чутливість — interrupt-storm ризик (open, потребує bench-рішення).** П'єзо-EXTI спрацьовує на *будь-яку* вібрацію (вітер, дощ, гойдання гілок), не лише chainsaw/кавітацію; hardware-захист GPIO — лише `BAT54S` voltage-clamp ([`02_01`](02_01_Hardware_Architecture_and_BOM)), **без амплітудного порогу**. Часті хибні пробудження загрожують drain'ом 0.47 F supercap (кожне wake → ADC+TinyML цикл). NVIC race-guard (FW.11 вище) захищає від *race*, але **не** від *частоти* пробуджень. Напрямки mitigation: (1) hardware comparator/RC-поріг — будити лише при амплітуді понад chainsaw-рівень; (2) software fast-amplitude gate одразу після wake — слабка вібрація → назад у STOP2 без повного аудіо-циклу.

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
| **Частота дискретизації** | **16 kHz** | `htim2` метроном (коментар у `firmware/soldier/main.c`) |
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

**Path B зафіксовано (§3.2) — цей розділ описує дотрансформаційний стан:** модель отримує **40 log-mel ознак** від `Compute_LogMel` (RFFT + HTK mel-bank + log; §3.4), НЕ сирий time-domain сигнал. Лінійна нормалізація `[0,1)` лишається ЛИШЕ входом до `Compute_LogMel` (DC прибирається покадрово всередині).

### 3.2 Decision Matrix: Три шляхи DSP (FW.25)

> **⚠️ DSP-шлях — рішення ML-партнера, а не firmware-даність (log-mel vs MFCC):**
> повний MFCC — не єдиний і не оптимальний шлях для CNN-ESC:
>
> 1. Для CNN-based Environmental Sound Classification (наш use case, не speech
>    recognition) сучасна література (Salamon & Bello 2015 — ESC-50 benchmark;
>    Piczak 2015; **BirdNET** — найближчий аналог для fauna detection) системно
>    показує: **log-mel spectrogram > MFCC** для CNN-входу. DCT-крок MFCC
>    декорелює ознаки для GMM-HMM, але **знищує просторову структуру**, яку
>    CNN-згортки експлуатують.
> 2. CMSIS-DSP **не має готової мел-функції** — `arm_mfcc_f32` робить повний
>    MFCC pipeline до DCT (не зупиняючись на mel). Mel-bank — custom.
> 3. TensorFlow Lite Micro має офіційний **`signal::microfrontend`** op, який
>    виконує FFT+mel+log **всередині TFLite-графа** — firmware не потребує
>    жодного custom DSP коду.
>
> Тому **рішення про DSP — upstream від ML-партнера**, не firmware'у. Нижче
> наведено три повноцінні шляхи з honest cost analysis.
>
> ## ✅ DECISION (2026-05-22): **Path B (log-mel spectrogram) офіційно зафіксовано як baseline**
>
> Архітектурне рішення прийнято на основі: (1) Path A провалюється на класі 4
> fauna через відсутність spectral structure для layered soundscape; (2) Path C
> має більший Tensor Arena overhead на критично обмеженій SRAM (64 KB
> STM32WLE5JC); (3) ESC-літературний консенсус (Salamon & Bello 2015, BirdNET,
> ESC-50) однозначно: log-mel > MFCC > raw audio для CNN-based ESC; (4)
> CMSIS-DSP вже завендорено (FW.46 `extern/`; logmel FFT `arm_rfft_fast_f32`) —
> додавання Mel-bank ~1-2 KB коду без зміни toolchain.
>
> **Fallback на Path C** — лише якщо ML-партнер (якщо матеріалізується) сильно
> натисне на TFLM end-to-end через тренувальний workflow (Edge Impulse).
> **Path A — fast-path MVP** для 4-class без fauna, якщо знадобиться більша модель (партнерів нема — baseline self-owned)
> 2+ місяців; пізніше міграція на Path B.
>
> Path B = **log-mel БЕЗ DCT-кроку MFCC** (поширена помилка плутати ці терміни).
> DCT декорелює ознаки для GMM/HMM, але **знищує просторову структуру**, яку
> 2D-CNN експлуатує.

#### Path A — Raw Audio + 1D CNN

Модель приймає `float32[512]` напряму (поточна нормалізація `[0.0, 1.0]`).
1D-CNN-шари вчаться шукати features з time-domain сигналу. Це
**Google's keyword spotting** підхід (HotwordNet style).

| Аспект | Значення |
|--------|----------|
| Firmware DSP code | **0 KB** (поточна нормалізація достатня) |
| Tensor Arena estimate | **~20–40 KB** (більший — без feature compression) |
| Model size (INT8) | ~30–60 KB Flash |
| CPU per inference | ~10–25 мс @ 48 MHz |
| Сильні сторони | Нуль firmware-DSP; найшвидший шлях до FW.4 розкоментованого `Run_Inference()`. Може спрацювати для класів 0–3 (silence/wind/cavitation/chainsaw) з достатньо великим вікном (32 мс достатньо для chainsaw F0~100 Hz: 3.2 цикли) |
| Слабкі сторони | **Не оптимальний для класу 4 (fauna soundscape)** — без частотного аналізу важко відрізнити layered спектр комах+птахів+амфібій від хаотичного шуму. Модель буде більшою на 30-50%, бо вчиться "FFT-features" з нуля |
| Коли обрати | Якщо ML-партнер хоче швидкий MVP для 4 класів без fauna; або як baseline для GA-оптимізації Любченка |

#### Path B — Log-Mel Spectrogram + 2D CNN ⭐ Default recommendation

Firmware виконує FFT → power spectrum → mel filterbank → log. Модель — 2D-CNN
на ~40×N mel-spectrogram. Це **сучасний ESC-стандарт** (ESC-50, UrbanSound8K,
BirdNET). **Зупиняється до DCT** — це ключова відмінність від MFCC.

| Аспект | Значення |
|--------|----------|
| Firmware DSP code | **~3–5 KB Flash** (FFT twiddle tables + mel-bank coeffs) |
| Firmware DSP RAM | **~1.5 KB scratch** (FFT buffer + mel output) |
| Tensor Arena estimate | **~15–30 KB** (менший — features pre-extracted) |
| Model size (INT8) | ~15–30 KB Flash |
| CPU per inference | ~12–18 мс @ 48 MHz (DSP ~1.5 мс + CNN ~10–16 мс) |
| Сильні сторони | **Оптимальний для bioacoustic (fauna)** — log-mel зберігає spectral structure для CNN. Найкращі benchmarks на ESC-датасетах. Менша модель, менший inference |
| Слабкі сторони | Custom Mel filterbank implementation — CMSIS-DSP **не має** прямої функції (`arm_mfcc_*` робить full MFCC; для mel-only треба зупинитися на проміжному кроці). ~50 рядків C для Mel-bank матриці |
| Коли обрати | **Default для 5-class з fauna**. Якщо ML-партнер тренує модель на TF/Keras з `librosa.feature.melspectrogram` (стандарт для ESC tutorial) — це Path B |

#### Path C — TFLM `signal::microfrontend` op (TF Audio Frontend)

TFLite Micro має офіційний op `signal::microfrontend` (TensorFlow Audio
Frontend, [google/tflite-micro](https://github.com/tensorflow/tflite-micro)),
який виконує FFT + mel + log **всередині TFLite-графа**. Firmware подає raw
audio, frontend op виконує DSP як layer.

| Аспект | Значення |
|--------|----------|
| Firmware DSP code | **0 KB** (frontend op part of TFLM runtime) |
| Tensor Arena estimate | **~25–35 KB** (включає frontend scratch) |
| Model size (INT8) | ~20–35 KB Flash (frontend params + downstream layers) |
| CPU per inference | ~15–22 мс @ 48 MHz (frontend ~2 мс + CNN ~13–20 мс) |
| Сильні сторони | **Нуль custom DSP коду** у firmware. Офіційно підтримано Google, well-tested, identical floating-point behavior між training (Python) та inference (firmware). Standard для STM32 keyword spotting (Google Speech Commands tutorial) |
| Слабкі сторони | Лочить на TFLM-інтерпретатор (НЕ завендорено; baseline-рантайм = self-contained INT8 forward pass, §4.1). Tensor Arena трохи більший (frontend scratch). Менше control над DSP параметрами |
| Коли обрати | Якщо ML-партнер використовує Edge Impulse, Google TF Speech tutorial, або хоче "config-only" approach без firmware DSP коду |

#### Реалізаційні наслідки кожного шляху

| Артефакт | Path A | Path B | Path C |
|----------|--------|--------|--------|
| `audio_buffer[512]` normalization | ✅ як зараз | Замінити на FFT scratch | Залишити (frontend читає raw) |
| `silken_net_audio_model.h` content | Великий 1D CNN | Менший 2D CNN | CNN + frontend params |
| Mel-bank матриця у Flash | — | `const float mel_bank[40][257]` ~40 KB АБО sparse triplet ~3 KB | Embedded у TFLite graph |
| CMSIS-DSP залежність | — | `arm_rfft_fast_f32` + `arm_vlog_f32` + custom mel | — |
| FW.42 Vcap guard поведінка | Без змін (поточний 4.5 V threshold) | Без змін | Без змін |
| `fauna_feature_accumulator` shape | `float[512]` raw window | `float[40 × N_frames]` log-mel | `float[40]` per-frame від frontend |

#### Default-рекомендація та open question

**Default:** Path B (log-mel) для 5-class з fauna. Друга найкраща опція:
Path C, якщо ML-партнер обирає TFLM frontend (легше підтримувати
training↔inference parity).

**Path A** доцільний як проміжний крок: спершу 4-class MVP (без fauna)
на raw audio → потім міграція на Path B при додаванні fauna.

**Path C** — найбезпечніший вибір при наявності будь-яких сумнівів,
бо elimінує firmware-side DSP complexity та decouples ML-партнера від
firmware-роботи.

> ⚠️ **Леджер-противага Path C (2026-06-11):** TFLM-інтерпретатор + frontend-op
> додають власний RAM-оверхед (інтерпретатор/op-resolver/scratch — одиниці КБ)
> **усередині тієї самої стелі arena 7–15 КБ** (§6) — фолбек став помітно
> вужчим, ніж на момент DECISION 2026-05-22. До того ж Path B фронтенд уже
> self-owned і доведений (3-way parity + QEMU-нога) — миграційна цінність C
> впала. Якщо фолбек таки знадобиться — спершу повторити FW.26-замір з
> реальним TFLM-обвісом.

**MFCC (повний — з DCT)** — **не рекомендовано**. Усі три шляхи вище
кращі за повний MFCC для CNN-based ESC. MFCC залишається валідним
для класичного speech recognition (GMM-HMM), що не наш use case.

### 3.3 Час DSP та inference latency per path

| Операція | Path A | Path B | Path C |
|----------|--------|--------|--------|
| DMA fill (512 семплів @ 16 kHz) | 32.0 мс | 32.0 мс | 32.0 мс |
| Normalization (firmware) | ~0.05 мс | вбудовано у FFT scaling | — (frontend читає raw) |
| Window function (Hann) | — | ~0.1 мс (`arm_mult_f32`) | — |
| FFT 512-point | — | ~1.1 мс | — (вбудовано у frontend op) |
| Magnitude | — | ~0.3 мс (`arm_cmplx_mag_f32`) | — |
| Mel filterbank (40 bins) | — | ~0.4 мс (custom matrix-vector) | — |
| Log (`arm_vlog_f32`) | — | ~0.1 мс | — |
| TFLM microfrontend op | — | — | ~2.0 мс (FFT+mel+log у TFLM) |
| CNN inference | ~15–25 мс | ~10–16 мс | ~13–20 мс |
| **Загальний awake-time** | **~47–57 мс** | **~44–50 мс** | **~47–54 мс** |

Жоден з шляхів не перевищує бюджет одного awake-циклу (потрібен <250 мс для
PVD safety, з запасом). Path B має найменшу sum, але різниця < 10%.

> **⚠️ Чесність float-рядків (FPU-міф знято, 2026-06-10):** наведені часи
> float-DSP (Hann/FFT/magnitude/mel/log) рахувались у припущенні апаратного
> FPU — але **WLE5 його не має** (§1.1): CMSIS f32 виконується software
> `__aeabi_f*`, тобто float-рядки Path B реально на порядок повільніші
> (орієнтир ~5–15 мс на FFT замість ~1 мс; усе ще в межах <250 мс бюджету).
> **Інференс це не зачіпає** — наш forward-pass цілочисельний (INT8). Точні часи —
> клас C (bench, цикло-точність; QEMU її не дає). Якщо bench покаже тісний
> енергобюджет — запасний хід: Q15 fixed-point шлях (`arm_rfft_q15`),
> контракт §3.4 при цьому не змінюється (mel/log семантика та сама).

---

### 3.4 Log-Mel Feature Contract (FW.25) — конкретна специфікація

> **Призначення:** конвертувати «implementation gate» (FW.25 log-mel contract) у простий *confirm*. Нижче — повний MCU-готовий контракт log-mel ознак. Firmware (`Compute_LogMel`) і тренувальний pipeline **мусять використовувати ідентичні параметри** — інакше модель, натренована на librosa-фічах, не працюватиме на MCU-фічах. **DSP self-owned** (`Compute_LogMel`, librosa≡stdlib≡C golden-vector parity + host-тести — вже реалізовано); опційна партнер-модель тренується на ЦЬОМУ контракті, не змінює його.

#### Параметри (proposed baseline)

| Параметр | Значення | Обґрунтування (MCU + ESC) |
|----------|----------|---------------------------|
| Sample rate | **16 000 Hz** | TIM2 метроном (§2.1) |
| Frame / `n_fft` | **512** (= 32 ms) | один DMA-блок = один FFT-кадр (§2.2) |
| Window | **Hann — periodic** (`fftbins=True`, знаменник `N=512`), `win_length=512` | librosa-default; ⚠️ **НЕ `arm_hanning_f32`** (symmetric, знаменник `N−1`) — розійдеться на краях кадру > 1e-3; вшити precomputed periodic-table |
| DC-removal | **− mean кожного кадру** (перед вікном) | audio нормалізоване в `[0,1)` (велика DC ≈0.5); `melspectrogram(y=audio,…)` цього НЕ робить → обов'язково на ОБОХ сторонах |
| `hop_length` | **512** (без overlap) | 5 с / 32 мс = **156 кадрів** — точно збігається з монолітним fauna-вікном (§10.2 / ARCH.40); overlap зламав би 156-кадровий Welford |
| `n_mels` | **40** | = `MODEL_INPUT_SIZE` (stub); ESC-стандарт |
| `fmin` / `fmax` | **50 Hz / 8000 Hz** | fmax = Nyquist@16k; покриває комах 4–8 кГц, птахів 1–6, амфібій 0.5–3 (§10) |
| Mel-scale | **HTK** (`mel = 2595·log₁₀(1 + f/700)`) | замкнена формула для precompute на MCU (Slaney — кусково-лінійна, зайва складність) |
| Power | **2.0** (`|X|²`) | librosa default; `re² + im²` без sqrt |
| Mel-filter norm | **None** (сирі трикутні фільтри) | уникаємо Slaney area-нормалізації; масштаб компенсує BatchNorm моделі |
| Log | **`ln(mel + 1e-6)`** (натуральний) | `arm_vlog_f32`; floor 1e-6 проти log(0) |
| Вхід-нормалізація | **у моделі** (BatchNorm 1-й шар) | MCU видає сирий log-mel; модель нормалізує — стандарт ESC-CNN |

**Вихід:** `float[40]` на кадр (4-class: один стовпець → `Run_Inference`; fauna: 156 стовпців → Welford mean+std, §10.2).

#### Бюджет-конверт моделі (обов'язкова друга половина контракту, 2026-06-11)

> Контракт ознак вище — лише половина деплой-умови. Модель мусить вписатись у **виміряний** RAM-леджер Солдата (§6, числа там — One-Home): **tensor arena target ≤ 10 КБ** (тверда стеля 7–15 КБ залежно від mruby-капу — поруч живе виміряна mruby-куча 38 КБ), Flash 32–64 КБ INT8 (§4.3). INT8-квантизація обов'язкова; **топологію обирати під стелю, не навпаки** — «типова ESC-CNN ~16 КБ arena» фізично не деплоїться. Тренувальний крос-чек партнера контракт не гейтить (контракт наш end-to-end), але arena-конверт гейтить залізно: модель ляже у `.bss` Солдата і CI-гейт `[FW.26] ARM static-RAM` зірветься ще до bench.

#### Firmware-інтерфейс

```c
/* Один 512-семпловий кадр (32 ms @ 16 kHz) → 40 log-mel ознак.
 * audio: нормалізований [0,1) (як audio_buffer[] зараз) — DC прибирається всередині.
 * out_mel: 40 float, далі → Run_Inference(out_mel, &confidence). */
void Compute_LogMel(const float audio[512], float out_mel[40]);
```

Пайплайн: **DC-remove (− mean per-frame)** → **periodic Hann** (precomputed table) → **RFFT 512→257** (`arm_rfft_fast_f32` на ARM; портативний radix-2 для host-тестів) → power `re²+im²` (257 bins, **без `1/N`**) → **mel-bank 40×257** (precomputed трикутні, HTK, `norm=None`, sparse-triplet для Flash) → `ln(·+1e-6)`. Вихід `out_mel[0..39]` — low→high mel. Таблиці (periodic-Hann, mel-bank, golden-vectors) генеруються офлайн з `silken_ml.codegen` ([`tools/ml`](https://github.com/Alexey-Lukin/silken_net/blob/main/tools/ml)) і вшиваються як `const` у `firmware/common/logmel_*.h`.

#### Reference (канонічний оракул — `silken_ml.dsp`)

> ⚠️ **DC-removal паритет:** firmware `Compute_LogMel` прибирає DC **кожного кадру**, а `librosa.feature.melspectrogram(y=audio,…)` — **ні**. Оскільки audio нормалізоване в `[0,1)` (DC ≈ 0.5), пряме `melspectrogram` РОЗІЙДЕТЬСЯ з MCU у нижніх mel-смугах (DC після Hann тече в bins 0–3) — на порядки понад tol 1e-3. Тому фреймуємо вручну й віднімаємо mean кожного кадру:

```python
import librosa, numpy as np
SR, N_FFT, HOP, N_MELS, FMIN, FMAX = 16000, 512, 512, 40, 50, 8000

mel_fb = librosa.filters.mel(sr=SR, n_fft=N_FFT, n_mels=N_MELS,
                             fmin=FMIN, fmax=FMAX, htk=True, norm=None)   # [40, 257]
win = librosa.filters.get_window("hann", N_FFT, fftbins=True)            # PERIODIC (denom N)

frames = librosa.util.frame(audio, frame_length=N_FFT, hop_length=HOP)   # [512, n]
frames = frames - frames.mean(axis=0, keepdims=True)                     # ← DC-remove per-frame
power  = np.abs(np.fft.rfft(frames * win[:, None], axis=0)) ** 2         # [257, n], re²+im²
logmel = np.log(mel_fb @ power + 1e-6).astype(np.float32)                # [40, n]
# один стовпець logmel[:, k] = [40] = вхід Run_Inference (Path B); = байт-у-байт Compute_LogMel
```

Те саме `mel_fb` вшивається у firmware як sparse triplet. **Канонічний оракул** — `silken_ml.dsp.logmel_librosa` (training-side) ≡ `silken_ml.dsp.logmel_stdlib` (pure-stdlib, без numpy — швидкий локальний + golden-gen), parity tol 1e-6. ML-партнера нема → контракт self-owned; майбутній партнер тренує на ЦЬОМУ самому контракті (крос-чек, не гейт).

#### Статус реалізації (self-owned)

Контракт — **наш канон end-to-end** (ML-партнера нема); верифікується локально без librosa на швидкому шляху.

1. **Оракул + golden-gen** — `silken_ml.dsp` ([`tools/ml`](https://github.com/Alexey-Lukin/silken_net/blob/main/tools/ml)): librosa (training) ≡ pure-stdlib (швидкий, без numpy), parity tol 1e-6 у `ml_smoke.yml`.
2. **Firmware** — `Compute_LogMel` ([`firmware/common/logmel.c`](https://github.com/Alexey-Lukin/silken_net/blob/main/firmware/common/logmel.c); host naive-DFT reference / ARM `arm_rfft_fast_f32`) + golden-vector host-тести ([`firmware/test/test_logmel.c`](https://github.com/Alexey-Lukin/silken_net/blob/main/firmware/test/test_logmel.c), tol 1e-3). Таблиці Hann/mel-bank/golden — `silken_ml.codegen` → `firmware/common/logmel_*.h`.
3. **CMSIS-шлях доведено без плати (FW.4, 2026-06-10)** — спільне ядро перевірок `firmware/sim/logmel_parity_core.h` ганяється двічі: host-ctest (скалярний CMSIS-DSP) **і** QEMU-M4 нога (`firmware/scripts/qemu_logmel.sh`, mps2-an386, soft-float ABI WLE5 — метод [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)): golden-parity (tol 1e-3) + **stack high-water gate** навколо чистих викликів (стек після reuse-buffers — два кадрові буфери; бюджет-tripwire живе у `firmware/sim/qemu_m4/logmel_main.c`). Silicon-confirm float32 — тонка формальність bench.
4. ✅ Розкоментовано `Run_Inference` call-site (`main.c`, `FW.4`) + виміряно Tensor Arena (forward-pass: 76 B стек / 0 .bss / 972 B Flash, §4.3) — self-owned baseline ESC-50 приземлено; host-тест `test_audio_model`. ARM-elf замір — CI hal_check lane.

---

## 🧠 4. Архітектура Моделі (TinyML Inference)

### 4.1 Фреймворк

**Деплой-рантайм:** self-contained цілочисельний (INT8) forward pass у
`silken_net_audio_model.h` — фіксована топологія, gemmlowp-style requantize,
**без TFLM/CMSIS-NN залежності** (ваги → Flash `const`, активації → стек, ~0 .bss).

> ⚠️ **Примирення TFLM ↔ CMSIS-NN (2026-06-12):** це **не альтернативи** — TFLM є
> *інтерпретатором*, що на Cortex-M делегує саме в CMSIS-NN (kernel-бекенд). ⚠️ **Канон
> вирівняно 2026-07-17:** ця нота півтора місяця перелічувала решту канону, яка казала
> «CMSIS-NN» про наш рантайм — і **ставала їй алібі замість фіксу** (сам перелік теж
> застарів: частину доків полагодили, нота цього не знала). Відтепер жоден канон-док не
> зве наш деплой-рантайм «CMSIS-NN»; борг закрито в `tools/ml` (№8). Ранній запис тут
> «TFLM/X-CUBE-AI» передував виміру FW.55 (mruby 38 КБ
> → arena-стеля 7–15 КБ, §6), на якому C++-каркас TFLM (~16–20 КБ Flash + ~4 КБ
> SRAM **понад** arena) став маргінальним. Тому baseline деплоїться фіксованою
> топологією-кодогеном (pure-C, host≡ARM, нуль нового vendoring), а **TFLite/LiteRT**
> — лише train/quantize/archive-формат (`silken_ml.export` INT8 PTQ). TFLM-інтерпретатор
> лишається fallback'ом, якщо знадобиться OTA-гнучкість графів **і** виміряний
> footprint влізе. ST X-CUBE-AI (нині ST Edge AI) — опція vendor-кодогену для більшої
> партнерської моделі. Метод — `tools/ml/docs/baseline_model_program.md`.

**Джерело:** `#include "silken_net_audio_model.h"` — baseline приземлено (`FW.4`,
self-owned ESC-50); stub лишається fallback'ом через `__has_include`.

### 4.2 Класи Виходу (Output Classes)

Визначено в `firmware/soldier/main.c` (`ml_event_id`):

```c
uint8_t ml_event_id = 0;  // Результат: 0-Тиша, 1-Вітер, 2-Кавітація, 3-Пилка, 4-Фауна
```

| Class ID | Назва | Фізичний сенс | Частотна характеристика |
|----------|-------|---------------|------------------------|
| **0** | Тиша (Silence) | Фоновий шум нижче порогу | < 40 dB SPL |
| **1** | Вітер (Wind) | Аеродинамічна вібрація крони | 0.1–2 kHz, широкосмуговий |
| **2** | Кавітація (**audible-proxy**) | Водний стрес ксилеми — низькочастотний structural-слід. ⚠️ Справжня акустична емісія кавітації = ультразвук **25–150 кГц** ([`UNI.11`](00_07_Action_Plan_Tracker) EIS-джерело; літ. Tyree&Dixon 1983), **поза Nyquist-8** цього тракту → 16 кГц ловить proxy, не саму AE (див. ноту нижче) | proxy < 8 кГц; фізична AE 25–150 кГц |
| **3** | Пилка/Вандалізм (Chainsaw/Tamper) | Бензопила або механічне пошкодження | 2–8 kHz, циклічний |
| **4** *(planned, Mongabay pivot)* | Fauna Activity (Soundscape) | «Багатошаровий» хор комах/птахів/амфібій з характерними піками на світанку та в сутінках — маркер реального функціонування екосистеми | 0.5–12 kHz, ритмічний (циркадний) |

> **⚖️ Field-валідність landed-baseline (`FW.4`) per-class — НЕ плутати з цілісністю пайплайну:**
> wind/chainsaw — **реальні** (ESC-50); fauna — **interim** ESC-50-проксі (реальне = Cherkasy
> Soundscape Library, post-TRL 7); **silence + cavitation — синтетичні placeholder'и** —
> cavitation (ключовий фізіологічний клас) натреновано лише на фізично-вмотивованому
> генераторі, **поки НЕ field-валідовано**. Тому baseline-точність (число → run-provenance `tools/ml`) — метрика **цілісності пайплайну** на змішаному корпусі, **НЕ** польова
> точність детекції. Джерела/генератори per-class — `tools/ml/docs/baseline_model_program.md` §2.1.
>
> ⚠️ **Глибша межа за placeholder-статус (кавітація, 2026-07-03) — audible-proxy, не сама AE:**
> справжня акустична емісія кавітації ксилеми = ультразвук **25–150 кГц** (Tyree&Dixon 1983,
> *Plant Physiol* 72:1094; EIS-джерело [`UNI.11`](00_07_Action_Plan_Tracker) ЧДТУ ПМКТ), **поза
> Nyquist-8** цього 16 кГц-тракту (AE-подія — резонансний ringdown на несучій 100 кГц–1 МГц, НЕ
> broadband-імпульс, тож спектр не «розтягується» вниз до 8 кГц). Тому навіть із польовою
> валідацією тракт ловить лише **низькочастотний structural-слід** події, а не діагностичну
> ультразвукову частоту — `synthetic.py:gen_cavitation` генерує 5–8 кГц **під Nyquist-стелю**, не
> з фізики. Справжня ultrasonic-детекція = окремий високочастотний канал / v3 AI-chip — трек ЧДТУ
> ПМКТ ([`UNI.11`](00_07_Action_Plan_Tracker) 25–150 кГц EIS п'єзодиска). Клас лишено (Mongabay/security-контекст),
> перейменовано наміром; частота-One-Home = UNI.11. Дзеркало: 01_01 §5.4 фонон-bandgap.

> **🌿 Mongabay Pivot — 5-й клас «Fauna Activity»:** Стаття Delgado et al. (Nicoya Peninsula, Costa Rica, 119 ділянок, 16 000 годин аудіо; короткий огляд: Mongabay, травень 2026) науково підтвердила, що **акустичний фон фауни** є надійним маркером екологічного здоров'я лісу — захищені та регенеровані під PES ліси демонструють виражені піки активності на світанку/в сутінках, тоді як пасовища та монокультурні плантації — ні. Для Silken Net це означає **стратегічне розширення carbon D-MRV другим виміром — біорізноманіттям** (both/and, НЕ заміна: вуглець лишається ядром економіки, fauna додається як 5-й клас): TinyML починає не лише ловити вандалізм/кавітацію, а й безперервно доводити, що Carbon Credit прив'язаний до **живої екосистеми**, а не до мертвої посадки. Класи 0–3 залишаються (security + physiology); клас 4 додається як **окрема метрика "Fauna Activity Index"** (інтенсивність 0–63) у тому ж байті телеметрії або поряд з `acoustic_events`. Детальний план у §10 нижче.

### 4.3 Tensor Arena (SRAM Budget) — Оцінка

> ✅ **Baseline приземлено (`FW.4`, 2026-06-12):** виміряний footprint self-owned ESC-50-моделі (per-frame 40→16→5, INT8) — **972 B Flash-ваги (`const`/.rodata), ~0 .bss, ~76 B стек** (активації forward-pass) — arena **<<** стелі 7–15 КБ (§6) з гігантським запасом. Таблиця нижче — рання оцінка для TFLM-2D-CNN-класу (fallback); фактичний baseline це forward-pass, не TFLM-arena (§4.1).

| Параметр | Типова оцінка | Примітка |
|----------|---------------|---------|
| Tensor Arena Size | **~16 KB** *(типова для класу — АЛЕ виміряна стеля Солдата = 7–15 КБ, §6 леджер 2026-06-11 → target ≤ 10 КБ)* | Path B 2D-CNN на log-mel (INT8); §3.2 діапазон ~15–30 KB **не влазить** поруч із виміряною mruby-кучею (38 КБ) — INT8+prune+менша топологія обов'язкові |
| Model Size (Flash) | **32–64 KB** | INT8 квантована модель |
| Input tensor | `float32[40]` (Path B log-mel) | 1 кадр 40 mel-смуг від `Compute_LogMel` (§3.4); INT8 → `int8[40]`. (Path A 1D-raw `[512]` — superseded) |
| Output tensor | `float32[5]` або `int8[5]` | Softmax 5 класів (0–3 + fauna §10) |
| Тип моделі (очікуваний) | 2D-CNN на log-mel + Softmax (**Path B**, §3.2 DECISION) | Path A 1D-raw — superseded |

**Очікувана архітектура (Path B — log-mel вхід; точна топологія — за тренуванням):**
```
per-frame:   Input(40 log-mel) → [Conv/Dense над mel-смугами] → Dense(N_class) → Softmax
fauna (§10): Input(mean‖std log-mel) → … → Dense(5) → Softmax
```
> Path A (1D time-domain `Input(512)→Conv1D…→Dense(4)`) — **superseded** рішенням §3.2; лишається лише як 4-class raw-MVP fallback, якщо ML-партнер недоступний.

### 4.4 Сигнатура функції інференсу

```c
// Оголошення в silken_net_audio_model.h (✅ landed FW.4):
uint8_t Run_Inference(const float* buffer, float* confidence);

// Виклик у main.c (Phase 1.5, ✅ розкоментований — FW.4):
ml_event_id = Run_Inference(logmel_features, &ml_confidence);  // Path B: 40 log-mel від Compute_LogMel
```

| Параметр | Тип | Зміст |
|----------|-----|-------|
| `input_buffer` | `float*` | **40 log-mel ознак** (Path B) від `Compute_LogMel` (§3.4); сирі [0,1)-семпли більше НЕ вхід моделі |
| `confidence` | `float*` | Ймовірність найбільш впевненого класу [0.0, 1.0] |
| Повернене значення | `uint8_t` | Class ID: 0=Silence, 1=Wind, 2=Cavitation, 3=Chainsaw, 4=Fauna |

### 4.5 Latency Estimation @ 48 MHz Cortex-M4

> ⚠️ **Таблиця = рання оцінка TFLM-2D-CNN-класу (Path-A мова, fallback — §4.3), не landed-вимір** (борг №6,
> `tools/ml/docs/baseline_model_program.md`): приземлений baseline FW.4 — per-frame
> **FC 40→16→5** (§4.1), Conv1D-шарів у ньому нема; 972 B Flash / 76 B стеку ⇒ реальна
> латентність на порядок менша за рядки нижче. Тримаємо консервативний envelope свідомо
> (той самий принцип, що [`02_01 §2`](02_01_Hardware_Architecture_and_BOM) для ~200 мс);
> точне число — лише bench (клас C).

| Крок | Час |
|------|-----|
| Нормалізація (512 операцій) | ~0.05 мс |
| Conv1D шар 1 (оцінка) | ~5–15 мс |
| Conv1D шар 2 (оцінка) | ~3–8 мс |
| Dense + Softmax | ~0.5 мс |
| **Загальний Inference Latency** | **~8–24 мс** |
| **З DSP (FFT + log-mel, `Compute_LogMel`)** | **~12–28 мс** |

> Інференс-рядки FPU-агностичні (INT8/integer). DSP-доданок — див.
> чесність-ноту §3.3: WLE5 без FPU → float-DSP software, реальний доданок
> більший за табличний (точно — bench).

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
Compute_LogMel(audio_buffer, logmel_features)   ← 512 семплів → 40 log-mel (Path B, §3.4)
        ↓
[✅ FW.4: розкоментовано]
ml_event_id = Run_Inference(logmel_features, &ml_confidence) ← Інференс (40 log-mel)
        ↓
if (ml_confidence >= CRITICAL)                ← DR14, default 0.85
    │
    ├── ml_event_id == 2 (Кавітація)
    │       └── acoustic_events++              ← Лічильник для батчу
    │
    ├── ml_event_id == 3 (Пилка/Вандалізм)
    │       ├── acoustic_events++              ← ТЕЖ інкремент
    │       └── Trigger_Emergency_LoRa_TX()    ← НЕГАЙНИЙ TX без сну
    │
    └── (будь-яке CRITICAL) warning_counter = 0

else if (ml_confidence >= WARNING)            ← DR13, default 0.60
    │
    └── ml_event_id ∈ {2, 3}
            ├── acoustic_events++              ← ТЕЖ інкремент
            ├── warning_counter++
            └── 3× поспіль ⇒ Trigger_Emergency_LoRa_TX() ЛИШЕ для класу 3

else                                          ← SILENCE-зона
    └── warning_counter = 0
```

### 5.2 Маппінг на Payload та Backend

```c
// Phase 2: Bit-Pack
lora_payload[7] = (uint8_t)(acoustic_events & 0xFF); // Byte 7: Acoustic Events
// ...
// [ARCH.102] Знімок БЕЗ обнулення — споживає лише успішна передача (Фаза 4).
```

| Подія | `ml_event_id` | `ml_confidence` | Дія firmware | Backend ефект |
|-------|--------------|-----------------|--------------|---------------|
| Тиша / Вітер / Фауна | 0, 1, 4 | будь-яка | Нічого (лічильник не рухається на жодному порозі) | `lora_payload[7]` без змін |
| Кавітація | 2 | < WARNING | Нічого | `lora_payload[7]` без змін |
| Кавітація | 2 | ≥ WARNING | `acoustic_events++` · `warning_counter++` | `TelemetryLog#acoustic_events > 0` |
| **Кавітація** | **2** | **≥ CRITICAL** | **`acoustic_events++`** | **`TelemetryLog#acoustic_events > 0`** |
| Пилка | 3 | < WARNING | Нічого | `lora_payload[7]` без змін |
| Пилка | 3 | ≥ WARNING | **`acoustic_events++`** · `warning_counter++` · 3× поспіль ⇒ panic TX | `TelemetryLog#acoustic_events > 0` |
| **Пилка/Вандалізм** | **3** | **≥ CRITICAL** | **`acoustic_events++` + `Trigger_Emergency_LoRa_TX()`** | **`EwsAlert` тривога** |

> 🔴 **[ARCH.102] Лічильник НЕ «лише кавітація» — і ця таблиця доти казала протилежне.** Клас 3 інкрементує його в обох зонах; одно­порогова схема `> 0.80` вище була застарілою редакцією (пороги стали двома при FW.18 — див. §5.3 нижче й [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)). Ціна дрейфу вимірна: бекенд-коментар у `insight_generator_service` виводив із цієї сторінки гарантію **про гроші** — «this term NEVER slashes a forester for third-party logging», — тоді як стороннє лісозаготівельне пиляння лічильник таки рухає. Сьогодні лісоруба тримає лише ENV-інертність акустичного терму, а не описаний тут механізм.
>
> ⚠️ **Друга властивість, яку легко проґавити: величина рахує події за ІНТЕРВАЛ МІЖ УСПІШНИМИ ПЕРЕДАЧАМИ, а не за пробудження.** На пробудження припадає щонайбільше один інференс, тож per-wake приріст ≤ 1; накопичення дає саме перерва в передачі — відкладений по морозу цикл (`Should_Defer_TX`) чи grace-hello. Споживання йде відніманням знімка після успішного TX (One-Home — `firmware/common/acoustic_ledger.h`), незʼїдений залишок переживає STOP2 у DR0. **Отже поріг, більший за 1, досяжний лише через накопичення** — читаючи будь-яке порівняння з цим полем, питай не «скільки подій», а «за який інтервал», бо каденс пробуджень енергетичний і не сталий.

> **🎯 Калібрування `ml_confidence` (пороги FW.18) — застереження landed-baseline:** на пристрої
> `ml_confidence` = max-prob softmax над **INT8-dequant** логітами (`SNAM_OUT_SCALE`), а ECE / conf-
> at-precision у тренуванні рахувалися на **float-softmax** keras-моделі — це РІЗНІ розподіли. Пороги
> FW.18 (RTC `DR13`/`DR14`, runtime-tunable) тому калібровані не на deployed-softmax; з appearance
> польових даних — перекалібрувати на INT8-dequant-розподілі (`silken_ml.export.int_reference_logits`).
> Деталі — `tools/ml/docs/baseline_model_program.md` §2.1.

### 5.3 Emergency LoRa TX (Реакція на Бензопилу)

*Ілюстрація decision-flow, **не** бітова копія (дім розкладки — нижче).* Коли TinyML класифікує пилку (`CRITICAL`), `Trigger_Emergency_LoRa_TX` (`firmware/soldier/main.c`) **позачергово** (поза Phase 4 jitter) шле 16-байтний panic-кадр і одразу засинає:

- **DID** дерева у байтах 0..3; **`0xFF`** — маркер паніки у байті 7 (максимальна тривога);
- **[FW.29]** `PANIC_FLAG_BIT` у StatusByte (байт 10) — однозначна детекція паніки на бекенді;
- **[FW.18b]** байт 11 = `Ttl_Byte_Pack(PANIC_TTL, tinyml_threshold_invalid_count)` — підвищений TTL (5 проти `DEFAULT_TTL` 3) для глибшого mesh-проникнення + спакований invalid-counter;
- **[SEC.10]** `panic_frame_counter` (saturating @ 0xFFFF) у байтах 14..15 (BE) — anti-replay nonce (сервер рубає повтори через Redis SETNX), персиститься у DR0 негайно;
- шифрування AES-128 (ECB-ера) **або** CCM-потік (`#if FW2_CCM_ENABLED`, той самий anti-replay FC у нонсі) → негайний `Radio.Send` → `Radio.Sleep`. Гілка `ARCH26_CAD_ENABLED` подовжує преамбулу («останній зойк» поза зоною Королеви).

> **Дім бітової розкладки panic-кадру:** [`03_01 §8`](03_01_Firmware_Lifecycle_and_DMA) (binary packet format) + StatusByte [`03_04 §4.4`](03_04_mruby_Lorenz_Attractor). Тут — лише ілюстрація реакції; байтові offset'и не дублюємо, щоб копія не старіла.

**Ключові відмінності panic-пакета від стандартного:**

| Параметр | Стандартний пакет | Panic пакет |
|----------|------------------|-------------|
| TTL | `DEFAULT_TTL = 3` | `PANIC_TTL = 5` |
| Байт 7 | `acoustic_events & 0xFF` | `0xFF` (маркер паніки) |
| Timing | Після засипання + jitter | Негайно |
| Відправляється | Через Phase 4 (з jitter) | Через `Trigger_Emergency_LoRa_TX()` позачергово |
| Backend | `TelemetryLog` | `EwsAlert` (критичний) |

### 5.4 [FW.18b] OTA Threshold Validation + Invalid-Counter

Пороги WARNING/CRITICAL — OTA-updatable (FW.18, `CMD_SET_AUDIO_THRESHOLDS` `0x9D` → RTC DR13/DR14). `TinyML_Apply_Thresholds(warn_raw, crit_raw)` валідує кожен OTA-payload перед застосуванням: `TinyML_Validate_Threshold` відкидає NaN/out-of-range → default; інверсія (`!(warn < crit)`) → default обидва (інваріант `SILENCE < WARNING < CRITICAL` зберігається навіть при корумпованому RTC або зловмисно сформованому OTA). Кожна відмова інкрементує `tinyml_threshold_invalid_count` (saturating `uint8` @ 255) — production-visibility лічильник, спакований у DR1 `WARN_ESC` ([`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)).

**Wiring у телеметрію — ✅ 2026-06-10 (bit-redistribution).** Лічильник їде верхніми 5 бітами TTL-байта (байт 11): бітфілд `[thr_invalid:5 | TTL:3]`, One-Home `firmware/common/ttl_byte.h`, wire-кап 31 (= «≥31»); TTL значеннями 0..5 у 3 біти вкладається з запасом, mesh-релей декрементує лише TTL-біти і не торкається лічильника origin-Солдата. За нульового лічильника байт бітово ідентичний legacy — стара прошивка для нового бекенда виглядає як counter=0 (wire-таблиця — [`03_01 §1.6`](03_01_Firmware_Lifecycle_and_DMA)). Backend (`TelemetryUnpackerService`) маскує `mesh_ttl` до нижніх 3 біт і на ненульовий звіт інкрементує Prometheus-counter **`silkennet_tinyml_threshold_invalid_reports_total`** (без per-DID мітки — свідоме відхилення від первісного ескізу `{soldier_did}`: cardinality budget [`06_03 §2.9`](06_03_Prometheus_Observability) тримає реєстр bounded; конкретний DID і значення лічильника атрибутуються warn-логом — патерн FW.22 acoustic-overflow). Grafana alert: `rate(silkennet_tinyml_threshold_invalid_reports_total[15m]) > 0` = десь у лісі корумпований RTC або зловмисний OTA-payload — IaC готовий (✅ 2026-06-10): stat-панель + alert rule `sn-alert-tinyml-threshold-invalid` у `deploy/grafana/`. Freeze-contract goldens: `test_soldier_logic.c` (fw18b-сюїта) ↔ `telemetry_unpacker_service_spec.rb`. 👤 Лишається: імпорт у Grafana Cloud (разом із S2.2).

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
| **Tensor Arena** | (fallback TFLM) | **~8–16 KB** | SRAM лише для fallback TFLM-інтерпретатора; landed baseline (`FW.4`) = forward-pass ~76 B стек / 0 .bss (§4.1, §4.3) |
| `fauna_feature_accumulator` *(transient, fauna-only, path-dependent — see §3.2)* | `float[]` + scalar | **~256 B** (Path B/C) або **~2 KB** (Path A: raw window memory) | Welford `mean+M2` агрегація 156 feature-векторів за 5 с (Path B: log-mel coefs; Path C: frontend output; Path A: raw audio statistics). 256 B залишається валідною оцінкою для Path B/C; Path A потребує ширшої статистики (`mean+std+kurtosis` на raw envelope) — TBD |
| **Разом TinyML** | | **~11–19 KB** (Path B/C) / **~13–21 KB** (Path A) | З урахуванням Tensor Arena; +~256 B–2 KB transient під час fauna-сесії |

### 6.2 Загальний SRAM-бюджет Soldier (відомі змінні)

> Per-variable Soldier RAM — **дзеркало владаря [`03_01 §3`](03_01_Firmware_Lifecycle_and_DMA)**; правити там. Тут — лише щоб звести TinyML-ledger (arena-стеля).

| Сегмент | Розмір |
|---------|--------|
| AES key (`aes_key[4]`, AES-128 post-ARCH.42) | 16 B |
| LoRa payloads (2 × 16 B) | 32 B |
| Mesh relay buffer (16 B) | 16 B |
| Mesh DID cache (3 × 4 B, FW.21) | 12 B |
| raw_audio_buffer[512] | 1 024 B |
| audio_buffer[512] | 2 048 B |
| OTA buffer (1024 B) | 1 024 B |
| OTA chunk map (256 B) | 256 B |
| Incoming LoRa buffer (256 B) | 256 B |
| Decrypted RX buffer (256 B) | 256 B |
| mruby VM heap **(ВИМІРЯНО, FW.55 QEMU sbrk-плато, newlib-nano)** | **38 392 B** консервативно (із зонд-оверхедом ~+4-5 КБ; чистий ~34 КБ; live-set ~27 КБ — простір для капу) |
| Tensor Arena (оцінка §4.3 ~16 КБ — але див. ВИМІРЯНУ стелю нижче) | ляже у `.bss` Солдата при приземленні моделі |
| fauna_feature_accumulator *(transient, path-dependent — §3.2; лише під час fauna-сесії — §10.2)* | ~324 B (Path B: 40 mel × Welford mean+M2, `FaunaWelford` у `fauna_session.h`; sizeof-tripwire у host-тесті) / ~2 KB (Path A raw window) |
| Stack: резерв леджера 12 288 B (wle5-карта, FW.55 фіт-гейт; виміряні сліди: mruby-шлях 2 896, `Compute_LogMel` 4 660 проти tripwire 6 144 у QEMU-нозі §3.4 п.3) | 12 288 B |
| **Статика Soldier-TU (ВИМІРЯНО, ARM `.data+.bss` compile-lane FW.46)** | **5 690 B** (рядки вище ≈ 4 976 Б + дрібнота; + libc/common/HAL ≈ 2.3 КБ поза TU) |
| **Леджер: 65 536 − mruby 38 392 − stack 12 288 − статика ~8 000** | **СТЕЛЯ tensor arena ≈ 6 856 B** (консервативно) … **≈ 15 344 B** (чистий mruby ~34 КБ + стек 8 КБ) |

> ⚠️ **Виміряна стеля arena = 7–15 КБ** (2026-06-11; залежить від mruby-капу й стек-резерву) — оцінка §4.3 «~16 КБ» **не влазить** ні за якого розкладу без заходів: INT8 + prune + менша топологія (target ≤ 10 КБ arena — **бриф ML-партнерам**) та/або жорсткий `_sbrk`-кап mruby (GC-on-OOM тримає live ~27 КБ ціною GC-тиску). Точний розмір самої arena — після моделі; статику вже тримає CI-гейт `[FW.26] ARM static-RAM` (`check_ram_budget.sh --hal-objects`, per-TU бюджети: Soldier 8 192, Queen 20 480 — arena зірве гейт і змусить свідому ревізію цього леджера).

> 🌿 **`fauna_feature_accumulator` (audit-fix, ARCH.40 / §10.2 / FW.25 path-dependent):** Welford running `mean+M2` для агрегації 156 feature-векторів у межах **одного** awake-циклу (5 с моноліт — STOP2 wipe'не SRAM2, тому декомпозиція "сон-між-вікнами" заборонена). **Розмір залежить від обраного DSP-шляху (§3.2 Decision Matrix):**
> - **Path B (log-mel, default-рекомендація)** при `N_mel = 13` (⚠️ **орієнтовна reduced-dim лише для fauna-агрегату** — НЕ per-frame контракт, той = **40** mel, §3.4; фінальний fauna `N_features` open, п.3 нижче): `mean[13] = 52 B` + `M2[13] = 52 B` + `count (uint32) = 4 B` + `inference_input[mean‖std][26] = 104 B` ≈ **212 B**, округлено до **~256 B** з запасом на FFT scratch buffer.
> - **Path C (TFLM frontend)** при `N_features = 40` mel bins: `mean[40] = 160 B` + `M2[40] = 160 B` + `count = 4 B` + `inference_input[80] = 320 B` ≈ **644 B**, округлено до **~768 B**.
> - **Path A (raw window memory)**: ширша статистика на time-domain envelope (`mean+std+kurtosis+RMS+ZCR`), ~**2 KB** з повним 512-семпловим reference window для cross-correlation.
>
> RAM виділяється тільки на час fauna-сесії і звільняється перед STOP2 — звичайні класи 0–3 (32 мс post-EXTI) цей блок не використовують. Точний розмір зафіксується після (1) DSP-шляху (Path B log-mel обрано self-owned), (2) калібрувального датасету ЧДТУ ПМКТ (див. §10.5), (3) фінального вибору `N_features` для 5-class моделі.

---

## 🔗 7. Інтеграція з Іншими Модулями

### 7.1 Вихід TinyML → Payload Byte 7

```
TinyML Inference → ml_event_id → acoustic_events counter
                                         ↓
                               lora_payload[7] = (uint8_t)(acoustic_events & 0xFF)
                                         ↓
                               AES-128-ECB encrypt → Radio.Send
                                         ↓
                               Queen decrypts → CIFO Cache → CoAP PUT
                                         ↓
                               TelemetryUnpackerService → TelemetryLog#acoustic_events
                                         ↓
                               LorenzAttractorService (acoustic input z=acoustic_events)
```

### 7.2 Вихід TinyML → EwsAlert (Клас 3)

```
ml_event_id == 3 (Chainsaw) + confidence ≥ critical-поріг (АБО 3× WARNING-ескалація)
        ↓
Trigger_Emergency_LoRa_TX() [StatusByte = PANIC_FLAG (status=homeostasis!), acoustic=0xFF, TTL=5]
        ↓
Queen (CIFO cache: byte[7] = 0xFF → critical priority eviction)
        ↓
TelemetryUnpackerService: panic = status_byte & PANIC_FLAG_BIT (SEC.10 anti-replay counter)
        ↓
AlertDispatchService: panic? || bio_status_anomaly? (без термального порога)
        ↓ [SLASH-1 P0: гейт саме panic?-first — реальна пилка НЕ ставить anomaly-status]
EwsAlert(severity: :critical, alert_type: :chainsaw_detected, "(PANIC-TX)" у message)
        ↓
EwsAlert.after_create_commit → dispatch_notifications! → WebSocket / SMS / PagerDuty
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
| 1 | `silken_net_audio_model.h` закоміщено в репозиторій | ✅ Self-owned baseline (ESC-50, `FW.4`, 2026-06-12); stub лишається fallback'ом через `__has_include` |
| 2 | `Run_Inference()` розкоментовано та функціонує | ✅ Розкоментовано (`main.c`); host-тест `test_audio_model` (12 golden, class-exact + softmax) |
| 3 | `TENSOR_ARENA_SIZE` задокументовано з реального файлу | ✅ Виміряно: 76 B стек / 0 .bss / 972 B Flash-ваги (forward-pass, §4.3) |
| 4 | Memory Map верифіковано (`arm-none-eabi-size`) | 🟡 Host footprint виміряно (`silken_ml.export`); ARM `arm-none-eabi-size` — CI hal_check lane |
| 5 | Host-based тести TinyML pipeline додані | ✅ Реалізовано (`test_tinyml_pipeline.c`; `make -C firmware/test tinyml`) |
| 6 | Smoke-тест: class 2 → `acoustic_events++` верифіковано | ✅ `test_audio_model` e2e (FW.4, 2026-06-13): cavitation-golden → real `Run_Inference` → `decide` → `acoustic_events++` |
| 7 | Smoke-тест: class 3 → `Trigger_Emergency_LoRa_TX()` верифіковано | ✅ `test_audio_model` e2e: chainsaw-golden → real `Run_Inference` → `decide` → emergency TX (per-class golden coverage у `emit_golden`) |
| 8 | Confidence threshold конфігурується (не хардкод) | ✅ FW.18: dual-threshold у RTC DR13/DR14 + 19 host-tests + Soldier OTA CMD dispatcher `0x9D` (`CMD_SET_AUDIO_THRESHOLDS`) з 7 host-tests |
| 9 | DSP preprocessing задокументовано (чи є FFT в моделі) | ✅ Path B log-mel — `Compute_LogMel` (RFFT + HTK mel-bank + log; §3.1/§3.4), не сирий time-domain |
| 10 | `acoustic_events` overflow захист реалізовано | ✅ Реалізовано (FW.22: `uint8_t` + saturating increment) |
| 11 | План 5-го класу «Fauna Activity» (§10, Mongabay pivot) задокументовано | ✅ Реалізовано (цей doc §10 + cross-ref до 00_02/00_07) |

---

## 🌿 10. Mongabay Pivot — 5-й клас «Fauna Activity» та біорізноманіття як D-MRV сигнал

> ⚠️ **"Pivot" тут = augmentation, НЕ заміна:** carbon (`growth_points`→SCC) лишається ядром економіки; biodiversity — другий вимір ПОВЕРХ (5-й acoustic-клас + `biodiversity_score` метадані ForestNFT). Ратифіковано founder 2026-07-20. Дім рішення → [`E.59`](00_07_Action_Plan_Tracker).

### 10.1 Контекст та джерело

**Джерело:** Delgado et al., польове дослідження на півострові Нікойя (Коста-Ріка) — 119 ділянок різних типів ландшафту, понад 16 000 годин неперервного аудіо-моніторингу; короткий огляд: *Mongabay News*, «Can listening to a forest reveal whether it is ecologically healthy?» (травень 2026). PES (Payment for Ecosystem Services) Коста-Ріки з 1997 року компенсує лісокористувачам утримання покриву — дослідження вперше надає інструментальне підтвердження, що `forest cover ≠ forest function`.

**Ключові інструментальні висновки статті, релевантні для Silken Net:**

1. Звуковий ландшафт лісу — **багатошаровий** (комахи + птахи + амфібії), з вираженими піками **на світанку та в сутінках** (циркадний ритм).
2. **Захищені ліси та регенеровані під PES** демонструють подібний рівень акустичної активності та dawn/dusk піки.
3. **Пасовища** — піки відсутні, рівномірний фон без структури.
4. **Монокультурні плантації** — часткове відновлення soundscape, але **непослідовно** (висока дисперсія між ділянками).
5. **Супутникові дані не розрізняють** функціональну екосистему від мертвої посадки — обидві дають однаковий «зелений піксель» NDVI.

> **Стратегічна важливість для Silken Net:** Це наукове підтвердження того, що інвестор carbon credit отримує не просто токен «1 SCC = 0.5 кг CO₂», а **функціональний біорізноманіттєвий актив**. Другий вимір розширює ринкове позиціювання від «ще одного MRV для вуглецю» до **«єдиного D-MRV, що доводить і вуглець, і біорізноманіття»** — категорія, де супутникові конкуренти (Pachama, Sylvera, NCX) фундаментально обмежені.

### 10.2 Що змінюється для TinyML архітектури

| Компонент | Поточний стан (TRL 6) | Цільовий стан (post-fauna-активація) |
|-----------|----------------------|--------------------------------------|
| Кількість класів | 4 (silence/wind/cavitation/chainsaw) | **5+** (додається `4 = fauna_activity`) АБО окрема паралельна метрика «Fauna Activity Index» (0–63) |
| Pre-processing | Лінійна нормалізація `[0.0, 1.0]` | **Path B (log-mel spectrogram) — ✅ ОФІЦІЙНО ЗАФІКСОВАНО (DECISION 2026-05-22, §3.2 Decision Matrix)**. Path A залишається fast-path MVP для 4-class без fauna (якщо ML-партнер недоступний). Path C — fallback якщо ML-партнер натисне на TFLM end-to-end. MFCC з повним DCT-кроком **категорично не рекомендовано** для CNN-based ESC |
| Вікно семплінгу | 32 мс (512 семплів @ 16 кГц) | Залишається 32 мс для класів 0–3; для класу 4 — **монолітне 5-секундне акумульоване вікно** (156 послідовних 32 мс вікон → агрегація feature-векторів через Welford mean+M2; формат feature-вектора залежить від обраного DSP-шляху §3.2: Path B/C log-mel coefs ~13–40 bins, Path A time-domain статистика). **Обов'язково в одному awake-циклі без STOP2 між вікнами** — див. примітку ⚠️ нижче |
| Тригер | П'єзо-EXTI на вібрацію | Класи 0–3 — як зараз; для класу 4 — **щогодинні «акустичні семплінги»** (без вібраційного тригера) на світанку (солар-час+0..2 год) та сутінках (солар-час−2..0 год) |
| Бюджет TX | 1 байт `acoustic_events` (saturating uint8) | Без змін у packet layout; «Fauna Activity Index» транслюється через **той самий байт** у режимі fauna-семплінгу (не змішується з кавітацією — режим маркується через окремий біт у Status Byte або через циркадне вікно на backend) |

> ⚠️ **Constraint — SRAM2 wipe vs. accumulator (audit-fix, ARCH.40):** Архітектура енергозбереження Soldier'а v3 ([`03_01 §1`](03_01_Firmware_Lifecycle_and_DMA)) використовує STOP2 RTC-only з `PWR_CR1_RRSTP=1` для досягнення 300 нА deep-sleep. Це **повністю стирає SRAM2** при кожному переході в STOP2. Проміжна matrix-statistic (`mean+std` 156 log-mel-векторів) у RAM не переживе сну. RTC Backup Domain не врятує: усі 20 backup-регістрів зайняті (останній, DR15, пішов під FW.2 CCM FC — [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA)), та й один uint32 фізично не вмістив би float-матрицю. **Висновок:** fauna-сесія мусить виконуватись **монолітно за один цикл активного пробудження**: 156 циклів TIM2+DMA послідовно один за одним у межах однієї main-loop ітерації, проміжна статистика тримається в RAM, і STOP2 викликається лише після того, як фінальний `fauna_activity_index` згорнуто в один байт. Декомпозиція на «спав → 32 мс → MFCC → знов сон» — заборонена.
>
> **Freeze-contract ✅ (2026-06-11, ARCH.40):** model-незалежна половина зафіксована кодом ДО fauna-pivot — `firmware/common/fauna_session.h` (Welford mean+M2 по 40 mel-бінах + монолітний `Fauna_Run_Session`: синхронний, завершений в одному виклику — STOP2 фізично не може втрутитись) + host-тести `make -C firmware/test fauna`, включно з named-тестом `test_fauna_sampling_no_stop2_in_session` (емуляція девайс-циклу: жоден із 156 кадрів не бачить сну перед собою) і чесним abort на збої кадру. Згортка mean/var → `fauna_activity_index` (0–63) **свідомо відкладена**: формула — калібрувальне рішення після приземлення моделі й польових ground-truth. Вхідний гейт сесії — `Fauna_Should_Sample` (FW.42, §10.3).

### 10.3 Енергетичний бюджет

> ⚠️ **Енергетична вартість fauna-сесії (ARCH.39):** наївна оцінка лише ADC-струму сильно занижує — повний бюджет мусить врахувати **активний CPU-струм** під час log-mel DSP + інференсу (і `1 мА × 3.3 V × 10 с` = **33 мДж**, не 3.3 мДж). Реальна вартість ≈ **20× вища** за naive-оцінку; енергетично pivot сумісний, але потребує програмного guard'у проти brownout при низькому V_cap.

Додатковий fauna-семплінг 2× на добу (світанок + сутінки), кожен по 5 с акустичного запису @ 16 кГц = 156 послідовних вікон по 32 мс.

**Розрахунок одного 5-секундного сеансу (моноліт, див. §10.2):**

| Фаза | Струм | Тривалість | Енергія |
|------|-------|-----------|---------|
| ADC + DMA wait (LP-RUN, периферія активна) | ~1 мА @ 3.3 V | 5.0 с (повне вікно) | **16.5 мДж** |
| Active CPU: MFCC (~3 мс) + INT8 inference (~7 мс) per 32 мс window | ~12 мА @ 3.3 V | 156 × 10 мс ≈ 1.56 с | **61.8 мДж** |
| **Разом за сесію** | | | **~78.3 мДж** |
| **Разом за добу (dawn + dusk)** | | | **~156.6 мДж/добу** |

Для довідки: 1× LoRa-TX @ +14 dBm ≈ **21.8 мДж** (SF9, [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power); «38/39 мДж» = списаний +22 dBm сценарій); fauna-сесія ≈ **3.6× TX**. Бюджет EDLC 0.47F/5.5V (повний) = 7.1 Дж → fauna-доба = **~2.2 %** буфера. Енергетично pivot сумісний з EBFC+EDLC.

**Транзієнтна просадка V_cap (критичний risk):** 61.8 мДж активного інференсу за 1.56 с — це **імпульсне** навантаження ~40 мВт. Якщо сесія стартує при V_cap, близькому до `VBAT_OK ON ≈ 3.4 V`, EDLC просідає нижче порогу, Buck-конвертер відключається посеред інференсу → reset. Розрахунок:
```
ΔV @ V_cap = 3.5 V (margin 100 мВ): ≈ −37 мВ → 3.463 V (вузько над порогом)
ΔV @ V_cap = 4.5 V (margin 1100 мВ): ≈ −29 мВ → 4.471 V (комфортно)
```

**Guard clause (FW.42, обов'язковий) — дворівнева політика енергозбереження:**

| V_cap | Дія | Обґрунтування |
|---|---|---|
| **≥ 4.5 V** | ✅ Повна fauna-сесія (5 с моноліт, 156 вікон) | Margin 1100 мВ над VBAT_OK ON (3.4 V) — комфортно витримує імпульсне навантаження ~40 мВт |
| **4.0–4.5 V** | ⚠️ **Skip fauna**, продовжувати класи 0–3 (security + physiology) | Margin 600 мВ — теоретично достатньо для fauna, але без запасу на нічну деградацію EDLC. Сесія пропускається; маркер `fauna_skipped_low_vcap` через статус-біт |
| **< 4.0 V** | 🔴 Skip fauna + знизити частоту LoRa TX (energy conservation mode) | Margin < 600 мВ — критичний рівень, система зосереджується на security (chainsaw detection класу 3) |
| **< 3.5 V** | 🛑 Skip усе крім watchdog | Margin < 100 мВ над VBAT_OK ON — brownout-protection |

Це захищає систему від brownout під час циркадного вікна, коли EBFC ще не повністю зарядив EDLC після нічної просадки, **а також зберігає базову функціональність security/physiology навіть у низько-енергетичних умовах** (наприклад, тривала хмарна погода в Carpathian winter).

> 🔗 **Cross-ref [`02_03 §9.6` Сценарій C](02_03_BQ25570_MPPT_Nano_Power#-9-розрахунок-енергетичного-балансу-з-урахуванням-ккд):** математичні константи sensitivity-моделі EDLC потребують узгодження з 78.3 мДж/сесію, дворівневим V_cap-порогом (4.5 V / 4.0 V / 3.5 V) та маркерами `fauna_skipped_low_vcap` після злиття цього патчу.

### 10.4 Маппінг на Backend та Web3

```
TinyML 5-class soundscape inference (dawn/dusk windows)
        ↓
LoRa payload[7] = fauna_activity_index (0–63), маркер режиму у Status Byte
        ↓
TelemetryUnpackerService → TelemetryLog#fauna_activity_index (нова колонка, TBD post-TRL 7)
        ↓
InsightGeneratorService → AiInsight(insight_type: :biodiversity_trend)
   (enum уже існує у app/models/ai_insight.rb — джерело даних до сьогодні було невизначене;
    Mongabay pivot робить TinyML soundscape ОФІЦІЙНИМ джерелом для biodiversity_trend)
        ↓
ForestNFT (SFC) метадані → "biodiversity_score": 0.0–1.0
        ↓
RWA market: інвестор бачить не лише CO₂, а й функціональний біорізноманіттєвий індекс
```

### 10.5 Залежності та академічна координація

| Залежність | Партнер | Документ | Що потрібно |
|------------|---------|----------|-------------|
| ~~FW.4 (`Run_Inference()`) + модель~~ — ✅ **закрито self-owned** ([`00_07` FW.4](00_07_Action_Plan_Tracker) 🟢: ESC-50 baseline landed, 972 B Flash / 76 B стеку; call-site розкоментовано) | — (партнерів нема; модель НАША end-to-end) | [`03_03 §4.1`](03_03_TinyML_Acoustic_Inference) | Партнерська/польова модель = **опційний апгрейд, НЕ блокер** |
| ~~FW.25 (DSP-шлях choice gate)~~ — ✅ **вирішено self-owned**: Path B (log-mel) обрано, `Compute_LogMel` реалізовано (librosa≡stdlib≡C golden-vector parity) | — (рішення НЕ чекало партнера) | [`03_03 §3.2`](03_03_TinyML_Acoustic_Inference) | Ярмілко-консультація по SPI/DMA лишається опційною ([`03_01`](03_01_Firmware_Lifecycle_and_DMA) — дім DMA) |
| Калібрувальний датасет з dawn/dusk записами Черкаського бору | Базіло + Бондаренко (ЧДТУ ПМКТ) + Спрягайло/Гаврилюк (ЧНУ Біо-хаб) | [`00_02 §1.2`](00_02_Academic_Integration_and_IP) (ПМКТ калібрувальний датасет), [`00_02 §1.2`](00_02_Academic_Integration_and_IP) Homeostasis Baseline | Польові аудіозаписи на світанку/в сутінках на ділянках різного типу (захищений бір, регенерація, монокультура), мінімум 4 сезони |
| GA-оптимізація 5-class моделі та confidence thresholds для dawn/dusk | Любченко (ЧНУ ФОТІУС) | [`00_02 §1.1`](00_02_Academic_Integration_and_IP) | Фітнес-функція з ground-truth (data-gate = Біо-хаб); GA generic (pymoo), compute = наш робочий кластер (UNI.9 R-кластер ⊥ локальна машина) |
| Macro-Micro verification (NDVI Sentinel-2 ↔ TinyML soundscape) | наш NDVI-адаптер + Карапетян (статистика fusion) | [`00_02 §1.2`](00_02_Academic_Integration_and_IP) | NDVI band-ratio (open-data Sentinel-2) ↔ TinyML; вихід → `biodiversity_trend` (наш enum); fusion = permutation/ANOVA (Карапетян) |
| Статистика розподілів `fauna_activity_index` між ділянками | Карапетян (ЧДТУ Data Science) | [`00_02 §1.2`](00_02_Academic_Integration_and_IP) | R-аналіз, ANOVA dawn/dusk peak amplitude між ландшафтами |

### 10.6 Дорожня карта (TRL крок за кроком)

```
TRL 6 → 7  (поточний, FW.4 + FW.25):
  - Узгодити з ML-партнером шлях A/B/C за §3.2 Decision Matrix
    (default-рекомендація: Path B log-mel; fallback: Path C TFLM frontend)
  - Розкоментувати Run_Inference() з 4-class моделлю
    (Path A — без DSP; Path B — після інтеграції FFT+Mel; Path C — TFLM frontend op)
  - Верифікувати TENSOR_ARENA + RAM бюджет per chosen path

TRL 7 → 8  (Mongabay pivot, blocked by ChDTU PMKT dataset):
  - Калібрувальний датасет dawn/dusk (Черкаський бір)
  - Re-train модель → 5-class (silence/wind/cavitation/chainsaw/fauna)
    — для fauna class B/C критично кращі за A
  - OTA-deploy через TinyMlModel + OtaPackagerService

TRL 8 → 9  (production biodiversity D-MRV):
  - Macro-Micro verification (наш NDVI ↔ TinyML soundscape)
  - AiInsight#biodiversity_trend → ForestNFT metadata
```

### 10.7 Ризики та відкриті питання

1. **Tensor Arena зростання** для 5-class CNN — масштаб залежить від обраного DSP-шляху (§3.2): Path A: +30–50% RAM (~20–40 KB; модель сама вчиться features); Path B: +10–20% (~15–30 KB; features pre-extracted, менша модель); Path C: +15–25% (~25–35 KB; включає frontend scratch). Baseline (per-frame MLP) тривіально влазить (§4.3); партнерська 2D-CNN — повторний замір проти стелі §6.
2. **Шум вітру 0.5–2 кГц перетинається з амфібіями** — ризик false positives для класу 4. Mitigation: акумульоване вікно + dawn/dusk timing constraint (вночі/на світанку вітер слабший). Path B/C дають кращу spectral discrimination ніж Path A.
3. **Регіональна специфіка soundscape** — модель, натренована на Черкаському борі, може не узагальнюватись на тропіки. Potential solution: Federated Learning (вже описаний у §11.3).
4. **Чи буде fauna класифікуватись через TinyML, чи через окремий DSP-only метричний модуль (без NN)?** — alternative architecture: спектральний descriptor **(ACI — Acoustic Complexity Index, Pieretti et al. 2011) обчислюється на STM32 з FFT (тобто потребує Path B-style DSP), без NN**. Це може стати TRL-7 інкрементом до повноцінної 5-class моделі. ACI **не є** "no-FFT alternative" — це спектральний показник, не часовий; виконується на тому ж FFT-output, що й Path B mel-bank.
5. **DSP-path lock-in ризик:** Path B (custom Mel-bank) self-owned + доведено (3-way parity + QEMU + baseline приземлено) → міграція на Path C малоймовірна; червневий леджер (§3.2) показав, що TFLM-фолбек вузький (його C++-каркас з'їдає ту саму arena-стелю). «Обирати Path C з самого початку» — **застаріла порада** (передувала self-owned DSP + бюджет-виміру); Path C лишається лише документованим fallback (§4.1).

### 10.8 Резонансні концепти Silken Net (поза статтею)

Стаття Delgado підкреслює, що ліс — це **процес, а не об'єкт**. Це ідеально резонує з трьома ядрами Silken Net:

- **Lorenz Attractor** ([`03_04`](03_04_mruby_Lorenz_Attractor)) — теж описує процес (динаміку гомеостазу), а не статичний стан. Біорізноманіття стає третім вхідним сигналом до атрактора (поряд з temp і acoustic_events) — або новим входом `growth_points`/статусу (post-E.63; β більше не збурюється).
- **Proof of Growth** vs `forest cover` — токен SCC мінтиться не за наявність дерева, а за **сталий процес зростання** (курс емісії — [`05_03`](05_03_Tokenomics_SCC_and_SFC)). Біорізноманіттєвий шар робить це доведення планетарним.
- **Фізичний виконавець** (лісник Моделі A + `MaintenanceRecord` — [`00_07`](00_07_Action_Plan_Tracker) E.20) — наземний звіт теж дає дані про функцію, не про покрив. TinyML soundscape = **автоматизована заміна** суб'єктивному human report, і після ⚖️ 2026-08-24 (гільдія-маркетплейс ⚫ won't-do — [`04_02 §Forester Guild`](04_02_Business_Logic_and_Services)) це не лише зручність: наземний звіт подає той, хто зацікавлений у його змісті, датчик — ні.

> **Pitch для інвестора (короткий):** «Супутник бачить піксель. Ми чуємо ліс. PES Коста-Ріки 30 років мав цю проблему — Silken Net вирішує її TinyML-датчиком на дереві.»

---

## 🔬 11. OTA Model Format та Federated Learning Pipeline

### 11.1 Формат Моделі — TFLite (єдиний допустимий)

**Критичне обмеження:** STM32WLE5JC (ARM Cortex-M4, C/C++) **не може** виконувати Ruby/Python артефакти (`.marshal`, `.pkl`, `.h5`). Допустимі формати для OTA-оновлення моделі:

> ⚠️ **Узгодження з runtime (§4.1):** на пристрої baseline виконується **fixed-topology INT8 forward-pass** (НЕ TFLM-інтерпретатор). Тому OTA-апдейт baseline-моделі = **INT8 weight-blob** (топологія фіксована, найдешевший шлях); повний `.tflite`-граф через OTA потребував би TFLM-fallback-інтерпретатора (post-TRL 8). FlatBuffer лишається форматом квантизації/архіву + OTA-графу для fallback-шляху.

| Формат | Розширення | Допустимість | Причина |
|--------|-----------|-------------|---------|
| **TensorFlow Lite FlatBuffer** | `.tflite` | ✅ Квантизація/архів + OTA-граф | На пристрої — лише через TFLM-fallback-інтерпретатор (§4.1); baseline = fixed-topology forward-pass (OTA = weight-blob) |
| TensorFlow Lite C-array | `.h` / `.cc` | ✅ Альтернативний | Скомпільований масив `const unsigned char model[]` — вбудовується у firmware |
| X-CUBE-AI (STM) | `.c` / `.h` | ⚠️ Можливий | Проприєтарний ST; краща оптимізація для STM32, але vendor lock-in |
| Ruby Marshal | `.marshal` | ❌ Заборонено | MCU не має Ruby VM |
| Python Pickle | `.pkl` | ❌ Заборонено | MCU не має Python runtime |
| ONNX | `.onnx` | ❌ Заборонено | Немає ONNX runtime для 64 KB SRAM |

### 11.2 Квантизація — INT8 (обов'язкова)

Модель **обов'язково** повинна використовувати **INT8 post-training quantization** для розгортання на STM32WLE5JC:

- **Float32 модель:** ~50-100 KB (перевищує SRAM бюджет)
- **INT8 модель:** ~12-25 KB (вписується в Tensor Arena 8-32 KB)
- **Втрата точності:** типово < 1-2% для аудіо-класифікації (допустимо)
- **Інструмент:** `tf.lite.TFLiteConverter` з `tf.lite.Optimize.DEFAULT` + representative dataset

### 11.3 Federated Learning Pipeline (Архітектура, Post-TRL 8)

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
OtaPackagerService → 512-byte chunks → Queen poll-fetch [FW.60] → LoRa → Soldiers
```

**Ключові обмеження:**
- Rails **лише** приймає готовий `.tflite` через API, зберігає в ActiveStorage, рахує SHA-256
- Тренування виконується **поза** Rails (Python, GPU-сервер або хмарний ML pipeline)
- `TinyMlModel` AR модель зберігає: `binary_payload`, `payload_size`, `binary_sha256`, `model_version`, `quantization_type` (`:int8`)
- OTA chunk format: `[0x99][index:2][total:2][bytecode:11]` — AES-128-ECB (Queen→Soldier reflex, LoRa-ключ; режими — 03_05 §3.7), pacing 60ms

**Статус:** Не реалізовано. Post-TRL 8. Прерквізити FW.4 ✅ (inference + `model.h` приземлено) — federated retraining лишається TRL-8 надбудовою.

> 🔴 **Rails-половина сьогодні — виміряно, а не оцінено** (мігровано з [`00_07`](00_07_Action_Plan_Tracker) ARCH.71 при його архівації; трекер тримає ВІДКРИТЕ, а це заморожений факт про те, чого немає). Транспорт **існує й гілку типу вже вміє**: `OtaTransmissionWorker#fetch_firmware_record` розрізняє `tinyml`/`weights` і резолвить `TinyMlModel`. Не існує **пускача**: контролера й маршруту для TinyML-деплою в дереві нуль, `TinyMlModel#activate!` має нуль викликачів поза спеками, а `firmware_compatible?`/`min_firmware_version` через нього транзитивно мертві. Єдиний шлях створення моделі — `db/seeds.rb` (демо), тож вимір «нуль `.create` поза спеками» був би ХИБНИМ — це окремий клас промаху, коли зонд не бачить сідів.
>
> **Форма реалізації, коли дійде (щоб не виводити наново):** параметризувати `Ota::DeploymentDispatcherService` по `firmware_type` + ендпоінт із власною policy + anti-rollback у **власному просторі версій** моделі — дзеркало Rails-половини `SEC.20`, не її повторне винайдення. ⛔ До появи ДРУГОЇ моделі це чистий YAGNI: один `.tflite` у сідах не створює потреби в тракті доставки.

### 11.4 Beyond TRL 9: On-Device Learning — Edge RL та Evolutionary Algorithms

> **Контекст:** Federated Learning Pipeline вище — це **top-down** (cloud навчає → edge виконує). Це **достатньо для TRL 9**, але обмежує адаптивність: модель оновлюється раз на тижні/місяці, а кліматичні мікро-зміни відбуваються щодоби.
>
> **Майбутній напрям (Beyond TRL 9 / SRL roadmap) — Edge AI Self-Evolution:**
> - **On-device class-incremental learning:** додавання нових акустичних патернів (нові інвазивні комахи у Черкаському борі, нові типи браконьєрської техніки) без необхідності retraining у cloud. Обмежено 1–4 incremental classes на STM32WLE5JC; для повного on-device backprop потрібен AI-coprocessor (Syntiant NDP120 / Maxim MAX78000) у v3 hardware.
> - **Edge Reinforcement Learning:** tabular Q-learning з 12-state × 4-action lookup для прийняття рішень (sleep_extend / normal / sample_extra / emergency_tx); reward = days-to-next-VBAT_OK. State buffer — Flash-KV ([`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)) / SRAM (RTC DR0..DR19 повні, DR20+ не існують на WLE5 — [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA)).
> - **Координація з mruby evolutionary algorithms у [`03_04`](03_04_mruby_Lorenz_Attractor)** — спільна `device-side learning loop` між TinyML (perception) і Lorenz contract (decision).
>
> **Безпекова прірва:** self-evolution + Web3-economic rewards = attack surface для adversarial reward poisoning. Mitigation — Auto-Immune Sentinel ([`05_06 §5`](05_06_Governance_and_DAO) + [`05_06 §5`](05_06_Governance_and_DAO)).
>
> 🔴 **Compute Budget Paradox — L1 не «self-evolves» фізично, і це не оцінка, а арифметика.** Перелік вище — інвентаризація того, **чому це неможливо** у поточному hardware envelope, а не план запуску на Soldier:
>
> - **mini-GA** (4 candidate sets × multi-epoch fitness): кожна fitness-епоха = повний цикл sense+Lorenz+TX ≈ **58 мДж** ([`02_03 §9.4`](02_03_BQ25570_MPPT_Nano_Power)). 10 generations/тиждень × 4 candidates × 58 мДж = **2.3 Дж/тиждень** додатково — при повному робочому вікні іоністора **3.87 Дж** ([`02_03 §8`](02_03_BQ25570_MPPT_Nano_Power)). Перевищує бюджет у 4-6× після врахування sleep drain.
> - **Tabular Q-learning:** сам lookup дешевий, але reward «days-to-next-VBAT_OK» вимагає **тижневих** епізодів, а ε-greedy exploration з 0.1 ймовірністю «sample_extra» з'їдає весь headroom Сценарію C (+1.4 мДж/год, [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)).
> - **On-device backprop:** seconds × 12 mA на Cortex-M4 без AI-акселератора = **гарантований brownout**.
>
> **Тому інтелект ієрархічно делегований**, і навчання відбувається там, де енергобюджет легший на 4-5 порядків:
>
> | Рівень | Що відбувається | Envelope |
> |--------|----------------|----------|
> | **L1 Soldier** | Inference-only: виконання **попередньо скомпільованого** mruby bytecode + емісія 1-bit stigmergic сигналу | STM32WLE5JC + 0.47F, +1.4 мДж/год headroom |
> | **L2 Conductor** | Кластерний агрегатор: локальний GA на (σ, ρ, β) для свого кластера → candidate sets до Queen | Solar + LiFePO4 (спека відкрита — [`00_07` ARCH.1](00_07_Action_Plan_Tracker)) |
> | **L3 Queen** | Distributed parameter estimation (Lorenz) + Cluster-level Edge Retraining (TinyML → `.tflite` OTA); справжній FL лише як Queen↔Rails обмін оновленнями моделі | 20Ah LiFePO4 + Solar + LTE ([`02_05`](02_05_Queen_Hardware_and_Starlink)) |
>
> До Soldier приходить **готовий compiled bytecode через OTA** (магік `0x45544952 "RITE"`, `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000` — [`03_02`](03_02_Queen_Gateway_Firmware)). Це усуває парадокс «self-training on edge» і тримає SRL-roadmap чесним.
