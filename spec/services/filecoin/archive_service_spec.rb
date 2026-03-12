# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filecoin::ArchiveService do
  let(:user) { create(:user) }
  let(:audit_log) do
    create(:audit_log,
      user: user,
      action: "update_settings",
      metadata: { field: "critical_z", old_value: 100, new_value: 200 }
    )
  end

  before do
    allow(Rails.application.credentials).to receive(:filecoin_api_key).and_return("test-api-key")
  end

  describe "#archive!" do
    context "when upload succeeds" do
      before { stub_pinata_success }

      it "uploads audit log data and saves CID" do
        cid = described_class.new(audit_log).archive!

        expect(cid).to eq("QmTestCid12345")
        expect(audit_log.reload.ipfs_cid).to eq("QmTestCid12345")
      end

      it "includes chain_hash and metadata in the payload" do
        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmTestCid12345" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content[:chain_hash]).to eq(audit_log.chain_hash)
        expect(content[:action]).to eq("update_settings")
        expect(content[:metadata]).to eq("field" => "critical_z", "old_value" => 100, "new_value" => 200)
      end

      it "includes telemetry_summary key in the payload" do
        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmTestCid12345" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content).to have_key(:telemetry_summary)
      end

      it "sends Bearer authorization header" do
        expected_auth = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_auth = kwargs[:headers]["Authorization"]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmTestCid12345" }.to_json)
        end

        described_class.new(audit_log).archive!

        expect(expected_auth).to eq("Bearer test-api-key")
      end
    end

    context "when audit log already has CID" do
      it "skips upload and returns nil" do
        audit_log.update!(ipfs_cid: "QmExistingCid")

        result = described_class.new(audit_log).archive!

        expect(result).to be_nil
      end
    end

    context "when API key is missing" do
      before do
        allow(Rails.application.credentials).to receive(:filecoin_api_key).and_return(nil)
      end

      it "raises an error about missing credentials" do
        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(RuntimeError, /Missing filecoin_api_key/)
      end
    end

    context "when IPFS upload fails" do
      it "raises an error on HTTP failure" do
        stub_pinata_failure

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin API returned 401/)
      end
    end

    context "when IPFS upload times out" do
      it "raises a timeout error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Filecoin Timeout: execution expired"))

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin Timeout/)
      end
    end

    context "when IPFS response has no CID" do
      it "raises an error about missing CID" do
        response = Web3::HttpClient::Response.new({ "status" => "ok" }.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(RuntimeError, /No CID returned/)
      end
    end

    context "when IPFS response body is invalid JSON" do
      it "raises a parse error" do
        response = Web3::HttpClient::Response.new("not json at all")
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Invalid JSON response/)
      end
    end

    context "when audit_log.created_at is nil" do
      it "sets telemetry_summary to nil in payload" do
        allow(audit_log).to receive(:created_at).and_return(nil)

        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmNilDate" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content[:telemetry_summary]).to be_nil
        expect(content[:created_at]).to be_nil
      end
    end

    context "when no AI insights exist for the date" do
      it "sets telemetry_summary to nil when summaries are empty" do
        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmNoInsights" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        # No AI insights exist, so telemetry_summary should be nil
        expect(content).to have_key(:telemetry_summary)
      end
    end

    context "when Net::OpenTimeout is raised" do
      it "raises a timeout error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Filecoin Timeout: connection timeout"))

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin Timeout/)
      end
    end
  end

  private

  def stub_pinata_success
    response = Web3::HttpClient::Response.new(
      { "IpfsHash" => "QmTestCid12345", "PinSize" => 1234, "Timestamp" => "2026-03-11T12:00:00Z" }.to_json
    )
    allow(Web3::HttpClient).to receive(:post).and_return(response)
  end

  def stub_pinata_failure
    allow(Web3::HttpClient).to receive(:post)
      .and_raise(Web3::HttpClient::RequestError.new("Filecoin API returned 401: Unauthorized"))
  end
end
