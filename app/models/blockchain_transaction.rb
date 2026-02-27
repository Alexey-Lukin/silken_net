# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  belongs_to :wallet
  
  # Поліморфний зв'язок для аудиту (Напр. AiInsight, EwsAlert або NaasContract)
  belongs_to :sourceable, polymorphic: true, optional: true

  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  # [СИНХРОНІЗОВАНО]: Додано статус :processing для запобігання Race Condition у Web3
  enum :status, {
    pending: 0,    # Очікує в черзі
    processing: 1, # В процесі підпису/відправки в RPC (блокування)
    confirmed: 2,  # Успішно в мережі Polygon (tx_hash є)
    failed: 3      # Помилка транзакції
  }, prefix: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  
  # tx_hash має бути унікальним і присутнім лише для підтверджених транзакцій
  validates :tx_hash, presence: true, uniqueness: true, if: :status_confirmed?

  # [НОВЕ]: Зв'язок для зручної навігації до організації
  delegate :organization, to: :wallet

  # Захист від подвійного запису хешу
  def confirm_minting!(hash)
    transaction do
      update!(tx_hash: hash, status: :confirmed)
      # [Trigger]: Тут можна викликати NotificationService для інвестора
    end
  end

  # Хелпер для посилання на Polygonscan
  def explorer_url
    return nil unless tx_hash
    "https://polygonscan.com/tx/#{tx_hash}"
  end
end
