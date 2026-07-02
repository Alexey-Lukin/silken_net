/*
 * radio.h — [FW.46] API-дзеркало Semtech radio-інтерфейсу (SubGHz_Phy
 * middleware) для HAL compile-lane. НЕ драйвер: справжній radio.h + radio.c
 * приїдуть із STM32CubeWL Middlewares на HAL-фазі (👤 CubeMX export) і
 * замінять цей файл. Сигнатури — дослівно Semtech RadioEvents_t/Radio_s
 * (та сама ABI-фіксація, що тримає OnRxDone non-const — див. коментарі
 * у main.c обох прошивок).
 *
 * ⚠️ Латентний баг для HAL-фази (зафіксовано в 00_07 FW.46): обидва main.c
 * кличуть Radio.Init(NULL), але Queen ЖИВЕ з OnRxDone — реальний Semtech
 * driver кличе колбеки ЧЕРЕЗ events-таблицю, з NULL OnRxDone не стрельне
 * ніколи. Реєстрацію RadioEvents_t треба додати при інтеграції middleware.
 * [ARCH.26 L3] CadDone ділить ту саму долю: OnCadDone Солдата інертний до
 * реєстрації events-таблиці.
 */
#ifndef SILKEN_RADIO_H
#define SILKEN_RADIO_H

#include <stdint.h>
#include <stdbool.h>

typedef enum {
    MODEM_FSK = 0,
    MODEM_LORA = 1,
} RadioModems_t;

typedef struct {
    void (*TxDone)(void);
    void (*TxTimeout)(void);
    void (*RxDone)(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr);
    void (*RxTimeout)(void);
    void (*RxError)(void);
    /* [ARCH.26 L3] вердикт CAD-нюху (SUBGHZ_IT_CAD_DONE/_ACTIVITY_DETECTED). */
    void (*CadDone)(bool channelActivityDetected);
} RadioEvents_t;

/* Поверхня, якою користуються soldier/queen (повний Radio_s — у middleware). */
struct Radio_s {
    void (*Init)(RadioEvents_t *events);
    void (*SetChannel)(uint32_t freq);
    void (*Send)(uint8_t *buffer, uint8_t size);
    void (*Rx)(uint32_t timeout);
    void (*Sleep)(void);
    /* [ARCH.26 L3] preambleLen — важіль PANIC extended-preamble (03_01 §1.9). */
    void (*SetTxConfig)(RadioModems_t modem, int8_t power, uint32_t fdev,
                        uint32_t bandwidth, uint32_t datarate, uint8_t coderate,
                        uint16_t preambleLen, bool fixLen, bool crcOn,
                        bool freqHopOn, uint8_t hopPeriod, bool iqInverted,
                        uint32_t timeout);
    void (*StartCad)(void);
};

extern const struct Radio_s Radio;

#endif /* SILKEN_RADIO_H */
