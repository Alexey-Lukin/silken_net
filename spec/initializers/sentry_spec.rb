# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sentry do
  let(:config) { described_class.configuration }

  describe "core settings" do
    it "sets environment from Rails.env" do
      expect(config.environment).to eq("test")
    end

    it "disables PII transmission" do
      expect(config.send_default_pii).to be(false)
    end

    it "configures background worker threads for async delivery" do
      expect(config.background_worker_threads).to eq(2)
    end

    it "limits breadcrumbs to prevent oversized payloads" do
      expect(config.max_breadcrumbs).to eq(30)
    end
  end

  describe "performance sampling" do
    it "configures a low traces_sample_rate for cost control" do
      expect(config.traces_sample_rate).to be <= 0.01
    end
  end

  describe "excluded exceptions" do
    let(:excluded) { config.excluded_exceptions }

    it "excludes standard Rails noise" do
      expect(excluded).to include(
        "ActiveRecord::RecordNotFound",
        "ActionController::RoutingError",
        "ActionController::BadRequest"
      )
    end

    it "excludes CoAP IoT transient errors" do
      expect(excluded).to include(
        "CoapClient::Error",
        "CoapClient::ClientError",
        "CoapClient::ServerError",
        "CoapClient::NetworkError"
      )
    end

    it "excludes Web3 transient errors" do
      expect(excluded).to include(
        "Web3::HttpClient::RequestError",
        "HTTPX::TimeoutError",
        "HTTPX::ConnectionError"
      )
    end

    it "excludes Sidekiq rate limiting errors" do
      expect(excluded).to include("Sidekiq::Limiter::OverLimit")
    end

    it "excludes domain-specific handled errors" do
      expect(excluded).to include(
        "HardwareKeyService::RotationPendingError",
        "BioContractFirmware::IntegrityError",
        "Polygon::HadronComplianceService::ComplianceError"
      )
    end
  end

  describe "before_send callback" do
    it "scrubs sensitive fields from event extra context" do
      event = Sentry::Event.new(configuration: config)
      event.extra = { aes_key: "supersecret", normal_field: "visible" }
      hint = {}

      filtered = config.before_send.call(event, hint)

      expect(filtered.extra[:aes_key]).to eq("[FILTERED]")
      expect(filtered.extra[:normal_field]).to eq("visible")
    end

    it "scrubs wallet_private_key from extra context" do
      event = Sentry::Event.new(configuration: config)
      event.extra = { wallet_private_key: "0xDEAD", mnemonic: "word list" }
      hint = {}

      filtered = config.before_send.call(event, hint)

      expect(filtered.extra[:wallet_private_key]).to eq("[FILTERED]")
      expect(filtered.extra[:mnemonic]).to eq("[FILTERED]")
    end

    it "passes through events without sensitive fields unchanged" do
      event = Sentry::Event.new(configuration: config)
      event.extra = { gateway_uid: "SNET-Q-001", status: "ok" }
      hint = {}

      filtered = config.before_send.call(event, hint)

      expect(filtered.extra[:gateway_uid]).to eq("SNET-Q-001")
      expect(filtered.extra[:status]).to eq("ok")
    end
  end
end
