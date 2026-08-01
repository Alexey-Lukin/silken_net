# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Admin::Nodes", type: :request do
  let(:org)         { create(:organization) }
  let(:admin)       { create(:user, :admin, organization: org) }
  let(:super_admin) { create(:user, :super_admin, organization: org) }
  let(:forester)    { create(:user, organization: org, role: :forester) }
  let(:realm)       { create(:codex_realm) }
  let!(:node)       { create(:codex_node, realm: realm) }
  let(:headers)     { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:token)       { admin.generate_token_for(:api_access) }

  describe "GET /codex/admin/nodes" do
    it "is forbidden for non-admins" do
      bad = forester.generate_token_for(:api_access)
      get "/codex/admin/nodes", headers: headers.merge("Authorization" => "Bearer #{bad}")
      expect(response).to have_http_status(:forbidden)
    end

    it "lists all nodes for admin+" do
      get "/codex/admin/nodes", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |n| n["slug"] }).to include(node.slug)
    end
  end

  describe "GET /codex/admin/nodes/:slug" do
    it "is forbidden for foresters" do
      bad = forester.generate_token_for(:api_access)
      get "/codex/admin/nodes/#{node.slug}",
          headers: headers.merge("Authorization" => "Bearer #{bad}")
      expect(response).to have_http_status(:forbidden)
    end

    it "renders a single node payload for admin+" do
      get "/codex/admin/nodes/#{node.slug}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "slug")).to eq(node.slug)
    end
  end

  describe "PATCH /codex/admin/nodes/:slug" do
    it "updates the node for admin+" do
      patch "/codex/admin/nodes/#{node.slug}",
            params: { node: { title_en: "New Title" } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(node.reload.title_en).to eq("New Title")
    end

    it "rejects an invalid lifecycle_status with 422" do
      patch "/codex/admin/nodes/#{node.slug}",
            params: { node: { lifecycle_status: "imaginary" } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 with model validation errors on update failure" do
      other_node = create(:codex_node, realm: realm)
      patch "/codex/admin/nodes/#{node.slug}",
            params: { node: { slug: other_node.slug } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end

    it "accepts external_refs JSONB array on update" do
      refs = [ { "label" => "Wikipedia", "url" => "https://en.wikipedia.org/wiki/Foo" } ]
      patch "/codex/admin/nodes/#{node.slug}",
            params: { node: { external_refs: refs } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(node.reload.external_refs).to eq(refs)
    end

    it "passes a non-array external_refs through (validator rejects with 422)" do
      patch "/codex/admin/nodes/#{node.slug}",
            params: { node: { external_refs: "not-an-array" } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end

    it "is forbidden for foresters" do
      bad = forester.generate_token_for(:api_access)
      patch "/codex/admin/nodes/#{node.slug}",
            params: { node: { title_en: "X" } },
            headers: headers.merge("Authorization" => "Bearer #{bad}"), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  # A real HTTP `as: :json` request always wraps a nested Hash — including each
  # element of a nested Array — as `ActionController::Parameters`, so the `#node_params`
  # per-element ternary always takes its `to_unsafe_h` branch in a genuine request-spec
  # (verified: `arr.first.respond_to?(:to_unsafe_h)` is true for a JSON array of hashes
  # here). The bare-`r` fallback only matters for a caller that hands `node_params` an
  # already-plain-Hash element directly — exercised here via a stubbed `params`.
  describe "#node_params external_refs per-element fallback" do
    it "passes through an array element that is already a plain Hash (no #to_unsafe_h)" do
      controller = Api::V1::Codex::Admin::NodesController.new
      plain_ref = { "url" => "https://example.test" }
      real_node_params = ActionController::Parameters.new(codex_uid: "CDX-ECO-9997")

      fake_params = double("params")
      allow(fake_params).to receive(:require).with(:node).and_return(real_node_params)
      allow(fake_params).to receive(:[]).with(:node).and_return({ external_refs: [ plain_ref ] })
      allow(controller).to receive(:params).and_return(fake_params)

      # Assigning an Array of Hashes INTO an ActionController::Parameters
      # container re-wraps each element back into Parameters (Rails' own
      # auto-wrap-on-write) — `.to_unsafe_h` compares content regardless of
      # which ternary branch (bare `r` vs `r.to_unsafe_h`) produced it.
      permitted = controller.send(:node_params)
      expect(permitted[:external_refs].map(&:to_unsafe_h)).to eq([ plain_ref ])
    end
  end

  describe "POST /codex/admin/nodes" do
    let(:payload) do
      {
        node: {
          slug: "new-dao-rune",
          codex_uid: "CDX-ECO-9999",
          codex_realm_id: realm.id,
          title_uk: "Нова DAO-руна",
          title_en: "New DAO Rune",
          archetype_key: Codex::ARCHETYPES.first,
          lifecycle_status: "thriving"
        }
      }
    end

    it "is forbidden for plain admin (super_admin only)" do
      post "/codex/admin/nodes", params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a node with seed_origin = dao_proposal for super_admin" do
      sa_token = super_admin.generate_token_for(:api_access)
      post "/codex/admin/nodes",
           params: payload,
           headers: headers.merge("Authorization" => "Bearer #{sa_token}"), as: :json
      expect(response).to have_http_status(:created)
      created = Codex::Node.find_by(slug: "new-dao-rune")
      expect(created).not_to be_nil
      expect(created.seed_origin).to eq("dao_proposal")
    end

    it "returns 422 with model validation errors when create fails" do
      sa_token = super_admin.generate_token_for(:api_access)
      bad_payload = payload.deep_dup
      bad_payload[:node][:slug] = node.slug  # duplicate slug → validation error
      post "/codex/admin/nodes",
           params: bad_payload,
           headers: headers.merge("Authorization" => "Bearer #{sa_token}"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end
  end

  describe "DELETE /codex/admin/nodes/:slug" do
    it "is forbidden for plain admin" do
      delete "/codex/admin/nodes/#{node.slug}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it "destroys the node and returns 204 for super_admin" do
      sa_token = super_admin.generate_token_for(:api_access)
      expect {
        delete "/codex/admin/nodes/#{node.slug}",
               headers: headers.merge("Authorization" => "Bearer #{sa_token}")
      }.to change(Codex::Node, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
