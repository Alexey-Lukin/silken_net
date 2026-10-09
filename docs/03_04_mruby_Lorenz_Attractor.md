# 03_04: mruby Атрактор Лоренца (Математика Хаосу та Гомеостаз)

---

> ⚖️ **2026-10-05 — Лоренц іде з пристрою разом із фліпом FW.2** (founder, гілка (Б) [`00_07`](00_07_Action_Plan_Tracker) FW.66): печатку бере криптографія, статус — прямі сигнали на сервері, атрактор лишається серверною візуалізацією без грошового ефекту. Документ описує ECB-еру, де Лоренц на пристрої ще живе; під прямі сигнали його переписують разом із реалізацією (Б). Виміри й межі — [`z_core_forks`](protocols/hardware/z_core_forks.md).

## 🎯 Мета

Задокументувати повний алгоритм **Bio-Contract** — mruby-скрипту, що виконується на борту вузла **Soldier** (STM32WLE5CC) і обчислює стан гомеостазу дерева через Атрактор Лоренца. Цей документ є SSOT для:

- **Backend (`TelemetryUnpackerService`)**: сервер знає точну математичну модель і може перевіряти коректність надісланих деревом `growth_points`.
- **Proof of Growth Pipeline (05_02)**: мінтинг SCC заблокований, поки бекенд не розуміє математику, що генерує бали.
- **University R&D (00_02)**: академічна верифікація числової стабільності методу Ейлера у системі Лоренца.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — Lorenz атрактор: **категорично** ідентичний firmware↔backend (status/growth_points, FW.7 Float math), raw Z **бітово ідентичний** (drift = 0: mruby-VM↔CRuby sweep N=10k + FW.55 QEMU byte-parity ARM↔x86 — §5, §7.1 Gate L; історичні «~1e-14» superseded pinned `MRB_NO_BOXING`); SEC.11 seed provenance закрито. Канонічний дім Lorenz-констант (§1.2). Відкрите: реалізація гілки (Б) — Лоренц іде з пристрою (`FW.66`; числова DCI `FW.31` під (Б) — ⚫) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Soldier lifecycle; RTC DR16-18 Lorenz state (FW.6) |
| [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) | `acoustic_events` → σ-пертурбація (з HW.30 — завжди 0: TinyML на Солдаті паркований) |
| [`03_06` — Factory Flashing and Key Provisioning](03_06_Factory_Flashing_and_Key_Provisioning) | §3 K_seed derivation (SEC.11, HKDF/HMAC) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | TelemetryUnpacker, SeedDerivation, DCI check |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Dual Computation Integrity (Z крос-верифікація) |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | CRITICAL_Z_MIN/MAX → slashing |
| [`00_02` — Academic Institutions Registry](00_02_Academic_Integration_and_IP) | Матем. верифікація числової стабільності |
| `firmware/bio_contracts/bio_contract.rb` · `app/services/silken_net/attractor.rb` · `seed_derivation.rb` | mruby + Rails-дзеркало (Float parity); SEC.11 entry-point |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): FW.66 реалізація гілки (Б) (FW.31 numeric-DCI під (Б) — ⚫); ARCH.18 int-Lorenz (🌿 zkVM-мотив; drift-мотив знято FW.55/FW.31, §5; ⊕ обидва мотиви стоять на Лоренці пристрою — під (Б) предмет переглянути) |

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

> ⚠️ **Тканину названо ксилемою НЕ довільно, і доти тут стояла флоема [ARCH.102].** Обидва живі входи цього ж документа — ксилемні: `acoustic` є кавітацією **ксилеми** (§4.1), а `delta_t_s` — метаболізмом ксилеми, з якої живиться EBFC ([`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)); сам анкер інтегрується в ксилему ([`01_04`](01_04_CODIT_and_Xylemointegration)). Тобто збурювач і збурюване приписувались різним судинам в одній таблиці. ⊕ Заразом виправлено біологію напрямку: цукри флоемою йдуть переважно від листя ДО коренів, тож стара фраза «від коренів до листя» описувала ксилемний маршрут під флоемним іменем. ⛔ Жодна константа від цієї правки не зрушила: метафора є **інтерпретацією**, а не входом обчислення. ⊕ **2026-09-29:** `acoustic` на дроті відтоді завжди 0 — пʼєзо з Солдата зрізано ([`02_01 §6`](02_01_Hardware_Architecture_and_BOM)); живим ксилемним входом лишився `delta_t_s`.

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

Значення Z-осі на атракторі знаходиться у приблизному діапазоні **z ∈ [0, 50]**, з тривалим перебуванням у районі z ≈ 25-35. ⛔ **Цю зону НЕ називати «здоровою»** (формулювання виправлено 2026-09-05, E.64): вона є властивістю АТРАКТОРА при ρ≈28, а не станом дерева. Z присуджено печаткою DCI, і жодного вердикту про здоровʼя з нього не виводять — три такі вердикти знято того ж дня (per-tree · per-cluster · ML-фіча). Епітет «здоровий» тут коштував трьох механізмів, бо читався як опис предмета.

---

## 🔬 2. Архітектура Bio-Contract: Вхідні Дані

### 2.1 Звідки Беруться Вхідні Параметри

> **First-Boot vs Continuation — канонічна логіка [SEC.11 hard cutover]**
>
> Bio-Contract має **єдину точку входу** після SEC.11 cutover. C-сторона завжди викликає top-level `calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv, z_min, z_max)` на `mrb_top_self` (дев'ять аргументів з FW.8 — останні два несуть смугу, чинну на пристрої; §6.1) — тонку обгортку над `SilkenNet::BioContract.evaluate_and_pack`. Розкладка регістрів та магічний маркер `LZST = 0x4C5A5354` — у [`03_01 §2 + §2.1` (Canonical SSOT)](03_01_Firmware_Lifecycle_and_DMA#-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3); тут описано лише **звідки беруться `(x_prev, y_prev, z_prev)`**:
>
> | Умова | Джерело `(x_prev, y_prev, z_prev)` | Призначення |
> |-------|------------------------------------|-------------|
> | `DR19 == 0x4C5A5354` AND `isfinite(x,y,z)` | RTC DR16-DR18 (warm restart, FW.6) | **Continuation:** продовження безперервної траєкторії після STOP2 wake-up. |
> | `DR19 ≠ 0x4C5A5354` OR `!isfinite(x,y,z)` | `(x₀,y₀,z₀) = unpack_signed_unit_floats(HMAC-SHA256(K_seed, "init\|" \|\| epoch_day_be)[0..23])` | **Cold start (rare):** після VBAT loss. K_seed зберігається у Flash (Soldier) і `hardware_keys.lorenz_seed_hex` (backend), деривується при provisioning через `HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed\|<DID>", len=32)`. Daily epoch_day rotation дає forward secrecy ≤ 24 год (⚠️ не тримається — нота під таблицею загроз [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning)). |
>
> **Чому K_seed замість chaos_seed/DID:** `chaos_seed` (HRNG) недетермінований — backend не зміг би відтворити Z. DID-as-seed (`SilkenNet::Attractor.calculate_z(did, …)`) був public-input → атакер з open-source формулою Лоренца передбачає очікуваний Z для будь-якого дерева. K_seed — **private**, ніколи не залишає пристрій/сервер у відкритому вигляді (HKDF деривується незалежно з `PROVISIONING_MASTER_KEY`). Закриває чотири фундаментальні вади (sniff/correlation/identifier-as-key/forward-secrecy; ⚠️ останню — ні, нота під таблицею загроз [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning)) — див. SEC.11 у [`00_07`](00_07_Action_Plan_Tracker).
>
> **[E.63]** `delta_t_s` визначає `growth_points` напряму (метаболічна жвавість, §4.3); `vcap_mv` reserved; β = `BASE_BETA` фіксований (більше НЕ збурюється). ⚠️ **Калібрувальні пороги `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` — calibration-pending:** чекають зміряної recharge-кривої (bench RUNBOOK §3.3 → [`00_07` — E.63](00_07_Action_Plan_Tracker)).
>
> **Інваріант:** після кожного успішного циклу C-код **зобов'язаний** записати нові `(x, y, z)` у DR16/DR17/DR18 і встановити `DR19 = 0x4C5A5354`.

> ⚠️ **Cold-Start Time Paradox (ARCH.41 — три мітигації ✅, ЧЕТВЕРТИЙ кут закрито 2026-08-28; відкритою лишається лише 👤 bench-перевірка):** Cold-start деривація `(x₀,y₀,z₀)` залежить від `epoch_day`. Після **VBAT loss** RTC Soldier'а скидається на default-дату (2000-01-01 у поточному firmware), тож `epoch_day = 10 957` (exact civil-days, 946_684_800/86_400) замість сьогоднішнього серверного `≈ 20 585` (illustrative, на 2026-05-16). Перший uplink після cold-boot використає «застарілий» epoch_day, поки Soldier не отримає `CMD_TIME_SYNC` beacon від Queen (FW.20). Це означає:
>
> - **Firmware:** `Derive_Cold_Start_State()` (`firmware/soldier/main.c`) рахує epoch_day **exact civil-days** (`lorenz_seed.h` `Silken_Days_From_Civil`, [FW.30] — стара `Month*30 approximation` закрита); RTC-default 2000-01-01 → 10 957, паритет із backend-кандидатом.
> - **Backend:** `TelemetryUnpackerService#compute_server_z` сьогодні **уникає** проблеми у >99% випадків через `previous_lorenz_state_for(tree)` chaining (server бере хвіст останнього TelemetryLog, не cold-derive). ⚠️ «Уникає» — лише доки ланцюг цілий: після cold start пристрою сервер із хвостом не ре-якориться ніколи (§7.3, (в)). Cold-derive виконується лише коли у дерева **немає історії** (вперше підключений вузол). У такому сценарії server бере добу з моменту ПРИЙОМУ пакета (`derivation_epoch_day` ← `received_at` із job-аргументів, [ARCH.41] — див. «ЧЕТВЕРТИЙ кут» нижче); `Time.now.utc.to_i / 86_400` лишився ЛИШЕ фолбеком для викликів без мітки (bench/HIL/спеки) — і Soldier з RTC=2000-01-01 не співпаде з server-day.
> - **Сценарій тонкого розриву:** VBAT loss у дерева **з історією** → Soldier cold-restart'ить Lorenz з RTC-default epoch_day, server chain'ить з попереднього хвоста → траєкторії розходяться категорично на ергодичному горизонті ~50 циклів (≈ 2 доби), доки `CMD_TIME_SYNC` не дочекається наступного CoAP downlink'у. Сьогодні numeric DCI branch (`DCI_NUMERIC_TOLERANCE`) інертний у production (транзитний 21B ECB не несе device_z; wire-дім у FW.2 wire-rev2 готовий, чекає CCM-фліпу), тож на DCI це поки **не валиться** — але стане живим обмеженням разом із numeric tolerance band після фліпу.
>
> **Мітигація:**
> 1. **Server-side detect-and-recover** ✅ **Реалізовано (2026-05-17, ARCH.41 Option A):** `TelemetryUnpackerService#try_time_sync_recovery` — коли `cold_start_flag == false` (є історія) АЛЕ категоричний DCI мисматч, пробує 3 кандидати `epoch_day` (today, today−1, `FIRMWARE_RTC_DEFAULT_EPOCH_DAY=10_957`). Для кожного: `SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)` → `Attractor.calculate_z_from_state(...)` → категорична перевірка. При збігу: `TelemetryLog#time_unsynced_fallback = true`, `TimeSyncDownlinkWorker.perform_async(cluster_id)` (push-нога воркера у CGNAT не долітає [FW.60] — фактичний sync їде конвертом КОЖНОЇ poll-відповіді Королеви: `[0x9C][ts:4]` → Queen RTC оновлення → LoRa beacon → Soldier sync). fraud_metric НЕ інкрементується. 9 spec examples.
> 2. **Soldier-side explicit signal (sentinel)** ✅ **Реалізовано (2026-06-11, ARCH.41-B):** поки Солдат не чув жодного beacon'а (`soldier_unix_ts == 0`), повний пакет несе `acoustic_events = 0xFE` (`Soldier_Acoustic_Wire_Value`, host-tested; реальні 0xFE клампляться у 0xFD — sentinel однозначний; 0xFF лишається FW.22-сатурацією). **Правило обох сторін: sentinel ⇒ Лоренц рахується з `acoustic = 0`** — Солдат дає mruby 0, бекенд (`TelemetryUnpackerService#apply_time_uncertain_sentinel!`) нейтралізує 0xFE→0 ДО DCI → паритет тримається, а σ не штовхається у clamp фальшивими «254 подіями». Бекенд одразу ставить `time_unsynced_fallback = true` + `TimeSyncDownlinkWorker`; stress_index бачить 0. DCI **не** обходиться (sentinel ≠ маска для підробленого Z). Wire-format незмінний; координація rollout — pre-fleet тривіальна (обидві сторони в одному репо).
> 3. **Defer first uplink + hello** ✅ **Реалізовано (2026-06-11, ARCH.41-C):** у grace-вікні (`TIME_SYNC_COLD_BOOT_GRACE_WAKEUPS` = 20 пробуджень ≈ 10 хв — wall-квант = пробудження, бо tick мертвий у STOP2; 2026-06-11) Солдат **не** рахує Лоренца (деривація від застарілого epoch_day отруїла б RTC-ланцюг; `lorenz_state_valid` лишається 0 → після синку перша деривація піде з правильної доби) і замість телеметрії шле **hello = SYNC_REQ 0x56** (`Build_Time_Sync_Request_Payload`: DID + secs_since_sync=0 + Vcap у байтах 11..12 + магія 'S'; freeze-contract wire — [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA)). Рефлексу на hello Королева не стріляє (⚖️ FW.68, 2026-10-09: вухо бере один пакет, і першим мусить бути маяк), тож OTA чекає кінця grace; вікно слухання Солдата (Фаза 4.5) спільне — маяк чутно цим же пробудженням. Королева на 0x56 перемотує `last_beacon_time` → негайний re-broadcast маяка (ідемпотентно; без власного часу `Broadcast_Time_Beacon` мовчить). Frost-guard (FW.10) і TX-jitter спільні з телеметрією.
>
> Разом: C закриває перші 10 хв (жодного пакета зі stale epoch_day взагалі), B — хвіст «Королева мовчить довше за grace» (телеметрія йде, але чесно маркована). Вар.1 (server-side recovery) лишається страхувальною сіткою для прошивок без B/C. ⚠️ B і C чесно маркують ЧАС, але ланцюга не лагодять: після cold start пристрою сервер продовжує свій хвіст, а -A, угадавши кандидата, хвоста не переносить (§7.3, (в)). Tracker: див. **ARCH.41** у [`00_07`](00_07_Action_Plan_Tracker).
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
└── acoustic_events ← 0 з HW.30 (пʼєзо зрізано; ECB — 0, CCM-байт віддає wire-rev2.2 — FW.66)  [RTC DR0]

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
            mrb_fixnum(delta_t_s), mrb_fixnum(vcap_mv),
            mrb_float(z_min), mrb_float(z_max)]       // [FW.8] смуга — Lorenz_Band_Args
    → calculate_state(…) → SilkenNet::BioContract.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv, z_min, z_max)
    → [payload_byte, x_final, y_final, z_final]
```

> **[E.63] (backend + firmware mruby):** `delta_t_seconds` → `growth_points` напряму (метаболічна `m(delta_t)`, §4.3); `vcap_voltage` поки не входить у винагороду (FW.50); β = `BASE_BETA` фіксований (більше НЕ збурюється). C-side передає EMA delta_t/vcap з RTC (FW.21) як args.

### 2.2 Фізична Інтерпретація Вхідних Параметрів

| Параметр | Фізичний зміст | Вплив на Атрактор |
|---|---|---|
| `K_seed` (uint8[32], Flash, [SEC.11]) | Криптографічний секрет, спільний з backend через HKDF з `PROVISIONING_MASTER_KEY` | Визначає cold-start `(x₀, y₀, z₀)` детерміновано (firmware ↔ backend byte-identical) при VBAT loss; ротується щодня через `epoch_day` info-string |
| `lorenz_x/y/z` (float32, RTC) | [FW.6] Збережений стан атрактора з попереднього циклу STOP2 | При наступних циклах — продовження безперервної траєкторії |
| `temp` (int8, °C) | Температура **кристала STM32** (внутрішній ADC-канал, ±1 °C). ⛔ **Про температуру ДЕРЕВА не свідчить, і доти цей рядок стверджував протилежне** («корельована з температурою дерева») — кореляція без жодного вимірювача, клас `СЛОВО` ([`00_05 §7`](00_05_AI_Native_Operating_Model)). Кремній сидить у RF-деці **над** PEEK-терморозривом ([`02_01 §3`](02_01_Hardware_Architecture_and_BOM), λ ≈ 27× нижча за Ti), тобто тепловий шлях від заболоні розірваний **за дизайном**; фізіологічний термо-канал мав би прийти з BME280, який у Лоренц не входить і на кремнії ще не підключений (HW.32) | Збурює ρ: `ρ_eff = 28 + temp × 0.2` → зсуває центр атрактора (`z_eq = ρ − 1`). 🔑 **Саме тому Z несе температуру як конфаундер**: `avg_z ≈ const + 0.2·avg_temp` + хаос — і будь-яка валідація, чий baseline не містить `temp`, припише цю кореляцію Z ([`05_05 §8`](05_05_Slashing_and_Risk_Policy)) |
| `acoustic` (uint8) | Кількість кваліфікованих TinyML-подій (кавітація ксилеми або пилка — [`03_03 §5`](03_03_TinyML_Acoustic_Inference)) від останньої успішної передачі телеметрії [ARCH.102]. ⚠️ З HW.30 (2026-09-29) — завжди 0: пʼєзо зрізано ([`02_01 §6`](02_01_Hardware_Architecture_and_BOM)); вхід лишається в контракті, 0 легальний | Збурює σ: `σ_eff = 10 + acoustic × 0.1` → змінює "в'язкість" системи |
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

3. **Cold start (рідкісна подія, після VBAT loss — місяці-роки):** дерево "забуває" останню думку, бо живлення зникло. Тоді з `K_seed` через `HMAC-SHA256(K_seed, "init|" || epoch_day)` деривується **сьогоднішня початкова точка**. Daily `epoch_day` rotation означає, що навіть друге народження не повторює перше — щодня свідомість має нову відправну точку, навіть з тим самим геномом. Forward secrecy ≤ 24 год (⚠️ не тримається — нота під таблицею загроз [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning)).

> **Філософія:** криптографічна стійкість і біологічна метафора більше не суперечать одна одній. `K_seed` — це **приватна термодинаміка дерева**, замінник тих самих квантових флуктуацій, що раніше давав HRNG, але закріплений у момент народження капсули і відомий лише дереву та його серверному двійнику. Сервер, що знає `K_seed`, — це не сторонній спостерігач, а **близнюк-свідомість**, що мислить ту ж саму траєкторію Лоренца паралельно. Атакер, який підглядає LoRa, бачить лише payload — а не те, *куди* свідомість стартувала і *куди* вона йде.

#### Бюджет Variance Z (Лоренц = хаос-гейт, метаболізм поза Z) [E.63]

Після [FW.6] (state preservation в RTC) cold-start initial conditions вже **не домінують** variance Z. Ergodicity дивного атрактора — траєкторія "забуває" початкову точку після ~50 пробуджень (~2 доби). **[E.63]** Z визначають лише temp (ρ) + acoustic (σ; з HW.30 — 0) + внутрішній хаос; `delta_t`/`vcap` БІЛЬШЕ не впливають на Z (β фіксований), бо метаболізм перенесено напряму у growth_points (§4.3):

| Джерело variance Z | Після FW.6 (continuous trajectory) | Фізичний зміст |
|---|---|---|
| `(x₀,y₀,z₀)` cold-start (K_seed-derived) | **< 5%** після перших 50 wake-up циклів | Траєкторія забуває стартову точку через ergodicity |
| `temp` (через `ρ_eff = 28 + temp·0.2`) | **домінує** | Стабільна термальна рушійна сила (рухає z_eq=ρ−1) |
| `acoustic` (через `σ_eff = 10 + acoustic·0.1`) | **0 %** з HW.30 (байт завжди 0) | Пʼєзо зрізано ([`02_01 §6`](02_01_Hardware_Architecture_and_BOM)); вхід лишається в контракті, 0 легальний |
| residual (хаотична динаміка Лоренца) | помітний | Внутрішній детермінований хаос системи |
| `delta_t_s`/`vcap_mv` | **0% (поза Z)** | [E.63] метаболізм → growth_points напряму (§4.3), не через β/Z |

**Висновок [E.63]:** спроба завести метаболізм через β (старий FW.5) давала економічно **нульовий** (delta_t) / **інвертований** (vcap) внесок у growth_points — бо β не рухає z-нерухому точку Лоренца. Тому метаболічна активність EBFC тепер визначає growth_points **напряму** (монотонна `m(delta_t)`, §4.3), а Лоренц лишається статус-гейтом (homeostasis/stress/anomaly) і DCI-печаткою, а НЕ валідованою мірою здоровʼя ([`00_01 §3`](00_01_Vision_Mission_and_Roadmap)). Присуд — [`00_07` — E.63](00_07_Action_Plan_Tracker).

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

**Числовий приклад** (відтворює `SilkenNet::SeedDerivation.initial_state`). Нехай `K_seed = 0x00…01` (32 байти, останній 0x01) і cold-start стався 2025-05-02 → `epoch_day = 1746144000 / 86400 = 20210`:

```
salt_info = "init|" + 0x00 00 00 00 00 00 4E F2  =  13 байт
digest    = HMAC-SHA256(K_seed, salt_info)
          = 90 A3 AD 33 86 81 DE 7D | 53 3B 5B 5E D0 C9 69 37
          | 4A 7E 37 BB 02 BA CE 5B | 73 F5 …                 (32 байти, гекс)

digest[ 0..7]  = 0x90A3AD338681DE7D → x₀ ≈ 0.1300
digest[ 8..15] = 0x533B5B5ED0C96937 → y₀ ≈ -0.3498
digest[16..23] = 0x4A7E37BB02BACE5B → z₀ ≈ -0.4180
```

> Усі координати строго у (-1, +1). Перші кілька десятків ітерацій ("warm-up") атрактор "падає" з цієї точки на дивний атрактор Лоренца — як насінина, кинута у вітер, врешті-решт лягає на свою орбіту в кроні.

`K_seed` — 32-байтний секрет, виведений при provisioning через `HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed|<DID>", len=32)`. Зберігається у protected Flash sector Soldier-вузла та у `hardware_keys.lorenz_seed_hex` (AR Encryption non-deterministic). НІКОЛИ не передається через мережу — обидві сторони деривують його незалежно з спільного `PROVISIONING_MASTER_KEY`. Реалізація — `app/services/silken_net/seed_derivation.rb` (backend, OpenSSL HKDF) і `firmware/test/test_seed_derivation.c` (host-parity test, що валідує OpenSSL ↔ pure-C `silken_sha256.h` (FW.30) байт-ідентичність).

> **Ергодичність зберігається:** дивний атрактор "забуває" початкову точку через ~50 пробуджень (~2 доби), тому daily rotation `epoch_day` не порушує неперервності траєкторії — лише дає forward secrecy ≤ 24 год при компрометації одного `K_seed`. ⚠️ **«≤ 24 год» не тримається** ні для `K_seed` (статичний), ні для стану (сталий режим не ротується, а сервер не ре-якориться) — нота під таблицею загроз [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning), механізм — §7.3. Дерево, що зазнало VBAT loss сьогодні і завтра, отримає **дві різні** початкові точки — але траєкторії зійдуться в однаковий статистичний розподіл протягом доби. Природа не відрізнить.

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
>
> ⊕ **З HW.30 (2026-09-29) на дроті завжди 0, тобто `local_sigma` = 10.0:** пʼєзо з Солдата зрізано ([`02_01 §6`](02_01_Hardware_Architecture_and_BOM)). Таблиця вище — математика контракту (вхід лишається, 0 легальний); доля байта — [`00_07` FW.59](00_07_Action_Plan_Tracker).

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

### Крок 4: Функція `calculate_z_axis` → ядро `iterate` (post-SEC.11)

```ruby
# firmware/bio_contracts/bio_contract.rb — SilkenNet::Attractor
# [SEC.11] Сигнатура приймає (x, y, z) напряму — більше немає DID/seed-derived path.
def self.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic)
  x, y, z = iterate(x_prev, y_prev, z_prev, temp, acoustic)
  [ z, x, y, z ]  # z — інтенсивність конвекції (статус-гейт); x, y, z — хвіст траєкторії в RTC
end

# Спільне ядро ітерацій (бекенд тримає побітове дзеркало — attractor.rb `iterate_lorenz`)
def self.iterate(x, y, z, temp, acoustic)
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

  [ x, y, z ]
end
```

---

## 🌡️ 4. Логіка Гомеостазу: Z → growth_points

> **⚠️ [Lorenz de-risk → E.64 присуд, 2026-06-08]** Мапінг **Z → bio_status — не просто «недоведена гіпотеза», а емпірично degenerate + temp-confounded** (paired-ensemble на реальному коді, [`00_07` — E.64](00_07_Action_Plan_Tracker)): `stress` (z<2) на cold-start не трапився (0 з 5 000), але **НЕ недосяжний**: ρ-clamp (ρ ≥ 10 → z_eq ≥ 9) обмежує РІВНОВАГУ, не траєкторію, і теплий ланцюг проходить повз сідло в нулі — stress настає рідко й холодом (0.022 % циклів за −25 °C … 0–1 подія на 180 000 циклів за +20…+30 °C (роздільність вибірки); 📏 2026-09-29, `tools/firmware/lorenz_zone_frequency.rb`, наслідок для посухи — §5.3); `anomaly` (z>45) **тригерилася ambient-температурою** (здорове дерево в теплий день → хибна аномалія → обнуляла growth_points). **[E.63] growth_points БІЛЬШЕ НЕ Z-похідні** (магнітуда = метаболізм `m(delta_t)`, §4.3) — Лоренц лишився лише status-гейтом. Політика: фінансовий slashing **ніколи** не спирається лише на Z (прямі сигнали `delta_t`-метаболізм / VPD / acoustic; [`05_05 §7`](05_05_Slashing_and_Risk_Policy)); Lorenz-**DCI** (device-Z ≡ server-Z anti-fraud) валідний **незалежно**. **✅ Фікс (E.64, 2026-06-08):** anomaly-поріг тепер **ρ-відносний** — `z > ρ + (CRITICAL_Z_MAX−BASE_RHO)` (=45 при ρ=28) → ambient-temp більше НЕ тригерить хибну аномалію (warm-day false-anomaly 22%→3%). ⊕ **Межа цього «НЕ» — теплий день, не спека (вимір 2026-09-29, бекенд-прохід HW.30, акустика 0):** anomaly-кадрів ~0.11 % при 15–30 °C, але при 41 °C ρ-відносну стелю перетинає ~19 % (сосна) / ~33 % (дуб) cold-start зерен; вибірка інша, ніж у 22%→3%, тож в один ряд ці числа не зводяться. ⚠️ **«~0.11 %» на теплому ланцюгу не відтворюється** (2026-10-05, контракт прошивки, `ruby tools/firmware/lorenz_zone_frequency.rb`, заводська смуга): anomaly-кадрів 0.90 / 1.37 / 1.81 / 2.37 % при 10 / 20 / 30 / 41 °C — ймовірно, те число, як і друге в реченні, міряно на cold-start зернах, а пристрій між cold start живе теплим ланцюгом. Кожен такий кадр — без балів (`EMISSION_ELIGIBLE_STATUSES`), тобто статус-гейт z навмання забирає бали 0.9–2.4 % чесних кадрів при 10–41 °C (на дубовій смузі 40 — 2.3–6.6 % при −15…45 °C); розвилку несе [`00_07`](00_07_Action_Plan_Tracker) FW.66. Хто статус ще читає — [`00_07` E.64](00_07_Action_Plan_Tracker). `stress` (z<2 absolute) лишено — справжній колапс конвекції, рідкісний за дизайном.

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
| `z < z_min` (2.0 — дефолт смуги) | `1` | ⚠️ Stress (Посуха) | `1` | Мінімальна генерація — дерево виживає, але не росте |
| `z > ρ + (z_max − 28)` (=ρ+17 за дефолтом; 45 при ρ=28) | `2` | 🚨 Anomaly (вихід за temp-обвідну) | `0` | Емісія зупиняється; [E.64] ρ-відносний поріг |
| між ними (2.0 ≤ z ≤ ρ+17 за дефолтом смуги) | `0` | ✅ Homeostasis (Здоровий Хаос) | `5 .. 31` (wire); `10 .. 62` (stored ×2) | Бали = метаболічна жвавість `m(delta_t)` (§4.3). 🔴 **Верхня межа тут стояла константою `45.0` до 2026-09-06 — при тому, що рядок ВИЩЕ вже був ρ-відносним [E.64].** Доповнення аномалії не може бути абсолютним, якщо сама аномалія рухається: код рахує `rho = (BASE_RHO + temp*0.2).clamp(10, 50)`, далі `rho + (CRITICAL_Z_MAX − BASE_RHO)`, тож стеля пробігає **27..67**, а `45.0` істинна рівно при 0 °C. У теплий день (temp 40 → ρ 36 → стеля 53) рядок оголошував аномалією те, що код класифікує гомеостазом — саме той хибний позитив, який E.64 і закривав |

### 4.3 Функція Нарахування Балів у Зоні Гомеостазу — Метаболічна Жвавість [E.63]

> **[E.63] Бали у гомеостазі задає МЕТАБОЛІЗМ (швидкість перезаряду EBFC), а НЕ Z.** Раніше магнітуда бралася з `|OPTIMAL_Z_TARGET − z|`, але paired-ensemble на реальному коді показав: Z-позиція у гомеостазі — хаотичний шум (std ≈ 4 GP) при ~нульовому корисному сигналі, а β-перетурбація від delta_t/vcap виходила економічно **нульова** (delta_t) / **інвертована** (vcap) — бо β НЕ рухає z-нерухому точку Лоренца (z_eq = ρ−1 залежить від ρ/temp, не від β). Розв'язання здоров'я від хаосу: Z лише класифікує стан (§4.2), а у гомеостазі бали = монотонна метаболічна жвавість. Присуд про сентинел «не виміряно» — врізка під кодом нижче; відкриті ноги (bench-калібрування `DELTA_T_FAST_S`/`SLOW_S`) — [`00_07` — E.63](00_07_Action_Plan_Tracker).

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

> ⚖️ **Сентинел «не виміряно» дає НУЛЬ балів, а не baseline — делегований присуд 2026-08-16 ([`00_07`](00_07_Action_Plan_Tracker) E.63; ухвалено під мандатом founder'а «виправляй все» + У-ВЕЙ і записано як делегований, [`00_05 §1`](00_05_AI_Native_Operating_Model)).** **Підстава:** мінт є твердженням про ДОВЕДЕНИЙ ріст, тож відсутність виміру мусить давати нуль, а не максимум — та сама планка, що вже стоїть на слешингу (хибний burn невідновний). **Форма:** `Attractor::DELTA_T_UNKNOWN_S = 0` плюс пара `status = 0, GP = 0`, якої доти не існувало: «зрив» і «не міряли» розрізняються за СТАТУСОМ, і жодного біта не додано. ⛔ **Не повертати посадкову точку на baseline:** `metabolic_health(60)` клампиться в `1.0` → `GP_HOMEO_MAX`, тобто «нейтральний» фолбек приземлявся рівно на максимум грошового виходу, а на кремнії це не край, а норма (до LSE/RTC bring-up `Wall_Seconds_Now()` віддає 0 щоцикла). **Ціна:** до того bring-up вузол не нараховує балів зовсім — чесна відмова замість вигаданого максимуму. Механіка ланцюга (`Wallet#credit!` → мінт → `leaf0` тижневого якоря), гілки посадки й мутаційний ліхтар — скіл `web3-pipeline` #21 і скіл `firmware` #8; найслабшої ланки присуд у записі не мав.

> **Wire vs Stored:** wire `growth_points` — 5-бітне `(5 + m·26).round.clamp(5, 31)`; backend `TelemetryUnpackerService` **лише декодує** wire-значення `(status_byte & 0x1F) * 2` → stored 10..62 — магнітуду з `delta_t` **НЕ** перераховує. Метаболічний DCI = структурний `check_metabolic_divergence!` (homeostasis→GP∈5..31 **або оголошений сентинел GP==0**, stress→GP==1; observational, як `check_z_divergence!`). 🔴 **Сентинельна гілка дописана 2026-09-06 і закрила ЖИВИЙ дефект:** пара `status = 0, GP = 0` — це ОГОЛОШЕНИЙ регістр ARCH.102 «я тут, але метаболізм не виміряно», який прошивка пакує окремою гілкою й власним коментарем каже, що бекенд розрізняє «зрив» від «не міряли» за СТАТУСОМ, не за балами. Гард робив рівно протилежне — читав пару як порушення смуги й інкрементував `TELEMETRY_FRAUD_DETECTED_TOTAL` на ЧЕСНІЙ відмові вузла (виміряно прямо). ⚠️ Дві половини одного присуду розійшлись тихо: ТОЧНА гілка (`expected_homeostasis_gp(0)` → 0) сентинел знала, СТРУКТУРНА ні. Ціна була б щоденною — `Wall_Seconds_Now()` віддає 0 до LSE/RTC bring-up (FW.49), тож на кремнії сентинел іде щоцикла. ⛔ Смугу при цьому НЕ розширено: `GP ∈ 1..4` при гомеостазі лишається порушенням (прошивка таких значень не пакує), а емісії пара не дає за побудовою — `emission_eligible_growth_points` множить нуль; точний `m(delta_t)`-перерахунок неможливий (wire=raw, GP=EMA), відкладено до **FW.2** — механіка й присуд у [`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA). Z (хаос) — для status-гейту + numeric-DCI (server-Z ≡ device-Z).

**Нарахування `growth_points` (wire) за `delta_t` — польова шкала перезаряду (монотонно, лінійно між FAST=600с і SLOW=7200с):**

| `delta_t` (с) | `m` | **Wire `growth_points`** (5-bit) | **Stored** (×2) | Стан метаболізму |
|---|---|---|---|---|
| ≤ 600 | 1.00 | **31** | 62 | Піковий — швидкий перезаряд |
| 1800 | 0.82 | **26** | 52 | Активний |
| 3900 | 0.50 | **18** | 36 | Помірний |
| 5400 | 0.27 | **12** | 24 | Млявий |
| ≥ 7200 | 0.00 | **5** | 10 | Мінімум (усе ще гомеостаз) |

> 📐 **Wire vs Stored:** Wire `growth_points` — 5-бітне поле, яке Soldier пакує у StatusByte; backend `TelemetryUnpackerService` робить `(status_byte & 0x1F) * 2` → Stored (`TelemetryLog#growth_points`). Калібрувальні `DELTA_T_FAST_S`/`DELTA_T_SLOW_S` — placeholder (bench, E.63); таблиця оновиться після зміряної recharge-кривої. **[E.63 (г), wire-rev2.1]** ВХІД формули (сатурований EMA-delta_t) їде у wire bytes 20..21 за контрактом «wire = вхід GP» → backend перевіряє цю таблицю **stateless байт-точно** (`Attractor.expected_homeostasis_gp` — byte-identical дзеркало цієї формули; observational до калібрування). Wire-дім — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security).

> ⛔ **Ці пороги рухає ЛИШЕ біологічна калібрація — ніколи бюджет радіо** (⚖️ 2026-09-22, делеговано: важіль (а) розвилки [`00_07`](00_07_Action_Plan_Tracker) ARCH.8 відхилено). Спокуса реальна: довший CCM-кадр штовхає робочу точку `delta_t` за `DELTA_T_SLOW_S`, і підняти стелю здається найдешевшим ліком. **Підстава перша, категоріальна:** слот чекає зміряної recharge-кривої, тож число з радіо-провенансом наступний прохід прочитає як зміряне — зворотний тест [`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap) «а звідки ти це знаєш?» дав би «бо кадр став довшим». **Друга, числова:** грошової лінії він не тримає й у найкращій установці — бали нараховуються НА ПАКЕТ, а частота пакетів упала разом із `delta_t` і лишається впалою (≈ −12 % SCC назавжди — число енергомоделі до зрізу пʼєзо, перерахунок 2026-09-26, доти −19 %; з 2026-09-29 CCM на моделі стоїть ПЕРЕД підлогою, тож дефолтний `--levers` ціни (а) не друкує, а під override, що кладе CCM за підлогу, — `ruby tools/firmware/tx_cadence_budget.rb --levers i_bq_quiescent_na=666` — друкує стелю (а) і саму цю структуру «частота пакетів не вертається», без відсотка SCC). Структурний аргумент від епохи моделі не залежить.

(Поза гомеостазом — гейт §4.2: `z < z_min` (2 за дефолтом) → wire 1 / stored 2 (стрес, absolute); `z > ρ+(z_max−BASE_RHO)` (дефолт `z_max` = `CRITICAL_Z_MAX`) → wire 0 (аномалія, [E.64] ρ-відносна; =45 при ρ=28, дзеркало `Attractor.anomaly_ceiling` §4 E.64-нота / код — НЕ hardcoded offset).)

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
| `11` | `3` | `vm_error` (mruby VM-збій → `BIO_STATUS_VM_ERROR=0x60`: status=3, gp=0, виживає mask `& 0x7F`; софт-фолт, **НЕ** tamper — SLASH-1 P0; фізичний tamper → PANIC_FLAG-канал, з HW.30 без пускача — пʼєзо зрізано, [`02_01 §6`](02_01_Hardware_Architecture_and_BOM)) |

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
| **Пакування статусу** | `BioContract.pack_status_byte(z_val, delta_t, local_rho, z_min, z_max)` — ДІМ формули (смугу дає C-міст з FW.8; дефолти — `CRITICAL_Z_MIN/MAX`) | `Attractor.pack_status_byte(z, temp, delta_t, critical_z_min:, critical_z_max:)` — дзеркало з 2026-09-06 [E.64]; зібране з уже наявних половин (`anomaly_ceiling` · `expected_homeostasis_gp` · `GP_STRESS` · `GP_UNMEASURED`), тож НОВИХ порогів не заведено. ⚠️ Годується СИРИМ `z` (`[3]`), не округленим `[0]` — прошивка класифікує саме ним. Споживач — `Hil::SoldierNode` (емуляція вузла); сам розпакувальник статус лише ДЕКОДУЄ |
| **Де використовується** | Пакується у `payload_byte` (byte 10 LoRa) | `TelemetryLog.z_value`, ZK-proof верифікація |

> **[SEC.11] Byte-Identical Initial State:** firmware та backend **деривують той самий `(x₀, y₀, z₀)`** через спільний HKDF/HMAC-SHA256 алгоритм з per-device `K_seed` (`SilkenNet::SeedDerivation` ↔ pure-C `silken_sha256.h` у firmware). DID більше не використовується як seed. Тому raw Z-значення тепер може порівнюватися чисельно (виміряний drift = **0 бітово**: ARM↔x86 — FW.55 QEMU byte-parity; mruby-VM↔CRuby — sweep N=10k, §7.1 Gate L; ⚠️ це про ядро КРОКУ — між кадрами паритет тримає ще й звуження стану до float32, нота «ТОЧНІСТЬ стану» нижче, [FW.66]). `check_z_divergence!` залишається категоричним за замовчанням; числовий tolerance band готовий до flip під feature-flag — Gate L закрито. ✅ **Парність доведено по ПОВНОМУ StatusByte з 2026-09-06** (`spec/services/silken_net/attractor_spec.rb`, 200-кейсовий fuzz проти СПРАВЖНЬОГО контракту через підпроцес `tools/firmware/contract_runner.rb`): доти звірялись лише біти 6..5, а GP-половина стояла «deferred to FW.2 — потрібне бекендне дзеркало `metabolic_health`», тоді як те дзеркало (`expected_homeostasis_gp`) приїхало ще з E.63 (г). Тобто відкладення пережило власний мотив, і саме ця дірка тримала `bin/forest_simulator` на `rand` замість обчислення ([`00_07`](00_07_Action_Plan_Tracker) E.64), лишаються гейти D/C/P/G (§7.1) + кремнієвий хвіст у FW.55 silicon-confirm дампі.

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
       │                  delta_t_s, vcap_mv,      │                          delta_t_s, vcap_mv)
       │                  z_min, z_max)            │
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
                                                   device_bio_status vs членство СИРОГО z?
                                                   (КАТЕГОРИЧНЕ за замовчанням; numeric
                                                    tolerance band під feature-flag, SEC.11)
                                                   tree.device_lorenz_bands (FW.8 — НАБІР смуг пристрою)
```

> 🔑 **Паритет — це й КІЛЬКІСТЬ кроків, не лише їхня арифметика [ARCH.102].** Panic-кадр пристрій шле з Фази 2, ДО кроку Фази 3, і `calculate_state` на ньому не кличе, тож сервер на panic-рядку теж не крокує, хвоста не персистить і DCI не судить (`TelemetryUnpackerService#step_lorenz_and_judge!`); наступний кадр продовжує ланцюг із хвоста ДО паніки. Сервер, що крокував би, стартував би наступний кадр зі стану, якого пристрій не мав, і ланцюги розходились би назавжди: сервер не ре-якориться, а cold-start пристрою його хвоста не скидає (§7.3). ⛔ «255 → 0», як для сентинела `0xFE`, паритету не відновлює — крок лишився б зайвим.

> 🔑 **Паритет — це й ТОЧНІСТЬ стану між кадрами [FW.66, 2026-10-05].** Солдат тримає стан у float32 (`float lorenz_x/y/z`, RTC DR16–DR18) і так само звужує cold-start (`*x0 = (float)dx`), а сам крок рахує в double (mruby). Сервер, що продовжував ланцюг у double, розходився з ним за 4–8 кадрів БЕЗ жодної втрати — хаос підсилює різницю округлення між кадрами, тож бітова рівність FW.55/Gate L, доведена для ядра кроку, на ланцюг не переходила: обидва прилади ланцюжать double з обох боків. Тому сервер звужує стартовий стан кадру й хвіст, що персиститься (`SilkenNet::Attractor.as_rtc_state`), а судить double-Z — так класифікує й пристрій; так само звужує HIL-двійник (`Hil::SoldierNode`). Пін — рівність float32-хвостів сервера й двійника біт у біт після кількох кадрів (`spec/lib/hil/soldier_node_spec.rb`; мутаційно перевірено за трьома осями: хвіст сервера · старт сервера · хвіст двійника). Дефект до правки відтворює `ruby tools/firmware/dci_chain_loss.rb server=double` (§7.3).

### 5.3 Метод `homeostatic?` (Backend-Only)

```ruby
# [FW.8 · ⚖️ 2026-09-29] Судить НАБОРОМ смуг, які може тримати пристрій:
# заводська 2.0/45.0 + утримувані + відкрита видача (облік — Downlink::ThresholdBand).
# 3-tier governance-ланцюг тут НЕ вживається: він відповідає на «що слати».
def check_z_divergence!(tree, attributes)
  raw_z = attributes[:lorenz_state_z]   # СИРИЙ z — ним класифікує прошивка
  device_bio_status = attributes[:bio_status]
  return if raw_z.nil? || device_bio_status.nil?

  bands = tree.device_lorenz_bands      # межі = x100 тіла 0x9A / 100.0, як на пристрої
  device_in_band = device_bio_status == :homeostasis
  # [E.64] ρ-відносна стеля — in_lorenz_band?(z, band, temp)
  matching = bands.select { |band| in_lorenz_band?(raw_z, band, temp) == device_in_band }
  # matching.empty?            → recovery (ARCH.41) або fraud
  # matching.size < bands.size → доказ смуги (Downlink::ThresholdBand.record_evidence!)
end
```

> 🔴 **[FW.8] `check_z_divergence!` судить НАБОРОМ смуг, які може тримати пристрій (`tree.device_lorenz_bands`), а НЕ 3-рівневим governance-ланцюгом.** ⛔ Не приписувати DCI governance-ланцюг: до 2026-09-27 per-species значення не доходили до `bio_status` ЖОДНИМ шляхом — `calculate_state` порогів не приймав, а C-шар `lorenz_thresholds.h` був write-only round-trip Flash→RAM→Flash. Тепер контракт їх приймає ([`00_07`](00_07_Action_Plan_Tracker) FW.8), але глобалки, що його годують, міняють лише парсер `0x9A` і boot-restore — обидва під `FW8_PARSER_ENABLED = 0`, тож бойова збірка досі судить 2.0/45.0, а фліп вмикає доставку й споживання разом. Доти (розведення ролей 2026-09-05) DCI судив цією однією смугою, бо сервер, що судив per-species, порівнював не два обчислення, а дві КОНФІГУРАЦІЇ, і на чесному дереві це давало категоричний mismatch; як бекенд дізнається смугу після фліпу — присуд ↓. 📏 Виміряно на реальному cold-start (5 000 прогонів, `initial_state` x₀,y₀,z₀ ∈ `[-1,1]` — частоти нижче належать САМЕ цій популяції старту): MIN-бік `z ∈ [2, family_min)` — 0.14 %, **MAX-бік `z ∈ (стеля_родини, стеля_пристрою]` — 1.4 %** (тепла погода штовхає Z саме туди); `z < 2` не трапився жодного разу — на cold-start. ⊕ **Теплий ланцюг дає інші числа й інший висновок** (📏 2026-09-29, справжній контракт, `tools/firmware/lorenz_zone_frequency.rb`): stress на ЗАВОДСЬКІЙ смузі — 0.022 % циклів за −25 °C … 0–1 подія на 180 000 циклів за +20…+30 °C (роздільність вибірки), тобто рідкісний, а НЕ недосяжний (ρ-clamp обмежує рівновагу, не траєкторію), а MIN-зона родин відвідується морозом у рази частіше, ніж казав cold-start, а теплом — співмірно або рідше: `z < 5` — 0.03–0.83 % (cold-start 0.14 %: до ~6× холодом, ~5× рідше за +30 °C), `z < 8` — 0.37–4.2 % (cold-start 0.24 %: до ~17× холодом) (⚖️ «посуха» в блоці присуду нижче); MAX-зона дуба (стеля родини ρ + 12 проти заводської ρ + 17) — 1.6–3.5 % циклів, спекою більше (cold-start казав 1.4 %). У зонах `2 ≤ z < 5` · `2 ≤ z < 8` · MAX заводська смуга дає гомеостаз 5–31 wire-бал там, де смуга родини дає stress 1 чи anomaly 0 (ціна поправки 7 ↓). ⊕ **Наслідок розгалужувався за станом пакета, і обидва рукави тихі:** на **cold-start** (`previous.nil?`) — прямий `TELEMETRY_FRAUD_DETECTED_TOTAL` із P0-правилом на ЧЕСНОМУ дереві, бо `try_time_sync_recovery` там гейтований `!cold_start_flag`; на **теплому** — той самий recovery перебирав epoch_day-кандидати тими САМИМИ порогами, знаходив «збіг» на чужій добі, ставив `time_unsynced_fallback` і слав зайвий `CMD_TIME_SYNC` вузлові, чий час нормальний (тобто платив ще й downlink-енергією). ⚖️ **Ціна названа:** у MAX-смузі підроблений `status_byte = homeostasis` більше не ловиться цим чеком — обмін свідомий, бо те покриття ловило чесні пакети РАЗОМ із підробленими й розрізнити їх не могло. Governance-ланцюг лишається домом питання «**що слати**» (видача — `Downlink::ThresholdBand`, ENV-гейт, що вмикається після фліпу), ⊕ **І біо-гілку на Z ЗНЯТО тим самим присудом** (⚖️ 2026-09-05, E.64 варіант A): `AlertDispatchService` більше не піднімає `attractor_destabilised`, бо той був вердиктом про ЗДОРОВʼЯ, виведеним із Z, тобто заперечував «Z = DCI-only» у коді. Посуха тепер судиться лише ПРИСТРІЙНИМ status-гейтом — ⚠️ і він живий, хоч і рідкісний: на теплому ланцюзі stress настає й на заводській смузі (📏 ↑), тож перил посухи МАЄ рідкісного авто-писача (`bio_status_stress?` → `severe_drought`, [`00_04`](00_04_Nature_as_a_Service_Contracts)) на Z-сигналі, який E.64 не визнав оракулом здоровʼя. Обмін 2026-09-05 стоїть без заміни (окремо не ратифіковано): біо-питання «дерево поза своєю нормою» вимірювачем не покрите, і здоровʼя чекає прямих сигналів. 🔴 Фліп FW.8 з видачею смуг родин підсилить цю гілку на порядки (MIN-зона ↑) — ⚖️ «посуха» в блоці присуду нижче. Стан → [`00_07`](00_07_Action_Plan_Tracker) FW.8.

> ⚖️ **ПРИСУД founder 2026-09-29 («FW.8 так» — ратифіковано ПОДАНЕ, за рекомендацією): як бекенд дізнається смугу, ЧИННУ на пристрої, і яку смугу взагалі дозволено слати — (в) + гард «лише звуження».** Ефір підтвердження смуги не несе: downlink-ревізія ([`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)) uplink-байтів не додала. Опції, рекомендація, підстава, гард, ціна й найслабша ланка нижче — **ратифікований текст дослівно** (змінено лише форму рефів і розбивку на абзаци); що змінило застосування — окремим блоком після нього.
>
> **Опції:** **(а) луна в аплінку** — HW.30 звільнив байт `acoustic_events` (крім сентинела `0xFE`), але долю звільнених слотів founder відклав до CCM-wire-фіналу ([`00_07` FW.59](00_07_Action_Plan_Tracker), 07-20), тож (а) зайняла б слот наперед присуду; **(б) підтвердження Королеви** — міряє ДОСТАВКУ, не застосування: MIC-відмова, порвана пара KV `0x10`/`0x11` чи re-provision зі свіжим журналом лишають пристрій на дефолтах, і DCI знову судив би дві конфігурації; **(в) самосвідчення статусу** — у зоні, де смуга дефолту й надіслана смуга дають РІЗНИЙ категоричний статус, сам `bio_status` пакета каже, котра смуга чинна. **Рекомендація — (в) + гард «лише звуження».**
>
> **Підстава:** нуль байтів і нуль прошивки; той самий рід доказу, що вже закриває `0x9E` — застосування доводить наступний аплінк (там — MIC новим ключем, тут — статус у зоні розбіжності); доказ ловить і ВІДКАТ (порвана пара, re-provision), що дає повторну видачу того ж кадру за чинною семантикою at-least-once ([`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)); не залежить від того, коли на кремнії ввімкнуть `FW8_PARSER_ENABLED`. DCI до доказу судить за НАБОРОМ кандидатів {дефолт, надіслана}: поза зоною розбіжності вони збігаються, тож перевірка точна; у зоні — приймає статус будь-якого кандидата, що не слабше за сьогоднішній DCI (ціна розведення ролей 2026-09-05 ↑ — у MAX-смузі він підробленого `homeostasis` і так не ловить).
>
> **Гард:** надіслана смуга мусить лежати в межах дефолту пристрою (2.0 / 45.0) — тоді статус вужчої смуги в зоні розбіжності дає не більше балів, ніж дефолтний (`pack_status_byte`: stress 1 · anomaly 0 проти гомеостазу ≥ 5), з ОДНИМ кутом: коли метаболізм не виміряно (сентинел ARCH.102), гомеостаз дає 0, а stress — 1, тож набір-кандидатів дає нечесному вузлу щонайбільше 1 бал на пакет лише в цьому куті; ⊕ без гарда смуга є тихим грошовим важелем: ширша — рідше «аномалія» — більше балів, і DCI цього не бачить, бо пристрій справді рахує з нею, а межі родини сьогодні валідовано лише на `min < max` (пише `super_admin`, кластерні оверрайди — ніхто).
>
> **Ціна:** до першого пакета в зоні розбіжності бекенд не знає, котра смуга чинна, — а зону відвідують рідко: MIN-бік 0.14 % (родина 5.0) · 0.24 % (8.0) прогонів, MAX-бік 1.4 % (📏 ↑), тобто для сосни (лише MIN-бік) — тижні; ця невизначеність нічого не коштує поза зоною, а в зоні коштує щонайбільше 1 бал на пакет у куті сентинела. Смугу, ширшу за дефолт, заборонено слати зовсім — вид, якому вона потрібна, вимагатиме зміни дефолту прошивки, тобто присуду, а не оверрайду.
>
> **Найслабша ланка:** частоти зони виміряно на cold-start-симуляції, не на живому дереві; якщо реальне Z сидить глибоко в гомеостазі, доказ може не прийти місяцями — тоді лишається (а) як прискорювач, коли FW.59 розсудить слот.
>
> 🤖 **Застосовано 2026-09-29 — механізм і сім поправок до поданого** (подане вище не змінено). Поправки 1–6 змінюють МЕХАНІЗМ; 7 змінює ЦІНУ, тож її, ціну стелі поправки 3 і наслідок «посуха» ↓ ПОВЕРНУТО founder-у ⚖️ ([`00_07` FW.8](00_07_Action_Plan_Tracker)). Поправки 6 і 7, «посуху» й хибні числа в ній я спершу не назвав — їх знайшли два адверсарні ревʼю того ж дня.
>
> ⚫ **2026-10-06 — FW.8 поглинуто гілкою (Б)** (founder: «FW.8 під (Б) — рекомендація так»): смуги на пристрої CCM-ери не буде — пороги родин і сезонів переїжджають на сервер, де їх судять прямі сигнали (нога E.64), пристроєву машинерію FW.8 знімає реалізація (Б) ([`00_07`](00_07_Action_Plan_Tracker) FW.66), тож три повернення нижче закрито для поля (їхній предмет — смуга CCM-ери, якої не буде, а ECB-ера в поле не йде); розділ лишається історією ECB-ери. **Підстава:** уточнена (Б) рахує вердикти на сервері, а пристрій повідомляє лише валідність виміру, тож смуга на пристрої не має споживача, і вся доказова машинерія — що сервер не знав, яку смугу тримає пристрій, — втрачає питання. **Ціна:** host-done тракт FW.8 стає мертвим і знімається; локальних рішень за порогами пристрій не ухвалює. **Найслабша ланка:** автономна дія на пристрої без звʼязку вимагатиме відбудувати downlink порогів — рамка адресних CCM-команд лишається (нею живе `0x9E`).
>
> **Механізм застосування.** Кандидати — заводська смуга (завжди) плюс утримувані (`trees.lorenz_band_held`: доведена й заміщені видачі, доки доказ їх не відкине) і відкрита видача (`lorenz_band_pending` — навіть спростована, бо її кадр ще може долетіти). Пакет чесний, якщо його статус дає бодай один кандидат. Пакет, що відкинув частину кандидатів, — доказ: видача, яку статус підтвердив ОДНУ, стає утримуваною; відкинута утримувана виходить із набору, і найближчий poll видає бажану смугу знову; відкинута відкрита видача після вікна доставки — спростування. Доказом не є `vm_error` і пакет із невідомим часом — той міг прийти з іншого ланцюга Лоренца. Гард перевіряє ще й СКЛАДЕНИЙ ланцюг перед видачею (валідації родини й оверрайду кожна бачить лише свою половину; діапазон — до пакування, бо `pack("s<")` число поза int16 мовчки загортає).
> 1. **Кандидат — МНОЖИНА, не «дефолт + надіслана».** Друга видача до доказу першої (виправлення одруку в довіднику) лишала б поза набором смугу, чий кадр МІГ долетіти першим, і DCI виписав би фрод чесному вузлу — рівно клас FW.8. Тож заміщена відкрита видача переходить у `held`.
> 2. **`0x9A` у драбині poll — НИЖЧЕ OTA-hint** (подане казало лише «після `0x9E`»). Hint живе до `fw=`, тобто лише поки Королева сама качає образ, а видача смуги відкрита тижнями, бо доказ рідкісний; вище за hint вона морила б OTA — голодування, яке я на старті застосування збирався лікувати паузою. **Пауза — доповнення, не поправка:** перевидача раз на `RESERVE_INTERVAL` (доба) тим самим кадром; кадр живе в черзі Королеви, доки не витратить `SOLDIER_CMD_SHOT_BUDGET` пострілів у голоси цілі або доки його не витіснять новіші (`SOLDIER_CMD_QUEUE_SLOTS`, найдавніший першим; кадрів смуги — щонайбільше один за poll), тож частіша перевидача довше тримала б кадр у черзі (освіження захищає від витіснення), але забирала б слоти в кадрів інших дерев; доба — компроміс, не вимір.
> 3. **Польовий аудит лічить спростування, а не «N видач без доказу».** Доказ рідкісний, тож лічба видач спрацьовувала б на кожному дереві, яке просто не відвідало зону. Лічаться пакети зі СТАРОЮ смугою після вікна доставки (`DELIVERY_WINDOW` 72 год: вузол виходить в ефір за енергією, до ~18 год між циклами, а нову смугу показує лише аплінк після того, за яким Королева вистрілила кадр); на третьому (`STALE_ALERT_PACKETS`) — per-tree `field_audit` `lorenz_band_not_applied`, чий текст каже «не доставлено або не застосовано»: вікно не виключає ТРАНСПОРТУ (під OTA-кампанією `0x9A` не видається, черга Королеви витісняє кадри). Оператора він не штрафує (`field_audit` поза `critical_unmaintained?`), а доказ застосування знімає його машинно: твердження — про сигнал, не про світ. ⚠️ **Стеля — ціна, яку я спершу прийняв сам, тож її повернуто ⚖️:** per-tree `field_audit` — ОДИН квиток на дерево (дедуп `(tree, status)`), тож цей ключ ділить слот із `tree_silent`, а сторож тиші читає будь-який per-tree аудит як «уже ескальовано»: тиша дерева з активним квитком смуги окремим алертом не з'явиться, доки людина не закриє квиток смуги. Обидва ведуть до одного виїзду до вузла, а резолвер кожного ключа знімає лише свій; подія перегляду — per-tree причина, що вимагає ІНШОЇ дії людини, ніж виїзд (тоді розводити per-tree `field_audit` за `message_key` — індекс, валідацію, пошук активного (`active_tree_field_audit_for`) і сторож тиші разом, як ARCH.110 зробив для кластерного рівня; клас — скіл `backend` #79).
> 4. **Перевидача тим самим кадром законна, лише поки ключ і лічильник не рушили.** Re-provision обнуляє DLFC у новій епосі, тож лічильник може знову дійти до числа видачі, і перевидача під новим ключем повторила б нонс CCM з іншим тілом; видача тому памʼятає епоху ключа, а зсув лічильника (ротація, DR-підйом) дає нову видачу.
> 5. **Членство судить СИРИЙ z, не `z_value`.** Прошивка класифікує сирим z, а `z_value` округлено до 4 знаків для зберігання: на межі смуги це розводило обчислення на порядки грубше за останній біт, який лікувала подана нога «квантизація смуги як на пристрої». Виправлено обидва операнди нерівності разом — половина лишила б більшу похибку поруч із виправленою меншою.
> 6. **Відкат ПІСЛЯ доказу дає нову видачу, а не «той самий кадр»** (подане: «повторну видачу того ж кадру»). Доведена видача вже записала свій DLFC у журнал Солдата (`0x12`), тож той самий кадр при відкаті він відкинув би як повтор, а після re-provision кадр під старим ключем не відкриється взагалі. «Той самий кадр» лишився правдою для ВІДКРИТОЇ видачі: доки її не доведено, Солдат її DLFC не записав (запис — після ефекту).
> 7. **Заводська смуга лишається кандидатом і ПІСЛЯ доказу** (подане: «DCI до доказу судить за НАБОРОМ кандидатів {дефолт, надіслана}»). Підстава: re-provision зі свіжим журналом чи порвана пара повертають чесний вузол на заводську без нашого кадру, і без дефолта в наборі він діставав би в зоні інкремент DCI-розбіжності (до 2026-10-05 — фрод із P0, FW.66) — рівно клас FW.8. **Ціна змінилась:** звуження обовʼязкове лише для чесного вузла — вузол, що після доказу показує в зоні заводський статус, отримує бали за заводською смугою, доки відкат → нова видача → вікно доставки → три спростування не дадуть польового аудиту; невизначеність «до першого пакета в зоні» для нього стає постійною й видимою лише через аудит. І ціна в зоні — не «щонайбільше 1 бал» Гарда: той рахував ПРОТИЛЕЖНИЙ напрямок (вузол, що бере статус вужчої смуги), а тут вузол лишає заводський статус і отримує гомеостаз 5–31 wire-бал (×2 у збереженні) там, де вужча смуга дала б stress 1 (MIN) чи anomaly 0 (MAX), — в ОБОХ зонах: дуб ≈ 3.6–5.8 % циклів теплого ланцюга, сосна (лише MIN) — 0.03–0.80 % (📏 ↑). Доки метаболізм не міряно (сентинел ARCH.102 — кожен цикл до RTC-підйому FW.49), гомеостаз дає 0, тож ціна латентна, а на MIN-боці навіть обернена.
>
> 🔴 **Незацінений наслідок — «посуха»** (знайшли адверсарні ревʼю; гард міряв лише БАЛИ). `AlertDispatchService` → `bio_status_stress?` піднімає medium `severe_drought`, а на ньому `EmergencyResponseService` просить полив 7200 с серіями по 3600 с: клапан, що серії не витримує (сід — 300 с), недоступний чи відсутній, дає CRITICAL `emergency_response_undeliverable` — критичний лист клієнтові й `under_threat` у його звіті, без машинного резолвера, а придатний — лише ЗАПИСАНИЙ полив, якого не було (Королева квитує токен луною, ACTION не виконуючи, [`03_02 §6`](03_02_Queen_Gateway_Firmware)); евристика `stress_index` на тому ж статусі дає дереву-добі 0.6, тобто знімає з `health_index` кластера 0.6/N за кожне таке дерево. Усе це — без гейта, з першим польовим вузлом. За гейтами — утримання ВСІХ виплат кластера, зокрема пожежних (`insurance_payout_worker`, kill-switch оракула вимкнено), і, з dClimate, CRITICAL кластерний `field_audit` `non_fire_peril`; платити посуха не може — писача `:verified` для неї немає. Гілка жива **вже сьогодні**, рідко й холодом (stress на заводській смузі — 0.022 % циклів за −25 °C … 0–1 подія на 180 000 циклів за +20…+30 °C (роздільність вибірки), 📏 ↑ — «недосяжна» стояло на самому cold-start), а фліп FW.8 з видачею смуг родин підсилить її на порядки (`z < 8` для дуба — 0.37–4.2 % циклів; ⊕ 2026-10-06: цього фліпу не буде — FW.8 ⚫, гілку знімає реалізація (Б)). І частота росте з МОРОЗОМ, а не зі спекою: сигнал, названий посухою, свідчить про холод — температурне змішування E.64 у найпрямішій формі. Тобто це Z-похідний вердикт про посуху на порогах-заповнювачах — те, що E.64 зняв на боці сервера з підставою «пороги в сідах — заповнювач, не вимір», свідомо лишивши пристрійний гейт домом посухи; ⚖️ — [`00_07` FW.8](00_07_Action_Plan_Tracker).
>
> ⊕ Той самий прохід спростував ADR прошивки: `lorenz_thresholds.h` лікував порвану пару ключів «наступним daily re-send», а щоденного перенадсилання бекенд не мав ніколи. Тепер лікує видача за доказом, і ADR переписано.
>
> **Порядок вмикання** (⚫ 2026-10-06 — історія ECB-ери: повернення ↑ закрито не розсудом, а поглинанням FW.8 гілкою (Б), тож цей абзац дозволу НЕ дає — ні фліпу, ні ENV, ⚫-врізка вище). ENV `FW8_THRESHOLDS_DOWNLINK_ENABLED` — ПІСЛЯ прошивкового фліпу `FW8_PARSER_ENABLED 1`, не до, і лише коли всі три повернення ⚖️ ↑ розсуджено: вузол без парсера смуги не прийме, і після вікна кожен його пакет зі старою смугою лічиться спростуванням. ⚠️ Гейт глобальний, а C-прошивку OTA не оновлюють: змішаний флот (частина вузлів без парсера) дасть польові аудити саме на них — per-device гейт знадобиться з першим змішаним флотом (стелю названо, не будовано). Параметри 24 год · 72 год · 3 пакети — інженерні, не виміряні; калібрують стенд і поле. Носії — `spec/services/downlink/threshold_band_spec.rb`, `pending_queue_service_spec` («0x9A смуга Лоренца») і `telemetry_unpacker_service_spec` («з виданою смугою», «СИРИМ z»); піни перевірено мутаціями.

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

  mrb_value args[9];
  args[0] = mrb_float_value(mrb, (double)x_prev);
  args[1] = mrb_float_value(mrb, (double)y_prev);
  args[2] = mrb_float_value(mrb, (double)z_prev);
  args[3] = mrb_fixnum_value((int8_t)lora_payload[6]); // Temp
  args[4] = mrb_fixnum_value(lora_payload[7]);          // Acoustic
  args[5] = mrb_fixnum_value(delta_t_s);                // [E.63] EMA DR10 → growth_points §4.3
  args[6] = mrb_fixnum_value(vcap_mv);                  // [E.63] EMA DR12 (reserved; не на Z)
  double band[2];                                       // [FW.8] смуга, ЧИННА на пристрої
  Lorenz_Band_Args(lorenz_z_min_x100, lorenz_z_max_x100, band); // One-Home: lorenz_thresholds.h
  args[7] = mrb_float_value(mrb, band[0]);              // z_min
  args[8] = mrb_float_value(mrb, band[1]);              // z_max

  mrb_value result = mrb_funcall_argv(mrb, mrb_top_self(mrb),
      mrb_intern_lit(mrb, "calculate_state"), 9, args);
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
                    vcap_mv   = SilkenNet::Attractor::NOMINAL_VCAP_MV,
                    z_min     = SilkenNet::BioContract::CRITICAL_Z_MIN,
                    z_max     = SilkenNet::BioContract::CRITICAL_Z_MAX)
  SilkenNet::BioContract.evaluate_and_pack(x_prev, y_prev, z_prev,
                                           temp, acoustic, delta_t_s, vcap_mv, z_min, z_max)
end
```

> ⛔ **ABI-підлога контракту (FW.8, 2026-09-27): арність `calculate_state` ≥ 9.** C-міст передає 9 аргументів, а C-прошивку OTA не оновлює (§6.2), тож OTA-контракт із меншою арністю впаде `ArgumentError` → VM_ERROR ×3 → SEC.20 erase і відкат до вбудованого байткоду. Пін — `firmware/test/test_bytecode_vm.c` (CI `tools/firmware/run_bytecode_vm.sh`): контракт на 7 параметрів там падає «given 9, expected 5» (мутаційно перевірено). Смуга в бойовій збірці — дефолти 2.0/45.0: її міняють лише парсер `0x9A` і boot-restore, обидва під `FW8_PARSER_ENABLED` ([`00_07`](00_07_Action_Plan_Tracker) FW.8). ⊕ RAM-ціна двох доданих аргументів — з байткоду: за `MRB_NO_BOXING` float їде значенням, тож float'ів виклик у heap не кладе (висновок із конфігу збірки; фазу завантаження окремо не міряли).

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
5. Soldier збирає chunks у `ota_buffer`, за ними — 7 блоків печатки `[0x9B]` (FW.23); APPLY лише після CRC32 (ISO 3309) → KPUB → `RITE` → Ed25519 → свіжість версії SEC.20 ([`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning))
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

> ⚫ **2026-10-05 — поглинуто гілкою (Б) FW.66:** у CCM-ері z на пристрої немає, тож числовій DCI нічого порівнювати; гейти D/C/P/G нижче не виконуються, код знімається в реалізації (Б). Розділ лишається історією рішення.


**Контекст:** SEC.11 закрив BLOCKER-2 і відкрив технічну можливість використовувати **числовий** DCI-перевірний крок (`|z − device_z| < ε`, z — сирий; нота під «Висновком Gate L») замість суто **категоричного** enum-match'у. Числова перевірка значно потужніша: дозволяє ловити replay-атаки з правильним StatusByte, але неправильною Z-magnitude (наприклад, attacker викликав легітимний enum через clamp-логіку, але справжня траєкторія розійшлася). Категорична перевірка пропускає такі сценарії.

**Стан коду (✅ ready, awaits lab data):** Feature-flag реалізовано у [`TelemetryUnpackerService#check_z_divergence!`](04_02_Business_Logic_and_Services) (2026-05-02). У production-середовищі branch неактивний — це навмисно. Активація через Kamal env, **без code change та без redeploy** контейнера.

**ENV-контракт:**

| ENV | Default | Тип | Семантика |
|-----|---------|-----|-----------|
| `DCI_NUMERIC_TOLERANCE` (до 2026-10-04 — з префіксом `GAIA_`, знятим разом із ретированим брендом, [`00_02 §5`](00_02_Academic_Integration_and_IP); у прод не пушився — Gate P ще попереду) | unset → `false` | Boolean (`true`/`1`/`yes`) | Вмикає numeric branch **on top of** категоричної перевірки (не замінює). Категоричний enum-match завжди виконується першим. |
| `DCI_NUMERIC_EPSILON` | `0.001` (constant `TelemetryUnpackerService::DEFAULT_DCI_EPSILON`) | Float (parsed via `Float()`) | Tolerance threshold. Malformed/non-numeric value → graceful fallback до DEFAULT_DCI_EPSILON + `Rails.logger.warn`. |

**Гейт активації — `device_z` має бути в payload: ✅ wire-дім існує (FW.2 wire-rev2, 2026-06-12).**

Numeric branch виконується **лише** коли `attributes[:device_z]` присутній. Транзитний 21B ECB-пакет raw Z **не несе** — фірмварний `bio_contract.rb#calculate_state` повертає тільки `status_byte = [PanicFlag:1 | Status:2 | GrowthPoints:5]` (FW.29-PACK). **FW.2 wire-rev2.1** (30-байтний CCM-пакет, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) + wire-budget ledger) виділив `device_z` bytes 16..17 шифртексту: **u16 фіксована точка z×512 (q=2⁻⁹)** — похибка квантування ≤ 0.00098 строго менша за ε=0.001 (запас тонкий, але Gate L дав drift=0, тож сумарна |Δ| = сама квантизація); діапазон 0..127.99 без сатурації — ⚠️ і запас міряється **проти самого z, не проти стелі**, та ще й проти ПРАВИЛЬНОГО z: пакується **КІНЦЕВЕ** значення після 250 ітерацій (`Pack_FW2_Device_Z(lorenz_z, …)`), і його зміряний максимум на обох клампах (ρ=50 **І** σ=30, 1 500 cold-start зерен) — **83.8**, тобто запас ≈44. ⛔ Не виводити запас ані з E.64-стелі (вона при ρ_max=50 дорівнює 67 — тобто МЕНША за саму величину, яку мала б обмежувати), ані з максимуму **УЗДОВЖ** траєкторії (той на тих самих клампах доходить до ~125 і лишив би запас ≈3): `generate_trajectory` на дріт не їде, але імʼя «траєкторія» тут живе поруч і плутається. Рецепт обох вимірів — шапка `SilkenNet::Attractor#iterate_lorenz`; **сентинель `0xFFFF` = «Лоренц цього циклу не рахувався»** (VM_ERROR чи непровіжинений seed: прошивка шле його за `lorenz_state_valid = 0`; у grace-вікні ARCH.41-C телеметрія не летить — hello `0x56`) → атрибут відсутній, branch чесно пропускається. Pack — `Pack_FW2_Device_Z(lorenz_z, lorenz_state_valid)` (`lora_ccm.h`); unpack + e2e — `process_ccm_chunk` ("FW.2 CCM path" спеки). Покриття ≥95% (Gate D) досяжне, бо device_z їде у КОЖНОМУ telemetry-кадрі (сентинель лише у grace-вікнах). Альтернативи (ML2 snapshot-варіант / server-side surrogate) лишаються в історії як відкинуті — wire-дім дешевший і дає повне покриття.

Branch інертний до фліпу `FW2_CCM_ENABLED` + `TELEMETRY_CCM_ENABLED` (+ ENV-флаги вище) — код staged у production без поведінкової зміни.

**Gate L — вимірювання drift ✅ machine-closed (2026-06-11, без заліза):**

Оригінальний протокол (N=10k векторів → x86 vs прошитий STM32 через SWD/RTT) писався до появи QEMU-лейну FW.55. Розкладання DCI-ланцюга на плечі закрило його софтом:

| Плече | Метод | Результат |
|-------|-------|-----------|
| mruby-ARM32 (девайс) ↔ mruby-x86 | FW.55 QEMU byte-parity ([`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)): той самий байткод на реальному M4 ISA-шляху, 64 зчеплені кейси (хаос ампліфікує будь-який ULP) | **бітова рівність** (кожен CI-прогін) |
| mruby-VM ↔ CRuby (справжній контракт) | `tools/firmware/dci_epsilon_sweep.sh` — **N=10 000 зчеплених кейсів** (генератор бітово дзеркалить `parity_core.h`; кожна сторона ланцюжить власний хвіст у double = модель warm-chaining DCI без float32-звуження між кадрами (його тримає нота FW.66 у §5); CRuby-сторона = `bio_contract.rb` напряму, FW.57-ізоляція) | **бітова рівність 10000/10000**, payload 0 розбіжностей, max\|Δz\| = 0 |
| CRuby-контракт ↔ backend `Attractor` | 200-кейсовий fuzz `attractor_spec` (FW.57 F4, постійний CI-гейт) | категорично + числово збігається |

**Висновок Gate L:** за поточної pinned-конфігурації (mruby 4.0.0, явний `MRB_NO_BOXING` + `MRB_CONSTRAINED_BASELINE_PROFILE` — [`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA)) увесь ланцюг device-mruby → server-CRuby **бітово точний**; виміряний drift = 0, ε=0.001 — чиста страховка від silicon-сюрпризів і майбутніх конфіг-дрейфів (правило кроку 6 «ε < 0.0001 → ставимо 0.001 conservative» виконано з нескінченним запасом). Історичне спостереження «~1e-14» (перший VM-прогін 2026-06-04, один кейс) **superseded** — не відтворюється: той самий кейс сьогодні бітово рівний (sweep, кейс 0). Кремнієвий хвіст Gate L = той самий one-command FW.55 silicon-confirm дамп (SWD, закриває FW.7/FW.19/FW.31 разом). Sweep — відтворюваний інструмент, не CI-гейт: переганяти після змін контракту/mruby-конфігурації.

> ⚠️ **ε живе на КВАНТІ дроту, а не на обчислювальному дрейфі [FW.31, 2026-10-05].** `device_z` квантовано q = 2⁻⁹ round-to-nearest (`firmware/common/lora_ccm.h`, `Pack_FW2_Device_Z`: похибка ≤ q/2 = 0.00098), тож ε = 0.001 стоїть лише на 2.2·10⁻⁵ над квантом; «нескінченний запас» вище — про mruby ⟷ CRuby, не про дріт. Тому дрейф судиться від СИРОГО z (`lorenz_state_z`), як і членство: `z_value` (round 4, ще ±0.00005) виносив за ε 0.36 % чесних кадрів (max 0.001028), тобто ≈ 5 % хибного fraud на дерево-добу з дня фліпу. Виправлено того ж дня; пін — `spec/services/telemetry_unpacker_service_spec.rb` («judges drift by the RAW z»). Опускати ε нижче q/2 не можна за побудовою.

**Rollout gates (порядок активації):**

1. **Gate L (Lab):** ✅ див. вище — drift виміряно (=0), ε=0.001 підтверджено conservative; кремнієвий хвіст їде з FW.55-дампом.
2. **Gate D (Device coverage):** `device_z` доступний у ≥ 95% telemetry packets. ✅ Wire-дім готовий (FW.2 wire-rev2, bytes 16..17 + сентинель — блок вище); вимірювання 95% — після CCM-фліпу. Прилад — `silkennet_telemetry_ccm_device_z_total{carried}` (2026-09-28; доти канон називав «decrypt_ok vs сентинель-частку», а лічильника сентинелів не було): частка `carried="true"` серед усіх кадрів, що дійшли до розвилки, без panic-кадрів (DCI їх не судить). Стара форма «1 − сентинели / `decrypt_ok`» завищила б покриття: `decrypt_ok` інкрементується ДО перевірки шуму сенсора, тож відкинуті кадри сиділи б у знаменнику, але ніколи не в сентинелях.
3. **Gate C (Canary):** Активація в `WEB3_STRICT_MODE=false` staging кластері на 24 год. Watch `silkennet_dci_numeric_mismatch_total` (є з 2026-09-28, реєстр [`06_03`](06_03_Prometheus_Observability); доти канон називав `…_rejections_total`, якого не було, а числова гілка била лише в спільний `fraud_detected`, куди пишуть вісім місць; «rejection» — неправда й за змістом: гілка лише сигналить, рядок персиститься). ⚠️ Гілка стоїть ДО відновлення ARCH.41, тож лічильник бачить і кадри, які далі врятує `time_unsynced_fallback` — канарку читати разом із ним. Очікувано: 0 mismatches (бо ε > max observed drift у Gate L). Будь-яке non-zero rejection → analiza root cause (seed corruption? RTC drift? overflow?) перед production.
4. **Gate P (Production canary):** Single Genesis cluster, `DCI_NUMERIC_TOLERANCE=true` через `kamal env push`, моніторинг 72 год.
5. **Gate G (Global):** Flip всіх production кластерів.

⚠️ **Передумова всіх п'яти — якір кадру ([`00_07`](00_07_Action_Plan_Tracker) FW.66) і межа повтору (SEC.40)** (⊕ 2026-10-06: якір кадру — гілка (А), не обрана; під ратифікованою (Б) числова DCI FW.31 ⚫, тож ці гейти втрачають предмет — врізка присудів FW.66, §7.3)**:** на теплому ланцюгу перший же розсинхрон (§7.3) дає числову розбіжність на кожному наступному кадрі, а під якорем повтор проходить печатку точно.

**Rollback procedure:**

```bash
# Kamal env push без redeploy:
kamal env push --secret DCI_NUMERIC_TOLERANCE=false
# АБО видалити з .kamal/secrets-common, тоді next deploy картки залишиться без флагу
```

Жоден код-rollback не потрібен — feature-flag перетворює numeric branch на no-op. Категорична перевірка продовжує захищати DCI.

**Side effects після flip:**

- Fraud detection стає **числовим**: ловить replay-атаки з правильним enum, неправильним magnitude — як описано на початку §7.1.
- `silkennet_dci_numeric_mismatch_total` росте на ε-межі (колонки `fraud_flagged` у `TelemetryLog` немає, а частка ~0.001–0.01 % — оцінка без виміру; квант дроту q/2 від сирого z ε не перетинає, нота під «Висновком Gate L») — це **acceptable noise**: гілка лише сигналить, автоматичного slashing не дає.
- Mint pipeline ([`05_02`](05_02_Proof_of_Growth_Pipeline)) НЕ блокується numeric divergence — це лише signal для AML/risk layer.

**Specs (вже в коді):**

`spec/services/telemetry_unpacker_service_spec.rb` describe `[FW.31] numeric tolerance band` — 6 examples:
1. toggle off (default) → numeric branch inert, тільки категорична перевірка
2. within ε → silent pass (no fraud flag)
3. drift > ε → fraud flag + structured log entry
4. default ε constant — pin `DEFAULT_DCI_EPSILON = 0.001`
5. malformed `DCI_NUMERIC_EPSILON="abc"` → graceful fallback + warn
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

### 7.3 Розрив теплого ланцюга DCI: точність виправлено, кроки й якір — ні (знайдено 2026-10-05; ⚖️ — `00_07 FW.66`)

**Механізм.** `check_z_divergence!` судить кожен отриманий кадр, але судить стан, який сервер продовжує від хвоста ОСТАННЬОГО ОТРИМАНОГО `TelemetryLog` (`TelemetryUnpackerService#previous_lorenz_state_for`), тоді як пристрій продовжує від RTC після КОЖНОГО свого кроку (FW.6, §2). Ланцюги збігаються, лише поки збігаються три речі: (а) ТОЧНІСТЬ стану між кадрами, (б) КІЛЬКІСТЬ кроків, (в) ЯКІР — моменти, коли сторона стартує заново з `K_seed` (ноти паритету — §5). Механізму доганяння немає ні на пристрої, ні на сервері, а без температур пропущених кроків його й не збудувати, тож порушення будь-якої з трьох умов розводить ланцюги назавжди: на ергодичному атракторі вони стають незалежними.

**(а) Точність — виправлено 2026-10-05.** Сервер ланцюжив double, а Солдат тримає стан у float32 (RTC DR16–DR18), тож без жодної втрати ланцюги розходились за 4–8 кадрів. Тепер сервер звужує, як пристрій (нота «ТОЧНІСТЬ стану» в §5).

**(б) Кількість кроків — відкрито; пускачі вже живі в прошивці й тракті:**
- морозне відкладення TX (FW.10, `Should_Defer_TX`; у полі предикат тотожний `temp < −15`, бо Vcap-половина вироджена) стоїть ПІСЛЯ кроку Фази 3, а стан однаково пишеться в RTC — кожна люта ніч розводить ланцюг кожного дерева холодної ділянки;
- кадр, що загубився дорогою: Королева кадрів телеметрії не підтверджує, тож Солдат їх не повторює, а CIFO Королеви при збігу DID перезаписує кадр, якого флаш ще не забрав (`Cifo_Upsert`, `firmware/queen/cifo_cache.h`);
- дублікат кадру — сервер крокує зайвий раз, а в ECB-ері дедупу кадрів немає: mesh-естафета ECB-ери (сусід пересилає чужий кадр зі зменшеним TTL на своєму наступному пробудженні, тобто в пізнішому флаші), повторний флаш Королеви, коли жоден CoAP-ретрай не дістав 2.xx, хоча сервер батч уже прийняв (FW.51: слоти живуть до успіху), і resume після часткового unpack ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security), «Anti-replay residuals»);
- VM_ERROR-кадр — пристрій не крокує; сервер доти крокував і ще й судив кадр (`vm_error` ≠ homeostasis робив майже кожен такий софт-збій P0 «fraud»), а з 2026-10-05 оминає його, як паніку (`step_lorenz_and_judge!`), тож пускачем (б) VM_ERROR більше не є — лишається (в) нижче;
- cadence-машина [`00_07`](00_07_Action_Plan_Tracker) ARCH.8, якщо пристрій крокуватиме частіше, ніж передаватиме (⊕ 2026-10-06: під гілкою (Б) у CCM-ері ланцюга немає, тож цей пускач зникає — врізка присудів FW.66 ↓).

**(в) Якір — відкрито.** Пристрій стартує заново з `K_seed` після втрати VBAT, після non-finite стану в RTC і на циклі після VM_ERROR (`lorenz_state_valid = 0`, `firmware/soldier/main.c`; це у відвантаженому STOP2 — після Standby [`00_07`](00_07_Action_Plan_Tracker) FW.54 пристрій натомість продовжить зі стану до збою, і паритет тоді тримається, бо сервер на VM_ERROR не крокує). Сервер стартує заново лише тоді, коли хвоста в нього немає (`compute_server_z`: `cold_start = previous.nil?`). Біта cold-start на дроті немає, тож про перезапуск пристрою сервер не дізнається, а відновлення ARCH.41 нижче, навіть угадавши кандидата, хвоста не переносить.

**Що далі робить сервер.** Розбіжність категорії стається на частці кадрів, і її долю вирішує відновлення ARCH.41 (`try_time_sync_recovery`, три cold-кандидати: сьогодні, вчора, 10957). Збіг кандидата мітить рядок `time_unsynced_fallback` і ставить у чергу `TimeSyncDownlinkWorker` — маяк часу всьому кластеру, без тротлінгу; незбіг інкрементує `DCI_CATEGORICAL_MISMATCH_TOTAL` — лічильник-спостереження без алерту (⚖️ founder 2026-10-05, [`00_07`](00_07_Action_Plan_Tracker) FW.66 нога 1; доти — `TELEMETRY_FRAUD_DETECTED_TOTAL` і P0-алерт `sn-alert-fraud-detected` «Можлива атака або hardware tamper»). Розрізняльної сили в цього відновлення немає: кандидат — свіжий старт, а z за 250 кроків від свіжого старту за помірних температур лежить у смузі майже завжди (нижче, «Якір кадру»), тож «відновлення» лише читає заяву пристрою: homeostasis стає time-sync, «поза смугою» стає розбіжністю. Бали від вердикту DCI не залежать: `Wallet#credit_telemetry!` має лише відро ліміту E.64 ([`05_03`](05_03_Tokenomics_SCC_and_SFC)), DCI-гейта на ньому немає.

**Вимір (2026-10-05, `ruby tools/firmware/dci_chain_loss.rb`; стелі — у шапці приладу).** 20 дерев × 2000 кадрів (≈ 151 доба), каденс 1.81 год, пристрій звужує стан, як прошивка:
- сервер звужує, без втрат — 0 прапорців на 40 000 кадрів; контроль дискримінує: `server=double` на тих самих входах дає 361 хибний fraud і 385 хибних time-sync, тобто ≈ 11 % і ≈ 12 % на дерево-добу — дефект (а) до правки;
- один втрачений кадр — після нього 358 хибних fraud і 362 хибних time-sync на 39 780 кадрів (0.90 % і 0.91 % на кадр, ≈ 11 % на дерево-добу кожне), і жодне з 20 дерев за 151 добу не лишилось без прапорця; при сталих −10 °C ≈ 4 %, при 25 °C ≈ 19 % хибного fraud на дерево-добу (`temp=…`). Решта пускачів (б) і (в) дають той самий розсинхрон — прилад моделює один.

**Наслідок.** P0 fraud від DCI спрацьовував лише на кадрі, що заявляє z ПОЗА смугою: чесний пристрій робить це на розсинхронізованому ланцюгу, фальсифікатор — лише якщо сам захоче. Фальсифікатор, що на КОЖНОМУ кадрі заявляє homeostasis, прапорця fraud не дістає взагалі: рідкісні кадри, де серверний z поза смугою, ARCH.41 списує на time-sync (`claim=homeostasis lost_at=-1`: 0 fraud і 363 time-sync на 40 000 кадрів). Отже грошового напряму підробки категорійна DCI не стримує — його стримує ключ AES (у CCM-ері ще й MIC і FC, але FC — лише в межах вікна кешу, [`00_07`](00_07_Action_Plan_Tracker) SEC.40); фізичний напрям — підроблений `stress`, один кадр якого вже кличе `severe_drought` і `EmergencyResponseService`, — P0 бачив лише разом із шумом розсинхрону; а розсинхронізований ланцюг ще й подає хибні докази смуги FW.8 (`record_band_evidence!`; не зміряно). ⚖️ **Тому P0 з категорійної DCI знято (founder 2026-10-05, FW.66 нога 1):** розбіжність лічить `silkennet_dci_categorical_mismatch_total` без алерту (читач — панель «Telemetry Ingest Rate»), а fraud-лічильник і P0 лишились за рештою семи джерел. Ціна названа: підроблений `stress` P0 більше не будить зовсім — долю гілки «stress → посуха» вирішує FW.8 (⊕ 2026-10-06: FW.8 ⚫ — гілку знімає реалізація (Б), [`00_07`](00_07_Action_Plan_Tracker) FW.66). ⚠️ Латентно: вузлів у лісі нуль.

**Якір кадру — лише в габарит атрактора (гілка (А), не обрана: ⚖️ 2026-10-05 ратифіковано (Б) — врізка наприкінці розділу; вимір 2026-10-05, `ruby tools/firmware/lorenz_anchor_transient.rb`).** Лік на (б) і (в) — стартовий стан кожного кадру виводити з `K_seed` і лічильника кадру FC (CCM-ера) без теплого ланцюга. Але якір у [-1,1]³, як у cold start, не годиться: такий старт лежить біля сідла в нулі, усі старти перші петлі йдуть разом однією нестійкою гілкою, і частка кадрів поза смугою стає функцією температури й N, а не хаосу — за N = 250 це 0 % при 10 °C, але 18.8 % / 32.9 % при 41 °C (заводська / дубова 40) проти 2.4 % / 6.1 % на теплому ланцюгу; прогрів 300–750 кроків розподілу не повертає, а вже подвоєння Лоренца за стелею [`02_03 §9.4`](02_03_BQ25570_MPPT_Nano_Power) кладе CCM-еру на метаболічну підлогу (H 1.81 → 2.02 год, m 0.104 → 0). Якір у ГАБАРИТ атрактора (точку HMAC розкладено в коробку x ±20 · y ±27 · z 1…ρ+20) розводить старти по фазах одразу: за ті самі 250 кроків частка anomaly відрізняється від теплої не більше ніж на 0.3 п.п. на −15…45 °C для обох смуг (незалежне перевимірювання, 4–8 млн кадрів на точку; відносно — до −41 % на холоді), тож статус лишається з z, а з ним FW.8 і грошовий гейт. Числова печатка влучає без `K_seed` ≈ 1–2·10⁻⁴ за кадр (≈ 13 біт) при σ = 10, але якщо σ (акустика з дроту) і T вибирає фальсифікатор — до 9.7·10⁻⁴, тож σ у якорі треба закріпити (якір [-1,1]³ — до 1.7·10⁻³). Повтору така печатка не бачить — z повтору перераховується точно, тож його тримає лише монотонна межа FC ([`00_07`](00_07_Action_Plan_Tracker) SEC.40). Статус-гейт z і на теплому ланцюгу навмання забирає бали 0.2–2.7 % чесних кадрів на заводській смузі й 2.3–6.6 % на дубовій (−15…45 °C; нота E.64 у §4).

**Дія.** Перша розвилка — P0 на DCI-розбіжності — ратифікована й застосована 2026-10-05 (↑ «Наслідок»); друга — ядро Z і печатка CCM-ери — теж ратифікована того ж дня: гілка (Б), Лоренц іде з пристрою разом із фліпом FW.2 ([`00_07`](00_07_Action_Plan_Tracker) FW.66); межа повтору — SEC.40. Ширша гілка тієї ж розвилки — прибрати Лоренца з пристрою й розвести ролі Z (печатка → криптографія, статус → прямі сигнали, атрактор → візуалізація) — це і є ратифікована (Б), присуди обох ніг — врізка нижче; виміри, Ено й нотатки стороннього frontier-LLM — [`z_core_forks`](protocols/hardware/z_core_forks.md). Доти «DCI не залежить від каденсу» правдиве лише про ПЕРЕВІРКУ, а не про ЛАНЦЮГ, який вона судить.

> ⚖️ **Присуди FW.66 — ратифіковано founder 2026-10-05 за рекомендацією («на оці всі шість так»); форми перенесено з трекера 2026-10-06 (присуд і підстава ноги 2 там скорочені — подання дослівно в [`z_core_forks`](protocols/hardware/z_core_forks.md) §4, ціну ноги 2 нижче взято звідти), реалізація — нога [`00_07`](00_07_Action_Plan_Tracker) FW.66.** **Нога 1 — P0 з категорійної DCI-розбіжності знято, обидві ери.** **Підстава:** виміряно, що цей P0 будив лише чесні дерева з розсинхронізованим ланцюгом (≈ 11 % дерев-діб після першої втрати) і ніколи — фальсифікатора homeostasis, а в ECB-ері ланцюг лагодити нема чим. **Ціна:** DCI не дає сигналу атаки на сторінку (і не давала); підроблений `stress` P0 більше не будить — один такий кадр і далі створює `severe_drought` і кличе `EmergencyResponseService`, долю цієї гілки вирішує ⚖️ «посуха» FW.8 (⊕ 2026-10-06: FW.8 поглинуто гілкою (Б), гілку знімає її реалізація — ⚫-врізка §5.3). **Найслабша ланка:** фальсифікатор, що заявляє «поза смугою», — грошового мотиву не має, фізичний має. **Нога 2 — гілка (Б): розвести ролі Z.** Печатку бере криптографія (MIC CCM + межа повтору [`00_07`](00_07_Action_Plan_Tracker) SEC.40 + QATT + якір сирих записів E.60), статус — прямі сигнали з тегом походження на сервері (біти статусу на дроті — валідність виміру; до калібрування «не виміряно»), гроші — серверний перерахунок із автентифікованих сирих полів (заяви пристрою — тест відповідності), атрактор — серверна візуалізація без грошового ефекту; mruby-Лоренц іде з пристрою разом із фліпом FW.2. **Підстава:** виміри цього розділу й межа брейншторму — I(статус; здоровʼя | входи) = 0 для будь-якої ключової F ([`z_core_forks`](protocols/hardware/z_core_forks.md) §6.1). **Ціна** (подання дослівно): перевідкриває E.64 («Z = DCI-only» → «Z не на пристрої») і FW.8: доказ видачі смуги потребує прямого відлуння версії смуги (16-бітне поле `device_z` звільняється), «посуха» з z зникає, а прямого свідка посухи до VPD немає; грошовий гейт за статусом знімається (чесні дерева отримують ті 0.9–2.4 %); канон [`03_04`](03_04_mruby_Lorenz_Attractor) переписується з атрактора на прямі сигнали, `LEAF_VERSION` +1; оповідь «ліс думає хаосом» переходить у візуалізацію. **Найслабша ланка:** енергетичний виграш (≈ 12 % активного циклу) стоїть на оцінці-стелі, не на вимірі — ΔE_cycle (RUNBOOK 3.2). ⊕ 2026-10-05: E.64 застосовано того ж дня — «Z не на пристрої» ([`05_05 §8.1`](05_05_Slashing_and_Risk_Policy)). ⊕ Застосовуючи, знайдено розвилку в самому поданні: «пряме відлуння смуги FW.8 у `device_z`» і «біти статусу — валідність виміру, вердикти на сервері» разом не тримаються — подано ⚖️ «FW.8 під (Б)», ратифіковано (а) 2026-10-06 (повна форма — ⚫-врізка §5.3). Стелі балів на дерево-добу (важіль брейншторму, [`z_core_forks`](protocols/hardware/z_core_forks.md) §6.2) у тілі присуду не було — це зміна токеноміки, і її подано окремо: ратифіковано й застосовано як E.64 ([`05_03`](05_03_Tokenomics_SCC_and_SFC), відро ліміту). Числова DCI FW.31 під (Б) втрачає предмет (⚫).
