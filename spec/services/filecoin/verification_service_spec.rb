# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filecoin::VerificationService do
  let(:user) { create(:user) }
  let(:audit_log) do
    create(:audit_log,
      user: user,
      action: "update_settings",
      ipfs_cid: "QmTestCid12345"
    )
  end

  describe "#verify!" do
    context "when remote chain_hash matches local" do
      it "returns verified: true" do
        stub_ipfs_gateway_success(audit_log.chain_hash)

        result = described_class.new(audit_log).verify!

        expect(result[:verified]).to be true
        expect(result[:cid]).to eq("QmTestCid12345")
        expect(result[:chain_hash]).to eq(audit_log.chain_hash)
      end
    end

    context "when remote chain_hash does not match" do
      it "returns verified: false with both hashes" do
        stub_ipfs_gateway_success("tampered_hash_value")

        result = described_class.new(audit_log).verify!

        expect(result[:verified]).to be false
        expect(result[:local_hash]).to eq(audit_log.chain_hash)
        expect(result[:remote_hash]).to eq("tampered_hash_value")
      end
    end

    context "when audit log has no CID" do
      it "raises an error" do
        audit_log.update_column(:ipfs_cid, nil)

        expect {
          described_class.new(audit_log).verify!
        }.to raise_error(RuntimeError, /has no IPFS CID/)
      end
    end

    context "when IPFS gateway fails" do
      it "raises an error on HTTP failure" do
        stub_ipfs_gateway_failure

        expect {
          described_class.new(audit_log).verify!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin API returned 404/)
      end
    end

    context "when IPFS gateway times out" do
      it "raises a timeout error" do
        allow(Web3::HttpClient).to receive(:get)
          .and_raise(Web3::HttpClient::RequestError.new("Filecoin Timeout: execution expired"))

        expect {
          described_class.new(audit_log).verify!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin Timeout/)
      end
    end

    context "when IPFS returns invalid JSON" do
      it "raises a parse error" do
        response = Web3::HttpClient::Response.new("not json")
        allow(Web3::HttpClient).to receive(:get).and_return(response)

        expect {
          described_class.new(audit_log).verify!
        }.to raise_error(Web3::HttpClient::RequestError, /Invalid JSON response/)
      end
    end
  end

  private

  def stub_ipfs_gateway_success(chain_hash)
    response = Web3::HttpClient::Response.new(
      { "chain_hash" => chain_hash, "action" => "update_settings" }.to_json
    )
    allow(Web3::HttpClient).to receive(:get).and_return(response)
  end

  def stub_ipfs_gateway_failure
    allow(Web3::HttpClient).to receive(:get)
      .and_raise(Web3::HttpClient::RequestError.new("Filecoin API returned 404: Not Found"))
  end
end
