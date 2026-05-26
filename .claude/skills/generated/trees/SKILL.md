---
name: trees
description: "Skill for the Trees area of silken_net. 32 symbols across 5 files."
---

# Trees

32 symbols | 5 files | Cohesion: 67%

## When to Use

- Working with code in `app/`
- Understanding how view_template, render_chronicle_frame, render_header work
- Modifying trees-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/views/components/trees/show.rb` | view_template, render_chronicle_frame, render_header, render_codex_citations, render_impedance_history (+8) |
| `app/views/components/trees/chronicle.rb` | view_template, render_header, render_entries, render_pagination, render_entry (+3) |
| `app/views/components/trees/index.rb` | view_template, render_header, header_stat, render_soldier_node, tree_status_led (+2) |
| `app/models/tree.rb` | ionic_voltage, current_stress, charge_percentage |
| `app/views/components/dashboard/map_node.rb` | view_template |

## Entry Points

Start here when exploring this area:

- **`view_template`** (Method) — `app/views/components/trees/show.rb:20`
- **`render_chronicle_frame`** (Method) — `app/views/components/trees/show.rb:50`
- **`render_header`** (Method) — `app/views/components/trees/show.rb:58`
- **`render_codex_citations`** (Method) — `app/views/components/trees/show.rb:86`
- **`render_impedance_history`** (Method) — `app/views/components/trees/show.rb:119`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `view_template` | Method | `app/views/components/trees/show.rb` | 20 |
| `render_chronicle_frame` | Method | `app/views/components/trees/show.rb` | 50 |
| `render_header` | Method | `app/views/components/trees/show.rb` | 58 |
| `render_codex_citations` | Method | `app/views/components/trees/show.rb` | 86 |
| `render_impedance_history` | Method | `app/views/components/trees/show.rb` | 119 |
| `render_hardware_security_vault` | Method | `app/views/components/trees/show.rb` | 178 |
| `render_economic_panel` | Method | `app/views/components/trees/show.rb` | 200 |
| `render_metadata_panel` | Method | `app/views/components/trees/show.rb` | 218 |
| `security_item` | Method | `app/views/components/trees/show.rb` | 247 |
| `meta_row` | Method | `app/views/components/trees/show.rb` | 254 |
| `ionic_voltage` | Method | `app/models/tree.rb` | 164 |
| `view_template` | Method | `app/views/components/trees/index.rb` | 10 |
| `render_header` | Method | `app/views/components/trees/index.rb` | 32 |
| `header_stat` | Method | `app/views/components/trees/index.rb` | 46 |
| `render_soldier_node` | Method | `app/views/components/trees/index.rb` | 54 |
| `tree_status_led` | Method | `app/views/components/trees/index.rb` | 90 |
| `tree_status_text_class` | Method | `app/views/components/trees/index.rb` | 96 |
| `charge_color` | Method | `app/views/components/trees/index.rb` | 105 |
| `current_stress` | Method | `app/models/tree.rb` | 151 |
| `charge_percentage` | Method | `app/models/tree.rb` | 169 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `View_template → Inline` | cross_community | 7 |
| `View_template → Map` | cross_community | 6 |
| `View_template → Merger` | cross_community | 5 |
| `View_template → Current_stress` | cross_community | 4 |
| `View_template → T` | cross_community | 3 |
| `View_template → Full_name` | cross_community | 3 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Maintenance | 10 calls |
| Fractions | 6 calls |
| Previews | 5 calls |
| Codex | 1 calls |

## How to Explore

1. `gitnexus_context({name: "view_template"})` — see callers and callees
2. `gitnexus_query({query: "trees"})` — find related execution flows
3. Read key files listed above for implementation details
