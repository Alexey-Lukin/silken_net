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
      # ✅ [S6.21] Другий фактор ЖИВИЙ: акаунт із `mfa_enabled?` після пароля НЕ
      # дістає сесії — лише pending-мітку з TTL і редирект на `/login/mfa`
      # (`MfaChallengesController`), де TOTP/recovery і завершує вхід. Сесія
      # (`session[:user_id]`) не існує до другого фактора — «наполовину зайшов»
      # не є станом.
      def create
        user = User.find_by(email_address: params[:email])

        if user&.authenticate(params[:password])
          if user.mfa_enabled?
            return redirect_to_mfa_challenge(user)
          end

          establish_session(user)

          # 🔴 [I18N.3] Вітання пишеться в локалі, якою вже РЕНДЕРИТЬСЯ наступна
          # сторінка. Цей екшен іде під `skip_before_action :authenticate_user!`,
          # тож на момент `set_locale` акаунт-щабель порожній за побудовою — без
          # цього людина з `users.locale = "lv"` і браузером `en` діставала
          # латиський дашборд з англійським вітанням.
          I18n.with_locale(resolve_locale(account: user)) do
            respond_to do |format|
              format.json { render_api_login_success(user) }
              format.html { redirect_to dashboard_index_path, success: I18n.t("flash.sessions.neural_link_established") }
            end
          end
        else
          render_login_failure
        end
      end

      # --- OMNIAUTH ВХІД (провайдери — `Identity::SUPPORTED_PROVIDERS`) ---
      # ⚠️ Перелік НЕ дублюється тут словами: доти рядок називав Apple, якого в
      # константі немає, і розходився з Privacy Policy, писаною за реальним
      # списком. Другий дім переліку = другий шанс розійтись [ARCH.69].
      #
      # 🔴 [ARCH.69] МАРШРУТУ ДО ЦЬОГО ЕКШЕНА НЕ ІСНУЄ — і не існувало ЖОДНОГО дня
      # історії репо (`git log --all -S` по `routes.rb` порожній). Доти цей коментар
      # називав «get/post '/auth/:provider/callback'», тобто описував дріт, якого
      # ніхто ніколи не тягнув. OmniAuth-гемів у Gemfile теж немає, отже
      # `request.env["omniauth.auth"]` не заповниться, і тіло нижче недосяжне.
      # Лишається як заготовка ПІД дротування (⚖️ founder: OAuth потрібен), а не як
      # живий шлях; доля «маршрут зʼявляється / екшен зникає» тримається разом із
      # ним → [`00_07`](../../../../docs/00_07_Action_Plan_Tracker.md) ARCH.69.
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

        # 🔴 [I18N.3] Дзеркало входу: тут актор ЗНИКАЄ, тож прощання не сміє їхати
        # мовою щойно знятого акаунта — сторінка логіну вже рендериться без нього.
        # `account: nil` явний, бо `current_user` лишається мемоїзованим і після
        # `reset_session`, тобто «нічого не передавати» дало б стару відповідь.
        I18n.with_locale(resolve_locale(account: nil)) do
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
      end

      private

      def current_session
        return unless current_user

        current_user.sessions.order(created_at: :desc).first
      end

      # [S6.21] `establish_session` + `render_api_login_success` живуть на предку
      # (`BaseController`) — точка входу одна на три шляхи, копій не заводимо.

      # [S6.21] Пароль пройдено, сесії ще НЕМА: pending-мітка + челендж. Мітка
      # ставиться в ЧИСТУ сесію (reset проти fixation ДО неї — інакше pending
      # їхав би в cookie, зафіксованому атакером до входу).
      def redirect_to_mfa_challenge(user)
        reset_session
        session[:mfa_pending_user_id] = user.id
        session[:mfa_pending_at] = Time.current.to_i

        respond_to do |format|
          # Bearer-флоу другого фактора не має (форма — браузерна); машинному
          # клієнту чесний 401 із кодом, а не половина входу.
          format.json { render json: { error: I18n.t("sessions.mfa_challenge.required"), code: "mfa_required" }, status: :unauthorized }
          format.html { redirect_to mfa_challenge_path, status: :see_other }
        end
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
