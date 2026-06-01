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

  describe "GET /api/v1/codex/admin/nodes" do
    it "is forbidden for non-admins" do
      bad = forester.generate_token_for(:api_access)
      get "/api/v1/codex/admin/nodes", headers: headers.merge("Authorization" => "Bearer #{bad}")
      expect(response).to have_http_status(:forbidden)
    end

    it "lists all nodes for admin+" do
      get "/api/v1/codex/admin/nodes", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |n| n["slug"] }).to include(node.slug)
    end
  end

  describe "GET /api/v1/codex/admin/nodes/:slug" do
    it "is forbidden for foresters" do
      bad = forester.generate_token_for(:api_access)
      get "/api/v1/codex/admin/nodes/#{node.slug}",
          headers: headers.merge("Authorization" => "Bearer #{bad}")
      expect(response).to have_http_status(:forbidden)
    end

    it "renders a single node payload for admin+" do
      get "/api/v1/codex/admin/nodes/#{node.slug}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "slug")).to eq(node.slug)
    end
  end

  describe "PATCH /api/v1/codex/admin/nodes/:slug" do
    it "updates the node for admin+" do
      patch "/api/v1/codex/admin/nodes/#{node.slug}",
            params: { node: { title_en: "New Title" } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(node.reload.title_en).to eq("New Title")
    end

    it "rejects an invalid lifecycle_status with 422" do
      patch "/api/v1/codex/admin/nodes/#{node.slug}",
            params: { node: { lifecycle_status: "imaginary" } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 with model validation errors on update failure" do
      other_node = create(:codex_node, realm: realm)
      patch "/api/v1/codex/admin/nodes/#{node.slug}",
            params: { node: { slug: other_node.slug } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end

    it "accepts external_refs JSONB array on update" do
      refs = [ { "label" => "Wikipedia", "url" => "https://en.wikipedia.org/wiki/Foo" } ]
      patch "/api/v1/codex/admin/nodes/#{node.slug}",
            params: { node: { external_refs: refs } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(node.reload.external_refs).to eq(refs)
    end

    it "passes a non-array external_refs through (validator rejects with 422)" do
      patch "/api/v1/codex/admin/nodes/#{node.slug}",
            params: { node: { external_refs: "not-an-array" } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end

    it "is forbidden for foresters" do
      bad = forester.generate_token_for(:api_access)
      patch "/api/v1/codex/admin/nodes/#{node.slug}",
            params: { node: { title_en: "X" } },
            headers: headers.merge("Authorization" => "Bearer #{bad}"), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/codex/admin/nodes" do
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
      post "/api/v1/codex/admin/nodes", params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a node with seed_origin = dao_proposal for super_admin" do
      sa_token = super_admin.generate_token_for(:api_access)
      post "/api/v1/codex/admin/nodes",
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
      post "/api/v1/codex/admin/nodes",
           params: bad_payload,
           headers: headers.merge("Authorization" => "Bearer #{sa_token}"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array).and(be_present)
    end
  end

  describe "DELETE /api/v1/codex/admin/nodes/:slug" do
    it "is forbidden for plain admin" do
      delete "/api/v1/codex/admin/nodes/#{node.slug}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it "destroys the node and returns 204 for super_admin" do
      sa_token = super_admin.generate_token_for(:api_access)
      expect {
        delete "/api/v1/codex/admin/nodes/#{node.slug}",
               headers: headers.merge("Authorization" => "Bearer #{sa_token}")
      }.to change(Codex::Node, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
