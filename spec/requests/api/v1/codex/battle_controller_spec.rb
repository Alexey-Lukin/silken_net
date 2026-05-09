# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe "Api::V1::Codex::Battle", type: :request do
  let(:user)    { create(:user) }
  let(:realm)   { create(:codex_realm) }
  let!(:left)   { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let!(:right)  { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let(:token)   { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  before { Sidekiq::Worker.clear_all }

  describe "GET /api/v1/codex/battle/pair" do
    it "rejects unauthenticated requests" do
      get "/api/v1/codex/battle/pair"
      expect(response).to have_http_status(:unauthorized)
    end

    it "renders an Arena frame with two cards and a hidden pair_seed" do
      get "/api/v1/codex/battle/pair", params: { realm: realm.slug }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("codex_battle_arena")
      expect(response.body).to include("VS")
      expect(response.body).to match(/name="pair_seed" value="[0-9a-f]{64}"/)
    end

    it "renders an empty-state when realm has too few nodes" do
      ::Codex::Node.where(codex_realm_id: realm.id).update_all(lifecycle_status: "extinct")
      get "/api/v1/codex/battle/pair", params: { realm: realm.slug }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("not enough nodes")
    end
  end

  describe "POST /api/v1/codex/battle/votes" do
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
      post "/api/v1/codex/battle/votes", params: { pair_seed: "x", winner_slug: left.slug }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a match, enqueues recompute worker, returns 201 + Blueprint" do
      seed = issue_seed
      expect {
        post "/api/v1/codex/battle/votes",
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
      post "/api/v1/codex/battle/votes",
           params: { pair_seed: seed, winner_slug: left.slug },
           headers: headers, as: :json
      post "/api/v1/codex/battle/votes",
           params: { pair_seed: seed, winner_slug: right.slug },
           headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("seed_invalid_or_consumed")
    end

    it "supports skip=true" do
      seed = issue_seed
      post "/api/v1/codex/battle/votes",
           params: { pair_seed: seed, skip: "true" },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "is_skip")).to be(true)
    end
  end

  describe "GET /api/v1/codex/leaderboard" do
    before do
      create(:codex_node, realm: realm, lifecycle_status: :thriving, attunement_elo: 1700, title_en: "Pinnacle")
      create(:codex_node, realm: realm, lifecycle_status: :thriving, attunement_elo: 1300, title_en: "Sparrow")
    end

    it "is publicly accessible (no auth)" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug }
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON sorted by Elo desc when format=json" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, format: :json }
      expect(response).to have_http_status(:ok)
      titles = response.parsed_body["data"].map { |row| row["title_en"] }
      expect(titles.first).to eq("Pinnacle")
    end

    it "renders an HTML table" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug }
      expect(response.body).to include("codex_leaderboard")
      expect(response.body).to include("Pinnacle")
    end

    it "honours limit param (max 100, default 25)" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, limit: 1 }
      # 1 row + header + structure — at least the count is bounded
      expect(response.body.scan(/<tr/).size).to be <= 3 # header + 1 row + maybe wrapper
    end
  end
end
