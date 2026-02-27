# frozen_string_literal: true

class ActuatorCommand < ApplicationRecord
  belongs_to :actuators
  belongs_to :ews_alert, optional: true # Команда може бути і ручною від лісника

  enum :status, {
    issued: 0,    # Створено в БД
    sent: 1,      # Відправлено Королеві через CoAP
    acknowledged: 2, # Отримано підтвердження (ACK) від пристрою
    failed: 3     # Помилка доставки
  }, prefix: true

  validates :command_payload, :duration_seconds, presence: true
end
