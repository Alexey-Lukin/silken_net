# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pundit authorization integration" do
  let(:organization) { create(:organization) }
  let(:other_org) { create(:organization) }

  let(:subscriber) { create(:user, :subscriber, organization: organization) }
  let(:admin) { create(:user, :admin, organization: organization) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:subscriber_headers) { { "Authorization" => "Bearer #{subscriber.generate_token_for(:api_access)}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }
  let(:super_admin_headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
  end

  describe "GET /users" do
    it "returns 403 for subscribers (not admin)" do
      get "/users", headers: subscriber_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 200 for admin" do
      get "/users", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /users/me" do
    it "returns 200 for any authenticated user" do
      get "/users/me", headers: subscriber_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /wallets" do
    let(:cluster) { create(:cluster, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_org) }
    let!(:own_tree) { create(:tree, cluster: cluster) }
    let!(:other_tree) { create(:tree, cluster: other_cluster) }

    it "scopes wallets to org for subscriber" do
      get "/wallets", headers: subscriber_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |w| w["id"] }
      expect(ids).to include(own_tree.wallet.id)
      expect(ids).not_to include(other_tree.wallet.id)
    end

    it "scopes wallets to own org for admin (org-scoped, not platform)" do
      get "/wallets", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |w| w["id"] }
      expect(ids).to include(own_tree.wallet.id)
      expect(ids).not_to include(other_tree.wallet.id)
    end

    # [SEC.25 Ф2] Єдиний приклад цієї осі, що йде РЕАЛЬНИМ HTTP-шляхом, тож він і несе
    # присуд: платформена роль сама по собі більше не відмикає чужі гаманці. Раніше
    # тут стояло «returns all wallets for super_admin (platform-wide)» — і це було
    # правдою.
    #
    # Bearer-запит cookie-сесії не носить, тобто acting-організації не обрано, і
    # контекст деградує до власної організації super_admin'а. Фабрика дає йому ВЛАСНУ,
    # третю організацію — тому чесна відповідь тут порожня, а не «усі». Саме ця
    # порожнеча і є доказом: доти той самий запит віддавав обидва чужі гаманці.
    it "не віддає super_admin чужих гаманців лише за роллю" do
      get "/wallets", headers: super_admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      ids = response.parsed_body["data"].map { |w| w["id"] }
      expect(ids).not_to include(own_tree.wallet.id)
      expect(ids).not_to include(other_tree.wallet.id)
    end
  end
end
