# Copilot Instructions — SilkenNet

> **SSOT = `CLAUDE.md` + `docs/` (`00_00`→`06_08`) + [Wiki](https://github.com/Alexey-Lukin/silken_net/wiki). Read those first.**
> This file is a thin pointer + a short trap cheat-sheet. **If anything here conflicts with `CLAUDE.md`, `CLAUDE.md` WINS** (it is the single maintained home; this file is kept thin on purpose so it cannot drift).

**SilkenNet** — planetary Bio-IoT D-MRV platform for forest monitoring (Ti-6Al-4V gyroid anchor + EBFC → STM32 Soldier → LoRa → Queen gateway → Rails 8.1 / Ruby 4.0.6 / PostgreSQL / Sidekiq → 12-chain Web3 Proof-of-Growth → SCC mint).

`CLAUDE.md` is short (orientation + routing): what-it-is §1 · **skill-routing table §2** (domain→skill→doc-home) · commands §3 · style/YAGNI §4 · critical invariants §5 (queues, AES, Lorenz/StatusByte) · gotchas §6 · repo-map §7 · Solidity/Foundry §8. Depth lives in the numbered `docs/NN_NN` (the skill routes you) + `docs/00_07` (open work / blockers).

---

## How Copilot is used here

Repo custom-instructions for Copilot Chat, PR review, and completions. For any non-trivial task, open `CLAUDE.md` (it's short) + the relevant `docs/NN_NN` first — completions alone won't carry the project's invariants. **Open work + active BLOCKERs live in `docs/00_07`** (don't mirror/guess them here); a BLOCKER = an active constraint until a real commit closes it (not a TODO/comment).

---

## Trap cheat-sheet (common wrong assumptions → home for the exact fact)

Not a restatement of facts (those live in `CLAUDE.md`) — just the traps + where to look:

- **LoRa crypto = AES-`128`-ECB** (NOT 256 — common stale assumption); CoAP = AES-256-CBC → `§5`.
- **Backend Lorenz = Float (IEEE 754 double)**, NOT BigDecimal (post-FW.7, bit-identical to firmware mruby) → `§6`.
- **StatusByte changed post-FW.29** = `[PanicFlag:1 | status:2 | growth_points:5]` (don't assume 6-bit GP) → `§5`. Ruby unpack: `"N n c C n C C a4"`.
- **`db/structure.sql`**, never `schema.rb`. Thin controllers — logic only in `app/services/` / `app/workers/`.
- **Sidekiq `:strict: true`** strict queue-drain order → `§5` (don't change a worker's queue without justification).
- **Partitioned models are THREE, and their One-Home helper DIFFERS** (`TelemetryLog` · `GatewayTelemetryLog` · `BlockchainTransaction`; exactly ONE — `GatewayTelemetryLog` — has no helper, deliberately) → always pass `created_at_iso`, but never guess the method — take it from `§6`. ⚠️ Corrected 2026-09-01: this mirror said FOUR / "two have none", both wrong, while `CLAUDE.md` and `.cursorrules` already carried the right numbers — a mirror drifting alone is exactly what this tier is prone to, so verify against `grep -rl 'self.primary_key = "id"' app/models/`, not against a sibling mirror.
- **AES keys never leave the Ruby process** (`HardwareKey#cached_binary_key`, in-process LRU; no Redis-serialize).
- **`oracle_status`** has a prefix → `oracle_status_fulfilled?` (NOT `fulfilled?`).
- **`TelemetryLog` has no AR validations** (KENOSIS) — checks only in `TelemetryUnpackerService.valid_sensor_data?`; don't add them back → `§6`.
- **Frontend = design-tokens only** (`bg-gaia-surface`…), `tokens(...)`, no DB in Phlex `initialize`, `focus-visible:` — take the boundary where raw palette is still legal from `§6` (it narrowed 2026-08-07; do not keep a copy here).
- **Minting guard-clauses** (oracle-гілка Path 1 + KYC бенефіціара на всіх шляхах) + `WEB3_STRICT_MODE`; Web3 logic only in service namespaces → `§6`.
- **TRL honesty:** anchor/EBFC = TRL 3 (in-silico ≠ TRL 4); don't overclaim → `§1`. Style: lazy-senior / YAGNI-first → `§4`.

---

## Pointers (don't duplicate — read the home)

- Sidekiq 9-queue strict order → `CLAUDE.md §5`.
- 12-chain Web3 topology + roles → `docs/05_01` + `web3-pipeline` skill.
- Where business logic lives (services/workers map) → `docs/04_02`.
- Solidity/Foundry conventions + invariant-gates (`test_pause_allowsSlash`, admin-last-guard, `totalSupply<=MAX`) → `CLAUDE.md §8`; contract spec → `docs/05_03`; test methodology → `docs/04_06 §B`.
- Open work / active blockers → `docs/00_07`.
- SSOT doc work / wiki-sync / doc-linters → skill `ssot-maintenance`.
