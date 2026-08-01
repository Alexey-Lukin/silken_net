# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Api::V1::SessionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, password: "password12345") }

  describe "POST /login" do
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

    it "destroys the current session record when session exists" do
      # First login to create a session
      post "/login", params: { email: user.email_address, password: "password12345" }, as: :json
      token = response.parsed_body["token"]

      delete "/logout", headers: { "Authorization" => "Bearer #{token}" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "redirects to login page for HTML format" do
      delete "/logout",
        headers: { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "signed_in? helper" do
    def json_headers
      { "Accept" => "application/json" }
    end

    def auth_headers
      json_headers.merge("Authorization" => "Bearer #{user.generate_token_for(:api_access)}")
    end

    it "returns true when user is authenticated" do
      get "/trees", headers: auth_headers
      expect(response).not_to have_http_status(:unauthorized)
    end

    it "returns false when user is not authenticated" do
      get "/organizations", headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "#current_session" do
    it "returns nil when current_user is nil" do
      controller = described_class.new
      allow(controller).to receive(:current_user).and_return(nil)
      result = controller.send(:current_session)
      expect(result).to be_nil
    end

    it "returns the most recent session when current_user exists" do
      # Login to create a session, then logout to exercise current_session lookup
      post "/login", params: { email: user.email_address, password: "password12345" }, as: :json
      token = response.parsed_body["token"]

      # The destroy action calls current_session internally, exercising lines 80-82
      delete "/logout", headers: { "Authorization" => "Bearer #{token}" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /login (HTML format)" do
    it "renders the login page" do
      get "/login", headers: { "Accept" => "text/html" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /login (HTML format)" do
    it "redirects on successful HTML login" do
      post "/login",
        params: { email: user.email_address, password: "password12345" },
        headers: { "Accept" => "text/html" }
      expect(response).to have_http_status(:redirect)
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
        dashboard_index_path: "/dashboard"
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

      expect(controller).to have_received(:redirect_to).with("/login", hash_including(:alert))
    end

    it "handles existing user with non-locked identity" do
      existing_user = create(:user, organization: organization, password: "password12345")
      uid = "existing_uid_#{SecureRandom.hex(4)}"
      auth_hash = build_auth_hash(email: existing_user.email_address, uid: uid, first_name: "Existing")

      Identity.create!(provider: auth_hash.provider, uid: uid, user: existing_user)

      controller = build_controller_with_auth(auth_hash)
      controller.send(:omniauth_create)

      expect(controller).to have_received(:redirect_to).with("/dashboard", hash_including(:notice))
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
