# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.34 L3] Helium SOS webhook — auth-клон oracle_callbacks-патерну:
# публічний POST + HMAC-SHA256(raw_body) у X-Helium-Signature +
# WEB3_STRICT_MODE fail-fast. Тонкий контролер: валідне → 202 + enqueue.
RSpec.describe "POST /telemetry/helium", type: :request do
  let(:secret)  { "helium-shared-secret" }
  let(:body)    { { dev_eui: "AABBCCDDEEFF0011", payload: Base64.strict_encode64("x" * 12) } }
  let(:raw)     { body.to_json }
  let(:sig)     { OpenSSL::HMAC.hexdigest("SHA256", secret, raw) }
  let(:headers) { { "CONTENT_TYPE" => "application/json", "X-Helium-Signature" => sig } }

  around do |example|
    Sidekiq::Testing.fake! { example.run }
  end

  before { HeliumSosWorker.clear }

  context "with HELIUM_WEBHOOK_SECRET set" do
    around do |example|
      old = ENV["HELIUM_WEBHOOK_SECRET"]
      ENV["HELIUM_WEBHOOK_SECRET"] = secret
      example.run
    ensure
      ENV["HELIUM_WEBHOOK_SECRET"] = old
    end

    it "accepts a valid HMAC-signed SOS and enqueues the worker" do
      post "/api/v1/telemetry/helium", params: raw, headers: headers

      expect(response).to have_http_status(:accepted)
      expect(HeliumSosWorker.jobs.size).to eq(1)
      args = HeliumSosWorker.jobs.last["args"]
      expect(args[0]).to eq("AABBCCDDEEFF0011")
      expect(args[1]).to eq(body[:payload])
    end

    it "accepts the Console camelCase devEUI key" do
      camel = { devEUI: "AABBCCDDEEFF0011", payload: body[:payload] }.to_json
      camel_sig = OpenSSL::HMAC.hexdigest("SHA256", secret, camel)

      post "/api/v1/telemetry/helium", params: camel,
           headers: headers.merge("X-Helium-Signature" => camel_sig)

      expect(response).to have_http_status(:accepted)
      expect(HeliumSosWorker.jobs.size).to eq(1)
    end

    # [INF.26] Контролерні відмови ЛІЧАТЬСЯ (rejected_auth / rejected_params):
    # доти ротація HELIUM_WEBHOOK_SECRET без синхронізації Console глушила
    # SOS-канал невідрізнимо від «жодна Королева не кричить». Піни нижче
    # цілять у ДЕЛЬТУ лічильника — зняття інкременту дає by(0) → RED.
    it "rejects a missing signature header and counts it as rejected_auth" do
      expect {
        post "/api/v1/telemetry/helium", params: raw,
             headers: { "CONTENT_TYPE" => "application/json" }
      }.to change {
        SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL.get(labels: { outcome: "rejected_auth" })
      }.by(1)

      expect(response).to have_http_status(:unauthorized)
      expect(HeliumSosWorker.jobs).to be_empty
    end

    it "rejects an invalid signature and counts it as rejected_auth" do
      expect {
        post "/api/v1/telemetry/helium", params: raw,
             headers: headers.merge("X-Helium-Signature" => "0" * 64)
      }.to change {
        SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL.get(labels: { outcome: "rejected_auth" })
      }.by(1)

      expect(response).to have_http_status(:unauthorized)
      expect(HeliumSosWorker.jobs).to be_empty
    end

    it "rejects a body without dev_eui/payload (після валідного HMAC) and counts it as rejected_params" do
      empty = {}.to_json
      empty_sig = OpenSSL::HMAC.hexdigest("SHA256", secret, empty)

      expect {
        post "/api/v1/telemetry/helium", params: empty,
             headers: headers.merge("X-Helium-Signature" => empty_sig)
      }.to change {
        SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL.get(labels: { outcome: "rejected_params" })
      }.by(1)

      expect(response).to have_http_status(:unprocessable_content)
      expect(HeliumSosWorker.jobs).to be_empty
    end
  end

  context "without HELIUM_WEBHOOK_SECRET" do
    around do |example|
      old_secret = ENV["HELIUM_WEBHOOK_SECRET"]
      old_strict = ENV["WEB3_STRICT_MODE"]
      ENV["HELIUM_WEBHOOK_SECRET"] = nil
      example.run
    ensure
      ENV["HELIUM_WEBHOOK_SECRET"] = old_secret
      ENV["WEB3_STRICT_MODE"] = old_strict
    end

    # Назва обіцяє ДВІ речі — «проходить» І «з попередженням», — а пін міряв лише
    # першу: 202 лишався б і при мовчазному пропуску без сліду, тобто найтихішій
    # формі цього дефекту (гілка bypass є, а сліду про неї немає).
    it "passes with a warning in dev/test (без підпису)" do
      ENV["WEB3_STRICT_MODE"] = nil
      allow(Rails.logger).to receive(:warn)

      post "/api/v1/telemetry/helium", params: raw,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:accepted)
      expect(Rails.logger).to have_received(:warn).with(/HELIUM_WEBHOOK_SECRET/)
    end

    it "fail-fast у WEB3_STRICT_MODE (endpoint без HMAC не живе в prod)" do
      ENV["WEB3_STRICT_MODE"] = "true"

      expect {
        post "/api/v1/telemetry/helium", params: raw,
             headers: { "CONTENT_TYPE" => "application/json" }
      }.to raise_error(SecurityError, /HELIUM_WEBHOOK_SECRET/)
    end
  end
end
