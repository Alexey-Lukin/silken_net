# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.95] Друга половина кроку 2б: попередня міграція поставила `wallets_balance_invariants` як
# `NOT VALID`, і тут обмеження перевіряє наявні рядки окремою транзакцією.
class ValidateWalletsBalanceInvariants < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :wallets, name: "wallets_balance_invariants"
  end

  # Відкат попередньої міграції ставить обмеження одразу валідним, тож тут скасовувати нічого.
  def down; end
end
