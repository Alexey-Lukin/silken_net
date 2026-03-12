# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web3::HttpClient do
  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:start).and_yield(mock_http)
  end

  describe ".post" do
    it "sends a POST request with JSON body and returns Response" do
      success_response = instance_double(Net::HTTPSuccess, body: '{"result": "ok"}')
      allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

      allow(mock_http).to receive(:request) do |req|
        expect(req).to be_a(Net::HTTP::Post)
        expect(req.body).to eq({ key: "value" }.to_json)
        expect(req["Content-Type"]).to eq("application/json")
        expect(req["Authorization"]).to eq("Bearer token123")
        success_response
      end

      response = described_class.post("https://api.example.com/data",
        body: { key: "value" },
        headers: { "Authorization" => "Bearer token123" },
        service_name: "Test"
      )

      expect(response).to be_a(Web3::HttpClient::Response)
      expect(response.parsed_body).to eq({ "result" => "ok" })
    end

    it "raises RequestError on non-success HTTP response" do
      error_response = instance_double(Net::HTTPInternalServerError, code: "500", body: "Internal Server Error")
      allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(mock_http).to receive(:request).and_return(error_response)

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Test"
        )
      }.to raise_error(Web3::HttpClient::RequestError, /Test API returned 500/)
    end

    it "raises RequestError on timeout" do
      allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout.new("execution expired"))

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
      success_response = instance_double(Net::HTTPSuccess, body: '{"data": "test"}')
      allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

      allow(mock_http).to receive(:request) do |req|
        expect(req).to be_a(Net::HTTP::Get)
        expect(req["Accept"]).to eq("application/json")
        success_response
      end

      response = described_class.get("https://api.example.com/info",
        headers: { "Accept" => "application/json" },
        service_name: "Test"
      )

      expect(response.parsed_body).to eq({ "data" => "test" })
    end

    it "raises RequestError on non-success HTTP response" do
      error_response = instance_double(Net::HTTPNotFound, code: "404", body: "Not Found")
      allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(mock_http).to receive(:request).and_return(error_response)

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
