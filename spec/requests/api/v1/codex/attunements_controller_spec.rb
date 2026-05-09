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
        .and change(Codex::AttunementBroadcastWorker.jobs, :size).by(1)

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
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end

    it "404s on unknown slug" do
      post "/api/v1/codex/nodes/no-such-slug/attunements",
           params: { attunement: {} }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/codex/nodes/:slug/attunements/me" do
    it "removes the caller's attunement and broadcasts" do
      create(:codex_attunement, user: user, node: node)
      expect(node.reload.attunement_count).to eq(1)

      expect {
        delete "/api/v1/codex/nodes/#{node.slug}/attunements/me", headers: headers, as: :json
      }.to change { node.reload.attunement_count }.by(-1)
        .and change(Codex::AttunementBroadcastWorker.jobs, :size).by(1)
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
    it "enqueues an attunement_streak probe alongside the broadcast" do
      expect(Codex::DiscoveryProbeWorker).to receive(:perform_async).with(
        user.id, "attunement_streak",
        hash_including("codex_node_id" => node.id, "trigger_ref_type" => "Codex::Attunement")
      )
      post "/api/v1/codex/nodes/#{node.slug}/attunements",
           params: { attunement: { intensity: 4 } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end
  end
end
