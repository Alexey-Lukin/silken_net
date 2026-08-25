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

      allow(Rails.logger).to receive(:info).with(/Батч abc123 завершено.*2026-03-06/)

      described_class.new.on_success(status, options)

      expect(Rails.logger).to have_received(:info).with(/Батч abc123 завершено.*2026-03-06/)
    end

    # [INS.1 / ARCH.59] Fan-out страхового оракула ПЕРЕЇХАВ у `ClusterHealthCheckWorker`
    # (там і живуть обидві гілки прапора). Вісь не знято, а ПЕРЕЦІЛЕНО: цей приклад
    # стереже, щоб сайт не повернувся сюди — у колбек, який у проді не виконується.
    # Фікстура несе ЖИВИЙ кластер зі страховкою І увімкнений прапор, тобто умови, за
    # яких старий код enqueue'вав би: без цього приклад був би зелений на порожній
    # множині й не відрізняв би «сайт знято» від «нічого не підходило».
    it "does NOT reach the insurance oracle from here — even with the flag on" do
      org = create(:organization)
      cluster = create(:cluster, organization: org)
      create(:parametric_insurance, organization: org, cluster: cluster, status: :active)
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current)
        .with(:parametric_insurance_oracle_enabled, default: false).and_return(true)

      expect { described_class.new.on_success(Sidekiq::Batch::Status.new("test-bid"), { "date" => "2026-03-06" }) }
        .not_to change { InsuranceOracleWorker.jobs.size }
    end
  end
end
