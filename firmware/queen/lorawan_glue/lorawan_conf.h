#ifndef SILKEN_LORAWAN_CONF_H
#define SILKEN_LORAWAN_CONF_H

/*
 * lorawan_conf.h — [ARCH.34] owned-конфіг vendored LoRaMac-node
 * (extern/stm32-mw-lorawan, шаблон Conf/lorawan_conf_template.h).
 *
 * Профіль СВІДОМО мінімальний — Helium SOS-маяк, не загальний LoRaWAN-вузол:
 * EU868 only · Class A only · без KMS · без Data-Distribution пакетів ·
 * без NvmDataMgmt (CONTEXT_MANAGEMENT 0: SOS-епізод = fresh OTAA join,
 * контекст ефемерний у RAM; єдиний персист = DevNonce через MIB_NVM_CTXS →
 * flash_kv — дім рішення 00_07 ARCH.34).
 */

#define LORAMAC_SPECIFICATION_VERSION                   0x01000400

#define LORAWAN_KMS                                     0
#define LORAWAN_DATA_DISTRIB_MGT                        0
#define LORAWAN_PACKAGES_VERSION                        1

/* Регіон: лише EU868 (Україна). Компілюється ЄДИНИЙ Region-TU. */
#define REGION_EU868

#define HYBRID_ENABLED                                  0
#define KEY_EXTRACTABLE                                 1
#define CONTEXT_MANAGEMENT_ENABLED                      0
#define LORAMAC_CLASSB_ENABLED                          0
#define DISABLE_LORAWAN_RX_WINDOW                       0

/* soft-se ключі: без спец-секції розміщення (шаблон клав у
 * .USER_embedded_Keys для KMS-провіженінгу; наш шлях — bench-провіженінг
 * з Flash, 03_06). Порожні макро = звичайний .data/.rodata. */
#define SOFT_SE_PLACE_IN_NVM_START
#define SOFT_SE_PLACE_IN_NVM_STOP

#endif /* SILKEN_LORAWAN_CONF_H */
