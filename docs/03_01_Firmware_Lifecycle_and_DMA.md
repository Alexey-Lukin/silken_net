# 03_01: Життєвий Цикл Прошивки та DMA (Фази 0–5, Watchdog, STOP2)

## 🎯 Мета

Зафіксувати детермінований життєвий цикл (Main Loop) вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор), переходи між станами сну та апаратні переривання (ISR) мікроконтролера родини STM32WLE5 (плата вузла — `CC`, стенд — `JC`, §1.1; Королева — `JC`, [`02_05`](02_05_Queen_Hardware_and_Starlink)). Документ слугує SSOT для Factory Flashing (масового виробництва) та OTA-розгортання.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — увесь C-код Soldier+Queen реалізований, host-based тести зелені (`make -C firmware/test`). Відкриті обмеження (чому не вище): silicon-bench UART/CoAP (`FW.3`, AT/DMA закрито host-рівнем), key-rotation активація (`FW.17`, gated FW.2 CCM), RDP-2 (`SEC.2`) — реєстр у [`00_07 §03a`](00_07_Action_Plan_Tracker)

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| `firmware/soldier/main.c` · `firmware/queen/main.c` · `firmware/bio_contracts/bio_contract.rb` | Джерела: C-код Soldier/Queen + mruby bio-contract |
| `firmware/test/` | Host-based x86 тести (`make -C firmware/test`) |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Queen: LoRa RX, CIFO, SIM7070G modem |
| [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) | TinyML класифікатор звуку — паркований з HW.30: актив без call-site на Солдаті |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | Математика Атрактора Лоренца |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Шифрування, ключі, RDP |
| [`02_03` — BQ25570 MPPT Nano Power](02_03_BQ25570_MPPT_Nano_Power) | Power-path: BQ25570 MPPT + EDLC буфер 0.47F (§12), VBAT_OK гейт |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери модуля 03** (SSOT): `FW.3` silicon-bench, `FW.17` key-rotation активація, `SEC.2` RDP-2, `SEC.3` factory |

---

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Інструментарій Розробки](#-інструментарій-розробки)
- [1. Soldier — Архітектура Вузла-Датчика](#-1-soldier--архітектура-вузла-датчика)
- [2. Soldier RTC Backup Register Map (DR0..DR19) — Canonical SSOT](#-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3)
- [3. Soldier RAM Budget (~2 KB з 64 KB SRAM)](#-3-soldier-ram-budget-2-kb-з-64-kb-sram)
- [4. Queen — Архітектура Шлюзу-Агрегатора](#-4-queen--архітектура-шлюзу-агрегатора)
- [5. Queen RAM Budget](#-5-queen-ram-budget)
- [6. ISR Map (Апаратні Рефлекси)](#-6-isr-map-апаратні-рефлекси)
- [7. DID Derivation (Ім'я з кремнію)](#-7-did-derivation-імя-з-кремнію)
- [8. Binary Packet Format (Зовнішній фрейм, 21 байт)](#-8-binary-packet-format-зовнішній-фрейм-21-байт)
- [9. Encryption Architecture](#-9-encryption-architecture)
- [10. Покриття Host-Based Тестами](#-10-покриття-host-based-тестами)
- [11. Bio-Contract Specification](#-11-bio-contract-specification-firmwarebio_contractsbio_contractrb)
- [12. Тестова Інфраструктура](#-12-тестова-інфраструктура-firmwaretest)
- [13. EMA (Exponential Moving Average) на Soldier — FW.21](#-13-ema-exponential-moving-average-на-soldier--fw21-)
<!-- TOC:AUTO:END -->

---

## 🛠️ Інструментарій Розробки

### STM32CubeIDE

| Аспект | Деталі |
|--------|--------|
| **Призначення** | Повноцінна C/C++ IDE для STM32WLE5xx (ARM Cortex-M4 + радіо SX126x на кристалі) |
| **Включає** | STM32CubeMX — графічний конфігуратор GPIO, тактових дерев, периферії |
| **Порт** | Налаштування GPIO pinout (PA9/PA10 UART, ADC, DMA USART1-RX Королеви, RNG, CRYP) до отримання плат |
| **Clock Tree** | Конфігурація HSE/LSE для ultra-low-power сну (ціль — Standby з RTC на LSE low drive, ≈ 300 nA — [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power), ⚖️ 2026-10-05 — §1.10; на TRL 6 baseline: STOP2, 1.07 µA за паспортом) |
| **HAL drivers** | Auto-генерація ініціалізаційного коду для I2C/SPI/ADC/UART/RTC/CRYP |
| **Debugger** | Інтеграція з ST-LINK-V3MINIE: breakpoints, live variable watch, SWO trace |
| **Збірка** | GCC ARM Embedded toolchain (вбудований у CubeIDE); той самий компілятор що й для host-тестів |

**Що можна зробити до отримання фізичних плат:**
1. Налаштувати повний Pinout у STM32CubeMX для обох прошивок (Soldier та Queen)
2. Сконфігурувати Clock Tree для STOP2 (MSI 100 kHz active clock, LSE 32.768 kHz для RTC)
3. Підготувати HAL-ініціалізацію для всіх периферій (ADC, DMA USART1-RX Королеви, IWDG, RNG, CRYP, SUBGHZ)
4. Запустити host-based тести (make -C firmware/test) без будь-якого ARM toolchain
5. Запустити Wokwi-симуляцію для логіки сенсорів та пакетного формату

### Конфігурація Pinout STM32CubeMX (5 Каналів Сенсора + SWD)

#### Канальна Карта (Channel Map)

| # | Назва Каналу | Периферія CubeMX | Шлях у CubeMX | Налаштування |
|---|---|---|---|---|
| SWD | Програматор (Оптичний Нерв) | SYS | `System Core → SYS → Debug` | **Serial Wire** (PA13=SWDIO, PA14=SWCLK → зелені) |
| 1 | Delta T (Алгоритм Часу) | RTC | `Timers → RTC` | **Activate Clock Source** + **WakeUp** (STOP2 wake) |
| 2 | Температура Кристала | ADC | `Analog → ADC` | **Temperature Sensor Channel** ✓ |
| 3 | ⛔ *знято* — п'єзодиск зрізано з Солдата ([`00_07`](00_07_Action_Plan_Tracker) HW.30, 2026-09-29) | — | — | PA0 / EXTI0 не конфігуруються; решта каналів тримає свої номери |
| 4 | Глибина Резервуара (Vcap) | ADC | `Analog → ADC` | **Vrefint Channel** ✓ (одночасно з каналом 2; FW.50: конвертується у чесні мВ VDDA = проксі заряду; реальний Vcap — окремий канал+дільник, §1.4) |
| 5 | RSSI Біомаса / Фенологія | — | *Без конфігурації на вузлі* | Zero-Energy: вимірюється Queen на стороні Gateway |
| 6 | Квантовий Шум (TRNG seed) | RNG | `Security → RNG` або `Computing → RNG` | **Activated** ✓ |

> **Канал 5 (RSSI):** 868 МГц LoRa-хвилі поглинаються водою в листі. Взимку RSSI ≈ -80 dBm; навесні при розпусканні листя RSSI падає до ≈ -105 dBm. Зміна RSSI між виміряннями дозволяє Queen відстежувати фенологічний стан (листяний покрив) без жодного додаткового датчика на Soldier. Значення RSSI автоматично фіксується SX1262 при кожному RX-пакеті.

#### Пін-бюджет STM32WLE5CC (UFQFPN48) — звірено з DS13105 Rev 12, табл. 20 (2026-09-25)

Плата вузла несе 48-пінний корпус, а не UFBGA73 модуля, тож частини GPIO просто немає. **Є:** PA0–PA15 · PB0 (він же `VDD_TCXO` — живлення TCXO) · PB2–PB8 · PB12 · PC13 · PC14/PC15 (LSE) · PH3-BOOT0. **Немає:** PB1 · PB9–PB11 · PB13–PB15 · PC0–PC6.

| Функція | Пін | У QFN48 |
|---|---|---|
| SWD | PA13 / PA14 | ✅ |
| *(вільний — пʼєзо зрізано, [`00_07`](00_07_Action_Plan_Tracker) HW.30)* | PA0 (WKUP1) | ✅ |
| I²C1 — BME280 + SE05x ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)) | PB6 (SCL) / PB7 (SDA) | ✅ |
| Консоль (FT232RL) | PA2 / PA3 — USART2 або LPUART1 (USART1 на PB6/PB7 зайнятий I²C) | ✅ |
| TCXO · LSE | PB0-VDD_TCXO · PC14/PC15 | ✅ |
| АЦП-входи | PB2 (IN4) · PB3 (IN2) · PB4 (IN3) · PA10 (IN6) · PA11 (IN7) · PA12 (IN8) · PA15 (IN11); PA13/PA14 теж АЦП, але зайняті SWD | ✅ сім вільних |
| RF-ключ поз. 19 `BGS12WN6` — CTRL + VDD-гейт (⚖️ founder 2026-09-30, [`02_01 §3.1`](02_01_Hardware_Architecture_and_BOM)) | 2 × GPIO з вільних PA/PB — призначає розкладка ([`00_07`](00_07_Action_Plan_Tracker) HW.9) | ✅ |
| `V_OC` EBFC (напрям ⚖️ founder 2026-09-10; фізика — гіпотеза до стенда, [`02_03 §12.4.2`](02_03_BQ25570_MPPT_Nano_Power)) | 1 АЦП-вхід із семи вільних, `VIN_DC` напряму (дільник 1:1), довгий sample-time — призначає розкладка ([`00_07`](00_07_Action_Plan_Tracker) HW.9; HAL — FW.46) | ✅ |
| Vcap-sense (⚖️ делеговано 2026-09-27, [`02_01 §7.1`](02_01_Hardware_Architecture_and_BOM); [`00_07`](00_07_Action_Plan_Tracker) FW.50) | 1 АЦП-вхід + 1 GPIO гейта TPS22860 (поз. 23) — призначає розкладка ([`00_07`](00_07_Action_Plan_Tracker) HW.9) | ✅ |

⚠️ **Акустичних пінів на Солдаті немає** ([`00_07`](00_07_Action_Plan_Tracker) HW.30, 2026-09-29): ні EXTI-пробудження від пʼєзо на PA0, ні аудіо-входу АЦП — PA0 і сім АЦП-входів вище вільні для розкладки ([`00_07`](00_07_Action_Plan_Tracker) HW.9). ⚠️ Керування RF-ключем фронтенду — два звичайні GPIO (`BGS12WN6`, ⚖️ 2026-09-30: CTRL — 0 → RF1, 1 → RF2; VDD-гейт — ключ живиться лише на час TX/RX, бо при поданому VDD тягне 63 мкА typ, а встановлення після подачі — 5–15 мкс, [`rf_switch_shortlist`](protocols/hardware/rf_switch_shortlist.md) §3); референс-плати ST на UFBGA73 можуть тримати його на PC-пінах, яких QFN48 не має, тож при перенесенні референс-розкладки ці піни перепризначаються ([`00_07`](00_07_Action_Plan_Tracker) HW.9). `.ioc` плати вузла ([`00_07`](00_07_Action_Plan_Tracker) FW.46) — на `STM32WLE5CC`.

#### Покрокова Конфігурація у STM32CubeIDE

**Крок 1: Створення проєкту**
1. `File → New → STM32 Project`
2. Part Number: `STM32WLE5CC` (плата вузла) — або `STM32WLE5JC` для стенду на LoRa-E5 mini → вибрати чип → Next
3. Назва: `snet_core`, мова: **C**, тип: **STM32Cube** → Finish

**Крок 2: Pinout & Configuration**

```
SWD Debugger:  System Core → SYS → Debug = "Serial Wire"
               PA13 (SWDIO) та PA14 (SWCLK) стануть зеленими

ADC Канали:    Analog → ADC
               ☑ Temperature Sensor Channel  (Канал 2: внутр. температура)
               ☑ Vrefint Channel             (Канал 4: внутр. опора → VDDA, FW.50)

RNG:           Security → RNG → ☑ Activated  (Канал 6: квантовий шум)

SUBGHZ (LoRa): Connectivity → SUBGHZ → ☑ Activated  (внутрішня шина LoRa SX1262)

RTC (Delta T): Timers → RTC
               ☑ Activate Clock Source
               ☑ WakeUp  (дозволяє STOP2 + RTC wake-up на мікроамперах)
```

**Крок 3: Clock Configuration**
- Вкладка **Clock Configuration** → переконатися що джерело **MSI** (Multispeed Internal RC Oscillator)
- Цільова частота: **~4 MHz** (енергозбереження — швидкість не потрібна)
- Кнопка **Resolve Clock Issues** якщо з'явиться попередження

**Крок 4: Генерація коду (Кенозис)**
- `Ctrl+S` → "Do you want to generate code?" → **Yes**
- Генерується `Core/Src/main.c` з HAL-ініціалізацією (~3000 рядків)

#### USER CODE Zones — Дисципліна Розробки

```c
/* USER CODE BEGIN 2 */
// Ваша логіка ініціалізації: ДІД-генерація, mruby VM init, завантаження ключів
/* USER CODE END 2 */

/* USER CODE BEGIN 3 */
// Головний цикл: sense → pack → lorenz → encrypt → TX → STOP2
/* USER CODE END 3 */
```

> ⚠️ **Критично:** Код поза `USER CODE BEGIN/END` зонами буде **стертий** при наступній регенерації конфігурації CubeMX. Вся бізнес-логіка Soldier — тільки всередині цих тегів.

### Host-Based Тести (без CubeIDE, без плат)

```bash
# Запуск усіх host-based тестів на x86 (не потрібен ARM toolchain)
make -C firmware/test

# Тільки Soldier:
make -C firmware/test soldier

# Тільки Queen:
make -C firmware/test queen
```

Компілятор: `gcc` (системний x86). Тести покривають: CIFO, AES, Lorenz, OTA, Mesh, CRC32, DID-генерацію.

### Фізичне Підключення Апаратного Відладчика (ST-LINK-V3MINIE + FT232RL)

#### Фаза 0: Заземлення (The Shield — Спільна Земля)

**Правило спільної землі:** Перед підключенням будь-яких інформаційних каналів — всі GND на одній шині.

```
ST-LINK GND  ──────┐
FT232RL GND  ──────┼──── Синя лінія Breadboard (─ GND)
LoRa-E5 GND  ──────┘
BQ25570 GND  ──────┘
```

#### Канал 1: ST-LINK-V3MINIE (SWD — Завантаження Коду)

| ST-LINK пін | LoRa-E5 mini пін | Призначення |
|---|---|---|
| **SWCLK** | **CLK** | Тактовий сигнал SWD (синхронізація) |
| **SWDIO** | **DIO** | Двонаправлений канал даних (код/регістри) |
| **NRST** | **RST** | Апаратний скид — **обовʼязковий** на фабричному джизі: кожен рядок конвеєра й стендових скриптів підключається під скидом (`mode=UR`), а ST вимагає NRST, підʼєднаний до MCU, для апаратного скиду ([`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning), STEP 2 d) |
| **T_VCC** | **3V3** | Референсна напруга (ST-LINK не живить плату, лише "чує" рівень) |

> ⚠️ **T_VCC ≠ живлення:** ST-LINK через T_VCC тільки перевіряє рівень логіки. Плата LoRa-E5 живиться від BQ25570 VOUT (3.3V). Не підключати VCC від ST-LINK до 3V3 — конфлікт джерел живлення!

#### Канал 2: FT232RL (UART — Читання Логів та Serial Console)

> ⚠️ **КРИТИЧНО:** Перед підключенням переконатися, що перемичка (jumper) на FT232RL стоїть у позиції **3.3V** (не 5V). 5V миттєво пошкодить GPIO STM32WLE5JC.

| FT232RL пін | LoRa-E5 mini пін | Призначення |
|---|---|---|
| **RX** | **TX2** — `PA2`, J1-13 | Мікроконтролер передає → адаптер отримує |
| **TX** | **RX2** — `PA3`, J1-14 | Адаптер передає → мікроконтролер отримує |
| **VCC** | *не підключати* | Залишити порожнім — LoRa-E5 вже живиться від BQ25570 |

> ⛔ Не на **TX/RX** гребінки (J1-18/19): це `PB6`/`PB7` — USART1 бортового моста CP2102N, а за схемою міст живиться лише від USB, тож без USB FT232RL подавав би напругу на виводи знеструмленого чипа. USART2 — той самий периферійний блок, що консоль у пін-бюджеті вузла (таблиця вище). Прошивка Солдата UART-виводу сьогодні не має — самотест читається по SWD (RUNBOOK §2.1).

**Налаштування Serial Monitor (Mac/Linux):** baudrate = 115200, 8N1.

#### Пін-мапа LoRa-E5 mini (первинка Seeed: схема «LoRa-E5 mini v1.0» + паспорт модуля Wio-E5 V1.1, звірено 2026-10-06)

Bench-carrier — STM32WLE5JC у модулі, і його виводи НЕ ті, що на платі вузла STM32WLE5CC (скіл `firmware` #16): у QFN48 вузла немає `PB13–PB15` і `PC0–PC6`, тож, наприклад, I²C стенда тут сидить на I2C2. Образ для mini — рукописний `hal_glue/boards/lora_e5/` (§12.4).

| Функція | Пін MCU | Гребінка J1 | Що ще на лінії |
|---|---|---|---|
| SWD | `PA13` SWDIO · `PA14` SWCLK | 3 · 4 | — |
| Скид | NRST | 5 (RST) | кнопка K2 на землю; DTR моста — через 100 нФ |
| USART1 | `PB6` TX · `PB7` RX | 18 · 19 | бортовий міст CP2102N → USB-C, через 20 Ом; за схемою міст живиться лише від USB (його VDD — власний регулятор від 5 В) |
| USART2 | `PA2` TX2 · `PA3` RX2 | 13 · 14 | — (консоль FT232RL ↑) |
| LPUART1 | `PC1` TX1 · `PC0` RX1 | 15 · 16 | — |
| I2C2 | `PB15` SCL · `PA15` SDA | 23 · 22 | підтяжки R15/R16 4.7 кОм до 3V3 на платі mini (BME280 стенда) |
| SPI2 | `PB13` SCK · `PB14` MISO · `PA10` MOSI · `PB9` NSS | 10 · 8 · 7 · 9 | `PB13` — ще й кнопка BOOT K3 на землю через 470 Ом |
| Світлодіод | `PB5` | — | червоний D6, **активний низьким** (анод через 1 кОм на 3V3) |
| Аналог і GPIO | `PB3` A3 · `PB4` A4 · `PA0` D0 · `PA9` D9 · `PB10` D10 | 20 · 21 · 17 · 12 · 11 | — |
| Живлення | 3V3 · USB 5V · GND | 2 · 1 · 6 і 24 | ⛔ не живити одночасно через USB-C і 3V3 від BQ25570 — [`02_04`](02_04_Bench_Build_Guide), крок прошивки |
| Тактування | LSE 32.768 кГц · 32 МГц | усередині модуля | паспорт V1.1, Figure 1: обидва вузли тактування на платі модуля (32 МГц блок-схема малює «XTAL», а функційно це TCXO — [`rf_frontend_forks`](protocols/hardware/rf_frontend_forks.md)), `PC14`/`PC15` серед виводів модуля немає (Table 1); живлення 32-МГц TCXO — `PB0` модуля (ніжка 28 → TP2), і паспорт велить лишати його плаваючим — не підтягувати й не заземлювати; CL і ESR кварцу LSE паспорт не дає — `LSEDRV` обирається запасом і перевіряється на стенді |


#### Фінальне Підключення до Mac

```
MacBook USB-A/C ──── ST-LINK-V3MINIE (Type-C) ──── SWD: CLK+DIO+RST+T_VCC → LoRa-E5
MacBook USB-A   ──── FT232RL                  ──── UART: TX→RX2, RX→TX2 → LoRa-E5 mini
```

Обидва USB-кабелі підключаються до Mac одночасно. STM32CubeIDE автоматично знаходить ST-LINK; для логів — `screen /dev/cu.usbserial-* 115200` або Serial Monitor у CubeIDE.

---

## 🌲 1. Soldier — Архітектура Вузла-Датчика

### 1.1 Апаратна Платформа

**MCU:** STM32WLE5CC на платі вузла (UFQFPN48; ⚖️ founder 2026-09-25 ратифікував чіп у QFN 7 × 7, P/N `CC` — наша поправка корпусу, [`02_01 §3`](02_01_Hardware_Architecture_and_BOM) поз. 1) · на стенді — STM32WLE5JC у модулі LoRa-E5 mini. Ядро (ARM Cortex-M4 @ 48 MHz) і вбудоване радіо SX126x ті самі, а збірка таргетує родину `STM32WLE5xx`, тож для прошивки різниця — лише в пінах (пін-бюджет вище)

| HAL Handle | Периферія | Призначення |
|------------|-----------|-------------|
| `hadc` | ADC | Рівно два канали: температура кристала + VREFINT → VDDA (FW.50). ⚠️ [ARCH.99] Каналу на сам іоністор НЕМА — поле `Vcap` на дроті несе напругу шини |
| `hiwdg` | IWDG | Апаратний Watchdog (auto-reset при зависанні mruby/HardFault) |
| `hrng` | RNG/TRNG | Істинна випадковість (тепловий шум кристала) |
| `hrtc` | RTC | Real-time clock + Backup Domain (персистентний стан після STOP2) |
| `hsubghz` | SUBGHZ | Інтегрований LoRa трансивер SX1262 (868 МГц) |
| `hcryp` | AES | Апаратний AES (Hardware Crypto Engine). **LoRa-канал: AES-128-ECB** (post-ARCH.42 transitional → CCM target FW.2). Queen додатково динамічно re-init'ить на AES-256-CBC для CoAP-batch flush. |

**Примітка:** Soldier — єдиний вузол, що має ADC та RTC. Queen — не має ADC та RTC (має RNG, AES та IWDG). Таймера й DMA на Солдаті з HW.30 немає (їх тримав лише аудіо-тракт пʼєзо); єдиний DMA-канал прошивки — USART1-RX Королеви (§6.2).

### 1.2 Загальний Lifecycle

```
Народження (Power-On) → DID Generation → mruby VM Init → Infinite Loop:
┌─────────────────────────────────────────────────────────┐
│  Phase 0: IWDG Refresh (Watchdog)                       │
│  Phase 1: Sensor Acquisition (ADC × 2 cycles + HRNG)   │
│  Phase 2: Bit-Pack (lora_payload[16])                   │
│  Phase 3: mruby Lorenz Attractor (bio-contract)         │
│  Phase 4: AES-128-ECB Encrypt → Radio.Send [ARCH.42]   │
│      [optional] Mesh Relay TX first                     │
│  Phase 4.5: RX Window (only if Vcap > 2800 mV)         │
│      Scenario A: OTA (0x99 marker) → Flash write        │
│      Scenario B: Mesh relay (16 bytes, TTL > 0)         │
│  Phase 5: Save to RTC Backup Domain → STOP2 (1.07 µA)  │
└─────────────────────────────────────────────────────────┘
       ↑ Wake on RTC (канон wake-source — §1.10)
```

---

### 1.3 Phase 0: IWDG Watchdog Refresh

```c
HAL_IWDG_Refresh(&hiwdg);
```

Перша інструкція кожного циклу. Якщо mruby VM або будь-який інший блок зависне і цей рядок не виконається протягом IWDG timeout (налаштовується prescaler: типово ~26 секунд), MCU автоматично перезавантажиться. Усі критичні дані зберігаються в RTC Backup Domain.

### 1.3.1 Error_Handler: Soft Reset замість Вічного Циклу (FW.14)

При HardFault або критичній помилці HAL викликається `Error_Handler()`. До виправлення (FW.14) він входив у нескінченний цикл — вузол зависав назавжди. Тепер реалізований soft reset:

```c
void Error_Handler(void) {
  HAL_Delay(100);     // 100 мс: дозволяє USART завершити передачу AT-команд
  NVIC_SystemReset(); // ARM CoreSight System Reset Request → перезавантаження за ~1 мс
}
```

`NVIC_SystemReset()` — стандартний ARM CoreSight System Reset. Вузол перезавантажується автоматично і повертається до нормальної роботи. Затримка 100 мс запобігає обриву незавершених UART-транзакцій перед скиданням.

---

### 1.4 Phase 1: Sensor Acquisition

**Метаболізм (delta_t):**
```c
// [FW.49 S1] wall-секунди з free-running RTC-календаря (LSE йде у STOP2)
uint32_t current_time = Wall_Seconds_Now();
// кожне пробудження рухає базу на свій wall-відлік (wall_time.h)
delta_t_seconds = Silken_Wake_Delta_Seconds(current_time, &last_wakeup_timestamp,
                                            DELTA_T_UNKNOWN_S,         // 0 = сентинел «не виміряно»
                                            DELTA_T_MAX_PLAUSIBLE_S);  // 7 діб
```

`delta_t_seconds` — час між пробудженнями в секундах; базу рухає кожне пробудження, а сентинел «не виміряно» дають лише гарди дельти нижче (EXTI-пробудження, що базу не рухало, пішло з пʼєзо — §1.10). Відображає швидкість заряду EDLC суперконденсатора (іоністора). Чим швидше заряд → тим активніший фотосинтез → тим здоровіше дерево. Це є первинний біофізичний сигнал для Атрактора Лоренца.

> **🟡 tick ≠ wall-time у STOP2 — S1-wiring ✅ (2026-06-12), bench bring-up 👤.** `HAL_GetTick()` (SysTick) **заморожений** у STOP2 — стара tick-різниця міряла лише active-час (~секунди) замість wall-інтервалу заряджання → `m(delta_t)` ≈ максимум у всіх дерев → over-mint Proof-of-Growth. Тепер: `Wall_Seconds_Now()` читає RTC-календар (`Silken_Unix_From_Calendar`, FW.30-арифметика) — він free-running від 2000-01-01 ще ДО першого синку (дельтам цього досить), а beacon-UTC робить його абсолютним (`Wall_Calendar_Set`: `Silken_Civil_From_Unix`-інверсія, roundtrip host-пара з прямою функцією). Guard-и дельти (cold-start / зсув назад / стрибок епохи при першому синку → сентинел «не виміряно» `DELTA_T_UNKNOWN_S`, ARCH.102: «нейтральні» 60 с мінтили максимум) — `wall_time.h`. Wire `dT:2` сатурується @0xFFFF (wall-дельти бувають добами; wrap збрехав би бекенду). Cold-start `epoch_day` (SEC.11) — wall-first з `Silken_Wall_Is_Utc`-предикатом; tick-екстраполяція лишилась фолбеком (бекенд-кандидати — [`03_04`](03_04_mruby_Lorenz_Attractor) Mitigation A). Tick-таймери порогів (FW.27-B/FW.20-S2) ще раніше мігрували на лічильники пробуджень. **Wake-source ВИРІШЕНО** — RTC WUT + Vcap-енергогейт (ADR §1.10, founder 2026-06-07); 👤 лишається bench bring-up: LSE clock-tree + `MX_RTC_Init` (календар/WUT) + верифікація `Wall_Seconds_Now` на кремнії (RUNBOOK §4).

> **In-silico L4 (2026-05-25; переглянуто 2026-09-27, [`00_07` E.63](00_07_Action_Plan_Tracker)):** колишній висновок «модель підтверджує `BASELINE_DELTA_T_S=60` фізично обґрунтованим» спростовано — він тримався на заглушці ціни циклу 5 мДж без сон-члена, у 8.5 раза нижчій за канон-ланцюг [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power). Зі зведеною ціною навіть pH-7.4 лабораторна стеля на купоні 2 см² дає `delta_t` понад 60 с у кожному сценарії, тож 60 с лишається лише дефолт-аргументом хаос-частини ([`03_04`](03_04_mruby_Lorenz_Attractor)), а не фізичним твердженням. Числа — [`in_silico/SUMMARY.md` §L4](protocols/ebfc/in_silico/SUMMARY.md) (машинний дім — `cache/kinetics/delta_t_lookup.json` + `monte_carlo.json`); деталі → [`01_03 §3.4 L4`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell).

**АЦП (два читання з явним вибором каналу — `Soldier_Adc_Read`):**

```c
// Канал стає на ранг 1 перед кожним стартом (MX_ADC_Init: ADC_SCAN_DISABLE)
(void)Soldier_Adc_Read(ADC_CHANNEL_TEMPSENSOR, &internal_temp);

uint16_t vrefint_raw = 0;   // VREFINT → справжні мВ VDDA (проксі заряду — FW.50 нижче)
if (Soldier_Adc_Read(ADC_CHANNEL_VREFINT, &vrefint_raw))
    vcap_voltage = Adc_Vdda_Mv(vrefint_raw, *(volatile const uint16_t*)ADC_VREFINT_CAL_ADDR);
```

> ⚠️ **Чому канал обирається явно (2026-10-09, знайдено розвідкою образу для mini — [`00_07` FW.46](00_07_Action_Plan_Tracker)).** Доти цикл читав два канали двома парами `HAL_ADC_Start`/`Poll`/`Stop` без вибору каналу, а пояснення тут казало, що роздвоєння «запобігає deadlock». Насправді ж воно покладалося на те, що позиція в послідовності ранґів переживе `HAL_ADC_Stop`, а той щоразу вимикає АЦП (ADDIS). Такої пам'яті не обіцяють ні HAL WL, ні RM0461; якби її не було, друге читання знову брало б температуру, і `vcap` рахувався б із неї. Тепер `Soldier_Adc_Read` ставить канал на ранг 1 перед кожним стартом, і відповідь кремнію на те питання ролі не грає. **Межа покриття:** `main.c` хост не компілює — лише ARM compile-lane; чи читає кожен виклик саме названий канал, покаже стенд (RUNBOOK §3.4).

> **🟡 `vcap_voltage` = VDDA-проксі у справжніх мВ [FW.50, рішення founder 2026-06-12].** До фіксу сирий 12-bit VREFINT-відлік (~1500) трактувався ЯК мілівольти: RX-вікно (`VCAP_LISTEN_THRESHOLD=2800`) **не відкривалось ніколи** — на кремнії Солдат був би глухий до OTA/mesh/time-sync/ротації ключа, а Vcap-енергогейти працювали з фейкових величин. Тепер call-site конвертує через `Adc_Vdda_Mv()` (factory VREFINT-cal, `firmware/common/adc_convert.h`, One-Home + host-тести): `vcap_voltage` = чесні мВ VDDA (≈3300, поки buck тримає; сідає лише при брауноуті). Семантика гейтів до живого Vcap-каналу — **порогів на цій шині ТРИ на ЧОТИРЬОХ сайтах порівняння** (перелік [ARCH.99] 2026-08-13 був неповний на один, дописано 2026-09-27; ⊕ 2026-09-29 fauna-гейт пішов із пʼєзо, HW.30): «слухай» (`VCAP_LISTEN_THRESHOLD=2800`) = живлення здорове (3300 > 2800 — вухо відкрите), і той самий поріг несе енергогейт FC-hiwater (`Fc_Hiwater_Advance`, CCM-гейтований, дрімає) — він пропускає Flash-advance завжди; CAD panic-преамбула (`CAD_PANIC_PREAMBLE_VCAP_MIN_MV=4500`) чесно зачинена (стеля VREFINT-тракту < 4500), extended-half fail-closed — а сам panic-транспорт з HW.30 викликача не має; 🔴 **cold-TX-defer (`COLD_TX_DEFER_VCAP_MV=4000`) — істинний завжди, тож кон'юнкція `Should_Defer_TX` згортається до самої температури** (§1.8а). **Залишок hardware:** VREFINT міряє VDDA, НЕ напругу EDLC — реальний Vcap = окремий ADC-канал з дільником за TPS22860-гейтом (⚖️ делеговано 2026-09-27; цільовий тракт = вузол VBAT/VSTOR BQ25570 через дільник — `VBAT_SEC` є піном BQ25505, не BQ25570; [`02_01 §7.1`](02_01_Hardware_Architecture_and_BOM)); конверсія та сама (`Adc_Raw_To_Mv`, дільник-параметр), номінали узгодити з [`02_03`](02_03_BQ25570_MPPT_Nano_Power) — трекінг [`00_07` — FW.50](00_07_Action_Plan_Tracker).

**HRNG (Chaos Seed):**
```c
HAL_RNG_GenerateRandomNumber(&hrng, &chaos_seed);
```

Апаратний генератор випадкових чисел на основі теплового шуму кристала. **[SEC.11 / FW.30]** `chaos_seed` більше НЕ використовується для Атрактора Лоренца — початковий стан `(x₀,y₀,z₀)` деривується з per-device K_seed (Flash `FLASH_SEED_ADDR`) через HKDF/HMAC. `chaos_seed` залишається для mesh anti-pingpong, TX jitter та CoAP nonce.

**BME280 (мікроклімат — HW.32, ADR [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM)):**
```c
// ЕСКІЗ call-site (не код дерева): BME_PWR_* · bme_ops · bme_io · bme_calib — імена
// майбутнього HAL-глю в main.c; функції Bme280_* — справжній API firmware/common/bme280.h.
// Гейтований TPS22860: GPIO ON → settle → forced-mode read → GPIO OFF (idle ~10 нА).
// Клімат змінюється повільно → опитування раз на N пробуджень (climate_due), не щоцикл.
// Bme280_Read_Calib(&bme_ops, bme_io, &bme_calib) — раз при bring-up (NVM незмінна).
if (climate_due) {
  Bme280_Raw raw;
  HAL_GPIO_WritePin(BME_PWR_PORT, BME_PWR_PIN, GPIO_PIN_SET);   // power-gate ON
  int rc = Bme280_Forced_Read(&bme_ops, bme_io, &raw);  // I²C, ~10 мс @ ~700 µA
  HAL_GPIO_WritePin(BME_PWR_PORT, BME_PWR_PIN, GPIO_PIN_RESET);  // OFF
  if (rc == BME280_OK) {
    int32_t t_fine, temp_centi = Bme280_Compensate_T(&bme_calib, raw.adc_T, &t_fine);
    uint32_t rh_q10 = Bme280_Compensate_H(&bme_calib, raw.adc_H, t_fine);
    vpd_index = Bme280_Vpd_Index_From_Compensated(temp_centi, rh_q10);  // → 1 байт
  } else {
    vpd_index = 0x00;  // сентинель «немає BME280», ніколи попереднє значення (контракт bme280.h)
  }
}
```

> **[HW.32] Реалізовано як pure-модуль `firmware/common/bme280.h`** (компенсація datasheet Bosch §8.2 + VPD FAO-56, host-golden `firmware/test/test_bme280.c` — int-шлях звірено проти незалежної float-копії §8.1). Транспорт forced-mode (`Bme280_Read_Calib` / `Bme280_Forced_Read`) — у тому ж `bme280.h` через шов `Bme280_Ops`, host-тестований проти фейка регістрів (`make -C firmware/test bme280`); на стенді лишаються HAL-опси (`HAL_I2C_Mem_Read/Write`, адреса 0x76/0x77) і живе читання; SENSE call-site вшивається разом із **CCM-флипом** (`FW2_CCM_ENABLED`), бо `vpd_index` живе тільки у CCM wire-rev2 (байт 19) — у транзитному 16B-кадрі місця нема. Канон формули — [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM).

> **VPD (Vapor Pressure Deficit)** обчислюється на вузлі з t°+RH і пакується **1 байтом** (канонічний дім — **CCM wire-rev2 byte 19 `vpd_index`**, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) wire-budget ledger; ⚠️ до BME280 байт несе SEC.20-звіт відкату — єдиний сигнал відкату в CCM-ері, тож call-site VPD іде лише разом із переїздом звіту в байт 11 — пакет wire-rev2.2 (⚖️ 2026-10-08), реалізація [`00_07`](00_07_Action_Plan_Tracker) FW.66; у транзитному 21B-кадрі VPD НЕ передається — байт 14 там належить gossip-freeze) як **прямий погодний confounder** — backend-гейт, що за задумом не штрафує за погоду, сьогодні wired no-op і структурно інертний ([`04_02`](04_02_Business_Logic_and_Services), врізка VPD-гейта; False-Slashing guard, [`05_05 §6/§7`](05_05_Slashing_and_Risk_Policy)). Сирі RH/тиск (для NaaS клімат-оракула, [`00_04`](00_04_Nature_as_a_Service_Contracts)) — у періодичному **climate frame** (FW.2 24B CCM extended payload; транзитний 16B-кадр місця не має). Тригер climate frame: кожні N uplink'ів або значна Δтиску (раннє попередження про шторм). Енергія: за TPS22860-гейтом ≈8нА avg ([`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM), [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)). 🚨 **DCI-guard:** BME280-дані (VPD/RH/тиск) **НЕ** входять у входи Атрактора Лоренца (ті — temp/acoustic; delta_t і vcap з E.63 Z не рухають) → firmware↔backend bit-identity не зачіпається.

**RSSI (Канал 5 — Zero-Energy Фенологія):**

> RSSI не вимірюється Soldier напряму. Значення RSSI (`rssi_byte`) автоматично фіксується на стороні **Queen (Gateway)** при кожному прийнятому пакеті SX1262. Без жодного додаткового датчика на дереві або мікроватів витрат:
>
> - **Взимку** (голе дерево): RSSI ≈ −80 dBm (сигнал майже ідеальний)
> - **Навесні при розпусканні листя**: RSSI падає до ≈ −105 dBm — соковите листя (80% вода) поглинає 868 МГц хвилі
> - **Аналіз на сервері**: сезонна динаміка RSSI → індекс листяного покриву → фенологічні дані для Proof of Growth
>
> Фізика: довжина хвилі 868 МГц (λ ≈ 34.5 см) ефективно поглинається полярними молекулами H₂O. Зміна RSSI на 20-25 dBm між зимою і піком вегетації — надійний сигнал стану біомаси.

---

### 1.5 Phase 1.5 — ⛔ знято разом із пʼєзо (HW.30)

⛔ **Фази 1.5 у циклі Солдата немає з 2026-09-29** — пʼєзо зрізано (⚖️ founder, [`02_01 §6`](02_01_Hardware_Architecture_and_BOM)), і з ним пішли EXTI0/PA0-пробудження, `vibration_detected`, аудіо-вікно TIM2 + ADC-DMA (`MX_TIM2_Init` · `MX_DMA_Init` · `HAL_ADC_ConvCpltCallback`), аудіо-буфери, виклик інференсу й пороги DR13/DR14. Модель, INT8-рантайм і log-mel-контракт лишаються активом без носія на вузлі ([`03_03`](03_03_TinyML_Acoustic_Inference) паркований); HAL-урок вікна (`HAL_ADC_Start_DMA` без злінкованого DMA — HardFault, не `HAL_ERROR`) — `firmware`-гоча #14. ⛔ Не повертати акустику на Солдата: звук — властивість ділянки, а не дерева, і чесний носій, якщо знадобиться, — прилад Королеви ([`00_07`](00_07_Action_Plan_Tracker) HW.52 — далека опція, не план).

---

### 1.6 Phase 2: Bit-Pack (lora_payload[16])

Фаза формує 16-байтний payload для AES-128 (LoRa, post-ARCH.42) і віддає його Фазі 3. **Тут — сама фаза: коли вона біжить і яка критична секція її захищає.**

> 🏠 **One-Home: побайтова розкладка й бітова семантика — НЕ тут.** Wire-структура шифрованого пакета (усі 16 байтів, обидві ери — 16B ECB і 30B CCM rev2.1) — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security), і саме туди реєстр [`00_06 §2`](00_06_SSOT_Documentation_Standard) призначає байт-позиції. Логіка й пакування самого StatusByte (байт 10) — [`03_04`](03_04_mruby_Lorenz_Attractor). ⚖️ **Присуд про напрямок 2026-09-04 (DOC-T.98):** кільце «дім віддає байт 11 сюди ⊥ реєстр віддає байт-позиції туди» розвʼязано на користь [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) — його Мета дослівно оголошує «структуру зашифрованих пакетів», тоді як Мета цієї сторінки є «життєвий цикл · переходи сну · ISR», і байтової мапи в ній немає.
>
> ⛔ **Не відновлювати таблицю тут — виміряно й відкинуто.** Поки копій було дві, вони розійшлися на трьох байтах (12/13/14), і **кожна сторона мала свою половину правди**: тут була точна семантика `FwContractReport` і `gossip_ts_lsb`, а в домі — хибне «`Vcap` = напруга суперконденсатора», тобто порушення інваріанта [ARCH.99], який `CLAUDE.md §6` тримає інлайн. Обидві половини зведено в дім тим самим проходом.

Після пакування:

```c
// [FW.28] Атомарне зчитування — критична секція проти PVD/panic-контекстів,
// що читають лічильник. [ARCH.102] Знімок БЕЗ обнулення: споживає лише
// успішна передача (Фаза 4), відніманням знімка.
__disable_irq();
uint8_t acoustic_snapshot = acoustic_events;
__enable_irq();

lora_payload[7] = acoustic_snapshot;
```

**Насичення acoustic_events (FW.22) та атомарне зчитування (FW.28):** лічильник `acoustic_events` — **`uint8_t`** із saturating increment:
```c
uint8_t acoustic_events = 0;                        // [FW.22] Saturating uint8_t
if (acoustic_events < 255) acoustic_events++;        // Saturating increment (no overflow)
```
При пакуванні — атомарне зчитування (FW.28); споживання перенесено на успішний TX ([ARCH.102](00_07_Action_Plan_Tracker)):
```c
// [FW.28] __disable_irq() guard — критична секція проти читачів з PVD/panic
__disable_irq();
uint8_t acoustic_snapshot = acoustic_events;         // [ARCH.102] без обнулення
__enable_irq();
lora_payload[7] = acoustic_snapshot;                 // Direct assignment (no clamping needed)
```
FW.22 переміщає захист від overflow на рівень інкременту (тип `uint8_t` фізично не може перевищити 255). FW.28 гарантує, що подія не втрачається між читанням і пакуванням. **[ARCH.102]** Обнулення тут більше НЕ стоїть: доти воно спрацьовувало на кожному проході циклу — до того, як стане відомо, чи кадр узагалі поїде, — тож подія, зафіксована в циклі з відкладеним TX або grace-hello, зникала, а на дроті величина зводилась до 0/1. Тепер лічильник — **ледж**: споживає рівно доставлене (`firmware/common/acoustic_ledger.h`), решта доживає до наступного успішного uplink'а й переживає STOP2 у DR0.

> ⊕ **2026-09-29 ([`00_07`](00_07_Action_Plan_Tracker) HW.30): інкременту вище в прошивці більше немає** — писачем лічильника був інференс, і він пішов разом із пʼєзо. `acoustic_events` завжди 0, тож байт 7 несе 0 або сентинел часу `0xFE` (ARCH.41-B); знімок і леджер у коді лишились; ECB-кадр лишається як є, а CCM-байт віддає пакет wire-rev2.2 ([`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security), реалізація [`00_07`](00_07_Action_Plan_Tracker) FW.66).

---

### 1.7 Phase 3: mruby Lorenz Attractor Bio-Contract

```c
mrb_state *mrb = mrb_open();         // ОДНОРАЗОВО при старті
mrb_load_irep(mrb, lorenz_bytecode); // Завантажуємо байт-код

// В кожному циклі:
int arena_idx = mrb_gc_arena_save(mrb);   // Зберігаємо стан GC
mrb_value result = mrb_funcall_argv(mrb, ...);
if (!mrb->exc) {
    lora_payload[10] = (uint8_t)mrb_fixnum(result);
} else {
    lora_payload[10] = BIO_STATUS_VM_ERROR; // 0x60: status=3=vm_error (НЕ tamper — SLASH-1; наш софт-збій)
    mrb->exc = NULL;
}
mrb_gc_arena_restore(mrb, arena_idx);     // Відновлюємо GC arena
mrb_full_gc(mrb);                         // [FW.55] VM вічна → повний GC щопробудження:
                                          // купа до живого мінімуму ДО сну (не reactive
                                          // OOM→GC→retry). Деталь WHY — коментар main.c + §12.7
```

**Вибір байт-коду при старті:**
```c
uint32_t* flash_check = (uint32_t*)MRUBY_CONTRACT_FLASH_ADDR; // 0x0803F000
if (*flash_check == 0x45544952) { // "RITE" в little-endian
    current_lorenz_bytecode = (uint8_t*)MRUBY_CONTRACT_FLASH_ADDR; // OTA-оновлений
} else {
    current_lorenz_bytecode = (uint8_t*)lorenz_bytecode; // Вбудований
}
```

> Детальна математика Атрактора Лоренца (σ=10, ρ=28, β=8/3, 250 ітерацій) описана в [`03_04`](03_04_mruby_Lorenz_Attractor).

---

### 1.8 Phase 4: AES-128-ECB Encrypt + LoRa TX [post-ARCH.42]

```c
// Anti-Collision Jitter (0-500 ms)
HAL_RNG_GenerateRandomNumber(&hrng, &random_jitter);
HAL_Delay(random_jitter % TX_JITTER_MAX_MS);

// Mesh Relay (відправляємо чужий пакет першим)
if (has_mesh_relay) {
    HAL_Delay(Lora_Phy_Send(mesh_relay_payload, 16, LORA_PHY_PREAMBLE_SYMBOLS));
    has_mesh_relay = 0;
}

// Шифруємо власні дані
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)lora_payload, 4, (uint32_t*)encrypted_payload, 1000);
HAL_Delay(Lora_Phy_Send(encrypted_payload, 16, LORA_PHY_PREAMBLE_SYMBOLS));
```

> 🔴 **Кожен `Send` дочікує свого ефіру, перш ніж радіо дістане наступну команду** ([`00_07`](00_07_Action_Plan_Tracker) FW.61): `Lora_Phy_Send` повертає ефір кадру + запас, і саме стільки чекає Фаза 4 — інакше `Radio.Rx` Фази 4.5 обірвав би телеметрію за мікросекунди після старту. Механізм, носії й стеля — дім профілю [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) (врізка під airtime-таблицею).

**Mesh Relay:** Якщо `has_mesh_relay == 1`, Soldier відправляє чужий зашифрований пакет (зі зменшеним TTL) перед власним. Це забезпечує ретрансляцію для дерев поза прямою видимістю Queen.

#### 1.8а Cold-Temperature TX Deferral (FW.10)

> **Кенозис холодом:** при `temp < -15°C` AND `vcap < 4000 mV` Soldier свідомо пропускає TX-вікно (Should_Defer_TX повертає 1). Логіка — захистити EBFC від глибокої розрядки в умовах, коли ксилема замерзла і регенерація заряду тимчасово зупинена. Поріг температури суворо `<` (не `<=`), тому рівно `-15°C` не вважається холодом — це freeze-contract проти випадкової зміни оператора порівняння.

> 🔴 **[ARCH.99] Vcap-половина кон'юнкції у полі не розрізняє — і це ЧЕТВЕРТИЙ гейт на шині VDDA, чиє виродження доти не було оголошене.** `vcap` тут — той самий `Adc_Vdda_Mv()` ([FW.50](00_07_Action_Plan_Tracker) вище), а шину BQ25570 тримає стабілізованою на 3.3 В ([`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)), тож `< 4000` істинне завжди, поки buck живий, і предикат зводиться до `temp < -15°C`. Клауза «холодне, але заряджене дерево передає» — рядки таблиці нижче з vcap 4001/5000/5500 — недосяжна за побудовою: **host-тести розрізняють, поле ні.** ⊕ Сусідні три гейти на тій самій шині свою виродженість називають (listen 2800 «вухо відкрите» · fauna 4500 «свідомо fail-closed» · CAD panic-преамбула 4500 «extended-half чесно fail-closed») — цей мовчав, а його заголовок стверджував протилежне. Напрямок безпечний (вузол мовчить там, де міг би передати: втрата зимової телеметрії, не шкода залізу); панічний кадр іде окремою функцією повз цей предикат (⊕ 2026-09-29, HW.30: fauna-гейт пішов із пʼєзо, тож сусідів лишилось два, а панічна функція лишилась без викликача). Присуд ARCH.99 ратифіковано (варіант A — дзеркало в прошивці лишено свідомо; архівний рядок ARCH.99 у [`00_07`](00_07_Action_Plan_Tracker)); відкрита робота — живий Vcap-канал: топологію делеговано 2026-09-27 (TPS22860-гейт, [`02_01 §7.1`](02_01_Hardware_Architecture_and_BOM)), каналу ще немає ([`00_07`](00_07_Action_Plan_Tracker) FW.50).

**Граничні випадки** (`firmware/test/test_soldier_logic.c` §FW.10, 13 host-тестів):

| Сценарій | T (°C) | vcap (mV) | Defer? | Тест |
|---------|--------|-----------|--------|------|
| Звичайна робота | +20 | 3500 | ❌ | `test_tx_defer_warm_and_low_vcap` |
| Boundary @ -15°C, low vcap | -15 | 0 | ❌ | `test_tx_defer_boundary_minus15_zero_vcap` (✨ 2026-05-03) |
| Холод -16°C, low vcap | -16 | 3999 | ✅ | `test_tx_defer_minus16_low_vcap` |
| Холод -16°C, threshold vcap | -16 | 4001 | ❌ | `test_tx_defer_boundary_vcap_4001` |
| Холод + battery-backed | -30 | 5000 | ❌ | `test_tx_defer_cold_but_very_high_vcap` |
| Екстремальний холод + battery | -40 | 5500 | ❌ | `test_tx_defer_extreme_cold_high_vcap_battery_backed` (✨ 2026-05-03) |
| Warm -5°C + low vcap | -5 | 1000 | ❌ | `test_tx_defer_warm_minus5_low_vcap` (✨ 2026-05-03) |

> **Cross-ref:** `00_07 FW.10` — закрито через цю секцію.

---

### 1.9 Phase 4.5: RX Window (OTA + Mesh)

Відкривається **тільки** якщо `vcap_voltage > 2800 mV` (достатньо енергії) — і лише ПІСЛЯ того, як власний кадр Фази 4 відлетів цілком (§1.8).

```
Radio.Rx(500ms) → Максимум 600ms очікування
       ↓
[якщо lora_rx_flag == 1]
       ↓
AES-128-ECB Decrypt → decrypted_rx_payload [post-ARCH.42][]
       ↓
Сценарій А: decrypted

_rx_payload[0] == OTA_MARKER (0x99)
  → Валідація мінімального розміру (>= 6 байт)
  → chunk_idx, total_chunks (big-endian)
  → total-mismatch streak (3 поспіль чужих total → wipe мертвої кампанії) [FW.53]
  → Bounds check: offset + chunk_size <= 1024
  → Dedup check: ota_chunk_received[chunk_idx]
  → memcpy → ota_buffer[]
  → Якщо всі чанки → чекати трейлер печатки 0x9B (7 блоків) → Ota_Seal_Try_Finalize:
    CRC32 (хвіст wire-потоку: OtaPackagerService паддить bytecode до
    (len+4) % 11 == 0 і додає CRC32 BE — §4.6) + Ed25519-печатка під KPUB
    (FW.23, [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning))
    → версія > high-water 0x15 (SEC.20 anti-rollback, строго `>`)
    → Write to Flash → commit high-water → NVIC_SystemReset()

Сценарій Б: incoming_lora_size == 16 (Mesh Relay)
  → TTL > 0?
  → incoming_did == tree_did? → break (власне відлуння)
  → recent_mesh_dids[3] check (anti-pingpong, FW.21: 3 слоти DR8/DR9/DR11)
  → Decrement TTL → Re-encrypt → store mesh_relay_payload
  → has_mesh_relay = 1
```

#### Проблема Рандеву та Поточне Рішення

> **Проблема Рандеву (Rendezvous Problem):** Якщо Солдат прокинеться і "вистрілить" пакетом, а приймач у цей момент перебуває в STOP2, пакет розчиниться в ефірі. SX1262 у режимі RX споживає ~4.5 мА — неприйнятно для EBFC біобатарейки.

**Поточне рішення (TRL 6)** складається з двох механізмів:

1. **Queen Always-On:** Королева має зовнішнє живлення (сонячна панель / акумулятор) і **ніколи не спить**. Її SX1262 завжди у `Radio.Rx(LORA_RX_INFINITE)`. Будь-який Солдат у радіусі 150–200 м може передати дані в будь-яку секунду — Королева завжди зловить. Це вирішує Рандеву для прямої видимості.

2. **Post-TX RX Window (600 мс):** Солдат після власного TX слухає ефір протягом 600 мс (`LORA_RX_LOOP_MS`), але **тільки** якщо `vcap > 2800 mV`. Це вікно дозволяє:
   - Прийом OTA-чанків від Королеви ("Рефлекторний Постріл")
   - Прийом mesh-пакетів від інших Солдатів для ретрансляції

**Обмеження:** Mesh relay між Солдатами працює **стохастично** — лише якщо два Солдати випадково мають перетин TX/RX вікон. Без синхронізації годинників (FW.20) та TDMA (ARCH.26) це ненадійно.

**Цільова архітектура (TRL 7+)** — три рівні Рандеву:

| Рівень | Механізм | Статус | Задача |
|--------|----------|--------|--------|
| L1: Зона Королеви | `Radio.Rx(LORA_RX_INFINITE)` — Queen завжди слухає | ✅ Реалізовано | — |
| L2: Синхронні Вікна (TDMA) | RTC-координоване пробудження: кожні N хвилин, ~2 сек RX. Queen beacon → Time Sync → спільний розклад | 🟡 Host-half (2026-07-02): слот-розкладка у маяку + parse + математика вікон/слотів (`common/tdma_schedule.h`, wire-дім [`03_02 §5а.2а`](03_02_Queen_Gateway_Firmware)) INERT за `ARCH26_TDMA_ENABLED`; фліп = bench WUT-армінг (SEC.15/FW.49). Енерго-політика ролей — ⚠️-блок нижче | [ARCH.26](00_07_Action_Plan_Tracker), [FW.20](00_07_Action_Plan_Tracker) |
| L3: CAD Preamble Detection | SX1262 `Radio.StartCad()` — короткий «нюх» ефіру на LoRa-преамбулу, **прив'язаний до TDMA-вікон L2 / грубого інтервалу** (НЕ щосекунди — див. ⚠️ нижче). Миттєвий PANIC (з HW.30 без викликача — транспорт лишено для [`00_07`](00_07_Action_Plan_Tracker) HW.52) ініціює **відправник** через extended-preamble (preamble sampling), а не постійний RX приймача. | 🟡 Host-half (2026-07-02): роль-гейтований нюх + «останній зойк» PANIC (973 симв @SF9, дворівневий V_cap-гейт + обов'язковий restore-8) — математика/пороги `common/cad_sniff.h`, глю INERT за `ARCH26_CAD_ENABLED` (окремий від L2-гейта); фліп = bench WUT-армінг @ T_sniff + PPK2 CAD-профіль. Енерго-double-bind → [`02_03 §9.10`](02_03_BQ25570_MPPT_Nano_Power) | [ARCH.26](00_07_Action_Plan_Tracker) |

> **⚠️ Енергетична корекція CAD (2026-05-28):** «прокидатися ~2 мс щосекунди» **недооцінює вартість** і енергетично нежиттєздатне для µW-вузла на EBFC. Реальний цикл — не лише радіо: wake MCU зі STOP2 → init SPI → конфіг SX1262 на CAD → очікування результату → знову сон. Активна фаза ≈ кілька мс при ~5 мА (MCU+SX1262), тобто десятки–сотні µJ **на один цикл**. ×86,400 циклів/добу → одиниці джоулів/добу, що **багатократно перевищує** і добовий харвест EBFC, і запас EDLC (½·0.47F·3.3² ≈ 2.56 J). Тому CAD НЕ можна робити щосекунди: правильно — CAD **у синхронних TDMA-вікнах L2** (кожні ~15 хв) або з грубим інтервалом; для миттєвого PANIC — **відправник** подовжує преамбулу довше за період сну приймача (LoRa preamble sampling), і низько-duty-cycle CAD-приймач її зловить. Енергобюджет CAD розкладено у [`02_03 §9.10`](02_03_BQ25570_MPPT_Nano_Power): double-bind нюх↔преамбула на чистому EBFC несумісний → нюх = привілей surplus-Провідника, EBFC-відправник мінімізує свій бік (baseline-пара 3 с ↔ 4 с).

> **⚠️ Та сама арифметика обмежує і L2-вікна (host-half знахідка, 2026-07-02):** суцільний RX у кожному вікні — 2 с × ~4.5 мА × 3.3 В ≈ **30 мДж/вікно**, ×96 вікон/добу (15-хв період) ≈ **2.9 Дж/добу** — у рази більше добового EBFC-харвесту. Тому L2-розклад НЕ означає «всі слухають»: **політика ролей** — повний RX у вікні дозволений лише **Провіднику** (ARCH.27, надлишок енергії); рядовий Солдат використовує розклад як **TX-таймінг** (slotted uplink — слот `DID % slot_count`, примітив для FW.27-A ACK-aggregation) і як каденцію майбутнього **L3 CAD-нюху** (~сотні µJ/вікно ≈ десятки мДж/добу — вміщається). Wire-формат розкладки (байти 5..8 маяка) + стеля фазової точності ±1 с + `ts_frac`-апгрейд — [`03_02 §5а.2а`](03_02_Queen_Gateway_Firmware) (один дім, тут не дублюється).

---

### 1.9.1 Mesh Relay Anti-Pingpong Algorithm [DOC.2]

> **SSOT:** алгоритм описано тут; персистенція кешу — у §2 (RTC Backup Domain Layout, регістри `DR8 / DR9 / DR11`).

Mesh-relay у §1.9 повторює прийнятий 16-байтний шифрований пакет від іншого Солдата, але **тільки якщо** його DID не "вже бачили" у недавньому минулому. Без цього два Солдати у радіусі прямої видимості один одного утворюють `pingpong`-цикл (TTL зменшується до 0, але кожна сторона ретранслює ту саму DID нескінченно за рахунок дрейфу годинника).

> **⚠️ Передумова (per-device crypto):** релей розшифровує чужий пакет → `TTL--` → перешифровує — коректно лише за **спільного** LoRa-ключа (ECB-ера). **CCM-ера (FW.2 (в), 2026-07-03): Сценарій Б гейтовано `#if !FW2_CCM_ENABLED`** — телеметрія/panic сусідів = air-кадри (30B rev2.1) на per-device session-ключах (гинуть на RX-guard до декрипту), TTL живе у ciphertext → **star-only прийнято** (ухвала гейту (а), [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); mesh повертається лише з wire-rev3-класом (cleartext TTL/адресація + opaque pass-through) → [`00_07` — ARCH.43](00_07_Action_Plan_Tracker) (mesh-вісь).

> **⚠️ Стеля масштабу (незалежна від crypto-ери):** «>1000 дерев через одну Queen» mesh НЕ дає навіть в ECB-ері: (1) `DEFAULT_TTL=3` → ≤3 хопи ≈ ~450–600 м ефективного радіусу; (2) один relay-буфер store-and-forward — релей повторює кадри поштучно, агрегації немає; (3) Queen CIFO ~100/~200 записів, overflow ~30 хв без Starlink ([`02_05 §2.1`](02_05_Queen_Hardware_and_Starlink)). Масштаб до тисяч дерев = більше Queen, не довший mesh ([`00_07` — ARCH.1](00_07_Action_Plan_Tracker) fractal L2 / ARCH.10 Q2Q).

> 🔬 **Math-обґрунтування TTL-глибини (ARCH.74, Monte Carlo — `tools/mesh/ttl_flood_monte_carlo.py`; N=100 [1 Королева always-on + 99 Солдатів], disk-радіо-модель r=150 м/1 км² кластер, q∈{0.20,0.25,0.30} одночасних відмов, TTL 1..7, 10⁴ реалізацій/топологію RGG+ER):** на **реалістичній просторовій топології (RGG)** `P_delivery` НІКОЛИ не досягає цілі 0.99 у межах TTL≤7 для жодного q (TTL=3: ≈0.27–0.29 · TTL=5 [=`PANIC_TTL`]: ≈0.51–0.59 · TTL=7: ≈0.64–0.74); ER null-модель (та сама щільність, БЕЗ просторової локальності) досягає порогу лише при q≤0.25/TTL=5, і не досягає його НІКОЛИ при q=0.30. 🔑 **Кількісно підтверджує стелю масштабу вище:** брак «довгих» ребер у фізичному radio-graph (на відміну від ER) робить глибший TTL недостатнім лікуванням — лік і далі fractal L2/більше Queen, не довший TTL. ⚠️ **Це НЕ виправдання живих `PANIC_TTL=5`/`DEFAULT_TTL=3`** — той шлях сьогодні star-only (передумова вище: CCM-ера робить Сценарій Б мертвим `#if !FW2_CCM_ENABLED`); ці числа — ARCH.43-readiness math-фундамент для mesh, який повертається post-TRL 6 разом із wire-rev3. Ідеалізації (isotropic disk-радіо без крон-затінення/рельєфу, рандомізовані щореалізації позиції) названі в докстрінгу скрипта — результати є оптимістичною верхньою межею, не польовою валідацією. Percolation-теорія (`q_c`/Markov) лишається Open Research ([`06_08`](06_08_Resilience_and_Failover_Policy)).

**Структура кешу (LIFO, 3 слоти, FW.21):**

| Слот | RTC регістр | Заповнюється коли |
|------|-------------|-------------------|
| `recent_mesh_dids[0]` | `DR8` | LIFO push — найновіший acceptance |
| `recent_mesh_dids[1]` | `DR9` | shift з [0] |
| `recent_mesh_dids[2]` | `DR11` | shift з [1] (eviction) |

> **Чому 3 слоти, а не 8 (як було у v1.x):** EMA-блок `FW.21` ([§13](#-13-ema-exponential-moving-average-на-soldier--fw21-)) забрав DR10/DR12 під `ema_delta_t_x100` і запакований `ema_vcap_x10`. Скорочення кешу до 3-х слотів вистачає для типової щільності 2-3 сусідні Солдати в радіусі — більше слотів давало б маргінальний appendix, але блокувало EMA.

**Псевдокод (виконується у фазі 1.9, гілка "Сценарій Б: Mesh Relay"):**

```text
on_lora_rx(payload, did_from_packet):
    if ttl <= 0:                              return  # видалити: пакет догорів
    if did_from_packet == tree_did:           return  # власне відлуння
    for slot in 0..2:                         # anti-pingpong cache
        if recent_mesh_dids[slot] == did_from_packet:
            return                            # вже ретранслювали → drop
    # acceptance: записуємо у LIFO (slot[2] витісняється)
    recent_mesh_dids[2] = recent_mesh_dids[1]
    recent_mesh_dids[1] = recent_mesh_dids[0]
    recent_mesh_dids[0] = did_from_packet
    decrement(ttl)
    re_encrypt(payload)                       # AES-128-ECB з нашим ключем [post-ARCH.42]
    has_mesh_relay = 1                        # → буде відправлено у фазі 4
    persist_to_rtc(DR8, recent_mesh_dids[0])
    persist_to_rtc(DR9, recent_mesh_dids[1])
    persist_to_rtc(DR11, recent_mesh_dids[2])
```

**Властивості:**
- **LIFO eviction** замість FIFO/LRU обрано через простоту (3 mov-операції замість циклу пошуку).
- **Persistence через сон:** кеш лежить у RTC backup domain, а той живий і в STOP2, і в цільовому Standby. 🔴 **Другий стан — «знеструмлення при живому RTC Backup» — у НАШОМУ залізі не існує:** окремого VBAT-джерела під backup-домен немає (coin cell у BOM Солдата відсутній), домен живиться від того самого buck'а, тож будь-яка справжня втрата живлення є full power-loss і кеш скидається у нулі — дзеркало [§13.3](#133-persistence--rtc-backup-registers-dr10--dr12-packed) («при втраті живлення RTC backup domain очищається → cold-start»). Розрізняти два стани має сенс лише як опис МОЖЛИВОСТІ кремнію, не нашої плати. При full power-loss — захист від ретрансляції власних пакетів = порівняння `did_from_packet == tree_did`, де `tree_did` деривується з UID на кожному boot ([§7](#-7-did-derivation-імя-з-кремнію), FW.54 — DR7 звільнено, у RTC зберігати нічого).
- **Невразливість до DID-spoofing у короткому вікні:** якщо зловмисник інжектує пакети з DID реального сусіднього дерева, перший пройде, але всі наступні будуть drop'нуті. Atttacker мусить сатурувати весь radio space — ⊕ з HW.30 цього не показує ні `acoustic_events` (завжди 0), ні panic-TX (SEC.10; викликача немає).

---

### 1.10 Phase 5: Deep Sleep — ціль Standby з RTC на LSE без SRAM2 (⚖️ 2026-10-05); відвантажено — STOP2

> ⚖️ **Ціль сну — Standby з RTC на LSE (low drive), без утримання SRAM2: ратифіковано founder 2026-10-05** (поправка Сценарію C; повна форма — врізка «⚖️ Режим сну» [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power), трекер — [`00_07`](00_07_Action_Plan_Tracker) FW.54). Серед режимів, що тримають BOR і RTC на LSE, клас ≈ 300 нА дає лише він (≈ 0.31 µA на 3.3 В — різниця рядків DS13105 Табл. 49; окремого рядка паспорт не має). **Відвантажена прошивка до фліпу FW.54 спить у STOP2** (`HAL_PWREx_EnterSTOP2Mode`, 1.07 µA). Шлях Standby — за гейтом `FW54_STANDBY_ENABLED` (0): рішення «пробудження зі Standby ⊥ холодний старт» за C1SBF і маркером DR19 та порядок входу — `firmware/common/standby_wake.h` (host-тест `make -C firmware/test standby_wake`), проводка — `firmware/soldier/main.c` (гілка на старті, обидва місця сну — цикл і PVD), compile-lane `hal_check_ccm` збирає її увімкненою проти WL-HAL (зроблено 2026-10-05). **Фліп чекає трьох умов:** ⚖️ RAM-стану FW.54 — без нього RAM-only лічильники пробуджень і `soldier_unix_ts` щопробудження стартували б з нуля, і прохання синхронізації замовкло б; пін-мапи ключів навантажень (`.ioc`, FW.46); виміряного сну на стенді (RUNBOOK 3.1). ⚖️ **Сам фліп — гейт першого польового деплою: ДЕЛЕГОВАНО 2026-10-06** (подання 2026-10-05, рекомендація «так» незмінна; founder того дня делегував ратифікацію відкритих присудів за рекомендацією). **Підстава** (як подано): у відвантаженому STOP2 на 15 µW обидві ери кадру за метаболічною підлогою вже на моделі — wire-GP сідає на підлогу гомеостазу, SCC ≈ 0.89/дерево/рік (−93.5 %, [`02_06`](02_06_Unit_Economics_and_BOM), SCC-rate модель), тобто поле зі STOP2-прошивкою мінтить на підлозі незалежно від CCM-розвилки [`ARCH.8`](00_07_Action_Plan_Tracker). **Ціна** (як подано): перший field-deploy чекає ще й трьох умов фліпу ([`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA): ⚖️ RAM-стану · пін-мапа `.ioc` · виміряний сон). **Найслабша ланка** (як подано): 300 нА — число моделі; канонна оцінка сну після фліпу (≈ 0.31 µA + радіо ≈ 50 нА) лишає CCM-ері ≤ 40 нА запасу стоку, тож фліп необхідний, але для CCM може виявитись недостатнім — вирок дає стенд. ⊕ **Дописано при ратифікації — не частина купленого:** (а) подання питало «як FW.2-фліп» і лише відсилало до його піна — «rollback до поля = хвилини, після = SWD-візити на статичний KEYL» ([`00_07`](00_07_Action_Plan_Tracker), рядок 🚦); для сну це розгортається так: режим — константа компіляції C-образу (`FW54_STANDBY_ENABLED`), а OTA латає лише mruby-байткод (печатка — [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)); BFU, що верифікував би C-образ при старті, ще немає (SEC.24 ⚪), а будь-який локальний завантажувач потребує доступу до плати; на L1-пілоті SWD-запис заборонено, і вихід у L0 стирає Flash разом із ключами (RUNBOOK 1.3), а після L2 «C-firmware замерзає назавжди» (RUNBOOK, нота pre-L2) — тож фліп після поля коштує візиту до кожного вузла. (б) Усі три умови вже стояли на шляху до поля: FW.2-фліп — гейт поля (той самий пін), а фліп сну — пʼята передумова розвилки ARCH.8, що його гейтує; новизна присуду — гейт більше не залежить від того, як розсудять розвилку. (в) Числа подання відтворено моделлю: «обидві ери за підлогою» — `m` 0.000 / 0.000 (`tools/firmware/tx_cadence_budget.rb i_stm32_sleep_na=1070`), «≤ 40 нА» — на 0.31 µA + 50 нА (`i_stm32_sleep_na=360`). (г) Найслабшу ланку зміряно точніше: «радіо ≈ 50 нА» — це сон радіо в cold start ([`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)), а `Radio.Sleep()` ставить `WarmStart = 1` (`firmware/extern/subghz-phy/radio_driver/radio.c`), тобто ≈ 140 нА: на ≈ 0.45 µA CCM уже за підлогою (бракує 92 нА — `i_stm32_sleep_na=450`). Після пробудження зі Standby `main()` ініціалізує радіо наново, тож утримання конфігурації там нічого не купує — лік: cold start на сайтах сну радіо в Standby-збірці ([`00_07`](00_07_Action_Plan_Tracker) FW.54, 🤖-нога). Тим самим ревʼю знайдено гірше й виправлено в коді 2026-10-06–07: на шляхах морозу (FW.10 — `goto` повз сон), низького vcap (прослуховування Фази 4.5 пропущене разом зі сном) і зойку OTA (FW.27-B — TX після сну) радіо засинало в STDBY_RC, 0.7 мА проти 140 нА (DS13105 Табл. 28); тепер на шляхах циклу сон радіо один — на вході у Фазу 5 (другий сайт — PVD-колбек, теж зі Standby), приймач наприкінці вікна гасить `Radio.Standby()`, бо `Set_Sleep` радіо приймає лише зі Standby (RM0461 Rev 11 §4.8.3; код до виправлення, найімовірніше, засинав і на звичайному шляху з живим приймачем — 4.82 мА), а інваріант стереже `make -C firmware/test standby_wake`. Історія цілі: документ спершу декларував STOP2 2.1 µA, з якими баланс ішов у мінус навіть на +14 dBm SF9 ([`02_03 §9.5`](02_03_BQ25570_MPPT_Nano_Power)), потім — «STOP2 RTC-only 300 нА» через біт `RRSTP`, і цей механізм на WL не існує (нота нижче).

> 🔴 **Механізм, який §1.10 декларував доти (`PWR.CR1 RRSTP=1` у STOP2), на STM32WLE5 не існує — спростовано первинкою 2026-10-05** ([`00_07`](00_07_Action_Plan_Tracker) FW.54). `PWR_CR1` WL несе LPMS · SUBGHZSPINSSSEL · FPDR · FPDS · DBP · VOS · LPR і біта `RRSTP` не має (`firmware/extern/cmsis-device-wl/Include/stm32wle5xx.h`); `PWR_CR3_RRS` керує утриманням SRAM2 лише в **Standby**, а в STOP2 SRAM1 і SRAM2 зберігаються завжди (DS13105 Rev 12, опис режимів). Тож у STOP2 «−800 нА» взяти нізвідки: паспорт дає Stop2 (+RTC) 1.07 µA при 3 В і 25 °C, а клас ≈ 300 нА — це Standby без SRAM2, де VCORE вимкнено й пробудження йде через reset (числа й обидва прочитання ланцюга — врізка під Сценарієм C [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)). Інвентар §2.3.1 уже написано під цю семантику — він вважає втраченим увесь RAM-стан, не лише SRAM2. Прошивка входить у STOP2 (`HAL_PWREx_EnterSTOP2Mode` у `firmware/soldier/main.c`), тож ціль цієї секції без зміни режиму недосяжна; який режим брати — ⚖️ FW.54. ⊕ Ратифіковано 2026-10-05: Standby без утримання SRAM2 (абзац «⚖️ Ціль сну» цієї секції), фліп — FW.54.

```c
// ЦІЛЬОВИЙ сон — Standby (⚖️ 2026-10-05). VCORE вимкнено: SRAM1 гине завжди, SRAM2 — бо RRS = 0;
// пробудження = reset, тобто main() з початку. До фліпу FW.54 відвантажена прошивка спить у STOP2
// (HAL_SuspendTick → HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI) → продовження після WFI).
// Імена API — з вендорованого stm32wlxx-hal-driver (не L4: там SRAM2-функції звуться інакше).

// 1. Стан, що мусить пережити сон, — у RTC Backup Domain (DR0..DR19, §2) і Flash-KV (група C, §2.3.1)
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0, dr0_packed); // усі 4 поля DR0 (§2) — часткове слово обнулить сусідів
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, last_wakeup_timestamp);
// ... DR2..DR19 (mesh state, EMA, Lorenz state — розкладка §2)

// 2. Ключі навантажень: у Standby GPIO рівня не тримають — його тримають лише pull-и PWR (APC)
HAL_PWREx_EnableGPIOPullDown(PWR_GPIO_x, PWR_GPIO_BIT_y); // кожен load-switch — вимкнено; пін-мапа — .ioc (FW.46)
HAL_PWREx_EnablePullUpPullDownConfig();                   // APC = 1

// 3. Клас 300 нА: SRAM2 без утримання; будить RTC WUT на LSE (low drive — кварц поз. 17, ⚖️ 2026-10-05)
HAL_PWREx_DisableSRAMRetention();  // PWR_CR3_RRS = 0 (біта RRSTP у WL немає — нота вище)
__HAL_PWR_CLEAR_FLAG(PWR_FLAG_WU); // стара wake-подія не дала б заснути
// Watchdog: IWDG у Standby ЗАМОРОЖЕНО (option byte IWDG_STDBY=0, SEC.15) — нота нижче
HAL_PWR_EnterSTANDBYMode();        // повернення — лише через reset

// Після reset — перша гілка main(): «пробудження зі Standby ⊥ холодний старт»
if (__HAL_PWR_GET_FLAG(PWR_FLAG_SB) != 0U) {   // C1SBF
    __HAL_PWR_CLEAR_FLAG(PWR_FLAG_SB);         // знімається через C1CSSF
    /* відновлення з DR0..DR19 і Flash-KV — замість продовження після WFI */
}
```

**Що ціль коштує і що в ній гине (Standby без SRAM2):** гине весь SRAM — OTA-буфер збирання, RAM-only лічильники, scratch RX/TX; виживає увесь DR0..DR19 (mesh-кеш `recent_mesh_dids`, EMA, Lorenz-стан — §2 канонічна таблиця) і Flash-KV. Повний інвентар трьох груп + key→поле map того, що рятувати, — §2.3.1; що мусить пережити сон і **не** влазить у RTC, іде у Flash-KV (§2.3) або в реклемований RTC (§2.3.2), і вибір між ними та SRAM2-retain — ⚖️ RAM-стану FW.54 (у Standby утримання SRAM2 коштує ≈ 0.18 µA, тобто ≈ 4.3 мДж/год з VSTOR за η_buck 0.5, DS13105 Табл. 49). Виграш проти STOP2: (1.07 − ≈ 0.31) µA × 3.3 В × 3600 с / η_buck 0.5 ≈ 18 мДж/год. Ціна (повна форма — [`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power)): reset на кожному пробудженні — clock tree, AES, радіо, mruby щоразу, — тож кожен WUT-тик енерговоріт FW.50 платить повний старт. ⚠️ Колишнє «~800 нА → 19 мДж/год» описувало саме різницю STOP2 → Standby, а не ціну SRAM2.

> **IWDG заморожено у STOP2 (SEC.15 — 📐 freeze-rationale):** За замовчуванням Independent Watchdog тактується LSI і **продовжує лічити у Stop**; max період ~32.7 с (LSI 32 kHz / prescaler 256 / reload 4095). Soldier спить між energy-sufficient циклами значно довше (`delta_t` до ~18 год), тож незаморожений пес дав би **spurious reset посеред сну** = позаплановий повний reboot (марна енергія + збита RTC-WUT-каденція + втрата OTA-буфера збирання й RAM-only лічильників). Тому factory flashing виставляє option byte **`IWDG_STOP=0`** (freeze у Stop; `IWDG_STDBY=0` — у цільовому Standby, ⚖️ 2026-10-05, операційний саме він) — заскриптовано поряд з RDP у `firmware/scripts/bench/01_option_bytes.sh` (чекліст RUNBOOK §1.2) і пишеться самим фабричним конвеєром `factory:execute` перед RDP ([`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning), STEP 2 d). Заморожений пес **не входить** в енергобюджет сну — ні STOP2, ні цільового Standby (звідси ціль ≈ 300 нА вище). Свідомий side-path: PVD-кома (`HAL_PWR_PVDCallback`) теж спить у STOP2 — freeze дозволяє їй тривати, поки напруга не підніметься; ⊕ з [`FW.69`](00_07_Action_Plan_Tracker) (2026-10-09) кома кінчається не поверненням у цикл, а скидом на підйомі VDD (§6.1), тож «hang із suspended-tick після PVD-wake» більше не настає, і IWDG-rescue йому не потрібен. Bench (1 год сну, нуль spurious reset, RUNBOOK §4.4). **⚠️ Frozen IWDG → RTC WUT стає ЄДИНИМ backstop живучості** (немає watchdog-rescue посеред сну; × SEC.2 RDP-L2 = немає SWD-recovery) → bench мусить ще й (а) аудитнути CubeMX `MX_RTC_Init` на WUT **auto-reload + IT enabled** (у repo — навмисний порожній stub `firmware/hal_glue/soldier_hal_check.c` «календар/WUT FW.49 — bench»; конфіг = board-freeze, не код), (б) верифікувати **reliable WAKE** за багатогодинний сон, не лише no-spurious-reset. **Послідовність-гейт (× SEC.2):** оскільки RDP-L2 необоротний (нема SWD-recovery), а IWDG заморожений (нема watchdog-rescue) — армінг WUT мусить стати **версійованою ревʼюйованою функцією** (не лише .ioc-секцією, яку CubeMX-реген тихо перезапише) **і** bench-верифікованим на багатогодинне пробудження **ДО** будь-якого RDP-L2 burn; інакше реген, що мовчки вимкне WUT-IT, цеглить польовий L2-вузол без шляху відновлення. Армінг авторюється на bench-день (LSE clock-tree реальний, період вимірюваний), не раніше — committed-fn без свого clock-tree доводить лише compile, не WAKE. → [`00_07` — SEC.15](00_07_Action_Plan_Tracker).

**Джерела пробудження (📐 КАНОН wake-source — FW.49):**
- **RTC WUT** (періодичний fine-tick; LSE і RTC живі і в STOP2, і в цільовому Standby) — ОСНОВНИЙ wake. Вузол прокидається за розкладом, перевіряє Vcap-енергогейт ([FW.50](00_07_Action_Plan_Tracker)) і робить повний sense→Lorenz→TX цикл лише при достатньому перезаряді; інакше — назад у сон (ціль — Standby, ⚖️ 2026-10-05; до фліпу FW.54 — STOP2). `delta_t` = wall-різниця між energy-sufficient циклами через `Wall_Seconds_Now()` (RTC-календар), а НЕ active-tick.
- **PVD Callback** (VDD < 2.2 В, поріг VPVD1 — аварійне, не пробудження; ⊕ 2026-10-09: доти код ставив `PWR_PVDLEVEL_7`, а це в WL зовнішній вхід проти VREFINT, якого жодна ніжка WLE5 не виводить — DS13105 Rev 12 знає лише VPVD0..VPVD6; виправлено на `PWR_PVDLEVEL_1`; ⊕ того ж дня [`FW.69`](00_07_Action_Plan_Tracker): рефлекс діє лише на спад, а сон із нього має вихід — §6.1).
- **VBAT_OK** ([`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)) — апаратний buck/brownout-**гейт** (нижче порогу MCU знеструмлений → recovery = power-on-reset), **НЕ** GPIO-EXTI wake: при буфері **2.75 Дж** (⚖️ ратифікований `VBAT_OV`=4.822В, [`00_07` — HW.7](00_07_Action_Plan_Tracker); було 4.39 Дж на теоретичній 5.5В-стелі) VBAT_OK і далі залипає HIGH (нема періодичного edge — буфер несе ≈47 TX-циклів запасу, висновок не змінюється зі зниженням стелі), а cold-start = power-on робить EXTI надлишковим.

> **Два різні пороги — не плутати (FW.49):** `VBAT_OK ON ≈ 3.4 В` — апаратний поріг **увімкнення buck'а** (BQ25570, [`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)): нижче нього MCU просто знеструмлений. **Vcap-енергогейт** — firmware-політика, що перевіряється вже ПІСЛЯ RTC-WUT-пробудження (пороги listen / cold-TX-defer / CAD panic-преамбула ≈ 4.5 В — значення + сирий-ADC застереження у §1.4 [FW.50](00_07_Action_Plan_Tracker)) — і вирішує, чи цей конкретний цикл робить корисну роботу. Тобто «3.4 В» (HW-гейт живлення) ≠ «4.5 В» (FW-гейт CAD panic-преамбули): різні шари, а не суперечливі значення одного порогу.

> **ADR wake-source (FW.49, founder 2026-06-07):** RTC WUT + Vcap-енергогейт + RTC-календар як timebase — обрано замість (а) чистого RTC-розкладу (`delta_t`=константа → мертвий біосигнал) і (б) VBAT_OK-edge (залипання HIGH + квантований `delta_t` + потреба HW-траси VBAT_OK→EXTI). `delta_t` як час перезаряду = метаболізм живе через Vcap-гейт, вимірюється wall-time. Staged-план + bench bring-up (LSE/RTC clock-tree у repo відсутній) — [`00_07` FW.49](00_07_Action_Plan_Tracker).

> ⚖️ **EXTI-кадр і `delta_t` — ратифіковано ДЕЛЕГОВАНО 2026-09-28** (founder доручив делеговану ратифікацію відкритих присудів §02–§03 за рекомендацією; [`00_07` FW.49](00_07_Action_Plan_Tracker)). Кадр, народжений п'єзо-пробудженням, пакує сентинел «не виміряно» — і в EMA-вхід Лоренца та дроту, і в сирий `delta_t` (байти 8–9), — а базу `delta_t` рухає лише не-EXTI цикл; TX на EXTI не змінено (тракт пилки й panic той самий). **Підстава:** напрямок похибки — EXTI-база вкорочує виміряний перезаряд, а коротший перезаряд `m(delta_t)` читає як здоровіший метаболізм, тобто over-mint; вимір, отруєний вітром, того ж роду, що й відсутній — прецедент «немає виміру → нуль, не максимум» ([`03_04 §4.3`](03_04_mruby_Lorenz_Attractor), делеговано 2026-08-16). Наступний не-EXTI кадр міряє від попереднього не-EXTI й несе в собі енергію EXTI-циклів, тобто читає перезаряд повільнішим за справжній — безпечний бік; так само цикл, де збіглись таймер і п'єзо (його судить прапорець: він EXTI, і вимір розтягується на два періоди). **Ціна:** EXTI-кадри не нараховують балів (під частим вітром вузол шле частину кадрів без GP); енергію EXTI-циклів ніхто не компенсує, тож перезаряд не-EXTI кадра після них виглядає повільнішим за справжній. **Найслабша ланка:** частоти EXTI в полі ніхто не міряв (друга лінія SW — [`00_07` HW.30](00_07_Action_Plan_Tracker)); якщо вона висока, недонарахування помітне. Носії — `firmware/common/wall_time.h` (`Silken_Wake_Delta_Seconds` · `Silken_Wake_Lorenz_Delta_T`: їх кличуть і Фази 1/3 `soldier/main.c`, і host-тест `test_soldier_logic.c`, обидва мутаційно перевірені). ⚠️ Енергогейт S2 (`delta_t` між ENERGY-SUFFICIENT циклами) цим не закрито — до нього базу рухає кожен не-EXTI цикл.
>
> ⊕ **2026-09-29 ([`00_07`](00_07_Action_Plan_Tracker) HW.30): предмет цього присуду пішов разом із пʼєзо.** EXTI-пробудження на Солдаті більше немає, аргумент `exti_born` знято з `wall_time.h` (`Silken_Wake_Delta_Seconds` · `Silken_Wake_Lorenz_Delta_T`), тож базу `delta_t` рухає КОЖНЕ пробудження, а сентинел дають лише гарди дельти (§1.4). Присуд лишається прецедентом «вимір, отруєний стороннім пробудженням, = не виміряно» для майбутнього EXTI-носія ([`00_07`](00_07_Action_Plan_Tracker) HW.52 — датчик нахилу, не вирішено).

---

### 1.11 Node Role Flag (ARCH.27) — Soldier vs Provisioner

ARCH.26 (TDMA / CAD mesh relay) вимагає рольової диференціації: **Soldier** = TX-only (глухий між вікнами), **Provisioner** = TX + CAD (елітний вузол з надлишком енергії, ловить преамбули). Прошивка компілюється **ідентично** для обох — роль персистується даними, не білдом.

**Зберігання — Protected Flash, не RTC.** `FLASH_ROLE_ADDR = FLASH_KEY_ADDR + 56` (`0x0803E000 + 56 = 0x0803E038`) — у тому ж WRPROT-захищеному 4 KB Protected Flash Sector, що LoRa AES-128 key (`+0`, magic `"KEYL"`, 20-байт блок post-ARCH.42) та K_seed (`+20`, magic `"LSED"` [SEC.11], 36-байт блок), **без створення нового сектора**. Роль живе у Flash, бо при cold-boot / VBAT-loss вона **не повинна змінюватися** — RTC було б помилкою (стирається при повному знеструмленні; див. §2.1).

**Формат — один `uint32` magic-word:**

| Значення | Роль |
|----------|------|
| `0x534F4C44` (`"SOLD"`) | `ROLE_SOLDIER` |
| `0x50524F56` (`"PROV"`) | `ROLE_PROVISIONER` |
| `0xFFFFFFFF` (unprovisioned) / `0x00000000` (erased) / інше (корупція) | fallback → `ROLE_SOLDIER` |

Fallback на `ROLE_SOLDIER` безпечний — переважна більшість вузлів є звичайними датчиками.

**Runtime.** Глобальний `volatile uint8_t g_node_role` встановлюється `Load_Node_Role()` у `main()` одразу після `Load_Lorenz_Seed()`. Споживачі: **ARCH.26 L3** — роль-гейт CAD-нюху (`Cad_Sniff_Due` першим аргументом, Phase 4.5 за `ARCH26_CAD_ENABLED`) та повний FW.20-S2 (mesh time-sync relay, guard 1 `Soldier_Try_Relay_Time_Beacon`). Backend `HardwareKeyService` не зачіпається — це чистий firmware-flag (інкрементальний патч, 2026-05-03).

**Тести.** 5 host-тестів (`test_arch27_*` у `firmware/test/test_soldier_logic.c`): `"SOLD"` / `"PROV"` / unprovisioned `0xFFFFFFFF` / zero / corrupted magic → коректний fallback.

**Cross-ref:** ARCH.26 ([`00_07` — ARCH.26](00_07_Action_Plan_Tracker); §1.9 RX-вікно), [SEC.11] K_seed Flash layout, §2.1 (чому роль у Flash, не RTC).

---

## 🗺️ 2. Soldier RTC Backup Register Map (DR0..DR19) — Canonical SSOT [DOC.3]

> **SSOT (єдина точка істини):** ця таблиця — **єдине** канонічне джерело розкладки RTC Backup Domain Soldier'а. Будь-яка зміна (додавання нового поля, перепакування біт-полів, новий магічний маркер) **повинна** починатися з оновлення цієї таблиці. Документація [`03_04`](03_04_mruby_Lorenz_Attractor) (Lorenz state), [`03_03`](03_03_TinyML_Acoustic_Inference) (TinyML EMA) та firmware-код посилаються на цю таблицю, а не дублюють її.

> **Політика розширення (cross-ref [ARCH.28](00_07_Action_Plan_Tracker)):** STM32WLE5 має лише 20 backup регістрів (DR0..DR19). Після **[FW.2 freeze-contract, 2026-05-24]** (DR15 → CCM Frame Counter) **вільні DR7** (звільнено FW.54: `tree_did` тепер `f(UID)`) **і DR13/DR14** (звільнено HW.30, 2026-09-29: TinyML-пороги пішли разом із пʼєзо) — їх витрачають за процедурою §2.2, а далі нова RTC-resident фіча йде у Flash-KV (§2.3; так уже маршрутизовано FW.20-S2 anti-storm bitmap). Перед будь-якою зміною RTC: (1) огляд цієї таблиці на конфлікти, (2) ASCII bit-field діаграма для будь-якого packed-регістру, (3) новий магічний маркер у §2.1, (4) обов'язковий `isfinite()`/magic check при відновленні. DR0-розкладку додатково стереже compile-time `_Static_assert` non-overlap (panic[31:16]/vm_streak[9:8]/acoustic[7:0], `soldier/main.c` [FW.54 guard]) — фіча, що вкраде зайнятий біт-слот, впаде на компіляції, не тихо перекриє money-path-лічильник у полі.

RTC Backup Domain не скидається при STOP2 та більшості реботів (окрім повного знеструмлення або `HAL_RTCEx_BKUPWrite` з нулями).

| Регістр | Змінна | Тип | Опис |
|---------|--------|-----|------|
| `DR0` | `[panic_frame_counter:16 \| rsv:5 \| canary_trip:1 \| vm_err_streak:2 \| acoustic_events:8]` | uint32 packed | **[SEC.10 + FW.22]** Спакована плоть: лічильник panic-кадрів anti-replay (uint16, monotonic + saturating @ 0xFFFF) у high 16 біт + лічильник акустичних подій (uint8, saturating [0,255]) у low 8 біт — з HW.30 писача немає, поле завжди 0 (доля слоту — [`00_07`](00_07_Action_Plan_Tracker) FW.59). **[SEC.20]** `vm_err_streak` (uint2, `DR0[9:8]`): N=3 поспіль bytecode-exec збоїв OTA-байткоду → erase contract → auto-fallback на embedded baseline (лічить лише bytecode-fault, не no-seed/OOM; переживає STOP2, cold-boot=0 природно). **[SEC.21]** `canary_trip` (`DR0[10]`): sticky-слід власного `__stack_chk_fail` (пише напряму `TAMP->BKP0R` перед `NVIC_SystemReset`; усі 4 write-sites preserve); гасить його wire-винос: три best-effort постріли event-кадру 0x57 (`device_event.h`), після третього Фаза 5 пише `DR0[10]=0`; доти — sticky, видимий і SWD'ом. Біти `[15:11]` зарезервовано. Пакетне збереження економить регістр — без packing знадобився б новий слот, тобто єдиний нині вільний DR7 (FW.54). Cold-boot DR0=0 → `panic_frame_counter` пересіюється з HRNG (range 0x0001..0xFFFF) для уникнення колізії з ще-не-протухлими replay-ключами `Rails.cache` попереднього втілення. |
| `DR1` | `last_wakeup_timestamp` | uint32 | **[FW.49 S1]** Wall-маркер останнього пробудження — з HW.30 його рухає кожне пробудження (§1.4; EXTI-пробудження пішло з пʼєзо, §1.10) (`Wall_Seconds_Now()`, unix-секунди RTC-календаря; до 2026-06-12 — заморожений у STOP2 `HAL_GetTick/1000`). Перехід tick→wall значень поглинають guard-и `wall_time.h` (стрибок → сентинел «не виміряно», ARCH.102). [ARCH.21] Зберігається при PVD-брауноуті для delta_t continuity після recovery. |
| `DR2` | `has_mesh_relay` | uint8 | Прапорець: 1 = є пакет для ретрансляції |
| `DR3` | `mesh_relay_payload[0..3]` | uint32 | Транзитний пакет, байти 0-3 |
| `DR4` | `mesh_relay_payload[4..7]` | uint32 | Транзитний пакет, байти 4-7 |
| `DR5` | `mesh_relay_payload[8..11]` | uint32 | Транзитний пакет, байти 8-11 |
| `DR6` | `mesh_relay_payload[12..15]` | uint32 | Транзитний пакет, байти 12-15 |
| `DR7` | **(вільний)** | — | **[FW.54 Вісь 2, 2026-06-12]** Звільнено: `tree_did` тепер детермінований `f(UID)` — recompute на boot з кремнієвого паспорта (`did_derive.h`, §7), зберігати нічого. Перший вільний регістр з часів FW.2-freeze — витрачати за процедурою §2.2 |
| `DR8` | `recent_mesh_dids[0]` | uint32 | Anti-pingpong DID cache, слот 0 |
| `DR9` | `recent_mesh_dids[1]` | uint32 | Anti-pingpong DID cache, слот 1 |
| `DR10` | `ema_delta_t_x100` | uint32 | [FW.21] EMA delta_t × 100 (fixed-point 0.01 с) |
| `DR11` | `recent_mesh_dids[2]` | uint32 | Anti-pingpong DID cache, слот 2 (FW.21 fallback: vcap_x10 запаковано в DR12) |
| `DR12` | `[valid:8 \| count:8 \| ema_vcap_x10:16]` | uint32 | [FW.21] Метадані EMA + упакований vcap_x10 (max 55000 ≤ 2^16) |
| `DR13` | **(вільний)** | — | **[HW.30, 2026-09-29]** Звільнено разом із пʼєзо (тримав TinyML-поріг WARNING, FW.18). Витрачати за процедурою §2.2 |
| `DR14` | **(вільний)** | — | **[HW.30, 2026-09-29]** Звільнено разом із пʼєзо (тримав TinyML-поріг CRITICAL, FW.18). Витрачати за процедурою §2.2 |
| `DR15` | `[FW2_FC_MAGIC:8 \| frame_counter:24]` | uint32 packed | **[FW.2 / ARCH.42, freeze-contract 2026-05-24]** CCM LoRa Frame Counter (uint24, monotonic, ~16.7M cycles ≈ 64× longevity @ 1 TX/h × 25y). Magic `0x46` ("F") у high 8 бітах захищає від cold-boot junk; невалідний magic → cold-boot політика [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) 📐 (Flash high-water floor з KV `0x14`, §2.3.1; fallback — HRNG reseed). Активний лише при `#define FW2_CCM_ENABLED 1` (deferred до HW bench для `CRYP_AES_CCM` HAL верифікації) — до flip DR15 залишається 0 та panic anti-replay тримається на DR0[31:16] (SEC.10 transitional). |
| `DR16` | `lorenz_x` | float32→uint32 | [FW.6] X-координата атрактора Лоренца (IEEE 754 bit-copy) |
| `DR17` | `lorenz_y` | float32→uint32 | [FW.6] Y-координата атрактора Лоренца |
| `DR18` | `lorenz_z` | float32→uint32 | [FW.6] Z-координата атрактора (інтенсивність конвекції) |
| `DR19` | `LORENZ_STATE_MAGIC` | uint32 | [FW.6] Маркер валідності: `0x4C5A5354` ("LZST"). Захист від RTC-корупції |

> **DR7 — звільнений [FW.54 Вісь 2]:** до 2026-06-12 тримав write-once `tree_did` (стара схема `UID⊕random`). DID тепер деривується з UID на кожному boot (§7) — ідентичність пережила б і повний VBAT-loss, і OTA-ребут без жодного збереженого слова.

> **DR16-DR19 — Стан Лоренца (FW.6):** (⊕ 2026-10-06: під ратифікованою гілкою (Б) Лоренц іде з пристрою разом із фліпом FW.2 — ці чотири регістри стануть кандидатами на звільнення з її реалізацією — рішення за зміною мапи цієї секції; [`00_07`](00_07_Action_Plan_Tracker) FW.66; доти мапа як є.) Зберігається/відновлюється при кожному циклі сну (STOP2; у цільовому Standby так само — DR живі). При первинному старті або після повного знеструмлення (DR19 ≠ `0x4C5A5354`) система переходить у режим cold-start від K_seed через HKDF/HMAC деривацію `(x₀,y₀,z₀)` (**[SEC.11 / FW.30]** — замість старого `chaos_seed`). K_seed зчитується з Protected Flash Sector (`FLASH_SEED_ADDR = FLASH_KEY_ADDR + 20` post-ARCH.42, magic `"LSED"` = `0x4C534544`). NaN/Inf перевірка через `isfinite()` захищає від бітових помилок у Backup Domain. STM32WLE5 підтримує 20 backup registers (DR0-DR19). **Після FW.2 freeze-contract (2026-05-24) DR15 зайнято CCM Frame Counter** (24-bit + 8-bit magic); вільні DR7 (FW.54) і DR13/DR14 (HW.30) — рядки вище.

> **DR13/DR14 — звільнено [HW.30, 2026-09-29]:** тримали два TinyML confidence-пороги FW.18 (WARNING/CRITICAL), які ставив OTA-опкод `0x9D`. Разом із пʼєзо пішли Фаза 1.5 (§1.5), пороги з їхнім writeback і сам опкод — `0x9D` RETIRED у прошивці й Rails, байт не перевикористовується (§4.5а); дизайн порогів як історія — [`03_03 §5`](03_03_TinyML_Acoustic_Inference).

### 2.1 Magic Markers (Канонічна Таблиця) [DOC.3]

Маркери валідності використовуються для розрізнення "регістр містить осмислені дані з попереднього циклу" vs "регістр у defaulted-стані після cold boot / RTC корупції / `HAL_RTCEx_BKUPWrite(0)`". Якщо маркер не збігається — відповідний блок ініціалізується з нуля.

| Магічний маркер | Значення (hex) | ASCII | Регістр-прапор | Захищає блок | Документ |
|-----------------|----------------|-------|----------------|--------------|----------|
| `LORENZ_STATE_MAGIC` | `0x4C5A5354` | `"LZST"` | `DR19` | `DR16/DR17/DR18` (lorenz_x/y/z) | [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor#21-звідки-беруться-вхідні-параметри) |
| `EMA_VALID_MAGIC` (8 біт у DR12) | `0x45` ('E', high byte) | — | `DR12[31:24]` | `DR10` (ema_delta_t), `DR12[15:0]` (ema_vcap_x10) | [§13.3](#133-persistence--rtc-backup-registers-dr10--dr12-packed) |

> Маркер `tree_did != 0` (захист DID у DR7) знято [FW.54 Вісь 2]: DID тепер деривується з UID на кожному boot ([§7](#-7-did-derivation-імя-з-кремнію)) — захищати в RTC нічого.

> **DR12 packed format (FW.21):** `[valid:8 | count:8 | ema_vcap_x10:16]`. `valid == 0x45` (`EMA_VALID_MAGIC`, 'E') означає що EMA fields ініціалізовано та накопичено ≥1 семпл. При cold boot DR12 == 0 → `valid != 0x45` → EMA reset.

> **Чому різні маркери:** Lorenz (`"LZST"`) використовує цілий 32-бітний маркер у виділеному регістрі тому що `(0.0, 0.0, 0.0)` — валідний (хоч і нетиповий) стан атрактора, тому zero-check недостатній. EMA використовує 8-бітний sentinel у packed-регістрі через дефіцит DR-простору.

### 2.2 Procedure для додавання нової RTC Backup фічі [ARCH.28]

> **Кенозис інженерії:** перш ніж претендувати на регістр — перевір, чи можна щільніше упакувати існуючий, або **звільнити** під-використаний/mis-allocated DR (§2.3.2 reclamation menu — ширина/частота-запису/durability-клас). STM32WLE5 (обидва корпуси) має ЛИШЕ 20 backup-регістрів (`DR0..DR19`); після `[SEC.10]` + `[FW.2]` (DR15 → CCM Frame Counter, freeze-contract) **вільні DR7** (FW.54) **і DR13/DR14** (HW.30). Реальні приклади того, як ми відмовилися від нового регістра на користь packing'у:
>
> - **`[SEC.10]` panic frame counter (uint16) → DR0[31:16]** — спакували поряд з `acoustic_events` у DR0[7:0]. Без packing'у пішов би DR15, і ми залишилися б без жодного резерву.
> - **`[FW.21]` EMA `ema_vcap_x10` (max 55000 ≤ 2¹⁶) → DR12[15:0]** — спакували разом з `valid:8 | count:8`. Це звільнило DR11 під 3-й слот anti-pingpong (без packing'у `MESH_DID_CACHE_SIZE` упав би з 3 до 2).
> - **`[ARCH.27]` Node Role flag → Flash, не RTC** — magic-word `"SOLD"`/`"PROV"` живе у Protected Flash sector (`FLASH_KEY_ADDR + 56`), бо при cold-boot/VBAT-loss роль не повинна змінюватися. RTC було б помилкою. Повний спец — **§1.11**.

**Чек-листа ПЕРЕД тим, як просити регістр:**

1. **SSOT-рев'ю.** Прочитати §2 (цю таблицю) ПОВНІСТЮ. Чи поле справді потребує переживання STOP2? Якщо ні — RAM-only достатньо. Якщо так, але переживає лише warm-boot, а не VBAT-loss → теж RAM (SRAM зберігається у STOP2). ⊕ 2026-10-05: у цільовому Standby (⚖️, §1.10) SRAM гине на кожному пробудженні, тож там «теж RAM» не тримається — гоча `firmware` #22.
2. **Packing-аудит.** Перевірити для кожного існуючого packed-регістру (DR0, DR12), чи є вільні бітові щілини для нового поля. Реальні розміри:
   - `DR0[15:11]` — 5 біт vacant (`[10]` = `canary_trip` SEC.21, `[9:8]` = `vm_err_streak` SEC.20 — див. §2 DR0-рядок).
   - `DR12[31:24]` — `valid:8` зайнято, але вільних бітів немає.
   - Більшість «full uint32» регістрів використовують лише частину діапазону (але НЕ `last_wakeup_timestamp` у DR1: це unix-секунди RTC-календаря — ≥ 946 684 800, тобто 30+ біт, і будь-яке звуження обрізало б базу delta_t, що годує GP).
3. **ASCII bit-field діаграма.** ОБОВ'ЯЗКОВО для будь-якого packed-регістру. Приклад з DR0:
   ```
   DR0 = [panic_frame_counter:16][rsv:5][canary:1][vm_err_streak:2][acoustic_events:8]
          ↑              MSB       [10]=SEC.21   [9:8]=SEC.20        LSB ↑
          PANIC_COUNTER_DR0_SHIFT=16                              raw uint8
   ```
   Без діаграми наступна людина (або ти за рік) не зрозумієш порядок бітів.
4. **Magic marker policy.** Якщо `0` — валідне значення поля (як `(0.0, 0.0, 0.0)` для Lorenz state), то ОБОВ'ЯЗКОВО потрібен окремий 32-бітний marker у сусідньому регістрі АБО 8-бітний sentinel у packed-регістрі. Маркер додати у §2.1. Якщо `0` валідно інтерпретується як «cold-boot default» (як колишні TinyML-пороги DR13/DR14 до HW.30: `0.0f` → fallback на дефолт), маркер не потрібен — достатньо range-check.
5. **Restore guard.** При читанні з RTC ПЕРЕД використанням — `isfinite()` для float, magic-check для structured fields, range-validation для цілочисельних. Захищає від bit-flip у backup domain (рідкісне, але документоване ST явище у high-radiation environments).
6. **Host-test bank.** Кожна нова фіча, що торкається RTC, повинна мати ≥3 host-тести: (a) cold-boot fallback, (b) warm-boot roundtrip, (c) corruption/bit-flip відкочується на default. Приклади: `test_arch21_pvd_*`, `test_sec10_dr0_*`.
7. **Doc update.** Оновити §2 канонічну таблицю + §2.1 magic markers + cross-link з 00_07 (відповідний ID).

**DR15 зайнято FW.2 (freeze-contract) — вільні DR7 (FW.54) і DR13/DR14 (HW.30):** нова RTC-resident фіча після них йде у §2.3 (Flash-based KV store). FW.20-S2 anti-storm bitmap уже так маршрутизовано (resolution 2026-05-30).

### 2.3 Overflow strategy: Flash-based KV store [ARCH.28]

> **DR15 вже зайнято (FW.2 CCM Frame Counter, freeze-contract):** наступна фіча, що потребує RTC-resident state з переживанням VBAT-loss, не отримає **нового** регістра — але спершу зваж **реклемацію** під-використаного/mis-allocated DR (**§2.3.2**: часто дешевше за Flash-wear). Якщо реклемація не підходить — нижче три Flash-шляхи; **шлях A — ✅ host-імплементовано (2026-06-07)**, бо на нього вже маршрутизовано три споживачі (FW.54 wall-маркери/EMA, FW.20-S2 bitmap, FW.49).

> **✅ Шлях A — імплементація (host-first):** `firmware/common/flash_kv.{h,c}` + power-cut тести `firmware/test/test_flash_kv.c` (`make -C firmware/test flash_kv`). Дизайн AN4894-патерну під ECC WLE5: **елемент = один doubleword** `[value:32][key:8][flags:8][crc16:16]` (програмування dw атомарне щодо ECC → «порваного» запису не існує), append-only «останній виграє», дві сторінки ping-pong із заголовками `SKV1|seq` + `FINI|seq` — **FINI програмиться останнім**, тож power-cut посеред compact лишає стару сторінку авторитетною (інваріанти I1-I3 у `flash_kv.c`, кожен доведений fault-injection тестом). Compact пропускає erase уже-чистої цілі (wear ÷2 у steady-state). Залізні примітиви ізольовано у `FlashKvOps` — host підставляє RAM-мок, MCU підставить `HAL_FLASH_Program/Erase` при HAL-фазі.
>
> **✅ Sibling — OTA contract blob writer (FW.52-г):** `firmware/common/flash_ota.{h,c}` (`Flash_Write_Contract`) reuse'ить ту саму `FlashKvOps`-абстракцію, але пише **простий blob** (не KV-журнал) — зібраний OTA-байткод у contract-сторінку **126** (`MRUBY_CONTRACT_FLASH_ADDR`): erase + dw-program, **power-cut-safe: RITE-magic dw програмиться ОСТАННІМ** (перерваний запис → dw[0]=0xFF → boot не бачить magic → fallback на embedded `lorenz_bytecode`). Host-тести `test_flash_ota.c` (8/8 — round-trip · magic-last · erase-fail · reject); HAL-glue `g_ota_flash_ops` у `main.c` (bench-фаза). Закрив FW.52-г: раніше `Write_OTA_Contract_To_Flash` був порожнім hal_mock-стабом → OTA нефункціональний end-to-end.
>
> **Розміщення (freeze-contract):** сторінки **122-123** (`0x0803D000`-`0x0803DFFF`) — хвіст зайнятий: 124 = **per-device identity** (KEYL-session/K_seed/роль — `FLASH_KEY_ADDR`), 125 = **cluster membership** (KPUB — публічний ключ печатки OTA, `FLASH_OTA_KEY_ADDR 0x0803E800` + **KEYB `FLASH_BCAST_KEY_ADDR` @+40, dw-align** — FW.2 (в) двоключова модель [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security); окрема сторінка, бо обидва per-cluster (⚠️ інструмента, що стирав би лише її, немає: заводський конвеєр стирає й переписує 124 і 125 разом — [`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning)); слот OTA-ключа сюди переїхав 2026-06-11 (тоді ще симетричний K_ota): первісний `0x0803D000` мовчки колідував із цим KV-регіоном — mount стер би ключ), 126(-127) = OTA contract (`MRUBY_CONTRACT_FLASH_ADDR`), 127 = Queen UID. Mount + HAL-глю ✅ написано у `main.c` під One-Home гейтом `FLASH_KV_BASE_ENABLED` — через SEC.20 він живий у бойовому білді, тож журнал монтується вже сьогодні (`firmware`-гоча #18; `!mounted` → anti-rollback degraded-allow); верифікація erase/program — bench.
>
> **Wear-бюджет (зчеплений з E.63-шкалою delta_t):** 2 КБ сторінка = 254 елементи; запис «снапшот циклу» = K елементів/пробудження → erase раз на ⌊254/K⌋ циклів; 10k endurance × 2 сторінки. При K=4 це ⌊254/4⌋ = 63 пробудження на erase × 20 000 erase = 1.26 млн пробуджень: при realistic ≈ 2 год ([`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)) → століття. 🔴 **А оптимістичного кута в цього бюджету НЕМАЄ — і L4 його не дає:** тут стояло «delta_t = 19.9 с → ~0.8 року», потім (зведення ціни циклу 2026-09-27) 171.7 с → ~6.9 року, але обидва числа — КУПОННІ (2 см²), а шапка `30_kinetics_delta_t.py` прямо забороняє читати їх як інтервал вузла: на площі анкера (65–123 см²) та сама лаб-стеля дала б ≈ 3–5 с, і тоді 1.26 млн пробуджень минули б за 1.5–2.5 місяці. Швидкий край задає не енергія, а підлога каденсу — період WUT, якого в коді ще немає ([`00_07`](00_07_Action_Plan_Tracker) FW.49). ⚠️ Підсумок свідомо КОНСЕРВАТИВНИЙ — він не бере «compact пропускає erase уже-чистої цілі» з блоку вище, який у steady-state подвоює ресурс. ⛔ Підсумок писати РАЗОМ із множниками: голе число в цьому рядку неперевірне. Якщо польова delta_t впаде під ~5 хв стабільно — розширити page-set (4-8 сторінок, адреси вниз від 122) або лишити SRAM2-retain (−800 нА) свідомим trade-off (FW.54).
>
> **Bench-residual:** реальні `HAL_FLASH_*` глю + політика ECCD-читання (double-error → NMI: чи читати через перевірку `FLASH_ECCR` — RM0461) + вимір erase-стійкості до LoRa RX-вікна.

| Шлях | Опис | Плюси | Мінуси | Коли вибирати |
|------|------|-------|--------|--------------|
| **A. STM32 Flash sector emulated EEPROM** ✅ host-impl | Дві 2 КБ-сторінки ping-pong під key-value store (журнальний append + compact) — реалізацію див. блок вище (`flash_kv.c`, key u8 → value u32; багатословний стан = кілька ключів). | Безкоштовно (Flash вже є), ємність сотні елементів/сторінку. | Erase блокує шину → `FlashKv_NeedsCompact()` назовні: викликач ущільнює поза LoRa RX-вікном. Wear ~10k cycles/сторінку — бюджет у блоці вище. | Стан, що мусить пережити VBAT-loss/SRAM2-off: FW.54 wall-маркери, FW.20-S2 bitmap, config/calibration. |
| **B. SE050 secure objects** | Якщо `[SEC.6]`/SE050 на платі — SE secure objects + HW monotonic counters (SE = SE050, [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)). | Tamper-protected, не впливає на main Flash. Counters апаратно monotonic — ідеально для anti-replay. | +$2.40–3.25/unit BOM. I²C latency. | Security-sensitive state: rotation counters, signing certificates, key versions. Synergy з `[FW.17]` Hash Ratchet. |
| **C. Bit-перепакування** | Перейти на 16-бітні розрядні поля для тих uint32, що використовують реально <2¹⁶ діапазон (DR1 `last_wakeup_timestamp` сюди НЕ належить — unix-секунди, 30+ біт). | Нульова BOM-вартість, нульова latency. | Ризикує overflow'ом при патологічних сценаріях (вузол прокинувся у режимі OTA на >18 год, потрапив у IWDG storm, тощо). Складніше debug'ити. | Останній крок перед Flash-KV: коли packing може дати +1-2 регістри на дешеві поля. |

**Рекомендований порядок при наступній витрати DR15:** (1) спершу аудит packing'у (§2.2 крок 2) → (2) шлях C якщо є кандидати → (3) шлях A для рідко-оновлюваних → (4) шлях B якщо SE050 вже на платі. Ніколи не дублювати дані між RTC і Flash «про всяк випадок» — це джерело розсинхронізації.

#### 2.3.1 FW.54 RAM-state inventory — що пережити SRAM2-off (key→поле map)

> **Передумова.** У цільовому RTC-only режимі (§1.10, 300 нА) **RTC Backup Domain (DR0..DR19) виживає** — це його суть. Втрачається лише runtime-стан у SRAM. Тому інвентар ділить увесь file-scope стан `firmware/soldier/main.c` на три групи; у Flash-KV їде **лише** група C (RTC повний — §2).

**Група A — RTC-resident (вже безпечне, нічого не робимо).** Усе, що Phase 5 (Кенозис) пише у DR0..DR19: panic/acoustic, `last_wakeup_timestamp`, mesh-relay payload+flag, `recent_mesh_dids` (mesh-кеш!), EMA (`ema_*`), Lorenz `(x,y,z)`+magic, FW.2 Frame Counter (`tree_did` RTC більше не несе — `f(UID)` на boot, §7). Точна розкладка — §2 (не дублюємо). Виживає у RTC-only без жодних змін.

**Група B — ефемерне (per-wake, втрата НЕ важлива).** Scratch-буфери, що наповнюються щоциклу до використання й не несуть сенсу між пробудженнями: `lora_payload`/`encrypted_payload` (TX), `incoming_lora_payload`/`decrypted_rx_payload` (RX), ISR-прапорець `lora_rx_flag`, `delta_t_seconds` (рахується щоциклу), `current_lorenz_bytecode` (вказівник, ставиться на boot), `g_node_role`/`lorenz_seed[]` (читаються з Protected Flash на boot — §1.11/SEC.11). Персистити нічого.

**Група C — must-survive, але RAM-only → Flash-KV ключі.** Стан, що мусить нести значення **між** циклами, але якому нема місця у RTC (DR0..DR19 практично повні — вільні лише DR7 і DR13/DR14, §2):

| Ключ | Поле(я) | Пакування (u32) | Споживач | Статус |
|------|---------|-----------------|----------|--------|
| `0x01` | *(не видано)* | — | — | ⛔ план WARN_ESC (FW.54) втратив предмет з HW.30: усі три його лічильники (`warning_counter` · `tinyml_threshold_invalid_count` · `fauna_skipped_low_vcap`) пішли разом із пʼєзо; ключа в коді не було ніколи, тож він вільний |
| `0x02` SYNC_WALL | `last_sync_request` (wall-сек) | u32 | FW.20-S2 sync-cooldown | план FW.54 (degradable) — ключа в коді немає |
| `0x03` OTA_SILENCE_WALL | `ota_last_chunk_rx` (wall-сек) | u32 | FW.27-B OTA re-request silence | план FW.54 (лише під OTA) — ключа в коді немає |
| `0x10`–`0x11` FW8_ZCFG | `lorenz_z_{min,max,opt}_x100` · `species_id` · `config_version` | 2 dw: `0x10`=[z_max:16\|z_min:16], `0x11`=[ver:8\|species:8\|z_opt:16] | FW.8 per-tree Z-пороги | ⚫ FW.8 (2026-10-06): ключі звільнить реалізація (Б), [`00_07`](00_07_Action_Plan_Tracker) FW.66; доти gated (`FW8_PARSER_ENABLED=0`); persist ✅ host (`common/lorenz_thresholds.h` + power-cut тести); споживач ✅ у `main.c` — boot-restore після mount'а + КЕНОЗИС-write по dirty 0x9A |
| `0x12` DL_DLFC (видано 2026-09-29; доти вільний — заявлявся під FW8_AUDIO, чий опкод `0x9D` з HW.30 RETIRED) | останній прийнятий DLFC адресних команд Rails → Солдат ([`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)); пишеться в КЕНОЗИСІ ПІСЛЯ того, як ефект команди вже в журналі (at-least-once — ⚖️ founder 2026-09-29, врізка [`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)); доти стояло «ПЕРШ ніж дія» | u32 — DLFC цілком | FW.17 downlink-ревізія: `DL_CCM_KV_KEY_DLFC` (`firmware/common/downlink_ccm.h`), секція 1.14 `soldier/main.c`; свіжий журнал провіжну — першого й повторного (⚖️ 2026-09-29) — його не несе → DLFC 0 | gated (`DL_CCM_RX_ENABLED` = FW8 ∨ FW17). Процедура §2.3: лічильник безпеки, реклемації RTC під нього немає, SE050 на платі немає, запис — лише на прийняту команду |
| `0x13` FW17_KEYVER | ratchet `key_version` (САМ ключ у Flash-KV НЕ їде — append-журнал не стирає; boot re-derive з K0). Пишеться ПЕРШ ніж ключ зміниться (`Key_Ratchet_Commit`): без запису ротації нема | `[rsv:16 \| version:16]` — версія в молодших бітах, як її пише й читає код (до 2026-09-28 тут стояв зворотний порядок) | FW.17 ротація ключа ([`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)) | gated (`FW17_RATCHET_ENABLED=0`); споживач ✅ у `main.c` — RX 0x9E → КЕНОЗИС-write, boot `Key_Ratchet_Apply`; активація після FW.2 CCM |
| `0x14` FW2_FC_HIWATER | монотонна межа Frame Counter (high-water > усіх переданих FC; політика — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) 📐) | `[frame_counter:24 \| rsv:8]` (значення ≤ `0xFFFFFF`; інше = сміття → floor відсутній) | FW.2 безумовна nonce-унікальність через cold-boot (`common/fc_hiwater.h`) | gated (`FW2_CCM_ENABLED=0`); споживач ✅ у `main.c` — boot-кеш після mount'а, КЕНОЗИС-advance, floor у `Load_Frame_Counter`; host-тести `test_flash_kv.c`; заводський журнал SEC.3 пише `1` — FC стартує біля нуля ([`00_07`](00_07_Action_Plan_Tracker) SEC.41) |
| `0x15` SEC20_OTA_VER | OTA version high-water — монотонна межа застосованої версії (кожен APPLY мусить > неї, інакше REJECT); кожен провіжн дерева — перший теж (⚖️ 2026-09-29) — пише її конвеєром = `clusters.ota_version_hiwater` у свіжий журнал, де поруч лише якір FC `0x14` = 1 (SEC.41) (`FactoryFlashing::FlashKvImage`, FW.17 — [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)) | u32 (0 = ще не застосовано → перший OTA свіжий) | SEC.20 anti-rollback (`common/ota_antirollback.h`); споживач ✅ у `main.c` — OTA APPLY-гейт + Commit, compact у КЕНОЗИСІ | **live (НЕ-gated — перший не-gated Flash-KV споживач)** |
| `0x20` S2_BITMAP | anti-storm журнал поколінь маяка (sliding window; покоління = `unix_ts/900`) | 1 dw: `[gen_hi:24 \| window:8]` (атомарний — порваної пари gen↔window не існує; gen завжди ≤ 2²⁴) | FW.20-S2 повний mesh-relay ([`03_02 §5а`](03_02_Queen_Gateway_Firmware)) | gated (`FW20_MESH_RELAY_ENABLED=0`); persist ✅ host (`common/beacon_dedup.h` + power-cut тести); споживач ✅ у `main.c` — boot-load після mount'а, Mark у RX, КЕНОЗИС-persist |

> **Головний wall-маркер delta_t — НЕ Flash-KV ключ.** «Wall-секунди останнього energy-sufficient циклу» (базу рухає `Silken_Wake_Delta_Seconds`, `firmware/common/wall_time.h`; до енергогейта S2 — останнього пробудження, бо з HW.30 базу рухає кожне) переселяє **семантику** `last_wakeup_timestamp` (DR1: tick-сек → wall-сек) — реюз наявного RTC-регістру, а не нова Flash-фіча. Тож FW.49 timebase **не** додає Flash-write/цикл; у Flash-KV їдуть лише вторинні маркери (`0x02`/`0x03`), що деградують м'яко (втрата → м'який re-ask після grace).

**K (елементів/пробудження) + звірка wear-бюджету.** (Спершу: чи треба Flash для live-набору взагалі — **ні**, він вміщується у RTC-headroom, **§2.3.2**. Нижче — бюджет на випадок, якщо headroom свідомо лишають Lorenz/іншому стану й live-набір таки їде у Flash.) Live-набір групи C = {`0x02`, `0x03`} (`0x01` з HW.30 предмета не має). Консервативно (snapshot-every-cycle = пишемо КОЖЕН live-ключ щоциклу) → **K=2 < K=4** припущення бюджету (вище). Реалістично (write-on-change — Flash-KV append-only «останній виграє») у steady-state не змінюється майже нічого: `0x02` пишеться лише на sync-запит, `0x03` — лише під OTA → **K ≲ 1**. Отже для каденсу ≈ 2 год (realistic) бюджет — століття, і це **безпечна нижня межа**; швидкого краю бюджет не має, доки не задано підлогу каденсу WUT (FW.49) — купонні числа L4 його не заміняють. Якщо FW.8 + FW.20-S2 активуються разом (⊕ 2026-10-06: FW.8 ⚫ — не активується, тож сценарій звужується до FW.20-S2, а «~6–8» нижче пораховано з двома ключами FW.8 — без них не перераховано) і знадобиться snapshot-every-cycle, K зросте у бік ~6–8 → erase раз на ⌊254/K⌋ циклів; навіть тоді при realistic delta_t це десятиліття, а за каденсу в хвилини й швидше — роки й місяці → застосувати «розширити page-set» (вище), рішення — разом із підлогою WUT.

> **⚠️ OTA-буфер збирання — окремий випадок (НЕ Flash-KV).** Стан OTA (`ota_buffer` + `ota_chunk_received` + `received_ota_seal` + лічильники чанків) — порядку КБ, і він **мусить** пережити STOP2 (⊕ ціль — Standby, ⚖️ 2026-10-05: там RAM гине щопробудження, тож пережити мусить уже його — §1.10), бо FW.27-B re-request добирає пропущені чанки **між** пробудженнями (Солдат у STOP2 пропускає частину broadcast — §4.6). Класти ~КБ у Flash-KV щоциклу = K у сотні dw → wear-смерть за дні: **неприйнятно**. Висновок для 👤-розвилки (persist-кожен-цикл vs SRAM2-retain): SRAM2-retain — рішення **per-mode, не глобальне**. Steady-state = RTC-only (300 нА); на час активної OTA-кампанії (рідко, хвилини-години) — тимчасово SRAM2 retention ON, потім назад у RTC-only. Це знімає і wear, і відмову «OTA ніколи не збереться під SRAM2-off».

#### 2.3.2 RTC headroom — чи можна звільнити DR замість Flash (FW.54 reclamation)

> **Виклик премісі.** §2/§2.2/§2.3 кажуть «20 регістрів зайнято → нова фіча у Flash». Це правда про **allocation**, але НЕ про **utilization**: кілька DR несуть жменю реальних біт у 32-бітному слоті, а один тримає write-once стан там, де він не потрібен. Перш ніж платити Flash-wear (§2.3) — є дешевший RTC-headroom. Реклемація розкладена по трьох осях.

**Вісь 1 — ширина (під-використані біти).** Кілька слотів несуть <8 біт корисного:

| DR | Реальні біти | Реклемація | Ціна |
|----|--------------|------------|------|
| `DR2` `has_mesh_relay` | **1** (прапорець 0/1) | → біт у вільному `DR0[15:11]` ⇒ **DR2 вільний** | нуль, mode-independent |
| `DR13` / `DR14` | 0 — з HW.30 не несуть нічого | реклемація не потрібна: TinyML-пороги пішли з пʼєзо ⇒ **обидва вільні** (§2) | нуль |
| `DR19` `LORENZ_STATE_MAGIC` | 32 (чистий маркер) | 5-біт sentinel у `DR0[15:11]` (як EMA `0x45` у DR12) ⇒ **DR19 вільний** | слабша bit-flip-стійкість за 32-біт маркер |

> `has_mesh_relay` (1 біт) сідає у вільні біти `DR0[15:11]` **без жодного нового регістру**. ⊕ 2026-09-29 (HW.30): `warning_counter`, головний live-споживач FW.54, що мав сісти туди ж, пішов разом із пʼєзо.

**Вісь 2 — частота запису (інверсія RTC↔Flash).** RTC backup безкоштовний щодо wear; Flash має wear + erase-блокує-шину. Оптимум: **write-ONCE → Flash** (нуль wear, ідеально), **часто-оновлюване → RTC**. Зараз **навпаки**:

- `DR7` `tree_did` — **write-once identity** у дефіцитному wear-free RTC; а часто-оновлюваний FW.54-стан (§2.3) виштовхується у wear-prone Flash. Інверсія.
- DID уже відомий провіженінгу: K_seed деривується **з DID** (`SilkenNet::SeedDerivation`, `info = "silken-lorenz-seed|<DID>"`; firmware-дзеркало — SEC.11 / §2) → щоб запекти K_seed у Protected Flash, host **мусить** знати DID на провіженінгу.
- ⚠️ Firmware до 2026-06-12 **самогенерував** DID з UID **⊕ true_random** і тримав лише в DR7. Наслідки: (1) DID **не VBAT-durable** → повний розряд EDLC (зимовий голод Солдата — [`02_03 §9.8а`](02_03_BQ25570_MPPT_Nano_Power), HW.44 — а cold-start machinery саме й існує, бо VBAT-loss очікуваний) **сиротив identity/гаманець** новим random-DID; (2) DID **не відтворюваний** → провіженінг не міг його передбачити, лише device-first (пристрій репортить → host деривує K_seed 2-м проходом).
- ✅ **ВИРІШЕНО (founder 2026-06-12): детермінований DID = f(UID)** без random — recompute на boot з always-present UID `0x1FFF7590`, зберігати нічого (кеш теж не потрібен) ⇒ **DR7 вільний** + DID VBAT-durable + однопрохідна фабрика. Канон механізму — **§7** (`did_derive.h` + Ruby-дзеркало `SilkenNet::DidDerivation`, golden freeze-contract обабіч). Альтернативу backend-assigned→Protected Flash відхилено (без self-derivation пристрій не має identity поза фабричним транскриптом; Flash-write на провіженінгу зайвий). Колізії ловить фабрична DB-unique-перевірка — деталі §7.

**Вісь 3 — durability-клас (transient operational).** RTC backup = VBAT-durable. Та частина стану потребує лише warm-STOP2-виживання, не VBAT-durability, і має прийнятну loss-on-power-cut семантику:

- `DR3`–`DR6` mesh-relay payload + `DR8`/`DR9`/`DR11` anti-pingpong кеш — транзитний/операційний (чужий пакет у транзиті; recent-DID дедуп). Втрата на cold-path безпечна (мережа має TTL/retry). У RTC лише щоб пережити майбутній SRAM2-off.
- **Реклемація (mode-coupled):** під per-mode SRAM2 (§2.3.1 OTA-висновок: SRAM2 ON у вузьких активних вікнах, RTC-only у steady-state) цей клас живе у SRAM → до **~8 регістрів** звільняється. Ціна: зчеплено з per-mode рішенням + втрата mesh-стану на холодних шляхах. `recent_mesh_dids` додатково стискається до 16-біт DID-хешів (3 у ~1.5 рег) ціною рідких хеш-колізій.

**Синтез + bottom-line для FW.54.** Усі 20 *allocated*, але мапа mis-allocated по трьох осях. Дешева реклемація (Вісь 1: DR2 тривіально; `warning_counter` у `DR0[15:11]`) **повністю розміщує live-набір FW.54 у RTC — Flash-KV для нього НЕ потрібен**. ⊕ 2026-09-29 (HW.30): live-набір звузився до двох wall-маркерів (`0x02`/`0x03`), а вільних регістрів уже без жодної реклемації три (DR7 · DR13 · DR14). Flash-KV (§2.3) лишається виправданим лише для (а) gated bulk (FW.20-S2 bitmap; FW.8 config — ⚫ 2026-10-06) ЯКЩО активуються, і (б) **не** OTA-буфера (це per-mode SRAM2, §2.3.1). Найбільший одиничний чистий виграш — **Вісь 2 (DR7/DID)**, що заразом закриває latent identity-orphaning. Порядок при наступній витраті регістру (доповнює §2.3): **(0) реклемація DR — Вісь 1 → Вісь 2 → Вісь 3 перед будь-яким Flash**.

### 2.4 Helper macros sketch (RTC_BKUP_Read32 / Write32) [ARCH.28]

Поточний код використовує `HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DRn)` / `HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DRn, val)` напряму у ~12 місцях `firmware/soldier/main.c` + ~3 у `firmware/queen/main.c`. Це робоче рішення для TRL-6, але втрачаємо логування. Майбутній рефакторинг (deferred):

```c
// Запропоновані обгортки (ще НЕ застосовані — це freeze-контракт SSOT для §2):
#define RTC_BKUP_READ32(reg)         HAL_RTCEx_BKUPRead(&hrtc, (reg))
#define RTC_BKUP_WRITE32(reg, val)   HAL_RTCEx_BKUPWrite(&hrtc, (reg), (uint32_t)(val))
// Опційно — debug-build trace:
#if RTC_BKUP_TRACE_ENABLED
  #define RTC_BKUP_WRITE32(reg, val) do { \
      DBG_RTC("DR" #reg " <- 0x%08lX", (uint32_t)(val)); \
      HAL_RTCEx_BKUPWrite(&hrtc, (reg), (uint32_t)(val)); \
  } while (0)
#endif
```

> **Чому НЕ застосовуємо зараз:** заміна 15 викликів торкається hot path (Phase 5 STOP2-write і ARCH.21 PVD callback) — кожне торкання потребує перевірки **всієї** родини `test_arch21_pvd_*` і `test_sec10_*` (перелік дає сам глоб по `firmware/test/`; числа тут не наводимо — вони дублюють патерн і тухнуть окремо від нього) + усього існуючого test-bank. Користь — лише консистентність + опційне трасування. ROI на TRL-6 негативний; повернутися до цього при рефакторингу під RTOS (ARCH.29) або при першому реальному debug-сесії з польового пристрою.

> **Cross-link:** `00_07 ARCH.28` — RTC Backup Domain allocation policy.

---

## 💾 3. Soldier RAM Budget (~2 KB з 64 KB SRAM)

| Змінна | Тип | Розмір | Призначення |
|--------|-----|--------|-------------|
| `aes_key[4]` | `uint32_t` | 16 B | AES-128 LoRa ключ (post-ARCH.42; Soldier; per-device через HKDF) |
| `lora_payload[16]` | `uint8_t` | 16 B | Вихідний payload перед шифруванням |
| `encrypted_payload[16]` | `uint8_t` | 16 B | Зашифрований payload для Radio.Send |
| `mesh_relay_payload[16]` | `uint8_t` | 16 B | Транзитний зашифрований mesh-пакет |
| `recent_mesh_dids[3]` | `uint32_t` | 12 B | Кеш DID для anti-pingpong (FW.21: shrunk 8→3, vcap_x10 запаковано у low 16 біт DR12 щоб звільнити DR11) |
| `incoming_lora_payload[256]` | `uint8_t` | 256 B | Вхідний LoRa буфер (volatile) |
| `decrypted_rx_payload[256]` | `uint8_t` | 256 B | Розшифрований вхідний потік |
| `ota_buffer[1024]` | `uint8_t` | 1024 B | OTA байт-код (assembly buffer) |
| `ota_chunk_received[256]` | `uint8_t` | 256 B | OTA dedup bitmap (один bit = один chunk) |
| **Всього** | | **~2 KB** | Лише перелічені змінні (аудіо-буферів з HW.30 немає); повну статику TU міряє CI-гейт [FW.26] (`firmware/scripts/check_ram_budget.sh --hal-objects`) |

**Стек — окремо від статики:** перевірка печатки OTA бере пік ≈2.0 КБ (FW.23, статичний граф GCC, [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)) — проти 12 КБ стек-резерву, чий One-Home до продового `.ld` — `firmware/sim/wle5_bench/stm32wle5.ld` (`__stack_reserve__`); ⊕ 2026-10-09: карта образу для mini (`hal_glue/boards/lora_e5/stm32wle5jc_soldier.ld`) несе його дзеркало, і рівність судить CI (крок FW.26), а ELF образу проходить той самий бюджет статики Солдата. Рахується поверх глибини місця виклику (RX-гілка головного циклу), а не від нуля.

---

## 👑 4. Queen — Архітектура Шлюзу-Агрегатора

### 4.1 Апаратна Платформа — дім [`03_02 §10`](03_02_Queen_Gateway_Firmware)

Повна HAL-периферія Королеви (включно з `hspi1` → W25Q32JV NOR Flash, ARCH.35 Overflow Tier) — [`03_02 §10`](03_02_Queen_Gateway_Firmware). Тут лишається лише те, що Queen ділить із Soldier ту саму MCU-платформу — родину STM32WLE5 (Queen — `JC`, [`02_05`](02_05_Queen_Hardware_and_Starlink); вузол — `CC`, §1.1), а отже й той самий ISR-каркас (§6 нижче).

### 4.2 Загальний Lifecycle

```
Init → Radio.Init → Radio.SetChannel → Lora_Phy_Apply_Tx/Rx [FW.61] → Radio.Rx(0xFFFFFF) [infinite]
┌─────────────────────────────────────────────────────────┐
│  while LoRa_Rx_Ring_Pop(rx_payload, &rx_rssi):  [FW.3]  │
│    1. AES-128-ECB Decrypt (16 bytes) [post-ARCH.42]    │
│    2. OTA Reflex Shot (if ota_is_active)               │
│    3. Extract sender DID (bytes 0-3)                   │
│    4. Process_And_Cache_Data(DID, payload, RSSI)       │
│    5. Radio.Rx(0xFFFFFF) → next pop                    │
│                                                         │
│  if cache_count >= 45 OR timer >= 1hour + jitter:      │
│    Health-блок у QATT-v2 header (ARCH.54; DID=0 retired)│
│    [MX_CRYP re-init → CRYP_KEYSIZE_256B + coap_key]   │
│    Flush_Cache_To_Rails() → CoAP PUT (AES-256-CBC)     │
│    [restore → CRYP_KEYSIZE_128B + LoRa aes_key — SEC.8]│
└─────────────────────────────────────────────────────────┘
```

### 4.3–4.5 CIFO-кеш · Flush до Rails · OTA Reflex Shot — дім [`03_02`](03_02_Queen_Gateway_Firmware)

Три ланки Queen-конвеєра описані в її власному домі, і кожна там **повніша**: `struct EdgeCache` + алгоритм евікції — [`03_02 §2`](03_02_Queen_Gateway_Firmware) · flush до Rails і повний цикл AT-взаємодії з модемом — [`03_02 §3`](03_02_Queen_Gateway_Firmware) + [`03_02 §4`](03_02_Queen_Gateway_Firmware) · OTA-бродкаст — [`03_02 §5`](03_02_Queen_Gateway_Firmware).

> ⛔ **Не відтворювати їх тут — виміряно й відкинуто 2026-09-04 (DOC-T.98), і копія була НЕБЕЗПЕЧНА, а не просто зайва.** Оголошений периметр цієї сторінки — «життєвий цикл, переходи сну, ISR»; евікційна політика кешу, AT-послідовність модема й парсер OTA-чанка не є жодним із трьох. Три виміряні розходження: `struct EdgeCache` стояв **без поля `int8_t snr`** [E.8], але з підсумком дому (`50 слотів = 1150 байт` — при чотирьох полях це 22 Б × 50 = 1100, тобто арифметика ламалась на власному рядку) · крок flush вчив граматики `AT+CCOAPNEW`/`AT+CCOAPSEND`, яку дім називає **неіснуючою в сімействі SIMCom** (FW.56 додав обовʼязковий `AT+CDNSGIP`, FW.3 замінив блокувальний `HAL_Delay` на response-driven токенайзер) — тобто на кремнії ця послідовність не виконається · HAL-таблиця не знала `hspi1` → W25Q32JV (ARCH.35 Overflow Tier).
>
> 🔑 **Прецедент у цьому ж файлі:** §5 нижче зведено до рефа з дослівно тим самим діагнозом — «Queen-таблиця тут раніше тихо розійшлась із домом». Той прохід зупинився на межі §4; цей його доробив.

### 4.5а Downlink Opcode Map — Canonical SSOT [DOC.4]

Карта маркерів downlink-пакетів (CoAP Rails→Queen та LoRa Queen→Soldier). Будь-який новий downlink-CMD **повинен** додаватися сюди до імплементації, щоб уникнути колізій. Опкоди розташовані у безпечному діапазоні `0x99..0x9F` (значення байтів, що не зустрічаються як прийнятні DID-prefixes у telemetry uplink — DID = murmur3-fmix32 від UID (§7) — старший байт `0x99..0x9F` так само малоймовірний).

| Опкод | Назва | Напрямок | Лінк | Документ | Статус |
|-------|-------|----------|------|----------|--------|
| `0x55` | OTA_REQ_MARKER (Magic Re-Request) | Soldier→Queen | LoRa **uplink** | [`03_02 §5.1.3`](03_02_Queen_Gateway_Firmware) | ✅ FW.27-B (2026-05-02) · ✅ [FW.68] 2026-10-09: `total = 0xFFFF` — перезапит трейлера печатки (маска відсутніх блоків — перший байт bitmap); Королева зойк лише записує й віддає боргом — рефлекс-пострілом на наступні кадри того ж DID; розкладка — `firmware/common/ota_rerequest_wire.h` |
| `0x56` | SYNC_REQ_MARKER («Королево, час!» / cold-boot hello: DID + secs_since_sync + 'S' + vcap_mv у байтах 11..12) | Soldier→Queen | LoRa **uplink** | [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor) (ARCH.41-C) | ✅ hello + Queen-перемотка маяка; drift-watchdog re-request вшито у ФАЗУ 4 — 0x56 ПОВЕРХ телеметрії за cooldown-гейтом (2026-07-12, [`03_02 §5а.1`](03_02_Queen_Gateway_Firmware) ③) |
| `0x57` | DEVICE_EVT_MARKER (device-event: `[code:1\|arg:4\|'E':1\|TTL:1\|seq:2\|vcap:2]`; code 0x02=canary-trip) | Soldier→Queen→Rails | LoRa **uplink** + CoAP `device/event/<uid>` | `firmware/common/device_event.h` + [`03_05 §2.2а`](03_05_Hardware_Symmetric_Crypto_and_Security) | ✅ SEC.21 L1 (Королева витягує cleartext → підписує EDSK тегом QEVT1 → `DeviceEventWorker` verify gateway-origin; trust L1-observational, ніколи не money-path) |
| `0x99` | OTA_MARKER (bytecode chunks) | Rails→Queen→Soldier | CoAP (poll-fetch [FW.60])/LoRa | §4.4 + 03_02 §5 | ✅ |
| `0x9A` | CMD_SET_THRESHOLDS (Lorenz Z per-tree) | Rails→Queen→Soldier — адресний CCM-кадр 23 Б сесійним ключем цілі ([`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)) | CoAP/LoRa | [`05_02 §4а.1`](05_02_Proof_of_Growth_Pipeline) | ⚫ FW.8 (2026-10-06, поглинуто гілкою (Б)): опкод знімає реалізація (Б) ([`00_07`](00_07_Action_Plan_Tracker) FW.66), фліпу не буде; доти написані приймач Солдата (CCM-шлях, `FW8_PARSER_ENABLED 0`), черга Королеви й відправник Rails (`Downlink::ThresholdBand`, ENV `FW8_THRESHOLDS_DOWNLINK_ENABLED`) |
| `0x9B` | CMD_OTA_SEAL (Ed25519-печатка OTA: 6 сегментів підпису + версія) | Rails→Queen→Soldier | CoAP/LoRa | [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning) | ✅ FW.23 (2026-05-02; Ed25519 — 2026-10-06) |
| `0x9C` | CMD_TIME_SYNC (envelope) | Rails→Queen | CoAP (кожна poll-відповідь [FW.60]) | §11 (FW.20) | ✅ FW.20 |
| `0x9F` | OTA_FETCH_HINT (анонс кампанії: `[0x9F][fw_id:4 BE][total:2 BE]`) | Rails→Queen | CoAP (poll-відповідь) | [`03_02 §4а`](03_02_Queen_Gateway_Firmware) | ✅ FW.60 |
| `0x9D` | ⛔ **RETIRED** — колишній CMD_SET_AUDIO_THRESHOLDS (TinyML per-Soldier) | — | — | [`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security) | ⛔ виведено 2026-09-29 разом із пʼєзо (HW.30) лок-степом: приймача в прошивці й кадру в Rails немає (`downlink_ccm.h` · `Downlink::CommandFrame`); байт **НЕ перевикористовувати** — виведений, але не вільний |
| `0x9E` | CMD_ROTATE_KEY (hash-ratchet advance-to-version) | Rails→Queen→Soldier — адресний CCM-кадр 17 Б ([`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)) | CoAP/LoRa | [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security) | 🟡 FW.17 (приймач Солдата й черга — CCM-форма; активація — після FW.2 CCM; Rails-ногу ревізії реалізовано 2026-09-29) |
> 🔴 **Політика розширення — і простір `0x99..0x9F` ВИЧЕРПАНО: вільних значень у ньому НЕМА жодного** (усі сім зайняті таблицею вище — RETIRED `0x9D` теж, бо виведений байт не повертається в обіг; плюс `0x55`/`0x56`/`0x57` на uplink-боці). Тобто гілка «обговорити перепакування або новий безпечний діапазон» більше не запасна — вона єдина. Перед додаванням нового опкоду: (1) перевірити цю таблицю, (2) **обрати діапазон, а не значення** — і обґрунтувати, чому нове старше-байтове вікно не колідує з DID-префіксами телеметрії (саме ця властивість і зробила `0x99..0x9F` безпечним), (3) задокументувати тут І у відповідному функціональному документі (03_02/03_05/05_02). ⚠️ Зайнятість перевіряй ТАБЛИЦЕЮ, не цим абзацом: припис, що називає конкретне вільне значення, стає невиконуваним рівно тоді, коли хтось те значення займе — а зайняти його приходять сюди ж.
>
> **Ключ LoRa-шару (CCM-ера, FW.2 (в)):** кластерні опкоди цієї карти — downlink-broadcast (`0x99` · `0x9B` · `0x9C`) та uplink-кадри (`0x55`/`0x56`/**`0x57`**) — їдуть 16B ECB на **cluster control-plane KEYB**; адресні команди `0x9A` · `0x9E` — з 2026-09-29 лише CCM сесійним ключем цілі (23 · 17 Б; `0x9D` того ж дня виведено з пʼєзо, HW.30; [`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)), бо живий приймач під KEYB = підробка на весь кластер ([`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security) двоключова модель); session KEYL носить лише телеметрію/panic (30B CCM rev2.1). ECB-ера — єдиний спільний ключ, і з 2026-09-28 це саме KEYB: на ньому їде й ECB-телеметрія ([`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security), врізка «ECB-ера»).

### 4.6 CoAP Downlink → OTA RAM Assembly — дім [`03_02 §5`](03_02_Queen_Gateway_Firmware)

Збірка OTA-образу в RAM із CoAP-downlink (шість guard'ів парсера чанка, явний `len`, CRC16, поведінка при дірі в бітмапі) — [`03_02 §5`](03_02_Queen_Gateway_Firmware). Карта опкодів, якими цей тракт керується, лишається тут — §4.5а вище (`[DOC.4]`, канонічний дім).

### 4.7 Actuator Command Dedup — дім [`03_02 §6`](03_02_Queen_Gateway_Firmware)

Ідемпотентність actuator-наказів на Королеві (MID-вікно, евікція, поведінка при повторі) описана в її власному домі — [`03_02 §6`](03_02_Queen_Gateway_Firmware). Тут лишається лише те, що ця дедуплікація є частиною Queen-lifecycle (§4.2 вище).

## 💾 5. Queen RAM Budget

Повний бюджет RAM Королеви — канон [`03_02 §9`](03_02_Queen_Gateway_Firmware) (з усіма FW.3/E.8-буферами: `lora_rx_ring`, `batch_attest_buffer`, OTA-скаляри). 03_01 — дім лише **Soldier** RAM (§3); Queen-таблиця тут раніше тихо розійшлась із домом (stale pre-FW.3 буфери, неузгоджений підсумок) → зведено до рефа.

---

## ⚡ 6. ISR Map (Апаратні Рефлекси)

### 6.1 Soldier ISR

| Callback | Тригер | Дія | Пріоритет |
|----------|--------|-----|-----------|
| `OnRxDone(payload, size, rssi, snr)` | LoRa RX complete (SX1262) | `memcpy` → volatile buffer, RSSI clamp [-128,127], `lora_rx_flag = 1` | Апаратний |
| `HAL_PWR_PVDCallback()` | VDD < 2.2 В (VPVD1; іоністор PVD не бачить — шину тримає buck) | **[ARCH.21]** BKUPWrite packed DR0 (усі 4 поля: panic · canary · vm_err_streak · acoustic) + DR1 (`last_wakeup`) + DR16-DR19 (Lorenz state + magic), Radio.Standby → Radio.Sleep (`Set_Sleep` радіо приймає лише зі Standby — RM0461 Rev 11 §4.8.3), кома: STOP2 через sleep-on-exit, кінець — скид на підйомі VDD (за `FW54_STANDBY_ENABLED` — Standby, вихід лише через WUT); спад — за PVDO ([`FW.69`](00_07_Action_Plan_Tracker)) | пріоритет 0 — найвищий налаштовний, не NMI |

> ⛔ **EXTI- і DMA-рефлексів у Солдата з HW.30 (2026-09-29) немає:** `HAL_GPIO_EXTI_Callback` + `EXTI0_IRQHandler` і `HAL_ADC_ConvCpltCallback` / `HAL_ADC_ErrorCallback` + `DMA1_Channel1_IRQHandler` пішли разом із пʼєзо й аудіо-вікном (§1.5). `DMA1_Channel1_IRQHandler` Королеви (§6.2) — інший чіп і власний USART1-RX, до цього не причетний. Урок про вектори (власного `stm32wlxx_it.c` репо не має — вектори живуть у `main.c`, і board-freeze [`FW.46`](00_07_Action_Plan_Tracker) зведе їх із `.ioc`-івським `_it.c` гучно, на лінку) — `firmware`-гоча #14.

**PVD — аварійний рефлекс смерті [ARCH.21]:**
```c
static volatile uint8_t pvd_coma = 0;   // [FW.69] кома триває: наступний підйом VDD — її кінець
void PVD_PVM_IRQHandler(void) { HAL_PWREx_PVD_PVM_IRQHandler(); }  // вектор — у main.c, не в .ioc

void HAL_PWR_PVDCallback(void) {
    if (!__HAL_PWR_GET_FLAG(PWR_FLAG_PVDO)) {   // підйом
        if (pvd_coma) NVIC_SystemReset();      // кінець коми: продовження через скид, стан у DR
        return;
    }
    if (pvd_coma) return;                      // ще один спад посеред коми
    // [SEC.10 · SEC.20 · SEC.21] Спакована DR0 — усі 4 write-sites пишуть ЧОТИРИ поля (§2)
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
        ((uint32_t)(canary_tripped & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT) |
        ((uint32_t)(ota_vm_error_streak & OTA_VM_ERR_STREAK_MASK) << OTA_VM_ERR_STREAK_DR0_SHIFT) |
        (uint32_t)acoustic_events);  // усі 4 поля — часткове слово обнулить сусідів
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, last_wakeup_timestamp); // delta_t continuity
    // [ARCH.21] Сторожовий пес траєкторії — рятуємо Lorenz state симетрично до Phase 5.
    // Без цього rescue брауноут = втрата траєкторії = cold-start через HKDF на наступному
    // boot'і = розрив growth_points streak = false slashing.
    if (lorenz_state_valid) {
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR16, float_to_uint32(lorenz_x));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR17, float_to_uint32(lorenz_y));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR18, float_to_uint32(lorenz_z));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR19, LORENZ_STATE_MAGIC);
    }
    Radio.Standby();   // Set_Sleep радіо приймає лише зі Standby (RM0461 Rev 11 §4.8.3)
    Radio.Sleep();
#if FW54_STANDBY_ENABLED
    Silken_Standby_Enter(&g_standby_ops);
#else
    pvd_coma = 1;                                   // [FW.69] не спимо В перериванні —
    HAL_SuspendTick();                              // ядро засне на ВИХОДІ з нього
    MODIFY_REG(PWR->CR1, PWR_CR1_LPMS, PWR_LOWPOWERMODE_STOP2);
    SET_BIT(SCB->SCR, SCB_SCR_SLEEPDEEP_Msk);
    HAL_PWR_EnableSleepOnExit();
#endif
}
// Старт уже нижче порогу (PVDO під час озброєння в main): колбек + for (;;) __WFI();
```

> ⚖️ **[FW.69] Рефлекс брауноуту засинав у перериванні без виходу — ДЕЛЕГОВАНО 2026-10-09** (мандат founder-а на §03a/§03b; знайшов адверсар образу для mini, [`00_07`](00_07_Action_Plan_Tracker) FW.69). **Дефект:** колбек викликається з переривання PVD з найвищим пріоритетом і засинав там через WFI, а WFI будить лише переривання, що може ПЕРЕВИЩИТИ поточне, — тобто ніщо: плата спала б до NRST чи вмикання живлення (IWDG у STOP2 конвеєр 1.3 заморожує), хоча коментар обіцяв «поки напруга не підніметься». Підйом VDD приходить тим самим IRQ і знову запускав «смерть», `HAL_ResumeTick` не стояло ніде, а PVD озброювали ДО відновлення стану з DR — ранній брауноут записав би в DR нулі з RAM (лічильники SEC.10/SEC.20/SEC.21, `last_wakeup`). **Присуд:** (1) колбек діє лише на спад — PVDO; (2) сон у STOP2 — через WFE із SEVONPEND (⊕ ХИБНО — першу форму того ж дня спростував адверсар, чинна — абзац ⊕ нижче), тож подією стає будь-яке очікуване переривання незалежно від пріоритету: і підйом VDD (той самий IRQ PVD — HAL знімає його pending перед колбеком), і майбутній WUT ([`SEC.15`](00_07_Action_Plan_Tracker)); прокинувшись — `NVIC_SystemReset`, продовження через уже збережений стан, як у Standby-гілці; (3) PVD озброюється ПІСЛЯ відновлення DR, хибний pending знімається, NVIC вмикає сам `main.c`, а не згенерований `HAL_MspInit` (той озброїв би його задовго до відновлення — вимога до `.ioc` на board-freeze); (4) старт, що вже нижче порогу, фронту не дасть — рефлекс тоді кличе сам `main.c` за PVDO. **Відкинуто:** прапор у колбеку й сон у Phase 5 — цикл ще мілісекунди працює на просілій шині й потребує перевірок у кількох фазах; знизити пріоритет PVD під джерело пробудження — пробудження поверталося б посеред перерваної фази зі зміненим тактом, а без WUT будити однаково нікому. **Ціна:** кожен брауноут — повний старт, як у Standby-ері. **Найслабша ланка:** SEVONPEND будить БУДЬ-ЯКЕ очікуване переривання: увімкнене IRQ, що спрацює до підйому, дасть скид на ще просілій шині, і старт за PVDO засне знову — петля коротких стартів коштує енергії, не стану; на кремнії не перевірено. **Межа покриття:** HAL-половина — ARM compile-lane (`hal_check` · `hal_check_ccm` · `soldier_lora_e5`), без виконання; стенд — RUNBOOK 3.6.

> ⊕ **Адверсар застосування (2026-10-09) — перша форма (WFE із SEVONPEND) лишала той самий дефект, який закривала; переписано тим самим днем.** (1) **Перегони:** SEVONPEND робить подією ПЕРЕХІД у очікування, а не сам стан; підйом VDD між читанням PVDO і першим WFE — імовірний, бо `Radio.Standby()` саме знімає навантаження, що просадило шину, — лишав IRQ PVD очікуваним без події, а `SEV; WFE; WFE` ковтав і подію, що прийшла у вікно, — і плата знову спала до скиду. (2) **Недоведене:** чи стає подією повторне очікування того САМОГО активного переривання, архітектура не гарантує — а саме на цьому стояв головний вихід. **Чинна форма — кома через sleep-on-exit:** колбек рятує стан, присипляє радіо, ставить `pvd_coma`, STOP2, SLEEPDEEP і SLEEPONEXIT — і ПОВЕРТАЄТЬСЯ; ядро засинає на виході з ISR. Підйом посеред тіла лишає IRQ PVD очікуваним, і воно ланцюжком входить знову; пізніший підйом — неактивне переривання, і воно витісняє сон, як будь-яке інше; в обох випадках колбек бачить PVDO = 0 при `pvd_coma` і робить скид. Інші переривання (майбутній WUT) лише відбувають своє й повертають плату в сон — петлі коротких стартів, названої найслабшою ланкою вище, тут немає. Старт уже нижче порогу — колбек і `for (;;) __WFI();` у `main`: у thread mode sleep-on-exit не спрацює. **Вектор `PVD_PVM_IRQHandler` переїхав у `main.c`:** якщо його не позначити в `.ioc`, слабкий псевдонім стартового файлу впав би в `Default_Handler` — нескінченну петлю на пріоритеті 0, без жодного запису в DR; згенерований дубль тепер дасть помилку лінку, а не тихий злам. **Що лишилось відкритим:** Standby-гілка (`FW54_STANDBY_ENABLED`) має той самий клас — у Standby PVD будить лише спад (DS13105), тож вихід із коми там — тільки WUT ([`SEC.15`](00_07_Action_Plan_Tracker)) — нога [`FW.69`](00_07_Action_Plan_Tracker); а справжній драйвер радіо в цьому ISR кличе `RADIO_DELAY_MS(2)`, тобто `HAL_Delay`, який тут не повернеться (гоча `firmware` #21), — до `radio_conf.h` вузол до коми не дійде. **Найслабша ланка нової форми:** поведінка STOP2 через sleep-on-exit на WL кремнії не міряна — RUNBOOK 3.6.

> ⚠️ `RadioSleep()` закінчується `RADIO_DELAY_MS(2)`, а в шаблоні ST це `HAL_Delay`, який у цьому перериванні не повернеться (SysTick — найнижчий пріоритет): створюючи `radio_conf.h`, див. гоча `firmware` #21.

**Trigger_Emergency_LoRa_TX (Panic Payload + SEC.10 Frame Counter)** — з HW.30 викликача немає: транспорт лишено як можливого носія сигналу «моє дерево впало» ([`00_07`](00_07_Action_Plan_Tracker) HW.52; ⛔ прибирається лише разом із його присудом):
```c
// [SEC.10] Інкрементуємо лічильник panic-кадрів (saturating @ 0xFFFF) ПЕРЕД пакуванням.
if (panic_frame_counter < 0xFFFF) panic_frame_counter++;

panic_payload[7]  = 0xFF;          // Acoustic = 0xFF = насичений лічильник паніки
panic_payload[10] = PANIC_FLAG_BIT; // [FW.29] bit 7 = 1 → однозначний маркер panic
panic_payload[11] = Ttl_Byte_Pack(5, 0u);  // [FW.18b] TTL=5 у нижніх 3 бітах; верхні 5 з HW.30 — 0
// [SEC.10] Counter BE у байтах 14..15 (вільні PAD bytes після firmware_id у 12..13)
panic_payload[14] = (uint8_t)(panic_frame_counter >> 8);
panic_payload[15] = (uint8_t)(panic_frame_counter & 0xFF);
// Persist негайно у DR0 — до Phase 5 могло не дійти при PVD/reset (усі 4 поля, §2)
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
    ((uint32_t)panic_frame_counter << PANIC_COUNTER_DR0_SHIFT) |
    ((uint32_t)(canary_tripped & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT) |
    ((uint32_t)(ota_vm_error_streak & OTA_VM_ERR_STREAK_MASK) << OTA_VM_ERR_STREAK_DR0_SHIFT) |
    (uint32_t)acoustic_events);
// AES-128-ECB Encrypt → Radio.Send [post-ARCH.42] → 100ms → Radio.Sleep
```

> **[FW.29] Навіщо окремий PANIC_FLAG_BIT?** До FW.29 backend розрізняв паніку лише за `acoustic_events == 0xFF`. Але `0xFF` може означати і реальне насичення кавітаційних подій за тривалий час. `PANIC_FLAG_BIT` у байті 10 (StatusByte, bit 7) є однозначним машинним маркером: у нормальному пакеті він завжди `0` (`lora_payload[10] &= ~PANIC_FLAG_BIT`), у panic-пакеті — завжди `1`.

### 6.2 Queen ISR

| Callback | Тригер | Дія |
|----------|--------|-----|
| `OnRxDone(payload, size, rssi, snr)` | LoRa RX (16 Б; у CCM-ері — ще air-кадр) | RSSI clamp → `LoRa_Rx_Ring_Push` (FIFO 15-slot, FW.3) → лічильник `lora_rx_drops` при переповненні |
| `HAL_UART_RxCpltCallback` (через `DMA1_Channel1_IRQHandler`) | USART1-RX circular DMA, повний оберт кільця (TC) | `uart_rx_wraps++` — позицію пера дає NDTR (`uart_rx_ring.h`) |
| `HardFault_Handler` | апаратний fault | `g_fault_marker` у RAM → `NVIC_SystemReset` (reset-cause у QATT) |

Queen не має PVD, EXTI чи IWDG ISR. Мінімальний ISR-footprint + **single-producer ring buffer** дозволяють Queen залишатися "завжди активною" без race conditions і без втрати голосів рою під час 25-секундного CoAP-flush'у (FW.3 — закрито архітектурно host-рівнем: ring buffer + circular-DMA RX; silicon-bench residual → [`00_07 §03a`](00_07_Action_Plan_Tracker)).

---

## 🔐 7. DID Derivation (Ім'я з кремнію)

> **[FW.54 Вісь 2, рішення founder 2026-06-12]** DID **детермінований**:
> `f(96-біт UID)` без random, recompute на кожному boot — зберігати нічого
> (DR7 звільнено, §2). Попередня схема (`UID⊕random` з FW.24-fallback'ом,
> write-once у DR7) мала дві системні вади: DID **не VBAT-durable** (повний
> розряд EDLC — очікувана подія зимового голоду Солдата (HW.44) — сиротив identity/гаманець новим
> random-DID) і **не відтворюваний** (провіженінг був приречений на
> device-first два проходи, хоча K_seed деривується саме з DID). Аналіз —
> §2.3.2 Вісь 2.

```c
// Кожен boot (firmware/soldier/did_derive.h — pure, host-тестований):
tree_did = Did_Derive_From_Uid(*(uint32_t*)(0x1FFF7590),   // STM32 factory
                               *(uint32_t*)(0x1FFF7594),   // UID, 96 біт,
                               *(uint32_t*)(0x1FFF7598));  // read-only
```

Мікс — murmur3-fmix32 ланцюгом (повний avalanche: один біт UID перемішує
весь DID). `DID == 0` неможливий: нуль зарезервовано, бекенд відкидає нульовий DID в
обох ерах (ARCH.54, [`03_02 §7`](03_02_Queen_Gateway_Firmware)) — нуль-хеш
відображається у `"SNET"`-константу. Ruby-дзеркало для фабрики — `SilkenNet::DidDerivation`;
golden-вектори заморожені обабіч (`test_soldier_logic.c` ↔
`spec/services/silken_net/did_derivation_spec.rb`).

> **Колізії та дефектні UID (доля FW.24).** Birthday-математика 32-бітного
> DID однакова для random- і деривованої схеми, але детермінізм робить
> колізію **видимою на фабриці** (DB-unique на `trees.did` при провіженінгу
> → quarantine юніта) замість тихого злиття двох дерев у полі. HRNG-fallback
> FW.24 знято разом з random-схемою: дефектний UID (все-нулі) дає
> детермінований заприсяжений DID (golden g2), і дублікат такого юніта
> впаде на тій самій фабричній перевірці. «Самонародження» без фабрики було
> ілюзією: без SEC.3-провіженінгу пристрій не має ні AES-ключа, ні K_seed.

**Зшито обабіч (2026-07-03):** фабрика (SEC.3) читає UID по SWD ще **до**
прошивки → `FactoryFlashing::TreeResolver` (create / re-flash / bind;
`trees.silicon_uid_hex` відрізняє re-flash того самого чипа від
birthday-колізії → quarantine) → Tree + HardwareKey + K_seed
**однопрохідно**; live wrong-board guard звіряє паспорт плати до першого
`-w32`. Польовий `POST /provisioning/register` — той самий
`wire_did` від 24-hex UID (старий `last(8)`-DID, якого кремній ніколи не
оголосив би, і мертвий для дерев double-init guard — виправлено).
Механіка конвеєра — [`03_06 §2/§5`](03_06_Factory_Flashing_and_Key_Provisioning).

---

## 📦 8. Binary Packet Format (Зовнішній фрейм, 21 байт)

Queen загортає кожен Soldier-пакет у 21-байтний outer frame перед відправкою в CoAP batch:

```
[DID:4][RSSI:1][Payload:16]
```

| Поле | Байти | Тип | Опис |
|------|-------|-----|------|
| DID | 0-3 | uint32 BE | Tree Device ID |
| RSSI | 4 | uint8 | Інвертований сигнал: `(uint8_t)(-(int16_t)rssi)` |
| Payload | 5-20 | uint8[16] | Розшифрований inner payload |

> **RSSI кодування:** `-85 dBm → 85` (uint8). Інверсія через `(int16_t)` cast захищає від UB при rssi == -128.

---

## 🔒 9. Encryption Architecture

Soldier↔Queen LoRa = **AES-128** (ECB transitional → CCM FW.2), Queen↔Rails CoAP = **AES-256-CBC** [post-ARCH.42]. Повна per-channel таблиця (напрямки · режими · IV/nonce) — канон [`03_05 §6`](03_05_Hardware_Symmetric_Crypto_and_Security). Нижче — firmware-специфічні impl-патерни цього вузла (їхній дім — тут).

**ECB Restoration — критичний паттерн:**
Функції `Flush_Cache_To_Rails()` та `Handle_CoAP_Command()` перемикають `hcryp` на CBC для роботи з server-bound трафіком. Після завершення **обов'язково** відновлюють ECB:

```c
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.KeySize   = CRYP_KEYSIZE_128B;  // CoAP-сесія лишила 256-бітний coap_key
hcryp.Init.pKey      = aes_key;            // LoRa-ключ Королеви
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);                     // відмова → RCC-reset AES → retry → NVIC_SystemReset
```

Без цього відновлення всі наступні LoRa-пакети від Soldiers будуть розшифровані неправильно до наступного ребуту Queen — і відновити треба ВСІ три поля: сам режим без `KeySize`/`pKey` лишив би 256-бітний CoAP-ключ. Дім — `Restore_ECB_Mode()` у `firmware/queen/main.c`.

**CoAP batch-IV — дім [`03_05 §4`](03_05_Hardware_Symmetric_Crypto_and_Security) (механіка) + [`03_05 §HRNG Fallback`](03_05_Hardware_Symmetric_Crypto_and_Security) (присуд), тут НЕ дублюється.**

Нормальний шлях — апаратний HRNG (CSPRNG): `HAL_RNG_Init` безпосередньо перед використанням, `HAL_RNG_DeInit` одразу після (нульовий струм сну) — це firmware-специфічна частина, і вона лишається тут. **Сам fallback при відмові HRNG — не тут:** чинна конструкція є **key-derived PRF** `coap_fallback_iv()` (HMAC-SHA256 над `label ‖ uid_hash ‖ unix_ts ‖ flush_seq ‖ tick`, `firmware/queen/coap_iv.h`).

> ⛔ **Не відтворювати тут XOR-маску `tick ^ (i * 0x5A5A5A5A)` — виміряно й відкинуто [SEC.12, 2026-06-15].** Вона давала IV **унікальність**, але не **непередбачуваність**: `HAL_GetTick` спостережуваний, маски константні, тож зловмисник без ключа вгадував IV. Ключ-деривована форма дає обидві властивості в чистому софті (`silken_sha256.h`, FW.30) — без AES-engine, без SEC.8 ECB-restore-танцю і без bench-гейта. **Опис із розділом «чому саме так» тут коштує найдорожче: він читається як чинна рекомендація на грошовому CoAP-каналі.**

---

## 🧪 10. Покриття Host-Based Тестами

Firmware логіка тестується на x86 з GCC (не потребує ARM toolchain):

```bash
make -C firmware/test             # Усі host-based тести (soldier / queen / bio_contract / logmel / audio_model / encryption / …)
make -C firmware/test queen       # Queen-only
make -C firmware/test soldier     # Soldier-only
make -C firmware/test bio_contract # Bio-Contract
make -C firmware/test audio_model # INT8-модель проти golden-векторів silken_ml (актив без call-site з HW.30)
make -C firmware/test encryption  # AES encryption
make -C firmware/test asan        # ASan+UBSan dynamic memory-safety lane (TEST.5; канон 04_06 §B.1.1)
```

**CI:** Firmware тести інтегровані в GitHub Actions (`firmware_test` job у `.github/workflows/ci.yml`).

> Методологія / гейт / тріаж покриття (cross-cutting) — канон [`04_06`](04_06_Testing_Guide_and_Coverage); тут — лише інвентар host-тестів цієї підсистеми (Soldier нижче, Queen — [`03_02 §11`](03_02_Queen_Gateway_Firmware)).

### Тести Queen

Повна Queen host-test-matrix (вкл. FW.1 Flash-key / FW.20 / FW.20-S2 / FW.27-B) — канон [`03_02 §11`](03_02_Queen_Gateway_Firmware). Дублювати тут означало drift (ця копія відставала від дому).

### Тести Soldier

| Модуль | Що покривається |
|--------|-----------------|
| Payload Packing | Всі поля, signed temp, max/zero, pack-unpack roundtrip, reserved=0 |
| DID Derivation | [FW.54 Вісь 2] golden-вектори g1-g4 (freeze-contract з `DidDerivation`-дзеркалом), avalanche, нуль-неможливість + детермінізм на LCG-sweep |
| Mesh Dedup | 3-slot cache (FW.21), eviction, pingpong scenario, relay decisions (OK/echo/known/ttl_zero) |
| OTA Assembly (Soldier) | Multi-chunk, duplicate ignore, buffer overflow, total mismatch, bitmap |
| CRC32 | ISO 3309 known value (`0xCBF43926`), bit flip detection, OTA verify/corrupted |
| Bio-Contract Byte | All statuses, clamping, full 256-combination roundtrip, `0xFF`=VM error |
| Panic Payload | DID, acoustic=0xFF marker, TTL=5, zero fields; **[FW.29]** PANIC_FLAG_BIT встановлений у panic, відсутній у звичайному пакеті |
| OnRxDone Boundary | Normal 16B, 255B accepted, 256B accepted, 257B rejected, 0B rejected |
| Lorenz State Persistence (FW.6) | RTC DR16-DR19, magic marker, NaN/Inf guard, cold boot |
| Acoustic Saturating Increment (FW.22) | Нуль, нормальний приріст, 254→255, 255 залишається 255, насичення, atomic snapshot |
| RSSI Clamping | Нормальні, edge ±128, overflow proof |
| EMA Filter (FW.21) | Cold start, smoothing (α=0.2), convergence, noise rejection, warmup flag, count saturation, zero inputs, overflow max, RTC save/load, cold boot |
| ADC→mV (FW.50) | VDDA recovery, pin voltage, 2:1 divider, div-by-zero guards, raw-count≠mV proof (helper `common/adc_convert.h`) |
| [решта] | Lorenz state + mesh + misc |

> **Що НЕ покривається тестами:** STOP2 wakeup sequence, IWDG timeout, PVD voltage threshold, реальний Radio.Send/Rx, SIM7070G AT-команди. Ці компоненти потребують Hardware-in-the-Loop (HIL) тестування.

---

## 🌿 11. Bio-Contract Specification (`firmware/bio_contracts/bio_contract.rb`)

Цей файл є мостом між C-ядром та математикою Атрактора Лоренца. Компілюється `mrbc` у байт-код (committed mirror `firmware/common/lorenz_bytecode.h`, генерує `tools/firmware/gen_bytecode.sh`, drift-gated — §12.4), який:
- Вбудовується у `lorenz_bytecode[]` через `#include` (FW.46; раніше — manual paste, був placeholder-stub)
- Або оновлюється через OTA → Flash-сектор `0x0803F000`

### 11.1 Структура модуля

```ruby
module SilkenNet
  class Attractor     # Математичне ядро (ізольований хаос)
  class BioContract   # Бізнес-логіка (токеноміка + статуси)
end

# C bridge — єдина публічна точка входу (9-арг сигнатура: SEC.11 cutover + FW.8 смуга; owner [`03_04 §6`](03_04_mruby_Lorenz_Attractor)):
def calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv, z_min, z_max)
  SilkenNet::BioContract.evaluate_and_pack(...)   # логіка status/GP — 03_04 §4/§4.3
end
```

C-код знає **тільки** про `calculate_state` (через `mrb_intern_lit`). Вся логіка всередині `SilkenNet::*` невидима для firmware. `(x_prev, y_prev, z_prev)` — RTC continuation (§2) або K_seed cold-start; `delta_t_s`/`vcap_mv` — EMA з RTC (FW.21).

### 11.2 Attractor — Математичне Ядро (firmware-дзеркало; owner 03_04)

> **Константи (σ=10 / ρ=28 / β=`8.0/3.0` / DT=0.01 / N=250 + clamps SIGMA/RHO), σ/ρ-пертурбація сенсорами (acoustic→σ, temp→ρ) і 250 кроків Ейлера — owner [`03_04 §1.2`](03_04_mruby_Lorenz_Attractor) (firmware↔backend таблиця) + [`03_04 §3`](03_04_mruby_Lorenz_Attractor) (алгоритм крок-за-кроком); тут НЕ дублюємо (One-Home; β=BASE_BETA фіксований після [E.63]).**

**Firmware-специфіка:** початковий стан `(x,y,z)` — НЕ наївний `seed%1000`, а детермінована деривація з per-device **K_seed** через HMAC-SHA256 ([SEC.11 / FW.30], §1.4 + [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning)). Детермінізм критичний: сервер мусить відтворити той самий Z для **Dual Computation Integrity** (це НЕ HRNG-per-wake). Між пробудженнями стан продовжується з RTC DR16-DR19 (§2, FW.6 continuation > 99.9% циклів); cold-start — з K_seed. Серверне дзеркало `app/services/silken_net/attractor.rb` рахує ідентично (DCI крос-верифікація).

### 11.3 BioContract — Статуси та Wire-Пакування

> **Пороги (смуга `z_min`/`z_max` — аргументи C-моста [FW.8], у бойовій збірці дефолти `CRITICAL_Z_MIN`=2.0 / `CRITICAL_Z_MAX`: stress `z < z_min`; anomaly-стеля **ρ-relative** [E.64]: `ρ + (z_max−BASE_RHO)` ≈45 @ ρ=28 і дефолтах) та логіка Z→status→growth_points — owner [`03_04 §4`](03_04_mruby_Lorenz_Attractor); growth_points-формула `m(delta_t)` — [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor) (One-Home). [E.63]: у гомеостазі GP = метаболічна жвавість `m(delta_t)`, НЕ `|29−z|`; Лоренц лишився лише status-гейтом.**

**Firmware-специфіка — StatusByte wire-пакування** (байт 10 payload, FW.29-PACK):

```ruby
# Layout: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)]
# Status переїхав з bits 7..6 → 6..5 (bit 7 = panic-frame marker, FW.29).
payload_byte = (status << 5) | growth_points
```

Status: 0 homeostasis / 1 stress / 2 anomaly / 3 vm_error (mruby VM-збій → `BIO_STATUS_VM_ERROR=0x60`, виживає `& 0x7F` як status=3, **GP=0**; **НЕ** tamper — SLASH-1 P0, фізичний tamper → PANIC_FLAG-канал, з HW.30 без пускача — пʼєзо зрізано). Wire-GP 5-біт (5..31) масштабується ÷2; backend ×2 upscale при unpack (tokenomic invariant). Серверне дзеркало `attractor.rb` звіряє z-val (розходження → DCI Alert).


## 🛠️ 12. Тестова Інфраструктура (`firmware/test/`)

### 12.1 Архітектура x86 Тестів

Тести компілюються GCC на x86/x64 без ARM toolchain. Ключовий компонент — `hal_mock.h`:

```
firmware/test/
  hal_mock.h          — Мінімальні HAL stubs для компіляції без STM32 HAL
  test_soldier_logic.c — pure-logic функції з soldier/main.c
  test_queen_logic.c   — pure-logic функції з queen/main.c
  Makefile             — gcc, -Wall -Wextra -Wpedantic -std=c11 -O2
```

**Принцип:** Тести **не включають** `soldier/main.c` напряму — ця половина чинна. ⚠️ **Друга половина застаріла і знята: дублювання pure-logic у тестовий файл більше НЕ норма, а виняток.** Архітектура переїхала на header-бібліотеки One-Home: pure-logic живе в `firmware/common/*.h`, і тест включає **справжній код** (виміряно 2026-08-22: `test_soldier_logic.c` має 13 таких `#include`, і сам пише «тест бʼє по справжньому коду, не по копії»). ⛔ Не копіюй математику в тест — скіл `firmware` каже те саме («Never fork the math into the test file»): копія розходиться мовчки, і саме проти цього збудовано `common/`. Копіювання лишається легальним ЛИШЕ для логіки, що фізично живе в `main.c` і ще не винесена. Що дає ця конструкція:
- Компілювати на x86 без ARM HAL бібліотек
- Тестувати ізольовану логіку без hardware state
- Запускати в CI (GitHub Actions) без фізичного MCU

### 12.2 HAL Mock — Важливі деталі

**AES Encrypt/Decrypt — прозорі stubs:**

```c
static inline int HAL_CRYP_Encrypt(CRYP_HandleTypeDef *h, uint32_t *in, uint16_t sz,
                                    uint32_t *out, uint32_t to) {
    (void)h; (void)to;
    memcpy(out, in, sz * 4);  // Просто копіює — немає реального шифрування
    return HAL_OK;
}
```

> ⚠️ **Наслідок:** Тести CIFO eviction, OTA dedup, batch packing, ECB restoration — всі перевіряють **структурну логіку**, але не криптографічну коректність. Реальне AES (128 LoRa / 256 CoAP) тестування потребує HIL з апаратним AES модулем.

**HRNG Mock — завжди повертає 42:**

```c
static inline int HAL_RNG_GenerateRandomNumber(RNG_HandleTypeDef *h, uint32_t *v) {
    (void)h; *v = 42; return HAL_OK;
}
```

> ⚠️ **Наслідок:** `test_hrng_iv_all_words_filled` перевіряє що `iv[i] == 42`, але не може перевірити що значення справді випадкове. Тест лише підтверджує, що HRNG викликається коректно.

**ADC Mock — завжди повертає 3000:**

```c
static inline uint32_t HAL_ADC_GetValue(ADC_HandleTypeDef *h) { (void)h; return 3000; }
```

**Temperature Macro:**

```c
#define __LL_ADC_CALC_TEMPERATURE(vref, raw, res) ((int)(25 + ((raw - 1000) / 10)))
// При raw=3000: temp = 25 + (2000/10) = 225°C (нереальне, але детерміноване)
```

**RadioDriver_t — struct з function pointers:**

```c
static RadioDriver_t Radio = {
    .Init = radio_init_stub,         // no-op
    .SetChannel = radio_set_channel_stub, // no-op
    .Send = radio_send_stub,         // no-op (не записує payload нікуди)
    .Rx = radio_rx_stub,             // no-op
    .Sleep = radio_sleep_stub        // no-op
};
```

> Цей підхід дозволяє компілювати `Radio.Send()` та `Radio.Rx()` без реального LoRa driver.

### 12.3 Makefile Деталі

```makefile
CC     = gcc
CFLAGS = -Wall -Wextra -Wpedantic -std=c11 -I. -O2
```

Усі warnings увімкнені (`-Wall -Wextra -Wpedantic`). `-std=c11` забезпечує MISRA-сумісні конструкції (наприклад, explicit casts). `-O2` дозволяє компілятору виявляти dead code та UB під час оптимізації.

**Команди:**
```bash
make -C firmware/test         # Build & run all (default target: queen + soldier)
make -C firmware/test queen   # Queen tests only
make -C firmware/test soldier # Soldier tests only
make -C firmware/test clean   # Remove test_queen, test_soldier binaries
```

### 12.4 ARM cross-compile build (FW.46)

**Дім build-системи прошивки.** До FW.46 закомічченого ARM-build не було — `.elf` збирались зовні (CubeIDE), не відтворювано й не CI-gated. Тепер відтворюваний CMake-крос-компайл того, що ми **володіємо**, живе в репо й гейтиться в CI (`ci.yml › firmware_arm_build`). Повний HAL-лінкований `.elf` — наступний крок (👤, [`00_07` — FW.46](00_07_Action_Plan_Tracker)). ⚖️ **Образ для bench-carrier LoRa-E5 mini — рукописний `hal_glue/boards/lora_e5/`, не bench-`.ioc`: ДЕЛЕГОВАНО 2026-10-06** (подання 2026-10-05; founder того дня делегував ратифікацію відкритих присудів за рекомендацією). **Підстава** (як подано): SEC.15 вимагає committed reviewed fn для армінгу WUT ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security) SEC.15) — регенерований `.ioc` цього не задовольняє за побудовою. ⊕ 2026-10-05: `LSEDRV` low присуджено як вхід `.ioc` вузла (кварц плати ABS06, CL 4 pF, поз. 17) — образ для mini його наосліп не успадковує, бо кварц модуля LoRa-E5 не звірено. **Ціна** (як подано): пін-мапу mini треба зняти з датащита Seeed (у дереві її немає — перша нога при «так»), без CubeMX-валідації; два образи з різними пін-мапами (mini JC ⊥ вузол CC — скіл `firmware` #16). **Найслабша ланка** (як подано): LSE-кварц у модулі mini з датащитом Seeed не звірено — зріз LSE/WUT може не піднятись. ⊕ **Дописано при ратифікації — не частина купленого:** (а) стенд на mini мусить довести пробудження саме тієї функції армінгу, тож образ на коді CubeMX довів би чужу; (б) найслабшу ланку зміряно: кварц LSE 32.768 кГц у модулі є (паспорт Wio-E5 V1.1, Figure 1 — [S8] у [`rf_frontend_forks`](protocols/hardware/rf_frontend_forks.md)), а `PC14`/`PC15` серед виводів модуля немає (Table 1); CL і ESR паспорт не дає — тож `LSEDRV` для mini обирається запасом і перевіряється на стенді, а не успадковується від `LSEDRV` low вузла; (в) пін-мапу знято при застосуванні — таблиця «Пін-мапа LoRa-E5 mini» в розділі «Фізичне Підключення Апаратного Відладчика» на початку цього доку. ⊕ **Образ для mini є — 2026-10-09: таргет `soldier_lora_e5`** (`hal_glue/boards/lora_e5/`: TU-обгортка `main.c` зі справжніми тілами MX_* і MSP, лінкер-карта `stm32wle5jc_soldier.ld`, заглушка радіо з усіма полями `Radio_s`; збірка з `CCM_SELFTEST`) — перший злінкований `.elf` Солдата в історії репо, і саме лінк, а не компіляція, — його гейт у CI-лейні HAL. **Що він дає:** такт MSI 48 МГц; RTC на LSI (календар і backup-регістри живуть, точність — відсотки); АЦП синхронно від PCLK, лише ранг 1; RNG на MSI (скидний PLLQ мовчить); IWDG з найдовшим вікном ≈ 31–35.5 с (LSI 29.5–34 кГц, DS13105); `SysTick_Handler`, без якого HAL-таймаути не спливали б; вектор PVD і його NVIC — у самому `main.c`, NVIC вмикається після відновлення стану ([`FW.69`](00_07_Action_Plan_Tracker)). POST іде ДО завантаження ключів, тож самотест конвеєра 1.3 не потребує: на порожній сторінці ключа `Load_AES_Key` кличе `Error_Handler` → скид, і результат POST переписується на кожному старті — його й читає SWD під скидом. **Чого не дає — свідомо:** LSE і армінгу WUT (SEC.15), тож цикл після POST засинає без джерела пробудження, і плату перезапускає IWDG — лише якщо option byte `IWDG_STOP` його не заморозив; конвеєр 1.3 пише `IWDG_STOP=0`, і тоді плата спить до скиду (на платі без ключів до сну цикл не доходить зовсім — див. вище); радіо — заглушка; GPIO й I²C — не налаштовано. ⚠️ Джерело RTC живе в backup-домені: перший образ із LSE на тій самій платі змінить його, і HAL при цьому скидає домен разом із DR0..DR19. **Що розвідка образу знайшла у вузловому коді — виправлено того ж дня:** АЦП читав два канали без вибору каналу (§1.4) і «Датчик смерті» ставив зовнішній вхід замість порогу 2.2 В (§1.10, PVD). ⚠️ Стеля compile-lanes до того: OBJECT-lib **компілює, не лінкує** → ungated-референс gated-символу (клас OnCadDone link-бомби ARCH.26, знято гейт-симетрією 2026-07-11) невидимий CI аж до повного `.elf` — нова гейтована гілка мусить бути **гейт-симетричною** (прототип + реєстрація + дефініція під одним `#if`). ⊕ 2026-10-09: бойову конфігурацію Солдата (+ `CCM_SELFTEST`) тепер лінкує `soldier_lora_e5`, а гейтовані гілки лінку досі не бачить ніхто.

```
firmware/
  CMakeLists.txt              — owned-код (logmel.c) + CMSIS-DSP + size + guarded HAL
  cmake/arm-none-eabi.cmake   — toolchain-file (Cortex-M4 soft-float; pin Arm GNU 13.2.Rel1)
  mruby/build_config.rb       — mruby builds (host mrbc / host-min / arm minimal)
  extern/                     — pinned submodules (перелік — `.gitmodules`; ролі й піни — §12.5)
tools/firmware/
  gen_bytecode.sh             — mrbc: bio_contract.rb → lorenz_bytecode.h (+ --check drift)
  check_bytecode.py           — light stdlib stamp-gate (CI firmware_test)
  run_bytecode_vm.sh          — minimal-VM harness: ганяє committed bytecode (mrb_load_irep)
```

Детальні recipe (env, локальний прогін, регенерація) — скіл `ml-engineering`. Локально:

```bash
cmake -B firmware/build -S firmware --toolchain $PWD/firmware/cmake/arm-none-eabi.cmake \
  -DCMSISCORE=$PWD/firmware/extern/CMSIS_6/CMSIS/Core   # toolchain path must be absolute
cmake --build firmware/build --target size        # arm-none-eabi-size logmel.o
tools/firmware/gen_bytecode.sh --check            # bytecode mirror == bio_contract.rb
tools/firmware/run_bytecode_vm.sh                 # minimal VM runs the bytecode
```

**ABI-інваріант (FPU-міф знято, 2026-06-10):** STM32WL Cortex-M4 — **без FPU**
(слово "FPU" відсутнє у DS13105/RM0461; рання версія цього розділу і
toolchain-файлів помилково пінила апаратний FPv4 hard-float — такий `.elf` на
кремнії впав би в UsageFault на першій VFP-інструкції). Тому **всі** ARM-збірки
(toolchain-file, mruby `build_config.rb`, обидві QEMU-ноги §12.7) —
`-mfloat-abi=soft`: float і double йдуть software `__aeabi_*`. QEMU-startup
свідомо не вмикає CPACR — випадкове повернення hard-float ловиться як
`PARITY-ABORT fault` (ABI-tripwire), а повернення hard-float токенів у канон
блокує `deprecated_terms`-гейт.

**Виміряний footprint** (вперше — ARM-build раніше не існувало):

| Артефакт | Flash (.text) | Static RAM |
|---|---|---|
| mruby core (bytecode-only, `libmruby_core.a`) | ~117 KB | 0 — mruby 4.0.0 ROM-таблиці у `.rodata` |
| logmel.c (наш DSP, `LOGMEL_USE_CMSIS`) | ~6.3 KB | 28 B |
| lorenz_bytecode (mrbc) | ~2.5 KB | 0 |
| Ed25519-перевірка печатки OTA (Monocypher + SHA-512, FW.23, 2026-10-06) | ~10.8 KB | 0 (пік стеку ≈2.0 КБ) |
| **Повний злінкований образ Солдата** — LoRa-E5 mini, `CCM_SELFTEST` (`soldier_lora_e5`, 2026-10-09) | ≈ 80 % із 244 КБ під сторінкою 122 — число залежить від тулчейну: 198 552 Б (Arm GNU 13.2.Rel1, локально) · 200 960 Б (apt-тулчейн CI) | 3 536 Б статики (+ купа `_sbrk` до стек-резерву 12 КБ) |

> mruby ≈ 46% від 256 KB Flash — інherentна ціна за **OTA-оновлюваний bio-contract** (байткод OTA'ється без reflash). Тримати в бюджеті при HAL-інтеграції. TinyML-модель (baseline 972 B) з HW.30 в образ Солдата не лягає — актив без call-site ([`00_07` — FW.4](00_07_Action_Plan_Tracker), архів).

**mruby build-інваріанти** (verified проти `doc/mruby4.0.md`; джерело — `build_config.rb`):
- **double, не float32:** НЕ ставимо `MRB_USE_FLOAT32` (флаг перейменовано з `MRB_USE_FLOAT` у mruby ≥3.0 — [`00_07` — FW.19](00_07_Action_Plan_Tracker)) → `mrb_float` = double, потрібно для DCI numeric parity ([`03_04 §5`](03_04_mruby_Lorenz_Attractor)).
- **NO_BOXING — ЯВНИЙ пін (2026-06-11):** `MRB_NO_BOXING` у `SILKEN_MIN_GEMS` — бо **дефолт mruby 4.0 = `MRB_WORD_BOXING`** (mrbconf.h), а не no-boxing, як канон вважав раніше. На 64-bit host word-boxing тримає double інлайн (виглядає чисто), на 32-bit WLE5 кожен Lorenz-double йде в heap RFloat'ом — фіт-гейт §12.7 зловив ~20 КБ транзієнту на один `calculate_state`. Відтепер фіт-гейт і є CI-enforcement цього піна (word-boxing на 32-bit одразу рве heap-бюджет). TU, що інклудять mruby-хедери, дзеркалять defines (`MRB_DEFS` у `qemu_parity.sh`, `run_bytecode_vm.sh`).
- **MCU-профіль:** `MRB_CONSTRAINED_BASELINE_PROFILE` (рідний upstream-профіль: heap-сторінки 256 об'єктів замість 1024, без method-cache, малий khash) — з дефолтними сторінками `mrb_open()` не вліз би у 64 КБ SRAM.
- **minimal gembox:** core + лише `mruby-compar-ext` (для `clamp`); core дає `abs`/`round`/`times`. `default-no-stdio` (~254 KB) не влазить у Flash.

**HAL compile-lane (`-DSILKEN_WITH_HAL=ON`, 2026-06-11):** WL-HAL завендорено pinned submodules (`stm32wlxx-hal-driver` v1.6.0 + `cmsis-device-wl` v1.4.0 — консистентна пара за актуальним STM32CubeWL), і CI компілює **обидва** `main.c` (ARM soft-float) проти справжнього HAL — вперше за історію репо. Анатомія: `firmware/hal_glue/` — owned CubeMX-замінники (`main.h`, `stm32wlxx_hal_conf.h` з рівно нашим периферійним набором; `radio.h` тепер вендорний Semtech `extern/subghz-phy/radio_driver` — owned-stub видалено Шляхом A 2026-07-04, §12.5) + wrapper-TU (`{soldier,queen}_hal_check.c` `#include`'ять main.c дослівно і докладають порожні MX-заглушки в той самий TU — main.c-фрагменти незаймані, merge-модель CubeMX збережена). Перший прогін зловив: `__HAL_RCC_CRYP_*` (F4-стиль) не існує на WL → `__HAL_RCC_AES_*` (Soldier STOP2-цикл + Queen `Restore_ECB_Mode`). Передбачені раніше mruby-renames (`mrb_alloca`/`io.h`) не знадобились — main.c їх не вживає.

**Scope-межа (залишок 👤):** повний `.elf` потребує те, чого не можна вигадати без board-freeze: `.ioc` → тіла `MX_*`/`SystemClock_Config` (пін-мапа, клок-дерево, ADC-канали, LSE — [`00_07` — FW.49/FW.50](00_07_Action_Plan_Tracker)) + компіляція SubGHz_Phy `radio.c` middleware (`radio_conf.h` з .ioc; сам submodule + `RadioEvents_t`-реєстрація обабіч уже ✅ — Шлях A 2026-07-04, §12.5; латентний `Radio.Init(NULL)` Queen-RX баг закрито тоді ж) + startup/ld → link → `check_ram_budget.sh` дає істинний повний [`00_07` — FW.26](00_07_Action_Plan_Tracker) розмір.

### 12.5 Vendor / dependency pin-policy (FW.47)

**Дім pin-політики зовнішніх залежностей.** FW.46 завендорив CMSIS-DSP/CMSIS_6/mruby/monocypher + (2026-06-11) `stm32wlxx-hal-driver` v1.6.0 / `cmsis-device-wl` v1.4.0 як pinned submodules (§12.4); FW.47 — аудит решти vendor-поверхні + єдина політика, щоб «assumed / вставлене вручну» не протікало в білд.

**Конвенція:** кожна firmware-native залежність → **pinned git-submodule `firmware/extern/<dep>` на release-tag** (як §12.4). CubeMX-glue (`*_hal_msp.c`, `main.h`/`radio.h`-config) лишається owned in-repo — submodule тягне лише upstream-драйвери.

| Залежність | Роль | Статус | Pin-план |
|---|---|---|---|
| CMSIS-DSP · CMSIS_6 · mruby | logmel FFT · Core · bio-contract VM | ✅ завендорено (§12.4) | submodule@tag |
| Monocypher | [L1 QATT] software-Ed25519 — підпис CoAP-батчів Queen ([`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)) · [FW.23] перевірка печатки OTA на Солдаті (`common/ota_seal.h`, [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning); з 2026-10-06) | ✅ завендорено (2026-06-07) | `extern/monocypher`@4.0.3 (+ optional `monocypher-ed25519` — стандартний SHA-512 EdDSA, parity з ruby `ed25519` gem host-tested) |
| OpenSSL | host-тест crypto (AES/HKDF/HMAC) | system host-dep; НЕ target | host-build, не вендориться |
| ~~mbedTLS~~ | target HMAC-SHA256 | ✅ **не потрібен** — FW.30 cold-start seed-HMAC закрито pure-C `silken_sha256.h` (byte-parity vs OpenSSL, KAT FIPS/RFC 4231); печатка OTA (FW.23) з 2026-10-06 — Ed25519 через Monocypher ↑, тож HMAC їй більше не потрібен | own-code `firmware/common/silken_sha256.h` |
| STM32 HAL + CMSIS-Device-WL | HAL · SUBGHZ/SX1262-периферія · CRYP | ✅ завендорено (2026-06-11, §12.4 — CI компілює обидва `main.c` під `-DSILKEN_WITH_HAL=ON`); host = `hal_mock.h` | `extern/stm32wlxx-hal-driver`@v1.6.0 + `extern/cmsis-device-wl`@v1.4.0 — пара ОДНОГО релізу STM32CubeWL, бампається лише разом (перевірка — скіл `dependency-update`, рядок firmware C) |
| **SubGHz_Phy (Radio_s middleware)** | `Radio.Init/Rx/Send` + `RadioEvents_t` (radio.c/radio_driver.c/radio_fw.c) — те, що кличуть обидва `main.c` | ✅ завендорено (2026-07-04, Шлях A: `RadioEvents_t` зареєстровано в обох `main.c`, owned-stub видалено; `radio.c` не компілюється до `radio_conf.h` з .ioc). Шлях B — переписати `main.c` на прямий `HAL_SUBGHZ_*` — відкинуто: він викинув би errata-обходи STM32WL, які живуть у `radio.c` і `radio_driver.c` (Inverted IQ, 500 кГц, implicit-header timeout, RFO-HP mismatch), а не в `radio_fw.c` | `extern/subghz-phy`@v1.5.0 (`stm32-mw-subghz-phy`, BSD-3-Clause ST + Clear BSD Semtech; SHA `7dc059f3` = трійка з HAL v1.6.0+CMSIS v1.4.0). Click-through **SLA0044** пакета STM32CubeWL покриває KMS · Secure Engine · Sigfox і `Projects/` (BSD-3 там лише basic Examples), а НЕ SubGHz_Phy/LoRaWAN — джерело: `LICENSE.md` STM32CubeWL; ⚠️ тож `radio_conf.h` для board-freeze роби з `Conf/radio_conf_template.h` цього submodule, а не копією з `Projects/` |
| **LoRaMac-node (LoRaWAN MAC)** | ARCH.34 Helium SOS: OTAA + DevNonce + EU868 — те, що кличе adapter `Helium_Mac_SendSos` (owned-обв'язка ✅ у `queen/main.c`+`helium_sos.h`) |  ✅ завендорено 2026-07-05, форк-пін (⚠️ `subghz-phy/lorawan/` то LBM radio-шар SWL2001, НЕ MAC — окремий submodule). ⚠️ Upstream-статус: Semtech перевів LoRaMac-node у **maintenance mode** (critical-fixes-only; нові фічі → LBM) — для SOS-профілю Class-A/1.0.4 прийнятно: замерзлий стабільний стек, наш UB-фікс = critical-клас (PR [#1648](https://github.com/Lora-net/LoRaMac-node/pull/1648)); LBM-міграція = лише якщо ARCH.34 виросте за SOS (міст уже vendored — subghz-phy/lorawan/) | `extern/stm32-mw-lorawan` @ **наш форк `Alexey-Lukin/...` tag `v2.6.2-silken.1`** (= upstream v2.6.2 + SF11/12 UB-фікс; тег = SSOT-пін, SHA не цитуємо — дрейфить; BSD-3; той самий Radio_s API; `Conf/*_template.h` → owned-glue) |
| CMSIS-NN | TinyML `Run_Inference` (опц. ARM-прискорення) | ✅ baseline = pure-C forward pass (FW.4, нуль нового vendoring); з HW.30 модель — актив без call-site на Солдаті, тож і прискорювачу нема споживача | `extern/CMSIS-NN`@tag — ЛИШЕ якщо більша модель захоче ARM-kernels ([`00_07` — FW.4](00_07_Action_Plan_Tracker)) |

> **SX1262 — два шари, не плутати:** низькорівнева HAL SUBGHZ-периферія (`HAL_SUBGHZ_*`, `SUBGHZ_HandleTypeDef`) живе у HAL-submodule ✅; але `Radio_s` API (`Radio.Init/Rx/Send`), який реально кличуть `main.c`, — це окремий **SubGHz_Phy middleware** (`radio.c` кличе `HAL_SUBGHZ_*` під собою): НЕ частина HAL-піна, а окрема залежність — власний submodule `extern/subghz-phy` (↑ таблиця). Chip-драйвер `sx126x.c` у дереві Є, але лише всередині LBM-шару `extern/subghz-phy/lorawan/radio_drivers/sx126x_driver/` (SWL2001, адаптований під WL5 HAL — не наш `Radio_s`-шлях; ⚠️ «не існує», що тут стояло до 2026-09-30, було буквально хибним, висновок про шлях — ні): наш шлях іде через `radio_driver/`. Вендоринг = Шлях A (↑ таблиця).

**Toolchain (окрема вісь):** ARM GCC + newlib у CI = apt (unpinned); bytecode-детермінізм рідить на pinned mruby submodule, не на toolchain. Pin через ARM-tarball (як локально) — far-future build-attestation ([`00_07` — FW.46](00_07_Action_Plan_Tracker)).

**Contracts (Solidity):** OZ + forge-std → npm + committed `package-lock.json`; CI = `npm ci` (пінить точно, не SemVer-range) → відтворювано. Лишаємо npm — міграція на `forge install`-submodules нічого не дає для reproducibility (FW.47-рішення). Backend/frontend — bundler (`Gemfile.lock`) + importmap, lockfile-managed.

**Python scientific envs (conda):** `tools/in_silico` (`silken_md`: OpenMM/RDKit/OpenFF/PySCF) і `tools/ml` (`silken_ml`: librosa/scikit-learn). `environment.yml` — human-editable джерело, але `>=`-діапазони → fresh-solve бере найновіший сумісний білд → числа TRL-доказового пайплайну можуть тихо зсунутися між прогонами. **`in_silico` запінено** committed `conda-lock.yml` (точні версії+хеші, `linux-64`+`osx-arm64`); CI ставить env з lock, окремий job `lock_sync` гейтить lock↔`environment.yml` (`conda-lock --check-input-hash`). **`ml` свідомо НЕ пінимо** — його gate само-перевірний (librosa ≡ stdlib parity 1e-6 + `emit_c --check`), version-drift ловиться парністю → lock дав би менше за вартість підтримки. Регенерація — `tools/in_silico/README.md`.

### 12.6 Static-analysis gate — cppcheck (the "ruff/rubocop for C")

**Дім cppcheck-гейту owned firmware C** (`soldier` + `queen` + `common` + `sim` — FW.55 bare-metal-нога, §12.7; vendored `extern/` + `.toolchain/` виключені). Аналог `lint` (RuboCop) / `python_lint` (ruff) — job `firmware_lint` у `.github/workflows/ci.yml`. cppcheck парсить джерела напряму (без крос-компіляції/HAL-хедерів) → ловить null-deref, buffer-overrun, uninit-read, знакові/цілочисельні сюрпризи й мертві умови ще до bench.

**Єдиний вхід (DRY):** `firmware/scripts/cppcheck.sh` — той самий скрипт ганяють CI і розробник локально (`--deep` = `+ --inconclusive`; `--misra` = MISRA C:2012 advisory, non-gating, лише де є `misra.py`-addon — apt-build, не conda-forge).

**Конфіг:**
- **Кастомна Cortex-M4 платформа** `firmware/.cppcheck/stm32wle5.xml`: `char` **unsigned** (Arm EABI; `unix32` хибно дав би signed) → знак-залежні перевірки коректні; ILP32-розміри (long/pointer/wchar_t = 4).
- **Gating-набір** `warning,performance,portability,style` на `--check-level=exhaustive`. cppcheck пінить ubuntu-24.04 (apt); локально — `conda create -n silken_lint -c conda-forge cppcheck`.

**Suppressions — задокументовані false-positives нашої архітектури, не сховані баги:**
- **Project-wide** (у runner): `missingInclude`/`missingIncludeSystem` (HAL/CMSIS/mruby-хедери лише в ARM-контексті); `staticFunction` (firmware = один TU `main.c`, host-тести компілюють **витягнуту** логіку → linkage-поради = шум; справжні мертві функції ловить рев'ю + ARM `-Wunused`).
- **Inline** `// cppcheck-suppress` з причиною на місці: radio `OnRxDone` (= Semtech `RadioEvents_t.RxDone`, ABI-фіксована сигнатура) і HAL weak-symbol callback'и (`HAL_UART_RxCpltCallback` Королеви: `const`/перейменування зламали б перекриття слабкого символа).

**Scope:** `firmware/test/` **свідомо виключено** (host-scaffolding — знахідки = const-шум на тест-локалах + навмисні boundary/clamp/overflow-патерни, 0 реальних багів, дослідження 2026-06-07). MISRA C:2012 доступна як advisory (`--misra`, apt `misra.py`-addon, non-gating); ескалація до gating — optional far-future. Контекст — [`00_07` — FW.48](00_07_Action_Plan_Tracker).

### 12.7 QEMU-M4 bit-parity lane — ISA-емуляція замість bench (FW.55)

**Що це:** committed-байткод `lorenz_bytecode.h` виконується реальним **Cortex-M4 код-шляхом** (minimal-gembox `libmruby.a` із `SILKEN_ARM_BUILD`, software-double `__aeabi_d*` — той самий машинний код, що піде на STM32WLE5 — вузловий `CC` і стендовий `JC` мають одне ядро) на `qemu-system-arm -M mps2-an386`, і дамп порівнюється **byte-exact** із host-голденом. Закриває FW.7/FW.19 residual «ARM↔x86 Float drift» до тонкого silicon-confirm (один прогін selftest на платі).

**Чому бітова рівність — правильний гейт:** Lorenz = лише `+−×÷` (correctly-rounded за IEEE 754), VM виконує той самий байткод у тому ж порядку, double на M4 (WLE5 без FPU — ABI-інваріант §12.4) — детермінований software-шлях `__aeabi_d*`. Розбіжність = справжня знахідка, не шум. Кейси **зчеплені** (вихід N → вхід N+1, RTC-continuation патерн) — одиничний ULP-дрейф ампліфікується хаосом і не сховається.

**Анатомія (One-Home):**
- `firmware/sim/parity_core.h` — спільний runner (host і ARM компілюють той самий код); краєві піни (temp/acoustic/delta_t/vcap) + LCG-розгортка.
- `firmware/sim/host_main.c` — host-голден; `firmware/sim/qemu_m4/{main,startup,syscalls}.c` + `mps2_an386.ld` — bare-metal нога (CMSDK UART0 → stdout, semihosting-вихід; карта пам'яті СИМУЛЯТОРА, не Солдата).
- `firmware/sim/wle5_bench/{main,startup,syscalls}.c` + `stm32wle5.ld` — **кремнієва нога** (silicon-confirm, RUNBOOK 2.3): той самий `parity_core.h` + той самий `libmruby.a` на РЕАЛЬНІЙ карті WLE5 (FLASH 256K @ 0x0800_0000 / SRAM 64K, .data копіюється startup'ом; LPUART1 PA2 AF8 → ST-LINK VCP, голий RM0461 без HAL — дамп не чекає CubeMX-vendoring). Раунди стрімляться нескінченно (`PARITY-BEGIN`→кейси→`PARITY-COMPLETE`→фіт-звіт) — знімач дампу не грає в «хто перший: reset чи порт».
- `firmware/sim/stack_paint.h` — спільний paint/scan стек-вотермарки всіх ARM-ніг.
- `firmware/scripts/qemu_parity.sh` — єдиний вхід (DRY, патерн `cppcheck.sh`): локально без qemu → host+ARM+wle5-build і чесний skip; CI з `REQUIRE_QEMU=1` — відсутній qemu = fail.
- `firmware/scripts/bench/05_parity_dump.py` — bench-день: дамп із плати по VCP ↔ host-голден, вердикт byte-exact (`--plan` дає кроки).
- CI: крок `[FW.55]` у job `firmware_arm_build` (`ci.yml`) — реюзає вже зібрані mruby-ліби.

**Фіт-гейт 64КБ (pre-flight кремнієвої ноги):** QEMU-mruby-нога друкує heap/stack high-water прогону (`PARITY-HEAP`/`PARITY-STACK`) + розклад фаз (`PARITY-MEM` open/irep/cases, чисті mruby-запити через лічильний allocf) + сирий SBRK-трас, а `qemu_parity.sh` гейтить high-water проти бюджету wle5-карти — 64КБ мінус static RAM реального `parity_wle5.elf` мінус стек-резерв (One-Home числа резерву — `stm32wle5.ld`). Ноги лінкують **newlib-nano** (CubeMX-дефолт майбутнього Солдата — повний newlib-dlmalloc давав +24КБ нерепрезентативного sbrk-роздуву). Числа переносяться на кремній чесно: той самий `libmruby.a`/libc ⇒ ідентична послідовність malloc'ів. «mruby-прогін не влазить у Солдата» — знахідка CI, не bench-дня: перший же тиждень гейта зловив **чотири** девайс-знахідки (арена-дисципліна, MCU-профіль, nano-libc, WORD_BOXING-дефолт 4.0 — хронологія в [`00_07` — FW.55](00_07_Action_Plan_Tracker)).

**Друга нога — log-mel DSP ([FW.4], 2026-06-10):** та сама машина, той самий
метод, інший вантаж: `Compute_LogMel` (`silken_common`, `LOGMEL_USE_CMSIS` —
справжній `arm_rfft_fast_f32` код-шлях, soft-float ABI WLE5) ганяє golden-вектори
спільним ядром `firmware/sim/logmel_parity_core.h` (One-Home з host-ctest
`test_logmel_cmsis`). Гейт тут — **толеранс проти double-оракула** (1e-3, не
byte-exact: float32 ≠ binary64) + **stack high-water**: вікно під SP фарбується,
після чистих викликів (вхід/вихід static) сканується;
перевищення бюджету-tripwire = fail. Вхід — `firmware/scripts/qemu_logmel.sh`
(локально без qemu → cross-build і чесний skip; CI `REQUIRE_QEMU=1`, крок
`[FW.4]` у `firmware_arm_build` — реюзає `firmware/build` з кроку FW.46).
Latency QEMU **не** міряє (не цикло-точний) — то клас C.

**Межі чесності:** QEMU виконує ISA, а не кремній — він **не** відповідає за периферію (RTC/AES/SUBGHZ), споживання чи таймінги. Це шар B класифікації симуляції ([`00_03 §3`](00_03_TRL_Matrix_HIL_and_Beyond)); кремнієвий клас C живе у bench-runbook. Статус — [`00_07` — FW.55](00_07_Action_Plan_Tracker).

---

## 📈 13. EMA (Exponential Moving Average) на Soldier — FW.21 🤖

> **Cross-ref:** [`00_07` — FW.21](00_07_Action_Plan_Tracker) — ✅ реалізовано (`firmware/soldier/main.c` + тести у `firmware/test/test_soldier_logic.c`)

### 13.1 Мета та контекст

**Проблема:** Сигнали `delta_t` та `vcap` мають значний шум при вимірюванні:
- `delta_t` (час заряду EDLC): ±8% через RTC jitter, кварцевий drift та нерегулярні прокидання
- `vcap` (Vcap в мВ): ±2–5% через 12-bit ADC noise (особливо при низьких напругах <500 мВ)

Без фільтрації ці шуми безпосередньо впливають на Lorenz Attractor variance (після реалізації FW.5 Варіант B+) → нестабільні growth_points між близькими за станом TX-циклами.

**Рішення:** Lightweight EMA (Exponential Moving Average) — **O(1) пам'ять, O(1) обчислення**, ідеально для STM32 embedded.

### 13.2 Математика EMA

```
EMA_t = α × x_t + (1−α) × EMA_{t-1}

Де:
  x_t     = поточне вимірювання (delta_t або vcap)
  EMA_{t-1} = попереднє значення EMA (зберігається між wakeup циклами)
  α       = 0.2 (smoothing factor — 0.1=сильне згладжування, 0.5=менше)
```

**Ефективна "пам'ять" EMA:** `N_eff = 2/α − 1 = 2/0.2 − 1 = 9` точок. Тобто EMA "пам'ятає" останні ~9 TX-циклів (при 1 пакеті/год ≈ 9 годин).

**Шумова характеристика:** при α=0.2 та вхідному noise σ_x:
- σ_EMA = σ_x × √(α / (2−α)) = σ_x × √(0.2/1.8) ≈ **0.33 × σ_x** (зменшення шуму в 3×)
- Для delta_t: ±8% → ±2.7%; для vcap: ±5% → ±1.7%

### 13.3 Persistence — RTC Backup Registers DR10 + DR12 (packed)

> **🔄 Дизайн уточнено під час імплементації (FW.21 fallback):** STM32WLE5 має лише 20 RTC backup регістрів (DR0..DR19). Оригінальна специфікація (DR24-DR26) фізично неможлива. Перша ітерація FW.21 звільнила 6 регістрів через `MESH_DID_CACHE_SIZE` 8→2 (DR8..DR9 mesh, DR10..DR12 EMA). Подальший аналіз показав: `ema_vcap_x10` має фізичний максимум **5500 × 10 = 55 000 ≤ 2¹⁶** і вкладається в **16 біт**, тому ми пакуємо його в low 16 біт DR12, звільняючи DR11 під 3-й mesh-слот. Поточна розкладка:
>
> | DR | Власник |
> |----|---------|
> | DR8, DR9, **DR11** | `recent_mesh_dids[3]` (3 слоти, fallback від 8→3) |
> | DR10 | `ema_delta_t_x100` (full uint32) |
> | **DR12** | `[valid:8 \| count:8 \| ema_vcap_x10:16]` (packed) |
>
> (DR15..DR19 пізніше зайнято FW.2 Frame Counter / Lorenz-станом — канонічна розкладка §2; вільні DR7 — FW.54 — і DR13/DR14, що тримали TinyML-пороги до HW.30.)

**Trade-off ping-pong (8 → 3 слоти, FW.21 fallback):**
- 2 слотів достатньо для immediate echo A→B→A; **3 слоти додатково покривають короткі кільця A→B→C→A** (B та C ще в кеші коли пакет повертається).
- Глибші ring-и (4+ унікальних реле) захищаються через TTL (DEFAULT_TTL=3, PANIC_TTL=5).
- При 100 деревах у кластері частота 4-relay колізій вкрай низька (TTL=3 уже обмежує глибину); ризик прийнятний.

**Розкладка DR10 + DR12:**
| RTC Reg | Поле | Тип | Призначення |
|---------|------|-----|-------------|
| DR10 | `ema_delta_t_x100` | uint32 | EMA delta_t × 100 (fixed-point 0.01 с, full 32 bits) |
| DR12 [31:24] | `ema_valid` | uint8 | Magic `0x45` ('E') — маркер ініціалізованого фільтра |
| DR12 [23:16] | `ema_count` | uint8 | Saturating counter @ 255 (warmup після ≥ `EMA_WARMUP_CYCLES`) |
| DR12 [15:0] | `ema_vcap_x10` | uint16 | EMA vcap × 10 (fixed-point 0.1 мВ; max 55000 ≤ 2¹⁶) |

**Cross-VBAT поведінка:** при втраті живлення RTC backup domain очищається → `ema_valid != 0x45` на boot → cold-start → 3 цикли warmup перед `EMA_Is_Warmed_Up()`. Споживач ([E.63] метаболізм: `delta_t`→`growth_points`) у ці 3 цикли дістає **дві РІЗНІ відповіді на дві різні відсутності**: `delta_t` = `DELTA_T_UNKNOWN_S` (сентинел `0` → GP=0), `vcap` = nominal 3300 мВ. Після прогріву — з EMA: **передавання у mruby `calculate_state()` wired** (FW.49-S1: `delta_t_for_lorenz = EMA_Get_DeltaT_Sec()` при `EMA_Is_Warmed_Up()`). 🔴 **Асиметрія навмисна й несуча:** метаболізм не виміряно взагалі, тож будь-яке число тут = вигаданий GP (`BASELINE_DELTA_T_S` давав рівно `GP_HOMEO_MAX` — максимум балів за відмову міряти, [ARCH.102](00_07_Action_Plan_Tracker)); шину живлення натомість стабілізує BQ25570, тож 3300 — не здогад, а специфікація. silicon-residual: `Wall_Seconds_Now()`=0 до LSE bring-up тримає delta_t на сентинелі кожен цикл (FW.49 bench). `SilkenNet::Attractor` backend-mirror вже E.63-compliant (β фіксований, метаболізм → `growth_points`).

### 13.4 Firmware — реалізація

```c
// firmware/soldier/main.c — секція 1.10 (стиль матчить FW.6 Lorenz state)

#define EMA_ALPHA_NUM     2       // α = 2/10 = 0.2
#define EMA_ALPHA_DEN     10
#define EMA_VALID_MAGIC   0x45    // 'E' — маркер ініціалізованого фільтра
#define EMA_WARMUP_CYCLES 3

uint32_t ema_delta_t_x100 = 0;
uint32_t ema_vcap_x10     = 0;
uint8_t  ema_valid        = 0;
uint8_t  ema_count        = 0;

static void EMA_Update(uint32_t raw_dt_sec, uint16_t raw_vcap_mv) {
    uint32_t raw_dt_x100  = raw_dt_sec * 100u;
    uint32_t raw_vcap_x10 = (uint32_t)raw_vcap_mv * 10u;

    if (ema_valid != EMA_VALID_MAGIC || ema_count == 0) {
        ema_delta_t_x100 = raw_dt_x100;
        ema_vcap_x10     = raw_vcap_x10;
        ema_valid        = EMA_VALID_MAGIC;
        ema_count        = 1;
        return;
    }

    ema_delta_t_x100 = (EMA_ALPHA_NUM * raw_dt_x100 +
                        (EMA_ALPHA_DEN - EMA_ALPHA_NUM) * ema_delta_t_x100) / EMA_ALPHA_DEN;
    ema_vcap_x10     = (EMA_ALPHA_NUM * raw_vcap_x10 +
                        (EMA_ALPHA_DEN - EMA_ALPHA_NUM) * ema_vcap_x10) / EMA_ALPHA_DEN;
    if (ema_count < 255) ema_count++;
}

static inline uint32_t EMA_Get_DeltaT_Sec(void) { return ema_delta_t_x100 / 100u; }
static inline uint16_t EMA_Get_Vcap_Mv  (void) { return (uint16_t)(ema_vcap_x10 / 10u); }
static inline uint8_t  EMA_Is_Warmed_Up(void) {
    return (ema_valid == EMA_VALID_MAGIC) && (ema_count >= EMA_WARMUP_CYCLES);
}
```

**BOOT — відновлення EMA з RTC** (одразу після відновлення Lorenz state):

```c
// [FW.21] ВІДНОВЛЕННЯ EMA-ФІЛЬТРА (RTC DR10 + DR12 packed)
// УВАГА: DR11 НЕ ЧЕПАЄМО — це recent_mesh_dids[2]. ema_vcap_x10 живе у low 16 біт DR12.
#define EMA_VCAP_X10_MASK 0xFFFFu
{
    uint32_t ema_meta = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR12);
    uint8_t  v        = (uint8_t)((ema_meta >> 24) & 0xFFu);
    if (v == EMA_VALID_MAGIC) {
        ema_delta_t_x100 = HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR10);
        ema_vcap_x10     = (uint32_t)(ema_meta & EMA_VCAP_X10_MASK); // НЕ DR11!
        ema_valid        = v;
        ema_count        = (uint8_t)((ema_meta >> 16) & 0xFFu);
    }
}
```

**SAVE — збереження EMA перед STOP2** (одразу після збереження mesh DIDs):

```c
// УВАГА: DR11 належить recent_mesh_dids[2] (§2 canonical SSOT). НЕ перезаписуємо.
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR10, ema_delta_t_x100);
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR12,
      ((uint32_t)ema_valid  << 24)
    | ((uint32_t)ema_count  << 16)
    | (ema_vcap_x10 & EMA_VCAP_X10_MASK));
```

**Інтеграція в Phase 1 (SENSE)** — викликається після зчитування `vcap_voltage`:

```c
HAL_ADC_Stop(&hadc);

// [FW.21] Оновлюємо фільтр пульсу. Стан живе в RTC DR10-12, зчитано в Phase 0 (BOOT).
EMA_Update(delta_t_seconds, vcap_voltage);
```

> Згладжені значення їдуть у mruby: прогрітий фільтр (`EMA_Is_Warmed_Up()`) віддає `EMA_Get_DeltaT_Sec()` у `calculate_state` замість сирого `delta_t` (§13.3; E.63 — вхід GP).

### 13.5 RAM Footprint

| Компонент | RAM | Коментар |
|-----------|-----|---------|
| 4 globals (`ema_*`) | **10 байтів** SRAM (2 × uint32 + 2 × uint8) | Статичні, BSS-розміщення |
| 3 RTC регістри (DR10-12) | 12 байтів у RTC backup domain (≠ SRAM) | Survives STOP2 + VBAT (поки RTC живиться) |
| Локальні в `EMA_Update` | ~16 байтів стек | Звільняються після виклику |
| CPU code | ~250 байтів Flash | 4 функції + load/save inline |
| **Net SRAM impact** | **10 байтів** | 0.015% від 64KB SRAM |

### 13.6 Вплив на Backend

**TelemetryLog:** поле `metabolism_s` (`delta_t`) в payload залишається **raw** значенням (не EMA). EMA — тільки для внутрішнього використання firmware (Lorenz input). Це дозволяє backend:
- Бачити реальний raw `delta_t` для діагностики
- Самостійно рахувати EMA server-side якщо потрібно (через TimescaleDB continuous aggregates, E.37)

**Dual Computation Integrity (метаболічний канал):** [E.63] FW.5 B+ β-пертурбацію **реверсовано** — raw `delta_t` більше не входить у Z. Wire несе **raw** `delta_t` (діагностика + server-side EMA), а `growth_points` пакуються з **EMA-згладженого**. **✅ Розрив закрито wire-rev2.1 (30B CCM, founder 2026-07-03, E.63 гейт (г)):** wire ДОДАТКОВО несе `ema_delta_t_s` (bytes 20..21) за контрактом **«wire = вхід GP»** — Soldier сатурує EMA до wire-u16 ПЕРЕД викликом mruby (Фаза 3, до гілкування — VM_ERROR-кадр теж несе чесне поточне значення) і пакує ТЕ САМЕ число → backend `Attractor.expected_homeostasis_gp(ema)` перераховує GP **stateless байт-точно**. Гілка у `check_metabolic_divergence!` — **observational** (warn+метрика) до bench-калібрування порогів; структурний band-check лишається для ECB-шляху (ema відсутній). Wire-дім + ухвала — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security); трекер — [`00_07` — E.63](00_07_Action_Plan_Tracker).

### 13.7 Тести (`firmware/test/test_soldier_logic.c` — секція FW.21)

10 host-based тестів (компілюються x86 gcc, без ARM toolchain):

| # | Тест | Перевірка |
|---|------|----------|
| 1 | `test_ema_cold_start` | Перший виклик: EMA = raw value, valid=MAGIC, count=1, не warmed up |
| 2 | `test_ema_second_cycle_smoothing` | Точна формула α=0.2: 3600→4000 дає EMA=3680, 4500→5000 дає 4600 |
| 3 | `test_ema_convergence` | Після 20 ітерацій з константним input EMA в межах ±1% від input |
| 4 | `test_ema_noise_rejection` | Spike 5× → EMA рухається лише ~1.8× від baseline (3× rejection) |
| 5 | `test_ema_warmup_flag` | count<3 → false; count=3 → true |
| 6 | `test_ema_count_saturates_at_255` | 300 ітерацій → count=255 (no wraparound) |
| 7 | `test_ema_zero_inputs_are_valid` | delta_t=0, vcap=0 не викликає overflow / NaN |
| 8 | `test_ema_no_overflow_at_max_inputs` | delta_t=86400s (24h), vcap=5500mV — fixed-point не переповнюється |
| 9 | `test_ema_rtc_save_load_roundtrip` | Save до DR10-12 → wipe RAM → load назад → значення збігаються |
| 10 | `test_ema_rtc_first_boot_no_magic` | Порожній RTC → load повертає cold state, не warmed up |

**Результат:** ✅ 102 passed (10 EMA tests + оновлений mesh-test набір під 3 слоти: `test_mesh_3_slots_all_known`, `test_mesh_4th_evicts_oldest`, `test_mesh_pingpong_scenario`).
