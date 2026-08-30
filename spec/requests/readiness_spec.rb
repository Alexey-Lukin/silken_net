# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Readiness probe", type: :request do
  describe "GET /ready" do
    it "returns 200 ready when DB and Redis are up" do
      get "/ready"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "status" => "ready",
        "checks" => { "database" => true, "redis" => true }
      )
    end

    it "returns 503 not_ready when the database does not respond" do
      conn = ActiveRecord::Base.connection
      allow(conn).to receive(:execute).and_call_original
      allow(conn).to receive(:execute).with("SELECT 1").and_raise(ActiveRecord::StatementInvalid)

      get "/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["status"]).to eq("not_ready")
      expect(response.parsed_body.dig("checks", "database")).to be(false)
    end

    it "returns 503 not_ready when Redis does not respond" do
      allow(Sidekiq).to receive(:redis).and_raise("redis down")

      get "/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("checks", "redis")).to be(false)
    end

    it "returns 503 not_ready when Kredis (Web3 locks) does not respond" do
      # Kredis backs the mint/burn nonce locks — a money-path dependency reached
      # through a SEPARATE client from the Sidekiq queue one ([INF.22]: they share a
      # single logical database now, so "distinct" is about the pool, not the DB
      # number). A node that can't reach it must not serve.
      allow(Kredis).to receive(:redis).and_raise("kredis down")

      get "/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("checks", "redis")).to be(false)
    end
  end
end
