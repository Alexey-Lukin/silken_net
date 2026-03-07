# frozen_string_literal: true

require "rails_helper"

RSpec.describe BurnCarbonTokensWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }
  let!(:admin_user) { create(:user, :admin, organization: organization) }

  before do
    allow(BlockchainBurningService).to receive(:call)
    allow(ActionCable.server).to receive(:broadcast)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "calls BlockchainBurningService with correct arguments" do
      described_class.new.perform(organization.id, naas_contract.id, tree.id)

      expect(BlockchainBurningService).to have_received(:call).with(
        organization.id,
        naas_contract.id,
        source_tree: tree
      )
    end

    it "creates a MaintenanceRecord with decommissioning action" do
      expect {
        described_class.new.perform(organization.id, naas_contract.id, tree.id)
      }.to change(MaintenanceRecord, :count).by(1)

      record = MaintenanceRecord.last
      expect(record.action_type).to eq("decommissioning")
      expect(record.notes).to include("SLASHING EXECUTED")
      expect(record.notes).to include(tree.did)
    end

    it "creates MaintenanceRecord without tree reference when tree_id is nil" do
      expect {
        described_class.new.perform(organization.id, naas_contract.id)
      }.to change(MaintenanceRecord, :count).by(1)

      record = MaintenanceRecord.last
      expect(record.notes).to include("Загальна деградація кластера")
    end

    it "broadcasts slashing event via ActionCable and Turbo" do
      described_class.new.perform(organization.id, naas_contract.id, tree.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("org_#{organization.id}_alerts", hash_including(event: "CONTRACT_SLASHED"))
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
    end

    it "returns early when contract is not found" do
      expect(Rails.logger).to receive(:error).with(/не знайдено/)

      described_class.new.perform(organization.id, -1)

      expect(BlockchainBurningService).not_to have_received(:call)
    end

    it "skips already breached contracts (idempotency)" do
      naas_contract.update_column(:status, :breached)

      described_class.new.perform(organization.id, naas_contract.id)

      expect(BlockchainBurningService).not_to have_received(:call)
    end

    it "re-raises errors for Sidekiq retry" do
      allow(BlockchainBurningService).to receive(:call).and_raise(StandardError, "RPC timeout")

      expect {
        described_class.new.perform(organization.id, naas_contract.id)
      }.to raise_error(StandardError, "RPC timeout")
    end
  end
end
