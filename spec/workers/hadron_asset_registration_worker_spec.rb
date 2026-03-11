# frozen_string_literal: true

require "rails_helper"

RSpec.describe HadronAssetRegistrationWorker, type: :worker do
  before do
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
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

    it "logs warning when NaaS contract is not found" do
      expect(Rails.logger).to receive(:warn).with(/NaaSContract #999999 not found/)

      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
    end

    it "has retry set to 5" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end
  end
end
