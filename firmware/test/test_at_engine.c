// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_at_engine.c — [FW.3/FW.56] host-тести AT-токенайзера, CoAP PDU та
 * повної CoAP-PUT розмови з SIM7070G на скриптованому модемі.
 *
 * Модем-симулятор — транскрипт-driven: стейджі «команда → відповідь» у
 * граматиці сімейства SIMCom (офіційна CoAP App Note; SIM7070-verbatim —
 * bench-runbook). Golden-вектор відповіді сервера взято ДОСЛІВНО з ноти:
 * "60457233c02105ff303234" → ACK 2.05, MID 0x7233.
 *
 * Build: make -C firmware/test at_engine
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../queen/at_engine.h"
#include "../queen/coap_pdu.h"
#include "../queen/sim7070_coap.h"

/* NB: старі FW.9-тести (підстроковий пошук "OK" у 128B-буфері) жили в
 * test_queen_logic.c і дзеркалили видалену реалізацію — закриті тут
 * повним покриттям токенайзера (включно з анти-кейсом "BROKEN"). */

/* ════════════════════════════════════════════════════════════════════
 * TEST FRAMEWORK (house pattern — test_queen_logic.c)
 * ════════════════════════════════════════════════════════════════════ */
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) static void name(void)
#define RUN(name) do { \
    printf("  %-58s", #name); \
    name(); \
    printf(" ✅\n"); \
    tests_passed++; \
} while(0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) { \
        printf(" ❌ FAIL (line %d: got %lld, expected %lld)\n", __LINE__, _a, _b); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_TRUE(expr) ASSERT_EQ(!!(expr), 1)
#define ASSERT_FALSE(expr) ASSERT_EQ(!!(expr), 0)

#define ASSERT_STREQ(a, b) do { \
    if (strcmp((a), (b)) != 0) { \
        printf(" ❌ FAIL (line %d: got \"%s\", expected \"%s\")\n", __LINE__, (a), (b)); \
        tests_failed++; return; \
    } \
} while(0)

/* ════════════════════════════════════════════════════════════════════
 * SCRIPTED MODEM — транскрипт-driven SIM7070G
 * ════════════════════════════════════════════════════════════════════ */
typedef struct {
    const char *expect; /* підстрока TX, що активує відповідь */
    const char *reply;  /* байти модем→MCU (включно з \r\n-обрамленням) */
} Stage;

typedef struct {
    const Stage *stages;
    int          n_stages;
    int          armed;        /* скільки стейджів уже активовано */
    size_t       match_off;    /* стейджі матчаться по черзі, без повторів */
    const char  *rx;
    size_t       rx_pos;
    char         tx[8192];
    size_t       tx_len;
    int          sink_calls;
    uint16_t     max_chunk;
} ModemSim;

static void modem_init(ModemSim *m, const Stage *stages, int n)
{
    memset(m, 0, sizeof *m);
    m->stages = stages;
    m->n_stages = n;
}

static int modem_src(void *io, uint8_t *b)
{
    ModemSim *m = (ModemSim *)io;
    if (!m->rx || m->rx[m->rx_pos] == '\0') return 0; /* тиша = timeout */
    *b = (uint8_t)m->rx[m->rx_pos++];
    return 1;
}

static int modem_sink(void *io, const uint8_t *bytes, uint16_t n)
{
    ModemSim *m = (ModemSim *)io;
    if (m->tx_len + n + 1u > sizeof m->tx) return 0;
    memcpy(m->tx + m->tx_len, bytes, n);
    m->tx_len += n;
    m->tx[m->tx_len] = '\0';
    m->sink_calls++;
    if (n > m->max_chunk) m->max_chunk = n;

    /* Чергова команда впізнана → озброїти її відповідь */
    if (m->armed < m->n_stages) {
        const char *hit = strstr(m->tx + m->match_off, m->stages[m->armed].expect);
        if (hit) {
            m->match_off = (size_t)(hit - m->tx) + strlen(m->stages[m->armed].expect);
            m->rx = m->stages[m->armed].reply;
            m->rx_pos = 0;
            m->armed++;
        }
    }
    return 1;
}

/* Зручність: прогнати ланцюжок байтів крізь токенайзер, зібрати події */
static int feed_str(AtEngine *e, const char *s, AtEvent *events, int max_events)
{
    int n = 0;
    for (const char *p = s; *p; p++) {
        AtEvent evt = At_Engine_Feed(e, (uint8_t)*p);
        if (evt != AT_EVT_NONE && n < max_events) events[n++] = evt;
    }
    return n;
}

/* ════════════════════════════════════════════════════════════════════
 * 1. ТОКЕНАЙЗЕР
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_tok_ok_with_framing) {
    AtEngine e; At_Engine_Reset(&e);
    AtEvent evts[4];
    int n = feed_str(&e, "\r\nOK\r\n", evts, 4);
    ASSERT_EQ(n, 1);
    ASSERT_EQ(evts[0], AT_EVT_FINAL_OK);
}

TEST(test_tok_error) {
    AtEngine e; At_Engine_Reset(&e);
    AtEvent evts[4];
    int n = feed_str(&e, "\r\nERROR\r\n", evts, 4);
    ASSERT_EQ(n, 1);
    ASSERT_EQ(evts[0], AT_EVT_FINAL_ERROR);
}

TEST(test_tok_cme_error_code) {
    AtEngine e; At_Engine_Reset(&e);
    AtEvent evts[4];
    int n = feed_str(&e, "\r\n+CME ERROR: 53\r\n", evts, 4);
    ASSERT_EQ(n, 1);
    ASSERT_EQ(evts[0], AT_EVT_FINAL_CME);
    ASSERT_EQ(e.cme_code, 53);
}

TEST(test_tok_echo_then_urc_then_ok) {
    AtEngine e; At_Engine_Reset(&e);
    AtEvent evts[8];
    int n = feed_str(&e, "AT+CCOAPNEW=\"1.2.3.4\",5683,0\r\r\n+CCOAPNEW: 1\r\n\r\nOK\r\n",
                     evts, 8);
    ASSERT_EQ(n, 3); /* echo-лінія + URC-лінія + фінал */
    ASSERT_EQ(evts[0], AT_EVT_LINE);
    ASSERT_EQ(evts[1], AT_EVT_LINE);
    ASSERT_EQ(evts[2], AT_EVT_FINAL_OK);
}

TEST(test_tok_long_line_truncated_but_classified) {
    AtEngine e; At_Engine_Reset(&e);
    char long_line[300];
    memset(long_line, 'A', sizeof long_line);
    long_line[298] = '\n';
    long_line[299] = '\0';
    AtEvent evts[4];
    int n = feed_str(&e, long_line, evts, 4);
    ASSERT_EQ(n, 1);
    ASSERT_EQ(evts[0], AT_EVT_LINE);
    ASSERT_TRUE(e.truncated);
    ASSERT_EQ((int)strlen(e.line), AT_LINE_MAX - 1);
}

TEST(test_tok_ok_inside_word_is_not_final) {
    AtEngine e; At_Engine_Reset(&e);
    AtEvent evts[4];
    /* стара impl шукала "OK" підстрокою будь-де — "BROKEN" хибно final'ився */
    int n = feed_str(&e, "\r\nBROKEN\r\n", evts, 4);
    ASSERT_EQ(n, 1);
    ASSERT_EQ(evts[0], AT_EVT_LINE);
}

/* ════════════════════════════════════════════════════════════════════
 * 2. ТРАНЗАКЦІЇ
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_transact_urc_before_ok) {
    static const Stage st[] = { { "AT+X", "\r\n+CCOAPNEW: 2\r\n\r\nOK\r\n" } };
    ModemSim m; modem_init(&m, st, 1);
    modem_sink(&m, (const uint8_t *)"AT+X\r\n", 6);

    AtEngine e; At_Engine_Reset(&e);
    AtTransact t; At_Transact_Init(&t, "+CCOAPNEW:");
    ASSERT_EQ(At_Transact_Run(&e, &t, modem_src, &m), AT_TX_OK);
    ASSERT_TRUE(t.urc_seen);
    ASSERT_EQ(At_Int_After_Colon(t.urc, -1), 2);
}

TEST(test_transact_error_and_cme) {
    static const Stage st[] = { { "AT+X", "\r\nERROR\r\n" } };
    ModemSim m; modem_init(&m, st, 1);
    modem_sink(&m, (const uint8_t *)"AT+X\r\n", 6);
    AtEngine e; At_Engine_Reset(&e);
    AtTransact t; At_Transact_Init(&t, NULL);
    ASSERT_EQ(At_Transact_Run(&e, &t, modem_src, &m), AT_TX_ERROR);

    static const Stage st2[] = { { "AT+Y", "\r\n+CME ERROR: 30\r\n" } };
    ModemSim m2; modem_init(&m2, st2, 1);
    modem_sink(&m2, (const uint8_t *)"AT+Y\r\n", 6);
    At_Engine_Reset(&e);
    At_Transact_Init(&t, NULL);
    ASSERT_EQ(At_Transact_Run(&e, &t, modem_src, &m2), AT_TX_ERROR);
    ASSERT_EQ(e.cme_code, 30);
}

TEST(test_transact_silence_is_timeout) {
    ModemSim m; modem_init(&m, NULL, 0); /* модем мовчить */
    AtEngine e; At_Engine_Reset(&e);
    AtTransact t; At_Transact_Init(&t, NULL);
    ASSERT_EQ(At_Transact_Run(&e, &t, modem_src, &m), AT_TX_TIMEOUT);
}

TEST(test_transact_noise_lines_skipped) {
    static const Stage st[] = { { "AT+X", "\r\nRDY\r\n\r\n+QIND: noise\r\n\r\nOK\r\n" } };
    ModemSim m; modem_init(&m, st, 1);
    modem_sink(&m, (const uint8_t *)"AT+X\r\n", 6);
    AtEngine e; At_Engine_Reset(&e);
    AtTransact t; At_Transact_Init(&t, NULL);
    ASSERT_EQ(At_Transact_Run(&e, &t, modem_src, &m), AT_TX_OK);
}

TEST(test_await_urc_after_final) {
    static const Stage st[] = { { "AT+X", "\r\nOK\r\n\r\n+CCOAPNMI: 0,4,\"60441234\"\r\n" } };
    ModemSim m; modem_init(&m, st, 1);
    modem_sink(&m, (const uint8_t *)"AT+X\r\n", 6);
    AtEngine e; At_Engine_Reset(&e);
    AtTransact t; At_Transact_Init(&t, NULL);
    ASSERT_EQ(At_Transact_Run(&e, &t, modem_src, &m), AT_TX_OK);
    char urc[AT_LINE_MAX];
    ASSERT_TRUE(At_Await_Urc(&e, "+CCOAPNMI:", urc, modem_src, &m));
    char hex[64];
    ASSERT_TRUE(At_Extract_Quoted(urc, 1, hex, sizeof hex));
    ASSERT_STREQ(hex, "60441234");
}

/* ════════════════════════════════════════════════════════════════════
 * 3. ПАРСЕРИ ЛІНІЙ + HEX
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_extract_quoted_dnsgip) {
    char out[40];
    const char *l = "+CDNSGIP: 1,\"api.silkennet.com\",\"10.20.30.40\"";
    ASSERT_TRUE(At_Extract_Quoted(l, 2, out, sizeof out));
    ASSERT_STREQ(out, "10.20.30.40");
    ASSERT_TRUE(At_Extract_Quoted(l, 1, out, sizeof out));
    ASSERT_STREQ(out, "api.silkennet.com");
    ASSERT_FALSE(At_Extract_Quoted(l, 3, out, sizeof out));
    char tiny[4];
    ASSERT_FALSE(At_Extract_Quoted(l, 2, tiny, sizeof tiny));
    ASSERT_FALSE(At_Extract_Quoted(l, 0, out, sizeof out)); /* n рахується з 1 — 0 поза контрактом */
}

TEST(test_int_after_colon) {
    ASSERT_EQ(At_Int_After_Colon("+CCOAPNEW: 1", -1), 1);
    ASSERT_EQ(At_Int_After_Colon("+CCOAPNEW: 12", -1), 12);
    ASSERT_EQ(At_Int_After_Colon("garbage", -1), -1);
    ASSERT_EQ(At_Int_After_Colon("+X: junk", 7), 7);
}

TEST(test_hex_roundtrip_and_rejects) {
    const uint8_t src[] = { 0x00, 0xDE, 0xAD, 0xBE, 0xEF, 0xFF };
    char hex[13];
    At_Hex_Encode(hex, src, 6);
    hex[12] = '\0';
    ASSERT_STREQ(hex, "00DEADBEEFFF");

    uint8_t back[8]; uint16_t n = 0;
    ASSERT_TRUE(At_Hex_Decode(back, sizeof back, "00deadbeefff", &n)); /* lowercase */
    ASSERT_EQ(n, 6);
    ASSERT_EQ(memcmp(back, src, 6), 0);

    ASSERT_FALSE(At_Hex_Decode(back, sizeof back, "ABC", &n));   /* непарна */
    ASSERT_FALSE(At_Hex_Decode(back, sizeof back, "ZZ", &n));    /* не hex (старший нібл) */
    ASSERT_FALSE(At_Hex_Decode(back, sizeof back, "AZ", &n));    /* не hex (молодший нібл) */
    ASSERT_FALSE(At_Hex_Decode(back, 2, "AABBCCDD", &n));        /* не влізло */
}

/* ════════════════════════════════════════════════════════════════════
 * 4. CoAP PDU
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_coap_build_golden_layout) {
    /* /telemetry/batch/SNET-Q-AABBCCDD (15 симв. → len-нібл 13 + ext 2) */
    uint8_t pdu[128];
    const uint8_t payload[] = { 0xDE, 0xAD };
    uint16_t n = Coap_Build_Put(pdu, sizeof pdu, 0xBEEF,
                                "telemetry", "batch", "SNET-Q-AABBCCDD",
                                payload, 2);
    ASSERT_EQ(n, 4 + (1 + 9) + (1 + 5) + (2 + 15) + 1 + 2);

    char hex[2 * 64 + 1];
    At_Hex_Encode(hex, pdu, n);
    hex[2 * n] = '\0';
    ASSERT_STREQ(hex,
        "4003BEEF"                              /* CON PUT MID=0xBEEF      */
        "B974656C656D65747279"                  /* δ=11 len=9 "telemetry"  */
        "056261746368"                          /* δ=0  len=5 "batch"      */
        "0D02534E45542D512D4141424243434444"    /* δ=0  len=13+2 UID       */
        "FF" "DEAD");
}

TEST(test_coap_build_golden_mid_ff) {
    /* [FW.56 e2e] Пін-кейс бага бекенд-Брами: 0xFF у MID та в payload.
     * Маркер payload легітимний лише на МЕЖІ опцій — глобальний пошук
     * 0xFF у lib/daemons/coap_listener ламався на кожному 256-му
     * coap_mid (ACK 2.04 летів, батч губився → FW.51 чистив кеш дарма).
     * Той самий hex заморожено у spec/lib/coap_server_pdu_spec.rb —
     * крос-імпл freeze-contract C-білдер ↔ Rails-парсер. */
    uint8_t pdu[128];
    const uint8_t payload[] = { 0xFF, 0x01, 0xFF };
    uint16_t n = Coap_Build_Put(pdu, sizeof pdu, 0x00FF,
                                "telemetry", "batch", "SNET-Q-00FF00FF",
                                payload, 3);
    ASSERT_EQ(n, 4 + (1 + 9) + (1 + 5) + (2 + 15) + 1 + 3);

    char hex[2 * 64 + 1];
    At_Hex_Encode(hex, pdu, n);
    hex[2 * n] = '\0';
    ASSERT_STREQ(hex,
        "400300FF"                              /* CON PUT MID=0x00FF      */
        "B974656C656D65747279"                  /* δ=11 len=9 "telemetry"  */
        "056261746368"                          /* δ=0  len=5 "batch"      */
        "0D02534E45542D512D3030464630304646"    /* δ=0  len=13+2 UID       */
        "FF" "FF01FF");

    /* ACK Брами на цей PDU (2.04, MID луною) — Ruby build_ack емітить
     * рівно ці байти, ми їх тут зараховуємо як доставку. */
    uint8_t ack[8]; uint16_t an = 0;
    ASSERT_TRUE(At_Hex_Decode(ack, sizeof ack, "604400FF", &an));
    ASSERT_TRUE(Coap_Reply_Confirms(ack, an, 0x00FF));
}

TEST(test_coap_build_guards) {
    uint8_t pdu[16]; /* замалий */
    ASSERT_EQ(Coap_Build_Put(pdu, sizeof pdu, 1, "telemetry", "batch", "X",
                             NULL, 0), 0);
    uint8_t big[128];
    ASSERT_EQ(Coap_Build_Put(big, sizeof big, 1, "telemetry", "", "X",
                             NULL, 0), 0); /* порожній сегмент */
}

TEST(test_coap_parse_official_note_reply) {
    /* ДОСЛІВНО з SIMCom CoAP App Note: ACK 2.05 Content, MID 0x7233 */
    uint8_t reply[32]; uint16_t n = 0;
    ASSERT_TRUE(At_Hex_Decode(reply, sizeof reply, "60457233c02105ff303234", &n));
    CoapHead h;
    ASSERT_TRUE(Coap_Parse_Head(reply, n, &h));
    ASSERT_EQ(h.version, 1);
    ASSERT_EQ(h.type, 2);            /* ACK */
    ASSERT_EQ(Coap_Code_Class(h.code), 2);
    ASSERT_EQ(h.message_id, 0x7233);
    ASSERT_TRUE(Coap_Reply_Confirms(reply, n, 0x7233));
    ASSERT_FALSE(Coap_Reply_Confirms(reply, n, 0x1111)); /* чужий ACK */
}

TEST(test_coap_reply_rejects) {
    uint8_t r[8]; uint16_t n = 0;
    ASSERT_TRUE(At_Hex_Decode(r, sizeof r, "60841234", &n)); /* ACK 4.04 */
    ASSERT_FALSE(Coap_Reply_Confirms(r, n, 0x1234));
    ASSERT_TRUE(At_Hex_Decode(r, sizeof r, "70001234", &n)); /* RST */
    ASSERT_FALSE(Coap_Reply_Confirms(r, n, 0x1234));
    ASSERT_FALSE(Coap_Reply_Confirms(r, 3, 0x1234));         /* куций */
    /* NON 2.05 (separate response, TKL=0 → MID не звіряємо) — приймаємо */
    ASSERT_TRUE(At_Hex_Decode(r, sizeof r, "50450001", &n));
    ASSERT_TRUE(Coap_Reply_Confirms(r, n, 0x1234));
}

/* ════════════════════════════════════════════════════════════════════
 * 5. ПОВНА РОЗМОВА (оркестратор × скриптований модем)
 * ════════════════════════════════════════════════════════════════════ */
static uint16_t build_test_pdu(uint8_t *pdu, uint16_t max, uint16_t mid)
{
    static const uint8_t batch[40] = { 0x11, 0x22, 0x33 }; /* «батч» */
    return Coap_Build_Put(pdu, max, mid, "telemetry", "batch",
                          "SNET-Q-AABBCCDD", batch, sizeof batch);
}

TEST(test_conversation_happy_path) {
    static const Stage st[] = {
        { "AT+CCOAPNEW=\"10.0.0.1\",5683,0", "\r\n+CCOAPNEW: 1\r\n\r\nOK\r\n" },
        { "AT+CCOAPSEND=1,",
          "\r\nOK\r\n\r\n+CCOAPNMI: 1,4,\"60441234\"\r\n" }, /* ACK 2.04, наш MID */
        { "AT+CCOAPDEL=1", "\r\nOK\r\n" },
    };
    ModemSim m; modem_init(&m, st, 3);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);

    uint8_t pdu[128];
    uint16_t n = build_test_pdu(pdu, sizeof pdu, 0x1234);
    ASSERT_TRUE(n > 0);
    ASSERT_TRUE(Sim7070_Coap_Put(&io, &e, "10.0.0.1", 5683, pdu, n, 0x1234));

    ASSERT_EQ(m.armed, 3); /* усі три команди пішли в правильному порядку */
    char lenpart[24];
    snprintf(lenpart, sizeof lenpart, "AT+CCOAPSEND=1,%u,\"", (unsigned)n);
    ASSERT_TRUE(strstr(m.tx, lenpart) != NULL);   /* cid з URC + довжина PDU */
    ASSERT_TRUE(m.max_chunk <= 2 * AT_HEX_CHUNK); /* hex — чанками, не моноліт */
}

TEST(test_conversation_new_fails_no_send) {
    static const Stage st[] = { { "AT+CCOAPNEW", "\r\nERROR\r\n" } };
    ModemSim m; modem_init(&m, st, 1);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);
    uint8_t pdu[128];
    uint16_t n = build_test_pdu(pdu, sizeof pdu, 0x1234);
    ASSERT_FALSE(Sim7070_Coap_Put(&io, &e, "10.0.0.1", 5683, pdu, n, 0x1234));
    ASSERT_TRUE(strstr(m.tx, "AT+CCOAPSEND") == NULL);
}

TEST(test_conversation_ok_without_nmi_is_not_delivery) {
    /* транспортний OK ≠ доставка: тиша замість NMI → 0 (кеш житиме, FW.51) */
    static const Stage st[] = {
        { "AT+CCOAPNEW", "\r\n+CCOAPNEW: 0\r\n\r\nOK\r\n" },
        { "AT+CCOAPSEND", "\r\nOK\r\n" },
        { "AT+CCOAPDEL=0", "\r\nOK\r\n" },
    };
    ModemSim m; modem_init(&m, st, 3);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);
    uint8_t pdu[128];
    uint16_t n = build_test_pdu(pdu, sizeof pdu, 0x1234);
    ASSERT_FALSE(Sim7070_Coap_Put(&io, &e, "10.0.0.1", 5683, pdu, n, 0x1234));
    ASSERT_TRUE(strstr(m.tx, "AT+CCOAPDEL=0") != NULL); /* сесію все одно прибрали */
}

TEST(test_conversation_nmi_4xx_rejected) {
    static const Stage st[] = {
        { "AT+CCOAPNEW", "\r\n+CCOAPNEW: 0\r\n\r\nOK\r\n" },
        { "AT+CCOAPSEND", "\r\nOK\r\n\r\n+CCOAPNMI: 0,4,\"60841234\"\r\n" },
        { "AT+CCOAPDEL=0", "\r\nOK\r\n" },
    };
    ModemSim m; modem_init(&m, st, 3);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);
    uint8_t pdu[128];
    uint16_t n = build_test_pdu(pdu, sizeof pdu, 0x1234);
    ASSERT_FALSE(Sim7070_Coap_Put(&io, &e, "10.0.0.1", 5683, pdu, n, 0x1234));
}

TEST(test_conversation_no_urc_cid_falls_back_to_zero) {
    static const Stage st[] = {
        { "AT+CCOAPNEW", "\r\nOK\r\n" }, /* модем без URC — буває */
        { "AT+CCOAPSEND=0,", "\r\nOK\r\n\r\n+CCOAPNMI: 0,4,\"60441234\"\r\n" },
        { "AT+CCOAPDEL=0", "\r\nOK\r\n" },
    };
    ModemSim m; modem_init(&m, st, 3);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);
    uint8_t pdu[128];
    uint16_t n = build_test_pdu(pdu, sizeof pdu, 0x1234);
    ASSERT_TRUE(Sim7070_Coap_Put(&io, &e, "10.0.0.1", 5683, pdu, n, 0x1234));
    ASSERT_EQ(m.armed, 3);
}

TEST(test_conversation_lowercase_nmi_hex) {
    /* нота показує lowercase hex від модема — приймаємо обидва регістри */
    static const Stage st[] = {
        { "AT+CCOAPNEW", "\r\n+CCOAPNEW: 0\r\n\r\nOK\r\n" },
        { "AT+CCOAPSEND", "\r\nOK\r\n\r\n+CCOAPNMI: 0,4,\"6044abcd\"\r\n" },
        { "AT+CCOAPDEL=0", "\r\nOK\r\n" },
    };
    ModemSim m; modem_init(&m, st, 3);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);
    uint8_t pdu[128];
    uint16_t n = build_test_pdu(pdu, sizeof pdu, 0xABCD);
    ASSERT_TRUE(Sim7070_Coap_Put(&io, &e, "10.0.0.1", 5683, pdu, n, 0xABCD));
}

TEST(test_resolve_host_urc_before_and_after_ok) {
    static const Stage before[] = {
        { "AT+CDNSGIP=\"api.silkennet.com\"",
          "\r\n+CDNSGIP: 1,\"api.silkennet.com\",\"10.20.30.40\"\r\n\r\nOK\r\n" },
    };
    ModemSim m; modem_init(&m, before, 1);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);
    char ip[16];
    ASSERT_TRUE(Sim7070_Resolve_Host(&io, &e, "api.silkennet.com", ip, sizeof ip));
    ASSERT_STREQ(ip, "10.20.30.40");

    static const Stage after[] = {
        { "AT+CDNSGIP=\"api.silkennet.com\"",
          "\r\nOK\r\n\r\n+CDNSGIP: 1,\"api.silkennet.com\",\"10.20.30.41\"\r\n" },
    };
    ModemSim m2; modem_init(&m2, after, 1);
    Sim7070Io io2 = { modem_src, modem_sink, &m2 };
    At_Engine_Reset(&e);
    ASSERT_TRUE(Sim7070_Resolve_Host(&io2, &e, "api.silkennet.com", ip, sizeof ip));
    ASSERT_STREQ(ip, "10.20.30.41");

    /* DNS впав → 0 (флеш цього кола пропускається, кеш живе — FW.51) */
    static const Stage fail[] = { { "AT+CDNSGIP", "\r\nERROR\r\n" } };
    ModemSim m3; modem_init(&m3, fail, 1);
    Sim7070Io io3 = { modem_src, modem_sink, &m3 };
    At_Engine_Reset(&e);
    ASSERT_FALSE(Sim7070_Resolve_Host(&io3, &e, "api.silkennet.com", ip, sizeof ip));
}

/* [FW.58] Предикат re-resolve: стрік провалів < поріг → тримаємо IP; >= поріг →
 * інвалідація CDNSGIP-кешу (наступний flush ре-резолвить — A-запис flip failover). */
TEST(test_fw58_reresolve_predicate) {
    ASSERT_FALSE(Coap_Reresolve_Due(0u));
    ASSERT_FALSE(Coap_Reresolve_Due((uint8_t)(COAP_RERESOLVE_THRESHOLD - 1u)));
    ASSERT_TRUE(Coap_Reresolve_Due(COAP_RERESOLVE_THRESHOLD));
    ASSERT_TRUE(Coap_Reresolve_Due(255u));
}


/* ════════════════════════════════════════════════════════════════════
 * 6. [FW.60] POLL-ПРИМІТИВИ — GET-білдер, payload-екстрактор, binary-read,
 *    сира UDP-розмова CA*-сім'ї
 * ════════════════════════════════════════════════════════════════════ */
#include "../queen/sim7070_udp.h"

/* Freeze-contract з Rails-боком: той самий hex заморожено у
 * spec/lib/coap_server_pdu_spec.rb (golden GET poll) — C-білдер ↔ Rails-парсер.
 * GET poll/SNET-Q-00000001?fw=42, MID 0x1234:
 * 40011234 B4 "poll" 0D02 <uid:15> 45 "fw=42" */
TEST(test_fw60_coap_build_get_golden) {
    uint8_t pdu[96];
    uint16_t n = Coap_Build_Get(pdu, sizeof pdu, 0x1234,
                                "poll", "SNET-Q-00000001", "fw=42", NULL);
    static const uint8_t expected[] = {
        0x40, 0x01, 0x12, 0x34,
        0xB4, 'p', 'o', 'l', 'l',
        0x0D, 0x02, 'S','N','E','T','-','Q','-','0','0','0','0','0','0','0','1',
        0x45, 'f','w','=','4','2'
    };
    ASSERT_EQ(n, (uint16_t)sizeof expected);
    ASSERT_TRUE(memcmp(pdu, expected, sizeof expected) == 0);
}

TEST(test_fw60_coap_build_get_two_queries_and_guards) {
    uint8_t pdu[96];
    /* Друга query-пара — окрема опція 15 з delta 0 (RFC 7252). */
    uint16_t n = Coap_Build_Get(pdu, sizeof pdu, 0x0001,
                                "ota", "X", "v=7", "ch=3");
    ASSERT_TRUE(n > 0u);
    /* ... B3"ota" 01"X" 43"v=7" 03"ch=3" — друга query delta=0, len=4 */
    ASSERT_EQ(pdu[4], 0xB3);              /* Uri-Path delta 11 len 3 */
    ASSERT_EQ(pdu[10], 0x43);             /* Uri-Query delta 4 len 3 */
    ASSERT_EQ(pdu[14], 0x04);             /* друга query: delta 0 len 4 */
    ASSERT_EQ(Coap_Build_Get(pdu, sizeof pdu, 1, "", "X", "q", NULL), 0);   /* порожній сегмент */
    ASSERT_EQ(Coap_Build_Get(pdu, 8, 1, "poll", "LONG-UID-123456", "q=1", NULL), 0); /* не влізло */
}

/* Golden SIMCom App Note: 2.05 Content із payload "024" — досі цей payload
 * викидався (читали лише 4-байтний header). Тепер він — сенс розмови. */
TEST(test_fw60_extract_payload_official_note) {
    uint8_t reply[32];
    uint16_t n = 0;
    ASSERT_TRUE(At_Hex_Decode(reply, sizeof reply, "60457233c02105ff303234", &n));
    const uint8_t *pl = NULL;
    uint16_t pl_len = 0;
    ASSERT_TRUE(Coap_Reply_Extract_Payload(reply, n, 0x7233, &pl, &pl_len));
    ASSERT_EQ(pl_len, 3);
    ASSERT_TRUE(memcmp(pl, "024", 3) == 0);
}

TEST(test_fw60_extract_payload_edges) {
    const uint8_t *pl = NULL;
    uint16_t pl_len = 9;
    /* 2.04 ACK без payload — валідно, тіла нема. */
    static const uint8_t ack[] = { 0x60, 0x44, 0x00, 0x07 };
    ASSERT_TRUE(Coap_Reply_Extract_Payload(ack, 4, 0x0007, &pl, &pl_len));
    ASSERT_EQ(pl_len, 0);
    /* Чужий MID на ACK → відмова. */
    ASSERT_FALSE(Coap_Reply_Extract_Payload(ack, 4, 0x0008, &pl, &pl_len));
    /* RST → відмова. */
    static const uint8_t rst[] = { 0x70, 0x00, 0x00, 0x07 };
    ASSERT_FALSE(Coap_Reply_Extract_Payload(rst, 4, 0x0007, &pl, &pl_len));
    /* TKL=2: токен проминається, payload після маркера на межі опцій. */
    static const uint8_t tkl2[] = { 0x62, 0x45, 0x00, 0x07, 0xAA, 0xBB, 0xFF, 0x01, 0x02 };
    ASSERT_TRUE(Coap_Reply_Extract_Payload(tkl2, sizeof tkl2, 0x0007, &pl, &pl_len));
    ASSERT_EQ(pl_len, 2);
    ASSERT_EQ(pl[0], 0x01);
    /* Маркер без тіла → format error (дзеркало Rails-парсера). */
    static const uint8_t bare[] = { 0x60, 0x45, 0x00, 0x07, 0xFF };
    ASSERT_FALSE(Coap_Reply_Extract_Payload(bare, sizeof bare, 0x0007, &pl, &pl_len));
    /* 0xFF ВСЕРЕДИНІ опції ≠ маркер (клас бага FW.56): опція 11 len 1
     * зі значенням 0xFF, справжній payload далі. */
    static const uint8_t ff_opt[] = { 0x60, 0x45, 0x00, 0x07, 0xB1, 0xFF, 0xFF, 0x5A };
    ASSERT_TRUE(Coap_Reply_Extract_Payload(ff_opt, sizeof ff_opt, 0x0007, &pl, &pl_len));
    ASSERT_EQ(pl_len, 1);
    ASSERT_EQ(pl[0], 0x5A);
}

/* Binary-read повз токенайзер: 0x0A всередині сирих байтів НЕ ламає читання. */
TEST(test_fw60_at_read_n_binary_safe) {
    static const Stage st[] = { { "PING", "\x01\x0A\xFF\x0D\x05rest" } };
    ModemSim m; modem_init(&m, st, 1);
    Sim7070Io io = { modem_src, modem_sink, &m };
    ASSERT_TRUE(io.sink(io.io, (const uint8_t *)"PING", 4)); /* озброїти reply */
    uint8_t buf[8];
    ASSERT_EQ(At_Read_N(io.src, io.io, buf, 5), 5);
    ASSERT_EQ(buf[1], 0x0A); /* лічене читання, не line-based */
    ASSERT_EQ(buf[2], 0xFF);
    /* Тиша після вичерпання reply → недочит. */
    ASSERT_EQ(At_Read_N(io.src, io.io, buf, 8), 4); /* "rest" */
}

/* Повна сира UDP-розмова: CAOPEN → '>' → PDU → OK → +CADATAIND → CARECV
 * (заголовок посимвольно + сирі байти З 0x0A всередині) → CACLOSE. */
TEST(test_fw60_udp_fetch_happy_path) {
    /* Відповідь: 2.05 (MID 0x1234) + 0xFF + 5 байт тіла (з \n усередині). */
    static const Stage st[] = {
        { "AT+CAOPEN=0,0,\"UDP\",\"10.0.0.1\",5683",
          "\r\n+CAOPEN: 0,0\r\n\r\nOK\r\n" },
        { "AT+CASEND=0,", "\r\n> " },
        { "\x40\x01\x12\x34", "\r\nOK\r\n\r\n+CADATAIND: 0\r\n" },
        { "AT+CARECV=0,",
          "\r\n+CARECV: 10,\x60\x45\x12\x34\xFF\x21\x0A\x22\x0D\x23\r\nOK\r\n" },
        { "AT+CACLOSE=0", "\r\nOK\r\n" },
    };
    ModemSim m; modem_init(&m, st, 5);
    Sim7070Io io = { modem_src, modem_sink, &m };
    AtEngine e; At_Engine_Reset(&e);

    static const uint8_t pdu[] = { 0x40, 0x01, 0x12, 0x34 };
    uint8_t reply[64];
    uint16_t got = Sim7070_Udp_Fetch(&io, &e, "10.0.0.1", 5683,
                                     pdu, sizeof pdu, reply, sizeof reply);
    ASSERT_EQ(got, 10);
    const uint8_t *pl = NULL;
    uint16_t pl_len = 0;
    ASSERT_TRUE(Coap_Reply_Extract_Payload(reply, got, 0x1234, &pl, &pl_len));
    ASSERT_EQ(pl_len, 5);
    ASSERT_EQ(pl[1], 0x0A); /* сирий 0x0A пережив увесь тракт */
}

TEST(test_fw60_udp_fetch_failures) {
    uint8_t reply[32];
    /* MID без 0x00-байтів: ModemSim текстовий (strstr), NUL обриває матчинг. */
    static const uint8_t pdu[] = { 0x40, 0x01, 0x01, 0x01 };

    /* CAOPEN result != 0 → сокет не відкрився. */
    static const Stage bad_open[] = {
        { "AT+CAOPEN=0,", "\r\n+CAOPEN: 0,23\r\n\r\nOK\r\n" },
        { "AT+CACLOSE=0", "\r\nOK\r\n" },
    };
    ModemSim m1; modem_init(&m1, bad_open, 2);
    Sim7070Io io1 = { modem_src, modem_sink, &m1 };
    AtEngine e1; At_Engine_Reset(&e1);
    ASSERT_EQ(Sim7070_Udp_Fetch(&io1, &e1, "10.0.0.1", 5683, pdu, 4, reply, sizeof reply), 0);

    /* Тиша замість +CADATAIND (сервер не відповів) → 0, сокет прибрано. */
    static const Stage no_data[] = {
        { "AT+CAOPEN=0,", "\r\n+CAOPEN: 0,0\r\n\r\nOK\r\n" },
        { "AT+CASEND=0,", "\r\n> " },
        { "\x40\x01\x01\x01", "\r\nOK\r\n" },
        { "AT+CACLOSE=0", "\r\nOK\r\n" },
    };
    ModemSim m2; modem_init(&m2, no_data, 4);
    Sim7070Io io2 = { modem_src, modem_sink, &m2 };
    AtEngine e2; At_Engine_Reset(&e2);
    ASSERT_EQ(Sim7070_Udp_Fetch(&io2, &e2, "10.0.0.1", 5683, pdu, 4, reply, sizeof reply), 0);
    ASSERT_TRUE(strstr(m2.tx, "AT+CACLOSE=0") != NULL); /* best-effort прибирання */

    /* CARECV каже більше, ніж влазить у буфер → відмова без переповнення. */
    static const Stage oversize[] = {
        { "AT+CAOPEN=0,", "\r\n+CAOPEN: 0,0\r\n\r\nOK\r\n" },
        { "AT+CASEND=0,", "\r\n> " },
        { "\x40\x01\x01\x01", "\r\nOK\r\n\r\n+CADATAIND: 0\r\n" },
        { "AT+CARECV=0,", "\r\n+CARECV: 999,junk" },
        { "AT+CACLOSE=0", "\r\nOK\r\n" },
    };
    ModemSim m3; modem_init(&m3, oversize, 5);
    Sim7070Io io3 = { modem_src, modem_sink, &m3 };
    AtEngine e3; At_Engine_Reset(&e3);
    ASSERT_EQ(Sim7070_Udp_Fetch(&io3, &e3, "10.0.0.1", 5683, pdu, 4, reply, 32), 0);
}

/* ════════════════════════════════════════════════════════════════════ */
int main(void)
{
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.3/FW.56] AT-engine + CoAP PDU + SIM7070G розмова (host)\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    printf("\n— Токенайзер —\n");
    RUN(test_tok_ok_with_framing);
    RUN(test_tok_error);
    RUN(test_tok_cme_error_code);
    RUN(test_tok_echo_then_urc_then_ok);
    RUN(test_tok_long_line_truncated_but_classified);
    RUN(test_tok_ok_inside_word_is_not_final);

    printf("\n— Транзакції —\n");
    RUN(test_transact_urc_before_ok);
    RUN(test_transact_error_and_cme);
    RUN(test_transact_silence_is_timeout);
    RUN(test_transact_noise_lines_skipped);
    RUN(test_await_urc_after_final);

    printf("\n— Парсери + hex —\n");
    RUN(test_extract_quoted_dnsgip);
    RUN(test_int_after_colon);
    RUN(test_hex_roundtrip_and_rejects);

    printf("\n— CoAP PDU —\n");
    RUN(test_coap_build_golden_layout);
    RUN(test_coap_build_golden_mid_ff);
    RUN(test_coap_build_guards);
    RUN(test_coap_parse_official_note_reply);
    RUN(test_coap_reply_rejects);

    printf("\n— Повна розмова —\n");
    RUN(test_conversation_happy_path);
    RUN(test_conversation_new_fails_no_send);
    RUN(test_conversation_ok_without_nmi_is_not_delivery);
    RUN(test_conversation_nmi_4xx_rejected);
    RUN(test_conversation_no_urc_cid_falls_back_to_zero);
    RUN(test_conversation_lowercase_nmi_hex);
    RUN(test_resolve_host_urc_before_and_after_ok);
    RUN(test_fw58_reresolve_predicate);

    printf("\n— [FW.60] Poll-примітиви + сира UDP-розмова —\n");
    RUN(test_fw60_coap_build_get_golden);
    RUN(test_fw60_coap_build_get_two_queries_and_guards);
    RUN(test_fw60_extract_payload_official_note);
    RUN(test_fw60_extract_payload_edges);
    RUN(test_fw60_at_read_n_binary_safe);
    RUN(test_fw60_udp_fetch_happy_path);
    RUN(test_fw60_udp_fetch_failures);

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
