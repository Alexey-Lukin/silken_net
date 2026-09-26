// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * sim7070_init.h — [HW.41] init-послідовність SIM7070G: ОДИН дім для
 * `main.c` і host-тесту (`test_queen_logic.c` §13 кличе цю саму таблицю).
 *
 * ЧОМУ таблиця, а не рядок викликів у main(): main.c HAL-залежний і host-сюїтою
 * не компілюється, тож тест тримав власну КОПІЮ послідовності — і копія доводила
 * себе, а не прошивку (`firmware`-скіл гоча #19). Тепер обидва читають цей масив.
 *
 * Граматику кожної команди звірено текстом із SIMCom SIM7070_SIM7080_SIM7090
 * Series AT Command Manual V1.03 (2026-09-27): CNMP §5.2.16 · CMNB §5.2.17 ·
 * CPSMS §5.2.18 · CEDRXS §5.2.42 · CGDCONT §6.2.2 · CNACT §7.2.1 · CNCFG §7.2.2.
 * Режими збереження: усе AUTO_SAVE, крім CNACT (NO_SAVE — після ребута модема
 * контекст сам не встає; його підхоплюють ворота flush'у, sim7070_coap.h).
 * ⚠️ Мануал ≠ модем: живий транскрипт — firmware/scripts/bench/RUNBOOK.md 5.1.
 *
 * Pure C, без HAL. Канон — 03_02 §4 (таблиця init-команд).
 */
#ifndef SILKEN_SIM7070_INIT_H
#define SILKEN_SIM7070_INIT_H

#include <stddef.h>
#include <stdint.h>

#include "sim7070_coap.h"   /* SIM7070_CMD_LTE_ONLY · SIM7070_CMD_PDP_ACTIVATE */

/* [HW.41] APN — build-time config, НЕ хардкод одного оператора: `#ifndef`-гейт
 * (голий #define клобберить `-D`, клас FW2_CCM_ENABLED/ARCH34_HELIUM_ENABLED)
 * override'иться при білді: `-DQUEEN_APN='"<carrier-apn>"'`. Дефолт `""` — не
 * здогадка «internet», а 3GPP-порожній APN (TS 27.007 §10.1.1: мережа сама добирає
 * профіль SIM'и), тож неконфігурований білд behavior-identical з auto-APN. */
#ifndef QUEEN_APN
#define QUEEN_APN  ""
#endif

/* Дві сім'ї PDP-контекстів, і номери в них — РІЗНІ простори: 3GPP `cid`
 * (CGDCONT, 1…15) ⊥ SIMCom APP-мережа `pdpidx` (CNACT/CNCFG, 0…3). Що
 * «pdpidx 1 = cid 1», мануал не стверджує — тож APN APP-мережі задаємо ЯВНО її
 * власною командою, а не сподіваємось, що модем візьме його з CGDCONT. */
#define SIM7070_CMD_CGDCONT(apn) ("AT+CGDCONT=1,\"IP\",\"" apn "\"\r\n")
/* CNCFG=<pdpidx>,<ip_type>,<APN>: ip_type 1 = IPv4 (той самий «IP», що CGDCONT).
 * APN null/відсутній → модем просить підписочний (V1.03 §7.2.2, дефолт NULL). */
#define SIM7070_CMD_CNCFG(apn)   ("AT+CNCFG=1,1,\"" apn "\"\r\n")

typedef enum {
    SIM7070_INIT_PLAIN      = 0,  /* провал не фатальний: модем міг ще прокидатись */
    SIM7070_INIT_LTE_MODE   = 1,  /* вердикт → lte_only_ok (ворота HW.31) */
    SIM7070_INIT_APP_APN    = 2   /* лише коли APN задано (див. Sim7070_Init_Step_Enabled) */
} Sim7070InitRole;

typedef struct {
    const char *cmd;
    uint8_t     role;
} Sim7070InitStep;

/* Порядок несучий: радіо (режим, RAT) → APN → енергоповедінка; активація PDP
 * (CNACT) іде ОКРЕМО після таблиці — лише за підтвердженого «лише LTE». */
static const Sim7070InitStep kSim7070Init[] = {
    /* Ехо геть (токенайзер його переживає, але ефір чистіший) і перевірка зв'язку. */
    { "ATE0\r\n", SIM7070_INIT_PLAIN },
    { "AT\r\n",   SIM7070_INIT_PLAIN },
    /* [HW.31] «Лише LTE» несе й відповідність антени поз. 11: GSM-стелі
     * підсилення модуля нижчі за пік рекомендованої антени (queen_antenna_shortlist
     * §2.1). Не підтверджено — ворота flush'у повторять і до OK нічого не передадуть. */
    { SIM7070_CMD_LTE_ONLY, SIM7070_INIT_LTE_MODE },
    /* [HW.41] Cat-M ⊥ NB-IoT — ЯВНО (⚖️ founder 2026-09-26): =3 обидва, бо Kyivstar
     * публічно заявляє NB-IoT, а зі збереженим =1 Королева не підʼєдналась би. */
    { "AT+CMNB=3\r\n", SIM7070_INIT_PLAIN },
    /* [HW.41] Явний 3GPP PDP-контекст cid=1 (той самий, що бенч-чеклист 02_04 §10.2
     * п.4 типує вручну). */
    { SIM7070_CMD_CGDCONT(QUEEN_APN), SIM7070_INIT_PLAIN },
    /* [HW.41] APN APP-мережі — її власною командою (див. вище). */
    { SIM7070_CMD_CNCFG(QUEEN_APN), SIM7070_INIT_APP_APN },
    /* [HW.10] PSM: TAU "00100001" = одиниця 001 (1 год, GPRS Timer 3) × 1 = 1 год
     * під годинний flush; Active-Time "00000000" = 0 × 2 с (GPRS Timer 2) — одразу
     * в PSM. RAU і GPRS-READY у модемі «Not supported» — порожні поля. */
    { "AT+CPSMS=1,,,\"00100001\",\"00000000\"\r\n", SIM7070_INIT_PLAIN },
    /* eDRX для ОБОХ AcT (4 = CAT-M, 5 = NB-IoT), бо RAT обирає мережа (CMNB=3);
     * "0010" = 20.48 с — короткий цикл для downlink-сприйнятливості. */
    { "AT+CEDRXS=1,4,\"0010\"\r\n", SIM7070_INIT_PLAIN },
    { "AT+CEDRXS=1,5,\"0010\"\r\n", SIM7070_INIT_PLAIN },
};
#define SIM7070_INIT_STEPS (sizeof(kSim7070Init) / sizeof(kSim7070Init[0]))

/* CNCFG — лише за ЗАДАНОГО APN: порожній рядок модем може прочитати інакше, ніж
 * «null/відсутній», тож неконфігурований білд лишає підписочний дефолт недоторканим
 * (V1.03 §7.2.2). Решта кроків — завжди. APN — аргумент, щоб host-тест судив обидві
 * гілки в одному TU; прошивка подає QUEEN_APN. */
static inline int Sim7070_Init_Step_Enabled(const Sim7070InitStep *s, const char *apn)
{
    if (s->role == SIM7070_INIT_APP_APN) return apn[0] != '\0';
    return 1;
}

/* Одна AT-розмова з бюджетом init'у — її подає викликач (main.c: SIM7070_Transact). */
typedef AtTxResult (*Sim7070InitTransactFn)(void *ctx, const char *cmd);

/* Прогнати init: таблиця → активація PDP лише за підтвердженого «лише LTE» (HW.31:
 * на модемі з GSM активація пішла б 2G; не підтверджено — PDP підніме ворота flush'у).
 * Провал будь-якого кроку не фатальний; вердикт тримаємо з двох місць: режим →
 * *out_lte_ok, невдала активація → *out_pdp_suspect (контекст NO_SAVE, до ребута сам не
 * встає — перший flush переактивує, HW.41). */
static inline void Sim7070_Init_Run(Sim7070InitTransactFn tx, void *ctx,
                                    uint8_t *out_lte_ok, uint8_t *out_pdp_suspect)
{
    *out_lte_ok = 0u;
    *out_pdp_suspect = 0u;
    for (size_t i = 0; i < SIM7070_INIT_STEPS; i++) {
        const Sim7070InitStep *step = &kSim7070Init[i];
        if (!Sim7070_Init_Step_Enabled(step, QUEEN_APN)) continue;
        AtTxResult r = tx(ctx, step->cmd);
        if (step->role == SIM7070_INIT_LTE_MODE) *out_lte_ok = (uint8_t)(r == AT_TX_OK);
    }
    if (*out_lte_ok) {
        *out_pdp_suspect = (uint8_t)(tx(ctx, SIM7070_CMD_PDP_ACTIVATE) != AT_TX_OK);
    }
}

#endif /* SILKEN_SIM7070_INIT_H */
