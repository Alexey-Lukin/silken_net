#ifndef SILKEN_COMMISSIONING_H
#define SILKEN_COMMISSIONING_H

/*
 * Commissioning.h — [ARCH.34] owned-комішенінг: публічна мережа (Helium =
 * стандартний LoRaWAN LNS, sync-word public), ідентичність — se-identity.h.
 */

#include "se-identity.h"
#include "LoRaMacVersion.h"

#define ABP_ACTIVATION_LRWAN_VERSION                       LORAMAC_VERSION

#define LORAWAN_REPEATER_SUPPORT                           false
#define LORAWAN_PUBLIC_NETWORK                             true
#define LORAWAN_NETWORK_ID                                 ( uint32_t )0

#endif /* SILKEN_COMMISSIONING_H */
