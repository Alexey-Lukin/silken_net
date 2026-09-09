# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [HW.44] Зимовий boot↔brownout цикл — чи вистачає енергії гістерезисного вікна
# VBAT_OK (02_03 §4.Г/§5: OFF=3.312 В / ON=3.400 В, C_VSTOR=0.47F) на завершення
# 3 EMA-warmup циклів (03_01 §13.3, EMA_WARMUP_CYCLES=3) при зимовому P_gen 3-5 µW,
# перш ніж VSTOR знову впаде нижче OFF-порога і backup-домен скинеться. Канон
# (02_03 §9.8) посилається сюди; рівняння й вхідні числа живуть тут і самоперевіряються
# проти надрукованих у 02_03 §9.3/§9.6/§9.8 проміжних результатів (--assert).
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/boot_brownout_cycle.rb                    # повний звіт (ECB + CCM, 3-5 µW)
#   ruby tools/firmware/boot_brownout_cycle.rb p_gen_uw=4.0        # override будь-якого параметра
#   ruby tools/firmware/boot_brownout_cycle.rb --assert            # regression-гейт: ECB-margin > 0
#                                                                   # у всій 3-5µW смузі (CCM = warn-only,
#                                                                   # бо FW.2 CCM ще bench-gated, не live)
#
# Модель (стелі позначені):
#   вікно      = E(V_ON) − E(V_OFF), E(V) = ½CV²                    ← чиста ємність, без ADC/резисторної похибки
#   цикл-ціна  = (TinyML + Lorenz + TX) / η_buck_active              ← §9.4/§9.6, season-independent
#   3-cycle    = 3 × цикл-ціна − 2 × interval_h × (E_gen − E_sleep) ← ГОЛОВНИЙ доданок = 3×ціна;
#                                                                      inter-cycle net — ЧУТЛИВІСТЬ, не факт
#                                                                      (interval_h — ПРИПУЩЕННЯ, не канон-число:
#                                                                      прошивка не документує pre-warmup каденцію
#                                                                      окремо від адаптивного H; 1.0 год — та сама
#                                                                      «1 TX/год» базова точка, що §9.5 бере як
#                                                                      референс ДО Сценарію C).
#
# ⛔ СТЕЛІ, ОГОЛОШЕНІ ВГОЛОС — інакше зелений прогін почне означати «не перевірено»:
#   • `V_OK_OFF/ON` — розрахункові цільові пороги дільника (02_03 §5), НЕ верифіковані на
#     фізичному CJMCU-2557 (HW.7, відкритий). ±2% VBAT_ACCURACY з датшита — окрема, ширша
#     смуга за 1%-резисторами; цей скрипт її НЕ стек-моделює (кореляція ROK1/ROK2 між обома
#     порогами робить наївний ±2%-на-кожен-порігworst-case неправильним EE-аргументом) —
#     трактуй тут надруковані margin-числа як НОМІНАЛЬНІ, не worst-case.
#   • `ETA_BOOST_WINTER=0.65` — єдина зимова точка, яку канон називає (§9.8, при 5 µW);
#     той самий коефіцієнт застосовано на всю смугу 3-5 µW, бо кривої η(I_IN) при <15 µW
#     канон не дає. Це спрощення, не вимір.
#   • `interval_h` — ПРИПУЩЕННЯ (див. вище), не задокументована pre-warmup каденція.
#     Головний (3×ціна) доданок від нього НЕ залежить — це і є причина розбивати звіт
#     на «headline» (робастний) і «sensitivity» (залежний від інтервалу) блоки.
#   • TX-енергії (ECB 16Б / CCM 30Б) — season-independent фіксовані навантаження з §9.4/§9.6;
#     CCM-число несе застереження ARCH.8 (той самий перерахунок, інша споживана величина).

PARAMS = {
  # ── VBAT_OK гістерезис (02_03 §4.Г, verified Eq.3/Eq.4) ───────────────────
  c_vstor_f: 0.47,          # EDLC на VSTOR (02_03 §8 BOM)
  v_ok_on: 3.400,           # OK_HYST (зростання) — buck ON, MCU boot
  v_ok_off: 3.312,          # OK_PROG (спадання) — buck OFF, brownout
  # ── EMA warmup (03_01 §13.3) ──────────────────────────────────────────────
  ema_warmup_cycles: 3,     # EMA_WARMUP_CYCLES — цикли до EMA_Is_Warmed_Up()
  # ── активний цикл, VOUT-навантаження (02_03 §9.4/§9.6 Сценарій C, +14dBm SF9) ─
  tinyml_mj: 7.92,
  lorenz_mj: 3.96,
  tx_ecb_mj: 21.78,         # 16Б ECB-кадр @ SF9 (транзитний wire-формат, ЖИВИЙ сьогодні)
  tx_ccm_mj: 29.9,          # 30Б CCM-кадр @ SF9 (wire-rev2.1, ARCH.8-корекція; FW.2 bench-gated)
  eta_buck_active: 0.88,    # §9.1 buck active
  # ── сон + генерація для inter-cycle sensitivity (02_03 §9.1/§9.3/§9.6/§9.8) ───
  i_stm32_sleep_na: 300,    # STOP2 RTC-only (Сценарій C, затверджено §9.8)
  v_out: 3.3,
  eta_buck_sleep: 0.50,     # §9.1 buck idle
  i_bq_quiescent_na: 488,   # BQ25570 IQ (§8)
  v_vstor_avg: 4.5,         # §9.1/§9.3 VSTOR avg для прямого IQ-споживання
  eta_boost_winter: 0.65,   # §9.8 "η_boost lower at lower I_IN" — єдина зимова точка канону
  p_gen_uw: 5.0,            # верхня межа зимового P_gen (HW.44 body: 3-5 µW)
  interval_h: 1.0           # ПРИПУЩЕННЯ pre-warmup wake-каденції (див. шапку)
}.freeze

P_GEN_SWEEP_UW = [ 3.0, 4.0, 5.0 ].freeze # HW.44-назва смуга: "P_gen 3-5 µW"

params = PARAMS.dup
assert_mode = ARGV.delete("--assert")
ARGV.each do |arg|
  key, val = arg.split("=", 2)
  key = key.to_sym
  abort("невідомий параметр: #{key} (є: #{PARAMS.keys.join(', ')})") unless PARAMS.key?(key)
  params[key] = Float(val)
end

def cap_energy_mj(c_f, v) = 0.5 * c_f * (v**2) * 1000.0

def window_mj(p) = cap_energy_mj(p[:c_vstor_f], p[:v_ok_on]) - cap_energy_mj(p[:c_vstor_f], p[:v_ok_off])

def active_cycle_from_vstor_mj(p, wire:)
  tx = wire == :ccm ? p[:tx_ccm_mj] : p[:tx_ecb_mj]
  (p[:tinyml_mj] + p[:lorenz_mj] + tx) / p[:eta_buck_active]
end

# Сон-стік VSTOR (µW): buck-гілка (STM32 STOP2) + пряма BQ-квієсцентна гілка.
# Відтворює 02_03 §9.3 крок-у-крок — асерт нижче звіряє з надрукованими там числами.
def sleep_drain_uw(p)
  p_stm32_sleep_uw = (p[:i_stm32_sleep_na] / 1000.0) * p[:v_out]
  p_drawn_from_vstor_uw = p_stm32_sleep_uw / p[:eta_buck_sleep]
  p_bq_q_uw = (p[:i_bq_quiescent_na] / 1000.0) * p[:v_vstor_avg]
  p_drawn_from_vstor_uw + p_bq_q_uw
end

def sleep_mj_per_hour(p) = sleep_drain_uw(p) * 3600.0 / 1000.0

def gen_mj_per_hour(p, p_gen_uw) = p_gen_uw * 3600.0 / 1000.0 * p[:eta_boost_winter]

# Headline: чиста 3-циклова ціна (робастна — не залежить від interval_h).
def headline_3cycle_mj(p, wire:) = p[:ema_warmup_cycles] * active_cycle_from_vstor_mj(p, wire: wire)

# Sensitivity: + inter-cycle net (sleep − gen) за (N-1) інтервалів між N циклами.
def sensitivity_3cycle_mj(p, wire:, p_gen_uw:)
  net_per_hour = sleep_mj_per_hour(p) - gen_mj_per_hour(p, p_gen_uw) # додатне = чистий дефіцит
  headline_3cycle_mj(p, wire: wire) + (p[:ema_warmup_cycles] - 1) * p[:interval_h] * net_per_hour
end

def report(p)
  win = window_mj(p)
  puts "═══ HW.44 — Boot↔brownout: вікно VBAT_OK vs 3-циклового EMA-warmup ═══"
  puts "  Гістерезис: OFF=%.3f В → ON=%.3f В, C=%.2f F  ⇒  вікно = %.2f мДж" %
       [ p[:v_ok_off], p[:v_ok_on], p[:c_vstor_f], win ]
  puts "  EMA_WARMUP_CYCLES = #{p[:ema_warmup_cycles]}"
  puts

  puts "── Headline: ціна ОДНОГО активного циклу (VSTOR), season-independent ──"
  %i[ecb ccm].each do |wire|
    c1 = active_cycle_from_vstor_mj(p, wire: wire)
    c3 = headline_3cycle_mj(p, wire: wire)
    margin = win - c3
    verdict = margin.positive? ? "margin +%.1f мДж (%.0f%%)" % [ margin, margin / win * 100 ] \
                                : "ДЕФІЦИТ %.1f мДж (%.0f%%) → циклить" % [ -margin, -margin / win * 100 ]
    puts "  %-4s 1×цикл=%6.2f мДж  3×=%7.2f мДж  вікно=%.2f мДж  → %s" %
         [ wire.to_s.upcase, c1, c3, win, verdict ]
  end
  puts

  puts "── Sensitivity: + inter-cycle sleep−gen @ interval_h=#{p[:interval_h]} год, P_gen 3–5 µW ──"
  puts "  (interval_h — ПРИПУЩЕННЯ, не канон-число; головний висновок НЕ спирається на цей блок)"
  puts "  %-4s %8s %10s %10s %10s" % [ "wire", "P_gen µW", "3×+bleed", "вікно", "margin" ]
  P_GEN_SWEEP_UW.each do |p_gen|
    %i[ecb ccm].each do |wire|
      cost = sensitivity_3cycle_mj(p, wire: wire, p_gen_uw: p_gen)
      margin = win - cost
      puts "  %-4s %8.1f %10.2f %10.2f %+10.2f" % [ wire.to_s.upcase, p_gen, cost, win, margin ]
    end
  end
  puts

  net_5 = gen_mj_per_hour(p, 5.0) - sleep_mj_per_hour(p)
  puts "── Довгий хвіст (без TX узагалі): чистий баланс сну сам по собі ──"
  puts "  @5µW: gen=%.2f сон=%.2f мДж/год → нетто %+.2f мДж/год" %
       [ gen_mj_per_hour(p, 5.0), sleep_mj_per_hour(p), net_5 ]
  if net_5.negative?
    puts "  → навіть БЕЗ жодного активного циклу вікно спливає за %.0f год (%.1f діб)" %
         [ win / -net_5, win / -net_5 / 24.0 ]
  end
  puts

  puts "── Вирок ──"
  puts "  1. ECB (транзитний, ЖИВИЙ сьогодні): headline margin +%.1f мДж — НЕ циклить від самого warmup-сплеску." %
       (win - headline_3cycle_mj(p, wire: :ecb))
  puts "  2. CCM (wire-rev2.1, FW.2 bench-gated, ЩЕ не в полі): headline margin %+.1f мДж — ЦИКЛИТЬ уже на" \
       " чистій 3-циклoвій ціні, без жодного sensitivity-припущення." %
       (win - headline_3cycle_mj(p, wire: :ccm))
  puts "  3. Vcap cold-TX-defer (COLD_TX_DEFER_VCAP_MV=4000) НЕ рятує жодного з двох випадків: `vcap` читає" \
       " VDDA (≈3300 мВ, поки buck живий), ніколи не сягає 4000, тож кон'юнкція вироджена в temp<-15°C" \
       " (ARCH.99/FW.50, вже канонізовано) — вище цієї температури TX не відкладається взагалі."
  puts "  4. Sensitivity-блок показує, що навіть ECB-запас тоншає з 1 год інтервалом і найнижчим P_gen (3 µW)," \
       " а сам сонний баланс негативний — вікно спливає за ~%.0f год і без жодного циклу." % (win / -net_5)
end

if assert_mode
  win = window_mj(params)
  failures = []
  P_GEN_SWEEP_UW.each do |p_gen|
    margin = win - sensitivity_3cycle_mj(params, wire: :ecb, p_gen_uw: p_gen)
    failures << "ECB @ P_gen=#{p_gen}µW margin=%.2f мДж (< 0)" % margin if margin.negative?
  end
  # self-check: відтворюємо надруковані в 02_03 §9.3/§9.6/§9.8 проміжні числа
  checks = {
    "P_BQ_Q (§9.3, 2.20 µW)" => ((params[:i_bq_quiescent_na] / 1000.0) * params[:v_vstor_avg] - 2.196).abs < 0.01,
    "sleep-drain @ Сценарій C (§9.6, 4.18 µW)" => (sleep_drain_uw(params) - 4.176).abs < 0.01,
    "E_sleep_supercap (§9.6, 15.04 мДж/год)" => (sleep_mj_per_hour(params) - 15.0336).abs < 0.01,
    "E_gen_winter @5µW (§9.8, 11.7 мДж/год)" => (gen_mj_per_hour(params, 5.0) - 11.7).abs < 0.01,
    "E_active_from_VSTOR ECB (§9.6, 38.25 мДж)" =>
      (active_cycle_from_vstor_mj(params, wire: :ecb) - 38.25).abs < 0.01
  }
  checks.each { |name, ok| failures << "self-check провалено: #{name}" unless ok }

  if failures.empty?
    puts "boot_brownout_cycle ✓ — ECB margin ≥ 0 у всій смузі P_gen 3-5µW; self-check проти 02_03 §9.3/§9.6/§9.8 OK"
    puts "  (CCM — warn-only, FW.2 ще bench-gated): " \
         "headline margin %+.1f мДж" % (win - headline_3cycle_mj(params, wire: :ccm))
    exit 0
  else
    warn "boot_brownout_cycle ✗\n  " + failures.join("\n  ")
    exit 1
  end
end

report(params)
