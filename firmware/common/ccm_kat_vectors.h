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
 * All vectors use the FW.2 wire-rev2 shape (founder decision 2026-06-12):
 * 16-byte key, 12-byte nonce, 8-byte AAD = DID(4)||gossip(1)||FC24(3 BE),
 * 12-byte plaintext, 12-byte ciphertext, 8-byte tag. KAT1/KAT2 carry a
 * non-zero gossip byte so the new AAD layout is exercised end-to-end.
 * Regenerated 2026-06-12 via OpenSSL oracle (tools: /tmp one-off, the
 * recipe documented in docs/03_05 wire-budget ledger).
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
 * zero key + DID 0x01020304 + gossip 0x00 + FC 5 + plaintext 01..0c
 *   → ciphertext 08ceca97bbf4fdc5aa2a365e , tag 2e68947871a505c4
 * (Перші 8 байт CT збігаються з rev1-вектором — той самий CTR-keystream
 *  при незмінному нонсі; tag інший, бо покриває довший PT.)
 */
static const uint8_t  G_ZERO_KEY[16] = { 0 };
static const uint32_t G_DID = 0x01020304;
static const uint32_t G_FC  = 5;
static const uint8_t  G_GOSSIP = 0x00;
static const uint8_t  G_PT[12]  = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c };
static const uint8_t  G_CT[12]  = { 0x08, 0xce, 0xca, 0x97, 0xbb, 0xf4, 0xfd, 0xc5, 0xaa, 0x2a, 0x36, 0x5e };
static const uint8_t  G_TAG[8] = { 0x2e, 0x68, 0x94, 0x78, 0x71, 0xa5, 0x05, 0xc4 };

/* ── Extra KAT vectors (raw nonce/AAD, OpenSSL-oracle-derived) ──────────── */
typedef struct {
    const char *name;
    uint8_t key[16];
    uint8_t nonce[12];   /* DID(4) || FC(4 BE, top 0x00) || 0x00 x4 */
    uint8_t aad[8];      /* DID(4) || gossip(1) || FC(3 BE) */
    uint8_t pt[12];
    uint8_t ct[12];
    uint8_t tag[8];
} CcmKatVector;

static const CcmKatVector CCM_KAT_EXTRA[] = {
    {
        .name  = "KAT1 key=0xAA*16 DID=DEADBEEF FC=1 gossip=0x5A",
        .key   = { 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa },
        .nonce = { 0xde, 0xad, 0xbe, 0xef, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 },
        .aad   = { 0xde, 0xad, 0xbe, 0xef, 0x5a, 0x00, 0x00, 0x01 },
        .pt    = { 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0xa0, 0xb0, 0xc0 },
        .ct    = { 0xf6, 0x33, 0x04, 0x41, 0x60, 0x8a, 0x7e, 0xc2, 0xcc, 0x4b, 0x07, 0x67 },
        .tag   = { 0xa9, 0x70, 0xe9, 0x43, 0x79, 0x97, 0x68, 0xc1 },
    },
    {
        .name  = "KAT2 key=00..0f DID=SNET FC=65535 gossip=0xFF",
        .key   = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f },
        .nonce = { 0x53, 0x4e, 0x45, 0x54, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00 },
        .aad   = { 0x53, 0x4e, 0x45, 0x54, 0xff, 0x00, 0xff, 0xff },
        .pt    = { 0xff, 0x00, 0xff, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 },
        .ct    = { 0x6c, 0xf4, 0xc7, 0xad, 0xfc, 0x28, 0x26, 0x59, 0x4e, 0xfc, 0x50, 0xec },
        .tag   = { 0x3d, 0x08, 0xad, 0x50, 0x65, 0x27, 0x9d, 0x15 },
    },
};
#define CCM_KAT_EXTRA_COUNT (sizeof(CCM_KAT_EXTRA) / sizeof(CCM_KAT_EXTRA[0]))

#endif /* CCM_KAT_VECTORS_H */
