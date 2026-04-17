# 03_01: Життєвий Цикл Прошивки та DMA (Фази 0–5, Watchdog, STOP2)

## 🛠️ Інструментарій Розробки

### STM32CubeIDE

| Аспект | Деталі |
|--------|--------|
| **Призначення** | Повноцінна C/C++ IDE для STM32WLE5JC (ARM Cortex-M4 + SX1262 LoRa) |
| **Включає** | STM32CubeMX — графічний конфігуратор GPIO, тактових дерев, периферії |
| **Порт** | Налаштування GPIO pinout (PA9/PA10 UART, ADC, TIM2 DMA, RNG, CRYP) до отримання плат |
| **Clock Tree** | Конфігурація HSE/LSE для STOP2 ultra-low-power режиму (2.1 µA) |
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
| 4 | Глибина Резервуара (Vcap) | ADC | `Analog → ADC` | **Vrefint Channel** ✓ (одночасно з каналом 2) |
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
# Запуск всіх 137 тестів на x86 (не потрібен ARM toolchain)
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

## 🎯 Мета

Зафіксувати детермінований життєвий цикл (Main Loop) вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор), переходи між станами сну та апаратні переривання (ISR) мікроконтролера STM32WLE5JC. Документ слугує SSOT для Factory Flashing (масового виробництва) та OTA-розгортання.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — C-код написаний, 137 host-based тестів проходять
- **Пов'язані модулі:**
  - EDLC Супераконденсатор → [`02_04_EDLC_Supercapacitor_Buffer`](02_04_EDLC_Supercapacitor_Buffer)
  - Прошивка Королеви → [`03_02_Queen_Gateway_Firmware`](03_02_Queen_Gateway_Firmware)
  - TinyML Акустичний Інференс → [`03_03_TinyML_Acoustic_Inference`](03_03_TinyML_Acoustic_Inference)
  - mruby Атрактор Лоренца → [`03_04_mruby_Lorenz_Attractor`](03_04_mruby_Lorenz_Attractor)
  - Апаратний AES-256 та Безпека → [`03_05_Hardware_AES256_and_Security`](03_05_Hardware_AES256_and_Security)

---

| Компонент | Стан |
|-----------|------|
| **Soldier main loop (Phases 0-5)** | ✅ Реалізовано (`firmware/soldier/main.c`) |
| **Queen main loop (RX → Cache → Flush)** | ✅ Реалізовано (`firmware/queen/main.c`) |
| **DMA Audio Pipeline (TinyML)** | ✅ Реалізовано (TIM2 + ADC DMA + CPU SLEEP) |
| **RTC Backup Domain (16 регістрів)** | ✅ Реалізовано (DR0..DR15, персистентний стан) |
| **Hardware ISR Map** | ✅ Задокументовано (4 рефлекси: RxDone, EXTI, PVD, DMA) |
| **Mesh Anti-Pingpong (8 слотів)** | ✅ Виправлено (розширено з 3 до 8 DR8..DR15) |
| **CIFO Priority-Aware Eviction** | ✅ Виправлено (критичні записи захищені від витіснення) |
| **OTA Integrity (CRC32)** | ✅ Виправлено (ISO 3309 перевірка перед flash write) |
| **AES Key — зашитий у Flash** | 🔴 BLOCKER (hardcoded, не обертається) |
| **AT Command Blocking (2s HAL_Delay)** | 🔴 BLOCKER (Queen сліпа 2 секунди під час CoAP flush) |
| **Starlink Latency Gap** | 🟡 OPEN (HAL_Delay(1000) для CoAP session може бути замало) |
| **Error_Handler без відновлення** | 🟡 OPEN (вимикає IRQ, вічний цикл — немає NVIC_SystemReset) |
| **CMD_DECRYPT_BUF_SIZE розбіжність** | 🟡 OPEN (544 у firmware, 96 у тестах — OTA path не покритий) |
| **Host-based Tests (137)** | ✅ Всі проходять (`make -C firmware/test`) |

---

## 🛑 Блокери

### 🔴 BLOCKER-1: Hardcoded AES-256 Key у Flash-пам'яті

**Статус:** Відкрито. Критичний ризик безпеки для масового виробництва.

**Файли:** `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:65-66`

```c
// Однаковий ключ у ВСІХ вузлах мережі Silken Net
uint32_t aes_key[8] = {0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
                       0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D};
```

**Ризики:**
1. **Єдина точка відмови:** Злам одного Солдата → компроментація всієї мережі.
2. **Неможливість ротації:** Замінити ключ без перепрошивки всіх вузлів неможливо.
3. **Flash читається через JTAG/SWD:** Якщо не активований RDP Level 2 (Readout Protection), ключ тривіально витягується.

**Необхідна дія:**
- Провізіонувати унікальний ключ на кожен пристрій через захищений канал (`POST /api/v1/provisioning/register`) під час Factory Flashing.
- Активувати RDP Level 2 як фінальний крок Factory Flashing (необоротно блокує JTAG).
- Перенести ключ у `FLASH_KEYR`-захищену зону або окремий secure element.
- Реалізувати механізм ротації ключів через OTA (окрема задача `03_05`).

**Блокує:** Factory Flashing, масове виробництво.

---

### 🔴 BLOCKER-2: AT Command Blocking — Queen сліпа 2 секунди

**Статус:** Відкрито. Архітектурна проблема CoAP uplink.

**Файл:** `firmware/queen/main.c:563`

```c
// Queen не може прийняти жодного LoRa-пакета під час цієї паузи
HAL_Delay(2000); // Чекаємо ACK від сервера
```

**Ризики:**
1. SX1262 LoRa FIFO — 256 байтів. При 16-байтних пакетах та 50+ деревах, що прокидаються одночасно, overflow FIFO за 2s гарантований.
2. Втрачені пакети не відновлюються (немає ARQ між Soldier і Queen).
3. Під час пожежі (критична ситуація) Queen може пропустити emergency-пакети від Солдатів саме в цей момент.

**Необхідна дія:**
- Переписати `Flush_Cache_To_Rails()` на UART interrupt-driven (DMA UART + callback).
- Відправку CoAP виконувати асинхронно, не блокуючи головний цикл.
- Альтернатива: другий буфер прийому під час flush (подвійна буферизація).

**Блокує:** Надійність Queen в умовах щільного LoRa-трафіку.

---

### 🔴 BLOCKER-3: Queen UID — статичний рядок у Flash

**Статус:** Відкрито. Блокує масштабування на кілька Queens.

**Файл:** `firmware/queen/main.c:71`

```c
const char queen_uid[] = "QUEEN-001"; // Hardcoded для кожної одиниці
```

**Ризики:**
1. Кожна Queen потребує окремо скомпільованої прошивки — неможливо зробити єдиний бінарний образ для заводського флешингу.
2. При OTA-оновленні Queen UID не зберігається (якщо OTA перезаписує цей регіон Flash).

**Необхідна дія:**
- Зберігати `queen_uid` в окремому захищеному регіоні Flash (наприклад, `FLASH_USER_SECTOR`) або в EEPROM-емуляції через STM32 Flash API.
- Провізіонувати `queen_uid` через той самий `POST /api/v1/provisioning/register` механізм, що і для Soldiers.

**Блокує:** Уніфікований Factory Flashing, масштабування мережі Queens.

---

### 🟡 BLOCKER-4: Starlink Latency Gap

**Статус:** Відкрито. Середня латентність Starlink Direct-to-Cell — 600-2400 ms.

**Файл:** `firmware/queen/main.c:542`

```c
SIM7070_SendATCommand("AT+CCOAPNEW=\"coap://api.silkennet.com:5683\"\r\n", 1000);
```

`HAL_Delay(1000)` після `AT+CCOAPNEW` — timeout для встановлення CoAP-сесії. Для Starlink це може бути недостатньо.

**Необхідна дія:**
- Замінити фіксований `HAL_Delay` на polling UART RX з перевіркою `OK` відповіді від модему.
- Збільшити timeout до 5000ms або реалізувати retry-логіку.

**Блокує:** Стабільність CoAP uplink через Starlink.

---

### 🟡 BLOCKER-5: Error_Handler без механізму відновлення

**Статус:** Відкрито. Системна вразливість при HardFault.

**Файл:** `firmware/soldier/main.c:758`, `firmware/queen/main.c:792`

```c
void Error_Handler(void) {
  __disable_irq();
  while (1) {}  // Вічний цикл — єдиний вихід це фізичний reset або IWDG
}
```

**Ризики:**
1. IWDG врятує Soldier (перезавантаження → дані з RTC). Але IWDG не освіжується всередині `Error_Handler` → ~26 секунд до IWDG reset (залежно від prescaler).
2. Queen **не має IWDG** — при HardFault вона "заморожується" назавжди до фізичного перезапуску.

**Необхідна дія для Queen:**
- Додати IWDG в Queen firmware (навіть при continuous operation це корисна "остання лінія оборони").
- Або в `Error_Handler` явно викликати `NVIC_SystemReset()` перед `while(1)`.

**Блокує:** Autonomous recovery у Production, 24/7 режим роботи.

---

### 🟡 BLOCKER-6: CMD_DECRYPT_BUF_SIZE розбіжність між firmware та тестами

**Статус:** Відкрито. Потенційна прогалина в тестовому покритті.

**Файли:** `firmware/queen/main.c:122` vs `firmware/test/test_queen_logic.c:21`

```c
// queen/main.c — реальний firmware:
#define CMD_DECRYPT_BUF_SIZE 544  // 512 OTA payload + 5 header + 2 CRC + 16 AES padding + 9 margin

// test_queen_logic.c — тест:
#define CMD_DECRYPT_BUF_SIZE  96  // Тільки CMD (актуаторні команди ≤96 байт)
```

**Ризики:**
1. Тестовий файл охоплює тільки CMD-гілку `Handle_CoAP_Command()` (≤96 байт), але не тестує OTA-гілку (≤528 байт).
2. Будь-які граничні умови OTA downlink з великим `aligned` не покриваються unit-тестами.
3. Зміна `CMD_DECRYPT_BUF_SIZE` в одному файлі без синхронізації другого може привести до тихого розбіжності.

**Необхідна дія:**
- Уточнити `CMD_DECRYPT_BUF_SIZE` у тесті або розділити тест на окремі константи `CMD_MAX` та `OTA_MAX`.
- Додати тести для OTA downlink з великим payload (≥512 байт) до `test_queen_logic.c`.

**Блокує:** Повнота тестового покриття OTA downlink.

---

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
| `hcryp` | AES | Апаратний AES-256-ECB (Hardware Crypto Engine) |

**Примітка:** Soldier — єдиний вузол, що має ADC, TIM2, IWDG, RNG та RTC. Queen — не має жодного з них (окрім RNG та AES).

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
│  Phase 4: AES-256-ECB Encrypt → Radio.Send             │
│      [optional] Mesh Relay TX first                     │
│  Phase 4.5: RX Window (only if Vcap > 2800 mV)         │
│      Scenario A: OTA (0x99 marker) → Flash write        │
│      Scenario B: Mesh relay (16 bytes, TTL > 0)         │
│  Phase 5: Save to RTC Backup Domain → STOP2 (2.1 µA)   │
└─────────────────────────────────────────────────────────┘
       ↑ Wake on RTC Alarm або GPIO EXTI (piezo disk)
```

---

### 1.3 Phase 0: IWDG Watchdog Refresh

```c
HAL_IWDG_Refresh(&hiwdg);
```

Перша інструкція кожного циклу. Якщо mruby VM, DMA або будь-який інший блок зависне і цей рядок не виконається протягом IWDG timeout (налаштовується prescaler: типово ~26 секунд), MCU автоматично перезавантажиться. Усі критичні дані зберігаються в RTC Backup Domain.

---

### 1.4 Phase 1: Sensor Acquisition

**Метаболізм (delta_t):**
```c
uint32_t current_time = HAL_GetTick() / 1000;
delta_t_seconds = current_time - last_wakeup_timestamp;
last_wakeup_timestamp = current_time;
```

`delta_t_seconds` — час між пробудженнями в секундах. Відображає швидкість заряду EDLC суперконденсатора (іоністора). Чим швидше заряд → тим активніший фотосинтез → тим здоровіше дерево. Це є первинний біофізичний сигнал для Атрактора Лоренца.

**АЦП (два окремих цикли Start/Poll/Stop):**

```c
// Цикл 1: Температура (внутрішній датчик STM32)
HAL_ADC_Start(&hadc);
HAL_ADC_PollForConversion(&hadc, 10);
internal_temp = HAL_ADC_GetValue(&hadc);
HAL_ADC_Stop(&hadc);

// Цикл 2: Напруга іоністора (канал VREFINT)
HAL_ADC_Start(&hadc);
HAL_ADC_PollForConversion(&hadc, 10);
vcap_voltage = HAL_ADC_GetValue(&hadc);
HAL_ADC_Stop(&hadc);
```

> ⚠️ **Чому два окремих цикли?** STM32 ADC з подвійним каналом (температура + VREFINT) вимагає перемикання між каналами. Роздвоєний Start/Stop запобігає deadlock при прочитанні VREFINT одразу після температурного каналу.

**HRNG (Chaos Seed):**
```c
HAL_RNG_GenerateRandomNumber(&hrng, &chaos_seed);
```

Апаратний генератор випадкових чисел на основі теплового шуму кристала. Подається як `chaos_seed` до Атрактора Лоренца → робить кожну ітерацію унікальною навіть при однакових фізичних умовах.

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
TinyML Inference → ml_event_id + ml_confidence
       ↓
if (ml_confidence > 0.80):
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

Формує 16-байтний payload для AES-256 шифрування:

```
Offset | Size | Field            | Значення
-------|------|------------------|---------------------------
0-3    | 4    | DID              | Tree ID (big-endian uint32)
4-5    | 2    | Vcap             | Напруга іоністора (mV, BE)
6      | 1    | Temp             | Температура кристала (°C, int8)
7      | 1    | Acoustic         | TinyML acoustic events (uint8)
8-9    | 2    | Metabolism       | delta_t_seconds (BE uint16)
10     | 1    | BioContract      | [Status:2 bits | GrowthPoints:6 bits]
11     | 1    | TTL              | Mesh Time-To-Live (initial = 3)
12-13  | 2    | FirmwareVersionID| FIRMWARE_VERSION_ID (BE uint16)
14-15  | 2    | Reserved         | Зарезервовано (нулі)
```

**Байт 10 (BioContract) — результат mruby Атрактора:**
- Біти `[7:6]`: Status → `0`=homeostasis, `1`=stress, `2`=anomaly, `3`=tamper
- Біти `[5:0]`: Growth Points → `0-63` (Proof of Growth)

Після пакування: `acoustic_events = 0` (скидаємо лічильник).

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

> Детальна математика Атрактора Лоренца (σ=10, ρ=28, β=8/3, 250 ітерацій) описана в `03_04_mruby_Lorenz_Attractor`.

---

### 1.8 Phase 4: AES-256-ECB Encrypt + LoRa TX

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

---

### 1.9 Phase 4.5: RX Window (OTA + Mesh)

Відкривається **тільки** якщо `vcap_voltage > 2800 mV` (достатньо енергії).

```
Radio.Rx(500ms) → Максимум 600ms очікування
       ↓
[якщо lora_rx_flag == 1]
       ↓
AES-256-ECB Decrypt → decrypted_rx_payload[]
       ↓
Сценарій А: decrypted

_rx_payload[0] == OTA_MARKER (0x99)
  → Валідація мінімального розміру (>= 6 байт)
  → chunk_idx, total_chunks (big-endian)
  → Bounds check: offset + chunk_size <= 1024
  → Dedup check: ota_chunk_received[chunk_idx]
  → memcpy → ota_buffer[]
  → Якщо всі чанки → CRC32 verify → Write to Flash → NVIC_SystemReset()

Сценарій Б: incoming_lora_size == 16 (Mesh Relay)
  → TTL > 0?
  → incoming_did == tree_did? → break (власне відлуння)
  → recent_mesh_dids[8] check (anti-pingpong)
  → Decrement TTL → Re-encrypt → store mesh_relay_payload
  → has_mesh_relay = 1
```

---

### 1.10 Phase 5: STOP2 Deep Sleep (2.1 µA)

```c
// 1. Зберігаємо стан у RTC Backup Domain (16 регістрів)
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0, acoustic_events);
HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR1, last_wakeup_timestamp);
// ... DR2..DR15 (mesh state)

// 2. Відключаємо периферію для мінімального споживання
HAL_RNG_DeInit(&hrng);
__HAL_RCC_CRYP_CLK_DISABLE();

// 3. Зупиняємо SysTick та входимо в STOP2
HAL_SuspendTick();
HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);
HAL_ResumeTick(); // Виконується після пробудження

// 4. Відновлюємо периферію після wake
HAL_RNG_Init(&hrng);
__HAL_RCC_CRYP_CLK_ENABLE();
HAL_CRYP_Init(&hcryp);
```

**Джерела пробудження:**
- RTC Alarm (основний — за розкладом заряду іоністора)
- GPIO EXTI на GPIO_PIN_0 (п'єзодиск — вібрація/звук)
- PVD Callback (напруга < 2.2V — аварійне відключення, не пробудження)

---

## 🗺️ 2. Soldier RTC Backup Register Map (DR0..DR15)

RTC Backup Domain не скидається при STOP2 та більшості реботів (окрім повного знеструмлення або `HAL_RTCEx_BKUPWrite` з нулями).

| Регістр | Змінна | Тип | Опис |
|---------|--------|-----|------|
| `DR0` | `acoustic_events` | uint16 | Лічильник акустичних подій (кавітація) |
| `DR1` | `last_wakeup_timestamp` | uint32 | Час останнього пробудження (HAL_GetTick/1000) |
| `DR2` | `has_mesh_relay` | uint8 | Прапорець: 1 = є пакет для ретрансляції |
| `DR3` | `mesh_relay_payload[0..3]` | uint32 | Транзитний пакет, байти 0-3 |
| `DR4` | `mesh_relay_payload[4..7]` | uint32 | Транзитний пакет, байти 4-7 |
| `DR5` | `mesh_relay_payload[8..11]` | uint32 | Транзитний пакет, байти 8-11 |
| `DR6` | `mesh_relay_payload[12..15]` | uint32 | Транзитний пакет, байти 12-15 |
| `DR7` | `tree_did` | uint32 | DID дерева (записується ОДИН РАЗ при народженні) |
| `DR8` | `recent_mesh_dids[0]` | uint32 | Anti-pingpong DID cache, слот 0 |
| `DR9` | `recent_mesh_dids[1]` | uint32 | Anti-pingpong DID cache, слот 1 |
| `DR10` | `recent_mesh_dids[2]` | uint32 | Anti-pingpong DID cache, слот 2 |
| `DR11` | `recent_mesh_dids[3]` | uint32 | Anti-pingpong DID cache, слот 3 |
| `DR12` | `recent_mesh_dids[4]` | uint32 | Anti-pingpong DID cache, слот 4 |
| `DR13` | `recent_mesh_dids[5]` | uint32 | Anti-pingpong DID cache, слот 5 |
| `DR14` | `recent_mesh_dids[6]` | uint32 | Anti-pingpong DID cache, слот 6 |
| `DR15` | `recent_mesh_dids[7]` | uint32 | Anti-pingpong DID cache, слот 7 |

> **DR7 — Незмінний DID:** Записується один раз при першому старті (`tree_did == 0`). Якщо `tree_did != 0` при наступних стартах, запис пропускається. Це гарантує унікальність ідентифікатора навіть після OTA-ребуту.

---

## 💾 3. Soldier RAM Budget (~5 KB з 64 KB SRAM)

| Змінна | Тип | Розмір | Призначення |
|--------|-----|--------|-------------|
| `aes_key[8]` | `uint32_t` | 32 B | AES-256 мережевий ключ |
| `lora_payload[16]` | `uint8_t` | 16 B | Вихідний payload перед шифруванням |
| `encrypted_payload[16]` | `uint8_t` | 16 B | Зашифрований payload для Radio.Send |
| `mesh_relay_payload[16]` | `uint8_t` | 16 B | Транзитний зашифрований mesh-пакет |
| `recent_mesh_dids[8]` | `uint32_t` | 32 B | Кеш DID для anti-pingpong |
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

**Queen НЕ має:** ADC, TIM2, IWDG, RTC — на відміну від Soldier.

### 4.2 Загальний Lifecycle

```
Init → Radio.Init → Radio.Rx(0xFFFFFF) [infinite]
┌─────────────────────────────────────────────────────────┐
│  if lora_rx_flag == 1:                                  │
│    1. AES-256-ECB Decrypt (16 bytes)                   │
│    2. OTA Reflex Shot (if ota_is_active)               │
│    3. Extract sender DID (bytes 0-3)                   │
│    4. Process_And_Cache_Data(DID, payload, RSSI)       │
│    5. lora_rx_flag = 0 → Radio.Rx(0xFFFFFF)           │
│                                                         │
│  if cache_count >= 45 OR timer >= 1hour + jitter:      │
│    Inject Queen Health Sentinel (DID=0x00000000)       │
│    Flush_Cache_To_Rails() → CoAP PUT (AES-256-CBC)     │
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
3. AES-256-CBC encrypt з HRNG IV (prepend IV як перші 16 байт)
4. `AT+CCOAPNEW` → `AT+CCOAPSEND` (hex-кодований) → `HAL_Delay(2000)` → `AT+CCOAPDEL`
5. **Restore ECB mode** для LoRa-трафіку (критично!)

**Queen Sentinel Packet (DID = 0x00000000):**

| Байти | Поле | Значення |
|-------|------|---------|
| 0-3 | DID | `0x00000000` (sentinel, "це Queen") |
| 4-5 | Vcap → Uptime | `HAL_GetTick() / 1000` (uint16, wraps ~65s) |
| 7 | Acoustic → Cache Load | `cache_count` (кількість дерев у кеші) |
| 10 | BioContract → Health | `min(cache_count, 63)` |

### 4.5 OTA Reflex Shot (Broadcast до Soldiers)

**Механізм:** Soldier слухає ефір 500ms після власного TX. Queen, отримавши пакет від Soldier, **миттєво** відповідає OTA-чанком.

```
Queen OnRxDone ISR → lora_rx_flag = 1
       ↓
Main loop: decrypt → if ota_is_active:
  Build OTA chunk (16 bytes):
    [0x99][chunk_idx_hi][chunk_idx_lo][total_hi][total_lo][bytecode:11]
  AES-256-ECB Encrypt → Radio.Send(16)
  HAL_Delay(60) → next_chunk_idx++
```

Chunk-розмір для LoRa OTA: **11 байт** корисного коду (з 16-байтного AES-блоку вираховуємо 5 байт заголовку).

### 4.6 CoAP Downlink → OTA RAM Assembly

Queen отримує великі OTA-пакети від Rails через CoAP (`Handle_CoAP_Command`):

```
Rail CoAP PUT: [IV:16][CBC_encrypted: [0x99][chunk_idx:2][total:2][bytecode:≤512][CRC:2]]
       ↓
Handle_CoAP_Command():
  AES-256-CBC Decrypt (з IV з перших 16 байт)
  Restore ECB mode
  OTA_MARKER detected (0x99):
    chunk_index, total_chunks (big-endian)
    Bitmap dedup: ota_chunk_bitmap
    memcpy → pending_ota_bytecode[chunk_index * 512]
    ota_chunks_received++
    if all received → ota_is_active = 1 → LoRa broadcast starts
```

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

## 💾 5. Queen RAM Budget (~3.7 KB з 64 KB SRAM)

| Змінна | Тип | Розмір | Призначення |
|--------|-----|--------|-------------|
| `aes_key[8]` | `uint32_t` | 32 B | AES-256 ключ (ідентичний Soldiers) |
| `forest_cache[50]` | `EdgeCache` | 1150 B | CIFO кеш (50 × 23 байт) |
| `binary_batch_buffer[2048]` | `uint8_t` | 2048 B | CoAP batch buffer |
| `at_tx_buffer[256]` | `char` | 256 B | AT-команди для SIM7070G |
| `cmd_dedup_ring[16]` | `uint32_t` | 64 B | Idempotency hash ring |
| `cmd_decrypt_buf[544]` | `uint8_t` | 544 B | Decrypt buffer (CMD + OTA) |
| `pending_ota_bytecode[8192]` | `uint8_t` | 8192 B | OTA assembly RAM |
| **Всього** | | **~12 KB** | |

> ⚠️ `pending_ota_bytecode[8192]` — найбільший буфер. При одночасному OTA та активному LoRa-трафіку пікове споживання RAM ~12 KB (з 64 KB доступних). Залишок (~52 KB) — стек, HAL структури, LoRa driver.

---

## ⚡ 6. ISR Map (Апаратні Рефлекси)

### 6.1 Soldier ISR

| Callback | Тригер | Дія | Пріоритет |
|----------|--------|-----|-----------|
| `OnRxDone(payload, size, rssi, snr)` | LoRa RX complete (SX1262) | `memcpy` → volatile buffer, RSSI clamp [-128,127], `lora_rx_flag = 1` | Апаратний |
| `HAL_GPIO_EXTI_Callback(GPIO_PIN_0)` | Piezo EXTI (п'єзодиск) | `vibration_detected = 1` | EXTI Line 0 |
| `HAL_PWR_PVDCallback()` | Vcap < 2.2V | BKUPWrite DR0, Radio.Sleep, Enter STOP2 | NMI-рівень |
| `HAL_ADC_ConvCpltCallback()` | DMA buffer повний (512 семплів) | `audio_ready = 1` | DMA IRQ |

**PVD — аварійний рефлекс смерті:**
```c
void HAL_PWR_PVDCallback(void) {
    HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR0, acoustic_events); // Рятуємо найважливіше
    Radio.Sleep();                                              // Не витрачати енергію
    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);               // Кома до відновлення напруги
}
```

**Trigger_Emergency_LoRa_TX (Panic Payload):**
```c
panic_payload[7] = 0xFF;  // Acoustic = 0xFF = panic marker
panic_payload[11] = 5;    // TTL = 5 (стандарт 3, паніка 5 — більше стрибків)
// AES-256-ECB Encrypt → Radio.Send → 100ms → Radio.Sleep
```

### 6.2 Queen ISR

| Callback | Тригер | Дія |
|----------|--------|-----|
| `OnRxDone(payload, size, rssi, snr)` | LoRa RX (рівно 16 байт) | RSSI clamp → memcpy → `lora_rx_flag = 1` |

Queen не має PVD, EXTI, DMA або IWDG ISR. Мінімальний ISR-footprint дозволяє Queen залишатися "завжди активною" без ризику race conditions між перериваннями.

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

if (tree_did == 0) tree_did = 0x511CEE01; // Non-zero guarantee

HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR7, tree_did); // Locked forever
```

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

| Шлях | Алгоритм | Режим | IV |
|------|-----------|-------|----|
| Soldier ↔ Queen (LoRa) | AES-256 | ECB | N/A (єдиний 16-байтний блок) |
| Queen → Rails (CoAP batch) | AES-256 | CBC | HRNG-generated (prepended до ciphertext) |
| Rails → Queen (CoAP commands) | AES-256 | CBC | Prepended у CoAP payload |

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

## 🧪 10. Покриття Host-Based Тестами (137 тестів)

Firmware логіка тестується на x86 з GCC (не потребує ARM toolchain):

```bash
make -C firmware/test         # Всі 137 тестів
make -C firmware/test queen   # Queen-only (79 тестів)
make -C firmware/test soldier # Soldier-only (58 тестів)
```

### Тести Queen (79)

| Модуль | Тести | Що покривається |
|--------|-------|-----------------|
| DJB2 Hash | 7 | Детермінізм, відомі значення (`djb2("a")=0x2B606`), NUL handling, UUID format |
| Dedup Ring | 7 | New/duplicate, ring wrap, eviction, stress 100 |
| CIFO Cache | 13 | Insert, dedup, priority eviction (всі 4 статуси), fallback, edge RSSI, UID=0 |
| Batch Packing | 8 | 21-байтний формат, ендіанність, RSSI -128, round-trip, cache clear |
| OTA Chunk Builder | 6 | First/last chunk, reassembly, out-of-range index |
| OTA Assembly CoAP | 12 | Single/multi-chunk, full 512-chunk, bounds overflow, invalid marker, zero total, duplicate dedup, bitmap reset, size tracking, out-of-order |
| RSSI Clamp | 8 | Normal, edge ±128, overflow proof, int16→int8 truncation demo |
| Queen Health | 7 | DID=0 sentinel, uptime packing, cache integration, dedup, batch |
| ECB Restoration | 3 | CRYP mode state після CBC→ECB переходу (Flush та Handle_CoAP) |
| HRNG IV Generation | 5 | Words filled, 16-byte size, RNG instance set, power management (DeInit), not tick-based |
| CBC Command Decryption | 3 | ECB restored after CMD decrypt, CBC during decrypt, both transitions in sequence |

### Тести Soldier (58)

| Модуль | Тести | Що покривається |
|--------|-------|-----------------|
| Payload Packing | 13 | Всі поля, signed temp, max/zero, pack-unpack roundtrip, reserved=0 |
| DID Generation | 4 | Non-zero guarantee (`0x511CEE01`), детермінізм, унікальність |
| Mesh Dedup | 10 | 8-slot cache, eviction, pingpong scenario, relay decisions (OK/echo/known/ttl_zero) |
| OTA Assembly (Soldier) | 7 | Multi-chunk, duplicate ignore, buffer overflow, total mismatch, bitmap |
| CRC32 | 7 | ISO 3309 known value (`0xCBF43926`), bit flip detection, OTA verify/corrupted |
| Bio-Contract Byte | 8 | All statuses, clamping, full 256-combination roundtrip, `0xFF`=VM error |
| Panic Payload | 4 | DID, acoustic=0xFF marker, TTL=5, zero fields |
| OnRxDone Boundary | 5 | Normal 16B, 255B accepted (old off-by-one fix), 256B accepted, 257B rejected, 0B rejected |

> **Що НЕ покривається тестами:** STOP2 wakeup sequence, IWDG timeout, PVD voltage threshold, реальний Radio.Send/Rx, SIM7070G AT-команди. Ці компоненти потребують Hardware-in-the-Loop (HIL) тестування.

---

## 🌿 11. Bio-Contract Specification (`firmware/bio_contracts/bio_contract.rb`)

Цей файл є мостом між C-ядром та математикою Атрактора Лоренца. Компілюється командою `mrbc` у байт-код, який:
- Вбудовується у `lorenz_bytecode[]` при першій компіляції firmware
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
  deviation = (OPTIMAL_Z_TARGET - z_val).abs
  reward = 50 - deviation.to_i
  growth_points = [reward, 10].max   # Мінімум 10, якщо reward < 10
end

growth_points = growth_points.clamp(0, 63)  # 6-bit max
payload_byte = (status << 6) | growth_points
```

**Reward Formula:** базова нагорода 50, мінус штраф за відхилення від `OPTIMAL_Z_TARGET=29.0`. Максимум 50 балів (при z=29.0). Мінімум 10 балів (при гомеостазі з великим відхиленням).

**Відображення на байт BioContract (байт 10 payload):**

| z_val | Status | Growth Points | Hex (приклад) |
|-------|--------|---------------|---------------|
| < 2.0 | 1 (stress) | 1 | `0x41` |
| > 45.0 | 2 (anomaly) | 0 | `0x80` |
| ≈ 29.0 | 0 (homeostasis) | 50 | `0x32` |
| mruby VM error | 3 (tamper) | 63 | `0xFF` |

> **Синхронізація з сервером:** `app/services/silken_net/attractor.rb` обчислює той самий z-val за тими самими константами. Якщо значення розходяться → Dual Computation Integrity Alert. **[FIX: R-11]** Виправлено: `BASE_BETA` уніфіковано як `8.0/3.0` (не `2.666`), sigma/rho clamp синхронізовано з сервером.

---

## 🛠️ 12. Тестова Інфраструктура (`firmware/test/`)

### 12.1 Архітектура x86 Тестів

Тести компілюються GCC на x86/x64 без ARM toolchain. Ключовий компонент — `hal_mock.h`:

```
firmware/test/
  hal_mock.h          — Мінімальні HAL stubs для компіляції без STM32 HAL
  test_soldier_logic.c — 58 тестів, pure-logic функції з soldier/main.c
  test_queen_logic.c   — 79 тестів, pure-logic функції з queen/main.c
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

> ⚠️ **Наслідок:** Тести CIFO eviction, OTA dedup, batch packing, ECB restoration — всі перевіряють **структурну логіку**, але не криптографічну коректність. Реальне AES-256 тестування потребує HIL з апаратним AES модулем.

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

---

## 🔗 13. Посилання

| Ресурс | Опис |
|--------|------|
| `firmware/soldier/main.c` | Повний C-код вузла Soldier |
| `firmware/queen/main.c` | Повний C-код шлюзу Queen |
| `firmware/bio_contracts/bio_contract.rb` | mruby Lorenz Attractor bio-contract |
| `firmware/test/hal_mock.h` | HAL stubs для x86 тестів |
| `firmware/test/test_soldier_logic.c` | 58 Soldier тестів |
| `firmware/test/test_queen_logic.c` | 79 Queen тестів |
| `firmware/test/Makefile` | Build system для host-based тестів |
| `docs/FIRMWARE.md` | Скорочений довідник прошивки |
| [03_02_Queen_Gateway_Firmware](03_02_Queen_Gateway_Firmware) | Детальна документація Queen |
| [03_03_TinyML_Acoustic_Inference](03_03_TinyML_Acoustic_Inference) | TinyML класифікатор звуку |
| [03_04_mruby_Lorenz_Attractor](03_04_mruby_Lorenz_Attractor) | Математика Атрактора |
| [03_05_Hardware_AES256_and_Security](03_05_Hardware_AES256_and_Security) | Деталі шифрування та RDP |
| [02_04_EDLC_Supercapacitor_Buffer](02_04_EDLC_Supercapacitor_Buffer) | EBFC та іоністор 0.47F |
