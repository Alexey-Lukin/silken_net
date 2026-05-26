---
name: soldier
description: "Skill for the Soldier area of silken_net. 37 symbols across 1 files."
---

# Soldier

37 symbols | 1 files | Cohesion: 97%

## When to Use

- Working with code in `firmware/`
- Understanding how SystemClock_Config, Trigger_Emergency_LoRa_TX, Write_OTA_Contract_To_Flash work
- Modifying soldier-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `firmware/soldier/main.c` | float_to_uint32, uint32_to_float, Soldier_CRC16_CCITT, Soldier_Handle_CMD_SET_THRESHOLDS, EMA_Update (+32) |

## Entry Points

Start here when exploring this area:

- **`SystemClock_Config`** (Function) — `firmware/soldier/main.c:1127`
- **`Trigger_Emergency_LoRa_TX`** (Function) — `firmware/soldier/main.c:1140`
- **`Write_OTA_Contract_To_Flash`** (Function) — `firmware/soldier/main.c:1141`
- **`main`** (Function) — `firmware/soldier/main.c:1167`
- **`HAL_PWR_PVDCallback`** (Function) — `firmware/soldier/main.c:2092`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `SystemClock_Config` | Function | `firmware/soldier/main.c` | 1127 |
| `Trigger_Emergency_LoRa_TX` | Function | `firmware/soldier/main.c` | 1140 |
| `Write_OTA_Contract_To_Flash` | Function | `firmware/soldier/main.c` | 1141 |
| `main` | Function | `firmware/soldier/main.c` | 1167 |
| `HAL_PWR_PVDCallback` | Function | `firmware/soldier/main.c` | 2092 |
| `Error_Handler` | Function | `firmware/soldier/main.c` | 2480 |
| `Soldier_Build_CCM_LoRa_Packet` | Function | `firmware/soldier/main.c` | 2435 |
| `float_to_uint32` | Function | `firmware/soldier/main.c` | 312 |
| `uint32_to_float` | Function | `firmware/soldier/main.c` | 318 |
| `Soldier_CRC16_CCITT` | Function | `firmware/soldier/main.c` | 400 |
| `Soldier_Handle_CMD_SET_THRESHOLDS` | Function | `firmware/soldier/main.c` | 418 |
| `EMA_Update` | Function | `firmware/soldier/main.c` | 815 |
| `EMA_Get_DeltaT_Sec` | Function | `firmware/soldier/main.c` | 839 |
| `EMA_Get_Vcap_Mv` | Function | `firmware/soldier/main.c` | 840 |
| `EMA_Is_Warmed_Up` | Function | `firmware/soldier/main.c` | 844 |
| `TinyML_Validate_Threshold` | Function | `firmware/soldier/main.c` | 854 |
| `TinyML_Apply_Thresholds` | Function | `firmware/soldier/main.c` | 880 |
| `Build_OTA_ReRequest_Payload` | Function | `firmware/soldier/main.c` | 928 |
| `Parse_HMAC_Trailer_Chunk` | Function | `firmware/soldier/main.c` | 984 |
| `Soldier_Handle_CMD_SET_AUDIO_THRESHOLDS` | Function | `firmware/soldier/main.c` | 1077 |

## How to Explore

1. `gitnexus_context({name: "SystemClock_Config"})` — see callers and callees
2. `gitnexus_query({query: "soldier"})` — find related execution flows
3. Read key files listed above for implementation details
