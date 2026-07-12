/*
 * beacon_dedup.h — [FW.20-S2 4/5] anti-storm журнал поколінь Time Beacon.
 *
 * Навіщо: повний mesh-relay дозволяє Провіднику нести далі ВЖЕ relay'ні
 * маяки (auth=0) — auth-біт перестає бути єдиним глушником шторму.
 * Королева маячить і кожні ~15 хв, і reflex'ом на зойк 0x56 (перемотка
 * такту), тож одне покоління часу лунає в ефірі кілька разів; при TTL≥3 додається
 * луна Провідник↔Провідник. Без журналу «це покоління я вже ніс» кожен
 * Провідник помножував би кожен почутий маяк — O(N²) airtime на покоління.
 * З журналом обсяг шторму обмежений конструкцією: ≤1 ретрансляція на
 * покоління на Провідника, TTL відповідає лише за ГЛИБИНУ, не за обсяг.
 *
 * Чому Flash, не SRAM/RTC: у цільовому RTC-only режимі (03_01 §1.10,
 * 300 нА) SRAM гасне щоциклу — RAM-журнал забував би все до наступного
 * пробудження і шторм повертався б. RTC backup повний (DR15 зайнято FW.2),
 * тож стан їде у Flash-KV (ARCH.28 шлях A) — резолюція 2026-05-30.
 *
 * Дизайн — sliding window (анти-replay патерн IPsec), ОДИН атомарний dw:
 *   • Покоління = unix_ts / 900 (такт маяка Королеви). Воно стійке до
 *     per-hop drift-компенсації (+секунди hold'у); перетин 900-с межі
 *     дрейфом коштує щонайбільше однієї зайвої ретрансляції — не шторм.
 *   • KV-ключ 0x20, значення = [gen_hi:24 | window:8]. gen завжди
 *     вміщується: max uint32 ts / 900 = 4 772 185 < 2²⁴. Один dw замість
 *     multi-dw — ECC-атомарність flash_kv гарантує «або записалось, або
 *     ні»: порваної пари gen↔window не існує, wear удвічі менший.
 *   • Вікно 8 поколінь = 2 год — глибше за max hop-delay (1 год, Guard 6
 *     relay'я). Старше за вікно = «бачили»: відмова ретранслювати
 *     застарілий час — фіча, не обмеження.
 *
 * Дисципліна викликача (soldier/main.c): Mark — чиста RAM-мутація,
 * безпечна під RX-вікном; Persist — окремо у КЕНОЗИСІ (Flash-program не
 * сміє лягати під LoRa RX). Power-cut між ними коштує однієї зайвої
 * ретрансляції після ребуту — деградація, не шторм.
 *
 * One-Home: журнальний Flash — flash_kv.h; wire-формат маяка — 03_02 §5а;
 * тут ЛИШЕ політика дедуплікації. Канон: 03_02 §5а + 03_01 §2.3.1
 * (реєстр KV-ключів) + 00_07 FW.20-S2.
 */
#ifndef SILKEN_BEACON_DEDUP_H
#define SILKEN_BEACON_DEDUP_H

#include <stdint.h>
#include "flash_kv.h"

/* Реєстр KV-ключів — 03_01 §2.3.1 (0x14 = FW2_FC_HIWATER, 0x20 = цей). */
#define FW20_DEDUP_KV_KEY       0x20u

/* Такт покоління = номінальний період маяка Королеви (TIME_BEACON_INTERVAL).
 * Зміна періоду маяка міняє лише гранулярність дедупу, не коректність. */
#define FW20_DEDUP_GEN_SECONDS  900u

#define FW20_DEDUP_WINDOW_BITS  8u

typedef struct {
    uint32_t gen_hi;  /* найновіше марковане покоління; 0 = журнал порожній */
    uint8_t  window;  /* біт i = покоління (gen_hi − i) вже ретрансльовано */
    uint8_t  dirty;   /* RAM розійшовся з Flash → Persist у КЕНОЗИСІ */
} BeaconDedup;

static inline uint32_t Beacon_Dedup_Gen(uint32_t unix_ts)
{
    return unix_ts / FW20_DEDUP_GEN_SECONDS;
}

/* Boot-restore з Flash. Нема ключа / сміття (window без gen) → порожній
 * журнал — перший почутий маяк піде в ефір, далі дедуп тримає лінію. */
static inline void Beacon_Dedup_Load(const FlashKv *kv, BeaconDedup *bd)
{
    uint32_t v = 0;
    bd->gen_hi = 0;
    bd->window = 0;
    bd->dirty  = 0;
    if (!FlashKv_Get32(kv, FW20_DEDUP_KV_KEY, &v)) return;
    if ((v >> 8) == 0) return;
    bd->gen_hi = v >> 8;
    bd->window = (uint8_t)(v & 0xFFu) | 1u; /* інваріант: gen_hi марковано */
}

/* 1 = покоління вже несли (або воно старше за вікно — застарілий час не
 * ретранслюємо), 0 = свіже. Чисте читання — безпечно у guard-ланцюзі. */
static inline int Beacon_Dedup_Seen(const BeaconDedup *bd, uint32_t gen)
{
    if (bd->gen_hi == 0) return 0;
    if (gen > bd->gen_hi) return 0;
    uint32_t delta = bd->gen_hi - gen;
    if (delta >= FW20_DEDUP_WINDOW_BITS) return 1;
    return (bd->window >> delta) & 1u;
}

/* Зафіксувати «це покоління понесли» — ЛИШЕ RAM (під RX-вікном безпечно).
 * dirty стає 1 тільки коли стан справді змінився — повторний Mark того
 * самого покоління не коштує Flash-запису у КЕНОЗИСІ. */
static inline void Beacon_Dedup_Mark(BeaconDedup *bd, uint32_t gen)
{
    if (gen == 0) return; /* NULL_TS guard відсіює раніше; тут — захист */
    if (gen > bd->gen_hi) {
        uint32_t shift = gen - bd->gen_hi;
        bd->window = (bd->gen_hi != 0 && shift < FW20_DEDUP_WINDOW_BITS)
                         ? (uint8_t)((uint32_t)(bd->window << shift) | 1u)
                         : 1u;
        bd->gen_hi = gen;
        bd->dirty  = 1;
    } else {
        uint32_t delta = bd->gen_hi - gen;
        if (delta < FW20_DEDUP_WINDOW_BITS) {
            uint8_t bit = (uint8_t)(1u << delta);
            if (!(bd->window & bit)) {
                bd->window |= bit;
                bd->dirty   = 1;
            }
        }
    }
}

/* Скинути журнал у Flash (КЕНОЗИС). Чистий стан → no-op без wear.
 * Відмова program → 0, dirty лишається — RAM-копія тримає дедуп до сну,
 * наступний КЕНОЗИС спробує ще раз. */
static inline int Beacon_Dedup_Persist(FlashKv *kv, BeaconDedup *bd)
{
    if (!bd->dirty) return 1;
    if (!FlashKv_Put32(kv, FW20_DEDUP_KV_KEY,
                       (bd->gen_hi << 8) | bd->window)) return 0;
    bd->dirty = 0;
    return 1;
}

#endif /* SILKEN_BEACON_DEDUP_H */
