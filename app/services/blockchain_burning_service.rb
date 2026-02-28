# frozen_string_literal: true

require "eth"

class BlockchainBurningService
  # ABI для функції спалювання/слашингу
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
    # 1. АГРЕГАЦІЯ ЗБИТКІВ
    # Сумуємо всі токени, випущені деревами цього кластера
    total_minted_amount = BlockchainTransaction
                          .joins(wallet: :tree)
                          .where(trees: { cluster_id: @cluster.id })
                          .where(status: :confirmed)
                          .sum(:amount)

    return if total_minted_amount.zero?

    # 2. WEB3 ІНІЦІАЛІЗАЦІЯ
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))
    contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    contract = Eth::Contract.from_abi(name: "SilkenCarbonCoin", address: contract_address, abi: CONTRACT_ABI)

    amount_in_wei = (total_minted_amount * (10**18)).to_i
    investor_address = @organization.crypto_public_address

    # 3. ВИКОНАННЯ (The Burning Ritual)
    # Захист від колізії Nonce
    lock_key = "lock:web3:oracle:#{oracle_key.address}"
    
    begin
      Rails.logger.warn "🔥 [Web3] Ініціація Slashing для #{@organization.name} на суму #{total_minted_amount} SCC..."

      tx_hash = nil
      Kredis.lock(lock_key, expires_in: 60.seconds, after_timeout: :raise) do
        tx_hash = client.transact_and_wait(
          contract,
          "slash",
          investor_address,
          amount_in_wei,
          sender_key: oracle_key,
          legacy: false # EIP-1559
        )
      end

      # 4. ФІКСАЦІЯ ПОДІЇ
      # [ВИПРАВЛЕНО]: Використовуємо системний гаманець або гаманець першого дерева для аудиту
      # BlockchainTransaction завжди потребує валідного Wallet об'єкта
      audit_wallet = @cluster.trees.first&.wallet || @organization.clusters.first&.trees&.first&.wallet

      if audit_wallet
        BlockchainTransaction.create!(
          wallet: audit_wallet,
          sourceable: @naas_contract, # Додаємо зв'язок з контрактом для аудиту
          amount: total_minted_amount,
          token_type: :carbon_coin,
          status: :confirmed,
          tx_hash: tx_hash,
          notes: "🚨 SLASHING: Контракт ##{@naas_contract.id} розірвано. Токени вилучено з гаманця #{investor_address}."
        )
      end

      # Остаточне розірвання контракту в базі
      @naas_contract.update!(status: :breached)

    rescue StandardError => e
      # Якщо транзакція впала (наприклад, інвестор вивів токени раніше)
      # Ми все одно тавруємо контракт як BREACHED, але логуємо фінансовий фейл
      @naas_contract.update!(status: :breached)
      
      Rails.logger.error "🛑 [Web3] Slashing Failed для контракту ##{@naas_contract.id}: #{e.message}"
      
      # Створюємо запис про збій для юристів/адмінів
      EwsAlert.create!(
        cluster: @cluster,
        severity: :critical,
        alert_type: :system_fault,
        message: "Slashing Protocol Failure: Не вдалося спалити #{total_minted_amount} SCC для #{@organization.name}. Error: #{e.message}"
      )
      
      raise e # Sidekiq спробує ще раз, якщо це помилка мережі, а не балансу
    end
  end
end
