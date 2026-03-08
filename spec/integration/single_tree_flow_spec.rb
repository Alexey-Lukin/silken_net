# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Single tree end-to-end flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
  end

  describe "tree with cluster" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "creates a wallet on tree creation" do
      expect(tree.wallet).to be_present
      expect(tree.wallet.balance).to eq(0)
      expect(tree.wallet.organization).to eq(organization)
    end

    it "creates a device calibration on tree creation" do
      expect(tree.device_calibration).to be_present
    end

    it "tracks voltage and last_seen_at" do
      expect(tree.last_seen_at).to be_nil
      tree.mark_seen!(3500)
      expect(tree.last_seen_at).to be_present
      expect(tree.latest_voltage_mv).to eq(3500)
    end

    it "calculates charge percentage" do
      tree.update_columns(latest_voltage_mv: 4150)
      expect(tree.charge_percentage).to be_between(0, 100)
    end

    it "detects low power" do
      tree.update_columns(latest_voltage_mv: 3000)
      expect(tree.low_power?).to be true
    end
  end

  describe "clusterless tree (standalone installation)" do
    let!(:tree) { create(:tree, cluster: nil, tree_family: tree_family) }

    it "creates a wallet without organization" do
      expect(tree.wallet).to be_present
      expect(tree.wallet.organization).to be_nil
    end

    it "still tracks voltage" do
      tree.mark_seen!(4000)
      expect(tree.latest_voltage_mv).to eq(4000)
    end
  end
end
