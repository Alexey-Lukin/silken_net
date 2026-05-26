---
name: clusters
description: "Skill for the Clusters area of silken_net. 24 symbols across 6 files."
---

# Clusters

24 symbols | 6 files | Cohesion: 69%

## When to Use

- Working with code in `app/`
- Understanding how show, find_contract, total_active_trees work
- Modifying clusters-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/views/components/clusters/show.rb` | render_vitals_panel, vital_block, env_block, view_template, render_header (+7) |
| `app/views/components/clusters/item.rb` | view_template, header_section, stats_section, stat_block, footer_section |
| `app/controllers/api/v1/contracts_controller.rb` | show, find_contract |
| `app/models/cluster.rb` | total_active_trees, health_index |
| `app/views/components/contracts/show.rb` | render_backing_asset_panel, metric_row |
| `app/views/components/organizations/show.rb` | render_clusters_registry |

## Entry Points

Start here when exploring this area:

- **`show`** (Method) — `app/controllers/api/v1/contracts_controller.rb:47`
- **`find_contract`** (Method) — `app/controllers/api/v1/contracts_controller.rb:93`
- **`total_active_trees`** (Method) — `app/models/cluster.rb:76`
- **`health_index`** (Method) — `app/models/cluster.rb:87`
- **`view_template`** (Method) — `app/views/components/clusters/item.rb:9`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `show` | Method | `app/controllers/api/v1/contracts_controller.rb` | 47 |
| `find_contract` | Method | `app/controllers/api/v1/contracts_controller.rb` | 93 |
| `total_active_trees` | Method | `app/models/cluster.rb` | 76 |
| `health_index` | Method | `app/models/cluster.rb` | 87 |
| `view_template` | Method | `app/views/components/clusters/item.rb` | 9 |
| `header_section` | Method | `app/views/components/clusters/item.rb` | 19 |
| `stats_section` | Method | `app/views/components/clusters/item.rb` | 35 |
| `stat_block` | Method | `app/views/components/clusters/item.rb` | 42 |
| `footer_section` | Method | `app/views/components/clusters/item.rb` | 49 |
| `render_vitals_panel` | Method | `app/views/components/clusters/show.rb` | 76 |
| `vital_block` | Method | `app/views/components/clusters/show.rb` | 103 |
| `env_block` | Method | `app/views/components/clusters/show.rb` | 110 |
| `render_backing_asset_panel` | Method | `app/views/components/contracts/show.rb` | 48 |
| `metric_row` | Method | `app/views/components/contracts/show.rb` | 64 |
| `render_clusters_registry` | Method | `app/views/components/organizations/show.rb` | 62 |
| `view_template` | Method | `app/views/components/clusters/show.rb` | 17 |
| `render_header` | Method | `app/views/components/clusters/show.rb` | 39 |
| `render_codex_citations` | Method | `app/views/components/clusters/show.rb` | 66 |
| `render_gateways_table` | Method | `app/views/components/clusters/show.rb` | 117 |
| `render_gateway_row` | Method | `app/views/components/clusters/show.rb` | 140 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `View_template → Map` | cross_community | 6 |
| `Show → Inline` | cross_community | 5 |
| `Show → Map` | cross_community | 5 |
| `View_template → Merger` | cross_community | 5 |
| `View_template → Merger` | cross_community | 4 |
| `View_template → T` | cross_community | 3 |
| `View_template → Vital_block` | cross_community | 3 |
| `View_template → Health_index` | cross_community | 3 |
| `View_template → Total_active_trees` | cross_community | 3 |
| `View_template → Render_gateway_row` | intra_community | 3 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Maintenance | 10 calls |
| Fractions | 4 calls |
| Previews | 2 calls |
| V1 | 1 calls |
| Models | 1 calls |

## How to Explore

1. `gitnexus_context({name: "show"})` — see callers and callees
2. `gitnexus_query({query: "clusters"})` — find related execution flows
3. Read key files listed above for implementation details
