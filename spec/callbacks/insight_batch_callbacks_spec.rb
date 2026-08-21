# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsightBatchCallbacks do
  describe "#on_success" do
    it "enqueues ClusterHealthCheckWorker with the date" do
      status = Sidekiq::Batch::Status.new("test-bid")
      options = { "date" => "2026-03-06" }

      described_class.new.on_success(status, options)

      expect(ClusterHealthCheckWorker.jobs.size).to eq(1)
      expect(ClusterHealthCheckWorker.jobs.first["args"]).to eq([ "2026-03-06" ])
    end

    it "logs batch completion with date" do
      status = Sidekiq::Batch::Status.new("abc123")
      options = { "date" => "2026-03-06" }

      expect(Rails.logger).to receive(:info).with(/Батч abc123 завершено.*2026-03-06/)

      described_class.new.on_success(status, options)
    end

    # [INS.1] Страховий оракул — per-cluster fan-out, за майстер-прапором (kill-switch).
    context "with the insurance oracle fan-out (gated)" do
      let(:org)        { create(:organization) }
      let(:cluster)    { create(:cluster, organization: org) }
      let!(:insurance) { create(:parametric_insurance, organization: org, cluster: cluster, status: :active) }
      let(:status)     { Sidekiq::Batch::Status.new("test-bid") }
      let(:options)    { { "date" => "2026-03-06" } }

      it "enqueues InsuranceOracleWorker per active-insurance cluster when the flag is on" do
        allow(SystemParameter).to receive(:current).and_call_original
        allow(SystemParameter).to receive(:current)
          .with(:parametric_insurance_oracle_enabled, default: false).and_return(true)

        expect { described_class.new.on_success(status, options) }
          .to change { InsuranceOracleWorker.jobs.size }.by(1)

        expect(InsuranceOracleWorker.jobs.first["args"]).to eq([ cluster.id, "2026-03-06" ])
      end

      it "does NOT enqueue the insurance oracle when the flag is off (default)" do
        expect { described_class.new.on_success(status, options) }
          .not_to change { InsuranceOracleWorker.jobs.size }
      end
    end
  end
end
