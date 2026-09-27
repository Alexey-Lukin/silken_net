# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.8 · E.63] Метаболічне квантування балів — ОДИН дім арифметики `Δt → m → wire-GP → SCC`,
# яку доти несли три прилади порізно: `scc_rate.rb` (значення), `uncertainty_budget.rb` (точність)
# і `tx_cadence_budget.rb` (грошова робоча точка ⊥ енергомодель). Дзеркало прошивки —
# `metabolic_health` у firmware/bio_contracts/bio_contract.rb (канон 03_04 §4.3).
#
# ⛔ ЧОМУ ЦЕ БІБЛІОТЕКА, А НЕ ЧЕТВЕРТА КОПІЯ. Гроші квантовані: 5-бітний wire-GP сходинками, тож
# гейт, що судить робочу точку ВІДСОТКОМ Δt, сліпий до сходинки — ±8 % у Δt біля 7027 с дають
# −23…+45 % у SCC, бо сходинка wire 6 → 5 (stored-GP 12 → 10) лежить за 46 с від точки (00_07 ARCH.8, ⚖️ делеговано
# 2026-09-27). Судити відстань до сходинки можна лише тим самим кодом, що рахує бали, — інакше
# гейт і модель розійдуться саме на межі, заради якої гейт існує.
#
# ⛔ ФУНКЦІЇ БЕРУТЬ ІМЕНОВАНІ АРГУМЕНТИ, І КАНОН-ЧИСЕЛ ТУТ НЕМАЄ — дзеркало `energy_chain.rb`:
# межі смуги, wire і поріг емісії живуть у домі приладу, що їх подає (`scc_rate.rb` для грошей,
# `PARAMS` сусідів для їхніх питань), а їхню відповідність канону доводять `--assert`-и ТАМ.
module SilkenGrowthSteps
  module_function

  def metabolic_m(delta_t_s:, fast_s:, slow_s:)
    ((slow_s - delta_t_s).to_f / (slow_s - fast_s)).clamp(0.0, 1.0)
  end

  # Неокруглений wire несе чутливість (uncertainty_budget.rb рахує квантування окремою складовою);
  # округлений — те, що їде дротом. Округлення — Float#round, тобто половина вгору.
  def wire_exact(delta_t_s:, fast_s:, slow_s:, gp_min:, gp_max:)
    gp_min + metabolic_m(delta_t_s: delta_t_s, fast_s: fast_s, slow_s: slow_s) * (gp_max - gp_min)
  end

  def wire_gp(**band) = wire_exact(**band).round

  # Сходинка wire-GP, на якій стоїть Δt: `down_s` — Δt, за яким wire падає на 1 (nil на підлозі
  # `gp_min`), `up_s` — Δt, нижче якого wire росте на 1 (nil на стелі `gp_max`).
  def step_edges(delta_t_s:, fast_s:, slow_s:, gp_min:, gp_max:)
    w = wire_gp(delta_t_s: delta_t_s, fast_s: fast_s, slow_s: slow_s, gp_min: gp_min, gp_max: gp_max)
    edge = ->(wire) { slow_s - (wire - gp_min).to_f / (gp_max - gp_min) * (slow_s - fast_s) }
    { wire: w, down_s: (w > gp_min ? edge.call(w - 0.5) : nil), up_s: (w < gp_max ? edge.call(w + 0.5) : nil) }
  end

  # SCC/дерево/рік: пакети на добу × бали на пакет, де бал нараховується НА ПАКЕТ.
  def scc_per_tree_year(delta_t_s:, stored_gp:, threshold:)
    365.0 * (86_400.0 / delta_t_s) * stored_gp / threshold
  end
end
