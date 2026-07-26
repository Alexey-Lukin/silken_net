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
 *       рівно сторінки 122-127 (Flash-KV 122-123 · identity 124 · KOTA/KEYB
 *       125 · OTA-contract 126 · Queen-UID 127) — усе, що пише HAL_FLASH
 *   #2  SRAM 64K  RW+XN — NX-stack/heap/data цілком (чесно за будь-якого
 *       майбутнього .ld: стек всередині 64K)
 * Периферія/System — фонова мапа (PRIVDEFENA=1, код повністю privileged).
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

/* Таблиця трьох регіонів — єдине джерело для Apply обох прошивок. */
static inline void Mpu_Build_Region_Table(MpuRegionWord out[3])
{
    out[0].rbar = Mpu_Rbar(SEC21_MPU_FLASH_BASE, 0u);
    out[0].rasr = Mpu_Rasr(0u, MPU_AP_RO,      0u,                 SEC21_MPU_FLASH_LOG2);
    out[1].rbar = Mpu_Rbar(SEC21_MPU_TAIL_BASE, 1u);
    out[1].rasr = Mpu_Rasr(1u, MPU_AP_PRIV_RW, SEC21_MPU_TAIL_SRD, SEC21_MPU_TAIL_LOG2);
    out[2].rbar = Mpu_Rbar(SEC21_MPU_SRAM_BASE, 2u);
    out[2].rasr = Mpu_Rasr(1u, MPU_AP_PRIV_RW, 0u,                 SEC21_MPU_SRAM_LOG2);
}

/* 1 = Flash-адреса CPU-writable під цією розкладкою (живий subregion
 * TAIL-вікна). Host-тест жене крізь неї ВСІ сторінки: 122-127 мусять бути
 * writable (Flash-KV/ключі/contract/UID), 0-121 — ні. */
static inline int Mpu_Flash_Addr_Writable(uint32_t addr)
{
    uint32_t tail_size = 1u << SEC21_MPU_TAIL_LOG2;
    if (addr < SEC21_MPU_TAIL_BASE || addr >= SEC21_MPU_TAIL_BASE + tail_size)
        return 0;
    uint32_t subregion = (addr - SEC21_MPU_TAIL_BASE) / (tail_size / 8u);
    return !((SEC21_MPU_TAIL_SRD >> subregion) & 1u);
}

#endif /* SILKEN_MPU_REGIONS_H */
