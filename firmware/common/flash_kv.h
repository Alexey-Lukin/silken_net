/*
 * flash_kv.h — [ARCH.28 шлях A] журнальний key-value у Flash STM32WLE5JC.
 *
 * Навіщо: RTC Backup (DR0..DR19) повний — нова persist-фіча йде сюди
 * (FW.54 wall-маркери/EMA при SRAM2-off, FW.20-S2 anti-storm bitmap).
 *
 * Дизайн (AN4894-патерн, адаптований під ECC цього кремнію):
 *   • Елемент = ОДИН doubleword (8 Б) — на WLE5 програмування dw атомарне
 *     щодо ECC, тож «порваного» запису не існує: або елемент є, або стоїть
 *     стертий 0xFF…FF. Розкладка: [value:32][key:8][flags:8][crc16:16].
 *   • Append-only: новіший запис того самого ключа перекриває старіший
 *     (останній валідний виграє). Без delete — наші ключі є постійним
 *     станом вузла, не кошиком.
 *   • Дві сторінки ping-pong. Заголовок сторінки = 2 dw: [SKV1|seq|crc] і
 *     [FINI|seq|crc]. FINI програмиться ПІСЛЯ переносу живих ключів —
 *     power-cut посеред compact лишає стару сторінку авторитетною.
 *   • Erase (~часта десятка мс) блокує шину → викликач питає
 *     FlashKv_NeedsCompact() і ущільнює у безпечній фазі циклу
 *     (після TX, перед STOP2), НЕ під LoRa RX-вікном.
 *
 * Wear-бюджет живе у канона ([`03_01 §2.3`]) — він зчеплений зі шкалою
 * delta_t (E.63): пишеш раз на цикл → сторінка стирається раз на
 * ~(елементів-на-сторінку) циклів.
 *
 * One-Home: firmware і host-тести компілюють цей самий код; залізні
 * примітиви ізольовано у FlashKvOps (host підставляє RAM + fault-injection,
 * MCU — HAL_FLASH_Program/Erase при HAL-фазі).
 *
 * Канон: 03_01 §2.3 + 00_07 FW.54 / FW.20-S2 / FW.49.
 */
#ifndef SILKEN_FLASH_KV_H
#define SILKEN_FLASH_KV_H

#include <stdint.h>

/* Залізні примітиви. byte_off — зсув від бази KV-регіону, кратний 8.
 * program/erase: 1 = успіх, 0 = відмова (host-тести симулюють power-cut). */
typedef struct {
    uint64_t (*read_dw)(void *io, uint32_t byte_off);
    int      (*program_dw)(void *io, uint32_t byte_off, uint64_t v);
    int      (*erase_page)(void *io, uint8_t page); /* 0 або 1 */
} FlashKvOps;

typedef struct {
    const FlashKvOps *ops;
    void             *io;
    uint16_t          page_dws;  /* dw на сторінку (2 КБ → 256) */
    uint8_t           active;    /* 0/1 */
    uint16_t          write_idx; /* перший вільний dw-індекс активної */
    uint16_t          seq;       /* erase-покоління активної */
} FlashKv;

/* Ключі: 0x01..0xFE. 0xFF = стертий флеш, 0x00 — зарезервовано. */
#define FLASH_KV_KEY_MIN 0x01u
#define FLASH_KV_KEY_MAX 0xFEu

/* Повертають 1 = успіх / знайдено; 0 = відмова / нема. */
int      FlashKv_Mount(FlashKv *kv, const FlashKvOps *ops, void *io, uint16_t page_dws);
int      FlashKv_Get32(const FlashKv *kv, uint8_t key, uint32_t *out);
int      FlashKv_Put32(FlashKv *kv, uint8_t key, uint32_t val);
int      FlashKv_Compact(FlashKv *kv);
uint16_t FlashKv_FreeSlots(const FlashKv *kv);

/* 1 = час ущільнюватись (вільних слотів ≤ margin). Викликач обирає фазу. */
static inline int FlashKv_NeedsCompact(const FlashKv *kv, uint16_t margin_dws)
{
    return FlashKv_FreeSlots(kv) <= margin_dws;
}

#endif /* SILKEN_FLASH_KV_H */
