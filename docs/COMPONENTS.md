# 🧩 Gaia 2.0 — Component Design System & Styleguide

> Living documentation for Phlex UI components in SilkenNet.
> Last audited against the **29 TailwindCSS Best Practices Manifesto**.

---

## Design Tokens

### Typography Scale

Custom terminal-aesthetic font sizes defined in `app/assets/tailwind/application.css`:

| Token         | Utility       | Size   | Use case                             |
|---------------|---------------|--------|--------------------------------------|
| `--font-size-micro`   | `text-micro`   | 8px    | Micro labels, file sizes, role text  |
| `--font-size-mini`    | `text-mini`    | 9px    | Uppercase nav items, status badges   |
| `--font-size-tiny`    | `text-tiny`    | 10px   | Small labels, metadata, descriptions |
| `--font-size-compact` | `text-compact` | 11px   | Data tables, addresses, metrics      |

**Rule 1 compliance:** These eliminate all arbitrary `text-[Npx]` values.

### Semantic Color Tokens

All status, token, and surface colors are **dynamic** — they automatically switch between high-contrast light and glowing dark palettes via CSS custom properties:

| Token                        | Light Mode         | Dark Mode          | Use case                        |
|------------------------------|--------------------|--------------------|----------------------------------|
| `gaia-surface`               | `#ffffff`          | `#000000`          | Card/form backgrounds            |
| `gaia-surface-alt`           | `#f3f4f6`          | `#0a0a0a`          | Table headers, secondary panels  |
| `gaia-text`                  | `#111827`          | `#10b981`          | Primary text                     |
| `gaia-text-muted`            | `#6b7280`          | `#065f46`          | Labels, metadata, placeholders   |
| `gaia-primary`               | `#10b981`          | `#10b981`          | Primary brand (emerald)          |
| `gaia-border`                | `#e5e7eb`          | `rgba(16,185,129,0.2)` | Borders, dividers           |
| `status-danger`              | `#fee2e2`          | `#7f1d1d`          | Error/danger background          |
| `status-danger-text`         | `#991b1b`          | `#fecaca`          | Error/danger text                |
| `status-danger-accent`       | `#dc2626`          | `#ef4444`          | Error/danger accent (values)     |
| `status-warning`             | `#fef3c7`          | `#78350f`          | Warning/processing background    |
| `status-warning-text`        | `#92400e`          | `#fde68a`          | Warning/processing text          |
| `status-info`                | `#dbeafe`          | `#1e3a5f`          | Informational background         |
| `status-info-text`           | `#1e40af`          | `#bfdbfe`          | Informational text               |
| `status-success`             | `#d1fae5`          | `#065f46`          | Success background               |
| `status-success-text`        | `#065f46`          | `#d1fae5`          | Success text                     |
| `status-active`              | `#ccfbf1`          | `#064e3b`          | Acknowledged/creative bg         |
| `status-active-text`         | `#115e59`          | `#a7f3d0`          | Acknowledged/creative text       |
| `status-neutral`             | `#f3f4f6`          | `#27272a`          | Neutral/inactive background      |
| `status-neutral-text`        | `#4b5563`          | `#a1a1aa`          | Neutral/inactive text            |
| `token-carbon`               | `#047857`          | `#059669`          | SCC token color                  |
| `token-forest`               | `#b45309`          | `#d97706`          | SFC token color                  |
| `gaia-input-bg`              | `#ffffff`          | `#09090b`          | Form input backgrounds           |
| `gaia-input-border`          | `#d1d5db`          | `rgba(16,185,129,0.3)` | Form input borders          |
| `gaia-input-text`            | `#111827`          | `#d1fae5`          | Form input text                  |
| `gaia-label`                 | `#6b7280`          | `#6b7280`          | Form field labels                |

**Rule 2 compliance:** All status-related colors use semantic tokens, not raw Tailwind colors.

### Light Mode Depth

In light mode, cards and panels use `shadow-sm` for visual depth. In dark mode, shadows are disabled
(`dark:shadow-none`) and depth is conveyed through border contrast instead. This is applied to:
- `StatCard`, `DataTable`, `PhotoCard`, `Actuators::Card`
- All form components (`Maintenance::Form`, `Firmwares::Form`, `TreeFamilies::Form`)

---

## TailwindMerge Configuration

The `ApplicationComponent` configures `TailwindMerge::Merger` to recognize our custom font sizes:

```ruby
# app/views/components/application_component.rb
CUSTOM_TEXT_SCALE = %w[micro mini tiny compact].freeze

def self.merger
  @merger ||= TailwindMerge::Merger.new(config: {
    theme: { "text" => CUSTOM_TEXT_SCALE }
  })
end
```

This ensures `text-tiny` (font-size) and `text-status-warning-text` (text-color) coexist
without TailwindMerge incorrectly merging them as conflicting classes.

---

## Shared UI Components (`app/views/shared/ui/`)

### StatusBadge

AASM state badge with 20+ predefined status styles.

```ruby
render Views::Shared::UI::StatusBadge.new(status: "confirmed")
render Views::Shared::UI::StatusBadge.new(status: "processing", class: "mt-2")
```

| Prop      | Type          | Default | Description                          |
|-----------|---------------|---------|--------------------------------------|
| `status:` | String/Symbol | —       | AASM state name                      |
| `id:`     | String        | `nil`   | Optional HTML id                     |
| `class:`  | String        | `nil`   | Override/extend classes (Rule 13)    |

**Status → Style Mapping:**

| Status           | Semantic Tokens                                 |
|------------------|-------------------------------------------------|
| pending, issued  | `bg-status-warning text-status-warning-text`    |
| processing, triggered, updating | `+ animate-pulse`               |
| confirmed, fulfilled | `bg-status-success text-status-success-text` |
| failed, active, breached, deceased, faulty | `bg-status-danger text-status-danger-text` |
| acknowledged     | `bg-status-active text-status-active-text`      |
| idle, draft, expired, offline | `bg-status-neutral text-status-neutral-text` |

---

### StatCard

Dashboard metric card with label, value, optional subtitle, and danger highlight.

```ruby
render Views::Shared::UI::StatCard.new(label: "Active Trees", value: "12,847", sub: "nodes")
render Views::Shared::UI::StatCard.new(label: "Alerts", value: "3", danger: true)
```

| Prop      | Type    | Default | Description                       |
|-----------|---------|---------|-----------------------------------|
| `label:`  | String  | —       | Metric label (uppercase)          |
| `value:`  | Any     | —       | Primary value to display          |
| `sub:`    | String  | `nil`   | Subtitle/unit text                |
| `danger:` | Boolean | `false` | Red highlight for critical values |
| `class:`  | String  | `nil`   | Override wrapper classes           |

**Rules applied:** No hardcoded margins (Rule 17), `gap-2` instead of `space-x-2` (Rule 8), `leading-tight` on value (Rule 21).

---

### DataTable

Reusable table wrapper with configurable columns and body rendering via block.

```ruby
render Views::Shared::UI::DataTable.new(
  columns: [
    { label: "ID", class: "w-20" },
    { label: "Name" },
    { label: "Status" }
  ]
) do
  # render table rows here
end
```

| Prop             | Type   | Default             | Description                |
|------------------|--------|---------------------|----------------------------|
| `columns:`       | Array  | —                   | Column definitions         |
| `empty_message:` | String | "No records found." | Fallback for empty tables  |
| `class:`         | String | `nil`               | Override wrapper classes    |

---

### ActionBadge

Action-type badge (destructive, mutative, creative, neutral) for audit logs.

```ruby
render Views::Shared::UI::ActionBadge.new(action: "create_user")
render Views::Shared::UI::ActionBadge.new(action: "delete_tree")
```

| Prop      | Type   | Default | Description                             |
|-----------|--------|---------|-----------------------------------------|
| `action:` | String | —       | Action name (matched via regex)         |
| `class:`  | String | `nil`   | Override classes                         |

**Pattern Matching:**
- `/delete|destroy|remove/` → destructive (danger)
- `/update|modify|change/` → mutative (warning)
- `/create|add|new/` → creative (active)
- Everything else → neutral

---

### EmptyState

Placeholder for empty data areas — supports both div (grid) and table row modes.

```ruby
# Grid mode
render Views::Shared::UI::EmptyState.new(title: "No data available", description: "Try adjusting filters.")

# Table mode
render Views::Shared::UI::EmptyState.new(title: "No records.", colspan: 5)
```

| Prop           | Type    | Default | Description                    |
|----------------|---------|---------|--------------------------------|
| `title:`       | String  | —       | Primary message                |
| `description:` | String  | `nil`   | Secondary explanation          |
| `icon:`        | String  | `"○"`   | Decorative icon (aria-hidden)  |
| `colspan:`     | Integer | `nil`   | If set, renders as `<tr><td>`  |

---

### MetaRow

Key-value display row for detail pages.

```ruby
render Views::Shared::UI::MetaRow.new(label: "Firmware", value: "v2.1.3")
```

| Prop     | Type   | Default | Description          |
|----------|--------|---------|----------------------|
| `label:` | String | —       | Key text             |
| `value:` | Any    | —       | Value text           |
| `class:` | String | `nil`   | Override classes      |

**Rule 8 compliance:** Uses `gap-2` instead of `ml-2` for spacing.

---

### Pagination

Pagy-based pagination navigation with previous/next links.

```ruby
render Views::Shared::UI::Pagination.new(
  pagy: @pagy,
  url_helper: ->(page:) { api_v1_trees_path(page: page) }
)
```

| Prop          | Type   | Default | Description                     |
|---------------|--------|---------|---------------------------------|
| `pagy:`       | Pagy   | —       | Pagination metadata object      |
| `url_helper:` | Lambda | —       | URL builder accepting `page:`   |

**Rules applied:** `focus-visible:` (Rule 26), no hardcoded `mt-6` (Rule 17), explicit `duration-200 ease-in-out` (Rule 27).

---

### PhotoCard

Photo gallery card with lazy loading, hover overlay, and optional delete button.

```ruby
render Views::Shared::UI::PhotoCard.new(photo: blob, record: @record, editable: true)
```

| Prop        | Type    | Default | Description                |
|-------------|---------|---------|----------------------------|
| `photo:`    | Blob    | —       | ActiveStorage blob         |
| `record:`   | Record  | —       | Parent record for delete   |
| `editable:` | Boolean | `false` | Show delete button         |

**Rules applied:** `group`/`group-hover:` for nested interactions (Rule 29), `focus-visible:` (Rule 26), `disabled:opacity-50 disabled:cursor-not-allowed` (Rule 28), `gap-1` instead of `space-y-1` (Rule 8).

---

### RelativeTime

Displays relative time ("5 minutes ago") with full timestamp tooltip.

```ruby
render Views::Shared::UI::RelativeTime.new(datetime: @tree.last_seen_at)
render Views::Shared::UI::RelativeTime.new(datetime: @alert.created_at, prefix: "Created ")
```

| Prop        | Type   | Default                      | Description            |
|-------------|--------|------------------------------|------------------------|
| `datetime:` | Time   | —                            | Time object (or nil)   |
| `css_class:`| String | `"text-emerald-900 text-tiny font-mono"` | CSS classes  |
| `prefix:`   | String | `nil`                        | Text before time       |

---

## Shared Helper Components

### Web3::Address (`app/views/shared/web3/address.rb`)

Ethereum address display with truncation and clipboard copy.

```ruby
render Views::Shared::Web3::Address.new(address: "0x1234567890abcdef...")
```

**Rules applied:** `focus-visible:` (Rule 26), `transition-colors duration-200` (Rule 27), `stroke="currentColor"` on SVG (Rule 18).

### IoT::MetricValue (`app/views/shared/iot/metric_value.rb`)

Numeric value display with configurable precision and unit.

```ruby
render Views::Shared::IoT::MetricValue.new(value: 3.14159, unit: "σ", precision: 4)
```

---

## 29-Rule Compliance Summary

### ✅ Fully Applied (all 67 components + shared/ui + layout + navigation)

| Rule | Description                            | Status |
|------|----------------------------------------|--------|
| 1    | No arbitrary values                    | ✅ All `text-[Npx]` replaced with `text-micro/mini/tiny/compact` across 63+ files |
| 2    | Semantic colors for states             | ✅ All amber → `status-warning`/`token-forest` tokens (20 files) |
| 6    | No @apply in Phlex                     | ✅ Ruby methods only |
| 7    | Mobile-first                           | ✅ Default = mobile, md: for desktop |
| 8    | gap- instead of margins                | ✅ Replaced `space-x`/`space-y` → `gap` in flex/grid (26+ files) |
| 10   | grid for 2D, flex for 1D              | ✅ Correct usage throughout |
| 11   | Prevent horizontal scroll              | ✅ overflow-x-auto on tables |
| 13   | Class override via tokens()            | ✅ `**attrs` pattern on shared/ui components |
| 14   | Logical class grouping                 | ✅ Layout→Spacing→Type→Visual→Interactive |
| 15   | Extract long class strings             | ✅ Private methods in shared/ui |
| 17   | No hardcoded margins in components     | ✅ Removed mt-6, mb-4, mb-2 from shared/ui |
| 18   | SVGs use currentColor                  | ✅ stroke="currentColor" |
| 20   | tracking-widest for uppercase          | ✅ Added where missing |
| 21   | leading-tight for headings             | ✅ Applied to h1 |
| 25   | hover/focus/active states              | ✅ All interactive elements |
| 26   | focus-visible: instead of focus:       | ✅ **All 67+ components** — zero focus: violations remain |
| 27   | Transitions with duration/ease         | ✅ duration-200 ease-in-out on shared/ui |
| 28   | disabled: states                       | ✅ On delete button |
| 29   | group/group-hover nested interactions  | ✅ PhotoCard, Sidebar |

### ⏳ Low-Priority Remaining Work

| Rule | Description                            | Status |
|------|----------------------------------------|--------|
| 3    | Dark mode definitions                  | ✅ Light/dark dynamic status colors implemented via CSS custom properties |
| 13   | Class override on domain components    | ⏳ Shared/ui has `**attrs`; domain components are page-level (less need) |
| 15   | Extract classes in domain components   | ⏳ Long inline strings remain in some domain views |
| 17   | Margins in domain page components      | ⏳ Page-level margins (`mb-4`, `mt-6`) are acceptable in non-reusable views |

---

## Component Preview — Lookbook

**Lookbook** (`lookbook` gem) is the Rails equivalent of Storybook for React/Vue.
It provides live previews, parameter playgrounds, and auto-generated docs for components.

**Status:** ✅ Installed and configured.

### Setup

```ruby
# Gemfile (development group)
gem "lookbook"
gem "view_component"

# config/routes.rb
mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?

# config/application.rb
config.lookbook.preview_paths = [ root.join("spec/components/previews").to_s ]
```

### Access

Run `bin/rails server` and navigate to **http://localhost:3000/lookbook**

### Available Previews

| Preview                      | Scenarios                                     |
|------------------------------|-----------------------------------------------|
| `StatusBadgePreview`         | All AASM states, Transaction lifecycle, Interactive param selector |
| `StatCardPreview`            | Default, Danger mode, Minimal, Interactive    |
| `ActionBadgePreview`         | All action types (creative/mutative/destructive/neutral), Interactive |
| `EmptyStatePreview`          | Default grid, Custom icon, Minimal            |
| `MetaRowPreview`             | Default, Numeric, Interactive                 |
| `AlertBadgePreview`          | Severity × Status matrix (9 combos), Interactive |
| `DashboardEventRowPreview`   | EwsAlert, BlockchainTx, Maintenance, Unknown events |
| `SidebarPreview`             | Default, With alerts badge, Telemetry active, Interactive |
| `Web3AddressPreview`         | Valid, Short, Nil fallback, Custom fallback, Interactive |
| `IoTMetricValuePreview`      | Default, High precision, Nil, No unit, Interactive |
| `DataTablePreview`           | Default with sample rows, Empty state         |
| `PaginationPreview`          | First page, Middle page, Last page            |
| `RelativeTimePreview`        | Recent, With prefix, Nil datetime             |
| `ThemeSwitcherPreview`       | Default toggle button                         |
| `WalletTransactionRowPreview`| Confirmed carbon, Pending forest, Failed, Processing, Interactive |
| `WalletBalanceDisplayPreview`| Tree wallet, Locked funds, Organization wallet, Zero balance, Interactive |
| `ClusterItemPreview`         | Healthy cluster, Under threat, Low health, Interactive |
| `ActuatorCommandStatusBadgePreview` | All command statuses, Interactive      |
| `ActuatorCommandRowPreview`  | Confirmed open, Issued activate, Failed close, Interactive |
| `PhotoCardPreview`           | Image photo (mock layout), File fallback (mock layout) |

### Creating New Previews

```ruby
# spec/components/previews/my_component_preview.rb
class MyComponentPreview < Lookbook::Preview
  # @param status select { choices: [pending, confirmed, failed] }
  def interactive(status: "pending")
    render Views::Shared::UI::StatusBadge.new(status: status)
  end
end
```

---

## Test Coverage

### Shared Components (`spec/views/shared/`)

| Test File                             | Examples | What's Tested                                    |
|---------------------------------------|----------|--------------------------------------------------|
| `shared/ui/status_badge_spec.rb`      | 25       | AASM state mapping, accessibility, semantic tokens |
| `shared/ui/stat_card_spec.rb`         | 7        | Props, danger mode, class override, accessibility |
| `shared/ui/action_badge_spec.rb`      | 8        | Pattern matching, semantic styles, accessibility  |
| `shared/ui/empty_state_spec.rb`       | 6        | Default state, custom icon, description           |
| `shared/ui/meta_row_spec.rb`          | 6        | Label/value rendering, nil handling               |
| `shared/ui/relative_time_spec.rb`     | 8        | Time intervals, edge cases                        |
| `shared/web3/address_spec.rb`         | 8        | Truncation, clipboard, nil fallback               |
| `shared/iot/metric_value_spec.rb`     | 6        | Precision, nil, BigDecimal, unit rendering        |

### Domain Components (`spec/views/components/`)

| Test File                                   | Examples | What's Tested                                    |
|---------------------------------------------|----------|--------------------------------------------------|
| `components/alerts/badge_spec.rb`           | 12       | Severity styles, status styles, rendering         |
| `components/dashboard/event_row_spec.rb`    | 10       | Event types (EwsAlert, Tx, Maintenance, Unknown) |
| `components/wallets/transaction_row_spec.rb`| 14       | Token types, status colors, hash truncation       |
| `components/wallets/balance_display_spec.rb`| 8        | Balance rendering, Turbo target, best practices   |
| `components/actuators/card_spec.rb`         | 16       | Status LED, matrix, container classes             |

**Total: 134 examples, 0 failures**
