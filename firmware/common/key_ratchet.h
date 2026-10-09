// SPDX-License-Identifier: AGPL-3.0-or-later
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
 * майбутні ключі (вони похідні) — лікує re-provision у нову ЕПОХУ (корінь
 * K0_e не виводиться зі злитого K_v, 03_05 §3.8; L2-плата його не приймає —
 * лише заміна); ECDH-alt задумано, його ще немає. Проти витоку самого master
 * епоха безсила. Фізичний витяг K0
 * з пристрою = поза моделлю (RDP2 / SE050-L2).
 *
 * Persist: у Flash-KV їде ЛИШЕ версія (ключ 0x13, 03_01 §2.3.1) — журнал
 * append-only, і старі записи не сміють розкривати ключі. Boot:
 * K_current = ratchet^version(K0 з Protected Flash). Порядок — версія ПЕРШ
 * за ключ (Key_Ratchet_Commit).
 *
 * Дзеркало бекенда: Cryptography::KeyRatchet (golden-KAT parity —
 * test_key_ratchet.c ↔ spec/services/cryptography/key_ratchet_spec.rb).
 * Активація — ПІСЛЯ FW.2 CCM (в ECB-ері LoRa-шар знімає Королева, Rails
 * ключа вузла не бачить, тож grace ротації не закрилось би ніколи) + mount
 * Flash-KV: 00_07 FW.17. Канон: 03_05 §3.8.
 */
#ifndef SILKEN_KEY_RATCHET_H
#define SILKEN_KEY_RATCHET_H

#include <stdint.h>
#include <string.h>

#include "silken_sha256.h"

#define KEY_RATCHET_KEY_LEN   16u
#define KEY_RATCHET_LABEL     "silken-lora-ratchet-v1"
/* Стеля стрибка версій за одну команду: обмежує CPU (1 крок = 1 HMAC) і
 * робить runaway-таргет із зіпсутого кадру нешкідливим. */
#define KEY_RATCHET_MAX_JUMP  8u

/* Команда CMD_ROTATE_KEY (0x9E) — адресний CCM-кадр сесійним ключем вузла
 * (03_05 §2.5): тіло [target_version:u16le] розпаковує
 * Dl_Cmd_Rotate_Target (downlink_ccm.h), ціль судить Key_Ratchet_Steps. */

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

/* Запис версії у постійне сховище (Солдат: Flash-KV 0x13). 1 = записано. */
typedef int (*KeyRatchetPersistFn)(void *ctx, uint16_t version);

/* Ротація ПРИСТРОЮ — лише через цей коміт: версія лягає у сховище ПЕРШ ніж
 * зміниться ключ. Тоді перший кадр новим ключем доводить, що й boot відтворить
 * новий, і бекенд має право закрити Dual-Key Grace на першому ж MIC-успіху
 * (TelemetryUnpackerService#decrypt_ccm_with_grace). ⛔ Не повертати порядок
 * «ключ у RAM, запис потім»: провалений запис лишав вузол на новому ключі до
 * першого power-cut'а, після якого boot повертав старий, уже забутий бекендом, —
 * глухий вузол, і лікує його лише SWD-візит. 1 = закомічено; 0 = кадр
 * відкинуто або запис не вдався, ключ і версія незмінні. */
static inline int Key_Ratchet_Commit(uint8_t key[KEY_RATCHET_KEY_LEN],
                                     uint16_t *version, uint16_t target_version,
                                     uint32_t did, KeyRatchetPersistFn persist,
                                     void *ctx)
{
    if (Key_Ratchet_Steps(*version, target_version) == 0u) return 0;
    if (!persist(ctx, target_version)) return 0;
    return Key_Ratchet_Advance(key, version, target_version, did);
}

/* Boot-модель: K_current = ratchet^version(K0). БЕЗ стелі MAX_JUMP — це не
 * ефірна команда, а відтворення власного персистнутого стану (Flash-KV 0x13
 * тримає лише версію; v HMAC-кроків — мікросекунди навіть на сотнях). */
static inline void Key_Ratchet_Apply(uint8_t key[KEY_RATCHET_KEY_LEN],
                                     uint16_t version, uint32_t did)
{
    for (uint16_t i = 0; i < version; i++) Key_Ratchet_Next(key, did);
}

/* Міст до CRYP-подання ключа: aes_key[4] на MCU живе словами у тій самій
 * BE-конвенції, що factory `-w32` (перший байт ключа = старший байт слова;
 * дзеркало Load_AES_Key ↔ CommandBuilder.write_block). Ratchet працює
 * байтами — конверсія обабіч re-key. */
static inline void Key_Ratchet_Words_To_Bytes(const uint32_t words[4],
                                              uint8_t key[KEY_RATCHET_KEY_LEN])
{
    for (unsigned i = 0; i < 4u; i++) {
        key[i * 4 + 0] = (uint8_t)(words[i] >> 24);
        key[i * 4 + 1] = (uint8_t)(words[i] >> 16);
        key[i * 4 + 2] = (uint8_t)(words[i] >> 8);
        key[i * 4 + 3] = (uint8_t)(words[i] & 0xFFu);
    }
}

static inline void Key_Ratchet_Bytes_To_Words(const uint8_t key[KEY_RATCHET_KEY_LEN],
                                              uint32_t words[4])
{
    for (unsigned i = 0; i < 4u; i++) {
        words[i] = ((uint32_t)key[i * 4 + 0] << 24) |
                   ((uint32_t)key[i * 4 + 1] << 16) |
                   ((uint32_t)key[i * 4 + 2] << 8)  |
                   (uint32_t)key[i * 4 + 3];
    }
}

#endif /* SILKEN_KEY_RATCHET_H */
