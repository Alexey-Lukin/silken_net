# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # optional: true — для аудит-транзакцій slashing, коли весь кластер мертвий
  # і жодного дерева-носія немає (пастка "Останнього дерева")
  belongs_to :wallet, optional: true

  # Запасний власник аудит-запису, коли wallet відсутній
  belongs_to :cluster, optional: true

  # Поліморфний зв'язок для аудиту (Напр. AiInsight, EwsAlert або NaasContract)
  belongs_to :sourceable, polymorphic: true, optional: true

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

  # Валідація адреси призначення (0x...)
  validates :to_address, presence: true, format: {
    with: /\A0x[a-fA-F0-9]{40}\z/,
    message: "має бути валідною 0x адресою"
  }

  # [ОПТИМІЗОВАНО]: tx_hash має бути присутнім для статусів sent та confirmed
  validates :tx_hash, presence: true, if: -> { status_sent? || status_confirmed? }
  validates :tx_hash, uniqueness: true, allow_nil: true

  # --- ДЕЛЕГУВАННЯ ---
  # Навігація через wallet (може бути nil для slashing-аудиту — тоді через cluster)
  delegate :organization, to: :wallet, allow_nil: true

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРАНЗАКЦІЇ (The Web3 Protocol)
  # =========================================================================

  # Фіксація моменту вильоту в мемпул
  def mark_as_sent!(hash)
    update!(tx_hash: hash, status: :sent, error_message: nil)
  end

  # Успішне підтвердження в мережі (виклик від BlockchainConfirmationWorker)
  def confirm!
    update!(status: :confirmed, error_message: nil)
  end

  # Фіксація збою (як при відправці, так і при Revert)
  def fail!(reason)
    update!(status: :failed, error_message: reason.truncate(500))
    Rails.logger.error "🛑 [Web3] Транзакція ##{id} провалилася: #{reason}"
  end

  # Хелпер для посилання на Polygonscan
  def explorer_url
    return nil unless tx_hash
    "https://polygonscan.com/tx/#{tx_hash}"
  end
end
