# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::Metrics do
  it "defines the metrics registry" do
    expect(described_class::REGISTRY).to be_a(Prometheus::Client::Registry)
  end

  it "registers scc_minted_total counter" do
    metric = described_class::REGISTRY.get(:silkennet_scc_minted_total)
    expect(metric).to be_a(Prometheus::Client::Counter)
  end

  it "registers scc_slashed_total counter" do
    metric = described_class::REGISTRY.get(:silkennet_scc_slashed_total)
    expect(metric).to be_a(Prometheus::Client::Counter)
  end

  it "registers rpc_errors_total counter with network and error_type labels" do
    metric = described_class::REGISTRY.get(:silkennet_rpc_errors_total)
    expect(metric).to be_a(Prometheus::Client::Counter)
  end

  it "registers telemetry_processed_total counter" do
    metric = described_class::REGISTRY.get(:silkennet_telemetry_processed_total)
    expect(metric).to be_a(Prometheus::Client::Counter)
  end

  it "registers telemetry_fraud_detected_total counter" do
    metric = described_class::REGISTRY.get(:silkennet_telemetry_fraud_detected_total)
    expect(metric).to be_a(Prometheus::Client::Counter)
  end

  it "registers sidekiq_queue_size gauge" do
    metric = described_class::REGISTRY.get(:silkennet_sidekiq_queue_size)
    expect(metric).to be_a(Prometheus::Client::Gauge)
  end

  it "registers sidekiq_queue_latency_seconds gauge" do
    metric = described_class::REGISTRY.get(:silkennet_sidekiq_queue_latency_seconds)
    expect(metric).to be_a(Prometheus::Client::Gauge)
  end

  it "increments scc_minted_total counter" do
    metric = described_class::SCC_MINTED_TOTAL
    before_val = metric.get(labels: { token_type: "carbon_coin" })

    metric.increment(labels: { token_type: "carbon_coin" })

    after_val = metric.get(labels: { token_type: "carbon_coin" })
    expect(after_val).to eq(before_val + 1.0)
  end

  it "increments rpc_errors_total counter with labels" do
    metric = described_class::RPC_ERRORS_TOTAL
    before_val = metric.get(labels: { network: "Polygon", error_type: "timeout" })

    metric.increment(labels: { network: "Polygon", error_type: "timeout" })

    after_val = metric.get(labels: { network: "Polygon", error_type: "timeout" })
    expect(after_val).to eq(before_val + 1.0)
  end

  # -----------------------------------------------------------------------
  # S2.4: 5 нових метрик (Sprint 2, Gap Analysis)
  # -----------------------------------------------------------------------

  describe "S2.4 — new worker-specific metrics registration" do
    it "registers slashing_events_total counter with reason label" do
      metric = described_class::REGISTRY.get(:silkennet_slashing_events_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers ota_chunks_sent_total counter with firmware_version label" do
      metric = described_class::REGISTRY.get(:silkennet_ota_chunks_sent_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers ews_alerts_total counter with alert_type label" do
      metric = described_class::REGISTRY.get(:silkennet_ews_alerts_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers oracle_dispatch_duration_seconds histogram" do
      metric = described_class::REGISTRY.get(:silkennet_oracle_dispatch_duration_seconds)
      expect(metric).to be_a(Prometheus::Client::Histogram)
    end

    it "registers coap_packets_received_total counter with status label" do
      metric = described_class::REGISTRY.get(:silkennet_coap_packets_received_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers lorenz_computation_duration_seconds histogram" do
      metric = described_class::REGISTRY.get(:silkennet_lorenz_computation_duration_seconds)
      expect(metric).to be_a(Prometheus::Client::Histogram)
    end
  end

  describe "S2.4 — new metrics increment behavior" do
    it "increments slashing_events_total by reason" do
      metric = described_class::SLASHING_EVENTS_TOTAL
      before_val = metric.get(labels: { reason: "tree_death" })

      metric.increment(labels: { reason: "tree_death" })

      expect(metric.get(labels: { reason: "tree_death" })).to eq(before_val + 1.0)
    end

    it "increments ota_chunks_sent_total by firmware_version" do
      metric = described_class::OTA_CHUNKS_SENT_TOTAL
      before_val = metric.get(labels: { firmware_version: "2.0.0" })

      metric.increment(labels: { firmware_version: "2.0.0" })

      expect(metric.get(labels: { firmware_version: "2.0.0" })).to eq(before_val + 1.0)
    end

    it "increments ews_alerts_total by alert_type" do
      metric = described_class::EWS_ALERTS_TOTAL
      before_val = metric.get(labels: { alert_type: "fire_detected" })

      metric.increment(labels: { alert_type: "fire_detected" })

      expect(metric.get(labels: { alert_type: "fire_detected" })).to eq(before_val + 1.0)
    end

    it "observes oracle_dispatch_duration_seconds histogram" do
      metric = described_class::ORACLE_DISPATCH_DURATION
      expect { metric.observe(1.5) }.not_to raise_error
    end

    it "increments coap_packets_received_total by status" do
      metric = described_class::COAP_PACKETS_RECEIVED_TOTAL
      before_val = metric.get(labels: { status: "success" })

      metric.increment(labels: { status: "success" })

      expect(metric.get(labels: { status: "success" })).to eq(before_val + 1.0)
    end

    it "increments coap_packets_received_total for error statuses" do
      metric = described_class::COAP_PACKETS_RECEIVED_TOTAL

      %w[decrypt_error unknown_device malformed].each do |status|
        before_val = metric.get(labels: { status: status })
        metric.increment(labels: { status: status })
        expect(metric.get(labels: { status: status })).to eq(before_val + 1.0)
      end
    end
  end

  describe "metric constants are accessible" do
    it "exposes SLASHING_EVENTS_TOTAL" do
      expect(described_class::SLASHING_EVENTS_TOTAL).to be_a(Prometheus::Client::Counter)
    end

    it "exposes OTA_CHUNKS_SENT_TOTAL" do
      expect(described_class::OTA_CHUNKS_SENT_TOTAL).to be_a(Prometheus::Client::Counter)
    end

    it "exposes EWS_ALERTS_TOTAL" do
      expect(described_class::EWS_ALERTS_TOTAL).to be_a(Prometheus::Client::Counter)
    end

    it "exposes ORACLE_DISPATCH_DURATION" do
      expect(described_class::ORACLE_DISPATCH_DURATION).to be_a(Prometheus::Client::Histogram)
    end

    it "exposes COAP_PACKETS_RECEIVED_TOTAL" do
      expect(described_class::COAP_PACKETS_RECEIVED_TOTAL).to be_a(Prometheus::Client::Counter)
    end

    it "exposes LORENZ_COMPUTATION_DURATION" do
      expect(described_class::LORENZ_COMPUTATION_DURATION).to be_a(Prometheus::Client::Histogram)
    end
  end

  # -----------------------------------------------------------------------
  # FW.22 / S2.3: Acoustic overflow and RPC circuit breaker metrics
  # -----------------------------------------------------------------------

  describe "FW.22 / S2.3 — acoustic overflow and circuit breaker metrics" do
    it "registers telemetry_acoustic_overflow_total counter" do
      metric = described_class::REGISTRY.get(:silkennet_telemetry_acoustic_overflow_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "increments telemetry_acoustic_overflow_total counter" do
      metric = described_class::TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL
      before_val = metric.get

      metric.increment

      expect(metric.get).to eq(before_val + 1.0)
    end

    it "registers rpc_circuit_breaker_open gauge with provider label" do
      metric = described_class::REGISTRY.get(:silkennet_rpc_circuit_breaker_open)
      expect(metric).to be_a(Prometheus::Client::Gauge)
    end

    it "registers circuit_breaker_rejections_total counter with service label" do
      # Was incremented (guarded) but never registered → silent no-op; now defined.
      metric = described_class::REGISTRY.get(:silkennet_circuit_breaker_rejections_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "sets rpc_circuit_breaker_open gauge for a provider" do
      metric = described_class::RPC_CIRCUIT_BREAKER_OPEN

      metric.set(1.0, labels: { provider: "alchemy.example.com:443" })
      expect(metric.get(labels: { provider: "alchemy.example.com:443" })).to eq(1.0)

      metric.set(0.0, labels: { provider: "alchemy.example.com:443" })
      expect(metric.get(labels: { provider: "alchemy.example.com:443" })).to eq(0.0)
    end
  end

  # -----------------------------------------------------------------------
  # 06_03 §2.9: Process / runtime health metrics (Ruby VM, GC, memory, Puma)
  # -----------------------------------------------------------------------

  describe "§2.9 — process/runtime metrics registration" do
    %i[
      silkennet_process_resident_memory_bytes
      silkennet_ruby_gc_count
      silkennet_ruby_gc_major_count
      silkennet_ruby_gc_heap_live_slots
      silkennet_ruby_threads
      silkennet_puma_running_threads
      silkennet_puma_max_threads
      silkennet_puma_pool_capacity
      silkennet_puma_backlog
    ].each do |name|
      it "registers #{name} gauge" do
        expect(described_class::REGISTRY.get(name)).to be_a(Prometheus::Client::Gauge)
      end
    end
  end

  describe "§2.9 — sample_process_runtime!" do
    it "populates GC + thread gauges with live values" do
      described_class.sample_process_runtime!
      expect(described_class::RUBY_GC_COUNT.get).to be > 0
      expect(described_class::RUBY_THREADS.get).to be > 0
      expect(described_class::RUBY_GC_HEAP_LIVE_SLOTS.get).to be > 0
    end

    it "is resilient — never raises even if a source is unavailable" do
      expect { described_class.sample_process_runtime! }.not_to raise_error
    end

    it "process_rss_bytes returns a non-negative Integer (0 off-Linux)" do
      rss = described_class.process_rss_bytes
      expect(rss).to be_a(Integer)
      expect(rss).to be >= 0
    end

    it "sample_puma_pool! never raises (no-op when Puma stats absent)" do
      expect { described_class.sample_puma_pool! }.not_to raise_error
    end
  end

  # -----------------------------------------------------------------------
  # ARCH.45: money-path idempotency observability (slash/payout SLO + DeadSet)
  # -----------------------------------------------------------------------
  describe "ARCH.45 — money-path idempotency observability" do
    %i[
      silkennet_slash_attempts_total
      silkennet_slash_success_total
      silkennet_solana_payout_attempts_total
      silkennet_solana_payout_success_total
    ].each do |name|
      it "registers #{name} counter" do
        expect(described_class::REGISTRY.get(name)).to be_a(Prometheus::Client::Counter)
      end
    end

    it "registers sidekiq_dead_set_size gauge" do
      expect(described_class::REGISTRY.get(:silkennet_sidekiq_dead_set_size)).to be_a(Prometheus::Client::Gauge)
    end

    it "increments slash attempts/success counters" do
      [ described_class::SLASH_ATTEMPTS_TOTAL, described_class::SLASH_SUCCESS_TOTAL ].each do |m|
        before_val = m.get
        m.increment
        expect(m.get).to eq(before_val + 1.0)
      end
    end

    it "increments Solana payout attempts/success counters" do
      [ described_class::SOLANA_PAYOUT_ATTEMPTS_TOTAL, described_class::SOLANA_PAYOUT_SUCCESS_TOTAL ].each do |m|
        before_val = m.get
        m.increment
        expect(m.get).to eq(before_val + 1.0)
      end
    end

    it "sets the dead_set_size gauge" do
      described_class::SIDEKIQ_DEAD_SET_SIZE.set(3)
      expect(described_class::SIDEKIQ_DEAD_SET_SIZE.get).to eq(3.0)
    end
  end
end
