# 03_05: Апаратне симетричне шифрування та Безпека (Криптографія Пакетів)

> 📜 **Архітектурна нота (ARCH.42 Варіант B, 2026-05-23):** Силова частина криптостеку розділена на дві категорії:
> 1. **LoRa-канал (Soldier ↔ Queen + OTA broadcast):** AES-128-CCM (ARCH.42 LoRa-вибір; SE = SE050 — §3.7)
> 2. **CoAP-магістраль (Queen ↔ Rails) + AR-Encryption у Postgres:** AES-256-CBC / AES-256-GCM (без апаратного SE-constraint; ключ Queen зберігається у Protected Flash MCU)
>
> Постквантовий горизонт + ratchet-rotation описано у новому **§10 PQC Migration Roadmap**.

---

## 🎯 Мета

Зафіксувати детальний криптографічний пайплайн вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор): режими роботи AES (CCM для LoRa, CBC для CoAP), структуру зашифрованих пакетів, управління ключами (SE050 Secure Element — голос-дерева Ed25519/attestation, SEC.6, §3.7; per-device HKDF-деривація + фабричний provisioning виокремлені в [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning)), генерацію вектора ініціалізації (IV/Nonce) та довгостроковий PQC migration roadmap. Документ є SSOT для Hardware Security Audit перед масовим виробничим розгортанням.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — апаратне шифрування налаштовано; host-based тести проходять
- **Архітектурне рішення ARCH.42 (2026-05-23):** Варіант B — LoRa-канал переведено на **AES-128-CCM** (ARCH.42 LoRa-вибір; SE = SE050 — §3.7); CoAP-магістраль залишається на **AES-256-CBC**. Глобальний SSOT-патч виконано.
- **Відкрите:** ECB→AES-128-CCM (FW.2), MAC/MIC, ротація ключів → [`00_07`](00_07_Action_Plan_Tracker) (SEC.*).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `firmware/soldier/main.c` · `firmware/queen/main.c` | Крипто call-sites: `MX_CRYP_Init`, `HAL_CRYP_Encrypt/Decrypt`, `Flush_Cache_To_Rails` (CBC), `Handle_CoAP_Command` (ECB restore) |
| `app/services/telemetry_unpacker_service.rb` | Rails-сторона дешифрування батча |
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Фази 0-5, RTC, IWDG, key loading |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Прошивка Королеви (CBC flush, ECB restore) |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | mruby атрактор |
| [`03_06` — Factory Flashing and Key Provisioning](03_06_Factory_Flashing_and_Key_Provisioning) | Provisioning ключів (HKDF/K_seed/OTA-HMAC) + factory-flashing — виокремлено з §3.4 |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | TelemetryUnpacker, ActuatorCommandWorker |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Pipeline (decrypt стадія) |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Апаратний контекст Queen |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | SEC.* (ECB→CCM, MAC, key rotation) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Відкриті безпекові питання та аналіз загроз (open → 00_07)](#-відкриті-безпекові-питання-та-аналіз-загроз-open--00_07)
- [1. Ініціалізація Крипто-Модуля (MX_CRYP_Init)](#-1-ініціалізація-крипто-модуля-mx_cryp_init)
- [2. Структура Зашифрованих Пакетів (Payload Structure)](#-2-структура-зашифрованих-пакетів-payload-structure)
- [3. Управління Ключами (Key Management)](#-3-управління-ключами-key-management)
- [4. Генерація Вектора Ініціалізації (IV)](#-4-генерація-вектора-ініціалізації-iv)
- [5. Діаграма Криптографічного Пайплайну](#-5-діаграма-криптографічного-пайплайну)
- [6. Зведена Таблиця Криптографічних Каналів](#-6-зведена-таблиця-криптографічних-каналів)
- [7. Відновлення Стану CRYP (ECB Restoration Pattern)](#-7-відновлення-стану-cryp-ecb-restoration-pattern)
- [8. Тестове Покриття (Host-Based Tests)](#-8-тестове-покриття-host-based-tests)
- [9. Резюме Аудиту Безпеки](#-9-резюме-аудиту-безпеки)
- [10. PQC Migration Roadmap (TRL-Stratified Post-Quantum Layering)](#-10-pqc-migration-roadmap-trl-stratified-post-quantum-layering)
<!-- TOC:AUTO:END -->

---

---

> **Стан реалізації** кожного компонента живе у відповідному розділі body нижче (§1–§10: крипто-init, packet-структура, key-management, IV, restore, PQC) + трекер відкритих пунктів — [`00_07`](00_07_Action_Plan_Tracker) (SEC.*). Канон **не тримає** окремий status-dashboard «Компонент \| Стан» (00_06 §1: стан компонентів читається з body + code-рефів, інакше дубль body/00_07 → drift).

---

## 🚧 Відкриті безпекові питання та аналіз загроз (open → 00_07)

> Статуси трекаються в [`00_07`](00_07_Action_Plan_Tracker) (SEC.*); нижче — канонічний аналіз загроз + рішення.

### Hardcoded AES-256 Key — Firmware CLOSED (FW.1, 2026-05-02)

✅ Firmware ЗАКРИТО (FW.1, 2026-05-02): `Load_AES_Key()` зчитує per-device HKDF-derived ключ з Protected Flash Sector (`FLASH_KEY_ADDR`, magic `"KEYL"`); hardcoded ідентичний ключ видалено. Factory Flashing Pipeline (SEC.3) та RDP Level 2 activation (SEC.2) залишаються (трекер → [`00_07`](00_07_Action_Plan_Tracker)).

**Файли (historical pre-FW.1):** `firmware/soldier/main.c`, `firmware/queen/main.c` (топ-рівневе оголошення `aes_key[]` до FW.1)

> ⚠️ **[PRE-FW.1 HISTORICAL — до 2026-05-02]** Код нижче — аудит-артефакт. Поточний стан: `uint32_t aes_key[8] = {0};` + `Load_AES_Key()` → §3.1.

```c
// [HISTORICAL] Однаковий ключ у ВСІХ вузлах мережі — Soldier та Queen.
// Post-FW.1: замінено на Load_AES_Key() з Protected Flash Sector.
// Якщо бачиш 0xXXXXXXXX у живій копії — FW.1 відкочений → СТОП та ескалюй.
uint32_t aes_key[8] = {0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX,
                       0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX, 0xXXXXXXXX};
```

> [HISTORICAL] `firmware/queen/main.c` до FW.1: `// МАЄ БУТИ ІДЕНТИЧНИМ ключу, зашитому в усіх Солдатах.`

**Виконані дії (FW.1, 2026-05-02):**

- ✅ `HKDF(PROVISIONING_MASTER_KEY, device_uid, "silken-aes-128-lora-key")` → Protected Flash (`FLASH_KEY_ADDR`) — per-device unique key.
- ✅ `Load_AES_Key()` + magic `"KEYL"` guard — boot відмовляє без provisioning (infinite reset loop; тест: `test_load_key_unprovisioned_flash_error`).
- ✅ Per-device ізоляція: злам одного Soldier не розкриває ключі сусідів.
- ✅ `Security::WeakKeyDetector` + boot-time guard (§3.1а, SEC.9) — FIPS-197 test vector не може потрапити в production.

**Залишається** (трекер — [`00_07`](00_07_Action_Plan_Tracker) SEC.2/SEC.3): SEC.3 Factory Flashing Pipeline tool (✅ 2026-05-24, dry-run; real `STM32_Programmer_CLI` subprocess + live `cryptoauthlib` I²C — deferred до HW bench; threat model → 03_06 §5); SEC.2 RDP Level 2 activation (необоротний final lock перед field deployment).

> **⚠️ ОПЕРАЦІЙНИЙ РИЗИК (Pre-Flight Checklist):** При кожному циклі прошивки — верифікувати що firmware binary отримує ключ з vault (не хардкоджений placeholder). Симптом помилки: Queen бачить щойно декриптований Soldier-пакет як хаотичний сміттєвий масив, ліс мовчазний, жодних помилок у Rails. Причина — ключ не синхронізований між Soldier і Queen Flash секторами. **Той самий «сміттєвий» ефект фундаментальний і для inter-Soldier mesh-релею за per-device ключів** (сусід не має ключа відправника) — opaque-релей вимагає cleartext address-шару або shared mesh-key → [`00_07` — ARCH.43](00_07_Action_Plan_Tracker).
>
> **⚠️ ЧЕСНІСТЬ ECB-транзиту (ARCH.42): per-device ключі НЕсумісні з ECB-каналом by construction.** Queen firmware тримає ОДИН `aes_key[4]` і декриптить ним усі вхідні LoRa-пакети; DID лежить УСЕРЕДИНІ шифроблоку → щоб обрати per-Soldier ключ, треба спершу розшифрувати (chicken-and-egg). Тож у ECB-перехідному режимі весь кластер де-факто живе на **спільному ключі** (Queen-key = Soldier-key) — FW.1 per-device HKDF-провіжининг стає реальним лише з **FW.2 CCM**, де DID/FC — cleartext AAD і бекенд (`process_ccm_chunk`) обирає `tree.hardware_key` per-DID. Це стосується і downlink-broadcast (OTA/beacon — один TX на всіх → один ключ). Bench-флешинг ECB-фази: всі вузли кластера отримують ключ Королеви. **Розв'язка (✅ founder 2026-07-03, FW.2 гейт (в)) — двоключова модель CCM-ери:** uplink-ізоляція йде session-ключем (KEYL per-device, CCM), а broadcast-структурність задовольняє окремий cluster control-plane ключ (KEYB — §3.1) — «спільний ключ» перестає бути компромісом usage-осей і стає СВІДОМИМ кластерним секретом класу K_ota лише для control-plane.

---

### ECB Mode для LoRa Soldier → Queen (transitional після ARCH.42)

🟡 Частково мітиговано через ARCH.42 (key-size 128); **повне закриття — після FW.2 CCM rollout** (трекер → [`00_07`](00_07_Action_Plan_Tracker) FW.2).

**Файли:** `firmware/soldier/main.c` (MX_CRYP_Init), `firmware/queen/main.c` (MX_CRYP_Init)

```c
// Soldier MX_CRYP_Init() — поточний стан (ARCH.42 transitional):
hcryp.Init.KeySize   = CRYP_KEYSIZE_128B;     // ARCH.42 — AES-128 LoRa (вибір; SE = SE050 — §3.7)
hcryp.Init.Algorithm = CRYP_AES_ECB;          // ECB transitional — TARGET: CRYP_AES_CCM після FW.2

// Queen MX_CRYP_Init() — поточний стан:
hcryp.Init.KeySize   = CRYP_KEYSIZE_128B;     // LoRa-канал з Soldiers (per-device 128-bit key)
hcryp.Init.Algorithm = CRYP_AES_ECB;          // ECB transitional — TARGET: CRYP_AES_CCM

// CoAP до Rails — Queen залишається на AES-256-CBC, окремий init context (HardwareKey Gateway-row).
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

**Необхідна дія (рекомендоване рішення — AES-128-CCM, після ARCH.42 Варіант B):**

Найефективніший шлях вирішення §ECB Mode та §MAC/MIC одночасно — перехід на **AES-128-CCM** (Counter with CBC-MAC), який **апаратно підтримується STM32WLE5JC** (`CRYP_AES_CCM` у HAL) та узгоджений з SE = **SE050** (§3.7). CCM надає конфіденційність + автентифікацію + захист від replay в одній операції. Силова margin: $2^{128}$ комбінацій — золотий стандарт LoRaWAN/Zigbee/Thread/BLE (індустріальне підтвердження "достатньо" для constrained IoT на 25-річний горизонт). Постквантовий розгляд — у §10.

**Структура 30-байтного LoRa-пакета (wire-rev2.1: rev2 founder 2026-06-12 — замість 16B ECB, rev1 = 24B; +2B EMA rev2.1 founder 2026-07-03, E.63 гейт (г) — обидві ревізії ДО фліпу за wire-budget ledger нижче):**

```
┌─ Header (cleartext, AAD) ─────────────────────────────────────────────┐
│ Byte 0 │ Byte 1 │ Byte 2 │ Byte 3 │ Byte 4 │ Byte 5 │ Byte 6 │ Byte 7 │
│      DID (Device ID, 4 байти)     │ gossip │  Frame Counter (3 B, BE) │
└────────┴────────┴────────┴────────┴────────┴────────┴────────┴────────┘
┌─ Encrypted payload (sensor data, 14 байтів) ──────────────────────────┐
│ Byte 8 │ Byte 9 │Byte 10 │Byte 11 │Byte 12 │Byte 13 │Byte 14 │Byte 15 │
│    Vcap (mV, BE)  │  Temp  │ Acous. │ delta_t RAW (BE)  │ Status │ Ctrl│
│Byte 16 │Byte 17 │Byte 18 │Byte 19 │Byte 20 │Byte 21 │                 │
│  device_z (BE)    │  diag  │  vpd   │ ema_delta_t (BE)  │              │
└────────┴────────┴────────┴────────┴────────┴────────┴─────────────────┘
┌─ MIC (Message Integrity Code, 8 байтів) ──────────────────────────────┐
│Byte 22 │Byte 23 │Byte 24 │Byte 25 │Byte 26 │Byte 27 │Byte 28 │Byte 29 │
│                    AES-CCM MAC (8 байтів — 64-bit)                    │
└────────┴────────┴────────┴────────┴────────┴────────┴────────┴────────┘
```

**14-байтний sensor payload (bytes 8..21):**

| Зсув | Поле | Тип | Діапазон / Кодування | Походження |
|------|------|-----|----------------------|------------|
| 0..1 | `Vcap_mv` | uint16 BE | 0..65535 мВ ⚠️ [ARCH.99] фактично ≈ VDDA-шина біля 3300, а не 0..5500: іменем поле обіцяє іоністор, а несе `Adc_Vdda_Mv()` ([`03_01`](03_01_Firmware_Lifecycle_and_DMA) FW.50) | повна 1 мВ-роздільність, як у поточному 16B |
| 2 | `temp_c` | int8 | −128..+127 °C | без змін |
| 3 | `acoustic_events` | uint8 (saturating) | 0..255 | FW.22 — saturating increment, без overflow ambiguity |
| 4..5 | `delta_t_s` | uint16 BE | 0..65535 сек (≈ 18 год) | повна роздільність — критично для [E.63] метаболічного `growth_points` (delta_t→GP на пристрої; backend декодує wire, точна звірка — FW.2, [`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA)) |
| 6 | `status_byte` | bitfield | `[panic:1 \| status:2 \| growth_points:5]` | FW.29 PANIC_FLAG_BIT (bit 7) + status (bits 6..5) + growth (bits 4..0); зменшено growth з 6 → 5 бітів (0..31), масштабований діапазон у `bio_contract.rb` |
| 7 | `mesh_ctrl` | bitfield | `[ttl:4 \| fw_version_id_low:4]` | TTL у верхніх 4 бітах (FW.10, max 15 hop), FW low-nibble (16-version rotation epoch керується OTA config) |
| 8..9 | `device_z` | uint16 BE | фіксована точка z×512 (q=2⁻⁹, 0..127.99); `0xFFFF` = «Лоренц не рахувався» (ARCH.41-C grace) | **[FW.31 Gate D]** numeric DCI: похибка квантування ≤ 0.00098 < ε 0.001; у шифртексті (z = здоров'я дерева); pack — `Pack_FW2_Device_Z` |
| 10 | `diag` | bitfield | `[thr_invalid:5 \| fauna_mode:1 \| fauna_skip:1 \| fc_degraded:1]` | **[FW.18b]** лічильник відкинутих OTA-порогів (у 21B жив у байті 11) + **[FW.42]** fauna-маркери ([`03_03 §10.4`](03_03_TinyML_Acoustic_Inference)) + **[FW.2]** I-HW degraded-прапорець; pack — `Pack_FW2_Diag` |
| 11 | `vpd_index` | uint8 | `0x00` = немає BME280 | **[HW.32]** резерв-дім VPD-індексу; шкала index→kPa визначається при калібруванні сенсора — закриває double-booking байта 14 з gossip'ом у 21B-плані |
| 12..13 | `ema_delta_t_s` | uint16 BE | 0..65535 с (сатурація min(EMA, 0xFFFF)) | **[E.63 (г), rev2.1]** КОНТРАКТ «wire = вхід GP»: САМЕ це число з'їла `metabolic_health` цього циклу (Soldier Фаза-3 сатурує ДО mruby і пакує те саме; panic → 0, не-warmed EMA → BASELINE 60) → backend `expected_homeostasis_gp(ema)` recompute'ить GP **stateless байт-точно**; observational до bench-калібрування порогів. RAW dT (bytes 4..5) лишається для діагностики/server-EMA ([`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA)). Транзієнт (не персистить) |

**Поля, які видалено / переміщено з поточного 16-байтного payload:**

| Поле (16B) | Куди подівся | Причина |
|------------|--------------|---------|
| `firmware_version_id` (2B → 4 bits) | spliced у `mesh_ctrl[3..0]`; epoch керується OTA | повна 16-bit version_id занадто щедра — на практиці одночасно живуть ≤ 16 версій fleet-wide; epoch у OTA config block (FW.8 канал) подовжує rotation |
| `panic_frame_counter` (2B, SEC.10) | замінено CCM Frame Counter (header) + MIC | **CCM nonce + MIC = криптографічний anti-replay**; SEC.10 RTC counter був тимчасовою сторожею панічного каналу до приходу FW.2 (явно так задокументовано в §3.5а) |
| `gossip_ts_byte` (1B, FW.20-S2 5/5) | **AAD byte 4** (wire-rev2) — навмисно cleartext | per-Soldier CCM-ключ робить шифртекст нечитним для сусідів → gossip У payload помер би; AAD-байт сусіди читають без ключа (та сама untrusted-довіра ±128 c, що в ECB-piggyback), бекенд автентифікує MIC'ом. Стара ідея «deferred до FW.20-S3 TDMA» знята — місце знайшлося задарма (top-байт FC32-поля був завжди 0x00, бо лічильник 24-бітний) |
| `PAD` (2B) | усунено повністю | пакет щільніший за 16B+5B header |

**Header (cleartext, AAD-authenticated):**

- **DID (4B):** Незмінений — Queen-side filter та lookup ключа. Передається як AAD у CCM, тому MIC покриває і його (підміна DID → MIC fail).
- **gossip_ts_lsb (1B, byte 4):** `soldier_unix_ts & 0xFF` (0 = час невідомий) — FW.20-S2 #5 gossip-piggyback, що переживає per-Soldier ключі. У нонс НЕ входить (унікальність тримає сам FC); підміна на дроті → MIC fail на бекенді.
- **Frame Counter (3B BE, wire-rev2):** на дроті їде справжня 24-бітна ширина (rev1 слав 4B, де top-байт був завжди 0x00 — wire-rev2 віддав його gossip'у). Monotonic 24-bit у `RTC_BKP_DR15` (єдиний вільний слот — DR2 ❌ зайнято `has_mesh_relay` за SSOT 03_01 §2; doc-fix 2026-05-24). ⊕ **Дротовані спостерігачі (2026-08-29):** `sn-alert-ccm-fc-replay` — не строго зростаючий FC (ДВІ причини протилежного знаку: інʼєкція записаних кадрів ⊥ скидання RTC після брауноуту, і розводить їх сусідство з `sn-alert-ccm-mic-fail`); `sn-alert-fw2-fc-degraded` — втрачений інваріант I-HW (Flash відмовляє писати high-water), тобто **ПРИЧИНА, яку перший побачить лише як наслідок і пізніше**. Cold-boot магічний маркер `FW2_FC_MAGIC_BYTE = 0x46` ('F', — дзеркало `lora_ccm.h`) у packing `[magic:8 | frame_counter:24]` — magic у high 8 бітах захищає від невалідного DR15 після VBAT loss (similar pattern до LORENZ_STATE_MAGIC у DR19). 24-bit FC дає **~16.7M значень** — за бюджету 1 TX/година × 8760 год/рік × 25 років = ~219 тис. TX/пристрій життєвий цикл = `18 bit` зайнято, **запас 6 bit ≈ 64× longevity margin** (компроміс: уживаємо magic-byte для cold-boot detection vs full 32-bit FC). Інкрементується перед кожним TX. Cold-boot після VBAT-loss (DR15 magic не збігається) → **Flash high-water floor** (KV-ключ `0x14`, монотонний якір — TRL-7 host-half ✅ 2026-06-12), fallback — reseed з HRNG (range `0x000001..0xFFFFFE`, без обнулення/overflow boundaries). Backend per-DID Redis SETNX 25h-window дедуплікує replay у вікні. **Повна cold-boot політика (floor+advance атомарність, чесна оцінка nonce-унікальності) — у 📐 КАНОНІЧНОМУ ДЖЕРЕЛІ нижче** (не дублюємо тут). **Реклама `panic_frame_counter` із DR0[31:16] звільняється** разом з активацією FW2_CCM (`#define FW2_CCM_ENABLED 1`) — CCM FC одночасно служить anti-replay для всіх пакетів (включно з panic), що закриває SEC.10 firmware-сторону автоматично.

**MIC (8B = 64-bit MAC) — обґрунтування розширення з 4B:**

CCM специфікація (NIST SP 800-38C) дозволяє `t ∈ {4, 6, 8, 10, 12, 14, 16}` байтів. Початкова чорнетка містила 4B (32-bit), що дає **forge probability ≈ 1/2³² ≈ 2.3×10⁻¹⁰ на спробу**. Для billion-tree-scale мережі з 10⁶ вузлами та активним adversary:
- 4B MIC: атакер з ~4 млрд forge-attempts (~14 годин при LoRa duty cycle) має ймовірність успіху ≈ 1
- 8B MIC: forge probability ≈ 1/2⁶⁴ ≈ 5.4×10⁻²⁰ — **криптографічно безпечно** на 25-річний горизонт навіть проти optimal-attack

Зайняття 4 додаткових байтів **звільняється** від видалення «Зарезервовано» поля (попередня чорнетка). Wire-rev2 свідомо НЕ торкає MIC (LoRaWAN-мінімум 4B відкинуто): +4B на claimants узято з символьного бюджету кадру (див. airtime нижче), 64-bit MIC лишається.

**Nonce конструкція (CCM nonce, 12 байт):**

```
nonce[12] = DID[0..3] || FC32[0..3 BE, top-байт 0] || 0x00 × 4
            ↑              ↑
            з header       monotonic per-DID (24-bit, доповнений нулем)

Байт-у-байт ідентичний rev1-нонсу: gossip-байт (AAD byte 4) у нонс НЕ
входить — унікальність (key, nonce) гарантує сам FC, а Redis replay-guard
і golden-вектори нонс-математики лишаються чинними.

```

**Унікальність (key_128, nonce) — безумовна при живому Flash-якорі, імовірнісний fallback — 📐 КАНОНІЧНЕ ДЖЕРЕЛО (FW.2 FC/nonce policy):**

> Єдине авторитетне місце для Frame-Counter lifecycle + nonce-унікальності. Решта місць лише **посилаються** сюди: [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA) (RTC-мапа, DR15) + §2.3.1 (KV-ключ `0x14`), `firmware/common/lora_ccm.h` (байт-формат), `firmware/common/fc_hiwater.h` (high-water механіка), `firmware/soldier/main.c::Load_Frame_Counter` (floor/reseed), `00_07 FW.2`.

- **Зберігання + інкремент:** FC — 24-bit у `RTC_BKP_DR15`, упакований `[FW2_FC_MAGIC:8 | frame_counter:24]` (magic `0x46` ловить невалідний DR15 після VBAT-loss). Інкремент перед кожним TX; wrap `0xFFFFFF → 1` (skip 0 = «треба reseed»). ~16.7M значень ≫ ~219 тис. TX за 25-річний lifecycle. FC персиститься у DR15 **перед** TX (reboot між Save і TX просуває лічильник, а не повторює).
- **Нормальна робота:** per-device LoRa key (FW.1 HKDF) константний + FC monotonic-incrementing → кожна (key, nonce) пара унікальна **за конструкцією**.
- **Flash high-water якір (TRL-7 monotonic, host-half ✅ 2026-06-12, gated `FW2_CCM_ENABLED`):** у Flash-KV ключі `0x14` (реєстр [`03_01 §2.3.1`](03_01_Firmware_Lifecycle_and_DMA)) лежить межа, яку жоден переданий FC ще не перетнув — **інваріант I-HW: переданий FC строго менший за межу у Flash на момент TX** (LoRaWAN NVM-патерн). Підтримка: проактивний advance у КЕНОЗИСІ (наступний TX ближче ніж `MARGIN=8` до межі → один dw-program ставить її на `STRIDE=256` уперед; ~856 записів за life-budget — мізер для wear, [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)) + сторожа-останній-рубіж у `Build_CCM` (energy-gated `VCAP_LISTEN_THRESHOLD`; відмова → TX дозволений + degraded-прапорець: телеметрія дорожча за теоретичний replay). Механіка + дисципліна викликача — `firmware/common/fc_hiwater.h`; сценарні host-тести (інваріант щоцикл, подвійний brownout, fault-injection) — `firmware/test/test_flash_kv.c` секція FW.2.
- **Cold-boot (VBAT loss):** DR15 magic втрачено → **перший рубіж = Flash-floor**: рестарт з межі `0x14` монотонний без жодної ентропії. Floor законний **лише разом з негайним просуванням межі** (атомарність floor+advance — інакше повторний brownout до наступного КЕНОЗИСУ стартував би з того самого floor і повторив nonce); запис тут — один атомарний dw-program без erase (compact відкладений у безпечну фазу), тож давнє застереження «Flash-write небезпечний при кволому пост-drain заряді» знято конструкцією: відмова program безпечна — спрацьовує fallback. **Fallback (якоря нема / Flash відмовив):** FC reseed **uniform-random з HRNG** — стара TRL-6 політика без погіршення. Monotonic-across-boot RTC-джерел у цей момент немає (RTC-календар і `soldier_unix_ts` на дефолтах — wall-clock дає лише FW.20 beacon, якого ще нема — той самий стан, що Lorenz cold-start, 03_06 §3); SE свідомо не будимо (§3.7).
- **Залишковий ризик / severity:** при живому якорі повтор (key, nonce) **неможливий за конструкцією** (інваріант I-HW). Імовірнісний ризик `N/2²⁴` на cold-boot лишається **тільки** на fallback-шляху: перше втілення до першого КЕНОЗИСУ або стабільно мертвий Flash-program — **Severity: MEDIUM на fallback, не baseline** (CTR-reuse дає лише витік `P1⊕P2` двох 12-байтних низькоентропійних сенсорних payload'ів, **не** компрометацію ключа; forge все одно потребує per-device key). Cold-boot'и рідкісні (drain ≈ сезонний). Epoch-край: 24-bit простір одноразовий — біля `0xFFFFFF` межа клемпиться, нову nonce-епоху відкриває лише ротація ключа (FW.17, §3.8); за life-budget край недосяжний (64× margin).
- **Reseed entropy (fallback-шлях):** тільки HRNG з **retry ×3** — слабкого `HAL_GetTick` fallback **немає** (на cold-boot tick малий+передбачуваний → кластеризується між cold-boot'ами того ж пристрою). Last-resort при мертвому HRNG — `tree_did ^ tick` (DID ламає крос-девайс кластеризацію). SEC.10 panic-counter (`main.c` DR0[31:16]) — **той самий** reseed-патерн + те саме hardening при активації FW.2.
- **TRL-7 residual:** SE050 monotonic counter лишається alt-шляхом для рунга L2 (§3.7) — Flash high-water його не потребує. Silicon-residual high-water = той самий, що FW.8/FW.17: Flash-KV HAL-глю на кремнії (bench). Трекінг → `00_07 FW.2`.

> ✅ **DR15 resource-conflict — ВИРІШЕНО (2026-05-30):** FW.2 FC **володіє** `RTC_BKP_DR15` (реалізовано — `lora_ccm.h` + `firmware/soldier/main.c`; канонічно у [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA)). FW.20-S2 anti-storm dedup-bitmap (ARCH.28) переходить на **Flash-KV store** ([`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)), бо всі 20 RTC backup-регістрів (DR0–DR19) зайняті. Стале-формулювання «DR15 наразі резерв» у [`00_07`](00_07_Action_Plan_Tracker)/[`03_02`](03_02_Queen_Gateway_Firmware) виправлено на цей вердикт.

**Конфігурація `hcryp` для CCM (AES-128) — WL-істинний двофазний флоу:**

> ⚠️ **WL-HAL знахідка (2026-07-03, зловлено compile-варіантом hal_check_ccm):** `HAL_CRYPEx_AESCCM_Encrypt/Decrypt` у STM32WLxx HAL **НЕ ІСНУЮТЬ** — то API старших родин (F4/F7/L4). WL дає лише `HAL_CRYP_Encrypt/Decrypt` (payload-фаза, CCM-алгоритм конфігом) + `HAL_CRYPEx_AESCCM_GenerateAuthTAG` (тег-фаза окремо); на decrypt HAL тег **не звіряє** — вирок виносить викликач константним порівнянням (`Fw2_Ccm_Tag_Equal`). Первісний freeze-contract кликав неіснуючий API і впав би на першому ж залізному лінку. Shape-дім: `firmware/common/lora_ccm.h` (шапка + `Build_CCM_B0*`); обидва call-sites (`Soldier_Build_CCM_LoRa_Packet` / `Queen_Parse_CCM_LoRa_Packet`) вже на двофазному флоу, host-мок дзеркалить його і **валідує B0** проти білдера.

```c
// Фаза 0 (конфіг): нонс живе всередині B0-блоку (NIST 800-38C: flags 0x5A ‖
// nonce[12] ‖ Q=12), AAD — окремим Header; Size обох фаз — у БАЙТАХ.
hcryp.Init.KeySize         = CRYP_KEYSIZE_128B;   // ARCH.42 — AES-128 LoRa (SE = SE050 — §3.7)
hcryp.Init.pKey            = aes_key;             // uint32_t aes_key[4] (16 bytes)
hcryp.Init.Algorithm       = CRYP_AES_CCM;
hcryp.Init.DataType        = CRYP_DATATYPE_8B;    // байтопотік (32B word-swap клас — KAT на bench)
hcryp.Init.B0              = b0_w;                // Build_CCM_B0(did, fc, …) — 16B
hcryp.Init.Header          = aad_w;               // AAD = DID(4)+gossip(1)+FC24(3)
hcryp.Init.HeaderSize      = 8;
hcryp.Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_BYTE;
hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_BYTE;
HAL_CRYP_Init(&hcryp);
// Фаза 1 (payload): 12B sensor → 12B ciphertext
HAL_CRYP_Encrypt(&hcryp, pt_w, 12, ct_w, 1000);
// Фаза 2 (тег): повний 16B-блок, MIC = перші 8 байт
HAL_CRYPEx_AESCCM_GenerateAuthTAG(&hcryp, tag_w, 1000);
// Після CCM: MX_CRYP_Restore_From_CCM() — ECB назад + width-units у WORD
// (липкий BYTE зламав би word-Size усіх ECB/CBC шляхів) + NULL B0/Header.
```

> **Примітка airtime:** 30-байтний пакет rev2.1 коштує ті самі 493.6 мс, що 28B rev2 (+20% vs 21B; SF10/DR2) — у межах duty-cycle бюджету EU868 (< 0.014% при 1 TX/година, запас 72×). Ключовий факт символьної квантизації: 24..27B коштують ОДНАКОВО (43 символи), 28-й байт відкриває блок 28..31B (48 символів) — тому VPD-байт rev2 оплачено свідомо (+12 мДж/TX), а **+2B EMA rev2.1 їдуть у тому самому блоці задарма** (нуль додаткових мс/мДж). Детальний розрахунок + wire-budget ledger — нижче.

> **Cross-ref для backend (✅ 2026-05-24; wire-rev2 ✅ 2026-06-12; rev2.1 ✅ 2026-07-03):** `TelemetryUnpackerService.process_ccm_chunk` реалізовано feature-flagged через `ENV["TELEMETRY_CCM_ENABLED"]=true` (default off → 21B ECB path без змін). Парсить 31-байтний chunk `[DID:4][RSSI:1][gossip:1][FC:3 BE][ciphertext:14][MIC:8]` (Queen prepends RSSI до 30B LoRa air format), виконує AES-128-CCM decrypt + MIC verify через `Cryptography::LoraCcm.decrypt(...)` (8-byte AAD=DID‖gossip‖FC24, 12-byte nonce=DID‖FC32‖4×0x00, 8-byte tag, `HardwareKey#binary_key` — 16 bytes після ARCH.42), per-DID Frame Counter SETNX `silken:ccm:fc:{did}:{fc}` TTL=25h (як SEC.10 panic guard), unpack 14-byte sensor payload (`n c C n C C n C C n` = … + device_z BE / diag / vpd_index / **ema_delta_t_s**), upscale `growth_points` 5-bit (0..31) → stored 0..62 через ×2 multiplier (per-species coefficient залишається у `Wallet#lock_and_mint!` через `tree_family.carbon_sequestration_coefficient` — без змін). Споживання rev2/rev2.1-полів: `device_z` (≠0xFFFF → /512.0) живить numeric DCI ([`03_04 §7.1`](03_04_mruby_Lorenz_Attractor) Gate D; транзієнт — стрипається перед persist, як lorenz_temperature_c); **`ema_delta_t_s` → точна metabolic-гілка `check_metabolic_divergence!`** (recompute `Attractor.expected_homeostasis_gp(ema)` == wire-GP; **observational** warn+метрика до bench-калібрування; транзієнт); diag-біти → метрики `silkennet_tinyml_threshold_invalid_reports_total` / `silkennet_fauna_skip_reports_total` / `silkennet_fw2_fc_degraded_reports_total` (cardinality-патерн FW.18b: per-DID атрибуція warn-логом); `vpd_index` до калібрування HW.32 у БД не пишеться. Spec coverage: `spec/services/cryptography/lora_ccm_spec.rb` (golden vectors rev2.1, дзеркало `ccm_kat_vectors.h`) + `spec/services/telemetry_unpacker_service_spec.rb` "FW.2 CCM" секція (вкл. exact-recompute гілку).

> **Cross-ref для firmware (✅ 2026-05-24 doc-fix + freeze-contract impl):** RTC Backup Domain розширення — Frame Counter у DR15 (єдиний вільний слот; DR2 ❌ був помилково вказаний — насправді DR2 зайнято `has_mesh_relay`). Magic marker `FW2_FC_MAGIC_BYTE = 0x46` ('F') у high 8 бітах захищає cold-boot. Реалізовано freeze-contract у `firmware/soldier/main.c` (`Load_Frame_Counter` / `Save_Frame_Counter` / `Soldier_Build_CCM_LoRa_Packet`) та `firmware/queen/main.c` (`Queen_Parse_CCM_LoRa_Packet`) під `#define FW2_CCM_ENABLED 0` — production cycle не активний до hardware bench. Host-тести у `firmware/test/test_ccm.c` + спільні KAT-вектори `firmware/common/ccm_kat_vectors.h` (wire-rev2, регенеровано 2026-06-12) забезпечують byte-level parity з OpenSSL CCM (linked via `-lcrypto`); єдине, що залишається для HW bench — підтвердити що STM32WLE5JC `HAL_CRYPEx_AESCCM_Encrypt` дає байт-точну відповідність до OpenSSL.

> **📋 FW.2 flip-checklist (стан post-pre-authoring 2026-07-03 — інтеграція ЗАШИТА за гейтами, фліп = верифікація):** уся integration-half, яку попередня версія цього чекліста веліла «написати на bench-дні», **вже authored** обабіч за `FW2_CCM_ENABLED` (Queen: OnRxDone 16|air + `rx_route.h` маршрутизація + fmt-aware CIFO + flush записами air+1 (rev2.1 = 31B); Soldier: Фаза-4 CCM TX + panic-CCM у `Trigger_Emergency_LoRa_TX` + ungated RX-guard `size!=16`-до-декрипту; господар-CI: compile-варіант `hal_check_ccm` доводить збірку гейтованого тракту проти справжнього WL-HAL щопушу). **Архітектура hot path Королеви — сліпий кур'єр** (інверсія довіри цього ж §: DID/FC з cleartext-AAD, сирий air-хвіст → запис air+1, MIC верифікує лише Rails per-DID; `Queen_Parse_CCM_LoRa_Packet` = bench-атестація RX-тракту, НЕ hot path). Фліп-день лишає: (1) bench-атестацію (`ccm_selftest`+`sym_selftest` через SWD — RUNBOOK §2.1) + e2e uplink-day; (2) фліп трьох прапорів (`FW2_CCM_ENABLED` обабіч + `TELEMETRY_CCM_ENABLED`); (3) **свідомі фліп-гейти** (дім рішень — [`00_07`](00_07_Action_Plan_Tracker) FW.2): (а) ✅ **УХВАЛЕНО (founder, 2026-07-03): atomic-cutover кластера як зашито** — Rails тримає ОДИН stride на батч, 16B-телеметрію не-прошитих Солдатів Королева ДРОПАЄ (wire-видимість — QATT-флаги `LEGACY_DROPS`/`CCM_SPOOF`, §2.2; точні числа — SWD). Одиниця cutover'а = **кластер** (Queen + її Солдати + Rails-ENV); операційне правило = **фліп ДО першого field-deploy** (OTA прошивку не оновлює → польова міграція була б SWD-візитами; rollback до поля = хвилини). Свідома ціна: mesh-естафета (вкл. panic-hop TTL=5) у CCM-еру мертва — air-кадр гине на RX-guard сусіда, Сценарій Б гейтовано `#if !FW2_CCM_ENABLED` → **star-only до ARCH.43-addressing**. Названі апгрейд-шляхи (НЕ будуємо — YAGNI до тригера): era-mix кластерів під одним Rails → per-gateway гейт замість глобального `TELEMETRY_CCM_ENABLED`; польовий ECB-парк до фліпа → SWD-візит-план; (б) ✅ **ЗНЯТО (ARCH.54, 2026-07-03)** — health живе у QATT-v2 конверті ([`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)), від CCM-stride не залежить, blackout зник by design; (в) ✅ **УХВАЛЕНО (founder, 2026-07-03): ДВОКЛЮЧОВА модель** (замінила план «спільне значення до ARCH.43»): **session KEYL per-device** (телеметрія+panic CCM — money-path ізольований, фабрика вже так деривує) + **cluster control-plane KEYB** (весь downlink-broadcast 0x99/0x9A/0x9B/0x9C/0x9D/0x9E + uplink 0x55/0x56 — Королева session-ключів не тримає). Механіка/слоти — §3.1; обґрунтування per-cluster = клас K_ota ([`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)); свідомі стелі: downlink лишається ECB+CRC **без MAC/FC** (anti-replay downlink'а нема, як і в ECB-ері — закриє майбутня downlink-wire-ревізія, вона ж активує FW.17 — §3.8), компрометація вузла = KEYB кластера розкрито (control-plane forge; OTA-image окремо гейтований K_ota-HMAC, мінт-фрод неможливий без session+K_seed); (г) ✅ **УХВАЛЕНО (founder, 2026-07-03, друге читання — переглянуто V3+): +2B EMA-поле ЗАРАЗ (wire-rev2.1, 30B)** — розділення осей, якого V3+ не зробив: НОСІЙ (wire-поле) ≠ ФОРМА (пороги/m()); носій інваріантний до форми й самоцінний для калібрування (польова recharge-крива КОЖНОГО дерева, не одна крива стенда), airtime-задарма (той самий 48-символьний блок), а «вирішити на фліп-дні» конфліктувало з дисципліною ledger'а (wire-ревізія нашвидку в день атестації). Контракт «wire = вхід GP» (Soldier сатурує ДО mruby, пакує те саме число) → точний stateless recompute `expected_homeostasis_gp(ema)` — **observational до bench-калібрування** (тут V3+ лишається правим: hard-gate поперед фізики не зашивається; вмикання строгості = один перемикач ПІСЛЯ RUNBOOK §3.3). CCM-flip також РОЗГЕЙТЛЮЄ (не фліпає автоматично) пов'язані гейти — FW.17-ротація (`FW17_RATCHET_ENABLED` + Queen `FW20_Q2_CMD_RELAY_ENABLED` + backend ENV, §3.8) фліпається окремим кроком з власним e2e (bench RUNBOOK §2.6); ARCH.35-ринг у CCM-ері потребує запису air+1 = 31B (`FLASH_RING_RECORD_SIZE` — позначено в коді).

#### 📒 Wire-budget ledger (SSOT черги на байти LoRa-кадру)

> **Навіщо:** до wire-rev2 на байти кадру стояла тіньова черга без обліку — претенденти жили розкидано по трекеру, а 24B-freeze мовчки ВИПУСТИВ FW.18b-лічильник (freeze 2026-05-24 старший за FW.18b 2026-06-10) і вбивав gossip (per-Soldier ключ робить payload нечитним для сусідів). Цей ledger — єдине місце обліку. **Нова потреба у wire-байтах реєструється ТУТ до того, як їй пообіцяно місце.**

**Бюджетні факти (рахуються з airtime-формули нижче):**
- Символьна квантизація SF10/125kHz/CR4:5: кадри **24..27B коштують однаково** (43 символи, 452.7 мс); 28B відкриває блок 28..31B (48 символів, 493.6 мс); наступний поріг — 32B.
- Top-байт старого FC32-поля був **завжди 0x00** (лічильник 24-бітний) — 1 безкоштовний cleartext-байт в AAD.
- Headroom після rev2.1: **+1 байт безкоштовно** (30..31B — той самий 48-символьний блок; 32B відкриває наступний; rev2.1 забрала 2 з 3 під EMA). Біти: `mesh_ctrl.ttl:4` тримає max 15 hop при потребі 0..5 (1 біт можна реклемувати), `vpd_index` до HW.32-калібрування = de-facto резервний байт.
- **RAM-ціна фліпа (виміряно `arm-none-eabi-size` на hal_check-TU, 2026-07-03, rev2-ширини):** Soldier `.bss` +20 Б (5 724 / 8 192 TU-бюджету), Queen `.bss` +596 Б (18 980 / 20 480 — ринг 16×len-слоти + CIFO 50×fmt-теговані слоти). **Rev2.1 ширини похідні** (+2/слот: ринг +32 Б, CIFO +100 Б розрахунково — перевимір на CI `hal_check_ccm` size). Бойовий білд (гейти 0) цієї ціни НЕ платить — ширини гейтовані, [FW.26]-гейт міряє бойовий `hal_check`.

**Розв'язана черга (wire-rev2, 2026-06-12):**

| Претендент | Розмір | Дім у rev2 | Статус |
|---|---|---|---|
| FW.31 Gate D `device_z` (numeric DCI; покриття ≥95% → мультиплексувати не можна) | 2 B | ciphertext bytes 16..17 (`×512`, сентинель `0xFFFF`) | ✅ |
| FW.18b `thr_invalid` (випав із 24B-freeze!) | 5 біт | `diag[7..3]` | ✅ |
| FW.42 fauna mode + skip | 2 біти | `diag[2..1]` | ✅ |
| FW.2 `fc_degraded` (I-HW сторожа без транспорту) | 1 біт | `diag[0]` | ✅ |
| FW.20-S2 gossip `ts_lsb` (МУСИТЬ бути cleartext) | 1 B | AAD byte 4 (екс-FC-нуль — задарма) | ✅ |
| HW.32 VPD-індекс (закрив double-booking байта 14 у 21B-плані: 03_01 §HW.32 і 03_02 §5а.2 обидва претендували на byte 14) | 1 B | ciphertext byte 19 (`0x00` до BME280) | ✅ (шкала — при калібруванні) |

**Відкриті спостереження (НЕ розв'язано rev2 — кандидати наступної ревізії/ARCH.26):**
- **Mesh-relay TTL у шифртексті:** ретранслятор НЕ може декрементувати `mesh_ctrl.ttl` (encrypted+MIC, per-Soldier ключ). Спадок rev1-freeze, rev2 не погіршує: relay CCM-телеметрії = opaque store-and-forward, дедуп — за cleartext DID (`recent_mesh_dids`). Чесне рішення (TTL у AAD? hop-лічильник Queen-side?) — разом з ARCH.26 TDMA.
- **Climate frame (HW.32 сирі RH/тиск):** окремий періодичний кадр (НЕ per-cycle поле) — Queen маршрутизує за довжиною (16B control / air-телеметрія (30B rev2.1) / інша довжина = climate). Формат проєктувати при HW.32.
- **E.63 EMA-delta_t — ✅ РОЗВ'ЯЗАНО rev2.1 (founder 2026-07-03, друге читання; було «на фліп-дні» V3+):** wire несе ОБИДВА — raw dT (bytes 12..13, діагностика/server-EMA — [`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA)) + **EMA-delta_t (bytes 20..21, контракт «wire = вхід GP»)** → точний stateless recompute можливий конструкцією, observational до bench-калібрування. Чому переглянуто V3+: носій ≠ форма (поле інваріантне до порогів/m()); самоцінність для калібрування (польовий розподіл recharge-кривих); airtime нуль; «на фліп-дні» ламало дисципліну ревізії нижче. Якщо bench покаже мертвий сигнал — поле деградує в діагностично-резервне (прецедент vpd_index). Гейт (г) фліп-чекліста ✅.
- **FW.59 reset-cause / crash-forensics (кандидат наступної ревізії):** Soldier потребує 3-біт cause + consec-counter на дроті (Королева reset-cause = era-invariant QATT-nibble bits4..7 у §2.2, НЕ тут). Слот-кандидати з headroom вище: `vpd_index` (double-book з HW.32) / реклемований `mesh_ctrl.ttl`-біт / airtime-free 31B. Рішення при CCM-wire-фіналі → [`00_07` — FW.59](00_07_Action_Plan_Tracker).

**Дисципліна ревізії:** формат ревізується ЛИШЕ до польового фліпу (`FW2_CCM_ENABLED` все ще 0 — обидві прошивки і бекенд за гейтами, тож rev2 коштував код+тести+KAT-регенерацію, нуль міграції). Після фліпу будь-яка зміна = повний міграційний цикл (фліт у полі) → нові претенденти збираються тут і їдуть пакетом у rev3.

#### 🤖 Верифікація LoRa Airtime Budget: 16B (ECB) vs 24B/28B/30B (CCM-ревізії) vs 21B (поточний raw)

**Параметри LoRa (Silken Net default):**
- Частота: 868.1 МГц (EU868 band, sub-band g1)
- SF (Spreading Factor): 10 (DR2 в EU868)
- BW (Bandwidth): 125 kHz
- CR (Coding Rate): 4/5
- Preamble: 8 символів (default LoRaWAN)
- CRC: увімкнений
- Explicit header: так

**Формула LoRa airtime (Semtech SX1262 datasheet):**

```
T_symbol = 2^SF / BW = 2^10 / 125000 = 8.192 мс

T_preamble = (n_preamble + 4.25) × T_symbol = 12.25 × 8.192 = 100.35 мс

payload_symbols = 8 + max(ceil((8×PL - 4×SF + 28 + 16) / (4×(SF-2))) × (CR+4), 0)
  де PL = payload length в байтах, CR = 1 (для 4/5)
```

**Розрахунок для 3 варіантів:**

| Параметр | **21B (поточний)** | **16B (raw encrypted)** | **24B (CCM)** | **29B (21B + DID + RSSI + CCM overhead)** |
|----------|:------------------:|:-----------------------:|:-------------:|:-----------------------------------------:|
| PL (payload bytes) | 21 | 16 | 24 | 29 |
| Payload символів | 8 + ceil((168−40+44)/(4×8))×5 = 8 + ceil(172/32)×5 = 8 + 6×5 = **38** | 8 + ceil((128−40+44)/32)×5 = 8 + ceil(132/32)×5 = 8 + 5×5 = **33** | 8 + ceil((192−40+44)/32)×5 = 8 + ceil(196/32)×5 = 8 + 7×5 = **43** | 8 + ceil((232−40+44)/32)×5 = 8 + ceil(236/32)×5 = 8 + 8×5 = **48** |
| T_payload (мс) | 38 × 8.192 = **311.3** | 33 × 8.192 = **270.3** | 43 × 8.192 = **352.3** | 48 × 8.192 = **393.2** |
| T_total (мс) | 100.4 + 311.3 = **411.7** | 100.4 + 270.3 = **370.7** | 100.4 + 352.3 = **452.7** | 100.4 + 393.2 = **493.6** |
| Δ vs поточний | baseline | −10% | **+10%** | +20% |

> **Символьна квантизація (ключ wire-budget ledger):** формула дає ОДНАКОВІ 43 символи для PL = 24..27 (ceil((8·PL+4)/32) = 7) і 48 символів для PL = 28..31. Тобто перші +3B понад 24B були безкоштовні, **28B (wire-rev2) = той самий airtime, що гіпотетичні 29B з колонки вище: 493.6 мс**; наступний поріг — 32B.

**Duty cycle бюджет (EU868, sub-band g1: 1% duty cycle):**

```
Duty cycle = T_airtime / T_period

При 1 TX / годину:
  21B: 411.7 мс / 3,600,000 мс = 0.011% ✅ (87× запас)
  24B: 452.7 мс / 3,600,000 мс = 0.013% ✅ (79× запас)
  28B (wire-rev2): 493.6 мс / 3,600,000 мс = 0.014% ✅ (72× запас)

При 1 TX / 10 хв (stress mode):
  28B: 493.6 мс / 600,000 мс = 0.082% ✅ (12× запас)

При Emergency TX (PANIC_TTL=5, max 5 hops):
  28B: 5 × 493.6 мс = 2.47 сек total airtime
  Duty cycle single burst: 2.47s / 3,600s = 0.069% ✅ (14× запас)
```

**Енергетичний вплив (SX1262, +14 dBm, 3.3V):**

| Пакет | Airtime | Струм TX | Енергія TX |
|-------|---------|----------|------------|
| 21B (ECB) | 411.7 мс | 87 мА | 411.7 × 87 × 3.3 / 1000 = **118 мДж** |
| 24B (CCM rev1) | 452.7 мс | 87 мА | 452.7 × 87 × 3.3 / 1000 = **130 мДж** |
| 28B (CCM wire-rev2) | 493.6 мс | 87 мА | 493.6 × 87 × 3.3 / 1000 = **142 мДж** |
| Δ rev2 vs 21B | +82 мс | — | **+24 мДж (+20%)** |

Для EDLC 0.47F × 5.5V (E_stored = ½CV² = 7.1 Дж): один TX CCM-пакет (wire-rev2 28B) споживає 142 мДж = **2.0% заряду суперконденсатора**. При одному TX/годину та EBFC > 500 мВ генерації — бюджет **з великим запасом**.

**Висновок:** Перехід з 21B ECB → 28B CCM (wire-rev2) збільшує airtime на **+20%** (+82 мс), duty cycle на **+0.003%**, енергоспоживання на **+24 мДж/TX** — з них +12 мДж купують дім для ВСІХ відомих wire-претендентів (ledger вище), що знімає другий польовий міграційний цикл. Зміна key size з 256→128 (ARCH.42) **не змінює** airtime (block-cipher block size = 128 bit обох випадках; зменшується лише кількість Round-функцій з 14→10, що дає ~25% швидший AES-операцію — нехтовно). Усі параметри залишаються **далеко в межах** EU868 duty cycle (1%) та енергобюджету Soldier (2.0% заряду EDLC per TX). **LoRa airtime budget верифіковано: AES-128-CCM 28B (wire-rev2) схвалено founder'ом 2026-06-12** (+2B EMA → **rev2.1 30B** 2026-07-03: той самий symbol-блок 28..31B, нуль додаткового airtime — поточний target = 30B). ✅

**Альтернативні рішення (якщо `CRYP_AES_CCM` не підтвердиться при STM32WLE5JC bench-тестуванні):**
- **AES-128-GCM** — аналогічно CCM, але апаратна підтримка на цій ревізії може відрізнятися (треба перевірити RM0461 §27.4).
- **AES-128-CTR + окремий HMAC-SHA256 MIC** — потребує більше коду, але гнучкіше; CTR не вимагає nonce-padding як CCM.
- **AES-128 CMAC-LoRaWAN-style** — нативний LoRaWAN формат, готовий ecosystem (Helium/Sigfox bridge через ARCH.34).
- **Збереження ECB + 4-байтний HMAC суфікс** — мінімальні зміни, але без захисту від pattern analysis (не рекомендовано).

Рішення архітектурно узгодити з [`03_01` — Firmware Lifecycle](03_01_Firmware_Lifecycle_and_DMA) та [`04_02` — Business Logic](04_02_Business_Logic_and_Services).

**Блокує:** Hardware Security Audit, захист від replay-атак на LoRa-мережу.

---

### Відсутність MAC/MIC (Message Authentication Code) для LoRa-пакетів

🟡 Відкрито (трекер → [`00_07`](00_07_Action_Plan_Tracker); закривається FW.2 CCM) — **критична відсутність автентифікації повідомлень.**

**Контекст:** LoRa-пакет (16 байт) містить лише зашифровані сенсорні дані. Не передбачено жодного механізму перевірки цілісності або автентифікації джерела.

**Ризики:**

1. **Bit-flip Attack:** Адверсар може змінити один або кілька бітів у зашифрованому пакеті. В режимі ECB (без дифузії між блоками) це призводить до **передбачуваних** змін у відповідних позиціях дешифрованого тексту. Наприклад, перевернути bit 7 байту 7 → змінити кількість акустичних подій → фальшивий сигнал пилки.
2. **Injection Attack:** Будь-який пристрій у зоні LoRa може відправити підроблений пакет з довільним DID та сенсорними даними. Queen розшифрує та кешує його без перевірки джерела.
3. **Відсутній захист від маніпуляцій з payload:** AES-ECB **не автентифікує** — він лише шифрує. Без MAC (наприклад, AES-GCM або HMAC-SHA256) Queen не може відрізнити легітимний пакет від підробленого.

**Необхідна дія:**

- **Рекомендоване рішення (після ARCH.42 Варіант B):** Перейти на **AES-128-CCM** з 30-байтним пакетом (wire-rev2.1) — вирішує §ECB Mode та §MAC/MIC одночасно (див. §ECB Mode вище для повної специфікації формату з Frame Counter + MIC).
- Альтернатива: **AES-128-GCM** (надає одночасно конфіденційність + автентифікацію + nonce).
- Або: додати **HMAC-SHA256 MIC** (4 байти суфіксу) до кожного LoRa-пакету, скоротивши сенсорний payload до 12 корисних байтів.
- LoRaWAN-нативний вибір: **AES-128-CMAC** (стандарт LoRaWAN MAC layer) — спрощує bridging до Helium/Sigfox/Things Network (ARCH.34).

**Блокує:** Довіра до телеметрії, Proof of Growth Pipeline (05_02), Hardware Security Audit.

---

### HRNG Fallback — покращена ентропія (Виправлено)

✅ Reuse закрито (harden 2026-05-29); **predictability закрито 2026-06-15 [SEC.12]** — fallback-IV тепер key-derived PRF (HMAC-SHA256), host-парність vs OpenSSL.

**Реалізація:** нормальний шлях — HRNG (CSPRNG). При апаратній відмові RNG (`HAL_RNG` error) увесь 16-байтний fallback-IV деривується чистою функцією `coap_fallback_iv` (`firmware/queen/coap_iv.h`) як **HMAC-SHA256, ключований секретним CoAP-ключем** — host-тестована в `firmware/test/test_encryption.c` проти ДВОХ незалежних oracle (OpenSSL HMAC + one-shot `Silken_Hmac_Sha256`) + per-device/reboot/flush uniqueness:

```c
// coap_iv.h — key-derived IV (НЕ raw CSPRNG, але НЕПЕРЕДБАЧУВАНИЙ без ключа)
IV[0:16] = HMAC_SHA256(coap_key,
             "SilkenNet-CoAP-IV-v1" || uid_hash || unix_ts || flush_seq || tick)[0:16]
//  coap_key  -> робить PRF непередбачуваним (атакер без ключа не вгадає IV)
//  uid_hash -> per-DEVICE · unix_ts -> cross-REBOOT · flush_seq -> cross-FLUSH · tick -> sub-second
```

**IV Reuse** унеможливлено по всіх осях (per-device/reboot/flush контекст), а **IV Unpredictability** — досягнуто: вихід HMAC обчислювально непередбачуваний без `coap_key`. Примітив — той самий shared `silken_sha256.h` (FW.30, byte-parity vs OpenSSL `SeedDerivation`).

> ✅ **Residual закрито [SEC.12, 2026-06-15]:** колишній XOR-mix (`coap_fallback_iv_word`) давав лише *uniqueness*; key-derived HMAC дає й *unpredictability* — **без** AES-engine `E_key(counter)`, **без** SEC.8 ECB-restore, **без** bench-гейту. Канон раніше припускав, що key-derived IV потребує CRYP-двигун; `silken_sha256.h` робить це у pure-SW (Королева на LiFePO4; HMAC лише на rare RNG-failure шляху). Normal-path HRNG лишається первинним.

---

### Відсутній Механізм Ротації Ключів (Key Rotation)

🟡 Відкрито (трекер → [`00_07`](00_07_Action_Plan_Tracker) FW.17) — системна проблема при масштабуванні.

**Контекст:** Поточна архітектура передбачає єдиний статичний ключ, зашитий при Factory Flashing. Немає механізму зміни ключа без повної перепрошивки через OTA або фізичного доступу.

**Ризики:**

1. **Long-term Key Exposure:** Якщо ключ скомпрометовано (наприклад, через фізичний злам одного вузла + зчитування Flash), всі минулі записані LoRa-пакети можуть бути ретроспективно дешифровані (відсутнє Perfect Forward Secrecy).
2. **Регуляторна невідповідність:** GDPR, ISO 27001 та NIST SP 800-57 вимагають ротацію криптографічних ключів. При масштабуванні до публічного продукту NaaS це може стати юридичним блокером.
3. **OTA як вектор атаки:** Якщо OTA-канал не має власного механізму ключ-обміну, оновлення нового ключа через OTA саме по собі шифрується старим (скомпрометованим) ключем.

**Рішення — спроєктовано і freeze-contract'нуто: §3.8 [FW.17].** Hash-Ratchet
(NIST SP 800-108 HMAC-KDF, ключ ніколи не летить ефіром, wire-команда `0x9E`,
backward secrecy + чесна модель загроз + ECDH-alt ADR) — повна специфікація,
доми коду й residual'и живуть у §3.8 (One-Home), тут не дублюємо. Старий
ескіз (AES-self-encrypt, claim повної PFS при фізичному витягу) — SUPERSEDED
специфікацією §3.8. Передумова FW.1 (per-device provisioning) — ✅ виконана
(§3.1); активація gated на FW.2 CCM (authenticated downlink).

**Блокує:** Довгострокова безпека мережі, відповідність регуляторним вимогам NaaS.

---

### Захист від ECB Restoration Race — реалізовано (SEC.8)

✅ Виправлено (SEC.8): ECB-відновлення захищене RCC-скиданням та `NVIC_SystemReset()`.
**Файл:** `firmware/queen/main.c`

**Реалізація:**
```c
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;

if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
    // Жорсткий апаратний скид крипто-блоку через регістри RCC
    __HAL_RCC_CRYP_FORCE_RESET();
    __HAL_RCC_CRYP_RELEASE_RESET();
    // Повторна ініціалізація після апаратного reset
    if (HAL_CRYP_Init(&hcryp) != HAL_OK) {
        NVIC_SystemReset();  // Повний перезапуск MCU — крипто-блок незворотньо несправний
    }
}
```

`__HAL_RCC_CRYP_FORCE_RESET()` скидає всі регістри AES-блоку до Power-On Reset стану. Якщо і повторна ініціалізація не вдається — `NVIC_SystemReset()` перезапускає весь MCU. Queen відновиться і повернеться до нормальної роботи, замість того щоб мовчки продовжувати розшифровувати LoRa-пакети у невірному режимі.

**Закриває:** Надійність криптографічного пайплайну Queen при апаратних збоях.

---

## 🔐 1. Ініціалізація Крипто-Модуля (MX_CRYP_Init)

### 1.1 Soldier — `firmware/soldier/main.c` (MX_CRYP_Init)

```c
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType    = CRYP_DATATYPE_32B;   // 32-бітний порядок слів
  hcryp.Init.KeySize     = CRYP_KEYSIZE_128B;    // ARCH.42 (2026-05-23): AES-128 LoRa (SE = SE050 — §3.7)
  hcryp.Init.pKey        = aes_key;              // Per-device HKDF-derived LoRa key (RAM mirror, populated by Load_AES_Key() at boot — see 03_06 §2; uint32_t aes_key[4] = 16 bytes)
  hcryp.Init.Algorithm   = CRYP_AES_ECB;         // ECB transitional — TARGET: CRYP_AES_CCM після FW.2 30B-packet rollout (wire-rev2.1)
  HAL_CRYP_Init(&hcryp);
}
```

### 1.2 Queen — `firmware/queen/main.c` (MX_CRYP_Init для LoRa) + динамічне переключення на CBC AES-256 для CoAP

```c
static void MX_CRYP_Init(void)
{
  hcryp.Instance = AES;
  hcryp.Init.DataType    = CRYP_DATATYPE_32B;   // 32-бітний порядок слів
  hcryp.Init.KeySize     = CRYP_KEYSIZE_128B;    // ARCH.42 — LoRa-сесія за замовчуванням AES-128 (per-Soldier key lookup)
  hcryp.Init.pKey        = aes_key;              // Per-Soldier HKDF-derived 128-bit LoRa key (CIFO cache); during CoAP flush — пересувається на coap_key[8] (AES-256)
  hcryp.Init.Algorithm   = CRYP_AES_ECB;         // ECB transitional — TARGET: CRYP_AES_CCM
  // Примітка: для CoAP batch flush та downlink Queen ДИНАМІЧНО переключається на CRYP_KEYSIZE_256B + CRYP_AES_CBC + coap_key[8] + HRNG IV; після CoAP операції — restore назад до CRYP_KEYSIZE_128B/ECB/LoRa-key (SEC.8 ECB Restoration з force-reset RCC).
  HAL_CRYP_Init(&hcryp);
}
```

**Апаратна периферія:** AES-блок STM32WLE5JC (`hcryp.Instance = AES`) — апаратне прискорення без залучення ядра Cortex-M4. Не потребує програмних крипто-бібліотек. **Підтримує обидва KeySize** через runtime re-init.

**Параметри ключа (LoRa-режим, Soldier + Queen за замовчуванням):**

| Параметр | Значення | Примітка |
|----------|----------|---------|
| `KeySize` | `CRYP_KEYSIZE_128B` | 128-бітний ключ (16 байт, 4 × uint32_t) — ARCH.42 |
| `DataType` | `CRYP_DATATYPE_32B` | Endianness: 32-бітний порядок байтів |
| `pKey` | `&aes_key[0]` | RAM-адреса per-device HKDF-derived ключа (завантажується з Protected Flash Sector через `Load_AES_Key()` — 03_06 §2, §Hardcoded AES Key closed via FW.1) |

**Параметри ключа (CoAP-режим, тільки Queen, для batch flush + downlink):**

| Параметр | Значення | Примітка |
|----------|----------|---------|
| `KeySize` | `CRYP_KEYSIZE_256B` | 256-бітний ключ (32 байти, 8 × uint32_t) для AES-256-CBC |
| `pKey` | `&coap_key[0]` | RAM-адреса CoAP HKDF-derived ключа (separate Flash slot, не плутати з LoRa-key) |
| `Algorithm` | `CRYP_AES_CBC` + IV | Динамічна re-init перед flush; restore назад на ECB+128B після |

---

## 📦 2. Структура Зашифрованих Пакетів (Payload Structure)

### 2.1 Soldier → Queen: LoRa Uplink (AES-128-ECB transitional → AES-128-CCM target)

**Поточний режим (transitional після ARCH.42, 2026-05-23):** AES-128-ECB · **Розмір:** 16 байт = 1 AES-блок · **IV:** відсутній
**Цільовий режим (FW.2):** AES-128-CCM · **Розмір:** 30 байтів (wire-rev2.1: header 8B + ciphertext 14B + MIC 8B) — див. §ECB Mode

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
- `GrowthPoints` (byte 10): упакований StatusByte `[PanicFlag:1|Status:2|GrowthPoints:5]` (FW.29-PACK; panic=0 у normal-frame, bits 6..5 status, bits 4..0 growth 0..31)
- `TTL byte` (byte 11): [FW.18b] бітфілд `[thr_invalid:5|TTL:3]` — нижні 3 біти Time to Live (початково 3, panic 5; −1 на hop), верхні 5 — лічильник відкинутих OTA-порогів (wire-дім [`03_01 §1.6`](03_01_Firmware_Lifecycle_and_DMA))
- `FW` (bytes 12-13): Firmware Version ID, big-endian (для OTA targeting)
- `PAD` (bytes 14-15): нульовий padding (резерв, не використовується)

**Emergency TX (EwsAlert / Panic) — `Trigger_Emergency_LoRa_TX()`:**
```
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 0 | Byte 1 | Byte 2 | Byte 3 | Byte 4 | Byte 5 | Byte 6 | Byte 7 |
|       DID (Device ID, 4 байти, big-endian)        |   0    |   0    |   0    | 0xFF   |
+--------+--------+--------+--------+--------+--------+--------+--------+
| Byte 8 | Byte 9 |Byte 10 |Byte 11 |Byte 12 |Byte 13 |Byte 14 |Byte 15 |
|   0    |   0    | PANIC_FLAG_BIT |PANIC_TTL|   0    |   0    |CTR_HI  |CTR_LO  |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

- Byte 7 = `0xFF` → код паніки (максимальна акустична подія)
- Byte 10 = `PANIC_FLAG_BIT` (0x80) → **[FW.29]** однозначний disambiguation panic vs saturated acoustic
- Byte 11 = `PANIC_TTL` (= 5, збільшений TTL для досягнення Queen через більше стрибків)
- Bytes 12-13 = `0x00` — panic НЕ несе firmware-версію (код `panic_payload[]` присвоює лише [0-3]/[7]/[10]/[11]/[14-15], решта zero-init; backend читає firmware_id = 0 для panic-кадрів)
- Bytes 14-15 = **[SEC.10]** `panic_frame_counter` BE (uint16, monotonic + saturating @ 0xFFFF)

**[SEC.10] Frame Counter anti-replay для panic packets (2026-05-03):**

Сторожовий пес панічного каналу до приходу повного FW.2 CCM. Counter інкрементується перед кожним `Trigger_Emergency_LoRa_TX`, упаковується BE у вільні PAD-байти (14..15), персистується у packed `RTC_BKP_DR0[31:16]` поряд з `acoustic_events[7:0]` — **без використання нових RTC слотів** (DR15 залишається вільним). Cold-boot resync через HRNG (range 0x0001..0xFFFF) уникає колізії з ще-не-протухлими Redis nonce-ключами попереднього втілення (probability ≈ 1/65536). На брауноуті `HAL_PWR_PVDCallback` (ARCH.21) теж зберігає packed DR0.

**Backend-сторона:** `TelemetryUnpackerService` детектує panic через `status_byte & PANIC_FLAG_BIT`, читає counter з `pad_data[2..3].unpack1("n")`, виконує SETNX через `Rails.cache.write(unless_exist: true)` з ключем `silken:panic:nonce:{hex_did}:{counter}` і TTL 25 годин. При replay → log warning + Prometheus metric `silkennet_panic_replay_rejected_total` increment + early return (TelemetryLog не створюється, AlertDispatchService не викликається). Counter==0 (legacy firmware без SEC.10) пропускає перевірку — rate-limit на AlertDispatchService рівні залишається активним.

**Не закриває повністю SEC.10:** counter не криптографічно прив'язаний до payload (немає MIC). Bit-flip атака на encrypted byte 10 може створити фальшивий panic flag, але новий counter буде передбачуваний (sequence) → backend SETNX зловить повторення; injection unique-counter packet з валідним AES-блоком майже неможливий (атакеру треба знати per-device LoRa AES-128 key — тоді він уже виграв партію). Повний захист — FW.2 CCM з MIC, ця імплементація — мінімальний life-safety fix до того.

**Шифрування (однаковий алгоритм для обох типів пакетів):**
```c
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)lora_payload,   4, (uint32_t*)encrypted_payload, 1000);
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)panic_payload,   4, (uint32_t*)encrypted_panic,   1000);
```
- Вхід: 4 слова × 32 біти = 16 байт відкритого тексту
- Вихід: 16 байт зашифрованого тексту (1 AES-блок)
- Таймаут: 1000 мс (апаратний модуль зазвичай завершує за < 1 мкс)

---

### 2.2 Queen → Rails: CoAP Batch Uplink (AES-256-CBC + L1 QATT підпис)

**Режим:** AES-256-CBC · **Дві форми payload** (📐 wire-дім, firmware-дзеркало розкладки: `firmware/common/queen_attest.h`):

```
Legacy (L0):    [IV:16][Encrypted Data: N×16]                  довжина % 16 == 0
Підписаний (L1, v2 — [ARCH.54]):
                [ver:1=0x02][queen_unix_ts:4 BE][flush_seq:4 BE]
                [health:8][IV:16][Encrypted Data: N×16][sig:64] довжина % 16 == 1
```

> **[ARCH.54] Health-блок (8 Б, ПІДПИСАНИЙ разом з батчем)** — пульс Королеви: `[uptime_min:u24 BE][cifo_fill][lora_rx_drops][coap_fail][csq][flags]` (бітова розкладка — One-Home `firmware/common/queen_attest.h`; споживач — `UnpackTelemetryWorker#enqueue_envelope_health` → `GatewayTelemetryWorker`). Замінив DID=0-псевдодерево у батчі (те брехало полями і ламало CCM-stride — [`03_02 §7`](03_02_Queen_Gateway_Firmware)); masking-attack закритий конструкцією — health без валідного Ed25519 не існує. **ct = 0 легальний** (empty-flush heartbeat: пульс за тихої години, unpack скипається під конвертом). v1 (0x01, residue 9, `SLKN-QATT1`) **вилучено повністю** — флоту в полі нема, redefine дешевший за дуал-версію.

**L1 Queen-attestation** (рунг драбини довіри — канон [`05_02`](05_02_Proof_of_Growth_Pipeline) «Trust-origin ladder»): Королева підписує батч **Ed25519** (software, Monocypher; сім'я `EDSK` у Protected Flash — §3.1). Encrypt-then-sign: бекенд (`UnpackTelemetryWorker`) верифікує підпис проти зареєстрованого при provisioning `HardwareKey.ed25519_public_key_hex` **ДО** decrypt — жодних padding-оракулів.

- **Повідомлення підпису:** `"SLKN-QATT2" ‖ uid_len:1 ‖ uid ‖ <payload без хвостового sig>` — доменний тег проти cross-protocol reuse (bump разом із форматом — старі вектори не колізують); UID (з CoAP URI-Path) вшито у підпис → батч однієї Королеви не сплайснути в URI іншої.
- **Розрізнення форм** — residue довжини (legacy ≡ 0, підписаний ≡ 1 mod 16): детерміністичне, без magic-вгадування проти випадкового IV. Сім'я не прошита → Queen шле legacy = pre-QATT плата живе без змін (але й без пульсу — heartbeat існує лише attested).
- **Anti-replay:** SHA256(sig) як nonce — **двофазний інтент-маркер (патерн ARCH.45)**: claim `SET NX <sidekiq-jid>` ДО unpack → finalize `"done"` ПІСЛЯ успішного unpack (Redis; Solid-Cache fallback дзеркальний в обох фазах — патерн M2M/S6.1; TTL — `UnpackTelemetryWorker::QATT_NONCE_TTL`). Crash-retry (той самий jid) = **resume**, не replay: однофазний nonce спалювався б на краші unpack'а і губив атестований батч назавжди — Королева звільняє CIFO по ACK 2.04 на enqueue ([`03_02 §4`](03_02_Queen_Gateway_Firmware)), єдина копія = Sidekiq-джоб; чужий jid / `"done"` / легасі `"1"` → reject `attest_replay`. Бонус: Redis timeout-after-effect на claim теж лікується owner-token'ом (retry впізнає свій запис). `ts`/`seq` — observability + майбутній high-water (Queen без RTC, [`03_02 §5а`](03_02_Queen_Gateway_Firmware) — `ts=0` легітимний).
- **Anti-replay residuals (свідомі):** replay після TTL-вікна (строго кращий за L0 «replay будь-коли») · resume після часткового unpack = можливі дублі префіксу чанків, поки ECB-шлях без per-chunk dedup (CCM-flip самоусуває через FC-dedup; разова інфляція замість безповоротної втрати атестованих даних) · DeadSet після `retry: 3` — стеля Sidekiq OSS (ручний retry з UI зберігає jid → resume дотискає батч у межах TTL) · SIGKILL між claim/finalize та split-store вікно (Redis-flap між фазами) — вузькі, на порядки вужчі за закритий crash-window.
- **Невалідний підпис** → drop + `attest_bad_signature` метрика (Grafana-алерт); **підписаний без зареєстрованого pubkey** → обробка як L0 + `attest_no_pubkey` (суворість нічого не дає, поки L0 приймається).
- **Загроза-модель чесно:** L1 доводить gateway-origin (захист від backend-compromise/injection), **не** operator-fraud — то L2 (драбина у [`05_02`](05_02_Proof_of_Growth_Pipeline)).

```
+------------------+------------------+------------------+-----+------------------+
|   IV (16 bytes)  | Encrypted Block 1| Encrypted Block 2| ... | Encrypted Block N|
|  (HRNG-generated)|  (AES-256-CBC)   |  (AES-256-CBC)   |     |  (AES-256-CBC)   |
+------------------+------------------+------------------+-----+------------------+
```

> **[FW.2] CCM-ера батча (INERT за гейтами):** після фліпа записи стають **31-байтними** (air+1, rev2.1) (розкладка — 📐 §2.1 cross-ref для backend, One-Home; білдер `firmware/queen/rx_route.h`) — Королева НЕ розшифровує (сліпий кур'єр, §2.1), MIC верифікує Rails per-DID; один stride на весь батч. Queen-health DID=0 у CCM-батч не пакується (фліп-гейт — [`00_07`](00_07_Action_Plan_Tracker) FW.2). CBC-конверт + L1 QATT-підпис поверх — незмінні.

**Кожен "Encrypted Block" містить один або кілька 21-байтних записів телеметрії** (вирівняних padding нулями до кратного 16; розкладка запису — [`03_01 §8`](03_01_Firmware_Lifecycle_and_DMA) One-Home):

```
21-byte Telemetry Record (Queen→Rails, у батчі перед AES-256-CBC):
+--------+--------+--------+--------+--------+-----------------------------------+
| DID[0] | DID[1] | DID[2] | DID[3] |  RSSI  |   16-байтний ECB-payload block     |
+--------+--------+--------+--------+--------+-----------------------------------+
  bytes 0..3 : DID (Device ID, big-endian)
  byte 4     : RSSI (Queen додає при LoRa-RX — Soldier його НЕ передає)
  bytes 5..20: непрозорий 16-байтний блок телеметрії (розкладка = normal-telemetry
               діаграма §2.2 вище + 03_01 §8 One-Home; поля UID/BioStat/Hash
               з попередньої чорнетки в коді НЕ існують)
```

**CoAP URI:** `PUT /telemetry/batch/<QUEEN_UID>` (queen_uid читається з Flash — Flash-provisioned або `"UNPROV-{HEX}"` через STM32 HW UID)

**Передача:** Зашифрований буфер перетворюється у Hex-рядок та відправляється через `AT+CCOAPSEND` команди до SIM7070G модему.

---

### 2.2а Queen → Rails: Device-Event L1 Uplink (Ed25519, окремий канал) [SEC.21]

**Навіщо окремий канал.** Рідкісні security-події з вузла (canary-trip = спрацював `__stack_chk_fail`, DR0[10]) НЕ є станом і не влазять у телеметрію. Живуть двома шарами (`firmware/common/device_event.h`):

- **Шар 1 (Soldier→Queen, LoRa):** 16B ECB-кадр `0x57` на cluster-ключі — та сама транзишн-довіра, що `0x55/0x56` (control-plane, Королева читає сама). Розкладка: `[0]=0x57 [1..4]=DID [5]=code [6..9]=arg [10]=0x45 'E' [11]=TTL [12..13]=seq [14..15]=vcap`. Солдат шле 3× ПОВЕРХ телеметрії (LoRa-lossy) і гасить DR0[10] по 3-му.
- **Шар 2 (Queen→Rails, CoAP `device/event/<uid>`):** Королева ДЕКРИПТУЄ кадр (щоб упізнати маркер), витягує cleartext-поля і форвардить під **ВЛАСНИМ Ed25519-підписом** — рунг **L1** драбини довіри ([`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)):

```
[ver:1=0x01][queen_unix_ts:4 BE][count:1][records:count×7][sig:64]
record = [did:4 BE][code:1][soldier_seq:2 BE]
підпис Ed25519(EDSK) над:  "SLKN-QEVT1" ‖ uid_len:1 ‖ uid ‖ <body без sig>
```

**Чому L1, а не blind-forward сирого ct.** Rails per-Tree LoRa-ключа (KEYL) не має **у жодній ері** для цього шляху: ECB-ера — Королева знімає LoRa-шар сама (Rails бачить лише CBC-батч); CCM-ера — `0x57` = control-plane cluster **KEYB**, якого Rails не має. Blind-forward + Rails-decrypt дав би key-mismatch → канарка мертва **fail-open**. Королева ж уже тримає plaintext — форвардимо його. **Per-event device-підпис фізично неможливий** (64B у 16B кадр — §554 05_02) → L1 Queen-attest = правильний рівень **назавжди**, L2-Merkle його не торкнеться.

**Домен-тег `SLKN-QEVT1`** (окремий від `SLKN-QATT2`) — canary-підпис не сплайснути в телеметрію-verify і навпаки (cross-protocol reuse guard, той самий інваріант, що QATT). **Механізм спільний з §2.2:** той самий EDSK (`ed25519_secret`), той самий `Ed25519Crypto::SigningService.verify` проти того самого `HardwareKey.ed25519_public_key_hex`-реєстру, той самий `ed25519_ready`-гейт (без EDSK L1 неможливий — canary чекає провіжинингу, не бреше L0). Споживач — `DeviceEventWorker` ([`04_02`](04_02_Business_Logic_and_Services)): verify → SHA256(sig)-nonce (anti-replay — Королевин sig монотонний, на відміну від Солдатового per-boot seq) → per-record `EwsAlert(firmware_canary_trip)`. **Trust L1-observational: НІКОЛИ не money-path** (slash-виключення дзеркалять `firmware_fault`). Best-effort доставка (окремий PUT без retry — Солдат повторює постріл ×3); опційний C-доповнювач (`QATT_HFLAG_CANARY` health-flag як гарантований кластер-early-warning) — YAGNI-резерв ([`00_07`](00_07_Action_Plan_Tracker) SEC.21).

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

### 2.4 Queen → Soldier: OTA LoRa Broadcast (AES-128-ECB)

**Режим:** AES-128-ECB · **Розмір:** 16 байт (LoRa-канал, post-ARCH.42) · **Ключ (CCM-ера):** cluster control-plane **KEYB** (§3.1 двоключова модель; ECB-ера — єдиний спільний `aes_key`). Downlink свідомо БЕЗ MAC/FC — стеля до downlink-wire-ревізії (вона ж активує FW.17, §3.8); OTA-image окремо автентифікований K_ota-HMAC (FW.23, [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)).

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

> ✅ **Post-FW.1 status (2026-05-02) + ARCH.42 update (2026-05-23):** Hardcoded ідентичний ключ **видалено**. Кожен Soldier отримує **унікальний** per-device LoRa AES-128 ключ (16 байт), а Queen додатково отримує AES-256 CoAP ключ (32 байти) — обидва через HKDF-SHA256 деривацію з `PROVISIONING_MASTER_KEY` під час factory provisioning. Ключ зберігається у **Protected Flash Sector** (`FLASH_KEY_ADDR`, RDP Level 1/2-захищений) і завантажується у RAM функцією `Load_AES_Key()` при boot. Деталі деривації — 03_06 §2 HKDF Key Derivation Protocol Design; backend mirror — `HardwareKey#aes_key_hex` (AR Encryption non-deterministic, conditional length: 32 hex для Tree LoRa, 64 hex для Gateway CoAP).

**Двоключова модель LoRa (✅ FW.2 гейт (в), founder 2026-07-03; 📐 дім моделі).** LoRa-шар CCM-ери має ДВА ключі з розділеними осями використання — session (money-path, per-device) та cluster control-plane (broadcast-структурний, клас K_ota):

| Параметр | Session KEYL (Tree) | Control-plane KEYB (Tree RX + Queen) | CoAP-ключ (Queen only) |
|----------|---------------------|--------------------------------------|------------------------|
| **Носій wire** | телеметрія + panic (30B CCM uplink rev2.1) | увесь downlink-broadcast (`0x99/0x9A/0x9B/0x9C/0x9D/0x9E`) + uplink-запити `0x55/0x56` (16B ECB) | CoAP batch/downlink (AES-256-CBC) |
| **Тип зберігання** | Protected Flash стор. 124, magic `"KEYL"` = `0x4B45594C` | Tree: стор. 125, magic `"KEYB"` = `0x4B455942` (`FLASH_BCAST_KEY_ADDR` = K_ota+40, dw-align); **Queen: її KEYL-слот несе KEYB-значення** (єдиний LoRa-ключ Королеви) | Protected Flash (окремий slot), magic `"KEYC"` = `0x4B455943` |
| **Розмір** | **128 біт (16 байт)** — ARCH.42 | 128 біт (16 байт) | 256 біт (32 байти) |
| **Захист** | RDP Level 1/2 — див. §3.3 | Те саме | Те саме |
| **Ротація** | Hash-Ratchet §3.8 (ротує ЛИШЕ session; активація gated) — [`00_07` — FW.17](00_07_Action_Plan_Tracker) | **re-provision only** (клас K_ota; Dual-Key Grace незастосовний — grace підтверджується uplink'ом, якого broadcast-ключ не має) | Re-provision (SEC.3) |
| **Унікальність** | **Per-device**: HKDF(`PROVISIONING_MASTER_KEY`, salt=`device_uid`, info=`"silken-aes-128-lora-key"`) | **Per-cluster**: HKDF(master, salt=`"cluster:<id>"`, info=`"silken-aes-128-broadcast-key"`) — `HardwareKeyService.derive_broadcast_key` | HKDF(master, salt=`device_uid`, info=`"silken-aes-256-device-key"`) |
| **Завантаження у RAM** | `Load_AES_Key()` → `aes_key[4]`; у CCM-еру session живе ЛИШЕ в CCM-скоупі (`MX_CRYP_Init_CCM` ставить його явно, Restore повертає амбієнт) | `Load_Broadcast_Key()` → `bcast_key[4]` = амбієнтний ECB-ключ (гейт `FW2_CCM_ENABLED`); KEYB-слот порожній → fail-open fallback на KEYL (bench-плата до KEYB-ери, прапорець `bcast_key_is_fallback`) | `Load_AES_Key()` → `coap_key[8]` (динамічне re-init для CoAP) |

> **ECB-ера (сьогодні, до фліпа):** KEYB не читається (за гейтом), працює односхемна модель — один `aes_key` на все, кластер де-факто на спільному значенні (чесність-блок §Hardcoded вище). Двоключовість вмикається фліпом `FW2_CCM_ENABLED` разом з усім CCM-трактом.

**Поточний код ініціалізації (`firmware/soldier/main.c` + `firmware/queen/main.c` після ARCH.42):**
```c
// Boot-time RAM-mirror; реальне значення зчитується з Flash у Load_AES_Key()
uint32_t aes_key[4]  = {0};   // 16 bytes — LoRa AES-128 (Soldier + Queen)
#ifdef QUEEN
uint32_t coap_key[8] = {0};   // 32 bytes — CoAP AES-256 (тільки Queen)
#endif

// У main() перед MX_CRYP_Init():
Load_AES_Key();  // reads from FLASH_KEY_ADDR, validates magic "KEYL",
                 // populates aes_key[4] in RAM
// Queen додатково: Load_CoAP_Key() ("KEYC" → coap_key[8]; м'який fallback — нулі)
// та Load_Ed25519_Seed() ("EDSK" → сім'я голосу L1 QATT, §2.2; відсутня → legacy-батчі).
// Word→BE-байти за FW.30-конвенцією (дзеркало Load_Lorenz_Seed) — наївний memcpy
// на LE Cortex-M4 перевернув би слова, і pubkey не зійшовся б із зареєстрованим.
```

> 🚫 **Архітектурний baseline:** "ідентичний на ВСІХ вузлах" — **історична форма §Hardcoded AES Key**, закрита FW.1. Цей блок документа явно зберігає згадку як warning для аудиторів, що інспектують стару прошивку до FW.1. При відсутності magic `"KEYL"` у Flash (raw чіп з фабрики) — `Load_AES_Key()` відмовляє у boot і enter'ить infinite reset loop (захист від випуску партії без provisioning). Цей invariant перевіряється у `firmware/test/test_soldier_logic.c::test_load_key_unprovisioned_flash_error`.

> ⚠️ **Audit-trail (історичний §Hardcoded AES Key):** До FW.1 перші 4 слова ключа збігалися зі стандартним тестовим ключем AES-128 з FIPS-197 (Appendix B). Поточна верифікація — `Security::WeakKeyDetector` (§3.1а нижче) + boot-time HKDF derivation гарантують, що цей вектор більше **не може потрапити** у production. Якщо інженер бачить hardcoded `0xXXXXXXXX` константи у будь-якій робочій копії — це означає, що FW.1 patch був відкочений; **stop and escalate**.

#### 3.1а Boot-time guard: `Security::WeakKeyDetector` (SEC.9 mitigation)

Щоб історична регресія FIPS-197 Appendix B не повторилась тихою підстановкою тест-вектора у `PROVISIONING_MASTER_KEY` під час майбутньої ротації, додано автоматичний детектор слабких master-ключів:

- **Сервіс:** `app/services/security/weak_key_detector.rb` (`Security::WeakKeyDetector.detect(value, hint:)`).
- **Boot-time guard:** `config/initializers/master_key_strength_check.rb` — у `RAILS_ENV=production` (включно з canopy) перевіряє `ENV["PROVISIONING_MASTER_KEY"]` і **raise'ить `SecurityError`** до запуску додатку, якщо ключ співпадає з відомим патерном.
- **Bypass:** `SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK=1` для аварійного rescue-boot (логується гучно, не для рутини).
- **Тест/dev:** перевірка пропускається — `spec/rails_helper.rb` піннить детермінований fixture (`silken-net-test-master-key-32b!!`), який сам по собі позначений у блок-листі.

**Що блокує детектор:**

| Категорія | Приклади |
|----------|---------|
| Публічні тест-вектори AES | FIPS-197 Appendix B / C.1–C.3, NIST SP 800-38A F.5 (AES-256 CTR), RFC 3686 §6 vector #1 |
| Публічні HMAC тест-вектори | RFC 4231 Test Cases 1 / 3 / 6-7 (20×0x0b, 20×0xaa, 131×0xaa), FIPS 198-1 §A.1 |
| Префіксні співпадіння | 32-байтний master, перші 16 байт якого = опубліковане 16-байтне FIPS значення (історична форма BLOCKER-а) |
| Виродженні патерни | all-zero, all-0xFF, single-byte repeat, монотонна послідовність (Δ=±1) |
| Низька ентропія [SEC.9] | короткий повторюваний блок (≤8 байт — напр. `deadbeef`×8) або <4 різних байт-значень (generic-евристика, останній прохід; CSPRNG-ключ ~30 distinct → 0 false positives) |
| Плейсхолдери | `CHANGEME`, `placeholder`, `your-master-…`, `<your-key>`, `TODO`, `secret-here`, сам spec-fixture |

Детектор перевіряє і raw-bytes, і hex-decoded, і base64-decoded інтерпретації — той самий тест-вектор не може непомітно зайти через "інший спосіб набору" (історично у репозиторії одне місце мало raw bytes, інше — hex).

**Як ротувати master-ключ (operator runbook):**

1. Згенерувати: `bundle exec ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'` (або апаратний HRNG).
2. **Локальна перевірка перед записом у vault:**
   ```bash
   bundle exec ruby -rdotenv -e '
     require_relative "app/services/security/weak_key_detector"
     k = STDIN.read.strip
     r = Security::WeakKeyDetector.detect(k, hint: "PROVISIONING_MASTER_KEY")
     abort "WEAK: #{r}" if r
     puts "OK"
   ' < /path/to/new_key.txt
   ```
3. Записати у Bitwarden / 1Password / Kamal secrets (див. [`06_04`](06_04_Secrets_Checklist)).
4. Re-deploy — initializer перезапустить guard з боку production.

**Сервіс автоматично запускається при кожному production boot — будь-яка ротація, яка пройшла повз runbook, буде заблокована до старту HTTP сервера.** Це й закриває SEC.9 🤖.

### 3.2 Secure Element (ATECC608B) — після ARCH.42

> ⚠️ **SUPERSEDED → §3.7 (SEC.6 RESOLVED 2026-06-07):** SE = **NXP SE050** (true-DePIN «голос дерева» — non-extractable Ed25519), НЕ ATECC608B (реверс рішення 2026-05-23). Нижче (§3.2 + 03_06 §1 Гілка B) лишено як **legacy ATECC provisioning-патерн** — factory-integration механіка **reusable для SE050**, тож не видаляється; чинне рішення, ціна, slot-map, ladder — **§3.7**.

> 🎯 **ARCH.42 Variant B (2026-05-23) — legacy, SUPERSEDED → SE050 (§3.7):** початковий вибір був ATECC608B Microchip (~$0.85/unit @ 10k MOQ) як єдиний SE для (а) LoRa AES-128 ключ у Slot 0, (б) ECC P-256 device identity у Slot 1, (в) device cert у Slot 2, (г) OTA HMAC-SHA256 ключ у Slot 3. AES-128 — апаратний maximum ATECC608B. **Чинне рішення — NXP SE050** (non-extractable Ed25519 «голос дерева», SEC.6 RESOLVED — §3.7); ATECC slot-провіжининг-патерн нижче лишено як reusable для SE050.

Поточна Гілка A (RDP Level 2 + Protected Flash) залишається активною baseline для pilot/<1000 unit deployments. Гілка B (ATECC608B) активується для mass production > 10k unit та urban deployments — див. 03_06 §1 Гілка B та §3.7.

```
Factory Flashing (поточна Гілка A, TRL 6/7 — pilot ≤ 10k):
  Rails Backend → POST /provisioning/register → {device_uid}
                  (Zero-Trust: aes_key НЕ повертається у відповіді)
  STM32 ← HKDF(PROVISIONING_MASTER_KEY, device_uid, "silken-aes-128-lora-key") → aes_key[4]
  ST-Link/SWD → Flash aes_key до Protected Sector → RDP Level 2 Lock

Цільова Гілка B (post-bench, mass production > 10k — ARCH.42 enabler):
  ATECC608B Slot 0 (AES-128) → ключ ніколи не покидає кремній SE
  STM32WLE5JC ↔ ATECC608B через I²C (PB6/PB7) → atcab_aes_encrypt() для LoRa CCM
  Defense-in-depth: ATECC data zone lock + STM32 RDP Level 2 → DPA/EM/glitch resilient
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

### 3.4 Стратегія Масового Виробництва (Factory Flashing Pipeline) — винесено в 03_06

> Повна підсистема **provisioning ключів і фабричного флешингу** виокремлена в окрему канон-сторінку [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning) (00_06 §4): фабричні Гілки A/B (Protected Flash / Secure Element) → 03_06 §1; HKDF-деривація per-device AES-ключів → 03_06 §2; Lorenz K_seed (SEC.11) → 03_06 §3; OTA image authentication (FW.23 HMAC dual-gate) → 03_06 §4; operations-security threat model заводського каналу (SEC.3) → 03_06 §5.
>
> Тут (03_05) лишаються крипто-режими (§1–§2), джерело ключа при старті + RDP (§3.1–§3.3), SE050 (§3.7), ротація ключа (§3.8), генерація IV (§4) та аудит/PQC (§6–§10).

### 3.5 Режим Транспортування — Shipping Mode (✂️ не потрібен — SEC.4 RESOLVED 2026-07-03)

**Рішення [SEC.4]:** shipping-mode-компонента у BOM Солдата **немає** — питання «чи потрібен взагалі» (воно передувало вибору pull-tab vs геркон) вирішено фізикою проти компонента:

1. **У коробці нема джерела** (zero-grid EBFC) — захищати можна лише factory-заряд supercap.
2. **Factory-заряд не переживає логістику незалежно від вимикача:** власний витік EDLC 1–2 µА ([`02_03 §12.1`](02_03_BQ25570_MPPT_Nano_Power)) з'їдає робоче вікно 5.5→3.4 В (≈1 Кл) за ~6–8 діб; вимикач відрізає лише MCU-споживання того самого порядку → максимум подвоює вікно. Преміса «лежить у коробці тижнями» мертва обабіч вимикача.
3. **Cold-start з 0 В — штатний дизайн-шлях, не аварія:** EBFC ≥500 мВ > 330 мВ порогу BQ25570 ([`02_03 §1`](02_03_BQ25570_MPPT_Nano_Power)); ризик R_int-осциляції має власну драбину мітигацій (HW.13, [`02_03 §1.5`](02_03_BQ25570_MPPT_Nano_Power)), якої shipping-mode не торкається.
4. Стара преміса «прокинеться від вібрації у коробці» — stale: wake-джерело = RTC WUT + Vcap-енергогейт ([`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA)), вібраційного wake не існує.
5. **Ціна для 20–25-річного вузла ненульова:** зайвий послідовний елемент power-path; pull-tab до того ж проколює герметизацію (potting — [`02_02 §3.4`](02_02_Blind_Mate_Pogo_Pin_Interface)).

**«Перший вдих» (наратив/UX)** живе краще без транспорт-компонента: якщо pilot захоче same-day перший TX — підзарядка в день інсталяції через наявний pogo-інтерфейс ([`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface)): інструмент монтажника подає «сильне дерево» на штатні піни, BQ25570 сам заряджає VSTOR за хвилини. Нуль BOM, працює за будь-якої тривалості логістики.

**Decision-record (на випадок reopen):** дефолтом був би **pull-tab** (one-shot, не спуфиться магнітом, дешевший); геркон (Hamlin 59140-1-T-00-A + N52 ∅6×3 мм) — **лише** з latching first-boot: геркон гейтить тільки перший boot, далі софт латчить power-on (set-and-hold GPIO/load-switch) і ігнорує геркон, інакше **magnet-DoS** — зловмисник сильним магнітом глушить security-сенсор (реальний вектор проти anti-illegal-logging вузла). Latching-патерн «one-shot arm замість continuous power-cut» — reusable інсайт для будь-якого магнітного інтерфейсу на security-пристрої.

**Reopen-умови (усі одночасно):** bench показує патологічний EBFC cold-start (R_int > 12 кΩ без мітигацій HW.13) × логістика ≤ тижня (заряд частково доживає) × pilot вимагає same-day TX — і навіть тоді перший кандидат = pogo-підзарядка вище, не транспорт-вимикач.

---

### 3.6 Процедура активації RDP Level 2 (необоротна) 🤖

**Cross-ref:** [`00_07` — SEC.2](00_07_Action_Plan_Tracker), §3.3 «Апаратний Захист Flash».

> ⚠️ **Активація RDP Level 2 — одностороння, незворотна дія.** Після `Apply` чіп фізично втрачає SWD інтерфейс назавжди. Цю процедуру виконують **тільки** після того, як OTA-пайплайн повністю верифікований у полі.

**Pre-flight checklist (обов'язково ДО натискання Apply):**

- [ ] OTA flow end-to-end протестований: `OtaPackagerService` → CoAP downlink → Queen broadcast → Soldier Flash write → magic check `0x45544952` ("RITE") → reboot → нова прошивка живе у `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`.
- [ ] OTA verification: щонайменше **2 успішні цикли** оновлення на тому ж пристрої (не лише бенчмарки).
- [ ] OTA rollback тестований: якщо новий bytecode falls back до embedded `lorenz_bytecode[]` при corrupt magic.
- [ ] **[SEC.20] Anti-rollback persist верифікований як durable-gate:** replay СТАРОЇ валідно-підписаної версії → REJECT (Flash-KV hiwater `0x15` строго `>`); 3×vm_error → fallback-erase → baseline + `reverted`-звіт у байтах 12..13 долітає до Rails (`EwsAlert firmware_reverted`); re-issue спаленої N → REJECT, N+1 → APPLY (RUNBOOK §2.5 SEC.20-половина). Після L2 це ЄДИНИЙ захист від downgrade — SWD-reflash мертвий.
- [ ] Provisioning HKDF flow завершено (§Hardcoded AES Key mitigation): унікальний `aes_key` записано в protected sector, master_key генерується HRNG (не FIPS-197 test vector).
- [ ] FW.2 (CCM) integrated: інакше після RDP-2 вже не можна «полагодити» AES-ECB вразливість через SWD reflash.
- [ ] Watchdog (IWDG) тестовано: якщо firmware зависає, IWDG перезавантажує MCU без SWD (SEC.8 §ECB Restoration Race у цьому доку ✅).
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

> ⚠️ **OTA латає ЛИШЕ mruby-байткод, не C-firmware [SEC.2].** `Flash_Write_Contract` (`firmware/common/flash_ota.h`) пише contract-сторінку (magic «RITE» @ `MRUBY_CONTRACT_FLASH_ADDR`) — тобто OTA оновлює **BioContract-байткод**, а НЕ C-прошивку (radio stack, AES, main loop). Після RDP L2 баг у C-коді **невиправний** (SWD off, OTA не дістає C). Чекліст-рядок «OTA rollback → fallback на embedded `lorenz_bytecode`» стосується **байткоду**, не C-recovery — це різні відмови. Висновок: RDP L2 = **остаточне заморожування C-прошивки** → активувати лише коли C-код доведений у полі на L1-партії місяцями (rollout-таблиця нижче) + FW.2 інтегровано.

**Поетапний rollout (рекомендовано):**

| Етап | RDP Level | Кількість | Призначення |
|------|-----------|-----------|-------------|
| Прототип / R&D | Level 0 | ~50 | Розробка, дебаг, SWD доступ |
| Field pilot (пілотний ліс) | Level 1 | 100–500 | Field sanity, OTA verification, recovery still possible |
| Mass production batch | Level 2 | 10,000+ | **Тільки** після ≥3 місяців stable OTA на Level-1 партії |

**Документ-tracker:** після кожного batch активації — оновити [`00_07`](00_07_Action_Plan_Tracker) SEC.2 (👤 — secrets / process).

---

### 3.7 Secure Element — NXP EdgeLock SE05x, baseline SE051C2 (ARCH.42 + SEC.6 + true-DePIN)

**Cross-ref:** [`00_07` — SEC.6](00_07_Action_Plan_Tracker), [`00_07` — ARCH.42](00_07_Action_Plan_Tracker), [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker) — **SE = SE05x (SEC.6 RESOLVED 2026-06-07; baseline SE051C2 — founder 2026-07-02)**, §3.2 «Secure Element після ARCH.42».

> ✅ **SE = NXP EdgeLock SE050 (SEC.6 RESOLVED 2026-06-07; supersedes the 2026-05-23 ATECC608B pick):** коли SilkenNet зобов'язався дати деревам **власний криптографічний голос** (true-DePIN: дерево підписує свої дані ключем, що не покидає кремній і якого не підробить навіть оператор), SE-частина мусила вміти **non-extractable Ed25519** (крива peaq/Solana). **ATECC608B (P-256 only) цього не вміє** → SE = **SE050** (Ed25519/EdDSA + AES-128/256 + monotonic counters + secure storage — суперсет ATECC). Trust-напрям + ladder — у SEC.6 ADR нижче.
>
> ✅ **Baseline-uplift усередині SE05x-family (founder 2026-07-02): baseline = SE051C2, SE050C2 = fallback.** SE-family рішення (SEC.6) стоїть; уточнено покоління: SE051 = та сама кремнієва платформа (струми/корпус HX2QFN20/I²C 0x48/T1oI2C — **ідентичні**, datasheet-verify нижче) + superset зверху: **AES-CCM/GCM on-chip** (наш FW.2-wire нативно; SE050 має лише CBC/ECB/CTR) · **SEMS Lite** польова applet-оновлюваність (для 20–25-річного пристрою = страховка; security-upgrades частково commercial-agreement) · **PERSO** applet (видалення невикористаних crypto-модулів → credential-пам'ять 45→101 kB) · TRNG NIST SP800-90B · IEC62443. Міграційна вартість = 0 (прод/залізо відсутні), спільний footprint → перемикання SE051↔SE050 безболісне до BOM-freeze. Eval-пара: SE051-кіт + OM-SE050ARD-E companion.
>
> **AES-128 для LoRa лишається — але це тепер ВИБІР, не constraint:** ATECC мав HW-максимум 128; SE050 вміє 128/256. Тримаємо **AES-128-CCM** свідомо — golden-standard constrained-IoT (LoRaWAN/Zigbee/Thread/BLE), сумісність з LoRaWAN-fallback (ARCH.34) і **freeze-contract FW.2** (28-byte CCM packet, wire-rev2). CoAP-магістраль Queen↔Rails — AES-256-CBC (ключ у Queen Protected Flash, не в SE). **ARCH.42 AES-128-рішення СТОЇТЬ — змінилась лише SE-частина (ATECC→SE050).** Глобальний AES-128-патч (ARCH.42) чинний: `CRYP_KEYSIZE_128B`, `HardwareKey.aes_key_hex` (Tree=32 hex / Gateway=64 hex), HKDF info `"silken-aes-128-lora-key"`.
>
> **Чому НЕ ATECC (реверс рішення 2026-05-23):** ATECC обрали за ціною ($0.85 vs SE050 ~$2.40–3.25) під припущення **кастодіального** trust. True-DePIN перевертає логіку: ECDSA-рушій ATECC — **P-256 (secp256r1)**, не збігається з жодним ланцюгом (EVM=secp256k1, Solana/peaq=Ed25519) → не може тримати голос дерева. Ціна (founder: не проблема) поступається vision. **SE050 datasheet-verify** (Ed25519/EdDSA + monotonic counters + AES-128) → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker).

> ✅ **SEC.6 ADR (2026-06-07) — SE050 soft-freeze + true-DePIN ladder.**
>
> **Soft-freeze:** SE050 footprint + I²C на PCB зараз, **DNP** (do-not-populate, як LTC3108 — [`02_01`](02_01_Hardware_Architecture_and_BOM) BOM п.13); populate на mass (>10k) post-FW.2. Пілот (≤100 / <10k) = Гілка A (RDP L2, канон-мінімум 03_06 §5). Асиметрія необоротності (B→A неможливо config-lock; A→B = PCB-респін) → закласти footprint = low-regret; **не** закласти = найдорожча помилка.
>
> **True-DePIN ladder («голос дерева»):** L0 custodial → L1 Queen-attest → L2 per-tree (SE050 Ed25519 + Merkle, energy-gated). Повний ladder (рунги/гейти/статус/енергобюджет) — канон [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline). §3.7 володіє лише SE/крипто-частиною (Slot-0 AES, Slot-1 Ed25519 keygen).
>
> **Що SE050 дає / межі:** дає **голос** (non-extractable Ed25519 = origin) + AES-128 tamper-storage (LoRa-ключ) + монотонні лічильники (FW.2 nonce + panic) + anti-clone serial + SHA/HMAC OTA. **НЕ замінює** ЗВТ-метрологію (точність/legal — STK.5) і slashing (економічний ризик — [`05_05 §3`](05_05_Slashing_and_Risk_Policy); ⚫ `operator-bond`/BIZ.13 відкликано ⚖️ 2026-08-24, розбір — [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)). Голос + точні «вуха» + skin-in-game = довірений RWA.
>
> **Усі залишкові кроки (docs/firmware/code/honesty/eval-kit/L1-L2) занесено в** [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker). Cross-ref [`00_07` — SEC.6](00_07_Action_Plan_Tracker), [`00_07` — ARCH.43](00_07_Action_Plan_Tracker), [`00_07` — E.60](00_07_Action_Plan_Tracker).

**Контекст:** навіть з RDP Level 2, key extraction теоретично можливий через **side-channel attacks** (DPA, EM analysis) або **fault injection** (voltage/clock glitching). Для batches > 1000 одиниць — це attractive target. Виділений Secure Element зберігає ключ у tamper-resistant ASIC з вбудованим detection.

> ⚠️ **Нижче (§3.7 integration detail) — ATECC-legacy (2026-05-23), залишене як патерн provisioning-послідовності + історичне порівняння.** SE = **SE050** (callout угорі, SEC.6 ADR). SE05x-конкретика — object-model замість 16 slots, `Se05x`/`sss` API замість `atcab_*`, on-chip Ed25519 keygen, latency/power/footprint — при eval-kit + datasheet-verify → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker).

**Кандидат (legacy): Microchip ATECC608B**

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
| 1 | **Ed25519 private (SE050)** | **Голос дерева** — device-held non-extractable ключ, що підписує власну телеметрію (L2, Merkle-корінь — E.60); та сама крива покриває peaq/Solana DID-підпис. SE050 генерує keypair **на чипі**, експортує лише pubkey (backend не знає private → непідробно). Раніше P-256 (ATECC) — не міг (інша крива) | ❌ never | On-chip keygen (factory) |
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
// Затримка: ~1.5 мс per block (vs ~10 µs HAL_CRYP). MCU лишається awake весь I²C-раунд.
// Чи прийнятно — залежить від ролі SE (per-packet vs provisioning-only), див. trade-off нижче
```

**Latency impact:** ATECC608B AES-ECB ~1.5 мс/блок vs ~10 µs MCU HAL_CRYP. За **енергією** на один 16-байтний LoRa пакет — нехтовно (числа нижче), але це тримає MCU awake ~1.5 мс/пакет замість ~10 µs — одна з осей trade-off «per-packet vs provisioning-only» (підрозділ нижче). Для CBC batch (50 × 16 байт = 800 байт) — додаткові ~75 мс на flush — прийнятно (CoAP flush триває кілька сек у будь-якому разі).

**Power impact** (cross-check проти канонічного Сценарію C, [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power) / дзеркало [`02_01 §2`](02_01_Hardware_Architecture_and_BOM) — active НЕ блокер, sleep-floor БЕЗ гейта перевертає баланс):
- **Active** (1.5 мс): 14 мА × 3.3 В = 46 мВт → ~69 мкДж/пакет на VOUT (~79 мкДж з VSTOR, η_buck 0.88). Проти Сценарію C: **≈0.3% LoRa-TX** (+14 dBm SF9, 21.8 мДж на VOUT) і **≈0.2% повного active-циклу** (33.7 мДж); у годинному вимірі (1 TX/1.77 год) ≈0.04 мДж/год ≈ 3% запасу Сценарію C (+1.4 мДж/год). Проти 0.47 F EDLC (≈7 Дж) — не «вбивця іоністора». Per-packet active-енергія SE **мала** — і саме тому вона **не** головний критерій вибору ролі (див. підрозділ нижче). ⚠️ Не рахувати % проти «TX ~39 мДж» — то E_TX @ +22 dBm зі *списаного* сценарію ([`02_03 §9.4`](02_03_BQ25570_MPPT_Nano_Power)).
- **Sleep: 150 нА — НЕ нехтовно** (інверсія попередньої подачі, що спиралась на застарілий бюджет ~1.5 мкА): у канонічному Сценарії C (300 нА RTC-only) always-on SE = 150 нА × 3.3 В / η_buck 0.50 (нанострумовий режим) ≈ **3.6 мДж/год з VSTOR — більше за весь запас Сценарію C (+1.4 мДж/год)** → баланс −2.2 мДж/год, supercap повільно розряджається. **Вимога-висновок:** SE сидить за load-switch гейтом (патерн TPS22860, як BME280 — [`02_01 §3.4`](02_01_Hardware_Architecture_and_BOM)); живлення лише в active-вікні. Сумісно з обома ролями: per-packet вмикає SE на кожен wake, provisioning-only — лише при ротації/фабриці. З гейтом sleep-внесок ~0.
- Числа — ATECC608B (порядок величини); **SE050 — paper-verified 2026-07-02** (таблиця datasheet-verify нижче): active той самий клас (AES-coproc 6.5 мА; PK/Ed25519 14.4 мА), але **сон СУТТЄВО гірший за ATECC-проксі — Deep-Power-Down 3–5 µA (НЕ 150 нА, ~20–30×)**, PD-I2C 450 µA → інверсія-висновок вище ПІДСИЛЮЄТЬСЯ: навіть DPD (≈10–16 µВт) з'їдає запас Сценарію C, load-switch = **повне зняття живлення**, не DPD-надія; головне eval-питання стає **cold-boot заряд** (датащит його не специфікує). Silicon-confirm при eval-kit ([`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker)).

**Footprint (PCB):**
- UDFN-8: 2×3 мм
- SOIC-8: 4×5 мм
- I²C: 2 GPIO (PB6/PB7) + 2 pull-ups (4.7 kΩ × 2)
- Загалом: ~3% PCB area для Soldier (KiCad layout у HW.9)

**Роль SE у LoRa-крипті: per-packet AES vs provisioning-only — trade-off [SEC.14 — ✅ RESOLVED 2026-07-03, §🗄️]**

> Це уточнення *всередині* Варіанту B, **не** перегляд ARCH.42. ARCH.42 зафіксував *AES-128-ключ у ATECC608B Slot 0*; окреме питання — *хто виконує шифрування кожного пакета*: сам SE щопакета, чи вбудований radio-AES STM32 з ключем у RDP-Flash — вирішене (Статус нижче: **provisioning-only**); аналіз залишено як обґрунтування.

Решта §3.7 (API sketch, latency/power) неявно припускає **per-packet ATECC AES** (`atcab_aes_encrypt()` на кожен LoRa-кадр). Це не єдиний шлях, і попередня подача «1.5 мс нехтовно / +0.1% ✅» приховувала справжню вісь. Енергія тут — хибний слід (вона мала з обох боків). Реальна вісь:

| | **Варіант B (поточний неявний): per-packet ATECC AES** | **Role-split: built-in AES + ATECC provisioning-only** |
|---|---|---|
| LoRa session-ключ живе | у ATECC Slot 0, **ніколи не залишає кремній SE** | у STM32 RDP-Flash (рівень захисту Гілки A для *цього* ключа) |
| Шифрування пакета | `atcab_aes_encrypt()` через I²C, ~1.5 мс, MCU awake весь раунд | вбудований radio-AES STM32WLE5JC, ~10 µs, inline |
| Роль ATECC | весь streaming AES **+** identity/attestation | **лише provisioning**: ECDH keygen, master/identity (Slot 1), device cert (Slot 2), OTA HMAC key (Slot 3), P-256 device-cert (НЕ peaq/Solana Ed25519) |
| Сильна сторона | LoRa-ключ DPA/EM-стійкий *by design* | SoC-AES створений саме для inline-LoRa; менше I²C failure-modes; latency ~10 µs |
| Ціна | +1.5 мс MCU-awake/пакет на вузлі, що спить 99% часу; +1 шина, що може відмовити | LoRa session-ключ не захищений на рівні SE (master/identity лишаються в ATECC) |

**Чому role-split легітимний:** уся цінність ATECC — «ключ не залишає ASIC», що *змушує* робити AES всередині SE. Якщо натомість прийняти, що LoRa session-ключ живе у RDP-Flash (Гілка-A рівень для одного цього ключа), то вбудований AES STM32 — швидший та ідіоматичний (radio-integrated CRYP саме для inline-LoRa), а ATECC робить те, у чому незамінний: асиметрику + tamper-resistant identity + provisioning. Per-device HKDF (03_06 §2) гарантує: екстракція LoRa-ключа з одного вузла **не** компрометує мережу.

**Чому per-packet (Варіант B) теж defensible:** для urban / high-value розгортань, де фізичний доступ до вузла ймовірний, tamper-resistance *самого LoRa-ключа* може бути вартий 1.5 мс. Це рішення про threat model, а не технічна необхідність.

**FW.2-CCM зміщує дефолт ще далі в бік provisioning-only:** trade-off вище зважено в ECB-рамці (`atcab_aes_encrypt`, ~1.5 мс/блок). FW.2 переводить inline-шлях на **AES-128-CCM** (`CRYP_AES_CCM`) — режим, для якого radio-AES SoC і створений (один inline-прохід, апаратний). Ганяти кожен CCM-кадр через I²C у SE per-packet — **важче** за ECB-число вище (CCM = encrypt + CBC-MAC, два проходи + nonce/MIC-менеджмент через шину). **Datasheet-verify 2026-07-02 радикалізує це до факту: SE050 ВЗАГАЛІ НЕ МАЄ CCM/GCM on-chip** (DS Rev 3.3 Table 2 «AES Modes: CBC, ECB, CTR») — per-packet FW.2-CCM через SE050 = не «повільніший виклик», а **композиція кількох APDU** (CTR-encrypt + CMAC) власноруч. Тобто прихід CCM не просто лишає built-in AES ідіоматичним, а **підсилює** provisioning-only-дефолт уже не смаком, а апаратним фактом; per-packet SE лишається опцією лише для urban/high-value threat-model (і там чесніше дивитись на **SE051** — applet 7.x має CCM/GCM on-chip).

**Статус:** SEC.6 (чи заводити SE + який) → **RESOLVED 2026-06-07: SE = SE05x, soft-freeze + true-DePIN ladder (ADR угорі §3.7; baseline SE051C2 — callout 2026-07-02)**. SEC.14 (роль *per-packet* vs *provisioning-only*) → **RESOLVED 2026-07-03 (founder): provisioning-only = design-default** для forest-baseline. Вирішальні осі — СЕ-агностичні (тримаються і з CCM-on-chip SE051, коли APDU-композиційний аргумент розчинився):

1. **Load-switch-інверсія** (Power impact вище): per-packet = cold-boot SE щоциклу, а cold-boot заряд датащитом **не специфікований** — незв'язаний невідомий на найтугішому бюджеті системи; provisioning-only тримає SE знеструмленим у steady-state.
2. **FW.17-ратчет** рахує K_{v+1} на MCU (§3.8 freeze-contract, golden-KAT обабіч) → session-ключ **MCU-резидентний за дизайном**; per-packet вимагав би переносити ратчет у SE05x або ключ однаково транзитить I²C.
3. **Двоключова модель FW.2 (в)** (§3.1) уже обмежила blast-radius: KEYL per-device HKDF → злам 1 вузла ≠ мережа.
4. **Латентність/ідіом:** inline radio-AES ~10 µs vs мс-клас T1oI2C APDU-раунд (MCU awake увесь раунд) на вузлі, що спить 99%+ часу.
5. **L2-форма:** SE = орган **ідентичності** (рідкісні Ed25519-підписи: тижневий Merkle-корінь, provisioning, атестація), CRYP = орган потокової симетрики.

**Наслідки рішення:** KEYL лишається у Protected Flash в **обох** фабричних гілках ([`03_06 §1`](03_06_Factory_Flashing_and_Key_Provisioning) — Гілка B стає «Гілка A + identity-chip»; graceful degradation: мертвий SE ≠ мертва телеметрія); SE Slot 0 (AES) = **reserved**, populate лише в задокументованому **urban/high-value варіанті** (per-packet; з SE051-baseline CCM on-chip він нативний); ARCH.42-формула «AES-128-ключ у Slot 0» щодо LoRa session-ключа **superseded** цим рішенням (сам вибір AES-128 — стоїть). Eval-residual звузився з «обрати роль» до **silicon-confirm** чисел обраної ролі (cold-boot заряд, T1oI2C латентності) → SE050-MIGRATION. Cross-ref [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker) (SEC.14 — §🗄️ архів).

**Розглянуті SE-чипи (історичне порівняння; SE050 обрано — true-DePIN, ADR угорі §3.7):**

| Чіп | Виробник | Особливості | Висновок |
|-----|----------|-------------|----------|
| **SE050** | NXP | Ed25519/EdDSA + AES-128/256 + monotonic counters + secure storage (суперсет ATECC) | ✅ **Обрано** (SEC.6) — єдиний з non-extractable Ed25519 = голос дерева |
| **ATECC608B** | Microchip | Зрілий ecosystem, ESP/STM32 libraries, AWS IoT default; **ECC = P-256 only** | Відхилено (P-256 ≠ голос дерева); slot-provisioning-патерн reusable для SE050 |
| **STSAFE-A110** | STMicroelectronics | Same vendor як STM32 → unified CubeMX toolchain; **ECC = P-256 only** | Відхилено (P-256 ≠ голос дерева) |
| **OPTIGA Trust M** | Infineon | TPM 2.0 features, X.509 PKI heavy; P-256/384 | Overkill + без Ed25519 |
| **NXP A71CH** | NXP | EOL announced 2024 | ❌ Не використовувати |

**Обрано: SE050** — true-DePIN вимагає non-extractable Ed25519 («голос дерева», крива peaq/Solana), і лише SE050 його вміє (решта — P-256-only). ATECC slot-provisioning-механіка лишається reusable для SE050 (SE05x = object-model замість 16 slots — §3.7 callout угорі). Deep SE05x-механіка (повне API-переписування) + final BOM — **eval-kit-gated** → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker); paper-половина datasheet-verify закрита нижче.

#### SE050 datasheet-verify — paper-половина (2026-07-02) [📐 paper-verified · silicon-confirm → eval-kit]

> Звірено посторінково проти **SE050 DS Rev 3.3** (док. 504933; Table 2/11/12/13/14), FIPS SP 140sp3840, AN12436 (через індекс), DigiKey (ціни = зріз 2026-07-02). Замінює ATECC-проксі-плейсхолдери цього §; числа кремнієво підтверджуються на eval-kit.

| Факт (paper-verified) | Значення | Наслідок для нас |
|---|---|---|
| **AES-режими on-chip** | **CBC / ECB / CTR — CCM/GCM НЕМАЄ** (Table 2) | per-packet FW.2-CCM ≠ один виклик → SEC.14 provisioning-only підсилений апаратно; CCM/GCM вміє **SE051** (applet 7.x) |
| **Струми** (Table 12) | active: PK-coproc (Ed25519) **14.4/16.1 мА** typ/max · AES-coproc 6.5/7.5 мА · CPU 4.4/7 мА · concurrent max 19 мА; сон: **DPD 3/5 µA** · PD-I2C 450/500 µА · PD-ISO7816 430/480 µА | «150 нА sleep» = хибний ATECC-проксі (~20–30×); load-switch = повне зняття живлення (Power impact вище) |
| **Ed25519 по варіантах** | конфіг **C** (єдиний з A/B/C/D), **E** (applet 7.2), SE051; **SE050F (FIPS): Ed25519 ВІДСУТНІЙ у approved-режимі** (FIPS SP Table 7 — лише ECDSA P-криві/RSA) | F-варіант відпадає для «голосу дерева»; цифра 1/2 у назві = температурний клас (2 = −40…105 °C), не крипто → ліс = **C2 / E2** |
| **Object-model** | динамічна ФС **50 kB** (100 M write / 25 р.): Symmetric/ECC/RSA/HMAC key · Binary · UserID · **Counter 1–8 B, inc-only** · PCR; policy per-object; T1oI2C @ 0x48, HS 3.4 МГц (clock-stretch) | «Slot 4–15 reserved» ATECC-патерну не існує як обмеження — об'єкти іменовані, ліміт = пам'ять |
| **Wake vs cold-boot** | wake-from-PD 67/97 µs (Table 14); Flash program 2.3 мс (Table 13); **cold-boot з повного вимкнення — НЕ специфіковано** | за load-switch SE щоразу холодний → **cold-boot час+заряд = головне eval-питання** (може стати домінантою бюджету) |
| **Ціна** (DigiKey, зріз) | SE050C2HQ1/Z01SDZ: **$4.50/1 · $2.84/100 · $2.50/1k**; сток ~20k, HX2QFN20 3×3 мм | плейсхолдер «$2.40–3.25» тримається лише @1k+ |
| **Eval-kit** | **OM-SE050ARD-E** (SE050E — найчистіший EdDSA-шлях, Arduino-header → Nucleo) + опц. OM-SE050ARD (C-конфіг = mass-BOM дефолт); **НЕ** -F | 👤 замовлення (SE050-MIGRATION) |
| **Host-стек** | Plug&Trust **nano-package**: bare-metal ок (клейм ~10 kB), портів під STM32WLE5 нема (I²C-shim наш); **mbedTLS-ALT дає лише ECDSA-sign** → EdDSA через `sss`/`Se05x` API; ліцензії mixed (nano = Apache-2.0, звірити per-file) | інтеграційні residuals → SE050-MIGRATION |
| **SE051 paper-verify** (DS Rev 1.4, док. 577314, Table 1/10/11) | AES **CBC/ECB/CTR/GCM/CCM** ✅ · струми **≡ SE050** (comm 3.0/3.7 мА · AES 6.5/7.5 · asym 14.4/16.5 · **DPD 3/5 µА** · PD-I2C 450/500 µА) · HX2QFN20 · I²C 0x48 HS 3.4 МГц (clock-stretch дефолт OFF → 1 МГц без stretch) · T1oI2C + GPC_SPE_172 авто-детект · **SEMS Lite** (польові applet-апдейти; security-upgrades = commercial agreement) · **PERSO** (45→101 kB) · TRNG SP800-90B · IEC62443-4-2 · конфіги A/C/P (+W UWB), temp-класи ті самі | **BASELINE (founder 2026-07-02): SE051C2**; SE050C2 = fallback — спільна платформа/footprint, перемикання до BOM-freeze безболісне |

**Open-for-eval (папери НЕ закрили):** cold-boot час+заряд (обидва чипи — платформа спільна) · латентності Ed25519-sign / AES-APDU через T1oI2C · applet-3.x EdDSA erratum (Errata sheet недоступний онлайн) · **ціна/сток SE051C2** (DigiKey — звірити при замовленні; SE050C2 = $2.50/1k відомий) · AN12973 конфіг-деталі SE051 A-vs-C · наявність офіційного OM-SE051ARD (fallback = Mikroe SE051 Click) · pin-звірка SE050↔SE051 при KiCad footprint · точний nano-package footprint на Cortex-M.

**Factory Flashing impact (cross-ref 03_06 §1):**

При інтеграції ATECC608B пайплайн виглядає так:

```
[Завод]
  1. Reflow PCBA (ATECC608B запаяний, але config zone не locked)
  2. Power-up → STM32 talks to ATECC608B over I²C
  3. STM32 → backend: POST /provisioning/register {device_uid}
  4. Backend → returns: {aes_key, ecc_keypair, cert_chain}
  5. STM32 → ATECC608B: write Slot 0 (AES), Slot 1 (ECC), Slot 2 (cert)
  6. STM32 → ATECC608B: LOCK config zone + data zone (irreversible на ASIC рівні)
  7. STM32CubeProgrammer → RDP Level 1 (на самому MCU)
  8. Final: пакування, лак (shipping-mode ✂️ не потрібен — §3.5)
```

**Подвійний lock (defense in depth):**
- ATECC608B: data zone locked → ключі неможливо ні прочитати, ні переписати
- STM32 RDP Level 1/2: SWD заблоковано → firmware не можна змінити

**Дорожня карта:**

- [ ] 👤 SE050 footprint + I²C placement у KiCad floorplan (soft-freeze DNP — ADR угорі §3.7) — дім роботи [`00_07` — HW.9](00_07_Action_Plan_Tracker) (PCB layout)
- [x] 🤖 (SEC.14) Перефреймувати latency/power → чесний trade-off «per-packet AES vs provisioning-only» — ✅ Виконано (підрозділ вище): енерго-аргумент перевірено = малий, але не вирішальний; справжня вісь = tamper-resistance LoRa-ключа ⟷ latency/ідіом; role-split альтернатива подана
- [x] 🤖 (SEC.14, 2026-06-12) Cross-check проти Сценарію C ([`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)) — точні %: active ≈0.3% TX / ≈0.2% циклу / ≈3% годинного запасу (підтверджує «малий»); **знахідка-інверсія**: always-on sleep 150 нА ≈ 3.6 мДж/год > запас Сценарію C → **load-switch гейт SE обов'язковий** (Power impact вище; стосується обох ролей)
- [x] 👤 (SEC.14) Роль SE обрано — ✅ RESOLVED 2026-07-03: **provisioning-only** design-default (Статус вище); eval-residual = silicon-confirm чисел → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker)
- [x] 🤖 Update 03_06 §1 Factory Flashing pipeline з SE-варіантом — ✅ Виконано: 03_06 §1 розділено на Гілку A (Protected Flash, TRL 6/7) та Гілку B (ATECC608B/STSAFE-A110, mass production > 10k); додано двошаровий defense-in-depth (data zone lock + RDP), latency/power/cost impact, criteria для вибору гілки, та irreversibility note (B → A неможливо)
- [ ] 🤖 Інтеграція з Backend `HardwareKeyService` (генерація SE-identity keypair + cert) — eval-kit-gated, Гілка B → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker)
- [ ] 🤖 (лише якщо колись обрано urban/high-value варіант) drop-in `Crypto_AES_Encrypt_Block()` SE-шлях за `#define USE_SECURE_ELEMENT` — **N/A для forest-baseline** (SEC.14 provisioning-only: LoRa AES = HAL_CRYP завжди)
- [ ] 👤 Замовити eval-пару: **SE051-кіт** (звірити офіційний OM-SE051ARD; fallback = Mikroe SE051 Plug&Trust Click) + **OM-SE050ARD-E** companion для порівняльного bench (**НЕ** -F — FIPS-режим без Ed25519) — baseline-рішення й обґрунтування в datasheet-verify таблиці вище → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker)
- [ ] 👤 Прийняти final BOM рішення перед першим mass production batch (>1000 unit)

**Пріоритет:** P2 — для TRL 6/7 RDP Level 2 (§3.6) є достатнім захистом. Secure Element — обов'язковий перед mass production (>10 000 unit) або для high-value deployments (urban / commercial sites).

---

### 3.8 [FW.17] Hash-Ratchet ротація LoRa-ключа (freeze-contract; активація gated)

**Статус:** 🟡 host-готово (2026-06-10) — примітив, wire-кадр і версійна дисципліна freeze-contract'нуті обабіч (golden-KAT byte-parity: `firmware/test/test_key_ratchet.c` ↔ `spec/services/cryptography/key_ratchet_spec.rb`); **інтеграція написана обабіч (2026-06-11), інертна за двома гейтами** (residual нижче). Закриває механізм «Відсутній Механізм Ротації Ключів» (нарація ризиків — блок у відкритих питаннях вище).

**Принцип.** Ключ ніколи не летить ефіром: backend командує лише «дожени версію N», обидва кінці синхронно деривують наступний ключ. Один крок ratchet'а — KDF in Counter Mode за NIST SP 800-108 (i=1, Label, Context=DID, L=128):

```
K_{v+1} = HMAC-SHA256(key = K_v,
                      msg = 0x01 ‖ "silken-lora-ratchet-v1" ‖ 0x00 ‖ DID_be4 ‖ 0x0080)[0..15]
```

Примітив — pure-C `Silken_Hmac_Sha256` (FW.30: апаратного SHA на WLE5 нема; AES-self-encrypt зі старого ескізу відкинуто — нестандартна конструкція без потреби, коли SHA256 вже відвантажено). DID у Context розводить ланцюги пристроїв зі спільним постачанням. Доми коду: `firmware/common/key_ratchet.h` ↔ `Cryptography::KeyRatchet`.

**Wire — `CMD_ROTATE_KEY` `0x9E` (опкод-карта [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA)):** `[0x9E][len_le:2 = 4][target_version:u16le][crc16_le:2]` = 7 байт, каркас 0x9A. Будує `OtaPackagerService.build_rotate_key_block`, парсить `Key_Ratchet_Parse_Cmd`; golden-кадр `9E 0400 0300 5C48` заморожено обабіч.

**Версійна дисципліна:** `u16` monotonic; advance лише вперед (replay/rollback → відмова) і стрибком ≤ `KEY_RATCHET_MAX_JUMP = 8` (CPU-bound: 1 крок = 1 HMAC; runaway-таргет зіпсутого кадру нешкідливий). Target — абсолютний, тож пропущені команди доганяються наступною.

**Persist (узгоджено з [`03_01 §2.3.1`](03_01_Firmware_Lifecycle_and_DMA)):** у Flash-KV їде **лише версія** (ключ `0x13 FW17_KEYVER`) — журнал append-only, і старі записи не сміють тримати ключового матеріалу. Boot: `K_current = ratchet^v(K0)` з Protected Flash (FW.1); v HMAC-кроків на boot — мікросекунди навіть на сотнях версій.

**ACK без окремого каналу:** backend ротує `HardwareKey` при dispatch'і команди (новий ключ; старий → `previous_aes_key_hex`, Dual-Key Grace 03_06 §2) → перший uplink, що декриптнувся новим ключем, = неявний per-device ACK (`clear_grace_period!` — наявна машинерія). Cluster-wide ротація = батч per-device команд; «cluster ACK» = усі grace-вікна кластера закриті.

**Чесна модель загроз:**
- ✅ **Backward secrecy** — головна регуляторна цінність (NIST SP 800-57 / GDPR / ISO 27001): витік `K_v` (DB-leak бекенда) не відкриває попередні ключі й записаний раніше трафік.
- ⚠️ Майбутні ключі з `K_v` похідні (hash-ланцюг) — відновлення після компрометації = re-provisioning (SEC.3) або ECDH-alt (нижче). Ratchet ≠ compromise recovery.
- ⚠️ Фізичний витяг `K0` з пристрою дає весь ланцюг — захист сьогодні = RDP2 (§3.6); справжнє закриття = SE050 non-extractable + HW monotonic counter (§3.7, рунг L2). `K0`-rederive свідомо обрано замість erase-old-key: append-only Flash-KV не вміє гарантовано стирати, а Protected Flash не перезаписується без unlock.
- 🔴 **Активаційні gates (уточнено 2026-07-03, разом з FW.2 (в)):** (i) **MAC-downlink** — ECB-downlink без MAC не сміє командувати ротацією (bit-flip/forge кадру); FW.2 CCM автентифікує лише UPLINK — downlink лишається ECB+CRC (§2.4), тож цей гейт **НЕ знімається CCM-фліпом**; його знімає майбутня downlink-wire-ревізія. (ii) **0x9E не несе DID-таргета** — кадр чують усі, хто випадково слухає (реле = таймінг RX-вікна, не адресація — [`03_02 §5б`](03_02_Queen_Gateway_Firmware)): сусід, що почув чужу ротацію, ротувався б у розсинхрон із backend'ом → перед активацією у кадр додається DID-поле (місце є: 7 з 16 Б зайнято). (iii) ✅ **ЗНЯТО двоключовою моделлю (FW.2 (в))** — колишня прихована несумісність «перша ротація робить downlink вузла нечитним назавжди» (ратчет ротував ЄДИНИЙ ключ, який обслуговував і RX; Queen не ротується) зникла конструкцією: ратчет ротує **лише session KEYL**, амбієнтний KEYB недоторканий (`MX_CRYP_Init` після Advance повертає bcast). До активації інтеграція інертна за двома дзеркальними гейтами: firmware `FW17_RATCHET_ENABLED 0` (компайл-флаг у `main.c`, патерн `FW2_CCM_ENABLED`/`FW8_PARSER_ENABLED`) + backend ENV `FW17_RATCHET_DOWNLINK_ENABLED` (закритий гейт → `RatchetGateClosedError` ДО будь-якої зміни БД; воркер дублює перевірку defense-in-depth).

**ECDH-alt (ADR):** Curve25519-обмін при provisioning дає *незалежну* ротацію (компрометація поточного ключа не тягне майбутніх), але потребує asymmetric-церемонії на M4 + key transport. Рішення: ratchet зараз (симетрія, нуль нових примітивів), ECDH — природно разом із SE050-L2 (ECDH усередині SE).

**Інтеграція ✅ (2026-06-11), за гейтами:** `key_version` колонка `HardwareKey` + ратчет-гілка `HardwareKeyService#rotate!` для Tree (Gateway лишається на випадковому ключі: доставка = re-provision SEC.3; legacy `sys/key_update` — слав КЛЮЧ ефіром, не мав firmware-споживача і викликав `ActuatorCommandWorker` з чужою арністю — **видалено**) + `KeyRotationDownlinkWorker` (0x9E через найкращу Queen кластера, патерн TimeSync) + Soldier-гілка `0x9E` у `main.c` (parse → `Key_Ratchet_Advance` → re-key CRYP → версія у Flash-KV у КЕНОЗИСІ) + mount Flash-KV (сторінки 122-123; спільний гейт із FW.8 — **K_ota тому переїхав на сторінку 125**, первісний `0x0803E800`-попередник `0x0803D000` колідував із KV-регіоном) + boot re-derive `Key_Ratchet_Apply`. **Queen-реле ✅ (2026-06-12):** `soldier_cmd_queue` (FW.20-Q2, спільний шлях з 0x9A) — маршрутизація + рефлекторні постріли з shot-бюджетом, інертне за `FW20_Q2_CMD_RELAY_ENABLED 0`; канон реле — [`03_02 §5б`](03_02_Queen_Gateway_Firmware).

**Residual ([`00_07` — FW.17](00_07_Action_Plan_Tracker)):** фліп трьох гейтів після FW.2 CCM (Soldier `FW17_RATCHET_ENABLED` + Queen `FW20_Q2_CMD_RELAY_ENABLED` + backend ENV) + bench (re-key CRYP та Flash-KV erase/program на кремнії); глибина `soldier_cmd_queue` під per-device CCM-батч cluster-wide ротації — разом із CCM-flip дизайном.

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
        // [HRNG-IV harden] pure-деривація (дім: firmware/queen/coap_iv.h):
        // унікальність across device (uid_hash) / reboot (queen_unix_ts) /
        // flush (coap_flush_seq); host-тести firmware/test/test_encryption.c
        batch_iv[i] = coap_fallback_iv_word(i, HAL_GetTick(),
                                            djb2_hash(queen_uid, strlen(queen_uid)),
                                            queen_unix_ts, coap_flush_seq);
    }
}

HAL_RNG_DeInit(&hrng);                  // Де-ініціалізація: нульове споживання у сні

hcryp.Init.pInitVect = batch_iv;        // Встановлюємо IV у крипто-модуль
HAL_CRYP_Init(&hcryp);                  // Оновлюємо конфігурацію CRYP

// IV лягає на свій зсув спільного конверта (розкладка: common/queen_attest.h):
memcpy(batch_attest_buffer + QATT_IV_OFFSET, batch_iv, 16);
HAL_CRYP_Encrypt(&hcryp, (uint32_t*)binary_batch_buffer,
                 padded_size / 4,
                 (uint32_t*)(batch_attest_buffer + QATT_CT_OFFSET),
                 2000);
```

**Характеристики IV:**

| Параметр | Значення |
|----------|---------|
| Розмір | 128 біт (4 × uint32_t) |
| Джерело | HRNG (тепловий шум) — при успіху |
| Fallback | `coap_fallback_iv_word(i, tick, uid_hash, queen_unix_ts, coap_flush_seq)` — pure (`coap_iv.h`), унікальний across device/reboot/flush; передбачуваний, але без chosen-plaintext вектора (§HRNG Fallback) |
| Унікальність | Новий IV на кожен батч-флашинг (не перевикористовується) |
| Передача | Prepend до ciphertext: `[IV:16][Encrypted:N×16]`; при L1 QATT — усередині підписаного конверта (§2.2) |

### 4.3 Queen: CBC IV для CoAP Command Downlink (Handle_CoAP_Command)

> **[FW.60]** Гілка виконується всередині poll-відповіді (Королева питає
> `poll/<uid>` після флашу — [`03_02 §4а`](03_02_Queen_Gateway_Firmware)).

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
         │ LoRa 868 MHz (AES-128-ECB, 16 bytes, no IV, no MAC)
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
  4. hcryp → CBC mode → encrypt у batch_attest_buffer (IV+ct на своїх зсувах)
  5. Restore: hcryp → ECB mode (ОДРАЗУ після encrypt, ДО модемної розмови — FW.3)
  6. [L1 QATT, якщо EDSK-сім'я прошита] Ed25519-підпис конверта (§2.2)
  7. AT+CCOAPSEND → SIM7070G → CoAP PUT /telemetry/batch/<queen_uid>
         │
         │ CoAP/UDP (AES-256-CBC; legacy [IV:16][ct] або підписаний
         │ [header:9][IV:16][ct][sig:64] — §2.2) via SIM7070G → Rails
         ▼
RAILS BACKEND
  UnpackTelemetryWorker: [L1 QATT] verify-до-decrypt → strip конверта
  TelemetryUnpackerService.decrypt_and_parse(payload)
         │
         │ CoAP Downlink (AES-256-CBC, [IV:16][Ciphertext]) —
         │ їде відповіддю на Королевин poll/<uid> [FW.60], НЕ push/сервер
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

| Канал | Алгоритм | Режим | Ключ (CCM-ера — §3.1) | IV / Nonce | MAC/MIC | Примітка |
|-------|----------|-------|----------------------|-----------|---------|---------|
| **Soldier → Queen** (LoRa, 16B) | AES-128 | ECB | (ECB-ера: єдиний спільний) | ❌ Відсутній | ❌ Відсутній | ⚠️ Replay вразливість |
| **EwsAlert / Panic → Queen** (LoRa, 16B) | AES-128 | ECB | (ECB-ера: єдиний спільний) | ❌ Відсутній | ❌ Відсутній | ⚠️ Критичні пакети без автентифікації |
| **Soldier → Queen** (LoRa, 30B rev2.1 — target FW.2, INERT за `FW2_CCM_ENABLED`) | AES-128 | CCM | **KEYL session (per-device)** | ✅ Nonce = DID‖FC24 (DR15 + Flash high-water) | ✅ 8B MIC (64-bit) | wire-rev2 §2.1; integration authored 2026-07-03, фліп = bench-атестація |
| **Soldier → Queen** (`0x55`/`0x56` control-запити, 16B) | AES-128 | ECB | **KEYB cluster** (Королева читає сама) | ❌ Відсутній | ❌ Відсутній | control-plane; лишається ECB і в CCM-еру |
| **Queen → Rails** (CoAP Batch) | AES-256 | CBC | KEYC (per-gateway) | ✅ HRNG (128-bit) | 🟡 **Ed25519 batch-sig (L1 QATT, §2.2)** — detached, encrypt-then-sign; legacy L0 без підпису приймається | IV prepend; sig хвостом |
| **Rails → Queen** (CoAP Command) | AES-256 | CBC | KEYC (per-gateway) | ✅ Від Backend | ❌ Відсутній | IV в перших 16 байтах; транспорт = poll-після-флашу [FW.60] ([`03_02 §4а`](03_02_Queen_Gateway_Firmware)) |
| **Queen → Soldier** (downlink LoRa: OTA/beacon/CMD) | AES-128 | ECB | **KEYB cluster** | ❌ Відсутній | ❌ MAC відсутній (стеля — §2.4); OTA-image гейтований K_ota-HMAC (FW.23) | broadcast-структурний; без MAC — FW.17 лишається замкненим (§3.8) |

---

## ⚡ 7. Відновлення Стану CRYP (ECB Restoration Pattern)

Queen динамічно перемикається між ECB та CBC в залежності від операції. Після кожної CBC-операції модуль явно відновлюється до ECB:

```c
// Після Flush_Cache_To_Rails() (CBC → ECB):
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);

// Після Handle_CoAP_Command() (CBC → ECB; виконується в poll-циклі [FW.60]):
hcryp.Init.Algorithm = CRYP_AES_ECB;
hcryp.Init.pInitVect = NULL;
HAL_CRYP_Init(&hcryp);
```

Це виправлено (`[FIX: CRITICAL — ECB Restoration]`). Без цього виправлення всі наступні `HAL_CRYP_Decrypt()` від Солдатів повертали сміття, що призводило до втрати всієї телеметрії до наступного перезапуску Queen.

---

## 🧪 8. Тестове Покриття (Host-Based Tests)

> Методологія / гейт / тріаж покриття (cross-cutting) — канон [`04_06`](04_06_Testing_Guide_and_Coverage); тут — лише per-subsystem інвентар host-тестів крипто-пайплайну (One-Home: інвентар біля підсистеми). Лічильники не ведемо (drift) — істина = вивід `make -C firmware/test`.

| Тест | Файл | Покриття |
|------|------|---------|
| AES-128 LoRa block encrypt/decrypt round-trip [post-ARCH.42] | `firmware/test/test_encryption.c` | ✅ ECB single-block 128B |
| AES-256 CoAP batch encrypt + IV prepend [Queen only] | `firmware/test/test_queen_logic.c` | ✅ Часткове |
| Load_AES_Key() Flash magic guard | `firmware/test/test_soldier_logic.c::test_load_key_unprovisioned_flash_error` | ✅ |
| Emergency TX format | `firmware/test/` | ⚠️ Не верифіковано |
| HRNG fallback behavior | Відсутній | 🔴 Не покрито |
| Key hardcoding detection | `app/services/security/weak_key_detector.rb` + boot guard | ✅ Backend |
| **AES-128-CCM encrypt + MIC verify [FW.2 target]** | `firmware/test/test_ccm.c` (двофазний WL-флоу + B0-валідація + tamper-bank + Phase-4/panic маршалінг e2e) + `test_ccm_selftest.c` (POST) + `spec/services/cryptography/lora_ccm_spec.rb` — KAT-parity з OpenSSL | ✅ host / 🟡 bench silicon-confirm |
| **Queen RX-роутинг + 31B CoAP-запис (air+1) [FW.2]** | `firmware/test/test_queen_rx_route.c` (класифікація 16/30/шум, cleartext-DID, golden-звірка запису проти backend-контракту) + fmt-aware CIFO у `test_queen_logic.c` + RX size-guard у `test_soldier_logic.c` | ✅ host |
| **Двоключова модель [FW.2 (в)]: KEYB-load + key-scoping** | `test_soldier_logic.c` (KEYB provisioned/fallback/wrong-magic/zero-key/magic-value) + `test_ccm.c::test_two_key_scoping_contract` (session у CCM-скоупі ≡ golden-KAT, амбієнт = bcast після Restore, «липкий ключ» ловиться) + `spec/services/hardware_key_service_spec.rb` (derive_broadcast_key: детермінізм, per-cluster ізоляція, domain-sep від KEYL/K_ota) + `command_builder_spec.rb` (KEYB-блок Tree, KEYL-broadcast Gateway) | ✅ host |

**Загальний статус:** host-based тести проходять (`make -C firmware/test`). Але тестове покриття **криптографічного пайплайну** є неповним — зокрема HRNG fallback, EwsAlert panic TX та **FW.2 CCM mode** не тестуються (CCM потребує hardware bench для верифікації `CRYP_AES_CCM` HAL модуля).

---

## 📋 9. Резюме Аудиту Безпеки

| Категорія | Стан | Деталі |
|-----------|------|--------|
| **Алгоритм LoRa** | ✅ AES-128 [ARCH.42] | Відповідає FIPS 197, IEEE 802.15.4 / LoRaWAN industry standard |
| **Алгоритм CoAP** | ✅ AES-256 | Без змін — Queen MCU зберігає 256-bit key у Protected Flash (немає SE-constraint на цьому каналі) |
| **Розмір ключа LoRa** | ✅ 128 біт | ARCH.42 — свідомий вибір (golden-standard LoRaWAN/Zigbee/BLE), **не** SE-constraint (SE050 вміє і 256; §3.7) |
| **Розмір ключа CoAP** | ✅ 256 біт | Без змін |
| **Апаратне прискорення** | ✅ STM32 AES Block | Без програмної крипто-бібліотеки; підтримує і 128B, і 256B через runtime re-init |
| **CBC IV для CoAP** | ✅ HRNG (тепловий шум) | Унікальний IV на кожен батч |
| **Зберігання ключа** | ✅ Protected Flash Sector (session `"KEYL"`, cluster control-plane `"KEYB"`, CoAP `"KEYC"`, L1-сім'я `"EDSK"`), RDP Level 1/2 protected. SE050 Slot 0 (Гілка B, §3.7) для mass production >10k |
| **Унікальність ключа** | ✅ Двоключова модель (FW.2 (в), §3.1) | Session per-device: `HKDF(MASTER, uid, "silken-aes-128-lora-key")` — money-path ізольований (злам 1 вузла ≠ підробка мінта сусідів); control-plane per-cluster: `HKDF(MASTER, "cluster:<id>", "silken-aes-128-broadcast-key")` — свідомий broadcast-структурний секрет класу K_ota; CoAP per-gateway. Domain separation 03_06 §2 |
| **ECB для LoRa** | 🟡 Transitional після ARCH.42 | AES-128-ECB → AES-128-CCM (target FW.2, 30B wire-rev2.1 packet + Frame Counter + 8B MIC) |
| **MAC/MIC (LoRa)** | 🟡 OPEN — закривається з FW.2 CCM | 8-byte MIC (64-bit, forge probability $5.4×10^{-20}$) |
| **CoAP batch origin + integrity** | 🟡 **L1 QATT shipped** (2026-06-07) | Ed25519 batch-підпис Королеви (§2.2): закриває CBC-malleability/injection + anti-replay у nonce-вікні; legacy L0 без підпису ще приймається (fleet-перехід); 👤 bench: EDSK на кремнії. Ladder → [`05_02`](05_02_Proof_of_Growth_Pipeline) |
| **RDP Protection** | 🟡 OPEN | Level 0 (розробка). Level 1/2 — фінальний крок Factory Flashing (розділ 3.3). Pre-flight checklist та незворотна процедура задокументовані у §3.6 🤖 |
| **Factory Flashing Pipeline** | 🟡 PARTIAL (SEC.3) | ✅ Архітектура (03_06 §1) + HKDF (03_06 §2) + Operations Security threat model + tool implementation + master-key DI + one-pass UID→DID (FW.54: `TreeResolver` + wrong-board guard) (03_06 §5 — `app/services/factory_flashing/*`, `lib/tasks/factory.rake`, RSpec-покрито, dry-run default). Residuals → [`00_07`](00_07_Action_Plan_Tracker) SEC.3 (bench SWD + `-r32`-формат · Bitwarden live · SE-I²C — SE050 eval-kit) |
| **Shipping Mode (Геркон)** | ✂️ PRUNED | Не потрібен (SEC.4 RESOLVED 2026-07-03) — фізика проти компонента; decision-record + reopen-умови → розділ 3.5 |
| **Secure Element (SE050)** | ✅ SEC.6 RESOLVED (true-DePIN) | §3.7 ADR — SE = **SE050** (Ed25519 on-chip keygen; реверс ATECC), soft-freeze DNP, populate post-FW.2; slot-map §3.7. Residuals → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker) |
| **Key Rotation** | 🟡 host-готово | Hash-Ratchet freeze-contract §3.8 (backward secrecy, ключ не летить ефіром); активація CCM-gated — `[FW.17]` |
| **HRNG Fallback** | ✅ Harden (2026-05-29) | `coap_fallback_iv_word` (pure, `coap_iv.h`) — унікальність across device/reboot/flush; §4.2 |
| **Runtime memory-safety** | 🟡 PARTIAL (SEC.21) | ✅ `-fstack-protector-strong` (`arm-none-eabi.cmake`) інструментує canary на attacker-reachable парсери (LoRa-RX / AT-токенайзер жують untrusted байти в сирому C ДО MIC-чеку); CI flag-gate (`firmware_arm_build`) стереже прапор. ✅ **Fielded-варта (2026-07-12):** власні strong `__stack_chk_fail`/`__stack_chk_guard` в обох main.c перекривають newlib (lazy-archive; дефолт був guard=0x00000000 з .bss — `__stack_chk_init` ніхто не кличе — і fail→abort→вічний wfi-hang): Soldier = слід у `DR0[10]` (пряме `TAMP->BKP0R`) + `NVIC_SystemReset`, Queen = reset-only (backup-domain нема; persist-слід → QATT-health, bench); HRNG-сів guard'а at-boot (`common/stack_canary.h`, I-CG: ніколи не нуль, NUL-LSB; Queen — Wu-Wei ДО старту UART-кільця) + CI source-gate обох TU. ✅ **MPU-draft:** NX-stack (SRAM 64K XN) + RO-code (Flash 256K RO, RW-хвіст стор. 122-127 через 16K-вікно+SRD — `common/mpu_regions.h`, golden-host-тести) за гейтом `SEC21_MPU_ENABLED` (компайл = `hal_check_ccm`; PRIVDEFENA=1, HFNMIENA=0 — canary-варта пише TAMP без trap'а). Residuals → [`00_07`](00_07_Action_Plan_Tracker) SEC.21: MPU-АКТИВАЦІЯ (реальний MemManage-trap; QEMU не моделює) [bench] (canary wire-винос ✅ L1 device-event — §2.2а) |
| **PQC Migration Roadmap** | ✅ Документовано | §10 — TRL-stratified layering (2026 → 2028 → 2035); LoRa поточно квантово-стійкий через симетрію + ratchet, асиметричні шари мігрують через hybrid Cloudflare X25519+Kyber → ML-KEM/ML-DSA |

---

## 🛡️ 10. PQC Migration Roadmap (TRL-Stratified Post-Quantum Layering)

> **Cross-ref:** [ARCH.42](00_07_Action_Plan_Tracker) (ARCH-decision цього документа), [FW.17](00_07_Action_Plan_Tracker) (Hash Ratchet KDF — Perfect Forward Secrecy bridge), [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) (peaq DID + IoTeX W3bstream рівні), [INF.4](00_07_Action_Plan_Tracker) (Cloudflare TLS termination), `manifest.md` §3 (Cryptographic Integrity).

### 10.1 Чому це **не** аварійне питання, але **обов'язково** має план

Квантовий комп'ютер достатньої потужності для злому ECC/RSA через алгоритм Шора — реальний ризик на горизонті 2035–2045. Для нашого 20–25-річного deployment-горизонту (2026–2046+) ми **зобов'язані** мати міграційний шлях, але **не зобов'язані** ламати поточну архітектуру у TRL 6.

**Ключове рознесення:**

| Тип крипто | Уразливість до квантовості | Наша поточна позиція |
|------------|----------------------------|----------------------|
| **Симетричне (AES)** | Лише **квадратний корінь** ослаблення через Гровера (Grover's algorithm). AES-128 → ефективна стійкість $2^{64}$; AES-256 → $2^{128}$. | LoRa AES-128 — `[FW.17]` Hash Ratchet KDF знижує per-key accumulated ciphertext до сотень пакетів; CoAP AES-256 — повний імунітет ($2^{128}$ під Grover'ом — більше енергії ніж є у всесвіті) |
| **Хеш-функції (SHA-256, HMAC-SHA256)** | Гровер ослаблює аналогічно, але NIST SP 800-208 (LMS/XMSS) вже стандартизує stateful hash-based signatures для довгого життя | OTA dual-gate `[FW.23]` — поточний HMAC-SHA256 криптографічно стійкіший до квантової атаки ніж Ed25519 |
| **Асиметричне (ECC P-256, Ed25519, RSA)** | **Повний злам Шор'ом за хвилини** на квантовому комп'ютері достатнього розміру | peaq DID (Ed25519), IoTeX ZK-proof, Chainlink ECDSA — usual асиметрія, мігрує через стандарти L1/L2 networks |

### 10.2 Триетапна міграція (TRL-stratified)

#### **Етап 1 (TRL 4–6, 2026–2028 — поточний)** — Криптографічний Схов

| Контур | Алгоритм | Постквантова позиція |
|--------|----------|----------------------|
| Soldier ↔ Queen (LoRa) | **AES-128-CCM** (post-FW.2) | Стійкий через симетричну природу + Hash Ratchet `[FW.17]` rotation. Per-key cumulative ciphertext < 1000 пакетів → Grover-attack не накопичує плейнтексту |
| Queen ↔ Rails (CoAP magistral) | **AES-256-CBC** | Повний квантовий імунітет ($2^{128}$ під Grover'ом) |
| Queen ↔ Rails (TLS layer, INF.4) | **TLS 1.3 X25519** [поточний] → **X25519 + Kyber-768 hybrid** [Cloudflare default 2024+] | Cloudflare Edge Network вже proxies TLS handshake з гібридним PQC за замовчуванням — 0 коду для нас |
| OTA Firmware Verification | **HMAC-SHA256** (FW.23 dual-gate) | Hash-based — стійкіший до квантового аналізу ніж Ed25519. Наш приховане перевага |
| peaq DID (machine identity) | **Ed25519** | Делегуємо peaq Substrate (мережа сама мігрує на ML-DSA коли стандарт буде native у Substrate) |
| Polygon SCC mint | **ECDSA secp256k1** | Делегуємо Polygon L2 (EVM-стек мігрує синхронно з Ethereum) |

**Що ми НЕ робимо у TRL 4–6:**
- ❌ НЕ пишемо жодного рядка PQC коду на Soldier (Dilithium підпис — 2420 байт, не вміщається у 30B LoRa packet; Kyber публічний ключ — 1184 байти, не вміщається у LoRa airtime budget)
- ❌ НЕ міняємо STM32WLE5JC на чіп з апаратним Kyber acceleration (такі чіпи ще не існують у TRL 9 silicon @ low-power profile)
- ❌ НЕ форсуємо peaq/Polygon DID міграцію — це залежить від upstream blockchain ecosystems

#### **Етап 2 (TRL 7–8, 2028–2030)** — Hybrid Layering на Edge

| Зміна | Контур | Деталі |
|-------|--------|--------|
| **Cloudflare PQC TLS** | Queen ↔ Rails (вже активно) | Нічого не робимо — Cloudflare auto-rolls hybrid Kyber-768 + X25519. Документація у [`06_01 §TLS`](06_01_Deployment_Kamal_Terraform) (INF.4) |
| **Hash Ratchet KDF** | LoRa AES-128 | `[FW.17]` — щотижнева ротація `K_LoRa[i+1] = AES_KDF(K_LoRa[i])`. PFS досягається: компрометація поточного ключа не розкриває минулих пакетів |
| **W3bstream PQC anchoring** | IoTeX ZK-proof | Якщо IoTeX мігрує на PQC-friendly proving system (zk-STARK замість Groth16) — оновимо `Iotex::W3bstreamVerificationService` через RPC bump |
| **Hybrid signature на provisioning** | peaq DID Ed25519 + Dilithium-2 | Подвійний підпис під час provisioning: Ed25519 (compat з peaq Substrate сьогодні) + Dilithium-2 (forward compat). При злам Ed25519 — Dilithium залишається валідним |

#### **Етап 3 (TRL 9+, 2032–2035)** — Кристалічні Ґратки на Edge

Коли silicon-вендори (STMicroelectronics, Microchip, NXP) випустять ультранизьковольтні MCU з апаратним прискоренням PQC ML-KEM/ML-DSA (приблизно 2032–2035 за поточним NIST roadmap):

| Зміна | Як зробимо |
|-------|------------|
| **Заміна STM32WLE5JC на STM32 серії з апаратним Kyber** | Нова revision PCB Soldier; завдяки Blind-Mate [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface) ліснику достатньо replace PEEK-капсулу — титановий анкер у заболоні залишається у дереві |
| **AES-128 LoRa → AES-256 (post-Grover margin)** | SE050 (чинний SE, §3.7) вже підтримує AES-128/192/256 hardware — апгрейд = key-size flip без заміни SE (AES-128 наразі свідомий вибір, не constraint) |
| **OTA HMAC-SHA256 → LMS/XMSS (stateful hash-based signature)** | NIST SP 800-208 стандарт; для billion-tree fleet — wholesale upgrade через factory re-flash під час planned maintenance windows |
| **peaq DID Ed25519 → ML-DSA (Dilithium)** | peaq Substrate-нативний; ми оновлюємо лише `Peaq::DidRegistryService` RPC bibilio через Gemfile bump |

### 10.3 Чому **не** робимо arithmetic compression / ASCON / повний PQC у Soldier зараз

| Технологія | Перевага | Чому не зараз |
|------------|----------|----------------|
| **Arithmetic Coding** (Shannon-optimal compression) | Стискання payload з 21B → ~14B (34% airtime saving) | Потребує big-integer math на кожен біт → з'їдає більше мікроамперів CPU ніж економить на LoRa TX. Bit-flip в ефірі руйнує весь пакет (no FEC). Наш bit-packing у [`03_01`](03_01_Firmware_Lifecycle_and_DMA) ефективніший за енергією. |
| **ASCON** (NIST Lightweight Crypto winner 2023) | Швидший за програмний AES на 8/32-bit MCU | STM32WLE5JC має **апаратний** AES (0 CPU cycles) — ASCON у софті повільніший за наш HW-AES. ASCON стане конкурентним лише коли silicon-вендори додадуть apparatне acceleration. |
| **Dilithium-2 signature** (PQC) | Квантова невідрікальність на per-packet рівні | Підпис 2420 байт vs наш 30-byte LoRa packet → fundamental fit problem. Якщо рамку розширити — duty cycle EU868 (1%) порушиться на 2 порядки. |
| **Kyber-768 KEM** (PQC key encapsulation) | Постквантовий ephemeral key exchange | Публічний ключ 1184 байти, ciphertext 1088 байт — LoRa SF10 payload max ~255 байт. Технологічно несумісно з constrained radio link. |

### 10.4 SSOT-карта: де читати про PQC

| Питання | Документ |
|---------|----------|
| Чому AES-128 LoRa достатньо на 25-річний горизонт | Цей §10 + ARCH.42 у [`00_07`](00_07_Action_Plan_Tracker) |
| Як Cloudflare hybrid Kyber+X25519 інтегровано | [`06_01 §TLS`](06_01_Deployment_Kamal_Terraform) (INF.4) |
| Hash Ratchet KDF дизайн | `[FW.17]` у [`00_07`](00_07_Action_Plan_Tracker) (placeholder) |
| peaq DID міграція на Substrate-PQC | `05_01 Multichain Architecture` §peaq |
| OTA HMAC-SHA256 dual-gate | 03_06 §4 цього файла + `[FW.23]` у [`00_07`](00_07_Action_Plan_Tracker) |
| Chainlink HMAC vs ECDSA migration | `04_02 ChainlinkOracleService` (delegated до Chainlink DON) |

### 10.5 Висновок

> **Наше поточне рішення** — 30-байтний LoRa packet (wire-rev2.1) з AES-128-CCM + 8-байтним MIC + Hash Ratchet rotation — це ідеальна **інженерна точка паритету** (Sweet Spot) для фізичної реальності TRL 6:
>
> ```
> [Абсолютна теорія: PQC + Ed25519 + Arithmetic] ─── Несумісно з EBFC батарейкою та 64KB SRAM
>                      │
>                      ▼ [Суворий інженерний компроміс]
> [Наше рішення: 30B AES-128-CCM + 8B MIC] ─── ✅ 20 років автономності, 0% CPU overhead,
>                                                  криптографічний anti-replay та anti-tamper.
>                      │
>                      ▼ [TRL 7-8 hybrid layering, 2028+]
> [Cloudflare PQC TLS + Hash Ratchet PFS] ─── ✅ Edge-side post-quantum шар без firmware change.
>                      │
>                      ▼ [TRL 9+ silicon evolution, 2032+]
> [STM32 PQC + LMS OTA + ML-DSA peaq DID] ─── ✅ Wholesale crypto refresh via PCB revision.
> ```
>
> ARCH.42 (AES-128 baseline) + FW.2 (CCM upgrade) + §10 PQC layering plan разом утворюють криптографічну дорожню карту, яка **не зачіпає поточний firmware у TRL 6**, але **гарантує квантовий імунітет** до 2046+.
