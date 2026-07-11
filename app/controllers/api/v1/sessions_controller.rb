# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      # Дозволяємо доступ до входу без автентифікації
      skip_before_action :authenticate_user!, only: [ :new, :create, :omniauth_create ]

      # Захист від перебору (Brute Force): обмеження кількості спроб входу
      rate_limit to: 5, within: 1.minute, only: :create, with: -> {
        render json: { error: I18n.t("flash.sessions.rate_limited") }, status: :too_many_requests
      }

      # --- ПОРТАЛ ВХОДУ ---
      def new
        respond_to do |format|
          format.html { render_auth_page(title: "Login Portal", component: Sessions::New.new) }
        end
      end

      # --- КЛАСИЧНИЙ ВХІД (Email/Password) ---
      def create
        user = User.find_by(email_address: params[:email])

        if user&.authenticate(params[:password])
          establish_session(user)

          respond_to do |format|
            format.json { render_api_login_success(user) }
            format.html { redirect_to api_v1_dashboard_index_path, notice: I18n.t("flash.sessions.neural_link_established") }
          end
        else
          render_login_failure
        end
      end

      # --- OMNIAUTH ВХІД (Google/Apple/LinkedIn/Facebook/Twitter) ---
      # Маршрут: get/post '/auth/:provider/callback'
      def omniauth_create
        auth = request.env["omniauth.auth"]

        # 1. Спершу знаходимо або створюємо користувача (Захист від RecordInvalid)
        user = User.find_or_create_by!(email_address: auth.info.email) do |u|
          u.password = SecureRandom.hex(16) # Тимчасовий пароль для has_secure_password
          u.first_name = auth.info.first_name
          u.last_name = auth.info.last_name
          u.role = :investor # Ранг за замовчуванням
        end

        # 2. Перевіряємо чи ідентичність заблокована (Account Takeover Protection)
        existing_identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
        if existing_identity&.locked?
          redirect_to api_v1_login_path, alert: I18n.t("flash.sessions.blocked_provider")
          return
        end

        # 3. Прив'язуємо ідентичність через наш оновлений метод (v2.0)
        Identity.find_or_create_from_auth_hash(auth, user: user)

        establish_session(user)

        redirect_to api_v1_dashboard_index_path, notice: I18n.t("flash.sessions.authenticated_via", provider: auth.provider.titleize)
      end

      # --- ВИХІД (Logout) ---
      def destroy
        # Видаляємо фізичний запис сесії, якщо він існує
        current_session&.destroy
        session[:user_id] = nil

        respond_to do |format|
          format.json { render json: { message: I18n.t("flash.sessions.logout_success") }, status: :ok }
          format.html { redirect_to api_v1_login_path, notice: I18n.t("flash.sessions.neural_link_severed") }
        end
      end

      private

      def current_session
        return unless current_user

        current_user.sessions.order(created_at: :desc).first
      end

      # Спільна логіка встановлення зв'язку
      def establish_session(user)
        # 1. Захист від Session Fixation: очищуємо стару сесію перед встановленням нової
        reset_session

        # 2. Стандартна Rails сесія (Cookie-based) + salt-прив'язка [SEC.16]:
        # authenticate_user! звіряє цей stamp — password-change гасить чужі cookie.
        session[:user_id] = user.id
        session[:ps] = user.password_salt.to_s.last(10)

        # 3. Створення запису в таблиці Session (Operational Pulse)
        # Це тригерне track_user_activity через after_create в моделі Session
        user.sessions.create!(
          ip_address: request.remote_ip,
          user_agent: request.user_agent.presence || "Unknown"
        )

        # 4. Пряме оновлення User (Touch visit)
        user.touch_visit!
      end

      def render_api_login_success(user)
        token = user.generate_token_for(:api_access)
        render json: {
          token: token,
          user: { id: user.id, email: user.email_address, full_name: user.full_name, role: user.role }
        }, status: :created
      end

      def render_login_failure
        respond_to do |format|
          format.json { render json: { error: I18n.t("flash.sessions.invalid_credentials") }, status: :unauthorized }
          format.html do
            render_auth_page(
              title: "Login Portal",
              component: Sessions::New.new(flash_alert: "Access Denied: Invalid Credentials."),
              status: :unauthorized
            )
          end
        end
      end
    end
  end
end
