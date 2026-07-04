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
    # NOT negligence → must NOT auto-burn (05_05 §6). Route to Field Audit.
    context "when Oracle is silent (no daily insights) — cluster-wide blackout" do
      it "does NOT slash (no breach, no burn)" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        described_class.call(contract, target_date)

        expect(contract.reload).to be_status_active
        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      end

      it "raises a :field_audit escalation for the cluster (NOT :system_fault — gap-D)" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        expect { described_class.call(contract, target_date) }
          .to change { EwsAlert.where(cluster: cluster, alert_type: :field_audit).count }.by(1)
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

    # [SLASH-1] >20% критичних → :degraded + enqueue burn-воркера, БЕЗ pre-breach.
    # Breach ставить лише BlockchainBurningService на реальному positive-A слешингу;
    # cause-gate чокпоінта вирішує slash-vs-freeze. Це й полагодило латентний баг
    # (раніше pre-breach коротко-замикав воркер → daily ніколи не палив).
    context "when critical anomalies exceed 20% threshold" do
      it "routes to the chokepoint (:degraded) + enqueues the burn worker WITHOUT pre-breaching" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 1.0) }
        trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }
        cluster.reload

        expect {
          expect(described_class.call(contract, target_date)).to eq(:degraded)
        }.to change { BurnCarbonTokensWorker.jobs.size }.by(1)

        # [ARCH.46] burn-воркер МУСИТЬ отримати прокинутий target_date (5-й арг) — інакше burn
        # перевираховує local_yesterday у момент виконання → date-mismatch over-burn (regression guard).
        expect(BurnCarbonTokensWorker.jobs.last["args"]).to eq(
          [ contract.organization_id, contract.id, nil, false, target_date.to_s ]
        )

        expect(contract.reload).to be_status_active # no pre-breach — chokepoint owns the verdict
      end

      it "treats the RF confidence boundary (0.83) as critical (:degraded)" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.83) }
        trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }
        cluster.reload

        expect(described_class.call(contract, target_date)).to eq(:degraded)
      end

      it "does not flag when stress_index is below the RF boundary (0.82) → :healthy" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.82) }
        trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }
        cluster.reload

        expect(described_class.call(contract, target_date)).to eq(:healthy)
        expect(contract.reload).to be_status_active
        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      end
    end

    # [GOV.1] Обидва пороги DAO-live через SystemParameter (← ProtocolParameters.sol).
    context "when governance overrides the thresholds (GOV.1)" do
      it "respects a raised slash_threshold: 30% critical < 50% → :healthy" do
        create(:system_parameter, key: "slash_threshold", value: "0.5",
                                  value_type: "float", category: "alerts")
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 1.0) }
        trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }
        cluster.reload

        expect(described_class.call(contract, target_date)).to eq(:healthy)
        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      end

      it "respects a raised stress_threshold: stress 0.85 no longer counts as critical" do
        create(:system_parameter, key: "stress_threshold", value: "0.9",
                                  value_type: "float", category: "alerts")
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.85) }
        trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }
        cluster.reload

        expect(described_class.call(contract, target_date)).to eq(:healthy)
        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      end
    end
  end
end
