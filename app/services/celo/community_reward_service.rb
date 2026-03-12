# frozen_string_literal: true

require "eth"

module Celo
  # =========================================================================
  # 🌿 CELO COMMUNITY REWARD SERVICE (Позитивний зворотний зв'язок)
  # =========================================================================
  # Якщо BurnCarbonTokensWorker — це "Батіг" (Slashing за смерть лісу),
  # то Celo — це "Пряник" (cUSD на смартфон лісника за ідеальне здоров'я лісу).
  #
  # Використовує стандартний ERC-20 інтерфейс для переказу cUSD (Celo Dollar)
  # з системного казначейства на гаманець організації.
  # =========================================================================
  class CommunityRewardService
    # Мінімальний ERC-20 ABI — лише transfer(address,uint256)
    ERC20_TRANSFER_ABI = [
      {
        "inputs" => [
          { "internalType" => "address", "name" => "to", "type" => "address" },
          { "internalType" => "uint256", "name" => "amount", "type" => "uint256" }
        ],
        "name" => "transfer",
        "outputs" => [
          { "internalType" => "bool", "name" => "", "type" => "bool" }
        ],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ].to_json

    # Celo Alfajores Testnet RPC (перемикається на Mainnet через ENV)
    DEFAULT_RPC_URL = "https://alfajores-forno.celo-testnet.org"

    # Фіксована винагорода за ідеальний стан кластера (5 cUSD)
    REWARD_AMOUNT = "5.0"

    # cUSD має 18 десяткових знаків (стандарт ERC-20)
    TOKEN_DECIMALS = 18

    # Максимальний stress_index для отримання винагороди
    MAX_STRESS_INDEX = 0.2

    def initialize(cluster, target_date)
      @cluster = cluster
      @target_date = target_date
    end

    def reward_community!
      # Guard Clause 1: Перевірка здоров'я кластера через AiInsight
      insight = fetch_health_insight
      return unless eligible_for_reward?(insight)

      # Guard Clause 2: Перевірка наявності гаманця організації
      organization = @cluster.organization
      return unless organization&.crypto_public_address.present?

      # Підключення до Celo RPC — Thread-cached RPC client
      client = Web3::RpcConnectionPool.client_for("CELO_RPC_URL", fallback: DEFAULT_RPC_URL)
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

      cusd_contract_address = ENV.fetch("CELO_CUSD_CONTRACT_ADDRESS")
      contract = Eth::Contract.from_abi(
        name: "CeloUSD",
        address: cusd_contract_address,
        abi: ERC20_TRANSFER_ABI
      )

      amount_in_wei = Web3::WeiConverter.to_wei(REWARD_AMOUNT, TOKEN_DECIMALS)
      recipient = organization.crypto_public_address
      lock_key = "lock:web3:oracle:#{oracle_key.address}"

      begin
        tx_hash = nil

        Kredis.lock(lock_key, expires_in: 30.seconds, after_timeout: :raise) do
          tx_hash = client.transact(
            contract, "transfer", recipient, amount_in_wei,
            sender_key: oracle_key, legacy: false
          )
        end

        if tx_hash.present?
          create_reward_transaction(tx_hash, recipient)

          Rails.logger.info "🌿 [Celo ReFi] Винагорода #{REWARD_AMOUNT} cUSD → #{organization.name} (Кластер: #{@cluster.name}, Дата: #{@target_date})"
        end

        tx_hash
      rescue StandardError => e
        Rails.logger.error "🛑 [Celo ReFi] Помилка переказу cUSD для кластера #{@cluster.name}: #{e.message}"
        raise e
      end
    end

    private

    def fetch_health_insight
      @cluster.ai_insights
              .daily_health_summary
              .for_date(@target_date)
              .first
    end

    def eligible_for_reward?(insight)
      return false if insight.nil?
      return false if insight.stress_index.nil?
      return false if insight.stress_index > MAX_STRESS_INDEX
      return false if insight.fraud_detected?

      true
    end

    def create_reward_transaction(tx_hash, recipient)
      BlockchainTransaction.create!(
        cluster: @cluster,
        sourceable: @cluster,
        to_address: recipient,
        amount: REWARD_AMOUNT,
        token_type: :cusd,
        blockchain_network: "celo",
        status: :sent,
        tx_hash: tx_hash,
        notes: "🌿 Celo ReFi: Винагорода #{REWARD_AMOUNT} cUSD за ідеальне здоров'я кластера #{@cluster.name} (#{@target_date})."
      )
    end
  end
end
