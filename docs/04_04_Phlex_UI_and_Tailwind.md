# 04_04: Phlex UI & Tailwind (SSOT Дизайн-Системи)

## 🎯 Мета

Зафіксувати повну специфікацію дизайн-системи Gaia 2.0 як Єдине Джерело Істини (SSOT). Документ описує **Phlex-компоненти**, **Tailwind CSS токени**, **Stimulus-контролери**, **Turbo-інтеграцію** та правила доступності. Слугує єдиним авторитетним джерелом для всіх UI-рішень в межах Rails 8.1 моноліту.

## ✅ Статус

- **Поточний TRL:** TRL 8 — Дизайн-система відповідає SSOT. Потребує production verification.
- **Стек:** Rails 8.1 · Phlex · Tailwind CSS 4 · TailwindMerge · Stimulus · Turbo 8
- **Пов'язані модулі:**
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - REST API → [`04_03_REST_API_v1_Reference`](04_03_REST_API_v1_Reference)
  - Моделі → [`04_01_Data_Models_and_Entities`](04_01_Data_Models_and_Entities)
  - Прошивка → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)

---

## Зміст

1. [Огляд Архітектури](#1-огляд-архітектури)
2. [ApplicationComponent — Базовий Клас](#2-applicationcomponent--базовий-клас)
3. [Tailwind Дизайн-Токени](#3-tailwind-дизайн-токени)
4. [Шкала Типографіки](#4-шкала-типографіки)
5. [TailwindMerge та патерн `tokens()`](#5-tailwindmerge-та-патерн-tokens)
6. [Реєстр Компонентів](#6-реєстр-компонентів)
   - [Спільні UI Примітиви](#61-спільні-ui-примітиви-appviewssharedui)
   - [Спільні IoT Компоненти](#62-спільні-iot-компоненти-appviewssharediot)
   - [Спільні Web3 Компоненти](#63-спільні-web3-компоненти-appviewssharedweb3)
   - [Доменні Компоненти](#64-доменні-компоненти-appviewscomponents)
7. [Stimulus Контролери](#7-stimulus-контролери)
8. [Інтеграція Turbo (Streams & Frames)](#8-інтеграція-turbo-streams--frames)
9. [Чекліст Доступності](#9-чекліст-доступності)
10. [Тестування та Lookbook](#10-тестування-та-lookbook)

---

## 1. Огляд Архітектури

Gaia 2.0 використовує підхід **Ruby-first, utility-CSS**: всі в'юшки — це Phlex Ruby-класи (без `.erb` шаблонів для доменної логіки), стилізовані виключно Tailwind utility-класами, об'єднаними без конфліктів через TailwindMerge.

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
            └─► render_auth_page(title:, component:)
                    └─► render AuthLayout.new(content: component)
                            └─► AuthLayout.view_template
                                    └─► render @content  ← Auth Component (Sessions::New, Errors::NoOrganization, etc.)
```

> **⚠️ Важливо:** Content component передається як параметр `content:` — **НЕ через блок**.
> Ruby closure блоку виконується в контексті контролера, тому `render` всередині блоку
> викликає `ActionController::API#render` (DoubleRenderError), а не `Phlex::HTML#render`.

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

  CUSTOM_TEXT_SCALE = %w[micro mini tiny compact].freeze

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

| Токен | Tailwind Клас | Light `#` | Dark `#` | Призначення |
|---|---|---|---|---|
| `--color-gaia-surface` | `bg-gaia-surface` | `#ffffff` | `#000000` | Фон карток, панелей, форм |
| `--color-gaia-surface-alt` | `bg-gaia-surface-alt` | `#f3f4f6` | `#0a0a0a` | Заголовки таблиць, вторинні панелі |
| `--color-gaia-text` | `text-gaia-text` | `#111827` | `#10b981` | Основний текст |
| `--color-gaia-text-muted` | `text-gaia-text-muted` | `#6b7280` | `#065f46` | Мітки, метадані, плейсхолдери |
| `--color-gaia-primary` | `text-gaia-primary` / `bg-gaia-primary` | `#10b981` | `#10b981` | Бренд-emerald (однаковий в обох режимах) |
| `--color-gaia-primary-hover` | `hover:bg-gaia-primary-hover` | `#059669` | `#34d399` | Hover основної кнопки |
| `--color-gaia-border` | `border-gaia-border` | `#e5e7eb` | `rgba(16,185,129,0.2)` | Межі, роздільники |

> **Legacy-кольори `gaia-green`, `gaia-dark`, `gaia-muted` видалені.** `--color-gaia-green`, `--color-gaia-dark`, `--color-gaia-muted` було видалено з `@theme` блоку `application.css` (Sprint 1, S1.7). Аудит підтвердив: жоден компонент їх не використовував — вони були присутні лише як визначення без відповідних utility-класів у коді. Семантичні токени `gaia-primary`, `gaia-text-muted`, `gaia-text` залишаються.

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

> ¹ px-значення розраховані при root font-size = 16px (стандарт браузера). Оскільки токени задані у `rem`, вони масштабуються разом з налаштуваннями доступності браузера.

Стандартні розміри Tailwind продовжують застосовуватись для більшого тексту (наприклад, `text-xs`, `text-sm`, `text-2xl`) — вони співіснують з кастомною шкалою. Кастомні токени зокрема усувають довільні значення на кшталт `text-[9px]` для розмірів менших за `text-xs`.

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
| `pending`, `issued`, `dormant`, `maintenance_needed` | `bg-status-warning text-status-warning-text` |
| `processing`, `triggered`, `updating` | `+ animate-pulse` |
| `manual_review` | `bg-status-warning text-status-warning-text + animate-pulse` — **[DOUBLE-SPEND GUARD]**: tx_hash існує або стан невідомий, потребує ручної звірки |
| `confirmed`, `fulfilled` | `bg-status-success text-status-success-text` |
| `sent`, `paid`, `maintenance` | `bg-status-info text-status-info-text` |
| `failed`, `active` (EwsAlert), `breached`, `deceased`, `faulty` | `bg-status-danger text-status-danger-text` |
| `acknowledged` | `bg-status-active text-status-active-text` |
| `idle`, `draft`, `expired`, `offline`, `resolved`, `cancelled`, `removed` | `bg-status-neutral text-status-neutral-text` |
| `ignored` | `bg-status-neutral text-status-neutral-text opacity-30 line-through` |
| `resolved`, `cancelled`, `removed` | `+ opacity-50` (застосовується через модифікатор) |

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
| `Navigation::Sidebar` | `navigation/sidebar.rb` | `current_path:`, `ews_alert_count:` | Повна навігаційна бічна панель з 4 групами секцій (Strategic, Forest Ops, Neural Network, Administration), виділенням активного стану, бейджем EWS-сигналів, пульсуючим статусом |

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
| `Firmwares::Index` | `firmwares/index.rb` | `firmwares:`, `pagy:` | Список прошивок |
| `Firmwares::New` | `firmwares/new.rb` | — | Форма завантаження нової прошивки |
| `Firmwares::Form` | `firmwares/form.rb` | `firmware:` | Поля форми прошивки |
| `Firmwares::Row` | `firmwares/row.rb` | `firmware:` | Один рядок списку прошивок |
| `Firmwares::OtaProgressBar` | `firmwares/ota_progress_bar.rb` | `uid:`, `percent:`, `current:`, `total:`, `status:` | Анімований прогрес-бар OTA; Turbo target `ota_progress_{uid}` |

#### Інші Доменні Компоненти

| Простір імен | Компоненти | Ключові Props |
|---|---|---|
| `Alerts` | `Index`, `Row`, `Badge` | `alert:` (матриця severity × status) |
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

> **⚠️ Важливо:** Будь-який `*_controller.js` у директорії автоматично реєструється через `eagerLoadControllersFrom` — **не залишайте scaffold-файли в production**.

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

| Stream | Підписка у | Оновлюється ким |
|---|---|---|
| `"telemetry_stream"` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` (черга: `uplink`) |
| `@wallet, :transactions` | `Wallets::Show` | `BlockchainMintingService` / TX workers |

**Патерн:**

```ruby
# Підписка (у view_template компонента)
turbo_stream_from @wallet, :transactions

# Broadcast (у worker/service)
Turbo::StreamsChannel.broadcast_prepend_to(
  [@wallet, :transactions],
  target: "transactions_ledger",
  partial: "wallets/transaction_row",
  locals: { tx: new_tx }
)
```

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
| `wallet_balance_{id}` | `Wallets::BalanceDisplay` | `BlockchainMintingService` |
| `transactions_ledger` | `Wallets::Show` | TX confirmation workers |
| `telemetry_feed` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` |
| `ota_progress_{uid}` | `Firmwares::OtaProgressBar` | `OtaTransmissionWorker` |
| `alert_badge_{id}` | `Alerts::Badge` | `EwsAlertWorker` |

---

## 9. Чекліст Доступності

Всі компоненти перевіряються за цим чеклістом:

| Правило | Реалізація |
|---|---|
| `role` на семантичних елементах | `role="table"` на таблицях, `role="status"` на бейджах, `role="navigation"` на бічній панелі, `role="group"` на StatCard |
| `aria-label` на інтерактивних елементах | Всі елементи `<button>` та `<a>` мають описовий `aria_label:` |
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

## 10. Тестування та Lookbook

### RSpec Тести Компонентів

| Spec-файл | Приклади | Покриття |
|---|---|---|
| `spec/views/shared/ui/status_badge_spec.rb` | 13 | Всі AASM стани, семантичні токени, доступність |
| `spec/views/shared/ui/stat_card_spec.rb` | 14 | Props, danger-режим, перевизначення класу |
| `spec/views/shared/ui/action_badge_spec.rb` | 10 | Pattern matching, семантичні стилі |
| `spec/views/shared/ui/empty_state_spec.rb` | 10 | За замовчуванням, кастомна іконка, table-режим |
| `spec/views/shared/ui/meta_row_spec.rb` | 5 | Мітка/значення, обробка nil |
| `spec/views/shared/ui/relative_time_spec.rb` | 9 | Інтервали часу, граничні випадки |
| `spec/views/shared/web3/address_spec.rb` | 10 | Обрізання, clipboard, nil fallback |
| `spec/views/shared/iot/metric_value_spec.rb` | 8 | Точність, nil, BigDecimal, одиниця |
| `spec/views/components/alerts/badge_spec.rb` | 12 | Матриця severity × status |
| `spec/views/components/dashboard/event_row_spec.rb` | 10 | Поліморфні типи подій |
| `spec/views/components/wallets/transaction_row_spec.rb` | 16 | Типи токенів, обрізання хешу |
| `spec/views/components/wallets/balance_display_spec.rb` | 8 | Рендеринг балансу, Turbo target |
| `spec/views/components/actuators/card_spec.rb` | 14 | Статус LED, рендеринг матриці |
| `spec/views/shared/ui/data_table_spec.rb` | 20 | Стовпці+рядки, порожній стан, кастомний empty_message, відповідність дизайн-системі, доступність, перевизначення класу, один стовпець |
| `spec/views/shared/ui/pagination_spec.rb` | 22 | Перша/середня/остання/одна сторінка, відповідність дизайн-системі, доступність, focus-visible, guard невалідного pagy |
| `spec/views/shared/ui/photo_card_spec.rb` | 17 | Ініціалізація, валідація, відповідність дизайн-системі, editable true/false, типографіка |
| `spec/views/shared/ui/skeleton_spec.rb` | 13 | Всі 6 варіантів, кастомні рядки, перевизначення класу |
| `spec/views/shared/ui/theme_switcher_spec.rb` | 10 | Поведінка перемикання, dark/light стан |
| `spec/views/components/alerts/row_spec.rb` | 12 | Severity, статус, дія вирішення |
| `spec/views/components/clusters/show_spec.rb` | 17 | Індекс здоров'я, список дерев, стан загрози |
| `spec/views/components/tree_families/form_spec.rb` | 14 | Форма створення/оновлення, валідація |
| `spec/views/components/wallets/show_spec.rb` | 11 | Фрейм балансу, журнал транзакцій, pagy пагінація |

### Lookbook (Дослідник Компонентів)

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

### Зведена Таблиця Відповідності 29 Правилам TailwindCSS

> Відстежує відповідність **Маніфесту 29 Найкращих Практик TailwindCSS** для всіх 67+ компонентів.

#### ✅ Повністю Застосовано (всі 67 компонентів + shared/ui + layout + navigation)

| Правило | Опис | Статус |
|---------|------|--------|
| 1 | Без довільних значень | ✅ Всі `text-[Npx]` замінено на `text-micro/mini/tiny/compact` в 63+ файлах |
| 2 | Семантичні кольори для станів | ✅ Всі amber → токени `status-warning`/`token-forest` (20 файлів) |
| 6 | Без @apply у Phlex | ✅ Лише Ruby-методи |
| 7 | Mobile-first | ✅ За замовчуванням = mobile, `md:` для desktop |
| 8 | `gap-` замість margins | ✅ `space-x`/`space-y` → `gap` у flex/grid (26+ файлів) |
| 10 | `grid` для 2D, `flex` для 1D | ✅ Правильне використання скрізь |
| 11 | Запобігання горизонтальному скролу | ✅ `overflow-x-auto` на таблицях |
| 13 | Перевизначення класів через `tokens()` | ✅ Патерн `**attrs` в shared/ui компонентах |
| 14 | Логічне групування класів | ✅ Layout→Spacing→Type→Visual→Interactive |
| 15 | Виносити довгі рядки класів | ✅ Приватні методи у shared/ui |
| 17 | Без hardcoded margins у компонентах | ✅ `mt-6`, `mb-4`, `mb-2` видалено зі shared/ui |
| 18 | SVG використовують `currentColor` | ✅ `stroke="currentColor"` |
| 20 | `tracking-widest` для uppercase | ✅ Додано де бракувало |
| 21 | `leading-tight` для заголовків | ✅ Застосовано до `h1` |
| 25 | Стани `hover`/`focus`/`active` | ✅ Всі інтерактивні елементи |
| 26 | `focus-visible:` замість `focus:` | ✅ **Всі 67+ компонентів** — нуль порушень `focus:` |
| 27 | Transitions з duration/ease | ✅ `duration-200 ease-in-out` у shared/ui |
| 28 | Стани `disabled:` | ✅ На кнопці видалення |
| 29 | Вкладені взаємодії `group`/`group-hover` | ✅ PhotoCard, Sidebar |

#### ⏳ Робота з Низьким Пріоритетом

| Правило | Опис | Статус |
|---------|------|--------|
| 3 | Dark mode визначення | ✅ Light/dark динамічні кольори статусів реалізовані через CSS custom properties |
| 13 | Перевизначення класів у domain компонентах | ⏳ Shared/ui має `**attrs`; domain компоненти — page-level (потреба менша) |
| 15 | Виносити класи у domain компонентах | ⏳ Довгі inline рядки залишаються в деяких domain views |
| 17 | Margins у domain page компонентах | ⏳ Page-level margins (`mb-4`, `mt-6`) допустимі в non-reusable views |

---

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
