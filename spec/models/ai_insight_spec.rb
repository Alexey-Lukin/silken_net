# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiInsight, type: :model do
  # 🔴 [ARCH.84] Носій навчального набору: тренер — rake-таска без спеки, тож
  # фільтр, написаний там рядком, не мав би свідка взагалі. Пара обовʼязкова —
  # без другої половини пін проходив би й на скоупі, що не бере НІЧОГО.
  describe ".stress_training_set" do
    let(:cluster) { create(:cluster) }
    let(:tree) { create(:tree, cluster: cluster) }

    it "excludes the cluster AGGREGATE — it carries no feature vector, only an average" do
      tree_row = create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
                                     target_date: Date.yesterday, stress_index: 0.2,
                                     average_temperature: 21.0, reasoning: { "avg_z" => 27.0 })
      cluster_row = create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                                        target_date: Date.yesterday, stress_index: 0.2)

      # Ліхтар на передумову: кластерний рядок СТВОРЕНО — інакше «не входить»
      # доводило б лише те, що його не існує.
      expect(cluster_row.average_temperature).to be_nil
      expect(described_class.stress_training_set).to include(tree_row)
      expect(described_class.stress_training_set).not_to include(cluster_row)
    end

    it "excludes a tree row whose stress was never measured" do
      unmeasured = create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
                                       target_date: Date.yesterday - 1, stress_index: nil)

      expect(described_class.stress_training_set).not_to include(unmeasured)
    end
  end

  describe ".fraudulent" do
    it "returns only insights with fraud_detected true" do
      tree = create(:tree)
      fraud = create(:ai_insight, analyzable: tree, fraud_detected: true, target_date: Date.yesterday)
      create(:ai_insight, analyzable: tree, fraud_detected: false, target_date: 2.days.ago,
             insight_type: :drought_probability)

      expect(described_class.fraudulent).to eq([ fraud ])
    end
  end

  describe "#confidence_level" do
    it "returns :n_a when probability_score is nil" do
      insight = described_class.new(probability_score: nil)
      expect(insight.confidence_level).to eq(:n_a)
    end

    it "returns :low for probability_score below 40" do
      insight = described_class.new(probability_score: 20.0)
      expect(insight.confidence_level).to eq(:low)
    end

    it "returns :medium for probability_score between 40 and 75" do
      insight = described_class.new(probability_score: 50.0)
      expect(insight.confidence_level).to eq(:medium)
    end

    it "returns :high for probability_score >= 75" do
      insight = described_class.new(probability_score: 80.0)
      expect(insight.confidence_level).to eq(:high)
    end
  end

  describe ".slash_stress_threshold" do
    it "defaults to SLASH_STRESS_THRESHOLD" do
      expect(described_class.slash_stress_threshold).to eq(0.83)
    end

    it "reads the governance value from SystemParameter (GOV.1)" do
      create(:system_parameter, key: "stress_threshold", value: "0.9",
                                value_type: "float", category: "alerts")
      expect(described_class.slash_stress_threshold).to eq(0.9)
    end
  end

  # [ARCH.100] Дім доби звіту. Пін тримає ДВІ властивості, і друга — та, заради якої
  # дім заведено: доба не залежить від пояса, у якому опинився процес чи орендар.
  describe ".reporting_date" do
    it "is the UTC day before the given moment" do
      expect(described_class.reporting_date(Time.utc(2026, 8, 13, 2, 0, 0))).to eq(Date.new(2026, 8, 12))
    end

    it "does not move with the ambient Rails timezone" do
      moment = Time.utc(2026, 8, 13, 2, 0, 0)
      answers = [ "UTC", "America/Manaus", "Pacific/Auckland" ].map do |zone|
        Time.use_zone(zone) { described_class.reporting_date(moment) }
      end

      expect(answers.uniq).to eq([ Date.new(2026, 8, 12) ])
    end
  end

  # =========================================================================
  # EVIDENCE PERSISTENCE (source_log_ids)
  # =========================================================================
  describe "evidence persistence" do
    let(:tree) { create(:tree) }
    let(:telemetry_logs) { create_list(:telemetry_log, 3, tree: tree) }
    # Партиціоновані таблиці мають composite PK [id, created_at].
    # source_log_ids зберігає лише integer частину.
    let(:log_integer_ids) { telemetry_logs.map { |l| Array(l.id).first } }
    let(:insight) do
      create(:ai_insight,
        analyzable: tree,
        target_date: Date.yesterday,
        source_log_ids: log_integer_ids
      )
    end

    describe "#source_logs" do
      it "returns associated telemetry logs" do
        found_ids = insight.source_logs.map { |l| Array(l.id).first }
        expect(found_ids).to match_array(log_integer_ids)
      end

      it "returns none when source_log_ids is empty" do
        empty_insight = create(:ai_insight, analyzable: tree, target_date: 2.days.ago,
                               insight_type: :drought_probability, source_log_ids: [])
        expect(empty_insight.source_logs).to be_empty
      end
    end

    describe "#attach_evidence!" do
      it "appends new log IDs without duplicates" do
        new_log = create(:telemetry_log, tree: tree)
        new_log_int_id = Array(new_log.id).first
        existing_id = log_integer_ids.first

        insight.attach_evidence!([ new_log_int_id, existing_id ])

        expect(insight.reload.source_log_ids).to include(new_log_int_id)
        expect(insight.source_log_ids.count(existing_id)).to eq(1) # no duplicate
      end
    end

    describe ".referencing_log" do
      it "finds insights that reference a specific telemetry log" do
        results = described_class.referencing_log(log_integer_ids.first)
        expect(results).to include(insight)
      end

      it "does not return insights that do not reference the log" do
        other = create(:ai_insight, analyzable: tree, target_date: 3.days.ago,
                       insight_type: :carbon_yield_forecast, source_log_ids: [])
        results = described_class.referencing_log(log_integer_ids.first)
        expect(results).not_to include(other)
      end
    end
  end
end
