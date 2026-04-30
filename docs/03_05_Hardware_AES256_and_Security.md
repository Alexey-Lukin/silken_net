# 03_05: Апаратний AES-256 та Безпека (Криптографія Пакетів)

---

## 🎯 Мета

Зафіксувати детальний криптографічний пайплайн вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор): режим роботи AES, структуру зашифрованих пакетів, управління ключами та генерацію вектора ініціалізації (IV). Документ є SSOT для Hardware Security Audit перед масовим виробничим розгортанням.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — апаратне шифрування налаштовано, 137 host-based тестів проходять
- **Пов'язані модулі:**
  - Життєвий Цикл Прошивки та DMA → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)
  - Прошивка Шлюзу Королеви → [`03_02_Queen_Gateway_Firmware`](03_02_Queen_Gateway_Firmware)
  - mruby Атрактор Лоренца → [`03_04_mruby_Lorenz_Attractor`](03_04_mruby_Lorenz_Attractor)
  - Бізнес-Логіка та Сервіси → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Proof of Growth Pipeline → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)

---

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
| **ECB Mode для Soldier ↔ Queen (відсутність IV)** | 🔴 BLOCKER (рекомендовано AES-256-CCM з 24-байтним пакетом) |
| **Відсутність MAC/MIC для LoRa-пакетів** | 🔴 BLOCKER (вирішується CCM — апаратний MIC + Frame Counter) |
| **HRNG Fallback — передбачуваний seed** | ✅ Виправлено (djb2 STM32 HW UID XOR tick — унікальний на кожній Queen) |
| **Відсутність ротації ключів (Key Rotation)** | 🟡 OPEN (рекомендовано Hash Ratchet KDF — PFS без передачі ключа) |
| **Ідентичний ключ Soldier та Queen (симетрія при прошивці)** | 🔴 BLOCKER (єдина точка компрометації + операційний ризик мовчазної втрати телеметрії при мисматчі) |

---

## 🛑 Блокери

---

### 🔴 BLOCKER-1: Hardcoded AES-256 Key у Flash-пам'яті (Ідентичний на всіх вузлах)

**Статус:** Відкрито. **Критичний ризик безпеки для масового виробництва.**

**Файли:** `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:81-82`

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

**Необхідна дія (рекомендоване рішення — AES-256-CCM):**

Найефективніший шлях вирішення BLOCKER-2 та BLOCKER-3 одночасно — перехід на **AES-256-CCM** (Counter with CBC-MAC), який **апаратно підтримується STM32WLE5JC** (`CRYP_AES_CCM` у HAL). CCM надає конфіденційність + автентифікацію + захист від replay в одній операції.

**Нова структура 24-байтного LoRa-пакета (замість поточних 16-байтних):**

```
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 0 | Byte 1 | Byte 2 | Byte 3 | Byte 4 | Byte 5 | Byte 6 | Byte 7 |
|       DID (Device ID, 4 байти)     |    Сенсорні дані (8 байтів)       |
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 8 | Byte 9 |Byte 10 |Byte 11 |Byte 12 |Byte 13 |Byte 14 |Byte 15 |
|    ...сенсорні дані...    | Frame Counter (4 байти, Nonce для CCM)     |
+--------+--------+--------+--------+--------+--------+--------+--------+
|Byte 16 |Byte 17 |Byte 18 |Byte 19 |Byte 20 |Byte 21 |Byte 22 |Byte 23 |
|        MIC (4 байти, AES-CCM MAC)  |         Зарезервовано              |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

- **Frame Counter (4B):** Зберігається в RTC Backup Domain (наприклад, `RTC_BKP_DR1`). Інкрементується при кожній відправці. Використовується як Nonce для AES-CCM. Queen запам'ятовує останній Frame Counter для кожного DID. Якщо приходить пакет з меншим або рівним лічильником — це **Replay Attack**, пакет ігнорується.
- **MIC (4B):** Message Integrity Code, апаратно генерується AES-CCM. Захищає від **Bit-flip та Injection** атак.

**Конфігурація `hcryp` для CCM:**
```c
hcryp.Init.Algorithm = CRYP_AES_CCM;
// Nonce формується з DID (4B) + Frame Counter (4B) + padding
```

> **Примітка:** 24-байтний пакет збільшує LoRa airtime на ~50% порівняно з 16B, але залишається в межах duty-cycle бюджету (< 1% при DR2 SF10, 868 МГц). Детальний розрахунок airtime — в 03_01.

**Альтернативні рішення (якщо CCM не підтвердиться при тестуванні):**
- **AES-256-GCM** — аналогічно CCM, але може не підтримуватися апаратно на всіх ревізіях STM32WLE5.
- **AES-256-CTR + окремий HMAC-SHA256 MIC** — потребує більше коду, але гнучкіше.
- **Збереження ECB + 4-байтний HMAC суфікс** — мінімальні зміни, але без захисту від pattern analysis.

Рішення архітектурно узгодити з [03_01 Firmware Lifecycle](03_01_Firmware_Lifecycle_and_DMA) та [04_02 Business Logic](04_02_Business_Logic_and_Services).

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

- **Рекомендоване рішення:** Перейти на **AES-256-CCM** з 24-байтним пакетом — вирішує BLOCKER-2 та BLOCKER-3 одночасно (див. BLOCKER-2 вище для повної специфікації 24-байтного формату з Frame Counter + MIC).
- Альтернатива: **AES-256-GCM** (надає одночасно конфіденційність + автентифікацію + nonce). Це найбільш ефективне рішення для обмежених STM32-ресурсів.
- Або: додати **HMAC-SHA256 MIC** (4 байти суфіксу) до кожного LoRa-пакету, скоротивши сенсорний payload до 12 корисних байтів.
- LoRaWAN також забезпечує MIC через AES-128-CMAC — розглянути перехід на LoRaWAN замість сирого LoRa.

**Блокує:** Довіра до телеметрії, Proof of Growth Pipeline (05_02), Hardware Security Audit.

---

### ✅ BLOCKER-4: HRNG Fallback — покращена ентропія (Виправлено)

**Статус:** Виправлено (PR #273).

**Реалізація:** Fallback тепер використовує djb2 хеш STM32 HW UID (унікальний для кожного чіпу, `0x1FFF7590`) XOR `HAL_GetTick()` з bit-shift для кожного слова IV:

```c
// djb2 hash of STM32 HW UID (unique per chip)
uint32_t uid_hash = djb2_hash((uint8_t*)0x1FFF7590, 12);
// i ∈ {0,1,2,3}: shift забезпечує різні слова IV
batch_iv[i] = uid_hash ^ (HAL_GetTick() << (i * 8)) ^ (i * RNG_FALLBACK_XOR_MASK);
```

Оскільки STM32 HW UID унікальний для кожної Queen, навіть при масовому blackout-відновленні (всі Queens перезавантажились одночасно) IV будуть різними для кожного пристрою — IV Reuse Attack унеможливлена на рівні fallback.

---

### 🟡 BLOCKER-5: Відсутній Механізм Ротації Ключів (Key Rotation)

**Статус:** Відкрито. Системна проблема при масштабуванні.

**Контекст:** Поточна архітектура передбачає єдиний статичний ключ, зашитий при Factory Flashing. Немає механізму зміни ключа без повної перепрошивки через OTA або фізичного доступу.

**Ризики:**

1. **Long-term Key Exposure:** Якщо ключ скомпрометовано (наприклад, через фізичний злам одного вузла + зчитування Flash), всі минулі записані LoRa-пакети можуть бути ретроспективно дешифровані (відсутнє Perfect Forward Secrecy).
2. **Регуляторна невідповідність:** GDPR, ISO 27001 та NIST SP 800-57 вимагають ротацію криптографічних ключів. При масштабуванні до публічного продукту NaaS це може стати юридичним блокером.
3. **OTA як вектор атаки:** Якщо OTA-канал не має власного механізму ключ-обміну, оновлення нового ключа через OTA саме по собі шифрується старим (скомпрометованим) ключем.

**Необхідна дія:**

- **Рекомендоване рішення — Hash Ratchet (Key KDF) для Perfect Forward Secrecy:**

  Передавати новий ключ через ефір (навіть зашифрованим старим ключем) — погана практика: якщо `K_old` скомпрометовано, `K_new` автоматично теж. Замість цього використовувати **синхронну деривацію** на обох кінцях без передачі самого ключа:

  1. Сервер надсилає CoAP-команду: `CMD:ROTATE_KEY:<UUID>` (команда, не ключ!).
  2. Queen пересилає команду через OTA-broadcast або цільовий downlink Солдату.
  3. Soldier та Queen **одночасно** проганяють поточний ключ через криптографічну хеш-функцію (або AES в режимі KDF, оскільки на борту вже є апаратний AES):

  ```c
  // Псевдокод Hash Ratchet (in-place деривація):
  HAL_CRYP_Encrypt(&hcryp, current_aes_key, 8, next_aes_key, 1000);
  memcpy(current_aes_key, next_aes_key, 32);
  // Запис нового ключа у Flash/RTC Backup Domain
  ```

  **Переваги Hash Ratchet:**
  - Ключ ніколи не передається по мережі → навіть при перехопленні `CMD:ROTATE_KEY` зловмисник не отримує жодної інформації про новий ключ.
  - **Perfect Forward Secrecy:** Якщо ключ коли-небудь скомпрометують фізично (витяг з Flash), атакуючий **не зможе** розшифрувати старі пакети, перехоплені раніше (бо попередній ключ вже знищено).
  - Мінімальний обчислювальний overhead: одна AES-операція при ротації.
  - Cluster-wide активація через confirmation ACK від усіх вузлів кластера.

- Альтернатива: **ECDH/Curve25519** key exchange при provisioning (складніше, але дозволяє незалежну ротацію).
- **Передумова:** FW.1 (per-device provisioning) має бути реалізований першим.

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
- **При помилці `HAL_CRYP_Init()` — виконати жорсткий апаратний скид (RCC Reset) криптопериферії:**

  ```c
  hcryp.Init.Algorithm = CRYP_AES_ECB;
  hcryp.Init.pInitVect = NULL;

  if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
      // Жорсткий апаратний скид крипто-блоку через регістри RCC
      __HAL_RCC_CRYP_FORCE_RESET();
      __HAL_RCC_CRYP_RELEASE_RESET();

      // Повторна ініціалізація після апаратного reset
      if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
          Error_Handler(); // Або NVIC_SystemReset() — повний перезапуск MCU
      }
  }
  ```

  **Логіка:** `__HAL_RCC_CRYP_FORCE_RESET()` скидає всі регістри периферійного блоку AES у стан після Power-On Reset. Це єдиний спосіб відновити "зависший" апаратний блок без перезавантаження всього MCU.

- Додати watchdog або перевірку стану `hcryp.State` перед кожним `HAL_CRYP_Encrypt/Decrypt`.

**Блокує:** Надійність криптографічного пайплайну Queen при апаратних збоях.

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

**CoAP URI:** `PUT /telemetry/batch/<QUEEN_UID>` (queen_uid читається з Flash — Flash-provisioned або `"UNPROV-{HEX}"` через STM32 HW UID)

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
> ⚠️ **Увага:** Аудит виявив, що перші 4 слова ключа збігаються зі стандартним тестовим ключем AES-128 з FIPS-197 (Appendix B) — загальновідомими тестовими векторами. Точні значення навмисно не публікуються в цьому документі. Для аудиту безпеки — дивись `firmware/soldier/main.c:66-67` та `firmware/queen/main.c:81-82`. Ключ **підлягає негайній заміні** відповідно до BLOCKER-1.

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

### 3.3 Апаратний Захист Flash (STM32 RDP — Readout Protection)

Інженери STMicroelectronics вбудували захист ключів безпосередньо в кремній. Механізм **RDP (Readout Protection)** налаштовується не в коді, а в **Option Bytes** — апаратних регістрах конфігурації чіпа, які зберігаються окремо від Flash і оновлюються через STM32CubeProgrammer.

| Рівень | Назва | Захист | Використання |
|--------|-------|--------|-------------|
| **RDP Level 0** | Відкритий (за замовчуванням) | Відсутній — Flash читається через SWD без обмежень | Розробка та налагодження |
| **RDP Level 1** | Захист виробництва | SWD заблоковано для зчитування. При спробі зняти — **чіп апаратно і миттєво стирає всю Flash та SRAM** | Масова партія (рекомендовано) |
| **RDP Level 2** | Абсолютний моноліт ("Drifting Ice") | Інтерфейс SWD фізично вимикається всередині кристала **назавжди** (необоротно). Перепрошивка можлива лише через OTA по радіо | Фінальне виробниче розгортання |

> **Про назву "Drifting Ice":** авторська метафора проєкту — чіп стає "крижиною, що дрейфує у вічній мерзлоті": повністю ізольований, але живий. Офіційна назва STM32: **RDP Level 2 (Permanent Protection)**.

**Ключові властивості RDP Level 1:**
- При підключенні програматора та спробі зчитати Flash → чіп автоматично стирає все → ключ знищується до того, як зловмисник його побачить
- Перепрошивка через SWD **залишається можливою** (тільки запис, не читання) — зручно для сервісних оновлень

**Ключові властивості RDP Level 2:**
- SWD інтерфейс фізично вимикається в кремнії назавжди — навіть виробник не може його відновити
- Єдиний спосіб оновлення прошивки — OTA через LoRa (`OtaPackagerService` → Queen → Soldier)
- Використовувати лише після повного відлагодження прошивки та підтвердження OTA-механізму

**Як активувати через STM32CubeProgrammer:**
```
Device Memory → Option Bytes → Read Out Protection → RDP: Level 1 (або Level 2) → Apply
```
> **⚠️ Незворотність RDP Level 2:** Активація RDP Level 2 — це одностороння дія. Після неї чіп стає чорним ящиком. Переконайся, що OTA-механізм повністю протестований **до** активації.

**Поточний стан (Reverse Shaping аудит):** RDP Level 0 — відкрито для розробки. Перехід на Level 1 є фінальним кроком перед відправкою першої партії в ліс.

---

### 3.4 Стратегія Масового Виробництва (Factory Flashing Pipeline)

При переході від прототипу до партії 10 000+ вузлів конвеєр на заводі виглядає так:

```
[Завод]
  1. Прошивка: масив aes_key[8] = {0,0,...,0} (порожній placeholder)
     Robot Programmer → Flash firmware → Board

  2. Provisioning: унікальний ключ для конкретного MCU
     Rails Backend → POST /api/v1/provisioning/register → {device_uid}
     Backend → генерує unique_key (HKDF від master_key + device_uid)
     Robot → записує unique_key у захищений сектор Flash

  3. Lock: апаратне блокування
     STM32CubeProgrammer (CLI) → Set RDP Level 1 (або Level 2)
     → необоротне блокування SWD зчитування

  4. Пакування
     Нанести лак → Встановити магніт Shipping Mode → Пакет → Ліс
```

**Переваги цієї схеми:**
- Компрометація одного Солдата не розкриває ключі сусідів (per-device HKDF)
- Фізичне вилучення ключа з чіпа неможливе після RDP Lock
- Ключ ніколи не існує в коді репозиторію — лише в Rails Vault (`HardwareKey`, encrypted at rest)

**Для поточного прототипу (TRL 6):** hardcoded ключ залишається правильним вибором — він економить тижні часу на інфраструктуру Provisioning. Перехід до per-device provisioning — після підтвердження архітектури в полі.

---

### 3.5 Режим Транспортування — Shipping Mode (Геркон / Reed Switch)

**Проблема:** Між заводом та лісом Солдат лежить у коробці тижнями. Якщо він прокинеться від вібрації під час перевезення — марно витратить енергію іоністора (якого може не вистачити для першого TX).

**Рішення — Shipping Mode на основі геркону (магнітного датчика):**

```
[Коробка]  Магніт прикріплений до корпусу → STM32 фізично відключений від живлення
                         ↓
[Монтажник у лісі]  Забиває анкер → Сканує QR-код → Знімає магніт
                         ↓
[Перший вдих] Солдат стартує main.c → реєструється на сервері → ліс "прокидається"
```

**Апаратна реалізація:**
- Компонент: **геркон (reed switch)** — копійчаний магнітний датчик (нормально-розімкнений або нормально-замкнений)
- Підключення: між лінією живлення (`VBAT`) та MCU через P-MOSFET або між GND та `ENABLE` піном DC-DC конвертора
- Логіка: поки магніт **притиснутий** → ланцюг розімкнений → живлення відсутнє → нульове споживання
- Зрив магніту → контакти замикаються → MCU отримує живлення → `main()` стартує

**Переваги:**
- Нульове споживання під час транспортування (фізичний розрив кола)
- Простота: 1 компонент, ~$0.05/шт, без програмного коду
- Маркетингова цінність: "The node takes its first breath the moment the anchor enters the tree"

**Додати до BOM Солдата:** геркон (наприклад, Hamlin 59140-1-T-00-A або аналог) + N52 неодимовий магніт ∅6×3 мм.

---

### 3.6 Процедура активації RDP Level 2 (необоротна) 🤖

**Cross-ref:** [10_02 SEC.2](10_02_Action_Plan_Tracker), §3.3 «Апаратний Захист Flash».

> ⚠️ **Активація RDP Level 2 — одностороння, незворотна дія.** Після `Apply` чіп фізично втрачає SWD інтерфейс назавжди. Цю процедуру виконують **тільки** після того, як OTA-пайплайн повністю верифікований у полі.

**Pre-flight checklist (обов'язково ДО натискання Apply):**

- [ ] OTA flow end-to-end протестований: `OtaPackagerService` → CoAP downlink → Queen broadcast → Soldier Flash write → magic check `0x45544952` ("RITE") → reboot → нова прошивка живе у `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`.
- [ ] OTA verification: щонайменше **2 успішні цикли** оновлення на тому ж пристрої (не лише бенчмарки).
- [ ] OTA rollback тестований: якщо новий bytecode falls back до embedded `lorenz_bytecode[]` при corrupt magic.
- [ ] Provisioning HKDF flow завершено (BLOCKER-1 mitigation): унікальний `aes_key` записано в protected sector, master_key генерується HRNG (не FIPS-197 test vector).
- [ ] FW.2 (CCM) integrated: інакше після RDP-2 вже не можна «полагодити» AES-ECB вразливість через SWD reflash.
- [ ] Watchdog (IWDG) тестовано: якщо firmware зависає, IWDG перезавантажує MCU без SWD (BLOCKER-6 в `02_05` ✅).
- [ ] Final firmware version task-snapshot задокументовано у `RELEASE_VERSION` ENV (Sentry release tracking) та git tag `vX.Y.Z`.
- [ ] Spare batch (≥10 одиниць) залишено на RDP Level 1 для in-field troubleshooting (RDP-1 дозволяє стирати+перепрошивати, але не зчитувати → ключ безпечний).

**Послідовність активації (per device, factory line):**

```bash
# 1. Final firmware flash (тестова прошивка вже видалена)
STM32_Programmer_CLI -c port=SWD freq=4000 \
    -d firmware/soldier/build/soldier.bin 0x08000000 \
    -v

# 2. Provisioning: записати unique_aes_key через protected sector
#    (тимчасово RDP=0, ключ деривується HKDF(master_key, device_uid))
STM32_Programmer_CLI -c port=SWD \
    -d provisioning/<device_uid>.key 0x0803E000 \
    -v

# 3. Burn Option Bytes: PCROP лок на сектор з ключем (опційно — додатковий бар'єр)
STM32_Programmer_CLI -c port=SWD \
    -ob PCROP1A_STRT=0x0803E000 PCROP1A_END=0x0803EFFF PCROP_RDP=DISABLE

# 4. Активація RDP Level 1 (дозволяє sanity check у полі)
STM32_Programmer_CLI -c port=SWD -ob RDP=0xBB
# Очікуваний результат: наступний Read-Out → масове стирання Flash + SRAM

# 5. Smoke test: чи MCU bootує? чи telemetry виходить через LoRa? чи приймається OTA?
#    (24-годинне burn-in у camera оточення з симульованим ENV)

# 6. ✋ STOP — рішення про RDP-2 ухвалюється офіційно (Engineering signoff)
#    На цьому етапі ще можна перепрошити через SWD (RDP-1 = write-allowed)

# 7. Активація RDP Level 2 — НЕЗВОРОТНО
STM32_Programmer_CLI -c port=SWD -ob RDP=0xCC
# ⚠️ ВСЕ. SWD назавжди вимкнений. Перепрошивка лише через OTA.
```

**Recovery options після RDP-2:** **жодних.** SWD інтерфейс фізично відключений у кремнії. Якщо OTA зламається → пристрій — електронне сміття. Тому checklist вище — обов'язковий.

**Поетапний rollout (рекомендовано):**

| Етап | RDP Level | Кількість | Призначення |
|------|-----------|-----------|-------------|
| Прототип / R&D | Level 0 | ~50 | Розробка, дебаг, SWD доступ |
| Field pilot (пілотний ліс) | Level 1 | 100–500 | Field sanity, OTA verification, recovery still possible |
| Mass production batch | Level 2 | 10,000+ | **Тільки** після ≥3 місяців stable OTA на Level-1 партії |

**Документ-tracker:** після кожного batch активації — оновити `docs/10_02` SEC.2 (👤 — secrets / process).

---

### 3.7 ATECC608B Secure Element — оцінка інтеграції 🤖

**Cross-ref:** [10_02 SEC.6](10_02_Action_Plan_Tracker), §3.2 «Відсутній Secure Element».

**Контекст:** навіть з RDP Level 2, key extraction теоретично можливий через **side-channel attacks** (DPA, EM analysis) або **fault injection** (voltage/clock glitching). Для batches > 1000 одиниць — це attractive target. Виділений Secure Element зберігає ключ у tamper-resistant ASIC з вбудованим detection.

**Кандидат: Microchip ATECC608B**

| Параметр | Значення |
|----------|----------|
| Інтерфейс | I²C (стандартний 100/400 кГц) або SWI (1-pin) |
| Slot capacity | 16 slots × 32–72 байти |
| Криптографія | ECC P-256, ECDH, ECDSA, AES-128, SHA-256, HMAC, KDF |
| Корпус | UDFN-8, SOIC-8 |
| Споживання | ~14 mA active, ~150 nA sleep |
| Робочий діапазон | −40 … +85°C ✅ (industrial) |
| Tamper-resistance | Active shield, voltage/temp/glitch detectors |
| Ціна (10k MOQ) | ~$0.60–0.80/unit |
| Datasheet | [DS40002239](https://www.microchip.com/atecc608b) |

**Архітектура інтеграції з STM32WLE5JC:**

```
                   ┌──────────────────────┐
                   │   STM32WLE5JC        │
                   │                      │
                   │   I²C1 (PB6/PB7)     │◀──┐
                   └────────┬─────────────┘   │
                            │                  │
                       I²C │ + GND, VCC        │
                            ▼                  │
                   ┌──────────────────────┐    │
                   │   ATECC608B          │    │
                   │                      │    │
                   │   Slot 0: AES key    │    │
                   │   Slot 1: ECC priv   │    │
                   │   Slot 2: device cert│    │
                   │   Slot 3: master HMAC│    │
                   └──────────────────────┘    │
                                                │
                   Provisioning через Backend  │
                   (один раз, на заводі) ──────┘
```

**Slot mapping (рекомендований):**

| Slot | Тип | Призначення | Read | Write |
|------|-----|-------------|------|-------|
| 0 | AES-128 key | LoRa Soldier↔Queen sym key | ❌ never | One-time (factory) |
| 1 | ECC P-256 private | Device identity (peaq DID signing) | ❌ never | One-time (factory) |
| 2 | Public key cert | X.509 device cert | ✅ open | Factory |
| 3 | HMAC-SHA256 key | OTA image HMAC verification (FW.23) | ❌ never | One-time |
| 4–15 | Reserved | Future use (key rotation, new chains) | — | — |

**Ключові переваги перед RDP Level 2 (наявні):**

| Аспект | RDP Level 2 (поточне рішення) | + ATECC608B |
|--------|-------------------------------|-------------|
| Key storage | MCU Flash (SWD off) | Окремий ASIC (tamper-evident) |
| Side-channel resistance | Слабка (стандартний CMOS) | DPA-resistant by design |
| Glitch attacks | Mitigated через RDP-2 | Detected → ASIC self-erase |
| Key never exposed | ❌ Ключ в MCU SRAM під час `HAL_CRYP_Init()` | ✅ Шифрування виконується **всередині** ATECC; MCU отримує лише ciphertext |
| ECDSA/ECDH support | Software (slow on Cortex-M4) | Hardware accelerator (~50 мс/sign) |
| Cost impact | $0 | +$0.60/unit (10k MOQ) |

**API integration sketch (firmware):**

Заміна `HAL_CRYP_AESECB_Encrypt(...)` на ATECC608B-driven:

```c
// Замість HAL_CRYP_AESECB_Encrypt():
atca_status_t status = atcab_aes_encrypt(
    /*key_id=*/ 0,           // Slot 0
    /*key_block=*/ 0,
    plaintext,
    ciphertext
);
// Затримка: ~1.5 мс per block (vs ~10 µs HAL_CRYP) — прийнятно для 16-байтних LoRa пакетів
```

**Latency impact:** ATECC608B AES-ECB ~1.5 мс/блок vs ~10 µs MCU HAL_CRYP. Для одного 16-байтного LoRa пакету — нехтовно. Для CBC batch (50 × 16 байт = 800 байт) — додаткові ~75 мс на flush — **прийнятно** (CoAP flush триває кілька сек у будь-якому разі).

**Power impact:**
- Active (1.5 мс): 14 мА × 3.3V = 46 мВт. На 1 LoRa пакет → ~70 мкДж.
- Sleep: 150 нА (нехтовно у бюджеті Soldier `E_sleep ≈ 1.5 мкА`)
- За 1 хв (1 wakeup) → +0.1% до total energy budget. ✅

**Footprint (PCB):**
- UDFN-8: 2×3 мм
- SOIC-8: 4×5 мм
- I²C: 2 GPIO (PB6/PB7) + 2 pull-ups (4.7 kΩ × 2)
- Загалом: ~3% PCB area для Soldier (KiCad layout у HW.9)

**Альтернативи:**

| Чіп | Виробник | Особливості | Висновок |
|-----|----------|-------------|----------|
| **ATECC608B** | Microchip | Зрілий ecosystem, ESP/STM32 libraries, AWS IoT default | ⭐ Рекомендовано |
| **STSAFE-A110** | STMicroelectronics | Same vendor як STM32 → unified toolchain (CubeMX), краща інтеграція | Сильна альтернатива |
| **OPTIGA Trust M** | Infineon | TPM 2.0 features, X.509 PKI heavy | Overkill для нашого use case |
| **NXP A71CH** | NXP | EOL announced 2024 | ❌ Не використовувати |

**Рекомендація:** ATECC608B або STSAFE-A110. Final pick — після завершення KiCad layout (HW.9) і перевірки I²C bus utilization (вже використовується для DS18B20 в `02_05` §4а?). STSAFE-A110 має невелику перевагу через native CubeMX-інтеграцію — економить ~3 дні firmware-розробки.

**Factory Flashing impact (cross-ref §3.4):**

При інтеграції ATECC608B пайплайн виглядає так:

```
[Завод]
  1. Reflow PCBA (ATECC608B запаяний, але config zone не locked)
  2. Power-up → STM32 talks to ATECC608B over I²C
  3. STM32 → backend: POST /api/v1/provisioning/register {device_uid}
  4. Backend → returns: {aes_key, ecc_keypair, cert_chain}
  5. STM32 → ATECC608B: write Slot 0 (AES), Slot 1 (ECC), Slot 2 (cert)
  6. STM32 → ATECC608B: LOCK config zone + data zone (irreversible на ASIC рівні)
  7. STM32CubeProgrammer → RDP Level 1 (на самому MCU)
  8. Final: пакування, shipping mode, лак
```

**Подвійний lock (defense in depth):**
- ATECC608B: data zone locked → ключі неможливо ні прочитати, ні переписати
- STM32 RDP Level 1/2: SWD заблоковано → firmware не можна змінити

**Дорожня карта:**

- [ ] 🤖 (наступний цикл) Завершити оцінку: ATECC608B vs STSAFE-A110 матриця, узгоджена з KiCad floorplan
- [ ] 🤖 Update §3.4 Factory Flashing pipeline з SE-варіантом
- [ ] 🤖 Інтеграція з Backend `Provisioning::HardwareKeyService` (генерація ECC keypair + cert)
- [ ] 🤖 Firmware HAL: drop-in replacement `Crypto_AES_Encrypt_Block()` що внутрішньо викликає ATECC або HAL_CRYP залежно від `#define USE_SECURE_ELEMENT`
- [ ] 👤 Замовити evaluation kit (Microchip ATECC608B-MAH-DAO або ST STSAFE-A110) для bench-test
- [ ] 👤 Прийняти final BOM рішення перед першим mass production batch (>1000 unit)

**Пріоритет:** P2 — для TRL 6/7 RDP Level 2 (§3.6) є достатнім захистом. Secure Element — обов'язковий перед mass production (>10 000 unit) або для high-value deployments (urban / commercial sites).

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
        // Fallback: djb2 хеш STM32 HW UID (унікальний per chip) XOR tick
        uint32_t uid_hash = djb2_hash((uint8_t*)0x1FFF7590U, 12U);
        batch_iv[i] = uid_hash ^ (HAL_GetTick() << (i * 8U)) ^ (i * RNG_FALLBACK_XOR_MASK);
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
| Fallback | `djb2(STM32_HW_UID) XOR (HAL_GetTick() << (i*8)) XOR XOR_MASK(i)` — унікальний на кожній Queen |
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
  6. AT+CCOAPSEND → SIM7070G → CoAP PUT /telemetry/batch/<queen_uid>
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
| `firmware/queen/main.c:81-82` | Hardcoded `aes_key` (ідентичний Soldier) |
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
| **ECB для LoRa** | 🔴 Детермінований | Рекомендовано: AES-256-CCM з 24-байтним пакетом (Frame Counter + MIC) |
| **MAC/MIC** | 🔴 Відсутній | Вирішується переходом на CCM (MIC апаратно генерується) |
| **RDP Protection** | 🟡 OPEN | Level 0 (розробка). Level 1/2 — фінальний крок Factory Flashing (розділ 3.3). Pre-flight checklist та незворотна процедура задокументовані у §3.6 🤖 |
| **Factory Flashing Pipeline** | 🟡 OPEN | Архітектура визначена (розділ 3.4), provisioning endpoint (`/api/v1/provisioning/register`) існує |
| **Shipping Mode (Геркон)** | 🟡 OPEN | Концепт визначено (розділ 3.5); компонент не доданий до BOM |
| **Secure Element (ATECC608B)** | 🟡 OPEN (P2) | Оцінка інтеграції завершена у §3.7 🤖 — рекомендовано перед mass production >10k unit; альтернатива STSAFE-A110 |
| **Key Rotation** | 🔴 Відсутній | Рекомендовано: Hash Ratchet KDF (PFS без передачі ключа по мережі) |
| **HRNG Fallback** | ✅ Виправлено | djb2(STM32_HW_UID) XOR tick — унікальний на кожній Queen (PR #273) |
