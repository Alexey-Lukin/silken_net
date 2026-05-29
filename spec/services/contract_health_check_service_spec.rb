# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractHealthCheckService do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }
  let(:target_date) { Time.current.utc.to_date - 1 }

  describe ".call" do
    context "when contract is not active" do
      it "returns early without checking" do
        contract.update_column(:status, NaasContract.statuses[:draft])
        expect { described_class.call(contract, target_date) }.not_to change { contract.reload.status }
      end
    end

    context "when cluster has no active trees" do
      it "returns early" do
        expect { described_class.call(contract, target_date) }.not_to change { contract.reload.status }
      end
    end

    # [SLASH-1] Cluster-wide blackout = gateway-fault / force-majeure signature,
    # NOT negligence → must NOT auto-burn (00_01 §6.5). Route to Field Audit.
    context "when Oracle is silent (no daily insights) — cluster-wide blackout" do
      it "does NOT slash (no breach, no burn)" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        described_class.call(contract, target_date)

        expect(contract.reload).to be_status_active
        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      end

      it "raises a system_fault Field-Audit alert for the cluster" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        expect { described_class.call(contract, target_date) }
          .to change { EwsAlert.where(cluster: cluster, alert_type: :system_fault).count }.by(1)
      end
    end

    context "when health is within threshold" do
      it "does not trigger slashing" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        trees.each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.2)
        end

        cluster.reload
        described_class.call(contract, target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when critical anomalies exceed 20% threshold" do
      it "activates slashing protocol" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        trees[0..2].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 1.0)
        end
        trees[3..9].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        described_class.call(contract, target_date)

        expect(contract.reload).to be_status_breached
      end

      it "activates slashing protocol when stress_index is at RF confidence boundary (0.83)" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        trees[0..2].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.83)
        end
        trees[3..9].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        described_class.call(contract, target_date)

        expect(contract.reload).to be_status_breached
      end

      it "does not trigger slashing when stress_index is below RF boundary (0.82)" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        trees[0..2].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.82)
        end
        trees[3..9].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        described_class.call(contract, target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when activate_slashing_protocol! encounters a database error" do
      # Trigger the REAL slash path (>20% critical insights — data present), since
      # absence-of-data now routes to Field Audit instead of slashing [SLASH-1].
      before do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 1.0) }
        trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }
        cluster.reload
        allow(contract).to receive(:update!).and_raise(StandardError, "DB lock timeout")
      end

      it "does not enqueue BurnCarbonTokensWorker when update! fails" do
        described_class.call(contract, target_date)

        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      end

      it "logs the slashing activation failure" do
        expect(Rails.logger).to receive(:error).with(/Провал активації Slashing/)

        described_class.call(contract, target_date)
      end
    end
  end
end
