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
    fulfilled: 2,  # Успішне завершення (Audit pass)
    breached: 3    # ПОРУШЕНО (Slashing Protocol активовано)
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :total_funding, presence: true, numericality: { greater_than: 0 }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  # --- СКОУПИ ---
  # [СИНХРОНІЗОВАНО]: Уніфікована назва для системної єдності
  scope :active, -> { status_active }

  # [ВИПРАВЛЕНО]: Фінансовий дедлайн.
  # Контракт активний до останньої секунди вказаного дня.
  scope :pending_completion, -> { active.where("end_date < ?", Date.current) }

  # =========================================================================
  # THE SLASHING PROTOCOL (D-MRV Арбітраж)
  # =========================================================================

  # [ВИПРАВЛЕНО]: Вигнання "Мертвих Душ".
  # Ми розраховуємо здоров'я лише за тими "Солдатами", що стоять у строю.
  def check_cluster_health!(target_date = Date.yesterday)
    return unless status_active?

    # Рахуємо лише активні дерева, ігноруючи deceased та removed
    active_trees = cluster.trees.active
    total_active_count = active_trees.count

    return if total_active_count.zero?

    # Аналізуємо вердикти Оракула (AiInsight)
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable: active_trees,
      target_date: target_date
    )

    # Якщо Оракул мовчав цілу добу — це сигнал глобальної аварії зв'язку (Starlink-блекаут).
    # Відсутність даних > 24 год автоматично вважається порушенням контракту.
    if daily_insights.empty?
      activate_slashing_protocol!
      return
    end

    # Рахуємо критичні аномалії серед живих
    critical_insights_count = daily_insights.where("stress_index >= 1.0").count

    # Математична межа порушення контракту (20% від активної біомаси)
    # $$HealthRatio = \frac{\sum \text{ActiveTrees with Stress} \ge 1.0}{\text{TotalActiveTrees}}$$
    if critical_insights_count > (total_active_count * 0.20)
      activate_slashing_protocol!
    end
  end

  private

  # [ВИПРАВЛЕНО]: Ліквідація Race Condition.
  # Тепер BurnCarbonTokensWorker гарантовано бачить статус :breached у базі.
  def activate_slashing_protocol!
    # Змінюємо стан у межах атомарної транзакції
    breach_confirmed = transaction do
      update!(status: :breached)
      true
    rescue StandardError => e
      Rails.logger.error "🛑 [D-MRV] Провал активації Slashing для контракту ##{id}: #{e.message}"
      false
    end

    # Воркер стає на крило ТІЛЬКИ після успішного COMMIT у PostgreSQL
    if breach_confirmed
      Rails.logger.warn "🚨 [D-MRV] NaasContract ##{id} РОЗІРВАНО. Сигнал на Slashing відправлено."

      # Web3-екзекутор тепер не зустріне "привида" зі статусом :active
      BurnCarbonTokensWorker.perform_async(self.organization_id, self.id)
    end
  end

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    errors.add(:end_date, "повинна бути пізніше дати початку") if end_date < start_date
  end
end
