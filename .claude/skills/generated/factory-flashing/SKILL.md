---
name: factory-flashing
description: "Skill for the Factory_flashing area of silken_net. 30 symbols across 7 files."
---

# Factory_flashing

30 symbols | 7 files | Cohesion: 91%

## When to Use

- Working with code in `app/`
- Understanding how Base, EnvAdapter, BitwardenAdapter work
- Modifying factory_flashing-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/services/factory_flashing/session.rb` | run, run, preflight!, build_commands, capture_failure (+3) |
| `app/services/factory_flashing/command_builder.rb` | gilka_a_commands, gilka_b_commands, write_block, rdp_command, initialize (+1) |
| `app/services/factory_flashing/executor.rb` | dry_run?, run, execute_single, ensure_programmer_available!, programmer_available? |
| `app/services/factory_flashing/atecc_provisioner.rb` | provision, initialize, validate_lengths!, emit_statements, wrap |
| `app/services/factory_flashing/master_key_source.rb` | Base, EnvAdapter, BitwardenAdapter |
| `app/services/ota_hmac_key_service.rb` | fetch_for, fetch_binary_for |
| `app/services/factory_flashing/audit_trail.rb` | record! |

## Entry Points

Start here when exploring this area:

- **`Base`** (Class) — `app/services/factory_flashing/master_key_source.rb:25`
- **`EnvAdapter`** (Class) — `app/services/factory_flashing/master_key_source.rb:33`
- **`BitwardenAdapter`** (Class) — `app/services/factory_flashing/master_key_source.rb:47`
- **`record!`** (Method) — `app/services/factory_flashing/audit_trail.rb:37`
- **`run`** (Method) — `app/services/factory_flashing/session.rb:31`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `Base` | Class | `app/services/factory_flashing/master_key_source.rb` | 25 |
| `EnvAdapter` | Class | `app/services/factory_flashing/master_key_source.rb` | 33 |
| `BitwardenAdapter` | Class | `app/services/factory_flashing/master_key_source.rb` | 47 |
| `record!` | Method | `app/services/factory_flashing/audit_trail.rb` | 37 |
| `run` | Method | `app/services/factory_flashing/session.rb` | 31 |
| `run` | Method | `app/services/factory_flashing/session.rb` | 47 |
| `preflight!` | Method | `app/services/factory_flashing/session.rb` | 80 |
| `build_commands` | Method | `app/services/factory_flashing/session.rb` | 102 |
| `capture_failure` | Method | `app/services/factory_flashing/session.rb` | 123 |
| `dry_run?` | Method | `app/services/factory_flashing/executor.rb` | 29 |
| `run` | Method | `app/services/factory_flashing/executor.rb` | 34 |
| `execute_single` | Method | `app/services/factory_flashing/executor.rb` | 42 |
| `ensure_programmer_available!` | Method | `app/services/factory_flashing/executor.rb` | 57 |
| `programmer_available?` | Method | `app/services/factory_flashing/executor.rb` | 68 |
| `provision` | Method | `app/services/factory_flashing/atecc_provisioner.rb` | 49 |
| `run_atecc_if_needed` | Method | `app/services/factory_flashing/session.rb` | 111 |
| `fetch_for` | Method | `app/services/ota_hmac_key_service.rb` | 36 |
| `fetch_binary_for` | Method | `app/services/ota_hmac_key_service.rb` | 61 |
| `gilka_a_commands` | Method | `app/services/factory_flashing/command_builder.rb` | 59 |
| `gilka_b_commands` | Method | `app/services/factory_flashing/command_builder.rb` | 79 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `Run → Fetch_for` | cross_community | 3 |
| `Run → Provision` | cross_community | 3 |
| `Run → Commands` | cross_community | 3 |
| `Run → Programmer_available?` | intra_community | 3 |

## Connected Areas

| Area | Connections |
|------|-------------|
| V1 | 2 calls |

## How to Explore

1. `gitnexus_context({name: "Base"})` — see callers and callees
2. `gitnexus_query({query: "factory_flashing"})` — find related execution flows
3. Read key files listed above for implementation details
