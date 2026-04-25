# frozen_string_literal: true

# = ===================================================================
# 📊 PROMETHEUS METRICS (Observability for Grafana/Prometheus)
# = ===================================================================
# Lightweight metrics exporter using the official prometheus-client gem.
# Exposes custom business metrics for the Gaia 2.0 platform:
#
# - Sidekiq web3 queue size and latency
# - Web3 RPC error rates (by network/type)
# - Financial: SCC minted, locked funds, slashed tokens
# - IoT: CoAP telemetry ingest rate and fraud detection
#
# The /metrics endpoint is secured via PrometheusCollector middleware
# (IP allowlist + HTTP Basic Auth). See app/middleware/prometheus_collector.rb.

require "prometheus/client"

module SilkenNet
  module Metrics
    REGISTRY = Prometheus::Client::Registry.new

    # -----------------------------------------------------------------------
    # 💎 FINANCIAL METRICS (Web3 / Tokenomics)
    # -----------------------------------------------------------------------

    # Total SCC tokens minted (monotonic counter)
    SCC_MINTED_TOTAL = REGISTRY.counter(
      :silkennet_scc_minted_total,
      docstring: "Total SCC (SilkenCarbonCoin) tokens minted",
      labels: [ :token_type ]
    )

    # Total tokens slashed (monotonic counter)
    SCC_SLASHED_TOTAL = REGISTRY.counter(
      :silkennet_scc_slashed_total,
      docstring: "Total tokens slashed (burned due to cluster stress)"
    )

    # Web3 RPC errors (labeled by network and error type)
    RPC_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_rpc_errors_total,
      docstring: "Total Web3 RPC errors",
      labels: [ :network, :error_type ]
    )

    # -----------------------------------------------------------------------
    # 📡 IoT / TELEMETRY METRICS
    # -----------------------------------------------------------------------

    # Total telemetry chunks processed (monotonic counter)
    TELEMETRY_PROCESSED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_processed_total,
      docstring: "Total telemetry chunks processed by TelemetryUnpackerService"
    )

    # Telemetry fraud/anomaly detections (monotonic counter)
    TELEMETRY_FRAUD_DETECTED_TOTAL = REGISTRY.counter(
      :silkennet_telemetry_fraud_detected_total,
      docstring: "Total telemetry packets rejected (sensor noise, unknown DID, tamper)"
    )

    # -----------------------------------------------------------------------
    # ⚙️ SIDEKIQ QUEUE METRICS (Gauges — sampled at scrape time)
    # -----------------------------------------------------------------------
    # [PLAN 1.3]: Renamed from WEB3_QUEUE_* to SIDEKIQ_QUEUE_* to reflect
    # monitoring ALL 9 queues (uplink, alerts, critical, downlink, default,
    # web3_critical, web3, web3_low, low), not just web3.

    # Sidekiq queue size (gauge — set on each scrape via collector callback)
    SIDEKIQ_QUEUE_SIZE = REGISTRY.gauge(
      :silkennet_sidekiq_queue_size,
      docstring: "Current size of a Sidekiq queue",
      labels: [ :queue ]
    )

    # Sidekiq queue latency in seconds (gauge — oldest job age)
    SIDEKIQ_QUEUE_LATENCY = REGISTRY.gauge(
      :silkennet_sidekiq_queue_latency_seconds,
      docstring: "Latency (age of oldest job) in a Sidekiq queue",
      labels: [ :queue ]
    )

    # Legacy aliases for backward compatibility with existing Grafana dashboards.
    WEB3_QUEUE_SIZE = SIDEKIQ_QUEUE_SIZE
    WEB3_QUEUE_LATENCY = SIDEKIQ_QUEUE_LATENCY

    # -----------------------------------------------------------------------
    # 🔗 DATABASE CONNECTION POOL METRICS (Gauges — Wiki 04_01 Blocker Fix)
    # -----------------------------------------------------------------------
    # Моніторинг Connection Pool для виявлення насичення під час масової
    # телеметрії. Критично при Sidekiq concurrency=15 та pessimistic locks.

    # Total pool size (max connections per database)
    DB_POOL_SIZE = REGISTRY.gauge(
      :silkennet_db_pool_size,
      docstring: "Maximum number of connections in the database pool",
      labels: [ :database ]
    )

    # Currently active (checked out) connections
    DB_POOL_CONNECTIONS = REGISTRY.gauge(
      :silkennet_db_pool_connections,
      docstring: "Number of active (checked out) database connections",
      labels: [ :database ]
    )

    # Idle connections available in the pool
    DB_POOL_IDLE = REGISTRY.gauge(
      :silkennet_db_pool_idle,
      docstring: "Number of idle database connections in the pool",
      labels: [ :database ]
    )

    # Threads waiting for a connection checkout
    DB_POOL_WAITING = REGISTRY.gauge(
      :silkennet_db_pool_waiting,
      docstring: "Number of threads waiting for a database connection",
      labels: [ :database ]
    )

    # -----------------------------------------------------------------------
    # 💰 TREASURY / ORACLE WALLET METRICS (Multi-chain balance monitoring)
    # -----------------------------------------------------------------------
    # Відстежує баланси Oracle wallets на всіх мережах.
    # Критично для масштабування: при мільйонах дерев витрати газу зростають пропорційно.

    # Oracle wallet balance in native currency (MATIC, SOL, CELO, ETH)
    ORACLE_BALANCE = REGISTRY.gauge(
      :silkennet_oracle_balance,
      docstring: "Oracle wallet balance in native currency (wei/lamports)",
      labels: [ :network ]
    )

    # Oracle wallet balance as ratio to minimum threshold (< 1.0 = critical)
    ORACLE_BALANCE_RATIO = REGISTRY.gauge(
      :silkennet_oracle_balance_ratio,
      docstring: "Oracle balance as ratio to minimum threshold (below 1.0 = critical)",
      labels: [ :network ]
    )

    # Treasury monitor errors (network unreachable, RPC timeout)
    TREASURY_CHECK_ERRORS_TOTAL = REGISTRY.counter(
      :silkennet_treasury_check_errors_total,
      docstring: "Total treasury monitoring RPC errors",
      labels: [ :network, :error_type ]
    )

    # -----------------------------------------------------------------------
    # 🔥 WORKER-SPECIFIC METRICS (Gap Analysis — S2.4)
    # -----------------------------------------------------------------------

    # Slashing events by reason (fraud, cluster_stress, contract_breach)
    SLASHING_EVENTS_TOTAL = REGISTRY.counter(
      :silkennet_slashing_events_total,
      docstring: "Total slashing (burn) events by reason",
      labels: [ :reason ]
    )

    # OTA firmware chunks sent to field devices
    OTA_CHUNKS_SENT_TOTAL = REGISTRY.counter(
      :silkennet_ota_chunks_sent_total,
      docstring: "Total OTA firmware chunks transmitted to field devices",
      labels: [ :firmware_version ]
    )

    # Early Warning System alerts dispatched
    EWS_ALERTS_TOTAL = REGISTRY.counter(
      :silkennet_ews_alerts_total,
      docstring: "Total EWS alerts dispatched (fire, drought, pest, storm)",
      labels: [ :alert_type ]
    )

    # Chainlink oracle dispatch latency (histogram for percentile analysis)
    ORACLE_DISPATCH_DURATION = REGISTRY.histogram(
      :silkennet_oracle_dispatch_duration_seconds,
      docstring: "Chainlink oracle dispatch latency in seconds",
      buckets: [ 0.5, 1, 2.5, 5, 10, 30, 60 ]
    )

    # CoAP UDP packets received by the daemon
    COAP_PACKETS_RECEIVED_TOTAL = REGISTRY.counter(
      :silkennet_coap_packets_received_total,
      docstring: "Total CoAP UDP packets received by the telemetry daemon",
      labels: [ :status ]  # success, decrypt_error, unknown_device, malformed
    )

    # Lorenz attractor computation duration (BigDecimal, 250 iterations)
    LORENZ_COMPUTATION_DURATION = REGISTRY.histogram(
      :silkennet_lorenz_computation_duration_seconds,
      docstring: "Lorenz attractor server-side computation time (BigDecimal, 250 iterations)",
      buckets: [ 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5 ]
    )

    # [S6.6] Missed Ethereum L1 anchor weeks detected
    ANCHOR_MISSED_WEEKS_TOTAL = REGISTRY.counter(
      :silkennet_anchor_missed_weeks_total,
      docstring: "Total missed Ethereum L1 anchor weeks detected (gap > 8 days)"
    )

    # [E.50]: Streamr broadcast failures counter — раніше помилки мовчки логувались без метрик.
    # Streamr — потік присутності (не фінансовий консенсус), але масові збої потребують alerting.
    STREAMR_BROADCAST_FAILURES_TOTAL = REGISTRY.counter(
      :silkennet_streamr_broadcast_failures_total,
      docstring: "Total Streamr broadcast failures (P2P real-time telemetry delivery)"
    )

    # [ENTROPY MONITOR]: Shannon entropy of Z-value distribution per cluster.
    # Healthy forest: ≈ 0.75-0.95 (diverse Z-values). Pre-stress: < 0.65.
    # Updated by QuantumStressAnalyzerWorker (queue: alerts, hourly).
    CLUSTER_ENTROPY_SCORE = REGISTRY.gauge(
      :silkennet_cluster_entropy_score,
      docstring: "Normalized Shannon entropy of Z-value distribution per cluster (0.0-1.0)",
      labels: [ :cluster_id ]
    )

    # Snapshot connection pool stats for Prometheus scraping.
    # Called from PrometheusCollector middleware or a periodic job.
    def self.sample_connection_pool!
      ActiveRecord::Base.connection_handler.all_connection_pools.each do |pool|
        db_name = pool.db_config.name.to_s

        conns = pool.connections
        in_use = conns.count(&:in_use?)

        DB_POOL_SIZE.set(pool.size, labels: { database: db_name })
        DB_POOL_CONNECTIONS.set(in_use, labels: { database: db_name })
        DB_POOL_IDLE.set(conns.size - in_use, labels: { database: db_name })
        DB_POOL_WAITING.set(pool.num_waiting_in_queue, labels: { database: db_name })
      end
    rescue StandardError => e
      Rails.logger.warn "⚠️ [Prometheus] Connection pool sampling failed: #{e.message}"
    end
  end
end
