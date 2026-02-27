# frozen_string_literal: true

class ParametricInsurance < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :organization # Страхова компанія (напр. Swiss Re або децентралізований пул)
  belongs_to :cluster      # Лісовий масив, що знаходиться під моніторингом

  # --- СТАТУСИ ТА ТРИГЕРИ ---
  enum :status, { active: 0, triggered: 1, paid: 2, expired: 3 }, prefix: true
  enum :trigger_event, { critical_fire: 0, extreme_drought: 1, insect_epidemic: 2 }

  # --- ВАЛІДАЦІЇ ---
  validates :payout_amount, :threshold_value, presence: true
  validates :threshold_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  # Поліморфний зв'язок: виплата буде зафіксована в блокчейні як джерело (sourceable)
  has_one :blockchain_transaction, as: :sourceable

  # =========================================================================
  # АВТОНОМНИЙ ОРАКУЛ (D-MRV Integration)
  # =========================================================================
  # Цей метод викликається воркером DailyAggregationWorker після стиснення телеметрії.
  def evaluate_daily_health!(target_date = Date.yesterday)
    return unless status_active?

    # 1. Отримуємо вердикт від нашого ШІ-Оракула (AiInsight)
    # Рахуємо відсоток дерев у кластері, які вчора мали статус :anomaly або :stress
    total_trees = cluster.trees.count
    return if total_trees.zero?

    anomalous_insights = AiInsight.where(
      analyzable: cluster.trees,
      analyzed_date: target_date,
      stress_index: 0.8..1.0 # Поріг критичного стану
    ).count

    current_anomalous_percentage = (anomalous_insights.to_f / total_trees * 100).round(2)

    # 2. Перевірка тригера
    if current_anomalous_percentage >= threshold_value
      activate_payout!(current_anomalous_percentage)
    end
  end

  private

  def activate_payout!(percentage)
    transaction do
      update!(status: :triggered)
      
      # Створюємо системне повідомлення для всіх стейкхолдерів
      Rails.logger.warn "💸 [INSURANCE] Тригер активовано! Пошкодження: #{percentage}%. Очікується виплата."

      # ЗАПУСК WEB3 ВОРКЕРА
      # Він виконає переказ стейблкоїнів (USDC/USDT) на гаманець організації-власника
      InsurancePayoutWorker.perform_async(self.id)
    end
  end
end
