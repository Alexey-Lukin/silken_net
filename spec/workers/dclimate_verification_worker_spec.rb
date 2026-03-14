# frozen_string_literal: true

require "rails_helper"

RSpec.describe DclimateVerificationWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }

  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_new_alert)
    allow_any_instance_of(EwsAlert).to receive(:schedule_satellite_verification!)
    allow(InsurancePayoutWorker).to receive(:perform_async)
    allow(BurnCarbonTokensWorker).to receive(:perform_async)
  end

  describe "sidekiq_options" do
    it "uses alerts queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("alerts")
    end

    it "retries 15 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(15)
    end
  end

  describe "#perform" do
    context "when alert exists and is unverified" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

      it "calls Dclimate::VerificationService" do
        service = instance_double(Dclimate::VerificationService)
        allow(Dclimate::VerificationService).to receive(:new).with(alert).and_return(service)
        allow(service).to receive(:perform)

        described_class.new.perform(alert.id)

        expect(service).to have_received(:perform)
      end
    end

    context "when alert does not exist" do
      it "returns nil without error" do
        expect(described_class.new.perform(-1)).to be_nil
      end
    end

    context "when alert is already verified" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :verified) }

      it "skips verification" do
        expect(Dclimate::VerificationService).not_to receive(:new)
        described_class.new.perform(alert.id)
      end
    end

    context "when alert is already rejected_fraud" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :rejected_fraud) }

      it "skips verification" do
        expect(Dclimate::VerificationService).not_to receive(:new)
        described_class.new.perform(alert.id)
      end
    end

    context "when alert is already inconclusive" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :inconclusive) }

      it "skips verification" do
        expect(Dclimate::VerificationService).not_to receive(:new)
        described_class.new.perform(alert.id)
      end
    end
  end

  describe ".sidekiq_retries_exhausted" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

    it "marks alert as inconclusive" do
      job = { "args" => [ alert.id ] }
      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      alert.reload
      expect(alert).to be_satellite_inconclusive
    end

    it "sets resolution_notes with manual audit message" do
      job = { "args" => [ alert.id ] }
      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      alert.reload
      expect(alert.resolution_notes).to include("Manual DAO audit required")
    end

    it "logs a warning" do
      job = { "args" => [ alert.id ] }
      expect(Rails.logger).to receive(:warn).with(/Cosmic Eye Exhausted/)
      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)
    end

    context "when alert does not exist" do
      it "does not raise error" do
        job = { "args" => [ -1 ] }
        expect { described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new) }.not_to raise_error
      end
    end
  end
end
