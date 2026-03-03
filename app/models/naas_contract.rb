# frozen_string_literal: true

class NaasContract < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :organization
  belongs_to :cluster

  alias_attribute :total_value, :total_funding

  # --- СТАТУСИ (The Lifecycle of Trust) ---
  enum :status, {
    draft: 0,      # Підготовка, очікування транзакції інвестора
    active: 1,     # Контракт у силі, емісія токенів дозволена
    fulfilled: 2,  # Успішне завершення
    breached: 3    # ПОРУШЕНО (Slashing Protocol активовано)
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :total_funding, presence: true, numericality: { greater_than: 0 }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  # --- СКОУПИ ---
  scope :active_contracts, -> { status_active }
  
  # [ВИПРАВЛЕНО]: Фінансовий дедлайн. 
  # Контракт вважається завершеним лише після того, як вказана дата повністю минула.
  scope :pending_completion, -> { active_contracts.where("end_date < ?", Date.current) }

  # =========================================================================
  # THE SLASHING PROTOCOL (D-MRV Арбітраж)
  # =========================================================================
  
  # [ВИПРАВЛЕНО]: Вигнання "Мертвих Душ". 
  # Тепер аналізуємо лише живі дерева на момент проведення аудиту.
  def check_cluster_health!(target_date = Date.yesterday)
    return unless status_active?

    # Рахуємо лише активні дерева (active), ігноруючи deceased та removed
    active_trees = cluster.trees.active
    total_active_count = active_trees.count
    
    return if total_active_count.zero?

    # Шукаємо інсайти саме для активних дерев
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable: active_trees,
      target_date: target_date
    )

    return if daily_insights.empty?

    # Рахуємо критичні аномалії серед живих (stress_index 1.0 = агонія/вандалізм)
    critical_insights_count = daily_insights.where("stress_index >= 1.0").count

    # Математична межа порушення контракту (20% від активної біомаси)
    if critical_insights_count > (total_active_count * 0.20)
      activate_slashing_protocol!
    end
  end

  private

  # [ВИПРАВЛЕНО]: Ліквідація Race Condition.
  # Ми розділяємо оновлення бази даних та запуск асинхронного воркера.
  def activate_slashing_protocol!
    # Використовуємо транзакцію лише для зміни стану
    breach_confirmed = transaction do
      update!(status: :breached)
      true
    rescue StandardError => e
      Rails.logger.error "🛑 [D-MRV] Провал активації Slashing для контракту ##{id}: #{e.message}"
      false
    end

    # Воркер запускається ТІЛЬКИ після успішного завершення транзакції (COMMIT)
    if breach_confirmed
      Rails.logger.warn "🚨 [D-MRV] NaasContract ##{id} РОЗІРВАНО. Сигнал на вилучення капіталу відправлено."
      
      # Тепер BurnCarbonTokensWorker гарантовано побачить статус :breached у базі
      BurnCarbonTokensWorker.perform_async(self.organization_id, self.id)
    end
  end

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    errors.add(:end_date, "повинна бути пізніше дати початку") if end_date < start_date
  end
end
