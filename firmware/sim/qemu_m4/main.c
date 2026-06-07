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

#include "../parity_core.h"

void Uart0_Init(void);

int main(void)
{
    Uart0_Init();
    setvbuf(stdout, NULL, _IONBF, 0);
    return Parity_Run();
}
