// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * standby_wake.h — [FW.54] сон Солдата в цільовому Standby (⚖️ founder 2026-10-05; 03_01 §1.10):
 *   (1) рішення «пробудження зі Standby ⊥ холодний старт»;
 *   (2) ПОРЯДОК входу в Standby — через ops-шов (host = журнал викликів, MCU = WL-HAL у main.c).
 *
 * Pure, без HAL. Навіщо окремо: у Standby VCORE вимкнено й пробудження йде через reset, тож main()
 * стартує з початку, і «прокинувся за розкладом» від «увімкнули живлення / натиснули reset»
 * відрізняє лише прапорець C1SBF у PWR_EXTSCR (CPU1 Standby flag; знімається записом C1CSSF —
 * у WL-HAL це `__HAL_PWR_GET_FLAG(PWR_FLAG_SB)` / `__HAL_PWR_CLEAR_FLAG(PWR_FLAG_SB)`).
 *
 * (1) Standby визнається лише тоді, коли C1SBF виставлено І маркер пробудження в RTC backup-домені
 *     цілий (SILKEN_STANDBY_WAKE_MAGIC; регістр — рядок мапи 03_01 §2). Маркер ОДНОРАЗОВИЙ: main()
 *     гасить його одразу після читання, тож при пробудженні він означає «цей сон почався з
 *     Silken_Standby_Enter після запису стану в цьому втіленні». Понад C1SBF він ловить: вхід у Standby
 *     повз Silken_Standby_Enter (стану ніхто не писав) · бітфліп у домені · на стенді — скид backup-
 *     домену, коли HAL міняє джерело годинника RTC при ініціалізації (уже ПІСЛЯ зняття C1SBF; шапка
 *     hal_glue/boards/lora_e5/soldier_lora_e5.c). TAMP не конфігурується, тож tamper-стирання — не
 *     сценарій. Будь-яка розбіжність — холодний старт: помилка в протилежний бік (холодний старт,
 *     прочитаний як пробудження, відновив би сміття) дорожча за зайвий холодний старт — звідси AND.
 *     ⚠️ [FW.66 (Б) · S5] Доти маркером був DR19 стану Лоренца — а його пишуть лише за валідного стану
 *     (не до першого маяка, не без K_seed), тож кожне пробудження до першого маяка читалось холодним
 *     стартом, а CCM-збірка, що Лоренца не тримає, не мала б маркера зовсім. Тепер маркер власний і
 *     пишеться кроком 1 нижче — на кожному вході через Silken_Standby_Enter (кінець циклу й рятувальний
 *     шлях PVD; що інших входів у main.c немає, стереже awk-пін `make -C firmware/test standby_wake`).
 *     ⚠️ Стеля: читача в рішення ще немає — `soldier_woke_from_standby` споживе відновлення живого
 *     набору з RTC (03_01 §2.3.2), коли сторожі синку перейдуть на wall-мітки,
 *     а доти кожен блок DR відновлюється за власним гардом, і маркер поведінки не змінює.
 *
 * (2) Порядок — кожен крок має причину:
 *       1. write_wake_marker()       маркер пробудження — ПІСЛЯ запису стану в DR (його роблять до цього
 *                                    виклику), тож маркер свідчить, що вхід пройшов цей шов. Чи ВЕСЬ
 *                                    стан записано, він не каже: рятувальний шлях PVD може перервати
 *                                    запис Фази 5 посередині й поставити маркер на частково новий домен;
 *       2. set_load_pulls()          pull-и PWR на ключі навантажень: у Standby GPIO рівня не тримають;
 *       3. enable_pull_config()      APC = 1 — ПІСЛЯ кроку 2, інакше застосується порожня конфігурація;
 *       4. disable_sram_retention()  RRS = 0: ціль ≈ 300 нА — без утримання SRAM2 (⚖️ 2026-10-05);
 *       5. clear_wakeup_flags()      виставлений WUF не дав би заснути — одразу reset;
 *       6. enter_standby()           на кремнії не повертається; на хості журнал лише фіксує виклик.
 *     Запис стану в DR / Flash-KV — ДО цього виклику (групи A і C, 03_01 §2.3.1), і тут його немає
 *     свідомо: що саме мусить пережити Standby — 03_01 §2.3.2 (живий набір) і §2.3.1 (OTA-буфер).
 *
 * Стеля: гейт `FW54_STANDBY_ENABLED` у main.c стоїть у 0, доки живий набір не живе в RTC (без нього
 * Standby обнуляв би RAM-only лічильники пробуджень щопробудження), не задано пін-мапу ключів (.ioc,
 * FW.46) і не зміряно сон на стенді (00_07 FW.54). Канон: 03_01 §1.10 · 02_03 §9.8.
 */
#ifndef SILKEN_STANDBY_WAKE_H
#define SILKEN_STANDBY_WAKE_H

#include <stdint.h>

/* Маркер пробудження — цілий 32-бітний, бо нуль і 0xFFFFFFFF дає порожній чи битий домен. "SBWK". */
#define SILKEN_STANDBY_WAKE_MAGIC 0x5342574BUL

/* 1 — це пробудження зі Standby (продовження роботи вузла), 0 — холодний старт. `marker_word` —
 * сире слово регістра маркера: порівняння живе тут, а не у викликача, щоб host-тест судив його. */
static inline uint8_t Silken_Wake_From_Standby(uint8_t c1sbf_set, uint32_t marker_word)
{
    return (uint8_t)((c1sbf_set != 0u) && (marker_word == SILKEN_STANDBY_WAKE_MAGIC));
}

typedef struct {
    void (*write_wake_marker)(void);
    void (*set_load_pulls)(void);
    void (*enable_pull_config)(void);
    void (*disable_sram_retention)(void);
    void (*clear_wakeup_flags)(void);
    void (*enter_standby)(void);
} SilkenStandbyOps;

static inline void Silken_Standby_Enter(const SilkenStandbyOps *ops)
{
    ops->write_wake_marker();
    ops->set_load_pulls();
    ops->enable_pull_config();
    ops->disable_sram_retention();
    ops->clear_wakeup_flags();
    ops->enter_standby();
}

#endif /* SILKEN_STANDBY_WAKE_H */
