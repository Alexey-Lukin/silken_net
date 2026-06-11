/*
 * logmel_main.c — [FW.4] QEMU-M4 нога log-mel DSP (qemu-system-arm mps2-an386).
 *
 * Той самий Compute_LogMel (LOGMEL_USE_CMSIS, arm_rfft_fast_f32), що поїде в
 * Солдата, на справжньому Cortex-M4 код-шляху: soft-float __aeabi_* — ABI
 * реального STM32WLE5JC (M4 БЕЗ FPU). Два вердикти за один прогін:
 *
 *   1) golden-parity — спільне ядро logmel_parity_core.h (те саме, що
 *      host-ctest): пакування RFFT + float32-numerics проти double-оракула;
 *   2) stack high-water НАВКОЛО чистих викликів Compute_LogMel: вхід/вихід —
 *      static (на Солдаті кадр живе в DMA-буфері, не на стеку), вікно під SP
 *      фарбується, після прогону сканується. Бюджет-гейт — коексистенція зі
 *      стеком main-циклу + 16 KB tensor arena + mruby (03_03 §6).
 *
 * QEMU не цикло-точний — latency тут НЕ міряємо (то клас C, bench);
 * біти і стек — міряємо. Build/run: firmware/scripts/qemu_logmel.sh
 */
#include <stdio.h>
#include <stdint.h>

#include "../logmel_parity_core.h"
#include "../stack_paint.h"

void Uart0_Init(void);

/* Вікно фарбування під SP: глибше за будь-який очікуваний високий слід. */
#define PAINT_WORDS    (16u * 1024u / 4u)

/* Tripwire-бюджет: після reuse-buffers очікуємо ~4 КБ (два кадрові буфери
 * по LOGMEL_N_FFT float + soft-float хвости). Перевищення = регресія стеку. */
#define STACK_BUDGET_BYTES  (6u * 1024u)

/* Як на Солдаті: кадр НЕ стековий. */
static float frame_in[LOGMEL_N_FFT];
static float mel_out[LOGMEL_N_MELS];

/* Paint/scan — спільний ../stack_paint.h (One-Home з parity-ногами). */

int main(void)
{
    float worst = 0.0f;
    int failed;
    uint32_t highwater;

    Uart0_Init();
    setvbuf(stdout, NULL, _IONBF, 0);

    /* 1. Парність (друк лише на фейлі — стек міряємо окремо, нижче). */
    failed = Logmel_Parity_Run(&worst);

    /* 2. Стек: фарба → чисті виклики (жодного stdio між ними) → скан. */
    {
        uint32_t *sp_ref = (uint32_t *)__builtin_frame_address(0);
        Stack_Paint(sp_ref, PAINT_WORDS);
        for (int g = 0; g < LOGMEL_GOLDEN_COUNT; g++) {
            for (int i = 0; i < LOGMEL_N_FFT; i++)
                frame_in[i] = LOGMEL_GOLDEN[g].input[i];
            Compute_LogMel(frame_in, mel_out);
        }
        highwater = Stack_Highwater(sp_ref, PAINT_WORDS);
    }

    /* Друк цілими числами: незалежно від float-printf варіанта newlib. */
    printf("LOGMEL-M4 worst-nano-delta=%lu tol-nano=%lu\n",
           (unsigned long)(worst * 1e9f),
           (unsigned long)(LOGMEL_PARITY_TOL * 1e9f));
    printf("LOGMEL-M4 STACK high-water=%lu budget=%lu\n",
           (unsigned long)highwater, (unsigned long)STACK_BUDGET_BYTES);
    if (highwater > STACK_BUDGET_BYTES) {
        printf("  FAIL stack high-water over budget\n");
        failed++;
    }
    if (highwater == 0u) {
        printf("  FAIL stack scan saw no footprint — paint/scan broken\n");
        failed++;
    }

    printf("LOGMEL-M4-COMPLETE %s\n", failed ? "FAIL" : "PASS");
    return failed ? 2 : 0;
}
