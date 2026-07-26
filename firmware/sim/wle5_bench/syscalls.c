// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * syscalls.c — [FW.55] newlib-ретаргет bench-ноги: РЕАЛЬНИЙ STM32WLE5JC.
 *
 * stdout → LPUART1 (PA2 AF8 → ST-LINK VCP на NUCLEO-WL55JC, UM2592),
 * 115200 8N1, TX-only polling. Куча — bump-алокатор від `end` з high-water
 * літописом: фіт у 64КБ SRAM — головне питання цієї ноги, і QEMU-нога міряє
 * ті самі числа наперед (той самий libmruby/newlib → послідовність malloc'ів
 * ідентична, водяний знак переноситься на кремній).
 *
 * Регістри — голий RM0461: parity-runner свідомо мінімальний і поза HAL,
 * щоб кремнієвий дамп не чекав CubeMX-vendoring (FW.46 👤).
 */
#include <stdint.h>
#include <errno.h>
#include <sys/stat.h>

#undef errno
extern int errno;

/* ── RM0461: RCC / GPIOA / LPUART1 ────────────────────────────────────── */
#define RCC_BASE      0x58000000u
#define RCC_CR        (*(volatile uint32_t *)(RCC_BASE + 0x00u))
#define RCC_CFGR      (*(volatile uint32_t *)(RCC_BASE + 0x08u))
#define RCC_AHB2ENR   (*(volatile uint32_t *)(RCC_BASE + 0x4Cu))
#define RCC_APB1ENR2  (*(volatile uint32_t *)(RCC_BASE + 0x5Cu))

#define RCC_CR_HSION       (1u << 8)
#define RCC_CR_HSIRDY      (1u << 10)
#define RCC_CFGR_SW_HSI16  0x1u
#define RCC_CFGR_SWS_HSI16 (0x1u << 2)

#define GPIOA_MODER   (*(volatile uint32_t *)0x48000000u)
#define GPIOA_AFRL    (*(volatile uint32_t *)0x48000020u)

#define LPUART1_BASE  0x40008000u
#define LPUART_CR1    (*(volatile uint32_t *)(LPUART1_BASE + 0x00u))
#define LPUART_BRR    (*(volatile uint32_t *)(LPUART1_BASE + 0x0Cu))
#define LPUART_ISR    (*(volatile uint32_t *)(LPUART1_BASE + 0x1Cu))
#define LPUART_TDR    (*(volatile uint32_t *)(LPUART1_BASE + 0x28u))

#define LPUART_CR1_UE  (1u << 0)
#define LPUART_CR1_TE  (1u << 3)
#define LPUART_ISR_TXE (1u << 7)

void Board_Init(void)
{
    /* HSI16 замість reset-MSI(4МГц): дамп за хвилини, не чверть години.
     * 16 МГц ≤ 18 МГц у Range1 → 0 WS, Flash ACR не чіпаємо (RM0461). */
    RCC_CR |= RCC_CR_HSION;
    while (!(RCC_CR & RCC_CR_HSIRDY)) { }
    RCC_CFGR = (RCC_CFGR & ~0x3u) | RCC_CFGR_SW_HSI16;
    while ((RCC_CFGR & 0xCu) != RCC_CFGR_SWS_HSI16) { }

    RCC_AHB2ENR  |= 1u; /* GPIOAEN */
    RCC_APB1ENR2 |= 1u; /* LPUART1EN (kernel clock = PCLK1 = 16 МГц, reset CCIPR) */

    /* PA2 → AF8 = LPUART1_TX (ST-LINK VCP, UM2592). RX не чіпаємо:
     * дамп — потік в один бік. */
    GPIOA_MODER = (GPIOA_MODER & ~(0x3u << 4)) | (0x2u << 4);
    GPIOA_AFRL  = (GPIOA_AFRL  & ~(0xFu << 8)) | (0x8u << 8);

    /* LPUART: BRR = 256·fck/baud = 256·16МГц/115200 → 35556 (RM0461). */
    LPUART_BRR = 35556u;
    LPUART_CR1 = LPUART_CR1_TE | LPUART_CR1_UE;
}

static void lpuart1_putc(char c)
{
    while (!(LPUART_ISR & LPUART_ISR_TXE)) { /* справжній дріт — чекаємо TXE */ }
    LPUART_TDR = (uint32_t)(uint8_t)c;
}

/* Сирий друк для фолт-хендлера (без printf/буферів). */
void Lpuart1_Puts_Raw(const char *s)
{
    while (*s) lpuart1_putc(*s++);
}

int _write(int fd, const char *buf, int len)
{
    (void)fd;
    for (int i = 0; i < len; i++) lpuart1_putc(buf[i]);
    return len;
}

/* Heap: від лінкерного `end` вгору до стек-резерву. One-Home: розмір резерву
 * живе у stm32wle5.ld абсолютним символом — його АДРЕСА і є числом. */
extern char end;
extern char __stack_top__;
extern char __stack_reserve__;

static char *brk_cur, *brk_max;

void *_sbrk(int incr)
{
    if (!brk_cur) brk_cur = &end;
    const char *limit = (const char *)((uintptr_t)&__stack_top__ - (uintptr_t)&__stack_reserve__);
    if (brk_cur + incr > limit) { errno = ENOMEM; return (void *)-1; }
    char *prev = brk_cur;
    brk_cur += incr;
    if (brk_cur > brk_max) brk_max = brk_cur;
    return prev;
}

/* Водяний знак кучі — головне число фіту; main друкує його після прогону. */
uint32_t Sbrk_Highwater(void)
{
    return brk_max ? (uint32_t)(brk_max - &end) : 0u;
}

/* На кремнії немає semihosting-виходу: exit = маркер + сон. Скрипт
 * ключується на маркери, не на завершення процесу. */
void _exit(int code)
{
    (void)code;
    Lpuart1_Puts_Raw("PARITY-EXIT\n");
    for (;;) { __asm__ volatile ("wfi"); }
}

/* Решта — заглушки рівно під потреби newlib/printf. */
int _close(int fd) { (void)fd; return -1; }
int _fstat(int fd, struct stat *st) { (void)fd; st->st_mode = S_IFCHR; return 0; }
int _isatty(int fd) { (void)fd; return 1; }
int _lseek(int fd, int off, int whence) { (void)fd; (void)off; (void)whence; return 0; }
int _read(int fd, char *buf, int len) { (void)fd; (void)buf; (void)len; return 0; }
int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }
int _getpid(void) { return 1; }
