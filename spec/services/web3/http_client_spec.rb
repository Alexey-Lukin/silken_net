# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web3::HttpClient do
  let(:mock_session) { instance_double(HTTPX::Session) }
  let(:configured_session) { instance_double(HTTPX::Session) }

  before do
    Web3::HttpClient.reset! # rubocop:disable RSpec/DescribedClass
    Web3::HttpClient.reset_circuit_breakers! # rubocop:disable RSpec/DescribedClass
    allow(HTTPX).to receive(:plugin).with(:persistent).and_return(mock_session)
    allow(mock_session).to receive(:with).and_return(configured_session)
    allow(mock_session).to receive(:close)
  end

  after do
    Web3::HttpClient.reset! # rubocop:disable RSpec/DescribedClass
    Web3::HttpClient.reset_circuit_breakers! # rubocop:disable RSpec/DescribedClass
  end

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

    it "wraps unexpected StandardError in RequestError" do
      response_body = instance_double(HTTPX::Response::Body)
      allow(response_body).to receive(:to_s).and_raise(Encoding::UndefinedConversionError, "binary to UTF-8")
      success_response = instance_double(HTTPX::Response, status: 200, body: response_body)
      allow(success_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)
      allow(configured_session).to receive(:post).and_return(success_response)

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Filecoin"
        )
      }.to raise_error(Web3::HttpClient::RequestError, /Filecoin connection error: binary to UTF-8/)
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
      described_class.reset!

      expect(mock_session).to have_received(:close)
      expect(Thread.current[:web3_httpx_session]).to be_nil
    end
  end

  describe "persistent session reuse" do
    it "reuses the same HTTPX session across multiple calls" do
      response_body = instance_double(HTTPX::Response::Body, to_s: '{"ok": true}')
      success_response = instance_double(HTTPX::Response, status: 200, body: response_body)
      allow(success_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)
      allow(configured_session).to receive_messages(post: success_response, get: success_response)

      described_class.post("https://api.example.com/first", body: { a: 1 })
      described_class.get("https://api.example.com/second")
      described_class.post("https://api.example.com/third", body: { b: 2 })

      # HTTPX.plugin(:persistent) should be called only once
      expect(HTTPX).to have_received(:plugin).with(:persistent).once
    end
  end

  describe "circuit breaker (S6.4)" do
    let(:timeout_error) { HTTPX::TimeoutError.new(nil, "execution expired") }
    let(:error_response) { instance_double(HTTPX::ErrorResponse, error: timeout_error) }

    before do
      allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
    end

    def make_failing_post(service_name: "Filecoin")
      described_class.post("https://api.example.com/data",
        body: { key: "value" },
        service_name: service_name
      )
    rescue Web3::HttpClient::CircuitOpenError
      raise # re-raise CircuitOpenError so tests can assert on it
    rescue Web3::HttpClient::RequestError
      # expected — swallow non-circuit errors (timeouts, connection failures)
    end

    def make_successful_post(service_name: "Filecoin")
      response_body = instance_double(HTTPX::Response::Body, to_s: '{"ok": true}')
      success_response = instance_double(HTTPX::Response, status: 200, body: response_body)
      allow(success_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(false)
      allow(configured_session).to receive(:post).and_return(success_response)

      described_class.post("https://api.example.com/data",
        body: { key: "value" },
        service_name: service_name
      )
    end

    it "opens circuit after MAX_FAILURES consecutive failures" do
      allow(configured_session).to receive(:post).and_return(error_response)

      Web3::HttpClient::MAX_FAILURES.times { make_failing_post }

      expect {
        make_failing_post
      }.to raise_error(Web3::HttpClient::CircuitOpenError, /circuit breaker is open/)
    end

    it "resets failure count on success" do
      allow(configured_session).to receive(:post).and_return(error_response)
      2.times { make_failing_post }

      make_successful_post

      status = Web3::HttpClient.circuit_status("Filecoin") # rubocop:disable RSpec/DescribedClass
      expect(status[:failures]).to eq(0)
      expect(status[:circuit_open]).to be false
    end

    it "does not affect other services" do
      allow(configured_session).to receive(:post).and_return(error_response)

      Web3::HttpClient::MAX_FAILURES.times { make_failing_post(service_name: "Streamr") }

      # Filecoin should still work
      expect {
        make_successful_post(service_name: "Filecoin")
      }.not_to raise_error
    end

    it "reopens circuit after CIRCUIT_OPEN_DURATION" do
      allow(configured_session).to receive(:post).and_return(error_response)

      Web3::HttpClient::MAX_FAILURES.times { make_failing_post }

      # Simulate time passing beyond circuit open duration
      allow(Time).to receive(:current).and_return(Time.current + Web3::HttpClient::CIRCUIT_OPEN_DURATION + 1)

      status = Web3::HttpClient.circuit_status("Filecoin") # rubocop:disable RSpec/DescribedClass
      expect(status[:available]).to be true
    end

    # 🔴 [ARCH.84] Дзеркало дефекту з `Web3::ResilientClient`, і саме тут воно
    # найгостріше: коментар методу дослівно каже «для моніторингу / Prometheus»,
    # а метод при вичерпаному cooldown видаляв `@failure_counts` і
    # `@circuit_opened_at` — тобто ЗВІТ напів-відкривав справжній breaker.
    # ⚠️ Нога трекера називала лише `ResilientClient`; сайтів було ДВА.
    # 🔴 Перехід open → half-open доти НЕ мав власного носія: єдиним, що його
    # виконувало в сюїті, був виклик із МОНІТОРИНГУ — тобто рівно той дефект,
    # який [ARCH.84] і лікує. Щойно звіт перевели на чистий предикат, гілка
    # переходу лишилась без жодного тесту, і це показало покриття, не око.
    # **Урок: коли прибираєш побічний ефект із читача, спитай, чи не БУВ той
    # ефект єдиним виконавцем механізму — інакше фікс лишає механізм без сітки.**
    it "ДИСПЕТЧЕР (не звіт) виконує перехід half-open після cooldown" do
      allow(configured_session).to receive(:post).and_return(error_response)
      Web3::HttpClient::MAX_FAILURES.times { make_failing_post }
      expect { make_failing_post }.to raise_error(Web3::HttpClient::CircuitOpenError)

      allow(Time).to receive(:current).and_return(Time.current + Web3::HttpClient::CIRCUIT_OPEN_DURATION + 1)

      # Запит проходить (breaker напів-відкрився) — і саме ЦЕЙ шлях мутує стан.
      # `make_successful_post` сам перестаблює сесію на успіх.
      expect { make_successful_post }.not_to raise_error
      expect(Web3::HttpClient.circuit_status("Filecoin")[:failures]).to eq(0) # rubocop:disable RSpec/DescribedClass
    end

    it "circuit_status НЕ мутує breaker при вичерпаному cooldown" do
      allow(configured_session).to receive(:post).and_return(error_response)
      Web3::HttpClient::MAX_FAILURES.times { make_failing_post }
      allow(Time).to receive(:current).and_return(Time.current + Web3::HttpClient::CIRCUIT_OPEN_DURATION + 1)

      first  = Web3::HttpClient.circuit_status("Filecoin") # rubocop:disable RSpec/DescribedClass
      second = Web3::HttpClient.circuit_status("Filecoin") # rubocop:disable RSpec/DescribedClass

      # Вердикт чесний (cooldown минув), але СТАН не зрушив: якби звіт мутував,
      # друге читання побачило б уже обнулений лічильник.
      expect(first[:available]).to be true
      expect(first[:circuit_open]).to be true
      expect(first[:failures]).to eq(Web3::HttpClient::MAX_FAILURES)
      expect(second).to eq(first)
    end

    it "is case-insensitive for service names" do
      allow(configured_session).to receive(:post).and_return(error_response)

      Web3::HttpClient::MAX_FAILURES.times { make_failing_post(service_name: "FILECOIN") }

      expect {
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "filecoin"
        )
      }.to raise_error(Web3::HttpClient::CircuitOpenError)
    end

    it "reports circuit status via circuit_status" do
      status = Web3::HttpClient.circuit_status("Filecoin") # rubocop:disable RSpec/DescribedClass
      expect(status).to include(
        service: "Filecoin",
        failures: 0,
        circuit_open: false,
        available: true
      )
    end

    it "blocks GET requests when circuit is open" do
      allow(configured_session).to receive(:post).and_return(error_response)

      Web3::HttpClient::MAX_FAILURES.times { make_failing_post(service_name: "TheGraph") }

      expect {
        described_class.get("https://api.example.com/query", service_name: "TheGraph")
      }.to raise_error(Web3::HttpClient::CircuitOpenError)
    end
  end

  describe ".reset_circuit_breakers!" do
    it "clears all circuit breaker state" do
      timeout_error = HTTPX::TimeoutError.new(nil, "expired")
      error_response = instance_double(HTTPX::ErrorResponse, error: timeout_error)
      allow(error_response).to receive(:is_a?).with(HTTPX::ErrorResponse).and_return(true)
      allow(configured_session).to receive(:post).and_return(error_response)

      Web3::HttpClient::MAX_FAILURES.times do
        described_class.post("https://api.example.com/data",
          body: { key: "value" },
          service_name: "Streamr"
        )
      rescue Web3::HttpClient::RequestError
        # expected
      end

      described_class.reset_circuit_breakers!

      status = Web3::HttpClient.circuit_status("Streamr") # rubocop:disable RSpec/DescribedClass
      expect(status[:failures]).to eq(0)
      expect(status[:available]).to be true
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
