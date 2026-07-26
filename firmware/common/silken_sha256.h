// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * silken_sha256.h — Pure-C SHA-256 (FIPS 180-4) + HMAC-SHA256 (RFC 2104).
 *
 * [SEC.11 / FW.30] Закриває TODO(FW.30-mbedtls): деривація
 * cold-start стану Лоренца більше не чекає на mbedTLS-лінк — той самий
 * header-only код працює і на STM32WLE5JC (Cortex-M4), і в host-тестах.
 * Контракт = SilkenNet::SeedDerivation (OpenSSL): байт-у-байт ідентичний
 * digest для тих самих входів. Parity доведено у
 * firmware/test/test_seed_derivation.c (KAT FIPS/RFC 4231 + крос-перевірка
 * проти OpenSSL на живих векторах).
 *
 * Без HAL-залежностей, без алокацій, без таблиць у RAM (K-константи у
 * .rodata/Flash). ~50 байт стеку на контекст + блок.
 *
 * Споживачі:
 *   - firmware/common/lorenz_seed.h  (HMAC для initial_state)
 *   - firmware/soldier/main.c        (через lorenz_seed.h)
 *   - firmware/test/test_seed_derivation.c (parity vs OpenSSL)
 */

#ifndef SILKEN_SHA256_H
#define SILKEN_SHA256_H

#include <stdint.h>
#include <string.h>

#define SILKEN_SHA256_DIGEST_LEN 32u
#define SILKEN_SHA256_BLOCK_LEN  64u

typedef struct {
    uint32_t state[8];
    uint64_t bit_len;
    uint8_t  buffer[SILKEN_SHA256_BLOCK_LEN];
    uint32_t buffer_len;
} SilkenSha256Ctx;

/* FIPS 180-4 §4.2.2 — перші 32 біти дробових частин кубічних коренів
 * перших 64 простих чисел. Вічні константи, не дрейфують. */
static const uint32_t silken_sha256_k[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

static inline uint32_t silken_sha256_rotr(uint32_t x, uint32_t n)
{
    return (x >> n) | (x << (32u - n));
}

static void Silken_Sha256_Init(SilkenSha256Ctx *ctx)
{
    /* FIPS 180-4 §5.3.3 — перші 32 біти дробових частин квадратних коренів
     * перших 8 простих чисел. */
    ctx->state[0] = 0x6a09e667u;
    ctx->state[1] = 0xbb67ae85u;
    ctx->state[2] = 0x3c6ef372u;
    ctx->state[3] = 0xa54ff53au;
    ctx->state[4] = 0x510e527fu;
    ctx->state[5] = 0x9b05688cu;
    ctx->state[6] = 0x1f83d9abu;
    ctx->state[7] = 0x5be0cd19u;
    ctx->bit_len    = 0u;
    ctx->buffer_len = 0u;
}

/* Компресія одного 64-байтного блоку (FIPS 180-4 §6.2.2). */
static void Silken_Sha256_Compress(SilkenSha256Ctx *ctx, const uint8_t block[SILKEN_SHA256_BLOCK_LEN])
{
    uint32_t w[64];
    uint32_t a, b, c, d, e, f, g, h;

    for (uint32_t i = 0; i < 16u; i++) {
        w[i] = ((uint32_t)block[i * 4u] << 24) |
               ((uint32_t)block[i * 4u + 1u] << 16) |
               ((uint32_t)block[i * 4u + 2u] << 8) |
               ((uint32_t)block[i * 4u + 3u]);
    }
    for (uint32_t i = 16u; i < 64u; i++) {
        uint32_t s0 = silken_sha256_rotr(w[i - 15u], 7u) ^
                      silken_sha256_rotr(w[i - 15u], 18u) ^ (w[i - 15u] >> 3u);
        uint32_t s1 = silken_sha256_rotr(w[i - 2u], 17u) ^
                      silken_sha256_rotr(w[i - 2u], 19u) ^ (w[i - 2u] >> 10u);
        w[i] = w[i - 16u] + s0 + w[i - 7u] + s1;
    }

    a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
    e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];

    for (uint32_t i = 0; i < 64u; i++) {
        uint32_t s1  = silken_sha256_rotr(e, 6u) ^ silken_sha256_rotr(e, 11u) ^
                       silken_sha256_rotr(e, 25u);
        uint32_t ch  = (e & f) ^ ((~e) & g);
        uint32_t t1  = h + s1 + ch + silken_sha256_k[i] + w[i];
        uint32_t s0  = silken_sha256_rotr(a, 2u) ^ silken_sha256_rotr(a, 13u) ^
                       silken_sha256_rotr(a, 22u);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2  = s0 + maj;

        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }

    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void Silken_Sha256_Update(SilkenSha256Ctx *ctx, const uint8_t *data, size_t len)
{
    ctx->bit_len += (uint64_t)len * 8u;
    while (len > 0u) {
        uint32_t space = SILKEN_SHA256_BLOCK_LEN - ctx->buffer_len;
        uint32_t take  = (len < (size_t)space) ? (uint32_t)len : space;
        memcpy(&ctx->buffer[ctx->buffer_len], data, take);
        ctx->buffer_len += take;
        data += take;
        len  -= take;
        if (ctx->buffer_len == SILKEN_SHA256_BLOCK_LEN) {
            Silken_Sha256_Compress(ctx, ctx->buffer);
            ctx->buffer_len = 0u;
        }
    }
}

static void Silken_Sha256_Final(SilkenSha256Ctx *ctx, uint8_t digest[SILKEN_SHA256_DIGEST_LEN])
{
    uint64_t bit_len = ctx->bit_len;

    /* Padding: 0x80, нулі до 56 mod 64, потім довжина BE64 (FIPS §5.1.1). */
    uint8_t pad_byte = 0x80u;
    Silken_Sha256_Update(ctx, &pad_byte, 1u);
    ctx->bit_len -= 8u; /* Padding не входить у довжину повідомлення */

    uint8_t zero = 0x00u;
    while (ctx->buffer_len != 56u) {
        Silken_Sha256_Update(ctx, &zero, 1u);
        ctx->bit_len -= 8u;
    }

    uint8_t len_be[8];
    for (uint32_t i = 0; i < 8u; i++) {
        len_be[i] = (uint8_t)(bit_len >> (56u - i * 8u));
    }
    Silken_Sha256_Update(ctx, len_be, 8u);

    for (uint32_t i = 0; i < 8u; i++) {
        digest[i * 4u]      = (uint8_t)(ctx->state[i] >> 24);
        digest[i * 4u + 1u] = (uint8_t)(ctx->state[i] >> 16);
        digest[i * 4u + 2u] = (uint8_t)(ctx->state[i] >> 8);
        digest[i * 4u + 3u] = (uint8_t)(ctx->state[i]);
    }
}

/* One-shot SHA-256. */
static void Silken_Sha256(const uint8_t *data, size_t len,
                          uint8_t digest[SILKEN_SHA256_DIGEST_LEN])
{
    SilkenSha256Ctx ctx;
    Silken_Sha256_Init(&ctx);
    Silken_Sha256_Update(&ctx, data, len);
    Silken_Sha256_Final(&ctx, digest);
}

/* HMAC-SHA256 (RFC 2104): H((K' ^ opad) || H((K' ^ ipad) || msg)).
 * K_seed = 32 байти < block, але довгі ключі теж обробляються коректно
 * (хешуються до 32) — повна відповідність OpenSSL::HMAC. */
static void Silken_Hmac_Sha256(const uint8_t *key, size_t key_len,
                               const uint8_t *msg, size_t msg_len,
                               uint8_t digest[SILKEN_SHA256_DIGEST_LEN])
{
    uint8_t key_block[SILKEN_SHA256_BLOCK_LEN];
    uint8_t pad[SILKEN_SHA256_BLOCK_LEN];
    uint8_t inner[SILKEN_SHA256_DIGEST_LEN];
    SilkenSha256Ctx ctx;

    memset(key_block, 0, sizeof(key_block));
    if (key_len > SILKEN_SHA256_BLOCK_LEN) {
        Silken_Sha256(key, key_len, key_block); /* K' = H(K) для довгих ключів */
    } else {
        memcpy(key_block, key, key_len);
    }

    for (uint32_t i = 0; i < SILKEN_SHA256_BLOCK_LEN; i++) pad[i] = key_block[i] ^ 0x36u;
    Silken_Sha256_Init(&ctx);
    Silken_Sha256_Update(&ctx, pad, SILKEN_SHA256_BLOCK_LEN);
    Silken_Sha256_Update(&ctx, msg, msg_len);
    Silken_Sha256_Final(&ctx, inner);

    for (uint32_t i = 0; i < SILKEN_SHA256_BLOCK_LEN; i++) pad[i] = key_block[i] ^ 0x5cu;
    Silken_Sha256_Init(&ctx);
    Silken_Sha256_Update(&ctx, pad, SILKEN_SHA256_BLOCK_LEN);
    Silken_Sha256_Update(&ctx, inner, SILKEN_SHA256_DIGEST_LEN);
    Silken_Sha256_Final(&ctx, digest);
}

/* HMAC-SHA256 над конкатенацією (a ‖ b) без суцільного буфера. [FW.23]
 * OTA dual-gate хешує bytecode ‖ (version_be ‖ total_be): тіло прошивки само
 * заповнює ota_buffer (~1 КБ), тож 6-байтний хвіст стрімимо окремо замість
 * +1 КБ на стек. Тотожно Silken_Hmac_Sha256 над злитим a‖b (доведено host-
 * тестом), а той — байт-у-байт OpenSSL::HMAC (test_seed_derivation). b_len==0
 * дозволено (тоді це HMAC лише над a). */
static inline void Silken_Hmac_Sha256_Concat(const uint8_t *key, size_t key_len,
                                       const uint8_t *a, size_t a_len,
                                       const uint8_t *b, size_t b_len,
                                       uint8_t digest[SILKEN_SHA256_DIGEST_LEN])
{
    uint8_t key_block[SILKEN_SHA256_BLOCK_LEN];
    uint8_t pad[SILKEN_SHA256_BLOCK_LEN];
    uint8_t inner[SILKEN_SHA256_DIGEST_LEN];
    SilkenSha256Ctx ctx;

    memset(key_block, 0, sizeof(key_block));
    if (key_len > SILKEN_SHA256_BLOCK_LEN) {
        Silken_Sha256(key, key_len, key_block);
    } else {
        memcpy(key_block, key, key_len);
    }

    for (uint32_t i = 0; i < SILKEN_SHA256_BLOCK_LEN; i++) pad[i] = key_block[i] ^ 0x36u;
    Silken_Sha256_Init(&ctx);
    Silken_Sha256_Update(&ctx, pad, SILKEN_SHA256_BLOCK_LEN);
    if (a_len > 0u) Silken_Sha256_Update(&ctx, a, a_len);
    if (b_len > 0u) Silken_Sha256_Update(&ctx, b, b_len);
    Silken_Sha256_Final(&ctx, inner);

    for (uint32_t i = 0; i < SILKEN_SHA256_BLOCK_LEN; i++) pad[i] = key_block[i] ^ 0x5cu;
    Silken_Sha256_Init(&ctx);
    Silken_Sha256_Update(&ctx, pad, SILKEN_SHA256_BLOCK_LEN);
    Silken_Sha256_Update(&ctx, inner, SILKEN_SHA256_DIGEST_LEN);
    Silken_Sha256_Final(&ctx, digest);
}

#endif /* SILKEN_SHA256_H */
