---
name: policies
description: "Skill for the Policies area of silken_net. 20 symbols across 10 files."
---

# Policies

20 symbols | 10 files | Cohesion: 100%

## When to Use

- Working with code in `app/`
- Understanding how authorize_forester!, forest_commander?, index? work
- Modifying policies-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `app/policies/maintenance_record_policy.rb` | index?, show?, create?, update?, verify? (+1) |
| `app/policies/actuator_policy.rb` | index?, show?, execute? |
| `app/policies/wallet_policy.rb` | show?, balance?, metadata? |
| `app/policies/application_policy.rb` | forester_or_above?, same_organization? |
| `app/controllers/api/v1/base_controller.rb` | authorize_forester! |
| `app/models/user.rb` | forest_commander? |
| `app/policies/codex/citation_policy.rb` | create? |
| `app/policies/ews_alert_policy.rb` | resolve? |
| `app/policies/naas_contract_policy.rb` | show? |
| `app/policies/user_policy.rb` | show? |

## Entry Points

Start here when exploring this area:

- **`authorize_forester!`** (Method) — `app/controllers/api/v1/base_controller.rb:95`
- **`forest_commander?`** (Method) — `app/models/user.rb:108`
- **`index?`** (Method) — `app/policies/actuator_policy.rb:3`
- **`show?`** (Method) — `app/policies/actuator_policy.rb:7`
- **`execute?`** (Method) — `app/policies/actuator_policy.rb:11`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `authorize_forester!` | Method | `app/controllers/api/v1/base_controller.rb` | 95 |
| `forest_commander?` | Method | `app/models/user.rb` | 108 |
| `index?` | Method | `app/policies/actuator_policy.rb` | 3 |
| `show?` | Method | `app/policies/actuator_policy.rb` | 7 |
| `execute?` | Method | `app/policies/actuator_policy.rb` | 11 |
| `forester_or_above?` | Method | `app/policies/application_policy.rb` | 40 |
| `create?` | Method | `app/policies/codex/citation_policy.rb` | 17 |
| `resolve?` | Method | `app/policies/ews_alert_policy.rb` | 7 |
| `index?` | Method | `app/policies/maintenance_record_policy.rb` | 3 |
| `show?` | Method | `app/policies/maintenance_record_policy.rb` | 7 |
| `create?` | Method | `app/policies/maintenance_record_policy.rb` | 11 |
| `update?` | Method | `app/policies/maintenance_record_policy.rb` | 15 |
| `verify?` | Method | `app/policies/maintenance_record_policy.rb` | 19 |
| `photos?` | Method | `app/policies/maintenance_record_policy.rb` | 23 |
| `same_organization?` | Method | `app/policies/application_policy.rb` | 44 |
| `show?` | Method | `app/policies/naas_contract_policy.rb` | 7 |
| `show?` | Method | `app/policies/user_policy.rb` | 7 |
| `show?` | Method | `app/policies/wallet_policy.rb` | 7 |
| `balance?` | Method | `app/policies/wallet_policy.rb` | 13 |
| `metadata?` | Method | `app/policies/wallet_policy.rb` | 17 |

## How to Explore

1. `gitnexus_context({name: "authorize_forester!"})` — see callers and callees
2. `gitnexus_query({query: "policies"})` — find related execution flows
3. Read key files listed above for implementation details
