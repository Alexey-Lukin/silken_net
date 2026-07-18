---
name: frontend
description: "Use when working on the silken_net frontend — the Phlex component tree (app/views/components/ + shared/ui|iot|web3/), the Tailwind v4 @theme design-token system (gaia-* surfaces/text, status-*, token-* blockchain, gaia-input-*), the ApplicationComponent base (the tokens() TailwindMerge wrapper + class-autoscoped t() i18n + Turbo-broadcast-safe delegated helpers), the 8 Stimulus controllers, and Turbo Streams/Frames. Knows the non-obvious gotchas — NO tailwind.config.js (SSOT = app/assets/tailwind/application.css @theme), raw Tailwind forbidden in shared components (use status-*/gaia-* tokens), register a new font-size in CUSTOM_TEXT_SCALE for TailwindMerge, NO DB queries in a Phlex initialize, t('.key') autoscopes by class name, specs default to English, Turbo broadcast_* runs in model context (no current_user). Routes to 04_04 (the design-system SSOT) + CLAUDE.md §6, does not restate. Examples: 'add a Phlex component', 'add a design token', 'why isn't my color class merging', 'add a Stimulus controller', 'i18n a component', 'a Turbo stream broadcast', 'why does a component spec render English'."
---

# Frontend (Phlex + Tailwind v4 + Turbo + Stimulus)

Navigation aid + non-obvious gotchas. The **SSOT is `04_04` + the code below** — this skill
points, it does not restate (so it can't drift). Verify a fact at its home before trusting a
summary. The view layer is **Phlex** (Ruby components, NOT ERB) on Rails 8.1, styled by
**Tailwind v4** (CSS-first `@theme`, no JS config), with **Turbo** + 8 **Stimulus** controllers.

## SSOT Documents — Read These First

| Document | What it covers |
|----------|----------------|
| `docs/04_04_Phlex_UI_and_Tailwind.md` | **The design-system SSOT** — §1 component hierarchy / render-flow / layout, §2 `ApplicationComponent`, §3 the token families (`gaia-*` surface+text, `status-*`, `token-*` blockchain, `gaia-input-*`) + colour-usage rules + the v3→v4 cheatsheet [DOC.11], §4 typography + motion scale, §5 TailwindMerge + `tokens()`, §6 the component registry (shared/ui, shared/iot, shared/web3, domain) |
| `CLAUDE.md §6` | The load-bearing frontend invariants (design-tokens only in shared components · `tokens(...)` · no DB in a Phlex `initialize` · `focus-visible:`) |
| `docs/04_06_Testing_Guide_and_Coverage.md §A` | RSpec conventions for Phlex components + the view-coverage map |

## Source Files

| File | Role |
|------|------|
| `app/views/components/application_component.rb` | The Phlex base (`< Phlex::HTML`). The **`tokens(*args, **conditions)`** TailwindMerge wrapper (last-wins conflict resolution); the **class-autoscoped `t('.key')`** override (`Codex::Show#t('.heading')` → `codex.show.heading`; overridden because the Phlex::Rails helper needs a view-context that is `nil` in component specs + Turbo broadcasts → absolute keys fall back to `I18n.t`); `CUSTOM_TEXT_SCALE` (custom font-sizes registered for TailwindMerge); pure helpers (`time_ago_in_words`, `number_to_human_size`) **delegated** so components render in broadcasts |
| `app/assets/tailwind/application.css` | **The Tailwind `@theme` block = the design-token SSOT** — there is **NO `tailwind.config.js`** (v4). Every `gaia-*`/`status-*`/`token-*` colour + the `CUSTOM_TEXT_SCALE` font-sizes live here |
| `app/views/shared/ui/*.rb` | Domain-agnostic primitives — `data_table`, `meta_row`, `pagination`, `empty_state`, `skeleton`, `photo_card`, `locale_switcher`. **Tokens only** (no raw Tailwind). Registry → `04_04 §6.1` |
| `app/views/shared/iot/*.rb` · `app/views/shared/web3/*.rb` | Shared IoT + Web3 components — `04_04 §6.2/§6.3` |
| `app/views/components/<domain>/*.rb` | Domain page components (trees, clusters, codex, oracle_visions, contracts, alerts, …) — these MAY use page-specific raw Tailwind |
| `app/javascript/controllers/*_controller.js` | The 8 Stimulus controllers (mobile_nav, clipboard, theme, reveal, map, matrix_rain, codex/comment, codex/reveal) — auto-registered via importmap |

## Gotchas Not Obvious From Docs

1. **NO `tailwind.config.js`** (Tailwind v4) — the SSOT is the **`@theme` block in `app/assets/tailwind/application.css`**. Don't create a config file; add a token to `@theme`.
2. **Raw Tailwind forbidden in SHARED components** — `bg-red-100` only in domain-specific page components; `shared/ui|iot|web3/` MUST use the semantic tokens (`bg-status-danger`, `bg-gaia-surface`, …) so the dark theme + design system stay coherent (CLAUDE.md §6).
3. **A new font-size → register it in `CUSTOM_TEXT_SCALE`** (`ApplicationComponent`) so TailwindMerge treats it as a font-size, not a text-colour (else `tokens()` mis-merges it). Current scale: `micro mini tiny compact display-sm display-md display-lg`.
4. **NO DB queries in a Phlex `initialize`** — components accept pre-loaded data only; queries belong in the controller/presenter (a query in `initialize` runs at render time → breaks caching + Turbo broadcasts).
5. **`t('.key')` autoscopes by class-name** — `Alerts::Badge#t('.heading')` → `I18n.t('alerts.badge.heading')` (the overridden base `t`, working in Phlex specs + Turbo broadcasts where there is no view context); absolute keys (`t('flash.x')`) fall back to `I18n.t`.
6. **Specs default to English** — a Ukrainian / LV / LT assertion needs an explicit `I18n.with_locale(:uk) { ... }`.
7. **Turbo `broadcast_*` runs in MODEL context** — a `broadcast_*` inside a model callback renders the component outside the request → **no `current_user` / session**. Pass everything the component needs explicitly; lean on the delegated pure helpers, not view helpers.
8. **`tokens()` is the class-builder, not string interpolation** — `tokens("base btn", active?: "ring-2")` merges via TailwindMerge so a later conflicting utility wins; hand-joined class strings don't get that conflict resolution.
9. **For live updates use `turbo_stream_from` + `Turbo::StreamsChannel.broadcast_*_to` (§8), NOT raw `ActionCable.server.broadcast`** — there is **no** consumer wiring repo-wide (`@rails/actioncable` isn't importmap-pinned, `app/channels/` is empty, no `subscriptions.create`). Raw `ActionCable.server.broadcast` broadcasts into the void; it has already shipped dead **4×** (Codex live-features, telemetry raw-hex) and never reached a browser. The working pattern is the Turbo helper — see telemetry/burn/wallet for the live examples. (UI.2 tracks the Codex descope/wire decision.)

## Common Tasks

- **Add a Phlex component**: `app/views/components/<domain>/<name>.rb` (`< ApplicationComponent`, `def view_template`); a reusable primitive → `app/views/shared/ui/`. **Tokens only** if shared; accept **pre-loaded data** (no DB in `initialize`); i18n via `t('.key')`. Spec per `04_06 §A`.
- **Add a design token**: edit the `@theme` block in `app/assets/tailwind/application.css` (a `gaia-*`/`status-*`/`token-*` colour or a font-size); a **font-size ALSO → `CUSTOM_TEXT_SCALE`**; document the usage rule in `04_04 §3`.
- **Token-migration (UI.1 buildable-backlog)**: `bin/rails gaia:lint_tokens` reports raw-Tailwind hits in shared components; `bin/migrate-tailwind-tokens` = the safe Ruby codemod (30-entry MAPPING + PROTECTED list + dry-run) — replacement is NOT visually-neutral, so QA both themes after a run. Migrate-to-green THEN wire the CI gate. Plan → `00_07 UI.1`.
- **Add a Stimulus controller**: `app/javascript/controllers/<name>_controller.js` (auto-registered); wire via `data-controller` / `data-action` in the Phlex component.
- **A Turbo broadcast**: render the component with explicit data (no `current_user`, gotcha #7); use the delegated pure helpers.
- **Local-verify**: `bin/rubocop -a app/views app/javascript` ([[feedback_local_verify]]) → `COVERAGE=0 bin/rspec spec/views` (Phlex specs — wrap non-English assertions in `I18n.with_locale`) → eyeball the dark theme + `focus-visible:` rings.
