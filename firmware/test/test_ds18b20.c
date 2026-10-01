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
 * Друга половина — транзакція 1-Wire над мок-шиною: доводить ПОСЛІДОВНІСТЬ
 * команд і розрізнення «немає presence» ⊥ «конверсії не видно» ⊥ «таймаут» ⊥
 * «CRC-брак»; мікросекундні тайминги шини мок не моделює — їх судить стенд.
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

/* ─── Транзакційний рівень: мок-шина на рівні бітів ──────────────────────────
 * Мок — модель ДАТЧИКА, а не дзеркало коду: він сам збирає біти в байти
 * молодшим першим і розпізнає лише справжні коди datasheet'а (0xCC · 0x44 ·
 * 0xBE). Шар, що слав би старшим бітом першим, писав би 0x33 (Read ROM!) і
 * 0x22 — мок їх не впізнає, і тест почервоніє на журналі команд. */

#define EV_RESET 0x100u   /* у журналі — reset-імпульс; решта — байти команд */
#define CONV_NEVER UINT32_MAX

typedef struct {
    /* поведінка */
    int      presence_resets;   /* на скільки перших reset'ів датчик відповідає */
    int      drives_conversion; /* тримає «0», доки рахує (зовнішнє VDD) */
    uint32_t conv_ms;           /* тривалість конверсії; CONV_NEVER = ніколи */
    uint8_t  sp[DS18B20_SCRATCHPAD_LEN];       /* scratchpad ДО конверсії */
    uint8_t  sp_after[DS18B20_SCRATCHPAD_LEN]; /* scratchpad ПІСЛЯ конверсії */
    /* стан */
    int      resets;
    uint8_t  in_byte, in_bits, cmd_pos;
    int      converting, reading;
    uint32_t conv_elapsed;
    unsigned out_bit;
    uint32_t delay_total_ms;
    int      unknown_cmd;
    /* журнал */
    uint16_t log[16];
    unsigned log_len;
} MockDs;

static void mock_log(MockDs *m, uint16_t ev)
{
    if (m->log_len < sizeof(m->log) / sizeof(m->log[0])) { m->log[m->log_len] = ev; }
    m->log_len++;
}

static int mock_reset(void *io)
{
    MockDs *m = io;
    m->resets++;
    mock_log(m, EV_RESET);
    m->in_byte = 0u; m->in_bits = 0u; m->cmd_pos = 0u; m->reading = 0;
    return m->resets <= m->presence_resets;
}

static void mock_on_byte(MockDs *m, uint8_t b)
{
    mock_log(m, b);
    if (m->cmd_pos == 0u) {
        if (b != DS18B20_CMD_SKIP_ROM) { m->unknown_cmd = 1; }
    } else if (m->cmd_pos == 1u) {
        if (b == DS18B20_CMD_CONVERT_T) {
            m->converting = 1; m->conv_elapsed = 0u;
        } else if (b == DS18B20_CMD_READ_SCRATCHPAD) {
            m->reading = 1; m->out_bit = 0u;
        } else {
            m->unknown_cmd = 1;
        }
    } else {
        m->unknown_cmd = 1;
    }
    m->cmd_pos++;
}

static void mock_write_bit(void *io, uint8_t bit)
{
    MockDs *m = io;
    if (bit) { m->in_byte |= (uint8_t)(1u << m->in_bits); }
    if (++m->in_bits == 8u) {
        mock_on_byte(m, m->in_byte);
        m->in_byte = 0u; m->in_bits = 0u;
    }
}

static uint8_t mock_read_bit(void *io)
{
    MockDs *m = io;
    if (m->reading) {
        unsigned i = m->out_bit++;
        if (i >= DS18B20_SCRATCHPAD_LEN * 8u) { return 1u; }
        return (uint8_t)((m->sp[i / 8u] >> (i % 8u)) & 0x01u);
    }
    if (m->converting && m->drives_conversion) {
        if (m->conv_ms != CONV_NEVER && m->conv_elapsed >= m->conv_ms) {
            m->converting = 0;
            memcpy(m->sp, m->sp_after, sizeof(m->sp));
            return 1u;
        }
        return 0u;
    }
    return 1u;   /* лінію ніхто не тримає — pull-up */
}

static void mock_delay_ms(void *io, uint32_t ms)
{
    MockDs *m = io;
    m->conv_elapsed += ms;
    m->delay_total_ms += ms;
}

static const Ds18b20_Ops mock_ops = {
    mock_reset, mock_write_bit, mock_read_bit, mock_delay_ms
};

/* Здоровий датчик: відповідає завжди, конверсія 600 мс, scratchpad до неї — POR. */
static void mock_init(MockDs *m, int16_t raw_after)
{
    memset(m, 0, sizeof(*m));
    m->presence_resets = 1000;
    m->drives_conversion = 1;
    m->conv_ms = 600u;
    build_sp(m->sp, (int16_t)DS18B20_POR_TEMP_RAW, 0x7F);
    build_sp(m->sp_after, raw_after, 0x7F);
}

static int log_has(const MockDs *m, uint16_t ev)
{
    for (unsigned i = 0; i < m->log_len && i < sizeof(m->log) / sizeof(m->log[0]); i++) {
        if (m->log[i] == ev) { return 1; }
    }
    return 0;
}

/* Повна транзакція: порядок команд за datasheet'ом і зимовий градус на виході. */
static void test_txn_happy_path_sequence(void)
{
    MockDs m;
    mock_init(&m, (int16_t)0xFF5E);                 /* −10.125 °C */
    int32_t t = 0;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);

    const uint16_t want[] = { EV_RESET, 0xCC, 0x44, EV_RESET, 0xCC, 0xBE };
    int seq_ok = m.log_len == sizeof(want) / sizeof(want[0]);
    for (unsigned i = 0; seq_ok && i < m.log_len; i++) { seq_ok = m.log[i] == want[i]; }

    CHECK(rc == DS18B20_OK, "здоровий датчик не дав DS18B20_OK");
    CHECK(t == -1013, "−10.125 °C декодовано не в −1013");
    CHECK(!m.unknown_cmd, "мок не впізнав команду — байти йдуть не молодшим бітом першим?");
    CHECK(seq_ok, "журнал ≠ reset·CC·44·reset·CC·BE");
    CHECK(m.delay_total_ms >= 600u && m.delay_total_ms <= 750u,
          "чекання не дорівнює тривалості конверсії в межах t_CONV,max");
}

/* Немає presence → «датчик не відповів», і в тишу не пишеться жоден байт. */
static void test_txn_no_presence(void)
{
    MockDs m;
    mock_init(&m, 0x0191);
    m.presence_resets = 0;
    int32_t t = 12345;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_ERR_NO_PRESENCE, "відсутній датчик не дав ERR_NO_PRESENCE");
    CHECK(t == DS18B20_TEMP_UNKNOWN, "відсутній датчик лишив викликачеві число");
    CHECK(m.log_len == 1u && m.log[0] == EV_RESET, "після тиші на reset у лінію пішли байти");
}

/* Presence зник між конверсією й читанням → та сама відмова, не scratchpad. */
static void test_txn_presence_lost_before_read(void)
{
    MockDs m;
    mock_init(&m, 0x0191);
    m.presence_resets = 1;
    int32_t t = 0;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_ERR_NO_PRESENCE, "зниклий на другому reset датчик не дав ERR_NO_PRESENCE");
    CHECK(t == DS18B20_TEMP_UNKNOWN, "зниклий датчик віддав градус");
    CHECK(!log_has(&m, 0xBE), "Read Scratchpad пішов у тишу");
}

/* 🚨 POR без конверсії: лінію ніхто не тримає, scratchpad = +85.00 → сентинел. */
static void test_txn_por_without_conversion(void)
{
    MockDs m;
    mock_init(&m, 0x0191);
    m.drives_conversion = 0;                        /* sp лишається POR */
    int32_t t = 0;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_ERR_UNCONFIRMED, "«1» на першому слоті прийнято за готовність");
    CHECK(t == DS18B20_TEMP_UNKNOWN, "power-on +85.00 віддано як ГРАДУС — це фабрикація");
    CHECK(!log_has(&m, 0xBE), "непідтверджений scratchpad усе одно читали");
}

/* Те саме з НЕ-POR вмістом: декодер окремо його б пропустив, шар — ні,
 * бо градус минулого циклу без видимої конверсії так само не є виміром. */
static void test_txn_stale_value_without_conversion(void)
{
    MockDs m;
    mock_init(&m, 0x0191);
    m.drives_conversion = 0;
    build_sp(m.sp, 0x0191, 0x7F);                   /* +25.06 від минулого разу */
    int32_t t = 0;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_ERR_UNCONFIRMED, "застарілий scratchpad без конверсії не відхилено");
    CHECK(t == DS18B20_TEMP_UNKNOWN, "градус минулого циклу віддано як свіжий");
}

/* Справжні +85.00 після ПОБАЧЕНОЇ конверсії — вимір, сентинел їх не ковтає. */
static void test_txn_real_85_after_conversion(void)
{
    MockDs m;
    mock_init(&m, (int16_t)DS18B20_POR_TEMP_RAW);
    int32_t t = 0;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_OK && t == 8500, "справжні +85.00 після конверсії не пройшли");
}

/* Конверсія не закінчується → таймаут рівно на t_CONV,max, scratchpad не читається. */
static void test_txn_conversion_timeout(void)
{
    MockDs m;
    mock_init(&m, 0x0191);
    m.conv_ms = CONV_NEVER;
    int32_t t = 0;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_ERR_TIMEOUT, "вічна конверсія не дала ERR_TIMEOUT");
    CHECK(t == DS18B20_TEMP_UNKNOWN, "після таймауту віддано градус");
    CHECK(m.delay_total_ms == 750u, "бюджет очікування ≠ t_CONV,max 12 біт (750 мс)");
    CHECK(!log_has(&m, 0xBE), "після таймауту читали scratchpad");
}

/* CRC-брак і німа лінія під час читання scratchpad'а → сентинел. */
static void test_txn_crc_reject(void)
{
    MockDs m;
    mock_init(&m, 0x0191);
    m.sp_after[DS18B20_SP_CRC] ^= 0xFFu;
    int32_t t = 0;
    int rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_ERR_CRC && t == DS18B20_TEMP_UNKNOWN, "зіпсований CRC пройшов як вимір");

    mock_init(&m, 0x0191);
    memset(m.sp_after, 0xFF, sizeof(m.sp_after));
    rc = Ds18b20_Read_Centi_C(&mock_ops, &m, &t);
    CHECK(rc == DS18B20_ERR_CRC && t == DS18B20_TEMP_UNKNOWN, "німа лінія (0xFF×9) віддала градус");
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

    printf("\n=== [HW.16] DS18B20 1-Wire transaction over a mock bus (host) ===\n");
    RUN(test_txn_happy_path_sequence);
    RUN(test_txn_no_presence);
    RUN(test_txn_presence_lost_before_read);
    RUN(test_txn_por_without_conversion);
    RUN(test_txn_stale_value_without_conversion);
    RUN(test_txn_real_85_after_conversion);
    RUN(test_txn_conversion_timeout);
    RUN(test_txn_crc_reject);

    printf("\n  passed: %d, failed: %d\n\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
