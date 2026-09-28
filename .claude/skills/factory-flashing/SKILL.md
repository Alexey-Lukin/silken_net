---
name: factory-flashing
description: "Use when working on the SEC.3 factory-flashing pipeline — provisioning per-device keys into an STM32 at manufacture (app/services/factory_flashing/, lib/tasks/factory.rake): the one-pass silicon UID→DID derivation [FW.54], the wrong-board guard, UID collision → quarantine, the six Flash key blocks and their magics, word→big-endian byte order [FW.30], the chain-hashed audit trail, and the 2-Person supervisor rule. ⚠️ Гілка B = Гілка A + SE identity: its runtime keys go to Protected Flash through the same SWD writes (since 2026-09-27 — before that a Гілка-B unit got no Flash KEYL and bricked), but the SE step itself is EMIT-ONLY — textual legacy ATECC calls, no real transport — so treat any SE05x request as blocked, not supported. Routes to 03_06 §5 + 03_01 §7, does not restate. Examples: \"why did factory:flash raise CollisionError\", \"add a key slot\", \"the backend DID does not match the silicon\", \"provision a new board\", \"what does the flashing session do, in order\", \"why is Гілка B not usable\"."
---

# Factory Flashing (SEC.3)

Burns per-device keys into a Soldier/Queen at manufacture, then locks the chip (RDP).
Navigation aid — the **SSOT is the code + docs below**; this skill points, it does not restate.

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `docs/03_06_Factory_Flashing_and_Key_Provisioning.md` | THE factory home (split from 03_05 §3.4): pipeline Гілки A/B, HKDF per-device derivation, K_ota, §5 ops-security (2-Person Rule, master-key delivery variants, SEC.3 status) |
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md` | Crypto modes, SE050 (SEC.6), key rotation, RDP (SEC.2) |
| `docs/00_07_Action_Plan_Tracker.md` | `SEC.3` (bench SWD + Bitwarden live — residuals), `SEC.2` (RDP Level 2) |

## Pipeline (entry → exit)

Entry: **`lib/tasks/factory.rake`** → **[FW.54] one-pass UID→DID at `factory:flash`**:
for a Tree the `device_uid` arg = **24-hex silicon UID** (NOT a DID) →
`SilkenNet::DidDerivation.wire_did_from_uid_hex` → `TreeResolver.resolve!`
(create with `CLUSTER_ID`+`TREE_FAMILY_ID` env / re-flash / bind legacy /
DID-collision → `CollisionError` = **quarantine**, `03_01 §7`); the session's
`device_uid` = derived wire-DID. Bare `SNET-` DID accepted only for a Tree
that already has `trees.silicon_uid_hex`; Gateway path unchanged.

Then **`FactoryFlashing::Session.run`** (after **supervisor-approved**). One `ActiveRecord::Base.transaction`:

1. **Preflight** — session `may_start?` + device exists + a live `rdp_level` 2 needs `RDP_L2_ACK=<device_uid>` (SEC.2: L2 is permanent; the raw-byte map is `CommandBuilder::RDP_OPTION_BYTE`, `03_05 §3.6`) + master key fetched into `@master_key` (fail fast before the tx; the result is NOT discarded — SEC.3 DI).
2. **Wrong-board guard [FW.54]** — `CommandBuilder.preflight_commands` (one invocation: `-c` + `-r32 0x1FFF7590 12`) runs FIRST; live mode parses stdout via `UidReadout` and compares the board's UID to `trees.silicon_uid_hex` **before any derivation or `-w32`** — mismatch/unparseable → `WrongBoardError` (not even a HardwareKey row materializes). dry-run or passport-less device → skip.
3. **Master key** — `MasterKeySource` (Env or Bitwarden adapter); `WeakKeyDetector` refuses a weak key. The fetched key threads as `master_key:` param into every derivation below (runtime callers of the same services use the ENV fallback instead).
4. **HardwareKey** — `HardwareKeyService.provision(device, master_key:)` (the SINGLE HKDF source — same derivation the firmware runs; never derive keys elsewhere).
5. **ATECC (Гілка B + Tree only)** — `SecureElementProvisioner` emits the I²C ATCA write-zone transcript.
6. **Commands** — `CommandBuilder#flash_commands` (key-page erase + key writes as whole doublewords + IWDG freeze [SEC.15] + RDP; the UID-read already ran as preflight — gotcha #11). ⛔ One run = keys → IWDG → RDP, so a live `RDP_LEVEL=2` run skips the self-test and WRP that the ratified burn order puts between keys and L2 — production runs the pipeline at `RDP_LEVEL=0`, then the `03_05 §3.6` steps (NOT at L1: on L1 a failed self-test board cannot be reflashed without an L0 regression, i.e. a mass erase). WRP is per chip — the Queen's page 125 is her runtime OTA-SHA mirror, so only page 124 there.
7. **Execute** — `Executor` (dry-run prints; `--execute` spawns subprocesses).
8. **Audit** — `AuditTrail.record!` → chain-hashed `AuditLog` (metadata incl. `silicon_uid_hex`) + `MaintenanceRecord`; `complete!` (or `fail_with!` + rollback).

## Key Components

| Component | Role |
|-----------|------|
| `app/services/factory_flashing/session.rb` | Orchestrator (`run`, `preflight!`, `verify_silicon_uid!` wrong-board guard, AASM start!/complete!/fail_with!) |
| `app/services/factory_flashing/tree_resolver.rb` | [FW.54] UID→DID→Tree: create / re-flash / bind / collision→quarantine; deliberately does NOT enqueue peaq (offline factory) |
| `app/services/factory_flashing/uid_readout.rb` | [FW.54] tolerant `-r32` stdout parser (keyed on `1FFF7590`); live format = bench-confirm (RUNBOOK 1.3) |
| `app/services/factory_flashing/command_builder.rb` | `STM32_Programmer_CLI` emission (`preflight_commands` class-method: `-c`+UID-read in one invocation; `flash_commands` per гілка, `block_words` → `flash_write_commands` (page erase + whole doublewords), `rdp_command`) |
| `app/services/factory_flashing/secure_element_provisioner.rb` | ATECC608B data-zone provisioning (Гілка B) |
| `app/services/factory_flashing/executor.rb` | dry-run vs live subprocess (`programmer_available?`) |
| `app/services/factory_flashing/master_key_source.rb` | `Base` / `EnvAdapter` / `BitwardenAdapter` master-key fetch — the fetched key feeds HKDF via `Session` (SEC.3 DI), not just the preflight gate |
| `app/services/factory_flashing/audit_trail.rb` | chain-hashed audit log record |
| `ota_hmac_key_service.rb` | per-cluster OTA HMAC key `fetch_for(cluster_id, master_key: nil)` (KOTA block in BOTH branches + the Гілка-B SE Slot-3 copy) |

> Line numbers drift every commit — grep/read `Session` for live locations rather than a hardcoded table (`[[feedback_no_volatile_counts]]`).

## Gotchas Not Obvious From Code

1. **Гілка A vs Гілка B (ARCH.42 variants, post-SEC.14 2026-07-03)** — A = keys written into **Protected Flash** via SWD (`-w32`). B = **Гілка A + SE05x identity-chip**: `CommandBuilder#flash_commands` emits the SAME `protected_flash_commands` for both branches (KEYL · LSED · KOTA · KEYB for a Tree; KEYL=KEYB-value · KEYC · EDSK for a Queen), because every runtime key has an MCU consumer (CRYP · Lorenz-VM · OTA-HMAC); the SE adds only the Ed25519 voice / cert / anti-clone serial (+ a Slot-3 K_ota copy for the open post-TRL-7 migration), **NOT** the LoRa key — Slot 0 is reserved and never written (⚖️ delegated 2026-09-27; verdict, price and weakest link — `03_06 §1`, callout «Набір ключів Гілки B»). 🔴 Until 2026-09-27 `gilka_b_commands` skipped every key write (legacy ATECC model): a Гілка-B Soldier had **no Flash KEYL → brick**, and a Гілка-B Queen had neither KEYC nor EDSK. ⛔ Do not read «Гілка B» as «keys live in the SE»: its runtime keys are protected by RDP exactly like Гілка A's (SEC.2/SEC.24) — the SE's non-extractability covers identity only.
2. **Flash layout MUST match firmware** — `CommandBuilder` addresses/magics mirror `firmware/soldier/main.c` `FLASH_KEY_ADDR` (post-ARCH.42): `KEYL`(0x4B45594C)+aes@`0x0803E000`, `LSED`(0x4C534544)+k_seed@`0x0803E014` (Tree), `KEYC`(0x4B455943)+coap@`0x0803E040`, `EDSK`(0x4544534B)+ed25519_seed@`0x0803E064` (Gateway, L1 QATT), `KOTA`(0x4B4F5441)+k_ota@`0x0803E800` (Tree, FW.23), `KEYB`(0x4B455942)+bcast@`0x0803E828` (Tree, FW.2 (в) cluster control-plane). Drift here ⇒ device can't read its own key. Change one side → change both + host tests. Word→BE-bytes convention (FW.30): firmware unpacks each `-w32` word MSB-first — naive memcpy on LE Cortex-M4 reverses every word.
3. **Dry-run is the default; live is the SEC.3 residual** — real `STM32_Programmer_CLI` execution + **RDP Level 2** (`SEC.2`, irreversible chip lock) are bench-gated, not yet run on hardware.
4. **Key shapes** — Tree: 32-hex AES-128 LoRa key **+** 64-hex Lorenz `K_seed`; Gateway: 64-hex AES-256 CoAP key **+** 32-hex broadcast key written to the LoRa `KEYL` slot (FW.2 (в), post-2026-07-03 — Queen's single control-plane key = the `KEYB` broadcast value; the pre-fix «LoRa slot unused» bricked her at boot) **+** optional 64-hex Ed25519 seed (L1 QATT «голос Королеви» — generated by `Session` on the factory host, NOT HKDF; only the pubkey persists in `HardwareKey`). `CommandBuilder#validate!` enforces this.
5. **Transaction + chain-hash integrity** — the whole run is one AR transaction; a downstream raise rolls back HardwareKey + audit rows together, so rolled-back rows never enter the chain-hashed `AuditLog` (the chain stays intact).
6. **Supervisor gate** — `Session` refuses to run unless the `ProvisioningSession` is `supervisor_approved` (preflight `may_start?`).
7. **Never add WeakKeyDetector to the ENV-fallback branch** of the derivation services — the rails_helper test pin (`silken-net-test-master-key-32b!!`) is itself a placeholder *needle* in the detector, so validating inside `hkdf_derive`/`fetch_for`/`derive_seed` fails the whole suite. Coverage is already two-layer by design: `EnvAdapter` guards the factory path, the boot initializer (`master_key_strength_check.rb`) guards runtime.
8. **[FW.54] UID wire-form is frozen** — 24 hex = three `%08X` words in register order (`0x1FFF7590` first), exactly how firmware `did_derive.h` reads them; golden pair `0039002F3138511538323634 → SNET-80B12004` frozen in `did_derivation_spec` ↔ `firmware/test/test_soldier_logic.c`. Reordering/re-endianing the parse = a different DID on backend vs silicon (keys diverge silently).
9. **DID is derived EVERYWHERE by one function** — `wire_did_from_uid_hex` feeds both the factory (`TreeResolver`) and the field `ProvisioningController#register` (the old `last(8)`-suffix DID + the dead tree double-init guard were a real prod bug, fixed 2026-07-03). Never invent a third derivation path.
10. **Collision ≠ re-flash** — same derived DID + different `silicon_uid_hex` = birthday collision or wrong chip → `CollisionError`, unit goes to quarantine (`03_01 §7`); same UID = legit re-flash (idempotent no-op). ⚠️ The no-op is the RESOLVER's only: `ensure_hardware_key` reuses the existing `HardwareKey` row, so a re-flash writes the SAME key — it is not compromise recovery for any tree (HKDF from the master is deterministic), and for a ratchet-rotated tree it writes K_v where the firmware expects the root K0 (deaf node or a desync on the next `0x9E`) → `03_05 §3.8`, `00_07` FW.17.

11. **Every transcript line is its own CLI process, and WL Flash takes only whole erased doublewords [SEC.3, 2026-09-28]** — `STM32_Programmer_CLI` holds SWD only within one invocation, so `CommandBuilder::CONNECT` prefixes EVERY line (a «disconnect» line does not exist); `-w32` neither erases nor splits a doubleword (STM32CubeProgrammer manual, `-w32` note; WL = 64 bits + ECC), so `flash_write_commands` erases the touched pages first and writes each touched doubleword exactly once, padding with `0xFFFFFFFF`. 🔴 Before 2026-09-28 only the KOTA|KEYB boundary was aligned (+40) — magic + key word and the KEYL|LSED boundary still shared doublewords across commands, and the execute-path shim stayed green because it accepts any args: a shim proves orchestration, not CLI semantics. Adding a key block → the three pins «форма запису Flash WL» in `command_builder_spec` judge it; a runtime-written page (the Queen's 125 = OTA-SHA, FW.52) must never enter the erase set. `Executor.redact` keeps `-w32` data out of `error_message`, which `Session` persists.

## How to Explore

1. grep/read `Session` — orchestrator callers/callees
2. grep `factory flashing` across `app/services/` — related flows
3. Read `command_builder.rb` for the exact CLI sequence; `03_06 §5` for the threat model
