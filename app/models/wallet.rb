# frozen_string_literal: true

class Wallet < ApplicationRecord
  belongs_to :tree
  has_many :blockchain_transactions, dependent: :destroy

  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :crypto_public_address, format: { with: /\A0x[a-fA-F0-9]{40}\z/ }, allow_blank: true

  def credit!(points)
    increment!(:balance, points)
  end

  # Метод для автоматичної емісії (викликається воркером)
  def lock_and_mint!(points_to_lock, threshold)
    # Адреса гаманця береться з організації, якій належить дерево
    target_address = tree.cluster&.organization&.crypto_public_address
    
    raise "Відсутня адреса організації" if target_address.blank?

    transaction do
      lock! # Row-level lock для запобігання Race Condition
      raise "Недостатньо балів" if balance < points_to_lock

      tokens_to_mint = points_to_lock / threshold
      
      decrement!(:balance, points_to_lock)
      
      tx = blockchain_transactions.create!(
        amount: tokens_to_mint, # Записуємо кількість токенів, а не балів
        token_type: :carbon_coin,
        status: :pending,
        notes: "Конвертація #{points_to_lock} балів росту."
      )

      MintCarbonCoinWorker.perform_async(tx.id)
      tx
    end
  end
end
