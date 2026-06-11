/*
 * soldier_hal_check.c — [FW.46] HAL compile-lane: ПЕРШИЙ справжній компайл
 * soldier/main.c проти vendored stm32wlxx-hal-driver (ARM, soft-float).
 *
 * main.c — CubeMX merge-фрагмент: 8 init-функцій оголошені static БЕЗ тіл
 * (тіла згенерує .ioc на HAL-фазі, 👤 board-freeze). Цей TU включає main.c
 * ДОСЛІВНО і докладає заглушки в той самий translation unit — компайл-гейт
 * чесний (всі виклики/типи/HAL-API перевіряються), main.c незайманий.
 *
 * Заглушки порожні СВІДОМО: клок-дерево, пін-мапа, ADC-канали, LSE — фізика
 * board-freeze; вигадані тіла стали б drift-джерелом проти майбутнього .ioc.
 * Канон: docs/03_01 §12.4 · трекер: 00_07 FW.46.
 */
#include "../soldier/main.c"

/* ── CubeMX-заглушки (👤 .ioc згенерує справжні) ───────────────────────── */
void SystemClock_Config(void) { /* 👤 клок-дерево (FW.49 LSE — bench) */ }
static void MX_GPIO_Init(void)   { /* 👤 пін-мапа = board-freeze */ }
static void MX_ADC_Init(void)    { /* 👤 канал/розводка дільника (FW.50) */ }
static void MX_TIM2_Init(void)   { /* 👤 метроном DMA 16 кГц від клок-дерева */ }
static void MX_IWDG_Init(void)   { /* 👤 вікно IWDG узгоджене зі STOP2 (SEC.15) */ }
static void MX_RNG_Init(void)    { /* 👤 */ }
static void MX_RTC_Init(void)    { /* 👤 календар/WUT (FW.49 — bench) */ }
static void MX_SUBGHZ_Init(void) { /* 👤 */ }
