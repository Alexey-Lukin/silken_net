# frozen_string_literal: true

class Wallet < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Financial Fabric) ---
  belongs_to :tree
  has_many :blockchain_transactions, dependent: :destroy

  # ⚡ [СИНХРОНІЗАЦІЯ]: Висхідна навігація до власника ресурсу
  # Дозволяє миттєво перевіряти права доступу: current_user.organization == wallet.organization
  has_one :cluster, through: :tree
  has_one :organization, through: :cluster

  # --- ВАЛІДАЦІЇ ---
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Стандартний формат Ethereum/Polygon адреси для On-Chain операцій
  validates :crypto_public_address, format: {
    with: /\A0x[a-fA-F0-9]{40}\z/,
    message: "має бути валідною 0x адресою"
  }, allow_blank: true

  # --- МЕТОДИ НАРАХУВАННЯ (Growth Credit) ---

  # Викликається TelemetryUnpackerService після кожного успішного пакету даних від STM32.
  # Кожен подих дерева конвертується в бали росту.
  def credit!(points)
    # increment! є атомарним на рівні БД (UPDATE ... SET balance = balance + points)
    # Це захищає нас від втрат при масовому надходженні пакетів через Starlink/LoRa
    increment!(:balance, points)

    # [СИНХРОНІЗАЦІЯ]: Миттєво оновлюємо цифри на Dashboard Архітектора
    broadcast_balance_update
  end

  # --- МЕТОДИ ЕМІСІЇ (Web3 Minting) ---

  # Конвертація накопичених балів росту в реальні токени SCC/SFC у мережі Polygon
  def lock_and_mint!(points_to_lock, threshold, token_type = :carbon_coin)
    # 1. ПЕРЕВІРКА ЖИТТЄЗДАТНОСТІ
    raise "🛑 [Wallet] Дерево не активне. Мінтинг заборонено." unless tree.active?
    return if threshold.to_f <= 0

    # 2. ПОШУК АДРЕСИ ПРИЗНАЧЕННЯ
    # Пріоритет: Власний гаманець дерева -> Гаманець Організації (Власника)
    target_address = crypto_public_address.presence || organization&.crypto_public_address

    if target_address.blank?
      raise "🛑 [Wallet] Відсутня крипто-адреса для мінтингу (Tree чи Organization)"
    end

    tx = transaction do
      # 3. PESSIMISTIC LOCKING (Захист від Race Conditions під час мінтингу)
      lock!

      if balance < points_to_lock
        raise "⚠️ [Wallet] Недостатньо балів (Баланс: #{balance}, Потрібно: #{points_to_lock})"
      end

      tokens_to_mint = (points_to_lock.to_f / threshold).floor
      next if tokens_to_mint.zero? # Немає сенсу створювати транзакцію на 0 токенів

      # 4. СПИСАННЯ БАЛІВ ТА ФІКСАЦІЯ ТРАНЗАКЦІЇ
      update!(balance: balance - points_to_lock)

      blockchain_transactions.create!(
        amount: tokens_to_mint,
        token_type: token_type,
        status: :pending,
        to_address: target_address,
        notes: "Конвертація #{points_to_lock} балів росту (Поріг: #{threshold})."
      )
    end

    return unless tx

    # 5. ЗАПУСК WEB3-КОНВЕЄРА (Polygon Network)
    # [ВИПРАВЛЕНО]: Воркер запускається ПІСЛЯ завершення транзакції (COMMIT),
    # щоб уникнути ситуації, коли Redis обробить завдання раніше, ніж БД закриє транзакцію.
    MintCarbonCoinWorker.perform_async(tx.id)

    Rails.logger.info "💎 [Wallet] Створено запит на мінтинг #{tx.amount} #{token_type} для #{target_address}."

    broadcast_balance_update
    tx
  end

  # Трансляція оновленого стану гаманця через Turbo Streams
  def broadcast_balance_update
    # Оновлення великої цифри балансу в UI
    Turbo::StreamsChannel.broadcast_replace_to(
      self,
      target: "wallet_balance_#{id}",
      html: Views::Components::Wallets::BalanceDisplay.new(wallet: self).call
    )
  end
end
