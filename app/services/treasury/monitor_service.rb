# frozen_string_literal: true

require "eth"
require "bigdecimal"

module Treasury
  # =========================================================================
  # 💰 TREASURY MONITOR SERVICE (Централізований моніторинг Oracle Wallets)
  # =========================================================================
  # Перевіряє баланси Oracle-гаманців на ВСІХ мережах одночасно:
  #   - Polygon (MATIC) → мінтинг SCC/SFC, слешинг
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

    # [ARCH.62] Токен-типи, чий заминчений обсяг детектор стежить (SCC + SFC).
    MINT_TOKEN_TYPES = %w[carbon_coin forest_coin].freeze
    # Ковзне вікно виміру обсягу мінту (partition-prune bound на created_at).
    MINT_VOLUME_WINDOW = 1.hour
    # Kredis-прапор inert circuit-break: детектор ставить per-token лише коли поріг увімкнено;
    # BlockchainMintingService читає його per token-group (ключ-prefix = One-Home там). TTL >
    # monitor-schedule → авто-release коли сплеск минув, авто-re-trip поки триває.
    MINT_CIRCUIT_TTL = 1.hour

    def perform
      results = DEFAULTS.map do |chain_key, defaults|
        config = build_config(chain_key, defaults)
        check_balance(chain_key, config)
      end

      # Оновлюємо Prometheus gauges
      update_metrics(results)

      # [G1/G2] Money-path limbo + drift видимість (той самий 15-хв прохід).
      update_money_path_metrics

      # [ARCH.62] Агрегатна mint-volume аномалія (той самий money-path прохід).
      detect_mint_volume_anomaly!

      # Генеруємо алерти для критичних балансів
      generate_alerts(results)

      results
    end

    private

    # [G1] manual_review-глибина + limbo-locked + [G2] chain-audit drift → Prometheus.
    # Без цих gauge стан «кошти застрягли/розійшлися» невидимий до ручної перевірки.
    def update_money_path_metrics
      SilkenNet::Metrics::BLOCKCHAIN_MANUAL_REVIEW_DEPTH.set(
        BlockchainTransaction.status_manual_review.count
      )

      limbo = BlockchainTransaction
              .where(status: [ :sent, :manual_review ])
              .where("created_at < ?", 1.hour.ago)
              .sum(:locked_points)
      SilkenNet::Metrics::BLOCKCHAIN_LIMBO_LOCKED_TOTAL.set(limbo.to_i)

      # ChainAuditService кешується (5хв) — дешевий тут; critical=true теж читає gauge.
      SilkenNet::Metrics::CHAIN_AUDIT_DELTA.set(ChainAuditService.call.delta.to_f)

      # [INF.22] Filecoin archive-backlog семплиться ТУТ (15-хв money-path прохід), НЕ у
      # FilecoinReconcileWorker (repair — daily :48): in-process gauge обнуляється на restart
      # job-контейнера (Akash-lease/deploy/OOM) → daily-семпл давав би ~24h сліпе вікно; 15-хв
      # cadence робить `min_over_time[6h]`-alert осмисленим. ВЕСЬ pending_archive (не LOOKBACK-
      # вікно) — post-LOOKBACK хвіст тримає плато, оператор бачить persistent-діру, не нуль.
      SilkenNet::Metrics::FILECOIN_UNARCHIVED_DEPTH.set(AuditLog.pending_archive.count)
    rescue StandardError => e
      # Спостережуваність не сміє валити monitor-цикл (баланси важливіші).
      Rails.logger.error "🛑 [Treasury] update_money_path_metrics: #{e.message}"
    end

    # [ARCH.62] Агрегатний mint-volume detector — комплемент, не заміна ex-post-clawback
    # (ARCH.53/SLASH-1 §3.3): обмежує blast-radius over-мінту у вікні детекції, поки clawback
    # (SE050 L2) не збудований. Gauge живий завжди (видимість обсягу); alert+circuit-break
    # активні ЛИШЕ коли SystemParameter-пороги увімкнено (inert-default — числа калібруються
    # з перших live-вікон, 👤). 05_02 §Модель довіри.
    def detect_mint_volume_anomaly!
      max_scc = SystemParameter.current(:mint_volume_hourly_max_scc, default: 0).to_f
      breaker_on = ActiveModel::Type::Boolean.new.cast(
        SystemParameter.current(:mint_circuit_breaker_enabled, default: false)
      )

      MINT_TOKEN_TYPES.each do |token_type|
        volume = BlockchainTransaction
                 .where(token_type: token_type, status: [ :sent, :confirmed ])
                 .where("created_at >= ?", MINT_VOLUME_WINDOW.ago)
                 .sum(:amount).to_f
        SilkenNet::Metrics::MINT_VOLUME_WINDOW_SCC.set(volume, labels: { token_type: token_type })

        # Поріг 0 = detector-off (gauge все одно живий) — не алертимо, поки 👤 не налаштує.
        next unless max_scc.positive? && volume > max_scc

        Rails.logger.warn "🚨 [ARCH.62] Mint-volume аномалія: #{token_type} " \
                          "#{volume.round(2)} SCC за #{MINT_VOLUME_WINDOW.inspect} (поріг #{max_scc.round(2)})."
        # Dedup: sustained breach інакше плодив би critical-алерт щоцикл (~4/год/токен) → флуд
        # ops-черги. Один активний mint-volume-алерт на token_type достатньо.
        unless active_mint_volume_alert?(token_type)
          EwsAlert.create(
            alert_type: :system_fault,
            severity: :critical,
            message: "Mint-volume anomaly [ARCH.62] #{token_type}: #{volume.round(2)} minted in the last " \
                     "#{MINT_VOLUME_WINDOW.inspect} exceeds the configured ceiling (#{max_scc.round(2)}). " \
                     "Possible firmware/pipeline bug or misused MINTER key. Verify recent mint tx before topping the ceiling."
          )
        end
        # Inert circuit-break: per-token HOLD нових mint-батчів, поки людина не звірить причину.
        trip_mint_circuit!(token_type, volume, max_scc) if breaker_on
      end
    rescue StandardError => e
      # Детектор — спостережуваність; не валимо monitor-цикл (баланси важливіші).
      Rails.logger.error "🛑 [Treasury] detect_mint_volume_anomaly!: #{e.message}"
    end

    # Активний mint-volume-алерт для цього token_type уже висить? (dedup — див. detector).
    # sanitize_sql_like екранує `_` у token_type (інакше LIKE-wildcard).
    def active_mint_volume_alert?(token_type)
      safe = ActiveRecord::Base.sanitize_sql_like(token_type)
      EwsAlert.where(alert_type: :system_fault, status: :active)
              .where("message LIKE ?", "Mint-volume anomaly [ARCH.62] #{safe}:%")
              .exists?
    end

    # Ставить inert per-token Kredis-прапор, який BlockchainMintingService читає per token-group →
    # HOLD цих mint-батчів у :pending (re-runnable) до TTL-expiry/reset. Reset — console (.remove).
    def trip_mint_circuit!(token_type, volume, max_scc)
      Kredis.flag("#{BlockchainMintingService::MINT_CIRCUIT_FLAG_PREFIX}#{token_type}").mark(expires_in: MINT_CIRCUIT_TTL)
      Rails.logger.error "🛑 [ARCH.62] Mint circuit-breaker TRIPPED (#{token_type}: #{volume.round(2)} > #{max_scc.round(2)}) — " \
                         "нові #{token_type} mint-батчі тримаються :pending до TTL-expiry/reset."
    end

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
