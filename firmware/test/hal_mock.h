/*
 * hal_mock.h — Minimal STM32 HAL stubs for host-based unit testing.
 *
 * This header provides just enough type definitions and function stubs
 * so that firmware logic can be compiled with gcc on x86/x64.
 * Only pure-logic functions are tested — no hardware interaction.
 */
#ifndef HAL_MOCK_H
#define HAL_MOCK_H

#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* ── Basic HAL types ───────────────────────────────────────────────── */
typedef int HAL_StatusTypeDef;
#define HAL_OK   0
#define HAL_ERROR 1

typedef struct { int dummy; } ADC_HandleTypeDef;
typedef struct { int dummy; } TIM_HandleTypeDef;
typedef struct { int dummy; } IWDG_HandleTypeDef;
typedef struct { int dummy; } RNG_HandleTypeDef;
typedef struct { int dummy; } RTC_HandleTypeDef;
typedef struct { int dummy; } SUBGHZ_HandleTypeDef;
typedef struct { int dummy; } UART_HandleTypeDef;
typedef struct { int dummy; } PWR_PVDTypeDef;

typedef struct {
    void* Instance;
    struct {
        int DataType;
        int KeySize;
        uint32_t* pKey;
        int Algorithm;
        uint32_t* pInitVect;
    } Init;
} CRYP_HandleTypeDef;

/* ── Constants ─────────────────────────────────────────────────────── */
#define CRYP_DATATYPE_32B   0
#define CRYP_KEYSIZE_256B   1
#define CRYP_AES_ECB        0
#define CRYP_AES_CBC        1

#define PWR_PVDLEVEL_7              7
#define PWR_PVD_MODE_IT_RISING_FALLING 0
#define PWR_MAINREGULATOR_ON        0
#define PWR_SLEEPENTRY_WFI          0
#define PWR_STOPENTRY_WFI           0

#define GPIO_PIN_0      0x0001
#define LL_ADC_RESOLUTION_12B 12

/* RTC Backup Registers */
#define RTC_BKP_DR0  0
#define RTC_BKP_DR1  1
#define RTC_BKP_DR2  2
#define RTC_BKP_DR3  3
#define RTC_BKP_DR4  4
#define RTC_BKP_DR5  5
#define RTC_BKP_DR6  6
#define RTC_BKP_DR7  7
#define RTC_BKP_DR8  8
#define RTC_BKP_DR9  9
#define RTC_BKP_DR10 10
#define RTC_BKP_DR11 11
#define RTC_BKP_DR12 12
#define RTC_BKP_DR13 13
#define RTC_BKP_DR14 14
#define RTC_BKP_DR15 15

/* ── Stub functions (no-ops) ───────────────────────────────────────── */
static inline int  HAL_Init(void) { return HAL_OK; }
static inline void SystemClock_Config(void) {}
static inline void MX_GPIO_Init(void) {}
static inline void MX_ADC_Init(void) {}
static inline void MX_TIM2_Init(void) {}
static inline void MX_IWDG_Init(void) {}
static inline void MX_RNG_Init(void) {}
static inline void MX_RTC_Init(void) {}
static inline void MX_SUBGHZ_Init(void) {}
static inline void MX_USART1_UART_Init(void) {}
static inline int  HAL_CRYP_Init(CRYP_HandleTypeDef *h) { (void)h; return HAL_OK; }

static inline void HAL_Delay(uint32_t ms) { (void)ms; }
static inline uint32_t HAL_GetTick(void) { return 0; }

static inline void HAL_PWR_ConfigPVD(PWR_PVDTypeDef *c) { (void)c; }
static inline void HAL_PWR_EnablePVD(void) {}
static inline void HAL_PWR_EnableBkUpAccess(void) {}
static inline void HAL_SuspendTick(void) {}
static inline void HAL_ResumeTick(void) {}
static inline void HAL_PWREx_EnterSTOP2Mode(int m) { (void)m; }
static inline void HAL_PWR_EnterSLEEPMode(int a, int b) { (void)a; (void)b; }

static inline uint32_t HAL_RTCEx_BKUPRead(RTC_HandleTypeDef *h, int r) { (void)h; (void)r; return 0; }
static inline void HAL_RTCEx_BKUPWrite(RTC_HandleTypeDef *h, int r, uint32_t v) { (void)h; (void)r; (void)v; }

static inline void HAL_IWDG_Refresh(IWDG_HandleTypeDef *h) { (void)h; }

static inline int HAL_RNG_GenerateRandomNumber(RNG_HandleTypeDef *h, uint32_t *v) { (void)h; *v = 42; return HAL_OK; }

static inline int HAL_ADC_Start(ADC_HandleTypeDef *h) { (void)h; return HAL_OK; }
static inline int HAL_ADC_Stop(ADC_HandleTypeDef *h) { (void)h; return HAL_OK; }
static inline int HAL_ADC_PollForConversion(ADC_HandleTypeDef *h, uint32_t t) { (void)h; (void)t; return HAL_OK; }
static inline uint32_t HAL_ADC_GetValue(ADC_HandleTypeDef *h) { (void)h; return 3000; }
static inline void HAL_ADCEx_Calibration_Start(ADC_HandleTypeDef *h) { (void)h; }
static inline int HAL_ADC_Start_DMA(ADC_HandleTypeDef *h, uint32_t *b, uint32_t l) { (void)h; (void)b; (void)l; return HAL_OK; }
static inline int HAL_ADC_Stop_DMA(ADC_HandleTypeDef *h) { (void)h; return HAL_OK; }

static inline int HAL_TIM_Base_Start(TIM_HandleTypeDef *h) { (void)h; return HAL_OK; }
static inline int HAL_TIM_Base_Stop(TIM_HandleTypeDef *h) { (void)h; return HAL_OK; }

/* AES encrypt/decrypt stubs: just copy data through (no actual crypto) */
static inline int HAL_CRYP_Encrypt(CRYP_HandleTypeDef *h, uint32_t *in, uint16_t sz,
                                    uint32_t *out, uint32_t to) {
    (void)h; (void)to;
    memcpy(out, in, sz * 4);
    return HAL_OK;
}
static inline int HAL_CRYP_Decrypt(CRYP_HandleTypeDef *h, uint32_t *in, uint16_t sz,
                                    uint32_t *out, uint32_t to) {
    (void)h; (void)to;
    memcpy(out, in, sz * 4);
    return HAL_OK;
}

static inline int HAL_UART_Transmit(UART_HandleTypeDef *h, uint8_t *d, uint16_t s, uint32_t t) {
    (void)h; (void)d; (void)s; (void)t; return HAL_OK;
}

/* Temperature macro stub */
#define __LL_ADC_CALC_TEMPERATURE(vref, raw, res) ((int)(25 + ((raw - 1000) / 10)))

/* Radio driver stub */
typedef struct {
    void (*Init)(void*);
    void (*SetChannel)(uint32_t);
    void (*Send)(uint8_t*, uint8_t);
    void (*Rx)(uint32_t);
    void (*Sleep)(void);
} RadioDriver_t;

static inline void radio_init_stub(void* p) { (void)p; }
static inline void radio_set_channel_stub(uint32_t f) { (void)f; }
static inline void radio_send_stub(uint8_t *b, uint8_t s) { (void)b; (void)s; }
static inline void radio_rx_stub(uint32_t t) { (void)t; }
static inline void radio_sleep_stub(void) {}

static RadioDriver_t Radio = {
    .Init = radio_init_stub,
    .SetChannel = radio_set_channel_stub,
    .Send = radio_send_stub,
    .Rx = radio_rx_stub,
    .Sleep = radio_sleep_stub
};

/* System reset stub */
static inline void NVIC_SystemReset(void) {}

/* Memory barrier stubs */
#define __DMB()         ((void)0)
#define __disable_irq() ((void)0)
#define __enable_irq()  ((void)0)

/* Flash stubs for OTA */
static inline void Write_OTA_Contract_To_Flash(uint8_t* d, uint16_t s) { (void)d; (void)s; }

#endif /* HAL_MOCK_H */
