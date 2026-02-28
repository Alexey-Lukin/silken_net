# frozen_string_literal: true

class ActuatorCommand < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :actuator
  # Команда може бути частиною автоматичної відповіді на тривогу
  belongs_to :ews_alert, optional: true
  # Також фіксуємо, який саме адміністратор/лісник віддав наказ вручну
  belongs_to :user, optional: true

  # --- СТАТУСИ (The Lifecycle of a Command) ---
  enum :status, {
    issued: 0,       # Створено, чекає на обробку
    sent: 1,         # Відправлено в ефір (CoapClient)
    acknowledged: 2, # Отримано підтвердження (ACK) від шлюзу
    failed: 3,       # Помилка зв'язку або шифрування
    confirmed: 4     # Успішно завершено (кенозис стану виконано)
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :command_payload, presence: true
  validates :duration_seconds, presence: true,
                               numericality: { greater_than: 0, less_than_or_equal_to: 3600 }

  # --- КОЛБЕКИ (The Spark of Action) ---
  # Запускаємо воркер ТІЛЬКИ після успішного збереження в БД
  after_commit :dispatch_to_edge!, on: :create

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :pending, -> { where(status: [ :issued, :sent ]) }

  # =========================================================================
  # БІЗНЕС-ЛОГІКА
  # =========================================================================

  # Розрахунок очікуваного часу завершення для UI
  def estimated_completion_at
    return nil unless sent_at
    sent_at + duration_seconds.seconds
  end

  private

  def dispatch_to_edge!
    # [СИНХРОНІЗОВАНО]: Перевірка готовності актуатора та шлюзу
    if actuator.ready_for_deployment?
      ActuatorCommandWorker.perform_async(self.id)
    else
      # Якщо шлюз офлайн або актуатор на ремонті — миттєва капітуляція
      transaction do
        update_columns(status: self.class.statuses[:failed])
        # Логуємо причину для патрульного
        Rails.logger.warn "🛑 [COMMAND] Спроба активації ##{id} провалена: Актуатор #{actuator.name} недоступний."
      end
    end
  end
end
