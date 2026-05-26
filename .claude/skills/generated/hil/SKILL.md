---
name: hil
description: "Skill for the Hil area of silken_net. 20 symbols across 2 files."
---

# Hil

20 symbols | 2 files | Cohesion: 83%

## When to Use

- Working with code in `lib/`
- Understanding how sample, sample_in_state, synthesize work
- Modifying hil-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `lib/hil/queen_simulator.rb` | dispatch_wire, encrypted_sentinel_payload, build_sentinel_chunk, build_sentinel_inner, clamp_uint16 (+6) |
| `lib/hil/lorenz_generator.rb` | sample, sample_in_state, synthesize, batch, build_sample (+4) |

## Entry Points

Start here when exploring this area:

- **`sample`** (Method) — `lib/hil/lorenz_generator.rb:91`
- **`sample_in_state`** (Method) — `lib/hil/lorenz_generator.rb:102`
- **`synthesize`** (Method) — `lib/hil/lorenz_generator.rb:128`
- **`batch`** (Method) — `lib/hil/lorenz_generator.rb:143`
- **`build_sample`** (Method) — `lib/hil/lorenz_generator.rb:189`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `sample` | Method | `lib/hil/lorenz_generator.rb` | 91 |
| `sample_in_state` | Method | `lib/hil/lorenz_generator.rb` | 102 |
| `synthesize` | Method | `lib/hil/lorenz_generator.rb` | 128 |
| `batch` | Method | `lib/hil/lorenz_generator.rb` | 143 |
| `build_sample` | Method | `lib/hil/lorenz_generator.rb` | 189 |
| `in_band?` | Method | `lib/hil/lorenz_generator.rb` | 224 |
| `forced_z_for` | Method | `lib/hil/lorenz_generator.rb` | 236 |
| `dispatch_wire` | Method | `lib/hil/queen_simulator.rb` | 136 |
| `encrypted_sentinel_payload` | Method | `lib/hil/queen_simulator.rb` | 146 |
| `build_sentinel_chunk` | Method | `lib/hil/queen_simulator.rb` | 164 |
| `build_sentinel_inner` | Method | `lib/hil/queen_simulator.rb` | 179 |
| `clamp_uint16` | Method | `lib/hil/queen_simulator.rb` | 202 |
| `clamp_int8` | Method | `lib/hil/queen_simulator.rb` | 206 |
| `clamp_uint8` | Method | `lib/hil/queen_simulator.rb` | 210 |
| `tick` | Method | `lib/hil/queen_simulator.rb` | 90 |
| `run!` | Method | `lib/hil/queen_simulator.rb` | 117 |
| `dispatch_direct` | Method | `lib/hil/queen_simulator.rb` | 129 |
| `next_cifo_fill` | Method | `lib/hil/queen_simulator.rb` | 193 |
| `initialize` | Method | `lib/hil/lorenz_generator.rb` | 78 |
| `resolve_seed_bytes` | Method | `lib/hil/lorenz_generator.rb` | 256 |

## Connected Areas

| Area | Connections |
|------|-------------|
| Silken_net | 3 calls |
| Cluster_457 | 1 calls |
| Cryptography | 1 calls |
| Models | 1 calls |

## How to Explore

1. `gitnexus_context({name: "sample"})` — see callers and callees
2. `gitnexus_query({query: "hil"})` — find related execution flows
3. Read key files listed above for implementation details
