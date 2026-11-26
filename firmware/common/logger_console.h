// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * logger_console.h — [FW.70] консоль логера П3 через UART: виставити час удома, зчитати
 * журнал біля дерева, поміряти датчик на стенді. Чиста логіка (рядок → команда → відповідь);
 * залізо — LogCOps: годинник, запис календаря, вивід рядка, вимір. Прошивка й host-тести
 * компілюють цей самий код.
 *
 * Коли консоль слухає — справа інтеграції (soldier/main.c): вікно на справжньому старті,
 * тож біля дерева її відкриває кнопка RST mini. Скид коштує ≤ один вимір (половина пари
 * живе в RAM) — і якір BOOT, але лише якщо далі буде запис.
 *
 * Команди — ASCII, рядок закінчується '\r' або '\n', регістр літери не важить:
 *   T<секунди UTC>  виставити календар. Запис судить ПЕРЕЧИТУВАННЯ: годинник мусить показати
 *                   UTC не раніше заданого й не пізніше ніж на LOGC_SET_SLACK_S — тоді якір
 *                   TIME_SET із прапорцем «час виставлено». Заряджений якір BOOT лягає ДО
 *                   запису календаря, тобто зі старим часом, як було на старті.
 *                   «OK,T,<секунди>,<якір записано 0|1>» · «ERR,T,<секунди годинника>».
 *                   Без set_time (NULL) — завжди «ERR,T,…», і журналу T не торкається: у
 *                   Солдата календар — база delta_t, і писати його можна лише разом із
 *                   базою (SEC.42, firmware/common/wall_time.h `Silken_Beacon_Commit`).
 *   D               рядок стану, усі записи журналу (LogJ_Format), «#E,<рядків>».
 *   S               рядок стану.
 *   M               один вимір датчика й температури — «#M,<секунди>,<показ|NA>,<код датчика>,
 *                   <сума збудження>,<сума повзунка>,<°C×100|NA>» (поля сум — pot_dendro.h).
 *                   Журналу НЕ торкається: це рядок для стенда (00_07 HW.54, домашній стенд KTR),
 *                   а не запис ряду. Без measure (NULL) — «ERR,M».
 *   Q               закрити вікно — «OK,Q».
 *   інше            «?».
 * Рядок стану: «#S,<секунди>,<годинник UTC 0|1>,<змонтовано 0|1>,<сторінка відкрита 0|1>,
 *   <seq>,<dw відкритої сторінки, 0 — закрита>,<write_fail>,<пауза 0|1>». Пауза після провалу
 *   програмування (LogJ_Holding) інакше виглядала б у дампі як сіла батарея; seq 8-бітний,
 *   порожнього журналу — 255 (перше відкриття дасть 0).
 *
 * Межі: рядок довший за LOGC_LINE_CAP — «?» (хвіст до кінця рядка відкидається);
 * редагування немає — термінал шле рядок цілком; поясу немає — лише секунди UTC; «UTC» —
 * поріг SILKEN_WALL_UTC_MIN (wall_time.h), а не перевірка правдивості годинника.
 *
 * Канон: 00_07 FW.70 · 03_01 §12.4.
 */
#ifndef SILKEN_LOGGER_CONSOLE_H
#define SILKEN_LOGGER_CONSOLE_H

#include <stddef.h>
#include <stdint.h>

#include "logger_journal.h"
#include "wall_time.h"

#define LOGC_LINE_CAP     16u          /* «T» + 10 цифр — найдовша команда */
#define LOGC_SET_SLACK_S  2u           /* перечитування може випередити запис на стільки */
#define LOGC_UNIX_MAX     4102444799u  /* 2099-12-31 23:59:59 UTC — стеля 2000-базового календаря RTC */

#define LOGC_CONTINUE 0
#define LOGC_QUIT     1

#define LOGC_T_NONE  INT32_MIN         /* температури немає — «NA» */
#define LOGC_M_CAP   64u               /* «#M,…» за крайніх значень усіх полів — 61 Б разом із '\n' */

/* Вимір для M; заповнює образ (soldier/main.c): датчик дендрометра й температура біля рами. */
typedef struct {
    uint16_t reading;    /* показ у шкалі журналу; LOGJ_READING_NONE — не поміряно */
    int16_t  rc;         /* код датчика, 0 — гаразд */
    uint32_t raw_exc;    /* сирі суми АЦП — для стенда */
    uint32_t raw_wiper;
    int32_t  t_centi;    /* °C × 100; LOGC_T_NONE — немає */
} LogCMeas;

typedef struct {
    uint32_t (*now)(void *io);                        /* секунди календаря */
    void     (*set_time)(void *io, uint32_t unix_s);  /* запис календаря; результат судить now().
                                                         NULL — образ не довіряє консолі календаря */
    void     (*emit)(void *io, const char *s, size_t n);
    void     (*measure)(void *io, LogCMeas *m);       /* NULL — образ без датчика: «ERR,M» */
} LogCOps;

typedef struct {
    char    buf[LOGC_LINE_CAP + 1u];
    uint8_t n;
    uint8_t over;  /* 1 = рядок задовгий — відповідь «?» */
} LogCLine;

/* Байт із UART. 1 = рядок завершено й чекає LogC_Exec. Порожній рядок (зокрема другий байт
 * пари «\r\n») — не команда. */
static inline int LogC_Feed(LogCLine *l, char c)
{
    if (c == '\r' || c == '\n') {
        if (l->n == 0u && !l->over) return 0;
        l->buf[l->n] = '\0';
        return 1;
    }
    if (l->n < LOGC_LINE_CAP) l->buf[l->n++] = c;
    else l->over = 1u;
    return 0;
}

/* Лише цифри, 1…10 штук, ≤ UINT32_MAX. */
static inline int logc_parse_u32(const char *s, uint32_t *out)
{
    uint64_t v = 0;
    int n = 0;
    for (; *s; s++, n++) {
        if (*s < '0' || *s > '9' || n >= 10) return 0;
        v = v * 10u + (uint64_t)(*s - '0');
    }
    if (n == 0 || v > UINT32_MAX) return 0;
    *out = (uint32_t)v;
    return 1;
}

/* Рядок стану (формат — шапка). */
static inline void LogC_Status(const LogJ *j, const LogCOps *ops, void *io)
{
    char o[LOGJ_FORMAT_CAP];
    size_t n = 0;
    uint32_t now = ops->now(io);
    o[n++] = '#'; o[n++] = 'S'; o[n++] = ',';
    n += logj_u32(o + n, now);
    o[n++] = ','; o[n++] = Silken_Wall_Is_Utc(now) ? '1' : '0';
    o[n++] = ','; o[n++] = j->n_pages ? '1' : '0';
    o[n++] = ','; o[n++] = j->open ? '1' : '0';
    o[n++] = ','; n += logj_u32(o + n, j->seq);
    o[n++] = ','; n += logj_u32(o + n, j->open ? j->widx : 0u);
    o[n++] = ','; n += logj_u32(o + n, j->write_fail);
    o[n++] = ','; o[n++] = LogJ_Holding(j) ? '1' : '0';
    o[n++] = '\n';
    ops->emit(io, o, n);
}

/* Рядок стану, усі записи, «#E,<рядків>». Повертає кількість рядків записів. */
static inline uint32_t LogC_Dump(const LogJ *j, const LogCOps *ops, void *io)
{
    char o[LOGJ_FORMAT_CAP];
    LogJIter it;
    LogJRec r;
    uint32_t rows = 0;
    LogC_Status(j, ops, io);
    LogJ_Iter_Begin(&it, j);
    while (LogJ_Iter_Next(&it, &r)) {
        ops->emit(io, o, LogJ_Format(o, sizeof o, &r));
        rows++;
    }
    size_t n = 0;
    o[n++] = '#'; o[n++] = 'E'; o[n++] = ',';
    n += logj_u32(o + n, rows);
    o[n++] = '\n';
    ops->emit(io, o, n);
    return rows;
}

static inline void logc_set_time(LogJ *j, const LogCOps *ops, void *io, uint32_t t)
{
    char o[LOGJ_FORMAT_CAP];
    size_t n = 0;
    uint32_t re = ops->now(io);
    if (ops->set_time) {
        (void)LogJ_Settle_Boot(j, re);         /* якір BOOT — зі старим часом */
        ops->set_time(io, t);
        re = ops->now(io);
    }
    if (ops->set_time && Silken_Wall_Is_Utc(re) && re >= t && re - t <= LOGC_SET_SLACK_S) {
        int jok = LogJ_Anchor(j, re, 1u, LOGJ_REASON_TIME_SET, 0u);
        o[n++] = 'O'; o[n++] = 'K'; o[n++] = ','; o[n++] = 'T'; o[n++] = ',';
        n += logj_u32(o + n, re);
        o[n++] = ','; o[n++] = jok ? '1' : '0';
    } else {
        o[n++] = 'E'; o[n++] = 'R'; o[n++] = 'R'; o[n++] = ','; o[n++] = 'T'; o[n++] = ',';
        n += logj_u32(o + n, re);
    }
    o[n++] = '\n';
    ops->emit(io, o, n);
}

static inline size_t logc_i32(char *o, int32_t v)
{
    if (v >= 0) return logj_u32(o, (uint32_t)v);
    o[0] = '-';
    return 1u + logj_u32(o + 1, 0u - (uint32_t)v);
}

/* Рядок «#M,…» (формат — шапка). Журналу не торкається. */
static inline void logc_measure(const LogCOps *ops, void *io)
{
    if (!ops->measure) { ops->emit(io, "ERR,M\n", 6u); return; }
    LogCMeas m = { LOGJ_READING_NONE, 0, 0u, 0u, LOGC_T_NONE };
    ops->measure(io, &m);
    char o[LOGC_M_CAP];
    size_t n = 0;
    o[n++] = '#'; o[n++] = 'M'; o[n++] = ',';
    n += logj_u32(o + n, ops->now(io));
    o[n++] = ',';
    if (m.reading == LOGJ_READING_NONE) { o[n++] = 'N'; o[n++] = 'A'; }
    else n += logj_u32(o + n, m.reading);
    o[n++] = ','; n += logc_i32(o + n, m.rc);
    o[n++] = ','; n += logj_u32(o + n, m.raw_exc);
    o[n++] = ','; n += logj_u32(o + n, m.raw_wiper);
    o[n++] = ',';
    if (m.t_centi == LOGC_T_NONE) { o[n++] = 'N'; o[n++] = 'A'; }
    else n += logc_i32(o + n, m.t_centi);
    o[n++] = '\n';
    ops->emit(io, o, n);
}

/* Виконати завершений рядок і звільнити його. LOGC_QUIT — закрити вікно. */
static inline int LogC_Exec(LogJ *j, const LogCOps *ops, void *io, LogCLine *l)
{
    int act = LOGC_CONTINUE;
    char c = l->over ? '\0' : l->buf[0];
    if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
    uint32_t t = 0;
    if (c == 'T' && logc_parse_u32(l->buf + 1, &t) && Silken_Wall_Is_Utc(t) && t <= LOGC_UNIX_MAX) {
        logc_set_time(j, ops, io, t);
    } else if (c == 'D' && l->buf[1] == '\0') {
        (void)LogC_Dump(j, ops, io);
    } else if (c == 'S' && l->buf[1] == '\0') {
        LogC_Status(j, ops, io);
    } else if (c == 'M' && l->buf[1] == '\0') {
        logc_measure(ops, io);
    } else if (c == 'Q' && l->buf[1] == '\0') {
        ops->emit(io, "OK,Q\n", 5u);
        act = LOGC_QUIT;
    } else {
        ops->emit(io, "?\n", 2u);
    }
    l->n = 0u;
    l->over = 0u;
    l->buf[0] = '\0';
    return act;
}

#endif /* SILKEN_LOGGER_CONSOLE_H */
