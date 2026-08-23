# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsuranceOracleWorker, type: :worker do
  let(:org)         { create(:organization) }
  let(:cluster)     { create(:cluster, organization: org) }
  let(:target_date) { Date.yesterday }

  before do
    allow(SystemParameter).to receive(:current).and_call_original
    allow(SystemParameter).to receive(:current)
      .with(:parametric_insurance_oracle_enabled, default: false).and_return(true)
    # EwsAlert-колбеки (arm_candidate! піднімає field_audit).
    silence_broadcasts!(:alert_notify, :alert_new)
  end

  # Активна страховка + 5 active-дерев у критичному стресі → перетинає поріг → arm.
  def armable_insurance
    insurance = create(:parametric_insurance, organization: org, cluster: cluster,
                       status: :active, threshold_value: 30, required_confirmations: 1)
    trees = create_list(:tree, 5, cluster: cluster, status: :active)
    cluster.update_column(:active_trees_count, 5)
    trees.each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.95) }
    insurance
  end

  describe "#perform" do
    it "arms active-insurance candidates via the daily oracle (Trigger-1, no payout)" do
      insurance = armable_insurance

      expect { described_class.new.perform(cluster.id, target_date.to_s) }
        .not_to change { InsurancePayoutWorker.jobs.size } # arm-only, НЕ виплата

      expect(insurance.reload).to be_status_triggered
    end

    it "is an inert no-op when the kill-switch flag is off" do
      insurance = armable_insurance
      allow(SystemParameter).to receive(:current)
        .with(:parametric_insurance_oracle_enabled, default: false).and_return(false)

      described_class.new.perform(cluster.id, target_date.to_s)

      expect(insurance.reload).to be_status_active
    end

    it "skips non-active insurances" do
      insurance = armable_insurance
      insurance.update_column(:status, ParametricInsurance.statuses[:paid])

      expect { described_class.new.perform(cluster.id, target_date.to_s) }
        .not_to change { insurance.reload.status }
    end

    it "returns gracefully for a missing cluster" do
      expect { described_class.new.perform(-1, target_date.to_s) }.not_to raise_error
    end

    # [ARCH.100] Дефолт — доба ЗАПИСУ інсайтів, не пояс кластера: доти цей пін стверджував
    # протилежне й був зелений, бо фікстурний кластер поясу не має і дві дати збігались.
    it "defaults target_date to the reporting-date anchor when no date string is passed" do
      create(:parametric_insurance, organization: org, cluster: cluster, status: :active)

      expect_any_instance_of(ParametricInsurance)
        .to receive(:evaluate_daily_health!).with(AiInsight.reporting_date)

      described_class.new.perform(cluster.id)
    end

    it "isolates a per-insurance failure and continues without raising" do
      armable_insurance
      allow_any_instance_of(ParametricInsurance).to receive(:evaluate_daily_health!).and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      expect { described_class.new.perform(cluster.id, target_date.to_s) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/страховка/)
    end

    it "logs and returns on an invalid date string (Date::Error)" do
      create(:parametric_insurance, organization: org, cluster: cluster, status: :active)
      allow(Rails.logger).to receive(:error)

      described_class.new.perform(cluster.id, "not-a-date")

      expect(Rails.logger).to have_received(:error).with(/Невірний формат дати/)
    end
  end
end
