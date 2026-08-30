# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sentry do
  let(:config) { described_class.configuration }

  describe "core settings" do
    # [INF.27] Was "sets environment from Rails.env" — a name that became a lie the day the
    # slot axis landed, while the assertion stayed green (both resolve to "test" here). The
    # value below is the FALLBACK half; that the initializer actually reads the slot One-Home
    # is judged where it can be judged — spec/deploy/deployment_slot_axis_spec.rb, cross-file.
    it "reports the deployment slot, falling back to Rails.env when undeclared" do
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

    it "scrubs a labelled secret value leaked into event.message" do
      event = Sentry::Event.new(configuration: config)
      event.message = "decrypt failed aes_key=2b7e151628aed2a6abf7158809cf4f3c retrying"
      hint = {}

      filtered = config.before_send.call(event, hint)

      expect(filtered.message).to include("aes_key=[FILTERED]")
      expect(filtered.message).not_to include("2b7e151628aed2a6")
    end

    it "leaves public hashes / non-secret message text intact" do
      event = Sentry::Event.new(configuration: config)
      event.message = "tx 0xabc123def reverted on Polygon"
      hint = {}

      filtered = config.before_send.call(event, hint)

      expect(filtered.message).to eq("tx 0xabc123def reverted on Polygon")
    end

    it "redacts an access_token= value leaked into event.message" do
      event = Sentry::Event.new(configuration: config)
      event.message = "oauth refresh failed access_token=ya29.SECRETVALUE123 retrying"

      filtered = config.before_send.call(event, {})

      expect(filtered.message).to include("access_token=[FILTERED]")
      expect(filtered.message).not_to include("ya29.SECRETVALUE123")
    end

    it "redacts a Bearer token leaked into event.message" do
      event = Sentry::Event.new(configuration: config)
      event.message = "rpc 401 Authorization: Bearer eyJhbGciOiJIUzI1.payloadpart.sigpart denied"

      filtered = config.before_send.call(event, {})

      expect(filtered.message).to include("Bearer [FILTERED]")
      expect(filtered.message).not_to include("eyJhbGciOiJIUzI1")
    end

    it "redacts a user-less inline URL credential (redis://:pw@host)" do
      event = Sentry::Event.new(configuration: config)
      event.message = "redis down: redis://:supersecretpw@cache.internal:6379"

      filtered = config.before_send.call(event, {})

      expect(filtered.message).to include("://:[FILTERED]@")
      expect(filtered.message).not_to include("supersecretpw")
    end

    it "recursively redacts nested breadcrumb data" do
      event = Sentry::Event.new(configuration: config)
      buffer = Sentry::BreadcrumbBuffer.new
      buffer.record(
        Sentry::Breadcrumb.new(
          category: "http",
          message: "GET https://user:pw12345678@rpc.host/path",
          data: { "response" => { "body" => "signing_key=deadbeefcafe1234" } }
        )
      )
      event.breadcrumbs = buffer

      filtered = config.before_send.call(event, {})
      crumb = filtered.breadcrumbs.to_a.last

      expect(crumb.message).to include("://user:[FILTERED]@")
      expect(crumb.data.dig("response", "body")).to include("signing_key=[FILTERED]")
      expect(crumb.data.dig("response", "body")).not_to include("deadbeefcafe1234")
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
