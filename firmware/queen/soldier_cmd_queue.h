// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * soldier_cmd_queue.h — [FW.20-Q2 · FW.17] черга адресних команд Rails → Солдат.
 *
 * Королева — сліпий курʼєр: Rails приносить готовий кадр, підписаний сесійним
 * ключем цільового вузла (downlink-wire-ревізія, 03_05 §2.5; формат —
 * common/downlink_ccm.h):
 *
 *   [opcode:1][DID:4][DLFC_lsb:2][CCM(body)][MIC:8]   — 17 / 20 / 23 Б
 *
 * Ключа Королева не має, тож перевіряє лише структуру (командний опкод і рівно
 * його довжина) і стріляє кадр як є, нічим його не шифруючи.
 *
 * Постріл — рефлекторний і АДРЕСНИЙ: лише коли почутий DID збігся з DID
 * команди. Солдат слухає ефір ~500 мс після ВЛАСНОГО TX, тож постріл услід за
 * голосом цілі — єдине гарантовано чуте вікно; маяк летить у переважно глухий
 * ліс (ADR — 03_02 §5б).
 *
 * Порядок для одного DID — за DLFC, найменший першим: Солдат приймає лише
 * DLFC, строго більший за останній прийнятий, тож старшу команду, вистріляну
 * після молодшої, він уже не відкриє ніколи. Порівняння — серійне по 16 бітах
 * ефіру (переходить через 0xFFFF → 0x0000).
 *
 * Бюджет — спроби В ЦІЛЬ, не оберт кластера: кожен постріл летить у відкрите
 * вікно саме цього Солдата, тож бюджет покриває лише втрачені вікна (радіо,
 * правило «один пакет за пробудження»). Більший бюджет повернув би холості
 * постріли, які адресність і знімає, і тримав би чергу за вже доставленою
 * командою. ACK на LoRa-рівні немає: Rails перевидає відкриту команду тим
 * самим кадром, і дублікат лише освіжає бюджет.
 *
 * Pure C, без HAL — host-тести: firmware/test/test_soldier_cmd_queue.c.
 */
#ifndef SILKEN_SOLDIER_CMD_QUEUE_H
#define SILKEN_SOLDIER_CMD_QUEUE_H

#include <stdint.h>
#include <string.h>

#include "../common/downlink_ccm.h"

/* 4 спроби в ціль — інженерний параметр, не вимір: запас на кілька втрачених
 * вікон поспіль. Частоту втрат вікна дасть лише стенд і поле. */
#define SOLDIER_CMD_SHOT_BUDGET  4u

/* Слотів небагато свідомо; глибина під кластерну ротацію (різні кадри на
 * кожен вузол) — нога активації FW.17 (03_05 §3.8). */
#define SOLDIER_CMD_QUEUE_SLOTS  4u

typedef struct {
    uint8_t  frame[SOLDIER_CMD_QUEUE_SLOTS][DL_CCM_FRAME_MAX];
    uint8_t  len[SOLDIER_CMD_QUEUE_SLOTS];   /* кадр + довжина = 24 Б слот */
    uint8_t  shots[SOLDIER_CMD_QUEUE_SLOTS]; /* лишок бюджету; 0 = слот вільний */
    uint32_t seq[SOLDIER_CMD_QUEUE_SLOTS];   /* коли поставлено чи освіжено */
    uint32_t clock;
} SoldierCmdQueue;

static inline void Soldier_Cmd_Queue_Init(SoldierCmdQueue *q)
{
    memset(q, 0, sizeof(*q));
}

/* Кадр → черга. 1 = у черзі (новим слотом або освіженим дублікатом),
 * 0 = структура не командна. Переповнення не відмовляє: витісняється слот,
 * найдавніше поставлений чи освіжений. Не «найменший лишок»: за адресних
 * пострілів лишок меншає лише в живих цілей, тож те правило витісняло б саме
 * їх, лишаючи в черзі команди дерев, що мовчать. */
static inline int Soldier_Cmd_Queue_Push(SoldierCmdQueue *q,
                                         const uint8_t *frame, uint16_t frame_size)
{
    if (!Dl_Ccm_Frame_Well_Formed(frame, frame_size)) return 0;
    q->clock++;

    for (uint8_t i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        if (q->shots[i] > 0u && q->len[i] == frame_size &&
            memcmp(q->frame[i], frame, frame_size) == 0) {
            q->shots[i] = SOLDIER_CMD_SHOT_BUDGET;
            q->seq[i]   = q->clock;
            return 1;
        }
    }

    uint8_t victim = 0;
    for (uint8_t i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        if (q->shots[i] == 0u) { victim = i; break; }
        if (q->seq[i] < q->seq[victim]) victim = i;
    }

    memcpy(q->frame[victim], frame, frame_size);
    q->len[victim]   = (uint8_t)frame_size;
    q->shots[victim] = SOLDIER_CMD_SHOT_BUDGET;
    q->seq[victim]   = q->clock;
    return 1;
}

/* Слот команди для почутого DID — з найменшим DLFC; -1 = для нього нічого.
 * Бюджет не витрачає: спершу лімітер ефіру, потім Take. */
static inline int Soldier_Cmd_Queue_Find_For(const SoldierCmdQueue *q, uint32_t heard_did)
{
    int best = -1;
    for (uint8_t i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        if (q->shots[i] == 0u || Dl_Ccm_Frame_Did(q->frame[i]) != heard_did) continue;
        if (best < 0 ||
            ((uint16_t)(Dl_Ccm_Frame_Dlfc_Lsb(q->frame[i]) -
                        Dl_Ccm_Frame_Dlfc_Lsb(q->frame[best])) & 0x8000u) != 0u) {
            best = i;
        }
    }
    return best;
}

/* Постріл зі слота: копія кадру, бюджет −1, згаслий слот звільняється.
 * Повертає довжину кадру. */
static inline uint8_t Soldier_Cmd_Queue_Take(SoldierCmdQueue *q, int slot,
                                             uint8_t out[DL_CCM_FRAME_MAX])
{
    memcpy(out, q->frame[slot], q->len[slot]);
    q->shots[slot]--;
    return q->len[slot];
}

#endif /* SILKEN_SOLDIER_CMD_QUEUE_H */
