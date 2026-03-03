# frozen_string_literal: true

class AddLockedPointsToBlockchainTransactions < ActiveRecord::Migration[8.1]
  def change
    # Кількість балів гомеостазу, заблокованих у момент створення транзакції.
    # Зберігаємо snapshot, щоб ролбек повертав рівно стільки балів, скільки було списано,
    # незалежно від майбутніх змін TokenomicsEvaluatorWorker::EMISSION_THRESHOLD.
    add_column :blockchain_transactions, :locked_points, :integer
  end
end
