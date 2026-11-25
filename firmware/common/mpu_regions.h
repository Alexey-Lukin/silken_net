// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * mpu_regions.h — [SEC.21] MPU region-config: NX-stack + RO-code (draft).
 *
 * Навіщо: канарка ловить смеш ПІСЛЯ факту — MPU не дає йому статись кодом:
 * увесь SRAM eXecute-Never (shellcode у стеку/буфері не виконається) + Flash
 * read-only для CPU-store (перезапис .text/ключів даними — MemManage trap).
 *
 * Розкладка WLE5JC (Flash 256K @0x08000000 / SRAM 64K @0x20000000) — 3 регіони
 * з 8, SRD-трюк для не-power-of-2 хвоста:
 *   #0  Flash 256K  RO+X  — код/const; фон для хвоста
 *   #1  16K @0x0803C000  RW+XN, SRD=0b00000011 — subregions 0-1 (сторінки
 *       120-121, код) ВИМКНЕНІ → провалюються у RO-#0; живими лишаються
 *       рівно сторінки 122-127 (Flash-KV 122-123 · identity 124 · KPUB/KEYB
 *       125 · OTA-contract 126 · Queen-UID 127) — усе, що пише HAL_FLASH
 *   #2  SRAM 64K  RW+XN — NX-stack/heap/data цілком (чесно за будь-якого
 *       майбутнього .ld: стек всередині 64K)
 * Периферія/System — фонова мапа (PRIVDEFENA=1, код повністю privileged).
 * ⊕ [FW.70] Образ логера П3 на mini — друга розкладка регіону #1, лише для нього: журнал
 *   займає сторінки 104-121 (03_01 §2.3), тож вікно — 64K @0x08030000 (субрегіон = 8K =
 *   4 сторінки), SRD=0b00000011 → сторінки 96-103 провалюються в RO-#0, записувані рівно
 *   104-127. Плата вузла лишається на 122-127: там сторінки 104-121 можуть бути кодом, і
 *   RW+XN на них зробив би код невиконуваним. Вибір — аргумент Mpu_*_For, не макрос
 *   усередині заголовка: host-тест судить обидві розкладки в одному TU.
 * HFNMIENA=0: у HardFault/NMI MPU не діє — canary-handler пише TAMP без trap'а.
 *
 * One-Home: тут ЛИШЕ pure-математика слів RBAR/RASR (ARMv7-M PMSA, дзеркало
 * CMSIS armv7m_mpu.h — host не має CMSIS, тож рахуємо самі; біти звіряє
 * host-тест golden'ами). Сам запис у MPU-регістри (Silken_Mpu_Apply) — у
 * main.c за гейтом SEC21_MPU_ENABLED: компіляцію стереже hal_check_ccm,
 * АКТИВАЦІЯ bench-gated — QEMU mps2 MPU не моделює вірогідно, реальний
 * MemManage-trap доводиться лише на кремнії (00_07 SEC.21). TEX/C/B/S
 * консервативні (normal memory, WT) — фінальні атрибути = bench-tuning.
 *
 * ⚠️ ТІЛО `MemManage_Handler` у цьому репо НЕ ЖИВЕ — воно приходить із
 * board-freeze `.ioc` (CubeMX, 00_07 FW.46), як і тіла MX_-ініціалізаторів і
 * SystemClock_Config.
 * Тобто вмикати SEC21_MPU_ENABLED ДО board-freeze означає озброїти пастку, чий
 * обробник є weak-дефолтом CMSIS (вічна петля) — trap спрацює й вузол мовчки
 * зависне замість того, щоб лишити слід. Порядок несучий: board-freeze → тіло
 * обробника → аж тоді активація.
 *
 * Канон: 03_05 §9 + 03_01 §2.3 (Flash-хвіст) + 00_07 SEC.21.
 */
#ifndef SILKEN_MPU_REGIONS_H
#define SILKEN_MPU_REGIONS_H

#include <stdint.h>

/* ARMv7-M PMSA бітові поля (RM DDI0403E) — власні, без CMSIS (host-parity). */
#define MPU_RBAR_VALID_BIT      0x10u
#define MPU_RASR_ENABLE_BIT     0x01u
#define MPU_RASR_SIZE_SHIFT     1
#define MPU_RASR_SRD_SHIFT      8
#define MPU_RASR_B_SHIFT        16
#define MPU_RASR_C_SHIFT        17
#define MPU_RASR_S_SHIFT        18
#define MPU_RASR_TEX_SHIFT      19
#define MPU_RASR_AP_SHIFT       24
#define MPU_RASR_XN_SHIFT       28

#define MPU_AP_PRIV_RW          0x3u  /* full access                  */
#define MPU_AP_RO               0x6u  /* read-only (privileged теж)   */

/* WLE5JC freeze-contract мапа (03_01 §2.3 / 03_06 §2). */
#define SEC21_MPU_FLASH_BASE    0x08000000u
#define SEC21_MPU_FLASH_LOG2    18u   /* 256K */
#define SEC21_MPU_TAIL_BASE     0x0803C000u
#define SEC21_MPU_TAIL_LOG2     14u   /* 16K-вікно; subregion = 2K = 1 сторінка */
#define SEC21_MPU_TAIL_SRD      0x03u /* сторінки 120-121 → назад у RO-#0 */
#define SEC21_MPU_SRAM_BASE     0x20000000u
#define SEC21_MPU_SRAM_LOG2     16u   /* 64K */
#define SEC21_MPU_FLASH_TAIL_FIRST_RW_PAGE 122u
#define SEC21_MPU_FLASH_PAGE_SIZE          2048u
/* [FW.70] Розкладка образу логера (mini) — регіон #1 ширший; решта таблиці та сама. */
#define SEC21_MPU_LOGGER_TAIL_BASE         0x08030000u
#define SEC21_MPU_LOGGER_TAIL_LOG2         16u   /* 64K-вікно; subregion = 8K = 4 сторінки */
#define SEC21_MPU_LOGGER_TAIL_SRD          0x03u /* сторінки 96-103 → назад у RO-#0 */
#define SEC21_MPU_LOGGER_FIRST_RW_PAGE     104u

/* RBAR: базова адреса (вирівняна на розмір) | VALID | номер регіону. */
static inline uint32_t Mpu_Rbar(uint32_t base, uint32_t region)
{
    return base | MPU_RBAR_VALID_BIT | (region & 0xFu);
}

/* RASR: SIZE-поле = log2(size)-1; normal memory WT (TEX=0,C=1,B=0,S=0). */
static inline uint32_t Mpu_Rasr(uint32_t xn, uint32_t ap, uint32_t srd,
                                uint32_t size_log2)
{
    return (xn << MPU_RASR_XN_SHIFT) | (ap << MPU_RASR_AP_SHIFT) |
           (1u << MPU_RASR_C_SHIFT) | (srd << MPU_RASR_SRD_SHIFT) |
           ((size_log2 - 1u) << MPU_RASR_SIZE_SHIFT) | MPU_RASR_ENABLE_BIT;
}

typedef struct {
    uint32_t rbar;
    uint32_t rasr;
} MpuRegionWord;

/* Регіон #1 обраної розкладки: logger = 0 — плата вузла, 1 — образ логера (FW.70). */
static inline void mpu_tail(int logger, uint32_t *base, uint32_t *log2, uint32_t *srd)
{
    *base = logger ? SEC21_MPU_LOGGER_TAIL_BASE : SEC21_MPU_TAIL_BASE;
    *log2 = logger ? SEC21_MPU_LOGGER_TAIL_LOG2 : SEC21_MPU_TAIL_LOG2;
    *srd  = logger ? SEC21_MPU_LOGGER_TAIL_SRD  : SEC21_MPU_TAIL_SRD;
}

/* Таблиця трьох регіонів — єдине джерело для Apply обох прошивок. */
static inline void Mpu_Build_Region_Table_For(MpuRegionWord out[3], int logger)
{
    uint32_t base, log2, srd;
    mpu_tail(logger, &base, &log2, &srd);
    out[0].rbar = Mpu_Rbar(SEC21_MPU_FLASH_BASE, 0u);
    out[0].rasr = Mpu_Rasr(0u, MPU_AP_RO,      0u,  SEC21_MPU_FLASH_LOG2);
    out[1].rbar = Mpu_Rbar(base, 1u);
    out[1].rasr = Mpu_Rasr(1u, MPU_AP_PRIV_RW, srd, log2);
    out[2].rbar = Mpu_Rbar(SEC21_MPU_SRAM_BASE, 2u);
    out[2].rasr = Mpu_Rasr(1u, MPU_AP_PRIV_RW, 0u,  SEC21_MPU_SRAM_LOG2);
}

static inline void Mpu_Build_Region_Table(MpuRegionWord out[3])
{
    Mpu_Build_Region_Table_For(out, 0);
}

/* 1 = Flash-адреса CPU-writable під цією розкладкою (живий subregion
 * TAIL-вікна). Host-тест жене крізь неї ВСІ сторінки: у вузла 122-127 мусять бути
 * writable (Flash-KV/ключі/contract/UID), 0-121 — ні; у логера — 104-127 і 0-103. */
static inline int Mpu_Flash_Addr_Writable_For(uint32_t addr, int logger)
{
    uint32_t base, log2, srd;
    mpu_tail(logger, &base, &log2, &srd);
    uint32_t tail_size = 1u << log2;
    if (addr < base || addr >= base + tail_size)
        return 0;
    uint32_t subregion = (addr - base) / (tail_size / 8u);
    return !((srd >> subregion) & 1u);
}

static inline int Mpu_Flash_Addr_Writable(uint32_t addr)
{
    return Mpu_Flash_Addr_Writable_For(addr, 0);
}

#endif /* SILKEN_MPU_REGIONS_H */
