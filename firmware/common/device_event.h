// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * device_event.h — [SEC.21] uplink device-event 0x57: рідкісні security-події,
 *                  що не є станом. Два шари, дві довіри:
 *
 *   Шар 1 (Soldier→Queen, LoRa): 16B ECB-кадр 0x57 на cluster-ключі — та сама
 *     транзишн-довіра, що 0x55/0x56 (Королева читає сама, control-plane).
 *   Шар 2 (Queen→Rails, CoAP): Королева ДЕКРИПТУЄ кадр (щоб упізнати), і
 *     форвардить cleartext-подію під ВЛАСНИМ Ed25519-підписом — рунг L1
 *     драбини довіри (той самий EDSK/механізм, що QATT-батч; дім 05_02
 *     Trust-origin ladder, wire 03_05 §2.2а). Rails верифікує gateway-origin
 *     проти HardwareKey.ed25519_public_key_hex — LoRa-ключа НЕ торкається.
 *
 * Навіщо L1, а не blind-forward сирого ct: Rails per-Tree LoRa-ключа не має в
 * ЖОДНІЙ ері (ECB: Королева знімає шар сама; CCM: 0x57=cluster KEYB, Rails не
 * має) → re-decrypt дав би сміття, канарка мертва fail-open. Королева вже
 * тримає plaintext — форвардимо його, не ciphertext. Per-event device-підпис
 * фізично неможливий (64B у 16B кадр, канон 05_02, §Trust-origin ladder — ⛔ не номер РЯДКА) → L1 Queen-attest =
 * правильний рівень назавжди, L2-Merkle його не торкнеться.
 *
 * Trust-клас події: L1-observational ops-алерт — НІКОЛИ не money-path (лише
 * EwsAlert; slash-виключення дзеркалять firmware_fault). Реєстр кодів
 * розширюваний: майбутня подія = +1 константа.
 *
 * One-Home: пакування тут (host-тести); L1-конверт дзеркалить DeviceEventWorker.
 * Канон: 03_01 §4.5а (opcode) + 03_02 (Queen forward) + 03_05 §2.2а (wire) + 00_07 SEC.21.
 */
#ifndef SILKEN_DEVICE_EVENT_H
#define SILKEN_DEVICE_EVENT_H

#include <stdint.h>
#include <string.h>

/* ── Шар 1: Soldier→Queen LoRa-кадр (16B = 1 AES-128-ECB блок) ──────────────
 *   [0]      0x57 EVT_MARKER      [10]     0x45 'E' magic (анти-DID-колізія)
 *   [1..4]   DID BE               [11]     TTL (=3, не panic)
 *   [5]      event_code           [12..13] event_seq BE (per-boot, діагностика)
 *   [6..9]   arg u32 BE           [14..15] vcap_mv BE
 */
#define DEVICE_EVT_MARKER        0x57u
#define DEVICE_EVT_MAGIC         0x45u /* 'E' */
#define DEVICE_EVT_MAGIC_OFFSET  10u
#define DEVICE_EVT_PACKET_SIZE   16u
#define DEVICE_EVT_TTL           3u

/* Реєстр подій. 0x01 зарезервовано: baseline-revert їде state-report'ом
 * (fw_report.h) — код існує на випадок sub-cycle latency потреби. */
#define DEVICE_EVT_BASELINE_REVERT 0x01u /* reserved — не емітиться */
#define DEVICE_EVT_CANARY_TRIP     0x02u /* __stack_chk_fail слід (DR0[10]) */

static inline void Device_Event_Build(uint8_t out[16], uint32_t did,
                                      uint8_t code, uint32_t arg,
                                      uint16_t seq, uint16_t vcap_mv)
{
    out[0]  = DEVICE_EVT_MARKER;
    out[1]  = (uint8_t)(did >> 24);
    out[2]  = (uint8_t)(did >> 16);
    out[3]  = (uint8_t)(did >> 8);
    out[4]  = (uint8_t)(did & 0xFFu);
    out[5]  = code;
    out[6]  = (uint8_t)(arg >> 24);
    out[7]  = (uint8_t)(arg >> 16);
    out[8]  = (uint8_t)(arg >> 8);
    out[9]  = (uint8_t)(arg & 0xFFu);
    out[10] = DEVICE_EVT_MAGIC;
    out[11] = DEVICE_EVT_TTL;
    out[12] = (uint8_t)(seq >> 8);
    out[13] = (uint8_t)(seq & 0xFFu);
    out[14] = (uint8_t)(vcap_mv >> 8);
    out[15] = (uint8_t)(vcap_mv & 0xFFu);
}

/* 1 = розшифрований 16B-кадр є device-event (маркер + magic). */
static inline int Device_Event_Is(const uint8_t p[16])
{
    return p[0] == DEVICE_EVT_MARKER && p[DEVICE_EVT_MAGIC_OFFSET] == DEVICE_EVT_MAGIC;
}

/* ── Шар 2: Queen→Rails підписаний L1-конверт (CoAP device/event/<uid>) ──────
 *   [ver:1=0x01][queen_unix_ts:4 BE][count:1][records:count×7][sig:64]
 *   record = [did:4 BE][code:1][soldier_seq:2 BE]
 * Підпис Ed25519 (EDSK) над:  "SLKN-QEVT1" ‖ uid_len:1 ‖ uid ‖ <body без sig>
 * Окремий доменний тег (НЕ SLKN-QATT2) — canary-підпис не сплайснути у
 * телеметрію-verify і навпаки (cross-protocol reuse guard, дзеркало QATT).
 */
#define DEVENV_VERSION_1     0x01u
#define DEVENV_HEADER_LEN    6u    /* [ver:1][queen_unix_ts:4][count:1] */
#define DEVENV_RECORD_LEN    7u    /* [did:4][code:1][soldier_seq:2]    */
#define DEVENV_SIG_LEN       64u   /* Ed25519 detached                  */
#define DEVENV_DOMAIN_TAG    "SLKN-QEVT1"
#define DEVENV_DOMAIN_TAG_LEN 10u  /* без NUL */
#define DEVENV_MAX_RECORDS   4u    /* дзеркало ring-місткості Королеви  */

/* Пише 6-байтний header у out. */
static inline void Devenv_Write_Header(uint8_t *hdr, uint32_t unix_ts,
                                       uint8_t count)
{
    hdr[0] = DEVENV_VERSION_1;
    hdr[1] = (uint8_t)(unix_ts >> 24);
    hdr[2] = (uint8_t)(unix_ts >> 16);
    hdr[3] = (uint8_t)(unix_ts >> 8);
    hdr[4] = (uint8_t)(unix_ts & 0xFFu);
    hdr[5] = count;
}

/* Пише 7-байтний cleartext-record (Королева витягла поля з декриптованого
 * 0x57-кадру: did=[1..4], code=[5], soldier_seq=[12..13]). */
static inline void Devenv_Write_Record(uint8_t *rec, uint32_t did,
                                       uint8_t code, uint16_t soldier_seq)
{
    rec[0] = (uint8_t)(did >> 24);
    rec[1] = (uint8_t)(did >> 16);
    rec[2] = (uint8_t)(did >> 8);
    rec[3] = (uint8_t)(did & 0xFFu);
    rec[4] = code;
    rec[5] = (uint8_t)(soldier_seq >> 8);
    rec[6] = (uint8_t)(soldier_seq & 0xFFu);
}

/* Довжина body (header+records) для N записів — вхід підпису (без sig). */
static inline uint16_t Devenv_Body_Len(uint8_t count)
{
    return (uint16_t)(DEVENV_HEADER_LEN + (uint16_t)count * DEVENV_RECORD_LEN);
}

#endif /* SILKEN_DEVICE_EVENT_H */
