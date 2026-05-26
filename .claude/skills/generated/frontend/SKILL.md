---
name: frontend
description: "Navigation + gotchas for Phlex + Tailwind v4 + Turbo + Stimulus. Read SSOT docs first."
---

# Frontend

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §7` | Phlex rules, design tokens, Turbo streams/frames, Stimulus, i18n |
| `docs/04_04_Frontend_Architecture.md` | Component hierarchy, tokens, text scale, i18n setup |
| `docs/04_06_Design_System.md` | gaia-* and status-* token families, dark theme |

## Gotchas Not Obvious From Docs

1. **tailwind.config.js is DELETED** — SSOT is `app/assets/stylesheets/application.css` `@theme` block. Don't create a config file.
2. **Raw Tailwind forbidden in shared components** — `bg-red-100` only in domain-specific page components. Shared components must use `bg-status-danger` etc.
3. **CUSTOM_TEXT_SCALE sync** — `text-micro/mini/tiny/compact` registered in `ApplicationComponent` for TailwindMerge. If you add a size, register it there too.
4. **No DB queries in Phlex initialize** — accept pre-loaded data only. Queries go in controller/presenter.
5. **t(".key") autoscopes** — `Alerts::Badge#t(".heading")` → `I18n.t("alerts.badge.heading")`. Works in Phlex, NOT in plain Ruby.
6. **Tests default to English** — Ukrainian/LV/LT tests need explicit `I18n.with_locale(:uk) { ... }`.
7. **Turbo broadcast context** — `broadcast_*` methods inside model callbacks run in the model context, not the request context. No current_user available.
