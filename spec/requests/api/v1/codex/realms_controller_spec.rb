# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Realms", type: :request do
  let(:org)   { create(:organization) }
  let(:user)  { create(:user, organization: org) }
  let(:token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  before do
    create(:codex_realm, slug: "ecosystem",   position: 1, name_uk: "Екосистеми",   name_en: "Ecosystems")
    create(:codex_realm, slug: "unique_tree", position: 2, name_uk: "Дерева",       name_en: "Unique Trees")
  end

  describe "GET /codex/realms" do
    it "returns 401 without a token" do
      get "/codex/realms", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the realm collection ordered by position" do
      get "/codex/realms", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      slugs = response.parsed_body["data"].map { |r| r["slug"] }
      expect(slugs).to eq(%w[ecosystem unique_tree])
    end

    it "exposes the bilingual names in the JSON payload" do
      get "/codex/realms", headers: headers, as: :json
      first = response.parsed_body["data"].first
      expect(first.keys).to include("name_uk", "name_en", "glyph", "accent_token")
    end
  end
end
