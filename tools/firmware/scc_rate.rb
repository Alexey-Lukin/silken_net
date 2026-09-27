# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [E.63/SCC-rate] SCC-generation rate — параметрична модель, single-source.
# Канон (02_06 §7.1 · 00_04 §3) ПОСИЛАЄТЬСЯ сюди, не restate'ить magnitude.
# Дзеркало queen_energy_budget.rb (HW.39).
#
# Pure Ruby (no Rails). Виклик:
#   ruby tools/firmware/scc_rate.rb                        # звіт (realistic + ceiling + арбітр)
#   ruby tools/firmware/scc_rate.rb --assert               # гейт на дефолтній Variant C (7027 с)
#   ruby tools/firmware/scc_rate.rb variant_c_s=8006 --assert  # гейт на іншій робочій точці (тут — CCM-точка)
#     (override, НЕ зміна дефолту — дзеркало uncertainty_budget.rb delta_t_s=; ARCH.8)
#
# ЧОМУ guard (adversarial-урок 2026-07-14): попередня канон-проза брала
# packets/day=24 і stored-GP/packet=50 як НЕЗАЛЕЖНІ числа — фізично несумісні
# (обидва = f(delta_t)). При Δt=3600s stored=38, не 50; для stored=50 → 40 пакетів,
# не 24. Guard виводить ОБИДВА з ОДНОГО delta_t → неможливо закодувати такий drift.
#
# Джерела (firmware/bio_contracts/bio_contract.rb — placeholder до bench, E.63):
#   DELTA_T_FAST_S=600 (m=1.0), DELTA_T_SLOW_S=7200 (m=0.0)
#   wire = round(GP_HOMEO_MIN + m*(GP_HOMEO_MAX-GP_HOMEO_MIN)), 5..31
#   stored = 2*wire (backend ×2 upscale, FW.29-PACK; 03_04 (status & 0x1F) * 2)
#   EMISSION_THRESHOLD = 10_000 GP = 1 SCC (05_03 tokenomics_evaluator_worker.rb)
# Стеля [E.63]: DELTA_T_* = placeholder, чекають bench recharge-кривої → magnitude
# уточнити при bench (RUNBOOK §3.3). Guard тримає self-consistency + фізичну стелю,
# НЕ фіксує точну magnitude (вона calibration-pending).

DELTA_T_FAST_S = 600      # bio_contract.rb: ≤ → m=1.0 (пік жвавості)
DELTA_T_SLOW_S = 7200     # bio_contract.rb: ≥ → m=0.0 (мінімум)
GP_HOMEO_MIN   = 5        # 5-бітний wire-мінімум (FW.29-PACK)
GP_HOMEO_MAX   = 31       # 5-бітний wire-максимум
BACKEND_UPSCALE = 2       # backend ×2 (03_04 growth_points = (status_byte & 0x1F) * 2)
EMISSION_THRESHOLD = 10_000 # 05_03: 10k GP = 1 SCC

# Робоча точка delta_t: Variant C — ⚖️ founder 2026-09-26: дефолт = енергомодель
# `tx_cadence_budget.rb` (ECB-ера, обраний радіо-фронтенд: TX `RFO_LP` у SMPS + RX-вікно, яке
# прошивка відкриває щоциклу, + TCXO), тобто 7027 с ≈ 1.95 год. Доти стояло 6372 с, порахованих
# без RX-вікна й на струмі чужого підсилювача — на +10 % оптимістичніше, поза ±8 % u_delta_t.
# ⚠️ ECB-ЕРА (payload 16 Б, FW2_CCM_ENABLED 0). CCM-кадр 30 Б → ≈ 2.22 год, m = 0, і wire-GP
#    сідає на підлогу GP_HOMEO_MIN: SCC/дерево/рік 5.39 → 3.94 (−27 %).
# ⛔ Не правити ДЕФОЛТ тут поодинці: `tx_cadence_budget.rb --assert` звіряє його з енергомоделлю
#    (±8 % u_delta_t) і з дзеркалом у uncertainty_budget.rb, а асерт нижче — з дзеркалом realistic
#    у tokenomics/supply_stress.rb. `variant_c_s=` override — лише для гейта на іншій точці.
# (1 TX/год = Δt=3600s = energy-NEGATIVE без мітигацій, 02_03 §9.5 — НЕ baseline.)
VARIANT_C_S = 7027

# Незалежний арбітр: 05_03 MAX_SUPPLY=1B ≈ 20M дерево-років ⇒ 50 SCC/tree/year.
ARBITER_SCC_YEAR = 50.0

# Арифметика `Δt → m → wire → SCC` — один дім із tx_cadence_budget.rb і uncertainty_budget.rb
# (lib/growth_steps.rb); числа смуги лишаються ТУТ, це дім грошей.
require_relative "lib/growth_steps"
GS = SilkenGrowthSteps
BAND = { fast_s: DELTA_T_FAST_S, slow_s: DELTA_T_SLOW_S, gp_min: GP_HOMEO_MIN, gp_max: GP_HOMEO_MAX }.freeze

def stored_gp_per_packet(delta_t_s) = BACKEND_UPSCALE * GS.wire_gp(delta_t_s: delta_t_s, **BAND)

def scc_per_tree_year(delta_t_s)
  GS.scc_per_tree_year(delta_t_s: delta_t_s, stored_gp: stored_gp_per_packet(delta_t_s), threshold: EMISSION_THRESHOLD)
end

# Де робоча точка стоїть на сходинці wire-GP і що коштує крок униз — гроші квантовані, і
# відстань до сходинки важить більше, ніж відсоток Δt (00_07 ARCH.8).
def step_note(delta_t_s)
  e = GS.step_edges(delta_t_s: delta_t_s, **BAND)
  drop = 100.0 * (1.0 - scc_per_tree_year(e[:down_s] + 1.0) / scc_per_tree_year(delta_t_s)) if e[:down_s]
  down = e[:down_s] && format("+%.0f с до %d→%d (−%.0f %% SCC)", e[:down_s] - delta_t_s, e[:wire], e[:wire] - 1, drop)
  up = e[:up_s] && format("−%.0f с до %d→%d", delta_t_s - e[:up_s], e[:wire], e[:wire] + 1)
  "сходинка wire-GP #{e[:wire]}: " + [ up, down || "підлога — нижче сходинок немає" ].compact.join(" · ")
end

# CO₂-еквівалент (BIZ.1, on-chain): 2000 SCC = 1 tCO₂ = 0.5 kg/SCC — canonical
# (ProtocolParameters.sol#sccPerTonneCo2() default + SystemParameter + doc 00_04 §3 · 02_06 §7.1).
SCC_PER_TONNE_CO2 = 2000

variant_c_s = VARIANT_C_S
ARGV.each do |arg|
  next unless arg.include?("=")

  key, val = arg.split("=", 2)
  abort("невідомий параметр: #{key} (є: variant_c_s)") unless key == "variant_c_s"
  variant_c_s = Float(val)
end
variant_c_h = (variant_c_s / 3600.0).round(2)

realistic = scc_per_tree_year(variant_c_s)     # робоча точка (дефолт: Variant C, 7027 с ≈ 1.95 год)
ceiling   = scc_per_tree_year(DELTA_T_FAST_S)  # фізична стеля recharge (Δt=600s)
co2_kg_year = realistic * 1000.0 / SCC_PER_TONNE_CO2  # kg CO₂ / tree / year (realistic)

if ARGV.include?("--assert")
  errors = []
  # 1. Self-consistency — пін ФОРМУЛИ, не величини робочої точки: на Δt = 3600 с пакетів 24 і
  #    stored-GP 38 (рівно приклад шапки, що спростовує «24 × 50»), тобто 33.288 SCC. Літерали —
  #    свідомо: очікування, пораховане тією самою формулою, не впало б ніколи.
  #    ⛔ Доти тут стояло вікно [5, 15] на РОБОЧІЙ точці: воно стояло за 0.39 SCC від легітимного
  #    значення й падало на 7074 с (сходинка wire 6 → 5, stored-GP 12 → 10) і на CCM-точці 8006 с з діагнозом «self-consistency
  #    зламано», хоча ламалась не формула, а точка (адверсарне ревʼю 2026-09-26 · ⚖️ делеговано
  #    2026-09-27, 00_07 ARCH.8). Рух робочої точки судить tx_cadence_budget.rb --assert.
  errors << "stored GP на Δt=3600 с = #{stored_gp_per_packet(3600)} ≠ 38 — формула Δt → m → wire зламана" \
    unless stored_gp_per_packet(3600) == 38
  errors << format("SCC на Δt=3600 с = %.3f ≠ 33.288 — packets×GP більше не з одного Δt", scc_per_tree_year(3600)) \
    unless (scc_per_tree_year(3600) - 33.288).abs < 0.001
  # 2. Anti-over-mint стеля: рекордний recharge (Δt=600s) ≤ фізичний максимум.
  errors << "ceiling=#{ceiling.round} > 400 SCC/tree/year — over-mint (перевір ×upscale / GP_MAX)" \
    if ceiling > 400
  # 3. Арбітр 05_03 MAX_SUPPLY-деривації має лежати у [realistic, ceiling].
  errors << "арбітр 50 поза [#{realistic.round},#{ceiling.round}] — economics↔MAX_SUPPLY divergence" \
    unless (realistic..ceiling).cover?(ARBITER_SCC_YEAR)
  # 5. Дзеркало realistic у стрес-моделі емісії: вона бере це число константою, і доти
  #    воно розходилось із цим файлом мовчки (7.92 там жило після руху робочої точки тут).
  #    Звіряється лише на ДЕФОЛТІ: override моделює іншу точку, а дзеркало — дефолтну.
  if variant_c_s == VARIANT_C_S
    stress = File.read(File.expand_path("../tokenomics/supply_stress.rb", __dir__))
    mirror = stress[/^REALISTIC_SCC_PER_TREE_YEAR\s*=\s*([\d.]+)/, 1]
    if mirror.nil?
      errors << "tokenomics/supply_stress.rb: константу REALISTIC_SCC_PER_TREE_YEAR не знайдено — дзеркало зникло"
    elsif (Float(mirror) - realistic).abs > 0.01
      errors << "tokenomics/supply_stress.rb REALISTIC_SCC_PER_TREE_YEAR=#{mirror} ≠ realistic #{realistic.round(2)} — " \
                "стрес-модель рахує емісію з протухлої робочої точки"
    end
  end
  # 4. CO₂-const parity (BIZ.1 on-chain): canonical-lock 2000 SCC/tCO₂.
  errors << "SCC_PER_TONNE_CO2=#{SCC_PER_TONNE_CO2} ≠ 2000 (BIZ.1 on-chain divergence)" \
    unless SCC_PER_TONNE_CO2 == 2000
  if errors.empty?
    puts "✅ scc_rate: realistic(Δt=#{variant_c_h}h)=#{realistic.round(1)} (#{step_note(variant_c_s)}) · " \
         "ceiling(Δt=600s)=#{ceiling.round} · арбітр(05_03)=#{ARBITER_SCC_YEAR.to_i} SCC/tree/year " \
         "(magnitude calibration-pending, E.63)"
    exit 0
  end
  warn "❌ scc_rate FAIL:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
else
  puts "SCC/tree/year — realistic(Δt=#{variant_c_h}h)=#{realistic.round(2)}, ceiling(Δt=600s)=#{ceiling.round}"
  puts "stored GP/packet — Variant-C=#{stored_gp_per_packet(variant_c_s)}, FAST=#{stored_gp_per_packet(DELTA_T_FAST_S)}"
  puts "робоча точка — #{step_note(variant_c_s)}"
  puts "арбітр 05_03 MAX_SUPPLY → #{ARBITER_SCC_YEAR.to_i} SCC/tree/year (у діапазоні)"
  puts "CO₂ kg/tree/year (realistic) — #{co2_kg_year.round(1)} (2000 SCC = 1 tCO₂, BIZ.1)"
end
