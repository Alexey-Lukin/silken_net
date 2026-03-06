# frozen_string_literal: true

require "bigdecimal"

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
  # [Cluster TZ]: Використовуємо часовий пояс кластера для детермінованості арбітражу.
  def evaluate_daily_health!(target_date = cluster.local_yesterday)
    return unless status_active?

    # 1. Отримуємо вердикт від нашого ШІ-Оракула (AiInsight)
    # [Counter Cache]: Використовуємо денормалізований лічильник замість COUNT(*) на мільйонах дерев.
    total_trees = cluster.active_trees_count
    return if total_trees.zero?

    # [SQL Optimization]: Підзапит замість масиву об'єктів (The Polymorphic IN Trap).
    # [СИНХРОНІЗОВАНО]: Використовуємо target_date та insight_type
    anomalous_count = AiInsight.daily_health_summary.where(
      analyzable_type: "Tree",
      analyzable_id: cluster.trees.select(:id),
      target_date: target_date,
      stress_index: 0.8..1.0 # Поріг критичного стану / пожежі
    ).count

    # Математика тригера:
    # $$ \text{damage\_ratio} = \frac{\text{anomalous\_count}}{\text{total\_trees}} \times 100 $$
    # [BigDecimal]: Використовуємо точну арифметику — для страхування мікропохибка Float неприпустима.
    damage_ratio = (BigDecimal(anomalous_count.to_s) / total_trees * 100).round(2)

    # 2. Перевірка тригера
    if damage_ratio >= threshold_value
      activate_payout!(damage_ratio)
    end
  end

  # [НОВЕ]: Визначаємо гаманець отримувача (Власника лісу)
  def recipient_wallet_address
    cluster.organization.crypto_public_address
  end

  private

  def activate_payout!(percentage)
    payout_triggered = transaction do
      update!(status: :triggered)

      # Створюємо системний запис для аудиторів та патрульних
      Rails.logger.warn "💸 [INSURANCE] Тригер ##{id} активовано! Пошкодження сектора: #{percentage}%."

      true
    end

    # ЗАПУСК WEB3 ВОРКЕРА ПІСЛЯ УСПІШНОГО COMMIT
    # [Transaction Safety]: Запускаємо воркер тільки після завершення транзакції,
    # щоб уникнути Race Condition між Redis і PostgreSQL COMMIT.
    InsurancePayoutWorker.perform_async(id) if payout_triggered
  end
end
