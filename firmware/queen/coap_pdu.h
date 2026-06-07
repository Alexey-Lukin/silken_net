/*
 * coap_pdu.h — [FW.56] мінімальний CoAP PDU builder/parser (RFC 7252, pure).
 *
 * Знахідка FW.56: SIM7070G — НЕ CoAP-стек, а UDP-труба. `AT+CCOAPSEND` шле
 * hex-байти ЯК Є, тож CoAP-заголовок, Uri-Path і payload будує хост-MCU;
 * відповідь сервера прилітає URC'ом `+CCOAPNMI` тим самим hex-PDU. Стара
 * граматика (`method=2, URI у лапках`) у сімействі SIMCom не існує.
 *
 * Builder покриває рівно наш wire-контракт: CON PUT
 * /telemetry/batch/<queen_uid> з бінарним payload (формат батча — 03_02 §3).
 * Parser читає заголовок відповіді — клас 2.xx = доставка підтверджена,
 * саме на нього ключується звільнення кешу (FW.51).
 *
 * One-Home: Queen firmware ТА host-тести компілюють цей самий код.
 * Канон: 03_02 §4 + 00_07 FW.56. Golden-вектор відповіді — з офіційної
 * SIMCom CoAP App Note (test_at_engine.c).
 */
#ifndef SILKEN_COAP_PDU_H
#define SILKEN_COAP_PDU_H

#include <stdint.h>
#include <string.h>

#define COAP_VER1_CON_TKL0  0x40u  /* ver=1, type=CON, token len=0 */
#define COAP_CODE_PUT       0x03u  /* 0.03 */
#define COAP_OPT_URI_PATH   11u
#define COAP_PAYLOAD_MARKER 0xFFu

/* Опція з delta/len 0..268 (нібл 13 + розширений байт — RFC 7252 §3.1).
 * Наші Uri-Path сегменти («telemetry», «batch», UID ≤ 31) у цей діапазон
 * вкладаються з запасом. Повертає нову позицію, 0 = не влізло. */
static inline uint16_t Coap_Emit_Option(uint8_t *out, uint16_t pos, uint16_t out_max,
                                        uint16_t delta, const uint8_t *val, uint16_t len)
{
    if (delta > 268u || len > 268u) return 0;

    uint8_t dn = (delta < 13u) ? (uint8_t)delta : 13u;
    uint8_t ln = (len   < 13u) ? (uint8_t)len   : 13u;
    uint16_t need = (uint16_t)(1u + (dn == 13u) + (ln == 13u) + len);
    if (pos + need > out_max) return 0;

    out[pos++] = (uint8_t)((dn << 4) | ln);
    if (dn == 13u) out[pos++] = (uint8_t)(delta - 13u);
    if (ln == 13u) out[pos++] = (uint8_t)(len - 13u);
    memcpy(out + pos, val, len);
    return (uint16_t)(pos + len);
}

/* CON PUT /<seg1>/<seg2>/<seg3> + payload. Повертає довжину PDU, 0 = буфер
 * замалий / порожній сегмент. message_id — лічильник викликача (анти-дублі
 * на боці CoAP-сервера). */
static inline uint16_t Coap_Build_Put(uint8_t *out, uint16_t out_max,
                                      uint16_t message_id,
                                      const char *seg1, const char *seg2, const char *seg3,
                                      const uint8_t *payload, uint16_t payload_len)
{
    if (out_max < 4u) return 0;
    out[0] = COAP_VER1_CON_TKL0;
    out[1] = COAP_CODE_PUT;
    out[2] = (uint8_t)(message_id >> 8);
    out[3] = (uint8_t)(message_id & 0xFFu);

    uint16_t pos = 4u;
    const char *segs[3] = { seg1, seg2, seg3 };
    uint16_t delta = COAP_OPT_URI_PATH; /* перша опція — повна дельта, далі 0 */
    for (int i = 0; i < 3; i++) {
        size_t l = segs[i] ? strlen(segs[i]) : 0u;
        if (l == 0u) return 0;
        pos = Coap_Emit_Option(out, pos, out_max, delta, (const uint8_t *)segs[i], (uint16_t)l);
        if (pos == 0u) return 0;
        delta = 0u;
    }

    if (payload_len > 0u) {
        if (pos + 1u + payload_len > out_max) return 0;
        out[pos++] = COAP_PAYLOAD_MARKER;
        memcpy(out + pos, payload, payload_len);
        pos = (uint16_t)(pos + payload_len);
    }
    return pos;
}

/* ── Відповідь сервера (з +CCOAPNMI) ────────────────────────────────── */

typedef struct {
    uint8_t  version;   /* мусить бути 1 */
    uint8_t  type;      /* 0 CON / 1 NON / 2 ACK / 3 RST */
    uint8_t  code;      /* class<<5 | detail: 0x44 = 2.04 Changed */
    uint16_t message_id;
} CoapHead;

static inline int Coap_Parse_Head(const uint8_t *in, uint16_t len, CoapHead *h)
{
    if (len < 4u) return 0;
    h->version    = (uint8_t)(in[0] >> 6);
    h->type       = (uint8_t)((in[0] >> 4) & 0x03u);
    h->code       = in[1];
    h->message_id = (uint16_t)(((uint16_t)in[2] << 8) | in[3]);
    return h->version == 1u;
}

static inline uint8_t Coap_Code_Class(uint8_t code) { return (uint8_t)(code >> 5); }

/* Доставка підтверджена: валідний заголовок + клас 2.xx (+ RST = відмова).
 * MID звіряє викликач — ACK несе MID нашого CON. */
static inline int Coap_Reply_Confirms(const uint8_t *in, uint16_t len,
                                      uint16_t expect_mid)
{
    CoapHead h;
    if (!Coap_Parse_Head(in, len, &h)) return 0;
    if (h.type == 3u) return 0;                     /* RST */
    if (h.type == 2u && h.message_id != expect_mid) return 0; /* чужий ACK */
    return Coap_Code_Class(h.code) == 2u;
}

#endif /* SILKEN_COAP_PDU_H */
