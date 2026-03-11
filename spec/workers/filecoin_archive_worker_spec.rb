# frozen_string_literal: true

require "rails_helper"

RSpec.describe FilecoinArchiveWorker, type: :worker do
  describe "#perform" do
    it "calls Filecoin::ArchiveService for the given audit log" do
      user = create(:user)
      audit_log = create(:audit_log, user: user, action: "login")

      service = instance_double(Filecoin::ArchiveService)
      allow(Filecoin::ArchiveService).to receive(:new).with(audit_log).and_return(service)
      allow(service).to receive(:archive!).and_return("QmTestCid12345")

      described_class.new.perform(audit_log.id)

      expect(service).to have_received(:archive!)
    end

    it "logs warning when audit log is not found" do
      expect(Rails.logger).to receive(:warn).with(/AuditLog #999999 not found/)

      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "uses the low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("low")
    end

    it "has retry set to 5" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end
  end
end
