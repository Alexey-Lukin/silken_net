# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::Base
      # [SEC.25 Ф2] Кидається `acting_organization!` — тобто В ТОЧЦІ ЧИТАННЯ організації,
      # а не `before_action`-гардом. Різниця несуча: від `BaseController` успадковують і
      # ті, хто організації не має за побудовою — обидва webhook'и, обидва auth-шляхи,
      # `m2m_auth` і платформені (`system_health`, `system_audits`, `organizations`).
      # ⚠️ Приналежність вирішує ДІЯ, а не шар: [SEC.26] дав організацію рівно тому
      # контролеру, що писав у ОПЕРАЦІЙНУ ціль, лишивши його читання org-less. Саме
      # це й показує, чому гард мусить жити в точці читання, а не на класі.
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
      # Resolve `I18n.locale` — повний ланцюг і його стелі живуть у самому
      # концерні (`LocaleSettable`), тут лише реєстрація: акаунт-щабель вимагає
      # ДРУГОГО проходу після автентифікації, див. `set_locale_from_account` нижче.
      # Without this every Dashboard request fell back to `default_locale`
      # because `Api::V1::BaseController` does NOT inherit from
      # `ApplicationController` (which is the one that included the concern
      # historically). The user-visible symptom was "switching the language
      # needs two clicks": the first POST wrote the cookie but the redirected
      # GET ignored it.
      include LocaleSettable

      # [SEC.25 Ф3] Без цього рядка `redirect_to …, success: "…"` НЕ ставить нічого —
      # і мовчки. `ActionController::Flash#redirect_to` перебирає ЛИШЕ `_flash_types`
      # і робить `delete` тільки для них; невідомий ключ їде далі в `Redirecting`,
      # де читають самий `:status`. Ні винятку, ні логу, ні падіння.
      #
      # 🔴 Тому категорії реєструються ТУТ, а не в `ApplicationController`: цей клас
      # успадковує `ActionController::Base` НАПРЯМУ, тож реєстрація в сестри його не
      # покриває — а саме під ним живуть усі сайти kwarg-форми.
      #
      # ⚠️ Регіонів у `FlashMessages` лишається два (a11y-контракт), категорій —
      # чотири (семантика й тон); мапінг тримає компонент, не цей список.
      add_flash_types :success, :error, :pending, :security

      # [SEC.16] Allowlist машинного токена — ВЕСЬ периметр, який прошивка має
      # право торкатись Bearer'ом. Свідомо крихітний, і це не обережність, а
      # вимір: машинних маршрутів [ARCH.77] пʼять, але три з них автентифікуються
      # НЕ токеном (`m2m_auth#create` — Ed25519 у тілі, `oracle_callbacks` і
      # `helium_sos` — HMAC, обидва `skip_before_action :authenticate_user!`).
      # Тобто Bearer-поверхня машини — рівно ці два екшени.
      #
      # 🔴 Форма — ALLOWLIST, ніколи denylist: новий admin-екшен зʼявляється
      # частіше, ніж новий машинний, тож denylist мовчки роздавав би доступ
      # кожному, кого забули дописати. Тут забудькуватість коштує 403 на
      # машинному шляху — гучно й одразу, а не тихо й назавжди.
      M2M_ALLOWED_ACTIONS = {
        "api/v1/m2m_auth" => %w[refresh].freeze,
        "api/v1/telemetry" => %w[gateway_uplink].freeze
      }.freeze

      # --- ПОРЯДОК ЗАХИСТУ ---
      before_action :authenticate_user!
      # [SEC.16] Одразу після автентифікації й ДО будь-якої роботи: машина не
      # сміє дійти навіть до `acting_organization`, якщо вона не на своєму шляху.
      before_action :restrict_machine_scope
      # [I18N.3] Другий прохід резолву локалі — рівно тут і не раніше: `set_locale`
      # реєструється разом із концерном (вище), тобто ДО автентифікації, коли
      # `current_user` ще `nil` і акаунт-щабель порожній за побудовою. Раніше
      # поставити не можна (нема кого читати), а перереєструвати `set_locale`
      # не можна теж — Rails дедуплікує колбеки за іменем фільтра й пересунув би
      # ЄДИНИЙ виклик сюди, лишивши сторінку логіну без мови.
      before_action :set_locale_from_account
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
      rescue_from Pundit::NotAuthorizedError, with: :render_forbidden_pundit

      # ⚠️ `ActiveModel::ValidationError` тут БУВ і знятий свідомо: його кидає лише
      # `validate!`, якого в дереві нема жодного, а сам виняток несе `#model`, не
      # `#record`, тож хендлер упав би `NoMethodError` ще до рендера. Сам
      # `render_validation_error` живий — його кличуть прямо, зсередини `format.json`.
      #
      # 🔴 І сусіда — `ActiveRecord::RecordInvalid` (у нього `#record` є, тобто
      # сигнатура збіглася б) — сюди свідомо НЕ додаємо. Він летить у
      # `StandardError` → 500, і це правильно: користувацький ввід контролери
      # гардять явно ДО bang-мутації (див. обидва шляхи зміни пароля), тож
      # `RecordInvalid`, що долетів сюди, означає пропущений гард — наш баг, а не
      # помилку людини. М'яка 422 його б замаскувала.

      # --- ХЕЛПЕРИ ДОСТУПУ ---
      # Робимо методи доступними в Phlex-компонентах через хелпери Rails
      helper_method :current_user, :signed_in?, :acting_organization

      private

      # [SEC.16/S6.21] ЄДИНА точка встановлення сесії — тепер на предку, бо шляхів
      # входу два (пароль · MFA-челендж), а формула одна:
      # anti-fixation reset → cookie-пара `user_id`+`ps` (salt-stamp гасить крадені
      # cookie на зміні пароля) → Session-рядок → touch. Друга рукописна копія цієї
      # формули вже одного разу розширила периметр salt-звіряльників непомітно —
      # тому дім один, і він тут.
      def establish_session(user)
        reset_session
        session[:user_id] = user.id
        session[:ps] = user.session_salt_stamp

        user.sessions.create!(
          ip_address: request.remote_ip,
          user_agent: request.user_agent.presence || "Unknown"
        )
        user.touch_visit!
      end

      # JSON-успіх входу (Bearer-токен) — спільний для пароль- і MFA-фіналу.
      def render_api_login_success(user)
        token = user.generate_token_for(:api_access)
        render json: {
          token: token,
          user: { id: user.id, email: user.email_address, full_name: user.full_name, role: user.role }
        }, status: :created
      end

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
        #
        # [SEC.16] Два purpose, і порядок тут не має значення (вони ізольовані
        # криптографічно — токен одного не резолвиться іншим). Значення має те,
        # що ми ЗАПАМʼЯТОВУЄМО, який саме спрацював: далі `restrict_machine_scope`
        # тримає машину в межах її allowlist'а.
        @current_user = authenticate_with_http_token do |token, _options|
          human = User.find_by_token_for(:api_access, token)
          next human if human

          machine = User.find_by_token_for(:m2m_access, token)
          @machine_token = true if machine
          machine
        end

        # Спроба 2: Перевірка через сесію Rails 8 (для Дашборду в браузері).
        # [SEC.16] Cookie salt-bound (дзеркало api_access-токена в User):
        # зміна пароля міняє password_salt → чужий/викрадений cookie гасне
        # одразу, а не доживає свої 14 днів.
        if @current_user.nil? && session[:user_id]
          user = User.find_by(id: session[:user_id])
          @current_user = user if user&.session_salt_matches?(session[:ps])
        end

        return render_unauthorized unless @current_user

        @current_user.touch_visit! # Оновлюємо "пульс" активності користувача
      end

      def current_user
        @current_user
      end

      # [SEC.16] Машина ≠ людина-адмін. Доти `m2m_auth#create` видавав шлюзові
      # `:api_access` першого org-admin'а — токен, нерозрізнимий від людського,
      # тобто фізично захоплена Королева давала повний admin-API організації.
      # Тепер той токен має власний purpose, і ось де він упирається в стелю.
      #
      # ⚠️ Відповідь 403, а не 401: токен ВАЛІДНИЙ, просто не для цього шляху —
      # 401 сказав би прошивці «перевидай токен», і вона крутила б Ed25519-цикл
      # проти дверей, які їй не відчиняться ніколи.
      # Чи автентифікований цей запит МАШИННИМ токеном. Читає `m2m_auth#refresh`,
      # щоб перевидати той самий purpose (інакше машина підвищувала б себе).
      def machine_token?
        @machine_token.present?
      end

      def restrict_machine_scope
        return unless machine_token?
        return if M2M_ALLOWED_ACTIONS[controller_path]&.include?(action_name)

        Rails.logger.warn(
          "🚨 [SEC.16] M2M-токен спробував #{controller_path}##{action_name} — поза allowlist'ом"
        )
        render json: { error: I18n.t("errors.api.forbidden"), code: "m2m_scope" }, status: :forbidden
      end

      # [I18N.3] Реалізація hook'а `LocaleSettable#locale_account`: саме тут живе
      # єдиний у дереві автентифікований користувач, тож саме тут концерн дістає
      # persisted-вподобу (`users.locale`). Сестра `ApplicationController` цього
      # методу не має за побудовою — під нею лише `LocalesController`, який
      # користувача резолвить сам, під salt-гардом SEC.16.
      def locale_account
        current_user
      end

      # [SEC.25 Ф2] Pundit дістає не користувача, а пару «хто + в контексті якої
      # організації» — бо організація запиту більше не виводиться з користувача
      # (super_admin її перемикає).
      #
      # ⚠️ `current_user &&` тут несуче, а не оборонний рефлекс: без нього анонімний
      # запит (`skip_before_action :authenticate_user!` — webhook'и, логін) дістав би
      # обгортку навколо `nil`, а обгортка — це об'єкт, тобто `present?` каже `true`.
      # Кожен `return scope.none unless user` у політиках перевернувся б на fail-OPEN. Нема користувача — нема пари.
      def pundit_user
        current_user && UserContext.new(current_user, acting_organization)
      end

      def signed_in?
        current_user.present?
      end

      # 2. ПРАВА ДОСТУПУ (RBAC) — рольові предикати, НЕ перехідний шар.
      #
      # 🔴 Тут стояв `TODO: перенести всі контролери на Pundit і видалити ці
      # методи` — план, ⚖️ ВІДХИЛЕНИЙ 2026-07-31 (`04_03 §3`): асоціативний скоуп
      # ратифіковано як АРХІТЕКТУРУ, не борг, `verify_authorized` закрито як
      # won't-do, десять мертвих політик знято разом зі спеками. TODO пережив
      # власну підставу мовчки — він не мав ID, тож жоден свіп по трекеру його не
      # бачив, і читач діставав припис робити те, що присуд заборонив [DOC-T.93,
      # знято 2026-08-27]. Клас — «відкинута вокабуляра повертається ПЕРЕвиведенням»:
      # «уніфікувати все на Pundit» звучить очевидно добре, тому й відроджується.
      #
      # Розподіл ролей, який тут ЧИННИЙ: Pundit — де питання предикатне
      # (роль × авторство); асоціативний скоуп від `acting_organization!` — де
      # питання про приналежність (чужий запис не матеріалізується взагалі).
      # Обидва хелпери нижче — жива рольова половина, її кличуть вісім контролерів.
      def authorize_admin!
        render_forbidden unless current_user&.admin_or_above?
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
      # [SEC.25] `flash:` передається ЯВНО, і це єдина точка його читання в дереві.
      # Компонент навмисно не звертається до `helpers.flash`: поза request-контекстом
      # (компонентні спеки йдуть через `ApplicationController.renderer`) `helpers`
      # дорівнює nil, тож амбієнтне читання зробило б layout нерендерабельним там,
      # де решта дерева рендериться нормально. Та сама причина, що в `current_user`
      # і `ews_alert_count` — layout приймає дані, а не ходить по них сам.
      def render_dashboard(title:, component:, status: :ok)
        render DashboardLayout.new(
          title: title,
          current_user: current_user,
          current_path: request.path,
          ews_alert_count: ews_alert_count_cached,
          flash: flash.to_hash,
          # [UI.6] Не-bang: цей хелпер обслуговує ВСІ 66 дашборд-рендерів, зокрема
          # сторінки, що організації не потребують. Bang перетворив би індикатор на
          # гард і поклав би карантин на платформені сторінки.
          acting_organization: acting_organization,
          content: component
        ), status: status
      end

      # Метод для рендерингу standalone auth-сторінок (login, forgot/reset password).
      # Забезпечує повний HTML-документ з CSS/JS includes без sidebar/DashboardLayout.
      # `title:` обов'язковий: усі сім викликачів і так передають його явно, тож
      # англійський дефолт «Access Portal» був недосяжним рядком, який мовчки
      # чекав першого викликача, що його забуде. Видалення дешевше за переклад.
      def render_auth_page(title:, component:, status: :ok)
        render AuthLayout.new(title: title, flash: flash.to_hash, content: component), status: status
      end

      # [SEC.25 Ф2] Організація, в контексті якої виконується ЦЕЙ запит.
      #
      # Для всіх, крім super_admin, це завжди власна організація — сесія тут свідомо
      # ІГНОРУЄТЬСЯ, а не звіряється: інакше переведення користувача в іншу організацію
      # лишало б його сесію дивитись на стару. Право перемикатись — платформена
      # здатність super_admin'а, а не властивість членства.
      #
      # Носій — `session[:acting_org_id]` (per-device, сусідить із `:user_id`/`:ps`),
      # а не колонка на `users`: стан ПЕРЕГЛЯДУ не є членством, і колонка пережила б
      # і сесію, і пристрій (перемкнувся на ноуті — змінилось на телефоні;
      # перемкнувся місяць тому — сьогодні тихо дивишся не туди).
      #
      # ⚠️ Точна межа життя, бо цей рядок доти обіцяв більше, ніж код робить: гине не
      # на логауті, а на наступному ЛОГІНІ. `sessions#destroy` знімає лише
      # `session[:user_id]`, `reset_session` живе в `establish_session` — тобто між
      # виходом і входом значення лежить у cookie. Наслідків це не має (без
      # `:user_id` запит не автентифікується), але передумову ставити на нього не
      # можна.
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
      # (платформені, webhook'и), не мусять падати лише через те, що ми
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
          format.any do
            render json: { error: I18n.t("errors.api.no_organization"), code: "no_organization" },
                   status: :unprocessable_content
          end
          format.html do
            render_auth_page(
              title: I18n.t("errors.api.no_organization_title"),
              # [UI.6] Актор потрібен, щоб сторінка знала, чи є звідси вихід:
              # super_admin без організації — це типовий перший вхід, і йому треба
              # не «зверніться до адміністратора», а реєстр кланів.
              component: Errors::NoOrganization.new(current_user: current_user),
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
      #     через `POST /login`, а решта б'ють у дії (як `telemetry#live`), що взагалі
      #     не мають `format.json` — там нема чого «забути попросити»;
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
          format.any { render json: { error: I18n.t("errors.api.unauthorized") }, status: :unauthorized }
          format.html do
            render_auth_page(
              title: I18n.t("sessions.login_title"),
              component: Sessions::New.new(flash_alert: I18n.t("errors.api.unauthorized")),
              status: :unauthorized
            )
          end
        end
      end

      # [UI.9] HTML-гілка тут така ж несуча, як у `render_forbidden_pundit` нижче, і
      # відсутня вона була не за задумом, а тому, що ніхто нею не ходив: **12**
      # контролерів тримають КЛАСОВИЙ `authorize_*!`, тож будь-хто, хто набрав їхню
      # адресу з браузера, діставав сирий JSON-блоб замість сторінки відмови. Два
      # контролери свого часу вже наткнулись і залатали локально — тобто симптом був
      # відомий, а корінь лишався жити.
      #
      # Шаблон — dashboard, з тієї самої підстави, що й у pundit-близнюка: усі
      # виклики стоять ПІСЛЯ `authenticate_user!`, тобто це свій автентифікований
      # користувач, якому не можна САМЕ це, а не чужий системі глядач.
      def render_forbidden
        respond_to do |format|
          format.json { render_forbidden_json }
          format.html do
            render_dashboard(
              title: I18n.t("errors.api.forbidden_title"),
              component: Errors::Page.new(
                heading: I18n.t("errors.api.forbidden_title"),
                message: I18n.t("errors.api.forbidden"),
                tone: :warning
              ),
              status: :forbidden
            )
          end
        end
      end

      # Один дім JSON-половини: локальні гарди, що вже мають власний `respond_to`
      # (м'яка посадка замість сторінки відмови — `maintenance_records`,
      # `maintenance_record_photos`), кличуть саме його.
      #
      # ⚠️ Тут довго стояло «інакше вийшов би вкладений `respond_to`, і це
      # зламало б виклик» — НЕПРАВДА, знято adversarial-проходом 2026-08-01.
      # `RespondToMismatchError` кидається лише коли формат УЖЕ відрендерено в
      # інший тип; json-у-json проходить, і доказ поруч — `render_validation_error`
      # має власний `respond_to`, а всі його викликачі сидять усередині
      # `format.json` (`tree_families`, `maintenance_records`, `firmwares`,
      # `provisioning`), і ці гілки виконуються зеленими прикладами.
      # Чинна підстава вужча й чесна: окремий метод робить JSON-половину ОДНИМ
      # домом — а не рятує від поломки, якої немає.
      def render_forbidden_json
        render json: { error: I18n.t("errors.api.forbidden") }, status: :forbidden
      end

      # [SEC.25] HTML-гілка в DASHBOARD-шаблоні, не в auth: усі 17 досяжних із браузера
      # `authorize`-викликів живуть у діях, де користувач гарантовано автентифікований
      # (жоден не в `skip_before_action :authenticate_user!`-контролері). Тобто це не
      # «чужий системі» глядач, як у `render_unauthorized`, а свій, якому не можна САМЕ
      # це — і сайдбар йому чесний та корисний, а не бутафорія.
      def render_forbidden_pundit(_exception)
        respond_to do |format|
          format.json { render_forbidden_json }
          # [UI.7] `format.any` — щоб відмова існувала для КОЖНОГО формату: перший
          # не-json/html маршрут (`wallets#ledger.csv`) показав, що всі рендерери
          # відмов на такому запиті вироджувались у 406 UnknownFormat — тобто
          # «формат не підтримується» замість чесного 403/404/401. Хвіст додано
          # рівно в пʼять рендерерів, досяжних із того шляху; parameter_missing /
          # validation_error / render_forbidden лишаються двоформатними, доки не
          # зʼявиться не-json/html маршрут, що їх досягає.
          format.any { render_forbidden_json }
          format.html do
            render_dashboard(
              title: I18n.t("errors.api.forbidden_title"),
              component: Errors::Page.new(
                heading: I18n.t("errors.api.forbidden_title"),
                message: I18n.t("errors.api.forbidden"),
                tone: :warning
              ),
              status: :forbidden
            )
          end
        end
      end

      # [SEC.25] Так само дашборд: 31 із 43 `find`-сайтів сидять у діях із `format.html`,
      # тобто типовий шлях сюди — протухле посилання або чужий id, а не поламана сесія.
      # `exception.model` лишається в обох гілках — воно й формує людське речення.
      def render_not_found(exception)
        respond_to do |format|
          format.json { render json: { error: I18n.t("errors.api.not_found", model: exception.model) }, status: :not_found }
          format.any { render json: { error: I18n.t("errors.api.not_found", model: exception.model) }, status: :not_found }
          format.html do
            render_dashboard(
              title: I18n.t("errors.api.not_found_title"),
              component: Errors::Page.new(
                heading: I18n.t("errors.api.not_found_title"),
                message: I18n.t("errors.api.not_found", model: exception.model),
                tone: :info
              ),
              status: :not_found
            )
          end
        end
      end

      # [UI.9] Останні два JSON-only рендерери. Досяжні саме з БРАУЗЕРА і саме через
      # форми: `params.require` стоїть у `settings`, `maintenance_records`,
      # `tree_families` — усі під `format.html`-екшенами. Тобто
      # сабміт форми з обрізаним полем віддавав користувачеві сирий JSON.
      #
      # ⚠️ Тут свідомо НЕ показуємо `exception.param` / `record.errors` у HTML: JSON
      # тримає їх для клієнта, що вміє їх прочитати, а сторінка каже людською мовою.
      # Це не втрата — деталь помилки форми належить самій формі, а сюди виняток
      # долітає лише тоді, коли форму обійшли.
      def render_parameter_missing(exception)
        respond_to do |format|
          format.json do
            render json: { error: I18n.t("errors.api.missing_parameter", param: exception.param) },
                   status: :bad_request
          end
          format.html { render_error_page(:bad_request_title, :bad_request, status: :bad_request) }
        end
      end

      def render_validation_error(record)
        respond_to do |format|
          format.json { render json: { errors: record.errors.full_messages }, status: :unprocessable_content }
          format.html do
            render_error_page(:validation_failed_title, :validation_failed, status: :unprocessable_content)
          end
        end
      end

      # Один дім HTML-половини для рендерерів, що ведуть у дашборд-шаблон: глядач
      # автентифікований, тож навігація йому чесна й корисна.
      def render_error_page(title_key, message_key, status:)
        render_dashboard(
          title: I18n.t("errors.api.#{title_key}"),
          component: Errors::Page.new(
            heading: I18n.t("errors.api.#{title_key}"),
            message: I18n.t("errors.api.#{message_key}"),
            tone: :warning
          ),
          status: status
        )
      end

      # [SEC.25] 🔴 ЄДИНИЙ із трьох, що йде в AUTH-шаблон, і це не смак: тут catch-all
      # для всієї поверхні застосунку, включно зі шляхами, де `current_user` ще НЕ
      # присвоєний (CSRF-виняток летить із `handle_unverified_request`, тобто ДО
      # `authenticate_user!`), і зі сценарієм «помилка зродилась усередині спроби щось
      # відрендерити». `AuthLayout` не залежить ні від користувача, ні від сайдбара, ні
      # від бейджа — останній рубіж тримаємо максимально тонким.
      def render_internal_server_error(exception)
        # Логуємо детальну помилку в консоль/файл, але не показуємо її клієнту
        Rails.logger.fatal "🚨 [API CRITICAL] #{exception.message}\n#{exception.backtrace.first(5).join("\n")}"
        respond_to do |format|
          format.json { render json: { error: I18n.t("errors.api.internal") }, status: :internal_server_error }
          format.any { render json: { error: I18n.t("errors.api.internal") }, status: :internal_server_error }
          format.html do
            render_auth_page(
              title: I18n.t("errors.api.internal_title"),
              component: Errors::Page.new(
                heading: I18n.t("errors.api.internal_title"),
                message: I18n.t("errors.api.internal"),
                tone: :danger
              ),
              status: :internal_server_error
            )
          end
        end
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

        # [UI.11] Без `expires_in`: кеш гаситься НА ЗАПИСІ (`EwsAlert`
        # after_commit), тобто живе рівно доки число чинне. TTL тут був проксі
        # для «щось змінилось», хоча момент зміни відомий точно — і при 60 с
        # бейдж відставав від живої стрічки тривог у дванадцять разів.
        # Ключ — з дому `Organization#alert_count_cache_key`, той самий, що
        # читає гасильник: рукописний дубль розійшовся б МОВЧКИ.
        Rails.cache.fetch(org.alert_count_cache_key) do
          org.ews_alerts.unresolved.count
        end
      rescue StandardError
        0
      end
    end
  end
end
