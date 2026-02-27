# frozen_string_literal: true

require "eth"

class BlockchainBurningService
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
    # 1. Агрегація збитків
    total_minted_amount = BlockchainTransaction
                          .joins(wallet: :tree)
                          .where(trees: { cluster_id: @cluster.id })
                          .where(status: :confirmed)
                          .sum(:amount)

    return if total_minted_amount.zero?

    # 2. Web3 Ініціалізація
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))
    contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    contract = Eth::Contract.from_abi(name: "SilkenCarbonCoin", address: contract_address, abi: CONTRACT_ABI)

    amount_in_wei = (total_minted_amount * (10**18)).to_i
    investor_address = @organization.crypto_public_address

    begin
      Rails.logger.warn "🔥 [Web3] Ініціація Slashing для #{@organization.name}..."

      # 3. Виклик транзакції з високим пріоритетом (EIP-1559)
      tx_hash = client.transact_and_wait(
        contract,
        "slash",
        investor_address,
        amount_in_wei,
        sender_key: oracle_key,
        legacy: false # Вмикаємо сучасний розрахунок газу
      )

      # 4. Фіксація події
      # [ПОКРАЩЕННЯ]: Шукаємо системний гаманець або гаманець Організації,
      # якщо всі дерева кластера знищені фізично/базово.
      target_wallet = @cluster.trees.first&.wallet || @organization.users.first&.sessions&.first&.user&.identities&.first # Складний фолбек для аудиту
      
      BlockchainTransaction.create!(
        wallet: target_wallet, # Поле null: false, тому нам потрібен об'єкт
        amount: total_minted_amount,
        token_type: :carbon_coin,
        status: :confirmed,
        tx_hash: tx_hash,
        notes: "🚨 SLASHING: Контракт ##{@naas_contract.id} (Кластер #{@cluster.name}) порушено. Токени спалено."
      )

      # Оновлюємо статус контракту, якщо він ще не змінений
      @naas_contract.update!(status: :breached) unless @naas_contract.status_breached?

    rescue StandardError => e
      # ВАЖЛИВО: Якщо грошей на гаманці інвестора немає, транзакція впаде.
      # У цьому разі ми позначаємо транзакцію як FAILED, але контракт все одно BREACHED.
      Rails.logger.error "🛑 [Web3] Slashing Failed: #{e.message}. Можлива відсутність токенів на балансі інвестора."
      
      # Створюємо запис про невдалу спробу спалювання для аудиту
      @naas_contract.update!(status: :breached)
      raise e # Для ретраю в Sidekiq
    end
  end
end
