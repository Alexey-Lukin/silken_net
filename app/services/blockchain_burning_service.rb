# frozen_string_literal: true

require "eth"

class BlockchainBurningService
  # ABI для функції вилучення/спалювання (Sovereign Slashing)
  CONTRACT_ABI = '[{"inputs":[{"internalType":"address","name":"investor","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"slash","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

  def self.call(organization_id, naas_contract_id)
    new(organization_id, naas_contract_id).call
  end

  def initialize(organization_id, naas_contract_id)
    @organization = Organization.find(organization_id)
    @naas_contract = NaasContract.find(naas_contract_id)
    @cluster = @naas_contract.cluster
  end

  def call
    # 1. АГРЕГАЦІЯ: Рахуємо всі токени, що були "зароблені" цим кластером
    total_minted_amount = BlockchainTransaction
                          .joins(wallet: :tree)
                          .where(trees: { cluster_id: @cluster.id })
                          .where(status: :confirmed)
                          .sum(:amount)

    return if total_minted_amount.zero?

    # 2. WEB3 ПІДГОТОВКА
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))
    contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    contract = Eth::Contract.from_abi(name: "SilkenCarbonCoin", address: contract_address, abi: CONTRACT_ABI)

    amount_in_wei = (total_minted_amount.to_f * (10**18)).to_i
    investor_address = @organization.crypto_public_address

    # 3. ВИКОНАННЯ (The Judgment)
    lock_key = "lock:web3:oracle:#{oracle_key.address}"
    
    begin
      tx_hash = nil
      Rails.logger.warn "🔥 [Slashing] Вилучення #{total_minted_amount} SCC у #{@organization.name}..."

      Kredis.lock(lock_key, expires_in: 60.seconds, after_timeout: :raise) do
        # Використовуємо EIP-1559 з високим пріоритетом для швидкої страти
        tx_hash = client.transact_and_wait(
          contract,
          "slash",
          investor_address,
          amount_in_wei,
          sender_key: oracle_key,
          legacy: false
        )
      end

      # 4. ФІКСАЦІЯ (Audit Trail)
      if tx_hash.present?
        # Позначаємо контракт як BREACHED (Розірвано)
        @naas_contract.update!(status: :breached)

        # Створюємо фінальний запис про спалення для прозорості
        create_audit_transaction(tx_hash, total_minted_amount)
        
        Rails.logger.info "✅ [Slashing] Виконано. Контракт ##{@naas_contract.id} анульовано. TX: #{tx_hash}"
      end

    rescue StandardError => e
      # Навіть якщо транзакція впала (напр. недостатньо токенів на гаманці), 
      # ми все одно маркуємо контракт як розірваний.
      @naas_contract.update!(status: :breached)
      
      handle_slashing_failure(e.message, total_minted_amount)
      raise e 
    end
  end

  private

  def create_audit_transaction(tx_hash, amount)
    # Шукаємо якір для логування (Wallet першого живого дерева)
    audit_wallet = @cluster.trees.active.first&.wallet
    return unless audit_wallet

    BlockchainTransaction.create!(
      wallet: audit_wallet,
      sourceable: @naas_contract,
      amount: amount,
      token_type: :carbon_coin,
      status: :confirmed,
      tx_hash: tx_hash,
      notes: "🚨 SLASHING: Кошти вилучено у інвестора через порушення гомеостазу лісу."
    )
  end

  def handle_slashing_failure(error_msg, amount)
    Rails.logger.error "🛑 [Web3 Slashing Error] ##{@naas_contract.id}: #{error_msg}"
    
    EwsAlert.create!(
      cluster: @cluster,
      severity: :critical,
      alert_type: :system_fault,
      message: "Slashing Failure: Не вдалося спалити #{amount} SCC. Можливо, токени виведені. Error: #{error_msg}"
    )
  end
end
