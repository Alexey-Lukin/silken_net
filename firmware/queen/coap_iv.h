#ifndef SILKEN_QUEEN_COAP_IV_H
#define SILKEN_QUEEN_COAP_IV_H

#include <stdint.h>
#include <string.h>
#include "../common/silken_sha256.h"  /* [FW.30] shared pure-C HMAC-SHA256 */

/*
 * coap_fallback_iv — derive the 16-byte AES-256-CBC IV for the Queen->Rails
 * CoAP batch when the hardware HRNG fails (HAL_RNG error). The normal path uses
 * HRNG (CSPRNG); this fallback is a KEY-DERIVED PRF — not a raw CSPRNG, but
 * UNPREDICTABLE: an attacker who does not hold the CoAP key cannot guess the IV.
 *
 *   IV = HMAC-SHA256(coap_key, "SilkenNet-CoAP-IV-v1"
 *                              || uid_hash || unix_ts || flush_seq || tick)[0:16]
 *
 *   coap_key  -> secret key that makes the PRF unpredictable (same key family as
 *                the CBC encryption, domain-separated by the label string).
 *   uid_hash  -> per-DEVICE (djb2 of queen_uid / STM32 HW UID).
 *   unix_ts   -> cross-REBOOT (server-synced wall-clock).
 *   flush_seq -> cross-FLUSH (monotonic per boot).
 *   tick      -> sub-second variation.
 *
 * [SEC.12] Supersedes the earlier XOR-mix fallback (`coap_fallback_iv_word`),
 * which preserved IV UNIQUENESS but not UNPREDICTABILITY. Because silken_sha256.h
 * (FW.30) already ships a host/MCU-shared HMAC-SHA256, the stricter CBC property
 * (unpredictability) is now met in PURE SOFTWARE — no AES-engine E_key(ctr) step,
 * no SEC.8 ECB-restore dance, no bench gate. The 4 integers are serialized
 * BIG-ENDIAN for deterministic host/OpenSSL parity. Pure function -> host-tested
 * vs OpenSSL in firmware/test/test_encryption.c. Canon: 03_05 §HRNG Fallback.
 */
static inline void coap_fallback_iv(uint8_t out_iv[16],
                                    const uint8_t *iv_key, size_t key_len,
                                    uint32_t tick, uint32_t uid_hash,
                                    uint32_t unix_ts, uint32_t flush_seq)
{
    /* Label = domain separation from any other use of the CoAP key. */
    static const uint8_t label[] = "SilkenNet-CoAP-IV-v1";
    uint8_t ctx[16];
    uint8_t digest[SILKEN_SHA256_DIGEST_LEN];

    ctx[0]  = (uint8_t)(uid_hash  >> 24); ctx[1]  = (uint8_t)(uid_hash  >> 16);
    ctx[2]  = (uint8_t)(uid_hash  >> 8);  ctx[3]  = (uint8_t)(uid_hash);
    ctx[4]  = (uint8_t)(unix_ts   >> 24); ctx[5]  = (uint8_t)(unix_ts   >> 16);
    ctx[6]  = (uint8_t)(unix_ts   >> 8);  ctx[7]  = (uint8_t)(unix_ts);
    ctx[8]  = (uint8_t)(flush_seq >> 24); ctx[9]  = (uint8_t)(flush_seq >> 16);
    ctx[10] = (uint8_t)(flush_seq >> 8);  ctx[11] = (uint8_t)(flush_seq);
    ctx[12] = (uint8_t)(tick      >> 24); ctx[13] = (uint8_t)(tick      >> 16);
    ctx[14] = (uint8_t)(tick      >> 8);  ctx[15] = (uint8_t)(tick);

    /* Concat variant streams label || ctx without a combined buffer; it is
       byte-identical to a one-shot HMAC over label||ctx (proven in
       test_seed_derivation.c), which is itself OpenSSL-parity-proven. */
    Silken_Hmac_Sha256_Concat(iv_key, key_len,
                              label, sizeof(label) - 1u,  /* exclude trailing NUL */
                              ctx, sizeof(ctx),
                              digest);
    memcpy(out_iv, digest, 16u);
}

#endif /* SILKEN_QUEEN_COAP_IV_H */
