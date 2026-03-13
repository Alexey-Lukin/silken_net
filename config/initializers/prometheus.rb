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
      labels: [:token_type]
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
      labels: [:network, :error_type]
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
      labels: [:queue]
    )

    # Web3 queue latency in seconds (gauge — oldest job age)
    WEB3_QUEUE_LATENCY = REGISTRY.gauge(
      :silkennet_web3_queue_latency_seconds,
      docstring: "Latency (age of oldest job) in Sidekiq web3 queues",
      labels: [:queue]
    )
  end
end
