---
name: codex
description: "Skill for the Codex area of silken_net. 99 symbols across 40 files."
---

# Codex

99 symbols | 40 files | Cohesion: 79%

## When to Use

- Working with code in `app/`
- Understanding how create, destroy, render_validation work
- Modifying codex-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/services/codex/pair_selector_service.rb` | call, pick_anchor, pick_opponent, sign_pair, store_seed (+2) |
| `app/controllers/api/v1/codex/citations_controller.rb` | destroy, broadcast_citation_removed, create, resolve_target!, cache_idempotent_response (+1) |
| `app/views/components/codex/node_card.rb` | render_cover, glyph_for_realm, view_template, render_realm_pill, render_lifecycle_badge (+1) |
| `app/services/codex/fraction_change_service.rb` | call, invalid, cooldown_blocked, enqueue_audit, enqueue_discovery_probe |
| `app/services/codex/presence_tracker.rb` | touch, leave, observers_for_tree, observed?, key_for |
| `app/controllers/api/v1/codex/attunements_controller.rb` | create, destroy, render_validation, enqueue_discovery_probe |
| `app/services/codex/vote_recorder_service.rb` | call, resolve_winner, compute_deltas, failure |
| `app/controllers/api/v1/codex/leaderboard_controller.rb` | index, resolve_realm, clamp_limit, serialize |
| `app/views/components/codex/show.rb` | view_template, render_hero, render_lore_columns, render_meta_panel |
| `app/workers/codex/elo_recompute_worker.rb` | perform, bump, probe_for_match_milestone |

## Entry Points

Start here when exploring this area:

- **`create`** (Method) — `app/controllers/api/v1/codex/attunements_controller.rb:14`
- **`destroy`** (Method) — `app/controllers/api/v1/codex/attunements_controller.rb:41`
- **`render_validation`** (Method) — `app/controllers/api/v1/codex/attunements_controller.rb:68`
- **`enqueue_discovery_probe`** (Method) — `app/controllers/api/v1/codex/attunements_controller.rb:77`
- **`simulate`** (Method) — `app/controllers/api/v1/oracle_visions_controller.rb:54`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `create` | Method | `app/controllers/api/v1/codex/attunements_controller.rb` | 14 |
| `destroy` | Method | `app/controllers/api/v1/codex/attunements_controller.rb` | 41 |
| `render_validation` | Method | `app/controllers/api/v1/codex/attunements_controller.rb` | 68 |
| `enqueue_discovery_probe` | Method | `app/controllers/api/v1/codex/attunements_controller.rb` | 77 |
| `simulate` | Method | `app/controllers/api/v1/oracle_visions_controller.rb` | 54 |
| `perform` | Method | `app/workers/codex/elo_recompute_worker.rb` | 21 |
| `bump` | Method | `app/workers/codex/elo_recompute_worker.rb` | 32 |
| `probe_for_match_milestone` | Method | `app/workers/codex/elo_recompute_worker.rb` | 51 |
| `perform_async` | Method | `spec/requests/api/v1/oracle_visions_controller_spec.rb` | 138 |
| `destroy` | Method | `app/controllers/api/v1/codex/citations_controller.rb` | 61 |
| `broadcast_citation_removed` | Method | `app/controllers/api/v1/codex/citations_controller.rb` | 157 |
| `create` | Method | `app/controllers/api/v1/codex/comments_controller.rb` | 14 |
| `cache_idempotent_response` | Method | `app/controllers/api/v1/codex/comments_controller.rb` | 71 |
| `broadcast_comment` | Method | `app/controllers/api/v1/codex/comments_controller.rb` | 79 |
| `perform` | Method | `app/workers/codex/attunement_broadcast_worker.rb` | 19 |
| `perform` | Method | `app/workers/codex/discovery_probe_worker.rb` | 29 |
| `create_discovery!` | Method | `app/workers/codex/discovery_probe_worker.rb` | 48 |
| `broadcast` | Method | `app/workers/codex/discovery_probe_worker.rb` | 70 |
| `show` | Method | `app/controllers/api/v1/codex/nodes_controller.rb` | 47 |
| `chronicle` | Method | `app/controllers/api/v1/trees_controller.rb` | 72 |

## Execution Flows

| Flow | Type | Steps |
|------|------|-------|
| `Index → Inline` | cross_community | 6 |
| `Chronicle → Inline` | cross_community | 6 |
| `View_template → Cache_key_for` | cross_community | 6 |
| `View_template → Typed_value` | cross_community | 6 |
| `View_template → Inline` | cross_community | 6 |
| `View_template → Map` | cross_community | 6 |
| `Index → Map` | cross_community | 5 |
| `Chronicle → Map` | cross_community | 5 |
| `View_template → Inline` | cross_community | 5 |
| `View_template → Map` | cross_community | 5 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Previews | 9 calls |
| Maintenance | 7 calls |
| Models | 6 calls |
| V1 | 4 calls |
| Fractions | 3 calls |
| Citations | 1 calls |

## How to Explore

1. `gitnexus_context({name: "create"})` — see callers and callees
2. `gitnexus_query({query: "codex"})` — find related execution flows
3. Read key files listed above for implementation details
