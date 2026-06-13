/*
 * test_audio_model.c — host-тест згенерованої INT8 акустичної моделі (FW.4).
 *
 * Доводить, що `Run_Inference` зі `silken_net_audio_model.h` відтворює
 * silken_ml integer-reference (golden-вектори): клас — точно (саме він керує
 * `ml_event_id`), а softmax-впевненість — у межах tol (gemmlowp last-bit +
 * float32 вхідний quant). Golden генерує `silken_ml.export.emit_golden`.
 *
 * Збірка (host): make -C firmware/test audio_model
 */
#include <math.h>
#include <stdio.h>

#include "../soldier/silken_net_audio_model.h"
#include "silken_net_audio_model_golden.h"

/* Очікувана впевненість із golden-логітів — той самий softmax, що в Run_Inference. */
static double expected_confidence(const int32_t *lg)
{
    int32_t best = lg[0];
    double sum = 0.0;
    for (int k = 1; k < SNAM_GOLDEN_N_CLASSES; k++)
        if (lg[k] > best) best = lg[k];
    for (int k = 0; k < SNAM_GOLDEN_N_CLASSES; k++)
        sum += exp(((double)lg[k] - (double)best) * (double)SNAM_OUT_SCALE);
    return 1.0 / sum;
}

/* [03_03 §5.1] Дзеркало Phase-1.5 рішення: клас → дія. Поріг впевненості — окремо
 * (FW.18, §8 #8); тут ізолюємо саме маппінг клас→дія для smoke #6/#7. */
static void decide(uint8_t cls, uint16_t *acoustic_events, int *emergency_tx)
{
    if (cls == ML_CLASS_CAVITATION)
        (*acoustic_events)++;
    else if (cls == ML_CLASS_CHAINSAW)
        *emergency_tx = 1;
}

int main(void)
{
    int fails = 0;

    for (int g = 0; g < SNAM_GOLDEN_COUNT; g++) {
        float confidence = -1.0f;
        uint8_t cls = Run_Inference(SNAM_GOLDEN[g].input, &confidence);

        if (cls != SNAM_GOLDEN[g].cls) {
            printf("  [%d] class %u != expected %u\n", g, cls, SNAM_GOLDEN[g].cls);
            fails++;
        }
        if (!(confidence >= 0.0f && confidence <= 1.0001f)) {
            printf("  [%d] confidence %.5f out of [0,1]\n", g, confidence);
            fails++;
        }
        double want = expected_confidence(SNAM_GOLDEN[g].logits);
        if (fabs((double)confidence - want) > 5.0e-2) {
            printf("  [%d] confidence %.5f vs golden %.5f (Δ>5e-2)\n", g, confidence, want);
            fails++;
        }
    }

    /* [03_03 §8 #6/#7] e2e smoke: реальний Run_Inference на golden-кадрі кавітації/пилки
     * → Phase-1.5 рішення (decide, main.c §5.1) → acoustic_events++ / emergency TX.
     * Доводить контракт class-ID (модель ↔ decision) наскрізь; падає, якщо golden
     * втратить покриття класу (per-class coverage у emit_golden). */
    int saw_cav = 0, saw_saw = 0;
    for (int g = 0; g < SNAM_GOLDEN_COUNT; g++) {
        float conf;
        if (SNAM_GOLDEN[g].cls == ML_CLASS_CAVITATION && !saw_cav) {
            uint16_t events = 0; int emerg = 0;
            uint8_t cls = Run_Inference(SNAM_GOLDEN[g].input, &conf);
            decide(cls, &events, &emerg);
            if (!(cls == ML_CLASS_CAVITATION && events == 1 && emerg == 0)) {
                printf("  [#6] cavitation→acoustic_events++ FAILED: cls=%u events=%u emerg=%d\n",
                       cls, events, emerg);
                fails++;
            }
            saw_cav = 1;
        }
        if (SNAM_GOLDEN[g].cls == ML_CLASS_CHAINSAW && !saw_saw) {
            uint16_t events = 0; int emerg = 0;
            uint8_t cls = Run_Inference(SNAM_GOLDEN[g].input, &conf);
            decide(cls, &events, &emerg);
            if (!(cls == ML_CLASS_CHAINSAW && emerg == 1 && events == 0)) {
                printf("  [#7] chainsaw→emergency TX FAILED: cls=%u events=%u emerg=%d\n",
                       cls, events, emerg);
                fails++;
            }
            saw_saw = 1;
        }
    }
    if (!saw_cav) { printf("  [#6] no cavitation golden frame (coverage gap)\n"); fails++; }
    if (!saw_saw) { printf("  [#7] no chainsaw golden frame (coverage gap)\n"); fails++; }

    if (fails == 0)
        printf("test_audio_model: OK — %d golden (class-exact + softmax) + §8 #6/#7 e2e smoke\n",
               SNAM_GOLDEN_COUNT);
    else
        printf("test_audio_model: %d FAILURE(S)\n", fails);
    return fails ? 1 : 0;
}
