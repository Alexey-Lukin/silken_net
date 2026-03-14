# 🎨 Gaia 2.0 — Frontend Guidelines

> Canonical reference for building UI in SilkenNet.
> Stack: **Rails 8.1 · Phlex · Tailwind CSS 4 · Stimulus · Turbo · Dark-First Design**

---

## Table of Contents

1. [Dark-First Philosophy & Semantic Colors](#1-dark-first-philosophy--semantic-colors)
2. [Phlex Components (DRY Principle)](#2-phlex-components-dry-principle)
3. [TailwindMerge Pattern & Custom Classes](#3-tailwindmerge-pattern--custom-classes)
4. [Pagination (Pagy) & Avoiding N+1](#4-pagination-pagy--avoiding-n1)
5. [Typography Scale](#5-typography-scale)
6. [File & Naming Conventions](#6-file--naming-conventions)
7. [Stimulus Controllers](#7-stimulus-controllers)
8. [Accessibility Checklist](#8-accessibility-checklist)

---

## 1. Dark-First Philosophy & Semantic Colors

### Core Principle

Gaia 2.0 is designed **dark-first**. The dark theme is the primary visual identity — a terminal-aesthetic with glowing emerald accents on pure black backgrounds. Light mode is a secondary, high-contrast alternative.

### How It Works

1. **CSS Custom Properties** define all colors in `app/assets/tailwind/application.css`:
   - Dark values are applied inside `.dark { ... }` (which is the default).
   - Light values are applied in the root `:root { ... }` scope.

2. **Tailwind config** (`tailwind.config.js`) maps semantic token names to CSS variables:
   ```js
   colors: {
     "gaia-surface":     "var(--color-gaia-surface)",     // #000 dark, #fff light
     "gaia-text":        "var(--color-gaia-text)",         // emerald dark, dark-gray light
     "status-danger":    "var(--color-status-danger)",     // red bg
     "token-carbon":     "var(--color-token-carbon)",      // SCC green
     // ... etc.
   }
   ```

3. **Theme switching** is handled by `theme_controller.js` (Stimulus), which toggles the `.dark` class on `<html>`. User preference persists in `localStorage`, with OS media query fallback.

### Rules for Developers

| ✅ Do | ❌ Don't |
|-------|---------|
| Use `bg-gaia-surface` for backgrounds | Use `bg-black` or `bg-white` directly |
| Use `text-gaia-text` for primary text | Use `text-gray-900` or `text-emerald-400` directly |
| Use `border-gaia-border` for dividers | Use `border-gray-200` or `border-emerald-900` |
| Use `bg-status-danger text-status-danger-text` for errors | Use `bg-red-100 text-red-800` |
| Use `text-status-warning-text` for pending states | Use `text-amber-500` |
| Use `shadow-sm dark:shadow-none` for cards | Use `shadow-lg` everywhere |

### Semantic Color Token Reference

| Token | Dark Value | Light Value | Use Case |
|-------|-----------|-------------|----------|
| `gaia-surface` | `#000000` | `#ffffff` | Card/panel backgrounds |
| `gaia-surface-alt` | `#0a0a0a` | `#f3f4f6` | Table headers, secondary panels |
| `gaia-text` | `#10b981` | `#111827` | Primary text |
| `gaia-text-muted` | `#065f46` | `#6b7280` | Labels, metadata |
| `gaia-primary` | `#10b981` | `#10b981` | Brand emerald (both modes) |
| `gaia-border` | `rgba(16,185,129,0.2)` | `#e5e7eb` | Borders |
| `status-danger` | `#7f1d1d` | `#fee2e2` | Error background |
| `status-danger-text` | `#fecaca` | `#991b1b` | Error text |
| `status-warning` | `#78350f` | `#fef3c7` | Warning background |
| `status-warning-text` | `#fde68a` | `#92400e` | Warning text |
| `status-success` | `#065f46` | `#d1fae5` | Success background |
| `status-success-text` | `#d1fae5` | `#065f46` | Success text |
| `token-carbon` | `#059669` | `#047857` | SCC token color |
| `token-forest` | `#d97706` | `#b45309` | SFC token color |

### Adding New Status Colors

1. Define CSS variables in `app/assets/tailwind/application.css` for both `:root` and `.dark`.
2. Register the token in `tailwind.config.js` under `theme.extend.colors`.
3. Use the token name in Phlex components via Tailwind classes.

---

## 2. Phlex Components (DRY Principle)

### Architecture

All views are **Phlex components** (Ruby classes inheriting `ApplicationComponent`):

```
app/views/
├── components/           # Domain-specific page components
│   ├── trees/
│   │   ├── index.rb      # Trees::Index
│   │   └── show.rb       # Trees::Show
│   ├── wallets/
│   │   ├── index.rb
│   │   ├── show.rb
│   │   ├── balance_display.rb
│   │   └── transaction_row.rb
│   └── ...
├── shared/
│   ├── ui/               # Reusable UI primitives
│   │   ├── status_badge.rb
│   │   ├── stat_card.rb
│   │   ├── data_table.rb
│   │   ├── pagination.rb
│   │   ├── empty_state.rb
│   │   ├── meta_row.rb
│   │   ├── action_badge.rb
│   │   ├── photo_card.rb
│   │   ├── relative_time.rb
│   │   └── theme_switcher.rb
│   ├── iot/              # IoT-specific display
│   │   └── metric_value.rb
│   └── web3/             # Web3-specific display
│       └── address.rb
└── layouts/
```

### Rendering Components

```ruby
# From a controller
def show
  render Trees::Show.new(tree: @tree, wallet: @wallet, recent_logs: @logs)
end

# From another component
render Views::Shared::UI::StatusBadge.new(status: @tx.status)
render Views::Shared::UI::StatCard.new(label: "Trees", value: "12,847", sub: "active")
render Views::Shared::Web3::Address.new(address: @wallet.crypto_public_address)
render Views::Shared::IoT::MetricValue.new(value: 3.14, unit: "σ")
```

### Component Structure Pattern

Every component follows this structure:

```ruby
# frozen_string_literal: true

module Trees
  class Show < ApplicationComponent
    def initialize(tree:, wallet:, recent_logs:)
      @tree = tree
      @wallet = wallet
      @recent_logs = recent_logs
    end

    def view_template
      div(class: "space-y-8") do
        render_header
        render_details
      end
    end

    private

    def render_header
      # ...
    end

    def render_details
      # ...
    end
  end
end
```

### Key Rules

1. **Controllers are thin** — pass pre-loaded data to components via constructor args.
2. **No database queries in views** — all data must be pre-loaded in the controller.
3. **Extract long class strings** into private methods:
   ```ruby
   # ✅ Good
   div(class: card_classes) { ... }

   def card_classes
     "p-6 border border-gaia-border bg-gaia-surface hover:border-gaia-primary transition-all"
   end

   # ❌ Bad — inline 100-char class strings
   div(class: "p-6 border border-gaia-border bg-gaia-surface hover:border-gaia-primary transition-all") { ... }
   ```
4. **Shared UI components** live in `app/views/shared/ui/` and are referenced with the `Views::Shared::UI::` namespace.
5. **Domain components** live in `app/views/components/<resource>/` and use the resource module namespace.

### Available Shared Components

| Component | Usage | Key Props |
|-----------|-------|-----------|
| `StatusBadge` | AASM state badges (20+ states) | `status:`, `class:` |
| `StatCard` | Dashboard metric card | `label:`, `value:`, `sub:`, `danger:` |
| `DataTable` | Reusable table wrapper | `columns:`, `empty_message:` |
| `Pagination` | Pagy-based pagination | `pagy:`, `url_helper:` |
| `EmptyState` | Empty data placeholder | `title:`, `description:`, `icon:`, `colspan:` |
| `MetaRow` | Key-value display | `label:`, `value:` |
| `ActionBadge` | Audit action badges | `action:` |
| `PhotoCard` | Photo with lazy loading | `photo:`, `record:`, `editable:` |
| `RelativeTime` | "5 minutes ago" display | `datetime:`, `prefix:` |
| `ThemeSwitcher` | Dark/light toggle | — |
| `IoT::MetricValue` | Numeric with precision | `value:`, `unit:`, `precision:` |
| `Web3::Address` | Ethereum address + copy | `address:`, `fallback:` |

---

## 3. TailwindMerge Pattern & Custom Classes

### The Problem

Tailwind classes can conflict. For example, `text-tiny` (font-size) and `text-emerald-500` (color) look like they should conflict because both start with `text-`. TailwindMerge resolves this intelligently.

### ApplicationComponent Setup

```ruby
class ApplicationComponent < Phlex::HTML
  CUSTOM_TEXT_SCALE = %w[micro mini tiny compact].freeze

  def tokens(*args, **conditions)
    result = args.compact.join(" ")
    conditional = conditions.filter_map { |cls, flag| cls.to_s if flag }.join(" ")
    combined = [result, conditional].reject(&:empty?).join(" ")
    self.class.merger.merge(combined)
  end

  def self.merger
    @merger ||= TailwindMerge::Merger.new(config: {
      theme: { "text" => CUSTOM_TEXT_SCALE }
    })
  end
end
```

### Using `tokens()` for Conditional Classes

```ruby
# Static + conditional classes
span(class: tokens(
  "px-2 py-0.5 text-mini uppercase font-bold",
  "bg-status-danger text-status-danger-text": alert.severity_critical?,
  "bg-status-warning text-status-warning-text": alert.severity_medium?,
  "bg-emerald-900 text-emerald-200": alert.severity_low?
))
```

### Passing Custom Classes to Shared Components

Shared UI components accept a `class:` keyword that gets merged with defaults:

```ruby
# Component definition
def initialize(status:, **attrs)
  @status = status
  @extra_classes = attrs[:class]
end

def view_template
  span(class: tokens(base_classes, @extra_classes)) { @status }
end

# Usage — custom classes merge cleanly
render Views::Shared::UI::StatusBadge.new(status: "confirmed", class: "mt-2")
```

### Class Grouping Order

When writing Tailwind classes, follow this order for consistency:

1. **Layout**: `flex`, `grid`, `block`, `relative`, `absolute`
2. **Spacing**: `p-4`, `gap-2`, `m-0`
3. **Sizing**: `w-full`, `h-4`, `max-w-xl`
4. **Typography**: `text-tiny`, `font-mono`, `uppercase`, `tracking-widest`
5. **Visual**: `bg-gaia-surface`, `border`, `text-gaia-text`, `shadow-sm`
6. **Interactive**: `hover:`, `focus-visible:`, `transition-all`, `duration-200`

---

## 4. Pagination (Pagy) & Avoiding N+1

### Pagy Setup

All paginated views use Pagy via the shared `Pagination` component:

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

### The `url_helper` Lambda

The `Pagination` component requires a lambda that generates URLs for each page. This decouples pagination from specific routes:

```ruby
url_helper: ->(page:) { helpers.api_v1_wallets_path(page: page) }
url_helper: ->(page:) { helpers.api_v1_alerts_path(page: page, severity: params[:severity]) }
```

### Avoiding N+1 Queries

**Rule: All data displayed in views MUST be pre-loaded in the controller.** No lazy-loading in Phlex components.

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

### Pre-loading Patterns

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

### Groupdate Integration

For time-series aggregation in reports:

```ruby
# Controller
@daily_counts = TelemetryLog.where(tree: @cluster.trees)
                             .group_by_day(:created_at)
                             .count
```

---

## 5. Typography Scale

Custom terminal-aesthetic font sizes defined via CSS custom properties:

| Token | Utility Class | Size | Use Case |
|-------|--------------|------|----------|
| `--font-size-micro` | `text-micro` | 8px | Micro labels, file sizes, role badges |
| `--font-size-mini` | `text-mini` | 9px | Uppercase nav items, status badges |
| `--font-size-tiny` | `text-tiny` | 10px | Small labels, metadata, descriptions |
| `--font-size-compact` | `text-compact` | 11px | Data tables, addresses, metrics |

**Never use arbitrary values** like `text-[9px]`. Always use the semantic tokens above.

These are registered in `ApplicationComponent` as `CUSTOM_TEXT_SCALE` so TailwindMerge correctly distinguishes font-size tokens from color tokens.

---

## 6. File & Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Shared UI component | `app/views/shared/ui/<name>.rb` | `status_badge.rb` |
| Domain component | `app/views/components/<resource>/<action>.rb` | `trees/show.rb` |
| Component module | `Module::<Resource>::<Action>` | `Trees::Show` |
| Shared UI module | `Views::Shared::UI::<Name>` | `Views::Shared::UI::StatusBadge` |
| Lookbook preview | `spec/components/previews/<name>_preview.rb` | `status_badge_preview.rb` |
| Preview template | `spec/components/previews/<name>_preview/<scenario>.html.erb` | `all_states.html.erb` |
| Component spec | `spec/views/components/<resource>/<name>_spec.rb` | `actuators/card_spec.rb` |
| Shared spec | `spec/views/shared/ui/<name>_spec.rb` | `status_badge_spec.rb` |

---

## 7. Stimulus Controllers

| Controller | File | Purpose |
|------------|------|---------|
| `theme` | `theme_controller.js` | Dark/light toggle via `localStorage` + OS query |
| `clipboard` | `clipboard_controller.js` | Copy-to-clipboard for Web3 addresses |

### Theme Controller Usage

```html
<div data-controller="theme">
  <button data-action="theme#toggle">
    <span data-theme-target="icon"></span>
  </button>
</div>
```

The controller reads from `localStorage.getItem("theme")`, falls back to `prefers-color-scheme: dark`, and toggles the `.dark` class on `<html>`.

---

## 8. Accessibility Checklist

Every component must satisfy:

- [ ] **`role` attributes** on tables (`role="table"`) and status elements (`role="status"`)
- [ ] **`aria-label`** on all interactive elements (buttons, links)
- [ ] **`scope="col"`** on table headers
- [ ] **`focus-visible:` instead of `focus:`** — keyboard users see focus rings, mouse users don't
- [ ] **`aria-hidden="true"`** on decorative elements (icons, background text)
- [ ] **`alt` text** on images
- [ ] **Color contrast** — semantic tokens guarantee WCAG AA in both modes
- [ ] **`disabled:opacity-50 disabled:cursor-not-allowed`** on disabled buttons

### Focus Ring Pattern

```ruby
# ✅ Always use focus-visible: (not focus:)
class: "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
```

### Transition Pattern

```ruby
# ✅ Always specify duration and easing
class: "transition-all duration-200 ease-in-out"
class: "transition-colors duration-200"
```

---

## Quick Reference Card

```ruby
# Render a status badge
render Views::Shared::UI::StatusBadge.new(status: "confirmed")

# Render a stat card
render Views::Shared::UI::StatCard.new(label: "Trees", value: "1,000", sub: "active")

# Render pagination
render Views::Shared::UI::Pagination.new(pagy: @pagy, url_helper: ->(page:) { path(page: page) })

# Render an empty state in a table
render Views::Shared::UI::EmptyState.new(title: "No data.", colspan: 5)

# Conditional classes
span(class: tokens("text-tiny uppercase", "text-red-500": danger?, "text-emerald-500": !danger?))

# Web3 address with copy button
render Views::Shared::Web3::Address.new(address: "0x1234...")

# IoT metric value
render Views::Shared::IoT::MetricValue.new(value: 3800, unit: "mV", precision: 0)
```

---

## Lookbook (Component Explorer)

**URL:** `http://localhost:3000/lookbook` (development only)

Preview files live in `spec/components/previews/`. See `docs/COMPONENTS.md` for the full catalog of available previews and how to create new ones.

```ruby
# spec/components/previews/my_component_preview.rb
# @label My Component
# @display bg_color "#000"
class MyComponentPreview < Lookbook::Preview
  # @label Default
  def default
    render Views::Shared::UI::MyComponent.new(prop: "value")
  end

  # @label Interactive
  # @param prop text
  def interactive(prop: "default")
    render Views::Shared::UI::MyComponent.new(prop: prop)
  end
end
```
