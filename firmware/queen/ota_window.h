// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef OTA_WINDOW_H
#define OTA_WINDOW_H

#include <stdint.h>

// = =========================================================================
// 🕯️ Ota_Late_Trailer_Resurrects — воскресіння OTA-вікна запізнілою печаткою
// = =========================================================================
//
// [FW.52б, рішення founder 2026-06-12] Печатка (7 × 0x9B трейлер-блоків, FW.23 Ed25519) їде
// від Rails ОКРЕМИМИ CoAP-чанками — порядок відносно тіла не гарантований,
// а downlink-нагоди прив'язані до flush-циклів. Якщо тіло відлунало раніше,
// Королева слушно гасить вікно ([PLAN 2.5] — не проповідувати в пустоту),
// але БЕЗ цього предиката запізніла печатка лягала в пам'ять мовчки: тіло
// в RAM ціле, печатка зібрана, Солдати кричать re-request — а вікно мертве
// до повторного повного push з Rails (канон 03_02 §5.1.6 п.2).
//
// Предикат істинний рівно тоді, коли четвертий сегмент довершив трейлер
// (all_mask), вікно згасло, тіло повністю зібране (збірка idle: bitmap і
// лічильник нульові — інакше re-request міг би служити недозібране), і є
// що казати (pending_ota_size > 0). Тоді викликач воскрешає вікно одразу
// у фазу печатки — анти-проповідь збережена, re-request знову почутий.
//
// Pure: host-тести firmware/test/test_queen_logic.c. Викликач — 0x9B
// хендлер main.c (мутація стану там, рішення — тут, One-Home).
static inline uint8_t Ota_Late_Trailer_Resurrects(uint8_t  trailer_seg_mask,
                                                  uint8_t  trailer_all_mask,
                                                  uint8_t  window_active,
                                                  uint16_t body_size,
                                                  uint16_t assembly_bitmap,
                                                  uint16_t assembly_received)
{
    return (uint8_t)((trailer_seg_mask == trailer_all_mask) &&
                     (window_active == 0u) &&
                     (body_size > 0u) &&
                     (assembly_bitmap == 0u) &&
                     (assembly_received == 0u));
}

// =========================================================================
// 🧭 Ota_Fetch_Rewind — куди повернути курсор фетчу (⚖️ FW.60, делеговано 2026-10-09)
// =========================================================================
//
// Курсор фетчу рухається на кожній відповіді, а відкинутий пакет (CRC тіла, конверт
// понад стелю) лишає діру: дійшовши кінця без живого вікна, курсор інакше стояв би там
// до ребуту Королеви, і `fw=` не прийшов би ніколи. Тож чого бракує, каже не курсор, а
// збирання: тіло — бітмап CoAP-чанків, поки збирання не довершене; печатка — маска
// трейлера, коли тіло зібране. Пакети кампанії нумеровані, як їх видає
// OtaPackagerService: тіло (0..body_n−1), тоді trailer_n блоків печатки. Повертає
// перший відсутній пакет або fetch_total — бракує нічого, фетчити нема чого.
// Межу повторів дає не лічильник, а сторож ARCH.59: знята кампанія відповідає 4.04, і
// викликач гасить pending (канон 03_02 §4а).
//
// Pure: host-тести firmware/test/test_queen_logic.c. Викликач — Queen_Poll_Downlink.
static inline uint16_t Ota_Fetch_Rewind(uint16_t fetch_total, uint16_t trailer_n,
                                        uint8_t  body_complete, uint16_t body_bitmap,
                                        uint8_t  seal_mask)
{
    if (fetch_total <= trailer_n) return fetch_total;
    const uint16_t body_n = (uint16_t)(fetch_total - trailer_n);
    if (!body_complete) {
        for (uint16_t i = 0; i < body_n && i < 16u; i++) {
            if (!(body_bitmap & (uint16_t)(1u << i))) return i;
        }
        return fetch_total;   /* поза 16-бітною мапою — стеля OTA_MAX_CHUNKS */
    }
    for (uint16_t s = 0; s < trailer_n && s < 8u; s++) {
        if (!(seal_mask & (uint8_t)(1u << s))) return (uint16_t)(body_n + s);
    }
    return fetch_total;
}

#endif // OTA_WINDOW_H
