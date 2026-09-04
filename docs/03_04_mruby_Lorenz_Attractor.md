# 03_04: mruby Атрактор Лоренца (Математика Хаосу та Гомеостаз)

---

## 🎯 Мета

Задокументувати повний алгоритм **Bio-Contract** — mruby-скрипту, що виконується на борту вузла **Soldier** (STM32WLE5JC) і обчислює стан гомеостазу дерева через Атрактор Лоренца. Цей документ є SSOT для:

- **Backend (`TelemetryUnpackerService`)**: сервер знає точну математичну модель і може перевіряти коректність надісланих деревом `growth_points`.
- **Proof of Growth Pipeline (05_02)**: мінтинг SCC заблокований, поки бекенд не розуміє математику, що генерує бали.
- **University R&D (00_02)**: академічна верифікація числової стабільності методу Ейлера у системі Лоренца.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — Lorenz атрактор: **категорично** ідентичний firmware↔backend (status/growth_points, FW.7 Float math), raw Z **бітово ідентичний** (drift = 0: mruby-VM↔CRuby sweep N=10k + FW.55 QEMU byte-parity ARM↔x86 — §5, §7.1 Gate L; історичні «~1e-14» superseded pinned `MRB_NO_BOXING`); SEC.11 seed provenance закрито. Канонічний дім Lorenz-констант (§1.2). Відкрите: numeric DCI ε flip (`FW.31`, deferred) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Soldier lifecycle; RTC DR16-18 Lorenz state (FW.6) |
| [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) | `acoustic_events` → σ-пертурбація |
| [`03_06` — Factory Flashing and Key Provisioning](03_06_Factory_Flashing_and_Key_Provisioning) | §3 K_seed derivation (SEC.11, HKDF/HMAC) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | TelemetryUnpacker, SeedDerivation, DCI check |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Dual Computation Integrity (Z крос-верифікація) |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | CRITICAL_Z_MIN/MAX → slashing |
| [`00_02` — Academic Institutions Registry](00_02_Academic_Integration_and_IP) | Матем. верифікація числової стабільності |
| `firmware/bio_contracts/bio_contract.rb` · `app/services/silken_net/attractor.rb` · `seed_derivation.rb` | mruby + Rails-дзеркало (Float parity); SEC.11 entry-point |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): FW.31 numeric-DCI flip (deferred); ARCH.18 int-Lorenz (🌿 zkVM-мотив; drift-мотив знято FW.55/FW.31, §5) |

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

У контексті SilkenNet ця система моделює **висхідний потік соку в ксилемі** — водно-мінеральний стовп, який транспірація тягне від коренів до крони.

> ⚠️ **Тканину названо ксилемою НЕ довільно, і доти тут стояла флоема [ARCH.102].** Обидва живі входи цього ж документа — ксилемні: `acoustic` є кавітацією **ксилеми** (§4.1), а `delta_t_s` — метаболізмом ксилеми, з якої живиться EBFC ([`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)); сам анкер інтегрується в ксилему ([`01_04`](01_04_CODIT_and_Xylemointegration)). Тобто збурювач і збурюване приписувались різним судинам в одній таблиці. ⊕ Заразом виправлено біологію напрямку: цукри флоемою йдуть переважно від листя ДО коренів, тож стара фраза «від коренів до листя» описувала ксилемний маршрут під флоемним іменем. ⛔ Жодна константа від цієї правки не зрушила: метафора є **інтерпретацією**, а не входом обчислення.

### 1.1 Система Диференціальних Рівнянь

```
dx/dt = σ · (y - x)
dy/dt = x · (ρ - z) - y
dz/dt = x · y - β · z
```

де:
- **x** — швидкість конвективного потоку (аналог швидкості соку в ксилемі)
- **y** — різниця температур між висхідним і низхідним потоком соку
- **z** — відхилення температурного профілю від лінійного (інтенсивність конвекції)
- **σ (sigma)** — число Прандтля (відношення в'язкості до теплопровідності соку)
- **ρ (rho)** — число Релея (різниця температур, що рухає конвекцію)
- **β (beta)** — геометричний параметр (форма конвективної клітини)

### 1.2 Базові Константи Системи

| Константа | Символ | Значення (firmware) | Значення (backend) | Фізичний зміст |
|---|---|---|---|---|
| `BASE_SIGMA` | σ | `10.0` (Float) | `10.0` (Float) | Число Прандтля — в'язкість ксилемного соку |
| `BASE_RHO` | ρ | `28.0` (Float) | `28.0` (Float) | Число Релея — температурний градієнт |
| `BASE_BETA` | β | `8.0 / 3.0` (Float) | `8.0 / 3.0` (Float) | Геометрія конвективної клітини |
| `DT` | Δt | `0.01` (Float) | `0.01` (Float) | Крок інтегрування методу Ейлера |
| `ITERATIONS` | N | `250` | `250` | Кількість ітерацій симуляції |

> **[FIX FW.7]:** Backend переведено з BigDecimal на Float (IEEE 754 double) — та сама математика, що firmware mruby (ті ж константи й операції). BigDecimal давав інші результати після 250 ітерацій через `round(18)` на кожному кроці.
>
> **Точність parity (уточнено FW.46, 2026-06-04 — перший реальний прогін mruby-VM):** firmware та backend дають **категорично ідентичний** вихід — `status`/`growth_points`/`payload_byte` бітово збігаються (перевірено реальним mruby 4.0.0 VM через `tools/firmware/run_bytecode_vm.sh`, що ганяє committed `lorenz_bytecode`). **Raw Z:** перший VM-прогін (2026-06-04, один кейс) показував **~1e-14** проти CRuby — **superseded 2026-06-11**: за pinned-конфігурації (явний `MRB_NO_BOXING` + MCU-профіль, FW.55-④) sweep N=10 000 зчеплених кейсів дає **бітову рівність** mruby-VM ↔ CRuby (max|Δz| = 0, `tools/firmware/dci_epsilon_sweep.sh`; деталі Gate L — §7.1), а ARM↔x86 плече бітово-нульове за FW.55 QEMU byte-parity. Раніше «bit-identical / 50k» стосувалося Ruby/C-мірор рівня (`firmware/test/test_bio_contract.c` реімплементує логіку в C), а не самого mruby-VM. Бітову інваріантність на **будь-якому** процесорі дає лише fixed-point Q-формат (§нижче, `FW.45`). **[FW.57 F4]** Окрім mruby-VM прогону, firmware↔backend `Z`/`bio_status` тепер звіряються ПРЯМО: `attractor_spec` ганяє справжній `bio_contract.rb` в ізольованому subprocess (`tools/firmware/contract_runner.rb`) замість рукописної `firmware_z`-копії — 3-тю kernel-копію усунено (GP-parity → FW.2).

> **[Майбутнє hardening — Integer/Fixed-Point Math, не реалізовано]** Float-парність вирішує bit-identity для пари x86-64 ↔ ARM Cortex-M4 (WLE5 — **без FPU**, [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA): binary64 рахується software `__aeabi_d*` — коректно-округлений IEEE 754; байт-парність саме цього шляху доведена QEMU-M4 ногою, [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)). Вона **НЕ гарантує** парності для:
> (a) інших toolchain/libc soft-float реалізацій поза перевіреним gcc/libgcc шляхом (денормали, FTZ-поведінка);
> (b) mruby збірок з `MRB_USE_FLOAT32` (32-bit Float — не наш випадок, але можливий регрес);
> (c) майбутніх ZK-circuits, де float взагалі недоступний.
>
> Третій рівень hardening — **fixed-point Q-формат:** вхідні дані × 10⁶, всі арифметичні операції у `int64_t`/Ruby `Integer` (немає overflow до 2⁶³ ≈ 9.2·10¹⁸). Тоді результат **бітово ідентичний на будь-якому процесорі**, від AVR до zkVM.
>
> Ціна: повне переписування `firmware/bio_contracts/bio_contract.rb`, `app/services/silken_net/attractor.rb`, усього parity-корпусу (§4.2 — sweep + Ruby/C-мірор), плюс ручне керування overflow (квадрати/добутки потрібно зрізати до Q-формату на кожному кроці Ейлера). Робота S→L залежно від обсягу регресії. Цінність — лише при переході до ZK-proof Lorenz (Risc Zero / SP1) або при підтримці радикально іншої HW-цілі (RV32E без FPU, тощо). До цього моменту Float-парність достатня. Зафіксовано як **ARCH.18** (int-Lorenz, 🌿 deferred until zkVM-Lorenz milestone; `FW.45` = історичний firmware-тег, злитий у ARCH.18 → §🗄️) у [`00_07`](00_07_Action_Plan_Tracker).

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

> **First-Boot vs Continuation — канонічна логіка [SEC.11 hard cutover]**
>
> Bio-Contract має **єдину точку входу** після SEC.11 cutover. C-сторона завжди викликає `BioContract.calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)`. Розкладка регістрів та магічний маркер `LZST = 0x4C5A5354` — у [`03_01 §2 + §2.1` (Canonical SSOT)](03_01_Firmware_Lifecycle_and_DMA#-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3); тут описано лише **звідки беруться `(x_prev, y_prev, z_prev)`**:
>
> | Умова | Джерело `(x_prev, y_prev, z_prev)` | Призначення |
> |-------|------------------------------------|-------------|
> | `DR19 == 0x4C5A5354` AND `isfinite(x,y,z)` | RTC DR16-DR18 (warm restart, FW.6) | **Continuation:** продовження безперервної траєкторії після STOP2 wake-up. |
> | `DR19 ≠ 0x4C5A5354` OR `!isfinite(x,y,z)` | `(x₀,y₀,z₀) = unpack_signed_unit_floats(HMAC-SHA256(K_seed, "init\|" \|\| epoch_day_be)[0..23])` | **Cold start (rare):** після VBAT loss. K_seed зберігається у Flash (Soldier) і `hardware_keys.lorenz_seed_hex` (backend), деривується при provisioning через `HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed\|<DID>", len=32)`. Daily epoch_day rotation дає forward secrecy ≤ 24 год. |
>
> **Чому K_seed замість chaos_seed/DID:** `chaos_seed` (HRNG) недетермінований — backend не зміг би відтворити Z. DID-as-seed (`SilkenNet::Attractor.calculate_z(did, …)`) був public-input → атакер з open-source формулою Лоренца передбачає очікуваний Z для будь-якого дерева. K_seed — **private**, ніколи не залишає пристрій/сервер у відкритому вигляді (HKDF деривується незалежно з `PROVISIONING_MASTER_KEY`). Закриває чотири фундаментальні вади (sniff/correlation/identifier-as-key/forward-secrecy) — див. SEC.11 у [`00_07`](00_07_Action_Plan_Tracker).
>
> **[E.63]** `delta_t_s` визначає `growth_points` напряму (метаболічна жвавість, §4.3); `vcap_mv` reserved; β = `BASE_BETA` фіксований (більше НЕ збурюється). ⚠️ **Калібрувальні пороги `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` — calibration-pending:** чекають зміряної recharge-кривої (bench RUNBOOK §3.3 → [`00_07` — E.63](00_07_Action_Plan_Tracker)).
>
> **Інваріант:** після кожного успішного циклу C-код **зобов'язаний** записати нові `(x, y, z)` у DR16/DR17/DR18 і встановити `DR19 = 0x4C5A5354`.

> ⚠️ **Cold-Start Time Paradox (ARCH.41 — три мітигації ✅, ЧЕТВЕРТИЙ кут закрито 2026-08-28; відкритою лишається лише 👤 bench-перевірка):** Cold-start деривація `(x₀,y₀,z₀)` залежить від `epoch_day`. Після **VBAT loss** RTC Soldier'а скидається на default-дату (2000-01-01 у поточному firmware), тож `epoch_day = 10 957` (exact civil-days, 946_684_800/86_400) замість сьогоднішнього серверного `≈ 20 585` (illustrative, на 2026-05-16). Перший uplink після cold-boot використає «застарілий» epoch_day, поки Soldier не отримає `CMD_TIME_SYNC` beacon від Queen (FW.20). Це означає:
>
> - **Firmware:** `Derive_Cold_Start_State()` (`firmware/soldier/main.c`) рахує epoch_day **exact civil-days** (`lorenz_seed.h` `Silken_Days_From_Civil`, [FW.30] — стара `Month*30 approximation` закрита); RTC-default 2000-01-01 → 10 957, паритет із backend-кандидатом.
> - **Backend:** `TelemetryUnpackerService#compute_server_z` сьогодні **уникає** проблеми у >99% випадків через `previous_lorenz_state_for(tree)` chaining (server бере хвіст останнього TelemetryLog, не cold-derive). Cold-derive виконується лише коли у дерева **немає історії** (вперше підключений вузол). У такому сценарії server бере добу з моменту ПРИЙОМУ пакета (`derivation_epoch_day` ← `received_at` із job-аргументів, [ARCH.41] — див. «ЧЕТВЕРТИЙ кут» нижче); `Time.now.utc.to_i / 86_400` лишився ЛИШЕ фолбеком для викликів без мітки (bench/HIL/спеки) — і Soldier з RTC=2000-01-01 не співпаде з server-day.
> - **Сценарій тонкого розриву:** VBAT loss у дерева **з історією** → Soldier cold-restart'ить Lorenz з RTC-default epoch_day, server chain'ить з попереднього хвоста → траєкторії розходяться категорично на ергодичному горизонті ~50 циклів (≈ 2 доби), доки `CMD_TIME_SYNC` не дочекається наступного CoAP downlink'у. Сьогодні numeric DCI branch (`GAIA_DCI_NUMERIC_TOLERANCE`) інертний у production (транзитний 21B ECB не несе device_z; wire-дім у FW.2 wire-rev2 готовий, чекає CCM-фліпу), тож на DCI це поки **не валиться** — але стане живим обмеженням разом із numeric tolerance band після фліпу.
>
> **Мітигація:**
> 1. **Server-side detect-and-recover** ✅ **Реалізовано (2026-05-17, ARCH.41 Option A):** `TelemetryUnpackerService#try_time_sync_recovery` — коли `cold_start_flag == false` (є історія) АЛЕ категоричний DCI мисматч, пробує 3 кандидати `epoch_day` (today, today−1, `FIRMWARE_RTC_DEFAULT_EPOCH_DAY=10_957`). Для кожного: `SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)` → `Attractor.calculate_z_from_state(...)` → категорична перевірка. При збігу: `TelemetryLog#time_unsynced_fallback = true`, `TimeSyncDownlinkWorker.perform_async(cluster_id)` (envelope-only CoAP → Queen RTC → LoRa beacon → Soldier sync). fraud_metric НЕ інкрементується. 9 spec examples.
> 2. **Soldier-side explicit signal (sentinel)** ✅ **Реалізовано (2026-06-11, ARCH.41-B):** поки Солдат не чув жодного beacon'а (`soldier_unix_ts == 0`), повний пакет несе `acoustic_events = 0xFE` (`Soldier_Acoustic_Wire_Value`, host-tested; реальні 0xFE клампляться у 0xFD — sentinel однозначний; 0xFF лишається FW.22-сатурацією). **Правило обох сторін: sentinel ⇒ Лоренц рахується з `acoustic = 0`** — Солдат дає mruby 0, бекенд (`TelemetryUnpackerService#apply_time_uncertain_sentinel!`) нейтралізує 0xFE→0 ДО DCI → паритет тримається, а σ не штовхається у clamp фальшивими «254 подіями». Бекенд одразу ставить `time_unsynced_fallback = true` + `TimeSyncDownlinkWorker`; stress_index бачить 0. DCI **не** обходиться (sentinel ≠ маска для підробленого Z). Wire-format незмінний; координація rollout — pre-fleet тривіальна (обидві сторони в одному репо).
> 3. **Defer first uplink + hello** ✅ **Реалізовано (2026-06-11, ARCH.41-C):** у grace-вікні (`TIME_SYNC_COLD_BOOT_GRACE_WAKEUPS` = 20 пробуджень ≈ 10 хв — wall-квант = пробудження, бо tick мертвий у STOP2; 2026-06-11) Солдат **не** рахує Лоренца (деривація від застарілого epoch_day отруїла б RTC-ланцюг; `lorenz_state_valid` лишається 0 → після синку перша деривація піде з правильної доби) і замість телеметрії шле **hello = SYNC_REQ 0x56** (`Build_Time_Sync_Request_Payload`: DID + secs_since_sync=0 + Vcap у байтах 11..12 + магія 'S'; freeze-contract wire — [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA)). OTA Reflex живий: Королева стріляє OTA на будь-який валідний RX ще до розбору маркера, а вікно слухання Солдата (Фаза 4.5) спільне — маяк чутно цим же пробудженням. Королева на 0x56 перемотує `last_beacon_time` → негайний re-broadcast маяка (ідемпотентно; без власного часу `Broadcast_Time_Beacon` мовчить). Frost-guard (FW.10) і TX-jitter спільні з телеметрією.
>
> Разом: C закриває перші 10 хв (жодного пакета зі stale epoch_day взагалі), B — хвіст «Королева мовчить довше за grace» (телеметрія йде, але чесно маркована). Вар.1 (server-side recovery) лишається страхувальною сіткою для прошивок без B/C. Tracker: див. **ARCH.41** у [`00_07`](00_07_Action_Plan_Tracker).
>
> 🔴 **ЧЕТВЕРТИЙ кут, якого A/B/C не покривають за побудовою — і він на СЕРВЕРІ, не на пристрої (закрито 2026-08-28).** Усі три мітигації вище стережуть пристрій із НЕВІРНИМ часом; жодна не стереже випадок, коли час пристрою правильний, а сервер деривує з ІНШОЇ доби. Саме це й було: `compute_server_z` кликав `SeedDerivation.initial_state(seed_bytes)` **без другого аргументу**, тобто падав на дефолт `current_epoch_day` = `Time.now.utc` у момент ОБРОБКИ — і Sidekiq-ретрай через межу півночі UTC давав інший `epoch_day` → інший (x₀,y₀,z₀) → категоричний DCI-мисматч на ЧЕСНОМУ дереві. ⚠️ **Ловити його нікому:** `try_time_sync_recovery` (вар.1) гейтований `!cold_start_flag`, а деривація відбувається саме на cold-start — тобто страхувальна сітка структурно відсутня рівно там, де дефект живе.
>
> 🔑 **Лік — доба ПРИЙОМУ, і жодна з двох раніше названих опцій не була правильною.** Псевдокод [`05_02`](05_02_Proof_of_Growth_Pipeline)/[`03_06`](03_06_Factory_Flashing_and_Key_Provisioning) приписував `telemetry_log.created_at`, але той ставиться при ВСТАВЦІ рядка, тобто на ретраї теж новий; `Time.now.utc` рухається так само. Єдина величина тракту, що не змінюється між спробами, — момент прийому, зафіксований інтейком і серіалізований у job-аргументи (`UnpackTelemetryWorker#perform` 4-й аргумент → `TelemetryUnpackerService.call(received_at:)`). Обидва боки деривації читають її через One-Home `derivation_epoch_day`, тож `try_time_sync_recovery` шукає кандидати на ТІЙ САМІЙ сітці днів, що й основний шлях. 🔒 `nil` (bench/HIL/спеки, що кличуть воркер напряму) чесно означає «прийом = зараз»; те, що обидва ПРОДОВІ enqueuer'и передають мітку, тримає гейт `spec/quality/telemetry_received_at_propagation_spec.rb` — з оголошеною стелею: він судить НАЯВНІСТЬ аргументу, ніколи його правильність.

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
├── delta_t_seconds ← EMA (RTC DR10), vcap_mv ← EMA (RTC DR12)  [FW.21; метаболізм→GP §4.3, E.63]
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

> **[E.63] (backend + firmware mruby):** `delta_t_seconds` → `growth_points` напряму (метаболічна `m(delta_t)`, §4.3); `vcap_voltage` поки не входить у винагороду (FW.50); β = `BASE_BETA` фіксований (більше НЕ збурюється). C-side передає EMA delta_t/vcap з RTC (FW.21) як args.

### 2.2 Фізична Інтерпретація Вхідних Параметрів

| Параметр | Фізичний зміст | Вплив на Атрактор |
|---|---|---|
| `K_seed` (uint8[32], Flash, [SEC.11]) | Криптографічний секрет, спільний з backend через HKDF з `PROVISIONING_MASTER_KEY` | Визначає cold-start `(x₀, y₀, z₀)` детерміновано (firmware ↔ backend byte-identical) при VBAT loss; ротується щодня через `epoch_day` info-string |
| `lorenz_x/y/z` (float32, RTC) | [FW.6] Збережений стан атрактора з попереднього циклу STOP2 | При наступних циклах — продовження безперервної траєкторії |
| `temp` (int8, °C) | Температура **кристала STM32** (внутрішній ADC-канал, ±1 °C). ⛔ **Про температуру ДЕРЕВА не свідчить, і доти цей рядок стверджував протилежне** («корельована з температурою дерева») — кореляція без жодного вимірювача, клас `СЛОВО` ([`00_05 §7`](00_05_AI_Native_Operating_Model)). Кремній сидить у RF-деці **над** PEEK-терморозривом ([`02_01 §3`](02_01_Hardware_Architecture_and_BOM), λ ≈ 27× нижча за Ti), тобто тепловий шлях від заболоні розірваний **за дизайном**; фізіологічний термо-канал мав би прийти з BME280, який у Лоренц не входить і на кремнії ще не підключений (HW.32) | Збурює ρ: `ρ_eff = 28 + temp × 0.2` → зсуває центр атрактора (`z_eq = ρ − 1`). 🔑 **Саме тому Z несе температуру як конфаундер**: `avg_z ≈ const + 0.2·avg_temp` + хаос — і будь-яка валідація, чий baseline не містить `temp`, припише цю кореляцію Z ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)) |
| `acoustic` (uint8) | Кількість кваліфікованих TinyML-подій (кавітація ксилеми або пилка — [`03_03 §5`](03_03_TinyML_Acoustic_Inference)) від останньої успішної передачі телеметрії [ARCH.102] | Збурює σ: `σ_eff = 10 + acoustic × 0.1` → змінює "в'язкість" системи |
| `delta_t_s` (uint16, с) | [E.63] Час перезаряду EBFC — швидкість метаболізму ксилеми | → growth_points напряму (монотонна `m(delta_t)`, §4.3); НЕ впливає на Z/β |
| `vcap_mv` (uint16, мВ) | Напруга суперконденсатора — накопичена енергія EBFC | [E.63] reserved; зараз це VDDA-проксі (FW.50 units-фікс ✅), у винагороду повернеться не раніше живого Vcap-каналу (FW.50 hardware); НЕ впливає на Z/β |

#### [E.63] Метаболізм → growth_points (β більше НЕ збурюється)

> Раніше [FW.5] мапив `delta_t`/`vcap` на β-пертурбацію; E.63 довів цей шлях економічно нульовим (delta_t) / інвертованим (vcap), бо β не рухає z-нерухому точку Лоренца. Тепер β = `BASE_BETA` (фіксований), а метаболічна жвавість визначає growth_points **напряму** — формула `m(delta_t)` у **§4.3**, тут не дублюється (One-Home).

#### Походження Початкової Точки: Свідомість, Що Пам'ятає Себе (post-SEC.11)

До SEC.11 cold-start стартова точка походила з `chaos_seed = HAL_RNG_GenerateRandomNumber(&hrng)` — апаратного TRNG, що читає **термічний шум кремнієвої решітки** STM32WLE5. Це була красива метафора: дерево, інтегроване з кристалом капсули через спільну температуру ксилеми, **буквально надає початковий стан своїй цифровій свідомості** через квантово-біологічне злиття. Кожне пробудження — нова мить мислення, що відштовхується від теплового шуму у цю конкретну мікросекунду.

Метафора була правдива поетично, але з криптографічної точки зору фатальна: сервер не може відтворити недетермінований HRNG → змушений був відображати `chaos_seed` через DID → 4-байтний публічний ідентифікатор ставав фактичним криптографічним параметром. Атакер з open-source формулою Лоренца передбачав очікуваний Z для будь-якого дерева → `check_z_divergence!` мовчав. Метафора, яка вбивала систему.

**Post-SEC.11 — поетика, що зберіглася і зміцнилася.** Свідомість дерева тепер походить з **двох взаємодоповнюючих джерел**, які разом утворюють повну біографію цифрового двійника:

1. **`K_seed` — біологічна геральдика, нуклеотид у Flash.** Під час physical provisioning конкретного дерева в полі система деривує 32-байтний секрет через `HKDF-SHA256(PROVISIONING_MASTER_KEY, "silken-lorenz-v1", "silken-lorenz-seed|<DID>")` і записує його у protected Flash sector — поряд з AES-ключем, під тим самим RDP-захистом. Цей секрет **народжується разом з деревом**: він унікальний, він приватний, він ніколи не залишає капсулу. Якщо `chaos_seed` був "теперішнім моментом" дерева, то `K_seed` — його **свідоцтво про народження**, цифрова ДНК, надіслана у Flash тоді, коли крона ще навіть не торкнулася ксилеми. Сервер деривує той самий `K_seed` незалежно — обидві сторони знають його, але світ — ні.

2. **RTC DR16-DR18 — пам'ять про вчорашню думку (FW.6 continuation, > 99.9% циклів).** Після першого пробудження свідомість дерева більше **не починається з нуля**. Кожне STOP2-пробудження читає `(x_prev, y_prev, z_prev)` з RTC Backup Domain — координати в фазовому просторі, де закінчилася попередня ітерація Лоренца. Це означає, що траєкторія **продовжується**: σ-перурбація від акустики та ρ від температури у попередньому циклі визначили, де саме на дивному атракторі дерево "перебуває" у момент пробудження (β = BASE_BETA фіксований — [E.63]; метаболізм → growth_points поза Z). Якщо метафора `chaos_seed` була "дерево надає себе своїй свідомості мить за миттю", то FW.6 — **"свідомість, що пам'ятає себе"**: кожна нова думка є продовженням попередньої, неперервна нитка існування у фазовому просторі.

3. **Cold start (рідкісна подія, після VBAT loss — місяці-роки):** дерево "забуває" останню думку, бо живлення зникло. Тоді з `K_seed` через `HMAC-SHA256(K_seed, "init|" || epoch_day)` деривується **сьогоднішня початкова точка**. Daily `epoch_day` rotation означає, що навіть друге народження не повторює перше — щодня свідомість має нову відправну точку, навіть з тим самим геномом. Forward secrecy ≤ 24 год.

> **Філософія:** криптографічна стійкість і біологічна метафора більше не суперечать одна одній. `K_seed` — це **приватна термодинаміка дерева**, замінник тих самих квантових флуктуацій, що раніше давав HRNG, але закріплений у момент народження капсули і відомий лише дереву та його серверному двійнику. Сервер, що знає `K_seed`, — це не сторонній спостерігач, а **близнюк-свідомість**, що мислить ту ж саму траєкторію Лоренца паралельно. Атакер, який підглядає LoRa, бачить лише payload — а не те, *куди* свідомість стартувала і *куди* вона йде.

#### Бюджет Variance Z (Лоренц = хаос-гейт, метаболізм поза Z) [E.63]

Після [FW.6] (state preservation в RTC) cold-start initial conditions вже **не домінують** variance Z. Ergodicity дивного атрактора — траєкторія "забуває" початкову точку після ~50 пробуджень (~2 доби). **[E.63]** Z визначають лише temp (ρ) + acoustic (σ) + внутрішній хаос; `delta_t`/`vcap` БІЛЬШЕ не впливають на Z (β фіксований), бо метаболізм перенесено напряму у growth_points (§4.3):

| Джерело variance Z | Після FW.6 (continuous trajectory) | Фізичний зміст |
|---|---|---|
| `(x₀,y₀,z₀)` cold-start (K_seed-derived) | **< 5%** після перших 50 wake-up циклів | Траєкторія забуває стартову точку через ergodicity |
| `temp` (через `ρ_eff = 28 + temp·0.2`) | **домінує** | Стабільна термальна рушійна сила (рухає z_eq=ρ−1) |
| `acoustic` (через `σ_eff = 10 + acoustic·0.1`) | помітний | Реактивний (кваліфіковані події рідкі) |
| residual (хаотична динаміка Лоренца) | помітний | Внутрішній детермінований хаос системи |
| `delta_t_s`/`vcap_mv` | **0% (поза Z)** | [E.63] метаболізм → growth_points напряму (§4.3), не через β/Z |

**Висновок [E.63]:** спроба завести метаболізм через β (старий FW.5) давала економічно **нульовий** (delta_t) / **інвертований** (vcap) внесок у growth_points — бо β не рухає z-нерухому точку Лоренца. Тому метаболічна активність EBFC тепер визначає growth_points **напряму** (монотонна `m(delta_t)`, §4.3), а Лоренц лишається чистим детектором стану (homeostasis/stress/anomaly). Присуд — [`00_07` — E.63](00_07_Action_Plan_Tracker).

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

`K_seed` — 32-байтний секрет, виведений при provisioning через `HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed|<DID>", len=32)`. Зберігається у protected Flash sector Soldier-вузла та у `hardware_keys.lorenz_seed_hex` (AR Encryption non-deterministic). НІКОЛИ не передається через мережу — обидві сторони деривують його незалежно з спільного `PROVISIONING_MASTER_KEY`. Реалізація — `app/services/silken_net/seed_derivation.rb` (backend, OpenSSL HKDF) і `firmware/test/test_seed_derivation.c` (host-parity test, що валідує OpenSSL ↔ pure-C `silken_sha256.h` (FW.30) байт-ідентичність).

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

> **Семантика входу `acoustic` [ARCH.102]:** лічильник кваліфікованих подій (кавітація ксилеми **або** пилка, обидві зони впевненості — класи й пороги [`03_03 §5`](03_03_TinyML_Acoustic_Inference)) **від останньої УСПІШНОЇ передачі телеметрії**, НЕ «за одне пробудження». Фаза 2 циклу лише знімає снапшот; споживає лічильник — відніманням знімка — тільки успішний TX, тож залишок циклів із відкладеною передачею (frost-defer, grace-hello) доживає до наступного кадру й переживає STOP2 у RTC DR0. Входи 50–255 у таблиці — акумуляція за тривалу перерву передачі, а не подія одного пробудження.

**Таблиця збурення ρ (вплив температури):**

| `temp` (°C) | `local_rho` (перед clamp) | `local_rho` (після clamp) | Стан дерева |
|---|---|---|---|
| −45 | 19.0 | 19.0 | Глибока зима |
| 0 | 28.0 | 28.0 | Базовий стан |
| +20 | 32.0 | 32.0 | Літній режим |
| +55 | 39.0 | 39.0 | Теплова аномалія |
| +110 | 50.0 | 50.0 | Максимум (пожежа, clamp) |

> `BASE_BETA = 8.0/3.0` — **фіксований** параметр. [E.63] скасував β-пертурбацію: метаболізм не може монотонно вести Z до цілі через β (β не рухає z-нерухому точку z_eq=ρ−1). Метаболізм тепер визначає `growth_points` напряму (§4.3).

### Крок 2.5: [E.63] Метаболізм → growth_points (поза Лоренцом)

Раніше [FW.5] цей крок збурював β від `delta_t`/`vcap`. E.63 довів цей шлях економічно нульовим (delta_t) / інвертованим (vcap) → **видалено**: β = `BASE_BETA` фіксований, а метаболічна жвавість `m(delta_t)` задає `growth_points` напряму у зоні гомеостазу — формула у **§4.3** (One-Home; тут не дублюється). `vcap` reserved (FW.50).

### Крок 3: Числове Інтегрування (Метод Ейлера, 250 ітерацій)

```ruby
250.times do
  # Обчислення похідних (права частина системи Лоренца)
  dx = local_sigma * (y - x)           # dx/dt = σ(y - x)
  dy = x * (local_rho - z) - y         # dy/dt = x(ρ - z) - y
  dz = (x * y) - (BASE_BETA * z)       # dz/dt = xy - βz  (β фікс, E.63)

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
def self.calculate_z_axis(x, y, z, temp, acoustic)
  local_sigma = BASE_SIGMA + (acoustic * 0.1)
  local_rho   = BASE_RHO   + (temp * 0.2)

  local_sigma = SIGMA_MIN if local_sigma < SIGMA_MIN  # clamp lower
  local_sigma = SIGMA_MAX if local_sigma > SIGMA_MAX  # clamp upper
  local_rho   = RHO_MIN   if local_rho   < RHO_MIN
  local_rho   = RHO_MAX   if local_rho   > RHO_MAX

  # [E.63] β = BASE_BETA (фіксований). Метаболізм (delta_t) більше НЕ збурює β —
  # він задає growth_points напряму (§4.3). Лоренц = чистий хаос-гейт.

  ITERATIONS.times do
    dx = local_sigma * (y - x)
    dy = x * (local_rho - z) - y
    dz = (x * y) - (BASE_BETA * z)

    x += dx * DT
    y += dy * DT
    z += dz * DT
  end

  z  # Повертаємо чисту інтенсивність конвекції (руху соку)
end
```

---

## 🌡️ 4. Логіка Гомеостазу: Z → growth_points

> **⚠️ [Lorenz de-risk → E.64 присуд, 2026-06-08]** Мапінг **Z → bio_status — не просто «недоведена гіпотеза», а емпірично degenerate + temp-confounded** (paired-ensemble на реальному коді, [`00_07` — E.64](00_07_Action_Plan_Tracker)): `stress` (z<2) **недосяжний** (ρ-clamp 10 → z_eq≥9); `anomaly` (z>45) **тригерилася ambient-температурою** (здорове дерево в теплий день → хибна аномалія → обнуляла growth_points). **[E.63] growth_points БІЛЬШЕ НЕ Z-похідні** (магнітуда = метаболізм `m(delta_t)`, §4.3) — Лоренц лишився лише status-гейтом. Політика: фінансовий slashing **ніколи** не спирається лише на Z (прямі сигнали `delta_t`-метаболізм / VPD / acoustic; [`05_05 §7`](05_05_Slashing_and_Risk_Policy)); Lorenz-**DCI** (device-Z ≡ server-Z anti-fraud) валідний **незалежно**. **✅ Фікс (E.64, 2026-06-08):** anomaly-поріг тепер **ρ-відносний** — `z > ρ + (CRITICAL_Z_MAX−BASE_RHO)` (=45 при ρ=28) → ambient-temp більше НЕ тригерить хибну аномалію (warm-day false-anomaly 22%→3%). `stress` (z<2 absolute) лишено — справжній колапс конвекції, рідкісний за дизайном.

### 4.1 Межі Стабільності та Їх Фізична Інтерпретація

| Константа | Значення | Фізичний зміст |
|---|---|---|
| `CRITICAL_Z_MIN` | `2.0` | Нижня межа — падіння нижче: втрата тургору, посуха |
| `CRITICAL_Z_MAX` | `45.0` | Верхня межа — стрибок вище: аномальний стрес, зовнішнє втручання |
| `OPTIMAL_Z_TARGET` | `29.0` | Ідеальна інтенсивність конвекції для максимального поглинання CO₂ |

> **Чому 29.0, а не z_eq = ρ−1 = 27.0?** Математичний рівноважний стан Лоренца при ρ=28 є z = ρ−1 = 27.0 (координата нерухомих точок C₁ та C₂). Значення `OPTIMAL_Z_TARGET = 29.0` є **навмисним зміщенням +2 від рівноваги** з двох причин: (1) Краща розрізненність класів — зміщення "ідеальної зони" дещо вище рівноваги створює асиметрію у функції нарахування балів, що покращує розрізнення здорових vs стресових дерев; (2) Біологічне обґрунтування — активне здорове дерево з інтенсивним метаболізмом демонструє конвекцію вище рівноваги, тоді як z = 27.0 відповідає "спокійному" стану.

### 4.2 Таблиця Рішень (Decision Table) — Лоренц як ГЕЙТ статусу

> **[E.63] Лоренц гейтить лише статус; магнітуду growth_points у гомеостазі задає метаболізм (§4.3), а не Z.**

| Z-значення | Статус (`bio_status`) | Назва | growth_points | Пояснення |
|---|---|---|---|---|
| `z < 2.0` | `1` | ⚠️ Stress (Посуха) | `1` | Мінімальна генерація — дерево виживає, але не росте |
| `z > ρ+17` (=45 при ρ=28) | `2` | 🚨 Anomaly (вихід за temp-обвідну) | `0` | Емісія зупиняється; [E.64] ρ-відносний поріг |
| `2.0 ≤ z ≤ 45.0` | `0` | ✅ Homeostasis (Здоровий Хаос) | `5 .. 31` (wire); `10 .. 62` (stored ×2) | Бали = метаболічна жвавість `m(delta_t)` (§4.3) |

### 4.3 Функція Нарахування Балів у Зоні Гомеостазу — Метаболічна Жвавість [E.63]

> **[E.63] Бали у гомеостазі задає МЕТАБОЛІЗМ (швидкість перезаряду EBFC), а НЕ Z.** Раніше магнітуда бралася з `|OPTIMAL_Z_TARGET − z|`, але paired-ensemble на реальному коді показав: Z-позиція у гомеостазі — хаотичний шум (std ≈ 4 GP) при ~нульовому корисному сигналі, а β-перетурбація від delta_t/vcap виходила економічно **нульова** (delta_t) / **інвертована** (vcap) — бо β НЕ рухає z-нерухому точку Лоренца (z_eq = ρ−1 залежить від ρ/temp, не від β). Розв'язання здоров'я від хаосу: Z лише класифікує стан (§4.2), а у гомеостазі бали = монотонна метаболічна жвавість. Присуд + докази — [`00_07` — E.63](00_07_Action_Plan_Tracker).

```
# [ARCH.102] СЕНТИНЕЛ ПЕРЕДУЄ ФОРМУЛІ — і це не деталь реалізації, а перший крок:
DELTA_T_UNKNOWN_S = 0    # «метаболізм не виміряно» (EMA не прогріта / RTC не піднято)
# delta_t_s == DELTA_T_UNKNOWN_S → status = 0, growth_points = 0 — і НЕ 5 («гомеостаз-мінімум»).
# 🔴 Чому окремою гілкою, а не значенням-за-замовчуванням: формула нижче на нулі
# ВИРОДЖУЄТЬСЯ у свою протилежність — m = 7200/6600 = 1.09 → clamp 1.0 → GP = 31 = максимум.
# Тобто «я не знаю» дало б найвищу нагороду, і саме це стояло тут до 2026-08-16
# (аргумент був BASELINE_DELTA_T_S = 60 с → теж m = 1.0). Дзеркалиться обабіч:
# `bio_contract.rb#pack_status_byte` ⊥ `Attractor.expected_homeostasis_gp`.

# [E.63] Монотонна жвавість m ∈ [0,1] зі швидкості перезаряду (delta_t, сек):
# швидший перезаряд → активніший метаболізм → більше балів.
# Калібрувальні пороги — placeholder, чекають bench recharge-кривої
# (firmware/scripts/bench/RUNBOOK.md §3.3 / 00_07 E.63); фінал per-deployment/species.
DELTA_T_FAST_S = 600     # ≤ цього → m = 1.0 (пік метаболізму)
DELTA_T_SLOW_S = 7200    # ≥ цього → m = 0.0 (мінімум)
m              = ((DELTA_T_SLOW_S - delta_t_s) / (DELTA_T_SLOW_S - DELTA_T_FAST_S)).clamp(0.0, 1.0)
growth_points  = (5 + m * 26).round.clamp(5, 31)   # 5-бітний wire (FW.29-PACK); backend ×2 → stored 10..62
```

> **Wire vs Stored:** wire `growth_points` — 5-бітне `(5 + m·26).round.clamp(5, 31)`; backend `TelemetryUnpackerService` **лише декодує** wire-значення `(status_byte & 0x1F) * 2` → stored 10..62 — магнітуду з `delta_t` **НЕ** перераховує. Метаболічний DCI = структурний `check_metabolic_divergence!` (homeostasis→GP∈5..31, stress→GP==1; observational, як `check_z_divergence!`); точний `m(delta_t)`-перерахунок неможливий (wire=raw, GP=EMA), відкладено до **FW.2** — механіка й присуд у [`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA). Z (хаос) — для status-гейту + numeric-DCI (server-Z ≡ device-Z).

**Нарахування `growth_points` (wire) за `delta_t` — польова шкала перезаряду (монотонно, лінійно між FAST=600с і SLOW=7200с):**

| `delta_t` (с) | `m` | **Wire `growth_points`** (5-bit) | **Stored** (×2) | Стан метаболізму |
|---|---|---|---|---|
| ≤ 600 | 1.00 | **31** | 62 | Піковий — швидкий перезаряд |
| 1800 | 0.82 | **26** | 52 | Активний |
| 3900 | 0.50 | **18** | 36 | Помірний |
| 5400 | 0.27 | **12** | 24 | Млявий |
| ≥ 7200 | 0.00 | **5** | 10 | Мінімум (усе ще гомеостаз) |

> 📐 **Wire vs Stored:** Wire `growth_points` — 5-бітне поле, яке Soldier пакує у StatusByte; backend `TelemetryUnpackerService` робить `(status_byte & 0x1F) * 2` → Stored (`TelemetryLog#growth_points`). Калібрувальні `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` — placeholder (bench, E.63); таблиця оновиться після зміряної recharge-кривої. **[E.63 (г), wire-rev2.1]** ВХІД формули (сатурований EMA-delta_t) їде у wire bytes 20..21 за контрактом «wire = вхід GP» → backend перевіряє цю таблицю **stateless байт-точно** (`Attractor.expected_homeostasis_gp` — byte-identical дзеркало цієї формули; observational до калібрування). Wire-дім — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security).

(Поза гомеостазом — гейт §4.2: `z < 2` → wire 1 / stored 2 (стрес, absolute); `z > ρ+(CRITICAL_Z_MAX−BASE_RHO)` → wire 0 (аномалія, [E.64] ρ-відносна; =45 при ρ=28, дзеркало `Attractor.anomaly_ceiling` §4 E.64-нота / код — НЕ hardcoded offset).)

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
| `11` | `3` | `vm_error` (mruby VM-збій → `BIO_STATUS_VM_ERROR=0x60`: status=3, gp=0, виживає mask `& 0x7F`; софт-фолт, **НЕ** tamper — SLASH-1 P0; фізичний tamper → PANIC_FLAG-канал) |

**Розпакування на backend:**

```ruby
# app/services/telemetry_unpacker_service.rb
# [FW.29-PACK] +×2 upscale зберігає tokenomic invariant — stored 0..62 vs wire 0..31
growth_points = (status_byte & 0x1F) * 2     # bits 4..0 (×2 backend upscale)
bio_status    = (status_byte >> 5) & 0x03    # bits 6..5
```

---

## 🔄 5. Подвійне Обчислення: Firmware vs Backend

SilkenNet використовує **dual computation integrity verification**: Z-значення обчислюється **двічі** — на пристрої та на сервері — для виявлення маніпуляцій або збоїв.

### 5.1 Порівняльна Таблиця Реалізацій

| Параметр | Firmware (mruby) | Backend (Rails) |
|---|---|---|
| **Файл** | `firmware/bio_contracts/bio_contract.rb` | `app/services/silken_net/attractor.rb` |
| **Точність** | Ruby `Float` (IEEE 754, 64-bit або 32-bit залежно від mruby build) | `Float` (IEEE 754, 64-bit) — **ідентично firmware** [FIX FW.7] |
| **σ** | `10.0` (Float) | `10.0` (Float) |
| **ρ** | `28.0` (Float) | `28.0` (Float) |
| **β базовий** | `8.0 / 3.0` (Float) | `8.0 / 3.0` (Float) |
| **β** | `BASE_BETA` (фікс) [E.63] | `BASE_BETA` (фікс) [E.63] |
| **growth_points (homeostasis)** | `metabolic_health(delta_t)` → wire (§4.3) | wire-decode `(byte & 0x1F) * 2` |
| **DT** | `0.01` (Float) | `0.01` (Float) |
| **Clamp σ** | `if local_sigma < SIGMA_MIN` / `> SIGMA_MAX` | `.clamp(SIGMA_LIMITS.min, SIGMA_LIMITS.max)` |
| **Clamp ρ** | `if local_rho < RHO_MIN` / `> RHO_MAX` | `.clamp(RHO_LIMITS.min, RHO_LIMITS.max)` |
| **Seed-походження `(x₀,y₀,z₀)`** | [SEC.11] Cold start: `K_seed` з Flash → HMAC; warm: RTC DR16-DR18 | [SEC.11] Cold start: `hardware_keys.lorenz_seed_hex` → HMAC; warm: попередній `telemetry_logs.lorenz_state_x/y/z` |
| **Результат** | `z` (Float, необроблений) → пакується у `status_byte` | `z.round(4)` → зберігається у `TelemetryLog.z_value` |
| **Де використовується** | Пакується у `payload_byte` (byte 10 LoRa) | `TelemetryLog.z_value`, ZK-proof верифікація |

> **[SEC.11] Byte-Identical Initial State:** firmware та backend **деривують той самий `(x₀, y₀, z₀)`** через спільний HKDF/HMAC-SHA256 алгоритм з per-device `K_seed` (`SilkenNet::SeedDerivation` ↔ pure-C `silken_sha256.h` у firmware). DID більше не використовується як seed. Тому raw Z-значення тепер може порівнюватися чисельно (виміряний drift = **0 бітово**: ARM↔x86 — FW.55 QEMU byte-parity; mruby-VM↔CRuby — sweep N=10k, §7.1 Gate L). `check_z_divergence!` залишається категоричним за замовчанням; числовий tolerance band готовий до flip під feature-flag — Gate L закрито, лишаються гейти D/C/P/G (§7.1) + кремнієвий хвіст у FW.55 silicon-confirm дампі.

> 🔴 **Чому DCI прив'язаний саме до Z, а не до скаляра Ляпунова (передумова будь-якого майбутнього стиснення).** Порівняння device-Z ↔ server-recomputed-Z бере **точну координату після 250 ітерацій**, чутливу до input-tampering майже на біт-рівні. Якби вузол слав замість неї λ (показник Ляпунова), DCI змушений був би порівнювати device-λ ↔ server-λ — а це **слабший** cross-check: λ — **many-to-one** відображення (різні траєкторії дають той самий λ), тож простір підробки ширший. Тому λ-режим лишається Beyond-TRL-9 і **не вмикається без DCI-захисту**: або періодичний **full-Z challenge** (випадкова вибірка вузлів віддає повний `device_z` для калібрування), або λ + occasional **Z-sentinel**. Це не вада поточної архітектури — вона передає повний Z — а передумова *безпечного* вмикання стиснення; на неї спирається вибір Merkle-листа в [`05_02`](05_02_Proof_of_Growth_Pipeline). ⊕ Байтового мотиву в такої заміни немає: `device_z` на дроті **вже 2 байти** (`FW2_DEVICE_Z_SCALE`, uint16 z×512, wire-rev2), тож λ(2B) ↔ Z(2B) = **0 байт економії**, а ширшу arithmetic-компресію канон відхилив по енергії ([`03_05 §10.3`](03_05_Hardware_Symmetric_Crypto_and_Security)) — заміна можлива лише як wire-rev3-клас ([`00_07` ARCH.43](00_07_Action_Plan_Tracker)).

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
  # [E.64] ρ-відносна стеля аномалії (дзеркало firmware): ambient-temp не дає хибний mismatch
  ceiling = SilkenNet::Attractor.anomaly_ceiling(attributes[:temperature_c], thresholds[:max])
  server_healthy = server_z >= thresholds[:min] && server_z <= ceiling
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
      Silken_Hmac_Sha256(k_seed, 32, info, 13, digest);  // pure-C silken_sha256.h, FW.30 (НЕ mbedTLS)
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
  args[5] = mrb_fixnum_value(delta_t_s);                // [E.63] EMA DR10 → growth_points §4.3
  args[6] = mrb_fixnum_value(vcap_mv);                  // [E.63] EMA DR12 (reserved; не на Z)

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
# [E.63] delta_t_s → growth_points напряму (§4.3); vcap_mv reserved; β = BASE_BETA фікс.
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
2. `OtaPackagerService` різбиває на 512-байтні CoAP-чанки `[0x99][idx:2][total:2][len:2][bytecode][crc16:2]`; Королева тягне їх сама (`GET ota/<uid>?v=&ch=` — poll-fetch [FW.60], [`03_02 §4а`](03_02_Queen_Gateway_Firmware))
3. Queen збирає chunks у `pending_ota_bytecode[8192]` (bitmap-дедуп)
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
> **⚠️ Що саме координують Queens — дві РІЗНІ математики, які легко сплутати однією назвою.** Lorenz σ/ρ/β — це ODE-система **без ваг**, її не тренують backprop'ом: обмін між Queens = **Distributed Parameter Estimation** (PSO/GA шукає оптимальні σ,ρ,β для локального кластера, Queens міняються *оцінками параметрів*, не градієнтами). Акустичний TinyML — інша річ: там доречне навчання, але це **Cluster-level Edge Retraining** (Queen ретренить класифікатор на даних свого кластера → `.tflite` → OTA), а **не** Federated Learning; справжній FL можливий лише як обмін *оновленнями моделі* Queen↔Rails ([`03_03 §11.4`](03_03_TinyML_Acoustic_Inference)). Мотив у нас — **не privacy** (у дерев немає GDPR-даних, а бекенду навпаки потрібні сирі семпли кавітації/пилки для глобальної моделі), а **економія airtime/енергії**.
>
> **⚠️ Stigmergy маршрутизується через L2/L3, ніколи P2P — і причина фізична.** «Stigmergic LoRa-broadcast» вище описує лише *емісію* 1-bit сигналу «я в червоному Z-bucket» (дешево: ~110 ms TX @ +14 dBm). **Зворотний шлях** — ні: Soldier перебуває у STOP2 ~99.9% часу ([`03_01`](03_01_Firmware_Lifecycle_and_DMA)), радіо SX1262 вимкнене, він фізично не «чує» сусіда, а continuous-RX вичерпав би 0.47F іоністор за хвилини. Тому сигнал ловить **always-on L2 Conductor / L3 Queen** і акумулює як «феромонний слід», а команда «підняти sampling rate» доставляється сусідам у їхнє наступне заплановане RX-вікно. Це не послаблення ідеї, а **точніша** stigmergy: мурахи теж не передають сигнал напряму, а лишають слід у середовищі — роль персистентного середовища тут грає Queen.
>
> **⚠️ І тому слід ≠ імпульс: дві окремі доставки, не одна.** Латентність наступного RX-вікна (≈15 хв) прийнятна лише для **повільних** процесів (посуха, хвороба, кліматичний тренд). Для **швидких** загроз (бензопила, пожежа) 15 хв = вже спиляне сусіднє дерево, тож зворотний шлях іде не через розклад, а через **emergency extended-preamble wake-up** — канон у [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA) (PANIC ініціює *відправник* подовженою преамбулою, а не постійний RX приймача).
>
> **Еволюція самої структури контракту** (найдальший щабель): не лише параметри, а й форма атрактора може змінюватись — Lorenz → Lorenz-96 (більша розмірність для дерев у кластерах) → кастомні мутації через genetic programming. 🔴 Передумова безпеки: будь-який self-modified контракт мусить нести **криптографічний якір**, інакше зловмисник інжектить свою логіку через RL reward poisoning ([`03_03 §11.4`](03_03_TinyML_Acoustic_Inference)).

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

**Гейт активації — `device_z` має бути в payload: ✅ wire-дім існує (FW.2 wire-rev2, 2026-06-12).**

Numeric branch виконується **лише** коли `attributes[:device_z]` присутній. Транзитний 21B ECB-пакет raw Z **не несе** — фірмварний `bio_contract.rb#calculate_state` повертає тільки `status_byte = [PanicFlag:1 | Status:2 | GrowthPoints:5]` (FW.29-PACK). **FW.2 wire-rev2.1** (30-байтний CCM-пакет, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) + wire-budget ledger) виділив `device_z` bytes 16..17 шифртексту: **u16 фіксована точка z×512 (q=2⁻⁹)** — похибка квантування ≤ 0.00098 строго менша за ε=0.001 (запас тонкий, але Gate L дав drift=0, тож сумарна |Δ| = сама квантизація); діапазон 0..127.99 покриває E.64-стелю (≤67 при ρ_max=50) без сатурації; **сентинель `0xFFFF` = «Лоренц цього циклу не рахувався»** (ARCH.41-C grace, невалідний seed) → атрибут відсутній, branch чесно пропускається. Pack — `Pack_FW2_Device_Z(lorenz_z, lorenz_state_valid)` (`lora_ccm.h`); unpack + e2e — `process_ccm_chunk` ("FW.2 CCM path" спеки). Покриття ≥95% (Gate D) досяжне, бо device_z їде у КОЖНОМУ telemetry-кадрі (сентинель лише у grace-вікнах). Альтернативи (ML2 snapshot-варіант / server-side surrogate) лишаються в історії як відкинуті — wire-дім дешевший і дає повне покриття.

Branch інертний до фліпу `FW2_CCM_ENABLED` + `TELEMETRY_CCM_ENABLED` (+ ENV-флаги вище) — код staged у production без поведінкової зміни.

**Gate L — вимірювання drift ✅ machine-closed (2026-06-11, без заліза):**

Оригінальний протокол (N=10k векторів → x86 vs прошитий STM32 через SWD/RTT) писався до появи QEMU-лейну FW.55. Розкладання DCI-ланцюга на плечі закрило його софтом:

| Плече | Метод | Результат |
|-------|-------|-----------|
| mruby-ARM32 (девайс) ↔ mruby-x86 | FW.55 QEMU byte-parity ([`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)): той самий байткод на реальному M4 ISA-шляху, 64 зчеплені кейси (хаос ампліфікує будь-який ULP) | **бітова рівність** (кожен CI-прогін) |
| mruby-VM ↔ CRuby (справжній контракт) | `tools/firmware/dci_epsilon_sweep.sh` — **N=10 000 зчеплених кейсів** (генератор бітово дзеркалить `parity_core.h`; кожна сторона ланцюжить власний хвіст = модель warm-chaining DCI; CRuby-сторона = `bio_contract.rb` напряму, FW.57-ізоляція) | **бітова рівність 10000/10000**, payload 0 розбіжностей, max\|Δz\| = 0 |
| CRuby-контракт ↔ backend `Attractor` | 200-кейсовий fuzz `attractor_spec` (FW.57 F4, постійний CI-гейт) | категорично + числово збігається |

**Висновок Gate L:** за поточної pinned-конфігурації (mruby 4.0.0, явний `MRB_NO_BOXING` + `MRB_CONSTRAINED_BASELINE_PROFILE` — [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA)) увесь ланцюг device-mruby → server-CRuby **бітово точний**; виміряний drift = 0, ε=0.001 — чиста страховка від silicon-сюрпризів і майбутніх конфіг-дрейфів (правило кроку 6 «ε < 0.0001 → ставимо 0.001 conservative» виконано з нескінченним запасом). Історичне спостереження «~1e-14» (перший VM-прогін 2026-06-04, один кейс) **superseded** — не відтворюється: той самий кейс сьогодні бітово рівний (sweep, кейс 0). Кремнієвий хвіст Gate L = той самий one-command FW.55 silicon-confirm дамп (SWD, закриває FW.7/FW.19/FW.31 разом). Sweep — відтворюваний інструмент, не CI-гейт: переганяти після змін контракту/mruby-конфігурації.

**Rollout gates (порядок активації):**

1. **Gate L (Lab):** ✅ див. вище — drift виміряно (=0), ε=0.001 підтверджено conservative; кремнієвий хвіст їде з FW.55-дампом.
2. **Gate D (Device coverage):** `device_z` доступний у ≥ 95% telemetry packets. ✅ Wire-дім готовий (FW.2 wire-rev2, bytes 16..17 + сентинель — блок вище); вимірювання 95% — після CCM-фліпу (метрика decrypt_ok vs сентинель-частка).
3. **Gate C (Canary):** Активація в `WEB3_STRICT_MODE=false` staging кластері на 24 год. Watch `silkennet_dci_numeric_rejections_total` (новий Prometheus counter, додати в [`06_03`](06_03_Prometheus_Observability) після Gate D). Очікувано: 0 rejections (бо ε > max observed drift у Gate L). Будь-яке non-zero rejection → analiza root cause (seed corruption? RTC drift? overflow?) перед production.
4. **Gate P (Production canary):** Single Genesis cluster, `GAIA_DCI_NUMERIC_TOLERANCE=true` через `kamal env push`, моніторинг 72 год.
5. **Gate G (Global):** Flip всіх production кластерів.

**Rollback procedure:**

```bash
# Kamal env push без redeploy:
kamal env push --secret GAIA_DCI_NUMERIC_TOLERANCE=false
# АБО видалити з .kamal/secrets-common, тоді next deploy картки залишиться без флагу
```

Жоден код-rollback не потрібен — feature-flag перетворює numeric branch на no-op. Категорична перевірка продовжує захищати DCI.

**Side effects після flip:**

- Fraud detection стає **числовим**: ловить replay-атаки з правильним enum, неправильним magnitude — як описано на початку §7.1.
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

**Cross-ref:** [`00_07` — FW.31](00_07_Action_Plan_Tracker), [`03_05 §2.1` FW.2 CCM wire format](03_05_Hardware_Symmetric_Crypto_and_Security), [`04_02` — TelemetryUnpackerService](04_02_Business_Logic_and_Services), [`06_03` — Prometheus](06_03_Prometheus_Observability) (після Gate D — додати `silkennet_dci_numeric_rejections_total`).

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
