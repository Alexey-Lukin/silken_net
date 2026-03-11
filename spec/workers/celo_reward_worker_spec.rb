# frozen_string_literal: true

require "rails_helper"

RSpec.describe CeloRewardWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }

  before do
    mock_service = instance_double(Celo::CommunityRewardService, reward_community!: nil)
    allow(Celo::CommunityRewardService).to receive(:new).and_return(mock_service)
  end

  describe "#perform" do
    it "finds Cluster and calls Celo::CommunityRewardService" do
      target_date = "2026-03-10"
      mock_service = instance_double(Celo::CommunityRewardService)
      allow(Celo::CommunityRewardService).to receive(:new).with(cluster, Date.parse(target_date)).and_return(mock_service)
      allow(mock_service).to receive(:reward_community!)

      described_class.new.perform(cluster.id, target_date)

      expect(Celo::CommunityRewardService).to have_received(:new).with(cluster, Date.parse(target_date))
      expect(mock_service).to have_received(:reward_community!)
    end

    it "does nothing when cluster not found" do
      described_class.new.perform(-1, "2026-03-10")

      expect(Celo::CommunityRewardService).not_to have_received(:new)
    end

    it "re-raises errors for Sidekiq retry" do
      mock_service = instance_double(Celo::CommunityRewardService)
      allow(Celo::CommunityRewardService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:reward_community!).and_raise(StandardError, "Celo RPC Error")

      expect {
        described_class.new.perform(cluster.id, "2026-03-10")
      }.to raise_error(StandardError, "Celo RPC Error")
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
