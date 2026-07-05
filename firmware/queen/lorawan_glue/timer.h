#ifndef SILKEN_LORAWAN_TIMER_H
#define SILKEN_LORAWAN_TIMER_H

#include <stdint.h>
#include "soft_timer.h"

/*
 * timer.h — [ARCH.34] контракт Conf/timer_template.h поверх owned
 * soft_timer (замість UTIL_TIMER зі stm32-utilities). LoRaMac бачить
 * TimerEvent_t непрозоро — лише ці виклики (звірено grep'ом по Mac/).
 */

#ifdef __cplusplus
extern "C" {
#endif

#define TIMERTIME_T_MAX ( ( uint32_t )~0 )

typedef uint32_t    TimerTime_t;
#define TimerEvent_t SoftTimer_t

#define TimerInit( HANDLE, CB )         Soft_Timer_Init( ( HANDLE ), ( CB ) )
#define TimerSetValue( HANDLE, TIMEOUT ) Soft_Timer_Set_Value( ( HANDLE ), ( TIMEOUT ) )
#define TimerStart( HANDLE )            Soft_Timer_Start( ( HANDLE ) )
#define TimerStop( HANDLE )             Soft_Timer_Stop( ( HANDLE ) )

#define TimerGetCurrentTime( )          Soft_Timer_Now_Ms( )
#define TimerGetElapsedTime( PAST )     Soft_Timer_Elapsed_Since( ( PAST ) )

/* ClassB-only компенсація дрейфу RTC від температури (LORAMAC_CLASSB=0 —
 * шлях мертвий, passthrough тримає лінк чесним, якщо TU її потягне). */
static inline TimerTime_t TimerTempCompensation( TimerTime_t period, float temperature )
{
    ( void )temperature;
    return period;
}

#ifdef __cplusplus
}
#endif

#endif /* SILKEN_LORAWAN_TIMER_H */
