# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :wallet

  # Поліморфний зв'язок для аудиту (Напр. AiInsight, EwsAlert або NaasContract)
  belongs_to :sourceable, polymorphic: true, optional: true

  # --- ТИПИ ТА СТАТУСИ (The Web3 State Machine) ---
  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  # [СИНХРОНІЗОВАНО]: Додано статус :processing для запобігання Race Condition у Web3
  enum :status, {
    pending: 0,    # Очікує в черзі
    processing: 1, # В процесі підпису/відправки в RPC (блокування)
    confirmed: 2,  # Успішно в мережі Polygon (tx_hash є)
    failed: 3      # Помилка транзакції
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :amount, presence: true, numericality: { greater_than: 0 }

  # [НОВЕ]: Валідація адреси призначення (0x...)
  validates :to_address, presence: true, format: {
    with: /\A0x[a-fA-F0-9]{40}\z/,
    message: "має бути валідною 0x адресою"
  }

  # tx_hash має бути унікальним і присутнім лише для підтверджених транзакцій
  validates :tx_hash, presence: true, uniqueness: true, if: :status_confirmed?

  # --- ДЕЛЕГУВАННЯ ---
  delegate :organization, to: :wallet

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТРАНЗАКЦІЇ (The Web3 Protocol)
  # =========================================================================

  # Успішне підтвердження в мережі
  def confirm!(hash)
    transaction do
      update!(tx_hash: hash, status: :confirmed, error_message: nil)
      # [Trigger]: Тут можна додати AlertNotificationWorker.perform_async
      # щоб сповістити користувача про успішний мінтинг
    end
  end

  # Фіксація збою (для дебагу в полі)
  def fail!(reason)
    update!(status: :failed, error_message: reason)
    Rails.logger.error "🛑 [Web3] Транзакція ##{id} провалилася: #{reason}"
  end

  # Хелпер для посилання на Polygonscan
  def explorer_url
    return nil unless tx_hash
    "https://polygonscan.com/tx/#{tx_hash}"
  end
end
