/*
 * flash_ring.c — [ARCH.35] sector-based ring на SPI NOR (дизайн — flash_ring.h).
 *
 * Інваріанти, на яких тримається power-cut-безпека:
 *   1. Слот видимий лише після used-біта (програмиться ПІСЛЯ запису даних).
 *   2. Доставка/дроп — consumed-біт (1→0, без erase) → durable, mount
 *      ніколи не воскрешає вже-підтверджене.
 *   3. Сирітський слот (power-cut між даними і used-бітом) НЕ перезаписується
 *      (NOR AND-ить байти) — Append tombstone'ить його (used+consumed), а
 *      прогулянки Read_Tail/Consume ходять по бітмапах і перестрибують.
 *   4. Erase сектора — тільки на вході head'а у нього; до того старі дані
 *      лежать неторкані (запас ретенції, не корупція).
 */
#include "flash_ring.h"

#include <string.h>

static uint32_t sector_base(const FlashRing *r, uint16_t sector)
{
    (void)r;
    return (uint32_t)sector * FLASH_RING_SECTOR_SIZE;
}

/* Біт slot'а у бітмапі: 0 = подія сталась (NOR: програмуємо 1→0). */
static int bitmap_bit_clear(const uint8_t *bmp, uint16_t slot)
{
    return (bmp[slot / 8u] & (uint8_t)(1u << (slot % 8u))) == 0u;
}

static int read_header(const FlashRing *r, uint16_t sector,
                       uint16_t *magic, uint32_t *seq)
{
    uint8_t hdr[FLASH_RING_HDR_SIZE];
    if (!r->ops->read(r->io, sector_base(r, sector) + FLASH_RING_HDR_OFF,
                      hdr, sizeof(hdr)))
        return 0;
    *magic = (uint16_t)hdr[0] | ((uint16_t)hdr[1] << 8);
    *seq   = (uint32_t)hdr[4] | ((uint32_t)hdr[5] << 8) |
             ((uint32_t)hdr[6] << 16) | ((uint32_t)hdr[7] << 24);
    return 1;
}

static int read_bitmaps(const FlashRing *r, uint16_t sector,
                        uint8_t used[FLASH_RING_BMP_BYTES],
                        uint8_t cons[FLASH_RING_BMP_BYTES])
{
    uint32_t base = sector_base(r, sector);
    if (!r->ops->read(r->io, base + FLASH_RING_USED_OFF, used, FLASH_RING_BMP_BYTES))
        return 0;
    return r->ops->read(r->io, base + FLASH_RING_CONS_OFF, cons, FLASH_RING_BMP_BYTES);
}

/* Недоставлені слоти сектора (used && !consumed). */
static uint32_t sector_pending(const uint8_t *used, const uint8_t *cons)
{
    uint32_t n = 0;
    for (uint16_t s = 0; s < FLASH_RING_SLOTS_PER_SECTOR; s++) {
        if (bitmap_bit_clear(used, s) && !bitmap_bit_clear(cons, s)) n++;
    }
    return n;
}

/* Програмування одного біта бітмапа: байт із єдиним нулем — NOR лишає
 * решту бітів неторканими (1 не перепрограмовується). */
static int program_bit(const FlashRing *r, uint16_t sector, uint32_t bmp_off,
                       uint16_t slot)
{
    uint8_t byte = (uint8_t)~(1u << (slot % 8u));
    return r->ops->program(r->io,
                           sector_base(r, sector) + bmp_off + slot / 8u,
                           &byte, 1u);
}

int FlashRing_Mount(FlashRing *r, const FlashRingOps *ops, void *io,
                    uint16_t n_sectors)
{
    if (!r || !ops || n_sectors < 2u) return 0;
    memset(r, 0, sizeof(*r));
    r->ops = ops;
    r->io = io;
    r->n_sectors = n_sectors;

    /* Прохід 1: знайти head (max seq) і max генерацію. */
    int      found = 0;
    uint32_t max_seq = 0;
    uint16_t head = 0;
    for (uint16_t s = 0; s < n_sectors; s++) {
        uint16_t magic; uint32_t seq;
        if (!read_header(r, s, &magic, &seq)) return 0;
        if (magic != FLASH_RING_MAGIC) continue;
        if (!found || seq > max_seq) { max_seq = seq; head = s; }
        found = 1;
    }

    if (!found) {
        /* Цілинний/стертий флеш: перший Append зробить erase+hdr. */
        r->mounted = 1;
        return 1;
    }

    r->head_sector = head;
    r->head_seq    = max_seq;

    /* Прохід 2: tail = валідний сектор із недоставленим і min seq;
     * count = сума недоставленого. */
    int      have_tail = 0;
    uint32_t min_seq = 0;
    uint16_t tail = head;
    for (uint16_t s = 0; s < n_sectors; s++) {
        uint16_t magic; uint32_t seq;
        if (!read_header(r, s, &magic, &seq)) return 0;
        if (magic != FLASH_RING_MAGIC) continue;
        uint8_t used[FLASH_RING_BMP_BYTES], cons[FLASH_RING_BMP_BYTES];
        if (!read_bitmaps(r, s, used, cons)) return 0;
        uint32_t pending = sector_pending(used, cons);
        r->count += pending;
        if (pending > 0u && (!have_tail || seq < min_seq)) {
            min_seq = seq;
            tail = s;
            have_tail = 1;
        }
    }

    /* head_slot = перший вільний слот head-сектора. */
    {
        uint8_t used[FLASH_RING_BMP_BYTES], cons[FLASH_RING_BMP_BYTES];
        if (!read_bitmaps(r, head, used, cons)) return 0;
        uint16_t s = 0;
        while (s < FLASH_RING_SLOTS_PER_SECTOR && bitmap_bit_clear(used, s)) s++;
        r->head_slot = s;
    }

    if (have_tail) {
        uint8_t used[FLASH_RING_BMP_BYTES], cons[FLASH_RING_BMP_BYTES];
        if (!read_bitmaps(r, tail, used, cons)) return 0;
        uint16_t s = 0;
        while (s < FLASH_RING_SLOTS_PER_SECTOR &&
               (!bitmap_bit_clear(used, s) || bitmap_bit_clear(cons, s))) s++;
        r->tail_sector = tail;
        r->tail_slot   = s;
    } else {
        r->tail_sector = r->head_sector;
        r->tail_slot   = r->head_slot;
    }

    r->mounted = 1;
    return 1;
}

/* FIFO-drop найстарішого сектора: durable consume-all (без erase — стирання
 * зробить head, коли докотиться). Повертає 1 = tail просунуто. */
static int drop_oldest_sector(FlashRing *r)
{
    uint8_t used[FLASH_RING_BMP_BYTES], cons[FLASH_RING_BMP_BYTES];
    if (!read_bitmaps(r, r->tail_sector, used, cons)) return 0;
    uint32_t pending = sector_pending(used, cons);

    /* Весь consumed-бітмап у нуль одним програмуванням. */
    uint8_t zeros[FLASH_RING_BMP_BYTES];
    memset(zeros, 0, sizeof(zeros));
    if (!r->ops->program(r->io,
                         sector_base(r, r->tail_sector) + FLASH_RING_CONS_OFF,
                         zeros, sizeof(zeros)))
        return 0;

    r->count      -= pending;
    r->tail_sector = (uint16_t)((r->tail_sector + 1u) % r->n_sectors);
    r->tail_slot   = 0;
    return 1;
}

static uint32_t slot_addr(const FlashRing *r, uint16_t sector, uint16_t slot)
{
    return sector_base(r, sector) + FLASH_RING_DATA_OFF +
           (uint32_t)slot * FLASH_RING_RECORD_SIZE;
}

int FlashRing_Append(FlashRing *r, const uint8_t rec[FLASH_RING_RECORD_SIZE])
{
    if (!r || !r->mounted || !rec) return 0;

    /* Знаходимо слот, у який МОЖНА писати. NOR не вміє перезаписати
     * сироту (power-cut між даними і used-бітом лишає байти, що AND-яться
     * з новим записом у мішанину) — не-цілинний слот без used-біта
     * tombstone'имо (used+consumed → назавжди невидимий) і йдемо далі. */
    for (;;) {
        if (r->head_slot >= FLASH_RING_SLOTS_PER_SECTOR) {
            /* Head-сектор повний → котимось у наступний. */
            uint16_t next = (uint16_t)((r->head_sector + 1u) % r->n_sectors);
            if (next == r->tail_sector && r->count > 0u) {
                if (!drop_oldest_sector(r)) return 0;
            } else if (next == r->tail_sector) {
                /* Порожній ring наздогнав сам себе: tail їде разом із head. */
                r->tail_sector = next;
                r->tail_slot   = 0;
            }
            r->head_sector = next;
            r->head_slot   = 0;
            continue;
        }

        if (r->head_slot == 0u) {
            /* Свіжий сектор: erase + заголовок нової генерації —
             * слоти цілинні за побудовою. */
            if (!r->ops->erase_sector(r->io, r->head_sector)) return 0;
            uint32_t seq = r->head_seq + 1u;
            uint8_t hdr[FLASH_RING_HDR_SIZE] = {
                (uint8_t)(FLASH_RING_MAGIC & 0xFFu),
                (uint8_t)(FLASH_RING_MAGIC >> 8),
                0xFFu, 0xFFu, /* rsv лишаємо стертим */
                (uint8_t)(seq & 0xFFu), (uint8_t)(seq >> 8),
                (uint8_t)(seq >> 16),   (uint8_t)(seq >> 24)
            };
            if (!r->ops->program(r->io, sector_base(r, r->head_sector), hdr,
                                 sizeof(hdr)))
                return 0;
            r->head_seq = seq;
            /* tail порожнього ring'а слідує за head'ом у новий сектор. */
            if (r->count == 0u) {
                r->tail_sector = r->head_sector;
                r->tail_slot   = 0;
            }
            break;
        }

        /* Посеред сектора (перший append після mount'а): цілинність слота. */
        uint8_t probe[FLASH_RING_RECORD_SIZE];
        if (!r->ops->read(r->io, slot_addr(r, r->head_sector, r->head_slot),
                          probe, sizeof(probe)))
            return 0;
        int virgin = 1;
        for (uint32_t i = 0; i < sizeof(probe); i++) {
            if (probe[i] != 0xFFu) { virgin = 0; break; }
        }
        if (virgin) break;

        /* Сирота: жертвуємо слотом durable. */
        if (!program_bit(r, r->head_sector, FLASH_RING_USED_OFF, r->head_slot))
            return 0;
        if (!program_bit(r, r->head_sector, FLASH_RING_CONS_OFF, r->head_slot))
            return 0;
        r->head_slot++;
    }

    /* Дані → used-біт (саме в цьому порядку — інваріант 1). */
    if (!r->ops->program(r->io, slot_addr(r, r->head_sector, r->head_slot),
                         rec, FLASH_RING_RECORD_SIZE))
        return 0;
    if (!program_bit(r, r->head_sector, FLASH_RING_USED_OFF, r->head_slot))
        return 0;

    r->head_slot++;
    r->count++;
    return 1;
}

/* idx-тий недоставлений слот від tail. Прогулянка по бітмапах (а не сирій
 * арифметиці слотів): tombstone-сироти (used+consumed) сидять ПОМІЖ
 * легітимних записів — їх просто перестрибуємо. */
static int find_pending(const FlashRing *r, uint32_t idx,
                        uint16_t *out_sector, uint16_t *out_slot)
{
    uint16_t sector = r->tail_sector;
    uint16_t start  = r->tail_slot;
    for (;;) {
        uint8_t used[FLASH_RING_BMP_BYTES], cons[FLASH_RING_BMP_BYTES];
        if (!read_bitmaps(r, sector, used, cons)) return 0;
        uint16_t end = (sector == r->head_sector) ? r->head_slot
                                                  : FLASH_RING_SLOTS_PER_SECTOR;
        for (uint16_t s = start; s < end; s++) {
            if (bitmap_bit_clear(used, s) && !bitmap_bit_clear(cons, s)) {
                if (idx == 0u) {
                    *out_sector = sector;
                    *out_slot   = s;
                    return 1;
                }
                idx--;
            }
        }
        if (sector == r->head_sector) return 0;
        sector = (uint16_t)((sector + 1u) % r->n_sectors);
        start  = 0;
        if (sector == r->tail_sector) return 0;
    }
}

int FlashRing_Read_Tail(const FlashRing *r, uint32_t idx,
                        uint8_t out[FLASH_RING_RECORD_SIZE])
{
    if (!r || !r->mounted || !out || idx >= r->count) return 0;

    uint16_t sector, slot;
    if (!find_pending(r, idx, &sector, &slot)) return 0;
    return r->ops->read(r->io, slot_addr(r, sector, slot), out,
                        FLASH_RING_RECORD_SIZE);
}

int FlashRing_Consume(FlashRing *r, uint32_t n)
{
    if (!r || !r->mounted || n > r->count) return 0;

    while (n > 0u) {
        uint16_t sector, slot;
        if (!find_pending(r, 0u, &sector, &slot)) return 0;
        if (!program_bit(r, sector, FLASH_RING_CONS_OFF, slot)) return 0;
        /* Tail рухається до щойно пожатого слота: наступний find_pending
         * не сканує вже-пройдене. */
        r->tail_sector = sector;
        r->tail_slot   = (uint16_t)(slot + 1u);
        r->count--;
        n--;
    }

    /* Tail → перший живий pending (або head, якщо порожньо). */
    if (r->count > 0u) {
        uint16_t sector, slot;
        if (find_pending(r, 0u, &sector, &slot)) {
            r->tail_sector = sector;
            r->tail_slot   = slot;
        }
    } else {
        r->tail_sector = r->head_sector;
        r->tail_slot   = r->head_slot;
    }
    return 1;
}

uint32_t FlashRing_Count(const FlashRing *r)
{
    return (r && r->mounted) ? r->count : 0u;
}
