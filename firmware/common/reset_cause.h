// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * reset_cause.h — [FW.59] Чому вузол перезавантажився: RCC_CSR → 3-бітний код.
 *
 * One-Home: цей самий декодер компілюють і прошивка Королеви, і host-тести
 * (патерн tx_defer.h / wall_time.h) — копії в тесті не існує за побудовою.
 * HAL тут немає: викликач подає СИРЕ значення `RCC->CSR` і прапорець
 * «маркер HardFault цілий», а весь присуд робиться арифметикою.
 *
 * ⚠️ RDP замикає SWD за дизайном (SEC.2), а флот planetary-remote — тож
 * ДРІТ є єдиним діагностичним каналом. Доти він ніс НУЛЬ сигналу «чому
 * вузол ребутнув», і тихий crash-loop (битий OTA / HAL-edge / brownout-
 * storm) був невидимий, поки дерево не згасне. Канон: 03_02 §7.
 *
 * 🔴 Чому SFTRSTF НЕ достатньо для HardFault: наш `HardFault_Handler`
 * виходить через `NVIC_SystemReset()`, тобто в кремнії лишає рівно той
 * самий SFTRSTF, що й штатний ребут по OTA чи команді. Розрізняє їх лише
 * маркер у RAM, що переживає ТЕПЛИЙ ресет (.noinit). Тому декодер бере
 * маркер КОН'ЮНКТИВНО з SFTRSTF: несвіжий маркер після холодного старту
 * (RAM не гарантовано чиста) не може підняти хибний HardFault.
 *
 * ⚠️ ОГОЛОШЕНА СТЕЛЯ, і вона не косметична: якщо лінкер-скрипт не винесе
 * `.noinit` за межі зони обнулення (board-freeze .ioc — 👤 bench), маркер
 * читатиметься як несвіжий і HardFault деградує у `SOFTWARE`. Деградація
 * ЧЕСНА (втрачаємо розрізнення, не набуваємо брехні) — але вона мовчазна,
 * і жоден наш гейт її не бачить: ARM-джоба збирає glue як OBJECT-бібліотеку
 * (compile-only, без лінкування), а host-сюїта лінкера не має взагалі.
 * Верифікація — приладом на стенді, ніколи зеленим CI (той самий присуд,
 * що для тіла MX_RTC_Init, FW.49).
 */

#ifndef SILKEN_RESET_CAUSE_H
#define SILKEN_RESET_CAUSE_H

#include <stdint.h>

/* ── Коди причини (рівно 3 біти: 0..7, усі вісім зайняті) ──────────────
 * 0 є СЕНТИНЕЛОМ «не повідомлено», а не «холодний старт»: усі історичні
 * рядки пульсу несуть нулі в цьому полі, тож будь-яке інше призначення
 * нуля заднім числом приписало б їм причину, якої ніхто не міряв. */
#define SILKEN_RESET_UNKNOWN    0u  /* прапорці не читались / прошивка < FW.59 */
#define SILKEN_RESET_POWER_ON   1u  /* BOR/POR/PDR — холодний старт або brownout */
#define SILKEN_RESET_PIN        2u  /* зовнішній NRST без BOR */
#define SILKEN_RESET_SOFTWARE   3u  /* NVIC_SystemReset (OTA-apply, CMD, canary) або OBL */
#define SILKEN_RESET_IWDG       4u  /* незалежний пес — main-loop завис (26.6 с) */
#define SILKEN_RESET_WWDG       5u  /* віконний пес — у нас не вмикається, код зарезервовано */
#define SILKEN_RESET_HARDFAULT  6u  /* наш .noinit-маркер разом із SFTRSTF */
#define SILKEN_RESET_LOW_POWER  7u  /* нелегальний вхід у low-power */

#define SILKEN_RESET_CAUSE_MAX  7u

/* ── Дзеркало RCC_CSR (RM0461 §6.4.29, STM32WLE5) ──────────────────────
 * Тримається тут, щоб заголовок лишався HAL-free й компілювався в host-
 * тестах. Дзеркало НЕ на слово: `queen/main.c` пінить кожну маску
 * `_Static_assert`-ом проти CMSIS-константи, і ARM-джоба це компілює —
 * тобто розсинхрон із кремнієм фізично не доїде до стенда. */
#define SILKEN_RCC_CSR_OBLRSTF   (1UL << 25)
#define SILKEN_RCC_CSR_PINRSTF   (1UL << 26)
#define SILKEN_RCC_CSR_BORRSTF   (1UL << 27)
#define SILKEN_RCC_CSR_SFTRSTF   (1UL << 28)
#define SILKEN_RCC_CSR_IWDGRSTF  (1UL << 29)
#define SILKEN_RCC_CSR_WWDGRSTF  (1UL << 30)
#define SILKEN_RCC_CSR_LPWRRSTF  (1UL << 31)

/* Магія маркера HardFault у .noinit — довільна, але НЕ 0 і НЕ 0xFFFFFFFF:
 * саме ці два значення дає незініціалізована RAM найчастіше. "HFLT". */
#define SILKEN_RESET_FAULT_MAGIC 0x48464C54UL

/*
 * Атрибут секції, що переживає теплий ресет. Mach-O вимагає пару
 * «сегмент,секція», тож голий `.noinit` там нелегальний — а `firmware/.clangd`
 * СВІДОМО парсить прошивку host-таргетом (там записано чому). Без цього
 * розгалуження редактор носив би вічну червону риску на файлі, який ARM-лейн
 * компілює бездоганно, і вона привчала б гортати діагностику цього файлу.
 * ⚠️ Ціна названа: на host-таргеті маркер лягає у `.bss` і теплого ресету не
 * переживе. Це нікого не ламає рівно тому, що ЖОДЕН host-TU його не компілює
 * (host-сюїта дзеркалить логіку через цей заголовок, а не через queen/main.c) —
 * тобто гілка є мовчанням для парсера, а не другою поведінкою.
 */
#if defined(__MACH__)
#define SILKEN_NOINIT
#else
#define SILKEN_NOINIT __attribute__((section(".noinit")))
#endif

/*
 * Декодер. `csr` — сире RCC->CSR ДО очищення прапорців; `fault_marker` —
 * 1, якщо .noinit-маркер ніс живу магію (викликач її вже погасив).
 *
 * Порядок перевірок — від найспецифічнішого до найзагальнішого, і він
 * несучий: прапорці RCC_CSR НАКОПИЧУЮТЬСЯ до RMVF, а внутрішній ресет
 * (пес, софт) на цьому сімействі підтягує ще й PINRSTF. Тож перевірка
 * PIN раніше за IWDG перетворила б кожен укус пса на «хтось натиснув
 * кнопку» — саме той клас підміни, що робить діагностику гіршою за її
 * відсутність.
 */
static inline uint8_t Silken_Reset_Cause_Decode(uint32_t csr, uint8_t fault_marker)
{
    if (fault_marker && (csr & SILKEN_RCC_CSR_SFTRSTF)) return SILKEN_RESET_HARDFAULT;
    if (csr & SILKEN_RCC_CSR_LPWRRSTF)                  return SILKEN_RESET_LOW_POWER;
    if (csr & SILKEN_RCC_CSR_WWDGRSTF)                  return SILKEN_RESET_WWDG;
    if (csr & SILKEN_RCC_CSR_IWDGRSTF)                  return SILKEN_RESET_IWDG;
    if (csr & SILKEN_RCC_CSR_SFTRSTF)                   return SILKEN_RESET_SOFTWARE;
    /* OBL — перезавантаження option-байтів: подія свідомої переконфігурації
     * (прошивання, зміна RDP), тому ділить кошик із SOFTWARE, а не заводить
     * власний код. Вісім кодів зайнято повністю; розкол — при wire-ревізії. */
    if (csr & SILKEN_RCC_CSR_OBLRSTF)                   return SILKEN_RESET_SOFTWARE;
    if (csr & SILKEN_RCC_CSR_BORRSTF)                   return SILKEN_RESET_POWER_ON;
    if (csr & SILKEN_RCC_CSR_PINRSTF)                   return SILKEN_RESET_PIN;
    return SILKEN_RESET_UNKNOWN;
}

/*
 * Чи є причина збоєм ПРОШИВКИ (на відміну від штатного чи зовнішнього
 * ребута). Vendor-attributable: пес і HardFault означають, що завис або
 * упав НАШ код; live-lock у low-power — так само наша конфігурація.
 * Живий споживач — бекенд (GatewayTelemetryLog#reset_fault?); тут форма
 * тримається поруч із кодами, щоб два боки не розійшлись у визначенні.
 */
static inline uint8_t Silken_Reset_Cause_Is_Fault(uint8_t cause)
{
    return (uint8_t)(cause == SILKEN_RESET_IWDG ||
                     cause == SILKEN_RESET_WWDG ||
                     cause == SILKEN_RESET_HARDFAULT ||
                     cause == SILKEN_RESET_LOW_POWER);
}

#endif /* SILKEN_RESET_CAUSE_H */
