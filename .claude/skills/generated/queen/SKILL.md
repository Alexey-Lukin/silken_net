---
name: queen
description: "Skill for the Queen area of silken_net. 27 symbols across 1 files."
---

# Queen

27 symbols | 1 files | Cohesion: 82%

## When to Use

- Working with code in `firmware/`
- Understanding how SystemClock_Config, Process_And_Cache_Data, main work
- Modifying queen-related functionality

## Key Files

| File | Symbols |
|------|---------|
| `firmware/queen/main.c` | Read_Queen_UID_From_Flash, LoRa_Rx_Ring_Pop, SystemClock_Config, MX_GPIO_Init, MX_USART1_UART_Init (+22) |

## Entry Points

Start here when exploring this area:

- **`SystemClock_Config`** (Function) — `firmware/queen/main.c:382`
- **`Process_And_Cache_Data`** (Function) — `firmware/queen/main.c:392`
- **`main`** (Function) — `firmware/queen/main.c:415`
- **`Queen_Parse_CCM_LoRa_Packet`** (Function) — `firmware/queen/main.c:1459`
- **`Error_Handler`** (Function) — `firmware/queen/main.c:1577`

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `SystemClock_Config` | Function | `firmware/queen/main.c` | 382 |
| `Process_And_Cache_Data` | Function | `firmware/queen/main.c` | 392 |
| `main` | Function | `firmware/queen/main.c` | 415 |
| `Queen_Parse_CCM_LoRa_Packet` | Function | `firmware/queen/main.c` | 1459 |
| `Error_Handler` | Function | `firmware/queen/main.c` | 1577 |
| `SIM7070_SendATCommand` | Function | `firmware/queen/main.c` | 391 |
| `Flush_Cache_To_Rails` | Function | `firmware/queen/main.c` | 393 |
| `Cmd_Dedup_Check` | Function | `firmware/queen/main.c` | 397 |
| `Handle_CoAP_Command` | Function | `firmware/queen/main.c` | 398 |
| `OnRxDone` | Function | `firmware/queen/main.c` | 781 |
| `Read_Queen_UID_From_Flash` | Function | `firmware/queen/main.c` | 171 |
| `LoRa_Rx_Ring_Pop` | Function | `firmware/queen/main.c` | 284 |
| `MX_GPIO_Init` | Function | `firmware/queen/main.c` | 383 |
| `MX_USART1_UART_Init` | Function | `firmware/queen/main.c` | 384 |
| `MX_SUBGHZ_Init` | Function | `firmware/queen/main.c` | 385 |
| `MX_CRYP_Init` | Function | `firmware/queen/main.c` | 386 |
| `MX_IWDG_Init` | Function | `firmware/queen/main.c` | 387 |
| `djb2_hash_bytes` | Function | `firmware/queen/main.c` | 396 |
| `Load_AES_Key` | Function | `firmware/queen/main.c` | 400 |
| `Get_Current_Unix_Ts` | Function | `firmware/queen/main.c` | 403 |

## How to Explore

1. `gitnexus_context({name: "SystemClock_Config"})` — see callers and callees
2. `gitnexus_query({query: "queen"})` — find related execution flows
3. Read key files listed above for implementation details
