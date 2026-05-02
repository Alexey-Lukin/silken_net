# 03_06: Lorenz Seed Provenance — Походження Початкової Точки Атрактора

---

## 🎯 Мета

Зафіксувати **криптографічно стійкий механізм виведення початкової точки `(x₀, y₀, z₀)` атрактора Лоренца** для кожного Soldier-вузла. Документ замінює попередній підхід «raw DID як seed», який мав фундаментальні безпекові вади і робив `check_z_divergence!` категоричним замість числового.

Цей документ є **SSOT для дизайну SEC.11** (див. `docs/10_02_Action_Plan_Tracker.md`). Імплементація — у наступному циклі. Тут — повний дизайн, аргументація і план міграції.

---

## ✅ Статус

- **Дизайн прийнятий:** 2026-05-02 (гібрид варіантів **A + B + D**, див. §5)
- **Імплементація:** 🟡 Заплановано (SEC.11), не виконано в поточному PR
- **TRL impact:** TRL 6 → TRL 6+ після впровадження (закриває один із трьох семантичних bypass-векторів Dual Computation Integrity)
- **Пов'язані документи:**
  - mruby Атрактор Лоренца → [`03_04_mruby_Lorenz_Attractor`](03_04_mruby_Lorenz_Attractor)
  - Hardware AES-256 та Security → [`03_05_Hardware_AES256_and_Security`](03_05_Hardware_AES256_and_Security)
  - Provisioning Pipeline → [`05_01_Provisioning_and_OTA`](05_01_Provisioning_and_OTA)
  - Proof of Growth Pipeline → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)

---

## 1. Проблема: Чому raw DID як seed — це security hole

### 1.1 Початковий стан (до SEC.11)

У firmware mruby `bio_contract.rb` атрактор стартує з:

```ruby
chaos_seed = HRNG()                       # Soldier: апаратний RNG
x0 = (chaos_seed & 0xFFFF) / 65535.0
y0 = ((chaos_seed >> 16) & 0xFFFF) / 65535.0
z0 = ((did_uint32 ^ chaos_seed) & 0xFFFF) / 65535.0
```

На сервері `SilkenNet::Attractor.calculate_z` цей самий `chaos_seed` **не відомий** (HRNG локальний), тому сервер використовує **DID як deterministic seed** для відтворення тієї ж точки. Результат: **публічний 4-байтний DID — фактичний криптографічний параметр**.

### 1.2 Чотири фундаментальні вади

| # | Вада | Експлуатація |
|---|------|--------------|
| 1 | **Публічний seed → публічна траєкторія** | DID їде відкритим текстом у заголовку LoRa-пакета (`[DID:4]`, поза AES). Атакер з знанням формули Лоренца (open-source firmware) обчислює `Z(DID, temp, acoustic, dt, vcap)` для будь-якого дерева → підробляє телеметрію з валідним StatusByte. `check_z_divergence!` мовчить. |
| 2 | **Кореляція сусідніх DID** | Provisioning видає DID послідовно (`SNET-AC0001AB`, `…AC`). Перші ~30 ітерацій Ейлера дві сусідні крони мають майже ідентичні траєкторії (Lorenz divergence — експоненційна, але повільна на ранніх кроках). Знижує статистичну ентропію. |
| 3 | **Семантична помилка категорій** | DID — *identifier*. Криптографія вимагає identifier як *input* до KDF, ніколи як *output* (ключ/seed). Identifier-as-key — класичний антипатерн. |
| 4 | **Відсутність forward secrecy** | Одне дерево все життя стартує з тієї самої точки. Один підроблений рецепт працює довічно. Жодного rotation. |

### 1.3 Наслідок для Dual Computation Integrity

Зараз `check_z_divergence!` **категоричний**: порівнює `bio_status` (homeostasis / stress / anomaly), не саму величину Z. Причина — Float drift між ARM (firmware) і x86 (backend) IEEE-754 при початкових умовах із публічного DID не дозволяє строге числове порівняння. Атакер, що тримає `bio_status = homeostasis`, проходить перевірку незалежно від того, наскільки фейковий його Z.

---

## 2. Цілі дизайну SEC.11

| Ціль | Метрика |
|------|---------|
| G1 — Закрити expose seed | `K_seed` ніколи не залишає пристрій / сервер у відкритому вигляді |
| G2 — Числовий divergence check | `(fw_z − be_z).abs < 0.001` після впровадження |
| G3 — Forward secrecy | Компрометація сьогоднішнього `K_seed` не дає історичних траєкторій |
| G4 — Daily rotation | Початкова точка змінюється раз на 24 год, синхронно firmware ↔ backend |
| G5 — No new secret distribution | Reuse існуючої `PROVISIONING_MASTER_KEY` infrastructure, нуль нових сервісів |
| G6 — Cold-start recovery без re-handshake | Reboot після VBAT loss відновлює стан без втручання сервера |

---

## 3. Розглянуті варіанти

### Варіант A — Per-device secret seed (HKDF з master)

```
K_seed = HKDF-SHA256(K_master, salt="silken-lorenz-v1", info=DID, len=32)
(x₀, y₀, z₀) = unpack_normalized(HMAC-SHA256(K_seed, "init")[0..23])
```

`K_seed` виводиться під час provisioning з `PROVISIONING_MASTER_KEY`, зберігається на пристрої в NVM (поряд з `K_aes`) і на сервері в `hardware_keys.lorenz_seed_hex` (AR Encryption non-deterministic, як `aes_key_hex`).

✅ Закриває вади 1, 2, 3, 4 з §1.2.
❌ Forward secrecy відсутня — один static seed на все життя пристрою.

### Варіант B — Per-epoch rotation

```
epoch_day = floor(Time.now.utc.to_i / 86400)
(x₀, y₀, z₀) = unpack_normalized(HMAC-SHA256(K_seed, "init|" || epoch_day_be)[0..23])
```

Те саме що A, але `info`-string у HMAC включає поточний день. Кожні 24 год точка старту детерміновано змінюється для обох сторін.

✅ Forward secrecy ≤ 1 доби.
⚠️ Час на пристрої повинен бути ± 1 година synced із сервером — **це саме що дав FW.20 (`CMD_TIME_SYNC` 0x9C)**. Прекрасний синергетичний ефект.

### Варіант C — Per-packet seed (rejected)

```
(x₀, y₀, z₀) = derive(K_seed, packet_counter || DID)
```

Кожен пакет — унікальна траєкторія.

✅ Replay attack повністю unfeasible.
❌ ~10 мс CPU + 1 HKDF + 1 HMAC на STM32WLE5JC щоразу. Для дерев із пробудженням раз/хв — помітний overhead. Виграш над B + continuation мізерний (B уже дає daily rotation, FW.6 continuation усуває потребу повторного init).

### Варіант D — Stateful from cold start (FW.6 extension)

При першому boot Soldier генерує `(x₀, y₀, z₀)` з HRNG, **відправляє на сервер у спецпакеті** `[0xA0][x:8][y:8][z:8]` шифровано. Сервер зберігає в `trees.lorenz_state_x/y/z`. Далі — лише continuation (FW.6 RTC DR16-DR18 magic `"LZST"`). Жодного seed-from-formula у звичайному циклі.

✅ Найчистіше: seed існує лише в момент init.
❌ Reboot recovery вимагає або сервер re-sync (`(x,y,z)` з останнього `TelemetryLog`), або повторний init handshake → складніший protocol.

---

## 4. Прийняте рішення: Гібрид A + B + D

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PROVISIONING (one-time, at factory or on first power-up)               │
│                                                                         │
│  Backend:  K_seed = HKDF-SHA256(                                        │
│              ikm    = PROVISIONING_MASTER_KEY,                          │
│              salt   = "silken-lorenz-v1",                               │
│              info   = DID,                                              │
│              length = 32 bytes                                          │
│            )                                                            │
│            INSERT hardware_keys SET                                     │
│              device_uid       = DID,                                    │
│              aes_key_hex      = ...,                                    │
│              lorenz_seed_hex  = K_seed (AR Encryption non-deterministic)│
│                                                                         │
│  Wire:     POST /api/v1/provisioning/register response includes K_seed  │
│            (alongside K_aes), encrypted under HKDF transport key        │
│                                                                         │
│  Soldier:  Store K_seed in protected Flash sector (same area as K_aes)  │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  COLD START (boot after VBAT loss; rare event ~once per months/years)   │
│                                                                         │
│  epoch_day = current_unix_ts / 86400                                    │
│  digest    = HMAC-SHA256(K_seed, "init|" || epoch_day_be)               │
│  x₀ = bytes_to_signed_unit_float(digest[ 0.. 7])  // ∈ [-1, +1]         │
│  y₀ = bytes_to_signed_unit_float(digest[ 8..15])                        │
│  z₀ = bytes_to_signed_unit_float(digest[16..23])                        │
│  Persist (x₀, y₀, z₀) to RTC DR16-DR18 with magic "LZST" (existing FW.6)│
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  STEADY-STATE CYCLE (FW.6 continuation; every wakeup)                   │
│                                                                         │
│  (x, y, z) = read RTC DR16-DR18 (or cold-start above if magic missing)  │
│  Run 250 Lorenz iterations with σ(acoustic), ρ(temp), β(dt, vcap)       │
│  Persist final (x, y, z) back to RTC DR16-DR18                          │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  SERVER MIRROR (TelemetryUnpackerService)                               │
│                                                                         │
│  IF telemetry_log.cold_start_flag == true:                              │
│    epoch_day = telemetry_log.created_at.to_i / 86400                    │
│    (x₀,y₀,z₀) = derive_from(hardware_key.binary_lorenz_seed, epoch_day) │
│  ELSE:                                                                  │
│    (x₀,y₀,z₀) = previous_telemetry_log.lorenz_state_xyz                 │
│                                                                         │
│  server_z = Attractor.calculate_z_continued(x₀,y₀,z₀, σ,ρ,β, 250)       │
│  device_z = decoded from packet                                         │
│  IF (server_z - device_z).abs > 0.001 → fraud_flag                      │
│  Persist server's final (x,y,z) to telemetry_log.lorenz_state_xyz       │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Чому саме гібрид

- **A** дає private seed з нуль-bойлерплейтом — піггібекаємо на існуючу `PROVISIONING_MASTER_KEY` і `HardwareKey` infra.
- **B** додає daily rotation **майже безкоштовно** — лише `info`-string у HMAC. Forward secrecy ≤ 24 год.
- **D** робить cold-start рідкісним: у норму дерево живе у continuation-режимі (FW.6); cold-start трапляється раз на місяці-роки при reboot. Тоді derive із K_seed — простий механізм відновлення, без re-handshake.
- **C відкинуто:** per-packet HMAC оvеrhead не виправдовується тим, що B+continuation уже дають еквівалентну security властивість для очікуваних threat models.

### 4.2 Криптографічні гарантії в одному рядку

> `K_seed` ніколи не залишає пристрій і сервер. `(x₀, y₀, z₀)` — функція від (`K_seed`, день). DID у формулі **не існує** як seed — він використовується лише як `info`-string у HKDF (namespace separator), що криптографічно безпечно і не вносить уразливості.

---

## 5. Вплив на Dual Computation Integrity

### 5.1 До SEC.11 (категоричний divergence)

```ruby
# TelemetryUnpackerService#check_z_divergence!
fw_status = decoded_byte >> 6
be_status = bio_status_from_z(server_z)
fraud_flag if fw_status != be_status   # 3-zone categorical
```

Tolerance band: `Z ∈ [2.0, 45.0]` → homeostasis. Атакер з `Z_fake = 28.0` проходить перевірку.

### 5.2 Після SEC.11 (числовий divergence)

```ruby
fraud_flag if (server_z - device_z).abs > 0.001
```

Чому це тепер можливо:
1. Обидві сторони стартують з **ідентичного** `(x₀, y₀, z₀)` (HMAC byte-exact).
2. `Float vs BigDecimal divergence` (FW.7) уже закрито — обидві сторони на Float (IEEE 754 double).
3. Залишається лише **ARM vs x86 IEEE-754 drift** — < 1e-12 за 250 ітерацій (емпірично з FW.7 фікса).
4. Tolerance `0.001` дає 9 порядків запасу над архітектурним drift.

**Ефект:** атакер не може передбачити очікуваний Z без знання `K_seed` → fake-телеметрія falls within `< 0.001` band з ймовірністю ~`6/45000` (Z домен ≈ [-25, +45]) → 99.99% детекція.

---

## 6. План міграції (SEC.11 implementation roadmap)

### 6.1 Schema migration

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_lorenz_seed_to_hardware_keys.rb
class AddLorenzSeedToHardwareKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :hardware_keys, :lorenz_seed_hex, :string, limit: 255
    add_column :telemetry_logs, :lorenz_state_x, :float
    add_column :telemetry_logs, :lorenz_state_y, :float
    add_column :telemetry_logs, :lorenz_state_z, :float
    add_column :telemetry_logs, :cold_start_flag, :boolean, default: false, null: false
  end
end
```

### 6.2 Backend (Ruby) — нові компоненти

| Компонент | LOC | Test count |
|-----------|-----|------------|
| `SilkenNet::SeedDerivation` (HKDF + HMAC + unpack) | ~40 | 8-10 |
| `HardwareKey#binary_lorenz_seed` (AR Encryption) | ~5 | 2 |
| `Attractor.calculate_z_from_state(x0, y0, z0, σ, ρ, β, n)` | ~15 (новий API) | 5 |
| `TelemetryUnpackerService` — per-tree seed dispatch + numeric divergence check | ~20 | 6 |
| `Provisioning::RegistrationService` — генерувати + повертати K_seed | ~10 | 3 |
| **RFC 5869 HKDF** — використати `OpenSSL::KDF.hkdf` (Ruby 3.2+, доступне у 4.0.2) | 0 | — |

### 6.3 Firmware

| Компонент | LOC | Test count |
|-----------|-----|------------|
| `bio_contract.rb` — приймати `(x0,y0,z0)` як args замість derive-from-DID | ~5 | 4 |
| `firmware/soldier/main.c` — HKDF/HMAC через mbedTLS (вже linkована для AES) | ~30 | 6 |
| `firmware/soldier/main.c` — Flash-зберігання K_seed (новий sector) | ~15 | 2 |
| `firmware/test/test_seed_derivation.c` — host-based parity з backend | ~80 | 8 |

### 6.4 Спільне (firmware ↔ backend parity)

- 1000-case fuzz: random `K_seed`, `epoch_day` → `(x₀,y₀,z₀)` byte-exact match.
- 100-case end-to-end: random `(K_seed, epoch_day, σ, ρ, β)` → Z-divergence < 1e-9.

### 6.5 Backward compat

**Pre-prod, breaking change.** Schema migration — clean. Жодних shim'ів. Існуючі `hardware_keys` без `lorenz_seed_hex` тригерять re-provisioning при наступному CoAP uplink (новий endpoint `POST /api/v1/provisioning/upgrade_seed`).

### 6.6 Послідовність розгортання

1. Schema migration + backend `SilkenNet::SeedDerivation` + spec (зелено).
2. Firmware HKDF/HMAC через mbedTLS + host-test parity (зелено).
3. `Provisioning::RegistrationService` оновлено + integration spec.
4. OTA bytecode оновлено для нового `bio_contract.rb` сигнатури.
5. Field migration: всі вузли проходять `upgrade_seed` upon first uplink post-deploy.
6. After 100% upgrade: видалити legacy DID-as-seed code path (`Attractor.calculate_z` з `chaos_seed: did_uint32` arg).
7. Включити numeric divergence (`< 0.001`) у `check_z_divergence!`. До цього — категоричний як fallback.

---

## 7. Threat model (post-SEC.11)

| Загроза | Захист |
|---------|--------|
| Sniff LoRa-пакет → відтворити Z | ❌ (без `K_seed` Z непередбачуваний) |
| Compromise одного `K_seed` (фізичний доступ до пристрою) | ⚠️ Один пристрій уразливий ≤ 24 год; інші — ні |
| Compromise `PROVISIONING_MASTER_KEY` | 🚨 Каскадне — потрібна окрема rotation strategy (SEC.9 окрема задача) |
| Replay вчорашнього валідного пакета | ❌ (`epoch_day` змінився, Z більше не валідний) |
| Підроблений `cold_start_flag = true` від device | ⚠️ Mitigation: server відкидає `cold_start` якщо < 7 днів від попередньої телеметрії |
| ARM ↔ x86 IEEE-754 drift > 0.001 | Емпірично < 1e-12; tolerance band 9 порядків запасу |

---

## 8. Open questions (для review)

1. **OTA-doable?** mbedTLS HKDF/HMAC додає ~4 KB до firmware image. Поточний bytecode area `0x0803F000` має ~52 KB вільного — комфортно, але треба підтвердити.
2. **Епохальний window** — 86400 секунд (1 доба) обраний з компромісу security ↔ time-sync requirements (FW.20 `CMD_TIME_SYNC` дає секундну точність). Якщо надалі знизимо до 1 год — потрібна частіша time-sync і ризик re-derive при network outage. Рекомендація: лишити 1 добу.
3. **Нacкільки часто треба ротувати `PROVISIONING_MASTER_KEY`?** Окрема задача SEC.9; не блокує SEC.11.
4. **Reboot edge case:** якщо Soldier reboot під час Lorenz iteration (рідко, але можливо при brown-out), RTC magic `"LZST"` може бути 50%-валідним. Mitigation: атомарний write (запис magic *після* (x,y,z)) — уже зроблено в FW.6.

---

## 9. Reference

- RFC 5869 — HMAC-based Extract-and-Expand Key Derivation Function (HKDF)
- RFC 2104 — HMAC: Keyed-Hashing for Message Authentication
- `docs/03_04_mruby_Lorenz_Attractor.md` — параметри σ, ρ, β; FW.7 Float decision
- `docs/03_05_Hardware_AES256_and_Security.md` — `PROVISIONING_MASTER_KEY` lifecycle
- `docs/05_01_Provisioning_and_OTA.md` — `POST /api/v1/provisioning/register` flow
- `docs/05_02_Proof_of_Growth_Pipeline.md` — `check_z_divergence!`, Dual Computation Integrity
- `docs/10_02_Action_Plan_Tracker.md` — **SEC.11** (this document is the design SSOT)
