# 03_02: Queen Gateway Firmware (LoRa RX → Dedup → CIFO → SIM7070G TX)

**Модуль:** 03_02 — Queen Gateway Firmware (STM32WLE5JC + SIM7070G)
**Пов'язані модулі:** [03_01 Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) · [03_05 Hardware AES256 and Security](03_05_Hardware_AES256_and_Security) · [04_02 Business Logic and Services](04_02_Business_Logic_and_Services) · [05_02 Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline)
**Поточний TRL:** 6 (C-код шлюзу написаний, 59 queen-specific host-based тестів проходять, але SSOT взаємодії з мережею відсутня)
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
| **HRNG Fallback → IV Reuse (CBC)** | 🔴 BLOCKER (при blackout IV≈0, IV reuse attack) |
| **OTA Broadcast Infinite Loop** | 🔴 BLOCKER (`ota_is_active` ніколи не скидається до 0) |
| **Host-based Tests (59 queen-specific)** | ✅ Всі проходять (`make -C firmware/test queen`) |

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

### 🔴 BLOCKER-2: AT Command Blocking — Queen сліпа ~25 секунд під час flush

**Статус:** Відкрито. Архітектурна проблема CoAP uplink.
**Файл:** `firmware/queen/main.c:542-566`

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

1. **Single-packet buffer:** `incoming_lora_payload[16]` — єдиний буфер. Радіо SX1262 продовжує приймати пакети через ISR (`OnRxDone`) під час усього flush. Але оскільки `lora_rx_flag` — однобітний прапорець, а `incoming_lora_payload` — єдиний буфер, кожен новий ISR **мовчки перезаписує** попередній пакет. Після ~25 секунд flush головний цикл обробить лише **один** (останній) пакет. **Усі проміжні пакети від дерев безповоротно втрачені.**
2. **Emergency packet loss:** Під час пожежі, якщо 10+ дерев одночасно надсилають emergency TinyML сигнали протягом 25-секундного flush — тільки одне зафіксується.
3. **Немає `Radio.Rx()` після flush:** Функція `Flush_Cache_To_Rails()` не викликає `Radio.Rx()`. Radio переходить у idle-стан після кожного `Radio.Send()` (OTA reflex shot). Якщо OTA не активовано — Radio залишається в RX-стані від попереднього `Radio.Rx(LORA_RX_INFINITE)`. Але якщо OTA активовано і flush відбувається в тому ж циклі — RX відновиться лише після наступного спрацювання `lora_rx_flag`.
4. **Відповідь модему не парситься:** `SIM7070_SendATCommand` використовує `HAL_Delay` замість читання UART. `OK`/`ERROR` від модему ігнорується.

**Необхідна дія:**
- Переписати `Flush_Cache_To_Rails()` на UART DMA interrupt-driven (DMA UART + callback).
- Відправку CoAP виконувати асинхронно, не блокуючи головний цикл.
- Перейти з однобітного `lora_rx_flag` на кільцевий буфер (ring buffer) для ISR-пакетів.
- Реалізувати парсинг відповіді `OK`/`ERROR` від SIM7070G.

**Блокує:** Надійність Queen в умовах щільного LoRa-трафіку, Emergency Alerting, Proof of Growth completeness.

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
**Файл:** `firmware/queen/main.c:542-566`

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

### 🔴 BLOCKER-8: HRNG Fallback до HAL_GetTick() — Критична IV-Reuse вразливість CBC

**Статус:** Відкрито. **Критична** криптографічна вразливість при масовому blackout-відновленні.
**Файл:** `firmware/queen/main.c:516-519`

```c
if (HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK) {
    /* Fallback: якщо HRNG не відповідає */
    batch_iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL);
}
```

`HAL_GetTick()` повертає кількість мілісекунд від старту. Після blackout усі Королеви мають `HAL_GetTick() ≈ 0`. Поєднуючи це з BLOCKER-1 (однаковий AES ключ для всіх вузлів):

**IV Reuse Attack (критична CBC вразливість):**
- Якщо дві Королеви використовують **однаковий ключ** + **однаковий IV** → атакуючий XOR-ує два шифротексти → отримує XOR відкритих текстів → телеметрія частково розкрита.
- Формально: `C1 XOR C2 = P1 XOR P2` при однаковому IV та ключі в режимі CBC.
- Це **повністю знищує конфіденційність** CBC для batch даних після будь-якого масового перезавантаження.

**Необхідна дія:**
- Використовувати STM32 TRNG (справжній апаратний RNG від теплового шуму) як єдине джерело IV.
- Якщо HRNG недоступний — застосувати комбінований seed: `tick XOR queen_uid_hash XOR uptime_counter` (різний для кожної Queen завдяки UID).
- Довгостроково — вирішується через BLOCKER-1: унікальний ключ на кожен пристрій ламає однорідність навіть при однаковому IV.

---

### 🔴 BLOCKER-9: OTA Broadcast Infinite Loop — `ota_is_active` ніколи не скидається

**Статус:** Відкрито. Після першого OTA Queen назавжди залишається в режимі бродкасту.
**Файл:** `firmware/queen/main.c:290-293`

```c
// Перемикаємося на наступний шматок для наступного дерева
current_ota_chunk_idx++;
if (current_ota_chunk_idx >= total_chunks) {
    current_ota_chunk_idx = 0;
    // Якщо маємо оновити ліс лише один раз, розкоментувати:
    // ota_is_active = 0;   ← ЗАКОМЕНТОВАНО. Прапорець ніколи не скидається до 0.
}
```

**Проблема:** Після того як `Handle_CoAP_Command` отримала всі CoAP-чанки та виставила `ota_is_active = 1`, цей прапорець **ніколи** не повертається до 0. Головний цикл при кожному отриманому LoRa-пакеті виконує OTA Reflex Shot (60 ms), незалежно від того, чи є нові прошивки. `current_ota_chunk_idx` циклічно скидається до 0, і цикл повторюється вічно.

**Наслідки:**
1. Кожна відповідь на LoRa-пакет від Солдата додає 60 ms фіксованої затримки **назавжди** — навіть після того, як усі Солдати вже оновилися.
2. OTA-чанки для старої прошивки продовжують надсилатися нескінченно. Солдат, який пізніше приєднався до мережі, отримає застарілу прошивку з `pending_ota_bytecode`.
3. При наступному OTA-оновленні `pending_ota_bytecode` перезаписується поступово (чанк за чанком), але `ota_is_active = 1` вже. Queen починає бродкастити **суміш** старої та нової прошивки до моменту, поки зберуться всі нові чанки.

**Необхідна дія:**
- Розкоментувати `ota_is_active = 0` після завершення одного повного циклу бродкасту.
- Або реалізувати підтвердження від Солдатів (ACK-based OTA completion) та скидати `ota_is_active` лише після отримання ACK від усіх активних вузлів у `forest_cache`.
- При скиданні OTA-стану також обнулити `pending_ota_size`, щоб запобігти broadcast з частковим буфером.

**Блокує:** Стабільна OTA-доставка при масовому оновленні лісу, коректна робота шлюзу після першої OTA-сесії.

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
║    current_jitter = HRNG() % 60001  ← Thundering Herd prevention        ║
║                    (fallback: HAL_GetTick(), без XOR-маски)              ║
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
| `snr` параметр | **не використовується** | SNR від SX1262 ігнорується в `OnRxDone` |

**Volatile-семантика:** `incoming_lora_payload` та `lora_rx_flag` оголошені `volatile`, бо записуються в ISR, читаються в main loop. `(void*)` cast безпечний: `lora_rx_flag` серіалізує доступ ISR→main.

**Single-packet buffer обмеження:** `incoming_lora_payload[16]` — єдиний буфер. При одночасному отриманні двох пакетів ISR перезаписує буфер — перший пакет втрачається. Це не проблема в нормальному режимі (LoRa TDMA природно розмазує трафік), але критично під час 25-секундного flush (BLOCKER-2).

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
   padded_size = ((offset + 15) / 16) * 16  ← AES block alignment
   Захист: if (padded_size > sizeof(binary_batch_buffer)) → cap

2. Generate IV: HRNG "Wu-Wei" підхід:
   hrng.Instance = RNG
   HAL_RNG_Init(&hrng)  ← ініціалізація тільки перед використанням
   for i in 0..3:
     if HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK:
       batch_iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL)  ← IV fallback
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
| Місце | Fallback при HRNG fail | Маска |
|-------|------------------------|-------|
| CBC IV generation (batch) | `HAL_GetTick() ^ (i * 0x5A5A5A5AUL)` | per-word, різна для кожного слова |
| Jitter regeneration після flush | `HAL_GetTick() ^ RNG_FALLBACK_XOR_MASK` | `0xA5A5A5A5UL` (одна константа) |
| Startup jitter (один раз) | `HAL_GetTick()` (без XOR!) | без маски — рядок 228 |

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
1. AT+CCOAPNEW="coap://api.silkennet.com:5683"\r\n  (HAL_Delay 1000 ms)
   ↳ Відкриваємо CoAP сесію, session_id=0

2. Формуємо та відправляємо AT+CCOAPSEND через UART (blocking):
   a. Заголовок команди: snprintf → HAL_UART_Transmit(..., strlen, 100ms)
      "AT+CCOAPSEND=0,2,"telemetry/batch/QUEEN-001",<size*2>,\""
   b. Hex payload: кожен байт окремо → HAL_UART_Transmit(2 байти ASCII, 10ms)
      Для 50 записів: total_size ≈ 1072 байт → 2144 ASCII → ~21.4 секунди
   c. Закриваємо: HAL_UART_Transmit("\"\r\n", 3, 100ms)
   ↳ Method=2 (PUT), URI-Path визначає шлюз (вирішує Starlink NAT)

3. HAL_Delay(2000)  ← Чекаємо UDP ACK від сервера (відповідь не читається!)

4. AT+CCOAPDEL=0\r\n  (HAL_Delay 500 ms)
   ↳ Закриваємо сесію, звільняємо ресурси модему
```

**Загальний час flush для 50 записів: ~25 секунд** (BLOCKER-2)

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
  current_ota_chunk_idx = 0       ← wrap → цикл починається знову
  // ota_is_active = 0;           ← ЗАКОМЕНТОВАНО (BLOCKER-9)
```

**Математика LoRa чанків:**
- Корисне навантаження: 11 байт (16 − 5 байт заголовка)
- Для 8192 байт bytecode: `(8192 + 10) / 11 = 745` LoRa-чанків
- Кожен Солдат при кожному своєму TX отримує **один** послідовний чанк
- Після 745-го чанка `current_ota_chunk_idx` скидається до 0 і цикл повторюється (BLOCKER-9)

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
    // УВАГА: ota_is_active ніколи не повертається до 0 (BLOCKER-9)
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
// Bytes 4-5: uptime proxy — тік / 1000 (wraps кожні ~65 секунд)
uint16_t uptime_sec = (uint16_t)(HAL_GetTick() / 1000);
queen_health[4] = (uint8_t)(uptime_sec >> 8);
queen_health[5] = (uint8_t)(uptime_sec & 0xFF);
// Byte 6:  зарезервовано (0x00) — майбутнє: температура корпусу Queen
// Byte 7:  кількість дерев у кеші (навантаження шлюзу, 0–50)
queen_health[7] = cache_count;
// Bytes 8-9: зарезервовано (0x00) — майбутнє: CSQ модему (0–31)
// Byte 10: growth_points = cache_count (cap at 63, QUEEN_HEALTH_GP_MAX)
queen_health[10] = (cache_count < QUEEN_HEALTH_GP_MAX) ? cache_count : QUEEN_HEALTH_GP_MAX;
// Bytes 11-15: зарезервовано (0x00) — майбутнє: напруга батареї, версія прошивки
Process_And_Cache_Data(0, queen_health, 0); // RSSI=0 (локальний пакет)
```

**Повна структура Queen Health Sentinel (16 байт payload):**

| Байт(и) | Поле | Значення | Опис |
|---------|------|----------|------|
| 0–3 | DID | `0x00000000` | Sentinel — "це Королева, не дерево" |
| 4–5 | Uptime | `HAL_GetTick() / 1000` | Uptime proxy (uint16, wraps ~65 с) |
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
| `forest_cache[50]` | `EdgeCache` | 1100 B | CIFO EdgeCache (50 × 22 байти) |
| `binary_batch_buffer[2048]` | `uint8_t` | 2048 B | Бінарний буфер перед шифруванням |
| `encrypted_batch_buffer[2064]` | `uint8_t static` | 2064 B | **static** (IV + зашифровані дані) |
| `pending_ota_bytecode[8192]` | `uint8_t` | 8192 B | RAM-буфер збірки OTA від Rails |
| `at_tx_buffer[256]` | `char` | 256 B | Формування AT-команд (`snprintf`) |
| `cmd_dedup_ring[16]` | `uint32_t` | 64 B | DJB2 хеші idempotency токенів |
| `cmd_decrypt_buf[544]` | `uint8_t` | 544 B | Decrypt buffer для CoAP команд/OTA |
| `incoming_lora_payload[16]` | `volatile uint8_t` | 16 B | Сирий зашифрований пакет від ISR |
| `decrypted_payload[16]` | `uint8_t` | 16 B | Розшифрований пакет |
| `ota_chunk_bitmap` | `uint16_t` | 2 B | Bitmap отриманих OTA-чанків (16 біт) |
| `ota_chunks_received` | `uint16_t` | 2 B | Лічильник отриманих CoAP-чанків |
| `ota_total_expected_chunks` | `uint16_t` | 2 B | Очікуваний total від header |
| `pending_ota_size` | `uint16_t` | 2 B | Реальний зібраний розмір байткоду |
| Scalar variables | misc | ~20 B | `cache_count`, `lora_rx_flag`, `current_rssi`, `ota_is_active`, `current_ota_chunk_idx`, `cmd_dedup_idx`, `cmd_dedup_used` |
| **Разом** | | **~14.4 KB** | З 64 KB SRAM = ~22% використання |

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

**Не покрито тестами:**
- AT command response parsing (модем відповіді)
- CoAP retry logic при мережевих помилках
- OTA downlink з `aligned >= 544` (повний 512-байтний CoAP чанк в тесті) — BLOCKER-7
- `ota_is_active` never-reset scenario (infinite broadcast loop) — BLOCKER-9
- Single-packet buffer overwrite during ~25 s flush — BLOCKER-2
- HRNG startup fallback (без XOR mask) vs flush-regen fallback (з `RNG_FALLBACK_XOR_MASK`)

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

*Документ створено: 2026-03-24 | Останнє оновлення: 2026-03-24 (Session 3 — детальний re-read main.c) | Автор: AI Agent (Copilot) | Issue: #187*
*Синхронізовано з: `firmware/queen/main.c` (800 рядків, читання рядок-за-рядком), `firmware/test/test_queen_logic.c` (1337 рядків)*
*Нові знахідки: BLOCKER-9 (OTA infinite loop), BLOCKER-2 ескалований (~25 с), payload_len formula, snr ignored, RNG_FALLBACK_XOR_MASK, startup vs regen jitter distinction*
