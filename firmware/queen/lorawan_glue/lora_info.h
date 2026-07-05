#ifndef SILKEN_LORA_INFO_H
#define SILKEN_LORA_INFO_H

#include <stdint.h>

/*
 * lora_info.h — [ARCH.34] owned мінімум ST lora_info (шаблон
 * Conf/lora_info_template.h без dual-core mailbox-розміщень).
 * LmHandler читає її один раз в Init — capability-довідка компіляції.
 */

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    uint32_t ContextManagement;
    uint32_t Region;  /* бітова маска скомпільованих регіонів */
    uint32_t ClassB;
    uint32_t Kms;
} LoraInfo_t;

void        LoraInfo_Init( void );
LoraInfo_t *LoraInfo_GetPtr( void );

#ifdef __cplusplus
}
#endif

#endif /* SILKEN_LORA_INFO_H */
