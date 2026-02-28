# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :user
  belongs_to :maintainable, polymorphic: true
  belongs_to :ews_alert, optional: true

  # Фотодокази для аудиту інвесторами (Silken Net Trust Protocol)
  # has_many_attached :photos

  # --- ТИПИ РОБІТ (The Intervention) ---
  enum :action_type, {
    installation: 0,    # Монтаж
    inspection: 1,      # Огляд
    cleaning: 2,        # Очищення (панелі/датчики)
    repair: 3,          # Ремонт заліза
    decommissioning: 4  # Демонтаж
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :action_type, :performed_at, presence: true
  validates :notes, presence: true, length: { minimum: 10 }
  validates :performed_at, comparison: { less_than_or_equal_to: -> { Time.current } }

  # --- СКОУПИ ---
  scope :recent, -> { order(performed_at: :desc) }
  scope :by_type, ->(type) { where(action_type: type) }

  # =========================================================================
  # КОЛБЕКИ (The Healing Protocol)
  # =========================================================================
  after_commit :heal_ecosystem!, on: :create

  private

  def heal_ecosystem!
    # Використовуємо ізольовану транзакцію для фіналізації станів
    ActiveRecord::Base.transaction do
      # 1. ОСВІЖЕННЯ ПУЛЬСУ
      # Актуалізуємо час останньої активності об'єкта
      maintainable.mark_seen! if maintainable.respond_to?(:mark_seen!)

      # 2. РЕАНІМАЦІЯ ПЕРИФЕРІЇ
      # [СИНХРОНІЗОВАНО]: Використовуємо mark_idle! для актуаторів
      if maintainable.is_a?(Actuator) && action_type_repair?
        maintainable.mark_idle!
      end

      # 3. ЖИТТЄВИЙ ЦИКЛ ОБ'ЄКТА
      # Якщо це дерево, і ми його демонтували — фіксуємо фінал
      if maintainable.is_a?(Tree) && action_type_decommissioning?
        maintainable.update!(status: :removed)
      end

      # 4. ЗАКРИТТЯ ІНЦИДЕНТУ (EWS Alert)
      # [СИНХРОНІЗОВАНО]: Автоматичне вирішення тривоги
      if ews_alert.present? && !ews_alert.resolved?
        resolution_msg = "🔧 Відновлено: #{action_type.humanize}. Запис ##{id}. Нотатки: #{notes.truncate(100)}"
        ews_alert.resolve!(user: user, notes: resolution_msg)
      end
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [MAINTENANCE FAILURE] Помилка зцілення ##{id}: #{e.message}"
    # Ми не зупиняємо потік, але фіксуємо збій у Error Tracker
  end
end
