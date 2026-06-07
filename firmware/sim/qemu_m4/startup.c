/*
 * startup.c — [FW.55] мінімальний bare-metal старт для QEMU mps2-an386.
 *
 * M-profile: ядро на reset бере SP з vector[0], PC з vector[1] (VTOR=0x0,
 * наш .isr_vector лінкується в ORIGIN(CODE)=0x00000000 — ZBT SSRAM1 цієї
 * плати). .data має VMA==LMA (увесь образ живе в RAM-подібному ZBT) — копія
 * не потрібна, лише зануляємо .bss. exit(main()) замість goto: newlib
 * добуферовує stdout у cleanup'і перед semihosting-виходом.
 */
#include <stdint.h>
#include <stdlib.h>

extern uint32_t __bss_start__, __bss_end__, __stack_top__;

int  main(void);
void _exit(int code);

/* CPACR: доступ до CP10/CP11 (FPU). Hard-float ABI кладе double в d-реги —
 * без цього перший же VMOV дає UsageFault (саме так виглядав перший
 * CI-прогін: PARITY-ABORT fault). */
#define SCB_CPACR (*(volatile uint32_t *)0xE000ED88u)

void Reset_Handler(void)
{
    SCB_CPACR |= (0xFu << 20);
    __asm__ volatile ("dsb; isb" ::: "memory");

    // cppcheck-suppress comparePointers // лінкерні символи — межі ОДНОГО .bss
    for (uint32_t *p = &__bss_start__; p < &__bss_end__; p++) *p = 0u;
    exit(main());
}

static void Hang_Handler(void)
{
    /* Фолт у parity-прогоні — діагноз сам по собі; маркер летить через
     * сирий UART у syscalls.c, далі — вихід (інакше CI чекав би таймаут). */
    extern void Uart0_Puts_Raw(const char *s);
    Uart0_Puts_Raw("PARITY-ABORT fault\n");
    _exit(3);
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
