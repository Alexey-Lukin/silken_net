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

    it "calls InsightGeneratorService.cleanup_old_logs!" do
      status = Sidekiq::Batch::Status.new("test-bid")
      options = { "date" => "2026-03-06" }

      expect(InsightGeneratorService).to receive(:cleanup_old_logs!)

      described_class.new.on_success(status, options)
    end

    it "logs batch completion with date" do
      status = Sidekiq::Batch::Status.new("abc123")
      options = { "date" => "2026-03-06" }

      allow(InsightGeneratorService).to receive(:cleanup_old_logs!)
      expect(Rails.logger).to receive(:info).with(/Батч abc123 завершено.*2026-03-06/)

      described_class.new.on_success(status, options)
    end
  end
end
