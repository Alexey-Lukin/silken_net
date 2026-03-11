# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  include EthAddressValidatable

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
  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  # [СИНХРОНІЗОВАНО]: Додано статус :sent для підтримки асинхронного Fire-and-Forget
  enum :status, {
    pending: 0,    # Очікує в черзі на обробку
    processing: 1, # В процесі підпису/відправки в RPC (заблоковано локом)
    sent: 4,       # [НОВЕ]: Відправлено в Polygon, чекаємо підтвердження блоку (tx_hash вже є)
    confirmed: 2,  # Успішно зафіксовано в блокчейні (Finalized)
    failed: 3      # Помилка транзакції або Revert на рівні EVM
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
  validates :blockchain_network, inclusion: { in: %w[evm solana] }

  # --- ДЕЛЕГУВАННЯ ---
  # Навігація через wallet (може бути nil для slashing-аудиту — тоді через cluster)
  delegate :organization, to: :wallet, allow_nil: true

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРАНЗАКЦІЇ (The Web3 Protocol)
  # =========================================================================

  # Фіксація моменту вильоту в мемпул
  def mark_as_sent!(hash)
    update!(tx_hash: hash, status: :sent, sent_at: Time.current, error_message: nil)
  end

  # Успішне підтвердження в мережі (виклик від BlockchainConfirmationWorker)
  # block_num — номер блоку для захисту від реорганізацій
  # gas_cost — кількість газу, витраченого на транзакцію
  def confirm!(block_num = nil, gas_cost = nil)
    update!(
      status: :confirmed,
      block_number: block_num,
      gas_used: gas_cost,
      confirmed_at: Time.current,
      error_message: nil
    )
  end

  # Фіксація збою (як при відправці, так і при Revert)
  def fail!(reason)
    update!(status: :failed, error_message: reason.truncate(500))
    Rails.logger.error "🛑 [Web3] Транзакція ##{id} провалилася: #{reason}"
  end

  # [MULTICHAIN]: Хелпер для визначення мережі транзакції
  def solana_network?
    blockchain_network == "solana"
  end

  # Хелпер для посилання на block explorer (Polygonscan або Solana Explorer)
  def explorer_url
    return nil unless tx_hash

    if solana_network?
      "https://explorer.solana.com/tx/#{tx_hash}?cluster=devnet"
    else
      "https://polygonscan.com/tx/#{tx_hash}"
    end
  end

  alias_method :polygonscan_url, :explorer_url
end
