# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.7] Контракт `04_03 §3.1`, політика (1): **тенантний ресурс + актор без
# організації → однакове `422 no_organization`**.
#
# Асоціативний контур виконував його з дня ратифікації (30+ сайтів кличуть
# `acting_organization!`), а Pundit-контур не проходив ніхто — і на одній
# порожнечі контексту три його контролери давали ЧОТИРИ різні відповіді:
# 200 зі списком платформених користувачів (`users#index`) · 403 на кожному з
# них (`users#show`) · 200 із порожнім реєстром (`wallets#index`, `contracts#index`) ·
# 404 (`contracts#show`). Рівно ті «три різні поведінки одного сімейства
# сторінок», які §3.1 оголосив знятими.
#
# 🔴 Чому пін живе ОКРЕМИМ файлом, а не рядками в трьох контролер-спеках:
# предмет тут — ЗГОДА трьох поверхонь, а не поведінка кожної. Пін усередині
# одного контролера самоузгоджений і сліпий до розходження з сусідом — рівно та
# форма, що вже коштувала на `Gateway#online?` (три відповіді на одне питання,
# кожен рендер окремо чесний).
RSpec.describe "Acting-organization contract (Pundit contour)", type: :request do
  # ЄДИНИЙ дім переліку: обидві половини доказу (відмова ⊥ дозвіл) ітерують саме
  # його, інакше додана поверхня мовчки дістала б лише одну з них.
  # ⚠️ Локальна змінна, а не константа: константа в `describe` тече на ВЕСЬ прогін
  # (`RSpec/LeakyConstantDeclaration`), а замикання блоку тут дає рівно те саме.
  tenant_surfaces = %w[
    users_index
    user_show
    wallets_index
    wallet_show
    wallet_balance
    wallet_metadata
    contracts_index
    contract_show
    contracts_stats
  ].freeze

  before do
    silence_broadcasts!(:wallet_balance, :tree_map)
  end

  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let!(:wallet) { tree.wallet || create(:wallet, tree: tree) }
  let!(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }
  let!(:org_member) { create(:user, :forester, organization: organization) }

  # ⚠️ Ліхтар на НАСЕЛЕННЯ, яке регресія витікала б. Без нього `422` не
  # відрізнити від «показувати нема чого»: `UserPolicy::Scope` на порожньому
  # контексті будував `WHERE organization_id IS NULL`, тобто фільтр, що
  # ЗБІГАЄТЬСЯ з org-less рядками. У проді їх двоє — сіджений super_admin і
  # `oracle_executioner`; тут теж двоє свідомо, бо на одному рядку клас «список,
  # який неможливо відкрити» ще читається як «один випадковий запис».
  let!(:platform_admin) { create(:user, :super_admin, organization: nil) }
  let!(:platform_operator) { create(:user, :super_admin, organization: nil) }

  let(:headers) { { "Authorization" => "Bearer #{platform_admin.generate_token_for(:api_access)}" } }

  # Позитивний контроль: ТА САМА роль, але з організацією. Без нього «гейт
  # реагує на відсутній контекст» не відрізнити від «гейт реагує на super_admin'а»
  # — тобто від гейта, надто широкого рівно на один крок.
  let(:contextual_admin) { create(:user, :super_admin, organization: organization) }
  let(:contextual_headers) do
    { "Authorization" => "Bearer #{contextual_admin.generate_token_for(:api_access)}" }
  end

  def path_for(surface)
    {
      "users_index" => "/users",
      "user_show" => "/users/#{org_member.id}",
      "wallets_index" => "/wallets",
      "wallet_show" => "/wallets/#{wallet.id}",
      "wallet_balance" => "/wallets/#{wallet.id}/balance",
      "wallet_metadata" => "/wallets/#{wallet.id}/metadata",
      "contracts_index" => "/contracts",
      "contract_show" => "/contracts/#{contract.id}",
      "contracts_stats" => "/contracts/stats"
    }.fetch(surface)
  end

  # Реєстр поверхонь вище — рукописний, тож четвертий Pundit-контролер утік би
  # ТИХО: він не почервонив би нічого, а просто лишився б непокритим. Ліхтар
  # ключується на файловій системі, тобто на джерелі, якого сам перелік не
  # породжує — інакше обидва боки звіряння мали б спільне походження й розбіжність
  # була б недосяжна за побудовою.
  it "covers every controller that reaches for Pundit" do
    pundit_callers = Dir[Rails.root.join("app/controllers/api/v1/*.rb")].select do |file|
      File.read(file).match?(/^\s*(?:@?\w+\s*=\s*)?(?:policy_scope\(|authorize\s)/)
    end.map { |file| File.basename(file, "_controller.rb") }

    expect(pundit_callers).to match_array(%w[contracts users wallets])
  end

  describe "an actor without an acting organization" do
    it "carries a population a regression would expose" do
      expect(User.where(organization_id: nil).count).to be >= 2
      expect(Wallet.count).to be_positive
      expect(NaasContract.count).to be_positive
    end

    tenant_surfaces.each do |surface|
      it "answers #{surface} with 422 no_organization" do
        get path_for(surface), headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["code"]).to eq("no_organization")
      end
    end

    # Той самий гард, окремим прикладом: шлях будується з `wallet_id`, тож
    # промах у ньому не спіймався б жодним із дев'яти вище.
    it "answers wallet_transaction_status with 422 no_organization" do
      get "/wallets/#{wallet.id}/transactions/1/status",
          params: { created_at: Time.current.iso8601 },
          headers: headers,
          as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("no_organization")
    end

    # [SEC.25] HTML-гілка несуча окремо: без неї браузерний глядач діставав би
    # сирий JSON-блоб замість сторінки (`04_03 §2.2б`, скіл `backend` #24).
    it "renders the no-organization PAGE for a browser, not a JSON blob" do
      get "/users", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
    end
  end

  describe "the same role WITH an acting organization" do
    tenant_surfaces.each do |surface|
      it "still serves #{surface}" do
        get path_for(surface), headers: contextual_headers, as: :json

        expect(response).to have_http_status(:ok)
      end
    end
  end

  # `users#me` — свідомий НЕ-член класу: питання «хто я» тенанта не потребує, і
  # `Errors::NoOrganization` [UI.6] саме звідси веде super_admin'а в реєстр
  # кланів. Якби гард поїхав у `before_action`, першою жертвою став би цей екшен
  # — тобто вихід зі стану «немає контексту» зник би разом із входом у нього.
  describe "the deliberate non-member of the class" do
    it "serves users#me without an acting organization" do
      get "/users/me", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(platform_admin.id)
    end
  end
end
