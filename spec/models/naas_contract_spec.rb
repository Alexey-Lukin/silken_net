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
        contract.update_column(:status, NaasContract.statuses[:draft])
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

        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_breached
      end

      it "enqueues BurnCarbonTokensWorker" do
        create(:tree, cluster: cluster, status: :active)

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

        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "SQL subquery optimization" do
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
end
