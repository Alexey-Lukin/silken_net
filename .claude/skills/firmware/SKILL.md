---
name: firmware
description: "Use when working on the silken_net STM32 firmware — Soldier (sense→TinyML→Lorenz→encrypt→TX, STOP2 loop) and Queen (LoRa RX→CIFO dedup→CoAP flush, OTA) in firmware/{soldier,queen}/main.c, the mruby bio_contract.rb, and the header-only One-Home libs in firmware/common/ (silken_sha256, lorenz_seed, lora_ccm, silken_crc, queen_attest). Knows the non-obvious gotchas — ECB-restore after CBC, Load_AES_Key before MX_CRYP_Init, RTC DR0..DR19 budget, post-FW.29 StatusByte bit-layout, Lorenz continuation vs cold-start, HAL_GetTick frozen in STOP2, vcap raw-ADC-not-mV, gated CCM vs live ECB — and the host-test parity discipline (make -C firmware/test). Routes to CLAUDE.md §3 + the 03_01..03_05 canon, does not restate. Examples: \"add a sensor field\", \"change Lorenz params\", \"modify AES / CRYP init\", \"touch RTC-persisted state\", \"why do LoRa decrypts fail after a flush\", \"edit the seed / cold-start crypto\"."
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
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md` | AES modes, HKDF key derivation, SE050 secure element (SEC.6; ATECC608B = banner-legacy pattern), IV, PQC roadmap |
| `docs/00_07_Action_Plan_Tracker.md` | FW.*/SEC.* task status, open items (canonical home of blockers) |

## Source Files

| File | Role |
|------|------|
| `firmware/soldier/main.c` | Sensor node: sense → TinyML → Lorenz → encrypt → TX (multi-phase STOP2 loop) |
| `firmware/queen/main.c` | Gateway: RX → decrypt → CIFO cache → batch flush via CoAP |
| `firmware/bio_contracts/bio_contract.rb` | mruby Lorenz attractor (runs on MCU); `calculate_state` is the sole entry-point |
| `firmware/common/*.h` | Shared header-only One-Home libs (compile into BOTH firmware + host tests — kill the mirror-drift pattern): `silken_sha256.h` (SHA-256/HMAC, FIPS/RFC KAT), `lorenz_seed.h` (FW.30 cold-start deriv), `silken_crc.h` (CRC16-CCITT, OTA), `lora_ccm.h` (CCM packet), `adc_convert.h` (FW.50 VREFINT-cal ADC→mV, helper-only/not-yet-wired), `queen_attest.h` (L1 QATT signed-batch envelope layout — wire home `03_05 §2.2`), `*_selftest.h` + `*_kat_vectors.h` (bench POST) |
| `firmware/test/` | x86 host-based tests — `make -C firmware/test` (host gate; not gcov-instrumented). **`make -C firmware/test asan`** = ASan+UBSan dynamic memory-safety lane (TEST.5, CI-gating in `firmware_test` — keep it green; canon `04_06 §B.1.1`). New crypto in `common/` ⇒ add a parity test vs OpenSSL, don't re-copy logic into the test file. |

> Line counts drift every commit — don't hardcode them (see `[[feedback_no_volatile_counts]]`); `wc -l` if you need a number.

## Gotchas Not Obvious From Docs

1. **ECB restore after CBC flush** — Queen MUST call `Restore_ECB_Mode()` after every CBC operation. Without it, subsequent LoRa decrypts silently fail (wrong KeySize + wrong key loaded in CRYP peripheral).
2. **RTC registers are all spoken-for — but allocated ≠ optimally packed** — DR0..DR19 fully allocated; after the FW.2 freeze-contract even DR15 is reserved (CCM Frame Counter, dormant until `FW2_CCM_ENABLED` flips at bench). For new persisted state: **first** check `03_01 §2.3.2` reclamation (several DRs are under-utilized → freeable without Flash: DR2 holds a 1-bit flag, DR14/DR19 pack, and DR7/DID is an inversion — write-once identity wasting a wear-free slot) **before** paying Flash-KV (`03_01 §2.3`) wear. RAM-state inventory + key→field map = `03_01 §2.3.1`. Canonical register map (bit-fields + magic markers) = `03_01 §2` — never restate the allocation in code comments, reference it.
3. **`Load_AES_Key()` BEFORE `MX_CRYP_Init()`** — reversing the order means CRYP uses a zeroed key. Both files follow this order but it's easy to break during refactoring.
4. **Cold-TX deferral** — at low temp + low Vcap (FW.10 winter ESR guard), Soldier skips TX entirely to avoid brownout. Don't assume every wake cycle emits a packet.
5. **StatusByte layout is post-FW.29** — packet byte 10 = `[PanicFlag:1 (bit7) | Status:2 (bits6..5) | GrowthPoints:5 (bits4..0)]`; firmware packs `(status << 5) | growth_points`, backend unpacks `(byte & 0x1F) * 2`. `Status` now has 4 values (0 homeostasis / 1 stress / 2 anomaly / 3 tamper). Normal frames force bit7=0 (`lora_payload[10] &= ~PANIC_FLAG_BIT`); panic frames set it. Canon: `03_04 §` Status-byte + `03_01 §8`.
6. **Lorenz state: continuation vs cold-start** — on boot, `DR19 == LORENZ_STATE_MAGIC (0x4C5A5354 "LZST") && isfinite(x,y,z)` → restore `(x,y,z)` from DR16/17/18 (warm continuation, >99% of cycles); else cold-start derives `(x₀,y₀,z₀)` from `K_seed` (Flash) via **`common/lorenz_seed.h`** (pure-C HMAC-SHA256 — byte-parity with backend `SeedDerivation`, FW.30 closed; mbedTLS no longer needed). `epoch_day` prefers beacon UTC (`soldier_unix_ts`, FW.20) over the RTC calendar; RTC-default after VBAT loss = 10957 (2000-01-01) = backend's `FIRMWARE_RTC_DEFAULT_EPOCH_DAY`. After each cycle the C side MUST write DR16-18 + set DR19. Canon: `03_04 §2.1`; layout `03_01 §2`.
7. **CCM is gated, ECB is live** — the FW.2 AES-128-CCM path (28B wire-rev2 frame, 8B MIC, 24-bit DR15 Frame Counter) is fully coded + host-tested but compiled out behind `#define FW2_CCM_ENABLED 0` until `CRYP_AES_CCM` is verified on an STM32WLE5JC bench. The shipping build is **AES-128-ECB transitional** (no MAC/IV). Don't assume CCM is active. Flip needs 3 Queen RX-fixes freeze-contract doesn't cover — see `03_05 §FW.2 flip-checklist`.
8. **`HAL_GetTick()` is frozen in STOP2** — SysTick stops during `EnterSTOP2Mode`, so every tick-based duration on the Soldier (`delta_t_seconds` metabolism — the *primary* bio-signal!, FW.27-B re-request, FW.20-S2 drift/cooldown) measures only active-time, NOT wall-time. Structural, not yet fixed — `00_07 FW.49`. Host mocks have a monotonic tick → they hide this. Don't trust a tick delta as wall-seconds.
9. **`vcap_voltage` is a raw ADC count, not mV** — `HAL_ADC_GetValue()` returns 0..4095 but the code treats it as millivolts (thresholds 2800/4000/4500, EMA, mruby `vcap_mv`). On real silicon those thresholds never trip. `00_07 FW.50`. Also VREFINT measures VDDA, not the EDLC. Pure conversion helper `Adc_Raw_To_Mv()` is ready + host-tested in `common/adc_convert.h`, but **not yet wired** — the live fix is gated on a Vcap resistor divider + separate ADC channel (hardware).
10. **`BIO_STATUS_VM_ERROR = 0x60`** (not 0xFF) — must survive the `& ~PANIC_FLAG_BIT` mask as tamper+gp=0. Backend `emission_eligible_growth_points` also zeroes gp for anomaly/tamper (defense-in-depth). A wire byte with status=anomaly/tamper must NEVER mint.
11. **OTA wire has two layers** — LoRa Queen→Soldier: `[0x99][idx:2][total:2][bytecode:11]` (5B header). CoAP Rails→Queen: `[0x99][idx:2][total:2][len:2][bytecode:len][crc16:2]` — explicit `len` (NOT length-guessing from CBC padding — that bug truncated every chunk) + CRC16 verified via `common/silken_crc.h`. The assembled stream Soldier CRC32-checks = `bytecode + zero-pad + CRC32`, LoRa-MTU(11)-aligned. Built by `OtaPackagerService`. Canon `03_01 §4.6` / `03_02 §5`.

## Common Tasks

- **Add sensor field**: Soldier Phase 1 ADC → pack in `lora_payload[]` → Queen `Process_And_Cache_Data` → `Flush_Cache_To_Rails` → Rails `TelemetryUnpackerService` unpack string → host tests. Check the RTC budget first (`03_01 §2`; allocated-full, but `§2.3.2` reclamation often frees a DR before reaching for Flash).
- **Change Lorenz params / `bio_contract.rb`**: edit `bio_contract.rb` AND `app/services/silken_net/attractor.rb` → run parity tests (must stay bitwise-identical, Float IEEE-754 both sides). **Two hidden gates a subset-run misses** (both tripped in E.63 + E.64): (1) regenerate `lorenz_bytecode.h` (`tools/firmware/gen_bytecode.sh`) — the **FW.46 sha256 stamp-gate goes red if it's stale**; (2) a signature change → grep **`spec/` too** (not just app/lib — once missed 6 integration-spec callers) + run the **FULL `bin/rspec`**, never a subset, before pushing a contract/DCI change.
- **Change seed/cold-start crypto**: edit `common/lorenz_seed.h` / `silken_sha256.h` ONCE (shared) → `make -C firmware/test seed_derivation` re-proves parity vs OpenSSL + backend `SeedDerivation`. Never fork the math into the test file.
- **Modify AES**: touch `MX_CRYP_Init()` in BOTH files, update `Load_AES_Key()`, `Restore_ECB_Mode()`, host tests. On a bench, `make -C firmware/test selftest sym_selftest` (CCM + ECB/CBC KAT) attests silicon==OpenSSL — catches the `CRYP_DATATYPE_32B` word-swap class invisible to passthrough host mocks.
- **Touch RTC-persisted state**: update the `03_01 §2` canonical table FIRST (SSOT), add `isfinite()`/magic/range restore guards, then ≥3 host tests (cold-boot / warm-roundtrip / corruption-fallback).
