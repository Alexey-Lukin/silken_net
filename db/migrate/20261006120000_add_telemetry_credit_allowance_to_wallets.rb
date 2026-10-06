# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [E.64, ⚖️ founder 2026-10-05/06] Відро ліміту зарахування телеметрії на дерево: ліміт
# росте зі ставкою частки MAX_SUPPLY на дерево (≈ 1 370 балів/добу) і тримає не більше
# 30 діб. Стан — два стовпці гаманця: залишок ліміту в БАЛАХ (numeric(24,6), як balance)
# і мить, до якої його нараховано. NULL = гаманець ще не отримував бал телеметрії
# (перше зарахування дістає ліміт однієї доби). Механіка — `Wallet#credit_telemetry!`.
class AddTelemetryCreditAllowanceToWallets < ActiveRecord::Migration[8.1]
  def change
    add_column :wallets, :credit_allowance_points, :decimal, precision: 24, scale: 6
    add_column :wallets, :credit_allowance_at, :datetime
  end
end
