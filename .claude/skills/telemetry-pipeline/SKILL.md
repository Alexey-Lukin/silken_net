---
name: telemetry-pipeline
description: "Use when working on the silken_net telemetry / Proof-of-Growth pipeline — the uplink→verification→minting flow (CoAP intake → UnpackTelemetryWorker / TelemetryUnpackerService → IoTeX verify → Chainlink oracle → mint), the Sidekiq strict-priority queues, TelemetryLog (RANGE-partitioned, KENOSIS — validations live in valid_sensor_data?, not the model), and the dual-computation integrity (server Float Lorenz ≡ firmware mruby). Knows the gotchas — DID=0 in a batch is DEAD (ARCH.54: Queen pulse rides the signed QATT-v2 header → enqueue_envelope_health, both eras drop DID=0), oracle_status_*? enum methods, strict queue drain (uplink fully before alerts), partition-pruning One-Home (TelemetryLog.partition_pruned — NOT find_with_partition_pruning, which is BlockchainTransaction's). The gotcha bodies live in gotchas.md, one generated index line each in the body — open it before touching the intake, the unpacker, a telemetry column or its readers, the partitions or the DCI checks. Routes to CLAUDE.md §5/§6 + the 05_02 canon, does not restate. Examples: \"add a telemetry field\", \"change minting logic / guards\", \"why is an alert delayed\", \"decode the uplink packet\", \"why does server Z differ from device Z\"."
---

# Telemetry Pipeline

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §1` | Proof of Growth pipeline — full A→D flow (sense→…→mint SCC) |
| `CLAUDE.md §5` | Sidekiq strict-priority queues + Lorenz/StatusByte + AES invariants |
| `CLAUDE.md §6` | Telemetry cross-domain gotchas (oracle_status prefix · KENOSIS · partitions) |
| `docs/05_02_Proof_of_Growth_Pipeline.md` | Exact worker ordering with queue assignments |
| `docs/05_03_Tokenomics_SCC_and_SFC.md` | Growth points, SCC minting (slashing → `05_05`) |
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md §3` | AES decrypt chain, key management |

## Gotchas Not Obvious From Docs

**Bodies live in [`gotchas.md`](gotchas.md) — open it before you touch the uplink intake, the unpacker, a telemetry column or its readers, the partitions, the DCI/Lorenz checks or a telemetry enqueue.** One generated line per gotcha below: the line is the CARRIER, meant to stop you mid-action; the mechanism and the bounds are in the companion. Numbering is append-only — cite `telemetry-pipeline #N`.

<!-- TELEMETRY-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. DID `0x00000000` in a batch is DEAD — the Queen pulse rides the signed QATT-v2 header, so never re-add gateway metrics as a fake tree
2. Call `log.oracle_status_fulfilled?`, never compare `oracle_status` to a string — it is a string-backed enum with the `oracle_status_` prefix
3. Dual computation: server Lorenz (Float) must match firmware mruby (Float) — any leftover `to_d` / BigDecimal code is a bug since FW.7
4. Queue drain is strict: `uplink` (#1) drains COMPLETELY before `alerts` (#2), so a telemetry flood delays alerts — by design
5. TelemetryLog carries no validations by design (KENOSIS TITAN) — the check lives in `TelemetryUnpackerService.valid_sensor_data?`; never add them back to the model
6. Partition-aware lookups: prune through the One-Home helper picked by CARDINALITY, never hand-roll `created_at` equality, and retain only by dropping partitions
7. «Wire = вхід GP»: the CCM frame carries the exact EMA `delta_t` the device fed into growth points, and the server recomputes GP from it statelessly
8. `firmware_version_id` — це wire-ЗВІТ, не FK: читай через `TelemetryLog#firmware_report_*`, ніколи не джойни й не порівнюй з `BioContractFirmware.id`
9. TelemetryLog несе MRV-lineage сліди, і стемпнутий рядок запечатаний — мутація leaf-поля кидає raise, а нове leaf-поле вимагає `LEAF_VERSION`-bump
10. Device-event 0x57 = ОКРЕМИЙ L1-канал, не телеметрія (SEC.21, 2026-07-12)
11. Детекція OTA-mismatch гейтована колонкою, якої доти не писав НІХТО — тож гілка ніколи не виконувалась, і оживить її не телеметрія, а фікс форми
12. `acoustic_events` змінив wire-семантику (ARCH.102, 2026-08-16): тепер це «детекції від останнього УСПІШНОГО uplink'а» — а доти на дроті було завжди 0 або 1, і бекендні пороги писались під семантику «подій за вікно», якої прошивка не мала
13. `telemetry_logs.sap_flow` не пише НІХТО — колонки нема в жодному wire-форматі (`PAYLOAD_FORMAT`, `CCM_SENSOR_PAYLOAD_FORMAT`), писальників у `app/` нуль — а читачі живі, і найгостріший тихо вимикає антифрод
14. Enqueue телеметрії мусить нести момент ПРИЙОМУ — інакше доба cold-derive Лоренца тихо з'їжджає на добу ОБРОБКИ
15. Soldier-pulse НЕ є окремим кадром і не потребує гілки в розпакувальнику
16. Z у продові читає РІВНО ОДИН споживач — `check_z_divergence!` (DCI). Не заводити з `z_value`/`Attractor`-предикатів жодного вердикту про ЗДОРОВʼЯ
17. `TelemetryUnpackerService#perform` ПОВЕРТАЄ `Summary`, а трансляція в UI стоїть ПІСЛЯ нього — і обидві половини несучі
18. `bin/forest_simulator` рахує `bio_status` ВЛАСНИМ Lorenz-ланцюгом і читає серверний хвіст рівно раз на процес — інакше DCI або вічно червона, або зелена за побудовою

<!-- /TELEMETRY-GOTCHAS-INDEX -->

## Common Tasks

- **Add telemetry field**: firmware pack → `TelemetryUnpackerService` unpack → DB migration → Phlex dashboard component → update `05_02`
- **Change minting logic**: `BlockchainMintingService` → the **2-guard oracle chain (IoTeX + oracle_status)** protects PATH 1 only (latent — ARCH.53 §🗄️: dispatch = local marker, DON-callback unwired, closure refused 2026-07-19); **KYC (Hadron) guards ALL paths and is the sole PATH-2 perimeter** — ⚠️ **периметр є, але СЬОГОДНІ він закритий для КОЖНОГО custodial-бенефіціара назавжди й мовчки** [ARCH.119]: єдиний писач `approved` не має адресата (ARCH.118), тож читати цей рядок як «є робочий запобіжник» = хибно; дім — скіл `web3-pipeline` гоча 1e (live PATH 2 mint = optimistic, KYC-only; L0-custodial + ex-post clawback). Service-home = `04_02 §4`; tokenomics course → `05_03` (see `web3-pipeline` skill)
