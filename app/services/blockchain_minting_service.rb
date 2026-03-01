# frozen_string_literal: true

require "eth"

class BlockchainMintingService
  # ABI для нашого D-MRV контракту (Decentralized Monitoring, Reporting, and Verification)
  CONTRACT_ABI = '[{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"string","name":"identifier","type":"string"}],"name":"mint","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

  def self.call(blockchain_transaction_id)
    new(blockchain_transaction_id).call
  end

  def initialize(blockchain_transaction_id)
    @transaction = BlockchainTransaction.find(blockchain_transaction_id)
    @wallet = @transaction.wallet
    @tree = @wallet.tree
  end

  def call
    return if @transaction.confirmed? || @transaction.tx_hash.present?

    # 1. ПІДКЛЮЧЕННЯ (The Alchemy Link)
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

    # [SAFETY]: Перевірка палива для здійснення транзакції
    balance = client.get_balance(oracle_key.address)
    raise "🚨 [Web3] Критично низький баланс Оракула: #{balance}" if balance < 0.05 * (10**18)

    # 2. МАРШРУТИЗАЦІЯ (The Sovereign Tokens)
    case @transaction.token_type
    when "carbon_coin"
      contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
      identifier = @tree&.did || "ORG_#{@wallet.organization_id}"
    when "forest_coin"
      contract_address = ENV.fetch("FOREST_COIN_CONTRACT_ADDRESS")
      identifier = "CLUSTER_#{@tree&.cluster_id || 'GLOBAL'}"
    else
      raise ArgumentError, "Невідомий тип токена: #{@transaction.token_type}"
    end

    # 3. ПІДГОТОВКА КОНТРАКТУ
    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)
    amount_in_wei = (@transaction.amount.to_f * (10**18)).to_i

    # 4. АТОМАРНИЙ МІНТИНГ З REDIS-LOCK (Захист Nonce від паралельних воркерів)
    lock_key = "lock:web3:oracle:#{oracle_key.address}"

    begin
      tx_hash = nil

      Kredis.lock(lock_key, expires_in: 60.seconds, after_timeout: :raise) do
        @transaction.update!(status: :processing)
        
        # ⚡ [СИНХРОНІЗАЦІЯ]: Транслюємо стан "В обробці" в UI
        broadcast_tx_update

        Rails.logger.info "⏳ [Web3] Мінтинг #{@transaction.amount} для #{identifier}..."

        # Використовуємо пріоритетну комісію для Polygon (EIP-1559)
        tx_hash = client.transact_and_wait(
          contract,
          "mint",
          @transaction.to_address,
          amount_in_wei,
          identifier,
          sender_key: oracle_key,
          legacy: false
        )
      end

      # 5. ПІДТВЕРДЖЕННЯ
      if tx_hash.present?
        @transaction.confirm!(tx_hash)
        
        # ⚡ [СИНХРОНІЗАЦІЯ]: Транзакція підтверджена, оновлюємо Ledger та Баланс
        broadcast_tx_update
        
        Rails.logger.info "✅ [Web3] Виконано. DID: #{identifier} | TX: #{tx_hash}"
      end

    rescue StandardError => e
      @transaction.fail!(e.message.truncate(200))
      
      # ⚡ [СИНХРОНІЗАЦІЯ]: Повідомляємо Архітектора про збій у Матриці
      broadcast_tx_update
      
      Rails.logger.error "🛑 [Web3 Failure] #{@transaction.id}: #{e.message}"
      raise e # Дозволяємо Sidekiq зробити retry, якщо помилка тимчасова (напр. мережа)
    end
  end

  private

  def broadcast_tx_update
    # 1. Оновлюємо конкретний рядок транзакції в таблиці гаманця
    Turbo::StreamsChannel.broadcast_replace_to(
      @wallet,
      target: "transaction_#{@transaction.id}",
      html: Views::Components::Wallets::TransactionRow.new(tx: @transaction).call
    )

    # 2. Оновлюємо велику цифру балансу в Hero-секції гаманця
    Turbo::StreamsChannel.broadcast_replace_to(
      @wallet,
      target: "wallet_balance_#{@wallet.id}",
      html: Views::Components::Wallets::BalanceDisplay.new(wallet: @wallet).call
    )

    # 3. Якщо транзакція підтверджена — додаємо спалах у глобальну стрічку подій Dashboard
    if @transaction.confirmed?
      Turbo::StreamsChannel.broadcast_prepend_to(
        "global_events",
        target: "events_feed",
        html: Views::Components::Dashboard::EventRow.new(event: @transaction).call
      )
    end
  end
end
