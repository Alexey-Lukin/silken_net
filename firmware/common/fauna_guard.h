// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * fauna_guard.h — [FW.42] Vcap-гейт fauna-сесії (One-Home: Soldier-глю та
 * host-тести компілюють цей самий предикат — без копій).
 *
 * Один fauna-сеанс (5 с моноліт, 156 вікон MFCC+INT8) коштує ~78 мДж
 * імпульсом ~40 мВт, що просаджує EDLC; старт біля VBAT_OK ON (~3.4 В) кинув
 * би шину нижче порогу buck'а посеред інференсу → reset. Тож сесія лише при
 * V_cap ≥ FAUNA_VCAP_MIN_MV (запас ~1.1 В), інакше — пропуск і лічильник
 * `fauna_skipped_low_vcap` (канон 03_03 §10.3).
 *
 * ⚠️ [ARCH.99] СТЕЛЯ задуму: виклик годує `vcap_voltage` = мВ VDDA (FW.50),
 * стеля VREFINT-тракту < 4500, тож гейт fail-CLOSED ЗА ПОБУДОВОЮ — fauna
 * спить до живого Vcap-каналу з дільником (повний EDLC 5500 > поріг).
 * Розгейт — залізом, не зниженням порогу.
 *
 * ⛔ Не копіюй предикат чи поріг у тест: копія з власною константою лишає
 * сюїту зеленою при зміні порогу чи оператора в прошивці (firmware-гоча #19).
 */

#ifndef SILKEN_FAUNA_GUARD_H
#define SILKEN_FAUNA_GUARD_H

#include <stdint.h>

/* Мін. V_cap для безпечного fauna-сеансу, мВ (03_03 §10.3). */
#define FAUNA_VCAP_MIN_MV 4500u

/*
 * 1 = сеанс дозволено. 0 = пропуск: `*skipped_low_vcap` зростає й сатурується
 * на 255 (метрика кумулятивна, дозволені виклики її не зменшують).
 */
static inline uint8_t Fauna_Should_Sample(uint16_t vcap_mv, uint8_t *skipped_low_vcap)
{
    if (vcap_mv >= FAUNA_VCAP_MIN_MV) return 1;
    if (*skipped_low_vcap < 255u) (*skipped_low_vcap)++;
    return 0;
}

#endif /* SILKEN_FAUNA_GUARD_H */
