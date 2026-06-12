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

    if (fails == 0)
        printf("test_audio_model: OK — %d golden frames (class-exact + softmax)\n",
               SNAM_GOLDEN_COUNT);
    else
        printf("test_audio_model: %d FAILURE(S)\n", fails);
    return fails ? 1 : 0;
}
