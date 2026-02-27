# frozen_string_literal: true

require "eth"

class BlockchainMintingService
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
    # Якщо транзакція вже має хеш або не в статусі pending/failed — виходимо.
    return unless @transaction.status_pending? || @transaction.status_failed?
    return if @transaction.tx_hash.present?

    # Переводимо в статус processing для блокування повторних запусків
    @transaction.update!(status: :processing)

    # 2. ПІДКЛЮЧЕННЯ
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
      @transaction.update!(status: :failed)
      raise ArgumentError, "Невідомий тип токена"
    end

    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)
    amount_in_wei = (@transaction.amount * (10**18)).to_i
    target_address = @wallet.crypto_public_address.presence || @tree.cluster.organization.crypto_public_address

    begin
      Rails.logger.info "⏳ [Web3] Мінтинг #{@transaction.amount} токенів для #{identifier}..."

      # [ПОКРАЩЕННЯ]: Використання transact_and_wait з автоматичним nonce
      # В ідеалі тут варто додати Redis-lock на oracle_key.address
      tx_hash = client.transact_and_wait(
        contract,
        "mint",
        target_address,
        amount_in_wei,
        identifier,
        sender_key: oracle_key,
        legacy: false # Використовувати EIP-1559 для Polygon
      )

      # 4. ФІНАЛІЗАЦІЯ
      @transaction.update!(status: :confirmed, tx_hash: tx_hash)
      Rails.logger.info "✅ [Web3] Успіх! TX: #{tx_hash}"

    rescue StandardError => e
      # Якщо транзакція "застрягла" або RPC впав — міняємо статус на failed,
      # щоб воркер міг спробувати пізніше.
      @transaction.update!(status: :failed)
      Rails.logger.error "🛑 [Web3 Error] #{e.message}"
      raise e # Прокидаємо для Sidekiq retry
    end
  end
end
