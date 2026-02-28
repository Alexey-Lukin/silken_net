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
    installation: 0,   # Первинне встановлення (мінтинг ключа)
    inspection: 1,     # Плановий обхід
    cleaning: 2,       # Очищення сонячної панелі або контактів
    repair: 3,         # Заміна плати / пайка в полі
    decommissioning: 4 # Демонтаж вбитого дерева / шлюзу
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :action_type, :performed_at, presence: true
  validates :notes, presence: true, length: { minimum: 10 }

  # --- СКОУПИ ---
  scope :recent, -> { order(performed_at: :desc) }

  # =========================================================================
  # КОЛБЕКИ (The Healing Protocol)
  # =========================================================================
  # Використовуємо after_commit, щоб гарантувати, що запис успішно зберігся в БД
  after_commit :heal_ecosystem!, on: :create

  private

  def heal_ecosystem!
    # Використовуємо транзакцію для групового оновлення
    ActiveRecord::Base.transaction do
      
      # 1. ОСВІЖЕННЯ ПУЛЬСУ
      # Якщо це Шлюз (Gateway) або він має метод mark_seen!
      if maintainable.respond_to?(:mark_seen!)
        maintainable.mark_seen!
      end

      # 2. РЕАНІМАЦІЯ АКТУАТОРІВ
      # Якщо ми відремонтували Актуатор, повертаємо його в стрій
      if maintainable.is_a?(Actuator) && maintainable.state_maintenance_needed? && action_type_repair?
        maintainable.update!(state: :idle)
        Rails.logger.info "⚙️ [MAINTENANCE] Актуатор #{maintainable.name} успішно відремонтовано та переведено в IDLE."
      end

      # 3. ЗАКРИТТЯ ІНЦИДЕНТУ (EWS Alert)
      # Якщо ремонт був прив'язаний до тривоги, і тривога ще активна
      if ews_alert.present? && !ews_alert.resolved?
        ews_alert.update!(
          status: :resolved, 
          resolved_at: Time.current,
          resolved_by: user.id,
          resolution_notes: "Автоматично закрито після #{action_type} (#{self.id}). Нотатки: #{notes}"
        )
        Rails.logger.info "🚨 [EWS] Тривогу ##{ews_alert.id} закрито завдяки втручанню патрульного #{user.email_address}."
      end
      
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [MAINTENANCE] Помилка протоколу відновлення: #{e.message}"
    raise e
  end
end
