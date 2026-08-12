# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.97] Третє поле того самого дайджесту лишилось на СТАРІЙ шкалі.
#
# Попередня міграція (`20260812175736`) звела `total_growth_points` і
# `total_scc_supply` до шкали їхніх ДЖЕРЕЛ — `numeric(24,6)`. `total_sfc`
# лишився `numeric(30,4)`, хоч сидить у ТОМУ САМОМУ хешованому рядку
# (`EthereumAnchor.aggregate_payload`) і має те саме джерело: суму
# `blockchain_transactions.amount`, тобто теж `numeric(24,6)`.
#
# Тобто фікс самофальсифікації був полагоджений на двох сайтах із трьох, а
# третій лишався захищеним ЗБІГОМ — тим, що mint пише `tokens_to_mint`
# (ціле). Збіг не тримає: SFC потрапляє в `blockchain_transactions` ще й
# страховим трактом — `InsurancePayoutWorker` пише `amount:
# insurance.payout_amount` з `token_type: insurance.token_type`, а
# `parametric_insurances.payout_amount` — голий `numeric` БЕЗ обмеження
# точності (сума рахується як `damage_ratio × insured_value`, тобто дробова
# за побудовою). Одна така виплата → 6-значний `total_sfc` → колонка ріже
# два знаки → `verify_state_root` віддає **false для чесного якоря**.
#
# Виміряно SQL: `SELECT 3.000003::numeric(30,4)` → `3.0000`.
#
# `safety_assured`: pre-launch (нуль якорів, контракт не задеплоєно — SEC.1).
class AlignTotalSfcScaleOnEthereumAnchors < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      change_column :ethereum_anchors, :total_sfc, :decimal, precision: 30, scale: 6, default: 0
    end
  end

  def down
    safety_assured do
      change_column :ethereum_anchors, :total_sfc, :decimal, precision: 30, scale: 4, default: 0
    end
  end
end
