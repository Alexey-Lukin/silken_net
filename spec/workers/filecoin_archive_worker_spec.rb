# frozen_string_literal: true

require "rails_helper"

RSpec.describe FilecoinArchiveWorker, type: :worker do
  describe "sidekiq_options" do
    it "uses the low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("low")
    end

    it "has retry set to 5" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end
  end

  describe "module inclusion" do
    it "includes ApplicationWeb3Worker" do
      expect(described_class.ancestors).to include(ApplicationWeb3Worker)
    end
  end

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

    it "passes the audit log to ArchiveService constructor" do
      user = create(:user)
      audit_log = create(:audit_log, user: user, action: "token_mint")

      service = instance_double(Filecoin::ArchiveService)
      allow(Filecoin::ArchiveService).to receive(:new).and_return(service)
      allow(service).to receive(:archive!).and_return("QmCid123")

      described_class.new.perform(audit_log.id)

      expect(Filecoin::ArchiveService).to have_received(:new).with(audit_log)
    end

    it "logs warning when audit log is not found (RecordNotFound rescue)" do
      expect(Rails.logger).to receive(:warn).with(/AuditLog #999999 not found/)

      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "does not raise when audit log is not found" do
      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "re-raises HTTPX::TimeoutError for Sidekiq retry" do
      user = create(:user)
      audit_log = create(:audit_log, user: user, action: "login")

      service = instance_double(Filecoin::ArchiveService)
      allow(Filecoin::ArchiveService).to receive(:new).and_return(service)
      allow(service).to receive(:archive!).and_raise(HTTPX::TimeoutError.new(nil, "Pinata timeout"))
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform(audit_log.id)
      }.to raise_error(HTTPX::TimeoutError)
    end

    it "re-raises connection errors for Sidekiq retry" do
      user = create(:user)
      audit_log = create(:audit_log, user: user, action: "login")

      service = instance_double(Filecoin::ArchiveService)
      allow(Filecoin::ArchiveService).to receive(:new).and_return(service)
      allow(service).to receive(:archive!).and_raise(Errno::ECONNREFUSED, "IPFS gateway down")
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform(audit_log.id)
      }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
