/*
 * stack_canary.h — [SEC.21] сів вартової канарки: цінність guard'а рівно
 *                  така, наскільки він непередбачуваний.
 *
 * Навіщо: -fstack-protector-strong (arm-none-eabi.cmake) ставить канарку на
 * attacker-reachable парсери (LoRa-RX / AT-токенайзер жують untrusted байти
 * в сирому C ДО MIC-чеку), але newlib'ів __stack_chk_init ніхто не кличе →
 * __stack_chk_guard живе нуль-ініціалізованим у .bss: канарка = 0x00000000,
 * найпередбачуваніше значення з можливих. Смеш, що пише нулі, пройшов би повз
 * варту мовчки.
 *
 * Як: кожен boot сіє guard з HRNG (теплового шуму кремнію); відмова HRNG →
 * подана викликачем ентропія (tick ⊕ адреса кадру); повна тиша → вшита
 * константа-межа. Інваріант I-CG: guard ніколи не нуль. Молодший байт
 * гаситься в 0x00 — NUL-термінатор обриває str-сімейство переписів ДО
 * канарки (glibc-практика; binary-memcpy переписам байдуже, їх ловить
 * сама випадковість).
 *
 * One-Home: тут ЛИШЕ виведення значення (pure, host-tested). Визначення
 * __stack_chk_guard / __stack_chk_fail — платформні, у кожному main.c
 * (Soldier лишає tamper-слід у DR0, Queen — reset-only).
 * Канон: 03_05 §9 + 00_07 SEC.21.
 */
#ifndef SILKEN_STACK_CANARY_H
#define SILKEN_STACK_CANARY_H

#include <stdint.h>

/* Остання межа I-CG: ні HRNG, ні ентропії викликача — guard усе одно
 * не нуль і не лінкерів дефолт. */
#define CANARY_GUARD_LAST_RESORT 0xA5C3A500u

static inline uint32_t Canary_Guard_Derive(uint32_t hrng_word, uint32_t fallback_entropy)
{
    uint32_t g = (hrng_word != 0u) ? hrng_word : fallback_entropy;
    g &= ~0xFFu; /* NUL-термінатор у молодшому байті */
    if (g == 0u) g = CANARY_GUARD_LAST_RESORT;
    return g;
}

#endif /* SILKEN_STACK_CANARY_H */
