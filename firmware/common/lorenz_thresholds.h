// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * lorenz_thresholds.h — [FW.8] persist пер-деревних Z-порогів у Flash-KV.
 *
 * Host-половина залишку FW.8 (⚫ 2026-10-06 — тракт знімає реалізація (Б)): парсер CMD_SET_THRESHOLDS
 * (0x9A, soldier/main.c) кладе пороги в RAM, і без журналу VBAT-loss повертав
 * би firmware-дефолти. Цей модуль кладе прийняту конфігурацію у Flash-KV
 * (ARCH.28 шлях A) і відновлює її на boot.
 *
 * Ключі — за реєстром 03_01 §2.3.1 (FW8_ZCFG, gated):
 *   0x10: [z_max_x100:u16 << 16 | z_min_x100:u16]
 *   0x11: [config_version:u8 << 24 | species_id:u8 << 16 | z_opt_x100:u16]
 *
 * Атомарність: кожен Put32 — ECC-атомарний dw, але ПАРА — ні. Power-cut
 * між ключами може лишити z-пару нового покоління з метою старого; Load
 * жене комбінацію через ті самі інваріанти, що й парсер. Невалідна →
 * дефолти, і це видно бекенду: статус пакета там, де смуги розходяться,
 * видає заводську, і смугу видають знову новим DLFC (облік —
 * Downlink::ThresholdBand, ⚖️ 2026-09-29; щоденного re-send, на який цей
 * абзац доти спирався, бекенд не мав ніколи). Валідний «мікс» уже судить
 * НОВОЮ z-парою, тож DCI він не чіпає; стара лишається лише мета (z_opt ·
 * species · version) — до наступної видачі. Свідомий trade-off замість
 * 2-фазного журналу.
 *
 * Парсер тіла 0x9A (Lorenz_Thresholds_From_Wire) і журнал судять ОДНИМ
 * Valid() — до downlink-ревізії (2026-09-29) парсер був рукописною копією в
 * main.c і ще однією в тесті, і паритет тримав лише тест. Інваріанти пінує
 * test_fw8_valid_agrees_with_parser (test_flash_kv.c).
 *
 * Залишок FW.8 після цього — ⚫ 2026-10-06 (поглинуто гілкою (Б), 00_07 FW.66):
 * фліпу FW8_PARSER_ENABLED 1 не буде, весь цей тракт знімає реалізація (Б).
 *
 * [FW.8, 2026-09-27] Споживач є: `calculate_state` приймає `z_min`/`z_max`, і
 * C-міст передає йому глобалки `lorenz_z_*_x100` / 100.0. До того ці глобалки
 * були write-only round-trip Flash→RAM→Flash — вердикт їх не читав зовсім.
 * 🔴 Гейт один на обидві половини: глобалки міняють лише парсер 0x9A і
 * boot-restore звідси — обидва під FW8_PARSER_ENABLED, тож бойова збірка судить
 * дефолтами навіть із залишком порогів у KV, а фліп вмикає доставку й
 * споживання разом. Яку смугу має КОЖЕН пристрій, бекенд знає з доказу, а не
 * з ефіру (⚖️ 2026-09-29): DCI судить набором кандидатів — заводська плюс
 * утримувані й відкрита видача, — а статус у зоні їхньої розбіжності каже, котра
 * чинна (`03_04 §5.3`). ⚠️ Rails-гейт видачі (ENV
 * FW8_THRESHOLDS_DOWNLINK_ENABLED) не вмикати: фліпу не буде (FW.8 ⚫ 2026-10-06).
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

/* [FW.8] Смуга для mruby-контракту: x100-цілі → Float у ТОМУ Ж порядку, в якому
 * calculate_state їх приймає (8-й аргумент z_min, 9-й z_max). One-Home: міст
 * Солдата (main.c) і QEMU-паритет (firmware/sim/parity_core.h) будують аргументи
 * ЦИМ викликом, тож квантизація `/100.0` і порядок живуть в одному місці, а
 * паритет і PARITY-MEM міряють той самий 9-аргументний виклик, що й пристрій.
 * ⚠️ Стеля: переставлені аргументи НА ВИКЛИКУ в main.c жоден гейт не бачить —
 * main.c збирається лише compile-only (hal_check), і так лишається до bench-дня. */
static inline void Lorenz_Band_Args(int16_t z_min_x100, int16_t z_max_x100, double out[2])
{
    out[0] = (double)z_min_x100 / 100.0;
    out[1] = (double)z_max_x100 / 100.0;
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
/* [FW.17 · 03_05 §2.5] Тіло команди 0x9A —
 * [z_min_x100][z_max_x100][z_opt_x100]:s16le · [species_id:u8][config_version:u8] —
 * у пороги з тими самими інваріантами, що Save/Load: парсер і журнал судять
 * одним Valid, тож розійтись не можуть. 1 = валідне. */
static inline int Lorenz_Thresholds_From_Wire(const uint8_t body[8], LorenzThresholds *t)
{
    t->z_min_x100     = (int16_t)((uint16_t)body[0] | ((uint16_t)body[1] << 8));
    t->z_max_x100     = (int16_t)((uint16_t)body[2] | ((uint16_t)body[3] << 8));
    t->z_opt_x100     = (int16_t)((uint16_t)body[4] | ((uint16_t)body[5] << 8));
    t->species_id     = body[6];
    t->config_version = body[7];
    return Lorenz_Thresholds_Valid(t);
}

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
