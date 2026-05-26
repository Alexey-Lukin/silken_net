---
name: models
description: "Skill for the Models area of silken_net. 196 symbols across 79 files."
---

# Models

196 symbols | 79 files | Cohesion: 78%

## When to Use

- Working with code in `app/`
- Understanding how Actuator, ActuatorCommand, AiInsight work
- Modifying models-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/models/cluster.rb` | Cluster, lorenz_overrides_for, numeric_or_nil, validate_lorenz_overrides_by_species, local_yesterday (+6) |
| `app/models/ews_alert.rb` | EwsAlert, broadcast_new_alert, broadcast_status_change, broadcast_alert_update, should_broadcast? (+6) |
| `app/controllers/api/v1/reports_controller.rb` | carbon_absorption, financial_summary, generate_carbon_csv_enum, generate_financial_csv_enum, generate_carbon_pdf (+2) |
| `app/models/system_parameter.rb` | current, current_values, typed_value, invalidate_cache, cache_key_for (+2) |
| `app/models/hardware_key.rb` | HardwareKey, owner, cached_binary_key, binary_previous_key, clear_grace_period! (+2) |
| `app/models/organization.rb` | Organization, cached_trees_count, total_clusters, total_invested, total_carbon_points (+1) |
| `app/models/actuator_command.rb` | expires_at_in_future, ActuatorCommand, expired?, dispatch_to_edge!, broadcast_prepend_to_activity_feed |
| `app/models/naas_contract.rb` | terminate_early!, NaasContract, check_cluster_health!, calculate_early_exit_fee, calculate_prorated_refund |
| `app/models/tiny_ml_model.rb` | record_prediction!, recalculate_drift_metrics!, TinyMlModel, firmware_compatible?, sanitize_version |
| `app/workers/unpack_telemetry_worker.rb` | perform, broadcast_to_matrix, broadcast_raw_hex, attempt_decryption, decrypt_aes |

## Entry Points

Start here when exploring this area:

- **`Actuator`** (Class) — `app/models/actuator.rb:2`
- **`ActuatorCommand`** (Class) — `app/models/actuator_command.rb:2`
- **`AiInsight`** (Class) — `app/models/ai_insight.rb:2`
- **`ApplicationRecord`** (Class) — `app/models/application_record.rb:0`
- **`AuditLog`** (Class) — `app/models/audit_log.rb:2`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `Actuator` | Class | `app/models/actuator.rb` | 2 |
| `ActuatorCommand` | Class | `app/models/actuator_command.rb` | 2 |
| `AiInsight` | Class | `app/models/ai_insight.rb` | 2 |
| `ApplicationRecord` | Class | `app/models/application_record.rb` | 0 |
| `AuditLog` | Class | `app/models/audit_log.rb` | 2 |
| `BioContractFirmware` | Class | `app/models/bio_contract_firmware.rb` | 4 |
| `BlockchainTransaction` | Class | `app/models/blockchain_transaction.rb` | 2 |
| `Cluster` | Class | `app/models/cluster.rb` | 2 |
| `Attunement` | Class | `app/models/codex/attunement.rb` | 12 |
| `Citation` | Class | `app/models/codex/citation.rb` | 12 |
| `Comment` | Class | `app/models/codex/comment.rb` | 15 |
| `Discovery` | Class | `app/models/codex/discovery.rb` | 14 |
| `DiscoveryRule` | Class | `app/models/codex/discovery_rule.rb` | 17 |
| `Fraction` | Class | `app/models/codex/fraction.rb` | 13 |
| `Match` | Class | `app/models/codex/match.rb` | 22 |
| `Node` | Class | `app/models/codex/node.rb` | 22 |
| `Realm` | Class | `app/models/codex/realm.rb` | 12 |
| `DeviceCalibration` | Class | `app/models/device_calibration.rb` | 2 |
| `EthereumAnchor` | Class | `app/models/ethereum_anchor.rb` | 6 |
| `EwsAlert` | Class | `app/models/ews_alert.rb` | 2 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `Perform → Cache_key_for` | cross_community | 9 |
| `Perform → Typed_value` | cross_community | 9 |
| `Show → Inline` | cross_community | 6 |
| `View_template → Inline` | cross_community | 6 |
| `View_template → Map` | cross_community | 6 |
| `View_template → Cache_key_for` | cross_community | 6 |
| `View_template → Typed_value` | cross_community | 6 |
| `View_template → Inline` | cross_community | 6 |
| `View_template → Map` | cross_community | 6 |
| `FlushQueue → Cache_key_for` | cross_community | 6 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Previews | 12 calls |
| V1 | 11 calls |
| Maintenance | 9 calls |
| Workers | 4 calls |
| Codex | 3 calls |
| Ed25519_crypto | 1 calls |
| Silken_net | 1 calls |
| Dclimate | 1 calls |

## How to Explore

1. `gitnexus_context({name: "Actuator"})` — see callers and callees
2. `gitnexus_query({query: "models"})` — find related execution flows
3. Read key files listed above for implementation details
