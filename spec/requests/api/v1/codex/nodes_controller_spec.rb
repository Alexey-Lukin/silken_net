# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Nodes", type: :request do
  let(:org)   { create(:organization) }
  let(:user)  { create(:user, organization: org) }
  let(:token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  let!(:eco)   { create(:codex_realm, slug: "ecosystem", position: 1) }
  let!(:tree)  { create(:codex_realm, slug: "unique_tree", position: 2) }
  let!(:node1) { create(:codex_node, realm: eco,  slug: "cherkasy-bir",   title_uk: "Черкаський бір",  title_en: "Cherkasy Pine Forest", lifecycle_status: :thriving,  attunement_elo: 1700) }
  let!(:node2) { create(:codex_node, realm: eco,  slug: "kholodnyi-yar",  title_uk: "Холодний Яр",     title_en: "Kholodnyi Yar",        lifecycle_status: :endangered, attunement_elo: 1500) }
  let!(:node3) { create(:codex_node, realm: tree, slug: "methuselah",     title_uk: "Мафусаїл",         title_en: "Methuselah",           lifecycle_status: :thriving,  attunement_elo: 1900) }

  describe "GET /api/v1/codex/nodes" do
    it "returns 401 without authentication" do
      get "/api/v1/codex/nodes", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns paginated JSON ordered by attunement_elo desc" do
      get "/api/v1/codex/nodes", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("data", "pagy")
      slugs = body["data"].map { |n| n["slug"] }
      expect(slugs.first).to eq("methuselah") # highest Elo
    end

    it "filters by realm slug" do
      get "/api/v1/codex/nodes", params: { realm: "unique_tree" }, headers: headers, as: :json
      slugs = response.parsed_body["data"].map { |n| n["slug"] }
      expect(slugs).to contain_exactly("methuselah")
    end

    it "filters by lifecycle_status" do
      get "/api/v1/codex/nodes", params: { lifecycle_status: "endangered" }, headers: headers, as: :json
      slugs = response.parsed_body["data"].map { |n| n["slug"] }
      expect(slugs).to contain_exactly("kholodnyi-yar")
    end

    it "supports trigram-style title search across both locales" do
      get "/api/v1/codex/nodes", params: { q: "Мафу" }, headers: headers, as: :json
      slugs = response.parsed_body["data"].map { |n| n["slug"] }
      expect(slugs).to contain_exactly("methuselah")
    end

    it "filters by archetype" do
      get "/api/v1/codex/nodes",
          params: { archetype: node1.archetype_key },
          headers: headers, as: :json
      slugs = response.parsed_body["data"].map { |n| n["slug"] }
      expect(slugs).to include("cherkasy-bir")
    end

    it "renders the Atlas dashboard as HTML when format=html" do
      get "/api/v1/codex/nodes", headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Codex Atlas")
    end
  end

  describe "GET /api/v1/codex/nodes/:slug" do
    it "returns the node payload by slug (not id)" do
      get "/api/v1/codex/nodes/cherkasy-bir", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["slug"]).to eq("cherkasy-bir")
      expect(body.keys).to include("title_uk", "title_en", "archetype_key", "lifecycle_status")
    end

    it "increments view_count atomically" do
      expect {
        get "/api/v1/codex/nodes/cherkasy-bir", headers: headers, as: :json
      }.to change { node1.reload.view_count }.by(1)
    end

    it "returns 404 for unknown slug" do
      get "/api/v1/codex/nodes/does-not-exist", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "hides drafts from non-super-admin users" do
      draft = create(:codex_node, slug: "draft-node", published_at: nil)
      get "/api/v1/codex/nodes/#{draft.slug}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "renders the Show dashboard as HTML with comments + attunement state" do
      create(:codex_comment, commentable: node1, user: user, body_md: "Lore note")

      get "/api/v1/codex/nodes/#{node1.slug}", headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(node1.title_en)
    end

    # 🔴 Пін КЛАСУ UI.7, і жити він мусить саме тут. Компонентна спека рендерить
    # повз маршрутизатор, тож ціль, яка існує, але дії не приймає, її не червонить:
    # обидві гілки тумблера цілили в колекційний шлях (зареєстрований лише під POST),
    # тож зняття резонансу летіло в 404 при повністю зеленій сюїті.
    it "aims the un-attune button at the DELETE route once the viewer is attuned" do
      create(:codex_attunement, user: user, node: node1)

      get "/api/v1/codex/nodes/#{node1.slug}", headers: headers.merge("Accept" => "text/html")

      expect(response.body).to include(%(action="#{api_v1_codex_node_my_attunement_path(node1.slug)}"))
      expect(response.body).not_to include(%(action="#{api_v1_codex_node_attunements_path(node1.slug)}"))
    end
  end
end
