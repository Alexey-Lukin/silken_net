# frozen_string_literal: true

class Wallet < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  belongs_to :tree
  has_many :blockchain_transactions, dependent: :destroy

  # --- ВАЛІДАЦІЇ ---
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # Стандартний формат Ethereum/Polygon адреси
  validates :crypto_public_address, format: {
    with: /\A0x[a-fA-F0-9]{40}\z/,
    message: "має бути валідною 0x адресою"
  }, allow_blank: true

  # --- МЕТОДИ НАРАХУВАННЯ (Credit) ---
  # Викликається TelemetryUnpackerService після кожного успішного пакету даних
  def credit!(points)
    # increment! є атомарним на рівні БД (UPDATE ... SET balance = balance + points)
    increment!(:balance, points)
  end

  # --- МЕТОДИ ЕМІСІЇ (Minting) ---
  # Конвертація балів росту в реальні токени в мережі Polygon
  def lock_and_mint!(points_to_lock, threshold, token_type = :carbon_coin)
    # 1. ПЕРЕВІРКА ЖИТТЄЗДАТНОСТІ
    raise "🛑 [Wallet] Дерево не активне. Мінтинг заборонено." unless tree.active?

    # 2. ПОШУК АДРЕСИ ПРИЗНАЧЕННЯ
    # Пріоритет: Дерево -> Організація (Власник)
    target_address = crypto_public_address.presence || tree.cluster&.organization&.crypto_public_address

    if target_address.blank?
      raise "🛑 [Wallet] Відсутня крипто-адреса для мінтингу (Tree чи Organization)"
    end

    transaction do
      # 3. PESSIMISTIC LOCKING (Захист від Race Conditions)
      lock!

      if balance < points_to_lock
        raise "⚠️ [Wallet] Недостатньо балів (Баланс: #{balance}, Потрібно: #{points_to_lock})"
      end

      tokens_to_mint = (points_to_lock.to_f / threshold).floor
      return if tokens_to_mint.zero? # Немає сенсу створювати транзакцію на 0 токенів

      # 4. СПИСАННЯ БАЛІВ ТА ФІКСАЦІЯ ТРАНЗАКЦІЇ
      # Оновлюємо через update! всередині транзакції для надійності
      update!(balance: balance - points_to_lock)

      tx = blockchain_transactions.create!(
        amount: tokens_to_mint,
        token_type: token_type,
        status: :pending,
        to_address: target_address, # Додано поле для чіткості в БД
        notes: "Конвертація #{points_to_lock} балів росту (Поріг: #{threshold})."
      )

      # 5. ЗАПУСК WEB3-КОНВЕЄРА (Polygon Network)
      MintCarbonCoinWorker.perform_async(tx.id)

      Rails.logger.info "💎 [Wallet] Створено запит на мінтинг #{tokens_to_mint} #{token_type} для #{target_address}."
      tx
    end
  end
end
