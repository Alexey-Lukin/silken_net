// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * soldier_dr0.h — розкладка RTC-регістра DR0 Солдата: одне слово, п'ять полів.
 *
 * One-Home (гоча firmware #19): цей самий пакувальник кличуть усі писачі DR0 у
 * soldier/main.c — кінець циклу (Фаза 5), рятувальний шлях PVD, панічний кадр і
 * відкат байткоду SEC.20 — і host-тести. Доти кожен писач складав слово власним
 * виразом, а тест перевіряв власну копію з трьох надбудов: поле, додане в три вирази
 * з чотирьох, тихо обнулялося б четвертим, і копія лишалась би зеленою.
 *
 *   DR0 = [panic_frame_counter:16 | rsv:2 | reset_cause:3 | canary:1 | vm_err_streak:2 | acoustic_events:8]
 *          31                  16   15 14   13         11   10         9              8   7               0
 *
 * Канон розкладки — docs/03_01 §2 (рядок DR0); тут її виконавчий двійник. Писач поза
 * пакувальником один: __stack_chk_fail (main.c) АБО-ить біт канарки прямо в
 * TAMP->BKP0R і решту слова зберігає, тож поля нижче переживають і його.
 */
#ifndef SILKEN_SOLDIER_DR0_H
#define SILKEN_SOLDIER_DR0_H

#include <stdint.h>
#include "reset_cause.h"

#define PANIC_COUNTER_DR0_SHIFT     16      /* [SEC.10] anti-replay panic-кадрів (uint16) */
#define PANIC_COUNTER_MASK          0xFFFFu
#define RESET_CAUSE_DR0_SHIFT       11      /* [FW.59] коди reset_cause.h (3 біти) */
#define RESET_CAUSE_DR0_MASK        0x07u
#define CANARY_TRIP_DR0_SHIFT       10      /* [SEC.21] слід __stack_chk_fail */
#define CANARY_TRIP_MASK            0x01u
#define OTA_VM_ERR_STREAK_DR0_SHIFT 8       /* [SEC.20] поспіль збоїв байткоду OTA (0..3) */
#define OTA_VM_ERR_STREAK_MASK      0x03u
#define ACOUSTIC_EVENTS_DR0_MASK    0xFFu   /* [FW.22] з HW.30 писача немає — завжди 0 */

/* Поля не перетинаються: сума масок на місцях дорівнює їхньому АБО лише тоді, коли
 * жоден біт не зайнято двічі. Нова фіча, що вкраде зайнятий слот, впаде ТУТ на
 * компіляції, а не тихо перекриє money-path-лічильник у полі. */
#define SOLDIER_DR0_FIELD(mask, shift) ((uint64_t)(mask) << (shift))
_Static_assert(
    SOLDIER_DR0_FIELD(PANIC_COUNTER_MASK, PANIC_COUNTER_DR0_SHIFT) +
    SOLDIER_DR0_FIELD(RESET_CAUSE_DR0_MASK, RESET_CAUSE_DR0_SHIFT) +
    SOLDIER_DR0_FIELD(CANARY_TRIP_MASK, CANARY_TRIP_DR0_SHIFT) +
    SOLDIER_DR0_FIELD(OTA_VM_ERR_STREAK_MASK, OTA_VM_ERR_STREAK_DR0_SHIFT) +
    SOLDIER_DR0_FIELD(ACOUSTIC_EVENTS_DR0_MASK, 0)
    ==
    (SOLDIER_DR0_FIELD(PANIC_COUNTER_MASK, PANIC_COUNTER_DR0_SHIFT) |
     SOLDIER_DR0_FIELD(RESET_CAUSE_DR0_MASK, RESET_CAUSE_DR0_SHIFT) |
     SOLDIER_DR0_FIELD(CANARY_TRIP_MASK, CANARY_TRIP_DR0_SHIFT) |
     SOLDIER_DR0_FIELD(OTA_VM_ERR_STREAK_MASK, OTA_VM_ERR_STREAK_DR0_SHIFT) |
     SOLDIER_DR0_FIELD(ACOUSTIC_EVENTS_DR0_MASK, 0)),
    "DR0 bit-map collision — поля перетнулись; ревізувати docs/03_01 §2");
_Static_assert(SOLDIER_DR0_FIELD(PANIC_COUNTER_MASK, PANIC_COUNTER_DR0_SHIFT) <= 0xFFFFFFFFull,
               "DR0 — 32-бітний регістр");
_Static_assert(RESET_CAUSE_DR0_MASK == SILKEN_RESET_CAUSE_MAX,
               "поле DR0 вміщає рівно коди reset_cause.h");

typedef struct {
    uint16_t panic_counter;
    uint8_t  reset_cause;      /* причина останнього СПРАВЖНЬОГО ребуту — стан, не подія */
    uint8_t  canary_tripped;
    uint8_t  vm_err_streak;
    uint8_t  acoustic_events;
} SoldierDr0;

static inline uint32_t Soldier_Dr0_Pack(const SoldierDr0 *s)
{
    /* Код поза діапазоном — «не повідомлено», а не маска: 9 & 7 = 1 дав би вигаданий
     * POWER_ON. Решта полів маскується, як маскували всі писачі доти. */
    uint8_t cause = (s->reset_cause <= RESET_CAUSE_DR0_MASK) ? s->reset_cause
                                                             : (uint8_t)SILKEN_RESET_UNKNOWN;
    return ((uint32_t)s->panic_counter << PANIC_COUNTER_DR0_SHIFT) |
           ((uint32_t)cause << RESET_CAUSE_DR0_SHIFT) |
           ((uint32_t)(s->canary_tripped & CANARY_TRIP_MASK) << CANARY_TRIP_DR0_SHIFT) |
           ((uint32_t)(s->vm_err_streak & OTA_VM_ERR_STREAK_MASK) << OTA_VM_ERR_STREAK_DR0_SHIFT) |
           (uint32_t)s->acoustic_events;
}

static inline SoldierDr0 Soldier_Dr0_Unpack(uint32_t raw)
{
    SoldierDr0 s;
    s.panic_counter   = (uint16_t)((raw >> PANIC_COUNTER_DR0_SHIFT) & PANIC_COUNTER_MASK);
    s.reset_cause     = (uint8_t)((raw >> RESET_CAUSE_DR0_SHIFT) & RESET_CAUSE_DR0_MASK);
    s.canary_tripped  = (uint8_t)((raw >> CANARY_TRIP_DR0_SHIFT) & CANARY_TRIP_MASK);
    s.vm_err_streak   = (uint8_t)((raw >> OTA_VM_ERR_STREAK_DR0_SHIFT) & OTA_VM_ERR_STREAK_MASK);
    s.acoustic_events = (uint8_t)(raw & ACOUSTIC_EVENTS_DR0_MASK);
    return s;
}

#endif /* SILKEN_SOLDIER_DR0_H */
