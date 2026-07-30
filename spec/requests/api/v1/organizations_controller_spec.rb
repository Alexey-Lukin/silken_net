# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrganizationsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  describe "GET /api/v1/organizations" do
    context "when as a super_admin" do
      let(:super_admin) { create(:user, :super_admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

      it "returns organizations list" do
        get "/api/v1/organizations", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context "when as a regular admin" do
      let(:admin) { create(:user, :admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }

      it "returns forbidden" do
        get "/api/v1/organizations", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when as a regular user" do
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

  context "with format.html responses" do
    let(:super_admin) { create(:user, :super_admin, organization: organization) }
    let(:html_headers) do
      { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/api/v1/organizations", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/api/v1/organizations/#{organization.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end

  # [SEC.25 Ф2] Ці приклади ходять cookie-СЕСІЄЮ, а не Bearer'ом, і це не стиль:
  # носій acting-організації — сесія, тож Bearer-запит її не має за побудовою, і
  # перемикання на ньому не перевіряється взагалі.
  describe "POST /api/v1/organizations/:id/switch" do
    let!(:super_admin) { create(:user, :super_admin, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_organization) }
    let!(:other_tree) { create(:tree, cluster: other_cluster) }

    before do
      allow_any_instance_of(Tree).to receive(:broadcast_map_update)
      allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
      post "/api/v1/login",
           params: { email: super_admin.email_address, password: "password12345" },
           as: :json
    end

    # 🔴 ЦЕЙ приклад — головний, бо він єдиний пінить ПОВНИЙ ланцюг
    # «контролер → pundit_user → acting-організація → дані».
    # Без нього мутація `pundit_user` → `current_user` (контекст геть) лишає всю
    # сюїту зеленою: у фікстурах super_admin має власну організацію, тож хибний
    # вибір і правильний дають однакову — порожню — відповідь. Тут вони РІЗНІ.
    it "перемикає те, що користувач реально бачить" do
      get "/api/v1/wallets", as: :json
      expect(response.parsed_body["data"].map { |w| w["id"] }).not_to include(other_tree.wallet.id)

      post "/api/v1/organizations/#{other_organization.id}/switch", as: :json
      expect(response).to have_http_status(:ok)

      get "/api/v1/wallets", as: :json
      expect(response.parsed_body["data"].map { |w| w["id"] }).to include(other_tree.wallet.id)
    end

    it "лишає слід у журналі організації, КУДИ входять — синхронно, до мутації сесії" do
      expect {
        post "/api/v1/organizations/#{other_organization.id}/switch", as: :json
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.order(:id).last
      expect(log.action).to eq("acting_organization_switched")
      expect(log.user_id).to eq(super_admin.id)
      # Саме тієї організації, чиї дані читатимуть, — інакше вона бачила б наслідки
      # без запису про те, хто прийшов.
      expect(log.organization_id).to eq(other_organization.id)
      expect(log.metadata["from_organization_id"]).to eq(organization.id)
      # Ланцюг рахується в `before_create` — тобто рядок реальний, а не в черзі.
      expect(log.chain_hash).to be_present
    end

    # За seeds людський super_admin створюється БЕЗ організації — тобто це не
    # екзотика, а типовий перший вхід: домашньої організації немає, і перше
    # перемикання йде «нізвідки».
    it "працює для super_admin без домашньої організації" do
      homeless = create(:user, :super_admin, organization: nil)
      post "/api/v1/login",
           params: { email: homeless.email_address, password: "password12345" },
           as: :json

      post "/api/v1/organizations/#{other_organization.id}/switch", as: :json

      expect(response).to have_http_status(:ok)
      expect(AuditLog.order(:id).last.metadata["from_organization_id"]).to be_nil
    end

    # Bearer сесії не носить, тож запис у неї нікуди б не поїхав: клієнт дістав би
    # 200 і нульовий ефект. Чесна відмова замість no-op'у, що виглядає як успіх.
    it "відмовляє на Bearer-запиті, бо носій контексту — сесія" do
      post "/api/v1/organizations/#{other_organization.id}/switch",
           headers: { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" },
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    # Резолвер мусить відкотитись на власну організацію, а не впасти, якщо
    # acting-організації більше немає.
    #
    # ⚠️ Знадобилось обійти аудит-ланцюг, і це саме по собі знахідка: `organizations`
    # має `has_many :audit_logs, dependent: :restrict_with_error`, а перемикання
    # ЗАВЖДИ лишає там запис — тобто організація, в яку хтось перемкнувся, стає
    # нищівно-захищеною. Продовим шляхом ця гілка недосяжна; вона лишається як
    # страхування на випадок ручного втручання в БД, і саме тому перевіряється
    # штучно, а не через `destroy!`.
    it "відкочується на власну організацію, якщо acting-організації більше немає" do
      post "/api/v1/organizations/#{other_organization.id}/switch", as: :json

      # [⚖️ 2026-07-30] Порядок тепер несучий: `Cluster has_many :trees` і
      # `Organization has_many :clusters` — обидва `restrict_with_error`, тож розбирати
      # треба знизу вгору. Це й є доказ присуду в дії: організацію з живим залізом
      # знищити не можна навіть штучно.
      other_tree.destroy!
      other_cluster.destroy!
      AuditLog.where(organization_id: other_organization.id).delete_all
      other_organization.destroy!

      get "/api/v1/wallets", as: :json

      expect(response).to have_http_status(:ok)
    end

    it "не дає перемкнутись звичайному адміністраторові" do
      admin = create(:user, :admin, organization: organization)
      post "/api/v1/login",
           params: { email: admin.email_address, password: "password12345" },
           as: :json

      post "/api/v1/organizations/#{other_organization.id}/switch", as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
