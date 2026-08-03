# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.25] Реєстр виключень інваріанта `04_03 §2.2б` — ДАНІ, а не перевірки.
#
# Живе окремим файлом свідомо: це артефакт, який читають як документ, і кожен
# його рядок — рішення людини («чому цей вхід законно відповідає JSON» +
# «за якої події рядок звідси зникає»). Перевірки, що його вживають, —
# `spec/security/browser_contour_json_spec.rb`.
#
# 🧱 Мапа ЛИШЕ СКОРОЧУЄТЬСЯ. Кожен запис — хеш із ДВОХ полів:
#   · `why`  — підстава, чому цей вхід законно відповідає JSON (обовʼязкова завжди);
#   · `back` — УМОВА ПОВЕРНЕННЯ: подія, після якої рядок звідси зникає, а гілка
#     стає must-fix. Обовʼязкова для LATENT і BY_DESIGN (вони тимчасові за
#     визначенням). `:none` дозволене лише MACHINE/HELPERS і означає «браузерного
#     двійника цій дії не існує», а не «я не придумав».
#
# 🔴 Чому поле, а не фраза в прозі [SEC.31]. Ця конвенція була заявлена тут із
# дня народження файла — і **17 із 37 записів її не виконували**, бо міряти її
# не було чим: єдиний ліхтар дивився на ДОВЖИНУ рядка підстави.
#
# ⚠️ Число залежить від критерію, і саме ця залежність доводить форму ліку:
# рахуючи за СЛОВОМ, дістаєш 16, рахуючи за названою ПОДІЄЮ — 17. Різниця рівно
# один рядок («найгостріший кандидат на повернення»), де слово присутнє, а події
# немає. Тобто лексичний гейт зарахував би його як виконаний — він міряв би
# словник. Плюс червонів би на чесній DRY-прозі («той самий клас query-гарда») і
# задовольнявся б дописуванням порожнього речення. Окреме поле задовольнити
# красномовством не можна: його або заповнено, або ні.
module BrowserContourRegistry
    # ─── МАШИННИЙ КОНТУР ────────────────────────────────────────────────────────
    # Клієнта відвантажує НЕ Rails (прошивка, чужий оракул, orchestrator).
    MACHINE = {
      "app/controllers/api/v1/m2m_auth_controller.rb#create" => {
        why:  "Ed25519-підпис у тілі; шлюз у полі",
        back: "зʼявиться браузерна форма видачі токена"
      },
      "app/controllers/api/v1/m2m_auth_controller.rb#refresh" => {
        why:  "Bearer-only оновлення токена",
        back: "зʼявиться UI керування M2M-доступом"
      },
      "app/controllers/api/v1/oracle_callbacks_controller.rb#create" => {
        why:  "Chainlink DON, HMAC-SHA256; браузерного шляху не існує за визначенням",
        back: :none
      },
      "app/controllers/api/v1/oracle_callbacks_controller.rb#verify_chainlink_signature!" => {
        why:  "приватний guard того ж вебхука — не екшен, тож власного контуру не має",
        back: :none
      },
      "app/controllers/api/v1/helium_sos_controller.rb#create" => {
        why:  "Helium Console webhook, HMAC-SHA256; клієнт — чужий оркестратор",
        back: :none
      },
      "app/controllers/api/v1/helium_sos_controller.rb#verify_helium_signature!" => {
        why:  "приватний guard того ж вебхука — не екшен, тож власного контуру не має",
        back: :none
      },
      "app/controllers/readiness_controller.rb#show" => {
        why:  "orchestrator-проба; ⚠️ НЕ має префікса /api/v1 — машинна за КЛІЄНТОМ, не за адресою. " \
              "⚠️ І це ТРЕТІЙ корінь ієрархії (успадковує ActionController::Base напряму), " \
              "через який CSRF-половина колись міряла неповну множину [SEC.31]",
        back: :none
      },
      "app/controllers/api/v1/telemetry_controller.rb#gateway_uplink" => {
        why:  "HTTP-фолбек CoAP-каналу від Королеви. ⚠️ Підстава ВУЖЧА, ніж здається: крипто-гарда " \
              "тут немає (звичайний authenticate_user!), тобто машинність тримається на відсутності UI",
        back: "зʼявиться ручне завантаження телеметрії"
      }
    }.freeze

    # ─── ПРИВАТНІ JSON-ХЕЛПЕРИ ──────────────────────────────────────────────────
    # Не екшени: їх кличуть ІЗСЕРЕДИНИ `format.json`-гілок. Саме тому `back: :none`
    # тут структурний, а не оцінковий: власного контуру хелпер не має взагалі, і
    # умова його повернення — це умова повернення ВИКЛИКАЧА, тобто чужий рядок.
    HELPERS = {
      "app/controllers/api/v1/base_controller.rb#render_forbidden_json" => {
        why:  "JSON-половина спільного 403; HTML-половину несе Errors::Page",
        back: :none
      },
      "app/controllers/api/v1/sessions_controller.rb#render_api_login_success" => {
        why:  "JSON-половина логіну; браузерна гілка редиректить",
        back: :none
      },
      "app/controllers/api/v1/codex/attunements_controller.rb#render_validation" => {
        why:  "приватний рендерер, кличеться з format.json",
        back: :none
      },
      "app/controllers/api/v1/codex/citations_controller.rb#resolve_target!" => {
        why:  "guard, кличеться до розгалуження формату",
        back: :none
      }
    }.freeze

    # ─── JSON-ONLY ЗА ЗАДУМОМ (окремий ID) ──────────────────────────────────────
    # UI для них — ФІЧА, не фікс дефекту; присуд «будувати чи ні» відкритий в UI.8.
    #
    # ⚠️ Рахуючи покриття цієї секції, рахуй УНІКАЛЬНІ підстави, а не ключі: 12
    # ключів несуть рівно ДВІ написані людиною підстави. Ключі тут множаться по
    # екшенах одного контролера, тож «12 із 12 мають умову повернення» — вимір
    # приладу, а не роботи; людина написала дві.
    ADMIN_REASON = {
      why:  "[UI.8] Уся лор-адмінка Codex керується через curl: `app/views/components/codex/admin/` " \
            "не існує, і `routes.rb` це прямо декларує. Присуд «будувати UI чи лишити машинним» " \
            "ВІДКРИТИЙ в UI.8 — тобто це не дефект із відомим ліком, а нерозв'язане питання наміру",
      back: "зʼявиться перший Phlex-компонент цієї адмінки"
    }.freeze

    CITATIONS_REASON = {
      why:  "[UI.8] Повна логіка створення/видалення цитат існує, а жодної кнопки чи форми немає — " \
            "слід просто в коді: `Codex::Citations::Strip` приймає `current_user:` і ніде його не читає",
      back: "перша кнопка цитування в UI"
    }.freeze

    BY_DESIGN = (
      %w[index show create update destroy].map { |a| "app/controllers/api/v1/codex/admin/discovery_rules_controller.rb##{a}" } +
      %w[index show create update destroy].map { |a| "app/controllers/api/v1/codex/admin/nodes_controller.rb##{a}" }
    ).index_with { ADMIN_REASON }.merge(
      "app/controllers/api/v1/codex/citations_controller.rb#create" => CITATIONS_REASON,
      "app/controllers/api/v1/codex/citations_controller.rb#destroy" => CITATIONS_REASON
    ).freeze

    # ─── ЛАТЕНТНІ: гілка існує, але з UI до неї не дійти ────────────────────────
    # 🔴 Підвидів ЧОТИРИ, і назва секції описує лише перший — тож підвид кожного
    # рядка названо в його ж `why`, інакше категорія бреше за читача:
    #   (а) UI-джерела нема — елемента, що породжує цей ввід, не існує (більшість);
    #   (б) джерело Є, але шлях падає РАНІШЕ (неіснуючий символ), тож недосяжність
    #       побічна — і зникає від ЧУЖОГО фіксу, не від нашого (`oracle_visions`);
    #   (в) гілка взагалі ДОСЯЖНА, відкладена лише через мʼякший симптом — тиша
    #       замість блоба (`codex/comments`). Це найкрихкіший підвид: він тримається
    #       не на недосяжності, а на оцінці шкоди;
    #   (г) джерело Є і сервіс СЮДИ відповідає — гілку закриває скоуп у СУСІДНЬОМУ
    #       екшені, тобто недосяжність тримає код, якого цей рядок не називає
    #       (`codex/fractions`); залишок тут — гонка, а не неможливість.
    # ⚠️ Підвид (г) знайдено adversarial-проходом уже ПІСЛЯ того, як таксономію
    # оголосили повною на трьох: класифікація без комірки для рядка не червоніє —
    # вона просто мовчки кладе його в найближчу.
    # 🔴 Свідомо НЕ лагодимо: фікс недосяжної гілки купує вакуумний пін проти
    # промаху, якого ніхто не побачить. `back` тут ОБОВʼЯЗКОВИЙ (`:none` заборонено
    # гейтом) — один лінк перетворює запис на must-fix.
    LATENT = {
      "app/controllers/api/v1/firmwares_controller.rb#deploy" => {
        why:  "три гарди за target_type/cluster_id, а обидві форми деплою шлють лише CSRF-токен",
        back: "у формі зʼявиться бодай одне з цих полів"
      },
      "app/controllers/api/v1/firmwares_controller.rb#inventory" => {
        why:  "лінка на inventory_firmwares_path немає ніде; панель годується @inventory_stats з #index",
        back: "перший лінк на inventory_firmwares_path"
      },
      "app/controllers/api/v1/firmwares_controller.rb#create" => {
        why:  "обхід multipart-ліміту через bytecode_payload — поля немає у формі",
        back: "поле bytecode_payload зʼявиться у формі"
      },
      "app/controllers/api/v1/contracts_controller.rb#stats" => {
        why:  "нуль лінків і нуль fetch() у app/javascript",
        back: "перший споживач — лінк або fetch"
      },
      "app/controllers/api/v1/telemetry_controller.rb#tree_history" => {
        why:  "графік історії; споживача (лінк чи fetch) не існує",
        back: "перший споживач — лінк або fetch"
      },
      "app/controllers/api/v1/telemetry_controller.rb#gateway_history" => {
        why:  "дзеркало tree_history, той самий статус",
        back: "перший споживач — лінк або fetch, так само як у tree_history"
      },
      "app/controllers/api/v1/alerts_controller.rb#index" => {
        why:  "гарди невалідного status/severity у query — жоден UI-елемент такого значення не " \
              "породжує. ⚠️ Недосяжність тримається на ВІДНОШЕННІ `FILTER_SEVERITIES ⊆ enum severity`, " \
              "а чіпа для `status` немає взагалі; жоден приклад цього відношення не пінить",
        back: "UI почне породжувати значення поза `FILTER_SEVERITIES`, або зʼявиться чіп для `status`"
      },
      "app/controllers/api/v1/blockchain_transactions_controller.rb#index" => {
        why:  "той самий клас query-гарда",
        back: "UI почне породжувати невалідне значення в query"
      },
      "app/controllers/api/v1/maintenance_records_controller.rb#index" => {
        why:  "той самий клас (невалідна ISO-дата у query)",
        back: "UI почне породжувати невалідну дату в query"
      },
      "app/controllers/api/v1/actuators_controller.rb#execute" => {
        why:  "ПЕРШИЙ сайт (400 на відсутній Idempotency-Key) гейтований `request.format.json?`, тож " \
              "браузер туди не доходить; ДРУГИЙ (віддача кешованої відповіді) гейта формату не має " \
              "взагалі — його тримає лише те, що браузерна форма цього заголовка не шле",
        back: "браузерна гілка почне слати Idempotency-Key, або зникне `request.format.json?`-гейт"
      },
      "app/controllers/api/v1/codex/comments_controller.rb#create" => {
        why:  "підвид (в), єдиний такий: гілка ДОСЯЖНА (пробіли проходять HTML5 required), просто " \
              "Turbo на JSON не робить нічого — симптом тиша, не блоб. Тобто тут відкладено не через " \
              "недосяжність, а через мʼякший симптом; найгостріший кандидат на повернення в реєстрі",
        back: "будь-яка робота над цією формою — рядок мусить бути знятий разом із нею, бо гілка вже жива"
      },
      "app/controllers/api/v1/codex/fractions_controller.rb#create" => {
        why:  "підвид (г), єдиний такий: UI-джерело Є (`Codex::Fractions::Picker` постить просто на " \
              "`codex_fractions_path`), і сервіс УЖЕ віддає сюди помилку — `invalid(\"node is not " \
              "pickable\")` для destroyed/extinct. Гілку закриває скоуп у СУСІДНЬОМУ екшені: `#picker` " \
              "фільтрує `where.not(lifecycle_status: destroyed/extinct)`, тож такий вузол просто не " \
              "показується. Отже реальний залишок — ГОНКА: вузол помирає між рендером пікера й сабмітом",
        back: "`#picker` перестане фільтрувати `lifecycle_status`, або зʼявиться другий шлях сабміту повз нього"
      },
      "app/controllers/api/v1/oracle_visions_controller.rb#simulate" => {
        why:  "підвид (б), єдиний такий: UI-джерело ІСНУЄ і рендериться адмінам " \
              "(`OracleVisions::SimulationPanel` з `oracle_visions/index`), а недосяжність тримається " \
              "виключно на `SimulationWorker`, якого немає в дереві — клік дає NameError→500 ще ДО " \
              "цього рядка. Голий сайт стоїть на шляху УСПІХУ, тож щойно воркер зʼявиться, адмін " \
              "дістане сирий блоб у Turbo Frame. Дім присуду «будувати чи зняти» — UI.7",
        back: "поява `SimulationWorker` — раніше за будь-яке рішення про UI"
      }
    }.freeze

    # ─── CSRF: машинні входи [SEC.30] ───────────────────────────────────────
    # `unguarded` = ТОЧНИЙ перелік дій, з яких CSRF-гард знято: `:all` — весь
    # контролер, масив — саме ці дії й ЖОДНОЇ іншої. Це твердження, яке гейт
    # міряє поведінкою, а не мітка.
    #
    # 🔴 Чому перелік, а не `:partial` [SEC.31]. Перша редакція цієї перевірки
    # питала «чи зняття скоуплене» — і не питала, ЩО саме скоуплено. Виміряно:
    # `only: :refresh` (повна інверсія — машинну дію закрито, cookie-дію відкрито),
    # `except: :create` і `only: [:create, :refresh]` дають рівно той самий вердикт
    # «скоуплене», тобто проходили б зеленим. Твердження «зняття мусить лишатись
    # `only: :create`» стояло тут словами й не пінилось нічим.
    #
    # 🔴 `why` зʼявився тому, що гейт просив підставу, якої структура не вміла
    # прийняти: повідомлення про помилку казало «додай із підставою», а значенням
    # був голий символ. Тобто три записи CSRF-половини жили поза конвенцією, яку
    # весь цей файл декларує, — і жоден ліхтар цього не бачив, бо `ALL` зібрано з
    # чотирьох ІНШИХ мап, а ця в нього не входить.
    MACHINE_ENTRIES = {
      "Api::V1::OracleCallbacksController" => {
        unguarded: :all,
        why: "Chainlink DON, HMAC-SHA256 у тілі; браузерного шляху не існує за визначенням, " \
             "тож ambient authority тут не буває — cookie в цьому контурі не ходить"
      },
      "Api::V1::HeliumSosController" => {
        unguarded: :all,
        why: "Helium Console webhook, HMAC-SHA256; клієнт — чужий оркестратор, не браузер"
      },
      "Api::V1::M2mAuthController" => {
        unguarded: %w[create],
        why: "машинний лише `create` (Ed25519-підпис у тілі); `refresh` іде через звичайний " \
             "`authenticate_user!`, тобто приймає cookie-сесію — саме тому звільнена мусить бути " \
             "РІВНО `create`: і розширення на весь контролер, і зсув зняття на `refresh` " \
             "відкривають браузерну дію"
      }
    }.freeze

    ALL = [ MACHINE, HELPERS, BY_DESIGN, LATENT ].reduce(:merge).freeze
end
