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

    context "when Oracle is silent (no daily insights)" do
      it "activates slashing protocol" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        described_class.call(contract, target_date)

        expect(contract.reload).to be_status_breached
      end

      it "enqueues BurnCarbonTokensWorker" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        described_class.call(contract, target_date)

        expect(BurnCarbonTokensWorker.jobs.size).to eq(1)
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
    end
  end
end
