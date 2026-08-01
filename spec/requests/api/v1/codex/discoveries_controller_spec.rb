# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Discoveries", type: :request do
  let(:user)  { create(:user) }
  let(:token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  describe "GET /codex/discoveries/me" do
    it "401s anonymous" do
      get "/codex/discoveries/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns own list ordered by unlocked_at desc (JSON)" do
      n1 = create(:codex_node, title_en: "Older")
      n2 = create(:codex_node, title_en: "Newer")
      create(:codex_discovery, user: user, node: n1, unlocked_at: 2.days.ago)
      create(:codex_discovery, user: user, node: n2, unlocked_at: 1.minute.ago)
      _other_user = create(:codex_discovery, node: n1)

      get "/codex/discoveries/me", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      titles = response.parsed_body["data"].map { |d| d["node_title_en"] }
      expect(titles).to eq([ "Newer", "Older" ])
      expect(response.parsed_body["meta"]["count"]).to eq(2)
    end

    it "renders an HTML list" do
      n = create(:codex_node)
      create(:codex_discovery, user: user, node: n)
      get "/codex/discoveries/me", headers: headers
      expect(response.body).to include("codex_discoveries_collection")
      expect(response.body).to include(n.title_en)
    end

    it "shows empty-state copy" do
      get "/codex/discoveries/me", headers: headers
      expect(response.body).to include("Nothing unlocked yet")
    end
  end
end
