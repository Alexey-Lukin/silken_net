# frozen_string_literal: true

# [BLOCKER-2] Модель для зберігання L1 Ethereum state root anchoring записів.
# Забезпечує аудит-трейл: { state_root, tx_hash, anchored_at, block_number }.
# [BLOCKER-6] Зберігає компоненти state_root (total_scc, chain_hash, anchored_at)
# для незалежної верифікації зовнішнім аудитором.
class EthereumAnchor < ApplicationRecord
  # --- СТАТУСИ ---
  enum :status, {
    pending: 0,     # State root обчислено, транзакція ще не відправлена
    sent: 1,        # Транзакція відправлена в мемпул, чекаємо підтвердження
    confirmed: 2,   # Транзакція підтверджена в L1 блоці
    failed: 3       # Помилка при відправленні або підтвердженні
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :state_root, presence: true, uniqueness: true,
            format: { with: /\A[a-f0-9]{64}\z/, message: "must be a 64-char hex SHA-256" }
  validates :total_scc, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :chain_hash, presence: true
  validates :anchored_at, presence: true
  validates :tx_hash, uniqueness: true, allow_nil: true,
            format: { with: /\A0x[a-fA-F0-9]{64}\z/, message: "must be a valid Ethereum tx hash" },
            if: -> { tx_hash.present? }
  validates :tx_hash, presence: true, if: -> { status_sent? || status_confirmed? }
  validates :block_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :gas_used, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :error_message, length: { maximum: 500 }, allow_nil: true

  # --- СКОУПИ ---
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: :confirmed) }
  scope :latest_confirmed, -> { status_confirmed.order(created_at: :desc).first }
  scope :in_flight, -> { where(status: [ :pending, :sent ]).where("created_at > ?", 1.week.ago) }

  # --- ХЕЛПЕРИ ---

  # Перевіряє, чи можна незалежно відтворити state_root з збережених компонентів.
  # Дозволяє зовнішньому аудитору верифікувати хеш без доступу до PostgreSQL.
  # [E.53/E.54] Формула оновлена: включає total_sfc та active_tree_count.
  def verify_state_root
    payload = "#{total_scc}|#{total_sfc}|#{active_tree_count}|#{chain_hash}|#{anchored_at.utc.iso8601}"
    expected = Digest::SHA256.hexdigest(payload)
    expected == state_root
  end

  # Etherscan URL для L1 транзакції
  def etherscan_url
    return nil unless tx_hash

    "https://etherscan.io/tx/#{tx_hash}"
  end
end
