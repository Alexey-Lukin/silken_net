# 03_05: Hardware AES256 & Security (Шифрування пакетів EwsAlert)

**Модуль:** 03_05 — Hardware AES256 & Security (Криптографічний Пайплайн Прошивки)
**Пов'язані модулі:** [03_01 Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) · [03_02 Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) · [03_04 mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) · [04_02 Business Logic and Services](04_02_Business_Logic_and_Services) · [05_02 Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline)
**Поточний TRL:** 6 (Апаратне шифрування налаштовано, 137 host-based тестів проходять, SSOT зафіксовано цим документом)
**Цільовий TRL:** 7 (Повна прозорість криптографічного пайплайну; Factory Flashing з унікальними ключами розблоковано)
**Статус Аудиту:** Reverse Shaping Cycle 1 — документування поточного стану ("як є") без рефакторингу коду

> **⚠️ SSOT Sync:** Цей документ синхронізовано з `firmware/soldier/main.c` та `firmware/queen/main.c` станом на 2026-03-24. Усі виявлені блокери безпеки задокументовані в розділі 🛑. **Жодного рефакторингу криптографії не виконувалось** — тільки виявлення та фіксація "як є".

---

## 🎯 Мета (Objective)

Зафіксувати детальний криптографічний пайплайн вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор): режим роботи AES, структуру зашифрованих пакетів, управління ключами та генерацію вектора ініціалізації (IV). Документ є SSOT для Hardware Security Audit перед масовим виробничим розгортанням.

> Цей документ **не** рефакторить криптографію. Він фіксує "як є" — включаючи всі відомі ризики та відкриті блокери безпеки. Ніколи не пишіть власну криптографію і не просіть ШІ "швидко пофіксити" крипто-код.

---

## ✅ Статус (Status)

| Компонент | Стан |
|-----------|------|
| **AES-256 апаратний модуль** (`MX_CRYP_Init` / `HAL_CRYP_Init`) | ✅ Реалізовано (обидва вузли) |
| **Soldier → Queen (LoRa): AES-256-ECB** | ✅ Реалізовано |
| **Queen → Rails (CoAP Batch): AES-256-CBC + HRNG IV** | ✅ Реалізовано |
| **Rails → Queen (CoAP Command): AES-256-CBC + IV** | ✅ Реалізовано |
| **ECB Restoration після CBC операцій (Queen)** | ✅ Виправлено (`[FIX: CRITICAL — ECB Restoration]`) |
| **HRNG Fallback (безпечна деградація)** | ✅ Реалізовано (XOR tick + index) |
| **Emergency TX (EwsAlert / Panic): AES-256-ECB** | ✅ Реалізовано |
| **AES Key — захардкоджений у Flash** | 🔴 BLOCKER (ідентичний для всіх вузлів) |
| **ECB Mode для Soldier ↔ Queen (відсутність IV)** | 🔴 BLOCKER (вразливість для статичних блоків) |
| **Відсутність MAC/MIC для LoRa-пакетів** | 🔴 BLOCKER (немає автентифікації повідомлень) |
| **HRNG Fallback — передбачуваний seed** | 🟡 OPEN (HAL_GetTick() → слабка ентропія) |
| **Відсутність ротації ключів (Key Rotation)** | 🟡 OPEN (неможлива без перепрошивки) |
| **Ідентичний ключ Soldier та Queen (симетрія при прошивці)** | 🔴 BLOCKER (єдина точка компрометації + операційний ризик мовчазної втрати телеметрії при мисматчі) |

---

## 🛑 Блокери (Blockers / Needs Action)

> Цей розділ є виходом **жорсткого аудиту безпеки** "Reverse Shaping". Виявлено 3 критичних (🔴) та 3 відкритих (🟡) ризики. Жодного рефакторингу не виконувалось.

---

### 🔴 BLOCKER-1: Hardcoded AES-256 Key у Flash-пам'яті (Ідентичний на всіх вузлах)

**Статус:** Відкрито. **Критичний ризик безпеки для масового виробництва.**

**Файли:** `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:65-66`

```c
// Однаковий ключ у ВСІХ вузлах мережі Silken Net — Soldier та Queen
// (Актуальні значення — у firmware/soldier/main.c:66-67, навмисно не дублюються тут)
uint32_t aes_key[8] = {0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX,
                       0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX};
```

Також у `firmware/queen/main.c:63-64` прямо зазначено:
```c
// МАЄ БУТИ ІДЕНТИЧНИМ ключу, зашитому в усіх Солдатах.
```

**Ризики:**

1. **Єдина точка відмови (Single Point of Failure):** Злам одного Солдата → витяг ключа → дешифрування трафіку **всієї мережі** (мільйони вузлів).
2. **Flash читається через JTAG/SWD:** Якщо не активовано RDP Level 2 (Readout Protection), ключ тривіально витягується стандартним програматором за 30 секунд.
3. **Неможливість ротації (No Key Rotation):** Замінити ключ без перепрошивки **кожного** вузла в полі — практично нездійснено при мільярдах дерев.
4. **Відсутня ізоляція між вузлами:** Відсутній механізм Per-Device Key Derivation (PKDF) — усі дерева в одній мережі розшифровують пакети одне одного.

**Необхідна дія:**

- Провізіонувати унікальний ключ на кожен пристрій через захищений канал (`POST /api/v1/provisioning/register`) під час Factory Flashing.
- Активувати **RDP Level 2** як фінальний крок Factory Flashing (необоротно блокує JTAG/SWD).
- Перенести ключ у `FLASH_KEYR`-захищену зону або окремий Secure Element (наприклад, ATECC608B).
- Реалізувати Per-Device Key Derivation: `device_key = HKDF(master_key, device_uid)`.

**Блокує:** Factory Flashing, масове виробництво, Hardware Security Audit.
> **⚠️ ОПЕРАЦІЙНИЙ РИЗИК (Deployment Pre-Flight):** Навіть при правильному provisioning, якщо `aes_key[8]` у `firmware/soldier/main.c` та `firmware/queen/main.c` відрізняється хоча б одним бітом, наслідки непомітні але катастрофічні:
> - **Симптом:** Queen декриптує кожен Soldier-пакет у беззмістовний сміттєвий масив. Ліс виглядатиме абсолютно мовчазним.
> - **Причина:** Відсутня MAC/MIC автентифікація (BLOCKER-3) — Rails не отримає жодної помилки, логи будуть порожніми.
> - **Правило:** Перевіряй симетрію ключів перед кожним циклом прошивки. Виробничий ключ зберігай в єдиному vault (Bitwarden/1Password) — не в двох різних місцях одночасно.

---

### 🔴 BLOCKER-2: ECB Mode для LoRa Soldier → Queen (Відсутній IV, немає дифузії між блоками)

**Статус:** Відкрито. **Архітектурна вразливість шифрування.**

**Файли:** `firmware/soldier/main.c:747`, `firmware/queen/main.c:781`

```c
// Soldier MX_CRYP_Init():
hcryp.Init.Algorithm = CRYP_AES_ECB; // Використовуємо базовий Electronic Codebook для простоти 1 блоку

// Queen MX_CRYP_Init():
hcryp.Init.Algorithm = CRYP_AES_ECB; // ECB для LoRa-трафіку між Королевою та Солдатами
```

**ECB (Electronic Codebook) — детермінований режим:**

- Той самий відкритий текст → той самий шифротекст (при однаковому ключі).
- Відсутній вектор ініціалізації (IV): `pInitVect = NULL`.
- Відсутня дифузія між різними блоками (кожен блок шифрується незалежно).

**Ризики:**

1. **Детермінований шифротекст:** Якщо дерево регулярно відправляє один і той самий `lora_payload` (наприклад, нічний "пульс спокою" — стабільна напруга, температура, нуль акустики), адверсар бачить **ідентичні зашифровані пакети** і може вивести паттерни без дешифрування.
2. **Атаки вибраного відкритого тексту (Chosen Plaintext Attack):** Якщо адверсар контролює фізичні умови навколо дерева (наприклад, нагріває датчик), він може отримати пари (plaintext, ciphertext) і атакувати ключ.
3. **Replay Attack:** Адверсар записує зашифрований пакет "здорового" дерева та повторно відправляє його пізніше, фальсифікуючи телеметрію. Немає захисту від повторного відтворення (немає nonce/timestamp у шифротексті).

**Пом'якшуюча обставина (Mitigation):** Оскільки LoRa-пакет є рівно одним AES-блоком (16 байт), ECB еквівалентний CBC для одного блоку — дифузія між блоками не має значення. Але проблема детермінізму та replay залишається.

**Необхідна дія:**

- Перейти на **AES-256-CTR** або **AES-256-GCM** для LoRa-трафіку (включає лічильник як nonce, забезпечуючи унікальність кожного шифротексту).
- Альтернатива при збереженні ECB: додати 2-4 байти per-packet nonce/counter до `lora_payload` (пожертвувати частиною сенсорного payload).
- Рішення архітектурно узгодити з [03_01 Firmware Lifecycle](03_01_Firmware_Lifecycle_and_DMA) та [04_02 Business Logic](04_02_Business_Logic_and_Services).

**Блокує:** Hardware Security Audit, захист від replay-атак на LoRa-мережу.

---

### 🔴 BLOCKER-3: Відсутність MAC/MIC (Message Authentication Code) для LoRa-пакетів

**Статус:** Відкрито. **Критична відсутність автентифікації повідомлень.**

**Контекст:** LoRa-пакет (16 байт) містить лише зашифровані сенсорні дані. Не передбачено жодного механізму перевірки цілісності або автентифікації джерела.

**Ризики:**

1. **Bit-flip Attack:** Адверсар може змінити один або кілька бітів у зашифрованому пакеті. В режимі ECB (без дифузії між блоками) це призводить до **передбачуваних** змін у відповідних позиціях дешифрованого тексту. Наприклад, перевернути bit 7 байту 7 → змінити кількість акустичних подій → фальшивий сигнал пилки.
2. **Injection Attack:** Будь-який пристрій у зоні LoRa може відправити підроблений пакет з довільним DID та сенсорними даними. Queen розшифрує та кешує його без перевірки джерела.
3. **Відсутній захист від маніпуляцій з payload:** AES-ECB **не автентифікує** — він лише шифрує. Без MAC (наприклад, AES-GCM або HMAC-SHA256) Queen не може відрізнити легітимний пакет від підробленого.

**Необхідна дія:**

- Перейти на **AES-256-GCM** (надає одночасно конфіденційність + автентифікацію + nonce). Це найбільш ефективне рішення для обмежених STM32-ресурсів.
- Або: додати **HMAC-SHA256 MIC** (4 байти суфіксу) до кожного LoRa-пакету, скоротивши сенсорний payload до 12 корисних байтів.
- LoRaWAN також забезпечує MIC через AES-128-CMAC — розглянути перехід на LoRaWAN замість сирого LoRa.

**Блокує:** Довіра до телеметрії, Proof of Growth Pipeline (05_02), Hardware Security Audit.

---

### 🟡 BLOCKER-4: HRNG Fallback — Передбачуваний Seed (HAL_GetTick)

**Статус:** Відкрито. Середня серйозність.

**Файли:** `firmware/queen/main.c:516-519`

```c
if (HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK) {
    /* Fallback: якщо HRNG не відповідає — XOR tick з індексом */
    batch_iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL);
}
```

**Аналіз:**

- `HAL_GetTick()` — мілісекунди з моменту запуску MCU. Цей час є частково передбачуваним (Queen запускається за фіксований час після подачі живлення, а flush відбувається через кратне `FLUSH_INTERVAL_MS`).
- XOR з фіксованою константою `0x5A5A5A5AUL` не додає ентропії — це детерміністична операція.
- Адверсар, що знає приблизний час запуску Queen та інтервал флашингу, може звузити простір пошуку IV до ~2^16 (64К варіантів) замість теоретичних 2^128.

**Пом'якшуюча обставина:** Fallback активується **лише при відмові HRNG** — нормальний сценарій використовує апаратний RNG (тепловий шум). Відмова HRNG — аномалія, не типовий режим.

**Необхідна дія:**

- Якщо HRNG недоступний, Queen має **відмовитись від flush** та спробувати повторно після перезапуску, а не використовувати слабкий fallback.
- Або комбінувати кілька джерел ентропії: `XOR(HAL_GetTick(), ADC_noise_sample, uid_hash)`.
- Додати лічильник відмов HRNG у метрики (Prometheus) для моніторингу апаратних аномалій.

**Блокує:** Криптографічна стійкість CBC IV при апаратних збоях.

---

### 🟡 BLOCKER-5: Відсутній Механізм Ротації Ключів (Key Rotation)

**Статус:** Відкрито. Системна проблема при масштабуванні.

**Контекст:** Поточна архітектура передбачає єдиний статичний ключ, зашитий при Factory Flashing. Немає механізму зміни ключа без повної перепрошивки через OTA або фізичного доступу.

**Ризики:**

1. **Long-term Key Exposure:** Якщо ключ скомпрометовано (наприклад, через фізичний злам одного вузла + зчитування Flash), всі минулі записані LoRa-пакети можуть бути ретроспективно дешифровані (відсутнє Perfect Forward Secrecy).
2. **Регуляторна невідповідність:** GDPR, ISO 27001 та NIST SP 800-57 вимагають ротацію криптографічних ключів. При масштабуванні до публічного продукту NaaS це може стати юридичним блокером.
3. **OTA як вектор атаки:** Якщо OTA-канал не має власного механізму ключ-обміну, оновлення нового ключа через OTA саме по собі шифрується старим (скомпрометованим) ключем.

**Необхідна дія:**

- Розробити протокол **Key Rotation** як окрему задачу наступного циклу:
  1. Backend генерує новий ключ `K_new`.
  2. Надсилає `K_new` через OTA (шифрований поточним `K_old`).
  3. Після підтвердження від усіх вузлів кластера — активація `K_new`.
- Розглянути **Diffie-Hellman Key Exchange** на рівні provisioning для усунення потреби в pre-shared key.

**Блокує:** Довгострокова безпека мережі, відповідність регуляторним вимогам NaaS.

---

### 🟡 BLOCKER-6: Відсутній Захист Від Downgrade Attack (ECB Restoration Race)

**Статус:** Відкрито. Потенційна умова гонки.

**Файли:** `firmware/queen/main.c:568-575`

```c
// [FIX: CRITICAL — ECB Restoration]
// Flush_Cache_To_Rails() переключає CRYP на CBC для шифрування батча.
// Якщо не повернути ECB, всі наступні HAL_CRYP_Decrypt() для LoRa-пакетів
// від Солдатів будуть використовувати CBC замість ECB → сміття → втрата даних
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);
```

**Аналіз:**

- `Flush_Cache_To_Rails()` переключає CRYP з ECB → CBC, виконує шифрування батча, потім явно відновлює ECB. Цей механізм виправлено (зафіксовано як `[FIX: CRITICAL]`).
- Проблема: `HAL_CRYP_Init()` є **блокуючим** викликом без таймауту в джерелі прошивки. Якщо периферійний блок AES "завис" (апаратний дефект), відновлення ECB може не відбутись.
- `Handle_CoAP_Command()` виконує аналогічне CBC→ECB відновлення (`firmware/queen/main.c:659-662`). Якщо функція поверне `return` через помилку розміру (`aligned > CMD_DECRYPT_BUF_SIZE`), ECB також відновлюється. Але якщо `HAL_CRYP_Decrypt()` сам завершиться помилкою — відновлення не гарантоване.

**Необхідна дія:**

- Обгорнути відновлення ECB у захисний патерн із перевіркою повернення `HAL_CRYP_Init()`.
- Додати watchdog або перевірку стану `hcryp.State` перед кожним `HAL_CRYP_Encrypt/Decrypt`.

**Блокує:** Надійність криптографічного пайплайну Queen при апаратних збоях.

---

### 🟢 INFO: Зафіксовані та Виправлені Ризики (Closed)

Наступні ризики виявлено та виправлено безпосередньо в C-коді до синхронізації SSOT:

| # | Ризик | Серйозність | Статус |
|---|-------|-------------|--------|
| R-01 | ECB Mode не відновлювався після CBC flush (`Flush_Cache_To_Rails`) | 🔴 | ✅ Виправлено: явний `CRYP_AES_ECB` restore |
| R-02 | ECB Mode не відновлювався після CBC в `Handle_CoAP_Command` | 🔴 | ✅ Виправлено: явний `CRYP_AES_ECB` restore |
| R-03 | `encrypted_batch_buffer[2064]` на стеку (ризик Stack Overflow) | 🔴 | ✅ Виправлено: `static uint8_t` у `Flush_Cache_To_Rails` |
| R-04 | HRNG re-init/de-init на кожен IV batch (неефективна, але безпечна ізоляція) | 🟡 | ✅ Прийнято: "Wu-Wei" підхід, мінімальне споживання |

---

## 🔐 1. Ініціалізація Крипто-Модуля (MX_CRYP_Init)

### 1.1 Soldier — `firmware/soldier/main.c:741-748`

```c
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType    = CRYP_DATATYPE_32B;   // 32-бітний порядок слів
  hcryp.Init.KeySize     = CRYP_KEYSIZE_256B;    // Gaia 2.0 Standard: 256-бітний ключ
  hcryp.Init.pKey        = aes_key;              // Вказівник на hardcoded ключ у Flash
  hcryp.Init.Algorithm   = CRYP_AES_ECB;         // Electronic Codebook для 1 блоку LoRa TX
  HAL_CRYP_Init(&hcryp);
}
```

### 1.2 Queen — `firmware/queen/main.c:770-782`

```c
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType    = CRYP_DATATYPE_32B;   // 32-бітний порядок слів
  hcryp.Init.KeySize     = CRYP_KEYSIZE_256B;    // Gaia 2.0 Standard: 256-бітний ключ
  hcryp.Init.pKey        = aes_key;              // Вказівник на hardcoded ключ у Flash
  hcryp.Init.Algorithm   = CRYP_AES_ECB;         // ECB базовий режим для LoRa RX
  // Примітка: CBC для батч-флашингу та downlink команд встановлюється динамічно
  HAL_CRYP_Init(&hcryp);
}
```

**Апаратна периферія:** AES-блок STM32WLE5JC (`hcryp.Instance = AES`) — апаратне прискорення без залучення ядра Cortex-M4. Не потребує програмних крипто-бібліотек.

**Параметри ключа:**

| Параметр | Значення | Примітка |
|----------|----------|---------|
| `KeySize` | `CRYP_KEYSIZE_256B` | 256-бітний ключ (32 байти, 8 × uint32_t) |
| `DataType` | `CRYP_DATATYPE_32B` | Endianness: 32-бітний порядок байтів |
| `pKey` | `&aes_key[0]` | Вказівник на Flash-адресу hardcoded ключа |

---

## 📦 2. Структура Зашифрованих Пакетів (Payload Structure)

### 2.1 Soldier → Queen: LoRa Uplink (AES-256-ECB)

**Режим:** AES-256-ECB · **Розмір:** 16 байт = 1 AES-блок · **IV:** відсутній

```
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 0 | Byte 1 | Byte 2 | Byte 3 | Byte 4 | Byte 5 | Byte 6 | Byte 7 |
|       DID (Device ID, 4 байти, big-endian)        | Vcap MSB|Vcap LSB| Temp°C |Acoustic|
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 8 | Byte 9 |Byte 10 |Byte 11 |Byte 12 |Byte 13 |Byte 14 |Byte 15 |
|ΔT MSB  |ΔT LSB  |GrowthPt|  TTL   |FW MSB  |FW LSB  | PAD    | PAD    |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

**Легенда:**
- `DID` (bytes 0-3): 4-байтний Decentralized Identity (Device ID), big-endian
- `Vcap` (bytes 4-5): напруга суперконденсатора в mV, big-endian
- `Temp°C` (byte 6): температура (int8_t), підписана (від -128 до +127 °C)
- `Acoustic` (byte 7): кількість TinyML-відфільтрованих акустичних подій (кавітація/пилка)
- `ΔT` (bytes 8-9): `delta_t_seconds` — час між пробудженнями (швидкість метаболізму EBFC)
- `GrowthPoints` (byte 10): упакований результат mruby Lorenz `[Status:2|GrowthPoints:6]`
- `TTL` (byte 11): Time to Live для Mesh-маршрутизації (початково 3, зменшується на 1 при кожному hop)
- `FW` (bytes 12-13): Firmware Version ID, big-endian (для OTA targeting)
- `PAD` (bytes 14-15): нульовий padding (резерв, не використовується)

**Emergency TX (EwsAlert / Panic) — `Trigger_Emergency_LoRa_TX()`:**
```
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 0 | Byte 1 | Byte 2 | Byte 3 | Byte 4 | Byte 5 | Byte 6 | Byte 7 |
|       DID (Device ID, 4 байти, big-endian)        |   0    |   0    |   0    | 0xFF   |
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 8 | Byte 9 |Byte 10 |Byte 11 |Byte 12 | ...   | ...   |Byte 15 |
|   0    |   0    |   0    |PANIC_TTL|   0   |   0    |   0    |   0    |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

- Byte 7 = `0xFF` → код паніки (максимальна акустична подія)
- Byte 11 = `PANIC_TTL` (= 5, збільшений TTL для досягнення Queen через більше стрибків)
- Решта байтів = нулі

**Шифрування (однаковий алгоритм для обох типів пакетів):**
```c
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)lora_payload,   4, (uint32_t*)encrypted_payload, 1000);
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)panic_payload,   4, (uint32_t*)encrypted_panic,   1000);
```
- Вхід: 4 слова × 32 біти = 16 байт відкритого тексту
- Вихід: 16 байт зашифрованого тексту (1 AES-блок)
- Таймаут: 1000 мс (апаратний модуль зазвичай завершує за < 1 мкс)

---

### 2.2 Queen → Rails: CoAP Batch Uplink (AES-256-CBC)

**Режим:** AES-256-CBC · **Структура:** `[IV:16][Encrypted Data: N×16]`

```
+------------------+------------------+------------------+-----+------------------+
|   IV (16 bytes)  | Encrypted Block 1| Encrypted Block 2| ... | Encrypted Block N|
|  (HRNG-generated)|  (AES-256-CBC)   |  (AES-256-CBC)   |     |  (AES-256-CBC)   |
+------------------+------------------+------------------+-----+------------------+
```

**Кожен "Encrypted Block" містить один або кілька 21-байтних записів телеметрії** (вирівняних padding нулями до кратного 16):

```
21-byte Telemetry Record (before encryption):
+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|  DID[0]|  DID[1]|  DID[2]|  DID[3]|  UID   | RSSI   |Vcap MSB|Vcap LSB| Temp°C |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|Acoustic|ΔT MSB  |ΔT LSB  |GrowthPt|  TTL   |FW MSB  |FW LSB  |BioStat | RSSI   |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+
| Hash   |  0     |  0     |        (padding нулями до кратного 16 байт)          |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+
```

**CoAP URI:** `PUT /telemetry/batch/<QUEEN_UID>` (queen_uid = `"QUEEN-001"`, hardcoded — ⚠️ окремий блокер 03_01 BLOCKER-3)

**Передача:** Зашифрований буфер перетворюється у Hex-рядок та відправляється через `AT+CCOAPSEND` команди до SIM7070G модему.

---

### 2.3 Rails → Queen: CoAP Command Downlink (AES-256-CBC)

**Режим:** AES-256-CBC · **Структура:** `[IV:16][Encrypted Command Data]`

```
+------------------+-----------------------------------------------+
|   IV (16 bytes)  |     Encrypted Command Payload (N×16 bytes)    |
|  (from Backend)  |          (AES-256-CBC decryption)             |
+------------------+-----------------------------------------------+
```

**Дешифровані дані — два формати:**

**Актуаторна команда (CMD):**
```
CMD:<ACTION>:<DURATION>:<ACTUATOR_ID>:<IDEMPOTENCY_TOKEN>
Приклад: CMD:OPEN:60:42:a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

**OTA Downlink (0x99 маркер):**
```
+--------+--------+--------+--------+--------+-----+-------+--------+
|  0x99  |ChunkIdx|ChunkIdx|TotalCh |TotalCh | ... |Bytecod|  CRC   |
| (OTA)  |  [MSB] |  [LSB] |  [MSB] |  [LSB] | e payload |  [2B]  |
+--------+--------+--------+--------+--------+-----+-------+--------+
```

---

### 2.4 Queen → Soldier: OTA LoRa Broadcast (AES-256-ECB)

**Режим:** AES-256-ECB · **Розмір:** 16 байт

```
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 0 | Byte 1 | Byte 2 | Byte 3 | Byte 4 | Byte 5 | Byte 6 |  ...  |
|  0x99  |ChunkIdx|ChunkIdx|TotalCh |TotalCh |Bytecode       ...       |
| (OTA)  |  [MSB] |  [LSB] |  [MSB] |  [LSB] |                        |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

---

## 🔑 3. Управління Ключами (Key Management)

### 3.1 Джерело AES-Ключа при Старті

| Параметр | Значення |
|----------|---------|
| **Тип зберігання** | C-масив у Flash-пам'яті MCU (`uint32_t aes_key[8]`) |
| **Адреса** | Визначається лінкером (`.rodata` або `.data` секція) |
| **Розмір** | 256 біт (32 байти, 8 × uint32_t) |
| **Захист** | RDP Level 0 (⚠️ нема захисту) або RDP Level 1/2 (потребує явного активування) |
| **Ротація** | Відсутня (static const) |
| **Унікальність** | Ідентичний на ВСІХ вузлах мережі |

**Поточний AES-256 ключ (hardcoded, зберігається у Flash-пам'яті — детальні значення у `firmware/soldier/main.c:66-67`):**
```c
uint32_t aes_key[8] = {
    0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX,  // 128 біт (частина 1)
    0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX   // 128 біт (частина 2)
};
```
> ⚠️ **Увага:** Аудит виявив, що перші 4 слова ключа збігаються зі стандартним тестовим ключем AES-128 з FIPS-197 (Appendix B) — загальновідомими тестовими векторами. Точні значення навмисно не публікуються в цьому документі. Для аудиту безпеки — дивись `firmware/soldier/main.c:66-67` та `firmware/queen/main.c:65-66`. Ключ **підлягає негайній заміні** відповідно до BLOCKER-1.

### 3.2 Відсутній Secure Element

Поточна архітектура не використовує зовнішнього Secure Element або Trust Platform Module (TPM). Ключ зберігається у звичайній Flash-пам'яті MCU, яка за замовчуванням (RDP Level 0) доступна через JTAG/SWD.

**Цільова архітектура (майбутній цикл):**

```
Factory Flashing:
  Rails Backend → POST /api/v1/provisioning/register → {device_uid, unique_key}
  ST-Link/SWD → Flash unique_key до захищеної зони → RDP Level 2 Lock

Alternatively:
  ATECC608B Secure Element → ключ ніколи не покидає чіп
  STM32WLE5JC ↔ ATECC608B через I²C → підпис/шифрування без expose ключа
```

---

## 🎲 4. Генерація Вектора Ініціалізації (IV)

### 4.1 Soldier: IV відсутній (ECB Mode)

Soldier використовує ECB — цей режим не потребує IV. `pInitVect = NULL` при ініціалізації `MX_CRYP_Init()`.

### 4.2 Queen: HRNG IV для CBC Batch (Flush_Cache_To_Rails)

**Джерело ентропії:** Апаратний RNG (HRNG) STM32WLE5JC — базується на тепловому шумі аналогової периферії.

```c
uint32_t batch_iv[4];                   // 128-бітний IV (4 × 32-бітних слова)

hrng.Instance = RNG;
HAL_RNG_Init(&hrng);                    // Ініціалізуємо апаратний RNG

for (uint8_t i = 0U; i < 4U; i++) {
    if (HAL_RNG_GenerateRandomNumber(&hrng, &batch_iv[i]) != HAL_OK) {
        // Fallback при відмові HRNG (⚠️ — слабка ентропія):
        batch_iv[i] = HAL_GetTick() ^ (i * 0x5A5A5A5AUL);
    }
}

HAL_RNG_DeInit(&hrng);                  // Де-ініціалізація: нульове споживання у сні

hcryp.Init.pInitVect = batch_iv;        // Встановлюємо IV у крипто-модуль
HAL_CRYP_Init(&hcryp);                  // Оновлюємо конфігурацію CRYP

// IV передається перед зашифрованими даними:
memcpy(encrypted_batch_buffer, batch_iv, 16);               // Prepend IV
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)binary_batch_buffer,
                 padded_size / 4,
                 (uint32_t*)(encrypted_batch_buffer + 16),   // Ciphertext після IV
                 2000);
```

**Характеристики IV:**

| Параметр | Значення |
|----------|---------|
| Розмір | 128 біт (4 × uint32_t) |
| Джерело | HRNG (тепловий шум) — при успіху |
| Fallback | `HAL_GetTick() ^ (i * 0x5A5A5A5AUL)` — при відмові HRNG |
| Унікальність | Новий IV на кожен батч-флашинг (не перевикористовується) |
| Передача | Prepend до ciphertext: `[IV:16][Encrypted:N×16]` |

### 4.3 Queen: CBC IV для CoAP Command Downlink (Handle_CoAP_Command)

IV надходить від Rails Backend як перші 16 байтів payload:

```c
uint32_t cmd_iv[4];
memcpy(cmd_iv, payload, 16);           // Витягуємо IV з перших 16 байтів

hcryp.Init.Algorithm = CRYP_AES_CBC;
hcryp.Init.pInitVect = cmd_iv;
HAL_CRYP_Init(&hcryp);

HAL_CRYP_Decrypt(&hcryp, (uint32_t*)(payload + 16), ...);  // Дешифруємо після IV
```

---

## 🔄 5. Діаграма Криптографічного Пайплайну

```
SOLDIER (STM32WLE5JC)
──────────────────────────────────────────────────────
Phase 2: Pack Payload
  lora_payload[16] = [DID:4][Vcap:2][Temp:1][Acoustic:1]
                     [ΔT:2][Growth:1][TTL:1][FW:2][PAD:2]

Phase 4: Encrypt & TX
  HAL_CRYP_Encrypt(ECB, lora_payload, 4 words, encrypted_payload)
  Radio.Send(encrypted_payload, 16)
         │
         │ LoRa 868 MHz (AES-256-ECB, 16 bytes, no IV, no MAC)
         ▼
QUEEN (STM32WLE5JC)
──────────────────────────────────────────────────────
Main Loop: RX & Decrypt
  HAL_CRYP_Decrypt(ECB, incoming_lora_payload, 4 words, decrypted_payload)
  Process_And_Cache_Data(DID, decrypted_payload, rssi)

CIFO Cache (50 entries max)
  [DID | Vcap | Temp | Acoustic | ΔT | Growth | RSSI | FW]

Flush_Cache_To_Rails():
  1. Pack to binary_batch_buffer (50 × 21 bytes = 1050 bytes)
  2. Pad to multiple of 16: padded_size
  3. Generate IV via HRNG (4 × HAL_RNG_GenerateRandomNumber)
  4. hcryp → CBC mode, pInitVect = batch_iv
  5. encrypted_batch_buffer = [IV:16][CBC-Encrypted:padded_size]
  6. AT+CCOAPSEND → SIM7070G → CoAP PUT /telemetry/batch/QUEEN-001
  7. Restore: hcryp → ECB mode, pInitVect = NULL
         │
         │ CoAP/UDP (AES-256-CBC, [IV:16][Ciphertext:N×16])
         │ via SIM7070G → Starlink/LTE → Rails Backend
         ▼
RAILS BACKEND
  TelemetryUnpackerService.decrypt_and_parse(payload)
         │
         │ CoAP Downlink (AES-256-CBC, [IV:16][Ciphertext])
         ▼
Handle_CoAP_Command():
  1. cmd_iv = payload[0..15]
  2. hcryp → CBC mode, pInitVect = cmd_iv
  3. HAL_CRYP_Decrypt(CBC, payload+16, ...)
  4. Route: CMD:* → Actuator | 0x99 → OTA assembly
  5. Restore: hcryp → ECB mode, pInitVect = NULL
```

---

## 📊 6. Зведена Таблиця Криптографічних Каналів

| Канал | Алгоритм | Режим | IV / Nonce | MAC/MIC | Примітка |
|-------|----------|-------|-----------|---------|---------|
| **Soldier → Queen** (LoRa, 16B) | AES-256 | ECB | ❌ Відсутній | ❌ Відсутній | ⚠️ Replay вразливість |
| **EwsAlert / Panic → Queen** (LoRa, 16B) | AES-256 | ECB | ❌ Відсутній | ❌ Відсутній | ⚠️ Критичні пакети без автентифікації |
| **Queen → Rails** (CoAP Batch) | AES-256 | CBC | ✅ HRNG (128-bit) | ❌ Відсутній | IV prepend |
| **Rails → Queen** (CoAP Command) | AES-256 | CBC | ✅ Від Backend | ❌ Відсутній | IV в перших 16 байтах |
| **Queen → Soldier** (OTA LoRa) | AES-256 | ECB | ❌ Відсутній | ❌ Відсутній | ⚠️ Прошивка без автентифікації |

---

## ⚡ 7. Відновлення Стану CRYP (ECB Restoration Pattern)

Queen динамічно перемикається між ECB та CBC в залежності від операції. Після кожної CBC-операції модуль явно відновлюється до ECB:

```c
// Після Flush_Cache_To_Rails() (CBC → ECB):
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);

// Після Handle_CoAP_Command() (CBC → ECB):
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);
```

Це виправлено (`[FIX: CRITICAL — ECB Restoration]`). Без цього виправлення всі наступні `HAL_CRYP_Decrypt()` від Солдатів повертали сміття, що призводило до втрати всієї телеметрії до наступного перезапуску Queen.

---

## 🧪 8. Тестове Покриття (Host-Based Tests)

| Тест | Файл | Покриття |
|------|------|---------|
| AES-256 block encrypt/decrypt round-trip | `firmware/test/test_queen_logic.c` | ✅ ECB single-block |
| CBC batch encrypt + IV prepend | `firmware/test/test_queen_logic.c` | ✅ Часткове |
| Emergency TX format | `firmware/test/` | ⚠️ Не верифіковано |
| HRNG fallback behavior | Відсутній | 🔴 Не покрито |
| Key hardcoding detection | Відсутній | 🔴 Не покрито |

**Загальний статус:** 137 host-based тестів проходять (`make -C firmware/test`). Але тестове покриття **криптографічного пайплайну** є неповним — зокрема HRNG fallback та EwsAlert panic TX не тестуються.

---

## 🔗 9. Пов'язані Ресурси

| Ресурс | Опис |
|--------|------|
| `firmware/soldier/main.c:60-67` | Оголошення `hcryp`, `hrng`, `aes_key` |
| `firmware/soldier/main.c:741-748` | `MX_CRYP_Init()` Soldier |
| `firmware/soldier/main.c:458` | `HAL_CRYP_Encrypt` Phase 4 TX |
| `firmware/soldier/main.c:477` | `HAL_CRYP_Decrypt` Mesh RX |
| `firmware/soldier/main.c:720` | `HAL_CRYP_Encrypt` Emergency TX |
| `firmware/queen/main.c:65-66` | Hardcoded `aes_key` (ідентичний Soldier) |
| `firmware/queen/main.c:247` | `HAL_CRYP_Decrypt` LoRa RX |
| `firmware/queen/main.c:493-576` | `Flush_Cache_To_Rails()` CBC batch encrypt |
| `firmware/queen/main.c:632-662` | `Handle_CoAP_Command()` CBC decrypt + ECB restore |
| `firmware/queen/main.c:770-782` | `MX_CRYP_Init()` Queen |
| `app/services/telemetry_unpacker_service.rb` | Rails-сторона дешифрування батча |
| [03_01 Firmware Lifecycle](03_01_Firmware_Lifecycle_and_DMA) | Фази 0-5, RTC, IWDG, Hardcoded Key BLOCKER |
| [04_02 Business Logic](04_02_Business_Logic_and_Services) | TelemetryUnpackerService, ActuatorCommandWorker |
| `POST /api/v1/provisioning/register` | Майбутній endpoint для унікального provisioning |

---

## 📋 10. Резюме Аудиту Безпеки

| Категорія | Стан | Деталі |
|-----------|------|--------|
| **Алгоритм** | ✅ AES-256 | Відповідає FIPS 197, NIST SP 800-38A |
| **Розмір ключа** | ✅ 256 біт | Відповідає Gaia 2.0 Standard |
| **Апаратне прискорення** | ✅ STM32 AES Block | Без програмної крипто-бібліотеки |
| **CBC IV для CoAP** | ✅ HRNG (тепловий шум) | Унікальний IV на кожен батч |
| **Зберігання ключа** | 🔴 Flash (hardcoded) | КРИТИЧНО: потрібен Secure Element або provisioning |
| **Унікальність ключа** | 🔴 Спільний для всіх вузлів | КРИТИЧНО: one-key compromise = total network compromise |
| **ECB для LoRa** | 🔴 Детермінований | Вразливий до pattern analysis та replay attack |
| **MAC/MIC** | 🔴 Відсутній | Немає автентифікації жодного LoRa-пакета |
| **RDP Protection** | ❓ Невідомо | Потрібна верифікація активації RDP Level 2 |
| **Key Rotation** | 🔴 Відсутній | Неможливий без повної перепрошивки |
| **HRNG Fallback** | 🟡 Слабкий | HAL_GetTick() — передбачуваний при відмові HRNG |
