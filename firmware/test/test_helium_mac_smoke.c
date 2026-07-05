/*
 * test_helium_mac_smoke.c — [ARCH.34] host-smoke СПРАВЖНЬОГО LoRaMac-node:
 * лінкує vendored MAC (EU868, soft-se, LmHandler) + owned glue і жене
 * Helium_Mac_SendSos на стаб-радіо. Радіо-ефіру нема — join впаде по
 * RX-таймаутах, і САМЕ ЦЕ і є перевірка: state-machine (Init → Configure →
 * Join → TX JoinRequest → RX1/RX2 вікна → таймаут → deadline-вихід)
 * крутиться на справжніх TU, а в стаб-ефір летить КРИПТОГРАФІЧНО СПРАВЖНІЙ
 * JoinRequest: MHDR=0x00, 23 байти, MIC від soft-se (AppKey=нулі
 * se-identity), DevNonce МОНОТОННИЙ між епізодами.
 *
 * Build & run: make -C firmware/test helium_mac_smoke
 * (JoinAccept-відповідь = мок-LNS з валідним крипто — окремий крок,
 *  00_07 ARCH.34; тут доводимо TX-половину і дисципліну епізоду.)
 */

#include "../queen/helium_sos.h"
#include "radio.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        fprintf(stderr, "FAIL %s:%d  expected %ld got %ld\n", \
                __FILE__, __LINE__, (long)(b), (long)(a)); \
        return 1; \
    } \
} while (0)

#define ASSERT_TRUE(x) do { \
    if (!(x)) { \
        fprintf(stderr, "FAIL %s:%d  %s is false\n", __FILE__, __LINE__, #x); \
        return 1; \
    } \
} while (0)

/* ── фейк-годинник: автоінкремент жене MAC-таймери (RX-вікна) уперед ──── */
static uint32_t g_tick;
uint32_t Helium_Test_Tick_Ms( void )
{
    g_tick += 1u; /* 1 мс на опит — 20с deadline = 20k ітерацій pump */
    return g_tick;
}

/* ── стаб-радіо: перехоплює ефір, симулює TxDone, RX завжди таймаутить ── */
static RadioEvents_t *g_events;
static int      g_tx_count;
static uint8_t  g_last_tx[64];
static uint8_t  g_last_tx_len;
static int      g_rx_requested;
static int      g_tx_pending;
static int      g_rx_timeout_pending;

static void         stub_Init( RadioEvents_t *events ) { g_events = events; }
static RadioState_t stub_GetStatus( void ) { return RF_IDLE; }
static void         stub_SetModem( RadioModems_t m ) { ( void )m; }
static void         stub_SetChannel( uint32_t f ) { ( void )f; }
static bool         stub_IsChannelFree( uint32_t f, uint32_t bw, int16_t t, uint32_t m )
{ ( void )f; ( void )bw; ( void )t; ( void )m; return true; }
static uint32_t     stub_Random( void ) { return 0xC0FFEEu; }
static void stub_SetRxConfig( RadioModems_t modem, uint32_t bandwidth,
                              uint32_t datarate, uint8_t coderate,
                              uint32_t bandwidthAfc, uint16_t preambleLen,
                              uint16_t symbTimeout, bool fixLen,
                              uint8_t payloadLen,
                              bool crcOn, bool freqHopOn, uint8_t hopPeriod,
                              bool iqInverted, bool rxContinuous )
{
    ( void )modem; ( void )bandwidth; ( void )datarate; ( void )coderate;
    ( void )bandwidthAfc; ( void )preambleLen; ( void )symbTimeout;
    ( void )fixLen; ( void )payloadLen; ( void )crcOn; ( void )freqHopOn;
    ( void )hopPeriod; ( void )iqInverted; ( void )rxContinuous;
}
static void stub_SetTxConfig( RadioModems_t modem, int8_t power, uint32_t fdev,
                              uint32_t bandwidth, uint32_t datarate,
                              uint8_t coderate, uint16_t preambleLen,
                              bool fixLen, bool crcOn, bool freqHopOn,
                              uint8_t hopPeriod, bool iqInverted, uint32_t timeout )
{
    ( void )modem; ( void )power; ( void )fdev; ( void )bandwidth;
    ( void )datarate; ( void )coderate; ( void )preambleLen; ( void )fixLen;
    ( void )crcOn; ( void )freqHopOn; ( void )hopPeriod; ( void )iqInverted;
    ( void )timeout;
}
static bool     stub_CheckRfFrequency( uint32_t f ) { ( void )f; return true; }
static uint32_t stub_TimeOnAir( RadioModems_t modem, uint32_t bandwidth,
                                uint32_t datarate, uint8_t coderate,
                                uint16_t preambleLen, bool fixLen,
                                uint8_t payloadLen, bool crcOn )
{
    ( void )modem; ( void )bandwidth; ( void )datarate; ( void )coderate;
    ( void )preambleLen; ( void )fixLen; ( void )payloadLen; ( void )crcOn;
    return 100u;
}
// cppcheck-suppress constParameterCallback // ABI Radio_s — const зламав би тип поля
static radio_status_t stub_Send( uint8_t *buffer, uint8_t size )
{
    g_tx_count++;
    g_last_tx_len = ( size < sizeof g_last_tx ) ? size : (uint8_t)sizeof g_last_tx;
    memcpy( g_last_tx, buffer, g_last_tx_len );
    g_tx_pending = 1; /* TxDone віддається з pump'а — не реентеримо MAC */
    return RADIO_STATUS_OK;
}
static void stub_Sleep( void ) { }
static void stub_Standby( void ) { }
static void stub_Rx( uint32_t timeout )
{
    ( void )timeout;
    g_rx_requested++;
    g_rx_timeout_pending = 1; /* ефіру нема — вікно завжди порожнє */
}
static void stub_SetTxContinuousWave( uint32_t f, int8_t p, uint16_t t )
{ ( void )f; ( void )p; ( void )t; }
static void     stub_SetMaxPayloadLength( RadioModems_t m, uint8_t max )
{ ( void )m; ( void )max; }
static void     stub_SetPublicNetwork( bool enable ) { ( void )enable; }
static uint32_t stub_GetWakeupTime( void ) { return 3u; }

const struct Radio_s Radio = {
    .Init                = stub_Init,
    .GetStatus           = stub_GetStatus,
    .SetModem            = stub_SetModem,
    .SetChannel          = stub_SetChannel,
    .IsChannelFree       = stub_IsChannelFree,
    .Random              = stub_Random,
    .SetRxConfig         = stub_SetRxConfig,
    .SetTxConfig         = stub_SetTxConfig,
    .CheckRfFrequency    = stub_CheckRfFrequency,
    .TimeOnAir           = stub_TimeOnAir,
    .Send                = stub_Send,
    .Sleep               = stub_Sleep,
    .Standby             = stub_Standby,
    .Rx                  = stub_Rx,
    .SetTxContinuousWave = stub_SetTxContinuousWave,
    .SetMaxPayloadLength = stub_SetMaxPayloadLength,
    .SetPublicNetwork    = stub_SetPublicNetwork,
    .GetWakeupTime       = stub_GetWakeupTime,
};

/* Відкладені radio-події: MAC не реентериться зсередини власних викликів.
 * Adapter кличе LmHandlerProcess у циклі — між ітераціями цей самий цикл
 * (через прапори вище) віддає TxDone/RxTimeout, як IRQ віддав би на MCU. */
void Helium_Test_Pump_Radio( void )
{
    if ( g_tx_pending && g_events != NULL && g_events->TxDone != NULL ) {
        g_tx_pending = 0;
        g_events->TxDone( );
    }
    if ( g_rx_timeout_pending && g_events != NULL && g_events->RxTimeout != NULL ) {
        g_rx_timeout_pending = 0;
        g_events->RxTimeout( );
    }
}

/* ── тести ────────────────────────────────────────────────────────────── */
static int test_episode_tx_real_join_request(void) {
    uint8_t sos[HELIUM_SOS_WIRE_LEN];
    Helium_Sos_Pack( sos, 0xA1B2C3D4u, 0u, 2u, 42u, 0u );

    int ok = Helium_Mac_SendSos( sos, 20000u );

    ASSERT_EQ( ok, 0 );                 /* ефіру нема — епізод чесно здався */
    ASSERT_TRUE( g_tx_count >= 1 );     /* але JoinRequest РЕАЛЬНО полетів  */
    ASSERT_EQ( g_last_tx_len, 23u );    /* MHDR+JoinEUI+DevEUI+DevNonce+MIC */
    ASSERT_EQ( g_last_tx[0], 0x00u );   /* MHDR = JoinRequest, LoRaWAN R1   */
    ASSERT_TRUE( g_rx_requested >= 1 ); /* RX-вікна відкривались            */
    printf("  test_episode_tx_real_join_request                          ✅\n");
    return 0;
}

static int test_devnonce_monotonic_between_episodes(void) {
    /* DevNonce живе у байтах 17..18 JoinRequest (little-endian на дроті). */
    uint16_t nonce1 = (uint16_t)( g_last_tx[17] | ( g_last_tx[18] << 8 ) );

    uint8_t sos[HELIUM_SOS_WIRE_LEN];
    Helium_Sos_Pack( sos, 0xA1B2C3D4u, 0u, 2u, 43u, 0u );
    ( void )Helium_Mac_SendSos( sos, 20000u );
    uint16_t nonce2 = (uint16_t)( g_last_tx[17] | ( g_last_tx[18] << 8 ) );

    ASSERT_TRUE( nonce2 > nonce1 ); /* LNS-replay захист: нонс лише вперед */
    printf("  test_devnonce_monotonic_between_episodes                   ✅\n");
    return 0;
}

int main(void) {
    int fails = 0;
    printf("test_helium_mac_smoke — [ARCH.34] справжній LoRaMac на стаб-радіо:\n");
    fails += test_episode_tx_real_join_request();
    fails += test_devnonce_monotonic_between_episodes();
    if (fails) {
        fprintf(stderr, "❌ test_helium_mac_smoke: %d failed\n", fails);
        return 1;
    }
    printf("✅ test_helium_mac_smoke: всі тести зелені\n");
    return 0;
}
