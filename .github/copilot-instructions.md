# Copilot Instructions — SilkenNet

> **SSOT = `CLAUDE.md` + `docs/` (`00_00`→`08_03`) + [Wiki](https://github.com/Alexey-Lukin/silken_net/wiki). Read those first.**
> This file is a thin pointer + a short trap cheat-sheet. **If anything here conflicts with `CLAUDE.md`, `CLAUDE.md` WINS** (it is the single maintained home; this file is kept thin on purpose so it cannot drift).

**SilkenNet** — planetary Bio-IoT D-MRV platform for forest monitoring (Ti-6Al-4V gyroid anchor + EBFC → STM32 Soldier → LoRa → Queen gateway → Rails 8.1 / Ruby 4.0.5 / PostgreSQL / Sidekiq → 12-chain Web3 Proof-of-Growth → SCC mint).

For depth read `CLAUDE.md` (architecture §3, data models §4, Proof-of-Growth §5, Sidekiq queues §6, frontend §7, API §8, security §9, deploy §10, Web3 §11, **active BLOCKERs §12**, Solidity/Foundry §13, lazy-senior/YAGNI style §2а) and the numbered `docs/NN_NN_*.md`. Validation commands → `CLAUDE.md §2`.

---

## How Copilot is used here

Repo custom-instructions for Copilot Chat, PR review, and completions. For any non-trivial task, open `CLAUDE.md` + the relevant `docs/NN_NN` first — completions alone won't carry the project's invariants. **Active BLOCKERs live in `CLAUDE.md §12`** (don't mirror/guess them here); a BLOCKER = an active constraint until a real commit closes it (not a TODO/comment).

---

## Trap cheat-sheet (common wrong assumptions → home for the exact fact)

Not a restatement of facts (those live in `CLAUDE.md`) — just the traps + where to look:

- **LoRa crypto = AES-`128`-ECB** (NOT 256 — common stale assumption); CoAP = AES-256-CBC → `§3`.
- **Backend Lorenz = Float (IEEE 754 double)**, NOT BigDecimal (post-FW.7, bit-identical to firmware mruby) → `§3`/`§5`.
- **StatusByte changed post-FW.29** = `[PanicFlag:1 | status:2 | growth_points:5]` (don't assume 6-bit GP) → `§3`. Ruby unpack: `"N n c C n C C a4"`.
- **`db/structure.sql`**, never `schema.rb`. Thin controllers — logic only in `app/services/` / `app/workers/`.
- **Sidekiq `:strict: true`** strict queue-drain order → `§6` (don't change a worker's queue without justification).
- **Partitioned tables** (`TelemetryLog`/`GatewayTelemetryLog`/`BlockchainTransaction`) → always pass `created_at_iso` + use `find_with_partition_pruning`.
- **AES keys never leave the Ruby process** (`HardwareKey#cached_binary_key`, in-process LRU; no Redis-serialize).
- **`oracle_status`** has a prefix → `oracle_status_fulfilled?` (NOT `fulfilled?`).
- **`TelemetryLog` has no AR validations** (KENOSIS) — checks only in `TelemetryUnpackerService.valid_sensor_data?`; don't add them back.
- **Frontend = design-tokens only** in shared components (`bg-gaia-surface`…), `tokens(...)`, no DB in Phlex `initialize`, `focus-visible:` → `§7`.
- **Minting guard-clauses** (`verified_by_iotex? && oracle_status_fulfilled? && hadron_kyc_status == "approved"`) + `WEB3_STRICT_MODE`; Web3 logic only in service namespaces → `§11`.
- **TRL honesty:** anchor/EBFC = TRL 3 (in-silico ≠ TRL 4); don't overclaim → `§1`. Style: lazy-senior / YAGNI-first → `§2а`.

---

## Pointers (don't duplicate — read the home)

- Sidekiq 9-queue strict order → `CLAUDE.md §6`.
- 12-chain Web3 topology + roles → `CLAUDE.md §11` + `docs/05_01`.
- Where business logic lives (services/workers map) → `docs/04_02`.
- Solidity/Foundry conventions + invariant-gates (`test_pause_allowsSlash`, admin-last-guard, `totalSupply<=MAX`) → `CLAUDE.md §13`; contract spec → `docs/05_03`; test methodology → `docs/04_06 §B`.
- SSOT doc work / wiki-sync / doc-linters → skill `ssot-maintenance`.
