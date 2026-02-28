# frozen_string_literal: true

require "eth"

class BlockchainMintingService
  # ABI для нашого D-MRV контракту
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
    
    # [SAFETY]: Перевірка палива
    balance = client.get_balance(oracle_key.address)
    raise "🚨 [Web3] Критично низький баланс Оракула: #{balance}" if balance < 0.05 * (10**18)

    # 2. МАРШРУТИЗАЦІЯ (The Sovereign Tokens)
    case @transaction.token_type
    when "carbon_coin"
      contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
      identifier = @tree.did
    when "forest_coin"
      contract_address = ENV.fetch("FOREST_COIN_CONTRACT_ADDRESS")
      identifier = "CLUSTER_#{@tree.cluster_id}"
    else
      raise ArgumentError, "Невідомий тип токена: #{@transaction.token_type}"
    end

    # 3. ПІДГОТОВКА КОНТРАКТУ
    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)
    amount_in_wei = (@transaction.amount.to_f * (10**18)).to_i
    
    # 4. АТОМАРНИЙ МІНТИНГ З REDIS-LOCK
    lock_key = "lock:web3:oracle:#{oracle_key.address}"
    
    begin
      tx_hash = nil
      
      # Чекаємо вільного вікна для Nonce
      Kredis.lock(lock_key, expires_in: 60.seconds, after_timeout: :raise) do
        @transaction.update!(status: :processing)
        
        Rails.logger.info "⏳ [Web3] Мінтинг #{@transaction.amount} для #{identifier}..."
        
        # Використовуємо пріоритетну комісію для Polygon
        tx_hash = client.transact_and_wait(
          contract,
          "mint",
          @transaction.to_address,
          amount_in_wei,
          identifier,
          sender_key: oracle_key,
          legacy: false # Використовуємо EIP-1559 (Dynamic Fees)
        )
      end

      # 5. ПІДТВЕРДЖЕННЯ
      if tx_hash.present?
        @transaction.confirm!(tx_hash)
        Rails.logger.info "✅ [Web3] Виконано. DID: #{identifier} | TX: #{tx_hash}"
      end

    rescue StandardError => e
      @transaction.fail!(e.message.truncate(200))
      Rails.logger.error "🛑 [Web3 Failure] #{@transaction.id}: #{e.message}"
      raise e # Дозволяємо Sidekiq зробити retry
    end
  end
end
