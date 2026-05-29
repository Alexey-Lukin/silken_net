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
  - Апаратне симетричне шифрування та Безпека → [`03_05_Hardware_Symmetric_Crypto_and_Security`](03_05_Hardware_Symmetric_Crypto_and_Security)
  - Моделі Даних та Сутності → [`04_01_Data_Models_and_Entities`](04_01_Data_Models_and_Entities)

---

### ⚙️ Стан Реалізації

| Компонент | Стан |
|-----------|------|
| **Piezoelectric EXTI trigger** | ✅ Реалізовано (`HAL_GPIO_EXTI_Callback`, GPIO_PIN_0) |
| **TIM2 metronome (16 kHz DMA clock)** | ✅ Реалізовано (`MX_TIM2_Init`) |
| **ADC DMA mode (512 samples)** | ✅ Реалізовано (`HAL_ADC_Start_DMA`) |
| **CPU SLEEP під час DMA** | ✅ Реалізовано (`HAL_PWR_EnterSLEEPMode` + WFI) |
| **DMA Complete ISR (`audio_ready`)** | ✅ Реалізовано (`HAL_ADC_ConvCpltCallback`) |
| **Memory barrier (`__DMB()`)** | ✅ Реалізовано (між DMA write та CPU read) |
| **12-bit → float нормалізація** | ✅ Реалізовано (`/ 4095.0f`) |
| **`Run_Inference()` виклик** | 🟡 BLOCKER-1 (частково) — оголошення доступне через stub, але call-site `main.c:1422` залишається закоментованим до інтеграції реальної моделі ML-партнером |
| **`silken_net_audio_model.h`** | 🟡 BLOCKER-2 (compilation unblocked) — реального файлу немає, але `silken_net_audio_model_stub.h` додано (2026-05-22) з контрактом (`Run_Inference` sig, `TENSOR_ARENA_SIZE=16K`, `NUM_CLASSES=5`, `ML_CLASS_*`). main.c використовує `__has_include` fallback. Дозволяє `arm-none-eabi-size firmware.elf` для реальної RAM verification |
| **Tensor Arena (SRAM budget)** | 🟡 BLOCKER-3 (estimate) — stub фіксує 16 KB (Path B baseline §3.2); реальне значення міряється після інтеграції моделі через `make size-check` або `arm-none-eabi-size firmware.elf` |
| **DSP preprocessing (FFT/MFCC)** | 🟢 Path B (log-mel) **офіційно зафіксовано** (2026-05-22, §3.2 Decision Matrix). Implementation gate — ML-партнер тренує з `librosa.feature.melspectrogram` (без DCT) + firmware додає CMSIS-DSP Mel-bank |
| **Confidence threshold (0.80)** | ✅ FW.18: dual-threshold у RTC DR13/DR14 (defaults 0.60/0.85), OTA-tunable через `CMD_SET_AUDIO_THRESHOLDS` (опкод `0x9D`) — Soldier dispatcher та 7 host-тестів імплементовано (`firmware/soldier/main.c:1003-1108`, `firmware/test/test_soldier_logic.c:4436-4442`). |
| **OTA threshold invalid counter** | ✅ Реалізовано (2026-05-22): `tinyml_threshold_invalid_count` (saturating uint8) у `firmware/soldier/main.c §1.11` — інкрементується на NaN/out-of-range/inversion. 7 host-тестів у `test_tinyml_pipeline.c`. Wiring до 21-byte packet — TBD. |
| **Decision: Cavitation → acoustic_events++** | ✅ Реалізовано (але мертве: inference закоментована) |
| **Decision: Chainsaw → Emergency LoRa TX** | ✅ Реалізовано (але мертве: inference закоментована) |
| **Host-based tests для аудіо-пайплайну** | ✅ Реалізовано (`firmware/test/test_tinyml_pipeline.c`, **51 тест** включно з 7 новими для invalid counter) |

---

## 🛑 Блокери

### 🟡 BLOCKER-1: `Run_Inference()` — Виклик інференсу закоментовано

**Статус:** Частково розблоковано (2026-05-22). Compilation більше не блокується (stub fallback закриває include), але call-site `main.c:1422` залишається закоментованим до інтеграції реальної моделі ML-партнером. TinyML inference поки що не виконується runtime.

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

### 🟡 BLOCKER-2: `silken_net_audio_model.h` — compilation unblocked via stub

**Статус:** Compilation unblocked (2026-05-22). `firmware/soldier/silken_net_audio_model_stub.h` додано як IP-friendly fallback з повним контрактом (`Run_Inference` signature, `TENSOR_ARENA_SIZE=16K`, `NUM_CLASSES=5`, `ML_CLASS_*` enums). `main.c` використовує `__has_include` — якщо реальна модель є, бере її; інакше падає на stub з `#warning`. Реальний `silken_net_audio_model.h` від ML-партнера залишається TBD.

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

**Виконано (2026-05-22):**
- ✅ `firmware/soldier/silken_net_audio_model_stub.h` додано — повний контракт без розкриття IP.
- ✅ `main.c:22-27` використовує `__has_include` fallback: реальна модель має пріоритет, stub — fallback з `#warning`.
- ✅ `make size-check` тепер проходить з stub (RAM budget verification без реальної моделі).

**Залишається (для ML-партнера, Бушин/Любченко):**
- Натренувати модель за Path B (log-mel, §3.2 Decision Matrix).
- Згенерувати реальний `silken_net_audio_model.h` через X-CUBE-AI або вручну з TFLite Micro.
- Розкоментувати `ml_event_id = Run_Inference(...)` у `main.c:1422`.
- Виміряти фактичний `TENSOR_ARENA_SIZE` через `arm-none-eabi-size firmware.elf` та оновити stub baseline (16 KB).

**Структура stub (актуальна):**
```c
// firmware/soldier/silken_net_audio_model_stub.h
#define ML_CLASS_SILENCE         0u
#define ML_CLASS_WIND            1u
#define ML_CLASS_CAVITATION      2u
#define ML_CLASS_CHAINSAW        3u
#define ML_CLASS_FAUNA_ACTIVITY  4u   /* Mongabay pivot, post-TRL 7 */
#define NUM_CLASSES              5u
#define MODEL_INPUT_SIZE         40u  /* Path B log-mel bands */
#define TENSOR_ARENA_SIZE        (16u * 1024u)
uint8_t Run_Inference(const float* buffer, float* confidence);
```

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

Теоретично достатньо (**~25 KB пік з fauna-вікном** — див. §7), але без фактичного `TENSOR_ARENA_SIZE` це залишається **"освіченим припущенням"**. Після розблокування `main.c` (BLOCKER-1) **першою дією** має бути:

```bash
make firmware_ram_budget   # custom target → arm-none-eabi-size firmware.elf
```

**Необхідна дія (порядок виконання):**
1. Отримати stub або реальний `silken_net_audio_model.h` (BLOCKER-2 — stub-стратегія IP-friendly).
2. Розкоментувати `Run_Inference()` (BLOCKER-1, `main.c:355`).
3. Скомпілювати firmware → запустити `arm-none-eabi-size firmware.elf` → зафіксувати фактичні `.text/.data/.bss` сегменти.
4. Порівняти з прогнозом §7 (~25 KB peak); якщо overshoot → зменшити `ota_buffer[1024]` (1 KB → 512 B) або аудіо-вікно.

**Блокує:** Безпечна робота системи, SRAM planning, OTA updates.

**[FW.26] CI gate активовано (2026-05-03):** `make -C firmware/test size-check` запускає host gcc проти `test_soldier` + `test_queen`, рахує `.bss + .data` і fail'ить якщо > 51200 байт (50 KB). Інтегровано як step у `firmware_test` job у `.github/workflows/ci.yml`. Поточна baseline: soldier=2.5 KB, queen=12.4 KB — комфортно < 50 KB запасу. Host build — placeholder (mock-структури, host-stdlib), але поділяє ті ж глобальні буфери (`raw_audio_buffer`, OTA chunk map, EMA state, mesh cache etc.), що і ARM build, тому регресія тут = регресія на target. ARM `arm-none-eabi-size` gate (`firmware_ram_budget` job) живе паралельно і автоматично активується після появи ELF artifacts (post-FW.4 lab build). Майбутні розширення (FW.21 EMA вже додав ~1 KB, ARCH.21 PVD save +0 B, FW.26 model TBD) пройдуть через свідомий budget review.

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

### 🟢 BLOCKER-5: DSP-шлях обрано — Path B (log-mel) [CLOSED 2026-05-22]

**Статус:** ✅ Choice gate **closed**. Архітектурне рішення зафіксовано як **Path B (log-mel spectrogram)** — деталі §3.2 Decision Matrix. Очікує формального підтвердження від ML-партнера (Бушин/Любченко) у training pipeline + переходу від "choice gate" до "implementation gate".

**Файл:** `firmware/soldier/main.c:1417-1419`

```c
// 4. Швидко переводимо 12-бітні RAW-дані у Float для TinyML
for(int i = 0; i < 512; i++) {
    audio_buffer[i] = (float)raw_audio_buffer[i] / 4095.0f; // Нормалізація 0.0 - 1.0
}
```

**Поточний пайплайн:** `ADC raw (12-bit) → linear normalization [0.0, 1.0] → model input`. Це валідний вхід для Path A (raw 1D CNN), але **не достатній** для Path B/C з частотним аналізом — див. §3.2 Decision Matrix.

**Реальна проблема (re-framed 2026-05-17):** Не "відсутній FFT/MFCC", а **відсутнє рішення про DSP-шлях**:

1. **Для класів 0–3** (silence/wind/cavitation/chainsaw) — кожен з трьох шляхів §3.2 принципово працює. Path A (raw 1D CNN, поточна нормалізація) може дати робочу 4-class модель для MVP без частотного аналізу.
2. **Для класу 4 fauna** (Mongabay pivot, §10) — Path A **не оптимальний**: без spectral structure layered soundscape (комахи 4–8 кГц + птахи 1–6 кГц + амфібії 0.5–3 кГц) важко відрізнити від хаотичного шуму вітру. Path B (log-mel) або C (TFLM microfrontend) дають перевагу. Це сучасний bioacoustic-ESC консенсус (Salamon & Bello 2015; BirdNET 2021).
3. **Чи `silken_net_audio_model.h` буде Path A/B/C** — невідомо без файлу (BLOCKER-2) та без рішення ML-партнера (Бушин або Любченко, [`08_02 §1.5/§1.8`](08_02_Cybernetic_and_Mathematical_Validation)).

**Розрахунок тривалості вікна:**
- 512 семплів × (1 / 16 000 Hz) = **32 мс** вікно
- Для бензопили (F0 ~ 100 Hz) → 32 мс = 3.2 повних цикли (достатньо для виявлення)
- Для кавітації (broadband noise) → 32 мс достатньо для енергетичного детектора
- Для fauna soundscape — 32 мс **недостатньо** окремо; потрібне 5 s акумульоване вікно (§10.2, ARCH.40)

**Необхідна дія (за пріоритетом):**
1. **Узгодити з ML-партнером** (Бушин/Любченко) обраний шлях за §3.2 Decision Matrix — це передує будь-якій CMSIS-DSP роботі.
2. **Залежно від обраного шляху:**
   - **Path A:** залишити поточну нормалізацію; перевести зусилля на більшу INT8 модель.
   - **Path B:** додати `arm_rfft_fast_f32()` + `arm_cmplx_mag_f32()` + custom Mel-filterbank + `arm_vlog_f32()`. **НЕ додавати `arm_mfcc_f32`** (повний MFCC з DCT — не оптимальний для CNN).
   - **Path C:** інтегрувати TFLM `signal::microfrontend` op у TFLite runtime; firmware DSP — нуль рядків коду.
3. Задокументувати фактичну архітектуру моделі у `silken_net_audio_model.h` (BLOCKER-2).

> 🎯 **Архітектурна рекомендація (review note 2026-05-22):** Враховуючи **Mongabay pivot** як стратегічний пріоритет (`§10`, 5-й клас fauna), **Path B (log-mel spectrogram) рекомендований як офіційний default**:
> - **Чому НЕ Path A:** Raw audio працює для класів 0–3 (кавітація, бензопила), але **вкрай неефективний** для біоакустики, де ключова ознака — структура звуку у **частотній області** (layered soundscape).
> - **Чому НЕ Path C:** TFLM `microfrontend` "чистіший" (firmware DSP = 0 рядків), але має **дещо більший RAM-overhead** ніж custom Mel-bank Path B. Path C залишається fallback'ом якщо ML-партнер обере його за simplicity.
> - **Дія:** Зафіксувати Path B як baseline у *Firmware_Architecture_Audit* після формального підтвердження від Бушин/Любченко. Це переводить FW.25 з "choice gate" у "implementation gate".

**Блокує:** Точність класифікації, особливо для класу 4 fauna. Класи 0–3 можуть бути MVP-сумісними з Path A (раннє розкоментування `Run_Inference()`).

> **🌿 Mongabay/Delgado 2026 — практичне посилення:** Стаття Delgado et al. описує лісовий звуковий ландшафт як **«багатошаровий» (layered soundscape)** — одночасні шари комах, птахів, амфібій з характерними піками на світанку та в сутінках. У часовій області ці шари **складно** відрізнити від рівномірного шуму вітру/дощу — подібна енергетична огинаюча, абсолютно різна спектральна структура. Це робить **Path B (log-mel) або Path C (TFLM microfrontend) сильно бажаним** для класу 4. Path A може давати робочі класи 0–3, але fauna потребує spectral features. Це переводить FW.25 з "повинні зробити MFCC" на "повинні узгодити шлях за §3.2 Decision Matrix" — стратегічна паралель Бушин ↔ TinyML, див. [`08_02` §1.5 Macro-Micro verification](08_02_Cybernetic_and_Mathematical_Validation). **Без частотних ознак біорізноманіття не вимірюється** — сенсор бачить лише «шум», як супутник бачить лише «зелений піксель».

---

### 🟡 BLOCKER-6: Хардкодований поріг впевненості `0.80`

**Статус:** 🤖 ✅ **Реалізовано (FW.18, повний)** — RTC-storage, dual-threshold decision logic та OTA CMD dispatcher (опкод `0x9D = CMD_SET_AUDIO_THRESHOLDS`) у `firmware/soldier/main.c` (секції 1.5а + 1.14, Phase 1.5). 7 host-тестів покривають happy-path/wrong-marker/CRC/inversion/short-frame/zero-warn/over-crit (`firmware/test/test_soldier_logic.c:4436-4442`). Спільний CMD-фреймворк з FW.8 (`CMD_SET_THRESHOLDS 0x9A`) залишається на Queen-стороні.

**Файл (історичний):** `firmware/soldier/main.c:357` — рядок `if (ml_confidence > 0.80)` замінено на dual-threshold zone-логіку.

**Проблема (вирішено для firmware-частини):**
1. ~~Поріг 80% хардкодований у Flash. Зміна вимагає повної перекомпіляції та перепрошивки.~~ → Тепер обидва пороги завантажуються з RTC `DR13/DR14` на boot, дефолти 0.60/0.85.
2. ~~Неможливо дистанційно налаштувати (через OTA), що критично для польових умов.~~ → Soldier dispatcher `CMD_SET_AUDIO_THRESHOLDS` (опкод `0x9D`) імплементовано: парсить 10-байтний фрейм, валідує CRC16/range/inversion, пише в RAM + DR13/DR14 через Phase 5 writeback. 7 host-тестів зелені.
3. ~~Відсутня градація: бінарне `так/ні`.~~ → Реалізовано SILENCE / WARNING / CRITICAL зони з ескалацією.

**Необхідна дія (виконана):**
- ✅ Зберігати поріг у RTC Backup регістрі — оновлюється через OTA-команду `0x9D` (Soldier `Soldier_Handle_CMD_SET_AUDIO_THRESHOLDS`, [код](../firmware/soldier/main.c)).
- ✅ Дворівневий поріг: `WARNING_THRESHOLD (0.60)` → лічильник події; `CRITICAL_THRESHOLD (0.85)` → Emergency TX.

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
// Зберігання у RTC Backup Registers (updateable via OTA CMD).
// SSOT для розташування — 03_01 §2 (Soldier RTC Backup Map).
// DR13 = WARNING_THRESHOLD  (float як uint32 bit-copy: default 0x3F19999A = 0.60f)
// DR14 = CRITICAL_THRESHOLD (float як uint32 bit-copy: default 0x3F59999A = 0.85f)
//
// Magic-маркер не використовується: cold boot RTC=0x00000000 → float 0.0f →
// не проходить діапазон [TINYML_THRESHOLD_MIN_VALID=0.01, MAX_VALID=0.99] →
// TinyML_Validate_Threshold() віддає дефолт. Інваріант warning<critical
// атомарно відновлюється через TinyML_Apply_Thresholds().

// Runtime variables
uint8_t warning_counter = 0;       // Лічильник WARNING-подій між TX
                                    // (SRAM зберігається в STOP2; reset при VBAT-loss/IWDG)
#define TINYML_WARNING_ESCALATION 3 // Після 3 WARNING поспіль → ескалація CRITICAL
```

> **⚠️ Історичне уточнення:** Оригінальний дизайн використовував `RTC_BKP_DR6/DR7`, але після оновлення SSOT-таблиці RTC у `03_01` §2 (FW.21 розширення EMA) ці регістри зайняті: `DR6 = mesh_relay_payload[12..15]`, `DR7 = tree_did`. Реалізація FW.18 використовує **DR13/DR14** з резерву `DR13..DR15`, що залишився після FW.21.

**Логіка рішення (замість поточного `if (ml_confidence > 0.80)`):**

```c
// На boot: TinyML_Apply_Thresholds() завантажує валідовану пару з DR13/DR14
// у глобальні tinyml_warning_threshold / tinyml_critical_threshold.
// При cold boot або корупції — дефолти 0.60/0.85.

if (ml_confidence >= tinyml_critical_threshold) {
    // === CRITICAL ZONE ===
    if (ml_event_id == 2) {  // Кавітація
        if (acoustic_events < 255) acoustic_events++;  // FW.22 saturating
    } else if (ml_event_id == 3) {  // Бензопила / вандалізм
        if (acoustic_events < 255) acoustic_events++;
        Trigger_Emergency_LoRa_TX();   // НЕГАЙНИЙ panic TX, PANIC_TTL=5
    }
    warning_counter = 0;  // Reset — ми вже відреагували

} else if (ml_confidence >= tinyml_warning_threshold) {
    // === WARNING ZONE ===
    if (ml_event_id == 2 || ml_event_id == 3) {
        if (acoustic_events < 255) acoustic_events++;  // Рахуємо, але не паніка
        if (warning_counter < 255) warning_counter++;
        if (warning_counter >= TINYML_WARNING_ESCALATION) {
            // 3+ послідовних WARNING → ескалація. Тільки бензопила отримує
            // fallback Emergency TX — кавітація рідко погіршується через шум,
            // тож ескалація обмежується саме ml_event_id == 3.
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

**OTA-оновлення порогів (через CoAP CMD downlink) — DEFERRED до FW.8 cycle:**

```c
// Queen → Soldier OTA command: CMD_SET_THRESHOLDS (0x9A — coordinated with FW.8)
// Payload: [CMD_ID:1][WARNING:4][CRITICAL:4] = 9 байт
//
// Виконується після TinyML_Apply_Thresholds() валідації, не як raw write —
// інакше зловмисник може записати warn=0.99/crit=0.50 і ефективно вимкнути
// ескалацію. Apply гарантує інваріант warn<crit та діапазон.
//
// case CMD_SET_THRESHOLDS:
//     {
//         float w = bytes_to_float(&payload[1]);
//         float c = bytes_to_float(&payload[5]);
//         TinyML_Apply_Thresholds(w, c, &tinyml_warning_threshold,
//                                  &tinyml_critical_threshold);
//         // Phase 5 writeback автоматично персистить оновлені значення.
//         break;
//     }
```

> **✅ Audit refinement (implemented 2026-05-22):** Embedded LOG_ERR на headless STM32 марний (немає консолі), тому замість printf реалізовано **saturating uint8 counter** `tinyml_threshold_invalid_count` (`firmware/soldier/main.c §1.11`), який інкрементується коли `TinyML_Apply_Thresholds` відкидає OTA payload через NaN, out-of-range або інверсію `warn >= crit`. Це справжня production-visibility — backend може piggybacked'ити лічильник на телеметрію → Grafana panel "OTA threshold corruption rate per Soldier". 7 нових host-тестів у `test_tinyml_pipeline.c` (`test_invalid_count_*`) покривають happy-path, NaN, out-of-range, inversion, cold-boot zeros, accumulation, saturation @ 255. Wiring до 21-byte packet — окрема задача.

**Стан:** Soldier-side OTA CMD dispatcher для `CMD_SET_AUDIO_THRESHOLDS` (`0x9D`)
**реалізовано** у `firmware/soldier/main.c` (секція 1.14: `Soldier_Handle_CMD_SET_AUDIO_THRESHOLDS`,
10-байтний frame layout: marker / warn:2 / crit:2 / version:1 / reserved:1 / crc16:2).
Парсер інтегровано в основний RX-цикл після AES-256-ECB decrypt.
Поточний Soldier-firmware обробляє опкоди: `0x99` OTA bytecode, `0x55/'R'` OTA-ReRequest,
`0x56/'S'` Time-Sync Request, **`0x9D` Audio Thresholds** (FW.18 imp).
Спільний CMD-фреймворк (`CMD:` prefix) залишається на Queen-стороні (`03_02` §6) —
Soldier використовує per-opcode dispatch для мінімізації RAM/flash overhead.

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

**Тести (реалізовано в `firmware/test/test_tinyml_pipeline.c`):**

19 нових host-based unit tests (44 total у TinyML suite):

*Dual-Threshold Confidence Zones (9):*
- `test_dual_threshold_silence_zone_no_action` — confidence < warning → no action
- `test_dual_threshold_warning_zone_at_boundary` — c == warning → WARNING (≥, не >)
- `test_dual_threshold_critical_just_below_no_emergency` — 0.84 → WARNING для chainsaw, не Emergency
- `test_dual_threshold_critical_zone_at_boundary` — c == critical → Emergency TX
- `test_dual_threshold_warning_escalation_chainsaw` — 3× WARNING → fallback Emergency
- `test_dual_threshold_warning_no_escalation_for_cavitation` — кавітація не ескалюється навіть при 5×
- `test_dual_threshold_silence_resets_counter_between_warnings` — SILENCE → counter=0
- `test_dual_threshold_chainsaw_critical_resets_counter` — CRITICAL після WARNING-серії → counter=0
- `test_dual_threshold_silence_with_chainsaw_class_no_emergency` — клас 3 + низька confidence → no emergency

*Threshold Validation & RTC Roundtrip (10):*
- `test_validate_threshold_in_range` — 0.55 / 0.95 → kept
- `test_validate_threshold_below_min_falls_back` — 0.005 / 0.0 / negative → default
- `test_validate_threshold_above_max_falls_back` — 1.0 / 99.0 → default
- `test_validate_threshold_nan_falls_back` — NaN → default
- `test_apply_thresholds_cold_boot_zeros` — RTC = 0x00 → defaults
- `test_apply_thresholds_inverted_falls_back_both` — warn ≥ crit → atomic rollback
- `test_apply_thresholds_equal_falls_back_both` — warn == crit → defaults
- `test_apply_thresholds_valid_pair_passes_through` — tropical config (0.70/0.90) → kept
- `test_apply_thresholds_partial_corruption_one_default` — частковий fallback з invariant check
- `test_threshold_rtc_roundtrip_bit_exact` — float32 ↔ uint32 bit-copy через DR13/DR14

**Блокує:** ~~Гнучкість налаштування~~ → закрито на firmware-рівні. Залишковий блокер: OTA CMD dispatcher на Soldier (DEFERRED → FW.8 cycle).

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

### 3.2 Decision Matrix: Три шляхи DSP (FW.25)

> **⚠️ Архітектурна корекція (2026-05-17):** Попередня редакція цього розділу
> декларувала **MFCC обов'язковим** як єдиний DSP-шлях. Аудит показав, що:
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
> CMSIS-DSP вже в стеку (FW.21 EMA, FW.5 Lorenz) — додавання Mel-bank ~1-2 KB
> коду без зміни toolchain.
>
> **Fallback на Path C** — лише якщо ML-партнер (Бушин/Любченко) сильно
> натисне на TFLM end-to-end через тренувальний workflow (Edge Impulse).
> **Path A — fast-path MVP** для 4-class без fauna, якщо ML-партнер недоступний
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
| Слабкі сторони | Лочить на TFLM runtime (вже наш runtime choice, тож не реальний lock). Tensor Arena трохи більший (frontend scratch). Менше control над DSP параметрами |
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

---

### 3.4 Log-Mel Feature Contract (FW.25) — конкретна специфікація

> **Призначення:** конвертувати «implementation gate» (BLOCKER-5) у простий *confirm*. Нижче — повний MCU-готовий контракт log-mel ознак. Firmware (`Compute_LogMel`) і тренувальний pipeline ML-партнера **мусять використовувати ідентичні параметри** — інакше модель, натренована на librosa-фічах, не працюватиме на MCU-фічах. ML-партнер (Бушин/Любченко) **підтверджує або коригує** ці значення; після цього DSP-імплементація (CMSIS-DSP + golden-vector host-тести) розблокована.

#### Параметри (proposed baseline)

| Параметр | Значення | Обґрунтування (MCU + ESC) |
|----------|----------|---------------------------|
| Sample rate | **16 000 Hz** | TIM2 метроном (§2.1) |
| Frame / `n_fft` | **512** (= 32 ms) | один DMA-блок = один FFT-кадр (§2.2) |
| Window | **Hann**, `win_length=512` | стандарт для спектрограм; `arm_mult_f32` |
| `hop_length` | **512** (без overlap) | 5 с / 32 мс = **156 кадрів** — точно збігається з монолітним fauna-вікном (§10.2 / ARCH.40); overlap зламав би 156-кадровий Welford |
| `n_mels` | **40** | = `MODEL_INPUT_SIZE` (stub); ESC-стандарт |
| `fmin` / `fmax` | **50 Hz / 8000 Hz** | fmax = Nyquist@16k; покриває комах 4–8 кГц, птахів 1–6, амфібій 0.5–3 (§10) |
| Mel-scale | **HTK** (`mel = 2595·log₁₀(1 + f/700)`) | замкнена формула для precompute на MCU (Slaney — кусково-лінійна, зайва складність) |
| Power | **2.0** (`|X|²`) | librosa default; `re² + im²` без sqrt |
| Mel-filter norm | **None** (сирі трикутні фільтри) | уникаємо Slaney area-нормалізації; масштаб компенсує BatchNorm моделі |
| Log | **`ln(mel + 1e-6)`** (натуральний) | `arm_vlog_f32`; floor 1e-6 проти log(0) |
| Вхід-нормалізація | **у моделі** (BatchNorm 1-й шар) | MCU видає сирий log-mel; модель нормалізує — стандарт ESC-CNN |

**Вихід:** `float[40]` на кадр (4-class: один стовпець → `Run_Inference`; fauna: 156 стовпців → Welford mean+std, §10.2).

#### Firmware-інтерфейс

```c
/* Один 512-семпловий кадр (32 ms @ 16 kHz) → 40 log-mel ознак.
 * audio: нормалізований [0,1) (як audio_buffer[] зараз) — DC прибирається всередині.
 * out_mel: 40 float, далі → Run_Inference(out_mel, &confidence). */
void Compute_LogMel(const float audio[512], float out_mel[40]);
```

Пайплайн: DC-remove (− mean) → Hann → **RFFT 512→257** (`arm_rfft_fast_f32` на ARM; портативний radix-2 для host-тестів) → power `re²+im²` (257 bins) → **mel-bank 40×257** (precomputed трикутні, HTK, sparse-triplet для Flash) → `ln(·+1e-6)`. Mel-матриця генерується офлайн (скрипт нижче) і вшивається як `const`.

#### Reference (ML-партнер тренує на ЦЬОМУ)

```python
import librosa, numpy as np
SR, N_FFT, HOP, N_MELS, FMIN, FMAX = 16000, 512, 512, 40, 50, 8000
mel = librosa.feature.melspectrogram(
    y=audio, sr=SR, n_fft=N_FFT, hop_length=HOP, win_length=N_FFT,
    window="hann", n_mels=N_MELS, fmin=FMIN, fmax=FMAX,
    power=2.0, htk=True, norm=None)            # htk=True + norm=None ⇔ MCU mel-bank
logmel = np.log(mel + 1e-6).astype(np.float32)  # натуральний log, floor 1e-6
# logmel.shape == (40, n_frames); один стовпець [40] = вхід Run_Inference
```

Той самий скрипт генерує mel-фільтробанк для вшивання у firmware:
`librosa.filters.mel(sr=SR, n_fft=N_FFT, n_mels=N_MELS, fmin=FMIN, fmax=FMAX, htk=True, norm=None)` → `float[40][257]` (sparse triplet).

#### Розблокування після confirm
1. ML-партнер підтверджує/коригує таблицю (особливо `fmin/fmax`, HTK vs Slaney, log-type).
2. Firmware: `Compute_LogMel` (`arm_rfft_fast_f32` + вшитий mel-bank) + golden-vector host-тести (numpy reference ↔ C, tolerance 1e-3).
3. Розкоментувати `Run_Inference` call-site (`main.c:1422`) + виміряти Tensor Arena (BLOCKER-3).

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
| **4** *(planned, Mongabay pivot)* | Fauna Activity (Soundscape) | «Багатошаровий» хор комах/птахів/амфібій з характерними піками на світанку та в сутінках — маркер реального функціонування екосистеми | 0.5–12 kHz, ритмічний (циркадний) |

> **🌿 Mongabay Pivot — 5-й клас «Fauna Activity»:** Стаття Delgado et al. (Nicoya Peninsula, Costa Rica, 119 ділянок, 16 000 годин аудіо; короткий огляд: Mongabay, травень 2026) науково підтвердила, що **акустичний фон фауни** є надійним маркером екологічного здоров'я лісу — захищені та регенеровані під PES ліси демонструють виражені піки активності на світанку/в сутінках, тоді як пасовища та монокультурні плантації — ні. Для Silken Net це означає **стратегічний pivot від карбонового D-MRV до повноцінного D-MRV біорізноманіття**: TinyML починає не лише ловити вандалізм/кавітацію, а й безперервно доводити, що Carbon Credit прив'язаний до **живої екосистеми**, а не до мертвої посадки. Класи 0–3 залишаються (security + physiology); клас 4 додається як **окрема метрика "Fauna Activity Index"** (інтенсивність 0–63) у тому ж байті телеметрії або поряд з `acoustic_events`. Детальний план у §10 нижче.

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
| `fauna_feature_accumulator` *(transient, fauna-only, path-dependent — see §3.2)* | `float[]` + scalar | **~256 B** (Path B/C) або **~2 KB** (Path A: raw window memory) | Welford `mean+M2` агрегація 156 feature-векторів за 5 с (Path B: log-mel coefs; Path C: frontend output; Path A: raw audio statistics). 256 B залишається валідною оцінкою для Path B/C; Path A потребує ширшої статистики (`mean+std+kurtosis` на raw envelope) — TBD |
| **Разом TinyML** | | **~11–19 KB** (Path B/C) / **~13–21 KB** (Path A) | З урахуванням Tensor Arena; +~256 B–2 KB transient під час fauna-сесії |

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
| fauna_feature_accumulator *(transient, path-dependent — §3.2; лише під час fauna-сесії — §10.2)* | ~256 B (Path B/C) / ~2 KB (Path A raw window) |
| Stack (оцінка) | ~4 096 B |
| **Разом (оцінка)** | **~25 KB** *(peak з fauna-вікном)* |
| **Залишок (з 64 KB)** | **~39 KB** |

> ⚠️ Точний розмір Tensor Arena невідомий. Потрібна верифікація через `arm-none-eabi-size`.

> 🌿 **`fauna_feature_accumulator` (audit-fix, ARCH.40 / §10.2 / FW.25 path-dependent):** Welford running `mean+M2` для агрегації 156 feature-векторів у межах **одного** awake-циклу (5 с моноліт — STOP2 wipe'не SRAM2, тому декомпозиція "сон-між-вікнами" заборонена). **Розмір залежить від обраного DSP-шляху (§3.2 Decision Matrix):**
> - **Path B (log-mel, default-рекомендація)** при `N_mel = 13`: `mean[13] = 52 B` + `M2[13] = 52 B` + `count (uint32) = 4 B` + `inference_input[mean‖std][26] = 104 B` ≈ **212 B**, округлено до **~256 B** з запасом на FFT scratch buffer.
> - **Path C (TFLM frontend)** при `N_features = 40` mel bins: `mean[40] = 160 B` + `M2[40] = 160 B` + `count = 4 B` + `inference_input[80] = 320 B` ≈ **644 B**, округлено до **~768 B**.
> - **Path A (raw window memory)**: ширша статистика на time-domain envelope (`mean+std+kurtosis+RMS+ZCR`), ~**2 KB** з повним 512-семпловим reference window для cross-correlation.
>
> RAM виділяється тільки на час fauna-сесії і звільняється перед STOP2 — звичайні класи 0–3 (32 мс post-EXTI) цей блок не використовують. Точний розмір зафіксується після (1) вибору DSP-шляху ML-партнером (Бушин/Любченко), (2) калібрувального датасету ЧДТУ ПМКТ (див. §10.5), (3) фінального вибору `N_features` для 5-class моделі.

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
| 1 | `silken_net_audio_model.h` закоміщено в репозиторій | 🟡 Stub додано (2026-05-22), реальна модель TBD ML-партнером |
| 2 | `Run_Inference()` розкоментовано та функціонує | 🔴 Відкрито (потребує реальної моделі) |
| 3 | `TENSOR_ARENA_SIZE` задокументовано з реального файлу | 🟡 Stub фіксує 16 KB (Path B baseline); реальна — TBD |
| 4 | Memory Map верифіковано (`arm-none-eabi-size`) | 🟡 `make size-check` проходить зі stub; ARM elf — після інтеграції моделі |
| 5 | Host-based тести TinyML pipeline додані | ✅ Реалізовано (`test_tinyml_pipeline.c`, **51 тест** включно з 7 для invalid counter) |
| 6 | Smoke-тест: class 2 → `acoustic_events++` верифіковано | 🔴 Відкрито |
| 7 | Smoke-тест: class 3 → `Trigger_Emergency_LoRa_TX()` верифіковано | 🔴 Відкрито |
| 8 | Confidence threshold конфігурується (не хардкод) | ✅ FW.18: dual-threshold у RTC DR13/DR14 + 19 host-tests + Soldier OTA CMD dispatcher `0x9D` (`CMD_SET_AUDIO_THRESHOLDS`) з 7 host-tests |
| 9 | DSP preprocessing задокументовано (чи є FFT в моделі) | 🟡 Відкрито |
| 10 | `acoustic_events` overflow захист реалізовано | ✅ Реалізовано (FW.22: `uint8_t` + saturating increment, 8 тестів) |
| 11 | План 5-го класу «Fauna Activity» (§10, Mongabay pivot) задокументовано | ✅ Реалізовано (цей doc §10 + cross-ref до 08_01/08_02/08_03/00_08) |

---

## 🌿 10. Mongabay Pivot — 5-й клас «Fauna Activity» та біорізноманіття як D-MRV сигнал

### 10.1 Контекст та джерело

**Джерело:** Delgado et al., польове дослідження на півострові Нікойя (Коста-Ріка) — 119 ділянок різних типів ландшафту, понад 16 000 годин неперервного аудіо-моніторингу; короткий огляд: *Mongabay News*, «Can listening to a forest reveal whether it is ecologically healthy?» (травень 2026). PES (Payment for Ecosystem Services) Коста-Ріки з 1997 року компенсує лісокористувачам утримання покриву — дослідження вперше надає інструментальне підтвердження, що `forest cover ≠ forest function`.

**Ключові інструментальні висновки статті, релевантні для Silken Net:**

1. Звуковий ландшафт лісу — **багатошаровий** (комахи + птахи + амфібії), з вираженими піками **на світанку та в сутінках** (циркадний ритм).
2. **Захищені ліси та регенеровані під PES** демонструють подібний рівень акустичної активності та dawn/dusk піки.
3. **Пасовища** — піки відсутні, рівномірний фон без структури.
4. **Монокультурні плантації** — часткове відновлення soundscape, але **непослідовно** (висока дисперсія між ділянками).
5. **Супутникові дані не розрізняють** функціональну екосистему від мертвої посадки — обидві дають однаковий «зелений піксель» NDVI.

> **Стратегічна важливість для Silken Net:** Це наукове підтвердження того, що інвестор carbon credit отримує не просто токен «1 SCC = 0.5 кг CO₂», а **функціональний біорізноманіттєвий актив**. Pivot змінює ринкове позиціювання з «ще одного MRV для вуглецю» на **«єдиний D-MRV рішення, що інструментально доводить біорізноманіття»** — категорія, де супутникові конкуренти (Pachama, Sylvera, NCX) фундаментально обмежені.

### 10.2 Що змінюється для TinyML архітектури

| Компонент | Поточний стан (TRL 6) | Цільовий стан (post-Mongabay pivot) |
|-----------|----------------------|--------------------------------------|
| Кількість класів | 4 (silence/wind/cavitation/chainsaw) | **5+** (додається `4 = fauna_activity`) АБО окрема паралельна метрика «Fauna Activity Index» (0–63) |
| Pre-processing | Лінійна нормалізація `[0.0, 1.0]` | **Path B (log-mel spectrogram) — ✅ ОФІЦІЙНО ЗАФІКСОВАНО (DECISION 2026-05-22, §3.2 Decision Matrix)**. Path A залишається fast-path MVP для 4-class без fauna (якщо ML-партнер недоступний). Path C — fallback якщо ML-партнер натисне на TFLM end-to-end. MFCC з повним DCT-кроком **категорично не рекомендовано** для CNN-based ESC |
| Вікно семплінгу | 32 мс (512 семплів @ 16 кГц) | Залишається 32 мс для класів 0–3; для класу 4 — **монолітне 5-секундне акумульоване вікно** (156 послідовних 32 мс вікон → агрегація feature-векторів через Welford mean+M2; формат feature-вектора залежить від обраного DSP-шляху §3.2: Path B/C log-mel coefs ~13–40 bins, Path A time-domain статистика). **Обов'язково в одному awake-циклі без STOP2 між вікнами** — див. примітку ⚠️ нижче |
| Тригер | П'єзо-EXTI на вібрацію | Класи 0–3 — як зараз; для класу 4 — **щогодинні «акустичні семплінги»** (без вібраційного тригера) на світанку (солар-час+0..2 год) та сутінках (солар-час−2..0 год) |
| Бюджет TX | 1 байт `acoustic_events` (saturating uint8) | Без змін у packet layout; «Fauna Activity Index» транслюється через **той самий байт** у режимі fauna-семплінгу (не змішується з кавітацією — режим маркується через окремий біт у Status Byte або через циркадне вікно на backend) |

> ⚠️ **Constraint — SRAM2 wipe vs. accumulator (audit-fix, ARCH.40):** Архітектура енергозбереження Soldier'а v3 ([03_01 §1 + 00_02](03_01_Firmware_Lifecycle_and_DMA)) використовує STOP2 RTC-only з `PWR_CR1_RRSTP=1` для досягнення 300 нА deep-sleep. Це **повністю стирає SRAM2** при кожному переході в STOP2. Проміжна matrix-statistic (`mean+std` 156 MFCC-векторів) у RAM не переживе сну. RTC Backup Domain не врятує: вільний лише DR15 (один uint32) — це фізично не вміщує float-матрицю. **Висновок:** fauna-сесія мусить виконуватись **монолітно за один цикл активного пробудження**: 156 циклів TIM2+DMA послідовно один за одним у межах однієї main-loop ітерації, проміжна статистика тримається в RAM, і STOP2 викликається лише після того, як фінальний `fauna_activity_index` згорнуто в один байт. Декомпозиція на «спав → 32 мс → MFCC → знов сон» — заборонена.

### 10.3 Енергетичний бюджет

> ⚠️ **Перерахунок (audit-fix, ARCH.39):** Перша редакція цього розділу містила дві помилки: (1) арифметична — `1 мА × 3.3 V × 10 с` дає **33 мДж**, не 3.3 мДж; (2) системна — не враховано активний CPU-струм під час MFCC + інференсу. Реальна вартість fauna-сесії приблизно у **20× вища** за оригінальну оцінку. Енергетично pivot все одно сумісний, але потребує програмного guard'у проти brownout при низькому V_cap.

Додатковий fauna-семплінг 2× на добу (світанок + сутінки), кожен по 5 с акустичного запису @ 16 кГц = 156 послідовних вікон по 32 мс.

**Розрахунок одного 5-секундного сеансу (моноліт, див. §10.2):**

| Фаза | Струм | Тривалість | Енергія |
|------|-------|-----------|---------|
| ADC + DMA wait (LP-RUN, периферія активна) | ~1 мА @ 3.3 V | 5.0 с (повне вікно) | **16.5 мДж** |
| Active CPU: MFCC (~3 мс) + INT8 inference (~7 мс) per 32 мс window | ~12 мА @ 3.3 V | 156 × 10 мс ≈ 1.56 с | **61.8 мДж** |
| **Разом за сесію** | | | **~78.3 мДж** |
| **Разом за добу (dawn + dusk)** | | | **~156.6 мДж/добу** |

Для довідки: 1× LoRa-TX @ +14 dBm ≈ 38 мДж; fauna-сесія = ~2× TX. Бюджет EDLC 0.47F/5.5V (повний) = 7.1 Дж → fauna-доба = **~2.2 %** буфера. Енергетично pivot сумісний з EBFC+EDLC.

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

> 🔗 **Cross-ref [02_03 §9.6 Сценарій C](02_03_BQ25570_MPPT_Nano_Power#9-sensitivity-analysis):** математичні константи sensitivity-моделі EDLC потребують узгодження з 78.3 мДж/сесію, дворівневим V_cap-порогом (4.5 V / 4.0 V / 3.5 V) та маркерами `fauna_skipped_low_vcap` після злиття цього патчу.

### 10.4 Маппінг на Backend та Web3

```
TinyML 5-class soundscape inference (dawn/dusk windows)
        ↓
LoRa payload[7] = fauna_activity_index (0–63), маркер режиму у Status Byte
        ↓
TelemetryUnpackerService → TelemetryLog#fauna_activity_index (нова колонка, TBD post-TRL 7)
        ↓
InsightGeneratorService → AiInsight(insight_type: :biodiversity_trend)
   (enum уже існує у app/models/ai_insight.rb:13 — джерело даних до сьогодні було невизначене;
    Mongabay pivot робить TinyML soundscape ОФІЦІЙНИМ джерелом для biodiversity_trend)
        ↓
ForestNFT (SFC) метадані → "biodiversity_score": 0.0–1.0
        ↓
RWA market: інвестор бачить не лише CO₂, а й функціональний біорізноманіттєвий індекс
```

### 10.5 Залежності та академічна координація

| Залежність | Партнер | Документ | Що потрібно |
|------------|---------|----------|-------------|
| FW.4 (`Run_Inference()`) розкоментувати, додати модель | ML-партнер (Бушин/Любченко ЧНУ або ChDTU) | `03_03` §1, [`08_02` §1.5/§1.8](08_02_Cybernetic_and_Mathematical_Validation) | Натренована TFLite модель з 5 класами (INT8) |
| FW.25 (DSP-шлях choice gate) — переведено P1→P0 | **Primary owner: Бушин або Любченко (ЧНУ ФОТІУС, ML)** — рішення про шлях A/B/C (§3.2 Decision Matrix). **Secondary: Ярмілко (ЧНУ ФОТІУС, SPI/DMA)** — integration consultant після вибору шляху, якщо обрано Path B з CMSIS-DSP | [`08_02` §1.5/§1.8](08_02_Cybernetic_and_Mathematical_Validation) | (1) Узгодити шлях A/B/C; (2) Path A: збільшити INT8 модель; Path B: CMSIS-DSP `arm_rfft_fast_f32` + custom Mel-bank + `arm_vlog_f32` (НЕ повний MFCC); Path C: TFLM `signal::microfrontend` op; (3) tensor_arena recheck per path |
| Калібрувальний датасет з dawn/dusk записами Черкаського бору | Базіло + Бондаренко (ЧДТУ ПМКТ) + Спрягайло/Гаврилюк (ЧНУ Біо-хаб) | [`08_04` §1.3 Завдання В](08_04_CHDTU_Data_Science_Collaboration), [`08_01` §2 Homeostasis Baseline](08_01_University_R_and_D_Protocols) | Польові аудіозаписи на світанку/в сутінках на ділянках різного типу (захищений бір, регенерація, монокультура), мінімум 4 сезони |
| GA-оптимізація 5-class моделі та confidence thresholds для dawn/dusk | Любченко (ЧНУ ФОТІУС) | [`08_02` §1.8](08_02_Cybernetic_and_Mathematical_Validation) | Akash GPU кластер, фітнес-функція з ground truth |
| Macro-Micro verification (NDVI Sentinel-2 ↔ TinyML soundscape) | Бушин (ЧНУ ФОТІУС, CNN) | [`08_02` §1.5](08_02_Cybernetic_and_Mathematical_Validation) | Pipeline злиття супутника + TinyML; AiInsight#biodiversity_trend |
| Статистика розподілів `fauna_activity_index` між ділянками | Карапетян (ЧДТУ Data Science) | [`08_04` §1.1](08_04_CHDTU_Data_Science_Collaboration) | R-аналіз, ANOVA dawn/dusk peak amplitude між ландшафтами |
| Грантовий вектор Horizon Europe CLUSTER 6 (Biodiversity Monitoring) | СЄУ + усі академічні партнери | [`00_08` BIZ section](00_08_Action_Plan_Tracker), [`08_03` Стаття 24a/34](08_03_Joint_Publications_and_IP_Strategy) | Заявка з акцентом на acoustic D-MRV |

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
  - Macro-Micro verification (Бушин CNN ↔ TinyML soundscape)
  - AiInsight#biodiversity_trend → ForestNFT metadata
  - Horizon Europe CLUSTER 6 grant submission
```

### 10.7 Ризики та відкриті питання

1. **Tensor Arena зростання** для 5-class CNN — масштаб залежить від обраного DSP-шляху (§3.2): Path A: +30–50% RAM (~20–40 KB; модель сама вчиться features); Path B: +10–20% (~15–30 KB; features pre-extracted, менша модель); Path C: +15–25% (~25–35 KB; включає frontend scratch). Залежить від BLOCKER-3.
2. **Шум вітру 0.5–2 кГц перетинається з амфібіями** — ризик false positives для класу 4. Mitigation: акумульоване вікно + dawn/dusk timing constraint (вночі/на світанку вітер слабший). Path B/C дають кращу spectral discrimination ніж Path A.
3. **Регіональна специфіка soundscape** — модель, натренована на Черкаському борі, може не узагальнюватись на тропіки. Potential solution: Federated Learning (вже описаний у §9).
4. **Чи буде fauna класифікуватись через TinyML, чи через окремий DSP-only метричний модуль (без NN)?** — alternative architecture: спектральний descriptor **(ACI — Acoustic Complexity Index, Pieretti et al. 2011) обчислюється на STM32 з FFT (тобто потребує Path B-style DSP), без NN**. Це може стати TRL-7 інкрементом до повноцінної 5-class моделі. ACI **не є** "no-FFT alternative" — це спектральний показник, не часовий; виконується на тому ж FFT-output, що й Path B mel-bank.
5. **DSP-path lock-in ризик:** якщо обрати Path B (custom Mel-bank у firmware), а потім ML-партнер мігрує на Path C (TFLM frontend) — firmware DSP код стає мертвим вантажем у Flash. Mitigation: обирати Path C з самого початку при будь-яких сумнівах щодо архітектурного контракту з ML-партнером.

### 10.8 Резонансні концепти Silken Net (поза статтею)

Стаття Delgado підкреслює, що ліс — це **процес, а не об'єкт**. Це ідеально резонує з трьома ядрами Silken Net:

- **Lorenz Attractor** ([`03_04`](03_04_mruby_Lorenz_Attractor)) — теж описує процес (динаміку гомеостазу), а не статичний стан. Біорізноманіття стає третім вхідним сигналом до атрактора (поряд з temp і acoustic_events) — або новим параметром β-пертурбації (FW.5 cycle 2).
- **Proof of Growth** vs `forest cover` — токен SCC мінтиться не за наявність дерева, а за **сталий процес зростання** (10 000 growth_points = 1 SCC). Біорізноманіттєвий шар робить це доведення планетарним.
- **Forester Guild (Proof-of-Physical-Work, E.20)** — наземні рейнджери теж дають дані про функцію, не про покрив. TinyML soundscape = **автоматизована заміна** суб'єктивному human report.

> **Pitch для інвестора (короткий):** «Супутник бачить піксель. Ми чуємо ліс. PES Коста-Ріки 30 років мав цю проблему — Silken Net вирішує її TinyML-датчиком на дереві.»

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

### Beyond TRL 9: On-Device Learning — Edge RL та Evolutionary Algorithms

> **Контекст:** Federated Learning Pipeline вище — це **top-down** (cloud навчає → edge виконує). Це **достатньо для TRL 9**, але обмежує адаптивність: модель оновлюється раз на тижні/місяці, а кліматичні мікро-зміни відбуваються щодоби.
>
> **Майбутній напрям (Beyond TRL 9 / SRL roadmap) — Edge AI Self-Evolution:**
> - **On-device class-incremental learning:** додавання нових акустичних патернів (нові інвазивні комахи у Черкаському борі, нові типи браконьєрської техніки) без необхідності retraining у cloud. Обмежено 1–4 incremental classes на STM32WLE5JC; для повного on-device backprop потрібен AI-coprocessor (Syntiant NDP120 / Maxim MAX78000) у v3 hardware.
> - **Edge Reinforcement Learning:** tabular Q-learning з 12-state × 4-action lookup для прийняття рішень (sleep_extend / normal / sample_extra / emergency_tx); reward = days-to-next-VBAT_OK. State buffer у RTC backup registers DR20-DR31.
> - **Координація з mruby evolutionary algorithms у `03_04`** — спільна `device-side learning loop` між TinyML (perception) і Lorenz contract (decision).
>
> **Безпекова прірва:** self-evolution + Web3-economic rewards = attack surface для adversarial reward poisoning. Mitigation — Apex Predator Defense (`05_03` + `00_06 §7.4`).
>
> **Деталі повної R&D-програми:** [`00_06 §7.2`](00_06_Strategic_Roadmap_and_HIL_Simulators) — Self-Evolving Behaviour Gap.

---

## 📚 Пов'язані Ресурси

- **[03_01 Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA)** — загальний lifecycle Soldier, фази 0-5, Watchdog
- **[03_04 mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor)** — як `acoustic_events` впливає на атрактор
- **[03_05 Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security)** — шифрування panic-пакетів EwsAlert
- **[04_01 Data Models and Entities](04_01_Data_Models_and_Entities)** — модель `TelemetryLog`, поле `acoustic_events`
- **[04_02 Business Logic and Services](04_02_Business_Logic_and_Services)** — `TelemetryUnpackerService`, `EwsAlertCreatorService`
- **`firmware/soldier/main.c`** — реалізація Phase 1.5 (рядки 316–365) та ISR (рядки 731–737)
- **`firmware/soldier/silken_net_audio_model.h`** — TBD ML-партнером (реальна модель)
- **`firmware/soldier/silken_net_audio_model_stub.h`** — ✅ IP-friendly stub (2026-05-22, BLOCKER-2 partial close)
- **CMSIS-DSP Documentation** — `arm_rfft_fast_f32`, `arm_cmplx_mag_f32`
- **TensorFlow Lite for Microcontrollers** — https://www.tensorflow.org/lite/microcontrollers
