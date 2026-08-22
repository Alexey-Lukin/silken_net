# Baseline TinyML Acoustic Model — Execution Program (ESC-50, self-owned)

> **Що це.** Робочий програм-документ для нашої власної baseline-моделі акустичного
> інференсу, натренованої на відкритих даних (ESC-50), щоб розблокувати ланцюг
> **FW.4 → FW.26 (arena) → FW.42 → ARCH.40** без очікування ML-партнера.
> Це **HOW/program**; *значення* живуть у каноні (нижче), не тут — щоб не плодити drift.
>
> **Канонічні домівки (значення правити ТАМ, не тут):**
> - Log-mel контракт ознак — [`docs/03_03 §3.4`](../../../docs/03_03_TinyML_Acoustic_Inference.md)
> - RAM-леджер / arena-стеля — [`docs/03_03 §6`](../../../docs/03_03_TinyML_Acoustic_Inference.md)
> - Архітектура моделі / класи / пороги — `docs/03_03 §4` / §5 / §10
> - Трекер блокерів — [`docs/00_07`](../../../docs/00_07_Action_Plan_Tracker.md) FW.4 / FW.25 / FW.26 / FW.42 / ARCH.40
> - ML-метод (parity-інваріант, скаффолди) — [`tools/ml/README.md`](../README.md) + скіл `ml-engineering`
> - Validation Gate (специфікація ДО коду) — [`00_06 §5`](../../../docs/00_06_SSOT_Documentation_Standard.md) ⚠️ доти цей рядок казав `docs/00_02` — номер розчинено 2026-08-10, і форма без імені доку й без `§` невидима обом реф-гейтам

---

## 0. Рамка та принцип володіння

- **ML-партнера НЕМА.** Нас ніщо не обмежує — ця модель **наша end-to-end**, не викидний
  stub «до партнера». Якщо партнерство не матеріалізується, baseline можна доростити до
  продакшну. Аспіраційний ростер (Любченко — NSGA-II
  оптимізація + циркадні пороги; Карапетян — статистика розподілів `fauna_activity_index`,
  ANOVA, RQA) беремо як **напрям, який перевіряємо**, а не як блокер чи обмеження
  toolchain. Це узгоджено з [`07_03` Стаття 24a](../../../docs/07_03_Academic_Integration_and_IP.md):
  *Архітектор володіє DSP+firmware; партнер (за наявності) тренує/оптимізує 5-class модель.*
- **Чесність placeholder'а.** Baseline вирішує **інтеграційно-вимірювальну** половину FW.4
  (компіляція, реальна arena, розкоментований call-site, реальні smoke-тести). **Польову
  валідність** дає лише калібрувальний датасет (Cherkasy Soundscape Library, ЧДТУ ПМКТ,
  post-TRL 7). Ці дві половини НЕ плутати в каноні.

---

## 1. Edge-ML стек: що маємо, що треба (аудит + доступне пояснення)

### 1.1 Глосарій (бо домен новий)
| Шар | Що це | Наш статус |
|-----|-------|-----------|
| **CMSIS-DSP** | бібліотека *сигнальної математики* (FFT, фільтри) | ✅ завендорено + використовується (`arm_rfft_fast_f32` у log-mel) |
| **CMSIS-NN** | бібліотека *INT8 NN-ядер* для Cortex-M (`arm_fully_connected_s8`…). **Ядра, не рантайм** | ⬜ не завендорено — для baseline **не потрібне** (pure-C); опційний ARM-прискорювач потім |
| **TFLM** / LiteRT-Micro | *інтерпретатор* `.tflite` на MCU. На Cortex-M **делегує саме в CMSIS-NN** | ⬜ не завендорено; C++ каркас; для нашого бюджету маргінальний (див. 1.3) |
| **TFLite / LiteRT** | формат моделі + **PC-квантизатор** (`TFLiteConverter` INT8 PTQ) | ✅ ставимо в `silken_ml` env — лише train/quantize/archive |
| **ST Edge AI** (ex-X-CUBE-AI) | vendor-кодоген `.tflite/ONNX → optimized C` для STM32 | опція для майбутньої великої партнерської моделі (lock-in) |
| Edge Impulse / microTVM / executorch | SaaS / компілятори | поза скоупом baseline |

> **Категорійна помилка в каноні (аномалія):** деякі доки ставлять «TFLM **vs** CMSIS-NN»
> як або/або. Це невірно — **TFLM це інтерпретатор ПОВЕРХ CMSIS-NN-ядер**. Реальна
> розвилка: *інтерпретатор (TFLM)* vs *фіксована топологія-кодоген (pure-C / CMSIS-NN
> forward pass)*; обидва внизу крутять INT8 через ті самі CMSIS-NN ядра.

### 1.2 Аудит вендорингу (`firmware/extern/`)
CMSIS-DSP (лінкується у `silken_common` через `LOGMEL_USE_CMSIS`), CMSIS_6 Core (його
потребує DSP), HAL + cmsis-device-wl (FW.46 lane), mruby, monocypher. **Нічого не
мис-вендорено**, усе на місці й використовується. CMSIS-NN/TFLM відсутні — **і правильно**,
бо для baseline вони не потрібні.

### 1.3 Факти про footprint (перевірено вебом, не з пам'яті)
- TFLM на Cortex-M **лінкує CMSIS-NN** як оптимізований kernel-backend; непідтримані
  оператори → reference-ядра. *(tflite-micro docs/arm.md; TF Blog 2021)*
- Ядро TFLM ≈ **16 КБ Flash** на M3, працює від ~**20 КБ Flash + 4 КБ SRAM** — але це
  **каркас, ПОНАД tensor-arena, і він C++**. *(arXiv 2010.08678; LiteRT microcontrollers)*
- Наш пост-FW.55 бюджет: 64 КБ SRAM − **38 КБ mruby** − stack − статика ⇒ **arena-стеля
  7–15 КБ** ([`03_03 §6`](../../../docs/03_03_TinyML_Acoustic_Inference.md)). TFLM-каркас
  (4 КБ SRAM + C++ vendoring у крос-компіляцію) тут **маргінальний + важкий lift**.

### 1.4 РІШЕННЯ runtime (з принципів + бюджет, не голосуванням доків)
**Baseline деплоїться як фіксована топологія INT8 forward pass** — портативний C
(host ≡ ARM, ідіома `logmel.c`), нуль нового вендорингу; CMSIS-NN-прискорення опційне
потім. **TFLite = лише train/quantize/archive.** TFLM-інтерпретатор = задокументований
**fallback**, ЯКЩО знадобиться OTA-гнучкість графів **І** виміряний footprint влізе.

*Чому не «доки праві бо їх більше»:* «CMSIS-NN»-доки праві щодо **kernel-шару**, але
неточні, називаючи його «рантаймом». `03_03` «TFLM» — право, що це стандартний
інтерпретатор, але переоцінене як «наш вибір» і написане **до** виміру FW.55, який стиснув
бюджет. Синтез вище примиряє обидва й розчиняє категорійну помилку.

---

## 2. Специфікація моделі (гіпотеза за Validation Gate `00_06 §5`)

- **Вхід:** `float[40]` per-frame log-mel — наявний контракт `Run_Inference`
  (`MODEL_INPUT_SIZE=40`); **НЕ** 2D-патч спектрограми. Деплой-інференс — покадровий.
- **Вихід:** 5 класів (silence/wind/cavitation/chainsaw/fauna) — під `NUM_CLASSES=5`, stub,
  decision-logic `main.c`.
- **Топологія:** крихітна MLP/1D-conv `40 → … → 5` під arena-стелю (для per-frame моделі
  arena реально — сотні байт). Точна топологія — з малого пошуку під стелю.
- **Квантизація:** INT8 PTQ через `TFLiteConverter`, representative dataset = реальні
  log-mel фічі (наш `silken_ml.dsp` оракул → train ≡ device parity).

### 2.1 Джерела даних класів (чесно)
| Клас | Джерело | Чесність |
|------|---------|----------|
| 0 silence | синтетичні low-energy + тихі ESC-50 сегменти | ок |
| 1 wind | ESC-50 `wind` | реальне |
| 2 **cavitation** | **немає відкритих даних** → фізично-вмотивований синтетичний генератор (імпульсні broadband сплески ~5–8 кГц) | **placeholder, марковано**; робить smoke-тест класу 2 реальним |
| 3 chainsaw | ESC-50 `chainsaw` | реальне |
| 4 fauna | ESC-50 тваринні (`crickets`/`chirping_birds`/`frog`/`insects`) як interim soundscape-проксі | **interim**; реальне = Cherkasy Soundscape Library (post-TRL 7) |

> **One-Home:** канонічна field-валідність-теза (що field-valid, що placeholder, + framing «pipeline-метрика, не польова точність») живе в [`03_03 §4.2`](../../../docs/03_03_TinyML_Acoustic_Inference.md); ця таблиця — джерела/генератори (HOW), не дублює канон.

> **Per-frame labeling caveat (документується):** кожен 32-мс кадр кліпу успадковує мітку
> кліпу (з silence-gating тихих кадрів). Мітки *слабкі* (кадр може не містити подію) —
> це обмеження baseline; майбутня темпоральна агрегація (fauna Welford §10.2 / партнерська
> модель) його знімає.

---

## 3. Pipeline — заповнення скаффолдів (enterprise-конвенції з докстрінгів)

- **`silken_ml.data`** — ESC-50 loader; **committed `models/registry/<run>/data_manifest.json`**
  (per-file sha256 + source + license + label); seeded stratified split; синт-генератори
  (silence, cavitation); фічі через `silken_ml.dsp` (ТОЙ САМИЙ контракт → train≡device).
- **`silken_ml.models`** — config-driven топологія під стелю.
- **`silken_ml.train`** — config (dataclass/YAML); seed-everything; **reproducibility
  manifest** `{data_hash, code_sha, env_hash, config, metrics}`; real eval (stratified,
  per-class P/R/F1, confusion, **confidence calibration** → пороги FW.18 §5); model
  registry `models/registry/<version>/` з provenance.
- **`silken_ml.export`** — TFLite INT8 PTQ + **QUANTIZATION-PARITY gate** (float↔INT8) +
  емітер `silken_net_audio_model.h` (INT8-ваги + inline portable-C `Run_Inference` +
  **виміряний** `TENSOR_ARENA_SIZE` + contract-hash banner, ідіома `codegen.emit_c`).
- **env** — TF додано до `environment.yml`; parity-гейт лишається зеленим (перевірено).

---

## 4. Інтеграція у firmware

1. `silken_net_audio_model.h` drop-in через `__has_include` (замінює `_stub.h`).
2. Розкоментувати call-site `Run_Inference` + `#include "../common/logmel.h"`
   (`main.c` ≈ Phase 1.5, рядки ~1927–1929).
3. Білд host + ARM; `arm-none-eabi-size` → **реальна arena** (FW.26);
   гейт `check_ram_budget.sh`.
4. Host-тести: TRL-7 #6 (class 2 → `acoustic_events++`) і #7 (class 3 → emergency TX)
   стають **реальними** (заміна mock у `test_tinyml_pipeline.c`).

---

## 5. Аномалії канону (знайдені; правляться разом із цією роботою)

| # | Де | Суть | Фікс |
|---|-----|------|------|
| 1 | 03_03 §4.1 / §6 / §3.2 / §10.7 | **runtime-дрейф** «TFLM як наш вибір» + категорійна помилка «TFLM vs CMSIS-NN» | ✅ **закрито** — §4.1 примирення · §3.2 «Лочить на TFLM (НЕ завендорено)» · §6 «landed baseline = forward-pass 76 B» · §10.7 «Path C — лише документований fallback» |
| 2 | 03_03 §5.3 + §7.1 | Soldier→Queen LoRa = **AES-256-ECB** (стале) | ✅ **закрито** — `grep -c "AES-256" docs/03_03` = 0; усюди AES-128 |
| 3 | 03_03 §5.3 code | стале тіло `Trigger_Emergency_LoRa_TX` (нема `Ttl_Byte_Pack`/`PANIC_FLAG_BIT`/counter[14..15]) | 🔴 **ЄДИНИЙ ЖИВИЙ** → трекер-дім **`00_07` FW.62** (звірка 2026-07-17: `Ttl_Byte_Pack` — 03_03 = 0 входжень, `main.c` = 2) → звірити код-блок із `Trigger_Emergency_LoRa_TX` |
| 4 | 03_03 §4.2 + §4.4 | return-doc лише 4 класи (0–3), пропущено **fauna=4** | ✅ **закрито** — §4.2 і §4.4 несуть «4=Fauna» |
| 5 | 03_03 §3.1 | стале «модель отримує сирий time-domain; DSP невідомий (BLOCKER-2)» | ✅ **закрито** — §3.1 «Path B зафіксовано … НЕ сирий time-domain»; `grep -c BLOCKER docs/03_03` = 0 |
| 6 | 03_03 §4.5 | latency-таблиця «Conv1D шар 1/2» (Path A мова) | ✅ **закрито 2026-07-17** — таблицю перемарковано як оцінку партнерського CNN-класу + landed FC 40→16→5 названо явно (число не вигадуємо — bench) |
| 7 | 02_01 §line | «TinyML Inference (CMSIS-NN, **~200 мс**)» суперечить §4.5 (~8–24 мс) | ✅ **закрито** — `grep -c "CMSIS-NN" docs/02_01` = 0; `02_01 §2` несе ноту «консервативний envelope, не landed-вимір» + зустрічна нота у `03_03 §4.5` (петля замкнена 07-17) |
| 8 | 07_03 Стаття 24a / 03_01 vendor-table | «<16KB arena» / «CMSIS-NN must vendor» — уточнити проти виміряної стелі + «pure-C baseline, CMSIS-NN опційно» | ✅ **закрито 2026-07-17** (UNI.19-свіп): `03_01` vendor-table + `02_01`-нота були закриті раніше; лишались `07_03` Ст.24a (унікальність #1 + «ML-партнер тренує CNN»), `05_02`, `00_08`, `04_02`, `03_01` Flash-рядок, `03_03` ×2 — усі вирівняні на landed 972 B / 76 B |

---

## 6. SSOT-оновлення (по завершенні фаз)
- **03_03** — аномалії §5 вище + статуси §8-чеклиста (1–4: stub→реальна модель, arena
  виміряна, Run_Inference розкоментовано).
- **00_07** — FW.4 / FW.25 / FW.26 машинна половина закрита (модель + arena + uncomment).
- **Ripple** — 02_01 latency, 07_03 Стаття 24a footprint, 03_01 vendor-table (current vs
  planned), 00_00 індекс (за потреби).
- **Пам'ять** — стан програми + рішення runtime.

---

## 7. Гейти (зелені перед commit)
`ruff check` · `pytest tools/ml/tests` (parity + нові train/export) · `make -C firmware/test`
(logmel/tinyml/fauna) · `silken-ml-gen-logmel --check` / `emit_c --check` ·
`check_ram_budget.sh` (ARM static-RAM) · звірка scope діфу (перед commit).

---

## 8. Status log (живий)
- **2026-06-12** — Дослідження + план зафіксовано. Перевірено: TF 2.21.0 + TFLiteConverter
  OK; parity-гейт зелений post-mutation (numpy 2.4.6 / librosa 0.11.0); ESC-50 доступний;
  CMSIS-NN/TFLM не завендорено (підтверджено pure-C рішення); runtime-примирення на доказах
  (web). ESC-50 завантажується. **Далі:** P1 `data` модуль.
- **2026-06-12 (cont.)** — ✅ **ВЕСЬ ланцюг виконано.** Pipeline (`data/models/train/export`)
  заповнено (ruff-clean, pytest **118-green**: 16 dsp + 102 export-arith). Тренування:
  float **85.6%** / INT8 **85.4%** (ECE 0.033). `silken_net_audio_model.h` згенеровано —
  parity з TFLite argmax-exact (max|Δ|=1), **972 B Flash / 0 .bss / 76 B стек**. Host-тест
  `test_audio_model` (12 golden) + увесь firmware-сьют зелений. `main.c` call-site
  розкоментовано + `logmel.h`. **Docs:** runtime-примирення 03_03 §4.1 + ~14 stale-спотів
  (CLAUDE.md / .github / stub.h / main.c / 03_03 / 03_01 / 00_07); `docs:check_refs` +
  `tracker:check` EXIT=0. **Deferred — ✅ вичерпано 2026-07-17:** 02_01 ~200мс (нота-envelope `02_01 §2`) · `07_03`/manifest
  `<16KB` (UNI.19-свіп + DOC-T.41 07-16) · 03_03 Path-A-4-class (§4.2/§4.4 = 5 класів). ⚠️ Цей
  список був **третім дзеркалом** боргу №8 — усередині файлу, що його ж і реєструє: борг стояв
  у §5-таблиці, у §8-Deferred і в самому каноні одночасно.
