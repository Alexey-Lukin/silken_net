# frozen_string_literal: true

class BlockchainTransaction < ApplicationRecord
  belongs_to :wallet

  # Типи токенів (з вашого Мастер-Плану)
  enum :token_type, {
    carbon_coin: 0, # За поглинання CO2 (розраховується з метаболізму)
    forest_coin: 1  # За біорізноманіття та підтримку гомеостазу
  }, prefix: true

  # Життєвий цикл транзакції в мережі Polygon/Solana
  enum :status, {
    pending: 0,   # Відправлено в чергу на підпис
    confirmed: 1, # Успішно замінчено на блокчейні (tx_hash отримано)
    failed: 2     # Помилка мережі або газу (потребує повернення балів у Wallet)
  }, prefix: true

  validates :amount, presence: true, numericality: { greater_than: 0 }

  # tx_hash з'явиться тільки після підтвердження від RPC-ноди
  validates :tx_hash, presence: true, uniqueness: true, if: :status_confirmed?

  # Метод для запису успішного хешу транзакції
  def confirm_minting!(hash)
    update!(tx_hash: hash, status: :confirmed)
  end
end
