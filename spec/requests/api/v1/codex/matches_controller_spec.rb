# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Matches", type: :request do
  let(:user)    { create(:user) }
  let(:realm)   { create(:codex_realm) }
  let!(:left)   { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let!(:right)  { create(:codex_node, realm: realm, lifecycle_status: :thriving) }
  let(:token)   { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  before { Sidekiq::Worker.clear_all }

  describe "GET /codex/matches/new" do
    it "rejects unauthenticated requests" do
      get "/codex/matches/new"
      expect(response).to have_http_status(:unauthorized)
    end

    it "renders an Arena frame with two cards and a hidden pair_seed" do
      get "/codex/matches/new", params: { realm: realm.slug }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("codex_battle_arena")
      expect(response.body).to include(I18n.t("codex.battle_arena.vs"))
      expect(response.body).to match(/name="pair_seed" value="[0-9a-f]{64}"/)
    end

    it "renders an empty-state when realm has too few nodes" do
      ::Codex::Node.where(codex_realm_id: realm.id).update_all(lifecycle_status: "extinct")
      get "/codex/matches/new", params: { realm: realm.slug }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("not enough nodes")
    end

    it "falls back to the first ordered realm when ?realm= is omitted" do
      get "/codex/matches/new", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/name="pair_seed" value="[0-9a-f]{64}"/)
    end

    it "falls back to the first ordered realm when ?realm= is an unknown slug" do
      get "/codex/matches/new", params: { realm: "totally-fake-slug" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/name="pair_seed" value="[0-9a-f]{64}"/)
    end
  end

  describe "POST /codex/matches" do
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
      post "/codex/matches", params: { pair_seed: "x", winner_slug: left.slug }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a match, enqueues recompute worker, returns 201 + Blueprint" do
      seed = issue_seed
      expect {
        post "/codex/matches",
             params: { pair_seed: seed, winner_slug: left.slug },
             headers: headers, as: :json
      }.to change(Codex::Match, :count).by(1)
        .and change(Codex::EloRecomputeWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data["winner_slug"]).to eq(left.slug)
      expect(data["is_skip"]).to be(false)
    end

    it "returns 422 for a winner_slug that matches neither node in the pair" do
      seed = issue_seed
      post "/codex/matches",
           params: { pair_seed: seed, winner_slug: "not-in-this-pair" },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("winner_not_in_pair")
    end

    it "returns 403 on replay (seed already consumed)" do
      seed = issue_seed
      post "/codex/matches",
           params: { pair_seed: seed, winner_slug: left.slug },
           headers: headers, as: :json
      post "/codex/matches",
           params: { pair_seed: seed, winner_slug: right.slug },
           headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("seed_invalid_or_consumed")
    end

    # [SEC.25 Ф4] Той самий replay із браузера. Арена — справжні `<form>` без
    # дебаунсу (компонент сам це документує), тож подвійний клік буденний, а
    # відповіддю був сирий JSON. Пін на ФОРМУ: статус не змінювався.
    it "redirects instead of blobbing JSON when the browser replays a seed" do
      seed = issue_seed
      post "/codex/matches",
           params: { pair_seed: seed, winner_slug: left.slug },
           headers: headers, as: :json
      post "/codex/matches",
           params: { pair_seed: seed, winner_slug: right.slug },
           headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(new_codex_match_path)
      # Без цього рядка `error:` можна зняти — статус і ціль не змінились би.
      expect(flash[:error]).to be_present
      expect(response.media_type).not_to eq("application/json")
    end

    it "supports skip=true" do
      seed = issue_seed
      post "/codex/matches",
           params: { pair_seed: seed, skip: "true" },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "is_skip")).to be(true)
    end

    # 🔴 [SEC.25] Успіх відповідає РЕДИРЕКТОМ, не сторінкою — і пін мусить називати
    # ЦІЛЬ разом із реалмом. Доти тут стояло очікування повної сторінки зі статусом
    # `:created`, і саме воно цементувало дефект: Turbo на успіху йде в
    # `proposeVisit(fetchResponse.location)`, а `location` — то URL відповіді, тобто
    # адреса, зареєстрована лише під POST. Отже після кожного голосу перезавантаження
    # сторінки давало `RoutingError`. Реалм у цілі — друга половина піна: без нього
    # PRG-цикл мовчки скидав би людину в перший упорядкований реалм на кожен голос.
    it "redirects to a fresh pair in the SAME realm after a successful vote" do
      4.times { create(:codex_node, realm: realm, lifecycle_status: :thriving) }

      seed = issue_seed
      post "/codex/matches",
           params: { pair_seed: seed, winner_slug: left.slug, realm: realm.slug },
           headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(new_codex_match_path(realm: realm.slug))
      expect(response.media_type).not_to eq("application/json")
    end

    # ⚠️ Приклад «error frame, коли наступна пара не будується» знято свідомо, а не
    # загублено: після переходу на PRG підбір наступної пари належить `#new`, і його
    # порожній стан уже запінений вище («renders an empty-state when realm has too
    # few nodes»). Тримати обидва означало б пінити одну поведінку у двох місцях —
    # причому другий робив це через подвійний стаб селектора з лічильником викликів,
    # тобто моделював послідовність, якої в контролері більше немає.
  end
end
