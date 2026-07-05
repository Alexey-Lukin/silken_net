/*
 * systime.c — [ARCH.34] тіло owned-systime (контракт у .h).
 * Арифметика — нормалізація SubSeconds у 0..999 (класичне гніздо помилок
 * зі знаками — host-тест test_soft_timer.c ганяє граничні).
 */
#include "systime.h"
#include "soft_timer.h"

/* Зсув wall-годинника відносно MCU-часу (SysTimeSet від DeviceTimeAns).
 * SOS-шлях його не рухає — 0 = boot-relative. */
static SysTime_t g_wall_offset = { 0, 0 };

static SysTime_t normalize( int64_t seconds, int32_t sub_ms )
{
    SysTime_t out;
    while ( sub_ms < 0 )    { sub_ms += 1000; seconds -= 1; }
    while ( sub_ms >= 1000 ) { sub_ms -= 1000; seconds += 1; }
    if ( seconds < 0 ) seconds = 0; /* час не тече назад: клемп до епохи */
    out.Seconds    = (uint32_t)seconds;
    out.SubSeconds = (int16_t)sub_ms;
    return out;
}

SysTime_t SysTimeAdd( SysTime_t a, SysTime_t b )
{
    return normalize( (int64_t)a.Seconds + (int64_t)b.Seconds,
                      (int32_t)a.SubSeconds + (int32_t)b.SubSeconds );
}

SysTime_t SysTimeSub( SysTime_t a, SysTime_t b )
{
    return normalize( (int64_t)a.Seconds - (int64_t)b.Seconds,
                      (int32_t)a.SubSeconds - (int32_t)b.SubSeconds );
}

uint32_t SysTimeToMs( SysTime_t t )
{
    return t.Seconds * 1000u + (uint32_t)t.SubSeconds;
}

SysTime_t SysTimeFromMs( uint32_t ms )
{
    SysTime_t out;
    out.Seconds    = ms / 1000u;
    out.SubSeconds = (int16_t)( ms % 1000u );
    return out;
}

SysTime_t SysTimeGetMcuTime( void )
{
    return SysTimeFromMs( Soft_Timer_Now_Ms( ) );
}

void SysTimeSet( SysTime_t t )
{
    g_wall_offset = SysTimeSub( t, SysTimeGetMcuTime( ) );
}

SysTime_t SysTimeGet( void )
{
    return SysTimeAdd( SysTimeGetMcuTime( ), g_wall_offset );
}
