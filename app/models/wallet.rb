# frozen_string_literal: true

class Wallet < ApplicationRecord
  include EthAddressValidatable

  # --- ЗВ'ЯЗКИ (The Financial Fabric) ---
  belongs_to :tree
  # [ВИПРАВЛЕНО: Чорна Діра Пам'яті]: Використовуємо delete_all для масової таблиці
  # blockchain_transactions, щоб уникнути OOM при видаленні гаманця з мільйонами TX.
  has_many :blockchain_transactions, dependent: :delete_all

  # [MRV.1] Settled/in-flight money-tx = докази під виданими кредитами (ISO 14064/Verra) —
  # хардделіт гаманця стер би trail (delete_all обходить callbacks). Порожній/чисто-pending
  # гаманець видаляється вільно; off-board з доказами = деактивація, не destroy.
  # prepend: true — інакше dependent: :delete_all (оголошений вище) стирає tx ДО guard'а.
  before_destroy :guard_mrv_evidence!, prepend: true

  # ⚡ [ВИПРАВЛЕНО: The Join Abyss]: Прямий зв'язок з організацією через денормалізований FK.
  # Замінює глибокий ланцюг wallet → tree → cluster → organization на один SELECT.
  belongs_to :organization, optional: true

  has_one :cluster, through: :tree

  # --- ВАЛІДАЦІЇ ---
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :locked_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :esg_retired_balance, numericality: { greater_than_or_equal_to: 0 }

  # SCC = Silken Carbon Coin — public-facing alias for the internal balance column.
  alias_attribute :scc_balance, :balance

  # Стандартний формат Ethereum/Polygon адреси для On-Chain операцій
  validates_eth_address :crypto_public_address, allow_blank: true

  # [KYC.1] KYC чіпляється до адреси-бенефіціара: власна адреса → власний статус;
  # зміна адреси = новий суб'єкт → скидання у pending + ре-верифікація.
  before_update :reset_hadron_kyc_on_address_change
  after_commit :enqueue_hadron_kyc_verification,
               if: -> { saved_change_to_crypto_public_address? && crypto_public_address.present? }

  # [KYC.1] Ефективний KYC-гейт мінтингу — статус БЕНЕФІЦІАРА адреси призначення
  # (дзеркало lock_and_mint!: власна адреса АБО custodial-адреса організації).
  # Custodial-гаманець (без власної адреси) успадковує статус організації.
  def kyc_approved_for_minting?
    if crypto_public_address.present?
      hadron_kyc_status == "approved"
    else
      organization&.hadron_kyc_status == "approved"
    end
  end

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
  # [BLOCKER FIX]: with_lock запобігає TOCTOU race condition — перевірка available_balance
  # та increment! тепер атомарні під SELECT ... FOR UPDATE.
  def lock_funds!(amount)
    with_lock do
      raise "⚠️ [Wallet] Недостатньо доступних коштів (Доступно: #{available_balance}, Потрібно: #{amount})" if available_balance < amount

      increment!(:locked_balance, amount)
    end
  end

  # Повернення заблокованих коштів після невдалої транзакції (Rollback).
  # [BLOCKER FIX]: with_lock запобігає race condition при одночасному rollback кількох TX.
  def release_locked_funds!(amount)
    with_lock do
      raise "⚠️ [Wallet] Спроба розблокувати більше, ніж заблоковано (Заблоковано: #{locked_balance}, Запит: #{amount})" if locked_balance < amount

      decrement!(:locked_balance, amount)
    end
  end

  # Викликається TelemetryUnpackerService після кожного успішного пакету даних від STM32.
  # Кожен подих дерева конвертується в бали росту.
  #
  # [BLOCKER FIX: Database Locking — Wiki 04_01]
  # Pessimistic lock (SELECT ... FOR UPDATE) запобігає race conditions
  # при одночасному надходженні тисяч пакетів телеметрії для одного дерева.
  # with_lock відкриває власну коротку транзакцію — lock тримається лише мілісекунди
  # (тільки на час INCREMENT), а не на всю тривалість commit_telemetry.
  # Це критично при 100+ млрд дерев та Sidekiq concurrency=15.
  def credit!(points)
    with_lock do
      increment!(:balance, points)
    end

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

    # 5. ЛОГУВАННЯ ТА ОНОВЛЕННЯ UI
    # [TRUSTLESS]: MintCarbonCoinWorker тепер працює з telemetry_log_id (oracle-driven flow).
    # Фактичний мінтинг запускається через OracleCallbacksController після верифікації
    # IoTeX + Chainlink, або через TokenomicsEvaluatorWorker → BlockchainMintingService.call_batch.
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

  # [MRV.1] Абортить destroy за наявності settled/in-flight money-tx (докази MRV).
  def guard_mrv_evidence!
    return unless blockchain_transactions.where(status: [ :confirmed, :sent, :manual_review ]).exists?

    errors.add(:base, "Wallet має settled/in-flight blockchain-транзакції (MRV-докази) — деактивуй, не видаляй")
    throw :abort
  end

  # [KYC.1] Явний одночасний сет статусу (verify-воркер / seeds) має пріоритет.
  def reset_hadron_kyc_on_address_change
    return unless will_save_change_to_crypto_public_address?
    return if will_save_change_to_hadron_kyc_status?

    self.hadron_kyc_status = "pending"
  end

  def enqueue_hadron_kyc_verification
    HadronKycVerificationWorker.perform_async("Wallet", id)
  end
end
