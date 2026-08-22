# 02_04: Bench Build & Test Guide — Складання Вузлів Soldier + Королева на Макетці

> **🔧 ЖИВИЙ РОБОЧИЙ ДОКУМЕНТ.** Практичний посібник, як **фізично зібрати й
> перевірити повні вузли Soldier (Частина I) + Королева (Частина II) поблоково на макетній платі** — крок за кроком,
> у міру надходження деталей. Поки власна PCB недоступна для замовлення на заводі,
> **breadboard — єдиний фізичний шлях** зібрати й протестувати архітектуру.
>
> Стенд **гібридний**: живлення від legacy-харвестера (44 мВ AA-симулятор → LTC3108,
> або майбутній реальний EBFC >500 мВ), а решта вузла — production-компоненти
> (BME280, SE051C2, п'єзо, LoRa) на **готовому модулі LoRa-E5 mini** (кремній
> STM32WLE5 вже в модулі → значна частина silicon-bench досяжна вже тут).
>
> Це **компонентна валідація архітектури поблоково, НЕ production-збірка.** Чесно:
> breadboard ≠ власна PCB; harvester ≠ живий EBFC; готовий модуль LoRa-E5 ≠ 2-декова
> капсула. Кожен блок можна зупинити й перевірити окремо.

---

## 🎯 Мета

Дати покрокову збірку та bring-up **кожного функціонального блоку** Soldier (Частина I) і
Королеви (Частина II) на макетці — з wiring-таблицями, мультиметр-checkpoint'ами й застереженнями, що кусають
не-експерта, — поки PCBA заблоковано (HW.9). Production-специфікації компонентів
(part-номери, ціни, DC-bias, DNP-стратегія) **не дублюються** тут — вони живуть у
[`02_01 §3`](02_01_Hardware_Architecture_and_BOM) / [`02_03`](02_03_BQ25570_MPPT_Nano_Power);
silicon-атестація (µА-профілі, crypto-KAT) — у `firmware/scripts/bench/RUNBOOK.md`. Тут —
**фізична збірка макетки**, якої нема ніде більше.

---

## ✅ Статус

- **Поточний TRL:** TRL 3 — **етап: breadboard bring-up** (компонентна валідація архітектури,
  ДО власної PCBA; System TRL = 3, gated anchor/EBFC — [`00_03`](00_03_TRL_Matrix_HIL_and_Beyond) / CLAUDE §1).
- Harvester-фронт спроєктовано; закупівля часткова (живий чекліст §1); нові блоки
  (BME280 / SE051C2 / п'єзо / radio) — bench-pending. Відкриті питання → [`00_07`](00_07_Action_Plan_Tracker) HW.35.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`02_03`](02_03_BQ25570_MPPT_Nano_Power) | Production power-архітектура Soldier (BQ25570, post-pivot) |
| [`02_05`](02_05_Queen_Hardware_and_Starlink) | Королева HW: SIM7070G модем, solar/BMS/Victron, Starlink (Частина II) |
| [`02_01 §3`](02_01_Hardware_Architecture_and_BOM) | Electronics BOM (production-специфікація + ціни) |
| [`07_01 §11.2`](07_01_Nature_as_a_Service_Contracts) | Повна вартість вузла (node-rollup) |
| [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security) / [`00_07` SE050-MIGRATION](00_07_Action_Plan_Tracker) | Secure Element (SE05x, роль/eval) |
| `firmware/scripts/bench/RUNBOOK.md` | Silicon-атестація на готовій платі (crypto/power/timing) |
| [`07_03`](07_03_Academic_Integration_and_IP) | Лабораторні протоколи ЧНУ |
| [`01_01 §6`](01_01_Coaxial_Gyroid_Topology_and_PEEK) | Beyond-TRL9 SKU-roadmap (5 SKU на біом, Stage 5+) — доти цей рядок вказував на дорожню карту фаз, де жодного SKU немає |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [0. Навіщо breadboard — чесна реальність](#0-навіщо-breadboard--чесна-реальність)
- [1. Повний BOM Стенду (живий чекліст закупівлі)](#1-повний-bom-стенду-живий-чекліст-закупівлі)
- [2. Блокова Архітектура Стенду](#2-блокова-архітектура-стенду)
- [3. Складання по Блоках](#3-складання-по-блоках)
- [4. Bench Bring-up Протокол](#4-bench-bring-up-протокол)
- [5. Legacy Harvester — Фізика (для розуміння + ЧНУ)](#5-legacy-harvester--фізика-для-розуміння--чну)
- [6. Перехід до PCB / Production](#6-перехід-до-pcb--production)
- [7. Частина II — Королева (Queen Gateway): що інше](#7-частина-ii--королева-queen-gateway-що-інше)
- [8. BOM Королеви (живий чекліст)](#8-bom-королеви-живий-чекліст)
- [9. Блокова Архітектура Королеви](#9-блокова-архітектура-королеви)
- [10. Складання Королеви по Блоках](#10-складання-королеви-по-блоках)
- [11. Bench-протокол Королеви](#11-bench-протокол-королеви)
- [12. Starlink (Phase 3 — майбутнє)](#12-starlink-phase-3--майбутнє)
<!-- TOC:AUTO:END -->

---

## 0. Навіщо breadboard — чесна реальність

- **Власна PCB недоступна для замовлення** (HW.9 KiCad-layout не розведено, завод поза
  досяжністю) → макетка = єдиний спосіб фізично зібрати й перевірити Soldier зараз.
- Мета — **компонентна валідація архітектури поблоково**, не production. Кожен блок
  збирається й тестується окремо, у міру надходження деталей поштою.
- **Гібрид живлення:** front-end — legacy-харвестер (44 мВ AA-симулятор → LTC3108,
  §3.1) або майбутній EBFC >500 мВ напряму в BQ25570; решта вузла — production-компоненти
  на **готовому модулі Seeed LoRa-E5 mini** (STM32WLE5JC + SX1262). Кремній уже в модулі,
  тож crypto-selftest, I2C bring-up, acoustic-wake **досяжні вже на макетці** (§4).
- **🔵 Золоте правило — Спільна Земля.** Усі `−` (GND) плат, батарейки, іоністора — в
  **єдину синю шину** вздовж краю макетки. Без спільної землі логічні рівні = хаос.
- **🔴 Дві залізні пере-умови ПЕРЕД живленням:** (1) **антена 868 МГц на місці** (SX1262
  PA згорить без неї — §3.7); (2) правильна **полярність** накопичувача (§3.2 — тип
  визначає напрям смужки).

---

## 1. Повний BOM Стенду (живий чекліст закупівлі)

> Production-специфікація + ціни (10k) — дім [`02_01 §3`](02_01_Hardware_Architecture_and_BOM);
> node-вартість — [`07_01 §11.2`](07_01_Nature_as_a_Service_Contracts). Тут — **bench-статус + що кусає**.
> Статус: ✅ в руках · 🛒 замовити.

### Блок 0 — Інструменти bring-up
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| SWD прошивка/дебаг | ST-LINK-V3MINIE | 🛒 | — |
| USB-UART консоль | FT232RL (3.3 В) | ✅ | **джампер рівня → 3.3 В** (не 5 В); дублює вбудований USB-C міст LoRa-E5 |
| Макетка + дроти + мультиметр | — | ✅ | — |

### Блок 1 — Power harvester (legacy 44 мВ)
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| Джерело | AA 1.5 В + відсік з тумблером | ✅ | — |
| Дільник 44 мВ | R1 3.3 кΩ + R2 100 Ω | ✅ (набір 820) | 200 мВ-опція `6.5к/1к` = старт ~15-25 хв замість ~95 (§5) |
| Boost harvester | LTC3108 module (**звичайний, НЕ -1**) | 🛒 | -1 дає 2.5/3.0/3.7/4.5 В фікс.; нам треба 3.3 В (VS1→VAUX, VS2→GND) |
| Трансформатор | Coilcraft **LPR6235-752SMRC** (1:100) | 🛒 | 1:20 стартує лише від ~80 мВ → 44 мВ-стенд не оживе |
| Обв'язка LTC3108 | C1 1 нФ · C2 330 пФ · 499 кΩ bleeder · C_IN 220 µF · VAUX 1 µF · VLDO 2.2 µF | 🛒 (2.2 µF ✅) | C1=1нФ/C2=330пФ (не навпаки); 499к ∥ C2 проти squegging; піни трансформатора — §5 |

### Блок 2 — Power management (BQ25570)
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| PMIC breakout | CJMCU-2557 (BQ25570) | ✅ | резистори OV/UV/OK ще Li-Po — перепрог лише при 5.5 В supercap (§6) |
| Накопичувач (lab) | 1000 µF/25 В алюміній **або** 1000 µF/6.3 В полімер OS-CON | 🛒 обидва | **полярність РІЗНА**: полімер смужка=`+`, алюміній смужка=`−` (переплутаєш → спалах/пшик) |
| Buffer (LoRa TX peak) | 47 µF / **25 В** X7R 1210 | 🛒 | **НЕ 6.3 В** — DC-bias з'їдає −45…85% ([`02_03 §6.1`](02_03_BQ25570_MPPT_Nano_Power)) |
| _(production)_ | 0.47 Ф/5.5 В EDLC (Eaton HV0H474AEJ-R / KEMET FG0H474ZF) | — | лише для реального EBFC; на 44 мВ = ~31 доба заряду (§5) |

### Блок 3 — Compute
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| MCU+LoRa модуль | Seeed **LoRa-E5 mini** (STM32WLE5JC+SX1262) | 🛒 (×2) | живиться від BQ25570 VOUT (3V3); Type-C = прошивка, SWD = дебаг |

### Блок 4 — Sense (клімат)
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| Клімат-сенсор | Bosch **BME280** (I2C, PB6/PB7) | 🛒 | **НЕ BME680** (газ-нагрівач 10-12 мА вбиває бюджет) |
| Load-switch | TI **TPS22860** (SOT-23, 10 нА) | 🛒 | power-gate BME280; потрібен breakout/адаптер для breadboard |
| _(production)_ | PTFE-мембрана (IP68 «дихання») | — | не bench-критично |

### Блок 5 — Security (Secure Element)
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| Secure Element | NXP **SE051C2** (I2C, спільна шина з BME280) | 🛒 | eval-**пара**: звірити офіційний OM-SE051ARD (fallback — Mikroe SE051 Plug&Trust Click) + **OM-SE050ARD-E** companion (НЕ -F); cold-boot заряд = головне eval-питання (датащит мовчить) |

### Блок 6 — Acoustic wake
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| П'єзо (bench) | ЗП-3 диск ×5 (THT) | ✅ | bench-legit; production = SMD Mallory/Murata (HW.30) |
| Clamp (acoustic) | **BAT54S** (dual Schottky, Cj ~5-10 пФ) | 🛒 | потрібен для acoustic-тракту |
| Clamp (energy-only) | 1N5819 ×2 | ✅ | **Cj ~150 пФ = low-pass**, глушить ультразвук → лише energy-стенд; свап на BAT54S перед acoustic |
| _(production)_ | Bergquist Sil-Pad 1500ST coupling | — | acoustic coupling Ti↔п'єзо |

### Блок 7 — Radio
| Компонент | Модель | Статус | ⚠️ Кусає |
|---|---|---|---|
| LoRa PHY | SX1262 (в LoRa-E5) | ✅ | — |
| Антена | 868 МГц (SMA/u.FL до модуля) | 🛒 | 🔴 **ОБОВ'ЯЗКОВА ПЕРЕД ЖИВЛЕННЯМ** — PA згорить без неї |

**Bench-carrier комплект (🛒 разом):** 2× LoRa-E5 mini · ST-LINK-V3MINIE · BME280.

---

## 2. Блокова Архітектура Стенду

```
[Блок 1: HARVESTER]              [Блок 2: PM]         [Блок 3: COMPUTE]
AA 1.5В→дільник 44мВ→LTC3108  →  BQ25570 (VSTOR)  →  LoRa-E5 mini (3V3)
   (+trafo 1:100 +обв'язка)      +накопичувач         (STM32WLE5+SX1262)
                                 (1мФ lab / 0.47Ф EBFC)      │
                                                     ┌───────┼─────────┐
                                              [Блок 4]│[Блок 5] │ [Блок 6]│ [Блок 7]
                                            I2C PB6/7 │I2C PB6/7│ EXTI    │ RF
                                            BME280@   │SE051C2  │ п'єзо→  │ антена
                                            TPS22860  │         │ BAT54S  │ 868
                        ─────── СПІЛЬНА СИНЯ ШИНА GND ───────────────────
```

- **Живлення:** harvester → BQ25570 заливає накопичувач → при VSTOR≥3.4 В Buck дає 3V3 → LoRa-E5.
- **I2C шина** (PB6=SCL, PB7=SDA) спільна: BME280 (за TPS22860-гейтом, адреса 0x76/0x77) + SE051C2 (0x48) + pull-up 4.7 кΩ.
- **EXTI:** п'єзо-сплеск → BAT54S clamp (0-3.3 В) → GPIO wake зі STOP2.

---

## 3. Складання по Блоках

> Порядок = інкрементальний, острів за островом; мультиметр на кожному checkpoint.
> Можна зупинитись на будь-якому блоці (деталі приходять поступово).

### 3.0 Інструменти
1. LoRa-E5 mini: Type-C → комп'ютер; прошити baseline-образ (STM32CubeProgrammer / `factory:flash` — [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning)).
2. FT232RL: **джампер рівня → 3.3 В**; TX/RX cross до LoRa-E5 UART → serial-консоль / mruby REPL.
3. ST-LINK-V3MINIE: SWD (SWCLK/SWDIO/GND) до LoRa-E5 для дебагу.
4. **⚠️ Не живити одночасно** через Type-C (крок 1) І harvester 3V3-пін (§3.3): 3V3-пін mini back-feed-ить onboard-LDO. Спершу Type-C flash → від'єднати → потім harvester.

### 3.1 Power harvester (44 мВ → 3 В) — legacy
Компоненти: Блок 1. Wiring + пінаут трансформатора + фізика Meissner-осцилятора → **§5** (deep-dive). Коротко:
1. Дільник: AA(+)→[R1 3.3к]→«точка магії» (~44 мВ)→[R2 100Ω]→GND.
2. LTC3108 + trafo 1:100 + обв'язка (C1 1нФ / C2 330пФ / 499к bleeder) → VOUT ~3.3 В.
3. **Checkpoint:** мультиметр на VOUT LTC3108 → росте 0→3 В (повільно).

### 3.2 Power management (BQ25570)
1. LTC3108 VOUT → BQ25570 `VIN_DC`; спільний GND.
2. Накопичувач: `(+)`→`VBAT`, `(−)`→GND. **⚠️ полярність за типом** (§1 Блок 2).
3. `VOUT` BQ25570 → перемичка на Блок 3.
4. **Checkpoint:** VBAT росте 0→3.4 В; при 3.4 В Buck відкривається → VOUT=3.3 В.

### 3.3 Compute
1. BQ25570 `VOUT` (3V3) → LoRa-E5 `3V3`; GND спільний.
2. **Checkpoint:** LoRa-E5 стартує (LED / serial-баннер); mruby REPL відповідає.

### 3.4 Sense (BME280 @ TPS22860)
1. TPS22860: `VIN`←3V3, `VOUT`→BME280 `VDD`, `ON`←GPIO (power-gate).
2. BME280: `SCL`→PB6, `SDA`→PB7, спільна шина; pull-up 4.7к на SCL/SDA до 3V3.
3. **Checkpoint:** I2C-scan бачить BME280 (0x76 при SDO→GND / 0x77 при SDO→VDD); forced-mode read дає t°/RH/тиск.
4. Деталі VPD/DCI-guard → [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM); firmware `bme280.h` (I2C-глю ще писати — §4).

### 3.5 Security (SE051C2)
1. SE051C2 (eval-плата): I2C `SCL`→PB6, `SDA`→PB7 (спільна з BME280) + pull-upّи; живлення за load-switch'ем (окремий TPS22860 або спільний — bench).
2. **Checkpoint:** I2C-scan бачить SE05x (0x48) — цього достатньо для першого contact. Повний provisioning (об'єктна модель, Ed25519) = bench-**ціль**: T1oI2C-глю під STM32WLE5 ще писати ([`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)).
3. Роль (provisioning-only, Ed25519 голос дерева), eval-номенклатура, cold-boot → [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security). LoRa KEYL лишається в Protected Flash.

### 3.6 Acoustic wake (п'єзо → EXTI)
1. П'єзо ЗП-3: один вивід→GND, інший→сигнальний tap. **BAT54S** = dual-diode rail-clamp: верхній катод→3.3 В, нижній анод→GND, tap між діодами→EXTI GPIO (обмежує сплеск у 0-3.3 В). **⚠️ на energy-стенді 1N5819 глушить ультразвук — свап на BAT54S для acoustic.**
2. Bias: слабкий pull-down (~1 МΩ tap→GND) тримає EXTI-пін не-плаваючим між сплесками.
3. **Checkpoint:** постукати/подати 16 кГц tone → сплеск на GPIO → wake зі STOP2 (EXTI-IRQ у логах).
4. Патерн Zero-Touch (SMD-piezo + Sil-Pad) → [`02_01 §6`](02_01_Hardware_Architecture_and_BOM); поріг → HW.30.

### 3.7 Radio (антена ПЕРША)
1. 🔴 **Прикрутити антену 868 до LoRa-E5 ПЕРЕД будь-яким живленням радіо.**
2. **Checkpoint:** LoRa TX (+14 dBm SF9) → приймач/інший LoRa-E5 бачить пакет.
3. Zero-Touch RF, SWR-фізика → [`02_01 §5`](02_01_Hardware_Architecture_and_BOM).

---

## 4. Bench Bring-up Протокол

> **Два рівні.** (A) **Breadboard-рівень** — «блок ожив?» (мультиметр/LED/I2C-scan/serial),
> §3-checkpoint'и вище. (B) **Silicon-атестація** — «кремній відповідає специфікації?»
> (µА-профілі, crypto-KAT, timing) — **дім `firmware/scripts/bench/RUNBOOK.md`**, НЕ дублюється тут.
> Оскільки LoRa-E5 = готовий STM32WLE5, RUNBOOK-сеанси §1-4 (crypto/RTC/power/I2C) досяжні
> вже на макетці; §5 (модем SIM7070G) — Queen-only, тут недосяжний.

**Мапа breadboard-блок → RUNBOOK-сеанс (silicon-half):**

| Блок стенду | RUNBOOK-сеанс | Що атестує кремній |
|---|---|---|
| 3.1-3.2 Power | RUNBOOK §3 [дані для E.63] | STOP2 floor (PPK2), E_cycle, Vcap recharge-крива → калібрування delta_t |
| 3.3 Compute | RUNBOOK §1-2 | flash/option-bytes, crypto-selftest (ccm/sym KAT ≡ OpenSSL) |
| 3.4 Sense | RUNBOOK §6 (BME280 bullet) | I2C-глю (в коді ще нема) + gate-timing + VPD-калібрування |
| 3.5 Security | RUNBOOK §6 (SE05x bullet) | cold-boot заряд + T1oI2C-латентність + SE sleep-floor за гейтом |
| 3.6 Acoustic | RUNBOOK §6 [bench:acoustic] | HW.11 coating-attenuation + HW.30 SMD voltage-spike |
| 3.7 Radio (LoRa) | RUNBOOK §6 (RF-bullet, HW.31) | LoRa 868 TX/RX діаграма+дальність; антена = pre-flight |
| 3.3 Time/RTC | RUNBOOK §4 [bench:lse-rtc-wut] | LSE bring-up, WUT wake, drift |

Кожен день → артефакти в `bench_artifacts/` + оновлення item-а в [`00_07`](00_07_Action_Plan_Tracker) (числа → канон-доми: енергія [`02_03`](02_03_BQ25570_MPPT_Nano_Power), час [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA), крипто [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)).

---

## 5. Legacy Harvester — Фізика (для розуміння + ЧНУ)

> Навчальна цінність: як 44 мВ піднімаються до 3.3 В. Для лаб-робіт ЧНУ
> ([`07_03`](07_03_Academic_Integration_and_IP)) + розуміння harvester-ланцюга.
> LTC3108/трансформатор **виключені з production** (EBFC >500 мВ живить BQ25570
> напряму), але лишаються **DNP cold-start fallback** ([`02_03 §1.5`](02_03_BQ25570_MPPT_Nano_Power)).

### Осцилятор Майснера (LTC3108 + trafo)
44 мВ → первинна котушка → трансформатор підсилює індукцією → мікросхема штовхає SW
сильніше → резонанс × тисячі разів/с → напруга зростає 44 мВ → ~2-3 В. Частоту задає
індуктивність вторинної обмотки (+ паразитна ~30 пФ), НЕ зовнішній кондер. C2 (330 пФ)
зв'язує обмотку із затвором; C1 (1 нФ) живить зарядну помпу; 499к bleeder ∥ C2 = анти-squegging.

### Пінаут трансформатора LPR6235-752SMRC (найтонша частина — не переплутати)
| З'єднання | Куди | Роль |
|---|---|---|
| Трансф. первинна pin **1** | «точка магії» (44 мВ) / VIN LTC3108 | Початок первинної котушки |
| Трансф. первинна pin **4** | пін **SW** LTC3108 | Кінець первинної («штовхач») |
| Трансф. вторинна pin **2** | синя лінія GND | Опора вторинної |
| Трансф. вторинна pin **3** | вузол **C1 (1нФ) & C2 (330пФ)** | Зв'язок вторинної з charge-pump + gate |
| Bleeder 499 кΩ | пін **C2** ↔ GND (∥ C2) | Анти-squegging (datasheet) |

> Піни 1,4 = первинна; 2,3 = вторинна (datasheet Coilcraft LPR6235). Переплутати
> первинку/вторинку або SW↔C1 = осцилятор не стартує (найчастіша причина «не блимає»).

### 🔴 Пастка 31-го Дня (теорема Тевеніна)
44 мВ-дільник + **виробничий 0.47 Ф** = семестр не блимне LED:
```
V_th=44мВ · R_th=R1∥R2≈97Ω · P_max=V_th²/(4·R_th)≈5µВт
P_to_cap≈5µВт × η_LTC3108(~30%) × η_BQ25570(~70%) ≈ 1µВт
E(0.47Ф до 3.4В)=½·0.47·3.4²=2.71 Дж → t=2.71/1µВт≈31 доба
```
Тому lab-стенд бере **1 мФ** (у ~470× менше), і `зарядний струм > витоку ×3-5`. Опція
200 мВ (`6.5к/1к`, R_th 870Ω → P_max ~11.5 µВт) → старт ~15-25 хв замість ~95.

**Час до VBAT_OK (3.4 В):** 44мВ+1мФ ≈ **95 хв** · 200мВ+1мФ ≈ **15-25 хв** · 44мВ+10мФ ≈ 16 год ·
44мВ+0.47Ф ≈ **31 доба** (не для лаб).

---

## 6. Перехід до PCB / Production

Коли з'явиться доступ до PCBA (HW.9) + реальний EBFC-анкер:
1. Прибрати Блок 1 (harvester: AA, дільник, LTC3108, trafo, обв'язка).
2. `VIN_DC` BQ25570 ← напряму вихід EBFC Gen 2.0 (>500 мВ, [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)).
3. Навчальний 1 мФ cap → виробничий **0.47 Ф EDLC** (безпечно лише бо EBFC дає ~15-30 µВт).
4. Перевірити cold-start: R_int EBFC ([`02_03 §1.5`](02_03_BQ25570_MPPT_Nano_Power)); якщо >12 кΩ → LTC3108 як DNP-preboost.
5. Перепрограмувати резистори BQ25570 Li-Po→supercap ([`02_03 §4`](02_03_BQ25570_MPPT_Nano_Power); R_OC1=VOC_SAMP→GND, інакше 35% замість 65%).
6. Розвести PCB (Power Deck + RF Deck, B2B-конектор) → production breadboard-валідація [`02_03 §10`](02_03_BQ25570_MPPT_Nano_Power).

---

## 7. Частина II — Королева (Queen Gateway): що інше

> Королева — **шлюз, не сенсор**: слухає LoRa від Soldier'ів і шле батчі в інтернет
> через стільниковий модем (SIM7070G + SIM-карта), згодом — Starlink. Живиться
> сонцем/акумулятором (не harvester). Інший стенд, але **той самий модуль LoRa-E5 mini**,
> тож частина silicon-bench спільна. Головна нова фізика: модем дає **2 А RF-burst**,
> що просаджує живлення → без tank-конденсаторів модем перезавантажується.

| Вісь | Soldier (Частина I) | Королева |
|---|---|---|
| Живлення | harvester 44мВ→LTC3108→BQ25570→EDLC | Solar 50W → Victron MPPT → LiFePO4 12В/20Ah + BMS |
| LoRa | **TX** (передає) | **RX continuous** (`OnRxDone` ISR, слухає Soldier'ів) |
| Uplink | лише LoRa 868 | **SIM7070G cellular** + LoRa-RX + (Starlink Phase-3) |
| Крипто | ECB-encrypt (TX) | ECB-**decrypt** (RX) + AES-256-**CBC** (CoAP батч) |
| Периферія | ADC/TIM/RTC (Lorenz/sense) | без ADC/TIM/RTC (пульс data-starved, ARCH.54) |
| Консоль | FT232RL на UART модуля | **USART1 зайнятий модемом** → консоль через SWD/RTT |
| Корпус | 2-декова капсула | IP67 ABS/PC ≥2.5 л |

---

## 8. BOM Королеви (живий чекліст)

> Production-spec + ціни — [`02_05 §7`](02_05_Queen_Hardware_and_Starlink); node-вартість — [`07_01 §14`](07_01_Nature_as_a_Service_Contracts).
> Нові позиції — постав ✅ в руках / 🛒 замовити по факту.

### Compute / LoRa-RX
| Компонент | Модель | ⚠️ Кусає |
|---|---|---|
| MCU+LoRa | Seeed **LoRa-E5 mini** (STM32WLE5JC+SX1262) | той самий, що на Soldier; тут LoRa працює на **RX** |
| Overflow Flash | Winbond **W25Q32JV** (SPI, gated) | опційно — CIFO працює RAM-only без нього |

### Cellular (Phase 1/2.5)
| Компонент | Модель | ⚠️ Кусає |
|---|---|---|
| Модем | **SIM7070G** (LTE-M/NB-IoT, UART AT, 3.7 В) + **breakout** (Waveshare/DFRobot — канон дає голий LCC68) | **НЕ SIM7000G** (firmware = 7070G); маркування звірити (RUNBOOK §5.6) |
| SIM-карта | **Kyivstar фізична** (UA: наземні вишки + Starlink DTC) · eSIM 1NCE/Twilio для інших країн | 🔴 APN + D2C-transport = фазована стратегія [`00_07`](00_07_Action_Plan_Tracker) HW.41 (firmware init БЕЗ `AT+CGDCONT`; D2C Carrier-NAT → CoAP/UDP ненадійний → CoAP-over-TCP) |
| Cellular антена | Wideband **700–2700 МГц** SMA (Kyivstar B1/3/7/8/20) | окрема від LoRa (не dual-band) |

### LoRa-антена
| Компонент | Модель | ⚠️ Кусає |
|---|---|---|
| 868 антена | **tuned** 5 dBi fiberglass omni (Mobilemark OD8-868 / Taoglas ALL.4101) SMA | 🔴 НЕ dual-band (VSWR>2.5 @868 → −3-5 дБ); 🔴 антена ПЕРЕД живленням |

### Power (Phase 1/2.5 — зафіксовано HW.39/HW.15)
| Компонент | Модель | ⚠️ Кусає |
|---|---|---|
| Панель | Monocrystalline **50 W** | 10 W відхилено (−4.4 Вт·год/добу взимку під кронами) |
| MPPT | **Victron SmartSolar 75/15** | 🔴 **LiFePO4-пресет** (не lead-acid); quiescent 20 мА = найбільший сток |
| Акумулятор | LiFePO4 **12 В / 20 Ah** | заряд лише 0…+45 °C → charge-protect (нижче) |
| BMS | JBD/Jiabaida-клас **20 А cont / 50 А peak** (SKU 👤) | має витримати 2 А burst; JBD з NTC+charge-FET субсумує charge-protect |
| Buck 12→3.7 В | ≥3 А cont / ≥5 А peak (MP1584/LM2596-клас, part# 👤) | живить модем; сам не рятує від burst — треба tank ↓ |
| Buck 12→3.3 В | ≥500 мА | живить STM32 |

### 🔴 VBAT tank конденсатори (5 шт — обов'язкові, впритул до VBAT модема)
| Cap | Значення | Відстань |
|---|---|---|
| C_BULK | **470 µF / 6.3 В** alu-polymer (Panasonic EEFCX0J471R / Kemet T520B477M006ATE015), ESR≤15мΩ | 5-10 мм |
| C_MID | **100 µF / 25 В** X7R 1210 (Murata GRM32ER71E107K) | ≤5 мм |
| C_HF1 | **10 µF / 25 В** X7R 0805 | ≤3 мм |
| C_HF2 | **100 nF / 50 В** X7R 0402 | впритул |
| C_RF | **33 pF / 50 В** NP0 0402 | впритул |

### Thermal (зима, P0) + Starlink (Phase 3 — майбутнє, НЕ для цього bench)
| Компонент | Модель | ⚠️ Кусає |
|---|---|---|
| T-датчик | **DS18B20** (1-Wire, ±0.5 °C) на LiFePO4 head | гейт charge-MOSFET при T<+1 °C |
| Charge-protect | P-MOSFET у charge path (part# 👤, або BMS-integrated) | 🔴 заряд <0 °C вбиває LiFePO4 (зимовий деплой; літній — ні) |
| Корпус | IP67 ABS/PC ≥2.5 л (світлий RAL 7035 проти sun-load) | bench-некритично; freeze-pending |
| _(Phase 3)_ Starlink | Starlink Mini + ESP32-S3 WiFi-міст | 🔴 прошивки ESP32 НЕ існує → не збирати зараз (§12) |

**Bench-carrier комплект (🛒):** LoRa-E5 mini · SIM7070G breakout · Victron 75/15 · LiFePO4 20Ah + BMS · панель 50W · антени 868+wideband · 5 VBAT-caps.

---

## 9. Блокова Архітектура Королеви

```
☀️ Solar 50W → [Victron MPPT 75/15] → [LiFePO4 12В/20Ah + BMS] ──┬──▶ Starlink Mini (Phase 3)
   (quiescent 20mA)          (192 Вт·год корисні)                 │
                                                                  ├─[buck 12→3.7В]─▶ SIM7070G VBAT
                                                                  │                   └[5-cap tank ВПРИТУЛ]
                                                                  │                   └─SMA─ wideband 700-2700
                                                                  └─[buck 12→3.3В]─▶ LoRa-E5 mini
                                                                       ├─SX1262─SMA─ 868 tuned (LoRa RX)
                                                                       ├─USART1(PA9/PA10)─ SIM7070G AT
                                                                       └─1-Wire─ DS18B20 (на LiFePO4 head)
        ═══════ СПІЛЬНА ШИНА GND (усі −: MPPT · BMS · обидва buck · модем · tank · STM32) ═══════
── усе в IP67 ≥2.5л; Starlink ПОЗА корпусом
```
**Data-flow:** Soldier → LoRa RX → ECB-decrypt → CIFO cache → (flush @3600с або ≥45/50 слотів) → CBC-encrypt батча → **ECB-restore + LoRa-key** (🔴 інакше LoRa-decrypt наступних пакетів ламається) → CoAP → SIM7070G → Rails.

---

## 10. Складання Королеви по Блоках

### 10.1 Живлення (solar → battery)
1. Solar(+/−) → Victron MPPT solar-in; MPPT battery-out → LiFePO4(+/−) через BMS. **⚠️ Victron у LiFePO4-пресет.**
2. Battery 12 В → два buck: 12→3.7 В (модем) + 12→3.3 В (STM32). **🔵 Усі GND — solar/MPPT/battery/BMS/обидва buck/модем/tank/STM32 — в єдину спільну землю** (без неї UART без опори + 2А-return без шляху → brownout).
3. **Checkpoint:** мультиметр — MPPT bulk-charge активний, buck-виходи стабільні 3.7 / 3.3 В.

### 10.2 Модем SIM7070G (+ 🔴 tank)
1. Buck-3.7 В → SIM7070G VCC; **5-cap tank ВПРИТУЛ до VBAT-піна** (C_BULK 5-10мм … C_HF2/C_RF впритул). ⚠️ На breadboard паразитна індуктивність гірша за PCB → caps максимально близько до VBAT-піна breakout'а.
2. UART: STM32 **PA9**→SIM_RX, **PA10**→SIM_TX; PWR_KEY→GPIO (👤 обрати вільний, або тримати для always-on).
3. Wideband антена → SMA модема; SIM-карта у breakout.
4. **Checkpoint:** `AT`→`OK`; `AT+CGDCONT=1,"IP","<APN 👤>"`; `AT+CGATT?`→`1` (зареєстровано); осцилограф VBAT під TX-burst → просадка **<20 мВ** (RUNBOOK §6).

### 10.3 LoRa-RX
1. 🔴 **868-антена → SMA ПЕРЕД живленням** (SX1262 PA). SX1262 у RX-continuous.
2. **Checkpoint:** Soldier-стенд (Частина I) TX → Queen `OnRxDone` ISR ловить пакет (SWD/RTT-лог).

### 10.4 Thermal (зимовий charge-protect)
1. DS18B20 (1-Wire GPIO, **pull-up 4.7 кΩ data→VDD** — інакше не відповість) на корпус LiFePO4 head → charge-MOSFET гейт.
2. **Checkpoint:** DS18B20 читає T; при T<+1 °C заряд блокується.

---

## 11. Bench-протокол Королеви

| Блок | RUNBOOK-сеанс | Що атестує |
|---|---|---|
| Cellular init/e2e | RUNBOOK §5 [bench:coap] | AT-граматика, CoAP PUT→Rails, DNS-failover, poll-downlink |
| Модем marking | RUNBOOK §5.6 | = SIM7070G (не 7000G) |
| VBAT power | RUNBOOK §6 | 5-cap tank тримає просадку <20 мВ |
| LoRa RX | RUNBOOK §6 (RF-bullet, HW.31) | 868 покриття/дальність |

---

## 12. Starlink (Phase 3 — майбутнє)

> **⚠️ Starlink DTC ≠ Starlink Mini.** Для України пакети йдуть через **Starlink Direct-to-Cell** (Phase 2.5) — Kyivstar SIM конектиться через LEO-супутники, **той самий SIM7070G, без термінала** (§8; транспорт → [`00_07`](00_07_Action_Plan_Tracker) HW.41). Ця секція — про **Starlink Mini** (Phase 3): окремий high-bandwidth термінал + ESP32-S3 WiFi-міст.

ESP32-S3 WiFi-міст STM32→Starlink Mini — **прошивки ще нема** (`firmware/esp32_coproc/` відсутня). Phase 1/2.5 працює через SIM7070G без Mini-термінала (DTC через Kyivstar). Збирати при Starlink-Mini bring-up. Дім рішення (ESP32-S3, не SIM8200G-M2) — [`02_05`](02_05_Queen_Hardware_and_Starlink) / [`00_07`](00_07_Action_Plan_Tracker) HW.18.
