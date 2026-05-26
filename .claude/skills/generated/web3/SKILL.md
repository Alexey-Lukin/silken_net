---
name: web3
description: "Skill for the Web3 area of silken_net. 40 symbols across 6 files."
---

# Web3

40 symbols | 6 files | Cohesion: 85%

## When to Use

- Working with code in `app/`
- Understanding how RequestError, CircuitOpenError, submit_chainlink_request work
- Modifying web3-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/services/web3/resilient_client.rb` | method_missing, provider_health, available_urls, provider_available?, circuit_open? (+8) |
| `app/services/web3/http_client.rb` | post, get, circuit_status, check_circuit!, record_failure (+6) |
| `app/services/web3/chainlink_router_version.rb` | active_version, entry_for, abi_for, selector_for, signature_for (+2) |
| `app/services/chainlink/oracle_dispatch_service.rb` | submit_chainlink_request, send_on_chain_request, pick_router_version, bytecode_check_enabled?, fetch_router_code (+1) |
| `app/services/streamr/broadcaster_service.rb` | broadcast!, publish_to_streamr |
| `app/workers/streamr_broadcast_worker.rb` | perform |

## Entry Points

Start here when exploring this area:

- **`RequestError`** (Class) — `app/services/web3/http_client.rb:45`
- **`CircuitOpenError`** (Class) — `app/services/web3/http_client.rb:49`
- **`submit_chainlink_request`** (Method) — `app/services/chainlink/oracle_dispatch_service.rb:65`
- **`send_on_chain_request`** (Method) — `app/services/chainlink/oracle_dispatch_service.rb:79`
- **`pick_router_version`** (Method) — `app/services/chainlink/oracle_dispatch_service.rb:128`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `RequestError` | Class | `app/services/web3/http_client.rb` | 45 |
| `CircuitOpenError` | Class | `app/services/web3/http_client.rb` | 49 |
| `submit_chainlink_request` | Method | `app/services/chainlink/oracle_dispatch_service.rb` | 65 |
| `send_on_chain_request` | Method | `app/services/chainlink/oracle_dispatch_service.rb` | 79 |
| `pick_router_version` | Method | `app/services/chainlink/oracle_dispatch_service.rb` | 128 |
| `bytecode_check_enabled?` | Method | `app/services/chainlink/oracle_dispatch_service.rb` | 156 |
| `fetch_router_code` | Method | `app/services/chainlink/oracle_dispatch_service.rb` | 171 |
| `functions_router_abi` | Method | `app/services/chainlink/oracle_dispatch_service.rb` | 186 |
| `active_version` | Method | `app/services/web3/chainlink_router_version.rb` | 76 |
| `entry_for` | Method | `app/services/web3/chainlink_router_version.rb` | 92 |
| `abi_for` | Method | `app/services/web3/chainlink_router_version.rb` | 99 |
| `selector_for` | Method | `app/services/web3/chainlink_router_version.rb` | 107 |
| `signature_for` | Method | `app/services/web3/chainlink_router_version.rb` | 111 |
| `fallback_for` | Method | `app/services/web3/chainlink_router_version.rb` | 119 |
| `selector_present_in_code?` | Method | `app/services/web3/chainlink_router_version.rb` | 135 |
| `method_missing` | Method | `app/services/web3/resilient_client.rb` | 50 |
| `provider_health` | Method | `app/services/web3/resilient_client.rb` | 82 |
| `available_urls` | Method | `app/services/web3/resilient_client.rb` | 98 |
| `provider_available?` | Method | `app/services/web3/resilient_client.rb` | 107 |
| `circuit_open?` | Method | `app/services/web3/resilient_client.rb` | 126 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `Perform → Cache_key_for` | cross_community | 9 |
| `Perform → Typed_value` | cross_community | 9 |
| `Perform → Circuit_open?` | cross_community | 8 |
| `Perform → Handle_response` | cross_community | 6 |
| `Perform → Record_success` | cross_community | 6 |
| `Mint_micro_reward! → Handle_response` | cross_community | 6 |
| `Mint_micro_reward! → Record_success` | cross_community | 6 |
| `FlushQueue → Cache_key_for` | cross_community | 6 |
| `FlushQueue → Typed_value` | cross_community | 6 |
| `Method_missing → Rate_limited?` | intra_community | 5 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Models | 5 calls |
| V1 | 1 calls |

## How to Explore

1. `gitnexus_context({name: "RequestError"})` — see callers and callees
2. `gitnexus_query({query: "web3"})` — find related execution flows
3. Read key files listed above for implementation details
