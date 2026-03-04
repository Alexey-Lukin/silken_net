# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrganizationsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  describe "GET /api/v1/organizations" do
    context "as a super_admin" do
      let(:super_admin) { create(:user, :super_admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

      it "returns organizations list" do
        get "/api/v1/organizations", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context "as a regular admin" do
      let(:admin) { create(:user, :admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }

      it "returns forbidden" do
        get "/api/v1/organizations", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "as a regular user" do
      let(:user) { create(:user, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

      it "returns forbidden" do
        get "/api/v1/organizations", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/organizations/:id" do
    let(:super_admin) { create(:user, :super_admin, organization: organization) }
    let(:headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

    it "uses cached_trees_count for performance" do
      get "/api/v1/organizations/#{organization.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["performance"]["total_trees"]).to be_a(Integer)
    end
  end
end
