---
name: workers
description: "Skill for the Workers area of silken_net. 57 symbols across 30 files."
---

# Workers

57 symbols | 30 files | Cohesion: 72%

## When to Use

- Working with code in `app/`
- Understanding how uses_etherisc?, call, blockchain_transaction_summary work
- Modifying workers-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/workers/application_web3_worker.rb` | within_rpc_limit, find_telemetry_log_with_pruning, with_web3_error_handling, log_web3_error, find_blockchain_tx_with_pruning |
| `app/workers/ota_transmission_worker.rb` | perform, fetch_firmware_record, broadcast_progress, handle_chunk_failure |
| `app/workers/actuator_command_worker.rb` | broadcast_command_state_static, perform, handle_failure, broadcast_command_state |
| `app/workers/gateway_telemetry_worker.rb` | perform, check_system_health, format_health_message, valid_gateway_stats? |
| `app/workers/puro_earth_passport_worker.rb` | perform, submit_to_puro_earth_api, build_passport_payload, compute_telemetry_hash |
| `app/workers/insurance_payout_worker.rb` | perform, satellite_verification_pending?, broadcast_insurance_update |
| `app/workers/mint_carbon_coin_worker.rb` | perform, process_telemetry_log, find_telemetry_log |
| `app/workers/alert_notification_worker.rb` | perform, broadcast_to_dashboards, notify_stakeholders |
| `app/views/components/dashboard/event_row.rb` | blockchain_transaction_summary, short_address |
| `spec/components/previews/dashboard_event_row_preview.rb` | blockchain_transaction, ews_alert |

## Entry Points

Start here when exploring this area:

- **`uses_etherisc?`** (Method) — `app/models/parametric_insurance.rb:22`
- **`call`** (Method) — `app/services/blockchain_minting_service.rb:58`
- **`blockchain_transaction_summary`** (Method) — `app/views/components/dashboard/event_row.rb:41`
- **`short_address`** (Method) — `app/views/components/dashboard/event_row.rb:50`
- **`perform`** (Method) — `app/workers/insurance_payout_worker.rb:9`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `uses_etherisc?` | Method | `app/models/parametric_insurance.rb` | 22 |
| `call` | Method | `app/services/blockchain_minting_service.rb` | 58 |
| `blockchain_transaction_summary` | Method | `app/views/components/dashboard/event_row.rb` | 41 |
| `short_address` | Method | `app/views/components/dashboard/event_row.rb` | 50 |
| `perform` | Method | `app/workers/insurance_payout_worker.rb` | 9 |
| `satellite_verification_pending?` | Method | `app/workers/insurance_payout_worker.rb` | 108 |
| `broadcast_insurance_update` | Method | `app/workers/insurance_payout_worker.rb` | 128 |
| `blockchain_transaction` | Method | `spec/components/previews/dashboard_event_row_preview.rb` | 14 |
| `prepare` | Method | `app/services/ota_packager_service.rb` | 36 |
| `coap_encrypt` | Method | `app/workers/concerns/coap_encryption.rb` | 51 |
| `wrap_with_time_sync` | Method | `app/workers/concerns/coap_encryption.rb` | 72 |
| `perform` | Method | `app/workers/ota_transmission_worker.rb` | 27 |
| `fetch_firmware_record` | Method | `app/workers/ota_transmission_worker.rb` | 101 |
| `broadcast_progress` | Method | `app/workers/ota_transmission_worker.rb` | 109 |
| `handle_chunk_failure` | Method | `app/workers/ota_transmission_worker.rb` | 126 |
| `within_rpc_limit` | Method | `app/workers/application_web3_worker.rb` | 97 |
| `find_telemetry_log_with_pruning` | Method | `app/workers/application_web3_worker.rb` | 108 |
| `perform` | Method | `app/workers/blockchain_confirmation_worker.rb` | 38 |
| `perform` | Method | `app/workers/mint_carbon_coin_worker.rb` | 36 |
| `process_telemetry_log` | Method | `app/workers/mint_carbon_coin_worker.rb` | 53 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `Perform → Inline` | cross_community | 6 |
| `Perform → Map` | cross_community | 6 |
| `Perform → Build_aad` | cross_community | 5 |
| `Perform → Circuit_failure_key` | cross_community | 5 |
| `Perform → Circuit_opened_at_key` | cross_community | 5 |
| `Perform → Cache_key_for` | cross_community | 5 |
| `Perform → Typed_value` | cross_community | 5 |
| `Perform → Build_aad` | cross_community | 5 |
| `Perform → Cache_key_for` | cross_community | 4 |
| `Perform → Typed_value` | cross_community | 4 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Models | 7 calls |
| Maintenance | 2 calls |
| Cluster_457 | 2 calls |
| Concerns | 2 calls |
| Previews | 2 calls |
| Chainlink | 1 calls |
| Dclimate | 1 calls |
| Codex | 1 calls |

## How to Explore

1. `gitnexus_context({name: "uses_etherisc?"})` — see callers and callees
2. `gitnexus_query({query: "workers"})` — find related execution flows
3. Read key files listed above for implementation details
