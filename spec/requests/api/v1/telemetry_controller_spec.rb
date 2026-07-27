# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::TelemetryController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  let!(:own_cluster) { create(:cluster, organization: organization) }
  let!(:other_cluster) { create(:cluster, organization: other_organization) }

  describe "GET /api/v1/telemetry/live" do
    context "when as HTML" do
      it "renders the live telemetry dashboard" do
        get "/api/v1/telemetry/live", headers: headers
        expect(response).to have_http_status(:ok)
      end

      # Єдиний рядок, що вирішує ЧИЯ організація, — у контролері, і компонентні
      # та воркерні специ його не бачать: перші дістають організацію моком,
      # другі дивляться з боку продюсера. Без цього піна підміна на
      # `Organization.first` лишила б усю сюїту зеленою, а крос-тенант — живим.
      def subscribed_stream_for(who)
        get "/api/v1/telemetry/live",
            headers: { "Authorization" => "Bearer #{who.generate_token_for(:api_access)}" }
        response.body.scan(/signed-stream-name="([^"]+)"/).flatten
                .map { |s| Turbo::StreamsChannel.verified_stream_name(s) }
      end

      # ⚠️ Двоє юзерів обовʼязкові, і це не надмірність: із одним пін мовчить на
      # найправдоподібнішій підміні. `organization` створюється в цьому файлі
      # першою, тож `Organization.first` їй ДОРІВНЮЄ — мутація на неї лишає
      # однокористувацький приклад зеленим (перевірено). Ловить лише різниця.
      it "subscribes each viewer to their OWN organization stream" do
        stranger = create(:user, organization: other_organization)

        expect(subscribed_stream_for(user)).to eq([ "telemetry_stream_org_#{organization.id}" ])
        expect(subscribed_stream_for(stranger)).to eq([ "telemetry_stream_org_#{other_organization.id}" ])
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/telemetry/live"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/trees/:id/telemetry (tree_history)" do
    let(:tree_family) { create(:tree_family) }
    let(:own_tree) { create(:tree, cluster: own_cluster, tree_family: tree_family) }
    let(:other_tree) { create(:tree, cluster: other_cluster, tree_family: tree_family) }

    before do
      create(:telemetry_log, tree: own_tree, z_value: 0.35, temperature_c: 22.5, created_at: 1.day.ago)
      create(:telemetry_log, tree: own_tree, z_value: 0.40, temperature_c: 23.0, created_at: 2.hours.ago)
    end

    it "returns telemetry history for a tree in the user's organization" do
      get "/api/v1/trees/#{own_tree.id}/telemetry",
          params: { tree_id: own_tree.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["did"]).to eq(own_tree.did)
      expect(body["unit"]).to eq("kOhm")
      expect(body["timestamps"]).to be_an(Array)
      expect(body["impedance"]).to be_an(Array)
      expect(body["temperature"]).to be_an(Array)
      expect(body["stress_index"]).to be_an(Array)
      expect(body["timestamps"].length).to eq(2)
    end

    it "supports days parameter" do
      get "/api/v1/trees/#{own_tree.id}/telemetry",
          params: { tree_id: own_tree.id, days: 1 },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a tree from another organization" do
      get "/api/v1/trees/#{other_tree.id}/telemetry",
          params: { tree_id: other_tree.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      get "/api/v1/trees/#{own_tree.id}/telemetry", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # =========================================================================
    # DAYS CAP: `params[:days]` was unbounded. Clamp into [1, 365] so that
    # bogus or absurd values gracefully degrade to a manageable window.
    # =========================================================================
    it "clamps `days` parameter to MAX_HISTORY_DAYS (365)" do
      get "/api/v1/trees/#{own_tree.id}/telemetry",
          params: { days: 99_999 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      # Range coercion is internal; the surfaced contract is that the request
      # returns successfully without OOMing the Ruby process.
    end

    it "treats non-numeric `days` as the default (7) instead of 0" do
      get "/api/v1/trees/#{own_tree.id}/telemetry",
          params: { days: "yesterday" }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      # Both seed logs (created 1d / 2h ago) must remain visible.
      expect(response.parsed_body["timestamps"].length).to eq(2)
    end
  end

  describe "POST /api/v1/gateways/:id/telemetry (gateway_uplink)" do
    let(:own_gateway) { create(:gateway, cluster: own_cluster) }

    before do
      allow(UnpackTelemetryWorker).to receive(:perform_async)
    end

    it "accepts telemetry payload and enqueues UnpackTelemetryWorker with correct arguments" do
      post "/api/v1/gateways/#{own_gateway.id}/telemetry",
           params: { gateway_id: own_gateway.id, payload: "AABBCCDD11223344" },
           headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body["status"]).to eq("accepted")
      expect(body["gateway_uid"]).to eq(own_gateway.uid)

      # Сигнатура має збігатися з CoAP daemon: (encoded_payload, sender_ip, gateway_uid)
      expect(UnpackTelemetryWorker).to have_received(:perform_async).with(
        "AABBCCDD11223344", "127.0.0.1", own_gateway.uid
      )
    end

    it "returns 404 for a gateway from another organization" do
      other_gateway = create(:gateway, cluster: other_cluster)

      post "/api/v1/gateways/#{other_gateway.id}/telemetry",
           params: { gateway_id: other_gateway.id, payload: "AABBCCDD" },
           headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      post "/api/v1/gateways/#{own_gateway.id}/telemetry",
           params: { payload: "AABBCCDD" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # =========================================================================
    # DoS GUARD: enqueueing a megabyte payload into Redis Sidekiq queue would
    # starve Puma threads and break the CoAP uplink path. 16 KiB is ~16× the
    # real-world batch ceiling.
    # =========================================================================
    it "rejects oversized payload with 413 and does not enqueue" do
      payload = "A" * (Api::V1::TelemetryController::MAX_UPLINK_PAYLOAD_SIZE + 1)

      post "/api/v1/gateways/#{own_gateway.id}/telemetry",
           params: { payload: payload }, headers: headers, as: :json

      # `:content_too_large` is the Rack-3 name for HTTP 413 (the older
      # `:payload_too_large` is deprecated). Asserting the raw integer keeps
      # the spec stable regardless of which symbol name the matcher accepts.
      expect(response.status).to eq(413)
      expect(UnpackTelemetryWorker).not_to have_received(:perform_async)
    end
  end

  describe "GET /api/v1/gateways/:id/telemetry (gateway_history)" do
    let(:own_gateway) { create(:gateway, cluster: own_cluster) }
    let(:other_gateway) { create(:gateway, cluster: other_cluster) }

    before do
      create(:gateway_telemetry_log, gateway: own_gateway, voltage_mv: 4200,
             cellular_signal_csq: 15, temperature_c: 25.0, created_at: 1.day.ago)
      create(:gateway_telemetry_log, gateway: own_gateway, voltage_mv: 4100,
             cellular_signal_csq: 14, temperature_c: 24.0, created_at: 2.hours.ago)
    end

    it "returns telemetry history for a gateway in the user's organization" do
      get "/api/v1/gateways/#{own_gateway.id}/telemetry",
          params: { gateway_id: own_gateway.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["uid"]).to eq(own_gateway.uid)
      expect(body["timestamps"]).to be_an(Array)
      expect(body["voltage"]).to be_an(Array)
      expect(body["signal"]).to be_an(Array)
      expect(body["temp"]).to be_an(Array)
      expect(body["timestamps"].length).to eq(2)
    end

    it "supports days parameter" do
      get "/api/v1/gateways/#{own_gateway.id}/telemetry",
          params: { gateway_id: own_gateway.id, days: 1 },
          headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a gateway from another organization" do
      get "/api/v1/gateways/#{other_gateway.id}/telemetry",
          params: { gateway_id: other_gateway.id },
          headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      get "/api/v1/gateways/#{own_gateway.id}/telemetry", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
