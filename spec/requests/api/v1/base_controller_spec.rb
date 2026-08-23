# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BaseController, type: :request do
  # Ці приклади пінять ДИСПЕТЧЕР — «гард кличе відмову», — а не її форму. Форму
  # (JSON проти сторінки) пінить request-рівень: `settings_controller_spec` має
  # обидві гілки формату, відколи [UI.9] дав `render_forbidden` HTML-половину.
  #
  # ⚠️ `and_call_original` тут стояв і був знятий свідомо: він виконував справжній
  # `render_forbidden` у контролері, зібраному через `described_class.new`, де
  # `request` — nil, а `render` застабано. Тобто нічого не доводив, зате після
  # [UI.9] почав падати на `respond_to`, який лізе в `request.formats`.
  describe "RBAC helpers" do
    let(:controller) { described_class.new }

    before do
      allow(controller).to receive(:render)
      allow(controller).to receive(:render_forbidden)
    end

    describe "authorize_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        controller.send(:authorize_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_super_admin! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        controller.send(:authorize_super_admin!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! when current_user is nil" do
      it "calls render_forbidden" do
        allow(controller).to receive(:current_user).and_return(nil)
        controller.send(:authorize_forester!)
        expect(controller).to have_received(:render_forbidden)
      end
    end

    describe "authorize_admin! with admin user" do
      it "does not call render_forbidden" do
        admin = create(:user, :admin)
        allow(controller).to receive(:current_user).and_return(admin)
        controller.send(:authorize_admin!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end

    describe "authorize_forester! with forester user" do
      it "does not call render_forbidden" do
        forester = create(:user, :forester)
        allow(controller).to receive(:current_user).and_return(forester)
        controller.send(:authorize_forester!)
        expect(controller).not_to have_received(:render_forbidden)
      end
    end
  end

  # [SEC.25] Приклади ходять справжнім HTTP свідомо: доти вони будували контролер через
  # `described_class.new` і стабили `render`, а `respond_to` лізе в `request.formats` —
  # у такому харнесі він падає `NoMethodError` на nil, тобто «доводив» би відсутність
  # диспетчера, а не поведінку. Той самий прецедент, що в блоках нижче.
  describe "render_internal_server_error" do
    let(:user) { create(:user, :forester, organization: create(:organization)) }
    let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

    before do
      # Стаб на дію, а не на модель: `dashboard#index` не має record-гардів у
      # `before_action`, тож виняток долітає саме до `rescue_from StandardError`,
      # а не перехоплюється раніше (на `trees#index` він давав 404 від `set_cluster`).
      allow_any_instance_of(Api::V1::DashboardController)
        .to receive(:index).and_raise(StandardError, "test failure")
      allow(Rails.logger).to receive(:fatal)
    end

    it "віддає 500 JSON на API-запит і логує деталі" do
      get "/dashboard", headers: headers, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["error"]).to be_present
      expect(Rails.logger).to have_received(:fatal).with(/API CRITICAL/)
    end

    it "віддає HTML-сторінку на браузерний запит, не JSON-блоб" do
      get "/dashboard", headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:internal_server_error)
      expect(response.media_type).to eq("text/html")
      # 🔴 Пін на ФОРМУ, не на статус: статус не змінювався, тож пін на 500 лишався б
      # зеленим і на старій, зламаній поведінці. Плюс негативна половина — саме сирий
      # блоб був симптомом.
      expect(response.body).to include("<html")
      expect(response.body).not_to include('{"error"')
    end

    # ⚠️ Цей рендерер — ЄДИНИЙ із трьох в auth-шаблоні, і причина в тому, що сюди
    # приходять і запити БЕЗ `current_user`. Пін тримає саме цю властивість: сторінка
    # мусить домалюватись без сайдбара й бейджа, тобто без залежностей від користувача.
    it "не тягне дашборд-хром, бо сюди приходять і запити без користувача" do
      get "/dashboard", headers: headers.merge("Accept" => "text/html")

      expect(response.body).not_to include("sidebar-navigation")
    end
  end

  describe "signed_in? helper" do
    it "returns false when no user is authenticated" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(nil)
      expect(controller.send(:signed_in?)).to be false
    end

    it "returns true when user is authenticated" do
      organization = create(:organization)
      user_for_test = create(:user, organization: organization, password: "password12345")
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user_for_test)
      expect(controller.send(:signed_in?)).to be true
    end
  end

  describe "CSRF bypass for Bearer-token requests" do
    let(:controller) { described_class.new }

    it "lets Bearer-token requests through (CSRF check skipped)" do
      request = instance_double(ActionDispatch::Request, authorization: "Bearer abc.def.ghi")
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }.not_to raise_error
    end

    it "raises InvalidAuthenticityToken for session-cookie requests" do
      request = instance_double(ActionDispatch::Request, authorization: nil)
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }
        .to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "raises for non-Bearer auth schemes (Basic)" do
      request = instance_double(ActionDispatch::Request, authorization: "Basic dXNlcjpwYXNz")
      allow(controller).to receive(:request).and_return(request)
      expect { controller.send(:handle_unverified_request) }
        .to raise_error(ActionController::InvalidAuthenticityToken)
    end
  end

  # [UI.9] Обидва рендерери дістали `respond_to`, тож контролеру потрібен реальний
  # `request` — інакше диспетчер лізе в `request.formats` на nil. `TestRequest`
  # дешевший за повний HTTP там, де живого шляху до винятку немає.
  #
  # ⚠️ Тут доти стояло, що `ActiveModel::ValidationError` «кидають лише сервіси» —
  # грепом це неправда: `validate!` не зустрічається в дереві ЖОДНОГО разу, тож
  # виняток не кидає ніхто. `rescue_from` на нього знято [SEC.25]; сам рендерер
  # живий і викликається прямо, тому приклад лишається.
  describe "render_parameter_missing" do
    it "returns 400 with the missing param name" do
      controller = described_class.new
      controller.request = ActionDispatch::TestRequest.create
      controller.response = ActionDispatch::TestResponse.new
      controller.request.format = :json
      allow(controller).to receive(:render)
      exception = ActionController::ParameterMissing.new(:tree_id)

      controller.send(:render_parameter_missing, exception)
      expect(controller).to have_received(:render).with(
        hash_including(json: hash_including(:error), status: :bad_request)
      )
    end
  end

  describe "render_validation_error" do
    it "returns 422 with all validation messages" do
      controller = described_class.new
      controller.request = ActionDispatch::TestRequest.create
      controller.response = ActionDispatch::TestResponse.new
      controller.request.format = :json
      allow(controller).to receive(:render)
      record = OpenStruct.new(errors: OpenStruct.new(full_messages: [ "Name can't be blank", "Email is invalid" ]))

      controller.send(:render_validation_error, record)
      expect(controller).to have_received(:render).with(
        hash_including(
          json: { errors: [ "Name can't be blank", "Email is invalid" ] },
          status: :unprocessable_content
        )
      )
    end
  end

  # [SEC.25] Обидва блоки нижче — на справжньому HTTP з тієї самої причини, що й 500-блок.
  # Обидва рендерери йдуть у ДАШБОРД-шаблон (не в auth): сюди приходить автентифікований
  # користувач, якому просто не можна саме це або який вклацав протухле посилання, —
  # сайдбар йому чесний. Пін це й тримає, інакше «HTML» нічого не каже про те, ЯКИЙ HTML.
  describe "render_not_found" do
    let(:user) { create(:user, :forester, organization: create(:organization)) }
    let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

    it "віддає 404 JSON з іменем моделі на API-запит" do
      get "/trees/999999", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["error"]).to be_present
    end

    it "віддає HTML-сторінку в дашборд-шаблоні на браузерний запит" do
      get "/trees/999999", headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("<html")
      expect(response.body).not_to include('{"error"')
      # Саме дашборд, а не auth-шаблон — навігація тут доречна й це вимір, не смак.
      expect(response.body).to include("sidebar-navigation")
    end
  end

  describe "render_forbidden_pundit" do
    let(:user) { create(:user, :forester, organization: create(:organization)) }
    let(:headers) { { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" } }

    # `users#index` — живий Pundit-шлях: `UserPolicy#index?` = `admin_or_above?`,
    # тож форестер отримує `Pundit::NotAuthorizedError` без жодного стабу.
    it "віддає 403 JSON на API-запит" do
      get "/users", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["error"]).to be_present
    end

    it "віддає HTML-сторінку в дашборд-шаблоні на браузерний запит" do
      get "/users", headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:forbidden)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("<html")
      expect(response.body).not_to include('{"error"')
      expect(response.body).to include("sidebar-navigation")
    end
  end

  describe "pagy_metadata" do
    it "extracts page/limit/count/pages from a Pagy object" do
      controller = described_class.new
      pagy = OpenStruct.new(page: 2, limit: 21, count: 105, last: 5)
      meta = controller.send(:pagy_metadata, pagy)
      expect(meta).to eq(page: 2, limit: 21, count: 105, pages: 5)
    end
  end

  # Бейдж «Threat Alerts» рендериться на КОЖНІЙ сторінці дашборда, тож його число —
  # найширше розповсюджений тенант-факт у застосунку.
  # ⚠️ Раніше тут стояв приклад `allow(EwsAlert).to receive(:unresolved) → double(count: 7)`
  # з очікуванням `eq(7)`. Він був ВАКУУМНИЙ: стабив саме те, що перевіряв, тобто
  # стверджував лише «хелпер повертає те, що повертає його ж реалізація». Саме тому
  # відсутність org-скоупу була невидима — приклад не міг її виразити в принципі.
  describe "ews_alert_count_cached (sidebar badge)" do
    let(:org_a) { create(:organization) }
    let(:org_b) { create(:organization) }
    let(:user_a) { create(:user, :forester, organization: org_a) }
    let(:user_b) { create(:user, :forester, organization: org_b) }

    before do
      allow(AlertNotificationWorker).to receive(:perform_async)
      silence_broadcasts!(:alert_notify)
      Rails.cache.clear
      # Pause: `Tree.after_create` тягне wallet+calibration на кожне дерево фабрики —
      # це N+1 У ФІКСТУРІ, не в коді під тестом.
      Prosopite.pause if defined?(Prosopite)
      create(:ews_alert, cluster: create(:cluster, organization: org_a), status: :active)
      3.times { create(:ews_alert, cluster: create(:cluster, organization: org_b), status: :active) }
      Prosopite.resume if defined?(Prosopite)
    end

    def count_for(user)
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user)
      controller.send(:ews_alert_count_cached)
    end

    # Один приклад ловить ДВІ незалежні мутації, і порядок викликів тут несучий:
    # A прогріває кеш, перевіряється B. Скинути org-скоуп ЗАПИТУ → A віддасть 4;
    # повернути глобальний КЛЮЧ кешу → B віддасть закешоване число A. Двоє
    # глядачів обовʼязкові — з одним «4 замість 1» не відрізнити від правильного.
    it "counts only the viewer's own organization, and does not cache across organizations" do
      expect(count_for(user_a)).to eq(1)
      expect(count_for(user_b)).to eq(3)
    end

    # 🔴 [UI.11] Кеш гаситься НА ЗАПИСІ, не за часом — і пін мусить довести саме
    # НЕГАЙНІСТЬ, бо TTL цього не дає в принципі. Порядок несучий: перше читання
    # ПРОГРІВАЄ кеш, і без гасіння друге віддало б старе число — тобто зняття
    # `after_commit`-гасильника червонить приклад поіменно.
    #
    # ⚠️ Ключ навмисно НЕ пишеться тут рукою: він має один дім
    # (`Organization#alert_count_cache_key`), і пін, що знав би власну копію
    # рядка, лишався б зеленим при розходженні читача з гасильником.
    it "оновлює бейдж ОДРАЗУ після появи тривоги, не чекаючи TTL" do
      expect(count_for(user_a)).to eq(1) # прогріває кеш

      Prosopite.pause if defined?(Prosopite)
      create(:ews_alert, cluster: create(:cluster, organization: org_a), status: :active)
      Prosopite.resume if defined?(Prosopite)

      expect(count_for(user_a)).to eq(2)
    end

    # Дзеркальна половина: закриття тривоги теж мусить гасити кеш, інакше бейдж
    # завищує загрозу — а це той бік помилки, що змушує оператора шукати те,
    # чого немає.
    it "оновлює бейдж ОДРАЗУ після закриття тривоги" do
      alert = org_a.ews_alerts.first
      expect(count_for(user_a)).to eq(1)

      alert.update!(status: :resolved)

      expect(count_for(user_a)).to eq(0)
    end

    it "returns zero for a viewer without an organization (fail-closed, not a global sum)" do
      expect(count_for(create(:user, :super_admin, organization: nil))).to eq(0)
    end

    it "swallows any backend error and returns 0 so the sidebar never breaks" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user_a)
      allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "cache down")
      expect(controller.send(:ews_alert_count_cached)).to eq(0)
    end
  end

  # [SEC.25 Ф2] Доти ці приклади конструювали контролер напряму й стабали `render`,
  # `respond_to` і `current_user`, тобто перевіряли приватний метод у вакуумі —
  # вони лишались би зеленими, навіть якби гард узагалі не був підключений до
  # жодного запиту. Тепер це справжній HTTP-шлях: гард живе в ТОЧЦІ ЧИТАННЯ
  # організації, тож єдиний спосіб довести, що він працює, — прийти по-справжньому.
  describe "коли організації немає" do
    let(:user_without_org) { create(:user, :admin, organization: nil) }

    def sign_in_headers(user)
      { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}" }
    end

    it "віддає 422 з машинним кодом на JSON-запит" do
      get "/dashboard", headers: sign_in_headers(user_without_org), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("no_organization")
    end

    it "віддає HTML-сторінку з поясненням на браузерний запит" do
      get "/dashboard", headers: sign_in_headers(user_without_org).merge("Accept" => "text/html")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/html")
      # 🔴 Саме цей рядок відрізняє полагоджене від зламаного: доти ця сторінка
      # віддавала JSON-блоб у браузері (`render_internal_server_error` без
      # `respond_to`), і глядач бачив сирий `{"error":...}` замість сторінки.
      expect(response.body).to include("<html")
    end

    # [UI.6] ПОЗИТИВНЕ твердження, і воно тут єдине можливе: при fail-closed
    # дефолті (`current_user: nil` → виходу немає) негативний приклад лишається
    # зеленим і тоді, коли контролер перестав передавати актора взагалі. А
    # компонентна спека конструює сторінку повз `render_no_organization`, тож
    # проводки не бачить у принципі. Мутація «прибрати `current_user:`» червонить
    # рівно цей приклад.
    it "дає super_admin без організації двері в реєстр, а не лише вихід" do
      homeless_admin = create(:user, :super_admin, organization: nil)

      get "/dashboard", headers: sign_in_headers(homeless_admin).merge("Accept" => "text/html")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(href="#{organizations_path}"))
    end

    it "не заважає сторінкам, які організації не читають" do
      # Гард у точці читання не має списку винятків — сторінка, що org не питає,
      # його просто не тригерить. Мутація «повернути класовий before_action»
      # червонить саме цей приклад.
      #
      # ⚠️ Суб'єкт несучий, і його не можна «спростити». Треба сторінку, яка
      # (а) успадковує `BaseController` — інакше класовий before_action до неї
      # не дійшов би й мутація лишилась би зеленою, і (б) організації не читає.
      # `SessionsController < BaseController` зі `skip_before_action
      # :authenticate_user!` дає рівно це. ⛔ НЕ `/up`: `ReadinessController`
      # успадковує `ActionController::Base` напряму, тож приклад став би
      get "/login"

      expect(response).to have_http_status(:ok)
    end
  end

  # [UI.6] Проводка `acting_organization:` у `render_dashboard` — один вузол на всі
  # дашборд-рендери, тож і пін потрібен один. Але саме ПОЗИТИВНИЙ і саме на
  # сторінці, де організація гарантовано є: на реєстрі кланів `nil` — легітимний
  # стан, тож там забута проводка невідрізненна від правди.
  describe "індикатор контексту в layout" do
    it "доїжджає до топ-бара дашборда" do
      org = create(:organization, name: "Cherkasy Forest Union")
      admin = create(:user, :super_admin, organization: org)

      get "/dashboard",
          headers: { "Authorization" => "Bearer #{admin.generate_token_for(:api_access)}",
                     "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cherkasy Forest Union")
    end
  end

  # [SEC.25] Дзеркало блоку вище, на найширшому гарді застосунку: `authenticate_user!`
  # — `before_action` для всього дашборда, тож його форма відмови видима кожному
  # реальному користувачеві, чия сесія протермінувалась.
  #
  # ⚠️ Приклади ходять справжнім HTTP свідомо: решта цього файла будує контролер через
  # `described_class.new` і стабить `render`, а `respond_to` лізе в `request.formats` —
  # у такому харнесі він упав би `NoMethodError` на nil, тобто «доводив» би відсутність
  # диспетчера, а не поведінку.
  describe "коли автентифікації немає" do
    it "віддає 401 JSON на API-запит" do
      get "/dashboard", as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["error"]).to be_present
    end

    it "віддає сторінку ЛОГІНУ на браузерний запит, зберігаючи 401" do
      get "/dashboard", headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("text/html")
      # 🔴 Пін саме на ФОРМУ входу, не на «якийсь HTML»: доти браузер діставав сирий
      # `{"error":...}` першою ж дією після протермінування сесії. І не на статус —
      # він тут НЕ змінювався, тож пін на 401 лишався б зеленим і на зламаній
      # поведінці (рівно та вакуумна форма, яку цей пакет виполює деінде).
      expect(response.body).to include("<html").and include(login_path)
      expect(response.body).not_to include('{"error"')
    end
  end
end
