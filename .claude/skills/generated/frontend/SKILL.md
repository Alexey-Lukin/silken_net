---
name: frontend
description: "Domain knowledge for Phlex + Tailwind v4 + Turbo + Stimulus frontend — design tokens, custom text scale, i18n (4 locales), Turbo streams"
---

# Frontend: Phlex + Tailwind v4 + Turbo + Stimulus

## Phlex Rules

- All components inherit `ApplicationComponent < Phlex::HTML` (`app/views/components/application_component.rb`).
- **No DB queries in `initialize`** — accept pre-loaded data only.
- Use `tokens(*static, **conditional)` for class composition; it runs TailwindMerge internally.
- Override `view_template` (not `template`) as the render entry point.
- `t(".key")` auto-scopes to the component class: `Alerts::Badge#t(".heading")` resolves to `I18n.t("alerts.badge.heading")`. Absolute keys (`t("flash.x")`) work as fallback.

## Design Tokens

- Shared components MUST use semantic tokens only: `bg-gaia-surface`, `text-gaia-text`, `bg-status-danger`, `text-status-danger-text`, `border-gaia-border`, etc. Full palette in `app/assets/tailwind/application.css` `@theme` block.
- Additional token families: `gaia-surface-{base,elevated,sunken,overlay}`, `gaia-text-{strong,muted,subtle}`, `gaia-primary{,-hover,-soft}`, `token-{carbon,forest}`, `gaia-input-{bg,border,text}`, `gaia-label`.
- Raw Tailwind utilities (`bg-red-100`, `text-zinc-300`) are allowed ONLY in domain-specific page components, never in shared/reusable ones.
- Light/dark theming via `.dark` class on `<html>` — CSS custom properties swap automatically.

## CSS

- `config/tailwind.config.js` is **DELETED**. The single source of truth is `app/assets/tailwind/application.css` (`@theme` block).
- Custom text scale (registered in `ApplicationComponent::CUSTOM_TEXT_SCALE` so TailwindMerge treats them as font-size, not color):
  - `text-micro` (8px), `text-mini` (9px), `text-tiny` (10px), `text-compact` (11px)
  - `text-display-sm`, `text-display-md`, `text-display-lg` (fluid clamp)
- Motion tokens: `--motion-fast` (150ms), `--motion-base` (220ms), `--motion-slow` (320ms); `--ease-out-soft`, `--ease-spring`.
- `@utility animate-fade-in` and `gaia-fade-in` keyframe available for entrance animations.
- Responsive tables: use `.gaia-responsive-table` with `data-label` on `<td>` for CSS-only card-flip on mobile.

## Turbo

- **Streams**: `"telemetry_stream"`, `[@wallet, :transactions]`, `"alert_badge_{id}"`, `"ota_progress_{uid}"`.
- **Frames (lazy)**: `wallet_balance_frame_{id}`, `wallet_metadata_frame_{id}`, `tree_chronicle_{id}`.
- ApplicationComponent includes `Phlex::Rails::Helpers::TurboStreamFrom` and `TurboFrameTag`.
- Turbo broadcasts render Phlex outside a controller context — `t()` falls back to `I18n.t` (no `helpers.translate`).

## Stimulus Controllers

| Controller | Purpose |
|------------|---------|
| `theme` | Light/dark toggle via `.dark` class + `localStorage`. Uses View Transitions API when available. |
| `clipboard` | Copy-to-clipboard utility. |
| `map` | Leaflet map with CartoDB Dark Matter tiles. Default center: Cherkasy, UA. |
| `matrix_rain` | Canvas hex rain animation (~16fps, GPU-composited). Decorative. |
| `mobile_nav` | Mobile navigation drawer toggle. |
| `reveal` | Show/hide content toggle. |

Controllers live in `app/javascript/controllers/`. Registered via `index.js`.

## i18n

- 4 locales: `en` (default), `uk`, `lv`, `lt`. Fallback chains: `uk -> en`, `lv -> en`, `lt -> en`.
- 34 domain locale files in `config/locales/<domain>/{en,uk,lv,lt}.yml`.
- Resolution: `params[:locale]` > `cookies[:locale]` > `Accept-Language` header > `:en`.
- CI gates: `i18n-tasks missing`, `check-consistent-interpolations`, `check-normalized`.
- Tests run in English by default. Test other locales explicitly: `I18n.with_locale(:uk) { ... }`.

## Gotchas

1. **Never create or reference `tailwind.config.js`** — it is deleted; all tokens live in `application.css @theme`.
2. **Always use design tokens** (`gaia-*`, `status-*`) in shared components. Raw utilities = domain pages only.
3. `CUSTOM_TEXT_SCALE` must stay in sync between `application.css @theme` and `ApplicationComponent`. If you add a custom font-size token, register it in both places.
4. Phlex components rendered in Turbo broadcasts have no Rails view context — never call `helpers.*` directly; use the `t()` override or `ActionController::Base.helpers` delegation.
5. `prefers-reduced-motion: reduce` is honoured globally — all `animation-duration` and `transition-duration` collapse to 0.01ms.
