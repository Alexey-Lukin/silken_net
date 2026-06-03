---
name: factory-flashing
description: "SEC.3 Factory Flashing pipeline — provision per-device keys into STM32/ATECC at manufacture. Read SSOT docs first."
---

# Factory Flashing (SEC.3)

Burns per-device keys into a Soldier/Queen at manufacture, then locks the chip (RDP).
Navigation aid — the **SSOT is the code + docs below**; this skill points, it does not restate.

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md` | §3.4 Factory Flashing threat model, HKDF per-device derivation, ATECC608B, RDP |
| `docs/00_07_Action_Plan_Tracker.md` | `SEC.3` (real `STM32_Programmer_CLI` on bench — residual), `SEC.2` (RDP Level 2), `FW.1` (HKDF) |
| `CLAUDE.md §9–§10, §12` | Security model, pre-flight (antenna before power), BLOCKER table (HW-AES-KEY → SEC.3) |

## Pipeline (entry → exit)

Entry: **`FactoryFlashing::Session.run`** (invoked by `lib/tasks/factory.rake` after a
`ProvisioningSession` is **supervisor-approved**). One `ActiveRecord::Base.transaction`:

1. **Preflight** — session `may_start?` + device exists + master key fetchable (fail fast before the tx).
2. **Master key** — `MasterKeySource` (Env or Bitwarden adapter); `WeakKeyDetector` refuses a weak key.
3. **HardwareKey** — `HardwareKeyService.provision` (the SINGLE HKDF source — same derivation the firmware runs; never derive keys elsewhere).
4. **ATECC (Гілка B + Tree only)** — `AteccProvisioner` emits the I²C ATCA write-zone transcript.
5. **Commands** — `CommandBuilder` emits the `STM32_Programmer_CLI` sequence.
6. **Execute** — `Executor` (dry-run prints; `--execute` spawns subprocesses).
7. **Audit** — `AuditTrail.record!` → chain-hashed `AuditLog` + `MaintenanceRecord`; `complete!` (or `fail_with!` + rollback).

## Key Components

| Component | Role |
|-----------|------|
| `factory_flashing/session.rb` | Orchestrator (`run`, `preflight!`, AASM start!/complete!/fail_with!) |
| `factory_flashing/command_builder.rb` | `STM32_Programmer_CLI` emission (`gilka_a_commands` / `gilka_b_commands`, `write_block`, `rdp_command`) |
| `factory_flashing/atecc_provisioner.rb` | ATECC608B data-zone provisioning (Гілка B) |
| `factory_flashing/executor.rb` | dry-run vs live subprocess (`programmer_available?`) |
| `factory_flashing/master_key_source.rb` | `Base` / `EnvAdapter` / `BitwardenAdapter` master-key fetch |
| `factory_flashing/audit_trail.rb` | chain-hashed audit log record |
| `ota_hmac_key_service.rb` | per-cluster OTA HMAC key (consumed by ATECC provisioning) |

> Line numbers drift every commit — `gitnexus_context({name: "Session"})` for live locations rather than a hardcoded table (`[[feedback_no_volatile_counts]]`).

## Gotchas Not Obvious From Code

1. **Гілка A vs Гілка B (ARCH.42 variants)** — A = keys written into **Protected Flash** via SWD (`-w32`); B = keys live in the **ATECC608B** secure element (no SWD key writes, only connect + RDP-lock + disconnect). Variant B is the decided production path (secure element + AES-128 LoRa).
2. **Flash layout MUST match firmware** — `CommandBuilder` addresses/magics mirror `firmware/soldier/main.c` `FLASH_KEY_ADDR` (post-ARCH.42): `KEYL`(0x4B45594C)+aes@`0x0803E000`, `LSED`(0x4C534544)+k_seed@`0x0803E014` (Tree), `KEYC`(0x4B455943)+coap@`0x0803E040` (Gateway). Drift here ⇒ device can't read its own key. Change one side → change both + host tests.
3. **Dry-run is the default; live is the SEC.3 residual** — real `STM32_Programmer_CLI` execution + **RDP Level 2** (`SEC.2`, irreversible chip lock) are bench-gated, not yet run on hardware.
4. **Key shapes** — Tree: 32-hex AES-128 LoRa key **+** 64-hex Lorenz `K_seed`; Gateway: 64-hex AES-256 CoAP key (LoRa slot intentionally unused). `CommandBuilder#validate!` enforces this.
5. **Transaction + chain-hash integrity** — the whole run is one AR transaction; a downstream raise rolls back HardwareKey + audit rows together, so rolled-back rows never enter the chain-hashed `AuditLog` (the chain stays intact).
6. **Supervisor gate** — `Session` refuses to run unless the `ProvisioningSession` is `supervisor_approved` (preflight `may_start?`).

## How to Explore

1. `gitnexus_context({name: "Session", repo: "silken_net"})` — orchestrator callers/callees
2. `gitnexus_query({query: "factory flashing", repo: "silken_net"})` — related execution flows
3. Read `command_builder.rb` for the exact CLI sequence; `03_05 §3.4` for the threat model
