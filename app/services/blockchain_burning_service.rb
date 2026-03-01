# frozen_string_literal: true

require "eth"

class BlockchainBurningService
  # ABI для функції вилучення/спалювання (Sovereign Slashing)
  CONTRACT_ABI = '[{"inputs":[{"internalType":"address","name":"investor","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"slash","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

  def self.call(organization_id, naas_contract_id, source_tree: nil)
    new(organization_id, naas_contract_id, source_tree).call
  end

  def initialize(organization_id, naas_contract_id, source_tree)
    @organization = Organization.find(organization_id)
    @naas_contract = NaasContract.find(naas_contract_id)
    @cluster = @naas_contract.cluster
    @source_tree = source_tree
  end

  def call
    # 1. АГРЕГАЦІЯ: Рахуємо всі токени, що були "зароблені" цим кластером.
    # [КЕНОЗИС]: Якщо порушення локальне (одне дерево), ми можемо вилучати 
    # або частку, або весь контракт. Наразі йдемо шляхом повної ануляції за порушення гомеостазу.
    total_minted_amount = BlockchainTransaction
                          .joins(wallet: :tree)
                          .where(trees: { cluster_id: @cluster.id })
                          .where(status: :confirmed)
                          .sum(:amount)

    return if total_minted_amount.zero?

    # 2. WEB3 ПІДГОТОВКА (The Judgment Bridge)
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))
    contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    contract = Eth::Contract.from_abi(name: "SilkenCarbonCoin", address: contract_address, abi: CONTRACT_ABI)

    amount_in_wei = (total_minted_amount.to_f * (10**18)).to_i
    investor_address = @organization.crypto_public_address

    # 3. ВИКОНАННЯ (The Verdict)
    lock_key = "lock:web3:oracle:#{oracle_key.address}"

    begin
      tx_hash = nil
      reason = @source_tree ? "загибель дерева #{@source_tree.did}" : "порушення умов кластера"
      
      Rails.logger.warn "🔥 [Slashing] Вилучення #{total_minted_amount} SCC у #{@organization.name}. Причина: #{reason}."

      Kredis.lock(lock_key, expires_in: 60.seconds, after_timeout: :raise) do
        tx_hash = client.transact_and_wait(
          contract, "slash", investor_address, amount_in_wei,
          sender_key: oracle_key, legacy: false
        )
      end

      # 4. ФІКСАЦІЯ (Immutable Audit)
      if tx_hash.present?
        # Маркуємо контракт як розірваний. Це автоматично блокує майбутні виплати.
        @naas_contract.update!(status: :breached)

        create_audit_transaction(tx_hash, total_minted_amount, reason)
        Rails.logger.info "✅ [Slashing] Виконано. TX: #{tx_hash}"
      end

    rescue StandardError => e
      # Контракт розривається в БД миттєво, навіть якщо блокчейн "лагає"
      @naas_contract.update!(status: :breached)
      handle_slashing_failure(e.message, total_minted_amount)
      raise e
    end
  end

  private

  def create_audit_transaction(tx_hash, amount, reason)
    # Фіксуємо подію в реєстрі Скарбниці
    audit_wallet = @source_tree&.wallet || @cluster.trees.active.first&.wallet
    return unless audit_wallet

    BlockchainTransaction.create!(
      wallet: audit_wallet,
      sourceable: @naas_contract,
      amount: amount,
      token_type: :carbon_coin,
      status: :confirmed,
      tx_hash: tx_hash,
      notes: "🚨 SLASHING: Кошти вилучено. Причина: #{reason}."
    )
  end

  def handle_slashing_failure(error_msg, amount)
    Rails.logger.error "🛑 [Slashing Failure] ##{@naas_contract.id}: #{error_msg}"
    
    # Створюємо критичний алерт для ручного втручання Оракула
    EwsAlert.create!(
      cluster: @cluster,
      severity: :critical,
      alert_type: :system_fault,
      message: "Критичний збій спалювання #{amount} SCC. Можлива втрата контролю над активами інвестора. Error: #{error_msg}"
    )
  end
end
