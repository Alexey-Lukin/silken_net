#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [STK.5] GUM uncertainty-budget тракту `delta_t → GP → SCC` — параметрична модель,
# single-source. Канон (05_02 §Trust-origin ladder) ПОСИЛАЄТЬСЯ сюди, не restate'ить
# числа: редагуєш бюджет — тут. Дзеркало scc_rate.rb (E.63) — той рахує ЗНАЧЕННЯ
# того самого ланцюга, цей рахує його НЕВИЗНАЧЕНІСТЬ.
#
# Pure Ruby (no Rails / no bundle). Виклик:
#   ruby tools/firmware/uncertainty_budget.rb                 # повний бюджет + вклади
#   ruby tools/firmware/uncertainty_budget.rb delta_t_s=3600  # робоча точка KEY=VAL
#   ruby tools/firmware/uncertainty_budget.rb --assert        # гейт: 5 інваріантів
#
# Метод — ISO/IEC Guide 98-3 (GUM) §5: для мультиплікативно-композитної моделі
# комбінована ВІДНОСНА невизначеність = квадратура відносних вкладів, кожен
# зважений коефіцієнтом чутливості c_i = (∂f/∂x_i)·(x_i/f).
#
# ⛔ МЕЖА, ЯКУ ЦЕЙ ДОКУМЕНТ НЕ ПЕРЕСТУПАЄ — і це перше, що спитає метролог:
# ланцюг рахується ДО `SCC` і зупиняється. Крок `SCC → tCO₂` (2000:1) НЕ є виміром
# — це внутрішня ОБЛІКОВА КОНВЕНЦІЯ (05_03 · 00_04 §3 кажуть це тричі), тож
# приписувати йому метрологічну невизначеність означало б видавати домовленість за
# вимірювану величину. Невизначеність там definitional, не інструментальна.
#
# ⚠️ ЧОГО СИСТЕМА НЕ МАЄ (заявляти вголос, інакше бюджет бреше про прилад):
#   • ЖОДНОГО виміряного значення дрейфу [ARCH.84]: писачів `temperature_offset_c`
#     і `vcap_coefficient` у дереві немає, рядок живе з дефолтами 0.0/1.0, а
#     `sensor_drift_critical?` не істинний НІКОЛИ. Пороги нижче — АПРІОРНІ МЕЖІ
#     при НУЛЬОВІЙ популяції вимірів, тобто верхні оцінки типу B, не статистика.
#   • `vcap` — це мВ VDDA (VREFINT-cal, FW.50), НЕ напруга іоністора [ARCH.99];
#     BQ25570 тримає ту шину на 3.3 В, тож про запас енергії вона не каже нічого.
#     Ім'я історичне; метрологу вимірювану величину називати правильно.
#   • DELTA_T_FAST_S / DELTA_T_SLOW_S — placeholder до bench-кривої recharge [E.63],
#     тож КООРДИНАТА робочої точки, а не лише її невизначеність, є попередньою.

PARAMS = {
  # ── робоча точка (02_03 §9.6 Variant C = energy-positive) ───────────────────
  delta_t_s: 6372.0,      # 1.77 год
  # ── межі метаболічного відображення (bio_contract.rb, placeholder [E.63]) ───
  delta_t_fast_s: 600.0,  # m = 1.0
  delta_t_slow_s: 7200.0, # m = 0.0
  # ── wire-квантування GP (FW.29-PACK, 5 біт) ────────────────────────────────
  gp_wire_min: 5.0,
  gp_wire_max: 31.0,
  # ── вхідні невизначеності (тип B, апріорні) ────────────────────────────────
  u_delta_t_raw_pct: 8.0, # сирий RTC-джитер до фільтра (03_01)
  ema_alpha: 0.2,         # EMA_ALPHA_NUM/DEN = 2/10 (firmware/soldier/main.c)
  u_temp_drift_c: 5.0,    # MAX_TEMP_DRIFT — АПРІОРНА межа (DeviceCalibration)
  temp_span_c: 135.0,     # SAFE_TEMP_RANGE = -45..90 → domain of validity
  u_vcap_coeff: 0.2,      # MAX_VCAP_TOLERANCE — 20%, теж апріорна межа
  # ── конверсія (05_06 §7 · 05_03) ───────────────────────────────────────────
  emission_threshold_gp: 10_000.0, # GP на 1 SCC; DAO-live, definitional
  coverage_k: 2.0                  # k=2 ≈ 95% (GUM §6.2 розширена невизначеність)
}.freeze

# Метаболічне відображення delta_t → m ∈ [0,1] (bio_contract.rb, дзеркало scc_rate.rb).
def metabolic_m(prm, delta_t)
  span = prm[:delta_t_slow_s] - prm[:delta_t_fast_s]
  ((prm[:delta_t_slow_s] - delta_t) / span).clamp(0.0, 1.0)
end

# Коефіцієнт чутливості у ВІДНОСНІЙ формі: c = |∂wire/∂t|·(t/wire).
#
# 🔴 Чутливість береться до WIRE, а не до `m`, і це не деталь: у GP іде
# `wire = GP_MIN + m·span_wire`, тобто величина зі ЗСУВОМ `GP_MIN=5`. Відносна
# невизначеність зсунутої величини НЕ дорівнює відносній невизначеності `m` —
# зсув демпфує її тим сильніше, чим менше `m`. Перша редакція цієї моделі
# рахувала c до `m` і завищувала бюджет у ~2.5× (20.5% замість 8.4% у робочій
# точці Variant C). Клас — «підміна виміру»: обидві величини лінійні за
# delta_t, обидві «метаболічні», але в конверсію входить рівно одна.
def sensitivity_wire(prm, delta_t)
  wire = wire_gp(prm, delta_t)
  return Float::INFINITY if wire <= 0.0

  span_dt = prm[:delta_t_slow_s] - prm[:delta_t_fast_s]
  span_wire = prm[:gp_wire_max] - prm[:gp_wire_min]
  (span_wire / span_dt) * (delta_t / wire)
end

# Неокруглений wire — саме він несе чутливість; округлення враховане окремою
# складовою (квантування), інакше воно порахувалось би двічі.
def wire_gp(prm, delta_t)
  prm[:gp_wire_min] + metabolic_m(prm, delta_t) * (prm[:gp_wire_max] - prm[:gp_wire_min])
end

# EMA придушує ВИПАДКОВУ складову: σ_out/σ_in = sqrt(α / (2−α)) для
# експоненційного фільтра першого порядку в усталеному режимі.
def ema_reduction(alpha)
  Math.sqrt(alpha / (2.0 - alpha))
end

def budget(prm)
  dt = prm[:delta_t_s]
  m = metabolic_m(prm, dt)
  wire = (prm[:gp_wire_min] + m * (prm[:gp_wire_max] - prm[:gp_wire_min])).round
  span_wire = prm[:gp_wire_max] - prm[:gp_wire_min]

  # (1) delta_t після EMA — єдина складова, що реально фільтрується.
  u_dt = prm[:u_delta_t_raw_pct] * ema_reduction(prm[:ema_alpha])
  # (2) підсилення відображенням: чутливість до WIRE (зі зсувом GP_MIN), не до m.
  c_m = sensitivity_wire(prm, dt)
  u_m = u_dt * c_m
  # (3) квантування wire: рівномірний розподіл півкроку → u = 0.5/sqrt(3) LSB.
  u_quant = wire.positive? ? (0.5 / Math.sqrt(3.0)) / wire * 100.0 : Float::INFINITY
  # (4) температурний дрейф — АПРІОРНА межа, прямокутний розподіл → /sqrt(3).
  u_temp = (prm[:u_temp_drift_c] / Math.sqrt(3.0)) / prm[:temp_span_c] * 100.0
  # (5) VDDA-коефіцієнт — теж апріорна межа (входить у придатність, не в GP).
  u_vcap = prm[:u_vcap_coeff] / Math.sqrt(3.0) * 100.0

  contributions = {
    "delta_t → m (підсилене відображенням)" => u_m,
    "wire-квантування GP (5 біт)" => u_quant,
    "температурний дрейф (апріорна межа)" => u_temp
  }
  combined = Math.sqrt(contributions.values.sum { |u| u * u })

  { m: m, wire: wire, span_wire: span_wire, u_dt: u_dt, c_m: c_m, u_vcap: u_vcap,
    contributions: contributions, combined: combined, expanded: combined * prm[:coverage_k] }
end

def report(prm)
  b = budget(prm)
  puts "GUM uncertainty-budget [STK.5] — тракт `delta_t → GP → SCC`"
  puts "робоча точка: delta_t=#{(prm[:delta_t_s] / 3600).round(2)} год · " \
       "m=#{b[:m].round(4)} · wire=#{b[:wire]} GP · stored=#{b[:wire] * 2} GP/пакет"
  puts

  printf("%-42s %10s\n", "складова", "u (%)")
  b[:contributions].each { |name, u| printf("%-42s %9.2f\n", name, u) }
  puts "-" * 53
  printf("%-42s %9.2f\n", "комбінована u_c (k=1)", b[:combined])
  printf("%-42s %9.2f\n", "розширена U (k=#{prm[:coverage_k].to_i}, ≈95%)", b[:expanded])
  puts

  dominant = b[:contributions].max_by { |_, u| u }
  puts "домінує: #{dominant[0]} — #{(dominant[1] / b[:combined] * 100).round(0)}% дисперсії"
  puts "коефіцієнт чутливості wire до delta_t: ×#{b[:c_m].round(2)} " \
       "(EMA дав #{b[:u_dt].round(2)}% на вході; зсув GP_MIN=#{prm[:gp_wire_min].to_i} демпфує)"
  puts
  puts "⛔ Ланцюг зупинено на SCC: крок SCC→tCO₂ (2000:1) — облікова конвенція, не вимір."
  puts "⚠️ Дрейф-складові — АПРІОРНІ межі при нулі виміряних значень [ARCH.84]."
  puts "⚠️ `vcap` = мВ VDDA, не напруга іоністора [ARCH.99]; u=#{b[:u_vcap].round(1)}% " \
       "входить у придатність, не в GP."
end

def assert_run(prm)
  errors = []
  b = budget(prm)

  # 1. EMA-редукція мусить відтворювати канон-цифри 03_01 (±8% → ±2.7%,
  #    ±5% → ±1.7%) з ТОГО САМОГО α, що прошитий у firmware. Ловить розходження
  #    між прошивкою і канон-прозою — вони живуть у різних домах.
  red = ema_reduction(prm[:ema_alpha])
  %w[8.0:2.7 5.0:1.7].each do |pair|
    raw, expected = pair.split(":").map(&:to_f)
    got = (raw * red).round(1)
    errors << "EMA-редукція: #{raw}% дало #{got}%, канон 03_01 каже #{expected}% " \
              "(α=#{prm[:ema_alpha]} розійшлось із прошивкою?)" if (got - expected).abs > 0.1
  end

  # 2. Квадратура: комбінована НЕ МОЖЕ бути меншою за найбільшу складову.
  #    Структурний інваріант GUM — ловить помилку знаку/суми.
  largest = b[:contributions].values.max
  errors << "u_c=#{b[:combined].round(2)} < найбільшої складової #{largest.round(2)} " \
            "— квадратура порахована неправильно" if b[:combined] < largest - 1e-9

  # 3. Кожна складова мусить бути СКІНЧЕННОЮ й додатною. Ловить Inf/NaN від ділення
  #    на нуль (wire=0, span=0, temp_span=0) — інакше квадратура віддає Inf, а
  #    інваріант 2 при цьому лишається формально істинним (Inf ≥ Inf).
  #    ⚠️ Тут СВІДОМО не перевіряється «чи є домінанта»: частка найбільшої складової
  #    є властивістю РОБОЧОЇ ТОЧКИ, а не обчислення — у середині діапазону (m≈0.5)
  #    складові природно вирівнюються, і гейт на домінанту червонів би на цілком
  #    легітимному вході (виміряно: delta_t=3900 s дає 42%). Домінанта лишається
  #    в ЗВІТІ, де вона інформує, а не гейтує.
  bad = b[:contributions].reject { |_, u| u.finite? && u.positive? }
  errors << "нескінченна/недодатна складова: #{bad.keys.join(', ')} — " \
            "ділення на нуль у бюджеті" if bad.any?

  # 4. МЕЖА ЛАНЦЮГА: `emission_threshold` — DEFINITIONAL, тож не сміє входити у
  #    квадратуру. Якби ввійшов, ми б приписали метрологічну невизначеність
  #    домовленості (той самий клас, що SCC→tCO₂).
  errors << "конверсійний поріг потрапив у бюджет — definitional величина " \
            "не має інструментальної невизначеності" if b[:contributions].key?("emission_threshold")

  # 5. РОБОЧА ТОЧКА не сміє лежати за межами відображення: m поза [0,1] означає,
  #    що delta_t вийшов за bio_contract-діапазон і бюджет рахує неіснуючий режим.
  errors << "m=#{b[:m].round(3)} поза (0,1] — робоча точка поза діапазоном " \
            "bio_contract, бюджет описує режим, якого немає" unless b[:m].positive? && b[:m] <= 1.0

  if errors.empty?
    puts "✅ uncertainty_budget: u_c=#{b[:combined].round(1)}% · " \
         "U(k=#{prm[:coverage_k].to_i})=#{b[:expanded].round(1)}% · " \
         "найбільша складова=#{((largest**2) / (b[:combined]**2) * 100).round}% дисперсії · " \
         "ланцюг зупинено на SCC " \
         "(координата робочої точки calibration-pending, E.63)"
    exit 0
  end
  warn "❌ uncertainty_budget FAIL:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
end

params = PARAMS.dup
assert_mode = ARGV.delete("--assert")
ARGV.each do |arg|
  key, val = arg.split("=", 2)
  key = key.to_sym
  abort("невідомий параметр: #{key} (є: #{PARAMS.keys.join(', ')})") unless PARAMS.key?(key)
  params[key] = Float(val)
end
params.freeze

assert_mode ? assert_run(params) : report(params)
