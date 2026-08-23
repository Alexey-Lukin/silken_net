# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrganizationsController, type: :request do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  describe "GET /organizations" do
    context "when as a super_admin" do
      let(:super_admin) { create(:user, :super_admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

      # 🔴 [TEST.12 вісь D] Доти приклад звався «returns organizations list» і міряв
      # лише `:ok` — тобто був зелений і на порожньому тілі, і на зламаному Blueprint'і.
      # ⚠️ Але вісь тут ІНША, ніж у `wallets`: реєстр кланів глобальний СВІДОМО —
      # `Organization.all` під `authorize_super_admin!` — бо саме він живить перемикач
      # контексту [SEC.25 Ф2]. Тож пін закріплює НАВМИСНУ глобальність: чужа
      # організація мусить бути ВИДИМОЮ, і «дбайливе» скоупення тут зламає перемикач.
      it "returns the global registry, not only the acting organization" do
        other_organization = create(:organization)

        get "/organizations", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        names = response.parsed_body["data"].map { |o| o["name"] }
        expect(names).to include(organization.name, other_organization.name)
      end
    end

    context "when as a regular admin" do
      let(:admin) { create(:user, :admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }

      it "returns forbidden" do
        get "/organizations", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when as a regular user" do
      let(:user) { create(:user, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

      it "returns forbidden" do
        get "/organizations", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /organizations/:id" do
    let(:super_admin) { create(:user, :super_admin, organization: organization) }
    let(:headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

    it "uses cached_trees_count for performance" do
      get "/organizations/#{organization.id}", headers: headers, as: :json
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
      get "/organizations", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show" do
      get "/organizations/#{organization.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    # [UI.6] ПОЗИТИВНИЙ пін проводки `acting_organization:` — і він тут єдиний
    # можливий. Дефолт `nil` у компонента означає легітимне «контекст не обрано»
    # (перший вхід super_admin іде без організації), тобто забута проводка
    # невідрізненна від правди: кнопки просто з'являються на всіх рядках, і жоден
    # НЕГАТИВНИЙ приклад не червоніє. Червоніє лише твердження, що маркер Є там,
    # де він мусить бути.
    # [UI.6] Проводка в `show` — четверта поверхня, і доти вона була ЄДИНОЮ
    # незапіненою: компонентна спека передає kwarg сама, а request-приклад
    # перевіряв лише 200 + content-type. Тобто заява «кожна проводка
    # mutation-verified» була ширша за зроблене рівно на цей екшен.
    it "позначає профіль клану, в контексті якого super_admin працює" do
      get "/organizations/#{organization.id}", headers: html_headers

      expect(response.body).to include("ACTIVE_CONTEXT")
    end

    it "позначає рядок організації, в контексті якої super_admin працює" do
      get "/organizations", headers: html_headers

      expect(response.body).to include("ACTIVE_CONTEXT")
      expect(response.body).not_to include(%(action="#{switch_organization_path(organization)}"))
    end
  end

  # [SEC.25 Ф2] Ці приклади ходять cookie-СЕСІЄЮ, а не Bearer'ом, і це не стиль:
  # носій acting-організації — сесія, тож Bearer-запит її не має за побудовою, і
  # перемикання на ньому не перевіряється взагалі.
  describe "POST /organizations/:id/switch" do
    let!(:super_admin) { create(:user, :super_admin, organization: organization) }
    let(:other_cluster) { create(:cluster, organization: other_organization) }
    let!(:other_tree) { create(:tree, cluster: other_cluster) }

    before do
      silence_broadcasts!(:tree_map, :wallet_balance)
      sign_in_via_form(super_admin, password: "password12345", as: :json)
    end

    # 🔴 ЦЕЙ приклад — головний, бо він єдиний пінить ПОВНИЙ ланцюг
    # «контролер → pundit_user → acting-організація → дані».
    # Без нього мутація `pundit_user` → `current_user` (контекст геть) лишає всю
    # сюїту зеленою: у фікстурах super_admin має власну організацію, тож хибний
    # вибір і правильний дають однакову — порожню — відповідь. Тут вони РІЗНІ.
    it "перемикає те, що користувач реально бачить" do
      get "/wallets", as: :json
      expect(response.parsed_body["data"].map { |w| w["id"] }).not_to include(other_tree.wallet.id)

      post "/organizations/#{other_organization.id}/switch", as: :json
      expect(response).to have_http_status(:ok)

      get "/wallets", as: :json
      expect(response.parsed_body["data"].map { |w| w["id"] }).to include(other_tree.wallet.id)
    end

    it "лишає слід у журналі організації, КУДИ входять — синхронно, до мутації сесії" do
      expect {
        post "/organizations/#{other_organization.id}/switch", as: :json
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
      sign_in_via_form(homeless, password: "password12345", as: :json)

      post "/organizations/#{other_organization.id}/switch", as: :json

      expect(response).to have_http_status(:ok)
      expect(AuditLog.order(:id).last.metadata["from_organization_id"]).to be_nil
    end

    # 🔴 Браузерна гілка — доти не виконана ЖОДНИМ прикладом, і саме тому в ній жив
    # `root_path`, якого в цьому застосунку не існує (корінь оголошено всередині
    # `namespace :api → :v1`). `rescue_from StandardError` перетворював це на 500:
    # перемикання відбувалось, а користувач бачив помилку. Пін навмисно на ТОЧНИЙ
    # код і ТОЧНУ ціль: `have_http_status(:redirect)` пропустив би будь-який 3xx, а
    # префікс — будь-який шлях, що з нього починається.
    it "віддає браузеру 303 на корінь дашборда" do
      post "/organizations/#{other_organization.id}/switch",
           headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with(root_path)
      # [SEC.25 Ф3] Доти перемикання було НІМИМ, тобто для скрінрідера зміна
      # тенант-контексту не оголошувалась узагалі. Без цього рядка `success:`
      # можна зняти й приклад лишиться зеленим — статус і ціль від нього не
      # залежать. Категорія саме `success` (polite): assertive на рутинному
      # перемиканні перебивав би мовлення.
      expect(flash[:success]).to include(other_organization.name)
    end

    # Bearer сесії не носить, тож запис у неї нікуди б не поїхав: клієнт дістав би
    # 200 і нульовий ефект. Чесна відмова замість no-op'у, що виглядає як успіх.
    it "відмовляє на Bearer-запиті, бо носій контексту — сесія" do
      post "/organizations/#{other_organization.id}/switch",
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
      # 🔴 [TEST.12 вісь D] Доти пін був `have_http_status(:ok)` — тобто міряв, що
      # резолвер не ВПАВ, і мовчав про те, чия організація стала чинною. Третій
      # клан тут несучий: без нього «відкотився на власну» не відрізнити від
      # «узяв першу-ліпшу живу», бо фолбек `current_user.organization` і будь-яка
      # інша жива організація дають однаково успішні 200.
      own_tree = create(:tree, cluster: create(:cluster, organization: organization))
      stranger_tree = create(:tree, cluster: create(:cluster, organization: create(:organization)))

      post "/organizations/#{other_organization.id}/switch", as: :json

      # [⚖️ 2026-07-30] Порядок тепер несучий: `Cluster has_many :trees` і
      # `Organization has_many :clusters` — обидва `restrict_with_error`, тож розбирати
      # треба знизу вгору. Це й є доказ присуду в дії: організацію з живим залізом
      # знищити не можна навіть штучно.
      other_tree.destroy!
      other_cluster.destroy!
      AuditLog.where(organization_id: other_organization.id).delete_all
      other_organization.destroy!

      get "/wallets", as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["data"].map { |w| w["id"] }
      expect(ids).to include(own_tree.wallet.id)
      expect(ids).not_to include(stranger_tree.wallet.id)
    end

    it "не дає перемкнутись звичайному адміністраторові" do
      admin = create(:user, :admin, organization: organization)
      sign_in_via_form(admin, password: "password12345", as: :json)

      post "/organizations/#{other_organization.id}/switch", as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
