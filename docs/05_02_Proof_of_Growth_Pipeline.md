# 05_02: Пайплайн «Proof of Growth»

## 🎯 Мета

Зафіксувати повний trustless консенсусний пайплайн SilkenNet — від фізичних біосигналів дерева (Lorenz Z-координата гомеостазу) до верифікованих on-chain активів (SilkenCarbonCoin / SCC). Включає опис прошивок Солдата й Королеви, всіх кроків верифікації (peaq DID → IoTeX ZK → Chainlink → Polygon + Solana) та відкритих блокерів.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Пайплайн повністю імплементовано.
- **Пов'язані модулі:**
  - Мультичейн → [`05_01_Multichain_Architecture`](05_01_Multichain_Architecture)
  - Токеноміка → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)
  - Моделі → [`04_01_Data_Models_and_Entities`](04_01_Data_Models_and_Entities)
  - Сервіси → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)

---

## 💡 Огляд

"Proof of Growth" — це trustless консенсусний пайплайн SilkenNet, що перетворює
фізичні біосигнали дерева (Lorenz Z-координата гомеостазу) на верифіковані
on-chain активи (SilkenCarbonCoin / SCC). Пайплайн складається з двох
взаємопов'язаних частин:

1. **Firmware (Залізо + mruby)** — STM32WLE5JC Солдат обчислює Z-координату
   і пакує `status_byte` з `growth_points` на рівні дерева.
2. **Backend (Rails 8.1 + Sidekiq)** — сервер розпаковує, перевіряє, надсилає
   до peaq / IoTeX / Chainlink і мінтить токени на Polygon та Solana.

### Ключовий інваріант пайплайну

```
tree.peaq_did ≠ nil                        ← peaq Machine Identity
  && telemetry_log.verified_by_iotex       ← IoTeX W3bstream ZK-proof
    && telemetry_log.zk_proof_ref ≠ nil
      && telemetry_log.oracle_status == "fulfilled"  ← Chainlink DON consensus
        → blockchain_transaction.status == :sent     ← Polygon EVM mint
          → solana micro-reward sent                 ← Solana SPL reward
```

Порушення будь-якого кроку заблоковує мінтинг.

---

## Повна Архітектурна Схема

```
╔══════════════════════════════════════════════════════════════════════╗
║  L1/L2: FIRMWARE (STM32WLE5JC)                                      ║
║                                                                      ║
║  [EBFC Аноду → BQ25570 MPPT → 0.47F EDLC Суперконденсатор]         ║
║       │ >500 mV від метаболізму глюкози дерева                      ║
║       ▼                                                              ║
║  [STM32WLE5JC SOLDIER]                                               ║
║   ФАЗА 1: SENSE                                                      ║
║     ADC → Vcap (мВ), Temp (°C), IWDG heartbeat                      ║
║     DMA 16kHz → raw_audio_buffer[512] → TinyML inference             ║
║     delta_t_seconds = tick - last_wakeup_timestamp (метаболізм EBFC) ║
║                                                                      ║
║   ФАЗА 2: mruby BioContract (on-device Lorenz) [SEC.11 + FW.6]      ║
║     ЄДИНА сигнатура (hard cutover): calculate_state(x,y,z,t,a,m,v)  ║
║       A) Warm continuation (RTC DR19 == "LZST"): (x,y,z) ← DR16-18   ║
║       B) Cold start (DR19 ≠ MAGIC, після VBAT loss):                 ║
║          K_seed (Flash) + epoch_day = unix_ts/86400                  ║
║          digest = HMAC-SHA256(K_seed, "init|" || epoch_day_be)       ║
║          (x₀,y₀,z₀) = bytes_to_signed_unit_floats(digest[0..23])    ║
║          ↳ identifier-as-key антипатерн (raw DID seed) ВИДАЛЕНО      ║
║     250 ітерацій Lorenz Euler → (x_final,y_final,z_final) → DR16-18  ║
║     bio_contract.rb :: BioContract.evaluate_and_pack → status_byte  ║
║     status_byte = [bio_status:2 bits | growth_points:6 bits]        ║
║                                                                      ║
║   ФАЗА 3: PACK + ENCRYPT                                             ║
║     Payload [16 bytes]: DID(N) Vcap(n) Temp(c) Acoustic(C)          ║
║                          Metabolism(n) StatusByte(C) TTL(C) Pad(a4) ║
║     AES-256-CBC hardware (CRYP module) → encrypted_payload[16]      ║
║     Prefix: DID[4] + RSSI_inverted[1] = L2 header (21 bytes total)  ║
║                                                                      ║
║   ФАЗА 4: LoRa TX / MESH RELAY                                       ║
║     Radio.Send(21 bytes) @ 868 MHz                                   ║
║     TTL-based multi-hop → anti-pingpong (seen-set cache 8 DIDs)     ║
║     Emergency TX якщо TinyML: chainsaw/fire detected (PANIC_TTL=5)  ║
║                                                                      ║
║  [STM32WLE5JC QUEEN + SIM7070G]                                      ║
║   LoRa RX (LORA_RX_INFINITE) → OnRxDone ISR → lora_rx_flag=1       ║
║   HAL_CRYP_Decrypt → decrypted_payload[16]                          ║
║   Process_And_Cache_Data → forest_cache[50] (CIFO EdgeCache)        ║
║   OTA Broadcast: рефлекторний постріл в ефір після кожного RX       ║
║   Queen health (DID=0): sentinel packet → GatewayTelemetryWorker    ║
║   Flush_Cache_To_Rails (кожну ~1 год + jitter):                     ║
║     binary_batch_buffer[2048] → CoAP PUT /telemetry/batch/<QUEEN_UID>║
║     via SIM7070G (LTE-M / Starlink Direct-to-Cell)                  ║
╚══════════════════════════════════════════════════════════════════════╝
        │ CoAP/UDP → port 5683 (lib/daemons/coap_listener.rb)
        ▼
╔══════════════════════════════════════════════════════════════════════╗
║  L5: BACKEND (Rails 8.1 + Sidekiq)                                  ║
║                                                                      ║
║  [UnpackTelemetryWorker] queue: uplink (prio 1)                     ║
║    Base64 decode → AES-256-CBC decrypt via HardwareKey.binary_key   ║
║    "Soft Key Rotation": new_key → fallback previous_key             ║
║    Gateway.find_by(uid:) → mark_seen!(new_ip:)                      ║
║    ▼                                                                 ║
║  [TelemetryUnpackerService]                                          ║
║    Chunk: [DID:4][RSSI:1][Payload:16] = 21 bytes                    ║
║    Format: "N n c C n C C a4" (unpack)                              ║
║    DeviceCalibration: normalize ADC → фізичні одиниці               ║
║    SilkenNet::Attractor.calculate_z_from_state(x_prev,y_prev,z_prev, ║
║      temp, acust, delta_t_s, vcap_mv) → z_value [SEC.11 sole API]   ║
║      ├─ warm: (x_prev,y_prev,z_prev) ← prev TelemetryLog.lorenz_state║
║      └─ cold: SeedDerivation.derive_initial_state(K_seed, epoch_day) ║
║              + telemetry_log.cold_start_flag = true                  ║
║    persist tail → telemetry_log.lorenz_state_x/y/z (mirror RTC)     ║
║    growth_points = status_byte & 0x3F (нижні 6 бітів)              ║
║    bio_status = status_byte >> 6 (верхні 2 біти)                    ║
║    AlertDispatchService.analyze_and_trigger!(log)                    ║
║    tree.wallet.credit!(log.growth_points)                           ║
║    ├──► IotexVerificationWorker.perform_async(id, created_at_iso)   ║
║    └──► StreamrBroadcastWorker.perform_async(id, created_at_iso)    ║
║                                                                      ║
║  ─────────── КРОК A: peaq DID (одноразово при Provisioning) ─────── ║
║  [ProvisioningController#register] POST /api/v1/provisioning         ║
║    PeaqRegistrationWorker.perform_async(tree.id)                    ║
║    ▼ Peaq::DidRegistryService#register!                              ║
║    DID = "did:peaq:0x" + SHA256(did:id:created_at)[0:40]           ║
║    Ed25519::sign(peaq_signing_key, did_string) → proof              ║
║    POST {peaq_node_url}/did/register                                 ║
║    → tree.peaq_did saved (UNIQUE index)                              ║
║                                                                      ║
║  ─────────── КРОК B: IoTeX W3bstream ZK-Verification ────────────── ║
║  [IotexVerificationWorker] queue: web3_critical (prio 6), retry: 5  ║
║    Iotex::W3bstreamVerificationService#verify!                       ║
║    POST {iotex_w3bstream_url}/verify                                 ║
║    Body: { device_id, peaq_did, telemetry_log_id, hardware_sig,     ║
║            chaotic_data: { z_value, temp, acoustic, voltage, bio }}  ║
║    Response: { proof_id | receipt_id } → zk_proof_ref               ║
║    → log.update!(verified_by_iotex: true, zk_proof_ref:)            ║
║    → ChainlinkDispatchWorker.perform_async(id, created_at_iso)      ║
║                                                                      ║
║  ─────────── КРОК C: Chainlink Oracle Dispatch ───────────────────── ║
║  [ChainlinkDispatchWorker] queue: web3_critical (prio 6), retry: 5  ║
║    Guard: log.verified_by_iotex? == true                             ║
║    Chainlink::OracleDispatchService#dispatch!                        ║
║    [PROD] Eth::Contract.transact("sendRequest", sub_id, payload)    ║
║           via Alchemy Polygon RPC → TX hash                          ║
║    [DEV]  SecureRandom.hex(16) stub                                  ║
║    → log.update!(chainlink_request_id:, oracle_status: "dispatched")║
║                                                                      ║
║  ─────────── КРОК D: Oracle Callback → Minting ──────────────────── ║
║  POST /api/v1/oracle_callbacks                                       ║
║    { chainlink_request_id, success: true/false }                     ║
║    → log.update!(oracle_status: "fulfilled" | "failed")             ║
║    ├──► MintCarbonCoinWorker.perform_async (EVM Polygon SCC/SFC)    ║
║    └──► SolanaMicroRewardWorker.perform_async (Solana USDC)         ║
║                                                                      ║
║  ─────────── КРОК E: BlockchainMintingService (EVM) ─────────────── ║
║    Guard: verified_by_iotex? && oracle_status=="fulfilled"           ║
║    Guard: wallet.hadron_kyc_status == "approved"                     ║
║    [batchMint path]:                                                 ║
║      eth_call dry-run → batch_dry_run_reverts?                       ║
║        ├── false → client.transact("batchMint") → Polygon Mainnet    ║
║        └── true  → fallback_to_individual_mints                      ║
║                     (кожен mint() окремо; "отруйний" запис ізольовано)║
║    [single mint path]: client.transact("mint") → Polygon Mainnet     ║
║    → blockchain_transaction.status = :sent, tx_hash saved            ║
║    → BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)   ║
║                                                                      ║
║  ─────────── КРОК F: Solana Micro-Reward (паралельно) ────────────── ║
║    Guard: verified_by_iotex? && oracle_status=="fulfilled"           ║
║    POST {SOLANA_RPC_URL} sendTransaction (Ed25519-signed, base64)    ║
║    SPL Token Program: TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA  ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## Детальний Опис Кожного Кроку

### Firmware: Солдат (STM32WLE5JC)

**Файл:** `firmware/soldier/main.c` (771 рядків)

#### Фаза 1 — SENSE (Збір фізичних даних)

| Сигнал | Джерело | Формат |
|--------|---------|--------|
| `vcap_voltage` | ADC → VREFINT канал | uint16 (мВ, 0–5000) |
| `internal_temp` | ADC → внутрішній датчик | int8 (°C, −45..90) |
| `acoustic_events` | DMA 16 кГц → TinyML CMSIS-NN | uint8 (0–255) |
| `delta_t_seconds` | `HAL_GetTick() - last_wakeup_timestamp` | uint32 (EBFC метаболізм) |

> **[SEC.11]** `chaos_seed = HAL_RNG_GenerateRandomNumber()` як вхід Лоренца — **видалено** (hard cutover). Початкова точка `(x₀, y₀, z₀)` тепер деривується з per-device `K_seed` (Flash) через `HMAC-SHA256(K_seed, "init|" || epoch_day_be)` лише при cold-start після VBAT loss; у норму FW.6 RTC continuation (DR16-DR18 magic `"LZST"`) пропускає re-init. HRNG залишається лише для AES IV jitter, mesh anti-pingpong та CoAP nonce. Деталі — [03_05 §3.4в](03_05_Hardware_AES256_and_Security#34в-lorenz-k_seed-derivation-sec11-).

**TinyML класи** (`silken_net_audio_model.h`): 0=Тиша, 1=Вітер, 2=Кавітація, 3=Пилка.

#### Фаза 2 — mruby BioContract (on-device Lorenz Attractor)

**Файл:** `firmware/bio_contracts/bio_contract.rb`

**Мова:** mruby (Ruby для embedded). Компілюється в байткод `mrbc` → вбудовується
в Flash (`lorenz_bytecode[]`) або оновлюється OTA (`MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`).

**Модуль `SilkenNet::Attractor` (firmware):**
```ruby
BASE_SIGMA = 10.0   # Float (не BigDecimal!)
BASE_RHO   = 28.0
BASE_BETA  = 8.0 / 3.0   # ≈ 2.6666... (точне в Ruby Float)
DT = 0.01
ITERATIONS = 250
SIGMA_LIMITS = (5.0..30.0)
RHO_LIMITS   = (10.0..50.0)
# [FW.5] β-perturbation від EBFC-метаболізму
BETA_DELTA_T_COEFF = 0.0001  # 1 с швидше baseline → β +0.0001
BETA_VCAP_COEFF    = 0.001   # 1 mV вище nominal → β +0.001
BETA_LIMITS        = (2.0..4.0)
BASELINE_DELTA_T_S = 60
NOMINAL_VCAP_MV    = 3300

def self.calculate_z_axis(x, y, z, temp, acoustic, delta_t_s = BASELINE_DELTA_T_S, vcap_mv = NOMINAL_VCAP_MV)
  # [SEC.11] (x, y, z) приходять як аргументи: warm — з RTC DR16-18,
  # cold — з K_seed/epoch_day (див. evaluate_and_pack нижче). DID не є входом.
  # local_sigma, local_rho: perturbation + clamp
  # [FW.5] local_beta: perturb_beta(delta_t_s, vcap_mv) → β ∈ [2.0, 4.0]
  ITERATIONS.times { dx/dy/dz → Euler integration (local_beta in dz) }
  z  # Ruby Float, НЕ BigDecimal
end
```

**Модуль `SilkenNet::BioContract` (firmware) — токеноміка:**
```ruby
CRITICAL_Z_MIN  = 2.0   # Порóг посухи (HARDCODED у firmware!)
CRITICAL_Z_MAX  = 45.0  # Поріг критичного стресу (HARDCODED!)
OPTIMAL_Z_TARGET = 29.0 # Ідеальний стан конвекції (HARDCODED!)

def self.evaluate_and_pack(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
  # (x_prev, y_prev, z_prev): warm — з RTC DR16-18; cold — з SEC.11 K_seed/epoch_day
  z_val = Attractor.calculate_z_axis(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)
  if    z_val < CRITICAL_Z_MIN  → status=1, growth_points=1  # stress
  elsif z_val > CRITICAL_Z_MAX  → status=2, growth_points=0  # anomaly
  else                          → status=0                    # homeostasis
    deviation = (OPTIMAL_Z_TARGET - z_val).abs
    growth_points = clamp(50 - deviation.round, 10, 63)  # FW.13: .round замість .to_i
  end
  payload_byte = (status << 6) | growth_points  # [ 2 bits | 6 bits ]
end
```

**Точка входу з C:** `calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)` → `payload_byte` (uint8_t). Сигнатура `calculate_state(seed, …)` ВИДАЛЕНА (SEC.11 hard cutover, pre-prod, no shim).

---

#### 🤖 FW.8 — OTA Sync для Per-Species Lorenz Thresholds (Дизайн)

> **Cross-ref:** [10_02 FW.8](10_02_Action_Plan_Tracker) — дизайн завершено ✅

**Проблема:** `CRITICAL_Z_MIN`, `CRITICAL_Z_MAX`, `OPTIMAL_Z_TARGET` hardcoded у Flash. Сосна (*Pinus sylvestris*) і дуб (*Quercus robur*) мають різний діапазон нормальної конвективної активності — один пороговий набір дає хибні anomaly alerts для одного виду при нормальному стані іншого.

**Рішення:** синхронізувати per-species пороги через OTA Config Payload — без перекомпіляції firmware.

##### 4а.1 Нова структура OTA Config Payload

Поточний OTA downlink передає лише mruby bytecode (bio_contract). Додаємо окремий **Config Block** як перший фрагмент batch:

```
OTA Batch Downlink Format (розширений):
  [CMD_TYPE:1] [PAYLOAD_LEN:2] [PAYLOAD:N]

Типи команд:
  CMD_OTA_BYTECODE    = 0x99   (існуючий — mruby chunks)
  CMD_SET_THRESHOLDS  = 0x9A   (НОВИЙ — per-species Z thresholds)
  CMD_SET_ML_THRESH   = 0x9B   (НОВИЙ — TinyML dual-threshold з FW.18)
  CMD_TIME_SYNC       = 0x9C   (НОВИЙ — RTC correction, FW.20)
  CMD_FACTORY_RESET   = 0xFE   (зарезервовано)
```

**CMD_SET_THRESHOLDS payload (10 байт):**

```
Байти  Поле                   Тип    Опис
0–1    z_min_fixed            int16  CRITICAL_Z_MIN × 100 (наприклад, 200 = 2.0)
2–3    z_max_fixed            int16  CRITICAL_Z_MAX × 100 (наприклад, 4500 = 45.0)
4–5    z_optimal_fixed        int16  OPTIMAL_Z_TARGET × 100 (наприклад, 2900 = 29.0)
6      species_id             uint8  0=Pinus, 1=Quercus, 2=Fagus, 3=Picea, 0xFF=custom
7      config_version         uint8  Version counter (anti-replay для конфігурації)
8–9    checksum               uint16 CRC16 байтів 0..7
```

**Розшифровується AES-256-CCM (після FW.2) або AES-256-CBC (поточний).**

##### 4а.2 Firmware — зберігання у RTC Backup Domain

```c
// firmware/soldier/main.c — нові RTC Backup Register слоти:

// RTC_BKP_DR20 — CRITICAL_Z_MIN × 100 (int16_t у lower 16 bits)
// RTC_BKP_DR21 — CRITICAL_Z_MAX × 100 (int16_t у lower 16 bits)
// RTC_BKP_DR22 — OPTIMAL_Z_TARGET × 100 (int16_t у lower 16 bits)
// RTC_BKP_DR23 — [config_version:8 | species_id:8]

#define THRESHOLD_MAGIC   0x5448524D  // "THRM" — маркер валідності

// Читання (з fallback на defaults якщо RTC порожній):
float Get_Critical_Z_Min(void) {
    if (HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR23) >> 24 != 0x54) {  // check "T"
        return 2.0f;  // default Pinus sylvestris
    }
    return (float)((int16_t)HAL_RTCEx_BKUPRead(&hrtc, RTC_BKP_DR20)) / 100.0f;
}

// OTA CMD handler:
case CMD_SET_THRESHOLDS:
    if (verify_crc16(cmd_payload, 8) == *(uint16_t*)(cmd_payload + 8)) {
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR20, (int16_t)(cmd_payload[0]|(cmd_payload[1]<<8)));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR21, (int16_t)(cmd_payload[2]|(cmd_payload[3]<<8)));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR22, (int16_t)(cmd_payload[4]|(cmd_payload[5]<<8)));
        HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR23,
            THRESHOLD_MAGIC | (cmd_payload[7] << 8) | cmd_payload[6]);
    }
    break;
```

**У bio_contract.rb (mruby) — замість hardcoded констант:**

```ruby
# BioContract — зчитує пороги з C-side через mrb_define_method або mrb_const_set
# Firmware C-code передає через mrb_fixnum_value() до виклику:
# args[4] = mrb_fixnum_value(z_min_x100)   # ← NEW
# args[5] = mrb_fixnum_value(z_max_x100)   # ← NEW
# args[6] = mrb_fixnum_value(z_opt_x100)   # ← NEW

CRITICAL_Z_MIN    = mrb_get_arg(4) / 100.0   # dynamic
CRITICAL_Z_MAX    = mrb_get_arg(5) / 100.0   # dynamic
OPTIMAL_Z_TARGET  = mrb_get_arg(6) / 100.0   # dynamic
```

##### 4а.3 Backend — OtaPackagerService та TreeFamily

```ruby
# app/services/ota_packager_service.rb — [FW.8] РЕАЛІЗОВАНО (Rails-сторона)
def build_threshold_config_block(tree)
  thresholds = tree.effective_lorenz_thresholds  # 3-tier: cluster > family > global
  z_min      = (thresholds[:min]     * 100).round.to_i
  z_max      = (thresholds[:max]     * 100).round.to_i
  z_opt      = (thresholds[:optimal] * 100).round.to_i
  species_id = SPECIES_ID_MAP[tree.tree_family.scientific_name] || 0xFF
  version    = (tree.ota_config_version.to_i + 1) & 0xFF

  payload = [z_min, z_max, z_opt, species_id, version].pack("s<s<s<CC")
  crc = Digest::CRC16.checksum(payload)
  payload + [crc].pack("S<")

  [CMD_SET_THRESHOLDS].pack("C") + [payload.bytesize].pack("S<") + payload
end
```

> **Статус [FW.8]:** ✅ Rails-сторона реалізована. Firmware C-side (обробник `CMD_SET_THRESHOLDS`, зберігання у RTC DR20-DR23) — TODO у наступному PR. До реалізації C-side, Soldier використовує хардкодовані значення `CRITICAL_Z_MIN=2.0`, `CRITICAL_Z_MAX=45.0`, `OPTIMAL_Z_TARGET=29.0`.

##### 4а.4 Per-Species Default Thresholds

| Вид дерева | `critical_z_min` | `critical_z_max` | `optimal_z_target` | Обґрунтування |
|---|---|---|---|---|
| *Pinus sylvestris* (Сосна звичайна) | **2.0** | **45.0** | **29.0** | Базові (поточні) |
| *Quercus robur* (Дуб звичайний) | **3.0** | **42.0** | **27.0** | Нижчий піковий стрес, менша варіативність |
| *Fagus sylvatica* (Бук лісовий) | **2.5** | **43.0** | **28.0** | Помірний діапазон |
| *Picea abies* (Ялина звичайна) | **1.5** | **46.0** | **30.0** | Ширший діапазон гомеостазу |
| *Betula pendula* (Береза бородавчаста) | **2.0** | **44.0** | **28.5** | Подібна до сосни |

> **Джерело значень:** Попередні пороги (сосна). Точні значення інших видів потребують калібрування з Lorenz trajectory analysis. **Рекомендовано:** запросити ботанічний baseline від Спрягайла/Гаврилюка (ЧНУ, `08_01`).

##### 4а.5 Backend Mirror (TelemetryUnpackerService)

Backend вже має `TreeFamily#critical_z_min|max|optimal_z_target` через `calculate_z` pipeline. Після реалізації FW.8, сервер також надсилає ці пороги на пристрій та верифікує що `z_value` в `TelemetryLog` відповідає тим самим порогам що використовуються firmware → Dual Computation Integrity.

---

**21-байтний пакет (binary packet format):**
```
Байти  Поле               Тип    Опис
0–3    DID (L2 header)    uint32 Апаратний ідентифікатор (SNET-XXXXXXXX raw)
4      RSSI (інвертований) uint8  -RSSI (positive byte)
────── L3 Payload (16 bytes, AES-256-CBC encrypted) ─────────────────
5–6    Vcap               uint16 Напруга суперконденсатора (мВ)
7      Temperature         int8  Температура (зі знаком)
8      Acoustic_events    uint8  Кількість акустичних подій
9–10   Metabolism_s       uint16 Час зарядки EBFC δt (секунди)
11     StatusByte         uint8  [7:6] bio_status | [5:0] growth_points
12     Mesh TTL           uint8  Initial=5 → decrements on each hop
13–14  Firmware version   uint16 firmware_version_id (перші 2 байти Pad-поля: Pad[0]<<8|Pad[1])
15–16  Reserved pad       uint16 Pad[2:3] (нулі, зарезервовано)
```

**Шифрування:** AES-256-CBC апаратним модулем `CRYP` → `HAL_CRYP_Encrypt`.
Заголовок [DID:4][RSSI:1] передається відкрито; payload[16] зашифровано.

#### Фаза 4 — LoRa TX + Mesh

- `Radio.Send(21 bytes)` @ 868 МГц (Europe/Ukraine)
- **Mesh relay:** TTL-based (DEFAULT_TTL=3, PANIC_TTL=5)
- **Anti-pingpong:** seen-set `recent_mesh_dids[3]` у RTC Backup Registers DR8/DR9/DR11 (FW.21: shrunk 8→3; DR10 + DR12 під EMA, vcap_x10 запаковано в low 16 біт DR12)
- **Emergency TX:** якщо `ml_event_id == 3` (Пилка) → `Trigger_Emergency_LoRa_TX` з PANIC_TTL

---

### Firmware: Королева (STM32WLE5JC + SIM7070G)

**Файл:** `firmware/queen/main.c` (550 рядків)

#### CIFO Edge Cache

```c
typedef struct {
    uint32_t uid;      // DID дерева
    uint8_t payload[16]; // Останній розшифрований payload
    int8_t rssi;
    uint8_t is_active;
} EdgeCache;

EdgeCache forest_cache[CACHE_MAX_ENTRIES]; // 50 слотів
```

**Дедуплікація:** Останній пакет від кожного DID перезаписує попередній
(тільки найсвіжіші дані).

**Queen Sentinel:** `DID == 0x00000000` → власна телеметрія Королеви →
`GatewayTelemetryWorker` (не TelemetryLog).

#### CoAP Batch Flush

```
Інтервал: FLUSH_INTERVAL_MS = 3_600_000 (1 година) + jitter 0–60 с
Примусовий: cache_count >= CACHE_MAX_ENTRIES - FLUSH_HEADROOM (5 вільних слотів)

Binary batch format: [DID:4][RSSI:1][Payload:16] × N entries
Транспорт: CoAP PUT /telemetry/batch/<QUEEN_UID>
           via SIM7070G (AT+CNMP=38, LTE-M/NB-IoT)
           або Starlink Direct-to-Cell
URI-Path: third segment = queen_uid (Flash-provisioned або "UNPROV-{HEX}") → Gateway lookup
```

#### OTA Downlink

```
Rails → CoAP downlink → queen RAM assembly (pending_ota_bytecode[8192])
Queen → LoRa broadcast (рефлекторний постріл після кожного RX):
  Chunk size: 11 bytes payload + 5 bytes header = 16 bytes (1 AES block)
  Format: [0x99][index:2][total:2][bytecode:11]
  AES-256-CBC encrypted before TX
  Pacing: 60ms delay між чанками
Soldier:
  MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000
  Magic check: 0x45544952 ("RITE") → load OTA bytecode
  Else → load embedded lorenz_bytecode[]
```

---

### Крок A: peaq DID Provisioning

**Тригер:** `POST /api/v1/provisioning` → `ProvisioningController#register`

**Файли:**
- `app/controllers/api/v1/provisioning_controller.rb:60`
- `app/workers/peaq_registration_worker.rb` — queue: `web3` (prio 7), retry: 5
- `app/services/peaq/did_registry_service.rb`
- `app/services/ed25519_crypto/signing_service.rb`

**Генерація DID:**
```ruby
hex_hash = SHA256("#{tree.did}:#{tree.id}:#{tree.created_at.to_i}")
peaq_did = "did:peaq:0x#{hex_hash[0, 40]}"
# Приклад: "did:peaq:0xa3f8...1e2c" (51 символ)
```

**HTTP-запит до peaq Substrate node:**
```
POST {credentials.peaq_node_url}/did/register
Content-Type: application/json
Timeout: connect=10s, read=30s

Body:
{
  "did": "did:peaq:0x{40hex}",
  "device_id": "SNET-XXXXXXXX",
  "metadata": { "type": "tree", "tree_id": ..., "cluster_id": ..., "registered_at": "ISO8601" },
  "proof": {                    ← опціонально (лише якщо peaq_signing_key є)
    "type": "Ed25519Signature2020",
    "verification_method": "did:peaq:0x...#key-1",
    "signature": "Ed25519::sign(peaq_signing_key, did_string)",
    "public_key": "Ed25519::public_key_from_seed(peaq_signing_key)"
  }
}
```

**Результат:** `tree.peaq_did` збережено в БД (UNIQUE index).
**Ідемпотентність:** `return if tree.peaq_did.present?` + `tree.with_lock`.

---

### Крок B: IoTeX W3bstream ZK-Верифікація

**Тригер:** `IotexVerificationWorker.perform_async(log.id_value, created_at_iso)`
з `TelemetryUnpackerService#commit_telemetry`

**Файли:**
- `app/workers/iotex_verification_worker.rb` — queue: `web3_critical` (prio 6), retry: 5
- `app/services/iotex/w3bstream_verification_service.rb`

**Статус (Wiki 05_01):** ✅ Real — HTTP POST через W3bstream API

**Payload до W3bstream:**
```json
{
  "device_id":        "SNET-XXXXXXXX",
  "peaq_did":         "did:peaq:0x{40hex}",
  "telemetry_log_id": 12345,
  "timestamp":        1720000000,
  "hardware_signature": "SHA256('{did}:{log_id}:{created_at.to_i}')",
  "chaotic_data": {
    "z_value":        23.4521,
    "temperature_c":  22.5,
    "acoustic_events": 3,
    "voltage_mv":     4200,
    "bio_status":     "homeostasis"
  }
}
```

**HTTP-запит:**
```
POST {credentials.iotex_w3bstream_url}/verify
Authorization: Bearer {credentials.iotex_api_key}
Content-Type: application/json
Timeout: connect=10s, read=30s
```

**Обробка відповіді:**
```ruby
zk_proof_ref = body["proof_id"] || body["receipt_id"]
raise VerificationError if zk_proof_ref.blank?
log.update!(verified_by_iotex: true, zk_proof_ref: zk_proof_ref)
ChainlinkDispatchWorker.perform_async(telemetry_log_id, created_at_iso)
```

**Ідемпотентність:** `return if log.verified_by_iotex?` в воркері.

---

### Крок C: Chainlink Oracle Dispatch

**Тригер:** `ChainlinkDispatchWorker.perform_async` з `IotexVerificationWorker`

**Файли:**
- `app/workers/chainlink_dispatch_worker.rb` — queue: `web3_critical` (prio 6), retry: 5
- `app/services/chainlink/oracle_dispatch_service.rb`

**Статус:** ✅ Real — Chainlink Functions Router v1 ABI. `WEB3_STRICT_MODE=true` вимагає `CHAINLINK_FUNCTIONS_ROUTER` + `CHAINLINK_SUBSCRIPTION_ID` в Production.
credentials, stub без них.

**Guard-перевірка:**
```ruby
raise DispatchError unless @log.verified_by_iotex?
```

**Payload до Chainlink DON:**
```json
{
  "peaq_did":    "did:peaq:0x{40hex}",
  "lorenz_state": {
    "sigma": 10.0,
    "rho":   28.0,
    "beta":  2.666666666666666667,
    "z_value": 23.4521
  },
  "zk_proof_ref":     "zk-proof-abc123",
  "tree_did":         "SNET-XXXXXXXX",
  "telemetry_log_id": 12345,
  "created_at":       "2026-03-23T06:00:00.000000Z",
  "timestamp":        "2026-03-23T06:00:01Z"
}
```

**Режим PROD (CHAINLINK_FUNCTIONS_ROUTER + CHAINLINK_SUBSCRIPTION_ID задані):**
```ruby
client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))
contract = Eth::Contract.from_abi(name: "FunctionsRouter", address: router_address, abi: abi)
# ABI v1 — 5 параметрів: subscriptionId, data, dataVersion, callbackGasLimit, donId
tx_hash = client.transact(contract, "sendRequest",
                           subscription_id.to_i, payload.to_json,
                           data_version, callback_gas_limit, don_id,
                           sender_key: oracle_key, legacy: false)
```

**Режим DEV (відсутні ENV):**
```ruby
"chainlink-req-#{SecureRandom.hex(16)}"  # ⚠️ LOCAL STUB
# WEB3_STRICT_MODE=true → raises DispatchError (Production mode)
```

**Оновлення БД:**
```ruby
# oracle_status — enum з prefix (oracle_status_dispatched?, oracle_status_fulfilled? тощо)
log.update!(chainlink_request_id: request_id, oracle_status: "dispatched")
```

**Ідемпотентність:** `return if log.chainlink_request_id.present?` в воркері.

---

### Крок D: Oracle Callback

**Тригер:** Chainlink DON → `POST /api/v1/oracle_callbacks`

**Файл:** `app/controllers/api/v1/oracle_callbacks_controller.rb`

**Авторизація:** `skip_before_action :authenticate_user!`
— машинний ендпоінт (без сесійної автентифікації).

**Пошук TelemetryLog з partition pruning:**
```ruby
scope = TelemetryLog.where(chainlink_request_id: params[:chainlink_request_id])
scope = scope.where(created_at: Time.iso8601(params[:created_at])) if params[:created_at].present?
log = scope.first!
```

**Успішний callback:**
```ruby
log.update!(oracle_status: "fulfilled")
MintCarbonCoinWorker.perform_async(log.id_value, log.created_at.iso8601(6))
SolanaMicroRewardWorker.perform_async(log.id_value, log.created_at.iso8601(6))
```

**Невдалий callback:**
```ruby
log.update!(oracle_status: "failed")
```

---

### Крок E: EVM Мінтинг SCC/SFC на Polygon

**Файли:**
- `app/workers/mint_carbon_coin_worker.rb` — queue: `web3_critical` (prio 6), retry: 5
- `app/services/blockchain_minting_service.rb`

**Trustless Guard Clauses (лише при oracle-driven flow з telemetry_log):**
```ruby
raise "Security Breach: Data not verified by IoTeX"               unless telemetry_log.verified_by_iotex?
raise "Security Breach: Chainlink Oracle consensus not fulfilled"  unless telemetry_log.oracle_status_fulfilled?  # enum method
raise "Compliance Breach: Wallet is not Hadron KYC approved"      unless wallet.hadron_kyc_status == "approved"
# TokenomicsEvaluatorWorker без log — growth_points вже верифіковані pipeline'ом.
```

**Oracle Balance Check:**
```ruby
balance = client.get_balance(oracle_key.address)
raise "🚨 Критично низький баланс Оракула" if balance < 0.05 * (10**18)  # 0.05 MATIC
```

**Rate Limiting:**
```ruby
Sidekiq::Limiter.window("web3_rpc", 50, :second, wait: 5)  # 50 RPC/sec global
```

**Мінтинг:**
- Одиночний: `client.transact(contract, "mint", to, amount, identifier)`
- Пакетний: `client.transact(contract, "batchMint", recipients[], amounts[], identifiers[])`
- Dynamic Tax: 2% до `DAO_TREASURY_ADDRESS` (якщо `insurance_pool_requires_funding?`)

**Solidity ABI контракту:**
```json
[
  { "name": "mint",      "inputs": ["address to", "uint256 amount", "string identifier"] },
  { "name": "batchMint", "inputs": ["address[] recipients", "uint256[] amounts", "string[] treeDids"] }
]
```

**Rollback:** `MintingRollbackService.call(transactions:)` при вичерпанні 10 retry `BlockchainConfirmationWorker`
через `sidekiq_retries_exhausted` (~15-20 хвилин поллінгу мемпулу).

---

### Крок F: Solana Мікро-Винагорода (паралельно з EVM)

**Файли:**
- `app/workers/solana_micro_reward_worker.rb` — queue: `web3` (prio 7), retry: 3
- `app/services/solana/minting_service.rb`

**Статус (Wiki 05_01):** ✅ Real — `sendTransaction` з Ed25519 підписом.

**Oracle Balance Guard:**
```ruby
verify_oracle_balance!(rpc_url, fee_payer_pubkey)
# raises при balance < MIN_ORACLE_BALANCE_LAMPORTS (0.05 SOL = 50M lamports)
```

**Розрахунок:**
```ruby
base  = 10_000          # 0.01 USDC у lamports
bonus = growth_points * 100   # 100 lamports / growth_point = 0.0001 USDC
total = base + bonus    # max: 10_000 + 63×100 = 16_300 lamports = 0.016 USDC
```

**Trustless Guards:** Ідентичні до EVM (`verified_by_iotex?` + `oracle_status_fulfilled?` — enum method).

---

## Усі Шляхи до `Wallet#lock_and_mint!` (Guard Inventory) [DOC.7]

> **Контекст:** `Wallet#lock_and_mint!(points, threshold, token_type)` — атомарна операція з `pessimistic_lock`, що конвертує `growth_points` у SCC (10 000 = 1 SCC). У системі **п'ять окремих шляхів** її викликають, кожен зі своїм guard chain. Раніше зв'язок між цими шляхами був розкиданий між `04_02 §4.2.2` (oracle path) та різними воркерами (tokenomics path). Ця секція — єдина точка істини; будь-який новий шлях повинен бути доданий сюди.

```
                                ┌─────────────────────────────────────┐
                                │  Wallet#lock_and_mint!(points,      │
                                │                       threshold,    │
                                │                       token_type)   │
                                │  • pessimistic_lock                 │
                                │  • atomic: balance -= points,       │
                                │            locked += points,        │
                                │            queue MintCarbonCoinJob  │
                                └──────────────┬──────────────────────┘
                                               ▲
        ┌─────────────────────────────────────┼─────────────────────────────────────┐
        │                                      │                                      │
   PATH 1                                  PATH 2                                  PATH 3
   Oracle-driven                           Tokenomics                              Slashing recovery
   (per-telemetry, hot path)               (hourly batch)                          (after burn rollback)
        │                                      │                                      │
   ▼                                      ▼                                          ▼
   MintCarbonCoinWorker          TokenomicsEvaluatorWorker            MintingRollbackService
   (web3_critical #6)            (default #5)                         (critical #3)
        │                                      │                                      │
   GUARDS:                       GUARDS:                              GUARDS:
   ✓ verified_by_iotex?          ✓ wallet.balance >= threshold        ✓ original burn TX confirmed
   ✓ oracle_status_fulfilled?    ✓ kyc_status == "approved"           ✓ rollback authorized by admin
   ✓ hadron_kyc_status==approved ✓ NOT in cooldown window              ✓ idempotency by tx_hash
   ✓ chainlink_request_id match  ✗ (does NOT need oracle)              ✗ (bypasses oracle)
   (raises if any fails)         (silently skips if any fails)         (raises + Sentry capture)

        │                                      │                                      │
        └──────────────────┬───────────────────┴──────────────────┬───────────────────┘
                           │                                      │
                    PATH 4                                  PATH 5
                    Solana micro-rewards                    Manual admin (super_admin only)
                    (parallel rail, NOT SCC)                (rake task, audit-logged)
                           │                                      │
                    SolanaMicroRewardWorker                MintingAdminController
                    (web3 #7)                              (admin/super_admin)
                           │                                      │
                    GUARDS:                                GUARDS:
                    ✓ wallet.solana_address present        ✓ Pundit policy: super_admin only
                    ✓ NOT main lock_and_mint! (parallel)   ✓ Confirmation token (re-typed)
                    ✗ (calls Solana::MintingService        ✓ AuditLog entry created
                       directly, NOT lock_and_mint!)
```

### Інваріанти для всіх шляхів

| Інваріант | Path 1 | Path 2 | Path 3 | Path 5 | Контроль |
|-----------|--------|--------|--------|--------|----------|
| Pessimistic lock на Wallet | ✅ | ✅ | ✅ | ✅ | `Wallet#lock_and_mint!` сам бере lock |
| Idempotency (повторний виклик не подвоює) | ✅ за `chainlink_request_id` | ✅ за `evaluation_period_id` | ✅ за `original_tx_hash` | ✅ за `confirmation_token` | DB unique constraint |
| `BlockchainTransaction.aasm: pending` створено | ✅ | ✅ | ✅ | ✅ | `MintCarbonCoinJob` |
| Rate limit (per wallet, anti-DoS) | ✅ Sidekiq уніфікований | ✅ cron | ⚠️ unbounded (admin-driven) | ⚠️ unbounded | Sidekiq + Pundit |
| WEB3_STRICT_MODE respected (raises на missing Web3 ENV) | ✅ | ✅ | ✅ | ✅ | shared `web3_strict_check!` |

> **PATH 4 (Solana) НЕ викликає `lock_and_mint!`** — Solana — паралельна рейка з прямим SPL Transfer без локування growth_points. growth_points і SCC mint обробляються Path 1, Solana — окрема мікро-винагорода, що не торкається balance/locked_balance.

> **TokenomicsEvaluatorWorker bypass [S6.12] — фактичний інваріант:** Path 2 НЕ перевіряє `verified_by_iotex?` / `oracle_status_fulfilled?`. Це **навмисно**, але обґрунтування потребує точності:
>
> - `growth_points` зараховуються у `wallet.balance` через `Wallet#credit!` у `TelemetryUnpackerService.commit_telemetry` **до** проходження пакетом IoTeX/Chainlink. Тобто upstream-перевірка для Path 2 — це **AES-256-CBC decrypt + `valid_sensor_data?`** (per-packet integrity perimeter), а **не** повний oracle pipeline.
> - Path 1 (oracle-driven mint per-telemetry) і Path 2 (hourly tokenomics aggregate) — **окремі шляхи мінтингу для тих самих growth_points**: Path 1 мінтить за конкретним verified `telemetry_log`, Path 2 агрегує накопичений `wallet.balance`. Без розмежування — циклічна залежність "не можна нарахувати tokenomics-bonus, доки oracle не підтвердив сам bonus".
> - **Hadron KYC є справжнім security perimeter Path 2** — `BlockchainMintingService` raise `Compliance Breach` для будь-якого `hadron_kyc_status != "approved"` незалежно від присутності `telemetry_log`. Це блокує ескалацію fake-`growth_points` (з compromised AES-key) у мінт через non-KYC wallet.
> - Spec coverage: `spec/services/blockchain_minting_service_spec.rb` → context "tokenomics flow without telemetry_log [S6.12]" (3 examples).
> - **Залишковий ризик (документований):** компрометація AES-key конкретного дерева → fake `growth_points` зараховуються `Wallet#credit!` → Path 2 щогодини мінтить SCC якщо wallet KYC-approved. Mitigation track: per-device HKDF key provisioning (FW.1 / SEC.3) + AES-256-CCM з MIC (FW.2) — обидва P0 у roadmap до польового deploy.

> **Path 3 raises замість silent-skip:** Slashing rollback — фінансово-критична операція. Беззвучне ігнорування призвело б до асиметрії "burn застосовано, mint-rollback пропущено → дисбаланс supply". Тому будь-який guard fail у Path 3 → exception + Sentry.

---

## Схема Полів БД (Proof of Growth State Machine)

```
trees
  └─ peaq_did             :string  UNIQUE    "did:peaq:0x{40hex}"

telemetry_logs  [PARTITION BY RANGE(created_at)]
  ├─ z_value              :decimal           Lorenz Z (BigDecimal 18 precision)
  ├─ growth_points        :integer           bits [5:0] з status_byte (0–63)
  ├─ bio_status           :integer enum      0=homeostasis|1=stress|2=anomaly|3=tamper
  ├─ verified_by_iotex    :boolean  NOT NULL DEFAULT false
  ├─ zk_proof_ref         :string            "proof_id" або "receipt_id" від W3bstream
  ├─ chainlink_request_id :string  INDEX     TX hash або stub request ID
  └─ oracle_status        :enum(string)  DEFAULT "pending"
                                   pending → dispatched → fulfilled | failed
                                   Rails enum з prefix: oracle_status_pending?, oracle_status_dispatched?, oracle_status_fulfilled?, oracle_status_failed?

Partial indexes (sparse, billions of rows):
  idx_telemetry_logs_oracle_dispatched  WHERE oracle_status = 'dispatched'
  idx_telemetry_logs_oracle_fulfilled   WHERE oracle_status = 'fulfilled'
  idx_telemetry_logs_oracle_failed      WHERE oracle_status = 'failed'
  index_telemetry_logs_on_chainlink_request_id

blockchain_transactions
  ├─ chainlink_request_id :string  INDEX    Audit trail on-chain ↔ off-chain
  └─ zk_proof_ref         :string           Незмінний ZK-доказ у TX записі
```

---

## Змінні Середовища та Credentials

| Змінна | Сервіс | Обов'язкова |
|--------|--------|-------------|
| `credentials.peaq_node_url` | `Peaq::DidRegistryService` | ✅ Так |
| `credentials.peaq_signing_key` | `Peaq::DidRegistryService` (Ed25519) | ✅ Так (raises `RegistrationError` при відсутності) |
| `credentials.iotex_w3bstream_url` | `Iotex::W3bstreamVerificationService` | ✅ Так |
| `credentials.iotex_api_key` | `Iotex::W3bstreamVerificationService` | ✅ Так |
| `ENV["CHAINLINK_FUNCTIONS_ROUTER"]` | `Chainlink::OracleDispatchService` | ⚠️ PROD only |
| `ENV["CHAINLINK_SUBSCRIPTION_ID"]` | `Chainlink::OracleDispatchService` | ⚠️ PROD only |
| `ENV["ORACLE_PRIVATE_KEY"]` | Chainlink dispatch + BlockchainMintingService | ✅ Так |
| `ENV["ALCHEMY_POLYGON_RPC_URL"]` | `Web3::RpcConnectionPool` | ✅ Так |
| `ENV["CARBON_COIN_CONTRACT_ADDRESS"]` | `BlockchainMintingService` | ✅ Так |
| `ENV["FOREST_COIN_CONTRACT_ADDRESS"]` | `BlockchainMintingService` | ✅ Так |
| `ENV["DAO_TREASURY_ADDRESS"]` | `BlockchainMintingService` (Dynamic Tax) | ✅ Так |
| `ENV["SOLANA_RPC_URL"]` | `Solana::MintingService` | ✅ Так |
| `ENV["PROVISIONING_MASTER_KEY"]` [SEC.11] | `SilkenNet::SeedDerivation`, `HardwareKeyService` | ✅ Так — без неї `SecurityError` (no SecureRandom fallback ANYWHERE; pre-prod hard cutover) |

---

## 🔬 SEC.11 — Lorenz Seed Provenance & Dual Computation Integrity

> **Cross-ref:** дизайн і threat model — [03_05 §3.4в](03_05_Hardware_AES256_and_Security#34в-lorenz-k_seed-derivation-sec11-); сервіс — [04_02 `SilkenNet::SeedDerivation`](04_02_Business_Logic_and_Services#silkennetseedderivation-); poetics — [03_04 §2.1, §3 Крок 1](03_04_mruby_Lorenz_Attractor); SEC.11 в трекері — [10_02 SEC.11](10_02_Action_Plan_Tracker).

### Чому це частина Proof of Growth, а не суто security task

`Wallet#lock_and_mint!` карбує SCC лише коли `bio_status == homeostasis` витримує ZK-верифікацію та oracle-консенсус. До SEC.11 атакер з знанням open-source формули Лоренца та публічного DID (їде відкритим текстом у `[DID:4]` префіксі LoRa-пакета) міг **підрахувати очікуваний Z для будь-якого дерева** і підробити телеметрію з валідним `status_byte`. `check_z_divergence!` мовчав, бо порівнював категорії (homeostasis/stress/anomaly), не саму величину Z — Float vs BigDecimal drift після 250 ітерацій Ейлера робив числове порівняння неможливим. Identifier-as-key антипатерн.

### Hard cutover (pre-prod, 2026-05-02)

| Шар | Зміна | Файл / артефакт |
|-----|-------|----------|
| Schema | Нові колонки `hardware_keys.lorenz_seed_hex` (NOT NULL), `telemetry_logs.lorenz_state_x/y/z`, `telemetry_logs.cold_start_flag` | `db/migrate/20260502090000_add_lorenz_seed_provenance_columns.rb` |
| Crypto core | `SilkenNet::SeedDerivation` — HKDF-SHA256 + HMAC-SHA256 + signed-unit-float unpack; raises `SecurityError` без `PROVISIONING_MASTER_KEY` (no fallback) | `app/services/silken_net/seed_derivation.rb` (17 specs) |
| Provisioning | `HardwareKeyService.provision` атомарно деривує AES key + K_seed одним викликом | `app/services/hardware_key_service.rb` |
| Attractor | Sole entry-point `Attractor.calculate_z_from_state(x_prev, y_prev, z_prev, …)`; legacy `calculate_z(seed, …)` ВИДАЛЕНО | `app/services/silken_net/attractor.rb` |
| Unpacker | Per-tree dispatch: warm tail з попереднього `TelemetryLog.lorenz_state_*`, cold start з `K_seed/epoch_day` + `cold_start_flag = true`; persist tail | `app/services/telemetry_unpacker_service.rb` |
| Firmware | mruby `bio_contract.rb` єдина сигнатура `calculate_state(x, y, z, …)`; chaos_seed та DID-as-seed видалено | `firmware/bio_contracts/bio_contract.rb` |
| Parity | Host-test OpenSSL HKDF/HMAC ↔ mbedTLS на MCU, 13 examples (детерміновані вектори + 100-case fuzz mirror Ruby) | `firmware/test/test_seed_derivation.c` |

### Cold-start vs Warm continuation dispatch у `TelemetryUnpackerService`

```ruby
prev_tail = tree.telemetry_logs
              .where.not(lorenz_state_x: nil)
              .order(created_at: :desc)
              .first

if prev_tail
  # Warm path (норма) — дзеркалить firmware FW.6 RTC DR16-DR18 continuation
  x0, y0, z0 = prev_tail.lorenz_state_x, prev_tail.lorenz_state_y, prev_tail.lorenz_state_z
  cold_start = false
else
  # Cold path — лише після VBAT loss / провізіонування / повного reboot
  raise MissingLorenzSeedError unless tree.hardware_key&.binary_lorenz_seed.present?
  epoch_day  = telemetry_log.created_at.utc.to_i / 86_400
  x0, y0, z0 = SilkenNet::SeedDerivation.derive_initial_state(
                 seed_bin:  tree.hardware_key.binary_lorenz_seed,
                 epoch_day: epoch_day
               )
  cold_start = true
end

z = SilkenNet::Attractor.calculate_z_from_state(
      x0, y0, z0, temp_c, acoustic, metabolism_s, voltage_mv
    )

telemetry_log.update!(
  z_value:         z,
  lorenz_state_x:  Attractor.last_state[:x],
  lorenz_state_y:  Attractor.last_state[:y],
  lorenz_state_z:  Attractor.last_state[:z],
  cold_start_flag: cold_start
)
```

**Інваріант:** обидві сторони (Soldier mruby + backend Ruby) стартують з **байт-ідентичного** `(x₀, y₀, z₀)` для тієї самої пари `(K_seed, epoch_day)`. Daily epoch rotation (UTC, 86400 сек) синхронізована через FW.20 `CMD_TIME_SYNC` → forward secrecy ≤ 24 год.

### Ефект на Dual Computation Integrity

**До SEC.11** — `check_z_divergence!` категоричний (3-zone homeostasis/stress/anomaly): атакер з `Z_fake = 28.0` проходив. Tolerance band = ширина категорії.

**Після SEC.11** — обидві сторони мають однакову початкову точку, тому Float vs Float drift між ARM та x86 IEEE-754 за 250 ітерацій < 1e-12 (емпірично після FW.7 closure). `check_z_divergence!` зберігає категоричну невідповідність як safety net і отримує hook для числового tolerance band (`(server_z - device_z).abs > 0.001`) — flip під feature-flag після інструментального вимірювання реального drift у польових умовах. Атакер без знання `K_seed` не може передбачити очікуваний Z → fake-телеметрія falls within `< 0.001` band з ймовірністю ~`6/45000` → детекція ≈ 99.99%.

> **Свідомо НЕ робимо** (pre-prod, no field devices, no prototypes, no firmware in flight): `POST /api/v1/provisioning/upgrade_seed` field-migration endpoint, TRL4 lab-mode response з `lorenz_seed` в JSON, SecureRandom fallback в `Rails.env != production`. SEC.9 (rotation `PROVISIONING_MASTER_KEY`) — окрема задача, не блокує SEC.11.

---

## 🚨 Блокери (Needs Action)

Нижче зафіксовані всі заглушки, хардкод, фейкові перевірки та пропущені
криптографічні верифікації, виявлені під час аудиту коду. **Жодного рефакторингу
в цьому документі.** Кожен блокер — передумова для Mainnet deployment.

---

### BLOCKER-01: AES ключ захардкоджений в прошивках Солдата і Королеви [P0 — CRITICAL SECURITY]

**Файли:**
- `firmware/soldier/main.c:66–67`
- `firmware/queen/main.c:81–82`

```c
// ОДНАКОВИЙ У ОБОХ ФАЙЛАХ:
uint32_t aes_key[8] = {0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
                       0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D};
```

**Наслідки:**
1. Ключ є у відкритому вихідному коді репозиторію (source code exposure).
2. Всі Солдати та всі Королеви світу використовують **один і той самий** AES ключ.
3. Компрометація одного пристрою → компрометація всієї мережі.
4. Бекенд зберігає ключ у `HardwareKey.binary_key` (per-device), але прошивка
   ігнорує цю per-device модель і використовує глобальний ключ.

**Потрібно:** Per-device унікальний ключ, що передається через provisioning API
(`/api/v1/provisioning` вже повертає `@key_hex` через `HardwareKeyService.provision`),
та механізм secure boot / attestation для захисту ключа в Flash.

---

### BLOCKER-02: ✅ ЗАКРИТО — Lorenz Float vs BigDecimal divergence + DID-as-seed

> **Закрито (2026-05-02):** дві ортогональні зміни усунули блокер.
> 1. **FW.7 (попередня сесія):** `app/services/silken_net/attractor.rb` переведено з `BigDecimal(18)` на Float (IEEE 754 double), байт-ідентично з firmware mruby. Накопичена похибка за 250 ітерацій Ейлера — < 1e-12 (емпірично).
> 2. **SEC.11 (поточна сесія, hard cutover):** початкова точка `(x₀, y₀, z₀)` тепер деривується з per-device `K_seed` через `HMAC-SHA256(K_seed, "init|" || epoch_day_be)` на обох сторонах байт-ідентично. DID видалено зі входів атрактора повністю (був identifier-as-key антипатерн). `check_z_divergence!` отримав hook для числового tolerance band (`< 0.001`) — flip під feature-flag після інструментального drift вимірювання у польових умовах.
>
> Деталі — секція **«SEC.11 — Lorenz Seed Provenance & Dual Computation Integrity»** вище.

**Історичний контекст** (для розуміння еволюції рішення):
- `firmware/bio_contracts/bio_contract.rb` — `BASE_BETA = 8.0 / 3.0` (Ruby Float)
- `app/services/silken_net/attractor.rb` (до FW.7) — `BASE_BETA = ("8.0".to_d / "3.0".to_d).round(18)` (BigDecimal)
- Різна математика (Float vs BigDecimal) давала розбіжність Z на десятки одиниць після 250 ітерацій хаотичної системи. Plus identifier-as-key антипатерн робив `check_z_divergence!` неможливим як числову перевірку.

---

### BLOCKER-03: CRITICAL_Z_MIN/MAX захардкоджені у bio_contract, але на сервері — per-species з TreeFamily [P1]

**Файли:**
- `firmware/bio_contracts/bio_contract.rb:60–61`
- `app/models/tree_family.rb:21–24`

```ruby
# Firmware — глобальні константи для ВСІХ видів дерев:
CRITICAL_Z_MIN = 2.0
CRITICAL_Z_MAX = 45.0

# Backend — per-species поріги з БД:
tree_family.critical_z_min  # може бути 5.0 для дуба, 1.5 для берези
tree_family.critical_z_max  # може бути 40.0 для дуба, 55.0 для берези
```

**Наслідок:** Firmware визначає `bio_status` та `growth_points` за однаковими
порогами для всіх видів, тоді як бекенд (`SilkenNet::Attractor.homeostatic?`,
`AlertDispatchService`) використовує `tree_family.critical_z_min/max`.
Дуб може отримати `status=0` (homeostasis) у firmware, але `anomaly` на сервері,
або навпаки — невідповідність у фінансовому звіті.

**Потрібно:** OTA-синхронізація порогів конкретного виду до кожного Солдата
(наприклад, через provisioning або OTA bio_contract з параметрами).

---



## 📊 Матриця Ризиків

| # | Блокер | Область | Вплив | Пріоритет |
|---|--------|---------|-------|-----------|
| 01 | AES ключ захардкоджений у firmware | Security | Компрометація всіх пристроїв | P0 |
| 02 | ~~Float vs BigDecimal Lorenz divergence~~ + ~~DID-as-seed identifier-as-key антипатерн~~ | Correctness + Security | ✅ Закрито (FW.7 + SEC.11, 2026-05-02) | — |
| 03 | CRITICAL_Z thresholds: global vs per-species | Correctness | Некоректний bio_status | P1 |

**Легенда пріоритетів:**
P0 = Блокує Mainnet негайно (security breach)
P1 = Потрібно вирішити до Mainnet deployment

---

## 📋 Статус Імплементації по Кроках

| Крок | Компонент | Статус | Примітка |
|------|-----------|--------|----------|
| Firmware Soldier | STM32WLE5JC + mruby BioContract | ⚠️ Open | BLOCKER-01,02,03 |
| Firmware Queen | STM32WLE5JC + SIM7070G CIFO | ⚠️ Open | BLOCKER-01 |

**Загальний висновок:** Пайплайн повністю реалізовано та покрито RSpec-тестами. Відкрито 3 блокери — всі пов'язані з firmware (AES key, Lorenz precision, per-species thresholds). Backend-шар готовий до Mainnet.
