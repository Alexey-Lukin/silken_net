# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  include AASM
  include EthAddressValidatable

  # PostgreSQL PK is composite (id, created_at) for declarative partitioning,
  # but Rails should use id alone for lookups, dom_id, and associations.
  self.primary_key = "id"

  # ---------------------------------------------------------------------------
  # PARTITION-AWARE LOOKUPS (Planetary Scale Guard)
  # ---------------------------------------------------------------------------
  # blockchain_transactions is RANGE-partitioned by created_at. Queries without
  # the partition key in WHERE force PostgreSQL to scan ALL partitions (O(P×log N)
  # instead of O(log N)). Always prefer find_with_partition_pruning when created_at
  # is available — it enables single-partition index seek.
  # ---------------------------------------------------------------------------

  # @param id [Integer] record ID
  # @param created_at [Time, String, nil] partition key for pruning
  # @return [BlockchainTransaction]
  # @raise [ActiveRecord::RecordNotFound] if not found
  def self.find_with_partition_pruning(id, created_at = nil)
    scope = where(id: id)
    if created_at.present?
      time = created_at.is_a?(String) ? Time.iso8601(created_at) : created_at.to_time
      # Use a 1-second range to account for sub-second precision differences
      # between ISO 8601 (second precision) and DB timestamps (microsecond).
      # PostgreSQL still prunes to at most one partition for a 1-second window.
      scope = scope.where(created_at: time...(time + 1))
    end
    scope.first!
  rescue ArgumentError, TypeError, NoMethodError
    # Invalid format or unexpected type — fall back to unscoped lookup
    where(id: id).first!
  end

  # --- ЗВ'ЯЗКИ ---
  # optional: true — для аудит-транзакцій slashing, коли весь кластер мертвий
  # і жодного дерева-носія немає (пастка "Останнього дерева")
  belongs_to :wallet, optional: true

  # Запасний власник аудит-запису, коли wallet відсутній
  belongs_to :cluster, optional: true

  # Поліморфний зв'язок для аудиту (Напр. AiInsight, EwsAlert або NaasContract)
  belongs_to :sourceable, polymorphic: true, optional: true

  # ---------------------------------------------------------------------------
  # SCALABILITY NOTE (Series D — Planetary Scale)
  # ---------------------------------------------------------------------------
  # При масштабуванні до мільярдів транзакцій (кожне дерево мінтить SCC щомісяця)
  # ця таблиця стане найбільшою в базі. Рекомендується:
  # 1. PostgreSQL Declarative Partitioning по created_at (RANGE, monthly/quarterly)
  # 2. Альтернатива: партиціювання по cluster_id (LIST) для географічної ізоляції
  # 3. pg_partman для автоматичного створення та maintenance нових партицій
  # Приклад:
  #   CREATE TABLE blockchain_transactions (...) PARTITION BY RANGE (created_at);
  #   CREATE TABLE blockchain_transactions_2026_q1 PARTITION OF blockchain_transactions
  #     FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
  # ---------------------------------------------------------------------------

  # --- ТИПИ ТА СТАТУСИ (The Web3 State Machine) ---
  enum :token_type, { carbon_coin: 0, forest_coin: 1, cusd: 2 }, prefix: true

  # [СИНХРОНІЗОВАНО]: Додано статус :sent для підтримки асинхронного Fire-and-Forget
  enum :status, {
    pending: 0,        # Очікує в черзі на обробку
    processing: 1,     # В процесі підпису/відправки в RPC (заблоковано локом)
    sent: 4,           # [НОВЕ]: Відправлено в Polygon, чекаємо підтвердження блоку (tx_hash вже є)
    confirmed: 2,      # Успішно зафіксовано в блокчейні (Finalized)
    failed: 3,         # Помилка транзакції або Revert на рівні EVM
    manual_review: 5   # [DOUBLE-SPEND GUARD]: tx_hash існує або стан невідомий — потребує ручної звірки
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :amount, presence: true, numericality: { greater_than: 0 }

  # [MULTICHAIN]: Валідація адреси призначення залежить від мережі.
  # EVM (Polygon/Ethereum): 0x + 40 hex символів
  # Solana: Base58 адреса (32-44 символи), не починається з 0x
  validates_eth_address :to_address, presence: true, unless: :solana_network?
  validates :to_address, presence: true, format: {
    with: /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/,
    message: "має бути валідною Solana Base58 адресою"
  }, if: :solana_network?

  # [ОПТИМІЗОВАНО]: tx_hash має бути присутнім для статусів sent та confirmed
  validates :tx_hash, presence: true, if: -> { status_sent? || status_confirmed? }

  # Валідація метрик газу (якщо присутні)
  validates :gas_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :gas_used, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :block_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :nonce, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # [MULTICHAIN]: blockchain_network визначає мережу транзакції
  validates :blockchain_network, inclusion: { in: %w[evm solana celo] }

  # [ARCH.45] In-flight money-path tx — intent-marker idempotency guard (дзеркало
  # EthereumAnchor.in_flight). Recent :pending/:sent = ще не фіналізована виплата/burn;
  # на retry ловить crash-window між on-chain broadcast і DB-записом (double-pay/double-burn).
  # Вікно 2 год >> retry-exhaustion (~хвилини), покриває годинний Solana-cron цикл.
  scope :in_flight, -> { where(status: [ :pending, :sent ]).where("created_at > ?", 2.hours.ago) }

  # --- ДЕЛЕГУВАННЯ ---
  # Навігація через wallet (може бути nil для slashing-аудиту — тоді через cluster)
  delegate :organization, to: :wallet, allow_nil: true

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРАНЗАКЦІЇ (The Web3 State Machine — AASM)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :pending, initial: true
    state :processing
    state :sent
    state :confirmed
    state :failed
    state :manual_review

    # Початок обробки (підпис / відправка в RPC)
    event :process do
      transitions from: :pending, to: :processing
    end

    # Фіксація моменту вильоту в мемпул
    event :mark_as_sent do
      before do |hash|
        self.tx_hash = hash
        self.sent_at = Time.current
        self.error_message = nil
      end
      transitions from: [ :pending, :processing ], to: :sent
    end

    # Успішне підтвердження в мережі (виклик від BlockchainConfirmationWorker)
    event :confirm do
      before do |block_num, gas_cost|
        self.block_number = block_num if block_num.present?
        self.gas_used = gas_cost if gas_cost.present?
        self.confirmed_at = Time.current
        self.error_message = nil
      end
      transitions from: [ :sent, :processing ], to: :confirmed
    end

    # Фіксація збою (як при відправці, так і при Revert)
    event :fail do
      before do |reason|
        self.error_message = reason.to_s.truncate(500)
      end
      after do
        Rails.logger.error "🛑 [Web3] Транзакція ##{id} провалилася: #{error_message}"
      end
      # :failed → :failed дозволяє оновити error_message при повторному збої
      # (напр. sidekiq_retries_exhausted після попереднього fail)
      transitions from: [ :pending, :processing, :sent, :failed ], to: :failed
    end

    # [DOUBLE-SPEND GUARD]: Ескалація до ручної перевірки.
    # Використовується коли tx_hash існує або стан транзакції на блокчейні невідомий.
    # Кошти залишаються в locked_balance до ручної звірки з блокчейн-експлорером.
    event :escalate_to_review do
      before do |reason|
        self.error_message = reason.to_s.truncate(500)
      end
      after do
        Rails.logger.warn "⚠️ [Web3] Транзакція ##{id} потребує ручної перевірки: #{error_message}"
      end
      transitions from: [ :pending, :processing, :sent, :failed ], to: :manual_review
    end
  end

  # [MULTICHAIN]: Хелпер для визначення мережі транзакції
  def solana_network?
    blockchain_network == "solana"
  end

  def celo_network?
    blockchain_network == "celo"
  end

  # Хелпер для посилання на block explorer (Polygonscan, Solana Explorer або Celo Explorer)
  def explorer_url
    return nil unless tx_hash

    if solana_network?
      "https://explorer.solana.com/tx/#{tx_hash}?cluster=devnet"
    elsif celo_network?
      "https://explorer.celo.org/alfajores/tx/#{tx_hash}"
    else
      "https://polygonscan.com/tx/#{tx_hash}"
    end
  end

  alias_method :polygonscan_url, :explorer_url

  # ⚡ [СИНХРОНІЗАЦІЯ]: Real-time broadcast при зміні статусу транзакції.
  # Оновлюємо рядок у таблиці Wallet Ledger та на сторінці деталей TX.
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  private

  def broadcast_status_change
    return unless wallet

    # Оновлення рядка транзакції в Wallet Ledger (підписка: [wallet, :transactions])
    Turbo::StreamsChannel.broadcast_replace_later_to(
      [ wallet, :transactions ],
      target: ActionView::RecordIdentifier.dom_id(self),
      html: Wallets::TransactionRow.new(tx: self).call
    )

    # Оновлення балансу при фінальних статусах (confirmed/failed)
    wallet.broadcast_balance_update if status_confirmed? || status_failed?
  end
end
