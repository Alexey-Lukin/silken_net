// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * sim7070_coap.h — [FW.3/FW.56] CoAP-PUT розмова з SIM7070G (pure-оркестратор).
 *
 * Уся послідовність CCOAPNEW → CCOAPSEND(hex-PDU) → +CCOAPNMI → CCOAPDEL
 * живе тут, над callback'ами TX/RX — без HAL. main.c дає лише UART-клей;
 * host-тести підставляють скриптований модем і ганяють ті самі байти.
 *
 * Доставка = відповідь сервера класу 2.xx у +CCOAPNMI (Coap_Reply_Confirms),
 * НЕ транспортний `OK` — саме на цьому ключується звільнення кешу (FW.51):
 * `OK` каже «модем прийняв», NMI каже «ліс почуто».
 *
 * Hex летить чанками (AT_HEX_CHUNK байт PDU за виклик sink) — старий
 * побайтовий TX робив флеш багатосекундним без жодної потреби.
 *
 * Канон: 03_02 §4 + 00_07 FW.3/FW.56.
 */
#ifndef SILKEN_SIM7070_COAP_H
#define SILKEN_SIM7070_COAP_H

#include <stdio.h>

#include "at_engine.h"
#include "coap_pdu.h"

#define AT_HEX_CHUNK 32u /* 32 байти PDU → 64 hex-символи на один UART TX */

/* UART TX: 1 = передано, 0 = відмова транспорту. */
typedef int (*AtSink)(void *io, const uint8_t *bytes, uint16_t n);

typedef struct {
    AtByteSource src; /* RX: володіє interbyte/deadline годинником */
    AtSink       sink;
    void        *io;
} Sim7070Io;

static inline int Sim7070_Send_Str(Sim7070Io *m, const char *s)
{
    return m->sink(m->io, (const uint8_t *)s, (uint16_t)strlen(s));
}

/* DNS сімейства SIMCom: AT+CDNSGIP="host" → URC `+CDNSGIP: 1,"host","ip"`.
 * CCOAPNEW приймає IP, не домен. 1 = ip заповнено. */
static inline int Sim7070_Resolve_Host(Sim7070Io *m, AtEngine *e,
                                       const char *host, char *ip, uint16_t ip_max)
{
    char cmd[96];
    if (snprintf(cmd, sizeof cmd, "AT+CDNSGIP=\"%s\"\r\n", host) >= (int)sizeof cmd) return 0;
    if (!Sim7070_Send_Str(m, cmd)) return 0;

    AtTransact t;
    At_Transact_Init(&t, "+CDNSGIP:");
    AtTxResult r = At_Transact_Run(e, &t, m->src, m->io);
    if (r != AT_TX_OK) return 0;

    /* URC буває й після OK — дочекаємось, якщо дорогою не впіймали. */
    if (!t.urc_seen && !At_Await_Urc(e, "+CDNSGIP:", t.urc, m->src, m->io)) return 0;
    return At_Extract_Quoted(t.urc, 2, ip, ip_max);
}

/* [ARCH.54 Шар 1] AT+CSQ → `+CSQ: <rssi>,<ber>` — сила стільникового
 * сигналу для health-блоку QATT-v2. 3GPP: 0..31 = -113..-51 дБм,
 * 99 = невідомо/нема мережі. Повертає 1 + *csq_out при успіху; 0 =
 * розмова провалилась (модем спить/ефір мовчить) — викликач лишає
 * попереднє значення (сентинель 0xFF до першого успіху). CSQ — рядок
 * ВІДПОВІДІ (не URC-подія), тож він приходить ДО фіналу OK і читається
 * з capture-слоту тим самим механізмом, що +CDNSGIP/+CCOAPNEW. */
static inline int Sim7070_Read_Csq(Sim7070Io *m, AtEngine *e, uint8_t *csq_out)
{
    if (!Sim7070_Send_Str(m, "AT+CSQ\r\n")) return 0;

    AtTransact t;
    At_Transact_Init(&t, "+CSQ:");
    if (At_Transact_Run(e, &t, m->src, m->io) != AT_TX_OK) return 0;
    if (!t.urc_seen) return 0;

    int32_t rssi = At_Int_After_Colon(t.urc, 0);
    if (rssi < 0 || rssi > 99) return 0; /* поза 3GPP-довідником = сміття */
    *csq_out = (uint8_t)rssi;
    return 1;
}

/* [HW.31] «Лише LTE» — УМОВА передачі, не налаштування. AT+CNMP=38 вимикає GSM
 * (SIMCom AT Manual V1.03 §5.2.16), а GSM-стелі підсилення модуля нижчі за пік
 * антени поз. 11 (queen_antenna_shortlist §2.1): у 2G Королева вийшла б за межі,
 * під які модуль сертифіковано. Рядок команди — один дім для init і воріт. */
#define SIM7070_CMD_LTE_ONLY "AT+CNMP=38\r\n"
#define SIM7070_CMD_READ_MODE "AT+CNMP?\r\n"
#define SIM7070_MODE_LTE_ONLY 38  /* той самий 38, що в рядку команди вище */

/* PDP-контекст APP-мережі: pdpidx 1, action 1 = Active (V1.03 §7.2.1). ⚠️ Режим
 * NO_SAVE: після самочинного ребута модема контекст не встає сам. action 2 (Auto
 * Active — модем сам повторює невдалу активацію) свідомо НЕ взято: фоновий
 * повтор при недоступній мережі може тримати модем поза PSM, а цю ціну ніхто
 * не міряв (03_02 §4, кандидат стенда). */
#define SIM7070_CMD_PDP_ACTIVATE "AT+CNACT=1,1\r\n"

/* Вердикт воріт. REFUSED — не передавати; HELD — режим перечитано й він 38;
 * REASSERTED — режим стверджено заново, і PDP уже переактивовано в LTE. */
#define SIM7070_GATE_REFUSED    0
#define SIM7070_GATE_HELD       1
#define SIM7070_GATE_REASSERTED 2

/* Ворота перед першою RF-командою flush'у. Режим — стан ЗАЛІЗА, тож ознаку,
 * поставлену раз за boot, щофлешу ПЕРЕЧИТУЄМО (`AT+CNMP?`, одна AT-розмова):
 * «+CNMP: 38» → HELD, і більше нічого не шлемо. Режим інший, нечитаний або
 * ознаки ще немає → AT+CNMP=38: OK → *confirmed = 1, PDP переактивується вже в
 * LTE (init-контекст міг піднятись в іншому RAT або не піднятись; його провал
 * проявить сама CoAP-розмова) → REASSERTED. ERROR · +CME · тиша → REFUSED:
 * викликач НЕ передає, слоти живі (FW.51), наступний flush повторить.
 * ⚠️ Дві стелі. (1) Реєстрацію в мережі модем робить сам, тож ворота тримають ДАНІ
 * (і PDP init'у — main.c), не сигналізацію реєстрації: на свіжому модемі до першого OK
 * вона може піти GSM-ом. (2) Режим AUTO_SAVE (V1.03 §5.2.16) — самочинний ребут
 * модема його НЕ скидає; readback ловить те, чого AUTO_SAVE не обіцяє: втрату NVRAM
 * чи заводський скид модема без ребута Королеви (00_07 HW.31). */
static inline int Sim7070_Ensure_Lte_Only(Sim7070Io *m, AtEngine *e, uint8_t *confirmed)
{
    AtTransact t;
    if (*confirmed) {
        At_Transact_Init(&t, "+CNMP:");
        if (Sim7070_Send_Str(m, SIM7070_CMD_READ_MODE) &&
            At_Transact_Run(e, &t, m->src, m->io) == AT_TX_OK &&
            t.urc_seen && At_Int_After_Colon(t.urc, -1) == SIM7070_MODE_LTE_ONLY) {
            return SIM7070_GATE_HELD;
        }
        *confirmed = 0u;  /* не 38 або нечитано — ознака більше не правда */
    }

    At_Transact_Init(&t, NULL);
    if (!Sim7070_Send_Str(m, SIM7070_CMD_LTE_ONLY)) return SIM7070_GATE_REFUSED;
    if (At_Transact_Run(e, &t, m->src, m->io) != AT_TX_OK) return SIM7070_GATE_REFUSED;
    *confirmed = 1u;

    At_Transact_Init(&t, NULL);
    if (Sim7070_Send_Str(m, SIM7070_CMD_PDP_ACTIVATE)) (void)At_Transact_Run(e, &t, m->src, m->io);
    return SIM7070_GATE_REASSERTED;
}

/* [HW.41] Повторна активація PDP — коли ПОПЕРЕДНЯ розмова впала (DNS чи PUT).
 * Контекст, що не піднявся на init чи впав пізніше, до ребута сам не встає
 * (NO_SAVE), і кожен flush падав би на DNS без жодної спроби. Best-effort:
 * ERROR тут може означати й «уже активний», тож вердикт дає сама розмова, не
 * цей OK. Повертає 1 на OK. */
static inline int Sim7070_Reactivate_Pdp(Sim7070Io *m, AtEngine *e)
{
    AtTransact t;
    At_Transact_Init(&t, NULL);
    if (!Sim7070_Send_Str(m, SIM7070_CMD_PDP_ACTIVATE)) return 0;
    return At_Transact_Run(e, &t, m->src, m->io) == AT_TX_OK;
}

/* Повна PUT-розмова. Повертає 1 лише при підтвердженій доставці (2.xx,
 * наш MID). CCOAPDEL — best-effort: сесію прибираємо, але вердикт уже є. */
static inline int Sim7070_Coap_Put(Sim7070Io *m, AtEngine *e,
                                   const char *server_ip, uint16_t port,
                                   const uint8_t *pdu, uint16_t pdu_len, uint16_t mid)
{
    char cmd[80];
    AtTransact t;

    /* 1. Сесія: запитуємо cid 0, віримо тому, що модем поверне в URC. */
    if (snprintf(cmd, sizeof cmd, "AT+CCOAPNEW=\"%s\",%u,0\r\n",
                 server_ip, (unsigned)port) >= (int)sizeof cmd) return 0;
    if (!Sim7070_Send_Str(m, cmd)) return 0;
    At_Transact_Init(&t, "+CCOAPNEW:");
    if (At_Transact_Run(e, &t, m->src, m->io) != AT_TX_OK) return 0;
    int32_t cid = t.urc_seen ? At_Int_After_Colon(t.urc, 0) : 0;

    /* 2. PDU як hex: заголовок команди, чанки, закривні лапки. */
    if (snprintf(cmd, sizeof cmd, "AT+CCOAPSEND=%ld,%u,\"",
                 (long)cid, (unsigned)pdu_len) >= (int)sizeof cmd) return 0;
    if (!Sim7070_Send_Str(m, cmd)) return 0;

    char hex[2u * AT_HEX_CHUNK];
    for (uint16_t off = 0; off < pdu_len; off += AT_HEX_CHUNK) {
        uint16_t rem = (uint16_t)(pdu_len - off);
        uint16_t n = (rem < AT_HEX_CHUNK) ? rem : (uint16_t)AT_HEX_CHUNK;
        At_Hex_Encode(hex, pdu + off, n);
        if (!m->sink(m->io, (const uint8_t *)hex, (uint16_t)(2u * n))) return 0;
    }
    if (!Sim7070_Send_Str(m, "\"\r\n")) return 0;

    At_Transact_Init(&t, NULL);
    if (At_Transact_Run(e, &t, m->src, m->io) != AT_TX_OK) return 0;

    /* 3. Вердикт доставки: +CCOAPNMI з hex-відповіддю сервера. */
    char urc[AT_LINE_MAX];
    int confirmed = 0;
    if (At_Await_Urc(e, "+CCOAPNMI:", urc, m->src, m->io)) {
        char    reply_hex[AT_LINE_MAX];
        uint8_t reply[AT_LINE_MAX / 2u];
        uint16_t reply_len = 0;
        if (At_Extract_Quoted(urc, 1, reply_hex, sizeof reply_hex) &&
            At_Hex_Decode(reply, sizeof reply, reply_hex, &reply_len)) {
            confirmed = Coap_Reply_Confirms(reply, reply_len, mid);
        }
    }

    /* 4. Прибрати сесію (модем тримає обмежений пул інстансів). */
    if (snprintf(cmd, sizeof cmd, "AT+CCOAPDEL=%ld\r\n", (long)cid) < (int)sizeof cmd &&
        Sim7070_Send_Str(m, cmd)) {
        At_Transact_Init(&t, NULL);
        (void)At_Transact_Run(e, &t, m->src, m->io);
    }
    return confirmed;
}

/* [FW.58] Скільки flush-РОЗМОВ поспіль (де ВСІ retry впали) до інвалідації
 * CDNSGIP-кешу. Мертвий CoAP-IP (A-запис flip на бекенді = єдиний zero-infra
 * глобальний failover) інакше довбеться до IWDG-ребута. 3 розмови × COAP_MAX_RETRIES
 * = ~9 доказів «IP мертвий» перед витратою DNS-раунду. Стрік окремий від
 * g_coap_fail_count (той — lifetime health-одометр), reset на першому success. */
#ifndef COAP_RERESOLVE_THRESHOLD
#define COAP_RERESOLVE_THRESHOLD 3u
#endif
static inline int Coap_Reresolve_Due(uint8_t consec_fail)
{
    return consec_fail >= COAP_RERESOLVE_THRESHOLD;
}

#endif /* SILKEN_SIM7070_COAP_H */
