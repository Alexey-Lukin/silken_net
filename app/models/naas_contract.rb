# frozen_string_literal: true

class NaasContract < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :organization
  belongs_to :cluster

  # --- СТАТУСИ (The Lifecycle of Trust) ---
  enum :status, {
    draft: 0,      # Підготовка, очікування транзакції інвестора
    active: 1,     # Контракт у силі, емісія токенів дозволена
    fulfilled: 2,  # Успішне завершення (напр. через 10 років)
    breached: 3    # ПОРУШЕНО (Slashing Protocol активовано)
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :total_funding, presence: true, numericality: { greater_than: 0 }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  # --- СКОУПИ ---
  scope :active_contracts, -> { status_active }
  # Контракти, термін дії яких закінчився, але вони ще не марковані як fulfilled
  scope :pending_completion, -> { active_contracts.where("end_date <= ?", Date.current) }

  # =========================================================================
  # THE SLASHING PROTOCOL (D-MRV Арбітраж)
  # =========================================================================
  # Викликається щоночі після роботи InsightGeneratorService
  def check_cluster_health!
    return unless status_active?

    total_trees_count = cluster.trees.count
    return if total_trees_count.zero?

    # [СИНХРОНІЗАЦІЯ З ОРАКУЛОМ]:
    # Використовуємо target_date та insight_type_daily_health_summary
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable: cluster.trees,
      target_date: Date.yesterday
    )

    # Якщо за вчора ще немає даних, ми не маємо права на арбітраж
    return if daily_insights.empty?

    # Рахуємо критичні аномалії (stress_index 1.0 = смерть/вандалізм)
    critical_insights_count = daily_insights.where("stress_index >= 1.0").count

    # Математична межа порушення контракту
    # anomalous_ratio = critical_insights / total_trees
    if critical_insights_count > (total_trees_count * 0.20)
      activate_slashing_protocol!
    end
  end

  private

  def activate_slashing_protocol!
    transaction do
      update!(status: :breached)

      # Залишаємо відбиток для аудиторів
      Rails.logger.warn "🚨 [D-MRV] NaasContract ##{id} РОЗІРВАНО. Критичне пошкодження сектору #{cluster.name}."

      # Активуємо воркер для спалювання токенів (Slashing)
      # Це фізично зменшує баланс інвестора в Polygon, відображаючи реальну втрату біомаси
      BurnCarbonTokensWorker.perform_async(self.organization_id, self.id)
    end
  end

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    errors.add(:end_date, "повинна бути пізніше дати початку") if end_date < start_date
  end
end
