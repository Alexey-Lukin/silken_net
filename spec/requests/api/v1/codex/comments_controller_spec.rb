# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Codex::Comments", type: :request do
  let(:org)     { create(:organization) }
  let(:user)    { create(:user, organization: org) }
  let(:realm)   { create(:codex_realm) }
  let(:node)    { create(:codex_node, realm: realm) }
  let(:token)   { user.generate_token_for(:api_access) }
  let(:headers) do
    { "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Idempotency-Key" => SecureRandom.uuid }
  end

  describe "POST /api/v1/codex/nodes/:slug/comments" do
    it "rejects unauthenticated requests" do
      post "/api/v1/codex/nodes/#{node.slug}/comments", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a comment and increments comments_count" do
      expect {
        post "/api/v1/codex/nodes/#{node.slug}/comments",
             params: { comment: { body_md: "Hello **world**." } },
             headers: headers, as: :json
      }.to change { node.reload.comments_count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "body_md")).to eq("Hello **world**.")
      expect(response.parsed_body.dig("data", "body_html")).to include("<strong>world</strong>")
    end

    it "rejects JSON writes without an Idempotency-Key" do
      bad_headers = headers.except("Idempotency-Key")
      post "/api/v1/codex/nodes/#{node.slug}/comments",
           params: { comment: { body_md: "Hi" } },
           headers: bad_headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include('Idempotency-Key')
    end

    it "returns the cached response on a retry with the same Idempotency-Key" do
      key = SecureRandom.uuid
      h   = headers.merge("Idempotency-Key" => key)

      expect {
        2.times do
          post "/api/v1/codex/nodes/#{node.slug}/comments",
               params: { comment: { body_md: "First and only post." } },
               headers: h, as: :json
        end
      }.to change(Codex::Comment, :count).by(1)

      # First → 201, second → 200 (cached). Final visible state == one row.
      expect(node.reload.comments_count).to eq(1)
    end

    it "returns 422 on a body that exceeds the cap" do
      post "/api/v1/codex/nodes/#{node.slug}/comments",
           params: { comment: { body_md: "x" * (Codex::Comment::BODY_MAX + 1) } },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s on unknown slug" do
      post "/api/v1/codex/nodes/no-such-slug/comments",
           params: { comment: { body_md: "hi" } },
           headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "permits a one-level reply with parent_id" do
      parent = create(:codex_comment, user: user, commentable: node)
      post "/api/v1/codex/nodes/#{node.slug}/comments",
           params: { comment: { body_md: "Reply.", parent_id: parent.id } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "parent_id")).to eq(parent.id)
    end

    it "allows HTML writes without an Idempotency-Key (skips idempotency cache)" do
      html_headers = { "Authorization" => "Bearer #{token}" }

      expect {
        post "/api/v1/codex/nodes/#{node.slug}/comments",
             params: { comment: { body_md: "html post" } },
             headers: html_headers
      }.to change { node.reload.comments_count }.by(1)

      expect(response).to redirect_to(api_v1_codex_node_path(node.slug))
    end
  end
end
