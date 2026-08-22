# 03_02: Прошивка Шлюзу Королеви (LoRa RX → Dedup → CIFO → SIM7070G TX)

---

## 🎯 Мета

Зафіксувати повний алгоритм роботи вузла **Queen** (шлюз-агрегатор на базі STM32WLE5JC + модем SIM7070G) — від прийому зашифрованого LoRa-пакета від Солдата до відправки бінарного батча на Rails-бекенд через CoAP/UDP. Документ визначає механізм дедуплікації пакетів (CIFO EdgeCache), алгоритм евікції, логіку OTA-бродкасту та повний цикл взаємодії з GSM-модемом.

> **Критична залежність:** Королева є єдиною точкою виходу ZK-пакетів у Proof of Growth Pipeline (05_02). Втрата пакетів телеметрії на рівні Королеви → ZK-proof не формується → мінтинг SCC блокується → токеноміка руйнується.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — C-код шлюзу написаний, host-based тести зелені (`make -C firmware/test queen`). Відкрите: FW.3 silicon-bench (AT/UART DMA RX закрито host-рівнем) → [`00_07 §03a`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Soldier lifecycle, binary packet, DID provisioning, RTC map |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Hardware Queen, SIM7070G, Starlink/Helium |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | AES режими, ключі (§3.1), HRNG IV |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `UnpackTelemetryWorker` (батч [IV:16][CBC ciphertext]) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Втрата пакетів Queen → ZK-proof/мінтинг |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): FW.3 silicon-bench (AT/UART DMA закрито host-рівнем), FW.27 Design A ACK-agg (gated ARCH.26) |

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
║    │    ├── Health-блок у QATT-v2 header (ARCH.54)          │          ║
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

| Константа | Значення | Файл | Призначення |
|-----------|----------|------|-------------|
| `LORA_RX_INFINITE` | `0xFFFFFF` | main.c | Нескінченний таймаут RX |
| `FLUSH_INTERVAL_MS` | `3 600 000` | main.c | Інтервал flush (1 год.) |
| `FLUSH_JITTER_MAX_MS` | `60 000` | main.c | Макс. jitter (60 сек) |
| `RNG_FALLBACK_XOR_MASK` | `0xA5A5A5A5UL` | main.c | XOR-маска при відмові HRNG (jitter) |
| `FLUSH_HEADROOM` | `5` | main.c | Слоти до примусового flush |
| `QUEEN_HEALTH_GP_MAX` | `31` | main.c | Макс. growth_points для sentinel (5-біт wire — дзеркало [FW.29-PACK], дім формату — [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA)) |
| `OTA_MAX_CHUNKS` | `16` | main.c | Макс. CoAP-чанків (bitmap 16 біт) |
| `CACHE_MAX_ENTRIES` | `50` | main.c | Місткість CIFO EdgeCache |
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
| `AT_INIT_BUDGET_MS` | `2000` | main.c | [FW.3] Бюджет однієї init-команди (ATE0/AT/CNMP/CPSMS/CEDRXS) |
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

> **Роль у вирішенні Проблеми Рандеву:** Королева є **єдиним always-on listener** у мережі. Її SX1262 завжди в `Radio.Rx(LORA_RX_INFINITE)` — нескінченний таймаут прийому. Це вирішує фундаментальну Проблему Рандеву (Rendezvous Problem) для всіх вузлів у прямій видимості (150–200 м): Солдат може "вистрілити" пакетом у будь-яку мілісекунду — Королева завжди зловить. Це можливо завдяки зовнішньому живленню (сонячна панель / акумулятор), на відміну від Солдатів з EBFC біобатарейкою. Для вузлів за межами прямої видимості Queen потрібні Синхронні Вікна (TDMA, L2 — 🟡 host-half: розкладка в маяку INERT до bench, §5а.2а) та CAD (L3 — 🟡 host-half: Soldier-side нюх/преамбула, Queen-wire не додає) ([ARCH.26](00_07_Action_Plan_Tracker), деталі — [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA)).

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
| Розмір пакета | 16 байт | Повний AES-блок (block size = 128 bit; key size = AES-128 post-ARCH.42 LoRa) |
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

> **[FW.2, INERT за `FW2_CCM_ENABLED`]** У CCM-ері слот несе `payload[24]` (опаковий air-хвіст — Королева НЕ розшифровує, інверсія довіри [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)) + `fmt`-тег (`EDGE_FMT_ECB16|CCM24`); `len`-тегований RX-ринг приймає 16|28. bio_status для евікції видно лише в ECB16-слотах (у CCM ті байти — шифртекст; офсет-колізія — firmware-скіл gotcha #7); CCM-записи евіктяться за RSSI/SNR — свідома стеля сліпого кур'єра, довгий лік = ARCH.35-ринг. RAM-ціна фліпа — леджер [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security) (One-Home чисел).

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
   for i in 0..3:
     if HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK:
       batch_iv[i] = coap_fallback_iv_word(i, tick, uid_hash,
                                           queen_unix_ts, coap_flush_seq)
       ← [HRNG-IV harden] pure-деривація з coap_iv.h: унікальність across
         device (uid_hash) / reboot (queen_unix_ts) / flush (coap_flush_seq);
         host-tested у firmware/test/test_encryption.c
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
| CBC IV generation (batch) | `coap_fallback_iv_word(i, tick, uid_hash, queen_unix_ts, coap_flush_seq)` — pure, дім: `firmware/queen/coap_iv.h` | per-word, 4 різні слова IV | [HRNG-IV harden] унікальність across device/reboot/flush; передбачуваний, але без chosen-plaintext вектора (§HRNG Fallback у [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)); host-тести `test_encryption.c` |
| Jitter regeneration після flush | `HAL_GetTick() ^ RNG_FALLBACK_XOR_MASK` | `0xA5A5A5A5UL` (одна константа) | Один tick, одна маска — простий jitter, криптостійкість не потрібна |
| Startup jitter (один раз) | `HAL_GetTick()` (без XOR!) | без маски — рядок 228 | Startup: tick вже унікальний бо залежить від часу включення живлення; жодна маска не додає ентропії у цьому контексті; jitter — не криптографічна операція |

> **Примітка:** Всі три fallback є слабкими при масовому blackout (стосується лише CoAP CBC IV). Для jitter безпека не потрібна. Різниця в масках — це не помилка, а різні вимоги до ентропії.

### Крок 3: Відновлення ECB

```c
// [FIX: CRITICAL — ECB Restoration]
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);
// Без цього — всі наступні LoRa decrypt дають сміття
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

| AT-команда | Бюджет | Призначення |
|------------|--------|-------------|
| `ATE0` | `AT_INIT_BUDGET_MS` | Вимкнути ехо (токенайзер його переживає, але ефір чистіший) |
| `AT` | `AT_INIT_BUDGET_MS` | Перевірка зв'язку з модемом |
| `AT+CNMP=38` | `AT_INIT_BUDGET_MS` | Режим LTE-M only (відключає NB-IoT) |
| `AT+CPSMS=…` / `AT+CEDRXS=…` | `AT_INIT_BUDGET_MS` | PSM/eDRX (деталі 3GPP — коментарі в `main.c`) |

Провал init не фатальний: модем міг ще прокидатись — flush-розмова повторить
усе зі свіжим бюджетом.

### CoAP Flush Sequence (кожен flush)

```
0. [FW.16→FW.3] Restore_ECB_Mode() — ОДРАЗУ після CBC-encrypt батча,
   ще ДО розмови з модемом: вікно чужого CRYP-режиму = нуль.

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
downlink** одразу після `send_success`: модем теплий, IP резольвлений,
NAT-pinhole свіжий — єдине живе вікно. Реалізація — `Queen_Poll_Downlink`
(`main.c`, викликається з хвоста `Flush_Cache_To_Rails`; це **перший
call-site** усього inbound-тракту — доти `Handle_CoAP_Command` був мертвим
кодом):

```
1. Дренаж черги (≤ QUEEN_POLL_MAX_PER_FLUSH = 3 повідомлень):
   GET poll/<uid>?fw=<delivered_id>  → Sim7070_Udp_Fetch (сирий CA*-тракт)
     → Coap_Reply_Extract_Payload (2.05 + наш MID) → конверт
     → Handle_CoAP_Command: 0 = time-only «черга порожня» → стоп;
       1 = контент (CMD / 0x9E-каркас / 0x9F OTA-hint) → наступний poll.
   ?fw= несе повністю зібраний contract-id (0 після ребуту) — Rails
   звіряє з gateways.pending_firmware_id = спостережене підтвердження
   доставки (Downlink::PendingQueueService, 04_02).

2. OTA-фетч за hint'ом [0x9F][fw_id:4 BE][total:2 BE]
   (≤ QUEEN_OTA_FETCH_PER_FLUSH = 4 чанків/флаш — IWDG-бюджет):
   GET ota/<uid>?v=<fw_id>&ch=<n> → повний конверт із чанком (≤560 Б,
   влазить лише в CARECV-ногу) → Handle_CoAP_Command → 0x99/0x9B гілки
   (bitmap/трейлер незмінні). Курсор послідовний, Queen-driven — Rails
   прогресу не веде; ребут → fw=0 → повторний hint → безпечний
   idempotent re-fetch (bitmap дедуплікує). Пакети вичерпано + збірка
   ожила (ota_is_active) → delivered_id = fw_id, hint згасне.
```

Кожна відповідь — той самий конверт `[IV:16][AES-256-CBC KEYC]` з
`[0x9C][ts:4]` усередині (`CoapEncryption`) → **кожен poll = RTC-sync
Королеви**, навіть порожній (time-only, 32 Б). Дубль-MID (мережеве дублювання
датаграми) Rails віддає байт-ідентично (MID-кеш `CoapGate`) — ⚠️ **не** плутати
з CON-ретрансмітом: його в poll-тракті немає ([`00_07` FW.63](00_07_Action_Plan_Tracker)).
Bench-residual: жива
poll-розмова обома маршрутами + verbatim `+CADATAIND`/`CARECV`-поведінка —
[`00_07` FW.60](00_07_Action_Plan_Tracker).

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

> ✅ **[FW.60] Inbound-тракт WIRED (2026-07-12):** `Handle_CoAP_Command` живе — перший call-site = poll-цикл `Queen_Poll_Downlink` (§4а; push із Rails фізично не долітав — CGNAT). OTA-чанки прибувають як відповіді Queen-driven fetch'а `GET ota/<uid>?v=&ch=` (сира CARECV-нога — конверт ≤560 Б у NMI-лінію не влазить), кампанію анонсує hint `[0x9F]` у poll-відповіді. Стеля збірки 16×512 = 8 КБ (Guard 3) тепер **enforce'иться Rails-боком ДО burn** (`Ota::DeploymentDispatcherService` oversized-гейт — [`04_02`](04_02_Business_Logic_and_Services)). Bench-residual (жива розмова + verbatim модем-поведінка) — [`00_07` FW.60](00_07_Action_Plan_Tracker).

**Два типи OTA-чанків — важливо не плутати:**
| Тип | Джерело | Розмір payload | Макс чанків | Ліміт |
|-----|---------|----------------|-------------|-------|
| **CoAP downlink** (Rails → Queen) | `Handle_CoAP_Command` ← Queen-driven fetch §4а (CARECV-нога, [FW.60]) | ≤512 байт | 16 | `OTA_MAX_CHUNKS` (bitmap; Rails-дзеркало = oversized-гейт dispatcher'а) |
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

─── Нова кампанія (idle-стан) ────────────────────────────────────────────
  if (ota_chunk_bitmap == 0 && ota_chunks_received == 0):
    pending_ota_size = 0   ← [AUDIT-2026-06-06] менша нова прошивка не
                              успадковує хвости старої (анти-«химера»)

─── Dedup via bitmap ─────────────────────────────────────────────────────
  chunk_bit = 1U << chunk_index
  if (ota_chunk_bitmap & chunk_bit) → return  (дублікат — ігноруємо)
  ota_chunk_bitmap |= chunk_bit               (маркуємо як отриманий)

─── Зберігаємо в RAM-буфер ───────────────────────────────────────────────
  memcpy(pending_ota_bytecode + offset, &cmd_decrypt_buf[OTA_COAP_HEADER_SIZE=7], payload_len)
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

**Статус:** ✅ Реалізовано у `firmware/soldier/main.c` (`Build_OTA_ReRequest_Payload`, OTA_REQ_MARKER 0x55; тиша = `OTA_REREQUEST_SILENT_WAKEUPS=10` **тихих пробуджень з відкритим вухом** ≈ 5 хв wall при циклі 26-32 с — стара tick-різниця була мертва у STOP2 і запізнювала зойк у ~6-15×; виправлено 2026-06-11, семантика навіть чесніша за wall-clock: лічиться тиша лише коли вухо справді слухало) + `firmware/queen/main.c` (`Process_LoRa_RX` REREQUEST handler перед CIFO/CoAP, `djb2_hash_bytes` length-strict NUL-safe replay-protection через `cmd_dedup_ring`). Host-тести (Soldier bitmap + silence-counter + Queen) у `firmware/test/test_soldier_logic.c` + `test_queen_logic.c`. Опціонально (поза цим циклом): зберегти останній OTA SHA-256 у Queen Flash для cross-check на re-request — поки не реалізовано, після `ota_is_active=0` буфер `pending_ota_bytecode` може бути перезаписаний наступним CoAP-push'ем, тоді re-request не обслуговується (Solider має чекати наступного Rails-driven OTA cycle).

**Ідея:** Soldier при `ota_chunks_received < ota_total_chunks` після таймауту (наприклад, **5 хвилин без нових chunks**) ініціює uplink-запит конкретних missing chunks через звичайний LoRa TX → Queen приймає, ретранслює лише ці chunks.

**Soldier-side state machine (новий):**

```c
// firmware/soldier/main.c — додатковий стан OTA
uint32_t ota_last_chunk_rx_tick = 0;   // 0 = ще не чули OTA (маркер «вже чули»)
uint8_t  ota_silent_wakeups     = 0;   // тихих пробуджень з відкритим вухом
#define OTA_REREQUEST_SILENT_WAKEUPS 10 // ≈5 хв wall при циклі 26-32 с
                                        // (tick мертвий у STOP2 — лічимо пробудження)
#define REREQUEST_MARKER          0x55  // Окремий маркер uplink-запиту

// У Phase 4.5 після обробки RX (новий чанк у RX-гілці скидає лічильник у 0):
if (ota_total_chunks > 0 &&
    ota_chunks_received < ota_total_chunks &&
    ota_last_chunk_rx_tick != 0) {
    if (ota_silent_wakeups < 255) ota_silent_wakeups++;
    if (ota_silent_wakeups >= OTA_REREQUEST_SILENT_WAKEUPS) {
        // Збираємо missing-bitmap і шлемо запит; лічильник у нуль —
        // Королеві стільки ж тихих пробуджень на ретрансляцію
        Send_OTA_ReRequest(ota_chunk_received, ota_total_chunks);
    }
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

    // AES-128-ECB шифрування + TX (як стандартний uplink-пакет, post-ARCH.42)
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
| Той самий chunk після сну (anti-replay) | `test_ota_stop2_simulation_duplicate_after_sleep_still_rejected` | Counter не подвоюється при повторному reflex shot Королеви |
| `total_chunks=0` malformed packet | `test_ota_total_chunks_zero_rejected` | Defence-in-depth: degenerate completion → CRC32 fail → no Flash write (not crash) |
| HMAC trailer state cross-cycle | `test_hmac_trailer_state_survives_simulated_stop2_between_segments` | bitmask `ota_hmac_segments_received` OR-агрегується через STOP2 між сегментами 1/3/2 |
| HMAC trailer idempotent overwrite | `test_hmac_trailer_duplicate_segment_overwrites_idempotently` | Дубль того самого сегменту не корумпує `received_hmac_tag[]` |

> **Cross-ref:** [`00_07`](00_07_Action_Plan_Tracker) FW.27 — повний контекст; [`04_06 §B.2`](04_06_Testing_Guide_and_Coverage) — тест-список.

#### 5.1.6 [FW.52] OTA throughput + `ota_is_active` lifetime — рішення прийнято

> **Статус:** ✅ обидва рішення прийнято founder 2026-06-12: **(а) повільний OTA прийнято як свідомий energy-first ADR** (п.1 нижче — обґрунтування); **(б) мертве вікно при запізнілій печатці виявилось reliability-багом і ВИПРАВЛЕНО** (п.2). Residual — лише bench ([`00_07`](00_07_Action_Plan_Tracker) FW.52).

Один повний reflex-shot OTA-цикл (§5) **повільний** (порядок днів-тижнів):

1. **1 RX-пакет за пробудження (Soldier) — прийнято by-design [ADR, founder 2026-06-12].** RX-вікно обробляє максимум один пакет за wake-цикл — усі гілки (`firmware/soldier/main.c`: сценарій OTA `0x99`, mesh-естафета, HMAC-trailer `0x9B`) завершуються `break` перед `Radio.Sleep()`. Отже OTA на `N` байтів = `⌈N/11⌉` reflex-чанків = стільки ж пробуджень (1024 B → ~94). **Чому прийнято, а не «пофіксено»:** (i) після E.63 `delta_t` — це економіка дерева: зайве RX-слухання → довший перезаряд → менше growth_points; (ii) `break` після одного пакета — анти-vampire захист (флуд `0x99`-чанками не тримає Солдата з відкритим вухом); (iii) OTA рідкісний, а швидкий security-важіль (ротація ключа `0x9E`) — однопакетний downlink поза OTA-збіркою. Vcap-гейтований re-arm RX лишається опцією перегляду **після** bench-даних E_cycle/recharge (FW.50, RUNBOOK 3.2/3.3) — поріг гейта без цих кривих був би здогадкою.
2. **✅ (2026-06-12) Запізніла печатка воскрешає вікно (Queen) — було багом, виправлено.** Печатка (4 × `0x9B`) їде окремими CoAP-chunk'ами, порядок відносно тіла не гарантований. Коли тіло відлунало без зібраного трейлера, Queen слушно гасить `ota_is_active` ([PLAN 2.5] — не проповідувати в пустоту), але раніше запізнілий трейлер лягав у пам'ять **мовчки**: тіло в RAM ціле, печатка зібрана, Солдати кричать re-request — а вікно мертве до повторного повного Rails-push. Тепер `0x9B`-хендлер при довершенні трейлера (повна маска + тіло зібране й збірка idle + вікно згасле) **воскрешає вікно одразу у фазу печатки** — предикат `Ota_Late_Trailer_Resurrects` (`firmware/queen/ota_window.h`, pure; host-тести `test_queen_logic.c`), мутація стану в `main.c`. Анти-проповідь збережена: якщо трейлер так і не приїде, вікно лишається закритим (recovery = Rails re-push, як і було). Lifetime-обмеження `pending_ota_bytecode` (§5.1.3 — перезапис наступним push) незмінне.
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
   │  ③ Drift-monitor + panic sync request `[0x56][DID:4][secs:4][TTL][magic 'S']`     ✅ FW.20-S2 (2/5)
   │     — hot-path wired обабіч ФАЗИ 4: cold-boot hello (ARCH.41-C, 0x56 ЗАМІСТЬ
   │       телеметрії у grace-вікні) + warm-зойк watchdog'а ПОВЕРХ телеметрії
   │       (cooldown ≈1 год; Queen у відповідь перемотує такт маяка → re-sync тим
   │       самим пробудженням). Hook, не пасивна надія: вухо Фази 4.5 (600 мс/цикл)
   │       ловить 15-хв маяк у середньому ~раз на 12 год — впритул до порога
   │       TIME_SYNC_DRIFT_THRESHOLD_WAKEUPS, а квазі-резонанс такту з циклом
   │       може давати довші сухі смуги
   │  ④ Per-hop drift compensation + anti-storm журнал поколінь (mesh-relay)           ✅ FW.20-S2 (3/5 + 4/5)
   │     — `Soldier_Try_Relay_Time_Beacon` вшито у RX-гілку Сценарію 0 за гейтом
   │       `FW20_MESH_RELAY_ENABLED` (фліп = bench Flash-KV HAL, як FW.17/FW.8/FW.2);
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
   ▼
Soldier — gossip-uplift (3-hop reach)
```

### 5а.2 Wire-формати

| Опкод | Маркер | Напрямок | Формат | Розмір | Cross-ref |
|-------|--------|----------|--------|--------|-----------|
| CMD_TIME_SYNC envelope | `0x9C` | Rails→Queen (CoAP, доставка = poll §4а [FW.60]) | `[0x9C][unix_ts_be:4][inner_payload]` | 5+N байт | FW.20 §1, `app/workers/concerns/coap_encryption.rb` |
| Time Beacon | `0x9C` + magic `'B'` | Queen→Soldier (LoRa ECB) | `[0x9C][ts:4][TDMA:4 →§5а.2а][AUTH\|TTL][magic 'B'][PAD:5]` | 16 байт | FW.20 §2 |
| SYNC_REQUEST | `0x56` + magic `'S'` | Soldier→Queen (LoRa ECB) | `[0x56][DID:4][secs_since_sync:4][PANIC_TTL][magic 'S' = 0x53][PAD:5]` | 16 байт | FW.20-S2 §3, `firmware/soldier/main.c:Build_Time_Sync_Request_Payload` |
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
- **Кеш Солдата — RAM-only derived state** (як `soldier_unix_ts`): гине з SRAM у RTC-only STOP2 / VBAT-loss, відновлюється наступним маяком ≤ 15 хв → **нуль нових RTC DR / Flash-KV ключів** ([`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA) бюджет повний). Провідник ретранслює байти 5..8 as-is (relay-тест тримає транзит).
- **Стеля точності (позначена):** маяк несе цілі секунди → фазова похибка вузла ≈ ±1 с (округлення + encrypt/airtime); слоти коротші за ~2 с розкидають популяцію **статистично** (фазові групи + FW.10 jitter), не ізолюють детерміновано. Шлях апгрейду: `ts_frac` (1/256 с) у **байті 11** (перший PAD) → ±4 мс → 100-мс слоти; байт зарезервовано, не реалізовано. **Sync-бюджет WUT-влучання = ±10 мс** (ціль детермінованих слотів; gossip-fallback ±128 с придатний лише для `epoch_day`, не TDMA): типовий LSE ±20 ppm набігає ~±18 мс за 15-хв такт маяка → чи вкладається реальний кварц у бюджет, вирішує bench `04_lse_drift.py` ([`00_07` — ARCH.26](00_07_Action_Plan_Tracker) — коротший такт / кращий кварц / ширший guard-інтервал).
- **Queen-константи** (`queen/main.c`): `TDMA_PERIOD_MIN 15` (= такт маяка) · `TDMA_WINDOW_100MS 20` · `TDMA_SLOT_COUNT 4` · `TDMA_PHASE_4S 0`.

### 5а.3 Опкод-карта (SSOT)

> **Канонічна таблиця опкодів LoRa/CoAP** живе в [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA#45а-downlink-opcode-map--canonical-ssot-doc4). Узагальнено для Time Sync контексту:

| Опкод | Призначення | Канал | Магія | Статус |
|-------|------------|-------|-------|--------|
| `0x55` | OTA_REQ_MARKER (FW.27-B Magic Re-Request) | Soldier→Queen LoRa | byte 10 не визначений | ✅ |
| `0x56` | SYNC_REQ_MARKER (FW.20-S2 panic sync) | Soldier→Queen LoRa | byte 10 = `'S'` (0x53) | ✅ |
| `0x99` | OTA_MARKER (bytecode chunk) | bidirectional | — | ✅ (Rails→Queen лег = poll-fetch §4а [FW.60]) |
| `0x9A` | CMD_SET_LORENZ_THRESHOLDS (FW.8) | Rails→Queen→Soldier | freeze-contract | 🟡 deferred TRL-7 |
| `0x9B` | HMAC_TRAILER_MARKER (FW.23 OTA dual-gate) | Rails→Queen→Soldier | seg_idx 1..3 печатка + 4 version | ✅ |
| `0x9C` | CMD_TIME_SYNC envelope / Time Beacon (FW.20) | Rails→Queen / Queen→Soldier | byte 10 = `'B'` (0x42) для LoRa beacon'а | ✅ (Rails-лег = кожна poll-відповідь §4а) |
| `0x9F` | OTA_FETCH_HINT (FW.60 — анонс кампанії у poll-відповіді) | Rails→Queen | `[0x9F][fw_id:4 BE][total:2 BE]` | ✅ |
| `0x9D` | CMD_SET_AUDIO_THRESHOLDS (FW.18) | Rails→Queen→Soldier | CRC16 | ✅ |
| `0x9E` | CMD_ROTATE_KEY (FW.17, реле — §5б) | Rails→Queen→Soldier | CRC16 | 🟡 gated (FW.2 CCM) |

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

- ✅ (2026-06-12) **Anti-storm журнал поколінь** — реалізовано: `common/beacon_dedup.h` поверх Flash-KV ключа `0x20` (реєстр — [`03_01 §2.3 ARCH.28`](03_01_Firmware_Lifecycle_and_DMA#23-overflow-strategy-flash-based-kv-store-arch28)); wiring у `soldier/main.c` за гейтом `FW20_MESH_RELAY_ENABLED=0` — residual = чистий bench-фліп (верифікація Flash-KV HAL, спільна з FW.17/FW.8/FW.2)
- ✅ (2026-06-12) **Queen beacon TTL=2** (`BEACON_BYTE9_AUTHORITATIVE = 0x82`) — канонічна умова «перемикається коли реалізуємо anti-storm» виконана. Глибше TTL (3+ хопи) — рішення founder'а про airtime: журнал робить його шторм-безпечним (TTL обмежує лише глибину, обсяг ≤1 ретрансляція/покоління/Провідник), фліп = одна константа
- **Hot-path виклик** `Soldier_Pack_Gossip_Ts_Byte` у Phase 2 normal-telemetry pack + RX-обробник для прийому. (Дім у CCM-кадрі вже зарезервовано — AAD byte 4, wire-rev2: gossip переживає per-Soldier ключі; CCM-фліп вшиває pack-половину автоматично через параметр `Soldier_Build_CCM_LoRa_Packet`)
- **Drift compensation** при ΔT = ±60°C lab-вимірювання (потребує термокамери, відсутня @ TRL-6)

> **Закриття 00_07:** після цього хабу записи `FW.20`, `FW.20-S2 (1/5..5/5)` у [`00_07 §03a`](00_07_Action_Plan_Tracker#03a--firmware) шорткозамкнено — лишилося лише посилання сюди для аудиту прогресу.

---

## 📨 5б. Soldier Command Relay (FW.20-Q2) — черга рефлекторних пострілів

**Статус:** ✅ написано (2026-06-12), інертне за гейтом `FW20_Q2_CMD_RELAY_ENABLED 0` — фліп разом із FW.2 CCM та Soldier-гілками (`FW17_RATCHET_ENABLED` / `FW8_PARSER_ENABLED`).

Королева-гонець для Soldier-bound команд **спільного каркаса** `[маркер][len_le:2][body][crc16_le:2]` (зараз: `0x9A` CMD_SET_THRESHOLDS, `0x9E` CMD_ROTATE_KEY — повна опкод-карта [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA#45а-downlink-opcode-map--canonical-ssot-doc4)). Дім коду: `firmware/queen/soldier_cmd_queue.h` (pure) + глю в `queen/main.c`; host-тести `firmware/test/test_soldier_cmd_queue.c` (`make -C firmware/test cmd_queue`).

**Шлях слова:** `Handle_CoAP_Command` (після зрізання 0x9C-конверта) маршрутизує кадр за маркером → валідатор каркаса (len + CRC-16/CCITT-FALSE — дзеркало guard'ів Солдата: битий у LTE-транзиті біт помирає на Королеві, не з'їдаючи ефір) → черга 16-байтних plaintext-блоків (zero-pad до одного LoRa AES-блоку) → **рефлекторний постріл** услід за кожним прийнятим uplink'ом (ECB-encrypt поточним LoRa-ключем + `Radio.Send`, перед OTA-чанком — команда першою).

**Чому рефлекс, а не маяковий слот (ADR):** Солдат слухає ефір лише ~500 мс після ВЛАСНОГО TX — постріл услід за його голосом є єдиним гарантовано чутим вікном; періодичний маяк летить у переважно глухий ліс. Первісний ескіз «спільна з beacon TX черга» відкинуто.

**Бюджет замість ACK:** на LoRa-рівні ACK нема (справжній per-device ACK `0x9E` — Dual-Key Grace на бекенді, [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)); кадр живе `SOLDIER_CMD_SHOT_BUDGET` пострілів (покриває повний оберт uplink'ів кластера з запасом) і згасає. Повтори нешкідливі за конструкцією: `0x9E` — forward-only ratchet (replay → відмова), `0x9A` — ідемпотентний; після re-key Солдата старі постріли дешифруються в сміття → CRC-відмова. Дедуп (Sidekiq retry / подвійний dispatch) — ідентичний блок лише освіжає бюджет; переповнення витісняє слот із найменшим лишком.

**Активаційні gates (уточнено 2026-07-03 — дім [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)):** (i) ECB-downlink без MAC не сміє командувати ротацією — і **CCM-фліп цього НЕ знімає** (FW.2 автентифікує лише uplink; команди лишаються 16B ECB на cluster-KEYB — двоключова модель [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security), а НЕ per-device downlink); (ii) командний broadcast чують **усі** Солдати, а кадр `0x9E` DID-таргета не несе → сусід-слухач ротувався б у розсинхрон — DID-поле в кадр = передумова активації; (iii) колишню несумісність «ротація глушить downlink вузла» знято двоключовою (ратчет ротує лише session KEYL). Глибина черги під cluster-wide ротацію — частина активаційного дизайну.

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
> закриває → [`00_07` FW.63](00_07_Action_Plan_Tracker).

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

- **Джерела в `main.c`:** `g_uptime_minutes` (sw-extended лічильник — `HAL_GetTick` вмирає на 49.7-й добі), `cache_count`, `lora_rx_drops` (сатурація u8), `g_coap_fail_count` (всі-retry-впали + DNS-fail), `g_last_csq` (`Sim7070_Read_Csq` перед flush-розмовою; 0xFF до першого успіху → бекенд пише NULL), `flags` (CCM-ера / ARCH.35-ринг).
- **Empty-flush heartbeat:** порожній CIFO при таймерному тику → конверт без записів (`header+IV+sig`, ~97 Б LTE) — пульс за тихої години; гейт `ed25519_ready` (legacy-плата без сім'ї не палить DC даремно). Backend legально скипає unpack (ct=0 — лише під конвертом).
- **Masking-attack закритий конструкцією:** health без валідного Ed25519 не існує (`UnpackTelemetryWorker` енкʼює пульс ЛИШЕ з `:attested`-гілки).
- **Маршрутизація на сервері:** `enqueue_envelope_health` → `GatewayTelemetryWorker` (черга uplink) → `GatewayTelemetryLog` (нові колонки `uptime_min/cifo_fill/lora_rx_drops/coap_fail_count/health_flags`; `voltage_mv`/`temperature_c` — nullable до ADC-тракту, не брешемо нулями). `health_flags` біт-розкладка — One-Home `queen_attest.h` (bit0 CCM-ера · bit1 ring · **bit2/bit3 = legacy-drops/ccm-spoof — wire-видимість cutover-вікна FW.2 (а)**; модель-хелпери `legacy_drops_seen?`/`ccm_spoof_seen?`). Dead-man switch і алерти — [`06_08 §1.3`](06_08_Resilience_and_Failover_Policy).
- **Golden-парність чотирьох реалізацій:** Monocypher (`test_queen_attest.c`) ↔ OpenSSL ↔ RSpec (`unpack_telemetry_worker_attest_spec.rb`) ↔ HIL-симулятор (`lib/hil/queen_simulator.rb`) — байт-у-байт (клас mirror-drift, що вбив DID=0, закритий назавжди).

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
| `cmd_decrypt_buf[544]` | `uint8_t` | 544 B | Decrypt buffer для CoAP команд/OTA |
| `incoming_lora_payload` (видалено в FW.3) | — | 0 B | Замінено на `lora_rx_ring[16]` (288 B) |
| `lora_rx_ring[16]` | `volatile LoRaRxSlot` | 288 B | **[FW.3 + E.8]** FIFO ring для ISR-пакетів (16 × 18 байтів = payload + rssi + snr) |
| `decrypted_payload[16]` | `uint8_t` | 16 B | Розшифрований пакет |
| `ota_chunk_bitmap` | `uint16_t` | 2 B | Bitmap отриманих OTA-чанків (16 біт) |
| `ota_chunks_received` | `uint16_t` | 2 B | Лічильник отриманих CoAP-чанків |
| `ota_total_expected_chunks` | `uint16_t` | 2 B | Очікуваний total від header |
| `pending_ota_size` | `uint16_t` | 2 B | Реальний зібраний розмір байткоду |
| Scalar variables | misc | ~24 B | `cache_count`, `current_rssi`, `lora_rx_head`, `lora_rx_tail`, `lora_rx_drops`, `ota_is_active`, `current_ota_chunk_idx`, `cmd_dedup_idx`, `cmd_dedup_used` |
| **Разом** | | **~15.5 KB** | З 64 KB SRAM = ~24% використання |

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
| CIFO Cache | Insert, dedup, priority eviction (всі 4 bio_status), fallback, edge RSSI |
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
| **[FW.23] HMAC Trailer Relay** | 3 segs storage, seg_idx>3 reject, marker mismatch |
| **[FW.20-Q2] Soldier Cmd Queue** (`test_soldier_cmd_queue.c`) | Валідатор каркаса (golden 0x9E, кадр 0x9A, чужі маркери, битий len/CRC), zero-pad до AES-блоку, shot-бюджет до згасання, дедуп-refresh, round-robin без голодування, евікція найбіднішого слота, інтеграція блоку з черги крізь `Key_Ratchet_Parse_Cmd` |

**Не покрито host-тестами (справжній HW-residual):**
- verbatim-звірка граматики SIM7070-ноти V1.03 + реальні таймінги/URC реального модему (bench-runbook)
- Повна async UART DMA flush — наступна ітерація FW.3 (вимагає DMA controller hardware)
- Реальні LTE-M / Starlink DTC мережеві помилки (скриптовані ERROR/+CME/тиша — покриті)
