# frozen_string_literal: true

class Wallet < ApplicationRecord
  belongs_to :tree

  has_many :blockchain_transactions, dependent: :destroy

  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # [НОВЕ] Перевірка формату крипто-гаманця (наприклад, для EVM-сумісних мереж типу Polygon)
  # Якщо адреса вказана, вона має починатися з '0x' і мати довжину 42 символи
  validates :crypto_public_address, format: { with: /\A0x[a-fA-F0-9]{40}\z/ }, allow_blank: true

  # Безпечне нарахування токенів
  def credit!(points)
    increment!(:balance, points)
  end

  def lock_and_mint!(amount, type = :carbon_coin)
    raise ActiveRecord::RecordInvalid, "Не вказано адресу" if crypto_public_address.blank?

    transaction do
      lock!
      raise ActiveRecord::RecordInvalid, "Недостатньо балів" if balance < amount

      decrement!(:balance, amount)
      tx = blockchain_transactions.create!(
        amount: amount,
        token_type: type,
        status: :pending
      )

      # Вистрілюємо задачу в Redis. Миттєво.
      MintCarbonCoinWorker.perform_async(tx.id)
    end
  end
end
