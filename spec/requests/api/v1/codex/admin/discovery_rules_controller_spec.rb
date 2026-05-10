# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Admin::DiscoveryRules", type: :request do
  let(:user)        { create(:user) }
  let(:admin)       { create(:user, :admin) }
  let(:node)        { create(:codex_node) }
  let(:token)  { user.generate_token_for(:api_access) }
  let(:admin_tok) { admin.generate_token_for(:api_access) }
  let(:headers_user)  { { "Authorization" => "Bearer #{token}" } }
  let(:headers_admin) { { "Authorization" => "Bearer #{admin_tok}" } }

  describe "GET /api/v1/codex/admin/discovery_rules" do
    it "403 for non-admin" do
      get "/api/v1/codex/admin/discovery_rules", headers: headers_user, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "200 for admin, lists rules" do
      create(:codex_discovery_rule, node: node, created_by_user: admin, name: "ouch-ten-hours")
      get "/api/v1/codex/admin/discovery_rules", headers: headers_admin, as: :json
      expect(response).to have_http_status(:ok)
      names = response.parsed_body["data"].map { |r| r["name"] }
      expect(names).to include("ouch-ten-hours")
    end
  end

  describe "POST /api/v1/codex/admin/discovery_rules" do
    let(:valid_payload) do
      {
        name: "ten-matches-mythos",
        codex_node_id: node.id,
        condition_type: "match_count",
        threshold_value: 10,
        params: { realm_slug: "mythos" },
        active: true
      }
    end

    it "403 for non-admin" do
      post "/api/v1/codex/admin/discovery_rules", params: valid_payload,
                                                  headers: headers_user, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "201 for admin and persists JSONB params + created_by_user_id" do
      Rails.cache.clear
      expect {
        post "/api/v1/codex/admin/discovery_rules",
             params: valid_payload, headers: headers_admin, as: :json
      }.to change(Codex::DiscoveryRule, :count).by(1)

      expect(response).to have_http_status(:created)
      created = Codex::DiscoveryRule.last
      expect(created.condition_type).to eq("match_count")
      expect(created.params).to eq("realm_slug" => "mythos")
      expect(created.created_by_user_id).to eq(admin.id)
    end

    it "422 on invalid payload" do
      post "/api/v1/codex/admin/discovery_rules",
           params: valid_payload.merge(threshold_value: 0),
           headers: headers_admin, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "PATCH /api/v1/codex/admin/discovery_rules/:id" do
    it "updates active flag and busts the engine cache" do
      rule = create(:codex_discovery_rule, node: node, created_by_user: admin)
      Codex::DiscoveryRule.cached_active_by_condition # warm cache

      patch "/api/v1/codex/admin/discovery_rules/#{rule.id}",
            params: { active: false }, headers: headers_admin, as: :json
      expect(response).to have_http_status(:ok)
      expect(rule.reload.active).to be(false)
      # cache must be busted — re-read returns no rules of this condition
      expect(Codex::DiscoveryRule.cached_active_by_condition.values.flatten).to eq([])
    end
  end

  describe "DELETE /api/v1/codex/admin/discovery_rules/:id" do
    it "204 for admin" do
      rule = create(:codex_discovery_rule, node: node, created_by_user: admin)
      delete "/api/v1/codex/admin/discovery_rules/#{rule.id}",
             headers: headers_admin, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Codex::DiscoveryRule.where(id: rule.id)).to be_empty
    end
  end
end
