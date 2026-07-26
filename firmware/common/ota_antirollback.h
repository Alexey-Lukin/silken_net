// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ota_antirollback.h — [SEC.20] високий приплив версії OTA: bytecode тече
 *                       лише вперед, старе слово не воскресає.
 *
 * Навіщо: dual-gate (FW.23, 03_06 §4) доводить, що образ СПРАВЖНІЙ (K_ota-
 * підпис над тілом ‖ версією), але не що він НОВІШИЙ. Захоплений валідно-
 * підписаний СТАРИЙ broadcast, пущений знову в ефір, проходив би всі брами →
 * тихий відкат bio_contract на версію з уже-загоєними ранами (money-баги
 * GP-формул E.63/FW.29). Той самий replay, з яким билися на uplink (CCM FC
 * high-water), лише на downlink — і downlink-MAC/FC (03_05 §2.4) його не ловить
 * (він проти transport-replay, не проти валідно-підписаної СТАРОЇ версії).
 *
 * Як: у Flash-KV (ключ 0x15) лежить найвища застосована версія. Кожен APPLY
 * мусить СТРОГО перевершити її. Flash-якір переживає повну смерть живлення
 * (сезонний drain EDLC) — на відміну від RTC; той самий урок, що fc_hiwater
 * вивчив для Frame Counter (03_05 §2.1). Без нього слот обнулявся б щозими →
 * перший же replay старої версії проходив би без жодного атакера.
 *
 * Інваріант I-AR: жоден bytecode, записаний у contract-Flash, не має версію
 * ≤ значенню ключа 0x15 на момент запису. Тоді replay старого = математично
 * відкинутий, без довіри до транспорту.
 *
 * Degraded (Flash-KV не змонтований): приплив недоступний → APPLY дозволено.
 * Оновлення дорожче за теоретичний replay на вже-мертвому Flash — дзеркало
 * degraded-шляху fc_hiwater. Атакер Flash здалеку не вбиває, тож fail-open тут
 * не дарує йому вектора.
 *
 * Гонка Write→Commit (викликач — soldier/main.c): приплив підіймається ПІСЛЯ
 * запису contract-сторінки. Power-cut між ними лишає contract новим, а приплив
 * старим → наступний boot дозволить лише ПОВТОРНИЙ APPLY тієї ж версії (той
 * самий bytecode, безпечно), не блокування свіжої. Зворотний порядок замкнув
 * би легітимну нову версію назавжди.
 *
 * One-Home: журнальний Flash — flash_kv.h; тут ЛИШЕ версійна політика.
 * Канон: 03_06 §4 (OTA-auth) + 03_05 §2.4 + 03_01 §2.3.1 (реєстр KV) + 00_07 SEC.20.
 */
#ifndef SILKEN_OTA_ANTIROLLBACK_H
#define SILKEN_OTA_ANTIROLLBACK_H

#include <stdint.h>
#include "flash_kv.h"

/* Реєстр KV-ключів — 03_01 §2.3.1 (0x14 = FW2_FC_HIWATER, 0x20 = S2_BITMAP). */
#define SEC20_OTA_VER_KV_KEY   0x15u

/* Найвища застосована версія з Flash. 0 = ключа ще нема (перший OTA) —
 * тоді будь-яка версія > 0 свіжа. */
static inline uint32_t Ota_Version_Load(const FlashKv *kv)
{
    uint32_t v = 0;
    if (!FlashKv_Get32(kv, SEC20_OTA_VER_KV_KEY, &v)) return 0;
    return v;
}

/* 1 = версія свіжа (строго вища за приплив) → APPLY дозволено; 0 = replay/
 * downgrade → REJECT. !mounted → degraded-allow (див. шапку). */
static inline int Ota_Version_Is_Fresh(const FlashKv *kv, int mounted, uint32_t version)
{
    if (!mounted) return 1;
    return version > Ota_Version_Load(kv);
}

/* Підняти приплив до застосованої версії (ПІСЛЯ Flash-запису contract).
 * !mounted або put-fail → no-op (degraded — приплив лишається, гірше не буде). */
static inline void Ota_Version_Commit(FlashKv *kv, int mounted, uint32_t version)
{
    if (!mounted) return;
    (void)FlashKv_Put32(kv, SEC20_OTA_VER_KV_KEY, version);
}

#endif /* SILKEN_OTA_ANTIROLLBACK_H */
