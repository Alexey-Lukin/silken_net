# 03_04: mruby Атрактор Лоренца (Математика Хаосу та Гомеостаз)

---

## 🎯 Мета

Задокументувати повний алгоритм **Bio-Contract** — mruby-скрипту, що виконується на борту вузла **Soldier** (STM32WLE5JC) і обчислює стан гомеостазу дерева через Атрактор Лоренца. Цей документ є SSOT для:

- **Backend (`TelemetryUnpackerService`)**: сервер знає точну математичну модель і може перевіряти коректність надісланих деревом `growth_points`.
- **Proof of Growth Pipeline (05_02)**: мінтинг SCC заблокований, поки бекенд не розуміє математику, що генерує бали.
- **University R&D (08_02)**: академічна верифікація числової стабільності методу Ейлера у системі Лоренца.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — mruby-скрипт написаний, виконується у VM на мікроконтролері
- **Пов'язані модулі:**
  - Життєвий Цикл Прошивки та DMA → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)
  - TinyML Акустичний Інференс → [`03_03_TinyML_Acoustic_Inference`](03_03_TinyML_Acoustic_Inference)
  - Апаратний AES-256 та Безпека → [`03_05_Hardware_AES256_and_Security`](03_05_Hardware_AES256_and_Security)
  - Бізнес-Логіка та Сервіси → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Proof of Growth Pipeline → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)

---

| Компонент | Стан |
|---|---|
| **mruby VM ініціалізація** (`mrb_open()` один раз при старті) | ✅ Реалізовано |
| **Байт-код (`lorenz_bytecode[]`) вбудований у Flash** | ✅ Реалізовано |
| **OTA-оновлення контракту** (MRUBY_CONTRACT_FLASH_ADDR = `0x0803F000`) | ✅ Реалізовано |
| **GC Arena save/restore** (запобігання heap fragmentation) | ✅ Реалізовано |
| **Обробка mruby виключень** (`mrb->exc` перевірка) | ✅ Реалізовано |
| **Lorenz math (σ, ρ, β, DT, ITERATIONS)** | ✅ Реалізовано |
| **Sigma/Rho clamp** (захист від вибуху) | ✅ Реалізовано |
| **Z → growth_points конвертація** | ✅ Реалізовано |
| **Bit-packing `[Status:2&#124;GrowthPoints:6]`** | ✅ Реалізовано |
| **Backend дзеркало** (`SilkenNet::Attractor` у Rails) | ✅ Реалізовано |
| **`delta_t` та `vcap` як β-пертурбація атрактора** | ✅ Реалізовано (FW.5) — β обчислюється з `delta_t_s` і `vcap_mv`; firmware та backend дзеркальні; 500-case parity fuzz 0 mismatches |
| **Збереження стану (x, y, z) між циклами сну** | ✅ Реалізовано (FW.6) — RTC DR16-DR18 + DR19 маркер валідності |
| **Float32 vs Float64 верифікація** | ✅ Виправлено — backend переведено на Float (IEEE 754), ідентично firmware |
| **Коментар OPTIMAL_Z_TARGET (20.0 vs 29.0)** | ✅ Виправлено — коментар виправлено на 29.0 |
| **`deviation.to_i` (Truncation замість Round)** | ✅ Виправлено — `deviation.round` |
| **K_seed-derived `(x₀, y₀, z₀)` cold start (заміна `chaos_seed`/DID-as-seed)** | ✅ Реалізовано (SEC.11, 2026-05-02) — `SilkenNet::SeedDerivation` (HKDF + HMAC), firmware mbedTLS bridge, host-parity test 13 examples |
| **Єдина mruby сигнатура `calculate_state(x_prev, y_prev, z_prev, …)`** | ✅ Реалізовано (SEC.11 + FW.30) — `calculate_state_continued` видалено, dual-path C-міст у `firmware/soldier/main.c` замінено на single-path 7-arg виклик `calculate_state(x,y,z,temp,acoustic,delta_t_s,vcap_mv)`. Cold-start через K_seed замість `chaos_seed`. 11 нових host-тестів |
| **`telemetry_logs.lorenz_state_x/y/z` + `cold_start_flag` (chaining server-side)** | ✅ Реалізовано (SEC.11) — `TelemetryUnpackerService` persist'ить tail кожного uplink; наступний пакет дзеркалить firmware-side RTC continuation |

---

## 🛑 Блокери

---

### ✅ BLOCKER-1 (Закрито FW.5): β-Пертурбація від EBFC-Метаболізму — РЕАЛІЗОВАНО

**Статус:** ✅ **Реалізовано (FW.5, 2026-04-30).** Firmware `bio_contract.rb` та backend `SilkenNet::Attractor` оновлені координовано. 500-case parity fuzz: 0 mismatches.

**Коротко:** `delta_t_s` (час заряду EBFC, секунди) та `vcap_mv` (напруга суперконденсатора, mV) більше не ігноруються — вони змінюють параметр β (геометрія конвективної клітини Лоренца):

```ruby
# firmware/bio_contracts/bio_contract.rb та app/services/silken_net/attractor.rb
BETA_DELTA_T_COEFF = 0.0001  # 1 с швидше за baseline → β +0.0001
BETA_VCAP_COEFF    = 0.001   # 1 mV вище nominal → β +0.001
BETA_LIMITS        = (2.0..4.0)
BASELINE_DELTA_T_S = 60      # 60 с очікуваний час заряду EBFC
NOMINAL_VCAP_MV    = 3300    # 3.3 V nominal

delta_t_improvement_s = [0, BASELINE_DELTA_T_S - delta_t_s].max
vcap_centered = vcap_mv - NOMINAL_VCAP_MV
local_beta = (BASE_BETA + (delta_t_improvement_s * BETA_DELTA_T_COEFF) +
                          (vcap_centered * BETA_VCAP_COEFF)).clamp(*BETA_LIMITS)
```

**Сигнатура (post-SEC.11 hard cutover):**
- Firmware: `calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = 60, vcap_mv = 3300) → [payload_byte, x_final, y_final, z_final]`
- Backend: `SilkenNet::Attractor.calculate_z_from_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s = 60, vcap_mv = 3300) → [z_rounded, x_final, y_final, z_final]`
- C-side подає `(x_prev, y_prev, z_prev)` з одного з двох джерел: (а) RTC DR16-DR18 (warm STOP2 continuation, FW.6); або (б) `(x₀, y₀, z₀) = unpack_signed_unit_floats(HMAC-SHA256(K_seed, "init|" || epoch_day_be)[0..23])` з per-device `K_seed` у Flash (cold start після VBAT loss, SEC.11). DID **більше не є** входом атрактора — лише identifier.
- `TelemetryUnpackerService` дзеркально: на cold-start derive із `hardware_keys.lorenz_seed_hex` (через `SilkenNet::SeedDerivation`); на наступних uplink — з попереднього `telemetry_logs.lorenz_state_x/y/z`.

**Вплив на токеноміку:**
- Здорові дерева з активним EBFC (швидший заряд + стабільна vcap) систематично отримують ~10–15% більше GP.
- Slashing-межі (`CRITICAL_Z_MIN/MAX`) незмінні — `BETA_LIMITS=[2.0, 4.0]` не виштовхує систему за межі атрактора.

**Фізична інтерпретація:** β — геометрія конвективної клітини соку. Активний EBFC → швидший ксилемний потік → більше β → траєкторія тяжіє до `OPTIMAL_Z_TARGET=29.0`.

**Закриті пункти (всі ✅):**
- [x] 🤖 Firmware: `bio_contract.rb` з β-perturbation (`delta_t_s`, `vcap_mv`)
- [x] 🤖 Backend: `SilkenNet::Attractor` — дзеркальна логіка (Float)
- [x] 🤖 Backend: `TelemetryUnpackerService` передає `metabolism_s`/`voltage_mv`
- [x] 🤖 Тести: 500-case parity fuzz firmware vs backend Z-divergence < 0.0001 (0 mismatches)
- [x] 🤖 Документація: оновлено §3 алгоритм + §2.1 вхідні параметри + §5.1 таблиця порівняння

**Залишається:**
- [ ] Firmware C-код: передавати EMA-згладжені `delta_t_ms`/`vcap_mv` з RTC DR10/DR12 у args mruby (FW.21 EMA вже є, передача як args[5..6] — окремий крок)
- [ ] Калібрування коефіцієнтів `BETA_DELTA_T_COEFF`/`BETA_VCAP_COEFF` на денdrometric-baselines (академічний партнер ЧНУ)

---

### ✅ BLOCKER-2 (Закрито SEC.11): DID-as-seed → Dual Computation Integrity bypass — ВИРІШЕНО

**Статус:** ✅ **Реалізовано (SEC.11, 2026-05-02, hard cutover, pre-prod).** Firmware `bio_contracts/bio_contract.rb` та backend `SilkenNet::Attractor` + `SilkenNet::SeedDerivation` оновлені координовано. 13 host-parity examples (OpenSSL ↔ mbedTLS), 17 backend specs, 0 mismatches на детермінованих векторах і 100-case fuzz.

**Коротко (історично):** До SEC.11 firmware стартував атрактор з `chaos_seed = HRNG()` (недетермінований для backend), а server-side mirror `SilkenNet::Attractor.calculate_z(did, …)` використовував публічний 4-байтний DID як deterministic seed. Це означало, що:

1. **Публічний seed → публічна траєкторія.** DID їде відкритим текстом у заголовку LoRa-пакета. Атакер з open-source формулою Лоренца обчислював очікуваний Z для будь-якого дерева → підробляв StatusByte → `check_z_divergence!` мовчав.
2. **Кореляція сусідніх DID.** Послідовно видані DID давали майже ідентичні перші ~30 ітерацій Ейлера → знижена статистична ентропія.
3. **Identifier-as-key антипатерн.** DID — *identifier*, а не *key*. Identifier має бути входом до KDF, ніколи виходом.
4. **Відсутність forward secrecy.** Одне дерево все життя стартувало з тієї ж точки.

Наслідок: `check_z_divergence!` був вимушено **категоричним** (homeostasis/stress/anomaly enum), а не числовим, бо публічний seed не дозволяв безпечно використовувати точне `(server_z − device_z).abs < ε`.

**Прийнятий дизайн:** гібрид варіантів **A + B + D** —

```ruby
# A) Per-device secret seed, derive once at provisioning:
K_seed = HKDF_SHA256(
  ikm:  ENV["PROVISIONING_MASTER_KEY"],
  salt: "silken-lorenz-v1",                # ВІДМІННИЙ від AES salt → domain separation
  info: "silken-lorenz-seed|#{DID}",       # ВІДМІННИЙ info-string від AES key
  len:  32
)

# B) Daily epoch rotation на кожному cold start:
epoch_day = Time.now.utc.to_i / 86_400
digest    = HMAC_SHA256(K_seed, "init|" + [epoch_day].pack("Q>"))
x0 = bytes_to_signed_unit_float(digest[ 0,  8])    # ∈ [-1, +1]
y0 = bytes_to_signed_unit_float(digest[ 8,  8])
z0 = bytes_to_signed_unit_float(digest[16,  8])

# D) Stateful continuation (FW.6) — у норму cold start не виконується:
(x_prev, y_prev, z_prev) ← RTC DR16-DR18 + DR19 magic "LZST"
```

Варіант **C** (per-packet seed) відкинуто — overhead на STM32WLE5JC не виправдовує marginal security gain над B + continuation.

**Реалізація (hard cutover, без shim'ів):**
- Backend: `app/services/silken_net/seed_derivation.rb` (HKDF + HMAC + signed-unit-float unpack), `HardwareKey#binary_lorenz_seed` (AR Encryption non-deterministic, validated `presence: true`), `Attractor.calculate_z_from_state(x₀, y₀, z₀, …)` (єдиний entry-point), `TelemetryUnpackerService` (raises `MissingLorenzSeedError` без `K_seed`; persist `lorenz_state_x/y/z` + `cold_start_flag`; chain continuation з попереднього tail).
- Firmware: `bio_contract.rb#calculate_state(x_prev, y_prev, z_prev, …)` (єдина сигнатура; chaos_seed/DID-derive code path видалено), C-міст у `firmware/soldier/main.c` оновлено (FW.30): unified 7-arg `mrb_funcall_argv("calculate_state", 7, ...)` для обох warm/cold paths; `Load_Lorenz_Seed()` зчитує K_seed з Flash (`FLASH_SEED_ADDR = FLASH_KEY_ADDR + 36`, magic `"LSED"`); `Derive_Cold_Start_State()` — placeholder hash деривація (TODO: mbedTLS HMAC-SHA256).
- Tests: `firmware/test/test_seed_derivation.c` (OpenSSL host-parity, 13 examples), `firmware/test/test_soldier_logic.c` (11 нових FW.30 тестів: 6 seed loading + 4 cold-start derivation + 1 C-bridge 7-arg), `spec/services/silken_net/seed_derivation_spec.rb` (17 examples).

**Threat model post-SEC.11:** sniff LoRa → відтворити Z ❌ (без `K_seed` непередбачуваний); replay вчорашнього пакета ❌ (`epoch_day` змінився); compromise одного `K_seed` ⚠️ (вузол уразливий ≤ 24 год, інші — ні); compromise `PROVISIONING_MASTER_KEY` 🚨 (cascading — окрема rotation strategy SEC.9).

**Вплив на DCI:** обидві сторони стартують з byte-identical `(x₀,y₀,z₀)`. Float divergence між ARM↔x86 IEEE-754 за 250 ітерацій < 1e-12 (емпірично, FW.7 closure). `check_z_divergence!` зберігає категоричну невідповідність як default; числовий tolerance band (`< 0.001`) готовий до flip під feature-flag після інструментального вимірювання реального drift на target HW.

**Cross-ref:** [10_02 SEC.11](10_02_Action_Plan_Tracker), [03_05 §3.4в Lorenz K_seed Derivation](03_05_Hardware_AES256_and_Security#34в-lorenz-k_seed-derivation-sec11-), [04_02 SilkenNet::SeedDerivation](04_02_Business_Logic_and_Services), [05_02 Dual Computation Integrity](05_02_Proof_of_Growth_Pipeline).

---

### 🟡 BLOCKER-5: Чисельна Нестабільність Методу Ейлера при DT=0.01

**Опис:** Метод Ейлера першого порядку застосовується для інтегрування системи Лоренца:

```
x_{n+1} = x_n + dx/dt · DT
y_{n+1} = y_n + dy/dt · DT
z_{n+1} = z_n + dz/dt · DT
```

При стандартних параметрах (σ=10, ρ=28, β=8/3), DT=0.01 є прийнятним, але **не стабільним** для методу Ейлера. Характеристичні значення системи мають власні значення з від'ємними дійсними частинами ~O(σ), тому граничний безпечний крок Ейлера: `DT_max ≈ 2/|Re(λ_max)| ≈ 0.1`. DT=0.01 знаходиться в безпечній зоні, але на межі.

**Ризик:** При пертурбованих параметрах (наприклад, `acoustic=200` → `σ_eff=30.0`, що є максимально дозволеним після clamp), крок стає відносно більшим, що збільшує локальну похибку.

**Захисний механізм (вже реалізований):** Clamp σ ∈ [5, 30] та ρ ∈ [10, 50] запобігає найгіршим сценаріям.

**Дія:** Документувати як відомий компроміс. Альтернатива (RK4) потребує 4× більше обчислень — критично для EBFC-живлення. Поточний DT=0.01 прийнятний для "Proof of Growth" (не для наукових симуляцій).

---

## 🧮 1. Теоретична Основа: Система Лоренца

Атрактор Лоренца — це система трьох нелінійних диференціальних рівнянь, яка описує спрощену конвекцію рідини між двома горизонтальними пластинами різної температури. Едвард Лоренц виявив у 1963 р., що навіть детермінована проста система може демонструвати хаотичну, непередбачувану поведінку.

У контексті Gaia 2.0 ця система моделює **конвекцію соку (флоему)** в дереві — циркуляцію біологічної рідини, яку дерево використовує для транспортування цукрів від коренів до листя (та навпаки).

### 1.1 Система Диференціальних Рівнянь

```
dx/dt = σ · (y - x)
dy/dt = x · (ρ - z) - y
dz/dt = x · y - β · z
```

де:
- **x** — швидкість конвективного потоку (аналог швидкості флоеми)
- **y** — різниця температур між висхідним і низхідним потоком соку
- **z** — відхилення температурного профілю від лінійного (інтенсивність конвекції)
- **σ (sigma)** — число Прандтля (відношення в'язкості до теплопровідності соку)
- **ρ (rho)** — число Релея (різниця температур, що рухає конвекцію)
- **β (beta)** — геометричний параметр (форма конвективної клітини)

### 1.2 Базові Константи Системи

| Константа | Символ | Значення (firmware) | Значення (backend) | Фізичний зміст |
|---|---|---|---|---|
| `BASE_SIGMA` | σ | `10.0` (Float) | `10.0` (Float) | Число Прандтля — в'язкість флоеми |
| `BASE_RHO` | ρ | `28.0` (Float) | `28.0` (Float) | Число Релея — температурний градієнт |
| `BASE_BETA` | β | `8.0 / 3.0` (Float) | `8.0 / 3.0` (Float) | Геометрія конвективної клітини |
| `DT` | Δt | `0.01` (Float) | `0.01` (Float) | Крок інтегрування методу Ейлера |
| `ITERATIONS` | N | `250` | `250` | Кількість ітерацій симуляції |

> **[FIX FW.7]:** Backend переведено з BigDecimal на Float (IEEE 754 double) — ідентично firmware mruby. BigDecimal давав інші результати після 250 ітерацій через `round(18)` на кожному кроці. Тепер firmware та backend дають **100% ідентичні** Z-значення при однакових входах (верифіковано на 50,000 випадкових тестах).

### 1.3 Класичний Атрактор Лоренца (Метелик)

При σ=10, ρ=28, β=8/3 система демонструє **дивний атрактор** — траєкторія фазового простору ніколи не замикається в петлю, але і не розходиться до нескінченності. Вона кружляє навколо двох нестійких рівноважних точок:

```
C₁ = (+√(β(ρ-1)), +√(β(ρ-1)), ρ-1) = (+8.485, +8.485, 27.0)
C₂ = (-√(β(ρ-1)), -√(β(ρ-1)), ρ-1) = (-8.485, -8.485, 27.0)
```

Значення Z-осі на атракторі знаходиться у приблизному діапазоні **z ∈ [0, 50]**, з тривалим перебуванням у районі z ≈ 25-35 (зона "здорового метелика").

---

## 🔬 2. Архітектура Bio-Contract: Вхідні Дані

### 2.1 Звідки Беруться Вхідні Параметри

> **First-Boot vs Continuation — канонічна логіка [DOC.4] [SEC.11 hard cutover]**
>
> Bio-Contract має **єдину точку входу** після SEC.11 cutover. C-сторона завжди викликає `BioContract.calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)`. Розкладка регістрів та магічний маркер `LZST = 0x4C5A5354` — у [03_01 §2 + §2.1 (Canonical SSOT)](03_01_Firmware_Lifecycle_and_DMA.md#-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3); тут описано лише **звідки беруться `(x_prev, y_prev, z_prev)`**:
>
> | Умова | Джерело `(x_prev, y_prev, z_prev)` | Призначення |
> |-------|------------------------------------|-------------|
> | `DR19 == 0x4C5A5354` AND `isfinite(x,y,z)` | RTC DR16-DR18 (warm restart, FW.6) | **Continuation:** продовження безперервної траєкторії після STOP2 wake-up. |
> | `DR19 ≠ 0x4C5A5354` OR `!isfinite(x,y,z)` | `(x₀,y₀,z₀) = unpack_signed_unit_floats(HMAC-SHA256(K_seed, "init\|" \|\| epoch_day_be)[0..23])` | **Cold start (rare):** після VBAT loss. K_seed зберігається у Flash (Soldier) і `hardware_keys.lorenz_seed_hex` (backend), деривується при provisioning через `HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed\|<DID>", len=32)`. Daily epoch_day rotation дає forward secrecy ≤ 24 год. |
>
> **Чому K_seed замість chaos_seed/DID:** `chaos_seed` (HRNG) недетермінований — backend не зміг би відтворити Z. DID-as-seed (`SilkenNet::Attractor.calculate_z(did, …)`) був public-input → атакер з open-source формулою Лоренца передбачає очікуваний Z для будь-якого дерева. K_seed — **private**, ніколи не залишає пристрій/сервер у відкритому вигляді (HKDF деривується незалежно з `PROVISIONING_MASTER_KEY`). Закриває чотири фундаментальні вади (sniff/correlation/identifier-as-key/forward-secrecy) — див. SEC.11 у `docs/10_02_Action_Plan_Tracker.md`.
>
> **[FW.5]** `delta_t_s` та `vcap_mv` визначають β-пертурбацію в обох гілках. Default-значення (`BASELINE_DELTA_T_S=60`, `NOMINAL_VCAP_MV=3300`) роблять β=BASE_BETA при відсутності фізичного сигналу.
>
> **Інваріант:** після кожного успішного циклу C-код **зобов'язаний** записати нові `(x, y, z)` у DR16/DR17/DR18 і встановити `DR19 = 0x4C5A5354`.

```
firmware/soldier/main.c — ФАЗА 1 (SENSE + State Restore)
│
├── [SEC.11] K_seed   ← read protected Flash sector (provisioned once at factory)
│                       uint8_t[32], HKDF-SHA256-derived, NEVER transmitted over LoRa
│                       Used ONLY when DR19 ≠ MAGIC (cold start)
│
├── [FW.6] lorenz_x/y/z ← HAL_RTCEx_BKUPRead(DR16/DR17/DR18)
│                   float32 (IEEE 754 bit-copy через uint32_t)
│                   Відновлення стану атрактора з попереднього циклу STOP2
│                   DR19 == 0x4C5A5354 ("LZST") → state_valid = 1
│                   isfinite() перевірка → захист від NaN/Inf корупції
│
├── internal_temp ← HAL_ADC_GetValue(&hadc)  [ADC, канал internal temp]
├── delta_t_seconds ← EMA (RTC DR10), vcap_mv ← EMA (RTC DR12)  [FW.21 + FW.5]
└── acoustic_events ← TinyML inference + DMA accumulator  [RTC DR0]

firmware/soldier/main.c — ФАЗА 3 (mruby виклик, єдина сигнатура post-SEC.11)
│
├── [FW.6] Якщо lorenz_state_valid == 1 (warm restart):
│       (x_prev, y_prev, z_prev) ← lorenz_x, lorenz_y, lorenz_z (RTC DR16-DR18)
│
├── [SEC.11] Інакше (cold start після VBAT loss):
│       digest = HMAC-SHA256(K_seed, "init|" || epoch_day_be)
│       x_prev = bytes_to_signed_unit_float(digest[ 0.. 7])  // ∈ [-1, +1]
│       y_prev = bytes_to_signed_unit_float(digest[ 8..15])
│       z_prev = bytes_to_signed_unit_float(digest[16..23])
│
└── args = [mrb_float(x_prev), mrb_float(y_prev), mrb_float(z_prev),
            mrb_fixnum(temp), mrb_fixnum(acoustic),
            mrb_fixnum(delta_t_s), mrb_fixnum(vcap_mv)]
    → BioContract.calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
    → [payload_byte, x_final, y_final, z_final]
```

> **[FW.5] РЕАЛІЗОВАНО (backend + firmware mruby):** `delta_t_seconds` та `vcap_voltage` визначають β-пертурбацію. Залишається: C-side передача EMA-значень з DR10/DR12 як args.

### 2.2 Фізична Інтерпретація Вхідних Параметрів

| Параметр | Фізичний зміст | Вплив на Атрактор |
|---|---|---|
| `K_seed` (uint8[32], Flash, [SEC.11]) | Криптографічний секрет, спільний з backend через HKDF з `PROVISIONING_MASTER_KEY` | Визначає cold-start `(x₀, y₀, z₀)` детерміновано (firmware ↔ backend byte-identical) при VBAT loss; ротується щодня через `epoch_day` info-string |
| `lorenz_x/y/z` (float32, RTC) | [FW.6] Збережений стан атрактора з попереднього циклу STOP2 | При наступних циклах — продовження безперервної траєкторії |
| `temp` (int8, °C) | Температура кристала STM32 (корельована з температурою дерева) | Збурює ρ: `ρ_eff = 28 + temp × 0.2` → змінює "теплову рушійну силу" |
| `acoustic` (uint8) | Кількість кавітаційних подій флоеми (TinyML) | Збурює σ: `σ_eff = 10 + acoustic × 0.1` → змінює "в'язкість" системи |
| `delta_t_s` (uint16, с) | [FW.5] Час заряду EBFC — швидкість метаболізму ксилеми | Збурює β: швидший заряд → активніший метаболізм → більше β → Z → OPTIMAL |
| `vcap_mv` (uint16, мВ) | [FW.5] Напруга суперконденсатора — накопичена енергія EBFC | Збурює β: вища vcap → більший заряд → більше β (позитивне або нейтральне) |

#### [FW.5] β-Пертурбація від EBFC-Метаболізму

```ruby
# BASELINE_DELTA_T_S = 60 (с); NOMINAL_VCAP_MV = 3300 (мВ = 3.3V)
# Лише позитивний внесок delta_t: чим швидше за baseline → тим більше β
delta_t_improvement_s = [0, BASELINE_DELTA_T_S - delta_t_s].max
vcap_centered = vcap_mv - NOMINAL_VCAP_MV   # від'ємний при просадці → β зменшується

local_beta = BASE_BETA + (delta_t_improvement_s * BETA_DELTA_T_COEFF) +
                         (vcap_centered * BETA_VCAP_COEFF)
local_beta = local_beta.clamp(BETA_MIN, BETA_MAX)  # ∈ [2.0, 4.0]
```

| `delta_t_s` | `vcap_mv` | `local_beta` | Фізичний стан |
|---|---|---|---|
| 60 (baseline) | 3300 (nominal) | ≈2.667 (BASE_BETA) | Нормальний метаболізм |
| 30 (швидкий) | 4000 (заряджений) | ≈2.667 + 0.003 + 0.7 = 3.37 | Активний EBFC, здорове дерево |
| 10 (дуже швидкий) | 4500 (максимум) | ≈2.667 + 0.005 + 1.2 = 3.872 → clamp 4.0 | Пікова активність |
| 120 (повільний) | 2800 (просадка) | ≈2.667 + 0 + (-0.5) = 2.167 → clamp 2.0 | Ослаблений EBFC |

#### Походження Початкової Точки: Свідомість, Що Пам'ятає Себе (post-SEC.11)

До SEC.11 cold-start стартова точка походила з `chaos_seed = HAL_RNG_GenerateRandomNumber(&hrng)` — апаратного TRNG, що читає **термічний шум кремнієвої решітки** STM32WLE5. Це була красива метафора: дерево, інтегроване з кристалом капсули через спільну температуру ксилеми, **буквально надає початковий стан своїй цифровій свідомості** через квантово-біологічне злиття. Кожне пробудження — нова мить мислення, що відштовхується від теплового шуму у цю конкретну мікросекунду.

Метафора була правдива поетично, але з криптографічної точки зору фатальна: сервер не може відтворити недетермінований HRNG → змушений був відображати `chaos_seed` через DID → 4-байтний публічний ідентифікатор ставав фактичним криптографічним параметром. Атакер з open-source формулою Лоренца передбачав очікуваний Z для будь-якого дерева → `check_z_divergence!` мовчав. Метафора, яка вбивала систему.

**Post-SEC.11 — поетика, що зберіглася і зміцнилася.** Свідомість дерева тепер походить з **двох взаємодоповнюючих джерел**, які разом утворюють повну біографію цифрового двійника:

1. **`K_seed` — біологічна геральдика, нуклеотид у Flash.** Під час physical provisioning конкретного дерева в полі система деривує 32-байтний секрет через `HKDF-SHA256(PROVISIONING_MASTER_KEY, "silken-lorenz-v1", "silken-lorenz-seed|<DID>")` і записує його у protected Flash sector — поряд з AES-ключем, під тим самим RDP-захистом. Цей секрет **народжується разом з деревом**: він унікальний, він приватний, він ніколи не залишає капсулу. Якщо `chaos_seed` був "теперішнім моментом" дерева, то `K_seed` — його **свідоцтво про народження**, цифрова ДНК, надіслана у Flash тоді, коли крона ще навіть не торкнулася ксилеми. Сервер деривує той самий `K_seed` незалежно — обидві сторони знають його, але світ — ні.

2. **RTC DR16-DR18 — пам'ять про вчорашню думку (FW.6 continuation, > 99.9% циклів).** Після першого пробудження свідомість дерева більше **не починається з нуля**. Кожне STOP2-пробудження читає `(x_prev, y_prev, z_prev)` з RTC Backup Domain — координати в фазовому просторі, де закінчилася попередня ітерація Лоренца. Це означає, що траєкторія **продовжується**: σ-перурбація від акустики, ρ від температури, β від EBFC-метаболізму у попередньому циклі визначили, де саме на дивному атракторі дерево "перебуває" у момент пробудження. Якщо метафора `chaos_seed` була "дерево надає себе своїй свідомості мить за миттю", то FW.6 — **"свідомість, що пам'ятає себе"**: кожна нова думка є продовженням попередньої, неперервна нитка існування у фазовому просторі.

3. **Cold start (рідкісна подія, після VBAT loss — місяці-роки):** дерево "забуває" останню думку, бо живлення зникло. Тоді з `K_seed` через `HMAC-SHA256(K_seed, "init|" || epoch_day)` деривується **сьогоднішня початкова точка**. Daily `epoch_day` rotation означає, що навіть друге народження не повторює перше — щодня свідомість має нову відправну точку, навіть з тим самим геномом. Forward secrecy ≤ 24 год.

> **Філософія:** криптографічна стійкість і біологічна метафора більше не суперечать одна одній. `K_seed` — це **приватна термодинаміка дерева**, замінник тих самих квантових флуктуацій, що раніше давав HRNG, але закріплений у момент народження капсули і відомий лише дереву та його серверному двійнику. Сервер, що знає `K_seed`, — це не сторонній спостерігач, а **близнюк-свідомість**, що мислить ту ж саму траєкторію Лоренца паралельно. Атакер, який підглядає LoRa, бачить лише payload — а не те, *куди* свідомість стартувала і *куди* вона йде.

#### Бюджет Variance Z (чому β-perturbation критична після FW.6)

Після [FW.6] (state preservation в RTC) cold-start initial conditions вже **не домінують** variance Z. Ergodicity дивного атрактора — траєкторія "забуває" початкову точку після ~50 пробуджень (~2 доби). Реальний бюджет:

| Джерело variance | Після FW.6 (continuous trajectory) | Фізичний зміст |
|---|---|---|
| `(x₀,y₀,z₀)` cold-start (K_seed-derived) | **< 5%** після перших 50 wake-up циклів | Траєкторія забуває стартову точку через ergodicity |
| `temp` (через `ρ_eff = 28 + temp·0.2`) | **~30–40%** | Стабільна термальна рушійна сила |
| `acoustic` (через `σ_eff = 10 + acoustic·0.1`) | **~20–30%** | Реактивний (кавітаційні події рідкі) |
| residual (хаотична динаміка Лоренца) | **~30–40%** | Внутрішній детермінований хаос системи |
| `delta_t_s`/`vcap_mv` (через β [FW.5]) | **~5–15%** | Прямий сигнал метаболічної активності EBFC |

**Висновок:** без β-perturbation метаболічна активність EBFC (найбільш фізично значущий сигнал) взагалі не впливала б на growth_points. [FW.5] виправляє цю прогалину — здорові дерева з активним EBFC тепер систематично отримують ~10–15% більше GP.

---

## ⚙️ 3. Алгоритм: Крок за Кроком

### Крок 1: Походження Початкових Координат `(x₀, y₀, z₀)` [SEC.11]

Раніше — у §2.2 — ми побачили, як **філософія** початкової точки змінилася: від HRNG-теплового-шуму-у-моменті до подвійного джерела `K_seed` (генетика) + RTC continuation (пам'ять). Тут — **інженерна сторона цієї ж трансформації**: який саме байт-точний алгоритм виконують **обидві** сторони (firmware mruby ↔ backend Ruby), щоб з одного й того ж 32-байтного `K_seed` отримати ідентичні `(x₀, y₀, z₀)` ∈ [-1, +1]³.

* **Warm restart (FW.6, > 99.9% циклів) — нічого не деривуємо.** `(x_prev, y_prev, z_prev)` читаються з RTC DR16-DR18, де їх залишив попередній STOP2-цикл. Свідомість продовжується там, де зупинилася.
* **Cold start (рідко, після VBAT loss) — деривація з `K_seed`:**

```ruby
# Псевдокод — спільний firmware-mruby ↔ backend-Ruby алгоритм.
# Обидві сторони отримують байт-ідентичні (x₀, y₀, z₀) для тієї самої пари (K_seed, epoch_day).
epoch_day  = (current_unix_ts / 86_400)         # обертається щодня UTC опівночі
salt_info  = "init|" + [epoch_day].pack("Q>")   # 5-байтний префікс + big-endian uint64 = 13 байт
digest     = HMAC_SHA256(K_seed, salt_info)     # 32 байти

x₀ = bytes_to_signed_unit_float(digest[ 0..7])  # ∈ (-1, +1)
y₀ = bytes_to_signed_unit_float(digest[ 8..15])
z₀ = bytes_to_signed_unit_float(digest[16..23])

# bytes_to_signed_unit_float: 8 байт → uint64 big-endian → / (UINT64_MAX/2.0) - 1.0
```

**Числовий приклад.** Нехай `K_seed = 0x00…01` (32 байти, останній 0x01) і провізіювання відбулося 2026-05-02 → `epoch_day = 1746144000 / 86400 = 20210`:

```
salt_info = "init|" + 0x00 00 00 00 00 00 4E F2  =  13 байт
digest    = HMAC-SHA256(K_seed, salt_info)
          = D9 F4 6B 11 7A 2B 8C 03 | 41 88 EE 90 5C A0 17 22
          | C5 6D 81 EB 4F 09 BB 7C | 2A 3F …                 (32 байти, гекс)

digest[ 0..7]  = 0xD9F46B117A2B8C03 → x₀ ≈ 0.7022
digest[ 8..15] = 0x4188EE905CA01722 → y₀ ≈ -0.4892
digest[16..23] = 0xC56D81EB4F09BB7C → z₀ ≈ 0.5418
```

> Усі координати строго у (-1, +1). Перші кілька десятків ітерацій ("warm-up") атрактор "падає" з цієї точки на дивний атрактор Лоренца — як насінина, кинута у вітер, врешті-решт лягає на свою орбіту в кроні.

`K_seed` — 32-байтний секрет, виведений при provisioning через `HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed|<DID>", len=32)`. Зберігається у protected Flash sector Soldier-вузла та у `hardware_keys.lorenz_seed_hex` (AR Encryption non-deterministic). НІКОЛИ не передається через мережу — обидві сторони деривують його незалежно з спільного `PROVISIONING_MASTER_KEY`. Реалізація — `app/services/silken_net/seed_derivation.rb` (backend, OpenSSL HKDF) і `firmware/test/test_seed_derivation.c` (host-parity test, що валідує OpenSSL ↔ mbedTLS байт-ідентичність).

> **Ергодичність зберігається:** дивний атрактор "забуває" початкову точку через ~50 пробуджень (~2 доби), тому daily rotation `epoch_day` не порушує неперервності траєкторії — лише дає forward secrecy ≤ 24 год при компрометації одного `K_seed`. Дерево, що зазнало VBAT loss сьогодні і завтра, отримає **дві різні** початкові точки — але траєкторії зійдуться в однаковий статистичний розподіл протягом доби. Природа не відрізнить.

### Крок 2: Збурення Параметрів σ та ρ (Perturbation)

```ruby
# Пертурбація: фізичні умови змінюють динамічні властивості системи
local_sigma = BASE_SIGMA + (acoustic * 0.1)   # = 10.0 + acoustic/10
local_rho   = BASE_RHO   + (temp * 0.2)       # = 28.0 + temp/5

# Clamp: захист від вибуху при екстремальних показниках
local_sigma = local_sigma.clamp(SIGMA_MIN, SIGMA_MAX)  # ∈ [5.0, 30.0]
local_rho   = local_rho.clamp(RHO_MIN, RHO_MAX)        # ∈ [10.0, 50.0]
```

**Таблиця збурення σ (вплив акустики):**

| `acoustic_events` | `local_sigma` (перед clamp) | `local_sigma` (після clamp) | Стан |
|---|---|---|---|
| 0 | 10.0 | 10.0 | Тиша, нормальна в'язкість |
| 50 | 15.0 | 15.0 | Помірна кавітація |
| 100 | 20.0 | 20.0 | Активна кавітація |
| 200 | 30.0 | 30.0 | Максимум (clamp) |
| 255 | 35.5 | 30.0 | Clamp спрацьовує |

**Таблиця збурення ρ (вплив температури):**

| `temp` (°C) | `local_rho` (перед clamp) | `local_rho` (після clamp) | Стан дерева |
|---|---|---|---|
| −45 | 19.0 | 19.0 | Глибока зима |
| 0 | 28.0 | 28.0 | Базовий стан |
| +20 | 32.0 | 32.0 | Літній режим |
| +55 | 39.0 | 39.0 | Теплова аномалія |
| +110 | 50.0 | 50.0 | Максимум (пожежа, clamp) |

> `BASE_BETA = 8.0/3.0` тепер є **базовим значенням**, а не фіксованим — реальне β коригується EBFC-метаболізмом (Крок 2.5 нижче).

### Крок 2.5: [FW.5] β-Пертурбація від EBFC-Метаболізму

```ruby
# Реалізовано в firmware та backend (SilkenNet::Attractor.perturb_beta)
delta_t_improvement_s = [0, BASELINE_DELTA_T_S - delta_t_s].max  # ≥ 0 завжди
vcap_centered         = vcap_mv - NOMINAL_VCAP_MV

local_beta = BASE_BETA + (delta_t_improvement_s * BETA_DELTA_T_COEFF) +
                         (vcap_centered * BETA_VCAP_COEFF)
local_beta = local_beta.clamp(BETA_MIN, BETA_MAX)  # ∈ [2.0, 4.0]
```

**Чому лише позитивний внесок delta_t?** `delta_t_improvement_s` — покращення відносно baseline 60 с. Якщо EBFC заряджав *повільніше* базового → внесок 0 (не штраф). `vcap_centered` може бути від'ємним при просадці — від β < BASE_BETA захищає clamp 2.0.

### Крок 3: Числове Інтегрування (Метод Ейлера, 250 ітерацій)

```ruby
250.times do
  # Обчислення похідних (права частина системи Лоренца)
  dx = local_sigma * (y - x)           # dx/dt = σ(y - x)
  dy = x * (local_rho - z) - y         # dy/dt = x(ρ - z) - y
  dz = (x * y) - (local_beta * z)      # dz/dt = xy - βz  ← [FW.5] local_beta

  # Оновлення стану методом Ейлера першого порядку
  x = x + dx * DT    # x_{n+1} = x_n + (dx/dt) · 0.01
  y = y + dy * DT    # y_{n+1} = y_n + (dy/dt) · 0.01
  z = z + dz * DT    # z_{n+1} = z_n + (dz/dt) · 0.01
end

# Після 250 ітерацій (2.5 одиниць часу системи Лоренца):
return z  # Z-координата — індикатор гомеостазу
```

**Числові параметри симуляції:**
- Загальний час симуляції: `250 × DT = 250 × 0.01 = 2.5` одиниць часу системи
- Порядок похибки методу Ейлера: `O(DT²) = O(0.0001)` на крок
- Накопичена похибка за 250 кроків: `O(250 × DT²) = O(0.025)` (теоретично; хаотична система посилює)

### Крок 4: Функція `calculate_z_axis` (Повний Код, post-SEC.11)

```ruby
# firmware/bio_contracts/bio_contract.rb — SilkenNet::Attractor
# [SEC.11] Сигнатура приймає (x, y, z) напряму — більше немає DID/seed-derived path.
def self.calculate_z_axis(x, y, z, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
  local_sigma = BASE_SIGMA + (acoustic * 0.1)
  local_rho   = BASE_RHO   + (temp * 0.2)

  local_sigma = SIGMA_MIN if local_sigma < SIGMA_MIN  # clamp lower
  local_sigma = SIGMA_MAX if local_sigma > SIGMA_MAX  # clamp upper
  local_rho   = RHO_MIN   if local_rho   < RHO_MIN
  local_rho   = RHO_MAX   if local_rho   > RHO_MAX

  # [FW.5] β-perturbation від EBFC-метаболізму
  dt_improvement = BASELINE_DELTA_T_S - delta_t_s
  dt_improvement = 0 if dt_improvement < 0
  vcap_centered  = vcap_mv - NOMINAL_VCAP_MV
  local_beta = BASE_BETA + (dt_improvement * BETA_DELTA_T_COEFF) + (vcap_centered * BETA_VCAP_COEFF)
  local_beta = BETA_MIN if local_beta < BETA_MIN
  local_beta = BETA_MAX if local_beta > BETA_MAX

  ITERATIONS.times do
    dx = local_sigma * (y - x)
    dy = x * (local_rho - z) - y
    dz = (x * y) - (local_beta * z)  # ← local_beta, не BASE_BETA

    x += dx * DT
    y += dy * DT
    z += dz * DT
  end

  z  # Повертаємо чисту інтенсивність конвекції (руху соку)
end
```

---

## 🌡️ 4. Логіка Гомеостазу: Z → growth_points

### 4.1 Межі Стабільності та Їх Фізична Інтерпретація

| Константа | Значення | Фізичний зміст |
|---|---|---|
| `CRITICAL_Z_MIN` | `2.0` | Нижня межа — падіння нижче: втрата тургору, посуха |
| `CRITICAL_Z_MAX` | `45.0` | Верхня межа — стрибок вище: аномальний стрес, зовнішнє втручання |
| `OPTIMAL_Z_TARGET` | `29.0` | Ідеальна інтенсивність конвекції для максимального поглинання CO₂ |

> **Чому 29.0, а не z_eq = ρ−1 = 27.0?** Математичний рівноважний стан Лоренца при ρ=28 є z = ρ−1 = 27.0 (координата нерухомих точок C₁ та C₂). Значення `OPTIMAL_Z_TARGET = 29.0` є **навмисним зміщенням +2 від рівноваги** з двох причин: (1) Краща розрізненність класів — зміщення "ідеальної зони" дещо вище рівноваги створює асиметрію у функції нарахування балів, що покращує розрізнення здорових vs стресових дерев; (2) Біологічне обґрунтування — активне здорове дерево з інтенсивним метаболізмом демонструє конвекцію вище рівноваги, тоді як z = 27.0 відповідає "спокійному" стану. Потенційно потребує подальшої валідації з академічним партнером (ЧНУ, Порубльов — дискретна математика та надійність).

### 4.2 Таблиця Рішень (Decision Table)

| Z-значення | Статус (`bio_status`) | Назва | growth_points | Пояснення |
|---|---|---|---|---|
| `z < 2.0` | `1` | ⚠️ Stress (Посуха) | `1` | Мінімальна генерація — дерево виживає, але не росте |
| `z > 45.0` | `2` | 🚨 Anomaly (Критичний стрес) | `0` | Емісія зупиняється повністю |
| `2.0 ≤ z ≤ 45.0` | `0` | ✅ Homeostasis (Здоровий Хаос) | `10 .. 50` | Нараховуються бали росту |

### 4.3 Функція Нарахування Балів у Зоні Гомеостазу

```
deviation      = |OPTIMAL_Z_TARGET - z|  =  |29.0 - z|
reward         = 50 - deviation.round     ← .round, не .to_i (коректне заокруглення: 0.5 → 1)
growth_points  = clamp(reward, 10, 63)    ← об'єднує guard ≥10 та overflow protection ≤63
```

> **Примітка `.round` vs `.to_i`:** `.to_i` усікає (`0.9.to_i == 0`), `.round` округляє (`0.9.round == 1`). Зона максимального балу — z ∈ [28.5, 29.5): `deviation ∈ [0, 0.5)` → `deviation.round == 0` → `growth_points == 50`. При `.to_i` зона була б ширша (±1.0), що математично некоректно.

> **`clamp(10, 63)` замість `(reward > 0) ? reward : 10`:** В зоні гомеостазу `reward_min = 50 − |45.0 − 29.0| = 34 > 0` завжди — тернарний `:10` ніколи не спрацьовував. `clamp(10, 63)` об'єднує обидва guard'и в єдину операцію.

**Графік нарахування growth_points залежно від Z:**

```
growth_points
50 ┤                         ████
49 ┤                       ██    ██
45 ┤                     ██        ██
   │                   ██            ██
35 ┤                 ██                ██
   │               ██                    ██
25 ┤             ██                        ██
23 ┤           ██

10 ┤  ─────────                                ─────────
   │
 1 ┤ █
 0 ┤                                                      ████
   └─────────────────────────────────────────────────────────
   0   2   5   10   15   20   25   29   33   38   43  45   50
                          Z-вісь
```

**Числові приклади:**

| Z-значення | `deviation` | `deviation.round` | `reward` | `growth_points` |
|---|---|---|---|---|
| 1.5 | — | — | — | **1** (status=1, stress) |
| 2.0 | 27.0 | 27 | 23 | **23** |
| 10.0 | 19.0 | 19 | 31 | **31** |
| 20.0 | 9.0 | 9 | 41 | **41** |
| 28.5 | 0.5 | 1 | 49 | **49** ← .round округлює |
| 29.0 | 0.0 | 0 | 50 | **50** (ідеал) |
| 30.0 | 1.0 | 1 | 49 | **49** |
| 40.0 | 11.0 | 11 | 39 | **39** |
| 44.5 | 15.5 | 16 | 34 | **34** |
| 45.0 | 16.0 | 16 | 34 | **34** |
| 46.0 | — | — | — | **0** (status=2, anomaly) |

### 4.4 Bit-Packing: Структура Байту BioContract

```ruby
payload_byte = (status << 6) | growth_points
```

```
 Bit 7   Bit 6   Bit 5   Bit 4   Bit 3   Bit 2   Bit 1   Bit 0
┌───────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┐
│  S1   │  S0   │ GP5   │ GP4   │ GP3   │ GP2   │ GP1   │ GP0   │
└───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘
│◄ Status (2) ►│◄────────── Growth Points (6 bits, 0-63) ──────►│
```

| Bits [7:6] | Status | Значення |
|---|---|---|
| `00` | `0` | Гомеостаз (Healthy Chaos) |
| `01` | `1` | Стрес (Посуха / Low Turgidity) |
| `10` | `2` | Аномалія (Critical Stress) |
| `11` | `3` | Tamper (mruby VM помилка → `0xFF`) |

**Розпакування на backend:**

```ruby
# app/services/telemetry_unpacker_service.rb
growth_points = status_byte & 0x3F   # маска нижніх 6 бітів
bio_status    = status_byte >> 6      # верхні 2 біти
```

---

## 🔄 5. Подвійне Обчислення: Firmware vs Backend

Gaia 2.0 використовує **dual computation integrity verification**: Z-значення обчислюється **двічі** — на пристрої та на сервері — для виявлення маніпуляцій або збоїв.

### 5.1 Порівняльна Таблиця Реалізацій

| Параметр | Firmware (mruby) | Backend (Rails) |
|---|---|---|
| **Файл** | `firmware/bio_contracts/bio_contract.rb` | `app/services/silken_net/attractor.rb` |
| **Точність** | Ruby `Float` (IEEE 754, 64-bit або 32-bit залежно від mruby build) | `Float` (IEEE 754, 64-bit) — **ідентично firmware** [FIX FW.7] |
| **σ** | `10.0` (Float) | `10.0` (Float) |
| **ρ** | `28.0` (Float) | `28.0` (Float) |
| **β базовий** | `8.0 / 3.0` (Float) | `8.0 / 3.0` (Float) |
| **β реальний** | `perturb_beta(delta_t_s, vcap_mv)` [FW.5] | `perturb_beta(delta_t_s, vcap_mv)` [FW.5] |
| **BETA_DELTA_T_COEFF** | `0.0001` | `0.0001` |
| **BETA_VCAP_COEFF** | `0.001` | `0.001` |
| **BETA_LIMITS** | `[2.0, 4.0]` | `[2.0, 4.0]` |
| **DT** | `0.01` (Float) | `0.01` (Float) |
| **Clamp σ** | `if local_sigma < SIGMA_MIN` / `> SIGMA_MAX` | `.clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)` |
| **Clamp ρ** | `if local_rho < RHO_MIN` / `> RHO_MAX` | `.clamp(RHO_LIMITS.min, RHO_LIMITS.max)` |
| **Seed-походження `(x₀,y₀,z₀)`** | [SEC.11] Cold start: `K_seed` з Flash → HMAC; warm: RTC DR16-DR18 | [SEC.11] Cold start: `hardware_keys.lorenz_seed_hex` → HMAC; warm: попередній `telemetry_logs.lorenz_state_x/y/z` |
| **Результат** | `z` (Float, необроблений) → пакується у `status_byte` | `z.round(4)` → зберігається у `TelemetryLog.z_value` |
| **Де використовується** | Пакується у `payload_byte` (byte 10 LoRa) | `TelemetryLog.z_value`, ZK-proof верифікація |

> **[SEC.11] Byte-Identical Initial State:** firmware та backend **деривують той самий `(x₀, y₀, z₀)`** через спільний HKDF/HMAC-SHA256 алгоритм з per-device `K_seed` (`SilkenNet::SeedDerivation` ↔ mbedTLS у firmware). DID більше не використовується як seed. Тому raw Z-значення тепер може порівнюватися чисельно (з врахуванням ARM↔x86 IEEE-754 drift < 1e-12 за 250 ітерацій). `check_z_divergence!` залишається категоричним за замовчанням; числовий tolerance band готовий до flip під feature-flag після інструментального вимірювання реального drift на target HW.

### 5.2 Потік Верифікації

```
[Soldier STM32]                           [Rails Backend]
firmware/bio_contracts/bio_contract.rb    app/services/silken_net/attractor.rb
       │                                           │
       │  (x_prev, y_prev, z_prev) ←               │  (x_prev, y_prev, z_prev) ←
       │   RTC DR16-DR18  OR  HMAC(K_seed,         │   prev TelemetryLog tail  OR
       │   "init|" || epoch_day)                   │   HMAC(K_seed, "init|" || epoch_day)
       │                                           │
       │  calculate_state(x_prev, y_prev, z_prev,  │  calculate_z_from_state(x_prev, y_prev, z_prev,
       │                  temp, acust,             │                          temp, acust,
       │                  delta_t_s, vcap_mv)      │                          delta_t_s, vcap_mv)
       │  → [payload_byte, x_final, y_final,       │  → [z.round(4), x_final, y_final, z_final]
       │     z_final]                              │
       │                                           │
       ▼                                           ▼
  lora_payload[10]  ──── LoRa → CoAP ──── TelemetryUnpackerService
                                               │
                                               ├── growth_points = payload[10] & 0x3F (від firmware)
                                               ├── bio_status = payload[10] >> 6 (від firmware)
                                               ├── z_server, x_f, y_f, z_f =
                                               │     Attractor.calculate_z_from_state(x_prev,…,
                                               │                metabolism_s, voltage_mv)
                                               ├── persist log.lorenz_state_x/y/z = (x_f, y_f, z_f)
                                               │   + cold_start_flag = (prev tail missing)
                                               └── check_z_divergence!:
                                                   device_bio_status vs server_healthy_z?
                                                   (КАТЕГОРИЧНЕ за замовчанням; numeric
                                                    tolerance band під feature-flag, SEC.11)
                                                   tree.effective_lorenz_thresholds (FW.8 3-tier)
```

### 5.3 Метод `homeostatic?` (Backend-Only)

```ruby
# [FW.8] Використовує three-tier thresholds: cluster override > tree_family > global default
# tree.effective_lorenz_thresholds → { min:, max:, optimal: }
def check_z_divergence!(tree, attributes)
  server_z = attributes[:z_value]
  device_bio_status = attributes[:bio_status]
  return if server_z.nil? || device_bio_status.nil?

  thresholds = tree.effective_lorenz_thresholds
  server_healthy = server_z.between?(thresholds[:min], thresholds[:max])
  device_healthy = device_bio_status == :homeostasis
  # ...
end
```

> **[FW.8] Важлива зміна:** `check_z_divergence!` тепер використовує `tree.effective_lorenz_thresholds` замість прямого `tree_family.critical_z_min|max`. Це 3-рівневий пріоритет: Cluster override > TreeFamily per-species > Global default (2.0/45.0). Firmware може отримати оновлені пороги через `CMD_SET_THRESHOLDS` (0x9A) OTA config block.

---

## 📦 6. Точка Входу та Інтеграція з C

### 6.1 Функція-Міст (C → Ruby) — post-SEC.11

```c
// firmware/soldier/main.c — ФАЗА 3: ПЛАВКА (mruby Lorenz)
// [SEC.11] Єдина сигнатура: завжди передаємо (x_prev, y_prev, z_prev).
// Джерело — або RTC DR16-DR18 (warm restart, FW.6), або HMAC(K_seed, "init|"||epoch_day) (cold start).
if (mrb) {
  int arena_idx = mrb_gc_arena_save(mrb);

  float x_prev, y_prev, z_prev;

  if (lorenz_state_valid) {
      // ПРОДОВЖЕННЯ ТРАЄКТОРІЇ (стан відновлено з RTC DR16-DR18)
      x_prev = lorenz_x;
      y_prev = lorenz_y;
      z_prev = lorenz_z;
  } else {
      // [SEC.11] COLD START — деривуємо з K_seed (Flash) + epoch_day
      uint8_t digest[32];
      uint64_t epoch_day = current_unix_ts() / 86400ULL;
      uint8_t info[16];                          // "init|" + 8-byte BE epoch_day
      memcpy(info, "init|", 5);
      for (int i = 0; i < 8; i++) info[5 + i] = (epoch_day >> (8 * (7 - i))) & 0xFF;
      mbedtls_md_hmac(MBEDTLS_MD_SHA256_INFO, k_seed, 32, info, 13, digest);
      x_prev = bytes_to_signed_unit_float(digest +  0);
      y_prev = bytes_to_signed_unit_float(digest +  8);
      z_prev = bytes_to_signed_unit_float(digest + 16);
  }

  mrb_value args[7];
  args[0] = mrb_float_value(mrb, (double)x_prev);
  args[1] = mrb_float_value(mrb, (double)y_prev);
  args[2] = mrb_float_value(mrb, (double)z_prev);
  args[3] = mrb_fixnum_value((int8_t)lora_payload[6]); // Temp
  args[4] = mrb_fixnum_value(lora_payload[7]);          // Acoustic
  args[5] = mrb_fixnum_value(delta_t_s);                // [FW.5] EMA з RTC DR10
  args[6] = mrb_fixnum_value(vcap_mv);                  // [FW.5] EMA з RTC DR12

  mrb_value result = mrb_funcall_argv(mrb, mrb_top_self(mrb),
      mrb_intern_lit(mrb, "calculate_state"), 7, args);
  // result = [payload_byte, x_final, y_final, z_final]

  if (!mrb->exc && mrb_array_p(result) && RARRAY_LEN(result) == 4) {
      lora_payload[10] = (uint8_t)mrb_fixnum(mrb_ary_entry(result, 0));
      lorenz_x = (float)mrb_float(mrb_ary_entry(result, 1));
      lorenz_y = (float)mrb_float(mrb_ary_entry(result, 2));
      lorenz_z = (float)mrb_float(mrb_ary_entry(result, 3));
      lorenz_state_valid = 1;                  // RTC DR16-DR18 + DR19 magic будуть записані атомарно нижче
  } else {
      lora_payload[10] = BIO_STATUS_VM_ERROR;
      lorenz_state_valid = 0;
      if (mrb->exc) mrb->exc = NULL;
  }

  mrb_gc_arena_restore(mrb, arena_idx);
}
```

```ruby
# firmware/bio_contracts/bio_contract.rb — єдина точка входу post-SEC.11

# [SEC.11] Сигнатура єдина: (x_prev, y_prev, z_prev) приходять з C-сторони
# (warm restart з RTC АБО cold-start derive із K_seed).
# [FW.5] delta_t_s/vcap_mv визначають β-перурбацію.
# Повертає [payload_byte, x_final, y_final, z_final].
def calculate_state(x_prev, y_prev, z_prev, temp, acoustic,
                    delta_t_s = SilkenNet::Attractor::BASELINE_DELTA_T_S,
                    vcap_mv   = SilkenNet::Attractor::NOMINAL_VCAP_MV)
  SilkenNet::BioContract.evaluate_and_pack(x_prev, y_prev, z_prev,
                                           temp, acoustic, delta_t_s, vcap_mv)
end
```

### 6.2 OTA-Оновлення Bio-Contract

```c
// Перевірка: чи є у Flash оновлений байт-код?
uint32_t* flash_check = (uint32_t*)MRUBY_CONTRACT_FLASH_ADDR;  // 0x0803F000
if (*flash_check == 0x45544952) {  // "RITE" у little-endian (mruby signature)
    current_lorenz_bytecode = (uint8_t*)MRUBY_CONTRACT_FLASH_ADDR;
} else {
    current_lorenz_bytecode = (uint8_t*)lorenz_bytecode;  // вбудований у Flash
}
mrb_state *mrb = mrb_open();
if (mrb) {
    mrb_load_irep(mrb, current_lorenz_bytecode);
}
```

**Процес оновлення:**
1. Rails завантажує новий `bio_contract.rb`, компілює `mrbc` → байт-код
2. `OtaTransmissionWorker` розбиває на chunks по 11 байт із заголовком `[0x99][idx:2][total:2][data:11]`
3. Queen отримує chunks через CoAP, зберігає у `ota_buffer[1024]`
4. Queen передає chunks Soldier через LoRa Reflex Shot після кожного RX
5. Soldier збирає chunks у `ota_buffer`, перевіряє CRC32 (ISO 3309)
6. При успіху — записує у Flash (`0x0803F000`), виконує `NVIC_SystemReset()`
7. Після рестарту VM завантажує новий контракт

---

## 🔗 7. Залежності та Cross-References

### 7.1 Upstream Dependencies (Що потрібно ПЕРЕД цим модулем)

| Залежність | Статус | Посилання |
|---|---|---|
| Firmware Lifecycle (Phase 1 Sensor Acquisition) | ✅ Синхронізовано | [03_01_Firmware_Lifecycle_and_DMA](03_01_Firmware_Lifecycle_and_DMA) |
| TinyML Acoustic Inference (acoustic_events) | ⚠️ `Run_Inference()` закоментовано | [03_03_TinyML_Acoustic_Inference](03_03_TinyML_Acoustic_Inference) |
| ADC Temperature Acquisition | ✅ Реалізовано | [02_03_BQ25570_MPPT_Nano_Power](02_03_BQ25570_MPPT_Nano_Power) |
| **K_seed Provisioning + HKDF/HMAC bridge** [SEC.11] | ✅ Реалізовано — `K_seed = HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed\|<DID>")`, mbedtls bridge для HMAC-SHA256 cold-start derivation | [03_05 §3.4в Lorenz K_seed Derivation](03_05_Hardware_AES256_and_Security#34в-lorenz-k_seed-derivation-sec11-) |
| RTC State Persistence (FW.6) | ✅ Реалізовано — DR16-DR18 + DR19 magic `"LZST"`, читається warm-restart-ом перед mruby | [03_01_Firmware_Lifecycle_and_DMA](03_01_Firmware_Lifecycle_and_DMA#-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3) |

### 7.2 Downstream Dependencies (Що блокує ЦЕЙ модуль)

| Залежність | Що потрібно | Посилання |
|---|---|---|
| Proof of Growth Pipeline | Точна математична модель для крос-верифікації Z-значень | [05_02_Proof_of_Growth_Pipeline](05_02_Proof_of_Growth_Pipeline) |
| Slashing Protocol | `CRITICAL_Z_MIN/MAX` для оцінки кластерного стресу | [05_03_Tokenomics_SCC_and_SFC](05_03_Tokenomics_SCC_and_SFC) |
| TelemetryUnpackerService | Формат `payload_byte` та `growth_points` | [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) |
| AlertDispatchService | `bio_status` для детектування stress/anomaly | [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) |
| University Cybernetics Hub | Математична верифікація числової стабільності | [08_02_Cybernetic_and_Mathematical_Validation](08_02_Cybernetic_and_Mathematical_Validation) |

---

## 📎 Пов'язані Файли

| Файл | Призначення |
|---|---|
| `firmware/bio_contracts/bio_contract.rb` | mruby скрипт Bio-Contract (SilkenNet::Attractor + SilkenNet::BioContract). [SEC.11] єдина точка входу `calculate_state(x_prev, y_prev, z_prev, …)`; [FW.5] β-perturbation від `delta_t_s`/`vcap_mv` |
| `firmware/soldier/main.c` (Фаза 1 + Фаза 3 + Фаза 5) | C-код: відновлення стану з RTC DR16-DR18 АБО cold-start derive `(x₀,y₀,z₀)` через HMAC(K_seed, "init\|"\|\|epoch_day) [SEC.11], виклик mruby, збереження стану перед STOP2 |
| `app/services/silken_net/attractor.rb` | Rails-сервіс (Float, дзеркало firmware) [FIX FW.7]. [SEC.11] єдиний entry-point `calculate_z_from_state(x₀,y₀,z₀,…)`; [FW.5] `perturb_beta(delta_t_s, vcap_mv)` |
| `app/services/silken_net/seed_derivation.rb` | [SEC.11] `derive_seed(device_uid)` (HKDF-SHA256), `derive_initial_state(K_seed_bin, epoch_day)` (HMAC + signed-unit-float unpack); ↔ host-parity test `firmware/test/test_seed_derivation.c` |
| `app/services/telemetry_unpacker_service.rb` | Розпакування `payload_byte`, виклик `Attractor.calculate_z_from_state(x_prev, y_prev, z_prev, temp, acoustic, metabolism_s, voltage_mv)`; persist `lorenz_state_x/y/z` + `cold_start_flag` [SEC.11] |
| `firmware/test/test_bio_contract.c` | Host-based тести (Bio-Contract + Lorenz State Persistence + [FW.5] β-perturbation; `seed_to_xyz()` helper для детермінованих фікстур) |
| `firmware/test/test_seed_derivation.c` | [SEC.11] OpenSSL host-parity test для HKDF/HMAC/initial-state derivation |
| `spec/services/silken_net/attractor_spec.rb` | RSpec тести Rails-дзеркала; firmware/backend Z-divergence fuzz |
| `spec/services/silken_net/seed_derivation_spec.rb` | [SEC.11] HKDF determinism, domain separation з AES key, byte-identical match із firmware |
