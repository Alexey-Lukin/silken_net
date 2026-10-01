// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ds18b20.h — [HW.16] термодатчик батареї Королеви: scratchpad DS18B20 →
 *             °C×100 (One-Home, pure, без HAL).
 *
 * Навіщо. Цей датчик гейтує ЗАРЯД LiFePO4 узимку: заряджати комірку нижче
 * +1 °C не можна (02_05 §4а.5), а заводський поріг BMS за замовчуванням
 * стоїть на −10 °C і повертається мовчки при заміні плати чи скиданні
 * параметрів. Тобто рядок, який цей модуль декодує, є входом «детектора
 * тихого дефолту» — єдиного, що ту мовчанку робить чутною (00_07 HW.16).
 * Датчик потрібен за БУДЬ-ЯКОЇ з двох живих гілок поз. 24 (02_05 §7).
 *
 * 🚨 ГОЛОВНЕ, і воно не про арифметику: у DS18B20 scratchpad після подачі
 * живлення містить рівно +85.00 °C, і це НЕ помилкове значення, а штатний
 * power-on стан. Він БІТОВО ТОТОЖНИЙ справжньому виміру +85.00 °C, тож
 * «відрізнити за значенням» не можна в принципі — і саме так датчик, який
 * ніколи не конвертував, видає робочий градус. Для нашого вживання це клас
 * ФОЛБЕКУ (00_01 §1.1: підставлене число є фабрикацією, введене — виміром):
 * гейт заряду прочитав би +85 як «тепло, заряджати можна» в мороз.
 * Тому модуль не вдає, що вміє це розсудити САМ: `Ds18b20_Is_Por_Value`
 * позначає неоднозначність, а зняти її може лише знання викликача про те,
 * чи конверсія ВЗАГАЛІ завершилась (`Ds18b20_Decode` бере це прапорцем).
 *
 * Цей модуль pure (1-Wire тайминг, GPIO й сама шина — HAL-половина, bench):
 *   1. Ds18b20_Crc8        — CRC-8/MAXIM по 8 байтах scratchpad'а проти 9-го.
 *   2. Ds18b20_Decode      — scratchpad → °C×100 або сентинел «не виміряно».
 *   3. Ds18b20_Resolution_Bits / Ds18b20_Conversion_Time_Ms — з config-байта,
 *      щоб викликач чекав рівно стільки, скільки датчик справді рахує.
 *
 * ⛔ Чому CRC-8 живе ТУТ, а не в silken_crc.h: той файл оголошує себе домом
 * CRC-примітивів НАШОГО дроту (CRC-16/CCITT, дзеркало в Ruby). CRC-8/MAXIM є
 * частиною чужого протоколу Maxim/ADI і нашого дроту не стосується — злиття
 * зробило б «один дім» із двох різних предметів.
 *
 * ⚠️ Стелі, названі вголос (гіпотеза за 00_06 §0 — фізику підтверджує стенд):
 *   - модуль не бачить шини: ні presence-pulse, ні ROM-команд, ні паразитного
 *     живлення тут немає; «датчик не відповів» мусить віддати HAL-половина, і
 *     у scratchpad'і це виглядає як усі 0xFF (CRC не зійдеться);
 *   - теплове зчеплення TO-92 з корпусом комірки й затримка відповіді — це
 *     властивість МОНТАЖУ, не декодера: судить морозильний стенд (00_07 HW.16);
 *   - ±0.5 °C паспортні лише на −10…+85 °C (ширше ±2 °C) — межа датчика, не коду;
 *   - клони DS18B20 ламають саме цей рівень (зсув поза ±0.5 °C, інша затримка),
 *     тож канал постачання є частиною достовірності числа (02_05 §4а.6).
 * Канон: 02_05 §4а.5 (вікно заряду) · §4а.6 (P/N і монтаж) · 00_07 HW.16.
 */
#ifndef SILKEN_DS18B20_H
#define SILKEN_DS18B20_H

#include <stdint.h>

/* Scratchpad — 9 байтів (datasheet ADI DS18B20, Figure 9). */
#define DS18B20_SCRATCHPAD_LEN   9u

#define DS18B20_SP_TEMP_LSB      0u
#define DS18B20_SP_TEMP_MSB      1u
#define DS18B20_SP_CONFIG        4u
#define DS18B20_SP_CRC           8u

/* Сентинел «не виміряно». Поза фізичним діапазоном датчика (−55…+125 °C),
 * тож сплутати з градусом не можна. ⛔ Нуль сентинелем бути НЕ може: 0 °C —
 * робоча точка вікна заряду. */
#define DS18B20_TEMP_UNKNOWN     INT32_MIN

/* Power-on значення температурного регістра: +85.0000 °C (datasheet §Memory). */
#define DS18B20_POR_TEMP_RAW     0x0550

/* Межі датчика в °C×100 — для плаузибіліті викликача, не для декодера. */
#define DS18B20_MIN_CENTI_C      (-5500)
#define DS18B20_MAX_CENTI_C      12500

/* CRC-8/MAXIM: поліном x⁸+x⁵+x⁴+1 (0x31), рефлексований 0x8C, init 0x00. */
static inline uint8_t Ds18b20_Crc8(const uint8_t *data, uint8_t len)
{
    uint8_t crc = 0u;
    for (uint8_t i = 0u; i < len; i++) {
        uint8_t byte = data[i];
        for (uint8_t bit = 0u; bit < 8u; bit++) {
            uint8_t mix = (uint8_t)((crc ^ byte) & 0x01u);
            crc >>= 1;
            if (mix) { crc ^= 0x8Cu; }
            byte >>= 1;
        }
    }
    return crc;
}

/* Чи сходиться CRC scratchpad'а. Усі 0xFF (німа шина) тут не проходять. */
static inline int Ds18b20_Scratchpad_Valid(const uint8_t *sp)
{
    return Ds18b20_Crc8(sp, (uint8_t)(DS18B20_SCRATCHPAD_LEN - 1u)) == sp[DS18B20_SP_CRC];
}

/* Роздільність із config-байта (біти 6:5 — R1:R0): 9 · 10 · 11 · 12 біт. */
static inline uint8_t Ds18b20_Resolution_Bits(const uint8_t *sp)
{
    return (uint8_t)(9u + ((sp[DS18B20_SP_CONFIG] >> 5) & 0x03u));
}

/* Час конверсії, мс (datasheet: t_CONV ≤ 750 мс на 12 бітах, удвічі менше
 * на кожен знятий біт). Викликач чекає СТІЛЬКИ, інакше прочитає попередній
 * вміст scratchpad'а як свіжий вимір. */
static inline uint16_t Ds18b20_Conversion_Time_Ms(uint8_t resolution_bits)
{
    switch (resolution_bits) {
        case 9u:  return 94u;
        case 10u: return 188u;
        case 11u: return 375u;
        default:  return 750u;
    }
}

/* Чи дорівнює температурний регістр power-on значенню (+85.00 °C).
 * ⚠️ Істина тут НЕ означає «датчик не міряв» — справжні +85.00 °C дають той
 * самий код. Вона означає НЕОДНОЗНАЧНІСТЬ, і зняти її може лише знання про
 * те, чи конверсія завершилась. */
static inline int Ds18b20_Is_Por_Value(const uint8_t *sp)
{
    int16_t raw = (int16_t)(((uint16_t)sp[DS18B20_SP_TEMP_MSB] << 8) |
                             (uint16_t)sp[DS18B20_SP_TEMP_LSB]);
    return raw == (int16_t)DS18B20_POR_TEMP_RAW;
}

/* Сирий регістр → °C×100. 1 LSB = 1/16 °C, тож ×25/4 з округленням
 * від нуля (щоб −0.0625 не ставало 0.00 і не читалось як «рівно нуль»). */
static inline int32_t Ds18b20_Raw_To_Centi_C(int16_t raw)
{
    int32_t scaled = (int32_t)raw * 25;
    return (scaled + (scaled >= 0 ? 2 : -2)) / 4;
}

/*
 * Scratchpad → °C×100, або DS18B20_TEMP_UNKNOWN.
 *
 * `conversion_completed` — твердження ВИКЛИКАЧА (HAL-половини) про те, що
 * після Convert-T минув Ds18b20_Conversion_Time_Ms і датчик відзвітував
 * про готовність. Воно тут несуче: без нього +85.00 °C неможливо відрізнити
 * від power-on стану, і модуль радше віддасть сентинел, ніж градус, якого
 * ніхто не міряв.
 */
static inline int32_t Ds18b20_Decode(const uint8_t *sp, int conversion_completed)
{
    if (!Ds18b20_Scratchpad_Valid(sp)) { return DS18B20_TEMP_UNKNOWN; }
    if (!conversion_completed && Ds18b20_Is_Por_Value(sp)) { return DS18B20_TEMP_UNKNOWN; }

    int16_t raw = (int16_t)(((uint16_t)sp[DS18B20_SP_TEMP_MSB] << 8) |
                             (uint16_t)sp[DS18B20_SP_TEMP_LSB]);
    return Ds18b20_Raw_To_Centi_C(raw);
}

#endif /* SILKEN_DS18B20_H */
