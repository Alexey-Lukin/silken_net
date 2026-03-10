# frozen_string_literal: true

require "rails_helper"

RSpec.describe Peaq::DidRegistryService, type: :service do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#register!" do
    context "when peaq_node_url is configured" do
      before do
        allow(Rails.application.credentials).to receive(:peaq_node_url).and_return("https://peaq-node.example.com")
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      end

      it "returns a peaq DID string with correct prefix" do
        allow(mock_http).to receive(:request).and_return(Net::HTTPSuccess.allocate)

        service = described_class.new(tree)
        result = service.register!

        expect(result).to start_with("did:peaq:0x")
        expect(result.length).to eq(49) # "did:peaq:0x" (11) + 40 hex chars
      end

      it "generates deterministic DID based on tree attributes" do
        allow(mock_http).to receive(:request).and_return(Net::HTTPSuccess.allocate)

        service = described_class.new(tree)
        did1 = service.register!
        did2 = service.register!

        expect(did1).to eq(did2)
      end

      it "raises RegistrationError when peaq node returns error" do
        error_response = Net::HTTPInternalServerError.allocate
        allow(error_response).to receive_messages(code: "500", body: "Internal Server Error")
        allow(mock_http).to receive(:request).and_return(error_response)

        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /peaq node повернув 500/)
      end

      it "raises RegistrationError on network failure" do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

        service = described_class.new(tree)

        expect {
          service.register!
        }.to raise_error(Peaq::DidRegistryService::RegistrationError, /Збій зв'язку з peaq node/)
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
