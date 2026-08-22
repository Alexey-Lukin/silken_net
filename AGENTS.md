# AGENTS.md — SilkenNet

> **SSOT = `CLAUDE.md` + `docs/` (`00_00`→`06_08`) + [Wiki](https://github.com/Alexey-Lukin/silken_net/wiki). Read those first.**
> This is the tool-agnostic agent guide (the open [AGENTS.md](https://agents.md) standard) — a **thin pointer**, not a second home. **If anything here conflicts with `CLAUDE.md`, `CLAUDE.md` WINS**: it is the single maintained home (prepended to every session), and this file is kept deliberately thin so it cannot drift. Cursor reads `.cursorrules`, Copilot reads `.github/copilot-instructions.md`, other agents read this — all three are pointers to the same home.

**SilkenNet** — planetary Bio-IoT D-MRV platform for forest monitoring: Ti-6Al-4V gyroid anchor + EBFC (~500 mV harvested from xylem, "zero-grid") → STM32 **"Soldier"** (sense → TinyML → Lorenz → encrypt → LoRa 868) → **"Queen"** gateway (CoAP) → Rails 8.1 / Ruby 4.0.6 / PostgreSQL / Sidekiq → 12-chain Web3 Proof-of-Growth → mint SCC. **Polyglot:** Ruby · firmware-C (STM32) · mruby · Solidity (Foundry) · Python (DFT/MD in-silico) · .NET C# (PicoGK CAD).

## Start here

`CLAUDE.md` is short (orientation + routing), and the fastest way in:

- **what-it-is** §1 · **skill-routing table** §2 (domain → skill → doc-home) · **environment/commands** §3 · **style / YAGNI ladder** §4 · **critical invariants** §5 (Sidekiq strict-priority queues, AES key-model, Lorenz/StatusByte) · **cross-domain gotchas** §6 · **repo-map** §7 · **Solidity/Foundry** §8.
- Depth lives in the numbered `docs/NN_NN_*.md` (the skills route you to the exact one); **open work + active blockers live in `docs/00_07`**.

## Working here (universal)

- **Minimal, in-scope changes.** Don't touch code outside the task. The best code is the code you don't write (YAGNI ladder — `CLAUDE.md` §4).
- **Don't trust stale statuses or counts** in any instruction file — verify against the LIVE code + `docs/`. A blocker in `docs/00_07` is an active constraint until a real commit closes it (never "resolved" via a TODO/comment).
- **Polyglot discipline:** firmware-C ≠ Rails-Ruby ≠ Solidity ≠ Python — distinct domains with distinct budgets (energy/RAM/Flash · gas · request-latency); don't carry assumptions between them.
- **Before editing a widely-used symbol,** trace its callers / blast-radius first (auth and money paths = highest risk); **before committing,** verify the diff scope matches intent, and don't rename by blind find-and-replace.
- **Honesty about hardware is load-bearing:** the platform ≠ the spec ideal (the clock drifts, the sensor lies, in-silico ≠ a physical TRL). Keep that honesty in code, comments, and docs.
- SSOT docs (`docs/NN_NN_*.md`), drift-hunts, and wiki-sync go through the `ssot-maintenance` skill; the exact gotchas per domain live in `CLAUDE.md` §6.
