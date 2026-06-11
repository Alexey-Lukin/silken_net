/*
 * startup.c — [FW.55] мінімальний bare-metal старт для STM32WLE5JC (bench).
 *
 * На відміну від QEMU-ноги (образ у ZBT, VMA==LMA, копія не потрібна) тут
 * справжній кремній: вектори @ 0x08000000, .data копіюється flash→SRAM,
 * .bss зануляється. VTOR ставимо явно (boot-alias 0x0 і так мапить flash,
 * але хай буде чесно). Clock/UART bring-up — Board_Init у syscalls.c.
 *
 * FPU не вмикаємо (CPACR не чіпаємо) — на WLE5 його просто НЕМАЄ: збірка
 * -mfloat-abi=soft, той самий __aeabi_* шлях, що довела QEMU-нога (§12.4).
 */
#include <stdint.h>

extern uint32_t __bss_start__, __bss_end__;
extern uint32_t __data_start__, __data_end__, __data_load__;
extern uint32_t __stack_top__;

int main(void);

#define SCB_VTOR (*(volatile uint32_t *)0xE000ED08u)

void Reset_Handler(void)
{
    SCB_VTOR = 0x08000000u;

    const uint32_t *src = &__data_load__;
    // cppcheck-suppress comparePointers // лінкерні символи — межі ОДНОГО .data
    for (uint32_t *p = &__data_start__; p < &__data_end__; p++) *p = *src++;
    // cppcheck-suppress comparePointers // лінкерні символи — межі ОДНОГО .bss
    for (uint32_t *p = &__bss_start__; p < &__bss_end__; p++) *p = 0u;

    (void)main();
    for (;;) { } /* main — нескінченний цикл раундів; це страховка */
}

static void Hang_Handler(void)
{
    /* Фолт на кремнії — діагноз сам по собі: сирий маркер у LPUART і стоп.
     * Semihosting'а без дебагера нема — скрипт 05_parity_dump.py побачить
     * ABORT (або тишу без COMPLETE) і дасть чесний вердикт. */
    extern void Lpuart1_Puts_Raw(const char *s);
    Lpuart1_Puts_Raw("PARITY-ABORT fault\n");
    for (;;) { }
}

__attribute__((used, section(".isr_vector")))
static const void *const vectors[16] = {
    &__stack_top__,        /* initial SP */
    (void *)Reset_Handler, /* Reset */
    (void *)Hang_Handler,  /* NMI */
    (void *)Hang_Handler,  /* HardFault */
    (void *)Hang_Handler,  /* MemManage */
    (void *)Hang_Handler,  /* BusFault */
    (void *)Hang_Handler,  /* UsageFault */
    0, 0, 0, 0,
    (void *)Hang_Handler,  /* SVCall */
    (void *)Hang_Handler,  /* DebugMon */
    0,
    (void *)Hang_Handler,  /* PendSV */
    (void *)Hang_Handler,  /* SysTick */
};
