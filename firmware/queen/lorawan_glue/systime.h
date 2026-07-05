#ifndef SILKEN_LORAWAN_SYSTIME_H
#define SILKEN_LORAWAN_SYSTIME_H

#include <stdint.h>

/*
 * systime.h — [ARCH.34] owned мінімум Semtech-systime під vendored
 * LoRaMac-node (ST-пакет тип оголошує ТУТ — LoRaMacTypes.h лише включає).
 *
 * Несуче для SOS: SysTimeGetMcuTime (EU868 duty-cycle backoff міряється
 * від нього) — поверх Soft_Timer_Now_Ms, точність = тіки. SysTimeGet/Set
 * (wall-clock) живлять лише DeviceTimeAns/ClockSync, яких SOS-маяк не
 * запитує — чесний boot-relative без претензії на UTC (Queen-wall живе
 * у queen_unix_ts, конвертація — справа adapter'а, ЯКЩО колись знадобиться).
 */

#ifdef __cplusplus
extern "C" {
#endif

#define UNIX_GPS_EPOCH_OFFSET 315964800

typedef struct SysTime_s {
    uint32_t Seconds;
    int16_t  SubSeconds; /* мс, нормалізовано 0..999 */
} SysTime_t;

SysTime_t SysTimeAdd( SysTime_t a, SysTime_t b );
SysTime_t SysTimeSub( SysTime_t a, SysTime_t b );

uint32_t  SysTimeToMs( SysTime_t t );
SysTime_t SysTimeFromMs( uint32_t ms );

void      SysTimeSet( SysTime_t t );
SysTime_t SysTimeGet( void );
SysTime_t SysTimeGetMcuTime( void );

#ifdef __cplusplus
}
#endif

#endif /* SILKEN_LORAWAN_SYSTIME_H */
