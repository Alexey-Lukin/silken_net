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

  scope :active_contracts, -> { where(status: :active) }

  # =========================================================================
  # THE SLASHING PROTOCOL (D-MRV Арбітраж)
  # =========================================================================
  # Викликається щоночі після роботи InsightGeneratorService
  def check_cluster_health!
    return unless status_active?

    total_trees_count = cluster.trees.count
    return if total_trees_count.zero?

    # [ОПТИМІЗАЦІЯ]: Замість мільйонів логів, ми опитуємо "Оракула" (AiInsight)
    # Шукаємо дерева, які вчора мали статус Аномалії (2) або Вандалізму (3)
    critical_insights_count = AiInsight.where(
      analyzable: cluster.trees,
      analyzed_date: Date.yesterday,
      stress_index: 1.0 # Наш показник повної аномалії/смерті
    ).count

    # Математична межа порушення контракту
    # $$ \text{anomalous\_ratio} = \frac{\text{critical\_insights}}{\text{total\_trees}} $$
    if critical_insights_count > (total_trees_count * 0.20)
      activate_slashing_protocol!
    end
  end

  private

  def activate_slashing_protocol!
    transaction do
      update!(status: :breached)

      # Залишаємо відбиток для аудиторів
      Rails.logger.warn "🚨 [D-MRV] NaasContract #{id} РОЗІРВАНО. Критичне пошкодження сектору."

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
