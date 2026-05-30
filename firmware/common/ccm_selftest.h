/*
 * ccm_selftest.h — On-target AES-128-CCM Power-On Self-Test (POST).
 *
 * [FW.2 / ARCH.42 Variant B] Industrial bench-attestation for the silicon
 * CRYP CCM engine. Runs Known-Answer Tests (KAT, see ccm_kat_vectors.h)
 * through the LIVE `HAL_CRYPEx_AESCCM_*`:
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

/* One KAT through the live HAL: (1) encrypt must byte-match the oracle
 * ciphertext+tag, (2) decrypt must recover plaintext, (3) a flipped MIC
 * bit MUST be rejected (HAL_ERROR). Returns 1 on full pass, else 0.
 * key/nonce are copied into word-aligned buffers (the STM32 CRYP HAL
 * consumes uint32_t* and we must not assume the const tables are aligned). */
static inline int Ccm_Kat_Run_One(CRYP_HandleTypeDef *hcryp,
                                  const uint8_t key[16], const uint8_t nonce[12],
                                  const uint8_t aad[8], const uint8_t pt[8],
                                  const uint8_t ct[8], const uint8_t tag[8]) {
    uint32_t key_w[4];
    uint32_t nonce_w[3];   /* 12 bytes */
    uint8_t  aad_buf[FW2_CCM_AAD_LEN];
    memcpy(key_w, key, 16);
    memcpy(nonce_w, nonce, 12);
    memcpy(aad_buf, aad, FW2_CCM_AAD_LEN);

#define CCM_KAT_SETUP() do {                                  \
        hcryp->Init.KeySize    = CRYP_KEYSIZE_128B;           \
        hcryp->Init.Algorithm  = CRYP_AES_CCM;                \
        hcryp->Init.pKey       = key_w;                       \
        hcryp->Init.pInitVect  = nonce_w;                     \
        hcryp->Init.Header     = aad_buf;                     \
        hcryp->Init.HeaderSize = FW2_CCM_AAD_LEN;             \
    } while (0)

    /* (1) Encrypt KAT */
    uint8_t ct_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    CCM_KAT_SETUP();
    if (HAL_CRYPEx_AESCCM_Encrypt(hcryp, (uint8_t *)pt, FW2_CCM_PLAINTEXT_LEN, ct_tag, 1000) != HAL_OK) return 0;
    if (memcmp(ct_tag, ct, FW2_CCM_PLAINTEXT_LEN) != 0) return 0;
    if (memcmp(ct_tag + FW2_CCM_PLAINTEXT_LEN, tag, FW2_CCM_MIC_LEN) != 0) return 0;

    /* (2) Decrypt roundtrip */
    uint8_t ct_in[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    uint8_t recovered[FW2_CCM_PLAINTEXT_LEN];
    memcpy(ct_in, ct, FW2_CCM_PLAINTEXT_LEN);
    memcpy(ct_in + FW2_CCM_PLAINTEXT_LEN, tag, FW2_CCM_MIC_LEN);
    CCM_KAT_SETUP();
    if (HAL_CRYPEx_AESCCM_Decrypt(hcryp, ct_in, FW2_CCM_PLAINTEXT_LEN, recovered, 1000) != HAL_OK) return 0;
    if (memcmp(recovered, pt, FW2_CCM_PLAINTEXT_LEN) != 0) return 0;

    /* (3) Tamper-reject: flip one MIC bit → decrypt MUST fail */
    ct_in[FW2_CCM_PLAINTEXT_LEN] ^= 0x01;
    CCM_KAT_SETUP();
    if (HAL_CRYPEx_AESCCM_Decrypt(hcryp, ct_in, FW2_CCM_PLAINTEXT_LEN, recovered, 1000) != HAL_ERROR) return 0;

#undef CCM_KAT_SETUP
    return 1;
}

/* POST: golden vector + all extras. Returns count of FAILED vectors
 * (0 = attestation OK → safe to flip FW2_CCM_ENABLED). */
static inline int Ccm_Run_Self_Test(CRYP_HandleTypeDef *hcryp,
                                    ccm_selftest_report_fn report) {
    int failed = 0;

    /* Golden — nonce/AAD built from DID/FC exactly like the field TX path. */
    uint8_t g_nonce[FW2_CCM_NONCE_LEN];
    uint8_t g_aad[FW2_CCM_AAD_LEN];
    Build_CCM_Nonce(G_DID, G_FC, g_nonce);
    Build_CCM_AAD(G_DID, G_FC, g_aad);
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
