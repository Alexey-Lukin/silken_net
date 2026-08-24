# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe HadronAssetRegistrationWorker, type: :worker do
  before do
    silence_broadcasts!(:wallet_balance, :tree_map)
  end

  describe "sidekiq_options" do
    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
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
    it "calls Polygon::HadronComplianceService for the given NaaS contract" do
      naas_contract = create(:naas_contract)

      service = instance_double(Polygon::HadronComplianceService)
      allow(Polygon::HadronComplianceService).to receive(:new).and_return(service)
      allow(service).to receive(:register_asset!).with(naas_contract).and_return("HADRON-RWA-TEST-123")

      described_class.new.perform(naas_contract.id)

      expect(service).to have_received(:register_asset!).with(naas_contract)
    end

    it "passes the correct NaaS contract to the service" do
      naas_contract = create(:naas_contract)

      service = instance_double(Polygon::HadronComplianceService)
      allow(Polygon::HadronComplianceService).to receive(:new).and_return(service)
      allow(service).to receive(:register_asset!).and_return("HADRON-RWA-TEST-456")

      described_class.new.perform(naas_contract.id)

      expect(service).to have_received(:register_asset!).with(naas_contract)
    end

    it "logs warning when NaaS contract is not found" do
      allow(Rails.logger).to receive(:warn).with(/NaaSContract #999999 not found/)

      expect { described_class.new.perform(999_999) }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with(/NaaSContract #999999 not found/)
    end

    it "does not raise when NaaS contract is not found" do
      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "re-raises HTTPX::TimeoutError for Sidekiq retry" do
      naas_contract = create(:naas_contract)

      service = instance_double(Polygon::HadronComplianceService)
      allow(Polygon::HadronComplianceService).to receive(:new).and_return(service)
      allow(service).to receive(:register_asset!).and_raise(HTTPX::TimeoutError.new(nil, "Hadron API timeout"))
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform(naas_contract.id)
      }.to raise_error(HTTPX::TimeoutError)
    end

    it "re-raises connection errors for Sidekiq retry" do
      naas_contract = create(:naas_contract)

      service = instance_double(Polygon::HadronComplianceService)
      allow(Polygon::HadronComplianceService).to receive(:new).and_return(service)
      allow(service).to receive(:register_asset!).and_raise(Errno::ECONNREFUSED, "Hadron API unavailable")
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)

      expect {
        described_class.new.perform(naas_contract.id)
      }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
