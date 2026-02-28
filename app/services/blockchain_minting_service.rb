# frozen_string_literal: true

require "eth"

class BlockchainMintingService
  # ABI нашого смарт-контракту SilkenCoin
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
    # 1. ЗАХИСТ ВІД ПОДВІЙНОГО МІНТИНГУ
    # Якщо транзакція вже має хеш або не в статусі pending/failed/processing — виходимо.
    # Ми дозволяємо повторний запуск для processing лише якщо впевнені, що минула спроба не пішла в мережу.
    return unless @transaction.status_pending? || @transaction.status_failed? || @transaction.status_processing?
    return if @transaction.tx_hash.present?

    # Переводимо в статус processing для блокування інших Sidekiq-воркерів
    @transaction.update!(status: :processing)

    # 2. ПІДКЛЮЧЕННЯ ДО ПОЛІГОНУ
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

    # 3. МАРШРУТИЗАЦІЯ (Carbon vs Forest)
    case @transaction.token_type
    when "carbon_coin"
      contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
      identifier = @tree.did
    when "forest_coin"
      contract_address = ENV.fetch("FOREST_COIN_CONTRACT_ADDRESS")
      identifier = "CLUSTER_#{@tree.cluster_id}"
    else
      @transaction.fail!("Невідомий тип токена")
      raise ArgumentError, "Невідомий тип токена: #{@transaction.token_type}"
    end

    # Підготовка контракту та суми
    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)
    amount_in_wei = (@transaction.amount * (10**18)).to_i
    target_address = @transaction.to_address # Використовуємо поле, яке ми зашліфували в моделі

    # 4. АТОМАРНА ЕМІСІЯ З ЗАХИСТОМ NONCE
    # Використовуємо Redis-замок, щоб транзакції Оракула не конфліктували
    lock_key = "lock:web3:oracle:#{oracle_key.address}"
    
    begin
      Rails.logger.info "⏳ [Web3] Спроба мінтингу #{@transaction.amount} SCC для #{identifier}..."

      # [СИНХРОНІЗАЦІЯ]: Використовуємо блок для гарантії послідовності Nonce
      tx_hash = nil
      
      # Ми чекаємо замка максимум 30 секунд
      Kredis.lock(lock_key, expires_in: 60.seconds, after_timeout: :raise) do
        tx_hash = client.transact_and_wait(
          contract,
          "mint",
          target_address,
          amount_in_wei,
          identifier,
          sender_key: oracle_key,
          legacy: false, # EIP-1559
          gas_limit: 150_000 # Стандартний ліміт для мінтингу
        )
      end

      # 5. ФІНАЛІЗАЦІЯ
      if tx_hash.present?
        @transaction.confirm!(tx_hash)
        Rails.logger.info "✅ [Web3] Успіх! TX: #{tx_hash}"
      else
        raise "Транзакція не повернула хеш"
      end

    rescue StandardError => e
      # Якщо транзакція впала — логуємо помилку і відкочуємо статус
      # Sidekiq спробує ще раз через кілька хвилин
      @transaction.fail!(e.message.truncate(200))
      
      Rails.logger.error "🛑 [Web3 Error] Провал мінтингу для #{@transaction.id}: #{e.message}"
      raise e 
    end
  end
end
