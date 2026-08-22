# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [E.63/SCC-rate] SCC-generation rate — параметрична модель, single-source.
# Канон (02_06 §7.1 · 00_04 §3) ПОСИЛАЄТЬСЯ сюди, не restate'ить magnitude.
# Дзеркало queen_energy_budget.rb (HW.39).
#
# Pure Ruby (no Rails). Виклик:
#   ruby tools/firmware/scc_rate.rb            # звіт (realistic + ceiling + арбітр)
#   ruby tools/firmware/scc_rate.rb --assert   # гейт: self-consistency + anti-over-mint + арбітр
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

# Робоча точка delta_t: Variant C = 1.77 год, рекомендований energy-positive (02_03 §9.6).
# (1 TX/год = Δt=3600s = energy-NEGATIVE без мітигацій, 02_03 §9.5 — НЕ baseline.)
VARIANT_C_S = 6372

# Незалежний арбітр: 05_03 MAX_SUPPLY=1B ≈ 20M дерево-років ⇒ 50 SCC/tree/year.
ARBITER_SCC_YEAR = 50.0

def metabolic_m(delta_t_s)
  ((DELTA_T_SLOW_S - delta_t_s).to_f / (DELTA_T_SLOW_S - DELTA_T_FAST_S)).clamp(0.0, 1.0)
end

def stored_gp_per_packet(delta_t_s)
  wire = (GP_HOMEO_MIN + metabolic_m(delta_t_s) * (GP_HOMEO_MAX - GP_HOMEO_MIN)).round
  BACKEND_UPSCALE * wire
end

def scc_per_tree_year(delta_t_s)
  packets_day = 86_400.0 / delta_t_s
  gp_day = packets_day * stored_gp_per_packet(delta_t_s)
  365.0 / (EMISSION_THRESHOLD / gp_day)
end

# CO₂-еквівалент (BIZ.1, on-chain): 2000 SCC = 1 tCO₂ = 0.5 kg/SCC — canonical
# (ProtocolParameters.sol#sccPerTonneCo2() default + SystemParameter + doc 00_04 §3 · 02_06 §7.1).
SCC_PER_TONNE_CO2 = 2000

realistic = scc_per_tree_year(VARIANT_C_S)     # Variant C 1.77h
ceiling   = scc_per_tree_year(DELTA_T_FAST_S)  # фізична стеля recharge (Δt=600s)
co2_kg_year = realistic * 1000.0 / SCC_PER_TONNE_CO2  # kg CO₂ / tree / year (realistic)

if ARGV.include?("--assert")
  errors = []
  # 1. Self-consistency: realistic виводиться з ОДНОГО delta_t → фізичний [5,15]
  #    (ловить хардкод-drift на кшталт 44-52 з несумісних packets×GP).
  errors << "realistic=#{realistic.round(1)} поза [5,15] — delta_t/m self-consistency зламано" \
    unless (5.0..15.0).cover?(realistic)
  # 2. Anti-over-mint стеля: рекордний recharge (Δt=600s) ≤ фізичний максимум.
  errors << "ceiling=#{ceiling.round} > 400 SCC/tree/year — over-mint (перевір ×upscale / GP_MAX)" \
    if ceiling > 400
  # 3. Арбітр 05_03 MAX_SUPPLY-деривації має лежати у [realistic, ceiling].
  errors << "арбітр 50 поза [#{realistic.round},#{ceiling.round}] — economics↔MAX_SUPPLY divergence" \
    unless (realistic..ceiling).cover?(ARBITER_SCC_YEAR)
  # 4. CO₂-const parity (BIZ.1 on-chain): canonical-lock 2000 SCC/tCO₂.
  errors << "SCC_PER_TONNE_CO2=#{SCC_PER_TONNE_CO2} ≠ 2000 (BIZ.1 on-chain divergence)" \
    unless SCC_PER_TONNE_CO2 == 2000
  if errors.empty?
    puts "✅ scc_rate: realistic(Δt=1.77h)=#{realistic.round(1)} · ceiling(Δt=600s)=#{ceiling.round} · " \
         "арбітр(05_03)=#{ARBITER_SCC_YEAR.to_i} SCC/tree/year (magnitude calibration-pending, E.63)"
    exit 0
  end
  warn "❌ scc_rate FAIL:"
  errors.each { |e| warn "  - #{e}" }
  exit 1
else
  puts "SCC/tree/year — realistic(Δt=1.77h)=#{realistic.round(2)}, ceiling(Δt=600s)=#{ceiling.round}"
  puts "stored GP/packet — Variant-C=#{stored_gp_per_packet(VARIANT_C_S)}, FAST=#{stored_gp_per_packet(DELTA_T_FAST_S)}"
  puts "арбітр 05_03 MAX_SUPPLY → #{ARBITER_SCC_YEAR.to_i} SCC/tree/year (у діапазоні)"
  puts "CO₂ kg/tree/year (realistic) — #{co2_kg_year.round(1)} (2000 SCC = 1 tCO₂, BIZ.1)"
end
