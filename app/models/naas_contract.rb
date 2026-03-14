# frozen_string_literal: true

class NaasContract < ApplicationRecord
  include AASM

  # [HYBRID PROTOCOL GAIA]: Ставка корпоративної страхової премії (Corporate Premium).
  # 5% від total_funding кожного NaaS-контракту направляється до DAO Treasury Parametric Insurance Pool.
  INSURANCE_PREMIUM_RATE = BigDecimal("0.05")

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

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ КОНТРАКТУ (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :draft, initial: true
    state :active
    state :fulfilled
    state :breached
    state :cancelled

    # Активація контракту (після підтвердження інвестиції)
    # [HYBRID PROTOCOL GAIA]: При активації контракту insurance_premium_amount (5% від total_funding)
    # у USDC направляється до DAO Treasury Parametric Insurance Pool.
    # Це забезпечує фінансування страхового пулу для параметричних виплат (пожежі, посухи, шкідники).
    event :activate do
      transitions from: :draft, to: :active
    end

    # Успішне завершення контракту (Audit pass)
    event :fulfill do
      transitions from: :active, to: :fulfilled
    end

    # Порушення контракту (Slashing Protocol)
    event :breach do
      transitions from: :active, to: :breached
    end

    # Дострокове розірвання інвестором (Early Exit)
    event :cancel do
      transitions from: [ :draft, :active ], to: :cancelled
    end
  end

  # =========================================================================
  # HYBRID PROTOCOL GAIA: Corporate Premium (Insurance Pool Funding)
  # =========================================================================

  # Сума страхової премії (5% від total_funding), що направляється до DAO Treasury
  # Parametric Insurance Pool при активації контракту.
  def insurance_premium_amount
    (total_funding * INSURANCE_PREMIUM_RATE).round(2)
  end

  # Частка total_funding, що залишається форестеру після вирахування страхової премії (95%).
  def forester_share_amount
    (total_funding - insurance_premium_amount).round(2)
  end

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

  # Делегує перевірку здоров'я кластера до ContractHealthCheckService.
  # [Cluster TZ]: Використовує часовий пояс кластера для детермінованості арбітражу.
  def check_cluster_health!(target_date = cluster.local_yesterday)
    ContractHealthCheckService.call(self, target_date)
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

  # Дострокове розірвання контракту — делегує до ContractTerminationService.
  def terminate_early!
    ContractTerminationService.call(self)
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

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    errors.add(:end_date, "повинна бути пізніше дати початку") if end_date < start_date
  end
end
