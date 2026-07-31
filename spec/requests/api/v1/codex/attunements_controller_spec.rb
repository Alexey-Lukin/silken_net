# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Attunements", type: :request do
  let(:org)     { create(:organization) }
  let(:user)    { create(:user, organization: org) }
  let(:other)   { create(:user, organization: org) }
  let(:realm)   { create(:codex_realm) }
  let(:node)    { create(:codex_node, realm: realm) }
  let(:token)   { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }

  # ⚠️ HTML-гілка обох екшенів доти не мала жодного прикладу — усі йшли `as: :json`.
  # Саме тому 302 на `destroy` пережив: `fetch` конвертує 301/302 у GET лише для
  # POST, а DELETE зберігає, тож браузер перевидав би DELETE на сторінку вузла,
  # де такого маршруту немає — привʼязку знято, а користувач бачить помилку.
  describe "HTML branch (the Dashboard toggle)" do
    it "answers a successful un-attune with 303 See Other, not 302" do
      create(:codex_attunement, user: user, node: node)

      delete "/api/v1/codex/nodes/#{node.slug}/attunements/me",
             headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(api_v1_codex_node_path(node.slug))
      expect(Codex::Attunement.find_by(user_id: user.id, codex_node_id: node.id)).to be_nil
    end
  end

  describe "POST /api/v1/codex/nodes/:slug/attunements" do
    it "rejects unauthenticated requests" do
      post "/api/v1/codex/nodes/#{node.slug}/attunements", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a new attunement on first POST and increments the counter" do
      expect {
        post "/api/v1/codex/nodes/#{node.slug}/attunements",
             params: { attunement: { intensity: 4 } },
             headers: headers, as: :json
      }.to change { node.reload.attunement_count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "intensity")).to eq(4)
    end

    it "is idempotent: a second POST updates the row, never duplicates it" do
      post "/api/v1/codex/nodes/#{node.slug}/attunements",
           params: { attunement: { intensity: 2 } },
           headers: headers, as: :json
      expect(node.reload.attunement_count).to eq(1)

      expect {
        post "/api/v1/codex/nodes/#{node.slug}/attunements",
             params: { attunement: { intensity: 5, quote: "I tune deeper" } },
             headers: headers, as: :json
      }.not_to change(Codex::Attunement, :count)

      attunement = Codex::Attunement.find_by(user_id: user.id, codex_node_id: node.id)
      expect(attunement.intensity).to eq(5)
      expect(attunement.quote).to eq("I tune deeper")
    end

    it "rejects out-of-range intensity with 422" do
      post "/api/v1/codex/nodes/#{node.slug}/attunements",
           params: { attunement: { intensity: 99 } },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end

    it "404s on unknown slug" do
      post "/api/v1/codex/nodes/no-such-slug/attunements",
           params: { attunement: {} }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "defaults intensity to 3 when the client omits it" do
      post "/api/v1/codex/nodes/#{node.slug}/attunements",
           params: { attunement: {} }, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "intensity")).to eq(3)
    end
  end

  describe "DELETE /api/v1/codex/nodes/:slug/attunements/me" do
    it "removes the caller's attunement" do
      create(:codex_attunement, user: user, node: node)
      expect(node.reload.attunement_count).to eq(1)

      expect {
        delete "/api/v1/codex/nodes/#{node.slug}/attunements/me", headers: headers, as: :json
      }.to change { node.reload.attunement_count }.by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "is a safe no-op when there is no attunement to remove" do
      delete "/api/v1/codex/nodes/#{node.slug}/attunements/me", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it "never deletes another user's attunement" do
      foreign = create(:codex_attunement, user: other, node: node)
      delete "/api/v1/codex/nodes/#{node.slug}/attunements/me", headers: headers, as: :json
      expect(Codex::Attunement.exists?(foreign.id)).to be(true)
    end
  end

  describe "Phase 6 — Discovery probe wire-up on attune" do
    it "enqueues an attunement_streak probe — the action's only side effect beyond the row" do
      expect(Codex::DiscoveryProbeWorker).to receive(:perform_async).with(
        user.id, "attunement_streak",
        hash_including("codex_node_id" => node.id, "trigger_ref_type" => "Codex::Attunement")
      )
      post "/api/v1/codex/nodes/#{node.slug}/attunements",
           params: { attunement: { intensity: 4 } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end

    # `Codex::DiscoveryProbeWorker` is defined today; `defined?` gates a
    # forward-looking rollout (the worker existing at all is Phase 6-only).
    # `hide_const` proves the attune still succeeds if the worker were absent.
    it "still succeeds when Codex::DiscoveryProbeWorker is not defined" do
      hide_const("Codex::DiscoveryProbeWorker")
      post "/api/v1/codex/nodes/#{node.slug}/attunements",
           params: { attunement: { intensity: 4 } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end

    # Fail-open: a Sidekiq enqueue hiccup must never roll back the attune itself.
    it "still succeeds (fail-open) when the probe enqueue raises" do
      allow(Codex::DiscoveryProbeWorker).to receive(:perform_async).and_raise(StandardError, "redis down")
      post "/api/v1/codex/nodes/#{node.slug}/attunements",
           params: { attunement: { intensity: 4 } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(Codex::Attunement.exists?(user_id: user.id, codex_node_id: node.id)).to be(true)
    end
  end
end
