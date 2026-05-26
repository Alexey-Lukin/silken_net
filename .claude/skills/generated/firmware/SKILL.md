---
name: firmware
description: "Navigation + gotchas for Soldier/Queen STM32 firmware. Read SSOT docs first."
---

# Firmware (Soldier + Queen)

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §3` | Full architecture, AES table, packet format, OTA, Lorenz |
| `docs/03_01_Firmware_Architecture.md` | Soldier/Queen lifecycle, STOP2 cycle, phase detail |
| `docs/03_04_mruby_Lorenz_Attractor.md` | Lorenz constants, Float vs BigDecimal, RTC persistence |
| `docs/03_05_Security_Architecture.md` | AES modes, HKDF key derivation, ATECC608B, PQC roadmap |
| `docs/00_08_Action_Plan_Tracker.md` | FW.* task status, blockers |

## Source Files

| File | Lines | Role |
|------|-------|------|
| `firmware/soldier/main.c` | ~1200 | Sensor node: sense → TinyML → Lorenz → encrypt → TX |
| `firmware/queen/main.c` | ~600 | Gateway: RX → decrypt → cache → batch flush via CoAP |
| `firmware/bio_contracts/bio_contract.rb` | ~120 | mruby Lorenz attractor (runs on MCU) |
| `firmware/test/` | host tests | x86 host-based tests (`make -C firmware/test`) |

## Gotchas Not Obvious From Docs

1. **ECB restore after CBC flush** — Queen MUST call `Restore_ECB_Mode()` after every CBC operation. Without it, subsequent LoRa decrypts silently fail (wrong KeySize + wrong key loaded in CRYP peripheral).
2. **RTC registers are FULL** — DR0-DR19 all used. New persisted state requires packing or freeing existing registers.
3. **Load_AES_Key() BEFORE MX_CRYP_Init()** — reversing order means CRYP uses zeroed key. Both files follow this order but it's easy to break during refactoring.
4. **Cold TX deferral** — at temp < -15°C and Vcap < 4000mV, Soldier skips TX entirely to avoid brownout. Don't assume every wake cycle produces a packet.
5. **StatusByte changed post-FW.29** — layout is now `[PANIC_FLAG:1|status:2|growth_points:5]`, not the original `[status:2|growth_points:6]`. Both firmware and backend must match.

## Common Tasks

- **Add sensor field**: Soldier Phase 1 ADC → pack in `lora_payload[]` → Queen `Process_And_Cache_Data` → `Flush_Cache_To_Rails` → Rails `TelemetryUnpackerService` unpack string → host tests
- **Change Lorenz params**: edit `bio_contract.rb` AND `app/services/silken_net/attractor.rb` → run parity tests
- **Modify AES**: touch `MX_CRYP_Init()` in BOTH files, update `Load_AES_Key()`, `Restore_ECB_Mode()`, and host tests
