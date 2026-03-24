# 03_02: Queen Gateway Firmware (LoRa RX → Dedup → CIFO → SIM7070G TX)

**Модуль:** 03_02 — Queen Gateway Firmware (STM32WLE5JC + SIM7070G)
**Пов'язані модулі:** [03_01 Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) · [03_05 Hardware AES256 and Security](03_05_Hardware_AES256_and_Security) · [04_02 Business Logic and Services](04_02_Business_Logic_and_Services) · [05_02 Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline)
**Поточний TRL:** 6 (C-код шлюзу написаний, 59 host-based тестів проходять, але SSOT взаємодії з мережею відсутня)
**Цільовий TRL:** 7 (Повна алгоритмічна прозорість маршрутизації та кешування)
**Статус Аудиту:** Reverse Shaping Cycle 1 — документування поточного стану ("як є") без рефакторингу коду

> **⚠️ SSOT Sync:** Цей документ синхронізовано з `firmware/queen/main.c` (801 рядків) та `firmware/test/test_queen_logic.c` (1337 рядків) станом на 2026-03-24. Всі 59 queen-specific тестів проходять (`make -C firmware/test queen`). Виявлені блокери задокументовані в розділі 🛑. Жодного рефакторингу не виконувалось.

---

## 🎯 Мета (Objective)

Зафіксувати повний алгоритм роботи вузла **Queen** (шлюз-агрегатор на базі STM32WLE5JC + модем SIM7070G) — від прийому зашифрованого LoRa-пакета від Солдата до відправки бінарного батча на Rails-бекенд через CoAP/UDP. Документ визначає механізм дедуплікації пакетів (CIFO EdgeCache), алгоритм евікції, логіку OTA-бродкасту та повний цикл взаємодії з GSM-модемом.

> Цей документ **не** рефакторить код. Він фіксує "як є" — включаючи всі відомі ризики та відкриті блокери.

> **Критична залежність:** Королева є єдиною точкою виходу ZK-пакетів у Proof of Growth Pipeline (05_02). Втрата пакетів телеметрії на рівні Королеви → ZK-proof не формується → мінтинг SCC блокується → токеноміка руйнується.

---

## ✅ Статус (Status)

| Компонент | Стан |
|-----------|------|
| **LoRa RX (OnRxDone ISR → main loop)** | ✅ Реалізовано (`firmware/queen/main.c`) |
| **AES-256-ECB decrypt (HAL hardware)** | ✅ Реалізовано (апаратний CRYP модуль) |
| **CIFO EdgeCache (50 слотів)** | ✅ Реалізовано (`Process_And_Cache_Data`) |
| **Priority-Aware CIFO Eviction** | ✅ Виправлено (критичні записи захищені) |
| **Flush trigger (≥45 entries OR 1 год)** | ✅ Реалізовано з HRNG-джиттером |
| **AES-256-CBC batch encrypt (HRNG IV)** | ✅ Реалізовано (`Flush_Cache_To_Rails`) |
| **CoAP PUT через SIM7070G AT-команди** | ✅ Реалізовано (hex-рядок over UART) |
| **ECB mode restore після CBC flush** | ✅ Виправлено (без цього LoRa decrypt руйнується) |
| **OTA Broadcast (Reflex Shot)** | ✅ Реалізовано (16-байтний чанк після кожного RX) |
| **OTA Assembly від CoAP Downlink** | ✅ Реалізовано (bitmap dedup, RAM assembly) |
| **Actuator Command Dedup (DJB2 Ring)** | ✅ Реалізовано (16-слотний кільцевий буфер) |
| **Queen Health Sentinel (DID=0)** | ✅ Виправлено (власний health packet у батч) |
| **RSSI Clamp (int16 → int8)** | ✅ Виправлено (SX1262 може давати < -128 dBm) |
| **Thundering Herd Jitter (HRNG)** | ✅ Виправлено (0–60 секунд рандомне зміщення) |
| **AT Command Timeout (blind delay)** | 🔴 BLOCKER (немає парсингу відповіді модему) |
| **Hardcoded AES Key у Flash** | 🔴 BLOCKER (єдиний ключ на всю мережу) |
| **Queen UID hardcoded "QUEEN-001"** | 🔴 BLOCKER (неможливий уніфікований флешинг) |
| **Error_Handler без IWDG у Queen** | 🟡 OPEN (вічний цикл при HardFault) |
| **No CoAP retry logic** | 🟡 OPEN (ACK miss → дані втрачено) |
| **CMD_DECRYPT_BUF_SIZE розбіжність** | 🟡 OPEN (544 у firmware, 96 у тестах) |
| **Host-based Tests (59 для Queen)** | ✅ Всі проходять (`make -C firmware/test queen`) |

---

## 🛑 Блокери (Blockers / Needs Action)

> Цей розділ є виходом аудиту "Reverse Shaping". Жодного рефакторингу не виконувалось — тільки виявлення.

### 🔴 BLOCKER-1: Hardcoded AES-256 Key у Flash-пам'яті

**Статус:** Відкрито. Критичний ризик безпеки для масового виробництва.
**Файл:** `firmware/queen/main.c:65-66`

```c
// Однаковий ключ у ВСІХ вузлах мережі Silken Net
uint32_t aes_key[8] = {0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
                       0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D};
```

**Ризики:**
1. **Єдина точка відмови:** Фізичний злам однієї Королеви → компрометація всієї мережі LoRa.
2. **JTAG/SWD читання Flash:** Без активованого RDP Level 2 ключ тривіально витягується.
3. **Неможливість ротації без перепрошивки:** При компрометації треба рефлешити всі вузли.

**Необхідна дія:**
- Провізіонувати унікальний ключ на кожну Королеву через `POST /api/v1/provisioning/register` (Factory Flashing).
- Активувати RDP Level 2 як фінальний крок флешингу (блокує JTAG назавжди).
- Перенести ключ у захищений регіон Flash або окремий secure element.

**Блокує:** Factory Flashing, масове виробництво, безпеку мережі.

---

### 🔴 BLOCKER-2: AT Command Blocking — Queen сліпа 2 секунди

**Статус:** Відкрито. Архітектурна проблема CoAP uplink.
**Файл:** `firmware/queen/main.c:563`

```c
// Queen не може прийняти жодного LoRa-пакета під час цієї паузи
HAL_Delay(2000); // Чекаємо ACK від сервера
```

**Ризики:**
1. SX1262 LoRa FIFO — 256 байтів. При 16-байтних пакетах і 50+ деревах, що прокидаються одночасно, overflow FIFO за 2 секунди гарантований.
2. Втрачені пакети не відновлюються — немає ARQ між Soldier і Queen.
3. Під час пожежі Queen може пропустити emergency TinyML-пакети від Солдатів саме в цей момент.

**Додатково:** Уся функція `SIM7070_SendATCommand` є blocking:
```c
void SIM7070_SendATCommand(char* command, uint32_t delay_ms) {
    HAL_UART_Transmit(&huart1, (uint8_t*)command, strlen(command), 1000);
    HAL_Delay(delay_ms); // Чекаємо відповідь (OK) — але не читаємо її!
}
```
Відповідь модему (`OK` / `ERROR`) **ніколи не парситься**. Навіть якщо модем повернув `ERROR`, Королева продовжує відправку наступних AT-команд.

**Необхідна дія:**
- Переписати `Flush_Cache_To_Rails()` на UART interrupt-driven (DMA UART + callback).
- Відправку CoAP виконувати асинхронно, не блокуючи головний цикл.
- Реалізувати парсинг відповіді `OK`/`ERROR` від SIM7070G.

**Блокує:** Надійність Queen в умовах щільного LoRa-трафіку, Emergency Alerting.

---

### 🔴 BLOCKER-3: Queen UID — статичний рядок у Flash

**Статус:** Відкрито. Блокує масштабування мережі Queens.
**Файл:** `firmware/queen/main.c:71`

```c
const char queen_uid[] = "QUEEN-001"; // Hardcoded для кожної одиниці
```

**Ризики:**
1. Кожна Королева потребує окремо скомпільованої прошивки — неможливий єдиний бінарний образ для заводського флешингу.
2. При OTA-оновленні Королеви UID може бути перезаписаний (якщо OTA торкається цього регіону Flash).
3. Сервер ідентифікує шлюз за UID в CoAP URI-Path `/telemetry/batch/<queen_uid>` — дублі UID призводять до плутанини даних.

**Необхідна дія:**
- Зберігати `queen_uid` в окремому захищеному регіоні Flash (User Sector) або EEPROM-емуляції.
- Провізіонувати через `POST /api/v1/provisioning/register` (той самий механізм, що і для Soldiers).

**Блокує:** Уніфікований Factory Flashing, масштабування мережі Queens.

---

### 🟡 BLOCKER-4: Starlink Latency Gap

**Статус:** Відкрито. Середня латентність Starlink Direct-to-Cell — 600–2400 ms.
**Файл:** `firmware/queen/main.c:542`

```c
SIM7070_SendATCommand("AT+CCOAPNEW=\"coap://api.silkennet.com:5683\"\r\n", 1000);
```

`HAL_Delay(1000)` після `AT+CCOAPNEW` — timeout для встановлення CoAP-сесії. Для Starlink це може бути недостатньо. Аналогічно `HAL_Delay(500)` після `AT+CCOAPDEL` і `HAL_Delay(2000)` для ACK.

**Необхідна дія:**
- Замінити фіксований `HAL_Delay` на polling UART RX з перевіркою `OK` відповіді від модему.
- Збільшити timeout до 5000 ms або реалізувати retry-логіку з exponential backoff.

**Блокує:** Стабільність CoAP uplink через Starlink (основний backhaul канал).

---

### 🟡 BLOCKER-5: Error_Handler без IWDG та без механізму відновлення

**Статус:** Відкрито. Системна вразливість при HardFault в Production.
**Файл:** `firmware/queen/main.c:792`

```c
void Error_Handler(void) {
  __disable_irq();
  while (1) {}  // Вічний цикл — єдиний вихід це фізичний reset
}
```

**Різниця від Soldier:** Soldier має IWDG (апаратний watchdog), який автоматично перезавантажує MCU через ~26 секунд. **Queen не має IWDG** в ініціалізації (`main.c` не містить `MX_IWDG_Init`). При HardFault Queen "заморожується" назавжди до фізичного перезапуску.

**Необхідна дія:**
- Додати IWDG в Queen firmware або явно викликати `NVIC_SystemReset()` в `Error_Handler`.
- Додати `HAL_IWDG_Refresh` в головний цикл для автовідновлення при зависанні.

**Блокує:** Autonomous 24/7 operation без людського втручання в Production.

---

### 🟡 BLOCKER-6: Відсутність Retry-логіки для CoAP flush

**Статус:** Відкрито. Архітектурна проблема надійності uplink.

Після `AT+CCOAPSEND` Queen виконує `HAL_Delay(2000)` і вважає відправку успішною. Відповідь модему не аналізується. Якщо:
- Starlink з'єднання відсутнє
- Сервер повернув CoAP error code
- Модем повернув `ERROR`

Весь кеш (до 50 записів, ~24 дерева × ~1 год даних) **безповоротно втрачається** — після `Flush_Cache_To_Rails()` виконується `cache_count = 0` і всі `is_active = 0`.

**Необхідна дія:**
- Зберігати батч у persistent буфері (Flash або EEPROM-емуляція) до підтвердження ACK.
- Або реалізувати подвійну буферизацію: flush → передача → при помилці → retry з тим самим буфером.

**Блокує:** Надійність Proof of Growth pipeline (втрачені пакети → пропущені growth_points → недонарахування SCC).

---

### 🟡 BLOCKER-7: CMD_DECRYPT_BUF_SIZE розбіжність між firmware та тестами

**Статус:** Відкрито. Потенційна прогалина в тестовому покритті.
**Файли:** `firmware/queen/main.c:122` vs `firmware/test/test_queen_logic.c:21`

```c
// queen/main.c — реальний firmware:
#define CMD_DECRYPT_BUF_SIZE 544  // 512 OTA payload + 5 header + 2 CRC + 16 AES padding + 9 margin

// test_queen_logic.c — тест:
#define CMD_DECRYPT_BUF_SIZE  96  // Тільки CMD (актуаторні команди ≤96 байт)
```

**Ризики:**
- OTA downlink гілка (`Handle_CoAP_Command` → OTA path) з великим `aligned` (≥512 байт) не покривається unit-тестами на x86.
- Зміна константи в одному файлі без синхронізації другого → тиха розбіжність.

**Необхідна дія:**
- Уточнити `CMD_DECRYPT_BUF_SIZE` в тесті або розділити на `CMD_MAX` та `OTA_MAX`.
- Додати тести для OTA downlink з payload ≥512 байт.

**Блокує:** Повнота тестового покриття OTA downlink шляху.

---

### 🟡 BLOCKER-8: HRNG Fallback до HAL_GetTick() для CBC IV

**Статус:** Відкрито. Потенційне послаблення криптографічного захисту batch.
**Файл:** `firmware/queen/main.c:516-519`

```c
if (HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK) {
    /* Fallback: якщо HRNG не відповідає */
    batch_iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL);
}
```

`HAL_GetTick()` повертає кількість мілісекунд від старту. Після blackout усі Королеви мають однаковий `HAL_GetTick()` ~ 0. При однаковому IV + однаковому ключі → однаковий шифротекст для різних шлюзів → CBC pattern analysis можливий.

**Необхідна дія:**
- Використовувати STM32 TRNG (справжній апаратний RNG від теплового шуму) як первинне джерело.
- Якщо HRNG недоступний — застосувати комбінований seed: `tick XOR uid XOR uptime_counter`.

**Блокує:** Криптографічна стійкість батчів при масовому blackout-відновленні.

---

### 🟢 INFO: Зафіксовані та Виправлені Ризики (Closed)

Наступні ризики виявлено та виправлено безпосередньо в C-коді:

| # | Ризик | Серйозність | Статус |
|---|-------|-------------|--------|
| R-01 | ECB Mode не відновлювався після CBC flush (LoRa decrypt → сміття) | 🔴 | ✅ Виправлено: `hcryp.Init.Algorithm = CRYP_AES_ECB` в `Flush_Cache_To_Rails` та `Handle_CoAP_Command` |
| R-02 | CIFO Blind Spot (critical fire trees evicted by worst RSSI) | 🟠 | ✅ Виправлено: priority-aware eviction — `bio_status != 0` захищений |
| R-03 | RSSI Truncation: `(int8_t)rssi` при rssi < -128 → UB, `+126` | 🟡 | ✅ Виправлено: clamp `[-128, 127]` в `OnRxDone` |
| R-04 | RSSI Negation UB: `(uint8_t)(-rssi)` при rssi == -128 | 🟡 | ✅ Виправлено: `(uint8_t)(-(int16_t)rssi)` в `Flush_Cache_To_Rails` |
| R-05 | Queen Health Blind Spot (шлюз не звітував про власний стан) | 🟠 | ✅ Виправлено: DID=0 sentinel packet перед кожним flush |
| R-06 | Thundering Herd (всі Королеви флашать одночасно після blackout) | 🟠 | ✅ Виправлено: HRNG jitter 0–60 секунд, перегенерується після кожного flush |
| R-07 | OTA chunk underflow: `pending_ota_size - offset` при `offset >= size` | 🟠 | ✅ Виправлено: bounds check `offset < pending_ota_size` |
| R-08 | OTA chunk index >= OTA_MAX_CHUNKS → bitmap overflow | 🔴 | ✅ Виправлено: guard `chunk_index >= OTA_MAX_CHUNKS → return` |
| R-09 | OTA duplicate chunk → premature broadcast activation | 🔴 | ✅ Виправлено: 16-bit `ota_chunk_bitmap` для дедуплікації чанків |
| R-10 | encrypted_batch_buffer на стеку (2064 байти, Stack overflow ризик) | 🔴 | ✅ Виправлено: переміщено до `static uint8_t` |
| R-11 | ECB для CoAP batch (однакові блоки → однаковий шифротекст) | 🔴 | ✅ Виправлено: CBC з HRNG IV для batch шифрування |

---

## 🗺️ Архітектура: Повний Data Flow

```
╔══════════════════════════════════════════════════════════════════════════╗
║  QUEEN (STM32WLE5JC + SIM7070G)  — Основний цикл (ніколи не спить)     ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  [INIT]                                                                  ║
║    HAL_Init → SystemClock_Config → MX_GPIO_Init                         ║
║    MX_USART1_UART_Init (115200 baud → SIM7070G)                         ║
║    MX_SUBGHZ_Init → MX_CRYP_Init (AES-256-ECB)                         ║
║    Radio.Init → Radio.SetChannel(868 MHz)                                ║
║    memset(forest_cache) → memset(cmd_dedup_ring)                         ║
║    SIM7070_SendATCommand("AT\r\n", 500ms)                               ║
║    SIM7070_SendATCommand("AT+CNMP=38\r\n", 1000ms)  ← LTE-M mode       ║
║    Radio.Rx(LORA_RX_INFINITE)  ← Відкриваємо вуха                      ║
║    current_jitter = HRNG() % 60000  ← Thundering Herd prevention        ║
║                                                                          ║
║  [MAIN LOOP]                                                             ║
║    ┌─────────────────────────────────────────────────────────┐          ║
║    │  if (lora_rx_flag == 1)                                 │          ║
║    │    ├── HAL_CRYP_Decrypt(ECB, incoming_lora[16])        │          ║
║    │    │     → decrypted_payload[16]                        │          ║
║    │    │                                                     │          ║
║    │    ├── [OTA REFLEX SHOT, if ota_is_active]             │          ║
║    │    │     Build chunk: [0x99][idx:2][total:2][data:11]  │          ║
║    │    │     HAL_CRYP_Encrypt(ECB) → Radio.Send(16 bytes)  │          ║
║    │    │     HAL_Delay(60ms) → current_ota_chunk_idx++      │          ║
║    │    │                                                     │          ║
║    │    ├── Extract DID (decrypted_payload[0..3])           │          ║
║    │    │                                                     │          ║
║    │    ├── Process_And_Cache_Data(uid, payload, rssi)      │          ║
║    │    │     1. DEDUP: знайти UID → оновити payload+RSSI   │          ║
║    │    │     2. INSERT: вільний слот → cache_count++        │          ║
║    │    │     3. CIFO EVICT: evict non-critical worst RSSI  │          ║
║    │    │                                                     │          ║
║    │    └── lora_rx_flag=0 → Radio.Rx(LORA_RX_INFINITE)    │          ║
║    │                                                         │          ║
║    │  if (cache_count >= 45 OR time >= 1h + jitter)         │          ║
║    │    ├── Inject Queen Health Sentinel (DID=0)            │          ║
║    │    ├── Flush_Cache_To_Rails()                          │          ║
║    │    │     Pack → CBC Encrypt → CoAP PUT                │          ║
║    │    └── Regenerate jitter (HRNG)                        │          ║
║    └─────────────────────────────────────────────────────────┘          ║
║                                                                          ║
╠══════════════════════════════════════════════════════════════════════════╣
║  CoAP/UDP → port 5683 → lib/daemons/coap_listener.rb                   ║
║  URI-Path: /telemetry/batch/<queen_uid>                                  ║
╚══════════════════════════════════════════════════════════════════════════╝
         │
         ▼
   Rails Backend (UnpackTelemetryWorker → TelemetryUnpackerService)
```

**Ключовий інваріант:** `LoRa RX → Dedup → CIFO Cache → SIM7070G CoAP TX`

---

## 📡 1. LoRa Reception та ISR

### OnRxDone (Апаратне переривання)

```c
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr)
{
    if (size == 16) {  // Очікуємо рівно 16 байт (повний AES block)
        memcpy((void*)incoming_lora_payload, payload, 16);
        // [FIX: RSSI Truncation] SX1262 може повернути RSSI < -128
        if (rssi < -128) rssi = -128;
        if (rssi > 127)  rssi = 127;
        current_rssi = (int8_t)rssi;
        lora_rx_flag = 1; // Сигналізуємо головному циклу
    }
    // Пакети != 16 байт мовчки відкидаються (не є LoRa від Soldier)
}
```

**Параметри прийому:**
| Параметр | Значення | Опис |
|----------|----------|------|
| Частота | 868 MHz | Регіон ЄС/Україна |
| Розмір пакета | 16 байт | Повний AES-256 блок |
| Таймаут RX | `LORA_RX_INFINITE = 0xFFFFFF` | Нескінченне очікування |
| UART baud | 115200 | SIM7070G модем |

**Volatile-семантика:** `incoming_lora_payload` та `lora_rx_flag` оголошені `volatile`, бо записуються в ISR, читаються в main loop. `(void*)` cast безпечний: `lora_rx_flag` серіалізує доступ ISR→main.

---

## 🗄️ 2. CIFO EdgeCache (Алгоритм дедуплікації та кешування)

### Структура даних

```c
#define CACHE_MAX_ENTRIES 50

typedef struct {
    uint32_t uid;        // DID дерева (4 байти)
    uint8_t payload[16]; // Останні розшифровані дані
    int8_t  rssi;        // Сила сигналу (dBm)
    uint8_t is_active;   // 1 = слот зайнятий
} EdgeCache;

EdgeCache forest_cache[CACHE_MAX_ENTRIES]; // 50 × 22 байти = 1100 байт
uint8_t cache_count = 0;
```

### Алгоритм `Process_And_Cache_Data(uid, payload, rssi)`

```
Крок 1 — ДЕДУПЛІКАЦІЯ:
  Пошук uid в усіх is_active слотах.
  Якщо знайдено → оновити payload + rssi → return.
  (Найсвіжіші дані завжди перемагають старі)

Крок 2 — ВСТАВКА:
  if (cache_count < 50):
    Знайти перший is_active==0 слот → записати → cache_count++ → return.

Крок 3 — CIFO Priority-Aware EVICTION (кеш повний):
  Мета: витіснити некритичне (homeostasis, bio_status==0) дерево з найгіршим RSSI.
  Fallback: якщо ВСІ записи критичні → витіснити абсолютно найгірший RSSI.

  bio_status = (payload[10] >> 6) & 0x03
    0 = homeostasis (кандидат на витіснення)
    1 = stress      (захищений)
    2 = anomaly     (захищений)
    3 = tamper      (захищений)
```

### Логіка евікції — псевдокод

```
best_evict_idx = -1,  best_evict_rssi = 127 (найгірший кандидат серед некритичних)
fallback_idx   =  0,  fallback_rssi   = 127 (найгірший серед усіх)

for i in 0..49:
  if NOT is_active[i]: continue  // [FIX: AUDIT] пропускаємо неактивні

  if rssi[i] < fallback_rssi:
    fallback_rssi = rssi[i]; fallback_idx = i

  if bio_status[i] == 0 AND rssi[i] < best_evict_rssi:
    best_evict_rssi = rssi[i]; best_evict_idx = i

evict_idx = (best_evict_idx >= 0) ? best_evict_idx : fallback_idx
// Перезаписуємо слот новим uid/payload/rssi (is_active вже = 1, cache_count не змінюється)
```

**Чому priority-aware важливо:** Без цього виправлення дерево на межі пожежі (найгірший RSSI = найслабший сигнал = найдальше від Queen) могло бути витіснено саме в момент критичного сигналу. Тепер такі записи захищені.

### Тригери Flush

| Умова | Деталь |
|-------|--------|
| **За кількістю** | `cache_count >= 45` (CACHE_MAX_ENTRIES − FLUSH_HEADROOM = 50 − 5) |
| **За часом** | `HAL_GetTick() − last_flush_time > 3,600,000 + current_jitter` |
| **Джиттер** | HRNG-based, 0–60,000 ms, перегенерується після кожного flush |

---

## 📦 3. Flush: Бінарна Упаковка та AES-CBC

### Крок 1: Binary Batch Pack (21 байт на запис)

```
Формат одного запису в binary_batch_buffer:
  [DID:4 bytes, big-endian]
  [RSSI:1 byte, inverted: -85 dBm → 85]
  [payload:16 bytes, decrypted sensor data]
  = 21 байт total

Максимум: 50 записів × 21 = 1050 байт
Buffer size: binary_batch_buffer[2048] — достатньо з запасом
```

**RSSI інверсія:** `(uint8_t)(-(int16_t)rssi)` — `int16_t` cast запобігає UB при rssi == −128 (мінімум int8_t).

### Крок 2: AES-256-CBC Encrypt

```
1. Padding: вирівнювання до 16 байт (нульовий pad)
2. Generate IV: HRNG (4 × uint32_t = 16 байт)
   Fallback при HRNG fail: HAL_GetTick() XOR (i * 0x5A5A5A5A)  ← BLOCKER-8
3. Switch CRYP: ECB → CBC з новим IV
4. Encrypt: HAL_CRYP_Encrypt(binary_batch_buffer, padded_size/4, output+16)
5. Prepend IV: encrypted_batch_buffer[0..15] = IV
6. Total: 16 (IV) + padded_size байт

static uint8_t encrypted_batch_buffer[2048 + 16];  ← static (не стек!)
```

### Крок 3: Restore ECB

```c
// [FIX: CRITICAL — ECB Restoration]
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);
// Без цього — всі наступні LoRa decrypt дають сміття
```

---

## 📱 4. SIM7070G Модем: Життєвий Цикл та AT-Команди

### Ініціалізація (один раз при старті)

| AT-команда | Затримка | Призначення |
|------------|----------|-------------|
| `AT\r\n` | 500 ms | Перевірка зв'язку з модемом |
| `AT+CNMP=38\r\n` | 1000 ms | Режим LTE-M only (відключає NB-IoT) |

### CoAP Flush Sequence (кожен flush)

```
1. AT+CCOAPNEW="coap://api.silkennet.com:5683"\r\n  (1000 ms)
   ↳ Відкриваємо CoAP сесію, session_id=0

2. AT+CCOAPSEND=0,2,"telemetry/batch/<queen_uid>",<size*2>,"<hex>"\r\n
   ↳ Method=2 (PUT), URI-Path визначає шлюз (вирішує Starlink NAT)
   ↳ Hex-рядок: 2 ASCII символи на байт, відправляється побайтово через HAL_UART_Transmit (10 ms/byte)
   ↳ Для 1066 байт (50 записів + IV): ~2132 ASCII символи, ~21 секунда UART TX  ← ⚠️

3. HAL_Delay(2000)  ← BLOCKER-2: Queen сліпа 2 секунди

4. AT+CCOAPDEL=0\r\n  (500 ms)
   ↳ Закриваємо сесію, звільняємо ресурси модему
```

**Важливо про URI-Path:** `/telemetry/batch/<queen_uid>` використовується замість IP-адреси, що вирішує проблему Starlink NAT та динамічних адрес. Сервер знаходить шлюз за UID, а не за IP.

### Відповіді модему (поточний стан — не парситься)

```c
void SIM7070_SendATCommand(char* command, uint32_t delay_ms) {
    HAL_UART_Transmit(&huart1, (uint8_t*)command, strlen(command), 1000);
    HAL_Delay(delay_ms); // Затримка замість парсингу відповіді  ← BLOCKER-2
}
```

**Реальні відповіді SIM7070G, які ігноруються:**
- `OK` — команда прийнята
- `ERROR` — помилка (не обробляється → дані втрачаються)
- `+CCOAPSEND: 0,1` — CoAP ACK отримано (не обробляється)

---

## 🔄 5. OTA Broadcast (Reflex Shot — LoRa Downlink до Солдатів)

### Механізм "Рефлекторного Пострілу"

Після отримання кожного LoRa-пакета від Солдата, Queen **негайно** відповідає OTA-чанком. Це працює тому що Солдат слухає ефір 500 ms після власного TX (Phase 4.5 в 03_01).

```
Солдат TX (16 bytes) → Queen OnRxDone ISR
  ↓
Queen: decrypt → [OTA REFLEX SHOT if ota_is_active]
  ↓
Build OTA chunk (16 bytes):
  [0]     = 0x99              ← OTA маркер
  [1-2]   = current_ota_chunk_idx (big-endian uint16)
  [3-4]   = total_chunks (big-endian uint16)
  [5-15]  = 11 байт mruby bytecode

HAL_CRYP_Encrypt(ECB) → Radio.Send(encrypted_ota, 16)
HAL_Delay(60ms)   ← час для фізичної передачі пакета
current_ota_chunk_idx++  → wrap to 0 after last chunk
```

**Математика чанків (LoRa downlink):**
- Корисне навантаження чанка: 11 байт (16 − 5 байт заголовка)
- Max bytecode розмір: 8192 байт (pending_ota_bytecode buffer)
- Max chunks (LoRa): `ceil(8192 / 11) = 745` ітерацій
- Кожен Солдат отримує наступний послідовний чанк при кожному своєму TX

### OTA Assembly (CoAP Downlink від Rails → RAM)

```
Rails → CoAP → Handle_CoAP_Command(payload, len):
  1. Мінімальна перевірка: len >= 32 (IV + 1 блок)
  2. Витягти IV з payload[0..15]
  3. Switch CRYP: ECB → CBC з IV
  4. HAL_CRYP_Decrypt → cmd_decrypt_buf[544]
  5. Restore ECB ← критично!

  Маршрутизація за маркером:
    if cmd_decrypt_buf starts "CMD:" → actuator command
    if cmd_decrypt_buf[0] == 0x99   → OTA downlink chunk

OTA Chunk Processing:
  chunk_index  = buf[1..2] (big-endian)
  total_chunks = buf[3..4] (big-endian)

  Guards:
    total_chunks == 0       → return  (invalid)
    chunk_index >= 16       → return  (bitmap overflow protection)
    aligned < 23            → return  (MISRA: мінімум header + AES block)
    offset + payload > 8192 → return  (buffer overflow protection)

  Dedup via bitmap:
    chunk_bit = 1 << chunk_index
    if (ota_chunk_bitmap & chunk_bit) → return (duplicate, ignore)
    ota_chunk_bitmap |= chunk_bit

  memcpy → pending_ota_bytecode[offset]
  ota_chunks_received++

  if (ota_chunks_received >= total_chunks):
    ota_chunk_bitmap = 0
    ota_chunks_received = 0
    ota_is_active = 1  ← запускаємо LoRa broadcast!
```

**Константи OTA:**
| Константа | Значення | Опис |
|-----------|----------|------|
| `OTA_MARKER` | `0x99` | Маркер OTA-пакета (перший байт) |
| `OTA_MAX_CHUNKS` | 16 | Максимум чанків від CoAP downlink |
| `MAX_OTA_CHUNK_PAYLOAD` | 512 байт | Макс. корисний payload на CoAP чанк |
| `pending_ota_bytecode` | 8192 байт | RAM-буфер збірки прошивки |
| `OTA_HEADER_SIZE` | 5 байт | 1 маркер + 2 index + 2 total |
| `OTA_CRC_SIZE` | 2 байти | CRC16-CCITT в кінці чанка |

---

## 🛡️ 6. Actuator Command Dedup (Idempotency Ring Buffer)

### Проблема, яку вирішує

`ActuatorCommandWorker` на Rails повторює відправку команди якщо ACK загубився. Без дедуплікації — клапан відкриється двічі.

### Механізм

```
Формат команди (plaintext після CBC decrypt):
  CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<IDEMPOTENCY_TOKEN>
  Приклад: CMD:OPEN:60:42:a1b2c3d4-e5f6-7890-abcd-ef1234567890

DJB2 Hash UUID токена (36 символів):
  h = 5381
  for c in token: h = h * 33 + c   ← 0 алокацій, детермінований

Ring Buffer cmd_dedup_ring[16]:
  cmd_dedup_idx  = поточна позиція запису (wraps mod 16)
  cmd_dedup_used = кількість заповнених слотів (≤ 16)

Cmd_Dedup_Check(hash):
  search ring → if found: return 1 (duplicate, ignore)
  ring[idx] = hash; idx = (idx+1) % 16
  return 0 (new, execute)
```

**RAM бюджет:** 16 × 4 (хеші) + 2 (індекси) = 66 байт.

**Eviction:** Ring buffer витісняє найстаріший запис при переповненні (FIFO). При 16 активних командах і 17-й новій — перша команда може бути ре-виконана. Прийнятно для IoT актуаторів.

---

## 👑 7. Queen Health Sentinel (DID = 0x00000000)

### Проблема

Без власного health packet сервер не знає стан шлюзу: чи жива Королева, скільки дерев вона бачить, яка завантаженість.

### Рішення

Перед кожним flush Королева інжектує власний пакет з `DID = 0x00000000` (sentinel):

```c
uint8_t queen_health[16] = {0};
// DID = 0x00000000 — зарезервований sentinel
// Bytes 4-5: uptime proxy (тік / 1000, wraps кожні ~65 секунд)
uint16_t uptime_sec = (uint16_t)(HAL_GetTick() / 1000);
queen_health[4] = (uint8_t)(uptime_sec >> 8);
queen_health[5] = (uint8_t)(uptime_sec & 0xFF);
// Byte 7: кількість дерев у кеші (навантаження)
queen_health[7] = cache_count;
// Byte 10: growth_points = cache_count (cap at 63)
queen_health[10] = (cache_count < QUEEN_HEALTH_GP_MAX) ? cache_count : QUEEN_HEALTH_GP_MAX;
Process_And_Cache_Data(0, queen_health, 0); // RSSI=0 (локальний пакет)
```

**Маршрутизація на сервері:** Backend `TelemetryUnpackerService` детектує `DID == 0` і направляє до `GatewayTelemetryWorker` замість створення `TelemetryLog`.

---

## 🔐 8. Шифрування: Режими та Переходи

| Шлях | Алгоритм | Режим | IV |
|------|----------|-------|----|
| Soldier → Queen (LoRa RX) | AES-256 | ECB | N/A (16-byte single block) |
| Queen → Rails (CoAP batch) | AES-256 | CBC | HRNG (prepended до ciphertext) |
| Rails → Queen (CoAP command) | AES-256 | CBC | Витягується з payload[0..15] |
| Queen → Soldier (OTA LoRa) | AES-256 | ECB | N/A |

### Критичний Transition Diagram

```
[Startup]
  CRYP = ECB (default)
      │
      ▼
[LoRa RX loop]
  HAL_CRYP_Decrypt(ECB) ← Soldier packets
      │
      │ Flush triggered
      ▼
[Flush_Cache_To_Rails]
  Switch → CBC (+ HRNG IV)
  HAL_CRYP_Encrypt(CBC) ← batch
  Switch → ECB ← [FIX R-01: MUST restore!]
      │
      ▼
[LoRa RX loop continues]
  HAL_CRYP_Decrypt(ECB) ← OK, mode restored
```

```
[CoAP Command arrives]
  Handle_CoAP_Command:
  Switch → CBC (+ IV from payload)
  HAL_CRYP_Decrypt(CBC) ← command
  Switch → ECB ← [FIX R-01: also here]
      │
      ▼
[LoRa RX continues correctly]
```

---

## 🧮 9. RAM Бюджет Королеви

| Змінна | Тип | Розмір | Призначення |
|--------|-----|--------|-------------|
| `aes_key[8]` | `uint32_t` | 32 B | AES-256 ключ (однаковий з Soldiers) |
| `forest_cache[50]` | `EdgeCache` | 1100 B | CIFO EdgeCache (50 слотів) |
| `binary_batch_buffer[2048]` | `uint8_t` | 2048 B | Бінарний буфер перед шифруванням |
| `encrypted_batch_buffer[2064]` | `uint8_t` | 2064 B | **static** (IV + зашифровані дані) |
| `pending_ota_bytecode[8192]` | `uint8_t` | 8192 B | RAM-буфер збірки OTA від Rails |
| `at_tx_buffer[256]` | `char` | 256 B | Формування AT-команд |
| `cmd_dedup_ring[16]` | `uint32_t` | 64 B | DJB2 хеші idempotency токенів |
| `cmd_decrypt_buf[544]` | `uint8_t` | 544 B | Decrypt buffer для CoAP команд/OTA |
| `incoming_lora_payload[16]` | `uint8_t` | 16 B | Сирий зашифрований пакет від ISR |
| `decrypted_payload[16]` | `uint8_t` | 16 B | Розшифрований пакет |
| **Разом** | | **~14.4 KB** | З 64 KB SRAM = 22% використання |

---

## 🔩 10. HAL Периферія Королеви

| Handle | Периферія | Призначення |
|--------|-----------|-------------|
| `huart1` | USART1 | SIM7070G модем (115200 baud) |
| `hsubghz` | SUBGHZ | LoRa трансивер SX1262 (868 MHz) |
| `hcryp` | AES | ECB для LoRa, CBC для CoAP батчів та команд |
| `hrng` | RNG | HRNG для CBC IV та Thundering Herd jitter |

**Примітка:** Queen **не має** ADC, TIM, IWDG, RTC — на відміну від Soldier. HRNG ініціалізується та де-ініціалізується "on-demand" (Wu-Wei підхід — нульове споживання між використаннями).

---

## 🧪 11. Тестове Покриття (Host-Based, x86)

```bash
make -C firmware/test queen    # 59 тестів, ~0.1 секунди
```

| Модуль | Тестів | Що покривається |
|--------|--------|-----------------|
| DJB2 Hash | 7 | Детермінізм, відомі значення, NUL-термінатор, UUID формат |
| Command Dedup Ring | 7 | New/duplicate, ring wrap, eviction, stress 100 |
| CIFO Cache | 13 | Insert, dedup, priority eviction (всі 4 bio_status), fallback, edge RSSI |
| Batch Packing | 8 | 21-байтний формат, ендіанність, RSSI -128, round-trip |
| OTA Chunk Builder | 6 | First/last chunk, reassembly, out-of-range index |
| OTA Assembly (CoAP→RAM) | 12 | Multi-chunk, duplicate ignore via bitmap, buffer overflow, invalid marker |
| RSSI Clamp | 8 | Normal, edge values, overflow proof, int16→int8 truncation demo |
| Queen Health Sentinel | 7 | DID=0, uptime packing, cache integration, dedup |
| ECB Restoration | 3 | CRYP mode state після CBC→ECB transition |
| HRNG IV Generation | 5 | All 4 words filled, 16-byte size, power mgmt deinit |
| CBC Command Decrypt | 3 | ECB restored після CBC decrypt, sequence correctness |
| **Всього** | **79** | *(включно з shared тестами; queen-specific: 59)* |

**Не покрито тестами (BLOCKER-7):**
- AT command response parsing (модем відповіді)
- CoAP retry logic при мережевих помилках
- OTA downlink з `aligned >= 544` (повний 512-байтний CoAP чанк в тесті)

---

## 🔗 Залежності

### Висхідні (Requires)

| Модуль | Статус | Деталь |
|--------|--------|--------|
| [03_01 Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | ✅ Синхронізовано | Soldier lifecycle, binary packet format, DID provisioning |
| [02_05 Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | — | Схема живлення Queen, антена SIM7070G |
| [03_05 Hardware AES256 and Security](03_05_Hardware_AES256_and_Security) | — | Деталі ключової інфраструктури |

### Низхідні (Blocks)

| Модуль | Чому блокується |
|--------|----------------|
| [05_02 Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Втрата пакетів на Queen → ZK-proof не формується → мінтинг SCC блокується |
| [04_02 Business Logic and Services](04_02_Business_Logic_and_Services) | `UnpackTelemetryWorker` очікує батч формату `[IV:16][CBC ciphertext]` |
| Factory Flashing | BLOCKER-1 (AES key) + BLOCKER-3 (Queen UID) блокують масове виробництво |

---

*Документ створено: 2026-03-24 | Автор: AI Agent (Copilot) | Issue: #187*
*Синхронізовано з: `firmware/queen/main.c` (801 рядків), `firmware/test/test_queen_logic.c` (1337 рядків)*
