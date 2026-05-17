# 03_02: Прошивка Шлюзу Королеви (LoRa RX → Dedup → CIFO → SIM7070G TX)

---

## 🎯 Мета

Зафіксувати повний алгоритм роботи вузла **Queen** (шлюз-агрегатор на базі STM32WLE5JC + модем SIM7070G) — від прийому зашифрованого LoRa-пакета від Солдата до відправки бінарного батча на Rails-бекенд через CoAP/UDP. Документ визначає механізм дедуплікації пакетів (CIFO EdgeCache), алгоритм евікції, логіку OTA-бродкасту та повний цикл взаємодії з GSM-модемом.

> **Критична залежність:** Королева є єдиною точкою виходу ZK-пакетів у Proof of Growth Pipeline (05_02). Втрата пакетів телеметрії на рівні Королеви → ZK-proof не формується → мінтинг SCC блокується → токеноміка руйнується.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — C-код шлюзу написаний
- **Пов'язані модулі:**
  - Життєвий Цикл Прошивки та DMA → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)
  - Апаратний AES-256 та Безпека → [`03_05_Hardware_AES256_and_Security`](03_05_Hardware_AES256_and_Security)
  - Бізнес-Логіка та Сервіси → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Proof of Growth Pipeline → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)

---

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
| **Hardcoded AES Key у Flash** | 🟡 BLOCKER (firmware fixed — `Load_AES_Key()`, needs factory pipeline + RDP L2) |
| **Queen UID hardcoded "QUEEN-001"** | ✅ Виправлено (Flash-based provisioning з fallback на STM32 HW UID) |
| **Error_Handler без IWDG у Queen** | ✅ Виправлено (IWDG додано з timeout ~26 с + refresh у main loop) |
| **No CoAP retry logic** | ✅ Виправлено (FW.9) — `SIM7070_SendATCommand_WithResponse`, max 3 retry, парсинг `OK`/`ERROR` |
| **CMD_DECRYPT_BUF_SIZE розбіжність** | ✅ Виправлено (тест синхронізовано: 96 → 544) |
| **HRNG Fallback → IV Reuse (CBC)** | ✅ Виправлено (fallback використовує djb2 STM32 HW UID XOR tick) |
| **OTA Broadcast Infinite Loop** | ✅ Виправлено (`ota_is_active = 0` розкоментовано після повного циклу бродкасту) |
| **Host-based Tests (59 queen-specific)** | ✅ Всі проходять (`make -C firmware/test queen`) |

---

## 🛑 Блокери

### 🔴 BLOCKER-1: Hardcoded AES-256 Key у Flash-пам'яті

**Статус:** Відкрито. Критичний ризик безпеки для масового виробництва.
> 🟡 Firmware part completed: `Load_AES_Key()` reads per-device key from Protected Flash Sector (0x0803E000). Hardcoded key removed. `Error_Handler()` if not provisioned. Залишається: factory flashing pipeline, RDP Level 2 activation.

**Файл:** `firmware/queen/main.c:81-82`

```c
// [FW.1] Hardcoded key removed. Key loaded from Protected Flash Sector via Load_AES_Key().
uint32_t aes_key[8] = {0};  // Overwritten by Load_AES_Key() before MX_CRYP_Init()
```

**Ризики:**
1. **~~Єдина точка відмови:~~** ✅ Firmware тепер підтримує per-device key (Flash-based). Залишається factory provisioning pipeline.
2. **JTAG/SWD читання Flash:** Без активованого RDP Level 2 ключ тривіально витягується.
3. **Неможливість ротації без перепрошивки:** При компрометації треба рефлешити всі вузли.

**Необхідна дія:**
- ~~Провізіонувати унікальний ключ на кожну Королеву через `POST /api/v1/provisioning/register` (Factory Flashing).~~ ✅ Firmware ready — `Load_AES_Key()` реалізовано.
- Активувати RDP Level 2 як фінальний крок флешингу (блокує JTAG назавжди).
- Перенести ключ у захищений регіон Flash або окремий secure element.

**Блокує:** Factory Flashing, масове виробництво, безпеку мережі.

---

### 🟡 BLOCKER-2: AT Command Blocking — Queen сліпа ~25 секунд під час flush

**Статус:** Частково виправлено — single-packet buffer overwrite закрито (FW.3, 2026-05-02). Повна async-переробка `Flush_Cache_To_Rails()` на UART DMA — відкрито.
**Файл:** `firmware/queen/main.c:805-870` (drain) + `firmware/queen/main.c:184-260` (ring buffer)

**Реальний час блокування під час flush (розрахунок для 50 записів):**

| Етап | Деталь | Час |
|------|--------|-----|
| `AT+CCOAPNEW` + delay | `SIM7070_SendATCommand(..., 1000)` | ~1.0 с |
| AT+CCOAPSEND заголовок | `HAL_UART_Transmit(..., 100)` | ~0.1 с |
| **UART hex TX** | 1072 байт × 2 ASCII символи × 10 ms/байт | **~21.4 с** |
| Завершення команди | 3 байти `\"\r\n` + `HAL_Delay(2000)` | ~2.1 с |
| `AT+CCOAPDEL` + delay | `SIM7070_SendATCommand(..., 500)` | ~0.5 с |
| **Разом** | | **~25.1 с** |

```c
// Hex TX: кожен байт окремим викликом, 10 ms timeout
for (int i = 0; i < total_size; i++) {
    snprintf(hex_byte, sizeof(hex_byte), "%02x", encrypted_batch_buffer[i]);
    HAL_UART_Transmit(&huart1, (uint8_t*)hex_byte, 2, 10); // ← 10 ms/byte
}
HAL_Delay(2000); // ← Чекаємо ACK — але не читаємо відповідь!
```

**Ризики (ескалація від "2 секунди" до "~25 секунд"):**

1. ✅ **Single-packet buffer overwrite — закрито (FW.3, 2026-05-02).** Раніше `incoming_lora_payload[16]` + однобітний `lora_rx_flag` — кожен новий ISR від `OnRxDone` мовчки переписував попередній голос. Тепер між ISR і main loop стоїть **FIFO ring buffer** (16 слотів × 17 байтів = 272 байти RAM, capacity = 15). ISR-side `LoRa_Rx_Ring_Push` атомарно додає голос; при переповненні рою інкрементує лічильник `lora_rx_drops` — жодна жертва не зникає у тиші. Main loop дренує весь ринг за одну ітерацію (`while (LoRa_Rx_Ring_Pop(...))`) перед перевіркою flush-таймера. 13 host-тестів покривають FIFO-семантику, переповнення, RSSI-clamp passthrough та симуляцію 25-секундного flush-сценарію (30 ISR-пакетів → 15 уцілілих + 15 видимих втрат). Single-producer/single-consumer інваріант + ARM Cortex-M4 атомарність 8-біт читання робить ринг lock-free.
2. **Emergency packet loss — суттєво пом'якшено.** До 15 emergency TinyML-сигналів за 25-секундне вікно тепер зберігаються; якщо рій кричить ще густіше — лічильник `lora_rx_drops` робить це видимим для backend gateway-телеметрії (наступний крок: експорт у queen_health sentinel-payload).
3. ✅ **Reflex `Radio.Rx()` після кожного дренованого пакета** — main loop викликає `Radio.Rx(LORA_RX_INFINITE)` всередині drain-петлі, після кожного pop'а. Жодного режиму Radio idle між пакетами.
4. **Відповідь модему частково парситься (FW.9).** `SIM7070_SendATCommand_WithResponse` шукає `OK`/`ERROR` у `Flush_Cache_To_Rails`, з `COAP_MAX_RETRIES=3` retry-логікою. Boot-time AT-команди (CNMP, CPSMS, CEDRXS) залишаються на blind delay — вони не у критичному 25-секундному вікні.

**Залишок роботи (наступна ітерація FW.3):**
- Переписати `Flush_Cache_To_Rails()` на UART DMA interrupt-driven (DMA UART + IDLE-line callback) — повна async, не блокуюча головний цикл.
- Експортувати `lora_rx_drops` у `queen_health` sentinel-payload (наразі — внутрішня метрика без backend-видимості).

**Блокує:** Часткове закриття — Queen більше не глуха в умовах щільного LoRa-трафіку (bursts ≤ 15 пакетів покриті ringom), Emergency Alerting суттєво підсилений. Повна async UART DMA — для full Mainnet-надійності при ≥ 16-пакетних bursts.

---

### ✅ BLOCKER-3: Queen UID — статичний рядок у Flash (Виправлено)

**Статус:** Виправлено. Flash-based provisioning реалізовано.
**Файл:** `firmware/queen/main.c`

**Реалізація:** Queen читає UID з виділеної сторінки Flash `0x0803F800` з перевіркою magic-маркера. При незаповненому Flash (значення `0xFFFFFFFF`) або невалідному маркері — генерує унікальний UID на основі апаратного STM32 UID (адреса `0x1FFF7590`) у форматі `"UNPROV-{8HEX}"`. Це гарантує унікальність навіть до заводського провізіонування — колізії між непровізіонованими Queens неможливі.

```c
// Flash provisioning page: 0x0803F800
// Format: [magic:4][len:1][uid:len]
// Fallback: STM32 HW UID at 0x1FFF7590 → "UNPROV-DEADBEEF"
```

**Закриває:** Уніфікований Factory Flashing, масштабування мережі Queens.

---

### ✅ BLOCKER-4: Starlink Latency Gap (Частково виправлено)

**Статус:** Таймаути збільшено. Повноцінний retry залишається відкритим (потребує UART RX парсингу).
**Файл:** `firmware/queen/main.c`

CoAP таймаути збільшені для Starlink DTC (worst-case RTT 600–2400 ms):
- `AT+CCOAPNEW`: `1000 ms` → `2000 ms`
- ACK wait (`HAL_Delay`): `2000 ms` → `5000 ms`

**Залишилось:** Реалізувати polling UART RX з перевіркою `OK` відповіді для повноцінного retry з exponential backoff. TODO-коментар додано у firmware.

**Частково закриває:** Стабільність CoAP uplink через Starlink.

---

### ✅ BLOCKER-5: IWDG Watchdog додано до Queen

**Статус:** Виправлено. IWDG ініціалізовано та інтегровано в main loop.
**Файл:** `firmware/queen/main.c`

**Реалізація:**
- `HAL_IWDG_Init()` викликається при ініціалізації Queen з timeout ~26.6 с (Reload × Prescaler / LSI_freq).
- `HAL_IWDG_Refresh()` викликається в головному циклі — до початку CoAP flush (IWDG pre-refresh перед 5-секундним delay) та після завершення flush.
- При HardFault або зависанні — IWDG автоматично перезавантажує MCU без фізичного втручання.

**Закриває:** Autonomous 24/7 operation без людського втручання в Production.

---

### ✅ BLOCKER-6: CoAP Retry-логіка — реалізовано (FW.9)

**Статус:** Виправлено. `SIM7070_SendATCommand_WithResponse` реалізовано, retry-цикл до 3 спроб.
**Файл:** `firmware/queen/main.c`

**Реалізація:**
```c
#define COAP_MAX_RETRIES  3    // [FW.9] Максимум спроб CoAP flush
#define UART_RX_BUF_SIZE  128  // [FW.9] Буфер для парсингу відповіді модему

for (uint8_t retry = 0; retry < COAP_MAX_RETRIES && !send_success; retry++) {
    // 1. Відкриваємо CoAP-сесію з перевіркою OK/ERROR
    if (!SIM7070_SendATCommand_WithResponse("AT+CCOAPNEW=...", COAP_BASE_TIMEOUT_MS)) {
        continue;  // Session open failed → retry
    }
    // 2. Відправляємо hex-кодований payload
    // ... AT+CCOAPSEND ...
    // 3. Парсимо відповідь: шукаємо "OK" у UART буфері
    if (HAL_UART_Receive(&huart1, uart_rx_buf, UART_RX_BUF_SIZE - 1, COAP_SEND_TIMEOUT_MS) == HAL_OK) {
        for (uint8_t j = 0; uart_rx_buf[j] != '\0'; j++) {
            if (strncmp(&uart_rx_buf[j], "OK", 2) == 0) { send_success = 1; break; }
        }
    }
    SIM7070_SendATCommand("AT+CCOAPDEL=0\r\n", 500);
}
```

Якщо після 3 спроб `send_success == 0` — кеш очищується (дані все ще втрачаються, persistent buffer — наступний крок). Але при транзієнтних збоях (моментовий Starlink gap, тимчасова помилка модему) retry значно підвищує надійність.

**Залишкова проблема:** Persistent буфер при 3-кратному збої не реалізовано — майбутня задача.

**Закриває:** Надійність CoAP uplink при транзієнтних мережевих збоях.

---

### ✅ BLOCKER-7: CMD_DECRYPT_BUF_SIZE синхронізовано

**Статус:** Виправлено. Тест синхронізовано з firmware.
**Файли:** `firmware/queen/main.c:122` та `firmware/test/test_queen_logic.c:21`

```c
// Обидва файли тепер:
#define CMD_DECRYPT_BUF_SIZE 544  // 512 OTA payload + 5 header + 2 CRC + 16 AES padding + 9 margin
```

**Закриває:** Повнота тестового покриття OTA downlink шляху.

---

### ✅ BLOCKER-8: HRNG Fallback — покращена ентропія IV

**Статус:** Виправлено. Fallback тепер використовує STM32 HW UID для унікальності між Queen-вузлами.
**Файл:** `firmware/queen/main.c`

**Реалізація:** При недоступності HRNG, IV генерується через комбінований seed:
```c
// djb2 хеш STM32 HW UID (0x1FFF7590) XOR HAL_GetTick() XOR XOR_MASK(i)
// Кожен bit-shift для i ∈ {0,1,2,3} гарантує різні слова IV
uint32_t tick     = HAL_GetTick();
uint32_t uid_hash = djb2_hash(queen_uid, strlen(queen_uid));
batch_iv[i] = tick ^ (uid_hash << i) ^ ((uint32_t)i * RNG_FALLBACK_XOR_MASK)
            ^ (tick >> (8U * i));
```

Оскільки STM32 HW UID унікальний для кожного чіпу, IV більше не буде однаковим навіть при масовому blackout-відновленні. Повністю усуває IV Reuse Attack у сценарії "всі Queens перезавантажились одночасно".

**Примітка:** Залишкова вразливість (BLOCKER-1: однаковий AES ключ) збережена — IV reuse повністю неможлива лише при унікальних ключах.

**Закриває:** IV Reuse Attack при blackout-відновленні.

---

### ✅ BLOCKER-9: OTA Broadcast Infinite Loop — виправлено

**Статус:** Виправлено. `ota_is_active` тепер скидається після завершення одного повного циклу бродкасту.
**Файл:** `firmware/queen/main.c`

```c
current_ota_chunk_idx++;
if (current_ota_chunk_idx >= total_chunks) {
    current_ota_chunk_idx = 0;
    ota_is_active = 0;   // ← розкоментовано: один повний цикл → стоп
}
```

Після того як усі LoRa-чанки надіслані (745 чанків для 8192 байт bytecode), Queen автоматично зупиняє бродкаст. Солдати, що підключились пізніше, можуть отримати оновлення лише якщо надійде новий CoAP downlink з `ota_is_active = 1`.

**Закриває:** Стабільна OTA-доставка при масовому оновленні лісу, коректна робота шлюзу після першої OTA-сесії.

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
║    current_jitter = HRNG() % 60001  ← Thundering Herd prevention        ║
║                    (fallback: HAL_GetTick(), без XOR-маски)              ║
║                                                                          ║
║  [MAIN LOOP]                                                             ║
║    ┌─────────────────────────────────────────────────────────┐          ║
║    │  while (LoRa_Rx_Ring_Pop(rx_payload, &rx_rssi, &rx_snr)):  [FW.3]│  ║
║    │    ├── HAL_CRYP_Decrypt(ECB, rx_payload[16])           │          ║
║    │    │     → decrypted_payload[16]                        │          ║
║    │    │                                                     │          ║
║    │    ├── [OTA REFLEX SHOT, if ota_is_active]             │          ║
║    │    │     Build chunk: [0x99][idx:2][total:2][data:11]  │          ║
║    │    │     HAL_CRYP_Encrypt(ECB) → Radio.Send(16 bytes)  │          ║
║    │    │     HAL_Delay(60ms) → current_ota_chunk_idx++      │          ║
║    │    │                                                     │          ║
║    │    ├── Extract DID (decrypted_payload[0..3])           │          ║
║    │    │                                                     │          ║
║    │    ├── Process_And_Cache_Data(uid, payload, rssi, snr) │          ║
║    │    │     1. DEDUP: знайти UID → оновити payload+RSSI   │          ║
║    │    │     2. INSERT: вільний слот → cache_count++        │          ║
║    │    │     3. CIFO EVICT: evict non-critical worst RSSI  │          ║
║    │    │                                                     │          ║
║    │    └── Radio.Rx(LORA_RX_INFINITE) → next pop            │          ║
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

## 📐 0. Всі #define Константи (SSOT)

| Константа | Значення | Файл:Рядок | Призначення |
|-----------|----------|------------|-------------|
| `LORA_RX_INFINITE` | `0xFFFFFF` | main.c:39 | Нескінченний таймаут RX |
| `FLUSH_INTERVAL_MS` | `3 600 000` | main.c:40 | Інтервал flush (1 год.) |
| `FLUSH_JITTER_MAX_MS` | `60 000` | main.c:41 | Макс. jitter (60 сек) |
| `RNG_FALLBACK_XOR_MASK` | `0xA5A5A5A5UL` | main.c:42 | XOR-маска при відмові HRNG (jitter) |
| `FLUSH_HEADROOM` | `5` | main.c:43 | Слоти до примусового flush |
| `QUEEN_HEALTH_GP_MAX` | `63` | main.c:44 | Макс. growth_points для sentinel |
| `OTA_MAX_CHUNKS` | `16` | main.c:45 | Макс. CoAP-чанків (bitmap 16 біт) |
| `CACHE_MAX_ENTRIES` | `50` | main.c:87 | Місткість CIFO EdgeCache |
| `CMD_DEDUP_SIZE` | `16` | main.c:113 | Розмір кільцевого буфера dedup |
| `UUID_STR_LEN` | `36` | main.c:114 | Довжина UUID рядка (8-4-4-4-12) |
| `CMD_DECRYPT_BUF_SIZE` | `544` | main.c:122 | Буфер decrypt CoAP команд/OTA |
| `OTA_MARKER` | `0x99` | main.c:29 | Маркер OTA-пакета |
| `OTA_HEADER_SIZE` | `5` | main.c:30 | Маркер + idx:2 + total:2 |
| `OTA_CRC_SIZE` | `2` | main.c:31 | CRC16-CCITT |
| `OTA_OVERHEAD` | `7` | main.c:32 | `OTA_HEADER_SIZE + OTA_CRC_SIZE` |
| `AES_BLOCK_SIZE` | `16` | main.c:33 | AES-256 block size |
| `MAX_OTA_CHUNK_PAYLOAD` | `512` | main.c:34 | Макс. байткод у CoAP-чанку |
| `OTA_FULL_CHUNK_THRESH` | `514` | main.c:35 | `MAX_OTA_CHUNK_PAYLOAD + OTA_CRC_SIZE` |
| `MIN_OTA_ALIGNED` | `23` | main.c:36 | `AES_BLOCK_SIZE + OTA_OVERHEAD` |

---

## 📡 1. LoRa Reception та ISR

> **Роль у вирішенні Проблеми Рандеву:** Королева є **єдиним always-on listener** у мережі. Її SX1262 завжди в `Radio.Rx(LORA_RX_INFINITE)` — нескінченний таймаут прийому. Це вирішує фундаментальну Проблему Рандеву (Rendezvous Problem) для всіх вузлів у прямій видимості (150–200 м): Солдат може "вистрілити" пакетом у будь-яку мілісекунду — Королева завжди зловить. Це можливо завдяки зовнішньому живленню (сонячна панель / акумулятор), на відміну від Солдатів з EBFC біобатарейкою. Для вузлів за межами прямої видимості Queen потрібні Синхронні Вікна (TDMA) та CAD — нереалізовані механізми рівнів L2/L3 ([ARCH.26](00_08_Action_Plan_Tracker), [деталі → 00_01 §Рівень 4](00_02_System_Architecture_and_12_Chain_Pipeline)).

### OnRxDone (Апаратне переривання)

```c
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr)
{
    // [E.8] SNR більше не відкидається — він плюметься у ринг і використовується
    //       як tiebreaker у CIFO eviction (Process_And_Cache_Data).
    if (size != 16) return;  // Очікуємо рівно 16 байт (повний AES block)

    // [FIX: RSSI Truncation] SX1262 може повернути RSSI < -128
    if (rssi < -128) rssi = -128;
    if (rssi > 127)  rssi = 127;

    // [FW.3 + E.8] Кладемо голос (payload + rssi + snr) у FIFO ring buffer
    // (16 слотів) — main loop дренує його після завершення CoAP-flush'у.
    // Якщо ринг переповнений, інкрементується lora_rx_drops, але існуючі
    // голоси недоторкані.
    LoRa_Rx_Ring_Push(payload, (int8_t)rssi, snr);
}
```

**Параметри прийому:**
| Параметр | Значення | Опис |
|----------|----------|------|
| Частота | 868 MHz | Регіон ЄС/Україна |
| Розмір пакета | 16 байт | Повний AES-256 блок |
| Таймаут RX | `LORA_RX_INFINITE = 0xFFFFFF` | Нескінченне очікування |
| UART baud | 115200 | SIM7070G модем |
| `snr` параметр | **використовується як CIFO tiebreaker (E.8)** | SX1262 SNR плюметься через ring buffer у `EdgeCache.snr`. У `Process_And_Cache_Data` він активується **лише** як tiebreaker: коли два non-critical (status=0) записи мають **однаковий** найгірший RSSI — той з нижчим SNR (шумніший канал → пакет імовірніше прийшов через інтерференцію та став stale) виганяється першим. RSSI залишається primary key, `bio_status` priority undisturbed. 7 host-тестів у `firmware/test/test_queen_logic.c` (`test_e8_*`). |

**[FW.3] LoRa RX Ring Buffer (single-producer / single-consumer FIFO):**

| Поле | Тип | Розмір | Призначення |
|------|-----|--------|-------------|
| `lora_rx_ring[16]` | `volatile LoRaRxSlot` | 16 × 18 = 288 B | FIFO слоти (16 байт payload + 1 байт rssi + 1 байт snr — [E.8]) |
| `lora_rx_head` | `volatile uint8_t` | 1 B | Куди ISR кладе наступний пакет |
| `lora_rx_tail` | `volatile uint8_t` | 1 B | Звідки main loop забирає |
| `lora_rx_drops` | `volatile uint16_t` | 2 B | Лічильник переповнень (видимий для майбутнього gateway-health export) |

Ефективна capacity = `LORA_RX_RING_SIZE - 1 = 15` (один слот віддано на розрізнення full vs empty). ARM Cortex-M4 атомарність 8-біт читання/запису гарантує lock-free ISR↔main coordination без `__disable_irq()`. На host-тестах volatile-лічильники поводяться як звичайні uint8 — single-thread детерміністичний доступ, логіка empty/full однакова.

**Замінено в FW.3 (2026-05-02):** `incoming_lora_payload[16]` + однобітний `lora_rx_flag` → ring buffer. Було: ISR під час 25-секундного CoAP-flush'у мовчки перезаписував попередній голос; main loop бачив тільки останній. Стало: до 15 голосів чекають у рингу; переповнення видиме через `lora_rx_drops`.

---

## 🗄️ 2. CIFO EdgeCache (Алгоритм дедуплікації та кешування)

### Структура даних

```c
#define CACHE_MAX_ENTRIES 50

typedef struct {
    uint32_t uid;        // DID дерева (4 байти)
    uint8_t payload[16]; // Останні розшифровані дані
    int8_t  rssi;        // Сила сигналу (dBm)
    int8_t  snr;         // [E.8] SNR (dB) — tiebreaker у CIFO eviction
    uint8_t is_active;   // 1 = слот зайнятий
} EdgeCache;

EdgeCache forest_cache[CACHE_MAX_ENTRIES]; // 50 × 23 байти = 1150 байт
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

  bio_status = (payload[10] >> 5) & 0x03   // [FW.29-PACK] bits 6..5 (status), bit 7 = PANIC_FLAG_BIT
    0 = homeostasis (кандидат на витіснення)
    1 = stress      (захищений)
    2 = anomaly     (захищений)
    3 = tamper      (захищений)
```

### Логіка евікції — псевдокод

```
best_evict_idx = -1,  best_evict_rssi = 127, best_evict_snr = 127  (найгірший кандидат серед некритичних)
fallback_idx   =  0,  fallback_rssi   = 127, fallback_snr   = 127  (найгірший серед усіх)

for i in 0..49:
  if NOT is_active[i]: continue  // [FIX: AUDIT] пропускаємо неактивні

  // [E.8] При рівному RSSI tiebreaker — нижчий SNR (шумніший канал → preferred to evict).
  if rssi[i] < fallback_rssi  OR  (rssi[i] == fallback_rssi AND snr[i] < fallback_snr):
    fallback_rssi = rssi[i]; fallback_snr = snr[i]; fallback_idx = i

  if bio_status[i] == 0 AND
     (rssi[i] < best_evict_rssi  OR  (rssi[i] == best_evict_rssi AND snr[i] < best_evict_snr)):
    best_evict_rssi = rssi[i]; best_evict_snr = snr[i]; best_evict_idx = i

evict_idx = (best_evict_idx >= 0) ? best_evict_idx : fallback_idx
// Перезаписуємо слот новим uid/payload/rssi/snr (is_active вже = 1, cache_count не змінюється)
```

**Чому priority-aware важливо:** Без цього виправлення дерево на межі пожежі (найгірший RSSI = найслабший сигнал = найдальше від Queen) могло бути витіснено саме в момент критичного сигналу. Тепер такі записи захищені.

**[E.8] SNR як tiebreaker:** RSSI вимірює потужність прийому (відстань / preposition), але два пакети можуть прийти з однаковим RSSI: один по чистому каналу, інший — крізь interference. SX1262 повертає і RSSI, і SNR (Signal-to-Noise Ratio). Раніше `(void)snr;` відкидав SNR. Тепер SNR plumb'иться повз ISR → ring buffer → `EdgeCache.snr` і використовується **виключно** як tiebreaker при рівному RSSI: нижчий SNR (шумніший канал → пакет імовірніше прийшов через колізію / multipath і вже стале) — preferred for eviction. RSSI залишається primary key, `bio_status` priority undisturbed. Покриття: 7 host-тестів `test_e8_*` у `firmware/test/test_queen_logic.c`.

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
   padded_size = ((offset + 15) / 16) * 16  ← AES block alignment
   Захист: if (padded_size > sizeof(binary_batch_buffer)) → cap

2. Generate IV: HRNG "Wu-Wei" підхід:
   hrng.Instance = RNG
   HAL_RNG_Init(&hrng)  ← ініціалізація тільки перед використанням
   for i in 0..3:
     if HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK:
       tick = HAL_GetTick(); uid_hash = djb2_hash(queen_uid, strlen(queen_uid));
        batch_iv[i] = tick ^ (uid_hash << i) ^ (i * 0xA5A5A5A5UL) ^ (tick >> (8*i))  ← IV fallback
   HAL_RNG_DeInit(&hrng)  ← деініціалізація зразу після

3. Switch CRYP: hcryp.Init.Algorithm = CRYP_AES_CBC
   hcryp.Init.pInitVect = batch_iv
   HAL_CRYP_Init(&hcryp)

4. Encrypt: HAL_CRYP_Encrypt(binary_batch_buffer, padded_size/4, output+16, 2000)

5. Prepend IV: encrypted_batch_buffer[0..15] = batch_iv
   Total encrypted_batch_buffer size = 16 (IV) + padded_size

static uint8_t encrypted_batch_buffer[2048 + 16];  ← static (не стек!)
```

**Два різні HRNG fallback — не плутати:**
| Місце | Fallback при HRNG fail | Маска | Пояснення |
|-------|------------------------|-------|-----------|
| CBC IV generation (batch) | `tick ^ (uid_hash << i) ^ (i * 0xA5A5A5A5UL) ^ (tick >> (8*i))` | per-word, 4 різні слова IV | djb2(UID) + подвійний tick shift (ліворуч і право) + маска — гарантує 4 унікальних слова навіть при однаковому tick та однаковому UID |
| Jitter regeneration після flush | `HAL_GetTick() ^ RNG_FALLBACK_XOR_MASK` | `0xA5A5A5A5UL` (одна константа) | Один tick, одна маска — простий jitter, криптостійкість не потрібна |
| Startup jitter (один раз) | `HAL_GetTick()` (без XOR!) | без маски — рядок 228 | Startup: tick вже унікальний бо залежить від часу включення живлення; жодна маска не додає ентропії у цьому контексті; jitter — не криптографічна операція |

> **Примітка:** Всі три fallback є слабкими при масовому blackout (BLOCKER-8 стосується CBC IV). Для jitter безпека не потрібна. Різниця в масках — це не помилка, а різні вимоги до ентропії.

### Крок 3: Відновлення ECB

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

### CoAP Flush Sequence (кожен flush, FW.9)

```
[FW.9] Retry loop: до 3 спроб (COAP_MAX_RETRIES), перервати при send_success=1.

1. SIM7070_SendATCommand_WithResponse("AT+CCOAPNEW=...", COAP_BASE_TIMEOUT_MS=2000 ms)
   ↳ Читаємо відповідь: якщо "OK" → success; "ERROR" → continue retry
   ↳ Відкриваємо CoAP сесію, session_id=0

2. Формуємо та відправляємо AT+CCOAPSEND через UART (blocking):
   a. Заголовок команди: snprintf → HAL_UART_Transmit(..., strlen, 100 ms)
      "AT+CCOAPSEND=0,2,"telemetry/batch/<queen_uid>",<size*2>,\""
   b. Hex payload: кожен байт окремо → HAL_UART_Transmit(2 байти ASCII, 10 ms)
      Для 50 записів: total_size ≈ 1072 байт → 2144 ASCII → ~21.4 секунди
   c. Закриваємо: HAL_UART_Transmit("\"\r\n", 3, 100 ms)
   ↳ Method=2 (PUT), URI-Path визначає шлюз (вирішує Starlink NAT)

3. HAL_UART_Receive(uart_rx_buf, UART_RX_BUF_SIZE=128, COAP_SEND_TIMEOUT_MS=5000 ms)
   ↳ Шукаємо "OK" у відповіді: якщо знайдено → send_success=1
   ↳ Якщо "ERROR" або timeout → continue до наступної retry-спроби
   ↳ Збільшено з 2000→5000 ms для Starlink DTC worst-case latency (600–2400 ms RTT)

4. AT+CCOAPDEL=0\r\n  (HAL_Delay 500 ms)
   ↳ Закриваємо сесію, звільняємо ресурси модему

5. При send_success=0 після 3 спроб — кеш очищується (дані втрачаються).
```

**Загальний час flush для 50 записів: ~25 секунд** (BLOCKER-2, залишається через blocking hex TX)

**Важливо про URI-Path:** `/telemetry/batch/<queen_uid>` використовується замість IP-адреси, що вирішує проблему Starlink NAT та динамічних адрес. Сервер знаходить шлюз за UID, а не за IP.

### Функції роботи з AT-командами (FW.9)

```c
// Проста відправка без читання відповіді (ініціалізація, CCOAPDEL)
void SIM7070_SendATCommand(char* command, uint32_t delay_ms) {
    HAL_UART_Transmit(&huart1, (uint8_t*)command, strlen(command), 1000);
    HAL_Delay(delay_ms);
}

// [FW.9] Відправка з читанням та перевіркою відповіді (CCOAPNEW)
static uint8_t SIM7070_SendATCommand_WithResponse(const char* command, uint32_t timeout_ms) {
    memset(uart_rx_buf, 0, UART_RX_BUF_SIZE);
    HAL_UART_Transmit(&huart1, (uint8_t*)command, strlen(command), 1000);
    HAL_UART_Receive(&huart1, uart_rx_buf, UART_RX_BUF_SIZE - 1, timeout_ms);
    // Шукаємо "OK" → повертаємо 1 (success) або 0 (failure/ERROR/timeout)
    for (uint8_t i = 0; uart_rx_buf[i] != '\0'; i++) {
        if (strncmp(&uart_rx_buf[i], "OK", 2) == 0) return 1;
    }
    return 0;
}

**Відповіді SIM7070G, що парсяться (FW.9):**
- `OK` — команда прийнята → `SIM7070_SendATCommand_WithResponse` повертає `1`
- `ERROR` — помилка → retry
- `+CCOAPSEND: 0,1` — CoAP ACK отримано (парсинг поки не реалізовано; достатньо `OK` від `AT+CCOAPNEW`)

---

## 🔄 5. OTA Broadcast (Reflex Shot — LoRa Downlink до Солдатів)

### Механізм "Рефлекторного Пострілу"

Після отримання кожного LoRa-пакета від Солдата, Queen **негайно** відповідає OTA-чанком. Це працює тому що Солдат слухає ефір 500 ms після власного TX (Phase 4.5 в 03_01).

```
Солдат TX (16 bytes) → Queen OnRxDone ISR
  ↓
Queen: decrypt → [OTA REFLEX SHOT if ota_is_active == 1]
  ↓
Всередині: total_chunks = (pending_ota_size + 10) / 11  ← LoRa chunk formula

if (current_ota_chunk_idx < total_chunks):
  Build OTA LoRa chunk (16 bytes):
    [0]     = 0x99                         ← OTA маркер
    [1-2]   = current_ota_chunk_idx BE     ← uint16 big-endian
    [3-4]   = total_chunks BE              ← uint16 big-endian
    [5-15]  = 11 байт mruby bytecode
               offset = current_ota_chunk_idx * 11
               bytes_to_copy = min(11, pending_ota_size - offset)
  HAL_CRYP_Encrypt(ECB) → Radio.Send(encrypted_ota, 16)
  HAL_Delay(60)   ← час для фізичної передачі пакета (~50-60 мс)

current_ota_chunk_idx++
if (current_ota_chunk_idx >= total_chunks):
  current_ota_chunk_idx = 0       ← wrap → один повний цикл завершено
  ota_is_active = 0               ← ✅ скидаємо після одного повного бродкасту (виправлено)
```

**Математика LoRa чанків:**
- Корисне навантаження: 11 байт (16 − 5 байт заголовка)
- Для 8192 байт bytecode: `(8192 + 10) / 11 = 745` LoRa-чанків
- Кожен Солдат при кожному своєму TX отримує **один** послідовний чанк
- Після 745-го чанка `current_ota_chunk_idx` скидається до 0 і `ota_is_active = 0` (бродкаст зупиняється)

### OTA Assembly (CoAP Downlink від Rails → RAM)

**Два типи OTA-чанків — важливо не плутати:**
| Тип | Джерело | Розмір payload | Макс чанків | Ліміт |
|-----|---------|----------------|-------------|-------|
| **CoAP downlink** (Rails → Queen) | `Handle_CoAP_Command` | ≤512 байт | 16 | `OTA_MAX_CHUNKS` (bitmap) |
| **LoRa Reflex Shot** (Queen → Soldier) | Main loop | 11 байт | ≤745 | `(pending_ota_size+10)/11` |

```
Rails → CoAP → Handle_CoAP_Command(payload, len):

─── Вхідні перевірки ────────────────────────────────────────────────────
1. len < 32 OR len > (CMD_DECRYPT_BUF_SIZE + 16=544+16=560) → return
   (мінімум: IV 16 + 1 AES-блок 16 = 32 байти)

2. Витягти IV з payload[0..15]: memcpy(cmd_iv, payload, 16)

3. Switch CRYP → CBC, decrypt payload+16 → cmd_decrypt_buf[544]
   aligned = ((len-16 + 15) / 16) * 16
   if (aligned > CMD_DECRYPT_BUF_SIZE=544) → restore ECB → return

4. Restore ECB ← обов'язково ДО обробки, щоб LoRa не зламалось!

5. cmd_decrypt_buf[CMD_DECRYPT_BUF_SIZE-1] = '\0'  ← NUL terminator

─── Маршрутизація за маркером ───────────────────────────────────────────
  if cmd_decrypt_buf starts "CMD:" → actuator command (секція 6)
  if cmd_decrypt_buf[0] == 0x99   → OTA downlink chunk

─── OTA Chunk Processing ─────────────────────────────────────────────────
Guard 1: if (aligned < 6) → return  [MISRA: мін. 1 маркер + 2 idx + 2 total + 1 байт коду]

Витягуємо:
  chunk_index  = (cmd_decrypt_buf[1] << 8) | cmd_decrypt_buf[2]  (big-endian)
  total_chunks = (cmd_decrypt_buf[3] << 8) | cmd_decrypt_buf[4]  (big-endian)
  ota_total_expected_chunks = total_chunks  ← оновлюється з кожним чанком

Guard 2: if (total_chunks == 0) → return  [invalid header]
Guard 3: if (chunk_index >= OTA_MAX_CHUNKS=16) → return  [bitmap overflow]
Guard 4: if (aligned < MIN_OTA_ALIGNED=23) → return  [MISRA: 16 AES + 7 overhead]

─── payload_len calculation (ключова формула) ──────────────────────────
  guaranteed = aligned - AES_BLOCK_SIZE(16)
  // guaranteed = корисні байти мінус можливий AES-padding (останній блок)

  if (guaranteed >= OTA_FULL_CHUNK_THRESH=514):
    payload_len = MAX_OTA_CHUNK_PAYLOAD = 512  ← повний чанк
  else:
    payload_len = guaranteed - OTA_OVERHEAD(7) ← останній/неповний чанк
    // OTA_OVERHEAD = OTA_HEADER_SIZE(5) + OTA_CRC_SIZE(2)

  offset = (uint32_t)chunk_index * MAX_OTA_CHUNK_PAYLOAD  (0, 512, 1024, ...)

Guard 5: if (offset + payload_len > sizeof(pending_ota_bytecode)=8192) → return

─── Dedup via bitmap ─────────────────────────────────────────────────────
  chunk_bit = 1U << chunk_index
  if (ota_chunk_bitmap & chunk_bit) → return  (дублікат — ігноруємо)
  ota_chunk_bitmap |= chunk_bit               (маркуємо як отриманий)

─── Зберігаємо в RAM-буфер ───────────────────────────────────────────────
  memcpy(pending_ota_bytecode + offset, &cmd_decrypt_buf[OTA_HEADER_SIZE=5], payload_len)
  ota_chunks_received++

  // Відстежуємо реальний розмір зібраного байткоду:
  if (offset + payload_len > pending_ota_size):
    pending_ota_size = offset + payload_len

─── Перевірка завершення ──────────────────────────────────────────────────
  if (ota_chunks_received >= ota_total_expected_chunks):
    ota_chunks_received = 0           ← скидаємо лічильник
    ota_total_expected_chunks = 0     ← скидаємо очікуваний total
    ota_chunk_bitmap = 0              ← скидаємо bitmap
    current_ota_chunk_idx = 0        ← починаємо LoRa broadcast з чанка 0
    ota_is_active = 1                 ← 🚀 запускаємо LoRa broadcast!
    // УВАГА: pending_ota_size НЕ скидається (залишається для broadcast)
    // ota_is_active скидається до 0 після одного повного циклу бродкасту (виправлено)
```

**Константи OTA (повна таблиця):**
| Константа | Значення | Розрахунок | Опис |
|-----------|----------|------------|------|
| `OTA_MARKER` | `0x99` | — | Маркер OTA-пакета (перший байт) |
| `OTA_HEADER_SIZE` | 5 | `1+2+2` | Маркер + index:2 + total:2 |
| `OTA_CRC_SIZE` | 2 | — | CRC16-CCITT в кінці чанка |
| `OTA_OVERHEAD` | 7 | `5+2` | Header + CRC (мінімум для розрахунку payload) |
| `AES_BLOCK_SIZE` | 16 | — | Розмір AES-блоку |
| `MAX_OTA_CHUNK_PAYLOAD` | 512 | — | Макс. байткод в одному CoAP-чанку |
| `OTA_FULL_CHUNK_THRESH` | 514 | `512+2` | Поріг повного чанка (payload + CRC) |
| `MIN_OTA_ALIGNED` | 23 | `16+7` | Мінімум для OTA: AES block + overhead |
| `OTA_MAX_CHUNKS` | 16 | `8192/512` | Макс. CoAP-чанків (bitmap обмеження) |
| `pending_ota_bytecode` | 8192 B | — | RAM-буфер збірки прошивки |

---

### 5.X [FW.27] OTA Broadcast Reliability — ACK-Aggregation + Magic Re-Request (DESIGN)

> **Статус:** 🤖 Дизайн завершено. Повна імплементація залежить від [ARCH.26 TDMA Sync Windows](00_08_Action_Plan_Tracker) — без скоординованого RX-вікна на Soldier'ах ACK-aggregation марна. Поточний broadcast — fire-and-forget, що документується тут чесно.

#### 5.X.1 Проблема, яку вирішує

Поточний OTA-broadcast Queen (§5) працює послідовно через LoRa без жодної перевірки доставки:

```
Queen Broadcast Loop:
  for chunk_idx in 0..total_chunks:
      LoRa.Send(chunk[chunk_idx])
      HAL_Delay(60ms)  # pacing
  ota_is_active = 0
```

**Проблеми:**

1. **Soldier у STOP2:** Якщо вузол спить під час трансляції конкретного `chunk_idx` — chunk втрачається без жодної індикації Queen.
2. **LoRa collision:** Інший Soldier (mesh relay) може заглушити наш broadcast — Queen цього не дізнається.
3. **RF dead zone:** Деякі вузли можуть бути поза радіо-видимістю Queen — жоден chunk до них не доходить взагалі.
4. **Bitmap fragmentation:** Soldier-side `ota_chunk_received[256]` фіксує отримані chunks, але:
   - При `ota_chunks_received < ota_total_chunks` після broadcast вузол навіки чекає на missing chunks (CRC32 не пройде, Flash write не виконається).
   - Eventually `IWDG` reset → `ota_buffer` очищується → весь broadcast потрібен заново.

**Поточна mitigation:** Жодної. Є тільки **Wave-based broadcast** (§5.5) — Queen транслює всю партію після кожного нового CoAP-batch від Rails. Це надає природний retry, але:
- Затримка між waves = 1 година (CoAP flush interval)
- Жодна гарантія, що `chunk_idx` пропущений у wave N буде успішним у wave N+1 (той самий Soldier може бути в STOP2 знову)
- Energy waste: вузли отримують повторні chunks, які вже у Flash

#### 5.X.2 Дизайн A: ACK-Aggregation (Queen-side coordination)

**Ідея:** Queen після broadcast чекає коротке *aggregation window* (10-15 секунд) і слухає uplink від Soldier'ів. Кожен Soldier формує **bitmap-ACK** з його локального `ota_chunk_received[]` і відправляє `[ACK_MARKER:1][DID:4][bitmap:N]` (N = `ceil(total_chunks/8)`, для 16 chunks → 2 байти).

```
Queen Broadcast Loop (з FW.27 ACK-aggregation):
  for retry_round in 0..MAX_BROADCAST_ROUNDS=3:
      missing_mask = (round == 0) ? ALL : aggregated_missing_from_acks
      for chunk_idx in 0..total_chunks:
          if (missing_mask & (1 << chunk_idx)):
              LoRa.Send(chunk[chunk_idx])
              HAL_Delay(60ms)

      # Aggregation Window (10s)
      LoRa.Rx(ACK_AGGREGATION_TIMEOUT_MS=10000)
      received_acks = []
      while (within_window):
          if (lora_rx_flag and starts_with ACK_MARKER):
              parse_ack(payload) → {did, bitmap}
              received_acks.append(bitmap)

      # Compute aggregated missing: union of all reported gaps
      aggregated_missing = OR(~bitmap for bitmap in received_acks)
      if (aggregated_missing == 0): break  # all confirmed

  ota_is_active = 0
```

**Format ACK-пакета (LoRa uplink Soldier→Queen):**

```
[ACK_MARKER:1][DID:4][TOTAL_CHUNKS:2][BITMAP:ceil(total/8)]
  0xA0           BE         BE              LSB-first

# Для 16 chunks: загальний розмір = 1+4+2+2 = 9 байт + AES padding to 16 → 1 LoRa frame
```

**Soldier-side: тригер ACK після broadcast wave:**

Soldier мав би передбачити закінчення broadcast (наприклад, `ota_chunks_received` не змінювався протягом останніх 5 секунд → broadcast скінчився) і відправити ACK у aggregation-вікно. Але **це вимагає TDMA Sync (ARCH.26)** — без узгодженого годинника Soldier не знає, коли почати TX, щоб не зіткнутися з іншими Soldier'ами.

**Чому DESIGN, а не імплементація:**

- TDMA не реалізована → 100 Soldier'ів одночасно відправляли б ACK → collision storm.
- Поточний `Trigger_Emergency_LoRa_TX()` має `random_jitter % 500ms` (FW.10) — для broadcast-ACK довелось би розширити цей jitter до пропорційного до кількості сусідніх вузлів, що знову вимагає координації.
- ACK-bitmap-aggregation потребує Queen RAM (`union_bitmap[ceil(OTA_MAX_CHUNKS/8)] = 2 байти` × до 100 unique DIDs у CIFO cache). Це окрема структура поза CIFO.

#### 5.X.3 Дизайн B: Magic Re-Request (Soldier-initiated vector OTA) — ✅ Реалізовано (2026-05-02)

**Статус:** ✅ Реалізовано у `firmware/soldier/main.c` (`Build_OTA_ReRequest_Payload`, OTA_REQ_MARKER 0x55, OTA_REREQUEST_TIMEOUT_MS=300000) + `firmware/queen/main.c` (`Process_LoRa_RX` REREQUEST handler перед CIFO/CoAP, `djb2_hash_bytes` length-strict NUL-safe replay-protection через `cmd_dedup_ring`). 22 host-тести (12 Soldier + 10 Queen) у `firmware/test/test_soldier_logic.c` + `test_queen_logic.c`. Опціонально (поза цим циклом): зберегти останній OTA SHA-256 у Queen Flash для cross-check на re-request — поки не реалізовано, після `ota_is_active=0` буфер `pending_ota_bytecode` може бути перезаписаний наступним CoAP-push'ем, тоді re-request не обслуговується (Solider має чекати наступного Rails-driven OTA cycle).

**Ідея:** Soldier при `ota_chunks_received < ota_total_chunks` після таймауту (наприклад, **5 хвилин без нових chunks**) ініціює uplink-запит конкретних missing chunks через звичайний LoRa TX → Queen приймає, ретранслює лише ці chunks.

**Soldier-side state machine (новий):**

```c
// firmware/soldier/main.c — додатковий стан OTA
uint32_t ota_last_chunk_rx_tick = 0;
#define OTA_REREQUEST_TIMEOUT_MS  300000  // 5 хв без нових chunks → re-request
#define REREQUEST_MARKER          0x55    // Окремий маркер uplink-запиту

// У Phase 4.5 після обробки RX:
if (ota_total_chunks > 0 &&
    ota_chunks_received < ota_total_chunks &&
    (HAL_GetTick() - ota_last_chunk_rx_tick) > OTA_REREQUEST_TIMEOUT_MS) {
    // Збираємо missing-bitmap і шлемо запит
    Send_OTA_ReRequest(ota_chunk_received, ota_total_chunks);
}

void Send_OTA_ReRequest(uint8_t* received_map, uint16_t total) {
    uint8_t req_payload[16] = {0};
    req_payload[0] = REREQUEST_MARKER;             // 0x55
    req_payload[1] = (uint8_t)(tree_did >> 24);
    req_payload[2] = (uint8_t)(tree_did >> 16);
    req_payload[3] = (uint8_t)(tree_did >> 8);
    req_payload[4] = (uint8_t)(tree_did & 0xFF);
    req_payload[5] = (uint8_t)(total & 0xFF);      // up to OTA_MAX_CHUNKS=16
    // Bitmap of missing (NOT received): bytes 6-7 для 16 chunks
    for (uint16_t i = 0; i < total && i < 16; i++) {
        if (!received_map[i]) {
            req_payload[6 + (i >> 3)] |= (1 << (i & 7));
        }
    }
    // PAD bytes 8-10, TTL=DEFAULT_TTL у [11], FW version у [12-13]
    req_payload[11] = DEFAULT_TTL;
    req_payload[12] = (uint8_t)(FIRMWARE_VERSION_ID >> 8);
    req_payload[13] = (uint8_t)(FIRMWARE_VERSION_ID & 0xFF);

    // AES-256-ECB шифрування + TX (як стандартний uplink-пакет)
    HAL_CRYP_Encrypt(&hcryp, (uint32_t*)req_payload, 4,
                      (uint32_t*)encrypted_payload, 1000);
    Radio.Send(encrypted_payload, 16);
}
```

**Queen-side: розпізнавання `REREQUEST_MARKER` в LoRa RX:**

```c
// У Process_LoRa_RX() поряд з існуючим CIFO insert:
if (decrypted_lora_buffer[0] == REREQUEST_MARKER) {
    // Не йде в CIFO, не йде у CoAP — тригерить локальний replay
    uint32_t requestor_did = ((uint32_t)decrypted_lora_buffer[1] << 24) |
                              ((uint32_t)decrypted_lora_buffer[2] << 16) |
                              ((uint32_t)decrypted_lora_buffer[3] << 8) |
                              (uint32_t)decrypted_lora_buffer[4];
    uint16_t total = decrypted_lora_buffer[5];
    uint16_t missing_mask = ((uint16_t)decrypted_lora_buffer[6]) |
                             ((uint16_t)decrypted_lora_buffer[7] << 8);

    // Replay only missing chunks. pending_ota_bytecode має бути ще в RAM
    // (інакше — ігноруємо, Soldier ребутнеться через IWDG).
    if (ota_is_active || ota_total_chunks > 0) {
        for (uint16_t i = 0; i < total && i < OTA_MAX_CHUNKS; i++) {
            if (missing_mask & (1 << i)) {
                Send_OTA_Chunk(i, /*from*/pending_ota_bytecode);
                HAL_Delay(60);
            }
        }
    }
    return;  // Не класифікуємо як telemetry
}
```

**Переваги Magic Re-Request:**

1. **Self-healing:** Soldier ініціює recovery без потреби в TDMA — у нього вже є jitter (`random_jitter % 500ms`) для уникнення collision з іншими uplink-пакетами.
2. **Targeted re-broadcast:** Queen відправляє лише missing chunks → 60-90% energy saving vs повторний wave.
3. **Vector OTA на одному пакеті:** 1 ACK-payload фіксує до 16 missing chunks одночасно (bitmap до OTA_MAX_CHUNKS).
4. **Power-aware throttle:** Soldier перевіряє `vcap_voltage > VCAP_LISTEN_THRESHOLD` (2800 мВ) перед re-request — слабкі вузли не споживають енергію на uplink.

**Обмеження / залишкові ризики:**

1. **Queen `pending_ota_bytecode` lifetime:** Якщо Queen вже відкинула буфер (наприклад, після повного `ota_is_active=0` cycle), re-request неможливо обслужити — потрібен повторний CoAP push з Rails. Можливе рішення: Queen зберігає останній OTA SHA-256 у Flash і перевіряє при re-request чи це той самий контракт.
2. **REREQUEST_MARKER (0x55) collision:** Маркер 0x55 вибраний так, щоб не конфліктувати з `OTA_MARKER (0x99)` та telemetry (DID byte 0 рідко 0x55, але можливо). Альтернатива — окреме AES-key namespace, що потребує SEC.3 (per-device HKDF).
3. **Replay window:** Зловмисник може resend REREQUEST → Queen знов ретранслює → battery drain. Mitigation: Queen дедуплікує REREQUEST за `(DID, missing_bitmap)` на 5 хв (cmd_dedup_ring already існує в queen-firmware §6).

#### 5.X.4 Інтеграція ARCH.26 (TDMA) → повна імплементація FW.27

Коли TDMA з'явиться:

1. **Aggregation window** (Дизайн A) стає feasible — Soldier'и розподіляються між слотами всередині 10-секундного вікна.
2. **Magic Re-Request** (Дизайн B) залишається корисним як safety net поза TDMA-вікнами.
3. Обидва дизайни ортогональні: A покриває collective recovery, B — individual recovery.

**Black-list рекомендація:** реалізовувати **Дизайн B (Magic Re-Request)** першим — він не вимагає TDMA, дає 80% користі з 20% складності. Дизайн A реалізовуємо одночасно з ARCH.26.

#### 5.X.5 [FW.27 follow-up] Soldier-side edge cases (host-test-only, 2026-05-03)

> **Кенозис тестів:** дозалучаємо 5 додаткових host-тестів у `firmware/test/test_soldier_logic.c`, що закривають реальні шуми ефіру в існуючому Magic Re-Request кодопотоці. Жодних змін у production firmware — це **freeze-contract regression bank**, який запобігає випадковому регресу при майбутніх рефакторингах.

| Сценарій | Тест | Що захищає |
|----------|------|-----------|
| Дублікат з ІНШИМ payload | `test_ota_duplicate_with_different_payload_preserves_original` | Anti-tamper: production guard `!ota_chunk_received[chunk_idx]` блокує перезапис, оригінальний payload незмінний байт-у-байт |
| STOP2 між OTA-чанками (out-of-order) | `test_ota_stop2_simulation_chunks_arrive_out_of_order` | bitmap-стан переживає множинні Process-цикли; offsets коректні після злиття |
| Той самий chunk після сну (anti-replay) | `test_ota_stop2_simulation_duplicate_after_sleep_still_rejected` | Counter не подвоюється при повторному reflex shot Королеви |
| `total_chunks=0` malformed packet | `test_ota_total_chunks_zero_rejected` | Defence-in-depth: degenerate completion → CRC32 fail → no Flash write (not crash) |
| HMAC trailer state cross-cycle | `test_hmac_trailer_state_survives_simulated_stop2_between_segments` | bitmask `ota_hmac_segments_received` OR-агрегується через STOP2 між сегментами 1/3/2 |
| HMAC trailer idempotent overwrite | `test_hmac_trailer_duplicate_segment_overwrites_idempotently` | Дубль того самого сегменту не корумпує `received_hmac_tag[]` |

> **Cross-ref:** `00_08 FW.27` — повний контекст; `04_06 §2.1` — тест-список.

---

## 📡 5а. Time Sync (FW.20, FW.20-S2) — Канонічний хаб

> **SSOT для Time Sync:** ця секція — єдина точка розкладки часо-синхронізаційного протоколу між Rails ↔ Queen ↔ Soldier. Усі деталі реалізації, статуси чек-боксів і регресійні тести зведені тут; `00_08 FW.20` / `FW.20-S2` тримає лише посилання сюди.

### 5а.1 Архітектура (3 рівні reach)

```
Rails (NTP/UTC source)
   │  CoAP downlink envelope: [0x9C][unix_ts_be:4][payload]   ✅ FW.20
   ▼
Queen (LTE-anchored time)
   │  ① Reflex broadcast `[0x9C][ts:4][TDMA-resv:4][AUTH_FLAG|TTL][magic 'B'][PAD:5]`  ✅ FW.20
   │  ② Authoritativeness flag (byte 9 bit 7 = AUTH)                                  ✅ FW.20-S2 (1/5)
   │
   │  1-hop reach (direct LoRa coverage)
   ▼
Soldier — direct
   │  ③ Drift-monitor + panic sync request `[0x56][DID:4][secs:4][TTL][magic 'S']`     ✅ FW.20-S2 (2/5)
   │  ④ Per-hop drift compensation (Provisioner-only relay): freeze-contract callable  ✅ FW.20-S2 (3/5)
   │     — `Soldier_Try_Relay_Time_Beacon` готова, активація потребує Queen TTL≥2
   │     + anti-storm dedup-bitmap у вільному RTC регістрі (DR15 наразі резерв)
   │
   │  2-hop reach (mesh relay через Provisioners)
   ▼
Soldier — relayed
   │  ⑤ Gossip-piggyback freeze-contract: byte 14 у normal-telemetry payload          ✅ FW.20-S2 (5/5)
   │     — `Soldier_Pack_Gossip_Ts_Byte` / `Soldier_Try_Apply_Gossip_Ts` callable
   │     — без активації у hot path (потребує hook у Phase 2 + RX-обробник)
   │     — точність ±128 сек (1 байт LSB), достатньо для FW.30 cold-start `epoch_day`
   ▼
Soldier — gossip-uplift (3-hop reach)
```

### 5а.2 Wire-формати

| Опкод | Маркер | Напрямок | Формат | Розмір | Cross-ref |
|-------|--------|----------|--------|--------|-----------|
| CMD_TIME_SYNC envelope | `0x9C` | Rails→Queen (CoAP) | `[0x9C][unix_ts_be:4][inner_payload]` | 5+N байт | FW.20 §1, `app/workers/concerns/coap_encryption.rb` |
| Time Beacon | `0x9C` + magic `'B'` | Queen→Soldier (LoRa ECB) | `[0x9C][ts:4][reserved:4][AUTH\|TTL][magic 'B'][PAD:5]` | 16 байт | FW.20 §2 |
| SYNC_REQUEST | `0x56` + magic `'S'` | Soldier→Queen (LoRa ECB) | `[0x56][DID:4][secs_since_sync:4][PANIC_TTL][magic 'S' = 0x53][PAD:5]` | 16 байт | FW.20-S2 §3, `firmware/soldier/main.c:Build_Time_Sync_Request_Payload` |
| Gossip ts_lsb (freeze) | — | Soldier→Soldier (piggyback у telemetry) | normal-telemetry plaintext byte 14 = `(soldier_unix_ts & 0xFFu)`; only valid коли `StatusByte & PANIC_FLAG_BIT == 0` | 1 байт у існуючому 16-байт payload | FW.20-S2 §5 |

### 5а.3 Опкод-карта (SSOT)

> **Канонічна таблиця опкодів LoRa/CoAP** живе в [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA#-45а-downlink-opcode-map). Узагальнено для Time Sync контексту:

| Опкод | Призначення | Канал | Магія | Статус |
|-------|------------|-------|-------|--------|
| `0x55` | OTA_REQ_MARKER (FW.27-B Magic Re-Request) | Soldier→Queen LoRa | byte 10 не визначений | ✅ |
| `0x56` | SYNC_REQ_MARKER (FW.20-S2 panic sync) | Soldier→Queen LoRa | byte 10 = `'S'` (0x53) | ✅ |
| `0x99` | OTA_MARKER (bytecode chunk) | bidirectional | — | ✅ |
| `0x9A` | CMD_SET_LORENZ_THRESHOLDS (FW.8) | Rails→Queen→Soldier | freeze-contract | 🟡 deferred TRL-7 |
| `0x9B` | HMAC_TRAILER_MARKER (FW.23 OTA dual-gate) | Rails→Queen→Soldier | seg_idx 1..3 | ✅ |
| `0x9C` | CMD_TIME_SYNC envelope / Time Beacon (FW.20) | Rails→Queen / Queen→Soldier | byte 10 = `'B'` (0x42) для LoRa beacon'а | ✅ |
| `0x9D` | CMD_SET_AUDIO_THRESHOLDS (FW.18) | Rails→Queen→Soldier | CRC16 | ✅ |

> **Розмежування 0x55 vs 0x56:** оба uplink-маркери, їх дезамбігвує magic-byte у позиції 10 (`'R'` для re-request vs `'S'` для sync) — захищає від ложної маршрутизації при випадковому bit-flip першого байта.

### 5а.4 Константи Soldier-сторони

```c
// firmware/soldier/main.c
#define BEACON_MARKER                    0x9C       // Time Beacon LoRa marker
#define BEACON_MAGIC_BYTE                'B'        // = 0x42
#define BEACON_AUTH_FLAG                 0x80       // byte 9 bit 7
#define BEACON_TTL_MASK                  0x7F       // byte 9 bits [6:0]
#define BEACON_RELAY_MIN_TTL             2u         // TTL=1 не релеїться
#define BEACON_RELAY_MAX_HOP_DELAY_SEC   3600UL     // sanity cap

#define SYNC_REQ_MARKER                  0x56       // Soldier→Queen sync request
#define SYNC_REQ_MAGIC_BYTE              0x53       // 'S' magic у byte 10
#define TIME_SYNC_DRIFT_THRESHOLD_SEC    43200UL    // 12 год без beacon → panic
#define TIME_SYNC_REQUEST_COOLDOWN_MS    3600000UL  // 1 год між zвiт-проханнями
#define TIME_SYNC_COLD_BOOT_GRACE_MS     600000UL   // 10 хв cold-boot grace

#define GOSSIP_TS_PAYLOAD_OFFSET         14u        // byte 14 у normal telemetry
#define GOSSIP_TS_MAX_DRIFT_SEC          127u       // ±128 sec window для gossip
```

### 5а.5 Регресійний бенч

| Шар | Тест-blok | Кількість | Файл |
|-----|-----------|-----------|------|
| Backend `CoapEncryption` envelope | TIME_SYNC envelope strip + roundtrip | 8 | `spec/workers/concerns/coap_encryption_spec.rb` |
| Queen beacon plaintext | `Build_Time_Beacon_Plaintext` byte 9 = 0x81 | 2 | `firmware/test/test_queen_logic.c` |
| Soldier beacon RX | authoritative/relay/legacy byte9 → flag | 3 | `firmware/test/test_soldier_logic.c` |
| Soldier drift-monitor | `Soldier_Should_Request_Time_Sync` cold-boot/grace/cooldown/payload layout | 9 | `firmware/test/test_soldier_logic.c` |
| Soldier mesh-relay (per-hop drift) | `Soldier_Try_Relay_Time_Beacon` 6 reasons + happy + boundary | 13 | `firmware/test/test_soldier_logic.c` |
| Soldier gossip-piggyback (freeze) | pack/apply, cold-boot, drift cap, window selection | 7 | `firmware/test/test_soldier_logic.c` |
| **Всього FW.20 + FW.20-S2** | — | **42** | — |

### 5а.6 Що ще лежить як freeze-contract (deferred TRL-7)

- **Anti-storm dedup bitmap** для повного активного mesh-relay'у (потребує вільного RTC регістра — DR15 наразі резерв; cross-ref [`03_01 §2.3 ARCH.28`](03_01_Firmware_Lifecycle_and_DMA#23-overflow-strategy-flash-based-kv-store-arch28))
- **Queen beacon TTL≥2** (зараз hardcoded TTL=1 у `BEACON_BYTE9_AUTHORITATIVE = 0x81`; перемикається коли реалізуємо anti-storm)
- **Hot-path виклик** `Soldier_Pack_Gossip_Ts_Byte` у Phase 2 normal-telemetry pack + RX-обробник для прийому
- **Drift compensation** при ΔT = ±60°C lab-вимірювання (потребує термокамери, відсутня @ TRL-6)

> **Закриття 00_08:** після цього хабу записи `FW.20`, `FW.20-S2 (1/5..5/5)` у `00_08 §Firmware` шорткозамкнено — лишилося лише посилання сюди для аудиту прогресу.

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
// Bytes 0-3: DID = 0x00000000 — зарезервований sentinel (не є деревом)
// Bytes 4-5: uptime proxy — тік / 1000 (uint16, wraps кожні ~18.2 год = 65535 с)
uint16_t uptime_sec = (uint16_t)(HAL_GetTick() / 1000);
queen_health[4] = (uint8_t)(uptime_sec >> 8);
queen_health[5] = (uint8_t)(uptime_sec & 0xFF);
// Byte 6:  зарезервовано (0x00) — майбутнє: температура корпусу Queen
// Byte 7:  кількість дерев у кеші (навантаження шлюзу, 0–50)
queen_health[7] = cache_count;
// Bytes 8-9: зарезервовано (0x00) — майбутнє: CSQ модему (0–31)
// [FW.29-PACK] Byte 10: growth_points = cache_count (cap at 31, QUEEN_HEALTH_GP_MAX)
queen_health[10] = (cache_count < QUEEN_HEALTH_GP_MAX) ? cache_count : QUEEN_HEALTH_GP_MAX;
// Bytes 11-15: зарезервовано (0x00) — майбутнє: напруга батареї, версія прошивки
Process_And_Cache_Data(0, queen_health, 0); // RSSI=0 (локальний пакет)
```

**Повна структура Queen Health Sentinel (16 байт payload):**

| Байт(и) | Поле | Значення | Опис |
|---------|------|----------|------|
| 0–3 | DID | `0x00000000` | Sentinel — "це Королева, не дерево" |
| 4–5 | Uptime | `HAL_GetTick() / 1000` | Uptime proxy в секундах (uint16, wraps ~18.2 год = 65535 с) |
| 6 | Reserved | `0x00` | Майбутнє: температура корпусу (°C) |
| 7 | Cache load | `cache_count` (0–50) | Кількість дерев у кеші |
| 8–9 | Reserved | `0x00` | Майбутнє: CSQ модему (0–31) |
| 10 | GP / Status | `cache_count` (cap 63) | Proxy навантаження (bits [5:0]) |
| 11–15 | Reserved | `0x00` | Майбутнє: V_bat, fw_version |

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
| `forest_cache[50]` | `EdgeCache` | 1150 B | CIFO EdgeCache (50 × 23 байти, після **[E.8]** додано `snr` 1 байт) |
| `binary_batch_buffer[2048]` | `uint8_t` | 2048 B | Бінарний буфер перед шифруванням |
| `encrypted_batch_buffer[2064]` | `uint8_t static` | 2064 B | **static** (IV + зашифровані дані) |
| `pending_ota_bytecode[8192]` | `uint8_t` | 8192 B | RAM-буфер збірки OTA від Rails |
| `at_tx_buffer[256]` | `char` | 256 B | Формування AT-команд (`snprintf`) |
| `cmd_dedup_ring[16]` | `uint32_t` | 64 B | DJB2 хеші idempotency токенів |
| `cmd_decrypt_buf[544]` | `uint8_t` | 544 B | Decrypt buffer для CoAP команд/OTA |
| `incoming_lora_payload` (видалено в FW.3) | — | 0 B | Замінено на `lora_rx_ring[16]` (288 B) |
| `lora_rx_ring[16]` | `volatile LoRaRxSlot` | 288 B | **[FW.3 + E.8]** FIFO ring для ISR-пакетів (16 × 18 байтів = payload + rssi + snr) |
| `decrypted_payload[16]` | `uint8_t` | 16 B | Розшифрований пакет |
| `ota_chunk_bitmap` | `uint16_t` | 2 B | Bitmap отриманих OTA-чанків (16 біт) |
| `ota_chunks_received` | `uint16_t` | 2 B | Лічильник отриманих CoAP-чанків |
| `ota_total_expected_chunks` | `uint16_t` | 2 B | Очікуваний total від header |
| `pending_ota_size` | `uint16_t` | 2 B | Реальний зібраний розмір байткоду |
| Scalar variables | misc | ~24 B | `cache_count`, `current_rssi`, `lora_rx_head`, `lora_rx_tail`, `lora_rx_drops`, `ota_is_active`, `current_ota_chunk_idx`, `cmd_dedup_idx`, `cmd_dedup_used` |
| **Разом** | | **~14.7 KB** | З 64 KB SRAM = ~23% використання |

---

## 🔩 10. HAL Периферія Королеви

| Handle | Периферія | Призначення |
|--------|-----------|-------------|
| `huart1` | USART1 | SIM7070G модем (115200 baud) |
| `hsubghz` | SUBGHZ | LoRa трансивер SX1262 (868 MHz) |
| `hcryp` | AES | ECB для LoRa, CBC для CoAP батчів та команд |
| `hrng` | RNG | HRNG для CBC IV та Thundering Herd jitter |
| `hiwdg` | IWDG | Апаратний Watchdog (~26.6 с timeout, auto-reset при зависанні) |
| `hspi1` | SPI1 | Зовнішня NOR Flash **Winbond W25Q32JV** (4 MB) — Overflow Tier CIFO ([ARCH.35](00_08_Action_Plan_Tracker), [BOM поз. 16 → 02_05 §BOM](02_05_Queen_Hardware_and_Starlink)). Піни: `PB3=SCK`, `PB4=MISO`, `PB5=MOSI`, `PA4=CS` (GPIO software-driven). Driver: `firmware/queen/flash_buffer.c` (`w25q32_write_page`, `w25q32_read_sector`, `w25q32_erase_sector`). |

**Примітка:** Queen **не має** ADC, TIM, RTC — на відміну від Soldier. HRNG та IWDG ініціалізуються при старті. HRNG де-ініціалізується "on-demand" (Wu-Wei підхід — нульове споживання між використаннями). `hspi1` ініціалізується тільки в момент drain CIFO→Flash (overflow event) і де-ініціалізується одразу після — енерго-нейтральний підхід (W25Q32JV power-down 1 µA, page write ~10 мА × 0.7 мс).

> **Compile-time guard:** при відсутності `hspi1` у `main.h` (CubeMX) функції `w25q32_*` повертають `STATUS_NOT_AVAILABLE`, CIFO залишається в RAM-only режимі, але система не падає. Це SSOT-bridge між картою периферії (`03_02 §10`) та overflow-логікою (`02_05 §2.1 Flash Ring Buffer`).

---

## 🧪 11. Тестове Покриття (Host-Based, x86)

```bash
make -C firmware/test queen    # 128 тестів, ~0.1 секунди
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
| **CoAP Retry (FW.9)** | **4** | **`COAP_MAX_RETRIES=3`, `COAP_BASE_TIMEOUT_MS=2000`, `COAP_SEND_TIMEOUT_MS=5000`, `UART_RX_BUF_SIZE=128`** |
| **[FW.1] Flash Key Loading** | **8** | `Load_AES_Key()` magic check, key-not-provisioned → Error_Handler |
| **[FW.20] Time Sync Envelope + Beacon** | **8** | CMD_TIME_SYNC strip, beacon plaintext layout, ts=0 guard |
| **[FW.20-S2] Beacon Authoritativeness Flag** | **2** | byte 9 bit 7 (`BEACON_AUTH_FLAG=0x80`) — Королева транслює `byte9 = 0x81` (auth=1 \| TTL=1). Підготовчий патч до повного mesh-relay: relay-маяки від Провідників матимуть auth=0, Soldier-ам арбітруватиме authoritative першим. Layout `[0x9C][ts_be:4][reserved:0×4][AUTH_FLAG\|TTL][magic 'B'][padding:0×5]`. |
| **[FW.27-B] Magic Re-Request Handler** | **10** | Bitmap accept/dedup, total mismatch, no-active-OTA |
| **[FW.23] HMAC Trailer Relay** | **4** | 3 segs storage, seg_idx>3 reject, marker mismatch |
| **[FW.3] LoRa RX Ring Buffer** | **13** | FIFO семантика, capacity 15, переповнення → drop counter, RSSI clamp passthrough, 25-сек flush сценарій (30 ISR пакетів → 15 уцілілих + 15 видимих втрат) |
| **Всього** | **128** | *(queen-specific: 128; раніше 113)* |

**Не покрито host-тестами (потребує hardware-in-loop):**
- AT command response parsing на реальному SIM7070G (boot-time CNMP/CPSMS/CEDRXS)
- CoAP retry logic при мережевих помилках LTE-M / Starlink DTC
- ✅ Single-packet buffer overwrite — закрито host-тестами FW.3 (симуляція) + 25-сек flush scenario test
- Повна async UART DMA flush — наступна ітерація FW.3 (вимагає DMA controller hardware)

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
| Factory Flashing | BLOCKER-1 (AES key) блокує масове виробництво |

---
