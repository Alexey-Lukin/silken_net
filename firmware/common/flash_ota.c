/* flash_ota.c — [FW.52-г] OTA contract blob writer. Деталі — flash_ota.h. */
#include "flash_ota.h"
#include <string.h>

int Flash_Write_Contract(const FlashKvOps *ops, void *io, const uint8_t *data, uint16_t size)
{
    /* size < 4: нема місця під RITE-magic → відмова (boot лишиться на embedded). */
    if (!ops || !ops->erase_page || !ops->program_dw || !data || size < 4u) return 0;
    if (!ops->erase_page(io, OTA_CONTRACT_PAGE)) return 0;

    uint16_t n_dw = (uint16_t)((size + 7u) / 8u);  /* округлення вгору до doubleword */

    /* Тіло (dw[1..n-1]) — ПЕРШИМ; magic-dw (dw[0], несе RITE) — ОСТАННІМ.
     * Перерваний тут запис лишає dw[0]=0xFF → boot не бачить magic → fallback. */
    for (uint16_t i = 1u; i < n_dw; i++) {
        uint64_t dw  = 0xFFFFFFFFFFFFFFFFull;        /* нероздані хвостові байти = 0xFF */
        uint32_t off = (uint32_t)i * 8u;
        uint16_t rem = (size > off) ? (uint16_t)(size - off) : 0u;
        if (rem > 8u) rem = 8u;
        memcpy(&dw, data + off, rem);                /* LE: data[off] → молодший байт dw */
        if (!ops->program_dw(io, off, dw)) return 0;
    }

    uint64_t dw0  = 0xFFFFFFFFFFFFFFFFull;
    uint16_t rem0 = (size < 8u) ? size : 8u;
    memcpy(&dw0, data, rem0);                        /* data[0..3] = RITE → молодші 4 байти */
    if (!ops->program_dw(io, 0u, dw0)) return 0;     /* magic — LAST (power-cut safety) */

    return 1;
}
