# frozen_string_literal: true

require "rails_helper"

RSpec.describe TheGraph::QueryService, type: :service do
  let(:mock_http) { instance_double(Net::HTTP) }

  describe "#fetch_total_carbon_minted" do
    context "when The Graph credentials are configured" do
      before do
        allow(Rails.application.credentials).to receive(:the_graph_api_url)
          .and_return("https://api.thegraph.com/subgraphs/name/silken-net/carbon")
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      end

      it "returns total minted amount from The Graph events" do
        body = {
          data: {
            carbonMintEvents: [
              { "id" => "0xabc-0", "to" => "0x123", "amount" => "500000", "treeDid" => "did:peaq:0x1", "timestamp" => "1700000000" },
              { "id" => "0xdef-1", "to" => "0x456", "amount" => "300000", "treeDid" => "did:peaq:0x2", "timestamp" => "1700000100" }
            ]
          }
        }.to_json

        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(response).to receive(:body).and_return(body)
        allow(mock_http).to receive(:request).and_return(response)

        result = described_class.new.fetch_total_carbon_minted
        expect(result).to eq(800_000)
      end

      it "sends a valid GraphQL query to the configured URL" do
        body = { data: { carbonMintEvents: [] } }.to_json

        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(response).to receive(:body).and_return(body)

        allow(mock_http).to receive(:request) do |request|
          parsed = JSON.parse(request.body)
          expect(parsed).to have_key("query")
          expect(parsed["query"]).to include("carbonMintEvents")
          expect(parsed["query"]).to include("first: 100")
          expect(request["Content-Type"]).to eq("application/json")
          response
        end

        described_class.new.fetch_total_carbon_minted
      end

      it "returns 0 when no events exist" do
        body = { data: { carbonMintEvents: [] } }.to_json

        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(response).to receive(:body).and_return(body)
        allow(mock_http).to receive(:request).and_return(response)

        result = described_class.new.fetch_total_carbon_minted
        expect(result).to eq(0)
      end

      it "raises QueryError when The Graph returns error" do
        error_response = Net::HTTPInternalServerError.allocate
        allow(error_response).to receive_messages(code: "500", body: "Internal Server Error")
        allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_http).to receive(:request).and_return(error_response)

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /The Graph повернув 500/)
      end

      it "raises QueryError on network failure" do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /Збій зв'язку з The Graph/)
      end

      it "raises QueryError on timeout" do
        allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /Збій зв'язку з The Graph/)
      end

      it "raises QueryError on invalid JSON response" do
        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(response).to receive(:body).and_return("not-json")
        allow(mock_http).to receive(:request).and_return(response)

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /Невалідна відповідь від The Graph/)
      end

      it "handles missing data key in response gracefully" do
        body = { errors: [ { message: "something went wrong" } ] }.to_json

        response = Net::HTTPSuccess.allocate
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(response).to receive(:body).and_return(body)
        allow(mock_http).to receive(:request).and_return(response)

        result = described_class.new.fetch_total_carbon_minted
        expect(result).to eq(0)
      end
    end

    context "when the_graph_api_url is not configured" do
      before do
        allow(Rails.application.credentials).to receive(:the_graph_api_url).and_return(nil)
      end

      it "raises QueryError" do
        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /the_graph_api_url не налаштовано/)
      end
    end
  end
end
