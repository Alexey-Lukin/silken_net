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
// 🧭 Збирання кампанії й курсор фетчу (⚖️ FW.60, делеговано 2026-10-09)
// =========================================================================
//
// Тіло зібране, коли розмір є, а мапа й лічильник обнулені завершенням (0x99-гілка
// main.c обнуляє їх саме тоді). Стан липкий до світанку нової кампанії, а світанок
// робить лише зміна fw у хінті (Queen_Ota_Campaign_Dawn): кожна кампанія приходить
// після свого hint'а. Тому пакет тіла, що прийшов після завершення, — дубль тієї ж
// кампанії (повторний фетч), а не світанок: інакше він стирав би щойно зібране.
static inline uint8_t Ota_Body_Complete(uint16_t body_size, uint16_t assembly_bitmap,
                                        uint16_t assembly_received)
{
    return (uint8_t)(body_size > 0u && assembly_bitmap == 0u && assembly_received == 0u);
}

static inline uint8_t Ota_Body_Is_Duplicate(uint16_t body_size, uint16_t assembly_bitmap,
                                            uint16_t assembly_received, uint16_t chunk_bit)
{
    if (Ota_Body_Complete(body_size, assembly_bitmap, assembly_received)) return 1;
    return (uint8_t)((assembly_bitmap & chunk_bit) != 0u);
}

// Що тягнути наступним, каже збирання, а не курсор: перший пакет, якого бракує,
// починаючи з `from` і по колу. Пакети кампанії нумеровані, як їх видає
// OtaPackagerService: тіло (0..body_n−1), тоді trailer_n блоків печатки. Тіло, поки не
// зібране, — бітмап CoAP-чанків; печатка — маска трейлера. Відкинутий пакет (транзитна
// CRC тіла, битий блок) лишає діру, і курсор вертається до неї на наступному колі;
// зібране вдруге не тягнеться. Повертає fetch_total — бракує нічого.
// Межу повторів дає не лічильник, а сторож ARCH.59: знята кампанія відповідає 4.04, і
// викликач гасить pending (канон 03_02 §4а).
//
// Pure: host-тести firmware/test/test_queen_logic.c. Викликач — Queen_Poll_Downlink.
static inline uint16_t Ota_Fetch_Next_Missing(uint16_t from, uint16_t fetch_total,
                                              uint16_t trailer_n, uint8_t body_complete,
                                              uint16_t body_bitmap, uint8_t seal_mask)
{
    if (fetch_total <= trailer_n) return fetch_total;
    const uint16_t body_n = (uint16_t)(fetch_total - trailer_n);
    if (from >= fetch_total) from = 0;
    for (uint16_t k = 0; k < fetch_total; k++) {
        const uint16_t i = (uint16_t)((from + k) % fetch_total);
        if (i < body_n) {
            /* поза 16-бітною мапою (стеля OTA_MAX_CHUNKS) — не тягнемо: такої кампанії
             * диспетчер не видає, а тягнути безкінечно те, що не ляже, гірше */
            if (!body_complete && i < 16u && !(body_bitmap & (uint16_t)(1u << i))) return i;
        } else {
            const uint16_t s = (uint16_t)(i - body_n);
            if (s < 8u && !(seal_mask & (uint8_t)(1u << s))) return i;
        }
    }
    return fetch_total;
}

#endif // OTA_WINDOW_H
