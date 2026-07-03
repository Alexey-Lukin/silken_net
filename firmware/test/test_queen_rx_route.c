/*
 * test_queen_rx_route.c — [FW.2] Маршрутизація RX Королеви + 29B-запис.
 *
 * Build & run: make -C firmware/test rx_route
 *
 * Pure-байтовий контракт (без OpenSSL): класифікація за розміром,
 * cleartext-DID демукс, 29B-запис проти ЖИВОГО golden-вектора
 * (ccm_kat_vectors.h — ті самі байти, що ганяє Rails-спека
 * Cryptography::LoraCcm) — тобто звірка саме тих октетів, які
 * process_ccm_chunk розпакує на бекенді.
 */

#include "../queen/rx_route.h"
#include "../common/ccm_kat_vectors.h"
#include <stdio.h>
#include <string.h>
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

static int test_classify_sizes(void) {
    /* Єдині два легальні розміри ефіру; все інше — шум. */
    ASSERT_EQ(Queen_Rx_Classify(16), QUEEN_RX_CONTROL_16B);
    ASSERT_EQ(Queen_Rx_Classify(FW2_CCM_AIR_PACKET_LEN), QUEEN_RX_CCM_28B);
    ASSERT_EQ(Queen_Rx_Classify(0), QUEEN_RX_DROP);
    ASSERT_EQ(Queen_Rx_Classify(1), QUEEN_RX_DROP);
    ASSERT_EQ(Queen_Rx_Classify(15), QUEEN_RX_DROP);
    ASSERT_EQ(Queen_Rx_Classify(17), QUEEN_RX_DROP);
    ASSERT_EQ(Queen_Rx_Classify(27), QUEEN_RX_DROP);
    ASSERT_EQ(Queen_Rx_Classify(29), QUEEN_RX_DROP);
    ASSERT_EQ(Queen_Rx_Classify(255), QUEEN_RX_DROP);
    printf("  test_classify_sizes                                        ✅\n");
    return 0;
}

static int test_cleartext_did_extraction(void) {
    uint8_t air[FW2_CCM_AIR_PACKET_LEN] = {0};
    air[0] = 0x53; air[1] = 0x4E; air[2] = 0x45; air[3] = 0x54; /* "SNET" */
    ASSERT_EQ(Queen_Ccm_Frame_Did(air), 0x534E4554u);

    memset(air, 0, sizeof air);
    ASSERT_EQ(Queen_Ccm_Frame_Did(air), 0u); /* DID=0 → викликач дропає (Sentinel-спуф) */
    printf("  test_cleartext_did_extraction                              ✅\n");
    return 0;
}

static int test_record_layout_synthetic(void) {
    /* air[i]=i → запис мусить бути [0,1,2,3][|rssi|][4..27] байт-у-байт. */
    uint8_t air[FW2_CCM_AIR_PACKET_LEN];
    uint8_t rec[QUEEN_CCM_RECORD_LEN];
    for (unsigned i = 0; i < sizeof air; i++) air[i] = (uint8_t)i;

    Queen_Ccm_Build_Record(air, -85, rec);
    ASSERT_MEM_EQ(&rec[0], &air[0], 4);
    ASSERT_EQ(rec[4], 85);
    ASSERT_MEM_EQ(&rec[5], &air[4], FW2_CCM_AIR_PACKET_LEN - 4u);
    printf("  test_record_layout_synthetic                               ✅\n");
    return 0;
}

static int test_rssi_convention(void) {
    /* Та сама конвенція, що 21B-legacy: |RSSI| як uint8; -128 без UB. */
    uint8_t air[FW2_CCM_AIR_PACKET_LEN] = {0};
    uint8_t rec[QUEEN_CCM_RECORD_LEN];

    Queen_Ccm_Build_Record(air, 0, rec);
    ASSERT_EQ(rec[4], 0);
    Queen_Ccm_Build_Record(air, -1, rec);
    ASSERT_EQ(rec[4], 1);
    Queen_Ccm_Build_Record(air, -128, rec);
    ASSERT_EQ(rec[4], 128);
    printf("  test_rssi_convention                                       ✅\n");
    return 0;
}

static int test_record_builders_equivalent(void) {
    /* Обидва шляхи (з ефіру та з CIFO-слота) мусять дати ІДЕНТИЧНІ 29B —
     * flush пакує з кешу, а golden-контракт доведений для air-білдера. */
    uint8_t air[FW2_CCM_AIR_PACKET_LEN];
    uint8_t rec_air[QUEEN_CCM_RECORD_LEN];
    uint8_t rec_cache[QUEEN_CCM_RECORD_LEN];
    for (unsigned i = 0; i < sizeof air; i++) air[i] = (uint8_t)(0xA0u + i);

    Queen_Ccm_Build_Record(air, -101, rec_air);
    Queen_Ccm_Build_Record_From_Cache(Queen_Ccm_Frame_Did(air), &air[4], -101, rec_cache);
    ASSERT_MEM_EQ(rec_air, rec_cache, QUEEN_CCM_RECORD_LEN);
    printf("  test_record_builders_equivalent                            ✅\n");
    return 0;
}

static int test_record_golden_vs_backend_contract(void) {
    /* e2e-зерно: air-кадр з golden-вектора → 29B-запис мусить лягти РІВНО
     * у розкладку, яку читає process_ccm_chunk (telemetry_unpacker):
     *   chunk[0..3]=DID, [4]=|RSSI|, [5]=gossip, [6..8]=FC24,
     *   [9..20]=ciphertext, [21..28]=MIC.
     * G_* — ті самі байти, що у spec/services/cryptography/lora_ccm_spec.rb. */
    uint8_t aad[FW2_CCM_AAD_LEN];
    uint8_t air[FW2_CCM_AIR_PACKET_LEN];
    uint8_t rec[QUEEN_CCM_RECORD_LEN];

    Build_CCM_AAD(G_DID, G_GOSSIP, G_FC, aad);
    memcpy(&air[0], aad, FW2_CCM_AAD_LEN);
    memcpy(&air[FW2_CCM_AAD_LEN], G_CT, FW2_CCM_PLAINTEXT_LEN);
    memcpy(&air[FW2_CCM_AAD_LEN + FW2_CCM_PLAINTEXT_LEN], G_TAG, FW2_CCM_MIC_LEN);

    Queen_Ccm_Build_Record(air, -77, rec);

    ASSERT_EQ(((uint32_t)rec[0] << 24) | ((uint32_t)rec[1] << 16) |
              ((uint32_t)rec[2] << 8)  | (uint32_t)rec[3], G_DID);
    ASSERT_EQ(rec[4], 77);
    ASSERT_EQ(rec[5], G_GOSSIP);
    ASSERT_EQ(((uint32_t)rec[6] << 16) | ((uint32_t)rec[7] << 8) | (uint32_t)rec[8], G_FC);
    ASSERT_MEM_EQ(&rec[9],  G_CT,  FW2_CCM_PLAINTEXT_LEN);
    ASSERT_MEM_EQ(&rec[21], G_TAG, FW2_CCM_MIC_LEN);
    printf("  test_record_golden_vs_backend_contract                     ✅\n");
    return 0;
}

#define RUN(test) do { \
    if (test()) { failed++; } else { passed++; } \
} while (0)

int main(void) {
    int passed = 0, failed = 0;
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.2] Queen RX-маршрутизація + 29B CoAP-запис (wire-rev2)\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    RUN(test_classify_sizes);
    RUN(test_cleartext_did_extraction);
    RUN(test_record_layout_synthetic);
    RUN(test_rssi_convention);
    RUN(test_record_builders_equivalent);
    RUN(test_record_golden_vs_backend_contract);

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d   Failed: %d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
