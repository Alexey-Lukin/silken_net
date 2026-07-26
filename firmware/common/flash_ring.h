// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * flash_ring.h — [ARCH.35] sector-based ring телеметрії на SPI NOR W25Q32JV.
 *
 * Навіщо: CIFO EdgeCache (50 RAM-слотів) переповнюється за ~30 хв при
 * 100 Soldiers/Queen без uplink'а — евікшн мовчки губить телеметрію лісу.
 * Ring = overflow tier L1 (06_08 §1.2): спіл при евікшні/провалі flush'а,
 * drain FIFO при відновленні uplink'а.
 *
 * Дизайн (02_05 §2.1, уточнений на імплементації):
 *   • NOR не вміє 0→1 без erase, erase — цілим сектором 4 КБ → ring
 *     обертається ПО СЕКТОРАХ; повний ring → FIFO-drop найстарішого сектора.
 *   • Слот = 21-байтний wire-запис батча (DID:4 BE + |RSSI| + payload:16) —
 *     бітово той самий формат, що пакує Flush_Cache_To_Rails: спіл/дрейн
 *     не перекодовують.
 *   • In-band заголовок сектора замість RTC-покажчиків з ескізу: Queen не
 *     використовує жодного RTC DR, але покажчики у регістрах гинуть з VBAT
 *     і вміють розійтися зі вмістом флешу. Заголовок [magic|seq] + два
 *     NOR-бітмапи (used/consumed, програмуються 1→0 БЕЗ erase) роблять ring
 *     самоописовим: mount-scan відновлює head/tail/count після будь-якого
 *     знеструмлення. Ціна — 56 Б/сектор → 192 слоти/сектор (~197k загалом).
 *   • Порядок запису слота: спершу 21 байт запису, ПОТІМ used-біт —
 *     power-cut між ними лишає слот невидимим (не сміттям).
 *   • Consume (підтверджена доставка) = consumed-біт; drop-oldest =
 *     consume-all сектора — обидва durable без erase, mount не воскрешає.
 *
 * Розкладка сектора (4096 Б):
 *   [0..7]    hdr: magic u16 LE | rsv u16 | seq u32 LE (генерація erase'ів)
 *   [8..31]   used-бітмап    (192 біти; біт 0 = слот записано)
 *   [32..55]  consumed-бітмап (192 біти; біт 0 = слот доставлено/dropped)
 *   [56..4091] 192 × 21-байт слоти
 *   [4092..4095] запас
 *
 * One-Home: firmware і host-тести компілюють цей самий код; залізні
 * примітиви ізольовано у FlashRingOps (host — RAM-мок з NOR-семантикою
 * 1→0 + fault-injection power-cut'ів; MCU — SPI W25Q32 у queen/main.c,
 * gated ARCH35_RING_ENABLED). Канон: 02_05 §2.1 + 06_08 §1.2 + 00_07 ARCH.35.
 */
#ifndef SILKEN_FLASH_RING_H
#define SILKEN_FLASH_RING_H

#include <stdint.h>

/* Залізні примітиви. addr — байтовий зсув від бази ring-регіону.
 * program — NOR-семантика (лише 1→0). Повертають 1 = успіх. */
typedef struct {
    int (*read)(void *io, uint32_t addr, uint8_t *buf, uint32_t len);
    int (*program)(void *io, uint32_t addr, const uint8_t *buf, uint32_t len);
    int (*erase_sector)(void *io, uint16_t sector);
} FlashRingOps;

#define FLASH_RING_SECTOR_SIZE      4096u
#define FLASH_RING_RECORD_SIZE      21u   /* wire-запис батча (03_05 §5) */
#define FLASH_RING_SLOTS_PER_SECTOR 192u
#define FLASH_RING_HDR_OFF          0u
#define FLASH_RING_HDR_SIZE         8u
#define FLASH_RING_USED_OFF         8u
#define FLASH_RING_CONS_OFF         32u
#define FLASH_RING_BMP_BYTES        24u   /* 192 біти */
#define FLASH_RING_DATA_OFF         56u
#define FLASH_RING_MAGIC            0xA35Cu /* «ARCH.35 Cache» */

/* W25Q32JV: 4 МБ / 4 КБ = 1024 сектори. Host-тести передають менше,
 * щоб ганяти wrap швидко; це параметр mount'а, не компайл-константа. */
#define FLASH_RING_W25Q32_SECTORS   1024u

typedef struct {
    const FlashRingOps *ops;
    void               *io;
    uint16_t            n_sectors;
    uint16_t            head_sector; /* сектор, куди пишемо */
    uint16_t            head_slot;   /* наступний вільний слот head'а */
    uint16_t            tail_sector; /* найстаріший сектор з недоставленим */
    uint16_t            tail_slot;   /* перший недоставлений слот tail'а */
    uint32_t            head_seq;    /* seq head-сектора (генерації) */
    uint32_t            count;       /* used && !consumed записи */
    uint8_t             mounted;
} FlashRing;

/* Усі повертають 1 = успіх / знайдено; 0 = відмова (стан незмінний,
 * окрім чесно-часткових NOR-програмувань, які mount переживає). */
int      FlashRing_Mount(FlashRing *r, const FlashRingOps *ops, void *io,
                         uint16_t n_sectors);
int      FlashRing_Append(FlashRing *r, const uint8_t rec[FLASH_RING_RECORD_SIZE]);
/* idx — позиція від tail серед недоставлених (0 = найстаріший). */
int      FlashRing_Read_Tail(const FlashRing *r, uint32_t idx,
                             uint8_t out[FLASH_RING_RECORD_SIZE]);
/* Durable-підтвердження доставки n найстаріших записів (FIFO). */
int      FlashRing_Consume(FlashRing *r, uint32_t n);
uint32_t FlashRing_Count(const FlashRing *r);

#endif /* SILKEN_FLASH_RING_H */
