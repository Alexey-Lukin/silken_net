# SPDX-License-Identifier: AGPL-3.0-or-later
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

  describe "GET /codex/admin/discovery_rules" do
    it "403 for non-admin" do
      get "/codex/admin/discovery_rules", headers: headers_user, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "200 for admin, lists rules" do
      create(:codex_discovery_rule, node: node, created_by_user: admin, name: "ouch-ten-hours")
      get "/codex/admin/discovery_rules", headers: headers_admin, as: :json
      expect(response).to have_http_status(:ok)
      names = response.parsed_body["data"].map { |r| r["name"] }
      expect(names).to include("ouch-ten-hours")
    end
  end

  describe "POST /codex/admin/discovery_rules" do
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
      post "/codex/admin/discovery_rules", params: valid_payload,
                                                  headers: headers_user, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "201 for admin and persists JSONB params + created_by_user_id" do
      Rails.cache.clear
      expect {
        post "/codex/admin/discovery_rules",
             params: valid_payload, headers: headers_admin, as: :json
      }.to change(Codex::DiscoveryRule, :count).by(1)

      expect(response).to have_http_status(:created)
      created = Codex::DiscoveryRule.last
      expect(created.condition_type).to eq("match_count")
      expect(created.params).to eq("realm_slug" => "mythos")
      expect(created.created_by_user_id).to eq(admin.id)
    end

    it "422 on invalid payload" do
      post "/codex/admin/discovery_rules",
           params: valid_payload.merge(threshold_value: 0),
           headers: headers_admin, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "GET /codex/admin/discovery_rules/:id" do
    it "renders a single rule for admin+" do
      rule = create(:codex_discovery_rule, node: node, created_by_user: admin, name: "show-me")
      get "/codex/admin/discovery_rules/#{rule.id}", headers: headers_admin, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "name")).to eq("show-me")
    end

    it "is forbidden for non-admin" do
      rule = create(:codex_discovery_rule, node: node, created_by_user: admin)
      get "/codex/admin/discovery_rules/#{rule.id}", headers: headers_user, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /codex/admin/discovery_rules/:id" do
    it "updates active flag and busts the engine cache" do
      rule = create(:codex_discovery_rule, node: node, created_by_user: admin)
      Codex::DiscoveryRule.cached_active_by_condition # warm cache

      patch "/codex/admin/discovery_rules/#{rule.id}",
            params: { active: false }, headers: headers_admin, as: :json
      expect(response).to have_http_status(:ok)
      expect(rule.reload.active).to be(false)
      # cache must be busted — re-read returns no rules of this condition
      expect(Codex::DiscoveryRule.cached_active_by_condition.values.flatten).to eq([])
    end

    it "returns 422 with model errors when update validation fails" do
      rule = create(:codex_discovery_rule, node: node, created_by_user: admin)
      patch "/codex/admin/discovery_rules/#{rule.id}",
            params: { threshold_value: 0 }, headers: headers_admin, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  # A real HTTP `as: :json` request always wraps a nested Hash as
  # `ActionController::Parameters` (`params[:params].is_a?(ActionController::Parameters)`
  # is true), so `#rule_params`'s `if`-branch (`to_unsafe_h`) is what every request-spec
  # above exercises. The `elsif ... is_a?(Hash)` fallback below only matters for a caller
  # that hands `rule_params` an already-plain-Hash `:params` value directly.
  describe "#rule_params plain-Hash fallback for :params" do
    it "accepts a plain Hash for :params when it did not arrive as ActionController::Parameters" do
      controller = Api::V1::Codex::Admin::DiscoveryRulesController.new
      real_base_params = ActionController::Parameters.new(
        name: "x", codex_node_id: node.id, condition_type: "match_count", threshold_value: 5
      )
      fake_params = double("params")
      allow(fake_params).to receive(:permit)
        .with(:name, :codex_node_id, :condition_type, :threshold_value, :active)
        .and_return(real_base_params)
      allow(fake_params).to receive(:[]).with(:params).and_return({ "realm_slug" => "mythos" })
      allow(controller).to receive(:params).and_return(fake_params)

      # `permitted[:params] = params[:params]` assigns INTO an
      # ActionController::Parameters container, which re-wraps a Hash-valued
      # assignment back into Parameters (Rails' own auto-wrap-on-write) — so
      # `.to_unsafe_h` is needed to compare content regardless of which
      # if/elsif branch produced it.
      permitted = controller.send(:rule_params)
      expect(permitted[:params].to_unsafe_h).to eq("realm_slug" => "mythos")
    end
  end

  describe "DELETE /codex/admin/discovery_rules/:id" do
    it "204 for admin" do
      rule = create(:codex_discovery_rule, node: node, created_by_user: admin)
      delete "/codex/admin/discovery_rules/#{rule.id}",
             headers: headers_admin, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Codex::DiscoveryRule.where(id: rule.id)).to be_empty
    end
  end
end
