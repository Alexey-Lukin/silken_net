---
name: v1
description: "Skill for the V1 area of silken_net. 158 symbols across 62 files."
---

# V1

158 symbols | 62 files | Cohesion: 76%

## When to Use

- Working with code in `app/`
- Understanding how AccountSecurityController, ActuatorsController, AlertsController work
- Modifying v1-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/controllers/api/v1/maintenance_records_controller.rb` | index, new, parse_iso8601_filter, MaintenanceRecordsController, create (+5) |
| `app/controllers/api/v1/base_controller.rb` | render_dashboard, pagy_metadata, BaseController, render_auth_page, ensure_organization! (+4) |
| `app/controllers/api/v1/tree_families_controller.rb` | index, show, new, edit, TreeFamiliesController (+2) |
| `app/controllers/api/v1/contracts_controller.rb` | index, calculate_portfolio_health_for_scope, ContractsController, stats, calculate_portfolio_health (+1) |
| `app/controllers/api/v1/provisioning_controller.rb` | new, render_new_with_errors, ProvisioningController, register, build_device |
| `app/controllers/api/v1/telemetry_controller.rb` | live, TelemetryController, tree_history, gateway_history, clamp_history_days |
| `app/controllers/api/v1/sessions_controller.rb` | SessionsController, new, render_login_failure, omniauth_create, establish_session |
| `app/controllers/api/v1/actuators_controller.rb` | index, ActuatorsController, show, execute |
| `app/controllers/api/v1/codex/matches_controller.rb` | new, create, resolve_realm, MatchesController |
| `app/controllers/api/v1/firmwares_controller.rb` | index, new, FirmwaresController, create |

## Entry Points

Start here when exploring this area:

- **`AccountSecurityController`** (Class) — `app/controllers/api/v1/account_security_controller.rb:4`
- **`ActuatorsController`** (Class) — `app/controllers/api/v1/actuators_controller.rb:4`
- **`AlertsController`** (Class) — `app/controllers/api/v1/alerts_controller.rb:4`
- **`AuditLogsController`** (Class) — `app/controllers/api/v1/audit_logs_controller.rb:4`
- **`BaseController`** (Class) — `app/controllers/api/v1/base_controller.rb:4`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `AccountSecurityController` | Class | `app/controllers/api/v1/account_security_controller.rb` | 4 |
| `ActuatorsController` | Class | `app/controllers/api/v1/actuators_controller.rb` | 4 |
| `AlertsController` | Class | `app/controllers/api/v1/alerts_controller.rb` | 4 |
| `AuditLogsController` | Class | `app/controllers/api/v1/audit_logs_controller.rb` | 4 |
| `BaseController` | Class | `app/controllers/api/v1/base_controller.rb` | 4 |
| `BlockchainTransactionsController` | Class | `app/controllers/api/v1/blockchain_transactions_controller.rb` | 4 |
| `ClustersController` | Class | `app/controllers/api/v1/clusters_controller.rb` | 4 |
| `DiscoveryRulesController` | Class | `app/controllers/api/v1/codex/admin/discovery_rules_controller.rb` | 7 |
| `NodesController` | Class | `app/controllers/api/v1/codex/admin/nodes_controller.rb` | 17 |
| `AttunementsController` | Class | `app/controllers/api/v1/codex/attunements_controller.rb` | 11 |
| `CitationsController` | Class | `app/controllers/api/v1/codex/citations_controller.rb` | 20 |
| `CommentsController` | Class | `app/controllers/api/v1/codex/comments_controller.rb` | 9 |
| `DiscoveriesController` | Class | `app/controllers/api/v1/codex/discoveries_controller.rb` | 14 |
| `FractionsController` | Class | `app/controllers/api/v1/codex/fractions_controller.rb` | 14 |
| `LeaderboardController` | Class | `app/controllers/api/v1/codex/leaderboard_controller.rb` | 10 |
| `MatchesController` | Class | `app/controllers/api/v1/codex/matches_controller.rb` | 16 |
| `NodesController` | Class | `app/controllers/api/v1/codex/nodes_controller.rb` | 5 |
| `RealmsController` | Class | `app/controllers/api/v1/codex/realms_controller.rb` | 5 |
| `ContractsController` | Class | `app/controllers/api/v1/contracts_controller.rb` | 4 |
| `DashboardController` | Class | `app/controllers/api/v1/dashboard_controller.rb` | 4 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `View_template → Inline` | cross_community | 7 |
| `Perform → Inline` | cross_community | 7 |
| `View_template → Inline` | cross_community | 7 |
| `View_template → Inline` | cross_community | 7 |
| `View_template → Map` | cross_community | 7 |
| `Retire_carbon! → Inline` | cross_community | 7 |
| `Retire_carbon! → Map` | cross_community | 7 |
| `View_template → Map` | cross_community | 6 |
| `Perform → Inline` | cross_community | 6 |
| `Show → Inline` | cross_community | 6 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Previews | 45 calls |
| Maintenance | 23 calls |
| Models | 5 calls |
| Trees | 1 calls |
| Services | 1 calls |

## How to Explore

1. `gitnexus_context({name: "AccountSecurityController"})` — see callers and callees
2. `gitnexus_query({query: "v1"})` — find related execution flows
3. Read key files listed above for implementation details
