// SPDX-License-Identifier: AGPL-3.0-or-later
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
    /* Від'ємні секунди НЕ клемпимо — Semtech-семантика: Seconds віднімаються
     * unsigned wrap'ом, і duty-cycle/backoff математика RegionCommon живе
     * саме на wrap-різницях. Клемп до нуля ламав би облік на rollover
     * HAL_GetTick (49.7 діб — Королева always-on, досяжно; code-review). */
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
