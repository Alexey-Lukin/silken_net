# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::TreeFamiliesController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:investor) { create(:user, :investor, organization: organization) }
  let(:admin_token) { admin.generate_token_for(:api_access) }
  let(:investor_token) { investor.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:investor_headers) { { "Authorization" => "Bearer #{investor_token}" } }

  let!(:scots_pine) { create(:tree_family, :scots_pine) }
  let!(:common_oak) { create(:tree_family, :common_oak) }

  describe "GET /api/v1/tree_families" do
    context "when as JSON" do
      it "returns all tree families for admin" do
        get "/api/v1/tree_families", headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        names = response.parsed_body["data"].map { |f| f["name"] }
        expect(names).to include("Scots Pine", "Common Oak")
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/tree_families", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 403 for non-admin users" do
      get "/api/v1/tree_families", headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      get "/api/v1/tree_families", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/tree_families/:id" do
    context "when as JSON" do
      it "returns a specific tree family" do
        get "/api/v1/tree_families/#{scots_pine.id}", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["name"]).to eq("Scots Pine")
      end
    end

    context "when as HTML" do
      it "renders the dashboard page" do
        get "/api/v1/tree_families/#{scots_pine.id}", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 403 for non-admin users" do
      get "/api/v1/tree_families/#{scots_pine.id}", headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/tree_families/new" do
    it "renders the new family form for admin" do
      get "/api/v1/tree_families/new", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-admin users" do
      get "/api/v1/tree_families/new", headers: investor_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/tree_families" do
    let(:valid_params) do
      {
        tree_family: {
          name: "Silver Birch",
          scientific_name: "Betula pendula",
          baseline_impedance: 1500,
          critical_z_min: 6.0,
          critical_z_max: 42.0,
          carbon_sequestration_coefficient: 1.2
        }
      }
    end

    let(:invalid_params) do
      {
        tree_family: {
          name: "",
          baseline_impedance: nil,
          critical_z_min: nil,
          critical_z_max: nil,
          carbon_sequestration_coefficient: nil
        }
      }
    end

    it "creates a new tree family with valid params" do
      expect {
        post "/api/v1/tree_families", params: valid_params, headers: headers
      }.to change(TreeFamily, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end

    it "does not create with invalid params and re-renders form" do
      expect {
        post "/api/v1/tree_families", params: invalid_params, headers: headers
      }.not_to change(TreeFamily, :count)

      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-admin users" do
      post "/api/v1/tree_families", params: valid_params, headers: investor_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/tree_families/:id/edit" do
    it "renders the edit form for admin" do
      get "/api/v1/tree_families/#{scots_pine.id}/edit", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-admin users" do
      get "/api/v1/tree_families/#{scots_pine.id}/edit", headers: investor_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/tree_families/:id" do
    it "updates the tree family with valid params" do
      patch "/api/v1/tree_families/#{scots_pine.id}",
            params: { tree_family: { name: "Updated Pine" } },
            headers: headers

      expect(response).to have_http_status(:redirect)
      expect(scots_pine.reload.name).to eq("Updated Pine")
    end

    it "re-renders form with invalid params" do
      patch "/api/v1/tree_families/#{scots_pine.id}",
            params: { tree_family: { name: "" } },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(scots_pine.reload.name).to eq("Scots Pine")
    end

    it "returns 403 for non-admin users" do
      patch "/api/v1/tree_families/#{scots_pine.id}",
            params: { tree_family: { name: "Hacked" } },
            headers: investor_headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
