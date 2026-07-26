// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * at_engine.h — [FW.3] байтовий AT-токенайзер + транзакційний цикл (pure).
 *
 * Стара схема `HAL_UART_Receive(128B, timeout)` чекала ПОВНИЙ буфер → кожен
 * AT-обмін коштував увесь timeout, навіть коли модем відповів за мить. Тут
 * лінія збирається байт за байтом і класифікується на терміналі (\n):
 * early-exit — латентність дорівнює реальній відповіді модему.
 *
 * One-Home: Queen firmware ТА host-тести (test_at_engine.c) компілюють цей
 * самий код. Жодного HAL — джерело байтів передається callback'ом, тому
 * транскрипти SIM7070G ганяються на host із довільною сегментацією потоку.
 *
 * Граматика сімейства SIMCom (офіційна CoAP App Note; verbatim-звірка
 * SIM7070-ноти V1.03 — рядок у bench-runbook): фінали `OK` / `ERROR` /
 * `+CME ERROR: <n>`; URC (`+CCOAPNEW:`, `+CCOAPNMI:`, `+CDNSGIP:`) можуть
 * лунати як ДО фінала, так і ПІСЛЯ нього — тому транзакція збирає префіксний
 * URC дорогою, а пост-фінальні чекає At_Await_Urc.
 *
 * Канон: 03_02 §4 (модем) + 00_07 FW.3/FW.56.
 */
#ifndef SILKEN_AT_ENGINE_H
#define SILKEN_AT_ENGINE_H

#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* Найдовша корисна лінія — +CCOAPNMI з hex-PDU відповіді сервера (ACK 2.04
 * на наш PUT — десятки байт). Довші лінії обрізаються з прапорцем truncated:
 * класифікація за префіксом усе одно працює. */
#define AT_LINE_MAX 160

typedef enum {
    AT_EVT_NONE = 0,     /* лінія ще не завершена */
    AT_EVT_LINE,         /* нетермінальна лінія (URC / echo / інфо) */
    AT_EVT_FINAL_OK,     /* OK */
    AT_EVT_FINAL_ERROR,  /* ERROR */
    AT_EVT_FINAL_CME     /* +CME ERROR: <n> (також +CMS) — код у cme_code */
} AtEvent;

typedef struct {
    char     line[AT_LINE_MAX]; /* валідна до наступного Feed після події */
    uint16_t len;
    uint8_t  truncated;
    int32_t  cme_code;
} AtEngine;

static inline void At_Engine_Reset(AtEngine *e)
{
    e->len = 0u;
    e->line[0] = '\0';
    e->truncated = 0u;
    e->cme_code = -1;
}

/* Один байт з UART → подія. \r ігнорується, \n завершує лінію; порожні
 * лінії (модемне обрамлення \r\n) подій не породжують. */
static inline AtEvent At_Engine_Feed(AtEngine *e, uint8_t byte)
{
    if (byte == (uint8_t)'\r') return AT_EVT_NONE;

    if (byte != (uint8_t)'\n') {
        if (e->len + 1u < (uint16_t)AT_LINE_MAX) {
            e->line[e->len++] = (char)byte;
        } else {
            e->truncated = 1u;
        }
        return AT_EVT_NONE;
    }

    if (e->len == 0u) return AT_EVT_NONE;

    e->line[e->len] = '\0';
    e->len = 0u; /* наступний Feed почне нову лінію; line[] живе до того */

    if (strcmp(e->line, "OK") == 0) return AT_EVT_FINAL_OK;
    if (strcmp(e->line, "ERROR") == 0) return AT_EVT_FINAL_ERROR;
    if (strncmp(e->line, "+CME ERROR:", 11) == 0 ||
        strncmp(e->line, "+CMS ERROR:", 11) == 0) {
        e->cme_code = (int32_t)strtol(e->line + 11, NULL, 10);
        return AT_EVT_FINAL_CME;
    }
    return AT_EVT_LINE;
}

/* ── Транзакція: команда вже передана, читаємо до фінала ─────────────────
 * Джерело байтів: 1 = байт є, 0 = тиша (interbyte-timeout / дедлайн) —
 * саме джерело володіє годинником (HAL_GetTick у firmware, скрипт у тестах).
 */
typedef int (*AtByteSource)(void *io, uint8_t *out_byte);

typedef enum {
    AT_TX_OK = 0,
    AT_TX_ERROR,    /* ERROR або +CME/+CMS — код у engine->cme_code */
    AT_TX_TIMEOUT
} AtTxResult;

typedef struct {
    const char *urc_prefix;        /* NULL → URC не збираємо */
    char        urc[AT_LINE_MAX];  /* перша лінія з префіксом */
    uint8_t     urc_seen;
} AtTransact;

static inline void At_Transact_Init(AtTransact *t, const char *urc_prefix)
{
    t->urc_prefix = urc_prefix;
    t->urc[0] = '\0';
    t->urc_seen = 0u;
}

/* Читає потік до фінала. URC з префіксом (якщо задано) ловиться дорогою —
 * сімейство SIMCom шле `+CCOAPNEW: <cid>` ПЕРЕД OK. Echo та сторонні лінії
 * («RDY», шум) проминаються. */
static inline AtTxResult At_Transact_Run(AtEngine *e, AtTransact *t,
                                         AtByteSource src, void *io)
{
    uint8_t b;
    while (src(io, &b)) {
        AtEvent evt = At_Engine_Feed(e, b);
        switch (evt) {
        case AT_EVT_FINAL_OK:    return AT_TX_OK;
        case AT_EVT_FINAL_ERROR: return AT_TX_ERROR;
        case AT_EVT_FINAL_CME:   return AT_TX_ERROR;
        case AT_EVT_LINE:
            if (t->urc_prefix && !t->urc_seen &&
                strncmp(e->line, t->urc_prefix, strlen(t->urc_prefix)) == 0) {
                /* line[] ≤ AT_LINE_MAX з NUL — копія завжди вміщується */
                strcpy(t->urc, e->line);
                t->urc_seen = 1u;
            }
            break;
        case AT_EVT_NONE:
            break;
        }
    }
    return AT_TX_TIMEOUT;
}

/* Пост-фінальний URC (`+CCOAPNMI:` приходить ПІСЛЯ OK, коли сервер
 * відповів по радіо). 1 = впіймано (лінія у out), 0 = джерело замовкло. */
static inline int At_Await_Urc(AtEngine *e, const char *urc_prefix,
                               char *out, AtByteSource src, void *io)
{
    uint8_t b;
    while (src(io, &b)) {
        if (At_Engine_Feed(e, b) != AT_EVT_LINE) continue;
        if (strncmp(e->line, urc_prefix, strlen(urc_prefix)) == 0) {
            strcpy(out, e->line);
            return 1;
        }
    }
    return 0;
}

/* [FW.60] Лічене бінарне читання ПОВЗ токенайзер: `AT+CARECV` віддає сирі
 * байти (не hex), і будь-який 0x0A всередині зламав би line-збирання. Читає
 * рівно n байтів з того самого джерела (interbyte/deadline-годинник у нього);
 * повертає фактично прочитане — < n означає тишу до дедлайну. */
static inline uint16_t At_Read_N(AtByteSource src, void *io,
                                 uint8_t *dst, uint16_t n)
{
    uint16_t got = 0;
    uint8_t b;
    while (got < n && src(io, &b)) dst[got++] = b;
    return got;
}

/* ── Дрібні чисті парсери AT-ліній ──────────────────────────────────── */

/* n-та (від 1) лапкована підстрока лінії → out (NUL-терміновано).
 * `+CDNSGIP: 1,"api.silkennet.com","10.0.0.1"` → n=2 дає IP. 1=є, 0=нема. */
static inline int At_Extract_Quoted(const char *line, uint8_t n,
                                    char *out, uint16_t out_max)
{
    const char *p = line;
    for (uint8_t i = 0; i < n; i++) {
        const char *open = strchr(p, '"');
        if (!open) return 0;
        const char *close = strchr(open + 1, '"');
        if (!close) return 0;
        if (i + 1u == n) {
            uint16_t l = (uint16_t)(close - open - 1);
            if (l + 1u > out_max) return 0;
            memcpy(out, open + 1, l);
            out[l] = '\0';
            return 1;
        }
        p = close + 1;
    }
    return 0;
}

/* Перше ціле після двокрапки: `+CCOAPNEW: 1` → 1. Нема/сміття → fallback. */
static inline int32_t At_Int_After_Colon(const char *line, int32_t fallback)
{
    const char *c = strchr(line, ':');
    if (!c) return fallback;
    char *end = NULL;
    long v = strtol(c + 1, &end, 10);
    return (end == c + 1) ? fallback : (int32_t)v;
}

/* ── Hex-кодек AT-ліній (CCOAPSEND шле PDU як hex-ASCII) ────────────── */

static inline void At_Hex_Encode(char *dst, const uint8_t *src, uint16_t n)
{
    static const char lut[] = "0123456789ABCDEF";
    for (uint16_t i = 0; i < n; i++) {
        dst[2u * i]      = lut[src[i] >> 4];
        dst[2u * i + 1u] = lut[src[i] & 0x0Fu];
    }
}

/* 1=ок, 0=непарна довжина чи не-hex символ. Регістр байдужий. */
static inline int At_Hex_Decode(uint8_t *dst, uint16_t dst_max,
                                const char *src, uint16_t *out_len)
{
    uint16_t n = (uint16_t)strlen(src);
    if (n & 1u) return 0;
    n /= 2u;
    if (n > dst_max) return 0;
    for (uint16_t i = 0; i < n; i++) {
        uint8_t hi, lo;
        char a = src[2u * i], b = src[2u * i + 1u];
        if      (a >= '0' && a <= '9') hi = (uint8_t)(a - '0');
        else if (a >= 'A' && a <= 'F') hi = (uint8_t)(a - 'A' + 10);
        else if (a >= 'a' && a <= 'f') hi = (uint8_t)(a - 'a' + 10);
        else return 0;
        if      (b >= '0' && b <= '9') lo = (uint8_t)(b - '0');
        else if (b >= 'A' && b <= 'F') lo = (uint8_t)(b - 'A' + 10);
        else if (b >= 'a' && b <= 'f') lo = (uint8_t)(b - 'a' + 10);
        else return 0;
        dst[i] = (uint8_t)((hi << 4) | lo);
    }
    *out_len = n;
    return 1;
}

#endif /* SILKEN_AT_ENGINE_H */
