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
    breached: 3,   # ПОРУШЕНО (Slashing Protocol активовано)
    cancelled: 4   # Достроково розірвано інвестором (Early Exit)
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :total_funding, presence: true, numericality: { greater_than: 0 }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  # --- CANCELLATION TERMS (JSONB Accessors) ---
  # cancellation_terms: { "early_exit_fee_percent" => 15, "burn_accrued_points" => true, "min_days_before_exit" => 30 }
  store_accessor :cancellation_terms, :early_exit_fee_percent, :burn_accrued_points, :min_days_before_exit

  # --- СКОУПИ ---
  # [СИНХРОНІЗОВАНО]: Уніфікована назва для системної єдності
  scope :active, -> { status_active }

  # [ВИПРАВЛЕНО]: Фінансовий дедлайн.
  # Контракт активний до останньої секунди вказаного дня.
  # [UTC Anchor]: Фіксований UTC-якір для детермінованості глобального арбітражу.
  scope :pending_completion, -> { active.where("end_date < ?", Time.current.utc.to_date) }

  # =========================================================================
  # THE SLASHING PROTOCOL (D-MRV Арбітраж)
  # =========================================================================

  # [ВИПРАВЛЕНО]: Вигнання "Мертвих Душ".
  # Ми розраховуємо здоров'я лише за тими "Солдатами", що стоять у строю.
  # [Cluster TZ]: Використовуємо часовий пояс кластера для детермінованості арбітражу.
  def check_cluster_health!(target_date = cluster.local_yesterday)
    return unless status_active?

    # [Counter Cache]: Використовуємо денормалізований лічильник замість COUNT(*).
    # Рахуємо лише активні дерева, ігноруючи deceased та removed.
    total_active_count = cluster.active_trees_count

    return if total_active_count.zero?

    # [SQL Optimization]: Використовуємо підзапит замість масиву об'єктів (The Polymorphic IN Trap).
    # При 100 000+ деревах, передача масиву ID генерує гігантський IN-оператор.
    # Subquery дозволяє PostgreSQL оптимізувати запит через JOIN/Hash.
    daily_insights = AiInsight.daily_health_summary.where(
      analyzable_type: "Tree",
      analyzable_id: cluster.trees.active.select(:id),
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

    # Математична межа порушення контракту (20% від активної біомаси).
    # [Rational]: Точна раціональна арифметика замість Float 0.20, щоб уникнути мікропохибок.
    # $$HealthRatio = \frac{\sum \text{ActiveTrees with Stress} \ge 1.0}{\text{TotalActiveTrees}}$$
    if critical_insights_count > total_active_count * Rational(1, 5)
      activate_slashing_protocol!
    end
  end

  # =========================================================================
  # EARLY TERMINATION (Дострокове розірвання контракту)
  # =========================================================================

  # Розрахунок штрафу за дострокове розірвання (Early Exit Fee).
  # $$ Fee = TotalFunding \times \frac{EarlyExitFeePercent}{100} $$
  def calculate_early_exit_fee
    fee_percent = (early_exit_fee_percent || 0).to_d
    (total_funding * fee_percent / 100).round(2)
  end

  # Розрахунок пропорційного повернення коштів з урахуванням штрафу.
  # $$ Refund = TotalFunding \times \frac{RemainingDays}{TotalDays} - EarlyExitFee $$
  def calculate_prorated_refund
    return BigDecimal("0") unless status_active?

    total_days = (end_date.to_date - start_date.to_date).to_i
    return BigDecimal("0") if total_days.zero?

    elapsed_days = (Time.current.utc.to_date - start_date.to_date).to_i
    remaining_days = [ total_days - elapsed_days, 0 ].max

    prorated = (total_funding * BigDecimal(remaining_days.to_s) / total_days).round(2)
    fee = calculate_early_exit_fee

    [ prorated - fee, BigDecimal("0") ].max
  end

  # Дострокове розірвання контракту з розрахунком штрафу та спалюванням балів.
  def terminate_early!
    raise "🛑 [NaasContract] Контракт не активний. Розірвання неможливе." unless status_active?

    min_days = (min_days_before_exit || 0).to_i
    elapsed = (Time.current.utc.to_date - start_date.to_date).to_i
    if min_days.positive? && elapsed < min_days
      raise "🛑 [NaasContract] Мінімальний термін до розірвання: #{min_days} днів (пройшло: #{elapsed})."
    end

    refund = calculate_prorated_refund
    should_burn = ActiveModel::Type::Boolean.new.cast(burn_accrued_points)

    transaction do
      update!(status: :cancelled, cancelled_at: Time.current)

      # Спалювання нарахованих балів/токенів, якщо умови контракту це передбачають
      if should_burn
        BurnCarbonTokensWorker.perform_async(organization_id, id)
        Rails.logger.warn "🔥 [NaasContract] Контракт ##{id} розірвано. Нараховані бали спалюються."
      end

      Rails.logger.info "📜 [NaasContract] Контракт ##{id} розірвано достроково. Повернення: #{refund}, Штраф: #{calculate_early_exit_fee}."
    end

    { refund: refund, fee: calculate_early_exit_fee, burned: should_burn }
  end

  # Відсоток виконання контракту за обсягом емісії відносно вкладених коштів.
  # Використовується для індикатора прогресу у вьюхах (Contracts::Index).
  def current_yield_performance
    return 0 if total_funding.nil? || total_funding.zero?

    (emitted_tokens.to_f / total_funding * 100).clamp(0, 100).round
  end

  # Whether the backing cluster currently has active EWS alerts.
  # Uses Ruby-level filtering to leverage eager-loaded ews_alerts (avoids N+1).
  def active_threats?
    return false unless cluster

    if cluster.association(:ews_alerts).loaded?
      cluster.ews_alerts.any? { |a| a.status_active? }
    else
      cluster.ews_alerts.unresolved.any?
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
