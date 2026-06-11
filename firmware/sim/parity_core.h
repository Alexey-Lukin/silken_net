/*
 * parity_core.h — [FW.55] спільне ядро біт-parity прогону mruby Lorenz.
 *
 * One-Home: host-голден (x86, gcc) і QEMU-M4 (arm-none-eabi, mps2-an386)
 * компілюють ЦЕЙ САМИЙ runner — реальний девайсний шлях mrb_load_irep по
 * committed-байткоду. Кожен кейс друкує StatusByte + сирі біти x/y/z
 * (IEEE 754 double як дві u32-половини) — CI порівнює дампи byte-exact.
 *
 * Чому бітова рівність — правильний гейт: Lorenz = лише +−×÷ (correctly-
 * rounded за IEEE 754), mruby VM виконує той самий байткод у тому ж
 * порядку, double на M4F — software (__aeabi_d*, детермінований integer-
 * код). Розбіжність ARM↔x86 = справжня знахідка (FW.7/FW.19), не шум.
 *
 * Кейси ЗЧЕПЛЕНІ: вихідні (x,y,z) кейсу N — вхід кейсу N+1 (RTC-continuation
 * патерн Солдата) → будь-який одиничний ULP-дрейф ампліфікується хаосом
 * на наступних ітераціях і не сховається.
 *
 * Канон: 03_01 §12 + 00_07 FW.55 (метод-шар — 00_03 §3).
 */
#ifndef SILKEN_PARITY_CORE_H
#define SILKEN_PARITY_CORE_H

#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include <mruby.h>
#include <mruby/irep.h>
#include <mruby/array.h>

#include "lorenz_bytecode.h" /* -I firmware/common */

/* Зонд пам'яті для bare-metal ніг (хто скільки з'їв: open/irep/cases) —
 * no-op на host-голдені. Нога визначає PARITY_MEM_MARK ДО include
 * (друк через свій Sbrk_Highwater); лінії не ^C → diff не чіпають. */
#ifndef PARITY_MEM_MARK
#define PARITY_MEM_MARK(phase) ((void)0)
#endif

#define PARITY_N_CASES 64

/* Дрібний детермінований LCG (Numerical Recipes) — однаковий на обох
 * таргетах, без libc rand(). */
static uint32_t parity_lcg(uint32_t *s)
{
    *s = (*s) * 1664525u + 1013904223u;
    return *s;
}

static void parity_dump_double(const char *tag, double v)
{
    uint64_t bits;
    memcpy(&bits, &v, sizeof bits);
    /* PRIx64 на newlib/arm інколи вимагає повного printf — друкуємо двома
     * u32-половинами, однаково всюди. */
    printf(" %s=%08lX%08lX", tag,
           (unsigned long)(uint32_t)(bits >> 32),
           (unsigned long)(uint32_t)(bits & 0xFFFFFFFFu));
}

/* 0 = усі кейси відпрацювали (parity вирішує зовнішній diff), 1 = VM-збій. */
static int Parity_Run(void)
{
    mrb_state *mrb = mrb_open();
    if (!mrb) { printf("PARITY-ABORT mrb_open\n"); return 1; }
    PARITY_MEM_MARK("open");

    mrb_load_irep(mrb, lorenz_bytecode);
    if (mrb->exc) { printf("PARITY-ABORT load_irep\n"); return 1; }
    PARITY_MEM_MARK("irep");

    /* Кейс 0 — канонічний cold-start (як test_bytecode_vm.c); далі стани
     * зчеплені, а сенсорні входи йдуть від LCG по краях діапазонів. */
    double x = 1.0, y = 1.0, z = 1.0;
    uint32_t seed = 0x53494C4Bu; /* "SILK" */

    /* Краєві піни попереду — клампи/гілки status'а мають побувати в обох
     * світах до того, як хаос піде гуляти. */
    static const double pin_temp[]  = { 25.0, -40.0, 85.0, 0.0 };
    static const double pin_ac[]    = { 10.0, 0.0, 255.0, 128.0 };
    static const double pin_dt[]    = { 60.0, 0.0, 86400.0, 30.0 };
    static const double pin_vcap[]  = { 3300.0, 1800.0, 5500.0, 4500.0 };

    for (int i = 0; i < PARITY_N_CASES; i++) {
        double temp, ac, dt, vcap;
        if (i < 4) {
            temp = pin_temp[i]; ac = pin_ac[i]; dt = pin_dt[i]; vcap = pin_vcap[i];
        } else {
            temp = -40.0 + (double)(parity_lcg(&seed) % 126u);
            ac   = (double)(parity_lcg(&seed) % 256u);
            dt   = (double)(parity_lcg(&seed) % 7200u);
            vcap = 1800.0 + (double)(parity_lcg(&seed) % 3700u);
        }

        mrb_value argv[7];
        argv[0] = mrb_float_value(mrb, x);
        argv[1] = mrb_float_value(mrb, y);
        argv[2] = mrb_float_value(mrb, z);
        argv[3] = mrb_float_value(mrb, temp);
        argv[4] = mrb_float_value(mrb, ac);
        argv[5] = mrb_float_value(mrb, dt);
        argv[6] = mrb_float_value(mrb, vcap);

        /* Арена — як у Солдата (main.c, навколо того ж mrb_funcall_argv):
         * без save/restore кожен результат пінився б в GC-арені, сміття 64
         * кейсів не збиралося б, і heap-вотермарк міряв би артефакт runner'а,
         * а не профіль девайса (фіт-гейт qemu_parity.sh саме це й зловив). */
        int arena_idx = mrb_gc_arena_save(mrb);
        mrb_value r = mrb_funcall_argv(mrb, mrb_top_self(mrb),
                                       mrb_intern_lit(mrb, "calculate_state"),
                                       7, argv);
        if (mrb->exc) { printf("PARITY-ABORT case %d raised\n", i); return 1; }
        if (!mrb_array_p(r) || RARRAY_LEN(r) < 4) {
            printf("PARITY-ABORT case %d malformed\n", i);
            return 1;
        }

        long payload = (long)mrb_integer(mrb_ary_ref(mrb, r, 0));
        x = mrb_float(mrb_ary_ref(mrb, r, 1));
        y = mrb_float(mrb_ary_ref(mrb, r, 2));
        z = mrb_float(mrb_ary_ref(mrb, r, 3));
        mrb_gc_arena_restore(mrb, arena_idx);
        /* Як Солдат після кожного пробудження (main.c): повний GC повертає
         * купу до живого мінімуму — high-water міряє девайсний профіль, а не
         * дрейф сміття до GC-порогу (~2×live ≈ стеля 64КБ SRAM). GC не чіпає
         * математику — дамп лишається byte-exact. */
        mrb_full_gc(mrb);
        if (i == 0) PARITY_MEM_MARK("case0");

        printf("C%02d p=%02lX", i, (unsigned long)(payload & 0xFFl));
        parity_dump_double("x", x);
        parity_dump_double("y", y);
        parity_dump_double("z", z);
        printf("\n");
    }

    PARITY_MEM_MARK("cases");
    mrb_close(mrb);
    printf("PARITY-COMPLETE n=%d\n", PARITY_N_CASES);
    return 0;
}

#endif /* SILKEN_PARITY_CORE_H */
