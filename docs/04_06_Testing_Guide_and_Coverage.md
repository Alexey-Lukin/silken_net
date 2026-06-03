# 04_06: Testing Guide & Coverage Matrix

## 🎯 Мета

Об'єднати у єдиному документі (а) канонічний набір конвенцій для RSpec тестів Phlex-компонентів SilkenNet та (б) повну карту покриття тестами всіх шарів (RSpec, Firmware C, Foundry Solidity). Документ оновлюється при додаванні нових сервісів, воркерів, компонентів або смарт-контрактів і є базою для аудиту якості.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — 30 best practices задокументовані та застосовуються у всіх нових спеках; покриття тестами для backend / firmware / contracts на operationally-ready рівні.
- **Охоплені фреймворки:**
  - RSpec (Ruby / Rails)
  - Firmware C (host-based, Make)
  - Foundry (Solidity)
- **Відкрите:** test-coverage gaps / відкриті ризики (§B.1) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`04_04` — Phlex UI and Tailwind](04_04_Phlex_UI_and_Tailwind) | Phlex UI (Частина A — view-component best practices) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Сервіси |
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | Моделі |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (coverage gaps, §B.1) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [A.1 Структура та конвенції (Convention over Configuration)](#a1-структура-та-конвенції-convention-over-configuration)
- [A.2 Моки та тестові дані](#a2-моки-та-тестові-дані)
- [A.3 Організація describe/context/it](#a3-організація-describecontextit)
- [A.4 Assertions](#a4-assertions)
- [A.5 Turbo & ActionCable](#a5-turbo--actioncable)
- [A.6 Pagination](#a6-pagination)
- [A.7 Performance & DRY](#a7-performance--dry)
- [A.8 Документація та стиль](#a8-документація-та-стиль)
- [A.9 Checklist для code review](#a9-checklist-для-code-review)
- [B.1 Відомі обмеження та відкриті ризики](#b1-відомі-обмеження-та-відкриті-ризики)
- [B.2 Рекомендації для нових фіч](#b2-рекомендації-для-нових-фіч)
- [B.3 Скоуп покриття та гейт](#b3-скоуп-покриття-та-гейт)
- [B.4 Пошук і тріаж прогалин](#b4-пошук-і-тріаж-прогалин)
<!-- TOC:AUTO:END -->

---

# Частина A — View Component Testing Guide (30 Best Practices)

Всі нові та існуючі спеки ПОВИННІ слідувати цим правилам.

## A.1 Структура та конвенції (Convention over Configuration)

### 1. Один файл — один компонент
Шлях спеки дзеркалить шлях компонента:
```
app/views/components/trees/show.rb  →  spec/views/components/trees/show_spec.rb
app/views/shared/ui/stat_card.rb    →  spec/views/shared/ui/stat_card_spec.rb
app/views/layouts/dashboard_layout.rb → spec/views/layouts/dashboard_layout_spec.rb
```

### 2. Використовуй `PhlexComponentHelper` (DRY rendering)
Модуль `spec/support/phlex_component_helper.rb` автоматично підключається до
всіх файлів у `spec/views/`. Він надає:
- `render_component(**kwargs)` — автоматично обирає `.call` чи `ApplicationController.renderer.render`
- `component_class` — синонім `described_class`
- `mock_pagy(count:, page:, last:)` — стандартний Pagy double (uses `previous:` not `prev:` — Pagy 43+)
- `mock_model(klass, id:, **attrs)` — OpenStruct з model_name/to_key/to_param

### 3. Рендеринг: renderer vs .call
- **`.call`** — для компонентів БЕЗ route helpers, turbo tags, form builders
- **`ApplicationController.renderer.render`** — для компонентів з `_path`, `turbo_frame_tag`, `form_with`, `button_to`
- `render_component` з хелпера обирає автоматично за аналізом вихідного файлу
- Якщо перевизначаєш `render_component` у спеці — ЗАВЖДИ пиши коментар чому

### 4. Не перевизначай `render_component` без потреби
Хелпер працює для 95% випадків. Перевизначай тільки коли:
- Компонент приймає блок (DataTable)
- Потрібна кастомна логіка рендерингу (layout wrapping)
- Layout-компоненти (`DashboardLayout`, `AuthLayout`) потребують `content:` параметр
- Сигнатура `initialize` конфліктує з `**kwargs`

### 5. `let(:component_class)` — видалити (deprecated)
Хелпер надає метод `component_class`. Якщо спека ще має
`let(:component_class) { described_class }` — це не помилка, але зайвий рядок.

---

## A.2 Моки та тестові дані

### 6. OpenStruct для моків, НЕ FactoryBot (для view спек)
View спеки тестують HTML-розмітку, не ORM. `OpenStruct` швидший за `build()`.
Виняток: `Maintenance::Form` потребує валідну AR-модель для `form_with`.

### 7. `mock_model(klass, id:, **attrs)` для моделей з route helpers
Якщо компонент використовує `api_v1_tree_path(tree)` або `dom_id(tx)` —
mock ПОВИНЕН мати `model_name`, `to_key`, `to_param`. Використовуй `mock_model`.

### 8. Кожен mock-метод — іменований за domain entity
```ruby
# ✅ Добре
def mock_tree(...) end
def mock_gateway(...) end
def mock_wallet(...) end

# ❌ Погано
def make_data(...) end
def build_mock(...) end
```

### 9. Параметри mock-методів мають розумні дефолти
```ruby
def mock_tree(did: "SNET-00000042", status: "active", ...)
```
Кожен параметр — з дефолтом. Тест перевизначає тільки те, що тестує.

### 10. `define_singleton_method` для предикатів
```ruby
t = OpenStruct.new(status: status)
t.define_singleton_method(:active?) { status == "active" }
```
OpenStruct не генерує `?`-методи автоматично.

---

## A.3 Організація describe/context/it

### 11. Стандартна ієрархія describe-блоків
```ruby
RSpec.describe Trees::Show do
  # Mock helpers
  # let/render

  describe "header section" do ... end
  describe "status indicators" do ... end
  describe "data table" do ... end
  describe "empty state" do ... end
  describe "edge cases" do ... end
  describe "accessibility" do ... end
  describe "design system compliance" do ... end
end
```

### 12. `describe "rendering"` — для базової перевірки (чи рендериться взагалі)
Перший describe-блок. Мінімум 2-3 it-блоки: ключовий заголовок, структурний елемент, анімація.

### 13. `describe "edge cases"` — nil handling, empty collections, boundary values
```ruby
describe "edge cases" do
  it "handles nil gateway gracefully" do ...
  it "shows empty state when logs are empty" do ...
end
```

### 14. `describe "accessibility"` — role, aria, focus-visible
```ruby
describe "accessibility" do
  it "renders table with role=table" do ...
  it "renders th with scope=col" do ...
  it "has focus-visible ring on interactive elements" do ...
end
```

### 15. `describe "design system compliance"` — gaia tokens, custom text scale
```ruby
describe "design system compliance" do
  it "uses gaia design tokens, not raw Tailwind colors" do
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-900")
  end

  it "uses custom text scale (text-tiny/mini/micro/compact)" do
    expect(html).to include("text-tiny")
  end
end
```

---

## A.4 Assertions

### 16. `include` для HTML content assertions
```ruby
expect(html).to include("SNET-00000042")
```
Не парсь HTML через Nokogiri — це view spec, не integration test.

### 17. НЕ тестуй повний HTML-рядок
```ruby
# ❌ Крихкий
expect(html).to include('<div class="p-6 border border-emerald-900 bg-black">')

# ✅ Стійкий
expect(html).to include("border-emerald-900")
expect(html).to include("bg-black")
```

### 18. Тестуй CSS-класи окремо, не разом
```ruby
# ✅ Кожен клас — окрема перевірка
expect(html).to include("text-emerald-500")
expect(html).to include("animate-pulse")
```

### 19. Тестуй наявність gaia-токенів, не hardcoded значень
```ruby
# ✅
expect(html).to include("text-gaia-primary")
expect(html).to include("bg-gaia-surface")
expect(html).to include("border-gaia-border")

# ❌ (дозволено тільки в domain-specific page components)
expect(html).to include("text-emerald-500")
```
Для shared UI компонентів — ТІЛЬКИ gaia-токени.
Для page components (Trees::Show, etc.) — допускається raw Tailwind.

### 20. Перевіряй data-атрибути для Stimulus/Turbo
```ruby
expect(html).to include('data-controller="clipboard"')
expect(html).to include("turbo-frame")
```

---

## A.5 Turbo & ActionCable

### 21. Turbo Frame: перевіряй ID
```ruby
describe "turbo frame" do
  it "renders turbo frame with correct id" do
    expect(html).to include("wallet_metadata_frame_1")
  end
end
```

### 22. Turbo Stream: НЕ перевіряй signed stream name
Turbo підписує stream names (base64). Перевіряй наявність `<turbo-cable-stream-source`,
але НЕ конкретний signed token.
```ruby
expect(html).to include("turbo-cable-stream-source")
```

---

## A.6 Pagination

### 23. `mock_pagy(last: 3)` для тестування пагінації
`last: 1` — пагінація не рендериться (Pagination returns early).
Завжди використовуй `last: 3` або вище.

### 24. Тестуй і наявність, і відсутність пагінації
```ruby
describe "pagination" do
  it "renders pagination when pagy.last > 1" do ...
  it "does not render pagination on single page" do ...
end
```

---

## A.7 Performance & DRY

### 25. Один `let(:html)` на describe-блок
Не рендери компонент у кожному `it`. Шаріть через `let`.
```ruby
describe "header" do
  let(:html) { render_component(tree: mock_tree) }

  it "displays the DID" do ...
  it "shows status badge" do ...
end
```

### 26. Не дублюй mock helpers між спеками одного namespace
Якщо `Trees::Show` і `Trees::Index` шарять `mock_tree` — DRY це не потрібно.
Кожна спека автономна. Дублювання моків між файлами — ОК.
DRY застосовується ВСЕРЕДИНІ одного файлу.

### 27. Не тестуй дочірні компоненти через батьківські
```ruby
# ❌ Trees::Index spec не повинен тестувати деталі Pagination
# ✅ Trees::Index spec перевіряє "pagination renders", деталі — в Pagination spec
```

---

## A.8 Документація та стиль

### 28. `# frozen_string_literal: true` + `require "rails_helper"` — завжди
Перші два рядки кожного файлу. Без виключень.

### 29. Опис `it` — англійською, декларативно
```ruby
# ✅
it "renders the gateway UID" do
it "displays BATCH_RECEIVED status" do
it "shows empty state when no logs" do

# ❌
it "should render gateway UID" do
it "test that status works" do
```

### 30. Мінімум 8 examples на компонент
Менше — означає недостатнє покриття. Виняток: тривіальні wrapper-компоненти
(BalanceFrame, OtaProgressBar) можуть мати 5-7.

---

## A.9 Checklist для code review

- [ ] Файл дзеркалить шлях компонента (BP #1)
- [ ] Використовує `render_component` з хелпера або обґрунтовано перевизначає (BP #2-4)
- [ ] Моки через OpenStruct з розумними дефолтами (BP #6-10)
- [ ] Є describe-блоки: rendering, edge cases, accessibility, design system (BP #11-15)
- [ ] Assertions через `include`, не повні HTML-рядки (BP #16-18)
- [ ] Gaia токени в shared components (BP #19)
- [ ] Turbo frame/stream перевірено (BP #21-22)
- [ ] Пагінація з `mock_pagy(last: 3)` (BP #23-24)
- [ ] `let(:html)` шариться в describe-блоці (BP #25)
- [ ] Мінімум 8 examples (BP #30)

---

# Частина B — Gap Analysis

## B.1 Відомі обмеження та відкриті ризики

### B.1.1 Firmware

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Mock AES | 🔴 CRITICAL | `hal_mock.h` копіює plaintext→ciphertext; реальна AES верифікація неможлива без ARM HW |
| Mock TinyML | 🟠 HIGH | `Run_Inference()` повертає фіксовані класи; реальна модель не тестується |
| AT Command UART | 🟡 MEDIUM | SIM7070G modem I/O не тестується повністю (апаратна залежність). Константи retry та таймаутів верифіковані `test_coap_retry_constants` (FW.9) |
| DMA Audio Timing | 🟠 HIGH | 512-sample DMA transfer timing не верифікується на host |

### B.1.2 Solidity

| Ризик | Серйозність | Опис |
|-------|------------|------|
| ERC20Permit | 🟡 MEDIUM | Permit/signature tests є базовими; cross-chain replay не тестується |
| Governor Integration | 🟡 MEDIUM | Governor + SCC mint interaction тестується окремо |

### B.1.3 Backend

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Concurrent State | 🟡 MEDIUM | Race conditions у AASM transitions не тестуються (потребують multi-thread test) |
| Live Web3 RPC | 🟡 MEDIUM | Всі Web3 виклики заглушені; live RPC тестування потребує staging env |

---

## B.2 Рекомендації для нових фіч

1. **Кожен новий Service/Worker** ПОВИНЕН мати spec файл з ratio ≥ 1.5x.
2. **AASM state machines** ПОВИННІ тестувати всі transitions + invalid transitions.
3. **Web3 сервіси** ПОВИННІ тестувати: stub mode, strict mode, missing credentials, RPC errors.
4. **Phlex компоненти** — слідувати Частині A цього документа (min 8 examples).
5. **Firmware** — кожна нова функція потребує host-based test у `firmware/test/`.
6. **Solidity** — naming: `test_` (happy), `testRevert_` (error), `testFuzz_` (fuzz).
7. **Per-group SimpleCov tripwire** — окрім глобального гейту, `spec/spec_helper.rb` `SimpleCov.at_exit` падає, якщо line-покриття групи `Services` / `Models` / `Workers` опускається нижче порога. Глобальні та per-group пороги живуть **тільки** у `spec/spec_helper.rb` (їхній єдиний дім — точні числа тут не дублюються, [`00_06 §1`](00_06_SSOT_Documentation_Standard)). Мета — ловити випадкове видалення спек у hot path-ах. Скоуп і політику гейту описує §B.3.

---

## B.3 Скоуп покриття та гейт

**Що міряється.** Гейт покриває **продакшн-застосунок** (`app/`) + допоміжні lib-движки, які він або специ вантажать (`lib/docs_*.rb`, `lib/wiki_link_normalizer.rb`, `lib/coap_client.rb`, `lib/tracker/`, `lib/hil/`, `lib/github_bootstrap.rb`). Пороги line/branch + per-group tripwire живуть **тільки** в `spec/spec_helper.rb` — точні числа сюди не копіюються (volatile, [`00_06 §1`](00_06_SSOT_Documentation_Standard)).

**Що відфільтровано — і чому.** `SimpleCov` фільтрує `/spec/`, `/config/`, `/db/`, `/vendor/`, `/firmware/`, `/lib/daemons/` та **`/lib/tasks/`**. Rake-таски — це ops/SSOT-оркестрація (file I/O + `puts`-звіти + `abort`-гейти), не running-застосунок; їхня **логіка винесена** в lib-движки зі 100% покриттям (`DocsLinter`, `DocsToc`, `DocsGraph` …), а самі таски ганяються в `docs.yml`/`ssot_guard.yml`, не в unit-сюїті. Рахувати їхні незаміряні `puts`-рядки = розводнити продакшн-гейт. Той самий принцип, що й фільтр `/firmware/` (host-mock'и): міряємо там, де факт «чи працює код» справді встановлюється (One-Home, [`00_06 §2`](00_06_SSOT_Documentation_Standard)).

**Зняття гейту.** `FEATURE_TEST=1` та `COVERAGE=0` повністю вимикають гейт (feature-специ міряються окремим CI-job'ом; `docs.yml` ганяє лише лінтер-специ → загальне покриття ≈0, гейт хибно впав би).

---

## B.4 Пошук і тріаж прогалин

**Знайти** — після ПОВНОГО `bin/rspec` (цілісний `coverage/.resultset.json`; subset-прогон переписує його частково й тригерить per-group tripwire-артефакт — не реальний fail):

```ruby
require "json"
cov = JSON.parse(File.read("coverage/.resultset.json")).values.first["coverage"]
cov.filter_map { |p, d|
  next unless p =~ %r{/(app|lib)/}
  t = h = 0
  (d["branches"] || {}).each { |_, s| s.each { |_, n| t += 1; h += 1 if n.to_i > 0 } }
  t > h ? [ t - h, p.sub(%r{.*/(app|lib)/}, '\1/') ] : nil
}.sort_by { |r| -r[0] }.first(25).each { |u, f| printf "-%3d %s\n", u, f }
```

**Тріаж — НЕ покривати сліпо.** Для кожної непокритої гілки:

- **Реальна логіка** (status / empty-state / guard / error-path) → написати тест.
- **Мертвий захисний `&.`** (receiver — обов'язковий `belongs_to`, гарантовано non-nil, або short-circuit'нутий другим операндом `&&`) → спростити `&.`→`.`; гілка зникає, тест не потрібен.
- **Недосяжний defensive guard** (інваріант, якого клас сам не порушує; `defined?(Const)` за завжди-завантаженого модуля) → лишити; крихкий white-box-тест заради % суперечить §A.16–17. Forward-looking-гілку (ще-не-зареєстрована версія тощо) можна чесно покрити `stub_const`.
- **Баг біля непокритого коду** → виправити + тест, або занести в [`00_07`](00_07_Action_Plan_Tracker).
