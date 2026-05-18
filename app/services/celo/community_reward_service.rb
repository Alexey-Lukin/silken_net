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

    # [E.49] RPC FALLBACK CASCADE для Celo. Якщо `CELO_RPC_URL` недоступний
    # (Net::ReadTimeout / HTTP 429 / Errno::ECONNREFUSED), Web3::ResilientClient
    # автоматично переключиться на наступний URL з цього списку. Циркуіт-брейкер
    # вимикає провайдера після 3 послідовних збоїв на 60 секунд
    # (див. `Web3::ResilientClient`). Адміністратор заповнює відповідні ENV-змінні
    # реальними endpoint'ами (Ankr / 1RPC / OnFinality / приватний node).
    RPC_FALLBACK_ENV_KEYS = %w[
      CELO_RPC_URL_FALLBACK_1
      CELO_RPC_URL_FALLBACK_2
    ].freeze

    # Фіксована винагорода за ідеальний стан кластера (5 cUSD)
    REWARD_AMOUNT = "5.0"

    # cUSD має 18 десяткових знаків (стандарт ERC-20)
    TOKEN_DECIMALS = 18

    # Максимальний stress_index для отримання винагороди
    MAX_STRESS_INDEX = 0.2

    # Мінімальний баланс оракула (CELO) для оплати газу транзакцій.
    # Аналог перевірки 0.05 MATIC у BlockchainMintingService.
    MIN_ORACLE_BALANCE_WEI = 0.05 * (10**18)

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

      # Guard Clause 3 — Idempotency for cluster_health_arbitration double-fire.
      # `ClusterHealthCheckWorker` runs both from `InsightBatchCallbacks#on_success`
      # AND from the 02:00 UTC `cluster_health_arbitration` cron — for healthy
      # clusters that means `CeloRewardWorker.perform_async` is enqueued twice
      # per day. The oracle Kredis lock serialises Celo TX broadcasts but does
      # NOT dedupe by (cluster, date), so without this check the org would be
      # paid 10 cUSD instead of 5 on every healthy day. We look at the audit
      # ledger we just wrote (`BlockchainTransaction` with `sourceable=cluster`,
      # `token_type=cusd`, status in `[:sent, :confirmed]`) for `@target_date`
      # and short-circuit if found.
      if reward_already_sent?
        Rails.logger.info "🌿 [Celo ReFi] Пропускаю — кластер #{@cluster.name} вже отримав cUSD за #{@target_date}."
        return
      end

      # Підключення до Celo RPC — Thread-cached RPC client з fallback cascade [E.49]
      client = Web3::RpcConnectionPool.client_for(
        "CELO_RPC_URL",
        fallback: DEFAULT_RPC_URL,
        fallback_env_keys: RPC_FALLBACK_ENV_KEYS
      )
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_PRIVATE_KEY"))

      # [BLOCKER-1 FIX]: Guard clause — перевірка балансу оракула перед відправкою транзакції.
      # Аналог BlockchainMintingService: raise if balance < 0.05 CELO.
      balance = client.get_balance(oracle_key.address)
      raise "🚨 [Celo] Критично низький баланс Оракула: #{balance}" if balance < MIN_ORACLE_BALANCE_WEI

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

    # True if we already wrote an audit-ledger entry for this cluster on the
    # same target_date for cUSD. Uses the date window `[target_date 00:00,
    # target_date+1 00:00)` against `created_at` so partition pruning kicks
    # in (`blockchain_transactions` is RANGE-partitioned by `created_at`).
    # `manual_review` and `failed` states do NOT count as a sent reward —
    # an admin retry must be able to deliver them.
    def reward_already_sent?
      window_start = @target_date.is_a?(Date) ? @target_date.beginning_of_day : @target_date
      window_end   = window_start + 1.day

      BlockchainTransaction
        .where(sourceable: @cluster, token_type: :cusd, blockchain_network: "celo")
        .where(status: [ :sent, :confirmed, :processing ])
        .where(created_at: window_start...window_end)
        .exists?
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
