---
name: ui
description: "Skill for the Ui area of silken_net. 114 symbols across 108 files."
---

# Ui

114 symbols | 108 files | Cohesion: 98%

## When to Use

- Working with code in `app/`
- Understanding how Show, Card, CommandRow work
- Modifying ui-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/views/shared/ui/pagination.rb` | Pagination, view_template, render_previous, render_next, render_indicator |
| `app/views/shared/ui/empty_state.rb` | EmptyState, view_template, render_content |
| `app/views/components/account_security/show.rb` | Show |
| `app/views/components/actuators/card.rb` | Card |
| `app/views/components/actuators/command_row.rb` | CommandRow |
| `app/views/components/actuators/command_status_badge.rb` | CommandStatusBadge |
| `app/views/components/actuators/index.rb` | Index |
| `app/views/components/actuators/show.rb` | Show |
| `app/views/components/alerts/badge.rb` | Badge |
| `app/views/components/alerts/index.rb` | Index |

## Entry Points

Start here when exploring this area:

- **`Show`** (Class) — `app/views/components/account_security/show.rb:3`
- **`Card`** (Class) — `app/views/components/actuators/card.rb:3`
- **`CommandRow`** (Class) — `app/views/components/actuators/command_row.rb:3`
- **`CommandStatusBadge`** (Class) — `app/views/components/actuators/command_status_badge.rb:3`
- **`Index`** (Class) — `app/views/components/actuators/index.rb:3`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `Show` | Class | `app/views/components/account_security/show.rb` | 3 |
| `Card` | Class | `app/views/components/actuators/card.rb` | 3 |
| `CommandRow` | Class | `app/views/components/actuators/command_row.rb` | 3 |
| `CommandStatusBadge` | Class | `app/views/components/actuators/command_status_badge.rb` | 3 |
| `Index` | Class | `app/views/components/actuators/index.rb` | 3 |
| `Show` | Class | `app/views/components/actuators/show.rb` | 1 |
| `Badge` | Class | `app/views/components/alerts/badge.rb` | 3 |
| `Index` | Class | `app/views/components/alerts/index.rb` | 3 |
| `Row` | Class | `app/views/components/alerts/row.rb` | 4 |
| `ApplicationComponent` | Class | `app/views/components/application_component.rb` | 2 |
| `Index` | Class | `app/views/components/audit_logs/index.rb` | 3 |
| `Show` | Class | `app/views/components/audit_logs/show.rb` | 3 |
| `Index` | Class | `app/views/components/blockchain_transactions/index.rb` | 3 |
| `OnChainFrame` | Class | `app/views/components/blockchain_transactions/on_chain_frame.rb` | 3 |
| `Show` | Class | `app/views/components/blockchain_transactions/show.rb` | 3 |
| `Grid` | Class | `app/views/components/clusters/grid.rb` | 3 |
| `Item` | Class | `app/views/components/clusters/item.rb` | 4 |
| `Show` | Class | `app/views/components/clusters/show.rb` | 3 |
| `Toggle` | Class | `app/views/components/codex/attunements/toggle.rb` | 9 |
| `Arena` | Class | `app/views/components/codex/battle/arena.rb` | 14 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `View_template → Merger` | cross_community | 3 |
| `View_template → T` | cross_community | 3 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Maintenance | 4 calls |
| Fractions | 1 calls |

## How to Explore

1. `gitnexus_context({name: "Show"})` — see callers and callees
2. `gitnexus_query({query: "ui"})` — find related execution flows
3. Read key files listed above for implementation details
