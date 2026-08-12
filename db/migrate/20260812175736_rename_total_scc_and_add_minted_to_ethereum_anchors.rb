# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.97] Якір підписував БАЛИ як «SCC supply» — і не сходився сам із собою.
#
# 1. ОДИНИЦЯ. `total_scc` тримав `Wallet.sum(:scc_balance)`, а це alias на колонку
#    `balance` з growth_points, тоді як сусідній `total_sfc` того самого дайджесту
#    несе справжні confirmed-мінти. Одна криптографічна обіцянка змішувала дві
#    одиниці. Ренейм, а НЕ перевизначення змісту наявної колонки: інакше одне ім'я
#    вказувало б на різний зміст у різні епохи — рівно той клас, який лікуємо.
#
# 2. ШКАЛА (виміряно рантаймом). Обидва джерела доказових величин —
#    `wallets.balance` і `blockchain_transactions.amount` — це `numeric(24,6)`, а
#    колонка якоря була `numeric(30,4)`. `generate_state_root` хешує НЕокруглене
#    значення в leaf0, а `verify_state_root` перераховує зі ЗБЕРЕЖЕНОЇ (округленої)
#    колонки → для чесного якоря з 6-знаковим джерелом верифікація віддавала
#    **false назавжди**. Доведено: 1000.123456 зберігалось як 1000.1235, і
#    наскрізна проба дала `verify_state_root -> false`. Тож шкала доказових колонок
#    дорівнює шкалі ДЖЕРЕЛ — розходження стає нерепрезентовним, а не залатаним.
#
# `safety_assured` свідомо: pre-launch (нуль якорів, контракт не задеплоєно — SEC.1),
# тож «rename ламає живий код» не має суб'єкта; єдиний письменник колонки —
# `Ethereum::StateAnchorService`, і він їде цим самим комітом.
class RenameTotalSccAndAddMintedToEthereumAnchors < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      rename_column :ethereum_anchors, :total_scc, :total_growth_points
      change_column :ethereum_anchors, :total_growth_points, :decimal, precision: 30, scale: 6, null: false
    end

    # Справжній SCC-supply — дзеркало on-chain `totalSupply()`: Σ(mints) − Σ(burns).
    # Ім'я каже «supply», а не «minted», бо величина НЕ кумулятивна: slash її зменшує.
    add_column :ethereum_anchors, :total_scc_supply, :decimal,
               precision: 30, scale: 6, null: false, default: 0
  end

  def down
    remove_column :ethereum_anchors, :total_scc_supply
    safety_assured do
      change_column :ethereum_anchors, :total_growth_points, :decimal, precision: 30, scale: 4, null: false
      rename_column :ethereum_anchors, :total_growth_points, :total_scc
    end
  end
end
