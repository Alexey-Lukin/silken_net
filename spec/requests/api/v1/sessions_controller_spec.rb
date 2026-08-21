# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Api::V1::SessionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, password: "password12345") }

  describe "POST /login" do
    # 🔴 [I18N.3] Межа ЗМІНИ АКТОРА — єдине місце, де локаль ЗАПИСУ й локаль
    # РЕНДЕРУ розходяться. `POST /login` іде під `skip_before_action
    # :authenticate_user!`, тож на момент запису flash акаунт-щабель резолвера
    # порожній за побудовою: вітання пишеться мовою браузера, а наступна сторінка
    # вже рендериться мовою АКАУНТУ. Людина з `users.locale = "lv"` без cookie й
    # з `Accept-Language: en` діставала латиську сторінку з англійським вітанням.
    # ⚠️ Пін дивиться на ТЕКСТ у flash, а не на статус: розходження мов — єдина
    # спостережна відмінність, і на статус воно не впливає ніяк.
    it "writes the greeting in the locale the NEXT page will render in" do
      user.update!(locale: "lv")

      post "/login",
           params: { email: user.email_address, password: "password12345" },
           headers: { "HTTP_ACCEPT_LANGUAGE" => "en" }

      expect(flash[:success]).to eq(I18n.t("flash.sessions.neural_link_established", locale: :lv))
      expect(flash[:success]).not_to eq(I18n.t("flash.sessions.neural_link_established", locale: :en))
    end

    # Дзеркало на ВИХОДІ: там актор ЗНИКАЄ, тож прощання не сміє їхати мовою
    # акаунта, якого на наступній сторінці вже немає — інакше та сама розбіжність
    # приїжджає з протилежного боку (сторінка логіну мовою браузера, прощання
    # мовою щойно знятого акаунта).
    it "writes the farewell without the account tier the logout has just removed" do
      user.update!(locale: "lv")
      post "/login", params: { email: user.email_address, password: "password12345" },
                     headers: { "HTTP_ACCEPT_LANGUAGE" => "en" }

      delete "/logout", headers: { "HTTP_ACCEPT_LANGUAGE" => "en" }

      expect(flash[:success]).to eq(I18n.t("flash.sessions.neural_link_severed", locale: :en))
    end

    it "authenticates with valid credentials" do
      post "/login", params: { email: user.email_address, password: "password12345" }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["token"]).to be_present
    end

    it "returns unauthorized with invalid credentials" do
      post "/login", params: { email: user.email_address, password: "wrong_password" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # Обидві гілки однієї невдачі мусять нести ОДИН текст. Раніше JSON віддавав
    # `flash.sessions.invalid_credentials`, а HTML — окремий сирий літерал
    # «Access Denied: Invalid Credentials.», тобто повідомлення розходились і
    # лише одне з них перекладалось. Спека дивилась тільки на статус JSON-гілки,
    # тому й не бачила цього.
    it "renders the same localized failure message on both the JSON and HTML branches" do
      expected = I18n.t("flash.sessions.invalid_credentials")

      post "/login", params: { email: user.email_address, password: "wrong_password" }, as: :json
      expect(response.parsed_body["error"]).to eq(expected)

      post "/login",
           params: { email: user.email_address, password: "wrong_password" },
           headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include(expected)
      expect(response.body).not_to include("Access Denied")
    end

    it "resets session before establishing new one (session fixation protection)" do
      # First login to establish a session
      post "/login", params: { email: user.email_address, password: "password12345" }, as: :json
      expect(response).to have_http_status(:created)
      first_token = response.parsed_body["token"]

      # Second login should reset the old session and create a new one
      expect {
        post "/login", params: { email: user.email_address, password: "password12345" }, as: :json
      }.to change(user.sessions, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["token"]).not_to eq(first_token)
    end
  end

  describe "DELETE /logout" do
    let(:api_token) { user.generate_token_for(:api_access) }
    let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

    it "logs out the user and returns success message" do
      delete "/logout", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to be_present
    end

    # 🔴 HTML-гілка logout'а доти не мала прикладу взагалі. Вихід приходить
    # `button_to`-ом (DELETE), а `fetch` зберігає метод на 301/302 — тобто на 302
    # браузер перевидавав би DELETE на `/login`, де є лише GET, уже ПІСЛЯ
    # того, як сесію знято. [UI.7]
    it "redirects the browser with 303 See Other, not 302" do
      delete "/logout", headers: headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(login_path)
    end

    it "returns 401 without authentication" do
      delete "/logout", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # 🔴 [SEC.16] Вихід мусить бути СИМЕТРИЧНИЙ входу: `establish_session` робить
    # `reset_session` проти session-fixation, а логаут доти знімав рівно ОДИН
    # ключ із трьох (`:user_id`), лишаючи в cookie `:ps` і `:acting_org_id`.
    # Доступу це не давало, але на спільному пристрої в браузері лишалась
    # організація попереднього оператора. Пін цілить у `:acting_org_id` навмисно
    # — саме він переживав вихід найдовше (гинув аж на НАСТУПНОМУ логіні), і
    # саме на ньому мутація `reset_session` → `session[:user_id] = nil` червоніє.
    it "clears the WHOLE session on logout, not just :user_id" do
      post "/login", params: { email: user.email_address, password: "password12345" }
      expect(session[:ps]).to be_present

      delete "/logout", headers: { "Accept" => "text/html" }

      expect(session[:user_id]).to be_nil
      expect(session[:ps]).to be_nil
      expect(session[:acting_org_id]).to be_nil
    end

    # Назва обіцяє ЗНИЩЕННЯ рядка, а не код відповіді: `:ok` переживає й
    # повністю знятий `current_session&.destroy`.
    it "destroys the current session record when session exists" do
      post "/login", params: { email: user.email_address, password: "password12345" }, as: :json
      token = response.parsed_body["token"]

      expect do
        delete "/logout", headers: { "Authorization" => "Bearer #{token}" }, as: :json
      end.to change { user.sessions.count }.by(-1)

      expect(response).to have_http_status(:ok)
    end

    it "redirects to login page for HTML format" do
      delete "/logout",
        headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }

      # Назва обіцяла «login page», а твердження приймало будь-який 3xx у будь-яку
      # адресу — тобто саме те, що назва обіцяє, ніхто не перевіряв [UI.7].
      expect(response).to redirect_to(login_path)
    end
  end

  describe "signed_in? helper" do
    def json_headers
      { "Accept" => "application/json" }
    end

    def auth_headers
      json_headers.merge("Authorization" => "Bearer #{user.generate_token_for(:api_access)}")
    end

    # 🔴 Обидва приклади доти ходили через HTTP і читали статус — а `signed_in?`
    # на тому шляху не викликається ЖОДНОГО разу: рішення про 401 ухвалює
    # `authenticate_user!`, який від цього хелпера не залежить. Тобто повністю
    # інвертований `signed_in?` лишав би блок зеленим. Форму взято в чесного
    # сусіда нижче (`#current_session` з nil-юзером) — прямий виклик.
    it "returns true when user is authenticated" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user)

      expect(controller.send(:signed_in?)).to be(true)
    end

    it "returns false when user is not authenticated" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(nil)

      expect(controller.send(:signed_in?)).to be(false)
    end
  end

  describe "#current_session" do
    it "returns nil when current_user is nil" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(nil)
      result = controller.send(:current_session)
      expect(result).to be_nil
    end

    # 🔴 Тіло цього приклада було ПОБАЙТОВО таким самим, як у «destroys the
    # current session record» вище — одне слабке тіло під двома різними
    # обіцянками, і жодна не перевірялась. Тут предметом є САМЕ ПОРЯДОК, тож
    # сесій мусить бути дві: на одній `order(created_at: :desc)` не відрізнити
    # від `:asc` і від відсутності сортування взагалі.
    it "returns the most recent session when current_user exists" do
      older  = user.sessions.create!(user_agent: "old", ip_address: "10.0.0.1", created_at: 2.days.ago)
      newest = user.sessions.create!(user_agent: "new", ip_address: "10.0.0.2", created_at: 1.minute.ago)

      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(user)

      expect(controller.send(:current_session)).to eq(newest)
      expect(controller.send(:current_session)).not_to eq(older)
    end
  end

  describe "GET /login (HTML format)" do
    it "renders the login page" do
      get "/login", headers: { "Accept" => "text/html" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /login (HTML format)" do
    # 🔴 [UI.7] Пара з логаутом нижче/вище — ДВІЙНИК: обидва приклади твердили лише
    # «якийсь 3xx», тоді як цілі протилежні (`dashboard_index_path` при вході ⊥
    # `login_path` при виході). Контролер, що після успішного входу веде назад на форму
    # логіну, лишався б зеленим — і це рівно та поведінка, яку користувач читає як
    # «пароль не підійшов».
    it "redirects a successful HTML login to the dashboard" do
      post "/login",
        params: { email: user.email_address, password: "password12345" },
        headers: { "Accept" => "text/html" }

      expect(response).to redirect_to(dashboard_index_path)
    end

    # ⚠️ [TEST.10] Доти цей приклад приймав і 401, і 500 — з підставою «Phlex may
    # not fully render in test env», яку вимір спростував: шлях стабільно віддає
    # 401 з HTML. Сюди ж зведено дубль, що жив окремим `describe` нижче: обидва
    # міряли ТОЙ САМИЙ POST, тож дім лишається один — поруч із успішним входом.
    it "рендерить сторінку входу НА МІСЦІ зі збереженим 401" do
      post "/login",
        params: { email: user.email_address, password: "wrong_password" },
        headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("<html")
      expect(response.body).to include(I18n.t("flash.sessions.invalid_credentials"))
    end
  end

  describe "omniauth_create" do
    let(:auth_hash) do
      OpenStruct.new(
        provider: "google_oauth2",
        uid: "123456",
        info: OpenStruct.new(email: "omniauth_user@example.com", first_name: "OmniAuth", last_name: "User"),
        credentials: OpenStruct.new(token: "mock_token", refresh_token: "mock_refresh",
                                    expires_at: 1.hour.from_now.to_i),
        to_h: { provider: "google_oauth2", uid: "123456" }
      )
    end

    def build_auth_hash(email:, uid:, first_name: "Test", last_name: "User")
      OpenStruct.new(
        provider: "google_oauth2",
        uid: uid,
        info: OpenStruct.new(email: email, first_name: first_name, last_name: last_name),
        credentials: OpenStruct.new(token: "t", refresh_token: "r", expires_at: 1.hour.from_now.to_i),
        to_h: { provider: "google_oauth2", uid: uid }
      )
    end

    # 🔒 [ARCH.69] СТЕЛЯ ЦЬОГО ХАРНЕСУ ОГОЛОШЕНА, і читати його як покриття не можна.
    # Він будує контролер РУКАМИ й підміняє `request` на `double`, тобто приклади
    # нижче не проходять ані роутером, ані Rack, ані CSRF, ані реальним
    # `establish_session`. Причина не лінь: маршруту до `omniauth_create` не існує
    # (і не існувало жодного дня історії репо), тож request-спеку тут написати
    # НЕМОЖЛИВО — вона зʼявиться разом із дротуванням, і тоді цей блок має бути
    # знесений, а не доповнений. Що харнес усе-таки доводить чесно: порядок кроків
    # усередині екшена й те, з якими аргументами він кличе свої співпраці.
    def build_controller_with_auth(auth_hash)
      controller = Api::V1::SessionsController.new
      mock_request = double("request",
        env: { "omniauth.auth" => auth_hash },
        remote_ip: "127.0.0.1",
        user_agent: "RSpec Test",
        host: "localhost",
        port: 3000,
        protocol: "http://",
        optional_port: "",
        host_with_port: "localhost:3000"
      )
      allow(controller).to receive_messages(
        request: mock_request,
        reset_session: nil,
        session: {},
        redirect_to: nil,
        login_path: "/login",
        dashboard_index_path: "/dashboard",
        mfa_challenge_path: "/login/mfa",
        # Ланцюг резолву читає `params`/`cookies`/`headers` реального запиту, яких
        # у double немає. Пінимо не ЛАНЦЮГ (його дім — `locale_settable`), а те,
        # що екшен передає в нього АКТОРА — саме це і є вісь I18N.3.
        resolve_locale: :en
      )
      controller
    end

    it "creates a new user and establishes session via OmniAuth callback" do
      test_user = User.find_or_create_by!(email_address: auth_hash.info.email) do |u|
        u.password = SecureRandom.hex(16)
        u.first_name = auth_hash.info.first_name
        u.last_name = auth_hash.info.last_name
        u.role = :investor
        u.organization = organization
      end

      identity = Identity.find_or_create_from_auth_hash(auth_hash, user: test_user)
      expect(identity).to be_persisted
      expect(identity.provider).to eq("google_oauth2")
    end

    it "blocks login when identity is locked" do
      locked_user = create(:user, organization: organization, email_address: "locked_auth@example.com")
      identity = Identity.create!(
        provider: "google_oauth2",
        uid: "locked-uid-789",
        user: locked_user,
        locked_at: Time.current
      )
      expect(identity.locked?).to be true

      # Verify that locked identity check works
      existing = Identity.find_by(provider: "google_oauth2", uid: "locked-uid-789")
      expect(existing&.locked?).to be true
    end

    it "executes the full omniauth_create flow with a new user" do
      auth_hash = build_auth_hash(
        email: "new_omniauth_#{SecureRandom.hex(4)}@example.com",
        uid: "omni_new_#{SecureRandom.hex(4)}",
        first_name: "OmniNew"
      )

      controller = build_controller_with_auth(auth_hash)
      controller.send(:omniauth_create)

      created_user = User.find_by(email_address: auth_hash.info.email)
      expect(created_user).to be_present
      expect(created_user.first_name).to eq("OmniNew")
      expect(created_user.role).to eq("investor")
    end

    it "redirects when identity is locked" do
      locked_user = create(:user, organization: organization, password: "password12345")
      uid = "locked_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: locked_user.email_address, uid: uid, first_name: "Locked")

      Identity.create!(provider: auth_hash.provider, uid: uid, user: locked_user, locked_at: Time.current)

      controller = build_controller_with_auth(auth_hash)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:redirect_to).with("/login", hash_including(:error))
    end

    it "handles existing user with non-locked identity" do
      existing_user = create(:user, organization: organization, password: "password12345")
      uid = "existing_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: existing_user.email_address, uid: uid, first_name: "Existing")

      Identity.create!(provider: auth_hash.provider, uid: uid, user: existing_user)

      controller = build_controller_with_auth(auth_hash)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:redirect_to).with("/dashboard", hash_including(:success))
    end

    # 🔴 [ARCH.69] НАЙВАЖЛИВІША вісь цього блоку: провайдер засвідчує лише ПЕРШИЙ
    # фактор. Без гейта акаунт із увімкненим TOTP діставав би повну сесію з самого
    # провайдерського твердження, тобто OAuth був би обхідним шляхом навколо MFA —
    # рівно проти інваріанта, який `create` оголошує словами («сесія не існує до
    # другого фактора»). Сьогодні недосяжно, бо маршруту немає; пін існує саме
    # тому, що дротування зробить це досяжним, і зробить мовчки.
    it "does NOT establish a session when the account has MFA enabled" do
      mfa_user = create(:user, organization: organization, password: "password12345")
      mfa_user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random)
      uid = "mfa_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: mfa_user.email_address, uid: uid)

      controller = build_controller_with_auth(auth_hash)
      # `redirect_to_mfa_challenge` містить `respond_to`, який поза request-циклом
      # недосяжний — стабимо САМ перехід, бо вісь тут «куди пішов екшен», а не
      # «як челендж рендериться» (це дім `MfaChallengesController`).
      allow(controller).to receive_messages(establish_session: nil, redirect_to_mfa_challenge: nil)
      controller.send(:omniauth_create)

      expect(controller).not_to have_received(:establish_session)
      expect(controller).to have_received(:redirect_to_mfa_challenge).with(mfa_user)
    end

    # Дзеркальна половина: без неї «сесії не було» не відрізнити від «екшен взагалі
    # нічого не робить». Той самий шлях на акаунті БЕЗ MFA мусить дати сесію.
    it "does establish a session when the account has no MFA" do
      plain_user = create(:user, organization: organization, password: "password12345")
      uid = "plain_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: plain_user.email_address, uid: uid)

      controller = build_controller_with_auth(auth_hash)
      allow(controller).to receive(:establish_session)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:establish_session)
    end

    # 🔴 [ARCH.69] ВЛАСНИКА ВИРІШУЄ `uid`, НІКОЛИ ЗБІГ ЗА ПОШТОЮ. Провайдер
    # засвідчує володіння СВОЇМ акаунтом; пошту він лише повідомляє. Доти резолв
    # ішов від пошти, і при відомому `uid` з іншим email екшен відкривав сесію
    # чужому користувачеві, оновлюючи токени на identity власника — а не червоніло
    # НІЩО: `find_or_create_from_auth_hash` переприв'язки не робить
    # (`identity.user = user if identity.new_record?`), і `uniqueness: {scope:
    # :provider}` не порушено, бо рядок той самий.
    # ⚠️ Найпростіший живий пускач — зміна пошти на боці провайдера: `uid` стабільний.
    it "opens the session for the identity OWNER, not for an email match" do
      owner     = create(:user, organization: organization, password: "password12345")
      namesake  = create(:user, organization: organization, password: "password12345")
      uid       = "owned_uid_#{SecureRandom.hex(4)}"
      Identity.create!(provider: "google_oauth2", uid: uid, user: owner)

      # Провайдер повідомляє пошту ІНШОГО акаунта при тому самому uid.
      auth_hash = build_auth_hash(email: namesake.email_address, uid: uid)

      controller = build_controller_with_auth(auth_hash)
      allow(controller).to receive(:establish_session)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:establish_session).with(owner)
    end

    # Дзеркало: невідомий `uid` мусить і далі резолвити за поштою — інакше пін вище
    # був би задоволений будь-яким звуженням, включно з «ніколи нікого не пускати».
    it "still resolves by email when the uid is unknown" do
      newcomer  = create(:user, organization: organization, password: "password12345")
      auth_hash = build_auth_hash(email: newcomer.email_address, uid: "unknown_uid_#{SecureRandom.hex(4)}")

      controller = build_controller_with_auth(auth_hash)
      allow(controller).to receive(:establish_session)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:establish_session).with(newcomer)
    end

    # 🔴 [ARCH.69] Порожній `omniauth.auth` — не гіпотеза, а прямий наслідок форми
    # дротування: маршрут оголошується безумовно, middleware стоїть за config-гейтом.
    # Без гарда прод без ключів віддавав би 500 на публічному шляху.
    it "refuses politely when the provider middleware did not populate the env" do
      controller = build_controller_with_auth(nil)
      allow(controller).to receive(:establish_session)
      controller.send(:omniauth_create)

      expect(controller).not_to have_received(:establish_session)
      expect(controller).to have_received(:redirect_to)
    end

    # 🔴 [ARCH.69] Salt-стемп: акаунт без `password_digest` діставав
    # `session[:ps] = nil`, тобто сесію, яку наступний запит відкидає — вхід
    # перетворювався на нескінченний редирект.
    # ⚠️ Підстава ПЕРЕМІРЯНА 2026-08-21: доти тут стояло «реальний шлях —
    # `Gdpr::AnonymizeUserService`», але той тим самим `update_columns` переписує
    # й `email_address` на tombstone-адресу, тож резолв такого рядка не знаходить.
    # Пін лишається (форма fail-closed коштує один предикат), але його пускач —
    # ще не виміряний, і фікстура нижче конструює стан РУКАМИ саме тому.
    it "restores a session salt for an account that arrived without a password" do
      passwordless = create(:user, organization: organization, password: "password12345")
      # `password_salt` — не колонка, а дериват `password_digest`
      # (`HasArgon2Password#password_salt`), тож занулюємо джерело, не похідну.
      passwordless.update_columns(password_digest: nil)
      uid = "pwless_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: passwordless.reload.email_address, uid: uid)

      expect(passwordless.session_salt_stamp).to be_blank

      controller = build_controller_with_auth(auth_hash)
      controller.send(:omniauth_create)

      expect(passwordless.reload.session_salt_stamp).to be_present
    end

    # [ARCH.69] Вісь I18N.3 — екшен мусить передавати АКТОРА в резолвер, інакше
    # вітання їде мовою браузера, а дашборд рендериться мовою акаунта.
    it "resolves the greeting locale from the account, not the browser" do
      account = create(:user, organization: organization, password: "password12345", locale: "lv")
      uid = "loc_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: account.email_address, uid: uid)

      controller = build_controller_with_auth(auth_hash)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:resolve_locale).with(account: account)
    end

    # [ARCH.69] `titleize` давав «Google Oauth2»; мапа `PROVIDER_NAMES` існує саме
    # для цього, і сусідній пін на сторінці безпеки вже стереже ту саму форму.
    it "names the provider through PROVIDER_NAMES, not titleize" do
      account = create(:user, organization: organization, password: "password12345")
      uid = "name_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: account.email_address, uid: uid)

      controller = build_controller_with_auth(auth_hash)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:redirect_to) do |path, opts|
        expect(path).to eq("/dashboard")
        expect(opts[:success]).to include("Google")
        # Негативна половина має базлайн: доти тут стояв `auth.provider.titleize`,
        # який на `google_oauth2` друкує саме «Google Oauth2».
        expect(opts[:success]).not_to include("Oauth2")
      end
    end
  end

  describe "rate limit" do
    it "returns 429 after exceeding login rate limit" do
      Prosopite.pause if defined?(Prosopite)
      6.times do
        post "/login", params: { email: user.email_address, password: "wrong" }, as: :json
      end

      expect(response).to have_http_status(:too_many_requests)
    ensure
      Prosopite.resume if defined?(Prosopite)
    end

    # 🔴 [SEC.25] Пін на ФОРМУ, не на статус: статус 429 віддавала й зламана версія,
    # тож пін на нього лишався б зеленим. Червоніє саме `media_type` — без
    # `respond_to` браузер діставав сирий JSON-блоб на сторінці входу.
    it "браузерові віддає сторінку входу з поясненням, а не JSON-блоб" do
      Prosopite.pause if defined?(Prosopite)
      6.times do
        post "/login",
          params: { email: user.email_address, password: "wrong" },
          headers: { "Accept" => "text/html" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(I18n.t("flash.sessions.rate_limited"))
    ensure
      Prosopite.resume if defined?(Prosopite)
    end
  end
end
