# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web3::HttpClient do
  describe ".post" do
    it "sends a POST request with JSON body and returns Response" do
      stub_request(:post, "https://api.example.com/data")
        .with(
          body: { key: "value" }.to_json,
          headers: { "Content-Type" => "application/json", "Authorization" => "Bearer token123" }
        )
        .to_return(status: 200, body: '{"result": "ok"}', headers: { "Content-Type" => "application/json" })

      response = described_class.post("https://api.example.com/data",
        body: { key: "value" },
        headers: { "Authorization" => "Bearer token123" },
        service_name: "Test"
      )

      expect(response).to be_a(Web3::HttpClient::Response)
      expect(response.parsed_body).to eq({ "result" => "ok" })
    end

    it "raises RequestError on non-success HTTP response" do
      stub_request(:post, "https://api.example.com/data")
        .to_return(status: 500, body: "Internal Server Error")

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Test"
        )
      }.to raise_error(Web3::HttpClient::RequestError, /Test API returned 500/)
    end

    it "raises RequestError on timeout" do
      stub_request(:post, "https://api.example.com/data")
        .to_timeout

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Test"
        )
      }.to raise_error(Web3::HttpClient::RequestError, /Test.*Timeout|Test connection error/)
    end
  end

  describe ".get" do
    it "sends a GET request and returns Response" do
      stub_request(:get, "https://api.example.com/info")
        .with(headers: { "Accept" => "application/json" })
        .to_return(status: 200, body: '{"data": "test"}', headers: { "Content-Type" => "application/json" })

      response = described_class.get("https://api.example.com/info",
        headers: { "Accept" => "application/json" },
        service_name: "Test"
      )

      expect(response.parsed_body).to eq({ "data" => "test" })
    end

    it "raises RequestError on non-success HTTP response" do
      stub_request(:get, "https://api.example.com/info")
        .to_return(status: 404, body: "Not Found")

      expect {
        described_class.get("https://api.example.com/info", service_name: "Test")
      }.to raise_error(Web3::HttpClient::RequestError, /Test API returned 404/)
    end
  end

  describe Web3::HttpClient::Response do
    it "provides raw body access" do
      response = described_class.new('{"key": "value"}')
      expect(response.body).to eq('{"key": "value"}')
    end

    it "parses JSON lazily" do
      response = described_class.new('{"key": "value"}')
      expect(response.parsed_body).to eq({ "key" => "value" })
    end

    it "raises RequestError on invalid JSON" do
      response = described_class.new("not json")
      expect { response.parsed_body }.to raise_error(Web3::HttpClient::RequestError, /Invalid JSON/)
    end
  end
end
