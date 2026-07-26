// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef SILKEN_MW_LOG_CONF_H
#define SILKEN_MW_LOG_CONF_H

/*
 * mw_log_conf.h — [ARCH.34] owned no-op лог для vendored LoRaMac-node.
 * Queen не має UART-консолі під логи (USART1 = SIM7070G); діагностика
 * SOS-шляху їде health-байтами QATT (ARCH.54), не printf'ом.
 */

#define TS_ON  1
#define TS_OFF 0

#define VLEVEL_OFF    0
#define VLEVEL_ALWAYS 0
#define VLEVEL_L      1
#define VLEVEL_M      2
#define VLEVEL_H      3

#define MW_LOG(TS, VL, ...) do { } while (0)

#endif /* SILKEN_MW_LOG_CONF_H */
