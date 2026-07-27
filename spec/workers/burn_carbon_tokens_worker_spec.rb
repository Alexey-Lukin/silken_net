# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BurnCarbonTokensWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }
  let!(:admin_user) { create(:user, :admin, organization: organization) }

  before do
    # [SLASH-1] Сервіс тепер повертає outcome (:slashed/:frozen/nil); за замовч. :slashed,
    # щоб тести «надгробка»/broadcast/метрики йшли slash-шляхом. Freeze-шлях — окремо нижче.
    allow(BlockchainBurningService).to receive(:call).and_return(:slashed)
    allow(ActionCable.server).to receive(:broadcast)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "calls BlockchainBurningService with correct arguments" do
      described_class.new.perform(organization.id, naas_contract.id, tree.id)

      expect(BlockchainBurningService).to have_received(:call).with(
        organization.id,
        naas_contract.id,
        source_tree: tree,
        contractual: false,
        target_date: nil
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

    it "broadcasts the slashing event to the contract Turbo stream" do
      described_class.new.perform(organization.id, naas_contract.id, tree.id)

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

    # [SLASH-1 §3.2] Freeze: cause-gate found no Category-A evidence → service returns
    # :frozen (Field-Audit alert raised THERE). The worker must NOT write the
    # decommissioning tombstone nor broadcast CONTRACT_SLASHED.
    it "does NOT write a tombstone or broadcast when the service freezes (:frozen)" do
      allow(BlockchainBurningService).to receive(:call).and_return(:frozen)

      expect {
        described_class.new.perform(organization.id, naas_contract.id, tree.id)
      }.not_to change(MaintenanceRecord, :count)

      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "parses a present target_date string and forwards the Date (ARCH.46 backfill)" do
      described_class.new.perform(organization.id, naas_contract.id, tree.id, false, "2026-07-01")

      expect(BlockchainBurningService).to have_received(:call).with(
        organization.id,
        naas_contract.id,
        source_tree: tree,
        contractual: false,
        target_date: Date.new(2026, 7, 1)
      )
    end

    it "passes the contractual flag through to the service (early-exit forfeiture)" do
      described_class.new.perform(organization.id, naas_contract.id, nil, true)

      expect(BlockchainBurningService).to have_received(:call).with(
        organization.id,
        naas_contract.id,
        source_tree: nil,
        contractual: true,
        target_date: nil
      )
    end
  end

  # -----------------------------------------------------------------------
  # S2.4: Prometheus metric SLASHING_EVENTS_TOTAL
  # -----------------------------------------------------------------------
  describe "Prometheus metrics (S2.4)" do
    it "increments SLASHING_EVENTS_TOTAL with reason tree_death when tree_id is provided" do
      metric = SilkenNet::Metrics::SLASHING_EVENTS_TOTAL
      before_val = metric.get(labels: { reason: "tree_death" })

      described_class.new.perform(organization.id, naas_contract.id, tree.id)

      expect(metric.get(labels: { reason: "tree_death" })).to eq(before_val + 1.0)
    end

    it "increments SLASHING_EVENTS_TOTAL with reason cluster_degradation when tree_id is nil" do
      metric = SilkenNet::Metrics::SLASHING_EVENTS_TOTAL
      before_val = metric.get(labels: { reason: "cluster_degradation" })

      described_class.new.perform(organization.id, naas_contract.id)

      expect(metric.get(labels: { reason: "cluster_degradation" })).to eq(before_val + 1.0)
    end

    it "does not increment metric when contract is already breached" do
      naas_contract.update_column(:status, :breached)

      metric = SilkenNet::Metrics::SLASHING_EVENTS_TOTAL
      before_tree = metric.get(labels: { reason: "tree_death" })
      before_cluster = metric.get(labels: { reason: "cluster_degradation" })

      described_class.new.perform(organization.id, naas_contract.id, tree.id)

      expect(metric.get(labels: { reason: "tree_death" })).to eq(before_tree)
      expect(metric.get(labels: { reason: "cluster_degradation" })).to eq(before_cluster)
    end
  end
end
