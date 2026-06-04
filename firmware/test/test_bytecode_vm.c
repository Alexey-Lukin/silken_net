/*
 * test_bytecode_vm.c — [FW.46] Run the committed mruby bytecode in a MINIMAL VM.
 *
 * Loads firmware/common/lorenz_bytecode.h via mrb_load_irep — the real
 * on-device path (NOT the .rb source) — into an mruby built with the firmware's
 * minimal gembox (core + mruby-compar-ext) and calls calculate_state. This
 * proves three things at once:
 *   1. the committed bytecode is loadable + executable,
 *   2. the minimal gembox resolves every method bio_contract.rb uses
 *      (abs / round / times / clamp), and
 *   3. calculate_state returns a well-formed [payload, x, y, z].
 *
 * Build/run: tools/firmware/run_bytecode_vm.sh
 */
#include <stdio.h>

#include <mruby.h>
#include <mruby/irep.h>
#include <mruby/array.h>
#include <mruby/string.h>

#include "lorenz_bytecode.h"   /* -I firmware/common */

int main(void)
{
    mrb_state *mrb = mrb_open();
    if (!mrb) { fprintf(stderr, "❌ mrb_open failed\n"); return 2; }

    /* Load + run the top-level → defines SilkenNet + the calculate_state entry. */
    mrb_load_irep(mrb, lorenz_bytecode);
    if (mrb->exc) { fprintf(stderr, "❌ mrb_load_irep raised\n"); return 3; }

    /* calculate_state(1.0, 1.0, 1.0, 25, 10, 60, 3300) → [payload, x, y, z]. */
    mrb_value argv[7];
    const double in[7] = { 1.0, 1.0, 1.0, 25.0, 10.0, 60.0, 3300.0 };
    for (int i = 0; i < 7; i++) argv[i] = mrb_float_value(mrb, in[i]);

    mrb_value r = mrb_funcall_argv(mrb, mrb_top_self(mrb),
                                   mrb_intern_lit(mrb, "calculate_state"), 7, argv);

    if (mrb->exc) {
        struct RObject *exc = mrb->exc;
        mrb->exc = NULL;   /* clear so we can inspect the exception safely */
        mrb_value msg = mrb_funcall(mrb, mrb_obj_value(exc), "inspect", 0);
        fprintf(stderr, "❌ calculate_state raised: %s\n",
                mrb_string_p(msg) ? mrb_str_to_cstr(mrb, msg) : "(unknown)");
        return 4;
    }
    if (!mrb_array_p(r) || RARRAY_LEN(r) < 4) {
        fprintf(stderr, "❌ calculate_state returned a malformed result\n");
        return 5;
    }

    long   payload = (long)mrb_integer(mrb_ary_ref(mrb, r, 0));
    double z       = mrb_float(mrb_ary_ref(mrb, r, 3));
    printf("✅ [FW.46] minimal VM ran lorenz_bytecode: "
           "calculate_state → payload=%ld (status=%ld, gp=%ld), z=%.6f\n",
           payload, payload >> 5, payload & 0x1F, z);

    mrb_close(mrb);
    return 0;
}
