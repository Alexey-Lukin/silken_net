/*
 * silken_crc.h — CRC-примітиви wire-рівня SilkenNet (One-Home).
 *
 * [FW.53] До цього файла CRC16-CCITT жив окремими копіями у
 * soldier/main.c (+ дзеркало в тестах), а Queen НЕ перевіряла CRC16
 * CoAP-OTA-чанків узагалі (бекенд додавав — фірмварь ігнорувала).
 * Тепер обидві прошивки та host-тести компілюють ОДИН код.
 *
 * CRC-16/CCITT-FALSE: поліном 0x1021, init 0xFFFF, без рефлексії.
 * Дзеркало Ruby: OtaPackagerService.crc16_ccitt — байт-у-байт.
 */

#ifndef SILKEN_CRC_H
#define SILKEN_CRC_H

#include <stdint.h>

static inline uint16_t Silken_Crc16_Ccitt(const uint8_t *data, uint16_t len)
{
    uint16_t crc = 0xFFFFu;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= (uint16_t)((uint16_t)data[i] << 8);
        for (uint8_t b = 0; b < 8u; b++) {
            crc = (crc & 0x8000u) ? (uint16_t)((uint16_t)(crc << 1) ^ 0x1021u)
                                  : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

#endif /* SILKEN_CRC_H */
