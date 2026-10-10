# 03_02: Прошивка Шлюзу Королеви (LoRa RX → Dedup → CIFO → SIM7070G TX)

---

## 🎯 Мета

Зафіксувати повний алгоритм роботи вузла **Queen** (шлюз-агрегатор на базі STM32WLE5JC + модем SIM7070G) — від прийому зашифрованого LoRa-пакета від Солдата до відправки бінарного батча на Rails-бекенд через CoAP/UDP. Документ визначає механізм дедуплікації пакетів (CIFO EdgeCache), алгоритм евікції, логіку OTA-бродкасту та повний цикл взаємодії з GSM-модемом.

> **Критична залежність:** Королева є єдиною точкою виходу ZK-пакетів у Proof of Growth Pipeline (05_02). Втрата пакетів телеметрії на рівні Королеви → ZK-proof не формується → мінтинг SCC блокується → токеноміка руйнується.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — C-код шлюзу написаний, host-based тести зелені (`make -C firmware/test queen`). Відкрите → пункти [`00_07`](00_07_Action_Plan_Tracker), чий meta-рядок веде `→ 03_02`, у будь-якій секції: здебільшого §03a, а також HW.41 (§02b; uplink першого деплою — init і PDP, §4), SEC.38 (§03b) і ARCH.54 (§06).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Soldier lifecycle, binary packet, DID provisioning, RTC map |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Hardware Queen, SIM7070G, Starlink/Helium |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | AES режими, ключі (§3.1), HRNG IV |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `UnpackTelemetryWorker` (батч [IV:16][CBC ciphertext]) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Втрата пакетів Queen → ZK-proof/мінтинг |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT) — ростера тут не ведемо (перелік ID згнив, пропускаючи більшість живих пунктів): пункти, чий meta-рядок веде `→ 03_02`, у будь-якій секції — здебільшого [`00_07 §03a`](00_07_Action_Plan_Tracker), а також HW.41 (§02b, uplink першого деплою), SEC.38 (§03b) і ARCH.54 (§06) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Архітектура: Повний Data Flow](#-архітектура-повний-data-flow)
- [0. Всі #define Константи (SSOT)](#-0-всі-define-константи-ssot)
- [1. LoRa Reception та ISR](#-1-lora-reception-та-isr)
- [2. CIFO EdgeCache (Алгоритм дедуплікації та кешування)](#-2-cifo-edgecache-алгоритм-дедуплікації-та-кешування)
- [3. Flush: Бінарна Упаковка та AES-CBC](#-3-flush-бінарна-упаковка-та-aes-cbc)
- [4. SIM7070G Модем: Життєвий Цикл та AT-Команди](#-4-sim7070g-модем-життєвий-цикл-та-at-команди)
- [5. OTA Broadcast (Reflex Shot — LoRa Downlink до Солдатів)](#-5-ota-broadcast-reflex-shot--lora-downlink-до-солдатів)
- [5а. Time Sync (FW.20, FW.20-S2) — Канонічний хаб](#-5а-time-sync-fw20-fw20-s2--канонічний-хаб)
- [5б. Soldier Command Relay (FW.20-Q2) — черга рефлекторних пострілів](#-5б-soldier-command-relay-fw20-q2--черга-рефлекторних-пострілів)
- [6. Actuator Command Dedup (Idempotency Ring Buffer)](#-6-actuator-command-dedup-idempotency-ring-buffer)
- [7. Пульс Королеви — health-блок QATT-v2](#-7-пульс-королеви--health-блок-qatt-v2-arch54-did0-sentinel-retired)
- [7а. Device-Event Forward — L1 canary-канал](#-7а-device-event-forward--l1-canary-канал-sec21)
- [8. Шифрування: Режими та Переходи](#-8-шифрування-режими-та-переходи)
- [9. RAM Бюджет Королеви](#-9-ram-бюджет-королеви)
- [10. HAL Периферія Королеви](#-10-hal-периферія-королеви)
- [11. Тестове Покриття (Host-Based, x86)](#-11-тестове-покриття-host-based-x86)
<!-- TOC:AUTO:END -->

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
║    MX_SUBGHZ_Init → MX_CRYP_Init (AES-128-ECB, LoRa channel)                         ║
║    Radio.Init → Radio.SetChannel(868 MHz)                                ║
║    memset(forest_cache) → memset(cmd_dedup_ring)                         ║
║    SIM7070_SendATCommand("AT\r\n", 500ms)                               ║
║    SIM7070_SendATCommand("AT+CNMP=38\r\n", 1000ms)  ← LTE only         ║
║    Radio.Rx(LORA_RX_INFINITE)  ← Відкриваємо вуха                      ║
║    current_jitter = HRNG() % 60001  ← Thundering Herd prevention        ║
║                    (fallback: HAL_GetTick() ^ uid_hash ^ маска)          ║
║                                                                          ║
║  [MAIN LOOP]                                                             ║
║    ┌─────────────────────────────────────────────────────────┐          ║
║    │  while (LoRa_Rx_Ring_Pop(rx_payload,&rx_len,&rx_rssi,&rx_snr)):  │  ║
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
║    │    ├── Health-блок у QATT-v2 header (ARCH.54)          │          ║
║    │    ├── Flush_Cache_To_Rails()                          │          ║
║    │    │     Pack → CBC Encrypt → CoAP PUT                │          ║
║    │    └── Regenerate jitter (HRNG)                        │          ║
║    └─────────────────────────────────────────────────────────┘          ║
║                                                                          ║
╠══════════════════════════════════════════════════════════════════════════╣
║  CoAP/UDP → port 5683 → lib/daemons/coap_listener                      ║
║  URI-Path: /telemetry/batch/<queen_uid>                                  ║
╚══════════════════════════════════════════════════════════════════════════╝
         │
         ▼
   Rails Backend (UnpackTelemetryWorker → TelemetryUnpackerService)
```

**Ключовий інваріант:** `LoRa RX → Dedup → CIFO Cache → SIM7070G CoAP TX`

---

## 📐 0. Всі #define Константи (SSOT)

| Константа | Значення | Файл | Призначення |
|-----------|----------|------|-------------|
| `LORA_RX_INFINITE` | `0xFFFFFF` | main.c | Нескінченний таймаут RX |
| `FLUSH_INTERVAL_MS` | `3 600 000` | main.c | Інтервал flush (1 год.); ⚖️ FW.64 2026-09-28 — `600 000` (10 хв) парою з Rails-дзеркалом, разом з актуаторною прошивкою ARCH.75 (§4а) |
| `FLUSH_JITTER_MAX_MS` | `60 000` | main.c | Макс. jitter (60 сек) |
| `RNG_FALLBACK_XOR_MASK` | `0xA5A5A5A5UL` | main.c | XOR-маска при відмові HRNG (jitter) |
| `FLUSH_HEADROOM` | `5` | main.c | Слоти до примусового flush |
| `OTA_MAX_CHUNKS` | `16` | main.c | Макс. CoAP-чанків (bitmap 16 біт) |
| `CACHE_MAX_ENTRIES` | `50` | `queen/cifo_cache.h` | Місткість CIFO EdgeCache |
| `CMD_DEDUP_SIZE` | `16` | main.c | Розмір кільцевого буфера dedup |
| `UUID_STR_LEN` | `36` | main.c | Довжина UUID рядка (8-4-4-4-12) |
| `CMD_DECRYPT_BUF_SIZE` | `544` | main.c | Буфер decrypt CoAP команд/OTA. **Деривація (відновлено 2026-08-22 з git — константа стояла магічною):** `512` OTA payload + `5` header + `2` CRC + `16` AES padding + `9` margin. Міняючи будь-який доданок, перерахуй суму тут, а не підганяй її |
| `OTA_MARKER` | `0x99` | main.c | Маркер OTA-пакета |
| `OTA_HEADER_SIZE` | `5` | main.c | Маркер + idx:2 + total:2 |
| `OTA_CRC_SIZE` | `2` | main.c | CRC16-CCITT |
| `AES_BLOCK_SIZE` | `16` | main.c | AES block size (128-bit, фіксований AES spec — рівне для AES-128 та AES-256) |
| `MAX_OTA_CHUNK_PAYLOAD` | `512` | main.c | Макс. байткод у CoAP-чанку |
| `OTA_COAP_HEADER_SIZE` | `7` | main.c | [FW.53] CoAP-шар (Rails→Queen): `[0x99][index:2][total:2][len:2]` — явний len |
| `OTA_COAP_MIN_FRAME` | `10` | main.c | [FW.53] `OTA_COAP_HEADER_SIZE + 1 + OTA_CRC_SIZE` — мін. валідний CoAP-чанк |
| `AT_INTERBYTE_TIMEOUT_MS` | `150` | main.c | [FW.3] Пауза між байтами UART = «модем дослухав» |
| `AT_INIT_BUDGET_MS` | `2000` | main.c | [FW.3] Бюджет однієї init-команди (ATE0/AT/CNMP/CMNB/CGDCONT/CNCFG/CPSMS/CEDRXS/CNACT) |
| `COAP_CONV_BUDGET_MS` | `15000` | main.c | [FW.3] Повна CoAP-розмова NEW→SEND→NMI→DEL (< вікно IWDG) |
| `COAP_MAX_RETRIES` | `3` | main.c | [FW.9] Спроби доставки батча |
| `COAP_SERVER_HOST` | `"api.silkennet.com"` | main.c | [FW.56] Хост для CDNSGIP (CCOAPNEW приймає лише IP) |
| `COAP_SERVER_PORT` | `5683` | main.c | CoAP UDP-порт |
| `AT_LINE_MAX` | `160` | at_engine.h | [FW.3] Стеля AT-лінії (довші — truncated, класифікація живе) |
| `AT_HEX_CHUNK` | `32` | sim7070_coap.h | [FW.3] Байтів PDU на один UART TX (64 hex-символи) |
| `QATT_*` (layout) | — | `common/queen_attest.h` | [L1 QATT] One-Home розкладка підписаного батч-конверта (зсуви/residue/префікс); wire-дім — [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security) |
| `FLASH_ED25519_SEED_MAGIC` | `"EDSK"` | main.c | [L1 QATT] Magic сім'ї голосу Королеви (слот після KEYC; дзеркало CommandBuilder) |

---

## 📡 1. LoRa Reception та ISR

> **Роль у вирішенні Проблеми Рандеву:** Королева є **єдиним always-on listener** у мережі. Її SX1262 завжди в `Radio.Rx(LORA_RX_INFINITE)` — нескінченний таймаут прийому. 🔴 **І «завжди» тримає НЕ цей виклик, а `SetRxConfig(… rxContinuous = true)` у базлайні модуляції** ([FW.61], профіль — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)): драйвер читає прапорець зі свого стану, і без нього `RadioInit` лишає `false`, тобто RX-**single** при будь-якому таймауті. Доти виклику не було зовсім — тож цей абзац описував намір, а не запрограмовану поведінку. Це вирішує фундаментальну Проблему Рандеву (Rendezvous Problem) для всіх вузлів у прямій видимості (150–200 м): Солдат може "вистрілити" пакетом у будь-яку мілісекунду — Королева завжди зловить. Це можливо завдяки зовнішньому живленню (сонячна панель / акумулятор), на відміну від Солдатів з EBFC біобатарейкою. Для вузлів за межами прямої видимості Queen потрібні Синхронні Вікна (TDMA, L2 — 🟡 host-half: розкладка в маяку INERT до bench, §5а.2а) та CAD (L3 — 🟡 host-half: Soldier-side нюх/преамбула, Queen-wire не додає) ([ARCH.26](00_07_Action_Plan_Tracker), деталі — [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA)).

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
    LoRa_Rx_Ring_Push(payload, (uint8_t)size, (int8_t)rssi, snr);
}
```

**Параметри прийому:**
| Параметр | Значення | Опис |
|----------|----------|------|
| Частота | 868 MHz | Регіон ЄС/Україна |
| Розмір пакета | 16 байт | Повний AES-блок (block size = 128 bit; key size = AES-128 post-ARCH.42 LoRa) |
| Таймаут RX | `LORA_RX_INFINITE = 0xFFFFFF` | Нескінченне очікування |
| UART baud | 115200 | SIM7070G модем |
| `snr` параметр | **використовується як CIFO tiebreaker (E.8)** | SX1262 SNR плюметься через ring buffer у `EdgeCache.snr`. У `Process_And_Cache_Data` він активується **лише** як tiebreaker: коли два non-critical (status=0) записи мають **однаковий** найгірший RSSI — той з нижчим SNR (шумніший канал → пакет імовірніше прийшов через інтерференцію та став stale) виганяється першим. RSSI залишається primary key, `bio_status` priority undisturbed. 7 host-тестів у `firmware/test/test_queen_logic.c` (`test_e8_*`). |

**[FW.3] LoRa RX Ring Buffer (single-producer / single-consumer FIFO):**

| Поле | Тип | Розмір | Призначення |
|------|-----|--------|-------------|
| `lora_rx_ring[16]` | `volatile LoRaRxSlot` | 16 × 19 = 304 B (ECB; у CCM-ері payload = air — леджер [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)) | FIFO слоти (payload + 1 байт `len` [FW.2] + 1 байт rssi + 1 байт snr [E.8]) |
| `lora_rx_head` | `volatile uint8_t` | 1 B | Куди ISR кладе наступний пакет |
| `lora_rx_tail` | `volatile uint8_t` | 1 B | Звідки main loop забирає |
| `lora_rx_drops` | `volatile uint16_t` | 2 B | Лічильник переповнень (видимий для майбутнього gateway-health export) |

Ефективна capacity = `LORA_RX_RING_SIZE - 1 = 15` (один слот віддано на розрізнення full vs empty). ARM Cortex-M4 атомарність 8-біт читання/запису гарантує lock-free ISR↔main coordination без `__disable_irq()`. На host-тестах volatile-лічильники поводяться як звичайні uint8 — single-thread детерміністичний доступ, логіка empty/full однакова.

**Замінено в FW.3 (2026-05-02):** `incoming_lora_payload[16]` + однобітний `lora_rx_flag` → ring buffer. Було: ISR під час 25-секундного CoAP-flush'у мовчки перезаписував попередній голос; main loop бачив тільки останній. Стало: до 15 голосів чекають у рингу; переповнення видиме через `lora_rx_drops`.

---

## 🗄️ 2. CIFO EdgeCache (Алгоритм дедуплікації та кешування)

### Структура даних

Слот `EdgeCache` (`uid` · `payload` · `rssi` · `snr` · `is_active` · `fmt`), формати, гейтована ширина payload і вся логіка дедуп/вставки/витіснення — pure-заголовок **`firmware/queen/cifo_cache.h`**, який компілюють і `main.c`, і host-тести. `main.c` тримає лише масив `forest_cache[CACHE_MAX_ENTRIES]`, лічильник `cache_count` (тригер флашу й `fill_pct` health-блоку QATT) і ARCH.35-хук спілу. ⛔ Не повертати рукописну копію структури чи функції в тест: копія вже раз розійшлась із прошивкою так, що сюїта зеленіла, поки прошивка не рахувала вставок. RAM-розміри — леджер [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security).

> **[FW.2, INERT за `FW2_CCM_ENABLED`]** У CCM-ері слот несе опаковий air-хвіст `air − 4` (rev2.1 = 26 Б — Королева НЕ розшифровує, інверсія довіри [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)) + `fmt`-тег (`EDGE_FMT_ECB16|EDGE_FMT_CCM_AIR`); `len`-тегований RX-ринг приймає 16 | air (rev2.1 = 30). bio_status для евікції видно лише в ECB16-слотах (у CCM ті байти — шифртекст; офсет-колізія — firmware-скіл gotcha #7); CCM-записи евіктяться за RSSI/SNR — свідома стеля сліпого кур'єра, довгий лік = ARCH.35-ринг. RAM-ціна фліпа — леджер [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) (One-Home чисел).

### Алгоритм `Process_And_Cache_Data(uid, payload, rssi, snr, fmt)` → `Cifo_Upsert`

```
Крок 1 — ДЕДУПЛІКАЦІЯ:
  Пошук uid в усіх is_active слотах.
  Якщо знайдено → оновити payload + rssi + snr + fmt → return (is_active не чіпається).
  (Найсвіжіші дані завжди перемагають старі)

Крок 2 — ВСТАВКА:
  Перший is_active==0 слот (незалежно від лічильника) → записати → cache_count++ → return.
  (Інкремент живе в Cifo_Upsert, не в каллера.)

Крок 3 — CIFO Priority-Aware EVICTION (кеш повний):
  Мета: витіснити некритичне (homeostasis, bio_status==0) дерево з найгіршим RSSI.
  Fallback: якщо ВСІ записи критичні → витіснити абсолютно найгірший RSSI.

  bio_status = (payload[10] >> 5) & 0x03   // [FW.29-PACK] bits 6..5 (status), bit 7 = PANIC_FLAG_BIT
    0 = homeostasis (кандидат на витіснення)
    1 = stress      (захищений)
    2 = anomaly     (захищений)
    3 = vm_error    (захищений; софт-збій, НЕ tamper)
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
// ARCH.35-хук спілу бачить жертву ДО перезапису; далі uid/payload/rssi/snr/fmt, is_active = 1 (навіть поверх 2), cache_count не змінюється
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

> **[FW.2, INERT]** CCM-ера: запис = **31 Б** (air+1, rev2.1; розкладка — 📐 [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) cross-ref; білдер `firmware/queen/rx_route.h`, golden-звірений), 50 × 31 = 1550 ≤ 2048 — запас лишається. Батч ОДНОРІДНИЙ (Rails тримає один stride): 16B-телеметрія не-прошитих Солдатів дропається з лічильником, health-запис DID=0 не пакується (фліп-гейти → [`00_07`](00_07_Action_Plan_Tracker) FW.2).

**RSSI інверсія:** `(uint8_t)(-(int16_t)rssi)` — `int16_t` cast запобігає UB при rssi == −128 (мінімум int8_t).

**[FW.51] Lifecycle слотів:** пакування лише читає кеш — слоти звільняються не тут, а аж після підтвердженого `send_success` (§4 крок 5). Інакше провал CoAP знищив би вже зібрану, але ще не доставлену телеметрію. **Викликач свідомо НЕ змінено на негайний re-flush** (energy-conservative): count-тригер і так повторює при повному кеші, а low-occupancy чекає ≤ 1 год — інакше retry-шторм на мертвому LTE висушив би Королеву.

### Крок 2: AES-256-CBC Encrypt

```
1. Padding: вирівнювання до 16 байт (нульовий pad)
   padded_size = ((offset + 15) / 16) * 16  ← AES block alignment
   Захист: if (padded_size > sizeof(binary_batch_buffer)) → cap

2. Generate IV: HRNG "Wu-Wei" підхід:
   hrng.Instance = RNG
   HAL_RNG_Init(&hrng)  ← ініціалізація тільки перед використанням
   for i in 0..3: HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]); збій → break
   якщо HRNG збійнув — УВЕСЬ IV з ключової PRF [SEC.12]:
     coap_fallback_iv(batch_iv, coap_key, tick, uid_hash,
                      queen_unix_ts, coap_flush_seq)
       ← HMAC-SHA256(coap_key, label ‖ uid_hash ‖ unix_ts ‖ flush_seq ‖ tick)[0:16]
         (firmware/queen/coap_iv.h): унікальний І непередбачуваний без
         ключа; host-tested проти OpenSSL у firmware/test/test_encryption.c
   HAL_RNG_DeInit(&hrng)  ← деініціалізація зразу після

3. Switch CRYP: hcryp.Init.Algorithm = CRYP_AES_CBC
   hcryp.Init.pInitVect = batch_iv
   HAL_CRYP_Init(&hcryp)

4. Encrypt: HAL_CRYP_Encrypt(binary_batch_buffer, padded_size/4,
                             batch_attest_buffer + QATT_CT_OFFSET, 2000)
   IV лягає на QATT_IV_OFFSET того ж буфера.

5. Restore ECB → [L1 QATT, якщо EDSK-сім'я прошита] header + право-вирівняний
   префікс домену+UID + Ed25519-підпис хвостом (розкладка/повідомлення —
   One-Home: common/queen_attest.h, wire-дім: 03_05 §2.2). Сім'ї нема →
   legacy [IV][ct] без жодних змін.

static uint8_t batch_attest_buffer[QATT_BUFFER_SIZE];  ← static (не стек!)
```

**Два різні HRNG fallback — не плутати:**
| Місце | Fallback при HRNG fail | Маска | Пояснення |
|-------|------------------------|-------|-----------|
| CBC IV generation (batch) | `coap_fallback_iv(…)` — HMAC-SHA256 під `coap_key`, дім: `firmware/queen/coap_iv.h` | увесь IV однією PRF (не по словах) | [SEC.12] унікальний І непередбачуваний без ключа (§HRNG Fallback у [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)); host-тести `test_encryption.c` |
| Jitter — старт і регенерація після flush | `HAL_GetTick() ^ uid_hash ^ RNG_FALLBACK_XOR_MASK` | `0xA5A5A5A5UL` + djb2(UID) | Обидва сайти однакові; `uid_hash` розводить Королеви з однаковим часом увімкнення. Jitter — не криптооперація, стійкість не потрібна |

> **Примітка:** слабким при масовому blackout лишається лише jitter-fallback, і йому безпека не потрібна; CoAP CBC IV від HRNG не залежить — PRF під ключем.

### Крок 3: Відновлення ECB

```c
// [FIX: CRITICAL — ECB Restoration] — дім: Restore_ECB_Mode() у queen/main.c
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.KeySize   = CRYP_KEYSIZE_128B;  // CBC-сесія лишила 256-бітний coap_key
hcryp.Init.pKey      = aes_key;            // LoRa-ключ Королеви
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);                     // відмова → RCC-reset AES → retry → NVIC_SystemReset
// Без усіх трьох полів — всі наступні LoRa decrypt дають сміття
```

> **[FW.3] Порядок:** restore тепер стоїть **одразу після** `HAL_CRYP_Encrypt`,
> ще до модемної розмови (§4) — вікно чужого CRYP-режиму нульове, скільки б
> не тривали DNS/NEW/NMI.

---

## 📱 4. SIM7070G Модем: Життєвий Цикл та AT-Команди

> **🔴 [FW.56] Знахідка pre-bench (2026-06-07): модем — UDP-труба, не CoAP-стек.**
> Попередня версія цього розділу (і коду) використовувала граматику
> `AT+CCOAPNEW="coap://host:port"` + `AT+CCOAPSEND=<cid>,<method>,"<uri>",<len>,"<hex>"` —
> **такої граматики в сімействі SIMCom не існує**. Офіційна CoAP App Note
> (сімейство SIM70xx; звірено посторінково з PDF) дає:
> `AT+CCOAPNEW="<ip>",<port>,<cid>` → `+CCOAPNEW: <cid>` → `OK`;
> `AT+CCOAPSEND=<cid>,<len>,"<hex>"`, де hex = **сирий CoAP PDU**, який будує
> хост-MCU; відповідь сервера прилітає URC `+CCOAPNMI: <cid>,<len>,"<hex>"`
> (теж сирий PDU). Доменів CCOAPNEW не приймає → потрібен крок `AT+CDNSGIP`.
> **Bench-рядок:** verbatim-звірка SIM7070-ноти V1.03 (`firmware/scripts/bench/RUNBOOK.md`).

> **📡 [FW.60] Inbound-тракти модема (розвідка 2026-07-12; AT Manual V1.03 + TCPUDP-нота V1.02, звірено посторінково):**
> для *вхідних* байтів у модема два тракти. **(а) CCOAP-розмова:** відповідь сервера = один
> hex-URC `+CCOAPNMI` → стеля PDU ≈ ⌊(`AT_LINE_MAX`−overhead)/2⌋ ≈ 60-70 Б — стеля **наша**
> (буфер рядка токенайзера), модемна стеля довгого NMI невідома (bench). **(б) CA\*-сім'я:**
> `AT+CAOPEN=<cid 0-12>,<pdp>,"UDP","<host≤64>",<port>` (DNS сам) → `CASEND` ≤1459 Б
> (промпт `>` — голий, БЕЗ `\n`, читається посимвольно повз токенайзер) →
> вхідне модем буферизує і будить коротким URC `+CADATAIND: <cid>` (офіційна NOTE мануалу) →
> `AT+CARECV=<cid>,≤1459` віддає **сирі** (не hex) лічені байти — повнорозмірний PDU одним
> читанням; `CASTATE`/`CACLOSE` керують життям. `CASERVER` (UDP/TCP listen) у модемі існує,
> але мережево мертвий за CGNAT (спостережена адреса шлюза = egress — [`04_01`](04_01_Data_Models_and_Entities)).
> Модемний DTLS-PSK (`CASSLCFG`+`PSKTABLE`) відхилено: ключ у модем + PSK plaintext'ом в AT —
> проти Zero-Trust і FW.56-уроку.
> **Wire-up ✅ (2026-07-12): увесь poll їде трактом (б)** — друге читання стелі
> фальсифікувало «CMD ≤60 Б через CCOAP»: найменший CMD-конверт (UUID-36 + 0x9C-конверт +
> CBC-pad + IV) = ~80 Б > NMI-стеля, обрізаний hex = втрачена сирена; тракт (а) лишається
> чистим uplink'ом. Механіка poll'а — §4а нижче; бенч-residual — [`00_07` FW.60](00_07_Action_Plan_Tracker).

### Архітектура (FW.3 + FW.56): три pure-шари + UART-клей

| Шар | Файл | Відповідальність | Host-тести |
|-----|------|------------------|------------|
| RX-кільце | `firmware/queen/uart_rx_ring.h` | Кільце-вид поверх circular-DMA: абсолютні лічильники (wraps·size + NDTR), монотонний clamp проти IRQ-латентності, overrun-детект + лічильник | `firmware/test/test_uart_rx_ring.c` (гонки знімка, wrap, overrun, інтеграція з токенайзером) |
| Токенайзер | `firmware/queen/at_engine.h` | Байт→лінія→подія (`OK`/`ERROR`/`+CME ERROR: n`/URC), early-exit, транзакції, hex-кодек, парсери лапок; **[FW.60]** `At_Read_N` — лічене binary-read повз токенайзер (сирі байти `CARECV` несуть `0x0A`) | `firmware/test/test_at_engine.c` |
| CoAP PDU | `firmware/queen/coap_pdu.h` | RFC 7252: CON PUT `/telemetry/batch/<uid>` builder + розбір відповіді (клас 2.xx, MID); **[FW.60]** `Coap_Build_Get` (Uri-Path + Uri-Query, опція на пару) + `Coap_Reply_Extract_Payload` (skip token/options до `0xFF`) | ↑ (golden-вектор — дослівно з SIMCom-ноти; GET-golden = freeze-contract зі `spec/lib/coap_server_pdu_spec.rb`) |
| Оркестратор uplink | `firmware/queen/sim7070_coap.h` | `CDNSGIP → CCOAPNEW → CCOAPSEND(hex чанками) → +CCOAPNMI → CCOAPDEL` | ↑ (скриптований модем, повні розмови) |
| Оркестратор poll **[FW.60]** | `firmware/queen/sim7070_udp.h` | Сира UDP-розмова: `CAOPEN → '>'-промпт → CASEND(сирий PDU) → +CADATAIND → CARECV(лічені сирі байти ≤1459) → CACLOSE`; `+CARECV: n,`-заголовок читається посимвольно | ↑ (happy-path + 3 fail-шляхи, сирі байти з `0x0A`) |
| UART-клей | `main.c` (`MX_USART1_RX_DMA_Init`, `Uart_Ring_Sync`, `Uart_At_Source/Sink`, `SIM7070_Transact`) | DMA-ініт + консистентний знімок (double-read wraps довкола NDTR) + владар дедлайнів (`UartAtIo`) | компілюється cppcheck-гейтом |

Латентність: токенайзер виходить на фіналі — обмін коштує реальний час
відповіді модему, а не повний timeout (стара схема `HAL_UART_Receive(128B)`
поверталась лише по таймауту → кожна команда «коштувала» весь бюджет).

**RX-вухо (FW.3, circular-DMA):** залізо пише в кільце безперервно і без
CPU — байти й URC поза вікном читання (запізнілий `+CCOAPNMI`, `RDY` після
ребуту модема) більше не гинуть в ORE, як у попередній побайтовій схемі.
Семантика `AT_INTERBYTE_TIMEOUT_MS` збережена (тиша = «модем дослухав»).
**Гігієна свіжості:** drain застояних байтів — перед кожною init-командою
(`SIM7070_Transact`: відповідь мусить належати *цій* команді; пізній `OK`
від таймаутнутого `CCOAPDEL` годину тому не сміє підтвердити нову) та один
раз на старті CoAP-розмови — але **НЕ** між retry: запізнілий `+CCOAPNMI`
з MID цієї розмови = законна доставка, заради якої кільце й існує.

### Ініціалізація (один раз при старті, response-driven)

Послідовність — ОДНА таблиця `firmware/queen/sim7070_init.h` (`kSim7070Init` + `Sim7070_Init_Run`), яку виконують і прошивка, і host-тест: ручна копія в тесті доводила б саму себе (`firmware`-скіл гоча #19). Граматику кожного рядка звірено текстом із AT Command Manual V1.03 (2026-09-27); мануал ≠ модем — живий транскрипт `firmware/scripts/bench/RUNBOOK.md` 5.2.

> ⚖️ **Cat-M ⊥ NB-IoT — `AT+CMNB=3` явно, eDRX для обох AcT (ратифіковано founder 2026-09-26 за рекомендацією; [`00_07`](00_07_Action_Plan_Tracker) HW.41).** **Підстава:** до цього дня init не задавав RAT узагалі — `CNMP=38` означає лише «LTE only», а вибір Cat-M ⊥ NB-IoT є окремою `AT+CMNB` у режимі AUTO_SAVE, тож модем тримав те, що в ньому збережено; Kyivstar публічно заявляє NB-IoT, а не LTE-M ([`queen_antenna_shortlist`](protocols/hardware/queen_antenna_shortlist.md) §5), і зі збереженим `=1` Королева не підʼєдналась би. Заразом виявилось, що eDRX запитувався з `AcT`=5, тобто лише для NB-IoT (коментар коду казав «LTE Cat M1»). **Ціна:** NB-IoT може взяти гору й там, де є Cat-M — вужчий uplink, інша поведінка PSM/eDRX, повна OTA-серія довша. **Найслабша ланка:** пріоритет RAT при `=3` мануал не описує, а який RAT оператор дає на M2M-SIM, скаже лише активація ([`00_07`](00_07_Action_Plan_Tracker) HW.41, нога SIM); публічна первинка 2026-10-04 називає лише NB-IoT, а чи вмикається він на SIM тарифу для пристроїв без окремого замовлення, не каже ніде ([`queen_antenna_shortlist`](protocols/hardware/queen_antenna_shortlist.md) §5, лист [`queen_sim_operator_rfq`](protocols/procurement/queen_sim_operator_rfq.md) п. 2). Носії — таблиця `firmware/queen/sim7070_init.h`, яку кличуть і `main.c`, і `test_queen_logic.c` (`test_hw41_init_run_transcript_default_build` · `test_hw41_rat_selection_then_apn` · `test_hw41_edrx_requested_for_both_act`; мутація «прибрати AcT=4» → RED).

| AT-команда | Бюджет | Призначення |
|------------|--------|-------------|
| `ATE0` | `AT_INIT_BUDGET_MS` | Вимкнути ехо (токенайзер його переживає, але ефір чистіший) |
| `AT` | `AT_INIT_BUDGET_MS` | Перевірка зв'язку з модемом |
| `AT+CNMP=38` | `AT_INIT_BUDGET_MS` | Режим «лише LTE» (вимикає GSM, не NB-IoT) — SIMCom AT Command Manual V1.03 §5.2.16. ⚠️ Несучий і для антени поз. 11: GSM-стелі підсилення модуля нижчі за пік рекомендованої антени ([`queen_antenna_shortlist`](protocols/hardware/queen_antenna_shortlist.md) §2.1). Тому це **ворота передачі** (HW.31, 2026-09-26): init тримає результат (`lte_only_ok`), а flush перед першою RF-командою кличе `Sim7070_Ensure_Lte_Only` (`sim7070_coap.h`). Режим — стан заліза, тож ознаку щофлешу **перечитують** (`AT+CNMP?`, 2026-09-27): «+CNMP: 38» → далі без жодного байта більше; режим інший чи нечитаний, або ознаки ще нема → CNMP=38 знову, і до OK ні DNS, ні PUT, ні poll; на OK — переактивація PDP (`AT+CNACT=1,1`). Host-тест `test_hw31_lte_only_gate` покриває саму функцію воріт, не її місце в `main.c` (його host не компілює). Init шле `AT+CNACT` лише за підтвердженого режиму. ⚠️ Дві стелі: реєстрацію модем робить сам, тож ворота тримають ДАНІ й PDP, не сигналізацію реєстрації свіжого модема до першого OK; і режим **AUTO_SAVE** (V1.03 §5.2.16, звірено 2026-09-27) — самочинний ребут модема його НЕ скидає, тож readback стереже вужче: втрату NVRAM чи заводський скид модема без ребута Королеви |
| `AT+CMNB=3` | `AT_INIT_BUDGET_MS` | [HW.41] Cat-M **і** NB-IoT — вибір RAT явно, а не збереженим у модемі станом (`CMNB` — AUTO_SAVE, дефолт мануал не називає; §5.2.17) |
| `AT+CGDCONT=1,"IP","<QUEEN_APN>"` | `AT_INIT_BUDGET_MS` | [HW.41] Явний 3GPP PDP-контекст (cid 1…15, AUTO_SAVE — V1.03 §6.2.2, звірено 2026-09-27) — `QUEEN_APN` build-time `#ifndef`-override (дефолт `""`, 3GPP-порожній APN, behavior-identical з до-HW.41 auto-APN) |
| `AT+CNCFG=1,1,"<QUEEN_APN>"` | `AT_INIT_BUDGET_MS` | [HW.41] APN **APP-мережі** SIMCom — окрема сім'я контекстів із власним простором номерів (`pdpidx` 0…3 ⊥ `cid` CGDCONT 1…15, V1.03 §7.2.2), тож APN з CGDCONT вона не бере; шлеться ЛИШЕ за заданого `QUEEN_APN` — порожній рядок модем може прочитати не як null, а неконфігурований білд лишає підписочний дефолт (APN null) недоторканим. Живий транскрипт — `firmware/scripts/bench/RUNBOOK.md` 5.2 |
| `AT+CPSMS=…` / `AT+CEDRXS=1,4,…` + `AT+CEDRXS=1,5,…` | `AT_INIT_BUDGET_MS` | PSM/eDRX (деталі 3GPP — коментарі в `main.c`); eDRX запитано для ОБОХ AcT — 4 = CAT-M, 5 = NB-IoT (§5.2.42), бо RAT обирає мережа (`CMNB=3`) |
| `AT+CNACT=1,1` | `AT_INIT_BUDGET_MS` | [HW.41] Активація APP-мережі (pdpidx 1). Синтаксис і режим звірено з V1.03 §7.2.1 (2026-09-27): `<action>` 0 Deactive · 1 Active · 2 Auto Active, режим **NO_SAVE** — після самочинного ребута модема контекст сам не встає, тому провал лікує наступна розмова (абзац нижче). ⛔ Auto Active (`=1,2` — модем сам повторює невдалу активацію) свідомо не взято: фоновий повтор при недоступній мережі може тримати модем поза PSM, а цієї енергії ніхто не міряв — кандидат стенда `[bench:coap]`. APN цього контексту задає `AT+CNCFG` (рядок вище). Живий транскрипт — `firmware/scripts/bench/RUNBOOK.md` 5.2, [`00_07`](00_07_Action_Plan_Tracker) HW.41 |

Провал init не фатальний: модем міг ще прокидатись. ⚠️ Але flush повторює лише CoAP-розмову (DNS/PUT), не
init-команди: несучу з них (`AT+CNMP=38`, HW.31) перевіряють ворота кроку 0а, решта лишається з тим, що модем зберіг.
Провал PDP (init чи пізній) лікує НАСТУПНА розмова ([`00_07`](00_07_Action_Plan_Tracker) HW.41, 2026-09-27): невдалий
init-`CNACT`, провал DNS чи всіх retry PUT ставлять підозру (`g_pdp_suspect`), і наступний flush спершу переактивує
PDP (`Sim7070_Reactivate_Pdp`, best-effort — ERROR тут може означати й «уже активний», вердикт дає сама розмова).

### CoAP Flush Sequence (кожен flush)

```
0. [FW.16→FW.3] Restore_ECB_Mode() — ОДРАЗУ після CBC-encrypt батча,
   ще ДО розмови з модемом: вікно чужого CRYP-режиму = нуль.

0а. [HW.31] Ворота «лише LTE» (Sim7070_Ensure_Lte_Only) — перед першою RF-командою:
   AT+CNMP? → «+CNMP: 38» → HELD, далі; інакше (чи ознаки ще нема) → AT+CNMP=38 →
   OK → AT+CNACT=1,1 (PDP уже в LTE) → REASSERTED; ERROR · +CME · тиша → return:
   слоти живі (FW.51), провал у health. Режим AUTO_SAVE (V1.03 §5.2.16).
   [HW.41] Попередня розмова впала → AT+CNACT=1,1 тут же (якщо ворота щойно самі
   не переактивували PDP), best-effort.

1. DNS (кеш порожній → резолв): AT+CDNSGIP="api.silkennet.com"
   ↳ URC +CDNSGIP: 1,"<host>","<ip>" (до АБО після OK — двигун ловить обидва
     порядки) → кеш coap_server_ip. Фейл → return: слоти живі (FW.51),
     наступний flush повторить і DNS.
   [FW.58] N=3 flush-провали ПІДРЯД (coap_consec_fail, reset на success) →
     Coap_Reresolve_Due → кеш інвалідується → примусовий re-resolve
     наступного flush: A-запис-фліп (zero-infra failover) підхоплюється
     БЕЗ ребута (host-дім test_fw58_reresolve_predicate; bench 00_07 FW.58).

2. PDU: Coap_Build_Put(CON PUT /telemetry/batch/<queen_uid>,
                       payload = legacy [IV:16][ct] АБО підписаний
                       [header][IV][ct][sig] — L1 QATT, wire-дім 03_05 §2.2)
   → coap_pdu_buf. MID = ++coap_mid (анти-дублі на CoAP-сервері).

3. Retry loop ≤ COAP_MAX_RETRIES, бюджет розмови COAP_CONV_BUDGET_MS (< IWDG):
   a. AT+CCOAPNEW="<ip>",5683,0      → +CCOAPNEW: <cid> → OK (cid — від модема)
   b. AT+CCOAPSEND=<cid>,<len_PDU>," + hex PDU чанками AT_HEX_CHUNK + "\r\n
   c. фінал OK = «модем прийняв» (ще НЕ доставка)
   d. URC +CCOAPNMI: <cid>,<n>,"<hex-PDU відповіді>" → Coap_Reply_Confirms:
      валідний заголовок + клас 2.xx + (для ACK) наш MID → send_success=1
   e. AT+CCOAPDEL=<cid> — best-effort прибирання сесії

4. [FW.51] Кеш звільняється ЛИШЕ при send_success (= підтверджена ДОСТАВКА,
   не транспортний OK). Усі спроби впали → слоти живі, наступний flush
   повторить; дедуплікація оновить ті самі DID найсвіжішим.
```

Час flush тепер домінується RTT мережі (NEW + NMI), а не UART: hex летить
чанками по `AT_HEX_CHUNK`, не побайтово. Старий «~25 секунд blocking hex TX»
закрито архітектурно.

**Важливо про URI-Path:** `/telemetry/batch/<queen_uid>` живе всередині
PDU (опції Uri-Path) — сервер знаходить шлюз за UID, а не за IP (вирішує
Starlink NAT та динамічні адреси).

**E2e-парність граматики (софтом, без заліза) — ✅ 2026-06-10.** Golden-вектори
`Coap_Build_Put` заморожені freeze-contract'ом обабіч дроту
(`firmware/test/test_at_engine.c` ↔ `spec/lib/coap_server_pdu_spec.rb`,
включно з пін-кейсом MID=0x00FF + 0xFF у payload), вердикт Брами винесено в
pure `CoapServerPdu` (`lib/coap_server_pdu.rb` — серверне дзеркало
`coap_pdu.h`), side-effect-оркестрацію — у `CoapGate.handle_datagram`
(`lib/coap_gate.rb`: enqueue ПЕРЕД поверненням reply → ACK **структурно**
не випереджає черги, enqueue-fail = no-reply = Королева ретраїть; демон
`lib/daemons/coap_listener` = лише UDP-клей), а повний
ланцюг PDU → парсер → `UnpackTelemetryWorker` → decrypt → unpack доведено
`spec/integration/coap_telemetry_intake_e2e_spec.rb`. Семантика відповіді
вирівняна з FW.51: **ACK 2.04 лише ПІСЛЯ прийняття батча в чергу**;
невідомий маршрут → 4.04, нечитабельний датаграм → RST (клас ≠ 2.xx →
Королева тримає кеш і повторює). Цей e2e зловив і закрив два продакшн-баги
Брами: (1) payload-маркер шукався глобальним `index("\xFF")` по всьому
датаграму включно з заголовком — кожен 256-й `coap_mid` давав фантомну
доставку (ACK 2.04 без батча → даремний cache-clear); (2) Sentinel-маршрут
(§7) падав на Sidekiq strict_args і його ковтав broad-rescue. Staging-smoke
(`coap_smoke.yml` → `bin/coap_smoke`: ті самі freeze-contract байти зондами
через реальний UDP/Ingress — RST/4.04-з-0xFF-MID-піном/2.04-після-enqueue,
loopback-довід `spec/lib/coap_smoke_spec.rb`) заведений post-deploy gate'ом
у обидва deploy-workflows (INF.6) і чекає лише задеплоєну Браму
(активація = host-Variable).

**Що лишається bench (HW-residual FW.3):**
- verbatim-звірка граматики SIM7070-ноти V1.03 + реальні таймінги модему;
- кремнієве підтвердження DMA-вуха: DMAMUX-роутинг USART1_RX, поведінка
  NDTR/TC на реальному кремнії, межовий байт рівно-повного кільця у гонці
  (логіка кільця host-доведена — `test_uart_rx_ring.c`; ✅ архітектурне
  закриття 2026-06-10: байтовий polling → circular-DMA кільце; bench-день
  скриптовано — `firmware/scripts/bench/06_uart_dma_ears.py`, RUNBOOK 5.4);
- поведінка при реальних LTE-M/Starlink мережевих помилках (скриптовані
  ERROR/+CME/тиша — покриті host).

### 4а. [FW.60] Downlink-poll після флашу (LwM2M Queue-Mode)

Push із Rails фізично не долітає (`gateway.ip_address` = CGNAT-egress,
`CASERVER` мережево мертвий — банер §4), тож **Королева сама питає свій
downlink** (⚖️ founder) одразу після `send_success`: модем теплий, IP резольвлений,
NAT-pinhole свіжий — єдине живе вікно. Реалізація — `Queen_Poll_Downlink`
(`main.c`, викликається з хвоста `Flush_Cache_To_Rails`; це **перший
call-site** усього inbound-тракту — доти `Handle_CoAP_Command` був мертвим
кодом):

```
1. Дренаж черги (≤ QUEEN_POLL_MAX_PER_FLUSH = 3 повідомлень):
   GET poll/<uid>?fw=<delivered_id>&cmd=<last_acked_cmd_token>&m=<mac>
     → Sim7070_Udp_Fetch (сирий CA*-тракт)
     → Coap_Reply_Extract_Payload (2.05 + наш MID) → конверт
     → Handle_CoAP_Command: 0 = time-only «черга порожня» → стоп;
       1 = контент (CMD / адресна команда 0x9A·0x9E / 0x9F OTA-hint) → наступний poll.
   ?fw= несе повністю зібраний contract-id (0 після ребуту) — Rails
   звіряє з gateways.pending_firmware_id = спостережене підтвердження
   доставки (Downlink::PendingQueueService, 04_02).
   ?cmd= [FW.63] несе токен ОСТАННЬОЇ успішно обробленої CMD (порожньо
   після ребуту, нове виконання АБО дедуп-збіг повтору — обидва означають
   «конверт доїхав») — Rails звіряє зі `.status_sent` і робить
   `mark_active!`→`acknowledge!`→Reset-план ЛИШЕ на цьому echo
   (`observe_delivered_command!`); build-час (видача CMD у кроці 1 вище)
   робить лише `dispatch!`.
   ?m= [SEC.38, ⚖️ founder 2026-09-27] — MAC запиту, ОСТАННЬОЮ опцією, і на
   poll, і на ota/<uid>: перші 16 байт HMAC-SHA256(K_mac, canonical) у hex,
   K_mac = HMAC-SHA256(KEYC, "silken-poll-mac-v1"), canonical =
   "silken-pull-v1\n" route "\n" uid "\n" MID ("\n" q)* — опції query в
   порядку надсилання без m= (queen/pull_mac.h ⟷ Downlink::PullMac, спільний
   golden-вектор). KEYC у RAM лежить словами `-w32`, тож ключ для HMAC —
   big-endian байти кожного слова. Без чинного MAC Rails відповідає 4.01 ДО
   будь-якої зміни стану; Queen, що не може його порахувати, запиту не шле.
   ⚠️ Свіжості MAC не дає: перехоплений справжній запит можна повторити —
   повтор нічого не підробляє, лише перевидає голову черги.
   Відповідь 2.05 несе власний тег [FW.60, ⚖️ 2026-10-09]: [IV:16][CBC][tag:16],
   tag = перші 16 Б HMAC-SHA256(K_rmac, "silken-reply-v1\n" m_hex "\n" ‖ конверт),
   K_rmac = HMAC-SHA256(KEYC, "silken-reply-mac-v1"), m_hex — тег ЦЬОГО запиту
   (Pull_Mac_Reply_Verify ⟷ Downlink::PullMac.seal_reply, спільний golden).
   Королева звіряє його ДО розшифрування; чужий тег = транспортний збій
   (лічильник g_poll_reply_tag_rejects, SWD). Свіжість — nonce n= (8 Б
   HRNG) у кожному запиті, перед m=: m= не повторюється ніколи, тож
   відповідь на повторений запит не підходить жодному новому; початковий
   MID теж із HRNG. KEYC із нулів — запит не йде.

2. OTA-фетч за hint'ом [0x9F][fw_id:4 BE][total:2 BE]
   (≤ QUEEN_OTA_FETCH_PER_FLUSH = 4 чанків/флаш — IWDG-бюджет):
   GET ota/<uid>?v=<fw_id>&ch=<n> → повний конверт із чанком (≤560 Б,
   влазить лише в CARECV-ногу) → Handle_CoAP_Command → 0x99/0x9B гілки
   (bitmap/трейлер незмінні). Курсор Queen-driven — Rails
   прогресу не веде; ребут → fw=0 → повторний hint → безпечний
   idempotent re-fetch (bitmap дедуплікує). Збирання повне (тіло й увесь
   трейлер) САМЕ цієї кампанії → delivered_id = fw_id, hint згасне
   (Ota_Campaign_Delivered: світанок прив'язує збирання до fw hint'а).
   Hint зупиняє дренаж poll'а: нижче за нього в драбині лише пороги 0x9A,
   яких він і так затінює до fw=.
   Кожна розмова бере наступний ВІДСУТНІЙ пакет від курсора, по колу
   (Ota_Fetch_Next_Missing, ota_window.h): відкинутий (транзитна CRC тіла)
   перезапитується, зібране вдруге не тягнеться, а пакет тіла
   після завершення — дубль (світанок нової кампанії робить лише зміна fw
   у хінті); 4.xx від chunk-server'а гасить pending — живу кампанію
   наступний hint увімкне знову.
```

> ⚖️ **Курсор OTA-фетчу на відкинутому пакеті — ДЕЛЕГОВАНО 2026-10-09** (мандат founder-а на §03a/§03b — «делегована ратифікація ще відкритих присудів по рекомендації»; нога [`00_07` FW.60](00_07_Action_Plan_Tracker)). **Дефект:** `(void)Handle_CoAP_Command(...)` → `g_ota_fetch_next_ch++` — курсор рухався й на відкинутому пакеті (`Handle_CoAP_Command` повертає 1 для будь-якого inner-контенту, прийнятого чи ні), завершення вимагає всіх чанків (`ota_is_active`), а hint того самого `fw` курсора не скидає: один відкинутий пакет зупиняв кампанію до ребуту Королеви, і `fw=` не приходив ніколи. Обіцянки гочі `firmware` #1c («does not advance until the chunk is handled») і картки `Downlink::PendingQueueService` у [`04_02`](04_02_Business_Logic_and_Services) («тягне відсутні чанки сама») були хибні. Нога подала два виходи: (а) лишити курсор і звузити обіцянки до «до успішного отримання», визнавши кампанію, що стоїть до ребуту; (б) курсор чекає результату обробки — тоді постійно битий пакет перезапитується щофлашу, і потрібна межа повторів. **Присуд — третій вихід, родич (б): курсор не довіряє результату, а звіряється зі станом збирання** (⊕ першу форму — «перемотка в кінці без живого вікна» — того ж дня спростував адверсар; чинна форма — абзац ⊕ нижче) — дійшовши кінця без живого вікна, повертається до першого пакета, якого збирання не має (тіло — бітмап CoAP-чанків, за повного тіла — маска трейлера; `Ota_Fetch_Rewind`, `firmware/queen/ota_window.h`), а 4.xx від chunk-server'а гасить `pending` (`Coap_Reply_Client_Error`, `coap_pdu.h`). **Підстава:** Королева вже знає, чого їй бракує, тож окремого лічильника повторів не треба; межу повторів дає наявний сторож ARCH.59 (`OTA_STUCK_MARGIN` 24 год): знята кампанія відповідає 4.04 (`firmware_id ≠ pending_firmware_id`), і `pending` гасне — без цього вона коштувала б розмову щофлашу довіку; транзієнтний 4.04 (пакунки ще не прогріто) теж безпечний, бо живу кампанію наступний hint увімкне знову. **Ціна:** отруєний пакет (детермінований збій пакування на боці Rails) коштує до `QUEEN_OTA_FETCH_PER_FLUSH` = 4 LTE-розмов на флаш, доки сторож не зніме кампанію (≤ 24 флаші — ≤ 96 розмов; ⊕ лише за таймером, нижче), замість мовчазного стояння до ребуту. **Найслабша ланка:** Королева не розрізняє «кампанію знято» і «пакунки не прогріто» — обидва 4.04 гасять `pending`, тож за довго холодного сховища кампанія чекає повернення hint'а; ціна — затримка, не втрата. Host-піни — `Ota_Fetch_Rewind` і `Coap_Reply_Client_Error` на справжніх функціях; клей `Queen_Poll_Downlink` — ARM compile-lane, без виконання.
> ⊕ **Адверсар застосування (2026-10-09) — перша форма ліку на реальних розмірах кампаній не тримала; переписано тим самим днем.** Стеля Солдата FW.67 дає тіло ≤ 2 CoAP-пакети (кампанія ≤ 9 пакетів), і на таких розмірах «перемотка в кінці без живого вікна» ламалась трьома способами: (1) курсор ішов лінійно й після перемотки скачував пакет тіла, який Королева вже мала, а 0x99-гілка, що робила світанок на «порожньому збиранні», після завершення тіла (мапу й лічильник обнулено) читала той дубль як нову кампанію й стирала зібране — петля до сторожа, ≈ 72 розмови й стирання сторінки Flash на добу; (2) доставку оголошували за `ota_is_active`, тобто за станом ПРОПОВІДІ, а не збирання: вікно гасне, щойно тіло відлунало, тож після перемотки доставку не оголошено б ніколи (ліс має прошивку, а сторож пише FAILED і оператор перевидає OTA всьому лісу); (3) живе вікно з неповним трейлером оголошувало б успіх без печатки. **Виправлено:** кожна розмова бере наступний ВІДСУТНІЙ пакет від курсора, по колу (`Ota_Fetch_Next_Missing`), — зібраного вдруге не тягне; пакет тіла після завершення — дубль (`Ota_Body_Is_Duplicate`), а світанок нової кампанії — лише зміна fw у хінті (кожна кампанія приходить після свого hint'а); доставка = ЗІБРАНО: тіло й увесь трейлер. **Числа ціни:** «≤ 24 флаші» — лише за таймером (`FLUSH_INTERVAL_MS` = 1 год); флаш за наповненням кешу CIFO (≥ 45 записів) у кластері від 45 дерев частіший, тож розмов за добу більше; 24 год сторожа рахуються від старту кампанії, а не від появи діри; «конверт понад стелю» для OTA-пакета неможливий (≤ 544 Б ≤ 560), тож реальний відкинутий пакет — транзитна CRC. **Найслабша ланка, якої подання не бачило:** 4.xx гасить pending, а повертає його лише hint; у grace ратчета ([`00_07` FW.17](00_07_Action_Plan_Tracker), гейтовано) poll на кожному запиті віддає кадр `0x9E` вище за hint, тож транзієнтний 4.04 посеред кампанії паркує OTA до кінця grace (≤ 24 год сторожа) — стане живим із фліпом FW.17. **Межа покриття:** host-піни — `Ota_Fetch_Next_Missing` · `Ota_Body_Is_Duplicate` (мутаційно перевірено) · `Coap_Reply_Client_Error`; клей `Queen_Poll_Downlink` — ARM compile-lane, без виконання.
> ⊕ **Третій раунд адверсара (2026-10-09) — досяжного хибного виходу не знайдено; знайдено, що ВСЯ гарантія лягла на один пускач без піна.** Зі зняттям світанку з 0x99 і липким «тіло зібране» предикат доставки став читати збирання, не знаючи, ЧИЄ воно: мутація «прибрати світанок із гілки hint'а» лишала б зібрану кампанію A, і hint B оголосив би B доставленою без жодного фетчу (Rails гасить hint, ліс B не дістає) — а сюїта мутацію пропускала зеленою, бо тест FW.53 після правки перевіряв тестовий хелпер, а не прошивку. **Виправлено:** світанок прив'язує збирання до `fw` hint'а, а доставку оголошують лише для кампанії, якій воно належить (`Ota_Hint_Starts_Campaign` · `Ota_Campaign_Delivered`, `ota_window.h`) — пропущений світанок тепер мовчить, і сторож ARCH.59 знімає кампанію чесним FAILED; світанок гасить і застаре `fw=` попередньої кампанії (її байтів у RAM уже немає). Мутаційно перевірено чотири піни: без звірки `fw`, без повної маски печатки, курсор від нуля замість від курсора, світанок на повторі того ж `fw` — кожна червона. **Битий блок печатки діри НЕ лишає**, і рядок «битий блок перезапитується» знято: Королева приймає `0x9B` за маркером і номером, цілісності блоку не звіряючи, тож спотворений блок лічиться прийнятим, курсор його не перетягне, а доставку оголошено; відкидає його Солдат печаткою — fail-closed (непідписане не пройде, пройти не пройде й кампанія), а лік — повторна OTA. Ймовірність такого блоку обмежує транспорт (LTE-канал і контрольна сума UDP), не наш код. **Тим самим ходом — енергія, якої подання не рахувало:** доки кампанія жива, кожен флаш тричі перечитував той самий hint (`Handle_CoAP_Command` повертав 1, і poll дренував далі до стелі `QUEEN_POLL_MAX_PER_FLUSH`); тепер hint зупиняє дренаж — нижче за нього в драбині лише пороги `0x9A`, яких він і так затінює до `fw=`. **Свідомо лишено:** прогрес-бар Rails іде НАЗАД, коли Королева перетягує діру (9/9 → 1/9) — бар показує пакет, що летить зараз, а монотонний максимум потребував би стану на сервері.

Кожна відповідь — той самий конверт `[IV:16][AES-256-CBC KEYC]` з
`[0x9C][ts:4]` усередині (`CoapEncryption`) → **кожен poll = RTC-sync
Королеви**, навіть порожній (time-only, 32 Б). Дубль-MID (мережеве дублювання
датаграми) Rails віддає байт-ідентично (MID-кеш `CoapGate`) — ⚠️ **не** плутати
з CON-ретрансмітом: його в poll-тракті немає (врізка «[FW.63] Виправлено» в [`03_02 §6`](03_02_Queen_Gateway_Firmware)).

**[SEC.38] Чому MAC над самим запитом (⚖️ founder 2026-09-27, за рекомендацією; реалізовано того ж дня).** `CoapGate.handle_queen_pull` шукав шлюз за uid з Uri-Path і вірив query будь-якого відправника: підроблений `fw=` закривав OTA-кампанію шлюзу, що її не отримав, а сам poll рухав стан наказів — шифрований конверт ВІДПОВІДІ цього не лікував. Відкинуто: **(б)** «не вірити `fw=` без підписаного uplink» — лікує одне поле, тоді як poll рухає й накази; **(в)** лише моніторинг — підробка лишалась би дієвою. **Ціна:** зміна wire-формату poll-запиту — Королева на старій прошивці більше не поллить. **Найслабша ланка:** байтовий вигляд KEYC на кремнії (слова `-w32` → big-endian) host-тест моделює, а не міряє; підтверджує лише живий round-trip на стенді (сеанс coap, [`00_07` SEC.38](00_07_Action_Plan_Tracker)).

**[FW.60] MAC над poll-ВІДПОВІДДЮ (⚖️ подано й ДЕЛЕГОВАНО 2026-10-09 — мандат founder-а на §03a/§03b, «делегована ратифікація ще відкритих присудів по рекомендації»; реалізовано того ж дня).** **Дефект:** конверт відповіді `[IV:16][AES-256-CBC KEYC]` ховав, ЩО каже Rails, але не доводив, що казав Rails: зміна IV переписує перший блок відкритого тексту — `[0x9C][ts:4]` і перші 11 Б inner, куди цілком лягає OTA-hint `[0x9F][fw:4][total:2]`, — а будь-яку стару відповідь можна повторити; `Apply_Server_Time` бере будь-який час, а Солдат, почувши маяк, стережеться лише нуля. **Ціну зміряно** (атакер на шляху Королева ⟷ сервер або з отруєним DNS імені CoAP-сервера, без KEYC): гроші ВГОРУ недосяжні (⊕ ХИБНО — спростовано адверсаром того ж дня, абзац ⊕ нижче) — стрибок часу назад чи понад тиждень guard'и `wall_time.h` віддають сентинелом «не виміряно» (бали 0), а відро балів [`E.64`](00_07_Action_Plan_Tracker) рахується серверним годинником (`credit_telemetry!` без `at:`); підроблений hint лише стирає кампанію (фетч під MAC запиту отримує 4.04), а непідписаного Солдат не прошиє — печатка Ed25519 [`FW.23`](00_07_Action_Plan_Tracker) звіряється до запису; `CMD:` сьогодні латентний — виконавця на Королеві немає ([`UI.14`](00_07_Action_Plan_Tracker)), а свіжий токен без відомого відкритого тексту не складеш; `0x9E` і печатка наскрізні. Тобто ціна — DoS на найдефіцитніше: кластер без балів і час, що смикає ресинки Солдатів, які платять ефіром з EBFC; і латентна поверхня, яка оживе з першим виконавцем актуатора. **Присуд — (а) encrypt-then-MAC, симетрично до SEC.38:** тег 16 Б хвостом над конвертом, підключ `K_rmac = HMAC-SHA256(KEYC, "silken-reply-mac-v1")`, у MAC — тег САМЕ ЦЬОГО запиту, тож відповідь чинна лише для свого питання; Королева звіряє тег до розшифрування (`Pull_Mac_Reply_Verify`), Rails ставить його на межі транспорту, поруч із перевіркою запиту (`CoapGate` → `Downlink::PullMac.seal_reply`). Свіжість між ребутами дає початковий MID із HRNG (RFC 7252 §4.4): з нуля запит після ребуту повторювався б побайтово, а з ним — і чинний тег старої відповіді (⊕ лише ймовірнісно — нижче; свіжість дає nonce). **Відкинуто:** **(б)** AEAD (AES-GCM/CCM) — та сама мета ціною злому формату конверта в обидва боки й атомарного перемикання кожної Королеви; **(в)** прийняти й задокументувати — чесно лише доти, доки поверхня `CMD:` латентна, тобто відкладення, а не закриття. **Ціна:** +16 Б на кожну 2.05 — найбільша відповідь (OTA-чанк) стає 560 + 16 Б (⊕ уточнено нижче: OTA-чанк — 544, а 560 — стеля Rails), `poll_reply` (600) тримає її під `_Static_assert`; wire-зміна обабіч — Королева на старій прошивці відповідей уже не прийме, а Rails на старому коді не поставить тегу (вузлів у лісі нуль). **Найслабша ланка:** 4.xx тегу не несуть — підроблений 4.04 у фетчі гасить `pending` до наступного hint'а (затримка флашу, не підробка); випадковий MID лишає повтор в одному житті Королеви — потрібен той самий MID із тим самим запитом, тобто цикл 65 536 розмов; байтовий вигляд KEYC на кремнії — той самий, що в SEC.38, і підтверджує його той самий живий round-trip. **Провенанс, сказаний чесно:** вимір, рекомендацію й делеговану ратифікацію зроблено однією сесією; вимір перевірено незалежним прочитанням коду (агент) і звірено вручну, кожен засновок — рядком коду (⊕ незалежність не втрималась: діру, абзац ⊕ нижче, пропустили і агент, і я). **Межа покриття:** golden-вектор тегу спільний (`firmware/test/test_pull_mac.c` ⟷ `spec/services/downlink/pull_mac_spec.rb`), відмова на чужому тегу й чужому запиті — host-пін, мутаційно перевірено обабіч; наскрізь із справжньою криптографією — `spec/integration/ota_deploy_tract_spec.rb`; клей `Queen_Poll_Downlink` — ARM compile-lane, без виконання.

> ⊕ **Адверсар застосування (2026-10-09) — сам MAC зроблено правильно наскрізь, а вимір ціни мав діру на ГРОШОВОМУ шляху: «гроші ВГОРУ недосяжні» — неправда.** Guard'и `wall_time.h` ловлять лише три випадки (немає попереднього · час назад · стрибок понад тиждень), а малий зсув годинника назад — менший за проміжок між пробудженнями — пропускають: Солдат міряє вкорочену, але додатну `delta_t`, і `m(delta_t)` дає їй максимум балів (`DELTA_T_FAST_S` = 600 с → m = 1.0; ⊕ точніше — `m()` бере прогріту EMA `delta_t` з α = 0.2, тож максимум дає повтор щопроміжку, [`03_05 §2.4`](03_05_Hardware_Symmetric_Crypto_and_Security)). Відро [`E.64`](00_07_Action_Plan_Tracker) — стеля, а не перевірка: чесна робоча точка лежить у 3.65× під нею (нота `Wallet`). Підроблена poll-відповідь давала цей важіль через годинник Королеви — MAC його закриває; але той самий зсув дає й **повтор маяка часу `0x9C` по LoRa без жодного ключа** ([`03_05 §2.4`](03_05_Hardware_Symmetric_Crypto_and_Security): маяк повторюваний, Солдат бере будь-який `ts ≠ 0`), і цей шлях відкритий сьогодні в обох ерах (⊕ закрито того ж дня — крок годинника за маяком зсуває й базу `delta_t`, абзац 🔒 у §5а). Він — не наслідок цього присуду й не його застосування, тож поданий founder-у окремо, з рекомендацією: [`00_07` SEC.42](00_07_Action_Plan_Tracker) (⊕ ратифіковано founder 2026-10-09 — обидва ліки, врізка [SEC.42] у [`03_05 §2.4`](03_05_Hardware_Symmetric_Crypto_and_Security)). Вибір (а) від цього не слабшає, а сильнішає: підробка відповіді важила й гроші, не лише DoS.

> ⊕ **Решта знахідок того ж адверсара — виправлено наступним ходом.** (1) **Свіжість від MID — ймовірнісна, не свіжість:** `m=` залежить лише від MID і запиту, а запит після ребуту (`fw=0`) і в усталеному стані сталий; Rails же на повторений старий запит видає СВІЖУ запечатану відповідь, тож атакер міг наперед зібрати відповіді на ті `m=`, що повторяться. Лік — nonce `n=` (8 Б HRNG; при відмові HRNG — деривація SEC.12 під KEYC) останньою опцією перед `m=`: канонічний рядок MAC бере всі опції, крім `m=`, тож nonce покриває і запит, і — через `m=` — тег відповіді, а Rails про нього не знає й міняти його не довелось (golden-вектор із `n=` спільний, `test_pull_mac.c` ⟷ `pull_mac_spec.rb`). (2) **Нульовий KEYC** (Королева без провіжну) — ключ публічний, тож `Pull_Mac_Query` такого запиту не складає. (3) **Відмова тегу мовчазна** — тепер її лічить `g_poll_reply_tag_rejects` (SWD, насичується), інакше її видно лише з відсутньої луни `cmd=`/`fw=`. (4) **Тегу не несуть не лише 4.xx:** статусні відповіді без тіла — 2.04 на PUT батча й 2.xx на PUT подій теж; підроблена 2.04 змушує Королеву звільнити CIFO, тобто батч губиться (сильніше за дроп), а для CON/NON-відповідей `Coap_Reply_Confirms` MID не звіряє — це спільна з аплінком функція, і як модем подає відповідь, покаже стенд (FW.56), тож тут її не чіпали. (5) **Розміри:** OTA-чанк — 544 Б, 560 — стеля `MAX_ENVELOPE_BYTES`; найбільша відповідь — 560 + 16 + 5 = 581 Б із 600. (6) Push-воркери `TimeSyncDownlinkWorker` і `KeyRotationDownlinkWorker` досі шлють Королеві конверт БЕЗ тегу в нікуди — Королева не слухає; знести — з рештою superseded push-воркерів ([`00_07` FW.60](00_07_Action_Plan_Tracker)).

**[FW.63] Чому `?cmd=`-echo, а не альтернативи (закрито 2026-09-09, ⚖️ ратифіковано
founder 2026-09-10).** Доти CMD-lifecycle просувався до `acknowledge!` при **побудові**
відповіді (build-time, до відправки байтів) — загублена 2.05 губила команду назавжди,
а слід («executed_at», Reset→`confirmed`) форензично брехав, що вона виконана. Мисленно
розглядались три виходи: **(а) `?cmd=`-echo** (обрано) — пряме дзеркало вже наявного
`?fw=`-патерну; Rails тримає команду в `.pending`, доки Королева не підтвердить її ЖИВИМ
echo на пізнішому poll'і; `Cmd_Dedup_Check` на Королеві вже унеможливлює подвійне
виконання при повторній видачі, тож re-serve безпечний. **(б) re-delivery без echo** —
простіше, але Rails ніколи не отримує позитивного підтвердження: команда мусила б
re-serve'итись до TTL НАСЛІПО, і UI показував би timeout навіть для вже виконаних
Королевою команд. **(в) свідомо лишити open-loop** із названою стелею — відкинуто: P1
safety-critical (сирена/клапан), ціна залишити як є перевищує ціну фіксу. Bench-residual: жива
poll-розмова обома маршрутами + verbatim `+CADATAIND`/`CARECV`-поведінка —
[`00_07` FW.60](00_07_Action_Plan_Tracker) / [`00_07` FW.63](00_07_Action_Plan_Tracker).

> ⚖️ **Каденс флашу під аварійний наказ — гілка (A), 10 хв для флоту; ратифіковано founder 2026-09-28 (за рекомендацією, [`00_07` FW.64](00_07_Action_Plan_Tracker)).** Poll живе лише після флашу, а таймерний флаш — компайл-тайм `FLUSH_INTERVAL_MS` = 1 год (другий тригер, наповнення кешу, від аварії не залежить), тож наказ із вікном релевантності коротшим за годину — сирена, 15 хв — за таймером не доїжджає (⚠️ анотовано 2026-10-02: «не доїжджає» несе силу, яку ⚖️ founder 2026-09-27 переглянув ще до цієї врізки, — не гарантовано, а не неможливо; чинна форма — [`04_02 §7`](04_02_Business_Logic_and_Services)). Присуд: `FLUSH_INTERVAL_MS` = `600 000` ПАРОЮ з `Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S` = 660 с (парність тримає `pending_queue_service_spec`; вікно `Gateway#online?` рахується від тієї ж константи й рухається само) — перемикається разом з актуаторною прошивкою ([`00_07` ARCH.75](00_07_Action_Plan_Tracker)), не раніше: доти скорочений каденс платив би енергією за можливість, якої немає. **Підстава:** одна константа з виміряною ціною; гілка (E) — `T3324` порядку каденсу + eDRX + MT-SMS — стоїть на трьох невиміряних входах: чи дає IoT-SIM MT-SMS/eDRX (лист [`00_07` HW.41](00_07_Action_Plan_Tracker)), idle-струм модема на eDRX замість мікроамперів PSM (даташит не звірено) і SMS-шлюз у Rails (його немає). (A) не зачиняє (E): та лишається апгрейдом латентності (≈ 20 с замість ≤ 11 хв), якщо ці входи виявляться дешевими. **Ціна:** модель `ruby tools/firmware/queen_energy_budget.rb tx_sessions_per_day=144` — флаш-сесії 0.12 → 0.70 Вт·год/добу, зимовий баланс Phase 1/2.5 +7.61 → +7.07 Вт·год/добу (≈ 7 % профіциту; з найощадливішою BMS, якої модель ще не має, ≈ 11–12 %), deploy-гейт `--assert` тримається (модель з `dcdc_eff` 0.88, 2026-10-01: 0.13 → 0.76 і +7.48 → +6.89 — ≈ 8 % профіциту, з найощадливішою BMS ≈ 13 %; гейт тримається); трафік ×6; коротше вікно CIFO-дедупу. **Найслабша ланка:** запас 900 − 660 − 190 = 50 с на poll → LoRa-реле → актуатор не виміряно (актуаторної прошивки немає); зимовий профіцит — модель, не вимір. ⚠️ Переміряно 2026-09-28: вікно `Gateway#online?` справді рухається само, але його люфт 20 % на 660 с (132 с) тривалості флашу (до ≈ 190 с) не вміщує — 660 × 1.2 = 792 < 850, тож базу вікна доповнено адитивним членом (⚖️ делеговано 2026-09-28, врізка `Gateway` у [`04_01 §3`](04_01_Data_Models_and_Entities)).

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
  HAL_CRYP_Encrypt(ECB) → HAL_Delay(Lora_Phy_Send(encrypted_ota, 16, …))
                  ← кадр відлітає цілком: 16 Б @ SF9 = 165 мс ефіру + запас
                    (03_05 §2.1, врізка під airtime-таблицею; FW.61)

current_ota_chunk_idx++
if (current_ota_chunk_idx >= total_chunks):     ← тіло відлунало
  if (усі 7 трейлер-блоків 0x9B зібрані):       ← [FW.23] печатка (6) + версія (1)
    seal_broadcast_phase = 1                     ← фаза печатки: 7 блоків 0x9B як є,
                                                    без жодного зміненого байта; після
                                                    сьомого — вікно закривається
  else:
    current_ota_chunk_idx = 0; ota_is_active = 0 ← без печатки Солдат не відрізнить
                                                    істинне слово від спокусника —
                                                    вікно закривається одразу
```

Солдат пише в Flash лише після обох брам — Ed25519-печатка кластера і версія > high-water (SEC.20) — [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning).

> 🔴 **Рефлекс ПЕЙСИТЬСЯ робочим циклом ([`00_07`](00_07_Action_Plan_Tracker) FW.61):** умови НКЕК для SRD 868 дають < 1 % — ≤ 36 с передавання на годину ([`certification_roadmap`](protocols/legal/certification_roadmap.md) §2), а серія 8 КБ — це ≈ 123 с ефіру. Тож кожен P2P-кадр Королеви (маяк · CMD · OTA-чанк · печатка · re-request) питає лімітер `firmware/queen/tx_duty.h` ДО `Send` і списує свій ефір після, а епізод LoRaWAN-детуру — стелею свого ефіру, бо смуга в них одна ([`02_05 §6.1`](02_05_Queen_Hardware_and_Starlink), ARCH.34): журнал з 13 п'ятихвилинних кошиків тримає стелю для будь-якого ковзного годинного вікна, маяк часу має резерв 3,6 с, решту ділять OTA й CMD. Коли ефір вичерпано, чанк просто не стріляє — курсор не рухається, і той самий чанк піде на наступному uplink'у; re-request обривається, і решту пропусків Солдат перепросить наступним зойком. Ціна: серія 8 КБ при безперервному попиті закінчується не раніше ніж за ~3 год (чотири порції по 32,4 с); реальний темп задають uplink'и Солдатів. Стелі (ребут обнуляє журнал · детур списується стелею ефіру епізоду, а не виміряним ефіром, тож епізод, що здався до uplink'у, списує й ефір кадру, якого не було · годинне вікно звірено з текстом EN 300 220-1 V3.1.1 2026-10-01, ковзне — суворіше, не мʼякше — [`certification_roadmap`](protocols/legal/certification_roadmap.md) §2.3) — шапка `tx_duty.h`.

**Математика LoRa чанків:**
- Корисне навантаження: 11 байт (16 − 5 байт заголовка)
- Для 8192 байт bytecode: `(8192 + 10) / 11 = 745` LoRa-чанків
- Кожен Солдат при кожному своєму TX отримує **один** послідовний чанк
- Після 745-го чанка йде фаза печатки (7 трейлер-блоків 0x9B), і лише тоді вікно закривається; без зібраного трейлера — одразу

### OTA Assembly (CoAP Downlink від Rails → RAM)

> ✅ **[FW.60] Inbound-тракт WIRED (2026-07-12):** `Handle_CoAP_Command` живе — перший call-site = poll-цикл `Queen_Poll_Downlink` (§4а; push із Rails фізично не долітав — CGNAT). OTA-чанки прибувають як відповіді Queen-driven fetch'а `GET ota/<uid>?v=&ch=` (сира CARECV-нога — конверт ≤560 Б у NMI-лінію не влазить), кампанію анонсує hint `[0x9F]` у poll-відповіді. Стеля збірки 16×512 = 8 КБ (Guard 3) тепер **enforce'иться Rails-боком ДО burn** (`Ota::DeploymentDispatcherService` oversized-гейт — [`04_02`](04_02_Business_Logic_and_Services)). Bench-residual (жива розмова + verbatim модем-поведінка) — [`00_07` FW.60](00_07_Action_Plan_Tracker).

**Два типи OTA-чанків — важливо не плутати:**
| Тип | Джерело | Розмір payload | Макс чанків | Ліміт |
|-----|---------|----------------|-------------|-------|
| **CoAP downlink** (Rails → Queen) | `Handle_CoAP_Command` ← Queen-driven fetch §4а (CARECV-нога, [FW.60]) | ≤512 байт | 16 | `OTA_MAX_CHUNKS` (bitmap; Rails-дзеркало = oversized-гейт dispatcher'а, поруч зі стелею Солдата — FW.67) |
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

─── OTA Chunk Processing — [FIX AUDIT-2026-06-06] явний len + CRC16 ──────
Wire (після зняття envelope): [0x99][idx:2 BE][total:2 BE][len:2 BE][bytecode:len][crc16:2 BE]
// Стара схема ВГАДУВАЛА довжину з CBC zero-padding (формула aligned−16−7) і
// при паддінгу 0..15 систематично обрізала 1..16 байт КОЖНОГО чанка
// (повний 512B → 500B). CRC16 від бекенду не перевірявся. Збірка була
// зламана by construction — явний len + CRC16 закривають клас помилок.

Guard 1: if (aligned < OTA_COAP_MIN_FRAME=10) → return  [header 7 + 1 байт + crc 2]

Витягуємо:
  chunk_index  = (cmd_decrypt_buf[1] << 8) | cmd_decrypt_buf[2]  (big-endian)
  total_chunks = (cmd_decrypt_buf[3] << 8) | cmd_decrypt_buf[4]  (big-endian)
  payload_len  = (cmd_decrypt_buf[5] << 8) | cmd_decrypt_buf[6]  (big-endian)
  ota_total_expected_chunks = total_chunks  ← оновлюється з кожним чанком

Guard 2: if (total_chunks == 0) → return  [invalid header]
Guard 3: if (chunk_index >= OTA_MAX_CHUNKS=16) → return  [bitmap overflow]
Guard 4: if (payload_len == 0 OR payload_len > MAX_OTA_CHUNK_PAYLOAD=512) → return
Guard 5: if (OTA_COAP_HEADER_SIZE + payload_len + OTA_CRC_SIZE > aligned) → return
         [len бреше за межі дешифрованого]

─── CRC16-CCITT verification (нове — біт-фліп LTE/Starlink вмирає тут) ──
  expected_crc = Silken_Crc16_Ccitt(frame, 7 + payload_len)   ← common/silken_crc.h
  received_crc = (frame[7+len] << 8) | frame[7+len+1]          ← big-endian хвіст
  if (expected_crc != received_crc) → return
  // Дзеркало OtaPackagerService.crc16_ccitt — байт-у-байт

  offset = (uint32_t)chunk_index * MAX_OTA_CHUNK_PAYLOAD  (0, 512, 1024, ...)

Guard 6: if (offset + payload_len > sizeof(pending_ota_bytecode)=8192) → return

─── Нова кампанія — НЕ тут ───────────────────────────────────────────────
  Світанок (pending_ota_size = 0 та решта стану: менша нова прошивка не
  успадковує хвостів старої, AUDIT-2026-06-06) робить лише зміна fw у
  хінті 0x9F — Queen_Ota_Campaign_Dawn(fw) [FW.60]. Порожнє збирання
  пускачем бути не може: після завершення тіла воно теж порожнє.

─── Dedup: бітмап І завершене тіло ───────────────────────────────────────
  chunk_bit = 1U << chunk_index
  if Ota_Body_Is_Duplicate(pending_ota_size, bitmap, received, chunk_bit)
    → return  (дублікат — і повторний фетч після завершення тіла)
  ota_chunk_bitmap |= chunk_bit               (маркуємо як отриманий)

─── Зберігаємо в RAM-буфер ───────────────────────────────────────────────
  memcpy(pending_ota_bytecode + offset, &cmd_decrypt_buf[OTA_COAP_HEADER_SIZE=7], payload_len)
  ota_chunks_received++

  // Відстежуємо реальний розмір зібраного байткоду:
  if (offset + payload_len > pending_ota_size):
    pending_ota_size = offset + payload_len

─── Перевірка завершення ──────────────────────────────────────────────────
  if (ota_chunks_received >= ota_total_expected_chunks):
    ota_chunks_received = 0           ← нуль лічильника й бітмапа при pending_ota_size > 0
    ota_total_expected_chunks = 0       = мітка «тіло зібране» (Ota_Body_Complete), не
    ota_chunk_bitmap = 0                  початок нової кампанії
    current_ota_chunk_idx = 0        ← починаємо LoRa broadcast з чанка 0
    ota_is_active = 1                 ← 🚀 запускаємо LoRa broadcast!
    // УВАГА: pending_ota_size НЕ скидається (залишається для broadcast)
    // ota_is_active скидається до 0 після одного повного циклу бродкасту (виправлено)
```

**Константи OTA (повна таблиця):**
| Константа | Значення | Розрахунок | Опис |
|-----------|----------|------------|------|
| `OTA_MARKER` | `0x99` | — | Маркер OTA-пакета (перший байт) |
| `OTA_HEADER_SIZE` | 5 | `1+2+2` | **LoRa-шар** (Queen→Soldier): маркер + index:2 + total:2 |
| `OTA_COAP_HEADER_SIZE` | 7 | `1+2+2+2` | **CoAP-шар** (Rails→Queen): + явний len:2 BE [AUDIT-2026-06-06] |
| `OTA_CRC_SIZE` | 2 | — | CRC16-CCITT в кінці CoAP-чанка (тепер перевіряється) |
| `OTA_COAP_MIN_FRAME` | 10 | `7+1+2` | Мінімальний валідний CoAP-кадр |
| `AES_BLOCK_SIZE` | 16 | — | Розмір AES-блоку |
| `MAX_OTA_CHUNK_PAYLOAD` | 512 | — | Макс. байткод в одному CoAP-чанку |
| `OTA_MAX_CHUNKS` | 16 | `8192/512` | Макс. CoAP-чанків (bitmap обмеження) |
| `pending_ota_bytecode` | 8192 B | — | RAM-буфер збірки прошивки (wire-потік: bytecode+pad+CRC32) |

---

### 5.1 [FW.27] OTA Broadcast Reliability — ACK-Aggregation + Magic Re-Request (DESIGN)

> **Статус:** 🤖 Дизайн завершено. Повна імплементація залежить від [ARCH.26 TDMA Sync Windows](00_07_Action_Plan_Tracker) — без скоординованого RX-вікна на Soldier'ах ACK-aggregation марна. Поточний broadcast — fire-and-forget, що документується тут чесно.

#### 5.1.1 Проблема, яку вирішує

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

#### 5.1.2 Дизайн A: ACK-Aggregation (Queen-side coordination)

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

#### 5.1.3 Дизайн B: Magic Re-Request (Soldier-initiated vector OTA) — ✅ Реалізовано (2026-05-02)

**Статус:** ✅ Реалізовано (2026-05-02); перезапит трейлера печатки й віддача відповіді боргом — 2026-10-09 ([`00_07` FW.68](00_07_Action_Plan_Tracker)). Розкладка зойку, сентинел печатки, будівники й рішення про тишу — `firmware/common/ota_rerequest_wire.h` (спільний Солдату, Королеві й host-тестам); борг Королеви — `firmware/queen/ota_rerequest_table.h`. Тиша = `OTA_REREQUEST_SILENT_WAKEUPS` = 10 **тихих пробуджень з відкритим вухом** ≈ 5 хв wall при циклі 26-32 с (tick заморожений у STOP2, тож лічимо пробудження; лічиться тиша лише тоді, коли вухо справді слухало). Host-піни — `firmware/test/test_soldier_logic.c` + `test_queen_logic.c` на справжніх функціях, не на копіях. ✅ **Queen-side SHA-256 cross-check реалізовано** (FW.52, `firmware/queen/ota_sha_guard.h`) — деталі §«Обмеження / залишкові ризики» п.1 нижче.

> ⚖️ **Трейлер печатки й рандеву відповіді — два присуди, застосовано 2026-10-09 ([`00_07` FW.68](00_07_Action_Plan_Tracker)).**
> **(1) Перезапит покриває трейлер — founder 2026-10-06, ратифіковано за рекомендацією** («FW.68 ратифікуємо рекомендацію»). Корінь: трейлер (7 блоків) Королева слала одним проходом без перезапиту, тож при N деревах на Королеву шанс дерева зібрати всі 7 ≈ N⁻⁷ (HMAC-ера: 4 блоки, N⁻⁴), а дерево з повним тілом і неповною печаткою чекало вічно — таймауту нема, а Rails трейлера більше не підказує; FW.23 погіршив, але рій N ≥ 3 не фіналізувався й тоді. Безпеки це не стосувалось (непідписаного запису нема) — лише живучості. Присуд: Солдат із повним тілом і неповною печаткою стріляє `0x55` із сентинелом `total = 0xFFFF` і маскою відсутніх блоків у першому байті бітмапа (кадр того самого розміру); Королева тримає трейлер до світанку НАСТУПНОЇ кампанії й відповідає з нього; гігієна стану — світанок кампанії на Королеві скидає маску й фазу печатки, Солдат відкидає блок печатки з total ≠ total активного збирання. **Підстава:** той самий механізм, що вже рятує тіло, — без нового кадру й без циклічного ефіру для всіх. **Ціна:** нова семантика uplink-кадру `0x55` (карта опкодів [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA)), по кілька десятків рядків C обабіч із host-пінами; ефір — лише запитані блоки. **Альтернатива:** Королева крутить трейлер циклічно, поки вікно кампанії живе, — без зміни кадру, але ефір платять усі й без зворотного звʼязку (≈ 18 власних пострілів на дерево за колекціонером купонів). **Найслабша ланка:** конкуренція перезапитів у великому рої під duty-лімітером FW.61 — та сама, що вже в тіла, плюс раунд на дерево.
> **(2) Відповідь на зойк — борг, а не залп: ⚖️ ДЕЛЕГОВАНО 2026-10-09** (мандат founder-а 2026-10-09 на §03a/§03b, дослівно: «машинну роботу, застосування вже ратифікованих присудів і делегована ратифікація ще відкритих присудів по рекомендації»). **Подану 2026-10-06 поправку — «зойк у вікно, яке Солдат слухає, + залп Королеви під довжину вуха (≈ 2–3 блоки)» — НЕ ратифіковано: звірка коду спростувала дві її підстави.** Подання дослівно: зойк — до вуха того самого пробудження, «як уже чутий `0x56`», а Королева відповідає стільки блоків, скільки вміщує вухо (≈ 500 мс ÷ 165 мс SF9 ≈ 2–3); найслабша ланка подання — швидкість: 72 пропущені чанки ≈ 24 зойки ≈ 2 год на дерево, а наступний крок — довше вухо після зойку, тобто енергетичний ⚖️. Діагноз, на якому воно стояло, правдивий: RX-вікна після зойку нема (зареєстровано лише `RxDone`/`CadDone`), і тіло рій перезапитом на кремнії не добирав (FW.27-B); підставу «`0x56` уже так працює й доходить» стенд не мірив. Вухо Солдата бере ОДИН пакет за пробудження — кожна гілка RX-циклу Фази 4.5 закінчується `break` (ADR FW.52, §5.1.6 п.1), тож «2–3 блоки на зойк» на кремнії — один, а решта залпу горить в ефірі й у ліміті 36 с/год; а Королева стріляє рефлексом на КОЖЕН почутий кадр (`Queen_Reflex_Shots`), тож зойк, переставлений одразу за телеметрію, летів би рівно тоді, коли Королева стріляє у відповідь на неї (half-duplex — гинуть обидва). Плюс знахідка, якої поправка не бачила: дедуп зойку жив у `cmd_dedup_ring` — 16 слотів без часу (обіцяне «5 хв» не існувало), тож повтор після втраченої відповіді ігнорувався, а зойки рою під час кампанії витісняли ідемпотентні токени CMD, на яких стоїть повтор FW.63 (§6).
> **Механізм:** Королева на `0x55` лише ЗАПИСУЄ борг (DID · бітмап тіла або маска печатки) у таблицю на `OTA_RR_SLOTS` Солдатів — без залпу, без дедупа й без рефлексу на сам зойк чи на hello `0x56` (після hello вухо мусить почути перемотаний маяк, а не OTA-чанк); `Queen_Reflex_Shots(heard_did)` після адресної команди й ПЕРЕД глобальним курсором стріляє перший блок боргу цього DID і знімає його біт. Зойк Солдата лишився, де стояв (після вуха, перед сном), — нового рандеву не зʼявляється.
> **Підстава:** рандеву «кадр Солдата → рефлекс → вухо» — те саме, яким іде все тіло OTA, тобто нового припущення про таймінг не додає; швидкість — блок на пробудження після зойку (72 чанки ≈ 36 хв, трейлер ≈ 3.5 хв при циклі 26–32 с) проти блока на десять пробуджень у поданій поправці; Солдат не платить жодного нового мДж на рандеву відповіді (⊕ новий TX усе ж є — сам зойк печатки, абзац ⊕ нижче); ефір Королеви — блок на почутий кадр, як у глобального курсора, а не залп.
> **Ціна:** таблиця боргу в RAM Королеви (§9); пріоритет рефлексу трирівневий (команда > борг > глобальний курсор) — курсор просувається повільніше, поки хтось перепитує; трейлер займає памʼять до наступного світанку, а не до «аміня».
> **Найслабша ланка:** місткість таблиці у великому рої — витіснений борг відновлюється лише наступним зойком (≈ 10 тихих пробуджень), а Cold-TX deferral (мороз, [`03_01 §1.8а`](03_01_Firmware_Lifecycle_and_DMA)) зупиняє віддачу разом із телеметрією; обидва — швидкість, не безпека. Рандеву лишається моделлю до стенда ([`00_07` FW.68](00_07_Action_Plan_Tracker), [bench:ota-day]).
> ⊕ **Адверсар застосування (2026-10-09) — шість поправок коду й тексту; вимір — host-піни й ARM compile-lane.** (а) Запит печатки несе total тіла в байтах 8..9, і Королева приймає борг печатки лише трейлером ТІЄЇ кампанії (`Ota_Rr_Admissible`): без цього дерево, що проспало кампанію N і досі чекає печатку P, діставало б після «аміня» N сім блоків N, відкидало їх і перепитувало щоп'ять хвилин — ≈ 14 с/год із 36 с/год ефіру на кожне таке дерево; а чужий блок печатки Солдат лічить у той самий streak, що й чужий чанк тіла (FW.53), тож на трьох поспіль відпускає мертву кампанію. (б) Постріл за почутий кадр — ОДИН: після адресної команди Королева виходить, бо OTA-блок після неї летів би в закрите вухо, а `Ota_Rr_Mark_Sent` списав би борг. (в) Адресні постріли (команда й борг) — лише на кадр із перших рук (TTL автора, `TTL_BYTE_ORIGIN`): ECB-кадр, ретрансльований сусідом, до вуха автора не веде; Солдат службових кадрів (`0x55` · `0x56` · `0x57`) не ретранслює — у зойку байт 11 є бітмапом, і декремент «TTL» псував би запит. (г) Світанок кампанії — одна функція `Queen_Ota_Campaign_Dawn` із двома пускачами: перший CoAP-чанк тіла при порожньому збиранні й зміна `fw` у хінті (⊕ першого пускача знято того ж дня — [FW.60](00_07_Action_Plan_Tracker), §4а: після завершення тіла збирання теж порожнє, і повторний фетч стирав би зібране; лишився хінт); вона гасить і вікно з курсором — інакше курсор читав би буфер, який нова кампанія вже переписує, а недозбирана попередня кампанія злилась би з новою. (ґ) Зойк без відповіді подвоює наступну паузу (10 → … → 160 пробуджень, `OTA_REREQUEST_BACKOFF_MAX`), новий блок скидає відступ: Королева, що не тримає запитаного (трейлер ще не скачано · ребут), не коштує Солдатові TX кожні 5 хв довіку. (д) Рефлексу на hello `0x56` немає, тож у grace-вікні холодного старту OTA чекає його кінця. **Ціна поправок:** новий TX Солдата все ж є — сам зойк печатки (доти дерево з повним тілом мовчало вічно), обмежений відступом; «72 чанки ≈ 36 хв» — найкращий випадок (кадр із перших рук щопробудження, вухо відкрите, ефір вільний, без втрат) плюс перша тиша ≈ 10 пробуджень до зойку. **Межа покриття:** host-піни — таблиця й wire на справжніх функціях; клей `main.c` (світанок, «амінь», `seal_was_complete`, порядок і вихід рефлексу, гілка боргу, streak печатки, фільтр ретрансляції) — лише ARM compile-lane, без виконання.

**Ідея:** Soldier при `ota_chunks_received < ota_total_chunks` (або, за повного тіла, при неповній печатці) після тиші ініціює uplink-запит конкретних missing-блоків звичайним LoRa TX → Queen записує борг і віддає блоки рефлекс-пострілами на наступні кадри цього дерева.

**Soldier-side — епілог вуха Фази 4.5:**

```c
// firmware/soldier/main.c; wire і рішення — ../common/ota_rerequest_wire.h
const OtaReqKind req_kind = Ota_Req_Kind(ota_total_chunks, ota_chunks_received,
                                         ota_seal_segments_received);   // тіло → печатка → нічого
if (Ota_Req_Silence_Due(req_kind, ota_last_chunk_rx_tick != 0, &ota_silent_wakeups,
                        ota_rereq_backoff)) {          // 10 тихих пробуджень × 2^відступ
    // Ota_Req_Build_Body / Ota_Req_Build_Seal(…, ota_total_chunks, …) → ECB під KEYB →
    // Lora_Phy_Send(…, 16) → лічильник у 0, відступ +1; новий блок тіла чи печатки
    // скидає обидва в гілці прийому
}

// Один 16-Б ECB-блок: [0x55][DID:4 BE][total:2 BE][bitmap:9]
//   total = чанків тіла → біт i = чанк i бракує (≤ 72 на один зойк)
//   total = 0xFFFF      → тіло повне; bitmap[0] біти 0..6 = трейлер-блоки seg 1..7, яких бракує,
//                         [8..9] = total тіла, до якого печатка
```

**Queen-side** (`firmware/queen/main.c`, перед CIFO — у кеш і в CoAP зойк не йде):

```c
// Обробник 0x55 — лише запис боргу (ota_rerequest_table.h):
if (Ota_Rr_Admissible(req, body_total,
                      Ota_Rr_Body_Buffer_Same(&queen_ota_sha_ops, NULL, pending_ota_bytecode,
                                              pending_ota_size, ota_is_active),   // FW.52
                      seal_total_held)) {        // total трейлера, який Королева тримає (0 — не тримає)
    Ota_Rr_Record(&g_ota_rr, req);   // той самий DID — заміна; повна таблиця — по колу
}
// Queen_Reflex_Shots(heard_did, first_hand) — ОДИН постріл за кадр: адресна команда (і вихід)
//   → блок боргу цього DID (Ota_Rr_Peek → лімітер FW.61 → постріл → Ota_Rr_Mark_Sent) →
//   глобальний курсор; команда й борг — лише на кадр із перших рук (TTL автора).
// Queen_Ota_Campaign_Dawn(fw): зміна fw у хінті (FW.60 — пускач єдиний) — збирання, вікно,
//   курсор, трейлер і борг з нуля; збирання відтепер належить fw.
```

**Переваги Magic Re-Request:**

1. **Self-healing:** Soldier ініціює recovery без потреби в TDMA — у нього вже є jitter (`random_jitter % 500ms`) для уникнення collision з іншими uplink-пакетами.
2. **Targeted re-broadcast:** Queen відправляє лише missing chunks → 60-90% energy saving vs повторний wave.
3. **Vector OTA на одному пакеті:** 1 ACK-payload фіксує до 72 missing chunks одночасно (bitmap 9 Б — `OTA_REQ_BITMAP_MAX_BYTES`).
4. **Power-aware throttle:** Soldier перевіряє `vcap_voltage > VCAP_LISTEN_THRESHOLD` (2800 мВ) перед re-request — слабкі вузли не споживають енергію на uplink.

**Обмеження / залишкові ризики:**

1. ✅ **Queen `pending_ota_bytecode` lifetime — закрито (FW.52).** Раніше: якщо Queen вже відкинула буфер (після повного `ota_is_active=0` cycle), re-request не обслуговувався — потрібен був повторний CoAP push з Rails. Тепер `firmware/queen/ota_sha_guard.h` персистує SHA-256 зібраного байткоду на Queen's власну Flash-сторінку 125 (magic-last power-cut-safe, дзеркало дизайну `firmware/common/flash_ota.c` — Soldier-івський сиблінг на іншій сторінці, інший чіп) одразу по завершенні прийому; re-request по закритому вікну звіряє поточний буфер проти персистованого хеша — збіг обслуговує (буфер підтверджено той самий), розбіжність/нічого-не-персистовано лишає стару поведінку (мовчання, Soldier чекає наступного Rails-driven циклу).
2. **REREQUEST_MARKER (0x55) collision:** Маркер 0x55 вибраний так, щоб не конфліктувати з `OTA_MARKER (0x99)` та telemetry (DID byte 0 рідко 0x55, але можливо). Альтернатива — окреме AES-key namespace, що потребує SEC.3 (per-device HKDF). ⊕ 2026-10-09 ([`00_07` FW.68](00_07_Action_Plan_Tracker)): «рідко» — це ≈ 1/256 дерев, і для кожного з них — завжди, бо DID = f(UID) маркерів не виключає: у ECB-ері кадр такого дерева Королева класифікує як зойк, тож воно лишається без телеметрії й без рефлексу; у CCM-ері телеметрія (30 Б) іде повз за довжиною, а клас знімає wire-rev3-адресація ([`00_07` ARCH.43](00_07_Action_Plan_Tracker)).
3. **Replay:** зойк — ECB під KEYB без свіжості, тож перехоплений кадр можна повторити. Ціна атаки — ефір Королеви, але борг віддається лише на кадри ТОГО DID і не швидше за блок на кадр, а загальну стелю тримає лімітер FW.61 (≤ 36 с/год). Дедупу свідомо немає ([`00_07` FW.68](00_07_Action_Plan_Tracker)): попередній, у `cmd_dedup_ring` без часу, ігнорував чесний повтор після втраченої відповіді й витісняв токени CMD (§6).
4. **Дві кампанії з тим самим total не розрізняються** ([`00_07` FW.68](00_07_Action_Plan_Tracker); названо 2026-10-09 при застосуванні FW.68, клас — з рев'ю застосування FW.23, 2026-10-06): наступна кампанія з тим самим total, що застала дерево з частковим тілом, змішує чанки двох кампаній — REJECT (CRC32, тоді Ed25519) скидає збирання (`Reset_Ota_Assembly`), і дерево пропускає кампанію, якщо її вікно вже закрите. Падіння безпечне (неправдивого не записано), але це не лікування: ідентичності кампанії в LoRa-чанку тіла немає. Те саме з печаткою: тіло A зібране, трейлер неповний, а прийшла кампанія B з тим самим total — її блоки проходять `Ota_Seal_Block_Belongs` (той звіряє лише total), і відкидає їх уже Ed25519 (досі цей варіант стояв лише в коментарі `OtaPackagerService`).

#### 5.1.4 Інтеграція ARCH.26 (TDMA) → повна імплементація FW.27

Коли TDMA з'явиться (слот-примітив уже host-готовий: `Tdma_Slot_For_Did` / `Tdma_Slot_Tx_Offset_Ms`, §5а.2а — розподіл детермінований від DID без реєстрації; ⚠️ стеля фазової точності ±1 с обмежує детерміновану ізоляцію слотів до `ts_frac`-апгрейду):

1. **Aggregation window** (Дизайн A) стає feasible — Soldier'и розподіляються між слотами всередині 10-секундного вікна.
2. **Magic Re-Request** (Дизайн B) залишається корисним як safety net поза TDMA-вікнами.
3. Обидва дизайни ортогональні: A покриває collective recovery, B — individual recovery.

**Black-list рекомендація:** реалізовувати **Дизайн B (Magic Re-Request)** першим — він не вимагає TDMA, дає 80% користі з 20% складності. Дизайн A реалізовуємо одночасно з ARCH.26.

#### 5.1.5 [FW.27 follow-up] Soldier-side edge cases (host-test-only, 2026-05-03)

> **Кенозис тестів:** дозалучаємо 5 додаткових host-тестів у `firmware/test/test_soldier_logic.c`, що закривають реальні шуми ефіру в існуючому Magic Re-Request кодопотоці. Жодних змін у production firmware — це **freeze-contract regression bank**, який запобігає випадковому регресу при майбутніх рефакторингах.

| Сценарій | Тест | Що захищає |
|----------|------|-----------|
| Дублікат з ІНШИМ payload | `test_ota_duplicate_with_different_payload_preserves_original` | Anti-tamper: production guard `!ota_chunk_received[chunk_idx]` блокує перезапис, оригінальний payload незмінний байт-у-байт |
| STOP2 між OTA-чанками (out-of-order) | `test_ota_stop2_simulation_chunks_arrive_out_of_order` | bitmap-стан переживає множинні Process-цикли; offsets коректні після злиття |
| Той самий chunk після сну (дедуп у межах збирання, не транспортний анти-повтор) | `test_ota_stop2_simulation_duplicate_after_sleep_still_rejected` | Counter не подвоюється при повторному reflex shot Королеви |
| `total_chunks=0` malformed packet | `test_ota_total_chunks_zero_rejected` | Defence-in-depth: degenerate completion → CRC32 fail → no Flash write (not crash) |
| Seal trailer state cross-cycle | `test_seal_trailer_out_of_order_completes_with_version` | bitmask сегментів OR-агрегується по 7 окремих викликах у довільному порядку (кожен — окреме пробудження; STOP2 зберігає SRAM) → `0x7F`, печатка й версія цілі |
| Seal trailer idempotent overwrite | `test_seal_trailer_duplicate_segment_is_idempotent` | Дубль того самого сегменту не корумпує `received_ota_seal[]` |

> До 2026-10-06 ці два рядки несли HMAC-тести `test_hmac_trailer_*`; з Ed25519-печаткою ([`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)) їх замінили тести `Ota_Seal_Parse_Chunk` у тому ж файлі.

> **Cross-ref:** [`00_07`](00_07_Action_Plan_Tracker) FW.27 — повний контекст; [`04_06 §B.2`](04_06_Testing_Guide_and_Coverage) — тест-список.

#### 5.1.6 [FW.52] OTA throughput + `ota_is_active` lifetime — рішення прийнято

> **Статус:** ✅ обидва рішення прийнято founder 2026-06-12: **(а) повільний OTA прийнято як свідомий energy-first ADR** (п.1 нижче — обґрунтування); **(б) мертве вікно при запізнілій печатці виявилось reliability-багом і ВИПРАВЛЕНО** (п.2). Residual — лише bench ([`00_07`](00_07_Action_Plan_Tracker) FW.52).

Один повний reflex-shot OTA-цикл (§5) **повільний** (порядок днів-тижнів):

1. **1 RX-пакет за пробудження (Soldier) — прийнято by-design [ADR, founder 2026-06-12].** RX-вікно обробляє максимум один пакет за wake-цикл — усі гілки (`firmware/soldier/main.c`: сценарій OTA `0x99`, mesh-естафета, трейлер печатки `0x9B`) завершуються `break` перед `Radio.Sleep()`. Отже OTA на `N` байтів = `⌈N/11⌉` reflex-чанків = стільки ж пробуджень (1024 B → ~94). **Чому прийнято, а не «пофіксено»:** (i) після E.63 `delta_t` — це економіка дерева: зайве RX-слухання → довший перезаряд → менше growth_points; (ii) `break` після одного пакета — анти-vampire захист (флуд `0x99`-чанками не тримає Солдата з відкритим вухом); (iii) OTA рідкісний, а швидкий security-важіль (ротація ключа `0x9E`) — однопакетний downlink поза OTA-збіркою. Vcap-гейтований re-arm RX лишається опцією перегляду **після** bench-даних E_cycle/recharge (FW.50, RUNBOOK 3.2/3.3) — поріг гейта без цих кривих був би здогадкою.
2. **✅ (2026-06-12) Запізніла печатка воскрешає вікно (Queen) — було багом, виправлено.** Печатка (7 × `0x9B` з 2026-10-06) їде окремими CoAP-chunk'ами, порядок відносно тіла не гарантований. Коли тіло відлунало без зібраного трейлера, Queen слушно гасить `ota_is_active` ([PLAN 2.5] — не проповідувати в пустоту), але раніше запізнілий трейлер лягав у пам'ять **мовчки**: тіло в RAM ціле, печатка зібрана, Солдати кричать re-request — а вікно мертве до повторного повного Rails-push. Тепер `0x9B`-хендлер при довершенні трейлера (повна маска + тіло зібране й збірка idle + вікно згасле) **воскрешає вікно одразу у фазу печатки** — предикат `Ota_Late_Trailer_Resurrects` (`firmware/queen/ota_window.h`, pure; host-тести `test_queen_logic.c`), мутація стану в `main.c`. Анти-проповідь збережена: якщо трейлер так і не приїде, вікно лишається закритим (recovery = Rails re-push, як і було). Lifetime-обмеження `pending_ota_bytecode` (§5.1.3 — перезапис наступним push) незмінне.
3. **Re-request на замороженому tick — ✅ вирішено (2026-06-11).** Стара 5-хв перевірка лічилась на `HAL_GetTick` (заморожений у STOP2 → міряла лише active-час, зойк запізнювався у ~6-15×). Тепер тиша = `OTA_REREQUEST_SILENT_WAKEUPS=10` пробуджень з відкритим вухом (§5.1.3) — STOP2-імунно за конструкцією і без залежності від FW.49 LSE; wall-clock лишається опцією уточнення post-bench, якщо знадобиться точний хвилинний інтервал.

> **Cross-ref:** FW.52 (рішення + контекст), FW.49 (wall-clock tick), §5.1.3 (re-request), §5 (reflex-shot механізм).

---

## 📡 5а. Time Sync (FW.20, FW.20-S2) — Канонічний хаб

> **SSOT для Time Sync:** ця секція — єдина точка розкладки часо-синхронізаційного протоколу між Rails ↔ Queen ↔ Soldier. Усі деталі реалізації, статуси чек-боксів і регресійні тести зведені тут; [`00_07`](00_07_Action_Plan_Tracker) FW.20 / FW.20-S2 тримає лише посилання сюди.

### 5а.1 Архітектура (3 рівні reach)

```
Rails (NTP/UTC source)
   │  CoAP downlink envelope: [0x9C][unix_ts_be:4][payload]   ✅ FW.20 (транспорт = poll §4а [FW.60] —
   │    конверт їде в КОЖНІЙ poll-відповіді, окремої кампанії не треба)
   ▼
Queen (LTE-anchored time)
   │  ① Reflex broadcast `[0x9C][ts:4][TDMA-resv:4][AUTH_FLAG|TTL][magic 'B'][PAD:5]`  ✅ FW.20
   │  ② Authoritativeness flag (byte 9 bit 7 = AUTH); TTL=2 — 1 relay-хоп             ✅ FW.20-S2 (1/5)
   │
   │  1-hop reach (direct LoRa coverage)
   ▼
Soldier — direct
   │  ③ Drift-monitor + panic sync request `[0x56][DID:4][secs:4][TTL]['S'][vcap:2]` ✅ FW.20-S2 (2/5)
   │     — hot-path wired обабіч ФАЗИ 4: cold-boot hello (ARCH.41-C, 0x56 ЗАМІСТЬ
   │       телеметрії у grace-вікні) + warm-зойк watchdog'а ПОВЕРХ телеметрії
   │       (cooldown ≈1 год; Queen у відповідь перемотує такт маяка → re-sync тим
   │       самим пробудженням). Hook, не пасивна надія: вухо Фази 4.5 (600 мс/цикл)
   │       ловить 15-хв маяк у середньому ~раз на 12 год — впритул до порога
   │       TIME_SYNC_DRIFT_THRESHOLD_WAKEUPS, а квазі-резонанс такту з циклом
   │       може давати довші сухі смуги
   │  ④ Per-hop drift compensation + anti-storm журнал поколінь (mesh-relay)           ✅ FW.20-S2 (3/5 + 4/5)
   │     — `Soldier_Try_Relay_Time_Beacon` вшито у RX-гілку Сценарію 0 за гейтом
   │       `FW20_MESH_RELAY_ENABLED` (фліп = bench Flash-KV HAL, як FW.17/FW.2; FW.8 ⚫);
   │       журнал — Flash-KV `0x20` (`common/beacon_dedup.h`, реєстр 03_01 §2.3.1):
   │       ≤1 ретрансляція на покоління (`unix_ts/900`) на Провідника — TTL задає
   │       ГЛИБИНУ mesh'а, журнал гасить ОБСЯГ (подвійний маяк у такті, пінг-понг
   │       при TTL≥3); без журналу (mount-fail) — fallback на auth-гейт (2-hop)
   │
   │  2-hop reach (mesh relay через Provisioners)
   ▼
Soldier — relayed
   │  ⑤ Gossip-piggyback freeze-contract: byte 14 у normal-telemetry payload          ✅ FW.20-S2 (5/5)
   │     — `Soldier_Pack_Gossip_Ts_Byte` / `Soldier_Try_Apply_Gossip_Ts` callable
   │     — без активації у hot path (потребує hook у Phase 2 + RX-обробник)
   │     — точність ±128 сек (1 байт LSB), достатньо для FW.30 cold-start `epoch_day`
   │     — ⛔ календаря НЕ пише (SEC.42): LSB секунд повторюється кожні 256 с, тож старий
   │       кадр декодується зсувом до ±127 с, а в CCM це AAD без ключа відправника — лише підказка epoch_day до синку
   ▼
Soldier — gossip-uplift (3-hop reach)
```

> 🔒 **Маяк повторюваний, тож база `delta_t` іде за фактичним кроком годинника, а крок НАЗАД обмежений** ([SEC.42], 2026-10-09, після двох раундів адверсара): застосування маяка — одна функція `Silken_Beacon_Commit` (`firmware/common/wall_time.h`) з ops-швом календаря, і її ж кличе host-дзеркало. Уперед Солдат бере маяк як є (повтор дає лише старі мітки, майбутньої без KEYB не підробити); назад календар іде не далі за `2 с + 100 ppm × час від останнього синку`, а коли мітку синку загубив скид SRAM — `2 с + 100 ppm × 180 діб`; більший крок клемпиться до межі. База `delta_t` зсувається на крок, ПЕРЕЧИТАНИЙ із календаря після запису, тож невдалий чи частковий запис (час ліг, дата — ні) гроші не зачіпає; лишається до секунди-двох на маяк (календар судиться цілими секундами, а запис починає секунду наново), більше — лише на апаратному збої RTCCLK під час запису. Мітку синку й сторож дрейфу рухає запис, що ліг (календар у [ціль, ціль + 1]), і сторож скидає лише повний синк; читання, що віддало 0 (на запіненому WL-HAL недосяжне), помиляється в бік довшого `delta_t`. Піни — `test_sec42_*` і `test_beacon_rx_*` (`firmware/test/test_soldier_logic.c`, зокрема невдалий і частковий запис); що `main.c` кличе її рівно раз із тим самим станом і що іншого писача календаря немає, стереже grep у цілі `soldier` (`firmware/test/Makefile`) — носій від випадкової регресії, а не межа проти навмисної правки. ⚠️ **Межа обмежує КРОК, не суму:** повтор щопробудження відводить календар на межу щоразу, доки не прийде чесний маяк уперед — він лікує одразу, — тож абсолютний час стереже не межа, а наступний справжній синк; коли абсолютний час стане несучим (TDMA, [`00_07`](00_07_Action_Plan_Tracker) ARCH.26), потрібен бюджет суми від останнього ПОВНОГО синку або автентифікований маяк (нога SEC.42). ⚠️ Без мітки синку межа бере кеп: на reset-циклі IWDG і в Standby, доки FW.54 не персистує мітку, це КОЖНЕ пробудження, тож мітка мусить увійти в живий набір ([`00_07`](00_07_Action_Plan_Tracker) FW.54). ⚠️ Передумови межі — RTC на LSE (на швидкому LSI чесний маяк клемпився б за живої мітки синку) і похибка часу Королеви в межах підлоги: її SysTick екстраполює до години між синками з сервером, а `Apply_Server_Time` бере мітку сервера без поправки на затримку зворотного каналу, тож два ресинки можуть ступити назад на різницю затримок; тактування Королеви — вимога board-freeze ([`00_07`](00_07_Action_Plan_Tracker) FW.46). ⚠️ Залишок, якого межа не закриває: перший синк на календарі від 2000-01-01 приймає будь-який маяк — повтор дає хибну добу ECB-деривації, і вона тримається до першого чесного маяка уперед (повтори далі клемпляться назад), а `time_uncertain` тим часом гасне, вимикаючи серверний захист ARCH.41-B для цих кадрів; гроші не підтверджено, ця ера в поле не йде. Присуд, розвилки й поправки адверсарів — врізка [SEC.42] у [`03_05 §2.4`](03_05_Hardware_Symmetric_Crypto_and_Security); серверна половина — [`00_07`](00_07_Action_Plan_Tracker) SEC.42.

### 5а.2 Wire-формати

| Опкод | Маркер | Напрямок | Формат | Розмір | Cross-ref |
|-------|--------|----------|--------|--------|-----------|
| CMD_TIME_SYNC envelope | `0x9C` | Rails→Queen (CoAP, доставка = poll §4а [FW.60]) | `[0x9C][unix_ts_be:4][inner_payload]` | 5+N байт | FW.20 §1, `app/workers/concerns/coap_encryption.rb` |
| Time Beacon | `0x9C` + magic `'B'` | Queen→Soldier (LoRa ECB) | `[0x9C][ts:4][TDMA:4 →§5а.2а][AUTH\|TTL][magic 'B'][PAD:5]` | 16 байт | FW.20 §2 |
| SYNC_REQUEST | `0x56` + magic `'S'` | Soldier→Queen (LoRa ECB) | `[0x56][DID:4][secs_since_sync:4][PANIC_TTL][magic 'S' = 0x53][vcap_mv:2 BE][PAD:3]` | 16 байт | FW.20-S2 §3, `firmware/soldier/main.c:Build_Time_Sync_Request_Payload` |
| Gossip ts_lsb (freeze) | — | Soldier→Soldier (piggyback у telemetry) | 21B ECB: plaintext byte 14 = `(soldier_unix_ts & 0xFFu)`, valid коли `StatusByte & PANIC_FLAG_BIT == 0`. **CCM wire-rev2: AAD byte 4** (cleartext навмисно — сусід читає без per-Soldier ключа, бекенд автентифікує MIC'ом; [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) wire-budget ledger) | 1 байт задарма обома форматами | FW.20-S2 §5 |

#### 5а.2а TDMA слот-розкладка маяка — байти 5..8 (ARCH.26 L2) — 📐 wire-дім

> **Статус:** 🟡 host-half (2026-07-02) — pack/parse/математика вікон написані обабіч і INERT за дзеркальними гейтами `ARCH26_TDMA_ENABLED 0` (queen + soldier); фліп = bench WUT-армінг ([SEC.15](00_07_Action_Plan_Tracker)/[FW.49](00_07_Action_Plan_Tracker)). One-Home математики — `firmware/common/tdma_schedule.h` (обидва main.c + host-тести компілюють одне джерело). Рандеву-контекст + енерго-політика ролей — [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA) (тут лише wire).

| Байт | Поле | Семантика |
|------|------|-----------|
| 5 | `period_min` | Період синхронних вікон, хвилини. **`0` = TDMA off** — нинішній нульовий ефір означає «вимкнено» за конструкцією, старі прошивки сумісні без фліпу |
| 6 | `window_100ms` | Довжина вікна у 100-мс квантах (Queen шле `20` = 2.0 с) |
| 7 | `slot_count` | TX-слоти всередині вікна для uplink'ів (FW.27-A); `0` = unslotted. Слот вузла = `DID % slot_count` — детерміновано, без реєстрації у Королеви |
| 8 | `phase_4s` | Фазовий зсув сітки у 4-с квантах — розводить сусідні кластери/Queen |

- **Сітка вікон:** вікно відкривається коли `unix_ts % (period_min×60) == phase_4s×4`; членство `[start, start+window)`, наступний старт — `Tdma_Next_Window_Start` (строго майбутній момент — готовий вхід RTC-WUT-армінгу).
- **Parse fail-closed:** `period=0` (легальний off) / `window=0` / `phase ≥ period` (сміття, бітфліп) → schedule disabled; невалідний маяк **затирає** попередній валідний кеш.
- **Кеш Солдата — RAM-only derived state** (як `soldier_unix_ts`): гине з SRAM у RTC-only сні (клас Standby — [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA) ⚠️) / VBAT-loss, відновлюється наступним маяком ≤ 15 хв → **нуль нових RTC DR / Flash-KV ключів** ([`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA) бюджет повний). Провідник ретранслює байти 5..8 as-is (relay-тест тримає транзит).
- **Стеля точності (позначена):** маяк несе цілі секунди → фазова похибка вузла ≈ ±1 с (округлення + encrypt/airtime); слоти коротші за ~2 с розкидають популяцію **статистично** (фазові групи + FW.10 jitter), не ізолюють детерміновано. Шлях апгрейду: `ts_frac` (1/256 с) у **байті 11** (перший PAD) → ±4 мс → 100-мс слоти; байт зарезервовано, не реалізовано. **Sync-бюджет WUT-влучання = ±10 мс** (ціль детермінованих слотів; gossip-fallback ±128 с придатний лише для `epoch_day`, не TDMA): типовий LSE ±20 ppm набігає ~±18 мс за 15-хв такт маяка → чи вкладається реальний кварц у бюджет, вирішує bench `04_lse_drift.py` ([`00_07` — ARCH.26](00_07_Action_Plan_Tracker) — коротший такт / кращий кварц / ширший guard-інтервал).
- **Queen-константи** (`queen/main.c`): `TDMA_PERIOD_MIN 15` (= такт маяка) · `TDMA_WINDOW_100MS 20` · `TDMA_SLOT_COUNT 4` · `TDMA_PHASE_4S 0`.

### 5а.3 Магія RX-класифікації (карта опкодів — не тут)

> **Карта опкодів LoRa/CoAP живе в [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA#45а-downlink-opcode-map--canonical-ssot-doc4) [DOC.4] і сюди НЕ копіюється.** Тут — предмет САМЕ Королеви: за чим вона розрізняє кадри після того, як перший байт прочитано. 🔴 Копія карти стояла тут і розійшлася з домом двома способами — бракувало живого `0x57`, а `0x9A` мав імʼя, якого немає більше НІДЕ в дереві. Підстава — One-Home ([`00_06 §2`](00_06_SSOT_Documentation_Standard)): другий список опкодів є не варіантом оформлення, а підозрою на дубль.

| Опкод | Чим Королева розрізняє | Примітка |
|-------|------------------------|----------|
| `0x56` | byte 10 = `'S'` (0x53) | `SYNC_REQ_MAGIC_BYTE`, panic sync |
| `0x57` | byte 10 = `'E'` (0x45) | device-event; магія — анти-DID-колізія (`firmware/common/device_event.h`) |
| `0x55` | **магії НЕМА** | OTA re-request: у коді немає ані `#define`, ані перевірки — розрізнення тримається на тому, що магія є в СУСІДІВ |
| `0x9B` | seg_idx 1..6 печатка + 7 version | OTA dual-gate trailer (Ed25519, [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)) |
| `0x9C` | byte 10 = `'B'` (0x42) на LoRa-беконі | CoAP-лег конверта магії не несе |
| `0x9A` · `0x9E` | довжина за опкодом (23 · 17 Б; `0x9D` — RETIRED з HW.30, байт не перевикористовується) | адресна команда під CCM сесійним ключем цілі (§5б, [`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)) — Королева ключа не має й перевіряє лише структуру |

> ⚠️ **Дезамбігвація uplink-трійки `0x55`/`0x56`/`0x57` асиметрична, і це не оздоба.** Магію мають лише двоє; `0x55` розпізнається як «маркер збігся, магії сусідів немає». Той самий клас колізії названо в коді: старший байт DID може випадково дорівнювати маркеру (`StatusByte 0x45 × DID-старший 0x57 = 1/256`), і знімає його не магія, а майбутня wire-rev3-адресація разом з рештою control-опкодів.

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

// [FW.20-S2 4/5] Anti-storm журнал поколінь (firmware/common/beacon_dedup.h)
#define FW20_DEDUP_KV_KEY                0x20u      // Flash-KV: [gen_hi:24|window:8]
#define FW20_DEDUP_GEN_SECONDS           900u       // такт покоління = період маяка
#define FW20_DEDUP_WINDOW_BITS           8u         // 2 год — глибше за max hop-delay
#define FW20_MESH_RELAY_ENABLED          0          // фліп = bench Flash-KV HAL
// Wall-кванти Солдата = ПРОБУДЖЕННЯ (2026-06-11): HAL_GetTick мертвий у
// STOP2 — tick-пороги розтягувались у ~6-15× wall (та сама пастка, що
// FW.27-B). Цикл 26-32 с (IWDG-вікно) → пробудження і є годинник.
// Лічильники SRAM (переживають STOP2, гинуть з VBAT — grace перезапускається).
#define TIME_SYNC_DRIFT_THRESHOLD_WAKEUPS 1440u     // ≈12 год без beacon → panic
#define TIME_SYNC_REQUEST_COOLDOWN_WAKEUPS 120u     // ≈1 год між зойками
#define TIME_SYNC_COLD_BOOT_GRACE_WAKEUPS  20u      // ≈10 хв cold-boot grace (ARCH.41-C)
#define SOLDIER_NOMINAL_CYCLE_S          30u        // wire-конверсія wakeups→сек (0x56 поле, ±20%)

#define GOSSIP_TS_PAYLOAD_OFFSET         14u        // byte 14 у normal telemetry
#define GOSSIP_TS_MAX_DRIFT_SEC          127u       // ±128 sec window для gossip
```

> ⚠️ **«Пробудження = годинник» не правдиве на жодному чинному режимі** (знайдено 2026-10-09, застосовуючи SEC.42; уточнено адверсаром): ці пороги припускають і живу SRAM між пробудженнями, і цикл ≈ 30 с, а такого режиму немає — цикл IWDG є скидом (лічильники в `.bss` обнуляються щоразу, тож на ньому `soldier_unix_ts` = 0 при кожному TX і grace-hello заміщує телеметрію щопробудження), WUT/STOP2 зберігає SRAM, але каденс ≈ 1.8 год CCM-ери, а Standby не має ні того, ні того. На каденсі CCM-ери ті самі числа дають ≈ 108 діб тиші до зойку, ≈ 9 діб між зойками, ≈ 36 год hello після холодного старту і `secs_since_sync`, занижене в рази. Wall-час, якого бракувало, коли ці пороги ставили, дав FW.49 (`Silken_Wall_Elapsed_Seconds` оголошено саме для цих сторожів), тож перевести їх на wall-мітки можна, щойно календар живий на кремнії. Що це дає живому набору Standby — різне: тишу синку виводити з мітки ОСТАННЬОГО ПОВНОГО синку, окремої від `soldier_unix_ts` (ту рухає й обрізаний крок SEC.42, тож на ній клемп знову став би повним синком); cooldown зойку стає міткою останнього зойку і мусить бути не коротшим за каденс, інакше обрізаний синк кликав би зойк щопробудження; grace виводиться з календаря лише після втрати VBAT (після скиду чи пробудження зі Standby календар уже UTC), тож `time_uncertain` тоді визначати як `!Silken_Wall_Is_Utc`. ⚠️ `OTA_REREQUEST_SILENT_WAKEUPS` (FW.27-B) його дім лічить як ЧАС («5 хв тиші»), але на каденсі, довшому за 5 хв, часовий поріг перепитував би на кожному пробудженні без чанка — одиниця (час ⊥ нагоди почути) вирішується на тому ж фліпі, наперед не присуджена. Нога — [`00_07`](00_07_Action_Plan_Tracker) FW.54.

### 5а.5 Регресійний бенч

> Кількісні тарифи тестів тут не ведемо (дрейфують щокомміту) — істина в самих тест-файлах; нижче — покриття за шарами.

| Шар | Тест-blok | Файл |
|-----|-----------|------|
| Backend `CoapEncryption` envelope | TIME_SYNC envelope strip + roundtrip | `spec/workers/concerns/coap_encryption_spec.rb` |
| Queen beacon plaintext | `Build_Time_Beacon_Plaintext` byte 9 = 0x82 (auth=1 \| TTL=2 — регресійна точка) | `firmware/test/test_queen_logic.c` |
| Soldier beacon RX | authoritative/relay/legacy byte9 → flag | `firmware/test/test_soldier_logic.c` |
| Soldier drift-monitor | `Soldier_Should_Request_Time_Sync` cold-boot/grace/cooldown/payload layout | `firmware/test/test_soldier_logic.c` |
| Soldier mesh-relay (per-hop drift) | `Soldier_Try_Relay_Time_Beacon` всі drop-reasons + happy + boundary (NULL-dedup = legacy auth-гейт) | `firmware/test/test_soldier_logic.c` |
| Soldier mesh-relay anti-storm (4/5) | журнал поколінь: auth=0 unlock, подвійний маяк у такті, пінг-понг при TTL=4, out-of-order у вікні, stale-відмова, DUPLICATE-останнім | `firmware/test/test_soldier_logic.c` |
| Журнал 0x20 persistence | roundtrip/window-slide/big-jump/wear-дисципліна/program-fail/garbage/compact — поверх реального Flash-KV з power-cut | `firmware/test/test_flash_kv.c` |
| Soldier gossip-piggyback (freeze) | pack/apply, cold-boot, drift cap, window selection | `firmware/test/test_soldier_logic.c` |
| TDMA слот-розкладка (ARCH.26 L2, §5а.2а) | pack↔parse roundtrip, all-zero=off, fail-closed сміття, next-window сітка/строго-майбутнє, in-window межі, DID-слот детермінізм, wire-екстремуми | `firmware/test/test_tdma_schedule.c` (`make -C firmware/test tdma`) |
| CAD-нюх + PANIC-преамбула (ARCH.26 L3 — Soldier-side, [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA)) | роль-гейт (лише Провідник), каденція wall-guards, чверть-символьна математика (мінімальність/floor-8/сатурація-65535), дворівневий V_cap-гейт, інваріант T_pre > T_sniff | `firmware/test/test_cad_sniff.c` (`make -C firmware/test cad`) |

### 5а.6 Що ще лежить як freeze-contract (deferred TRL-7)

- ✅ (2026-06-12) **Anti-storm журнал поколінь** — реалізовано: `common/beacon_dedup.h` поверх Flash-KV ключа `0x20` (реєстр — [`03_01 §2.3 ARCH.28`](03_01_Firmware_Lifecycle_and_DMA#23-overflow-strategy-flash-based-kv-store-arch28)); wiring у `soldier/main.c` за гейтом `FW20_MESH_RELAY_ENABLED=0` — residual = чистий bench-фліп (верифікація Flash-KV HAL, спільна з FW.17/FW.2; FW.8 ⚫)
- ✅ (2026-06-12) **Queen beacon TTL=2** (`BEACON_BYTE9_AUTHORITATIVE = 0x82`) — канонічна умова «перемикається коли реалізуємо anti-storm» виконана. Глибше TTL (3+ хопи) — рішення founder'а про airtime: журнал робить його шторм-безпечним (TTL обмежує лише глибину, обсяг ≤1 ретрансляція/покоління/Провідник), фліп = одна константа
- **Hot-path виклик** `Soldier_Pack_Gossip_Ts_Byte` у Phase 2 normal-telemetry pack + RX-обробник для прийому. (Дім у CCM-кадрі вже зарезервовано — AAD byte 4, wire-rev2: gossip переживає per-Soldier ключі; CCM-фліп вшиває pack-половину автоматично через параметр `Soldier_Build_CCM_LoRa_Packet`)
- **Drift compensation** при ΔT = ±60°C lab-вимірювання (потребує термокамери, відсутня @ TRL-6)

> **Закриття 00_07:** після цього хабу записи `FW.20`, `FW.20-S2 (1/5..5/5)` у [`00_07 §03a`](00_07_Action_Plan_Tracker#03a--firmware) шорткозамкнено — лишилося лише посилання сюди для аудиту прогресу.

---

## 📨 5б. Soldier Command Relay (FW.20-Q2) — черга рефлекторних пострілів

**Статус:** ✅ написано (2026-06-12), переписано під downlink-wire-ревізію 2026-09-29 (адресні CCM-кадри, [`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)); інертне за гейтом `FW20_Q2_CMD_RELAY_ENABLED 0` — фліп разом із приймачем Солдата `FW17_RATCHET_ENABLED` (`FW8_PARSER_ENABLED` — ⚫ FW.8 2026-10-06, не фліпається; `0x9A` знімає реалізація (Б), [`00_07`](00_07_Action_Plan_Tracker) FW.66).

Королева — **сліпий курʼєр** для команд, адресованих одному Солдату: `0x9A` пороги Лоренца · `0x9E` ротація ключа (`0x9D` аудіо-пороги виведено з пʼєзо, HW.30; опкод-карта [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA#45а-downlink-opcode-map--canonical-ssot-doc4)). Кадр `[opcode][DID][DLFC_lsb][CCM(body)][MIC]` підписує Rails сесійним ключем цілі; ключа Королева не має. Дім коду: `firmware/queen/soldier_cmd_queue.h` (pure) + глю в `queen/main.c`; формат — `firmware/common/downlink_ccm.h`; host-тести `firmware/test/test_soldier_cmd_queue.c` (`make -C firmware/test cmd_queue`).

**Шлях слова:** `Handle_CoAP_Command` (після зрізання 0x9C-конверта) бере довжину з опкоду (конверт її не несе: CBC-вирівнювання нулями) → **лише структура**: командний опкод і рівно його довжина (MIC звіряє Солдат) → черга: слот 24 Б (кадр до 23 Б + довжина) → **адресний рефлекторний постріл** `Queen_Reflex_Shots(heard_did)` — лише коли почутий DID збігся з DID команди; кадр летить як є, без жодного шифрування Королеви, замість OTA-блока (команда першою й єдиною: вухо Солдата бере один пакет, ADR FW.52, — блок після неї летів би в закрите вухо; ⚖️ FW.68). Почутий DID — з відкритого AAD у CCM-ері і з байтів 0..3 ECB-телеметрії; на зойк 0x55 і hello 0x56 рефлексу немає зовсім, 0x57 несе там маркер, тож адресний постріл за ним не влучає, а ECB-кадр, ретрансльований сусідом (TTL < TTL автора), адресних пострілів не дістає — вухо автора вже закрите.

**Порядок для одного DID — за DLFC, найменший першим** (серійне порівняння по 16 бітах ефіру): Солдат приймає лише DLFC, строго більший за останній прийнятий, тож старша команда, вистріляна після молодшої, не відкрилась би вже ніколи.

**Чому рефлекс, а не маяковий слот (ADR):** Солдат слухає ефір лише ~500 мс після ВЛАСНОГО TX — постріл услід за його голосом є єдиним гарантовано чутим вікном; періодичний маяк летить у переважно глухий ліс. Первісний ескіз «спільна з beacon TX черга» відкинуто.

**Бюджет замість ACK:** на LoRa-рівні ACK нема (справжній per-device ACK `0x9E` — Dual-Key Grace на бекенді, [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)). `SOLDIER_CMD_SHOT_BUDGET` = **4 спроби В ЦІЛЬ** — інженерний параметр, не вимір: кожен постріл летить у відкрите вікно саме цієї цілі, тож бюджет покриває лише втрачені вікна (радіо, правило «один пакет за пробудження»). Колишні 64 постріли мали підставу «покрити оберт кластера», бо стріляли після будь-якого Солдата; адресність її зняла, а 64 спроби в ціль повернули б холості постріли, які вона й знімає (ціна присуду [`03_05 §2.5`](03_05_Hardware_Symmetric_Crypto_and_Security)), і на години тримали б наступну команду того ж дерева за вже доставленою. Повтори нешкідливі за конструкцією: прийнятий кадр Солдат удруге не відкриє (DLFC уже не строго більший). Дедуп — Rails перевидає відкриту команду тим самим кадром, і дублікат лише освіжає бюджет. **Жертва переповнення — найдавніше поставлений чи освіжений слот**, не «найменший лишок»: за адресних пострілів лишок меншає лише в живих цілей, тож старе правило витісняло б саме їх, лишаючи команди дерев, що мовчать.

**Активація:** колишні гейти (i) «ECB-downlink без MAC» і (ii) «кадр без DID-таргета» ([`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)) закриває сама форма кадру — MIC сесійним ключем цілі і DID в AAD; фліп реле — разом із приймачами Солдата. Глибина черги під кластерну ротацію (різні кадри на кожен вузол) — нога активації FW.17.

---

## 🛡️ 6. Actuator Command Dedup (Idempotency Ring Buffer)

### Проблема, яку вирішує

**[FW.60]** `CMD:*` прибуває як відповідь на власний `poll/<uid>` Королеви (§4а;
push-воркер superseded — CGNAT). Якщо команда прилетіла двічі, без дедуплікації
клапан відкрився б двічі — саме це закриває ring-buffer нижче.

> 🔴 **[FW.63] Виправлено 2026-07-27.** Тут стояло: «Якщо 2.05-відповідь
> загубилась, Королева CON-ретрансмітить той самий MID і Rails віддає її
> байт-ідентично (MID-кеш `CoapGate`)». Це **неправда** і ніколи не було
> правдою: `Queen_Poll_Downlink` робить `coap_mid++` на КОЖНУ спробу й виходить
> при порожній відповіді, а `Sim7070_Udp_Fetch` — одна розмова
> `CAOPEN→CASEND→CADATAIND→CARECV→CACLOSE` без внутрішніх ретраїв. Same-MID
> retry існує лише в **uplink-PUT** (`COAP_MAX_RETRIES` навколо незмінного
> `coap_mid`, §4) — звідти механіку помилково перенесли на poll-GET. MID-кеш
> `CoapGate` лишається корисним (мережеве дублювання датаграми), але діру
> «втрачена 2.05 → наказ зник назавжди, а слід каже `confirmed`» він НЕ
> закриває — її закрив `?cmd=`-echo (§4а вище, 2026-09-09) → [`00_07` FW.63](00_07_Action_Plan_Tracker).
>
> ⊕ **Наслідок для самого кеша, закритий 2026-09-08.** Якщо ретрансміту немає,
> то same-MID приходить рівно двома шляхами з ПРОТИЛЕЖНОЮ ціною: дубльована
> датаграма (безневинна — кеш і є правильна відповідь) і **пост-ребутна
> колізія MID** (`coap_mid` живе в RAM Королеви, слот кешу TTL не має → той
> самий номер несе ІНШЕ питання, і віддати кеш означає відповісти на чуже,
> мовчки проковтнувши поточний pending). Доти обидва рахувались одним
> лічильником `poll_retransmit`, тобто небезпечний носив імʼя безневинного.
> Тепер кеш тримає **відбиток запиту** (маршрут + query): збіг → `poll_duplicate`
> і кеш; розбіжність → `poll_mid_collision` і свіжа деривація. ⚠️ Стеля: колізія
> з ідентичним відбитком лишається невідрізнимою від дубля (питання те саме,
> відповідь виправляється наступним poll'ом) — повний лік = TTL на слот, і він
> свідомо не будується (машинне рішення 2026-09-08; ⚖️ FW.63 від 09-10 TTL не судив).

### Механізм

> **⚖️ Вокабуляр ACTION — доменний за `device_type`** (присуд власника 2026-08-14,
> [`00_07` UI.14](00_07_Action_Plan_Tracker)): `OPEN_VALVE` · `ACTIVATE_SIREN` ·
> `ACTIVATE_BEACON` · `STOP`. Підстава не стильова: Королева реєстру пристроїв не має
> і мати не буде, тож універсальний `OPEN` вимагав би від неї знати, що актуатор 42 —
> це клапан. **Самоописова дія — єдина форма, що працює на stateless-шлюзі**, і саме її
> вже пишуть усі продові писачі (`EmergencyResponseService`, `ActuatorSafetySweepWorker`,
> UI). Шару перекладу немає ніде й не буде: `ActuatorCommand.override_payload?` звіряє
> префікс ТОЧНИМ збігом, тож наївний `.upcase` у контролері зробив би `stop` командою,
> що гасить чергу актуатора. Дім регексу — `ActuatorCommand::ALLOWED_PAYLOAD_FORMAT`
> ([`04_01 §4`](04_01_Data_Models_and_Entities)); Королева ACTION не інтерпретує взагалі
> (§6 нижче — на місці виконання коментар, не код).

```
Формат команди (plaintext після CBC decrypt):
  CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<IDEMPOTENCY_TOKEN>
  Приклад: CMD:OPEN_VALVE:60:42:a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Токен = ОСТАННЄ поле: Королева ключує на останній ':' (cmd_token.h, pure,
  host-тестований), Rails гарантує ACTION без двокрапки (ALLOWED_PAYLOAD_FORMAT).
  [FW.60] Доти — «після 3-ї ':'»: `ACTION:value` зсував вікно на ACTUATOR_ID,
  дедуп лишався self-consistent, а echo ?cmd= ніколи не збігався з токеном.

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

## 👑 7. Пульс Королеви — health-блок QATT-v2 [ARCH.54; DID=0-sentinel retired]

### Було (retired 2026-07-03)

DID=0-псевдодерево у батчі: 16B-пакет маскував health під телеметрію. Байтова звірка викрила подвійну брехню — бекенд читав його Солдатськими офсетами (uptime→`voltage_mv`, `0x00`→temperature, cache_count→CSQ), `battery_critical?` хибно горів ~5% життя (uptime-wrap 18.2 год), а при size-flush (cache 45..50 > CSQ-валідного 0..31) пульс мовчки дропався САМЕ під навантаженням; у CCM-ері 16B-запис ще й ламав CCM-stride. e2e був циркулярним (Ruby↔Ruby, без golden проти firmware-байтів).

### Стало

Пульс живе у **header'і підписаного QATT-v2 конверта** (кожен flush; wire-дім — [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security), бітова розкладка One-Home `firmware/common/queen_attest.h`):

- **Джерела в `main.c`:** `g_uptime_minutes` (sw-extended лічильник — `HAL_GetTick` вмирає на 49.7-й добі), `cache_count`, `lora_rx_drops` (сатурація u8), `g_coap_fail_count` (всі-retry-впали + DNS-fail), `g_last_csq` (`Sim7070_Read_Csq` перед flush-розмовою; 0xFF до першого успіху → бекенд пише NULL), `flags` (CCM-ера / ARCH.35-ринг / **reset-cause**, §7.1).
- **Empty-flush heartbeat:** порожній CIFO при таймерному тику → конверт без записів (`header+IV+sig`, ~97 Б LTE) — пульс за тихої години; гейт `ed25519_ready` (legacy-плата без сім'ї не палить DC даремно). Backend legально скипає unpack (ct=0 — лише під конвертом).
- **Masking-attack закритий конструкцією:** health без валідного Ed25519 не існує (`UnpackTelemetryWorker` енкʼює пульс ЛИШЕ з `:attested`-гілки).
- **Маршрутизація на сервері:** `enqueue_envelope_health` → `GatewayTelemetryWorker` (черга uplink) → `GatewayTelemetryLog` (нові колонки `uptime_min/cifo_fill/lora_rx_drops/coap_fail_count/health_flags`; `voltage_mv` — nullable до ADC-тракту, `temperature_c` — до датчика (DS18B20 по 1-Wire, HW.16), не брешемо нулями). `health_flags` біт-розкладка — One-Home `queen_attest.h` (bit0 CCM-ера · bit1 ring · **bit2/bit3 = legacy-drops/ccm-spoof — wire-видимість cutover-вікна FW.2 (а)**; модель-хелпери `legacy_drops_seen?`/`ccm_spoof_seen?`). Dead-man switch і алерти — [`06_08 §1.3`](06_08_Resilience_and_Failover_Policy).
- **Golden-парність чотирьох реалізацій:** Monocypher (`test_queen_attest.c`) ↔ OpenSSL ↔ RSpec (`unpack_telemetry_worker_attest_spec.rb`) ↔ HIL-симулятор (`lib/hil/queen_simulator.rb`) — байт-у-байт (клас mirror-drift, що вбив DID=0, закритий назавжди).

### 7.1 Reset-cause — чому Королева перевтілилась [FW.59]

RDP замикає SWD за дизайном ([`00_07`](00_07_Action_Plan_Tracker) SEC.2), а флот planetary-remote — тож **дріт є єдиним діагностичним каналом**, і доти він ніс нуль сигналу «чому вузол ребутнув»: тихий crash-loop (битий OTA · HAL-edge · brownout-storm) лишався невидимим, поки дерево не згасне. Recovery в нас був (IWDG/PVD, ARCH.21), reporting — ні.

- **Слот:** старші **три** біти health-flags (bits5..7). ⚠️ Не чотири: bit4 несе ратифіковану бронь `QATT_HFLAG_CANARY` [SEC.21], і `_Static_assert` у `queen_attest.h` тепер робить наїзд на неї помилкою компіляції, а не питанням уважності.
- **Коди (One-Home — `firmware/common/reset_cause.h`, той самий заголовок компілюють прошивка й host-тести):** `0 unknown · 1 power_on · 2 pin · 3 software · 4 iwdg · 5 wwdg · 6 hardfault · 7 low_power`. Вісім кодів вичерпують поле; `OBL` ділить кошик із `software` (свідома переконфігурація). 🔴 **Нуль є сентинелом «не повідомлено», ніколи «холодний старт»** — кожен рядок пульсу, старший за FW.59, несе тут нуль, і будь-яке інше прочитання приписало б усій історії причину, якої ніхто не міряв.
- **Порядок декоду несучий:** внутрішній ресет підтягує ще й `PINRSTF`, тож перевірка PIN раніше за IWDG перетворила б кожен укус пса на «хтось натиснув кнопку». Пінить `test_queen_attest.c`.
- **HardFault не виводиться з `RCC_CSR`:** наш handler виходить через `NVIC_SystemReset`, лишаючи той самий `SFTRSTF`, що й штатний ребут. Розрізняє їх маркер у `.noinit`, узятий **кон'юнктивно** з `SFTRSTF` — несвіжа RAM після холодного старту не може підняти хибний HardFault.
- **Дзеркало масок:** `reset_cause.h` тримає власну копію бітів `RCC_CSR`, щоб лишатись HAL-free; кожна маса пінеться `_Static_assert`-ом проти CMSIS у `queen/main.c`, тобто розсинхрон із кремнієм падає в ARM-джобі, а не на стенді.
- **Споживач:** `GatewayTelemetryLog#reset_cause`/`#reset_fault?` → `GatewayTelemetryWorker` → `EwsAlert` типу `firmware_fault` (vendor-attributable: не A-сет, не `comms_no_ack?`, поза `critical_unmaintained?` — оператор не платить за наш баг). Гілка стоїть **першою** в ланцюзі вердиктів: `coap_fail_count` насичується за аптайм і далі не спадає, тож нижче за нього вона не спрацювала б жодного разу.
- ⚠️ **Дві оголошені стелі.** (1) Consec-лічильник на дріт **не їде** — поле вичерпано кодами; повторюваність читається бекендом із власної історії пульсу (`uptime_min` малий у низці флешів), а швидкий crash-loop, що не встигає флешнути, ловить dead-man switch (`queen_offline`, [`06_08 §1.3`](06_08_Resilience_and_Failover_Policy)) — **ціною того, що ПРИЧИНА такого циклу не доїжджає, доки вузол не стабілізується на один флеш**. (2) Винесення `.noinit` за зону обнулення робить лінкер-скрипт (👤 board-freeze `.ioc`); без нього HardFault чесно деградує у `software`. Деградація не бреше, але вона мовчазна: ARM-джоба збирає glue OBJECT-бібліотекою (compile-only), host-сюїта лінкера не має — **верифікація приладом на стенді, ніколи зеленим CI** (той самий присуд, що для тіла `MX_RTC_Init`, [`00_07`](00_07_Action_Plan_Tracker) FW.49).

---

## 🐦 7а. Device-Event Forward — L1 canary-канал [SEC.21]

Окремий підписаний Queen→Rails канал для рідкісних security-подій вузла (canary-trip). НЕ телеметрія: у CIFO/батч не лягає (stride священний), окремий CoAP PUT `device/event/<uid>`.

**RX-класифікація (LoRa `OnRxDone`-луп).** Після декрипту 16B ECB-кадру Королева впізнає device-event за `Device_Event_Is(decrypted)` (marker `0x57` @ [0] + magic `0x45` @ [10]) — ПЕРЕД CIFO, симетрично до `0x55/0x56` control-опкодів. ⚠️ Класифікація за marker+magic на `decrypted[0]/[10]` несе той самий наявний клас DID-колізії, що `0x55/0x56` (StatusByte `0x45` × DID-старший `0x57` = 1/256) — wire-rev3-адресація зніме її разом з рештою control-опкодів. Упізнаний кадр → cleartext-record `[did:4][code:1][soldier_seq:2]` у міні-ring (4 слоти; переповнення зсуває найстарший — Солдат повторює постріл ×3).

**L1-forward (у `Flush_Cache_To_Rails`, ПІСЛЯ основного flush'у).** Королева підписує ring ВЛАСНИМ EDSK (тег `SLKN-QEVT1`, окремий від QATT2) — рунг **L1** ([`05_02` Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)); конверт `[ver][queen_unix_ts][count][records][sig:64]`, повний wire-дім + «чому L1, а не blind-forward» — [`03_05 §2.2а`](03_05_Hardware_Symmetric_Crypto_and_Security). Гейт на `ed25519_ready` (без EDSK L1 неможливий — той самий гейт, що атестація батча). Best-effort (окремий PUT без retry); очистка ring лише по 2.xx (FW.51-інваріант). Споживач — `DeviceEventWorker` (verify gateway-origin, Rails LoRa-ключа не торкається). **Trust L1-observational: НІКОЛИ не money-path.**

---

## 🔐 8. Шифрування: Режими та Переходи

Per-channel режими (LoRa **AES-128** ECB→CCM · CoAP **AES-256-CBC**) — канон [`03_05 §6`](03_05_Hardware_Symmetric_Crypto_and_Security). Нижче — Queen-специфічний flow перемикання CRYP-режиму (його дім — тут).

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
| `aes_key[4]` | `uint32_t` | 16 B | **AES-128 LoRa ключ** (per-Soldier HKDF; CIFO key-cache) [post-ARCH.42] |
| `coap_key[8]` | `uint32_t` | 32 B | **AES-256 CoAP ключ** Queen (для batch flush до Rails; окремий MX_CRYP re-init під час CoAP-сесії) |
| `forest_cache[50]` | `EdgeCache` | 1150 B | CIFO EdgeCache (50 × 23 байти, після **[E.8]** додано `snr` 1 байт) |
| `binary_batch_buffer[2048]` | `uint8_t` | 2048 B | Бінарний буфер перед шифруванням |
| `batch_attest_buffer[QATT_BUFFER_SIZE]` | `uint8_t static` | 2192 B | **static** конверт батча: [prefix-зона][header][IV][ct][sig] — розкладка One-Home `common/queen_attest.h` (замінив `encrypted_batch_buffer[2064]`, L1 QATT) |
| `ed25519_secret[64]` + `ed25519_pub[32]` | `uint8_t` | 97 B | [L1 QATT] голос Королеви (деривується при boot з EDSK-сім'ї; +`ed25519_ready` 1 B) |
| `pending_ota_bytecode[8192]` | `uint8_t` | 8192 B | RAM-буфер збірки OTA від Rails |
| `at_engine_state` | `AtEngine` | ~168 B | [FW.3] AT-токенайзер (лінія `AT_LINE_MAX` + стан) |
| `uart_rx_buf[512]` + `uart_rx_ring` + `hdma_usart1_rx` | `uint8_t` + `UartRxRing` + DMA handle | ~632 B | **[FW.3]** circular-DMA вухо модема: кільце + вид консьюмера (`queen/uart_rx_ring.h`) + HAL-handle; `uart_rx_wraps` — у скалярах |
| `coap_pdu_buf` | `uint8_t static` | sizeof(batch_attest_buffer)+64 | [FW.56] CoAP PDU (заголовок+Uri-Path+батч; static у `Flush_Cache_To_Rails`) |
| `coap_server_ip[16]` | `char` | 16 B | [FW.56] CDNSGIP-кеш IP сервера (boot; [FW.58] інвалідація після N=3 flush-провалів підряд → re-resolve) |
| `cmd_dedup_ring[16]` | `uint32_t` | 64 B | DJB2 хеші idempotency токенів |
| `g_ota_rr` | `OtaRrTable` | 132 B | **[FW.68]** борг перепитувань `0x55`: `OTA_RR_SLOTS` = 8 слотів × 16 Б (DID · total · бітмап · ознака зайнятості) + курсор витіснення (`queen/ota_rerequest_table.h`, §5.1.3) |
| `g_tx_duty` | `TxDutyLedger` | 60 B | **[FW.61]** журнал ефіру P2P-кадрів: 13 п'ятихвилинних кошиків — стеля робочого циклу ≤ 36 с у будь-яку годину (`queen/tx_duty.h`, §5) |
| `cmd_decrypt_buf[544]` | `uint8_t` | 544 B | Decrypt buffer для CoAP команд/OTA |
| `incoming_lora_payload` (видалено в FW.3) | — | 0 B | Замінено на `lora_rx_ring[16]` (288 B) |
| `lora_rx_ring[16]` | `volatile LoRaRxSlot` | 288 B | **[FW.3 + E.8]** FIFO ring для ISR-пакетів (16 × 18 байтів = payload + rssi + snr) |
| `decrypted_payload[16]` | `uint8_t` | 16 B | Розшифрований пакет |
| `ota_chunk_bitmap` | `uint16_t` | 2 B | Bitmap отриманих OTA-чанків (16 біт) |
| `ota_chunks_received` | `uint16_t` | 2 B | Лічильник отриманих CoAP-чанків |
| `ota_total_expected_chunks` | `uint16_t` | 2 B | Очікуваний total від header |
| `pending_ota_size` | `uint16_t` | 2 B | Реальний зібраний розмір байткоду |
| Scalar variables | misc | ~24 B | `cache_count`, `current_rssi`, `lora_rx_head`, `lora_rx_tail`, `lora_rx_drops`, `ota_is_active`, `current_ota_chunk_idx`, `cmd_dedup_idx`, `cmd_dedup_used` |
| **Разом** | | **~15.6 KB** | З 64 KB SRAM = ~24% використання |

---

## 🔩 10. HAL Периферія Королеви

| Handle | Периферія | Призначення |
|--------|-----------|-------------|
| `huart1` | USART1 | SIM7070G модем (115200 baud) |
| `hsubghz` | SUBGHZ | LoRa трансивер SX1262 (868 MHz) |
| `hcryp` | AES | ECB для LoRa, CBC для CoAP батчів та команд |
| `hrng` | RNG | HRNG для CBC IV та Thundering Herd jitter |
| `hiwdg` | IWDG | Апаратний Watchdog (~26.6 с timeout, auto-reset при зависанні) |
| `hspi1` | SPI1 | Зовнішня NOR Flash **Winbond W25Q32JV** (4 MB) — Overflow Tier CIFO ([ARCH.35](00_07_Action_Plan_Tracker), [`02_05 §7`](02_05_Queen_Hardware_and_Starlink) BOM поз. 16). Піни: `PB3=SCK`, `PB4=MISO`, `PB5=MOSI`, `PA4=CS` (GPIO software-driven). Driver (**planned, ARCH.35 — ще не реалізовано**): `firmware/queen/flash_buffer.c` (`w25q32_write_page` / `w25q32_read` / `w25q32_erase_sector`; **sector-based** ring — NOR стирається цілим 4 KB сектором, деталі та псевдокод у [`02_05 §2.1`](02_05_Queen_Hardware_and_Starlink)). |
| — | GPIO (1-Wire) | Термодатчик батареї **DS18B20+** ([`02_05 §7`](02_05_Queen_Hardware_and_Starlink) поз. 23) — open-drain, pull-up 4.7 кΩ; пін — board-freeze. Pure-транзакція над ops-швом `Ds18b20_Ops` — `firmware/common/ds18b20.h` (host-тест `make -C firmware/test ds18b20`); HAL-половини (опси) ще немає ([HW.16](00_07_Action_Plan_Tracker)). Мікросекундні слоти — без TIM (примітка ↓), кандидат — лічильник циклів DWT CYCCNT; таймінги судить осцилограф на стенді |

**Примітка:** Queen **не має** ADC, TIM, RTC — на відміну від Soldier. HRNG та IWDG ініціалізуються при старті. HRNG де-ініціалізується "on-demand" (Wu-Wei підхід — нульове споживання між використаннями). `hspi1` ініціалізується тільки в момент drain CIFO→Flash (overflow event) і де-ініціалізується одразу після — енерго-нейтральний підхід (W25Q32JV power-down 1 µA, page write ~10 мА × 0.7 мс).

> **Compile-time guard:** при відсутності `hspi1` у `main.h` (CubeMX) функції `w25q32_*` повертають `STATUS_NOT_AVAILABLE`, CIFO залишається в RAM-only режимі, але система не падає. Це SSOT-bridge між картою периферії ([`03_02 §10`](03_02_Queen_Gateway_Firmware)) та overflow-логікою ([`02_05 §2.1`](02_05_Queen_Hardware_and_Starlink) Flash Ring Buffer).

---

## 🧪 11. Тестове Покриття (Host-Based, x86)

```bash
make -C firmware/test queen       # CIFO/OTA/beacon/key-loading suite
make -C firmware/test at_engine   # [FW.3/FW.56] AT-двигун + CoAP PDU + розмова
```

> Лічильники тестів тут не ведемо (drift) — істина = вивід `make`; методологія / гейт / тріаж — канон [`04_06`](04_06_Testing_Guide_and_Coverage). Нижче —
> покриті області та їхні нюанси.

| Модуль | Що покривається |
|--------|-----------------|
| DJB2 Hash | Детермінізм, відомі значення, NUL-термінатор, UUID формат |
| Command Dedup Ring | New/duplicate, ring wrap, eviction, stress |
| CIFO Cache | Insert, dedup, priority eviction (всі 4 bio_status), fallback, edge RSSI, облік лічильника крізь флаш, повний CCM-хвіст і `fmt` при витісненні, порядок ARCH.35-хука — усе на справжньому `queen/cifo_cache.h`, не на копії |
| Batch Packing | 21-байтний формат, ендіанність, RSSI -128, round-trip |
| **[FW.51] Flush Lifecycle** | fail→кеш збережено, success→очищено, retry без втрат, dedup-refresh найсвіжішого |
| **[L1 QATT] Attestation конверт** (`test_queen_attest.c`) | layout-інваріанти (residue/зсуви/префікс), crypto-parity Monocypher↔OpenSSL (pubkey + детермінований підпис байт-у-байт + tamper-fail), end-to-end збірка→backend-розбір, golden-KAT (дзеркало RSpec `unpack_telemetry_worker_attest_spec.rb`; чотири незалежні реалізації: Monocypher ↔ OpenSSL ↔ worker-spec ↔ HIL `queen_simulator` signed-режим, e2e `qatt_hil_e2e_spec.rb`) |
| OTA Chunk Builder | First/last chunk, reassembly, out-of-range index |
| OTA Assembly (CoAP→RAM) | Multi-chunk, duplicate ignore via bitmap, buffer overflow, invalid marker |
| RSSI Clamp | Normal, edge values, overflow proof, int16→int8 truncation demo |
| Пульс QATT-v2 (ARCH.54) | health-блок у header, empty-flush heartbeat, CSQ-читання, golden-парність 4 реалізацій |
| ECB Restoration | CRYP mode state після CBC→ECB transition |
| HRNG IV Generation | All 4 words filled, 16-byte size, power mgmt deinit |
| CBC Command Decrypt | ECB restored після CBC decrypt, sequence correctness |
| **[FW.3] AT-токенайзер** (`test_at_engine.c`) | Фінали OK/ERROR/`+CME ERROR: n`, echo, порожні лінії, truncation довгих URC, анти-кейс «BROKEN» (підстроковий "OK" старої impl), транзакції: URC-до-OK і URC-після-OK, тиша→timeout, шумові лінії |
| **[FW.56] CoAP PDU** (`test_at_engine.c`) | Golden-розкладка CON PUT (опції Uri-Path + extended-length для UID), розбір відповіді **дослівно з SIMCom-ноти** (`60457233…` → ACK 2.05 MID 0x7233), reject 4.xx/RST/чужий MID/куций PDU |
| **[FW.3/FW.56] Повна розмова** (`test_at_engine.c`) | Скриптований SIM7070G: happy path (cid від модема, hex чанками), NEW-fail → SEND не летить, OK-без-NMI ≠ доставка, NMI 4.04 reject, fallback cid=0, lowercase hex, CDNSGIP (URC до/після OK, фейл → слоти живі) |
| **[FW.3] LoRa RX Ring Buffer** | FIFO семантика, переповнення → drop counter, RSSI clamp passthrough, flush-вікно сценарій (ISR-пакети під час розмови з модемом) |
| **[FW.1] Flash Key Loading** | `Load_AES_Key()` magic check, key-not-provisioned → Error_Handler |
| **[FW.20] Time Sync Envelope + Beacon** | CMD_TIME_SYNC strip, beacon plaintext layout, ts=0 guard |
| **[FW.20-S2] Beacon Authoritativeness Flag** | byte 9 bit 7 (`BEACON_AUTH_FLAG=0x80`) — Королева транслює `byte9 = 0x82` (auth=1 \| TTL=2). Relay-маяки Провідників — auth=0, TTL−1. Layout `[0x9C][ts_be:4][reserved:0×4][AUTH_FLAG\|TTL][magic 'B'][padding:0×5]` |
| **[FW.27-B] Magic Re-Request Handler** | Bitmap accept/dedup, total mismatch, no-active-OTA |
| **[FW.23] Seal Trailer Relay** | 7 segs storage (`ota_seal_wire.h`), seg_idx>7 reject, marker mismatch, same-segment overwrite; FW.52б late-trailer resurrect fires on the 7th |
| **[FW.20-Q2 · FW.17] Soldier Cmd Queue** (`test_soldier_cmd_queue.c`) | Структурна перевірка на golden downlink-кадрах (чужі опкоди й довжини), адресність за DID, порядок за DLFC із переходом 0xFFFF→0x0000, бюджет спроб у ціль, освіження дубліката, жертва — найдавніше поставлений, байт-у-байт прохід кадру Rails → Солдат |

**Не покрито host-тестами (справжній HW-residual):**
- verbatim-звірка граматики SIM7070-ноти V1.03 + реальні таймінги/URC реального модему (bench-runbook)
- Повна async UART DMA flush — наступна ітерація FW.3 (вимагає DMA controller hardware)
- Реальні LTE-M / Starlink DTC мережеві помилки (скриптовані ERROR/+CME/тиша — покриті)
