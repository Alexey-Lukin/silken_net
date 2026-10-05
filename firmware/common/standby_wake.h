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
 * (1) Standby визнається лише тоді, коли C1SBF виставлено І маркер RTC backup-домену цілий (DR19 =
 *     LORENZ_STATE_MAGIC). Standby тримає backup-домен, тож розбіжність означає, що сон почався до
 *     першого запису маркера; читати тоді DR як продовження — означало б відновлювати сміття, тож це
 *     холодний старт. Помилка в протилежний бік (холодний старт, прочитаний як пробудження) дорожча за
 *     зайвий холодний старт — звідси AND, а не OR.
 *
 * (2) Порядок — кожен крок має причину:
 *       1. set_load_pulls()          pull-и PWR на ключі навантажень: у Standby GPIO рівня не тримають;
 *       2. enable_pull_config()      APC = 1 — ПІСЛЯ кроку 1, інакше застосується порожня конфігурація;
 *       3. disable_sram_retention()  RRS = 0: ціль ≈ 300 нА — без утримання SRAM2 (⚖️ 2026-10-05);
 *       4. clear_wakeup_flags()      виставлений WUF не дав би заснути — одразу reset;
 *       5. enter_standby()           на кремнії не повертається; на хості журнал лише фіксує виклик.
 *     Запис стану в DR / Flash-KV — ДО цього виклику (групи A і C, 03_01 §2.3.1), і тут його немає
 *     свідомо: що саме мусить пережити Standby, судить ⚖️ RAM-стану FW.54.
 *
 * Стеля: гейт `FW54_STANDBY_ENABLED` у main.c стоїть у 0, доки не розсуджено RAM-стан (без нього
 * Standby обнуляв би RAM-only лічильники пробуджень щопробудження), не задано пін-мапу ключів (.ioc,
 * FW.46) і не зміряно сон на стенді (00_07 FW.54). Канон: 03_01 §1.10 · 02_03 §9.8.
 */
#ifndef SILKEN_STANDBY_WAKE_H
#define SILKEN_STANDBY_WAKE_H

#include <stdint.h>

/* 1 — це пробудження зі Standby (продовження роботи вузла), 0 — холодний старт. */
static inline uint8_t Silken_Wake_From_Standby(uint8_t c1sbf_set, uint8_t backup_marker_ok)
{
    return (uint8_t)((c1sbf_set != 0u) && (backup_marker_ok != 0u));
}

typedef struct {
    void (*set_load_pulls)(void);
    void (*enable_pull_config)(void);
    void (*disable_sram_retention)(void);
    void (*clear_wakeup_flags)(void);
    void (*enter_standby)(void);
} SilkenStandbyOps;

static inline void Silken_Standby_Enter(const SilkenStandbyOps *ops)
{
    ops->set_load_pulls();
    ops->enable_pull_config();
    ops->disable_sram_retention();
    ops->clear_wakeup_flags();
    ops->enter_standby();
}

#endif /* SILKEN_STANDBY_WAKE_H */
