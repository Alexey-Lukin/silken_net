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
#define HAL_TIMEOUT 3

typedef struct { int dummy; } ADC_HandleTypeDef;
typedef struct { int dummy; } TIM_HandleTypeDef;
typedef struct { int dummy; } IWDG_HandleTypeDef;
typedef struct {
    void* Instance;
    int dummy;
} RNG_HandleTypeDef;
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
        uint32_t* pInitVect;  /* ECB/CBC IV. Для CCM НЕ використовується — WL бере нонс із B0. */
        /* [FW.2 / ARCH.42] CCM-поля — ДЗЕРКАЛО справжнього WL CRYP_ConfigTypeDef
         * (stm32wlxx_hal_cryp.h): B0 = форматований 16B-блок (flags‖nonce‖Q,
         * будує lora_ccm.h::Build_CCM_B0 — мок його ВАЛІДУЄ, не пропускає),
         * Header/HeaderSize = AAD, width-unit'и = семантика Size-параметрів.
         * WL-флоу двофазний: HAL_CRYP_Encrypt/Decrypt (payload) →
         * HAL_CRYPEx_AESCCM_GenerateAuthTAG (тег окремо); AESCCM_Encrypt/
         * Decrypt як у F4/F7/L4 у WL-HAL НЕ ІСНУЮТЬ. */
        uint32_t* B0;
        uint32_t* Header;
        uint32_t HeaderSize;   /* одиниця = HeaderWidthUnit */
        uint32_t DataWidthUnit;
        uint32_t HeaderWidthUnit;
    } Init;
} CRYP_HandleTypeDef;

/* ── Constants ─────────────────────────────────────────────────────── */
#define RNG             ((void*)0x58001000UL) /* RNG peripheral base (mock) */
#define CRYP_DATATYPE_32B   0
#define CRYP_DATATYPE_8B    2   /* байтопотік без word-swap — CCM-контекст (lora_ccm.h) */
#define CRYP_KEYSIZE_256B   1   /* CoAP-канал AES-256 (Queen↔Rails) */
#define CRYP_KEYSIZE_128B   2   /* LoRa-канал AES-128 (Soldier↔Queen) — post-ARCH.42 Variant B */
#define CRYP_AES_ECB        0
#define CRYP_AES_CBC        1
#define CRYP_AES_CCM        2   /* FW.2 target: AES-128-CCM з 8-byte MIC (post-ARCH.42) */
#define CRYP_DATAWIDTHUNIT_WORD    0x00000000U
#define CRYP_DATAWIDTHUNIT_BYTE    0x00000001U
#define CRYP_HEADERWIDTHUNIT_WORD  0x00000000U
#define CRYP_HEADERWIDTHUNIT_BYTE  0x00000001U

#define PWR_PVDLEVEL_7              7
#define PWR_PVD_MODE_IT_RISING_FALLING 0
#define PWR_MAINREGULATOR_ON        0
#define PWR_SLEEPENTRY_WFI          0
#define PWR_STOPENTRY_WFI           0

#define GPIO_PIN_0      0x0001
#define LL_ADC_RESOLUTION_12B 12

/* RTC Backup Registers (STM32WLE5 supports DR0-DR19, 20 registers total) */
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
/* [FW.6] Lorenz state persistence registers */
#define RTC_BKP_DR16 16
#define RTC_BKP_DR17 17
#define RTC_BKP_DR18 18
#define RTC_BKP_DR19 19

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
static inline int  HAL_RNG_Init(RNG_HandleTypeDef *h) { (void)h; return HAL_OK; }
static inline int  HAL_RNG_DeInit(RNG_HandleTypeDef *h) { (void)h; return HAL_OK; }

/* RCC clock control stubs (for peripheral power management) */
#define __HAL_RCC_CRYP_CLK_DISABLE() ((void)0)
#define __HAL_RCC_CRYP_CLK_ENABLE()  ((void)0)
/* RCC CRYP peripheral reset stubs (for FW.16 ECB restore recovery) */
#define __HAL_RCC_CRYP_FORCE_RESET()   ((void)0)
#define __HAL_RCC_CRYP_RELEASE_RESET() ((void)0)

static inline void HAL_Delay(uint32_t ms) { (void)ms; }
static inline uint32_t HAL_GetTick(void) { return 0; }

static inline void HAL_PWR_ConfigPVD(PWR_PVDTypeDef *c) { (void)c; }
static inline void HAL_PWR_EnablePVD(void) {}
static inline void HAL_PWR_EnableBkUpAccess(void) {}
static inline void HAL_SuspendTick(void) {}
static inline void HAL_ResumeTick(void) {}
static inline void HAL_PWREx_EnterSTOP2Mode(int m) { (void)m; }
static inline void HAL_PWR_EnterSLEEPMode(int a, int b) { (void)a; (void)b; }

/* [FW.6] Functional RTC Backup Register mock — stores/retrieves values for testing state persistence */
#define RTC_BKP_REGISTER_COUNT 20
static uint32_t _rtc_bkp_regs[RTC_BKP_REGISTER_COUNT] = {0};

static inline uint32_t HAL_RTCEx_BKUPRead(RTC_HandleTypeDef *h, int r) {
    (void)h;
    if (r >= 0 && r < RTC_BKP_REGISTER_COUNT) return _rtc_bkp_regs[r];
    return 0;
}
static inline void HAL_RTCEx_BKUPWrite(RTC_HandleTypeDef *h, int r, uint32_t v) {
    (void)h;
    if (r >= 0 && r < RTC_BKP_REGISTER_COUNT) _rtc_bkp_regs[r] = v;
}
static inline void _rtc_bkp_reset_all(void) {
    memset(_rtc_bkp_regs, 0, sizeof(_rtc_bkp_regs));
}

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

/* ── [FW.2] AES-128-CCM мок: WL-true ДВОФАЗНИЙ флоу через OpenSSL EVP ──
 *
 * Дзеркалить справжній STM32WLxx HAL (НЕ F4/F7-стиль AESCCM_Encrypt —
 * його у WL нема): payload-фаза HAL_CRYP_Encrypt/Decrypt(CCM) + окрема
 * тег-фаза HAL_CRYPEx_AESCCM_GenerateAuthTAG. На decrypt тег НЕ
 * звіряється моком — як і кремній, він лише віддає ОБЧИСЛЕНИЙ тег, а
 * порівняння (константним часом) робить викликач (Fw2_Ccm_Tag_Equal).
 *
 * B0 тут ВАЛІДУЄТЬСЯ проти lora_ccm.h::Build_CCM_B0 (flags 0x5A, Q =
 * Size) — старий мок його пропускав і TODO висів до bench; тепер
 * байт-ряд B0 доведений host-тестами, bench лишає тільки silicon.
 *
 * Decrypt-емуляція без сирої AES: CTR-симетрія CCM — EVP-*encrypt*
 * шифротексту тим самим нонсом повертає plaintext (C=P⊕S ⇒ P=C⊕S);
 * тег того проходу хибний (рахований над ct-як-pt), тому другий
 * encrypt-прохід над відновленим pt дає чесний tag(pt) для тег-фази.
 *
 * Enable per-test: #define HAL_MOCK_CCM_ENABLED ДО включення hal_mock.h;
 * бінарник лінкує -lcrypto. */
#ifdef HAL_MOCK_CCM_ENABLED
#include <openssl/evp.h>

#define CCM_MOCK_NONCE_LEN  12
#define CCM_MOCK_TAG_LEN    8
#define CCM_MOCK_MAX_PAYLOAD 64

static uint8_t _ccm_mock_tag[CCM_MOCK_TAG_LEN];
static int     _ccm_mock_tag_valid = 0;

/* B0-привратник: flags/Q мусять збігатися з Build_CCM_B0, нонс — назовні. */
static inline int _ccm_mock_parse_b0(const CRYP_HandleTypeDef *h, uint16_t size_bytes,
                                     uint8_t nonce_out[CCM_MOCK_NONCE_LEN]) {
    const uint8_t *b0 = (const uint8_t *)h->Init.B0;
    if (!b0) return 0;
    if (b0[0] != 0x5Au) return 0;  /* FW2_CCM_B0_FLAGS: Adata=1, t=8, q=3 */
    if (b0[13] != 0x00u) return 0;
    if ((uint16_t)(((uint16_t)b0[14] << 8) | b0[15]) != size_bytes) return 0;
    memcpy(nonce_out, &b0[1], CCM_MOCK_NONCE_LEN);
    return 1;
}

/* Один EVP-CCM-encrypt прохід: out=шифропотік(in), tag_out=tag(in). */
static inline int _ccm_mock_evp_pass(const CRYP_HandleTypeDef *h,
                                     const uint8_t *nonce,
                                     const uint8_t *in, uint16_t size_bytes,
                                     uint8_t *out, uint8_t tag_out[CCM_MOCK_TAG_LEN]) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return 0;
    int ok = 1, len = 0, final_len = 0;
    ok &= EVP_EncryptInit_ex(ctx, EVP_aes_128_ccm(), NULL, NULL, NULL);
    ok &= EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_CCM_SET_IVLEN, CCM_MOCK_NONCE_LEN, NULL);
    ok &= EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_CCM_SET_TAG, CCM_MOCK_TAG_LEN, NULL);
    ok &= EVP_EncryptInit_ex(ctx, NULL, NULL,
                             (const unsigned char *)h->Init.pKey, nonce);
    ok &= EVP_EncryptUpdate(ctx, NULL, &len, NULL, (int)size_bytes);
    if (h->Init.Header && h->Init.HeaderSize > 0) {
        ok &= EVP_EncryptUpdate(ctx, NULL, &len,
                                (const unsigned char *)h->Init.Header,
                                (int)h->Init.HeaderSize);
    }
    ok &= EVP_EncryptUpdate(ctx, out, &len, in, (int)size_bytes);
    ok &= EVP_EncryptFinal_ex(ctx, out + len, &final_len);
    ok &= EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_CCM_GET_TAG, CCM_MOCK_TAG_LEN, tag_out);
    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

/* Payload-фаза (спільна для encrypt/decrypt). Size — у БАЙТАХ:
 * контракт lora_ccm.h вимагає DataWidthUnit=BYTE + HeaderWidthUnit=BYTE
 * (мок фейлить інакше — ловить неправильно зібраний Init до bench). */
static inline int _ccm_mock_payload(CRYP_HandleTypeDef *h, int encrypt,
                                    uint32_t *in, uint16_t size_bytes, uint32_t *out) {
    uint8_t nonce[CCM_MOCK_NONCE_LEN];
    /* Будь-яка спроба payload-фази інвалідовує стешований тег ДО привратників —
     * інакше провалений виклик лишав би живим тег ПОПЕРЕДНЬОЇ операції і
     * GenerateAuthTAG віддавав би сталу істину (кремній так не милосердний). */
    _ccm_mock_tag_valid = 0;
    if (!h || !in || !out) return HAL_ERROR;
    if (h->Init.KeySize != CRYP_KEYSIZE_128B) return HAL_ERROR;
    if (h->Init.DataWidthUnit != CRYP_DATAWIDTHUNIT_BYTE) return HAL_ERROR;
    if (h->Init.HeaderWidthUnit != CRYP_HEADERWIDTHUNIT_BYTE) return HAL_ERROR;
    if (size_bytes > CCM_MOCK_MAX_PAYLOAD) return HAL_ERROR;
    if (!_ccm_mock_parse_b0(h, size_bytes, nonce)) return HAL_ERROR;

    if (encrypt) {
        if (!_ccm_mock_evp_pass(h, nonce, (const uint8_t *)in, size_bytes,
                                (uint8_t *)out, _ccm_mock_tag)) return HAL_ERROR;
    } else {
        uint8_t scratch_tag[CCM_MOCK_TAG_LEN];
        uint8_t ct_scratch[CCM_MOCK_MAX_PAYLOAD];
        /* CTR-симетрія: encrypt(ct) → pt; тег цього проходу — сміття. */
        if (!_ccm_mock_evp_pass(h, nonce, (const uint8_t *)in, size_bytes,
                                (uint8_t *)out, scratch_tag)) return HAL_ERROR;
        /* Другий прохід над відновленим pt → чесний tag(pt) для тег-фази. */
        if (!_ccm_mock_evp_pass(h, nonce, (const uint8_t *)out, size_bytes,
                                ct_scratch, _ccm_mock_tag)) return HAL_ERROR;
    }
    _ccm_mock_tag_valid = 1;
    return HAL_OK;
}

/* Тег-фаза. Пише CCM_MOCK_TAG_LEN=8 байт (MIC). Викликач тримає
 * uint32_t tag_w[4] (16B): справжній WL HAL пише повний 16B-блок,
 * контракт lora_ccm.h — «перші 8 байт = MIC» — валідний обабіч.
 * const у сигнатурі — wart справжнього HAL-прототипу (він теж пише). */
static inline int HAL_CRYPEx_AESCCM_GenerateAuthTAG(CRYP_HandleTypeDef *h,
                                                    const uint32_t *AuthTag,
                                                    uint32_t Timeout) {
    (void)Timeout;
    if (!h || !AuthTag) return HAL_ERROR;
    if (!_ccm_mock_tag_valid) return HAL_ERROR; /* тег без payload-фази = помилка порядку */
    memcpy((void *)AuthTag, _ccm_mock_tag, CCM_MOCK_TAG_LEN);
    return HAL_OK;
}
#endif /* HAL_MOCK_CCM_ENABLED */

/* AES encrypt/decrypt stubs: just copy data through (no actual crypto).
 * [ARCH.42] Гардовано: test_sym_selftest визначає HAL_MOCK_SYM_ENABLED
 * і отримує OpenSSL-backed реалізацію (нижче) — байтопотокова
 * семантика = контракт бекенду. CCM-гілка (якщо ввімкнена) має
 * пріоритет за Algorithm — обидва варіанти диспетчеризують у неї. */
#ifndef HAL_MOCK_SYM_ENABLED
static inline int HAL_CRYP_Encrypt(CRYP_HandleTypeDef *h, uint32_t *in, uint16_t sz,
                                    uint32_t *out, uint32_t to) {
    (void)to;
#ifdef HAL_MOCK_CCM_ENABLED
    if (h->Init.Algorithm == CRYP_AES_CCM) return _ccm_mock_payload(h, 1, in, sz, out);
#endif
    (void)h;
    memcpy(out, in, sz * 4);
    return HAL_OK;
}
static inline int HAL_CRYP_Decrypt(CRYP_HandleTypeDef *h, uint32_t *in, uint16_t sz,
                                    uint32_t *out, uint32_t to) {
    (void)to;
#ifdef HAL_MOCK_CCM_ENABLED
    if (h->Init.Algorithm == CRYP_AES_CCM) return _ccm_mock_payload(h, 0, in, sz, out);
#endif
    (void)h;
    memcpy(out, in, sz * 4);
    return HAL_OK;
}
#endif /* !HAL_MOCK_SYM_ENABLED */

static inline int HAL_UART_Transmit(UART_HandleTypeDef *h, uint8_t *d, uint16_t s, uint32_t t) {
    (void)h; (void)d; (void)s; (void)t; return HAL_OK;
}
static inline int HAL_UART_Receive(UART_HandleTypeDef *h, uint8_t *d, uint16_t s, uint32_t t) {
    (void)h; (void)d; (void)s; (void)t; return HAL_TIMEOUT;
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

/* NVIC interrupt control stubs (for FW.11 race condition fix) */
typedef enum { EXTI0_IRQn = 6 } IRQn_Type;
static inline void HAL_NVIC_DisableIRQ(IRQn_Type n) { (void)n; }
static inline void HAL_NVIC_EnableIRQ(IRQn_Type n) { (void)n; }

/* System reset stub */
static inline void NVIC_SystemReset(void) {}

/* Memory barrier stubs */
#define __DMB()         ((void)0)
#define __disable_irq() ((void)0)
#define __enable_irq()  ((void)0)

/* Flash stubs for OTA */
static inline void Write_OTA_Contract_To_Flash(const uint8_t* d, uint16_t s) { (void)d; (void)s; }

/* ── [FW.1 + ARCH.42] Flash Key Region Mock ─────────────────────────── */
/*
 * Simulates the Protected Flash Sector at FLASH_KEY_ADDR (0x0803E000).
 * Post-ARCH.42 layout (LoRa AES-128, 16 bytes):
 *   [magic:4][key[0]:4][key[1]:4][key[2]:4][key[3]:4] = 5 × uint32_t = 20 bytes
 * Pre-ARCH.42 layout was 9 × uint32_t = 36 bytes (AES-256).
 *
 * Mock allocates 9 words for backward-compat (test fixtures provide uint32_t[8]
 * keys, але Load_AES_Key читає лише перші FLASH_KEY_WORDS=4 слова).
 *
 * Tests set _mock_flash_key_region[] directly, then call Load_AES_Key()
 * which reads from (const uint32_t *)FLASH_KEY_ADDR.
 * The FLASH_KEY_ADDR macro is redefined below to point to this array.
 */
#define MOCK_FLASH_KEY_REGION_WORDS  9  /* 1 magic + up to 8 key words (Load_AES_Key reads first 4) */
static uint32_t _mock_flash_key_region[MOCK_FLASH_KEY_REGION_WORDS] = {0};

static inline void _mock_flash_key_reset(void) {
    memset(_mock_flash_key_region, 0xFF, sizeof(_mock_flash_key_region));
}

/* Write a valid provisioned key into the mock Flash region */
static inline void _mock_flash_key_provision(uint32_t magic, const uint32_t key[8]) {
    _mock_flash_key_region[0] = magic;
    for (int i = 0; i < 8; i++) {
        _mock_flash_key_region[1 + i] = key[i];
    }
}

/* Error_Handler mock — trackable for tests */
static int _mock_error_handler_called = 0;
static inline void _mock_error_handler_reset(void) { _mock_error_handler_called = 0; }

/* ── [SEC.11 / FW.30] Flash Lorenz Seed Region Mock ───────────────── */
/*
 * Simulates the Protected Flash Sector at FLASH_SEED_ADDR (FLASH_KEY_ADDR + 20, post-ARCH.42 AES-128).
 * Layout: [magic:4][seed[0]:4][seed[1]:4]...[seed[7]:4] = 9 × uint32_t = 36 bytes.
 */
#define MOCK_FLASH_SEED_REGION_WORDS 9  /* 1 magic + 8 seed words */
static uint32_t _mock_flash_seed_region[MOCK_FLASH_SEED_REGION_WORDS] = {0};

static inline void _mock_flash_seed_reset(void) {
    memset(_mock_flash_seed_region, 0xFF, sizeof(_mock_flash_seed_region));
}

static inline void _mock_flash_seed_provision(uint32_t magic, const uint32_t seed[8]) {
    _mock_flash_seed_region[0] = magic;
    for (int i = 0; i < 8; i++) {
        _mock_flash_seed_region[1 + i] = seed[i];
    }
}

/* ── [SEC.11 / FW.30] RTC Date/Time Mock for cold-start derivation ── */
typedef struct { uint8_t Hours; uint8_t Minutes; uint8_t Seconds; } RTC_TimeTypeDef;
typedef struct { uint8_t Date; uint8_t Month; uint8_t Year; /* years since 2000 */ } RTC_DateTypeDef;
#define RTC_FORMAT_BIN 0

/* Mock date: 2026-05-02 → Year=26, Month=5, Date=2 */
static uint8_t _mock_rtc_year  = 26;
static uint8_t _mock_rtc_month = 5;
static uint8_t _mock_rtc_date  = 2;

static inline int HAL_RTC_GetTime(RTC_HandleTypeDef *h, RTC_TimeTypeDef *t, int fmt) {
    (void)h; (void)fmt;
    t->Hours = 12; t->Minutes = 0; t->Seconds = 0;
    return HAL_OK;
}
static inline int HAL_RTC_GetDate(RTC_HandleTypeDef *h, RTC_DateTypeDef *d, int fmt) {
    (void)h; (void)fmt;
    d->Year = _mock_rtc_year; d->Month = _mock_rtc_month; d->Date = _mock_rtc_date;
    return HAL_OK;
}

/* ── [ARCH.42] OpenSSL-backed ECB/CBC mock ──────────────────────
 * Дзеркало CCM-mock'а для ТРАНЗИТНИХ шляхів ARCH.42: рахує справжній AES
 * через EVP з БАЙТОПОТОКОВОЮ семантикою (sz — у 32-бітних словах, як у
 * STM32 HAL; bytes = sz*4). Це КОНТРАКТ, який бекенд (Ruby OpenSSL)
 * очікує від кремнію — sym_selftest.h ганяє через нього NIST-вектори,
 * верифікуючи власну логіку + вектори до bench-дня.
 * Enable per-test: #define HAL_MOCK_SYM_ENABLED BEFORE including hal_mock.h
 * (вимикає passthrough-пару вище). Потрібен libcrypto (як CCM-mock). */
#ifdef HAL_MOCK_SYM_ENABLED
#include <openssl/evp.h>

static inline const EVP_CIPHER *_sym_mock_cipher(const CRYP_HandleTypeDef *h) {
    if (h->Init.Algorithm == CRYP_AES_ECB && h->Init.KeySize == CRYP_KEYSIZE_128B)
        return EVP_aes_128_ecb();
    if (h->Init.Algorithm == CRYP_AES_CBC && h->Init.KeySize == CRYP_KEYSIZE_256B)
        return EVP_aes_256_cbc();
    if (h->Init.Algorithm == CRYP_AES_CBC && h->Init.KeySize == CRYP_KEYSIZE_128B)
        return EVP_aes_128_cbc();
    return NULL;
}

static inline int _sym_mock_run(CRYP_HandleTypeDef *h, int encrypt,
                                uint32_t *in, uint16_t sz_words, uint32_t *out) {
    const EVP_CIPHER *cipher = _sym_mock_cipher(h);
    if (!cipher || !in || !out) return HAL_ERROR;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return HAL_ERROR;

    int ok = EVP_CipherInit_ex(ctx, cipher, NULL,
                               (const unsigned char *)h->Init.pKey,
                               (const unsigned char *)h->Init.pInitVect,
                               encrypt);
    EVP_CIPHER_CTX_set_padding(ctx, 0);  /* firmware зеро-паддить сам */

    int len = 0, final_len = 0;
    ok &= EVP_CipherUpdate(ctx, (unsigned char *)out, &len,
                           (const unsigned char *)in, (int)sz_words * 4);
    ok &= EVP_CipherFinal_ex(ctx, (unsigned char *)out + len, &final_len);
    EVP_CIPHER_CTX_free(ctx);
    return ok ? HAL_OK : HAL_ERROR;
}

static inline int HAL_CRYP_Encrypt(CRYP_HandleTypeDef *h, uint32_t *in, uint16_t sz,
                                    uint32_t *out, uint32_t to) {
    (void)to;
#ifdef HAL_MOCK_CCM_ENABLED
    if (h->Init.Algorithm == CRYP_AES_CCM) return _ccm_mock_payload(h, 1, in, sz, out);
#endif
    return _sym_mock_run(h, 1, in, sz, out);
}
static inline int HAL_CRYP_Decrypt(CRYP_HandleTypeDef *h, uint32_t *in, uint16_t sz,
                                    uint32_t *out, uint32_t to) {
    (void)to;
#ifdef HAL_MOCK_CCM_ENABLED
    if (h->Init.Algorithm == CRYP_AES_CCM) return _ccm_mock_payload(h, 0, in, sz, out);
#endif
    return _sym_mock_run(h, 0, in, sz, out);
}
#endif /* HAL_MOCK_SYM_ENABLED */

#endif /* HAL_MOCK_H */
