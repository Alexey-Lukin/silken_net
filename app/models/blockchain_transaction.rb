# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  belongs_to :wallet
  
  # Поліморфний зв'язок для аудиту (Напр. AiInsight або ParametricInsurance)
  belongs_to :sourceable, polymorphic: true, optional: true

  enum :token_type, { carbon_coin: 0, forest_coin: 1 }, prefix: true

  enum :status, {
    pending: 0,   # В черзі (MintCarbonCoinWorker)
    confirmed: 1, # В Polygon (tx_hash отримано)
    failed: 2     # Rollback потрібен
  }, prefix: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :tx_hash, presence: true, uniqueness: true, if: :status_confirmed?

  # Захист від подвійного запису хешу
  def confirm_minting!(hash)
    transaction do
      update!(tx_hash: hash, status: :confirmed)
      # Додаткова логіка: сповіщення власника організації через Push
    end
  end
end
