# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe "Api::V1::Codex::Matches", type: :request do
  let(:user)    { create(:user) }
  let(:realm)   { create(:codex_realm) }
  let!(:left)   { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let!(:right)  { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let(:token)   { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  before { Sidekiq::Worker.clear_all }

  describe "GET /api/v1/codex/matches/new" do
    it "rejects unauthenticated requests" do
      get "/api/v1/codex/matches/new"
      expect(response).to have_http_status(:unauthorized)
    end

    it "renders an Arena frame with two cards and a hidden pair_seed" do
      get "/api/v1/codex/matches/new", params: { realm: realm.slug }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("codex_battle_arena")
      expect(response.body).to include("VS")
      expect(response.body).to match(/name="pair_seed" value="[0-9a-f]{64}"/)
    end

    it "renders an empty-state when realm has too few nodes" do
      ::Codex::Node.where(codex_realm_id: realm.id).update_all(lifecycle_status: "extinct")
      get "/api/v1/codex/matches/new", params: { realm: realm.slug }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("not enough nodes")
    end
  end

  describe "POST /api/v1/codex/matches" do
    def issue_seed
      r = Kredis.redis(config: :shared)
      seed = SecureRandom.hex(32)
      r.setex(
        "codex:pair_seed:#{seed}",
        ::Codex::PairSelectorService::SEED_TTL.to_i,
        "#{user.id}|#{realm.id}|#{left.id}|#{right.id}|#{Time.current.to_i}"
      )
      seed
    end

    it "rejects unauthenticated requests" do
      post "/api/v1/codex/matches", params: { pair_seed: "x", winner_slug: left.slug }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a match, enqueues recompute worker, returns 201 + Blueprint" do
      seed = issue_seed
      expect {
        post "/api/v1/codex/matches",
             params: { pair_seed: seed, winner_slug: left.slug },
             headers: headers, as: :json
      }.to change(Codex::Match, :count).by(1)
        .and change(Codex::EloRecomputeWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["winner_slug"]).to eq(left.slug)
      expect(data["is_skip"]).to be(false)
    end

    it "returns 403 on replay (seed already consumed)" do
      seed = issue_seed
      post "/api/v1/codex/matches",
           params: { pair_seed: seed, winner_slug: left.slug },
           headers: headers, as: :json
      post "/api/v1/codex/matches",
           params: { pair_seed: seed, winner_slug: right.slug },
           headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("seed_invalid_or_consumed")
    end

    it "supports skip=true" do
      seed = issue_seed
      post "/api/v1/codex/matches",
           params: { pair_seed: seed, skip: "true" },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "is_skip")).to be(true)
    end
  end
end
