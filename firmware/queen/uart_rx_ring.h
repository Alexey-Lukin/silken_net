// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * uart_rx_ring.h — [FW.3] кільце-вид поверх circular-DMA UART RX (pure).
 *
 * Стара схема читала модем побайтово (`HAL_UART_Receive(1)`): байти, що
 * прилітали МІЖ викликами чи поза вікном транзакції — губились назавжди
 * (ORE overrun; запізнілий `+CCOAPNMI` зникав без сліду). Тут DMA пише в
 * кільце безперервно і без CPU, а цей модуль — чиста арифметика погляду
 * консьюмера на нього: жоден байт не вмирає мовчки.
 *
 * Продюсер описується знімком (wraps, ndtr):
 *   wraps — лічильник TC-переривань (повних обертів кільця), веде клей;
 *   ndtr  — регістр NDTR каналу, рахує ВНИЗ (байтів у поточному крузі =
 *           size − ndtr; ndtr==0 — мить перед автоперезарядкою = повний
 *           круг, формула це дає без спецвипадку).
 * Абсолютна позиція запису wr = wraps·size + (size − ndtr).
 *
 * Дві гонки, обидві приборкані:
 *   • рваний знімок (TC між читаннями wraps і ndtr) — обов'язок клею:
 *     double-read wraps довкола ndtr, пара приймається лише при збігу;
 *   • IRQ-латентність (NDTR вже перезаряджено, wraps++ ще в черзі NVIC —
 *     позиція «стрибає назад» на цілий круг) — гасить монотонний clamp
 *     wr_seen: видимість продюсера ніколи не задкує, байти просто
 *     проявляються на мить пізніше.
 *
 * Переповнення (продюсер об'їхав консьюмера) = старі клітини вже переписані
 * й досі переписуються — читати рване нечесно: скидаємо все, рахуємо подію.
 * Лічильники абсолютні (uint32, переживають wrap через signed-діф).
 *
 * One-Home: Queen firmware та host-тести (test_uart_rx_ring.c) компілюють
 * цей самий код. Канон: 03_02 §4 + 00_07 FW.3.
 */
#ifndef SILKEN_UART_RX_RING_H
#define SILKEN_UART_RX_RING_H

#include <stdint.h>

typedef struct {
    uint8_t  *buf;       /* DMA-мішень; пам'яттю володіє викликач */
    uint16_t  size;
    uint32_t  rd;        /* спожито байтів від старту DMA (абсолютний) */
    uint32_t  wr_seen;   /* монотонна видимість продюсера (абсолютна) */
    uint32_t  overruns;  /* скільки разів кільце нас об'їхало (дані втрачено) */
} UartRxRing;

static inline void Uart_Ring_Init(UartRxRing *r, uint8_t *buf, uint16_t size)
{
    r->buf      = buf;
    r->size     = size;
    r->rd       = 0u;
    r->wr_seen  = 0u;
    r->overruns = 0u;
}

/* Знімок продюсера → оновлена видимість; повертає к-ть доступних байтів.
 * Консистентність пари (wraps, ndtr) — обов'язок викликача (див. шапку). */
static inline uint32_t Uart_Ring_Advance(UartRxRing *r, uint32_t wraps, uint16_t ndtr)
{
    uint32_t wr = wraps * (uint32_t)r->size +
                  ((uint32_t)r->size - (uint32_t)ndtr);

    /* signed-діф: коректно і при uint32-переповненні абсолютних лічильників */
    if ((int32_t)(wr - r->wr_seen) > 0) r->wr_seen = wr;

    /* Строго БІЛЬШЕ size: рівно-повне кільце ще читабельне (продюсер у
     * клітину rd ще не писав); межовий байт-у-гонці — клас C, bench. */
    if (r->wr_seen - r->rd > (uint32_t)r->size) {
        r->overruns++;
        r->rd = r->wr_seen;
    }
    return r->wr_seen - r->rd;
}

/* 1 = байт знятий, 0 = порожньо (станом на останній Advance). */
static inline int Uart_Ring_Pop(UartRxRing *r, uint8_t *out)
{
    if (r->rd == r->wr_seen) return 0;
    *out = r->buf[r->rd % (uint32_t)r->size];
    r->rd++;
    return 1;
}

#endif /* SILKEN_UART_RX_RING_H */
