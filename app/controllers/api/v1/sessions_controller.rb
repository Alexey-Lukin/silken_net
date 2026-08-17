# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      # Дозволяємо доступ до входу без автентифікації
      skip_before_action :authenticate_user!, only: [ :new, :create, :omniauth_create ]

      # Захист від перебору (Brute Force): обмеження кількості спроб входу.
      #
      # 🔴 [SEC.25] HTML-гілка тут несуча: без неї пʼять невдалих входів за хвилину
      # віддавали сирий JSON-блоб на САМІЙ сторінці входу — найвидніша неавтентифікована
      # поверхня дерева. Сиблінг `PasswordsController` цю ж лямбду мав із `respond_to`
      # уже давно; периметр фіксу просто не дійшов сюди.
      #
      # Рендер НА МІСЦІ, а не редирект (на відміну від сиблінга): та сама форма, що й
      # у `render_login_failure` двома методами нижче — статус зберігається, введений
      # email не губиться. Лямбда виконується в контексті контролера
      # (`ActionController::RateLimiting` — «evaluated within the context of the
      # controller processing the request»), тож приватні рендерери їй доступні.
      rate_limit to: 5, within: 1.minute, only: :create, with: -> {
        respond_to do |format|
          format.json { render json: { error: I18n.t("flash.sessions.rate_limited") }, status: :too_many_requests }
          format.html do
            render_auth_page(
              title: I18n.t("sessions.login_title"),
              component: Sessions::New.new(flash_alert: I18n.t("flash.sessions.rate_limited")),
              status: :too_many_requests
            )
          end
        end
      }

      # --- ПОРТАЛ ВХОДУ ---
      def new
        respond_to do |format|
          format.html { render_auth_page(title: I18n.t("sessions.login_title"), component: Sessions::New.new) }
        end
      end

      # --- КЛАСИЧНИЙ ВХІД (Email/Password) ---
      #
      # 🔴 [S6.21] Другого фактора тут НЕМА, і це не пропуск опису: `otp_required_for_login`
      # у шляху входу не читається жодного разу, тож пароль дає повний доступ навіть
      # акаунту з «увімкненим» MFA. Саме тому напрямок «увімкнути» в
      # `AccountSecurityController#toggle_mfa` закритий — інакше прапорець друкував би
      # захист, якого нема. Дротуючи verify-on-login, знімай той гейт ТИМ САМИМ комітом;
      # `spec/security/mfa_claim_honesty_spec.rb` почервоніє й нагадає.
      def create
        user = User.find_by(email_address: params[:email])

        if user&.authenticate(params[:password])
          establish_session(user)

          respond_to do |format|
            format.json { render_api_login_success(user) }
            format.html { redirect_to dashboard_index_path, success: I18n.t("flash.sessions.neural_link_established") }
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
          redirect_to login_path, error: I18n.t("flash.sessions.blocked_provider")
          return
        end

        # 3. Прив'язуємо ідентичність через наш оновлений метод (v2.0)
        Identity.find_or_create_from_auth_hash(auth, user: user)

        establish_session(user)

        redirect_to dashboard_index_path, success: I18n.t("flash.sessions.authenticated_via", provider: auth.provider.titleize)
      end

      # --- ВИХІД (Logout) ---
      def destroy
        # Видаляємо фізичний запис сесії, якщо він існує
        current_session&.destroy

        # [SEC.16] `reset_session`, а НЕ `session[:user_id] = nil`: у cookie живуть
        # ТРИ ключі, і зняття одного лишає два. Доступу вони не дають
        # (`authenticate_user!` вимагає `:user_id`), тож це не діра, а залишковий
        # слід — і найгірший із трьох саме `:acting_org_id`: на спільному пристрої
        # в браузері лишалась організація, в контексті якої працював попередній
        # оператор. Дзеркалить `establish_session`, який робить те саме на вході
        # проти session-fixation — вихід мусить бути симетричним входу.
        reset_session

        respond_to do |format|
          format.json { render json: { message: I18n.t("flash.sessions.logout_success") }, status: :ok }
          # 303, не 302 [UI.7]: logout приходить `button_to`-ом (DELETE), а `fetch`
          # зберігає метод на 301/302 — тобто браузер перевидавав би DELETE на
          # `/login`, де зареєстровано лише GET. Сесію на той момент уже знято.
          format.html do
            redirect_to login_path,
                        status: :see_other,
                        success: I18n.t("flash.sessions.neural_link_severed")
          end
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
        session[:ps] = user.session_salt_stamp

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
            # Той самий ключ, що й у JSON-гілці двома рядками вище. Раніше тут
            # стояв окремий сирий літерал — тобто одна й та сама невдача входу
            # мала ДВА різні тексти, і лише один із них перекладався.
            render_auth_page(
              title: I18n.t("sessions.login_title"),
              component: Sessions::New.new(flash_alert: I18n.t("flash.sessions.invalid_credentials")),
              status: :unauthorized
            )
          end
        end
      end
    end
  end
end
