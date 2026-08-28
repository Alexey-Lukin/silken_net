# 03_06: Factory Flashing та Provisioning Ключів (HKDF · K_seed · OTA-Auth)

---

## 🎯 Мета

Зафіксувати конвеєр **Factory Flashing** (масове виробництво) та повний протокол **provisioning ключів** вузлів Soldier/Queen: дві гілки фабрики (Protected Flash STM32 / Secure Element), HKDF-деривація per-device AES-ключів, Lorenz K_seed (SEC.11), OTA image authentication (FW.23 HMAC dual-gate) та operations-security threat model заводського каналу (SEC.3). Виокремлено з [`03_05 §3.4`](03_05_Hardware_Symmetric_Crypto_and_Security) (там лишаються крипто-режими/пакети/IV/SE050/ротація; тут — provisioning-підсистема).

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — backend provisioning + HKDF + K_seed + OTA-HMAC реалізовано (host-тести зелені); фабрична Rake-CLI dry-run ✅. Відкрите: real `STM32_Programmer_CLI` + live SE05x/`sss` I²C на bench (SEC.3; SE = **SE050**, `cryptoauthlib` — ATECC-ери, superseded SEC.6), RDP Level 2 (SEC.2), K_ota bench (FW.23) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Крипто-режими (AES CCM/CBC/ECB), пакети, IV, SE050 §3.7, ротація §3.8 — дім, з якого виокремлено |
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | RTC/Flash-KV мапа; K_ota Protected Flash сторінка |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | K_seed → (x₀,y₀,z₀) cold-start (§2.1) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `FactoryFlashing::*`, `HardwareKeyService`, `OtaPackagerService`, `OtaHmacKeyService` |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Відкриті: SEC.2 RDP-2, SEC.3 factory bench, FW.23 K_ota bench |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Стратегія Масового Виробництва (Factory Flashing Pipeline)](#1-стратегія-масового-виробництва-factory-flashing-pipeline)
- [2. HKDF Key Derivation Protocol Design](#2-hkdf-key-derivation-protocol-design-)
- [3. Lorenz K_seed Derivation (SEC.11)](#3-lorenz-k_seed-derivation-sec11-)
- [4. OTA Authentication Protocol Design (FW.23) ✅ Реалізовано (2026-05-02)](#4-ota-authentication-protocol-design-fw23--реалізовано-2026-05-02)
- [5. Factory Flashing Operations Security 🤖 (SEC.3, 2026-05-17)](#5-factory-flashing-operations-security--sec3-2026-05-17)
<!-- TOC:AUTO:END -->

---

## 1. Стратегія Масового Виробництва (Factory Flashing Pipeline)

При переході від прототипу до партії 10 000+ вузлів конвеєр на заводі виглядає так. **Дві гілки:** (A) ключі у protected Flash sector STM32 (TRL 6/7, baseline), (B) = A + Secure Element SE05x, baseline SE051C2 (mass production > 10k / high-value urban — оцінка SE у 03_05 §3.7). **Post-SEC.14 (provisioning-only, 2026-07-03):** LoRa-ключ KEYL живе у Protected Flash в **обох** гілках; SE у Гілці B додає лише ідентичність/provisioning (Ed25519 «голос дерева», cert, anti-clone serial) — «Гілка A + identity-chip», graceful degradation (мертвий SE ≠ мертва телеметрія).

### Гілка A — Protected Flash Sector (TRL 6/7, baseline)

```
[Завод]
  0. Ідентичність (one-pass, FW.54): SWD-read 96-біт UID ДО прошивки
     STM32_Programmer_CLI -r32 0x1FFF7590 12  → три %08X-слова
     host деривує DID = murmur3-fmix32(UID) (03_01 §7; SilkenNet::DidDerivation)
     TreeResolver: Tree create / re-flash (паспорт silicon_uid_hex збігся) /
     bind (legacy без паспорта) / DID-колізія → QUARANTINE юніта

  1. Прошивка: масив aes_key[4] = {0,0,0,0} (порожній placeholder)
     Robot Programmer → Flash firmware → Board

  2. Provisioning: rake-тріо §5 (2-Person Rule) — ключі від ПРАВИЛЬНОГО DID
     factory:flash[UID,…] → approve → execute:
     Backend деривує unique_key (HKDF від master_key + DID; жоден ключ не
     летить мережею) → транскрипт: connect → -r32 UID-read (wrong-board
     guard: чужа плата = жодного -w32) → -w32 у Flash (0x0803E000)

  3. Lock: апаратне блокування
     STM32CubeProgrammer (CLI) → Set RDP Level 1 (або Level 2)
     → необоротне блокування SWD зчитування
     → активація WRPROT на key sector + seed sector + role sector

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
           ota_hmac = per-cluster HKDF (FW.23, "silken-ota-hmac-v1")
       - Зберігає (DID → HardwareKey, silicon_uid_hex → Tree; tamper-detect:
         підміна чіпа → wrong-board guard / паспорт-mismatch)
       - ECC keypair + X.509 device cert (peaq DID signing, ARCH.27 evolution)
     Жоден ключ не летить мережею — усе входить у ATCA-транскрипт (SecureElementProvisioner)

  4. STM32 → SE: write keys per slot mapping (legacy ATECC-скетч; cross-ref 03_05 §3.7):
     # SLOT 0 (AES LoRa) — ✂️ НЕ пишеться post-SEC.14 (provisioning-only):
     #   KEYL → Protected Flash як у Гілці A; slot reserved (urban-варіант)
     atcab_write_zone(SLOT 1, ecc_priv, 32B)    # Ed25519 private (голос дерева; SE05x → on-chip keygen)
     atcab_write_zone(SLOT 2, cert_der, 64B)    # X.509 device cert
     atcab_write_zone(SLOT 3, ota_hmac, 32B)    # FW.23 OTA image HMAC verification
     # Slot 4..15 — reserved (legacy ATECC-нумерація; SE05x = object-model, не slots;
     #   FW.17-ратчет ротує session на MCU — 03_05 §3.8, НЕ в SE)

  5. Lock (irreversible на ASIC рівні):
     atcab_lock_config_zone()    # Config (slot policies) → permanent
     atcab_lock_data_zone()      # All slot writes → forbidden forever
     # ⚠️ Після цього кроку ключі НЕ можуть бути ні прочитані, ні переписані —
     # навіть з фізичним доступом, navigate ASIC шар.

  6. Lock STM32:
     STM32CubeProgrammer → Set RDP Level 1 (або Level 2 після SEC.2 верифікації OTA)
     → SWD заблоковано → firmware не змінити

  7. Пакування (як у Гілці A):
     Лак → Box → Field (shipping-mode ✂️ не потрібен — 03_05 §3.5)
```

**Подвійний lock (defense in depth, тільки Гілка B):**

| Шар захисту | Що блокує | Атака, від якої захищає |
|-------------|-----------|--------------------------|
| **ATECC608B data zone lock** | Read/write ключів | DPA/EM side-channel, fault injection (chip self-erase при detection), chip swap |
| **STM32 RDP Level 1/2** | SWD flash dump | Прямий read firmware через debug port |
| **Backend (atecc_serial pin)** | ATECC swap на іншому board | Адверсар викрадає ATECC з одного board і ставить на інший — backend reject при провіженінгу через mismatch (device_uid, atecc_serial) пари |

**Latency impact (Гілка B vs A):** ATECC608B AES-ECB ~1.5 мс/блок vs MCU HAL_CRYP ~10 µs. Для одного 16/30-байтного LoRa пакета — нехтовно. Для CBC batch 50 × 16 байт = 800 байт — додаткові ~75 мс на flush (CoAP flush триває кілька секунд у будь-якому разі).

**Power impact (Гілка B):** ATECC active ~69 мкДж/пакет → ≈0.2% active-циклу Soldier (точні числа — 03_05 §3.7, дзеркало SSOT там). ⚠️ Sleep 150 нА always-on **з'їдає весь запас Сценарію C** → SE обов'язково за load-switch гейтом (розрахунок і вимога — 03_05 §3.7). Енергія active **мала, але не вирішальна**; сама вісь «SE AES щопакета vs лише provisioning» — **ВИРІШЕНО (SEC.14, 2026-07-03): provisioning-only**, streaming AES = вбудований radio-AES STM32; розбір осей і наслідки — 03_05 §3.7 (Статус).

**Cost impact (Гілка B):** +$0.60/unit (ATECC608B 10k MOQ) або +$0.85/unit (STSAFE-A110). Cross-ref [`00_04`](00_04_Nature_as_a_Service_Contracts) unit economics.

**Вибір гілки — критерії прийняття рішення:**

| Сценарій | Рекомендована гілка | Обґрунтування |
|----------|---------------------|---------------|
| Pilot batch (< 1 000 unit), TRL 6 | **A** (Protected Flash) | Економія часу та BOM; RDP Level 1 + WRPROT достатньо для pilot |
| Mass production 1k–10k unit, TRL 7 | **A**, з планом міграції на B | RDP Level 2 + WRPROT забезпечує proportional захист |
| Mass production > 10k unit | **B** (Secure Element) | Side-channel attractive target; tamper-resistance ROI > $0.60/unit |
| High-value deployments (urban, commercial, regulated) | **B** | Compliance: NIST FIPS 140-2 Level 3, ISO 27001, GDPR Article 32 |

**Переваги обох гілок:**
- Компрометація одного Soldier не розкриває ключі сусідів (per-device HKDF)
- Фізичне вилучення ключа з чіпа неможливе після RDP Lock (Гілка A) або data-zone lock (Гілка B)
- Деривовані device-ключі ніколи не в репозиторії — лише `HardwareKey` (AR-encrypted у Vault); сам `master_key` custody = deploy-ENV Тір-0 (§5.A), **НЕ** Vault
- Якщо Backend-side master key компрометовано → перевипуск всіх ключів через field re-flash (Гілка A) або re-provisioning + ATECC re-lock через RMA (Гілка B, болючіше)

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

> **Domain separation:** Два різні info-strings гарантують, що LoRa та CoAP ключі НЕ корелюють криптографічно — компрометація 16-байтного LoRa-ключа конкретного дерева **не дає жодної інформації** про 32-байтний CoAP-ключ Queen, який обслуговує це дерево. Те саме для `OtaHmacKeyService` (info `"silken-ota-hmac-v1"`) та `SilkenNet::SeedDerivation` (info `"silken-lorenz-seed|<DID>"`).
>
> 🔴 **[SEC.34] Ця обіцянка ТЕПЕР МАЄ НОСІЯ — `spec/security/hkdf_domain_separation_spec.rb`, і доти не мала жодного.** Причина, чому саме тут потрібен гейт, а не домовленість: HKDF-колізія **не кидає** — `OpenSSL::KDF.hkdf` віддає бездоганні байти, provisioning проходить, і **прошивка погоджується**, бо деривує те саме хибне значення. Тобто зелено на КОЖНОМУ ярусі, і єдине, що відділяє два ключі, — унікальність пари `(salt, info)`. Salt при цьому гейтувати не можна (він рантаймовий, і `"cluster:<id>"` законно спільний для KEYB ⊥ K_ota), тож уся вага лежить на info — звідси пін на попарну відмінність усіх шести info-рядків + ліхтар популяції. ⊕ Друга вісь того ж піна: голе імʼя `HKDF_INFO` жило у ДВОХ класах із різними значеннями (`HardwareKeyService` як мертвий compat-аліас ⊥ `OtaHmacKeyService` живим), тож `info: HKDF_INFO` у новій деривації означало б різне залежно від файлу; аліас знято, гейт тримає єдиність власника. ⛔ **Конвенцію «де живе ідентичність» НЕ вирівнювати** (`HardwareKeyService` кладе її в `salt`, `SeedDerivation` — в `info`): `firmware/soldier/main.c` дзеркалить обидві форми побайтово, тож вирівнювання = пере-ключення всього флоту.

**Властивості HKDF:**
- Якщо зловмисник знає `unique_device_key[i]`, він не може відновити `master_key` або `unique_device_key[j]` — однонаправлена функція
- Два пристрої з однаковим `device_uid` отримають однаковий ключ (детерміновано) — важливо для Queen, яка повинна знати ключ кожного Soldier у своєму кластері
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
     STM32_Programmer_CLI -r32 0x1FFF7590 12      # 96-біт UID, три %08X-слова
     DID = SilkenNet::DidDerivation.wire_did_from_uid_hex(UID)
     # murmur3-fmix32 (03_01 §7) — байт-у-байт той самий DID плата порахує
     # собі на boot (firmware/soldier/did_derive.h, golden-вектори обабіч)

  b) factory:flash[UID,…] → FactoryFlashing::TreeResolver:
     Tree create (CLUSTER_ID + TREE_FAMILY_ID env; координати — полю) /
     re-flash (trees.silicon_uid_hex збігся) / bind (legacy без паспорта) /
     DID-колізія (інший чип, той самий DID) → QUARANTINE юніта (03_01 §7)

  c) Backend деривує ключі від ПРАВИЛЬНОГО DID (Zero-Trust — нічого мережею):
     lora_key  = HKDF_SHA256(master_key, DID, "silken-aes-128-lora-key")  # Tree, 16B — session KEYL
     k_seed    = SeedDerivation (§3, info "silken-lorenz-seed|<DID>")     # Tree, 32B
     k_ota     = per-cluster HKDF (§4, FW.23)                             # Tree, 32B
     bcast_key = HardwareKeyService.derive_broadcast_key(cluster_id)      # ОБИДВА, 16B — KEYB
                 # = HKDF(master, "cluster:<id>", "silken-aes-128-broadcast-key")
                 # Tree → KEYB-слот (стор. 125, +40); Gateway → її KEYL-слот
                 # (єдиний LoRa-ключ Королеви — FW.2 (в), 03_05 §3.1)
     coap_key  = HKDF_SHA256(master_key, uid, "silken-aes-256-device-key") # Gateway, 32B
     HardwareKey.create!(device_uid: DID, aes_key_hex: …)

  d) factory:execute (після 2-Person approve; live) — транскрипт:
     connect → -r32 UID-read → wrong-board guard (Session звіряє паспорт
     плати з trees.silicon_uid_hex; чужа плата → WrongBoardError, жодного
     -w32) → -w32 KEYL/LSED/KOTA per-word → RDP → disconnect
     # 0x0803E000 = FLASH_KEY_ADDR; Гілка B: ключі через ATCA (§1)

  e) Lock:
     STM32_Programmer_CLI -ob RDP=1    # Pilot batch
     # (Level 2 після верифікації OTA — SEC.2)

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
# app/services/hardware_key_service.rb — два derivation methods.
# Master key: явний `master_key:` параметр — фабрична Session несе його від
# MasterKeySource (SEC.3 DI, vault-ключ реально живить HKDF); nil → ENV
# PROVISIONING_MASTER_KEY (runtime-fallback: register API, IoTeX seed).

LORA_KEY_INFO = "silken-aes-128-lora-key".freeze   # ARCH.42 — Tree LoRa channel (16 bytes)
COAP_KEY_INFO = "silken-aes-256-device-key".freeze # Gateway CoAP-to-Rails channel (32 bytes)

# LoRa AES-128 ключ (Tree або Gateway LoRa-сесія)
def self.derive_lora_key(device_uid, master_key: nil)
  master_key ||= ENV["PROVISIONING_MASTER_KEY"]  # SecurityError якщо blank (SEC.11)
  prk  = OpenSSL::HMAC.digest("SHA256", master_key, device_uid)
  okm  = OpenSSL::HMAC.digest("SHA256", prk, LORA_KEY_INFO + "\x01")
  okm[0, 16]  # 128 bits — AES-128
end

# CoAP AES-256 ключ (тільки Gateway — для batch flush до Rails)
def self.derive_device_key(device_uid, master_key: nil)
  master_key ||= ENV["PROVISIONING_MASTER_KEY"]
  prk  = OpenSSL::HMAC.digest("SHA256", master_key, device_uid)
  okm  = OpenSSL::HMAC.digest("SHA256", prk, COAP_KEY_INFO + "\x01")
  okm[0, 32]  # 256 bits — AES-256
end

# app/controllers/api/v1/provisioning_controller.rb (Zero-Trust — НЕ повертає keys)
def register
  device_uid = params.require(:device_uid)
  device_type = params[:type] == "gateway" ? "gateway" : "tree"
  hkdf_key   = device_type == "gateway" \
                 ? HardwareKeyService.derive_device_key(device_uid)  # 32 bytes для Gateway
                 : HardwareKeyService.derive_lora_key(device_uid)    # 16 bytes для Tree
  HardwareKey.create!(device_uid:, aes_key_hex: hkdf_key.unpack1("H*"))
  render json: { did: tree.did }  # NO key у response
end
```

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

> **Чому fallback на Soldier:** більшість вузлів — звичайні датчики (Soldier=TX-only). Provisioner (TX+CAD) — еліта з надлишком енергії, явно прошивається factory pipeline'ом. Корупція/erase Flash (`0xFFFFFFFF` unprovisioned, `0x00000000` erased, бітові помилки) → безпечний дефолт без CAD-режиму, який спалив би слабкого Солдата енерго-голодним радіо.

> **Споживачі прапорця:** ARCH.26 L3 (CAD relay), повний FW.20-S2 (mesh time-sync relay) — без додаткової логіки в `HardwareKeyService`/backend; це чистий firmware-flag. Backend не повинен довіряти claimed role з пакету (TX-сторона може брехати) — `g_node_role` локально визначає поведінку, серверна сторона вирішує доверу через ECC підпис при provisioning.

> **5 host-тестів** у `test_soldier_logic.c`: SOLD / PROV / unprovisioned 0xFFFFFFFF / zero / corrupted magic → all fallback paths.

### Захист Flash Key Sector (WRPROT)

```
STM32CubeProgrammer → Option Bytes → Write Protection:
  Сторінки 124-125 (0x0803E000 + 0x0803E800; WLE5 = 2KB-сторінки,
  дзеркало firmware-арифметики FLASH_KEY_ADDR/FLASH_OTA_KEY_ADDR)
  → Write-Protected ON

Результат: навіть якщо SWD відкритий (RDP Level 0 у R&D) —
  запис у ключові сторінки неможливий без зняття WRPROT
  (зняття стирає відповідну сторінку Flash!)
```

> **Семантика двох сторінок (FW.2 (в)):** 124 = **per-device identity** (KEYL session · LSED · ROLE; Queen: KEYC · EDSK), 125 = **cluster membership** (KOTA · KEYB @+40, dw-align) — переїзд дерева між кластерами стирає/пише лише 125-ту, per-device ключі недоторкані.

### Безпекові параметри (post-ARCH.42)

| Параметр | LoRa-канал (Tree + Queen) | CoAP-канал (Queen only) | Обґрунтування |
|----------|---------------------------|--------------------------|---------------|
| KDF алгоритм | HKDF-SHA256 (RFC 5869) | HKDF-SHA256 | Стандарт NIST SP 800-56C; SHA256 — software (backend OpenSSL / Soldier pure-C `silken_sha256.h`) |
| Master key size | 256 bits | 256 bits | Master input — однаковий 256-bit secret для обох KDF-outputs |
| Output key size | **128 bits (16 bytes)** — ARCH.42 | 256 bits (32 bytes) | LoRa: AES-128 (свідомий вибір, **не** SE-constraint — SE050 вміє 256, 03_05 §3.7); CoAP: AES-256 (Queen Flash, no SE constraint) |
| Info string | `"silken-aes-128-lora-key"` (session) · `"silken-aes-128-broadcast-key"` (KEYB cluster, salt=`"cluster:<id>"` — FW.2 (в)) | `"silken-aes-256-device-key"` | Domain separation — усі KDF outputs ortho (вкл. `"silken-ota-hmac-v1"` §4) |
| Master key storage | **Deploy-ENV `PROVISIONING_MASTER_KEY`** (boot-guard SEC.9; §5.A ранжує Direct-ENV найнижче — чесний поточний тір) → KMS-MAC pre-mainnet (SEC.22, [`06_04 §5.7`](06_04_Secrets_Checklist)); **деривовані** ключі — `HardwareKey` AR-encrypted | Same | Never in-repo; on-compromise runbook → [`06_04 §5.8`](06_04_Secrets_Checklist) |
| Device key storage | Protected Flash (LoRa magic `"KEYL"`) — **обидві гілки** (SEC.14 provisioning-only; SE Slot 0 reserved для urban-варіанту — 03_05 §3.7) | Protected Flash (CoAP magic `"KEYC"`) — Queen MCU only | Фізичний захист; AES-128 на LoRa — свідомий вибір, не SE-constraint (ADR 03_05 §3.7); CoAP-key лишається у MCU Flash (канал не через SE) |
| Backup/rotate | Session: dual-key grace period (HardwareKey#previous_aes_key_hex — закривається неявним uplink-ACK). **KEYB: re-provision only** — grace незастосовний (broadcast-ключ не має власного uplink'а для ACK; клас K_ota) | Same (grace) | Zero-downtime rotation (session); cluster-ключі ротуються фізичним re-flash 125-ї сторінки |
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
[payload_byte, x_f, y_f, z_f] = mruby BioContract.calculate_state(
                                  x_prev, y_prev, z_prev,
                                  temp, acoustic, delta_t_s, vcap_mv)
write RTC DR16-DR18 = (x_f, y_f, z_f); DR19 = "LZST"

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

server_z, x_f, y_f, z_f = Attractor.calculate_z_from_state(
                            x₀, y₀, z₀, temp, acoustic, delta_t_s, vcap_mv)
log.update!(lorenz_state_x: x_f, lorenz_state_y: y_f, lorenz_state_z: z_f,
            cold_start_flag: cold_start_flag)
```

### Криптографічні гарантії в одному рядку

> `K_seed` ніколи не залишає пристрій і сервер. `(x₀, y₀, z₀)` — функція від (`K_seed`, `epoch_day`). DID у формулі **не існує** як seed — він використовується лише як `info`-string у HKDF (namespace separator), що криптографічно безпечно і не вносить уразливості.

### Threat model post-SEC.11

| Загроза | Захист |
|---------|--------|
| Sniff LoRa-пакет → відтворити Z | ❌ (без `K_seed` Z непередбачуваний) |
| Compromise одного `K_seed` (фізичний доступ до пристрою) | ⚠️ Один пристрій уразливий ≤ 24 год; інші — ні |
| Compromise `PROVISIONING_MASTER_KEY` | 🚨 Каскадне — потрібна окрема rotation strategy (SEC.9) |
| Replay вчорашнього валідного пакета | ❌ (`epoch_day` змінився, Z більше не валідний) |
| Підроблений `cold_start_flag = true` від device | ❌ Структурно неможливо: прапорця НЕМА на дроті (ані `PAYLOAD_FORMAT`, ані `CCM_SENSOR_PAYLOAD_FORMAT`) — сервер деривує його сам із наявності попереднього хвоста траєкторії (`TelemetryUnpackerService#compute_server_z`) |
| ARM ↔ x86 IEEE-754 drift > 0.001 | Емпірично < 1e-12; tolerance band 9 порядків запасу при flip на numeric |

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

## 4. OTA Authentication Protocol Design (FW.23) ✅ Реалізовано (2026-05-02)

**Статус реалізації:**

| Шар | Файл | Що зроблено |
|-----|------|-------------|
| Backend (HKDF) | `app/services/ota_hmac_key_service.rb` | `OtaHmacKeyService.fetch_for(cluster_id, master_key: nil)` — HKDF-SHA256, info `"silken-ota-hmac-v1"`; ikm = `master_key:` параметр (фабрична Session, SEC.3 DI) або ENV-fallback, raise `SecurityError` без жодного (SEC.11 hard cutover) |
| Backend (signing) | `app/services/ota_packager_service.rb` | `compute_hmac_tag(bytecode, version_id, lora_total_chunks, cluster_id:)` + `build_hmac_trailer_chunks(tag, lora_total_chunks, version_id)` (3× `[0x9B][seg_idx:2 BE][total:2 BE][hmac:11]` + seg 4 `[0x9B][0x0004][total:2 BE][version_id:4 BE][PAD:7]`) + `prepare(..., cluster_id:)` opt-in з `manifest[:hmac_signed/lora_total_chunks/total_packages/hmac_cluster_id]` |
| Firmware Queen | `firmware/queen/main.c` | Stateless relay: `Handle_CoAP_Command` зберігає 4 trailer-блоки (3 печатки + версія) у `pending_ota_hmac_chunks[4][16]`, ready-bitmask = `0x0F`; reflex broadcast loop додає Phase 1 (trailer) після Phase 0 (bytecode); 60 ms pacing |
| Firmware Soldier | `firmware/soldier/main.c` | `Load_Ota_Hmac_Key` (K_ota з Protected Flash `0x0803E800`, magic "KOTA"; fail-safe `ota_hmac_key_valid=0`) + `Parse_HMAC_Trailer_Chunk` (seg 1..3 → `received_hmac_tag`, seg 4 → `received_ota_version`) + `OTA_Try_Finalize` (**реальний** `Silken_Hmac_Sha256_Concat(K_ota, body‖version_be‖total_be)` → `OTA_Verify_Dual_Gate`: Gate 1 magic "RITE" + Gate 2 constant-time HMAC) — фіналізація з обох гілок (тіло 0x99 / печатка 0x9B), бо печатка приходить ПІСЛЯ тіла; APPLY лише при всіх 4 трейлер-чанках; fail-safe magic-wipe при REJECT |
| Backend specs | `spec/services/ota_hmac_key_service_spec.rb`, `spec/services/ota_packager_service_spec.rb`, `spec/integration/ota_firmware_flow_spec.rb` | determinism / domain separation / anti-replay / anti-truncation / per-cluster isolation / manifest metadata / package ordering / version-on-wire (seg 4 = firmware.id BE) / blank input / SEC.11 |
| Firmware host-tests | `firmware/test/test_soldier_logic.c`, `test_queen_logic.c` | trailer assemble (in-order/out-of-order/version chunk/all-4=0x0F) / reject seg_idx>4 / **real HMAC compute** (`Silken_Hmac_Sha256_Concat` ≡ one-shot ≡ OpenSSL) / `OTA_Try_Finalize` APPLY·WAIT·REJECT(tampered/version-mismatch/no-key) / dual-gate magic+hmac / constant-time first/last byte / Queen relay 4 segments / wrong marker reject / overwrite same segment |

**Статус: реальний compute — ✅ зашито (2026-06-11).** Soldier dual-gate **більше не інертний**: `OTA_Try_Finalize` обчислює `Silken_Hmac_Sha256_Concat(K_ota, body ‖ version_id_be ‖ total_be)` (pure-C `silken_sha256.h`, той самий шлях, яким FW.30 закрив seed-HMAC; byte-parity vs OpenSSL транзитивно через `_Concat ≡ one-shot`; **mbedTLS не потрібен**) і пускає у `OTA_Verify_Dual_Gate` — підмінений bytecode з валідним CRC32 тепер **відсікається** на Gate 2. Дві опори, яких бракувало, додано: (1) `Load_Ota_Hmac_Key` — K_ota з Protected Flash `0x0803E800` (magic "KOTA", окрема сторінка 125 за `KEYL`-сторінкою; первісний `0x0803D000` колідував із Flash-KV регіоном — переїзд 2026-06-11, [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA); `ota_hmac_key_valid=0` ⇒ жоден OTA не застосовується — fail-safe); (2) `version_id` на дроті — **4-й `[0x9B]` trailer-чанк** (seg_idx=4, `version_id:4 BE`), бо у 16-байтну печатку-сегмент він не влазив. Bonus-fix: фіналізація тепер спрацьовує з обох RX-гілок (тіло 0x99 / печатка 0x9B) — раніше перевірка стріляла по завершенню ТІЛА і скидала збірку, тож печатка, що Королева шле ПІСЛЯ тіла, гинула й OTA ніколи не застосовувався. ✅ (2026-06-11) **factory-тракт K_ota зашито**: Гілка A (`CommandBuilder`) емітує KOTA-блок `0x0803E800` (дзеркало `Load_Ota_Hmac_Key`, golden-спека; `Session` тягне `OtaHmacKeyService.fetch_for(cluster_id)`) — знахідка: до цього K_ota жив лише у superseded ATECC-гілці B, тобто Гілка A випускала дерева з вічно fail-closed OTA. 🟡 **Лишається (bench):** фізичний `factory:execute` (SWD) + e2e dual-gate на STM32 (валідний APPLY + tampered REJECT) — RUNBOOK §2.5.


> **Cross-ref:** [`00_07` — FW.23](00_07_Action_Plan_Tracker) — дизайн завершено ✅
> **Залежність:** FW.1 (per-device HKDF) — ✅ реалізовано (03_05 §3.1); спільна master-secret інфраструктура наявна.

**Мета:** усунути BLOCKER 03_05 §6 «Queen → Soldier (OTA LoRa) — MAC/MIC відсутній». Зловмисник у радіусі Queen може:
1. **Підмінити OTA chunks** → впровадити шкідливий mruby bytecode на всі Солдати кластера
2. **Bit-flip атака на CRC16** → CRC16-CCITT не криптографічний, валідний CRC можна підрахувати для будь-якого payload
3. **Replay старого OTA** → відкочити Солдат на застарілу/вразливу прошивку

Симетричне шифрування (AES-128-ECB) гарантує лише **конфіденційність**, не **автентичність походження**. Дзеркало проблеми FW.2 для каналу телеметрії, але з більшою серйозністю — OTA bytecode виконується на всіх Солдатах у радіусі.

### Криптографічна основа: HMAC-SHA256 поверх повного image

```
HMAC-SHA256(K_ota, full_bytecode || version_id || total_chunks) → 32 bytes
```

**Чому HMAC-SHA256, а не Ed25519/ECDSA:**
- HMAC-SHA256 рахується **програмно** (pure-C `silken_sha256.h`, FW.30 — у STM32WLE5JC є апаратний AES, але **немає** HASH/SHA-блоку, тож SHA256 завжди software): кілька SHA-проходів над image — на порядок дешевше за програмний Ed25519 verify (~80 мс)
- 32-байтний tag поміщається у 3 LoRa-чанки (vs 64 байти Ed25519 sig → 6 чанків)
- Симетричне рішення прийнятне ТОМУ ЩО `K_ota` per-кластер, не глобальний (компрометація Queen ≠ компрометація всієї мережі)
- При billion-tree масштабі — міграційний шлях на асиметричний image-підпис (post-TRL 7; SE05x-ера = Ed25519, присуд → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker)) — скетч механіки нижче

### Wire Format — `[0x9B] HMAC-Trailer` Chunk

OTA-broadcast emit'ить **4** додаткові LoRa-чанки `[0x9B]` після останнього bytecode chunk: 3 несуть 32-байтну HMAC-печатку, 4-й — `version_id`. Існуючий формат `[0x99]` для bytecode chunks не змінюється — окремий маркер дає чисте розділення payload-і-tag шарів (audit trail у логах Queen, простіший parser у firmware).

```
LoRa Reflex Shot чанки (16 байт після AES-128-ECB encrypt):

Chunks 0..N-1:                                Marker
  [0x99][idx:2][total:2][bytecode:11]          ← Bytecode chunks

Chunk N (HMAC trailer #1):                    Marker
  [0x9B][0x00][0x01][total:2][hmac[0..10]]     ← Перші 11 байтів HMAC tag

Chunk N+1 (HMAC trailer #2):                  Marker
  [0x9B][0x00][0x02][total:2][hmac[11..21]]    ← Наступні 11 байтів

Chunk N+2 (HMAC trailer #3):                  Marker
  [0x9B][0x00][0x03][total:2][hmac[22..31]||PAD:1]  ← Останні 10 байт + 1 байт padding

Chunk N+3 (version envelope #4):              Marker
  [0x9B][0x00][0x04][total:2][version_id:4||PAD:7]  ← version_id (4 BE) + 7 PAD
```

**Layout детально:**
| Зсув | Розмір | Поле | Опис |
|------|--------|------|------|
| 0 | 1 | `0x9B` | HMAC-trailer marker (відрізняє від `0x99` bytecode) |
| 1–2 | 2 | `seg_idx` BE | Сегмент: 1–3 = HMAC-печатка, 4 = version envelope |
| 3–4 | 2 | `total_chunks` BE | Загальна кількість bytecode chunks (для cross-check) |
| 5–15 (seg 1–3) | 11 | `hmac_segment` | 11 байтів HMAC-SHA256 tag (seg 3 має 10 байт + 1 PAD `0x00`) |
| 5–8 (seg 4) | 4 | `version_id` BE | `firmware.id` — вхід HMAC, без нього Soldier не перерахує печатку |
| 9–15 (seg 4) | 7 | PAD | `0x00` |

**Чому 3 чанки печатки:** 32-байтний HMAC ÷ 11 байт payload = 2.91 → ceil(2.91) = 3 чанки. Альтернатива (truncated HMAC до 16 байт = 2 чанки) знижує security margin до 128-bit — недостатньо для NIST SP 800-107 у production. **Чому окремий 4-й чанк для `version_id`:** він — вхід HMAC, але у 16-байтну печатку-сегмент не влазить (1+2+2+11 зайнято); 0x99-заголовок теж повний. Окремий seg 4 під тим самим маркером — найдешевше (+1 LoRa-чанк ≈ 60 мс на ~745, той самий «<0.5%» бюджет), Queen релеїть його тим самим stateless-шляхом.

### Backend HMAC Generation — `OtaPackagerService` extension

**Файл:** `app/services/ota_packager_service.rb`

Розширення `prepare` методу: після генерації bytecode-chunks обчислюється HMAC поверх повного `payload`, потім додаються 4 trailer-chunks (3 печатки + version envelope). Контракт `prepare` повертає той же hash, але `packages` enumerator emit'ить додатково 4 пакети (`manifest[:total_packages] = total_chunks + 4`).

```
HMAC input (canonical):
  ┌─────────────────────────────────────────────────────────────┐
  │  full_bytecode_payload (raw, до chunking, до AES-encrypt)  │
  │  ‖ version_id (4 bytes BE — firmware.version_id)            │
  │  ‖ total_chunks (2 bytes BE)                                 │
  └─────────────────────────────────────────────────────────────┘

K_ota = OtaHmacKeyService.fetch_for(cluster_id)   # 32-byte HMAC key
hmac_tag = OpenSSL::HMAC.digest("SHA256", K_ota, hmac_input)  # 32 bytes
```

**Domain separation context** — `version_id` і `total_chunks` входять у HMAC input для запобігання:
- **Re-labeling** (старий image з валідним HMAC, пере-мічений НОВОЮ версією → HMAC над тілом ‖ версією ламається). ⚠️ **НЕ плутати з rollback:** валідно-`K_ota`-підписана СТАРА версія у свіжій сесії проходить цей HMAC — монотонність версій закрита ОКРЕМО на Soldier (`common/ota_antirollback.h`, Flash-KV high-water ключ 0x15; [`00_07` SEC.20](00_07_Action_Plan_Tracker))

**⚠️ Bump-інваріант відкликаного/проваленого OTA (SEC.20).** `Ota_Version_Commit` палить слот `0x15` **у момент APPLY** (Flash-запис contract'а), НЕ в момент доведеного успішного виконання. Наслідок жорсткий: версія N, що впала у vm-error-fallback (3 bytecode-збої → erase contract → embedded baseline), **спалена назавжди** — повторний push виправленого bytecode з тим самим `version_id=N` отримає мовчазний REJECT (`Ota_Version_Is_Fresh` вимагає строго `>`). Фікс = завжди **новий** `BioContractFirmware`-запис (auto-increment `id` > N задарма); re-deploy/re-activate старого запису = no-op на девайсі. Факт відкату видимий backend'у з кожного кадру: wire-звіт `[semantic:1|reverted:1|hiwater&0x3FFF]` у байтах 12..13 ([`03_01 §1.6`](03_01_Firmware_Lifecycle_and_DMA)) / CCM vpd-байт → `TelemetryLog#firmware_report_reverted?` → `EwsAlert firmware_reverted` («re-issue версією > спаленої»).
- **Truncation attack** (відкидання останніх chunks → змінений `total_chunks` ламає HMAC)

**Rails-half дзеркало (SEC.20, 2026-07-12).** Той самий інваріант enforce-иться ДО ефіру: `Ota::DeploymentDispatcherService` ([`04_02`](04_02_Business_Logic_and_Services)) тримає per-cluster high-water `clusters.ota_version_hiwater` і відсікає деплой із `firmware.id ≤ hiwater` (строго `>` — число те саме, що seg-4 трейлера і слот `0x15`). Слот палиться **при dispatch** — свідомо суворіше за Солдатів APPLY-time (Rails не має ack-каналу apply-стану: fw-report асинхронний і не гарантує покриття флоту), тож обірвана кампанія теж перевипускається новим записом; кластеру без eligible-шлюзів слот НЕ палиться. UI/API-контракт відмови → [`04_03 §5.7`](04_03_REST_API_v1_Reference).

### Key Management — `K_ota` per-cluster

Дзеркало дизайну HKDF з §2, але з окремим **info-string** для domain separation від AES LoRa key:

```
K_ota = HKDF-SHA256(
  ikm:    master_key,                  # фабрика: параметр від Session (SEC.3 DI); runtime: ENV PROVISIONING_MASTER_KEY
  salt:   "cluster:#{cluster_id}",
  info:   "silken-ota-hmac-v1",        # ← ВІДМІННЕ від "silken-aes-256-device-key"
  length: 32
)
```

**Чому per-cluster, а не per-device:**
- OTA broadcast — **broadcast** за визначенням, всі Солдати кластера отримують той самий image, тому потребують той самий ключ
- Per-device HMAC означав би N окремих verifications → економічно неможливо для broadcast
- Компрометація одного Солдата = компрометація `K_ota` ОДНОГО кластера, не всієї мережі
- Cluster — природна одиниця ізоляції (один Queen / одна організація)

**Storage:**
- Backend: новий model `OtaHmacKey` (analog `HardwareKey`, AR Encryption non-deterministic) ABO derived on-demand з `PROVISIONING_MASTER_KEY` через `OtaHmacKeyService.fetch_for(cluster_id)` (рекомендовано — нульовий state)
- Soldier firmware: `K_ota` записується у Protected Flash сторінку 125 (`0x0803E800`, одразу за per-device key-сторінкою; до 2026-06-11 — `0x0803D000`, що колідувало з Flash-KV регіоном [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)) під час Factory Flashing з тим самим magic-marker pattern як `Load_AES_Key()` — ✅ **Гілка A емітує KOTA-блок з 2026-06-11** (`CommandBuilder`, magic `0x4B4F5441` + 8 слів ключа; golden-спека дзеркалить `Load_Ota_Hmac_Key`). До того цей рядок був декларацією: K_ota емітувала лише superseded ATECC-гілка B → реальне дерево виходило з фабрики з вічно fail-closed OTA (зловлено при FW.23-ревізії)
- SE (post-TRL 7, SE050 — ATECC superseded): SE-резидентний `K_ota` = рішення SE050-MIGRATION ([`00_07`](00_07_Action_Plan_Tracker)); поки HMAC рахує MCU → ключ мусить жити у MCU Flash незалежно від SE

### Dual-Gate Verification (FW.23 чекбокс 5) — Soldier перед Flash write

Магічний marker `0x45544952` (`"RITE"` little-endian) — **необхідний, але недостатній**: він лише підтверджує цілісність формату, не походження. HMAC — **достатній**, але дорогий. Двоступенева перевірка економить cycles на ранній відсів пошкоджених/невалідних images:

Реалізація — pure-функція вердикту `OTA_Try_Finalize` (host-tested), яку кличуть **обидві** RX-гілки (0x99 тіло / 0x9B печатка), бо печатка приходить ПІСЛЯ тіла:

```
firmware/soldier/main.c — фактичний OTA Flash write path (FW.23):

OtaFinalizeVerdict OTA_Try_Finalize(buf, bytes_received, chunks_received,
                                    total_chunks, segments_received,
                                    K_ota, k_ota_valid, version_id,
                                    received_tag, &data_len)
{
  // Зібрано і тіло, і всі 4 трейлер-чанки? Інакше — WAIT (нічого не чіпаємо).
  if (chunks_received < total_chunks || total_chunks == 0)  return WAIT;
  if (segments_received != 0x0F /* 3 печатки + версія */)   return WAIT;

  data_len = bytes_received - 4;                 // тіло без CRC32-хвоста
  if (CRC32(buf, data_len) != tail_crc)          return REJECT;
  if (!k_ota_valid)                              return REJECT;  // fail-safe

  // Gate 2: HMAC над тілом ‖ version_be ‖ total_be. _Concat стрімить 6-байтний
  // хвіст окремо — тіло (~1 КБ) живе у buf, без +1 КБ стека.
  uint8_t suffix[6] = { version_id:4 BE, total_chunks:2 BE };
  Silken_Hmac_Sha256_Concat(K_ota, 32, buf, data_len, suffix, 6, expected);

  // OTA_Verify_Dual_Gate: Gate 1 magic "RITE" + Gate 2 constant-time compare.
  return OTA_Verify_Dual_Gate(buf, data_len, expected, received_tag) ? APPLY : REJECT;
}

// Викликач (обидві гілки):
//   APPLY  → Write_OTA_Contract_To_Flash(buf, data_len); NVIC_SystemReset();
//   REJECT → buf[0..3]=0 (жертовний magic-wipe); Reset_Ota_Assembly();
//   WAIT   → нічого (тіло зібране, печатка ще летить)
```

**Властивості dual-gate:**
- **Performance:** Gate 1 (magic, у `OTA_Verify_Dual_Gate`) у ~1 µs відкидає «биті» images; HMAC рахується лише коли зібрано і тіло, і всі 4 трейлер-чанки
- **Defense-in-depth:** HMAC обчислюється на тих самих байтах, що Gate 1 verify (`buf[0..data_len)`) — bit-flip між брамами «провезти» не можна
- **Fail-safe (no key):** `k_ota_valid==0` (K_ota не provisioned) ⇒ REJECT — без ключа походження не довести, краще не оновитись
- **Fail-safe (magic-wipe):** REJECT затирає `buf[0..3]` у RAM, щоб частково записаний OTA не воскрес при наступному boot із корумпованого RAM
- **Ordering-safe:** фіналізація спрацьовує з гілки, що завершилась ОСТАННЬОЮ (тіло чи печатка) — раніше перевірка по завершенню ТІЛА скидала збірку, і печатка (Королева шле її ПІСЛЯ тіла) гинула

### Queen Verification — опційний intermediate gate

Queen МОЖЕ верифікувати HMAC перед relay (якщо знає `K_ota` своїх Солдатів — типово так, бо Queen у тому ж кластері). Це economy-of-scale gate: 1 verify на Queen vs N verify на N Солдатах.

**Рекомендація:** Queen НЕ верифікує (Stateless-Relay підхід) — це залишає Queen-firmware простим і дозволяє Backend → Soldier end-to-end автентифікацію без довіри до проміжного Queen. Якщо Queen скомпрометовано — Soldier'и все одно відкинуть підмінений image на Gate 2.

### Безпекові параметри

| Параметр | Значення | Обґрунтування |
|----------|---------|---------------|
| MAC алгоритм | HMAC-SHA256 (RFC 2104) | Стандарт NIST FIPS 198-1; SHA256 — software (pure-C `silken_sha256.h`, FW.30 — чип без HASH-блоку) |
| Tag size | 256 біт (32 байти) | NIST SP 800-107 рекомендація для AES-256 рівня безпеки |
| `K_ota` size | 256 біт | Match HMAC output size |
| `K_ota` scope | Per-cluster (HKDF salt = `"cluster:#{id}"`) | Ізоляція кластерів, broadcast-сумісність |
| Domain separation | `info: "silken-ota-hmac-v1"` | Окремо від `"silken-aes-256-device-key"` (FW.1) |
| Magic marker | `0x45544952` ("RITE" LE) | Існуючий u-boot-style format-integrity marker (Gate 1) |
| HMAC input | `bytecode \|\| version_id \|\| total_chunks` | Anti-replay + anti-truncation |
| Comparison | `Hmac_Constant_Time_Compare` (constant-time) | Захист від timing attack |
| Wire overhead | +3 LoRa chunks (+~180 мс broadcast) | < 0.5% від загальної OTA-сесії 745 чанків |
| Implementation | Mandatory з дня 1 | Pre-production, no fallback path needed |

### Implementation Plan

Реалізація — три синхронні зміни (один coordinated commit, no backward-compat shim):

| Компонент | Зміна |
|-----------|-------|
| **Backend** (`OtaPackagerService`) | Завжди обчислювати HMAC та emit'ити 3 trailer-чанки `[0x9B]` після bytecode. Додати `OtaHmacKeyService.fetch_for(cluster_id)` (HKDF derivation) |
| **Firmware Soldier** | Парсити `[0x9B]` chunks у RAM (32-байтний `received_hmac_tag`), виконувати dual-gate verification перед `HAL_FLASH_Program(MRUBY_CONTRACT_FLASH_ADDR, ...)` |
| **Firmware Queen** | Stateless-relay, без verification (Backend → Soldier end-to-end) — повторюємо `[0x9B]` chunks у broadcast-циклі так само як `[0x99]` |

### Future Evolution: HMAC → ECDSA-P256 (post-TRL 7)

> ⚠️ **Скетч ATECC-ери (2026-05)** — SE = **SE050** (ATECC superseded, SEC.6 ✅ — [`03_05 §3.7`](03_05_Hardware_Symmetric_Crypto_and_Security) ADR): у SE05x-ері природна крива = **Ed25519** (on-chip keygen, «голос дерева»), не P-256. Механіка кроків (HSM-підпис → pubkey у Flash → sig-чанки → software verify → асиметрія довіри) переноситься 1:1; присуд «чи мігрувати» = [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker) ⚖️ OTA-auth еволюція.

Архітектурний шлях (не fallback) для billion-tree масштабу де компрометація одного Queen не повинна дозволяти підпис нових images:
1. Backend підписує image через ECDSA-P256 з master key (HSM)
2. Public key розповсюджується у Soldier flash (slot 2 ATECC608B або Protected Flash)
3. Wire format: `[0x9B][seg_idx:2][total:2][sig_segment]` → 6 чанків (64B sig)
4. ECDSA verify (~80 мс, software) дорожчий за software HMAC-SHA256, але прийнятний для рідкісної OTA-операції
5. Компрометація Soldier НЕ дозволяє підписувати OTA (асиметричні ключі — асимметрія довіри)

### Test Coverage — ✅ реалізовано
- **Backend (`spec/services/ota_packager_service_spec.rb`):** HMAC chunk generation (4 чанки = 3 печатки + версія), deterministic за фіксованого `K_ota`, replay/truncation negative cases, version_id-на-дроті (seg 4 = `firmware.id` BE)
- **Firmware (`firmware/test/test_soldier_logic.c`):** trailer assemble (version chunk, all-4=0x0F, seg_idx>4 reject), **реальний HMAC compute** (`Silken_Hmac_Sha256_Concat ≡ one-shot ≡ OpenSSL`), `OTA_Try_Finalize` APPLY·WAIT·REJECT (tampered/version-mismatch/no-key), constant-time compare
- **Integration (`spec/integration/ota_firmware_flow_spec.rb`):** backend → Queen relay (4 segments) → Soldier dual-gate accept/reject; tag reconstruction == `compute_hmac_tag`

> **Cross-ref:** FW.1 (HKDF master-key infrastructure), FW.2 (CCM MIC для телеметрії — паралельний MAC concept), 03_05 §3.7 (SE-роль ADR; ATECC slot-map = legacy-патерн), 03_05 §6 «Queen → Soldier (OTA LoRa)» row у криптографічній таблиці.

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
| Session AASM | `app/models/provisioning_session.rb` | ✅ `pending → supervisor_approved → active → completed \| failed`; 2-Person Rule = `supervisor_id != operator_id` (валідація) **+ `approve` guard `credentials_verified?` (true лише через `approve_with_credentials!` — Argon2id-пароль супервайзера); сирий `approve!` з console відмовляється → оператор, що лише *назвав* супервайзера, схвалити сам НЕ може** |
| Master key source | `app/services/factory_flashing/master_key_source.rb` | ✅ `EnvAdapter` (з `Security::WeakKeyDetector` SEC.9), `BitwardenAdapter` skeleton (raise `NotImplementedError` — TODO live `bw` API). Fetched ключ **наскрізно живить деривацію** (SEC.3 DI): Session тримає його у `@master_key` і передає параметром — non-ENV adapter підключається без правок сервісів |
| UID→DID resolver | `app/services/factory_flashing/tree_resolver.rb` | ✅ [FW.54] one-pass прив'язка: 24-hex UID → `DidDerivation.wire_did` → Tree create (`CLUSTER_ID`+`TREE_FAMILY_ID`) / re-flash (`trees.silicon_uid_hex` збігся) / bind (legacy) / **DID-колізія → `CollisionError` = quarantine юніта** (03_01 §7). Peaq свідомо НЕ enqueue'иться (offline-фабрика; peaq — за польовим register) |
| UID-readout parser | `app/services/factory_flashing/uid_readout.rb` | ✅ [FW.54] толерантний парсер `-r32 0x1FFF7590`-виводу (keyed на адресу) → три слова → 24-hex; точний формат live-CLI = bench-confirm (RUNBOOK 1.3) |
| Command emission | `app/services/factory_flashing/command_builder.rb` | ✅ `preflight_commands` (connect + `-r32 0x1FFF7590 12` UID-read, обидві гілки) + Гілка A — `STM32_Programmer_CLI -w32` per word для `KEYL`/`LSED`/`KEYC`/`EDSK` slots (EDSK = L1 QATT сім'я голосу Королеви, Gateway-only; генерується `Session`'ом на фабричному хості — НЕ HKDF, у БД лише pubkey), RDP level 1/2 config; Гілка B — skip key writes (keys через ATCA), only RDP lock + disconnect |
| Subprocess executor | `app/services/factory_flashing/executor.rb` | ✅ dry-run default (`[dry-run] cmd`); `dry_run: false` → `Open3.capture3` з `ProgrammerMissingError` коли CLI відсутній у PATH; `CommandFailedError` зупиняє на першому non-zero exit |
| ATECC provisioning | `app/services/factory_flashing/secure_element_provisioner.rb` | ✅ Гілка B skeleton — emit `atcab_init` + `atcab_read_serial_number` + slot writes (0/1/2/3) + `atcab_lock_config_zone` + `atcab_lock_data_zone`; raw key bytes scrubbed (`/* NB elided */`) |
| Audit trail | `app/services/factory_flashing/audit_trail.rb` | ✅ `AuditLog(action: "factory_flash")` chain-hashed + `MaintenanceRecord(action_type: :installation, system_generated: true)`; metadata містить `operator_id`/`supervisor_id`/`batch_id`/`flash_addr`/`rdp_level`/`se_serial_hex`/`firmware_version`/`command_count`/`dry_run` |
| Orchestrator | `app/services/factory_flashing/session.rb` | ✅ `ActiveRecord::Base.transaction` — failure rolls back HardwareKey + audit writes разом; `PreflightError` для non-approved sessions / missing device / unavailable master key. **[FW.54] Wrong-board guard**: live-режим ганяє `preflight_commands` і звіряє паспорт плати (`UidReadout`) з `trees.silicon_uid_hex` ДО деривації/першого `-w32` — чужа плата → `WrongBoardError`, навіть HardwareKey не матеріалізується (dry-run/безпаспортні: skip). Preflight-ключ НЕ відкидається: `@master_key` → `HardwareKeyService.provision` / `OtaHmacKeyService.fetch_for` / `SeedDerivation.derive_seed` параметром (SEC.3 DI; runtime-викликачі цих сервісів лишаються на ENV-fallback) |
| Operator CLI | `lib/tasks/factory.rake` | ✅ `factory:flash[device_uid,batch_id,gilka,operator_id,supervisor_id,firmware_version]` — **[FW.54] Tree: device_uid = 24-hex silicon UID** (→ `TreeResolver`; create-гілка = `CLUSTER_ID`+`TREE_FAMILY_ID` env; голий `SNET-` DID лише для дерева з уже прив'язаним паспортом); Gateway: uid як досі (`ATECC_SERIAL` env для Гілки B, `RDP_LEVEL` env override) → `factory:approve[session_id]` (**mandatory `SUPERVISOR_PASSWORD` env — супервайзер автентифікується власним паролем, SEC.3**) → `factory:execute[session_id]` (`EXECUTE=1` для real subprocess) |

> **[SEC.3] Authenticated 2-Person approval:** `factory:approve` вимагає `SUPERVISOR_PASSWORD` — `ProvisioningSession#approve_with_credentials!` верифікує його через `supervisor.authenticate` (Argon2id). Оператор може *назвати* супервайзера, але НЕ схвалить сесію без того, щоб супервайзер фізично ввів власний пароль (закрито колишній skippable `SUPERVISOR_ID` env-match). **Сирий `approve!` (Rails console) теж закрито кодом (2026-06-15):** перехід `approve` має guard `credentials_verified?`, що true лише всередині `approve_with_credentials!` після успішної Argon2id-автентифікації → console self-approve неможливий (`AASM::InvalidTransition`). **Залишок — суто операційний:** raw-SQL / object-manipulation (`update_column` / `instance_variable_set`) обходить будь-який in-process guard → межа §5 access-control (master-key лише `super_admin` + MFA), не код.

**Test coverage:** RSpec — `spec/models/provisioning_session_spec.rb` (AASM/validations + `approve_with_credentials!`), `spec/services/factory_flashing/*` (вкл. `tree_resolver_spec` — чотири долі кремнію; execute-path шим з UID-verify pass/wrong-board), `spec/integration/factory_flashing_e2e_spec.rb` (Rake trio: one-pass UID→Tree→ключі, firmware-equivalent HKDF, legacy-DID abort). Counts → suite.

**Зразок dry-run вивода** (Tree, Гілка A, RDP=1):
```
[dry-run] STM32_Programmer_CLI -c port=SWD reset=HWrst
[dry-run] STM32_Programmer_CLI -r32 0x1FFF7590 12               # [FW.54] UID-read (wrong-board guard)
[dry-run] STM32_Programmer_CLI -w32 0x0803E000 0x4B45594C       # KEYL magic
[dry-run] STM32_Programmer_CLI -w32 0x0803E004 0xAABBCCDD       # AES key word 0
[dry-run] STM32_Programmer_CLI -w32 0x0803E008 0xEEFF0011       # AES key word 1
[dry-run] STM32_Programmer_CLI -w32 0x0803E00C 0x22334455       # AES key word 2
[dry-run] STM32_Programmer_CLI -w32 0x0803E010 0x66778899       # AES key word 3
[dry-run] STM32_Programmer_CLI -w32 0x0803E014 0x4C534544       # LSED magic
… (8 K_seed words at 0x0803E018..0x0803E034)
[dry-run] STM32_Programmer_CLI -ob RDP=1
[dry-run] STM32_Programmer_CLI -c port=SWD --quietMode
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
| `super_admin` | Ініціювати provisioning сесію | HSM presence + MFA. ⚠️ **MFA-половина сьогодні НЕДОСЯЖНА:** другого фактора в застосунку немає, і шлях його «увімкнення» закрито саме тому, що він лише друкував би заявку ([`00_07`](00_07_Action_Plan_Tracker) `S6.21`). Тобто рядок описує цільову умову, а не чинну — до TOTP реальний бар'єр тут = пароль + фізична присутність supervisor'а (§5) |
| `admin` | Спостерігати за прогресом | Read-only audit view |
| Factory Operator (без Rails-ролі) | Виконувати фізичне підключення | Лише після авторизації supervisor'а; UI показує тільки статус, не ключ |

**Як master key потрапляє до інструменту (три варіанти, від кращого до гіршого).** Після SEC.3 DI деривація приймає ключ параметром від `MasterKeySource` — варіанти 1–2 підключаються новим адаптером без правок derivation-сервісів (до DI non-ENV adapter був би мертвим кодом — деривація однаково читала ENV):

1. **HSM injection (рекомендовано для > 1 000 unit):** `PROVISIONING_MASTER_KEY` ніколи не покидає HSM (AWS CloudHSM / Thales Luna). Інструмент викликає HSM API для деривації `device_key = HKDF(master_key, device_uid)` всередині апаратного модуля → отримує лише готовий `device_key`. `master_key` у RAM інструменту не з'являється жодного разу.

2. **Envelope encryption (TRL 6/7, pilot batch):** `PROVISIONING_MASTER_KEY` зберігається у Bitwarden Secrets Manager або 1Password Secrets Automation. Перед кожною сесією — short-lived token (TTL 15 хв) генерується через API і передається інструменту через `PROVISIONING_SESSION_TOKEN` ENV. Після закінчення TTL — інструмент не може деривувати нові ключі без нового токена.

3. **Direct ENV (development/lab only):** `PROVISIONING_MASTER_KEY` встановлюється в ENV вручну перед запуском. Недопустимо у field-batch. `Security::WeakKeyDetector` блокує запуск з тест-векторами ([`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security), SEC.9).

**Ротація master key:**

- Нова сесія починається лише після верифікації нового ключа через `Security::WeakKeyDetector` (CLI runbook у [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security)).
- `previous_aes_key_hex` (Dual-Key Grace Period у `HardwareKey`) активний до підтвердження прошивки всіх пристроїв у партії.
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
| Persistent key cache на factory machine | `device_key` у RAM інструменту — zero-copy підхід: передається прямо в SWD write call, після якого `SecureRandom.random_bytes(32)` → overwrite буфера |
| Shoulder surfing / screen recording | Factory laptop з privacy screen filter; Provisioning Tool запускається у fullscreen kiosk mode без title bar |
| Key exposure через SWD/JTAG replay | Після Flash write → `HAL_FLASH_Lock()` → RDP Level 1 програмується одразу тим самим сеансом (`--rdp 1` прапорець у STM32CubeProgrammer CLI) |

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

**1. `AuditLog` (chain-hashed, `pg_advisory_xact_lock(827549841, org_id)`):**
```ruby
AuditLog.create!(
  action:        "factory_flash",
  actor_id:      operator_user.id,          # supervisor_id у metadata
  target_type:   "HardwareKey",
  target_id:     hardware_key.id,
  metadata: {
    device_uid:    device_uid,               # "SNET-XXXXXXXX"
    operator_id:   operator_user.id,
    supervisor_id: supervisor_user.id,       # 2-person rule
    atecc_serial:  se_serial_hex,         # Гілка B: 9-байт serial (nil для Гілки A)
    rdp_level:     1,                        # рівень RDP після flash
    batch_id:      batch_identifier,         # для групового аудиту
    flash_addr:    "0x0803E000",
    firmware_ver:  firmware_version_string
  }
)
```

**2. `MaintenanceRecord(action_type: :installation)`** — закриває loop «фізично прошито ↔ DB-зареєстровано»:
```ruby
MaintenanceRecord.create!(
  tree_or_gateway: device,
  action_type:     :installation,
  performed_by:    operator_user,
  notes:           "Factory Flash. Batch: #{batch_id}. RDP Level: #{rdp_level}. #{atecc_note}"
)
```

**Tamper-evident retention policy:**
- `AuditLog` — заборонено видаляти (Rails guard: `before_destroy { raise "AuditLog is immutable" }`).
- Chain hash перевіряється при кожному audit export (`AuditLog.verify_chain_integrity`).
- Мінімальний retention: 7 років (GDPR Article 17(3)(b) — legal obligation exception).

**2-Person Rule (рекомендовано для > 100 unit batch):** supervisor має підтвердити сесію через окремий Rails UI перед тим як інструмент отримає session token. Реалізується через `ProvisioningSession` AASM: `pending → supervisor_approved → active → completed/failed`.

---

### D. Гілка A vs Гілка B Threat Model Diff

| Вектор атаки | Гілка A (Protected Flash STM32) | Гілка B (ATECC608B / STSAFE-A110) |
|-------------|----------------------------------|-----------------------------------|
| **Фізичне вилучення ключа з чіпа** | RDP Level 1: ускладнено (voltage glitching можливий на старих ревізіях); RDP Level 2: практично неможливо | ATECC data zone lock + DPA-hardened silicon: key never leaves chip в plaintext; fault injection → self-erase |
| **Chip swap (ворог замінює STM32/ATECC на інший)** | STM32 не має унікального hardware ID прив'язаного до DB — swap непомітний до першого uplink (DID mismatch детектує Rails) | ATECC serial (9 байт, factory-burned) pin'ується у `(device_uid, atecc_serial)` парі в `HardwareKey`. Чужий ATECC → provisioning API reject з 409 |
| **Replay provisioning request** | `POST /provisioning/register` — ідемпотентний через duplicate DID check (409) | Те саме + ATECC serial pinning |
| **Factory insider attack (оператор копіює ключ)** | Ризик: SWD adapter може перехопити байти під час write якщо не використовується HSM injection | Ризик нижчий: ATECC write через I²C, ключ загружається через `atcab_write_zone()` — не проходить через user-space буфер у стандартній реалізації |
| **Cold-boot attack на factory laptop RAM** | Ризик: `device_key` у RAM до wipe (~мс) | Ризик нижчий: HSM injection → `device_key` ніколи не в laptop RAM |
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
