# frozen_string_literal: true

require "eth"

class BlockchainMintingService
  # Універсальний ABI для обох контрактів.
  # Оскільки обидві функції mint() приймають (address, uint256, string),
  # ми можемо використовувати один ABI, назвавши третій параметр просто "identifier".
  CONTRACT_ABI = '[{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"string","name":"identifier","type":"string"}],"name":"mint","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

  def self.call(blockchain_transaction_id)
    new(blockchain_transaction_id).call
  end

  def initialize(blockchain_transaction_id)
    @transaction = BlockchainTransaction.find(blockchain_transaction_id)
    @wallet = @transaction.wallet

    # Знаходимо дерево (Солдата), з гаманця якого ініційовано мінтинг
    @tree = @wallet.tree
  end

  def call
    # Захист від подвійного мінтингу. 
    # Працюємо ТІЛЬКИ якщо транзакція в очікуванні.
    return unless @transaction.status_pending?

    # БЛОКУВАННЯ: Миттєво переводимо в статус processing, щоб Sidekiq 
    # при випадковому ретраї не запустив паралельний мінтинг.
    @transaction.update!(status: :processing)

    # 1. Підключення до ноди (через Alchemy) та ініціалізація Оракула
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

    # 2. МАРШРУТИЗАТОР ТОКЕНІВ (Dual-Token Economy)
    # Визначаємо адресу контракту та ідентифікатор для публічного аудиту
    if @transaction.token_type == "carbon_coin"
      contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
      identifier = @tree.did # Для вуглецю звітуємо за кожне дерево окремо
    elsif @transaction.token_type == "forest_coin"
      contract_address = ENV.fetch("FOREST_COIN_CONTRACT_ADDRESS")
      identifier = "CLUSTER_#{@tree.cluster.id}" # Для біорізноманіття звітуємо за ліс
    else
      # Якщо сталась архітектурна помилка, повертаємо статус і зупиняємось
      @transaction.update!(status: :failed)
      raise ArgumentError, "Невідомий тип токена: #{@transaction.token_type}"
    end

    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)

    # 3. Підготовка даних (1 токен = 1 * 10^18 wei)
    # ВАЖЛИВО: .to_i гарантує відсутність Float-значень, які крашать EVM-транзакції
    amount_in_wei = (@transaction.amount * (10**18)).to_i
    investor_address = @wallet.crypto_public_address

    begin
      Rails.logger.info "⏳ [Web3] Ініціація мінтингу #{@transaction.amount} #{@transaction.token_type.upcase} для #{identifier}..."

      # 4. Формування, підпис (ECDSA) та відправка транзакції
      # client.transact_and_wait блокує потік до підтвердження блоку мережею
      tx_hash = client.transact_and_wait(
        contract,
        "mint",
        investor_address,
        amount_in_wei,
        identifier,
        sender_key: oracle_key
      )

      # 5. Успіх: записуємо хеш назавжди
      @transaction.update!(status: :confirmed, tx_hash: tx_hash)
      Rails.logger.info "✅ [Web3] Успішний мінтинг! Хеш: #{tx_hash}"

    rescue StandardError => e
      # Ми БІЛЬШЕ НЕ робимо Rollback тут. 
      # Ми просто логуємо удар і прокидаємо помилку у Воркер, 
      # який вирішить: робити retry чи остаточно ховати транзакцію.
      Rails.logger.error "🛑 [Web3] Помилка мінтингу RPC: #{e.message}."
      raise e
    end
  end
end
