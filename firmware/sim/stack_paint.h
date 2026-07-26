// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * stack_paint.h — [FW.55/FW.4] спільний paint/scan стек-вотермарки для
 * bare-metal ніг (QEMU mps2-an386 + WLE5 bench).
 *
 * Вікно під SP фарбується патерном, після прогону сканується знизу:
 * перше не-патерн слово = найглибший дотик. One-Home: ті самі функції
 * у всіх ARM-main'ах (logmel_main / qemu_m4 main / wle5_bench main) —
 * розмір вікна кожна нога задає сама (на WLE5 він обмежений резервом
 * лінкер-карти, на mps2 — щедрий).
 */
#ifndef SILKEN_STACK_PAINT_H
#define SILKEN_STACK_PAINT_H

#include <stdint.h>

#define STACK_PAINT_PATTERN 0xC0FFEE55u

__attribute__((noinline))
// cppcheck-suppress constParameterPointer // фарбування йде ЧЕРЕЗ похідний від sp_ref вказівник
static void Stack_Paint(uint32_t *sp_ref, uint32_t words)
{
    /* Зупиняємось під власним живим кадром — інакше зафарбували б свою
     * адресу повернення. Незафарбований хвостик угорі вікна нічого не
     * краде: глибокий слід вимірюваного коду лежить значно нижче. */
    const uint32_t *own = (const uint32_t *)__builtin_frame_address(0);
    for (uint32_t *p = sp_ref - words; p < own - 8; p++)
        *p = STACK_PAINT_PATTERN;
}

__attribute__((noinline))
static uint32_t Stack_Highwater(const uint32_t *sp_ref, uint32_t words)
{
    /* Скан знизу: перше не-патерн слово = найглибший дотик. */
    const uint32_t *p = sp_ref - words;
    while (p < sp_ref && *p == STACK_PAINT_PATTERN) p++;
    return (uint32_t)(sp_ref - p) * 4u;
}

#endif /* SILKEN_STACK_PAINT_H */
