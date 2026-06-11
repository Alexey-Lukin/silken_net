/*
 * main.c — [FW.55] bench-нога parity-прогону: реальний STM32WLE5JC (клас C,
 * RUNBOOK 2.3). Той самий parity_core.h і той самий libmruby.a (soft-double
 * __aeabi_*), що довели byte-exact на QEMU — але тепер кремній: справжній
 * flash, справжній SRAM, справжнє ядро.
 *
 * Раунди нескінченні: PARITY-BEGIN → 64 зчеплені кейси → PARITY-COMPLETE →
 * heap/stack звіт → пауза → знову. Скрипт 05_parity_dump.py чіпляється за
 * будь-який BEGIN — жодної гри «хто перший: reset плати чи відкритий порт».
 *
 * Друк — LPUART1 PA2 → ST-LINK VCP NUCLEO-WL55JC, 115200 8N1.
 * Build: firmware/scripts/qemu_parity.sh (артефакт parity_wle5.elf);
 * flash: bench/00_flash.sh; дамп + вердикт: bench/05_parity_dump.py.
 */
#include <stdio.h>
#include <stdint.h>

#include "../parity_core.h"
#include "../stack_paint.h"

void Board_Init(void);
uint32_t Sbrk_Highwater(void);

/* Вікно під SP: усередині стек-резерву лінкер-карти (12К, stm32wle5.ld) —
 * нижче починається heap-ліміт _sbrk. */
#define PAINT_WORDS (11u * 1024u / 4u)

static void Pause_Between_Rounds(void)
{
    /* ~кілька секунд @ 16 МГц — щоб скрипту було зручно зачепитись за BEGIN. */
    for (volatile uint32_t i = 0; i < 16000000u; i++) { }
}

int main(void)
{
    Board_Init();
    setvbuf(stdout, NULL, _IONBF, 0);

    for (;;) {
        printf("PARITY-BEGIN wle5-bench\n");

        uint32_t *sp_ref = (uint32_t *)__builtin_frame_address(0);
        Stack_Paint(sp_ref, PAINT_WORDS);
        (void)Parity_Run(); /* VM-збій сам видний у дампі (PARITY-ABORT) */

        printf("PARITY-STACK high-water=%lu\n",
               (unsigned long)Stack_Highwater(sp_ref, PAINT_WORDS));
        printf("PARITY-HEAP high-water=%lu\n",
               (unsigned long)Sbrk_Highwater());

        Pause_Between_Rounds();
    }
}
