# frozen_string_literal: true

require "rails_helper"

RSpec.describe Peaq::DidRegistryService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#register!" do
    context "when peaq_node_url is configured" do
      before do
        allow(Rails.application.credentials).to receive(:peaq_node_url).and_return("https://peaq-node.example.com")
        allow(Web3::HttpClient).to receive(:post)
          .and_return(Web3::HttpClient::Response.new("{}"))
      end

      it "returns a peaq DID string with correct prefix" do
        service = described_class.new(tree)
        result = service.register!

        expect(result).to start_with("did:peaq:0x")
        expect(result.length).to eq(51) # "did:peaq:0x" (11) + 40 hex chars
      end

      it "generates deterministic DID based on tree attributes" do
        service = described_class.new(tree)
        did1 = service.register!
        did2 = service.register!

        expect(did1).to eq(did2)
      end

      it "raises RegistrationError when peaq node returns error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("peaq DID API returned 500: Internal Server Error"))

        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq DID API returned 500/)
      end

      it "raises RegistrationError on network failure" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("peaq DID connection error: Connection refused"))

        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq DID connection error/)
      end
    end

    context "when peaq_node_url is not configured" do
      before do
        allow(Rails.application.credentials).to receive(:peaq_node_url).and_return(nil)
      end

      it "raises RegistrationError" do
        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq_node_url не налаштовано/)
      end
    end
  end
end
