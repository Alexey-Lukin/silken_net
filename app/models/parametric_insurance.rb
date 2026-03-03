# frozen_string_literal: true

class ParametricInsurance < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Організація-страховик (напр. Swiss Re або децентралізований пул)
  belongs_to :organization
  belongs_to :cluster      # Лісовий масив під захистом Aegis

  # --- СТАТУСИ ТА ТРИГЕРИ ---
  enum :status, { active: 0, triggered: 1, paid: 2, expired: 3 }, prefix: true
  enum :trigger_event, { critical_fire: 0, extreme_drought: 1, insect_epidemic: 2 }

  # Тип токена виплати — обирається інвестором при підписанні контракту
  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :payout_amount, :threshold_value, presence: true
  validates :threshold_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  # Поліморфний зв'язок: виплата буде зафіксована в блокчейні
  has_one :blockchain_transaction, as: :sourceable

  # =========================================================================
  # АВТОНОМНИЙ ОРАКУЛ (D-MRV Integration)
  # =========================================================================
  # Цей метод викликається воркером DailyAggregationWorker
  def evaluate_daily_health!(target_date = Date.yesterday)
    return unless status_active?

    # 1. Отримуємо вердикт від нашого ШІ-Оракула (AiInsight)
    total_trees_count = cluster.trees.count
    return if total_trees_count.zero?

    # [СИНХРОНІЗОВАНО]: Використовуємо target_date та insight_type
    anomalous_insights = AiInsight.daily_health_summary.where(
      analyzable: cluster.trees,
      target_date: target_date,
      stress_index: 0.8..1.0 # Поріг критичного стану / пожежі
    ).count

    # Математика тригера:
    # $$ \text{damage\_ratio} = \frac{\text{anomalous\_insights}}{\text{total\_trees}} \times 100 $$
    current_anomalous_percentage = (anomalous_insights.to_f / total_trees_count * 100).round(2)

    # 2. Перевірка тригера
    if current_anomalous_percentage >= threshold_value
      activate_payout!(current_anomalous_percentage)
    end
  end

  # [НОВЕ]: Визначаємо гаманець отримувача (Власника лісу)
  def recipient_wallet_address
    cluster.organization.crypto_public_address
  end

  private

  def activate_payout!(percentage)
    transaction do
      update!(status: :triggered)

      # Створюємо системний запис для аудиторів та патрульних
      Rails.logger.warn "💸 [INSURANCE] Тригер ##{id} активовано! Пошкодження сектора: #{percentage}%."

      # ЗАПУСК WEB3 ВОРКЕРА
      # Він виконає переказ USDC/USDT на адресу recipient_wallet_address
      InsurancePayoutWorker.perform_async(self.id)
    end
  end
end
