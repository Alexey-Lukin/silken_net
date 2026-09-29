// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_downlink_ccm.c — адресні команди Rails → Солдат під AES-128-CCM
 *                       (downlink-wire-ревізія, docs/03_05 §2.5).
 *
 * Build & run: make -C firmware/test downlink_ccm
 *
 * Golden-вектори — ccm_kat_vectors.h (CCM_KAT_DOWNLINK), ті самі кадри пінить
 * Rails-бік (spec/services/cryptography/lora_ccm_spec.rb), тож зелене тут і
 * там = прошивка ≡ OpenSSL ≡ бекенд байт-у-байт. Мок — WL-true двофазний
 * флоу (hal_mock.h), як у test_ccm.c.
 */
#define HAL_MOCK_CCM_ENABLED

#include "hal_mock.h"
#include "../common/ccm_selftest.h"
#include <stdio.h>
#include <string.h>

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        fprintf(stderr, "FAIL %s:%d  expected %lu got %lu\n", \
                __FILE__, __LINE__, (unsigned long)(b), (unsigned long)(a)); \
        return 1; \
    } \
} while (0)

#define ASSERT_MEM_EQ(a, b, n) do { \
    if (memcmp((a), (b), (n)) != 0) { \
        fprintf(stderr, "FAIL %s:%d  memory mismatch (%zu bytes)\n", \
                __FILE__, __LINE__, (size_t)(n)); \
        return 1; \
    } \
} while (0)

static CRYP_HandleTypeDef hcryp;

static DlCcmResult Open_Vector_Frame(const CcmDownlinkKatVector *v, const uint8_t *frame,
                                     uint32_t self_did, uint32_t last_dlfc,
                                     uint8_t body[DL_CCM_BODY_MAX], uint32_t *dlfc)
{
    uint32_t key_w[4];
    memcpy(key_w, v->key, 16);
    return Dl_Ccm_Open(&hcryp, key_w, frame, Dl_Ccm_Frame_Len(frame[0]),
                       self_did, last_dlfc, body, dlfc);
}

static int test_frame_lengths_by_opcode(void)
{
    ASSERT_EQ(Dl_Ccm_Frame_Len(DL_CCM_OP_ROTATE_KEY), 17);
    ASSERT_EQ(Dl_Ccm_Frame_Len(DL_CCM_OP_THRESHOLDS), 23);
    /* Кластерні кадри (маяк, OTA, печатка) командами не є — лишаються ECB. */
    ASSERT_EQ(Dl_Ccm_Frame_Len(0x99), 0);
    ASSERT_EQ(Dl_Ccm_Frame_Len(0x9B), 0);
    ASSERT_EQ(Dl_Ccm_Frame_Len(0x9C), 0);
    ASSERT_EQ(Dl_Ccm_Frame_Len(0x9D), 0); /* RETIRED з HW.30 */
    /* 16 Б не збігається з жодною командною довжиною: розрізнення з ECB
     * за довжиною не має перетину. */
    uint8_t f[DL_CCM_FRAME_MAX] = { DL_CCM_OP_ROTATE_KEY };
    ASSERT_EQ(Dl_Ccm_Frame_Well_Formed(f, 16), 0);
    ASSERT_EQ(Dl_Ccm_Frame_Well_Formed(f, 17), 1);
    ASSERT_EQ(Dl_Ccm_Frame_Well_Formed(f, 18), 0);
    f[0] = DL_CCM_OP_THRESHOLDS;
    ASSERT_EQ(Dl_Ccm_Frame_Well_Formed(f, 17), 0);
    ASSERT_EQ(Dl_Ccm_Frame_Well_Formed(f, 23), 1);
    printf("  test_frame_lengths_by_opcode                               ✅\n");
    return 0;
}

static int test_nonce_differs_from_uplink_only_in_direction_byte(void)
{
    uint8_t dl[FW2_CCM_NONCE_LEN], ul[FW2_CCM_NONCE_LEN];
    Build_DL_CCM_Nonce(0x01020304u, 5u, dl);
    Build_CCM_Nonce(0x01020304u, 5u, ul);
    ASSERT_MEM_EQ(dl, ul, 8);
    ASSERT_EQ(ul[8], 0x00);
    ASSERT_EQ(dl[8], DL_CCM_DIRECTION_BYTE);
    ASSERT_MEM_EQ(&dl[9], &ul[9], 3);
    printf("  test_nonce_differs_from_uplink_only_in_direction_byte      ✅\n");
    return 0;
}

static int test_golden_aad_is_the_frame_header(void)
{
    for (unsigned i = 0; i < CCM_KAT_DOWNLINK_COUNT; i++) {
        const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[i];
        uint8_t aad[DL_CCM_AAD_LEN];
        Build_DL_CCM_AAD(v->frame[0], v->did, v->dlfc, aad);
        ASSERT_MEM_EQ(aad, v->frame, DL_CCM_AAD_LEN);
        ASSERT_EQ(Dl_Ccm_Frame_Did(v->frame), v->did);
        ASSERT_EQ(Dl_Ccm_Frame_Dlfc_Lsb(v->frame), v->dlfc & 0xFFFFu);
    }
    printf("  test_golden_aad_is_the_frame_header                        ✅\n");
    return 0;
}

/* Шифрування тим самим WL-флоу дає рівно кадр Rails-оракула. */
static int test_golden_seal_parity_with_rails_oracle(void)
{
    for (unsigned i = 0; i < CCM_KAT_DOWNLINK_COUNT; i++) {
        const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[i];
        const uint8_t n = Dl_Ccm_Body_Len(v->frame[0]);
        uint8_t nonce[FW2_CCM_NONCE_LEN];
        Build_DL_CCM_Nonce(v->did, v->dlfc, nonce);
        ASSERT_EQ(Ccm_Kat_Run_One(&hcryp, v->key, nonce, v->frame, DL_CCM_AAD_LEN,
                                  v->body, &v->frame[DL_CCM_AAD_LEN], n,
                                  &v->frame[DL_CCM_AAD_LEN + n]), 1);
    }
    printf("  test_golden_seal_parity_with_rails_oracle                  ✅\n");
    return 0;
}

static int test_open_golden_frames(void)
{
    for (unsigned i = 0; i < CCM_KAT_DOWNLINK_COUNT; i++) {
        const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[i];
        uint8_t  body[DL_CCM_BODY_MAX] = {0};
        uint32_t dlfc = 0;
        ASSERT_EQ(Open_Vector_Frame(v, v->frame, v->did, v->dlfc - 1u, body, &dlfc), DL_CCM_OK);
        ASSERT_EQ(dlfc, v->dlfc);
        ASSERT_MEM_EQ(body, v->body, Dl_Ccm_Body_Len(v->frame[0]));
        /* Гігієна: жодного вказівника на мертвий стек-фрейм Dl_Ccm_Open. */
        ASSERT_EQ(hcryp.Init.B0 == NULL, 1);
        ASSERT_EQ(hcryp.Init.Header == NULL, 1);
        ASSERT_EQ(hcryp.Init.DataWidthUnit, CRYP_DATAWIDTHUNIT_WORD);
        ASSERT_EQ(hcryp.Init.HeaderWidthUnit, CRYP_HEADERWIDTHUNIT_WORD);
    }
    printf("  test_open_golden_frames                                    ✅\n");
    return 0;
}

/* Повтор уже прийнятого кадру (last = його DLFC) чи старішого реконструюється
 * в інше значення → інший нонс → MIC; порівняння лічильників тут немає. */
static int test_replay_fails_on_mic(void)
{
    const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[0];
    uint8_t  body[DL_CCM_BODY_MAX];
    uint32_t dlfc = 0xDEADu;
    ASSERT_EQ(Open_Vector_Frame(v, v->frame, v->did, v->dlfc, body, &dlfc), DL_CCM_BAD_MIC);
    ASSERT_EQ(Open_Vector_Frame(v, v->frame, v->did, v->dlfc + 7u, body, &dlfc), DL_CCM_BAD_MIC);
    ASSERT_EQ(dlfc, 0xDEADu); /* відмова стану не чіпає */
    printf("  test_replay_fails_on_mic                                   ✅\n");
    return 0;
}

static int test_foreign_did_rejected_before_crypto(void)
{
    const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[1];
    uint8_t  body[DL_CCM_BODY_MAX];
    uint32_t dlfc = 0;
    ASSERT_EQ(Open_Vector_Frame(v, v->frame, v->did ^ 1u, v->dlfc - 1u, body, &dlfc),
              DL_CCM_NOT_MINE);
    printf("  test_foreign_did_rejected_before_crypto                    ✅\n");
    return 0;
}

static int test_every_region_is_authenticated(void)
{
    const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[1];
    const uint8_t len = Dl_Ccm_Frame_Len(v->frame[0]);
    uint8_t  body[DL_CCM_BODY_MAX];
    uint32_t dlfc = 0;
    /* DLFC_lsb (AAD), кожен байт шифротексту й MIC. DID-біт — чужий кадр
     * (попередній тест), опкод-біт — інша довжина (MALFORMED нижче). */
    for (uint8_t pos = DL_CCM_DLFC_OFFSET; pos < len; pos++) {
        uint8_t frame[DL_CCM_FRAME_MAX];
        memcpy(frame, v->frame, len);
        frame[pos] ^= 0x01u;
        DlCcmResult r = Open_Vector_Frame(v, frame, v->did, 0x0000FFF0u, body, &dlfc);
        if (r != DL_CCM_BAD_MIC) {
            fprintf(stderr, "FAIL %s:%d  byte %u tamper → %d\n", __FILE__, __LINE__, pos, r);
            return 1;
        }
    }
    uint8_t frame[DL_CCM_FRAME_MAX];
    memcpy(frame, v->frame, len);
    frame[0] = DL_CCM_OP_ROTATE_KEY; /* 0x9A→0x9E: довжина вже не та */
    uint32_t key_w[4];
    memcpy(key_w, v->key, 16);
    ASSERT_EQ(Dl_Ccm_Open(&hcryp, key_w, frame, len, v->did, 0u, body, &dlfc), DL_CCM_MALFORMED);
    printf("  test_every_region_is_authenticated                         ✅\n");
    return 0;
}

static int test_wrong_key_rejected(void)
{
    const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[0];
    uint32_t key_w[4];
    memcpy(key_w, v->key, 16);
    key_w[3] ^= 0x80000000u;
    uint8_t  body[DL_CCM_BODY_MAX];
    uint32_t dlfc = 0;
    ASSERT_EQ(Dl_Ccm_Open(&hcryp, key_w, v->frame, Dl_Ccm_Frame_Len(v->frame[0]),
                          v->did, v->dlfc - 1u, body, &dlfc), DL_CCM_BAD_MIC);
    printf("  test_wrong_key_rejected                                    ✅\n");
    return 0;
}

/* Той самий (ключ, DID, лічильник, AAD, тіло), запечатаний АПЛІНК-нонсом
 * (байт напрямку 0), як downlink не відкривається: простори нонсів розведено. */
static int test_uplink_direction_nonce_does_not_open(void)
{
    const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[1];
    const uint8_t n = Dl_Ccm_Body_Len(v->frame[0]);
    uint32_t key_w[4], b0_w[4], aad_w[2] = {0}, pt_w[2] = {0}, ct_w[2] = {0}, tag_w[4];
    uint8_t  nonce[FW2_CCM_NONCE_LEN];
    memcpy(key_w, v->key, 16);
    Build_CCM_Nonce(v->did, v->dlfc, nonce);
    Build_CCM_B0_From_Nonce(nonce, n, (uint8_t *)b0_w);
    memcpy(aad_w, v->frame, DL_CCM_AAD_LEN);
    memcpy(pt_w, v->body, n);
    hcryp.Init.KeySize = CRYP_KEYSIZE_128B;
    hcryp.Init.Algorithm = CRYP_AES_CCM;
    hcryp.Init.DataType = CRYP_DATATYPE_8B;
    hcryp.Init.pKey = key_w;
    hcryp.Init.B0 = b0_w;
    hcryp.Init.Header = aad_w;
    hcryp.Init.HeaderSize = DL_CCM_AAD_LEN;
    hcryp.Init.DataWidthUnit = CRYP_DATAWIDTHUNIT_BYTE;
    hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_BYTE;
    ASSERT_EQ(HAL_CRYP_Encrypt(&hcryp, pt_w, n, ct_w, 1000), HAL_OK);
    ASSERT_EQ(HAL_CRYPEx_AESCCM_GenerateAuthTAG(&hcryp, tag_w, 1000), HAL_OK);

    uint8_t frame[DL_CCM_FRAME_MAX];
    memcpy(frame, v->frame, DL_CCM_AAD_LEN);
    memcpy(&frame[DL_CCM_AAD_LEN], ct_w, n);
    memcpy(&frame[DL_CCM_AAD_LEN + n], tag_w, DL_CCM_MIC_LEN);
    uint8_t  body[DL_CCM_BODY_MAX];
    uint32_t dlfc = 0;
    ASSERT_EQ(Open_Vector_Frame(v, frame, v->did, v->dlfc - 1u, body, &dlfc), DL_CCM_BAD_MIC);
    printf("  test_uplink_direction_nonce_does_not_open                  ✅\n");
    return 0;
}

static int test_dlfc_reconstruction(void)
{
    ASSERT_EQ(Dl_Ccm_Reconstruct_Dlfc(0u, 1u), 1u);
    ASSERT_EQ(Dl_Ccm_Reconstruct_Dlfc(0x0000FFFFu, 0x0002u), 0x00010002u);  /* перенос */
    ASSERT_EQ(Dl_Ccm_Reconstruct_Dlfc(0x00010002u, 0x0002u), 0x00020002u);  /* рівний → наступне вікно */
    ASSERT_EQ(Dl_Ccm_Reconstruct_Dlfc(0x00010005u, 0x0003u), 0x00020003u);
    ASSERT_EQ(Dl_Ccm_Reconstruct_Dlfc(0x00010005u, 0x0006u), 0x00010006u);
    ASSERT_EQ(Dl_Ccm_Reconstruct_Dlfc(0xFFFF0005u, 0x0006u), 0xFFFF0006u);
    ASSERT_EQ(Dl_Ccm_Reconstruct_Dlfc(0xFFFF0005u, 0x0003u), 0u);           /* вичерпано */
    printf("  test_dlfc_reconstruction                                   ✅\n");
    return 0;
}

/* Стеля з шапки downlink_ccm.h, пінована: розрив ≥ 65536 реконструюється в
 * хибне вікно й падає на MIC; у межах вікна той самий кадр відкривається. */
static int test_gap_ceiling_is_named_not_silent(void)
{
    const CcmDownlinkKatVector *v = &CCM_KAT_DOWNLINK[0]; /* DLFC 0x00010002 */
    uint8_t  body[DL_CCM_BODY_MAX];
    uint32_t dlfc = 0;
    ASSERT_EQ(Open_Vector_Frame(v, v->frame, v->did, 0u, body, &dlfc), DL_CCM_BAD_MIC);
    ASSERT_EQ(Open_Vector_Frame(v, v->frame, v->did, 0x0000FFFFu, body, &dlfc), DL_CCM_OK);
    ASSERT_EQ(dlfc, 0x00010002u);
    ASSERT_EQ(Open_Vector_Frame(v, v->frame, v->did, 0xFFFF0005u, body, &dlfc), DL_CCM_DLFC_EXHAUSTED);
    printf("  test_gap_ceiling_is_named_not_silent                       ✅\n");
    return 0;
}

/* Тіла команд: little-endian поля старого каркаса, байти — golden Rails. */
static int test_rotate_key_body(void)
{
    ASSERT_EQ(Dl_Cmd_Rotate_Target(CCM_KAT_DOWNLINK[0].body), 3);
    const uint8_t le[2] = { 0x34, 0x12 };
    ASSERT_EQ(Dl_Cmd_Rotate_Target(le), 0x1234);
    printf("  test_rotate_key_body                                       ✅\n");
    return 0;
}

#define RUN(test) do { \
    if (test()) { failed++; } else { passed++; } \
} while (0)

int main(void)
{
    int passed = 0, failed = 0;
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.17 · 03_05 §2.5] Downlink-CCM: адресні команди Rails → Солдат\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    RUN(test_frame_lengths_by_opcode);
    RUN(test_nonce_differs_from_uplink_only_in_direction_byte);
    RUN(test_golden_aad_is_the_frame_header);
    RUN(test_golden_seal_parity_with_rails_oracle);
    RUN(test_open_golden_frames);
    RUN(test_replay_fails_on_mic);
    RUN(test_foreign_did_rejected_before_crypto);
    RUN(test_every_region_is_authenticated);
    RUN(test_wrong_key_rejected);
    RUN(test_uplink_direction_nonce_does_not_open);
    RUN(test_dlfc_reconstruction);
    RUN(test_gap_ceiling_is_named_not_silent);
    RUN(test_rotate_key_body);

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d   Failed: %d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
