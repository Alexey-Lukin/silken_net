---
name: maintenance
description: "Skill for the Maintenance area of silken_net. 198 symbols across 69 files."
---

# Maintenance

198 symbols | 69 files | Cohesion: 54%

## When to Use

- Working with code in `app/`
- Understanding how toggle_mfa, unlink_identity, unlock_identity work
- Modifying maintenance-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/views/components/maintenance/show.rb` | view_template, render_header, render_evidence_gallery, render_no_photos_placeholder, render_notes_panel (+9) |
| `app/views/components/gateways/show.rb` | view_template, render_status_header, render_technical_matrix, render_soldier_fleet_overview, render_network_config (+4) |
| `app/views/components/settings/show.rb` | view_template, header_section, render_settings_form, render_field, render_logo_field (+3) |
| `app/views/components/audit_logs/show.rb` | view_template, render_header, render_details_table, detail_row, render_metadata_panel (+2) |
| `app/controllers/api/v1/base_controller.rb` | render_unauthorized, render_forbidden, render_forbidden_pundit, render_not_found, render_parameter_missing (+1) |
| `app/views/components/maintenance/index.rb` | view_template, header_section, filter_bar, records_table, render_row (+1) |
| `app/views/components/notifications/settings.rb` | view_template, header_section, render_channels_form, render_field, render_channels_status (+1) |
| `app/views/components/codex/discoveries/list.rb` | view_template, render_header, render_empty, render_grid, render_card |
| `app/views/components/contracts/show.rb` | view_template, render_hero_section, render_emission_ledger, render_legal_vault, term_row |
| `app/views/components/gateways/item.rb` | view_template, header_section, stats_section, stat_block, footer_section |

## Entry Points

Start here when exploring this area:

- **`toggle_mfa`** (Method) — `app/controllers/api/v1/account_security_controller.rb:40`
- **`unlink_identity`** (Method) — `app/controllers/api/v1/account_security_controller.rb:73`
- **`unlock_identity`** (Method) — `app/controllers/api/v1/account_security_controller.rb:107`
- **`change_password`** (Method) — `app/controllers/api/v1/account_security_controller.rb:119`
- **`render_unauthorized`** (Method) — `app/controllers/api/v1/base_controller.rb:149`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `toggle_mfa` | Method | `app/controllers/api/v1/account_security_controller.rb` | 40 |
| `unlink_identity` | Method | `app/controllers/api/v1/account_security_controller.rb` | 73 |
| `unlock_identity` | Method | `app/controllers/api/v1/account_security_controller.rb` | 107 |
| `change_password` | Method | `app/controllers/api/v1/account_security_controller.rb` | 119 |
| `render_unauthorized` | Method | `app/controllers/api/v1/base_controller.rb` | 149 |
| `render_forbidden` | Method | `app/controllers/api/v1/base_controller.rb` | 153 |
| `render_forbidden_pundit` | Method | `app/controllers/api/v1/base_controller.rb` | 157 |
| `render_not_found` | Method | `app/controllers/api/v1/base_controller.rb` | 161 |
| `render_parameter_missing` | Method | `app/controllers/api/v1/base_controller.rb` | 165 |
| `render_internal_server_error` | Method | `app/controllers/api/v1/base_controller.rb` | 173 |
| `deploy` | Method | `app/controllers/api/v1/firmwares_controller.rb` | 136 |
| `update` | Method | `app/controllers/api/v1/locales_controller.rb` | 13 |
| `redirect_back_or_to` | Method | `app/controllers/api/v1/locales_controller.rb` | 38 |
| `destroy` | Method | `app/controllers/api/v1/maintenance_record_photos_controller.rb` | 11 |
| `authorize_record_mutation!` | Method | `app/controllers/api/v1/maintenance_records_controller.rb` | 201 |
| `create` | Method | `app/controllers/api/v1/passwords_controller.rb` | 26 |
| `create` | Method | `app/controllers/api/v1/sessions_controller.rb` | 21 |
| `destroy` | Method | `app/controllers/api/v1/sessions_controller.rb` | 65 |
| `render_api_login_success` | Method | `app/controllers/api/v1/sessions_controller.rb` | 103 |
| `gateway_uplink` | Method | `app/controllers/api/v1/telemetry_controller.rb` | 65 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `View_template → Inline` | cross_community | 7 |
| `View_template → Inline` | cross_community | 6 |
| `View_template → Map` | cross_community | 6 |
| `View_template → Map` | cross_community | 6 |
| `View_template → Inline` | cross_community | 6 |
| `View_template → Map` | cross_community | 6 |
| `View_template → Merger` | cross_community | 6 |
| `View_template → Inline` | cross_community | 6 |
| `View_template → Map` | cross_community | 6 |
| `View_template → Inline` | cross_community | 6 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Previews | 20 calls |
| Fractions | 20 calls |
| Models | 4 calls |
| V1 | 2 calls |
| Clusters | 1 calls |
| Services | 1 calls |

## How to Explore

1. grep/read `toggle_mfa` — see callers and callees
2. grep `maintenance` across `app/` — find related flows
3. Read key files listed above for implementation details
