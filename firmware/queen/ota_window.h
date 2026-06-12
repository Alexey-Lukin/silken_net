#ifndef OTA_WINDOW_H
#define OTA_WINDOW_H

#include <stdint.h>

// = =========================================================================
// 🕯️ Ota_Late_Trailer_Resurrects — воскресіння OTA-вікна запізнілою печаткою
// = =========================================================================
//
// [FW.52б, рішення founder 2026-06-12] Печатка (4 × 0x9B трейлер-чанки) їде
// від Rails ОКРЕМИМИ CoAP-чанками — порядок відносно тіла не гарантований,
// а downlink-нагоди прив'язані до flush-циклів. Якщо тіло відлунало раніше,
// Королева слушно гасить вікно ([PLAN 2.5] — не проповідувати в пустоту),
// але БЕЗ цього предиката запізніла печатка лягала в пам'ять мовчки: тіло
// в RAM ціле, печатка зібрана, Солдати кричать re-request — а вікно мертве
// до повторного повного push з Rails (канон 03_02 §5.X.6 п.2).
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

#endif // OTA_WINDOW_H
