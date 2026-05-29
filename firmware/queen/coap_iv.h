#ifndef SILKEN_QUEEN_COAP_IV_H
#define SILKEN_QUEEN_COAP_IV_H

#include <stdint.h>

#ifndef RNG_FALLBACK_XOR_MASK
#define RNG_FALLBACK_XOR_MASK 0xA5A5A5A5UL
#endif

/*
 * coap_fallback_iv_word — one 32-bit word of the AES-256-CBC IV for the
 * Queen->Rails CoAP batch, used ONLY when the hardware HRNG fails
 * (HAL_RNG error). The normal path uses HRNG (cryptographically random);
 * this fallback is a UNIQUENESS-preserving degradation, NOT a CSPRNG.
 *
 *   uid_hash  -> per-DEVICE uniqueness (djb2 of queen_uid / STM32 HW UID); a
 *                mass blackout-reboot still yields distinct IVs per Queen.
 *   unix_ts   -> cross-REBOOT uniqueness (server-synced wall-clock; advances
 *                every sync and differs across reboots once re-synced).
 *   flush_seq -> cross-FLUSH uniqueness within a boot session (monotonic).
 *   tick + i  -> sub-second variation; the 4 IV words differ from each other.
 *
 * Threat model (03_05 BLOCKER-4): the CoAP batch plaintext is the Queen's own
 * telemetry — an attacker cannot inject chosen plaintext, so there is no
 * BEAST/chosen-plaintext vector. CBC's operative requirement here is IV
 * UNIQUENESS (no reuse -> no equal-prefix leakage), which this guarantees.
 * IV UNPREDICTABILITY (the stricter CBC property) is NOT met by this fallback;
 * the proper fix is a key-derived IV E_key(counter) and is bench-gated
 * (03_05 §2.9-style roadmap). Pure function -> host-tested in test_encryption.c.
 */
static inline uint32_t coap_fallback_iv_word(uint8_t i,
                                             uint32_t tick,
                                             uint32_t uid_hash,
                                             uint32_t unix_ts,
                                             uint32_t flush_seq)
{
    return (tick + (uint32_t)i)
         ^ (uid_hash << i)
         ^ (unix_ts * 65537U)            /* cross-reboot wall-clock, bit-spread */
         ^ (flush_seq * 2654435761U)     /* cross-flush monotonic (Knuth mult.) */
         ^ ((uint32_t)i * RNG_FALLBACK_XOR_MASK);
}

#endif /* SILKEN_QUEEN_COAP_IV_H */
