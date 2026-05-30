/*
 * ccm_kat_vectors.h — Known-Answer Test (KAT) vectors for AES-128-CCM.
 *
 * [FW.2 / ARCH.42 Variant B] Single source of truth for the CCM test
 * vectors, shared by:
 *   - firmware/test/test_ccm.c          (host parity vs Cryptography::LoraCcm)
 *   - firmware/common/ccm_selftest.h    (on-target POST / bench attestation)
 *
 * Oracle = OpenSSL EVP aes-128-ccm (12-byte nonce, 8-byte tag) — the same
 * primitive the Rails backend (`Cryptography::LoraCcm`) uses, so a PASS on
 * real STM32WLE5JC silicon proves  silicon == OpenSSL == backend.
 *
 * The golden vector is the canonical anchor (zero key); the extras vary
 * key / nonce / AAD / plaintext so the KAT exercises more of the codebook.
 * All vectors use the FW.2 fixed shape: 16-byte key, 12-byte nonce,
 * 8-byte AAD, 8-byte plaintext, 8-byte ciphertext, 8-byte tag.
 *
 * NB (industrial follow-up): adding the official NIST SP 800-38C Appendix C
 * Example 3 (Klen=128, Tlen=64, Nlen=96 — matches this config) as a
 * third-party oracle is a worthwhile belt-and-suspenders KAT; left as a
 * marked TODO rather than transcribed from memory.
 */
#ifndef CCM_KAT_VECTORS_H
#define CCM_KAT_VECTORS_H

#include <stdint.h>

/* ── Golden vector (canonical; also asserted in test_ccm.c) ──────────────
 * zero key + DID 0x01020304 + FC 5 + plaintext 01..08
 *   → ciphertext 08ceca97bbf4fdc5 , tag a6d8e20ce0deeae9
 */
static const uint8_t  G_ZERO_KEY[16] = { 0 };
static const uint32_t G_DID = 0x01020304;
static const uint32_t G_FC  = 5;
static const uint8_t  G_PT[8]  = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
static const uint8_t  G_CT[8]  = { 0x08, 0xce, 0xca, 0x97, 0xbb, 0xf4, 0xfd, 0xc5 };
static const uint8_t  G_TAG[8] = { 0xa6, 0xd8, 0xe2, 0x0c, 0xe0, 0xde, 0xea, 0xe9 };

/* ── Extra KAT vectors (raw nonce/AAD, OpenSSL-oracle-derived) ──────────── */
typedef struct {
    const char *name;
    uint8_t key[16];
    uint8_t nonce[12];   /* DID(4) || FC(4 BE) || 0x00 x4 */
    uint8_t aad[8];      /* DID(4) || FC(4 BE) */
    uint8_t pt[8];
    uint8_t ct[8];
    uint8_t tag[8];
} CcmKatVector;

static const CcmKatVector CCM_KAT_EXTRA[] = {
    {
        .name  = "KAT1 key=0xAA*16 DID=DEADBEEF FC=1",
        .key   = { 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa },
        .nonce = { 0xde, 0xad, 0xbe, 0xef, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 },
        .aad   = { 0xde, 0xad, 0xbe, 0xef, 0x00, 0x00, 0x00, 0x01 },
        .pt    = { 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80 },
        .ct    = { 0xf6, 0x33, 0x04, 0x41, 0x60, 0x8a, 0x7e, 0xc2 },
        .tag   = { 0x97, 0x57, 0x88, 0x68, 0xf4, 0x18, 0xc9, 0x63 },
    },
    {
        .name  = "KAT2 key=00..0f DID=SNET FC=65535",
        .key   = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f },
        .nonce = { 0x53, 0x4e, 0x45, 0x54, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00 },
        .aad   = { 0x53, 0x4e, 0x45, 0x54, 0x00, 0x00, 0xff, 0xff },
        .pt    = { 0xff, 0x00, 0xff, 0x00, 0x11, 0x22, 0x33, 0x44 },
        .ct    = { 0x6c, 0xf4, 0xc7, 0xad, 0xfc, 0x28, 0x26, 0x59 },
        .tag   = { 0xde, 0x95, 0xc8, 0x2c, 0xd1, 0x1d, 0xed, 0xb1 },
    },
};
#define CCM_KAT_EXTRA_COUNT (sizeof(CCM_KAT_EXTRA) / sizeof(CCM_KAT_EXTRA[0]))

#endif /* CCM_KAT_VECTORS_H */
