// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_ccm.c — Host-based unit tests for [FW.2 / ARCH.42 Variant B]
 *              AES-128-CCM LoRa packet emission and reception (wire-rev2.2 30B).
 *
 * Build & run: make -C firmware/test ccm
 *
 * Coverage:
 *   1. Golden vector parity vs Rails Cryptography::LoraCcm
 *   2. RTC_BKP_DR15 Frame Counter pack/unpack with magic marker
 *   3. Cold-boot FC reseed (HRNG)
 *   4. B0-блок: голден-байти + мок-привратник проти кривого B0
 *   5. Sensor payload pack/unpack roundtrip
 *   6. Soldier build → Queen parse roundtrip
 *   7. MIC tamper detection (кінцева звірка Fw2_Ccm_Tag_Equal)
 *   8. AAD tamper detection (DID/FC/gossip flip → MIC fail)
 *   9. Ciphertext tamper detection
 *  10. Wrong key on Queen → MIC fail
 *  11. Panic flag inside encrypted payload (MIC covers it)
 *  12. mesh_ctrl bitfield roundtrip (TTL + fw_epoch_nibble)
 *
 * Мок = WL-true ДВОФАЗНИЙ флоу (hal_mock.h): HAL_CRYP_Encrypt/Decrypt
 * (payload) + HAL_CRYPEx_AESCCM_GenerateAuthTAG (тег), B0 валідується
 * проти lora_ccm.h::Build_CCM_B0 — F4-стильного AESCCM_Encrypt у WL-HAL
 * НЕ ІСНУЄ (знахідка 2026-07-03), тож і тести, і польовий код живуть
 * на одному real-API shape. Байт-рівність із OpenSSL = та сама
 * гарантія, що дає Rails-side spec; на bench лишається лише silicon
 * (ccm_selftest.h ганяє ці ж вектори через живий CRYP).
 */

#define HAL_MOCK_CCM_ENABLED

#include "hal_mock.h"
#include "../common/lora_ccm.h"
#include "../common/fw_report.h"    /* [FW.66] байт 11 wire-rev2.2 — SEC.20-звіт */
#include "../common/reset_cause.h"  /* [FW.59] коди diag[7..5] */
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

/* Golden vector (G_ZERO_KEY/G_DID/G_FC/G_PT/G_CT/G_TAG) lives in the shared
 * single-source KAT header (DRY) — also consumed by the on-target POST
 * (firmware/common/ccm_selftest.h). Keeps one canonical set of vectors. */
#include "../common/ccm_kat_vectors.h"

/* hcryp instance (firmware code references &hcryp; declare it locally). */
static CRYP_HandleTypeDef hcryp;
static RTC_HandleTypeDef  hrtc;
static RNG_HandleTypeDef  hrng;

static void Reset_Mock_State(void) {
    _rtc_bkp_reset_all();
    memset(&hcryp, 0, sizeof(hcryp));
}

/* CCM-конфіг у стилі MX_CRYP_Init_CCM обох main.c: B0 + AAD + BYTE-юніти.
 * Вказівники лишаються на буферах викликача — тримати їх живими до кінця
 * обох фаз (усі хелпери нижче так і роблять). */
static void Cryp_Init_For_Ccm(uint32_t key_w[4], uint32_t b0_w[4], uint32_t aad_w[2]) {
    hcryp.Init.KeySize         = CRYP_KEYSIZE_128B;
    hcryp.Init.Algorithm       = CRYP_AES_CCM;
    hcryp.Init.DataType        = CRYP_DATATYPE_8B;
    hcryp.Init.pKey            = key_w;
    hcryp.Init.B0              = b0_w;
    hcryp.Init.Header          = aad_w;
    hcryp.Init.HeaderSize      = FW2_CCM_AAD_LEN;
    hcryp.Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_BYTE;
    hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_BYTE;
    HAL_CRYP_Init(&hcryp);
}

/* ── [FW.2 (в)] Key-scoping mirror (двоключова модель) ──────────────────
 * Точні дзеркала CRYP-ініціалізаторів soldier/main.c CCM-ери: амбієнт-ECB
 * живе на cluster-plane (bcast), CCM-фаза явно бере session (aes) і
 * Restore повертає амбієнт. Тест нижче тримає контракт: липкий session
 * в амбієнті = downlink Королеви декриптувався б чужим ключем. */
static uint32_t scoping_aes_key[4];   /* session (KEYL) */
static uint32_t scoping_bcast_key[4]; /* cluster-plane (KEYB) */

static void Scoping_MX_CRYP_Init(void) {
    hcryp.Init.DataType = CRYP_DATATYPE_32B;
    hcryp.Init.KeySize  = CRYP_KEYSIZE_128B;
    hcryp.Init.pKey     = scoping_bcast_key;  /* FW2-гілка main.c */
    hcryp.Init.Algorithm = CRYP_AES_ECB;
    HAL_CRYP_Init(&hcryp);
}

static void Scoping_MX_CRYP_Init_CCM(uint32_t *b0_4w, uint32_t *aad_2w) {
    hcryp.Init.Algorithm       = CRYP_AES_CCM;
    hcryp.Init.DataType        = CRYP_DATATYPE_8B;
    hcryp.Init.pKey            = scoping_aes_key;  /* session — явний, не успадкований */
    hcryp.Init.B0              = b0_4w;
    hcryp.Init.Header          = aad_2w;
    hcryp.Init.HeaderSize      = FW2_CCM_AAD_LEN;
    hcryp.Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_BYTE;
    hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_BYTE;
    HAL_CRYP_Init(&hcryp);
}

static void Scoping_MX_CRYP_Restore_From_CCM(void) {
    hcryp.Init.B0              = NULL;
    hcryp.Init.Header          = NULL;
    hcryp.Init.HeaderSize      = 0;
    hcryp.Init.DataWidthUnit   = CRYP_DATAWIDTHUNIT_WORD;
    hcryp.Init.HeaderWidthUnit = CRYP_HEADERWIDTHUNIT_WORD;
    Scoping_MX_CRYP_Init();
}

/* Двофазний encrypt (payload → тег), дзеркало Soldier_Build_CCM_LoRa_Packet. */
static int Ccm_Encrypt_TwoPhase(uint32_t key_w[4],
                                const uint8_t nonce[FW2_CCM_NONCE_LEN],
                                const uint8_t aad[FW2_CCM_AAD_LEN],
                                const uint8_t pt[FW2_CCM_PLAINTEXT_LEN],
                                uint8_t out_ct[FW2_CCM_PLAINTEXT_LEN],
                                uint8_t out_mic[FW2_CCM_MIC_LEN]) {
    uint32_t b0_w[FW2_CCM_B0_LEN / 4];
    uint32_t aad_w[FW2_CCM_AAD_LEN / 4];
    uint32_t pt_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4];
    uint32_t ct_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4];
    uint32_t tag_w[4];
    Build_CCM_B0_From_Nonce(nonce, FW2_CCM_PLAINTEXT_LEN, (uint8_t *)b0_w);
    memcpy(aad_w, aad, FW2_CCM_AAD_LEN);
    memcpy(pt_w, pt, FW2_CCM_PLAINTEXT_LEN);
    Cryp_Init_For_Ccm(key_w, b0_w, aad_w);
    if (HAL_CRYP_Encrypt(&hcryp, pt_w, FW2_CCM_PLAINTEXT_LEN, ct_w, 1000) != HAL_OK)
        return HAL_ERROR;
    if (HAL_CRYPEx_AESCCM_GenerateAuthTAG(&hcryp, tag_w, 1000) != HAL_OK)
        return HAL_ERROR;
    memcpy(out_ct, ct_w, FW2_CCM_PLAINTEXT_LEN);
    memcpy(out_mic, tag_w, FW2_CCM_MIC_LEN);
    return HAL_OK;
}

/* Двофазний decrypt + caller-side MIC-звірка (дзеркало Queen_Parse_CCM):
 * HAL_OK ЛИШЕ якщо computed tag == wire MIC — тобто семантика «HAL_ERROR
 * на tamper» збережена для всіх tamper-тестів, але живе там, де на WL
 * насправді: у константній звірці викликача. */
static int Ccm_Decrypt_TwoPhase(uint32_t key_w[4],
                                const uint8_t nonce[FW2_CCM_NONCE_LEN],
                                const uint8_t aad[FW2_CCM_AAD_LEN],
                                const uint8_t ct[FW2_CCM_PLAINTEXT_LEN],
                                const uint8_t mic[FW2_CCM_MIC_LEN],
                                uint8_t out_pt[FW2_CCM_PLAINTEXT_LEN]) {
    uint32_t b0_w[FW2_CCM_B0_LEN / 4];
    uint32_t aad_w[FW2_CCM_AAD_LEN / 4];
    uint32_t ct_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4];
    uint32_t pt_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4];
    uint32_t tag_w[4];
    Build_CCM_B0_From_Nonce(nonce, FW2_CCM_PLAINTEXT_LEN, (uint8_t *)b0_w);
    memcpy(aad_w, aad, FW2_CCM_AAD_LEN);
    memcpy(ct_w, ct, FW2_CCM_PLAINTEXT_LEN);
    Cryp_Init_For_Ccm(key_w, b0_w, aad_w);
    if (HAL_CRYP_Decrypt(&hcryp, ct_w, FW2_CCM_PLAINTEXT_LEN, pt_w, 1000) != HAL_OK)
        return HAL_ERROR;
    if (HAL_CRYPEx_AESCCM_GenerateAuthTAG(&hcryp, tag_w, 1000) != HAL_OK)
        return HAL_ERROR;
    if (!Fw2_Ccm_Tag_Equal((const uint8_t *)tag_w, mic))
        return HAL_ERROR;
    memcpy(out_pt, pt_w, FW2_CCM_PLAINTEXT_LEN);
    return HAL_OK;
}

/* ── tests ───────────────────────────────────────────────────────────── */

static int test_golden_vector_encrypt(void) {
    uint32_t key_words[4] = {0};
    memcpy(key_words, G_ZERO_KEY, 16);

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    uint8_t ct[FW2_CCM_PLAINTEXT_LEN];
    uint8_t mic[FW2_CCM_MIC_LEN];

    Build_CCM_Nonce(G_DID, G_FC, nonce);
    Build_CCM_AAD(G_DID, G_GOSSIP, G_FC, aad);

    ASSERT_EQ(Ccm_Encrypt_TwoPhase(key_words, nonce, aad, G_PT, ct, mic), HAL_OK);
    ASSERT_MEM_EQ(ct, G_CT, FW2_CCM_PLAINTEXT_LEN);
    ASSERT_MEM_EQ(mic, G_TAG, FW2_CCM_MIC_LEN);
    printf("  test_golden_vector_encrypt                                 ✅\n");
    return 0;
}

static int test_golden_vector_decrypt(void) {
    uint32_t key_words[4] = {0};
    memcpy(key_words, G_ZERO_KEY, 16);

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    uint8_t out[FW2_CCM_PLAINTEXT_LEN];

    Build_CCM_Nonce(G_DID, G_FC, nonce);
    Build_CCM_AAD(G_DID, G_GOSSIP, G_FC, aad);

    ASSERT_EQ(Ccm_Decrypt_TwoPhase(key_words, nonce, aad, G_CT, G_TAG, out), HAL_OK);
    ASSERT_MEM_EQ(out, G_PT, FW2_CCM_PLAINTEXT_LEN);
    printf("  test_golden_vector_decrypt                                 ✅\n");
    return 0;
}

static int test_b0_block_format(void) {
    /* B0 = [0x5A][nonce:12][0x00 0x00 0x0C] — NIST 800-38C: Adata=1,
     * t=8 → M'=3, q=3 → L'=2; Q(=12) big-endian у хвості. Байт-ряд
     * зашитий у Build_CCM_B0* і валідується моком — розійтися з
     * кремнієвим B0 тепер можна лише свідомо. */
    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t b0[FW2_CCM_B0_LEN];
    Build_CCM_Nonce(G_DID, G_FC, nonce);
    Build_CCM_B0(G_DID, G_FC, b0);

    ASSERT_EQ(b0[0], FW2_CCM_B0_FLAGS);
    ASSERT_EQ(b0[0], 0x5Au);
    ASSERT_MEM_EQ(&b0[1], nonce, FW2_CCM_NONCE_LEN);
    ASSERT_EQ(b0[13], 0x00);
    ASSERT_EQ(b0[14], 0x00);
    ASSERT_EQ(b0[15], FW2_CCM_PLAINTEXT_LEN);
    printf("  test_b0_block_format                                       ✅\n");
    return 0;
}

static int test_b0_gatekeeper_rejects_malformed(void) {
    /* Мок-привратник: криві flags або Q ≠ Size → payload-фаза HAL_ERROR
     * (ловить неправильно зібраний Init до bench-дня). Плюс порядок фаз:
     * тег без payload-фази — теж помилка. */
    uint32_t key_w[4] = {0};
    uint32_t b0_w[FW2_CCM_B0_LEN / 4];
    uint32_t aad_w[FW2_CCM_AAD_LEN / 4];
    uint32_t pt_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4] = {0};
    uint32_t ct_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4];
    uint32_t tag_w[4];
    uint8_t  nonce[FW2_CCM_NONCE_LEN];
    uint8_t  aad[FW2_CCM_AAD_LEN];

    Build_CCM_Nonce(G_DID, G_FC, nonce);
    Build_CCM_AAD(G_DID, G_GOSSIP, G_FC, aad);
    memcpy(aad_w, aad, FW2_CCM_AAD_LEN);

    /* Криві flags (0x59 ≠ 0x5A). */
    Build_CCM_B0_From_Nonce(nonce, FW2_CCM_PLAINTEXT_LEN, (uint8_t *)b0_w);
    ((uint8_t *)b0_w)[0] = 0x59u;
    Cryp_Init_For_Ccm(key_w, b0_w, aad_w);
    ASSERT_EQ(HAL_CRYP_Encrypt(&hcryp, pt_w, FW2_CCM_PLAINTEXT_LEN, ct_w, 1000), HAL_ERROR);

    /* Q-поле бреше про довжину. */
    Build_CCM_B0_From_Nonce(nonce, FW2_CCM_PLAINTEXT_LEN, (uint8_t *)b0_w);
    ((uint8_t *)b0_w)[15] = FW2_CCM_PLAINTEXT_LEN + 1;
    Cryp_Init_For_Ccm(key_w, b0_w, aad_w);
    ASSERT_EQ(HAL_CRYP_Encrypt(&hcryp, pt_w, FW2_CCM_PLAINTEXT_LEN, ct_w, 1000), HAL_ERROR);

    /* Тег-фаза без payload-фази (провалена вище) = помилка порядку. */
    ASSERT_EQ(HAL_CRYPEx_AESCCM_GenerateAuthTAG(&hcryp, tag_w, 1000), HAL_ERROR);
    printf("  test_b0_gatekeeper_rejects_malformed                       ✅\n");
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

/* [SEC.41] Вичерпання 24-бітного простору — насичення, НЕ перехід через нуль:
 * перехід повторював nonce під тим самим ключем на кожному cold start після нього. */
static int test_fc_next_saturates_never_wraps(void) {
    uint32_t next = 0;
    ASSERT_EQ(Fw2_Next_Frame_Counter(5u, &next), 1);
    ASSERT_EQ(next, 6u);
    ASSERT_EQ(Fw2_Next_Frame_Counter(0xFFFFFEu, &next), 1);
    ASSERT_EQ(next, FW2_FC_VALUE_MASK);
    next = 0xABCDEFu;
    ASSERT_EQ(Fw2_Next_Frame_Counter(FW2_FC_VALUE_MASK, &next), 0);
    ASSERT_EQ(next, 0xABCDEFu); /* відмова лишає вихід недоторканим */
    printf("  test_fc_next_saturates_never_wraps                         ✅\n");
    return 0;
}

static int test_sensor_payload_pack_roundtrip(void) {
    uint8_t buf[FW2_CCM_PLAINTEXT_LEN];
    Pack_CCM_Sensor_Payload(3500, -15, 0xAA /* fw_report7 */, 1234, 0x5A, 0x37,
                            0x0B6E /* voc_mv 2926 */, 0xAD, 0x42,
                            4321 /* [E.63 (г)] ema */, buf);
    /* [FW.66 · wire-rev2.2] Позиції — за ledger 03_05 §2.1 (air = PT + 8):
     * байт 11 ← PT[3] звіт, 16..17 ← PT[8..9] voc_mv BE, 18 ← diag, 19 ← vpd. */
    ASSERT_EQ(buf[3], 0xAA);
    ASSERT_EQ(buf[8], 0x0B); ASSERT_EQ(buf[9], 0x6E);
    ASSERT_EQ(buf[10], 0xAD);
    ASSERT_EQ(buf[11], 0x42);
    uint16_t vcap; int8_t temp; uint8_t report; uint16_t dt;
    uint8_t status, ctrl, diag, vpd; uint16_t voc; uint16_t ema;
    Unpack_CCM_Sensor_Payload(buf, &vcap, &temp, &report, &dt, &status, &ctrl,
                              &voc, &diag, &vpd, &ema);
    ASSERT_EQ(vcap, 3500);
    ASSERT_EQ((uint32_t)(int32_t)temp, (uint32_t)(int32_t)-15);
    ASSERT_EQ(report, 0xAA);
    ASSERT_EQ(dt, 1234);
    ASSERT_EQ(status, 0x5A);
    ASSERT_EQ(ctrl, 0x37);
    /* mesh_ctrl bitfield: TTL=3, fw_nibble=7 */
    ASSERT_EQ((ctrl >> FW2_MESH_TTL_SHIFT) & FW2_MESH_TTL_MASK, 3);
    ASSERT_EQ(ctrl & FW2_MESH_FW_NIBBLE_MASK, 7);
    ASSERT_EQ(voc, 2926);
    ASSERT_EQ(diag, 0xAD);
    ASSERT_EQ(vpd, 0x42);
    ASSERT_EQ(ema, 4321); /* [E.63 (г)] wire-rev2.1 bytes 12..13 плейну */
    printf("  test_sensor_payload_pack_roundtrip                         ✅\n");
    return 0;
}

static int test_soldier_to_queen_roundtrip(void) {
    /* Encrypt as Soldier (manual — replicates Soldier_Build_CCM_LoRa_Packet). */
    uint32_t key_words[4];
    for (int i = 0; i < 4; i++) key_words[i] = 0xDEAD0000u | (uint32_t)i;

    const uint32_t did = 0x534E4554u; /* "SNET" */
    const uint32_t fc  = 9001;

    uint8_t nonce[FW2_CCM_NONCE_LEN];
    uint8_t aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    uint8_t ct[FW2_CCM_PLAINTEXT_LEN];
    uint8_t mic[FW2_CCM_MIC_LEN];

    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, 0x00, fc, aad);
    Pack_CCM_Sensor_Payload(4200, 22, Fw_Report_To_Ccm7(0x8000u | 7u), 600, 0x00, 0x53,
                            (uint16_t)FW2_VOC_MV_UNKNOWN, 0x00,
                            (uint8_t)FW2_VPD_INDEX_NONE, 550 /* ema */, pt);

    ASSERT_EQ(Ccm_Encrypt_TwoPhase(key_words, nonce, aad, pt, ct, mic), HAL_OK);

    /* Assemble the 30B on-air packet. */
    uint8_t air[FW2_CCM_AIR_PACKET_LEN];
    memcpy(&air[0],  aad, FW2_CCM_AAD_LEN);
    memcpy(&air[FW2_CCM_AAD_LEN], ct, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&air[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN], mic, FW2_CCM_MIC_LEN);

    /* Parse as Queen (manual — replicates Queen_Parse_CCM_LoRa_Packet). */
    uint8_t recv_nonce[FW2_CCM_NONCE_LEN];
    uint8_t recv_aad[FW2_CCM_AAD_LEN];
    uint32_t recv_did =
        ((uint32_t)air[0] << 24) | ((uint32_t)air[1] << 16) |
        ((uint32_t)air[2] << 8)  | (uint32_t)air[3];
    uint8_t  recv_gossip = air[4];
    uint32_t recv_fc =
        ((uint32_t)air[5] << 16) | ((uint32_t)air[6] << 8) | (uint32_t)air[7];
    Build_CCM_Nonce(recv_did, recv_fc, recv_nonce);
    Build_CCM_AAD(recv_did, recv_gossip, recv_fc, recv_aad);

    uint8_t recv_pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Ccm_Decrypt_TwoPhase(key_words, recv_nonce, recv_aad,
                                   &air[FW2_CCM_AAD_LEN],
                                   &air[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN],
                                   recv_pt), HAL_OK);
    ASSERT_EQ(recv_did, did);
    ASSERT_EQ(recv_fc, fc);
    ASSERT_MEM_EQ(recv_pt, pt, FW2_CCM_PLAINTEXT_LEN);
    printf("  test_soldier_to_queen_roundtrip                            ✅\n");
    return 0;
}

/* Helper: build a fully-encrypted 30B packet for tamper tests. */
static void Build_Reference_Packet(uint32_t key_words[4], uint32_t did, uint32_t fc,
                                   uint8_t out[FW2_CCM_AIR_PACKET_LEN]) {
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14};
    uint8_t ct[FW2_CCM_PLAINTEXT_LEN], mic[FW2_CCM_MIC_LEN];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, 0x00, fc, aad);
    Ccm_Encrypt_TwoPhase(key_words, nonce, aad, pt, ct, mic);
    memcpy(&out[0],  aad, FW2_CCM_AAD_LEN);
    memcpy(&out[FW2_CCM_AAD_LEN], ct, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&out[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN], mic, FW2_CCM_MIC_LEN);
}

static int Try_Decrypt(uint32_t key_words[4],
                       const uint8_t in[FW2_CCM_AIR_PACKET_LEN],
                       uint8_t out_pt[FW2_CCM_PLAINTEXT_LEN]) {
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint32_t did =
        ((uint32_t)in[0] << 24) | ((uint32_t)in[1] << 16) |
        ((uint32_t)in[2] << 8)  | (uint32_t)in[3];
    uint8_t  gossip = in[4];
    uint32_t fc =
        ((uint32_t)in[5] << 16) | ((uint32_t)in[6] << 8) | (uint32_t)in[7];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, gossip, fc, aad);
    return Ccm_Decrypt_TwoPhase(key_words, nonce, aad, &in[FW2_CCM_AAD_LEN],
                                &in[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN],
                                out_pt);
}

static int test_mic_tamper_detected(void) {
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];
    Build_Reference_Packet(key, 0xAABBCCDD, 42, pkt);

    pkt[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN] ^= 0x01; /* flip a bit in the MIC */
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
     * the 30B packet (= offset 6 of the encrypted payload). Flipping it
     * on the wire breaks MIC, so an attacker cannot forge a panic alert
     * from a benign packet. This was an explicit FW.29 design goal. */
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];

    /* Build a benign packet (status_byte = 0, no panic). */
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    uint8_t ct[FW2_CCM_PLAINTEXT_LEN], mic[FW2_CCM_MIC_LEN];
    Build_CCM_Nonce(0xAABBCCDD, 42, nonce);
    Build_CCM_AAD(0xAABBCCDD, 0x00, 42, aad);
    Pack_CCM_Sensor_Payload(3500, 25, 0x00, 100, 0x00 /* no panic */, 0x33,
                            (uint16_t)FW2_VOC_MV_UNKNOWN, 0x00,
                            (uint8_t)FW2_VPD_INDEX_NONE, 90 /* ema */, pt);
    ASSERT_EQ(Ccm_Encrypt_TwoPhase(key, nonce, aad, pt, ct, mic), HAL_OK);
    memcpy(&pkt[0],  aad, FW2_CCM_AAD_LEN);
    memcpy(&pkt[FW2_CCM_AAD_LEN], ct, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&pkt[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN], mic, FW2_CCM_MIC_LEN);

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

static int test_gossip_byte_is_mic_protected(void) {
    /* [wire-rev2] AAD byte 4 = gossip_ts_lsb. Сусід читає його без ключа,
     * але бекенд верифікує MIC'ом: підміна gossip на дроті → decrypt fail.
     * (Сусідська довіра до gossip лишається untrusted-уточненням ±128 c —
     * та сама модель, що ECB-piggyback FW.20-S2 #5.) */
    uint32_t key[4] = {0xCAFE0000, 0xCAFE0001, 0xCAFE0002, 0xCAFE0003};
    uint8_t pkt[FW2_CCM_AIR_PACKET_LEN];
    Build_Reference_Packet(key, 0xAABBCCDD, 42, pkt);

    pkt[4] ^= 0xA5; /* flip gossip byte → AAD diverges → MIC must fail */
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Try_Decrypt(key, pkt, pt), HAL_ERROR);
    printf("  test_gossip_byte_is_mic_protected                          ✅\n");
    return 0;
}

static int test_diag_byte_pack(void) {
    /* [FW.66 · wire-rev2.2] [reset_cause:3 | time_uncertain:1 | voc_attempt:1 |
     * резерв:2 | fc_degraded:1] — ledger 03_05 §2.1. */
    ASSERT_EQ(Pack_FW2_Diag(SILKEN_RESET_UNKNOWN, 0, 0, 0), 0x00);
    ASSERT_EQ(Pack_FW2_Diag(SILKEN_RESET_IWDG, 0, 0, 0), 0x80);    /* 4 << 5 */
    ASSERT_EQ(Pack_FW2_Diag(SILKEN_RESET_LOW_POWER, 1, 1, 1), 0xF9); /* усе, крім резерву */
    ASSERT_EQ(Pack_FW2_Diag(0, 1, 0, 0), FW2_DIAG_TIME_UNCERTAIN_BIT);
    ASSERT_EQ(Pack_FW2_Diag(0, 0, 1, 0), FW2_DIAG_VOC_ATTEMPT_BIT);
    ASSERT_EQ(Pack_FW2_Diag(0, 0, 0, 1), FW2_DIAG_FC_DEGRADED_BIT);
    /* Код поза 0..7 — «не повідомлено», а не обрізаний маскою ЧУЖИЙ код (8 & 7 = 0
     * випадково збіглося б, 14 & 7 = 6 = HardFault — вигадана причина). */
    ASSERT_EQ(Pack_FW2_Diag(14, 0, 0, 0), 0x00);
    /* Резервні біти не пише жоден вхід. */
    for (unsigned rc = 0; rc <= 255u; rc++)
        ASSERT_EQ(Pack_FW2_Diag((uint8_t)rc, 1, 1, 1) & FW2_DIAG_RESERVED_MASK, 0);
    /* Поля не налазять одне на одне — і біти сходяться в повний байт без резерву. */
    ASSERT_EQ((FW2_DIAG_RESET_CAUSE_MASK << FW2_DIAG_RESET_CAUSE_SHIFT) |
              FW2_DIAG_TIME_UNCERTAIN_BIT | FW2_DIAG_VOC_ATTEMPT_BIT |
              FW2_DIAG_RESERVED_MASK | FW2_DIAG_FC_DEGRADED_BIT, 0xFF);
    ASSERT_EQ((FW2_DIAG_RESET_CAUSE_MASK << FW2_DIAG_RESET_CAUSE_SHIFT) &
              (FW2_DIAG_TIME_UNCERTAIN_BIT | FW2_DIAG_VOC_ATTEMPT_BIT |
               FW2_DIAG_RESERVED_MASK | FW2_DIAG_FC_DEGRADED_BIT), 0);
    printf("  test_diag_byte_pack                                        ✅\n");
    return 0;
}

/* [FW.66 · wire-rev2.2] ЗОЛОТИЙ plaintext — один на дві мови. Pack_CCM_Sensor_Payload з
 * джерелами test_phase4 нижче МУСИТЬ дати рівно ці 14 байт, а Ruby-спека
 * (`telemetry_unpacker_service_spec.rb`, «golden wire-rev2.2 plaintext») читає цей самий
 * масив звідси й проганяє його через справжній розпакувальник поле за полем. Без нього
 * кожна мова перевіряла б розкладку лише проти СЕБЕ: обмін out[10]⟷out[11] разом з
 * Unpack лишив би обидві сюїти зеленими, а бекенд читав би VPD як diag.
 * vcap 3300 · temp −7 · звіт 0xAA (відкат id 42) · dt 0xFFFF · status 0x25 · mesh 0x31 ·
 * voc 2926 · diag 0xD9 (HardFault | time_uncertain | voc_attempt | fc_degraded) ·
 * vpd 0x42 · ema 3600. VPD свідомо БЕЗ бітів 4 і 0 — тих, що бекенд читає з diag: обмін
 * diag⟷vpd тоді червонить і Ruby-бік, а не лише цей масив. */
static const uint8_t G_PT_REV22[FW2_CCM_PLAINTEXT_LEN] = {
    0x0C, 0xE4, 0xF9, 0xAA, 0xFF, 0xFF, 0x25, 0x31, 0x0B, 0x6E, 0xD9, 0x42, 0x0E, 0x10
};

static int test_phase4_marshalling_e2e_to_backend_bytes(void) {
    /* e2e дзеркало Фази 4 → ефір → 31B-запис Королеви: аргументи складені
     * як call-site у soldier/main.c (mesh_ctrl = TTL|fw-nibble, dt-сатурація,
     * сирий vcap), а розкладка на виході — та, яку читає process_ccm_chunk.
     * [FW.66 · wire-rev2.2] Поля, що в main.c поки пишуться «не виміряно»
     * (voc_mv · vpd · reset_cause), тут свідомо НЕНУЛЬОВІ — доводять бітфілд і
     * позиції наскрізь до дня, коли в них зʼявляться джерела. */
    enum { DEFAULT_TTL_M = 3, FIRMWARE_VERSION_ID_M = 0x0001 };
    uint32_t key[4] = {0x11110000, 0x22220000, 0x33330000, 0x44440000};
    const uint32_t did = 0x00C0FFEE;
    const uint32_t fc  = 77;

    /* Джерела Фази 4 (імена дзеркалять main.c): */
    uint16_t vcap_voltage = 3300;                     /* сирий, НЕ EMA */
    int8_t   temp_c       = -7;
    uint8_t  fw_report7   = Fw_Report_To_Ccm7(0xC000u | 42u); /* SEC.20: відкат id 42 */
    uint32_t delta_t_raw  = 200000;                   /* зимова доба > 0xFFFF */
    uint32_t dt_wire      = (delta_t_raw > 0xFFFFu) ? 0xFFFFu : delta_t_raw;
    uint8_t  status_byte  = 0x25 & (uint8_t)~0x80u;   /* після FW.29-маски */
    uint8_t  mesh_ctrl    = (uint8_t)(((DEFAULT_TTL_M & FW2_MESH_TTL_MASK)
                                       << FW2_MESH_TTL_SHIFT) |
                                      (FIRMWARE_VERSION_ID_M & FW2_MESH_FW_NIBBLE_MASK));
    uint8_t  diag         = Pack_FW2_Diag(SILKEN_RESET_HARDFAULT, 1, 1, 1);
    uint16_t voc_mv       = 2926;                     /* V_OC EBFC, мВ */
    uint8_t  vpd_index    = 0x42;
    uint8_t  gossip       = (uint8_t)(0x66554433u & 0xFFu); /* unix_ts LSB */
    uint16_t wire_ema     = 3600; /* [E.63 (г)] контракт «wire = вхід GP» */

    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN], ct[FW2_CCM_PLAINTEXT_LEN], mic[FW2_CCM_MIC_LEN];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, gossip, fc, aad);
    Pack_CCM_Sensor_Payload(vcap_voltage, temp_c, fw_report7, (uint16_t)dt_wire,
                            status_byte, mesh_ctrl, voc_mv, diag, vpd_index,
                            wire_ema, pt);
    ASSERT_MEM_EQ(pt, G_PT_REV22, FW2_CCM_PLAINTEXT_LEN); /* та сама розкладка, що читає Ruby */
    ASSERT_EQ(Ccm_Encrypt_TwoPhase(key, nonce, aad, pt, ct, mic), HAL_OK);

    uint8_t air[FW2_CCM_AIR_PACKET_LEN];
    memcpy(&air[0], aad, FW2_CCM_AAD_LEN);
    memcpy(&air[FW2_CCM_AAD_LEN], ct, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&air[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN], mic, FW2_CCM_MIC_LEN);

    /* Королева: запис air+1 [DID][|RSSI|][air-хвіст] (rx_route-контракт;
     * offsets ПОХІДНІ — статичний 29/9/21 дрейфив би з wire-ревізією). */
    enum { REC_LEN  = FW2_CCM_AIR_PACKET_LEN + 1,
           REC_CT   = 1 + FW2_CCM_AAD_LEN,                          /* 9  */
           REC_MIC  = REC_CT + FW2_CCM_PLAINTEXT_LEN };             /* 23 */
    uint8_t rec[REC_LEN];
    memcpy(&rec[0], &air[0], 4);
    rec[4] = 91; /* |-91| */
    memcpy(&rec[5], &air[4], FW2_CCM_AIR_PACKET_LEN - 4);

    /* «Rails»: поля з запису → decrypt+verify → unpack-звірка джерел. */
    uint32_t r_did = ((uint32_t)rec[0] << 24) | ((uint32_t)rec[1] << 16) |
                     ((uint32_t)rec[2] << 8)  | (uint32_t)rec[3];
    uint8_t  r_gossip = rec[5];
    uint32_t r_fc = ((uint32_t)rec[6] << 16) | ((uint32_t)rec[7] << 8) | (uint32_t)rec[8];
    ASSERT_EQ(r_did, did);
    ASSERT_EQ(r_gossip, gossip);
    ASSERT_EQ(r_fc, fc);

    uint8_t r_nonce[FW2_CCM_NONCE_LEN], r_aad[FW2_CCM_AAD_LEN], r_pt[FW2_CCM_PLAINTEXT_LEN];
    Build_CCM_Nonce(r_did, r_fc, r_nonce);
    Build_CCM_AAD(r_did, r_gossip, r_fc, r_aad);
    ASSERT_EQ(Ccm_Decrypt_TwoPhase(key, r_nonce, r_aad, &rec[REC_CT], &rec[REC_MIC], r_pt), HAL_OK);

    uint16_t u_vcap, u_dt, u_voc; int8_t u_temp;
    uint8_t u_rep, u_st, u_mc, u_diag, u_vpd; uint16_t u_ema;
    Unpack_CCM_Sensor_Payload(r_pt, &u_vcap, &u_temp, &u_rep, &u_dt, &u_st, &u_mc,
                              &u_voc, &u_diag, &u_vpd, &u_ema);
    ASSERT_EQ(u_vcap, vcap_voltage);
    ASSERT_EQ((uint32_t)(int32_t)u_temp, (uint32_t)(int32_t)temp_c);
    ASSERT_EQ(u_rep, 0x80 | 42);              /* reverted-біт + id7 */
    ASSERT_EQ(u_dt, 0xFFFF);                   /* сатурація доїхала */
    ASSERT_EQ(u_st, status_byte);
    ASSERT_EQ((u_mc >> FW2_MESH_TTL_SHIFT) & FW2_MESH_TTL_MASK, DEFAULT_TTL_M);
    ASSERT_EQ(u_mc & FW2_MESH_FW_NIBBLE_MASK, FIRMWARE_VERSION_ID_M & 0x0F);
    ASSERT_EQ(u_voc, voc_mv);
    ASSERT_EQ(u_diag, diag);
    ASSERT_EQ(u_diag >> FW2_DIAG_RESET_CAUSE_SHIFT, SILKEN_RESET_HARDFAULT);
    ASSERT_EQ(u_vpd, vpd_index);
    ASSERT_EQ(u_ema, wire_ema); /* [E.63 (г)] EMA доїхав до «Rails» байт-точно */
    printf("  test_phase4_marshalling_e2e_to_backend_bytes               ✅\n");
    return 0;
}

static int test_panic_marshalling_ccm(void) {
    /* [FW.66 · wire-rev2.2] Справжній Pack_CCM_Panic_Payload — той, що кличе CCM-гілка
     * Trigger_Emergency_LoRa_TX (скіл firmware #19: копія доводила б копію). Нулі
     * vcap/temp/dt (legacy-parity), status=PANIC_FLAG, TTL=PANIC(5), ema=0. 🔴 Байт 11
     * — SEC.20-звіт, а НЕ panic-код 0xFF: у rev2.2 0xFF читався б відкатом із
     * critical-алертом `firmware_reverted` на КОЖНОМУ зойку (скіл firmware #25). */
    enum { PANIC_TTL_M = 5, FIRMWARE_VERSION_ID_M = 0x0001 };
    uint32_t key[4] = {0x51CC0000, 0x51CC0001, 0x51CC0002, 0x51CC0003};
    const uint32_t did = 0x0BAD5EED;
    const uint32_t fc  = 4242;

    uint8_t mesh_ctrl = (uint8_t)(((PANIC_TTL_M & FW2_MESH_TTL_MASK)
                                   << FW2_MESH_TTL_SHIFT) |
                                  (FIRMWARE_VERSION_ID_M & FW2_MESH_FW_NIBBLE_MASK));
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint8_t pt[FW2_CCM_PLAINTEXT_LEN], ct[FW2_CCM_PLAINTEXT_LEN], mic[FW2_CCM_MIC_LEN];
    Build_CCM_Nonce(did, fc, nonce);
    Build_CCM_AAD(did, 0x00, fc, aad);
    /* Робочий (не відкочений) контракт id 5, час невідомий. */
    Pack_CCM_Panic_Payload(Fw_Report_To_Ccm7(0x8000u | 5u), mesh_ctrl,
                           Pack_FW2_Diag(SILKEN_RESET_UNKNOWN, 1, 0, 0), pt);
    ASSERT_EQ(Ccm_Encrypt_TwoPhase(key, nonce, aad, pt, ct, mic), HAL_OK);

    uint8_t r_pt[FW2_CCM_PLAINTEXT_LEN];
    ASSERT_EQ(Ccm_Decrypt_TwoPhase(key, nonce, aad, ct, mic, r_pt), HAL_OK);

    uint16_t u_vcap, u_dt, u_voc; int8_t u_temp;
    uint8_t u_rep, u_st, u_mc, u_diag, u_vpd; uint16_t u_ema;
    Unpack_CCM_Sensor_Payload(r_pt, &u_vcap, &u_temp, &u_rep, &u_dt, &u_st, &u_mc,
                              &u_voc, &u_diag, &u_vpd, &u_ema);
    ASSERT_EQ(u_rep, 5);                                   /* звіт, не код паніки */
    ASSERT_EQ(u_rep & 0x80, 0);                            /* і НЕ вигаданий відкат */
    ASSERT_EQ(u_ema, 0);                                   /* panic: ema=0 */
    ASSERT_EQ(u_st & FW2_STATUS_PANIC_BIT, FW2_STATUS_PANIC_BIT);
    ASSERT_EQ((u_st & FW2_STATUS_GROWTH_MASK), 0);         /* панічний зойк не мінтить */
    ASSERT_EQ((u_mc >> FW2_MESH_TTL_SHIFT) & FW2_MESH_TTL_MASK, PANIC_TTL_M);
    ASSERT_EQ(u_vcap, 0); ASSERT_EQ(u_dt, 0); ASSERT_EQ(u_temp, 0);
    ASSERT_EQ(u_voc, FW2_VOC_MV_UNKNOWN);
    ASSERT_EQ(u_vpd, FW2_VPD_INDEX_NONE);
    ASSERT_EQ(u_diag, FW2_DIAG_TIME_UNCERTAIN_BIT);

    /* Справжній відкат доїжджає і в зойку — єдиний сигнал відкату CCM-ери не губиться. */
    Pack_CCM_Panic_Payload(Fw_Report_To_Ccm7(0xC000u | 42u), mesh_ctrl, 0x00, pt);
    ASSERT_EQ(pt[3], 0x80 | 42);
    printf("  test_panic_marshalling_ccm                                 ✅\n");
    return 0;
}

static int test_two_key_scoping_contract(void) {
    /* [FW.2 (в)] Контракт двоключової моделі (дзеркала Scoping_MX_* вгорі):
     * амбієнт-ECB = cluster-plane (bcast), CCM-скоуп явно бере session,
     * Restore повертає амбієнт + WORD-юніти + жодних висячих B0/Header.
     * Функціональний доказ: session = golden-KAT ключ, bcast — інший;
     * якби Init_CCM успадкував «липкий» амбієнт (клас регресії, який цей
     * тест сторожує), CT/MIC розійшлися б із golden-вектором. */
    memcpy(scoping_aes_key, G_ZERO_KEY, 16);                 /* session (KEYL) */
    for (int i = 0; i < 4; i++) scoping_bcast_key[i] = 0xB0B0B0B0u; /* KEYB */

    /* Boot-стан: амбієнт = bcast */
    Scoping_MX_CRYP_Init();
    ASSERT_EQ((void *)hcryp.Init.pKey, (void *)scoping_bcast_key);
    ASSERT_EQ(hcryp.Init.Algorithm, CRYP_AES_ECB);

    /* Фаза-4 CCM TX: session у скоупі */
    uint8_t nonce[FW2_CCM_NONCE_LEN], aad[FW2_CCM_AAD_LEN];
    uint32_t b0_w[FW2_CCM_B0_LEN / 4], aad_w[FW2_CCM_AAD_LEN / 4];
    uint32_t pt_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4], ct_w[(FW2_CCM_PLAINTEXT_LEN + 3) / 4];
    uint32_t tag_w[4];
    Build_CCM_Nonce(G_DID, G_FC, nonce);
    Build_CCM_AAD(G_DID, G_GOSSIP, G_FC, aad);
    Build_CCM_B0_From_Nonce(nonce, FW2_CCM_PLAINTEXT_LEN, (uint8_t *)b0_w);
    memcpy(aad_w, aad, FW2_CCM_AAD_LEN);
    memcpy(pt_w, G_PT, FW2_CCM_PLAINTEXT_LEN);

    Scoping_MX_CRYP_Init_CCM(b0_w, aad_w);
    ASSERT_EQ((void *)hcryp.Init.pKey, (void *)scoping_aes_key);
    ASSERT_EQ(HAL_CRYP_Encrypt(&hcryp, pt_w, FW2_CCM_PLAINTEXT_LEN, ct_w, 1000), HAL_OK);
    ASSERT_EQ(HAL_CRYPEx_AESCCM_GenerateAuthTAG(&hcryp, tag_w, 1000), HAL_OK);
    ASSERT_MEM_EQ(ct_w, G_CT, FW2_CCM_PLAINTEXT_LEN);  /* session діяв, не bcast */
    ASSERT_MEM_EQ(tag_w, G_TAG, FW2_CCM_MIC_LEN);

    /* Гігієна Restore: амбієнт знову cluster-plane, RX-вікно готове */
    Scoping_MX_CRYP_Restore_From_CCM();
    ASSERT_EQ((void *)hcryp.Init.pKey, (void *)scoping_bcast_key);
    ASSERT_EQ(hcryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_EQ((void *)hcryp.Init.B0, NULL);
    ASSERT_EQ((void *)hcryp.Init.Header, NULL);
    ASSERT_EQ(hcryp.Init.DataWidthUnit, CRYP_DATAWIDTHUNIT_WORD);
    printf("  test_two_key_scoping_contract                              ✅\n");
    return 0;
}

#define RUN(test) do { \
    if (test()) { failed++; } else { passed++; } \
} while (0)

int main(void) {
    int passed = 0, failed = 0;
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.2 / ARCH.42 Variant B] AES-128-CCM 30-byte (wire-rev2.2) LoRa packet tests\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    Reset_Mock_State();
    (void)hrtc; (void)hrng;

    RUN(test_golden_vector_encrypt);
    RUN(test_golden_vector_decrypt);
    RUN(test_b0_block_format);
    RUN(test_b0_gatekeeper_rejects_malformed);
    RUN(test_fc_pack_unpack);
    RUN(test_fc_cold_boot_invalid_magic);
    RUN(test_fc_reseed_clamps_boundary);
    RUN(test_fc_next_saturates_never_wraps);
    RUN(test_sensor_payload_pack_roundtrip);
    RUN(test_soldier_to_queen_roundtrip);
    RUN(test_mic_tamper_detected);
    RUN(test_aad_did_tamper_detected);
    RUN(test_aad_fc_tamper_detected);
    RUN(test_ciphertext_tamper_detected);
    RUN(test_wrong_key_rejected);
    RUN(test_panic_flag_inside_encrypted_payload);
    RUN(test_mesh_ctrl_bitfield_extraction);
    RUN(test_gossip_byte_is_mic_protected);
    RUN(test_diag_byte_pack);
    RUN(test_phase4_marshalling_e2e_to_backend_bytes);
    RUN(test_panic_marshalling_ccm);
    RUN(test_two_key_scoping_contract);

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d   Failed: %d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
