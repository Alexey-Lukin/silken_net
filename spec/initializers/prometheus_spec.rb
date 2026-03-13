# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Prometheus Metrics Initializer" do
  describe "SilkenNet::Metrics" do
    it "defines the metrics registry" do
      expect(SilkenNet::Metrics::REGISTRY).to be_a(Prometheus::Client::Registry)
    end

    it "registers scc_minted_total counter" do
      metric = SilkenNet::Metrics::REGISTRY.get(:silkennet_scc_minted_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers scc_slashed_total counter" do
      metric = SilkenNet::Metrics::REGISTRY.get(:silkennet_scc_slashed_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers rpc_errors_total counter with network and error_type labels" do
      metric = SilkenNet::Metrics::REGISTRY.get(:silkennet_rpc_errors_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers telemetry_processed_total counter" do
      metric = SilkenNet::Metrics::REGISTRY.get(:silkennet_telemetry_processed_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers telemetry_fraud_detected_total counter" do
      metric = SilkenNet::Metrics::REGISTRY.get(:silkennet_telemetry_fraud_detected_total)
      expect(metric).to be_a(Prometheus::Client::Counter)
    end

    it "registers web3_queue_size gauge" do
      metric = SilkenNet::Metrics::REGISTRY.get(:silkennet_web3_queue_size)
      expect(metric).to be_a(Prometheus::Client::Gauge)
    end

    it "registers web3_queue_latency_seconds gauge" do
      metric = SilkenNet::Metrics::REGISTRY.get(:silkennet_web3_queue_latency_seconds)
      expect(metric).to be_a(Prometheus::Client::Gauge)
    end

    it "increments scc_minted_total counter" do
      metric = SilkenNet::Metrics::SCC_MINTED_TOTAL
      before_val = metric.get(labels: { token_type: "carbon_coin" })

      metric.increment(labels: { token_type: "carbon_coin" })

      after_val = metric.get(labels: { token_type: "carbon_coin" })
      expect(after_val).to eq(before_val + 1.0)
    end

    it "increments rpc_errors_total counter with labels" do
      metric = SilkenNet::Metrics::RPC_ERRORS_TOTAL
      before_val = metric.get(labels: { network: "Polygon", error_type: "timeout" })

      metric.increment(labels: { network: "Polygon", error_type: "timeout" })

      after_val = metric.get(labels: { network: "Polygon", error_type: "timeout" })
      expect(after_val).to eq(before_val + 1.0)
    end
  end
end
