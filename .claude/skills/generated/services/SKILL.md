---
name: services
description: "Skill for the Services area of silken_net. 107 symbols across 33 files."
---

# Services

107 symbols | 33 files | Cohesion: 78%

## When to Use

- Working with code in `app/`
- Understanding how ApplicationService, BlockchainBurningService, BlockchainMintingService work
- Modifying services-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/services/blockchain_minting_service.rb` | BlockchainMintingService, perform, process_token_group, build_batch_arrays, identifier_for (+11) |
| `app/services/insight_generator_service.rb` | InsightGeneratorService, generate_for_tree, detect_fraud?, calculate_deviation, calculate_stress_index (+11) |
| `app/services/telemetry_unpacker_service.rb` | TelemetryUnpackerService, commit_telemetry, check_firmware_mismatch!, process_chunk, valid_sensor_data? (+9) |
| `app/services/minting_rollback_service.rb` | MintingRollbackService, fetch_transaction_receipt, fetch_evm_transaction_receipt, classify_evm_receipt, fetch_solana_transaction_status (+5) |
| `app/services/ota_packager_service.rb` | generate_manifest, generate_packages, hmac_enabled?, compute_hmac_tag, build_hmac_trailer_chunks (+1) |
| `app/services/hardware_key_service.rb` | derive_key_for, derive_lora_key, derive_iotex_seed, derive_device_key, hkdf_derive |
| `app/services/blockchain_burning_service.rb` | BlockchainBurningService, perform, create_audit_transaction, handle_slashing_failure |
| `app/services/contract_health_check_service.rb` | ContractHealthCheckService, perform, activate_slashing_protocol! |
| `app/models/wallet.rb` | credit!, should_broadcast?, release_locked_funds! |
| `app/services/alert_dispatch_service.rb` | analyze_and_trigger!, create_and_dispatch_alert!, create_fraud_alert! |

## Entry Points

Start here when exploring this area:

- **`ApplicationService`** (Class) — `app/services/application_service.rb:23`
- **`BlockchainBurningService`** (Class) — `app/services/blockchain_burning_service.rb:4`
- **`BlockchainMintingService`** (Class) — `app/services/blockchain_minting_service.rb:5`
- **`ChainAuditService`** (Class) — `app/services/chain_audit_service.rb:4`
- **`ContractHealthCheckService`** (Class) — `app/services/contract_health_check_service.rb:14`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `ApplicationService` | Class | `app/services/application_service.rb` | 23 |
| `BlockchainBurningService` | Class | `app/services/blockchain_burning_service.rb` | 4 |
| `BlockchainMintingService` | Class | `app/services/blockchain_minting_service.rb` | 5 |
| `ChainAuditService` | Class | `app/services/chain_audit_service.rb` | 4 |
| `ContractHealthCheckService` | Class | `app/services/contract_health_check_service.rb` | 14 |
| `ContractTerminationService` | Class | `app/services/contract_termination_service.rb` | 16 |
| `InsightGeneratorService` | Class | `app/services/insight_generator_service.rb` | 2 |
| `MintingRollbackService` | Class | `app/services/minting_rollback_service.rb` | 24 |
| `EntropyCalculatorService` | Class | `app/services/silken_net/entropy_calculator_service.rb` | 27 |
| `TelemetryUnpackerService` | Class | `app/services/telemetry_unpacker_service.rb` | 2 |
| `BridgeService` | Class | `app/services/toucan/bridge_service.rb` | 16 |
| `MintBatchCollectorService` | Class | `app/services/treasury/mint_batch_collector_service.rb` | 19 |
| `MonitorService` | Class | `app/services/treasury/monitor_service.rb` | 22 |
| `TreeChronicleService` | Class | `app/services/tree_chronicle_service.rb` | 19 |
| `weighted_growth_points` | Method | `app/models/tree_family.rb` | 101 |
| `credit!` | Method | `app/models/wallet.rb` | 85 |
| `should_broadcast?` | Method | `app/models/wallet.rb` | 189 |
| `analyze_and_trigger!` | Method | `app/services/alert_dispatch_service.rb` | 15 |
| `create_and_dispatch_alert!` | Method | `app/services/alert_dispatch_service.rb` | 124 |
| `homeostatic?` | Method | `app/services/silken_net/attractor.rb` | 67 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `Perform → Inline` | cross_community | 7 |
| `Register → Hkdf_derive` | cross_community | 5 |
| `Perform → Build_aad` | cross_community | 5 |
| `Perform → Validate_inputs!` | cross_community | 4 |
| `Perform → Calculate_deviation` | cross_community | 4 |
| `Perform → Calculate_stress_index_heuristic` | cross_community | 4 |
| `Perform → Set` | cross_community | 3 |
| `Perform → Binary_key` | cross_community | 3 |
| `Perform → Frame_counter_replayed?` | cross_community | 3 |
| `Perform → Normalize_voltage` | cross_community | 3 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Models | 9 calls |
| Maintenance | 3 calls |
| Silken_net | 2 calls |
| Celo | 1 calls |
| Workers | 1 calls |
| Ed25519_crypto | 1 calls |
| Treasury | 1 calls |
| Web3 | 1 calls |

## How to Explore

1. `gitnexus_context({name: "ApplicationService"})` — see callers and callees
2. `gitnexus_query({query: "services"})` — find related execution flows
3. Read key files listed above for implementation details
