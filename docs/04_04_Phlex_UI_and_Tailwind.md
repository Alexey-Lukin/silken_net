# 04_04: Phlex UI & Tailwind (SSOT Дизайн-Системи)

## 🎯 Мета

Зафіксувати повну специфікацію дизайн-системи SilkenNet як Єдине Джерело Істини (SSOT). Документ описує **Phlex-компоненти**, **Tailwind CSS токени**, **Stimulus-контролери**, **Turbo-інтеграцію** та правила доступності. Слугує єдиним авторитетним джерелом для всіх UI-рішень в межах Rails 8.1 моноліту.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — рушій (Phlex + `@theme`-токени + `tokens()`) production-grade; **дизайн-система ≠ повністю мігрована**: shared-компоненти чисті, але raw-Tailwind у прикладних компонентах лишається (токен-міграція UI.1-3), а `gaia:lint_tokens` — rake-таск **без CI-гейта** (тож правило не enforced, лише документоване). Потребує production verification.
- **Стек:** Rails 8.1 · Phlex · Tailwind CSS 4 · TailwindMerge · Stimulus · Turbo 8
- **Відкрите:** production verification (UI на живому деплої) — [`06_01 §DEPLOY-DAY`](06_01_Deployment_Kamal_Terraform); UI-беклог (токен-міграція / a11y / i18n) → [`00_07`](00_07_Action_Plan_Tracker) UI.1/UI.2/UI.3, I18N.1.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | Моделі (дані для компонентів) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (сервіси) |
| [`04_03` — REST API v1 Reference](04_03_REST_API_v1_Reference) | REST API (Turbo Frame ендпоінти) |
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Прошивка (OTA progress streams) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (UI.1/UI.2/UI.3, I18N.1) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Огляд Архітектури](#1-огляд-архітектури)
- [2. ApplicationComponent — Базовий Клас](#2-applicationcomponent--базовий-клас)
- [3. Tailwind Дизайн-Токени](#3-tailwind-дизайн-токени)
- [4. Шкала Типографіки](#4-шкала-типографіки)
- [5. TailwindMerge та патерн `tokens](#5-tailwindmerge-та-патерн-tokens)
- [6. Реєстр Компонентів](#6-реєстр-компонентів)
- [7. Stimulus Контролери](#7-stimulus-контролери)
- [8. Інтеграція Turbo (Streams & Frames)](#8-інтеграція-turbo-streams--frames)
- [9. Чекліст Доступності](#9-чекліст-доступності)
- [10. Lookbook (Дослідник Компонентів)](#10-lookbook-дослідник-компонентів)
- [Додаткові Матеріали](#додаткові-матеріали)
- [11. Міграція з ActionController::API на ActionController::Base](#11-міграція-з-actioncontrollerapi-на-actioncontrollerbase)
- [12. Інтернаціоналізація та Локалізація (i18n)](#12-інтернаціоналізація-та-локалізація-i18n)
- [13. Mobile Drawer (Phase 2)](#13-mobile-drawer-phase-2)
- [14. Animations & Motion (Phase 3)](#14-animations--motion-phase-3)
- [15. Native HTML over Stimulus (де доречно)](#15-native-html-over-stimulus-де-доречно)
- [16. Codemod-Driven Migration (Phase 4)](#16-codemod-driven-migration-phase-4)
- [17. Responsive Tables — CSS-only Card Flip (Phase 5)](#17-responsive-tables--css-only-card-flip-phase-5)
- [18. Industry Standards (SSOT) + Per-PR Definition of Done](#18-industry-standards-ssot--per-pr-definition-of-done)
<!-- TOC:AUTO:END -->

---

## 1. Огляд Архітектури

SilkenNet використовує підхід **Ruby-first, utility-CSS**: всі в'юшки — це Phlex Ruby-класи (без `.erb` шаблонів для доменної логіки), стилізовані виключно Tailwind utility-класами, об'єднаними без конфліктів через TailwindMerge.

Дизайн-система побудована за принципом **dark-first** — термінальна/кіберпанк естетика з emerald-акцентами (`#10b981`) на чорному фоні (`#000000`). Світлий режим — вторинний, висококонтрастний варіант, що активується перемиканням класу `.dark` на `<html>`.

### Ієрархія Компонентів

```
ApplicationComponent (Phlex::HTML)
│   Включає: Routes, TurboStreamFrom, TurboFrameTag, FormWith,
│            ButtonTo, AssetPath, FormAuthenticityToken
│   Визначає: tokens(), TailwindMerge::Merger, CUSTOM_TEXT_SCALE
│
├── app/views/layouts/          # Layout-обгортки (include Phlex::Rails::Layout)
│   ├── DashboardLayout         ← Основний layout (sidebar + top bar + breadcrumbs)
│   │                             Приймає content: параметр з domain component
│   └── AuthLayout              ← Легкий layout для login/password (без sidebar)
│
├── app/views/shared/           # Reusable примітиви (рівень фреймворку)
│   ├── ui/                     # Загальні UI-елементи
│   │   ├── StatusBadge         ← AASM стан → семантичний колір
│   │   ├── StatCard            ← Картка метрики дашборду
│   │   ├── DataTable           ← Таблиця з налаштовуваними стовпцями
│   │   ├── Pagination          ← Pagy-навігація prev/next
│   │   ├── EmptyState          ← Плейсхолдер (grid або table-row режим)
│   │   ├── MetaRow             ← Рядок відображення ключ-значення
│   │   ├── ActionBadge         ← Бейдж типу дії аудиту
│   │   ├── PhotoCard           ← Фото ActiveStorage з hover-оверлеєм
│   │   ├── RelativeTime        ← "5 хвилин тому" з підказкою
│   │   ├── Skeleton            ← Скелетон завантаження (6 варіантів)
│   │   └── ThemeSwitcher       ← Перемикач темної/світлої теми
│   ├── iot/
│   │   └── MetricValue         ← Числове значення сенсора з точністю та одиницею
│   └── web3/
│       └── Address             ← Ethereum-адреса з обрізанням + копіюванням
│
└── app/views/components/       # Доменні компоненти рівня сторінки
    ├── navigation/Sidebar
    ├── dashboard/Home, Map, MapNode, EventRow
    ├── trees/Index, Show, Chronicle
    ├── wallets/Index, Show, BalanceDisplay, BalanceFrame, MetadataFrame, TransactionRow
    ├── alerts/Index, Row, Badge
    ├── telemetry/LiveStream, LogEntry
    ├── oracle_visions/Index, ForecastCard, SimulationPanel
    ├── clusters/Grid, Item, Show
    ├── gateways/Index, Item, Show
    ├── actuators/Index, Show, Card, CommandRow, CommandStatusBadge
    ├── firmwares/Index, New, Form, Row, OtaProgressBar
    ├── maintenance/Index, Show, Form, PhotoGallery, PhotosPage
    ├── contracts/Index, Show
    ├── blockchain_transactions/Index, Show, OnChainFrame
    ├── reports/Index, CarbonAbsorption, FinancialSummary
    ├── tree_families/Index, Show, Form
    ├── organizations/Index, Show
    ├── users/Index, Profile
    ├── audit_logs/Index, Show
    ├── system_audits/Index
    ├── system_health/Show
    ├── provisioning/New, Success
    ├── account_security/Show
    ├── notifications/Settings
    ├── settings/Show
    ├── sessions/New
    └── passwords/Forgot, Reset
```

### Потік Рендерингу

```
HTTP Request (Dashboard pages)
    └─► Controller (тонкий — попередньо завантажує всі дані, без бізнес-логіки)
            └─► render_dashboard(title:, component:)
                    └─► render DashboardLayout.new(content: component)
                            └─► DashboardLayout.view_template
                                    ├─► render Navigation::Sidebar.new(...)
                                    └─► render @content  ← Domain Component
                                            ├─► render Views::Shared::UI::StatusBadge.new(...)
                                            ├─► render Views::Shared::UI::DataTable.new(...) { rows }
                                            └─► turbo_stream_from / turbo_frame_tag (lazy)

HTTP Request (Auth pages — login, forgot/reset password, no-organization quarantine)
    └─► Controller
            └─► render_auth_page(title:, component:, status: :ok)
                    └─► render AuthLayout.new(title:, content: component)
                            └─► AuthLayout.view_template
                                    └─► render @content  ← Auth Component (Sessions::New, Errors::NoOrganization, etc.)
```

> **⚠️ Важливо:** Content component передається як параметр `content:` — **НЕ через блок**.
> Ruby closure блоку виконується в контексті контролера, тому `render` всередині блоку
> викликає `ActionController::Base#render` (DoubleRenderError), а не `Phlex::HTML#render`.

### Layout Компоненти

| Layout | Файл | Включає | Призначення |
|---|---|---|---|
| `DashboardLayout` | `app/views/layouts/dashboard_layout.rb` | `Phlex::Rails::Layout` | Основний layout з sidebar, top bar, breadcrumbs |
| `AuthLayout` | `app/views/layouts/auth_layout.rb` | `Phlex::Rails::Layout` | Легкий layout для login/password сторінок |

Обидва layout-компоненти включають `Phlex::Rails::Layout`, який автоматично додає необхідні
Rails view helpers: `csp_meta_tag`, `csrf_meta_tags`, `stylesheet_link_tag`, `javascript_importmap_tags`.

---

## 2. ApplicationComponent — Базовий Клас

**Файл:** `app/views/components/application_component.rb`

```ruby
class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::TurboStreamFrom
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::AssetPath
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include ActionView::RecordIdentifier  # dom_id / dom_class helpers для Turbo цілей

  delegate :time_ago_in_words, :number_to_human_size,
           to: :"ActionController::Base.helpers"

  CUSTOM_TEXT_SCALE = %w[micro mini tiny compact display-sm display-md display-lg].freeze

  def tokens(*args, **conditions)
    result = args.compact.join(" ")
    conditional = conditions.filter_map { |cls, flag| cls.to_s if flag }.join(" ")
    combined = [ result, conditional ].reject(&:empty?).join(" ")
    self.class.merger.merge(combined)
  end

  def self.merger
    @merger ||= TailwindMerge::Merger.new(config: {
      theme: { "text" => CUSTOM_TEXT_SCALE }
    })
  end
end
```

### Ключові Дизайн-Рішення

| Рішення | Обґрунтування |
|---|---|
| `delegate :time_ago_in_words` до `ActionController::Base.helpers` | Контексти Turbo-broadcast не мають Rails view context; це забезпечує роботу хелперів у background workers |
| Реєстрація `CUSTOM_TEXT_SCALE` | Запобігає TailwindMerge трактувати `text-tiny` (font-size) і `text-status-warning-text` (color) як конфліктуючі класи |
| Без DB-запитів у `initialize` | Всі дані передаються як аргументи конструктора; компоненти — чисті функції рендерингу |

#### Sync `@theme` ↔ Ruby Token Constants [DOC.5]

> **Lint-rule (manual review checklist):** при будь-якій зміні `@theme` блоку в `app/assets/tailwind/application.css` обов'язково оновити **три точки** одночасно. Інакше TailwindMerge не "побачить" нові семантичні групи і дозволить silent class collision (наприклад, `text-mega text-status-danger-text` обидва пройдуть, хоча `text-mega` — нова шкала шрифту, а `text-status-danger-text` — колір; їх **не повинно** ставити в одну групу).

| `@theme` запис у `application.css` | Ruby-константа в `application_component.rb` | Що оновити |
|------------------------------------|---------------------------------------------|------------|
| `--font-size-<name>` (новий розмір типографіки) | `CUSTOM_TEXT_SCALE` | додати `<name>` у масив |
| `--color-<group>-<name>` (нова семантична група кольорів — наприклад `--color-token-*`) | (майбутня константа `CUSTOM_COLOR_TOKENS`, якщо буде потрібна окрема група) | реєструвати у `self.merger` config |
| Видалення/перейменування існуючого токена | відповідна константа | синхронно видалити/перейменувати |

**Рекомендований workflow при зміні токенів:**
1. Відредагувати `@theme` блок у `application.css`.
2. Запустити `grep -r "<old_token_name>" app/views/components/ app/views/shared/` — знайти всі використання.
3. Оновити `CUSTOM_TEXT_SCALE` (або відповідну константу) у `application_component.rb`.
4. Запустити RSpec component specs (`bundle exec rspec spec/components/`) — TailwindMerge помилки виявляться як unexpected class collisions у snapshot-тестах.

> **Чому це не автоматизовано:** Tailwind v4 не експортує `@theme` як JSON/Ruby-сумісний формат. Парсинг CSS у Ruby — фрагільний (CSS comments, nested `@layer`, тощо). Простіше тримати **дві точки істини під дисципліною code review** ніж писати/підтримувати парсер. Якщо це стане bottleneck — кандидат на окремий `bin/check-tailwind-tokens` rake task.

---

## 3. Tailwind Дизайн-Токени

**Файл:** `app/assets/tailwind/application.css`

Система токенів відповідає принципу **Tailwind v4 SSOT** — єдине джерело істини:

- **`@theme` блок** в `application.css` реєструє усі семантичні токени (`--color-*`, `--font-size-*`, `--font-family-*`) — Tailwind v4 генерує utility-класи напряму: `bg-gaia-surface`, `text-status-danger-text`, `font-mono` тощо.
- **CSS custom properties** у `:root` / `.dark` задають фактичні значення токенів для light/dark режимів.

> `config/tailwind.config.js` видалено — він порушував SSOT, дублюючи кожен токен на рівні JS.

### 3.1 Поверхневі, Текстові та Основні Токени (`gaia-*`)

> **Phase 1 of the frontend overhaul (Tailwind v4 SSOT).** Палітра розширена
> до 4-tier surface depth scale (Material 3 elevation pattern) і 3-level text
> hierarchy для адекватного контрасту в light/dark. Перемикання теми тепер
> змінює усі поверхні, а не лише текст. Legacy `--gaia-surface-alt` видалено —
> усі call-sites мігровано на `--gaia-surface-sunken`.

#### Surfaces (4-tier depth)

| Токен | Tailwind Клас | Light `#` | Dark `#` | Призначення |
|---|---|---|---|---|
| `--color-gaia-surface-base` | `bg-gaia-surface-base` | `#fafafa` | `#050607` | Page background (під `<body>`) |
| `--color-gaia-surface` | `bg-gaia-surface` | `#ffffff` | `#0b0f0e` | Картки, панелі, форми |
| `--color-gaia-surface-elevated` | `bg-gaia-surface-elevated` | `#ffffff` (+`shadow-lg`) | `#11161a` | Modals, popovers, dropdowns |
| `--color-gaia-surface-sunken` | `bg-gaia-surface-sunken` | `#f3f4f6` | `#070a09` | Table-row alt, code blocks, input bg, table headers |

#### Text (3-level hierarchy)

| Токен | Tailwind Клас | Light `#` | Dark `#` | Призначення |
|---|---|---|---|---|
| `--color-gaia-text-strong` | `text-gaia-text-strong` | `#0f172a` | `#e6fff4` | Headings, primary numbers |
| `--color-gaia-text` | `text-gaia-text` | `#1f2937` | `#a7f3d0` | Body |
| `--color-gaia-text-muted` | `text-gaia-text-muted` | `#52525b` | `#6ee7b7` | Labels, metadata |
| `--color-gaia-text-subtle` | `text-gaia-text-subtle` | `#9ca3af` | `rgba(52,211,153,0.55)` | Placeholders, watermarks, disabled |

#### Primary + borders

| Токен | Tailwind Клас | Light `#` | Dark `#` | Призначення |
|---|---|---|---|---|
| `--color-gaia-primary` | `text-gaia-primary` / `bg-gaia-primary` | `#10b981` | `#10b981` | Бренд-emerald (однаковий) |
| `--color-gaia-primary-hover` | `hover:bg-gaia-primary-hover` | `#059669` | `#34d399` | Hover primary |
| `--color-gaia-primary-soft` | `bg-gaia-primary-soft` | `#d1fae5` | `rgba(16,185,129,0.12)` | Chips, pills, low-emphasis bg, active-nav highlight |
| `--color-gaia-border` | `border-gaia-border` | `#e5e7eb` | `rgba(16,185,129,0.18)` | Default межі |
| `--color-gaia-border-strong` | `border-gaia-border-strong` | `#cbd5e1` | `rgba(16,185,129,0.40)` | Hover-borders, dividers, focus-ring backup |

> **Legacy-кольори `gaia-green`, `gaia-dark`, `gaia-muted` видалені.** Семантичні токени `gaia-primary`, `gaia-text-muted`, `gaia-text` залишаються.

### 3.2 Статусні Токени (`status-*`)

Всі AASM-стани рендеряться виключно через ці токени — ніяких raw Tailwind кольорів.

| Пара Токенів | Light Bg / Text | Dark Bg / Text | AASM Стани |
|---|---|---|---|
| `status-danger` / `status-danger-text` | `#fee2e2` / `#991b1b` | `#7f1d1d` / `#fecaca` | `failed`, `active` (лише EwsAlert — див. примітку), `breached`, `deceased`, `faulty` |
| `status-danger-accent` | `#dc2626` | `#ef4444` | Акцентні значення, LED-індикатори |
| `status-warning` / `status-warning-text` | `#fef3c7` / `#92400e` | `#78350f` / `#fde68a` | `pending`, `issued`, `triggered`, `updating`, `dormant` |
| `status-info` / `status-info-text` | `#dbeafe` / `#1e40af` | `#1e3a5f` / `#bfdbfe` | `sent`, `paid`, `maintenance` |
| `status-success` / `status-success-text` | `#d1fae5` / `#065f46` | `#065f46` / `#d1fae5` | `confirmed`, `fulfilled` |
| `status-active` / `status-active-text` | `#ccfbf1` / `#115e59` | `#064e3b` / `#a7f3d0` | `acknowledged` |
| `status-neutral` / `status-neutral-text` | `#f3f4f6` / `#4b5563` | `#27272a` / `#a1a1aa` | `idle`, `draft`, `expired`, `offline`, `resolved`, `cancelled`, `ignored` (+ `opacity-30 line-through`) |

### 3.3 Кольори Blockchain Токенів (`token-*`)

| Токен | Tailwind Клас | Light | Dark | Призначення |
|---|---|---|---|---|
| `--color-token-carbon` | `text-token-carbon` | `#047857` | `#059669` | SilkenCarbonCoin (SCC) |
| `--color-token-forest` | `text-token-forest` | `#b45309` | `#d97706` | SilkenForestCoin (SFC) |

### 3.4 Токени Форм Введення (`gaia-input-*`)

| Токен | Tailwind Клас | Light | Dark |
|---|---|---|---|
| `--color-gaia-input-bg` | `bg-gaia-input-bg` | `#ffffff` | `#09090b` |
| `--color-gaia-input-border` | `border-gaia-input-border` | `#d1d5db` | `rgba(16,185,129,0.3)` |
| `--color-gaia-input-text` | `text-gaia-input-text` | `#111827` | `#d1fae5` |
| `--color-gaia-label` | `text-gaia-label` | `#6b7280` | `#6b7280` |

### 3.5 Правила Використання Кольорів

| ✅ Правильно | ❌ Заборонено |
|---|---|
| `bg-gaia-surface` | `bg-white` / `bg-black` (у shared-компонентах) |
| `text-gaia-text` | `text-gray-900` / `text-emerald-400` (у shared-компонентах) |
| `border-gaia-border` | `border-gray-200` / `border-emerald-900` (у shared-компонентах) |
| `bg-status-danger text-status-danger-text` | `bg-red-100 text-red-800` |
| `shadow-sm dark:shadow-none` | `shadow-lg` скрізь |

> **Виняток:** Доменні page-компоненти (не shared/ui) можуть використовувати raw Tailwind кольори (наприклад, `border-emerald-900`, `bg-zinc-950`) для кіберпанк-естетики, оскільки вони не переповикористовуються у різних контекстах.

### 3.6 Tailwind v3 → v4 Cheatsheet [DOC.11]

> **Контекст:** Проект використовує **Tailwind CSS v4** (нативно, без PostCSS-плагіна). Якщо ви прийшли з v3-кодової бази (зокрема старого fork'а / зовнішнього прикладу), нижче — найкритичніші відмінності, які впливають на наші файли.

| Аспект | Tailwind v3 (legacy) | Tailwind v4 (поточний) |
|--------|---------------------|------------------------|
| **Конфігурація** | `tailwind.config.js` (JS-об'єкт `theme.extend.colors`) | `@theme { --color-*: ... }` блок у CSS, **видалено** `tailwind.config.js` |
| **Tokens SSOT** | JS дублює CSS-змінні | CSS — єдина точка істини; Tailwind v4 автогенерує utility-класи з `@theme` змінних |
| **Підключення** | `@tailwind base; @tailwind components; @tailwind utilities;` (3 директиви) | `@import "tailwindcss";` (1 рядок) |
| **Кастомні утиліти** | `@layer utilities { .my-class { ... } }` | `@utility my-class { ... }` (нова синтаксис, працює як first-class) |
| **Темні режими** | `darkMode: 'class'` у JS-конфігу + `dark:` префікс | `@variant dark` у CSS + `dark:` префікс (без JS-конфігу) |
| **Opacity-модифікатори** | `bg-red-500/50` (потребує JIT) | `bg-red-500/50` (нативно, працює завжди) |
| **CSS-змінні в utility** | потрібен arbitrary-value: `bg-[var(--my-color)]` | автоматично: будь-який `--color-X` у `@theme` → `bg-X` |
| **Container queries** | потрібен плагін | вбудовано: `@container`, `@max-md:`, `@min-lg:` |
| **PostCSS-залежність** | потрібен `postcss.config.js` + `tailwindcss/nesting` | необов'язково (CLI або Vite-плагін достатньо) |
| **Браузери** | IE11/legacy via `target: 'modern'` | Chrome 111+, Safari 16.4+, Firefox 128+ (немає legacy fallback) |

**Конкретні наслідки для нашого репо:**
- `config/tailwind.config.js` **видалено** (S1.7). Якщо ви бачите цей файл у старому fork'у — НЕ копіювати назад.
- `app/assets/tailwind/application.css` — **єдиний** файл-джерело для дизайн-токенів. `@theme { --color-gaia-*: ... }` блок є SSOT.
- `CUSTOM_TEXT_SCALE` у `ApplicationComponent` — **компенсація** того, що TailwindMerge не має доступу до v4 `@theme` (див. [DOC.5](#sync-theme--ruby-token-constants-doc5)).
- При перенесенні стороннього компонента з v3-екосистеми: (а) видалити будь-які JS-конфіги, (б) перенести `theme.extend.colors` у `@theme` блок, (в) перевірити що arbitrary-кольори не використовують raw hex (мають бути семантичні токени), (г) запустити RSpec component specs.

**Що НЕ змінилось:**
- Utility-класи (`bg-*`, `text-*`, `flex`, `grid`) — синтаксис ідентичний.
- Responsive-префікси (`sm:`, `md:`, `lg:`, `xl:`).
- State-варіанти (`hover:`, `focus:`, `disabled:`, `aria-*:`).
- `dark:` префікс синтаксично той самий — змінилось лише як він конфігурується.

> **Migration anti-pattern:** не вмикайте назад `postcss.config.js` з `tailwindcss/nesting` — v4 нативно підтримує CSS Nesting рівня браузера. Старий PostCSS-плагін і v4-нативний nesting можуть конфліктувати.

---

## 4. Шкала Типографіки

**Визначено у:** блоці `@theme` файлу `app/assets/tailwind/application.css`
**Зареєстровано у:** `ApplicationComponent::CUSTOM_TEXT_SCALE`

Кастомні термінальні розміри шрифтів, що усувають всі довільні значення `text-[Npx]`:

| CSS Токен | Utility Клас | Розмір | Line Height | Призначення |
|---|---|---|---|---|
| `--font-size-micro` | `text-micro` | `0.5rem` (8px¹) | `1rem` | Мікро-мітки, розміри файлів, бейджі ролей, водяні знаки |
| `--font-size-mini` | `text-mini` | `0.5625rem` (9px¹) | `1rem` | Елементи навігації верхнього регістру, текст статус-бейджів |
| `--font-size-tiny` | `text-tiny` | `0.625rem` (10px¹) | `1rem` | Малі мітки, метадані, заголовки секцій |
| `--font-size-compact` | `text-compact` | `0.6875rem` (11px¹) | `1.25rem` | Таблиці даних, адреси, значення метрик |
| `--font-size-display-sm` | `text-display-sm` | `clamp(1.25rem, 1.6vw + 0.5rem, 1.5rem)` | — | Responsive H3 / section headers |
| `--font-size-display-md` | `text-display-md` | `clamp(1.5rem, 2vw + 0.75rem, 2rem)` | — | Responsive H2 / page sub-titles |
| `--font-size-display-lg` | `text-display-lg` | `clamp(1.875rem, 3vw + 1rem, 2.75rem)` | — | Responsive H1 / hero titles |

> ¹ px-значення розраховані при root font-size = 16px (стандарт браузера). Оскільки токени задані у `rem`, вони масштабуються разом з налаштуваннями доступності браузера.
>
> ² **`text-display-*` через `clamp()`** — fluid typography (Google Web Vitals
> friendly: уникає CLS-перерозкладок при зміні vw). Реєструються в
> `ApplicationComponent::CUSTOM_TEXT_SCALE` як font-size (а не як text-color).

Стандартні розміри Tailwind продовжують застосовуватись для більшого тексту (наприклад, `text-xs`, `text-sm`, `text-2xl`) — вони співіснують з кастомною шкалою. Кастомні токени зокрема усувають довільні значення на кшталт `text-[9px]` для розмірів менших за `text-xs`.

### Motion Tokens (Phase 1)

| CSS Токен | Значення | Призначення |
|---|---|---|
| `--motion-fast` | `150ms` | Hover/focus transitions |
| `--motion-base` | `220ms` | Standard UI transitions (drawers, modals) |
| `--motion-slow` | `320ms` | Page-level entrances |
| `--ease-out-soft` | `cubic-bezier(0.22, 0.61, 0.36, 1)` | Default easing для UI |
| `--ease-spring` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Playful overshoot (badges, micro-interactions) |

**Глобальний `prefers-reduced-motion`** (WCAG 2.3.3) — у `@layer base`:
усі `animation-duration` та `transition-duration` примусово зводяться до 0.01ms,
коли OS повідомляє про reduced-motion. Для CSS-анімації сторінкам нічого додавати
не треба — правило діє автоматично. ⚠️ **Виняток — canvas/`requestAnimationFrame`:**
CSS-гейт глушить лише `*-duration`, НЕ JS rAF-цикл, тож JS-контролери руху
(`matrix-rain`, `reveal`, `codex--reveal`) мусять САМІ перевіряти
`matchMedia("(prefers-reduced-motion: reduce)")` у `connect()` і виходити (реалізовано).

**`@utility animate-fade-in`** — keyframe `gaia-fade-in` (translateY 4px → 0 +
opacity 0 → 1) тривалістю `--motion-base`. Використовуйте для entrance-анімацій
карток / алертів.

### Базові Стилі Типографіки

Визначено у `@layer base` всередині `application.css`:

| Елемент | Розмір | Жирність | Міжлітерний інтервал |
|---|---|---|---|
| `h1` | `1.875rem` | `300` (light) | `0.05em` |
| `h2` | `1.5rem` | `300` (light) | `0.05em` |
| `h3` | `1.25rem` | `400` (normal) | — |
| `h4` | `1rem` | `500` (medium) | `0.1em` uppercase |

### Сімейства Шрифтів

| Сімейство | Шрифти |
|---|---|
| `font-mono` | JetBrains Mono → Fira Code → SF Mono → Cascadia Code → системний mono |
| `font-sans` | Inter → system-ui → -apple-system → … |

---

## 5. TailwindMerge та патерн `tokens()`

`tokens()` — метод композиції класів дизайн-системи, який замінює пряму конкатенацію рядків і запобігає конфліктам Tailwind-класів.

### Сигнатура

```ruby
def tokens(*static_classes, **conditional_classes)
  # static_classes  — застосовуються завжди
  # conditional_classes — { "рядок-класів": boolean_умова }
end
```

### Приклади

**Статичні + умовні класи:**

```ruby
# Стилізація на основі статусу
span(class: tokens(
  "px-2 py-0.5 rounded text-tiny font-bold uppercase tracking-widest",
  "bg-status-danger text-status-danger-text animate-pulse": alert.severity == "critical",
  "bg-status-warning text-status-warning-text": alert.severity == "medium",
  "bg-zinc-800 text-zinc-300": alert.severity == "low"
))

# Активний елемент навігації
a(class: tokens(
  nav_item_base_classes,
  active ? nav_item_active_classes : nav_item_inactive_classes
))
```

**Перевизначення класів через props (shared-компоненти):**

```ruby
def initialize(status:, **attrs)
  @status = status
  @extra_class = attrs[:class]
end

def view_template
  span(class: tokens(badge_base_classes, STYLES[@status], @extra_class)) { @status }
end

# Виклик з перевизначенням без конфліктів:
render Views::Shared::UI::StatusBadge.new(status: "confirmed", class: "mt-2")
```

### Чому TailwindMerge

Без нього `tokens("text-tiny text-emerald-500")` міг би давати некоректний результат, бо TailwindMerge (без конфігурації) трактує обидва як `text-*` конфлікти та видаляє один. Реєстрація `CUSTOM_TEXT_SCALE` навчає TailwindMerge, що `text-micro/mini/tiny/compact` — це font-size токени, а не color токени.

---

## 6. Реєстр Компонентів

### 6.1 Спільні UI Примітиви (`app/views/shared/ui/`)

Це будівельні блоки рівня фреймворку, що використовуються у всіх доменних в'юшках.

| Компонент | Файл | Ключові Props | Призначення |
|---|---|---|---|
| **StatusBadge** | `status_badge.rb` | `status:`, `id:`, `class:` | AASM стан → семантичний кольоровий бейдж (20+ станів) |
| **StatCard** | `stat_card.rb` | `label:`, `value:`, `sub:`, `danger:`, `class:` | Картка метрики дашборду з опціональним danger-виділенням |
| **DataTable** | `data_table.rb` | `columns:`, `empty_message:`, `class:`, `&block` | Обгортка таблиці з налаштовуваними заголовками стовпців |
| **Pagination** | `pagination.rb` | `pagy:`, `url_helper:` | Pagy-навігація prev/next |
| **EmptyState** | `empty_state.rb` | `title:`, `description:`, `icon:`, `colspan:` | Плейсхолдер порожніх даних (grid або `<tr><td>` режим) |
| **MetaRow** | `meta_row.rb` | `label:`, `value:`, `class:` | Рядок ключ-значення для сторінок деталей |
| **ActionBadge** | `action_badge.rb` | `action:`, `class:` | Бейдж типу дії журналу аудиту (regex pattern matching) |
| **PhotoCard** | `photo_card.rb` | `photo:`, `record:`, `editable:` | Картка ActiveStorage blob з hover-оверлеєм |
| **RelativeTime** | `relative_time.rb` | `datetime:`, `css_class:`, `prefix:` | "5 хвилин тому" з повною міткою часу у `title`-підказці |
| **Skeleton** | `skeleton.rb` | `variant:`, `lines:`, `class:` | Скелетон завантаження (6 варіантів: `:balance`, `:card`, `:stats`, `:table`, `:map`, `:text`) |
| **ThemeSwitcher** | `theme_switcher.rb` | — | Кнопка перемикання темної/світлої теми (використовує Stimulus `theme` контролер) |

#### StatusBadge — Маппінг Станів

| AASM Стани | Семантичний Стиль |
|---|---|
| `pending`, `issued`, `dormant`, `maintenance_needed`, `endangered` (Codex lifecycle) | `bg-status-warning text-status-warning-text` |
| `processing`, `triggered`, `updating` | `+ animate-pulse` |
| `manual_review` | `bg-status-warning text-status-warning-text + animate-pulse` — **[DOUBLE-SPEND GUARD]**: tx_hash існує або стан невідомий, потребує ручної звірки |
| `confirmed`, `fulfilled`, `thriving` (Codex lifecycle) | `bg-status-success text-status-success-text` |
| `sent`, `paid`, `maintenance` | `bg-status-info text-status-info-text` |
| `failed`, `active` (EwsAlert), `breached`, `deceased`, `faulty`, `destroyed` (Codex lifecycle) | `bg-status-danger text-status-danger-text` |
| `acknowledged`, `mythical` (Codex lifecycle) | `bg-status-active text-status-active-text` |
| `idle`, `draft`, `expired`, `offline`, `resolved`, `cancelled`, `removed`, `unknown` (Codex lifecycle), `extinct` (Codex lifecycle) | `bg-status-neutral text-status-neutral-text` |
| `ignored` | `bg-status-neutral text-status-neutral-text opacity-30 line-through` |
| `resolved`, `cancelled`, `removed`, `extinct` (Codex) | `+ opacity-50` (застосовується через модифікатор) |

> **Примітка щодо `active`:** Стан `active` маппиться на `status-danger` при використанні з `EwsAlert` (нерозв'язаний сигнал загрози). Для інших сутностей (наприклад, `Tree` зі `status: "active"`) той самий рядок відповідає `DEFAULT_STYLE` нейтральному fallback, оскільки `StatusBadge` маппить лише стани, явно перелічені у `STYLES`. Доменні компоненти (наприклад, `Trees::Show`) застосовують власну логіку кольорів inline.

#### Skeleton — Варіанти

| Варіант | Рядки | Призначення |
|---|---|---|
| `:balance` | 3 (мітка, сума, підпис) | Lazy-load фрейм балансу гаманця |
| `:card` | 3 (заголовок, тіло, підпис) | Фрейм метаданих/blockchain-ідентичності |
| `:stats` | 3 | Картки статистики дашборду |
| `:table` | 4 повних рядки | Завантаження даних таблиці |
| `:map` | 3 (заголовок, карта, підвал) | Завантаження геопросторової карти |
| `:text` | 1 | Вбудовані текстові фрагменти |

---

### 6.2 Спільні IoT Компоненти (`app/views/shared/iot/`)

| Компонент | Файл | Ключові Props | Призначення |
|---|---|---|---|
| **MetricValue** | `metric_value.rb` | `value:`, `unit:`, `precision:` | Числове відображення значення сенсора з налаштовуваною точністю; обробляє `nil` та `BigDecimal` |

```ruby
render Views::Shared::IoT::MetricValue.new(value: 3800.0, unit: "mV", precision: 0)
render Views::Shared::IoT::MetricValue.new(value: lorenz_z, unit: "σ", precision: 4)
```

---

### 6.3 Спільні Web3 Компоненти (`app/views/shared/web3/`)

| Компонент | Файл | Ключові Props | Призначення |
|---|---|---|---|
| **Address** | `address.rb` | `address:`, `fallback:` | Ethereum-адреса з обрізанням `PREFIX_LENGTH=6` / `SUFFIX_LENGTH=4` + кнопка копіювання (використовує `clipboard` Stimulus контролер) |

```ruby
render Views::Shared::Web3::Address.new(address: @wallet.crypto_public_address)
render Views::Shared::Web3::Address.new(address: nil, fallback: "NOT_PROVISIONED")
```

---

### 6.4 Доменні Компоненти (`app/views/components/`)

Доменні компоненти — рівень сторінки, **не** призначені для повторного використання поза своїм контекстом.

#### Навігація

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Navigation::Sidebar` | `navigation/sidebar.rb` | `current_path:`, `ews_alert_count:` | Повна навігаційна бічна панель з 5 групами секцій (Strategic Insight, **Library** (Codex), Forest Ops, Neural Network, Administration), виділенням активного стану, бейджем EWS-сигналів, пульсуючим статусом |

#### Дашборд

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Dashboard::Home` | `dashboard/home.rb` | `stats:`, `events:` | Головний дашборд: 4 картки статистики, геопросторова панель карти, живий потік подій |
| `Dashboard::Map` | `dashboard/map.rb` | `trees:` | Обгортка Leaflet-карти з потоком маркерів дерев через Turbo/Stimulus |
| `Dashboard::MapNode` | `dashboard/map_node.rb` | `tree:` | Прихований Stimulus target-вузол для живих оновлень карти |
| `Dashboard::EventRow` | `dashboard/event_row.rb` | `event:` | Поліморфний рядок події (EwsAlert / BlockchainTransaction / MaintenanceRecord) |

#### Дерева

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Trees::Index` | `trees/index.rb` | `trees:`, `pagy:` | Пагінований список дерев |
| `Trees::Show` | `trees/show.rb` | `tree:`, `latest_log:`, `recent_logs:`, `maintenance_history:` | Повна деталізація дерева: біометрична матриця (радіальний SVG), графік історії імпедансу, економічна панель, сховище безпеки обладнання, журнал технічного обслуговування. Містить lazy-loading Turbo Frame `tree_chronicle_{id}`, що підвантажує `Trees::Chronicle` з `/api/v1/trees/:id/chronicle`. |
| `Trees::Chronicle` | `trees/chronicle.rb` | `tree:`, `entries:` (Array\<TreeChronicleService::Entry>), `pagy:` | Хронологічний список подій дерева. Рендериться у Turbo Frame (`tree_chronicle_{id}`). Підтримує пагінацію `Shared::UI::Pagination`, порожній стан `Shared::UI::EmptyState`. Стилізація severity через inline CSS-класи (`stable/info/warning/critical`). Skeleton-завантаження через `Shared::UI::Skeleton`. |

#### Гаманці

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Wallets::Index` | `wallets/index.rb` | `wallets:`, `pagy:` | Пагінований список гаманців |
| `Wallets::Show` | `wallets/show.rb` | `wallet:`, `transactions:`, `pagy: nil` | Деталізація гаманця з lazy-завантаженим фреймом балансу, журналом транзакцій, on-chain діями |
| `Wallets::BalanceDisplay` | `wallets/balance_display.rb` | `wallet:` | Картка балансу SCC з розбивкою locked/available/ESG-retired; Turbo target `wallet_balance_{id}` |
| `Wallets::BalanceFrame` | `wallets/balance_frame.rb` | `wallet:` | Turbo Frame обгортка для lazy-завантаження балансу |
| `Wallets::MetadataFrame` | `wallets/metadata_frame.rb` | `wallet:` | Turbo Frame обгортка для метаданих blockchain-ідентичності |
| `Wallets::TransactionRow` | `wallets/transaction_row.rb` | `tx:` | Рядок on-chain транзакції зі статус-бейджем та відображенням хешу |

#### Телеметрія

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Telemetry::LiveStream` | `telemetry/live_stream.rb` | — | Live telemetry HUD: Matrix Rain canvas (Stimulus), sticky `<thead>`, `turbo_stream_from "telemetry_stream"` |
| `Telemetry::LogEntry` | `telemetry/log_entry.rb` | `log:` | Один декодований рядок телеметрії, вставлений `UnpackTelemetryWorker` |

#### Oracle Visions

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `OracleVisions::Index` | `oracle_visions/index.rb` | `forecasts:`, `clusters:` | Список AI-прогнозів + панель симуляції |
| `OracleVisions::ForecastCard` | `oracle_visions/forecast_card.rb` | `forecast:` | Окрема картка прогнозу атрактора Лоренца |
| `OracleVisions::SimulationPanel` | `oracle_visions/simulation_panel.rb` | `clusters:` | What-If форма симуляції з повзунками діапазону; надсилає до `simulate_api_v1_oracle_visions_path` у Turbo Frame |

#### Firmware OTA

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Firmwares::Index` | `firmwares/index.rb` | `firmwares:`, `inventory_stats:`, `pagy:`, `active_ota_gateways:` | Список прошивок + інвентар версій + секція живих OTA-кампаній [SEC.20] |
| `Firmwares::New` | `firmwares/new.rb` | — | Форма завантаження нової прошивки |
| `Firmwares::Form` | `firmwares/form.rb` | `firmware:` | Поля форми прошивки |
| `Firmwares::Row` | `firmwares/row.rb` | `firmware:` | Один рядок списку прошивок |
| `Firmwares::OtaProgressBar` | `firmwares/ota_progress_bar.rb` | `uid:`, `percent:`, `current:`, `total:`, `status:` | Анімований прогрес-бар OTA; Turbo target `ota_progress_{uid}` |

#### Codex (Lore Layer)

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Codex::Index` | `codex/index.rb` | `nodes:`, `pagy:`, `realms:`, `active_realm_slug:` | Сторінка-каталог lore-вузлів (Atlas). Сітка карток (`NodeCard`), вкладки шарів (`RealmTabs`), пагінація `Shared::UI::Pagination`, порожній стан `Shared::UI::EmptyState` |
| `Codex::Show` | `codex/show.rb` | `node:`, `current_user:`, `comments:`, `current_user_attuned:` | Детальна сторінка lore-вузла. Bilingual title/subtitle, 3 markdown-блоки (`context_md` → `Codex::MarkdownRenderer`), `Shared::UI::StatusBadge` для `lifecycle_status`, зовнішні посилання, мета-рядки (Elo, view_count). Phase 2: рендерить `Codex::Attunements::Toggle` + `Codex::Comments::Thread`. |
| `Codex::RealmTabs` | `codex/realm_tabs.rb` | `realms:`, `active_slug:` | Горизонтальні вкладки шарів. Active token: `bg-gaia-primary text-gaia-primary-text` |
| `Codex::NodeCard` | `codex/node_card.rb` | `node:` | Картка одного lore-вузла. ActiveStorage `cover_image` з placeholder-гліфом per realm, lifecycle-бейдж, footer з Elo+geo_region. Linkable до `/api/v1/codex/nodes/:slug`. |
| `Codex::Attunements::Toggle` | `codex/attunements/toggle.rb` | `node:`, `current_user_attuned:`, `count:` | **Phase 2.** Кнопка "Attune"/"Attuned" + лічильник. POST/DELETE на nested-route. Лічильник оновлюється виключно через Turbo Stream broadcast (Solid Cable target `codex_node_<id>_attunement_count`) — без Stimulus optimistic UI (ADR-CDX-8, [`04_05 §2`](04_05_Codex_Lore_Module): `codex--attune` видалений як over-engineering). |
| `Codex::Comments::Thread` | `codex/comments/thread.rb` | `node:`, `comments:`, `current_user:` | **Phase 2.** Список коментарів (хронологічно) + composer (тільки для авторизованих). DOM id `codex_node_<id>_comments` — таргет для Solid Cable broadcast. Stimulus `codex--comment`. |
| `Codex::Comments::Item` | `codex/comments/item.rb` | `comment:` | **Phase 2.** Один рядок коментаря (sanitised markdown через `MarkdownRenderer`, ISO timestamp). Hidden-state — italic + opacity-50 + повідомлення модератора. DOM id `codex_comment_<id>`. |
| `Codex::Comments::Form` | `codex/comments/form.rb` | `node:` | **Phase 2.** Composer (textarea + Post). `maxlength: Codex::Comment::BODY_MAX`. Stimulus targets `codex--comment.body` / `.form`. |
| `Codex::Fractions::Card` | `codex/fractions/card.rb` | `fraction:`, `current_user:` | **Phase 3.** Read-only summary ідентичності caller'а. Empty-state CTA коли fraction nil; "Change →" + Cooldown pill коли set. DOM id `codex_fraction_card`. |
| `Codex::Fractions::Cooldown` | `codex/fractions/cooldown.rb` | `fraction:` | **Phase 3.** Status pill ("Open" / "Locked · Nd Mh"). Tokens: `status-success` / `status-warning`. |
| `Codex::Fractions::Picker` | `codex/fractions/picker.rb` | `realms:`, `active_realm:`, `nodes:`, `current_fraction:` | **Phase 3.** Turbo Frame grid pickable nodes для активного realm. Realm tabs (active = `bg-gaia-primary`), node cards з POST формою на `/codex/fractions`, disable button під час cooldown. DOM id `codex_fraction_picker`. |
| `Codex::Fractions::ProfileBadge` | `codex/fractions/profile_badge.rb` | `fraction:` | **Phase 3.** 1-row teaser для `Users::Profile`. Embed live в `render_codex_fraction` секцію. Стоїть на gaia-* tokens — не торкає legacy emerald palette профілю. |
| `Codex::Fractions::OnboardingWizard` | `codex/fractions/onboarding_wizard.rb` | `current_user:` | **Phase 8.** First-login банер у `DashboardLayout` — рендериться лише коли `current_user.codex_fraction.blank?`, з двома CTA: «Choose your Fraction →» (`/api/v1/codex/fractions/picker`) та «Browse the Codex» (`/api/v1/codex/realms`). Без Stimulus — нативна Turbo-Drive навігація (узгоджено з § 15 Native HTML over Stimulus). Layout-хук обгорнутий у `rescue StandardError` (ADR-CDX-7 fail-open). DOM id `codex_onboarding_wizard`. |
| `Codex::Battle::Arena` | `codex/battle/arena.rb` | `left:`, `right:`, `pair_seed:`, `realm:`, `error:` | **Phase 4.** Turbo Frame `id="codex_battle_arena"` з двома cards (Title + Archetype + `Elo: N · Mm`) + VS-divider + Skip. POST форми на `/codex/matches` (`MatchesController#create`; один winner_slug per форма + окрема skip-форма). UI-назва "Battle Arena" — UX label, REST-ресурс — `Codex::Match`. Error-state pill при `not enough nodes`. |
| `Codex::Leaderboard::Table` | `codex/leaderboard/table.rb` | `realm:`, `nodes:`, `limit:` | **Phase 4.** Read-only top-N Elo board. HTML `<table>` з колонками rank / Title / Elo / Matches / Lifecycle. Рендериться публічно (`/codex/leaderboard` без auth). Empty-state copy коли `nodes.empty?`. |
| `Codex::Discoveries::Toast` | `codex/discoveries/toast.rb` | `node:`, `trigger_type:`, `unlocked_at:` | **Phase 5.** Single-card toast рендериться `Codex::DiscoveryProbeWorker` через ActionCable broadcast `codex:discoveries:user:<user_id>`. Stimulus `codex--reveal` data-attribute (matrix-rain JS controller — Phase 6 batch). Trigger-type label dispatch: Observed / Battle / Pact / Streak / Oracle / Granted. gaia-* tokens only. **Namespacing під `Codex::Discoveries::*` (plural)** — необхідно щоб уникнути Zeitwerk const-clash з `Codex::Discovery` AR class. |
| `Codex::Discoveries::List` | `codex/discoveries/list.rb` | `discoveries:`, `pagy:` | **Phase 5.** Paginated 3-col grid of own unlocked nodes (rendered by `GET /api/v1/codex/discoveries/me` HTML format). Empty-state copy "Nothing unlocked yet — observe a tree, vote in the Arena, choose a fraction." Кожна card показує title / archetype_key / `trigger_type · unlocked_at`. gaia-* tokens only. |
| `Codex::Citations::Pill` | `codex/citations/pill.rb` | `citation:` | **Phase 6.** Single inline citation chip — `« Title · archetype_key »`. Slug-href anchor до `/api/v1/codex/nodes/:slug`, hover-title зі 140-char note, `aria-label` для screen readers, `focus-visible:ring-2`. gaia-* tokens (`bg-gaia-surface-sunken`, `border-gaia-border`, `hover:border-gaia-primary`). Defensive nil-safe — рендерить порожньо якщо `citation.node` зник. |
| `Codex::Citations::Strip` | `codex/citations/strip.rb` | `target:`, `citations:`, `current_user:` | **Phase 6.** Wrap-flex container з усіма pills прив'язаними до операційної цілі (`Tree`/`Cluster`/`AiInsight`/`EwsAlert`/`OracleVision`/`NaasContract`). DOM id `codex_citations_<type_underscore>_<id>` (продюсера НЕМА — сирий ActionCable знято 2026-07-27; живим тракт стане лише через підписаний Turbo-стрім). Empty-state copy "No lore citations yet." щоб freshly-cited entity мав стабільний DOM target. Інтегровано в `Trees::Show`, `Clusters::Show`, `Alerts::Row`, `OracleVisions::ForecastCard` через приватний `render_codex_citations` що early-return'ить на `defined?(Codex::Citation)` гарду + `for_target(target).includes(:node)`. |

> ⚠️ **Сирий ActionCable знято 2026-07-27** (UI.2 descope + SEC). Підписника не існувало ніколи, а `/cable` монтується движком САМ (`after_initialize`, `internal: true` — його не видно в `bin/rails routes`), тож канал без авторизації підписки був латентним крос-тенантним IDOR при послідовних ID. Realtime — лише через ПІДПИСАНІ Turbo-стріми, бо їх ім'я дістається тільки тому, кому сторінка вже відрендерилась. Заборону тримає `spec/security/no_raw_action_cable_spec.rb`.

#### Інші Доменні Компоненти

| Простір імен | Компоненти | Ключові Props |
|---|---|---|
| `Alerts` | `Index`, `Row` | `alert:` (`Badge` знято 2026-07-27 — UI без жодного рендерера) |
| `Clusters` | `Grid`, `Item`, `Show` | `cluster:`, `trees:` |
| `Gateways` | `Index`, `Item`, `Show` | `gateway:` |
| `Actuators` | `Index`, `Show`, `Card`, `CommandRow`, `CommandStatusBadge` | `actuator:`, `command:` |
| `Maintenance` | `Index`, `Show`, `Form`, `PhotoGallery`, `PhotosPage` | `record:`, `photos:` |
| `Contracts` | `Index`, `Show` | `contract:` |
| `BlockchainTransactions` | `Index`, `Show`, `OnChainFrame` | `tx:` |
| `Reports` | `Index`, `CarbonAbsorption`, `FinancialSummary` | `data:` |
| `TreeFamilies` | `Index`, `Show`, `Form` | `family:` |
| `Organizations` | `Index`, `Show` | `organization:` |
| `Users` | `Index`, `Profile` | `user:` |
| `AuditLogs` | `Index`, `Show` | `log:` |
| `SystemAudits` | `Index` | `audits:` |
| `SystemHealth` | `Show` | `health:` |
| `Provisioning` | `New`, `Success` | `hardware_key:` |
| `AccountSecurity` | `Show` | `user:` |
| `Notifications` | `Settings` | `settings:` |
| `Sessions` | `New` | `flash_alert:`, `flash_notice:` — рендериться через `AuthLayout` |
| `Passwords` | `Forgot`, `Reset` | `token:`, `flash_alert:` — рендериться через `AuthLayout` |
| `Errors` | `NoOrganization` | Quarantine-сторінка для користувачів без організації — рендериться через `AuthLayout` |

### 6.5 Namespacing Convention — Куди Розмістити Новий Компонент [DOC.6]

При зростанні `app/views/components/` (29+ директорій станом на цю редакцію) нові розробники регулярно розміщують компонент у "майже правильному" місці. Це призводить до дрейфу: один і той самий патерн у `alerts/`, `ews_alerts/` і `notifications/`. Нижченаведене **decision tree** усуває неоднозначність.

```
START: Що це за компонент?
│
├── (а) Чисто візуальний примітив без бізнес-логіки
│       (button, badge, table-wrapper, skeleton)
│       → app/views/shared/ui/                                [§6.1]
│       Приклади: StatusBadge, StatCard, DataTable, Skeleton
│
├── (б) IoT / hardware-specific відображення
│       (sensor value, calibration display, telemetry sparkline)
│       → app/views/shared/iot/                               [§6.2]
│       Приклади: MetricValue (mV, °C, σ)
│
├── (в) Web3 / blockchain-specific відображення
│       (address, tx hash, chain badge)
│       → app/views/shared/web3/                              [§6.3]
│       Приклади: Address (truncated 0x... з clipboard)
│
└── (г) Доменний компонент рівня сторінки
        (одна конкретна модель або use-case)
        → app/views/components/<resource_name>/               [§6.4]
        │
        ├── Ресурс відповідає AR-моделі (Tree, Wallet, Gateway)?
        │     → component/<plural_resource_name>/<action_or_part>.rb
        │       Приклади: trees/show.rb, wallets/balance_frame.rb
        │
        ├── Ресурс — domain concept без явної AR-моделі
        │   (Dashboard, OracleVisions, Reports)?
        │     → component/<concept>/<action_or_part>.rb
        │       Приклади: dashboard/home.rb, oracle_visions/forecast_card.rb
        │
        └── Auth / session / global UI shell?
              → component/<context>/<part>.rb
                Приклади: sessions/new.rb, navigation/sidebar.rb
```

**Правила іменування файлів:**
- Папка = `snake_case` множина моделі (`trees/`, `wallets/`, `gateways/`).
- Файл = `snake_case` action / part (`index.rb`, `show.rb`, `balance_frame.rb`, `transaction_row.rb`).
- Class = `CamelCase` namespaced: `Trees::Show`, `Wallets::BalanceFrame`.
- **Не дублювати** `<Resource>::<Resource>Show` — Rails-style: `Trees::Show`, не `Trees::TreeShow`.

**Anti-patterns (що НЕ робити):**
- ❌ `app/views/components/shared_status_badge.rb` — generic-примітив **повинен** бути в `shared/ui/`.
- ❌ `app/views/components/alerts/wallet_balance.rb` — компонент гаманця **не належить** до namespace тривог.
- ❌ Один файл з декількома компонентами через `class Inner < ApplicationComponent` — кожен компонент = окремий файл.
- ❌ DB-запити в `initialize` (наприклад, `@cluster = Cluster.find(...)`) — передавати вже завантажені об'єкти.

**Коли створювати новий namespace:**
- Створено новий ресурс/контролер у `config/routes.rb`.
- 2+ компоненти спільної доменної логіки (один компонент = inline у parent, два — підстава для namespace).
- Існуючий namespace має >10 компонентів і чітко розділяється на підсистеми (наприклад `Trees::*` → `Trees::Show::*` для секцій сторінки).

---

## 7. Stimulus Контролери

**Розташування файлів:** `app/javascript/controllers/`
**Автореєстрація:** `eagerLoadControllersFrom("controllers", application)` через importmap

| Контролер | Файл | `data-controller` | Призначення |
|---|---|---|---|
| **theme** | `theme_controller.js` | `theme` | Перемикач темного/світлого режиму |
| **clipboard** | `clipboard_controller.js` | `clipboard` | Копіювання в буфер обміну для Web3-адрес |
| **map** | `map_controller.js` | `map` | Геопросторова карта дерев Leaflet.js |
| **matrix-rain** | `matrix_rain_controller.js` | `matrix-rain` | Canvas-ефект Matrix digital rain |
| **mobile-nav** | `mobile_nav_controller.js` | `mobile-nav` | Шим `<dialog>` мобільної навігації (backdrop-click + scroll-lock Safari) — § 15.2 |
| **codex--comment** | `codex/comment_controller.js` | `codex--comment` | Codex thread — inline reply / broadcast (`Codex::Comments::Thread`) |
| **codex--reveal** | `codex/reveal_controller.js` | `codex--reveal` | Codex discovery-toast reveal (`Codex::Discoveries::Toast`) |
| **reveal** ⚠️ | `reveal_controller.js` | `reveal` | Appear-on-scroll (IntersectionObserver) — § 14.3. **Наразі 0 консюмерів** (`data-controller="reveal"` ніде): scaffold, який авто-реєструється |

> **⚠️ Важливо:** Будь-який `*_controller.js` у директорії автоматично реєструється через `eagerLoadControllersFrom` — **не залишайте scaffold-файли в production** (пор. `reveal` вище: авто-зареєстрований, але без жодного консюмера).

### 7.1 Контролер `theme`

**Targets:** `icon`
**Actions:** `toggle`

Керує темою dark/light:

1. Читає `localStorage.getItem("theme")` при `connect()`
2. Fallback на `window.matchMedia("(prefers-color-scheme: dark)")`
3. Перемикає клас `.dark` на `document.documentElement`
4. Слухає зміни на рівні ОС через `mediaQuery.addEventListener("change", ...)`
5. Оновлює target `icon` SVG-іконкою (☀ в dark-режимі, ☽ у light-режимі)

```html
<div data-controller="theme">
  <button data-action="click->theme#toggle"
          data-theme-target="icon">
    <!-- SVG інжектується контролером -->
  </button>
</div>
```

**`disconnect()`:** Видаляє `mediaQuery.removeEventListener("change", ...)` — запобігає memory leak при Turbo Drive навігації між сторінками.

**Phlex-використання:** Обгорнутий у `Views::Shared::UI::ThemeSwitcher`.

### 7.2 Контролер `clipboard`

**Values:** `content` (String — текст для копіювання)
**Targets:** `button`

Копіює `contentValue` до буфера через `navigator.clipboard.writeText()` з fallback на `document.execCommand("copy")`. Показує галочку `✓` на 2 секунди як візуальний зворотний зв'язок.

```html
<span data-controller="clipboard"
      data-clipboard-content-value="0x1234...abcd">
  <button data-action="clipboard#copy"
          data-clipboard-target="button">⧉</button>
</span>
```

**`disconnect()`:** Викликає `clearTimeout(this.feedbackTimeout)` — очищає таймер зворотного зв'язку ✓, запобігаючи DOM mutation після знищення компонента.

**Phlex-використання:** Вбудований у `Views::Shared::Web3::Address`.

### 7.3 Контролер `map`

**Targets:** `node`

Ініціалізує Leaflet.js карту з тайлами CartoDB Dark Matter (кіберпанк-естетика). Підтримує хеш `markers` (`DID → L.Marker`) для інкрементальних оновлень.

**Ключовий lifecycle:**

- `connect()` — ініціалізує карту, встановлює центр за замовчуванням (Черкаси: 49.4444, 32.0598); ініціалізує `this.markers = {}` (DID рядок → `L.Marker` instance) та `this.markerLayer = L.layerGroup()`
- `disconnect()` — викликає `this.map.off()`, `this.map.remove()`, встановлює `this.map = null`, `this.markerLayer = null`, скидає `this.markers = {}`, очищає `this.resizeTimeout`. **Turbo Drive Cache fix:** видаляє всі дочірні вузли (`replaceChildren()`) та Leaflet CSS-класи (`leaflet-*`) зі свого DOM-елемента — гарантує, що `connect()` ініціалізує карту з повністю чистого стану після відновлення зі snapshot-кешу Turbo.
- `nodeTargetConnected(element)` — викликається автоматично Turbo/Stimulus коли `<div data-map-target="node">` додається до DOM через Turbo Stream; витягує `data-lat/lng/did/stress/charge` та викликає `updateMarker()`

**Логіка кольору маркера:**

| Умова | Колір | Свічення |
|---|---|---|
| `stress > 0.8` або `status === "removed"` | `#ef4444` (червоний) | `rgba(239,68,68,0.8)` |
| `stress > 0.4` або `charge < 30` | `#eab308` (жовтий) | `rgba(234,179,8,0.6)` |
| За замовчуванням (здорове) | `#10b981` (emerald) | `rgba(16,185,129,0.5)` |

**Phlex-використання:** `data: { controller: "map" }` на map `<div>` у `Dashboard::Map`. Приховані `<div data-map-target="node">` елементи стрімляться через Turbo з `Dashboard::MapNode`.

### 7.4 Контролер `matrix-rain`

Canvas-ефект Matrix digital rain з hex-символами (`0-9A-F`). Canvas-елемент отримує `transform-gpu will-change-transform` для GPU-compositing (апаратне прискорення).

- `connect()` — отримує canvas 2D контекст, запускає rAF-цикл (`requestAnimationFrame`) з throttle до ~16 fps (`FRAME_INTERVAL = 60ms`); цикл автоматично призупиняється при неактивній вкладці
- `disconnect()` — скасовує rAF через `cancelAnimationFrame(this.rafId)`, видаляє resize-слухач
- `resize()` — підганяє canvas під батьківський елемент, переініціалізує масив `drops[]`

**Phlex-використання:** `canvas(data: { controller: "matrix-rain" }, class: "absolute inset-0 z-0 opacity-20 pointer-events-none w-full h-full transform-gpu will-change-transform")` всередині `Telemetry::LiveStream`.

---

## 8. Інтеграція Turbo (Streams & Frames)

### 8.1 Turbo Streams

Оновлення DOM в реальному часі через `ActionCable` (Solid Cable).

Реєстр звірено з кодом ПОВНІСТЮ (UI.4, 2026-07-27) — обидва боки, і продюсери, і підписники.

| Stream | Підписка у | Продюсер(и) |
|---|---|---|
| `"telemetry_stream"` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` (черга `uplink` — firehose) |
| `[wallet, :transactions]` | `Wallets::Show` | `BlockchainTransaction#broadcast_status_change` (рядок tx) · `Wallet#broadcast_balance_update` (frame-заглушка балансу, клас 2 §8.1а) |
| `"ota_channel_{uid}"` | `Gateways::Show` · `Firmwares::Index` | `Downlink::PendingQueueService` [SEC.20] — живий FW.60 poll-тракт; `OtaTransmissionWorker` теж пише сюди, але сам **не має енкʼюера** (superseded) |
| `[cluster, :alerts]` | `Clusters::Show` | `EwsAlert#broadcast_new_alert` · `#broadcast_alert_update` |
| `"ews_alerts_org_{id}"` | `Alerts::Index` | `EwsAlert#broadcast_alert_update` |
| `"geospatial_matrix"` | `Dashboard::Map` | `Tree#broadcast_map_update` |
| голий `Organization` | ⚠️ **ніхто** | 4 продюсери: `ActuatorCommand` · `ResetActuatorStateWorker` (×2) · `ActuatorCommandWorker` · `InsurancePayoutWorker` |
| голий `NaasContract` | ⚠️ **ніхто** | `BurnCarbonTokensWorker` |
| `"global_events"` | ⚠️ **ніхто** | `InsurancePayoutWorker` |

> 🔴 **Стріми з підписником ≠ робочий тракт — ціль теж мусить існувати в DOM тієї сторінки.** Саме тут ховались усі знайдені дефекти, і жоден із них не був видимий із коду продюсера. Три приклади, кожен іншого роду: `Wallet#broadcast_balance_update` слав у голий `wallet`-стрім (підписник був — на ІНШИЙ, композитний); `BlockchainMintingService` цілив у `transaction_{id}`, тоді як `Wallets::TransactionRow` рендерить `dom_id` = `blockchain_transaction_{id}`; `ResetActuatorStateWorker` цілить у `actuator_card_{id}`, а `Actuators::Card` рендерить `actuator_{id}` (і той самий контролер у синхронному шляху вживає ПРАВИЛЬНИЙ id).
>
> ⚠️ **Три останні рядки — живі продюсери в порожнечу**, свідомо лишені до продуктового рішення «дотягнути чи знести» ([`00_07`](00_07_Action_Plan_Tracker) UI.4). П'ять із них б'ють у голий `Organization`-стрім — це **одна архітектурна діра, не п'ять недоглядів**: жодна сторінка не підписана на `turbo_stream_from(@organization)`, і `"ews_alerts_org_{id}"` тут не рахується (це рукописний РЯДОК, структурно інший стрім).
>
> ⚠️ `[cluster, :alerts]` має **розбіжність форми**: `Alerts::Row` віддає `<tr>`, а `Clusters::Show` тримає список як `<div>`-и, не таблицю. Тракт «живий» за парою стрім+ціль, але вставка структурно невалідна — окремий відкритий пункт UI.4.

**Патерн:**

```ruby
# Підписка (у view_template компонента)
turbo_stream_from @wallet, :transactions

# Broadcast (у worker/service) — рендер ЗАВЖДИ через `html:` + Phlex-компонент
Turbo::StreamsChannel.broadcast_replace_later_to(
  [ @wallet, :transactions ],
  target: ActionView::RecordIdentifier.dom_id(tx),
  html: Wallets::TransactionRow.new(tx: tx).call
)
```

> ⚠️ **`partial:`/`locals:` тут не спрацюють — і голий `Turbo::Broadcastable` теж.** Партіалів моделей у репо НЕМА (`app/views/` тримає лише мейлери, layouts і Phlex-компоненти), тому успадковані `model.broadcast_update`/`broadcast_replace`, які дефолтяться на `to_partial_path`, кидають `ActionView::MissingTemplate` — синхронно, у виклику. Броадкастити лише явним `Turbo::StreamsChannel.broadcast_*_to` з `html:`. Прецедент — [`00_07`](00_07_Action_Plan_Tracker) ARCH.67: такий виклик у money-path-сервісі обривав батч-цикл, лишаючи `locked_balance` решти транзакцій замороженим.

> ⚠️ **Broadcast не має локалі глядача — і структурно не може мати (⊥, не баг).** `html:` — звичайний аргумент, тож Phlex-рендер відбувається **eagerly в процесі-продюсері**; `_later_` відкладає лише доставку. `LocaleSettable` — це `before_action`, тож у Sidekiq його нема, а `ApplicationController.renderer` `before_action`-ланцюг не проганяє: рендер бере `I18n.locale` **поточного треда**. Наслідок двоякий — продюсер із контролера (`resolve!` → `after_update_commit` → `broadcast_alert_update`) віддає локаль **того, хто клацнув** («латвієць бачить український рядок, бо українець натиснув Підтвердити»), а з воркера — `default_locale`. Глибше: один HTML летить у **спільний** stream N підписникам із різними локалями, тож єдиної правильної локалі там не існує в принципі. Reload лікує.

### 8.1а Правило: payload броадкасту не несе локаль-залежної прози

> 🧱 **Інваріант (фундамент, не оптимізація): вартість live-оновлення масштабується ПОПИТОМ (глядачі), НІКОЛИ каталогом (локалі).**
>
> Кількість локалей — це число, яке ми хочемо нарощувати вільно й дешево; кількість глядачів — реальний попит, за який платити не шкода. Будь-який дизайн, у якому додавання **невживаної** мови робить кожну наступну подію дорожчою, оподатковує саму амбіцію бути багатомовними.
>
> Тому «розкласти broadcast по локалях» (по стріму на мову) — **заборонений клас**, а не дорогий варіант. Ціна: на кожну подію — по Phlex-рендеру, по `INSERT` у `solid_cable_messages` і по `NOTIFY` **на кожну локаль каталогу**, з `message_retention: 1.day`. Solid Cable — Postgres, і хоч БД окрема (`_cable`), інстанс той самий, що обслуговує money-path: фан-аут по каталогу = множник на записи, що ділять IOPS і пул зʼєднань із мінтингом. І головне — переважна більшість тих рядків не доставляється **нікому**: робота не просто дорога, вона доказово змарнована.
>
> **Два дозволені класи:**
> 1. **Locale-invariant payload** (найкращий) — броадкаст несе лише те, що однакове в усіх мовах: числа, ID, хеші, timestamp, `data-*`. Еталон уже в репо — `Dashboard::MapNode` (нуль `t()`). Підписи живуть у хромі сторінки, відрендереному один раз у запиті, де локаль відома.
> 2. **Viewer-driven pull** — броадкаст несе локаль-вільну заглушку (`turbo_frame` зі `src`), і кожен клієнт тягне фрагмент **своїм** запитом, де `LocaleSettable` уже відпрацював. Ціна — O(фактичних глядачів), нуль залежності від каталогу. Для рідкісних подій (OTA-прогрес) це прийнятно; для firehose (телеметрія) обовʼязковий клас 1.
>
> **Гейт, що це тримає** (форма — «курована мапа як tripwire»): узяти компоненти, які РЕАЛЬНО рендеряться в `broadcast_*`-сайтах, і для кожного зрендерити двічі у двох різних локалях — вивід мусить бути байт-у-байт однаковий. Дві локалі доводять інваріантність, тож сам гейт теж не залежить від каталогу. Новий broadcast-компонент потрапляє під перевірку **за замовчуванням**; свідомий виняток — іменований запис зі списку, що тільки скорочується. Міграція наявних поверхонь і вмикання гейта → [`00_07`](00_07_Action_Plan_Tracker) I18N.2 (той самий ratchet-порядок, що в UI.1: спершу migrate-to-green, потім HARD).

### 8.2 Turbo Frames (Lazy Loading)

Використовуються для відкладення дорогих запитів до бази даних до моменту після першого рендерингу сторінки.

| Frame | Використовується у | URL джерела |
|---|---|---|
| `wallet_balance_frame_{id}` | `Wallets::Show` | `balance_api_v1_wallet_path(@wallet)` |
| `wallet_metadata_frame_{id}` | `Wallets::Show` | `metadata_api_v1_wallet_path(@wallet)` |
| `simulation_results` | `OracleVisions::SimulationPanel` | Turbo form target |

**Патерн Skeleton:**

```ruby
turbo_frame_tag "wallet_balance_frame_#{@wallet.id}",
                src: balance_api_v1_wallet_path(@wallet),
                loading: :lazy do
  render Views::Shared::UI::Skeleton.new(variant: :balance)
end
```

### 8.3 Turbo Target IDs (для Worker Broadcasts)

Іменовані DOM-цілі, що використовуються Sidekiq workers для інжекції контенту в реальному часі:

| Target ID | Компонент | Оновлюється ким |
|---|---|---|
| `wallet_balance_frame_{id}` | `Wallets::BalanceFrameStub` → після фетчу `Wallets::BalanceFrame` | `Wallet#broadcast_balance_update`. ⚠️ Ціль — сам **turbo-frame**, а не `wallet_balance_{id}` усередині нього: payload = локаль-вільна заглушка зі `src`, фрагмент кожен глядач тягне своїм запитом (клас 2, §8.1а) |
| `blockchain_transaction_{id}` | `Wallets::TransactionRow` | `BlockchainTransaction#broadcast_status_change` (`dom_id`, не рукописний рядок) |
| `telemetry_feed` · `feed_placeholder` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` |
| `alerts_list` · `ews_alert_{id}` | `Alerts::Row` | `EwsAlert#broadcast_new_alert` (prepend) · `#broadcast_alert_update` (replace) |
| `map_node_{id}` | `Dashboard::MapNode` | `Tree#broadcast_map_update` — **еталон класу 1** (нуль `t()`) |
| `ota_progress_{uid}` | `Firmwares::OtaProgressBar` | `Downlink::PendingQueueService` [SEC.20]: hint → 0% · chunk-fetch → `ch+1/total` · `fw=` → COMPLETE (Rails бачить кожен fetch Королеви; initial-render = `Gateways::Show` + `Firmwares::Index`) |

> ⚠️ **Цілі БЕЗ сторінки, що їх рендерить** (продюсер живий, вставляти нема куди): `recent_commands_feed` · `command_status_{id}` · `actuator_card_{id}` (реальний id — `actuator_{id}`) · `insurance_card_{id}` · `contract_status_badge_{id}` · `events_feed`. Реєстр і рішення по кожному → [`00_07`](00_07_Action_Plan_Tracker) UI.4.
>
> `Alerts::Badge` тут більше немає: його єдиний продовий рендерер (`EwsAlert#broadcast_status_change`) знято 2026-07-27 як тракт, ціль якого не існувала в DOM жодної сторінки. Сам компонент лишається змонтованим лише в Lookbook — доля як design-system-активу відкрита в UI.4.

---

## 9. Чекліст Доступності

Всі компоненти перевіряються за цим чеклістом:

| Правило | Реалізація |
|---|---|
| `role` на семантичних елементах | `role="table"` на таблицях, `role="status"` на бейджах, `role="navigation"` на бічній панелі, `role="group"` на StatCard |
| `aria-label` на інтерактивних елементах | `<button>` та icon-only `<a>` мають описовий `aria_label:`. **Виняток [UI.3]:** лінки з видимим текстом + динамічним дочірнім контентом (nav-item + EWS-badge у `Navigation::Sidebar`) — БЕЗ `aria_label` (він перекриває дочірній текст для SR, badge стає нечутним); такі читаються дочірнім текстом + `aria-current` |
| `aria-current="page"` | Активні елементи навігації у `Navigation::Sidebar` |
| `scope="col"` на `<th>` | Всі заголовки таблиць |
| `focus-visible:` а не `focus:` | 100% відповідність у всіх 83+ компонентах |
| `aria-hidden="true"` на декоративних елементах | Іконки бічної панелі, фонові текстові водяні знаки |
| Клавіатурно-навіговані focus rings | `focus-visible:ring-2 focus-visible:ring-gaia-primary` на всіх інтерактивних елементах |
| Контрастність кольорів | Семантичні токени гарантують WCAG AA в обох режимах (light та dark) |
| `disabled:opacity-50 disabled:cursor-not-allowed` | Всі відключені кнопки (наприклад, видалення PhotoCard) |
| `role="status" aria-label="Loading…"` | Компонент `Skeleton` |

### Стандартний Патерн Фокусу

```ruby
# ✅ Канонічне focus ring для всіх інтерактивних елементів
class: "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"

# ✅ Патерн переходу
class: "transition-all duration-200 ease-in-out"
class: "transition-colors duration-300"   # перемикання теми
```

---

## 10. Lookbook (Дослідник Компонентів)

> **Тести view-компонентів** — конвенції написання спек + карта покриття (який spec що верифікує) живуть у [`04_06`](04_06_Testing_Guide_and_Coverage) (Testing Guide: Частина A — конвенції, §A.10 — карта покриття). One-Home: 04_06 володіє view-component-тестуванням; цей документ — реєстр компонентів ([§6](#6-реєстр-компонентів)) + Lookbook-explorer нижче.

Lookbook надає живий попередній перегляд усіх компонентів за адресою `http://localhost:3000/lookbook` (лише в режимі development).

**Файли превью:** `spec/components/previews/`

| Превью | Сценарії |
|---|---|
| `StatusBadgePreview` | Всі AASM стани, Transaction lifecycle, Interactive |
| `StatCardPreview` | Default, Danger, Minimal, Interactive |
| `ActionBadgePreview` | 2 сценарії: `all_types` (4 типи дій), `interactive` |
| `EmptyStatePreview` | Grid, Custom icon, Minimal |
| `MetaRowPreview` | Default, Numeric, Interactive |
| `AlertBadgePreview` | 2 сценарії: `all_combos` (9 combo matrix severity × status), `interactive` |
| `DashboardEventRowPreview` | EwsAlert, BlockchainTx, Maintenance, Unknown |
| `SidebarPreview` | Default, With alert badge, Telemetry active, Interactive |
| `Web3AddressPreview` | Valid, Short, Nil fallback, Custom fallback, Interactive |
| `IoTMetricValuePreview` | Default, High precision, Nil, No unit, Interactive |
| `DataTablePreview` | With sample rows, Empty state |
| `PaginationPreview` | First page, Middle page, Last page |
| `RelativeTimePreview` | Recent, With prefix, Nil datetime |
| `ThemeSwitcherPreview` | Default toggle button |
| `SkeletonPreview` | Default (balance), Text, Card, Stats, Table, Map, Custom lines, Interactive |
| `WalletTransactionRowPreview` | Confirmed carbon, Pending forest, Failed, Processing, Interactive |
| `WalletBalanceDisplayPreview` | Tree wallet, Locked funds, Org wallet, Zero balance, Interactive |
| `ClusterItemPreview` | Healthy, Under threat, Low health, Interactive |
| `ActuatorCommandStatusBadgePreview` | All command statuses, Interactive |
| `ActuatorCommandRowPreview` | Confirmed open, Issued activate, Failed close, Interactive |
| `PhotoCardPreview` | Image photo, File fallback |

---

## Додаткові Матеріали

### Налаштування Lookbook

```ruby
# Gemfile (development group)
gem "lookbook"
gem "view_component"
```

```ruby
# config/routes.rb
mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?
```

```ruby
# config/application.rb
config.lookbook.preview_paths = [ root.join("spec/components/previews").to_s ]
```

**Доступ:** Запустіть `bin/rails server` і відкрийте **http://localhost:3000/lookbook**

---

### Додавання Нових Кольорів Статусу

Щоб розширити систему семантичних колірних токенів новим кольором статусу:

1. **Define CSS variables** in `app/assets/tailwind/application.css` for both `:root` and `.dark`:
   ```css
   :root {
     --status-new: #e0f2fe;
     --status-new-text: #075985;
   }
   .dark {
     --status-new: #0c4a6e;
     --status-new-text: #bae6fd;
   }
   ```
   2. **Зареєструйте токен** у блоці `@theme` в `application.css`:
   ```css
   @theme {
     --color-status-new: var(--status-new);
     --color-status-new-text: var(--status-new-text);
   }
   ```
   3. **Використовуйте назву токена** у Phlex-компонентах через Tailwind-класи: `bg-status-new text-status-new-text`

---

### Пагінація (Pagy) та Запобігання N+1

#### Налаштування Pagy

Усі пагіновані вигляди використовують Pagy через спільний компонент `Pagination`:

```ruby
# Controller
def index
  @pagy, @trees = pagy(Tree.includes(:cluster, :tree_family).active, items: 20)
end

# View
render Views::Shared::UI::Pagination.new(
  pagy: @pagy,
  url_helper: ->(page:) { helpers.api_v1_cluster_trees_path(@cluster, page: page) }
)
```

#### Запобігання N+1 Запитам

**Правило: Всі дані, що відображаються у вигляді, ОБОВ'ЯЗКОВО мають бути попередньо завантажені в контролері.** Ліниве завантаження в Phlex-компонентах заборонено.

```ruby
# ✅ Good — eager load everything the view needs
def index
  @pagy, @contracts = pagy(
    NaasContract.includes(:organization, :cluster).order(created_at: :desc),
    items: 20
  )
end

# ❌ Bad — N+1 when the view calls contract.organization.name
def index
  @pagy, @contracts = pagy(NaasContract.order(created_at: :desc), items: 20)
end
```

**Типові патерни:**

```ruby
# Nested associations
Tree.includes(:cluster, :tree_family, wallet: :blockchain_transactions)

# Counter cache (no extra query)
cluster.active_trees_count  # Uses denormalized column

# Conditional eager loading for N+1 prevention in Ruby-level filtering
cluster.association(:ews_alerts).loaded?
  ? cluster.ews_alerts.any?(&:status_active?)
  : cluster.ews_alerts.unresolved.any?
```

#### Інтеграція Groupdate

Для агрегації часових рядів у звітах:

```ruby
# Controller
@daily_counts = TelemetryLog.where(tree: @cluster.trees)
                             .group_by_day(:created_at)
                             .count
```

---

### Конвенції Файлів та Іменування

| Елемент | Конвенція | Приклад |
|---------|-----------|---------|
| Shared UI компонент | `app/views/shared/ui/<name>.rb` | `status_badge.rb` |
| Domain компонент | `app/views/components/<resource>/<action>.rb` | `trees/show.rb` |
| Модуль компонента | `Module::<Resource>::<Action>` | `Trees::Show` |
| Shared UI модуль | `Views::Shared::UI::<Name>` | `Views::Shared::UI::StatusBadge` |
| Lookbook preview | `spec/components/previews/<name>_preview.rb` | `status_badge_preview.rb` |
| Preview шаблон | `spec/components/previews/<name>_preview/<scenario>.html.erb` | `all_states.html.erb` |
| Spec компонента | `spec/views/components/<resource>/<name>_spec.rb` | `actuators/card_spec.rb` |
| Shared spec | `spec/views/shared/ui/<name>_spec.rb` | `status_badge_spec.rb` |

---

### Картка Швидкого Доступу

```ruby
# Відобразити статус-бейдж
render Views::Shared::UI::StatusBadge.new(status: "confirmed")

# Відобразити картку метрики
render Views::Shared::UI::StatCard.new(label: "Trees", value: "1,000", sub: "active")

# Відобразити пагінацію
render Views::Shared::UI::Pagination.new(pagy: @pagy, url_helper: ->(page:) { path(page: page) })

# Відобразити порожній стан у таблиці
render Views::Shared::UI::EmptyState.new(title: "Немає даних.", colspan: 5)

# Умовні класи
span(class: tokens("text-tiny uppercase", "text-red-500": danger?, "text-emerald-500": !danger?))

# Web3 адреса з кнопкою копіювання
render Views::Shared::Web3::Address.new(address: "0x1234...")

# IoT метрика з точністю
render Views::Shared::IoT::MetricValue.new(value: 3800, unit: "mV", precision: 0)

# Lookbook preview з анотаціями
class MyComponentPreview < Lookbook::Preview
  # @label Мій Компонент
  # @display bg_color "#000"

  # @label Інтерактивний
  # @param prop text
  def interactive(prop: "default")
    render Views::Shared::UI::MyComponent.new(prop: prop)
  end
end
```

---

## 11. Міграція з ActionController::API на ActionController::Base

### Контекст

`Api::V1::BaseController` раніше успадковував `ActionController::API`. Це було змінено на `ActionController::Base`
(з `layout false`), оскільки `ActionController::API` не надає `ActionView::Rendering` з `view_context`,
необхідним для Phlex `render_in`. При `ActionController::API` Phlex-компоненти повертали порожній body
з HTTP 200 — тести проходили, бо перевіряли лише `have_http_status(:ok)`, не вміст відповіді.

### Виявлені та виправлені баги

Після переходу Phlex-компоненти почали реально рендеритись, що виявило приховані помилки:

| Компонент | Баг | Виправлення |
|-----------|-----|-------------|
| `Gateways::Show` | (1) `@gateway.firmware_hash` — колонка не існує; (2) `hardware_key&.uid` — HardwareKey має `device_uid`, не `uid` | (1) `try(:firmware_hash)` safe fallback; (2) `.device_uid` |
| `Provisioning::Success` | `@device.did` — Gateway має `uid`, не `did` | Замінено на `@device.try(:did) \|\| @device.try(:uid)` |
| `Maintenance::Show` | `edit_api_v1_maintenance_record_path` — маршрут `:edit` не існував | Додано маршрут `:edit` та дію контролера `edit` |

### CI: Компіляція Tailwind CSS

Tailwind CSS повинен бути скомпільований перед тестами. Крок `bin/rails tailwindcss:build`
додано до CI workflow перед запуском rspec (обидва jobs: `test` та `feature-test`).
Layout-компоненти (`AuthLayout`, `DashboardLayout`) використовують `stylesheet_link_tag "tailwind"`,
що вимагає наявності скомпільованого `tailwind.css` у `app/assets/builds/`.

### Правила

1. **Компоненти НЕ ПОВИННІ звертатись до методів/колонок моделей, що не існують** — навіть якщо
   компонент "працював" під `ActionController::API`, перехід на `ActionController::Base` виявить
   баг як `NoMethodError` під час рендерингу.
2. **Тести view-компонентів повинні використовувати моки з полями, що відповідають реальній схемі БД**
   (наприклад, `device_uid`, а не `uid` для HardwareKey).
3. **`bin/rails tailwindcss:build` обов'язковий перед тестами**, якщо layout-компоненти посилаються
   на скомпільовані CSS-файли.

> **CSRF** — `protect_from_forgery with: :exception` + Bearer-bypass через `handle_unverified_request`: дім опису — §1 (архітектура контролера).

---

## 12. Інтернаціоналізація та Локалізація (i18n)

> SSOT для чотиримовного UI (EN — default; UA/LV/LT — auto-detect через
> Accept-Language або explicit cookie; розширюваний до N мов додаванням рядка
> в `config.i18n.available_locales` + одного YAML-набору) та для Phlex
> `t(".key")` autoscope, CI-гейтів, controller/backend локалізації.
> Об'єднує колишні §12 (Phase 1-2) та §19 (Convention over Configuration).

### 12.1 Архітектурні правила (foundational)

1. **Жодних hardcoded user-facing strings.** Все, що користувач бачить (UI текст, flash, error JSON, mailer body) — через `I18n.t`. Hardcoded UA/EN рядки у `app/views/components/**/*.rb` та `app/controllers/api/v1/**/*.rb` **мають** блокуватись CI. ⚠️ **Фактично не блокуються:** job `i18n_check` (`ci.yml`) ганяє лише `i18n-tasks missing` / `check-consistent-interpolations` / `check-normalized` — усі три звіряють **парність ІСНУЮЧИХ `t()`-ключів** між локалями; сканера сирих строкових літералів у репо немає, тож хардкод у «захищеній» зоні проходить зеленим. Робота → [`00_07`](00_07_Action_Plan_Tracker) I18N.1.
2. **Per-domain YAML layout.** Файли локалізації лежать як `config/locales/<domain>/<locale>.yml`. Кожен «домен» = верхньокореневий namespace (`wallets`, `codex`, `actuators`, `flash`, `errors`, ...). Масштабовано до десятків доменів без monolithic `en.yml`. Детальна структура — §12.3.
3. **Class-name autoscope для Phlex.** `ApplicationComponent` override'ить `t` (від `Phlex::Rails::Helpers::Translate`):
   - `t(".key")` всередині `Codex::Show` резолвить у `I18n.t("codex.show.key")`
   - Абсолютний ключ (`t("flash.errors.unauthorized")`) працює без autoscope
   - Працює як у controller-render контексті, так і в `Component.new(...).call` (specs/Turbo broadcasts)
   - Для анонімних subclasses (`Class.new(Component)` у тестах) scope обчислюється по першому named ancestor
   - **Міграція завершена:** всі компоненти переведені на `t(".key")` relative-lookup. Абсолютні `t("codex.fractions.current")` залишаються тільки для cross-scope ключів (ключ із сусіднього компонента). `I18n.t()` у view-шарі повністю замінено на `t()` — 0 залишків. Detail-pattern та приклади — §12.6.
4. **Controller-side strings.** Flash, error JSON, redirect notice — всі через `I18n.t("flash.<controller>.<action>")` / `I18n.t("errors.api.<code>")`. Hardcoded UA рядки у контролерах = CI failure. Детальний мапінг доменів — §12.8.
5. **Mailer та service-worker.** Mailer templates (`app/views/<mailer>/*.erb`) та `pwa/service-worker.js` поки **out of scope** для авто-перевірки — їх локалізують вручну за тим самим патерном (`config/locales/mailers/...`, `pwa/...`). Service-worker не йде через I18n (це JS у браузері). Поточний backlog — §12.13.

### 12.2 Конфігурація

`config/application.rb`:
```ruby
config.i18n.available_locales = %i[uk en lv lt]
config.i18n.default_locale    = :en
config.i18n.fallbacks         = true    # локаль-НЕЗАЛЕЖНИЙ ланцюг, див. нижче
config.i18n.load_path        += Dir[Rails.root.join("config/locales/**/*.yml")]
```

**`fallbacks = true` — не «увімкнути», а САМЕ локаль-незалежна форма.** Railtie
(`ActiveSupport::I18nRailtie#init_fallbacks`) приймає чотири форми — `true`,
Array, Hash і `OrderedOptions`; з `true` він будує `Fallbacks.new(default_locale)`,
тобто хвіст `[:en]` для **будь-якої** локалі, зокрема ще не існуючої, а
регіональні дістають ще й parent-ланку: `pt-BR → [:pt-BR, :pt, :en]`. Саме це
й означає обіцянка «розширюваний до N мов додаванням рядка» — жодна нова мова
не потребує запису у fallback-конфізі.

> ⚠️ **Чому НЕ поіменний хеш** (стояв тут до 2026-07-26). Hash — єдина з чотирьох
> форм, яка кладе всі локалі в `@map` і лишає `defaults` **порожнім**: п'ята
> локаль не діставала `:en` взагалі. І гірше — `production.rb` (Rails-скаффолд)
> мав власний `config.i18n.fallbacks = true`, а environment-файли вантажаться
> ПІСЛЯ тіла `Application`, тож railtie бачив лише останнє значення: прод жив на
> локаль-незалежному ланцюгу, dev/test — на хеші. Розбіжність тиха, але кусюча:
> у test ще й `raise_on_missing_translations`, тож нова локаль валила б спеки там,
> де прод спокійно віддавав би англійську. Дім тепер один — `application.rb`.
> **Пріоритет вибору мови (без збереженої cookie):**
> `request.preferred_language(available_locales)` читає `Accept-Language`
> браузера — `uk` → `:uk`, `lv` → `:lv`, `lt` → `:lt`, будь-що інше → `:en`.
> Тобто українець, латвієць і литовець отримують свою мову автоматично;
> решта світу — English. Явний вибір через switcher зберігається у постійній
> cookie і має найвищий пріоритет.
>
> **Чому `uk`, а не `ua`?** `uk` — IETF BCP 47 / ISO 639-1 код **мови**
> (Ukrainian). `ua` — ISO 3166-1 код **країни** Україна. `<html lang="uk">`
> — єдиний валідний варіант для browser/screen-reader negotiation. UI-label
> для користувача — `UA · Українська`, де довга назва береться з
> `locale.available.<code>` у YAML, а дволітерний префікс — з Ruby-мапи в
> `locale_switcher.rb` (з фолбеком `code.upcase`).
>
> 🧱 **Ендоніми живуть ЛИШЕ в базовій локалі — і це не економія, а тип даних.**
> «Українська» однакова в будь-якому UI: користувач шукає в перемикачі власну
> назву своєї мови, не її переклад. Тобто таблиця локаль-**інваріантна**, і
> кожна зайва копія — не переклад, а запрошення її «виправити». Копії росли як
> N×N (чотири мови = 16 рядків, при орієнтирі 150+ — 22 500), тож решта каталогу
> тепер бере значення fallback-ланцюгом. Ruby-мапа з §12.14 тут НЕ потрібна саме
> тому, що `i18n-tasks missing` цей скоуп і так ігнорує (динамічний ключ) —
> механізм, яким §12.14 обґрунтовує заморожену мапу, на цю поверхню не діяв.
> Вісь тримає `spec/i18n/locale_catalog_invariance_spec.rb`: базова визначає
> ендонім для КОЖНОЇ налаштованої локалі · жодна не-базова не має власної копії
> (`fallback: false`) · усі UI-локалі резолвлять однаково. Спека ітерує
> `available_locales`, тож п'ята мова не потребує правки спеки, але одразу
> потрапляє під неї.

> 🧱 **Базовий шар перекладів дає гем `rails-i18n` — і він МУСИТЬ лишатись у
> головній групі `Gemfile`.** Власні YAML під `config/locales/` покривають лише
> НАШІ рядки; усе, що малює сам Rails — `errors.messages.*` (валідація),
> `date.*`/`time.*` (формати, назви днів і місяців), `number.*` (роздільники,
> валютний символ), `helpers.submit.*`, `datetime.distance_in_words.*` — живе в
> цьому гемі, і він же вмикає **правила плюралізації** (без них українська йде
> за дефолтним `one/other`, тож форми `few`/`many` не можуть бути обрані ніколи,
> хоч би скільки їх було в YAML).
>
> ⚠️ **Пастка, що вже спрацювала (2026-07-26).** Гем був у `Gemfile.lock` —
> але лише **транзитивно**, як залежність `i18n-tasks`, оголошеного в групі
> `development, test` та ще й з `require: false`. `Bundler.require` не брав його
> в ЖОДНОМУ середовищі → `RailsI18n::Railtie` не спрацьовував → локалі гема не
> доїжджали в `I18n.load_path`, і uk/lv/lt мовчки падали на англійський fallback:
> українець бачив `can't be blank`, `Sunday` і символ `$`. Присутність у
> lock-файлі **не означає завантаження** — умова саме `Bundler.require`, тож
> перевіряти треба рантаймом (`I18n.load_path.grep(/rails-i18n/)`), не грепом по
> `Gemfile.lock`.

### 12.3 Структура локалей (per-domain, не файли-портянки)

```
config/locales/
├── defaults/<locale>.yml       # app-shell: name, theme, locale-switcher, accessibility
├── components/<locale>.yml     # cross-cutting UI components
├── navigation/<locale>.yml     # sidebar, top bar, breadcrumb
├── sessions/<locale>.yml       # login screen
├── dashboard/<locale>.yml      # dashboard home
├── trees/<locale>.yml          # tree show page
├── wallets/<locale>.yml        # wallet page
├── flash/<locale>.yml          # controller flash messages
└── errors/<locale>.yml         # error JSON
```

Один домен = одна папка × **по файлу на кожну налаштовану локаль**. Nesting тримати shallow (≤ 4 рівнів). Fallback-ланцюжок (§12.2) гарантує, що частково перекладений файл не ламає UI. Додавання нового домену — повний набір файлів, `i18n-tasks missing` має лишатися зеленим.

> 🧱 **Роздрібнення локалей у цьому документі НЕ повторюється — і це навмисно.** Єдиний дім переліку — `config.i18n.available_locales` (§12.2); канон називає **правило** («по файлу на локаль»), а не **реєстр**. Причина емпірична: коли документ носив `{uk,en}`, роздрібнення застаріло мовчки при доданні lv/lt — і рецепт §16.2 почав радити створити два файли там, де HARD-гейт парності вимагає всі. Реєстр, скопійований у прозу, старіє рівно тоді, коли каталог росте, тобто саме тоді, коли на нього дивляться. Це той самий one-home-борг, що трекається [`00_07`](00_07_Action_Plan_Tracker) I18N.3 — тут він закритий тим, що дублю просто немає.

### 12.4 Resolution priority (`LocaleSettable` concern)

```
params[:locale] → cookies[:locale] → request.preferred_language → I18n.default_locale
```

Усі джерела whitelist'яться проти `I18n.available_locales` — adversarial input просто провалюється на default. Concern підмішаний у **обидва** `ApplicationController` і `Api::V1::BaseController` — інакше після POST `/api/v1/locale` + redirect Dashboard ігнорує щойно записану cookie і відкочується на `default_locale` (legacy 2-кліки-щоб-змінити-locale bug, фікснутий саме інклудом у обох контролерах).

### 12.5 LocaleSwitcher (`Views::Shared::UI::LocaleSwitcher`)

Native `<form>` + `<select>` + `onchange="this.form.requestSubmit()"` — Rails-canonical pattern. Браузер сам обробляє позиціонування, keyboard navigation, focus management та accessibility — **нуль custom JS**, **без Stimulus**, **без Popover API**. Коли JS вимкнено, `<noscript>` показує submit button — форма працює end-to-end.

```ruby
# layout
render Views::Shared::UI::LocaleSwitcher.new
```

Endpoint: `POST /api/v1/locale` → cookie `locale=<en|uk|lv|lt>` (httponly, same_site=lax, secure-in-prod), open-redirect guard перевіряє `request.host == referer.host`. Форма сабмітить `data-turbo="false"` — повний page reload гарантує, що `data-turbo-permanent` sidebar теж перерендериться новою мовою.

> **Історія еволюції (для контексту, не для повторення).** Ранні ітерації використовували `<details>`+`<summary>` + Stimulus `locale` controller (outside-click/Escape handlers), потім HTML Popover API. Popover був видалений, бо він промотує dropdown у top-layer і відриває його від нормального containing block — CSS `position: relative` на wrapper'і не може анкорити dropdown поруч з тригером без re-positioning JS (Stimulus з `getBoundingClientRect`). Це fragile (resize/scroll handlers, z-index edge cases, focus quirks) для меню з 2 опцій. Натомість нативний `<select>` — obvious correct primitive. Повний rationale-блок зафіксовано у `app/views/shared/ui/locale_switcher.rb`. Cross-ref у §15.1 (Native HTML over Stimulus) — Popover API лишається рекомендацією для майбутніх dropdown patterns, але в проекті ще не застосований.

### 12.6 Phlex `t(".key")` pattern — як додати нову локалізовану строку

```ruby
# app/views/components/wallets/show.rb
module Wallets
  class Show < ApplicationComponent
    def view_template
      h2 { t(".heading") }                          # → "wallets.show.heading"
      p  { t(".intro", balance: @wallet.balance) }  # interpolation
    end
  end
end
```

```yaml
# config/locales/wallets/en.yml
en:
  wallets:
    show:
      heading: "Wallet"
      intro: "Current balance: %{balance} SCC"
```

```yaml
# config/locales/wallets/uk.yml
uk:
  wallets:
    show:
      heading: "Гаманець"
      intro: "Поточний баланс: %{balance} SCC"
```

Cross-scope keys (потрібен ключ із сусіднього компонента) — використовуйте абсолютний `t("codex.fractions.current")`. Не вводьте `tr()` private helper — це попередній паттерн, замінений на `t(".key")` (537+ викликів у проекті vs 5 legacy `tr` визначень).

### 12.7 Pluralization

**Набір форм визначає МОВА, не ми** — CLDR-правила, а не наша домовленість. Живий
приклад у репо, `maintenance.index.photo_count` (той самий ключ, чотири файли):

```yaml
en:  { one: "1 Photo",        other: "%{count} Photos" }        # 2 форми
lv:  { one: "1 fotogrāfija",  other: "%{count} fotogrāfijas" }  # 2 форми
lt:  { one: "1 nuotrauka",    few: "%{count} nuotraukos",       # 3 форми
       other: "%{count} nuotraukų" }
uk:  { one: "1 фото", few: "%{count} фото",                     # 4 форми
       many: "%{count} фото", other: "%{count} фото" }
```

Різна кількість форм між локалями — нормально й **не валить** гейт парності:
`i18n-tasks` знає про plural-піддерева, а `check-consistent-interpolations` дивиться
на `%{}`, не на набір ключів. Обов'язок локалі — покрити форми **своєї** мови.

> ⚠️ **Правила плюралізації приходять із `rails-i18n` (§12.2) — без нього форми
> `few`/`many` НЕДОСЯЖНІ.** Дефолтний бекенд I18n знає рівно два випадки
> (`one` для `count == 1`, `other` для решти), тож українські `few`/`many` лежать
> у YAML мертвим вантажем, а `t(count: 3)` віддає `other`. Помилка тиха: ключ
> існує, гейт парності зелений, рендериться просто не та форма. Саме так воно й
> жило до 2026-07-26 — гем був у lock-файлі, але не завантажувався.
>
> Перевірка — рантайм, не греп: `I18n.t("...", count: 3, locale: :uk)` мусить
> дати САМЕ `few`-рядок. Побічний доказ, що бекенд живий:
> `I18n.t("datetime.distance_in_words.x_minutes", count: 3, locale: :uk)` →
> `"3 хвилини"` (не `"3 хвилин"`).

### 12.8 Backend localization

Усі рядки у `app/controllers/api/v1/**/*.rb` йдуть через `I18n.t`:

| Domain | YAML файл | Приклад ключа |
|---|---|---|
| Flash messages | `flash/{en,uk}.yml` | `flash.sessions.signed_in` |
| Error JSON | `errors/{en,uk}.yml` | `errors.api.forbidden` |
| Account Security | `account_security/{en,uk}.yml` | `account_security.mfa.enabled` |
| Passwords | `passwords/{en,uk}.yml` | `passwords.reset.email_sent` |
| M2M auth | `m2m_auth/<locale>.yml` | `m2m_auth.token.issued` |
| **Заголовок сторінки** | `<domain>/<locale>.yml` | `wallets.index_title` · `trees.show_title` (інтерполяція — `%{name}`/`%{uid}`/`%{id}`) |

> 🧱 **`title:` — не «рядок десь у кутку», а ім'я сторінки.** Аргумент `render_dashboard(title:)` стає ОДРАЗУ двома речами: `<title>` вкладки (а отже й запис в історії браузера) і видимий `<h1>` (`DashboardLayout`). Тому конвенція жорстка: плоский ключ `<domain>.<action>_title` (виняток — домен `codex`, який уже має власні під-скоупи й лишається на `page_title` усередині них).
>
> 🧱 **Ім'я сторінки живе в ОДНОМУ місці — `title:` контролера.** `DashboardLayout` малює його як `h1` у верхній панелі, тож компонент, який малює власний заголовок сторінки нижче, дублює ім'я — а на сторінці з ОДНІЄЮ секцією ще й дає ДВА різні імені одного екрана. Перевірка проста: якщо `h3` компонента називає ту саму сутність, що `title:`, — його місце порожнє. Якщо називає одну з кількох секцій (`oracle_visions`) або є заголовком ФОРМИ («Register Intervention Ritual» проти «New Maintenance Ritual») — лишається, це різні речі.
>
> ⚠️ **Інтерпольований заголовок мусить лишати змінну в НАЗИВНОМУ.** У ній сидить власна назва або ID, які не відмінюються, тож рамка «Профіль %{name}» у відмінюваних мовах ламається, а «Профіль // %{name}» — ні. Усі 52 мігровані заголовки тримають змінну після роздільника (`//`, `:`, `#`) саме з цієї причини.
>
> Клас стереже `spec/i18n/controller_title_literals_spec.rb`: **жодного строкового літерала одразу після `title:`** у `app/controllers/**`. Гейта на це не мав ніхто, і не випадково — `i18n-tasks` бачить лише ІСНУЮЧІ `t()`-ключі, а сирий літерал для нього не існує взагалі; `raise_on_missing_translations` теж мовчить, бо ніхто нічого не шукає. Саме тому клас доріс до 56 сайтів у 25 контролерах непоміченим.

### 12.9 Spec convention

**Базова локаль застосунку — `:en` (§12.2), тож специ рендеряться англійською без жодного хука.** Єдине, що для цього робить `spec/rails_helper.rb`, — гасить *витік*: ендпоінт `LocalesController#update` мутує `I18n.locale` глобально (thread-local), тож без скидання один POST-спек фарбував би всі наступні приклади.

```ruby
config.after { I18n.locale = I18n.default_locale }   # after, НЕ before — щоб per-example `around { I18n.with_locale(:uk) }` лишався чинним
```

Спека, що перевіряє НЕ базову локаль, обгортається в `I18n.with_locale(:uk) { … }` явно.

> ⚠️ **Назва прикладу мусить казати, що він реально пінить.** `it "… in Ukrainian by default"` з тілом `I18n.with_locale(:uk) { … }` — самосуперечність: ім'я обіцяє пін на **дефолтну поведінку**, а тіло фіксує поведінку **конкретної локалі**. Такий приклад лишиться зеленим, якщо `default_locale` завтра стане будь-чим іншим, тобто читається як сторож і ним не є. Сам дефолт пінить один рядок у `spec/requests/api/v1/locales_controller_spec.rb` — і це правильний дім для нього. (Формулювання «дефолт = `:uk`» пережило в цьому документі перемикання дефолту на `:en`; клас — той самий, що в §12.3: скопійований у прозу стан старіє мовчки.)

### 12.10 CI-гейт

`.github/workflows/ci.yml` запускає job `i18n_check`:

```bash
bundle exec i18n-tasks missing                          # ключ у одній locale, відсутній в іншій
bundle exec i18n-tasks check-consistent-interpolations  # %{var} drift між locales
bundle exec i18n-tasks check-normalized                 # YAML не у нормалізованій формі
```

Будь-який з цих → red build. Runtime safety net (test env): `config.i18n.raise_on_missing_translations = true` — будь-який spec, що проходить по missing-ключу, валить CI. ⚠️ Ця сітка **не покриває Phlex** (§12.14): `ApplicationComponent#t` для абсолютних ключів кличе голий `I18n.t`, якого цей конфіг не хукає.

Конфіг: `config/i18n-tasks.yml` (base locale `:en`, scan `app/` + `lib/`, `app/javascript` + `app/assets` excluded). **Перелік локалей там не дублюється** — деривується з `available_locales` (§12.2) через Erubi, fail-closed; шов «конфіг гейта ⟷ конфіг Rails» пінить `spec/i18n/i18n_tasks_config_spec.rb`, бо поодинці обидва боки лишаються зеленими навіть розійшовшись.

#### Політика повноти: «завершені» проти «наздоганяючих» (founder 2026-07-27)

Парність — захист, поки локалей чотири, і **блокатор онбордингу**, щойно їх більше: неповний переклад робить CI червоним, тож додати мову інкрементально стає неможливо. Розділення обов'язків:

| Клас | Обов'язок | Механізм |
|---|---|---|
| **Базова** (`en`) | ключ мусить існувати завжди | вона й є еталон diff'у |
| **Завершені** (`uk`, `lv`, `lt`) | повна парність, HARD | входять у `-l`-субсет CI |
| **Наздоганяючі** (кожна нова) | нічого; fallback легальний | не входять у `-l`, але лишаються в `locales:` |

Мова переїжджає з «наздоганяючих» у «завершені» **однією правкою `-l`-списку в CI**, коли переклад дороблено. Ключ, доданий лише в наздоганяючу локаль, гейт усе одно спіймає — зворотний diff обходить усі локалі з `locales:`, а не лише субсет.

> 🔴 **«Очевидний» шлях — пастка, і вона мовчазна.** Напрошується `ignore_missing:` з per-locale хешем (у самому гемі навіть є коментар `# ignore per locale`). Але перевірка `missing` **не передає локаль** у `ignore_pattern`, тож селектор вироджується в `/\b\b/`, матчить кожен ключ і **вимикає гейт для ВСІХ локалей одразу**, лишаючись зеленим (i18n-tasks 1.1.2; per-locale scoping реально працює лише для `ignore_eq_base`). Це рідний брат маски `ignore_inconsistent_interpolations: ['*']`, яка тут уже одного разу вимкнула цілий CI-крок: **конфіг-виключення здатне зняти гейт, не лишивши жодного сліду в його виводі.** Тому субсет — на боці CLI (`-l`), де він видимий у логах білда.
>
> Поки «завершені» = усі налаштовані локалі, прапорець `-l` **не додається**: він був би незадіяною машинерією, а незадіяний гейт-шлях ніхто не перевіряє. Політика чинна як рішення, вмикається першою ж наздоганяючою мовою. Стан → [`00_07`](00_07_Action_Plan_Tracker) I18N.3.

Запуск авто-нормалізації локально:
```bash
bundle exec i18n-tasks normalize    # сортує ключі, фіксить indent
bundle exec i18n-tasks unused       # довідково: не gated у CI (false positives від dynamic keys)
```

### 12.11 Rack deprecation: `:unprocessable_entity` → `:unprocessable_content`

Усі `render status: :unprocessable_entity` замінено на `:unprocessable_content` (RFC 9110 / Rack 3.2+). Старий символ deprecation-warning'ить і буде видалений у Rack 4.0.

### 12.12 Чек-ліст для нових компонентів

- [ ] Всі user-facing strings проходять через `t(".key")` (relative-lookup), `tr()` helper не використовувати
- [ ] YAML-ключ є в **кожній** налаштованій локалі — `i18n-tasks missing` сьогодні HARD-гейт парності по всьому каталогу (§12.10). ⚠️ Саме це й робить його блокатором онбордингу нової мови; політика «завершені проти тих, що наздоганяють» — відкрите ⚖️ [`00_07`](00_07_Action_Plan_Tracker) I18N.3, доти правило вище чинне без винятків
- [ ] ARIA-label з `t(...)` (бо screen-reader читає його)
- [ ] Зарезервовані ключі не перетинаються (`:locale`, `:scope`, `:default` — не використовувати як interpolation)
- [ ] Pluralization через `t(..., count:)` + CLDR rules (UA — 4 форми, EN — 2)
- [ ] Spec покриває обидві локалі через `I18n.with_locale(:en) { ... }` / `I18n.with_locale(:uk) { ... }`

### 12.13 Backlog: що ще не локалізовано (інкрементально)

CI-гейт ловить майбутні regressions. Класи, що лишаються нелокалізованими (пооб'єктний реєстр — [`00_07`](00_07_Action_Plan_Tracker) I18N.1, тут лише класи):
- `app/views/<mailer>/*.{erb,text.erb}` + mailer-`subject` — уся пошта мономовна **українською**, тобто навіть не `default_locale`
- `app/views/pwa/service-worker.js` — manifest + offline сторінка JS-string'и (не через Rails I18n)
- **Сирі enum'и як видимий текст** — `severity`, `action_type`, `token_type`, `status`, `AuditLog#action`, breadcrumb-сегменти: клас, який §12.14 закрив для `alert_type` і який лишається відкритим для решти
- **Проза, записана в БД сервісом** (`EwsAlert#message`, `resolution_notes`, `MaintenanceRecord#notes`, `*.error_message`) — не `t()`-заміна, а редизайн «ключ + параметри замість готового рядка»
- Окремі inline UA коментарі у `.rb` файлах — не user-facing, не блокують гейт

### 12.14 Enum-мітки: контракт «модель ↔ локаль»

Значення enum'а, показане користувачеві (`alert_type`, `status`, `action_type`), — це **мітка**, і її дім — локаль-файл, а не `case` у Ruby й не `.humanize` (останній — англійський Rails-метод: він мовчки віддає англійську в усіх чотирьох локалях).

Еталон — `EwsAlert#alert_type` (дім реалізації [`04_02`](04_02_Business_Logic_and_Services), `TreeChronicle::TextFormatter`):

```ruby
ALERT_TYPE_SCOPE = "alerts.types"        # ← ОДНА деривація ключа на застосунок

def alert_title(alert)
  type = alert.alert_type.to_s
  I18n.t("#{ALERT_TYPE_SCOPE}.#{type}", default: type.humanize)   # fail-open
end
```

Викликачі (`Alerts::Row` тощо) ходять **через цей метод**, а не будують ключ самі: дві деривації означають, що друкарська помилка в одній із них лишається зеленою назавжди.

**Скоуп належить домену МОДЕЛІ, а не компонента, який першим його показав.** Мітки `severity` спершу жили під `alerts.badge.severities` — бо `Alerts::Badge` вивів їх перший. Щойно з'явився другий викликач (`Alerts::Row`), цей шлях став брехнею про власника: значення належать `EwsAlert`, а не бейджу. Тому дім — `alerts.severities` поруч із `alerts.types`, а деривація — `TreeChronicle::TextFormatter::SEVERITY_SCOPE` + `alert_severity_label`. **Поріг простий: константа потрібна там, де викликачів ДВА і більше** — доти локальний `t(".key")` чесний і дешевший (саме тому `alerts.badge.statuses` свідомо лишився на місці: викликач один).

> ⚠️ **Сире значення enum'а, інтерпольоване в ПЕРЕКЛАДЕНЕ речення, — гірший різновид промаху, ніж просто сирий текст.** Фраза виглядає локалізованою, тож при вичитці її пропускають: `t(".threat", type: @event.alert_type)` давало «⚠ Загроза: fire_detected у Карпати-7». Той самий підвид — англійський `aria_label`, зібраний із перекладеного шаблону й сирого значення: скрін-рідер читає англійський токен усередині української фрази, а очима це не видно взагалі. Обидва випадки шукаються не по `.humanize`, а по інтерполяції атрибута моделі в `t(...)`.

**Locale-інваріантні значення (емодзі, гліфи) у YAML НЕ кладуться.** `i18n-tasks missing` — HARD-гейт парності, тож один емодзі перетворився б на по копії в **кожній** локалі каталогу, які перекладач може «виправити». Аргумент масштабується в гірший бік: чим більше локалей, тим дорожча помилка. Їхній дім — заморожена Ruby-мапа поруч зі scope-константою.

**Гейт свідомо перевіряє ЛИШЕ базову локаль — і саме тому масштабується.** Вартість перевірки не залежить від розміру каталогу локалей, а нова локаль із ще-порожнім YAML **не робить спеку червоною**: fallback-ланцюг (§12.2) віддає базову мітку, UI лишається справним. Обов'язок «мати мітку» лежить на базовій локалі, обов'язок «наздогнати переклад» — на самій локалі. Це поділ, який тримає і на чотирьох мовах, і на ста п'ятдесяти.

> ⚠️ **Чого CI тут НЕ бачить — і чому вісь тримає спека.** `i18n-tasks missing` звіряє **локаль з локаллю** і структурно сліпий до «enum виріс, YAML лишився» (саме так `alert_type` доріс до 14 значень, поки формат знав 9). `raise_on_missing_translations` (test-env) **не покриває Phlex**: `ApplicationComponent#t` для абсолютних ключів кличе голий `I18n.t`, якого цей конфіг не хукає. А `default:` глушить залишок. Тож вісь «джерело значень → базова локаль» тримають **лише спеки**, і вона двобічна: «немає мітки для значення» ⊕ «є мітка без значення». Другий бік важливіший, бо **не має симптомів** — зайвий рядок просто ніколи не читається (так `alerts.badge.severities.high` прожив у всіх чотирьох локалях, хоч `EwsAlert.severity` = low/medium/critical).
>
> Дім осі — `spec/i18n/enum_label_parity_spec.rb`: **курована мапа як tripwire**, по рядку на пару «джерело → скоуп» (`alert_type`, `severity`, `status`, `ActuatorCommand#status`, `StatusBadge::STYLES`). Новий user-visible enum додає рядок туди; **мертвий рядок мусить червоніти** — окрема перевірка ловить нерезолвний скоуп і порожнє джерело, інакше «0 порушень» означало б «0 перевірок». `text_formatter_parity_spec` лишається при своєму: icon-мапа + пін «резолвиться через YAML, не через `humanize`-фолбек».
>
> 🔒 Стеля обох спек названа в їхніх шапках: перевіряється **лише базова локаль** (ціна не росте з каталогом) і **лише зареєстровані пари** — enum, що рендериться сирим і скоупа не має взагалі, гейт не бачить; і жодна з них не перевіряє, що викликач ходить ЧЕРЕЗ спільну константу.
>
> ⚠️ **`I18n.exists?` у такій спеці — ОБОВ'ЯЗКОВО з `fallback: false`.** `config.i18n.fallbacks` (§12.2) діє в **усіх** середовищах, тож без прапорця порожня `lv` «існує» через `en`, і перевірка мовчки стає вакуумною на трьох локалях із чотирьох.
>
> ⚠️ **`check-normalized` завжди виходить з нульовим кодом** (upstream-quirk) — CI гейтить грепом по виводу (`ci.yml`). Локально перевіряй так само, exit-code тут нічого не доводить.

---

## 13. Mobile Drawer (Phase 2)

> Off-canvas mobile-only sidebar drawer з backdrop, scroll-lock,
> focus-trap, Escape-to-close. Сумісний з `prefers-reduced-motion`
> через motion tokens.

### 13.1 Архітектура

| Шар | Файл | Відповідальність |
|---|---|---|
| Trigger | `Views::Shared::UI::MobileNavToggle` | Бургер-кнопка `<button>` (mobile-only, `md:hidden`) |
| Drawer | `DashboardLayout#render_mobile_drawer` | `<aside role="dialog">` slide-in panel + `<div>` backdrop |
| Behaviour | `app/javascript/controllers/mobile_nav_controller.js` | open/close, scroll-lock, focus-trap, Escape, Turbo-visit close |

### 13.2 Поведінка

- **Open/close** — translate-x-full ↔ translate-x-0 (CSS transform, GPU).
- **Backdrop** — `bg-black/60` + `opacity-0 ↔ opacity-100`, fade-in.
- **Scroll-lock** — `body.style.overflow = "hidden"` поки drawer відкритий.
- **Focus management:**
  - на open → фокус на перший focusable у drawer
  - на close → фокус повертається на trigger (WCAG 2.4.3)
  - Tab/Shift+Tab закільцьовуються всередині drawer (focus-trap)
- **Escape** → close.
- **Backdrop click** → close.
- **Turbo `turbo:visit`** → close (щоб наступна сторінка не успадкувала open-state).

### 13.3 Адаптивність

| Viewport | Sidebar | Toggle |
|---|---|---|
| `< md` (mobile) | Hidden, відкривається через drawer | Visible (`md:hidden`) |
| `≥ md` (tablet+) | Static visible (`hidden md:block`) | Hidden |

Десктопний sidebar — Turbo-permanent (не перерендериться між сторінками).
Мобільний drawer — звичайний рендер (стан синхронізується JS-ом).

---

## 14. Animations & Motion (Phase 3)

> Узагальнена motion-система побудована поверх токенів з § 4 (motion tokens).
> WCAG 2.3.3 / Web Vitals friendly — усі анімації автоматично вимикаються
> під `prefers-reduced-motion: reduce`.

### 14.1 Fluid base typography

`@layer base` тепер використовує `clamp()` для `<h1..h3>`, замість фіксованих
rem-розмірів. Заголовки масштабуються плавно між мобайлом і десктопом без
`@media`-сходинок. Зніжує CLS до нуля при зміні vw.

```css
h1 { font-size: clamp(1.5rem,  2.5vw + 0.75rem, 1.875rem); }
h2 { font-size: clamp(1.25rem, 1.6vw + 0.5rem,  1.5rem);   }
h3 { font-size: clamp(1.125rem, 1vw + 0.5rem,   1.25rem);  }
```

Для page-level hero-заголовків — використовуйте `text-display-*` токени
(`display-sm/md/lg`, див. § 4) явно через клас.

### 14.2 View Transitions API (Theme Switcher)

`theme_controller.toggle()` обгортає зміну `.dark` класу у
`document.startViewTransition()`. Браузер робить плавний crossfade між
світлою і темною темами — без DOM-flicker, без необхідності CSS-transitions
на кожному елементі.

```js
if (typeof document.startViewTransition === "function") {
  document.startViewTransition(() => this.applyTheme(next))
} else {
  this.applyTheme(next)  // fallback для старих браузерів
}
```

CSS у `application.css`:
```css
::view-transition-old(root),
::view-transition-new(root) {
  animation-duration: var(--motion-base, 220ms);
  animation-timing-function: var(--ease-out-soft, ease-out);
}
```

Підтримка: Chromium 111+, Safari 18+. Fallback — миттєвий apply
(існуюча поведінка). API сам поважає `prefers-reduced-motion`.

### 14.3 `reveal_controller` (appear-on-scroll)

> **Наразі без консюмерів** — референс-патерн; жоден view не ставить `data-controller="reveal"` (§ 15.2).

Stimulus controller, який скидає `opacity-0 translate-y-2` коли елемент
вперше з'являється у viewport. One-shot (`unobserve` після першого спрацювання).

```html
<article data-controller="reveal"
         class="opacity-0 translate-y-2 transition-all
                duration-[var(--motion-slow)] ease-[var(--ease-out-soft)]">
  ...
</article>
```

Поведінка:
- **`prefers-reduced-motion: reduce`** → reveal негайно, observer не створюється
- **No IntersectionObserver** (старі браузери) → reveal негайно
- **Поріг видимості:** 15% (тюниться через `data-reveal-threshold-value`)
- **Root margin:** `0px 0px -10% 0px` — спрацьовує трохи раніше за повний enter

### 14.4 Анімаційний бюджет

| Тип | Тривалість | Easing | Приклад |
|---|---|---|---|
| Hover/focus | `--motion-fast` (150ms) | `--ease-out-soft` | LocaleSwitcher hover |
| UI transitions | `--motion-base` (220ms) | `--ease-out-soft` | Mobile drawer slide-in, theme crossfade |
| Page entrance | `--motion-slow` (320ms) | `--ease-out-soft` | `reveal_controller` |
| Micro-bounces | `--motion-base` | `--ease-spring` | Badge "new!" pop, error shake |

> Не плодьте кастомні durations / easings — використовуйте токени.

---

## 15. Native HTML over Stimulus (де доречно)

> **Filozofia:** використовуй Web Platform де він уже дозрів — це менше JS,
> менше bugs, краща a11y "з коробки", forward-compatible. Stimulus залишай
> для речей, де нативу або немає, або він ще не Baseline.

### 15.1 Що використовуємо нативно (без JS)

| Нативний API | Що дає | Замість чого | Підтримка |
|---|---|---|---|
| **HTML Popover API** (`popover="auto"`, `popovertarget`) | Outside-click close, Escape close, top-layer стек, focus restore | Рекомендований default для нових dropdown / menu / tooltip patterns; **у проекті ще не застосований** — `locale_controller` був видалений, але locale switcher використовує нативний `<select>` (top-layer detachment Popover ламав CSS anchor positioning для 2-опцій-кейсу, див. §12.5) | Baseline 2024 — Chromium 114+, Safari 17+, Firefox 125+ |
| **`<dialog>` + `.showModal()`** | Focus-trap, Escape, top-layer, `::backdrop`, inert page below, focus restore | Manual focus-trap код у `mobile_nav_controller` (~150→~25 рядків) | Baseline 2022 — всі evergreen |
| **`@starting-style` CSS** | "From"-frame для transition без JS-flush reflow | Manual rAF в JS | Baseline 2024 |
| **View Transitions API** (`document.startViewTransition`) | Smooth crossfade між DOM-станами | Manual CSS transitions на кожному елементі | Chromium 111+, Safari 18+ (graceful fallback) |
| **`prefers-reduced-motion`** (CSS) | Глобально вимикає анімації | JS feature-detection у кожному компоненті | Baseline |
| **`<details>` / `<summary>`** | Disclosure pattern + keyboard | Custom accordion JS | Baseline |

### 15.2 Що залишилось у Stimulus (виправдано)

| Controller | Чому не нативно |
|---|---|
| `theme_controller` | Stateful: localStorage + system preference listener + View Transitions wrapper + icon swap target. Це класичний Stimulus use-case. |
| `mobile_nav_controller` (тонкий шим) | Native `<dialog>` не закривається на backdrop-click + scroll-lock у Safari через `.showModal()` не завжди — лишаємо ~25 рядків шіма. |
| `reveal_controller` ⚠️ | CSS `animation-timeline: view()` ще НЕ Baseline (Safari/Firefox в роботі) — IntersectionObserver лишається оптимальним до ~2027. **Наразі 0 консюмерів** (`data-controller="reveal"` ніде) — scaffold-патерн задокументовано (§ 14.3), але ще не застосовано (дзеркало Popover-чесності § 15.1). |
| `clipboard_controller`, `map_controller`, `matrix_rain_controller`, `codex/*` | Інтеграція з 3rd-party / Canvas / складна логіка. |

### 15.3 Чек-ліст: коли можна **не** писати Stimulus controller

Перш ніж писати новий Stimulus controller — пройдіть цей список. Якщо
**будь-яке** "так" — спробуйте нативний шлях:

- [ ] Це dropdown / menu / tooltip → **HTML Popover API** (`popover="auto"`)
- [ ] Це modal / dialog / sheet / off-canvas drawer → **`<dialog>`** + `.showModal()`
- [ ] Це collapsible accordion → **`<details>`** з опційним `name="..."` для exclusive
- [ ] Це form submission з UI feedback → **Turbo Forms** + Turbo Stream response
- [ ] Це validation помилки → **Constraint Validation API** + `:user-invalid` CSS
- [ ] Це date/time picker → **`<input type="date">`**, **`type="time">`**
- [ ] Це color picker → **`<input type="color">`**
- [ ] Це search з autocomplete → **`<input list>` + `<datalist>`**
- [ ] Це auto-resize textarea → **`field-sizing: content`** CSS (Baseline 2024)
- [ ] Це smooth scroll / scroll-snap → **`scroll-behavior: smooth`** + `scroll-snap-*`
- [ ] Це responsive container — →  **CSS container queries** `@container`

Якщо **жодне** не підходить — Stimulus це нормальний вибір.

---

## 16. Codemod-Driven Migration (Phase 4)

> Page-component migration from raw Tailwind to gaia tokens is automated
> through a deterministic Ruby codemod. The migration is **incremental**:
> each PR migrates a domain (trees / wallets / alerts / …), the codemod
> guarantees consistent mapping, and the CI lint task prevents regressions.

### 16.1 Tooling

| Tool | Purpose |
|---|---|
| `bin/migrate-tailwind-tokens` | Word-boundary `gsub` codemod with `--dry-run` and `--report` modes. Mapping table mirrors § 3.1 (4-tier surfaces + 3-level text + primary tokens). |
| `bundle exec rake gaia:lint_tokens` | **Локальна** compliance-перевірка — `exit 1`, якщо в `app/views/components/` знайдено сиру Tailwind-утиліту кольору; brand-glow allowlist усередині (див. джерело). ⚠️ **НЕ підключена до `.github/workflows/`** (нуль згадок), тож правило документоване, а не enforced — стан і робота живуть у [`00_07`](00_07_Action_Plan_Tracker) UI.1. Дзеркалить чесне формулювання у ✅ Статус вище; попереднє «CI-grade» суперечило власному Статусу того ж документа. |

### 16.2 Migration workflow per domain

```bash
# 1. preview
bin/migrate-tailwind-tokens --dry-run app/views/components/wallets/

# 2. apply
bin/migrate-tailwind-tokens app/views/components/wallets/

# 3. add i18n — по файлу на КОЖНУ налаштовану локаль (перелік: available_locales, §12.2).
#    Створювати підмножину = червоний `i18n-tasks missing` (§12.10).
mkdir -p config/locales/wallets
for f in config/locales/defaults/*.yml; do touch "config/locales/wallets/$(basename "$f")"; done
# … use t(".key") in each component (see § 12.6)

# 4. update specs
# базова локаль = :en, тож англійські assertions працюють без обгортки (§12.9)
# перевіряєш ІНШУ локаль — явний `I18n.with_locale(:uk) { … }`, і назви приклад по локалі, не «by default»

# 5. verify
bundle exec rspec spec/views/components/wallets/
COMPONENTS=app/views/components/wallets/ bundle exec rake gaia:lint_tokens
```

### 16.3 Mapping table (codemod)

| Raw Tailwind | Gaia token | Notes |
|---|---|---|
| `bg-black`, `bg-white` | `bg-gaia-surface` | Card / panel base |
| `bg-gray-50` | `bg-gaia-surface-base` | Page background |
| `bg-gray-100`, `bg-emerald-950/{10,20}` | `bg-gaia-surface-sunken` | Inset rows / hover backdrop |
| `bg-gray-900` | `bg-gaia-surface-elevated` | Modal / popover surface |
| `border-gray-200`, `border-emerald-900` | `border-gaia-border` | Default panel border |
| `border-gray-300`, `border-emerald-{700,800,900}/50` | `border-gaia-border-strong` | Hover/focus border |
| `text-gray-900`, `text-white` | `text-gaia-text-strong` | Headings, primary copy |
| `text-gray-700`, `text-emerald-400` | `text-gaia-text` | Body |
| `text-gray-{500,600}`, `text-emerald-700` | `text-gaia-text-muted` | Labels, captions |
| `text-gray-{300,400}`, `text-emerald-{800,900}` | `text-gaia-text-subtle` | Watermarks, placeholders |
| `text-emerald-500` | `text-gaia-primary` | Brand accent |
| `text-emerald-600` | `text-gaia-primary-hover` | Brand hover |

### 16.4 Allowlist — what stays raw on purpose

Brand-glow / decorative Tailwind utilities never go through the codemod:

- `bg-emerald-500/10`, `bg-emerald-500/20` — login submit + impedance bar fill
- `bg-emerald-500` (with `animate-ping` / `animate-pulse`) — pulse accents
- `border-emerald-500/20` (with `animate-spin`) — spinner ring

These encode brand expression, not theme intent — leave them alone.

### 16.5 i18n locale-file convention

```
config/locales/
├── defaults/      # app-shell, accessibility, theme, locale-switcher
├── components/    # cross-cutting UI components
├── navigation/    # sidebar, top bar, breadcrumb
├── sessions/      # login screen
├── dashboard/     # dashboard home
└── trees/         # tree show page
```

Each domain = one folder × two files (`uk.yml` + `en.yml`). Keep nesting
shallow (≤ 4 levels). See § 12.2 — same rules for new domains.

---

## 17. Responsive Tables — CSS-only Card Flip (Phase 5)

> Tables that work as a real `<table>` on desktop and become a stack of
> labelled cards on mobile — without JS, without dual-render, without
> losing semantics. Pattern crystallised in Phase 5 to ship `Alerts::Index`
> and `Telemetry::LiveStream` to mobile users without breaking Turbo
> Streams or screen readers.

### 17.1 Why not JavaScript?

Three options were evaluated:

| Option | Verdict |
|---|---|
| **Heavy refactor on `DataTable` shared component** with `mobile_layout:` prop | Rejected — `DataTable` is orphan (only one consumer, and it bypasses the component). Would require rewriting Turbo-Stream wiring + bulk citation lookup. |
| **JS-driven dual-render** (Stimulus controller swaps markup) | Rejected — duplicates the source of truth, ships extra JS, breaks `prefers-reduced-motion` simplicity, fights Turbo Stream row replace. |
| **CSS-only flip via `attr(data-label)`** ✅ | Single semantic HTML, 0 JS, 0 new components, screen reader friendly, Turbo Streams keep working unchanged. |

The chosen pattern is documented in [A11Y Project — Accessible Data Tables](https://www.a11yproject.com/posts/accessible-data-tables/) and Heydon Pickering's *Inclusive Components* (Responsive Tables chapter).

### 17.2 Markup contract

```ruby
# Wrap any <table> with `gaia-responsive-table`. Mark <thead> with
# `gaia-sticky-thead` for sticky headers on desktop. Each <td> gets
# `data-label` matching its column header — that becomes the visible
# label on mobile.
table(class: "gaia-responsive-table w-full text-left font-mono", role: "table") do
  thead(class: "gaia-sticky-thead bg-gaia-surface-sunken text-gaia-text-subtle uppercase") do
    tr do
      th(scope: "col", class: "p-4") { t("table.severity") }
      # …
    end
  end
  tbody do
    @alerts.each do |alert|
      tr do
        td(class: "p-4", data_label: t("table.severity")) { severity_badge }
        # …
        # Action cells WITHOUT data_label collapse into a centred footer
        # block on mobile (no duplicate column heading).
        td(class: "p-4 text-right") { action_button }
      end
    end
  end
end
```

CSS lives in `app/assets/tailwind/application.css` § "Responsive Table Pattern".

### 17.3 What changes on mobile (`< 768px`)

- `<thead>` is **visually hidden** (clip-path), not removed — assistive tech in browse mode still sees the real table.
- Each `<tr>` becomes a bordered card (`bg-gaia-surface`, `border-gaia-border`).
- Each `<td>` becomes a flex row with `attr(data-label)` rendered via `::before` as the left-side label and the cell value on the right.
- Cells without `data-label` (action buttons) become centred footer blocks.
- The `md:min-w-[640px]` and `md:overflow-x-auto` classes on the wrapper drop the horizontal-scroll fallback on mobile so the card layout occupies full width.

### 17.4 Sticky-bottom pagination on mobile

Pair the responsive table with `Views::Shared::UI::Pagination.new(sticky_mobile: true)` to stick prev/next to the bottom of the viewport on mobile, honouring iOS notch / Android gesture bar via `env(safe-area-inset-bottom)`.

```ruby
render Views::Shared::UI::Pagination.new(
  pagy: @pagy,
  url_helper: ->(page:) { api_v1_alerts_path(page: page) },
  sticky_mobile: true   # adds `gaia-pagination-sticky` CSS class
)
```

### 17.5 i18n

The mobile labels come from `data-label`, which itself is i18n'd through the standard `t("table.severity")` helper. Switch `:en` ↔ `:uk` and the card labels switch with the desktop column headers — no parallel translation surface.

---

## 18. Industry Standards (SSOT) + Per-PR Definition of Done

> Перенесено з тимчасового `docs/plans/frontend_overhaul_plan.md` (Phase 6,
> retire-plan consolidation; сам файл видалено після переїзду evergreen-знань).
> Розділ — SSOT для рев'юверів: кожен фронтенд-PR
> посилається на конкретний пункт замість винаходу власних правил.

### 18.1 Accessibility — WCAG 2.2 AA + WAI-ARIA 1.2

- **Контрастність:** мінімум 4.5:1 для тексту, 3:1 для UI-елементів та non-text. Перевіряємо обидві теми (light + dark) через Lighthouse / axe DevTools.
- **Focus visible:** `focus-visible:ring-2 focus-visible:ring-gaia-primary` на всіх інтерактивних елементах (canon WCAG 2.4.7).
- **Reduced motion:** глобальний `@media (prefers-reduced-motion: reduce)` у `application.css` — § 14.4.
- **Semantic landmarks:** `<header role="banner">`, `<nav role="navigation">`, `<main role="main">`, `<aside>`, `<footer role="contentinfo">`.
- **ARIA patterns:** офіційний APG (Authoring Practices Guide) для menu, dialog, disclosure. `LocaleSwitcher` — нативний `<select>` з auto-submit (`onchange` → `requestSubmit`), sr-only `<label>` + `aria-label` (без Popover/Stimulus — § 12.5).
- **Keyboard nav:** Escape, Tab order, focus-trap (для drawer — забезпечується нативним `<dialog>.showModal()`, § 13.1).
- **Touch targets:** мінімум 24×24 CSS px (WCAG 2.5.8), цільовий 44×44 (Apple HIG) для primary actions.
- **Responsive tables:** `data-label` per `<td>` + `gaia-responsive-table` CSS — § 17 — зберігає семантику для AT, доступний на mobile.

### 18.2 Internationalization — Rails I18n + Unicode CLDR

- **Файлова структура** за доменом (`config/locales/<domain>/<locale>.yml`) — Rails Guide "Lazy Lookup" pattern, § 12.3.
- **Pluralization:** `t(..., count:)` + CLDR rules (UA — 4 форми: one/few/many/other; EN — one/other).
- **Інтерполяція:** ніяких зарезервованих ключів (`:locale`, `:scope`, `:default`).
- **`<html lang>`:** SEO + screen readers (W3C HTML 5.2). Виставляється у `dashboard_layout`/`auth_layout` через `I18n.locale`.
- **No hardcoded strings** у view-shared компонентах — `bin/migrate-tailwind-tokens` + `t(".key")` lazy-lookup pattern (§ 12.5).
- **Locale = `uk`, не `ua`** — ISO-639-1 (§ 12.1).

### 18.3 Security — OWASP ASVS L2 + GitHub Security

- **CSRF:** Rails default `protect_from_forgery` — `LocaleSwitcher` submit це звичайна form з authenticity token.
- **Open-redirect guard:** `LocalesController#sanitized_referer` валідує `request.host == referer.host`.
- **Cookie flags:** `httponly: true`, `same_site: :lax`, `secure: production?`.
- **CSP:** дотримуємося існуючої політики (`csp_meta_tag`); inline-стилі заборонені.
- **HSTS / X-Frame-Options:** Rails defaults.
- **Dependency scanning:** GitHub Dependabot + `bundle audit` + `gh-advisory-database` на кожен PR (DoD § 18.9).
- **Secret scanning:** GitHub native secret-scanning + push-protection (у CI).

### 18.4 Performance — Google Web Vitals + Core Performance budgets

- **LCP < 2.5 s** на 4G/Slow Mobile — fluid `clamp()` typography уникає CLS-перерозкладок при зміні vw (§ 14.1).
- **CLS < 0.1** — `Skeleton` варіанти займають той самий простір, що й контент.
- **INP < 200 ms** — Stimulus controllers без важких synchronous блоків; `matrix-rain` throttle ~16 fps (`requestAnimationFrame`).
- **Lazy-load** через Turbo Frames `loading: :lazy` для дорогих фрагментів (Wallet balance/metadata).
- **Resource hints:** `<link rel="preconnect">` для CDN тайлів Leaflet (CartoDB).
- **Bundle budget:** importmap (no bundler) — кожен Stimulus controller ≤ 5 KB gzipped (manual budget).

### 18.5 Design tokens — W3C DTCG + Material 3 + Tailwind v4

- Naming convention `--<group>-<role>-<modifier>` (наприклад `--gaia-text-strong`) — узгоджено з W3C Design Tokens Community Group draft.
- Tier-1 (raw colors) → Tier-2 (semantic tokens) — у нас лише Tier-2 (semantic), що відповідає Material 3 "system tokens".
- Surface elevation (4-tier: `base` / `surface` / `elevated` / `sunken`) — Material 3 "elevation tokens" (§ 3.1).
- SSOT для токенів — `@theme` блок у `app/assets/tailwind/application.css`. `tailwind.config.js` не існує (§ 3).

### 18.6 Code quality — Google Style Guide + GitHub Engineering

- **Convention over configuration:** Phlex namespacing віддзеркалює routes (Rails-way).
- **Small PRs / atomic commits:** Conventional Commits (`docs:`, `feat:`, `fix:`, `refactor:`, `test:`, `chore:`) — DORA "small batch size".
- **Code review:** `parallel_validation` (Code Review + CodeQL) перед merge.
- **Comments:** "explain why, not what" (Google C++ Style Guide §3.5). Уникаємо tautological comments.
- **Naming:** Ruby — `snake_case`, Phlex class — `CamelCase` з namespace, Stimulus controller — `kebab-case` файл + `camelCase` target/values.

### 18.7 DORA metrics — DevOps Research & Assessment

- **Deployment frequency:** фази → окремі PR-и (≥ 1 на фазу) — досягнуто.
- **Lead time for changes:** малий surface → швидкий review.
- **Change failure rate:** `parallel_validation` + CodeQL + повний RSpec прогін перед merge.
- **MTTR:** Sentry DSN підключено через `.kamal/secrets-common` → стек-трейси в production.

### 18.8 Rails-specific — Rails Doctrine + The Rails Way

- **Convention over Configuration:** `LocaleSettable` — concern, не базовий клас.
- **Beautiful code over the easy code:** малі methods у Phlex (`render_summary`, `render_menu`, `render_option`).
- **Optimize for programmer happiness:** Phlex API natural Ruby vs ERB strings.
- **Push complexity downwards:** `I18n.t` у view, не у controller; cookie writing у controller, не у model.

### 18.9 Per-PR Definition of Done (фронтенд-зміни)

Кожен PR із змінами у `app/views/` має у description checklist:

- [ ] WCAG AA contrast verified у обох темах (axe DevTools / Lighthouse), мінімум 4.5:1 для тексту
- [ ] Keyboard reachable — Tab + Escape, focus order логічний
- [ ] `prefers-reduced-motion` поважається (без важких decorative animations при reduce)
- [ ] `focus-visible:ring-2 focus-visible:ring-gaia-primary` на нових інтерактивних елементах
- [ ] No hardcoded EN/UK strings у `app/views/components/` чи `app/views/shared/` — `t(".key")` lazy-lookup
- [ ] Cookie flags `secure / httponly / same_site` встановлені де писали cookie
- [ ] No open-redirect — `referer` валідується проти `request.host`
- [ ] Conventional Commit message (`feat(scope):` / `fix(scope):` / `docs(scope):`)
- [ ] `bundle exec rubocop && bundle exec rspec spec/views/ spec/requests/<changed>` зелено
- [ ] `bundle exec rake gaia:lint_tokens` зелено для торкнутих файлів (§ 16)
- [ ] `parallel_validation` (Code Review + CodeQL) пройшов або addressed

Sandbox-обмеження: автоматичний прогін axe-core / Lighthouse у CI потребує headless Chromium з мережевим доступом. Поки що це **manual gate** для рев'ювера. Коли `cuprite` тести отримають axe-runner — переведемо у автомат і відмітимо чек-бокс програмно.

### 18.10 Authoring micro-conventions (Phlex + Tailwind)

Дрібні, але обов'язкові правила написання розмітки (доповнюють §3.5 кольори / §4 типографіку / §9 a11y):

- **Без `@apply` у Phlex** — композиція класів лише Ruby (`tokens()` + приватні методи), не CSS-`@apply`.
- **`gap-*` замість `space-x/y`** у flex/grid контейнерах.
- **`grid` для 2D-розкладок, `flex` для 1D.**
- **Порядок класів:** Layout → Spacing → Type → Visual → Interactive (стабільний read/diff).
- **Довгі рядки класів** — виносити у приватні методи компонента, особливо у shared/ui (не inline-портянки).
- **SVG — `stroke="currentColor"`** (успадковує колір тексту → працює з токенами/темами).
- **`tracking-widest`** для uppercase-міток; **`leading-tight`** для заголовків.
- **`group` / `group-hover:`** для вкладених hover-взаємодій (PhotoCard, Sidebar).

