# frozen_string_literal: true

require "rails_helper"

RSpec.describe SolanaMicroRewardWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }

  before do
    allow(Solana::MintingService).to receive_message_chain(:new, :mint_micro_reward!)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    let!(:telemetry_log) do
      create(:telemetry_log, :verified_telemetry, tree: tree)
    end

    it "finds TelemetryLog and calls Solana::MintingService" do
      mock_service = instance_double(Solana::MintingService)
      allow(Solana::MintingService).to receive(:new).with(telemetry_log).and_return(mock_service)
      allow(mock_service).to receive(:mint_micro_reward!)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(Solana::MintingService).to have_received(:new).with(telemetry_log)
      expect(mock_service).to have_received(:mint_micro_reward!)
    end

    it "does nothing when telemetry_log not found" do
      described_class.new.perform(-1, Time.current.iso8601(6))

      expect(Solana::MintingService).not_to have_received(:new)
    end

    it "re-raises errors for Sidekiq retry" do
      mock_service = instance_double(Solana::MintingService)
      allow(Solana::MintingService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:mint_micro_reward!).and_raise(StandardError, "Solana RPC Error")

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(StandardError, "Solana RPC Error")
    end

    it "uses partition pruning with created_at_iso" do
      # Verify it can find with correct created_at
      mock_service = instance_double(Solana::MintingService)
      allow(Solana::MintingService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:mint_micro_reward!)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(mock_service).to have_received(:mint_micro_reward!)
    end

    it "works without created_at_iso parameter" do
      mock_service = instance_double(Solana::MintingService)
      allow(Solana::MintingService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:mint_micro_reward!)

      described_class.new.perform(telemetry_log.id_value)

      expect(mock_service).to have_received(:mint_micro_reward!)
    end
  end

  describe "sidekiq options" do
    it "uses web3 queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("web3")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end
end
