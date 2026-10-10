// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * lorenz_thresholds.h — смуга Лоренца ECB-контракту: заводські константи й
 * One-Home побудови аргументів `calculate_state`.
 *
 * Пристрій судить статус кадру ЗАВОДСЬКОЮ смугою — інших він не приймає й не
 * тримає: видачу смуги FW.8 (`0x9A`) і її журнал Flash-KV `0x10/0x11` знято
 * разом із гілкою (Б) (00_07 FW.66). Смуга лишається АРГУМЕНТАМИ 9-аргументного
 * ABI контракту (ABI-підлога, 03_04), тож міст Солдата й QEMU-паритет передають
 * саме ці константи, а байткод не регенерується. Контракт іде з ECB-ерою.
 *
 * Канон: 03_04 §4.1 (числа) · бекенд-дзеркало — Tree::DEVICE_DEFAULT_LORENZ_BAND.
 */
#ifndef SILKEN_LORENZ_THRESHOLDS_H
#define SILKEN_LORENZ_THRESHOLDS_H

#include <stdint.h>

#define LORENZ_DEFAULT_Z_MIN_X100 200  /* 2.00 */
#define LORENZ_DEFAULT_Z_MAX_X100 4500 /* 45.00 */

/* Смуга для mruby-контракту: x100-цілі → Float у ТОМУ Ж порядку, в якому
 * calculate_state їх приймає (8-й аргумент z_min, 9-й z_max). One-Home: міст
 * Солдата (main.c) і QEMU-паритет (firmware/sim/parity_core.h) будують аргументи
 * ЦИМ викликом, тож квантизація `/100.0` і порядок живуть в одному місці, а
 * паритет і PARITY-MEM міряють той самий 9-аргументний виклик, що й пристрій.
 * ⚠️ Стеля: переставлені аргументи НА ВИКЛИКУ в main.c жоден гейт не бачить —
 * main.c збирається лише compile-only (hal_check), і так лишається до bench-дня. */
static inline void Lorenz_Band_Args(int16_t z_min_x100, int16_t z_max_x100, double out[2])
{
    out[0] = (double)z_min_x100 / 100.0;
    out[1] = (double)z_max_x100 / 100.0;
}

#endif /* SILKEN_LORENZ_THRESHOLDS_H */
