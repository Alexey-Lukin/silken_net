/*
 * cad_sniff.h — [ARCH.26 L3] CAD-нюх Провідника + PANIC extended-preamble
 * (One-Home: Soldier-глю та host-тести компілюють цей самий код — без копій).
 *
 * Третя сходинка драбини Рандеву (03_01 §1.9): Провідник (ARCH.27,
 * надлишок енергії) періодично «нюхає» ефір SX126x CAD-ом (мс-burst
 * замість повного RX); PANIC-відправник подовжує LoRa-преамбулу довше за
 * період нюху — гарантія зловлення T_pre > T_sniff, асинхронне
 * пробудження кластера поза 150-200 м зоною Королеви (L1).
 *
 * Енерго-double-bind (канон 02_03 §9.10): нюх частіше за ~хвилини не
 * тягне EBFC-харвест, а преамбула довша за ~10 с спалює EDLC відправника
 * — на чистому EBFC несумісно. Тому нюх = привілей surplus-Провідника
 * (роль-гейт тут), а EBFC-відправник мінімізує СВІЙ бік: baseline-пара
 * T_sniff 3 с ↔ T_pre 4 с (≈0.6 Дж ≈ 23% EDLC — «останній зойк»)
 * за дворівневим Vcap-гейтом (FW.42-патерн). Обидві константи
 * bench-tunable (PPK2, 00_07 ARCH.26); host-тест №10 тримає нерівність
 * гарантії — розсинхрон пари не пройде повз сюїту.
 */

#ifndef SILKEN_CAD_SNIFF_H
#define SILKEN_CAD_SNIFF_H

#include <stdint.h>
#include "wall_time.h"

/* Дефолтна LoRaWAN-преамбула (03_05) — ціль ОБОВ'ЯЗКОВОГО відновлення
 * після PANIC-TX (липка довга преамбула на звичайних TX мовчки палить
 * airtime/бюджет — дисципліна Restore_ECB_Mode). */
#define CAD_PREAMBLE_DEFAULT_SYMBOLS   8u
/* Стеля 16-бітного preamble-регістра SX126x. */
#define CAD_PREAMBLE_MAX_SYMBOLS       65535u
/* Період нюху Провідника, сек (лише surplus-джерело — EBFC не тягне,
 * 02_03 §9.10). 0 = нюхати щопробудження (діагностичний режим). */
#define CAD_SNIFF_PERIOD_S_DEFAULT     3u
/* Цільова тривалість PANIC-преамбули: період нюху + запас на CAD-цикл
 * і фазову похибку. */
#define CAD_PANIC_PREAMBLE_MS          4000u
/* T_sym @ SF9/BW125 = 2^9/125 кГц = 4096 мкс (SF9-basis — 02_03 §9.8). */
#define CAD_T_SYM_SF9_BW125_US         4096u
/* Vcap-поріг повної преамбули — дзеркало FAUNA_VCAP_MIN_MV: вище стелі
 * VREFINT-тракту (~3300 мВ), тож до живого Vcap-каналу (FW.50)
 * extended-half чесно fail-closed. */
#define CAD_PANIC_PREAMBLE_VCAP_MIN_MV 4500u

/*
 * Чи час Провіднику нюхнути ефір. Роль-гейт першим (рядовий Солдат =
 * TX-only, інваріант 03_01 §1.9); last==0 → due (cold-start / SRAM-wipe
 * у STOP2 — маркер RAM-only, як TDMA-кеш L2); зсув wall-годинника назад
 * (маяк відкотив календар) → elapsed 0 → not due (guard wall_time.h).
 */
static inline uint8_t Cad_Sniff_Due(uint8_t is_provisioner, uint32_t wall_now,
                                    uint32_t last_sniff_wall, uint32_t period_s)
{
    if (!is_provisioner)       return 0u;
    if (last_sniff_wall == 0u) return 1u;
    return (uint8_t)(Silken_Wall_Elapsed_Seconds(wall_now, last_sniff_wall) >= period_s);
}

/*
 * Мінімальне число преамбула-символів, щоб airtime покрив t_ms:
 * T_air(n) = (n + 4.25)·T_sym (LoRa PHY, 03_05). Фіксована крапка у
 * чверть-символах (4.25 = 17 чвертей), ceil обабіч — жодного float у
 * hot-path. Кламп [8, 65535]; t_sym_us==0 → дефолт (захист ділення).
 */
static inline uint16_t Cad_Preamble_Symbols_For_Ms(uint32_t t_ms, uint32_t t_sym_us)
{
    if (t_sym_us == 0u) return CAD_PREAMBLE_DEFAULT_SYMBOLS;

    uint64_t quarters = (((uint64_t)t_ms * 4000u) + t_sym_us - 1u) / t_sym_us;
    if (quarters <= 17u) return CAD_PREAMBLE_DEFAULT_SYMBOLS;

    uint64_t n = (quarters - 17u + 3u) / 4u;
    if (n < CAD_PREAMBLE_DEFAULT_SYMBOLS) return CAD_PREAMBLE_DEFAULT_SYMBOLS;
    if (n > CAD_PREAMBLE_MAX_SYMBOLS)     return (uint16_t)CAD_PREAMBLE_MAX_SYMBOLS;
    return (uint16_t)n;
}

/*
 * Дворівневий Vcap-гейт PANIC-преамбули (FW.42-патерн): вистачає заряду →
 * повний «останній зойк» extended_symbols; нижче порога → дефолтні 8
 * (brownout ПОСЕРЕД преамбули = не вилетіло НІЧОГО — коротший зойк, який
 * зловить хоча б always-on Королева, чесніший за німу смерть).
 */
static inline uint16_t Cad_Panic_Preamble_Symbols(uint16_t vcap_mv, uint16_t vcap_min_mv,
                                                  uint16_t extended_symbols)
{
    if (vcap_mv < vcap_min_mv) return CAD_PREAMBLE_DEFAULT_SYMBOLS;
    return extended_symbols;
}

/*
 * CadDone → дія: відкривати повне RX-вухо лише при детектованій
 * активності (порожній нюх = назад у сон). Тривіальне тіло навмисно —
 * host-testable seam семантики (дзеркало OnRxDone→lora_rx_flag).
 */
static inline uint8_t Cad_Should_Open_Rx(uint8_t channel_activity_detected)
{
    return (uint8_t)(channel_activity_detected != 0u);
}

#endif /* SILKEN_CAD_SNIFF_H */
