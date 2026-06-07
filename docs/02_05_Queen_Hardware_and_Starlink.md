# 02_05: Апаратне Забезпечення Королеви та Starlink (Міст)

---

## 🎯 Мета

Зафіксувати **повну апаратну архітектуру** вузла "Королева" (Queen Gateway) — єдиного фізичного моста між автономною LoRa-мережею лісу та глобальним інтернетом. Документ відповідає на три критичних питання:

1. Як **фізично** з'єднані MCU (STM32WLE5JC), стільниковий модем (SIM7070G) та Starlink?
2. Чи **вистачає** пікового струму від батареї для SIM7070G (до 2А в стрибках)?
3. Яка **добова потреба у ватт-годинах** для цілодобової роботи Королеви в різних фазах?

> Цей документ фіксує "як є" — включаючи всі відомі ризики, невирішені архітектурні питання та підтверджені специфікації компонентів.

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — Схеми/прототипи існують, прошивка готова; Phase 2.5 Starlink DTC підтверджено через Київстар
- **Відкрите:** зимовий енергодефіцит, SIM7070G BMS/decoupling, теплове управління IP67 → [`00_07`](00_07_Action_Plan_Tracker) (HW.14/15/18).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`02_03` — BQ25570 MPPT Nano Power](02_03_BQ25570_MPPT_Nano_Power) | MPPT (живлення, cold-start) |
| [`02_04` — EDLC Supercapacitor Buffer](02_04_EDLC_Supercapacitor_Buffer) | Суперконденсатор-буфер |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Прошивка Королеви (CIFO, OTA, AT) |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Аудит безпеки (ECB/CBC, ключі) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (gateway telemetry) |
| [`07_02` — Unit Economics and BOM](07_02_Unit_Economics_and_BOM) | Вартість розгортання |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | HW.14/15/18 (energy, BMS, thermal) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Відкриті апаратні питання (open → 00_07)](#-відкриті-апаратні-питання-open--00_07)
- [2. Детальна Архітектура Підключень](#-2-детальна-архітектура-підключень)
- [3. Power Tree (Дерево Живлення)](#-3-power-tree-дерево-живлення)
- [4. Енергетичний Бюджет](#-4-енергетичний-бюджет)
- [4а. Тепловий бюджет IP67 корпусу](#-4а-тепловий-бюджет-ip67-корпусу-)
- [5. Топологія Uplink](#-5-топологія-uplink)
- [6. Стратегія Підключення](#-6-стратегія-підключення)
- [6.1 Helium Network (HNT) — Резервна Нервова Система (Queen-side)](#-61-helium-network-hnt--резервна-нервова-система-queen-side)
- [7. BOM Королеви](#-7-bom-королеви)
<!-- TOC:AUTO:END -->

---

## 🚧 Відкриті апаратні питання (open → 00_07)

> Статуси трекаються в [`00_07`](00_07_Action_Plan_Tracker) (HW.14/15/18).

### Starlink DTC (Phase 2.5) vs Starlink Mini

**Статус:** Частково вирішено для Phase 2.5. Відкрито для Phase 3.

#### Що підтверджено

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

> **⚠️ Транспортна надійність через D2C (2026-05-28):** Direct-to-Cell працює за LTE-протоколами (SMS + базовий 4G) через жорсткий **Carrier-NAT**, який може блокувати вхідний UDP (а CoAP — UDP) або змінювати порти. Тому **чистий CoAP/UDP ненадійний** на D2C; архітектура має передбачати фолбек **CoAP-over-TCP** ([RFC 8323](https://www.rfc-editor.org/rfc/rfc8323)) або **MQTT-SN**, а Ingress Proxy ([`06_01`](06_01_Deployment_Kamal_Terraform)) — толерувати високий jitter / packet loss супутникового LTE. HIL `realistic_mode` ([`00_03 §3.2`](00_03_TRL_Matrix_HIL_and_Beyond)) моделює саме ці умови.

#### Що залишається відкритим

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
- Описати рішення в [`03_02`](03_02_Queen_Gateway_Firmware) та оновити апаратну схему
- Прошивку для co-processor додати в `firmware/` перед Phase 3 деплоєм

**Блокує:** Лише Phase 3 (Planetary Scale). Phase 1 та Phase 2.5 — не блоковані.

**🤖 Decision memo [HW.18] — рекомендація: ESP32-S3** (confirm/adjust):

Роль co-processor у Phase 3 **єдина** — WiFi-STA + TCP/IP-міст STM32 → Starlink Mini (Ethernet/WiFi). Обидва варіанти це вміють; вирішують вартість/енергія/доцільність:

| Вісь | **ESP32-S3** (Варіант А) | SIM8200G-M2 (Варіант Б) |
|------|--------------------------|--------------------------|
| Ціна | ~$2–4 | ~$50–90 (5G M.2 модуль) |
| 5G-можливість | — (не потрібна) | **марнується** — у глибокому лісі стільникового нема (тому й Starlink) |
| Idle power | deep-sleep ~10 µA між погодинними TX | вищий module-idle → гірше для §Зимовий енергодефіцит |
| Active | 80–240 мА (~0.3–0.9 Вт) WiFi-burst | співмірно у WiFi-режимі, але модуль важчий |
| Інтеграція | UART/SPI; ESP-IDF/lwIP зрілі; **треба написати прошивку** | один UART-AT, простіша схема |
| Екосистема | величезна (ESP-IDF, lwIP) | нішевий M.2-модем |

**Рекомендація: ESP32-S3.** Co-proc лише мостить до WiFi Starlink Mini — ESP32-S3 робить це за ~$3 з near-zero sleep (критично: Queen уже тягне 20–40 Вт Starlink-burst, зимовий дефіцит §Зимовий енергодефіцит — кожен mW idle важить). 5G у SIM8200G-M2 безсенсовий (нема покриття у Phase-3 ultra-remote) + ~20× дорожчий + вищий idle. Єдина ціна ESP32-S3 — написати co-proc прошивку (UART-AT bridge + WiFi-STA + lwIP), обмежено й зріло.

**SIM8200G-M2 виправданий ЛИШЕ** якщо Phase 3 переосмислити як «5G-where-available як другий backhaul» (суперечить ultra-remote премісі). Інакше — ESP32-S3.

**Після confirm:** оновити схему + [`03_02`](03_02_Queen_Gateway_Firmware) (firmware-контракт co-proc) + `firmware/esp32_coproc/` (UART-AT + WiFi-STA + lwIP).

---

### Зимовий Енергетичний Дефіцит

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

### Розбіжність найменування модему

**Статус:** Відкрито. Блокер для закупівлі обладнання та BOM.

| Джерело | Модель модему |
|---------|--------------|
| Wiki [`02_05`](02_05_Queen_Hardware_and_Starlink) (до аудиту) | **SIM7000G** |
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
| **eDRX (Extended DRX)** | ✅ Підтримує | ✅ **Покращена підтримка** (AT+CEDRXS) |
| **PSM (Power Saving Mode)** | ✅ Підтримує | ✅ **Покращена підтримка** (AT+CPSMS) |
| **Idle споживання (PSM)** | ~10 мкА | **~3 мкА** (критично для IoT) |

> **📝 Рішення (Legacy notes, підтверджено):** Зупинитися на **SIM7070G**. Він має кращу підтримку eDRX та PSM для мереж NB-IoT/LTE-M, що критично для зниження idle-споживання Queen між hourly CoAP flush-циклами. PSM-режим SIM7070G (~3 мкА) значно знижує фонове споживання порівняно з SIM7000G (~10 мкА). AT-команди у firmware вже орієнтовані на SIM7070G (`AT+CNMP=38`).

**Необхідна дія:**
- Фізично перевірити маркування на прототипі модему
- Привести wiki, BOM та коментарі прошивки до єдиного найменування **SIM7070G**
- Додати AT+CPSMS та AT+CEDRXS команди у firmware flush-цикл Queen

**Блокує:** BOM закупівля, Hardware Security Audit.

---

### Пікові струми SIM7070G — BMS не специфікований + VBAT decoupling

**Статус:** Часткове рішення зафіксовано (VBAT tank-cap bank — §2.2.1, BOM 17–20). BMS/MPPT моделі залишаються відкритими.

SIM7070G у режимі LTE-M TX може споживати імпульсно до **2A** пікового значення. Це створює дві окремі проблеми:

1. **Системний рівень:** BMS (Battery Management System) має витримувати ці спалахи без срабатывания захисту від перетоку.
2. **Module рівень:** Транзієнтна просадка `VBAT` модему під час 2А burst → brownout reboot (`§2.2.1`).

- **BMS:** захист від перетоку має бути ≥ 5А (з 2.5× запасом)
- **Провідники:** AWG16 або AWG18 для L < 30 см
- **MPPT:** Victron SmartSolar 75/10 (вихідний струм 10А > 2А ✅), але модель не зафіксована в BOM
- **VBAT decoupling:** ✅ Специфіковано — 5-cap tier у §2.2.1 та BOM позиції 17–20

**Необхідна дія:**
- Зафіксувати модель BMS: мінімум 12V / 20A continuous / 50A peak
- Зафіксувати модель MPPT: мінімум Victron SmartSolar MPPT 75/15
- ✅ Фінальний layout SIM7070G ділянки PCB: bulk cap ≤ 10 мм від VBAT pin, HF caps впритул

**Блокує:** Фінальний BOM, підготовка до масового виробництва.

---

### Теплове управління в IP67 корпусі

**Статус:** 🤖 Тепловий бюджет розраховано (див. §3.4 нижче). Залишок — фізична інтеграція NTC/DS18B20 та charge-protect MOSFET (👤).

- SIM7070G + MCU під час TX: до ~500 мВт × 5 сек (нехтовно)
- Starlink Mini (Phase 3): 20–40W → ~2–4W втрат у блоці живлення
- Влітку при прямому сонці корпус може нагрітися до 60–70°C внутрішньої температури
- LiFePO4 зарядка при T < 0°C пошкоджує батарею → потрібен температурний захист заряду

**Необхідна дія:**
- [x] 🤖 Розрахувати тепловий бюджет корпусу (T_зовн = +40°C) — див. §3.4 «Тепловий бюджет IP67 корпусу»
- [ ] 👤 Додати термодатчик (NTC або DS18B20)
- [ ] 👤 Реалізувати апаратний захист заряду при T < 0°C

**Блокує:** Сертифікація для зимового деплою.

> **Cross-ref:** [`00_07` — HW.16](00_07_Action_Plan_Tracker) — checklist синхронізовано.

---


## 🌐 2. Детальна Архітектура Підключень

### 2.1 STM32WLE5JC ↔ LoRa мережа

| Параметр | Значення |
|---------|---------|
| Частота | 868.0 МГц (EU ISM, `Radio.SetChannel(868000000)`) |
| Розмір пакету | 16 байт (один AES блок; block size 128 bit фіксований; key size = AES-128 для LoRa post-ARCH.42) |
| Режим RX | Continuous (`LORA_RX_INFINITE`) |
| ISR | `OnRxDone()` — апаратне переривання від SX1262 |
| Обробка пакету | `Process_And_Cache_Data()` → CIFO cache (50 слотів) |

**CIFO Cache (Forest Cache) — Hot Tier:**
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

⚠️ **Capacity math (2026):** 50 слотів × 1 пакет/Soldier/год × 100 Soldiers/Queen ⇒ переповнення за **30 хв** при втраті Starlink. На верхньому краю scaling roadmap ([`00_08 §2.1`](00_08_Beyond_TRL9_Planetary_Roadmap), 200 Soldiers/Queen) — переповнення за **15 хв**. Це **критичний gap**, який маскувався тестами в стенді з <50 Soldiers.

**Flash Ring Buffer — Overflow Tier (ARCH.35):**
```c
// firmware/queen/flash_buffer.c — пропозиція ARCH.35
// W25Q32 SPI NOR: 4 MB = 1024 sectors × 4 KB; page-program 256 B, але erase —
// ТІЛЬКИ цілим сектором 4 KB (NOR не вміє 0→1 без erase). Тому ring — ПО СЕКТОРАХ,
// а не по довільних 21-байт offset'ах: 21-байт слоти пакуються послідовно у сектор
// (~195 слотів/сектор) → ~199k слотів. Покажчики (write_sector, read_sector,
// slot_in_sector) у вільних Queen RTC backup регістрах (DR0..DR19;
// DR20+ не існують на WLE5 — лише 20 регістрів).
#define SLOTS_PER_SECTOR  (4096 / 21)   // 195
#define N_SECTORS         1024

void cifo_overflow_to_flash(EdgeCache* slot) {
    if (slot_in_sector == 0) {                                  // починаємо новий сектор
        if ((write_sector + 1) % N_SECTORS == read_sector)
            read_sector = (read_sector + 1) % N_SECTORS;        // ring повний → FIFO-drop найстарішого СЕКТОРА
        w25q32_erase_sector(write_sector);                      // обов'язковий erase ПЕРЕД програмуванням
    }
    w25q32_write_page(write_sector, slot_in_sector * 21, slot, 21);
    if (++slot_in_sector >= SLOTS_PER_SECTOR) { slot_in_sector = 0; write_sector = (write_sector + 1) % N_SECTORS; }
}

void cifo_drain_from_flash(void) {                              // FIFO: найстаріший сектор першим
    while (read_sector != write_sector && uplink_available()) {
        for (int i = 0; i < SLOTS_PER_SECTOR; i++) {
            w25q32_read(read_sector, i * 21, &slot, 21);
            if (coap_send(&slot) != OK) return;                 // стоп без втрати прогресу
        }
        read_sector = (read_sector + 1) % N_SECTORS;            // сектор повністю злито (стертя — при наступному обороті)
    }
}
```

**Енерго-бюджет flash write:** W25Q32 page write ~10 мА × 0.7 мс/page = 7 µA·s; sector erase (4 KB) ~15 мА × ~45 мс ≈ 675 µA·s, але амортизовано раз на ~195 слотів. При середньому 100 overflow-events/добу на Queen — одиниці mA·s/добу, що значно нижче добового нойзу LiFePO4 12V/20Ah (~3.2 Вт·год/добу phase 2.5, див. §1.2 §Зимовий енергодефіцит). **Не змінює зимовий енергобюджет.**

---

### 2.2 STM32WLE5JC ↔ SIM7070G

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

#### 2.2.1 VBAT Decoupling Network (захист від brownout reboot)

> 🔴 **Класична IoT-пастка:** DC-DC конвертер 12V→3.7V специфіковано на ≥3А continuous / ≥5А peak (`§3 Power Tree`, `§Пікові струми SIM7070G`). Але **час реакції регулятора + паразитна індуктивність доріжок плати** означають, що при наносекундному переході модему з 10 мА (idle) у 2 А (LTE-M TX burst) напруга на піні `VBAT` модему **миттєво просідає** перш ніж DC-DC встигне піднятися. Якщо просадка перевищує brownout-поріг SIM7070G (~3.0–3.2 В) навіть на мілісекунди — **модем апаратно перезавантажується посеред CoAP-пакету**. Симптом: Queen «втрачає» Starlink DTC з'єднання раз на ~1–10 spike-frames, незрозумілі gaps у telemetry.
>
> Рішення — локальна «батарея» конденсаторів **безпосередньо біля пінів VBAT модему** (як можна ближче, доріжка ≤ 5 мм), яка віддає заряд миттєво поки DC-DC «розганяється».

**Tank Cap Bank — обов'язкова специфікація біля SIM7070G VBAT pins:**

| Поз. | Компонент | Призначення | Розташування |
|------|-----------|-------------|--------------|
| C_BULK | **470 µF, 6.3V, low-ESR aluminum polymer** (Panasonic SP-Cap EEFCX0J471R або Kemet T520B477M006ATE015), ESR ≤ 15 мΩ | Основний бункер для 1–10 мс TX-burst | 5–10 мм від VBAT pin |
| C_MID | **100 µF, 25V, X7R, 1210** (Murata GRM32ER71E107K), C_eff @ 3.7V ≈ 85 µF після derating | Мід-частотний buffer (kHz range RF chopping) | ≤ 5 мм від VBAT pin |
| C_HF1 | **10 µF, 25V, X7R, 0805** | HF фільтр живлення | ≤ 3 мм від VBAT pin |
| C_HF2 | **100 nF, 50V, X7R, 0402** | HF decoupling MCU bus | впритул до VBAT pin |
| C_RF | **33 pF, 50V, NP0, 0402** | Фільтр антенного RF-сплеску у живлення | впритул до VBAT pin |

**Розрахунок transient response (підтвердження достатності):**

```
ESR_parallel ≈ ESR_bulk ∥ ESR_MLCCs ≈ 15 mΩ ∥ ~5 mΩ ≈ 4 mΩ
ΔV_peak_ESR = I_peak × ESR_parallel = 2 A × 4 mΩ = 8 mV   ✓ (далеко від brownout)

ΔV_droop за 1 мс burst (до того, як DC-DC підхопить):
  ΔV = (I_peak − I_DCDC_response) × t / C_bulk_eff
       = (2 − 0.3) × 0.001 / 470e-6 = 3.6 mV   ✓
```

Поріг brownout SIM7070G — **3.0 В** (datasheet SIM7070_Series_Hardware_Design_V1.05). Margin від 3.7 В номіналу — 700 мВ. Сумарна просадка з tank bank: < 20 мВ навіть при найгіршому 2А спалаху. **Запас > 35×.** ✓

**❌ Анти-патерни (типові помилки):**
- ❌ Тільки 10 µF MLCC біля модему без bulk cap — derating + малий C дає просадку 200+ mV
- ❌ Танталовий cap без полімерного покриття — failure mode «short circuit on overvoltage» при випадковому 12V spike
- ❌ Bulk cap далі ніж 15 мм від модему — паразитна індуктивність доріжки (~10 нГн/см) формує LC-tank, що дзвенить на спадаючому фронті
- ❌ Економія на C_RF — без 33 pF cap RF-burst антени потрапляє назад у VBAT та збиває MCU UART (виглядає як «AT command no response»)

> **Cross-ref:** додати ці п'ять компонентів у BOM §7 (рядки 16–20, нові). Специфікація узгоджена з SIMCom Hardware Design Guide §3.4.1 (Power Supply Design) та принципом tiered-decoupling, описаним у [`02_03 §6.3`](02_03_BQ25570_MPPT_Nano_Power).

---

### 2.3 STM32WLE5JC ↔ Starlink Mini

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

## 🔋 4. Енергетичний Бюджет

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

### Phase 3: Starlink Mini

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

## 🌡️ 4а. Тепловий бюджет IP67 корпусу 🤖

**Cross-ref:** [`00_07` — HW.16](00_07_Action_Plan_Tracker), §Теплове управління IP67 вище.

**Мета:** перевірити, що температура всередині корпусу не виходить за робочі діапазони компонентів при найгіршому сценарії: T_зовн = +40°C, прямі сонячні промені, штиль.

### 4а.1 Робочі температурні діапазони компонентів

| Компонент | Operating Temp | Storage / Critical Limits |
|-----------|---------------|---------------------------|
| STM32WLE5JC (industrial) | −40 … +85°C | Junction T_J,max = +125°C |
| SX1262 LoRa (вбудований у WLE5JC) | −40 … +85°C | RF performance деградує > +85°C |
| SIM7070G (industrial) | −40 … +85°C | TX peak повинен бути < +85°C |
| LiFePO4 (LiFeYPO₄) | −20 … +60°C (розряд) | **Заряд лише 0 … +45°C** ⚠️ |
| BMS (типовий 12V 20A) | −20 … +60°C | — |
| BQ25570 MPPT | −40 … +85°C | — |
| EDLC 0.47F/5.5V | −40 … +70°C | C-deg при > +70°C |

**Найжорсткіше обмеження:** заряд LiFePO4 при T < 0°C → деградація плакування графіту → necessary charge-disable нижче 0°C.

### 4а.2 Розсіювання тепла (Phase 1/2.5)

Усереднений тепловий бюджет (24-годинний цикл, без прямого сонця):

| Джерело | Потужність (середнє) | Тривалість/добу | Енергія/добу |
|---------|---------------------|-----------------|--------------|
| MCU active (STM32WLE5JC) | 30 мВт | 100% (always-on RX) | ~720 Вт·с (нехтовно) |
| SIM7070G idle | 37 мВт | ~95% | ~3.0 Вт·год |
| SIM7070G TX bursts (370 мВт avg, 7.4 Вт peak) | ~370 мВт | 5% (CoAP flush) | ~0.44 Вт·год |
| BMS + MPPT quiescent | 60 мВт (5 мА × 12V) | 100% | 1.44 Вт·год |
| DC-DC 12V→3.7V losses (η ≈ 88%) | ~10–20 мВт | 100% | ~0.4 Вт·год |
| **Разом Phase 1/2.5** | **≈ 130 мВт середнє** | — | **≈ 5.3 Вт·год** |

**Пікова теплова потужність (CoAP TX burst, 1–5 сек):** до **2.5 Вт** (sum SIM7070G TX peak + DC-DC losses + BMS dissipation). Тривалість недостатня для значного підйому температури в корпусі ≥ 2.5L (теплоємність повітря + електроніки domiнує).

### 4а.3 Розсіювання тепла (Phase 3, Starlink Mini)

| Джерело | Потужність | Тривалість/добу | Енергія/добу |
|---------|-----------|-----------------|--------------|
| Phase 1/2.5 baseline | ~130 мВт | 100% | 5.3 Вт·год |
| Starlink Mini (5 хв/год × 25 Вт) | 25 Вт | ~8% (1.92 год) | 50.0 Вт·год |
| Starlink Mini PSU losses (η ≈ 90%) | ~2.5 Вт | 8% | 5.0 Вт·год |
| ESP32-S3 co-processor | ~500 мВт | 100% | 12.0 Вт·год |
| **Разом Phase 3** | — | — | **≈ 72 Вт·год** |

**Пікова теплова потужність (Starlink Mini active):** ~3 Вт всередині корпусу Queen (PSU losses) + 25 Вт у самому терміналі (зовнішній корпус Starlink). Старлінк-термінал розташований **поза** Queen IP67 enclosure — лише його DC-DC регулятор живлення живе всередині.

### 4а.4 Розрахунок встановленої температури всередині корпусу

**Модель:** thermal resistance air-to-ambient через стінки IP67 enclosure.

Для типового ABS/PC корпусу 200×150×100 мм (V ≈ 3L), стінка 3 мм:
- Площа поверхні: A ≈ 0.13 м²
- Convective h (still air, vertical surface): ~5 Вт/м²·K
- R_θ (air-to-ambient) ≈ 1 / (h × A) ≈ **1.5 K/Вт**

**Phase 1/2.5 (середнє розсіювання 0.13 Вт):**
- ΔT = P × R_θ = 0.13 × 1.5 = **0.2 K** (нехтовно)
- T_внутр (T_зовн = +40°C) ≈ +40.2°C ✅
- T_внутр (T_зовн = +40°C + sun load **+15°C** через ABS чорний) ≈ +55.2°C ✅ (< +85°C operating limit для всіх компонентів)

**Phase 3 (середнє розсіювання 3 Вт під час Starlink burst, 5-хв):**
- ΔT = 3 × 1.5 = **4.5 K** середнє в момент роботи
- За 5 хв термальної інерції підйом ~2–3 K (transient)
- T_внутр (sonce + Starlink active) ≈ **+57–60°C** ✅ (з запасом)

**Висновок:** при T_зовн ≤ +40°C тепловий запас **достатній** навіть без активного охолодження. Активна вентиляція не потрібна. Sun load — головний внесок (+15 K), не власне розсіювання.

**Mitigation для прямого сонця:**
- Світлий або металізований корпус (α_solar < 0.4 замість ~0.9 для чорного ABS)
- Sunshade/montaging під кроною (типовий use case ↔ Queen на дереві)

### 4а.5 Низькі температури (зима, T_зовн = −20°C)

При −20°C амбієнт + майже відсутньому власному тепловиділенні:
- T_внутр ≈ T_зовн = **−20°C**
- LiFePO4 заряд **заблокований** (T < 0°C → деградація)
- Розряд LiFePO4 OK до −20°C
- Усі IC industrial-grade OK до −40°C

**Mitigation для заряду в зимовий період:**
1. **Hardware charge-disable:** NTC або DS18B20 → MOSFET у charge path. Заряд блокується якщо T < +1°C (±1 K hysteresis).
2. **Self-heating:** при T < 0°C і доступному PV — короткочасно навантажити SIM7070G у TX режимі (~370 мВт) для генерації власного тепла. У 3L корпусі при ~370 мВт встановлена ΔT ≈ 0.6 K → не вистачить, але затримує охолодження.
3. **Heated battery box** (опція для високоширотних деплоїв): self-heating LiFePO4 з вбудованим нагрівачем (~10 мВт quiescent при увімкненому BMS).

### 4а.6 Розташування термодатчика

| Розташування | Що вимірює | Призначення |
|--------------|-----------|-------------|
| **Біля LiFePO4 (NTC ε-bonded)** | T батареї (head-on) | **Charge protection (P0)** — гейт для charge MOSFET |
| Біля SIM7070G | T модему | Throttling TX rate якщо > +75°C |
| Біля STM32 (junction sensor) | T MCU | Software safety, telemetry |

**Рекомендація:** мінімум 1 датчик біля батареї (charge protection). DS18B20 (1-Wire) переважніше для LiFePO4 head — ±0.5°C точність, цифровий, 1 GPIO.

### 4а.7 Підсумок та action items для BOM

| Item | Рекомендація | Пріоритет |
|------|--------------|-----------|
| Sun load mitigation | Світлий корпус (RAL 7035 / metallic) АБО sunshade | P1 (літо) |
| Charge protection T-sensor | DS18B20 на корпусі LiFePO4 | **P0 (зима)** |
| Charge MOSFET cut-off | P-MOSFET у charge path, NTC-driven або MCU GPIO | **P0 (зима)** |
| Backend critical_fault? for T < −20°C | `GatewayTelemetryLog::LOW_TEMPERATURE_THRESHOLD` + ❄️ EwsAlert message — ✅ виконано | **P0 (зима)** |
| Active cooling | Не потрібно при T_зовн ≤ +40°C | — |
| Heater для LiFePO4 | Опційно для T_зовн < −20°C deployments | P3 |

**Висновок:** теплова архітектура **проходить** для нормальних кліматичних зон Європи (Карпати, Полісся). Зимовий charge-protection обов'язковий: hardware-частина (DS18B20 + MOSFET) — 👤; backend-частина (`GatewayTelemetryLog#critical_fault?` детектує `temperature_c < −20°C` → ❄️ EwsAlert) — ✅ реалізовано (HW.16).

---

## 📶 5. Топологія Uplink

```
[Ліс: 1–5000 дерев у радіусі 3–5 км]
           │ LoRa 868 МГц
           │ 16-байтні пакети (AES-128-ECB, post-ARCH.42)
           ▼
[STM32WLE5JC: Continuous RX]
           │
           │ 1. OnRxDone ISR → AES-128-ECB decrypt (LoRa key) → Process_And_Cache_Data()
           │ 2. CIFO cache: дедуплікація + priority-aware eviction
           │ 3. 50 слотів × 21 байт → binary batch
           │
[Flush trigger: 1 год або 45/50 слотів]
           │
           │ 4. MX_CRYP re-init → CRYP_KEYSIZE_256B + coap_key
           │ 5. HRNG → 128-бітний IV
           │ 6. AES-256-CBC шифрує весь батч (CoAP магістраль)
           │ 7. Restore CRYP_KEYSIZE_128B + LoRa aes_key (SEC.8)
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

## 🛰️ 6. Стратегія Підключення

| Фаза | Технологія | Termінал Starlink | Покриття | Потужність TX | Вартість/міс |
|------|-----------|-------------------|---------|--------------|-------------|
| **Phase 1** | LTE-M (наземні вишки) | ❌ | Там де є 4G | ~370 мВт | ~$10–30 (SIM) |
| **Phase 2.5** | Starlink DTC (Київстар) | ❌ | Розширене (DTC footprint) | ~370 мВт | ~$10–30 (SIM) |
| **Phase 3** | Starlink Mini | ✅ ($599 одноразово) | Глобальне | 20–40 Вт | ~$50/міс |
| **Phase 4 (Backup)** | Helium Network (HNT) — **Queen-side LoRaWAN** | ❌ | Там де є hotspot-и Helium (~15 км) | ~37 мВт (SF9, агрегат-frame) | частки цента/frame |

**Рекомендація:** Розпочати з Phase 1, перейти на Phase 2.5 (без апаратних змін!) для лісів поза 4G-покриттям. Phase 3 — лише для Амазонії, Тайги, Африки де DTC недоступний.

**Перевірка DTC-покриття для Черкаського бору:**
1. [Starlink Coverage Map](https://www.starlink.com/map) → фільтр "Direct to Cell"
2. Запит до Київстар корпоративний: "Чи підтримує SIM LTE-M з'єднання через Starlink DTC?"

---

## 🌐 6.1 Helium Network (HNT) — Резервна Нервова Система (Queen-side)

**Проблема:** Queen — єдина точка відмови між лісом та інтернетом. При втраті власного Starlink/LTE та одночасній недоступності Queen-to-Queen LoRa backhaul (всі сусідні Queen також offline) — зв'язок з кластером обривається повністю. Усі Солдати продовжують генерувати дані, але ніхто не слухає.

**Рішення:** [Helium Network](https://www.helium.com/) — найбільша у світі децентралізована мережа **LoRaWAN**. Сотні тисяч hotspot-ів у 180+ країнах, встановлених звичайними людьми на балконах та дахах.

> ⚠️ **Архітектурне уточнення (2026, post-ARCH.42):** Helium працює на протоколі **LoRaWAN MAC-layer**, а Soldier використовує **raw LoRa P2P** (фізичний рівень) з **AES-128-ECB** (ARCH.42; transitional) → AES-128-CCM (FW.2 target) поверх 21-байтного binary payload. Helium hotspot **не прийме** прямий пакет з Soldier — для валідного uplink потрібен LoRaWAN frame з DevEUI/AppEUI/AppKey, FCntUp counter, MIC та OTAA/ABP join state. Однак LoRaWAN нативно використовує саме AES-128 (AppSKey/NwkSKey), тому ARCH.42 спрощує future Helium bridging — той самий ключ-розмір. Helium fallback архітектурно **переноситься з Soldier на Queen**.

### Архітектура Helium Fallback (правильна)

```
[Нормальна робота]
  Soldier ──raw LoRa──▶ Queen ──CoAP/LTE-M──▶ Rails Backend

[Власний Starlink/LTE-M Queen впав + Q2Q backhaul недоступний]
  Soldier ──raw LoRa──▶ Queen
                          │ (CIFO + Flash Ring Buffer накопичує дані)
                          │
                          │ Queen збирає batch і формує валідний LoRaWAN frame
                          ▼
              🌐 Будь-який Helium hotspot у радіусі ~15 км
                          │ (стандартний LoRaWAN MAC)
                          ▼
                    Helium LNS / Console
                          │
                          ▼ HTTP Integration webhook
                    api.silkennet.com/api/v1/telemetry/helium (HMAC-signed)
```

### Чому LoRaWAN живе тільки на Queen

| Чинник | Soldier (STM32WLE5JC, EBFC) | Queen (STM32WLE5JC + LiFePO4 12V/20Ah) |
|--------|-----------------------------|------------------------------------------|
| Flash budget для LoRaWAN-стека (LoRaMac-node ≈ 30 KB) | ❌ Конкурує з mruby VM + TinyML | ✅ Достатньо ресурсу |
| TX power для +15 dBm (Helium SF12 reach 15 км) | ❌ EBFC vcap ~500 мВ — без запасу потужності | ✅ +22 dBm з власної мережі живлення |
| Знання uplink topology | ❌ Soldier має бути topology-agnostic | ✅ Queen вже є topology-aware |
| OTAA join state + FCntUp counter persistence | ❌ Cold sleep STOP2 ускладнює state mgmt | ✅ Завжди живий під час кризи |

### Умови активації Fallback

Queen переходить у Helium режим автоматично коли:
1. Власний Starlink/LTE-M uplink fail після N retry (`L1 → L2` exhausted)
2. Queen-to-Queen LoRa backhaul (SF12) не знаходить online-сусіда у радіусі 5–15 км
3. CIFO + Flash Ring Buffer fill > 50% (загроза втрати даних, якщо все ще нема uplink)

```c
// firmware/queen/main.c — пропозиція ARCH.34
#define HELIUM_FALLBACK_THRESHOLD_MIN  30   // хв без uplink перед активацією
#define HELIUM_PAYLOAD_AGGREGATE_MAX   11   // байт корисного payload у LoRaWAN frame
#define HELIUM_BLIND_WINDOW_MAX_MS     20000  // верхній ліміт сліпоти (< IWDG ~26.6 с)

if (uplink_down_minutes >= HELIUM_FALLBACK_THRESHOLD_MIN &&
    q2q_backhaul_unavailable &&
    buffer_fill_pct >= 50) {
    // Стиснути batch до lambda-summary (ARCH.22) для вписування в обмежений LoRaWAN payload
    HAL_IWDG_Refresh(&hiwdg);                           // refresh ДО входу в сліпу зону
    queen_helium_lorawan_uplink(aggregated_lambda_summary, count);  // multi-channel hop, OTAA
    Radio_Reinit_RawLoRa_868MHz();                      // повернути PHY у raw LoRa P2P 868.0 MHz, AES-128-ECB (post-ARCH.42)
    Radio.Rx(LORA_RX_INFINITE);                         // одразу примусово відкрити RX-вікно
    HAL_IWDG_Refresh(&hiwdg);                           // та одразу після виходу
}
```

> **🔴 Hard Rule (Radio-blindness mitigation, ARCH.34):**
> Будь-який виклик `queen_helium_lorawan_uplink()` ОБОВ'ЯЗКОВО супроводжується:
> 1. **Pre-flight IWDG refresh** + захоплення `helium_session_start_tick = HAL_GetTick()`.
> 2. **Multi-channel hopping** Helium-сесії на каналах 868.1/868.3/868.5 МГц (LoRaWAN MAC), під час якої raw-LoRa preamble на 868.0 МГц апаратно не детектується — будь-який панічний пакет від Soldier (chainsaw alert) втрачається.
> 3. **Жорстка post-condition:** одразу після `LoRaMacMlmeRequest/MCPS` (або при таймауті) виклик `Radio_Reinit_RawLoRa_868MHz()` → `Radio.SetChannel(868000000)` → `Radio.SetModem(MODEM_LORA)` → `Radio.Rx(LORA_RX_INFINITE)`.
> 4. **Бюджет сліпоти:** `helium_session_elapsed = HAL_GetTick() - helium_session_start_tick` має бути `< HELIUM_BLIND_WINDOW_MAX_MS (20 с)`. Перевищення → форсований hardware reset через IWDG (~26.6 с), оскільки кластер краще перезавантажити, ніж довго не слухати.
> 5. **AES контекст (post-ARCH.42):** Helium uplink використовує LoRaWAN AES-128 CMAC/CTR (інший ключ — `AppSKey`/`NwkSKey`). Наш raw LoRa тепер також AES-128-ECB (ARCH.42 Variant B). Після виходу з Helium-сесії `hcryp` має бути перевипадково ініціалізований у `CRYP_KEYSIZE_128B` + `CRYP_AES_ECB` режим з нашим LoRa-ключем (`aes_key[4]`) для `radio_decrypt_lora()`. Спрощений context-switch — обидві сесії на тій самій key-size.
>
> Втрата chainsaw-пакета у Helium-вікні — прийнятний ризик (Edge Data Fusion агрегує lambda-summary, а Soldier ретрансмітить панік-пакет з TTL=5 reflex broadcast). Цей risk acceptance задокументований як ALARP — At-Least-As-Reasonably-Practical mitigation: коротке вікно (≤ 20 с) + soldier-side TTL retry + IWDG fallback.

### Економіка Helium

- **Вартість:** кожен переданий LoRaWAN frame (Data Credit, DC) = $0.00001 USD
- **Оплата:** з Treasury DAO — Queen, що звертається до Helium, оплачує DC токенами IOT з гаманця кластера
- **Формат пакету:** агрегований lambda-summary 11 байт замість повного 21-байтного Lorenz payload (ARCH.22 Edge Data Fusion). 1 LoRaWAN frame несе summary 50+ Soldier'ів за останні хвилини.

### Що потрібно для реалізації

| Крок | Дія | Де |
|------|-----|----|
| LoRaWAN MAC-stack | Інтегрувати LoRaMac-node (Semtech BSD-3) у Queen firmware | `firmware/queen/lorawan/` (новий) |
| DevEUI / AppEUI / AppKey | Зареєструвати **кожну Queen** (не Soldier!) у [Helium Console](https://console.helium.com/) | Helium |
| HTTP Integration | Налаштувати webhook → `https://api.silkennet.com/api/v1/telemetry/helium` | Helium Console |
| Rails endpoint | `POST /api/v1/telemetry/helium` → `UnpackHeliumLambdaSummaryWorker` (HMAC-signed) | Rails API |
| BOM | Queen Helium credentials у новій моделі `GatewayLoraWanCredentials` (AR Encryption) | Backend |
| OTAA join state | Persistent зберігання у Queen Flash (FCntUp counter survives reboot) | `firmware/queen/main.c` |

### Статус Helium Fallback

| Компонент | Стан |
|-----------|------|
| Концепт і архітектура (Queen-side LoRaWAN) | ✅ Визначено (правка 2026) |
| LoRaWAN MAC-stack у Queen firmware | 🔴 Не реалізовано (ARCH.34) |
| Rails endpoint `/api/v1/telemetry/helium` | 🔴 Не реалізовано |
| Реєстрація Queen у Helium Console | 🔴 Не виконано |
| GatewayLoraWanCredentials model | 🔴 Не створено |
| Soldier-side `helium_compat_emit()` (попередній план) | ❌ **Відкинуто** — фундаментально несумісно з flash/RAM/topology constraints STM32WLE5JC у Soldier |

> **Стратегічна цінність:** Helium перетворює систему на фізично невбивану мережу. Навіть якщо всі власні Starlink-канали Queen упадуть одночасно з Q2Q backhaul — Queen продовжуватиме викидати агрегований lambda-summary через чужі Helium hotspot-и. Для pitch deck: _"The forest cannot go dark — even when our own sky falls, the Helium hotspots of strangers keep the canopy alive."_

---

## 🧾 7. BOM Королеви

| # | Компонент | Специфікація | Фаза | Статус |
|---|-----------|-------------|------|--------|
| 1 | **STM32WLE5JC** (LoRa-E5 Mini, Seeed Studio) | ARM Cortex-M4 + SX1262, 868 МГц, 256KB Flash | 1/2.5/3 | ✅ |
| 2 | **SIM7070G** | LTE-M / NB-IoT / GNSS, UART AT, 3.7V | 1/2.5 | ✅ Підтверджено |
| 3 | **Starlink Mini** | LEO satellite terminal, DC 12–48V, 20–40W | 3 only | 📋 Заплановано |
| 4 | **ESP32-S3** (WiFi co-processor для Starlink Mini) | 240 МГц, WiFi 802.11n, UART | 3 only | ⚠️ Не реалізовано |
| 5 | **Сонячна панель** | Monocrystalline, 50W (Phase 1/2.5) / 100W (Phase 3 winter) | 1/2.5/3 | ✅ Архітектурно |
| 6 | **MPPT контролер** | Victron SmartSolar MPPT 75/15 (рекомендовано) | 1/2.5/3 | 🟡 Модель не зафіксована |
| 7 | **LiFePO4 акумулятор** | 12V / 20Ah (Phase 1/2.5), 40Ah (Phase 3 winter) | 1/2.5/3 | 🟡 Ємність уточнюється |
| 8 | **BMS** | 12V / 20А continuous / 50А peak, температурний захист | 1/2.5/3 | 🟡 Модель не зафіксована |
| 9 | **DC-DC buck 12V→3.7V** | ≥3А continuous, ≥5А peak | 1/2.5 | ✅ Архітектурно |
| 10 | **DC-DC buck 12V→3.3V** | ≥500 мА | 1/2.5/3 | ✅ Архітектурно |
| 11 | **LTE-M / NB-IoT антена** | Wideband Cellular **700–2700 МГц** (покриває Kyivstar B1/B3/B7/B8/B20). Зовнішня SMA, IP67. **БЕЗ суміщення з 868 МГц LoRa** — окремі чіпи (STM32WLE5JC vs SIM7070G), окремі RF-порти. Опційно: LTE+Active GNSS combo (Taoglas FXUB63, Pulse W3007) — додає GPS L1 1575 МГц для PPS time-sync SIM7070G. Раніше «868/LTE-M dual-band» — **виключено** (поганий VSWR на вузькому 868, низьке gain). | 1/2.5 | ✅ Архітектурно (REVISED 2026-05-16) |
| 12 | **LoRa антена** | 868 МГц **tuned** (вузькодіапазонна, 863–870 EU ISM), 5 dBi Fiberglass collinear omni (Mobilemark OD8-868, Taoglas ALL.4101 або еквівалент). Зовнішня SMA, IP67. Призначена для пробивання вологого лісу 150+ м до Soldiers. **НЕ використовувати dual-band/wideband** — VSWR > 2.5 на 868, втрата ~3-5 дБ EIRP → втрата покриття. | 1/2.5/3 | ✅ Архітектурно |
| 13 | **IP67 корпус** | ABS/PC + ущільнення, ≥2.5L | 1/2.5/3 | 📋 Не специфіковано |
| 14 | **SWD програматор** | ST-LINK-V3MINIE | — | ✅ |
| 15 | **UART адаптер** | FT232RL, 3.3V режим | — | ✅ |
| 16 | **SPI NOR Flash** (ARCH.35) | Winbond **W25Q32JV** (4 MB, SPI, SOIC-8), 100k erase cycles | 1/2.5/3 | 🟡 Заплановано — overflow tier для CIFO; ~$0.50/од; 190k+ telemetry slots; ~10 мА × 0.7 мс/page write |
| 17 | **C_BULK (SIM7070G VBAT tank)** | 470 µF / 6.3V / aluminum polymer, ESR ≤ 15 мΩ (Panasonic EEFCX0J471R або Kemet T520B477M006ATE015) | 1/2.5 | 🔴 **Обов'язково** — без нього brownout reboot SIM7070G при 2А LTE-M burst (§2.2.1) |
| 18 | **C_MID (SIM7070G VBAT)** | 100 µF / 25V / X7R / 1210 (Murata GRM32ER71E107K) | 1/2.5 | 🔴 Обов'язково — С_eff ≈ 85 µF після DC bias derating |
| 19 | **C_HF1 (SIM7070G VBAT)** | 10 µF / 25V / X7R / 0805 | 1/2.5 | 🔴 Обов'язково |
| 20 | **C_HF2 + C_RF (SIM7070G VBAT)** | 100 nF / 50V / X7R / 0402 + 33 pF / 50V / NP0 / 0402 | 1/2.5 | 🔴 Обов'язково — HF фільтр + RF-burst guard |
