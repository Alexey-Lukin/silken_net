/*
 * rx_route.h — [FW.2] Маршрутизація вхідних LoRa-кадрів Королеви +
 *              29-байтний CoAP-запис CCM-телеметрії (wire-rev2).
 *
 * Інверсія довіри wire-rev2 (2026-07-03): per-device CCM-ключі несумісні
 * з decrypt-на-Королеві (03_05 §3.1 — вона не тримає чужих ключів), тож
 * hot path НЕ розшифровує 28B-кадри. Демукс = cleartext DID з AAD;
 * сирий хвіст кадру їде бекенду як є, MIC верифікує Rails per-DID
 * (`TelemetryUnpackerService#process_ccm_chunk`). Королева тут — сліпий
 * кур'єр: цілісність її не стосується, вона лише додає RSSI-мітку прийому.
 *
 * Запис батча (довжина ПОХІДНА: air+1; rev2.1 = 31B — контракт
 * process_ccm_chunk; канон 03_05 §2.1 cross-ref):
 *   [0..3]       DID (= air 0..3, BE)
 *   [4]          |RSSI| (Queen-injected; бекенд читає як -chunk[4])
 *   [5..air]     air 4..кінець як є: gossip(1) ‖ FC24(3) ‖
 *                ciphertext(FW2_CCM_PLAINTEXT_LEN) ‖ MIC(8)
 *
 * Pure header (без HAL) — host-тести test_queen_rx_route.c ганяють ці
 * байти напряму, без mirror-дрейфу.
 */
#ifndef QUEEN_RX_ROUTE_H
#define QUEEN_RX_ROUTE_H

#include <stdint.h>
#include <string.h>
#include "../common/lora_ccm.h"

/* [DID:4][|RSSI|:1][air-хвіст: air_len-4] — похідне від wire-контракту,
 * щоб зміна довжини кадру (rev2→rev2.1) не лишала тут статичного дрейфу. */
#define QUEEN_CCM_RECORD_LEN  (FW2_CCM_AIR_PACKET_LEN + 1u)

/* Класи вхідного ефіру. Розмір — єдиний чесний дискримінатор ДО
 * будь-якого декрипту: 16B = ECB-світ (телеметрія/control-frames — далі
 * розбирає існуючий маркер-каскад), FW2_CCM_AIR_PACKET_LEN = CCM-телеметрія
 * (blind-forward), решта = шум/чужий формат → мовчазний дроп (жодного
 * ECB-декрипту сміття — та сама контамінаційна пастка, що Soldier-RX guard). */
typedef enum {
    QUEEN_RX_CONTROL_16B = 0,  /* ECB-тракт: decrypt → маркерний каскад */
    QUEEN_RX_CCM_AIR,          /* wire-rev2.1: cleartext-DID демукс, без decrypt */
    QUEEN_RX_DROP              /* невідома довжина — не наш ефір */
} QueenRxClass;

static inline QueenRxClass Queen_Rx_Classify(uint16_t size) {
    if (size == 16u)                    return QUEEN_RX_CONTROL_16B;
    if (size == FW2_CCM_AIR_PACKET_LEN) return QUEEN_RX_CCM_AIR;
    return QUEEN_RX_DROP;
}

/* Cleartext DID з AAD (байти 0..3 BE) — демукс без ключа. DID==0 =
 * зарезервований Sentinel Королеви: 28B-кадр з нулем — спуф, викликач
 * зобов'язаний дропнути (бекенд process_ccm_chunk дропає його теж —
 * defense-in-depth, але батч-місце шкода). */
static inline uint32_t Queen_Ccm_Frame_Did(const uint8_t air[FW2_CCM_AIR_PACKET_LEN]) {
    return ((uint32_t)air[0] << 24) | ((uint32_t)air[1] << 16) |
           ((uint32_t)air[2] << 8)  | (uint32_t)air[3];
}

/* 29B-запис для CoAP-батча: DID ‖ |RSSI| ‖ air-хвіст незайманим.
 * |RSSI| — та сама конвенція, що 21B-legacy запис ((uint8_t)(-(int16_t)rssi):
 * -85 дБм → 85; int16-каст знімає UB на -128). MIC лишається над
 * оригінальними байтами — Королева їх не торкається. */
static inline void Queen_Ccm_Build_Record(const uint8_t air[FW2_CCM_AIR_PACKET_LEN],
                                          int8_t rssi,
                                          uint8_t out[QUEEN_CCM_RECORD_LEN]) {
    memcpy(&out[0], &air[0], 4);
    out[4] = (uint8_t)(-(int16_t)rssi);
    memcpy(&out[5], &air[4], FW2_CCM_AIR_PACKET_LEN - 4u);
}

/* Той самий запис, але з CIFO-слота: DID і air-хвіст (air 4..кінець)
 * зберігаються там нарізно (DID не дублюється у payload — 4B економії
 * на слот). Байт-еквівалентність обох білдерів доводить host-тест. */
static inline void Queen_Ccm_Build_Record_From_Cache(uint32_t did,
                                                     const uint8_t tail[FW2_CCM_AIR_PACKET_LEN - 4u],
                                                     int8_t rssi,
                                                     uint8_t out[QUEEN_CCM_RECORD_LEN]) {
    out[0] = (uint8_t)(did >> 24);
    out[1] = (uint8_t)(did >> 16);
    out[2] = (uint8_t)(did >> 8);
    out[3] = (uint8_t)(did);
    out[4] = (uint8_t)(-(int16_t)rssi);
    memcpy(&out[5], tail, FW2_CCM_AIR_PACKET_LEN - 4u);
}

#endif /* QUEEN_RX_ROUTE_H */
