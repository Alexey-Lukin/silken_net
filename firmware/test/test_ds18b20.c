// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_ds18b20.c — [HW.16] декодер scratchpad'а DS18B20 (host).
 *
 * Golden'и СВІДОМО зовнішні, щоб тест не доводив сам себе:
 *   (а) CRC-8/MAXIM звіряється стандартним check-вектором «123456789» → 0xA1;
 *   (б) температури — рядки таблиці Temperature/Data даташита ADI DS18B20
 *       (+125 · +85 · +25.0625 · +10.125 · +0.5 · 0 · −0.5 · −10.125 ·
 *       −25.0625 · −55 °C), тобто друга транскрипція ЧУЖОГО документа.
 *
 * Найважливіший тест — не арифметика, а пастка: power-on scratchpad несе
 * рівно +85.00 °C і бітово тотожний справжньому виміру +85.00 °C, тож
 * декодер мусить віддати сентинел, доки викликач не ствердив, що конверсія
 * завершилась (00_07 HW.16; клас ФОЛБЕКУ — 00_01 §1.1).
 *
 * Build: make -C firmware/test ds18b20
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "../common/ds18b20.h"

static int tests_passed = 0;
static int tests_failed = 0;
static int last_failed = 0;

#define RUN(name) do { \
    last_failed = 0; \
    printf("  %-58s", #name); \
    name(); \
    if (!last_failed) { printf(" ✅\n"); tests_passed++; } \
} while(0)

#define CHECK(cond, msg) do { \
    if (!(cond)) { \
        printf(" ❌\n    %s\n", msg); \
        if (!last_failed) { tests_failed++; last_failed = 1; } \
    } \
} while(0)

/* Збирає scratchpad із заданим сирим градусом і конфігом, CRC — рахований. */
static void build_sp(uint8_t *sp, int16_t raw, uint8_t config)
{
    memset(sp, 0, DS18B20_SCRATCHPAD_LEN);
    sp[DS18B20_SP_TEMP_LSB] = (uint8_t)((uint16_t)raw & 0xFFu);
    sp[DS18B20_SP_TEMP_MSB] = (uint8_t)(((uint16_t)raw >> 8) & 0xFFu);
    sp[2] = 0x4B;              /* TH — заводський дефолт */
    sp[3] = 0x46;              /* TL — заводський дефолт */
    sp[DS18B20_SP_CONFIG] = config;
    sp[5] = 0xFF;
    sp[6] = 0x0C;
    sp[7] = 0x10;
    sp[DS18B20_SP_CRC] = Ds18b20_Crc8(sp, DS18B20_SCRATCHPAD_LEN - 1u);
}

/* (а) ЗОВНІШНІЙ вектор: CRC-8/MAXIM("123456789") = 0xA1. */
static void test_crc8_external_check_vector(void)
{
    const uint8_t v[9] = { '1', '2', '3', '4', '5', '6', '7', '8', '9' };
    uint8_t crc = Ds18b20_Crc8(v, 9u);
    char m[96];
    snprintf(m, sizeof(m), "CRC-8/MAXIM(\"123456789\") = 0x%02X, очікувалось 0xA1", crc);
    CHECK(crc == 0xA1u, m);
}

/* (б) Таблиця даташита: сирий регістр → °C×100. */
static void test_datasheet_temperature_table(void)
{
    const struct { int16_t raw; int32_t centi; const char *label; } rows[] = {
        { (int16_t)0x07D0,  12500, "+125.0000" },
        { (int16_t)0x0550,   8500, "+85.0000"  },
        { (int16_t)0x0191,   2506, "+25.0625"  },
        { (int16_t)0x00A2,   1013, "+10.1250"  },
        { (int16_t)0x0008,     50, "+0.5000"   },
        { (int16_t)0x0000,      0, "0.0000"    },
        { (int16_t)0xFFF8,    -50, "-0.5000"   },
        { (int16_t)0xFF5E,  -1013, "-10.1250"  },
        { (int16_t)0xFE6F,  -2506, "-25.0625"  },
        { (int16_t)0xFC90,  -5500, "-55.0000"  }
    };
    for (unsigned i = 0; i < sizeof(rows) / sizeof(rows[0]); i++) {
        int32_t got = Ds18b20_Raw_To_Centi_C(rows[i].raw);
        char m[128];
        snprintf(m, sizeof(m), "%s °C: got %d centi, очікувалось %d",
                 rows[i].label, got, rows[i].centi);
        CHECK(got == rows[i].centi, m);
    }
}

/* 🚨 Пастка power-on: +85.00 без ствердженої конверсії = сентинел, не градус. */
static void test_power_on_value_is_not_a_measurement(void)
{
    uint8_t sp[DS18B20_SCRATCHPAD_LEN];
    build_sp(sp, (int16_t)DS18B20_POR_TEMP_RAW, 0x7F);

    CHECK(Ds18b20_Is_Por_Value(sp), "POR-патерн не впізнано");
    CHECK(Ds18b20_Decode(sp, 0) == DS18B20_TEMP_UNKNOWN,
          "без ствердженої конверсії +85.00 віддано як ГРАДУС — це фабрикація");
    CHECK(Ds18b20_Decode(sp, 1) == 8500,
          "зі ствердженою конверсією справжні +85.00 мусять пройти");
}

/* Сусідній градус POR-патерном НЕ є — інакше сентинел ковтав би робочі виміри. */
static void test_neighbour_of_por_is_a_measurement(void)
{
    uint8_t sp[DS18B20_SCRATCHPAD_LEN];
    build_sp(sp, (int16_t)(DS18B20_POR_TEMP_RAW - 1), 0x7F);
    CHECK(!Ds18b20_Is_Por_Value(sp), "84.94 °C хибно позначено як POR");
    CHECK(Ds18b20_Decode(sp, 0) == 8494, "84.94 °C мусить проходити без конверсія-прапорця");
}

/* Зіпсований CRC і німа шина (усі 0xFF) → сентинел. */
static void test_bad_crc_and_dead_bus(void)
{
    uint8_t sp[DS18B20_SCRATCHPAD_LEN];
    build_sp(sp, 0x0191, 0x7F);
    sp[DS18B20_SP_CRC] ^= 0xFFu;
    CHECK(Ds18b20_Decode(sp, 1) == DS18B20_TEMP_UNKNOWN, "зіпсований CRC пройшов як вимір");

    uint8_t dead[DS18B20_SCRATCHPAD_LEN];
    memset(dead, 0xFF, sizeof(dead));
    CHECK(!Ds18b20_Scratchpad_Valid(dead), "німа шина (0xFF×9) пройшла CRC");
    CHECK(Ds18b20_Decode(dead, 1) == DS18B20_TEMP_UNKNOWN, "німа шина віддала градус");
}

/* Один перевернутий біт ТЕМПЕРАТУРИ мусить ламати CRC — інакше він не стереже. */
static void test_crc_catches_single_bit_flip_in_temperature(void)
{
    uint8_t sp[DS18B20_SCRATCHPAD_LEN];
    build_sp(sp, (int16_t)0xFF5E, 0x7F);          /* −10.125 °C — зимова точка */
    CHECK(Ds18b20_Decode(sp, 1) == -1013, "контроль: чистий scratchpad не декодується");

    sp[DS18B20_SP_TEMP_MSB] ^= 0x01u;             /* −10.125 → +... за один біт */
    CHECK(Ds18b20_Decode(sp, 1) == DS18B20_TEMP_UNKNOWN,
          "перевернутий біт знака температури пройшов повз CRC");
}

/* Роздільність і час конверсії — з config-байта. */
static void test_resolution_and_conversion_time(void)
{
    const struct { uint8_t cfg; uint8_t bits; uint16_t ms; } rows[] = {
        { 0x1F,  9u,  94u },
        { 0x3F, 10u, 188u },
        { 0x5F, 11u, 375u },
        { 0x7F, 12u, 750u }
    };
    uint8_t sp[DS18B20_SCRATCHPAD_LEN];
    for (unsigned i = 0; i < sizeof(rows) / sizeof(rows[0]); i++) {
        build_sp(sp, 0x0191, rows[i].cfg);
        uint8_t bits = Ds18b20_Resolution_Bits(sp);
        char m[128];
        snprintf(m, sizeof(m), "config 0x%02X → %u біт (очік. %u), %u мс (очік. %u)",
                 rows[i].cfg, bits, rows[i].bits,
                 Ds18b20_Conversion_Time_Ms(bits), rows[i].ms);
        CHECK(bits == rows[i].bits && Ds18b20_Conversion_Time_Ms(bits) == rows[i].ms, m);
    }
}

/* Сентинел не сміє збігтися з жодним фізичним градусом датчика. */
static void test_sentinel_outside_sensor_range(void)
{
    CHECK(DS18B20_TEMP_UNKNOWN < DS18B20_MIN_CENTI_C,
          "сентинел лежить усередині діапазону датчика");
    CHECK(DS18B20_TEMP_UNKNOWN != 0, "нуль сентинелем бути не може — це робоча точка заряду");
}

int main(void)
{
    printf("\n=== [HW.16] DS18B20 scratchpad decode (host) ===\n");
    RUN(test_crc8_external_check_vector);
    RUN(test_datasheet_temperature_table);
    RUN(test_power_on_value_is_not_a_measurement);
    RUN(test_neighbour_of_por_is_a_measurement);
    RUN(test_bad_crc_and_dead_bus);
    RUN(test_crc_catches_single_bit_flip_in_temperature);
    RUN(test_resolution_and_conversion_time);
    RUN(test_sentinel_outside_sensor_range);

    printf("\n  passed: %d, failed: %d\n\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
