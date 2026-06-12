/*
 * fc_hiwater.h — [FW.2 TRL-7] монотонна "верхня межа" Frame Counter
 *                у Flash-KV: безумовна унікальність nonce через cold-boot.
 *
 * Навіщо: RTC DR15 тримає FC лише поки живе VBAT. Повна смерть живлення
 * (сезонний drain EDLC) стирала магію DR15 → HRNG-reseed з імовірнісною
 * унікальністю (~N/2²⁴, MEDIUM — канон 03_05 §2.1). Цей модуль додає
 * Flash-якір, що переживає будь-яку смерть: у KV-ключі 0x14 лежить межа,
 * яку ЖОДЕН переданий FC ще не перетнув (LoRaWAN NVM-патерн).
 *
 * Інваріант I-HW: кожен FC, що пішов у ефір, СТРОГО МЕНШИЙ за значення
 * 0x14 у Flash на момент TX. Тоді рестарт з межі (floor) математично
 * не може повторити nonce — без жодної ентропії.
 *
 * Дисципліна підтримки інваріанта (споживач — soldier/main.c):
 *   • КЕНОЗИС (безпечна фаза, після TX): якщо fc підійшов до межі ближче
 *     ніж на MARGIN — просунути межу на STRIDE уперед (один dw-program,
 *     erase відкладений у спільний FlashKv_Compact).
 *   • Cold-boot: floor застосовується ЛИШЕ якщо нову межу вдалося ОДРАЗУ
 *     записати у Flash (атомарність floor+advance) — інакше негайний
 *     повторний brownout стартував би з того самого floor і повторив
 *     nonce. Відмова запису → чесний відкат на HRNG-reseed (стара
 *     політика, не гірше за неї).
 *   • Перетин межі без запису (Flash стабільно мертвий) — TX дозволений
 *     (телеметрія дорожча за теоретичний replay), але викликач палить
 *     діагностичний degraded-прапорець.
 *
 * Край простору: 24-bit FC одноразовий за конструкцією — біля 0xFFFFFF
 * межа клемпиться і unique-гарантію далі дає лише ротація ключа (FW.17
 * відкриває нову nonce-епоху). За TX-бюджету життя (~219 тис.) цей край
 * недосяжний — документована межа дизайну, не робочий режим.
 *
 * One-Home: wire/DR15-пакування FC — lora_ccm.h; журнальний Flash —
 * flash_kv.h; тут ЛИШЕ high-water політика. Канон: 03_05 §2.1 (FC/nonce,
 * 📐 ЄДИНЕ ДЖЕРЕЛО) + 03_01 §2.3.1 (реєстр KV-ключів) + 00_07 FW.2.
 */
#ifndef SILKEN_FC_HIWATER_H
#define SILKEN_FC_HIWATER_H

#include <stdint.h>
#include "flash_kv.h"
#include "lora_ccm.h"

/* Реєстр KV-ключів — 03_01 §2.3.1 (0x13 = FW17_KEYVER, 0x20… = S2_BITMAP). */
#define FW2_FC_KV_KEY_HIWATER   0x14u

/* Крок межі: записів між Flash-оновленнями. 219k TX / 256 ≈ 856 dw за
 * життя — мізер проти wear-бюджету журналу (03_01 §2.3). */
#define FW2_FC_HIWATER_STRIDE   256u

/* Запас наближення: скільки TX може статись між двома КЕНОЗИСАМИ
 * (телеметрія + panic-черга) — з горою. */
#define FW2_FC_HIWATER_MARGIN   8u

/* Прочитати межу з Flash. 0 = ключа нема або сміття (floor відсутній —
 * викликач іде HRNG-шляхом). Валідне значення ∈ (0 .. FW2_FC_VALUE_MASK]. */
static inline uint32_t Fc_Hiwater_Load(const FlashKv *kv)
{
    uint32_t v = 0;
    if (!FlashKv_Get32(kv, FW2_FC_KV_KEY_HIWATER, &v)) return 0;
    if (v == 0 || v > FW2_FC_VALUE_MASK) return 0;
    return v;
}

/* Наступна межа від поточного fc. Клемп на стелі 24-bit простору —
 * далі epoch-край (див. шапку). */
static inline uint32_t Fc_Hiwater_Target(uint32_t fc)
{
    uint32_t t = fc + FW2_FC_HIWATER_STRIDE;
    if (t > FW2_FC_VALUE_MASK) t = FW2_FC_VALUE_MASK;
    return t;
}

/* 1 = час просувати межу: наступний TX підбирається до неї ближче ніж
 * на MARGIN (hiwater==0 — ключа ще нема, перший запис теж "час"). */
static inline int Fc_Hiwater_Should_Advance(uint32_t hiwater, uint32_t next_fc)
{
    return (next_fc + FW2_FC_HIWATER_MARGIN) >= hiwater;
}

/* Просунути межу у Flash до target. Успіх → оновлює кеш викликача (1);
 * відмова program / kv → кеш недоторканий (0). Ідемпотентний біля стелі:
 * межа вже стоїть на target → успіх без зайвого wear. */
static inline int Fc_Hiwater_Advance(FlashKv *kv, uint32_t target,
                                     uint32_t *hiwater_io)
{
    if (target == *hiwater_io) return 1;
    if (!FlashKv_Put32(kv, FW2_FC_KV_KEY_HIWATER, target)) return 0;
    *hiwater_io = target;
    return 1;
}

#endif /* SILKEN_FC_HIWATER_H */
