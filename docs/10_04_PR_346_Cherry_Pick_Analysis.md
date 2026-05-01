# 10_04 — Аналіз PR #346 (`fix/setup-db-and-dot-env`)

> **Статус:** Аналіз завершено. Перенесено лише валідні правки + застосовано
> кращі рішення там, де PR-патч лише обходив проблему.
>
> **Витяг:** PR #346 містить ~18 файлів змін. Близько половини — обхідні шляхи
> навколо проблем, які вже коректно вирішені у `main` (через `AuthLayout`,
> `render_dashboard(content:)`, `render_auth_page`). Решта — реальні bug-fixes,
> що відображають дрейф моделей/гемів за час життя бранчу. Цей PR забирає
> справжні fixes і пропонує **кращі архітектурні рішення** замість трьох
> обхідних шляхів PR.

---

## 1. ВЗЯТО з PR #346 (валідні фікси)

### 1.1 `Gemfile` + `Gemfile.lock` — `dotenv-rails` + `arm64-darwin-25`

| Зміна | Обґрунтування |
|---|---|
| `gem "dotenv-rails"` (group `:development`) | До цього у репо було `dotenv` (3.2.0) як транзитивна залежність, але Rails-інтеграція (`Dotenv::Rails`) — окремий гем. Без нього `.env` файл у корені проєкту **НЕ** автоматично завантажується перед `Rails.application.initialize!`, і ENV-змінні з нього недоступні в `config/database.yml`, `config/puma.rb`, ініціалізаторах. Це і є причина зміни (1.2). У production контейнерах ENV вже встановлені оркестратором (Kamal/Akash), тому `dotenv-rails` потрібен **тільки** в `:development`. |
| Платформа `arm64-darwin-25` у `Gemfile.lock` | Підтримка дев-машин на macOS Tahoe / Xcode 26 (arm64-darwin-25). Без неї `bundle install` на новому Mac відмовляється встановлювати native-розширення. |

### 1.2 `config/database.yml` — ENV-driven development

| Було | Стало |
|---|---|
| `username: postgres` (hardcoded) | `username: <%= ENV.fetch("POSTGRES_USER", "postgres") %>` |
| `password: password` | `password: <%= ENV.fetch("POSTGRES_PASSWORD", "password") %>` |
| `host: localhost` | `host: <%= ENV.fetch("POSTGRES_HOST", "localhost") %>` |

**Чому:** на macOS Homebrew за замовчуванням створює PostgreSQL-роль із іменем
`$USER`, не `postgres`. Старий конфіг змушував кожного розробника або змінювати
файл (потім ігнорувати в git), або вручну створювати роль. ENV-fetch з sensible
defaults — стандартний Rails-патерн (Heroku, fly.io, Kamal, dev-containers).
У `test:` ENV вже використовувався — приведено в гармонію.

### 1.3 `config/puma.rb` — `workers=0` за замовчуванням у development

```ruby
default_workers = ENV.fetch("RAILS_ENV", "development") == "development" ? 0 : 2
workers ENV.fetch("WEB_CONCURRENCY", default_workers)
```

**Чому це bug-fix, а не нова поведінка:** коментар у блоці `cluster do … end`
(вже у `main`) явно стверджує:
> *"these hooks NEVER run in single mode (`workers 0`, our default in
> `RAILS_ENV=development`)"*

Але реалізація `workers ENV.fetch("WEB_CONCURRENCY", 2)` дефолтила у **2**,
а не **0**. Документована поведінка не відповідала реальності. PR виправляє
розбіжність. У development single-mode дозволяє binding.irb / `debug` працювати
без master-worker fork-танцю.

### 1.4 `firmwares_controller.rb` + Phlex компоненти — рейміни атрибутів моделі

Атрибути `BioContractFirmware`:
| Старе ім'я (зник у моделі) | Нове ім'я (у `db/structure.sql:345-346`) |
|---|---|
| `target_hardware` | `target_hardware_type` |
| `checksum` | `binary_sha256` |
| `file_size` | (немає такої колонки) |

Вплив: 3 файли (`firmwares_controller.rb` JSON `as_json` whitelist,
`firmwares/index.rb`, `firmwares/row.rb`) рендерили nil → `N/A` для
`checksum`, або взагалі генерували 500 на JSON. PR приводить у відповідність.
Прибрано також `file_size` із `as_json` only-list (колонки не існує).

### 1.5 `oracle_visions/forecast_card.rb` — рейміни `AiInsight`

Модель `AiInsight` (db/structure.sql:235+):
| Старе | Нове |
|---|---|
| `confidence_score` | `probability_score` |
| `payload["description"]` | `summary` (text column) |
| `payload["yield_impact"]` | `prediction_data&.dig("yield_impact")` (jsonb) |

Старий код рендерив `nil%` і ламав HTML. Рейміни узгоджені зі схемою БД та
валідаціями в `AiInsight` (`validates :probability_score, ...`).

### 1.6 `settings/show.rb` — nil-safety на `value`

```ruby
input(value: value&.to_s, ...)  # було: value: value
```

Захищає `<input>` від `value=` attr із Integer / Float / nil типами,
коли `Organization#alert_threshold_critical_z` (numeric) рендериться у формі.
Phlex може серіалізувати numeric, але `&.to_s` робить намір явним і
запобігає `NoMethodError`, якщо колонка nullable.

### 1.7 `app/views/shared/ui/pagination.rb` — `pagy.prev` → `pagy.previous`

Pagy ≥ 9 (у проекті 43.5.3) видалив `.prev` на користь `.previous`.
Було вже видно як дим: `app/services/tree_chronicle_service.rb:45` додає
local-polyfill через `define_singleton_method(:prev)`. Без виправлення Pagination
кидає `NoMethodError` для будь-якого контролера, який не використовує
`TreeChronicleService`. Старий polyfill у `tree_chronicle_service.rb` залишено
як defensive-код (нікому не шкодить).

---

## 2. ПОКРАЩЕННЯ (на запит ревью — кращі рішення замість PR-патчів)

### 2.1 Polymorphic `display_identifier` замість `&.try(:did) || &.try(:uid)` ⭐

**Проблема, яку вирішував PR:** `MaintenanceRecord#maintainable` —
поліморфний (`Tree` має `did`, `Gateway` має `uid`). Оригінальний код у
3 місцях писав `record.maintainable&.did || record.maintainable&.uid`. На
`Gateway` цей вираз кидає `NoMethodError`, бо `Gateway` НЕ має методу `did`
(`&.` короткозамикає на `nil`, а не на missing-method).

**Патч PR (нав'язлива оборона):**
```ruby
record.maintainable&.try(:did) || record.maintainable&.try(:uid) || '—'
```
Дублюється у 3 callsites; залишається крихким для нових `maintainable_type`.

**Краще рішення (взято тут):** додано полі-морфний метод на обох моделях:
```ruby
# Tree
alias_attribute :display_identifier, :did

# Gateway
alias_attribute :display_identifier, :uid
```

Тепер усі 3 callsites — `record.maintainable&.display_identifier || '—'`.
Будь-який новий `maintainable_type` (наприклад, `Actuator`) лише визначає
`display_identifier` і автоматично підтримується.

**Зачеплено:**
- `app/models/tree.rb`
- `app/models/gateway.rb`
- `app/views/components/maintenance/index.rb`
- `app/views/components/maintenance/show.rb` (PR не торкав — тут також було баговано)
- `app/blueprints/maintenance_record_blueprint.rb` (PR не торкав — тут було несиметрично з `&.try(:did) || &.uid`)

### 2.2 `before_action :ensure_organization!` + Phlex `Errors::NoOrganization` замість `render html: ...html_safe, layout: false` ⭐

**Проблема, яку вирішував PR:** `DashboardController#index` крашився, якщо
`current_user.organization` було `nil` (системні боти, нові акаунти без onboarding).

**Патч PR (анти-патерн для цього кодбейсу):**
```ruby
unless org
  format.html do
    render html: "<p style='font-family:monospace;...'>No organization assigned...</p>".html_safe,
           layout: false
  end
end
```

Чому це поганий патерн саме у цьому проєкті:
1. **Inline HTML + `html_safe` у контролері** прямо порушує `docs/04_04`:
   *"Ruby-first, utility-CSS: всі в'юшки — це Phlex Ruby-класи, без `.erb`
   шаблонів для доменної логіки"*.
2. **`layout: false`** прибирає `<html><head>`, CSP-meta, CSRF-meta, Tailwind CSS
   та importmap. Користувач бачить нестилізований фрагмент без OAuth-state,
   без можливості log out.
3. **Не повторно використовується**: ~18 контролерів API v1 також читають
   `current_user.organization`. Той самий nil-ризик у кожному з них.

**Краще рішення (взято тут):**

1. `BaseController#ensure_organization!` (private) — reusable `before_action`:
   ```ruby
   def ensure_organization!
     return if current_user&.organization
     respond_to do |format|
       format.json { render json: { error: "No organization...", code: "no_organization" }, status: :unprocessable_content }
       format.html { render_auth_page(title: "Access Denied", component: Errors::NoOrganization.new, status: :unprocessable_content) }
     end
   end
   ```

2. `DashboardController#index` опт-ін через
   `before_action :ensure_organization!, only: :index`. Інші 17 контролерів
   можуть бути додані пізніше тим самим однорядковим хуком.

3. `Errors::NoOrganization` — Phlex-компонент, що відповідає auth-стилю
   (Sessions::New / Passwords::Forgot patterns: emerald palette, цифрова
   diamond-логотип, focus-visible ring, `text-tiny`/`text-compact` custom
   scale). Семантичний токен `border-status-danger-accent` /
   `bg-status-danger-accent` для LED denied-стану (`docs/04_04 §3.2`).

4. Рендериться через існуючий `render_auth_page` → `AuthLayout` (full HTML
   з CSP/CSRF/Tailwind/importmap), машинно-читабельний JSON-код помилки
   `"no_organization"` для клієнтів API.

5. Спека за `docs/10_01` (12 examples: rendering / accessibility /
   design system compliance), узгоджено з conventions для Phlex view specs.

### 2.3 RSpec-специ оновлено під рейміни (1.4-1.7)

Оновлені моки/expectations у спеках:
- `firmwares/row_spec.rb` — `target_hardware_type`, `binary_sha256`
- `oracle_visions/forecast_card_spec.rb` — `probability_score`, `summary`, `prediction_data`
- `oracle_visions/index_spec.rb` — `probability_score`, `summary`, `prediction_data`
- `maintenance/index_spec.rb` — мок використовує `display_identifier`
- `shared/ui/pagination_spec.rb` — `OpenStruct(previous: ...)` замість `prev:`

PR #346 цього не зробив — специ у тому бранчі впали б на CI.

---

## 3. ВІДКИНУТО з PR #346 (вже виправлено інакше у `main`)

### 3.1 BaseController обхід рендерингу — НЕ беремо

PR додавав:
```ruby
include ActionView::Rendering
include ActionController::ContentSecurityPolicy
include ActionController::RequestForgeryProtection
helper Importmap::ImportmapTagsHelper
helper Turbo::StreamsHelper
protect_from_forgery with: :exception, if: -> { request.format.html? }

def render_to_body(options = {})
  if options.key?(:json)
    # ... ручний JSON serialization, бо ActionView::Rendering ламає json:
  else
    super
  end
end
```

Це обхід проблеми "як рендерити Phlex з `ActionController::API`". Але `main`
вже коректно це робить через `Phlex::Rails` API:

- `BaseController#render_dashboard(title:, component:)` рендерить
  `DashboardLayout.new(... content: component)` напряму через Phlex.
- `BaseController#render_auth_page(title:, component:)` рендерить
  `AuthLayout.new(content: component)`.

Включення `ActionView::Rendering` у `ActionController::API` ламає `render json:`
(саме тому PR і змушений був додавати `render_to_body` hack). Цей шлях
архітектурно гірший — відмовляємось.

### 3.2 `DashboardLayout` `@content`-rewrite — вже у `main`

PR замінює `def view_template(&block) ... yield ... end` на
`def view_template ... render @content if @content`. **Цю саму зміну вже
зроблено у `main`** (бачимо у `app/views/layouts/dashboard_layout.rb:42`),
тому патч PR є no-op.

### 3.3 HTML-обгортки в `sessions/new`, `passwords/forgot`, `passwords/reset` — НЕ беремо

PR інлайнить `<html><head><body>` всередину кожної auth-сторінки:
```ruby
def view_template
  doctype
  html(lang: "en") do
    head do ... end
    body do
      main(...) { ... }
    end
  end
end
```

Це повторює один і той самий boilerplate у 3 файлах. На `main` цю проблему
вже вирішено через `AuthLayout` (`app/views/layouts/auth_layout.rb`), який
обертає auth-компоненти. Дублювання шкідливе — пропускаємо.

### 3.4 `ApplicationComponent` додаткові view-helpers — НЕ беремо

PR додавав:
```ruby
include Phlex::Rails::Helpers::CSPMetaTag
include Phlex::Rails::Helpers::CSRFMetaTags
include Phlex::Rails::Helpers::StyleSheetLinkTag
include Phlex::Rails::Helpers::JavaScriptImportmapTags
```

Проблема: `ApplicationComponent` — базовий клас для **всіх** компонентів,
включно з тими, що рендеряться у `Turbo::StreamsChannel.broadcast_render_to`
(broadcasting), де **немає Rails view context**. Виклики `csp_meta_tag` /
`stylesheet_link_tag` упадуть з `nil:NilClass`. Ці helpers потрібні лише в
*layouts* (`AuthLayout`, `DashboardLayout`) — там вони і знаходяться.

---

## 4. Підсумок

| Категорія | Файлів | Дія |
|---|---|---|
| Валідні bug-fixes (рейміни моделей, gem, ENV, pagy, puma) | 11 | ✅ Взято дослівно або з невеликою корекцією |
| Кращі архітектурні рішення замість PR-обхідних патчів | 5 + 3 нові | ⭐ Замінено |
| Обхідні рішення, які `main` вже виправив правильно | 4 | ❌ Відкинуто |

Усього: 14 модифікованих + 3 нових файли (Phlex-компонент, спека, цей doc).

### Файли результату
**Models:** `app/models/tree.rb`, `app/models/gateway.rb` (додано
`alias_attribute :display_identifier`)

**Controllers:** `app/controllers/api/v1/base_controller.rb`
(`ensure_organization!`), `app/controllers/api/v1/dashboard_controller.rb`
(before_action), `app/controllers/api/v1/firmwares_controller.rb` (рейміни)

**Views (Phlex):** `app/views/components/firmwares/{index,row}.rb`,
`app/views/components/oracle_visions/forecast_card.rb`,
`app/views/components/maintenance/{index,show}.rb`,
`app/views/components/settings/show.rb`,
`app/views/shared/ui/pagination.rb`,
**+ новий** `app/views/components/errors/no_organization.rb`

**Serializers:** `app/blueprints/maintenance_record_blueprint.rb`

**Config:** `config/database.yml`, `config/puma.rb`, `Gemfile`, `Gemfile.lock`

**Specs (оновлено + новий):** `spec/views/components/firmwares/row_spec.rb`,
`spec/views/components/oracle_visions/{forecast_card,index}_spec.rb`,
`spec/views/components/maintenance/index_spec.rb`,
`spec/views/shared/ui/pagination_spec.rb`,
**+ новий** `spec/views/components/errors/no_organization_spec.rb` (12 examples)

**Docs:** цей файл (`docs/10_04_PR_346_Cherry_Pick_Analysis.md`).
