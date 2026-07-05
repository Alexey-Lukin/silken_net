/*
 * test_helium_mac_smoke.c — [ARCH.34] host-smoke СПРАВЖНЬОГО LoRaMac-node:
 * лінкує vendored MAC (EU868, soft-se, LmHandler) + owned glue і жене
 * Helium_Mac_SendSos на стаб-радіо. Дві половини:
 *
 * 1) LNS мовчить (тести 1-3) — join чесно вмирає по RX-таймаутах, і САМЕ ЦЕ
 *    і є перевірка TX-половини: state-machine (Init → Configure → Join →
 *    TX JoinRequest → RX1/RX2 вікна → таймаут → deadline-вихід) крутиться
 *    на справжніх TU, а в стаб-ефір летить КРИПТОГРАФІЧНО СПРАВЖНІЙ
 *    JoinRequest: MHDR=0x00, 23 байти, MIC від soft-se (AppKey=нулі
 *    se-identity), DevNonce МОНОТОННИЙ між епізодами.
 *
 * 2) Мок-LNS онлайн (тест 4) — server-половина рукостискання на тих самих
 *    нуль-ключах: звіряє MIC JoinRequest'а, відповідає криптовалідним
 *    JoinAccept у RX1-вікно → ПОВНИЙ цикл join+uplink на host; SOS-кадр
 *    звіряється сесійними ключами, що їх LNS вивів зі СВОГО боку.
 *
 * Свідомо НЕ покрито (04_06 §B.4 — LEAVE, не забуте):
 *  - LmHandlerCallbacks-вітейбл без логіки (GetBatteryLevel/GetTemperature/
 *    OnRxData/OnClassChange/OnBeaconStatusChange/OnSysTimeUpdate/
 *    OnTxPeriodicityChanged/OnTxFrameCtrlChanged/OnPingSlotPeriodicityChanged/
 *    OnSystemReset/OnNvmDataChange/OnRestoreContextRequest/
 *    OnStoreContextRequest/OnNetworkParametersChange) — самі лише required
 *    function-pointers LmHandlerCallbacks_t; SOS-профіль їх не торкається
 *    (без даунлінку, без Class B/C, без ClockSync/NVM-контексту).
 *  - `Helium_Mac_SendSos` return-0 гілки на LmHandlerInit/Configure-фейл
 *    та на LmHandlerSend-фейл — вендорні LmHandler/LoRaMac внутрішні стани
 *    (package-registration clash, вичерпаний duty-cycle, MAC busy у
 *    RX-вікні). Недосяжні під нашим фіксованим валідним EU868-конфігом
 *    без fault-injection у vendored-стан; такий тест звіряв би поведінку
 *    LmHandler/LoRaMac, не нашого adapter'а, і був би крихким під апгрейд
 *    submodule (готча firmware-скіла #12 — вендорна версія міняє класифікацію
 *    під ногами). Реальний тригер — bench/RF територія, не host-мок.
 *
 * Build & run: make -C firmware/test helium_mac_smoke
 */

#include "../queen/helium_sos.h"
#include "../common/flash_kv.h"
#include "radio.h"
#include "lorawan_aes.h" /* мок-LNS: ті самі vendored-примітиви, що soft-se */
#include "cmac.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>

void Helium_Mac_Bind_Nvm( FlashKv *kv );

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

/* ── мок-LNS: server-половина рукостискання на нуль-ключах se-identity ──
 * Крипто — ті самі vendored cmac.c + lorawan_aes.c, що лінкує soft-se
 * (нуль-дублювання логіки); decrypt-напрямок розгейчено -DAES_DEC_PREKEYED
 * лише в цьому бінарі: сервер ШИФРУЄ JoinAccept AES-decrypt-ом, девайс
 * відновлює encrypt-ом — девайсовій половині decrypt не потрібен ніде.
 * Вимкнений LNS (тести TX-половини) мовчить — RX-вікна таймаутять. */
static int      g_lns_enabled;
static int      g_lns_accept_pending; /* Send прийняв join → чекаємо RX-вікна */
static int      g_lns_rx_answer;      /* вікно відкрите → pump доставить кадр */
static uint32_t g_lns_join_nonce;     /* строго вгору — IsJoinNonce10xOk (1.0.4) */
static uint8_t  g_lns_join_accept[17]; /* MHDR + enc(payload 12 + MIC 4), без CFList */
static uint8_t  g_lns_nwk_s_key[16];
static uint8_t  g_lns_app_s_key[16];

#define LNS_NET_ID   0x000013u    /* NetID Helium */
#define LNS_DEV_ADDR 0x26011B07u
static const uint8_t LNS_NWK_KEY[16] = { 0 }; /* AppKey/NwkKey = нулі (se-identity) */

static void lns_cmac4( const uint8_t key[16], const uint8_t *data, uint32_t len,
                       uint8_t out[4] )
{
    AES_CMAC_CTX ctx;
    uint8_t digest[AES_CMAC_DIGEST_LENGTH];
    AES_CMAC_Init( &ctx );
    AES_CMAC_SetKey( &ctx, key );
    AES_CMAC_Update( &ctx, data, len );
    AES_CMAC_Final( digest, &ctx );
    memcpy( out, digest, 4 ); /* MIC = перші 4 байти дайджеста, як на дроті */
}

static void lns_aes_enc( const uint8_t key[16], const uint8_t in[16], uint8_t out[16] )
{
    lorawan_aes_context ctx;
    lorawan_aes_set_key( key, 16, &ctx );
    lorawan_aes_encrypt( in, out, &ctx );
}

static void lns_aes_dec( const uint8_t key[16], const uint8_t in[16], uint8_t out[16] )
{
    lorawan_aes_context ctx;
    lorawan_aes_set_key( key, 16, &ctx );
    lorawan_aes_decrypt( in, out, &ctx );
}

/* Сесійні ключі 1.0.x — дзеркало DeriveSessionKey10x (LoRaMacCrypto.c):
 * enc(NwkKey, tag | JoinNonce(3 LE) | NetID(3 LE) | DevNonce(2 LE) | 0-pad) */
static void lns_derive_key( uint8_t tag, uint32_t join_nonce, uint16_t dev_nonce,
                            uint8_t out[16] )
{
    uint8_t base[16] = { 0 };
    base[0] = tag; /* 0x01 = NwkSKey · 0x02 = AppSKey */
    base[1] = (uint8_t)( join_nonce );
    base[2] = (uint8_t)( join_nonce >> 8 );
    base[3] = (uint8_t)( join_nonce >> 16 );
    base[4] = (uint8_t)( LNS_NET_ID );
    base[5] = (uint8_t)( LNS_NET_ID >> 8 );
    base[6] = (uint8_t)( LNS_NET_ID >> 16 );
    base[7] = (uint8_t)( dev_nonce );
    base[8] = (uint8_t)( dev_nonce >> 8 );
    lns_aes_enc( LNS_NWK_KEY, base, out );
}

/* Дисципліна справжньої LNS: спершу MIC JoinRequest'а, і лише тоді
 * криптовалідний JoinAccept (у RX1-вікно його доставить pump). */
static void lns_answer_join_request( const uint8_t *jr, uint8_t len )
{
    uint8_t mic[4];
    if ( len != 23u || jr[0] != 0x00u ) return;   /* не JoinRequest — мовчимо */
    lns_cmac4( LNS_NWK_KEY, jr, 19u, mic );
    if ( memcmp( mic, jr + 19, 4 ) != 0 ) return; /* MIC-fail → join потоне  */

    uint16_t dev_nonce  = (uint16_t)( jr[17] | ( jr[18] << 8 ) );
    uint32_t join_nonce = ++g_lns_join_nonce;

    /* block[0]=MHDR (лише для CMAC); [1..16] = AES-блок plaintext+MIC:
     * JoinNonce(3) NetID(3) DevAddr(4) DLSettings RxDelay | MIC(4) */
    uint8_t block[17];
    block[0]  = 0x20u;
    block[1]  = (uint8_t)( join_nonce );
    block[2]  = (uint8_t)( join_nonce >> 8 );
    block[3]  = (uint8_t)( join_nonce >> 16 );
    block[4]  = (uint8_t)( LNS_NET_ID );
    block[5]  = (uint8_t)( LNS_NET_ID >> 8 );
    block[6]  = (uint8_t)( LNS_NET_ID >> 16 );
    block[7]  = (uint8_t)( LNS_DEV_ADDR );
    block[8]  = (uint8_t)( LNS_DEV_ADDR >> 8 );
    block[9]  = (uint8_t)( LNS_DEV_ADDR >> 16 );
    block[10] = (uint8_t)( LNS_DEV_ADDR >> 24 );
    block[11] = 0x00u; /* DLSettings: OptNeg=0 (1.0.x), RX1offset=0, RX2=DR0 */
    block[12] = 0x01u; /* RxDelay = 1 с */
    lns_cmac4( LNS_NWK_KEY, block, 13u, block + 13 );

    g_lns_join_accept[0] = 0x20u;
    lns_aes_dec( LNS_NWK_KEY, block + 1, g_lns_join_accept + 1 );
    g_lns_accept_pending = 1;

    /* LNS виводить сесійні ключі зі СВОГО боку — ними тест звірить uplink */
    lns_derive_key( 0x01u, join_nonce, dev_nonce, g_lns_nwk_s_key );
    lns_derive_key( 0x02u, join_nonce, dev_nonce, g_lns_app_s_key );
}

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
    /* реалістичний порядок SF12-кадру (~1.3-1.6 с) — duty-cycle-математика
     * region-коду ганяється на чесних числах, не на іграшкових */
    return 1500u;
}
// cppcheck-suppress constParameterCallback // ABI Radio_s — const зламав би тип поля
static radio_status_t stub_Send( uint8_t *buffer, uint8_t size )
{
    g_tx_count++;
    g_last_tx_len = ( size < sizeof g_last_tx ) ? size : (uint8_t)sizeof g_last_tx;
    memcpy( g_last_tx, buffer, g_last_tx_len );
    if ( g_lns_enabled ) {
        lns_answer_join_request( buffer, size );
    }
    g_tx_pending = 1; /* TxDone віддається з pump'а — не реентеримо MAC */
    return RADIO_STATUS_OK;
}
static void stub_Sleep( void ) { }
static void stub_Standby( void ) { }
static void stub_Rx( uint32_t timeout )
{
    ( void )timeout;
    g_rx_requested++;
    if ( g_lns_accept_pending ) {
        /* вікно СПРАВДІ відкрите — лише тепер LNS сміє відповісти (кадр до
         * Radio.Rx летів би у MAC поза RxSlot-станом) */
        g_lns_accept_pending = 0;
        g_lns_rx_answer = 1;
        return;
    }
    g_rx_timeout_pending = 1; /* ефіру нема — вікно порожнє */
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
    if ( g_lns_rx_answer && g_events != NULL && g_events->RxDone != NULL ) {
        g_lns_rx_answer = 0;
        g_events->RxDone( g_lns_join_accept, sizeof g_lns_join_accept, -50, 8 );
    }
    if ( g_rx_timeout_pending && g_events != NULL && g_events->RxTimeout != NULL ) {
        g_rx_timeout_pending = 0;
        g_events->RxTimeout( );
    }
}

/* ── RAM-KV: DevNonce-персист ганяється справжнім flash_kv-каналом ────── */
#define KV_PAGE_DWS 32u
static uint64_t g_kv_mem[2][KV_PAGE_DWS];
static uint64_t kv_read( void *io, uint32_t byte_off )
{
    ( void )io;
    uint32_t dw = byte_off / 8u;
    return g_kv_mem[dw / KV_PAGE_DWS][dw % KV_PAGE_DWS];
}
static int kv_program( void *io, uint32_t byte_off, uint64_t v )
{
    ( void )io;
    uint32_t dw = byte_off / 8u;
    g_kv_mem[dw / KV_PAGE_DWS][dw % KV_PAGE_DWS] = v;
    return 1;
}
static int kv_erase( void *io, uint8_t page )
{
    ( void )io;
    memset( g_kv_mem[page], 0xFF, sizeof g_kv_mem[page] );
    return 1;
}
static const FlashKvOps g_kv_ops = { kv_read, kv_program, kv_erase };
static FlashKv g_kv;

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
    /* DevNonce живе у байтах 17..18 JoinRequest (little-endian на дроті).
     * Другий епізод жене ПОВНИЙ цикл DeInit→Init→re-bind (симетрія епізоду —
     * фікс events-перебіндингу з code-review). */
    uint16_t nonce1 = (uint16_t)( g_last_tx[17] | ( g_last_tx[18] << 8 ) );

    uint8_t sos[HELIUM_SOS_WIRE_LEN];
    Helium_Sos_Pack( sos, 0xA1B2C3D4u, 0u, 2u, 43u, 0u );
    ( void )Helium_Mac_SendSos( sos, 20000u );
    uint16_t nonce2 = (uint16_t)( g_last_tx[17] | ( g_last_tx[18] << 8 ) );

    ASSERT_TRUE( nonce2 > nonce1 ); /* LNS-replay захист: нонс лише вперед */
    printf("  test_devnonce_monotonic_between_episodes                   ✅\n");
    return 0;
}

static int test_devnonce_survives_reboot_via_kv(void) {
    /* «Ребут»: KV-канал (persist одразу після Join — вікно power-cut
     * звужене до мс) мусить тримати монотонність через холодний старт. */
    uint16_t nonce_before = (uint16_t)( g_last_tx[17] | ( g_last_tx[18] << 8 ) );
    uint32_t stored = 0u;
    ASSERT_TRUE( FlashKv_Get32( &g_kv, 0x30u, &stored ) ); /* persist стався */
    ASSERT_TRUE( (uint16_t)stored >= nonce_before );

    /* Свіжий mount тієї самої "флеші" + re-bind = MCU після ребуту.
     * static — Bind тримає вказівник НАЗАВЖДИ, локальний носій = читання
     * мертвого фрейму наступним епізодом (ASan stack-use-after-scope). */
    static FlashKv kv2;
    ASSERT_TRUE( FlashKv_Mount( &kv2, &g_kv_ops, NULL, KV_PAGE_DWS ) );
    Helium_Mac_Bind_Nvm( &kv2 );

    uint8_t sos[HELIUM_SOS_WIRE_LEN];
    Helium_Sos_Pack( sos, 0xA1B2C3D4u, 0u, 4u, 44u, 0u );
    ( void )Helium_Mac_SendSos( sos, 20000u );
    uint16_t nonce_after = (uint16_t)( g_last_tx[17] | ( g_last_tx[18] << 8 ) );

    ASSERT_TRUE( nonce_after > nonce_before );
    printf("  test_devnonce_survives_reboot_via_kv                       ✅\n");
    return 0;
}

static int test_mock_lns_full_join_and_uplink(void) {
    /* Мок-LNS онлайн → епізод МУСИТЬ дійти до кінця: JoinAccept приймається
     * справжнім RX-трактом MAC (decrypt soft-se, MIC, JoinNonce-перевірка,
     * деривація сесійних ключів), SOS летить data-uplink'ом. Звірка нижче —
     * server-side: MIC NwkSKey'єм і FRMPayload AppSKey'єм, ключами з БОКУ
     * LNS. Дедлайн = БОЙОВИЙ бюджет сліпоти: join+uplink на SF12-TOA і
     * живому duty-cycle EU868 зобов'язані вміститись у нього цілком. */
    g_lns_enabled = 1;
    uint8_t sos[HELIUM_SOS_WIRE_LEN];
    Helium_Sos_Pack( sos, 0xA1B2C3D4u, 1u, 3u, 45u, 1u );

    int ok = Helium_Mac_SendSos( sos, HELIUM_BLIND_WINDOW_MAX_MS );

    ASSERT_EQ( ok, 1 );                 /* повний цикл: join + TxDone        */
    ASSERT_EQ( g_last_tx_len, 25u );    /* MHDR+DevAddr+FCtrl+FCnt+FPort+12+MIC */
    ASSERT_EQ( g_last_tx[0], 0x40u );   /* UnconfirmedDataUp                 */
    uint32_t addr = (uint32_t)g_last_tx[1] | ( (uint32_t)g_last_tx[2] << 8 ) |
                    ( (uint32_t)g_last_tx[3] << 16 ) | ( (uint32_t)g_last_tx[4] << 24 );
    ASSERT_EQ( addr, (uint32_t)LNS_DEV_ADDR ); /* адреса, призначена LNS'ом  */
    ASSERT_EQ( g_last_tx[5] & 0x0Fu, 0u );     /* FOptsLen=0 — офсети чинні  */
    ASSERT_EQ( g_last_tx[8], 2u );             /* FPort SOS-профілю          */
    /* FCnt — з дроту, як його бере справжня LNS (LoRaMac-node шле перший
     * post-join кадр із FCnt=1: NvmCtx тримає останній УЖИТИЙ). Свіжість
     * join'а доводять сесійні ключі нижче — вони від ЦЬОГО JoinNonce. */
    uint32_t fcnt = (uint32_t)g_last_tx[6] | ( (uint32_t)g_last_tx[7] << 8 );

    /* Приймальна перевірка LNS: MIC = cmac(NwkSKey, B0 | MHDR..FRM) */
    uint8_t micbuf[16 + 21] = { 0 };
    micbuf[0]  = 0x49u; /* B0; [1..4]=ConfFCnt=0, [5]=dir=uplink */
    micbuf[6]  = (uint8_t)( addr );
    micbuf[7]  = (uint8_t)( addr >> 8 );
    micbuf[8]  = (uint8_t)( addr >> 16 );
    micbuf[9]  = (uint8_t)( addr >> 24 );
    micbuf[10] = (uint8_t)( fcnt );
    micbuf[11] = (uint8_t)( fcnt >> 8 );
    micbuf[15] = 21u; /* довжина кадру без MIC */
    memcpy( micbuf + 16, g_last_tx, 21 );
    uint8_t mic[4];
    lns_cmac4( g_lns_nwk_s_key, micbuf, sizeof micbuf, mic );
    ASSERT_TRUE( memcmp( mic, g_last_tx + 21, 4 ) == 0 );

    /* FRMPayload: XOR із S1 = enc(AppSKey, A1) → байт-у-байт наш SOS-кадр */
    uint8_t a1[16] = { 0 };
    a1[0]  = 0x01u;
    a1[6]  = (uint8_t)( addr );
    a1[7]  = (uint8_t)( addr >> 8 );
    a1[8]  = (uint8_t)( addr >> 16 );
    a1[9]  = (uint8_t)( addr >> 24 );
    a1[10] = (uint8_t)( fcnt );
    a1[11] = (uint8_t)( fcnt >> 8 );
    a1[15] = 0x01u; /* лічильник блоків CTR — перший */
    uint8_t s1[16];
    lns_aes_enc( g_lns_app_s_key, a1, s1 );
    uint8_t frm[HELIUM_SOS_WIRE_LEN];
    for ( unsigned i = 0; i < HELIUM_SOS_WIRE_LEN; i++ ) {
        frm[i] = g_last_tx[9 + i] ^ s1[i];
    }
    ASSERT_TRUE( memcmp( frm, sos, HELIUM_SOS_WIRE_LEN ) == 0 );
    printf("  test_mock_lns_full_join_and_uplink                         ✅\n");
    return 0;
}

int main(void) {
    int fails = 0;
    printf("test_helium_mac_smoke — [ARCH.34] справжній LoRaMac на стаб-радіо:\n");
    if ( !FlashKv_Mount( &g_kv, &g_kv_ops, NULL, KV_PAGE_DWS ) ) {
        fprintf(stderr, "❌ KV mount failed\n");
        return 1;
    }
    Helium_Mac_Bind_Nvm( &g_kv );
    fails += test_episode_tx_real_join_request();
    fails += test_devnonce_monotonic_between_episodes();
    fails += test_devnonce_survives_reboot_via_kv();
    fails += test_mock_lns_full_join_and_uplink();
    if (fails) {
        fprintf(stderr, "❌ test_helium_mac_smoke: %d failed\n", fails);
        return 1;
    }
    printf("✅ test_helium_mac_smoke: всі тести зелені\n");
    return 0;
}
