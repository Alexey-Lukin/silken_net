# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeChronicleService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }

  describe ".call" do
    context "with no events" do
      it "returns empty entries and valid pagy" do
        result = described_class.call(tree: tree)

        expect(result[:entries]).to be_empty
        expect(result[:pagy]).to respond_to(:page)
        expect(result[:pagy].count).to eq(0)
      end
    end

    context "with AiInsight events" do
      it "formats homeostasis events when stress_index < 0.2" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1, reasoning: { "avg_z" => "24.3" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:homeostasis)
        expect(entry.title).to eq("Deep Homeostasis")
        expect(entry.severity).to eq(:stable)
        expect(entry.source_type).to eq("AiInsight")
      end

      it "formats stress events when stress_index >= 0.3" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.5,
               reasoning: { "max_temp" => "42" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:stress)
        expect(entry.severity).to eq(:warning)
      end

      it "formats critical stress events when stress_index >= 0.8" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.85)

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.severity).to eq(:critical)
      end

      it "formats fraud events" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, fraud_detected: true,
               reasoning: { "deviation_from_baseline" => "35" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:fraud)
        expect(entry.severity).to eq(:critical)
        expect(entry.icon).to eq("\u26A0")
      end
    end

    context "with EwsAlert events" do
      it "formats alert events" do
        create(:ews_alert, tree: tree, cluster: cluster,
               alert_type: :fire_detected, severity: :critical,
               message: "Temperature threshold exceeded")

        result = described_class.call(tree: tree)
        alert_entry = result[:entries].find { |e| e.event_type == :alert }

        expect(alert_entry).to be_present
        expect(alert_entry.severity).to eq(:critical)
        expect(alert_entry.icon).to include("\u{1F525}")
      end

      it "includes recovery events for resolved alerts" do
        alert = create(:ews_alert, tree: tree, cluster: cluster,
                       alert_type: :severe_drought, severity: :medium,
                       message: "Drought detected")
        alert.update_columns(status: "resolved", resolved_at: Time.current,
                             resolution_notes: "Rain restored moisture")

        result = described_class.call(tree: tree)
        recovery_entry = result[:entries].find { |e| e.event_type == :recovery }

        expect(recovery_entry).to be_present
        expect(recovery_entry.title).to eq("Incident Resolved")
        expect(recovery_entry.severity).to eq(:stable)
      end
    end

    context "with MaintenanceRecord events" do
      it "formats maintenance events" do
        user = create(:user, organization: organization)
        create(:maintenance_record, maintainable: tree, user: user,
               action_type: :inspection, performed_at: 1.day.ago)

        result = described_class.call(tree: tree)
        entry = result[:entries].find { |e| e.event_type == :maintenance }

        expect(entry).to be_present
        expect(entry.severity).to eq(:info)
        expect(entry.icon).to eq("\u2699")
      end
    end

    context "with BlockchainTransaction events" do
      it "formats confirmed minting events" do
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "a" * 40)
        create(:blockchain_transaction, wallet: wallet,
               status: :confirmed, token_type: :carbon_coin,
               confirmed_at: 1.day.ago, tx_hash: "0x" + SecureRandom.hex(32))

        result = described_class.call(tree: tree)
        entry = result[:entries].find { |e| e.event_type == :minting }

        expect(entry).to be_present
        expect(entry.icon).to eq("\u25C6")
      end
    end

    context "with pagination" do
      before do
        25.times do |i|
          create(:ai_insight, :daily_health_summary, analyzable: tree,
                 target_date: i.days.ago, stress_index: 0.1,
                 model_source: "test_#{i}")
        end
      end

      it "returns paginated results (default 20 per page)" do
        result = described_class.call(tree: tree, page: 1)

        expect(result[:entries].size).to eq(20)
        expect(result[:pagy].count).to eq(25)
        expect(result[:pagy].last).to eq(2)
      end

      it "returns second page" do
        result = described_class.call(tree: tree, page: 2)

        expect(result[:entries].size).to eq(5)
      end
    end

    context "with chronological ordering" do
      it "sorts entries by date descending (newest first)" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 3.days.ago, stress_index: 0.1, model_source: "old")
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1, model_source: "new")

        result = described_class.call(tree: tree)
        dates = result[:entries].map(&:date)

        expect(dates).to eq(dates.sort.reverse)
      end
    end
  end
end
