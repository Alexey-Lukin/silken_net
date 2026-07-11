# frozen_string_literal: true

# [ARCH.56 (b), дожим] change_column :numeric→numeric(24,6) тихо no-op'нувся
# (same base type) і squash зафіксував bare numeric — явний SQL не залишає
# Rails-у простору для тлумачень. Ловить review-агент канон↔schema.
class FixBlockchainAmountPrecision < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute "ALTER TABLE blockchain_transactions ALTER COLUMN amount TYPE numeric(24,6)"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE blockchain_transactions ALTER COLUMN amount TYPE numeric"
    end
  end
end
