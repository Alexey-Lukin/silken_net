# frozen_string_literal: true

require "eth"

class BlockchainMintingService
  # ABI оновлено для підтримки поштучного mint та пакетного batchMint
  CONTRACT_ABI = [
    {
      "inputs" => [
        { "internalType" => "address", "name" => "to", "type" => "address" },
        { "internalType" => "uint256", "name" => "amount", "type" => "uint256" },
        { "internalType" => "string", "name" => "identifier", "type" => "string" }
      ],
      "name" => "mint", "outputs" => [], "stateMutability" => "nonpayable", "type" => "function"
    },
    {
      "inputs" => [
        { "internalType" => "address[]", "name" => "recipients", "type" => "address[]" },
        { "internalType" => "uint256[]", "name" => "amounts", "type" => "uint256[]" },
        { "internalType" => "string[]", "name" => "treeDids", "type" => "string[]" }
      ],
      "name" => "batchMint", "outputs" => [], "stateMutability" => "nonpayable", "type" => "function"
    }
  ].to_json

  # Поштучний виклик
  def self.call(blockchain_transaction_id)
    new([ blockchain_transaction_id ]).call
  end

  # Пакетний виклик для цілого сектора/кластера
  def self.call_batch(blockchain_transaction_ids)
    new(blockchain_transaction_ids).call
  end

  def initialize(transaction_ids)
    @transactions = BlockchainTransaction.where(id: transaction_ids)
                                         .where.not(status: :confirmed)
    @wallet_mapping = @transactions.includes(wallet: :tree).index_by(&:id)
  end

  def call
    return if @transactions.empty?

    # 1. ПІДКЛЮЧЕННЯ (The Alchemy Link)
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

    # [SAFETY]: Перевірка балансу Оракула
    balance = client.get_balance(oracle_key.address)
    raise "🚨 [Web3] Критично низький баланс Оракула: #{balance}" if balance < 0.05 * (10**18)

    # 2. ГРУПУВАННЯ ЗА ТИПОМ ТОКЕНА (SCC та SFC мають різні контракти)
    @transactions.group_by(&:token_type).each do |token_type, txs|
      process_token_group(client, oracle_key, token_type, txs)
    end
  end

  private

  def process_token_group(client, oracle_key, token_type, txs)
    contract_address = case token_type
                       when "carbon_coin" then ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
                       when "forest_coin" then ENV.fetch("FOREST_COIN_CONTRACT_ADDRESS")
                       else raise ArgumentError, "Невідомий тип токена: #{token_type}"
    end

    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)
    lock_key = "lock:web3:oracle:#{oracle_key.address}"

    begin
      tx_hash = nil

      Kredis.lock(lock_key, expires_in: 90.seconds, after_timeout: :raise) do
        # Переводимо всі транзакції в статус обробки
        txs.each do |tx|
          tx.update!(status: :processing)
          broadcast_tx_update(tx)
        end

        if txs.size == 1
          # Одиночний мінтинг
          tx = txs.first
          tx_hash = client.transact_and_wait(
            contract, "mint", tx.to_address, to_wei(tx.amount), identifier_for(tx),
            sender_key: oracle_key, legacy: false
          )
        else
          # 💎 ПАКЕТНИЙ МІНТИНГ (Gas Saving Mode)
          recipients = txs.map(&:to_address)
          amounts = txs.map { |tx| to_wei(tx.amount) }
          identifiers = txs.map { |tx| identifier_for(tx) }

          Rails.logger.info "📦 [Web3] BatchMinting #{txs.size} транзакцій для #{token_type}..."

          tx_hash = client.transact_and_wait(
            contract, "batchMint", recipients, amounts, identifiers,
            sender_key: oracle_key, legacy: false
          )
        end
      end

      # 5. ПІДТВЕРДЖЕННЯ ВСЬОГО ПАКЕТА
      if tx_hash.present?
        txs.each do |tx|
          tx.confirm!(tx_hash)
          broadcast_tx_update(tx)
        end
        Rails.logger.info "✅ [Web3] Пакет виконано. TX: #{tx_hash}"
      end

    rescue StandardError => e
      txs.each do |tx|
        tx.fail!(e.message.truncate(200))
        broadcast_tx_update(tx)
      end
      Rails.logger.error "🛑 [Web3 Failure] Пакетна помилка: #{e.message}"
      raise e
    end
  end

  def identifier_for(tx)
    tree = tx.wallet.tree
    tx.token_type == "carbon_coin" ? (tree&.did || "ORG_#{tx.wallet.organization_id}") : "CLUSTER_#{tree&.cluster_id || 'GLOBAL'}"
  end

  def to_wei(amount)
    (amount.to_f * (10**18)).to_i
  end

  def broadcast_tx_update(transaction)
    wallet = transaction.wallet
    
    # Оновлення рядка в таблиці
    Turbo::StreamsChannel.broadcast_replace_to(
      wallet,
      target: "transaction_#{transaction.id}",
      html: Views::Components::Wallets::TransactionRow.new(tx: transaction).call
    )

    # Оновлення балансу (тільки при успіху або старті)
    Turbo::StreamsChannel.broadcast_replace_to(
      wallet,
      target: "wallet_balance_#{wallet.id}",
      html: Views::Components::Wallets::BalanceDisplay.new(wallet: wallet).call
    )
  end
end
