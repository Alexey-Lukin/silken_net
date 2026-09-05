// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * lorenz_thresholds.h — [FW.8] persist пер-деревних Z-порогів у Flash-KV.
 *
 * Host-половина deferred-TRL-7 залишку FW.8: парсер CMD_SET_THRESHOLDS
 * (0x9A, soldier/main.c) приймає пороги лише в RAM — VBAT-loss повертає
 * firmware-дефолти до наступного daily re-send. Цей модуль кладе прийняту
 * конфігурацію у Flash-KV (ARCH.28 шлях A) і відновлює її на boot.
 *
 * Ключі — за реєстром 03_01 §2.3.1 (FW8_ZCFG, gated):
 *   0x10: [z_max_x100:u16 << 16 | z_min_x100:u16]
 *   0x11: [config_version:u8 << 24 | species_id:u8 << 16 | z_opt_x100:u16]
 *
 * Атомарність: кожен Put32 — ECC-атомарний dw, але ПАРА — ні. Power-cut
 * між ключами може лишити z-пару нового покоління з метою старого; Load
 * жене комбінацію через ті самі інваріанти, що й парсер (невалідна →
 * дефолти), а валідний «мікс» — короткоживучий: наступний daily re-send
 * перезапише обидва ключі. Свідомий trade-off замість 2-фазного журналу.
 *
 * Інваріанти Valid() дзеркалять Soldier_Handle_CMD_SET_THRESHOLDS
 * (main.c) і Test_Handle_CMD_SET_THRESHOLDS (test_soldier_logic.c) —
 * парність пінується host-тестом test_fw8_valid_agrees_with_parser.
 *
 * Залишок FW.8 після цього: фліп FW8_PARSER_ENABLED 1 + mount KV у main.c
 * (KENOSIS-фаза) + HAL_FLASH глю — bench.
 *
 * 🔴 МЕЖА, без якої шапка вище вводить в оману: доставлені пороги СЬОГОДНІ
 * НІ НА ЩО НЕ ВПЛИВАЮТЬ. Вердикт `bio_status` рахує mruby `bio_contract.rb`
 * за ЗАШИТИМИ `BioContract::CRITICAL_Z_MIN/MAX` — `calculate_state` порогів
 * не приймає в сигнатурі, а C-глобалки `lorenz_z_*_x100` є write-only
 * round-trip Flash→RAM→Flash: жодна гілка рішення їх не читає. Тобто цей
 * модуль персистить конфігурацію, у якої немає СПОЖИВАЧА, і «до наступного
 * daily re-send» описує лише збереження значення, не його дію.
 * ⛔ Отже фліп FW8_PARSER_ENABLED сам собою per-species НЕ вмикає — потрібне
 * ще й читання порогів самим контрактом. Наслідок для бекенду (DCI судить за
 * смугою пристрою, а не за бажаною) — `03_04 §5.3`.
 *
 * Канон: 03_01 §2.3.1 + 05_02 §4а + 00_07 FW.8.
 */
#ifndef SILKEN_LORENZ_THRESHOLDS_H
#define SILKEN_LORENZ_THRESHOLDS_H

#include <stdint.h>

#include "flash_kv.h"

#define FW8_KV_KEY_ZPAIR 0x10u /* [z_max:16 | z_min:16] */
#define FW8_KV_KEY_META  0x11u /* [ver:8 | species:8 | z_opt:16] */

/* Дефолти — ті самі значення, що LORENZ_DEFAULT_* у soldier/main.c
 * (числовий дім — 03_04 §4.1: 2.00 / 45.00 / 29.00). */
#define FW8_DEFAULT_Z_MIN_X100 200
#define FW8_DEFAULT_Z_MAX_X100 4500
#define FW8_DEFAULT_Z_OPT_X100 2900
#define FW8_DEFAULT_SPECIES_ID 0xFFu /* unmapped */
#define FW8_DEFAULT_CONFIG_VER 0u    /* 0 = firmware-baked defaults */

typedef struct {
    int16_t z_min_x100;
    int16_t z_max_x100;
    int16_t z_opt_x100;
    uint8_t species_id;
    uint8_t config_version;
} LorenzThresholds;

static inline void Lorenz_Thresholds_Defaults(LorenzThresholds *t)
{
    t->z_min_x100     = FW8_DEFAULT_Z_MIN_X100;
    t->z_max_x100     = FW8_DEFAULT_Z_MAX_X100;
    t->z_opt_x100     = FW8_DEFAULT_Z_OPT_X100;
    t->species_id     = FW8_DEFAULT_SPECIES_ID;
    t->config_version = FW8_DEFAULT_CONFIG_VER;
}

/* Ті самі інваріанти, що в парсері 0x9A: зона не колапсує, оптимум
 * усередині, значення у правдоподібному діапазоні Z (±100.00). */
static inline int Lorenz_Thresholds_Valid(const LorenzThresholds *t)
{
    if (!(t->z_min_x100 < t->z_max_x100))                          return 0;
    if (t->z_opt_x100 < t->z_min_x100 || t->z_opt_x100 > t->z_max_x100) return 0;
    if (t->z_min_x100 < -10000 || t->z_max_x100 > 10000)           return 0;
    return 1;
}

/* Зберегти прийняту конфігурацію. 1 = обидва ключі записано. Невалідну
 * не пишемо взагалі — Flash-KV не сміє тримати те, що Load відкине. */
static inline int Lorenz_Thresholds_Save(FlashKv *kv, const LorenzThresholds *t)
{
    if (!Lorenz_Thresholds_Valid(t)) return 0;

    uint32_t zpair = (uint32_t)(uint16_t)t->z_min_x100 |
                     ((uint32_t)(uint16_t)t->z_max_x100 << 16);
    uint32_t meta  = (uint32_t)(uint16_t)t->z_opt_x100 |
                     ((uint32_t)t->species_id << 16) |
                     ((uint32_t)t->config_version << 24);

    if (!FlashKv_Put32(kv, FW8_KV_KEY_ZPAIR, zpair)) return 0;
    return FlashKv_Put32(kv, FW8_KV_KEY_META, meta);
}

/* Boot-restore. 1 = відновлено збережену конфігурацію; 0 = у Flash нічого
 * валідного (порожньо / порвана пара / сміття) → t = дефолти. */
static inline int Lorenz_Thresholds_Load(const FlashKv *kv, LorenzThresholds *t)
{
    uint32_t zpair = 0, meta = 0;

    if (FlashKv_Get32(kv, FW8_KV_KEY_ZPAIR, &zpair) &&
        FlashKv_Get32(kv, FW8_KV_KEY_META, &meta)) {
        t->z_min_x100     = (int16_t)(uint16_t)(zpair & 0xFFFFu);
        t->z_max_x100     = (int16_t)(uint16_t)(zpair >> 16);
        t->z_opt_x100     = (int16_t)(uint16_t)(meta & 0xFFFFu);
        t->species_id     = (uint8_t)(meta >> 16);
        t->config_version = (uint8_t)(meta >> 24);
        if (Lorenz_Thresholds_Valid(t)) return 1;
    }

    Lorenz_Thresholds_Defaults(t);
    return 0;
}

#endif /* SILKEN_LORENZ_THRESHOLDS_H */
