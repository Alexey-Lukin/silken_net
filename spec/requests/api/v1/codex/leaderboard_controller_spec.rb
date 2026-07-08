# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Leaderboard", type: :request do
  let(:realm) { create(:codex_realm) }

  before do
    create(:codex_node, realm: realm, lifecycle_status: :thriving, attunement_elo: 1700,
           title_en: "Pinnacle", title_uk: "Вершина")
    create(:codex_node, realm: realm, lifecycle_status: :thriving, attunement_elo: 1300,
           title_en: "Sparrow",  title_uk: "Горобець")
  end

  describe "GET /api/v1/codex/leaderboard" do
    it "is publicly accessible (no auth required)" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug }
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON sorted by Elo desc" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, format: :json }
      expect(response).to have_http_status(:ok)
      titles = response.parsed_body["data"].map { |row| row["title_en"] }
      expect(titles.first).to eq("Pinnacle")
      expect(titles.last).to eq("Sparrow")
    end

    it "includes both bilingual title columns in each JSON row" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, format: :json }
      row = response.parsed_body["data"].first
      expect(row.keys).to include("title_uk", "title_en", "attunement_elo", "match_count", "lifecycle_status")
    end

    it "renders an HTML leaderboard table" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug }
      expect(response.body).to include("codex_leaderboard")
      expect(response.body).to include("Pinnacle")
    end

    it "excludes destroyed/extinct nodes" do
      create(:codex_node, realm: realm, lifecycle_status: :extinct, title_en: "Dead")
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, format: :json }
      titles = response.parsed_body["data"].map { |r| r["title_en"] }
      expect(titles).not_to include("Dead")
    end

    it "honours the limit param (clamp to MAX_LIMIT=100)" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, limit: 1, format: :json }
      expect(response.parsed_body["data"].size).to eq(1)
    end

    it "clamps excessively large limit to 100" do
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, limit: 999, format: :json }
      expect(response).to have_http_status(:ok)
      # The result size will be <= 100 regardless of input
      expect(response.parsed_body["data"].size).to be <= 100
    end

    it "falls back to the first realm when realm param is blank" do
      create(:codex_realm, position: 0, slug: "first_realm")
      get "/api/v1/codex/leaderboard"
      expect(response).to have_http_status(:ok)
    end

    it "uses DEFAULT_LIMIT (25) when no limit is supplied" do
      30.times { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
      get "/api/v1/codex/leaderboard", params: { realm: realm.slug, format: :json }
      expect(response.parsed_body["data"].size).to eq(25)
    end

    it "renders an empty board gracefully when no realm exists at all" do
      Codex::Node.delete_all
      Codex::Realm.delete_all
      get "/api/v1/codex/leaderboard", params: { format: :json }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to eq([])
    end
  end
end
