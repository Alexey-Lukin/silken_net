# frozen_string_literal: true

class EnhanceActuatorCommandsResilience < ActiveRecord::Migration[8.1]
  def change
    change_table :actuator_commands do |t|
      # 🛡️ Idempotency: UUID щоб STM32 ігнорував повтори одного наказу
      t.uuid :idempotency_token, null: false

      # 🚦 Priority: 0=low (плановий полив), 1=medium (діагностика), 2=high (EWS)
      t.integer :priority, null: false, default: 0

      # ⏱️ TTL: команда без терміну придатності може стати шкідливою
      t.datetime :expires_at

      # 📈 Денормалізація: усуваємо N+1 JOIN actuator->gateway->cluster->organization
      t.references :organization, foreign_key: true
    end

    add_index :actuator_commands, :idempotency_token, unique: true
    add_index :actuator_commands, :priority
    add_index :actuator_commands, :expires_at, where: "status IN (0, 1)"
  end
end
