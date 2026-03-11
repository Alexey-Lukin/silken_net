# frozen_string_literal: true

require "rails_helper"

RSpec.describe Polygon::HadronComplianceService do
  describe "#verify_investor!" do
    let(:tree) { create(:tree) }
    let(:wallet) { tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "pending") } }

    before do
      allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
      allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    end

    context "when wallet has no crypto address" do
      it "raises ComplianceError" do
        wallet.update!(crypto_public_address: nil)

        expect {
          described_class.new.verify_investor!(wallet)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /crypto_public_address/)
      end
    end

    context "when simulation mode (no API key)" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return(nil)
      end

      it "approves the wallet KYC status" do
        result = described_class.new.verify_investor!(wallet)

        expect(result).to eq("approved")
        expect(wallet.reload.hadron_kyc_status).to eq("approved")
      end
    end

    context "when Hadron API returns approved" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        stub_request_with_response({ "status" => "approved" })
      end

      it "sets wallet status to approved" do
        result = described_class.new.verify_investor!(wallet)

        expect(result).to eq("approved")
        expect(wallet.reload.hadron_kyc_status).to eq("approved")
      end
    end

    context "when Hadron API returns rejected" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        stub_request_with_response({ "status" => "rejected" })
      end

      it "sets wallet status to rejected" do
        result = described_class.new.verify_investor!(wallet)

        expect(result).to eq("rejected")
        expect(wallet.reload.hadron_kyc_status).to eq("rejected")
      end
    end

    context "when Hadron API times out" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout.new("execution expired"))
      end

      it "raises ComplianceError" do
        expect {
          described_class.new.verify_investor!(wallet)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /timeout/)
      end
    end
  end

  describe "#register_asset!" do
    let(:naas_contract) { create(:naas_contract) }

    before do
      allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
      allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    end

    context "when contract is not active" do
      it "raises ComplianceError" do
        naas_contract.update!(status: :draft)

        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /must be active/)
      end
    end

    context "when simulation mode (no API key)" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return(nil)
      end

      it "registers asset and saves hadron_asset_id" do
        asset_id = described_class.new.register_asset!(naas_contract)

        expect(asset_id).to start_with("HADRON-RWA-#{naas_contract.id}-")
        expect(naas_contract.reload.hadron_asset_id).to eq(asset_id)
      end
    end

    context "when Hadron API succeeds" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        stub_request_with_response({ "asset_id" => "HADRON-RWA-POLYGON-42" })
      end

      it "saves the returned asset_id" do
        asset_id = described_class.new.register_asset!(naas_contract)

        expect(asset_id).to eq("HADRON-RWA-POLYGON-42")
        expect(naas_contract.reload.hadron_asset_id).to eq("HADRON-RWA-POLYGON-42")
      end
    end

    context "when NaaSContract has no cluster" do
      it "raises ComplianceError" do
        allow(naas_contract).to receive(:cluster).and_return(nil)

        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /must have an associated Cluster/)
      end
    end

    context "when Hadron API returns no asset_id" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        stub_request_with_response({ "status" => "ok" })
      end

      it "raises ComplianceError about missing asset_id" do
        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /did not return an asset_id/)
      end
    end

    context "when Hadron API returns non-success HTTP" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        mock_response = instance_double(Net::HTTPServerError, code: "500", body: "Internal Server Error")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(Net::HTTP).to receive(:start).and_return(mock_response)
      end

      it "raises ComplianceError for non-success response" do
        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /Hadron API returned 500/)
      end
    end

    context "when Hadron API KYC returns invalid JSON" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        mock_response = instance_double(Net::HTTPSuccess, body: "not json")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(Net::HTTP).to receive(:start).and_return(mock_response)
      end

      it "raises ComplianceError for parse error on KYC" do
        tree_local = create(:tree)
        wallet_local = tree_local.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "c" * 40) }

        expect {
          described_class.new.verify_investor!(wallet_local)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /Invalid response from Hadron KYC API/)
      end
    end

    context "when Hadron API asset registration returns invalid JSON" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        mock_response = instance_double(Net::HTTPSuccess, body: "not json")
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(Net::HTTP).to receive(:start).and_return(mock_response)
      end

      it "raises ComplianceError for parse error on asset registration" do
        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /Invalid response from Hadron Asset API/)
      end
    end
  end

  private

  def stub_request_with_response(body_hash)
    mock_response = instance_double(Net::HTTPSuccess, body: body_hash.to_json)
    allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(Net::HTTP).to receive(:start).and_return(mock_response)
  end
end
