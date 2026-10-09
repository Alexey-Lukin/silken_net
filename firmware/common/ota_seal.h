// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ota_seal.h — [FW.23, ⚖️ founder 2026-10-05/06] Ed25519-печатка OTA-контракту:
 * перевірка й вердикт фіналізації. Pure (жодного HAL, жодних глобалок) — тож і Солдат
 * (firmware/soldier/main.c), і host-тести (firmware/test/test_soldier_logic.c,
 * test_ota_seal.c) кличуть ОДИН код, а не копію (скіл firmware #19).
 *
 * Бекенд підписує тіло контракту приватним ключем кластера (seed = HKDF(master,
 * "cluster:<id>", "silken-ota-ed25519-v1"), `OtaSealKeyService`), а Солдат тримає лише
 * ПУБЛІЧНИЙ ключ (Protected Flash 0x0803E800, magic "KPUB"). Доти печаткою був
 * HMAC-SHA256 під кластерним K_ota, що лежав на КОЖНОМУ вузлі кластера: один витягнутий
 * вузол підписував контракт для всіх. Ed25519, а не ECDSA, бо печатка мусить бути
 * ДЕТЕРМІНОВАНОЮ — пакет кампанії переготовлюють, і випадковий nonce зшив би трейлер
 * із сегментів двох підписів.
 *
 * Підписане повідомлення: тіло (без CRC32-хвоста) ‖ version_id BE(4) ‖ total_chunks BE(2) —
 * ті самі байти, що HMAC-вхід доти. Дзеркало — `OtaPackagerService.seal_message` (Ruby).
 */
#ifndef SILKEN_OTA_SEAL_H
#define SILKEN_OTA_SEAL_H

#include <stddef.h>
#include <stdint.h>
#include "ota_seal_wire.h"
#include "monocypher.h"
#include "monocypher-ed25519.h"

#define OTA_SEAL_PUBKEY_BYTES  32u
#define OTA_SEAL_PUBKEY_WORDS  8u            /* слова KPUB-блоку у Flash */
#define OTA_SEAL_SUFFIX_BYTES  6u           /* version_id BE(4) ‖ total_chunks BE(2) */
#define OTA_SEAL_RITE_MAGIC    0x45544952u  /* "RITE" little-endian у bytecode[0..3] */

/* Публічний ключ зі слів KPUB-блоку Flash. Фабрика пише 64-hex ключ словами `-w32` по
 * 8 hex (FactoryFlashing::CommandBuilder#block_words), прошивка читає їх як uint32 і
 * розпаковує старшим байтом уперед (FW.30): наївний memcpy на LE Cortex-M4 перевернув би
 * кожне слово, і печатка не зійшлася б ніколи — тихий вічний REJECT. Пін наскрізь
 * (деривація Ruby → слова фабрики → цей розпак → перевірка Ruby-печатки) —
 * test_ota_seal.c ⟷ command_builder_spec. 1 — ключ є; 0 — усі слова нульові
 * (magic є, ключа нема: зіпсований провіжн). */
static inline int Ota_Seal_Pubkey_From_Words(const uint32_t words[OTA_SEAL_PUBKEY_WORDS],
                                             uint8_t pubkey_out[OTA_SEAL_PUBKEY_BYTES])
{
    uint32_t key_or = 0;
    for (uint32_t i = 0; i < OTA_SEAL_PUBKEY_WORDS; i++) {
        key_or |= words[i];
        pubkey_out[i * 4u + 0u] = (uint8_t)(words[i] >> 24);
        pubkey_out[i * 4u + 1u] = (uint8_t)(words[i] >> 16);
        pubkey_out[i * 4u + 2u] = (uint8_t)(words[i] >> 8);
        pubkey_out[i * 4u + 3u] = (uint8_t)words[i];
    }
    return key_or != 0u;
}

/* Печатка над (body ‖ suffix) без копії тіла в буфер — рівно кроки
 * `crypto_ed25519_check`: h = reduce(SHA-512(R ‖ A ‖ повідомлення)), потім рівняння
 * перевірки; лише повідомлення стрімиться двома шматками (пін рівності з
 * `crypto_ed25519_check` над склеєним повідомленням — test_ota_seal.c).
 * 1 — печатка справжня для цього публічного ключа; 0 — ні. */
static inline int Ota_Seal_Verify(const uint8_t pubkey[OTA_SEAL_PUBKEY_BYTES],
                                  const uint8_t sig[OTA_SEAL_SIG_BYTES],
                                  const uint8_t *body, size_t body_len,
                                  const uint8_t *suffix, size_t suffix_len)
{
    if (pubkey == NULL || sig == NULL || (body == NULL && body_len) || (suffix == NULL && suffix_len)) return 0;

    crypto_sha512_ctx ctx;
    uint8_t hash[64];
    uint8_t h_ram[32];
    crypto_sha512_init(&ctx);
    crypto_sha512_update(&ctx, sig, 32);      /* R */
    crypto_sha512_update(&ctx, pubkey, OTA_SEAL_PUBKEY_BYTES);
    crypto_sha512_update(&ctx, body, body_len);
    crypto_sha512_update(&ctx, suffix, suffix_len);
    crypto_sha512_final(&ctx, hash);
    crypto_eddsa_reduce(h_ram, hash);
    return crypto_eddsa_check_equation(sig, pubkey, h_ram) == 0;
}

/* [FW.23] Вердикт фіналізації OTA. Тіло (0x99) і печатка (0x9B) приходять РІЗНИМИ
 * кадрами, і останнім може завершитись будь-що (блок печатки без збирання тіла Солдат
 * відкидає — Ota_Seal_Block_Belongs, ota_seal_wire.h); обидві гілки кличуть цей вердикт, і APPLY настає лише коли
 * зібрано і тіло, і всі 7 трейлер-блоків.
 *   WAIT   — ще не все (тіло АБО печатка/версія) → викликач НІЧОГО не чіпає
 *   APPLY  — CRC32, magic "RITE" і печатка розчинились → викликач пише у Flash
 *   REJECT — зібрано повністю, але CRC / magic / ключ / печатка впали → жертовний wipe
 * Свіжість версії (SEC.20, `Ota_Version_Is_Fresh`) — окрема брама над APPLY у викликача. */
typedef enum {
    OTA_FINALIZE_WAIT = 0,
    OTA_FINALIZE_APPLY,
    OTA_FINALIZE_REJECT
} OtaFinalizeVerdict;

static inline OtaFinalizeVerdict Ota_Seal_Try_Finalize(const uint8_t *buf,
                                                       uint16_t bytes_received,
                                                       uint16_t chunks_received,
                                                       uint16_t total_chunks,
                                                       uint8_t  segments_received,
                                                       const uint8_t *pubkey,
                                                       uint8_t  pubkey_valid,
                                                       uint32_t version_id,
                                                       const uint8_t sig[OTA_SEAL_SIG_BYTES],
                                                       uint16_t *data_len_out)
{
    if (buf == NULL || sig == NULL || data_len_out == NULL) return OTA_FINALIZE_REJECT;

    /* Ще не зібрано тіло або не прийшли всі трейлер-блоки — чекаємо мовчки. */
    if (total_chunks == 0 || chunks_received < total_chunks)  return OTA_FINALIZE_WAIT;
    if (segments_received != OTA_SEAL_ALL_RECEIVED)           return OTA_FINALIZE_WAIT;

    /* Зібрано все, але тіло коротше за CRC-хвіст — це не прошивка. */
    if (bytes_received <= 4u)                                 return OTA_FINALIZE_REJECT;

    uint16_t data_len = (uint16_t)(bytes_received - 4u);
    *data_len_out = data_len;

    /* CRC32 (ISO 3309) над тілом; останні 4 байти потоку — очікувана сума (BE). */
    uint32_t expected_crc = ((uint32_t)buf[data_len] << 24) | ((uint32_t)buf[data_len + 1] << 16) |
                            ((uint32_t)buf[data_len + 2] << 8) | (uint32_t)buf[data_len + 3];
    uint32_t crc = 0xFFFFFFFFu;
    for (uint16_t i = 0; i < data_len; i++) {
        crc ^= buf[i];
        for (uint8_t bit = 0; bit < 8u; bit++) crc = (crc & 1u) ? ((crc >> 1) ^ 0xEDB88320u) : (crc >> 1);
    }
    crc = ~crc;
    if (crc != expected_crc)                                  return OTA_FINALIZE_REJECT;

    /* Без публічного ключа походження не довести — fail-safe (краще не оновитись). */
    if (!pubkey_valid || pubkey == NULL)                      return OTA_FINALIZE_REJECT;

    /* Брама 1 (~1 µs): magic "RITE" — швидко відсікає шум ефіру. */
    if (data_len < 4u)                                        return OTA_FINALIZE_REJECT;
    uint32_t magic = (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) | ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
    if (magic != OTA_SEAL_RITE_MAGIC)                         return OTA_FINALIZE_REJECT;

    /* Брама 2: Ed25519-печатка над тіло ‖ version_be ‖ total_be. */
    const uint8_t suffix[OTA_SEAL_SUFFIX_BYTES] = {
        (uint8_t)(version_id >> 24), (uint8_t)(version_id >> 16), (uint8_t)(version_id >> 8), (uint8_t)version_id,
        (uint8_t)(total_chunks >> 8), (uint8_t)total_chunks
    };
    if (!Ota_Seal_Verify(pubkey, sig, buf, data_len, suffix, sizeof(suffix))) return OTA_FINALIZE_REJECT;
    return OTA_FINALIZE_APPLY;
}

#endif /* SILKEN_OTA_SEAL_H */
