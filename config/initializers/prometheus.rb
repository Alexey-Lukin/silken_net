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

    # Web3 queue size (gauge — set on each scrape via collector callback)
    WEB3_QUEUE_SIZE = REGISTRY.gauge(
      :silkennet_web3_queue_size,
      docstring: "Current size of the Sidekiq web3 queue",
      labels: [ :queue ]
    )

    # Web3 queue latency in seconds (gauge — oldest job age)
    WEB3_QUEUE_LATENCY = REGISTRY.gauge(
      :silkennet_web3_queue_latency_seconds,
      docstring: "Latency (age of oldest job) in Sidekiq web3 queues",
      labels: [ :queue ]
    )

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
