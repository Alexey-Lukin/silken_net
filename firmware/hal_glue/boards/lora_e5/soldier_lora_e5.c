// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * soldier_lora_e5.c — [FW.46 ⚖️ делеговано 2026-10-06] образ Солдата для bench-carrier
 * LoRa-E5 mini (STM32WLE5JC). Рукописний, а не bench-.ioc: армінг WUT мусить стати
 * закоміченою ревʼюйованою функцією (SEC.15), а регенерований .ioc її не дає за
 * побудовою. Підстава, ціна й найслабша ланка присуду — docs/03_01 §12.4; пін-мапа
 * mini — docs/03_01, «Пін-мапа LoRa-E5 mini».
 *
 * Як hal_check-обгортка, цей TU включає soldier/main.c ДОСЛІВНО й докладає тіла
 * MX_*-ініцій у той самий TU (у main.c вони static). Але тут тіла справжні: кожна
 * периферія, якої цикл торкається до першого сну, налаштована, бо заглушка, що лишає
 * хендл порожнім, перетворила б читання POST через SWD на перегони з петлею скидів.
 * Перший зріз — самотест CCM/sym на кремнії (збірка з CCM_SELFTEST, RUNBOOK 2.1–2.2).
 *
 * Межі першого зрізу — свідомі, не дефекти:
 *  · такт — MSI 48 МГц без LSE: клок-дерево вузла з LSE — board-freeze, а армінг WUT —
 *    функція SEC.15, не ця нога;
 *  · RTC — на LSI: календар і backup-регістри DR живуть, точність LSI — відсотки, для
 *    POST байдуже. ⚠️ Джерело RTC живе в backup-домені: перший образ із LSE на тій самій
 *    платі змінить його, і HAL при цьому скидає домен разом із DR0..DR19;
 *  · WUT не армиться: після POST цикл засинає в STOP2 без джерела пробудження, і IWDG
 *    (≈ 32 с) перезапускає плату, якщо option byte IWDG_STOP його не заморозив
 *    (RUNBOOK 1.2). Результат POST переживає скид — його читають SWD-ом у режимі під
 *    скидом, до startup (RUNBOOK 2.1);
 *  · радіо — заглушка: radio.c без radio_conf.h не компілюється (board-freeze), а зрізам
 *    без радіо воно не потрібне. Send віддає OK, решта нічого не робить;
 *  · GPIO не налаштовано: цикл до сну пінів не торкається.
 */
#include "../../../soldier/main.c"
#include <errno.h>

/* ── Такт ────────────────────────────────────────────────────────────────── */
void SystemClock_Config(void)
{
    RCC_OscInitTypeDef osc = {0};
    RCC_ClkInitTypeDef clk = {0};

    // 48 МГц — Range 1 і два такти очікування Flash (RM0461).
    if (HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1) != HAL_OK) Error_Handler();

    osc.OscillatorType      = RCC_OSCILLATORTYPE_MSI | RCC_OSCILLATORTYPE_LSI;
    osc.MSIState            = RCC_MSI_ON;
    osc.MSICalibrationValue = RCC_MSICALIBRATION_DEFAULT;
    osc.MSIClockRange       = RCC_MSIRANGE_11;   // 48 МГц — референсне клок-дерево CubeWL
    osc.LSIState            = RCC_LSI_ON;        // RTC (нижче) і IWDG
    osc.LSIDiv              = RCC_LSI_DIV1;
    osc.PLL.PLLState        = RCC_PLL_NONE;
    if (HAL_RCC_OscConfig(&osc) != HAL_OK) Error_Handler();

    clk.ClockType      = RCC_CLOCKTYPE_HCLK3 | RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK |
                         RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clk.SYSCLKSource   = RCC_SYSCLKSOURCE_MSI;
    clk.AHBCLKDivider  = RCC_SYSCLK_DIV1;
    clk.APB1CLKDivider = RCC_HCLK_DIV1;
    clk.APB2CLKDivider = RCC_HCLK_DIV1;
    clk.AHBCLK3Divider = RCC_SYSCLK_DIV1;
    if (HAL_RCC_ClockConfig(&clk, FLASH_LATENCY_2) != HAL_OK) Error_Handler();
}

/* ── Периферія циклу ─────────────────────────────────────────────────────── */
static void MX_GPIO_Init(void) { /* цикл до сну пінів не торкається */ }

static void MX_ADC_Init(void)
{
    hadc.Instance                   = ADC;
    hadc.Init.ClockPrescaler        = ADC_CLOCK_SYNC_PCLK_DIV4;   // 12 МГц, без ядерного такту
    hadc.Init.Resolution            = ADC_RESOLUTION_12B;
    hadc.Init.DataAlign             = ADC_DATAALIGN_RIGHT;
    hadc.Init.ScanConvMode          = ADC_SCAN_DISABLE;           // лише ранг 1 — Soldier_Adc_Read
    hadc.Init.EOCSelection          = ADC_EOC_SINGLE_CONV;
    hadc.Init.LowPowerAutoWait      = DISABLE;
    hadc.Init.LowPowerAutoPowerOff  = DISABLE;
    hadc.Init.ContinuousConvMode    = DISABLE;
    hadc.Init.NbrOfConversion       = 1;
    hadc.Init.DiscontinuousConvMode = DISABLE;
    hadc.Init.ExternalTrigConv      = ADC_SOFTWARE_START;
    hadc.Init.ExternalTrigConvEdge  = ADC_EXTERNALTRIGCONVEDGE_NONE;
    hadc.Init.DMAContinuousRequests = DISABLE;
    hadc.Init.Overrun               = ADC_OVR_DATA_OVERWRITTEN;
    // 160.5 такту на 12 МГц ≈ 13 мкс — із запасом понад мінімуми вибірки внутрішніх
    // каналів (датчик температури, VREFINT — DS13105).
    hadc.Init.SamplingTimeCommon1   = ADC_SAMPLETIME_160CYCLES_5;
    hadc.Init.SamplingTimeCommon2   = ADC_SAMPLETIME_160CYCLES_5;
    hadc.Init.OversamplingMode      = DISABLE;
    // Тригер — раз на цикл, тобто довше за tIdle паспорта: HAL вимагає тоді LOW.
    hadc.Init.TriggerFrequencyMode  = ADC_TRIGGER_FREQ_LOW;
    if (HAL_ADC_Init(&hadc) != HAL_OK) Error_Handler();
}

static void MX_IWDG_Init(void)
{
    hiwdg.Instance       = IWDG;
    hiwdg.Init.Prescaler = IWDG_PRESCALER_256;
    hiwdg.Init.Window    = IWDG_WINDOW_DISABLE;
    hiwdg.Init.Reload    = 4095;   // LSI 32 кГц / 256 × 4096 ≈ 32.8 с — найдовше вікно
    if (HAL_IWDG_Init(&hiwdg) != HAL_OK) Error_Handler();
}

static void MX_RNG_Init(void)
{
    hrng.Instance                 = RNG;
    hrng.Init.ClockErrorDetection = RNG_CED_ENABLE;
    if (HAL_RNG_Init(&hrng) != HAL_OK) Error_Handler();
}

static void MX_RTC_Init(void)
{
    hrtc.Instance            = RTC;
    hrtc.Init.HourFormat     = RTC_HOURFORMAT_24;
    hrtc.Init.AsynchPrediv   = 127;
    hrtc.Init.SynchPrediv    = 249;                     // LSI 32 кГц / 128 / 250 = 1 Гц
    hrtc.Init.OutPut         = RTC_OUTPUT_DISABLE;
    hrtc.Init.OutPutRemap    = RTC_OUTPUT_REMAP_NONE;
    hrtc.Init.OutPutPolarity = RTC_OUTPUT_POLARITY_HIGH;
    hrtc.Init.OutPutType     = RTC_OUTPUT_TYPE_OPENDRAIN;
    hrtc.Init.OutPutPullUp   = RTC_OUTPUT_PULLUP_NONE;
    hrtc.Init.BinMode        = RTC_BINARY_NONE;         // календар BCD — Wall_Seconds_Now
    hrtc.Init.BinMixBcdU     = RTC_BINARY_MIX_BCDU_0;
    if (HAL_RTC_Init(&hrtc) != HAL_OK) Error_Handler();
}

static void MX_SUBGHZ_Init(void) { /* радіо — заглушка нижче */ }

/* ── MSP: такти периферії, яких main.c не вмикає ─────────────────────────── */
void HAL_MspInit(void)
{
    // «Датчик смерті» (ARCH.21): HAL_PWR_ConfigPVD у main.c налаштовує лише лінію, а без
    // NVIC колбек не стрельне ніколи; у CubeMX це робить згенерований HAL_MspInit.
    HAL_NVIC_SetPriority(PVD_PVM_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(PVD_PVM_IRQn);
}

void HAL_CRYP_MspInit(CRYP_HandleTypeDef *h)
{
    (void)h;
    __HAL_RCC_AES_CLK_ENABLE();   // MX_CRYP_Init (main.c) такту не вмикає
}

void HAL_ADC_MspInit(ADC_HandleTypeDef *h)
{
    (void)h;
    __HAL_RCC_ADC_CLK_ENABLE();
}

void HAL_RNG_MspInit(RNG_HandleTypeDef *h)
{
    (void)h;
    RCC_PeriphCLKInitTypeDef p = {0};
    p.PeriphClockSelection = RCC_PERIPHCLK_RNG;
    p.RngClockSelection    = RCC_RNGCLKSOURCE_MSI;   // скидний PLLQ мовчить: PLL не вмикається
    if (HAL_RCCEx_PeriphCLKConfig(&p) != HAL_OK) Error_Handler();
    __HAL_RCC_RNG_CLK_ENABLE();
}

void HAL_RNG_MspDeInit(RNG_HandleTypeDef *h)
{
    (void)h;
    __HAL_RCC_RNG_CLK_DISABLE();
}

void HAL_RTC_MspInit(RTC_HandleTypeDef *h)
{
    (void)h;
    RCC_PeriphCLKInitTypeDef p = {0};
    p.PeriphClockSelection = RCC_PERIPHCLK_RTC;
    p.RTCClockSelection    = RCC_RTCCLKSOURCE_LSI;
    if (HAL_RCCEx_PeriphCLKConfig(&p) != HAL_OK) Error_Handler();
    __HAL_RCC_RTC_ENABLE();
    __HAL_RCC_RTCAPB_CLK_ENABLE();
}

/* ── Переривання, яких main.c не визначає ────────────────────────────────── */
void SysTick_Handler(void) { HAL_IncTick(); }               // без нього HAL-таймаути не спливають
void PVD_PVM_IRQHandler(void) { HAL_PWREx_PVD_PVM_IRQHandler(); } // → HAL_PWR_PVDCallback (main.c)

/* ── Купа для newlib (mruby): від `end` до стек-резерву лінкер-карти ─────── */
extern char end;
extern char _estack;
extern char __stack_reserve__;
volatile uint32_t g_sbrk_highwater = 0;   // SWD: скільки купи справді взято (фіт у 64 КБ)

void *_sbrk(int incr)
{
    static char *brk;
    if (brk == NULL) brk = &end;
    const char *limit = (const char *)((uintptr_t)&_estack - (uintptr_t)&__stack_reserve__);
    if (brk + incr > limit) { errno = ENOMEM; return (void *)-1; }
    char *prev = brk;
    brk += incr;
    if ((uint32_t)(brk - &end) > g_sbrk_highwater) g_sbrk_highwater = (uint32_t)(brk - &end);
    return prev;
}

/* ── Радіо — заглушка: усі поля Radio_s, бо порожнє поле — виклик за NULL ── */
static void           Stub_Init(RadioEvents_t *e) { (void)e; }
static RadioState_t   Stub_GetStatus(void) { return RF_IDLE; }
static void           Stub_SetModem(RadioModems_t m) { (void)m; }
static void           Stub_SetChannel(uint32_t f) { (void)f; }
static bool           Stub_IsChannelFree(uint32_t f, uint32_t bw, int16_t rssi, uint32_t t)
{ (void)f; (void)bw; (void)rssi; (void)t; return true; }
static uint32_t       Stub_Random(void) { return 0u; }
static void           Stub_SetRxConfig(RadioModems_t m, uint32_t bw, uint32_t dr, uint8_t cr,
                                       uint32_t bwafc, uint16_t pre, uint16_t st, bool fix,
                                       uint8_t len, bool crc, bool fh, uint8_t hp, bool iq,
                                       bool cont)
{ (void)m; (void)bw; (void)dr; (void)cr; (void)bwafc; (void)pre; (void)st; (void)fix;
  (void)len; (void)crc; (void)fh; (void)hp; (void)iq; (void)cont; }
static void           Stub_SetTxConfig(RadioModems_t m, int8_t pw, uint32_t fdev, uint32_t bw,
                                       uint32_t dr, uint8_t cr, uint16_t pre, bool fix,
                                       bool crc, bool fh, uint8_t hp, bool iq, uint32_t to)
{ (void)m; (void)pw; (void)fdev; (void)bw; (void)dr; (void)cr; (void)pre; (void)fix;
  (void)crc; (void)fh; (void)hp; (void)iq; (void)to; }
static bool           Stub_CheckRfFrequency(uint32_t f) { (void)f; return true; }
static uint32_t       Stub_TimeOnAir(RadioModems_t m, uint32_t bw, uint32_t dr, uint8_t cr,
                                     uint16_t pre, bool fix, uint8_t len, bool crc)
{ (void)m; (void)bw; (void)dr; (void)cr; (void)pre; (void)fix; (void)len; (void)crc; return 0u; }
static radio_status_t Stub_Send(uint8_t *b, uint8_t n) { (void)b; (void)n; return RADIO_STATUS_OK; }
static void           Stub_Void(void) { }
static void           Stub_Rx(uint32_t t) { (void)t; }
static void           Stub_SetTxContinuousWave(uint32_t f, int8_t p, uint16_t t) { (void)f; (void)p; (void)t; }
static int16_t        Stub_Rssi(RadioModems_t m) { (void)m; return 0; }
static void           Stub_Write(uint16_t a, uint8_t d) { (void)a; (void)d; }
static uint8_t        Stub_Read(uint16_t a) { (void)a; return 0u; }
static void           Stub_WriteRegisters(uint16_t a, uint8_t *b, uint8_t n) { (void)a; (void)b; (void)n; }
static void           Stub_ReadRegisters(uint16_t a, uint8_t *b, uint8_t n) { (void)a; (void)b; (void)n; }
static void           Stub_SetMaxPayloadLength(RadioModems_t m, uint8_t n) { (void)m; (void)n; }
static void           Stub_SetPublicNetwork(bool e) { (void)e; }
static uint32_t       Stub_GetWakeupTime(void) { return 0u; }
static void           Stub_SetRxDutyCycle(uint32_t rx, uint32_t sl) { (void)rx; (void)sl; }
static void           Stub_TxCw(int8_t p) { (void)p; }
static int32_t        Stub_RxGeneric(GenericModems_t m, RxConfigGeneric_t *c, uint32_t cont, uint32_t st)
{ (void)m; (void)c; (void)cont; (void)st; return 0; }
static int32_t        Stub_TxGeneric(GenericModems_t m, TxConfigGeneric_t *c, int8_t p, uint32_t t)
{ (void)m; (void)c; (void)p; (void)t; return 0; }
static int32_t        Stub_TxLong(uint16_t n, uint32_t t, void (*cb)(uint8_t **, uint8_t))
{ (void)n; (void)t; (void)cb; return 0; }
static int32_t        Stub_RxLong(uint8_t b, uint32_t t, void (*cb)(uint8_t *, uint8_t))
{ (void)b; (void)t; (void)cb; return 0; }
static radio_status_t Stub_LrFhssSetCfg(const radio_lr_fhss_cfg_params_t *c) { (void)c; return RADIO_STATUS_OK; }
static radio_status_t Stub_LrFhssToa(const radio_lr_fhss_time_on_air_params_t *p, uint32_t *ms)
{ (void)p; *ms = 0u; return RADIO_STATUS_OK; }

const struct Radio_s Radio = {
    .Init = Stub_Init, .GetStatus = Stub_GetStatus, .SetModem = Stub_SetModem,
    .SetChannel = Stub_SetChannel, .IsChannelFree = Stub_IsChannelFree, .Random = Stub_Random,
    .SetRxConfig = Stub_SetRxConfig, .SetTxConfig = Stub_SetTxConfig,
    .CheckRfFrequency = Stub_CheckRfFrequency, .TimeOnAir = Stub_TimeOnAir, .Send = Stub_Send,
    .Sleep = Stub_Void, .Standby = Stub_Void, .Rx = Stub_Rx, .StartCad = Stub_Void,
    .SetTxContinuousWave = Stub_SetTxContinuousWave, .Rssi = Stub_Rssi, .Write = Stub_Write,
    .Read = Stub_Read, .WriteRegisters = Stub_WriteRegisters, .ReadRegisters = Stub_ReadRegisters,
    .SetMaxPayloadLength = Stub_SetMaxPayloadLength, .SetPublicNetwork = Stub_SetPublicNetwork,
    .GetWakeupTime = Stub_GetWakeupTime, .IrqProcess = Stub_Void, .RxBoosted = Stub_Rx,
    .SetRxDutyCycle = Stub_SetRxDutyCycle, .TxPrbs = Stub_Void, .TxCw = Stub_TxCw,
    .RadioSetRxGenericConfig = Stub_RxGeneric, .RadioSetTxGenericConfig = Stub_TxGeneric,
    .TransmitLongPacket = Stub_TxLong, .ReceiveLongPacket = Stub_RxLong,
    .LrFhssSetCfg = Stub_LrFhssSetCfg, .LrFhssGetTimeOnAirInMs = Stub_LrFhssToa,
};
