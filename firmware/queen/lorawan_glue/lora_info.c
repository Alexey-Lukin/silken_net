/*
 * lora_info.c — [ARCH.34] owned мінімум (шаблон template: лише те, що
 * профіль реально вмикає — EU868, без Kms/ClassB/CtxMgmt/dual-core).
 */
#include "lora_info.h"
#include "lorawan_conf.h"
#include "LoRaMacInterfaces.h" /* LoRaMacRegion_t enum */

static LoraInfo_t loraInfo;

void LoraInfo_Init( void )
{
    loraInfo.ContextManagement = CONTEXT_MANAGEMENT_ENABLED;
    loraInfo.Region            = 0u;
    loraInfo.ClassB            = LORAMAC_CLASSB_ENABLED;
    loraInfo.Kms               = LORAWAN_KMS;
#ifdef REGION_EU868
    loraInfo.Region |= ( 1u << LORAMAC_REGION_EU868 );
#endif
    /* Порожня маска = зіпсутий конфіг; шаблон тут вічно крутився у
     * printf-циклі — Queen чесніше перезавантажити IWDG'ом не годуючи,
     * але до ефіру так не дійде: гейт компайл-тайму нижче. */
}

LoraInfo_t *LoraInfo_GetPtr( void )
{
    return &loraInfo;
}

#ifndef REGION_EU868
#error "[ARCH.34] lorawan_conf.h мусить вмикати REGION_EU868 (єдиний профіль Queen)"
#endif
