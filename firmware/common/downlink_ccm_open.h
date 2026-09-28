// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * downlink_ccm_open.h — HAL-половина downlink_ccm.h: відкрити адресний
 * командний кадр Rails → Солдат (docs/03_05 §2.5).
 *
 * Той самий двофазний WL-флоу, що аплінк (lora_ccm.h): B0 + HAL_CRYP_Decrypt
 * (Size у байтах) + HAL_CRYPEx_AESCCM_GenerateAuthTAG, а звірка тегу — тут,
 * константним часом (WL-HAL тег сам не звіряє). Відмінності від аплінку лише
 * дві: AAD 7 Б, а не 8 (перший на цьому шляху заголовок, не кратний слову, —
 * його атестує downlink-вектор самотесту, ccm_selftest.h), і байт напрямку
 * в нонсі.
 *
 * Header-only, `hcryp` інжектується (host — мок hal_mock.h, кремній —
 * глобальний &hcryp), як у ccm_selftest.h. Викликач включає HAL (або мок)
 * ДО цього файлу.
 *
 * ⚠️ Функція лишає CRYP у CCM-конфігурації з ключем викликача (вказівники
 * B0/Header вона сама обнуляє, width-unit'и повертає у WORD). Базову лінію
 * ECB відновлює викликач одразу після виклику — на Солдаті це
 * MX_CRYP_Restore_From_CCM() (firmware-скіл, гоча 1).
 */
#ifndef SILKEN_DOWNLINK_CCM_OPEN_H
#define SILKEN_DOWNLINK_CCM_OPEN_H

#include <string.h>

#include "downlink_ccm.h"

typedef enum {
    DL_CCM_OK = 0,
    DL_CCM_MALFORMED,       /* не командний опкод або не його довжина */
    DL_CCM_NOT_MINE,        /* DID чужий — відкинуто до криптографії */
    DL_CCM_DLFC_EXHAUSTED,  /* реконструкція переповнилась (див. шапку downlink_ccm.h) */
    DL_CCM_HAL_ERROR,
    DL_CCM_BAD_MIC,         /* підробка, чужий ключ або повтор (інший нонс) */
} DlCcmResult;

/* Відкрити кадр. key_w — сесійний ключ вузла (KEYL / K_v), last_dlfc —
 * останній прийнятий DLFC. DL_CCM_OK → body_out несе Dl_Ccm_Body_Len(frame[0])
 * байт відкритого тіла, *dlfc_out — реконструйований DLFC (його й писати в
 * журнал ПЕРЕД застосуванням). Будь-яка інша відповідь — стан незмінний. */
// cppcheck-suppress shadowVariable
static inline DlCcmResult Dl_Ccm_Open(CRYP_HandleTypeDef *hcryp, uint32_t key_w[4],
                                      const uint8_t *frame, uint16_t frame_len,
                                      uint32_t self_did, uint32_t last_dlfc,
                                      uint8_t body_out[DL_CCM_BODY_MAX],
                                      uint32_t *dlfc_out)
{
    if (!Dl_Ccm_Frame_Well_Formed(frame, frame_len)) return DL_CCM_MALFORMED;
    if (Dl_Ccm_Frame_Did(frame) != self_did)         return DL_CCM_NOT_MINE;

    uint32_t dlfc = Dl_Ccm_Reconstruct_Dlfc(last_dlfc, Dl_Ccm_Frame_Dlfc_Lsb(frame));
    if (dlfc == 0u) return DL_CCM_DLFC_EXHAUSTED;

    const uint8_t body_len = Dl_Ccm_Body_Len(frame[0]);

    /* Word-aligned плоть: CRYP HAL споживає uint32_t*, а кадр — байтовий буфер
     * радіо без обіцянки вирівнювання. */
    uint8_t  nonce[FW2_CCM_NONCE_LEN];
    uint32_t b0_w[FW2_CCM_B0_LEN / 4];
    uint32_t aad_w[(DL_CCM_AAD_LEN + 3u) / 4] = {0};
    uint32_t ct_w[(DL_CCM_BODY_MAX + 3u) / 4] = {0};
    uint32_t pt_w[(DL_CCM_BODY_MAX + 3u) / 4] = {0};
    uint32_t tag_w[4]; /* WL HAL пише повний блок, MIC = перші 8 байт */

    Build_DL_CCM_Nonce(Dl_Ccm_Frame_Did(frame), dlfc, nonce);
    Build_CCM_B0_From_Nonce(nonce, body_len, (uint8_t *)b0_w);
    memcpy(aad_w, frame, DL_CCM_AAD_LEN);
    memcpy(ct_w, &frame[DL_CCM_AAD_LEN], body_len);

    hcryp->Init.KeySize         = CRYP_KEYSIZE_128B;
    hcryp->Init.Algorithm       = CRYP_AES_CCM;
    hcryp->Init.DataType        = CRYP_DATATYPE_8B;
    hcryp->Init.pKey            = key_w;
    hcryp->Init.B0              = b0_w;
    hcryp->Init.Header          = aad_w;
    hcryp->Init.HeaderSize      = DL_CCM_AAD_LEN;
    hcryp->Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_BYTE;
    hcryp->Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_BYTE;

    int hal_ok = HAL_CRYP_Init(hcryp) == HAL_OK &&
                 HAL_CRYP_Decrypt(hcryp, ct_w, body_len, pt_w, 1000) == HAL_OK &&
                 HAL_CRYPEx_AESCCM_GenerateAuthTAG(hcryp, tag_w, 1000) == HAL_OK;

    /* Жодного висячого вказівника на цей стек-фрейм (дзеркало гігієни
     * Ccm_Run_Self_Test); ключ і ECB повертає викликач. */
    hcryp->Init.B0              = NULL;
    hcryp->Init.Header          = NULL;
    hcryp->Init.HeaderSize      = 0;
    hcryp->Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_WORD;
    hcryp->Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_WORD;

    if (!hal_ok) return DL_CCM_HAL_ERROR;
    if (!Fw2_Ccm_Tag_Equal((const uint8_t *)tag_w,
                           &frame[DL_CCM_AAD_LEN + body_len])) return DL_CCM_BAD_MIC;

    memcpy(body_out, pt_w, body_len);
    *dlfc_out = dlfc;
    return DL_CCM_OK;
}

#endif /* SILKEN_DOWNLINK_CCM_OPEN_H */
