# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::Base
      # [SEC.25 Ф2] Кидається `acting_organization!` — тобто В ТОЧЦІ ЧИТАННЯ організації,
      # а не `before_action`-гардом. Різниця несуча: від `BaseController` успадковують і
      # ті, хто організації не має за побудовою — більшість codex (lore глобальний),
      # обидва webhook'и, обидва auth-шляхи, `m2m_auth` і платформені (`system_health`,
      # `system_audits`, `organizations`). ⚠️ «Більшість», а не «весь» codex: [SEC.26]
      # дав `Codex::CitationsController` організацію, бо цитата пише в ОПЕРАЦІЙНУ ціль,
      # і саме це показує, чому гард живе в точці читання — той самий контролер
      # org-less на читанні лору й org-скоуплений на записі цитати.
      # Класовий `before_action` вимагав би
      # `skip_before_action` у кожному з них — тобто «однорідне правило», зібране зі
      # списку винятків, який мусить рости з кожним новим контролером і який хтось
      # забуде поповнити. Гард у точці читання списку не має взагалі: сторінка, що
      # організації не читає, його не тригерить, а забути його неможливо, бо він НЕ
      # окремий крок — він і є спосіб дістати організацію.
      class NoActingOrganization < StandardError; end

      # Phlex components (DashboardLayout, AuthLayout) generate complete HTML documents,
      # so Rails must not wrap their output in application.html.erb.
      layout false

      # Full CSRF protection for session-based Dashboard requests.
      # Bearer-token API requests bypass via handle_unverified_request below.
      protect_from_forgery with: :exception

      include Pagy::Method
      include Pundit::Authorization
      # Resolve `I18n.locale` from params → cookie → Accept-Language → default.
      # Without this every Dashboard request fell back to `default_locale`
      # because `Api::V1::BaseController` does NOT inherit from
      # `ApplicationController` (which is the one that included the concern
      # historically). The user-visible symptom was "switching the language
      # needs two clicks": the first POST wrote the cookie but the redirected
      # GET ignored it.
      include LocaleSettable

      # --- ПОРЯДОК ЗАХИСТУ ---
      before_action :authenticate_user!
      # Слід для ARCH.57: ставиться ПІСЛЯ автентифікації (раніше немає кого писати)
      # і несе лише id — див. застереження в `Current`.
      before_action :expose_acting_context

      # --- ОБРОБКА ПОМИЛОК (The Safety Net) ---
      # Ми не даємо хакеру зрозуміти природу помилки, але даємо розробнику чіткий JSON
      # StandardError defined first, so it is checked last (Rails rescue_from: reverse order).
      # This lets specific handlers below (RecordNotFound, etc.) take priority.
      # [coverage-leave, env-conditional]: `Rails.env` is fixed to "test" for the
      # whole RSpec process, so the `development?` branch (no handler registered,
      # full backtraces in-browser) structurally cannot fire within the suite —
      # exercising it would require reloading this class under RAILS_ENV=development,
      # which is out of scope for a unit/request run. Mirrors the `defined?(dev-gem)`
      # env-conditional leave category (04_06 §B.4).
      rescue_from StandardError, with: :render_internal_server_error unless Rails.env.development?
      rescue_from NoActingOrganization, with: :render_no_organization
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
      rescue_from ActiveModel::ValidationError, with: :render_validation_error
      rescue_from Pundit::NotAuthorizedError, with: :render_forbidden_pundit

      # --- ХЕЛПЕРИ ДОСТУПУ ---
      # Робимо методи доступними в Phlex-компонентах через хелпери Rails
      helper_method :current_user, :signed_in?, :acting_organization

      private

      # 0. CSRF BYPASS FOR BEARER TOKEN REQUESTS
      # Bearer-token API requests are immune to CSRF by design: browsers never
      # auto-attach Authorization headers in cross-origin requests (unlike cookies).
      # For these requests, skip the :exception strategy and let normal auth proceed.
      # Session-based Dashboard requests without a valid CSRF token raise
      # ActionController::InvalidAuthenticityToken (the strictest protection).
      def handle_unverified_request
        raise ActionController::InvalidAuthenticityToken unless bearer_token_request?
      end

      def bearer_token_request?
        request.authorization&.start_with?("Bearer ")
      end

      # 1. АВТЕНТИФІКАЦІЯ (The Handshake)
      # Підтримуємо як сесійні куки (для Дашборду), так і Bearer Tokens (для Мобільного додатка)
      def authenticate_user!
        # Спроба 1: Перевірка через HTTP Token (для API-запитів)
        @current_user = authenticate_with_http_token do |token, _options|
          User.find_by_token_for(:api_access, token)
        end

        # Спроба 2: Перевірка через сесію Rails 8 (для Дашборду в браузері).
        # [SEC.16] Cookie salt-bound (дзеркало api_access-токена в User):
        # зміна пароля міняє password_salt → чужий/викрадений cookie гасне
        # одразу, а не доживає свої 14 днів.
        if @current_user.nil? && session[:user_id]
          user = User.find_by(id: session[:user_id])
          @current_user = user if user && session[:ps].to_s == user.password_salt.to_s.last(10)
        end

        return render_unauthorized unless @current_user

        @current_user.touch_visit! # Оновлюємо "пульс" активності користувача
      end

      def current_user
        @current_user
      end

      # [SEC.25 Ф2] Pundit дістає не користувача, а пару «хто + в контексті якої
      # організації» — бо організація запиту більше не виводиться з користувача
      # (super_admin її перемикає).
      #
      # ⚠️ `current_user &&` тут несуче, а не оборонний рефлекс: без нього анонімний
      # запит (`skip_before_action :authenticate_user!` — публічний codex-leaderboard,
      # webhook'и, логін) дістав би обгортку навколо `nil`, а обгортка — це об'єкт,
      # тобто `present?` каже `true`. Кожен `return scope.none unless user` у
      # codex-політиках перевернувся б на fail-OPEN. Нема користувача — нема пари.
      def pundit_user
        current_user && UserContext.new(current_user, acting_organization)
      end

      def signed_in?
        current_user.present?
      end

      # 2. ПРАВА ДОСТУПУ (RBAC) — Legacy хелпери для поступової міграції
      # TODO: Перенести всі контролери на Pundit і видалити ці методи
      def authorize_admin!
        render_forbidden unless current_user&.role_admin? || current_user&.role_super_admin?
      end

      def authorize_super_admin!
        render_forbidden unless current_user&.role_super_admin?
      end

      def authorize_forester!
        render_forbidden unless current_user&.forest_commander?
      end

      # 3. PHLEX INTEGRATION (The Visual Oracle)
      # Метод для рендерингу Phlex-компонентів всередині нашого DashboardLayout.
      # Використовується, коли контролер відповідає на .html запит.
      # Content component передається як параметр — НЕ через блок,
      # оскільки блок виконується в контексті контролера (Ruby closure),
      # і `render` всередині блоку викликає контролерний render (DoubleRenderError).
      def render_dashboard(title:, component:, status: :ok)
        render DashboardLayout.new(
          title: title,
          current_user: current_user,
          current_path: request.path,
          ews_alert_count: ews_alert_count_cached,
          content: component
        ), status: status
      end

      # Метод для рендерингу standalone auth-сторінок (login, forgot/reset password).
      # Забезпечує повний HTML-документ з CSS/JS includes без sidebar/DashboardLayout.
      # `title:` обов'язковий: усі сім викликачів і так передають його явно, тож
      # англійський дефолт «Access Portal» був недосяжним рядком, який мовчки
      # чекав першого викликача, що його забуде. Видалення дешевше за переклад.
      def render_auth_page(title:, component:, status: :ok)
        render AuthLayout.new(title: title, content: component), status: status
      end

      # [SEC.25 Ф2] Організація, в контексті якої виконується ЦЕЙ запит.
      #
      # Для всіх, крім super_admin, це завжди власна організація — сесія тут свідомо
      # ІГНОРУЄТЬСЯ, а не звіряється: інакше переведення користувача в іншу організацію
      # лишало б його сесію дивитись на стару. Право перемикатись — платформена
      # здатність super_admin'а, а не властивість членства.
      #
      # Носій — `session[:acting_org_id]` (per-device, гине з логаутом, сусідить із
      # `:user_id`/`:ps`), а не колонка на `users`: стан ПЕРЕГЛЯДУ не є членством, і
      # колонка пережила б і сесію, і пристрій (перемкнувся на ноуті — змінилось на
      # телефоні; перемкнувся місяць тому — сьогодні тихо дивишся не туди).
      #
      # Bearer-запит cookie-сесії не несе → падає на власну організацію. Це і є
      # правильна деградація: API-клієнт не має UI-контексту перегляду.
      def acting_organization
        return @acting_organization if defined?(@acting_organization)

        @acting_organization = resolve_acting_organization
      end

      # Bang-форма: усе, що БЕЗ організації працювати не може, читає організацію ЧЕРЕЗ
      # неї. Раніше ці ж місця робили `current_user.organization.trees` і на nil давали
      # три різні поведінки в межах одного сімейства сторінок — 422 з HTML, 200 із
      # фальшивим порожнім станом (не відрізнити від завантаження) і 500 з JSON-блобом
      # у браузері. Тепер шлях один і керований.
      def acting_organization!
        acting_organization || raise(NoActingOrganization)
      end

      # Читання org тут навмисне НЕ-bang: контролери, що організації не потребують
      # (codex, платформені, webhook'и), не мусять падати лише через те, що ми
      # ставимо слід для аудиту.
      def expose_acting_context
        Current.acting_organization_id = acting_organization&.id
        Current.home_organization_id = current_user&.organization_id
      end

      def resolve_acting_organization
        return nil unless current_user
        return current_user.organization unless current_user.role_super_admin?

        switched = session[:acting_org_id] && Organization.find_by(id: session[:acting_org_id])
        switched || current_user.organization
      end

      # JSON клієнти отримують 422 з машинно-читабельним кодом помилки.
      # HTML клієнти бачать стилізовану Phlex-сторінку всередині AuthLayout
      # (узгоджено з docs/04_04_Phlex_UI_and_Tailwind.md — UI лише через Phlex).
      def render_no_organization(_exception = nil)
        respond_to do |format|
          format.json do
            render json: { error: I18n.t("errors.api.no_organization"), code: "no_organization" },
                   status: :unprocessable_content
          end
          format.html do
            render_auth_page(
              title: I18n.t("errors.api.no_organization_title"),
              component: Errors::NoOrganization.new,
              status: :unprocessable_content
            )
          end
        end
      end

      # 4. СТАНДАРТИ ВІДПОВІДЕЙ (The Oracle's Voice)
      #
      # [SEC.25] HTML-гілка тут несуча, бо `authenticate_user!` — `before_action` для
      # ВСЬОГО дашборда: без неї протермінована сесія віддавала реальному користувачеві
      # сирий JSON-блоб замість сторінки логіну, першою ж його дією.
      #
      # 🔴 Чому РЕНДЕР на місці, а не редирект на `/login` — вибір виміряний, не
      # смаковий, і вимір інвертував початкове припущення пункту:
      #   · шість request-прикладів, які «мали б почервоніти» від редиректу, виявились
      #     не недбалими API-тестами, а сигналом: два роблять справжній cookie-логін
      #     через `POST /api/v1/login`, а три б'ють у дії (`codex/matches#new`,
      #     `telemetry#live`, `codex/fractions#picker`), що взагалі не мають
      #     `format.json` — там нема чого «забути попросити»;
      #   · `redirect_to` без `return_to` губить намір: у цьому дереві
      #     `sessions#create` завжди веде на дашборд, тож користувача телепортувало б
      #     геть зі сторінки, яку він відкривав (механізму «повернись назад» немає);
      #   · рендер узгоджений із власним прецедентом — `render_login_failure` нижче
      #     по файлу вже відповідає на «автентифікація не вдалася» саме так: сторінка
      #     логіну на місці, статус 401 в ОБОХ форматах.
      # Наслідок для сумісності: статус лишається 401 і для HTML, тож жоден наявний
      # приклад не змінює поведінки — вони пінять рівно статус.
      def render_unauthorized
        respond_to do |format|
          format.json { render json: { error: I18n.t("errors.api.unauthorized") }, status: :unauthorized }
          format.html do
            render_auth_page(
              title: I18n.t("sessions.login_title"),
              component: Sessions::New.new(flash_alert: I18n.t("errors.api.unauthorized")),
              status: :unauthorized
            )
          end
        end
      end

      def render_forbidden
        render json: { error: I18n.t("errors.api.forbidden") }, status: :forbidden
      end

      def render_forbidden_pundit(_exception)
        render json: { error: I18n.t("errors.api.forbidden") }, status: :forbidden
      end

      def render_not_found(exception)
        render json: { error: I18n.t("errors.api.not_found", model: exception.model) }, status: :not_found
      end

      def render_parameter_missing(exception)
        render json: { error: I18n.t("errors.api.missing_parameter", param: exception.param) }, status: :bad_request
      end

      def render_validation_error(record)
        render json: { errors: record.errors.full_messages }, status: :unprocessable_content
      end

      def render_internal_server_error(exception)
        # Логуємо детальну помилку в консоль/файл, але не показуємо її клієнту
        Rails.logger.fatal "🚨 [API CRITICAL] #{exception.message}\n#{exception.backtrace.first(5).join("\n")}"
        render json: { error: I18n.t("errors.api.internal") }, status: :internal_server_error
      end

      # 5. PAGINATION METADATA (Pagy Helper)
      def pagy_metadata(pagy)
        { page: pagy.page, limit: pagy.limit, count: pagy.count, pages: pagy.last }
      end

      # 6. EWS ALERT COUNT (pre-computed for Sidebar — Rule 3: Zero DB queries in views)
      # Скоуп організації тримають ОБА шари: і запит, і ключ кешу. Раніше не тримав
      # жоден — `EwsAlert.unresolved.count` під глобальним ключем показував бейджем
      # інцидентну активність УСІЄЇ платформи кожному автентифікованому глядачу
      # (виміряно: власних 1, у бейджі 4). Org-сліпий ключ тут не «менша половина»
      # дефекту, а окрема його половина: навіть зі скоупленим запитом перший, хто
      # прогріє кеш, роздав би своє число всім іншим на хвилину.
      # Без організації — 0, а не глобальна сума (fail-closed).
      def ews_alert_count_cached
        org = acting_organization
        return 0 unless org

        Rails.cache.fetch("ews_alert_count_unresolved/org/#{org.id}", expires_in: 1.minute) do
          org.ews_alerts.unresolved.count
        end
      rescue StandardError
        0
      end
    end
  end
end
