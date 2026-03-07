# frozen_string_literal: true

class Wallet < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Financial Fabric) ---
  belongs_to :tree
  has_many :blockchain_transactions, dependent: :destroy

  # ⚡ [ВИПРАВЛЕНО: The Join Abyss]: Прямий зв'язок з організацією через денормалізований FK.
  # Замінює глибокий ланцюг wallet → tree → cluster → organization на один SELECT.
  belongs_to :organization, optional: true

  has_one :cluster, through: :tree

  # --- ВАЛІДАЦІЇ ---
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :locked_balance, numericality: { greater_than_or_equal_to: 0 }

  # SCC = Silken Carbon Coin — public-facing alias for the internal balance column.
  alias_attribute :scc_balance, :balance

  # Стандартний формат Ethereum/Polygon адреси для On-Chain операцій
  validates :crypto_public_address, format: {
    with: /\A0x[a-fA-F0-9]{40}\z/,
    message: "має бути валідною 0x адресою"
  }, allow_blank: true

  # Троттлінг трансляції: оновлюємо UI не частіше ніж раз на N секунд,
  # щоб уникнути "шторму" WebSocket-повідомлень при масовій телеметрії.
  BROADCAST_THROTTLE_SECONDS = 10

  # --- МЕТОДИ НАРАХУВАННЯ (Growth Credit) ---

  # Доступний баланс — це загальний баланс мінус заблоковані кошти (Pending транзакції).
  # Захищає від Double Spend: користувач не може витратити кошти, що вже відправлені в блокчейн.
  def available_balance
    balance - locked_balance
  end

  # Блокування коштів для Pending транзакцій (Double Spend Protection).
  # Кошти залишаються на балансі, але не доступні для витрат.
  def lock_funds!(amount)
    raise "⚠️ [Wallet] Недостатньо доступних коштів (Доступно: #{available_balance}, Потрібно: #{amount})" if available_balance < amount

    increment!(:locked_balance, amount)
  end

  # Повернення заблокованих коштів після невдалої транзакції (Rollback).
  def release_locked_funds!(amount)
    raise "⚠️ [Wallet] Спроба розблокувати більше, ніж заблоковано (Заблоковано: #{locked_balance}, Запит: #{amount})" if locked_balance < amount

    decrement!(:locked_balance, amount)
  end

  # Фіналізація витрати після підтвердження транзакції в блокчейні.
  # Списуємо кошти з balance та знімаємо блокування.
  def finalize_spend!(amount)
    transaction do
      lock!
      raise "⚠️ [Wallet] Невідповідність: locked_balance (#{locked_balance}) < amount (#{amount})" if locked_balance < amount
      raise "⚠️ [Wallet] Невідповідність: balance (#{balance}) < amount (#{amount})" if balance < amount

      decrement!(:locked_balance, amount)
      decrement!(:balance, amount)
    end
  end

  # Викликається TelemetryUnpackerService після кожного успішного пакету даних від STM32.
  # Кожен подих дерева конвертується в бали росту.
  def credit!(points)
    # increment! є атомарним на рівні БД (UPDATE ... SET balance = balance + points)
    # Це захищає нас від втрат при масовому надходженні пакетів через Starlink/LoRa
    increment!(:balance, points)

    # [СИНХРОНІЗАЦІЯ]: Оновлюємо цифри на Dashboard Архітектора з троттлінгом,
    # щоб при 1 000 000 дерев не створювати ~16 000 повідомлень/сек
    broadcast_balance_update if should_broadcast?
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

      if available_balance < points_to_lock
        raise "⚠️ [Wallet] Недостатньо балів (Доступно: #{available_balance}, Потрібно: #{points_to_lock})"
      end

      tokens_to_mint = (points_to_lock.to_f / threshold).floor
      return if tokens_to_mint.zero? # Немає сенсу створювати транзакцію на 0 токенів

      # 4. БЛОКУВАННЯ КОШТІВ (Pending Balance Protection)
      # Замість негайного списання з balance, блокуємо кошти в locked_balance.
      # Це захищає від Double Spend: кошти недоступні, але залишаються на балансі
      # до фіналізації транзакції в блокчейні.
      increment!(:locked_balance, points_to_lock)

      blockchain_transactions.create!(
        amount: tokens_to_mint,
        token_type: token_type,
        status: :pending,
        to_address: target_address,
        locked_points: points_to_lock,
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
      html: Wallets::BalanceDisplay.new(wallet: self).call
    )
  end

  private

  # Троттлінг WebSocket-трансляцій: не частіше ніж раз на BROADCAST_THROTTLE_SECONDS.
  # Використовуємо Rails.cache для зберігання мітки останнього broadcast.
  def should_broadcast?
    cache_key = "wallet_broadcast_throttle:#{id}"
    return false if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: BROADCAST_THROTTLE_SECONDS.seconds)
    true
  end
end
