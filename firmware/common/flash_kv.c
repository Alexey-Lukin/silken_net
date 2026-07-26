// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * flash_kv.c — [ARCH.28 шлях A] імплементація журнального KV (див. flash_kv.h).
 *
 * Інваріанти, на яких стоїть відновлення після power-cut:
 *   I1. Елемент атомарний (ECC dw) — валідний АБО 0xFF…FF; сміття з
 *       обірваного програмування ловиться crc16 і мовчки скіпається.
 *   I2. FINI-заголовок програмиться ОСТАННІМ — сторінка без FINI ніколи
 *       не стає авторитетною.
 *   I3. Стара сторінка стирається лише ПІСЛЯ FINI нової — у найгіршому
 *       разі живуть дві повні валідні: виграє вища seq, нижча стирається
 *       при Mount.
 */
#include <string.h>

#include "flash_kv.h"
#include "silken_crc.h"

#define KV_PAGE_MAGIC 0x534B5631u /* "SKV1" */
#define KV_FINI_MAGIC 0x46494E49u /* "FINI" */
#define KV_REC_FLAGS  0xA5u
#define KV_ERASED_DW  0xFFFFFFFFFFFFFFFFull
#define KV_HDR_DWS    2u

/* ── Пакування ──────────────────────────────────────────────────────── */

static uint16_t kv_crc16(uint32_t value, uint8_t key, uint8_t flags)
{
    uint8_t b[6] = {
        (uint8_t)(value >> 24), (uint8_t)(value >> 16),
        (uint8_t)(value >> 8),  (uint8_t)value,
        key, flags
    };
    return Silken_Crc16_Ccitt(b, sizeof b);
}

static uint64_t kv_pack_rec(uint8_t key, uint32_t value)
{
    uint16_t crc = kv_crc16(value, key, KV_REC_FLAGS);
    return ((uint64_t)value << 32) | ((uint64_t)key << 24) |
           ((uint64_t)KV_REC_FLAGS << 16) | crc;
}

static int kv_unpack_rec(uint64_t dw, uint8_t *key, uint32_t *value)
{
    if (dw == KV_ERASED_DW) return 0;
    uint8_t  k     = (uint8_t)(dw >> 24);
    uint8_t  flags = (uint8_t)(dw >> 16);
    uint16_t crc   = (uint16_t)dw;
    uint32_t v     = (uint32_t)(dw >> 32);
    if (flags != KV_REC_FLAGS) return 0;
    if (crc != kv_crc16(v, k, flags)) return 0;
    if (k < FLASH_KV_KEY_MIN || k > FLASH_KV_KEY_MAX) return 0;
    *key = k;
    *value = v;
    return 1;
}

static uint64_t kv_pack_hdr(uint32_t magic, uint16_t seq)
{
    uint8_t b[6] = {
        (uint8_t)(magic >> 24), (uint8_t)(magic >> 16),
        (uint8_t)(magic >> 8),  (uint8_t)magic,
        (uint8_t)(seq >> 8),    (uint8_t)seq
    };
    uint16_t crc = Silken_Crc16_Ccitt(b, sizeof b);
    return ((uint64_t)magic << 32) | ((uint64_t)seq << 16) | crc;
}

static int kv_unpack_hdr(uint64_t dw, uint32_t expect_magic, uint16_t *seq)
{
    if (dw == KV_ERASED_DW) return 0;
    uint32_t magic = (uint32_t)(dw >> 32);
    uint16_t s     = (uint16_t)(dw >> 16);
    if (magic != expect_magic) return 0;
    if (dw != kv_pack_hdr(magic, s)) return 0;
    *seq = s;
    return 1;
}

/* ── Доступ до сторінок ─────────────────────────────────────────────── */

static uint32_t kv_off(const FlashKv *kv, uint8_t page, uint16_t dw_idx)
{
    return ((uint32_t)page * kv->page_dws + dw_idx) * 8u;
}

static uint64_t kv_read(const FlashKv *kv, uint8_t page, uint16_t dw_idx)
{
    return kv->ops->read_dw(kv->io, kv_off(kv, page, dw_idx));
}

/* Стан сторінки: 0 = не авторитетна, 1 = повна валідна (SKV1+FINI). */
static int kv_page_valid(const FlashKv *kv, uint8_t page, uint16_t *seq)
{
    uint16_t s0 = 0, s1 = 0;
    if (!kv_unpack_hdr(kv_read(kv, page, 0), KV_PAGE_MAGIC, &s0)) return 0;
    if (!kv_unpack_hdr(kv_read(kv, page, 1), KV_FINI_MAGIC, &s1)) return 0;
    if (s0 != s1) return 0;
    *seq = s0;
    return 1;
}

/* Перший стертий dw після заголовків (сміття по дорозі скіпається —
 * write-курсор завжди стає на чистий флеш). */
static uint16_t kv_scan_write_idx(const FlashKv *kv, uint8_t page)
{
    for (uint16_t i = KV_HDR_DWS; i < kv->page_dws; i++) {
        if (kv_read(kv, page, i) == KV_ERASED_DW) return i;
    }
    return kv->page_dws;
}

/* ── API ────────────────────────────────────────────────────────────── */

static int kv_format_page(FlashKv *kv, uint8_t page, uint16_t seq)
{
    if (!kv->ops->erase_page(kv->io, page)) return 0;
    if (!kv->ops->program_dw(kv->io, kv_off(kv, page, 0),
                             kv_pack_hdr(KV_PAGE_MAGIC, seq))) return 0;
    if (!kv->ops->program_dw(kv->io, kv_off(kv, page, 1),
                             kv_pack_hdr(KV_FINI_MAGIC, seq))) return 0;
    return 1;
}

int FlashKv_Mount(FlashKv *kv, const FlashKvOps *ops, void *io, uint16_t page_dws)
{
    if (!kv || !ops || page_dws <= KV_HDR_DWS) return 0;
    kv->ops = ops;
    kv->io = io;
    kv->page_dws = page_dws;

    uint16_t seq0 = 0, seq1 = 0;
    int v0 = kv_page_valid(kv, 0, &seq0);
    int v1 = kv_page_valid(kv, 1, &seq1);

    if (v0 && v1) {
        /* Power-cut після FINI нової, до erase старої: вища seq виграє.
         * (u16-wrap тут не страшний: 10k endurance ≪ 65535 поколінь.) */
        uint8_t newer = (uint8_t)((seq1 > seq0) ? 1 : 0);
        if (!kv->ops->erase_page(kv->io, (uint8_t)(1u - newer))) return 0;
        kv->active = newer;
        kv->seq = newer ? seq1 : seq0;
    } else if (v0 || v1) {
        kv->active = (uint8_t)(v1 ? 1 : 0);
        kv->seq = v1 ? seq1 : seq0;
        /* Сусідка без FINI = обірваний compact → прибрати недобудову. */
        uint8_t other = (uint8_t)(1u - kv->active);
        if (kv_read(kv, other, 0) != KV_ERASED_DW) {
            if (!kv->ops->erase_page(kv->io, other)) return 0;
        }
    } else {
        /* Перше життя (або подвійна руїна): формат із нуля. */
        if (!kv_format_page(kv, 0, 1u)) return 0;
        if (!kv->ops->erase_page(kv->io, 1)) return 0;
        kv->active = 0;
        kv->seq = 1u;
    }

    kv->write_idx = kv_scan_write_idx(kv, kv->active);
    return 1;
}

int FlashKv_Get32(const FlashKv *kv, uint8_t key, uint32_t *out)
{
    if (!kv || !out) return 0;
    int found = 0;
    /* Прямий скан, останній валідний виграє — O(сторінка), без RAM-індексу
     * (RAM Солдата дорожча за лічені сотні читань flash). */
    for (uint16_t i = KV_HDR_DWS; i < kv->write_idx; i++) {
        uint8_t k; uint32_t v;
        if (kv_unpack_rec(kv_read(kv, kv->active, i), &k, &v) && k == key) {
            *out = v;
            found = 1;
        }
    }
    return found;
}

int FlashKv_Put32(FlashKv *kv, uint8_t key, uint32_t val)
{
    if (!kv) return 0;
    if (key < FLASH_KV_KEY_MIN || key > FLASH_KV_KEY_MAX) return 0;
    if (kv->write_idx >= kv->page_dws) return 0; /* FULL — спершу Compact */
    if (!kv->ops->program_dw(kv->io, kv_off(kv, kv->active, kv->write_idx),
                             kv_pack_rec(key, val))) return 0;
    kv->write_idx++;
    return 1;
}

uint16_t FlashKv_FreeSlots(const FlashKv *kv)
{
    return (uint16_t)(kv->page_dws - kv->write_idx);
}

/* Чи сторінка повністю стерта (усі dw = FF). Дешевше за зайвий erase:
 * у ping-pong steady-state ціль уже чиста — пропуск вдвічі ріже wear. */
static int kv_page_blank(const FlashKv *kv, uint8_t page)
{
    for (uint16_t i = 0; i < kv->page_dws; i++) {
        if (kv_read(kv, page, i) != KV_ERASED_DW) return 0;
    }
    return 1;
}

int FlashKv_Compact(FlashKv *kv)
{
    if (!kv) return 0;
    uint8_t  dst = (uint8_t)(1u - kv->active);
    uint16_t new_seq = (uint16_t)(kv->seq + 1u);

    if (!kv_page_blank(kv, dst) && !kv->ops->erase_page(kv->io, dst)) return 0;
    if (!kv->ops->program_dw(kv->io, kv_off(kv, dst, 0),
                             kv_pack_hdr(KV_PAGE_MAGIC, new_seq))) return 0;

    /* Скан із кінця: перша зустріч ключа = найсвіжіше значення; бачені
     * ключі — у бітмапі на стеку (256 біт = 32 Б, нуль RAM-статики). */
    uint8_t  seen[32];
    memset(seen, 0, sizeof seen);
    uint16_t dst_idx = KV_HDR_DWS;

    for (uint16_t i = kv->write_idx; i > KV_HDR_DWS; i--) {
        uint8_t k; uint32_t v;
        if (!kv_unpack_rec(kv_read(kv, kv->active, i - 1u), &k, &v)) continue;
        if (seen[k >> 3] & (uint8_t)(1u << (k & 7u))) continue;
        seen[k >> 3] |= (uint8_t)(1u << (k & 7u));
        if (!kv->ops->program_dw(kv->io, kv_off(kv, dst, dst_idx),
                                 kv_pack_rec(k, v))) return 0;
        dst_idx++;
    }

    /* I2: FINI останнім — лише тепер нова сторінка авторитетна. */
    if (!kv->ops->program_dw(kv->io, kv_off(kv, dst, 1),
                             kv_pack_hdr(KV_FINI_MAGIC, new_seq))) return 0;
    /* I3: стару — геть (відмова тут не фатальна: Mount добере вищу seq). */
    if (!kv->ops->erase_page(kv->io, kv->active)) return 0;

    kv->active = dst;
    kv->seq = new_seq;
    kv->write_idx = dst_idx;
    return 1;
}
