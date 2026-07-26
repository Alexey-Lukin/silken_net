// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef SILKEN_UTILITIES_CONF_H
#define SILKEN_UTILITIES_CONF_H

#include <stdint.h>
#include <stddef.h>

/*
 * utilities_conf.h — [ARCH.34] owned-конфіг vendored utilities.h.
 * Сюди LoRaMac-node приходить за платформою: критичні секції та ALIGN
 * (CubeWL тут ще тягне trace/sequencer — профіль SOS їх не має).
 *
 * Критичні секції: MAC захищає чергу команд/таймери. MCU = PRIMASK
 * save/restore; host-збірка (compile-проба/тести) = no-op — SOS-шлях
 * однопотоковий у main loop.
 */

#if defined(STM32WLE5xx) || defined(USE_HAL_DRIVER)
#include "cmsis_compiler.h"
#define CRITICAL_SECTION_BEGIN( )                     \
    uint32_t primask_bit = __get_PRIMASK( );          \
    __disable_irq( )
#define CRITICAL_SECTION_END( ) __set_PRIMASK( primask_bit )
#else
#define CRITICAL_SECTION_BEGIN( ) do { } while (0)
#define CRITICAL_SECTION_END( )   do { } while (0)
#endif

/* MIC-буфери LoRaMacCrypto реально вимагають вирівнювання — не порожній. */
#ifndef ALIGN
#define ALIGN( n ) __attribute__( ( aligned( n ) ) )
#endif

#endif /* SILKEN_UTILITIES_CONF_H */
