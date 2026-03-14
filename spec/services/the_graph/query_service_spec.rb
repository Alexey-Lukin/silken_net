# frozen_string_literal: true

require "rails_helper"

RSpec.describe TheGraph::QueryService, type: :service do
  describe "#fetch_total_carbon_minted" do
    context "when The Graph credentials are configured" do
      before do
        allow(Rails.application.credentials).to receive(:the_graph_api_url)
          .and_return("https://api.thegraph.com/subgraphs/name/silken-net/carbon")
      end

      it "returns total minted amount from The Graph events" do
        body = {
          "data" => {
            "carbonMintEvents" => [
              { "id" => "0xabc-0", "to" => "0x123", "amount" => "500000", "treeDid" => "did:peaq:0x1", "timestamp" => "1700000000" },
              { "id" => "0xdef-1", "to" => "0x456", "amount" => "300000", "treeDid" => "did:peaq:0x2", "timestamp" => "1700000100" }
            ]
          }
        }

        response = Web3::HttpClient::Response.new(body.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        result = described_class.new.fetch_total_carbon_minted
        expect(result).to eq(800_000)
      end

      it "sends a valid GraphQL query to the configured URL" do
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          body = kwargs[:body]
          expect(body).to have_key(:query)
          expect(body[:query]).to include("carbonMintEvents")
          expect(body[:query]).to include("first: 100")
          Web3::HttpClient::Response.new({ "data" => { "carbonMintEvents" => [] } }.to_json)
        end

        described_class.new.fetch_total_carbon_minted
      end

      it "returns 0 when no events exist" do
        response = Web3::HttpClient::Response.new({ "data" => { "carbonMintEvents" => [] } }.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        result = described_class.new.fetch_total_carbon_minted
        expect(result).to eq(0)
      end

      it "raises QueryError when The Graph returns error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("The Graph API returned 500: Internal Server Error"))

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /The Graph API returned 500/)
      end

      it "raises QueryError on network failure" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("The Graph connection error: Connection refused"))

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /The Graph connection error/)
      end

      it "raises QueryError on timeout" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("The Graph Timeout: execution expired"))

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /The Graph Timeout/)
      end

      it "raises QueryError on invalid JSON response" do
        response = Web3::HttpClient::Response.new("not-json")
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /Invalid JSON response/)
      end

      it "wraps unexpected StandardError in QueryError" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(NoMethodError, "undefined method for nil:NilClass")

        expect {
          described_class.new.fetch_total_carbon_minted
        }.to raise_error(TheGraph::QueryService::QueryError, /Збій зв'язку з The Graph/)
      end

      it "handles missing data key in response gracefully" do
        response = Web3::HttpClient::Response.new({ "errors" => [ { "message" => "something went wrong" } ] }.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

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

  describe "#fetch_protocol_financials" do
    context "when The Graph credentials are configured" do
      before do
        allow(Rails.application.credentials).to receive(:the_graph_api_url)
          .and_return("https://api.thegraph.com/subgraphs/name/silken-net/carbon")
      end

      it "returns protocol financials from The Graph singleton entity" do
        body = {
          "data" => {
            "protocolFinancial" => {
              "totalMinted" => "1000000",
              "totalBurned" => "250000",
              "totalPremiums" => "50000"
            }
          }
        }

        response = Web3::HttpClient::Response.new(body.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        result = described_class.new.fetch_protocol_financials
        expect(result).to eq(total_minted: 1_000_000, total_burned: 250_000, total_premiums: 50_000)
      end

      it "sends a valid GraphQL query for protocolFinancial" do
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          body = kwargs[:body]
          expect(body).to have_key(:query)
          expect(body[:query]).to include('protocolFinancial(id: "1")')
          expect(body[:query]).to include("totalMinted")
          expect(body[:query]).to include("totalBurned")
          expect(body[:query]).to include("totalPremiums")
          Web3::HttpClient::Response.new({ "data" => { "protocolFinancial" => nil } }.to_json)
        end

        described_class.new.fetch_protocol_financials
      end

      it "returns zeros when entity does not exist" do
        response = Web3::HttpClient::Response.new({ "data" => { "protocolFinancial" => nil } }.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        result = described_class.new.fetch_protocol_financials
        expect(result).to eq(total_minted: 0, total_burned: 0, total_premiums: 0)
      end

      it "raises QueryError when The Graph returns error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("The Graph API returned 500: Internal Server Error"))

        expect {
          described_class.new.fetch_protocol_financials
        }.to raise_error(TheGraph::QueryService::QueryError, /The Graph API returned 500/)
      end

      it "raises QueryError on network failure" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("The Graph connection error: Connection refused"))

        expect {
          described_class.new.fetch_protocol_financials
        }.to raise_error(TheGraph::QueryService::QueryError, /The Graph connection error/)
      end

      it "wraps unexpected StandardError in QueryError" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(NoMethodError, "undefined method for nil:NilClass")

        expect {
          described_class.new.fetch_protocol_financials
        }.to raise_error(TheGraph::QueryService::QueryError, /Збій зв'язку з The Graph/)
      end
    end

    context "when the_graph_api_url is not configured" do
      before do
        allow(Rails.application.credentials).to receive(:the_graph_api_url).and_return(nil)
      end

      it "raises QueryError" do
        expect {
          described_class.new.fetch_protocol_financials
        }.to raise_error(TheGraph::QueryService::QueryError, /the_graph_api_url не налаштовано/)
      end
    end
  end
end
