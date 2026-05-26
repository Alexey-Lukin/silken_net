---
name: firmware
description: "Domain knowledge for Soldier and Queen STM32 firmware — AES modes, packet format, OTA, Lorenz state, gotchas"
---

## Architecture

Both Soldier and Queen run on **STM32WLE5JC** (Cortex-M4, 256KB Flash, 64KB RAM, integrated sub-GHz radio SX1262).

**Soldier** (`firmware/soldier/main.c`): sensor node implanted in a tree. Wakes from STOP2, runs 5 phases (Sense -> TinyML -> mruby Lorenz -> AES encrypt -> LoRa TX), then sleeps. Single main-loop iteration per wake. DID stored in RTC DR7.

**Queen** (`firmware/queen/main.c`): gateway node with SIM7070G modem. Runs continuously: LoRa RX (FIFO ring, 16 slots) -> AES-128-ECB decrypt -> CIFO edge cache (50 slots, dedup by DID) -> hourly AES-256-CBC batch flush via CoAP to Rails. Also handles OTA relay and time beacon broadcast every 15 min.

## AES Modes (post-ARCH.42, 2026-05-23)

| Direction | Mode | Key size | Key source | IV |
|-----------|------|----------|------------|----|
| Soldier -> Queen (LoRa) | AES-128-ECB (transitional) | 128-bit | `aes_key[4]` from `FLASH_KEY_ADDR` (0x0803E000) | none |
| Queen -> Soldier (OTA reflex + beacon) | AES-128-ECB | 128-bit | same LoRa key | none |
| Queen -> Rails (CoAP batch) | AES-256-CBC | 256-bit | `coap_key[8]` (separate Flash slot, TODO) | HRNG 16B |
| Rails -> Queen (CoAP downlink) | AES-256-CBC | 256-bit | same CoAP key | from payload |
| FW.2 target: Soldier -> Queen | AES-128-CCM | 128-bit | same LoRa key | DID+FC nonce | 24B packet, 8B MIC |

## Packet Format

**21-byte transitional packet** (5 unencrypted + 16 encrypted as 1 ECB block):

```
[DID:4][RSSI:1] | [Vcap:2][Temp:1][Acoustic:1][dT:2][StatusByte:1][TTL:1][FW_VER:2][GossipTs:1][PAD:1]
  Queen prepends   AES-128-ECB encrypted (16 bytes)
```

StatusByte layout: `[PANIC_FLAG:1 | status:2 | growth_points:5]` (post-FW.29). Ruby unpack: `"N n c C n C C a4"`.

**FW.2 target**: 24-byte CCM packet `[DID:4][FC:4][CT:8][MIC:8]`. Freeze-contract in `firmware/common/lora_ccm.h`. Gated by `FW2_CCM_ENABLED 0`.

## Critical Gotchas

1. **ECB restore after CBC flush**: `Restore_ECB_Mode()` in queen MUST be called after every CBC operation (Flush_Cache_To_Rails, Handle_CoAP_Command). Without it, LoRa decrypt breaks silently (wrong KeySize + wrong key). If HAL_CRYP_Init fails: RCC reset -> retry -> NVIC_SystemReset.

2. **Antenna BEFORE power on SX1262**: powering the radio without antenna connected will damage the PA. Pre-flight hardware check.

3. **HRNG IV reuse (Queen)**: if HRNG fails, CBC IV falls back to djb2(queen_uid) XOR tick -- predictable. Not a cryptographic PRNG.

4. **Load_AES_Key() BEFORE MX_CRYP_Init()**: both Soldier and Queen call Load_AES_Key first, then MX_CRYP_Init. Reversing order means CRYP uses zeroed key.

5. **Cold TX deferral**: at temp < -15C and Vcap < 4000mV, Soldier skips TX entirely (goto phase5_kenosis) to avoid brownout.

6. **RTC Backup Register map is FULL** (DR0-DR19, all 20 used). Adding new persisted state requires packing/freeing existing registers.

## OTA Flow

**Rails -> Queen**: CoAP downlink delivers 512B chunks wrapped in `[0x9C ts envelope][0x99][idx:2BE][total:2BE][bytecode][CRC16]`. Queen assembles in `pending_ota_bytecode[8192]` with bitmap dedup. After all chunks: `ota_is_active = 1`.

**Queen -> Soldier**: reflex broadcast -- on each Soldier LoRa RX, Queen sends one chunk `[0x99][idx:2][total:2][11B data]` encrypted ECB. Pacing: 60ms between chunks. After bytecode: 3x HMAC trailer chunks `[0x9B][seg:2][total:2][11B hmac_segment]`.

**Soldier OTA assembly**: `ota_buffer[1024]`, per-chunk flag array. After all chunks received: CRC32 check + HMAC dual-gate (Gate 1: magic `0x45544952` = "RITE"; Gate 2: constant-time HMAC compare). Only then `Write_OTA_Contract_To_Flash()` + `NVIC_SystemReset()`.

**Re-request (FW.27-B)**: after 5 min silence, Soldier sends `[0x55][DID:4][total:2BE][bitmap:9]` (missing chunks). Queen replays only missing.

**Flash addresses**: OTA bytecode at `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`. AES key at `0x0803E000`. Queen UID at `0x0803F800`.

## Lorenz Attractor State

mruby contract `firmware/bio_contracts/bio_contract.rb` runs 250 Euler iterations (Float, not BigDecimal). Called as `calculate_state(x, y, z, temp, acoustic, delta_t_s, vcap_mv)` returning `[payload_byte, x_final, y_final, z_final]`.

**RTC persistence**: state (x,y,z) in DR16-DR18 as IEEE 754 float bit-copies. DR19 = magic `0x4C5A5354` ("LZST"). On boot: if magic present and values are finite -> restore. Otherwise cold-start from K_seed (HKDF/HMAC derivation via `Derive_Cold_Start_State()`).

**K_seed**: 32 bytes at `FLASH_SEED_ADDR` (0x0803E000 + 20), magic "LSED". Per-device, derived via HKDF-SHA256.

## Common Tasks

**Adding a new sensor field to telemetry**:
1. Add ADC read in Soldier Phase 1 (after `vcap_voltage` read, ~line 1397)
2. Pack into `lora_payload[]` -- find a free byte or repurpose PAD bytes 14-15 (byte 14 is gossip_ts in normal frames, bytes 14-15 are panic counter in panic frames)
3. Update Queen `Process_And_Cache_Data` if CIFO priority logic needs it
4. Update Queen `Flush_Cache_To_Rails` 21-byte binary packing (offset calc)
5. Update Rails `TelemetryUnpackerService` unpack format string
6. Update `firmware/test/test_soldier_logic.c` host tests

**Modifying AES encryption**: touch `MX_CRYP_Init()` in both files. If changing key size, update `FLASH_KEY_WORDS`, `Load_AES_Key()`, and `Restore_ECB_Mode()`. Run host tests in `firmware/test/`.

**Changing Lorenz parameters**: edit `firmware/bio_contracts/bio_contract.rb` AND `app/services/silken_net/attractor.rb` (backend mirror). Run parity tests.

## Active Blockers

- **TinyML commented out**: `Run_Inference()` call at soldier ~line 1468 is commented. Model header `silken_net_audio_model.h` absent, stub used.
- **AT blind delay**: Queen `SIM7070_SendATCommand()` uses `HAL_Delay()`. Partially mitigated by `SIM7070_SendATCommand_WithResponse()` (FW.9) but legacy callers remain.
- **AES-ECB on LoRa**: no MAC, no IV. Replay/bit-flip vulnerable. Closed by FW.2 (AES-128-CCM). Needs STM32 hardware bench for `CRYP_AES_CCM` HAL verification.
- **CoAP AES-256 key not loaded from Flash**: `coap_key[8]` is zeroed at boot; `Load_CoAP_Key()` not yet implemented (ARCH.42 follow-up).
