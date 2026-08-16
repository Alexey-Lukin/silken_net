# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class NaasContract < ApplicationRecord
  include AASM
  include Auditable

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
  # [ARCH.57] Кожна зміна статусу контракту → tamper-evident audit-ланцюг. Хук на
  # saved_change_to_status?, НЕ на AASM after_all_transitions: prod-шляхи ставлять
  # статус raw enum-write'ом (breach у BlockchainBurningService, cancel у
  # ContractTerminationService — обидва update!), який AASM-хук не бачить.
  after_update_commit :record_contract_audit_trail, if: :saved_change_to_status?

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

  # [SEC.1] Сукупна страхова премія (5% від funding), спрямована до DAO Treasury
  # Parametric Insurance Pool через активовані контракти. Премія сплачується при
  # активації (USDC) і лишається в пулі через fulfilled/breached; draft ще не сплачено,
  # cancelled повертається — обидва виключені. Це DB-джерело правди для premium-показника
  # Real-Yield звіту: премія — off-chain USDC-факт, НЕ on-chain SCC-подія (знятий
  # `PremiumPaid` — канон 05_03).
  def self.total_insurance_premiums
    (where(status: %i[active fulfilled breached]).sum(:total_funding) * INSURANCE_PREMIUM_RATE).round(2)
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
  def check_cluster_health!(target_date = AiInsight.reporting_date)
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

  # [UI.10] `current_yield_performance` ЗНЯТО 2026-08-14 (присуд власника).
  # Він ділив `emitted_tokens` (SCC) на `total_funding` (USD за послугу,
  # `07_01 §5`) і подавав частку відсотком, а `.clamp(0, 100)` маскував те, що
  # величина не міряє нічого: у чисельника й знаменника різні одиниці. Датчик,
  # який він живив, стояв під підписом «Cluster Health» — тобто чужа величина
  # під чужим підписом. Колонку знято цілком, а не перецілено: здоровʼя кластера
  # вже має два чесні доми (агрегат у герої `Contracts::Index`, per-contract
  # `backing_asset` у `contracts#show`), тож третій був би новою поверхнею
  # заради виправдання колонки. Заразом закривається `securities_review.md` F7
  # («yield» = мова доходу на інвестицію → Howey prong 3).

  # [UI.8] `active_threats?` знято 2026-08-16 — питання «чи є загрози в кластері»
  # має ОДИН дім, `Cluster#active_threats?` (лише critical, канон `04_01 §Cluster`).
  # Цей двійник ніколи не мав UI-споживача: контролер завів `methods: [:active_threats?]`
  # разом із коментарем про «червоний вогник у списку» за ТИЖДЕНЬ до того, як метод
  # зʼявився на моделі, і метод приїхав латкою під виклик, що падав. Ширший поріг
  # (будь-яка severity) звідти й походить — його не обирали.

  private

  # [ARCH.57] Імена state-based (raw update!-шляхи breach/cancel не мають AASM-події).
  # Chain-only (без IPFS): total_funding комерційно чутливий — публічний IPFS-периметр
  # лишається за money-tx переходами MRV.1.
  def record_contract_audit_trail
    from, to = saved_change_to_status
    record_audit_trail!(
      action: "naas_contract_to_#{to}",
      organization_id: organization_id,
      metadata: {
        from: from.to_s, to: to.to_s,
        cluster_id: cluster_id, total_funding: total_funding.to_s
      }
    )
  end

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    errors.add(:end_date, :must_be_after_start) if end_date < start_date
  end
end
