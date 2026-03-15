# frozen_string_literal: true

require "rails_helper"

RSpec.describe TokenomicsBatchCallbacks do
  describe "#on_success" do
    it "enqueues MintCarbonCoinWorker for auto-discovery minting" do
      status = Sidekiq::Batch::Status.new("test-bid")
      options = { "cycle_id" => "test-cycle-uuid" }

      described_class.new.on_success(status, options)

      expect(MintCarbonCoinWorker.jobs.size).to eq(1)
      # Auto-discovery mode: no arguments
      expect(MintCarbonCoinWorker.jobs.first["args"]).to be_empty
    end

    it "logs batch completion with cycle_id" do
      status = Sidekiq::Batch::Status.new("abc123")
      options = { "cycle_id" => "my-cycle" }

      expect(Rails.logger).to receive(:info).with(/Батч abc123 завершено.*my-cycle/)

      described_class.new.on_success(status, options)
    end
  end
end
