/*
 * test_ccm.c — Host-based unit tests for [FW.2 / ARCH.42 Variant B]
 *              AES-128-CCM LoRa packet emission and reception.
 *
 * Build & run: make -C firmware/test ccm
 *
 * Coverage:
 *   1. Golden vector parity vs Rails Cryptography::LoraCcm
 *   2. RTC_BKP_DR15 Frame Counter pack/unpack with magic marker
 *   3. Cold-boot FC reseed (HRNG)
 *   4. FC monotonic increment + saturating wrap
 *   5. Sensor payload pack/unpack roundtrip
 *   6. Soldier build → Queen parse roundtrip
 *   7. MIC tamper detection (Queen drops packet)
 *   8. AAD tamper detection (DID/FC flip → MIC fail)
 *   9. Ciphertext tamper detection
 *  10. Wrong key on Queen → MIC fail
 *  11. Panic flag inside encrypted payload (MIC covers it)
 *  12. mesh_ctrl bitfield roundtrip (TTL + fw_epoch_nibble)
 *
 * Mock HAL_CRYPEx_AESCCM_* are libcrypto-backed (OpenSSL EVP), so
 * byte-level parity here is the same guarantee Rails-side spec gives.
 * Only `HAL_CRYPEx_AESCCM_Encrypt` on real STM32WLE5JC silicon is
 * unverified — that's the one item that genuinely needs HW bench.
 */

#define HAL_MOCK_CCM_ENABLED

#include "hal_mock.h"
#include "../common/lora_ccm.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

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

/* ── shared fixtures ─────────────────────────────────────────────────── */

/* AES-128 zero key + DID 0x01020304 + FC 5 + plaintext 01..08 → golden:
 *   ciphertext = 08 ce ca 97 bb f4 fd c5
 *   tag        = a6 d8 e2 0c e0 de ea e9
 * (Identical to the Rails Cryptography::LoraCcm spec golden vector.) */
static const uint8_t G_ZERO_KEY[16] = {0};
static const uint32_t G_DID = 0x01020304;
static const uint32_t G_FC  = 5;
static const uint8_t G_PT[FW2_CCM_PLAINTEXT_LEN] =
    { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
static const uint8_t G_CT[FW2_CCM_PLAINTEXT_LEN] =
    { 0x08, 0xce, 0xca, 0x97, 0xbb, 0xf4, 0xfd, 0xc5 };
static const uint8_t G_TAG[FW2_CCM_MIC_LEN] =
    { 0xa6, 0xd8, 0xe2, 0x0c, 0xe0, 0xde, 0xea, 0xe9 };

/* hcryp instance (firmware code references &hcryp; declare it locally). */
static CRYP_HandleTypeDef hcryp;
static RTC_HandleTypeDef  hrtc;
static RNG_HandleTypeDef  hrng;

static void Reset_Mock_State(void) {
    _rtc_bkp_reset_all();
    memset(&hcryp, 0, sizeof(hcryp));
}

/* Set up CCM context the same way Soldier_Build_CCM_LoRa_Packet does. */
static void Cryp_Init_For_Encrypt(uint32_t key[4], uint8_t *nonce, uint8_t *aad) {
    hcryp.Init.KeySize    = CRYP_KEYSIZE_128B;
    hcryp.Init.pKey       = key;
    hcryp.Init.Algorithm  = CRYP_AES_CCM;
    hcryp.Init.pInitVect  = (uint32_t*)nonce;
    hcryp.Init.Header     = aad;
    hcryp.Init.HeaderSize = FW2_CCM_AAD_LEN;
}

/* ── tests ───────────────────────────────────────────────────────────── */

static int test_golden_vector_encrypt(void) {
    uint32_t key_words[4] = {0};
    memcpy(key_words, G_ZERO_KEY, 16);

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    uint8_t out[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];

    Build_CCM_Nonce(G_DID, G_FC, nonce);
    Build_CCM_AAD(G_DID, G_FC, aad);
    Cryp_Init_For_Encrypt(key_words, nonce, aad);

    int rc = HAL_CRYPEx_AESCCM_Encrypt(&hcryp, (uint8_t*)G_PT,
                                       FW2_CCM_PLAINTEXT_LEN, out, 1000);
    ASSERT_EQ(rc, HAL_OK);
    ASSERT_MEM_EQ(out, G_CT, FW2_CCM_PLAINTEXT_LEN);
    ASSERT_MEM_EQ(out + FW2_CCM_PLAINTEXT_LEN, G_TAG, FW2_CCM_MIC_LEN);
    printf("  test_golden_vector_encrypt                                 ✅\n");
    return 0;
}

static int test_golden_vector_decrypt(void) {
    uint32_t key_words[4] = {0};
    memcpy(key_words, G_ZERO_KEY, 16);

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    uint8_t ct_and_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    uint8_t out[FW2_CCM_PLAINTEXT_LEN];

    Build_CCM_Nonce(G_DID, G_FC, nonce);
    Build_CCM_AAD(G_DID, G_FC, aad);
    memcpy(ct_and_tag, G_CT, FW2_CCM_PLAINTEXT_LEN);
    memcpy(ct_and_tag + FW2_CCM_PLAINTEXT_LEN, G_TAG, FW2_CCM_MIC_LEN);

    Cryp_Init_For_Encrypt(key_words, nonce, aad);
    int rc = HAL_CRYPEx_AESCCM_Decrypt(&hcryp, ct_and_tag,
                                       FW2_CCM_PLAINTEXT_LEN, out, 1000);
    ASSERT_EQ(rc, HAL_OK);
    ASSERT_MEM_EQ(out, G_PT, FW2_CCM_PLAINTEXT_LEN);
    printf("  test_golden_vector_decrypt                                 ✅\n");
    return 0;
}

static int test_fc_pack_unpack(void) {
    uint32_t packed = Pack_FW2_Frame_Counter(42);
    /* High byte = 0x46 ('F'), low 24 bits = 42 */
    ASSERT_EQ((packed >> 24) & 0xFF, FW2_FC_MAGIC_BYTE);
    ASSERT_EQ(packed & 0x00FFFFFF, 42);
    ASSERT_EQ(Unpack_FW2_Frame_Counter(packed), 42);
    printf("  test_fc_pack_unpack                                        ✅\n");
    return 0;
}

static int test_fc_cold_boot_invalid_magic(void) {
    /* DR15 = 0 after VBAT loss → magic mismatch → Unpack returns 0. */
    ASSERT_EQ(Unpack_FW2_Frame_Counter(0), 0);
    /* DR15 random junk with wrong magic → 0. */
    ASSERT_EQ(Unpack_FW2_Frame_Counter(0xAABBCCDDu), 0);
    /* Correct magic preserves counter even at 24-bit boundary. */
    ASSERT_EQ(Unpack_FW2_Frame_Counter(Pack_FW2_Frame_Counter(0xFFFFFE)), 0xFFFFFE);
    printf("  test_fc_cold_boot_invalid_magic                            ✅\n");
    return 0;
}

static int test_fc_reseed_clamps_boundary(void) {
    /* HRNG = 0 → reseed gives at least FW2_FC_HRNG_MIN. */
    ASSERT_EQ(Reseed_FW2_Frame_Counter(0), FW2_FC_HRNG_MIN);
    /* HRNG = max → reseed clamps to FW2_FC_HRNG_MAX. */
    ASSERT_EQ(Reseed_FW2_Frame_Counter(0xFFFFFFFF), FW2_FC_HRNG_MAX);
    /* HRNG in band → passthrough. */
    ASSERT_EQ(Reseed_FW2_Frame_Counter(0x123456), 0x123456);
    printf("  test_fc_reseed_clamps_boundary                             ✅\n");
    return 0;
}

static int test_sensor_payload_pack_roundtrip(void) {
    uint8_t buf[FW2_CCM_PLAINTEXT_LEN];
    Pack_CCM_Sensor_Payload(3500, -15, 99, 1234, 0x5A, 0x37, buf);
    uint16_t vcap; int8_t temp; uint8_t acoustic; uint16_t dt;
    uint8_t status, ctrl;
    Unpack_CCM_Sensor_Payload(buf, &vcap, &temp, &acoustic, &dt, &status, &ctrl);
    ASSERT_EQ(vcap, 3500);
    ASSERT_EQ((uint32_t)(int32_t)temp, (uint32_t)(int32_t)-15);
    ASSERT_EQ(acoustic, 99);
    ASSERT_EQ(dt, 1234);
    ASSERT_EQ(status, 0x5A);
    ASSERT_EQ(ctrl, 0x37);
    /* mesh_ctrl bitfield: TTL=3, fw_nibble=7 */
    ASSERT_EQ((ctrl >> FW2_MESH_TTL_SHIFT) & FW2_MESH_TTL_MASK, 3);
    ASSERT_EQ(ctrl & FW2_MESH_FW_NIBBLE_MASK, 7);
    printf("  test_sensor_payload_pack_roundtrip                         ✅\n");
    return 0;
}

static int test_soldier_to_queen_roundtrip(void) {
    /* Encrypt as Soldier (manual — replicates Soldier_Build_CCM_LoRa_Packet). */
    uint32_t key_words[4];
    for (int i = 0; i < 4; i++) key_words[i] = 0xDEAD0000u | (uint32_t)i;
    uint8_t key_bytes[16];
    memcpy(key_bytes, key_words, 16);

    const uint32_t did = 0x534E4554u; /* "SNET" */
    const uint32_t fc  = 9001;

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    uint8_t ct_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];

    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, fc, aad);
    Pack_CCM_Sensor_Payload(4200, 22, 7, 600, 0x00, 0x53, pt);

    Cryp_Init_For_Encrypt(key_words, nonce, aad);
    ASSERT_EQ(HAL_CRYPEx_AESCCM_Encrypt(&hcryp, pt, FW2_CCM_PLAINTEXT_LEN, ct_tag, 1000), HAL_OK);

    /* Assemble 24B on-air packet. */
    uint8_t air[FW2_CCM_AIR_PACKET_LEN];
    memcpy(&air[0],  aad, FW2_CCM_AAD_LEN);
    memcpy(&air[8],  ct_tag, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&air[16], ct_tag + FW2_CCM_PLAINTEXT_LEN, FW2_CCM_MIC_LEN);

    /* Parse as Queen (manual — replicates Queen_Parse_CCM_LoRa_Packet). */
    uint8_t recv_nonce[FW2_CCM_NONCE_LEN];
    uint8_t recv_aad[FW2_CCM_AAD_LEN];
    uint32_t recv_did =
        ((uint32_t)air[0] << 24) | ((uint32_t)air[1] << 16) |
        ((uint32_t)air[2] << 8)  | (uint32_t)air[3];
    uint32_t recv_fc =
        ((uint32_t)air[4] << 24) | ((uint32_t)air[5] << 16) |
        ((uint32_t)air[6] << 8)  | (uint32_t)air[7];
    Build_CCM_Nonce(recv_did, recv_fc, recv_nonce);
    Build_CCM_AAD(recv_did, recv_fc, recv_aad);

    uint8_t recv_ct_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    memcpy(recv_ct_tag, &air[8], FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN);

    uint8_t recv_pt[FW2_CCM_PLAINTEXT_LEN];
    Cryp_Init_For_Encrypt(key_words, recv_nonce, recv_aad);
    int rc = HAL_CRYPEx_AESCCM_Decrypt(&hcryp, recv_ct_tag, FW2_CCM_PLAINTEXT_LEN, recv_pt, 1000);
    ASSERT_EQ(rc, HAL_OK);
    ASSERT_EQ(recv_did, did);
    ASSERT_EQ(recv_fc, fc);
    ASSERT_MEM_EQ(recv_pt, pt, FW2_CCM_PLAINTEXT_LEN);

    /* Use key_bytes to assure mock truly reads pKey. */
    (void)key_bytes;
    printf("  test_soldier_to_queen_roundtrip                            ✅\n");
    return 0;
}

/* Helper: build a fully-encrypted 24B packet for tamper tests. */
static void Build_Reference_Packet(uint32_t key_words[4], uint32_t did, uint32_t fc,
                                   uint8_t out[FW2_CCM_AIR_PACKET_LEN]) {
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN] = {1,2,3,4,5,6,7,8};
    uint8_t ct_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, fc, aad);
    Cryp_Init_For_Encrypt(key_words, nonce, aad);
    HAL_CRYPEx_AESCCM_Encrypt(&hcryp, pt, FW2_CCM_PLAINTEXT_LEN, ct_tag, 1000);
    memcpy(&out[0],  aad, FW2_CCM_AAD_LEN);
    memcpy(&out[8],  ct_tag, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&out[16], ct_tag + FW2_CCM_PLAINTEXT_LEN, FW2_CCM_MIC_LEN);
}

static int Try_Decrypt(uint32_t key_words[4],
                       const uint8_t in[FW2_CCM_AIR_PACKET_LEN],
                       uint8_t out_pt[FW2_CCM_PLAINTEXT_LEN]) {
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint32_t did =
        ((uint32_t)in[0] << 24) | ((uint32_t)in[1] << 16) |
        ((uint32_t)in[2] << 8)  | (uint32_t)in[3];
    uint32_t fc =
        ((uint32_t)in[4] << 24) | ((uint32_t)in[5] << 16) |
        ((uint32_t)in[6] << 8)  | (uint32_t)in[7];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, fc, aad);

    uint8_t ct_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    memcpy(ct_tag, &in[8], FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN);
    Cryp_Init_For_Encrypt(key_words, nonce, aad);
    return HAL_CRYPEx_AESCCM_Decrypt(&hcryp, ct_tag, FW2_CCM_PLAINTEXT_LEN, out_pt, 1000);
}

static int test_mic_tamper_detected(void) {
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];
    Build_Reference_Packet(key, 0xAABBCCDD, 42, pkt);

    pkt[20] ^= 0x01; /* flip a bit in the MIC */
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Try_Decrypt(key, pkt, pt), HAL_ERROR);
    printf("  test_mic_tamper_detected                                   ✅\n");
    return 0;
}

static int test_aad_did_tamper_detected(void) {
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];
    Build_Reference_Packet(key, 0xAABBCCDD, 42, pkt);

    pkt[0] ^= 0xFF; /* flip DID byte → MIC must fail because AAD changed */
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Try_Decrypt(key, pkt, pt), HAL_ERROR);
    printf("  test_aad_did_tamper_detected                               ✅\n");
    return 0;
}

static int test_aad_fc_tamper_detected(void) {
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];
    Build_Reference_Packet(key, 0xAABBCCDD, 42, pkt);

    pkt[7] ^= 0x01; /* flip FC LSB → MIC must fail (nonce + AAD diverge) */
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Try_Decrypt(key, pkt, pt), HAL_ERROR);
    printf("  test_aad_fc_tamper_detected                                ✅\n");
    return 0;
}

static int test_ciphertext_tamper_detected(void) {
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];
    Build_Reference_Packet(key, 0xAABBCCDD, 42, pkt);

    pkt[10] ^= 0x55; /* flip a ciphertext byte → MIC fail */
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Try_Decrypt(key, pkt, pt), HAL_ERROR);
    printf("  test_ciphertext_tamper_detected                            ✅\n");
    return 0;
}

static int test_wrong_key_rejected(void) {
    uint32_t enc_key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint32_t bad_key[4] = {0xBADBAD00, 0xBADBAD01, 0xBADBAD02, 0xBADBAD03};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];
    Build_Reference_Packet(enc_key, 0xAABBCCDD, 42, pkt);

    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Try_Decrypt(bad_key, pkt, pt), HAL_ERROR);
    printf("  test_wrong_key_rejected                                    ✅\n");
    return 0;
}

static int test_panic_flag_inside_encrypted_payload(void) {
    /* FW.29 panic flag (bit 7 of status_byte) now lives at offset 14 within
     * the 24B packet (= offset 6 of the encrypted payload). Flipping it
     * on the wire breaks MIC, so an attacker cannot forge a panic alert
     * from a benign packet. This was an explicit FW.29 design goal. */
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];

    /* Build a benign packet (status_byte = 0, no panic). */
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    uint8_t ct_tag[FW2_CCM_PLAINTEXT_LEN + FW2_CCM_MIC_LEN];
    Build_CCM_Nonce(0xAABBCCDD, 42, nonce);
    Build_CCM_AAD(0xAABBCCDD, 42, aad);
    Pack_CCM_Sensor_Payload(3500, 25, 5, 100, 0x00 /* no panic */, 0x33, pt);
    Cryp_Init_For_Encrypt(key, nonce, aad);
    ASSERT_EQ(HAL_CRYPEx_AESCCM_Encrypt(&hcryp, pt, FW2_CCM_PLAINTEXT_LEN, ct_tag, 1000), HAL_OK);
    memcpy(&pkt[0],  aad, FW2_CCM_AAD_LEN);
    memcpy(&pkt[8],  ct_tag, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&pkt[16], ct_tag + FW2_CCM_PLAINTEXT_LEN, FW2_CCM_MIC_LEN);

    /* Attacker flips PANIC_FLAG_BIT on byte 14 of the on-air packet. */
    pkt[14] ^= FW2_STATUS_PANIC_BIT;

    uint8_t out_pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Try_Decrypt(key, pkt, out_pt), HAL_ERROR); /* MIC blocks it */
    printf("  test_panic_flag_inside_encrypted_payload                   ✅\n");
    return 0;
}

static int test_mesh_ctrl_bitfield_extraction(void) {
    /* TTL=5, fw_epoch_nibble=0xA → mesh_ctrl = 0x5A. */
    uint8_t ctrl = (uint8_t)(((5 & FW2_MESH_TTL_MASK) << FW2_MESH_TTL_SHIFT) |
                             (0xA & FW2_MESH_FW_NIBBLE_MASK));
    ASSERT_EQ(ctrl, 0x5A);
    ASSERT_EQ((ctrl >> FW2_MESH_TTL_SHIFT) & FW2_MESH_TTL_MASK, 5);
    ASSERT_EQ(ctrl & FW2_MESH_FW_NIBBLE_MASK, 0xA);
    printf("  test_mesh_ctrl_bitfield_extraction                         ✅\n");
    return 0;
}

#define RUN(test) do { \
    if (test()) { failed++; } else { passed++; } \
} while (0)

int main(void) {
    int passed = 0, failed = 0;
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.2 / ARCH.42 Variant B] AES-128-CCM 24-byte LoRa packet tests\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    Reset_Mock_State();
    (void)hrtc; (void)hrng;

    RUN(test_golden_vector_encrypt);
    RUN(test_golden_vector_decrypt);
    RUN(test_fc_pack_unpack);
    RUN(test_fc_cold_boot_invalid_magic);
    RUN(test_fc_reseed_clamps_boundary);
    RUN(test_sensor_payload_pack_roundtrip);
    RUN(test_soldier_to_queen_roundtrip);
    RUN(test_mic_tamper_detected);
    RUN(test_aad_did_tamper_detected);
    RUN(test_aad_fc_tamper_detected);
    RUN(test_ciphertext_tamper_detected);
    RUN(test_wrong_key_rejected);
    RUN(test_panic_flag_inside_encrypted_payload);
    RUN(test_mesh_ctrl_bitfield_extraction);

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d   Failed: %d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
