## 03_01: Firmware Lifecycle and DMA (Фази 0-5, Watchdog, STOP2)

**Модуль:** 03_01 — Firmware Core Architecture (Soldier & Queen Lifecycles)
**Пов'язані модулі:** [02_04 EDLC Supercapacitor Buffer](02_04_EDLC_Supercapacitor_Buffer) · [03_02 Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) · [03_03 TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) · [03_04 mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) · [03_05 Hardware AES256 and Security](03_05_Hardware_AES256_and_Security)
**Поточний TRL:** 6 (C-код написаний, 112 host-based тестів проходять, SSOT зафіксовано цим документом)
**Цільовий TRL:** 7 (Повна синхронізація логіки мікроконтролера з Wiki; Factory Flashing розблоковано)
**Статус Аудиту:** Reverse Shaping Cycle 1 — документування поточного стану ("як є") без рефакторингу коду

> **⚠️ SSOT Sync:** Цей документ синхронізовано з `firmware/soldier/main.c` та `firmware/queen/main.c` станом на 2026-03-23. Усі 112 host-based тестів проходять (`make -C firmware/test`). Виявлені блокери задокументовані в розділі 🛑.

---

## 🎯 Мета (Objective)

Зафіксувати детермінований життєвий цикл (Main Loop) вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор), переходи між станами сну та апаратні переривання (ISR) мікроконтролера STM32WLE5JC. Документ слугує SSOT для Factory Flashing (масового виробництва) та OTA-розгортання.

> Цей документ **не** рефакторить код. Він фіксує "як є" — включаючи всі відомі ризики та відкриті блокери.

---

## ✅ Статус (Status)

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
| **Host-based Tests (112)** | ✅ Всі проходять (`make -C firmware/test`) |

---

## 🛑 Блокери (Blockers / Needs Action)

> Цей розділ є виходом аудиту "Reverse Shaping". Жодного рефакторингу не виконувалось — тільки виявлення.

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

### 🟢 INFO: Зафіксовані та Виправлені Ризики (Closed)

Наступні ризики виявлено та виправлено безпосередньо в C-коді:

| # | Ризик | Серйозність | Статус |
|---|-------|-------------|--------|
| R-01 | LoRa Collision Storm (100+ дерев одночасно) | 🔴 | ✅ Виправлено: HRNG jitter 0-500ms |
| R-02 | OTA Integrity Gap (запис без CRC) | 🔴 | ✅ Виправлено: CRC32 ISO 3309 |
| R-03 | OTA Buffer Overflow (chunk_idx * size) | 🔴 | ✅ Виправлено: bounds check |
| R-04 | ECB Mode не відновлювався після CBC flush | 🔴 | ✅ Виправлено: ECB restore в Flush та Handle_CoAP |
| R-05 | CIFO Blind Spot (critical trees evicted) | 🟡 | ✅ Виправлено: priority-aware eviction |
| R-06 | RSSI Negation UB (rssi == -128) | 🟡 | ✅ Виправлено: (int16_t) cast |
| R-07 | RSSI Truncation (< -128 dBm) | 🟡 | ✅ Виправлено: clamp [-128, 127] |
| R-08 | mruby Heap Fragmentation | 🟡 | ✅ Виправлено: gc_arena_save/restore |
| R-09 | mruby Exception Handling | 🟡 | ✅ Виправлено: mrb->exc check |
| R-10 | Mesh Ping-Pong (3-slot cache) | 🟡 | ✅ Виправлено: розширено до 8 слотів |
| R-11 | Attractor Sync Drift (8/3 vs 2.666) | 🟠 | ✅ Виправлено: уніфіковано 8.0/3.0 |
| R-12 | OTA Queen Chunk Underflow | 🟠 | ✅ Виправлено: offset < pending_ota_size |
| R-13 | Firmware Version Missing (bytes 12-13) | 🟡 | ✅ Виправлено: FIRMWARE_VERSION_ID |
| R-14 | Queen Health Blind Spot | 🟠 | ✅ Виправлено: DID=0 sentinel |

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
Сценарій А: decrypted_rx_payload[0] == OTA_MARKER (0x99)
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

---

## 🧪 10. Host-Based Test Coverage (112 тестів)

Firmware логіка тестується на x86 з GCC (не потребує ARM toolchain):

```bash
make -C firmware/test         # Всі 112 тестів
make -C firmware/test queen   # Queen-only (59 тестів)
make -C firmware/test soldier # Soldier-only (53 тести)
```

| Модуль | Тести | Що покривається |
|--------|-------|-----------------|
| DJB2 Hash | 7 | Детермінізм, відомі значення, NUL handling, UUID format |
| Dedup Ring | 7 | New/duplicate, ring wrap, eviction, stress 100 |
| CIFO Cache | 13 | Insert, dedup, priority eviction (всі 4 статуси), fallback, edge RSSI |
| Batch Packing | 8 | 21-байтний формат, ендіанність, RSSI -128, round-trip |
| OTA Chunk Builder | 6 | First/last chunk, reassembly, out-of-range |
| RSSI Clamp | 8 | Normal, edge values, overflow proof, int16→int8 truncation |
| Queen Health | 7 | DID=0 sentinel, uptime packing, cache integration, dedup |
| ECB Restoration | 3 | CRYP mode state після CBC→ECB переходу |
| Payload Packing | 13 | Всі поля, signed temp, max/zero, pack-unpack roundtrip |
| DID Generation | 4 | Non-zero guarantee, детермінізм, унікальність |
| Mesh Dedup | 10 | 8-slot cache, eviction, pingpong, relay decisions |
| OTA Assembly | 7 | Multi-chunk, duplicate ignore, buffer overflow, total mismatch |
| CRC32 | 7 | ISO 3309 known value, bit flip detection, OTA verify |
| Bio-Contract Byte | 8 | All statuses, clamping, full 256-combination roundtrip |
| Panic Payload | 4 | DID, marker, TTL, zero fields |

> **Що НЕ покривається тестами:** STOP2 wakeup sequence, IWDG timeout, PVD voltage threshold, реальний Radio.Send/Rx, SIM7070G AT-команди. Ці компоненти потребують Hardware-in-the-Loop (HIL) тестування.

---

## 🔗 11. Посилання

| Ресурс | Опис |
|--------|------|
| `firmware/soldier/main.c` | Повний C-код вузла Soldier |
| `firmware/queen/main.c` | Повний C-код шлюзу Queen |
| `firmware/test/` | Host-based тести (112 тестів) |
| `firmware/bio_contracts/bio_contract.rb` | mruby Lorenz Attractor |
| `docs/FIRMWARE.md` | Скорочений довідник прошивки |
| [03_02_Queen_Gateway_Firmware](03_02_Queen_Gateway_Firmware) | Детальна документація Queen |
| [03_03_TinyML_Acoustic_Inference](03_03_TinyML_Acoustic_Inference) | TinyML класифікатор звуку |
| [03_04_mruby_Lorenz_Attractor](03_04_mruby_Lorenz_Attractor) | Математика Атрактора |
| [03_05_Hardware_AES256_and_Security](03_05_Hardware_AES256_and_Security) | Деталі шифрування та RDP |
| [02_04_EDLC_Supercapacitor_Buffer](02_04_EDLC_Supercapacitor_Buffer) | EBFC та іоністор 0.47F |
