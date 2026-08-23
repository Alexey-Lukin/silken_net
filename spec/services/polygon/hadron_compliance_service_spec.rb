# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Polygon::HadronComplianceService do
  describe "#verify_investor!" do
    let(:tree) { create(:tree) }
    let(:wallet) { tree.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "pending") } }

    before do
      silence_broadcasts!(:wallet_balance, :tree_map)
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

    context "when WEB3_STRICT_MODE=true without API key" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return(nil)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("WEB3_STRICT_MODE").and_return("true")
      end

      it "raises ComplianceError instead of running the simulator" do
        expect {
          described_class.new.verify_investor!(wallet)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /WEB3_STRICT_MODE/)
      end
    end

    # A forgotten WEB3_STRICT_MODE on a deploy surface must NOT reopen the fake-KYC hole:
    # production alone fails closed (belt-and-suspenders, mirrors oracle_callbacks/helium_sos).
    context "when RAILS_ENV=production without the flag or an API key" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return(nil)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("WEB3_STRICT_MODE").and_return(nil)
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "raises instead of simulating (production alone is fail-closed)" do
        expect {
          described_class.new.verify_investor!(wallet)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /production/)
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
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Hadron Timeout: execution expired"))
      end

      it "raises ComplianceError" do
        expect {
          described_class.new.verify_investor!(wallet)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /Timeout/)
      end
    end
  end

  # [KYC.1] KYC організації-бенефіціара (custodial-мінт успадковує цей статус).
  describe "#verify_organization!" do
    let(:organization) { create(:organization) }

    context "when simulation mode (no API key)" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return(nil)
      end

      it "approves the organization KYC status" do
        result = described_class.new.verify_organization!(organization)

        expect(result).to eq("approved")
        expect(organization.reload.hadron_kyc_status).to eq("approved")
      end
    end

    context "when Hadron API returns rejected" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        stub_request_with_response({ "status" => "rejected" })
      end

      it "sets organization status to rejected" do
        result = described_class.new.verify_organization!(organization)

        expect(result).to eq("rejected")
        expect(organization.reload.hadron_kyc_status).to eq("rejected")
      end
    end

    context "when organization has a blank crypto address" do
      it "raises ComplianceError" do
        organization.crypto_public_address = ""

        expect {
          described_class.new.verify_organization!(organization)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /crypto_public_address/)
      end
    end
  end

  describe "#register_asset!" do
    let(:naas_contract) { create(:naas_contract) }

    before do
      silence_broadcasts!(:wallet_balance, :tree_map)
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

    context "when WEB3_STRICT_MODE=true without API key" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return(nil)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("WEB3_STRICT_MODE").and_return("true")
      end

      it "raises ComplianceError instead of running the simulator" do
        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /WEB3_STRICT_MODE/)
      end
    end

    context "when RAILS_ENV=production without the flag or an API key" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return(nil)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("WEB3_STRICT_MODE").and_return(nil)
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "raises instead of simulating (production alone is fail-closed)" do
        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /production/)
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
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Hadron API returned 500: Internal Server Error"))
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
        response = Web3::HttpClient::Response.new("not json")
        allow(Web3::HttpClient).to receive(:post).and_return(response)
      end

      it "raises ComplianceError for parse error on KYC" do
        tree_local = create(:tree)
        wallet_local = tree_local.wallet.tap { |w| w.update!(crypto_public_address: "0x" + "c" * 40) }

        expect {
          described_class.new.verify_investor!(wallet_local)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /Invalid JSON response/)
      end
    end

    context "when Hadron API asset registration returns invalid JSON" do
      before do
        allow(Rails.application.credentials).to receive(:hadron_api_key).and_return("test-hadron-key")
        response = Web3::HttpClient::Response.new("not json")
        allow(Web3::HttpClient).to receive(:post).and_return(response)
      end

      it "raises ComplianceError for parse error on asset registration" do
        expect {
          described_class.new.register_asset!(naas_contract)
        }.to raise_error(Polygon::HadronComplianceService::ComplianceError, /Invalid JSON response/)
      end
    end
  end

  private

  def stub_request_with_response(body_hash)
    response = Web3::HttpClient::Response.new(body_hash.to_json)
    allow(Web3::HttpClient).to receive(:post).and_return(response)
  end
end
