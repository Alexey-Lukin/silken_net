# frozen_string_literal: true

require "bigdecimal"

class ParametricInsurance < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  # Організація-страховик (напр. Swiss Re або децентралізований пул)
  belongs_to :organization
  belongs_to :cluster      # Лісовий масив під захистом Aegis

  # =========================================================================
  # ETHERISC DIP ORACLE MODE
  # =========================================================================
  # Коли `etherisc_policy_id` присутній, система переключається в режим Oracle:
  # замість емісії внутрішніх токенів (SCC/SFC), InsurancePayoutWorker
  # тригерить зовнішній claim через Etherisc Decentralized Insurance Protocol,
  # який виплачує USDC з децентралізованого пулу ліквідності на Polygon.
  # Це запобігає інфляції внутрішніх токенів при страхових виплатах.

  # @return [Boolean] true якщо страховка прив'язана до зовнішнього Etherisc policy
  def uses_etherisc?
    etherisc_policy_id.present?
  end

  # --- СТАТУСИ ТА ТРИГЕРИ ---
  enum :status, { active: 0, triggered: 1, paid: 2, expired: 3 }, prefix: true

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ СТРАХУВАННЯ (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :active, initial: true
    state :triggered
    state :paid
    state :expired

    # Тригер страхового випадку (D-MRV verification)
    event :trigger do
      transitions from: :active, to: :triggered
    end

    # Виплата здійснена
    event :pay do
      before do
        self.paid_at = Time.current
      end
      transitions from: :triggered, to: :paid
    end

    # Строк дії вичерпано
    event :expire do
      transitions from: :active, to: :expired
    end
  end

  enum :trigger_event, { critical_fire: 0, extreme_drought: 1, insect_epidemic: 2 }

  # Тип токена виплати — обирається інвестором при підписанні контракту
  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :payout_amount, :threshold_value, presence: true
  validates :threshold_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :required_confirmations, numericality: { greater_than: 0 }

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
    tree_scope = cluster.trees.select(:id)
    anomalous_insights = AiInsight.daily_health_summary.where(
      analyzable_type: "Tree",
      analyzable_id: tree_scope,
      target_date: target_date,
      stress_index: 0.8..1.0 # Поріг критичного стану / пожежі
    )

    # =========================================================================
    # ORACLE CONSENSUS (Захист від помилки одиночного Оракула)
    # =========================================================================
    # Виплата тригериться лише якщо required_confirmations незалежних джерел
    # (різних AI-моделей) підтвердили катастрофу для кожного аномального дерева.
    # Це запобігає хибним виплатам через помилку одного Оракула.
    min_sources = required_confirmations

    # Рахуємо дерева, де аномалію підтвердили >= required_confirmations незалежних джерел
    confirmed_anomalous_count = if min_sources <= 1
      anomalous_insights.select(:analyzable_id).distinct.count
    else
      # GROUP BY analyzable_id, HAVING COUNT(DISTINCT model_source) >= required_confirmations
      anomalous_insights
        .where.not(model_source: nil)
        .group(:analyzable_id)
        .having("COUNT(DISTINCT model_source) >= ?", min_sources)
        .count
        .size
    end

    # Математика тригера:
    # $$ \text{damage\_ratio} = \frac{\text{confirmed\_anomalous\_count}}{\text{total\_trees}} \times 100 $$
    # [BigDecimal]: Використовуємо точну арифметику — для страхування мікропохибка Float неприпустима.
    damage_ratio = (BigDecimal(confirmed_anomalous_count.to_s) / total_trees * 100).round(2)

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
