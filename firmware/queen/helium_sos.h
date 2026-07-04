#ifndef SILKEN_QUEEN_HELIUM_SOS_H
#define SILKEN_QUEEN_HELIUM_SOS_H

#include <stdint.h>

/*
 * helium_sos.h — [ARCH.34 L3] SOS-маяк Королеви: коли ВСІ власні uplink'и
 * мертві, Королева кричить один 12-байтний кадр через чужі Helium-hotspot'и
 * (LoRaWAN), а телеметрія Солдатів чекає у Flash-ринзі (ARCH.35).
 *
 * Тут живе pure-половина (host-тестована): wire-пакування, тригер-предикат,
 * бюджет radio-сліпоти, DID-парсер. Сам LoRaWAN MAC (OTAA join, FCntUp,
 * канальний hop) — vendored LoRaMac-node за Helium_Mac_SendSos(); його NVM
 * (FCntUp persist) поїде через flash_kv Королеви на bench-фазі.
 *
 * SOS-wire 12 Б (📐 One-Home — 06_08 §1.2; приймач HeliumSosWorker#decode_sos,
 * unpack "N n C C3 C" — big-endian, суворо ≥12):
 *   [queen_did:4 BE][vcap_mv:2 BE][error_code:1][uptime_min:u24 BE][flags:1][rsv:1]
 *
 * Тригер (02_05 §6.1): uplink мертвий ≥30 хв + Q2Q недоступний + буфер ≥50%.
 * Ретрансміт — не частіше того ж порогу: SOS і так ідемпотентний на бекенді,
 * а EU868 duty-cycle і Helium DC не люблять базікання.
 */

#define HELIUM_SOS_WIRE_LEN            12u

/* Пороги активації — числа канону 02_05 §6.1 (не міняй без каноном). */
#define HELIUM_FALLBACK_THRESHOLD_MIN  30u    /* хв без підтвердженого uplink */
#define HELIUM_SOS_REPEAT_MIN          30u    /* мін. пауза між SOS-кадрами   */
#define HELIUM_BUFFER_FILL_MIN_PCT     50u    /* заповнення CIFO/ринга        */
#define HELIUM_BLIND_WINDOW_MAX_MS     20000u /* стеля radio-сліпоти < IWDG   */

/* error_code — дзеркало HeliumSosWorker::ERROR_CODES (бекенд-SSOT). */
#define HELIUM_ERR_STARLINK_DOWN       1u
#define HELIUM_ERR_LTE_DOWN            2u
#define HELIUM_ERR_Q2Q_UNREACHABLE     3u
#define HELIUM_ERR_BUFFER_PRESSURE     4u

/* Пакує SOS-кадр. uptime_min сатурується у u24 (28+ років — чесна стеля). */
static inline void Helium_Sos_Pack(uint8_t out[HELIUM_SOS_WIRE_LEN],
                                   uint32_t queen_did, uint16_t vcap_mv,
                                   uint8_t error_code, uint32_t uptime_min,
                                   uint8_t flags)
{
    if (uptime_min > 0xFFFFFFu) uptime_min = 0xFFFFFFu;
    out[0]  = (uint8_t)(queen_did >> 24);
    out[1]  = (uint8_t)(queen_did >> 16);
    out[2]  = (uint8_t)(queen_did >> 8);
    out[3]  = (uint8_t)(queen_did);
    out[4]  = (uint8_t)(vcap_mv >> 8);
    out[5]  = (uint8_t)(vcap_mv);
    out[6]  = error_code;
    out[7]  = (uint8_t)(uptime_min >> 16);
    out[8]  = (uint8_t)(uptime_min >> 8);
    out[9]  = (uint8_t)(uptime_min);
    out[10] = flags;
    out[11] = 0u; /* rsv — майбутні розширення хвостом */
}

/* Тригер канону: всі три умови РАЗОМ + пауза ретрансміту. */
static inline int Helium_Sos_Should_Fire(uint32_t min_since_uplink_ok,
                                         uint32_t min_since_last_sos,
                                         uint8_t buffer_fill_pct,
                                         int q2q_unavailable)
{
    return min_since_uplink_ok >= HELIUM_FALLBACK_THRESHOLD_MIN
        && q2q_unavailable
        && buffer_fill_pct >= HELIUM_BUFFER_FILL_MIN_PCT
        && min_since_last_sos >= HELIUM_SOS_REPEAT_MIN;
}

/* Причина SOS: буфер уже тисне → buffer_pressure; інакше — впав єдиний
 * transitional-uplink (SIM7070G LTE-M). Starlink/Q2Q-коди чекають на своє
 * залізо (02_05 Phase 2). */
static inline uint8_t Helium_Sos_Error_Code(uint8_t buffer_fill_pct)
{
    return (buffer_fill_pct >= HELIUM_BUFFER_FILL_MIN_PCT)
        ? HELIUM_ERR_BUFFER_PRESSURE
        : HELIUM_ERR_LTE_DOWN;
}

/* 1 = сесія вклалась у бюджет сліпоти. Wrap-safe: беззнакова різниця тіків
 * коректна і через переповнення HAL_GetTick (49.7 діб). */
static inline int Helium_Blind_Budget_Ok(uint32_t session_start_tick,
                                         uint32_t now_tick)
{
    return (uint32_t)(now_tick - session_start_tick) < HELIUM_BLIND_WINDOW_MAX_MS;
}

/* DID з uid-рядка Королеви: 8 hex після останнього '-' ("SNET-Q-%08X").
 * 0 = не розпарсилось (UNPROV-сміття, короткий хвіст) — SOS з did=0 бекенд
 * все одно дропне cross-check'ом, тож викликач мусить скіпнути постріл. */
static inline uint32_t Helium_Did_From_Uid(const char *uid)
{
    const char *tail = 0;
    const char *p;
    uint32_t did = 0u;
    int i;

    if (!uid) return 0u;
    for (p = uid; *p; p++) {
        if (*p == '-') tail = p + 1;
    }
    if (!tail) return 0u;

    for (i = 0; i < 8; i++) {
        char c = tail[i];
        uint32_t nib;
        if (c >= '0' && c <= '9')      nib = (uint32_t)(c - '0');
        else if (c >= 'A' && c <= 'F') nib = (uint32_t)(c - 'A') + 10u;
        else if (c >= 'a' && c <= 'f') nib = (uint32_t)(c - 'a') + 10u;
        else return 0u;
        did = (did << 4) | nib;
    }
    if (tail[8] != '\0') return 0u; /* хвіст довший за %08X — не наш формат */
    return did;
}

/* MAC-шов [ARCH.34]: OTAA join + один unconfirmed uplink 12 Б, дедлайн =
 * бюджет сліпоти. Імплементація = adapter-TU поверх vendored LoRaMac-node
 * (з'являється разом із submodule на bench-фазі); прототип живе тут, щоб
 * gated-виклик у main.c завжди бачив компілятор. 1 = кадр пішов у ефір. */
int Helium_Mac_SendSos(const uint8_t sos_frame[HELIUM_SOS_WIRE_LEN],
                       uint32_t deadline_ms);

#endif /* SILKEN_QUEEN_HELIUM_SOS_H */
