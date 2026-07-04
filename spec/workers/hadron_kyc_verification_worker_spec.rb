# frozen_string_literal: true

require "rails_helper"

RSpec.describe HadronKycVerificationWorker, type: :worker do
  let(:worker) { described_class.new }
  let(:service) { instance_double(Polygon::HadronComplianceService) }

  before do
    allow(Polygon::HadronComplianceService).to receive(:new).and_return(service)
  end

  describe "sidekiq options" do
    it "uses the web3_low queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("web3_low")
    end
  end

  describe "#perform" do
    it "verifies an Organization beneficiary" do
      organization = create(:organization)
      allow(service).to receive(:verify_organization!)

      worker.perform("Organization", organization.id)

      expect(service).to have_received(:verify_organization!).with(organization)
    end

    it "verifies a Wallet with its own address" do
      tree = create(:tree)
      wallet = tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40) }
      allow(service).to receive(:verify_investor!)

      worker.perform("Wallet", wallet.id)

      expect(service).to have_received(:verify_investor!).with(wallet)
    end

    it "skips a custodial wallet without its own address (org-KYC governs)" do
      tree = create(:tree)
      wallet = tree.wallet
      wallet.update_column(:crypto_public_address, nil)

      worker.perform("Wallet", wallet.id)

      expect(Polygon::HadronComplianceService).not_to have_received(:new)
    end

    it "skips gracefully when the record is gone" do
      expect { worker.perform("Wallet", -1) }.not_to raise_error
    end

    it "refuses unknown subject types (whitelist)" do
      expect { worker.perform("User", 1) }.to raise_error(KeyError)
    end
  end
end
