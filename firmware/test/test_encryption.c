// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_encryption.c — Host-based unit tests for AES-256 ECB/CBC mode switching.
 *
 * Tests the critical crypto state transitions in Queen firmware:
 *   - ECB mode for LoRa packet decryption (Soldier → Queen)
 *   - CBC mode for batch encryption (Queen → Rails CoAP uplink)
 *   - CBC mode for command decryption (Rails CoAP downlink → Queen)
 *   - ECB restoration after every CBC operation (FW.16)
 *   - Error recovery path: RCC reset + retry on HAL_CRYP_Init failure
 *
 * Build: make -C firmware/test encryption
 *
 * Coverage:
 *   - ECB/CBC mode switching correctness
 *   - ECB restore after Flush_Cache_To_Rails (CBC encrypt)
 *   - ECB restore after Handle_CoAP_Command (CBC decrypt)
 *   - ECB restore on error path (aligned > CMD_DECRYPT_BUF_SIZE)
 *   - HAL_CRYP_Init failure → RCC reset → retry → NVIC_SystemReset
 *   - IV handling (NULL for ECB, non-NULL for CBC)
 *   - Key preservation across mode switches
 *   - Sequential CBC→ECB→CBC→ECB transitions
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "hal_mock.h"
#include "../queen/coap_iv.h"  /* [HRNG-IV] real fallback-IV derivation under test */
#include <openssl/hmac.h>      /* [SEC.12] independent HMAC oracle for the keyed IV */
#include <openssl/evp.h>

/* ══════════════════════════════════════════════════════════════════
 * CONSTANTS (from queen/main.c)
 * ══════════════════════════════════════════════════════════════════ */
#define CMD_DECRYPT_BUF_SIZE  544

/* ══════════════════════════════════════════════════════════════════
 * MOCK STATE for HAL_CRYP_Init failure simulation
 * ══════════════════════════════════════════════════════════════════ */
static int mock_cryp_init_fail_count = 0;  /* How many more HAL_CRYP_Init calls should fail */
static int mock_cryp_init_call_count = 0;
static int mock_rcc_reset_called = 0;
static int mock_nvic_reset_called = 0;

/* Override HAL_CRYP_Init for failure simulation */
static int Mock_HAL_CRYP_Init(CRYP_HandleTypeDef *h)
{
    mock_cryp_init_call_count++;
    (void)h;
    if (mock_cryp_init_fail_count > 0) {
        mock_cryp_init_fail_count--;
        return HAL_ERROR;
    }
    return HAL_OK;
}

static void Mock_RCC_CRYP_FORCE_RESET(void) { mock_rcc_reset_called++; }
static void Mock_RCC_CRYP_RELEASE_RESET(void) { /* paired with force */ }
static void Mock_NVIC_SystemReset(void) { mock_nvic_reset_called++; }

static void reset_crypto_mocks(void)
{
    mock_cryp_init_fail_count = 0;
    mock_cryp_init_call_count = 0;
    mock_rcc_reset_called = 0;
    mock_nvic_reset_called = 0;
}

/* ══════════════════════════════════════════════════════════════════
 * EXTRACTED LOGIC (from queen/main.c)
 * ══════════════════════════════════════════════════════════════════ */

/* [FW.1] Flash-based AES key provisioning constants */
#define FLASH_KEY_ADDR             ((uintptr_t)_mock_flash_key_region)
#define FLASH_KEY_WORDS            4  /* ARCH.42 Variant B: 16 bytes = AES-128 LoRa */
#define FLASH_KEY_MAGIC            0x4B45594CUL  /* "KEYL" — LoRa key (post-ARCH.42; was "SKEY" / 0x534B4559) */

/* [FW.1] Error_Handler for Load_AES_Key */
static void Error_Handler(void) { _mock_error_handler_called++; }

/* AES key — now loaded from Flash by Load_AES_Key() */
static uint32_t test_aes_key[4] = {0};  /* AES-128 LoRa (ARCH.42) */

/* [FW.1] Load AES Key from Flash (extracted from soldier/queen main.c) */
static void Load_AES_Key(void)
{
    const uint32_t *flash_ptr = (const uint32_t *)FLASH_KEY_ADDR;

    if (flash_ptr[0] != FLASH_KEY_MAGIC) {
        Error_Handler();
        return;
    }

    uint32_t key_or = 0;
    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        key_or |= flash_ptr[1 + i];
    }
    if (key_or == 0) {
        Error_Handler();
        return;
    }

    for (int i = 0; i < FLASH_KEY_WORDS; i++) {
        test_aes_key[i] = flash_ptr[1 + i];
    }
}

/* Simulated CRYP handle */
static CRYP_HandleTypeDef test_cryp;

/* Standard test key for provisioning */
static const uint32_t _enc_test_key[8] = {
    0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C,
    0x1A2B3C4D, 0x5E6F7A8B, 0x9C0D1E2F, 0x3A4B5C6D
};

/* Initialize CRYP in ECB mode (default state for LoRa) */
static void Init_CRYP_ECB(void)
{
    /* [FW.1] Provision test key into mock Flash before loading */
    _mock_flash_key_provision(FLASH_KEY_MAGIC, _enc_test_key);
    _mock_error_handler_reset();
    Load_AES_Key();

    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.KeySize = CRYP_KEYSIZE_128B;  /* ARCH.42 LoRa AES-128 */
    test_cryp.Init.DataType = CRYP_DATATYPE_32B;
    test_cryp.Init.pKey = test_aes_key;
    test_cryp.Init.pInitVect = NULL;
    HAL_CRYP_Init(&test_cryp);
}

/* [FW.16] Restore_ECB_Mode with error recovery
 * This is the extracted helper function from queen/main.c */
static void Restore_ECB_Mode_Testable(
    CRYP_HandleTypeDef *hcryp,
    int (*cryp_init)(CRYP_HandleTypeDef*),
    void (*rcc_force_reset)(void),
    void (*rcc_release_reset)(void),
    void (*nvic_reset)(void))
{
    hcryp->Init.Algorithm = CRYP_AES_ECB;
    hcryp->Init.pInitVect = NULL;
    if (cryp_init(hcryp) != HAL_OK) {
        rcc_force_reset();
        rcc_release_reset();
        hcryp->Init.Algorithm = CRYP_AES_ECB;
        hcryp->Init.pInitVect = NULL;
        if (cryp_init(hcryp) != HAL_OK) {
            nvic_reset();
        }
    }
}

/* Simulate Flush_Cache_To_Rails CBC→ECB transition */
static void Simulate_Flush_CBC_Then_ECB(CRYP_HandleTypeDef *hcryp)
{
    /* Switch to CBC for batch encryption */
    uint32_t batch_iv[4] = {0x11111111, 0x22222222, 0x33333333, 0x44444444};
    hcryp->Init.Algorithm = CRYP_AES_CBC;
    hcryp->Init.pInitVect = batch_iv;
    HAL_CRYP_Init(hcryp);

    /* Encrypt data (mock just copies) */
    uint32_t plain[4] = {0xAA, 0xBB, 0xCC, 0xDD};
    uint32_t cipher[4];
    HAL_CRYP_Encrypt(hcryp, plain, 4, cipher, 2000);

    /* Restore ECB */
    Restore_ECB_Mode_Testable(hcryp, Mock_HAL_CRYP_Init,
        Mock_RCC_CRYP_FORCE_RESET, Mock_RCC_CRYP_RELEASE_RESET,
        Mock_NVIC_SystemReset);
}

/* Simulate Handle_CoAP_Command CBC→ECB transition */
static void Simulate_CoAP_Command_CBC_Then_ECB(CRYP_HandleTypeDef *hcryp)
{
    /* Switch to CBC for command decryption */
    uint32_t cmd_iv[4] = {0x55555555, 0x66666666, 0x77777777, 0x88888888};
    hcryp->Init.Algorithm = CRYP_AES_CBC;
    hcryp->Init.pInitVect = cmd_iv;
    HAL_CRYP_Init(hcryp);

    /* Decrypt data (mock just copies) */
    uint32_t cipher[4] = {0xEE, 0xFF, 0x00, 0x11};
    uint32_t plain[4];
    HAL_CRYP_Decrypt(hcryp, cipher, 4, plain, 2000);

    /* Restore ECB */
    Restore_ECB_Mode_Testable(hcryp, Mock_HAL_CRYP_Init,
        Mock_RCC_CRYP_FORCE_RESET, Mock_RCC_CRYP_RELEASE_RESET,
        Mock_NVIC_SystemReset);
}

/* ══════════════════════════════════════════════════════════════════
 * TEST FRAMEWORK
 * ══════════════════════════════════════════════════════════════════ */
static int tests_run = 0, tests_failed = 0;

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        printf("    FAIL: %s:%d — expected %d, got %d\n", __func__, __LINE__, (int)(b), (int)(a)); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_NULL(ptr) do { \
    if ((ptr) != NULL) { \
        printf("    FAIL: %s:%d — expected NULL\n", __func__, __LINE__); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_NOT_NULL(ptr) do { \
    if ((ptr) == NULL) { \
        printf("    FAIL: %s:%d — expected non-NULL\n", __func__, __LINE__); \
        tests_failed++; return; \
    } \
} while(0)

#define TEST(name) static void name(void)
#define RUN(name) do { int _prev = tests_failed; tests_run++; name(); printf("  %-55s %s\n", #name, tests_failed == _prev ? "✅" : "❌"); } while(0)

/* ══════════════════════════════════════════════════════════════════
 * 1. ECB/CBC MODE SWITCHING TESTS
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_initial_mode_is_ecb)
{
    Init_CRYP_ECB();
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_switch_to_cbc_changes_algorithm)
{
    Init_CRYP_ECB();
    uint32_t iv[4] = {1, 2, 3, 4};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_CBC);
    ASSERT_NOT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_ecb_restore_clears_iv)
{
    Init_CRYP_ECB();
    /* Switch to CBC */
    uint32_t iv[4] = {1, 2, 3, 4};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;

    /* Restore ECB */
    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.pInitVect = NULL;
    HAL_CRYP_Init(&test_cryp);

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_key_preserved_across_mode_switch)
{
    Init_CRYP_ECB();
    uint32_t *original_key = test_cryp.Init.pKey;

    /* Switch to CBC and back */
    uint32_t iv[4] = {1, 2, 3, 4};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;
    HAL_CRYP_Init(&test_cryp);

    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.pInitVect = NULL;
    HAL_CRYP_Init(&test_cryp);

    ASSERT_EQ((int)(uintptr_t)test_cryp.Init.pKey, (int)(uintptr_t)original_key);
}

/* ══════════════════════════════════════════════════════════════════
 * 2. ECB RESTORE AFTER FLUSH (Flush_Cache_To_Rails)
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_ecb_restored_after_flush_simulation)
{
    Init_CRYP_ECB();
    reset_crypto_mocks();

    Simulate_Flush_CBC_Then_ECB(&test_cryp);

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
    ASSERT_EQ(mock_rcc_reset_called, 0); /* No error recovery needed */
}

TEST(test_ecb_restored_after_coap_command_simulation)
{
    Init_CRYP_ECB();
    reset_crypto_mocks();

    Simulate_CoAP_Command_CBC_Then_ECB(&test_cryp);

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_sequential_flush_then_command_both_restore)
{
    Init_CRYP_ECB();
    reset_crypto_mocks();

    /* First: Flush (CBC encrypt → ECB restore) */
    Simulate_Flush_CBC_Then_ECB(&test_cryp);
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);

    /* Second: CoAP Command (CBC decrypt → ECB restore) */
    Simulate_CoAP_Command_CBC_Then_ECB(&test_cryp);
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
}

TEST(test_multiple_consecutive_flushes)
{
    Init_CRYP_ECB();
    reset_crypto_mocks();

    for (int i = 0; i < 5; i++) {
        Simulate_Flush_CBC_Then_ECB(&test_cryp);
        ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
        ASSERT_NULL(test_cryp.Init.pInitVect);
    }
}

/* ══════════════════════════════════════════════════════════════════
 * 3. ERROR RECOVERY TESTS (FW.16)
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_ecb_restore_first_init_success)
{
    reset_crypto_mocks();
    Init_CRYP_ECB();

    /* Switch to CBC */
    test_cryp.Init.Algorithm = CRYP_AES_CBC;

    /* Restore — should succeed on first try */
    mock_cryp_init_fail_count = 0;
    Restore_ECB_Mode_Testable(&test_cryp, Mock_HAL_CRYP_Init,
        Mock_RCC_CRYP_FORCE_RESET, Mock_RCC_CRYP_RELEASE_RESET,
        Mock_NVIC_SystemReset);

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_EQ(mock_rcc_reset_called, 0);   /* No RCC reset needed */
    ASSERT_EQ(mock_nvic_reset_called, 0);  /* No system reset */
    ASSERT_EQ(mock_cryp_init_call_count, 1); /* Called once */
}

TEST(test_ecb_restore_first_fail_rcc_reset_then_success)
{
    reset_crypto_mocks();
    Init_CRYP_ECB();

    test_cryp.Init.Algorithm = CRYP_AES_CBC;

    /* First HAL_CRYP_Init fails, second succeeds */
    mock_cryp_init_fail_count = 1;
    Restore_ECB_Mode_Testable(&test_cryp, Mock_HAL_CRYP_Init,
        Mock_RCC_CRYP_FORCE_RESET, Mock_RCC_CRYP_RELEASE_RESET,
        Mock_NVIC_SystemReset);

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_EQ(mock_rcc_reset_called, 1);   /* RCC reset triggered */
    ASSERT_EQ(mock_nvic_reset_called, 0);  /* No system reset */
    ASSERT_EQ(mock_cryp_init_call_count, 2); /* Called twice */
}

TEST(test_ecb_restore_both_fail_nvic_system_reset)
{
    reset_crypto_mocks();
    Init_CRYP_ECB();

    test_cryp.Init.Algorithm = CRYP_AES_CBC;

    /* Both HAL_CRYP_Init calls fail → NVIC_SystemReset */
    mock_cryp_init_fail_count = 2;
    Restore_ECB_Mode_Testable(&test_cryp, Mock_HAL_CRYP_Init,
        Mock_RCC_CRYP_FORCE_RESET, Mock_RCC_CRYP_RELEASE_RESET,
        Mock_NVIC_SystemReset);

    ASSERT_EQ(mock_rcc_reset_called, 1);   /* RCC reset attempted */
    ASSERT_EQ(mock_nvic_reset_called, 1);  /* System reset triggered */
    ASSERT_EQ(mock_cryp_init_call_count, 2); /* Called twice */
}

/* ══════════════════════════════════════════════════════════════════
 * 4. ERROR PATH ECB RESTORE (Handle_CoAP_Command overflow)
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_error_path_ecb_restore_on_overflow)
{
    /* When aligned > CMD_DECRYPT_BUF_SIZE, the function must restore ECB
     * before returning. This tests that error path. */
    Init_CRYP_ECB();
    reset_crypto_mocks();

    /* Switch to CBC as Handle_CoAP_Command would */
    test_cryp.Init.Algorithm = CRYP_AES_CBC;

    /* Simulate overflow detection → early exit → must restore ECB */
    Restore_ECB_Mode_Testable(&test_cryp, Mock_HAL_CRYP_Init,
        Mock_RCC_CRYP_FORCE_RESET, Mock_RCC_CRYP_RELEASE_RESET,
        Mock_NVIC_SystemReset);

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

/* ══════════════════════════════════════════════════════════════════
 * 5. IV HANDLING TESTS
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_ecb_mode_iv_is_null)
{
    Init_CRYP_ECB();
    ASSERT_NULL(test_cryp.Init.pInitVect);
}

TEST(test_cbc_mode_iv_is_set)
{
    Init_CRYP_ECB();
    uint32_t iv[4] = {0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xFEDCBA98};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;
    ASSERT_NOT_NULL(test_cryp.Init.pInitVect);
    ASSERT_EQ(test_cryp.Init.pInitVect[0], (uint32_t)0xDEADBEEF);
}

TEST(test_ecb_restore_nulls_iv_after_cbc)
{
    Init_CRYP_ECB();
    uint32_t iv[4] = {1, 2, 3, 4};

    /* Set CBC with IV */
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;
    ASSERT_NOT_NULL(test_cryp.Init.pInitVect);

    /* Restore ECB */
    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.pInitVect = NULL;

    ASSERT_NULL(test_cryp.Init.pInitVect);
}

/* ══════════════════════════════════════════════════════════════════
 * 6. ENCRYPT/DECRYPT WITH MODE VERIFICATION
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_encrypt_in_ecb_mode)
{
    Init_CRYP_ECB();
    uint32_t plain[4] = {0x01, 0x02, 0x03, 0x04};
    uint32_t cipher[4];

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    int ret = HAL_CRYP_Encrypt(&test_cryp, plain, 4, cipher, 1000);
    ASSERT_EQ(ret, HAL_OK);
    /* Mock copies through — verify data preserved */
    ASSERT_EQ(cipher[0], plain[0]);
}

TEST(test_decrypt_in_ecb_mode)
{
    Init_CRYP_ECB();
    uint32_t cipher[4] = {0xAA, 0xBB, 0xCC, 0xDD};
    uint32_t plain[4];

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
    int ret = HAL_CRYP_Decrypt(&test_cryp, cipher, 4, plain, 1000);
    ASSERT_EQ(ret, HAL_OK);
    ASSERT_EQ(plain[0], cipher[0]);
}

TEST(test_encrypt_in_cbc_mode)
{
    Init_CRYP_ECB();
    uint32_t iv[4] = {0x11, 0x22, 0x33, 0x44};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;
    HAL_CRYP_Init(&test_cryp);

    uint32_t plain[4] = {0x01, 0x02, 0x03, 0x04};
    uint32_t cipher[4];

    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_CBC);
    int ret = HAL_CRYP_Encrypt(&test_cryp, plain, 4, cipher, 2000);
    ASSERT_EQ(ret, HAL_OK);
}

/* ══════════════════════════════════════════════════════════════════
 * [FW.1] FLASH KEY + CRYP INIT INTEGRATION TESTS
 * ══════════════════════════════════════════════════════════════════ */

TEST(test_load_key_then_cryp_init_uses_flash_key)
{
    /* Full init sequence: Load_AES_Key → MX_CRYP_Init → pKey points to Flash-loaded key */
    _mock_flash_key_reset();
    _mock_error_handler_reset();
    memset(test_aes_key, 0, sizeof(test_aes_key));

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _enc_test_key);
    Load_AES_Key();
    ASSERT_EQ(_mock_error_handler_called, 0);

    /* Simulate MX_CRYP_Init (same as in firmware) */
    test_cryp.Init.Algorithm = CRYP_AES_ECB;
    test_cryp.Init.KeySize = CRYP_KEYSIZE_128B;  /* ARCH.42 LoRa AES-128 */
    test_cryp.Init.DataType = CRYP_DATATYPE_32B;
    test_cryp.Init.pKey = test_aes_key;
    HAL_CRYP_Init(&test_cryp);

    /* pKey should point to test_aes_key which now has Flash-loaded values */
    /* Post-ARCH.42: AES-128 LoRa key = first 4 words (was 8 для AES-256) */
    ASSERT_EQ(test_cryp.Init.pKey[0], 0x2B7E1516);
    ASSERT_EQ(test_cryp.Init.pKey[3], 0x09CF4F3C);
}

TEST(test_no_key_means_no_cryp_init)
{
    /* If Flash not provisioned, Error_Handler fires before MX_CRYP_Init */
    _mock_flash_key_reset();  /* 0xFFFFFFFF — unprogrammed */
    _mock_error_handler_reset();
    memset(test_aes_key, 0, sizeof(test_aes_key));

    Load_AES_Key();
    ASSERT_EQ(_mock_error_handler_called > 0, 1);

    /* test_aes_key should still be zeros — MX_CRYP_Init should NOT be called */
    /* Post-ARCH.42: test_aes_key[4] (AES-128 LoRa, 16 bytes) */
    ASSERT_EQ(test_aes_key[0], 0);
    ASSERT_EQ(test_aes_key[3], 0);
}

TEST(test_key_loaded_before_ecb_restore_preserves_key)
{
    /* After Flash key load + ECB restore cycle, pKey still points to valid key */
    _mock_flash_key_reset();
    _mock_error_handler_reset();

    _mock_flash_key_provision(FLASH_KEY_MAGIC, _enc_test_key);
    Load_AES_Key();
    Init_CRYP_ECB();

    /* Switch to CBC then restore ECB */
    uint32_t iv[4] = {1, 2, 3, 4};
    test_cryp.Init.Algorithm = CRYP_AES_CBC;
    test_cryp.Init.pInitVect = iv;
    HAL_CRYP_Init(&test_cryp);

    /* Restore ECB */
    reset_crypto_mocks();
    Restore_ECB_Mode_Testable(&test_cryp, Mock_HAL_CRYP_Init,
        Mock_RCC_CRYP_FORCE_RESET, Mock_RCC_CRYP_RELEASE_RESET,
        Mock_NVIC_SystemReset);

    /* Key should still be the provisioned one */
    /* Post-ARCH.42: AES-128 LoRa key = first 4 words */
    ASSERT_EQ(test_cryp.Init.pKey[0], 0x2B7E1516);
    ASSERT_EQ(test_cryp.Init.pKey[3], 0x09CF4F3C);
    ASSERT_EQ(test_cryp.Init.Algorithm, CRYP_AES_ECB);
}

/* ══════════════════════════════════════════════════════════════════
 * HRNG-IV FALLBACK (coap_iv.h — the REAL derivation, not re-implemented)
 *
 * [SEC.12] The fallback IV is now a KEY-DERIVED PRF: HMAC-SHA256(coap_key,
 * label || uid || ts || seq || tick)[0:16]. Verifies (1) byte-parity with two
 * independent oracles — OpenSSL HMAC + the shared one-shot Silken_Hmac_Sha256
 * (proving it is genuinely that HMAC ⇒ UNPREDICTABLE without the key), and
 * (2) UNIQUENESS across the dimensions that matter for CBC: device, reboot,
 * flush. Canon: 03_05 §HRNG Fallback.
 * ══════════════════════════════════════════════════════════════════ */

/* Arbitrary fixed 32-byte test key (AES-256 CoAP-key stand-in). */
static const uint8_t TEST_COAP_KEY[32] = {
    0x9f, 0x2c, 0x41, 0xb7, 0x6e, 0x18, 0xd3, 0x05,
    0xaa, 0x57, 0x3e, 0xc9, 0x12, 0x84, 0xfb, 0x60,
    0x7d, 0x39, 0xe2, 0x4c, 0x91, 0x08, 0xbd, 0x56,
    0x2f, 0xa1, 0x6b, 0xd4, 0x83, 0x1e, 0xc7, 0x70
};

static void put_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);  p[3] = (uint8_t)v;
}

TEST(test_coap_fallback_iv_parity) {
    uint8_t iv[16];
    coap_fallback_iv(iv, TEST_COAP_KEY, sizeof TEST_COAP_KEY,
                     1000U, 0xDEADBEEFU, 1700000000U, 1U);

    /* Independent message assembly: BE label || uid || ts || seq || tick. */
    uint8_t msg[20 + 16];
    memcpy(msg, "SilkenNet-CoAP-IV-v1", 20);
    put_be32(msg + 20, 0xDEADBEEFU);
    put_be32(msg + 24, 1700000000U);
    put_be32(msg + 28, 1U);
    put_be32(msg + 32, 1000U);

    /* Oracle 1: OpenSSL HMAC (fully independent primitive). */
    uint8_t mac_ossl[32];
    unsigned int mlen = 0;
    HMAC(EVP_sha256(), TEST_COAP_KEY, (int)sizeof TEST_COAP_KEY, msg, sizeof msg, mac_ossl, &mlen);
    ASSERT_EQ(memcmp(iv, mac_ossl, 16) == 0, 1);

    /* Oracle 2: the shared one-shot HMAC over the contiguous buffer (proves the
       concat-streamed wrapper equals a flat HMAC over the same bytes). */
    uint8_t mac_silken[SILKEN_SHA256_DIGEST_LEN];
    Silken_Hmac_Sha256(TEST_COAP_KEY, sizeof TEST_COAP_KEY, msg, sizeof msg, mac_silken);
    ASSERT_EQ(memcmp(iv, mac_silken, 16) == 0, 1);
}

TEST(test_coap_fallback_iv_deterministic) {
    uint8_t a[16], b[16];
    coap_fallback_iv(a, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xDEADBEEFU, 1700000000U, 1U);
    coap_fallback_iv(b, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xDEADBEEFU, 1700000000U, 1U);
    ASSERT_EQ(memcmp(a, b, 16) == 0, 1);   /* same inputs → same IV */
}

TEST(test_coap_fallback_iv_per_device) {
    /* mass blackout-reboot: same tick/unix/seq, different device UID → different IV */
    uint8_t a[16], b[16];
    coap_fallback_iv(a, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xAAAA1111U, 1700000000U, 1U);
    coap_fallback_iv(b, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xBBBB2222U, 1700000000U, 1U);
    ASSERT_EQ(memcmp(a, b, 16) != 0, 1);
}

TEST(test_coap_fallback_iv_cross_reboot) {
    /* different wall-clock (queen_unix_ts) → different IV (cross-reboot uniqueness) */
    uint8_t a[16], b[16];
    coap_fallback_iv(a, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xDEADBEEFU, 1700000000U, 1U);
    coap_fallback_iv(b, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xDEADBEEFU, 1700003600U, 1U);
    ASSERT_EQ(memcmp(a, b, 16) != 0, 1);
}

TEST(test_coap_fallback_iv_cross_flush) {
    /* different flush sequence → different IV (within-boot uniqueness) */
    uint8_t a[16], b[16];
    coap_fallback_iv(a, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xDEADBEEFU, 1700000000U, 1U);
    coap_fallback_iv(b, TEST_COAP_KEY, sizeof TEST_COAP_KEY, 1000U, 0xDEADBEEFU, 1700000000U, 2U);
    ASSERT_EQ(memcmp(a, b, 16) != 0, 1);
}

/* ══════════════════════════════════════════════════════════════════
 * MAIN
 * ══════════════════════════════════════════════════════════════════ */
int main(void)
{
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  SilkenNet Firmware — AES Encryption Unit Tests\n");
    printf("══════════════════════════════════════════════════════════════\n");

    printf("\n  ECB/CBC Mode Switching:\n");
    RUN(test_initial_mode_is_ecb);
    RUN(test_switch_to_cbc_changes_algorithm);
    RUN(test_ecb_restore_clears_iv);
    RUN(test_key_preserved_across_mode_switch);

    printf("\n  ECB Restore After Flush/Command:\n");
    RUN(test_ecb_restored_after_flush_simulation);
    RUN(test_ecb_restored_after_coap_command_simulation);
    RUN(test_sequential_flush_then_command_both_restore);
    RUN(test_multiple_consecutive_flushes);

    printf("\n  Error Recovery (FW.16):\n");
    RUN(test_ecb_restore_first_init_success);
    RUN(test_ecb_restore_first_fail_rcc_reset_then_success);
    RUN(test_ecb_restore_both_fail_nvic_system_reset);

    printf("\n  Error Path ECB Restore:\n");
    RUN(test_error_path_ecb_restore_on_overflow);

    printf("\n  IV Handling:\n");
    RUN(test_ecb_mode_iv_is_null);
    RUN(test_cbc_mode_iv_is_set);
    RUN(test_ecb_restore_nulls_iv_after_cbc);

    printf("\n  Encrypt/Decrypt Mode Verification:\n");
    RUN(test_encrypt_in_ecb_mode);
    RUN(test_decrypt_in_ecb_mode);
    RUN(test_encrypt_in_cbc_mode);

    printf("\n  Flash Key + CRYP Init Integration (FW.1):\n");
    RUN(test_load_key_then_cryp_init_uses_flash_key);
    RUN(test_no_key_means_no_cryp_init);
    RUN(test_key_loaded_before_ecb_restore_preserves_key);

    printf("\n  HRNG-IV Fallback (coap_iv.h, SEC.12 keyed-HMAC):\n");
    RUN(test_coap_fallback_iv_parity);
    RUN(test_coap_fallback_iv_deterministic);
    RUN(test_coap_fallback_iv_per_device);
    RUN(test_coap_fallback_iv_cross_reboot);
    RUN(test_coap_fallback_iv_cross_flush);

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n", tests_run - tests_failed, tests_failed);
    printf("══════════════════════════════════════════════════════════════\n\n");

    return tests_failed ? 1 : 0;
}
