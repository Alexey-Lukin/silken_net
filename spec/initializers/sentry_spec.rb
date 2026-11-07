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

  # [OPS.22, ⚖️ founder 2026-09-05] 7.0 made logs default-on (metrics since 6.3.0) and removed
  # both flags, so the ratified "declared off" posture is three initializer lines — and deleting
  # them would change what reaches a named subprocessor without reddening anything else.
  describe "data categories beyond errors and traces" do
    it "stops Rails structured logging at its source" do
      expect(config.rails.structured_logging.enabled).to be(false)
    end

    it "drops log items from any emitter" do
      expect(config.before_send_log.call(Object.new)).to be_nil
    end

    it "drops metric items from any emitter" do
      expect(config.before_send_metric.call(Object.new)).to be_nil
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

    # [SEC.23, ⚖️ founder 2026-11-07] `send_default_pii = false` alone still let these through on
    # 7.0.0 and 7.2.0 (measured) — each pin below goes red if its line in the initializer goes.
    it "drops Sidekiq job arguments from an error event, keeping class and jid" do
      event = Sentry::Event.new(configuration: config)
      event.contexts = { sidekiq: { "class" => "AlertMailerJob", "jid" => "abc123",
                                    "args" => [ "subject@example.com", { "first_name" => "Olena" } ] } }

      filtered = config.before_send.call(event, {})

      expect(filtered.contexts[:sidekiq]["args"]).to eq("[Filtered]")
      expect(filtered.contexts[:sidekiq]).to include("class" => "AlertMailerJob", "jid" => "abc123")
    end
  end

  describe "SEC.23 — subject data that send_default_pii = false does not stop" do
    it "filters User-Agent, Referer and Accept-Language from request headers" do
      headers = { "User-Agent" => "Mozilla/5.0 (iPhone)", "Referer" => "https://x.test/trees/7",
                  "Accept-Language" => "uk-UA", "Accept" => "text/html" }

      kept = config.data_collection.http_headers.request.filter(headers)

      expect(kept.values.join(" ")).not_to include("iPhone", "trees/7", "uk-UA")
      expect(kept["Accept"]).to eq("text/html")
    end

    it "keeps SQL text out of sql.active_record breadcrumbs" do
      expect(config.rails.active_support_logger_subscription_items["sql.active_record"]).not_to include(:sql)
    end

    it "scrubs job arguments and SQL literals from a transaction, which bypasses before_send" do
      event = Struct.new(:contexts, :spans).new(
        { sidekiq: { "class" => "MintJob", "args" => [ "0xWallet" ] } },
        [ { op: "db.sql.active_record", description: "SELECT * FROM users WHERE email = 'a@b.test' AND id = $1" },
          { op: "http.client", description: "GET https://rpc.test/'quoted'" } ]
      )

      out = config.before_send_transaction.call(event, {})

      expect(out.contexts[:sidekiq]["args"]).to eq("[Filtered]")
      expect(out.spans[0][:description]).to eq("SELECT * FROM users WHERE email = '?' AND id = $1")
      expect(out.spans[1][:description]).to include("'quoted'")
    end
  end

  describe "before_send callback, continued" do
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
