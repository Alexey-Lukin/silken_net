# 03_06: Factory Flashing та Provisioning Ключів (HKDF · K_seed · OTA-Auth)

---

## 🎯 Мета

Зафіксувати конвеєр **Factory Flashing** (масове виробництво) та повний протокол **provisioning ключів** вузлів Soldier/Queen: дві гілки фабрики (Protected Flash STM32 / Secure Element), HKDF-деривація per-device AES-ключів, Lorenz K_seed (SEC.11), OTA image authentication (FW.23 HMAC dual-gate) та operations-security threat model заводського каналу (SEC.3). Виокремлено з [`03_05 §3.4`](03_05_Hardware_Symmetric_Crypto_and_Security) (там лишаються крипто-режими/пакети/IV/SE050/ротація; тут — provisioning-підсистема).

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — backend provisioning + HKDF + K_seed + OTA-печатку Ed25519 реалізовано (host-тести зелені); фабрична Rake-CLI dry-run ✅. Відкрите: real `STM32_Programmer_CLI` + live SE05x/`sss` I²C на bench (SEC.3; SE = **SE050**, `cryptoauthlib` — ATECC-ери, superseded SEC.6), RDP Level 2 (SEC.2), bench OTA-печатки (FW.23) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Крипто-режими (AES CCM/CBC/ECB), пакети, IV, SE050 §3.7, ротація §3.8 — дім, з якого виокремлено |
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | RTC/Flash-KV мапа; сторінка Protected Flash публічного ключа печатки OTA (KPUB) |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | K_seed → (x₀,y₀,z₀) cold-start (§2.1) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `FactoryFlashing::*`, `HardwareKeyService`, `OtaPackagerService`, `OtaSealKeyService` |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Відкриті: SEC.2 RDP-2, SEC.3 factory bench, FW.23 bench OTA-печатки |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Стратегія Масового Виробництва (Factory Flashing Pipeline)](#1-стратегія-масового-виробництва-factory-flashing-pipeline)
- [2. HKDF Key Derivation Protocol Design](#2-hkdf-key-derivation-protocol-design-)
- [3. Lorenz K_seed Derivation (SEC.11)](#3-lorenz-k_seed-derivation-sec11-)
- [4. OTA Authentication Protocol Design (FW.23) ✅ Реалізовано (2026-05-02 · Ed25519-печатка — 2026-10-06)](#4-ota-authentication-protocol-design-fw23--реалізовано-2026-05-02--ed25519-печатка--2026-10-06)
- [5. Factory Flashing Operations Security 🤖 (SEC.3, 2026-05-17)](#5-factory-flashing-operations-security--sec3-2026-05-17)
<!-- TOC:AUTO:END -->

---

## 1. Стратегія Масового Виробництва (Factory Flashing Pipeline)

При переході від прототипу до партії 10 000+ вузлів конвеєр на заводі виглядає так. **Дві гілки:** (A) ключі у protected Flash sector STM32 (TRL 6/7, baseline), (B) = A + Secure Element SE05x, baseline SE051C2 (mass production > 10k / high-value urban — оцінка SE у 03_05 §3.7). **Post-SEC.14 (provisioning-only, 2026-07-03):** LoRa-ключ KEYL живе у Protected Flash в **обох** гілках; SE у Гілці B додає лише ідентичність/provisioning (Ed25519 «голос дерева», cert, anti-clone serial) — «Гілка A + identity-chip», graceful degradation (мертвий SE ≠ мертва телеметрія).

### Гілка A — Protected Flash Sector (TRL 6/7, baseline)

```
[Завод]
  0. Ідентичність (one-pass, FW.54): SWD-read 96-біт UID ДО прошивки
     STM32_Programmer_CLI -c port=SWD mode=UR -r32 0x1FFF7590 12  → три %08X-слова
     host деривує DID = murmur3-fmix32(UID) (03_01 §7; SilkenNet::DidDerivation)
     TreeResolver: Tree create / re-flash (паспорт silicon_uid_hex збігся) /
     bind (legacy без паспорта) / DID-колізія → QUARANTINE юніта

  1. Прошивка: масив aes_key[4] = {0,0,0,0} (порожній placeholder)
     Robot Programmer → Flash firmware → Board

  2. Provisioning: rake-тріо §5 (2-Person Rule) — ключі від ПРАВИЛЬНОГО DID
     factory:flash[UID,…] → approve → execute:
     Backend деривує unique_key (HKDF від master_key + DID; жоден ключ не
     летить мережею) → транскрипт, де кожен виклик CLI несе власний -c:
     -r32 UID-read (wrong-board guard: чужа плата = жодного -w32) → -e
     сторінок ключів → -w32 у Flash (0x0803E000) цілими doubleword'ами

  3. Lock: апаратне блокування. Пілот — той самий прогін конвеєра, що й
     крок 2: IWDG-заморозка у STOP2/STANDBY (SEC.15) → RDP Level 1 (блокує
     SWD-зчитування і SWD-перезапис); WRPROT ключових сторінок — окремим
     кроком оператора (конвеєр WRP не пише; на L1 option bytes ще змінювані).
     Продакшн-L2 — конвеєр на RDP_LEVEL=0 (ключі + IWDG), далі за 03_05 §3.6:
     self-test → WRPROT → [BOOT_LOCK] → RDP L2 останнім (порядок — ⚖️
     делеговано 2026-09-27, 03_05 §3.3). WRPROT — ПО ЧІПУ: Солдат стор.
     124–125 (key · seed · role · KPUB/KEYB), Королева — лише 124 (її 125 —
     OTA-SHA-дзеркало FW.52, прошивка пише його в рантаймі)

  4. Пакування
     Нанести лак → Пакет → Ліс (shipping-mode ✂️ не потрібен — 03_05 §3.5)
```

### Гілка B — Secure Element SE05x, baseline SE051C2 (mass production > 10k, SEC.6; скетч нижче = legacy ATECC-патерн)

```
[Завод]
  1. Reflow PCBA (ATECC608B запаяний; config zone та data zone обидві unlocked)
     Robot Programmer → Flash base firmware (без AES key, з ATCA-комуникатором) → Board

  2. Power-up self-test:
     STM32 → I²C ping ATECC608B → перевірити serial_number (унікальний 9 байт)
     Якщо ATECC608B не відповідає → fail → reject board (заводський QC)

  3. Provisioning (host-side, one-pass FW.54 — БЕЗ network round-trip):
     host уже знає UID (SWD-read крок 0 Гілки A той самий) → DID (03_01 §7)
     → TreeResolver → Rails-host деривує локально:
           aes_key  = HKDF_SHA256(master_key, DID, "silken-aes-128-lora-key")
           ota_pub  = per-cluster Ed25519 pubkey (FW.23, seed info "silken-ota-ed25519-v1")
           # ⚖️ делеговано 2026-09-27 (врізка під блоком): Гілка B пише
           # ТОЙ САМИЙ набір Protected Flash, що Гілка A — KEYL · LSED · KEYB ·
           # KPUB, бо в кожного MCU-споживач (CRYP · Lorenz-VM · OTA-печатка)
       - Зберігає (DID → HardwareKey, silicon_uid_hex → Tree; tamper-detect:
         підміна чіпа → wrong-board guard / паспорт-mismatch)
       - ECC keypair + X.509 device cert (peaq DID signing, ARCH.27 evolution)
     Жоден ключ не летить мережею — runtime-ключі йдуть SWD -w32 (крок 4,
     як Гілка A), а ATCA-транскрипт (SecureElementProvisioner) несе лише
     ідентичність і копію KPUB у Slot 3 під відкриту post-TRL-7 міграцію

  4. STM32 → SE: write keys per slot mapping (legacy ATECC-скетч; cross-ref 03_05 §3.7):
     # SLOT 0 (AES LoRa) — ✂️ НЕ пишеться post-SEC.14 (provisioning-only):
     #   KEYL іде в Protected Flash як у Гілці A (тим самим SWD -w32 — окремий
     #   крок транскрипту, не ATCA); slot reserved (urban-варіант). Код
     #   зведено 2026-09-27: доти Гілка B SWD-ключів не писала зовсім (цегла на
     #   першому boot), а SecureElementProvisioner емітив Slot-0
     atcab_write_zone(SLOT 1, ecc_priv, 32B)    # Ed25519 private (голос дерева; SE05x → on-chip keygen)
     atcab_write_zone(SLOT 2, cert_der, 64B)    # X.509 device cert
     atcab_write_zone(SLOT 3, ota_pub, 32B)     # FW.23 OTA seal pubkey (копія; MCU перевіряє з KPUB)
     # Slot 4..15 — reserved (legacy ATECC-нумерація; SE05x = object-model, не slots;
     #   FW.17-ратчет ротує session на MCU — 03_05 §3.8, НЕ в SE)

  5. Lock (irreversible на ASIC рівні; legacy ATECC-скетч — SE05x немає 1:1 еквівалента,
     policy per-object фіксується в момент СТВОРЕННЯ (крок 4), не двома фінальними
     викликами, тож форма цього completion-proof теж зміниться —
     protocols/hardware/se050_atecc_api_migration_candidates.md):
     atcab_lock_config_zone()    # Config (slot policies) → permanent
     atcab_lock_data_zone()      # All slot writes → forbidden forever
     # ⚠️ Після цього кроку ключі НЕ можуть бути ні прочитані, ні переписані —
     # навіть з фізичним доступом до ASIC шару.

  6. Lock STM32 — як у Гілці A, крок 3 (Гілка B = Гілка A + SE): пілот —
     IWDG → RDP Level 1 + WRPROT; продакшн-L2 — за 03_05 §3.6 (self-test →
     WRPROT → [BOOT_LOCK] → RDP L2 останнім) → SWD заблоковано

  7. Пакування (як у Гілці A):
     Лак → Box → Field (shipping-mode ✂️ не потрібен — 03_05 §3.5)
```

> ⚖️ **Набір ключів Гілки B — делеговано 2026-09-27 ([`00_07` SE050-MIGRATION](00_07_Action_Plan_Tracker)): той самий, що в Гілці A — KEYL · LSED · KEYB · KPUB у Protected Flash тим самим SWD `-w32` (кроки 3–4 конвеєра Гілки B); SE додає лише ідентичність** (задум; сьогодні SE-транскрипт пише туди тільки копію KPUB — публічного ключа печатки OTA — у Slot 3 під відкриту post-TRL-7 міграцію, а слоти ідентичності 1/2 — TODO до eval-kit). **Підстава:** кожен із чотирьох має MCU-споживача, а не SE-споживача — KEYL і KEYB живлять CRYP радіо-AES, LSED — Lorenz-VM (cold-start), KPUB — перевірку печатки OTA, яку рахує MCU (з 2026-10-06 — публічний ключ Ed25519 на місці симетричного K_ota, §4; SE-резидентність дала б тут цілісність слота, не секретність — [`00_07` SE050-MIGRATION](00_07_Action_Plan_Tracker)); а за ратифікованою роллю SE (SEC.14, provisioning-only, «мертвий SE ≠ мертва телеметрія», [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security)) жоден runtime-шлях через SE не йде. Отже присуд вимушений роллю, не смаком. Для Королеви SE немає за жодної гілки, тож її Гілка B = Гілка A повністю, включно з EDSK. **Ціна:** runtime-ключі Гілки B не отримують SE-нездобутності — їх захищає RDP ([`03_05 §3.3`](03_05_Hardware_Symmetric_Crypto_and_Security)), як у Гілці A; «data zone lock» у таблиці «Подвійний lock» і колонка «Гілка B» у §5.D стережуть лише вміст SE. **Найслабша ланка** — саме це очікування: хто читає «Гілка B = SE» як «ключі в SE», той переоцінює захист KEYL. Застосовано в коді того ж дня (`CommandBuilder#protected_flash_commands` — однаковий транскрипт обох гілок; `SecureElementProvisioner` Slot 0 не емітить); доти Гілка B не писала жодного SWD-ключа — KEYL-less Солдат цеглився на першому boot, Королева не мала навіть KEYC. Носії — `spec/services/factory_flashing/command_builder_spec.rb` (транскрипт B ≡ A для обох типів пристроїв) · `session_spec.rb` (KEYL через SWD; Королева з KEYC і EDSK) · `secure_element_provisioner_spec.rb` (Slot 0 порожній).

**Подвійний lock (defense in depth, тільки Гілка B):**

| Шар захисту | Що блокує | Атака, від якої захищає |
|-------------|-----------|--------------------------|
| **ATECC608B data zone lock** (легасі-скетч; SE05x — per-object policy) | Запис і читання data-слотів SE. Сьогодні транскрипт пише туди рівно один ключ — копію KPUB у Slot 3 (під відкриту post-TRL-7 міграцію OTA-auth; з 2026-10-06 це публічний ключ, тож секрету lock сьогодні не стереже жодного), а слоти ідентичності 1/2 — TODO до eval-kit. Runtime-шлях через SE не йде: CRYP, Lorenz-VM і перевірка OTA-печатки беруть ключі з Protected Flash, і їх стереже рядок «STM32 RDP Level 1/2» (врізка «Набір ключів Гілки B») | DPA/EM side-channel, fault injection (chip self-erase при detection), chip swap |
| **STM32 RDP Level 1/2** | SWD flash dump | Прямий read firmware через debug port |
| **Backend (atecc_serial pin)** | ATECC swap на іншому board | Адверсар викрадає ATECC з одного board і ставить на інший — backend reject при провіженінгу через mismatch (device_uid, серійник SE) пари — ⚠️ ціль, не код: сьогодні серійник лише пишеться в `provisioning_sessions.se_serial_hex` + аудит, пін у `HardwareKey` не реалізовано ([`00_07`](00_07_Action_Plan_Tracker) SE050-MIGRATION) |

**Latency impact (Гілка B vs A):** ⚠️ легасі-аналіз відкинутої альтернативи — post-SEC.14 SE per-packet AES не робить (provisioning-only, «Power impact» нижче), тож сьогодні цей рядок нічого не коштує. ATECC608B AES-ECB ~1.5 мс/блок vs MCU HAL_CRYP ~10 µs. Для одного 16/30-байтного LoRa пакета — нехтовно. Для CBC batch 50 × 16 байт = 800 байт — додаткові ~75 мс на flush (CoAP flush триває кілька секунд у будь-якому разі).

**Power impact (Гілка B):** ATECC active ~69 мкДж/пакет → ≈0.2% active-циклу Soldier (точні числа — 03_05 §3.7, дзеркало SSOT там). ⚠️ Sleep 150 нА always-on **перекидає баланс Сценарію C у мінус** (запасу в його точці немає — [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)) → SE обов'язково за load-switch гейтом (розрахунок і вимога — 03_05 §3.7). Енергія active **мала, але не вирішальна**; сама вісь «SE AES щопакета vs лише provisioning» — **ВИРІШЕНО (SEC.14, 2026-07-03): provisioning-only**, streaming AES = вбудований radio-AES STM32; розбір осей і наслідки — 03_05 §3.7 (Статус).

**Cost impact (Гілка B):** +$0.60/unit (ATECC608B 10k MOQ) або +$0.85/unit (STSAFE-A110). Cross-ref [`00_04`](00_04_Nature_as_a_Service_Contracts) unit economics.

**Вибір гілки — критерії прийняття рішення:**

| Сценарій | Рекомендована гілка | Обґрунтування |
|----------|---------------------|---------------|
| Pilot batch (< 1 000 unit), TRL 6 | **A** (Protected Flash) | Економія часу та BOM; RDP Level 1 + WRPROT достатньо для pilot |
| Mass production 1k–10k unit, TRL 7 | **A**, з планом міграції на B | RDP Level 2 + WRPROT забезпечує proportional захист |
| Mass production > 10k unit | **B** (Secure Element) | Side-channel attractive target; tamper-resistance ROI > $0.60/unit — ⚠️ стереже лише вміст SE (ідентичність); runtime-ключі в обох гілках на рівні RDP (врізка «Набір ключів Гілки B») |
| High-value deployments (urban, commercial, regulated) | **B** | Compliance: NIST FIPS 140-2 Level 3, ISO 27001, GDPR Article 32 |

**Переваги обох гілок:**
- Компрометація одного Soldier не розкриває ключі сусідів (per-device HKDF)
- Фізичне вилучення ключа з чіпа ускладнює RDP Lock (§5.D: L1 — ускладнено, L2 — практично неможливо), і для runtime-ключів це рівень ОБОХ гілок — у Гілці B вони теж у Protected Flash; data-zone lock Гілки B стереже лише вміст SE (сьогодні — копію KPUB, публічну з 2026-10-06, тобто жодного секрету; ідентичність — ціль, врізка «Набір ключів Гілки B»)
- Деривовані device-ключі ніколи не в репозиторії — лише `HardwareKey` (AR-encrypted у Vault); сам `master_key` custody = deploy-ENV Тір-0 (§5.A), **НЕ** Vault
- Якщо Backend-side master key компрометовано → задумано перевипуск всіх ключів через field re-flash. 🔴 **Три межі, яких цей рядок не мав до 2026-09-27:** (1) **re-flash досяжний лише в L1-партіях** — пілотній і spare-резерві серії (регресія = mass erase); пілот покривають у себе вручну (⚖️ founder 2026-09-27), тож його SWD-пади захищає ручна маска, а не зовнішній coater; spare лишається під серійним Parylene з відкритими SWD-падами, якщо coater маскує дрібні пади, і їде на покриття без ключів — провіжн після повернення, інакше йде маршрутом пілоту (⚖️ founder 2026-09-27, провіжн після покриття — делеговано; [`03_05 §3.3`](03_05_Hardware_Symmetric_Crypto_and_Security) і §3.6); серійна плата — RDP L2 під Parylene, SWD мертвий назавжди, тож сьогодні її ключі не перевипускаються нічим, крім заміни плати; (2) re-provision дерева з 2026-09-28 пише НОВИЙ KEYL — корінь нової епохи від поточного master ([`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)) — і наново деривує KPUB/KEYB, а з 2026-09-29 і K_seed: сесія деривує його поточним master і пише в рядок тією ж транзакцією (⚖️ founder, врізка «Провіжн дерева» в §5); доти LSED брався з рядка й під новим master лишався старим; KEYC Королеви — випадковий, ротується окремо; (3) Гілка B відрізняється від A не ключами (runtime-ключі в обох у Protected Flash — врізка «Набір ключів Гілки B», §1), а хвостом у SE: копія KPUB у Slot 3 лежить під data zone, замкненою назавжди, і «re-lock» фізично неможливий — lock односторонній, тож після ротації кореня копія застаріває назавжди (з 2026-10-06 це публічний ключ, а MCU перевіряє з Protected Flash, тож застаріла копія — сміття в слоті, не витік)

**Для поточного прототипу (TRL 6):** Гілка A з protected Flash sector. Гілка B активується перед першим mass production batch (рішення прив'язане до BOM freeze, cross-ref [`02_06 §8.1`](02_06_Unit_Economics_and_BOM)).

**Зворотність:**
- Гілка A → B: можлива (re-flash MCU + добавити ATECC до PCBA = новий PCB revision)
- Гілка B → A: **неможлива** (ATECC config zone locked permanently — board залишається B forever)

> **Cross-ref:** §2 HKDF derivation (детальна криптографія), 03_05 §3.6 RDP Level 2 procedure (irreversible lock checklist), 03_05 §3.7 ATECC608B integration assessment (slot mapping, alternatives, BOM impact), [`00_07` — SEC.3](00_07_Action_Plan_Tracker), [`00_07` — SEC.6](00_07_Action_Plan_Tracker), [`00_07` — FW.1](00_07_Action_Plan_Tracker).

---

## 2. HKDF Key Derivation Protocol Design 🤖

> **Cross-ref:** [`00_07` — FW.1](00_07_Action_Plan_Tracker) — дизайн завершено ✅

**Мета:** замінити один hardcoded ключ на МЕРЕЖУ унікальних ключів, де кожен пристрій має свій, а компрометація одного не розкриває решту. Весь дизайн базується на HKDF (RFC 5869) — стандартному HMAC-based Key Derivation Function.

### Криптографічна основа: HKDF-SHA256 — два info-strings після ARCH.42

```
LoRa-канал (Soldier + Queen LoRa-сесія) — ARCH.42 default:
  HKDF(master_key, device_uid, "silken-aes-128-lora-key") → 16 bytes (AES-128)

CoAP-магістраль (Queen ↔ Rails) — тільки на Gateway-рядках HardwareKey:
  HKDF(master_key, device_uid, "silken-aes-256-device-key") → 32 bytes (AES-256)

Де:
  master_key  = 32-байтний секрет (генерується HRNG; custody СЬОГОДНІ = deploy-ENV
                `PROVISIONING_MASTER_KEY` + boot-guard SEC.9 — НЕ Rails Vault/HSM;
                KMS-MAC latch = pre-mainnet SEC.22 → 06_04 §5.7, on-compromise → §5.8)
  device_uid  = wire-ідентифікатор пристрою: Tree → DID "SNET-XXXXXXXX"
                (ДЕРИВОВАНИЙ з 96-біт silicon UID, murmur3-fmix32 — 03_01 §7;
                сирий 24-hex UID живе окремо у trees.silicon_uid_hex);
                Gateway → uid "SNET-Q-XXXXXXXX"
  info        = ASCII string (domain separation — два різні KDF outputs з одного master)
  output len  = 16 байт (LoRa) АБО 32 байти (CoAP)
```

> **Domain separation:** Два різні info-strings гарантують, що LoRa та CoAP ключі НЕ корелюють криптографічно — компрометація 16-байтного LoRa-ключа конкретного дерева **не дає жодної інформації** про 32-байтний CoAP-ключ Queen, який обслуговує це дерево. Те саме для `OtaSealKeyService` (info `"silken-ota-ed25519-v1"` — seed Ed25519-ключа печатки OTA) та `SilkenNet::SeedDerivation` (info `"silken-lorenz-seed|<DID>"`).
>
> 🔴 **[SEC.34] Ця обіцянка ТЕПЕР МАЄ НОСІЯ — `spec/security/hkdf_domain_separation_spec.rb`, і доти не мала жодного.** Причина, чому саме тут потрібен гейт, а не домовленість: HKDF-колізія **не кидає** — `OpenSSL::KDF.hkdf` віддає бездоганні байти, provisioning проходить, і **прошивка погоджується**, бо деривує те саме хибне значення. Тобто зелено на КОЖНОМУ ярусі, і єдине, що відділяє два ключі, — унікальність пари `(salt, info)`. Salt при цьому гейтувати не можна (він рантаймовий, і `"cluster:<id>"` законно спільний для KEYB ⊥ ключа печатки OTA), тож уся вага лежить на info — звідси пін на попарну відмінність усіх шести info-рядків + ліхтар популяції. ⊕ Друга вісь того ж піна: голе імʼя `HKDF_INFO` жило у ДВОХ класах із різними значеннями (`HardwareKeyService` як мертвий compat-аліас ⊥ живим у сервісі ключа OTA — тоді `OtaHmacKeyService`, з 2026-10-06 `OtaSealKeyService`), тож `info: HKDF_INFO` у новій деривації означало б різне залежно від файлу; аліас знято, гейт тримає єдиність власника. ⛔ **Конвенцію «де живе ідентичність» НЕ вирівнювати** (`HardwareKeyService` кладе її в `salt`, `SeedDerivation` — в `info`): прошивка HKDF від master не рахує — вона вантажить прошиті значення, тож бекенд, що змінив конвенцію, деривуватиме ІНШІ ключі, ніж лежать у Flash, і вирівнювання = пере-ключення всього вже прошитого флоту.

**Властивості HKDF:**
- Якщо зловмисник знає `unique_device_key[i]`, він не може відновити `master_key` або `unique_device_key[j]` — однонаправлена функція
- Два пристрої з однаковим `device_uid` отримають однаковий ключ (детерміновано) — важливо для Rails, який звіряє MIC кожного DID його власним ключем (Королева per-device ключів не тримає — сліпий кур'єр)
- SHA-256 рахується програмно (backend — OpenSSL; Soldier cold-start — pure-C `silken_sha256.h`, FW.30): STM32WLE5JC має апаратний AES, але **не** HASH/SHA-блок

### Схема Provisioning (повна послідовність)

```
═══════════════════════════════════════════════════════════════════════
STEP 1: Генерація MASTER KEY (одноразово, до виробництва)
═══════════════════════════════════════════════════════════════════════

Backend (Rails):
  master_key = SecureRandom.bytes(32)       # CSPRNG, 256 bits
  # Custody СЬОГОДНІ: master → deploy-ENV PROVISIONING_MASTER_KEY (Тір-0, §5.A);
  #   fetch = EnvAdapter (master_key_source.rb) + boot-guard SEC.9. НЕ HardwareKey-Vault-record
  #   (той тримає лише ДЕРИВОВАНІ device-ключі, §2).
  # ⚠️ НІКОЛИ не комітити master_key у репозиторій!
  # Висхідні тіри (Vault/Bitwarden → KMS-MAC pre-mainnet → HSM >1000 units) — §5.A ranking

═══════════════════════════════════════════════════════════════════════
STEP 2: Factory Flashing (конвеєр на заводі)
═══════════════════════════════════════════════════════════════════════

[Заводський стенд — rake-тріо §5, one-pass FW.54]
  a) SWD-read кремнієвого паспорта ДО прошивки (host-first, НЕ device-first):
     STM32_Programmer_CLI -c port=SWD mode=UR -r32 0x1FFF7590 12   # 96-біт UID, три %08X-слова
     DID = SilkenNet::DidDerivation.wire_did_from_uid_hex(UID)
     # murmur3-fmix32 (03_01 §7) — байт-у-байт той самий DID плата порахує
     # собі на boot (firmware/soldier/did_derive.h, golden-вектори обабіч)

  b) factory:flash[UID,…] → FactoryFlashing::TreeResolver:
     Tree create (CLUSTER_ID + TREE_FAMILY_ID env; координати — полю) /
     re-flash (trees.silicon_uid_hex збігся) / bind (legacy без паспорта) /
     DID-колізія (інший чип, той самий DID) → QUARANTINE юніта (03_01 §7)

  c) Backend деривує ключі від ПРАВИЛЬНОГО DID (Zero-Trust — нічого мережею):
     lora_key  = HKDF_SHA256(master_key, DID, "silken-aes-128-lora-key")  # Tree, 16B — session KEYL
                 # [FW.17] re-provision (рядок уже є) — епоха e+1, info "…:e<N>" (03_05 §3.8);
                 # тією ж транзакцією downlink_frame_counter = 0 (03_05 §2.5)
     k_seed    = SeedDerivation (§3, info "silken-lorenz-seed|<DID>")     # Tree, 32B
     k_ota     = per-cluster HKDF (§4, FW.23)                             # Tree, 32B
     bcast_key = HardwareKeyService.derive_broadcast_key(cluster_id)      # ОБИДВА, 16B — KEYB
                 # = HKDF(master, "cluster:<id>", "silken-aes-128-broadcast-key")
                 # Tree → KEYB-слот (стор. 125, +40); Gateway → її KEYL-слот
                 # (єдиний LoRa-ключ Королеви — FW.2 (в), 03_05 §3.1)
     coap_key  = HKDF_SHA256(master_key, uid, "silken-aes-256-device-key") # Gateway, 32B
     HardwareKey.create!(device_uid: DID, aes_key_hex: …)

  d) factory:execute (після 2-Person approve; live) — транскрипт, де КОЖЕН
     рядок — окремий процес CLI з власним -c під скидом (mode=UR; з'єднання
     між процесами не живе): -r32 UID + перше слово стор. 124 → wrong-board
     guard (Session звіряє паспорт плати з trees.silicon_uid_hex; чужа плата
     → WrongBoardError, жодного -w32; безпаспортну вже прошиту плату —
     Королеву — стирає лише REFLASH_ACK=<device_uid>) →
     -e сторінок ключів (Солдат 124 125, Королева 124: -w32 не стирає, і
     re-flash без цього впав би; КОЖЕН провіжн дерева, перший теж (⚖️ founder
     2026-09-29), додає 122 123 і пише свіжий журнал Flash-KV — FlashKvImage, FW.17) → -w32 KEYL/LSED/KPUB/KEYB (Tree; Gateway —
     KEYL=KEYB-значення/KEYC/EDSK) цілими doubleword'ами: WL програмує
     64 біти + ECC лише по стертому, тож суміжні слова йдуть одним -w32,
     а діру в зачепленому doubleword'і добиває 0xFFFFFFFF → -ob IWDG_SW=1
     IWDG_STOP=0 IWDG_STDBY=0 (SEC.15: пес заморожений у STOP2 — ДО RDP,
     бо L2 робить option bytes read-only) → RDP
     # 0x0803E000 = FLASH_KEY_ADDR. Гілка B пише ТОЙ САМИЙ набір тим самим
     # SWD -w32 (⚖️ делеговано 2026-09-27, §1 крок 3); SE-кроки — окремо

  e) Lock (порядок і межа партій — ⚖️ делеговано 2026-09-27, 03_05 §3.3:
     продакшн = WRP → [BOOT_LOCK] → RDP L2 ОСТАННІМ; Parylene серії — ПІСЛЯ
     RDP L2, пілот — покриття прототипів, HW.11):
     STM32_Programmer_CLI -c port=SWD mode=UR -ob RDP=0xBB    # Pilot batch — L1; CLI пише СИРИЙ байт (03_05 §3.6)
     # (Level 2 = 0xCC конвеєр не палить — сесія відхиляє рівень 2, ⚖️ SEC.2
     #  founder 2026-09-28: self-test і WRP мусять стати між ключами й L2, тож
     #  продакшн гонить конвеєр на RDP_LEVEL=0, далі кроки 5–7 03_05 §3.6)

  # [ARCH.77] Польова альтернатива — БРАУЗЕРНИЙ контур (forester, НЕ фабрика;
  # межа = хто відвантажує клієнта, не формат відповіді):
  # POST /provisioning/register (04_03 §5.2) — той самий wire_did
  # від 24-hex UID; координати + peaq DID заводяться там.

═══════════════════════════════════════════════════════════════════════
STEP 3: Runtime — Soldier читає свій LoRa AES-128 ключ
═══════════════════════════════════════════════════════════════════════

firmware/soldier/main.c (післі ARCH.42):
  // Boot-time RAM mirror (заповнюється з Flash через Load_AES_Key()):
  uint32_t aes_key[4] = {0};   // 16 bytes — LoRa AES-128
  // FLASH_KEY_ADDR layout: [magic "KEYL":4][aes_key:16] = 20 bytes total
  // При ініціалізації:
  Load_AES_Key();              // populates aes_key[4] from Protected Flash
  MX_CRYP_Init();              // hcryp.Init.KeySize = CRYP_KEYSIZE_128B; hcryp.Init.pKey = aes_key;

═══════════════════════════════════════════════════════════════════════
STEP 4: Queen і ключі Soldiers — ✅ ВИРІШЕНО (FW.2 (в), 2026-07-03)
═══════════════════════════════════════════════════════════════════════

Рішення: Queen НЕ ЗНАЄ session-ключів Солдатів взагалі.
  CCM-ера: Королева — сліпий кур'єр (queen/rx_route.h) — demux по
  cleartext DID з AAD, MIC верифікує Rails per-DID. Єдиний LoRa-ключ
  Королеви = cluster control-plane KEYB (її KEYL-слот несе
  broadcast-значення) — ним вона шифрує downlink і читає 0x55/0x56.
  Канон моделі: 03_05 §3.1.

Історичні варіанти (розглянуто, відхилено):
  A. queen_key = HKDF(master, queen_uid) — лишав ECB-demux нерозв'язаним;
  B. key table 50×ключів у Flash — RAM/Flash-ціна + service downlink-канал;
  C. master_key у SE Королеви (HKDF on-the-fly) — master на кожному
     гейтвеї = концентрація ризику, яку blind-courier усуває безкоштовно.
```

### Rails Backend — API та зберігання (post-ARCH.42)

```ruby
# app/services/hardware_key_service.rb — обидва derivation-методи йдуть через один
# приватний hkdf_derive (RFC 5869, OpenSSL::KDF). Master key: явний `master_key:`
# — фабрична Session несе його від MasterKeySource (SEC.3 DI); nil → ENV
# PROVISIONING_MASTER_KEY (runtime-fallback: register API, IoTeX seed); blank →
# SecurityError (SEC.11). Повертає hex UPPER.

LORA_HKDF_INFO = "silken-aes-128-lora-key"   # ARCH.42 — Tree LoRa channel (16 bytes)
COAP_HKDF_INFO = "silken-aes-256-device-key" # Gateway CoAP-to-Rails channel (32 bytes)

# IKM = master_key, salt = device_uid, info = domain separation
OpenSSL::KDF.hkdf(master_key, salt: device_uid.to_s, info: LORA_HKDF_INFO,
                  length: 16, hash: "SHA256").unpack1("H*").upcase  # derive_lora_key
OpenSSL::KDF.hkdf(master_key, salt: device_uid.to_s, info: COAP_HKDF_INFO,
                  length: 32, hash: "SHA256").unpack1("H*").upcase  # derive_device_key
```

> ⛔ **HKDF тут не переписують руками через `OpenSSL::HMAC`.** HKDF-Extract бере **salt ключем**, а IKM — повідомленням; переставлені аргументи дають бездоганні, але ІНШІ байти, тобто ключ флоту розходиться з прошитим, і видно це лише на першому uplink'у. Рукописна форма в цьому розділі вже раз саме так і розійшлась із кодом (salt і IKM місцями). Носій проти колізії info-рядків — `spec/security/hkdf_domain_separation_spec.rb` (SEC.34, вище).

Реєстрація з браузерного контуру — `Api::V1::ProvisioningController#register` → `HardwareKeyService.provision(device)` (Zero-Trust: ключ у відповідь НЕ повертається; DID дерева — `SilkenNet::DidDerivation.wire_did_from_uid_hex`, [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA)).

### Firmware — зчитування ключа з Protected Flash Sector (AES-128 LoRa)

```c
// firmware/soldier/main.c — post-ARCH.42 (4 words замість 8):

// Flash Protected Key Sector (0x0803E000 — 4 KB, protected via WRPROT option bytes)
#define FLASH_KEY_ADDR   0x0803E000UL
#define FLASH_KEY_WORDS  4                // 4 × uint32_t = 16 bytes (AES-128)
#define FLASH_KEY_MAGIC       0x4B45594CUL     // "KEYL" — LoRa key

uint32_t aes_key[FLASH_KEY_WORDS] = {0};

void Load_AES_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_KEY_ADDR;
    // 1. Magic check (захист від unprovisioned chip)
    if (flash_ptr[0] != FLASH_KEY_MAGIC) {
        Error_Handler();   // infinite reset loop (захист від випуску партії без provisioning)
    }
    // 2. Non-zero check
    uint32_t key_sum = 0;
    for (int i = 0; i < FLASH_KEY_WORDS; i++) key_sum |= flash_ptr[1 + i];
    if (key_sum == 0) { Error_Handler(); }
    // 3. Copy into RAM mirror
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        aes_key[i] = flash_ptr[1 + i];
    }
}

// MX_CRYP_Init() then sets: hcryp.Init.KeySize = CRYP_KEYSIZE_128B; hcryp.Init.pKey = aes_key;
```

### [FW.30] Lorenz K_seed — зчитування з Protected Flash Sector

K_seed зберігається одразу після AES ключа у тій самій Protected Flash сторінці:

```c
// firmware/soldier/main.c — [SEC.11 / FW.30]:

// Flash layout (post-ARCH.42 — AES-128 LoRa key only):
//   [LORA_KEY_MAGIC:4][AES_KEY:16] | [SEED_MAGIC:4][K_SEED:32]
//   ^FLASH_KEY_ADDR        ^FLASH_SEED_ADDR
// (Gateway-only Queen також має окрему пару [COAP_MAGIC:4][COAP_KEY:32] у наступному slot)
#define FLASH_SEED_ADDR   (FLASH_KEY_ADDR + 20)  // 0x0803E014 (4 magic + 16 key = 20)
#define FLASH_SEED_WORDS  8                        // 8 × uint32_t = 32 bytes
#define FLASH_SEED_MAGIC  0x4C534544UL             // "LSED" — Lorenz Seed

uint8_t lorenz_seed[32] = {0};
uint8_t lorenz_seed_valid = 0;

void Load_Lorenz_Seed(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_SEED_ADDR;
    if (flash_ptr[0] != FLASH_SEED_MAGIC) { lorenz_seed_valid = 0; return; }
    uint32_t seed_or = 0;
    for (int i = 0; i < FLASH_SEED_WORDS; i++) seed_or |= flash_ptr[1 + i];
    if (seed_or == 0) { lorenz_seed_valid = 0; return; }
    for (int i = 0; i < FLASH_SEED_WORDS; i++) {
        uint32_t word = flash_ptr[1 + i];
        lorenz_seed[i*4+0] = (uint8_t)(word >> 24);
        lorenz_seed[i*4+1] = (uint8_t)(word >> 16);
        lorenz_seed[i*4+2] = (uint8_t)(word >>  8);
        lorenz_seed[i*4+3] = (uint8_t)(word & 0xFF);
    }
    lorenz_seed_valid = 1;
}
```

> **Відмінності від Load_AES_Key():** (1) відсутність K_seed не є фатальною — `Error_Handler()` НЕ викликається (warm continuation через RTC все ще працює); (2) big-endian byte order для сумісності з HMAC-SHA256; (3) magic marker `"LSED"` відрізняється від `"SKEY"` для захисту від помилкового cross-read.

### [ARCH.27] Node Role — окремий Flash slot після K_seed (2026-05-03)

`g_node_role` персистується у тому ж Protected Flash Sector одразу після K_seed — **без створення нового сектора**:

```c
// Flash layout (post-ARCH.42): [LORA_KEY_MAGIC:4][AES_KEY:16] | [SEED_MAGIC:4][K_SEED:32] | [ROLE:4]
//   ^FLASH_KEY_ADDR (0x0803E000)  ^FLASH_SEED_ADDR (+20 = 0x0803E014)  ^FLASH_ROLE_ADDR (+56 = 0x0803E038)
#define FLASH_ROLE_ADDR        (FLASH_KEY_ADDR + 56)   // 0x0803E038 (20 + 4 magic + 32 seed = 56)
#define ROLE_SOLDIER_MAGIC     0x534F4C44UL            // "SOLD"
#define ROLE_PROVISIONER_MAGIC 0x50524F56UL            // "PROV"
#define ROLE_SOLDIER           0
#define ROLE_PROVISIONER       1

volatile uint8_t g_node_role = ROLE_SOLDIER;  // безпечний дефолт

void Load_Node_Role(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_ROLE_ADDR;
    uint32_t role_word = flash_ptr[0];
    if      (role_word == ROLE_PROVISIONER_MAGIC) g_node_role = ROLE_PROVISIONER;
    else if (role_word == ROLE_SOLDIER_MAGIC)     g_node_role = ROLE_SOLDIER;
    else                                          g_node_role = ROLE_SOLDIER; // fallback
}
```

> **Чому fallback на Soldier:** більшість вузлів — звичайні датчики (Soldier=TX-only). Provisioner (TX+CAD) — еліта з надлишком енергії, яку factory pipeline мусить прошивати явно; ⚠️ сьогодні `CommandBuilder` `FLASH_ROLE_ADDR` не пише зовсім, тож кожен фабричний юніт вантажиться Солдатом через цей fallback (роль Провідника — ARCH.26); а re-flash конвеєром стирає й раніше записану роль — стор. 124 стирається перед записом ключів, тож роль пишеться після кожного прогону. Корупція/erase Flash (`0xFFFFFFFF` unprovisioned, `0x00000000` erased, бітові помилки) → безпечний дефолт без CAD-режиму, який спалив би слабкого Солдата енерго-голодним радіо.

> **Споживачі прапорця:** ARCH.26 L3 (CAD relay), повний FW.20-S2 (mesh time-sync relay) — без додаткової логіки в `HardwareKeyService`/backend; це чистий firmware-flag. Backend не повинен довіряти claimed role з пакету (TX-сторона може брехати) — `g_node_role` локально визначає поведінку, серверна сторона вирішує доверу через ECC підпис при provisioning.

> **5 host-тестів** у `test_soldier_logic.c`: SOLD / PROV / unprovisioned 0xFFFFFFFF / zero / corrupted magic → all fallback paths.

### Захист Flash Key Sector (WRPROT)

```
STM32CubeProgrammer → Option Bytes → Write Protection:
  СОЛДАТ — сторінки 124-125 (0x0803E000 + 0x0803E800; WLE5 = 2KB-сторінки,
  дзеркало firmware-арифметики FLASH_KEY_ADDR/FLASH_OTA_KEY_ADDR)
  КОРОЛЕВА — лише сторінка 124: її 125 — OTA-SHA-дзеркало (FW.52,
  firmware/queen/ota_sha_guard.h), яке прошивка стирає й пише в рантаймі;
  WRP там мовчки зламав би перезапит OTA, а L2 — назавжди
  → Write-Protected ON

Результат: навіть якщо SWD відкритий (RDP Level 0 у R&D) —
  запис у ключові сторінки неможливий без зняття WRPROT
  (зняття стирає відповідну сторінку Flash!)
```

> **Семантика двох сторінок (FW.2 (в)):** 124 = **per-device identity** (KEYL session · LSED · ROLE; Queen: KEYC · EDSK), 125 = **cluster membership** (KPUB · KEYB @+40, dw-align) — переїзд дерева між кластерами міняє вміст лише 125-ї. ⚠️ Інструмента, що стирав би лише її, немає: конвеєр стирає й переписує 124 і 125 разом (per-device ключі повертаються тими самими — HKDF детермінований), тож роль на стор. 124 після кожного прогону пишеться наново.

### Безпекові параметри (post-ARCH.42)

| Параметр | LoRa-канал (Tree + Queen) | CoAP-канал (Queen only) | Обґрунтування |
|----------|---------------------------|--------------------------|---------------|
| KDF алгоритм | HKDF-SHA256 (RFC 5869) | HKDF-SHA256 | Стандарт NIST SP 800-56C; SHA256 — software (backend OpenSSL / Soldier pure-C `silken_sha256.h`) |
| Master key size | 256 bits | 256 bits | Master input — однаковий 256-bit secret для обох KDF-outputs |
| Output key size | **128 bits (16 bytes)** — ARCH.42 | 256 bits (32 bytes) | LoRa: AES-128 (свідомий вибір, **не** SE-constraint — SE050 вміє 256, 03_05 §3.7); CoAP: AES-256 (Queen Flash, no SE constraint) |
| Info string | `"silken-aes-128-lora-key"` (session) · `"silken-aes-128-broadcast-key"` (KEYB cluster, salt=`"cluster:<id>"` — FW.2 (в)) | `"silken-aes-256-device-key"` | Domain separation — усі KDF outputs ortho (вкл. `"silken-ota-ed25519-v1"` §4) |
| Master key storage | **Deploy-ENV `PROVISIONING_MASTER_KEY`** (boot-guard SEC.9; §5.A ранжує Direct-ENV найнижче — чесний поточний тір) → KMS-MAC pre-mainnet (SEC.22, [`06_04 §5.7`](06_04_Secrets_Checklist)); **деривовані** ключі — `HardwareKey` AR-encrypted | Same | Never in-repo; on-compromise runbook → [`06_04 §5.8`](06_04_Secrets_Checklist) |
| Device key storage | Protected Flash (LoRa magic `"KEYL"`) — **обидві гілки** (SEC.14 provisioning-only; SE Slot 0 reserved для urban-варіанту — 03_05 §3.7) | Protected Flash (CoAP magic `"KEYC"`) — Queen MCU only | Фізичний захист; AES-128 на LoRa — свідомий вибір, не SE-constraint (ADR 03_05 §3.7); CoAP-key лишається у MCU Flash (канал не через SE) |
| Backup/rotate | Session: dual-key grace period (HardwareKey#previous_aes_key_hex — закривається неявним uplink-ACK: перший кадр, чий CCM-MIC пройшов новим ключем, FW.17). **KEYB: re-provision only** — grace незастосовний (broadcast-ключ не має власного uplink'а для ACK; той самий клас, що KPUB) | Grace, але **закриває його re-provision, не uplink**: AES-CBC без MAC розшифровується будь-яким ключем у сміття без помилки, тож «розшифрувалось» ключа не підтверджує. У вікні обидва напрямки CoAP-тракту ідуть попереднім (`HardwareKey#coap_binary_key`); `FactoryFlashing::Session`, що залила поточний, закриває grace (dry-run — ні) | Zero-downtime rotation (session); cluster-ключі ротуються фізичним re-flash (конвеєр стирає й переписує стор. 124 і 125 разом) |
| Post-quantum margin | $2^{128}$ (post-Grover ≈ $2^{64}$ — захищається ratchet `[FW.17]` + PQC bridge 03_05 §10) | $2^{256}$ (post-Grover ≈ $2^{128}$ — абсолютний квантовий імунітет) | Чому CoAP залишається 256: інфраструктурне TLS-termination через Cloudflare X25519+Kyber вже доступне (post-quantum hybrid) |

> **Cross-ref:** SEC.3 Factory Flashing pipeline, SEC.6 Secure Element (SE050, 03_05 §3.7), SEC.2 RDP Level 2, **ARCH.42 ✅ resolved 2026-05-23 (Variant B)**, **03_05 §10 PQC Migration Roadmap**.

---

## 3. Lorenz K_seed Derivation (SEC.11) 🤖

> **Cross-ref:** [`00_07` — SEC.11](00_07_Action_Plan_Tracker) — ✅ DONE 2026-05-02 (hard cutover, pre-prod)

**Мета:** криптографічно стійкий механізм виведення початкової точки `(x₀, y₀, z₀)` атрактора Лоренца для кожного Soldier-вузла. Замінює попередній підхід "raw DID як seed", який мав фундаментальні безпекові вади і робив `check_z_divergence!` категоричним замість числового. Деталі — у [`03_04 §2.1 + §3` Крок 1](03_04_mruby_Lorenz_Attractor); тут — лише cryptographic protocol layer.

### Чотири фундаментальні вади до SEC.11

1. **Публічний seed → публічна траєкторія.** DID їде відкритим текстом у заголовку LoRa-пакета (`[DID:4]`, поза AES). Атакер з open-source формулою Лоренца обчислює `Z(DID, temp, acoustic, dt, vcap)` для будь-якого дерева → підробляє телеметрію з валідним StatusByte, `check_z_divergence!` мовчить.
2. **Кореляція сусідніх DID.** Provisioning видає DID послідовно (`SNET-AC0001AB`, `…AC`). Перші ~30 ітерацій Ейлера дві сусідні крони мають майже ідентичні траєкторії → знижена статистична ентропія.
3. **Семантична помилка категорій.** DID — *identifier*. Identifier-as-key — класичний антипатерн, бо identifier має бути входом до KDF, ніколи виходом.
4. **Відсутність forward secrecy.** Одне дерево все життя стартує з тієї ж точки. Один підроблений рецепт працює довічно.

### Прийнятий дизайн: гібрид A + B + D

```
═══════════════════════════════════════════════════════════════════════
PROVISIONING (one-time, разом з AES key)
═══════════════════════════════════════════════════════════════════════

K_seed = HKDF-SHA256(
  ikm     = PROVISIONING_MASTER_KEY,        # той самий master, що для AES key
  salt    = "silken-lorenz-v1",             # ВІДМІННИЙ від AES salt → domain separation
  info    = "silken-lorenz-seed|<DID>",     # ВІДМІННИЙ info-string від AES
  length  = 32 bytes
)

Backend storage:
  HardwareKey.create!(
    device_uid:      DID,
    aes_key_hex:     <derived per §2>,
    lorenz_seed_hex: <K_seed hex, AR Encryption non-deterministic>
  )

Soldier storage:
  K_seed → protected Flash sector (поряд з K_aes; той самий RDP захист).
  НІКОЛИ не передається через LoRa або UART; обидві сторони деривують
  незалежно з PROVISIONING_MASTER_KEY.

═══════════════════════════════════════════════════════════════════════
COLD START (boot після VBAT loss; рідка подія, місяці-роки)
═══════════════════════════════════════════════════════════════════════

epoch_day = current_unix_ts / 86400              # daily rotation, UTC
salt_info = "init|" || pack_be(epoch_day, 8)     # 13 bytes total
digest    = HMAC-SHA256(K_seed, salt_info)       # 32 bytes
x₀ = bytes_to_signed_unit_float(digest[ 0.. 7])  # ∈ [-1, +1]
y₀ = bytes_to_signed_unit_float(digest[ 8..15])
z₀ = bytes_to_signed_unit_float(digest[16..23])
# Зберегти (x₀,y₀,z₀) у RTC DR16-DR18 з magic "LZST" (FW.6)

bytes_to_signed_unit_float(b8):
  u64 = unpack_be_uint64(b8)
  return (u64 / (UINT64_MAX / 2.0)) - 1.0

═══════════════════════════════════════════════════════════════════════
STEADY-STATE (FW.6 continuation; кожне пробудження)
═══════════════════════════════════════════════════════════════════════

(x_prev, y_prev, z_prev) = read RTC DR16-DR18 (warm) АБО cold-start (rare)
[payload_byte, x_f, y_f, z_f] = mruby calculate_state(
                                  x_prev, y_prev, z_prev,
                                  temp, acoustic, delta_t_s, vcap_mv, z_min, z_max)
write RTC DR16-DR18 = (float)(x_f, y_f, z_f); DR19 = "LZST"   # float32: так стан і живе між кадрами

═══════════════════════════════════════════════════════════════════════
SERVER MIRROR (TelemetryUnpackerService, byte-identical mathematics)
═══════════════════════════════════════════════════════════════════════

IF prev_telemetry_log.lorenz_state_(x|y|z) IS NULL:
  cold_start_flag = true
  K_seed_bin = hardware_key.binary_lorenz_seed
  # [ARCH.41] Доба = момент ПРИЙОМУ (job-аргумент `received_at`), не `created_at`:
  # той ставиться при вставці рядка, тобто на Sidekiq-ретраї він теж новий.
  epoch_day  = received_at.to_i / 86400
  (x₀,y₀,z₀) = SilkenNet::SeedDerivation.initial_state(K_seed_bin, epoch_day)
ELSE:
  cold_start_flag = false
  (x₀,y₀,z₀) = (prev.lorenz_state_x, prev.lorenz_state_y, prev.lorenz_state_z)

(x₀,y₀,z₀) = Attractor.as_rtc_state(x₀, y₀, z₀)    # [FW.66] float32, як RTC Солдата (і cold-start теж)
server_z, x_f, y_f, z_f = Attractor.calculate_z_from_state(
                            x₀, y₀, z₀, temp, acoustic, delta_t_s, vcap_mv)
# check_z_divergence! судить z_f (double) — так класифікує й пристрій, до звуження
log.update!(lorenz_state_(x|y|z): Attractor.as_rtc_state(x_f, y_f, z_f),
            cold_start_flag: cold_start_flag)
```

### Криптографічні гарантії в одному рядку

> `K_seed` ніколи не залишає пристрій і сервер. `(x₀, y₀, z₀)` — функція від (`K_seed`, `epoch_day`). DID у формулі **не існує** як seed — він використовується лише як `info`-string у HKDF (namespace separator), що криптографічно безпечно і не вносить уразливості.

### Threat model post-SEC.11

| Загроза | Захист |
|---------|--------|
| Sniff LoRa-пакет → відтворити Z | ❌ (без `K_seed` Z непередбачуваний) |
| Compromise одного `K_seed` (фізичний доступ до пристрою) | ⚠️ Один пристрій уразливий ≤ 24 год; інші — ні (⚠️ «≤ 24 год» не тримається — нота під таблицею) |
| Compromise `PROVISIONING_MASTER_KEY` | 🚨 Каскадне — потрібна окрема rotation strategy (SEC.9) |
| Replay вчорашнього валідного пакета | ❌ (`epoch_day` змінився, Z більше не валідний) (⚠️ не тримається — нота під таблицею) |
| Підроблений `cold_start_flag = true` від device | ❌ Структурно неможливо: прапорця НЕМА на дроті (ані `PAYLOAD_FORMAT`, ані `CCM_SENSOR_PAYLOAD_FORMAT`) — сервер деривує його сам із наявності попереднього хвоста траєкторії (`TelemetryUnpackerService#compute_server_z`) |
| ARM ↔ x86 IEEE-754 drift > 0.001 | Емпірично < 1e-12 (дрейф ядра); ⚠️ запас ε рахується від кванта дроту q/2 = 0.00098, тобто лише 2.2·10⁻⁵ — нота під «Висновком Gate L», [`03_04 §7.1`](03_04_mruby_Lorenz_Attractor) |

> ⚠️ **Два рядки таблиці вище стверджують сильніше за систему (виправлено 2026-10-05 після адверсарної перевірки; [`00_07`](00_07_Action_Plan_Tracker) FW.66).** `K_seed` статичний, а `epoch_day` публічний, тож злитий `K_seed` не обмежує жодна ротація — ні добова, ні будь-який якір: обмежити можна лише злитий СТАН. А стан у сталому режимі не ротується взагалі: `epoch_day` входить лише в cold start пристрою, DCI судить СЕРВЕРНИЙ ланцюг, а сервер не ре-якориться ніколи, тож злитий стан ланцюга (з RTC DR16–DR18 чи з `telemetry_logs`) дає передбачати серверний z без строку — cold start пристрою його не скидає ([`03_04 §7.3`](03_04_mruby_Lorenz_Attractor)). Для грошового напряму не потрібне ні те, ні те: категорійна DCI судить лише членство в смузі, а в ній чесний ланцюг ≈ 99 % кадрів, тож фальсифікатор, що завжди заявляє homeostasis, не дістає жодного fraud (0 на 40 000 кадрів) — рядок «Sniff → відтворити Z» правдивий про ЧИСЛО z, а не про категорію, яку судить DCI. Повтор старого кадру DCI так само не відсікає, а ще й крокує серверний ланцюг і нараховує бали вдруге (`Wallet#credit_telemetry!` від вердикту DCI не залежить — його обмежує лише відро E.64). Від повтору поодинокого LoRa-кадру телеметрії захищає FC CCM-ери — з 2026-10-05 ковзне вікно бекенда на (DID, епоха) без строку давності ([`00_07`](00_07_Action_Plan_Tracker) SEC.40; доти — кеш на 25 год, після якого не захищало нічого); в ECB-ері поодинокий кадр не захищений нічим — конверт Королеви несе nonce QATT на 30 діб, панічні кадри — лічильник SEC.10. Рядки лишено як запис дизайну SEC.11 — читати їх разом із цією нотою.

### Реалізація

| Компонент | Файл |
|-----------|------|
| Backend HKDF + HMAC + initial-state derive | `app/services/silken_net/seed_derivation.rb` |
| Backend AR Encryption поле | `HardwareKey#lorenz_seed_hex` (validated `presence: true`) |
| Backend dispatch | `app/services/telemetry_unpacker_service.rb` (raises `MissingLorenzSeedError` без K_seed) |
| Backend attractor entry-point | `Attractor.calculate_z_from_state(x₀, y₀, z₀, …)` |
| Firmware pure-C bridge (FW.30) | `firmware/soldier/main.c` → `silken_sha256.h` (HKDF/HMAC, без mbedTLS) |
| Firmware mruby entry-point | `firmware/bio_contracts/bio_contract.rb#calculate_state(x_prev, y_prev, z_prev, …)` |
| Host-parity test | `firmware/test/test_seed_derivation.c` (OpenSSL HKDF/HMAC = `silken_sha256.h` на MCU) |
| Backend specs | `spec/services/silken_net/seed_derivation_spec.rb` |

> **Cross-ref:** [`03_04 §2.1` First-Boot vs Continuation](03_04_mruby_Lorenz_Attractor#21-звідки-беруться-вхідні-параметри); [`05_02 §Dual` Computation Integrity](05_02_Proof_of_Growth_Pipeline); SEC.9 master-key rotation.

---

## 4. OTA Authentication Protocol Design (FW.23) ✅ Реалізовано (2026-05-02 · Ed25519-печатка — 2026-10-06)

> ⚖️ **2026-10-05/06 — печатка асиметрична** (founder, [`00_07`](00_07_Action_Plan_Tracker) FW.23; поправку примітиву — Ed25519 замість ECDSA-P256 — ратифіковано 2026-10-06 й застосовано того ж дня). Доти печаткою був HMAC-SHA256 під кластерним `K_ota`, що лежав на **кожному** вузлі кластера: витягнутий вузол підписував контракт для всіх. Тепер бекенд підписує приватним ключем кластера, а вузол тримає лише **публічний** — витягнутий вузол віддає тільки те, що й так не секрет.

**Статус реалізації:**

| Шар | Файл | Що зроблено |
|-----|------|-------------|
| Backend (ключ) | `app/services/ota_seal_key_service.rb` | `OtaSealKeyService.signing_key_for(cluster_id, master_key: nil)` → `Ed25519::SigningKey` із seed = HKDF-SHA256 (info `"silken-ota-ed25519-v1"`); `public_key_hex_for` → 64 HEX для фабрики; ikm = `master_key:` (фабрична Session, SEC.3 DI) або ENV-fallback, `SecurityError` без жодного (SEC.11) |
| Backend (печатка) | `app/services/ota_packager_service.rb` | `seal_message` (тіло ‖ `version_id` BE4 ‖ `total` BE2) · `compute_seal` (64 Б) · `build_seal_trailer_chunks` (7 блоків `0x9B`) · `prepare(..., cluster_id:)` opt-in з `manifest[:sealed/seal_cluster_id/lora_total_chunks/total_packages]` |
| Firmware (дріт) | `firmware/common/ota_seal_wire.h` | константи трейлера + `Ota_Seal_Parse_Chunk` — одна копія для Королеви й Солдата, pure, без криптографії |
| Firmware (перевірка) | `firmware/common/ota_seal.h` | `Ota_Seal_Verify` (Monocypher: стрімінговий SHA-512 → `crypto_eddsa_reduce` → `crypto_eddsa_check_equation`, без копії тіла) · `Ota_Seal_Try_Finalize` (вердикт WAIT·APPLY·REJECT) |
| Firmware Queen | `firmware/queen/main.c` | сліпий гонець: `pending_ota_seal_chunks[7][16]`, ready-mask `OTA_SEAL_ALL_RECEIVED` = `0x7F`; один блок на рефлекс-постріл після почутого uplink'у (FW.27-B, duty-лімітер FW.61), трейлер — одним проходом ([`FW.68`](00_07_Action_Plan_Tracker)); криптографії не включає |
| Firmware Soldier | `firmware/soldier/main.c` | `Load_Ota_Seal_Pubkey` (Protected Flash `0x0803E800`, magic `"KPUB"`, ненульовий ключ, інакше `ota_seal_pubkey_valid=0` → fail-closed) · `Ota_Seal_Parse_Chunk` / `Ota_Seal_Try_Finalize` з обох RX-гілок (тіло `0x99` / печатка `0x9B`) |
| Factory | `FactoryFlashing::CommandBuilder` · `Session` · `SecureElementProvisioner` | сторінка 125: `KPUB`-блок (magic `0x4B505542` + 8 слів публічного ключа) на місці колишнього `KOTA`; `Session` тягне `OtaSealKeyService.public_key_hex_for`; SE Slot 3 (superseded Гілка B) — той самий публічний ключ |
| Backend specs | `spec/services/ota_seal_key_service_spec.rb` · `ota_packager_service_spec.rb` · `spec/integration/ota_firmware_flow_spec.rb` · factory-специ | золотий вектор · детермінізм повторного пакування (байт-у-байт) · relabel / truncation / tamper / чужий кластер → `Ed25519::VerifyError` · маніфест · KPUB-транскрипт |
| Firmware host-tests | `firmware/test/test_ota_seal.c` · `test_soldier_logic.c` · `test_queen_logic.c` | золотий вектор Ruby перевіряють прошивка, Monocypher і OpenSSL · стрімінг ≡ `crypto_ed25519_check` · кожен змінений вхід ламає перевірку · збирання 7 блоків (поза порядком, дублікат, seg 6 = 9 Б, криві блоки) · `Ota_Seal_Try_Finalize` APPLY·WAIT·REJECT · реле Королеви 7 блоків, FW.52б воскресіння рівно на сьомому |

**Ціна (виміряно 2026-10-06; Cortex-M4 soft-float, `-Os`, `--gc-sections`):** +11 024 Б `.text` (≈10.8 КіБ: Monocypher-перевірка + SHA-512; гармошка з викликом `Ota_Seal_Verify` проти без, верхня оцінка — спільні з образом функції libc пораховано двічі; рядок у [`03_01 §12`](03_01_Firmware_Lifecycle_and_DMA)) · пік стеку перевірки ≈2.0 КБ (статичний граф GCC `-fcallgraph-info=su`; найбільший кадр — `crypto_eddsa_check_equation` 1 128 Б) проти ~0.3 КБ HMAC · `.bss` Солдата +32 Б (печатка 64 Б замість тегу 32 Б), Королеви +48 Б (7 блоків замість 4) — RAM-гейт [FW.26] зелений · ефір +3 рефлекс-постріли (16 Б @ SF9 ≈ 165 мс кожен; трейлер 7 блоків замість 4). 🔴 **Найслабша ланка (з подання, відкрита):** запас флешу Солдата до board-freeze не виміряно — повного `.elf` нема ([`03_01 §12.4`](03_01_Firmware_Lifecycle_and_DMA)), тож +10.8 КБ стоять у черзі поруч із mruby ~117 КБ без доведеного «влазить». 🟡 **Лишається (bench, клас C):** час перевірки на кремнії (QEMU-M4 смуга [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA) виконує ISA, але не цикло-точна) + e2e на STM32: валідний APPLY + підмінений байт тіла → REJECT — RUNBOOK §2.5 (доки стоять [`FW.67`](00_07_Action_Plan_Tracker)/[`FW.68`](00_07_Action_Plan_Tracker) — тестовим контрактом ≤ 1 019 Б і одним Солдатом).

> **Cross-ref:** [`00_07` — FW.23](00_07_Action_Plan_Tracker)
> **Залежність:** FW.1 (per-device HKDF) — ✅ (03_05 §3.1); спільна master-secret інфраструктура.

**Мета:** усунути BLOCKER 03_05 §6 «Queen → Soldier (OTA LoRa) — MAC/MIC відсутній». Зловмисник у радіусі Queen може:
1. **Підмінити OTA chunks** → впровадити шкідливий mruby bytecode на всі Солдати кластера
2. **Підробити контрольну суму** → CRC (CRC16 чанка, CRC32 потоку) не криптографічні, валідну суму можна порахувати для будь-якого payload
3. **Повторити старий OTA** → відкотити Солдат на застарілу/вразливу прошивку
4. **Витягнути ключ із вузла** (фізичний доступ до дерева в лісі — найдешевша атака на цю систему) → підписати контракт для всього кластера. Цю загрозу HMAC-ера не закривала: ключ перевірки на вузлі був і ключем підпису.

Симетричне шифрування (AES-128-ECB, KEYB) гарантує лише **конфіденційність**, не **автентичність походження**. Дзеркало проблеми FW.2 для каналу телеметрії, але з більшою серйозністю — OTA bytecode виконується на всіх Солдатах у радіусі.

### Криптографічна основа: Ed25519 (RFC 8032) поверх повного image

```
message = padded_bytecode ‖ version_id (4 B BE) ‖ total_chunks (2 B BE)
seal    = Ed25519_Sign(sk_cluster, message)    → 64 B (R ‖ S)
```

`padded_bytecode` — тіло, вирівняне під LoRa-MTU (FW.53), **без** CRC32-хвоста: рівно ті байти, що Солдат тримає в `ota_buffer[0..data_len)`.

**Чому Ed25519, а не ECDSA-P256 (⚖️ поправка примітиву, 2026-10-06):**
- **Детермінізм несучий.** Пакет кампанії готують більше одного разу: `Ota::PackageStore` перегріває кеш, `OtaTransmissionWorker` пакує окремо, а Королева ретранслює ті сегменти, що дотягнула. ECDSA з випадковим k дав би дві різні печатки однієї кампанії, трейлер зшився б із сегментів обох → вічний REJECT. Детермінований ECDSA (RFC 6979) вимагав би звіреної бекенд-реалізації або зберігання печатки на кампанію; Ed25519 детермінований за побудовою (nonce = H(prefix ‖ message)). Пін «повторне `prepare` = ті самі байти» — `ota_packager_service_spec`.
- **Ключ лягає в той самий слот:** 32 Б Ed25519 — на місце `K_ota`; ключ P-256 (64 Б) вимагав би переносу макета сторінки 125 на обох боках (з +40 уже лежить KEYB).
- **На хості — той самий код, що на кремнії:** перевірка — портабельний C (Monocypher, pinned submodule 4.0.3, ним уже підписує QATT Королева, L1; pin-policy [`03_01 §12.5`](03_01_Firmware_Lifecycle_and_DMA)), тож host-тести ганяють рівно те, що вшито; ECDSA на апаратному PKA (подання 2026-10-05) на хості не перевірявся б узагалі. Нових залежностей нуль.
- Узгоджено з SE05x-ерою: природна крива там — теж Ed25519 ([`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker)).

**Чому не лишили HMAC:** він дешевший (~0.3 КБ стеку, нуль флешу понад наявний `silken_sha256.h`, 3 блоки печатки замість 6), але per-cluster `K_ota` лише обмежував шкоду від витягнутого вузла ОДНИМ кластером, а не знімав її. Ціна асиметрії виміряна вище й платиться раз на кампанію.

### Wire Format — `[0x9B]` трейлер печатки

OTA-broadcast emit'ить **7** додаткових LoRa-блоків `[0x9B]` після останнього bytecode-чанка: 6 несуть 64-байтну печатку, 7-й — `version_id`. Формат `[0x99]` для bytecode не змінюється — окремий маркер розділяє шари тіла й печатки. Константи — `firmware/common/ota_seal_wire.h` ⟷ `OtaPackagerService`: зміна з одного боку без другого рве OTA.

```
LoRa Reflex Shot блоки (16 байт, далі AES-128-ECB під KEYB):

Chunks 0..N-1:
  [0x99][idx:2][total:2][bytecode:11]                   ← тіло

Seg 1..5 (chunks N..N+4):
  [0x9B][0x00][seg][total:2][seal[11·(seg−1) .. +10]]   ← по 11 байт печатки

Seg 6 (chunk N+5):
  [0x9B][0x00][0x06][total:2][seal[55..63] ‖ PAD:2]     ← останні 9 байт + 2 PAD

Seg 7 (chunk N+6) — version envelope:
  [0x9B][0x00][0x07][total:2][version_id:4 ‖ PAD:7]
```

**Layout детально:**
| Зсув | Розмір | Поле | Опис |
|------|--------|------|------|
| 0 | 1 | `0x9B` | маркер трейлера печатки (відрізняє від `0x99`) |
| 1–2 | 2 | `seg_idx` BE | 1–6 = печатка, 7 = version envelope |
| 3–4 | 2 | `total_chunks` BE | кількість bytecode-чанків — прошивка поле НЕ читає: підписаний total береться з `0x99`-заголовків, тож блок печатки до кампанії не прив'язаний ([`FW.68`](00_07_Action_Plan_Tracker)) |
| 5–15 (seg 1–5) | 11 | `seal_segment` | 11 байт печатки |
| 5–13 (seg 6) | 9 | `seal_segment` | останні 9 байт (6 × 11 = 66 ≥ 64) + 2 PAD `0x00` |
| 5–8 (seg 7) | 4 | `version_id` BE | `firmware.id` — частина підписаного; без нього Солдат не відтворить повідомлення |
| 9–15 (seg 7) | 7 | PAD | `0x00` |

**Чому 6 + 1:** 64 Б ÷ 11 Б = 5.82 → 6 сегментів. `version_id` у 16-байтний сегмент печатки не влазить (1+2+2+11 зайнято), `0x99`-заголовок теж повний — тож окремий seg 7 під тим самим маркером; Королева релеїть його тим самим stateless-шляхом. Ready-mask — по біту на блок: `0x7F`.

### Backend — `OtaPackagerService` + `OtaSealKeyService`

`prepare(firmware, chunk_size:, cluster_id:)` після bytecode-чанків рахує печатку над `@padded_payload` і додає 7 трейлер-блоків; `manifest[:total_packages] = total_chunks + 7` (живий poll-тракт `Downlink::PendingQueueService` рахує від `packages.size`; push-воркер `OtaTransmissionWorker` — superseded FW.60). Без `cluster_id` потік непідписаний — лише для bench-стендів без кластера.

```
seed   = HKDF-SHA256(ikm: master_key, salt: "cluster:#{cluster_id}", info: "silken-ota-ed25519-v1", length: 32)
sk, pk = Ed25519(seed)                                        # OtaSealKeyService
seal   = sk.sign(seal_message(padded_bytecode, firmware.id, lora_total_chunks))   # 64 B
```

**Що прив'язує повідомлення** — `version_id` і `total_chunks` входять у підписане:
- **Re-labeling** (старий image, пере-мічений НОВОЮ версією → печатка над тілом ‖ версією не сходиться). ⚠️ **НЕ плутати з rollback:** валідно підписана СТАРА версія у свіжій сесії печатку проходить — монотонність версій закрита ОКРЕМО на Soldier (`common/ota_antirollback.h`, Flash-KV high-water ключ 0x15; [`00_07` SEC.20](00_07_Action_Plan_Tracker)); ⚠️ брама свіжості відкрита, якщо журнал Flash-KV не змонтувався (`!mounted` → degraded-allow)
- **Truncation attack** (відкидання останніх chunks → змінений `total_chunks` ламає печатку)

**⚠️ Bump-інваріант відкликаного/проваленого OTA (SEC.20).** `Ota_Version_Commit` палить слот `0x15` **у момент APPLY** (Flash-запис contract'а), НЕ в момент доведеного успішного виконання. Наслідок жорсткий: версія N, що впала у vm-error-fallback (3 bytecode-збої → erase contract → embedded baseline), **спалена назавжди** — повторний push виправленого bytecode з тим самим `version_id=N` отримає мовчазний REJECT (`Ota_Version_Is_Fresh` вимагає строго `>`). Фікс = завжди **новий** `BioContractFirmware`-запис (auto-increment `id` > N задарма); re-deploy/re-activate старого запису = no-op на девайсі. Факт відкату видимий backend'у з кожного кадру: wire-звіт `[semantic:1|reverted:1|hiwater&0x3FFF]` у байтах 12..13 ([`03_01 §1.6`](03_01_Firmware_Lifecycle_and_DMA)) / CCM vpd-байт → `TelemetryLog#firmware_report_reverted?` → `EwsAlert firmware_reverted` («re-issue версією > спаленої»).

**Rails-half дзеркало (SEC.20, 2026-07-12).** Той самий інваріант enforce-иться ДО ефіру: `Ota::DeploymentDispatcherService` ([`04_02`](04_02_Business_Logic_and_Services)) тримає per-cluster high-water `clusters.ota_version_hiwater` і відсікає деплой із `firmware.id ≤ hiwater` (строго `>` — число те саме, що seg-7 трейлера і слот `0x15`). Слот палиться **при dispatch** — свідомо суворіше за Солдатів APPLY-time (Rails не має ack-каналу apply-стану: fw-report асинхронний і не гарантує покриття флоту), тож обірвана кампанія теж перевипускається новим записом; кластеру без eligible-шлюзів слот НЕ палиться. UI/API-контракт відмови → [`04_03 §5.7`](04_03_REST_API_v1_Reference).

### Key Management — ключ печатки per-cluster

Дзеркало HKDF-дизайну §2 з власним **info** `"silken-ota-ed25519-v1"`. Salt-домен `"cluster:<id>"` той самий, що в KEYB, — законно, бо вся вага розділення лежить на info, а його унікальність стереже гейт `spec/security/hkdf_domain_separation_spec.rb` (SEC.34, §2).

**Чому per-cluster, а не per-device:** OTA — broadcast: усі Солдати кластера отримують той самий image і ту саму печатку; per-device печатка означала б N трейлерів на один ефір. Cluster — природна одиниця ізоляції (одна Королева / одна організація). Після асиметрії per-cluster стереже вже не від витягнутого вузла (йому нема чого віддати), а розводить кластери між собою: печатка одного не відкривається публічним ключем іншого (`ota_packager_service_spec`).

**Storage:**
- **Backend:** нульовий state — ключ деривується на вимогу з `PROVISIONING_MASTER_KEY`, приватний живе лише в процесі, що пакує; без master — `SecurityError` (SEC.11), а не непідписаний пакет. Прогріту кампанію `Ota::PackageStore` віддає без master-key у процесі. 🔴 **Стеля:** компрометація master = підпис для будь-якого кластера — так само, як у HMAC-ері; асиметрія закрила вузол, не корінь. Runbook кореня — [`06_04 §5.8`](06_04_Secrets_Checklist).
- **Soldier:** **публічний** ключ у Protected Flash сторінки 125 (`0x0803E800`): magic `"KPUB"` (`0x4B505542`) + 8 BE-слів; слідом — KEYB-блок з +40. Пише фабрика (Гілка A `CommandBuilder`; golden-транскрипт дзеркалить `Load_Ota_Seal_Pubkey`). Нова magic, а не стара `"KOTA"`, — щоб формати не плуталися: стара прошивка не прочитає публічний ключ як `K_ota`, нова — `K_ota` як публічний ключ; обидві лишаються fail-closed. Вузлів із KOTA у полі нема (pre-production).
- **SE (SE050-ера):** рішення SE050-MIGRATION ([`00_07`](00_07_Action_Plan_Tracker)). Публічний ключ не секрет, тож SE-резидентність тут — про цілісність слота, не про конфіденційність.

### Dual-Gate Verification — Soldier перед Flash write

Магічний marker `0x45544952` (`"RITE"` LE) — **необхідний, але недостатній**: підтверджує формат, не походження. Печатка — **достатня**, але дорожча. Вердикт — pure-функція `Ota_Seal_Try_Finalize` (`common/ota_seal.h`; host-тести кличуть той самий код, що вшито в Солдата), яку кличуть **обидві** RX-гілки (`0x99` тіло / `0x9B` печатка), бо печатка приходить ПІСЛЯ тіла:

```
Ota_Seal_Try_Finalize(buf, bytes_received, chunks_received, total_chunks,
                      segments_received, pubkey, pubkey_valid, version_id, sig, &data_len)
  1. тіло не зібране АБО segments != 0x7F           → WAIT    (нічого не чіпаємо)
  2. bytes_received ≤ 4                             → REJECT  (це не прошивка)
  3. CRC32(buf[0..data_len)) ≠ хвіст BE             → REJECT
  4. !pubkey_valid                                  → REJECT  (походження не довести — fail-closed)
  5. magic ≠ "RITE"                                 → REJECT  (брама 1, ~1 µs)
  6. Ota_Seal_Verify(pubkey, sig, buf, data_len,
                     version_be ‖ total_be)         → APPLY | REJECT  (брама 2)

Викликач (обидві гілки):
  APPLY  → Ota_Version_Is_Fresh (SEC.20; інакше REJECT) → Write_OTA_Contract_To_Flash
           → Ota_Version_Commit → NVIC_SystemReset
  REJECT → buf[0..3]=0 (жертовний magic-wipe); Reset_Ota_Assembly()
  WAIT   → нічого (тіло зібране, печатка ще летить — або навпаки)
```

`Ota_Seal_Verify` — рівно кроки `crypto_ed25519_check` (h = reduce(SHA-512(R ‖ A ‖ повідомлення)), потім рівняння перевірки, яке відкидає S ≥ L), лише повідомлення стрімиться двома шматками: тіло (≤ 1 019 Б — стеля `ota_buffer`, [`FW.67`](00_07_Action_Plan_Tracker)) лишається в `ota_buffer`, 6-байтний суфікс іде окремо, без копії в стек. Пін рівності зі склеєним `crypto_ed25519_check` — `test_ota_seal.c`.

**Властивості:**
- **Performance:** брама 1 відкидає шум за ~1 µs; печатка рахується лише коли зібрано і тіло, і всі 7 блоків
- **Defense-in-depth:** печатку перевіряють на тих самих байтах, що й браму 1 (`buf[0..data_len)`) — bit-flip між брамами «провезти» не можна
- **Fail-safe (no key):** `ota_seal_pubkey_valid==0` (KPUB не провіжнено, нульовий ключ або стара magic) ⇒ REJECT
- **Magic-wipe — прибирання, не захист:** REJECT затирає `buf[0..3]` у RAM, але boot цього буфера не читає (контракт вантажиться лише з Flash, `.bss` скидається); захищає те, що запис у Flash стоїть лише за APPLY
- **Ordering-safe — частково:** фіналізація спрацьовує з гілки, що завершилась ОСТАННЬОЮ (тіло чи печатка), але блоки печатки, що прийшли ДО першого чанка тіла, світанок кампанії стирає ([`FW.68`](00_07_Action_Plan_Tracker))
- **Час не секрет:** перевірка variable-time, і це законно — печатка, публічний ключ і тіло публічні; constant-time compare HMAC-ери більше не потрібен

### Queen — сліпий гонець

Королева печатку НЕ перевіряє і ключа не має: включає лише `ota_seal_wire.h`, тримає 7 блоків як є й ретранслює. Автентифікація Backend → Soldier наскрізна: скомпрометована Королева може не доставити кампанію, але не може її підробити — Солдат відкине на брамі 2. ⚠️ Підробити ≠ підмінити: справжню печатку ІНШОЇ кампанії свого кластера з версією вище за приплив вузла вона доставити може (↓ «Стелі»). Перевірка на Королеві дала б лише economy-of-scale (1 verify замість N), а Солдатів не захистила б: вони перевіряють і так.

### Безпекові параметри

| Параметр | Значення | Обґрунтування |
|----------|---------|---------------|
| Алгоритм | Ed25519 (RFC 8032, PureEdDSA, SHA-512) | детермінований (несуче для повторного пакування); ~128-біт рівень |
| Печатка | 512 біт (64 Б, R ‖ S) | 6 LoRa-сегментів |
| Ключ на вузлі | публічний, 256 біт (32 Б) | сторінка 125, magic `"KPUB"`; не секрет |
| Ключ підпису | лише бекенд, seed = HKDF-SHA256 | `PROVISIONING_MASTER_KEY`; на вузлі НЕМА |
| Scope | per-cluster (salt `"cluster:#{id}"`) | ізоляція кластерів, broadcast-сумісність |
| Domain separation | `info: "silken-ota-ed25519-v1"` | гейт унікальності info (SEC.34) |
| Magic marker | `0x45544952` ("RITE" LE) | брама 1 |
| Підписане | `padded_bytecode ‖ version_id ‖ total_chunks` | anti-relabel + anti-truncation |
| Бібліотека (вузол) | Monocypher 4.0.3, pinned submodule | `crypto_eddsa_check_equation` відкидає S ≥ L (malleability) |
| Бібліотека (бекенд) | гем `ed25519` | паритет — золотий вектор: Ruby ⇒ прошивка ⇒ OpenSSL |
| Wire overhead | +7 рефлекс-пострілів (16 Б @ SF9 ≈ 165 мс ефіру кожен) | ≥ 7 % ефіру кампанії: тіло — щонайбільше 93 чанки (стеля Солдата, [`FW.67`](00_07_Action_Plan_Tracker)) |

### Стелі печатки й відкриті дефекти доставки (адверсарне рев'ю, 2026-10-06)

Рев'ю застосування в рамці атакувальника (KEYB відомий, дамп вузла, захоплена Королева; модель асемблера Солдата, ~268 тис. ворожих кадрів) **непідписаного запису не знайшло**: перевірка й запис у Flash беруть той самий `ota_buffer`/`data_len`, той самий `received_ota_version` годує і свіжість, і commit, а довжина підписаного повідомлення прив'язує `data_len` до total. Знайшло інше:
- 🔴 **Доставка — дві стелі, ширші за FW.23.** Чинний контракт (2 855 Б) не вміщується ні в `ota_buffer` (93 чанки ≈ 1 019 Б), ні у Flash-слот (одна сторінка 2 КБ) — [`FW.67`](00_07_Action_Plan_Tracker): гейт диспетчера відмовляє такій кампанії ДО burn, а місткість не піднімають до реалізації гілки (Б): після неї контракт тоншає або зникає, його розмір міряє реалізація (Б), і якщо не влізе — стелю піднімають тією ж ревізією (⚖️ founder 2026-10-06). Трейлер іде одним проходом і не перезапитується: при N Солдатах на Королеву шанс дерева зібрати 7 блоків ≈ N⁻⁷ (HMAC-ера — N⁻⁴) — [`FW.68`](00_07_Action_Plan_Tracker): лік ратифіковано (⚖️ founder 2026-10-06) — перезапит `0x55` покриватиме й трейлер, світанок кампанії скидатиме стан печатки на Королеві, а Солдат відкидатиме блок печатки з чужим total; але відповідь на `0x55` сьогодні лягає в сон запитувача (вухо закрито до зойку) — ⚖️-поправка там само, реалізація відкрита.
- **Печатка прив'язує кластер, версію й total — і більше нічого.** Ні canary-когорти, ні `target_hardware_type`/`tree_family`, ні строку, ні відкликання: власник KEYB чи захоплена Королева може доставити будь-яку перехоплену справжню кампанію свого кластера з версією вище за приплив вузла — зокрема відкликану чи canary-only — на будь-якого Солдата кластера.
- **Малопорядковий публічний ключ приймає будь-яку печатку** (перевірка Monocypher кофакторна), а `Ota_Seal_Pubkey_From_Words` відкидає лише нульовий. Шлях туди — лише запис сторінки 125, а хто її пише, той і так ставить свій ключ; HKDF-ключ бекенду малопорядковим не буває.
- **Тегу типу в підписаному нема:** мертвий push-воркер запечатав би `TinyMlModel` тим самим ключем, з id іншої таблиці як версією, — оживляючи той шлях, додай тег типу.
- Атакувальник може змусити щонайбільше одну перевірку на 8 пробуджень Солдата (1 чанк тіла + 7 блоків із валідним CRC і `RITE`); вікно IWDG (~26 с, [`03_01`](03_01_Firmware_Lifecycle_and_DMA)) перевірку не обриває.

### Test Coverage — ✅
- **Backend:** `ota_seal_key_service_spec` (формула HKDF, детермінізм, ізоляція кластерів, SEC.11, публічний ключ) · `ota_packager_service_spec` (золотий вектор, повторний `prepare` байт-у-байт, relabel/truncation/tamper, 7 блоків, маніфест) · `spec/integration/ota_firmware_flow_spec.rb` (трейлер → печатка → публічний ключ кластера приймає; підмінене тіло, чужа версія, обрізання, чужий кластер — ні)
- **Firmware:** `test_ota_seal.c` (золотий вектор Ruby перевіряють прошивка, Monocypher і OpenSSL; кожен змінений вхід ламає перевірку; OpenSSL ≡ Monocypher у ключах і підписах; стрімінг ≡ `crypto_ed25519_check`) · `test_soldier_logic.c` (збирання трейлера, `Ota_Seal_Try_Finalize` APPLY·WAIT·REJECT) · `test_queen_logic.c` (реле 7 блоків, FW.52б воскресіння на сьомому)
- **Золотий вектор** (master `"silken-fw23-golden-master-key"`, кластер `"cluster-golden-1"`) — один на обидві мови: міняєш формат повідомлення чи деривацію → перегенеровуєш у ОБОХ (`ota_packager_service_spec` ⟷ `test_ota_seal.c`). Мутаційно перевірено (2026-10-06): прибраний `version_id` у підписаному (Ruby) і нехешований суфікс (C) — обидва червоні.

> **Cross-ref:** FW.1 (HKDF master-key), FW.2 (CCM MIC телеметрії — паралельний concept), SEC.20 (anti-rollback), [`03_05 §6`](03_05_Hardware_Symmetric_Crypto_and_Security) «Queen → Soldier (OTA LoRa)», [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA) опкод `0x9B`.

---

## 5. Factory Flashing Operations Security 🤖 (SEC.3, 2026-05-17)

> ⚠️ **Internal Admin Tool — поза публічним REST API.** Цей розділ описує **окремий канал** доставки ключів від Rails Backend до програматора (SWD/JTAG). Він НЕ є описом `POST /provisioning/register` (реєстрація після деплою, Zero-Trust, без ключа у відповіді — [`04_03 §5.2`](04_03_REST_API_v1_Reference) залишається незмінним). Threat model нижче розроблений з нуля з урахуванням фізичного доступу на заводі.

**Cross-ref:** [`00_07` — SEC.3](00_07_Action_Plan_Tracker) | §1 (pipeline design) | §2 (HKDF derivation) | 03_05 §3.6 (RDP Level 2) | 03_05 §3.7 (ATECC608B) | SEC.1 (Gnosis Safe multisig) | SEC.2 (RDP activation) | SEC.6 (Secure Element) | SEC.9 (WeakKeyDetector)

---

### Implementation status (2026-05-24)

> **Реєстр сервіс-об'єктів (роль кожного `FactoryFlashing::*`) — дім [`04_02 §8`](04_02_Business_Logic_and_Services); модель сесії — [`04_01` ProvisioningSession](04_01_Data_Models_and_Entities).** Нижче — security-нюанси + impl/bench-статус per шар (дім — цей файл, 03_06).
>
> Дизайн A–D нижче імплементовано як Rake-driven internal admin tool. Реальний `STM32_Programmer_CLI` subprocess execution та live `cryptoauthlib` I²C — gated на HW bench (deferred).

| Шар | Файл | Статус |
|-----|------|--------|
| Session AASM | `app/models/provisioning_session.rb` | ✅ `pending → supervisor_approved → active → completed \| failed`; 2-Person Rule = `supervisor_id != operator_id` (валідація) **+ `approve` guard `credentials_verified?` (true лише через `approve_with_credentials!` — Argon2id-пароль і TOTP супервайзера, без активного MFA — відмова); сирий `approve!` з console відмовляється → оператор, що лише *назвав* супервайзера, схвалити сам НЕ може** |
| Master key source | `app/services/factory_flashing/master_key_source.rb` | ✅ `EnvAdapter` (з `Security::WeakKeyDetector` SEC.9), `BitwardenAdapter` skeleton (raise `NotImplementedError` — TODO live `bw` API). Fetched ключ **наскрізно живить деривацію** (SEC.3 DI): Session тримає його у `@master_key` і передає параметром — non-ENV adapter підключається без правок сервісів |
| UID→DID resolver | `app/services/factory_flashing/tree_resolver.rb` | ✅ [FW.54] one-pass прив'язка: 24-hex UID → `DidDerivation.wire_did` → Tree create (`CLUSTER_ID`+`TREE_FAMILY_ID`) / re-flash (`trees.silicon_uid_hex` збігся) / bind (legacy) / **DID-колізія → `CollisionError` = quarantine юніта** (03_01 §7). Peaq свідомо НЕ enqueue'иться (offline-фабрика; peaq — за польовим register) |
| UID-readout parser | `app/services/factory_flashing/uid_readout.rb` | ✅ [FW.54] толерантний парсер `-r32 0x1FFF7590`-виводу (keyed на адресу) → три слова → 24-hex; точний формат live-CLI = bench-confirm (RUNBOOK 1.3) |
| Command emission | `app/services/factory_flashing/command_builder.rb` | ✅ `preflight_commands` (`-c` + `-r32 0x1FFF7590 12` UID-read одним викликом, обидві гілки) + Гілка A — `-e` сторінок ключів і `STM32_Programmer_CLI -w32` цілими doubleword'ами (суміжні слова одним рядком, діру добиває `0xFFFFFFFF`; кожен рядок несе власний `-c`): Tree — `KEYL`/`LSED`/`KPUB`/`KEYB`, Gateway — `KEYL` (= KEYB-значення)/`KEYC`/`EDSK` (EDSK = L1 QATT сім'я голосу Королеви, Gateway-only; генерується `Session`'ом на фабричному хості — НЕ HKDF, у БД лише pubkey), IWDG-заморозка + RDP L0/L1 (байта L2 у `RDP_OPTION_BYTE` немає — ⚖️ SEC.2 2026-09-28); Гілка B — **той самий** `-w32`-набір обох типів (`protected_flash_commands`; Гілка B = A + identity-chip, ⚖️ делеговано 2026-09-27 — врізка «Набір ключів Гілки B», §1; доти skip-key-writes = цегла на першому boot, а Gilka-B Королева не мала ні KEYC, ні EDSK) |
| Subprocess executor | `app/services/factory_flashing/executor.rb` | ✅ dry-run default (`[dry-run] cmd`); `dry_run: false` → `Open3.capture3` з `ProgrammerMissingError` коли CLI відсутній у PATH; `CommandFailedError` зупиняє на першому non-zero exit. Дані `-w32` — ключі зі справжнього master key, тож і друк dry-run, і повідомлення помилки (його `Session` персистить у `provisioning_sessions.error_message`) несуть лише адресу й лічильник слів (`Executor.redact`, позиційно), а 8-hex-слова stderr маскуються. ⚠️ У argv процесу CLI ключі все одно є — вимога до фабричного хоста, §5 |
| ATECC provisioning | `app/services/factory_flashing/secure_element_provisioner.rb` | ✅ Гілка B skeleton — emit `atcab_init` + `atcab_read_serial_number` + slot writes (1/2/3; Slot 0 reserved — не пишеться з 2026-09-27) + `atcab_lock_config_zone` + `atcab_lock_data_zone`; raw key bytes scrubbed (`/* NB elided */`) |
| Audit trail | `app/services/factory_flashing/audit_trail.rb` | ✅ `AuditLog(action: "factory_flash")` chain-hashed + `MaintenanceRecord(action_type: :installation, system_generated: true)`; metadata містить `operator_id`/`supervisor_id`/`batch_id`/`flash_addr`/`rdp_level`/`se_serial_hex`/`firmware_version`/`command_count`/`dry_run` |
| Orchestrator | `app/services/factory_flashing/session.rb` | ✅ `ActiveRecord::Base.transaction` — failure rolls back HardwareKey + audit writes разом; `PreflightError` для non-approved sessions / missing device / unavailable master key. **[FW.17] Re-provision дерева** (рядок `HardwareKey` уже є) — нова епоха ключа ([`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security), реалізовано 2026-09-28): KEYL = K0_e від поточного master, свіжий журнал Flash-KV (`FactoryFlashing::FlashKvImage`, стор. 122–123 стираються обидві), у БД `epoch` + 1 · `key_version` 0 · старий ключ у grace до першого MIC новим, аудит несе `key_epoch`; dry-run епоху лише планує. ⊕ 2026-09-29 (⚖️ founder, врізка «Провіжн дерева» нижче): K_seed теж деривується поточним master тією ж транзакцією, а свіжий журнал пишеться на КОЖНОМУ провіжні дерева, першому теж. Королеви це не стосується — її re-flash і є доставкою ротованого KEYC. **[FW.54] Wrong-board guard**: live-режим ганяє `preflight_commands` і звіряє паспорт плати (`UidReadout`) з `trees.silicon_uid_hex` ДО деривації/першого `-w32` — чужа плата → `WrongBoardError`, навіть HardwareKey не матеріалізується (dry-run/безпаспортні: skip). Безпаспортну плату (Королеву) впізнати нема чим, а `-e` сторінки ключів незворотний, тож preflight читає й перше слово стор. 124: уже прошиту (чи нечитану) таку плату конвеєр стирає лише за `REFLASH_ACK=<device_uid>` — оголошений намір, як набране «RDP2» стендового скрипта; інакше чужа Королева на джизі втратила б свої ключі. Dry-run pubkey голосу Королеви не чіпає — план не підміняє L1-ідентичність. Preflight-ключ НЕ відкидається: `@master_key` → `HardwareKeyService.provision` / `OtaSealKeyService.public_key_hex_for` / `SeedDerivation.derive_seed` параметром (SEC.3 DI; runtime-викликачі цих сервісів лишаються на ENV-fallback) |
| Operator CLI | `lib/tasks/factory.rake` | ✅ `factory:flash[device_uid,batch_id,gilka,operator_id,supervisor_id,firmware_version]` — **[FW.54] Tree: device_uid = 24-hex silicon UID** (→ `TreeResolver`; create-гілка = `CLUSTER_ID`+`TREE_FAMILY_ID` env; голий `SNET-` DID лише для дерева з уже прив'язаним паспортом); Gateway: uid як досі (`ATECC_SERIAL` env для Гілки B, `RDP_LEVEL` env override) → `factory:approve[session_id]` (**mandatory `SUPERVISOR_PASSWORD` + `SUPERVISOR_OTP` env — супервайзер автентифікується власним паролем і поточним TOTP-кодом, SEC.3**) → `factory:execute[session_id]` (`EXECUTE=1` для real subprocess; `REFLASH_ACK=<device_uid>` — перепрошивка вже прошитої безпаспортної плати, зокрема доставка ротованого KEYC Королеві; `STLINK_SN=<серійник зонда>` — станція з кількома ST-LINK: кожен рядок підключається наново, а паспорт плати звіряє лише перший, тож `sn=` стоїть у КОЖНОМУ `-c` (UM2237: `sn` ⊥ `index`, дефолт — index 0; лише алфанумерика — рядок іде в шелл). Кількість зондів конвеєр не перевіряє: вивід `--list` на кремнії не бачили) |

> **[SEC.3] Authenticated 2-Person approval:** `factory:approve` вимагає `SUPERVISOR_PASSWORD` і `SUPERVISOR_OTP` — `ProvisioningSession#approve_with_credentials!` верифікує пароль через `supervisor.authenticate` (Argon2id), а код — через `User#verify_totp!`. Оператор може *назвати* супервайзера, але НЕ схвалить сесію без того, щоб супервайзер фізично ввів власний пароль і код зі свого автентифікатора (закрито колишній skippable `SUPERVISOR_ID` env-match). **Сирий `approve!` (Rails console) теж закрито кодом (2026-06-15):** перехід `approve` має guard `credentials_verified?`, що true лише всередині `approve_with_credentials!` після успішної автентифікації → console self-approve неможливий (`AASM::InvalidTransition`). **Залишок — суто операційний:** raw-SQL / object-manipulation (`update_column` / `instance_variable_set`) обходить будь-який in-process guard → межа §5 access-control (master-key лише `super_admin` + MFA), не код.
>
> ⚖️ **Другий фактор на схваленні — ратифіковано ДЕЛЕГОВАНО 2026-09-28 (founder доручив делеговану ратифікацію відкритих присудів §02–§03 за рекомендацією).** Схвалення = пароль + поточний TOTP-код супервайзера; супервайзер без активного MFA (`mfa_enabled?`) не схвалює нічого. **Підстава:** 2-Person Rule стоїть на автентичності ДРУГОЇ людини, а пароль — один фактор, який підглядають на тій самій фабричній станції; другий фактор у застосунку вже живий (вхід, [`00_07`](00_07_Action_Plan_Tracker) S6.21 §🗄️). ⚠️ **Рекомендацію ЗВУЖЕНО при ратифікації:** вона відмовляла без MFA лише `super_admin`, а `supervisor_id` — будь-який `User`, ролі ніхто не судить (e2e-спека сама бере супервайзера з роллю `admin`), тож для решти ролей лишався б пароль-only шлях — рівно те, що присуд закриває; власна ціна рекомендації («супервайзер без MFA мусить його ввімкнути») вже говорила про всіх. **Ціна:** ще одна env-змінна на кроці схвалення; кожен супервайзер мусить мати MFA; `otp_last_used_at` спільний із входом, тож код, використаний на вході, на схваленні не пройде (анти-replay) — у тому ж 30-с кроці треба дочекатись наступного коду. **Найслабша ланка:** живого прогону конвеєра не було (нога CLI в [`00_07`](00_07_Action_Plan_Tracker) SEC.3), тож форму кроку ніхто не пробував руками. Носії — `spec/models/provisioning_session_spec.rb` (напівактивований MFA, роль без MFA, код входу) і `spec/integration/factory_flashing_e2e_spec.rb` (без коду — `abort`).

> ⚖️ **[FW.17] Провіжн дерева — два присуди founder 2026-09-29, ратифіковано за рекомендацією.** Обидва знайшла реалізація форми «re-provision = нова епоха ключа» ([`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security), ⚖️ 2026-09-28).
>
> **(1) K_seed на re-provision — поточним master.** Сесія передеривовує KEYL і KPUB/KEYB, а K_seed (LSED) брала з рядка `HardwareKey`, тож «перепровіжн флоту», яким ранбук [`06_04 §5.8`](06_04_Secrets_Checklist) A.3 лікує компрометацію master, лишав би DCI-сід старим і скомпрометованим. Тепер `reprovision_tree_key!` деривує K_seed (`SeedDerivation.derive_seed(did, master_key:)`) і пише його в рядок тією ж транзакцією, що й епоху. **Підстава:** K_seed = HKDF(master, DID), тож під незмінним master крок ідемпотентний (той самий сід), а під новим — рівно те, що обіцяє ранбук. **Ціна:** рядок і LSED змінюються разом лише в живому прогоні, а dry-run лише планує; K_seed живить тільки ХОЛОДНИЙ старт Лоренца, тож новий сід набирає сили з першою холодною деривацією вузла. **Найслабша ланка:** як теплий стан Лоренца в RTC (DR16–DR19 переживає SWD, поки RTC-домен живлений) поводиться проти бекендової траєкторії після зміни сіда — не відкривано й не міряно.
>
> **(2) Свіжий журнал Flash-KV — і на ПЕРШОМУ провіжні.** Той самий образ (`FlashKvImage`, стирання сторінок 122–123), що й на re-provision. **Підстава:** плата, що вже бувала на стенді (dev-прошивка, скинута БД), несе чужий журнал — вціліла версія ратчета `0x13` дала б boot `ratchet^v(K0)` ≠ K0, тобто глухий вузол, а вцілілий DLFC `0x12` = N глушив би команди нового рядка Rails, доки лічильник Rails не переросте N; `0x15` = приплив кластера закриває повтор старого підписаного OTA й для нового вузла. ⊕ **Якір FC `0x14` = 1 (⚖️ founder 2026-10-05, [`00_07`](00_07_Action_Plan_Tracker) SEC.41):** лічильник кадрів CCM під свіжим ключем стартує біля нуля, а не з HRNG рівномірно в [1, 0xFFFFFE], тож 24-бітний простір увесь попереду, а пересів із HRNG лишається справжнім fallback мертвого Flash. **Ціна:** стирання двох сторінок на кожному першому провіжні (на новому чипі — no-op) і один рядок `-w32`. **Найслабша ланка:** на новому чипі сторінки й так чисті, тож виграш — лише для перевикористаних плат, частки яких у партії ніхто не знає.
>
> **Реалізація (✅ 2026-09-29):** `FactoryFlashing::Session` — журнал ставиться в `ensure_hardware_key` для будь-якого дерева, K_seed — у `reprovision_tree_key!` (разом із планом dry-run); піни — `session_spec` (перший провіжн пише журнал · Королеві журналу немає · dry-run планує новий сід, рядок не чіпає) і `session_run_execute_path_spec` («K_seed на re-provision дерева»: той самий master → той самий сід, новий → новий, рядок і LSED разом). Мутації обох рядків і кожної з трьох точок — червоні.

**Test coverage:** RSpec — `spec/models/provisioning_session_spec.rb` (AASM/validations + `approve_with_credentials!`), `spec/services/factory_flashing/*` (вкл. `tree_resolver_spec` — чотири долі кремнію; execute-path шим з UID-verify pass/wrong-board), `spec/integration/factory_flashing_e2e_spec.rb` (Rake trio: one-pass UID→Tree→ключі, firmware-equivalent HKDF, legacy-DID abort). Counts → suite.

**Зразок dry-run вивода** (Tree, Гілка A, `rdp_level` 1; кожен рядок — окремий процес CLI, тож `-c` під скидом несе кожен; дані `-w32` друк заступає лічильником слів):
```
[dry-run] STM32_Programmer_CLI -c port=SWD mode=UR -r32 0x1FFF7590 12 -r32 0x0803E000 4   # [FW.54] UID + перше слово стор. 124
[dry-run] STM32_Programmer_CLI -c port=SWD mode=UR -e 122 123 124 125    # журнал Flash-KV + сторінки ключів: -w32 сам не стирає
[dry-run] STM32_Programmer_CLI -c port=SWD mode=UR -w32 0x0803D000 <8 words>
          # стор. 122: свіжий журнал SKV1 · FINI · 0x15 = приплив OTA кластера (FW.17) · 0x14 = 1 — якір FC (SEC.41)
[dry-run] STM32_Programmer_CLI -c port=SWD mode=UR -w32 0x0803E000 <14 words>
          # стор. 124: KEYL magic + 4 AES words, LSED magic + 8 K_seed words — 7 doubleword'ів
[dry-run] STM32_Programmer_CLI -c port=SWD mode=UR -w32 0x0803E800 <16 words>
          # стор. 125: KPUB magic + 8 слів публічного ключа печатки (FW.23), стерте слово, KEYB magic + 4 words (+40, FW.2 (в)), стерте слово
[dry-run] STM32_Programmer_CLI -c port=SWD mode=UR -ob IWDG_SW=1 IWDG_STOP=0 IWDG_STDBY=0   # SEC.15 — ДО RDP
[dry-run] STM32_Programmer_CLI -c port=SWD mode=UR -ob RDP=0xBB          # L1 — сирий байт, не номер рівня
```

**Hardware-gated TODO:**
- 👤 Реальний `STM32_Programmer_CLI` execution на STM32WLE5JC bench (зараз `EXECUTE=1` raise'ить `ProgrammerMissingError` без CLI у PATH). ✅ (2026-06-07) Software-половина доведена шим-інтеграцією: fake-CLI на PATH → повна Session через реальні subprocess'и (ok/verify-fail/rdp-fail + [FW.54] UID-verify pass/wrong-board, stop-on-fail, transcript) — `spec/services/factory_flashing/session_run_execute_path_spec.rb`; на bench лишається фізика SWD **+ звірити реальний формат `-r32`-виводу проти `UidReadout` парсера (RUNBOOK 1.3)**
- 👤 Bitwarden Secrets Manager live API (`BitwardenAdapter#fetch_master_key` placeholder)
- 🔗 Live SE I²C call в `SecureElementProvisioner` — eval-kit-gated (SE = **SE050**, SEC.6 ✅; `cryptoauthlib`→SE05x/`sss` код-міграція → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker) (B))

---

### A. Access Control до `PROVISIONING_MASTER_KEY`

**Хто має право запускати Factory Flashing Tool:**

| Роль | Право | Умова |
|------|-------|-------|
| `super_admin` | Ініціювати provisioning сесію | HSM presence + MFA. MFA стоїть і на ВХОДІ (TOTP живий з 2026-08-20, [`00_07`](00_07_Action_Plan_Tracker) `S6.21` §🗄️), і на СХВАЛЕННІ сесії: `factory:approve` вимагає пароль і поточний TOTP супервайзера, без активного MFA — відмова для будь-якої ролі (⚖️ делеговано 2026-09-28 — врізка «[SEC.3] Authenticated 2-Person approval» вище) |
| `admin` | Спостерігати за прогресом | Read-only audit view |
| Factory Operator (без Rails-ролі) | Виконувати фізичне підключення | Лише після авторизації supervisor'а; UI показує тільки статус, не ключ |

**Як master key потрапляє до інструменту (три варіанти, від кращого до гіршого).** Після SEC.3 DI деривація приймає ключ параметром від `MasterKeySource` — варіанти 1–2 підключаються новим адаптером без правок derivation-сервісів (до DI non-ENV adapter був би мертвим кодом — деривація однаково читала ENV):

1. **HSM injection (рекомендовано для > 1 000 unit):** `PROVISIONING_MASTER_KEY` ніколи не покидає HSM (AWS CloudHSM / Thales Luna). Інструмент викликає HSM API для деривації `device_key = HKDF(master_key, device_uid)` всередині апаратного модуля → отримує лише готовий `device_key`. `master_key` у RAM інструменту не з'являється жодного разу.

2. **Envelope encryption (TRL 6/7, pilot batch):** `PROVISIONING_MASTER_KEY` зберігається у Bitwarden Secrets Manager або 1Password Secrets Automation. Перед кожною сесією — short-lived token (TTL 15 хв) генерується через API і передається інструменту через `PROVISIONING_SESSION_TOKEN` ENV. Після закінчення TTL — інструмент не може деривувати нові ключі без нового токена.

3. **Direct ENV (development/lab only):** `PROVISIONING_MASTER_KEY` встановлюється в ENV вручну перед запуском. Недопустимо у field-batch. `Security::WeakKeyDetector` блокує запуск з тест-векторами ([`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security), SEC.9).

**Ротація master key:**

- Нова сесія починається лише після верифікації нового ключа через `Security::WeakKeyDetector` (CLI runbook у [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security)).
- `previous_aes_key_hex` (Dual-Key Grace Period у `HardwareKey`) активний до підтвердження прошивки всіх пристроїв у партії. ⚠️ **Механізм під цим рядком — лише половина:** з 2026-09-28 re-provision дерева пише новий KEYL (нова епоха від поточного master, [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)), а з 2026-09-29 і K_seed — поточним master, тією ж транзакцією, що й рядок (⚖️ founder, врізка «Провіжн дерева» в §5; доти K_seed брався з рядка й під новим master лишався старим). Відкритими лишаються кластерні похідні, які бекенд деривує з master на льоту (ключ печатки OTA — `OtaSealKeyService`), на бекенді зміняться для всього флоту одразу, тоді як пристрої триматимуть старий публічний ключ — печатка розійдеться з кожним вузлом. Форма ротації й відновлення — [`00_07` — FW.17](00_07_Action_Plan_Tracker).
- Fail-closed boot guard: `config/initializers/master_key_strength_check.rb` відмовляє у запуску Rails якщо `PROVISIONING_MASTER_KEY` = тест-вектор (SEC.9).

---

### B. Anti-Key-Leak via Factory Operator

**Принцип нульового доступу оператора до сирого ключа:**

```
PROVISIONING_MASTER_KEY
        │
        ▼
  Backend (Rails)          ← оператор не бачить цей шар
  HKDF(master, uid) ──────→ device_key (32 байти)
        │
        ▼ (через захищений канал: USB/SWD adapter)
  STM32 Protected Flash    ← оператор бачить: Status: "key_burned"
  FLASH_KEY_ADDR (0x0803E000)
```

**Що показує UI оператору:**
```json
{ "status": "key_burned", "device_uid": "SNET-A1B2C3D4", "timestamp": "..." }
```
Ніколи: `aes_key`, `lorenz_seed`, `master_key`, байтове значення.

**Технічні заходи проти витоку:**

| Загроза | Захід |
|---------|-------|
| Скріншот/відеозапис ключа | UI не рендерить ключ; Backend повертає лише `{ status }` |
| Clipboard intercept | Кнопки Copy відсутні на сторінці provisioning UI |
| Logfile з ключем | `filter_parameters += [:aes_key, :lorenz_seed, :device_key, :binary_key]` у Rails; `Sentry` scrub_patterns покривають `aes_key` |
| Persistent key cache на factory machine | Ключі живуть у памʼяті Ruby-процесу (`HardwareKey` → рядки команд `Executor`) і в argv процесу CLI; zero-copy чи перезапису буфера в коді немає. Друк dry-run і персистоване повідомлення помилки ключів не несуть (`Executor.redact`). ⚠️ **Вимога до фабричного хоста:** однокористувацький kiosk, `/proc` з `hidepid=2`, без auditd-логування argv (execve) — інакше ключі читаються з таблиці процесів, і в кожному рядку `-w32` лежить цілий блок |
| Shoulder surfing / screen recording | Factory laptop з privacy screen filter; Provisioning Tool запускається у fullscreen kiosk mode без title bar |
| Key exposure через SWD/JTAG replay | RDP піднімає останній рядок того самого прогону конвеєра (`-ob RDP=0xBB` — пілот, L1); продакшн гонить конвеєр на `RDP_LEVEL=0`, а L2 палить поза ним після self-test і WRP ([`03_05 §3.6`](03_05_Hardware_Symmetric_Crypto_and_Security)). Прапорця `--rdp` у CLI немає — це опція стендового `01_option_bytes.sh` |

**Secure RAM wipe після Flash write (Гілка A):**
```c
// Після успішного HAL_FLASH_Program_Word() виклику:
memset(temp_key_buffer, 0, sizeof(temp_key_buffer));
// АБО (більш надійно на ARM):
volatile uint8_t *p = temp_key_buffer;
for (size_t i = 0; i < 32; i++) p[i] = 0;
__DSB(); __ISB();  // barrier — унеможливлює оптимізацію компілятора
```

---

### C. Audit-Trail Provisioning Сесій

**Кожна provisioning сесія генерує append-only записи в двох місцях:**

**1. `AuditLog` (chain-hashed, `pg_advisory_xact_lock(827549841, org_id)`):** `action: "factory_flash"`, `auditable` = `HardwareKey`, актор = оператор; `metadata` несе оператора й **supervisor'а** (2-person rule), batch, адресу й RDP-рівень прошивки, серійник SE (Гілка B), версію прошивки й розмір транскрипту — сирі байти ключа **ніколи**. Дім точного переліку ключів — `FactoryFlashing::AuditTrail#audit_metadata` (`app/services/factory_flashing/audit_trail.rb`), не цей документ; ⛔ перейменовувати ключі можна лише до першого прод-запису — далі вони живуть у хеші ланцюга ([`04_01 §7`](04_01_Data_Models_and_Entities), ARCH.57).

**2. `MaintenanceRecord(action_type: :installation)`** — закриває loop «фізично прошито ↔ DB-зареєстровано»; `system_generated: true`, бо на стенді немає камери (Evidence Protocol — [`04_01 §7`](04_01_Data_Models_and_Entities)). Обидва записи пишуться в одній транзакції з `HardwareKey`: невдалий ключ відкочує й аудит, тож у ланцюг не потрапляє рядок без пристрою.

**Tamper-evident retention policy:**
- `AuditLog` — заборонено видаляти (Rails guard: `before_destroy` кидає `ActiveRecord::ReadOnlyRecord`, [`04_01 §7`](04_01_Data_Models_and_Entities)).
- Chain hash перевіряється при кожному audit export (`AuditLog.verify_chain_integrity`).
- Мінімальний retention: ⚖️ **строк НЕ ухвалено** — дім рішення [`00_07`](00_07_Action_Plan_Tracker) SEC.18, і RoPA свідомо тримає `[TBD]`. 🔴 Тут стояло «7 років (GDPR Article 17(3)(b) — legal obligation exception)», і обидві половини не тримаються: число не було ухвалене ніде (а сусідня нога SEC.18 прямо забороняє ВИГАДУВАТИ строки), а літера **(b)** до нас текстуально не тягнеться — [`dpia_art35`](protocols/legal/dpia_art35.md) R3 (2026-09-06) прочитав первинку: (b) вимагає обовʼязку «*by Union or Member State law*», якій ПКУ/ЗУ про бухоблік не відповідають, тож кандидати — **(e)** або Art.6(1)(f), і вибір належить юристу.

**2-Person Rule (рекомендовано для > 100 unit batch):** supervisor має підтвердити сесію через окремий Rails UI перед тим як інструмент отримає session token. Реалізується через `ProvisioningSession` AASM: `pending → supervisor_approved → active → completed/failed`.

---

### D. Гілка A vs Гілка B Threat Model Diff

> ⚠️ **Колонку «Гілка B» писано в легасі-моделі ATECC, де ключі жили в SE.** За присудом 2026-09-27 (врізка «Набір ключів Гілки B», §1) runtime-ключі Гілки B — KEYL · LSED · KEYB · KPUB, а в Королеви всі — лежать у Protected Flash і їдуть тим самим SWD `-w32` із фабричного хоста, тож у рядках «Фізичне вилучення», «Factory insider» і «Cold-boot» Гілка B для НИХ рівна Гілці A (для insider-а — не краща). Перевага колонки стосується лише того, що лежить у SE: ціль — ідентичність дерева, а сьогодні транскрипт пише туди тільки копію KPUB — з 2026-10-06 публічну (слоти 1/2 — TODO), тож сьогодні перевага нульова й для Солдата; у Королеви SE немає взагалі.

| Вектор атаки | Гілка A (Protected Flash STM32) | Гілка B (ATECC608B / STSAFE-A110) |
|-------------|----------------------------------|-----------------------------------|
| **Фізичне вилучення ключа з чіпа** | RDP Level 1: ускладнено (voltage glitching можливий на старих ревізіях); RDP Level 2: практично неможливо | Лише вміст SE (сьогодні — копія KPUB у Slot 3, публічна; ідентичність — ціль): ATECC data zone lock + DPA-hardened silicon — key never leaves chip в plaintext; fault injection → self-erase. Runtime-ключі — як Гілка A (RDP) |
| **Chip swap (ворог замінює STM32/ATECC на інший)** | STM32 не має унікального hardware ID прив'язаного до DB — swap непомітний до першого uplink (DID mismatch детектує Rails) | ATECC serial (9 байт, factory-burned) мусить пінитись у пару `(device_uid, серійник SE)` — ⚠️ ціль: сьогодні він лише в `provisioning_sessions.se_serial_hex`, `HardwareKey` колонки не має. Чужий ATECC → provisioning API reject з 409 |
| **Replay provisioning request** | `POST /provisioning/register` — ідемпотентний через duplicate DID check (409) | Те саме + ATECC serial pinning |
| **Factory insider attack (оператор копіює ключ)** | Ризик: SWD adapter може перехопити байти під час write якщо не використовується HSM injection | Не нижчий, ніж у Гілці A: runtime-ключі йдуть тим самим SWD `-w32` з хоста, копія в Slot 3 з 2026-10-06 публічна, тож її I²C-запис секрету не несе, а ідентичність у легасі-скетчі народжується на хості (крок 3 §1); нижчим ризик стане лише з on-chip keygen SE05x — ціль, не код |
| **Cold-boot attack на factory laptop RAM** | Ризик: `device_key` у RAM до wipe (~мс) | Той самий, що в Гілці A: runtime-ключі деривує Rails-хост і пише SWD, а ідентичність сьогодні теж народжується на хості (кроки 3–4 §1) — поза RAM хоста її виведе лише on-chip keygen SE05x, а це ціль, не код (`SecureElementProvisioner`: TODO) |
| **Перехід Гілка A → Гілка B** | Можливо (re-flash MCU + добавити ATECC до PCBA = новий PCB revision) | — |
| **Перехід Гілка B → Гілка A** | ❌ Неможливо (ATECC config zone locked permanently) | — |

**Рекомендований мінімум для TRL 6 (pilot batch ≤ 100 unit):**
- Гілка A + envelope encryption (Bitwarden Secrets Automation, short-lived token TTL 15 хв)
- 2-person rule (operator + supervisor)
- AuditLog chain-hash + MaintenanceRecord :installation
- RDP Level 1 відразу після Flash write

**Перехід на Гілка B** активується перед першим mass production batch (рішення прив'язане до BOM freeze — cross-ref [`02_06 §8.1`](02_06_Unit_Economics_and_BOM), SEC.6, ARCH.42).

### 5.A. Custody-тір ranking — `PROVISIONING_MASTER_KEY` storage (честь про поточний тір)

> Дім ранжування custody самого `master_key` (НЕ деривованих `HardwareKey` — ті AR-encrypted у Vault, §2). Референситься [`06_04 §5.8`](06_04_Secrets_Checklist) (rotation) + §2 (storage). **Чесність (SEC.22):** master сьогодні на НАЙНИЖЧОМУ тірі — deploy-ENV plaintext; висхідні тіри = план, не поточність.

| Тір | Custody | Стан сьогодні | master у пам'яті |
|-----|---------|---------------|-------------------|
| **0 · Direct-ENV** (найнижчий) | deploy-ENV `PROVISIONING_MASTER_KEY`; `EnvAdapter` (`master_key_source.rb`) + boot-guard SEC.9 | ✅ **єдиний живий шлях** | plaintext у `/proc/<pid>/environ`, provider-visible (SEC.22) |
| **1 · Vault / secret-manager** | Bitwarden/1Password/HashiCorp; `BitwardenAdapter` | 🟡 skeleton (`NotImplementedError`) | at-rest enc, але master у RAM інструменту при fetch |
| **2 · KMS-MAC** | GCP-KMS Expand-only HKDF (backend+firmware), keyring `silken-mac-ew1` | 🔗 pre-mainnet SEC.22 → [`06_04 §5.7`](06_04_Secrets_Checklist) | master **НІКОЛИ** не в процесі (деривація в KMS) |
| **3 · HSM injection** (найвищий, >1000 units) | AWS CloudHSM / Thales Luna; master не покидає HSM | 🌿 mass-production | master у RAM інструменту не з'являється |

**Master-тір ↑ = менша fleet-forge blast-radius** (master = HKDF-корінь усіх anti-fraud інваріантів флоту до re-flash — [`06_04 §5.8`](06_04_Secrets_Checklist)). Деривовані device-ключі AR-encrypted у Vault незалежно від master-тіру (§2 — це ІНШИЙ ключ).

---

> **Cross-ref:** §1 (pipeline design Гілка A + B), §2 (HKDF derivation), 03_05 §3.6 (RDP Level 2 — необоротна процедура), 03_05 §3.7 (ATECC608B slot mapping), [`00_07` — SEC.3](00_07_Action_Plan_Tracker), [`00_07` — SEC.1](00_07_Action_Plan_Tracker) (Gnosis Safe multisig для admin role).
