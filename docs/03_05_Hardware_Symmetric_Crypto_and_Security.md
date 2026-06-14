# 03_05: Апаратне симетричне шифрування та Безпека (Криптографія Пакетів)

> 📜 **Архітектурна нота (ARCH.42 Варіант B, 2026-05-23):** Силова частина криптостеку розділена на дві категорії:
> 1. **LoRa-канал (Soldier ↔ Queen + OTA broadcast):** AES-128-CCM (ARCH.42 LoRa-вибір; SE = SE050 — §3.7)
> 2. **CoAP-магістраль (Queen ↔ Rails) + AR-Encryption у Postgres:** AES-256-CBC / AES-256-GCM (без апаратного SE-constraint; ключ Queen зберігається у Protected Flash MCU)
>
> Постквантовий горизонт + ratchet-rotation описано у новому **§10 PQC Migration Roadmap**.

---

## 🎯 Мета

Зафіксувати детальний криптографічний пайплайн вузлів **Soldier** (датчик дерева) та **Queen** (шлюз-агрегатор): режими роботи AES (CCM для LoRa, CBC для CoAP), структуру зашифрованих пакетів, управління ключами (HKDF per-device + SE050 Secure Element — голос-дерева Ed25519/attestation, SEC.6; деталі §3.7), генерацію вектора ініціалізації (IV/Nonce) та довгостроковий PQC migration roadmap. Документ є SSOT для Hardware Security Audit перед масовим виробничим розгортанням.

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

**Залишається** (трекер — [`00_07`](00_07_Action_Plan_Tracker) SEC.2/SEC.3): SEC.3 Factory Flashing Pipeline tool (✅ 2026-05-24, dry-run; real `STM32_Programmer_CLI` subprocess + live `cryptoauthlib` I²C — deferred до HW bench; threat model → §3.4г); SEC.2 RDP Level 2 activation (необоротний final lock перед field deployment).

> **⚠️ ОПЕРАЦІЙНИЙ РИЗИК (Pre-Flight Checklist):** При кожному циклі прошивки — верифікувати що firmware binary отримує ключ з vault (не хардкоджений placeholder). Симптом помилки: Queen бачить щойно декриптований Soldier-пакет як хаотичний сміттєвий масив, ліс мовчазний, жодних помилок у Rails. Причина — ключ не синхронізований між Soldier і Queen Flash секторами. **Той самий «сміттєвий» ефект фундаментальний і для inter-Soldier mesh-релею за per-device ключів** (сусід не має ключа відправника) — opaque-релей вимагає cleartext address-шару або shared mesh-key → [`00_07` — ARCH.43](00_07_Action_Plan_Tracker).
>
> **⚠️ ЧЕСНІСТЬ ECB-транзиту (ARCH.42): per-device ключі НЕсумісні з ECB-каналом by construction.** Queen firmware тримає ОДИН `aes_key[4]` і декриптить ним усі вхідні LoRa-пакети; DID лежить УСЕРЕДИНІ шифроблоку → щоб обрати per-Soldier ключ, треба спершу розшифрувати (chicken-and-egg). Тож у ECB-перехідному режимі весь кластер де-факто живе на **спільному ключі** (Queen-key = Soldier-key) — FW.1 per-device HKDF-провіжининг стає реальним лише з **FW.2 CCM**, де DID/FC — cleartext AAD і бекенд (`process_ccm_chunk`) обирає `tree.hardware_key` per-DID. Це стосується і downlink-broadcast (OTA/beacon — один TX на всіх → один ключ). Bench-флешинг ECB-фази: всі вузли кластера отримують ключ Королеви.

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

**Структура 28-байтного LoRa-пакета (wire-rev2, founder decision 2026-06-12 — замість 16B ECB; rev1 = 24B, ревізовано ДО фліпу за wire-budget ledger нижче):**

```
┌─ Header (cleartext, AAD) ─────────────────────────────────────────────┐
│ Byte 0 │ Byte 1 │ Byte 2 │ Byte 3 │ Byte 4 │ Byte 5 │ Byte 6 │ Byte 7 │
│      DID (Device ID, 4 байти)     │ gossip │  Frame Counter (3 B, BE) │
└────────┴────────┴────────┴────────┴────────┴────────┴────────┴────────┘
┌─ Encrypted payload (sensor data, 12 байтів) ──────────────────────────┐
│ Byte 8 │ Byte 9 │Byte 10 │Byte 11 │Byte 12 │Byte 13 │Byte 14 │Byte 15 │
│    Vcap (mV, BE)  │  Temp  │ Acous. │  delta_t (sec, BE)│ Status │ Ctrl│
│Byte 16 │Byte 17 │Byte 18 │Byte 19 │                                   │
│  device_z (BE)    │  diag  │  vpd   │                                  │
└────────┴────────┴────────┴────────┴───────────────────────────────────┘
┌─ MIC (Message Integrity Code, 8 байтів) ──────────────────────────────┐
│Byte 20 │Byte 21 │Byte 22 │Byte 23 │Byte 24 │Byte 25 │Byte 26 │Byte 27 │
│                    AES-CCM MAC (8 байтів — 64-bit)                    │
└────────┴────────┴────────┴────────┴────────┴────────┴────────┴────────┘
```

**12-байтний sensor payload (bytes 8..19):**

| Зсув | Поле | Тип | Діапазон / Кодування | Походження |
|------|------|-----|----------------------|------------|
| 0..1 | `Vcap_mv` | uint16 BE | 0..65535 мВ (фактично 0..5500) | повна 1 мВ-роздільність, як у поточному 16B |
| 2 | `temp_c` | int8 | −128..+127 °C | без змін |
| 3 | `acoustic_events` | uint8 (saturating) | 0..255 | FW.22 — saturating increment, без overflow ambiguity |
| 4..5 | `delta_t_s` | uint16 BE | 0..65535 сек (≈ 18 год) | повна роздільність — критично для [E.63] метаболічного `growth_points` (delta_t→GP на пристрої; backend декодує wire, точна звірка — FW.2, [`03_01 §13.6`](03_01_Firmware_Lifecycle_and_DMA)) |
| 6 | `status_byte` | bitfield | `[panic:1 \| status:2 \| growth_points:5]` | FW.29 PANIC_FLAG_BIT (bit 7) + status (bits 6..5) + growth (bits 4..0); зменшено growth з 6 → 5 бітів (0..31), масштабований діапазон у `bio_contract.rb` |
| 7 | `mesh_ctrl` | bitfield | `[ttl:4 \| fw_version_id_low:4]` | TTL у верхніх 4 бітах (FW.10, max 15 hop), FW low-nibble (16-version rotation epoch керується OTA config) |
| 8..9 | `device_z` | uint16 BE | фіксована точка z×512 (q=2⁻⁹, 0..127.99); `0xFFFF` = «Лоренц не рахувався» (ARCH.41-C grace) | **[FW.31 Gate D]** numeric DCI: похибка квантування ≤ 0.00098 < ε 0.001; у шифртексті (z = здоров'я дерева); pack — `Pack_FW2_Device_Z` |
| 10 | `diag` | bitfield | `[thr_invalid:5 \| fauna_mode:1 \| fauna_skip:1 \| fc_degraded:1]` | **[FW.18b]** лічильник відкинутих OTA-порогів (у 21B жив у байті 11) + **[FW.42]** fauna-маркери ([`03_03 §10.4`](03_03_TinyML_Acoustic_Inference)) + **[FW.2]** I-HW degraded-прапорець; pack — `Pack_FW2_Diag` |
| 11 | `vpd_index` | uint8 | `0x00` = немає BME280 | **[HW.32]** резерв-дім VPD-індексу; шкала index→kPa визначається при калібруванні сенсора — закриває double-booking байта 14 з gossip'ом у 21B-плані |

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
- **Frame Counter (3B BE, wire-rev2):** на дроті їде справжня 24-бітна ширина (rev1 слав 4B, де top-байт був завжди 0x00 — wire-rev2 віддав його gossip'у). Monotonic 24-bit у `RTC_BKP_DR15` (єдиний вільний слот — DR2 ❌ зайнято `has_mesh_relay` за SSOT 03_01 §2; doc-fix 2026-05-24). Cold-boot магічний маркер `FW2_FC_MAGIC_BYTE = 0x46` ('F', — дзеркало `lora_ccm.h`) у packing `[magic:8 | frame_counter:24]` — magic у high 8 бітах захищає від невалідного DR15 після VBAT loss (similar pattern до LORENZ_STATE_MAGIC у DR19). 24-bit FC дає **~16.7M значень** — за бюджету 1 TX/година × 8760 год/рік × 25 років = ~219 тис. TX/пристрій життєвий цикл = `18 bit` зайнято, **запас 6 bit ≈ 64× longevity margin** (компроміс: уживаємо magic-byte для cold-boot detection vs full 32-bit FC). Інкрементується перед кожним TX. Cold-boot після VBAT-loss (DR15 magic не збігається) → **Flash high-water floor** (KV-ключ `0x14`, монотонний якір — TRL-7 host-half ✅ 2026-06-12), fallback — reseed з HRNG (range `0x000001..0xFFFFFE`, без обнулення/overflow boundaries). Backend per-DID Redis SETNX 25h-window дедуплікує replay у вікні. **Повна cold-boot політика (floor+advance атомарність, чесна оцінка nonce-унікальності) — у 📐 КАНОНІЧНОМУ ДЖЕРЕЛІ нижче** (не дублюємо тут). **Реклама `panic_frame_counter` із DR0[31:16] звільняється** разом з активацією FW2_CCM (`#define FW2_CCM_ENABLED 1`) — CCM FC одночасно служить anti-replay для всіх пакетів (включно з panic), що закриває SEC.10 firmware-сторону автоматично.

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
- **Cold-boot (VBAT loss):** DR15 magic втрачено → **перший рубіж = Flash-floor**: рестарт з межі `0x14` монотонний без жодної ентропії. Floor законний **лише разом з негайним просуванням межі** (атомарність floor+advance — інакше повторний brownout до наступного КЕНОЗИСУ стартував би з того самого floor і повторив nonce); запис тут — один атомарний dw-program без erase (compact відкладений у безпечну фазу), тож давнє застереження «Flash-write небезпечний при кволому пост-drain заряді» знято конструкцією: відмова program безпечна — спрацьовує fallback. **Fallback (якоря нема / Flash відмовив):** FC reseed **uniform-random з HRNG** — стара TRL-6 політика без погіршення. Monotonic-across-boot RTC-джерел у цей момент немає (RTC-календар і `soldier_unix_ts` на дефолтах — wall-clock дає лише FW.20 beacon, якого ще нема — той самий стан, що Lorenz cold-start, §3.4в); SE свідомо не будимо (§3.7).
- **Залишковий ризик / severity:** при живому якорі повтор (key, nonce) **неможливий за конструкцією** (інваріант I-HW). Імовірнісний ризик `N/2²⁴` на cold-boot лишається **тільки** на fallback-шляху: перше втілення до першого КЕНОЗИСУ або стабільно мертвий Flash-program — **Severity: MEDIUM на fallback, не baseline** (CTR-reuse дає лише витік `P1⊕P2` двох 12-байтних низькоентропійних сенсорних payload'ів, **не** компрометацію ключа; forge все одно потребує per-device key). Cold-boot'и рідкісні (drain ≈ сезонний). Epoch-край: 24-bit простір одноразовий — біля `0xFFFFFF` межа клемпиться, нову nonce-епоху відкриває лише ротація ключа (FW.17, §3.8); за life-budget край недосяжний (64× margin).
- **Reseed entropy (fallback-шлях):** тільки HRNG з **retry ×3** — слабкого `HAL_GetTick` fallback **немає** (на cold-boot tick малий+передбачуваний → кластеризується між cold-boot'ами того ж пристрою). Last-resort при мертвому HRNG — `tree_did ^ tick` (DID ламає крос-девайс кластеризацію). SEC.10 panic-counter (`main.c` DR0[31:16]) — **той самий** reseed-патерн + те саме hardening при активації FW.2.
- **TRL-7 residual:** SE050 monotonic counter лишається alt-шляхом для рунга L2 (§3.7) — Flash high-water його не потребує. Silicon-residual high-water = той самий, що FW.8/FW.17: Flash-KV HAL-глю на кремнії (bench). Трекінг → `00_07 FW.2`.

> ✅ **DR15 resource-conflict — ВИРІШЕНО (2026-05-30):** FW.2 FC **володіє** `RTC_BKP_DR15` (реалізовано — `lora_ccm.h` + `firmware/soldier/main.c`; канонічно у [`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA)). FW.20-S2 anti-storm dedup-bitmap (ARCH.28) переходить на **Flash-KV store** ([`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)), бо всі 20 RTC backup-регістрів (DR0–DR19) зайняті. Стале-формулювання «DR15 наразі резерв» у [`00_07`](00_07_Action_Plan_Tracker)/[`03_02`](03_02_Queen_Gateway_Firmware) виправлено на цей вердикт.

**Конфігурація `hcryp` для CCM (AES-128):**

```c
hcryp.Init.KeySize      = CRYP_KEYSIZE_128B;   // ARCH.42 — AES-128 LoRa (SE = SE050 — §3.7)
hcryp.Init.pKey         = aes_key;             // uint32_t aes_key[4] (16 bytes, AES-128)
hcryp.Init.Algorithm    = CRYP_AES_CCM;
hcryp.Init.HeaderSize   = 8;                   // AAD = DID(4) + gossip(1) + FC24(3)
hcryp.Init.Header       = (uint32_t*)header;   // bytes [0..7] of packet
hcryp.Init.B0           = b0_block;            // CCM B0 (formatted nonce + length flags)
// Encrypt: input = sensor_payload[12], output = ciphertext[12] + MIC[8]
HAL_CRYPEx_AESCCM_Encrypt(&hcryp, sensor_payload, 12, ciphertext_with_mic, 100);
// → ciphertext_with_mic[0..11] = encrypted sensor, [12..19] = MIC
```

> **Примітка airtime:** 28-байтний пакет коштує 493.6 мс (+20% vs 21B, +9% vs 24B-rev1; SF10/DR2) — у межах duty-cycle бюджету EU868 (< 0.014% при 1 TX/година, запас 72×). Ключовий факт символьної квантизації: 24..27B коштують ОДНАКОВО (43 символи), 28-й байт відкриває новий блок (48 символів) — тому перші +3B claimants безкоштовні, а четвертий (VPD) оплачено свідомо (+12 мДж/TX), щоб не платити другий польовий міграційний цикл при приході BME280. Детальний розрахунок + wire-budget ledger — нижче.

> **Cross-ref для backend (✅ 2026-05-24; wire-rev2 ✅ 2026-06-12):** `TelemetryUnpackerService.process_ccm_chunk` реалізовано feature-flagged через `ENV["TELEMETRY_CCM_ENABLED"]=true` (default off → 21B ECB path без змін). Парсить 29-байтний chunk `[DID:4][RSSI:1][gossip:1][FC:3 BE][ciphertext:12][MIC:8]` (Queen prepends RSSI до 28B LoRa air format), виконує AES-128-CCM decrypt + MIC verify через `Cryptography::LoraCcm.decrypt(...)` (8-byte AAD=DID‖gossip‖FC24, 12-byte nonce=DID‖FC32‖4×0x00, 8-byte tag, `HardwareKey#binary_key` — 16 bytes після ARCH.42), per-DID Frame Counter SETNX `silken:ccm:fc:{did}:{fc}` TTL=25h (як SEC.10 panic guard), unpack 12-byte sensor payload (`n c C n C C n C C` = … + device_z BE / diag / vpd_index), upscale `growth_points` 5-bit (0..31) → stored 0..62 через ×2 multiplier (per-species coefficient залишається у `Wallet#lock_and_mint!` через `tree_family.carbon_sequestration_coefficient` — без змін). Споживання rev2-полів: `device_z` (≠0xFFFF → /512.0) живить numeric DCI ([`03_04 §7.1`](03_04_mruby_Lorenz_Attractor) Gate D; транзієнт — стрипається перед persist, як lorenz_temperature_c); diag-біти → метрики `silkennet_tinyml_threshold_invalid_reports_total` / `silkennet_fauna_skip_reports_total` / `silkennet_fw2_fc_degraded_reports_total` (cardinality-патерн FW.18b: per-DID атрибуція warn-логом); `vpd_index` до калібрування HW.32 у БД не пишеться. Spec coverage: `spec/services/cryptography/lora_ccm_spec.rb` (golden vectors rev2, дзеркало `ccm_kat_vectors.h`) + `spec/services/telemetry_unpacker_service_spec.rb` "FW.2 CCM 29-byte path".

> **Cross-ref для firmware (✅ 2026-05-24 doc-fix + freeze-contract impl):** RTC Backup Domain розширення — Frame Counter у DR15 (єдиний вільний слот; DR2 ❌ був помилково вказаний — насправді DR2 зайнято `has_mesh_relay`). Magic marker `FW2_FC_MAGIC_BYTE = 0x46` ('F') у high 8 бітах захищає cold-boot. Реалізовано freeze-contract у `firmware/soldier/main.c` (`Load_Frame_Counter` / `Save_Frame_Counter` / `Soldier_Build_CCM_LoRa_Packet`) та `firmware/queen/main.c` (`Queen_Parse_CCM_LoRa_Packet`) під `#define FW2_CCM_ENABLED 0` — production cycle не активний до hardware bench. Host-тести у `firmware/test/test_ccm.c` + спільні KAT-вектори `firmware/common/ccm_kat_vectors.h` (wire-rev2, регенеровано 2026-06-12) забезпечують byte-level parity з OpenSSL CCM (linked via `-lcrypto`); єдине, що залишається для HW bench — підтвердити що STM32WLE5JC `HAL_CRYPEx_AESCCM_Encrypt` дає байт-точну відповідність до OpenSSL.

> **📋 FW.2 flip-checklist (НЕ забути при `FW2_CCM_ENABLED 1`):** окрім самого дефайна і bench-атестації (`ccm_selftest` + `sym_selftest` через SWD), Queen потребує трьох RX-правок, які freeze-contract НЕ покриває: (1) `OnRxDone` жорстко відкидає `size != 16` → 28-байтні CCM-кадри впадуть ще в ISR; (2) `LoRaRxSlot.payload[16]` замалий для 28B — ринг треба розширити; (3) `Queen_Parse_CCM_LoRa_Packet` ніде не викликається з main-loop RX-гілки — треба call-site з маршрутизацією 28B-телеметрія vs 16B-control-frames (OTA/re-request лишаються ECB). Soldier-сторона: call-site `Soldier_Build_CCM_LoRa_Packet` у Фазі TX (джерела rev2-полів — шапка функції у `main.c`: `Pack_FW2_Device_Z(lorenz_z, lorenz_state_valid)` + `Pack_FW2_Diag(...)` + gossip). Бекенд-сторона flip — `TELEMETRY_CCM_ENABLED=true` (вже feature-flagged, rev2-ready). CCM-flip також РОЗГЕЙТЛЮЄ (не фліпає автоматично) пов'язані гейти — FW.17-ротація (`FW17_RATCHET_ENABLED` + Queen `FW20_Q2_CMD_RELAY_ENABLED` + backend ENV, §3.8) фліпається окремим кроком з власним e2e (bench RUNBOOK §2.6).

#### 📒 Wire-budget ledger (SSOT черги на байти LoRa-кадру)

> **Навіщо:** до wire-rev2 на байти кадру стояла тіньова черга без обліку — претенденти жили розкидано по трекеру, а 24B-freeze мовчки ВИПУСТИВ FW.18b-лічильник (freeze 2026-05-24 старший за FW.18b 2026-06-10) і вбивав gossip (per-Soldier ключ робить payload нечитним для сусідів). Цей ledger — єдине місце обліку. **Нова потреба у wire-байтах реєструється ТУТ до того, як їй пообіцяно місце.**

**Бюджетні факти (рахуються з airtime-формули нижче):**
- Символьна квантизація SF10/125kHz/CR4:5: кадри **24..27B коштують однаково** (43 символи, 452.7 мс); 28B відкриває новий блок (48 символів, 493.6 мс); наступний поріг — 32B.
- Top-байт старого FC32-поля був **завжди 0x00** (лічильник 24-бітний) — 1 безкоштовний cleartext-байт в AAD.
- Headroom після rev2: **+3 байти безкоштовно** (28..31B — той самий 48-символьний блок; 32B відкриває наступний). Біти: `mesh_ctrl.ttl:4` тримає max 15 hop при потребі 0..5 (1 біт можна реклемувати), `vpd_index` до HW.32-калібрування = de-facto резервний байт.

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
- **Climate frame (HW.32 сирі RH/тиск):** окремий періодичний кадр (НЕ per-cycle поле) — Queen маршрутизує за довжиною (16B control / 28B телеметрія / інша довжина = climate). Формат проєктувати при HW.32.
- **E.63 EMA-delta_t (точний stateless метаболічний DCI):** `m(wire_dT)==GP` потребує, щоб wire ніс САМЕ EMA-згладжений delta_t, з якого рахувались GP. Кандидат rev3: «замінити семантику наявного dT-поля на EMA» (0 байтів, але бекенд втрачає raw dT) vs «+2B EMA-поле» (28..31B — той самий символьний блок, задарма) — рішення за founder'ом ([`00_07` — E.63](00_07_Action_Plan_Tracker)).

**Дисципліна ревізії:** формат ревізується ЛИШЕ до польового фліпу (`FW2_CCM_ENABLED` все ще 0 — обидві прошивки і бекенд за гейтами, тож rev2 коштував код+тести+KAT-регенерацію, нуль міграції). Після фліпу будь-яка зміна = повний міграційний цикл (фліт у полі) → нові претенденти збираються тут і їдуть пакетом у rev3.

#### 🤖 Верифікація LoRa Airtime Budget: 16B (ECB) vs 24B/28B (CCM) vs 21B (поточний raw)

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

**Висновок:** Перехід з 21B ECB → 28B CCM (wire-rev2) збільшує airtime на **+20%** (+82 мс), duty cycle на **+0.003%**, енергоспоживання на **+24 мДж/TX** — з них +12 мДж купують дім для ВСІХ відомих wire-претендентів (ledger вище), що знімає другий польовий міграційний цикл. Зміна key size з 256→128 (ARCH.42) **не змінює** airtime (block-cipher block size = 128 bit обох випадках; зменшується лише кількість Round-функцій з 14→10, що дає ~25% швидший AES-операцію — нехтовно). Усі параметри залишаються **далеко в межах** EU868 duty cycle (1%) та енергобюджету Soldier (2.0% заряду EDLC per TX). **LoRa airtime budget верифіковано: AES-128-CCM 28B (wire-rev2) схвалено founder'ом 2026-06-12.** ✅

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

- **Рекомендоване рішення (після ARCH.42 Варіант B):** Перейти на **AES-128-CCM** з 28-байтним пакетом (wire-rev2) — вирішує §ECB Mode та §MAC/MIC одночасно (див. §ECB Mode вище для повної специфікації формату з Frame Counter + MIC).
- Альтернатива: **AES-128-GCM** (надає одночасно конфіденційність + автентифікацію + nonce).
- Або: додати **HMAC-SHA256 MIC** (4 байти суфіксу) до кожного LoRa-пакету, скоротивши сенсорний payload до 12 корисних байтів.
- LoRaWAN-нативний вибір: **AES-128-CMAC** (стандарт LoRaWAN MAC layer) — спрощує bridging до Helium/Sigfox/Things Network (ARCH.34).

**Блокує:** Довіра до телеметрії, Proof of Growth Pipeline (05_02), Hardware Security Audit.

---

### HRNG Fallback — покращена ентропія (Виправлено)

✅ Reuse закрито; **harden 2026-05-29** (cross-reboot/flush uniqueness + host-тести). 🟡 Residual (predictability) — low-severity, нижче.

**Реалізація:** fallback-IV винесено у pure-функцію `firmware/queen/coap_iv.h` →
`coap_fallback_iv_word(i, tick, uid_hash, unix_ts, flush_seq)`, host-тестовану в
`firmware/test/test_encryption.c` (per-word / per-device / cross-reboot /
cross-flush uniqueness). Нормальний шлях — HRNG (CSPRNG); fallback спрацьовує лише
при апаратній відмові RNG.

```c
// coap_iv.h — uniqueness-preserving degradation (НЕ CSPRNG)
batch_iv[i] = (tick + i)                  // sub-second + per-word
            ^ (uid_hash << i)             // per-DEVICE (djb2 queen_uid / STM32 HW UID)
            ^ (unix_ts * 65537U)          // cross-REBOOT (server-synced wall-clock)
            ^ (flush_seq * 2654435761U)   // cross-FLUSH (monotonic per-boot)
            ^ ((uint32_t)i * RNG_FALLBACK_XOR_MASK);
```

**IV Reuse** унеможливлено по всіх осях: `uid_hash` (per-device, mass blackout-reboot guard) + `queen_unix_ts` (cross-reboot) + `coap_flush_seq` (cross-flush).

> 🟡 **Чесний residual (predictability):** fallback-IV **унікальний, але передбачуваний** (uid/час/лічильник вгадувані). Сувора вимога CBC — *непередбачуваність*; але загроза тут **low-severity**, бо CoAP-батч несе власну телеметрію Королеви → **немає chosen-plaintext вектора** (BEAST-патерн непридатний), отже операційна вимога — саме *uniqueness* (досягнуто). Повна unpredictability = key-derived IV `E_key(counter)` через AES-engine (окремий CRYP-крок + SEC.8 restore) — **bench-gated** roadmap-пункт. Normal-path HRNG вже непередбачуваний.

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
  hcryp.Init.pKey        = aes_key;              // Per-device HKDF-derived LoRa key (RAM mirror, populated by Load_AES_Key() at boot — see §3.4а; uint32_t aes_key[4] = 16 bytes)
  hcryp.Init.Algorithm   = CRYP_AES_ECB;         // ECB transitional — TARGET: CRYP_AES_CCM після FW.2 28B-packet rollout (wire-rev2)
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
| `pKey` | `&aes_key[0]` | RAM-адреса per-device HKDF-derived ключа (завантажується з Protected Flash Sector через `Load_AES_Key()` — §3.4а, §Hardcoded AES Key closed via FW.1) |

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
**Цільовий режим (FW.2):** AES-128-CCM · **Розмір:** 28 байтів (wire-rev2: header 8B + ciphertext 12B + MIC 8B) — див. §ECB Mode

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
|   0    |   0    | PANIC_FLAG_BIT |PANIC_TTL| FW_HI | FW_LO  |CTR_HI  |CTR_LO  |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

- Byte 7 = `0xFF` → код паніки (максимальна акустична подія)
- Byte 10 = `PANIC_FLAG_BIT` (0x80) → **[FW.29]** однозначний disambiguation panic vs saturated acoustic
- Byte 11 = `PANIC_TTL` (= 5, збільшений TTL для досягнення Queen через більше стрибків)
- Bytes 12-13 = `firmware_version_id` BE (FW.22)
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
Підписаний (L1): [ver:1=0x01][queen_unix_ts:4 BE][flush_seq:4 BE]
                [IV:16][Encrypted Data: N×16][sig:64]          довжина % 16 == 9
```

**L1 Queen-attestation** (рунг драбини довіри — канон [`05_02`](05_02_Proof_of_Growth_Pipeline) «Trust-origin ladder»): Королева підписує батч **Ed25519** (software, Monocypher; сім'я `EDSK` у Protected Flash — §3.1). Encrypt-then-sign: бекенд (`UnpackTelemetryWorker`) верифікує підпис проти зареєстрованого при provisioning `HardwareKey.ed25519_public_key_hex` **ДО** decrypt — жодних padding-оракулів.

- **Повідомлення підпису:** `"SLKN-QATT1" ‖ uid_len:1 ‖ uid ‖ <payload без хвостового sig>` — доменний тег проти cross-protocol reuse; UID (з CoAP URI-Path) вшито у підпис → батч однієї Королеви не сплайснути в URI іншої.
- **Розрізнення форм** — residue довжини (legacy ≡ 0, підписаний ≡ 9 mod 16): детерміністичне, без magic-вгадування проти випадкового IV. Сім'я не прошита → Queen шле legacy = старий флот живе без змін.
- **Anti-replay:** SHA256(sig) як nonce (Redis `SET NX`; Solid-Cache fallback — патерн M2M/S6.1; TTL-вікно — `UnpackTelemetryWorker::QATT_NONCE_TTL`). `ts`/`seq` — observability + майбутній high-water (Queen без RTC, [`03_02 §5а`](03_02_Queen_Gateway_Firmware) — `ts=0` легітимний); **residual:** replay після TTL-вікна — свідомий, строго кращий за L0 «replay будь-коли».
- **Невалідний підпис** → drop + `attest_bad_signature` метрика (Grafana-алерт); **підписаний без зареєстрованого pubkey** → обробка як L0 + `attest_no_pubkey` (суворість нічого не дає, поки L0 приймається).
- **Загроза-модель чесно:** L1 доводить gateway-origin (захист від backend-compromise/injection), **не** operator-fraud — то L2 (драбина у [`05_02`](05_02_Proof_of_Growth_Pipeline)).

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

### 2.4 Queen → Soldier: OTA LoRa Broadcast (AES-128-ECB)

**Режим:** AES-128-ECB · **Розмір:** 16 байт (LoRa-канал, post-ARCH.42)

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

> ✅ **Post-FW.1 status (2026-05-02) + ARCH.42 update (2026-05-23):** Hardcoded ідентичний ключ **видалено**. Кожен Soldier отримує **унікальний** per-device LoRa AES-128 ключ (16 байт), а Queen додатково отримує AES-256 CoAP ключ (32 байти) — обидва через HKDF-SHA256 деривацію з `PROVISIONING_MASTER_KEY` під час factory provisioning. Ключ зберігається у **Protected Flash Sector** (`FLASH_KEY_ADDR`, RDP Level 1/2-захищений) і завантажується у RAM функцією `Load_AES_Key()` при boot. Деталі деривації — §3.4а HKDF Key Derivation Protocol Design; backend mirror — `HardwareKey#aes_key_hex` (AR Encryption non-deterministic, conditional length: 32 hex для Tree LoRa, 64 hex для Gateway CoAP).

| Параметр | LoRa-ключ (Soldier + Queen) | CoAP-ключ (Queen only) |
|----------|------------------------------|------------------------|
| **Тип зберігання** | Protected Flash Sector, magic `"KEYL"` = `0x4B45594C` | Protected Flash Sector (окремий slot), magic `"KEYC"` = `0x4B455943` |
| **Адреса** | `FLASH_KEY_ADDR` | `FLASH_COAP_KEY_ADDR` (тільки Queen) |
| **Розмір** | **128 біт (16 байт, 4 × uint32_t)** — ARCH.42 | 256 біт (32 байти, 8 × uint32_t) |
| **Захист** | RDP Level 1 (виробництво) / RDP Level 2 (необоротний final lock) — див. §3.3 | Те саме |
| **Ротація** | Hash-Ratchet §3.8 (host-готово, активація CCM-gated) — [`00_07` — FW.17](00_07_Action_Plan_Tracker) | Те саме |
| **Унікальність** | **Унікальний per-device** через HKDF(`PROVISIONING_MASTER_KEY`, salt=`device_uid`, info=`"silken-aes-128-lora-key"`) | HKDF(`PROVISIONING_MASTER_KEY`, salt=`device_uid`, info=`"silken-aes-256-device-key"`) |
| **Завантаження у RAM** | `Load_AES_Key()` на boot → `aes_key[4]` (LoRa-режим) | `Load_AES_Key()` на boot → `coap_key[8]` (динамічне MX_CRYP re-init для CoAP) |

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
3. Записати у Bitwarden / 1Password / Kamal secrets / Akash SDL (див. [`06_04`](06_04_Secrets_Checklist)).
4. Re-deploy — initializer перезапустить guard з боку production.

**Сервіс автоматично запускається при кожному production boot — будь-яка ротація, яка пройшла повз runbook, буде заблокована до старту HTTP сервера.** Це й закриває SEC.9 🤖.

### 3.2 Secure Element (ATECC608B) — після ARCH.42

> ⚠️ **SUPERSEDED → §3.7 (SEC.6 RESOLVED 2026-06-07):** SE = **NXP SE050** (true-DePIN «голос дерева» — non-extractable Ed25519), НЕ ATECC608B (реверс рішення 2026-05-23). Нижче (§3.2 + §3.4 Гілка B) лишено як **legacy ATECC provisioning-патерн** — factory-integration механіка **reusable для SE050**, тож не видаляється; чинне рішення, ціна, slot-map, ladder — **§3.7**.

> 🎯 **ARCH.42 Variant B (2026-05-23) — legacy, SUPERSEDED → SE050 (§3.7):** початковий вибір був ATECC608B Microchip (~$0.85/unit @ 10k MOQ) як єдиний SE для (а) LoRa AES-128 ключ у Slot 0, (б) ECC P-256 device identity у Slot 1, (в) device cert у Slot 2, (г) OTA HMAC-SHA256 ключ у Slot 3. AES-128 — апаратний maximum ATECC608B. **Чинне рішення — NXP SE050** (non-extractable Ed25519 «голос дерева», SEC.6 RESOLVED — §3.7); ATECC slot-провіжининг-патерн нижче лишено як reusable для SE050.

Поточна Гілка A (RDP Level 2 + Protected Flash) залишається активною baseline для pilot/<1000 unit deployments. Гілка B (ATECC608B) активується для mass production > 10k unit та urban deployments — див. §3.4 Гілка B та §3.7.

```
Factory Flashing (поточна Гілка A, TRL 6/7 — pilot ≤ 10k):
  Rails Backend → POST /api/v1/provisioning/register → {device_uid}
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

### 3.4 Стратегія Масового Виробництва (Factory Flashing Pipeline)

При переході від прототипу до партії 10 000+ вузлів конвеєр на заводі виглядає так. **Дві альтернативні гілки:** (A) ключ у protected Flash sector STM32 (TRL 6/7, mass production до ~10k unit), (B) ключ у Secure Element ATECC608B/STSAFE-A110 (mass production > 10k або high-value urban deployments — див. §3.7 для повної оцінки SE).

#### Гілка A — Protected Flash Sector (TRL 6/7, baseline)

```
[Завод]
  1. Прошивка: масив aes_key[8] = {0,0,...,0} (порожній placeholder)
     Robot Programmer → Flash firmware → Board

  2. Provisioning: унікальний ключ для конкретного MCU
     Rails Backend → POST /api/v1/provisioning/register → {device_uid}
     Backend → генерує unique_key (HKDF від master_key + device_uid)
     Robot → записує unique_key у захищений сектор Flash (0x0803E000)

  3. Lock: апаратне блокування
     STM32CubeProgrammer (CLI) → Set RDP Level 1 (або Level 2)
     → необоротне блокування SWD зчитування
     → активація WRPROT на key sector + seed sector + role sector

  4. Пакування
     Нанести лак → Встановити магніт Shipping Mode → Пакет → Ліс
```

#### Гілка B — ATECC608B / STSAFE-A110 Secure Element (mass production > 10k, SEC.6)

```
[Завод]
  1. Reflow PCBA (ATECC608B запаяний; config zone та data zone обидві unlocked)
     Robot Programmer → Flash base firmware (без AES key, з ATCA-комуникатором) → Board

  2. Power-up self-test:
     STM32 → I²C ping ATECC608B → перевірити serial_number (унікальний 9 байт)
     Якщо ATECC608B не відповідає → fail → reject board (заводський QC)

  3. Provisioning (один HTTPS round-trip):
     STM32 → POST /api/v1/provisioning/register
       { device_uid: HAL_GetUID(), atecc_serial: <9-byte hex>, firmware_version: <ver> }
     Rails Backend:
       - Зберігає (device_uid, atecc_serial) у HardwareKey (для tamper-detect: підміна
         чіпа на іншому boards тригерить mismatch при наступному провіженінгу)
       - Деривує HKDF як у §3.4а:
           aes_key  = HKDF_SHA256(master_key, device_uid, "silken-aes-128-lora-key")
           ota_hmac = HKDF_SHA256(master_key, device_uid, "silken-ota-hmac-v1")
       - Генерує ECC P-256 keypair (для майбутнього peaq DID signing, ARCH.27 evolution)
       - Видає device cert (X.509, підписаний intermediate CA Silken Net)
     Response: { aes_key, ota_hmac_key, ecc_priv, ecc_pub_cert_pem }

  4. STM32 → ATECC608B: write keys per slot mapping (cross-ref §3.7):
     atcab_write_zone(SLOT 0, aes_key,  32B)    # AES LoRa session key
     atcab_write_zone(SLOT 1, ecc_priv, 32B)    # ECC P-256 private (peaq DID signing)
     atcab_write_zone(SLOT 2, cert_der, 64B)    # X.509 device cert
     atcab_write_zone(SLOT 3, ota_hmac, 32B)    # FW.23 OTA image HMAC verification
     # Slot 4..15 — reserved for key rotation (FW.17 Hash Ratchet KDF)

  5. Lock (irreversible на ASIC рівні):
     atcab_lock_config_zone()    # Config (slot policies) → permanent
     atcab_lock_data_zone()      # All slot writes → forbidden forever
     # ⚠️ Після цього кроку ключі НЕ можуть бути ні прочитані, ні переписані —
     # навіть з фізичним доступом, navigate ASIC шар.

  6. Lock STM32:
     STM32CubeProgrammer → Set RDP Level 1 (або Level 2 після SEC.2 верифікації OTA)
     → SWD заблоковано → firmware не змінити

  7. Пакування (як у Гілці A):
     Лак → Shipping Mode магніт → Box → Field
```

**Подвійний lock (defense in depth, тільки Гілка B):**

| Шар захисту | Що блокує | Атака, від якої захищає |
|-------------|-----------|--------------------------|
| **ATECC608B data zone lock** | Read/write ключів | DPA/EM side-channel, fault injection (chip self-erase при detection), chip swap |
| **STM32 RDP Level 1/2** | SWD flash dump | Прямий read firmware через debug port |
| **Backend (atecc_serial pin)** | ATECC swap на іншому board | Адверсар викрадає ATECC з одного board і ставить на інший — backend reject при провіженінгу через mismatch (device_uid, atecc_serial) пари |

**Latency impact (Гілка B vs A):** ATECC608B AES-ECB ~1.5 мс/блок vs MCU HAL_CRYP ~10 µs. Для одного 16/28-байтного LoRa пакета — нехтовно. Для CBC batch 50 × 16 байт = 800 байт — додаткові ~75 мс на flush (CoAP flush триває кілька секунд у будь-якому разі).

**Power impact (Гілка B):** ATECC active ~69 мкДж/пакет → ≈0.2% active-циклу Soldier (точні числа — §3.7, дзеркало SSOT там). ⚠️ Sleep 150 нА always-on **з'їдає весь запас Сценарію C** → SE обов'язково за load-switch гейтом (розрахунок і вимога — §3.7). Енергія active **мала, але не вирішальна**: чи робить SE AES щопакета, чи лише provisioning (а streaming AES — на вбудованому radio-AES STM32) — окрема вісь компромісу (tamper-resistance LoRa-ключа ⟷ latency/ідіом), повний розбір — §3.7 (SEC.14).

**Cost impact (Гілка B):** +$0.60/unit (ATECC608B 10k MOQ) або +$0.85/unit (STSAFE-A110). Cross-ref §7.2 unit economics.

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
- Ключ ніколи не існує в коді репозиторію — лише в Rails Vault (`HardwareKey`, encrypted at rest)
- Якщо Backend-side master key компрометовано → перевипуск всіх ключів через field re-flash (Гілка A) або re-provisioning + ATECC re-lock через RMA (Гілка B, болючіше)

**Для поточного прототипу (TRL 6):** Гілка A з protected Flash sector. Гілка B активується перед першим mass production batch (рішення прив'язане до BOM freeze, cross-ref [`07_02 §8.1`](07_02_Unit_Economics_and_BOM)).

**Зворотність:**
- Гілка A → B: можлива (re-flash MCU + добавити ATECC до PCBA = новий PCB revision)
- Гілка B → A: **неможлива** (ATECC config zone locked permanently — board залишається B forever)

> **Cross-ref:** §3.4а HKDF derivation (детальна криптографія), §3.6 RDP Level 2 procedure (irreversible lock checklist), §3.7 ATECC608B integration assessment (slot mapping, alternatives, BOM impact), [`00_07` — SEC.3](00_07_Action_Plan_Tracker), [`00_07` — SEC.6](00_07_Action_Plan_Tracker), [`00_07` — FW.1](00_07_Action_Plan_Tracker).

---

### 3.4а HKDF Key Derivation Protocol Design 🤖

> **Cross-ref:** [`00_07` — FW.1](00_07_Action_Plan_Tracker) — дизайн завершено ✅

**Мета:** замінити один hardcoded ключ на МЕРЕЖУ унікальних ключів, де кожен пристрій має свій, а компрометація одного не розкриває решту. Весь дизайн базується на HKDF (RFC 5869) — стандартному HMAC-based Key Derivation Function.

#### Криптографічна основа: HKDF-SHA256 — два info-strings після ARCH.42

```
LoRa-канал (Soldier + Queen LoRa-сесія) — ARCH.42 default:
  HKDF(master_key, device_uid, "silken-aes-128-lora-key") → 16 bytes (AES-128)

CoAP-магістраль (Queen ↔ Rails) — тільки на Gateway-рядках HardwareKey:
  HKDF(master_key, device_uid, "silken-aes-256-device-key") → 32 bytes (AES-256)

Де:
  master_key  = 32-байтний секрет (генерується HRNG, зберігається у Rails Vault)
  device_uid  = 8-байтний унікальний ідентифікатор пристрою (STM32 UID96 або DID)
  info        = ASCII string (domain separation — два різні KDF outputs з одного master)
  output len  = 16 байт (LoRa) АБО 32 байти (CoAP)
```

> **Domain separation:** Два різні info-strings гарантують, що LoRa та CoAP ключі НЕ корелюють криптографічно — компрометація 16-байтного LoRa-ключа конкретного дерева **не дає жодної інформації** про 32-байтний CoAP-ключ Queen, який обслуговує це дерево. Те саме для `OtaHmacKeyService` (info `"silken-ota-hmac-v1"`) та `SilkenNet::SeedDerivation` (info `"silken-lorenz-seed|<DID>"`).

**Властивості HKDF:**
- Якщо зловмисник знає `unique_device_key[i]`, він не може відновити `master_key` або `unique_device_key[j]` — однонаправлена функція
- Два пристрої з однаковим `device_uid` отримають однаковий ключ (детерміновано) — важливо для Queen, яка повинна знати ключ кожного Soldier у своєму кластері
- SHA-256 рахується програмно (backend — OpenSSL; Soldier cold-start — pure-C `silken_sha256.h`, FW.30): STM32WLE5JC має апаратний AES, але **не** HASH/SHA-блок

#### Схема Provisioning (повна послідовність)

```
═══════════════════════════════════════════════════════════════════════
STEP 1: Генерація MASTER KEY (одноразово, до виробництва)
═══════════════════════════════════════════════════════════════════════

Backend (Rails):
  master_key = SecureRandom.bytes(32)       # CSPRNG, 256 bits
  # Зберегти у HardwareKey master record (id: 0, device_uid: "MASTER")
  # AR Encryption: at-rest encryption у Vault (HardwareKey#aes_key_hex)
  # ⚠️ НІКОЛИ не комітити master_key у репозиторій!
  # Зберегти у Bitwarden / 1Password / HashiCorp Vault (апаратний HSM у production)

═══════════════════════════════════════════════════════════════════════
STEP 2: Factory Flashing (конвеєр на заводі)
═══════════════════════════════════════════════════════════════════════

[Заводський стенд]
  a) Прошивка базового firmware:
     STM32CubeProgrammer --write firmware_base.hex   # aes_key[8] = {0,0,...,0}
     Firmware reads device_uid = HAL_GetUID() → 12 bytes (STM32 unique ID)
     DID = "SNET-" + hex(CRC32(device_uid))

  b) Provisioning запит (UART або WiFi через тестовий стенд):
     POST /api/v1/provisioning/register
       { device_uid: "<hex_uid>", firmware_version: <ver> }

  c) Backend: ProvisioningController#register (Zero-Trust — keys НЕ повертаються в response)
     # LoRa key (Tree або Gateway):
     lora_key  = HKDF_SHA256(master_key, device_uid, "silken-aes-128-lora-key")  # 16 bytes
     # CoAP key (тільки Gateway — для batch flush до Rails):
     coap_key  = HKDF_SHA256(master_key, device_uid, "silken-aes-256-device-key") # 32 bytes  [Gateway only]
     HardwareKey.create!(device_uid:, aes_key_hex: lora_key.unpack1("H*"))   # 32 hex для Tree
     # Gateway: HardwareKey.create!(aes_key_hex: coap_key.unpack1("H*"))     # 64 hex для Gateway
     Response: { did: "SNET-XXXXXXXX" }   # Zero-Trust — NO keys у response

  d) Заводський стенд записує унікальний ключ (Гілка A — Protected Flash):
     STM32CubeProgrammer --write-option-bytes key_address=0x0803E000 key=<hex>
     # 0x0803E000 = FLASH_KEY_ADDR (Protected Flash Sector, perma-protected)
     # АБО ATECC608B Slot 0 (Гілка B після ARCH.42 — Secure Element §3.7)

  e) Lock:
     STM32CubeProgrammer --set-rdp-level 1    # Pilot batch
     # (Level 2 після верифікації OTA — SEC.2)

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
STEP 4: Queen — знає ключі ВСІХ своїх Soldiers
═══════════════════════════════════════════════════════════════════════

Варіант A (рекомендований для TRL 7):
  Queen теж provisioned із ключем:
    queen_key = HKDF_SHA256(master_key, queen_uid, "silken-aes-128-lora-key")
  Але для декриптування Soldier-пакетів потрібна інша стратегія.

Варіант B (production-ready):
  Queen зберігає ALL keys у своїй Flash (CIFO-based key table):
    key_table[50] → 50 × 32 bytes = 1600 bytes (допустимо для 64KB Flash)
    Завантажуються через CoAP downlink від Rails після provisioning

Варіант C (альтернатива, ATECC608B):
  Queen містить ATECC608B → Queen знає master_key у захищеному чіпі →
  обчислює HKDF(master_key, incoming_DID) on-the-fly під час decrypt

  ⚠️ Варіант C потребує завантаження master_key у ATECC608B на заводі —
  одна точка компрометації, але захищена апаратно.
```

#### Rails Backend — API та зберігання (post-ARCH.42)

```ruby
# app/services/hardware_key_service.rb — два derivation methods:

LORA_KEY_INFO = "silken-aes-128-lora-key".freeze   # ARCH.42 — Tree LoRa channel (16 bytes)
COAP_KEY_INFO = "silken-aes-256-device-key".freeze # Gateway CoAP-to-Rails channel (32 bytes)

# LoRa AES-128 ключ (Tree або Gateway LoRa-сесія)
def self.derive_lora_key(device_uid)
  master_key = fetch_master_key_from_vault!
  prk  = OpenSSL::HMAC.digest("SHA256", master_key, device_uid)
  okm  = OpenSSL::HMAC.digest("SHA256", prk, LORA_KEY_INFO + "\x01")
  okm[0, 16]  # 128 bits — AES-128
end

# CoAP AES-256 ключ (тільки Gateway — для batch flush до Rails)
def self.derive_device_key(device_uid)
  master_key = fetch_master_key_from_vault!
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

#### Firmware — зчитування ключа з Protected Flash Sector (AES-128 LoRa)

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

#### [FW.30] Lorenz K_seed — зчитування з Protected Flash Sector

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

#### [ARCH.27] Node Role — окремий Flash slot після K_seed (2026-05-03)

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

#### Захист Flash Key Sector (WRPROT)

```
STM32CubeProgrammer → Option Bytes → Write Protection:
  Сектор 0x0803E000 (Page 127, якщо 4KB sectors) → Write-Protected ON

Результат: навіть якщо SWD відкритий (RDP Level 0 у R&D) —
  запис у ключовий сектор неможливий без зняття WRPROT
  (зняття стирає відповідну сторінку Flash!)
```

#### Безпекові параметри (post-ARCH.42)

| Параметр | LoRa-канал (Tree + Queen) | CoAP-канал (Queen only) | Обґрунтування |
|----------|---------------------------|--------------------------|---------------|
| KDF алгоритм | HKDF-SHA256 (RFC 5869) | HKDF-SHA256 | Стандарт NIST SP 800-56C; SHA256 — software (backend OpenSSL / Soldier pure-C `silken_sha256.h`) |
| Master key size | 256 bits | 256 bits | Master input — однаковий 256-bit secret для обох KDF-outputs |
| Output key size | **128 bits (16 bytes)** — ARCH.42 | 256 bits (32 bytes) | LoRa: AES-128 (свідомий вибір, **не** SE-constraint — SE050 вміє 256, §3.7); CoAP: AES-256 (Queen Flash, no SE constraint) |
| Info string | `"silken-aes-128-lora-key"` | `"silken-aes-256-device-key"` | Domain separation — два різні KDF outputs ortho |
| Master key storage | Rails Vault (AR Encryption) + HSM у production | Same | Never in-repo |
| Device key storage | Protected Flash (LoRa magic `"KEYL"`) → SE050 Slot 0 (Гілка B, §3.7) | Protected Flash (CoAP magic `"KEYC"`) — Queen MCU only | Фізичний захист; AES-128 на LoRa — свідомий вибір, не SE-constraint (ADR §3.7); CoAP-key лишається у MCU Flash (канал не через SE) |
| Backup/rotate | Dual-key grace period (HardwareKey#previous_aes_key_hex) | Same | Zero-downtime rotation |
| Post-quantum margin | $2^{128}$ (post-Grover ≈ $2^{64}$ — захищається ratchet `[FW.17]` + PQC bridge §10) | $2^{256}$ (post-Grover ≈ $2^{128}$ — абсолютний квантовий імунітет) | Чому CoAP залишається 256: інфраструктурне TLS-termination через Cloudflare X25519+Kyber вже доступне (post-quantum hybrid) |

> **Cross-ref:** SEC.3 Factory Flashing pipeline, SEC.6 Secure Element (SE050, §3.7), SEC.2 RDP Level 2, **ARCH.42 ✅ resolved 2026-05-23 (Variant B)**, **§10 PQC Migration Roadmap**.

---

### 3.4в Lorenz K_seed Derivation (SEC.11) 🤖

> **Cross-ref:** [`00_07` — SEC.11](00_07_Action_Plan_Tracker) — ✅ DONE 2026-05-02 (hard cutover, pre-prod)

**Мета:** криптографічно стійкий механізм виведення початкової точки `(x₀, y₀, z₀)` атрактора Лоренца для кожного Soldier-вузла. Замінює попередній підхід "raw DID як seed", який мав фундаментальні безпекові вади і робив `check_z_divergence!` категоричним замість числового. Деталі — у [`03_04 §2.1 + §3` Крок 1](03_04_mruby_Lorenz_Attractor); тут — лише cryptographic protocol layer.

#### Чотири фундаментальні вади до SEC.11

1. **Публічний seed → публічна траєкторія.** DID їде відкритим текстом у заголовку LoRa-пакета (`[DID:4]`, поза AES). Атакер з open-source формулою Лоренца обчислює `Z(DID, temp, acoustic, dt, vcap)` для будь-якого дерева → підробляє телеметрію з валідним StatusByte, `check_z_divergence!` мовчить.
2. **Кореляція сусідніх DID.** Provisioning видає DID послідовно (`SNET-AC0001AB`, `…AC`). Перші ~30 ітерацій Ейлера дві сусідні крони мають майже ідентичні траєкторії → знижена статистична ентропія.
3. **Семантична помилка категорій.** DID — *identifier*. Identifier-as-key — класичний антипатерн, бо identifier має бути входом до KDF, ніколи виходом.
4. **Відсутність forward secrecy.** Одне дерево все життя стартує з тієї ж точки. Один підроблений рецепт працює довічно.

#### Прийнятий дизайн: гібрид A + B + D

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
    aes_key_hex:     <derived per §3.4а>,
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
  epoch_day  = telemetry_log.created_at.to_i / 86400
  (x₀,y₀,z₀) = SilkenNet::SeedDerivation.derive_initial_state(K_seed_bin, epoch_day)
ELSE:
  cold_start_flag = false
  (x₀,y₀,z₀) = (prev.lorenz_state_x, prev.lorenz_state_y, prev.lorenz_state_z)

server_z, x_f, y_f, z_f = Attractor.calculate_z_from_state(
                            x₀, y₀, z₀, temp, acoustic, delta_t_s, vcap_mv)
log.update!(lorenz_state_x: x_f, lorenz_state_y: y_f, lorenz_state_z: z_f,
            cold_start_flag: cold_start_flag)
```

#### Криптографічні гарантії в одному рядку

> `K_seed` ніколи не залишає пристрій і сервер. `(x₀, y₀, z₀)` — функція від (`K_seed`, `epoch_day`). DID у формулі **не існує** як seed — він використовується лише як `info`-string у HKDF (namespace separator), що криптографічно безпечно і не вносить уразливості.

#### Threat model post-SEC.11

| Загроза | Захист |
|---------|--------|
| Sniff LoRa-пакет → відтворити Z | ❌ (без `K_seed` Z непередбачуваний) |
| Compromise одного `K_seed` (фізичний доступ до пристрою) | ⚠️ Один пристрій уразливий ≤ 24 год; інші — ні |
| Compromise `PROVISIONING_MASTER_KEY` | 🚨 Каскадне — потрібна окрема rotation strategy (SEC.9) |
| Replay вчорашнього валідного пакета | ❌ (`epoch_day` змінився, Z більше не валідний) |
| Підроблений `cold_start_flag = true` від device | Mitigation: server відкидає `cold_start` якщо < 7 днів від попередньої телеметрії |
| ARM ↔ x86 IEEE-754 drift > 0.001 | Емпірично < 1e-12; tolerance band 9 порядків запасу при flip на numeric |

#### Реалізація

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

### 3.4б OTA Authentication Protocol Design (FW.23) ✅ Реалізовано (2026-05-02)

**Статус реалізації:**

| Шар | Файл | Що зроблено |
|-----|------|-------------|
| Backend (HKDF) | `app/services/ota_hmac_key_service.rb` | `OtaHmacKeyService.fetch_for(cluster_id)` — HKDF-SHA256, info `"silken-ota-hmac-v1"`, raise `SecurityError` без `PROVISIONING_MASTER_KEY` (SEC.11 hard cutover) |
| Backend (signing) | `app/services/ota_packager_service.rb` | `compute_hmac_tag(bytecode, version_id, lora_total_chunks, cluster_id:)` + `build_hmac_trailer_chunks(tag, lora_total_chunks, version_id)` (3× `[0x9B][seg_idx:2 BE][total:2 BE][hmac:11]` + seg 4 `[0x9B][0x0004][total:2 BE][version_id:4 BE][PAD:7]`) + `prepare(..., cluster_id:)` opt-in з `manifest[:hmac_signed/lora_total_chunks/total_packages/hmac_cluster_id]` |
| Firmware Queen | `firmware/queen/main.c` | Stateless relay: `Handle_CoAP_Command` зберігає 4 trailer-блоки (3 печатки + версія) у `pending_ota_hmac_chunks[4][16]`, ready-bitmask = `0x0F`; reflex broadcast loop додає Phase 1 (trailer) після Phase 0 (bytecode); 60 ms pacing |
| Firmware Soldier | `firmware/soldier/main.c` | `Load_Ota_Hmac_Key` (K_ota з Protected Flash `0x0803E800`, magic "KOTA"; fail-safe `ota_hmac_key_valid=0`) + `Parse_HMAC_Trailer_Chunk` (seg 1..3 → `received_hmac_tag`, seg 4 → `received_ota_version`) + `OTA_Try_Finalize` (**реальний** `Silken_Hmac_Sha256_Concat(K_ota, body‖version_be‖total_be)` → `OTA_Verify_Dual_Gate`: Gate 1 magic "RITE" + Gate 2 constant-time HMAC) — фіналізація з обох гілок (тіло 0x99 / печатка 0x9B), бо печатка приходить ПІСЛЯ тіла; APPLY лише при всіх 4 трейлер-чанках; fail-safe magic-wipe при REJECT |
| Backend specs | `spec/services/ota_hmac_key_service_spec.rb`, `spec/services/ota_packager_service_spec.rb`, `spec/integration/ota_firmware_flow_spec.rb` | determinism / domain separation / anti-replay / anti-truncation / per-cluster isolation / manifest metadata / package ordering / version-on-wire (seg 4 = firmware.id BE) / blank input / SEC.11 |
| Firmware host-tests | `firmware/test/test_soldier_logic.c`, `test_queen_logic.c` | trailer assemble (in-order/out-of-order/version chunk/all-4=0x0F) / reject seg_idx>4 / **real HMAC compute** (`Silken_Hmac_Sha256_Concat` ≡ one-shot ≡ OpenSSL) / `OTA_Try_Finalize` APPLY·WAIT·REJECT(tampered/version-mismatch/no-key) / dual-gate magic+hmac / constant-time first/last byte / Queen relay 4 segments / wrong marker reject / overwrite same segment |

**Статус: реальний compute — ✅ зашито (2026-06-11).** Soldier dual-gate **більше не інертний**: `OTA_Try_Finalize` обчислює `Silken_Hmac_Sha256_Concat(K_ota, body ‖ version_id_be ‖ total_be)` (pure-C `silken_sha256.h`, той самий шлях, яким FW.30 закрив seed-HMAC; byte-parity vs OpenSSL транзитивно через `_Concat ≡ one-shot`; **mbedTLS не потрібен**) і пускає у `OTA_Verify_Dual_Gate` — підмінений bytecode з валідним CRC32 тепер **відсікається** на Gate 2. Дві опори, яких бракувало, додано: (1) `Load_Ota_Hmac_Key` — K_ota з Protected Flash `0x0803E800` (magic "KOTA", окрема сторінка 125 за `KEYL`-сторінкою; первісний `0x0803D000` колідував із Flash-KV регіоном — переїзд 2026-06-11, [`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA); `ota_hmac_key_valid=0` ⇒ жоден OTA не застосовується — fail-safe); (2) `version_id` на дроті — **4-й `[0x9B]` trailer-чанк** (seg_idx=4, `version_id:4 BE`), бо у 16-байтну печатку-сегмент він не влазив. Bonus-fix: фіналізація тепер спрацьовує з обох RX-гілок (тіло 0x99 / печатка 0x9B) — раніше перевірка стріляла по завершенню ТІЛА і скидала збірку, тож печатка, що Королева шле ПІСЛЯ тіла, гинула й OTA ніколи не застосовувався. ✅ (2026-06-11) **factory-тракт K_ota зашито**: Гілка A (`CommandBuilder`) емітує KOTA-блок `0x0803E800` (дзеркало `Load_Ota_Hmac_Key`, golden-спека; `Session` тягне `OtaHmacKeyService.fetch_for(cluster_id)`) — знахідка: до цього K_ota жив лише у superseded ATECC-гілці B, тобто Гілка A випускала дерева з вічно fail-closed OTA. 🟡 **Лишається (bench):** фізичний `factory:execute` (SWD) + e2e dual-gate на STM32 (валідний APPLY + tampered REJECT) — RUNBOOK §2.5.


> **Cross-ref:** [`00_07` — FW.23](00_07_Action_Plan_Tracker) — дизайн завершено ✅
> **Залежність:** FW.1 (per-device HKDF) — ✅ реалізовано (§3.1); спільна master-secret інфраструктура наявна.

**Мета:** усунути BLOCKER §6 «Queen → Soldier (OTA LoRa) — MAC/MIC відсутній». Зловмисник у радіусі Queen може:
1. **Підмінити OTA chunks** → впровадити шкідливий mruby bytecode на всі Солдати кластера
2. **Bit-flip атака на CRC16** → CRC16-CCITT не криптографічний, валідний CRC можна підрахувати для будь-якого payload
3. **Replay старого OTA** → відкочити Солдат на застарілу/вразливу прошивку

Симетричне шифрування (AES-128-ECB) гарантує лише **конфіденційність**, не **автентичність походження**. Дзеркало проблеми FW.2 для каналу телеметрії, але з більшою серйозністю — OTA bytecode виконується на всіх Солдатах у радіусі.

#### Криптографічна основа: HMAC-SHA256 поверх повного image

```
HMAC-SHA256(K_ota, full_bytecode || version_id || total_chunks) → 32 bytes
```

**Чому HMAC-SHA256, а не Ed25519/ECDSA:**
- HMAC-SHA256 рахується **програмно** (pure-C `silken_sha256.h`, FW.30 — у STM32WLE5JC є апаратний AES, але **немає** HASH/SHA-блоку, тож SHA256 завжди software): кілька SHA-проходів над image — на порядок дешевше за програмний Ed25519 verify (~80 мс)
- 32-байтний tag поміщається у 3 LoRa-чанки (vs 64 байти Ed25519 sig → 6 чанків)
- Симетричне рішення прийнятне ТОМУ ЩО `K_ota` per-кластер, не глобальний (компрометація Queen ≠ компрометація всієї мережі)
- При billion-tree масштабі — міграційний шлях на ECDSA P-256 (slot 1 ATECC608B, post-TRL 7) описаний нижче

#### Wire Format — `[0x9B] HMAC-Trailer` Chunk

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

#### Backend HMAC Generation — `OtaPackagerService` extension

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
- **Replay attack** (старий image з валідним HMAC, але новою версією)
- **Truncation attack** (відкидання останніх chunks → змінений `total_chunks` ламає HMAC)

#### Key Management — `K_ota` per-cluster

Дзеркало дизайну HKDF з §3.4а, але з окремим **info-string** для domain separation від AES LoRa key:

```
K_ota = HKDF-SHA256(
  ikm:    PROVISIONING_MASTER_KEY,
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

#### Dual-Gate Verification (FW.23 чекбокс 5) — Soldier перед Flash write

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

#### Queen Verification — опційний intermediate gate

Queen МОЖЕ верифікувати HMAC перед relay (якщо знає `K_ota` своїх Солдатів — типово так, бо Queen у тому ж кластері). Це economy-of-scale gate: 1 verify на Queen vs N verify на N Солдатах.

**Рекомендація:** Queen НЕ верифікує (Stateless-Relay підхід) — це залишає Queen-firmware простим і дозволяє Backend → Soldier end-to-end автентифікацію без довіри до проміжного Queen. Якщо Queen скомпрометовано — Soldier'и все одно відкинуть підмінений image на Gate 2.

#### Безпекові параметри

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

#### Implementation Plan

Реалізація — три синхронні зміни (один coordinated commit, no backward-compat shim):

| Компонент | Зміна |
|-----------|-------|
| **Backend** (`OtaPackagerService`) | Завжди обчислювати HMAC та emit'ити 3 trailer-чанки `[0x9B]` після bytecode. Додати `OtaHmacKeyService.fetch_for(cluster_id)` (HKDF derivation) |
| **Firmware Soldier** | Парсити `[0x9B]` chunks у RAM (32-байтний `received_hmac_tag`), виконувати dual-gate verification перед `HAL_FLASH_Program(MRUBY_CONTRACT_FLASH_ADDR, ...)` |
| **Firmware Queen** | Stateless-relay, без verification (Backend → Soldier end-to-end) — повторюємо `[0x9B]` chunks у broadcast-циклі так само як `[0x99]` |

#### Future Evolution: HMAC → ECDSA-P256 (post-TRL 7)

Архітектурний шлях (не fallback) при додаванні ATECC608B (§3.7) для billion-tree масштабу де компрометація одного Queen не повинна дозволяти підпис нових images:
1. Backend підписує image через ECDSA-P256 з master key (HSM)
2. Public key розповсюджується у Soldier flash (slot 2 ATECC608B або Protected Flash)
3. Wire format: `[0x9B][seg_idx:2][total:2][sig_segment]` → 6 чанків (64B sig)
4. ECDSA verify (~80 мс, software) дорожчий за software HMAC-SHA256, але прийнятний для рідкісної OTA-операції
5. Компрометація Soldier НЕ дозволяє підписувати OTA (асиметричні ключі — асимметрія довіри)

#### Test Coverage — ✅ реалізовано
- **Backend (`spec/services/ota_packager_service_spec.rb`):** HMAC chunk generation (4 чанки = 3 печатки + версія), deterministic за фіксованого `K_ota`, replay/truncation negative cases, version_id-на-дроті (seg 4 = `firmware.id` BE)
- **Firmware (`firmware/test/test_soldier_logic.c`):** trailer assemble (version chunk, all-4=0x0F, seg_idx>4 reject), **реальний HMAC compute** (`Silken_Hmac_Sha256_Concat ≡ one-shot ≡ OpenSSL`), `OTA_Try_Finalize` APPLY·WAIT·REJECT (tampered/version-mismatch/no-key), constant-time compare
- **Integration (`spec/integration/ota_firmware_flow_spec.rb`):** backend → Queen relay (4 segments) → Soldier dual-gate accept/reject; tag reconstruction == `compute_hmac_tag`

> **Cross-ref:** FW.1 (HKDF master-key infrastructure), FW.2 (CCM MIC для телеметрії — паралельний MAC concept), §3.7 (ATECC608B slot 3 reserved for OTA HMAC), §6 «Queen → Soldier (OTA LoRa)» row у криптографічній таблиці.

---

### 3.4г Factory Flashing Operations Security 🤖 (SEC.3, 2026-05-17)

> ⚠️ **Internal Admin Tool — поза публічним REST API.** Цей розділ описує **окремий канал** доставки ключів від Rails Backend до програматора (SWD/JTAG). Він НЕ є описом `POST /api/v1/provisioning/register` (реєстрація після деплою, Zero-Trust, без ключа у відповіді — [`04_03 §5.2`](04_03_REST_API_v1_Reference) залишається незмінним). Threat model нижче розроблений з нуля з урахуванням фізичного доступу на заводі.

**Cross-ref:** [`00_07` — SEC.3](00_07_Action_Plan_Tracker) | §3.4 (pipeline design) | §3.4а (HKDF derivation) | §3.6 (RDP Level 2) | §3.7 (ATECC608B) | SEC.1 (Gnosis Safe multisig) | SEC.2 (RDP activation) | SEC.6 (Secure Element) | SEC.9 (WeakKeyDetector)

---

#### Implementation status (2026-05-24)

> **Реєстр сервіс-об'єктів (роль кожного `FactoryFlashing::*`) — дім [`04_02 §8`](04_02_Business_Logic_and_Services); модель сесії — [`04_01` ProvisioningSession](04_01_Data_Models_and_Entities).** Нижче — security-нюанси + impl/bench-статус per шар (дім 03_05).
>
> Дизайн A–D нижче імплементовано як Rake-driven internal admin tool. Реальний `STM32_Programmer_CLI` subprocess execution та live `cryptoauthlib` I²C — gated на HW bench (deferred).

| Шар | Файл | Статус |
|-----|------|--------|
| Session AASM | `app/models/provisioning_session.rb` | ✅ `pending → supervisor_approved → active → completed \| failed`, 2-Person Rule валідація `supervisor_id != operator_id` |
| Master key source | `app/services/factory_flashing/master_key_source.rb` | ✅ `EnvAdapter` (з `Security::WeakKeyDetector` SEC.9), `BitwardenAdapter` skeleton (raise `NotImplementedError` — TODO live `bw` API) |
| Command emission | `app/services/factory_flashing/command_builder.rb` | ✅ Гілка A — `STM32_Programmer_CLI -w32` per word для `KEYL`/`LSED`/`KEYC`/`EDSK` slots (EDSK = L1 QATT сім'я голосу Королеви, Gateway-only; генерується `Session`'ом на фабричному хості — НЕ HKDF, у БД лише pubkey), RDP level 1/2 config; Гілка B — skip key writes (keys через ATCA), only firmware connect + RDP lock |
| Subprocess executor | `app/services/factory_flashing/executor.rb` | ✅ dry-run default (`[dry-run] cmd`); `dry_run: false` → `Open3.capture3` з `ProgrammerMissingError` коли CLI відсутній у PATH; `CommandFailedError` зупиняє на першому non-zero exit |
| ATECC provisioning | `app/services/factory_flashing/atecc_provisioner.rb` | ✅ Гілка B skeleton — emit `atcab_init` + `atcab_read_serial_number` + slot writes (0/1/2/3) + `atcab_lock_config_zone` + `atcab_lock_data_zone`; raw key bytes scrubbed (`/* NB elided */`) |
| Audit trail | `app/services/factory_flashing/audit_trail.rb` | ✅ `AuditLog(action: "factory_flash")` chain-hashed + `MaintenanceRecord(action_type: :installation, skip_photo_validation: true)`; metadata містить `operator_id`/`supervisor_id`/`batch_id`/`flash_addr`/`rdp_level`/`atecc_serial_hex`/`firmware_version`/`command_count`/`dry_run` |
| Orchestrator | `app/services/factory_flashing/session.rb` | ✅ `ActiveRecord::Base.transaction` — failure rolls back HardwareKey + audit writes разом; `PreflightError` для non-approved sessions / missing device / unavailable master key |
| Operator CLI | `lib/tasks/factory.rake` | ✅ `factory:flash[device_uid,batch_id,gilka,operator_id,supervisor_id,firmware_version]` (`ATECC_SERIAL` env для Гілки B, `RDP_LEVEL` env override) → `factory:approve[session_id]` (з `SUPERVISOR_ID` env guard) → `factory:execute[session_id]` (`EXECUTE=1` для real subprocess) |

**Test coverage:** model AASM/validations (15), MasterKeySource (6), CommandBuilder golden vectors (11), Executor dry-run/execute (6), AteccProvisioner (10), AuditTrail (6), Session orchestration (7), E2E Rake trio (3 — firmware-equivalent HKDF verification).

**Зразок dry-run вивода** (Tree, Гілка A, RDP=1):
```
[dry-run] STM32_Programmer_CLI -c port=SWD reset=HWrst
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
- 👤 Реальний `STM32_Programmer_CLI` execution на STM32WLE5JC bench (зараз `EXECUTE=1` raise'ить `ProgrammerMissingError` без CLI у PATH). ✅ (2026-06-07) Software-половина доведена шим-інтеграцією: fake-CLI на PATH → повна Session через реальні subprocess'и (ok/verify-fail/rdp-fail, stop-on-fail, transcript) — `spec/services/factory_flashing/session_run_execute_path_spec.rb`; на bench лишається фізика SWD
- 👤 Bitwarden Secrets Manager live API (`BitwardenAdapter#fetch_master_key` placeholder)
- 🔗 Live `cryptoauthlib` I²C call в `AteccProvisioner` — після SEC.6 PCBA з ATECC608B

---

#### A. Access Control до `PROVISIONING_MASTER_KEY`

**Хто має право запускати Factory Flashing Tool:**

| Роль | Право | Умова |
|------|-------|-------|
| `super_admin` | Ініціювати provisioning сесію | З MFA + HSM presence |
| `admin` | Спостерігати за прогресом | Read-only audit view |
| Factory Operator (без Rails-ролі) | Виконувати фізичне підключення | Лише після авторизації supervisor'а; UI показує тільки статус, не ключ |

**Як master key потрапляє до інструменту (три варіанти, від кращого до гіршого):**

1. **HSM injection (рекомендовано для > 1 000 unit):** `PROVISIONING_MASTER_KEY` ніколи не покидає HSM (AWS CloudHSM / Thales Luna). Інструмент викликає HSM API для деривації `device_key = HKDF(master_key, device_uid)` всередині апаратного модуля → отримує лише готовий `device_key`. `master_key` у RAM інструменту не з'являється жодного разу.

2. **Envelope encryption (TRL 6/7, pilot batch):** `PROVISIONING_MASTER_KEY` зберігається у Bitwarden Secrets Manager або 1Password Secrets Automation. Перед кожною сесією — short-lived token (TTL 15 хв) генерується через API і передається інструменту через `PROVISIONING_SESSION_TOKEN` ENV. Після закінчення TTL — інструмент не може деривувати нові ключі без нового токена.

3. **Direct ENV (development/lab only):** `PROVISIONING_MASTER_KEY` встановлюється в ENV вручну перед запуском. Недопустимо у field-batch. `Security::WeakKeyDetector` блокує запуск з тест-векторами (§3.1а, SEC.9).

**Ротація master key:**

- Нова сесія починається лише після верифікації нового ключа через `Security::WeakKeyDetector` (CLI runbook у §3.1а).
- `previous_aes_key_hex` (Dual-Key Grace Period у `HardwareKey`) активний до підтвердження прошивки всіх пристроїв у партії.
- Fail-closed boot guard: `config/initializers/master_key_strength_check.rb` відмовляє у запуску Rails якщо `PROVISIONING_MASTER_KEY` = тест-вектор (SEC.9).

---

#### B. Anti-Key-Leak via Factory Operator

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

#### C. Audit-Trail Provisioning Сесій

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
    atecc_serial:  atecc_serial_hex,         # Гілка B: 9-байт serial (nil для Гілки A)
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
- Chain hash перевіряється при кожному audit export (`AuditLog.verify_chain_integrity!`).
- Мінімальний retention: 7 років (GDPR Article 17(3)(b) — legal obligation exception).

**2-Person Rule (рекомендовано для > 100 unit batch):** supervisor має підтвердити сесію через окремий Rails UI перед тим як інструмент отримає session token. Реалізується через `ProvisioningSession` AASM: `pending → supervisor_approved → active → completed/failed`.

---

#### D. Гілка A vs Гілка B Threat Model Diff

| Вектор атаки | Гілка A (Protected Flash STM32) | Гілка B (ATECC608B / STSAFE-A110) |
|-------------|----------------------------------|-----------------------------------|
| **Фізичне вилучення ключа з чіпа** | RDP Level 1: ускладнено (voltage glitching можливий на старих ревізіях); RDP Level 2: практично неможливо | ATECC data zone lock + DPA-hardened silicon: key never leaves chip в plaintext; fault injection → self-erase |
| **Chip swap (ворог замінює STM32/ATECC на інший)** | STM32 не має унікального hardware ID прив'язаного до DB — swap непомітний до першого uplink (DID mismatch детектує Rails) | ATECC serial (9 байт, factory-burned) pin'ується у `(device_uid, atecc_serial)` парі в `HardwareKey`. Чужий ATECC → provisioning API reject з 409 |
| **Replay provisioning request** | `POST /api/v1/provisioning/register` — ідемпотентний через duplicate DID check (409) | Те саме + ATECC serial pinning |
| **Factory insider attack (оператор копіює ключ)** | Ризик: SWD adapter може перехопити байти під час write якщо не використовується HSM injection | Ризик нижчий: ATECC write через I²C, ключ загружається через `atcab_write_zone()` — не проходить через user-space буфер у стандартній реалізації |
| **Cold-boot attack на factory laptop RAM** | Ризик: `device_key` у RAM до wipe (~мс) | Ризик нижчий: HSM injection → `device_key` ніколи не в laptop RAM |
| **Перехід Гілка A → Гілка B** | Можливо (re-flash MCU + добавити ATECC до PCBA = новий PCB revision) | — |
| **Перехід Гілка B → Гілка A** | ❌ Неможливо (ATECC config zone locked permanently) | — |

**Рекомендований мінімум для TRL 6 (pilot batch ≤ 100 unit):**
- Гілка A + envelope encryption (Bitwarden Secrets Automation, short-lived token TTL 15 хв)
- 2-person rule (operator + supervisor)
- AuditLog chain-hash + MaintenanceRecord :installation
- RDP Level 1 відразу після Flash write

**Перехід на Гілка B** активується перед першим mass production batch (рішення прив'язане до BOM freeze — cross-ref [`07_02 §8.1`](07_02_Unit_Economics_and_BOM), SEC.6, ARCH.42).

---

> **Cross-ref:** §3.4 (pipeline design Гілка A + B), §3.4а (HKDF derivation), §3.6 (RDP Level 2 — необоротна процедура), §3.7 (ATECC608B slot mapping), [`00_07` — SEC.3](00_07_Action_Plan_Tracker), [`00_07` — SEC.1](00_07_Action_Plan_Tracker) (Gnosis Safe multisig для admin role).

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

**Cross-ref:** [`00_07` — SEC.2](00_07_Action_Plan_Tracker), §3.3 «Апаратний Захист Flash».

> ⚠️ **Активація RDP Level 2 — одностороння, незворотна дія.** Після `Apply` чіп фізично втрачає SWD інтерфейс назавжди. Цю процедуру виконують **тільки** після того, як OTA-пайплайн повністю верифікований у полі.

**Pre-flight checklist (обов'язково ДО натискання Apply):**

- [ ] OTA flow end-to-end протестований: `OtaPackagerService` → CoAP downlink → Queen broadcast → Soldier Flash write → magic check `0x45544952` ("RITE") → reboot → нова прошивка живе у `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`.
- [ ] OTA verification: щонайменше **2 успішні цикли** оновлення на тому ж пристрої (не лише бенчмарки).
- [ ] OTA rollback тестований: якщо новий bytecode falls back до embedded `lorenz_bytecode[]` при corrupt magic.
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

**Поетапний rollout (рекомендовано):**

| Етап | RDP Level | Кількість | Призначення |
|------|-----------|-----------|-------------|
| Прототип / R&D | Level 0 | ~50 | Розробка, дебаг, SWD доступ |
| Field pilot (пілотний ліс) | Level 1 | 100–500 | Field sanity, OTA verification, recovery still possible |
| Mass production batch | Level 2 | 10,000+ | **Тільки** після ≥3 місяців stable OTA на Level-1 партії |

**Документ-tracker:** після кожного batch активації — оновити [`00_07`](00_07_Action_Plan_Tracker) SEC.2 (👤 — secrets / process).

---

### 3.7 Secure Element — NXP EdgeLock SE050 (ARCH.42 + SEC.6 + true-DePIN)

**Cross-ref:** [`00_07` — SEC.6](00_07_Action_Plan_Tracker), [`00_07` — ARCH.42](00_07_Action_Plan_Tracker), [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker) — **SE = SE050 (RESOLVED 2026-06-07)**, §3.2 «Secure Element після ARCH.42».

> ✅ **SE = NXP EdgeLock SE050 (SEC.6 RESOLVED 2026-06-07; supersedes the 2026-05-23 ATECC608B pick):** коли SilkenNet зобов'язався дати деревам **власний криптографічний голос** (true-DePIN: дерево підписує свої дані ключем, що не покидає кремній і якого не підробить навіть оператор), SE-частина мусила вміти **non-extractable Ed25519** (крива peaq/Solana). **ATECC608B (P-256 only) цього не вміє** → SE = **SE050** (Ed25519/EdDSA + AES-128/256 + monotonic counters + secure storage — суперсет ATECC). Trust-напрям + ladder — у SEC.6 ADR нижче.
>
> **AES-128 для LoRa лишається — але це тепер ВИБІР, не constraint:** ATECC мав HW-максимум 128; SE050 вміє 128/256. Тримаємо **AES-128-CCM** свідомо — golden-standard constrained-IoT (LoRaWAN/Zigbee/Thread/BLE), сумісність з LoRaWAN-fallback (ARCH.34) і **freeze-contract FW.2** (28-byte CCM packet, wire-rev2). CoAP-магістраль Queen↔Rails — AES-256-CBC (ключ у Queen Protected Flash, не в SE). **ARCH.42 AES-128-рішення СТОЇТЬ — змінилась лише SE-частина (ATECC→SE050).** Глобальний AES-128-патч (ARCH.42) чинний: `CRYP_KEYSIZE_128B`, `HardwareKey.aes_key_hex` (Tree=32 hex / Gateway=64 hex), HKDF info `"silken-aes-128-lora-key"`.
>
> **Чому НЕ ATECC (реверс рішення 2026-05-23):** ATECC обрали за ціною ($0.85 vs SE050 ~$2.40–3.25) під припущення **кастодіального** trust. True-DePIN перевертає логіку: ECDSA-рушій ATECC — **P-256 (secp256r1)**, не збігається з жодним ланцюгом (EVM=secp256k1, Solana/peaq=Ed25519) → не може тримати голос дерева. Ціна (founder: не проблема) поступається vision. **SE050 datasheet-verify** (Ed25519/EdDSA + monotonic counters + AES-128) → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker).

> ✅ **SEC.6 ADR (2026-06-07) — SE050 soft-freeze + true-DePIN ladder.**
>
> **Soft-freeze:** SE050 footprint + I²C на PCB зараз, **DNP** (do-not-populate, як LTC3108 — [`02_01`](02_01_Hardware_Architecture_and_BOM) BOM п.13); populate на mass (>10k) post-FW.2. Пілот (≤100 / <10k) = Гілка A (RDP L2, канон-мінімум §3.4г). Асиметрія необоротності (B→A неможливо config-lock; A→B = PCB-респін) → закласти footprint = low-regret; **не** закласти = найдорожча помилка.
>
> **True-DePIN ladder («голос дерева»):** L0 custodial → L1 Queen-attest → L2 per-tree (SE050 Ed25519 + Merkle, energy-gated). Повний ladder (рунги/гейти/статус/енергобюджет) — канон [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline). §3.7 володіє лише SE/крипто-частиною (Slot-0 AES, Slot-1 Ed25519 keygen).
>
> **Що SE050 дає / межі:** дає **голос** (non-extractable Ed25519 = origin) + AES-128 tamper-storage (LoRa-ключ) + монотонні лічильники (FW.2 nonce + panic) + anti-clone serial + SHA/HMAC OTA. **НЕ замінює** ЗВТ-метрологію (точність/legal — STK.4) і operator-bond/slashing (економічний ризик — BIZ.13). Голос + точні «вуха» + skin-in-game = довірений RWA.
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
- Числа — ATECC608B (порядок величини); SE050 active/standby струми — datasheet-verify при eval-kit ([`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker), no-premature-canon).

**Footprint (PCB):**
- UDFN-8: 2×3 мм
- SOIC-8: 4×5 мм
- I²C: 2 GPIO (PB6/PB7) + 2 pull-ups (4.7 kΩ × 2)
- Загалом: ~3% PCB area для Soldier (KiCad layout у HW.9)

**Роль SE у LoRa-крипті: per-packet AES vs provisioning-only — відкритий trade-off [SEC.14]**

> Це уточнення *всередині* Варіанту B, **не** перегляд ARCH.42. ARCH.42 зафіксував *AES-128-ключ у ATECC608B Slot 0*; відкритим лишається інше питання — *хто виконує шифрування кожного пакета*: сам SE щопакета, чи вбудований radio-AES STM32 з ключем у RDP-Flash.

Решта §3.7 (API sketch, latency/power) неявно припускає **per-packet ATECC AES** (`atcab_aes_encrypt()` на кожен LoRa-кадр). Це не єдиний шлях, і попередня подача «1.5 мс нехтовно / +0.1% ✅» приховувала справжню вісь. Енергія тут — хибний слід (вона мала з обох боків). Реальна вісь:

| | **Варіант B (поточний неявний): per-packet ATECC AES** | **Role-split: built-in AES + ATECC provisioning-only** |
|---|---|---|
| LoRa session-ключ живе | у ATECC Slot 0, **ніколи не залишає кремній SE** | у STM32 RDP-Flash (рівень захисту Гілки A для *цього* ключа) |
| Шифрування пакета | `atcab_aes_encrypt()` через I²C, ~1.5 мс, MCU awake весь раунд | вбудований radio-AES STM32WLE5JC, ~10 µs, inline |
| Роль ATECC | весь streaming AES **+** identity/attestation | **лише provisioning**: ECDH keygen, master/identity (Slot 1), device cert (Slot 2), OTA HMAC key (Slot 3), P-256 device-cert (НЕ peaq/Solana Ed25519) |
| Сильна сторона | LoRa-ключ DPA/EM-стійкий *by design* | SoC-AES створений саме для inline-LoRa; менше I²C failure-modes; latency ~10 µs |
| Ціна | +1.5 мс MCU-awake/пакет на вузлі, що спить 99% часу; +1 шина, що може відмовити | LoRa session-ключ не захищений на рівні SE (master/identity лишаються в ATECC) |

**Чому role-split легітимний:** уся цінність ATECC — «ключ не залишає ASIC», що *змушує* робити AES всередині SE. Якщо натомість прийняти, що LoRa session-ключ живе у RDP-Flash (Гілка-A рівень для одного цього ключа), то вбудований AES STM32 — швидший та ідіоматичний (radio-integrated CRYP саме для inline-LoRa), а ATECC робить те, у чому незамінний: асиметрику + tamper-resistant identity + provisioning. Per-device HKDF (§3.4а) гарантує: екстракція LoRa-ключа з одного вузла **не** компрометує мережу.

**Чому per-packet (Варіант B) теж defensible:** для urban / high-value розгортань, де фізичний доступ до вузла ймовірний, tamper-resistance *самого LoRa-ключа* може бути вартий 1.5 мс. Це рішення про threat model, а не технічна необхідність.

**Статус:** SEC.6 (чи заводити SE + який) → **RESOLVED 2026-06-07: SE = SE050, soft-freeze + true-DePIN ladder (ADR угорі §3.7)**. SEC.14 (роль *per-packet* vs *provisioning-only*) лишається **відкритим** — обидва шляхи сумісні з ARCH.42 (AES-128 — тепер вибір, не SE-constraint: SE050 вміє 128/256); вибір при bench eval, з **явним** вибором осі. Cross-ref [`00_07` — SEC.6](00_07_Action_Plan_Tracker), [`00_07` — SEC.14](00_07_Action_Plan_Tracker), [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker).

**Альтернативи:**

| Чіп | Виробник | Особливості | Висновок |
|-----|----------|-------------|----------|
| **ATECC608B** | Microchip | Зрілий ecosystem, ESP/STM32 libraries, AWS IoT default | ⭐ Рекомендовано |
| **STSAFE-A110** | STMicroelectronics | Same vendor як STM32 → unified toolchain (CubeMX), краща інтеграція | Сильна альтернатива |
| **OPTIGA Trust M** | Infineon | TPM 2.0 features, X.509 PKI heavy | Overkill для нашого use case |
| **NXP A71CH** | NXP | EOL announced 2024 | ❌ Не використовувати |

**Рекомендація:** ATECC608B або STSAFE-A110. Final pick — після завершення KiCad layout (HW.9) і перевірки I²C bus utilization (вже використовується для DS18B20 в [`02_05 §4а`](02_05_Queen_Hardware_and_Starlink)?). STSAFE-A110 має невелику перевагу через native CubeMX-інтеграцію — економить ~3 дні firmware-розробки.

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
- [x] 🤖 (SEC.14) Перефреймувати latency/power → чесний trade-off «per-packet AES vs provisioning-only» — ✅ Виконано (підрозділ вище): енерго-аргумент перевірено = малий, але не вирішальний; справжня вісь = tamper-resistance LoRa-ключа ⟷ latency/ідіом; role-split альтернатива подана
- [x] 🤖 (SEC.14, 2026-06-12) Cross-check проти Сценарію C ([`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)) — точні %: active ≈0.3% TX / ≈0.2% циклу / ≈3% годинного запасу (підтверджує «малий»); **знахідка-інверсія**: always-on sleep 150 нА ≈ 3.6 мДж/год > запас Сценарію C → **load-switch гейт SE обов'язковий** (Power impact вище; стосується обох ролей)
- [ ] 👤/🤖 (SEC.14) Обрати роль SE — per-packet SE050 AES (Варіант B) vs built-in AES + SE050 provisioning-only — за віссю trade-off вище, при bench eval + BOM freeze (не за замовчуванням)
- [x] 🤖 Update §3.4 Factory Flashing pipeline з SE-варіантом — ✅ Виконано: §3.4 розділено на Гілку A (Protected Flash, TRL 6/7) та Гілку B (ATECC608B/STSAFE-A110, mass production > 10k); додано двошаровий defense-in-depth (data zone lock + RDP), latency/power/cost impact, criteria для вибору гілки, та irreversibility note (B → A неможливо)
- [ ] 🤖 Інтеграція з Backend `Provisioning::HardwareKeyService` (генерація ECC keypair + cert)
- [ ] 🤖 Firmware HAL: drop-in replacement `Crypto_AES_Encrypt_Block()` що внутрішньо викликає ATECC або HAL_CRYP залежно від `#define USE_SECURE_ELEMENT`
- [ ] 👤 Замовити evaluation kit (Microchip ATECC608B-MAH-DAO або ST STSAFE-A110) для bench-test
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

**ACK без окремого каналу:** backend ротує `HardwareKey` при dispatch'і команди (новий ключ; старий → `previous_aes_key_hex`, Dual-Key Grace §3.4а) → перший uplink, що декриптнувся новим ключем, = неявний per-device ACK (`clear_grace_period!` — наявна машинерія). Cluster-wide ротація = батч per-device команд; «cluster ACK» = усі grace-вікна кластера закриті.

**Чесна модель загроз:**
- ✅ **Backward secrecy** — головна регуляторна цінність (NIST SP 800-57 / GDPR / ISO 27001): витік `K_v` (DB-leak бекенда) не відкриває попередні ключі й записаний раніше трафік.
- ⚠️ Майбутні ключі з `K_v` похідні (hash-ланцюг) — відновлення після компрометації = re-provisioning (SEC.3) або ECDH-alt (нижче). Ratchet ≠ compromise recovery.
- ⚠️ Фізичний витяг `K0` з пристрою дає весь ланцюг — захист сьогодні = RDP2 (§3.6); справжнє закриття = SE050 non-extractable + HW monotonic counter (§3.7, рунг L2). `K0`-rederive свідомо обрано замість erase-old-key: append-only Flash-KV не вміє гарантовано стирати, а Protected Flash не перезаписується без unlock.
- 🔴 **Активаційний gate:** ECB-downlink без MAC (BLOCKER-2) не сміє командувати ротацією (bit-flip/forge кадру). Активація — лише ПІСЛЯ FW.2 CCM (authenticated downlink). До того інтеграція інертна за двома дзеркальними гейтами: firmware `FW17_RATCHET_ENABLED 0` (компайл-флаг у `main.c`, патерн `FW2_CCM_ENABLED`/`FW8_PARSER_ENABLED`) + backend ENV `FW17_RATCHET_DOWNLINK_ENABLED` (закритий гейт → `RatchetGateClosedError` ДО будь-якої зміни БД; воркер дублює перевірку defense-in-depth).

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
| **Soldier → Queen** (LoRa, 16B) | AES-128 | ECB | ❌ Відсутній | ❌ Відсутній | ⚠️ Replay вразливість |
| **EwsAlert / Panic → Queen** (LoRa, 16B) | AES-128 | ECB | ❌ Відсутній | ❌ Відсутній | ⚠️ Критичні пакети без автентифікації |
| **Queen → Rails** (CoAP Batch) | AES-256 | CBC | ✅ HRNG (128-bit) | 🟡 **Ed25519 batch-sig (L1 QATT, §2.2)** — detached, encrypt-then-sign; legacy L0 без підпису приймається | IV prepend; sig хвостом |
| **Rails → Queen** (CoAP Command) | AES-256 | CBC | ✅ Від Backend | ❌ Відсутній | IV в перших 16 байтах |
| **Queen → Soldier** (OTA LoRa) | AES-128 | ECB | ❌ Відсутній | ❌ Відсутній | ⚠️ Прошивка без автентифікації |

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
| AES-128 LoRa block encrypt/decrypt round-trip [post-ARCH.42] | `firmware/test/test_encryption.c` | ✅ ECB single-block 128B |
| AES-256 CoAP batch encrypt + IV prepend [Queen only] | `firmware/test/test_queen_logic.c` | ✅ Часткове |
| Load_AES_Key() Flash magic guard | `firmware/test/test_soldier_logic.c::test_load_key_unprovisioned_flash_error` | ✅ |
| Emergency TX format | `firmware/test/` | ⚠️ Не верифіковано |
| HRNG fallback behavior | Відсутній | 🔴 Не покрито |
| Key hardcoding detection | `app/services/security/weak_key_detector.rb` + boot guard | ✅ Backend |
| **AES-128-CCM encrypt + MIC verify [FW.2 target]** | TBD — STM32 hardware bench | 🟡 Pending |

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
| **Зберігання ключа** | ✅ Protected Flash Sector (LoRa `"KEYL"`, CoAP `"KEYC"`, L1-сім'я `"EDSK"`), RDP Level 1/2 protected. SE050 Slot 0 (Гілка B, §3.7) для mass production >10k |
| **Унікальність ключа** | ✅ Per-device HKDF (FW.1 + ARCH.42) | LoRa: `HKDF-SHA256(MASTER, uid, "silken-aes-128-lora-key")`; CoAP: `HKDF-SHA256(MASTER, uid, "silken-aes-256-device-key")` — domain separation §3.4а |
| **ECB для LoRa** | 🟡 Transitional після ARCH.42 | AES-128-ECB → AES-128-CCM (target FW.2, 28B wire-rev2 packet + Frame Counter + 8B MIC) |
| **MAC/MIC (LoRa)** | 🟡 OPEN — закривається з FW.2 CCM | 8-byte MIC (64-bit, forge probability $5.4×10^{-20}$) |
| **CoAP batch origin + integrity** | 🟡 **L1 QATT shipped** (2026-06-07) | Ed25519 batch-підпис Королеви (§2.2): закриває CBC-malleability/injection + anti-replay у nonce-вікні; legacy L0 без підпису ще приймається (fleet-перехід); 👤 bench: EDSK на кремнії. Ladder → [`05_02`](05_02_Proof_of_Growth_Pipeline) |
| **RDP Protection** | 🟡 OPEN | Level 0 (розробка). Level 1/2 — фінальний крок Factory Flashing (розділ 3.3). Pre-flight checklist та незворотна процедура задокументовані у §3.6 🤖 |
| **Factory Flashing Pipeline** | 🟡 PARTIAL (SEC.3) | ✅ Архітектура (§3.4) + HKDF (§3.4а) + Operations Security threat model (§3.4г, 2026-05-17) + tool implementation (§3.4г Implementation status, 2026-05-24 — `app/services/factory_flashing/*`, `lib/tasks/factory.rake`, 63 specs, dry-run). 👤 Залишається: real `STM32_Programmer_CLI` execution на bench + Bitwarden live API + ATCA I²C |
| **Shipping Mode (Геркон)** | 🟡 OPEN | Концепт визначено (розділ 3.5); компонент не доданий до BOM |
| **Secure Element (SE050)** | ✅ SEC.6 RESOLVED (true-DePIN) | §3.7 ADR — SE = **SE050** (Ed25519 on-chip keygen; реверс ATECC), soft-freeze DNP, populate post-FW.2; slot-map §3.7. Residuals → [`00_07` — SE050-MIGRATION](00_07_Action_Plan_Tracker) |
| **Key Rotation** | 🟡 host-готово | Hash-Ratchet freeze-contract §3.8 (backward secrecy, ключ не летить ефіром); активація CCM-gated — `[FW.17]` |
| **HRNG Fallback** | ✅ Harden (2026-05-29) | `coap_fallback_iv_word` (pure, `coap_iv.h`) — унікальність across device/reboot/flush; §4.2 |
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
- ❌ НЕ пишемо жодного рядка PQC коду на Soldier (Dilithium підпис — 2420 байт, не вміщається у 28B LoRa packet; Kyber публічний ключ — 1184 байти, не вміщається у LoRa airtime budget)
- ❌ НЕ міняємо STM32WLE5JC на чіп з апаратним Kyber acceleration (такі чіпи ще не існують у TRL 9 silicon @ low-power profile)
- ❌ НЕ форсуємо peaq/Polygon DID міграцію — це залежить від upstream blockchain ecosystems

#### **Етап 2 (TRL 7–8, 2028–2030)** — Hybrid Layering на Edge

| Зміна | Контур | Деталі |
|-------|--------|--------|
| **Cloudflare PQC TLS** | Queen ↔ Rails (вже активно) | Нічого не робимо — Cloudflare auto-rolls hybrid Kyber-768 + X25519. Документація у `06_02 INF.4` |
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
| **Dilithium-2 signature** (PQC) | Квантова невідрікальність на per-packet рівні | Підпис 2420 байт vs наш 28-byte LoRa packet → fundamental fit problem. Якщо рамку розширити — duty cycle EU868 (1%) порушиться на 2 порядки. |
| **Kyber-768 KEM** (PQC key encapsulation) | Постквантовий ephemeral key exchange | Публічний ключ 1184 байти, ciphertext 1088 байт — LoRa SF10 payload max ~255 байт. Технологічно несумісно з constrained radio link. |

### 10.4 SSOT-карта: де читати про PQC

| Питання | Документ |
|---------|----------|
| Чому AES-128 LoRa достатньо на 25-річний горизонт | Цей §10 + ARCH.42 у [`00_07`](00_07_Action_Plan_Tracker) |
| Як Cloudflare hybrid Kyber+X25519 інтегровано | `06_02 INF.4` (Akash TLS strategy) |
| Hash Ratchet KDF дизайн | `[FW.17]` у [`00_07`](00_07_Action_Plan_Tracker) (placeholder) |
| peaq DID міграція на Substrate-PQC | `05_01 Multichain Architecture` §peaq |
| OTA HMAC-SHA256 dual-gate | §3.4б цього файла + `[FW.23]` у [`00_07`](00_07_Action_Plan_Tracker) |
| Chainlink HMAC vs ECDSA migration | `04_02 ChainlinkOracleService` (delegated до Chainlink DON) |

### 10.5 Висновок

> **Наше поточне рішення** — 28-байтний LoRa packet (wire-rev2) з AES-128-CCM + 8-байтним MIC + Hash Ratchet rotation — це ідеальна **інженерна точка паритету** (Sweet Spot) для фізичної реальності TRL 6:
>
> ```
> [Абсолютна теорія: PQC + Ed25519 + Arithmetic] ─── Несумісно з EBFC батарейкою та 64KB SRAM
>                      │
>                      ▼ [Суворий інженерний компроміс]
> [Наше рішення: 28B AES-128-CCM + 8B MIC] ─── ✅ 20 років автономності, 0% CPU overhead,
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
