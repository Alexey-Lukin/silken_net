# frozen_string_literal: true

class Wallet < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :tree
  has_many :blockchain_transactions, dependent: :destroy

  # --- ВАЛІДАЦІЇ ---
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # Стандартний формат Ethereum-адреси
  validates :crypto_public_address, format: { with: /\A0x[a-fA-F0-9]{40}\z/ }, allow_blank: true

  # --- МЕТОДИ НАРАХУВАННЯ (Credit) ---
  def credit!(points)
    # Використовуємо транзакцію для безпеки, хоча increment! атомарний на рівні БД
    increment!(:balance, points)
  end

  # --- МЕТОДИ ЕМІСІЇ (Minting) ---
  # [ПОКРАЩЕНО]: Додано параметр token_type для підтримки різних екологічних активів
  def lock_and_mint!(points_to_lock, threshold, token_type = :carbon_coin)
    # Гнучка адресація: дерево -> організація -> помилка
    target_address = crypto_public_address.presence || tree.cluster&.organization&.crypto_public_address
    
    if target_address.blank?
      raise "🛑 [Wallet] Відсутня крипто-адреса для мінтингу (Tree чи Organization)" 
    end

    transaction do
      # Pessimistic Locking (SELECT ... FOR UPDATE)
      # Захищає від ситуації, коли два воркери одночасно бачать один і той самий баланс
      lock! 
      
      raise "⚠️ [Wallet] Недостатньо балів (Баланс: #{balance}, Потрібно: #{points_to_lock})" if balance < points_to_lock

      tokens_to_mint = points_to_lock / threshold
      
      # Списуємо бали росту
      decrement!(:balance, points_to_lock)
      
      # Створюємо запис у блокчейн-черзі
      tx = blockchain_transactions.create!(
        amount: tokens_to_mint,
        token_type: token_type,
        status: :pending,
        notes: "Конвертація #{points_to_lock} балів росту на адресу #{target_address}."
      )

      # Відправляємо задачу в Web3-воркер (Polygon Network)
      MintCarbonCoinWorker.perform_async(tx.id)
      tx
    end
  end
end
