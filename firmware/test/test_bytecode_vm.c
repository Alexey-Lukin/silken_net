// SPDX-License-Identifier: AGPL-3.0-or-later
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
 * ⊕ [FW.66 S4] Друга половина — контракт CCM-ери (firmware/common/ccm_bytecode.h):
 * `ccm_state(pt)` над 14 байтами plaintext, складеними СПРАВЖНІМ Pack_CCM_Sensor_Payload
 * (lora_ccm.h), дає байт статусу [0 | gp] на межах Δt; і ери розведені — точка входу
 * чужої ери падає винятком (→ VM_ERROR на пристрої), а не біжить із чужими аргументами.
 *
 * Build/run: tools/firmware/run_bytecode_vm.sh
 */
#include <stdio.h>

#include <mruby.h>
#include <mruby/irep.h>
#include <mruby/array.h>
#include <mruby/string.h>

#include "lorenz_bytecode.h"   /* -I firmware/common */
#include "ccm_bytecode.h"      /* [FW.66 S4] контракт CCM-ери */
#include "lora_ccm.h"          /* Pack_CCM_Sensor_Payload — той самий складальник, що в main.c */
#include "lorenz_thresholds.h" /* Lorenz_Band_Args — той самий хелпер, що в main.c */

/* Виклик точки входу, що мусить ВПАСТИ (ера не своя): 1 — впала, 0 — ні. */
static int entry_raises(mrb_state *mrb, const char *entry, mrb_int argc, const mrb_value *argv)
{
    mrb_funcall_argv(mrb, mrb_top_self(mrb), mrb_intern_cstr(mrb, entry), argc, argv);
    int raised = mrb->exc != NULL;
    mrb->exc = NULL;
    return raised;
}

/* [FW.66 S4] Контракт CCM-ери на межах Δt. Очікування — числа серверної формули
 * (`SilkenNet::Attractor.expected_homeostasis_gp`; її паритет із контрактом на всьому
 * діапазоні судить spec/services/silken_net/attractor_spec.rb), статус — 0. */
static int ccm_contract_checks(void)
{
    static const struct { uint16_t ema; long gp; } cases[] = {
        { 0, 0 }, { 599, 31 }, { 600, 31 }, { 601, 31 }, { 3600, 19 },
        { 7199, 5 }, { 7200, 5 }, { 7201, 5 }, { 0xFFFF, 5 },
        { 2250, 25 }, { 5550, 12 },   /* єдині точні півцілі: 24.5 → 25 · 11.5 → 12 */
    };
    mrb_state *mrb = mrb_open();
    if (!mrb) { fprintf(stderr, "❌ mrb_open failed\n"); return 6; }
    mrb_load_irep(mrb, ccm_bytecode);
    if (mrb->exc) { fprintf(stderr, "❌ mrb_load_irep(ccm_bytecode) raised\n"); return 7; }

    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        uint8_t pt[FW2_CCM_PLAINTEXT_LEN];
        Pack_CCM_Sensor_Payload(3300, 25, 0x2A, 600, 0u, 0x31, 0u,
                                Pack_FW2_Diag(0u, 0u, 0u, 0u), 0u, cases[i].ema, pt);
        mrb_value arg = mrb_str_new(mrb, (const char *)pt, sizeof pt);
        mrb_value r = mrb_funcall_argv(mrb, mrb_top_self(mrb), mrb_intern_lit(mrb, "ccm_state"), 1, &arg);
        if (mrb->exc || !mrb_integer_p(r) || mrb_integer(r) != cases[i].gp) {
            fprintf(stderr, "❌ ccm_state(ema=%u) → %ld, expected status 0 | gp %ld\n", cases[i].ema,
                    (long)(mrb->exc || !mrb_integer_p(r) ? -1 : mrb_integer(r)), cases[i].gp);
            return 8;
        }
    }
    /* Ера ECB у CCM-VM: точки входу calculate_state тут немає. */
    mrb_value nine[9];
    for (int i = 0; i < 9; i++) nine[i] = mrb_float_value(mrb, 1.0);
    if (!entry_raises(mrb, "calculate_state", 9, nine)) {
        fprintf(stderr, "❌ ccm_bytecode answered calculate_state — eras are not separated\n");
        return 9;
    }
    mrb_close(mrb);

    /* Ера CCM у ECB-VM: точки входу ccm_state там немає. */
    mrb = mrb_open();
    if (!mrb) { fprintf(stderr, "❌ mrb_open failed\n"); return 6; }
    mrb_load_irep(mrb, lorenz_bytecode);
    mrb_value pt_arg = mrb_str_new(mrb, "\0\0\0\0\0\0\0\0\0\0\0\0\0\0", FW2_CCM_PLAINTEXT_LEN);
    if (!entry_raises(mrb, "ccm_state", 1, &pt_arg)) {
        fprintf(stderr, "❌ lorenz_bytecode answered ccm_state — eras are not separated\n");
        return 10;
    }
    mrb_close(mrb);

    printf("✅ [FW.66 S4] minimal VM ran ccm_bytecode: ccm_state over the Δt boundaries, eras separated\n");
    return 0;
}

int main(void)
{
    mrb_state *mrb = mrb_open();
    if (!mrb) { fprintf(stderr, "❌ mrb_open failed\n"); return 2; }

    /* Load + run the top-level → defines SilkenNet + the calculate_state entry. */
    mrb_load_irep(mrb, lorenz_bytecode);
    if (mrb->exc) { fprintf(stderr, "❌ mrb_load_irep raised\n"); return 3; }

    /* calculate_state(1.0, 1.0, 1.0, 25, 10, 60, 3300, z_min, z_max) → [payload, x, y, z].
     * 9 аргументів, як на пристрої: контракт, що приймає менше, тут падає
     * ArgumentError-ом (exit 4) — це й пін ABI-підлоги (03_04 §6). */
    double band[2];
    Lorenz_Band_Args(LORENZ_DEFAULT_Z_MIN_X100, LORENZ_DEFAULT_Z_MAX_X100, band);
    mrb_value argv[9];
    const double in[9] = { 1.0, 1.0, 1.0, 25.0, 10.0, 60.0, 3300.0, band[0], band[1] };
    for (int i = 0; i < 9; i++) argv[i] = mrb_float_value(mrb, in[i]);

    mrb_value r = mrb_funcall_argv(mrb, mrb_top_self(mrb),
                                   mrb_intern_lit(mrb, "calculate_state"), 9, argv);

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
    return ccm_contract_checks();
}
