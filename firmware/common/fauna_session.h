/*
 * fauna_session.h — [ARCH.40] монолітна fauna-сесія: Welford-акумулятор +
 * сесійний драйвер (One-Home, freeze-contract).
 *
 * Кенозис сесії: 5 с слухання світанку = 156 послідовних 32 мс кадрів
 * (FAUNA_SESSION_FRAMES × Compute_LogMel → 40 mel-ознак), агрегованих у
 * running mean+M2 (Welford — чисельно стабільний на довгих сумах, на відміну
 * від naive sum/sum²). STOP2 wipe'ає SRAM2 → проміжна статистика НЕ ПЕРЕЖИВЕ
 * сну, а всі 20 RTC backup-регістрів зайняті (03_01 §2) — тому сесія
 * МОНОЛІТНА: Fauna_Run_Session синхронна і завершена в одному виклику,
 * STOP2 фізично не може втрутитись, доки вона не повернулась. Майбутній
 * call-site у main.c (fauna-pivot, FW.4) зобов'язаний кликати її ДО Фази 5
 * (кенозису сну); вхідний гейт — Fauna_Should_Sample (FW.42 vcap-політика).
 *
 * Згортка mean/var → fauna_activity_index (0–63) тут СВІДОМО відсутня:
 * формула — калібрувальне рішення після приземлення моделі й польових
 * ground-truth (03_03 §10.2/§10.4); передчасний хардкод став би drift-якорем.
 *
 * Дзеркало тестів: firmware/test/test_fauna_session.c (зокрема named-тест
 * ARCH.40 — test_fauna_sampling_no_stop2_in_session).
 * Канон: 03_03 §10.2 (моноліт) + §10.3 (енергія/FW.42) + 00_07 ARCH.40.
 */
#ifndef SILKEN_FAUNA_SESSION_H
#define SILKEN_FAUNA_SESSION_H

#include <stdint.h>

#include "logmel_contract.h" /* LOGMEL_N_MELS — розмірність feature-вектора */

#define FAUNA_SESSION_FRAMES 156u /* 5 с / 32 мс (03_03 §10.2) */

/* Welford running-статистика по кожному mel-біну. Живе в RAM рівно одну
 * сесію (~324 Б: 2 × 40 float + n) — жодної персистенції між awake. */
typedef struct {
    float    mean[LOGMEL_N_MELS];
    float    m2[LOGMEL_N_MELS];   /* Σ(x−mean)² — var = m2/n */
    uint16_t n;
} FaunaWelford;

static inline void Fauna_Welford_Init(FaunaWelford *w)
{
    for (uint16_t i = 0; i < LOGMEL_N_MELS; i++) {
        w->mean[i] = 0.0f;
        w->m2[i]   = 0.0f;
    }
    w->n = 0;
}

static inline void Fauna_Welford_Update(FaunaWelford *w,
                                        const float feat[LOGMEL_N_MELS])
{
    w->n++;
    for (uint16_t i = 0; i < LOGMEL_N_MELS; i++) {
        float delta  = feat[i] - w->mean[i];
        w->mean[i]  += delta / (float)w->n;
        float delta2 = feat[i] - w->mean[i];
        w->m2[i]    += delta * delta2;
    }
}

/* Популяційна дисперсія біна (0, поки кадрів нема). */
static inline float Fauna_Welford_Var(const FaunaWelford *w, uint16_t bin)
{
    if (w->n == 0) return 0.0f;
    return w->m2[bin] / (float)w->n;
}

/* Постачальник кадру: на девайсі = TIM2+DMA запис 512 семплів +
 * Compute_LogMel; повертає 0 = кадр не вдався (DMA/ADC збій) → сесія
 * чесно переривається. ctx — стан постачальника (на хості — мок). */
typedef uint8_t (*FaunaFrameFn)(void *ctx, float mel_out[LOGMEL_N_MELS]);

/* Монолітний прогін сесії (ARCH.40): рівно FAUNA_SESSION_FRAMES кадрів
 * один за одним у МЕЖАХ ОДНОГО виклику; повертає кількість оброблених
 * (== FAUNA_SESSION_FRAMES при успіху; менше = перервано на збої кадру —
 * акумулятор валідний для n оброблених, рішення «слати чи ні» за call-site). */
static inline uint16_t Fauna_Run_Session(FaunaFrameFn next_mel, void *ctx,
                                         FaunaWelford *w)
{
    float frame[LOGMEL_N_MELS];

    Fauna_Welford_Init(w);
    for (uint16_t f = 0; f < FAUNA_SESSION_FRAMES; f++) {
        if (!next_mel(ctx, frame)) return f;
        Fauna_Welford_Update(w, frame);
    }
    return FAUNA_SESSION_FRAMES;
}

#endif /* SILKEN_FAUNA_SESSION_H */
