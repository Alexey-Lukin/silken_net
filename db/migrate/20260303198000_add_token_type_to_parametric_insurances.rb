# frozen_string_literal: true

class AddTokenTypeToParametricInsurances < ActiveRecord::Migration[8.1]
  def change
    # Тип токена виплати, який інвестор обирає при підписанні страхового контракту.
    # 0 = carbon_coin (SCC), 1 = forest_coin (SFC).
    # За замовчуванням carbon_coin для зворотної сумісності з існуючими контрактами.
    add_column :parametric_insurances, :token_type, :integer, default: 0, null: false
  end
end
