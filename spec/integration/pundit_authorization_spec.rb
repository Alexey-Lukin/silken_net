# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pundit authorization integration" do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }

  let(:investor) { create(:user, :investor, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:investor_headers) { { "Authorization" => "Bearer #{investor.generate_token_for(:api_access)}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }
  let(:super_admin_headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
  end

  describe "GET /api/v1/users" do
    it "returns 403 for investors (not admin)" do
      get "/api/v1/users", headers: investor_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 200 for admin" do
      get "/api/v1/users", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/users/me" do
    it "returns 200 for any authenticated user" do
      get "/api/v1/users/me", headers: investor_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/wallets" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let!(:own_tree) { create(:tree, cluster: cluster) }
    let!(:other_tree) { create(:tree, cluster: other_cluster) }

    it "scopes wallets to org for investor" do
      get "/api/v1/wallets", headers: investor_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["wallets"].map { |w| w["id"] }
      expect(ids).to include(own_tree.wallet.id)
      expect(ids).not_to include(other_tree.wallet.id)
    end

    it "returns all wallets for admin" do
      get "/api/v1/wallets", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["wallets"].map { |w| w["id"] }
      expect(ids).to include(own_tree.wallet.id, other_tree.wallet.id)
    end
  end
end
