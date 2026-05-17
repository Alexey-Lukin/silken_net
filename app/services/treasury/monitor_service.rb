# frozen_string_literal: true

require "eth"
require "bigdecimal"

module Treasury
  # =========================================================================
  # 💰 TREASURY MONITOR SERVICE (Централізований моніторинг Oracle Wallets)
  # =========================================================================
  # Перевіряє баланси Oracle-гаманців на ВСІХ мережах одночасно:
  #   - Polygon (MATIC) → мінтинг SCC/SFC, слешинг, Chainlink dispatch
  #   - Solana (SOL) → мікро-винагороди USDC
  #   - Celo (CELO) → community rewards cUSD
  #   - Ethereum L1 (ETH) → state root anchoring (щотижня)
  #
  # Повертає структурований звіт для Prometheus gauges та EWS alerts.
  # Підтримує пороги (мінімальні баланси) для кожної мережі.
  #
  # Використання:
  #   report = Treasury::MonitorService.call
  #   report.each { |r| puts "#{r[:network]}: #{r[:status]}" }
  # =========================================================================
  class MonitorService < ApplicationService
    # [E.51] Мінімальні пороги балансу Oracle wallets — configurable через SystemParameter.
    # Дефолтні значення використовуються як fallback якщо SystemParameter ще не seed-нуті.
    # Governance: може бути оновлено через ProtocolParameters.sol + ParameterSyncWorker.
    DEFAULTS = {
      polygon: { min_balance: 0.05, currency: "MATIC", decimals: 18, param_key: "oracle_min_balance_matic" },
      solana:  { min_balance: 0.05, currency: "SOL",   decimals: 9,  param_key: "oracle_min_balance_sol" },
      celo:    { min_balance: 0.05, currency: "CELO",  decimals: 18, param_key: "oracle_min_balance_celo" },
      ethereum: { min_balance: 0.01, currency: "ETH",  decimals: 18, param_key: "oracle_min_balance_eth" }
    }.freeze

    # Network-specific configuration (RPC keys, private keys, fallback URLs).
    NETWORK_CONFIG = {
      polygon: {
        network: "polygon",
        env_rpc_key: "ALCHEMY_POLYGON_RPC_URL",
        env_private_key: "ORACLE_PRIVATE_KEY"
      },
      solana: {
        network: "solana",
        env_rpc_key: "SOLANA_RPC_URL",
        env_public_key: "SOLANA_FEE_PAYER_PUBKEY"
      },
      celo: {
        network: "celo",
        env_rpc_key: "CELO_RPC_URL",
        env_private_key: "ORACLE_PRIVATE_KEY",
        fallback_rpc: "https://alfajores-forno.celo-testnet.org"
      },
      ethereum: {
        network: "ethereum",
        env_rpc_key: "ALCHEMY_ETHEREUM_RPC_URL",
        env_private_key: "ETHEREUM_ANCHOR_PRIVATE_KEY"
      }
    }.freeze

    # Таймаут для окремого RPC-виклику (секунди)
    RPC_TIMEOUT = 10

    def perform
      results = DEFAULTS.map do |chain_key, defaults|
        config = build_config(chain_key, defaults)
        check_balance(chain_key, config)
      end

      # Оновлюємо Prometheus gauges
      update_metrics(results)

      # Генеруємо алерти для критичних балансів
      generate_alerts(results)

      results
    end

    private

    # [E.51] Builds config for a chain by merging network config with governance-aware thresholds.
    # SystemParameter.current reads from 24h cache → no DB hit on every monitor cycle.
    def build_config(chain_key, defaults)
      net = NETWORK_CONFIG[chain_key]
      min_balance = (SystemParameter.current(defaults[:param_key], default: defaults[:min_balance]) || defaults[:min_balance]).to_f
      min_balance_wei = (BigDecimal(min_balance.to_s) * 10**defaults[:decimals]).to_i

      net.merge(
        currency: defaults[:currency],
        decimals: defaults[:decimals],
        min_balance_wei: min_balance_wei
      )
    end

    # Перевіряє баланс Oracle-гаманця на конкретній мережі.
    # Повертає Hash з результатом перевірки.
    def check_balance(chain_key, config)
      balance = fetch_balance(chain_key, config)

      min_threshold = config[:min_balance_wei].to_i
      ratio = min_threshold.positive? ? (balance.to_f / min_threshold) : 0.0
      status = balance >= min_threshold ? :healthy : :critical

      {
        network: config[:network],
        currency: config[:currency],
        balance_raw: balance,
        balance_human: humanize_balance(balance, config[:decimals]),
        min_threshold_raw: min_threshold,
        min_threshold_human: humanize_balance(min_threshold, config[:decimals]),
        ratio: ratio.round(2),
        status: status
      }
    rescue StandardError => e
      SilkenNet::Metrics::TREASURY_CHECK_ERRORS_TOTAL.increment(
        labels: { network: config[:network], error_type: e.class.name }
      )

      Rails.logger.error "🛑 [Treasury] #{config[:network]} balance check failed: #{e.message}"

      {
        network: config[:network],
        currency: config[:currency],
        balance_raw: nil,
        balance_human: "ERROR",
        min_threshold_raw: config[:min_balance_wei].to_i,
        min_threshold_human: humanize_balance(config[:min_balance_wei].to_i, config[:decimals]),
        ratio: 0.0,
        status: :error,
        error: e.message.truncate(200)
      }
    end

    # Отримує баланс для конкретної мережі
    def fetch_balance(chain_key, config)
      Timeout.timeout(RPC_TIMEOUT) do
        case chain_key
        when :solana then fetch_solana_balance(config)
        else fetch_evm_balance(config)
        end
      end
    end

    # EVM-мережі (Polygon, Celo, Ethereum): eth_getBalance через eth gem
    def fetch_evm_balance(config)
      client = if config[:fallback_rpc]
        Web3::RpcConnectionPool.client_for(config[:env_rpc_key], fallback: config[:fallback_rpc])
      else
        Web3::RpcConnectionPool.client_for(config[:env_rpc_key])
      end

      private_key = ENV[config[:env_private_key]]
      return 0 if private_key.blank?

      oracle_key = Eth::Key.new(priv: private_key)
      client.get_balance(oracle_key.address)
    end

    # Solana: getBalance через JSON RPC
    def fetch_solana_balance(config)
      if ENV[config[:env_rpc_key]].blank? && Rails.env.production?
        Rails.logger.warn "[Treasury] #{config[:env_rpc_key]} not set in production — Solana balance check skipped"
        return 0
      end
      rpc_url = ENV.fetch(config[:env_rpc_key], "https://api.devnet.solana.com")
      fee_payer = ENV[config[:env_public_key]]
      return 0 if fee_payer.blank?

      payload = {
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "getBalance",
        params: [ fee_payer, { commitment: "confirmed" } ]
      }

      response = Web3::HttpClient.post(rpc_url,
        body: payload,
        open_timeout: 10,
        read_timeout: RPC_TIMEOUT,
        service_name: "Solana"
      )

      response.parsed_body&.dig("result", "value").to_i
    end

    # Оновлює Prometheus gauges з поточними балансами
    def update_metrics(results)
      results.each do |result|
        network = result[:network]

        if result[:balance_raw]
          SilkenNet::Metrics::ORACLE_BALANCE.set(
            result[:balance_raw],
            labels: { network: network }
          )
        end

        SilkenNet::Metrics::ORACLE_BALANCE_RATIO.set(
          result[:ratio],
          labels: { network: network }
        )
      end
    end

    # Генерує EWS alerts для критичних балансів
    def generate_alerts(results)
      critical_results = results.select { |r| r[:status] == :critical }
      return if critical_results.empty?

      critical_results.each do |result|
        Rails.logger.warn "🚨 [Treasury] CRITICAL: #{result[:network]} Oracle balance " \
                          "#{result[:balance_human]} #{result[:currency]} " \
                          "below threshold #{result[:min_threshold_human]} #{result[:currency]} " \
                          "(ratio: #{result[:ratio]}x)"

        # Створюємо EwsAlert для оперативного реагування (system_fault — загальний тип для інфраструктурних проблем)
        EwsAlert.create(
          alert_type: :system_fault,
          severity: :critical,
          message: "#{result[:network]} Oracle wallet balance " \
                   "(#{result[:balance_human]} #{result[:currency]}) " \
                   "is below minimum threshold " \
                   "(#{result[:min_threshold_human]} #{result[:currency]}). " \
                   "Ratio: #{result[:ratio]}x. " \
                   "Blockchain transactions will fail without top-up."
        )
      end
    end

    # Конвертує wei/lamports у людський формат
    def humanize_balance(raw_balance, decimals)
      format("%.6f", (BigDecimal(raw_balance.to_s) / 10**decimals))
    end
  end
end
