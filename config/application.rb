# SPDX-License-Identifier: AGPL-3.0-or-later
require_relative "boot"

# ⚠️ ПОРЯДОК НЕСУЧИЙ, не алфавіт. `active_storage/engine` у тілі класу згадує
# `ImageAnalyzer::Vips` → autoload → ruby-vips → glib. Якщо glib заходить ПЕРШОЮ,
# нативний argon2id ламається на arm64-darwin: `__stack_chk_fail` у `initial_hash`,
# SIGABRT (134) на ~50 хешах. Зворотний порядок чистий, тож argon2id вантажимо
# ПЕРЕД будь-яким railtie. Мінімальний репро (без Rails):
#   ruby -e 'require "ruby-vips"; require "argon2id"; 50.times { Argon2id::Password.create("p") }'  → 134
#   ruby -e 'require "argon2id"; require "ruby-vips"; …'                                            → 0
# Linux (CI/Docker) не відтворює — тримаємо рядок для локальної сюїти на macOS.
require "argon2id"

# [ARCH.79] Railtie перелічені ЯВНО замість `rails/all` — той тягне десять, і три
# з них ніхто не вмикав рішенням: вони приходять пакетом і мовчки публікують
# поверхню. Порядок збережено від `rails/all`, бо він і є той несучий порядок ↑.
#   ⊘ `action_mailbox/engine`   — 14 ingress-маршрутів (Postmark/SendGrid/Mandrill/
#     Mailgun/Relay + `rails/conductor`) плюс модель `InboundEmail`, що пише блоб у
#     НАШЕ сховище на кожен вхідний лист, — при повній відсутності `app/mailboxes/`.
#   ⊘ `action_text/engine`      — нуль `has_rich_text` у дереві.
#   ⊘ `rails/test_unit/railtie` — сюїта на RSpec.
# ⚠️ Тут НЕМА `rescue LoadError`, яким `rails/all` глушить кожен require: відсутній
# railtie мусить впасти голосно, інакше зникнення engine'а читалось би як норма.
require "rails"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "action_cable/engine"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SilkenNet
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets daemons tasks])

    # [KENOSIS TITAN]: structure.sql зберігає партиціювання PostgreSQL (schema.rb не підтримує)
    config.active_record.schema_format = :sql

    # [I18N]: Quadrilingual UI (EN default). Мову запиту резолвить
    # `LocaleSettable` — ланцюг і його стелі живуть ТАМ, не тут. Locale files are
    # organised by domain under config/locales/<group>/<locale>.yml — the
    # nested load_path picks them up automatically. New languages are added
    # by appending to `available_locales` and shipping a matching YAML set.
    #
    # ⚠️ [I18N.3] Тут доти стояло «UA/LV/LT auto-detected via Accept-Language
    # header» — і це було САМОСВІДЧЕННЯ: щабель `Accept-Language` не працював
    # жодного разу, бо викликав неіснуючий метод. Конфіг-файл заявляв
    # спроможність, якої в застосунку не було, тобто найгучніший носій брехні
    # стояв найдалі від коду, що її спростовує. Рядок тепер РОУТИТЬ у концерн
    # замість переказувати його — дзеркало не може розійтись із тим, чого не
    # дублює.
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
    config.i18n.available_locales = %i[uk en lv lt]
    config.i18n.default_locale    = :en
    # Локаль-НЕЗАЛЕЖНИЙ ланцюг: `true` → railtie будує `Fallbacks.new(default_locale)`,
    # тобто хвіст `[:en]` для БУДЬ-ЯКОЇ локалі — і наявної, і майбутньої, і
    # регіональної (`pt-BR` → `[:pt-BR, :pt, :en]` через parent-ланцюг). Поіменний
    # хеш, що стояв тут раніше, був єдиною формою з ПОРОЖНІМ `defaults`: нова
    # локаль не діставала `:en` взагалі, а `production.rb` це мовчки перекривав
    # своїм `= true` — тобто dev/test і прод розходились. Дім пояснення — `04_04 §12.2`.
    config.i18n.fallbacks         = true

    # [GAIA SHIELD]: Rack::Attack — DDoS / brute-force / bot-scanner protection.
    # Inserted early in the middleware stack so malicious traffic is dropped
    # before it reaches ActionDispatch, Warden or ActiveRecord.
    config.middleware.use Rack::Attack

    # [OBSERVABILITY]: Prometheus /metrics endpoint — secured by IP allowlist
    # and optional HTTP Basic Auth. Inserted early so it short-circuits before
    # routing, session handling, or CSRF protection.
    require_relative "../app/middleware/prometheus_collector"
    config.middleware.use PrometheusCollector

    # Phlex components & layouts: autoload app/views/components and
    # app/views/layouts so Wallets::TransactionRow, DashboardLayout, etc.
    # are resolvable by Zeitwerk without the Views:: wrapper.
    #
    # [ARCH.93] Обидва шляхи мусять стояти і в eager_load_paths, і це НЕ
    # надлишковість: `autoload_paths` не входить в `eager_load_paths`
    # автоматично — Rails виключає `app/views` з дефолтного `app/*` за
    # побудовою (там історично шаблони, не Ruby-класи). Виміряно рантаймом
    # ДО фіксу: `eager_load!` давав 16 нащадків `ApplicationComponent` при 112
    # файлах на диску, тобто 96 класів (94 компоненти + 2 лейаути) народжувались
    # під час ЗАПИТУ. У проді це знімає рівно те, заради чого `eager_load = true`
    # існує: `NameError`, синтаксис і циклічний реф ловились першим відвідувачем
    # сторінки, а не деплоєм. `app/views/shared` тут не потрібен — він
    # резолвиться через `Views::`-неймспейс і вже в переліку (ті самі 16).
    %w[app/views/components app/views/layouts].each do |phlex_path|
      config.autoload_paths   << root.join(phlex_path).to_s
      config.eager_load_paths << root.join(phlex_path).to_s
    end

    # [SEC.27] Друга лінія під модельними валідаціями вкладень: жодне наше
    # вкладення не приймає bmp/psd/ico (allow-list усіх трьох — jpeg/png/webp),
    # але Rails-дефолт лишає ці формати variant-придатними, тобто тримає шлях
    # у декодер, якого ми не потребуємо. Після звуження вже залитий блоб такого
    # типу деградує до `representable? == false` замість `Vips::Error` у рендері.
    # heic/heif лишаються свідомо — `MaintenanceRecord#photos` їх приймає і
    # рендерить `variant(:thumb)`, тобто це живий тракт польових фото.
    config.active_storage.variable_content_types =
      ActiveStorage::Engine.config.active_storage.variable_content_types -
      %w[image/bmp image/vnd.adobe.photoshop image/vnd.microsoft.icon]

    # Use RSpec and FactoryBot for generators
    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end

    # Prepend a custom PostgreSQL bin path to PATH if configured via POSTGRES_BIN_PATH.
    # Useful when multiple PG versions are installed and the server version differs from
    # the default pg_dump/psql binaries in PATH (e.g. PG17 server, PG16 client in PATH).
    # Set POSTGRES_BIN_PATH in .env or .env.development.local (gitignored).
    if (pg_bin = ENV["POSTGRES_BIN_PATH"]).present? && !ENV["PATH"].to_s.include?(pg_bin)
      ENV["PATH"] = "#{pg_bin}:#{ENV["PATH"]}"
    end

    # Lookbook component previews path.
    # ⚠️ Цей реєстр відповідає лише за ЗНАХОДЖЕННЯ класів превʼю. Шаблони
    # (`render_with_template`) резолвляться через VIEW-шляхи — окремий дім, і його
    # дротує `config/initializers/lookbook_preview_view_path.rb`; без нього
    # 11 із 59 сценаріїв віддавали 500 при повній навігації [UI.3].
    if defined?(Lookbook)
      preview_root = root.join("spec/components/previews").to_s
      config.lookbook.preview_paths = [ preview_root ]
    end
  end
end
