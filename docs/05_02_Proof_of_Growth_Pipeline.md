# 05_02: Пайплайн «Proof of Growth»

## 🎯 Мета

Зафіксувати повний trustless консенсусний пайплайн SilkenNet — від фізичних біосигналів дерева (Lorenz Z-координата гомеостазу) до верифікованих on-chain активів (SilkenCarbonCoin / SCC). Включає опис прошивок Солдата й Королеви, всіх кроків верифікації (peaq DID → IoTeX ZK → Chainlink → Polygon + Solana) та відкритих блокерів.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Пайплайн повністю імплементовано, BLOCKER-04/05/06/07/08/09/10/11/12 закриті.
- **Синхронізація:** 2026-04-15
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
║     RNG → chaos_seed (32-bit entropy)                                ║
║     DMA 16kHz → raw_audio_buffer[512] → TinyML inference             ║
║     delta_t_seconds = tick - last_wakeup_timestamp (метаболізм EBFC) ║
║                                                                      ║
║   ФАЗА 2: mruby BioContract (on-device Lorenz)                      ║
║     bio_contract.rb :: Attractor.calculate_z_axis(seed, temp, acust) ║
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
║  [UnpackTelemetryWorker] queue: uplink (prio 9)                     ║
║    Base64 decode → AES-256-CBC decrypt via HardwareKey.binary_key   ║
║    "Soft Key Rotation": new_key → fallback previous_key             ║
║    Gateway.find_by(uid:) → mark_seen!(new_ip:)                      ║
║    ▼                                                                 ║
║  [TelemetryUnpackerService]                                          ║
║    Chunk: [DID:4][RSSI:1][Payload:16] = 21 bytes                    ║
║    Format: "N n c C n C C a4" (unpack)                              ║
║    DeviceCalibration: normalize ADC → фізичні одиниці               ║
║    SilkenNet::Attractor.calculate_z(seed, temp, acust) → z_value    ║
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
║  [IotexVerificationWorker] queue: web3_critical (prio 7), retry: 5  ║
║    Iotex::W3bstreamVerificationService#verify!                       ║
║    POST {iotex_w3bstream_url}/verify                                 ║
║    Body: { device_id, peaq_did, telemetry_log_id, hardware_sig,     ║
║            chaotic_data: { z_value, temp, acoustic, voltage, bio }}  ║
║    Response: { proof_id | receipt_id } → zk_proof_ref               ║
║    → log.update!(verified_by_iotex: true, zk_proof_ref:)            ║
║    → ChainlinkDispatchWorker.perform_async(id, created_at_iso)      ║
║                                                                      ║
║  ─────────── КРОК C: Chainlink Oracle Dispatch ───────────────────── ║
║  [ChainlinkDispatchWorker] queue: web3_critical (prio 7), retry: 5  ║
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

**Файл:** `firmware/soldier/main.c` (648 рядків)

#### Фаза 1 — SENSE (Збір фізичних даних)

| Сигнал | Джерело | Формат |
|--------|---------|--------|
| `vcap_voltage` | ADC → VREFINT канал | uint16 (мВ, 0–5000) |
| `internal_temp` | ADC → внутрішній датчик | int8 (°C, −45..90) |
| `acoustic_events` | DMA 16 кГц → TinyML CMSIS-NN | uint8 (0–255) |
| `delta_t_seconds` | `HAL_GetTick() - last_wakeup_timestamp` | uint32 (EBFC метаболізм) |
| `chaos_seed` | `HAL_RNG_GenerateRandomNumber` | uint32 (апаратна ентропія) |

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

def self.calculate_z_axis(seed, temp, acoustic)
  x = ((seed % 1000) / 500.0) - 1.0
  y = (((seed >> 4) % 1000) / 500.0) - 1.0
  z = (((seed >> 8) % 1000) / 500.0) - 1.0
  # local_sigma, local_rho: perturbation + clamp
  ITERATIONS.times { dx/dy/dz → Euler integration (Float) }
  z  # Ruby Float, НЕ BigDecimal
end
```

**Модуль `SilkenNet::BioContract` (firmware) — токеноміка:**
```ruby
CRITICAL_Z_MIN  = 2.0   # Порóг посухи (HARDCODED у firmware!)
CRITICAL_Z_MAX  = 45.0  # Поріг критичного стресу (HARDCODED!)
OPTIMAL_Z_TARGET = 29.0 # Ідеальний стан конвекції (HARDCODED!)

def self.evaluate_and_pack(seed, temp, acoustic)
  z_val = Attractor.calculate_z_axis(seed, temp, acoustic)
  if    z_val < CRITICAL_Z_MIN  → status=1, growth_points=1  # stress
  elsif z_val > CRITICAL_Z_MAX  → status=2, growth_points=0  # anomaly
  else                          → status=0                    # homeostasis
    deviation = (OPTIMAL_Z_TARGET - z_val).abs
    growth_points = clamp(50 - deviation.to_i, 10, 63)
  end
  payload_byte = (status << 6) | growth_points  # [ 2 bits | 6 bits ]
end
```

**Точка входу з C:** `calculate_state(seed, temp, acoustic)` → `payload_byte` (uint8_t).

#### Фаза 3 — PACK + ENCRYPT

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
- **Anti-pingpong:** seen-set `recent_mesh_dids[8]` у RTC Backup Registers
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
URI-Path: third segment = queen_uid ("QUEEN-001") → Gateway lookup
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
- `app/workers/peaq_registration_worker.rb` — queue: `web3` (prio 3), retry: 5
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
- `app/workers/iotex_verification_worker.rb` — queue: `web3_critical` (prio 7), retry: 5
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
- `app/workers/chainlink_dispatch_worker.rb` — queue: `web3_critical` (prio 7), retry: 5
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
- `app/workers/mint_carbon_coin_worker.rb` — queue: `web3_critical` (prio 7), retry: 5
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
- `app/workers/solana_micro_reward_worker.rb` — queue: `web3` (prio 3), retry: 3
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
| `credentials.peaq_signing_key` | `Peaq::DidRegistryService` (Ed25519) | ⚠️ Фактично ні |
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

---

## 🚨 Блокери (Needs Action)

Нижче зафіксовані всі заглушки, хардкод, фейкові перевірки та пропущені
криптографічні верифікації, виявлені під час аудиту коду. **Жодного рефакторингу
в цьому документі.** Кожен блокер — передумова для Mainnet deployment.

---

### BLOCKER-01: AES ключ захардкоджений в прошивках Солдата і Королеви [P0 — CRITICAL SECURITY]

**Файли:**
- `firmware/soldier/main.c:66–67`
- `firmware/queen/main.c:65–66`

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

### BLOCKER-02: Lorenz Attractor — Float у firmware vs BigDecimal(18) на сервері [P1]

**Файли:**
- `firmware/bio_contracts/bio_contract.rb` — `BASE_BETA = 8.0 / 3.0` (Ruby Float)
- `app/services/silken_net/attractor.rb` — `BASE_BETA = ("8.0".to_d / "3.0".to_d).round(18)` (BigDecimal)

```ruby
# Firmware (mruby):
BASE_BETA = 8.0 / 3.0   # → 2.6666666666666665 (IEEE 754 Float64)

# Backend (Rails):
BASE_BETA = ("8.0".to_d / "3.0".to_d).round(18)  # → 2.666666666666666667
```

**Наслідок:** Після 250 ітерацій Euler integration, накопичена похибка
Float vs BigDecimal призводить до різних значень Z на пристрої та сервері.
Це означає, що `growth_points` у пакеті (обчислені on-device) та `growth_points`
у `TelemetryLog` (зчитані з `status_byte`) можуть відрізнятись від `z_value`
(обчисленого сервером через `SilkenNet::Attractor.calculate_z`).

**Потрібно:** Або перейти на integer-math у firmware (помножити всі значення на
фіксований масштаб), або документувати, що on-device та backend Z — це
**різні** числа (один для локального рішення, інший для фінансового консенсусу).

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
| 02 | Float vs BigDecimal Lorenz divergence | Correctness | Різні Z на device vs server | P1 |
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
| A | peaq DID Provisioning | ✅ Real | Ed25519-підпис обов'язковий |
| B | IoTeX W3bstream ZK | ✅ Real | Ed25519 hw sig + proof ref regex |
| C | Chainlink Oracle Dispatch | ✅ Real | ABI v1, WEB3_STRICT_MODE |
| D | Oracle Callback | ✅ Real | HMAC-SHA256 (`X-Chainlink-Signature`) |
| E | EVM Minting Polygon | ✅ Real | Guard clauses, Dynamic Tax, Treasury |
| F | Solana Micro-Reward | ✅ Real | `sendTransaction` з Ed25519 підписом |

**Загальний висновок:** Пайплайн повністю реалізовано та покрито RSpec-тестами. Відкрито 3 блокери — всі пов'язані з firmware (AES key, Lorenz precision, per-species thresholds). Backend-шар готовий до Mainnet.

---

*Джерела: `firmware/soldier/main.c`, `firmware/queen/main.c`, `firmware/bio_contracts/bio_contract.rb`, `app/services/peaq/`, `app/services/iotex/`, `app/services/chainlink/`, `app/services/blockchain_minting_service.rb`, `app/controllers/api/v1/oracle_callbacks_controller.rb`*
