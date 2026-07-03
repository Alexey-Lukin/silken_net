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
 * All vectors use the FW.2 wire-rev2.1 shape (founder decisions 2026-06-12
 * rev2 + 2026-07-03 rev2.1 [E.63 гейт (г)]: +2B EMA-delta_t):
 * 16-byte key, 12-byte nonce, 8-byte AAD = DID(4)||gossip(1)||FC24(3 BE),
 * 14-byte plaintext, 14-byte ciphertext, 8-byte tag. KAT1/KAT2 carry a
 * non-zero gossip byte so the AAD layout is exercised end-to-end.
 * Regenerated 2026-07-03 via OpenSSL oracle (recipe: scratchpad
 * gen_kat_rev21.rb one-off — same EVP aes-128-ccm primitive as
 * Cryptography::LoraCcm; documented in docs/03_05 wire-budget ledger).
 * Consistency proof of the oracle: the first 12 CT bytes of every vector
 * equal the rev2 CT (same CTR keystream under an unchanged nonce); tags
 * differ because they cover the longer plaintext.
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
 * zero key + DID 0x01020304 + gossip 0x00 + FC 5 + plaintext 01..0e
 *   → ciphertext 08ceca97bbf4fdc5aa2a365edde4 , tag d9f62e0b417a5d98
 * (Перші 12 байт CT збігаються з rev2-вектором — той самий CTR-keystream
 *  при незмінному нонсі; tag інший, бо покриває довший PT.)
 */
static const uint8_t  G_ZERO_KEY[16] = { 0 };
static const uint32_t G_DID = 0x01020304;
static const uint32_t G_FC  = 5;
static const uint8_t  G_GOSSIP = 0x00;
static const uint8_t  G_PT[14]  = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e };
static const uint8_t  G_CT[14]  = { 0x08, 0xce, 0xca, 0x97, 0xbb, 0xf4, 0xfd, 0xc5, 0xaa, 0x2a, 0x36, 0x5e, 0xdd, 0xe4 };
static const uint8_t  G_TAG[8] = { 0xd9, 0xf6, 0x2e, 0x0b, 0x41, 0x7a, 0x5d, 0x98 };

/* ── Extra KAT vectors (raw nonce/AAD, OpenSSL-oracle-derived) ──────────── */
typedef struct {
    const char *name;
    uint8_t key[16];
    uint8_t nonce[12];   /* DID(4) || FC(4 BE, top 0x00) || 0x00 x4 */
    uint8_t aad[8];      /* DID(4) || gossip(1) || FC(3 BE) */
    uint8_t pt[14];
    uint8_t ct[14];
    uint8_t tag[8];
} CcmKatVector;

static const CcmKatVector CCM_KAT_EXTRA[] = {
    {
        .name  = "KAT1 key=0xAA*16 DID=DEADBEEF FC=1 gossip=0x5A",
        .key   = { 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa },
        .nonce = { 0xde, 0xad, 0xbe, 0xef, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 },
        .aad   = { 0xde, 0xad, 0xbe, 0xef, 0x5a, 0x00, 0x00, 0x01 },
        .pt    = { 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0xa0, 0xb0, 0xc0, 0xd0, 0xe0 },
        .ct    = { 0xf6, 0x33, 0x04, 0x41, 0x60, 0x8a, 0x7e, 0xc2, 0xcc, 0x4b, 0x07, 0x67, 0x0d, 0x71 },
        .tag   = { 0xd0, 0x8e, 0xc4, 0xfe, 0xcd, 0x2e, 0x01, 0x90 },
    },
    {
        .name  = "KAT2 key=00..0f DID=SNET FC=65535 gossip=0xFF",
        .key   = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f },
        .nonce = { 0x53, 0x4e, 0x45, 0x54, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00 },
        .aad   = { 0x53, 0x4e, 0x45, 0x54, 0xff, 0x00, 0xff, 0xff },
        .pt    = { 0xff, 0x00, 0xff, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa },
        .ct    = { 0x6c, 0xf4, 0xc7, 0xad, 0xfc, 0x28, 0x26, 0x59, 0x4e, 0xfc, 0x50, 0xec, 0xb7, 0xb4 },
        .tag   = { 0x43, 0x31, 0x77, 0xf2, 0x64, 0x79, 0x72, 0x29 },
    },
};
#define CCM_KAT_EXTRA_COUNT (sizeof(CCM_KAT_EXTRA) / sizeof(CCM_KAT_EXTRA[0]))

#endif /* CCM_KAT_VECTORS_H */
