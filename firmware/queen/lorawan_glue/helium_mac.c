/*
 * helium_mac.c — [ARCH.34] adapter: Helium_Mac_SendSos поверх vendored
 * LoRaMac-node (LmHandler). Викликач — queen_helium_lorawan_uplink()
 * (main.c), який ВЖЕ тримає всю hard-rule обв'язку сліпоти (IWDG pre/post,
 * повернення вух + ECB, вирок бюджету) — тут лише LoRaWAN-епізод.
 *
 * Модель епізоду (SOS-only профіль, lorawan_conf.h):
 *   Init(раз) → Join OTAA force → тугий цикл LmHandlerProcess+таймери →
 *   Send unconfirmed 12 Б → цикл до TxDone → персист DevNonce.
 * Контекст сесії ЕФЕМЕРНИЙ (fresh join щоепізоду — legal 1.0.4; сесійні
 * ключі народжуються заново). Єдине, що LNS вимагає монотонним МІЖ
 * join'ами, — DevNonce: один u32 у Queen flash_kv (ключ 0x30) через
 * MIB_NVM_CTXS; без KV-біндінгу (до bench-mount) епізод чесно деградує —
 * перший join пройде, повторний після ребуту Helium може відкинути
 * (residual → 00_07 ARCH.34).
 *
 * IWDG всередині НЕ годуємо свідомо: deadline ≤ 20 с < вікно пса 26.6 с —
 * якщо цикл завис глибше за deadline, пес і МАЄ вкусити (канон 02_05 §6.1).
 */
#include "../helium_sos.h"
#include "../../common/flash_kv.h"

#include "platform.h"
#include "lorawan_conf.h"
#include "soft_timer.h"
#include "lora_info.h"
#include "LmHandler.h"
#include "LoRaMac.h"

#define HELIUM_SOS_FPORT        2u
#define HELIUM_KV_KEY_DEVNONCE  0x30u /* Queen KV-простір 0x30+ (00_07 ARCH.34) */

/* ── стан епізоду (single-threaded main loop) ─────────────────────────── */
static uint8_t  g_initialized;
static uint8_t  g_joined;
static uint8_t  g_tx_done;
static FlashKv *g_kv; /* NULL до bench-mount — DevNonce ephemeral */

/* ── джерело часу для soft_timer/systime ──────────────────────────────── */
#if defined(STM32WLE5xx) || defined(USE_HAL_DRIVER)
#include "stm32wlxx_hal.h"
uint32_t Soft_Timer_Now_Ms( void ) { return HAL_GetTick( ); }
/* IRQ справжній; __WFI дрімає між подіями — SysTick (1 кГц, живить
 * HAL_GetTick) будить щомс, тож полінг-таймери НЕ просипають вікна,
 * а 20-секундний епізод не палить ядро даремно. */
#define HELIUM_PUMP_RADIO_HOOK( ) __WFI( )
#else
/* host-збірка: тік і відкладені radio-події (IRQ-сурогат) дає тест-харнес */
extern uint32_t Helium_Test_Tick_Ms( void );
extern void     Helium_Test_Pump_Radio( void );
uint32_t Soft_Timer_Now_Ms( void ) { return Helium_Test_Tick_Ms( ); }
#define HELIUM_PUMP_RADIO_HOOK( ) Helium_Test_Pump_Radio( )
#endif

/* ── LmHandler callbacks ──────────────────────────────────────────────── */
static uint8_t GetBatteryLevel( void ) { return 254u; } /* Queen на LiFePO4-мережі */
static int16_t GetTemperature( void )  { return 0; }

static void GetUniqueId( uint8_t *id )
{
#if defined(STM32WLE5xx) || defined(USE_HAL_DRIVER)
    /* DevEUI з 96-bit HW UID (та сама база, що UNPROV-fallback Queen UID);
     * UID_BASE — CMSIS-константа кремнію, не магічна адреса. */
    const uint8_t *uid = (const uint8_t *)UID_BASE;
    for ( int i = 0; i < 8; i++ ) id[i] = uid[i];
#else
    for ( int i = 0; i < 8; i++ ) id[i] = (uint8_t)( 0xA0u + i );
#endif
}

static void GetDevAddr( uint32_t *devAddr ) { *devAddr = 0u; } /* OTAA: LNS призначить */

// cppcheck-suppress constParameterCallback // ABI LmHandlerCallbacks_t — const зламав би тип поля
static void OnJoinRequest( LmHandlerJoinParams_t *params )
{
    if ( params != NULL && params->Status == LORAMAC_HANDLER_SUCCESS ) {
        g_joined = 1u;
    }
}

static void OnTxData( LmHandlerTxParams_t *params )
{
    ( void )params;
    g_tx_done = 1u;
}

/* Решта — свідомі no-op: SOS не приймає downlink-даних (RX-вікна MAC
 * відпрацьовує сам), клас не міняємо, beacon/ClockSync вимкнені конфігом. */
static void OnMacProcess( void ) { }
static void OnNvmDataChange( LmHandlerNvmContextStates_t s ) { ( void )s; }
static void OnRestoreContextRequest( void *nvm, uint32_t n ) { ( void )nvm; ( void )n; }
static void OnStoreContextRequest( void *nvm, uint32_t n ) { ( void )nvm; ( void )n; }
static void OnNetworkParametersChange( CommissioningParams_t *p ) { ( void )p; }
static void OnRxData( LmHandlerAppData_t *d, LmHandlerRxParams_t *p ) { ( void )d; ( void )p; }
static void OnClassChange( DeviceClass_t c ) { ( void )c; }
static void OnBeaconStatusChange( LmHandlerBeaconParams_t *p ) { ( void )p; }
static void OnSysTimeUpdate( void ) { }
static void OnTxPeriodicityChanged( uint32_t p ) { ( void )p; }
static void OnTxFrameCtrlChanged( LmHandlerMsgTypes_t m ) { ( void )m; }
static void OnPingSlotPeriodicityChanged( uint8_t p ) { ( void )p; }
static void OnSystemReset( void ) { }

static LmHandlerCallbacks_t g_callbacks = {
    .GetBatteryLevel              = GetBatteryLevel,
    .GetTemperature               = GetTemperature,
    .GetUniqueId                  = GetUniqueId,
    .GetDevAddr                   = GetDevAddr,
    .OnRestoreContextRequest      = OnRestoreContextRequest,
    .OnStoreContextRequest        = OnStoreContextRequest,
    .OnMacProcess                 = OnMacProcess,
    .OnNvmDataChange              = OnNvmDataChange,
    .OnNetworkParametersChange    = OnNetworkParametersChange,
    .OnJoinRequest                = OnJoinRequest,
    .OnTxData                     = OnTxData,
    .OnRxData                     = OnRxData,
    .OnClassChange                = OnClassChange,
    .OnBeaconStatusChange         = OnBeaconStatusChange,
    .OnSysTimeUpdate              = OnSysTimeUpdate,
    .OnTxPeriodicityChanged       = OnTxPeriodicityChanged,
    .OnTxFrameCtrlChanged         = OnTxFrameCtrlChanged,
    .OnPingSlotPeriodicityChanged = OnPingSlotPeriodicityChanged,
    .OnSystemReset                = OnSystemReset,
};

static uint8_t g_lmh_data_buffer[64]; /* 12 Б SOS + запас MAC-команд */

static LmHandlerParams_t g_params = {
    .ActiveRegion        = LORAMAC_REGION_EU868,
    .DefaultClass        = CLASS_A,
    .AdrEnable           = false,       /* SOS = фіксований DR, не оптимізація */
    .IsTxConfirmed       = LORAMAC_HANDLER_UNCONFIRMED_MSG,
    .TxDatarate          = DR_0,        /* SF12 — максимальний reach до hotspot'а */
    .TxPower             = 0,           /* TX_POWER_0 = максимум регіону */
    .PublicNetworkEnable = true,
    .DutyCycleEnabled    = true,        /* ETSI EU868 — не обхідний */
    .DataBufferMaxSize   = sizeof g_lmh_data_buffer,
    .DataBuffer          = g_lmh_data_buffer,
    .PingSlotPeriodicity = 0,
    .RxBCTimeout         = 0,
};

/* ── DevNonce persist (MIB_NVM_CTXS → flash_kv) ───────────────────────── */
static LoRaMacNvmData_t *nvm_ctx( void )
{
    MibRequestConfirm_t mib;
    mib.Type = MIB_NVM_CTXS;
    if ( LoRaMacMibGetRequestConfirm( &mib ) != LORAMAC_STATUS_OK ) return NULL;
    return mib.Param.Contexts;
}

static void devnonce_restore( void )
{
    uint32_t stored;
    LoRaMacNvmData_t *nvm = nvm_ctx( );
    if ( nvm == NULL || g_kv == NULL ) return;
    if ( FlashKv_Get32( g_kv, HELIUM_KV_KEY_DEVNONCE, &stored ) ) {
        nvm->Crypto.DevNonce = (uint16_t)stored;
    }
}

static void devnonce_persist( void )
{
    const LoRaMacNvmData_t *nvm = nvm_ctx( );
    if ( nvm == NULL || g_kv == NULL ) return;
    ( void )FlashKv_Put32( g_kv, HELIUM_KV_KEY_DEVNONCE, nvm->Crypto.DevNonce );
}

void Helium_Mac_Bind_Nvm( FlashKv *kv )
{
    g_kv = kv;
}

/* ── епізод ───────────────────────────────────────────────────────────── */
static void pump_until( const volatile uint8_t *flag, uint32_t deadline_tick )
{
    while ( !*flag &&
            (int32_t)( Soft_Timer_Now_Ms( ) - deadline_tick ) < 0 ) {
        HELIUM_PUMP_RADIO_HOOK( );
        Soft_Timer_Dispatch( );
        LmHandlerProcess( );
    }
}

int Helium_Mac_SendSos( const uint8_t sos_frame[HELIUM_SOS_WIRE_LEN],
                        uint32_t deadline_ms )
{
    uint32_t deadline_tick = Soft_Timer_Now_Ms( ) + deadline_ms;

    /* ПОВНИЙ пере-Init ЩОЕПІЗОДУ — не латч. Semtech-драйвер тримає ОДИН
     * static-вказівник events: LoRaMacInitialization біндить свою таблицю,
     * а post-episode main.c повертає Queen'ину (Radio_Reinit_RawLoRa —
     * інакше Королева ГЛУХНЕ до Солдатів назавжди, знахідка code-review
     * 2-го епізоду). Отже наступний епізод МУСИТЬ ре-біндити MAC заново;
     * DeInit best-effort (BUSY після deadline-аборту — Init однаково
     * перезбирає MacCtx; стан епізоду не переживає — ephemeral by design). */
    if ( g_initialized ) {
        ( void )LmHandlerDeInit( );
    }
    LoraInfo_Init( );
    if ( LmHandlerInit( &g_callbacks, 0x01000000u ) != LORAMAC_HANDLER_SUCCESS ) {
        return 0;
    }
    if ( LmHandlerConfigure( &g_params ) != LORAMAC_HANDLER_SUCCESS ) {
        return 0;
    }
    g_initialized = 1u;

    /* fresh join щоепізоду; DevNonce тягнемо З persist ДО join, назад —
     * ПІСЛЯ (LoRaMacCrypto інкрементить його на кожен JoinRequest). */
    g_joined  = 0u;
    g_tx_done = 0u;
    devnonce_restore( );
    LmHandlerJoin( ACTIVATION_TYPE_OTAA, true );
    /* Persist ОДРАЗУ: на повернення Join nonce вже інкрементнутий, а кадр
     * ще не обов'язково в ефірі — power-cut/IWDG у pump-вікні коштував би
     * спалений-але-незбережений nonce → LNS-відмова наступного join
     * (code-review). Спалити nonce, якого LNS не бачив, — нешкідливо. */
    devnonce_persist( );
    pump_until( &g_joined, deadline_tick );

    if ( !g_joined ) {
        devnonce_persist( ); /* JoinRequest уже спалив DevNonce — зберегти */
        return 0;
    }

    LmHandlerAppData_t app = {
        .Port       = HELIUM_SOS_FPORT,
        .BufferSize = HELIUM_SOS_WIRE_LEN,
        .Buffer     = (uint8_t *)sos_frame,
    };
    if ( LmHandlerSend( &app, LORAMAC_HANDLER_UNCONFIRMED_MSG, false )
         != LORAMAC_HANDLER_SUCCESS ) {
        devnonce_persist( );
        return 0;
    }
    pump_until( &g_tx_done, deadline_tick );

    devnonce_persist( );
    return g_tx_done ? 1 : 0;
}
