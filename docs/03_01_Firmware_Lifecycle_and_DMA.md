# 03_01: Життєвий Цикл Прошивки та DMA (Фази 0–5, Watchdog, STOP2)

## 🎯 Мета

Зафіксувати детермінований життєвий цикл (Main Loop) вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор), переходи між станами сну та апаратні переривання (ISR) мікроконтролера STM32WLE5JC. Документ слугує SSOT для Factory Flashing (масового виробництва) та OTA-розгортання.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — увесь C-код Soldier+Queen реалізований, host-based тести зелені (`make -C firmware/test`). Відкриті обмеження (чому не вище): async UART DMA flush (`FW.3` AT-blind), key-rotation (`FW.17`), RDP-2 (`SEC.2`) — реєстр у [`00_07 §03`](00_07_Action_Plan_Tracker)

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| `firmware/soldier/main.c` · `firmware/queen/main.c` · `firmware/bio_contracts/bio_contract.rb` | Джерела: C-код Soldier/Queen + mruby bio-contract |
| `firmware/test/` | Host-based x86 тести (`make -C firmware/test`) |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Queen: LoRa RX, CIFO, SIM7070G modem |
| [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) | TinyML класифікатор звуку |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | Математика Атрактора Лоренца |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Шифрування, ключі, RDP |
| [`02_04` — EDLC Supercapacitor Buffer](02_04_EDLC_Supercapacitor_Buffer) | EBFC та іоністор 0.47F |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери модуля 03** (SSOT): `FW.3` AT-blind, `FW.17` key-rotation, `SEC.2` RDP-2, `SEC.3` factory |

---

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Інструментарій Розробки](#-інструментарій-розробки)
- [1. Soldier — Архітектура Вузла-Датчика](#-1-soldier--архітектура-вузла-датчика)
- [2. Soldier RTC Backup Register Map (DR0..DR19) — Canonical SSOT](#-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3)
- [3. Soldier RAM Budget (~5 KB з 64 KB SRAM)](#-3-soldier-ram-budget-5-kb-з-64-kb-sram)
- [4. Queen — Архітектура Шлюзу-Агрегатора](#-4-queen--архітектура-шлюзу-агрегатора)
- [5. Queen RAM Budget](#-5-queen-ram-budget)
- [6. ISR Map (Апаратні Рефлекси)](#-6-isr-map-апаратні-рефлекси)
- [7. DID Generation (Народження)](#-7-did-generation-народження)
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
| **Призначення** | Повноцінна C/C++ IDE для STM32WLE5JC (ARM Cortex-M4 + SX1262 LoRa) |
| **Включає** | STM32CubeMX — графічний конфігуратор GPIO, тактових дерев, периферії |
| **Порт** | Налаштування GPIO pinout (PA9/PA10 UART, ADC, TIM2 DMA, RNG, CRYP) до отримання плат |
| **Clock Tree** | Конфігурація HSE/LSE для STOP2 ultra-low-power режиму (цільове: 300 nA RTC-only — [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power); на TRL 6 baseline: 1.07 µA з SRAM2 retention) |
| **HAL drivers** | Auto-генерація ініціалізаційного коду для I2C/SPI/ADC/UART/RTC/CRYP |
| **Debugger** | Інтеграція з ST-LINK-V3MINIE: breakpoints, live variable watch, SWO trace |
| **Збірка** | GCC ARM Embedded toolchain (вбудований у CubeIDE); той самий компілятор що й для host-тестів |

**Що можна зробити до отримання фізичних плат:**
1. Налаштувати повний Pinout у STM32CubeMX для обох прошивок (Soldier та Queen)
2. Сконфігурувати Clock Tree для STOP2 (MSI 100 kHz active clock, LSE 32.768 kHz для RTC)
3. Підготувати HAL-ініціалізацію для всіх периферій (ADC, TIM2 DMA, IWDG, RNG, CRYP, SUBGHZ)
4. Запустити host-based тести (make -C firmware/test) без будь-якого ARM toolchain
5. Запустити Wokwi-симуляцію для логіки сенсорів та пакетного формату

### Конфігурація Pinout STM32CubeMX (6 Каналів Сенсора + SWD)

#### Канальна Карта (Channel Map)

| # | Назва Каналу | Периферія CubeMX | Шлях у CubeMX | Налаштування |
|---|---|---|---|---|
| SWD | Програматор (Оптичний Нерв) | SYS | `System Core → SYS → Debug` | **Serial Wire** (PA13=SWDIO, PA14=SWCLK → зелені) |
| 1 | Delta T (Алгоритм Часу) | RTC | `Timers → RTC` | **Activate Clock Source** + **WakeUp** (STOP2 wake) |
| 2 | Температура Кристала | ADC | `Analog → ADC` | **Temperature Sensor Channel** ✓ |
| 3 | Голос Дерева / П'єзодиск | GPIO_EXTI | Клік на пін **PA0** → | **GPIO_EXTI0** (зовнішнє переривання) |
| 4 | Глибина Резервуара (Vcap) | ADC | `Analog → ADC` | **Vrefint Channel** ✓ (одночасно з каналом 2; ⚠️ FW.50: міряє VDDA, не Vcap — потрібен окремий канал+дільник, §1.4) |
| 5 | RSSI Біомаса / Фенологія | — | *Без конфігурації на вузлі* | Zero-Energy: вимірюється Queen на стороні Gateway |
| 6 | Квантовий Шум (TRNG seed) | RNG | `Security → RNG` або `Computing → RNG` | **Activated** ✓ |

> **Канал 5 (RSSI):** 868 МГц LoRa-хвилі поглинаються водою в листі. Взимку RSSI ≈ -80 dBm; навесні при розпусканні листя RSSI падає до ≈ -105 dBm. Зміна RSSI між виміряннями дозволяє Queen відстежувати фенологічний стан (листяний покрив) без жодного додаткового датчика на Soldier. Значення RSSI автоматично фіксується SX1262 при кожному RX-пакеті.

#### Покрокова Конфігурація у STM32CubeIDE

**Крок 1: Створення проєкту**
1. `File → New → STM32 Project`
2. Part Number: `STM32WLE5JC` → вибрати чип → Next
3. Назва: `snet_core`, мова: **C**, тип: **STM32Cube** → Finish

**Крок 2: Pinout & Configuration**

```
SWD Debugger:  System Core → SYS → Debug = "Serial Wire"
               PA13 (SWDIO) та PA14 (SWCLK) стануть зеленими

ADC Канали:    Analog → ADC
               ☑ Temperature Sensor Channel  (Канал 2: внутр. температура)
               ☑ Vrefint Channel             (Канал 4: напруга іоністора)

RNG:           Security → RNG → ☑ Activated  (Канал 6: квантовий шум)

SUBGHZ (LoRa): Connectivity → SUBGHZ → ☑ Activated  (внутрішня шина LoRa SX1262)

RTC (Delta T): Timers → RTC
               ☑ Activate Clock Source
               ☑ WakeUp  (дозволяє STOP2 + RTC wake-up на мікроамперах)

PA0 (Piezo):   Клік на пін PA0 на схемі → GPIO_EXTI0  (Канал 3)
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
| **NRST** | **RST** | Апаратний скид після прошивки (опціонально) |
| **T_VCC** | **3V3** | Референсна напруга (ST-LINK не живить плату, лише "чує" рівень) |

> ⚠️ **T_VCC ≠ живлення:** ST-LINK через T_VCC тільки перевіряє рівень логіки. Плата LoRa-E5 живиться від BQ25570 VOUT (3.3V). Не підключати VCC від ST-LINK до 3V3 — конфлікт джерел живлення!

#### Канал 2: FT232RL (UART — Читання Логів та Serial Console)

> ⚠️ **КРИТИЧНО:** Перед підключенням переконатися, що перемичка (jumper) на FT232RL стоїть у позиції **3.3V** (не 5V). 5V миттєво пошкодить GPIO STM32WLE5JC.

| FT232RL пін | LoRa-E5 mini пін | Призначення |
|---|---|---|
| **RX** | **TX** | Мікроконтролер передає → адаптер отримує |
| **TX** | **RX** | Адаптер передає → мікроконтролер отримує |
| **VCC** | *не підключати* | Залишити порожнім — LoRa-E5 вже живиться від BQ25570 |

**Налаштування Serial Monitor (Mac/Linux):** baudrate = 115200, 8N1.

#### Фінальне Підключення до Mac

```
MacBook USB-A/C ──── ST-LINK-V3MINIE (Type-C) ──── SWD: CLK+DIO+RST+T_VCC → LoRa-E5
MacBook USB-A   ──── FT232RL                  ──── UART: TX→RX, RX→TX → LoRa-E5
```

Обидва USB-кабелі підключаються до Mac одночасно. STM32CubeIDE автоматично знаходить ST-LINK; для логів — `screen /dev/cu.usbserial-* 115200` або Serial Monitor у CubeIDE.

---

## 🌲 1. Soldier — Архітектура Вузла-Датчика

### 1.1 Апаратна Платформа

**MCU:** STM32WLE5JC (ARM Cortex-M4 @ 48 MHz + integrated SX1262 LoRa)

| HAL Handle | Периферія | Призначення |
|------------|-----------|-------------|
| `hadc` | ADC | Температура + напруга іоністора (Vcap) |
| `htim2` | TIM2 | Метроном DMA: 16 кГц тактування для аудіо-семплінгу |
| `hiwdg` | IWDG | Апаратний Watchdog (auto-reset при зависанні mruby/HardFault) |
| `hrng` | RNG/TRNG | Істинна випадковість (тепловий шум кристала) |
| `hrtc` | RTC | Real-time clock + Backup Domain (персистентний стан після STOP2) |
| `hsubghz` | SUBGHZ | Інтегрований LoRa трансивер SX1262 (868 МГц) |
| `hcryp` | AES | Апаратний AES (Hardware Crypto Engine). **LoRa-канал: AES-128-ECB** (post-ARCH.42 transitional → CCM target FW.2). Queen додатково динамічно re-init'ить на AES-256-CBC для CoAP-batch flush. |

**Примітка:** Soldier — єдиний вузол, що має ADC, TIM2, RNG та RTC. Queen — не має ADC, TIM2 та RTC (окрім RNG, AES та IWDG, доданого у PR #273).

### 1.2 Загальний Lifecycle

```
Народження (Power-On) → DID Generation → mruby VM Init → Infinite Loop:
┌─────────────────────────────────────────────────────────┐
│  Phase 0: IWDG Refresh (Watchdog)                       │
│  Phase 1: Sensor Acquisition (ADC × 2 cycles + HRNG)   │
│  Phase 1.5: TinyML Audio (only if vibration_detected)   │
│      TIM2 + ADC DMA → CPU SLEEP → DMA ConvCplt ISR     │
│  Phase 2: Bit-Pack (lora_payload[16])                   │
│  Phase 3: mruby Lorenz Attractor (bio-contract)         │
│  Phase 4: AES-128-ECB Encrypt → Radio.Send [ARCH.42]   │
│      [optional] Mesh Relay TX first                     │
│  Phase 4.5: RX Window (only if Vcap > 2800 mV)         │
│      Scenario A: OTA (0x99 marker) → Flash write        │
│      Scenario B: Mesh relay (16 bytes, TTL > 0)         │
│  Phase 5: Save to RTC Backup Domain → STOP2 (1.07 µA)  │
└─────────────────────────────────────────────────────────┘
       ↑ Wake on RTC Alarm або GPIO EXTI (piezo disk)
```

---

### 1.3 Phase 0: IWDG Watchdog Refresh

```c
HAL_IWDG_Refresh(&hiwdg);
```

Перша інструкція кожного циклу. Якщо mruby VM, DMA або будь-який інший блок зависне і цей рядок не виконається протягом IWDG timeout (налаштовується prescaler: типово ~26 секунд), MCU автоматично перезавантажиться. Усі критичні дані зберігаються в RTC Backup Domain.

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
uint32_t current_time = HAL_GetTick() / 1000;
delta_t_seconds = current_time - last_wakeup_timestamp;
last_wakeup_timestamp = current_time;
```

`delta_t_seconds` — час між пробудженнями в секундах. Відображає швидкість заряду EDLC суперконденсатора (іоністора). Чим швидше заряд → тим активніший фотосинтез → тим здоровіше дерево. Це є первинний біофізичний сигнал для Атрактора Лоренца.

> **🔴 tick ≠ wall-time у STOP2 — структурний дефект виміру.** `HAL_GetTick()` (SysTick) **заморожений** під час `HAL_PWREx_EnterSTOP2Mode` (`HAL_SuspendTick`+WFI). Тож `delta_t_seconds` тут міряє лише **active-час** циклу (~секунди обчислень), а НЕ wall-інтервал між пробудженнями, який і є фізичним часом заряду EDLC (L4-модель вище очікує 36–190 с). Цей дефект ділять усі tick-таймери Soldier (FW.27-B re-request, FW.20-S2 drift/cooldown/grace, beacon drift-comp). Канон-фікс і трекінг — [`00_07` — FW.49](00_07_Action_Plan_Tracker) (`Wall_Seconds_Now()` на RTC-календарі/LSE). Host-тести цього не ловлять — mock-tick монотонний. **Wake-source ВИРІШЕНО** — RTC WUT + Vcap-енергогейт (ADR §1.10, founder 2026-06-07); лишається лише bench bring-up (`MX_RTC_Init`/LSE clock-tree у repo відсутній).

> **In-silico L4 validation (2026-05-25):** Michaelis-Menten + Arrhenius модель підтверджує `BASELINE_DELTA_T_S=60` фізично обґрунтованим. Очікувані значення: здорове дерево (10 мМ глюкози, 25°C) → delta_t ≈ 36 с; стресоване (5 мМ, 5°C) → ≈ 190 с; Monte Carlo 90% CI для healthy: 14–120 с. Деталі → [`01_03 §3.4 L4`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell), [`in_silico/SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md).

**АЦП (два окремих цикли Start/Poll/Stop):**

```c
// Цикл 1: Температура (внутрішній датчик STM32)
HAL_ADC_Start(&hadc);
HAL_ADC_PollForConversion(&hadc, 10);
internal_temp = HAL_ADC_GetValue(&hadc);
HAL_ADC_Stop(&hadc);

// Цикл 2: сирий VREFINT-відлік (= опора VDDA, НЕ мВ Vcap — 🔴 FW.50 нижче)
HAL_ADC_Start(&hadc);
HAL_ADC_PollForConversion(&hadc, 10);
vcap_voltage = HAL_ADC_GetValue(&hadc);
HAL_ADC_Stop(&hadc);
```

> ⚠️ **Чому два окремих цикли?** STM32 ADC з подвійним каналом (температура + VREFINT) вимагає перемикання між каналами. Роздвоєний Start/Stop запобігає deadlock при прочитанні VREFINT одразу після температурного каналу.

> **🔴 `vcap_voltage` — сирий ADC-відлік, не мВ.** `HAL_ADC_GetValue()` повертає 12-bit count (0..4095), а код скрізь трактує його ЯК мілівольти: пакування байтів 4-5, пороги `VCAP_LISTEN_THRESHOLD=2800` / `COLD_TX_DEFER_VCAP_MV=4000` / `FAUNA_VCAP_MIN_MV=4500`, EMA, `vcap_mv` у mruby. На реальному залізі raw VREFINT ≈ 1500 → RX-вікно (>2800) не відкриється ніколи, а Vcap-енергогейт працює з фейкових величин. Додатково: VREFINT міряє **VDDA** (за buck-регулятором — майже константа), а НЕ напругу EDLC-іоністора; для Vcap потрібен окремий ADC-канал з дільником (цільовий тракт = BQ25570 VBAT_SEC, [`02_01 §7.1`](02_01_Hardware_Architecture_and_BOM)). Pure-helper `Adc_Raw_To_Mv()` з factory VREFINT-калібруванням ✅ реалізовано + host-тести (`firmware/common/adc_convert.h`, One-Home); жива розводка (окремий ADC-канал Vcap + резистивний дільник) лишається hardware-гейтом — трекінг [`00_07` — FW.50](00_07_Action_Plan_Tracker), номінали дільника узгодити з [`02_03`](02_03_BQ25570_MPPT_Nano_Power).

**HRNG (Chaos Seed):**
```c
HAL_RNG_GenerateRandomNumber(&hrng, &chaos_seed);
```

Апаратний генератор випадкових чисел на основі теплового шуму кристала. **[SEC.11 / FW.30]** `chaos_seed` більше НЕ використовується для Атрактора Лоренца — початковий стан `(x₀,y₀,z₀)` деривується з per-device K_seed (Flash `FLASH_SEED_ADDR`) через HKDF/HMAC. `chaos_seed` залишається для mesh anti-pingpong, TX jitter та CoAP nonce.

**BME280 (мікроклімат — HW.32, ADR [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM)):**
```c
// Гейтований TPS22860: GPIO ON → settle → forced-mode read → GPIO OFF (idle ~10 нА).
// Клімат змінюється повільно → опитування раз на N пробуджень (climate_due), не щоцикл.
if (climate_due) {
  HAL_GPIO_WritePin(BME_PWR_PORT, BME_PWR_PIN, GPIO_PIN_SET);   // power-gate ON
  bme280_forced_read(&bme_temp_c, &bme_rh_pct, &bme_pressure_hpa);  // ~10 мс @ ~700 µA
  HAL_GPIO_WritePin(BME_PWR_PORT, BME_PWR_PIN, GPIO_PIN_RESET);  // OFF
  vpd_index = compute_vpd_index(bme_temp_c, bme_rh_pct);  // VPD=f(t°,RH), on-node → 1 байт
}
```

> **VPD (Vapor Pressure Deficit)** обчислюється на вузлі з t°+RH і пакується **1 байтом** (Phase 2, байт 14) як **прямий confounder сокоруху** — backend використовує його, щоб не штрафувати за погоду (False-Slashing guard, [`05_05`](05_05_Slashing_and_Risk_Policy) §6/§7). Сирі RH/тиск (для NaaS клімат-оракула, [`07_01`](07_01_Nature_as_a_Service_Contracts)) — у періодичному **climate frame** (FW.2 24B CCM extended payload; транзитний 16B-кадр місця не має). Тригер climate frame: кожні N uplink'ів або значна Δтиску (раннє попередження про шторм). Енергія: за TPS22860-гейтом ≈8нА avg ([`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM), [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)). 🚨 **DCI-guard:** BME280-дані (VPD/RH/тиск) **НЕ** входять у входи Атрактора Лоренца (ті — temp/acoustic/delta_t/vcap, FW.5) → firmware↔backend bit-identity не зачіпається.

**RSSI (Канал 5 — Zero-Energy Фенологія):**

> RSSI не вимірюється Soldier напряму. Значення RSSI (`rssi_byte`) автоматично фіксується на стороні **Queen (Gateway)** при кожному прийнятому пакеті SX1262. Без жодного додаткового датчика на дереві або мікроватів витрат:
>
> - **Взимку** (голе дерево): RSSI ≈ −80 dBm (сигнал майже ідеальний)
> - **Навесні при розпусканні листя**: RSSI падає до ≈ −105 dBm — соковите листя (80% вода) поглинає 868 МГц хвилі
> - **Аналіз на сервері**: сезонна динаміка RSSI → індекс листяного покриву → фенологічні дані для Proof of Growth
>
> Фізика: довжина хвилі 868 МГц (λ ≈ 34.5 см) ефективно поглинається полярними молекулами H₂O. Зміна RSSI на 20-25 dBm між зимою і піком вегетації — надійний сигнал стану біомаси.

---

### 1.5 Phase 1.5: DMA Audio Pipeline (TinyML)

Активується **тільки** якщо `vibration_detected == 1` (ISR від п'єзодиска, GPIO_PIN_0).

```
Piezo EXTI ISR → vibration_detected = 1
       ↓
TIM2 Start (16 kHz clock)
ADC Start DMA → raw_audio_buffer[512]
       ↓
CPU: __disable_irq() → HAL_PWR_EnterSLEEPMode(WFI) → __enable_irq()
       ↓  (CPU спить, DMA наповнює буфер без участі процесора)
DMA ConvCplt ISR → audio_ready = 1 → CPU wake
       ↓
__DMB() (memory barrier — гарантуємо видимість DMA-даних CPU)
       ↓
HAL_ADC_Stop_DMA() + HAL_TIM_Base_Stop()
       ↓
Normalization: raw_audio_buffer[i] / 4095.0f → audio_buffer[i]
       ↓
Compute_LogMel(audio_buffer) → 40 log-mel ознак   [Path B log-mel — FW.25, 03_03 §3.4]
       ↓
TinyML Inference → ml_event_id + ml_confidence
       ↓
if (ml_confidence ≥ critical_threshold):   # FW.18 dual-zone (warn 0.60 / crit 0.85) — повна логіка 03_03 §5
  ml_event_id == 2 → acoustic_events++ (кавітація ксилеми)
  ml_event_id == 3 → Trigger_Emergency_LoRa_TX() (бензопила/вандалізм)
```

**TinyML Classes:**

| Event ID | Подія | Дія |
|----------|-------|-----|
| 0 | Тиша (Silence) | Нічого |
| 1 | Вітер (Wind) | Нічого |
| 2 | Кавітація (Cavitation) | `acoustic_events++` |
| 3 | Бензопила / Тампер (Chainsaw/Tamper) | `Trigger_Emergency_LoRa_TX()` — паніка! |

> **Ключова деталь DMA:** Під час наповнення буферу CPU переходить у `SLEEP` (не `STOP2`). Це легший сон: тактування CPU зупинено, але DMA, TIM2 та ADC продовжують працювати. `DMA ConvCpltCallback` виводить CPU зі сну через переривання.

> **Бар'єр пам'яті `__DMB()`:** Без Data Memory Barrier CPU може прочитати `raw_audio_buffer` зі свого кешу (стара версія) до того, як DMA запише нові дані. `__DMB()` гарантує, що всі попередні операції запису завершені перед наступним читанням.

---

### 1.6 Phase 2: Bit-Pack (lora_payload[16])

Формує 16-байтний payload для AES-128 шифрування (LoRa, post-ARCH.42):

```
Offset | Size | Field            | Значення
-------|------|------------------|---------------------------
0-3    | 4    | DID              | Tree ID (big-endian uint32)
4-5    | 2    | Vcap             | Напруга іоністора (mV, BE)
6      | 1    | Temp             | Температура кристала (°C, int8)
7      | 1    | Acoustic         | TinyML acoustic events (uint8, насичення: >255→255)
8-9    | 2    | Metabolism       | delta_t_seconds (BE uint16)
10     | 1    | BioContract      | [PanicFlag:1 bit | Status:2 bits | GrowthPoints:5 bits]
11     | 1    | TTL              | Mesh Time-To-Live (initial = 3)
12-13  | 2    | FirmwareVersionID| FIRMWARE_VERSION_ID (BE uint16)
14     | 1    | VPD index        | [HW.32] BME280 VPD (non-panic): 0–255 ≈ 0–5.1 kPa @ 0.02 kPa/LSB. Panic-пакет: байт належить SEC.10 frame counter
15     | 1    | Reserved         | Зарезервовано (0). Panic-пакет: SEC.10 frame counter (14-15 BE)
```

**Байт 10 (BioContract) — результат mruby Атрактора:**
- Біт `[7]`: PanicFlag → `0`=звичайний пакет, `1`=panic (Emergency TX). Нормальні пакети завжди маскуються `& ~PANIC_FLAG_BIT`.
- Біти `[6:5]`: Status → `0`=homeostasis, `1`=stress, `2`=anomaly, `3`=tamper
- Біти `[4:0]`: Growth Points → `0-31` (Proof of Growth; нормальний діапазон 10–31)

> **[FW.29] Disambiguація panic vs насичений acoustic_events:** до FW.29 `acoustic_events == 0xFF` вказував і на реальне насичення кавітаційних подій, і на panic. Тепер `PANIC_FLAG_BIT` (bit 7 байта 10) однозначно маркує паніку: `panic_payload[10] = 0x80`, а `panic_payload[7] = 0xFF` (acoustic). Нормальні пакети завжди виконують `lora_payload[10] &= ~PANIC_FLAG_BIT`.

> **[HW.32] Байт 14 (VPD index) — co-existence з SEC.10:** на **non-panic** пакетах байт 14 несе VPD-індекс (BME280, on-node), а байт 15 = 0. На **panic**-пакетах байти 14-15 належать SEC.10 anti-replay frame counter (BE) — VPD там не інтерпретується. Конфлікту немає: інтерпретація розрізняється `PANIC_FLAG_BIT` (байт 10, bit 7). Backend (`TelemetryUnpackerService`) читає байт 14 → `vpd` лише для non-panic пакетів. Сирі RH/тиск чекають FW.2 24B CCM (climate frame).

Після пакування:

```c
// [FW.28] Atomic read-and-clear: захист від Race Condition між DMA ISR та main loop
// (ISR може збільшити acoustic_events між перевіркою та скиданням у main loop)
__disable_irq();
uint8_t acoustic_snapshot = acoustic_events;
acoustic_events = 0;
__enable_irq();

lora_payload[7] = acoustic_snapshot;
```

**Насичення acoustic_events (FW.22) та атомарне зчитування (FW.28):** лічильник `acoustic_events` — **`uint8_t`** із saturating increment:
```c
uint8_t acoustic_events = 0;                        // [FW.22] Saturating uint8_t
if (acoustic_events < 255) acoustic_events++;        // Saturating increment (no overflow)
```
При пакуванні — атомарне зчитування та скидання (FW.28):
```c
// [FW.28] __disable_irq() guard — запобігає race condition з DMA ISR
__disable_irq();
uint8_t acoustic_snapshot = acoustic_events;
acoustic_events = 0;
__enable_irq();
lora_payload[7] = acoustic_snapshot;                 // Direct assignment (no clamping needed)
```
FW.22 переміщає захист від overflow на рівень інкременту (тип `uint8_t` фізично не може перевищити 255). FW.28 гарантує що жодна кавітаційна подія не втрачається між читанням і скиданням у main loop.

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
    lora_payload[10] = BIO_STATUS_VM_ERROR; // 0xFF = tamper status
    mrb->exc = NULL;
}
mrb_gc_arena_restore(mrb, arena_idx);     // Відновлюємо GC arena
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
    Radio.Send(mesh_relay_payload, 16);
    HAL_Delay(100);
    has_mesh_relay = 0;
}

// Шифруємо власні дані
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)lora_payload, 4, (uint32_t*)encrypted_payload, 1000);
Radio.Send(encrypted_payload, 16);
```

**Mesh Relay:** Якщо `has_mesh_relay == 1`, Soldier відправляє чужий зашифрований пакет (зі зменшеним TTL) перед власним. Це забезпечує ретрансляцію для дерев поза прямою видимістю Queen.

#### 1.8а Cold-Temperature TX Deferral (FW.10)

> **Кенозис холодом:** при `temp < -15°C` AND `vcap < 4000 mV` Solider свідомо пропускає TX-вікно (Should_Defer_TX повертає 1). Логіка — захистити EBFC від глибокої розрядки в умовах, коли ксилема замерзла і регенерація заряду тимчасово зупинена. Поріг температури суворо `<` (не `<=`), тому рівно `-15°C` не вважається холодом — це freeze-contract проти випадкової зміни оператора порівняння.

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

Відкривається **тільки** якщо `vcap_voltage > 2800 mV` (достатньо енергії).

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
  → Якщо всі чанки → CRC32 verify (хвіст wire-потоку: OtaPackagerService
    паддить bytecode до (len+4) % 11 == 0 і додає CRC32 BE — §4.6)
    → Write to Flash → NVIC_SystemReset()

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
| L2: Синхронні Вікна (TDMA) | RTC-координоване пробудження: кожні N хвилин, ~2 сек RX. Queen beacon → Time Sync → спільний розклад | ❌ Не реалізовано | [ARCH.26](00_07_Action_Plan_Tracker), [FW.20](00_07_Action_Plan_Tracker) |
| L3: CAD Preamble Detection | SX1262 `Radio.StartCad()` — короткий «нюх» ефіру на LoRa-преамбулу, **прив'язаний до TDMA-вікон L2 / грубого інтервалу** (НЕ щосекунди — див. ⚠️ нижче). Миттєвий PANIC (chainsaw) ініціює **відправник** через extended-preamble (preamble sampling), а не постійний RX приймача. | ❌ Не реалізовано | [ARCH.26](00_07_Action_Plan_Tracker) |

> **⚠️ Енергетична корекція CAD (2026-05-28):** «прокидатися ~2 мс щосекунди» **недооцінює вартість** і енергетично нежиттєздатне для µW-вузла на EBFC. Реальний цикл — не лише радіо: wake MCU зі STOP2 → init SPI → конфіг SX1262 на CAD → очікування результату → знову сон. Активна фаза ≈ кілька мс при ~5 мА (MCU+SX1262), тобто десятки–сотні µJ **на один цикл**. ×86,400 циклів/добу → одиниці джоулів/добу, що **багатократно перевищує** і добовий харвест EBFC, і запас EDLC (½·0.47F·3.3² ≈ 2.56 J). Тому CAD НЕ можна робити щосекунди: правильно — CAD **у синхронних TDMA-вікнах L2** (кожні ~15 хв) або з грубим інтервалом; для миттєвого PANIC — **відправник** подовжує преамбулу довше за період сну приймача (LoRa preamble sampling), і низько-duty-cycle CAD-приймач її зловить. Енергобюджет CAD переглянути окремо ([ARCH.26](00_07_Action_Plan_Tracker)).

---

### 1.9.1 Mesh Relay Anti-Pingpong Algorithm [DOC.2]

> **SSOT:** алгоритм описано тут; персистенція кешу — у §2 (RTC Backup Domain Layout, регістри `DR8 / DR9 / DR11`).

Mesh-relay у §1.9 повторює прийнятий 16-байтний шифрований пакет від іншого Солдата, але **тільки якщо** його DID не "вже бачили" у недавньому минулому. Без цього два Солдати у радіусі прямої видимості один одного утворюють `pingpong`-цикл (TTL зменшується до 0, але кожна сторона ретранслює ту саму DID нескінченно за рахунок дрейфу годинника).

> **⚠️ Передумова (per-device crypto):** релей розшифровує чужий пакет → `TTL--` → перешифровує — коректно лише за **спільного** LoRa-ключа. За канонічних **per-device** ключів ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)) Солдат не може розшифрувати чужий пакет (виходить сміття), а DID лежить усередині шифроблоку → opaque-релей потребує cleartext address-шару. Поточний production — **зірка** (Soldier→Queen 1-hop); mesh = страховка TRL 4-5 (рандеву → ARCH.26). Відкрите архітектурне питання → [`00_07` — ARCH.43](00_07_Action_Plan_Tracker).

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
- **Persistence через STOP2:** кеш виживає глибокий сон і повне знеструмлення з RTC Backup живленням. При full power-loss (включно з RTC) — кеш скидається у нулі, але `tree_did != 0` у DR7 захищає від ретрансляції власних пакетів.
- **Невразливість до DID-spoofing у короткому вікні:** якщо зловмисник інжектує пакети з DID реального сусіднього дерева, перший пройде, але всі наступні будуть drop'нуті. Atttacker мусить сатурувати весь radio space — що видно через `acoustic_events` (FW.18) і `panic TX` (SEC.10).

---

### 1.10 Phase 5: STOP2 Deep Sleep (target: 300 nA RTC-only)

> **⚠️ Power optimization target:** Раніше документ декларував STOP2 sleep current **2.1 µA**. Перерахунок енергобалансу ([`02_03 §9.5`](02_03_BQ25570_MPPT_Nano_Power)) показав, що при 2.1 µA система йде у мінус навіть з TX @ +14 dBm SF9. **Цільове значення для виходу у позитивний баланс — STOP2 у RTC-only mode (300 nA)** — [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power) Сценарій C. Це досягається відключенням SRAM2 retention (`PWR.CR1 RRSTP=1`) і збереженням стану ТІЛЬКИ у RTC Backup registers (20 × uint32). Реалізація — наступний firmware-цикл.

```c
// 1. Зберігаємо стан у RTC Backup Domain (20 регістрів — повне розкладання §2)
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0, acoustic_events);
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, last_wakeup_timestamp);
// ... DR2..DR19 (mesh state, Lorenz state, TinyML thresholds)

// 2. Відключаємо периферію для мінімального споживання
HAL_RNG_DeInit(&hrng);
__HAL_RCC_CRYP_CLK_DISABLE();

// 3. Цільова конфігурація для 300 nA (RTC-only mode):
//    SRAM2 retention OFF — стан тільки в RTC BKP registers
__HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE2);
// PWR->CR3 |= PWR_CR3_RRS  // RRSTP=0: SRAM2 OFF у STOP2 → -800 nA
// Watchdog: IWDG продовжує працювати з LSI 32 kHz (~200 nA)

// 4. Зупиняємо SysTick та входимо в STOP2
HAL_SuspendTick();
HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
HAL_ResumeTick(); // Виконується після пробудження

// 5. Відновлюємо периферію після wake
HAL_RNG_Init(&hrng);
__HAL_RCC_CRYP_CLK_ENABLE();
HAL_CRYP_Init(&hcryp);
```

**Trade-off RTC-only vs SRAM2 retention:** При SRAM2 OFF втрачається лише runtime-стан у **SRAM** — НЕ те, що в RTC Backup Domain. Виживає увесь DR0..DR19 (mesh-кеш `recent_mesh_dids`, EMA, Lorenz-стан, TinyML-пороги — §2 канонічна таблиця). Втрачається: OTA-буфер збирання, RAM-only лічильники (`warning_counter` ескалації TinyML тощо), scratch RX/TX/audio. Повний інвентар трьох груп + key→поле map того, що рятувати — §2.3.1. Усе, що має пережити STOP2 і **не** влазить у RTC (повний), іде у Flash-KV (§2.3). Перевага: економія ~800 nA × 3.3V × 3600s × η_buck(0.5) = 19 мДж/год → дозволяє +1 TX cycle на 2 години.

**Джерела пробудження (📐 КАНОН wake-source — FW.49):**
- **RTC WUT** (періодичний fine-tick, LSE йде у STOP2) — ОСНОВНИЙ wake. Вузол прокидається за розкладом, перевіряє Vcap-енергогейт ([FW.50](00_07_Action_Plan_Tracker)) і робить повний sense→Lorenz→TX цикл лише при достатньому перезаряді; інакше — назад у STOP2. `delta_t` = wall-різниця між energy-sufficient циклами через `Wall_Seconds_Now()` (RTC-календар), а НЕ active-tick.
- **GPIO EXTI** на GPIO_PIN_0 (п'єзодиск — async chainsaw/panic).
- **PVD Callback** (напруга < 2.2V — аварійне, не пробудження).
- **VBAT_OK** ([`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)) — апаратний buck/brownout-**гейт** (нижче порогу MCU знеструмлений → recovery = power-on-reset), **НЕ** GPIO-EXTI wake: при буфері 4.39 Дж VBAT_OK залипає HIGH (нема періодичного edge), а cold-start = power-on робить EXTI надлишковим.

> **Два різні пороги — не плутати (FW.49):** `VBAT_OK ON ≈ 3.4 В` — апаратний поріг **увімкнення buck'а** (BQ25570, [`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)): нижче нього MCU просто знеструмлений. **Vcap-енергогейт** — firmware-політика, що перевіряється вже ПІСЛЯ RTC-WUT-пробудження (пороги listen / cold-TX-defer / fauna ≈ 4.5 В — значення + сирий-ADC застереження у §1.4 [FW.50](00_07_Action_Plan_Tracker)) — і вирішує, чи цей конкретний цикл робить корисну роботу. Тобто «3.4 В» (HW-гейт живлення) ≠ «4.5 В» (FW-гейт fauna-сесії): різні шари, а не суперечливі значення одного порогу.

> **ADR wake-source (FW.49, founder 2026-06-07):** RTC WUT + Vcap-енергогейт + RTC-календар як timebase — обрано замість (а) чистого RTC-розкладу (`delta_t`=константа → мертвий біосигнал) і (б) VBAT_OK-edge (залипання HIGH + квантований `delta_t` + потреба HW-траси VBAT_OK→EXTI). `delta_t` як час перезаряду = метаболізм живе через Vcap-гейт, вимірюється wall-time. Staged-план + bench bring-up (LSE/RTC clock-tree у repo відсутній) — [`00_07` FW.49](00_07_Action_Plan_Tracker).

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

**Runtime.** Глобальний `volatile uint8_t g_node_role` встановлюється `Load_Node_Role()` у `main()` одразу після `Load_Lorenz_Seed()`. ARCH.26 (CAD relay) і повний FW.20-S2 (mesh time-sync relay) споживають прапорець без додаткової логіки. Backend `HardwareKeyService` не зачіпається — це чистий firmware-flag (інкрементальний патч, 2026-05-03).

**Тести.** 5 host-тестів (`test_arch27_*` у `firmware/test/test_soldier_logic.c`): `"SOLD"` / `"PROV"` / unprovisioned `0xFFFFFFFF` / zero / corrupted magic → коректний fallback.

**Cross-ref:** ARCH.26 ([`00_01`](00_01_Vision_Mission_and_Roadmap); §1.9 RX-вікно), [SEC.11] K_seed Flash layout, §2.1 (чому роль у Flash, не RTC).

---

## 🗺️ 2. Soldier RTC Backup Register Map (DR0..DR19) — Canonical SSOT [DOC.3]

> **SSOT (єдина точка істини):** ця таблиця — **єдине** канонічне джерело розкладки RTC Backup Domain Soldier'а. Будь-яка зміна (додавання нового поля, перепакування біт-полів, новий магічний маркер) **повинна** починатися з оновлення цієї таблиці. Документація [`03_04`](03_04_mruby_Lorenz_Attractor) (Lorenz state), [`03_03`](03_03_TinyML_Acoustic_Inference) (TinyML EMA) та firmware-код посилаються на цю таблицю, а не дублюють її.

> **Політика розширення (cross-ref [ARCH.28](00_07_Action_Plan_Tracker)):** STM32WLE5 має лише 20 backup регістрів (DR0..DR19). Після [FW.18] (DR13/DR14 TinyML) + **[FW.2 freeze-contract, 2026-05-24]** (DR15 → CCM Frame Counter) **жодного вільного регістра не лишилось** — нова RTC-resident фіча йде у Flash-KV (§2.3; так уже маршрутизовано FW.20-S2 anti-storm bitmap). Перед будь-якою зміною RTC: (1) огляд цієї таблиці на конфлікти, (2) ASCII bit-field діаграма для будь-якого packed-регістру, (3) новий магічний маркер у §2.1, (4) обов'язковий `isfinite()`/magic check при відновленні.

RTC Backup Domain не скидається при STOP2 та більшості реботів (окрім повного знеструмлення або `HAL_RTCEx_BKUPWrite` з нулями).

| Регістр | Змінна | Тип | Опис |
|---------|--------|-----|------|
| `DR0` | `[panic_frame_counter:16 \| reserved:8 \| acoustic_events:8]` | uint32 packed | **[SEC.10 + FW.22]** Спакована плоть: лічильник panic-кадрів anti-replay (uint16, monotonic + saturating @ 0xFFFF) у high 16 біт + лічильник акустичних подій (uint8, saturating [0,255]) у low 8 біт. Біти [23:16] зарезервовано. Пакетне збереження економить регістр — без packing був би потрібен новий слот, що залишило б DR15 єдиним вільним. Cold-boot DR0=0 → `panic_frame_counter` пересіюється з HRNG (range 0x0001..0xFFFF) для уникнення колізії з ще-не-протухлими Redis nonce-ключами попереднього втілення. |
| `DR1` | `last_wakeup_timestamp` | uint32 | Час останнього пробудження (HAL_GetTick/1000). [ARCH.21] Зберігається при PVD-брауноуті для delta_t continuity після recovery. |
| `DR2` | `has_mesh_relay` | uint8 | Прапорець: 1 = є пакет для ретрансляції |
| `DR3` | `mesh_relay_payload[0..3]` | uint32 | Транзитний пакет, байти 0-3 |
| `DR4` | `mesh_relay_payload[4..7]` | uint32 | Транзитний пакет, байти 4-7 |
| `DR5` | `mesh_relay_payload[8..11]` | uint32 | Транзитний пакет, байти 8-11 |
| `DR6` | `mesh_relay_payload[12..15]` | uint32 | Транзитний пакет, байти 12-15 |
| `DR7` | `tree_did` | uint32 | DID дерева (записується ОДИН РАЗ при народженні) |
| `DR8` | `recent_mesh_dids[0]` | uint32 | Anti-pingpong DID cache, слот 0 |
| `DR9` | `recent_mesh_dids[1]` | uint32 | Anti-pingpong DID cache, слот 1 |
| `DR10` | `ema_delta_t_x100` | uint32 | [FW.21] EMA delta_t × 100 (fixed-point 0.01 с) |
| `DR11` | `recent_mesh_dids[2]` | uint32 | Anti-pingpong DID cache, слот 2 (FW.21 fallback: vcap_x10 запаковано в DR12) |
| `DR12` | `[valid:8 \| count:8 \| ema_vcap_x10:16]` | uint32 | [FW.21] Метадані EMA + упакований vcap_x10 (max 55000 ≤ 2^16) |
| `DR13` | `tinyml_warning_threshold` | float32→uint32 | [FW.18] WARNING-зона TinyML confidence (default 0.60f, range [0.01, 0.99]) |
| `DR14` | `tinyml_critical_threshold` | float32→uint32 | [FW.18] CRITICAL-зона TinyML confidence (default 0.85f, range [0.01, 0.99]) |
| `DR15` | `[FW2_FC_MAGIC:8 \| frame_counter:24]` | uint32 packed | **[FW.2 / ARCH.42, freeze-contract 2026-05-24]** CCM LoRa Frame Counter (uint24, monotonic, ~16.7M cycles ≈ 64× longevity @ 1 TX/h × 25y). Magic `0x46` ("F") у high 8 бітах захищає від cold-boot junk; невалідний magic → HRNG reseed `0x000001..0xFFFFFE`. Активний лише при `#define FW2_CCM_ENABLED 1` (deferred до HW bench для `CRYP_AES_CCM` HAL верифікації) — до flip DR15 залишається 0 та panic anti-replay тримається на DR0[31:16] (SEC.10 transitional). |
| `DR16` | `lorenz_x` | float32→uint32 | [FW.6] X-координата атрактора Лоренца (IEEE 754 bit-copy) |
| `DR17` | `lorenz_y` | float32→uint32 | [FW.6] Y-координата атрактора Лоренца |
| `DR18` | `lorenz_z` | float32→uint32 | [FW.6] Z-координата атрактора (інтенсивність конвекції) |
| `DR19` | `LORENZ_STATE_MAGIC` | uint32 | [FW.6] Маркер валідності: `0x4C5A5354` ("LZST"). Захист від RTC-корупції |

> **DR7 — Незмінний DID:** Записується один раз при першому старті (`tree_did == 0`). Якщо `tree_did != 0` при наступних стартах, запис пропускається. Це гарантує унікальність ідентифікатора навіть після OTA-ребуту.

> **DR16-DR19 — Стан Лоренца (FW.6):** Зберігається/відновлюється при кожному циклі STOP2. При первинному старті або після повного знеструмлення (DR19 ≠ `0x4C5A5354`) система переходить у режим cold-start від K_seed через HKDF/HMAC деривацію `(x₀,y₀,z₀)` (**[SEC.11 / FW.30]** — замість старого `chaos_seed`). K_seed зчитується з Protected Flash Sector (`FLASH_SEED_ADDR = FLASH_KEY_ADDR + 20` post-ARCH.42, magic `"LSED"` = `0x4C534544`). NaN/Inf перевірка через `isfinite()` захищає від бітових помилок у Backup Domain. STM32WLE5 підтримує 20 backup registers (DR0-DR19). Після [FW.18] DR13/DR14 зайнято TinyML-порогами; **після FW.2 freeze-contract (2026-05-24) DR15 зайнято CCM Frame Counter** (24-bit + 8-bit magic) — резервних регістрів більше немає.

> **DR13/DR14 — TinyML confidence thresholds (FW.18):** Замість hardcoded `0.80` у `firmware/soldier/main.c` Phase 1.5 використовуються два пороги, що зчитуються на boot з RTC (IEEE 754 bit-copy через `uint32_to_float`) та валідуються діапазоном `[TINYML_THRESHOLD_MIN_VALID=0.01, TINYML_THRESHOLD_MAX_VALID=0.99]`. Magic-маркер не використовується (cold boot DR=0x00000000 → float 0.0f → invalid → fallback на дефолт). Інваріант `warning < critical` гарантується через `TinyML_Apply_Thresholds()` — при інверсії або рівності обидва пороги атомарно відкочуються на дефолти 0.60/0.85. Phase 5 writeback (`DR13/DR14`) персистить OTA-set значення через STOP2; деталі логіки і таблиця зон — [`03_03 §5`](03_03_TinyML_Acoustic_Inference).

### 2.1 Magic Markers (Канонічна Таблиця) [DOC.3]

Маркери валідності використовуються для розрізнення "регістр містить осмислені дані з попереднього циклу" vs "регістр у defaulted-стані після cold boot / RTC корупції / `HAL_RTCEx_BKUPWrite(0)`". Якщо маркер не збігається — відповідний блок ініціалізується з нуля.

| Магічний маркер | Значення (hex) | ASCII | Регістр-прапор | Захищає блок | Документ |
|-----------------|----------------|-------|----------------|--------------|----------|
| `LORENZ_STATE_MAGIC` | `0x4C5A5354` | `"LZST"` | `DR19` | `DR16/DR17/DR18` (lorenz_x/y/z) | [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor#21-звідки-беруться-вхідні-параметри) |
| `EMA_VALID_FLAG` (8 біт у DR12) | `0xA5` (high byte) | — | `DR12[31:24]` | `DR10` (ema_delta_t), `DR12[15:0]` (ema_vcap_x10) | [§13.3](#133-persistence--rtc-backup-registers-dr10--dr12-packed) |
| `tree_did != 0` | будь-яке non-zero | — | `DR7` (self) | `DR7` (захист від перезапису DID при OTA) | [§7](#-7-did-generation-народження) |

> **DR12 packed format (FW.21):** `[valid:8 | count:8 | ema_vcap_x10:16]`. `valid == 0xA5` означає що EMA fields ініціалізовано та накопичено ≥1 семпл. При cold boot DR12 == 0 → `valid != 0xA5` → EMA reset.

> **Чому різні маркери:** Lorenz (`"LZST"`) використовує цілий 32-бітний маркер у виділеному регістрі тому що `(0.0, 0.0, 0.0)` — валідний (хоч і нетиповий) стан атрактора, тому zero-check недостатній. EMA використовує 8-бітний sentinel у packed-регістрі через дефіцит DR-простору.

### 2.2 Procedure для додавання нової RTC Backup фічі [ARCH.28]

> **Кенозис інженерії:** перш ніж претендувати на регістр — перевір, чи можна щільніше упакувати існуючий, або **звільнити** під-використаний/mis-allocated DR (§2.3.2 reclamation menu — ширина/частота-запису/durability-клас). STM32WLE5JC має ЛИШЕ 20 backup-регістрів (`DR0..DR19`); після `[FW.18]` + `[SEC.10]` + `[FW.2]` (DR15 → CCM Frame Counter, freeze-contract) **вільних регістрів не лишилось**. Реальні приклади того, як ми відмовилися від нового регістра на користь packing'у:
>
> - **`[SEC.10]` panic frame counter (uint16) → DR0[31:16]** — спакували поряд з `acoustic_events` у DR0[7:0]. Без packing'у пішов би DR15, і ми залишилися б без жодного резерву.
> - **`[FW.21]` EMA `ema_vcap_x10` (max 55000 ≤ 2¹⁶) → DR12[15:0]** — спакували разом з `valid:8 | count:8`. Це звільнило DR11 під 3-й слот anti-pingpong (без packing'у `MESH_DID_CACHE_SIZE` упав би з 3 до 2).
> - **`[ARCH.27]` Node Role flag → Flash, не RTC** — magic-word `"SOLD"`/`"PROV"` живе у Protected Flash sector (`FLASH_KEY_ADDR + 56`), бо при cold-boot/VBAT-loss роль не повинна змінюватися. RTC було б помилкою. Повний спец — **§1.11**.

**Чек-листа ПЕРЕД тим, як просити регістр:**

1. **SSOT-рев'ю.** Прочитати §2 (цю таблицю) ПОВНІСТЮ. Чи поле справді потребує переживання STOP2? Якщо ні — RAM-only достатньо. Якщо так, але переживає лише warm-boot, а не VBAT-loss → теж RAM (SRAM зберігається у STOP2).
2. **Packing-аудит.** Перевірити для кожного існуючого packed-регістру (DR0, DR12), чи є вільні бітові щілини для нового поля. Реальні розміри:
   - `DR0[15:8]` — 8 біт зарезервовано (vacant).
   - `DR12[31:24]` — `valid:8` зайнято, але вільних бітів немає.
   - Більшість «full uint32» регістрів використовують лише частину діапазону (наприклад, `last_wakeup_timestamp` у DR1 — це секунди від boot, рідко перевищує 24 біт за реалістичний час до VBAT-loss).
3. **ASCII bit-field діаграма.** ОБОВ'ЯЗКОВО для будь-якого packed-регістру. Приклад з DR0:
   ```
   DR0 = [panic_frame_counter:16][reserved:8][acoustic_events:8]
          ↑              MSB                          LSB ↑
          PANIC_COUNTER_DR0_SHIFT=16                  raw uint8
   ```
   Без діаграми наступна людина (або ти за рік) не зрозумієш порядок бітів.
4. **Magic marker policy.** Якщо `0` — валідне значення поля (як `(0.0, 0.0, 0.0)` для Lorenz state), то ОБОВ'ЯЗКОВО потрібен окремий 32-бітний marker у сусідньому регістрі АБО 8-бітний sentinel у packed-регістрі. Маркер додати у §2.1. Якщо `0` валідно інтерпретується як «cold-boot default» (як `tinyml_warning_threshold == 0.0f` → fallback `TINYML_DEFAULT_WARNING`), маркер не потрібен — достатньо range-check.
5. **Restore guard.** При читанні з RTC ПЕРЕД використанням — `isfinite()` для float, magic-check для structured fields, range-validation для цілочисельних. Захищає від bit-flip у backup domain (рідкісне, але документоване ST явище у high-radiation environments).
6. **Host-test bank.** Кожна нова фіча, що торкається RTC, повинна мати ≥3 host-тести: (a) cold-boot fallback, (b) warm-boot roundtrip, (c) corruption/bit-flip відкочується на default. Приклади: `test_arch21_pvd_*`, `test_sec10_dr0_*`.
7. **Doc update.** Оновити §2 канонічну таблицю + §2.1 magic markers + cross-link з 00_07 (відповідний ID).

**DR15 зайнято FW.2 (freeze-contract) — вільних регістрів нема:** будь-яка нова RTC-resident фіча йде у §2.3 (Flash-based KV store). FW.20-S2 anti-storm bitmap уже так маршрутизовано (resolution 2026-05-30).

### 2.3 Overflow strategy: Flash-based KV store [ARCH.28]

> **DR15 вже зайнято (FW.2 CCM Frame Counter, freeze-contract):** наступна фіча, що потребує RTC-resident state з переживанням VBAT-loss, не отримає **нового** регістра — але спершу зваж **реклемацію** під-використаного/mis-allocated DR (**§2.3.2**: часто дешевше за Flash-wear). Якщо реклемація не підходить — нижче три Flash-шляхи; **шлях A — ✅ host-імплементовано (2026-06-07)**, бо на нього вже маршрутизовано три споживачі (FW.54 wall-маркери/EMA, FW.20-S2 bitmap, FW.49).

> **✅ Шлях A — імплементація (host-first):** `firmware/common/flash_kv.{h,c}` + power-cut тести `firmware/test/test_flash_kv.c` (`make -C firmware/test flash_kv`). Дизайн AN4894-патерну під ECC WLE5: **елемент = один doubleword** `[value:32][key:8][flags:8][crc16:16]` (програмування dw атомарне щодо ECC → «порваного» запису не існує), append-only «останній виграє», дві сторінки ping-pong із заголовками `SKV1|seq` + `FINI|seq` — **FINI програмиться останнім**, тож power-cut посеред compact лишає стару сторінку авторитетною (інваріанти I1-I3 у `flash_kv.c`, кожен доведений fault-injection тестом). Compact пропускає erase уже-чистої цілі (wear ÷2 у steady-state). Залізні примітиви ізольовано у `FlashKvOps` — host підставляє RAM-мок, MCU підставить `HAL_FLASH_Program/Erase` при HAL-фазі.
>
> **✅ Sibling — OTA contract blob writer (FW.52-г):** `firmware/common/flash_ota.{h,c}` (`Flash_Write_Contract`) reuse'ить ту саму `FlashKvOps`-абстракцію, але пише **простий blob** (не KV-журнал) — зібраний OTA-байткод у contract-сторінку **126** (`MRUBY_CONTRACT_FLASH_ADDR`): erase + dw-program, **power-cut-safe: RITE-magic dw програмиться ОСТАННІМ** (перерваний запис → dw[0]=0xFF → boot не бачить magic → fallback на embedded `lorenz_bytecode`). Host-тести `test_flash_ota.c` (8/8 — round-trip · magic-last · erase-fail · reject); HAL-glue `g_ota_flash_ops` у `main.c` (bench-фаза). Закрив FW.52-г: раніше `Write_OTA_Contract_To_Flash` був порожнім hal_mock-стабом → OTA нефункціональний end-to-end.
>
> **Розміщення (freeze-contract):** сторінки **122-123** (`0x0803D000`-`0x0803DFFF`) — хвіст зайнятий: 124 = ключі/K_seed/роль (`FLASH_KEY_ADDR`), 126(-127) = OTA contract (`MRUBY_CONTRACT_FLASH_ADDR`), 127 = Queen UID. Сторінка 125 — буфер росту key-блоку, НЕ чіпати.
>
> **Wear-бюджет (зчеплений з E.63-шкалою delta_t):** 2 КБ сторінка = 254 елементи; запис «снапшот циклу» = K елементів/пробудження → erase раз на ⌊254/K⌋ циклів; 10k endurance × 2 сторінки. При K=4 і delta_t=36 с (оптимістичний кут L4) → ~2.6 роки; при realistic 1.77 год ([`02_03 §9.8`](02_03_BQ25570_MPPT_Nano_Power)) → століття. Якщо польова delta_t впаде під ~5 хв стабільно — розширити page-set (4-8 сторінок, адреси вниз від 122) або лишити SRAM2-retain (−800 нА) свідомим trade-off (FW.54).
>
> **Bench-residual:** реальні `HAL_FLASH_*` глю + політика ECCD-читання (double-error → NMI: чи читати через перевірку `FLASH_ECCR` — RM0461) + вимір erase-стійкості до LoRa RX-вікна.

| Шлях | Опис | Плюси | Мінуси | Коли вибирати |
|------|------|-------|--------|--------------|
| **A. STM32 Flash sector emulated EEPROM** ✅ host-impl | Дві 2 КБ-сторінки ping-pong під key-value store (журнальний append + compact) — реалізацію див. блок вище (`flash_kv.c`, key u8 → value u32; багатословний стан = кілька ключів). | Безкоштовно (Flash вже є), ємність сотні елементів/сторінку. | Erase блокує шину → `FlashKv_NeedsCompact()` назовні: викликач ущільнює поза LoRa RX-вікном. Wear ~10k cycles/сторінку — бюджет у блоці вище. | Стан, що мусить пережити VBAT-loss/SRAM2-off: FW.54 wall-маркери, FW.20-S2 bitmap, config/calibration. |
| **B. SE050 secure objects** | Якщо `[SEC.6]`/SE050 на платі — SE secure objects + HW monotonic counters (SE = SE050, [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)). | Tamper-protected, не впливає на main Flash. Counters апаратно monotonic — ідеально для anti-replay. | +$2.40–3.25/unit BOM. I²C latency. | Security-sensitive state: rotation counters, signing certificates, key versions. Synergy з `[FW.17]` Hash Ratchet. |
| **C. Bit-перепакування** | Перейти на 16-бітні розрядні поля для тих uint32, що використовують реально <2¹⁶ діапазон (наприклад, `last_wakeup_timestamp` секунди від boot, рідко >18 год = 65 К секунд). | Нульова BOM-вартість, нульова latency. | Ризикує overflow'ом при патологічних сценаріях (вузол прокинувся у режимі OTA на >18 год, потрапив у IWDG storm, тощо). Складніше debug'ити. | Останній крок перед Flash-KV: коли packing може дати +1-2 регістри на дешеві поля. |

**Рекомендований порядок при наступній витрати DR15:** (1) спершу аудит packing'у (§2.2 крок 2) → (2) шлях C якщо є кандидати → (3) шлях A для рідко-оновлюваних → (4) шлях B якщо SE050 вже на платі. Ніколи не дублювати дані між RTC і Flash «про всяк випадок» — це джерело розсинхронізації.

#### 2.3.1 FW.54 RAM-state inventory — що пережити SRAM2-off (key→поле map)

> **Передумова.** У цільовому RTC-only режимі (§1.10, 300 нА) **RTC Backup Domain (DR0..DR19) виживає** — це його суть. Втрачається лише runtime-стан у SRAM. Тому інвентар ділить увесь file-scope стан `firmware/soldier/main.c` на три групи; у Flash-KV їде **лише** група C (RTC повний — §2).

**Група A — RTC-resident (вже безпечне, нічого не робимо).** Усе, що Phase 5 (Кенозис) пише у DR0..DR19: panic/acoustic, `last_wakeup_timestamp`, mesh-relay payload+flag, `recent_mesh_dids` (mesh-кеш!), EMA (`ema_*`), Lorenz `(x,y,z)`+magic, TinyML-пороги, `tree_did`, FW.2 Frame Counter. Точна розкладка — §2 (не дублюємо). Виживає у RTC-only без жодних змін.

**Група B — ефемерне (per-wake, втрата НЕ важлива).** Scratch-буфери, що наповнюються щоциклу до використання й не несуть сенсу між пробудженнями: `raw_audio_buffer`/`audio_buffer` (DMA), `lora_payload`/`encrypted_payload` (TX), `incoming_lora_payload`/`decrypted_rx_payload` (RX), ISR-прапорці (`vibration_detected`, `audio_ready`, `lora_rx_flag`), `ml_event_id`/`ml_confidence`, `delta_t_seconds` (рахується щоциклу), `current_lorenz_bytecode` (вказівник, ставиться на boot), `g_node_role`/`lorenz_seed[]` (читаються з Protected Flash на boot — §1.11/SEC.11). Персистити нічого.

**Група C — must-survive, але RAM-only → Flash-KV ключі.** Стан, що мусить нести значення **між** циклами, але якому нема місця у RTC (DR0..DR19 повні):

| Ключ | Поле(я) | Пакування (u32) | Споживач | Статус |
|------|---------|-----------------|----------|--------|
| `0x01` WARN_ESC | `warning_counter` · `tinyml_threshold_invalid_count` · `fauna_skipped_low_vcap` | `[warn:8 \| inval:8 \| fauna:8 \| rsv:8]` | TinyML escalation (3× WARNING поспіль — [`03_03 §5`](03_03_TinyML_Acoustic_Inference)) + діагностика | **live** |
| `0x02` SYNC_WALL | `last_sync_request` (wall-сек) | u32 | FW.20-S2 sync-cooldown | live (degradable) |
| `0x03` OTA_SILENCE_WALL | `ota_last_chunk_rx` (wall-сек) | u32 | FW.27-B OTA re-request silence | live (лише під OTA) |
| `0x10`–`0x11` FW8_ZCFG | `lorenz_z_{min,max,opt}_x100` · `species_id` · `config_version` | 2 dw | FW.8 per-tree Z-пороги | gated (`FW8_PARSER_ENABLED=0`) |
| `0x12` FW8_AUDIO | audio config + version | u32 | FW.8 audio-пороги | gated |
| `0x20…` S2_BITMAP | anti-storm dedup bitmap | multi-dw | FW.20-S2 mesh-relay | gated (повний mesh-relay) |

> **Головний wall-маркер delta_t — НЕ Flash-KV ключ.** «Wall-секунди останнього energy-sufficient циклу» (база `Silken_Wall_Delta_Seconds`, `firmware/common/wall_time.h`) переселяє **семантику** `last_wakeup_timestamp` (DR1: tick-сек → wall-сек) — реюз наявного RTC-регістру, а не нова Flash-фіча. Тож FW.49 timebase **не** додає Flash-write/цикл; у Flash-KV їдуть лише вторинні маркери (`0x02`/`0x03`), що деградують м'яко (втрата → м'який re-ask після grace).

**K (елементів/пробудження) + звірка wear-бюджету.** (Спершу: чи треба Flash для live-набору взагалі — **ні**, він вміщується у RTC-headroom, **§2.3.2**. Нижче — бюджет на випадок, якщо headroom свідомо лишають Lorenz/іншому стану й live-набір таки їде у Flash.) Live-набір групи C = {`0x01`, `0x02`, `0x03`}. Консервативно (snapshot-every-cycle = пишемо КОЖЕН live-ключ щоциклу) → **K=3 < K=4** припущення бюджету (вище). Реалістично (write-on-change — Flash-KV append-only «останній виграє») у steady-state змінюється лише `0x01`, і лише коли інференс зрушив лічильник → **K≈1**. Отже наведені у бюджеті ~2.6 роки (оптимістичний кут 36 с) / століття (realistic 1.77 год) — **безпечні нижні межі, не оптимістичні**. Якщо FW.8 + FW.20-S2 активуються разом і знадобиться snapshot-every-cycle, K зросте у бік ~6–8 → erase раз на ⌊254/K⌋ циклів; навіть тоді при realistic delta_t це десятиліття, лише оптимістичний 36-с кут наближається до бюджету → застосувати «розширити page-set» (вище).

> **⚠️ OTA-буфер збирання — окремий випадок (НЕ Flash-KV).** Стан OTA (`ota_buffer` + `ota_chunk_received` + `received_hmac_tag` + лічильники чанків) — порядку КБ, і він **мусить** пережити STOP2, бо FW.27-B re-request добирає пропущені чанки **між** пробудженнями (Солдат у STOP2 пропускає частину broadcast — §4.6). Класти ~КБ у Flash-KV щоциклу = K у сотні dw → wear-смерть за дні: **неприйнятно**. Висновок для 👤-розвилки (persist-кожен-цикл vs SRAM2-retain): SRAM2-retain — рішення **per-mode, не глобальне**. Steady-state = RTC-only (300 нА); на час активної OTA-кампанії (рідко, хвилини-години) — тимчасово SRAM2 retention ON, потім назад у RTC-only. Це знімає і wear, і відмову «OTA ніколи не збереться під SRAM2-off».

#### 2.3.2 RTC headroom — чи можна звільнити DR замість Flash (FW.54 reclamation)

> **Виклик премісі.** §2/§2.2/§2.3 кажуть «20 регістрів зайнято → нова фіча у Flash». Це правда про **allocation**, але НЕ про **utilization**: кілька DR несуть жменю реальних біт у 32-бітному слоті, а один тримає write-once стан там, де він не потрібен. Перш ніж платити Flash-wear (§2.3) — є дешевший RTC-headroom. Реклемація розкладена по трьох осях.

**Вісь 1 — ширина (під-використані біти).** Кілька слотів несуть <8 біт корисного:

| DR | Реальні біти | Реклемація | Ціна |
|----|--------------|------------|------|
| `DR2` `has_mesh_relay` | **1** (прапорець 0/1) | → біт у вільному `DR0[15:8]` ⇒ **DR2 вільний** | нуль, mode-independent |
| `DR14` `tinyml_critical` | ~7 (float ∈ [0.01,0.99]) | обидва пороги як 2× `uint8`-відсоток у `DR13[15:0]` ⇒ **DR14 вільний** | 1% гранулярність (нехтовна); freeze-contract правка |
| `DR19` `LORENZ_STATE_MAGIC` | 32 (чистий маркер) | 7-біт sentinel у `DR0[15:9]` (як EMA `0xA5` у DR12) ⇒ **DR19 вільний** | слабша bit-flip-стійкість за 32-біт маркер |

> `warning_counter` (головний live-споживач FW.54) ескалює на 3 і скидається ([`03_03 §5`](03_03_TinyML_Acoustic_Inference)) → реально **2 біти**, не 8. Він + `has_mesh_relay` (1 біт) сідають у вільний байт `DR0[15:8]` **без жодного нового регістру**.

**Вісь 2 — частота запису (інверсія RTC↔Flash).** RTC backup безкоштовний щодо wear; Flash має wear + erase-блокує-шину. Оптимум: **write-ONCE → Flash** (нуль wear, ідеально), **часто-оновлюване → RTC**. Зараз **навпаки**:

- `DR7` `tree_did` — **write-once identity** у дефіцитному wear-free RTC; а часто-оновлюваний FW.54-стан (§2.3) виштовхується у wear-prone Flash. Інверсія.
- DID уже відомий провіженінгу: K_seed деривується **з DID** (`SilkenNet::SeedDerivation`, `info = "silken-lorenz-seed|<DID>"`; firmware-дзеркало — SEC.11 / §2) → щоб запекти K_seed у Protected Flash, host **мусить** знати DID на провіженінгу.
- ⚠️ Поточний firmware натомість **самогенерує** DID з UID **⊕ true_random** (§7 НАРОДЖЕННЯ) і тримає лише в DR7. Наслідки: (1) DID **не VBAT-durable** → повний розряд EDLC (HW.14 зимовий дефіцит — а cold-start machinery саме й існує, бо VBAT-loss очікуваний) **сиротить identity/гаманець** новим random-DID; (2) DID **не відтворюваний** → провіженінг не може його передбачити, лише device-first (пристрій репортить → host деривує K_seed 2-м проходом).
- **Реклемація:** DID → Protected Flash (поряд key/seed/role на `FLASH_KEY_ADDR`; write-once → нуль wear) **АБО** детермінований DID = f(UID) без random (відтворюваний з always-present UID `0x1FFF7590` → DR7 стає кешем, recompute на boot). Обидва шляхи: **DR7 вільний** + DID стає VBAT-durable. 👤 рішення: source-of-truth DID (UID-deterministic vs backend-assigned) обирає шлях — це **окремий correctness/hardening finding**, не лише register-free (трекер [`00_07`](00_07_Action_Plan_Tracker) FW.54).

**Вісь 3 — durability-клас (transient operational).** RTC backup = VBAT-durable. Та частина стану потребує лише warm-STOP2-виживання, не VBAT-durability, і має прийнятну loss-on-power-cut семантику:

- `DR3`–`DR6` mesh-relay payload + `DR8`/`DR9`/`DR11` anti-pingpong кеш — транзитний/операційний (чужий пакет у транзиті; recent-DID дедуп). Втрата на cold-path безпечна (мережа має TTL/retry). У RTC лише щоб пережити майбутній SRAM2-off.
- **Реклемація (mode-coupled):** під per-mode SRAM2 (§2.3.1 OTA-висновок: SRAM2 ON у вузьких активних вікнах, RTC-only у steady-state) цей клас живе у SRAM → до **~8 регістрів** звільняється. Ціна: зчеплено з per-mode рішенням + втрата mesh-стану на холодних шляхах. `recent_mesh_dids` додатково стискається до 16-біт DID-хешів (3 у ~1.5 рег) ціною рідких хеш-колізій.

**Синтез + bottom-line для FW.54.** Усі 20 *allocated*, але мапа mis-allocated по трьох осях. Дешева реклемація (Вісь 1: DR2 тривіально; `warning_counter` у `DR0[15:8]`) **повністю розміщує live-набір FW.54 у RTC — Flash-KV для нього НЕ потрібен**. Flash-KV (§2.3) лишається виправданим лише для (а) gated bulk (FW.8 config, FW.20-S2 bitmap) ЯКЩО активуються, і (б) **не** OTA-буфера (це per-mode SRAM2, §2.3.1). Найбільший одиничний чистий виграш — **Вісь 2 (DR7/DID)**, що заразом закриває latent identity-orphaning. Порядок при наступній витраті регістру (доповнює §2.3): **(0) реклемація DR — Вісь 1 → Вісь 2 → Вісь 3 перед будь-яким Flash**.

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

> **Чому НЕ застосовуємо зараз:** заміна 15 викликів торкається hot path (Phase 5 STOP2-write і ARCH.21 PVD callback) — кожне торкання потребує перевірки усіх 5 host-тестів `test_arch21_pvd_*` + 13 `test_sec10_*` + усього існуючого test-bank. Користь — лише консистентність + опційне трасування. ROI на TRL-6 негативний; повернутися до цього при рефакторингу під RTOS (ARCH.29) або при першому реальному debug-сесії з польового пристрою.

> **Cross-link:** `00_07 ARCH.28` — RTC Backup Domain allocation policy.

---

## 💾 3. Soldier RAM Budget (~5 KB з 64 KB SRAM)

| Змінна | Тип | Розмір | Призначення |
|--------|-----|--------|-------------|
| `aes_key[4]` | `uint32_t` | 16 B | AES-128 LoRa ключ (post-ARCH.42; Soldier; per-device через HKDF) |
| `lora_payload[16]` | `uint8_t` | 16 B | Вихідний payload перед шифруванням |
| `encrypted_payload[16]` | `uint8_t` | 16 B | Зашифрований payload для Radio.Send |
| `mesh_relay_payload[16]` | `uint8_t` | 16 B | Транзитний зашифрований mesh-пакет |
| `recent_mesh_dids[3]` | `uint32_t` | 12 B | Кеш DID для anti-pingpong (FW.21: shrunk 8→3, vcap_x10 запаковано у low 16 біт DR12 щоб звільнити DR11) |
| `raw_audio_buffer[512]` | `uint16_t` | 1024 B | Сирі 12-бітні DMA-семпли (TinyML) |
| `audio_buffer[512]` | `float` | 2048 B | Нормалізовані float-семпли для inference |
| `incoming_lora_payload[256]` | `uint8_t` | 256 B | Вхідний LoRa буфер (volatile) |
| `decrypted_rx_payload[256]` | `uint8_t` | 256 B | Розшифрований вхідний потік |
| `ota_buffer[1024]` | `uint8_t` | 1024 B | OTA байт-код (assembly buffer) |
| `ota_chunk_received[256]` | `uint8_t` | 256 B | OTA dedup bitmap (один bit = один chunk) |
| **Всього** | | **~5 KB** | |

---

## 👑 4. Queen — Архітектура Шлюзу-Агрегатора

### 4.1 Апаратна Платформа

Queen **ніколи не спить** (continuous operation). Живиться від сонячної панелі та акумулятора.

| HAL Handle | Периферія | Призначення |
|------------|-----------|-------------|
| `huart1` | USART1 | SIM7070G модем (LTE-M / NB-IoT, 115200 baud) |
| `hsubghz` | SUBGHZ | LoRa трансивер SX1262 (868 МГц) |
| `hcryp` | AES | ECB (LoRa), CBC (CoAP batches), CBC (downlink commands) |
| `hrng` | RNG | HRNG для генерації IV (CBC) та flush jitter |
| `hiwdg` | IWDG | Апаратний Watchdog (~26.6 с timeout, додано у PR #273) |

**Queen НЕ має:** ADC, TIM2, RTC — на відміну від Soldier. **Queen тепер має IWDG** (додано у PR #273).

### 4.2 Загальний Lifecycle

```
Init → Radio.Init → Radio.Rx(0xFFFFFF) [infinite]
┌─────────────────────────────────────────────────────────┐
│  while LoRa_Rx_Ring_Pop(rx_payload, &rx_rssi):  [FW.3]  │
│    1. AES-128-ECB Decrypt (16 bytes) [post-ARCH.42]    │
│    2. OTA Reflex Shot (if ota_is_active)               │
│    3. Extract sender DID (bytes 0-3)                   │
│    4. Process_And_Cache_Data(DID, payload, RSSI)       │
│    5. Radio.Rx(0xFFFFFF) → next pop                    │
│                                                         │
│  if cache_count >= 45 OR timer >= 1hour + jitter:      │
│    Inject Queen Health Sentinel (DID=0x00000000)       │
│    [MX_CRYP re-init → CRYP_KEYSIZE_256B + coap_key]   │
│    Flush_Cache_To_Rails() → CoAP PUT (AES-256-CBC)     │
│    [restore → CRYP_KEYSIZE_128B + LoRa aes_key — SEC.8]│
└─────────────────────────────────────────────────────────┘
```

### 4.3 CIFO Cache Algorithm

```c
typedef struct {
    uint32_t uid;       // Tree DID
    uint8_t payload[16]; // Останній decrypted payload
    int8_t rssi;        // Signal quality
    uint8_t is_active;  // 1 = зайнятий слот
} EdgeCache;

EdgeCache forest_cache[50]; // 50 слотів = 1150 байт RAM
```

**Логіка `Process_And_Cache_Data(uid, payload, rssi)`:**
1. **Dedup:** Знайти uid → оновити payload + RSSI → повернути
2. **Insert:** Знайти вільний слот → вставити → `cache_count++`
3. **CIFO Priority Eviction** (кеш повний):
   - Шукати `bio_status == 0` (homeostasis) з найгіршим RSSI → витісняємо
   - Якщо ВСІ записи критичні → fallback: найгірший RSSI незалежно від статусу

### 4.4 Cache Flush до Rails (CoAP)

**Тригери:**
- `cache_count >= 45` (50 - 5 headroom)
- `HAL_GetTick() - last_flush_time > 3,600,000 + jitter` (1 година + random jitter 0-60s)

**Flush Jitter:** При одночасному ребуті кількох Queens (blackout) — без jitter всі Queens відправлять батч одночасно → DDoS на backend. Jitter (0-60s, HRNG) розмазує трафік.

**Послідовність:**
1. Inject Queen Health Packet (DID=0x00000000 sentinel)
2. Pack cache → `binary_batch_buffer` (21 байт/запис: 4 DID + 1 RSSI + 16 payload)
3. **MX_CRYP re-init** → `CRYP_KEYSIZE_256B` + `coap_key[8]` (CoAP AES-256-CBC ключ Queen, окремий HKDF info `"silken-aes-256-device-key"`)
4. AES-256-CBC encrypt з HRNG IV (prepend IV як перші 16 байт)
5. `AT+CCOAPNEW` → `AT+CCOAPSEND` (hex-кодований) → `HAL_Delay(2000)` → `AT+CCOAPDEL`
6. **Restore ECB+128B mode** → `CRYP_KEYSIZE_128B` + `aes_key[4]` (LoRa) для трафіку від Soldiers (критично — SEC.8 ECB Restoration)

**Queen Sentinel Packet (DID = 0x00000000):** health-пакет Королеви перевикористовує ту саму 16-байтну wire-розкладку, що й Soldier, але з `DID=0` (sentinel «це Королева, не дерево») і репурпозить поля (uptime · cache-load · health-proxy `cache_count`, cap 5-біт). Повна byte-map + C-код + server-routing (`GatewayTelemetryWorker`) — канон [`03_02 §7`](03_02_Queen_Gateway_Firmware).

### 4.5 OTA Reflex Shot (Broadcast до Soldiers)

**Механізм:** Soldier слухає ефір 500ms після власного TX. Queen, отримавши пакет від Soldier, **миттєво** відповідає OTA-чанком.

```
Queen OnRxDone ISR → LoRa_Rx_Ring_Push (FIFO 15-slot, FW.3)
       ↓
Main loop: while pop → decrypt → if ota_is_active:
  Build OTA chunk (16 bytes):
    [0x99][chunk_idx_hi][chunk_idx_lo][total_hi][total_lo][bytecode:11]
  AES-128-ECB Encrypt → Radio.Send [post-ARCH.42](16)
  HAL_Delay(60) → next_chunk_idx++
```

Chunk-розмір для LoRa OTA: **11 байт** корисного коду (з 16-байтного AES-блоку вираховуємо 5 байт заголовку).

### 4.5а Downlink Opcode Map — Canonical SSOT [DOC.4]

Карта маркерів downlink-пакетів (CoAP Rails→Queen та LoRa Queen→Soldier). Будь-який новий downlink-CMD **повинен** додаватися сюди до імплементації, щоб уникнути колізій. Опкоди розташовані у безпечному діапазоні `0x99..0x9F` (значення байтів, що не зустрічаються як прийнятні DID-prefixes у telemetry uplink — DID generated as `crc32` із низькою імовірністю старшого байта `0x99..0x9F`).

| Опкод | Назва | Напрямок | Лінк | Документ | Статус |
|-------|-------|----------|------|----------|--------|
| `0x55` | OTA_REQ_MARKER (Magic Re-Request) | Soldier→Queen | LoRa **uplink** | [`03_02 §5.X.3`](03_02_Queen_Gateway_Firmware) | ✅ FW.27-B (2026-05-02) |
| `0x99` | OTA_MARKER (bytecode chunks) | Rails→Queen→Soldier | CoAP/LoRa | §4.4 + 03_02 §5 | ✅ |
| `0x9A` | CMD_SET_THRESHOLDS (Lorenz Z per-tree) | Rails→Queen→Soldier | CoAP/LoRa | [`05_02 §4а.1`](05_02_Proof_of_Growth_Pipeline) | 🟡 FW.8 (Queen-side; Soldier dispatcher TBD) |
| `0x9B` | CMD_HMAC_TRAILER (OTA HMAC-SHA256 печатка) | Rails→Queen→Soldier | CoAP/LoRa | [`03_05 §3.4б`](03_05_Hardware_Symmetric_Crypto_and_Security) | ✅ FW.23 (2026-05-02) |
| `0x9C` | CMD_TIME_SYNC (envelope) | Rails→Queen | CoAP | §11 (FW.20) | ✅ FW.20 |
| `0x9D` | CMD_SET_AUDIO_THRESHOLDS (TinyML per-Soldier) | Rails→Queen→Soldier | CoAP/LoRa | [`03_03` — BLOCKER-6](03_03_TinyML_Acoustic_Inference) | ✅ FW.18 (2026-05-02) |
| `0x9E` | _reserved_ | — | — | — | вільний |
| `0x9F` | _reserved_ | — | — | — | вільний |

> **Політика розширення:** перед додаванням нового опкоду — (1) перевірити цю таблицю, (2) обрати наступний вільний з `0x9E..0x9F`, (3) задокументувати тут І у відповідному функціональному документі (03_02/03_05/05_02). Якщо `0x9E..0x9F` вичерпано — обговорити перепакування або новий безпечний діапазон.

### 4.6 CoAP Downlink → OTA RAM Assembly

Queen отримує великі OTA-пакети від Rails через CoAP (`Handle_CoAP_Command`):

```
Rail CoAP PUT: [IV:16][CBC_encrypted: [0x99][chunk_idx:2 BE][total:2 BE][len:2 BE][bytecode:len][crc16:2 BE]]
       ↓
Handle_CoAP_Command():
  AES-256-CBC Decrypt (з IV з перших 16 байт; CRYP_KEYSIZE_256B + coap_key)
  Restore ECB+128B mode (CRYP_KEYSIZE_128B + LoRa aes_key) — SEC.8
  OTA_MARKER detected (0x99):
    chunk_index, total_chunks, len (big-endian)
    CRC16-CCITT verify над header+bytecode (common/silken_crc.h ↔ OtaPackagerService.crc16_ccitt)
    Bitmap dedup: ota_chunk_bitmap (+ idle-стан → pending_ota_size = 0: нова кампанія)
    memcpy → pending_ota_bytecode[chunk_index * 512]
    ota_chunks_received++
    if all received → ota_is_active = 1 → LoRa broadcast starts
```

> **[FW.53] Явний `len` + CRC16-перевірка.** Стара схема вгадувала
> довжину чанка з CBC zero-padding (формула `aligned−16−7`) і при паддінгу 0..15
> байт **систематично обрізала 1..16 байт кожного чанка** (повний 512B → 500B);
> CRC16 від бекенду не перевірявся взагалі. Деталі парсера — [`03_02 §5`](03_02_Queen_Gateway_Firmware).
> Сам потік, що його чанкують CoAP/LoRa-шари, тепер **wire-потік**: `bytecode +
> zero-pad + CRC32(4B BE)`, вирівняний на LoRa MTU 11 — щоб CRC32 лягав рівно в
> кінець останнього LoRa-чанка (Soldier рахує отримане як `11 × chunks`).
> Будує `OtaPackagerService` (дзеркальні специфікації — `spec/services/ota_packager_service_spec.rb`).

### 4.7 Actuator Command Dedup (Idempotency)

```
CoAP Downlink: CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<UUID>
       ↓
djb2_hash(UUID) → 32-bit hash
       ↓
Cmd_Dedup_Check(hash):
  Scan cmd_dedup_ring[16]
  Found → return 1 (duplicate, ignore)
  Not found → store → return 0 (execute)
```

**DJB2 hash:** `h = h * 33 + c` (швидкий, 0 алокацій, достатній простір для 16-слотного ring buffer).

---

## 💾 5. Queen RAM Budget

Повний бюджет RAM Королеви — канон [`03_02 §9`](03_02_Queen_Gateway_Firmware) (з усіма FW.3/E.8-буферами: `lora_rx_ring`, `batch_attest_buffer`, OTA-скаляри). 03_01 — дім лише **Soldier** RAM (§3); Queen-таблиця тут раніше тихо розійшлась із домом (stale pre-FW.3 буфери, неузгоджений підсумок) → зведено до рефа.

---

## ⚡ 6. ISR Map (Апаратні Рефлекси)

### 6.1 Soldier ISR

| Callback | Тригер | Дія | Пріоритет |
|----------|--------|-----|-----------|
| `OnRxDone(payload, size, rssi, snr)` | LoRa RX complete (SX1262) | `memcpy` → volatile buffer, RSSI clamp [-128,127], `lora_rx_flag = 1` | Апаратний |
| `HAL_GPIO_EXTI_Callback(GPIO_PIN_0)` | Piezo EXTI (п'єзодиск) | `vibration_detected = 1` | EXTI Line 0 |
| `HAL_PWR_PVDCallback()` | Vcap < 2.2V | **[ARCH.21]** BKUPWrite packed DR0 (`panic_counter` + `acoustic`) + DR1 (`last_wakeup`) + DR16-DR19 (Lorenz state + magic), Radio.Sleep, Enter STOP2 | NMI-рівень |
| `HAL_ADC_ConvCpltCallback()` | DMA buffer повний (512 семплів) | `audio_ready = 1` | DMA IRQ |

**PVD — аварійний рефлекс смерті [ARCH.21]:**
```c
void HAL_PWR_PVDCallback(void) {
    // [SEC.10] Spakovana DR0: panic_counter в high 16 + acoustic в low 8 біт
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
        ((uint32_t)panic_frame_counter << 16) | (uint32_t)acoustic_events);
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
    Radio.Sleep();
    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
}
```

**Trigger_Emergency_LoRa_TX (Panic Payload + SEC.10 Frame Counter):**
```c
// [SEC.10] Інкрементуємо лічильник panic-кадрів (saturating @ 0xFFFF) ПЕРЕД пакуванням.
if (panic_frame_counter < 0xFFFF) panic_frame_counter++;

panic_payload[7]  = 0xFF;          // Acoustic = 0xFF = насичений лічильник паніки
panic_payload[10] = PANIC_FLAG_BIT; // [FW.29] bit 7 = 1 → однозначний маркер panic
panic_payload[11] = 5;             // TTL = 5 (стандарт 3, паніка 5 — більше стрибків)
// [SEC.10] Counter BE у байтах 14..15 (вільні PAD bytes після firmware_id у 12..13)
panic_payload[14] = (uint8_t)(panic_frame_counter >> 8);
panic_payload[15] = (uint8_t)(panic_frame_counter & 0xFF);
// Persist negайно у DR0 — до Phase 5 могло не дойти при PVD/reset
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0,
    ((uint32_t)panic_frame_counter << 16) | (uint32_t)acoustic_events);
// AES-128-ECB Encrypt → Radio.Send [post-ARCH.42] → 100ms → Radio.Sleep
```

> **[FW.29] Навіщо окремий PANIC_FLAG_BIT?** До FW.29 backend розрізняв паніку лише за `acoustic_events == 0xFF`. Але `0xFF` може означати і реальне насичення кавітаційних подій за тривалий час. `PANIC_FLAG_BIT` у байті 10 (StatusByte, bit 7) є однозначним машинним маркером: у нормальному пакеті він завжди `0` (`lora_payload[10] &= ~PANIC_FLAG_BIT`), у panic-пакеті — завжди `1`.

### 6.2 Queen ISR

| Callback | Тригер | Дія |
|----------|--------|-----|
| `OnRxDone(payload, size, rssi, snr)` | LoRa RX (рівно 16 байт) | RSSI clamp → `LoRa_Rx_Ring_Push` (FIFO 15-slot, FW.3) → лічильник `lora_rx_drops` при переповненні |

Queen не має PVD, EXTI, DMA або IWDG ISR. Мінімальний ISR-footprint + **single-producer ring buffer** дозволяють Queen залишатися "завжди активною" без race conditions і без втрати голосів рою під час 25-секундного CoAP-flush'у (FW.3 — part-1 закрито; повна async UART DMA flush відкрита → [`00_07 §03`](00_07_Action_Plan_Tracker)).

---

## 🔐 7. DID Generation (Народження)

```c
// Виконується ОДИН РАЗ в житті пристрою (якщо DR7 == 0)
uint32_t uid_word0 = *(uint32_t*)(0x1FFF7590); // STM32 factory UID (96 bits)
uint32_t uid_word1 = *(uint32_t*)(0x1FFF7594);
uint32_t uid_word2 = *(uint32_t*)(0x1FFF7598);

uint32_t true_random = 0;
HAL_RNG_GenerateRandomNumber(&hrng, &true_random); // TRNG (теплошумова ентропія)

tree_did = uid_word0 ^ (uid_word1 << 5) ^ (uid_word2 >> 3) ^ true_random;

// [FW.24] HRNG-based fallback: до 3 спроб HRNG замість детермінованої магічної константи
if (tree_did == 0) {
    uint32_t rng_fallback = 0;
    for (int i = 0; i < 3 && rng_fallback == 0; i++) {
        HAL_RNG_GenerateRandomNumber(&hrng, &rng_fallback);
    }
    tree_did = (rng_fallback != 0) ? rng_fallback : (HAL_GetTick() ^ 0x511CEE01);
}

HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR7, tree_did); // Locked forever
```

> **[FW.24] Навіщо змінено fallback?** Стара реалізація використовувала константу `0x511CEE01` — єдине детерміноване значення, яке колізувало б у всіх Солдатів зі зламаним UID і нулевим HRNG. FW.24 вводить три додаткові спроби HRNG: при справному RNG хоч одна дасть ненульовий результат, забезпечуючи унікальний DID навіть при нульовому XOR-результаті UID. Магічна константа залишається лише як останній рядок захисту при повній відмові HRNG.

**Потім:** `POST /api/v1/provisioning/register` — реєструє DID у Rails backend для отримання AES-ключа та прив'язки до Tree-сутності в БД.

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
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);
```

Без цього відновлення всі наступні LoRa-пакети від Soldiers будуть розшифровані неправильно до наступного ребуту Queen.

**HRNG IV Generation — "Wu-Wei" паттерн:**

```c
// [FIX: R-16] Стара вразливість: IV = HAL_GetTick() (детермінований, передбачуваний).
// Нова версія: апаратний TRNG, з fallback XOR-маскою при відмові HRNG.
uint32_t batch_iv[4];

hrng.Instance = RNG;
HAL_RNG_Init(&hrng);                                    // Init безпосередньо перед використанням

for (uint8_t i = 0U; i < 4U; i++) {
    if (HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK) {
        batch_iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL); // Fallback: tick XOR index mask
    }
}

HAL_RNG_DeInit(&hrng);                                  // DeInit одразу після — нульовий струм сну
```

**Чому XOR-маска, а не просто tick?** При відмові HRNG кожен з 4 IV-слів отримує різну маску (`0x00000000`, `0x5A5A5A5A`, `0xB4B4B4B4`, `0x0F0F0F0F`). Це запобігає ситуації де всі 4 слова IV ідентичні навіть при однаковому tick.

---

## 🧪 10. Покриття Host-Based Тестами

Firmware логіка тестується на x86 з GCC (не потребує ARM toolchain):

```bash
make -C firmware/test             # Усі host-based тести (soldier / queen / bio_contract / tinyml / encryption)
make -C firmware/test queen       # Queen-only
make -C firmware/test soldier     # Soldier-only
make -C firmware/test bio_contract # Bio-Contract
make -C firmware/test tinyml      # TinyML pipeline (включно з FW.18 OTA invalid-counter)
make -C firmware/test encryption  # AES encryption
```

**CI:** Firmware тести інтегровані в GitHub Actions (`firmware_test` job у `.github/workflows/ci.yml`).

### Тести Queen

Повна Queen host-test-matrix (вкл. FW.1 Flash-key / FW.20 / FW.20-S2 / FW.27-B) — канон [`03_02 §11`](03_02_Queen_Gateway_Firmware). Дублювати тут означало drift (ця копія відставала від дому).

### Тести Soldier

| Модуль | Тести | Що покривається |
|--------|-------|-----------------|
| Payload Packing | 13 | Всі поля, signed temp, max/zero, pack-unpack roundtrip, reserved=0 |
| DID Generation | 5 | HRNG-based fallback (FW.24), детермінізм, унікальність; magic constant `0x511CEE01` лише як last-resort |
| Mesh Dedup | 10 | 3-slot cache (FW.21), eviction, pingpong scenario, relay decisions (OK/echo/known/ttl_zero) |
| OTA Assembly (Soldier) | 7 | Multi-chunk, duplicate ignore, buffer overflow, total mismatch, bitmap |
| CRC32 | 7 | ISO 3309 known value (`0xCBF43926`), bit flip detection, OTA verify/corrupted |
| Bio-Contract Byte | 8 | All statuses, clamping, full 256-combination roundtrip, `0xFF`=VM error |
| Panic Payload | 6 | DID, acoustic=0xFF marker, TTL=5, zero fields; **[FW.29]** PANIC_FLAG_BIT встановлений у panic, відсутній у звичайному пакеті |
| OnRxDone Boundary | 5 | Normal 16B, 255B accepted, 256B accepted, 257B rejected, 0B rejected |
| Lorenz State Persistence (FW.6) | 9 | RTC DR16-DR19, magic marker, NaN/Inf guard, cold boot |
| Acoustic Saturating Increment (FW.22) | 6 | Нуль, нормальний приріст, 254→255, 255 залишається 255, насичення, atomic snapshot |
| RSSI Clamping | 7 | Нормальні, edge ±128, overflow proof |
| EMA Filter (FW.21) | 10 | Cold start, smoothing (α=0.2), convergence, noise rejection, warmup flag, count saturation, zero inputs, overflow max, RTC save/load, cold boot |
| ADC→mV (FW.50) | 10 | VDDA recovery, pin voltage, 2:1 divider, div-by-zero guards, raw-count≠mV proof (helper `common/adc_convert.h`) |
| [решта] | ~12 | Lorenz state + mesh + misc |

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

def calculate_state(seed, temp, acoustic)  # C bridge — єдина публічна функція
  SilkenNet::BioContract.evaluate_and_pack(seed, temp, acoustic)
end
```

C-код знає **тільки** про `calculate_state` (через `mrb_intern_lit`). Вся логіка всередині `SilkenNet::*` невидима для firmware.

### 11.2 Attractor — Математичне Ядро

**Константи:**

| Константа | Значення | Призначення |
|-----------|----------|-------------|
| `BASE_SIGMA` | `10.0` | Швидкість конвекції (температурний градієнт) |
| `BASE_RHO` | `28.0` | Число Релея (нагрів → конвекція) |
| `BASE_BETA` | `8.0 / 3.0` | Геометрична константа (розсіювання) |
| `DT` | `0.01` | Крок інтегрування Ейлера |
| `ITERATIONS` | `250` | Кількість ітерацій до виходу на траєкторію хаосу |
| `SIGMA_MIN` | `5.0` | Clamp мінімум sigma |
| `SIGMA_MAX` | `30.0` | Clamp максимум sigma |
| `RHO_MIN` | `10.0` | Clamp мінімум rho |
| `RHO_MAX` | `50.0` | Clamp максимум rho |

**Ініціалізація стану (x, y, z) з chaos_seed:**

```ruby
x = ((seed % 1000) / 500.0) - 1.0          # x ∈ [-1.0, 1.0]
y = (((seed >> 4) % 1000) / 500.0) - 1.0   # y ∈ [-1.0, 1.0]
z = (((seed >> 8) % 1000) / 500.0) - 1.0   # z ∈ [-1.0, 1.0]
```

HRNG-seed з кожним пробудженням дає нову початкову точку, роблячи кожну ітерацію унікальною. Але за 250 кроків система **завжди виходить на дивний атрактор Лоренца** — хаотична, але детермінована траєкторія.

**Пертурбація параметрів датчиками:**

```ruby
local_sigma = (BASE_SIGMA + acoustic * 0.1).clamp(SIGMA_MIN, SIGMA_MAX)
local_rho   = (BASE_RHO   + temp    * 0.2).clamp(RHO_MIN,   RHO_MAX)
```

- `acoustic` → σ (скільки "турбуленції" в системі — кавітація посилює хаос)
- `temp` → ρ (температура впливає на тепловий рушій конвекції)
- `BASE_BETA = 8.0/3.0` — незмінний (геометрична постійна ксилемного каналу)

**250 ітерацій Ейлера:**

```ruby
dx = local_sigma * (y - x)
dy = x * (local_rho - z) - y
dz = (x * y) - (BASE_BETA * z)
x += dx * DT
y += dy * DT
z += dz * DT
```

**Повертає:** `z` — інтенсивність конвекції (рух соку у ксилемі). Серверна копія (`app/services/silken_net/attractor.rb`) обчислює те саме для крос-верифікації.

### 11.3 BioContract — Токеноміка та Статуси

**Порогові значення:**

| Константа | Значення | Значення для дерева |
|-----------|----------|---------------------|
| `CRITICAL_Z_MIN` | `2.0` | Нижче → втрата тургору, посуха |
| `CRITICAL_Z_MAX` | `45.0` | Вище → аномальний стрес, втручання |
| `OPTIMAL_Z_TARGET` | `29.0` | Ідеальний стан конвекції (max CO₂ депонування) |

**Логіка `evaluate_and_pack(seed, temp, acoustic)`:**

```ruby
z_val = Attractor.calculate_z_axis(seed, temp, acoustic)

    # Стрес
  status = 1; growth_points = 1
elsif z_val > CRITICAL_Z_MAX   # Аномалія
  status = 2; growth_points = 0
else                           # Гомеостаз
  status = 0
  # [E.63] growth_points = монотонна метаболічна жвавість зі швидкості перезаряду
  # (delta_t), а НЕ |29−z| (та була хаотичним шумом). Формула m(delta_t)→GP +
  # калібрувальні пороги — SSOT 03_04 §4.3 (One-Home, тут не дублюємо).
  growth_points = metabolic_growth_points(delta_t_s)   # 5-bit wire (5..31)
end

# [FW.29-PACK] Layout: [PanicFlag:1 (bit 7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)].
# Status переїхав з bits 7..6 на bits 6..5 для уникнення колізії з bit 7,
# який FW.29 зарезервував під однозначне маркування panic-frame'у.
payload_byte = (status << 5) | growth_points
```

**Reward Formula:** базова нагорода 50, мінус штраф за відхилення від `OPTIMAL_Z_TARGET=29.0`. Wire-значення масштабується ÷2 (для 5-бітного простору 5..31), backend ×2 upscale при unpack для збереження tokenomic invariant.

**Відображення на байт BioContract (байт 10 payload, після FW.29-PACK):**

| z_val | Status | Wire GP | Hex (приклад) |
|-------|--------|---------|---------------|
| < 2.0 | 1 (stress) | 1 | `0x21` |
| > 45.0 | 2 (anomaly) | 0 | `0x40` |
| ≈ 29.0 | 0 (homeostasis) | 25 | `0x19` |
| mruby VM error | 3 (tamper) | 31 (after `& 0x7F`) | `0x7F` |

> **Синхронізація з сервером:** `app/services/silken_net/attractor.rb` обчислює той самий z-val за тими самими константами. Якщо значення розходяться → Dual Computation Integrity Alert. **[FIX: R-11]** Виправлено: `BASE_BETA` уніфіковано як `8.0/3.0` (не `2.666`), sigma/rho clamp синхронізовано з сервером.

---

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

**Принцип:** Тести **не включають** `soldier/main.c` напряму. Натомість вони дублюють (копіюють + адаптують) pure-logic функції в тестовий файл. Це дозволяє:
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

**Дім build-системи прошивки.** До FW.46 закомічченого ARM-build не було — `.elf` збирались зовні (CubeIDE), не відтворювано й не CI-gated. Тепер відтворюваний CMake-крос-компайл того, що ми **володіємо**, живе в репо й гейтиться в CI (`ci.yml › firmware_arm_build`). Повний HAL-лінкований `.elf` — наступний крок (👤, [`00_07` — FW.46](00_07_Action_Plan_Tracker)).

```
firmware/
  CMakeLists.txt              — owned-код (logmel.c) + CMSIS-DSP + size + guarded HAL
  cmake/arm-none-eabi.cmake   — toolchain-file (Cortex-M4F; pin Arm GNU 13.2.Rel1)
  mruby/build_config.rb       — mruby builds (host mrbc / host-min / arm minimal)
  extern/                     — pinned submodules: CMSIS-DSP · CMSIS_6 (Core) · mruby · monocypher
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

**Виміряний footprint** (вперше — ARM-build раніше не існувало):

| Артефакт | Flash (.text) | Static RAM |
|---|---|---|
| mruby core (bytecode-only, `libmruby_core.a`) | ~117 KB | 0 — mruby 4.0.0 ROM-таблиці у `.rodata` |
| logmel.c (наш DSP, `LOGMEL_USE_CMSIS`) | ~6.3 KB | 28 B |
| lorenz_bytecode (mrbc) | ~2.5 KB | 0 |

> mruby ≈ 46% від 256 KB Flash — інherentна ціна за **OTA-оновлюваний bio-contract** (байткод OTA'ється без reflash). Тримати в бюджеті при HAL-інтеграції (+ CMSIS-NN модель, [`00_07` — FW.4](00_07_Action_Plan_Tracker)).

**mruby build-інваріанти** (verified проти `doc/mruby4.0.md`; джерело — `build_config.rb`):
- **double, не float32:** НЕ ставимо `MRB_USE_FLOAT32` (флаг перейменовано з `MRB_USE_FLOAT` у mruby ≥3.0 — [`00_07` — FW.19](00_07_Action_Plan_Tracker)) → `mrb_float` = double, потрібно для DCI numeric parity ([`03_04 §5`](03_04_mruby_Lorenz_Attractor)).
- **NO_BOXING (default):** НЕ вмикати `MRB_WORD_BOXING`/`MRB_NAN_BOXING` на 32-bit — там нема inline-float, кожен double йшов би в heap → GC-thrash на крихітному heap.
- **minimal gembox:** core + лише `mruby-compar-ext` (для `clamp`); core дає `abs`/`round`/`times`. `default-no-stdio` (~254 KB) не влазить у Flash.

**Scope-межа:** §12.4 крос-компілює owned-код і вимірює його розмір. Soldier/Queen `.elf` (`main.c`/`queen/main.c`) залежать від `main.h`/`radio.h` (CubeMX-HAL, поза репо) → лінкуються лише за `-DSILKEN_WITH_HAL=ON` після вендорингу CubeMX-проєкту (👤). Тоді `firmware/scripts/check_ram_budget.sh` дає істинний повний [`00_07` — FW.26](00_07_Action_Plan_Tracker) розмір. C-API mruby для `main.c` у HAL-фазі: `mrb_alloca→mrb_temp_alloc`, `mruby/ext/io.h→mruby/io.h` (4.0.0 renames).

### 12.5 Vendor / dependency pin-policy (FW.47)

**Дім pin-політики зовнішніх залежностей.** FW.46 завендорив CMSIS-DSP/CMSIS_6/mruby як pinned submodules (§12.4); FW.47 — аудит решти vendor-поверхні + єдина політика, щоб «assumed / вставлене вручну» не протікало в білд.

**Конвенція:** кожна firmware-native залежність → **pinned git-submodule `firmware/extern/<dep>` на release-tag** (як §12.4). CubeMX-glue (`*_hal_msp.c`, `main.h`/`radio.h`-config) лишається owned in-repo — submodule тягне лише upstream-драйвери.

| Залежність | Роль | Статус | Pin-план |
|---|---|---|---|
| CMSIS-DSP · CMSIS_6 · mruby | logmel FFT · Core · bio-contract VM | ✅ завендорено (§12.4) | submodule@tag |
| Monocypher | [L1 QATT] software-Ed25519 — підпис CoAP-батчів Queen ([`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)) | ✅ завендорено (2026-06-07) | `extern/monocypher`@4.0.2 (+ optional `monocypher-ed25519` — стандартний SHA-512 EdDSA, parity з ruby `ed25519` gem host-tested) |
| OpenSSL | host-тест crypto (AES/HKDF/HMAC) | system host-dep; НЕ target | host-build, не вендориться |
| mbedTLS | target HMAC-SHA256 / HKDF | 🔴 лише `TODO(FW.30-mbedtls)`, не залінковано | `extern/mbedtls`@tag — [`00_07` — FW.30](00_07_Action_Plan_Tracker) |
| STM32 HAL + CMSIS-Device-WL | HAL · SUBGHZ/SX1262-радіо · CRYP | 🔴 assumed (CubeMX, поза репо); host = `hal_mock.h` | STM32CubeWL@tag — `-DSILKEN_WITH_HAL=ON` |
| CMSIS-NN | TinyML `Run_Inference` | 🔴 ще нема згадок (модель відсутня) | `extern/CMSIS-NN`@tag — [`00_07` — FW.4](00_07_Action_Plan_Tracker) |

> SX1262-радіо = HAL SUBGHZ-периферія (`SUBGHZ_HandleTypeDef`), не окремий Semtech-драйвер → у HAL-submodule, не окрема залежність.

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
- **Inline** `// cppcheck-suppress` з причиною на місці: radio `OnRxDone` (= Semtech `RadioEvents_t.RxDone`, ABI-фіксована сигнатура) і HAL weak-symbol callback'и (`HAL_ADC_ConvCpltCallback`: `const`/перейменування зламали б перекриття слабкого символа).

**Scope:** `firmware/test/` **свідомо виключено** (host-scaffolding — знахідки = const-шум на тест-локалах + навмисні boundary/clamp/overflow-патерни, 0 реальних багів, дослідження 2026-06-07). MISRA C:2012 доступна як advisory (`--misra`, apt `misra.py`-addon, non-gating); ескалація до gating — optional far-future. Контекст — [`00_07` — FW.48](00_07_Action_Plan_Tracker).

### 12.7 QEMU-M4 bit-parity lane — ISA-емуляція замість bench (FW.55)

**Що це:** committed-байткод `lorenz_bytecode.h` виконується реальним **Cortex-M4 код-шляхом** (minimal-gembox `libmruby.a` із `SILKEN_ARM_BUILD`, software-double `__aeabi_d*` — той самий машинний код, що піде на STM32WLE5JC) на `qemu-system-arm -M mps2-an386`, і дамп порівнюється **byte-exact** із host-голденом. Закриває FW.7/FW.19 residual «ARM↔x86 Float drift» до тонкого silicon-confirm (один прогін selftest на платі).

**Чому бітова рівність — правильний гейт:** Lorenz = лише `+−×÷` (correctly-rounded за IEEE 754), VM виконує той самий байткод у тому ж порядку, double на M4F — детермінований software-шлях. Розбіжність = справжня знахідка, не шум. Кейси **зчеплені** (вихід N → вхід N+1, RTC-continuation патерн) — одиничний ULP-дрейф ампліфікується хаосом і не сховається.

**Анатомія (One-Home):**
- `firmware/sim/parity_core.h` — спільний runner (host і ARM компілюють той самий код); краєві піни (temp/acoustic/delta_t/vcap) + LCG-розгортка.
- `firmware/sim/host_main.c` — host-голден; `firmware/sim/qemu_m4/{main,startup,syscalls}.c` + `mps2_an386.ld` — bare-metal нога (CMSDK UART0 → stdout, semihosting-вихід; карта пам'яті СИМУЛЯТОРА, не Солдата).
- `firmware/scripts/qemu_parity.sh` — єдиний вхід (DRY, патерн `cppcheck.sh`): локально без qemu → host+ARM-build і чесний skip; CI з `REQUIRE_QEMU=1` — відсутній qemu = fail.
- CI: крок `[FW.55]` у job `firmware_arm_build` (`ci.yml`) — реюзає вже зібрані mruby-ліби.

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

> **🔄 Дизайн уточнено під час імплементації (FW.21 fallback):** STM32WLE5JC має лише 20 RTC backup регістрів (DR0..DR19). Оригінальна специфікація (DR24-DR26) фізично неможлива. Перша ітерація FW.21 звільнила 6 регістрів через `MESH_DID_CACHE_SIZE` 8→2 (DR8..DR9 mesh, DR10..DR12 EMA). Подальший аналіз показав: `ema_vcap_x10` має фізичний максимум **5500 × 10 = 55 000 ≤ 2¹⁶** і вкладається в **16 біт**, тому ми пакуємо його в low 16 біт DR12, звільняючи DR11 під 3-й mesh-слот. Поточна розкладка:
>
> | DR | Власник |
> |----|---------|
> | DR8, DR9, **DR11** | `recent_mesh_dids[3]` (3 слоти, fallback від 8→3) |
> | DR10 | `ema_delta_t_x100` (full uint32) |
> | **DR12** | `[valid:8 \| count:8 \| ema_vcap_x10:16]` (packed) |
> | DR13..DR15 | резерв для майбутніх FW-задач |

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

**Cross-VBAT поведінка:** при втраті живлення RTC backup domain очищається → `ema_valid != 0x45` на boot → cold-start → 3 цикли warmup перед `EMA_Is_Warmed_Up()`. Споживач (FW.5 Lorenz) у ці 3 цикли мав би працювати з raw значеннями — але передавання EMA у mruby `calculate_state()` ще НЕ виконано (відкладено у задачу FW.5 B+ через потребу в координованому backend апдейті: `SilkenNet::Attractor` mirror, per-tree EMA state на сервері, 50k fuzz-тести Z-divergence < 1%).

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
// Передавання згладжених значень у mruby — задача FW.5.
EMA_Update(delta_t_seconds, vcap_voltage);
```

> ⚠️ Поточна реалізація **тільки** оновлює EMA-стан. Передавання `EMA_Get_*()` у mruby `calculate_state()` — задача FW.5 (Варіант B+).

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

**Dual Computation Integrity (метаболічний канал):** [E.63] FW.5 B+ β-пертурбацію **реверсовано** — raw `delta_t` більше не входить у Z. Wire несе **raw** `delta_t`, а `growth_points` пакуються з **EMA-згладженого** (firmware-internal) → backend **не може** точно перерахувати GP з одного пакета. Тому метаболічний DCI зараз — **структурний** `check_metabolic_divergence!` (wire-GP↔статус conformance, observational; [`04_02`](04_02_Business_Logic_and_Services) / [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor)). Точний stateless `m(wire_dT)==GP` відкладено до **FW.2**, коли wire нестиме EMA `delta_t` (пакет → 24B CCM). Трекер — [`00_07` — E.63](00_07_Action_Plan_Tracker).

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
