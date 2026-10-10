// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * downlink_ccm.h — адресні команди Rails → Солдат під AES-128-CCM сесійним
 * ключем цільового вузла (downlink-wire-ревізія, ⚖️ founder 2026-09-28;
 * канон — docs/03_05 §2.5, робочий аркуш — protocols/hardware/downlink_wire_revision.md).
 *
 * Кадр на ефірі (Королева несе його як є — ключа вона не має):
 *
 *   [opcode:1][DID:4 BE][DLFC_lsb:2 BE]   ← AAD: відкритий, під MIC
 *   [body:N]                              ← CCM-шифротекст
 *   [MIC:8]
 *
 *   0x9E ротація ключа  N=2 → 17 Б.
 *   16 Б лишається ECB-шляхом (маяк, OTA), тож довжина розводить два шляхи
 *   без жодного прапорця.
 *
 * Тіло — байт-у-байт тіло старого каркаса [маркер][len][body][crc16] без len і
 * CRC (little-endian поля, OtaPackagerService): цілісність тепер несе MIC.
 * DID і DLFC у заголовку — big-endian, як AAD і нонс аплінку (lora_ccm.h).
 *
 * Нонс = DID(4 BE) ‖ DLFC(4 BE) ‖ 0x01 ‖ 0x00×3. Байт напрямку 0x01 розводить
 * простори нонсів downlink і аплінку, бо в аплінку байти 8..11 = 0
 * (Build_CCM_Nonce) під тим самим K_v; повтор нонса під CCM = витік потоку
 * ключа й підробка MIC. B0 — той самий Build_CCM_B0_From_Nonce (прапорці
 * 0x5A: t=8, q=3), Q = N.
 *
 * DLFC — один u32 на пристрій (Rails ↔ Flash-KV Солдата), в ефірі — молодші
 * 16 біт. Реконструкція бере найменше u32, строго більше за останнє прийняте,
 * з цими молодшими бітами. Повтор старого кадру реконструюється в ІНШЕ
 * значення → інший нонс → MIC не сходиться: «лише строго більший» тримає сама
 * криптографія, порівнювати окремо нічого. Стеля: розрив понад 65535
 * невидачених-неприйнятих команд реконструюється хибно, і вузол глухне для
 * команд до re-provision (той обнуляє DLFC разом із новою епохою ключа).
 *
 * Pure (без HAL): включають Солдат, черга Королеви (довжини й DID) і host-тести.
 * Розшифрування — HAL-половина в downlink_ccm_open.h.
 */
#ifndef SILKEN_DOWNLINK_CCM_H
#define SILKEN_DOWNLINK_CCM_H

#include <stdint.h>
#include <string.h>

#include "lora_ccm.h"

/* 0x9A — RETIRED з FW.66 (смуга Лоренца FW.8, ролі Z розведено); ⛔ не перевикористовувати. */
/* 0x9D — RETIRED з HW.30 (аудіо-пороги зрізаного пʼєзо); ⛔ не перевикористовувати. */
#define DL_CCM_OP_ROTATE_KEY        0x9Eu  /* FW.17 — ротація ключа     */

#define DL_CCM_DIRECTION_BYTE       0x01u  /* нонс[8]; аплінк — 0x00 */
#define DL_CCM_AAD_LEN              7u     /* opcode + DID + DLFC_lsb */
#define DL_CCM_DID_OFFSET           1u
#define DL_CCM_DLFC_OFFSET          5u
#define DL_CCM_MIC_LEN              FW2_CCM_MIC_LEN

#define DL_CCM_BODY_ROTATE_KEY      2u     /* [target_version:u16le] */
/* Найбільше тіло ЖИВОГО опкоду: ним розмірені буфер Солдата й слот черги Королеви,
 * тож новий опкод із довшим тілом піднімає цю межу тим самим кроком. */
#define DL_CCM_BODY_MAX             DL_CCM_BODY_ROTATE_KEY
#define DL_CCM_FRAME_MAX            (DL_CCM_AAD_LEN + DL_CCM_BODY_MAX + DL_CCM_MIC_LEN) /* 17 */

/* Довжина тіла за опкодом; 0 = опкод не командний. */
static inline uint8_t Dl_Ccm_Body_Len(uint8_t opcode)
{
    switch (opcode) {
    case DL_CCM_OP_ROTATE_KEY: return (uint8_t)DL_CCM_BODY_ROTATE_KEY;
    default:                   return 0u;
    }
}

/* Повна довжина кадру за опкодом; 0 = опкод не командний. */
static inline uint8_t Dl_Ccm_Frame_Len(uint8_t opcode)
{
    uint8_t body = Dl_Ccm_Body_Len(opcode);
    return body ? (uint8_t)(DL_CCM_AAD_LEN + body + DL_CCM_MIC_LEN) : 0u;
}

/* Структура без ключа: командний опкод і рівно його довжина. Цього досить
 * Королеві (MIC вона звірити не може) і Солдату як дешевий фільтр до крипти. */
static inline int Dl_Ccm_Frame_Well_Formed(const uint8_t *frame, uint16_t len)
{
    if (len < 1u) return 0;
    uint8_t expected = Dl_Ccm_Frame_Len(frame[0]);
    return expected != 0u && len == expected;
}

static inline uint32_t Dl_Ccm_Frame_Did(const uint8_t *frame)
{
    return ((uint32_t)frame[DL_CCM_DID_OFFSET] << 24) |
           ((uint32_t)frame[DL_CCM_DID_OFFSET + 1] << 16) |
           ((uint32_t)frame[DL_CCM_DID_OFFSET + 2] << 8) |
           (uint32_t)frame[DL_CCM_DID_OFFSET + 3];
}

static inline uint16_t Dl_Ccm_Frame_Dlfc_Lsb(const uint8_t *frame)
{
    return (uint16_t)(((uint16_t)frame[DL_CCM_DLFC_OFFSET] << 8) |
                      frame[DL_CCM_DLFC_OFFSET + 1]);
}

/* AAD = [opcode][DID BE][DLFC_lsb BE] — рівно перші 7 байт кадру. */
static inline void Build_DL_CCM_AAD(uint8_t opcode, uint32_t did, uint32_t dlfc,
                                    uint8_t aad[DL_CCM_AAD_LEN])
{
    aad[0] = opcode;
    aad[1] = (uint8_t)(did >> 24);
    aad[2] = (uint8_t)(did >> 16);
    aad[3] = (uint8_t)(did >> 8);
    aad[4] = (uint8_t)(did);
    aad[5] = (uint8_t)(dlfc >> 8);
    aad[6] = (uint8_t)(dlfc);
}

/* Нонс = DID ‖ DLFC32 BE ‖ 0x01 ‖ 0x00×3 (байт напрямку — див. шапку). */
static inline void Build_DL_CCM_Nonce(uint32_t did, uint32_t dlfc,
                                      uint8_t nonce[FW2_CCM_NONCE_LEN])
{
    nonce[0]  = (uint8_t)(did >> 24);
    nonce[1]  = (uint8_t)(did >> 16);
    nonce[2]  = (uint8_t)(did >> 8);
    nonce[3]  = (uint8_t)(did);
    nonce[4]  = (uint8_t)(dlfc >> 24);
    nonce[5]  = (uint8_t)(dlfc >> 16);
    nonce[6]  = (uint8_t)(dlfc >> 8);
    nonce[7]  = (uint8_t)(dlfc);
    nonce[8]  = DL_CCM_DIRECTION_BYTE;
    nonce[9]  = 0x00;
    nonce[10] = 0x00;
    nonce[11] = 0x00;
}

/* Flash-KV ключ DLFC на Солдаті — останній прийнятий, u32 (реєстр 03_01 §2.3.1;
 * раніше вільний 0x12). Свіжий журнал re-provision його не несе → DLFC 0. */
#define DL_CCM_KV_KEY_DLFC          0x12u

/* ── Тіла команд — little-endian поля старого каркаса (OtaPackagerService) ──
 * Розпаковка й межі самого поля; зміст судить домен: ратчет — Key_Ratchet_Steps. */

/* 0x9E: [target_version:u16le]. */
static inline uint16_t Dl_Cmd_Rotate_Target(const uint8_t body[DL_CCM_BODY_ROTATE_KEY])
{
    return (uint16_t)((uint16_t)body[0] | ((uint16_t)body[1] << 8));
}

/* Найменше u32 > last з молодшими бітами lsb. 0 = переповнення (last уже в
 * останньому 16-бітному вікні) — кадр не приймається. Легального 0 немає:
 * Rails видає DLFC від 1, а результат завжди > last ≥ 0. */
static inline uint32_t Dl_Ccm_Reconstruct_Dlfc(uint32_t last, uint16_t lsb)
{
    uint32_t cand = (last & 0xFFFF0000u) | lsb;
    if (cand > last) return cand;
    if ((last & 0xFFFF0000u) == 0xFFFF0000u) return 0u;
    return cand + 0x10000u;
}

#endif /* SILKEN_DOWNLINK_CCM_H */
