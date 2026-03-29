# 04_04: Phlex UI & Tailwind (Design System SSOT)

## 🎯 Мета (Objective)

Зафіксувати повну специфікацію дизайн-системи Gaia 2.0 як Єдине Джерело Істини (SSOT). Документ описує **Phlex-компоненти**, **Tailwind CSS токени**, **Stimulus-контролери**, **Turbo-інтеграцію** та правила доступності. Слугує єдиним авторитетним джерелом для всіх UI-рішень в межах Rails 8.1 моноліту. Зворотньо виведено (Reverse Shaping) з живого кодбейсу.

## ✅ Статус (Status)

- **Поточний TRL:** TRL 9 — Operational. Reverse-shaped from live codebase.
- **Stack:** Rails 8.1 · Phlex · Tailwind CSS 4 · TailwindMerge · Stimulus · Turbo 8
- **Пов'язані модулі:**
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - REST API → [`04_03_REST_API_v1_Reference`](04_03_REST_API_v1_Reference)
  - Моделі → [`04_01_Data_Models_and_Entities`](04_01_Data_Models_and_Entities)
  - Прошивка → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)

## 🛑 Блокери (Blockers / Needs Action)

- ~~**🔴 BLOCKER-01: `map` контролер — відсутній `disconnect()` (Memory Leak при Turbo Drive навігації).**
  `map_controller.js` не мав `disconnect()` методу. Leaflet map instance не знищувалась при Turbo Drive-навігації → витік пам'яті при кожному переході між сторінками. Маркери накопичувались у пам'яті браузера.~~ ✅ **ВИРІШЕНО** у кодбейсі: `map_controller.js` має `disconnect()` що викликає `this.map.off()`, `this.map.remove()`, скидає `this.markers = {}` та очищає `resizeTimeout`. `matrix_rain_controller.js` — коректно очищає `clearInterval` + `removeEventListener` у `disconnect()`.

- ~~**🟠 BLOCKER-02: Відсутні RSpec-тести для `PhotoCard`, `DataTable`, `Pagination`.**
  Документ (§10) декларує 134 приклади в 13 файлах, але три з 11 Shared UI компонентів не мають spec-файлів:
  - `spec/views/shared/ui/photo_card_spec.rb` — **ВІДСУТНІЙ** (`PhotoCard` — ActiveStorage, hover overlay, editable delete)
  - `spec/views/shared/ui/data_table_spec.rb` — **ВІДСУТНІЙ** (`DataTable` — configurable columns, empty state, block rendering)
  - `spec/views/shared/ui/pagination_spec.rb` — **ВІДСУТНІЙ** (`Pagination` — Pagy prev/next, URL helper)~~ ✅ **ВИРІШЕНО** у [commit b08de50](https://github.com/Alexey-Lukin/silken_net/commit/b08de50f84f1bc612b91db0e90b5e2082338b5d6) (PR #231):
  - `spec/views/shared/ui/data_table_spec.rb` — додано 20 прикладів: columns+rows, empty state, custom `empty_message`, design system compliance, accessibility, class override, single column
  - `spec/views/shared/ui/pagination_spec.rb` — додано 22 приклади: middle/first/last/single page, design system compliance, accessibility, focus-visible, invalid pagy guard
  - `spec/views/shared/ui/photo_card_spec.rb` — додано 17 прикладів: initialization, validation, design system compliance, editable true/false, typography
  - `spec/components/previews/skeleton_preview.rb` — додано Lookbook preview з 8 сценаріями: default, text, card, stats, table, map, custom_lines, interactive

- ~~**🟡 BLOCKER-03: Legacy `2xs`/`3xs` fontSize аліаси в `tailwind.config.js` не зареєстровані в `CUSTOM_TEXT_SCALE`.**
  `config/tailwind.config.js` розширює `theme.fontSize` через:
  ```js
  "2xs": ["0.625rem", { lineHeight: "0.875rem" }],  /* 10px — збігається з `tiny` */
  "3xs": ["0.5rem",   { lineHeight: "0.75rem"  }],  /* 8px  — збігається з `micro` */
  ```
  Ці аліаси генерують класи `text-2xs` / `text-3xs`, що **не зареєстровані** у `ApplicationComponent::CUSTOM_TEXT_SCALE = %w[micro mini tiny compact]`. Якщо компонент комбінує `text-2xs` з `text-status-*`, TailwindMerge трактує обидва як `text-*` конфлікт і видаляє один із класів.~~ ✅ **ВИРІШЕНО** у [commit b08de50](https://github.com/Alexey-Lukin/silken_net/commit/b08de50f84f1bc612b91db0e90b5e2082338b5d6) (PR #231): legacy аліаси `"2xs"` та `"3xs"` видалено з `config/tailwind.config.js`. Тепер `theme.fontSize` містить виключно семантичні токени (`micro`, `mini`, `tiny`, `compact`), зареєстровані в `CUSTOM_TEXT_SCALE`. TailwindMerge коректно розрізняє font-size та color класи без конфліктів.

### 🔍 Аудит 2026-03-29 — Нові знайдені проблеми

#### 🔴 Блокери

- **🔴 B-01 · `Web3::Address` використовує raw Tailwind кольори в shared-компоненті.** `app/views/shared/web3/address.rb` містить `text-emerald-500`, `text-emerald-700`, `hover:text-emerald-300`, `focus-visible:ring-emerald-500`, `text-gray-700`. Документ §3.5 забороняє raw Tailwind кольори в shared-компонентах (тільки semantic tokens). `shared/web3/` — reusable shared namespace, а не domain page component. **Дія:** Замінити на семантичні токени: `text-gaia-primary`, `hover:text-gaia-primary-hover`, `focus-visible:ring-gaia-primary`, `text-gaia-text-muted`.

- **🔴 B-02 · `IoT::MetricValue` використовує raw Tailwind кольори в shared-компоненті.** `app/views/shared/iot/metric_value.rb` містить `text-emerald-400` (value span) та `text-emerald-700` (unit span). Порушення того ж правила §3.5. **Дія:** Замінити на `text-gaia-primary` та `text-gaia-text-muted`.

- **🔴 B-03 · Текст вирішення BLOCKER-03 фактично неточний щодо `tailwind.config.js`.** Документ стверджує: "тепер `theme.fontSize` містить виключно семантичні токени (`micro`, `mini`, `tiny`, `compact`)". В реальності `config/tailwind.config.js` **взагалі не має ключа `fontSize`** — ані в `theme`, ані в `theme.extend`. Кастомні font-size токени визначені виключно у CSS `@theme` блоку в `application.css` (`--font-size-micro` тощо). **Дія:** Оновити текст вирішення: "Legacy аліаси видалені повністю. Кастомні токени (`micro`, `mini`, `tiny`, `compact`) визначені у CSS `@theme` блоці `application.css`, а не в JS-конфігу".

#### 🟠 Попередження

- **🟠 W-01 · `StatusBadge` §6.1 — стан `dormant` в неправильному рядку таблиці.** Документ §6.1 розміщує `dormant` серед нейтральних станів (`idle`, `draft`, `expired` тощо). Код `status_badge.rb` та §3.2 узгоджені: `dormant → bg-status-warning`. **Дія:** Перемістити `dormant` у рядок `status-warning` таблиці §6.1.

- **🟠 W-02 · `StatusBadge` — два стани відсутні у таблиці §6.1.** Код містить `"ignored" → bg-status-neutral opacity-30 line-through` та `"maintenance_needed" → bg-status-warning` — жоден не задокументований у §6.1. **Дія:** Додати `ignored` до нейтрального рядка (з приміткою про `opacity-30 line-through`) та `maintenance_needed` до warning-рядка.

- **🟠 W-03 · §6.1 не відображає модифікатори opacity та text-decoration для нейтральних станів.** Код: `resolved`, `cancelled`, `removed` → `opacity-50`; `ignored` → `opacity-30 line-through`; `deceased` → `line-through`. **Дія:** Додати колонку "Модифікатори" або примітки до таблиці станів.

- **🟠 W-04 · Кількість прикладів у таблиці §10 неправильна для 9 з 16 spec-файлів.** Перевірені значення (`grep '^\s*it '`): `status_badge_spec.rb` — 13 (doc: 25); `stat_card_spec.rb` — 14 (doc: 7); `action_badge_spec.rb` — 10 (doc: 8); `empty_state_spec.rb` — 10 (doc: 6); `meta_row_spec.rb` — 5 (doc: 6); `relative_time_spec.rb` — 9 (doc: 8); `address_spec.rb` — 10 (doc: 8); `transaction_row_spec.rb` — 16 (doc: 14); `card_spec.rb` (actuators) — 14 (doc: 16). Реальний підрахунок 16 файлів: **198**, а не 193. **Дія:** Перерахувати всі приклади та оновити таблицю і підсумок.

- **🟠 W-05 · Шість spec-файлів повністю відсутні в таблиці §10.** Існуючі файли не включені до документа: `skeleton_spec.rb` (13 прикладів), `theme_switcher_spec.rb` (10), `alerts/row_spec.rb` (12), `clusters/show_spec.rb` (17), `tree_families/form_spec.rb` (14), `wallets/show_spec.rb` (11). Разом 77 додаткових прикладів — реальний total: **275** у 22 файлах. **Дія:** Додати всі 6 файлів до таблиці §10; оновити підсумок.

- **🟠 W-06 · `hello_controller.js` — активний але незадокументований Stimulus-контролер.** `app/javascript/controllers/hello_controller.js` існує і містить `connect()` що встановлює `this.element.textContent = "Hello World!"`. Через `eagerLoadControllersFrom` він автоматично зареєстрований і доступний через `data-controller="hello"` в production. Це scaffold-залишок. **Дія:** Або видалити файл, або задокументувати як debug-заглушку.

- **🟠 W-07 · Кількість компонентів у §9 занижена.** Документ: "100% compliance across all 67+ components". Реально `find app/views -name "*.rb"` (без `application_component.rb`): **83 файли**. **Дія:** Оновити на "83+ компонентів".

- **🟠 W-08 · `Wallets::Show` — параметр `pagy:` опціональний, але задокументований без дефолту.** Код: `def initialize(wallet:, transactions:, pagy: nil)`. **Дія:** Оновити Props на `wallet:, transactions:, pagy: nil`.

- **🟠 W-09 · CSS `@theme` блок містить три незадокументовані кольорові змінні.** `app/assets/tailwind/application.css`: `--color-gaia-green: #10b981`, `--color-gaia-dark: #064e3b`, `--color-gaia-muted: #065f46`. Генерують класи `bg-gaia-green`, `text-gaia-dark`, `text-gaia-muted`. Відсутні у §3. **Дія:** Додати до таблиці токенів §3 або видалити як невикористані.

- **🟠 W-10 · TRL 9 завищений за наявності активних порушень правил дизайн-системи.** B-01 та B-02 — два shared-компоненти порушують core color-token rule §3.5. B-03 — текст вирішення неточний. W-06 — orphan Stimulus-контролер живий у production. W-04/W-05 — таблиця тестів неточна. **Дія:** Понизити до TRL 8 до виправлення B-01/B-02/W-06 та актуалізації тестової таблиці.

#### 🟡 Нотатки

- **🟡 N-01 · `theme_controller.js` — `disconnect()` не задокументований у §7.1.** Метод видаляє `mediaQuery.addEventListener("change", ...)` для запобігання memory leak при Turbo Drive навігації. **Дія:** Додати опис `disconnect()` до §7.1.

- **🟡 N-02 · `clipboard_controller.js` — `disconnect()` не задокументований у §7.2.** Метод викликає `clearTimeout(this.feedbackTimeout)`. **Дія:** Додати до §7.2.

- **🟡 N-03 · `map_controller.js` — опис `disconnect()` у §7.3 неповний.** Після `this.map.remove()` код також встановлює `this.map = null`. `this.markerLayer` не очищається — потенційний minor memory leak. **Дія:** Додати `this.map = null` до опису; розглянути очищення `this.markerLayer`.

- **🟡 N-04 · `eagerLoadControllersFrom` не попереджає про автоматичну реєстрацію будь-якого `*_controller.js`.** Включно з `hello_controller.js`. **Дія:** Додати до §7 примітку: "Будь-який `*_controller.js` у директорії автоматично реєструється — не залишати scaffold-файли в production".

- **🟡 N-05 · Таблиця Typography Scale §4 показує px-значення, а не rem.** CSS: `0.5rem`, `0.5625rem` тощо — масштабуються з налаштуваннями браузера, а не є фіксованими px. **Дія:** Розширити колонку: `0.5rem (8px)` — уточнити root-relative природу.

- **🟡 N-06 · `StatusBadge` стан `ignored` відсутній у §3.2 таблиці status-токенів.** Код: `ignored → status-neutral`. **Дія:** Додати `ignored` до колонки AASM states для `status-neutral` у §3.2.

- **🟡 N-07 · Lookbook `ActionBadgePreview` — опис сценаріїв вводить в оману.** Документ: "All 4 action types, Interactive". Насправді: 2 методи (`all_types` та `interactive`). **Дія:** Уточнити: "2 сценаріїв: `all_types` (4 типи), `interactive`".

- **🟡 N-08 · Lookbook `AlertBadgePreview` — опис сценаріїв вводить в оману.** Документ: "Severity × Status matrix (9 combos), Interactive". Насправді: 2 методи (`all_combos`, `interactive`). **Дія:** Уточнити: "2 сценаріїв: `all_combos` (9 combo matrix), `interactive`".


---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [ApplicationComponent — Base Class](#2-applicationcomponent--base-class)
3. [Tailwind Design Tokens](#3-tailwind-design-tokens)
4. [Typography Scale](#4-typography-scale)
5. [TailwindMerge & `tokens()` Pattern](#5-tailwindmerge--tokens-pattern)
6. [Component Registry](#6-component-registry)
   - [Shared UI Primitives](#61-shared-ui-primitives-appviewssharedui)
   - [Shared IoT Components](#62-shared-iot-components-appviewssharediot)
   - [Shared Web3 Components](#63-shared-web3-components-appviewssharedweb3)
   - [Domain Components](#64-domain-components-appviewscomponents)
7. [Stimulus Controllers](#7-stimulus-controllers)
8. [Turbo Integration (Streams & Frames)](#8-turbo-integration-streams--frames)
9. [Accessibility Checklist](#9-accessibility-checklist)
10. [Testing & Lookbook](#10-testing--lookbook)

---

## 1. Architecture Overview

Gaia 2.0 uses a **Ruby-first, utility-CSS** approach: all views are Phlex Ruby classes (no `.erb` templates for domain logic), styled exclusively with Tailwind utility classes, merged conflict-free via TailwindMerge.

The design system is **dark-first** — a terminal/cyberpunk aesthetic with glowing emerald accents (`#10b981`) on a pure black (`#000000`) background. Light mode is a secondary, high-contrast alternative activated by toggling the `.dark` class on `<html>`.

### Component Hierarchy

```
ApplicationComponent (Phlex::HTML)
│   Includes: Routes, TurboStreamFrom, TurboFrameTag, FormWith,
│             ButtonTo, AssetPath, FormAuthenticityToken
│   Defines:  tokens(), TailwindMerge::Merger, CUSTOM_TEXT_SCALE
│
├── app/views/shared/        # Reusable primitives (framework-level)
│   ├── ui/                  # Generic UI elements
│   │   ├── StatusBadge      ← AASM state → semantic color
│   │   ├── StatCard         ← Dashboard metric card
│   │   ├── DataTable        ← Table wrapper with configurable columns
│   │   ├── Pagination       ← Pagy-based prev/next
│   │   ├── EmptyState       ← Placeholder (grid or table-row mode)
│   │   ├── MetaRow          ← Key-value display row
│   │   ├── ActionBadge      ← Audit action type badge
│   │   ├── PhotoCard        ← ActiveStorage photo with hover overlay
│   │   ├── RelativeTime     ← "5 minutes ago" with tooltip
│   │   ├── Skeleton         ← Loading skeleton (6 variants)
│   │   └── ThemeSwitcher    ← Dark/light toggle button
│   ├── iot/
│   │   └── MetricValue      ← Numeric sensor value with precision + unit
│   └── web3/
│       └── Address          ← Ethereum address with truncation + copy
│
└── app/views/components/    # Domain-specific page components
    ├── navigation/Sidebar
    ├── dashboard/Home, Map, MapNode, EventRow
    ├── trees/Index, Show
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

### Rendering Flow

```
HTTP Request
    └─► Controller (thin — pre-loads all data, no business logic)
            └─► render DomainComponent.new(data:)
                    └─► view_template
                            ├─► render Views::Shared::UI::StatusBadge.new(...)
                            ├─► render Views::Shared::UI::DataTable.new(...) { rows }
                            └─► turbo_stream_from / turbo_frame_tag (lazy)
```

---

## 2. ApplicationComponent — Base Class

**File:** `app/views/components/application_component.rb`

```ruby
class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::TurboStreamFrom
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::AssetPath
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include ActionView::RecordIdentifier  # dom_id / dom_class helpers for Turbo targets

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

### Key Design Decisions

| Decision | Rationale |
|---|---|
| `delegate :time_ago_in_words` to `ActionController::Base.helpers` | Turbo broadcast contexts have no Rails view context; this ensures helpers work in background workers |
| `CUSTOM_TEXT_SCALE` registration | Prevents TailwindMerge from treating `text-tiny` (font-size) and `text-status-warning-text` (color) as conflicting classes |
| No DB queries in `initialize` | All data must be passed as constructor args; components are pure render functions |

---

## 3. Tailwind Design Tokens

**Files:** `app/assets/tailwind/application.css` · `config/tailwind.config.js`

The token system works in two layers:

1. **CSS custom properties** (defined in `application.css`) hold the actual values and switch between light/dark modes.
2. **Tailwind config** maps semantic class names to the CSS variables — Tailwind generates utility classes like `bg-gaia-surface`, `text-status-danger-text`, etc.

### 3.1 Surface, Text & Primary Tokens (`gaia-*`)

| Token | Tailwind Class | Light `#` | Dark `#` | Use Case |
|---|---|---|---|---|
| `--color-gaia-surface` | `bg-gaia-surface` | `#ffffff` | `#000000` | Card, panel, form backgrounds |
| `--color-gaia-surface-alt` | `bg-gaia-surface-alt` | `#f3f4f6` | `#0a0a0a` | Table headers, secondary panels |
| `--color-gaia-text` | `text-gaia-text` | `#111827` | `#10b981` | Primary body text |
| `--color-gaia-text-muted` | `text-gaia-text-muted` | `#6b7280` | `#065f46` | Labels, metadata, placeholders |
| `--color-gaia-primary` | `text-gaia-primary` / `bg-gaia-primary` | `#10b981` | `#10b981` | Brand emerald (same in both modes) |
| `--color-gaia-primary-hover` | `hover:bg-gaia-primary-hover` | `#059669` | `#34d399` | Primary button hover |
| `--color-gaia-border` | `border-gaia-border` | `#e5e7eb` | `rgba(16,185,129,0.2)` | Borders, dividers |

### 3.2 Status Tokens (`status-*`)

All AASM state rendering uses these tokens — never raw Tailwind colors.

| Token Pair | Light Bg / Text | Dark Bg / Text | AASM States |
|---|---|---|---|
| `status-danger` / `status-danger-text` | `#fee2e2` / `#991b1b` | `#7f1d1d` / `#fecaca` | `failed`, `active` (EwsAlert only — see note), `breached`, `deceased`, `faulty` |
| `status-danger-accent` | `#dc2626` | `#ef4444` | Accent values, LED indicators |
| `status-warning` / `status-warning-text` | `#fef3c7` / `#92400e` | `#78350f` / `#fde68a` | `pending`, `issued`, `triggered`, `updating`, `dormant` |
| `status-info` / `status-info-text` | `#dbeafe` / `#1e40af` | `#1e3a5f` / `#bfdbfe` | `sent`, `paid`, `maintenance` |
| `status-success` / `status-success-text` | `#d1fae5` / `#065f46` | `#065f46` / `#d1fae5` | `confirmed`, `fulfilled` |
| `status-active` / `status-active-text` | `#ccfbf1` / `#115e59` | `#064e3b` / `#a7f3d0` | `acknowledged` |
| `status-neutral` / `status-neutral-text` | `#f3f4f6` / `#4b5563` | `#27272a` / `#a1a1aa` | `idle`, `draft`, `expired`, `offline`, `resolved`, `cancelled` |

### 3.3 Blockchain Token Colors (`token-*`)

| Token | Tailwind Class | Light | Dark | Use Case |
|---|---|---|---|---|
| `--color-token-carbon` | `text-token-carbon` | `#047857` | `#059669` | SilkenCarbonCoin (SCC) |
| `--color-token-forest` | `text-token-forest` | `#b45309` | `#d97706` | SilkenForestCoin (SFC) |

### 3.4 Form Input Tokens (`gaia-input-*`)

| Token | Tailwind Class | Light | Dark |
|---|---|---|---|
| `--color-gaia-input-bg` | `bg-gaia-input-bg` | `#ffffff` | `#09090b` |
| `--color-gaia-input-border` | `border-gaia-input-border` | `#d1d5db` | `rgba(16,185,129,0.3)` |
| `--color-gaia-input-text` | `text-gaia-input-text` | `#111827` | `#d1fae5` |
| `--color-gaia-label` | `text-gaia-label` | `#6b7280` | `#6b7280` |

### 3.5 Color Usage Rules

| ✅ Do | ❌ Never |
|---|---|
| `bg-gaia-surface` | `bg-white` / `bg-black` (in shared components) |
| `text-gaia-text` | `text-gray-900` / `text-emerald-400` (in shared components) |
| `border-gaia-border` | `border-gray-200` / `border-emerald-900` (in shared components) |
| `bg-status-danger text-status-danger-text` | `bg-red-100 text-red-800` |
| `shadow-sm dark:shadow-none` | `shadow-lg` everywhere |

> **Exception:** Domain-specific page components (not shared/ui) may use raw Tailwind colors (e.g., `border-emerald-900`, `bg-zinc-950`) for their cyberpunk terminal aesthetic, since they are not reused across contexts.

---

## 4. Typography Scale

**Defined in:** `app/assets/tailwind/application.css` `@theme` block
**Registered in:** `ApplicationComponent::CUSTOM_TEXT_SCALE`

Custom terminal-aesthetic font sizes that eliminate all `text-[Npx]` arbitrary values:

| CSS Token | Utility Class | Size | Line Height | Use Case |
|---|---|---|---|---|
| `--font-size-micro` | `text-micro` | 8px | 1rem | Micro labels, file sizes, role badges, watermarks |
| `--font-size-mini` | `text-mini` | 9px | 1rem | Uppercase nav items, status badge text |
| `--font-size-tiny` | `text-tiny` | 10px | 1rem | Small labels, metadata, section headings |
| `--font-size-compact` | `text-compact` | 11px | 1.25rem | Data tables, addresses, metric values |

Standard Tailwind sizes continue to apply for larger text (e.g., `text-xs`, `text-sm`, `text-2xl`) — these coexist with the custom scale. The custom tokens specifically eliminate arbitrary values like `text-[9px]` for sub-`text-xs` sizes.

### Typography Base Styles

Defined in `@layer base` inside `application.css`:

| Element | Size | Weight | Letter Spacing |
|---|---|---|---|
| `h1` | `1.875rem` | `300` (light) | `0.05em` |
| `h2` | `1.5rem` | `300` (light) | `0.05em` |
| `h3` | `1.25rem` | `400` (normal) | — |
| `h4` | `1rem` | `500` (medium) | `0.1em` uppercase |

### Font Families

| Family | Fonts |
|---|---|
| `font-mono` | JetBrains Mono → Fira Code → SF Mono → Cascadia Code → system mono |
| `font-sans` | Inter → system-ui → -apple-system → … |

---

## 5. TailwindMerge & `tokens()` Pattern

`tokens()` is the design system's class composition method — it replaces direct string concatenation and prevents Tailwind class conflicts.

### Signature

```ruby
def tokens(*static_classes, **conditional_classes)
  # static_classes  — always applied
  # conditional_classes — { "class-string": boolean_condition }
end
```

### Examples

**Static + conditional classes:**

```ruby
# Status-driven styling
span(class: tokens(
  "px-2 py-0.5 rounded text-tiny font-bold uppercase tracking-widest",
  "bg-status-danger text-status-danger-text animate-pulse": alert.severity == "critical",
  "bg-status-warning text-status-warning-text": alert.severity == "medium",
  "bg-zinc-800 text-zinc-300": alert.severity == "low"
))

# Active nav item
a(class: tokens(
  nav_item_base_classes,
  active ? nav_item_active_classes : nav_item_inactive_classes
))
```

**Prop-driven class override (shared components):**

```ruby
def initialize(status:, **attrs)
  @status = status
  @extra_class = attrs[:class]
end

def view_template
  span(class: tokens(badge_base_classes, STYLES[@status], @extra_class)) { @status }
end

# Caller overrides without conflict:
render Views::Shared::UI::StatusBadge.new(status: "confirmed", class: "mt-2")
```

### Why TailwindMerge

Without it, `tokens("text-tiny text-emerald-500")` could produce broken output because TailwindMerge (without configuration) treats both as `text-*` conflicts and drops one. The `CUSTOM_TEXT_SCALE` registration teaches TailwindMerge that `text-micro/mini/tiny/compact` are font-size tokens, not color tokens.

---

## 6. Component Registry

### 6.1 Shared UI Primitives (`app/views/shared/ui/`)

These are the framework-level building blocks used across all domain views.

| Component | File | Key Props | Purpose |
|---|---|---|---|
| **StatusBadge** | `status_badge.rb` | `status:`, `id:`, `class:` | AASM state → semantic color badge (20+ states) |
| **StatCard** | `stat_card.rb` | `label:`, `value:`, `sub:`, `danger:`, `class:` | Dashboard metric card with optional danger highlight |
| **DataTable** | `data_table.rb` | `columns:`, `empty_message:`, `class:`, `&block` | Table wrapper with configurable column headers |
| **Pagination** | `pagination.rb` | `pagy:`, `url_helper:` | Pagy-based prev/next navigation |
| **EmptyState** | `empty_state.rb` | `title:`, `description:`, `icon:`, `colspan:` | Empty data placeholder (grid or `<tr><td>` mode) |
| **MetaRow** | `meta_row.rb` | `label:`, `value:`, `class:` | Key-value display row for detail pages |
| **ActionBadge** | `action_badge.rb` | `action:`, `class:` | Audit log action-type badge (regex pattern matching) |
| **PhotoCard** | `photo_card.rb` | `photo:`, `record:`, `editable:` | ActiveStorage blob card with hover overlay |
| **RelativeTime** | `relative_time.rb` | `datetime:`, `css_class:`, `prefix:` | "5 minutes ago" with full timestamp `title` tooltip |
| **Skeleton** | `skeleton.rb` | `variant:`, `lines:`, `class:` | Loading skeleton (6 variants: `:balance`, `:card`, `:stats`, `:table`, `:map`, `:text`) |
| **ThemeSwitcher** | `theme_switcher.rb` | — | Dark/light toggle button (uses `theme` Stimulus controller) |

#### StatusBadge — State Mapping

| AASM States | Semantic Style |
|---|---|
| `pending`, `issued` | `bg-status-warning text-status-warning-text` |
| `processing`, `triggered`, `updating` | `+ animate-pulse` |
| `confirmed`, `fulfilled` | `bg-status-success text-status-success-text` |
| `sent`, `paid`, `maintenance` | `bg-status-info text-status-info-text` |
| `failed`, `active` (EwsAlert), `breached`, `deceased`, `faulty` | `bg-status-danger text-status-danger-text` |
| `acknowledged` | `bg-status-active text-status-active-text` |
| `idle`, `draft`, `expired`, `offline`, `resolved`, `cancelled`, `dormant`, `removed` | `bg-status-neutral text-status-neutral-text` |

> **Note on `active`:** The state `active` maps to `status-danger` when used with `EwsAlert` (an unresolved threat alert). For other entities (e.g., `Tree` with `status: "active"`) the same string resolves to the `DEFAULT_STYLE` neutral fallback, since `StatusBadge` only maps the states explicitly listed in `STYLES`. Domain components (e.g., `Trees::Show`) apply their own color logic inline.

#### Skeleton — Variants

| Variant | Lines | Use Case |
|---|---|---|
| `:balance` | 3 (label, amount, sub) | Wallet balance lazy-load frame |
| `:card` | 3 (title, body, sub) | Metadata/blockchain identity frame |
| `:stats` | 3 | Dashboard stat cards |
| `:table` | 4 full-width rows | Table data loading |
| `:map` | 3 (header, map, footer) | Geospatial map loading |
| `:text` | 1 | Inline text fragments |

---

### 6.2 Shared IoT Components (`app/views/shared/iot/`)

| Component | File | Key Props | Purpose |
|---|---|---|---|
| **MetricValue** | `metric_value.rb` | `value:`, `unit:`, `precision:` | Sensor numeric display with configurable decimal precision; handles `nil` and `BigDecimal` |

```ruby
render Views::Shared::IoT::MetricValue.new(value: 3800.0, unit: "mV", precision: 0)
render Views::Shared::IoT::MetricValue.new(value: lorenz_z, unit: "σ", precision: 4)
```

---

### 6.3 Shared Web3 Components (`app/views/shared/web3/`)

| Component | File | Key Props | Purpose |
|---|---|---|---|
| **Address** | `address.rb` | `address:`, `fallback:` | Ethereum address with `PREFIX_LENGTH=6` / `SUFFIX_LENGTH=4` truncation + clipboard copy button (uses `clipboard` Stimulus controller) |

```ruby
render Views::Shared::Web3::Address.new(address: @wallet.crypto_public_address)
render Views::Shared::Web3::Address.new(address: nil, fallback: "NOT_PROVISIONED")
```

---

### 6.4 Domain Components (`app/views/components/`)

Domain components are page-level and are **not** expected to be reused outside their context.

#### Navigation

| Component | File | Props | Description |
|---|---|---|---|
| `Navigation::Sidebar` | `navigation/sidebar.rb` | `current_path:`, `ews_alert_count:` | Full app navigation sidebar with 4 section groups (Strategic, Forest Ops, Neural Network, Administration), active state highlighting, EWS alert badge, status pulse |

#### Dashboard

| Component | File | Props | Description |
|---|---|---|---|
| `Dashboard::Home` | `dashboard/home.rb` | `stats:`, `events:` | Main dashboard: 4 stat cards, geospatial map panel, live event feed |
| `Dashboard::Map` | `dashboard/map.rb` | `trees:` | Leaflet map wrapper with tree marker streaming via Turbo/Stimulus |
| `Dashboard::MapNode` | `dashboard/map_node.rb` | `tree:` | Hidden Stimulus target node for live map updates |
| `Dashboard::EventRow` | `dashboard/event_row.rb` | `event:` | Polymorphic event row (EwsAlert / BlockchainTransaction / MaintenanceRecord) |

#### Trees

| Component | File | Props | Description |
|---|---|---|---|
| `Trees::Index` | `trees/index.rb` | `trees:`, `pagy:` | Paginated tree list |
| `Trees::Show` | `trees/show.rb` | `tree:`, `latest_log:`, `recent_logs:`, `maintenance_history:` | Full tree detail: biometric matrix (radial SVG), impedance history chart, economic panel, hardware security vault, maintenance ledger |

#### Wallets

| Component | File | Props | Description |
|---|---|---|---|
| `Wallets::Index` | `wallets/index.rb` | `wallets:`, `pagy:` | Paginated wallet list |
| `Wallets::Show` | `wallets/show.rb` | `wallet:`, `transactions:`, `pagy:` | Wallet detail with lazy-loaded balance frame, transaction ledger, on-chain actions |
| `Wallets::BalanceDisplay` | `wallets/balance_display.rb` | `wallet:` | SCC balance card with locked/available/ESG-retired breakdown; Turbo target `wallet_balance_{id}` |
| `Wallets::BalanceFrame` | `wallets/balance_frame.rb` | `wallet:` | Turbo Frame wrapper for lazy balance loading |
| `Wallets::MetadataFrame` | `wallets/metadata_frame.rb` | `wallet:` | Turbo Frame wrapper for blockchain identity metadata |
| `Wallets::TransactionRow` | `wallets/transaction_row.rb` | `tx:` | Single on-chain transaction row with status badge and hash display |

#### Telemetry

| Component | File | Props | Description |
|---|---|---|---|
| `Telemetry::LiveStream` | `telemetry/live_stream.rb` | — | Live telemetry HUD: Matrix Rain canvas background (Stimulus), sticky `<thead>`, `turbo_stream_from "telemetry_stream"` |
| `Telemetry::LogEntry` | `telemetry/log_entry.rb` | `log:` | Single decoded telemetry row inserted by `UnpackTelemetryWorker` |

#### Oracle Visions

| Component | File | Props | Description |
|---|---|---|---|
| `OracleVisions::Index` | `oracle_visions/index.rb` | `forecasts:`, `clusters:` | AI forecast list + simulation panel |
| `OracleVisions::ForecastCard` | `oracle_visions/forecast_card.rb` | `forecast:` | Individual Lorenz attractor forecast card |
| `OracleVisions::SimulationPanel` | `oracle_visions/simulation_panel.rb` | `clusters:` | What-If simulation form with range sliders; submits to `simulate_api_v1_oracle_visions_path` into a Turbo Frame |

#### Firmware OTA

| Component | File | Props | Description |
|---|---|---|---|
| `Firmwares::Index` | `firmwares/index.rb` | `firmwares:`, `pagy:` | Firmware list |
| `Firmwares::New` | `firmwares/new.rb` | — | New firmware upload form |
| `Firmwares::Form` | `firmwares/form.rb` | `firmware:` | Firmware form fields |
| `Firmwares::Row` | `firmwares/row.rb` | `firmware:` | Single firmware list row |
| `Firmwares::OtaProgressBar` | `firmwares/ota_progress_bar.rb` | `uid:`, `percent:`, `current:`, `total:`, `status:` | Animated OTA progress bar; Turbo target `ota_progress_{uid}` |

#### Other Domain Components

| Namespace | Components | Key Props |
|---|---|---|
| `Alerts` | `Index`, `Row`, `Badge` | `alert:` (severity × status matrix) |
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
| `Sessions` | `New` | — |
| `Passwords` | `Forgot`, `Reset` | — |

---

## 7. Stimulus Controllers

**File location:** `app/javascript/controllers/`
**Auto-registration:** `eagerLoadControllersFrom("controllers", application)` via importmap

| Controller | File | `data-controller` | Purpose |
|---|---|---|---|
| **theme** | `theme_controller.js` | `theme` | Dark/light mode toggle |
| **clipboard** | `clipboard_controller.js` | `clipboard` | Copy-to-clipboard for Web3 addresses |
| **map** | `map_controller.js` | `map` | Leaflet.js geospatial tree map |
| **matrix-rain** | `matrix_rain_controller.js` | `matrix-rain` | Canvas Matrix digital rain effect |

### 7.1 `theme` Controller

**Targets:** `icon`
**Actions:** `toggle`

Manages dark/light theme:

1. Reads `localStorage.getItem("theme")` on `connect()`
2. Falls back to `window.matchMedia("(prefers-color-scheme: dark)")`
3. Toggles `.dark` class on `document.documentElement`
4. Listens for OS-level changes via `mediaQuery.addEventListener("change", ...)`
5. Updates `icon` target with SVG (☀ in dark mode, ☽ in light mode)

```html
<div data-controller="theme">
  <button data-action="click->theme#toggle"
          data-theme-target="icon">
    <!-- SVG injected by controller -->
  </button>
</div>
```

**Phlex usage:** Wrapped by `Views::Shared::UI::ThemeSwitcher`.

### 7.2 `clipboard` Controller

**Values:** `content` (String — the text to copy)
**Targets:** `button`

Copies `contentValue` to clipboard via `navigator.clipboard.writeText()` with `document.execCommand("copy")` fallback. Shows `✓` checkmark for 2 seconds as visual feedback.

```html
<span data-controller="clipboard"
      data-clipboard-content-value="0x1234...abcd">
  <button data-action="clipboard#copy"
          data-clipboard-target="button">⧉</button>
</span>
```

**Phlex usage:** Embedded inside `Views::Shared::Web3::Address`.

### 7.3 `map` Controller

**Targets:** `node`

Initializes a Leaflet.js map with CartoDB Dark Matter tiles (cyberpunk aesthetic). Maintains a `markers` hash (`DID → L.Marker`) for incremental updates.

**Key lifecycle:**

- `connect()` — initializes map, sets default center (Cherkasy: 49.4444, 32.0598); initializes `this.markers = {}` (DID string → `L.Marker` instance) and `this.markerLayer = L.layerGroup()`
- `disconnect()` — ✅ **реалізовано**: викликає `this.map.off()`, `this.map.remove()`, скидає `this.markers = {}`, очищає `this.resizeTimeout` — Leaflet map коректно знищується при Turbo Drive навігації
- `nodeTargetConnected(element)` — called automatically by Turbo/Stimulus when a `<div data-map-target="node">` is added to the DOM via Turbo Stream; extracts `data-lat/lng/did/stress/charge` and calls `updateMarker()`

**Marker color logic:**

| Condition | Color | Glow |
|---|---|---|
| `stress > 0.8` or `status === "removed"` | `#ef4444` (red) | `rgba(239,68,68,0.8)` |
| `stress > 0.4` or `charge < 30` | `#eab308` (yellow) | `rgba(234,179,8,0.6)` |
| Default (healthy) | `#10b981` (emerald) | `rgba(16,185,129,0.5)` |

**Phlex usage:** `data: { controller: "map" }` on the map `<div>` in `Dashboard::Map`. Hidden `<div data-map-target="node">` elements streamed via Turbo from `Dashboard::MapNode`.

### 7.4 `matrix-rain` Controller

Canvas-based Matrix digital rain effect using hex characters (`0-9A-F`).

- `connect()` — gets canvas 2D context, starts `setInterval(draw, 60ms)`
- `disconnect()` — clears interval, removes resize listener
- `resize()` — fits canvas to parent, reinitializes `drops[]` array

**Phlex usage:** `canvas(data: { controller: "matrix-rain" }, class: "absolute inset-0 z-0 opacity-20 ...")` inside `Telemetry::LiveStream`.

---

## 8. Turbo Integration (Streams & Frames)

### 8.1 Turbo Streams

Real-time DOM updates delivered over `ActionCable` (Solid Cable).

| Stream | Subscribed In | Updated By |
|---|---|---|
| `"telemetry_stream"` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` (queue: `uplink`) |
| `@wallet, :transactions` | `Wallets::Show` | `BlockchainMintingService` / TX workers |

**Pattern:**

```ruby
# Subscribe (in component view_template)
turbo_stream_from @wallet, :transactions

# Broadcast (in worker/service)
Turbo::StreamsChannel.broadcast_prepend_to(
  [@wallet, :transactions],
  target: "transactions_ledger",
  partial: "wallets/transaction_row",
  locals: { tx: new_tx }
)
```

### 8.2 Turbo Frames (Lazy Loading)

Used to defer expensive data fetches until after the initial page paint.

| Frame | Used In | Source URL |
|---|---|---|
| `wallet_balance_frame_{id}` | `Wallets::Show` | `balance_api_v1_wallet_path(@wallet)` |
| `wallet_metadata_frame_{id}` | `Wallets::Show` | `metadata_api_v1_wallet_path(@wallet)` |
| `simulation_results` | `OracleVisions::SimulationPanel` | Turbo form target |

**Skeleton pattern:**

```ruby
turbo_frame_tag "wallet_balance_frame_#{@wallet.id}",
                src: balance_api_v1_wallet_path(@wallet),
                loading: :lazy do
  render Views::Shared::UI::Skeleton.new(variant: :balance)
end
```

### 8.3 Turbo Target IDs (for Worker Broadcasts)

Named DOM targets used by Sidekiq workers to inject real-time content:

| Target ID | Component | Updated By |
|---|---|---|
| `wallet_balance_{id}` | `Wallets::BalanceDisplay` | `BlockchainMintingService` |
| `transactions_ledger` | `Wallets::Show` | TX confirmation workers |
| `telemetry_feed` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` |
| `ota_progress_{uid}` | `Firmwares::OtaProgressBar` | `OtaTransmissionWorker` |
| `alert_badge_{id}` | `Alerts::Badge` | `EwsAlertWorker` |

---

## 9. Accessibility Checklist

All components are audited against this checklist:

| Rule | Implementation |
|---|---|
| `role` on semantic elements | `role="table"` on tables, `role="status"` on badges, `role="navigation"` on sidebar, `role="group"` on StatCard |
| `aria-label` on interactive elements | All `<button>` and `<a>` elements have descriptive `aria_label:` |
| `aria-current="page"` | Active nav items in `Navigation::Sidebar` |
| `scope="col"` on `<th>` | All table headers |
| `focus-visible:` not `focus:` | 100% compliance across all 67+ components |
| `aria-hidden="true"` on decorative elements | Sidebar icons, background text watermarks |
| Keyboard-navigable focus rings | `focus-visible:ring-2 focus-visible:ring-gaia-primary` on all interactive elements |
| Color contrast | Semantic tokens guarantee WCAG AA in both light and dark modes |
| `disabled:opacity-50 disabled:cursor-not-allowed` | All disabled buttons (e.g., PhotoCard delete) |
| `role="status" aria-label="Loading…"` | `Skeleton` component |

### Standard Focus Pattern

```ruby
# ✅ Canonical focus ring for all interactive elements
class: "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"

# ✅ Transition pattern
class: "transition-all duration-200 ease-in-out"
class: "transition-colors duration-300"   # theme switches
```

---

## 10. Testing & Lookbook

### RSpec Component Tests

| Spec File | Examples | Coverage |
|---|---|---|
| `spec/views/shared/ui/status_badge_spec.rb` | 25 | All AASM states, semantic tokens, accessibility |
| `spec/views/shared/ui/stat_card_spec.rb` | 7 | Props, danger mode, class override |
| `spec/views/shared/ui/action_badge_spec.rb` | 8 | Pattern matching, semantic styles |
| `spec/views/shared/ui/empty_state_spec.rb` | 6 | Default, custom icon, table mode |
| `spec/views/shared/ui/meta_row_spec.rb` | 6 | Label/value, nil handling |
| `spec/views/shared/ui/relative_time_spec.rb` | 8 | Time intervals, edge cases |
| `spec/views/shared/web3/address_spec.rb` | 8 | Truncation, clipboard, nil fallback |
| `spec/views/shared/iot/metric_value_spec.rb` | 6 | Precision, nil, BigDecimal, unit |
| `spec/views/components/alerts/badge_spec.rb` | 12 | Severity × Status matrix |
| `spec/views/components/dashboard/event_row_spec.rb` | 10 | Polymorphic event types |
| `spec/views/components/wallets/transaction_row_spec.rb` | 14 | Token types, hash truncation |
| `spec/views/components/wallets/balance_display_spec.rb` | 8 | Balance rendering, Turbo target |
| `spec/views/components/actuators/card_spec.rb` | 16 | Status LED, matrix rendering |
| `spec/views/shared/ui/data_table_spec.rb` | 20 | Columns+rows, empty state, custom empty_message, design system compliance, accessibility, class override, single column |
| `spec/views/shared/ui/pagination_spec.rb` | 22 | Middle/first/last/single page, design system compliance, accessibility, focus-visible, invalid pagy guard |
| `spec/views/shared/ui/photo_card_spec.rb` | 17 | Initialization, validation, design system compliance, editable true/false, typography |

**Total:** **193** · **0 failures**

### Lookbook (Component Explorer)

Lookbook provides a live preview of all components at `http://localhost:3000/lookbook` (development only).

**Preview files:** `spec/components/previews/`

| Preview | Scenarios |
|---|---|
| `StatusBadgePreview` | All AASM states, Transaction lifecycle, Interactive |
| `StatCardPreview` | Default, Danger, Minimal, Interactive |
| `ActionBadgePreview` | All 4 action types, Interactive |
| `EmptyStatePreview` | Grid, Custom icon, Minimal |
| `MetaRowPreview` | Default, Numeric, Interactive |
| `AlertBadgePreview` | Severity × Status matrix (9 combos), Interactive |
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

_Document reverse-shaped (Cycle 1) from:_
`app/views/components/` · `app/views/shared/` · `app/javascript/controllers/` · `config/tailwind.config.js` · `app/assets/tailwind/application.css` · `docs/COMPONENTS.md` · `docs/FRONTEND_GUIDELINES.md`
