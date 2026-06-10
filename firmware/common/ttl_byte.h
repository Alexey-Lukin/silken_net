/*
 * ttl_byte.h — [FW.18b] бітфілд байта 11 LoRa-плейну (One-Home).
 *
 * Дріт уже забитий, а production-visibility лічильнику відкинутих
 * OTA-порогів (`tinyml_threshold_invalid_count`, 03_03 §5.4) треба
 * додому. TTL живе значеннями 0..5 (DEFAULT_TTL=3, PANIC_TTL=5) —
 * байту досить трьох біт, верхні п'ять віддаємо лічильнику:
 *
 *   Байт 11: [thr_invalid:5 (біти 7..3) | TTL:3 (біти 2..0)]
 *
 * Pack(ttl, 0) == старий «чистий» TTL-байт — стара прошивка для бекенда
 * виглядає як лічильник 0, нічого не ламається. Лічильник належить
 * Солдату-ОРИГІНАЛУ: mesh-релей декрементує лише TTL-біти і зберігає
 * чужі верхні п'ять незмінними (Ttl_Byte_Decrement).
 *
 * Дзеркало бекенда: TelemetryUnpackerService (маски ідентичні, golden
 * у test_soldier_logic.c ↔ telemetry_unpacker_service_spec.rb).
 * Канон: 03_01 §1.6 (wire) + 03_03 §5.4 (лічильник) + 00_07 FW.18b.
 */
#ifndef SILKEN_TTL_BYTE_H
#define SILKEN_TTL_BYTE_H

#include <stdint.h>

#define TTL_BYTE_TTL_MASK      0x07u
#define TTL_BYTE_INVALID_SHIFT 3u
#define TTL_BYTE_INVALID_MAX   31u /* 5 біт на дроті; RAM-лічильник сатурує @255 */

static inline uint8_t Ttl_Byte_Pack(uint8_t ttl, uint8_t invalid_count)
{
    uint8_t capped = (invalid_count > TTL_BYTE_INVALID_MAX)
                         ? (uint8_t)TTL_BYTE_INVALID_MAX
                         : invalid_count;
    return (uint8_t)((uint8_t)(capped << TTL_BYTE_INVALID_SHIFT) |
                     (ttl & TTL_BYTE_TTL_MASK));
}

static inline uint8_t Ttl_Byte_Ttl(uint8_t b) { return (uint8_t)(b & TTL_BYTE_TTL_MASK); }

static inline uint8_t Ttl_Byte_Invalid(uint8_t b)
{
    return (uint8_t)(b >> TTL_BYTE_INVALID_SHIFT);
}

/* Mesh-релей: TTL-- без дотику до чужого лічильника. TTL=0 не чіпаємо —
 * викликач і так релеїть лише живі пакети (Ttl_Byte_Ttl > 0). */
static inline uint8_t Ttl_Byte_Decrement(uint8_t b)
{
    uint8_t ttl = Ttl_Byte_Ttl(b);
    if (ttl == 0u) return b;
    return (uint8_t)((b & (uint8_t)~TTL_BYTE_TTL_MASK) | (uint8_t)(ttl - 1u));
}

#endif /* SILKEN_TTL_BYTE_H */
