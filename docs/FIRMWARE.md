# Embedded Firmware

## Platform

**MCU:** STM32WLE5JC (Seeed Studio LoRa-E5 mini)
- ARM Cortex-M4 @ 48 MHz + integrated LoRa transceiver (SX1262)
- 256 KB Flash, 64 KB SRAM
- Deep sleep (STOP2): 2.1 uA
- TX power: up to +22 dBm
- Frequency: 868 MHz (EU)

---

## Soldier Node (`firmware/soldier/main.c`)

### Lifecycle

A Soldier (tree sensor node) operates in a single main loop, spending most of its time in STOP2 deep sleep (2.1 µA). Each wakeup cycle:

```
STOP2 Sleep → Wakeup (RTC/vibration) → Phase 0-5 → STOP2 Sleep
```

### Phase 0: Watchdog (IWDG)

```c
HAL_IWDG_Refresh(&hiwdg);
```

Hardware watchdog auto-resets MCU if the main loop hangs (mruby OOM, HardFault). All critical data survives in RTC Backup Domain.

### Phase 1: Sensor Acquisition

- **Metabolism:** `delta_t_seconds` — time between wakeups. Faster supercapacitor charge = healthier sap flow.
- **Temperature:** Internal STM32 sensor via ADC (`__LL_ADC_CALC_TEMPERATURE`).
- **Vcap voltage:** Supercapacitor voltage via ADC (VREFINT channel).
- **Chaos seed:** True random number from HRNG (thermal noise) for Lorenz attractor.

Two separate ADC Start/Poll/Stop cycles prevent deadlock when switching channels.

### Phase 1.5: TinyML Audio Classification

Activated ONLY when `vibration_detected == 1` (piezoelectric EXTI interrupt):

1. Start TIM2 + ADC in DMA mode → CPU enters SLEEP
2. DMA fills `raw_audio_buffer[512]` without CPU involvement
3. `HAL_ADC_ConvCpltCallback` → CPU wakes up
4. Normalize: `raw_audio_buffer[i] / 4095.0f` → `audio_buffer[i]`
5. TinyML inference → `ml_event_id` + `ml_confidence`

| Event ID | Event | Action |
|----------|-------|--------|
| 0 | Silence | None |
| 1 | Wind | None |
| 2 | Cavitation | `acoustic_events++` |
| 3 | Chainsaw/Tamper | `Trigger_Emergency_LoRa_TX()` — immediate panic alert! |

Confidence threshold: `ml_confidence > 0.80` (80%).

### Phase 2: Bit-Pack

Fills 16-byte `lora_payload` (see Binary Packet Format below). Clears `acoustic_events` counter after packing.

### Phase 3: mruby Lorenz Attractor Bio-Contract

```c
mrb_funcall_argv(mrb, mrb_top_self(mrb), mrb_intern_lit(mrb, "calculate_state"), 3, args);
```

mruby VM is opened ONCE at init (`mrb_open()`) — not per-cycle — to prevent OOM and heap fragmentation.

**Inputs:** chaos_seed (HRNG), temperature (ADC), acoustic_events (TinyML).
**Output → `lora_payload[10]`:** `[Status:2 bits | GrowthPoints:6 bits]`
**Fallback:** If VM failed at init → `lora_payload[10] = 0xFF`.

### Phase 4: LoRa TX (Encryption + Mesh)

1. **Anti-Collision Jitter:** Random 0-500 ms delay (HRNG) before TX. Prevents collisions when 100+ trees wake simultaneously (thunder, earthquake).
2. **Mesh Relay:** If `has_mesh_relay == 1`, the relayed encrypted packet is sent FIRST.
3. **AES-256-ECB** encryption (hardware crypto module).
4. **`Radio.Send(encrypted_payload, 16)`**

### Phase 4.5: RX Window (OTA + Mesh)

Opens ONLY if `vcap_voltage > 2800` mV (enough energy).
Listens for up to 600 ms (`Radio.Rx(500)`).

**Scenario A — OTA packet (marker `0x99`):**
- Chunks collected into `ota_buffer[1024]` with duplicate protection via `ota_chunk_received[]`
- When all chunks received → `Write_OTA_Contract_To_Flash` → `NVIC_SystemReset()`

**Scenario B — Mesh relay (16 bytes, TTL > 0):**
- Check: own echo (`incoming_did == tree_did`) → ignore
- Check: anti-pingpong cache (`recent_mesh_dids[]`) → skip known DIDs
- Decrement TTL → re-encrypt → store in `mesh_relay_payload` for next Phase 4

### Phase 5: Deep Sleep (STOP2)

1. Save all critical data to RTC Backup registers (see table below)
2. `HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI)` — 2.1 µA
3. Wake on RTC alarm or GPIO EXTI (piezo disk)

### Soldier HAL Peripherals

| Handle | Peripheral | Purpose |
|--------|------------|---------|
| `hadc` | ADC | Temperature + supercapacitor voltage |
| `htim2` | TIM2 | DMA clock for TinyML audio sampling (16 kHz) |
| `hiwdg` | IWDG | Hardware watchdog (auto-reset on hang) |
| `hrng` | RNG | True random numbers (thermal noise entropy) |
| `hrtc` | RTC | Real-time clock + Backup Domain persistence |
| `hsubghz` | SUBGHZ | Integrated LoRa transceiver SX1262 |
| `hcryp` | AES | Hardware AES-256-ECB |

### Soldier RAM Budget (~5 KB of 64 KB SRAM)

| Variable | Type | Size | Purpose |
|----------|------|------|---------|
| `aes_key[8]` | `uint32_t` | 32 B | AES-256 network key |
| `lora_payload[16]` | `uint8_t` | 16 B | Outgoing payload before encryption |
| `encrypted_payload[16]` | `uint8_t` | 16 B | Encrypted payload for Radio.Send |
| `mesh_relay_payload[16]` | `uint8_t` | 16 B | Relayed encrypted mesh packet |
| `recent_mesh_dids[3]` | `uint32_t` | 12 B | Last 3 seen DIDs (anti-pingpong) |
| `raw_audio_buffer[512]` | `uint16_t` | 1024 B | Raw 12-bit DMA samples (TinyML) |
| `audio_buffer[512]` | `float` | 2048 B | Normalized float samples for inference |
| `incoming_lora_payload[256]` | `uint8_t` | 256 B | Incoming LoRa packet buffer |
| `decrypted_rx_payload[256]` | `uint8_t` | 256 B | Decrypted incoming data |
| `ota_buffer[1024]` | `uint8_t` | 1024 B | OTA bytecode assembly buffer |
| `ota_chunk_received[256]` | `uint8_t` | 256 B | OTA chunk dedup bitmap |

### Soldier RTC Backup Register Map

| Register | Variable | Description |
|----------|----------|-------------|
| `DR0` | `acoustic_events` | Acoustic event counter |
| `DR1` | `last_wakeup_timestamp` | Last wakeup time (for delta_t) |
| `DR2` | `has_mesh_relay` | Flag: pending mesh relay packet |
| `DR3..DR6` | `mesh_relay_payload[0..15]` | Relay packet (4×32 bit = 16 bytes) |
| `DR7` | `tree_did` | DID — written ONCE in device lifetime |
| `DR8..DR10` | `recent_mesh_dids[0..2]` | Anti-pingpong DID cache |

### Soldier ISR (Interrupt Service Routines)

| Callback | Trigger | Action |
|----------|---------|--------|
| `OnRxDone` | LoRa RX complete | Copy packet, set `lora_rx_flag = 1` |
| `HAL_GPIO_EXTI_Callback` | GPIO_PIN_0 (piezo) | Set `vibration_detected = 1` |
| `HAL_PWR_PVDCallback` | Voltage < 2.2V | Emergency save → Radio.Sleep → STOP2 |
| `HAL_ADC_ConvCpltCallback` | DMA buffer full | Set `audio_ready = 1` |

**PVD (Programmable Voltage Detector):** When supercapacitor drops below 2.2V, the system immediately saves data to RTC and enters deep sleep — no TX attempt (insufficient energy).

---

## Queen Node (`firmware/queen/main.c`)

### Lifecycle

A Queen (gateway node) operates continuously — it NEVER sleeps:

```
Init → LoRa RX (infinite) → [packet received] → Decrypt → Cache →
→ [trigger: cache full OR 1 hour] → Encrypt batch (CBC) →
→ CoAP PUT via SIM7070G → Clear cache → Continue RX
```

Powered by solar panel + battery (not supercapacitor).

### LoRa Reception & Caching

Queen listens on `Radio.Rx(0xFFFFFF)` (infinite timeout). When `OnRxDone` ISR fires:

1. **AES-256-ECB Decrypt** (hardware, 16 bytes)
2. **OTA Reflex Shot** (if active) — immediately send next OTA chunk
3. **Extract DID** (first 4 bytes of decrypted payload)
4. **CIFO Cache** — `Process_And_Cache_Data(sender_id, decrypted_payload, current_rssi)`
5. **Resume RX** — `lora_rx_flag = 0; Radio.Rx(0xFFFFFF);`

### OTA Broadcast (Reflex Shot)

Immediately after receiving a Soldier packet, Queen fires an OTA chunk in response. This works because Soldiers listen for 500 ms after their own TX.

OTA chunk format (16 bytes):
```
[0]     0x99            — OTA marker
[1-2]   chunk_index     — Chunk number (big-endian uint16)
[3-4]   total_chunks    — Total count (big-endian uint16)
[5-15]  data            — Up to 11 bytes of mruby bytecode
```

`current_ota_chunk_idx` increments per TX, wraps to 0 after last chunk. Each Soldier gets the next sequential chunk.

### Edge Cache (CIFO Algorithm)

```c
typedef struct {
    uint32_t uid;           // Tree DID
    uint8_t payload[16];    // Last decrypted data
    int8_t rssi;            // Signal quality
    uint8_t is_active;      // 1 = slot occupied
} EdgeCache;

EdgeCache forest_cache[50]; // 50 slots
```

**Algorithm (`Process_And_Cache_Data`):**
1. **Dedup:** Find UID in cache → update payload + RSSI
2. **Insert:** Find free slot (`is_active == 0`) → insert
3. **CIFO Eviction:** Cache full → find slot with worst RSSI → overwrite

### Cache Flush to Server

**Triggers:**
- `cache_count >= 45` (cache nearly full: 50 - 5 = 45)
- `HAL_GetTick() - last_flush_time > 3,600,000` (1 hour elapsed)

**Sequence:**
1. Pack cache into `binary_batch_buffer` (21 bytes per entry)
2. AES-256-CBC encrypt (IV from `HAL_GetTick()`)
3. Open CoAP session (`AT+CCOAPNEW`)
4. Transmit hex string (`AT+CCOAPSEND`) with URI `/telemetry/batch/<queen_uid>`
5. Wait for ACK (`HAL_Delay(2000)`)
6. Close session (`AT+CCOAPDEL`)

### Actuator Command Dedup (Idempotency)

When Rails retries a command (ACK lost), Queen must execute it only ONCE.

**Mechanism:**
- DJB2 hash of UUID token (32-bit, zero allocations): `h = h * 33 + c`
- Ring buffer `cmd_dedup_ring[16]` stores last 16 hashes
- `Cmd_Dedup_Check(hash)` → 0 = new, 1 = duplicate

**RAM budget:** 64 bytes (hashes) + 2 bytes (indices) = 66 bytes.

### Queen HAL Peripherals

| Handle | Peripheral | Purpose |
|--------|------------|---------|
| `huart1` | USART1 | SIM7070G modem (115200 baud) |
| `hsubghz` | SUBGHZ | LoRa transceiver SX1262 (868 MHz) |
| `hcryp` | AES | ECB for LoRa, CBC for CoAP batches |

**Note:** Queen has NO ADC, TIM, RNG, RTC, IWDG — unlike Soldier.

### Queen RAM Budget (~3.7 KB of 64 KB SRAM)

| Variable | Type | Size | Purpose |
|----------|------|------|---------|
| `aes_key[8]` | `uint32_t` | 32 B | AES-256 key (identical to Soldiers) |
| `forest_cache[50]` | `EdgeCache` | 1150 B | CIFO cache |
| `binary_batch_buffer[2048]` | `uint8_t` | 2048 B | CoAP batch buffer |
| `at_tx_buffer[256]` | `char` | 256 B | AT command buffer |
| `cmd_dedup_ring[16]` | `uint32_t` | 64 B | Idempotency hash ring |
| `cmd_decrypt_buf[96]` | `uint8_t` | 96 B | CoAP command decrypt buffer |

### Queen ISR

| Callback | Trigger | Action |
|----------|---------|--------|
| `OnRxDone` | LoRa RX (exactly 16 bytes) | Copy packet, save RSSI, set `lora_rx_flag = 1` |

---

## Binary Packet Format

### Outer Frame (21 bytes) — Queen wraps each Soldier packet

```
[DID:4][RSSI:1][Payload:16]
```

| Field | Size | Description |
|-------|------|-------------|
| DID | 4 bytes | Tree device identifier (big-endian) |
| RSSI | 1 byte | Signal strength (inverted: -85 dBm → 85) |
| Payload | 16 bytes | Decrypted sensor data |

### Inner Payload (16 bytes, after AES decryption)

```
[DID:4][Vcap:2][Temp:1][Acoustic:1][Time:2][BioContract:1][TTL:1][Pad:4]
```

| Byte(s) | Field | Type | Description |
|---------|-------|------|-------------|
| 0-3 | DID | uint32 | Decentralized Identity (big-endian) |
| 4-5 | Vcap | uint16 | Supercapacitor voltage (mV, big-endian) |
| 6 | Temp | int8 | Crystal temperature (°C, signed) |
| 7 | Acoustic | uint8 | TinyML-filtered acoustic event count |
| 8-9 | Metabolism | uint16 | Time between wakeups (seconds, big-endian) |
| 10 | BioContract | uint8 | `[Status:2 bits \| GrowthPoints:6 bits]` from mruby |
| 11 | TTL | uint8 | Time-To-Live for mesh (initial = 3) |
| 12-13 | FirmwareVersionID | uint16 | Firmware version (big-endian, 0 = not set) |
| 14-15 | Reserved | 2 bytes | Available for future use |

**Byte 10 (BioContract)** — Lorenz Attractor result:
- Bits `[7:6]` — Status: `0`=homeostasis, `1`=stress, `2`=anomaly, `3`=tamper
- Bits `[5:0]` — Growth Points: `0-63` (Proof of Growth)

**Bytes 12-13 (FirmwareVersionID):** Allows the backend `TelemetryUnpackerService` to compare the tree's firmware version against the latest active `BioContractFirmware`. On mismatch → tree is marked `fw_pending` for OTA re-delivery.

### Queen Sentinel Packet (DID = 0x00000000)

When the Queen injects its own health telemetry into the batch, it uses DID = `0x00000000` as a sentinel. The backend detects this and routes to `GatewayTelemetryWorker` instead of creating a `TelemetryLog`.

| Byte(s) | Field | Mapping |
|---------|-------|---------|
| 4-5 | Vcap | Queen battery voltage (mV) |
| 6 | Temp | Queen housing temperature (°C) |
| 7 | Acoustic → CSQ | Cellular signal quality (0-31, or 99 = unknown) |

## Mesh Networking

- **TTL-based routing:** Maximum 3 hops between Soldier and Queen
- **Anti-pingpong:** DID seen-cache prevents packet loops
- **RTC persistence:** Mesh routing state stored in RTC backup registers (survives deep sleep)
- **Echo protection:** Soldier ignores packets with its own DID

## OTA Updates

### Queen → Soldier (LoRa OTA)

- **Chunk format:** `[0x99][chunk_idx:2][total:2][data:11]` = 16 bytes
- **Delivery:** Reflex shot — Queen sends OTA chunk immediately after receiving Soldier data
- **Timing:** Soldier listens for 500 ms after its own TX
- **Chunk rotation:** `current_ota_chunk_idx` wraps to 0 after last chunk
- **Dedup:** `ota_chunk_received[]` bitmap prevents duplicate writes

### Rails → Queen (CoAP OTA)

- **Chunk size:** 512 bytes per firmware frame
- **Pacing:** 0.4s delay between chunks (STM32 HAL_FLASH_Program write time)
- **Retry:** Up to 5 retries per chunk with exponential backoff
- **Worker:** `OtaTransmissionWorker` (Sidekiq `downlink` queue)

## mruby Bio-Contract

File: `firmware/bio_contracts/bio_contract.rb`

The bio-contract runs on the mruby VM embedded in the Soldier's firmware. VM is opened ONCE at init (`mrb_open()`) — not per-cycle — to prevent OOM and heap fragmentation.

```ruby
# Lorenz attractor constants
SIGMA = 10.0
RHO   = 28.0
BETA  = 8.0 / 3.0
DT    = 0.01

# Sensor perturbation
local_sigma = SIGMA + (acoustic * 0.1)
local_rho   = RHO + (temp * 0.2)

# 250 iterations of Euler integration
# Returns packed byte: (status << 6) | growth_points
```

**OTA contract selection:** At boot, Soldier checks `MRUBY_CONTRACT_FLASH_ADDR` (0x0803F000) for `"RITE"` magic bytes (mruby bytecode signature). If present → use OTA contract; otherwise → use built-in `lorenz_bytecode[]`.

The server-side `SilkenNet::Attractor` service independently computes the same Z-value for dual computation integrity verification.

## DID Generation

1. Read STM32 factory UID (96-bit unique identifier at 0x1FFF7590)
2. XOR with TRNG (True Random Number Generator) output
3. Guarantee non-zero: if result == 0, use fallback `0x511CEE01`
4. Lock in RTC backup register DR7 (persists across resets, written ONCE)
5. Register with backend via `POST /api/v1/provisioning/register`

## Encryption

| Path | Algorithm | Mode | IV |
|------|-----------|------|----|
| Soldier ↔ Queen (LoRa) | AES-256 | ECB | N/A (single 16-byte block) |
| Queen → Rails (CoAP batch) | AES-256 | CBC | `HAL_GetTick()`-based (prepended to ciphertext) |
| Rails → Queen (CoAP commands) | AES-256 | ECB | N/A |

## Known Risks & Mitigations

| Risk | Severity | Description | Status |
|------|----------|-------------|--------|
| **LoRa Collision Storm** | 🔴 Critical | 100+ trees wake simultaneously → TX collisions | ✅ Fixed: random jitter 0-500ms before TX |
| **OTA Integrity Gap** | 🟠 High | No CRC/SHA-256 check before flash write — corrupted byte → infinite reboot | ⚠️ Open |
| **CIFO Blind Spot** | 🟡 Medium | Worst-RSSI tree evicted from cache — but it may carry critical fire perimeter data | ⚠️ Open |
| **AT Command Blocking** | 🟠 High | `HAL_Delay(2000)` after CoAP — Queen blind for 2s, LoRa FIFO overflow risk | ⚠️ Open (needs UART interrupt driver rewrite) |
| **mruby Heap Fragmentation** | 🟡 Medium | `mrb_open()` once, but objects inside loop may fragment heap over weeks | ⚠️ Open |
| **Mesh Ping-Pong** | 🟡 Medium | 3-slot `recent_mesh_dids` cache may be insufficient for dense forests | ⚠️ Open |
| **Starlink Latency** | 🟡 Medium | `HAL_Delay(1000)` for CoAP session may be too short for Starlink | ⚠️ Open |
| **Queen Health Blind Spot** | 🟠 High | Queen doesn't send own battery/temperature/CSQ to server | ⚠️ Open (backend ready for DID=0 sentinel) |
