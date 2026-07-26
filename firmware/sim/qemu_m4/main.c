// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * main.c — [FW.55] QEMU-M4 нога parity-прогону (qemu-system-arm -M mps2-an386).
 *
 * Справжній Cortex-M4 код-шлях: той самий committed-байткод, той самий
 * minimal-gembox libmruby (SILKEN_ARM_BUILD), software-double __aeabi_* —
 * як на STM32WLE5JC. Друк — CMSDK UART0 (syscalls.c), вихід — semihosting.
 *
 * Build/run: firmware/scripts/qemu_parity.sh
 */
#include <stdio.h>
#include <stdint.h>

uint32_t Sbrk_Highwater(void);

/* Лічильний mrb-алокатор (діагностика фіт-гейта): об'єктний файл переважує
 * mrb_basic_alloc_func з archive (allocf.c). Міряє ЧИСТІ mruby-запити на
 * ARM-нозі (host-зонд показував +136Б/кейс — а sbrk ріс сторінками);
 * великі запити (≥4КБ ≈ heap-сторінка 5144Б) логуються поіменно. printf
 * тут безпечний: його malloc іде в newlib, не в цей allocf. */
#include <stdlib.h>
static size_t mrb_cur, mrb_peak;
void *mrb_basic_alloc_func(void *p, size_t size)
{
    if (size == 0) {
        if (p) { size_t *h = (size_t *)p - 2; mrb_cur -= h[0]; free(h); }
        return NULL;
    }
    if (size >= 4096)
        printf("MRB-BIG %lu (cur=%lu)\n", (unsigned long)size, (unsigned long)mrb_cur);
    if (p) {
        size_t *h = (size_t *)p - 2;
        size_t old = h[0];
        size_t *nh = realloc(h, size + 2 * sizeof(size_t));
        if (!nh) return NULL;
        nh[0] = size;
        mrb_cur += size - old;
        if (mrb_cur > mrb_peak) mrb_peak = mrb_cur;
        return nh + 2;
    }
    size_t *h = malloc(size + 2 * sizeof(size_t));
    if (!h) return NULL;
    h[0] = size;
    mrb_cur += size;
    if (mrb_cur > mrb_peak) mrb_peak = mrb_cur;
    return h + 2;
}

/* Зонд фаз пам'яті (open/irep/cases) — sbrk + чисті mruby-запити. */
#define PARITY_MEM_MARK(phase) \
    printf("PARITY-MEM %s=%lu mrb=%lu/%lu\n", phase, \
           (unsigned long)Sbrk_Highwater(), \
           (unsigned long)mrb_cur, (unsigned long)mrb_peak)

#include "../parity_core.h"
#include "../stack_paint.h"

void Uart0_Init(void);

/* Вікно фарбування: глибше за очікуваний слід mruby VM (C-рекурсія + printf). */
#define PAINT_WORDS (16u * 1024u / 4u)

int main(void)
{
    Uart0_Init();
    setvbuf(stdout, NULL, _IONBF, 0);

    uint32_t *sp_ref = (uint32_t *)__builtin_frame_address(0);
    Stack_Paint(sp_ref, PAINT_WORDS);
    int rc = Parity_Run();

    /* Числа фіту для WLE5-ноги (64КБ SRAM): qemu_parity.sh гейтить їх проти
     * бюджету wle5_bench-карти — «не влазить» ловиться в CI, не на bench. */
    printf("PARITY-STACK high-water=%lu\n",
           (unsigned long)Stack_Highwater(sp_ref, PAINT_WORDS));
    printf("PARITY-HEAP high-water=%lu\n", (unsigned long)Sbrk_Highwater());
    return rc;
}
