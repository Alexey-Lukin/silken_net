# frozen_string_literal: true

require "rails_helper"

RSpec.describe HadronKycReverifyWorker, type: :worker do
  # update_columns skips callbacks (no extra KYC after_commit); the mock is set
  # AFTER create so the create-triggered enqueue is not counted — only the
  # worker's own effect is asserted.
  def stale_pending(factory, status: "pending", updated_at: 2.hours.ago, **attrs)
    rec = create(factory)
    rec.update_columns({ hadron_kyc_status: status, updated_at: updated_at }.merge(attrs))
    rec
  end

  describe "#perform" do
    it "re-enqueues verification for a stale pending Wallet with its own address" do
      wallet = stale_pending(:wallet)
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).to have_received(:perform_async).with("Wallet", wallet.id)
    end

    it "re-enqueues verification for a stale pending Organization" do
      org = stale_pending(:organization)
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).to have_received(:perform_async).with("Organization", org.id)
    end

    it "skips approved Wallets — only stranded pending needs recovery" do
      stale_pending(:wallet, status: "approved")
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).not_to have_received(:perform_async)
    end

    it "skips approved Organizations" do
      stale_pending(:organization, status: "approved")
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).not_to have_received(:perform_async)
    end

    it "skips rejected subjects (terminal, not a stuck-verify)" do
      stale_pending(:wallet, status: "rejected")
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).not_to have_received(:perform_async)
    end

    it "skips fresh pending Wallets still inside the first-verify cycle" do
      stale_pending(:wallet, updated_at: Time.current)
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).not_to have_received(:perform_async)
    end

    it "skips fresh pending Organizations" do
      stale_pending(:organization, updated_at: Time.current)
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).not_to have_received(:perform_async)
    end

    it "skips custodial wallets without their own address (org-KYC governs)" do
      wallet = stale_pending(:wallet, crypto_public_address: nil)
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).not_to have_received(:perform_async).with("Wallet", wallet.id)
    end

    it "caps re-enqueue at BATCH_LIMIT per model (backlog drains across crons)" do
      stub_const("#{described_class}::BATCH_LIMIT", 1)
      2.times { stale_pending(:wallet) }
      allow(HadronKycVerificationWorker).to receive(:perform_async)

      described_class.new.perform

      expect(HadronKycVerificationWorker).to have_received(:perform_async).once
    end

    it "samples the pending-KYC depth gauge (backlog visibility)" do
      stale_pending(:wallet)
      allow(HadronKycVerificationWorker).to receive(:perform_async)
      allow(SilkenNet::Metrics::HADRON_KYC_PENDING_DEPTH).to receive(:set)

      described_class.new.perform

      expect(SilkenNet::Metrics::HADRON_KYC_PENDING_DEPTH).to have_received(:set).with(an_instance_of(Integer))
    end
  end
end
