# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      # Дозволяємо доступ до входу без автентифікації
      skip_before_action :authenticate_user!, only: [ :new, :create, :omniauth_create ]

      # --- ПОРТАЛ ВХОДУ ---
      def new
        respond_to do |format|
          format.html { render Views::Components::Sessions::New.new }
        end
      end

      # --- КЛАСИЧНИЙ ВХІД (Email/Password) ---
      def create
        user = User.find_by(email_address: params[:email])

        if user&.authenticate(params[:password])
          establish_session(user)

          respond_to do |format|
            format.json { render_api_login_success(user) }
            format.html { redirect_to api_v1_dashboard_index_path, notice: "Neural Link Established." }
          end
        else
          render_login_failure
        end
      end

      # --- OMNIAUTH ВХІД (Google/Apple/LinkedIn) ---
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

        # 2. Прив'язуємо ідентичність через наш оновлений метод (v2.0)
        Identity.find_or_create_from_auth_hash(auth, user: user)

        establish_session(user)

        redirect_to api_v1_dashboard_index_path, notice: "Authenticated via #{auth.provider.titleize}."
      end

      # --- ВИХІД (Logout) ---
      def destroy
        # Видаляємо фізичний запис сесії, якщо він існує
        current_session&.destroy
        session[:user_id] = nil
        
        respond_to do |format|
          format.json { render json: { message: "Вихід успішний. Брама закрита." }, status: :ok }
          format.html { redirect_to api_v1_login_path, notice: "Neural Link Severed." }
        end
      end

      private

      # Спільна логіка встановлення зв'язку
      def establish_session(user)
        # 1. Стандартна Rails сесія (Cookie-based)
        session[:user_id] = user.id

        # 2. Створення запису в таблиці Session (Operational Pulse)
        # Це тригерне track_user_activity через after_create в моделі Session
        user.sessions.create!(
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        # 3. Пряме оновлення User (Touch visit)
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
          format.json { render json: { error: "Невірні координати доступу." }, status: :unauthorized }
          format.html do
            flash.now[:alert] = "Access Denied: Invalid Credentials."
            render Views::Components::Sessions::New.new, status: :unauthorized
          end
        end
      end
    end
  end
end
