# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Fractions", type: :request do
  let(:org)   { create(:organization) }
  let(:user)  { create(:user, organization: org) }
  let(:realm) { create(:codex_realm) }
  let(:node)  { create(:codex_node, realm: realm, lifecycle_status: :thriving, archetype_key: "nlos_routing") }
  let(:other_node) { create(:codex_node, realm: realm, lifecycle_status: :thriving, archetype_key: "mesh_sharding") }
  let(:token)   { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }

  before { Sidekiq::Worker.clear_all }

  describe "POST /api/v1/codex/fractions" do
    it "rejects unauthenticated requests" do
      post "/api/v1/codex/fractions",
           params: { fraction: { node_slug: node.slug } }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a new fraction on first POST and enqueues audit" do
      expect {
        post "/api/v1/codex/fractions",
             params: { fraction: { node_slug: node.slug } },
             headers: headers, as: :json
      }.to change(Codex::Fraction, :count).by(1)
        .and change(Codex::FractionAuditWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["archetype_key"]).to eq("nlos_routing")
      expect(data["node_slug"]).to eq(node.slug)
      expect(data["cooldown_active"]).to be(true)
    end

    it "returns 429 with cooldown_until when re-pick is within 7 days" do
      Codex::FractionChangeService.call(user: user, node: node)

      post "/api/v1/codex/fractions",
           params: { fraction: { node_slug: other_node.slug } },
           headers: headers, as: :json

      expect(response).to have_http_status(:too_many_requests)
      body = response.parsed_body
      expect(body["error"]).to eq("cooldown_active")
      expect(body["cooldown_until"]).to be_present
    end

    it "404s on unknown slug" do
      post "/api/v1/codex/fractions",
           params: { fraction: { node_slug: "does-not-exist" } },
           headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "422s when picking an extinct node" do
      dead = create(:codex_node, realm: realm, lifecycle_status: :extinct)
      post "/api/v1/codex/fractions",
           params: { fraction: { node_slug: dead.slug } },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects with notice on HTML format success" do
      post "/api/v1/codex/fractions",
           params: { fraction: { node_slug: node.slug } },
           headers: { "Authorization" => "Bearer #{token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to("/api/v1/codex/nodes/#{node.slug}")
      expect(flash[:notice]).to include("Fraction set")
    end

    it "redirects with alert on HTML format cooldown" do
      Codex::FractionChangeService.call(user: user, node: node)

      post "/api/v1/codex/fractions",
           params: { fraction: { node_slug: other_node.slug } },
           headers: { "Authorization" => "Bearer #{token}", "Accept" => "text/html" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("cooldown active")
    end
  end

  describe "GET /api/v1/codex/fractions/me" do
    it "rejects unauthenticated requests" do
      get "/api/v1/codex/fractions/me", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 204 when the user has no fraction yet" do
      get "/api/v1/codex/fractions/me", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it "returns the caller's fraction with full Blueprint payload" do
      Codex::FractionChangeService.call(user: user, node: node)
      get "/api/v1/codex/fractions/me", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["user_id"]).to eq(user.id)
      expect(data["node_slug"]).to eq(node.slug)
    end

    it "renders the My Fraction dashboard as HTML" do
      Codex::FractionChangeService.call(user: user, node: node)
      get "/api/v1/codex/fractions/me",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "text/html" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end
  end

  describe "GET /api/v1/codex/fractions/picker" do
    it "rejects unauthenticated requests" do
      get "/api/v1/codex/fractions/picker"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the picker frame for the active realm" do
      node # ensure pickable node exists
      get "/api/v1/codex/fractions/picker",
          params: { realm: realm.slug },
          headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("codex_fraction_picker")
      expect(response.body).to include(node.title_en)
    end

    it "falls back to the first ordered realm when ?realm= is omitted" do
      node
      get "/api/v1/codex/fractions/picker",
          headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("codex_fraction_picker")
    end
  end
end
