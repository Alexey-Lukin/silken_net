## 02_05: Queen Hardware & Starlink Uplink (The Bridge)

**Модуль:** 02_05 — Queen Gateway Hardware: STM32WLE5JC + SIM7070G + Starlink Direct-to-Cell / Starlink Mini  
**Пов'язані модулі:** [02_03 BQ25570 MPPT](02_03_BQ25570_MPPT_Nano_Power) · [02_04 EDLC Supercapacitor](02_04_EDLC_Supercapacitor_Buffer) · [03_02 Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) · [03_05 Hardware AES256 and Security](03_05_Hardware_AES256_and_Security) · [04_02 Business Logic and Services](04_02_Business_Logic_and_Services)  
**Поточний TRL:** 5 (Схеми/прототипи існують, прошивка готова; Phase 2.5 Starlink DTC підтверджено через Київстар)  
**Цільовий TRL:** 6 (Повна прозорість апаратної архітектури та енергетичного бюджету шлюзу)  
**Статус Аудиту:** Reverse Shaping Cycle 1 + нотатка N1 інтегрована (2026-03-24).

> **⚠️ SSOT Sync:** Цей документ синхронізовано з `firmware/queen/main.c`, `docs/HARDWARE.md` та поточним станом апаратної архітектури. BLOCKER-1 переформульовано: Starlink Direct-to-Cell (DTC) через Київстар **не потребує** окремого Starlink-термінала або додаткового модему — SIM7070G є достатнім для Phase 2.5.

---

## 🎯 Мета (Objective)

Зафіксувати **повну апаратну архітектуру** вузла "Королева" (Queen Gateway) — єдиного фізичного моста між автономною LoRa-мережею лісу та глобальним інтернетом. Документ відповідає на три критичних питання:

1. Як **фізично** з'єднані MCU (STM32WLE5JC), стільниковий модем (SIM7070G) та Starlink?
2. Чи **вистачає** пікового струму від батареї для SIM7070G (до 2А в стрибках)?
3. Яка **добова потреба у ватт-годинах** для цілодобової роботи Королеви в різних фазах?

> Цей документ фіксує "як є" — включаючи всі відомі ризики, невирішені архітектурні питання та підтверджені специфікації компонентів.

---

## ✅ Статус (Status)

| Компонент | Стан |
|-----------|------|
| **MCU (STM32WLE5JC) + LoRa RX 868 МГц** | ✅ Реалізовано (`firmware/queen/main.c`) |
| **SIM7070G UART1 драйвер (AT-команди CoAP)** | ✅ Реалізовано (UART1, 115200 baud) |
| **AES-256-CBC шифрування батча перед TX** | ✅ Реалізовано (апаратний CRYP модуль) |
| **CIFO Cache (50 записів × 21 байт)** | ✅ Реалізовано (`forest_cache[]`) |
| **Flush кожну годину з HRNG jitter (0–60 сек)** | ✅ Реалізовано (`FLUSH_INTERVAL_MS = 3600000`) |
| **OTA downlink від Rails через CoAP → LoRa broadcast** | ✅ Реалізовано (`Handle_CoAP_Command`) |
| **Джерело живлення: Сонячна панель + MPPT + LiFePO4** | ✅ Архітектурно визначено (BOM — нижче) |
| **Phase 2.5: Starlink DTC через Київстар (SIM7070G)** | ✅ **ПІДТВЕРДЖЕНО** — термінал Starlink не потрібен |
| **Phase 3: STM32WLE5JC → Starlink Mini TCP/IP міст** | 🔴 BLOCKER (тільки для Phase 3 з терміналом) |
| **SIM7070G пікові струми: BMS валідовано** | 🟡 OPEN (2А пік не підтверджений BMS-специфікацією) |
| **Зимовий енергетичний баланс (Phase 3 Starlink Mini)** | 🔴 BLOCKER (дефіцит при 10–15% інсоляції) |
| **Конкретна модель MPPT-контролера** | 🟡 OPEN (серія не зафіксована в SSOT) |
| **Теплове управління в IP67 корпусі** | 🟡 OPEN (тепловий бюджет не розрахований) |
| **Узгодження найменування модему (SIM7000G vs SIM7070G)** | 🔴 BLOCKER (розбіжність wiki vs firmware) |

---

## 🛑 Блокери (Blockers / Needs Action)

> Виявлено під час апаратного аудиту "Reverse Shaping". Статус BLOCKER-1 оновлено після підтвердження Starlink DTC через Київстар (нотатка N1).

---

### ⚡ BLOCKER-1 → ПЕРЕКЛАСИФІКОВАНО: Starlink DTC (Phase 2.5) vs Starlink Mini (Phase 3)

**Статус:** Частково вирішено для Phase 2.5. Відкрито для Phase 3.

#### Що підтверджено (Phase 2.5 — Starlink Direct-to-Cell через Київстар)

**Starlink Direct-to-Cell (DTC)** — це сервіс SpaceX, що дозволяє LEO-супутникам Starlink безпосередньо обслуговувати стандартні стільникові пристрої через протоколи LTE-M / NB-IoT. **Київстар є партнерським оператором** для DTC в Україні.

**Ключовий висновок:** SIM7070G із SIM-картою Київстар може підключатися до мережі через Starlink DTC **без будь-якого додаткового Starlink-термінала або окремого Starlink-модему**. З точки зору прошивки `firmware/queen/main.c` — нічого не змінюється. Ті самі AT-команди, той самий UART1, той самий CoAP-код.

```
[Ліс — без LTE-вишок]
      │
      ▼
STM32WLE5JC ─[UART1 AT]─▶ SIM7070G (Київстар SIM)
                                │
                                │ LTE-M / NB-IoT радіо
                                ▼
                     🛰️ Starlink LEO Satellite (DTC)
                                │
                                │ IP backhaul
                                ▼
                     [api.silkennet.com:5683 CoAP]
```

**Що це означає для фаз розгортання:**

| Фаза | Підключення | Starlink-термінал | Зміни в прошивці |
|------|-------------|-------------------|------------------|
| **Phase 1** | LTE-M через наземні вишки Київстар | ❌ Не потрібен | — |
| **Phase 2.5** ⬅️ **НОВА** | LTE-M через Starlink DTC (Київстар) | ❌ Не потрібен | — |
| **Phase 3** | Starlink Mini (термінал, Ethernet/WiFi) | ✅ Потрібен | TCP/IP co-proc. (ESP32-S3 або SIM8200G-M2) |

**Практичне значення:** Phase 2.5 дозволяє покрити лісові масиви поза зоною LTE-вишок **вже зараз**, без апаратних змін і без додаткових витрат на термінал ($599). Єдина умова — SIM-карта Київстар з підтримкою DTC.

**Перевірка покриття DTC:**
- Зайди на [Starlink Availability Map](https://www.starlink.com/map) → фільтр "Direct to Cell"
- Або запитай Київстар: чи активовано DTC для корпоративних SIM у зоні Черкаський бір / Канівські гори

#### Що залишається відкритим (Phase 3 — Starlink Mini з терміналом)

Для ультра-віддалених локацій (Амазонія, Тайга, Африка) де DTC може бути недоступний або потрібна більша пропускна здатність — Starlink Mini (фізичний термінал) залишається Phase 3.

STM32WLE5JC не має TCP/IP стеку → потрібна проміжна ланка:

**Варіант А: ESP32-S3 як WiFi-coprocessor (анонсований у Wiki)**
```
STM32WLE5JC ─[UART AT]─▶ ESP32-S3 ─[WiFi 802.11n]─▶ Starlink Mini
                           (TCP/IP stack, WiFi AP mode)
```
- Drawback: ESP32-S3 ~80–240 мА → ~300–900 мВт додаткового споживання
- **Прошивка ESP32-S3 відсутня в `firmware/`** — потрібна розробка

**Варіант Б: Модем SIM8200G-M2 з інтегрованим WiFi**
```
STM32WLE5JC ─[UART AT]─▶ SIM8200G-M2 ─[WiFi]─▶ Starlink Mini
```
- Один UART-інтерфейс, спрощена схема. Дорожчий компонент.

**Необхідна дія (Phase 3):**
- Прийняти архітектурне рішення: ESP32-S3 або SIM8200G-M2
- Описати рішення в `03_02_Queen_Gateway_Firmware` та оновити апаратну схему
- Прошивку для co-processor додати в `firmware/` перед Phase 3 деплоєм

**Блокує:** Лише Phase 3 (Planetary Scale). Phase 1 та Phase 2.5 — не блоковані.

---

### 🔴 BLOCKER-2: Зимовий Енергетичний Дефіцит (Phase 3 Starlink Mini)

**Статус:** Відкрито. Критичний ризик автономності Королеви взимку при використанні Starlink Mini.

> ⚠️ Phase 2.5 (DTC) цей блокер **не зачіпає** — SIM7070G у LTE-M режимі споживає ~370 мВт TX burst, а не 20–40 Вт.

**Розрахунок:**

| Параметр | Phase 1/2.5 (SIM7070G) | Phase 3 (Starlink Mini) |
|----------|------------------------|------------------------|
| Споживання MCU (Continuous RX) | 7 мА × 3.3V = 23 мВт | 23 мВт |
| Споживання модему (idle) | ~10 мА × 3.7V = 37 мВт | ~1 мА (WiFi idle) |
| Пік під час TX (1×/годину) | 200 мА × 3.7V = 0.74 Вт | 20–40 Вт (Starlink) |
| Тривалість TX на добу | 5 сек × 24 = 120 сек | 2–3 хв × 24 = 1.2 год |
| **Добова потреба** | **~3.2 Вт·год/добу** | **~44 Вт·год/добу** |

**Бюджет сонячної панелі (50W Monocrystalline):**

| Умови | Вироблення |
|-------|-----------|
| Літо, чисте небо | 6 год × 50W × 80% = 240 Вт·год/добу ✅ |
| Зима, відкрите місце | 3 год × 50W × 80% = 120 Вт·год/добу ✅ |
| **Зима, хвойний ліс (10–15% інсоляції)** | **3 год × 50W × 12.5% = 18.75 Вт·год/добу** |

**Висновок (зима, Phase 1/2.5):** 18.75 Вт·год генерації vs 3.2 Вт·год споживання → **профіцит +15.5 Вт·год/добу ✅**

**Висновок (зима, Phase 3 Hard OFF):** 18.75 Вт·год vs ~44 Вт·год → дефіцит ~25 Вт·год → автономність 7.7 днів на LiFePO4 12V/20Ah.

**Необхідні дії (Phase 3):**
- Або збільшити батарею до 40Ah (→ 15 днів автономності)
- Або скоротити Starlink duty cycle до 1 хв/годину → ~9 Вт·год/добу (профіцит ✅)
- Або встановити 100W сонячну панель

**Блокує:** Лише Phase 3. Розрахунок Unit Economics (07_02).

---

### 🔴 BLOCKER-3: Розбіжність найменування модему (SIM7000G vs SIM7070G)

**Статус:** Відкрито. Блокер для закупівлі обладнання та BOM.

| Джерело | Модель модему |
|---------|--------------|
| Wiki `02_05` (до аудиту) | **SIM7000G** |
| `firmware/queen/main.c:53` (коментар) | **SIM7070G** |
| `firmware/queen/main.c:206` AT-команди | `AT+CNMP=38` (LTE-M-специфічна, SIM7070G) |

**SIM7000G vs SIM7070G — різні пристрої:**

| Характеристика | SIM7000G | SIM7070G |
|---------------|---------|---------|
| Форм-фактор | LCC68 | LCC68 (сумісний) |
| LTE-M / NB-IoT | ✅ | ✅ |
| GPS | ✅ | ✅ |
| Пікове споживання TX | ~500 мА (LTE-M) | ~400 мА (NB-IoT peak) |
| max TX power | 23 dBm | 23 dBm |

**Необхідна дія:**
- Фізично перевірити маркування на прототипі модему
- Привести wiki, BOM та коментарі прошивки до єдиного найменування
- Уточнити пікові струми відповідно до фінального вибору

**Блокує:** BOM закупівля, Hardware Security Audit.

---

### 🟡 BLOCKER-4: Пікові струми SIM7070G — BMS не специфікований

**Статус:** Відкрито.

SIM7070G у режимі LTE-M TX може споживати імпульсно до **2A** пікового значення. BMS (Battery Management System) не специфікований в поточному BOM.

- **BMS:** захист від перетоку має бути ≥ 5А (з 2.5× запасом)
- **Провідники:** AWG16 або AWG18 для L < 30 см
- **MPPT:** Victron SmartSolar 75/10 (вихідний струм 10А > 2А ✅), але модель не зафіксована в BOM

**Необхідна дія:**
- Зафіксувати модель BMS: мінімум 12V / 20A continuous / 50A peak
- Зафіксувати модель MPPT: мінімум Victron SmartSolar MPPT 75/15

**Блокує:** Фінальний BOM, підготовка до масового виробництва.

---

### 🟡 BLOCKER-5: Теплове управління в IP67 корпусі

**Статус:** Відкрито.

- SIM7070G + MCU під час TX: до ~500 мВт × 5 сек (нехтовно)
- Starlink Mini (Phase 3): 20–40W → ~2–4W втрат у блоці живлення
- Влітку при прямому сонці корпус може нагрітися до 60–70°C внутрішньої температури
- LiFePO4 зарядка при T < 0°C пошкоджує батарею → потрібен температурний захист заряду

**Необхідна дія:**
- Розрахувати тепловий бюджет корпусу (T_зовн = +40°C)
- Додати термодатчик (NTC або DS18B20)
- Реалізувати апаратний захист заряду при T < 0°C

**Блокує:** Сертифікація для зимового деплою.

---

### 🟡 BLOCKER-6: Відсутність IWDG (Watchdog) у Queen прошивці

**Статус:** Задокументовано в [03_01 Firmware Lifecycle](03_01_Firmware_Lifecycle_and_DMA) (BLOCKER-5). Дублюється тут як апаратний ризик.

`firmware/queen/main.c:791`: Queen не має апаратного watchdog (`IWDG`). Якщо прошивка зависне (наприклад, нескінченне очікування AT-відповіді від SIM7070G), Королева ніколи не перезавантажиться.

**Необхідна дія:** Додати `HAL_IWDG_Init()` + `HAL_IWDG_Refresh()` в основний цикл Queen.

---

## 🌐 2. Детальна Архітектура Підключень

### 2.1 STM32WLE5JC ↔ LoRa мережа

| Параметр | Значення |
|---------|---------|
| Частота | 868.0 МГц (EU ISM, `Radio.SetChannel(868000000)`) |
| Розмір пакету | 16 байт (один AES-256 блок) |
| Режим RX | Continuous (`LORA_RX_INFINITE`) |
| ISR | `OnRxDone()` — апаратне переривання від SX1262 |
| Обробка пакету | `Process_And_Cache_Data()` → CIFO cache (50 слотів) |

**CIFO Cache (Forest Cache):**
```c
// firmware/queen/main.c:87-97
typedef struct {
    uint32_t uid;         // DID дерева (4 байти)
    uint8_t  payload[16]; // Розшифровані дані сенсора
    int8_t   rssi;        // RSSI [dBm]
    uint8_t  is_active;
} EdgeCache;

EdgeCache forest_cache[50]; // 50 × 22 байти = 1.1 KB
```

**Flush trigger:** кожні 3600 сек (+0–60 сек HRNG jitter) АБО при заповненні ≥ 45/50 слотів.

---

### 2.2 STM32WLE5JC ↔ SIM7070G (Phase 1 / Phase 2.5 DTC)

**Фізичне підключення:**

| Сигнал | STM32 Pin | SIM7070G Pin | Примітка |
|--------|-----------|--------------|---------|
| UART TX | PA9 (UART1_TX) | SIM_RX | Передача AT-команд |
| UART RX | PA10 (UART1_RX) | SIM_TX | Відповідь модему |
| PWR_KEY | GPIO (TBD) | PWRKEY | Програмне вмикання/вимикання |
| VCC | Рег. 12V → 3.7V | VCC (3.7V) | Живлення від LiFePO4 через DC-DC |
| GND | GND | GND | — |

**Ініціалізація (AT-команди при старті):**
```c
// firmware/queen/main.c:205-206
SIM7070_SendATCommand("AT\r\n", 500);          // Перевірка зв'язку
SIM7070_SendATCommand("AT+CNMP=38\r\n", 1000); // LTE-M only mode
```

**CoAP Uplink (при кожному flush):**
```c
// firmware/queen/main.c:542-566
SIM7070_SendATCommand("AT+CCOAPNEW=\"coap://api.silkennet.com:5683\"\r\n", 1000);
// AT+CCOAPSEND=0,2,"telemetry/batch/<queen_uid>",<size>,"<hex_data>"
SIM7070_SendATCommand("AT+CCOAPDEL=0\r\n", 500);
```

**Пікові струми SIM7070G:**

| Режим | Струм | Напруга | Потужність |
|-------|-------|---------|-----------|
| Sleep | < 1 мА | 3.7V | < 3.7 мВт |
| Idle (мережа підключена) | ~10 мА | 3.7V | 37 мВт |
| LTE-M TX (середній) | ~100 мА | 3.7V | 370 мВт |
| LTE-M TX **пік** | **до 2А** | 3.7V | **до 7.4 Вт** |
| NB-IoT TX | ~100–150 мА | 3.7V | 370–555 мВт |

> ⚠️ Пікові 2А тривають мікросекунди (RF burst). Але BMS та провідники **повинні** витримувати 2А без просадки.

---

### 2.3 STM32WLE5JC ↔ Starlink Mini (Phase 3 — Planetary Scale)

**⚠️ Поточний стан: архітектурно визначено, але НЕ реалізовано у firmware. Не потрібно для Phase 1 та 2.5.**

Starlink Mini — компактний термінал LEO-супутника для ультра-віддалених локацій (Амазонія, Тайга, Африка де DTC недоступний або недостатньо швидкий).

| Параметр | Starlink Mini |
|---------|-------------|
| Живлення | DC 12–48V (рекомендовано 12V від LiFePO4) |
| Споживання | **20–40 Вт** (типово ~23 Вт при активному сеансі) |
| Підключення | Ethernet (RJ45) **або** WiFi (802.11n, 2.4/5 GHz) |
| Латентність | 25–60 мс (LEO orbit) |
| Throughput | до 100 Мбіт/с DL / 10 Мбіт/с UL |

**Duty Cycling Starlink Mini (рекомендована стратегія):**
```
[55 хв: Starlink OFF — STM32 накопичує дані в CIFO Cache]
[5 хв: STM32 подає 12V на Starlink → очікує з'єднання (~30-60 сек) → flush → OFF]
```

---

## 🌲 3. Power Tree (Дерево Живлення)

```
☀️ Solar Panel (50W, 12–18V Voc)
         │
         ▼
┌────────────────────┐
│  MPPT Controller   │  Victron SmartSolar MPPT 75/15 (рекомендовано)
└────────────────────┘
         │ 12V (зарядний)
         ▼
┌────────────────────┐
│  LiFePO4 Battery   │  12V / 20Ah (Phase 1/2.5), 40Ah (Phase 3 winter)
│  + BMS (20A cont., │  192 Вт·год корисна (80% DoD)
│    50A peak)       │
└────────────────────┘
         │ 12V (розряд)
         ├────────────────────────────▶ Starlink Mini (Phase 3 only)
         ▼
┌────────────────────┐
│  DC-DC Buck        │  12V → 3.7V та 3.3V, ≥3А
└────────────────────┘
         │ 3.7V              │ 3.3V
         ▼                   ▼
┌──────────────┐    ┌────────────────────┐
│  SIM7070G    │    │  STM32WLE5JC       │
│  (LTE-M/DTC) │    │  (MCU + LoRa)      │
│  ~10–200 мА  │    │  ~7 мА (Cont. RX)  │
│  2А пік TX   │    │  ~15 мА (RNG/AES)  │
└──────────────┘    └────────────────────┘
```

---

## 🔋 4. Енергетичний Бюджет (Energy Budget)

### Phase 1/2.5: SIM7070G LTE-M / Starlink DTC

| Компонент | Режим | Струм | Час на добу | Вт·год/добу |
|-----------|-------|-------|------------|------------|
| STM32WLE5JC | Continuous RX | 7 мА × 3.3V | 24 год | 0.55 |
| SIM7070G | Idle | 10 мА × 3.7V | 23.93 год | 0.89 |
| SIM7070G | LTE-M TX burst (1×/год) | avg 100 мА × 3.7V | ~5 сек × 24 | 0.12 |
| MPPT + BMS quiescent | — | ~5 мА × 12V | 24 год | 1.44 |
| DC-DC losses (5%) | — | — | 24 год | 0.15 |
| **Разом** | | | | **~3.2 Вт·год/добу** |
| **Генерація (зима, хвойний ліс)** | 50W × 3h × 12.5% | | | **18.75 Вт·год/добу** |
| **Баланс** | | | | **+15.5 Вт·год/добу ✅** |

### Phase 3: Starlink Mini (Duty Cycle: 5 хв/годину, Hard OFF)

| Компонент | Вт·год/добу |
|-----------|------------|
| STM32WLE5JC + SIM7070G (ідентично Phase 1/2.5) | 1.56 |
| Starlink Mini активний (5 хв/год × 25 Вт × 24) | 50.0 |
| ESP32-S3 co-processor (якщо використовується) | 12.0 |
| **Разом Phase 3** | **~44–64 Вт·год/добу** |
| **Генерація (зима, хвойний ліс)** | **18.75 Вт·год/добу** |
| **Баланс (зима, Phase 3)** | **-25 до -45 Вт·год ⚠️** |

> **Висновок:** Phase 1/2.5 (SIM7070G / DTC) — стійка навіть взимку під кронами (профіцит +15.5 Вт·год). Phase 3 (Starlink Mini) вимагає або більшого акумулятора (≥40Ah), або скорочення duty cycle до 1 хв/год, або 100W панелі.

---

## 📶 5. Топологія Uplink (LoRa → Modem → Rails)

```
[Ліс: 1–5000 дерев у радіусі 3–5 км]
           │ LoRa 868 МГц
           │ 16-байтні пакети (AES-256-ECB)
           ▼
[STM32WLE5JC: Continuous RX]
           │
           │ 1. OnRxDone ISR → AES-ECB decrypt → Process_And_Cache_Data()
           │ 2. CIFO cache: дедуплікація + priority-aware eviction
           │ 3. 50 слотів × 21 байт → binary batch
           │
[Flush trigger: 1 год або 45/50 слотів]
           │
           │ 4. HRNG → 128-бітний IV
           │ 5. AES-256-CBC шифрує весь батч
           │ 6. AT+CCOAPNEW + AT+CCOAPSEND → SIM7070G UART
           │
           ▼
[SIM7070G: LTE-M]
    Phase 1: наземні вишки Київстар
    Phase 2.5: Starlink DTC через Київстар (без термінала!) ← НОВА
    Phase 3: Starlink Mini (термінал, ESP32/SIM8200G-M2)
           │
           ▼
[coap://api.silkennet.com:5683]
           │ POST /telemetry/batch/<queen_uid>
           ▼
[Rails API → TelemetryUnpackerService → PostgreSQL]
```

---

## 🛰️ 6. Стратегія Підключення (Connectivity Strategy)

| Фаза | Технологія | Termінал Starlink | Покриття | Потужність TX | Вартість/міс |
|------|-----------|-------------------|---------|--------------|-------------|
| **Phase 1** | LTE-M (наземні вишки) | ❌ | Там де є 4G | ~370 мВт | ~$10–30 (SIM) |
| **Phase 2.5** | Starlink DTC (Київстар) | ❌ | Розширене (DTC footprint) | ~370 мВт | ~$10–30 (SIM) |
| **Phase 3** | Starlink Mini | ✅ ($599 одноразово) | Глобальне | 20–40 Вт | ~$50/міс |
| **Phase 4 (Backup)** | Helium Network (HNT) | ❌ | Там де є роутери Helium (~15 км) | ~37 мВт (SF9) | частки цента/пакет |

**Рекомендація:** Розпочати з Phase 1, перейти на Phase 2.5 (без апаратних змін!) для лісів поза 4G-покриттям. Phase 3 — лише для Амазонії, Тайги, Африки де DTC недоступний.

**Перевірка DTC-покриття для Черкаського бору:**
1. [Starlink Coverage Map](https://www.starlink.com/map) → фільтр "Direct to Cell"
2. Запит до Київстар корпоративний: "Чи підтримує SIM LTE-M з'єднання через Starlink DTC?"

---

## 🌐 6.1 Helium Network (HNT) — Резервна Нервова Система

**Проблема:** Queen — єдина точка відмови між лісом та інтернетом. При пожежі, повені або втраті живлення — зв'язок з кластером обривається повністю. Усі Солдати продовжують генерувати дані, але ніхто не слухає.

**Рішення:** [Helium Network](https://www.helium.com/) — найбільша у світі децентралізована мережа LoRaWAN. Сотні тисяч роутерів у 180+ країнах, встановлених звичайними людьми на балконах та дахах.

### Архітектура Helium Fallback

```
[Нормальна робота]
  Soldier ──LoRa──▶ Queen (власна) ──CoAP──▶ Rails Backend

[Queen недоступна (пожежа / відключення живлення)]
  Soldier ──LoRa──▶ 🌐 Будь-який Helium роутер у радіусі 15 км
                         │ (відкрита мережа, чужий пристрій)
                         ▼
                    Helium Network (LNS)
                         │
                         ▼
                    api.silkennet.com (через Helium HTTP Integration)
```

### Умови активації Fallback

Солдат переходить у режим Helium fallback автоматично при відсутності ACK від Queen протягом N циклів (конфігурується). Логіка в `firmware/soldier/main.c`:

```c
// Псевдокод — пропозиція для майбутнього циклу
// HELIUM_FALLBACK_THRESHOLD: 3 цикли (~3 години без ACK від Queen)
// Стиснення: замість 16-байт повного payload → 8 байт (DID:4 + lambda:2 + status:1 + CRC:1)
#define HELIUM_FALLBACK_THRESHOLD 3     // пропущені ACK перед активацією fallback
#define HELIUM_PAYLOAD_SIZE       8     // стиснений пакет: DID + lambda_exponent + status + CRC8

if (queen_ack_timeout_count >= HELIUM_FALLBACK_THRESHOLD) {
    // Перемикаємо DevEUI/AppKey на Helium credentials (з захищеної зони Flash)
    // lora_payload_compressed: [DID:4][lambda_exp:2][bio_status:1][CRC8:1]
    Send_Via_Helium_LoRaWAN(lora_payload_compressed, HELIUM_PAYLOAD_SIZE);
    queen_ack_timeout_count = 0;
}
```

### Економіка Helium

- **Вартість:** кожен переданий пакет (Data Credit, DC) = $0.00001 USD
- **Оплата:** з Treasury DAO — Солдати, що звертаються до Helium, оплачують мікротранзакції токенами IOT з Гаманця кластера
- **Формат пакету:** той самий 21-байтний payload (можливо стиснутий до 12 байт через lambda-summary замість повного Lorenz)

### Що потрібно для реалізації

| Крок | Дія | Де |
|------|-----|----|
| DevEUI / AppKey | Зареєструвати кожен Soldat у [Helium Console](https://console.helium.com/) | Helium |
| HTTP Integration | Налаштувати webhook → `https://api.silkennet.com/api/v1/telemetry/helium` | Helium Console |
| Firmware | Додати LoRaWAN stack (OTAA join) як fallback шлях поруч із raw AES LoRa | `firmware/soldier/main.c` |
| Rails | Новий endpoint `POST /api/v1/telemetry/helium` → `UnpackHeliumTelemetryWorker` | Rails API |
| BOM | Helium credentials (DevEUI + AppKey) зберігати в `HardwareKey` моделі | Backend |

### Статус Helium Fallback

| Компонент | Стан |
|-----------|------|
| Концепт і архітектура | ✅ Визначено (цей документ) |
| Firmware зміни | 🔴 Не реалізовано |
| Rails endpoint | 🔴 Не реалізовано |
| Реєстрація у Helium Console | 🔴 Не виконано |
| BOM (credentials storage) | 🟡 Потребує уточнення схеми |

> **Стратегічна цінність:** Helium перетворює систему на фізично невбивану мережу. Навіть якщо всі Королеви згорять у лісовій пожежі — Солдати продовжуватимуть передавати сигнали SOS через чужі роутери. Для pitch deck: _"The forest cannot go dark — it has a global backup nervous system."_

---

## 🧾 7. BOM Королеви (Bill of Materials)

| # | Компонент | Специфікація | Фаза | Статус |
|---|-----------|-------------|------|--------|
| 1 | **STM32WLE5JC** (LoRa-E5 Mini, Seeed Studio) | ARM Cortex-M4 + SX1262, 868 МГц, 256KB Flash | 1/2.5/3 | ✅ |
| 2 | **SIM7070G** (або SIM7000G — уточнити) | LTE-M / NB-IoT / GNSS, UART AT, 3.7V | 1/2.5 | ⚠️ Назва уточнюється |
| 3 | **Starlink Mini** | LEO satellite terminal, DC 12–48V, 20–40W | 3 only | 📋 Заплановано |
| 4 | **ESP32-S3** (WiFi co-processor для Starlink Mini) | 240 МГц, WiFi 802.11n, UART | 3 only | ⚠️ Не реалізовано |
| 5 | **Сонячна панель** | Monocrystalline, 50W (Phase 1/2.5) / 100W (Phase 3 winter) | 1/2.5/3 | ✅ Архітектурно |
| 6 | **MPPT контролер** | Victron SmartSolar MPPT 75/15 (рекомендовано) | 1/2.5/3 | 🟡 Модель не зафіксована |
| 7 | **LiFePO4 акумулятор** | 12V / 20Ah (Phase 1/2.5), 40Ah (Phase 3 winter) | 1/2.5/3 | 🟡 Ємність уточнюється |
| 8 | **BMS** | 12V / 20А continuous / 50А peak, температурний захист | 1/2.5/3 | 🟡 Модель не зафіксована |
| 9 | **DC-DC buck 12V→3.7V** | ≥3А continuous, ≥5А peak | 1/2.5 | ✅ Архітектурно |
| 10 | **DC-DC buck 12V→3.3V** | ≥500 мА | 1/2.5/3 | ✅ Архітектурно |
| 11 | **LTE-M антена** | 868/LTE-M dual-band SMA (зовнішня, IP67) | 1/2.5 | ✅ Архітектурно |
| 12 | **LoRa антена** | 868 МГц, 5 dBi, зовнішня SMA | 1/2.5/3 | ✅ Архітектурно |
| 13 | **IP67 корпус** | ABS/PC + ущільнення, ≥2.5L | 1/2.5/3 | 📋 Не специфіковано |
| 14 | **SWD програматор** | ST-LINK-V3MINIE | — | ✅ |
| 15 | **UART адаптер** | FT232RL, 3.3V режим | — | ✅ |

---

## 🔗 Пов'язані Документи

| Модуль | Зміст |
|--------|-------|
| [03_02 Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Детальна логіка прошивки: CIFO, дедуплікація, OTA, AT-команди |
| [03_05 Hardware AES256 and Security](03_05_Hardware_AES256_and_Security) | Повний аудит безпеки: ECB vs CBC, управління ключами |
| [02_03 BQ25570 MPPT Nano Power](02_03_BQ25570_MPPT_Nano_Power) | MPPT для Soldier |
| [07_02 Unit Economics and BOM](07_02_Unit_Economics_and_BOM) | Вартість розгортання (блокується цим документом) |
