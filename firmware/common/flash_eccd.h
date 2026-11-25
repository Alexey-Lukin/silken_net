// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * flash_eccd.h — [FW.70 · ARCH.28] нечитабельний dw внутрішньої Flash WL: NMI → 0 у перевіреному читанні.
 *
 * HAL-половина (CMSIS FLASH, бар'єри ядра): включає ЛИШЕ main.c образу — Солдата чи
 * Королеви — і рівно один раз, бо заголовок визначає вектор NMI_Handler. Host-тести його не
 * компілюють; їхня половина — контракт «0 = нечитабельне» у тестах кожного формату.
 *
 * Чому. Dw, який скид чи втрата живлення обірвали посеред програмування чи стирання сторінки,
 * може читатись стертим, сміттям (ECC узгоджений або з однією виправленою помилкою) — або з
 * ECC double error: FLASH_ECCR.ECCD і NMI. Вендорний Default_Handler (startup_stm32wle5xx.s) — вічна
 * петля, тож одне таке читання на монтуванні Flash-KV чи журналу логера зациклювало б
 * старт до укусу пса, і так на кожному наступному старті. Первинка класу — порт X-CUBE-EEPROM
 * 3.0.0 для STM32WL: EE_Init спершу перечитує кожен рядок своїх сторінок, «to delete
 * corrupted lines detectable through NMI», а його NMI_Handler на ECCD гасить прапорець і
 * повертається. RM0461 не прочитано (st.com машинним каналом недосяжний): які дані віддає
 * ECCD-читання, коли саме приходить NMI і чи кешується рядок із помилкою — питання стенду.
 *
 * Форма. Повертається обробник ЛИШЕ під час перевіреного читання (silken_flash_reading): гасить
 * ECCD, ставить прапорець — і читання, що вже віддало сміття, повертає замість нього 0. Саме
 * читання кличуть лише з потоку, не з ISR: воно не реентерабельне, а вікно приписує собі будь-який
 * ECCD (ADDR_ECC обробник не звіряє — без RM0461 одиниця поля невідома).
 * Поза перевіреним читанням (сирий вказівник, вибірка інструкції) і для інших джерел NMI —
 * петля до пса, як доти: повернення там дало б мовчазне сміття замість гучної петлі. Інше
 * джерело NMI У ВІКНІ обробник не гасить і повертається (CSS у дереві не ввімкнено).
 * Silken_Flash_Read_Dw читає dw двома 32-бітними словами (не ldrd: питання рестарту
 * інструкції посеред пари слів не виникає), після DSB+ISB сам опитує FLASH->ECCR.ECCD і,
 * якщо прапорець стоїть, а обробник ще не прийшов, чекає його (обмежено) — тож запізнілий NMI
 * не губиться й не лягає на наступне читання. Нуль не є ні записом, ні стертим у жодному з
 * форматів, що читають через нього (logger_journal.h — тип 0 не пишеться; flash_kv.c —
 * прапорці 0 ≠ 0xA5 і магія 0; перевірка RITE контракту; queen/ota_sha_guard.h — магія 0):
 * монтування його пропускає, курсор запису поверх нього не програмує, дамп журналу друкує
 * «#X,0000000000000000». Кеш даних Flash (DATA_CACHE_ENABLE у hal_conf) на ECCD скидається:
 * рядок зі сміттям, якщо ліг у кеш, повторне читання віддало б уже без NMI. Два лічильники
 * читає стенд через SWD (адреси дає nm образу): silken_flash_eccd_hits — нечитабельних читань,
 * silken_flash_eccd_nmi — повернень обробника; hits > nmi — NMI не встиг, і ECCD погасило саме
 * читання.
 *
 * Стелі, названі вголос:
 *   · порваний dw, що читається стертим, курсор запису бере як стертий і програмує поверх
 *     частково заряджених комірок; порваний dw, що читається сміттям без NMI, ловить лише
 *     формат — crc16 у Flash-KV, SHA в ota_sha_guard; у журналі логера CRC немає, і такий dw
 *     ляже в дамп виміром чи якорем зі зсунутими бітами (один dw на обірване програмування, а
 *     обірване стирання лишає таких на всю сторінку — напівстертий заголовок журналу без
 *     CRC може змонтуватись найновішим: нога 00_07 FW.70);
 *   · сирими лишились: VM mruby читає тіло контракту на місці — над повним RITE тіло ціле,
 *     лише якщо обірвано програмування (magic-last; RITE над порваною старшою половиною dw0
 *     дає VM_ERROR, і за три поспіль контракт стирається — SEC.20); обірване СТИРАННЯ сторінки
 *     контракту лишає RITE над напівстертим тілом, і ECCD у сирому читанні VM, як і доти,
 *     зациклює старт до перепрошивки (нога 00_07 SEC.20); заводські сторінки 124 · 125 · 127 Солдата, ключі й UID
 *     Королеви — їх пише лише завод, і ECCD там, як і доти, зациклює старт;
 *   · NMI, що прийшов після вичерпаного очікування (прапорець ECCD гаситься самим читанням)
 *     або чий ECCD ще не видно в регістрі на першому опитуванні, застає обробник поза читанням —
 *     петля до пса, як доти;
 *   · рядок фізично не нулиться (вендор нулить на фазі очищення): кожне читання знову дає
 *     NMI — кілька тактів на рідкісний dw, зате обробник не пише Flash.
 *
 * Канон: 03_01 §2.3 · 00_07 FW.70.
 */
#ifndef SILKEN_FLASH_ECCD_H
#define SILKEN_FLASH_ECCD_H

#include <stdint.h>

#include "stm32wlxx_hal.h"

/* Скільки опитувань FLASH->ECCR чекати обробника, коли ECCD уже стоїть, а NMI ще не прийшов. */
#define SILKEN_FLASH_ECCD_WAIT 1000u

/* RAM, група B (03_01 §2.3.1): прапорці живуть одне перевірене читання; лічильник — від старту. */
static volatile uint8_t  silken_flash_reading;
static volatile uint8_t  silken_flash_eccd;
static volatile uint32_t silken_flash_eccd_hits;
static volatile uint32_t silken_flash_eccd_nmi;

void NMI_Handler(void)
{
    if (silken_flash_reading != 0u) {
        if (READ_BIT(FLASH->ECCR, FLASH_ECCR_ECCD) != 0U) {
            silken_flash_eccd = 1u;
            silken_flash_eccd_nmi++;
            __HAL_FLASH_CLEAR_FLAG(FLASH_FLAG_ECCD);
        }
        return;
    }
    for (;;) { }
}

/* Прочитати dw внутрішньої Flash; 0 — якщо читання дало ECC double error. */
static inline uint64_t Silken_Flash_Read_Dw(uint32_t addr)
{
    if (READ_BIT(FLASH->ECCR, FLASH_ECCR_ECCD) != 0U) {
        __HAL_FLASH_CLEAR_FLAG(FLASH_FLAG_ECCD);     /* чужий слід не приписувати цьому читанню */
    }
    silken_flash_eccd = 0u;
    silken_flash_reading = 1u;
    uint32_t lo = *(const volatile uint32_t *)addr;
    uint32_t hi = *(const volatile uint32_t *)(addr + 4u);
    __DSB();
    __ISB();
    for (uint32_t n = 0u; n < SILKEN_FLASH_ECCD_WAIT && READ_BIT(FLASH->ECCR, FLASH_ECCR_ECCD) != 0U; n++) { }
    if (READ_BIT(FLASH->ECCR, FLASH_ECCR_ECCD) != 0U) {   /* NMI так і не прийшов */
        silken_flash_eccd = 1u;
        __HAL_FLASH_CLEAR_FLAG(FLASH_FLAG_ECCD);
    }
    silken_flash_reading = 0u;
    if (silken_flash_eccd == 0u) return ((uint64_t)hi << 32) | lo;
    silken_flash_eccd_hits++;
    if (READ_BIT(FLASH->ACR, FLASH_ACR_DCEN) != 0U) {
        __HAL_FLASH_DATA_CACHE_DISABLE();
        __HAL_FLASH_DATA_CACHE_RESET();
        __HAL_FLASH_DATA_CACHE_ENABLE();
    }
    return 0u;
}

#endif /* SILKEN_FLASH_ECCD_H */
