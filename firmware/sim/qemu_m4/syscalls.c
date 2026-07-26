// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * syscalls.c — [FW.55] newlib-ретаргет для QEMU mps2-an386: stdout → CMSDK
 * APB UART0, куп(а) → bump-алокатор від `end` (mruby живе на malloc),
 * вихід — semihosting (bkpt 0xAB), інакше QEMU висів би до таймауту CI.
 */
#include <stdint.h>
#include <errno.h>
#include <sys/stat.h>

#undef errno
extern int errno;

/* CMSDK APB UART0 на mps2-an386 */
#define UART0_BASE  0x40004000u
#define UART0_DATA  (*(volatile uint32_t *)(UART0_BASE + 0x00u))
#define UART0_STATE (*(volatile uint32_t *)(UART0_BASE + 0x04u))
#define UART0_CTRL  (*(volatile uint32_t *)(UART0_BASE + 0x08u))
#define UART_STATE_TX_FULL 0x1u
#define UART_CTRL_TX_EN    0x1u

void Uart0_Init(void)
{
    UART0_CTRL = UART_CTRL_TX_EN;
}

static void uart0_putc(char c)
{
    while (UART0_STATE & UART_STATE_TX_FULL) { /* QEMU зливає миттєво */ }
    UART0_DATA = (uint32_t)(uint8_t)c;
}

/* Сирий друк для фолт-хендлера (без printf/буферів). */
void Uart0_Puts_Raw(const char *s)
{
    UART0_CTRL = UART_CTRL_TX_EN;
    while (*s) uart0_putc(*s++);
}

int _write(int fd, const char *buf, int len)
{
    (void)fd;
    for (int i = 0; i < len; i++) uart0_putc(buf[i]);
    return len;
}

/* Heap: від лінкерного `end` (база RAM-регіону) вгору, до стек-резерву. */
extern char end;            /* з mps2_an386.ld */
extern uint32_t __stack_top__;
#define STACK_RESERVE (64u * 1024u)

static char *brk_cur, *brk_max;

/* Сирий трас sbrk-викликів (діагностика фіт-гейта): без printf — він сам
 * ходить у malloc → рекурсія. Друк hex напряму в UART. */
static void sbrk_trace(int incr, const char *tot_from)
{
    static const char hexd[] = "0123456789ABCDEF";
    char line[28] = "SBRK ";
    char *w = line + 5;
    uint32_t v = (uint32_t)(incr < 0 ? -incr : incr);
    *w++ = incr < 0 ? '-' : '+';
    for (int s = 28; s >= 0; s -= 4) *w++ = hexd[(v >> s) & 0xFu];
    *w++ = ' '; *w++ = 't'; *w++ = '=';
    v = (uint32_t)(tot_from - &end);
    for (int s = 28; s >= 0; s -= 4) *w++ = hexd[(v >> s) & 0xFu];
    *w++ = '\n'; *w = '\0';
    Uart0_Puts_Raw(line);
}

void *_sbrk(int incr)
{
    if (!brk_cur) brk_cur = &end;
    const char *limit = (const char *)((uintptr_t)&__stack_top__ - STACK_RESERVE);
    if (brk_cur + incr > limit) { errno = ENOMEM; return (void *)-1; }
    char *prev = brk_cur;
    brk_cur += incr;
    if (brk_cur > brk_max) brk_max = brk_cur;
    sbrk_trace(incr, brk_cur);
    return prev;
}

/* Водяний знак кучі: той самий libmruby/newlib, що й на WLE5 → послідовність
 * malloc'ів ідентична, число ПЕРЕНОСИТЬСЯ на кремній (фіт у 64КБ SRAM гейтить
 * qemu_parity.sh проти бюджету wle5_bench-карти). */
uint32_t Sbrk_Highwater(void)
{
    return brk_max ? (uint32_t)(brk_max - &end) : 0u;
}

/* Semihosting ADP_Stopped_ApplicationExit — QEMU завершується (код 0;
 * вердикт parity дає diff дампів, не exit-код емулятора). */
void _exit(int code)
{
    (void)code;
    /* r0 = 0x18 ReportException, r1 = 0x20026 ApplicationExit */
    __asm__ volatile (
        "movs r0, #0x18      \n"
        "ldr  r1, =0x20026   \n"
        "bkpt 0xAB           \n"
        ::: "r0", "r1", "memory");
    for (;;) { }
}

/* Решта — заглушки рівно під потреби newlib/printf. */
int _close(int fd) { (void)fd; return -1; }
int _fstat(int fd, struct stat *st) { (void)fd; st->st_mode = S_IFCHR; return 0; }
int _isatty(int fd) { (void)fd; return 1; }
int _lseek(int fd, int off, int whence) { (void)fd; (void)off; (void)whence; return 0; }
int _read(int fd, char *buf, int len) { (void)fd; (void)buf; (void)len; return 0; }
int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }
int _getpid(void) { return 1; }
