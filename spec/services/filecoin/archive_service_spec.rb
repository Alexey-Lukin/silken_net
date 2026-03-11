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
        allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
          expected_body = JSON.parse(req.body)
          instance_double(Net::HTTPSuccess, body: { "IpfsHash" => "QmTestCid12345" }.to_json, is_a?: true).tap do |resp|
            allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          end
        end

        described_class.new(audit_log).archive!

        content = expected_body["pinataContent"]
        expect(content["chain_hash"]).to eq(audit_log.chain_hash)
        expect(content["action"]).to eq("update_settings")
        expect(content["metadata"]).to eq("field" => "critical_z", "old_value" => 100, "new_value" => 200)
      end

      it "includes telemetry_summary key in the payload" do
        expected_body = nil
        allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
          expected_body = JSON.parse(req.body)
          instance_double(Net::HTTPSuccess, body: { "IpfsHash" => "QmTestCid12345" }.to_json, is_a?: true).tap do |resp|
            allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          end
        end

        described_class.new(audit_log).archive!

        content = expected_body["pinataContent"]
        expect(content).to have_key("telemetry_summary")
      end

      it "sends Bearer authorization header" do
        expected_auth = nil
        allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
          expected_auth = req["Authorization"]
          instance_double(Net::HTTPSuccess, body: { "IpfsHash" => "QmTestCid12345" }.to_json).tap do |resp|
            allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          end
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
        }.to raise_error(RuntimeError, /IPFS upload failed/)
      end
    end

    context "when IPFS upload times out" do
      it "raises a timeout error" do
        allow_any_instance_of(Net::HTTP).to receive(:request)
          .and_raise(Net::ReadTimeout.new("execution expired"))

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(RuntimeError, /Filecoin IPFS Timeout/)
      end
    end

    context "when IPFS response has no CID" do
      it "raises an error about missing CID" do
        mock_response = instance_double(Net::HTTPSuccess,
          body: { "status" => "ok" }.to_json
        )
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(RuntimeError, /No CID returned/)
      end
    end
  end

  private

  def stub_pinata_success
    mock_response = instance_double(Net::HTTPSuccess,
      body: { "IpfsHash" => "QmTestCid12345", "PinSize" => 1234, "Timestamp" => "2026-03-11T12:00:00Z" }.to_json
    )
    allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)
  end

  def stub_pinata_failure
    mock_response = instance_double(Net::HTTPUnauthorized,
      body: "Unauthorized", code: "401"
    )
    allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)

    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)
  end
end
