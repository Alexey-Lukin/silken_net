---
name: previews
description: "Skill for the Previews area of silken_net. 112 symbols across 42 files."
---

# Previews

112 symbols | 42 files | Cohesion: 54%

## When to Use

- Working with code in `spec/`
- Understanding how command_status, index, show work
- Modifying previews-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `spec/components/previews/skeleton_preview.rb` | default, text, card, stats, table (+2) |
| `spec/components/previews/wallet_transaction_row_preview.rb` | confirmed_carbon, pending_forest, failed, processing, interactive (+2) |
| `spec/components/previews/wallet_balance_display_preview.rb` | tree_wallet, locked_funds, organization_wallet, zero_balance, interactive (+1) |
| `spec/components/previews/iot_metric_value_preview.rb` | default, high_precision, nil_value, without_unit, interactive |
| `spec/components/previews/web3_address_preview.rb` | valid_address, short_address, nil_address, custom_fallback, interactive |
| `spec/components/previews/actuator_command_row_preview.rb` | confirmed_open, issued_activate, failed_close, interactive, mock_command |
| `spec/components/previews/cluster_item_preview.rb` | healthy, under_threat, low_health, interactive, mock_cluster |
| `app/views/components/actuators/index.rb` | view_template, header_section, stat_label, render_empty_state |
| `app/views/components/audit_logs/index.rb` | view_template, header_section, audit_table, render_log_row |
| `spec/components/previews/sidebar_preview.rb` | default, with_alerts, telemetry_active, interactive |

## Entry Points

Start here when exploring this area:

- **`command_status`** (Method) — `app/controllers/api/v1/actuators_controller.rb:114`
- **`index`** (Method) — `app/controllers/api/v1/codex/admin/discovery_rules_controller.rb:10`
- **`show`** (Method) — `app/controllers/api/v1/codex/admin/discovery_rules_controller.rb:17`
- **`update`** (Method) — `app/controllers/api/v1/codex/admin/discovery_rules_controller.rb:34`
- **`index`** (Method) — `app/controllers/api/v1/codex/admin/nodes_controller.rb:21`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `command_status` | Method | `app/controllers/api/v1/actuators_controller.rb` | 114 |
| `index` | Method | `app/controllers/api/v1/codex/admin/discovery_rules_controller.rb` | 10 |
| `show` | Method | `app/controllers/api/v1/codex/admin/discovery_rules_controller.rb` | 17 |
| `update` | Method | `app/controllers/api/v1/codex/admin/discovery_rules_controller.rb` | 34 |
| `index` | Method | `app/controllers/api/v1/codex/admin/nodes_controller.rb` | 21 |
| `show` | Method | `app/controllers/api/v1/codex/admin/nodes_controller.rb` | 30 |
| `update` | Method | `app/controllers/api/v1/codex/admin/nodes_controller.rb` | 49 |
| `inventory` | Method | `app/controllers/api/v1/firmwares_controller.rb` | 122 |
| `stream_config` | Method | `app/controllers/api/v1/oracle_visions_controller.rb` | 42 |
| `render` | Method | `app/services/codex/markdown_renderer.rb` | 29 |
| `view_template` | Method | `app/views/components/actuators/command_row.rb` | 8 |
| `view_template` | Method | `app/views/components/actuators/index.rb` | 11 |
| `header_section` | Method | `app/views/components/actuators/index.rb` | 34 |
| `stat_label` | Method | `app/views/components/actuators/index.rb` | 51 |
| `render_empty_state` | Method | `app/views/components/actuators/index.rb` | 58 |
| `view_template` | Method | `app/views/components/alerts/row.rb` | 16 |
| `render_codex_citations` | Method | `app/views/components/alerts/row.rb` | 50 |
| `view_template` | Method | `app/views/components/audit_logs/index.rb` | 9 |
| `header_section` | Method | `app/views/components/audit_logs/index.rb` | 22 |
| `audit_table` | Method | `app/views/components/audit_logs/index.rb` | 35 |

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
| Maintenance | 20 calls |
| V1 | 1 calls |
| Blockchain_transactions | 1 calls |
| Contracts | 1 calls |

## How to Explore

1. `gitnexus_context({name: "command_status"})` — see callers and callees
2. `gitnexus_query({query: "previews"})` — find related execution flows
3. Read key files listed above for implementation details
