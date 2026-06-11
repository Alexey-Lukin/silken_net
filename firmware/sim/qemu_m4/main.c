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

#include "../parity_core.h"
#include "../stack_paint.h"

void Uart0_Init(void);
uint32_t Sbrk_Highwater(void);

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
