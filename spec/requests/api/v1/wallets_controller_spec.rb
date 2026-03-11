# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::WalletsController, type: :request do
  before do
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }

  describe "GET /api/v1/wallets" do
    context "when as admin" do
      let(:admin) { create(:user, :admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }

      it "returns paginated wallets" do
        get "/api/v1/wallets", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("pagy")
        expect(response.parsed_body["pagy"]).to include("page", "count", "pages")
      end
    end

    context "when as super_admin" do
      let(:super_admin) { create(:user, :super_admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

      it "returns paginated wallets" do
        get "/api/v1/wallets", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("pagy")
      end
    end

    context "when as regular user" do
      let(:user) { create(:user, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

      it "returns only organization wallets with pagination" do
        get "/api/v1/wallets", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("pagy")
      end
    end
  end

  describe "GET /api/v1/wallets/:id" do
    let(:user) { create(:user, organization: organization) }
    let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

    it "returns wallet with paginated transactions" do
      get "/api/v1/wallets/#{wallet.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("wallet")
      expect(response.parsed_body).to have_key("transactions")
      expect(response.parsed_body).to have_key("pagy")
    end
  end

  context "format.html responses" do
    let(:admin) { create(:user, :admin, organization: organization) }
    let(:html_headers) do
      { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/wallets", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/wallets/#{wallet.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end
