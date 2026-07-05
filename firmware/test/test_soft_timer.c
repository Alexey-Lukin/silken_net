/*
 * test_soft_timer.c — [ARCH.34] owned таймер-движок під LoRaMac-node
 * (queen/lorawan_glue/soft_timer.c) + systime-арифметика.
 *
 * Build & run: make -C firmware/test soft_timer
 *
 * Джерело часу інжектоване — тест крутить фейк-тік руками (wrap-кейси
 * включно; движок живе на цьому ж контракті і на MCU — HAL_GetTick).
 */

#include "../queen/lorawan_glue/soft_timer.h"
#include "../queen/lorawan_glue/systime.h"
#include <stdio.h>
#include <stdint.h>

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        fprintf(stderr, "FAIL %s:%d  expected %ld got %ld\n", \
                __FILE__, __LINE__, (long)(b), (long)(a)); \
        return 1; \
    } \
} while (0)

static uint32_t g_tick;
uint32_t Soft_Timer_Now_Ms( void ) { return g_tick; }

static int      g_fired;
static SoftTimer_t g_self_restart;

static void on_fire( void *ctx ) { ( void )ctx; g_fired++; }

static void on_fire_and_restart( void *ctx )
{
    ( void )ctx;
    g_fired++;
    if ( g_fired < 3 ) Soft_Timer_Start( &g_self_restart ); /* періодика руками */
}

static int test_oneshot_fires_once(void) {
    SoftTimer_t t;
    g_tick = 1000u; g_fired = 0;
    Soft_Timer_Init( &t, on_fire );
    Soft_Timer_Set_Value( &t, 50u );
    Soft_Timer_Start( &t );
    ASSERT_EQ( Soft_Timer_Dispatch( ), 0u );  /* ще рано */
    g_tick += 49u;
    ASSERT_EQ( Soft_Timer_Dispatch( ), 0u );
    g_tick += 1u;                              /* рівно target */
    ASSERT_EQ( Soft_Timer_Dispatch( ), 1u );
    ASSERT_EQ( g_fired, 1 );
    ASSERT_EQ( Soft_Timer_Dispatch( ), 0u );  /* one-shot: удруге мовчить */
    ASSERT_EQ( t.IsRunning, 0u );
    printf("  test_oneshot_fires_once                                    ✅\n");
    return 0;
}

static int test_stop_silences(void) {
    SoftTimer_t t;
    g_tick = 0u; g_fired = 0;
    Soft_Timer_Init( &t, on_fire );
    Soft_Timer_Set_Value( &t, 10u );
    Soft_Timer_Start( &t );
    Soft_Timer_Stop( &t );
    g_tick += 100u;
    ASSERT_EQ( Soft_Timer_Dispatch( ), 0u );
    ASSERT_EQ( g_fired, 0 );
    printf("  test_stop_silences                                         ✅\n");
    return 0;
}

static int test_restart_from_callback(void) {
    g_tick = 0u; g_fired = 0;
    Soft_Timer_Init( &g_self_restart, on_fire_and_restart );
    Soft_Timer_Set_Value( &g_self_restart, 10u );
    Soft_Timer_Start( &g_self_restart );
    for ( int i = 0; i < 5; i++ ) {
        g_tick += 10u;
        Soft_Timer_Dispatch( );
    }
    ASSERT_EQ( g_fired, 3 ); /* callback перезапускав себе двічі й замовк */
    printf("  test_restart_from_callback                                 ✅\n");
    return 0;
}

static int test_tick_wrap(void) {
    SoftTimer_t t;
    g_tick = 0xFFFFFFF0u; g_fired = 0; /* за 16 мс до переповнення */
    Soft_Timer_Init( &t, on_fire );
    Soft_Timer_Set_Value( &t, 100u );  /* target = 0x54 після wrap */
    Soft_Timer_Start( &t );
    g_tick = 0x00000010u;              /* уже за wrap'ом, 48 мс минуло */
    ASSERT_EQ( Soft_Timer_Dispatch( ), 0u );
    g_tick = 0x00000054u;              /* рівно 100 мс */
    ASSERT_EQ( Soft_Timer_Dispatch( ), 1u );
    ASSERT_EQ( g_fired, 1 );
    printf("  test_tick_wrap                                             ✅\n");
    return 0;
}

static int test_reinit_unlinks_stale(void) {
    SoftTimer_t t;
    g_tick = 0u; g_fired = 0;
    Soft_Timer_Init( &t, on_fire );
    Soft_Timer_Set_Value( &t, 5u );
    Soft_Timer_Start( &t );
    Soft_Timer_Init( &t, on_fire ); /* ре-Init активного: хвіст у списку = крах */
    g_tick += 50u;
    ASSERT_EQ( Soft_Timer_Dispatch( ), 0u ); /* після ре-Init він зупинений */
    printf("  test_reinit_unlinks_stale                                  ✅\n");
    return 0;
}

static int test_systime_normalization(void) {
    /* Від'ємний SubSeconds після Sub — класичне гніздо помилок. */
    SysTime_t a = { 10u, 200 };
    SysTime_t b = {  3u, 700 };
    SysTime_t d = SysTimeSub( a, b ); /* 6.500 */
    ASSERT_EQ( d.Seconds, 6u );
    ASSERT_EQ( d.SubSeconds, 500 );
    SysTime_t s = SysTimeAdd( d, b ); /* назад 10.200 */
    ASSERT_EQ( s.Seconds, 10u );
    ASSERT_EQ( s.SubSeconds, 200 );
    ASSERT_EQ( SysTimeToMs( d ), 6500u );
    SysTime_t f = SysTimeFromMs( 12345u );
    ASSERT_EQ( f.Seconds, 12u );
    ASSERT_EQ( f.SubSeconds, 345 );
    /* Від'ємна різниця = unsigned wrap (Semtech-семантика — duty-cycle
     * математика RegionCommon живе на wrap-різницях через rollover тіків). */
    SysTime_t neg = SysTimeSub( b, a ); /* 3.700−10.200 = −6.5 = −7s+500ms */
    ASSERT_EQ( neg.Seconds, 0xFFFFFFF9u ); /* (uint32_t)-7 */
    ASSERT_EQ( neg.SubSeconds, 500 );
    printf("  test_systime_normalization                                 ✅\n");
    return 0;
}

static SoftTimer_t g_zero_period;
static void on_fire_zero_forever( void *ctx )
{
    ( void )ctx;
    g_fired++;
    Soft_Timer_Start( &g_zero_period ); /* period-0 вічний self-restart */
}

static int test_dispatch_cap_breaks_zero_period_loop(void) {
    g_tick = 0u; g_fired = 0;
    Soft_Timer_Init( &g_zero_period, on_fire_zero_forever );
    Soft_Timer_Set_Value( &g_zero_period, 0u );
    Soft_Timer_Start( &g_zero_period );
    /* Без cap це вічний цикл (0 >= 0 і зі свіжим now) — Dispatch мусить
     * повернутись, віддавши прогрес полінг-циклу викликача. */
    uint32_t fired = Soft_Timer_Dispatch( );
    ASSERT_EQ( fired, 32u );
    Soft_Timer_Stop( &g_zero_period );
    printf("  test_dispatch_cap_breaks_zero_period_loop                  ✅\n");
    return 0;
}

static int test_mcu_time_follows_tick(void) {
    g_tick = 65432u;
    SysTime_t m = SysTimeGetMcuTime( );
    ASSERT_EQ( m.Seconds, 65u );
    ASSERT_EQ( m.SubSeconds, 432 );
    printf("  test_mcu_time_follows_tick                                 ✅\n");
    return 0;
}

static int test_systime_wall_clock_offset(void) {
    /* SysTimeSet/Get — офсет годинника від DeviceTimeAns (SOS-маяк цим
     * шляхом не ходить, systime.h; контракт лишається чесним для того, хто
     * колись підключить ClockSync). Set фіксує offset = wall − mcu «зараз»;
     * Get() відтоді = поточний mcu + той самий offset — прив'язка тримається
     * крізь плин тіків, а не застигає на значенні з моменту синхронізації. */
    g_tick = 5000u;                      /* mcu = 5.000 с у момент синхронізації */
    SysTime_t wall = { 1000000u, 250 };  /* сервер каже: зараз 1000000.250 с     */
    SysTimeSet( wall );

    SysTime_t now = SysTimeGet( );       /* той самий тік — Get() = щойно заданий wall */
    ASSERT_EQ( now.Seconds, wall.Seconds );
    ASSERT_EQ( now.SubSeconds, wall.SubSeconds );

    g_tick += 2500u;                     /* +2.500 с mcu-часу спливло             */
    SysTime_t later = SysTimeGet( );
    ASSERT_EQ( later.Seconds, wall.Seconds + 2u );
    ASSERT_EQ( later.SubSeconds, 750 );  /* offset тримає прив'язку, не reset      */
    printf("  test_systime_wall_clock_offset                             ✅\n");
    return 0;
}

int main(void) {
    int fails = 0;
    printf("test_soft_timer — [ARCH.34] owned таймер + systime:\n");
    fails += test_oneshot_fires_once();
    fails += test_stop_silences();
    fails += test_restart_from_callback();
    fails += test_tick_wrap();
    fails += test_reinit_unlinks_stale();
    fails += test_dispatch_cap_breaks_zero_period_loop();
    fails += test_systime_normalization();
    fails += test_mcu_time_follows_tick();
    fails += test_systime_wall_clock_offset();
    if (fails) {
        fprintf(stderr, "❌ test_soft_timer: %d failed\n", fails);
        return 1;
    }
    printf("✅ test_soft_timer: всі тести зелені\n");
    return 0;
}
