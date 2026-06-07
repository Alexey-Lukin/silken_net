/*
 * sym_selftest.h — On-target AES-128-ECB + AES-256-CBC Power-On Self-Test.
 *
 * [ARCH.42] Брат-близнюк ccm_selftest.h для ТРАНЗИТНИХ шляхів
 * ARCH.42: LoRa AES-128-ECB (Soldier↔Queen) та CoAP AES-256-CBC
 * (Queen↔Rails). Визначає правильність як «байти HAL == байти OpenSSL»
 * (NIST SP 800-38A вектори) — саме це потрібно бекенду.
 *
 * НАВІЩО: MX_CRYP_Init конфігурує CRYP_DATATYPE_32B; байтові масиви,
 * завантажені little-endian словами без свопу, дають per-word byte-reversal
 * відносно канонічного AES-байтопотоку. Soldier↔Queen симетричні (обидва
 * 32B) — mesh працює, а от Rails (OpenSSL) розшифрує СМІТТЯ. Host-тести
 * (passthrough-mock) цього класу помилок не бачать — його ловить ЛИШЕ
 * цей POST на живому кремнії. Якщо на bench KAT падає → перемкнути
 * DataType на CRYP_DATATYPE_8B (або своп у софті) і повторити до зеленого.
 *
 * Використання: як Ccm_Run_Self_Test — у CCM_SELFTEST-збірці, результат
 * читати через SWD (0 = PASS: кремній == OpenSSL == backend).
 */
#ifndef SYM_SELFTEST_H
#define SYM_SELFTEST_H

#include <string.h>
#include "sym_kat_vectors.h"

typedef void (*sym_selftest_report_fn)(const char *name, int pass);

/* ECB-128 KAT: encrypt → байт-збіг з NIST CT; decrypt → roundtrip.
 * Розміри HAL — у 32-бітних СЛОВАХ (16 байт = 4), як у бойових викликах. */
// cppcheck-suppress shadowVariable
static inline int Sym_Kat_Ecb128(CRYP_HandleTypeDef *hcryp) {
    uint32_t key_w[4];
    uint32_t pt_w[4], ct_w[4], rec_w[4];
    memcpy(key_w, SYM_ECB128_KEY, 16);
    memcpy(pt_w, SYM_ECB128_PT, 16);

    hcryp->Init.Algorithm = CRYP_AES_ECB;
    hcryp->Init.KeySize   = CRYP_KEYSIZE_128B;
    hcryp->Init.pKey      = key_w;
    hcryp->Init.pInitVect = NULL;
    if (HAL_CRYP_Init(hcryp) != HAL_OK) return 0;

    if (HAL_CRYP_Encrypt(hcryp, pt_w, 4, ct_w, 1000) != HAL_OK) return 0;
    if (memcmp(ct_w, SYM_ECB128_CT, 16) != 0) return 0;

    if (HAL_CRYP_Decrypt(hcryp, ct_w, 4, rec_w, 1000) != HAL_OK) return 0;
    if (memcmp(rec_w, SYM_ECB128_PT, 16) != 0) return 0;
    return 1;
}

/* CBC-256 KAT (CoAP magistral): encrypt → байт-збіг з NIST CT; roundtrip. */
// cppcheck-suppress shadowVariable
static inline int Sym_Kat_Cbc256(CRYP_HandleTypeDef *hcryp) {
    uint32_t key_w[8];
    uint32_t iv_w[4];
    uint32_t pt_w[4], ct_w[4], rec_w[4];
    memcpy(key_w, SYM_CBC256_KEY, 32);
    memcpy(pt_w, SYM_CBC256_PT, 16);

    memcpy(iv_w, SYM_CBC256_IV, 16);
    hcryp->Init.Algorithm = CRYP_AES_CBC;
    hcryp->Init.KeySize   = CRYP_KEYSIZE_256B;
    hcryp->Init.pKey      = key_w;
    hcryp->Init.pInitVect = iv_w;
    if (HAL_CRYP_Init(hcryp) != HAL_OK) return 0;

    if (HAL_CRYP_Encrypt(hcryp, pt_w, 4, ct_w, 1000) != HAL_OK) return 0;
    if (memcmp(ct_w, SYM_CBC256_CT, 16) != 0) return 0;

    /* CBC decrypt мутує chaining-стан — свіжий IV перед roundtrip */
    memcpy(iv_w, SYM_CBC256_IV, 16);
    if (HAL_CRYP_Init(hcryp) != HAL_OK) return 0;
    if (HAL_CRYP_Decrypt(hcryp, ct_w, 4, rec_w, 1000) != HAL_OK) return 0;
    if (memcmp(rec_w, SYM_CBC256_PT, 16) != 0) return 0;
    return 1;
}

/* POST обох транзитних шляхів. Повертає кількість FAILED (0 = атестація OK).
 * УВАГА: лишає hcryp у CBC-конфігурації — викликач відновлює бойовий
 * контекст (Soldier: MX_CRYP_Init; Queen: Restore_ECB_Mode). */
// cppcheck-suppress shadowVariable
static inline int Sym_Run_Self_Test(CRYP_HandleTypeDef *hcryp,
                                    sym_selftest_report_fn report) {
    int failed = 0;

    int ecb_pass = Sym_Kat_Ecb128(hcryp);
    if (!ecb_pass) failed++;
    if (report) report("ECB-128 LoRa path (SP 800-38A F.1.1)", ecb_pass);

    int cbc_pass = Sym_Kat_Cbc256(hcryp);
    if (!cbc_pass) failed++;
    if (report) report("CBC-256 CoAP path (SP 800-38A F.2.5)", cbc_pass);

    return failed;
}

#endif /* SYM_SELFTEST_H */
