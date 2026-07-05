---
name: fractions
description: "Skill for the Fractions area of silken_net. 46 symbols across 29 files."
---

# Fractions

46 symbols | 29 files | Cohesion: 57%

## When to Use

- Working with code in `app/`
- Understanding how hidden?, show?, view_template work
- Modifying fractions-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/views/components/codex/fractions/picker.rb` | view_template, render_header, render_realm_tabs, realm_tab_classes, render_grid (+2) |
| `app/views/components/codex/battle/arena.rb` | view_template, render_header, render_error |
| `app/views/components/codex/fractions/card.rb` | view_template, render_filled, render_empty |
| `app/views/components/alerts/row.rb` | severity_badge, row_classes |
| `app/views/components/application_component.rb` | tokens, merger |
| `app/views/components/codex/leaderboard/table.rb` | view_template, render_header |
| `app/views/components/codex/realm_tabs.rb` | view_template, render_tab |
| `app/views/components/gateways/show.rb` | connection_led_classes, battery_color |
| `app/views/shared/ui/data_table.rb` | view_template, render_thead |
| `app/views/shared/ui/mobile_nav_toggle.rb` | view_template, burger_icon |

## Entry Points

Start here when exploring this area:

- **`hidden?`** (Method) — `app/models/codex/comment.rb:48`
- **`show?`** (Method) — `app/policies/codex/comment_policy.rb:11`
- **`view_template`** (Method) — `app/views/components/actuators/command_status_badge.rb:16`
- **`view_template`** (Method) — `app/views/components/alerts/badge.rb:20`
- **`severity_badge`** (Method) — `app/views/components/alerts/row.rb:60`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `hidden?` | Method | `app/models/codex/comment.rb` | 48 |
| `show?` | Method | `app/policies/codex/comment_policy.rb` | 11 |
| `view_template` | Method | `app/views/components/actuators/command_status_badge.rb` | 16 |
| `view_template` | Method | `app/views/components/alerts/badge.rb` | 20 |
| `severity_badge` | Method | `app/views/components/alerts/row.rb` | 60 |
| `row_classes` | Method | `app/views/components/alerts/row.rb` | 92 |
| `tokens` | Method | `app/views/components/application_component.rb` | 44 |
| `merger` | Method | `app/views/components/application_component.rb` | 51 |
| `view_template` | Method | `app/views/components/codex/attunements/toggle.rb` | 16 |
| `view_template` | Method | `app/views/components/codex/battle/arena.rb` | 23 |
| `render_header` | Method | `app/views/components/codex/battle/arena.rb` | 39 |
| `render_error` | Method | `app/views/components/codex/battle/arena.rb` | 49 |
| `view_template` | Method | `app/views/components/codex/comments/form.rb` | 12 |
| `view_template` | Method | `app/views/components/codex/comments/item.rb` | 11 |
| `view_template` | Method | `app/views/components/codex/fractions/card.rb` | 13 |
| `render_filled` | Method | `app/views/components/codex/fractions/card.rb` | 31 |
| `render_empty` | Method | `app/views/components/codex/fractions/card.rb` | 59 |
| `render_open` | Method | `app/views/components/codex/fractions/cooldown.rb` | 29 |
| `view_template` | Method | `app/views/components/codex/fractions/picker.rb` | 16 |
| `render_header` | Method | `app/views/components/codex/fractions/picker.rb` | 33 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `View_template → Cache_key_for` | cross_community | 6 |
| `View_template → Typed_value` | cross_community | 6 |
| `View_template → Merger` | intra_community | 6 |
| `View_template → Merger` | cross_community | 6 |
| `View_template → Merger` | cross_community | 5 |
| `View_template → Merger` | cross_community | 5 |
| `View_template → Merger` | cross_community | 5 |
| `View_template → Merger` | cross_community | 5 |
| `View_template → Inline` | cross_community | 5 |
| `View_template → Map` | cross_community | 5 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Maintenance | 21 calls |
| Previews | 3 calls |
| Codex | 1 calls |

## How to Explore

1. grep/read `hidden?` — see callers and callees
2. grep `fractions` across `app/` — find related flows
3. Read key files listed above for implementation details
