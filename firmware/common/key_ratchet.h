/*
 * key_ratchet.h — [FW.17] Hash-Ratchet ротація LoRa-ключа (freeze-contract).
 *
 * Ключ НІКОЛИ не летить ефіром: команда 0x9E каже лише «доженіть версію N»,
 * обидва кінці (Soldier і Rails) синхронно проганяють ratchet. Один крок:
 *
 *   K_{v+1} = HMAC-SHA256(key = K_v,
 *                         msg = 0x01 ‖ "silken-lora-ratchet-v1" ‖ 0x00
 *                               ‖ DID_be4 ‖ 0x0080)[0..15]
 *
 * — KDF in Counter Mode за NIST SP 800-108 (i=1, Label, Context=DID,
 * L=128): регуляторно-чистий примітив (та сама вимога SP 800-57, що
 * мотивує FW.17), на вже-відвантаженому pure-C SHA256 (FW.30 — HW-SHA на
 * WLE5 нема; AES-self-encrypt зі старого ескізу 03_05 відкинуто). DID у
 * Context розводить ланцюги пристроїв зі спільним постачанням.
 *
 * Властивості (чесно): ratchet дає BACKWARD secrecy — витік K_v не
 * відкриває K_{v-1} і записаний раніше трафік (головна цінність для
 * GDPR/ISO 27001/NIST SP 800-57). Витік K_v БУДЬ-ЯКОГО кінця відкриває
 * майбутні ключі (вони похідні) — лікується re-provisioning або ECDH-alt
 * (03_05). Фізичний витяг K0 з пристрою = поза моделлю (RDP2 / SE050-L2).
 *
 * Persist: у Flash-KV їде ЛИШЕ версія (ключ 0x13, 03_01 §2.3.1) — журнал
 * append-only, і старі записи не сміють розкривати ключі. Boot:
 * K_current = ratchet^version(K0 з Protected Flash).
 *
 * Дзеркало бекенда: Cryptography::KeyRatchet (golden-KAT parity —
 * test_key_ratchet.c ↔ spec/lib/cryptography/key_ratchet_spec.rb).
 * Активація — ПІСЛЯ FW.2 CCM (ECB-downlink без MAC не сміє командувати
 * ротацією) + mount Flash-KV: 00_07 FW.17. Канон: 03_05 §3.8.
 */
#ifndef SILKEN_KEY_RATCHET_H
#define SILKEN_KEY_RATCHET_H

#include <stdint.h>
#include <string.h>

#include "silken_crc.h"
#include "silken_sha256.h"

#define KEY_RATCHET_KEY_LEN   16u
#define KEY_RATCHET_LABEL     "silken-lora-ratchet-v1"
/* Стеля стрибка версій за одну команду: обмежує CPU (1 крок = 1 HMAC) і
 * робить runaway-таргет із зіпсутого кадру нешкідливим. */
#define KEY_RATCHET_MAX_JUMP  8u

/* CMD_ROTATE_KEY (0x9E, опкод-карта 03_01 §4.5а), той самий каркас, що
 * 0x9A: [маркер:1][len_le:2 = 4][target_version_le:2][crc16_le:2] = 7 Б. */
#define CMD_ROTATE_KEY_MARKER       0x9Eu
#define CMD_ROTATE_KEY_BODY_SIZE    2u
#define CMD_ROTATE_KEY_PAYLOAD_LEN  4u /* body + crc16 */
#define CMD_ROTATE_KEY_FRAME_SIZE   7u

/* Один крок ratchet'а in-place. */
static inline void Key_Ratchet_Next(uint8_t key[KEY_RATCHET_KEY_LEN], uint32_t did)
{
    /* SP 800-108 CTR: [i=0x01][Label]["\0"][Context=DID_be][L=0x0080] */
    uint8_t msg[1 + sizeof(KEY_RATCHET_LABEL) - 1 + 1 + 4 + 2];
    uint8_t digest[32];
    size_t  off = 0;

    msg[off++] = 0x01;
    memcpy(msg + off, KEY_RATCHET_LABEL, sizeof(KEY_RATCHET_LABEL) - 1);
    off += sizeof(KEY_RATCHET_LABEL) - 1;
    msg[off++] = 0x00;
    msg[off++] = (uint8_t)(did >> 24);
    msg[off++] = (uint8_t)(did >> 16);
    msg[off++] = (uint8_t)(did >> 8);
    msg[off++] = (uint8_t)(did & 0xFFu);
    msg[off++] = 0x00; /* L = 128 біт, big-endian */
    msg[off++] = 0x80;

    Silken_Hmac_Sha256(key, KEY_RATCHET_KEY_LEN, msg, off, digest);
    memcpy(key, digest, KEY_RATCHET_KEY_LEN);
}

/* Скільки кроків легітимно зробити до target_version. 0 = відмова:
 * не вперед (replay/rollback) або стрибок понад стелю (зіпсутий кадр). */
static inline uint16_t Key_Ratchet_Steps(uint16_t current_version, uint16_t target_version)
{
    if (target_version <= current_version)                          return 0;
    if ((uint16_t)(target_version - current_version) > KEY_RATCHET_MAX_JUMP) return 0;
    return (uint16_t)(target_version - current_version);
}

/* Просунути ключ і версію до target. 1 = просунуто, 0 = кадр відкинуто
 * (версія і ключ незмінні). */
static inline int Key_Ratchet_Advance(uint8_t key[KEY_RATCHET_KEY_LEN],
                                      uint16_t *version, uint16_t target_version,
                                      uint32_t did)
{
    uint16_t steps = Key_Ratchet_Steps(*version, target_version);
    if (steps == 0u) return 0;
    for (uint16_t i = 0; i < steps; i++) Key_Ratchet_Next(key, did);
    *version = target_version;
    return 1;
}

/* Парсер кадру 0x9E — той самий патерн guard'ів, що 0x9A (FW.8).
 * 1 = валідний, *target_version заповнено. */
static inline int Key_Ratchet_Parse_Cmd(const uint8_t *frame, uint16_t frame_size,
                                        uint16_t *target_version)
{
    if (frame_size < CMD_ROTATE_KEY_FRAME_SIZE)        return 0;
    if (frame[0] != CMD_ROTATE_KEY_MARKER)             return 0;

    uint16_t payload_len = (uint16_t)frame[1] | ((uint16_t)frame[2] << 8);
    if (payload_len != CMD_ROTATE_KEY_PAYLOAD_LEN)     return 0;

    const uint8_t *body = frame + 3;
    uint16_t expected_crc = Silken_Crc16_Ccitt(body, CMD_ROTATE_KEY_BODY_SIZE);
    uint16_t received_crc = (uint16_t)body[CMD_ROTATE_KEY_BODY_SIZE]
                          | ((uint16_t)body[CMD_ROTATE_KEY_BODY_SIZE + 1] << 8);
    if (expected_crc != received_crc)                  return 0;

    *target_version = (uint16_t)body[0] | ((uint16_t)body[1] << 8);
    return 1;
}

#endif /* SILKEN_KEY_RATCHET_H */
