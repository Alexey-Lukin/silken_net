# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsurancePayoutRecoveryWorker, type: :worker do
  describe "#perform" do
    it "re-enqueues InsurancePayoutWorker only for insurances stuck in :triggered" do
      triggered = create(:parametric_insurance, :triggered)
      create(:parametric_insurance) # :active — must be skipped
      allow(InsurancePayoutWorker).to receive(:perform_async)

      described_class.new.perform

      expect(InsurancePayoutWorker).to have_received(:perform_async).with(triggered.id).once
      expect(InsurancePayoutWorker).to have_received(:perform_async).exactly(:once)
    end

    it "enqueues nothing when no insurances are stuck in :triggered" do
      create(:parametric_insurance) # :active only
      allow(InsurancePayoutWorker).to receive(:perform_async)

      described_class.new.perform

      expect(InsurancePayoutWorker).not_to have_received(:perform_async)
    end
  end
end
