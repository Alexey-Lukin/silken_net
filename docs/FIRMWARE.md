# Embedded Firmware

## Platform

**MCU:** STM32WLE5JC (Seeed Studio LoRa-E5 mini)
- ARM Cortex-M4 @ 48 MHz + integrated LoRa transceiver (SX1262)
- 256 KB Flash, 64 KB SRAM
- Deep sleep (STOP2): 2.1 uA
- TX power: up to +22 dBm
- Frequency: 868 MHz (EU)

## Soldier Node Lifecycle

A Soldier (tree sensor node) operates in 5 phases:

### Phase 1: Sensor Acquisition
- Read supercapacitor voltage (ADC)
- Measure temperature (internal sensor)
- Sample acoustic events via piezoelectric disk
- Perform Electrical Impedance Spectroscopy (EIS) for xylem health

### Phase 2: TinyML Audio Classification
- Feed acoustic data into on-device neural network
- Classify: silence / wind / cavitation / chainsaw
- Output informs bio_status and alert generation

### Phase 3: mruby Lorenz Attractor Bio-Contract
- mruby VM executes `bio_contract.rb`
- Lorenz attractor equations with sensor perturbation:
  - Acoustic → sigma (coupling coefficient)
  - Temperature → rho (system energy)
  - Tree DID → initial conditions (unique chaotic fingerprint)
- Returns packed byte: `(status << 6) | growth_points`

### Phase 4: Bit-Pack & LoRa TX
- Pack 16-byte payload (see Binary Packet Format below)
- Encrypt with AES-256-ECB using device-specific key
- Transmit via LoRa (868 MHz)

### Phase 5: RX Window + Deep Sleep
- Brief RX window for OTA updates and mesh relay
- Enter STOP2 deep sleep (2.1 uA)
- Wake on RTC alarm or piezo EXTI interrupt

## Queen Node Lifecycle

A Queen (gateway node) operates continuously:

1. **LoRa RX** - Continuous reception from Soldiers
2. **AES Decrypt** - Decrypt using per-device key from provisioning
3. **CIFO Cache** - Closest In, Farthest Out buffer (max 50 trees)
4. **CoAP Batch PUT** - Send accumulated batch via LTE (SIM7070G) or Starlink
5. **OTA Broadcast** - During Soldier TX windows, relay firmware chunks

## Binary Packet Format

### Outer Frame (21 bytes)

```
[DID:4][RSSI:1][Payload:16]
```

| Field | Size | Description |
|-------|------|-------------|
| DID | 4 bytes | Tree device identifier |
| RSSI | 1 byte | Received signal strength (mesh relay quality) |
| Payload | 16 bytes | Encrypted sensor data |

### Inner Payload (16 bytes, after AES decryption)

```
[DID:4][Vcap:2][Temp:1][Acoustic:1][Time:2][Z:1][TTL:1][Pad:4]
```

| Field | Size | Description |
|-------|------|-------------|
| DID | 4 bytes | Device identifier (redundancy check) |
| Vcap | 2 bytes | Supercapacitor voltage (mV) |
| Temp | 1 byte | Temperature (C, offset +40) |
| Acoustic | 1 byte | Acoustic event count |
| Time | 2 bytes | Metabolism seconds |
| Z | 1 byte | Lorenz Z-value (scaled) |
| TTL | 1 byte | Mesh hop count (max 3) |
| Pad | 4 bytes | Reserved / alignment |

## Mesh Networking

- **TTL-based routing:** Maximum 3 hops between Soldier and Queen
- **Anti-pingpong:** 3-DID cache prevents packet loops
- **RTC persistence:** Mesh routing state stored in RTC backup registers (survives deep sleep)

## OTA Updates

- **Chunk size:** 512 bytes per firmware frame
- **Payload per encrypted frame:** 13 bytes (after AES overhead)
- **Resumable:** Tracks last-sent chunk index, continues after power loss
- **Pacing:** 0.4s delay between chunks (STM32 HAL_FLASH_Program write time)
- **Retry:** Up to 5 retries per chunk with exponential backoff

## mruby Bio-Contract

File: `firmware/bio_contracts/bio_contract.rb`

The bio-contract runs on the mruby VM embedded in the Soldier's firmware. It implements the Lorenz attractor with sensor perturbation:

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

The server-side `SilkenNet::Attractor` service independently computes the same Z-value for dual computation integrity verification.

## DID Generation

1. Read STM32 factory UID (96-bit unique identifier)
2. XOR with TRNG (True Random Number Generator) output
3. Format: `SNET-{last 8 hex digits}`
4. Lock in RTC backup registers (persists across resets)
5. Register with backend via `POST /api/v1/provisioning/register`
