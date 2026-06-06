/*
 * lorenz_seed.h — SEC.11 / FW.30 cold-start деривація стану Лоренца.
 *
 * [AUDIT-2026-06-06] Єдине джерело правди для firmware-сторони деривації —
 * дзеркало app/services/silken_net/seed_derivation.rb БАЙТ-У-БАЙТ:
 *
 *   info   = "init|" || epoch_day_be8                  (13 байт)
 *   digest = HMAC-SHA256(K_seed, info)
 *   x0/y0/z0 = signed_unit_float(digest[0..7], [8..15], [16..23]) ∈ [-1, +1]
 *
 * До цього файла firmware жив на Knuth-hash плейсхолдері з approx_days
 * (Y*365 + M*30 + D — без високосних) — cold-start координати НЕ збігалися
 * з backend ні алгоритмом, ні епохою; рятувала лише категоріальна
 * толерантність ARCH.41. Тепер обидві сторони рахують одне й те саме.
 *
 * epoch_day: пріоритет — UTC від Queen-маяка (FW.20); фолбек — RTC-календар
 * через days_from_civil (точна громадянська арифметика з високосними;
 * RTC-default 2000-01-01 → 10957 = ARCH.41 кандидат бекенду).
 *
 * Споживачі: soldier/main.c (Derive_Cold_Start_State) і
 * test_seed_derivation.c + test_soldier_logic.c (parity vs OpenSSL).
 */

#ifndef SILKEN_LORENZ_SEED_H
#define SILKEN_LORENZ_SEED_H

#include <stdint.h>
#include "silken_sha256.h"

#define SILKEN_LORENZ_SEED_LEN   32u
#define SILKEN_EPOCH_SECONDS     86400u

/* (2^64 - 1) / 2 — той самий IEEE-754 double, що й у Ruby/OpenSSL-тесті. */
#define SILKEN_UINT64_HALF       9223372036854775807.5

/* 8 BE-байтів → double ∈ [-1, +1]. Цілочисельне завантаження + одне
 * віднімання/ділення у double — біт-ідентично між OpenSSL (Ruby) і цим
 * кодом (convert-then-subtract в обох). */
static inline double Silken_Signed_Unit_Float(const uint8_t bytes[8])
{
    uint64_t n = ((uint64_t)bytes[0] << 56) | ((uint64_t)bytes[1] << 48) |
                 ((uint64_t)bytes[2] << 40) | ((uint64_t)bytes[3] << 32) |
                 ((uint64_t)bytes[4] << 24) | ((uint64_t)bytes[5] << 16) |
                 ((uint64_t)bytes[6] << 8)  | ((uint64_t)bytes[7]);
    return ((double)n - SILKEN_UINT64_HALF) / SILKEN_UINT64_HALF;
}

/* Дні від 1970-01-01 для громадянської дати (алгоритм Говарда Гіннанта,
 * days_from_civil) — точний, з високосними роками; валідний далеко за межі
 * RTC-діапазону STM32 (2000..2099). 2000-01-01 → 10957. */
static inline int32_t Silken_Days_From_Civil(int32_t y, uint32_t m, uint32_t d)
{
    y -= (m <= 2u) ? 1 : 0;
    int32_t  era = (y >= 0 ? y : y - 399) / 400;
    uint32_t yoe = (uint32_t)(y - era * 400);                /* [0, 399] */
    uint32_t mp  = (m + 9u) % 12u;                           /* Mar=0 .. Feb=11 */
    uint32_t doy = (153u * mp + 2u) / 5u + d - 1u;           /* [0, 365] */
    uint32_t doe = yoe * 365u + yoe / 4u - yoe / 100u + doy; /* [0, 146096] */
    return era * 146097 + (int32_t)doe - 719468;
}

/* epoch_day з UTC unix-секунд (шлях Queen-маяка). */
static inline uint32_t Silken_Epoch_Day_From_Unix(uint32_t unix_ts)
{
    return unix_ts / SILKEN_EPOCH_SECONDS;
}

/* Деривація (x₀, y₀, z₀) з K_seed + epoch_day — дзеркало
 * SilkenNet::SeedDerivation.initial_state. */
static inline void Silken_Derive_Initial_State(const uint8_t seed[SILKEN_LORENZ_SEED_LEN],
                                               uint64_t epoch_day,
                                               double *x0, double *y0, double *z0)
{
    uint8_t info[13];
    uint8_t digest[SILKEN_SHA256_DIGEST_LEN];

    info[0] = (uint8_t)'i';
    info[1] = (uint8_t)'n';
    info[2] = (uint8_t)'i';
    info[3] = (uint8_t)'t';
    info[4] = (uint8_t)'|';
    for (uint32_t i = 0; i < 8u; i++) {
        info[5u + i] = (uint8_t)(epoch_day >> (56u - i * 8u));
    }

    Silken_Hmac_Sha256(seed, SILKEN_LORENZ_SEED_LEN, info, sizeof(info), digest);

    *x0 = Silken_Signed_Unit_Float(&digest[0]);
    *y0 = Silken_Signed_Unit_Float(&digest[8]);
    *z0 = Silken_Signed_Unit_Float(&digest[16]);
}

#endif /* SILKEN_LORENZ_SEED_H */
