// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * queen_hal_check.c — [FW.46] HAL compile-lane: ПЕРШИЙ справжній компайл
 * queen/main.c проти vendored stm32wlxx-hal-driver (ARM, soft-float).
 *
 * Той самий патерн, що soldier_hal_check.c: main.c = CubeMX merge-фрагмент
 * (4 init-прототипи static без тіл), цей TU включає його дослівно і докладає
 * порожні заглушки — фізика тіл прийде з .ioc (👤 board-freeze).
 * Канон: docs/03_01 §12.4 · трекер: 00_07 FW.46.
 */

/* ── board-freeze pin-макроси (👤 .ioc згенерує справжні) для ARCH.35-compile-lane:
 * потрібні ДО include, бо гейтований main.c-блок кличе їх як макро (W25Q32 CS).
 * Порожні = compile-only; реальний GPIO-toggle прийде з .ioc board-freeze. */
#ifndef W25Q32_CS_LOW
#define W25Q32_CS_LOW()   ((void)0)
#endif
#ifndef W25Q32_CS_HIGH
#define W25Q32_CS_HIGH()  ((void)0)
#endif

#include "../queen/main.c"

/* ── CubeMX-заглушки (👤 .ioc згенерує справжні) ───────────────────────── */
void SystemClock_Config(void) { /* 👤 клок-дерево */ }
static void MX_GPIO_Init(void)        { /* 👤 пін-мапа = board-freeze */ }
static void MX_USART1_UART_Init(void) { /* 👤 UART1 ↔ SIM7070G (PA9/PA10?) */ }
static void MX_SUBGHZ_Init(void)      { /* 👤 */ }
