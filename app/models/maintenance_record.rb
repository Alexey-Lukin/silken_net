# frozen_string_literal: true

class MaintenanceRecord < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Хто проводив роботи (Патрульний / Інженер)
  belongs_to :user
  
  # Об'єкт обслуговування: Tree, Gateway або Actuator
  belongs_to :maintainable, polymorphic: true
  
  # Тривога, яка стала причиною виїзду (Оракул покликав людину)
  belongs_to :ews_alert, optional: true

  # --- ТИПИ РОБІТ (The Intervention) ---
  enum :action_type, {
    installation: 0,    # Первинне встановлення (мінтинг ключа)
    inspection: 1,      # Плановий обхід
    cleaning: 2,        # Очищення сонячної панелі або контактів
    repair: 3,          # Заміна плати / пайка в полі
    decommissioning: 4  # Демонтаж вбитого дерева / шлюзу
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :action_type, :performed_at, presence: true
  validates :notes, presence: true, length: { minimum: 10 }
  # performed_at не може бути в майбутньому (Захист від помилок інтерфейсу)
  validates :performed_at, comparison: { less_than_or_equal_to: -> { Time.current } }

  # --- СКОУПИ ---
  scope :recent, -> { order(performed_at: :desc) }

  # =========================================================================
  # КОЛБЕКИ (The Healing Protocol)
  # =========================================================================
  # Використовуємо after_commit, щоб гарантувати, що запис успішно зберігся в БД
  after_commit :heal_ecosystem!, on: :create

  private

  def heal_ecosystem!
    # Оскільки after_commit поза основною транзакцією, створюємо нову для цілісності відновлення
    ActiveRecord::Base.transaction do
      
      # 1. ОСВІЖЕННЯ ПУЛЬСУ
      # Якщо об'єкт підтримує mark_seen! (Gateway/Tree), оновлюємо його timestamp
      maintainable.mark_seen! if maintainable.respond_to?(:mark_seen!)

      # 2. РЕАНІМАЦІЯ ПЕРИФЕРІЇ
      # Якщо відремонтували Актуатор — повертаємо його в стрій (IDLE)
      if maintainable.is_a?(Actuator) && action_type_repair?
        maintainable.update!(state: :idle)
        Rails.logger.info "⚙️ [MAINTENANCE] Актуатор #{maintainable.name} повернуто до життя."
      end

      # 3. ЖИТТЄВИЙ ЦИКЛ ОБ'ЄКТА
      # Якщо демонтували дерево — міняємо його статус
      if maintainable.is_a?(Tree) && action_type_decommissioning?
        maintainable.update!(status: :removed)
      end

      # 4. ЗАКРИТТЯ ІНЦИДЕНТУ (EWS Alert)
      # [СИНХРОНІЗОВАНО]: Викликаємо метод resolve!, який ми написали в моделі EwsAlert
      if ews_alert.present? && !ews_alert.resolved?
        resolution_msg = "Відновлено через #{action_type} (Запис ##{id}). Нотатки: #{notes}"
        ews_alert.resolve!(user: user, notes: resolution_msg)
      end
      
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [MAINTENANCE] Помилка протоколу відновлення ##{id}: #{e.message}"
    # У after_commit raise не скасує створення MaintenanceRecord, 
    # але сповістить розробника про збій у "загоєнні"
    raise e
  end
end
