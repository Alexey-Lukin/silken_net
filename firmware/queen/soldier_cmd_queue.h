/*
 * soldier_cmd_queue.h — [FW.20-Q2] черга Soldier-bound команд (0x9A, 0x9E).
 *
 * Королева — гонець, не тлумач: CoAP-downlink від Rails приносить готовий
 * командний кадр спільного каркаса (DOC.4, 03_01 §4.5а)
 *
 *   [маркер:1][len_le:2][body:len-2][crc16_le:2],  CRC-16/CCITT-FALSE над body
 *
 * Черга тримає його plaintext-блоком 16 Б (один LoRa AES-блок, zero-pad) і
 * віддає по одному «рефлекторному пострілу» на кожен прийнятий uplink —
 * Солдат слухає ефір лише ~500 мс після ВЛАСНОГО TX, тож постріл услід за
 * його голосом — єдине вікно, коли слово гарантовано чуте. Періодичний маяк
 * (Broadcast_Time_Beacon) для доставки НЕ годиться: він летить у переважно
 * глухий ліс (ADR; тому черга — рефлекторна, не маякова).
 *
 * Повторні постріли того самого кадру нешкідливі за конструкцією: 0x9E —
 * forward-only ratchet (replay → відмова, key_ratchet.h), 0x9A — ідемпотентне
 * виставлення порогів. Тож не чекаємо ACK (його на LoRa-рівні нема; справжній
 * per-device ACK 0x9E = Dual-Key Grace на бекенді, 03_05 §3.8) — даємо кадру
 * бюджет пострілів, що покриває повний оберт кластера uplink'ів з запасом.
 *
 * Дедуп: ідентичний блок уже в черзі (Sidekiq retry, подвійний dispatch) →
 * не множимо, лише освіжаємо бюджет.
 *
 * Активація — разом із Soldier-гілками (FW2 CCM → FW17_RATCHET_ENABLED /
 * FW8_PARSER_ENABLED): ECB-downlink без MAC не сміє командувати ротацією,
 * а на спільному транзит-ключі командний broadcast чули б усі (per-device
 * адресація приходить лише з CCM-криптом). Гейт Queen-боку —
 * FW20_Q2_CMD_RELAY_ENABLED у main.c. Канон: 03_02 §5б, 03_05 §3.8.
 *
 * Pure C, без HAL — host-тести: firmware/test/test_soldier_cmd_queue.c.
 */
#ifndef SILKEN_SOLDIER_CMD_QUEUE_H
#define SILKEN_SOLDIER_CMD_QUEUE_H

#include <stdint.h>
#include <string.h>

#include "../common/silken_crc.h"

/* Опкоди, яким дозволено в чергу (DOC.4, 03_01 §4.5а). Новий Soldier-bound
 * CMD спільного каркаса → додати сюди І в опкод-карту. */
#define SOLDIER_CMD_MARKER_THRESHOLDS  0x9Au  /* CMD_SET_THRESHOLDS (FW.8) */
#define SOLDIER_CMD_MARKER_ROTATE_KEY  0x9Eu  /* CMD_ROTATE_KEY (FW.17)   */

#define SOLDIER_CMD_BLOCK_SIZE   16u  /* один LoRa AES-блок */
#define SOLDIER_CMD_HEADER_SIZE  3u   /* [маркер:1][len_le:2] */
#define SOLDIER_CMD_CRC_SIZE     2u
/* Мінімальний кадр: header + body(≥1) + crc16. */
#define SOLDIER_CMD_MIN_FRAME    (SOLDIER_CMD_HEADER_SIZE + 1u + SOLDIER_CMD_CRC_SIZE)

/* Бюджет пострілів на кадр: Queen чує ~1-2 uplink/с при повному CIFO
 * (50 слотів ≈ кластер), цикл Солдата 26-32 с ⇒ 64 пострілів покривають
 * понад один повний оберт кластера — вікно цільового Солдата гарантовано
 * влучене щонайменше раз. Кожен постріл ≈ 60 мс ефіру. */
#define SOLDIER_CMD_SHOT_BUDGET  64u

/* Слотів небагато свідомо: на транзит-ключі cluster-wide батч ідентичних
 * кадрів дедупиться в один; per-device CCM-батч (роздільні байти) — частина
 * активаційного дизайну FW.2 і може попросити глибшу чергу (03_05 §3.8). */
#define SOLDIER_CMD_QUEUE_SLOTS  4u

typedef struct {
    uint8_t block[SOLDIER_CMD_QUEUE_SLOTS][SOLDIER_CMD_BLOCK_SIZE];
    uint8_t shots[SOLDIER_CMD_QUEUE_SLOTS]; /* лишок бюджету; 0 = слот вільний */
    uint8_t next;                           /* round-robin курсор TX */
} SoldierCmdQueue;

static inline void Soldier_Cmd_Queue_Init(SoldierCmdQueue *q)
{
    memset(q, 0, sizeof(*q));
}

/* Валідатор спільного каркаса — дзеркало guard'ів Солдата
 * (Key_Ratchet_Parse_Cmd / Soldier_Handle_CMD_SET_THRESHOLDS), щоб біт,
 * збрехавший у LTE-транзиті, помирав тут, а не з'їдав постріли в ефірі.
 * 1 = кадр валідний і вміщається в один LoRa-блок. */
static inline int Soldier_Cmd_Frame_Valid(const uint8_t *frame, uint16_t frame_size)
{
    if (frame_size < SOLDIER_CMD_MIN_FRAME)               return 0;
    if (frame[0] != SOLDIER_CMD_MARKER_THRESHOLDS &&
        frame[0] != SOLDIER_CMD_MARKER_ROTATE_KEY)        return 0;

    uint16_t payload_len = (uint16_t)frame[1] | ((uint16_t)frame[2] << 8);
    if (payload_len < SOLDIER_CMD_CRC_SIZE + 1u)          return 0;

    uint16_t total = (uint16_t)(SOLDIER_CMD_HEADER_SIZE + payload_len);
    if (total > SOLDIER_CMD_BLOCK_SIZE)                   return 0;
    if (total > frame_size)                               return 0;

    uint16_t body_len = (uint16_t)(payload_len - SOLDIER_CMD_CRC_SIZE);
    const uint8_t *body = frame + SOLDIER_CMD_HEADER_SIZE;
    uint16_t expected_crc = Silken_Crc16_Ccitt(body, body_len);
    uint16_t received_crc = (uint16_t)body[body_len]
                          | ((uint16_t)body[body_len + 1] << 8);
    if (expected_crc != received_crc)                     return 0;

    return 1;
}

/* Кадр → черга. 1 = у черзі (новим слотом або освіженим дублікатом),
 * 0 = кадр відкинуто валідатором. Переповнення не відмовляє: витісняємо
 * слот із найменшим лишком бюджету (найближчий до згасання) — свіжа
 * команда цінніша за майже відстріляну. */
static inline int Soldier_Cmd_Queue_Push(SoldierCmdQueue *q,
                                         const uint8_t *frame, uint16_t frame_size)
{
    if (!Soldier_Cmd_Frame_Valid(frame, frame_size)) return 0;

    uint8_t padded[SOLDIER_CMD_BLOCK_SIZE] = {0};
    uint16_t payload_len = (uint16_t)frame[1] | ((uint16_t)frame[2] << 8);
    memcpy(padded, frame, (size_t)(SOLDIER_CMD_HEADER_SIZE + payload_len));

    /* Дедуп: той самий блок уже летить — лише освіжаємо бюджет. */
    for (uint8_t i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        if (q->shots[i] > 0u &&
            memcmp(q->block[i], padded, SOLDIER_CMD_BLOCK_SIZE) == 0) {
            q->shots[i] = SOLDIER_CMD_SHOT_BUDGET;
            return 1;
        }
    }

    /* Вільний слот, інакше — жертва з найменшим лишком. */
    uint8_t victim = 0;
    for (uint8_t i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        if (q->shots[i] == 0u) { victim = i; break; }
        if (q->shots[i] < q->shots[victim]) victim = i;
    }

    memcpy(q->block[victim], padded, SOLDIER_CMD_BLOCK_SIZE);
    q->shots[victim] = SOLDIER_CMD_SHOT_BUDGET;
    return 1;
}

/* Один рефлекторний постріл: round-robin серед живих слотів (щоб два кадри
 * в черзі не голодували один одного), бюджет −1, згаслий слот звільняється.
 * 1 = out_block готовий до AES-encrypt + Radio.Send. */
static inline int Soldier_Cmd_Queue_Next(SoldierCmdQueue *q,
                                         uint8_t out_block[SOLDIER_CMD_BLOCK_SIZE])
{
    for (uint8_t i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        uint8_t idx = (uint8_t)((q->next + i) % SOLDIER_CMD_QUEUE_SLOTS);
        if (q->shots[idx] == 0u) continue;
        memcpy(out_block, q->block[idx], SOLDIER_CMD_BLOCK_SIZE);
        q->shots[idx]--;
        q->next = (uint8_t)((idx + 1u) % SOLDIER_CMD_QUEUE_SLOTS);
        return 1;
    }
    return 0;
}

#endif /* SILKEN_SOLDIER_CMD_QUEUE_H */
