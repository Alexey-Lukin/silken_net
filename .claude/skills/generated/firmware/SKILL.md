---
name: firmware
description: "Navigation + gotchas for Soldier/Queen STM32 firmware. Read SSOT docs first."
---

# Firmware (Soldier + Queen)

Navigation aid + non-obvious gotchas. The **SSOT is the docs + code below** — this skill
points, it does not restate (so it can't drift). Verify a fact at its home before trusting a summary.

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §3` | High-level architecture, AES table, OTA, Lorenz (summary — for exact packet/Status-byte bit-layout trust the canon docs below, not the summary) |
| `docs/03_01_Firmware_Lifecycle_and_DMA.md` | Soldier/Queen lifecycle, STOP2 phases, ISR map, **RTC Backup Register Map §2 (canonical DR0..DR19 + magic markers)**, binary packet format §8 |
| `docs/03_02_Queen_Gateway_Firmware.md` | Queen: LoRa RX → CIFO dedup → CoAP flush, OTA broadcast, AES mode transitions |
| `docs/03_03_TinyML_Acoustic_Inference.md` | Audio DMA, CMSIS-NN, decision logic, confidence thresholds (DR13/DR14) |
| `docs/03_04_mruby_Lorenz_Attractor.md` | Lorenz constants (§4.1), Float-not-BigDecimal parity, RTC continuation vs cold-start (§2.1), Status-byte packing |
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md` | AES modes, HKDF key derivation, ATECC608B, IV, PQC roadmap |
| `docs/00_07_Action_Plan_Tracker.md` | FW.*/SEC.* task status, open items (canonical home of blockers) |

## Source Files

| File | Role |
|------|------|
| `firmware/soldier/main.c` | Sensor node: sense → TinyML → Lorenz → encrypt → TX (multi-phase STOP2 loop) |
| `firmware/queen/main.c` | Gateway: RX → decrypt → CIFO cache → batch flush via CoAP |
| `firmware/bio_contracts/bio_contract.rb` | mruby Lorenz attractor (runs on MCU); `calculate_state` is the sole entry-point |
| `firmware/test/` | x86 host-based tests — `make -C firmware/test` (host gate; not gcov-instrumented) |

> Line counts drift every commit — don't hardcode them (see `[[feedback_no_volatile_counts]]`); `wc -l` if you need a number.

## Gotchas Not Obvious From Docs

1. **ECB restore after CBC flush** — Queen MUST call `Restore_ECB_Mode()` after every CBC operation. Without it, subsequent LoRa decrypts silently fail (wrong KeySize + wrong key loaded in CRYP peripheral).
2. **RTC registers are all spoken-for** — DR0..DR19 fully allocated; after the FW.2 freeze-contract even DR15 is reserved (CCM Frame Counter, dormant until `FW2_CCM_ENABLED` flips at bench). New persisted state goes to **Flash-KV overflow (`03_01 §2.3`)**, not a new register. Canonical map (incl. bit-fields + magic markers) = `03_01 §2` — never restate the allocation in code comments, reference it.
3. **`Load_AES_Key()` BEFORE `MX_CRYP_Init()`** — reversing the order means CRYP uses a zeroed key. Both files follow this order but it's easy to break during refactoring.
4. **Cold-TX deferral** — at low temp + low Vcap (FW.10 winter ESR guard), Soldier skips TX entirely to avoid brownout. Don't assume every wake cycle emits a packet.
5. **StatusByte layout is post-FW.29** — packet byte 10 = `[PanicFlag:1 (bit7) | Status:2 (bits6..5) | GrowthPoints:5 (bits4..0)]`; firmware packs `(status << 5) | growth_points`, backend unpacks `(byte & 0x1F) * 2`. `Status` now has 4 values (0 homeostasis / 1 stress / 2 anomaly / 3 tamper). Normal frames force bit7=0 (`lora_payload[10] &= ~PANIC_FLAG_BIT`); panic frames set it. Canon: `03_04 §` Status-byte + `03_01 §8`.
6. **Lorenz state: continuation vs cold-start** — on boot, `DR19 == LORENZ_STATE_MAGIC (0x4C5A5354 "LZST") && isfinite(x,y,z)` → restore `(x,y,z)` from DR16/17/18 (warm continuation, >99% of cycles); else cold-start derives `(x₀,y₀,z₀)` from `K_seed` (Flash) via HKDF/HMAC on `epoch_day`. After each cycle the C side MUST write DR16-18 + set DR19. Canon decision table: `03_04 §2.1`; layout: `03_01 §2`.
7. **CCM is gated, ECB is live** — the FW.2 AES-128-CCM path (24B frame, 8B MIC, DR15 Frame Counter) is fully coded + host-tested but compiled out behind `#define FW2_CCM_ENABLED 0` until `CRYP_AES_CCM` is verified on an STM32WLE5JC bench. The shipping build is **AES-128-ECB transitional** (no MAC/IV). Don't assume CCM is active.

## Common Tasks

- **Add sensor field**: Soldier Phase 1 ADC → pack in `lora_payload[]` → Queen `Process_And_Cache_Data` → `Flush_Cache_To_Rails` → Rails `TelemetryUnpackerService` unpack string → host tests. Check the RTC budget first (`03_01 §2` — registers are full).
- **Change Lorenz params**: edit `bio_contract.rb` AND `app/services/silken_net/attractor.rb` → run parity tests (must stay bitwise-identical, Float IEEE-754 both sides).
- **Modify AES**: touch `MX_CRYP_Init()` in BOTH files, update `Load_AES_Key()`, `Restore_ECB_Mode()`, and host tests (`make -C firmware/test`).
- **Touch RTC-persisted state**: update the `03_01 §2` canonical table FIRST (SSOT), add `isfinite()`/magic/range restore guards, then ≥3 host tests (cold-boot / warm-roundtrip / corruption-fallback).
