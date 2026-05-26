---
name: tree-chronicle
description: "Skill for the Tree_chronicle area of silken_net. 23 symbols across 2 files."
---

# Tree_chronicle

23 symbols | 2 files | Cohesion: 98%

## When to Use

- Working with code in `app/`
- Understanding how homeostasis_title, homeostasis_description, stress_title work
- Modifying tree_chronicle-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/services/tree_chronicle/text_formatter.rb` | homeostasis_title, homeostasis_description, stress_title, stress_description, fraud_title (+10) |
| `app/services/tree_chronicle_service.rb` | insight_entries, format_insight, alert_entries, format_alert, maintenance_entries (+3) |

## Entry Points

Start here when exploring this area:

- **`homeostasis_title`** (Method) — `app/services/tree_chronicle/text_formatter.rb:14`
- **`homeostasis_description`** (Method) — `app/services/tree_chronicle/text_formatter.rb:18`
- **`stress_title`** (Method) — `app/services/tree_chronicle/text_formatter.rb:24`
- **`stress_description`** (Method) — `app/services/tree_chronicle/text_formatter.rb:28`
- **`fraud_title`** (Method) — `app/services/tree_chronicle/text_formatter.rb:35`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `homeostasis_title` | Method | `app/services/tree_chronicle/text_formatter.rb` | 14 |
| `homeostasis_description` | Method | `app/services/tree_chronicle/text_formatter.rb` | 18 |
| `stress_title` | Method | `app/services/tree_chronicle/text_formatter.rb` | 24 |
| `stress_description` | Method | `app/services/tree_chronicle/text_formatter.rb` | 28 |
| `fraud_title` | Method | `app/services/tree_chronicle/text_formatter.rb` | 35 |
| `fraud_description` | Method | `app/services/tree_chronicle/text_formatter.rb` | 39 |
| `insight_entries` | Method | `app/services/tree_chronicle_service.rb` | 57 |
| `format_insight` | Method | `app/services/tree_chronicle_service.rb` | 65 |
| `alert_icon` | Method | `app/services/tree_chronicle/text_formatter.rb` | 45 |
| `alert_title` | Method | `app/services/tree_chronicle/text_formatter.rb` | 57 |
| `alert_description` | Method | `app/services/tree_chronicle/text_formatter.rb` | 69 |
| `recovery_title` | Method | `app/services/tree_chronicle/text_formatter.rb` | 74 |
| `recovery_description` | Method | `app/services/tree_chronicle/text_formatter.rb` | 78 |
| `alert_entries` | Method | `app/services/tree_chronicle_service.rb` | 103 |
| `format_alert` | Method | `app/services/tree_chronicle_service.rb` | 110 |
| `maintenance_title` | Method | `app/services/tree_chronicle/text_formatter.rb` | 90 |
| `maintenance_description` | Method | `app/services/tree_chronicle/text_formatter.rb` | 94 |
| `maintenance_entries` | Method | `app/services/tree_chronicle_service.rb` | 141 |
| `format_maintenance` | Method | `app/services/tree_chronicle_service.rb` | 149 |
| `minting_title` | Method | `app/services/tree_chronicle/text_formatter.rb` | 101 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Maintenance | 1 calls |

## How to Explore

1. `gitnexus_context({name: "homeostasis_title"})` — see callers and callees
2. `gitnexus_query({query: "tree_chronicle"})` — find related execution flows
3. Read key files listed above for implementation details
