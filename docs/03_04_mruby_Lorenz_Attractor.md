# 03_04: mruby Атрактор Лоренца (Математика Хаосу та Гомеостаз)

---

## 🎯 Мета

Задокументувати повний алгоритм **Bio-Contract** — mruby-скрипту, що виконується на борту вузла **Soldier** (STM32WLE5JC) і обчислює стан гомеостазу дерева через Атрактор Лоренца. Цей документ є SSOT для:

- **Backend (`TelemetryUnpackerService`)**: сервер знає точну математичну модель і може перевіряти коректність надісланих деревом `growth_points`.
- **Proof of Growth Pipeline (05_02)**: мінтинг SCC заблокований, поки бекенд не розуміє математику, що генерує бали.
- **University R&D (08_02)**: академічна верифікація числової стабільності методу Ейлера у системі Лоренца.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — Lorenz атрактор bitwise-identical firmware↔backend (FW.7 Float parity, 50k fuzz); SEC.11 seed provenance закрито. Канонічний дім Lorenz-констант (§1.2). Відкрите: numeric DCI ε flip (`FW.31`, deferred) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [03_01_Firmware_Lifecycle_and_DMA](03_01_Firmware_Lifecycle_and_DMA) | Soldier lifecycle; RTC DR16-18 Lorenz state (FW.6) |
| [03_03_TinyML_Acoustic_Inference](03_03_TinyML_Acoustic_Inference) | `acoustic_events` → σ-пертурбація |
| [03_05_Hardware_Symmetric_Crypto_and_Security](03_05_Hardware_Symmetric_Crypto_and_Security) | §3.4в K_seed derivation (SEC.11, HKDF/HMAC) |
| [04_02_Business_Logic_and_Services](04_02_Business_Logic_and_Services) | TelemetryUnpacker, SeedDerivation, DCI check |
| [05_02_Proof_of_Growth_Pipeline](05_02_Proof_of_Growth_Pipeline) | Dual Computation Integrity (Z крос-верифікація) |
| [05_03_Tokenomics_SCC_and_SFC](05_03_Tokenomics_SCC_and_SFC) | CRITICAL_Z_MIN/MAX → slashing |
| [08_02_Cybernetic_and_Mathematical_Validation](08_02_Cybernetic_and_Mathematical_Validation) | Матем. верифікація числової стабільності |
| `firmware/bio_contracts/bio_contract.rb` · `app/services/silken_net/attractor.rb` · `seed_derivation.rb` | mruby + Rails-дзеркало (Float parity); SEC.11 entry-point |
| [00_07_Action_Plan_Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): FW.31 numeric-DCI flip (deferred); FW.45 fixed-point hardening |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Теоретична Основа: Система Лоренца](#-1-теоретична-основа-система-лоренца)
- [2. Архітектура Bio-Contract: Вхідні Дані](#-2-архітектура-bio-contract-вхідні-дані)
- [3. Алгоритм: Крок за Кроком](#-3-алгоритм-крок-за-кроком)
- [4. Логіка Гомеостазу: Z → growth_points](#-4-логіка-гомеостазу-z--growth_points)
- [5. Подвійне Обчислення: Firmware vs Backend](#-5-подвійне-обчислення-firmware-vs-backend)
- [6. Точка Входу та Інтеграція з C](#-6-точка-входу-та-інтеграція-з-c)
- [6.3 Майбутнє: Forest-Level Lorenz Coupling (Beyond TRL 9)](#-63-майбутнє-forest-level-lorenz-coupling-beyond-trl-9)
- [7. Відомі Обмеження та Deferred-Фічі](#-7-відомі-обмеження-та-deferred-фічі)
<!-- TOC:AUTO:END -->

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

> **[Майбутнє hardening — Integer/Fixed-Point Math, не реалізовано]** Float-парність вирішує bit-identity для пари x86-64 ↔ ARM Cortex-M4 з FPU (обидві архітектури — IEEE 754 binary64). Вона **НЕ гарантує** парності для:
> (a) MCU без FPU (емуляція через soft-float дає той самий двійковий результат у переважній більшості випадків, але не завжди для денормалізованих);
> (b) mruby збірок з `MRB_USE_FLOAT32` (32-bit Float — не наш випадок, але можливий регрес);
> (c) майбутніх ZK-circuits, де float взагалі недоступний.
>
> Третій рівень hardening — **fixed-point Q-формат:** вхідні дані × 10⁶, всі арифметичні операції у `int64_t`/Ruby `Integer` (немає overflow до 2⁶³ ≈ 9.2·10¹⁸). Тоді результат **бітово ідентичний на будь-якому процесорі**, від AVR до zkVM.
>
> Ціна: повне переписування `firmware/bio_contracts/bio_contract.rb`, `app/services/silken_net/attractor.rb`, всіх 50k parity-тестів, плюс ручне керування overflow (квадрати/добутки потрібно зрізати до Q-формату на кожному кроці Ейлера). Робота S→L залежно від обсягу регресії. Цінність — лише при переході до ZK-proof Lorenz (Risc Zero / SP1) або при підтримці радикально іншої HW-цілі (RV32E без FPU, тощо). До цього моменту Float-парність достатня. Зафіксовано як `[FW.45] Integer-Math Lorenz hardening — deferred until ZK-circuit milestone` у `docs/00_07_Action_Plan_Tracker`.

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
> Bio-Contract має **єдину точку входу** після SEC.11 cutover. C-сторона завжди викликає `BioContract.calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)`. Розкладка регістрів та магічний маркер `LZST = 0x4C5A5354` — у [03_01 §2 + §2.1 (Canonical SSOT)](03_01_Firmware_Lifecycle_and_DMA#-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3); тут описано лише **звідки беруться `(x_prev, y_prev, z_prev)`**:
>
> | Умова | Джерело `(x_prev, y_prev, z_prev)` | Призначення |
> |-------|------------------------------------|-------------|
> | `DR19 == 0x4C5A5354` AND `isfinite(x,y,z)` | RTC DR16-DR18 (warm restart, FW.6) | **Continuation:** продовження безперервної траєкторії після STOP2 wake-up. |
> | `DR19 ≠ 0x4C5A5354` OR `!isfinite(x,y,z)` | `(x₀,y₀,z₀) = unpack_signed_unit_floats(HMAC-SHA256(K_seed, "init\|" \|\| epoch_day_be)[0..23])` | **Cold start (rare):** після VBAT loss. K_seed зберігається у Flash (Soldier) і `hardware_keys.lorenz_seed_hex` (backend), деривується при provisioning через `HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed\|<DID>", len=32)`. Daily epoch_day rotation дає forward secrecy ≤ 24 год. |
>
> **Чому K_seed замість chaos_seed/DID:** `chaos_seed` (HRNG) недетермінований — backend не зміг би відтворити Z. DID-as-seed (`SilkenNet::Attractor.calculate_z(did, …)`) був public-input → атакер з open-source формулою Лоренца передбачає очікуваний Z для будь-якого дерева. K_seed — **private**, ніколи не залишає пристрій/сервер у відкритому вигляді (HKDF деривується незалежно з `PROVISIONING_MASTER_KEY`). Закриває чотири фундаментальні вади (sniff/correlation/identifier-as-key/forward-secrecy) — див. SEC.11 у `docs/00_07_Action_Plan_Tracker`.
>
> **[FW.5]** `delta_t_s` та `vcap_mv` визначають β-пертурбацію в обох гілках. Default-значення (`BASELINE_DELTA_T_S=60`, `NOMINAL_VCAP_MV=3300`) роблять β=BASE_BETA при відсутності фізичного сигналу.
>
> **Інваріант:** після кожного успішного циклу C-код **зобов'язаний** записати нові `(x, y, z)` у DR16/DR17/DR18 і встановити `DR19 = 0x4C5A5354`.

> ⚠️ **Cold-Start Time Paradox (ARCH.41, відкрите питання):** Cold-start деривація `(x₀,y₀,z₀)` залежить від `epoch_day`. Після **VBAT loss** RTC Soldier'а скидається на default-дату (2000-01-01 у поточному firmware), тож `approx_days ≈ 10 951` замість сьогоднішнього серверного `≈ 20 585` (на 2026-05-16). Перший uplink після cold-boot використає «застарілий» epoch_day, поки Soldier не отримає `CMD_TIME_SYNC` beacon від Queen (FW.20). Це означає:
>
> - **Firmware:** `Derive_Cold_Start_State()` у `firmware/soldier/main.c:2242` свідомо документує цей gap (`TEMPORARY: Month*30 approximation` + `cross-month boot drift`).
> - **Backend:** `TelemetryUnpackerService#compute_server_z` сьогодні **уникає** проблеми у >99% випадків через `previous_lorenz_state_for(tree)` chaining (server бере хвіст останнього TelemetryLog, не cold-derive). Cold-derive виконується лише коли у дерева **немає історії** (вперше підключений вузол). У такому сценарії server бере `Time.now.utc.to_i / 86_400` — і Soldier з RTC=2000-01-01 не співпаде з server-day.
> - **Сценарій тонкого розриву:** VBAT loss у дерева **з історією** → Soldier cold-restart'ить Lorenz з RTC-default epoch_day, server chain'ить з попереднього хвоста → траєкторії розходяться категорично на ергодичному горизонті ~50 циклів (≈ 2 доби), доки `CMD_TIME_SYNC` не дочекається наступного CoAP downlink'у. Сьогодні numeric DCI branch (`GAIA_DCI_NUMERIC_TOLERANCE`) інертний у production (LoRa packet 21B не несе device_z), тож на DCI це поки **не валиться** — але блокує майбутній numeric tolerance band, якщо `device_z` додасться у wire-формат.
>
> **Мітигація:**
> 1. **Server-side detect-and-recover** ✅ **Реалізовано (2026-05-17, ARCH.41 Option A):** `TelemetryUnpackerService#try_time_sync_recovery` — коли `cold_start_flag == false` (є історія) АЛЕ категоричний DCI мисматч, пробує 3 кандидати `epoch_day` (today, today−1, `FIRMWARE_RTC_DEFAULT_EPOCH_DAY=10_951`). Для кожного: `SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)` → `Attractor.calculate_z_from_state(...)` → категорична перевірка. При збігу: `TelemetryLog#time_unsynced_fallback = true`, `TimeSyncDownlinkWorker.perform_async(cluster_id)` (envelope-only CoAP → Queen RTC → LoRa beacon → Soldier sync). fraud_metric НЕ інкрементується. 9 spec examples.
> 2. **Soldier-side explicit signal** — забронювати 1 біт у Status Byte (наразі лише `[PanicFlag:1 | Status:2 | GrowthPoints:5]` — все зайнято) АБО у Pad (наразі firmware_version_id у байтах 0..1 + panic_counter у байтах 2..3 — все зайнято) під `time_uncertain_flag`. Це wire-format change → blocked by наступним packet revision. Простіше: при cold-boot Soldier інкрементує спеціальне значення в `acoustic_events` (наприклад, `0xFE` — щоб не сплутати з `255 = saturated`) як sentinel; backend трактує як «time uncertain». Не ламає wire-format, але вимагає координованого rollout firmware.
> 3. **Architectural альтернатива — defer first uplink** — Soldier при cold-boot не відсилає uplink до отримання `CMD_TIME_SYNC` beacon (max 10 хв grace, `TIME_SYNC_COLD_BOOT_GRACE_MS`). Просто, але ламає OTA Reflex Shot первинний trigger (Queen чекає uplink Soldier'а щоб надіслати OTA). Можна обійти: Soldier у grace-вікні шле **спрощений «hello» пакет** без Lorenz state, тільки DID + Vcap + `TIME_REQ` маркер.
>
> Найдешевший плановий шлях для TRL 7 — варіант 1 (server-side fallback) + опційно варіант 2 (sentinel у acoustic_events). Tracker: див. **ARCH.41** у [00_07](00_07_Action_Plan_Tracker).

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

- **Warm restart (FW.6, > 99.9% циклів) — нічого не деривуємо.** `(x_prev, y_prev, z_prev)` читаються з RTC DR16-DR18, де їх залишив попередній STOP2-цикл. Свідомість продовжується там, де зупинилася.
- **Cold start (рідко, після VBAT loss) — деривація з `K_seed`:**

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

> **⚠️ [Lorenz de-risk, 2026-05-29]** Мапінг **Z → bio_status / growth_points нижче — недоведена гіпотеза**, не встановлений факт. Межі (`CRITICAL_Z_MIN/MAX`, `OPTIMAL_Z_TARGET`) обґрунтовані теоретично, але потребують ground-truth ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)). Політика: фінансовий slashing **ніколи** не спирається лише на Z — Z є одним із сигналів `stress_index` поряд із прямими (sap_flow / VPD / acoustic). Lorenz-**DCI** (anti-fraud, device-Z vs server-Z) валідний **незалежно** від результату валідації. Деталі — [`05_05 §7`](05_05_Slashing_and_Risk_Policy).

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
| `2.0 ≤ z ≤ 45.0` | `0` | ✅ Homeostasis (Здоровий Хаос) | `5 .. 31` (wire); `10 .. 62` (stored after backend ×2 upscale) | Нараховуються бали росту |

### 4.3 Функція Нарахування Балів у Зоні Гомеостазу

```
deviation      = |OPTIMAL_Z_TARGET - z|  =  |29.0 - z|
reward         = 50 - deviation.round              ← .round, не .to_i (коректне заокруглення: 0.5 → 1)
# [FW.29-PACK] Wire-діапазон скорочено з 6-біт (10..63) до 5-біт (5..31)
# щоб звільнити bit 7 під PANIC_FLAG_BIT (FW.29). Backend ×2 upscale при unpack
# зберігає tokenomic emission rate (effective stored 10..62 vs old 10..63).
growth_points  = (reward / 2).clamp(5, 31)
```

> **Примітка `.round` vs `.to_i`:** `.to_i` усікає (`0.9.to_i == 0`), `.round` округляє (`0.9.round == 1`). Зона максимального балу — z ∈ [28.5, 29.5): `deviation ∈ [0, 0.5)` → `deviation.round == 0` → wire `growth_points == 25` → stored `50`. При `.to_i` зона була б ширша (±1.0), що математично некоректно.

> **`(reward / 2).clamp(5, 31)` замість `clamp(reward, 10, 63)`:** [FW.29-PACK] StatusByte layout після FW.29 — `[PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)]`. Wire-діапазон growth_points = 5 біт = 0..31. `(reward / 2)` масштабує тіло homeostasis [10..50] → [5..25]; clamp(5, 31) залишає margin зверху. Backend `(status_byte & 0x1F) * 2` повертає до stored 0..62.

**Графік нарахування `reward` (= stored growth_points) залежно від Z:**

> Графік показує **stored**-значення (0..50) — це Wire ×2 після backend upscale. Wire-значення у пакеті — це Stored / 2 (діапазон 5..25 у homeostasis після `(reward / 2).clamp(5, 31)`).

```
reward / stored growth_points
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

> 📐 **Wire vs Stored:** Wire `growth_points` (те, що йде в LoRa-пакеті) — це 5-бітне поле `(reward / 2).clamp(5, 31)`. Backend `TelemetryUnpackerService` робить `(status_byte & 0x1F) * 2`, повертаючи Stored. Колонка **Wire** — це що Soldier пакує у Status Byte; **Stored** — те, що бачить `TelemetryLog#growth_points`.

| Z-значення | `deviation` | `deviation.round` | `reward` | **Wire `growth_points`** (5-bit, packed) | **Stored** (backend ×2) |
|---|---|---|---|---|---|
| 1.5 | — | — | — | **1** (status=1, stress) | 2 |
| 2.0 | 27.0 | 27 | 23 | **11** (`23/2 → clamp`) | 22 |
| 10.0 | 19.0 | 19 | 31 | **15** | 30 |
| 20.0 | 9.0 | 9 | 41 | **20** | 40 |
| 28.5 | 0.5 | 1 | 49 | **24** ← .round округлює | 48 |
| 29.0 | 0.0 | 0 | 50 | **25** (ідеал) | 50 |
| 30.0 | 1.0 | 1 | 49 | **24** | 48 |
| 40.0 | 11.0 | 11 | 39 | **19** | 38 |
| 44.5 | 15.5 | 16 | 34 | **17** | 34 |
| 45.0 | 16.0 | 16 | 34 | **17** | 34 |
| 46.0 | — | — | — | **0** (status=2, anomaly) | 0 |

### 4.4 Bit-Packing: Структура Байту BioContract

```ruby
# [FW.29-PACK] Wire layout: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)].
# Bit 7 (PANIC_FLAG_BIT, FW.29) для нормальних пакетів завжди 0
# (`lora_payload[10] &= ~PANIC_FLAG_BIT`), для panic-пакетів завжди 1.
payload_byte = (status << 5) | growth_points
```

```
 Bit 7   Bit 6   Bit 5   Bit 4   Bit 3   Bit 2   Bit 1   Bit 0
┌───────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┐
│PANIC  │  S1   │  S0   │ GP4   │ GP3   │ GP2   │ GP1   │ GP0   │
└───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘
│PanicFlag│◄ Status (2) ►│◄────── Growth Points (5 bits, 0-31) ──►│
   FW.29       FW.29-PACK
```

| Bits [6:5] | Status | Значення |
|---|---|---|
| `00` | `0` | Гомеостаз (Healthy Chaos) |
| `01` | `1` | Стрес (Посуха / Low Turgidity) |
| `10` | `2` | Аномалія (Critical Stress) |
| `11` | `3` | Tamper (mruby VM помилка → `0xFF` після firmware mask `& 0x7F` = `0x7F`) |

**Розпакування на backend:**

```ruby
# app/services/telemetry_unpacker_service.rb
# [FW.29-PACK] +×2 upscale зберігає tokenomic invariant — stored 0..62 vs wire 0..31
growth_points = (status_byte & 0x1F) * 2     # bits 4..0 (×2 backend upscale)
bio_status    = (status_byte >> 5) & 0x03    # bits 6..5
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
                                               ├── growth_points = (payload[10] & 0x1F) * 2  [FW.29-PACK ×2 upscale]
                                               ├── bio_status = (payload[10] >> 5) & 0x03   [FW.29-PACK bits 6..5]
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

## 🌌 6.3 Майбутнє: Forest-Level Lorenz Coupling (Beyond TRL 9)

> **Контекст:** Поточна архітектура запускає Lorenz attractor **ізольовано на кожному дереві** — `bio_contract.rb` бачить лише власні `delta_t/temp/acoustic`, не знає нічого про сусідів. Це **достатньо для TRL 9** (commercial product), але **обмежує систему до сенсорної мережі**, а не нервової системи лісу.
>
> **Майбутній напрям (Beyond TRL 9 / SRL roadmap) — Chimera States у network of coupled attractors:** розширити `bio_contract.rb` так, щоб входи атрактора містили **aggregated neighbor signals** (median Z у кластері за останню годину, отриманий через stigmergic LoRa-broadcast). Це дає математично описуваний колективний гомеостаз — теорія Куромото-Баттогтох (2002) **chimera states** передбачає, що такі мережі утворюють частково синхронізовані, частково хаотичні patterns, які точно віддзеркалюють реальну структуру здорового лісу.
>
> **Партнери:** Кирилюк (синергетика економічних систем, `08_01 §1.4`), Гусак (нелінійна динаміка, `08_01 §1.2`), Порубльов (кібернетика FOTIUS, `08_02`).
>
> **Деталі повної R&D-програми:** [`00_03 §7.1`](00_03_TRL_Matrix_HIL_and_Beyond) — Forest-Level Emergence Gap.

---

## ⚠️ 7. Відомі Обмеження та Deferred-Фічі

### 7.1 Numeric Tolerance Band — DCI ε (deferred, code-staged; `00_07 FW.31`)


**Контекст:** SEC.11 закрив BLOCKER-2 і відкрив технічну можливість використовувати **числовий** DCI-перевірний крок (`|server_z − device_z| < ε`) замість суто **категоричного** enum-match'у. Числова перевірка значно потужніша: дозволяє ловити replay-атаки з правильним StatusByte, але неправильною Z-magnitude (наприклад, attacker викликав легітимний enum через clamp-логіку, але справжня траєкторія розійшлася). Категорична перевірка пропускає такі сценарії.

**Стан коду (✅ ready, awaits lab data):** Feature-flag реалізовано у [`TelemetryUnpackerService#check_z_divergence!`](04_02_Business_Logic_and_Services) (2026-05-02). У production-середовищі branch неактивний — це навмисно. Активація через Kamal env, **без code change та без redeploy** контейнера.

**ENV-контракт:**

| ENV | Default | Тип | Семантика |
|-----|---------|-----|-----------|
| `GAIA_DCI_NUMERIC_TOLERANCE` | unset → `false` | Boolean (`true`/`1`/`yes`) | Вмикає numeric branch **on top of** категоричної перевірки (не замінює). Категоричний enum-match завжди виконується першим. |
| `GAIA_DCI_NUMERIC_EPSILON` | `0.001` (constant `TelemetryUnpackerService::DEFAULT_DCI_EPSILON`) | Float (parsed via `Float()`) | Tolerance threshold. Malformed/non-numeric value → graceful fallback до DEFAULT_DCI_EPSILON + `Rails.logger.warn`. |

**Гейт активації — `device_z` має бути в payload:**

Numeric branch виконується **лише** коли `attributes[:device_z]` присутній. Сьогодні LoRa packet 21B (`Soldier → Queen`) **не несе** raw Z — фірмварний `bio_contract.rb#calculate_state` повертає тільки `status_byte = [PanicFlag:1 | Status:2 | GrowthPoints:5]` (FW.29-PACK). Branch стає активним після одного з:

1. **FW.2 CCM transition** (24-байтний пакет, [`03_05 §3.2 BLOCKER-2`](03_05_Hardware_Symmetric_Crypto_and_Security)) — якщо при перепакуванні зарезервувати ≥2 байти на стиснутий Z (наприклад, [E.7 ARCH.22 lambda-exponent](05_02_Proof_of_Growth_Pipeline)).
2. **Окремий пакет-варіант ML2** — рідкісний uplink (~1/добу) із повним Z-snapshot для калібровки.
3. **Server-side surrogate** — backend сам обчислює `device_z` зі збереженого `(x_prev, y_prev, z_prev)` chain'у + telemetry inputs, як референс для self-check (це робить numeric branch ефективно lab-only).

До цього часу — branch інертний, але код вже staged у production без поведінкової зміни.

**Lab measurement protocol (pre-flip gate):**

Потрібно фактично виміряти ARM↔x86 IEEE-754 drift на цільовому залізі, перш ніж довірити numeric ε фінансовим рішенням (slashing, mint). Емпірика [FW.7](../00_07_Action_Plan_Tracker.md) дала `< 1e-12` теоретично — але без instrumented testing цифру не можна "закладати в конституцію".

| Крок | Дія | Артефакт |
|------|-----|----------|
| 1 | Згенерувати N=10 000 детермінованих тест-векторів через `SilkenNet::SeedDerivation` для синтетичних `K_seed` (різні per-vector) + випадкові `(temp, acoustic, delta_t_s, vcap_mv)` у валідних діапазонах | `firmware/test/test_dci_drift_vectors.json` (gitignored, recreatable) |
| 2 | Прогнати ті самі вектори через `Attractor.calculate_z_from_state` на GCP x86-64 (production-mirror Docker image) | CSV: `vector_id, server_z` |
| 3 | Прошити test-фірмвар на STM32WLE5JC (REVB silicon, той самий що у Pilot Site), прогнати вектори через mruby `calculate_state`, прочитати Z через SWD/RTT | CSV: `vector_id, device_z` |
| 4 | Diff: `device_z − server_z` distribution. Скласти histogram (logspace bins для tail), розрахувати p50/p99/p99.9/p99.99/max | Jupyter notebook `analysis/dci_drift_distribution.ipynb` (deferred) |
| 5 | Перевірити нульовий drift на subset, де `chaos_seed → byte-identical (x₀,y₀,z₀)` (SEC.11 invariant) — будь-який non-zero drift тут = баг в seed derivation, не Float | Assertion у notebook |
| 6 | Обрати ε := max(p99.99, 2 × max_observed_drift). Якщо ε ≥ 0.1 — Lorenz dynamics зламана й треба окремо розбиратися (ARCH.18 fixed-point). Якщо ε < 0.0001 — поставити `0.001` як conservative default (надлишок margin) | Кеп ε у `DEFAULT_DCI_EPSILON` constant + PR |

**Rollout gates (порядок активації):**

1. **Gate L (Lab):** Lab measurement виконано, ε обраний, distribution stored.
2. **Gate D (Device coverage):** `device_z` доступний у ≥ 95% telemetry packets (після FW.2 wire revision АБО після ML2 variant).
3. **Gate C (Canary):** Активація в `WEB3_STRICT_MODE=false` staging кластері на 24 год. Watch `silkennet_dci_numeric_rejections_total` (новий Prometheus counter, додати в [`06_03`](06_03_Prometheus_Observability) після Gate D). Очікувано: 0 rejections (бо ε > max observed drift у Gate L). Будь-яке non-zero rejection → analiza root cause (seed corruption? RTC drift? overflow?) перед production.
4. **Gate P (Production canary):** Single Genesis cluster, `GAIA_DCI_NUMERIC_TOLERANCE=true` через `kamal env push`, моніторинг 72 год.
5. **Gate G (Global):** Flip всіх production кластерів.

**Rollback procedure:**

```bash
# Kamal env push без redeploy:
kamal env push --secret GAIA_DCI_NUMERIC_TOLERANCE=false
# АБО видалити з .kamal/secrets, тоді next deploy картки залишиться без флагу
```

Жоден код-rollback не потрібен — feature-flag перетворює numeric branch на no-op. Категорична перевірка продовжує захищати DCI.

**Side effects після flip:**

- Fraud detection стає **числовим**: ловить replay-атаки з правильним enum, неправильним magnitude — як написано у §145 вище.
- `TelemetryLog#fraud_flagged` зростає на ~0.001-0.01% legitimate traffic (false positives на ε boundary) — це **acceptable noise**, бо `fraud_flagged` тригерить ручний review, не automatic slashing.
- Mint pipeline ([`05_02`](05_02_Proof_of_Growth_Pipeline)) НЕ блокується numeric divergence — це лише signal для AML/risk layer.

**Specs (вже в коді):**

`spec/services/telemetry_unpacker_service_spec.rb` describe `[FW.31] numeric tolerance band` — 6 examples:
1. toggle off (default) → numeric branch inert, тільки категорична перевірка
2. within ε → silent pass (no fraud flag)
3. drift > ε → fraud flag + structured log entry
4. default ε constant — pin `DEFAULT_DCI_EPSILON = 0.001`
5. malformed `GAIA_DCI_NUMERIC_EPSILON="abc"` → graceful fallback + warn
6. `device_z` missing → numeric branch skipped (Gate D guard)

**Cross-ref:** [00_07 FW.31](00_07_Action_Plan_Tracker), [03_05 §3.2 BLOCKER-2 FW.2 CCM wire format](03_05_Hardware_Symmetric_Crypto_and_Security), [04_02 TelemetryUnpackerService](04_02_Business_Logic_and_Services), [06_03 Prometheus](06_03_Prometheus_Observability) (після Gate D — додати `silkennet_dci_numeric_rejections_total`).

---

### 7.2 Чисельна стабільність методу Ейлера (відомий компроміс)


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

