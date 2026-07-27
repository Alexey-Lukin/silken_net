# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Citations", type: :request do
  let(:org)       { create(:organization) }
  let(:forester)  { create(:user, organization: org, role: :forester) }
  let(:investor)  { create(:user, organization: org, role: :investor) }
  let(:admin)     { create(:user, :admin, organization: org) }
  let(:node)      { create(:codex_node) }
  let(:tree)      { create(:tree) }
  let(:token)     { forester.generate_token_for(:api_access) }
  let(:headers) do
    { "Authorization" => "Bearer #{token}",
      "Content-Type"  => "application/json",
      "Idempotency-Key" => SecureRandom.uuid }
  end

  describe "POST /api/v1/codex/citations" do
    it "rejects unauthenticated requests" do
      post "/api/v1/codex/citations", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects investors (forester+ only)" do
      bad_token = investor.generate_token_for(:api_access)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers.merge("Authorization" => "Bearer #{bad_token}"),
           as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a citation and increments node.citation_count" do
      received = []
      allow(ActionCable.server).to receive(:broadcast) { |topic, payload| received << [ topic, payload ] }

      expect {
        post "/api/v1/codex/citations",
             params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id, note: "see lore_md" },
             headers: headers, as: :json
      }.to change { node.reload.citation_count }.by(1)

      expect(response).to have_http_status(:created)
      payload = response.parsed_body["data"]
      expect(payload).to include(
        "codex_node_id" => node.id,
        "citable_type"  => "Tree",
        "citable_id"    => tree.id,
        "note"          => "see lore_md",
        "node_slug"     => node.slug
      )
    end

    it "rejects JSON writes without Idempotency-Key" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers.except("Idempotency-Key"), as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "returns the cached response on Idempotency-Key replay" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers, as: :json
      first = response.parsed_body
      expect {
        post "/api/v1/codex/citations",
             params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
             headers: headers, as: :json
      }.not_to change(Codex::Citation, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(first)
    end

    it "rejects an unsupported citable_type" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "User", citable_id: 1 },
           headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 422 on duplicate (DB UNIQUE)" do
      create(:codex_citation, node: node, created_by_user: forester,
             citable_type: "Tree", citable_id: tree.id)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "resolves OracleVision citable_type to AiInsight when no STI subclass is defined" do
      insight = create(:ai_insight)
      expect(defined?(::OracleVision)).to be_nil

      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "OracleVision", citable_id: insight.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("AiInsight")
    end

    it "supports citable_type=Cluster" do
      cluster = create(:cluster)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Cluster", citable_id: cluster.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("Cluster")
    end

    it "supports citable_type=AiInsight" do
      insight = create(:ai_insight)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "AiInsight", citable_id: insight.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("AiInsight")
    end

    it "supports citable_type=EwsAlert" do
      alert = create(:ews_alert)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "EwsAlert", citable_id: alert.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("EwsAlert")
    end

    it "supports citable_type=NaasContract" do
      contract = create(:naas_contract)
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "NaasContract", citable_id: contract.id },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("NaasContract")
    end

    it "honors an OracleVision STI subclass when present" do
      stub_const("OracleVision", Class.new(AiInsight))
      insight = OracleVision.create!(analyzable: create(:tree), insight_type: :daily_health_summary,
                                     target_date: Date.current - 1, stress_index: 0.1, summary: "x")

      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "OracleVision", citable_id: insight.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "citable_type")).to eq("AiInsight")
    end

    it "returns 400 when a CITABLE_CLASS_MAP lambda raises NameError" do
      bogus_map = {
        "Tree" => -> { Tree },
        "Cluster" => -> { Cluster },
        "AiInsight" => -> { AiInsight },
        "EwsAlert" => -> { EwsAlert },
        "OracleVision" => -> { raise NameError, "uninitialized constant ImaginaryClass" },
        "NaasContract" => -> { NaasContract }
      }.freeze
      stub_const("Api::V1::Codex::CitationsController::CITABLE_CLASS_MAP", bogus_map)

      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "OracleVision", citable_id: 1 },
           headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("Unsupported citable_type")
    end


    # Non-JSON requests bypass the Idempotency-Key gate; the cache helpers
    # all early-return `nil` for blank keys (covers L124/L131/L137 branches).
    it "creates the citation without Idempotency-Key for form-encoded requests" do
      post "/api/v1/codex/citations",
           params: { codex_node_slug: node.slug, citable_type: "Tree", citable_id: tree.id },
           headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:created)
      expect(Codex::Citation.exists?(codex_node_id: node.id, citable_id: tree.id)).to be(true)
    end
  end

  describe "DELETE /api/v1/codex/citations/:id" do
    let!(:citation) do
      create(:codex_citation, node: node, created_by_user: forester,
             citable_type: "Tree", citable_id: tree.id)
    end

    it "lets the author delete within the 24 h grace" do
      delete "/api/v1/codex/citations/#{citation.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(Codex::Citation.find_by(id: citation.id)).to be_nil
    end

    it "blocks a non-author forester" do
      other = create(:user, organization: org, role: :forester)
      other_token = other.generate_token_for(:api_access)
      delete "/api/v1/codex/citations/#{citation.id}",
             headers: headers.merge("Authorization" => "Bearer #{other_token}")
      expect(response).to have_http_status(:forbidden)
    end

    it "lets admin+ delete past the grace window" do
      citation.update_columns(created_at: 25.hours.ago)
      admin_token = admin.generate_token_for(:api_access)
      delete "/api/v1/codex/citations/#{citation.id}",
             headers: headers.merge("Authorization" => "Bearer #{admin_token}")
      expect(response).to have_http_status(:no_content)
    end

    it "returns 204 and skips broadcast when the citable target has been destroyed" do
      tree.destroy!
      expect(ActionCable.server).not_to receive(:broadcast)

      delete "/api/v1/codex/citations/#{citation.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
