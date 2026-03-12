# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web3::HttpClient do
  let(:mock_session) { instance_double(HTTPX::Session) }
  let(:configured_session) { instance_double(HTTPX::Session) }

  before do
    Web3::HttpClient.reset! # rubocop:disable RSpec/DescribedClass
    allow(HTTPX).to receive(:plugin).with(:persistent).and_return(mock_session)
    allow(mock_session).to receive(:with).and_return(configured_session)
    allow(mock_session).to receive(:close)
  end

  after { Web3::HttpClient.reset! } # rubocop:disable RSpec/DescribedClass

  describe ".post" do
    it "sends a POST request with JSON body and returns Response" do
      response_body = instance_double(HTTPX::Response::Body, to_s: '{"result": "ok"}')
      success_response = instance_double(HTTPX::Response, status: 200, body: response_body)
      allow(success_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)

      allow(configured_session).to receive(:post)
        .with("https://api.example.com/data", body: { key: "value" }.to_json)
        .and_return(success_response)

      allow(mock_session).to receive(:with).with(
        timeout: { connect_timeout: 10, read_timeout: 30 },
        headers: { "content-type" => "application/json", "Authorization" => "Bearer token123" }
      ).and_return(configured_session)

      response = described_class.post("https://api.example.com/data",
        body: { key: "value" },
        headers: { "Authorization" => "Bearer token123" },
        service_name: "Test"
      )

      expect(response).to be_a(Web3::HttpClient::Response)
      expect(response.parsed_body).to eq({ "result" => "ok" })
    end

    it "raises RequestError on non-success HTTP response" do
      response_body = instance_double(HTTPX::Response::Body, to_s: "Internal Server Error")
      error_response = instance_double(HTTPX::Response, status: 500, body: response_body)
      allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)
      allow(configured_session).to receive(:post).and_return(error_response)

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Test"
        )
      }.to raise_error(Web3::HttpClient::RequestError, /Test API returned 500/)
    end

    it "raises RequestError on timeout" do
      timeout_error = HTTPX::TimeoutError.new(nil, "execution expired")
      error_response = instance_double(HTTPX::ErrorResponse, error: timeout_error)
      allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
      allow(configured_session).to receive(:post).and_return(error_response)

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Test"
        )
      }.to raise_error(Web3::HttpClient::RequestError, /Test.*Timeout/)
    end

    it "wraps connection errors in RequestError" do
      conn_error = HTTPX::ConnectionError.new("Connection refused")
      error_response = instance_double(HTTPX::ErrorResponse, error: conn_error)
      allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
      allow(configured_session).to receive(:post).and_return(error_response)

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Test"
        )
      }.to raise_error(Web3::HttpClient::RequestError, /Test connection error \(HTTPX::ConnectionError\)/)
    end
  end

  describe ".get" do
    it "sends a GET request and returns Response" do
      response_body = instance_double(HTTPX::Response::Body, to_s: '{"data": "test"}')
      success_response = instance_double(HTTPX::Response, status: 200, body: response_body)
      allow(success_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)

      allow(configured_session).to receive(:get)
        .with("https://api.example.com/info")
        .and_return(success_response)

      allow(mock_session).to receive(:with).with(
        timeout: { connect_timeout: 10, read_timeout: 30 },
        headers: { "Accept" => "application/json" }
      ).and_return(configured_session)

      response = described_class.get("https://api.example.com/info",
        headers: { "Accept" => "application/json" },
        service_name: "Test"
      )

      expect(response.parsed_body).to eq({ "data" => "test" })
    end

    it "raises RequestError on non-success HTTP response" do
      response_body = instance_double(HTTPX::Response::Body, to_s: "Not Found")
      error_response = instance_double(HTTPX::Response, status: 404, body: response_body)
      allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)
      allow(configured_session).to receive(:get).and_return(error_response)

      expect {
        described_class.get("https://api.example.com/info", service_name: "Test")
      }.to raise_error(Web3::HttpClient::RequestError, /Test API returned 404/)
    end
  end

  describe ".reset!" do
    it "clears the cached session" do
      # Trigger session creation
      response_body = instance_double(HTTPX::Response::Body, to_s: '{"ok": true}')
      success_response = instance_double(HTTPX::Response, status: 200, body: response_body)
      allow(success_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)
      allow(configured_session).to receive(:get).and_return(success_response)

      described_class.get("https://api.example.com/test")

      # Reset should close and clear the session
      expect(mock_session).to receive(:close)
      described_class.reset!

      expect(Thread.current[:web3_httpx_session]).to be_nil
    end
  end

  describe "persistent session reuse" do
    it "reuses the same HTTPX session across multiple calls" do
      response_body = instance_double(HTTPX::Response::Body, to_s: '{"ok": true}')
      success_response = instance_double(HTTPX::Response, status: 200, body: response_body)
      allow(success_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)
      allow(configured_session).to receive_messages(post: success_response, get: success_response)

      # HTTPX.plugin(:persistent) should be called only once
      expect(HTTPX).to receive(:plugin).with(:persistent).once.and_return(mock_session)

      described_class.post("https://api.example.com/first", body: { a: 1 })
      described_class.get("https://api.example.com/second")
      described_class.post("https://api.example.com/third", body: { b: 2 })
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
