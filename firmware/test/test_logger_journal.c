// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_logger_journal.c — [FW.70] host-тести сторінкового журналу логера П3.
 *
 * RAM-мок N сторінок × 256 dw + fault-injection program/erase. Доводить: стерте ⊥
 * валідне; пара в одному dw; явний слот (пропуск не зсуває міток); розриви → якір;
 * кільце губить НАЙСТАРІШЕ; монтування після скиду; 180 діб на 18 сторінках без втрат;
 * заголовок сторінки з CRC-8 — напівстерта сторінка не монтується й не йде в дамп, брудна після
 * стирання — мертва, серія мертвих стирань не обертає 8-бітний seq;
 * якір BOOT лягає перед першим записом старту, і петля скидів без запису Flash не торкається;
 * консоль (logger_console.h): виставлення часу судить перечитування, дамп = стан + записи.
 *
 * Build: make -C firmware/test logger_journal
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../common/logger_journal.h"
#include "../common/logger_console.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) static void name(void)
#define RUN(name) do { \
    int _f = tests_failed; \
    printf("  %-58s", #name); \
    name(); \
    if (tests_failed == _f) { printf(" ✅\n"); tests_passed++; } \
} while (0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) { \
        printf(" ❌ FAIL (line %d: got %lld, expected %lld)\n", __LINE__, _a, _b); \
        tests_failed++; return; \
    } \
} while (0)
#define ASSERT_TRUE(e)  ASSERT_EQ(!!(e), 1)
#define ASSERT_STR(a, b) do { \
    if (strcmp((a), (b)) != 0) { \
        printf(" ❌ FAIL (line %d: got \"%s\", expected \"%s\")\n", __LINE__, (a), (b)); \
        tests_failed++; return; \
    } \
} while (0)

/* ── RAM-мок ───────────────────────────────────────────────────────── */
#define PG_DWS   256u
#define MAX_PG   18u

typedef struct {
    uint64_t mem[MAX_PG][PG_DWS];
    int      erases[MAX_PG];
    int      programs;
    int      fail_program_at;   /* -1 = ніколи; інакше відмова, починаючи з цього номера програмування */
    int      fail_program_n;    /* скільки програмувань поспіль відмовляють (за замовчуванням 1) */
    int      fail_erase_page;   /* -1 = ніколи */
    uint32_t fail_erase_mask;   /* біт p = відмовляє стирання сторінки p */
    int      dirty_erase_page;  /* -1 = ніколи; інакше стирання «вдається», але лишає нестертий dw */
    int      reprogram_errors;  /* спроби програмувати НЕстертий dw (на WL — PROGERR) */
} Mock;

static Mock M;

static void mock_init(void)
{
    memset(M.mem, 0xFF, sizeof M.mem);
    memset(M.erases, 0, sizeof M.erases);
    M.programs = 0; M.fail_program_at = -1; M.fail_program_n = 1; M.fail_erase_page = -1; M.reprogram_errors = 0;
    M.fail_erase_mask = 0; M.dirty_erase_page = -1;
}
static uint64_t m_read(void *io, uint32_t off)
{
    (void)io; uint32_t dw = off / 8u;
    return M.mem[dw / PG_DWS][dw % PG_DWS];
}
static int m_program(void *io, uint32_t off, uint64_t v)
{
    (void)io; uint32_t dw = off / 8u;
    uint64_t *cell = &M.mem[dw / PG_DWS][dw % PG_DWS];
    int n = M.programs++;
    if (*cell != UINT64_MAX) { M.reprogram_errors++; return 0; }
    if (M.fail_program_at >= 0 && n >= M.fail_program_at && n < M.fail_program_at + M.fail_program_n)
        return 0;                                      /* dw лишився стертим */
    *cell = v;
    return 1;
}
static int m_erase(void *io, uint8_t page)
{
    (void)io;
    if (((M.fail_erase_mask >> page) & 1u) || (int)page == M.fail_erase_page) return 0;
    memset(M.mem[page], 0xFF, sizeof M.mem[page]);
    if ((int)page == M.dirty_erase_page) M.mem[page][PG_DWS / 2u] = 0xFFFFFFFF7FFFFFFFull; /* один біт не підвівся */
    M.erases[page]++;
    return 1;
}
static const LogJOps OPS = { m_read, m_program, m_erase };

#define CAD   30u
#define CAD_S (CAD * 60u)
#define T0    1764000000u   /* грудень 2025 — довільна точка з виставленим часом */

/* Зібрати всі виміри дампу (і порахувати якорі). */
typedef struct { uint32_t t[20000]; uint16_t r[20000]; int8_t c[20000]; int n; int anchors; int corrupt; } Dump;
static Dump D;
static void dump(const LogJ *j)
{
    LogJIter it; LogJRec r;
    D.n = 0; D.anchors = 0; D.corrupt = 0;
    LogJ_Iter_Begin(&it, j);
    while (LogJ_Iter_Next(&it, &r)) {
        if (r.kind == LOGJ_REC_MEAS) { D.t[D.n] = r.t_s; D.r[D.n] = r.reading; D.c[D.n] = r.temp; D.n++; }
        else if (r.kind == LOGJ_REC_ANCHOR) D.anchors++;
        else D.corrupt++;
    }
}

/* ── тести ─────────────────────────────────────────────────────────── */

TEST(test_valid_record_is_never_erased_pattern)
{
    ASSERT_TRUE(LogJ_Pack_Data(LOGJ_SLOT_MAX, 0xFFFF, -1, 0xFFFF, -1) != UINT64_MAX);
    ASSERT_TRUE(LogJ_Pack_Anchor(LOGJ_TYPE_RESUME, 0xF, 0xFF, 0xFFFF, 0xFFFFFFFFu) != UINT64_MAX);
    ASSERT_EQ(LogJ_Type(UINT64_MAX), 0xF);
    ASSERT_EQ(LogJ_Type(LogJ_Pack_Data(7, 1, 2, 3, 4)), LOGJ_TYPE_DATA);
}

TEST(test_data_pack_layout_roundtrip)
{
    uint64_t dw = LogJ_Pack_Data(0x0ABC, 0x1234, -25, 0xBEEF, 63);
    ASSERT_EQ((dw >> 48) & 0xFFF, 0xABC);
    ASSERT_EQ((uint16_t)dw, 0x1234);
    ASSERT_EQ((int8_t)(uint8_t)(dw >> 16), -25);
    ASSERT_EQ((uint16_t)(dw >> 24), 0xBEEF);
    ASSERT_EQ((int8_t)(uint8_t)(dw >> 40), 63);
}

TEST(test_temp_from_centi_rounds_and_clamps)
{
    ASSERT_EQ(LogJ_Temp_From_Centi(0), 0);
    ASSERT_EQ(LogJ_Temp_From_Centi(2549), 51);      /* 25.49 °C → 25.5 */
    ASSERT_EQ(LogJ_Temp_From_Centi(2524), 50);      /* 25.24 → 25.0 */
    ASSERT_EQ(LogJ_Temp_From_Centi(-1226), -25);    /* −12.26 → −12.5 */
    ASSERT_EQ(LogJ_Temp_From_Centi(-4000), -80);    /* −40 °C */
    ASSERT_EQ(LogJ_Temp_From_Centi(8500), 127);     /* стеля, не сентинел */
    ASSERT_EQ(LogJ_Temp_From_Centi(-9000), -127);
    ASSERT_TRUE(LogJ_Temp_From_Centi(-2147483647) != LOGJ_TEMP_NONE);
}

TEST(test_fresh_mount_is_empty_and_first_anchor_opens_page0)
{
    mock_init();
    LogJ j;
    ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD), 0);
    dump(&j); ASSERT_EQ(D.n + D.anchors, 0);
    ASSERT_TRUE(LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1));
    ASSERT_EQ(LogJ_Type(M.mem[0][0]), LOGJ_TYPE_PAGE);
    ASSERT_TRUE(logj_page_ok(M.mem[0][0]));
    ASSERT_EQ(logj_page_seq(M.mem[0][0]), 0);                 /* seq 0 */
    ASSERT_EQ(LogJ_Type(M.mem[0][1]), LOGJ_TYPE_RESUME);
    ASSERT_EQ((uint16_t)(M.mem[0][1] >> 32), (LOGJ_REASON_BOOT << 8) | 1);
    ASSERT_EQ((uint32_t)M.mem[0][1], T0);
    ASSERT_EQ(M.mem[0][2], UINT64_MAX);
}

TEST(test_two_measurements_share_one_dword)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    ASSERT_TRUE(LogJ_Record(&j, T0, 1000, 10));
    ASSERT_EQ(M.mem[0][2], UINT64_MAX);                       /* A чекає в RAM */
    ASSERT_TRUE(LogJ_Record(&j, T0 + CAD_S + 7, 1001, -3));   /* 7 с дрейфу — той самий слот */
    ASSERT_EQ(M.mem[0][2], LogJ_Pack_Data(0, 1000, 10, 1001, -3));
    dump(&j);
    ASSERT_EQ(D.n, 2);
    ASSERT_EQ(D.t[0], T0); ASSERT_EQ(D.t[1], T0 + CAD_S);
    ASSERT_EQ(D.r[1], 1001); ASSERT_EQ(D.c[1], -3);
}

TEST(test_skipped_wake_keeps_later_timestamps_exact)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    LogJ_Record(&j, T0, 1, 0);
    LogJ_Record(&j, T0 + 3 * CAD_S, 2, 0);                    /* слоти 1–2 пропущено */
    LogJ_Record(&j, T0 + 4 * CAD_S, 3, 0);
    dump(&j);
    ASSERT_EQ(D.n, 3);                                        /* пропуск — без вигаданого рядка */
    ASSERT_EQ(D.t[0], T0);                 ASSERT_EQ(D.r[0], 1);
    ASSERT_EQ(D.t[1], T0 + 3 * CAD_S);     ASSERT_EQ(D.r[1], 2);
    ASSERT_EQ(D.t[2], T0 + 4 * CAD_S);     ASSERT_EQ(D.r[2], 3);
    ASSERT_EQ(D.anchors, 2);                                  /* жодного зайвого якоря */
}

TEST(test_clock_backwards_and_same_slot_write_gap_anchor)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    LogJ_Record(&j, T0, 1, 0);
    LogJ_Record(&j, T0 + 60, 2, 0);                           /* той самий слот */
    LogJ_Record(&j, T0 - 5000, 3, 0);                         /* годинник назад */
    LogJ_Record(&j, T0 - 5000 + CAD_S, 4, 0);
    dump(&j);
    ASSERT_EQ(D.anchors, 4);                                  /* сторінка · boot · два GAP */
    ASSERT_EQ(D.n, 4);                                        /* обірвані пари — без рядків NA */
    ASSERT_EQ(D.t[0], T0); ASSERT_EQ(D.r[0], 1);
    ASSERT_EQ(D.t[1], T0 + 60); ASSERT_EQ(D.r[1], 2);
    ASSERT_EQ(D.t[2], T0 - 5000); ASSERT_EQ(D.r[2], 3);
    ASSERT_EQ(D.t[3], T0 - 5000 + CAD_S); ASSERT_EQ(D.r[3], 4);
}

TEST(test_slot_overflow_writes_gap_anchor)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    uint32_t far = T0 + (LOGJ_SLOT_MAX + 10u) * CAD_S;        /* ≈ 85 діб мовчання без скиду */
    LogJ_Record(&j, far, 7, 0);
    LogJ_Record(&j, far + CAD_S, 8, 0);
    dump(&j);
    ASSERT_EQ(D.n, 2);
    ASSERT_EQ(D.t[0], far); ASSERT_EQ(D.t[1], far + CAD_S);
    ASSERT_EQ(D.anchors, 3);
}

TEST(test_page_rotation_keeps_time_continuous)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 2u) * 2 + 6;                       /* переповнити сторінку 0 */
    for (int i = 0; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    ASSERT_EQ(LogJ_Type(M.mem[1][0]), LOGJ_TYPE_PAGE);
    ASSERT_EQ(logj_page_seq(M.mem[1][0]), 1);                 /* seq 1 */
    dump(&j);
    ASSERT_EQ(D.n, n);
    for (int i = 0; i < n; i++) { ASSERT_EQ(D.t[i], T0 + (uint32_t)i * CAD_S); ASSERT_EQ(D.r[i], i); }
}

TEST(test_ring_drops_oldest_keeps_newest)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 3, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = 4 * (int)(PG_DWS - 1u) * 2;                       /* більше, ніж уміщають 3 сторінки */
    for (int i = 0; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    dump(&j);
    ASSERT_TRUE((uint32_t)D.n >= LOGJ_GUARANTEED_MEAS(3u, PG_DWS));
    ASSERT_EQ(D.r[D.n - 1], n - 1);                           /* n парне — усі пари закриті */
    for (int i = 1; i < D.n; i++) ASSERT_EQ(D.t[i], D.t[i - 1] + CAD_S);
    ASSERT_EQ(D.r[0], n - D.n);                               /* перший = найстаріший уцілілий */
    LogJ_Record(&j, T0 + (uint32_t)n * CAD_S, 0xAAAA, 0);     /* непарний — чекає в RAM, у дамп не входить */
    dump(&j);
    ASSERT_EQ(D.r[D.n - 1], n - 1);
}

TEST(test_mount_after_reset_resumes_mid_page)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    for (int i = 0; i < 9; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    /* скид: RAM зникла, вимір 8 (непарний) загинув із нею */
    LogJ k;
    ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
    ASSERT_EQ(k.widx, 2 + 4);
    uint32_t t = T0 + 10u * CAD_S;
    ASSERT_TRUE(LogJ_Anchor(&k, t, 1, LOGJ_REASON_BOOT, 4));  /* IWDG */
    LogJ_Record(&k, t, 100, 0);
    LogJ_Record(&k, t + CAD_S, 101, 0);
    ASSERT_EQ(M.reprogram_errors, 0);
    dump(&k);
    ASSERT_EQ(D.n, 8 + 2);
    ASSERT_EQ(D.r[7], 7); ASSERT_EQ(D.t[8], t); ASSERT_EQ(D.r[9], 101);
}

TEST(test_mount_recovers_last_slot_so_replay_is_a_gap)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    for (int i = 0; i < 4; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);
    /* без якоря відновлення (порушення протоколу) повтор слота 1 не перепише минуле */
    LogJ_Record(&k, T0 + CAD_S, 50, 0);
    LogJ_Record(&k, T0 + 2 * CAD_S, 51, 0);
    ASSERT_EQ(M.reprogram_errors, 0);
    dump(&k);
    ASSERT_EQ(D.r[0], 0); ASSERT_EQ(D.r[3], 3);
    ASSERT_EQ(D.anchors, 3);
}

TEST(test_mount_skips_hole_left_by_failed_program)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    LogJ_Record(&j, T0, 1, 0);
    M.fail_program_at = M.programs;                           /* наступне програмування — відмова */
    ASSERT_EQ(LogJ_Record(&j, T0 + CAD_S, 2, 0), 0);
    ASSERT_EQ(j.write_fail, 1);
    LogJ_Record(&j, T0 + 2 * CAD_S, 3, 0);
    LogJ_Record(&j, T0 + 3 * CAD_S, 4, 0);
    ASSERT_EQ(M.mem[0][2], UINT64_MAX);                       /* дірка */
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);
    ASSERT_EQ(k.widx, 4);                                     /* за останнім непорожнім, не на дірці */
    LogJ_Anchor(&k, T0 + 5 * CAD_S, 1, LOGJ_REASON_BOOT, 1);
    ASSERT_EQ(M.reprogram_errors, 0);
    dump(&k);
    ASSERT_EQ(D.n, 2);
    ASSERT_EQ(D.t[0], T0 + 2 * CAD_S); ASSERT_EQ(D.r[1], 4);
}

/* [FW.70] Скид посеред програмування лишає dw, що на WL читається з ECC double error і NMI;
 * глю віддає його як LOGJ_UNREADABLE_DW (common/flash_eccd.h). Двійник дірки від відмови. */
TEST(test_unreadable_dw_is_corrupt_in_dump_and_never_reprogrammed)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    for (int i = 0; i < 4; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    M.mem[0][j.widx] = LOGJ_UNREADABLE_DW;                    /* скид посеред наступної пари */
    LogJ k;
    ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
    ASSERT_EQ(k.widx, j.widx + 1);                            /* за нечитабельним, не на ньому */
    uint32_t t = T0 + 6u * CAD_S;
    LogJ_Arm_Boot(&k, 4, 1);
    LogJ_Record(&k, t, 100, 0);
    LogJ_Record(&k, t + CAD_S, 101, 0);
    ASSERT_EQ(M.reprogram_errors, 0);
    dump(&k);
    ASSERT_EQ(D.corrupt, 1);
    ASSERT_EQ(D.n, 4 + 2);
    ASSERT_EQ(D.r[3], 3); ASSERT_EQ(D.t[4], t); ASSERT_EQ(D.r[5], 101);
    LogJIter it; LogJRec r; char line[LOGJ_FORMAT_CAP];
    LogJ_Iter_Begin(&it, &k);
    while (LogJ_Iter_Next(&it, &r) && r.kind != LOGJ_REC_CORRUPT) { }
    ASSERT_EQ(r.kind, LOGJ_REC_CORRUPT);
    ASSERT_TRUE(LogJ_Format(line, sizeof line, &r) > 0);
    ASSERT_STR(line, "#X,0000000000000000\n");
}

/* Сторінку стерто під відкриття, а скид обірвав програмування її заголовка: такий заголовок
 * не стає сторінкою, а наступне відкриття стирає її знову, не пише поверх. Поточна сторінка —
 * на межі seq (0xFF): справжній наступний заголовок мав би seq 0, тобто стоїть там само, де
 * нуль від глю, і лише тут журнал, що прийняв би 0 за заголовок, взяв би рядок за найновішу. */
TEST(test_unreadable_page_header_is_not_mounted_and_is_erased_before_reuse)
{
    mock_init();
    M.mem[0][0] = LogJ_Pack_Page(LOGJ_FLAG_TIME_VALID, CAD, 0xFFu, T0);
    LogJ j;
    ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD), 1);
    for (uint32_t i = 0; j.widx < PG_DWS; i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    M.mem[1][0] = LOGJ_UNREADABLE_DW;
    LogJ k;
    ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
    ASSERT_EQ(k.cur, 0); ASSERT_EQ(k.seq, 0xFF); ASSERT_EQ(k.widx, PG_DWS);
    int e1 = M.erases[1];
    ASSERT_TRUE(LogJ_Anchor(&k, T0 + 600u * CAD_S, 1, LOGJ_REASON_BOOT, 4));
    ASSERT_EQ(M.erases[1], e1 + 1);
    ASSERT_EQ(LogJ_Type(M.mem[1][0]), LOGJ_TYPE_PAGE);
    ASSERT_EQ(logj_page_seq(M.mem[1][0]), 0);                 /* 0xFF + 1 */
    ASSERT_EQ(M.reprogram_errors, 0);
}

TEST(test_erase_failure_moves_to_next_page)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    M.fail_erase_page = 0;
    ASSERT_TRUE(LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1)); /* мертва сторінка 0 — друга спроба */
    ASSERT_EQ(j.write_fail, 1);
    ASSERT_EQ(LogJ_Type(M.mem[1][0]), LOGJ_TYPE_PAGE);
    ASSERT_EQ(logj_page_seq(M.mem[1][0]), 1);                 /* seq зрушив і на відмові */
    LogJ_Record(&j, T0 + CAD_S, 9, 0);
    LogJ_Record(&j, T0 + 2 * CAD_S, 10, 0);
    dump(&j);
    ASSERT_EQ(D.n, 2); ASSERT_EQ(D.r[1], 10);
}

TEST(test_time_set_anchor_marks_validity)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, 1000, 0, LOGJ_REASON_BOOT, 1);            /* RTC не виставлено */
    LogJ_Record(&j, 1000, 1, 0);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_TIME_SET, 0);
    LogJ_Record(&j, T0, 2, 0);
    LogJ_Record(&j, T0 + CAD_S, 3, 0);
    LogJIter it; LogJRec r; int meas = 0, valid = 0;
    LogJ_Iter_Begin(&it, &j);
    while (LogJ_Iter_Next(&it, &r))
        if (r.kind == LOGJ_REC_MEAS) { meas++; valid += r.time_valid; }
    ASSERT_EQ(meas, 3); ASSERT_EQ(valid, 2);                  /* пару до виставлення обірвано — без NA */
}

TEST(test_format_lines)
{
    char b[64];
    LogJRec r = {0};
    r.kind = LOGJ_REC_MEAS; r.t_s = 1764000000u; r.time_valid = 1; r.reading = 31207; r.temp = -25;
    LogJ_Format(b, sizeof b, &r); ASSERT_STR(b, "1764000000,1,31207,-12.5\n");
    r.reading = LOGJ_READING_NONE; r.temp = LOGJ_TEMP_NONE; r.time_valid = 0;
    LogJ_Format(b, sizeof b, &r); ASSERT_STR(b, "1764000000,0,NA,NA\n");
    r.reading = 0; r.temp = 7;
    LogJ_Format(b, sizeof b, &r); ASSERT_STR(b, "1764000000,0,0,3.5\n");
    LogJRec a = {0};
    a.kind = LOGJ_REC_ANCHOR; a.type = LOGJ_TYPE_RESUME; a.tag = (LOGJ_REASON_BOOT << 8) | 4;
    a.t_s = 42; a.time_valid = 1; a.cad_min = 30;
    LogJ_Format(b, sizeof b, &a); ASSERT_STR(b, "#R,0,4,42,1,30\n");
    a.type = LOGJ_TYPE_PAGE; a.tag = 17;
    LogJ_Format(b, sizeof b, &a); ASSERT_STR(b, "#P,17,42,1,30\n");
    LogJRec x = {0}; x.kind = LOGJ_REC_CORRUPT; x.raw = 0x0123456789abcdefULL;
    LogJ_Format(b, sizeof b, &x); ASSERT_STR(b, "#X,0123456789abcdef\n");
    r.reading = 31207; r.temp = -25; r.time_valid = 1;
    ASSERT_EQ(LogJ_Format(b, LOGJ_FORMAT_CAP, &r), strlen("1764000000,1,31207,-12.5\n"));
    ASSERT_EQ(LogJ_Format(b, LOGJ_FORMAT_CAP - 1u, &r), 0);
    a.type = LOGJ_TYPE_RESUME; a.tag = 0xFFFF; a.t_s = UINT32_MAX; a.cad_min = 255;
    ASSERT_EQ(LogJ_Format(b, LOGJ_FORMAT_CAP, &a), strlen("#R,255,255,4294967295,1,255\n"));
    ASSERT_TRUE(strlen("#R,255,255,4294967295,1,255\n") + 1u <= LOGJ_FORMAT_CAP);
}

TEST(test_corrupt_dword_is_reported_not_swallowed)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    M.mem[0][2] = 0x5000000000000001ULL;                      /* тип 0x5 — не наш */
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);
    dump(&k);
    ASSERT_EQ(D.corrupt, 1);
}

TEST(test_sensor_failure_is_an_NA_row)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    LogJ_Record(&j, T0, LOGJ_READING_NONE, LOGJ_TEMP_NONE);  /* прокинувся, не зміг поміряти */
    LogJ_Record(&j, T0 + CAD_S, 5, 2);
    dump(&j);
    ASSERT_EQ(D.n, 2);
    ASSERT_EQ(D.r[0], LOGJ_READING_NONE); ASSERT_EQ(D.c[0], LOGJ_TEMP_NONE);
    ASSERT_EQ(D.r[1], 5);
}

TEST(test_header_program_failure_pauses_then_resumes_by_itself)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 2u) * 2;                           /* сторінка 0 рівно повна */
    for (int i = 0; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    LogJ_Record(&j, T0 + (uint32_t)n * CAD_S, (uint16_t)n, 0);
    M.fail_program_at = M.programs;                           /* заголовок сторінки 1 — відмова */
    LogJ_Record(&j, T0 + (uint32_t)(n + 1) * CAD_S, (uint16_t)(n + 1), 0);
    ASSERT_EQ(j.write_fail, 1);
    ASSERT_TRUE(LogJ_Holding(&j));                            /* пауза видна, не мімікрує під тишу */
    for (int i = n + 2; i < n + 5; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(!LogJ_Holding(&j));
    ASSERT_EQ(j.cur, 1);                                      /* та сама стерта сторінка — історія не тратиться */
    dump(&j);
    ASSERT_EQ(D.n, n + 2);                                    /* втрачено пару n, n+1 і вимір паузи */
    for (int i = 0; i < n; i++) { ASSERT_EQ(D.t[i], T0 + (uint32_t)i * CAD_S); ASSERT_EQ(D.r[i], i); }
    ASSERT_EQ(D.r[n], n + 3); ASSERT_EQ(D.t[n + 1], T0 + (uint32_t)(n + 4) * CAD_S);
    ASSERT_EQ(M.reprogram_errors, 0);
}

TEST(test_resume_program_failure_keeps_timestamps_true)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    for (int i = 0; i < 96; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);      /* скид через дві доби */
    uint32_t t = T0 + 2u * 86400u + 777u;                     /* не на сітці старого якоря */
    M.fail_program_at = M.programs;                           /* якір відновлення — відмова */
    ASSERT_EQ(LogJ_Anchor(&k, t, 1, LOGJ_REASON_BOOT, 4), 0);
    ASSERT_EQ(k.open, 1);
    ASSERT_EQ(k.cur, 0);                                      /* повтор на тій самій сторінці, без стирання */
    for (int i = 0; i < 4; i++) LogJ_Record(&k, t + (uint32_t)i * CAD_S, (uint16_t)(200 + i), 0);
    dump(&k);
    ASSERT_EQ(D.n, 96 + 4);
    for (int i = 0; i < 4; i++) { ASSERT_EQ(D.t[96 + i], t + (uint32_t)i * CAD_S); ASSERT_EQ(D.r[96 + i], 200 + i); }
    ASSERT_EQ(M.erases[1], 0);
}

TEST(test_resume_double_failure_closes_page_and_dates_stay_true)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    for (int i = 0; i < 96; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);
    uint32_t t = T0 + 2u * 86400u + 777u;
    M.fail_program_at = M.programs; M.fail_program_n = 2;     /* якір і його повтор */
    ASSERT_EQ(LogJ_Anchor(&k, t, 1, LOGJ_REASON_BOOT, 4), 0);
    ASSERT_EQ(k.open, 0);
    for (int i = 0; i < 4; i++) LogJ_Record(&k, t + (uint32_t)i * CAD_S, (uint16_t)(200 + i), 0);
    ASSERT_EQ(k.cur, 1);
    dump(&k);
    ASSERT_EQ(D.n, 96 + 4);
    for (int i = 0; i < 4; i++) { ASSERT_EQ(D.t[96 + i], t + (uint32_t)i * CAD_S); ASSERT_EQ(D.r[96 + i], 200 + i); }
}

TEST(test_resume_failure_after_rotation_erases_nothing_more)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 2u) * 2;                           /* сторінка 0 рівно повна */
    for (int i = 0; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);
    uint32_t t = T0 + (uint32_t)n * CAD_S + 600u;
    M.fail_program_at = M.programs + 1;                       /* заголовок стор. 1 — так, якір — ні */
    ASSERT_EQ(LogJ_Anchor(&k, t, 1, LOGJ_REASON_BOOT, 4), 0);
    ASSERT_EQ(k.open, 1); ASSERT_EQ(k.cur, 1);
    ASSERT_EQ(k.widx, 2);                                     /* заголовок уже якір — без повтору */
    ASSERT_EQ(M.erases[2], 0);                                /* і без стирання */
    LogJ_Record(&k, t, 300, 0);
    LogJ_Record(&k, t + CAD_S, 301, 0);
    dump(&k);
    ASSERT_EQ(D.n, n + 2);
    ASSERT_EQ(D.t[n], t); ASSERT_EQ(D.t[n + 1], t + CAD_S);
}

TEST(test_persistent_program_failure_backs_off_and_recovers_without_reset)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 18, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 2u) * 2 + 9 * (int)(PG_DWS - 1u) * 2;  /* сторінки 0…9 рівно повні */
    int i = 0;
    for (; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    int e0 = 0; for (unsigned p = 0; p < 18; p++) e0 += M.erases[p];
    M.fail_program_at = M.programs; M.fail_program_n = 1000000; /* глю зламано: програмування — ніколи */
    for (int e = i + 4 * 48; i < e; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    int e1 = 0; for (unsigned p = 0; p < 18; p++) e1 += M.erases[p];
    ASSERT_TRUE(e1 - e0 <= 9);                                /* ≈ 6 першої доби, далі одна на добу */
    ASSERT_EQ(M.erases[10], e1 - e0);                         /* і всі — тієї самої сторінки */
    ASSERT_TRUE(LogJ_Holding(&j));
    M.fail_program_at = -1;                                   /* відмова минула — скиду немає */
    for (int e = i + (int)LOGJ_HOLD_MAX + 4; i < e; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(!LogJ_Holding(&j));
    ASSERT_TRUE(j.open);
    dump(&j);
    int hist = 0; for (int q = 0; q < D.n; q++) hist += (D.r[q] < n);
    ASSERT_EQ(hist, n);                                       /* історія сторінок 0…9 ціла */
    ASSERT_TRUE(D.r[D.n - 1] > n);                            /* і запис відновився сам */
    for (int q = 1; q < D.n; q++) ASSERT_TRUE(D.t[q] > D.t[q - 1]);
}

TEST(test_mount_last_slot_honours_closed_half)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    LogJ_Record(&j, T0, 1, 0);
    LogJ_Record(&j, T0 + 3 * CAD_S, 2, 0);                    /* пропуск: A записано з закритою B */
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);
    ASSERT_EQ(k.last_g, T0);                                  /* слот B не існував — не зайнятий */
    LogJ_Record(&k, T0 + CAD_S, 3, 0);
    LogJ_Record(&k, T0 + 2 * CAD_S, 4, 0);
    dump(&k);
    ASSERT_EQ(D.anchors, 2);                                  /* без зайвого якоря розриву */
    ASSERT_EQ(D.n, 3);
    ASSERT_EQ(D.t[1], T0 + CAD_S); ASSERT_EQ(D.t[2], T0 + 2 * CAD_S);
}

TEST(test_erase_failure_mid_pair_keeps_both_halves)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 2u) * 2;
    for (int i = 0; i < n + 1; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    M.fail_erase_page = 1;
    LogJ_Record(&j, T0 + (uint32_t)(n + 1) * CAD_S, (uint16_t)(n + 1), 0);
    dump(&j);
    ASSERT_EQ(D.n, n + 2);
    ASSERT_EQ(D.r[n], n); ASSERT_EQ(D.r[n + 1], n + 1);
    ASSERT_EQ(j.cur, 2);
}

TEST(test_stale_page_after_erase_failure_is_not_dumped)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 3, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int per = (int)(PG_DWS - 1u) * 2, i = 0;
    for (; i < per * 3 - 2; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    M.fail_erase_page = 0;                                    /* повернення на сторінку 0 — відмова */
    for (int e = i + 40; i < e; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    ASSERT_EQ(LogJ_Type(M.mem[0][0]), LOGJ_TYPE_PAGE);        /* стара сторінка 0 лишилась */
    dump(&j);
    for (int q = 1; q < D.n; q++) ASSERT_TRUE(D.t[q] > D.t[q - 1]);
    ASSERT_TRUE(D.r[0] >= 508);                               /* стара сторінка 0 несла 0…507 — у дамп не йде */
}

TEST(test_mount_picks_newest_across_seq_wrap)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    j.seq = 0xFCu;                                            /* наступне відкриття — seq 0xFD */
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 1u) * 2 * 4;                       /* FE · FF · 00 і знову стор. 0 = 01 */
    for (int i = 0; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    ASSERT_EQ(logj_page_seq(M.mem[3][0]), 0x00);
    ASSERT_EQ(logj_page_seq(M.mem[0][0]), 0x01);
    LogJ k;
    ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
    ASSERT_EQ(k.cur, 0); ASSERT_EQ(k.seq, 1);                 /* найновіша — НИЖЧА за номером */
    dump(&k);
    for (int q = 1; q < D.n; q++) ASSERT_EQ(D.t[q], D.t[q - 1] + CAD_S);
    ASSERT_EQ(D.r[0], (int)(PG_DWS - 2u) * 2);                /* найстаріша вціліла — сторінка 1 */
    ASSERT_EQ(D.r[D.n - 1], n - 1);
}

/* Заголовок сторінки несе CRC-8: будь-яка зміна 1–3 біт — уже не заголовок (повний перебір,
 * 4 × 43 744 варіанти). Золоте значення пінить кодування на Flash: журнал, записаний пілотом,
 * мусить читатися наступною прошивкою. */
TEST(test_page_header_crc_catches_every_1_to_3_bit_change)
{
    ASSERT_EQ(LogJ_Pack_Page(1u, 30u, 0x5Au, 1764000000u), 0x311E5A2969248100ll);
    const uint64_t hs[4] = { LogJ_Pack_Page(1u, 30u, 0x5Au, 1764000000u),
                             LogJ_Pack_Page(0u, 255u, 0xFFu, UINT32_MAX),
                             LogJ_Pack_Page(0u, 0u, 0u, 0u),
                             LogJ_Pack_Page(1u, 30u, 0u, 946684877u) };
    for (int h = 0; h < 4; h++) {
        ASSERT_TRUE(logj_page_ok(hs[h]));
        for (int a = 0; a < 64; a++) {
            uint64_t ea = 1ull << a;
            ASSERT_TRUE(!logj_page_ok(hs[h] ^ ea));
            for (int b = a + 1; b < 64; b++) {
                uint64_t eb = ea | (1ull << b);
                ASSERT_TRUE(!logj_page_ok(hs[h] ^ eb));
                for (int c = b + 1; c < 64; c++) ASSERT_TRUE(!logj_page_ok(hs[h] ^ eb ^ (1ull << c)));
            }
        }
    }
    ASSERT_TRUE(!logj_page_ok(UINT64_MAX));                   /* стерте й нечитабельне — контракт */
    ASSERT_TRUE(!logj_page_ok(LOGJ_UNREADABLE_DW));           /* валідатора; тут судить нібл типу */
}

/* Голова — сторінка 0 (seq 4), повна; наступне відкриття стирає найстарішу — сторінку 1 (seq 1),
 * і живлення зникає посеред стирання. Дві форми напівстертого заголовка, обидві на моделі
 * «стирання лише піднімає біти»: seq поповз у 5 = «найновіший + 1» — ланцюг seq не відрізнив би
 * його від щойно відкритої сторінки — і в 3, seq живої сторінки 3, яку дамп тоді підмінив би
 * сміттям. Монтування бере справжню голову, дамп сміття не несе, наступне відкриття стирає
 * сторінку 1 знову. */
TEST(test_torn_erase_header_is_not_a_page)
{
    static const uint64_t creep[2]  = { 0x04ull << 40, 0x02ull << 40 };
    static const uint8_t  claims[2] = { 5u, 3u };
    for (int v = 0; v < 2; v++) {
        mock_init();
        LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
        LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
        uint32_t i = 0;
        for (; i < 100000u && !(j.open && j.cur == 0 && j.seq == 4 && j.widx == PG_DWS); i++)
            LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
        ASSERT_EQ(j.cur, 0); ASSERT_EQ(j.widx, PG_DWS);
        uint64_t old = M.mem[1][0];
        ASSERT_TRUE(logj_page_ok(old)); ASSERT_EQ(logj_page_seq(old), 1);
        uint64_t torn = old | creep[v] | 0x00F00F00ull;           /* і секунди піднялись */
        ASSERT_EQ(LogJ_Type(torn), LOGJ_TYPE_PAGE);
        ASSERT_EQ(logj_page_seq(torn), claims[v]);
        ASSERT_TRUE(!logj_page_ok(torn));
        M.mem[1][0] = torn;
        for (uint16_t d = 1; d < PG_DWS; d++)                     /* тіло — частково стерте */
            M.mem[1][d] = (d % 3u == 0u) ? UINT64_MAX : (M.mem[1][d] | 0x0F0000F000F0000Full);

        LogJ k;
        ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
        ASSERT_EQ(k.cur, 0); ASSERT_EQ(k.seq, 4); ASSERT_EQ(k.widx, PG_DWS);
        dump(&k);
        ASSERT_EQ(D.corrupt, 0);                                  /* сміття сторінки 1 у дамп не йде */
        ASSERT_EQ(D.n, (int)(PG_DWS - 1u) * 2 * 3);               /* сторінки 2 · 3 · 0, кожна повна */
        ASSERT_EQ(D.r[D.n - 1], (int)(i - 1u));
        for (int q = 1; q < D.n; q++) ASSERT_EQ(D.t[q], D.t[q - 1] + CAD_S);

        LogJ_Arm_Boot(&k, 4, 1);
        LogJ_Record(&k, T0 + i * CAD_S, (uint16_t)i, 0); i++;
        LogJ_Record(&k, T0 + i * CAD_S, (uint16_t)i, 0); i++;
        ASSERT_TRUE(logj_page_ok(M.mem[1][0]));
        ASSERT_EQ(logj_page_seq(M.mem[1][0]), 5);
        ASSERT_EQ(M.reprogram_errors, 0);
        dump(&k);
        ASSERT_EQ(D.corrupt, 0);
        ASSERT_EQ(D.r[D.n - 1], (int)(i - 1u));
        for (int q = 1; q < D.n; q++) ASSERT_EQ(D.t[q], D.t[q - 1] + CAD_S);
    }
}

/* Скид посеред програмування пари лишив DATA (нібл 0x1) недопрограмованим до ніблю заголовка
 * 0x3. Без CRC монтування взяло б його за якір (секунди — показ виміру) і писало б якір розриву,
 * а дамп датував би від нього все далі на сторінці; з CRC це «#X», а сітка тече далі. */
TEST(test_torn_dw_with_page_nibble_is_corrupt_not_an_anchor)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    for (int i = 0; i < 4; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    uint64_t torn = LogJ_Pack_Data(2, 4, 0, 5, 0) | (0x2ull << 60);
    ASSERT_EQ(LogJ_Type(torn), LOGJ_TYPE_PAGE);
    ASSERT_TRUE(!logj_page_ok(torn));
    M.mem[0][j.widx] = torn;
    LogJ k;
    ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
    ASSERT_EQ(k.widx, j.widx + 1);
    LogJ_Record(&k, T0 + 4u * CAD_S, 4, 0);                   /* та сама сітка, без якоря старту */
    LogJ_Record(&k, T0 + 5u * CAD_S, 5, 0);
    ASSERT_EQ(M.reprogram_errors, 0);
    dump(&k);
    ASSERT_EQ(D.corrupt, 1);
    ASSERT_EQ(D.anchors, 2);                                  /* заголовок + BOOT; розриву немає */
    ASSERT_EQ(D.n, 6);
    for (int q = 1; q < D.n; q++) ASSERT_EQ(D.t[q], D.t[q - 1] + CAD_S);
}

/* Стирання повернуло успіх, а dw лишився нестертим (знос у петлі скидів): заголовок на таку
 * сторінку не лягає — вона мертва, як за відмови стирання. */
TEST(test_erase_that_leaves_a_dirty_dw_is_a_dead_page)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    M.dirty_erase_page = 0;
    ASSERT_TRUE(LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1)); /* брудна сторінка 0 — друга спроба */
    ASSERT_EQ(j.write_fail, 1);
    ASSERT_EQ(M.mem[0][0], UINT64_MAX);                       /* заголовок на брудну не ліг */
    ASSERT_TRUE(logj_page_ok(M.mem[1][0]));
    ASSERT_EQ(logj_page_seq(M.mem[1][0]), 1);                 /* мертва сторінка зсунула seq */
    LogJ_Record(&j, T0 + CAD_S, 9, 0);
    LogJ_Record(&j, T0 + 2 * CAD_S, 10, 0);
    ASSERT_EQ(M.reprogram_errors, 0);
    dump(&j);
    ASSERT_EQ(D.corrupt, 0); ASSERT_EQ(D.n, 2); ASSERT_EQ(D.r[1], 10);
}

/* Мертві всі сторінки, крім голови (0xFF — біля межі 8-бітного seq): без повернення розгортка
 * дійшла б до самої голови, і щойно стирання там спрацює, кільце стерло б найновішу повну
 * сторінку, а seq «голова + n» виніс би з вікна дампу неушкоджені сторінки. З поверненням голова
 * не стирається ніколи, журнал стоїть на паузі, а щойно стирання відновиться — відкривається
 * наступна за головою, і історія голови в дампі ціла. */
TEST(test_dead_erase_streak_never_erases_the_head)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    j.seq = 0xFEu;                                            /* перше відкриття — seq 0xFF */
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    uint32_t i = 0;
    for (; j.widx < PG_DWS; i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    ASSERT_EQ(j.cur, 0); ASSERT_EQ(j.seq, 0xFF);
    int e0 = M.erases[0];
    M.fail_erase_mask = (1u << 1) | (1u << 2) | (1u << 3);   /* голова стирається, решта — ні */
    int holding = 0;
    for (int c = 0; c < 100; c++, i++) {
        LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
        holding |= LogJ_Holding(&j);
        ASSERT_EQ(M.erases[0], e0);                           /* голову не стерто */
        ASSERT_TRUE((uint8_t)(j.seq - 0xFFu) <= 3u);          /* seq не відходить від голови далі n − 1 */
    }
    ASSERT_TRUE(holding);
    ASSERT_TRUE(j.write_fail >= 3u);
    for (int c = 0; c < 200 && !LogJ_Holding(&j); c++, i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(LogJ_Holding(&j));
    ASSERT_EQ(j.cur, 0); ASSERT_EQ(j.seq, 0xFF);              /* повернуто до голови */
    M.fail_erase_mask = 0;                                    /* стирання відновилось */
    for (int c = 0; c < 200 && !j.open; c++, i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(j.open);
    ASSERT_EQ(j.cur, 1); ASSERT_EQ(j.seq, 0x00);
    ASSERT_EQ(M.erases[0], e0);
    LogJ k;
    ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
    ASSERT_EQ(k.cur, 1); ASSERT_EQ(k.seq, 0x00);              /* найновіша — через межу 0xFF → 0x00 */
    dump(&k);
    ASSERT_EQ(D.r[0], 0);                                     /* історія голови в дампі ціла */
    ASSERT_TRUE(D.n >= (int)(PG_DWS - 2u) * 2);
}

/* Серія мертвих стирань скидається вдалим відкриттям: інакше дві короткі серії в різні дні
 * склались би в «мертві всі, крім голови», і журнал став би на паузу при живій наступній сторінці. */
TEST(test_dead_run_resets_after_a_successful_open)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    uint32_t i = 0;
    for (; j.widx < PG_DWS; i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    M.fail_erase_mask = (1u << 1) | (1u << 2);               /* перша серія: дві мертві */
    for (int c = 0; c < 10 && !(j.open && j.cur == 3); c++, i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(j.open); ASSERT_EQ(j.cur, 3); ASSERT_EQ(j.seq, 3);
    M.fail_erase_mask = 0;
    for (; j.widx < PG_DWS; i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    M.fail_erase_mask = 1u << 0;                              /* друга серія: одна мертва */
    uint32_t c0 = i;
    do { LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0); i++; } while (!(j.open && j.cur != 3) && i < c0 + 6u);
    ASSERT_TRUE(j.open);
    ASSERT_EQ(j.cur, 1);
    ASSERT_TRUE(!LogJ_Holding(&j));
}

/* Провал заголовка посеред серії не скидає її: курсор і seq вертаються на попередню мертву
 * сторінку разом із лічильником, тож повернення й далі знаходить саму голову. Якби провал
 * заголовка обнуляв серію, розгортка дорахувала б лише дві мертві з трьох і стерла б голову. */
TEST(test_header_failure_mid_streak_still_rewinds_to_the_head)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    uint32_t i = 0;
    for (; j.widx < PG_DWS; i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    int e0 = M.erases[0];
    M.fail_erase_mask = 1u << 1;                              /* сторінка 1 мертва */
    M.fail_program_at = M.programs;                           /* заголовок сторінки 2 не ляже */
    for (int c = 0; c < 6 && !LogJ_Holding(&j); c++, i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(LogJ_Holding(&j));
    ASSERT_EQ(j.cur, 1);                                      /* повернуто на мертву, не на голову */
    M.fail_program_at = -1;
    M.fail_erase_mask = (1u << 1) | (1u << 2) | (1u << 3);
    int rewound = 0;
    for (int c = 0; c < 300 && !rewound; c++, i++) {
        LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
        ASSERT_EQ(M.erases[0], e0);                           /* голову не стерто */
        rewound = (j.cur == 0 && LogJ_Holding(&j));
    }
    ASSERT_TRUE(rewound);
    ASSERT_EQ(j.seq, 0);
}

/* Порожній журнал, мертві всі сторінки: голови немає, і повернення стає на сторінку n − 1 із
 * seq 255; щойно стирання відновиться, перше відкриття — сторінка 0, seq 0. */
TEST(test_empty_journal_streak_rewinds_and_opens_page_0)
{
    mock_init();
    LogJ j; ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD), 0);
    M.fail_erase_mask = 0xFu;
    ASSERT_TRUE(!LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1));
    uint32_t i = 1;
    for (int c = 0; c < 200 && !LogJ_Holding(&j); c++, i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(LogJ_Holding(&j));
    ASSERT_EQ(j.cur, 3); ASSERT_EQ(j.seq, 255);
    M.fail_erase_mask = 0;
    for (int c = 0; c < 200 && !j.open; c++, i++) LogJ_Record(&j, T0 + i * CAD_S, (uint16_t)i, 0);
    ASSERT_TRUE(j.open);
    ASSERT_EQ(j.cur, 0); ASSERT_EQ(j.seq, 0);
    ASSERT_TRUE(logj_page_ok(M.mem[0][0]));
    ASSERT_EQ(M.reprogram_errors, 0);
}

TEST(test_mount_with_full_open_page_rotates_cleanly)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 2u) * 2;
    for (int i = 0; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD);
    ASSERT_EQ(k.widx, PG_DWS);
    ASSERT_TRUE(LogJ_Anchor(&k, T0 + (uint32_t)n * CAD_S, 1, LOGJ_REASON_BOOT, 1));
    ASSERT_EQ(k.cur, 1);
    ASSERT_EQ(M.reprogram_errors, 0);
}

TEST(test_slots_use_anchor_cadence_not_config)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, 30);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    for (int i = 0; i < 4; i++) LogJ_Record(&j, T0 + (uint32_t)i * 1800u, (uint16_t)i, 0);
    LogJ k; LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, 15);       /* прошивка з іншим каденсом */
    LogJ_Record(&k, T0 + 4u * 1800u, 4, 0);                   /* без якоря — сітка старого */
    LogJ_Record(&k, T0 + 5u * 1800u, 5, 0);
    uint32_t t = T0 + 6u * 1800u;
    LogJ_Anchor(&k, t, 1, LOGJ_REASON_BOOT, 1);
    LogJ_Record(&k, t, 6, 0);
    LogJ_Record(&k, t + 900u, 7, 0);
    dump(&k);
    ASSERT_EQ(D.n, 8);
    for (int q = 1; q < 6; q++) ASSERT_EQ(D.t[q], D.t[q - 1] + 1800u);
    ASSERT_EQ(D.t[7], D.t[6] + 900u);
}

TEST(test_corrupt_zero_cadence_anchor_does_not_divide)
{
    mock_init();
    M.mem[0][0] = LogJ_Pack_Page(1, 0, 0, T0);
    M.mem[0][1] = LogJ_Pack_Data(1, 1, 0, 2, 0);
    LogJ j;
    ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD), 1);
    ASSERT_TRUE(LogJ_Record(&j, T0 + CAD_S, 9, 0));
    ASSERT_TRUE(LogJ_Record(&j, T0 + 2 * CAD_S, 10, 0));
    dump(&j);
    ASSERT_EQ(D.corrupt, 1);                                  /* DATA під якорем без каденсу — видно */
    ASSERT_EQ(D.n, 2);
}

TEST(test_invalid_config_is_refused)
{
    LogJ j;
    ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, LOGJ_PAGES_MAX + 1u, CAD), -1); /* 8-бітний seq */
    ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, 0), -1);
    ASSERT_EQ(LogJ_Record(&j, T0, 1, 0), 0);
    ASSERT_EQ(LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1), 0);
    dump(&j); ASSERT_EQ(D.n + D.anchors, 0);
    ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 1, CAD), -1);
    ASSERT_EQ(LogJ_Mount(&j, NULL, NULL, PG_DWS, 4, CAD), -1);
}

TEST(test_period_drift_reanchors_and_bounds_label_error)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 8, CAD);      /* 8 сторінок — без оберту кільця */
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    const int n = 2000; const uint32_t per = CAD_S + 3u;      /* WUT переармовують після роботи */
    for (int i = 0; i < n; i++) LogJ_Record(&j, T0 + (uint32_t)i * per, (uint16_t)i, 0);
    dump(&j);
    ASSERT_TRUE(D.n >= n - 1);                                /* останній може чекати в RAM */
    ASSERT_EQ(D.r[0], 0);
    ASSERT_TRUE(D.anchors > 3);                               /* розходження стало явним якорем */
    for (int q = 0; q < D.n; q++) {
        uint32_t truth = T0 + (uint32_t)D.r[q] * per;
        uint32_t err = D.t[q] > truth ? D.t[q] - truth : truth - D.t[q];
        ASSERT_TRUE(err <= CAD_S / 4u);
    }
    for (int q = 1; q < D.n; q++) ASSERT_EQ(D.r[q], D.r[q - 1] + 1);  /* жодного виміру не загублено */
}

/* Ретрай стирання маскує «сторінку без заголовка»: вада живе лише тоді, коли відмова
 * заголовка припадає на ОСТАННЮ спробу. Тут перша сторінка не стирається, а на другій
 * падає програмування заголовка — дані після цього мусять лягти на сторінку з якорем. */
TEST(test_header_failure_on_last_attempt_leaves_page_closed)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    int n = (int)(PG_DWS - 2u) * 2;
    for (int i = 0; i < n + 1; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    M.fail_erase_page = 1;
    M.fail_program_at = M.programs;                           /* перше програмування — заголовок сторінки 2 */
    ASSERT_EQ(LogJ_Record(&j, T0 + (uint32_t)(n + 1) * CAD_S, (uint16_t)(n + 1), 0), 0);
    ASSERT_EQ(j.open, 0);
    M.fail_erase_page = -1;
    for (int i = n + 2; i < n + 6; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    dump(&j);
    ASSERT_EQ(D.n, n + 2);                                    /* пара n, n+1 і вимір паузи — втрачено */
    ASSERT_EQ(D.r[n], n + 3); ASSERT_EQ(D.r[n + 1], n + 4);   /* решта — на сторінці з якорем */
    ASSERT_EQ(D.t[n + 1], T0 + (uint32_t)(n + 4) * CAD_S);
}

/* Присуд П3: 180 діб × 48 вимірів на 18 сторінках — без жодної втрати й з точним часом. */
TEST(test_pilot_season_180_days_on_18_pages)
{
    _Static_assert(LOGJ_GUARANTEED_MEAS(18u, 256u) >= 180u * 48u, "18 сторінок не тримають 180 діб");
    _Static_assert(LOGJ_GUARANTEED_MEAS(17u, 256u) <  180u * 48u, "межа: 17 сторінок уже замало");
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 18, CAD);
    LogJ_Anchor(&j, T0, 1, LOGJ_REASON_BOOT, 1);
    const int n = 180 * 48;
    for (int i = 0; i < n; i++)
        LogJ_Record(&j, T0 + (uint32_t)i * CAD_S + (uint32_t)(i % 5), (uint16_t)(i & 0x7FFF), (int8_t)(i % 100 - 50));
    dump(&j);
    ASSERT_EQ(D.n, n);                                        /* n парне — остання пара закрита */
    for (int i = 0; i < n; i++) {
        ASSERT_EQ(D.t[i], T0 + (uint32_t)i * CAD_S);
        ASSERT_EQ(D.r[i], i & 0x7FFF);
        ASSERT_EQ(D.c[i], i % 100 - 50);
    }
    int max_erase = 0;
    for (unsigned p = 0; p < 18; p++) if (M.erases[p] > max_erase) max_erase = M.erases[p];
    ASSERT_EQ(max_erase, 1);                                  /* сезон — одне стирання на сторінку */
    ASSERT_EQ(M.reprogram_errors, 0);
}

/* ── якір BOOT: заряджають на старті, пишуть перед першим записом старту ── */
/* Коди скиду — reset_cause.h: 1 power-on · 2 NRST · 3 software · 4 IWDG · 6 HardFault. */

static int erases_total(void)
{
    int n = 0;
    for (unsigned p = 0; p < MAX_PG; p++) n += M.erases[p];
    return n;
}

/* Теги якорів відновлення в порядку дампу (тег = (причина<<8) | код скиду). */
static int resume_tags(const LogJ *j, uint16_t *tags, uint8_t *tv, int cap)
{
    LogJIter it; LogJRec r; int n = 0;
    LogJ_Iter_Begin(&it, j);
    while (LogJ_Iter_Next(&it, &r))
        if (r.kind == LOGJ_REC_ANCHOR && r.type == LOGJ_TYPE_RESUME && n < cap) {
            tags[n] = r.tag; tv[n] = r.time_valid; n++;
        }
    return n;
}

TEST(test_reset_loop_without_a_write_never_touches_flash)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Arm_Boot(&j, 1, 1);
    for (int i = 0; i < 3; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    int programs = M.programs, erases = erases_total();
    for (int boot = 0; boot < 10000; boot++) {            /* скид за скидом — до першого запису */
        LogJ k;
        ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
        LogJ_Arm_Boot(&k, 3, 1);
    }
    ASSERT_EQ(M.programs, programs);
    ASSERT_EQ(erases_total(), erases);
}

TEST(test_boot_anchor_lands_before_first_measurement_with_reset_code)
{
    mock_init();
    LogJ j; ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD), 0);
    LogJ_Arm_Boot(&j, 6, 1);
    ASSERT_EQ(M.programs, 0);                             /* зарядити ≠ записати */
    LogJ_Record(&j, T0, 10, 2);
    LogJ_Record(&j, T0 + CAD_S, 11, 3);
    char all[256] = "", b[LOGJ_FORMAT_CAP];
    LogJIter it; LogJRec r;
    LogJ_Iter_Begin(&it, &j);
    while (LogJ_Iter_Next(&it, &r)) { LogJ_Format(b, sizeof b, &r); strcat(all, b); }
    ASSERT_STR(all, "#P,0,1764000000,1,30\n#R,0,6,1764000000,1,30\n"
                    "1764000000,1,10,1.0\n1764001800,1,11,1.5\n");
}

TEST(test_boot_anchor_after_reset_carries_its_code_mid_page)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Arm_Boot(&j, 1, 1);
    for (int i = 0; i < 4; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    LogJ k; ASSERT_EQ(LogJ_Mount(&k, &OPS, NULL, PG_DWS, 4, CAD), 1);
    LogJ_Arm_Boot(&k, 4, 1);
    uint32_t t = T0 + 10u * CAD_S;
    LogJ_Record(&k, t, 100, 0);
    LogJ_Record(&k, t + CAD_S, 101, 0);
    uint16_t tags[8]; uint8_t tv[8];
    ASSERT_EQ(resume_tags(&k, tags, tv, 8), 2);
    ASSERT_EQ(tags[0], (LOGJ_REASON_BOOT << 8) | 1);
    ASSERT_EQ(tags[1], (LOGJ_REASON_BOOT << 8) | 4);
    dump(&k);
    ASSERT_EQ(D.n, 4 + 2);
    ASSERT_EQ(D.t[4], t); ASSERT_EQ(D.r[5], 101);
    ASSERT_EQ(M.reprogram_errors, 0);
}

TEST(test_anchor_puts_armed_boot_first_and_keeps_the_newer_validity)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Arm_Boot(&j, 2, 0);                              /* NRST, годинник ще не виставлено */
    ASSERT_TRUE(LogJ_Anchor(&j, T0, 1, LOGJ_REASON_TIME_SET, 0));
    LogJ_Record(&j, T0 + CAD_S, 5, 0);
    LogJ_Record(&j, T0 + 2u * CAD_S, 6, 0);
    uint16_t tags[8]; uint8_t tv[8];
    ASSERT_EQ(resume_tags(&j, tags, tv, 8), 2);
    ASSERT_EQ(tags[0], (LOGJ_REASON_BOOT << 8) | 2);     ASSERT_EQ(tv[0], 0);
    ASSERT_EQ(tags[1], LOGJ_REASON_TIME_SET << 8);         ASSERT_EQ(tv[1], 1);
    LogJIter it; LogJRec r; int meas = 0, valid = 0;
    LogJ_Iter_Begin(&it, &j);
    while (LogJ_Iter_Next(&it, &r))
        if (r.kind == LOGJ_REC_MEAS) { meas++; valid += r.time_valid; }
    ASSERT_EQ(meas, 2); ASSERT_EQ(valid, 2);
}

TEST(test_boot_anchor_gets_one_attempt_and_never_lands_late)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Arm_Boot(&j, 3, 0);
    M.fail_program_at = 0;                                /* перший заголовок не ліг → пауза */
    ASSERT_EQ(LogJ_Record(&j, T0, 1, 0), 0);
    ASSERT_EQ(j.boot_pend, 0);
    ASSERT_EQ(M.erases[0], 1);
    ASSERT_EQ(LogJ_Record(&j, T0 + CAD_S, 1, 0), 0);      /* пауза тримає: тієї ж сторінки не стирає */
    ASSERT_EQ(M.erases[0], 1);
    for (int i = 2; i < 6; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)i, 0);
    uint16_t tags[8]; uint8_t tv[8];
    int n = resume_tags(&j, tags, tv, 8);
    ASSERT_TRUE(n >= 1);
    for (int i = 0; i < n; i++) ASSERT_TRUE((tags[i] >> 8) != LOGJ_REASON_BOOT);
    dump(&j);
    ASSERT_EQ(D.n, 4);                                    /* (2,3) · (4,5); 0 і 1 — у паузі */
    ASSERT_EQ(D.r[0], 2);
}

TEST(test_unmounted_journal_ignores_boot_arming)
{
    mock_init();
    LogJ j; ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 1, CAD), -1);
    LogJ_Arm_Boot(&j, 1, 1);
    ASSERT_EQ(j.boot_pend, 0);
    ASSERT_EQ(LogJ_Settle_Boot(&j, T0), 0);
    ASSERT_EQ(M.programs, 0);
}

/* ── консоль: шов LogCOps на моці годинника й виводу ───────────────── */
#define CLK_2000 946684800u   /* календар RTC після втрати живлення — 2000-01-01 */

static uint32_t CLK;
static int      CLK_FOLLOWS_SET;
static uint32_t CLK_SET_OFFSET;
static char     OUT[16384];
static size_t   OUTN;
static uint32_t c_now(void *io) { (void)io; return CLK; }
static void     c_set(void *io, uint32_t t) { (void)io; if (CLK_FOLLOWS_SET) CLK = t + CLK_SET_OFFSET; }
static void     c_emit(void *io, const char *s, size_t n)
{
    (void)io;
    if (OUTN + n < sizeof OUT) { memcpy(OUT + OUTN, s, n); OUTN += n; OUT[OUTN] = '\0'; }
}
static const LogCOps COPS = { c_now, c_set, c_emit, NULL };

static void console_init(uint32_t clk, int follows, uint32_t offset)
{
    CLK = clk; CLK_FOLLOWS_SET = follows; CLK_SET_OFFSET = offset; OUTN = 0; OUT[0] = '\0';
}
/* Згодувати байти; повертає, скільки разів консоль попросила закрити вікно. */
static int feed(LogJ *j, const char *s)
{
    LogCLine l = {0}; int quits = 0;
    for (; *s; s++)
        if (LogC_Feed(&l, *s)) quits += (LogC_Exec(j, &COPS, NULL, &l) == LOGC_QUIT);
    return quits;
}

TEST(test_console_crlf_and_blank_lines_frame_one_command)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    console_init(T0, 1, 0);
    ASSERT_EQ(feed(&j, "S\r\n\r\n\nq\n"), 1);
    ASSERT_STR(OUT, "#S,1764000000,1,1,0,255,0,0,0\nOK,Q\n");
}

TEST(test_console_time_set_writes_boot_then_time_anchor)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    console_init(CLK_2000 + 77u, 1, 0);
    LogJ_Arm_Boot(&j, 1, 0);
    feed(&j, "T1764000000\n");
    ASSERT_STR(OUT, "OK,T,1764000000,1\n");
    console_init(CLK, 1, 0);
    feed(&j, "D\n");
    ASSERT_STR(OUT, "#S,1764000000,1,1,1,0,3,0,0\n"
                    "#P,0,946684877,0,30\n#R,0,1,946684877,0,30\n#R,1,0,1764000000,1,30\n#E,3\n");
}

TEST(test_console_time_set_is_judged_by_the_reread)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    console_init(CLK_2000, 0, 0);                         /* запис календаря не ліг */
    feed(&j, "T1764000000\n");
    ASSERT_STR(OUT, "ERR,T,946684800\n");
    console_init(CLK_2000, 1, LOGC_SET_SLACK_S + 1u);     /* перечитування втекло вперед */
    feed(&j, "T1764000000\n");
    ASSERT_STR(OUT, "ERR,T,1764000003\n");
    ASSERT_EQ(M.programs, 0);                             /* нічого не заряджено — нічого не записано */
    console_init(CLK_2000, 1, LOGC_SET_SLACK_S);          /* межа допуску — ще правда */
    feed(&j, "T1764000000\n");
    ASSERT_STR(OUT, "OK,T,1764000002,1\n");
}

TEST(test_console_malformed_lines_answer_question_mark_and_write_nothing)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    console_init(T0, 1, 0);
    LogJ_Arm_Boot(&j, 1, 1);
    feed(&j, "T\nT17640x0000\nT99999999999\nT4294967296\nT1599999999\nT4102444800\n"
             "DD\nX\nT 1764000000\n0123456789012345678\n");
    ASSERT_STR(OUT, "?\n?\n?\n?\n?\n?\n?\n?\n?\n?\n");
    ASSERT_EQ(M.programs, 0);
    ASSERT_EQ(j.boot_pend, 1);                            /* жоден рядок не писав — якір чекає */
}

TEST(test_console_dump_is_status_then_every_record_then_count)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Arm_Boot(&j, 1, 1);
    for (int i = 0; i < 5; i++) LogJ_Record(&j, T0 + (uint32_t)i * CAD_S, (uint16_t)(100 + i), 0);
    char want[1024] = "#S,1764009000,1,1,1,0,4,0,0\n", b[LOGJ_FORMAT_CAP];
    LogJIter it; LogJRec r; int rows = 0;
    LogJ_Iter_Begin(&it, &j);
    while (LogJ_Iter_Next(&it, &r)) { LogJ_Format(b, sizeof b, &r); strcat(want, b); rows++; }
    ASSERT_EQ(rows, 6);                                   /* #P · #R · (0,1) · (2,3); вимір 4 у RAM */
    strcat(want, "#E,6\n");
    console_init(T0 + 5u * CAD_S, 1, 0);
    feed(&j, "d\n");
    ASSERT_STR(OUT, want);
}

TEST(test_console_status_reports_the_pause_after_a_program_failure)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    M.fail_program_at = 0;
    LogJ_Arm_Boot(&j, 1, 1);
    LogJ_Record(&j, T0, 1, 0);
    ASSERT_TRUE(LogJ_Holding(&j));
    console_init(T0, 1, 0);
    feed(&j, "S\n");
    ASSERT_STR(OUT, "#S,1764000000,1,1,0,255,0,1,1\n");
}

TEST(test_console_on_unmounted_journal_still_sets_the_clock)
{
    mock_init();
    LogJ j; ASSERT_EQ(LogJ_Mount(&j, &OPS, NULL, PG_DWS, 1, CAD), -1);
    console_init(CLK_2000, 1, 0);
    feed(&j, "T1764000000\nD\n");
    ASSERT_STR(OUT, "OK,T,1764000000,0\n#S,1764000000,1,0,0,0,0,0,0\n#E,0\n");
    ASSERT_EQ(M.programs, 0);
}

TEST(test_console_without_calendar_right_refuses_time_and_writes_nothing)
{
    /* Образ mini: set_time = NULL — календар Солдата є базою delta_t (SEC.42). */
    static const LogCOps RO = { c_now, NULL, c_emit, NULL };
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Arm_Boot(&j, 2, 0);
    console_init(CLK_2000 + 5u, 1, 0);
    LogCLine l = {0};
    for (const char *p = "T1764000000\n"; *p; p++) if (LogC_Feed(&l, *p)) LogC_Exec(&j, &RO, NULL, &l);
    ASSERT_STR(OUT, "ERR,T,946684805\n");
    ASSERT_EQ(CLK, CLK_2000 + 5u);
    ASSERT_EQ(M.programs, 0);
    ASSERT_EQ(j.boot_pend, 1);                            /* відмова — не запис: якір чекає далі */
}

/* M — вимір датчика для стенда (шов measure). */
static LogCMeas MEAS;
static void c_meas(void *io, LogCMeas *m) { (void)io; *m = MEAS; }
static const LogCOps MOPS = { c_now, NULL, c_emit, c_meas };
static void feed_ops(LogJ *j, const LogCOps *ops, const char *s)
{
    LogCLine l = {0};
    for (; *s; s++) if (LogC_Feed(&l, *s)) LogC_Exec(j, ops, NULL, &l);
}

TEST(test_console_measure_prints_one_line_and_never_touches_the_journal)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    LogJ_Arm_Boot(&j, 1, 0);
    console_init(CLK_2000 + 9u, 1, 0);
    MEAS = (LogCMeas){ 19656, 0, 1024000u, 307200u, -1825 };
    feed_ops(&j, &MOPS, "M\nm\n");
    ASSERT_STR(OUT, "#M,946684809,19656,0,1024000,307200,-1825\n"
                    "#M,946684809,19656,0,1024000,307200,-1825\n");
    ASSERT_EQ(M.programs, 0);
    ASSERT_EQ(M.erases[0] + M.erases[1] + M.erases[2] + M.erases[3], 0);
    ASSERT_EQ(j.boot_pend, 1);                            /* вимір для стенда — не запис ряду */
}

TEST(test_console_measure_failure_prints_NA_and_the_code)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    console_init(T0, 1, 0);
    MEAS = (LogCMeas){ LOGJ_READING_NONE, -2, 512000u, 0u, LOGC_T_NONE };
    feed_ops(&j, &MOPS, "M\n");
    ASSERT_STR(OUT, "#M,1764000000,NA,-2,512000,0,NA\n");
    console_init(T0, 1, 0);                               /* крайні значення всіх полів — у буфер */
    MEAS = (LogCMeas){ 65520, INT16_MIN, UINT32_MAX, UINT32_MAX, INT32_MIN + 1 };
    feed_ops(&j, &MOPS, "M\n");
    ASSERT_STR(OUT, "#M,1764000000,65520,-32768,4294967295,4294967295,-2147483647\n");
    ASSERT_EQ(strlen(OUT), 61u);                          /* найдовший можливий рядок … */
    ASSERT_TRUE(strlen(OUT) <= LOGC_M_CAP);               /* … вміщається в буфер консолі */
}

TEST(test_console_without_sensor_refuses_measure)
{
    mock_init();
    LogJ j; LogJ_Mount(&j, &OPS, NULL, PG_DWS, 4, CAD);
    console_init(T0, 1, 0);
    feed(&j, "M\nMM\nM1\n");
    ASSERT_STR(OUT, "ERR,M\n?\n?\n");
    ASSERT_EQ(M.programs, 0);
}

int main(void)
{
    printf("\n[FW.70] logger_journal — сторінковий журнал логера П3\n");
    RUN(test_valid_record_is_never_erased_pattern);
    RUN(test_data_pack_layout_roundtrip);
    RUN(test_temp_from_centi_rounds_and_clamps);
    RUN(test_fresh_mount_is_empty_and_first_anchor_opens_page0);
    RUN(test_two_measurements_share_one_dword);
    RUN(test_skipped_wake_keeps_later_timestamps_exact);
    RUN(test_clock_backwards_and_same_slot_write_gap_anchor);
    RUN(test_slot_overflow_writes_gap_anchor);
    RUN(test_page_rotation_keeps_time_continuous);
    RUN(test_ring_drops_oldest_keeps_newest);
    RUN(test_mount_after_reset_resumes_mid_page);
    RUN(test_mount_recovers_last_slot_so_replay_is_a_gap);
    RUN(test_mount_skips_hole_left_by_failed_program);
    RUN(test_unreadable_dw_is_corrupt_in_dump_and_never_reprogrammed);
    RUN(test_unreadable_page_header_is_not_mounted_and_is_erased_before_reuse);
    RUN(test_erase_failure_moves_to_next_page);
    RUN(test_time_set_anchor_marks_validity);
    RUN(test_format_lines);
    RUN(test_corrupt_dword_is_reported_not_swallowed);
    RUN(test_sensor_failure_is_an_NA_row);
    RUN(test_header_program_failure_pauses_then_resumes_by_itself);
    RUN(test_resume_program_failure_keeps_timestamps_true);
    RUN(test_resume_double_failure_closes_page_and_dates_stay_true);
    RUN(test_resume_failure_after_rotation_erases_nothing_more);
    RUN(test_persistent_program_failure_backs_off_and_recovers_without_reset);
    RUN(test_mount_last_slot_honours_closed_half);
    RUN(test_erase_failure_mid_pair_keeps_both_halves);
    RUN(test_header_failure_on_last_attempt_leaves_page_closed);
    RUN(test_stale_page_after_erase_failure_is_not_dumped);
    RUN(test_mount_picks_newest_across_seq_wrap);
    RUN(test_page_header_crc_catches_every_1_to_3_bit_change);
    RUN(test_torn_erase_header_is_not_a_page);
    RUN(test_torn_dw_with_page_nibble_is_corrupt_not_an_anchor);
    RUN(test_erase_that_leaves_a_dirty_dw_is_a_dead_page);
    RUN(test_dead_erase_streak_never_erases_the_head);
    RUN(test_dead_run_resets_after_a_successful_open);
    RUN(test_header_failure_mid_streak_still_rewinds_to_the_head);
    RUN(test_empty_journal_streak_rewinds_and_opens_page_0);
    RUN(test_mount_with_full_open_page_rotates_cleanly);
    RUN(test_slots_use_anchor_cadence_not_config);
    RUN(test_corrupt_zero_cadence_anchor_does_not_divide);
    RUN(test_invalid_config_is_refused);
    RUN(test_period_drift_reanchors_and_bounds_label_error);
    RUN(test_pilot_season_180_days_on_18_pages);
    RUN(test_reset_loop_without_a_write_never_touches_flash);
    RUN(test_boot_anchor_lands_before_first_measurement_with_reset_code);
    RUN(test_boot_anchor_after_reset_carries_its_code_mid_page);
    RUN(test_anchor_puts_armed_boot_first_and_keeps_the_newer_validity);
    RUN(test_boot_anchor_gets_one_attempt_and_never_lands_late);
    RUN(test_unmounted_journal_ignores_boot_arming);
    printf("\n[FW.70] logger_console — консоль логера П3\n");
    RUN(test_console_crlf_and_blank_lines_frame_one_command);
    RUN(test_console_time_set_writes_boot_then_time_anchor);
    RUN(test_console_time_set_is_judged_by_the_reread);
    RUN(test_console_malformed_lines_answer_question_mark_and_write_nothing);
    RUN(test_console_dump_is_status_then_every_record_then_count);
    RUN(test_console_status_reports_the_pause_after_a_program_failure);
    RUN(test_console_on_unmounted_journal_still_sets_the_clock);
    RUN(test_console_without_calendar_right_refuses_time_and_writes_nothing);
    RUN(test_console_measure_prints_one_line_and_never_touches_the_journal);
    RUN(test_console_measure_failure_prints_NA_and_the_code);
    RUN(test_console_without_sensor_refuses_measure);
    printf("\n  %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed ? 1 : 0;
}
