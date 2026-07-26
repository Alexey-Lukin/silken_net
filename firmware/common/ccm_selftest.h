// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ccm_selftest.h — On-target AES-128-CCM Power-On Self-Test (POST).
 *
 * [FW.2 / ARCH.42 Variant B] Industrial bench-attestation for the silicon
 * CRYP CCM engine. Runs Known-Answer Tests (KAT, see ccm_kat_vectors.h)
 * through the LIVE WL-true два-фазний флоу (B0 + HAL_CRYP_Encrypt/Decrypt +
 * HAL_CRYPEx_AESCCM_GenerateAuthTAG — F4-стильних AESCCM_Encrypt/Decrypt
 * у WL-HAL НЕ ІСНУЄ, знахідка 2026-07-03; invocation shape — lora_ccm.h):
 *   - on STM32WLE5JC  → exercises the real on-chip CRYP peripheral (the
 *                       genuine bench unknown: endianness, B0 formatting,
 *                       header feeding, silicon errata);
 *   - on host (CI)    → exercises the OpenSSL mock (verifies THIS self-test
 *                       logic + the vectors, so the bench step is trusted).
 *
 * FIPS-140-style usage: call Ccm_Run_Self_Test() at boot; if it returns
 * non-zero, REFUSE to enable CCM transmit (do not ship telemetry encrypted
 * by an engine that failed its KAT). A return of 0 is the attestation that
 * gates flipping `FW2_CCM_ENABLED` / `TELEMETRY_CCM_ENABLED`.
 *
 * Header-only (static inline) so it compiles into both the firmware build
 * and the host harness with no extra Makefile object. Requires a HAL
 * (real or hal_mock.h) + lora_ccm.h to be included by the caller first.
 */
#ifndef CCM_SELFTEST_H
#define CCM_SELFTEST_H

#include <string.h>
#include "lora_ccm.h"
#include "ccm_kat_vectors.h"

/* Caller-provided reporter: vector name + pass flag (1 = pass, 0 = fail).
 * On target wire it to UART/SWO; on host to printf. May be NULL. */
typedef void (*ccm_selftest_report_fn)(const char *name, int pass);

/* One KAT through the live HAL, WL-true two-phase:
 *   (1) encrypt payload-фаза + тег-фаза → ciphertext і MIC мусять
 *       байт-збігтися з oracle;
 *   (2) decrypt payload-фаза → plaintext збігається, тег-фаза →
 *       computed MIC збігається з oracle (на WL звірка = справа викликача);
 *   (3) tamper: біт у ciphertext → computed MIC МУСИТЬ розійтися з oracle
 *       (Fw2_Ccm_Tag_Equal = 0) — саме так польовий код відкидає підробку.
 * Returns 1 on full pass, else 0.
 * key/nonce/aad копіюються у word-aligned буфери (STM32 CRYP HAL споживає
 * uint32_t*, а const-таблиці векторів вирівнювання не обіцяють).
 * `hcryp` is an INJECTED handle (host harness passes a mock, target passes the
 * global &hcryp) — it deliberately mirrors the HAL global name for readability. */
// cppcheck-suppress shadowVariable
static inline int Ccm_Kat_Run_One(CRYP_HandleTypeDef *hcryp,
                                  const uint8_t key[16], const uint8_t nonce[12],
                                  const uint8_t aad[FW2_CCM_AAD_LEN],
                                  const uint8_t pt[FW2_CCM_PLAINTEXT_LEN],
                                  const uint8_t ct[FW2_CCM_PLAINTEXT_LEN],
                                  const uint8_t tag[FW2_CCM_MIC_LEN]) {
    uint32_t key_w[4];
    uint32_t b0_w[FW2_CCM_B0_LEN / 4];
    uint32_t aad_w[FW2_CCM_AAD_LEN / 4];
    memcpy(key_w, key, 16);
    Build_CCM_B0_From_Nonce(nonce, FW2_CCM_PLAINTEXT_LEN, (uint8_t *)b0_w);
    memcpy(aad_w, aad, FW2_CCM_AAD_LEN);

/* HAL_CRYP_Init у макро: мок — no-op, кремній защіпає конфіг у периферію. */
#define CCM_KAT_SETUP() do {                                        \
        hcryp->Init.KeySize         = CRYP_KEYSIZE_128B;            \
        hcryp->Init.Algorithm       = CRYP_AES_CCM;                 \
        hcryp->Init.DataType        = CRYP_DATATYPE_8B;             \
        hcryp->Init.pKey            = key_w;                        \
        hcryp->Init.B0              = b0_w;                         \
        hcryp->Init.Header          = aad_w;                        \
        hcryp->Init.HeaderSize      = FW2_CCM_AAD_LEN;              \
        hcryp->Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_BYTE;      \
        hcryp->Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_BYTE;    \
        if (HAL_CRYP_Init(hcryp) != HAL_OK) return 0;               \
    } while (0)

    /* (1) Encrypt KAT: payload-фаза + тег-фаза проти oracle. */
    uint32_t pt_w[(FW2_CCM_PLAINTEXT_LEN + 3u) / 4];
    uint32_t ct_w[(FW2_CCM_PLAINTEXT_LEN + 3u) / 4];
    uint32_t tag_w[4]; /* 16B: WL HAL пише повний блок, MIC = перші 8 байт */
    memcpy(pt_w, pt, FW2_CCM_PLAINTEXT_LEN);
    CCM_KAT_SETUP();
    if (HAL_CRYP_Encrypt(hcryp, pt_w, FW2_CCM_PLAINTEXT_LEN, ct_w, 1000) != HAL_OK) return 0;
    if (HAL_CRYPEx_AESCCM_GenerateAuthTAG(hcryp, tag_w, 1000) != HAL_OK) return 0;
    if (memcmp(ct_w, ct, FW2_CCM_PLAINTEXT_LEN) != 0) return 0;
    if (memcmp(tag_w, tag, FW2_CCM_MIC_LEN) != 0) return 0;

    /* (2) Decrypt roundtrip: plaintext назад + computed MIC == oracle. */
    uint32_t ct_in_w[(FW2_CCM_PLAINTEXT_LEN + 3u) / 4];
    uint32_t rec_w[(FW2_CCM_PLAINTEXT_LEN + 3u) / 4];
    memcpy(ct_in_w, ct, FW2_CCM_PLAINTEXT_LEN);
    CCM_KAT_SETUP();
    if (HAL_CRYP_Decrypt(hcryp, ct_in_w, FW2_CCM_PLAINTEXT_LEN, rec_w, 1000) != HAL_OK) return 0;
    if (HAL_CRYPEx_AESCCM_GenerateAuthTAG(hcryp, tag_w, 1000) != HAL_OK) return 0;
    if (memcmp(rec_w, pt, FW2_CCM_PLAINTEXT_LEN) != 0) return 0;
    if (!Fw2_Ccm_Tag_Equal((const uint8_t *)tag_w, tag)) return 0;

    /* (3) Tamper-reject: біт у ciphertext → computed MIC розходиться з
     * oracle. Провал звірки = єдиний привратник на WL (HAL сам не звіряє). */
    ct_in_w[0] ^= 0x01u;
    CCM_KAT_SETUP();
    if (HAL_CRYP_Decrypt(hcryp, ct_in_w, FW2_CCM_PLAINTEXT_LEN, rec_w, 1000) != HAL_OK) return 0;
    if (HAL_CRYPEx_AESCCM_GenerateAuthTAG(hcryp, tag_w, 1000) != HAL_OK) return 0;
    if (Fw2_Ccm_Tag_Equal((const uint8_t *)tag_w, tag)) return 0; /* збіг = провал KAT */

#undef CCM_KAT_SETUP
    return 1;
}

/* POST: golden vector + all extras. Returns count of FAILED vectors
 * (0 = attestation OK → safe to flip FW2_CCM_ENABLED).
 * `hcryp` injected (see Ccm_Kat_Run_One) — mirrors the HAL global name. */
// cppcheck-suppress shadowVariable
static inline int Ccm_Run_Self_Test(CRYP_HandleTypeDef *hcryp,
                                    ccm_selftest_report_fn report) {
    int failed = 0;

    /* Golden — nonce/AAD built from DID/gossip/FC exactly like field TX. */
    uint8_t g_nonce[FW2_CCM_NONCE_LEN];
    uint8_t g_aad[FW2_CCM_AAD_LEN];
    Build_CCM_Nonce(G_DID, G_FC, g_nonce);
    Build_CCM_AAD(G_DID, G_GOSSIP, G_FC, g_aad);
    int g_pass = Ccm_Kat_Run_One(hcryp, G_ZERO_KEY, g_nonce, g_aad, G_PT, G_CT, G_TAG);
    if (!g_pass) failed++;
    if (report) report("golden: zero-key DID=01020304 FC=5", g_pass);

    for (unsigned i = 0; i < CCM_KAT_EXTRA_COUNT; i++) {
        const CcmKatVector *v = &CCM_KAT_EXTRA[i];
        int pass = Ccm_Kat_Run_One(hcryp, v->key, v->nonce, v->aad, v->pt, v->ct, v->tag);
        if (!pass) failed++;
        if (report) report(v->name, pass);
    }
    return failed;
}

#endif /* CCM_SELFTEST_H */
