// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * sim7070_udp.h — [FW.60] сира UDP-розмова CA*-сім'ї SIM7070G (pure-оркестратор).
 *
 * Downlink-poll Королеви: CCOAP-тракт (sim7070_coap.h) годиться лише для
 * uplink — його відповідь приходить hex-URC'ом `+CCOAPNMI` крізь line-based
 * токенайзер, стеля ~⌊(AT_LINE_MAX−overhead)/2⌋ ≈ 60-70 Б. Навіть найменший
 * CMD-конверт (~80 Б: UUID-36 + 0x9C-конверт + CBC-pad + IV) у лінію не
 * влазить — обрізаний hex = втрачена сирена. Тому ВЕСЬ poll їде CA*-сім'єю:
 * `CAOPEN` (UDP-сокет, DNS уміє сам — але даємо кешований IP) → `CASEND`
 * (промпт '>' → сирі байти PDU) → URC `+CADATAIND: <cid>` (вхідне
 * буферизовано) → `CARECV` (СИРІ лічені байти — повний PDU одним читанням,
 * ≤1459 Б) → `CACLOSE`. Модем-факти звірені посторінково: 03_02 §4
 * [FW.60]-банер (AT Manual V1.03 + TCPUDP-нота V1.02).
 *
 * FW.3-клас акуратності: заголовок `+CARECV: <n>,` читається посимвольно
 * ПОВЗ токенайзер (сирі байти після коми можуть нести 0x0A — line-збирання
 * зламалось би), тіло — ліченим At_Read_N.
 *
 * One-Home: Queen firmware ТА host-тести компілюють цей самий код.
 * Канон: 03_02 §4 + 00_07 FW.60.
 */
#ifndef SILKEN_SIM7070_UDP_H
#define SILKEN_SIM7070_UDP_H

#include "sim7070_coap.h"

/* Один сокет за раз — фіксований cid 0 (пул модема 0..12 нам не потрібен). */
#define SIM7070_UDP_CID 0

/* Другий int лінії `+CAOPEN: <cid>,<result>` — 0 = сокет відкрито. */
static inline int32_t Sim7070_Second_Int(const char *line, int32_t fallback)
{
    const char *c = strchr(line, ',');
    if (!c) return fallback;
    char *end = NULL;
    long v = strtol(c + 1, &end, 10);
    return (end == c + 1) ? fallback : (int32_t)v;
}

/* Промпт CASEND — голий '>' БЕЗ \n (токенайзер його не побачить ніколи):
 * читаємо посимвольно до '>' або тиші. Обрамлення \r\n проминаємо. */
static inline int Sim7070_Await_Prompt(Sim7070Io *m)
{
    uint8_t b;
    while (m->src(m->io, &b)) {
        if (b == (uint8_t)'>') return 1;
    }
    return 0;
}

/* Заголовок відповіді читання: `+CARECV: <n>,` посимвольно (без токенайзера —
 * далі йдуть сирі байти). Повертає 1 + *n_out; 0 = тиша/чужа лінія. */
static inline int Sim7070_Read_Carecv_Header(Sim7070Io *m, uint16_t *n_out)
{
    static const char prefix[] = "+CARECV: ";
    uint8_t b;
    uint8_t matched = 0;
    /* Фаза 1: знайти префікс у потоці (echo/\r\n/чужі URC проминаються). */
    while (matched < (uint8_t)(sizeof prefix - 1u)) {
        if (!m->src(m->io, &b)) return 0;
        if ((char)b == prefix[matched]) matched++;
        else matched = ((char)b == prefix[0]) ? 1u : 0u;
    }
    /* Фаза 2: цифри довжини до коми. */
    uint32_t n = 0;
    uint8_t digits = 0;
    while (m->src(m->io, &b)) {
        if (b == (uint8_t)',') {
            if (digits == 0u) return 0;
            *n_out = (uint16_t)n;
            return 1;
        }
        if (b < (uint8_t)'0' || b > (uint8_t)'9' || n > 6553u) return 0;
        n = n * 10u + (uint32_t)(b - (uint8_t)'0');
        digits++;
    }
    return 0;
}

/* Повна UDP-розмова один запит → одна відповідь. Повертає довжину відповіді
 * у reply (0 = провал будь-якої фази; сокет прибирається best-effort).
 * Дедлайн усієї розмови тримає джерело (UartAtIo) — як у CCOAP-тракті. */
static inline uint16_t Sim7070_Udp_Fetch(Sim7070Io *m, AtEngine *e,
                                         const char *server_ip, uint16_t port,
                                         const uint8_t *pdu, uint16_t pdu_len,
                                         uint8_t *reply, uint16_t reply_max)
{
    char cmd[96];
    AtTransact t;
    uint16_t got = 0;

    /* 1. Сокет: `+CAOPEN: <cid>,<result>` (result 0 = success) + OK. */
    if (snprintf(cmd, sizeof cmd, "AT+CAOPEN=%d,0,\"UDP\",\"%s\",%u\r\n",
                 SIM7070_UDP_CID, server_ip, (unsigned)port) >= (int)sizeof cmd) return 0;
    if (!Sim7070_Send_Str(m, cmd)) return 0;
    At_Transact_Init(&t, "+CAOPEN:");
    if (At_Transact_Run(e, &t, m->src, m->io) != AT_TX_OK) return 0;
    if (!t.urc_seen && !At_Await_Urc(e, "+CAOPEN:", t.urc, m->src, m->io)) return 0;
    if (Sim7070_Second_Int(t.urc, -1) != 0) return 0;

    /* 2. Запит: CASEND → промпт '>' → сирі байти PDU → OK. */
    if (snprintf(cmd, sizeof cmd, "AT+CASEND=%d,%u\r\n",
                 SIM7070_UDP_CID, (unsigned)pdu_len) >= (int)sizeof cmd) goto close;
    if (!Sim7070_Send_Str(m, cmd)) goto close;
    if (!Sim7070_Await_Prompt(m)) goto close;
    if (!m->sink(m->io, pdu, pdu_len)) goto close;
    At_Transact_Init(&t, NULL);
    if (At_Transact_Run(e, &t, m->src, m->io) != AT_TX_OK) goto close;

    /* 3. Відповідь: модем буферизує і будить коротким URC `+CADATAIND`. */
    {
        char urc[AT_LINE_MAX];
        if (!At_Await_Urc(e, "+CADATAIND:", urc, m->src, m->io)) goto close;
    }

    /* 4. Читання: заголовок посимвольно, тіло — ліченим binary-read. */
    if (snprintf(cmd, sizeof cmd, "AT+CARECV=%d,%u\r\n",
                 SIM7070_UDP_CID, (unsigned)reply_max) >= (int)sizeof cmd) goto close;
    if (!Sim7070_Send_Str(m, cmd)) goto close;
    {
        uint16_t n = 0;
        if (!Sim7070_Read_Carecv_Header(m, &n) || n == 0u || n > reply_max) goto close;
        if (At_Read_N(m->src, m->io, reply, n) != n) { got = 0; goto close; }
        got = n;
    }
    /* Фінал OK після тіла — доїдаємо, щоб кільце не тримало хвіст. */
    At_Transact_Init(&t, NULL);
    (void)At_Transact_Run(e, &t, m->src, m->io);

close:
    /* 5. Прибрати сокет (best-effort — вердикт уже у got). */
    if (snprintf(cmd, sizeof cmd, "AT+CACLOSE=%d\r\n", SIM7070_UDP_CID) < (int)sizeof cmd &&
        Sim7070_Send_Str(m, cmd)) {
        At_Transact_Init(&t, NULL);
        (void)At_Transact_Run(e, &t, m->src, m->io);
    }
    return got;
}

#endif /* SILKEN_SIM7070_UDP_H */
