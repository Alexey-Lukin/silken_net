# Frontend Overhaul Plan — Gaia 2.0 Dashboard

> **Контекст.** Завдання від користувача: перебудувати фронтенд так, щоб (а) перемикання
> dark/light давало візуально помітну різницю, (б) кольорова гама була збалансована та
> сучасна, (в) з'явилася справжня i18n з UA↔EN switcher (Rails-way, easily extensible),
> (г) усе responsive (mobile/tablet/desktop), (д) плавні анімації, (е) акуратна структура,
> (є) типографіка за стандартами (мінімальні розміри ≥ 12 px, чітка модульна шкала).
>
> Документ — SSOT для багатосесійної реалізації. Працюємо інкрементально, без зламу
> існуючих specs (де можливо — оновлюємо їх відповідно до нових токенів).

---

## 0. Що зараз не так (root-cause аудит)

| # | Симптом | Причина |
|---|---------|---------|
| 1 | "При перемиканні dark/light майже нічого не міняється" | `gaia-text` у dark = `#10b981` (emerald). Усе inline-стилізовано як `text-gray-900 dark:text-emerald-500`/`bg-white dark:bg-black` — палітра в обох режимах фактично двоколірна. Топ-бар, сайдбар, breadcrumbs використовують **raw Tailwind** замість gaia-токенів, тому переключення не доходить до більшості поверхонь. |
| 2 | "Гама не збалансована" | Dark — моно-emerald на чорному (низький WCAG для muted-варіантів: `#065f46` на `#000` ≈ 3.7:1). Light — generic Tailwind gray. Немає окремих `surface-elevated`, `surface-sunken`, accent layers. |
| 3 | Немає i18n | `config/locales/en.yml` порожній. `available_locales` не задано. `I18n.t` не використовується ніде у views. Switcher відсутній. |
| 4 | Mobile/tablet недопрацьовано | Sidebar `hidden md:block` — на mobile його просто немає, бургера/drawer теж немає. Top-bar має `md:` breakpoints, але багато inline-розмірів не масштабуються. Таблиці `overflow-x-auto`, але без sticky-колонок. |
| 5 | Анімації обмежені | Лише `transition-colors duration-300`, `animate-pulse`, `animate-ping`. Немає system-wide `prefers-reduced-motion`, немає stagger/entrance анімацій для cards/rows. |
| 6 | Типографіка | Кастомна шкала `micro/mini/tiny/compact` = 8/9/10/11 px — **нижче WCAG AA мінімуму 12 px** для тіла. Заголовки задані фіксованими rem без responsive-clamp. |
| 7 | Структура | Layout robotically inline'ить розмітку (top-bar, breadcrumbs, telemetry, avatar). 174 рядки в `Navigation::Sidebar` — приватні методи добре, але мова жорстко зашита (UA коментарі + EN labels) — i18n зніме цю двозначність. |

---

## 1. Цілі та KPI

- **D1.** Перемикання dark↔light видно на ≥ 95 % площі екрану (не тільки border + 1-2 текстові кольори).
- **D2.** Усі інтерактивні елементи мають WCAG AA контраст у обох темах (4.5:1 для тексту, 3:1 для UI).
- **D3.** Працюючий i18n: UA (default) + EN, перемикач у топ-барі, новий локаль зберігається в cookie + Accept-Language fallback.
- **D4.** Mobile breakpoint < 768 px — drawer-сайдбар, top-bar з бургером, сторінки читаються без горизонтального скролу.
- **D5.** `prefers-reduced-motion: reduce` поважається; всі анімації мають `duration-{150-300}` + `ease-out`.
- **D6.** Мінімальний font-size у production-розмітці = 12 px (`text-xs`); `text-micro/mini` залишаються лише як **decorative-only** для caps-labels із чітким aria-fallback.
- **D7.** Жоден shared/ui компонент не використовує raw Tailwind кольори — лише gaia-токени.

---

## 2. Дизайн-система (Tailwind v4 — `app/assets/tailwind/application.css`)

### 2.1 Розширена палітра поверхонь

Замість 2 (`surface`, `surface-alt`) — 4-рівнева шкала глибини:

```
--gaia-surface-base       (page background)
--gaia-surface            (cards, panels)
--gaia-surface-elevated   (modals, popovers, dropdown)
--gaia-surface-sunken     (table-row alt, code blocks, input bg)
```

**Light:**
- base `#fafafa`, surface `#ffffff`, elevated `#ffffff` (з shadow), sunken `#f3f4f6`

**Dark (cyber-emerald, з нюансами):**
- base `#050607`, surface `#0b0f0e`, elevated `#11161a`, sunken `#070a09`
- межі: `--gaia-border` `rgba(16,185,129,0.18)`, `--gaia-border-strong` `rgba(16,185,129,0.4)`

### 2.2 Текстова ієрархія (3 рівні)

```
--gaia-text-strong   (headings, primary numbers)
--gaia-text          (body)
--gaia-text-muted    (labels, metadata)
--gaia-text-subtle   (placeholders, watermarks, disabled)
```

**Light:** `#0f172a` / `#1f2937` / `#52525b` / `#9ca3af`
**Dark:** `#e6fff4` / `#a7f3d0` / `#6ee7b7` / `#34d399 @ 0.55` (тонує emerald, але не чорно-білий моно)

### 2.3 Брендові акценти (без зміни ідентичності)

- `--gaia-primary` `#10b981` (без змін — бренд)
- `--gaia-primary-hover` light `#059669`, dark `#34d399`
- `--gaia-primary-soft` (bg для chip/pill, low-emphasis): `#d1fae5` light / `rgba(16,185,129,0.1)` dark
- `--gaia-primary-glow` (focus ring + neon shadow): `0 0 0 3px rgba(16,185,129,0.35)`

### 2.4 Status-токени — переглянути контраст

Поточні значення (наприклад, `--status-warning-text: #fde68a` на `#78350f`) — ОК.
**Додати:** `--status-success-strong`, `--status-danger-strong` для CTA/кнопок (а не лише для chip).

### 2.5 Typography scale — нова шкала

| Token | Розмір | Використання |
|-------|--------|--------------|
| `text-overline` | 0.75 rem (12px), wide tracking, uppercase | Caps-labels, секційні заголовки sidebar |
| `text-xs`–`text-base` | стандарт Tailwind | body |
| `text-display-sm` | clamp(1.25rem, 1.6vw + 0.5rem, 1.5rem) | H3 |
| `text-display-md` | clamp(1.5rem, 2vw + 0.75rem, 2rem) | H2 |
| `text-display-lg` | clamp(1.875rem, 3vw + 1rem, 2.75rem) | H1 |

**Legacy** `text-micro/mini/tiny/compact` залишаємо для зворотної сумісності, але:
- Документуємо як "decorative-only".
- Body-копія мігрується на `text-xs`/`text-sm` (поетапно).

### 2.6 Motion tokens

```css
--ease-out-soft: cubic-bezier(0.22, 0.61, 0.36, 1);
--ease-spring:   cubic-bezier(0.34, 1.56, 0.64, 1);
--motion-fast: 150ms;
--motion-base: 220ms;
--motion-slow: 320ms;
```

`@media (prefers-reduced-motion: reduce)` — глобально вимикати `animate-pulse`, `animate-ping`,
trasition-duration fall back to 0.01ms (не нуль, щоб не зламати focus ring transitions).

---

## 3. Internationalization (i18n) — Rails way

### 3.1 Конфігурація

`config/application.rb`:
```ruby
config.i18n.available_locales = %i[uk en]
config.i18n.default_locale    = :uk
config.i18n.fallbacks         = { uk: [:uk, :en], en: [:en] }
```

`Gemfile`: `gem "rails-i18n"` (CLDR pluralization, дати) — додавати тільки якщо потрібно (наразі — так, для `time_ago_in_words`/Pagy).

### 3.2 Файлова структура

```
config/locales/
  defaults/
    en.yml
    uk.yml
  navigation/
    en.yml
    uk.yml
  components/
    en.yml
    uk.yml
  flash/
    en.yml
    uk.yml
```

`config/application.rb`:
```ruby
config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
```

### 3.3 Switcher infrastructure

- `app/controllers/concerns/locale_settable.rb` — `before_action :set_locale`, пріоритет:
  1. `params[:locale]` (тільки для `LocaleController#update`)
  2. `cookies[:locale]`
  3. `request.preferred_language(I18n.available_locales)`
  4. `I18n.default_locale`
- Включити в `ApplicationController` (Rails-way concern, не базовий клас).
- `app/controllers/api/v1/locales_controller.rb` (`POST /api/v1/locale`) — приймає `locale=`,
  валідує по whitelist, кладе у `cookies.permanent[:locale]`, редіректить на `request.referer || root_path`.
  Для Turbo: повертає `turbo_stream` з новим `<html lang>` + reload broadcasts; простіше — стандартний redirect із `Turbo-Visit-Control: reload` для гарантованого ре-рендера.
- Маршрут: `post "locale", to: "locales#update", as: :locale`.

### 3.4 LocaleSwitcher Phlex компонент

`app/views/shared/ui/locale_switcher.rb`:
- Dropdown із 2 опцій (UA / EN), позначка активної.
- Stimulus `locale` контролер — submit form на change, optimistic UI.
- A11y: `<button aria-haspopup="listbox" aria-expanded>`, `role="menu"`.
- Mobile: collapses to icon-only.
- Сидить у топ-барі поряд із `ThemeSwitcher` та аватаром.

### 3.5 Послідовність міграції копії

1. **Layouts/navigation** (high-visibility): `dashboard_layout`, `auth_layout`, `Navigation::Sidebar`, breadcrumb fragments.
2. **Shared/ui** компоненти з рядками: `EmptyState`, `Pagination` (prev/next labels), `ThemeSwitcher` (aria-label).
3. **Page components** (хвиля 2): `Dashboard::Home`, `Trees::Index`, `Wallets::Show`, `Alerts::Index`.
4. **Forms** (Maintenance::Form, Firmwares::Form) — labels через `t("activerecord.attributes.…")`.
5. **Auth** (`Sessions::New`, `Passwords::*`) — flash messages.
6. **Решта** (incremental).

Domain-specific term glossary (UA→EN): "Цитадель" → Citadel, "Військо" → Fleet, "Королева" → Queen, "Солдат" → Soldier, "Гай" → Cluster, "Ліс" → Forest. Документувати в `config/locales/glossary.md`.

---

## 4. Layout & Responsive Architecture

### 4.1 Breakpoint strategy (mobile-first)

| Breakpoint | Ширина | Цільові пристрої |
|------------|--------|------------------|
| (default) | <640 px | mobile portrait |
| `sm:` | ≥640 px | mobile landscape |
| `md:` | ≥768 px | tablet portrait |
| `lg:` | ≥1024 px | tablet landscape / small laptop |
| `xl:` | ≥1280 px | desktop |
| `2xl:` | ≥1536 px | large desktop |

### 4.2 Топ-бар (рефактор `dashboard_layout.rb#render_top_bar`)

- На mobile (`<md`): висота 56 px, бургер ліворуч (`MobileNavToggle`), назва сторінки центрована, ThemeSwitcher + LocaleSwitcher + avatar зправа (avatar collapses to initials only).
- На tablet (`md`): 64 px, breadcrumbs з'являються.
- На desktop (`lg+`): 80 px, повний telemetry block, full username.

### 4.3 Sidebar — двосторонній

- **Desktop** (`md+`): sticky, 16 rem ширини (наразі 16 rem `w-64` — лишаємо).
- **Mobile/tablet portrait** (`<md`): off-canvas drawer (`fixed inset-y-0 left-0 -translate-x-full md:translate-x-0`), backdrop `<button class="fixed inset-0 bg-black/50">` для закриття.
- Stimulus `mobile-nav` контролер: `open()`, `close()`, `Escape` key, scroll-lock на `body`, focus-trap (manual implementation — without external lib).
- Закривати drawer на Turbo `turbo:visit`.

### 4.4 Сторінки-таблиці (Trees::Index, Wallets::Index, Telemetry::LiveStream)

- На mobile: переходять у card-list (повторне використання `Shared::UI::DataTable` з prop `mobile_layout: :cards` — нова опція).
- Sticky headers на desktop.
- Pagination footer завжди sticky-bottom з safe-area inset (iOS notch).

### 4.5 Контент-обгортка

Замінити жорстке `max-w-7xl` на `max-w-screen-2xl`, додати `px-4 sm:px-6 lg:px-8` (вже є у `dashboard_layout`). Для дашборду ввести 12-колонковий grid (`grid-cols-12`) з spans, що валиться на 1-кол на mobile.

---

## 5. Animations & Micro-interactions

### 5.1 Глобальні правила

- Усі hover / focus transitions: `transition-colors duration-200 ease-[var(--ease-out-soft)]`.
- Drawer / modal entry: `transition-transform duration-[var(--motion-base)] ease-[var(--ease-out-soft)]`.
- Card hover: `hover:-translate-y-0.5 hover:shadow-lg` (тільки на pointer-fine, через `@media (hover: hover)`).
- `prefers-reduced-motion` — глобальний CSS клас `.motion-safe` через media-query (вбудовано в `@layer base`).

### 5.2 Entrance animations (lightweight)

- Stimulus `reveal` контролер: при `connect()` додає `animate-fade-in` (CSS keyframe) до елемента, прибирає після завершення. Використовується для card-grids, alert lists.
- Stagger через `style="--reveal-delay: 50ms"` * index.

### 5.3 Theme transition

- Поточне `transition-colors duration-300` залишаємо, але додаємо `view-transition-name: theme` (Chrome 111+, прогресивне покращення) — `document.startViewTransition(() => toggleClass(...))` у `theme_controller`.

---

## 6. Component refactor (incremental)

| Компонент | Зміни |
|-----------|-------|
| `dashboard_layout.rb` | усе raw Tailwind → gaia-токени; mobile drawer slot; LocaleSwitcher; breadcrumbs i18n; FOUC script розширити для locale (data-attr на `<html lang>`). |
| `auth_layout.rb` | gaia-токени; LocaleSwitcher + ThemeSwitcher у footer; responsive padding. |
| `Navigation::Sidebar` | `t("navigation.sections.*")` для груп та пунктів; gaia-токени; mobile-collapse via Stimulus; emoji icons → SVG (легкі inline, single-color, поважають `currentColor`). |
| `Views::Shared::UI::ThemeSwitcher` | tri-state (system/light/dark) — опційно, у фазі 2; `aria-label` через i18n. |
| `Views::Shared::UI::LocaleSwitcher` | новий. |
| `Views::Shared::UI::MobileNavToggle` | новий бургер-button; `data-action="mobile-nav#open"`. |
| `Views::Shared::UI::DataTable` | prop `mobile_layout: :cards`; sticky `<thead>`. |
| `Views::Shared::UI::Pagination` | i18n labels; mobile compact mode (тільки prev/next + page indicator). |
| `Views::Shared::UI::StatusBadge` | без логіки — тільки текстові labels через i18n. |

---

## 7. Stimulus controllers (нові)

| Controller | Файл | Ціль |
|------------|------|------|
| `mobile-nav` | `mobile_nav_controller.js` | open/close drawer, scroll-lock, focus-trap, ESC handler |
| `locale` | `locale_controller.js` | submit form on `<select>` change |
| `reveal` | `reveal_controller.js` | entrance animation (CSS class toggle) |
| `theme` (refactor) | — | tri-state + `View Transitions API` integration |

---

## 8. Тестування

### 8.1 Phlex component specs (`spec/views/...`)
- Нові: `locale_switcher_spec.rb`, `mobile_nav_toggle_spec.rb`.
- Оновити `theme_switcher_spec.rb` — tri-state.
- Оновити `dashboard_layout_spec.rb` (якщо є) — наявність `MobileNavToggle`, `LocaleSwitcher`.
- Перевірка design-system compliance: `expect(html).not_to include("bg-white"); not_to include("text-gray-900")`.

### 8.2 i18n
- `spec/i18n_spec.rb` (i18n-tasks gem-based) — перевірка повноти ключів `uk` vs `en`.
- Інтеграційні: `LocaleSwitcherFlow`-spec — POST `/api/v1/locale`, перевірка cookie + redirect.

### 8.3 Visual regression (manual)
- Lookbook scenarios: light + dark + UA + EN (4 матриці).

### 8.4 Accessibility
- axe-core (manual run у Lookbook) — мінімум 0 critical violations.

---

## 9. Реалізація — фази

### Phase 1 — Foundation (поточна сесія, скільки встигнемо)
1. ✅ Зберегти план (`docs/plans/frontend_overhaul_plan.md`).
2. i18n config: `available_locales`, `default_locale`, `load_path`, `LocaleSettable` concern, `LocalesController`, route.
3. Базові locale файли (`config/locales/defaults/{uk,en}.yml`, `navigation/{uk,en}.yml`, `components/{uk,en}.yml`).
4. `Views::Shared::UI::LocaleSwitcher` + Stimulus `locale_controller`.
5. Розширення палітри в `application.css` (4-рівневі поверхні, текстова ієрархія, motion tokens, reduced-motion media-query).
6. `dashboard_layout` — заміна raw Tailwind на gaia-токени, інтеграція LocaleSwitcher, додавання `<html lang>`.
7. RSpec: `locale_switcher_spec`, smoke-spec на `LocalesController`.
8. Перевірка `bundle exec rubocop && bundle exec rspec spec/views/shared/ui/locale_switcher_spec.rb spec/requests/api/v1/locales_spec.rb`.

### Phase 2 — Mobile drawer + nav i18n
1. `MobileNavToggle` + `mobile_nav_controller.js`.
2. `Navigation::Sidebar` — i18n labels, gaia-токени, drawer-mode rendering.
3. `dashboard_layout` — інтеграція drawer slot.
4. Auth layout — responsive + LocaleSwitcher.

### Phase 3 — Animations + typography
1. Motion tokens: глобальний `prefers-reduced-motion` handling.
2. `reveal_controller` + CSS keyframes.
3. View Transitions API у `theme_controller`.
4. Typography scale: додати `text-display-*`, оновити `<h1..h4>` у `@layer base` на `clamp()`.

### Phase 4 — Component-by-component migration
- Page components переводимо по одному, з оновленням spec (gaia-tokens compliance + i18n).
- Чек-лист: див. § 6.

### Phase 5 — DataTable mobile cards + table-heavy pages
- `DataTable` prop `mobile_layout`.
- `Trees::Index`, `Wallets::Index`, `Alerts::Index`, `Telemetry::LiveStream`.

### Phase 6 — Polish & verification
- axe-core run, contrast audit (Lighthouse).
- Documentation update: `docs/04_04_Phlex_UI_and_Tailwind.md` (сек. 3.1, 4) + новий розділ "Internationalization".

---

## 10. Ризики та компроміси

| Ризик | Мітигація |
|-------|-----------|
| Великий surface-of-change → багато оновлень spec | Фазова міграція; кожна фаза — окремий PR. Spec-and-go: одночасно правимо component + spec. |
| Tri-state ThemeSwitcher може зламати existing UX | Винести у Phase 3; зберегти 2-state як дефолт, tri-state як progressive enhancement. |
| `rails-i18n` додає вагу | Це малий gem; альтернатива — самописні pluralization rules для UA. Додаємо. |
| Mobile drawer може конфліктувати з Turbo Drive cache | `disconnect()` Stimulus примусово закриває drawer + знімає scroll-lock; `data-turbo-temporary` на backdrop. |
| Зміна 4-рівневої палітри ламає screenshot-spec | У нас assert через `include`-strings, не повний HTML — стійко. |
| Перейменування токенів `gaia-text` → `gaia-text-strong` | Утримуємо `gaia-text` як alias для `gaia-text` (body), додаємо `text-strong/muted/subtle` поряд — без deprecation. |

---

## 11. Definition of Done (per phase)

- [ ] `bundle exec rubocop` зелений.
- [ ] `bundle exec rspec spec/views/ spec/requests/` зелений у межах зачеплених файлів.
- [ ] Lookbook рендериться без помилок у обох локалях.
- [ ] Manual smoke: dark↔light дає ≥ 95% візуальної різниці на dashboard, /trees, /wallets, /alerts.
- [ ] Mobile (375 px) — sidebar drawer працює, контент без horizontal scroll.
- [ ] `docs/04_04_Phlex_UI_and_Tailwind.md` оновлено для змінених токенів/компонентів.
