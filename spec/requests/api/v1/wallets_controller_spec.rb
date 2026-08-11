# SPDX-License-Identifier: AGPL-3.0-or-later
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

  describe "GET /wallets" do
    context "when as admin" do
      let(:admin) { create(:user, :admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }

      it "returns paginated wallets" do
        get "/wallets", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("pagy")
        expect(response.parsed_body["pagy"]).to include("page", "count", "pages")
      end
    end

    context "when as super_admin" do
      let(:super_admin) { create(:user, :super_admin, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{super_admin.generate_token_for(:api_access)}" } }

      it "returns paginated wallets" do
        get "/wallets", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("pagy")
      end
    end

    context "when as regular user" do
      let(:user) { create(:user, organization: organization) }
      let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

      # 🔴 [TEST.12 вісь D] Доти приклад стверджував тенант-ізоляцію ІМЕНЕМ, а міряв
      # `:ok` + наявність ключа `pagy` — тобто лишався зеленим і зі знятим
      # `policy_scope`. Другий, тихіший бік: у фікстурі не існувало ЧУЖОГО гаманця
      # взагалі, тож і пін на вміст не мав би що ловити — назва обіцяла «лише свої»
      # там, де інших не було в природі. Обидві половини потрібні разом.
      #
      # ⚠️ Гаманець тут не створюється прямо: `Tree#build_default_wallet` робить його
      # сам і бере організацію з `cluster&.organization` — тобто чужий гаманець мусить
      # народитись від чужого дерева, інакше фікстура опише звʼязок, якого модель не дає.
      it "returns only organization wallets with pagination" do
        foreign_tree = create(:tree, cluster: create(:cluster, organization: create(:organization)))

        get "/wallets", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key("pagy")

        ids = response.parsed_body["data"].map { |w| w["id"] }
        expect(ids).to include(wallet.id)
        expect(ids).not_to include(foreign_tree.wallet.id)
      end
    end
  end

  describe "GET /wallets/:id" do
    let(:user) { create(:user, organization: organization) }
    let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

    it "returns wallet with paginated transactions" do
      get "/wallets/#{wallet.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("data")
      expect(response.parsed_body).to have_key("transactions")
      expect(response.parsed_body).to have_key("pagy")
    end

    # Крос-org відмова. Це ЄДИНИЙ ендпоінт-показ у застосунку, чий `find` НЕ
    # скоуплений організацією (`Wallet.find(params[:id])`) — tenancy тримає лише
    # `authorize @wallet`, а `wallets.id` послідовний, тобто перебирається. Сусіди
    # (clusters/gateways/actuators/alerts) дзеркальний приклад мають, гаманці — ні,
    # і policy-спека його не замінює: вона кличе політику напряму, минаючи контролер,
    # тож зняття `authorize` лишало б зеленим і її, і решту сюїти.
    # HTML-гілку пінимо окремо (SEC.25): саме вона віддає ПІДПИСАНЕ ім'я стріму
    # `[wallet, :transactions]`, а підписане ім'я — безстроковий capability-токен,
    # тож витік їде вебсокетом уже ПІСЛЯ того, як HTTP-відповідь закрилась.
    context "when the wallet belongs to another organization" do
      let(:other_tree) { create(:tree, cluster: create(:cluster, organization: create(:organization))) }
      let!(:foreign_wallet) { other_tree.wallet || create(:wallet, tree: other_tree) }

      it "denies the JSON read" do
        get "/wallets/#{foreign_wallet.id}", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "denies the HTML read and hands out no live subscription" do
        get "/wallets/#{foreign_wallet.id}", headers: headers.merge("Accept" => "text/html")
        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include("turbo-cable-stream-source")
      end
    end
  end

  context "with format.html responses" do
    let(:admin) { create(:user, :admin, organization: organization) }
    let(:html_headers) do
      { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}", "Accept" => "text/html" }
    end

    it "renders HTML for index" do
      get "/wallets", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for show with crypto_public_address present" do
      wallet.update!(crypto_public_address: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12")
      get "/wallets/#{wallet.id}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end

  describe "HTML show with nil crypto_public_address" do
    let(:admin) { create(:user, :admin, organization: organization, password: "password12345") }

    it "renders HTML for show when crypto_public_address is nil" do
      wallet.update!(crypto_public_address: nil)

      get "/wallets/#{wallet.id}",
        headers: {
          "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}",
          "Accept" => "text/html"
        }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end

  describe "GET /wallets/:id/balance" do
    let(:admin) { create(:user, :admin, organization: organization) }
    let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }

    it "renders balance Turbo Frame for HTML" do
      allow_any_instance_of(Wallets::BalanceFrame).to receive(:template) { |c| c.plain "balance" }

      get "/wallets/#{wallet.id}/balance", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON with balance data" do
      get "/wallets/#{wallet.id}/balance", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data).to include("id", "scc_balance", "locked_balance", "available_balance", "esg_retired_balance")
      expect(data["id"]).to eq(wallet.id)
      expect(data["scc_balance"].to_d).to eq(wallet.scc_balance)
      expect(data["available_balance"].to_d).to eq(wallet.available_balance)
    end

    # [SEC.25] `balance?` делегує `show?`, тобто захист СПІЛЬНИЙ — і саме тому
    # доказ був лише в `show`, а тут його не було: контролер вантажить запис голим
    # `Wallet.find(params[:id])` у ВСІХ трьох екшенах, тож будь-яке звуження, зроблене
    # у `show?`, мовчки визначає й ці два. Пін на екшен, а не на політику: класифікація
    # по ФАЙЛУ склеїла б їх із `show` і показала б поверхню покритою.
    context "when the wallet belongs to another organization" do
      let(:other_tree) { create(:tree, cluster: create(:cluster, organization: create(:organization))) }
      let!(:foreign_wallet) { other_tree.wallet || create(:wallet, tree: other_tree) }

      it "denies the balance read in both formats" do
        get "/wallets/#{foreign_wallet.id}/balance", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)

        get "/wallets/#{foreign_wallet.id}/balance", headers: headers.merge("Accept" => "text/html")
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /wallets/:id/metadata" do
    let(:admin) { create(:user, :admin, organization: organization) }
    let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }

    it "renders metadata Turbo Frame for HTML" do
      allow_any_instance_of(Wallets::MetadataFrame).to receive(:template) { |c| c.plain "metadata" }

      get "/wallets/#{wallet.id}/metadata", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON with metadata" do
      get "/wallets/#{wallet.id}/metadata", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data).to include("id", "crypto_public_address", "locked_balance", "available_balance", "esg_retired_balance", "network")
      expect(data["network"]).to eq("Polygon PoS (Mainnet)")
      expect(data["crypto_public_address"]).to eq(wallet.crypto_public_address)
    end

    # [SEC.25] Дзеркало піна на `balance` — і тут ставка вища: цей екшен віддає
    # `crypto_public_address` чужої організації, тобто адресу гаманця на публічному
    # ланцюзі. Захист той самий (`metadata?` → `show?`), доказ доти був відсутній.
    context "when the wallet belongs to another organization" do
      let(:other_tree) { create(:tree, cluster: create(:cluster, organization: create(:organization))) }
      let!(:foreign_wallet) { other_tree.wallet || create(:wallet, tree: other_tree) }

      it "denies the metadata read in both formats" do
        get "/wallets/#{foreign_wallet.id}/metadata", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
        # ⚠️ НЕ `not_to include(foreign_wallet.crypto_public_address)`: гаманець
        # створює колбек `Tree#build_default_wallet`, а не фабрика, тож адреса там
        # `nil` → `.to_s` = `""` → `include("")` істинне ЗАВЖДИ, і пін падав би
        # незалежно від поведінки коду. Пінимо відсутність корисного навантаження.
        expect(response.parsed_body).not_to have_key("data")

        get "/wallets/#{foreign_wallet.id}/metadata", headers: headers.merge("Accept" => "text/html")
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # [I18N.2 · клас 2] Ендпоінт існує рівно для того, щоб броадкаст рядка не ніс
  # перекладеної прози: комірку статусу кожен глядач тягне СВОЇМ запитом, тобто
  # у своїй локалі й зі своєю авторизацією.
  #
  # 🔴 Жоден гейт цієї поверхні не вимагає: `broadcast_payload_invariance_spec`
  # до дочірніх компонентів сліпий, `turbo_stream_scope_spec` нових підписок не
  # бачить (їх і немає). Тож доказ тут — не формальність, а єдине, що стоїть між
  # цією коміркою й тихим крос-тенантним читанням.
  describe "GET /wallets/:wallet_id/transactions/:id/status" do
    let(:admin) { create(:user, :admin, organization: organization) }
    let(:headers) { { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}" } }
    let!(:transaction) { create(:blockchain_transaction, wallet: wallet, status: :confirmed) }

    # ⚠️ Локаль ведемо COOKIE, а не заголовком `Accept-Language`, і це не смак:
    # виміряно 2026-08-06, що третій щабель `LocaleSettable#resolve_locale` мертвий —
    # `request.preferred_language` у цьому дереві не існує (гема немає), а гард
    # `return nil unless request.respond_to?(:preferred_language)` ковтає це мовчки.
    # Cookie — саме той шлях, яким локаль приходить у проді (її ставить перемикач).
    it "renders the status frame with the badge in the VIEWER's locale" do
      cookies[:locale] = "uk"

      get "/wallets/#{wallet.id}/transactions/#{transaction.id}/status",
          headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="tx_status_frame_#{transaction.id}"))
      expect(response.body).to include(I18n.t("ui.status.confirmed", locale: :uk))
      # Відповідь БЕЗ `src` — інакше Turbo впізнає self-referencing фрейм, тихо
      # лишить його порожнім і напише `references itself` лише в консоль.
      expect(response.body).not_to include("src=")
    end

    # Вісь тенантності: те саме право, що й сторінка (`transaction_status? = show?`).
    context "when the wallet belongs to another organization" do
      let(:other_tree) { create(:tree, cluster: create(:cluster, organization: create(:organization))) }
      let!(:foreign_wallet) { other_tree.wallet || create(:wallet, tree: other_tree) }
      let!(:foreign_tx) { create(:blockchain_transaction, wallet: foreign_wallet) }

      it "denies the read" do
        get "/wallets/#{foreign_wallet.id}/transactions/#{foreign_tx.id}/status",
            headers: headers.merge("Accept" => "text/html")

        expect(response).to have_http_status(:forbidden)
      end
    end

    # 🔴 Друга вісь, і вона НЕ покривається першою: гаманець свій, транзакція чужа.
    # Скоуп тут дає асоціація (`@wallet.blockchain_transactions`), а не політика,
    # тож пін мусить бити саме в неї — інакше id чужої транзакції рендерився б
    # у власному фреймі глядача.
    it "404s on a transaction that belongs to a different wallet" do
      other_tree = create(:tree, cluster: cluster)
      other_wallet = other_tree.wallet || create(:wallet, tree: other_tree)
      foreign_tx = create(:blockchain_transaction, wallet: other_wallet)

      get "/wallets/#{wallet.id}/transactions/#{foreign_tx.id}/status",
          headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:not_found)
    end
  end
end
