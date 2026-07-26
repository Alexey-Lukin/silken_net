// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef SILKEN_LORAWAN_PLATFORM_H
#define SILKEN_LORAWAN_PLATFORM_H

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

/*
 * platform.h — [ARCH.34] owned-платформа для LmHandler/Packages
 * (чекають її замість CubeMX-generated). Критичні секції/ALIGN живуть
 * у utilities_conf.h (туди ходить решта стека) — тут лише доповнення.
 */

#include "utilities_conf.h"

/* Шаблонні розміщення пам'яті (dual-core mailbox ST-прикладів) — Queen
 * одноядерна WLE5, звичайні секції. */
#define UTIL_MEM_PLACE_IN_SECTION( __x__ )

#endif /* SILKEN_LORAWAN_PLATFORM_H */
