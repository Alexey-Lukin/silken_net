# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.25] Реєстр виключень інваріанта `04_03 §2.2б` — ДАНІ, а не перевірки.
#
# Живе окремим файлом свідомо: це артефакт, який читають як документ, і кожен
# його рядок — рішення людини («чому цей вхід законно відповідає JSON» +
# «за якої події рядок звідси зникає»). Перевірки, що його вживають, —
# `spec/security/browser_contour_json_spec.rb`.
#
# 🧱 Мапа ЛИШЕ СКОРОЧУЄТЬСЯ. Дописувати рядок можна тільки разом із підставою
# та умовою повернення; голий запис відхиляє власний ліхтар гейта.
module BrowserContourRegistry
    # ─── МАШИННИЙ КОНТУР ────────────────────────────────────────────────────────
    # Клієнта відвантажує НЕ Rails (прошивка, чужий оракул, orchestrator).
    MACHINE = {
      "app/controllers/api/v1/m2m_auth_controller.rb#create" =>
        "Ed25519-підпис у тілі; шлюз у полі. Повертається, якщо з'явиться браузерна форма видачі токена",
      "app/controllers/api/v1/m2m_auth_controller.rb#refresh" =>
        "Bearer-only оновлення токена. Повертається разом із UI керування M2M-доступом",
      "app/controllers/api/v1/oracle_callbacks_controller.rb#create" =>
        "Chainlink DON, HMAC-SHA256. Браузерного шляху не існує за визначенням",
      "app/controllers/api/v1/oracle_callbacks_controller.rb#verify_chainlink_signature!" =>
        "guard того ж вебхука",
      "app/controllers/api/v1/helium_sos_controller.rb#create" =>
        "Helium Console webhook, HMAC-SHA256",
      "app/controllers/api/v1/helium_sos_controller.rb#verify_helium_signature!" =>
        "guard того ж вебхука",
      "app/controllers/readiness_controller.rb#show" =>
        "orchestrator-проба; ⚠️ НЕ має префікса /api/v1 — машинна за КЛІЄНТОМ, не за адресою",
      "app/controllers/api/v1/telemetry_controller.rb#gateway_uplink" =>
        "HTTP-фолбек CoAP-каналу від Королеви. ⚠️ Підстава ВУЖЧА, ніж здається: крипто-гарда тут " \
        "немає (звичайний authenticate_user!), тобто машинність тримається на відсутності UI. " \
        "Повертається, щойно з'явиться ручне завантаження телеметрії"
    }.freeze

    # ─── ПРИВАТНІ JSON-ХЕЛПЕРИ ──────────────────────────────────────────────────
    # Не екшени: їх кличуть ІЗСЕРЕДИНИ `format.json`-гілок.
    HELPERS = {
      "app/controllers/api/v1/base_controller.rb#render_forbidden_json" =>
        "JSON-половина спільного 403; HTML-половину несе Errors::Page",
      "app/controllers/api/v1/sessions_controller.rb#render_api_login_success" =>
        "JSON-половина логіну; браузерна гілка редиректить",
      "app/controllers/api/v1/codex/attunements_controller.rb#render_validation" =>
        "приватний рендерер, кличеться з format.json",
      "app/controllers/api/v1/codex/citations_controller.rb#resolve_target!" =>
        "guard, кличеться до розгалуження формату"
    }.freeze

    # ─── JSON-ONLY ЗА ЗАДУМОМ (окремий ID) ──────────────────────────────────────
    # UI для них — ФІЧА, не фікс дефекту; присуд «будувати чи ні» відкритий в UI.8.
    ADMIN_REASON =
      "[UI.8] Уся лор-адмінка Codex керується через curl: `app/views/components/codex/admin/` " \
      "не існує, і `routes.rb` це прямо декларує. Присуд «будувати UI чи лишити машинним» " \
      "ВІДКРИТИЙ в UI.8 — тобто це не дефект із відомим ліком, а нерозв'язане питання наміру. " \
      "Умова повернення: щойно з'явиться перший Phlex-компонент цієї адмінки"

    CITATIONS_REASON =
      "[UI.8] Повна логіка створення/видалення цитат існує, а жодної кнопки чи форми немає — " \
      "слід просто в коді: `Codex::Citations::Strip` приймає `current_user:` і ніде його не читає. " \
      "Умова повернення: перша кнопка цитування в UI"

    BY_DESIGN = (
      %w[index show create update destroy].map { |a| "app/controllers/api/v1/codex/admin/discovery_rules_controller.rb##{a}" } +
      %w[index show create update destroy].map { |a| "app/controllers/api/v1/codex/admin/nodes_controller.rb##{a}" }
    ).index_with { ADMIN_REASON }.merge(
      "app/controllers/api/v1/codex/citations_controller.rb#create" => CITATIONS_REASON,
      "app/controllers/api/v1/codex/citations_controller.rb#destroy" => CITATIONS_REASON
    ).freeze

    # ─── ЛАТЕНТНІ: гілка існує, UI-джерела нема ─────────────────────────────────
    # 🔴 Свідомо НЕ лагодимо: фікс недосяжної гілки купує вакуумний пін проти
    # промаху, якого ніхто не побачить. Умова повернення в КОЖНОМУ рядку — і вона
    # не декоративна: один лінк перетворює запис на must-fix.
    LATENT = {
      "app/controllers/api/v1/firmwares_controller.rb#deploy" =>
        "три гарди за target_type/cluster_id, а обидві форми деплою шлють лише CSRF-токен. Повертається, щойно у формі з'явиться бодай одне з цих полів",
      "app/controllers/api/v1/firmwares_controller.rb#inventory" =>
        "лінка на inventory_firmwares_path немає ніде; панель годується @inventory_stats з #index. Повертається з першим лінком",
      "app/controllers/api/v1/firmwares_controller.rb#create" =>
        "обхід multipart-ліміту через bytecode_payload — поля немає у формі. Повертається, якщо поле з'явиться",
      "app/controllers/api/v1/contracts_controller.rb#stats" =>
        "нуль лінків і нуль fetch() у app/javascript. Повертається з першим споживачем",
      "app/controllers/api/v1/telemetry_controller.rb#tree_history" =>
        "графік історії; споживача (лінк чи fetch) не існує. Повертається з першим",
      "app/controllers/api/v1/telemetry_controller.rb#gateway_history" =>
        "дзеркало tree_history, той самий статус",
      "app/controllers/api/v1/alerts_controller.rb#index" =>
        "гарди невалідного status/severity у query — жоден UI-елемент такого значення не породжує",
      "app/controllers/api/v1/blockchain_transactions_controller.rb#index" =>
        "той самий клас query-гарда",
      "app/controllers/api/v1/maintenance_records_controller.rb#index" =>
        "той самий клас (невалідна ISO-дата у query)",
      "app/controllers/api/v1/actuators_controller.rb#execute" =>
        "400 на відсутній Idempotency-Key гейтований `request.format.json?`, тож браузер туди не доходить; другий — віддача кешованої відповіді",
      "app/controllers/api/v1/codex/comments_controller.rb#create" =>
        "422 досяжна (пробіли проходять HTML5 required), але Turbo на JSON не робить НІЧОГО — симптом тиша, не блоб. Тримається тут як найгостріший кандидат на повернення",
      "app/controllers/api/v1/codex/fractions_controller.rb#create" =>
        "422 потребує гонки життєвого циклу вузла",
      "app/controllers/api/v1/oracle_visions_controller.rb#simulate" =>
        "дім присуду — UI.7 (тракт мертвий тричі, включно з неіснуючим воркером); тут лише щоб гейт не червонів"
    }.freeze

    # ─── CSRF: машинні входи [SEC.30] ───────────────────────────────────────
    # Значення = ОБСЯГ зняття: `:all` — контролер суто машинний; `:partial` —
    # у ньому є дія, що автентифікується cookie-сесією, тож зняття мусить бути
    # `only:` (інакше машинний вхід лагодиться ціною відкриття браузерного).
    MACHINE_ENTRIES = {
      "Api::V1::OracleCallbacksController" => :all,
      "Api::V1::HeliumSosController" => :all,
      "Api::V1::M2mAuthController" => :partial
    }.freeze

    ALL = [ MACHINE, HELPERS, BY_DESIGN, LATENT ].reduce(:merge).freeze
end
