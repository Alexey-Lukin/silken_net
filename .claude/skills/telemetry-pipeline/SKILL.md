---
name: telemetry-pipeline
description: "Use when working on the silken_net telemetry / Proof-of-Growth pipeline — the uplink→verification→minting flow (CoAP intake → UnpackTelemetryWorker / TelemetryUnpackerService → Wallet#credit! → optimistic mint = live PATH 2; IoTeX verify → Chainlink = PATH 1, latent / activation-gated — ARCH.53), the Sidekiq strict-priority queues, TelemetryLog (RANGE-partitioned, KENOSIS — the bounds check runs in the unpacker before create!, never in the model), and the dual-computation integrity (server Float Lorenz ≡ firmware mruby). Knows the gotchas — DID=0 in a batch is DEAD (ARCH.54: Queen pulse rides the signed QATT-v2 header → enqueue_envelope_health, both eras drop DID=0), oracle_status_*? enum methods, strict queue drain (uplink fully before alerts), partition-pruning One-Home (TelemetryLog.partition_pruned — NOT find_with_partition_pruning, which is BlockchainTransaction's). The gotcha bodies live in gotchas.md, one generated index line each in the body — open it before touching the intake, the unpacker, a telemetry column or its readers, the partitions or the DCI checks. Routes to CLAUDE.md §5/§6 + the 05_02 canon, does not restate. Examples: \"add a telemetry field\", \"change minting logic / guards\", \"why is an alert delayed\", \"decode the uplink packet\", \"why does server Z differ from device Z\"."
---

# Telemetry Pipeline

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §1` | One-line overview of the pipeline (sense→…→mint SCC) |
| `CLAUDE.md §5` | Sidekiq strict-priority queues + Lorenz/StatusByte + AES invariants |
| `CLAUDE.md §4` | KENOSIS — the telemetry hot path carries no AR validations |
| `CLAUDE.md §6` | DCI = categorical match (Float Lorenz) · partitions (One-Home by cardinality) · minting guard-clauses (PATH 1/2, beneficiary KYC) |
| `docs/05_02_Proof_of_Growth_Pipeline.md` | The full A→F flow (workers + queues) · PATH 1 / PATH 2 trust model |
| `docs/05_03_Tokenomics_SCC_and_SFC.md` | Growth points, SCC minting (slashing → `05_05`) |
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md §2` · `§3.1` · `§6` | Wire + decrypt chain · key source · channel summary table |

## Gotchas Not Obvious From Docs

**Bodies live in [`gotchas.md`](gotchas.md) — open it before you touch the uplink intake, the unpacker, a telemetry column or its readers, the partitions, the DCI/Lorenz checks or a telemetry enqueue.** One generated line per gotcha below: the line is the CARRIER, meant to stop you mid-action; the mechanism and the bounds are in the companion. Numbering is append-only — cite `telemetry-pipeline #N`.

<!-- TELEMETRY-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. DID `0x00000000` in a batch is DEAD — the Queen pulse rides the signed QATT-v2 header, so never re-add gateway metrics as a fake tree
2. Call `log.oracle_status_fulfilled?` — the enum is declared `prefix: true`, so a bare `fulfilled?` raises NoMethodError and `== :fulfilled` (a Symbol) is silently false
3. Dual computation: server Lorenz (Float) must match firmware mruby (Float) — a `to_d`/BigDecimal operand inside the Lorenz/DCI arithmetic is a bug since FW.7; the `decimal` column `z_value` and the leaf `to_s("F")` are storage, not computation
4. Queue drain is strict: `uplink` (#1) drains COMPLETELY before `alerts` (#2), so a telemetry flood delays alerts — by design
5. TelemetryLog carries no validations by design (KENOSIS TITAN) — the bounds check runs in `TelemetryUnpackerService` BEFORE `create!` (`#valid_sensor_data?` on ECB, an inline `SAFE_*_RANGE` guard on CCM); never add validations back to the model
6. Partition-aware lookups: prune through the One-Home helper picked by CARDINALITY, never hand-roll `created_at` equality, and retain only by dropping partitions
7. «Wire = вхід GP»: the CCM frame carries the exact EMA `delta_t` the device fed into growth points, and the server recomputes GP from it statelessly
8. `firmware_version_id` — це wire-ЗВІТ, не FK: читай через `TelemetryLog#firmware_report_*`, ніколи не джойни й не порівнюй з `BioContractFirmware.id`
9. TelemetryLog несе MRV-lineage сліди, і стемпнутий рядок запечатаний — мутація leaf-поля кидає raise, а нове leaf-поле вимагає `LEAF_VERSION`-bump
10. Device-event 0x57 = ОКРЕМИЙ L1-канал, не телеметрія (SEC.21, 2026-07-12)
11. OTA-mismatch у розпакувальнику СПОСТЕРЕЖНИЙ (ARCH.85): колонку-гейт тепер пише форма, тож гілка біжить, але лише логує й `fw_pending` не ставить — а перш ніж довіритись гілці, гейтованій колонкою, перелічи ПИСАЛЬНИКІВ, не читачів
12. `acoustic_events` = детекції від останнього УСПІШНОГО uplink'а (ARCH.102): накопичення легальне, `0xFE` — сентинел часу, а кавітація й пилка злиті в один лічильник — вердикту на цьому полі не будуй
13. `telemetry_logs.sap_flow` не пише НІХТО — поля нема в жодному wire-форматі, а єдиний живий читач заходить через мапу `latest_per_tree`, тож читачів колонки шукай і за спільним ВХОДОМ, не лише за іменем
14. Enqueue телеметрії мусить нести момент ПРИЙОМУ — інакше доба cold-derive Лоренца тихо з'їжджає на добу ОБРОБКИ
15. Soldier-pulse НЕ є окремим кадром і не потребує гілки в розпакувальнику
16. Z у проді має РІВНО ОДНОГО споживача-вердикт — `check_z_divergence!` (DCI); решта читачів `z_value` лише показують чи пінять його, і жодного вердикту про ЗДОРОВʼЯ з `z_value`/`Attractor`-предикатів не заводити
17. `TelemetryUnpackerService#perform` ПОВЕРТАЄ `Summary`, а трансляція в UI стоїть ПІСЛЯ нього — і обидві половини несучі
18. `bin/forest_simulator` рахує `bio_status` ВЛАСНИМ Lorenz-ланцюгом і читає серверний хвіст рівно раз на дерево за процес — інакше DCI або вічно червона, або зелена за побудовою

<!-- /TELEMETRY-GOTCHAS-INDEX -->

## Common Tasks

- **Add telemetry field**: FIRST a row in the wire-budget ledger `03_05 §2.1` (headroom after rev2.1 is zero → a new field is a wire revision, `03_01 §1.6`) → firmware pack on both eras (ECB `PAYLOAD_FORMAT` · CCM `CCM_SENSOR_PAYLOAD_FORMAT`) → unpack in both chunk paths + decide column ⊥ transient (the strip-list in `commit_telemetry`) → migration + the `TelemetryLog` row in `04_01 §3` → a leaf field needs a `LEAF_VERSION` bump (#9); it never enters Lorenz-Z; add a reader only together with its writer (#13)
- **Change minting logic**: `BlockchainMintingService` (service-home `04_02 §4`). Guard-clauses (PATH 1 latent · PATH 2 optimistic · beneficiary KYC — the only VERIFICATION gate of PATH 2, today a closed door until a real provider, BIZ.20; beside it stand non-verification SKIP/HOLD: SEC.13 `peaq_did_compromised`, the SFC block, the ARCH.62 circuit-flag) → `CLAUDE.md §6` «Мінтинг guard-clauses»; mechanism → `web3-pipeline` #1 · #12 · #1e; tokenomics → `05_03`. ⛔ Never read the KYC line as a working safeguard.
