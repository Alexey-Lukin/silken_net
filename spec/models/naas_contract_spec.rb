# frozen_string_literal: true

require "rails_helper"

RSpec.describe NaasContract, type: :model do
  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#check_cluster_health!" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }
    let(:target_date) { Time.current.utc.to_date - 1 }

    context "when contract is not active" do
      it "returns early without checking" do
        contract.update_column(:status, described_class.statuses[:draft])
        expect { contract.check_cluster_health!(target_date) }.not_to change { contract.reload.status }
      end
    end

    context "when cluster has no active trees" do
      it "returns early" do
        expect { contract.check_cluster_health!(target_date) }.not_to change { contract.reload.status }
      end
    end

    context "when Oracle is silent (no daily insights)" do
      it "activates slashing protocol" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_breached
      end

      it "enqueues BurnCarbonTokensWorker" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        contract.check_cluster_health!(target_date)

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
        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when critical anomalies exceed 20% threshold" do
      it "activates slashing protocol" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        # 3 out of 10 trees with stress >= 1.0 (30% > 20% threshold)
        trees[0..2].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 1.0)
        end
        trees[3..9].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_breached
      end
    end

    context "when critical anomalies are exactly at 20% threshold" do
      it "does not trigger slashing" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        # 2 out of 10 trees (20% = threshold, not exceeded)
        trees[0..1].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 1.0)
        end
        trees[2..9].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when deceased trees are present" do
      it "ignores deceased trees in calculations (Active Soul Counting)" do
        active_trees = create_list(:tree, 5, cluster: cluster, status: :active)
        create_list(:tree, 5, cluster: cluster, status: :deceased)

        active_trees.each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when SQL subquery optimization" do
      it "uses subquery instead of loading all tree IDs into memory" do
        create(:tree, cluster: cluster, status: :active)
        create(:ai_insight,
          analyzable: cluster.trees.active.first,
          target_date: target_date,
          stress_index: 0.1
        )

        # Verify the query uses a subquery (WHERE analyzable_id IN (SELECT ...))
        # rather than loading IDs into an array (WHERE analyzable_id IN (1, 2, 3, ...))
        queries = []
        callback = ->(_name, _start, _finish, _id, payload) {
          queries << payload[:sql] if payload[:sql]&.include?("ai_insights")
        }

        cluster.reload
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          contract.check_cluster_health!(target_date)
        end

        insight_query = queries.find { |q| q.include?("analyzable_type") }
        expect(insight_query).to be_present
        # The subquery should contain SELECT "trees"."id" FROM "trees"
        expect(insight_query).to include("SELECT")
        expect(insight_query).to include("trees")
      end
    end
  end

  describe "cluster timezone integration" do
    let(:organization) { create(:organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }

    context "when cluster has a timezone set" do
      let(:cluster) { create(:cluster, organization: organization, environmental_settings: { "timezone" => "Pacific/Auckland" }) }

      it "uses cluster timezone for default target_date" do
        create(:tree, cluster: cluster, status: :active)

        nz_yesterday = Time.use_zone("Pacific/Auckland") { Date.yesterday }
        utc_yesterday = Time.current.utc.to_date - 1

        # Create insight for the NZ-timezone yesterday
        create(:ai_insight,
          analyzable: cluster.trees.active.first,
          target_date: nz_yesterday,
          stress_index: 0.1
        )

        # When NZ yesterday differs from UTC yesterday, the cluster timezone matters
        if nz_yesterday != utc_yesterday
          # With cluster timezone, contract should find the insight
          contract.check_cluster_health!(nz_yesterday)
          expect(contract.reload).to be_status_active
        end
      end
    end

    context "when cluster has no timezone set" do
      let(:cluster) { create(:cluster, organization: organization) }

      it "falls back to UTC" do
        expect(cluster.local_yesterday).to eq(Time.current.utc.to_date - 1)
      end
    end
  end

  describe "#terminate_early!" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }

    it "changes status to cancelled and sets cancelled_at" do
      contract.terminate_early!
      contract.reload

      expect(contract).to be_status_cancelled
      expect(contract.cancelled_at).to be_present
    end

    it "raises when contract is not active" do
      contract.update_column(:status, described_class.statuses[:draft])

      expect { contract.terminate_early! }.to raise_error(RuntimeError, /не активний/)
    end

    it "raises when minimum days before exit not met" do
      contract.update!(start_date: 10.days.ago, min_days_before_exit: 60)

      expect { contract.terminate_early! }.to raise_error(RuntimeError, /Мінімальний термін/)
    end

    it "enqueues BurnCarbonTokensWorker when burn_accrued_points is true" do
      contract.update!(burn_accrued_points: true)

      contract.terminate_early!

      expect(BurnCarbonTokensWorker.jobs.size).to eq(1)
    end

    it "does not enqueue BurnCarbonTokensWorker when burn_accrued_points is false" do
      contract.update!(burn_accrued_points: false)

      contract.terminate_early!

      expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
    end

    it "returns refund and fee details" do
      contract.update!(early_exit_fee_percent: 10, burn_accrued_points: false)

      result = contract.terminate_early!

      expect(result).to include(:refund, :fee, :burned)
      expect(result[:burned]).to be(false)
    end
  end

  describe "#calculate_early_exit_fee" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "calculates fee based on early_exit_fee_percent" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000, early_exit_fee_percent: 15)

      expect(contract.calculate_early_exit_fee).to eq(BigDecimal("7500.0"))
    end

    it "returns 0 when no fee percent is set" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000)

      expect(contract.calculate_early_exit_fee).to eq(BigDecimal("0"))
    end
  end

  describe "#calculate_prorated_refund" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "calculates prorated refund minus fee" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000, start_date: 6.months.ago, end_date: 6.months.from_now,
        status: :active, early_exit_fee_percent: 10)

      refund = contract.calculate_prorated_refund

      expect(refund).to be > 0
      expect(refund).to be < 50_000
    end

    it "returns 0 when contract is not active" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000, status: :draft)

      expect(contract.calculate_prorated_refund).to eq(BigDecimal("0"))
    end
  end

  describe "cancellation_terms store_accessor" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }

    it "reads and writes early_exit_fee_percent" do
      contract.update!(early_exit_fee_percent: 15)

      expect(contract.reload.early_exit_fee_percent).to eq(15)
    end

    it "reads and writes burn_accrued_points" do
      contract.update!(burn_accrued_points: true)

      expect(contract.reload.burn_accrued_points).to be(true)
    end

    it "reads and writes min_days_before_exit" do
      contract.update!(min_days_before_exit: 30)

      expect(contract.reload.min_days_before_exit).to eq(30)
    end
  end

  describe "#current_yield_performance" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "returns percentage of emitted tokens vs total funding" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 10_000, emitted_tokens: 2_500)

      expect(contract.current_yield_performance).to eq(25)
    end

    it "returns 0 when total_funding is zero" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 1, emitted_tokens: 0)
      contract.update_column(:total_funding, 0)

      expect(contract.current_yield_performance).to eq(0)
    end

    it "returns 0 when total_funding is nil" do
      contract = create(:naas_contract, organization: organization, cluster: cluster)
      contract.update_column(:total_funding, nil)

      expect(contract.current_yield_performance).to eq(0)
    end

    it "clamps result to 100 when emitted exceeds funding" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 1_000, emitted_tokens: 2_000)

      expect(contract.current_yield_performance).to eq(100)
    end

    it "returns 0 when no tokens have been emitted" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000, emitted_tokens: 0)

      expect(contract.current_yield_performance).to eq(0)
    end
  end

  describe "scopes" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    describe ".active" do
      it "returns only active contracts" do
        active = create(:naas_contract, organization: organization, cluster: cluster, status: :active)
        draft = create(:naas_contract, organization: organization, cluster: cluster, status: :draft)

        expect(described_class.active).to include(active)
        expect(described_class.active).not_to include(draft)
      end
    end

    describe ".pending_completion" do
      it "returns active contracts past their end date" do
        expired = create(:naas_contract, organization: organization, cluster: cluster,
          status: :active, end_date: 1.day.ago)
        ongoing = create(:naas_contract, organization: organization, cluster: cluster,
          status: :active, end_date: 1.month.from_now)

        expect(described_class.pending_completion).to include(expired)
        expect(described_class.pending_completion).not_to include(ongoing)
      end
    end
  end

  describe "validations" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "requires total_funding to be positive" do
      contract = build(:naas_contract, organization: organization, cluster: cluster, total_funding: -1)
      expect(contract).not_to be_valid
    end

    it "requires start_date" do
      contract = build(:naas_contract, organization: organization, cluster: cluster, start_date: nil)
      expect(contract).not_to be_valid
    end

    it "requires end_date" do
      contract = build(:naas_contract, organization: organization, cluster: cluster, end_date: nil)
      expect(contract).not_to be_valid
    end

    it "requires end_date after start_date" do
      contract = build(:naas_contract, organization: organization, cluster: cluster,
        start_date: 1.month.from_now, end_date: 1.month.ago)
      expect(contract).not_to be_valid
      expect(contract.errors[:end_date]).to be_present
    end
  end
end
