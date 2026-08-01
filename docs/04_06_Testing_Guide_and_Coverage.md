# 04_06: Testing Guide & Coverage Matrix

## 🎯 Мета

Канонічний дім тест-**методології** SilkenNet: (а) конвенції RSpec для Phlex-компонентів (Частина A) + карта покриття view-шару (§A.10); (б) gap-аналіз ризиків покриття всіх шарів — RSpec, Firmware C, Foundry Solidity (Частина B). **One-Home-межа (за типом):** методологія/гейт/тріаж/cross-cutting-ризики + view-coverage — тут; per-subsystem spec-інвентарі («який spec що верифікує» для конкретної підсистеми) живуть БІЛЯ своєї підсистеми (Ethereum — [`05_04 §7`](05_04_Ethereum_L1_State_Anchor), Queen-firmware — [`03_02 §11`](03_02_Queen_Gateway_Firmware), crypto — [`03_05 §8`](03_05_Hardware_Symmetric_Crypto_and_Security), метрики — [`06_03`](06_03_Prometheus_Observability) тощо), посилаючись сюди за методом.

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
- [A.10 Карта покриття — view-компоненти (spec ⟶ що верифікує)](#a10-карта-покриття--view-компоненти-spec--що-верифікує)
- [B.1 Відомі обмеження та відкриті ризики](#b1-відомі-обмеження-та-відкриті-ризики)
- [B.2 Рекомендації для нових фіч](#b2-рекомендації-для-нових-фіч)
- [B.3 Скоуп покриття та гейт](#b3-скоуп-покриття-та-гейт)
- [B.4 Пошук і тріаж прогалин](#b4-пошук-і-тріаж-прогалин)
- [B.5 Worked triage examples](#b5-worked-triage-examples)
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
Якщо компонент використовує `tree_path(tree)` або `dom_id(tx)` —
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

### 10а. 🔴 Стаб на РЕАЛЬНОМУ класі не сміє ВИЗНАЧАТИ метод, якого в застосунку немає

Мок на `OpenStruct` (правила 6–10) імітує **дані** — це нормально. `prepend` на живий
клас — інша річ: він змінює саму поверхню, що тестується, і якщо додає метод, якого
в продакшні не існує, спека пінить світ, у якому дефект **неможливий**.

Куплено дорого ([UI.6], 2026-07-31): чотири спеки родини `maintenance` робили

```ruby
Views::Shared::UI::PhotoCard.prepend(Module.new do
  def maintenance_record_photo_path(*, **) = "/…/photos/1"   # ❌ метод НЕ існував
end)
```

Хелпер не існував (зайвий `as:` у вкладеному `resources` подвоював префікс), тож
сторінка запису **з будь-яким фото віддавала 500** — а сюїта лишалась зеленою роками.
Сусідній стаб у тому ж файлі підміняв хелпер, який **існує**, і його коментар
стверджував протилежне («routes do not expose an `:edit` action») — тобто був stale-
дзеркалом ери до фіксу маршруту.

**Правило.** `prepend`/`allow_any_instance_of` на продакшн-клас дозволені лише для
того, що в тому класі **вже є**. Перед тим як стабити маршрут-хелпер — перевір його
в рантаймі (`Rails.application.routes.url_helpers.respond_to?(:name)`), а не на око.

**Межа проходить по КОНТРАКТУ АРГУМЕНТІВ, не по «маршрут ⊥ зовнішній ресурс».**
`rails_blob_path` теж маршрут-хелпер; стабити його доводиться тому, що він вимагає від
мока `signed_id`, а не тому, що він «зовнішній». `…_photo_path` вимагає лише
`to_param`, який `Object` дає безкоштовно, — тому й працює без стабу. Питання завжди
одне: **чи задовольняє мок контракт аргументів цього хелпера**.

⚠️ **Що саме купує зняття стабу — ІМ'Я, а не URL.** Хелпер із голим `OpenStruct`
резолвиться, але підставляє `inspect`-рядок у сегмент:
`/maintenance_records/7/photos/%23%3COpenStruct%20id=99%3E`. Тобто спека
доводить «метод існує», а не «шлях правильний». Наслідок для пінів: перевіряй
**повний** шлях (`include(maintenance_record_photo_path(record, photo))`),
ніколи не префікс на кшталт `include("/photos/")` — префікс істинний при будь-якому
сміттєвому аргументі.

⚠️ І наслідок для покриття: компонентна спека рендерить повз маршрутизатор, тож
непіднятий хелпер вона не побачить у принципі. Кожна сторінка, що рендерить дію,
потребує **одного** request-приклада на справжньому HTTP — саме він ловить цей клас.

🔴 **Той самий сліпий кут має ДРУГУ форму, і вона тихіша: хелпер резолвиться, а ціль
не приймає ДІЄСЛОВО** ([UI.7], 2026-07-31). `Codex::Attunements::Toggle` слав un-attune
на колекційний шлях, зареєстрований лише під `POST` — рядок HTML виглядав бездоганно,
компонентна спека рендерила його роками зеленою, а кнопка вела в 404 у всіх. Тому пінь
**ЦІЛЬ, а не дієслово**: `include(%(action="#{шлях}"))` плюс `not_to include` на сусідній
шлях, коли дві дії не сміють ділити адресу. І **сам стаб може звузити світ до дефекту**:
той спек визначав рівно ОДИН із двох потрібних хелперів — той, яким компонент помилково
слав обидві дії. Це не порушення правила вище (метод існував), а його сусід: стаб покривав
**підмножину** реальної поверхні, тож правильний маршрут не міг зʼявитись у рендері навіть
теоретично. Рефлекс: стабиш маршрут-хелпер — спитай, **скільки їх у цієї сторінки**.

⚠️ **Виміряна стеля, яку не закрити спекою взагалі:** `allow_forgery_protection = false`
у test-env, а `ApplicationController.renderer` не має сесії — тож `authenticity_token`
не рендериться навіть при примусово ввімкненому захисті (перевірено). Уся сюїта сліпа
до відсутнього CSRF-токена, і саме так рукописна `<form>` без нього прожила поруч із
`button_to`-сусідами. Не вдавай, що покрив: використовуй `button_to`/`form_with`, які
кладуть токен самі, і не рукописний `<form>`.

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

### 22. Turbo Stream: пінь РОЗПАКОВАНЕ ім'я, а не підписаний токен
Заборона стосується **токена**, не імені. Пін на сам підписаний рядок пінив би
`secret_key_base` і серіалізатор Turbo замість НАШОГО скоупу — і мовчки порвався б
на ротації ключа. Але зупинятись на «елемент присутній» не можна: підпис
детермінований, тож імʼя **розпаковується** і є єдиним, що робить підписку
правильною чи витоком ([`04_04 §8.1`](04_04_Phlex_UI_and_Tailwind), SEC.25).

```ruby
def subscribed_streams(markup)
  markup.scan(/signed-stream-name="([^"]+)"/).flatten
        .map { |s| Turbo::StreamsChannel.verified_stream_name(s) }
end

# Скоуп несе саме ІМʼЯ → рівність множини, не `include`.
# `_e{epoch}` — покоління імені [SEC.25 Ф3]; у компонент-спеці бери епоху
# НЕ-дефолтну (тут 7), інакше зашита в код одиниця лишила б пін зеленим.
expect(subscribed_streams(html)).to eq([ "telemetry_stream_org_42_e7" ])
```

⚠️ **Голий `include("turbo-cable-stream-source")` — вакуумний пін**: він зелений і
тоді, коли сторінка підписана на чужий стрім. Саме ця редакція правила лишила
компонент-спеки телеметрії й мапи без жодного асершна на підписку — ані на ціль,
ані на факт. Форму доказу диктує **кардинальність сторінки**: одна сутність →
two-subject (двоє глядачів мусять дістати РІЗНІ імена), список → рівність множини
(дефект там виглядає як ЗАЙВИЙ стрім, а не як відсутній власний).

### 23. `ApplicationCable::Connection`: три пастки харнеса, кожна дає ФАЛЬШИВО-ЗЕЛЕНЕ

Знайдені читанням джерела `actioncable`/`rspec-rails`, не помилкою, — але кожна
коштувала б налагодження, і дві з трьох роблять приклад зеленим із хибної причини.

- 🔴 **`TestCookieJar` має `signed` і `encrypted`, але НЕ `signed_or_encrypted`.**
  Тобто дослівне дзеркало продового `CookieStore` (який читає саме через
  `signed_or_encrypted`) штатним харнесом **не пишеться взагалі** — приклад упаде
  на `NoMethodError`, а не на тому, що перевіряє.
- 🔴 **`TestCookies#[]=` бере `options.symbolize_keys[:value]`.** Хеш сесії, покладений
  без обгортки `{ value: … }`, мовчки стає `nil` — і тоді КОЖЕН приклад «доводить»
  відмову з порожнього cookie незалежно від логіки під тестом. Класика вакуумного
  зеленого: асершн правдивий, а причина не та.
- ✅ **Харнес будувати не треба:** `rspec-rails` `ChannelExampleGroup` уже підмішує
  обидва `Behavior` і дає матчер `have_rejected_connection`.

⚠️ Суміжна пастка фікстур на acting-організації: `Organization has_many :audit_logs,
dependent: :restrict_with_error`, а перемикання контексту **завжди** лишає запис
([`04_03 §3.1`](04_03_REST_API_v1_Reference)) — тож організація, в яку хтось перемкнувся,
більше не видаляється. Спека «організації немає» природним `destroy!` не пишеться;
будуй такий стан, не видаляючи вже вживану організацію.

---

## A.6 Pagination

### 24. `mock_pagy(last: 3)` для тестування пагінації
`last: 1` — пагінація не рендериться (Pagination returns early).
Завжди використовуй `last: 3` або вище.

### 25. Тестуй і наявність, і відсутність пагінації
```ruby
describe "pagination" do
  it "renders pagination when pagy.last > 1" do ...
  it "does not render pagination on single page" do ...
end
```

---

## A.7 Performance & DRY

### 26. Один `let(:html)` на describe-блок
Не рендери компонент у кожному `it`. Шаріть через `let`.
```ruby
describe "header" do
  let(:html) { render_component(tree: mock_tree) }

  it "displays the DID" do ...
  it "shows status badge" do ...
end
```

### 27. Не дублюй mock helpers між спеками одного namespace
Якщо `Trees::Show` і `Trees::Index` шарять `mock_tree` — DRY це не потрібно.
Кожна спека автономна. Дублювання моків між файлами — ОК.
DRY застосовується ВСЕРЕДИНІ одного файлу.

### 28. Не тестуй дочірні компоненти через батьківські
```ruby
# ❌ Trees::Index spec не повинен тестувати деталі Pagination
# ✅ Trees::Index spec перевіряє "pagination renders", деталі — в Pagination spec
```

---

## A.8 Документація та стиль

### 29. `# frozen_string_literal: true` + `require "rails_helper"` — завжди
Перші два рядки кожного файлу. Без виключень.

### 30. Опис `it` — англійською, декларативно
```ruby
# ✅
it "renders the gateway UID" do
it "displays BATCH_RECEIVED status" do
it "shows empty state when no logs" do

# ❌
it "should render gateway UID" do
it "test that status works" do
```

### 31. Мінімум 8 examples на компонент
Менше — означає недостатнє покриття. Виняток: тривіальні wrapper-компоненти
(BalanceFrame) можуть мати 5-7.

---

## A.9 Checklist для code review

- [ ] Файл дзеркалить шлях компонента (BP #1)
- [ ] Використовує `render_component` з хелпера або обґрунтовано перевизначає (BP #2-4)
- [ ] Моки через OpenStruct з розумними дефолтами (BP #6-10)
- [ ] Є describe-блоки: rendering, edge cases, accessibility, design system (BP #11-15)
- [ ] Assertions через `include`, не повні HTML-рядки (BP #16-18)
- [ ] Gaia токени в shared components (BP #19)
- [ ] Turbo frame/stream перевірено (BP #21-22)
- [ ] Пагінація з `mock_pagy(last: 3)` (BP #24-25)
- [ ] `let(:html)` шариться в describe-блоці (BP #26)
- [ ] Мінімум 8 examples (BP #31)

---

## A.10 Карта покриття — view-компоненти (spec ⟶ що верифікує)

Інвентар спек view-шару. One-Home: 04_06 володіє конвенціями цих спек (Частина A), тож і їхня карта покриття живе тут; реєстр самих компонентів — [`04_04 §6`](04_04_Phlex_UI_and_Tailwind). Точні example-counts навмисно НЕ фіксуються (volatile, [`00_06 §1`](00_06_SSOT_Documentation_Standard)) — покриття описане словами.

| Spec-файл | Покриття |
|---|---|
| `spec/views/shared/ui/status_badge_spec.rb` | Всі AASM стани, семантичні токени, доступність |
| `spec/views/shared/ui/stat_card_spec.rb` | Props, danger-режим, перевизначення класу |
| `spec/views/shared/ui/action_badge_spec.rb` | Pattern matching, семантичні стилі |
| `spec/views/shared/ui/empty_state_spec.rb` | За замовчуванням, кастомна іконка, table-режим |
| `spec/views/shared/ui/meta_row_spec.rb` | Мітка/значення, обробка nil |
| `spec/views/shared/ui/relative_time_spec.rb` | Інтервали часу, граничні випадки |
| `spec/views/shared/web3/address_spec.rb` | Обрізання, clipboard, nil fallback |
| `spec/views/shared/iot/metric_value_spec.rb` | Точність, nil, BigDecimal, одиниця |
| `spec/views/components/alerts/badge_spec.rb` | Матриця severity × status |
| `spec/views/components/dashboard/event_row_spec.rb` | Поліморфні типи подій |
| `spec/views/components/wallets/transaction_row_spec.rb` | Типи токенів, обрізання хешу |
| `spec/views/components/wallets/balance_display_spec.rb` | Рендеринг балансу, Turbo target |
| `spec/views/components/actuators/card_spec.rb` | Статус LED, рендеринг матриці |
| `spec/views/components/actuators/command_status_frame_spec.rb` | Пара класу 2 ([`04_04 §8.1а`](04_04_Phlex_UI_and_Tailwind)): фрейм сторінки/відповіді **без** `src` (self-referencing `src` Turbo не зациклює, а гасить — `references itself` у консоль і порожній фрейм, тобто симптом тихий) ⟷ broadcast-заглушка **зі** `src`; id фрейма ≠ id бейджа всередині; байт-у-байт однаковий рендер у всіх налаштованих локалях |
| `spec/views/shared/ui/data_table_spec.rb` | Стовпці+рядки, порожній стан, кастомний empty_message, відповідність дизайн-системі, доступність, перевизначення класу, один стовпець |
| `spec/views/shared/ui/pagination_spec.rb` | Перша/середня/остання/одна сторінка, відповідність дизайн-системі, доступність, focus-visible, guard невалідного pagy |
| `spec/views/shared/ui/photo_card_spec.rb` | Ініціалізація, валідація, відповідність дизайн-системі, editable true/false, типографіка |
| `spec/views/shared/ui/skeleton_spec.rb` | Всі 6 варіантів, кастомні рядки, перевизначення класу |
| `spec/views/shared/ui/theme_switcher_spec.rb` | Поведінка перемикання, dark/light стан |
| `spec/views/components/alerts/row_spec.rb` | Severity, статус, дія вирішення |
| `spec/views/components/clusters/show_spec.rb` | Індекс здоров'я, список дерев, стан загрози |
| `spec/views/components/tree_families/form_spec.rb` | Форма створення/оновлення, валідація |
| `spec/views/components/wallets/show_spec.rb` | Фрейм балансу, журнал транзакцій, pagy пагінація |

---

# Частина B — Gap Analysis

## B.1 Відомі обмеження та відкриті ризики

### B.1.1 Firmware

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Mock AES | 🔴 CRITICAL | `hal_mock.h` копіює plaintext→ciphertext; реальна AES верифікація неможлива без ARM HW |
| Mock TinyML | 🟡 MEDIUM | `test_tinyml_pipeline.c` мокає `Run_Inference()` для decision-логіки; **реальна модель тестується** окремо — `test_audio_model.c` (12 golden, INT8 forward-pass ≡ silken_ml reference, FW.4) |
| AT Command UART | 🟡 MEDIUM | SIM7070G modem I/O не тестується повністю (апаратна залежність). Retry/timeout-логіка верифікована `test_at_engine.c` (conversation-fail) + `test_fw51_*` (fail→retry→no-loss) (FW.9) |
| DMA Audio Timing | 🟠 HIGH | 512-sample DMA transfer timing не верифікується на host |

**Coverage-lane (TEST.1, 2026-06-11):** `make -C firmware/test coverage` — gcov-звіт по owned-модулях (`../common`, `../queen`: і `.c`, і header-only через атрибуцію у TU) + CI-крок у `ci.yml` (visibility, без порога). Чесні межі звіту: `test_soldier/queen_logic` міряють **дзеркала** логіки `main.c`, не сам `main.c` (його покриває QEMU/bench-фаза, [`03_01 §12.7`](03_01_Firmware_Lifecycle_and_DMA)); непокритий хвіст у звіті — переважно defensive ops-failure guards (таксономія §B.4: leave + чому).

**ASan/UBSan-lane (TEST.5, 2026-06-24):** `make -C firmware/test asan` — уся host-сюїта (істина = вивід `make`, не лічильник тут) перебудовується й проганяється під AddressSanitizer + UndefinedBehaviorSanitizer (`-fsanitize=address,undefined -fno-sanitize-recover=all`), той самий re-instrumented-rebuild ідіом, що й coverage-lane; CI-крок `[TEST.5]` у `firmware_test` (gating через `ci-ok`). Ловить heap/stack/global overflow, use-after-free/return, double-free (ASan) + signed-overflow, OOB-shift, misalign/null-deref (UBSan) — динамічна пара до статичного cppcheck (`firmware_lint`) + `-Wall`, закриває OpenSSF `dynamic_analysis_unsafe` для memory-unsafe C (раніше лише статика). `detect_leaks=0` свідомо: OpenSSL one-time global init (`test_encryption`, `test_queen_attest`) ніколи не звільняється за дизайном (короткоживучі тести не кличуть `OPENSSL_cleanup`) → LSAN-«still reachable» = хибнопозитив, не buffer-баг; критерій цілить overwrites/UAF/UB, які ASan+UBSan покривають (Monocypher heap не алокує). Межі ті самі, що в coverage-lane: міряємо дзеркала логіки `main.c`, не сам `main.c`.

### B.1.2 Solidity

Відкритих ризиків немає. ERC20Permit (повна EIP-712 сюїта: `permit()` + SFC `delegateBySig` + cross-chain інваріант) та Governor↔SCC integration (DAO керує/ротує `MINTER_ROLE`/`SLASHER_ROLE` через 48h-Timelock) — закрито; цемент у [`00_07`](00_07_Action_Plan_Tracker) (TEST.3).

**Гілкове/рядкове покриття під `forge coverage --ir-minimum` = артефакт виміру, не геп.** `--ir-minimum` обов'язковий (без оптимізатора OZ `P256.sol` → stack-too-deep, `foundry.toml`), а під ним forge недо-інструментує: `require`-revert гілки, single-statement тіла (`pause()`/`unpause()`) та override-делегації (`return super._x()`) звітуються «непокритими», хоча `testRevert_`/`expectRevert` їх виконують і проходять. Тому контрактний гейт спирається на **line/func**, не на branch% (звірено по токенах + StateRootAnchor + ProtocolParameters: кожна непокрита гілка має тест). Єдиний справжній func-геп — Governor `_cancel` (proposer-cancel flow) — закрито `test_cancel_byProposerWhilePending`.

### B.1.3 Backend

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Live Web3 RPC | 🟡 MEDIUM | Всі Web3 виклики заглушені; live RPC тестування потребує staging env |

**Concurrent State — закрито (свідоме рішення, не геп).** Money-path money-safety тримає **Postgres pessimistic-lock**, не наш код: `Wallet#lock_funds!`/`lock_and_mint!`/`release_locked_funds!`/`credit!` беруть `with_lock`/`lock!` (`SELECT … FOR UPDATE`) — регресію «лок прибрано» ловить mock-сюїта (`wallet_spec` «uses with_lock/lock!»). AASM-переходи `BlockchainTransaction` (`confirm!`/`fail!`/`escalate_to_review!`) **без** `requires_lock` = м'яка robustness-діра, що самозагоюється в бік безпеки — **НЕ** money-loss: переходи не чіпають wallet-money (mint-flow тримає locked як «сконвертовано назавжди»; `finalize_spend!` видалено E.66-prune), а `manual_review` = double-spend-backstop. Реальний multi-thread тест свідомо **не пишемо**: (1) перевіряв би серіалізацію `FOR UPDATE` самого Postgres, не нашу логіку; (2) без `lock_version` на money-таблицях гонка AASM-переходів vacuous (кожен потік бачить свіжий дозволений from-state → last-write-wins, нуль raise); (3) був би перший non-transactional thread-DB файл = непропорційний flake-ризик (клас TEST.2). Цемент у [`00_07`](00_07_Action_Plan_Tracker) (TEST.4). **[ARCH.45] окремий клас:** concurrent-safety (цей TEST.4, pessimistic-lock) ≠ on-chain↔DB crash-window idempotency (intent-marker + `BlockchainTransaction.in_flight` guard для Solana payout / burn / Etherisc — [`04_02 §4/§10`](04_02_Business_Logic_and_Services)); останнє вкрите double-pay / double-burn / double-claim specs.

**Load/throughput bench-harness (INF.23) — coverage boundary (свідоме, не геп).** `lib/silken_net/load_test/*` **у gate-скоупі** (НЕ фільтрується, як `/lib/tasks/`) — але покриття цілить у **pure-детектори**, що несуть INF.23 honesty-інваріант «dev-число ≠ capacity»: `LoadReport.classify_redis`/`environment_class` (io-bound prod-like gate), `CoapFlood.parse_linux_udp_rcvbuf_errors` (авторитетний Linux-CI drop-лічильник /proc/net/snmp), `DrainBench.diverging?` (backlog-divergence) + input-guards. Самі drain/flood-**цикли** (`run_backlog`/`run_arrival`/`wait_for_drain`/`flood_worker`) РЕАЛЬНО дренажать → потрібен живий Sidekiq/UDP-стек (`bin/coap_load` проти dev/staging) → **integration-class, поза host-unit скоупом** (той самий клас, що firmware DMA-timing §B.1.1): specs лишають живі цикли integration-leave, покриваючи детектори.

### B.1.4 Browser / feature-шар (`spec/features/`)

| Ризик | Серйозність | Опис |
|-------|------------|------|
| ~~JS не виконується у feature-специ~~ — ✅ ЗНЯТО 2026-07-31 | — | Причина була НЕ в Rails: глушив власний безумовний stub у `spec/support/layout_asset_stubs.rb`. Тепер він ловить лише реальний `Propshaft::MissingAssetError`, і Stimulus/Turbo в браузері живі ↓ |

**Шар існує з 2026-07-30 і доти був порожнім — при повністю зібраній машинерії.** `spec/features/` містила лише `.gitkeep`, а CI-джоба `feature-test` піднімала Postgres+Redis на КОЖНОМУ ruby-PR, виконувала `rspec spec/features` над порожньою множиною й повідомляла успіх. 🔴 Клас, вартий запам'ятовування ширше за цей випадок: **гейт, що перевіряє порожню множину, зелений НАЗАВЖДИ і не має симптому** — він не падає, не попереджає, і жоден лічильник не показує «0 прикладів» як проблему. Ціна входу виявилась не в інфраструктурі (cuprite · capybara · `spec/support/cuprite.rb` · скріншоти-на-падінні — усе стояло), а у **відсутньому `require "capybara/rspec"`**: DSL не був підключений, бо порожній директорії він не потрібен.

🔴 **Тут доти стояла «чесна межа шару»: нібито в тестовому середовищі сторінки не несуть asset-тегів узагалі, і винен рендер-шлях запиту Rails. Обидві половини СПРОСТОВАНО 2026-07-31 — і винен був не Rails, а наш власний харнес.** Глушив `spec/support/layout_asset_stubs.rb`: він БЕЗУМОВНО повертав `""` замість `stylesheet_link_tag`/`javascript_importmap_tags` на `DashboardLayout`/`AuthLayout`. Рендер-шлях запиту весь цей час віддавав повний importmap — це перевірено тим самим `ActionDispatch::Integration::Session`, яким «доводили» протилежне. 🔴 **Чому діагноз тримався й чому шукали не там: контрольним виміром був `bin/rails runner`, а він НЕ вантажить `spec/support/`** — тобто найпереконливіший «доказ провини Rails» був артефактом того, що контроль не проходив через власний стаб. Клас ширший за випадок: **контраст «тут працює, там ні» доводить провину лише тоді, коли обидва середовища вантажать одні й ті самі support-шари.** Лік — глушити відсутність asset'а, а не виклик (`rescue Propshaft::MissingAssetError`).

✅ **Що це означає для нового feature-спека сьогодні:** сценарії на живий Stimulus/Turbo **можна й треба писати** — `typeof window.Stimulus` = `"object"`, `turbo:morph` відтворюється керовано (`Turbo.visit(href, {action:"replace"})`). Зразок — `spec/features/dashboard_browser_smoke_spec.rb` («runs OUR Stimulus controller»). ⚠️ Дві пастки лишаються чинними, і зразок обходить їх НЕ боротьбою, а зміною якоря: Capybara скоупить пошук у `/html/body` (тож `have_css("html.dark")` не матчить НІКОЛИ) → пінься за вузол у `body`, який мутує контролер; `theme#toggle` іде через `document.startViewTransition` (застосування асинхронне) → спершу дочекайся DOM-зміни через `have_css`, і лише ПОТІМ читай `evaluate_script`. ⚠️ І **не «лагодь» такий приклад моком**: замоканий Stimulus доводив би, що працює мок, а не застосунок. ⚠️ Мапа (Leaflet) лишається невирішеною окремо: контролер реєструється й модуль вантажиться, але `L.map()` не викликається — причина НЕ встановлена, деталь → [`00_07`](00_07_Action_Plan_Tracker) TEST.7.

⚠️ **Гейт покриття:** `FEATURE_TEST=1` (як і `COVERAGE=0`) повністю вимикає SimpleCov-поріг — feature-специ міряються окремою CI-джобою, а їхній власний прогін дає ≈0% глобального покриття, тож гейт хибно впав би (§B.3).

---

## B.2 Рекомендації для нових фіч

1. **Кожен новий Service/Worker** ПОВИНЕН мати spec файл з ratio ≥ 1.5x.
2. **AASM state machines** ПОВИННІ тестувати всі transitions + invalid transitions.
3. **Web3 сервіси** ПОВИННІ тестувати: stub mode, strict mode, missing credentials, RPC errors.
4. **Phlex компоненти** — слідувати Частині A цього документа (min 8 examples).
5. **Firmware** — кожна нова функція потребує host-based test у `firmware/test/`.
6. **Solidity** — naming: `test_` (happy), `testRevert_` (error), `testFuzz_` (fuzz), `check_` (Halmos symbolic proof, `test/symbolic/`), `property_` (Medusa fuzz, `test/medusa/`). CI-аудит-шари: static (Slither + Aderyn) · symbolic (Halmos — доводить інваріант для ВСІХ входів) · property-fuzz (Foundry invariant + Medusa). Інструменти/roadmap → [`05_03`](05_03_Tokenomics_SCC_and_SFC).
7. **Per-group SimpleCov tripwire** — окрім глобального гейту, `spec/spec_helper.rb` `SimpleCov.at_exit` падає, якщо **line- або branch**-покриття групи `Services` / `Models` / `Workers` опускається нижче порога (поріг per-group = `floor(поточне покриття)` — найтісніший цілий % нижче факту; branch — тісніший сигнал за line). Глобальні та per-group пороги живуть **тільки** у `spec/spec_helper.rb` (їхній єдиний дім — точні числа тут не дублюються, [`00_06 §1`](00_06_SSOT_Documentation_Standard)). Мета — ловити випадкове видалення спек у hot path-ах. Скоуп і політику гейту описує §B.3.
8. **Нова непокрита гілка** — спершу спитай: вона *dead* (недосяжна за інваріантом / валідацією / типом) чи *real*? **Dead → прибрати (рефактор)** краще, ніж тестувати — зменшує знаменник і прибирає cruft. Real → тест. Defensive-leave — лише з інлайн-обґрунтуванням ЧОМУ (тріаж + матриця §B.4).
9. **ENV-мутації у спеках авто-ізольовані** — глобальний `config.around` у `spec/rails_helper.rb` знімає snapshot ENV перед кожним прикладом і відновлює його `ENV.replace` в `ensure` (вже **після** тіардауну моків). Тож `ENV["X"] = "y"` у `before`/`it` не тече в наступні приклади, а окремий `after { ENV.delete }` НЕ потрібен — і навіть **небезпечний**, якщо приклад робить `stub_const("ENV", …)`: user-`after` біжить раніше за відновлення стабу → чистить стаблений Hash, лишаючи реальну змінну (саме так народився seed-залежний flake — витік `TELEMETRY_CCM_ENABLED` міняв `chunk_size` 21→29 → пакети тихо скіпались). Потрібне per-example значення став у `before`; ізоляцію тримає глобальний хук.
10. **Мережеві loopback-зонди ловлять connection-Errno, не лише timeout** (TEST.6) — UDP-тест на «мертвий порт» (щойно закритий сокет) на Linux дістає ICMP port-unreachable: `IO.select` бачить сокет readable, а `recvfrom` спливає `Errno::ECONNREFUSED` замість тиші. macOS цей ICMP на **non-connected** UDP НЕ доставляє (30/30 silent) → зелено локально, seed-залежний flake **лише в Linux CI** (гонка «ICMP встиг/не встиг за `timeout`»). Зонд/клієнт має трактувати `ECONNREFUSED`/`ENETUNREACH`/`EHOSTUNREACH` як «шлях не відповів» (тиша → ретрай → чесний false), а не пробивати голий Errno (`CoapSmoke::UNREACHABLE`). Регресію пінити **host-independent** (стаб `recvfrom` → `ECONNREFUSED` після readable-`IO.select`), бо реальний ICMP платформозалежний і на dev не відтворюється.
11. **Policy-спека НЕ заміняє request-спеку на тенант-ізоляції** (SEC.25, 2026-07-28) — вона кличе політику **напряму**, минаючи контролер, тож доводить лише те, що правило написане правильно, і нічого — про те, що контролер його питає. Саме тому `Wallets::Show` роками тримав єдиний нескоуплений `find` на тенант-скоупленому записі (послідовний PK, money-поверхня, ще й видача підписки на чужий ledger) при повністю зеленій policy-спеці: мутація `authorize` не вбивала жодного прикладу. Пін тенант-ізоляції = **request**-спека на крос-org доступ, і **обидві** гілки формату окремо (`as: :json` не рендерить HTML-гілку, тобто підписку не перевіряє взагалі). Дзеркальне правило для самої підписки → BP #22.
12. **Агентський flake-репорт ≠ факт — спершу CI-історія, потім hunt** (TEST.6, 2026-07) — 4-агентний review заявив race у `batch_payout_service`; репро-кампанія (87 clean-прогонів на 2 платформах: 52 macOS + 35 Linux-стенд, ідентичний CI-runner'у) + обидві гіпотези (wall-clock `unsettled_within(7.days)`-boundary · Redis SMEMBERS-порядок) фальсифіковані проти коду; фінальний доказ — **уся 90-денна CI-історія: 80 failure-ранів, `batch_payout` червоним не був жодного разу** (0 re-run'ів у проєкті) → вердикт: фантом-репорт. Правильний порядок дій зворотний: СПОЧАТКУ CI-історія (дешево), ПОТІМ репро-кампанія. Сторожа: `ci.yml` job `test` вантажить `tmp/rspec_results.json` + `examples.txt` артефактом on-failure → реальний red = one-command repro (`--only-failures --seed <n>`); ре-відкриття TEST.6-класу — лише з таким failing-example. Анти-патерни при справжньому флейку: seed-pin (вбиває order-detection) і дефенсивний sort без repro.

13. **Fail-closed дефолт робить НЕГАТИВНИЙ пін сліпим до забутої ПРОВОДКИ — потрібна позитивна половина** ([UI.5](00_07_Action_Plan_Tracker), 2026-07-31) — коли компонент дістає актора kwarg'ом із безпечним дефолтом (`current_user: nil` → ховати гейтоване), приклад «нижча роль не бачить X» лишається зеленим і тоді, коли шар вище **перестав передавати актора взагалі**: без актора гейтоване сховане в УСІХ. Тобто негативне твердження стереже сам фільтр, але не його проводку. Ловить її лише **позитивний** пін («роль, якій пункт належить, його БАЧИТЬ»), і жити той мусить у **request**-спеці — компонентна конструює компонент напряму, повз layout, тож проводки не бачить у принципі (сиблінг BP #11: там повз контролер, тут повз layout). Верифікація — дві РІЗНІ мутації: фільтра (червонить компонентні приклади) і проводки (червонить рівно один request-приклад). Узагальнення на будь-який безпечний дефолт: спитай, **який приклад впаде, якщо аргумент перестане приходити** — якщо жоден, ти запінив дефолт, а не поведінку.

14. 🔴 **Мок аргументів компонента — це НЕДОВЕДЕНИЙ контракт із викликачем, і брехати він може двома способами** ([UI.7], 2026-07-31). Компонентна спека сама конструює те, що в житті будує контролер, тож фікстура здатна оголосити світ, у якому дефекту не існує — і жодна мутація цього не покаже, бо код і пін розходяться з реальністю **синхронно**. Дві виміряні форми, обидві на одній метриці. **(а) Вигаданий КЛЮЧ:** `Contracts::Index` читав `@stats[:avg_health]`, контролер клав `cluster_health:` — картка «Network Health» рендерила голе «%», а `mock_stats` вигадувала рівно `avg_health:` і асертила «87%». **(б) Вигадана ШКАЛА при правильному ключі — тихіша:** `Dashboard::Home` робив `.to_i` над `health_avg` ∈ 0..1, тобто здорова організація бачила на головній «0%», а фікстура підставляла `92` і пін «92%» був зелений. 🔴 **І механізм НЕ той, який напрошується — це виправлення власної підстави, зроблене за добу.** Спершу було записано, що HTML-гілки `users#index` і `contracts#index` не мали жодного request-прикладу. Насправді **обидві мали** — `it "renders the dashboard page"`, зелений увесь час. Він перевіряв **лише код 200**, а `nil`, інтерпольований у рядок, нічого не кидає: сторінка чесно віддавала 200 із голим «%», і мертвий `href: "#"` її теж не ламав. Тобто дві половини контракту **зустрічались** — просто ніхто їх не ПОРІВНЮВАВ. Це важливіше за «прикладу не було»: smoke-приклад на статус створює **видимість** покриття HTML-гілки й тому надійно закриває питання для наступного читача. **Правило:** значення у фікстурі беруться з ТОГО, що будує контролер (ключ І шкала І тип), з посиланням на його рядок у коментарі; а сторінка, чиї числа приходять із контролера, потребує request-прикладу **на ВМІСТ** — «рендериться без помилки» не є твердженням про правду того, що відрендерилось (сиблінг BP #11: «воно запустилось» ≠ «воно спрацювало»). ⚠️ Сиблінг BP #11/#13: там повз контролер і повз layout, тут — повз **викликача**.

---

## B.3 Скоуп покриття та гейт

**Що міряється.** Гейт покриває **продакшн-застосунок** (`app/`) + допоміжні lib-движки, які він або специ вантажать (`lib/docs_*.rb`, `lib/wiki_link_normalizer.rb`, `lib/coap_client.rb`, `lib/tracker/`, `lib/hil/`, `lib/github_bootstrap.rb`). Пороги line/branch + per-group tripwire живуть **тільки** в `spec/spec_helper.rb` — точні числа сюди не копіюються (volatile, [`00_06 §1`](00_06_SSOT_Documentation_Standard)).

**Що відфільтровано — і чому.** `SimpleCov` фільтрує `/spec/`, `/config/`, `/db/`, `/vendor/`, `/firmware/`, `/lib/daemons/`, **`/lib/tasks/`** та **`/scripts/`**. Rake-таски — це ops/SSOT-оркестрація (file I/O + `puts`-звіти + `abort`-гейти), не running-застосунок; їхня **логіка винесена** в lib-движки зі 100% покриттям (`DocsLinter`, `DocsToc`, `DocsGraph` …), а самі таски ганяються в `docs.yml`/`ssot_guard.yml`, не в unit-сюїті. Рахувати їхні незаміряні `puts`-рядки = розводнити продакшн-гейт. Той самий принцип, що й фільтр `/firmware/` (host-mock'и): міряємо там, де факт «чи працює код» справді встановлюється (One-Home, [`00_06 §2`](00_06_SSOT_Documentation_Standard)). **`/scripts/`** (standalone CLI drift-гейти — `guard_registry_sync`/`workflow_gate_perimeter`/`docs_check`/`stan_audit`) фільтрується з тим самим rationale: pure-Ruby, ганяються `ruby scripts/*.rb` у `docs.yml`, якість-межа = власна spec+mutation, не app coverage-floor.

> ⚠️ **Стеля самого ратчета: підлога `floor(поточне)` карає не лише падіння покриття, а й ВИДАЛЕННЯ покритого коду.** Арифметика однобічна — при `h/t < 1` зняття `k` покритих гілок дає `(h−k)/(t−k) < h/t`, тобто чистий refactor-прибирання механічно опускає відсоток, не додавши жодної непокритої гілки. Це пряма напруга з драбинкою «лінивого сеньйора» ([`CLAUDE.md §4`](../CLAUDE.md): видалення > додавання) і з §B.4, який велить мертву гілку **прибирати**, а не покривати: обидві поради здатні зробити білд червоним. Тримати в голові при тріажі — падіння групи після рефактора-видалення означає «перерахуй підлогу», а не «допиши тест». (Прецедент 2026-07-27 був ІНШИМ: `Workers` просів через три нові воркери зі своїми захисними гілками, не через видалення — але клас реальний і перевірений арифметично.)

> ⚠️ **Друга стеля того ж ратчета: саме значення НЕ детерміноване між платформами, тож локальне «вище порога» не є доказом про CI.** Виміряно 2026-08-01 звіркою CI-артефакту покриття з локальним прогоном: єдина розбіжність у всьому корпусі — `case/when` довкола connection-Errno в `lib/silken_net/load_test/coap_flood.rb`, де Linux лишає непокритою на одну гілку більше, ніж macOS. Це той самий платформний клас, що §B.2 #10, лише б'є не по тесту, а по МЕТРИЦІ — і білд червоніє при `0 failures`, тобто `test`-джоба читається як провалений тест. **Рефлекс:** червона `test`-джоба + «examples, 0 failures» → грепни `below the expected minimum`; а покриття перед push'ем звіряй артефактом CI (`gh run download <run> -n simplecov-coverage`), не локальним числом. Присуд про сам поріг (підняти запас · вивести load-harness зі скоупу · лишити ніж) → [`00_07`](00_07_Action_Plan_Tracker) TEST.9.

**Зняття гейту.** `FEATURE_TEST=1` та `COVERAGE=0` повністю вимикають гейт (feature-специ міряються окремим CI-job'ом; `docs.yml` ганяє лише лінтер-специ → загальне покриття ≈0, гейт хибно впав би).

> **Sweep = момент для security-лінтерів.** Gap-парсинг водить по рідко-виконуваних шляхах (guard / `&.` / regex) — там же часто сидять security-знахідки. Цей цикл закрив CodeQL-**ReDoS** у `lib/tracker/dashboard.rb` (вкладений `(?:[…]+\s*)*` з опційним роздільником → exponential backtracking), помічений саме під час coverage-sweep. Тож прогнати CodeQL / `bin/brakeman` на файлах, які чіпаєш у sweep, — дешева суміжна вигода.

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

**Тріаж — НЕ покривати сліпо. Недосяжна гілка = мертвий код → спершу спитай: рефакторити геть чи лишити (і ЧОМУ).**

- **Реальна логіка** (status / empty-state / guard / error-path) → написати тест.
- **Справді мертве → РЕФАКТОРИТИ гілку** (прибрати, а не «лишати заради %»):
  - **Мертвий `&.`**: receiver short-circuit'нутий другим операндом `&&`, або літерал/константа → `&.`→`.`. ⚠️ обов'язковий `belongs_to` ≠ гарантований non-nil на READ — `dependent: :nullify` зануляє FK, і тоді `parent.child` читається nil (це захист нульованого FK, **НЕ** мертвий `&.`).
  - **Завжди-true модифікатор-`if`**, чию умову робить істинною інваріант методу (напр. `… if x.status_paid?` після `return unless triggered || paid` + AASM, де `triggered` йде ЛИШЕ в `paid`) → прибрати надлишковий `if` (якщо це не послаблює safety-guard нижче).
- **Не мертве, лише не-в-тесті:**
  - **Env-conditional** `defined?(Const)`, де `Const` — dev/test-only gem (`group :development, :test`): else — це **прод-шлях** (не мертвий). Покрити `hide_const`, АБО лишити + 1 рядок чому, якщо це ламає глобальну інтеграцію гему в харнесі (напр. `Prosopite` RSpec-хуки).
  - **Forward-looking** (ще-не-зареєстрована версія тощо) → чесно покрити `stub_const`.
- **Defensive, що ЛИШАЄМО — обов'язково задокументувати інлайн ЧОМУ:**
  - **Model-validation-dead**: гілка guard-ить стан, заборонений валідаціями самої моделі (`if tx.tx_hash.present?`-else, коли `:sent`-tx завжди має hash) → справжній guard — валідація; гілку лишити.
  - **Financial-safety-defensive**: недосяжний за поточним інваріантом, але захищає від МАЙБУТНЬОЇ зміни стейт-машини (напр. мінтинг лише для `:paid`) → прибирання послабило б захист; крихкий white-box-тест заради % суперечить §A.16–17.
- **Баг біля непокритого коду** → виправити + тест, або занести в [`00_07`](00_07_Action_Plan_Tracker).

**Швидка матриця dead-vs-leave (довідник):**

| Гілка | Вердикт | Чому |
|-------|---------|------|
| always-true умова (інваріант / AASM) | **refactor** | прибрати надлишковий `if` — behavior-preserving |
| dead `&.` (receiver non-nil: `&&`-short-circuit / `dependent: :delete_all` / літерал) | **refactor** | `&.`→`.` |
| exhaustive `case` implicit-else (`i%3 ∈ {0,1,2}`) | **leave** | нема чого прибирати; явний `else` = новий dead-код |
| model-validation-dead (`if x.present?`-else, коли валідація гарантує present) | **leave** | справжній guard — валідація |
| financial-safety-defensive (dead за інваріантом, але захищає від зміни стейт-машини) | **leave + ЧОМУ** | прибирання послабить захист |
| env-conditional `defined?(dev/test-gem)` | **cover** (`hide_const`) / leave якщо ламає харнес | else = прод-шлях |
| nullify-FK `parent.child` (`dependent: :nullify`) | **cover / leave** | child реально nil після видалення батька |

> **Gotcha (parser vs verify).** Гап-парсер вище читає resultset лише після **повного** прогону; verify-субсети (`COVERAGE=0 bin/rspec <file>`) **перезаписують** `coverage/.resultset.json` частково → повторний парс покаже сміття. Цикл: правки → субсет-verify (швидко) → **повний** прогін перед наступним парсом.

**Seed-флак покриття (точний hunt).** Коли line/branch «плавають» між прогонами (маржа гейту їх ховає), винуватець — код, що вправляється лише за певного ПОРЯДКУ тестів. Інструмент: `scripts/coverage_seed_diff.rb` — порівнює два `.resultset.json` від двох fixed-seed прогонів і друкує рядки/гілки, чия покритість різниться (рецепт зняття пари — у шапці скрипта; SimpleCov мержить у 10-хв вікні, тож `.resultset.json` обовʼязково чистити МІЖ прогонами). Тріаж знахідок: класичні корені — **незворотні `Module#prepend` у спеках** (анонімний модуль тіньовить продакшн-метод до кінця процесу — решта сюїти тестує підміну; worked example — §B.5), memoization first-test-wins, class-level стан, **ENV-витік без robust-restore** (`after { ENV.delete }` чистить стаблений Hash, якщо приклад робить `stub_const("ENV", …)` → реальна змінна тече; мітиговано глобальним ENV-snapshot, §B.2 #9). Прецедент (2026-06-12, TEST.1): єдиними флоатерами всієї сюїти були 2 рядки + 2 гілки `sessions_controller#current_session` — `around`-хук препендив підміну за хибною преміссою «методу нема»; видалення препенду зробило покриття детермінованим. View-стаби з `prepend` (asset/route-хелпери, ідемпотентні patched-once гарди) — легітимні: тіньовлять фреймворкові методи поза скоупом покриття.

---

## B.5 Worked triage examples

Конкретні рішення sweep'у — як читати «недосяжне» правильно (мапінг на матрицю §B.4):

- **`insurance #perform if status_paid?` → REFACTOR.** AASM має лише `triggered→paid`, тож після transaction-блоку статус завжди `:paid` → умова завжди-true; `tx ||=` сам short-circuit'ить → прибрання behavior-preserving (−1 гілка зі знаменника).
- **`minting_rollback log.tree&.wallet` → REFACTOR.** `Tree dependent: :delete_all` видаляє логи разом із деревом → orphaned-log не існує → `tree` non-nil → `&.` мертвий. **NB:** якби стояв `:nullify` — `&.` був би real (лишити). **Завжди перевіряй `dependent:` перед тим, як назвати `&.` мертвим.**
- **`attractor case i % 3` → LEAVE.** `i` — loop-індекс, `i % 3 ∈ {0,1,2}` завжди; implicit-else недосяжний математично. Додати явний `else` = ДОПИСАТИ dead-код заради лічильника.
- **`insurance tx.tx_hash.present?`-else → LEAVE.** `:sent`-tx завжди має hash (валідація моделі; `update!(status: :sent, tx_hash: nil)` падає — доведено тестом, що НЕ проходить). Справжній guard — валідація, не цей `if`.
- **`audit_log defined?(Prosopite)`-else → LEAVE некритим.** Prosopite — у `group :development, :test`, тож else — це прод-шлях (не мертвий); але `hide_const("Prosopite")` ламає глобальні Prosopite-RSpec-хуки (доведено фейлом `create`). Прод-only + не cleanly-testable → лишити з цим рядком-обґрунтуванням.
- **`codex/citation for_target(anon)` → COVER (без стабів).** `polymorphic_type_for` повертає nil для анонімного класу (`Class.new.new` → `klass.name` nil) — чистий реальний вхід для nil-type guard.
- **`sessions#current_session` seed-флак → REFACTOR спеки (видалити prepend).** Інтеграційна спека `around`-хуком препендила анонімний модуль із власним `current_session` за хибною преміссою «методу на контролері нема» (він є). `Module#prepend` незворотний → за сід-порядків, де ця спека бігла першою, продакшн-метод (2 рядки + 2 гілки) діставав нуль покриття, а РЕШТА сюїти тестувала підміну — інтегріті-дефект, не лише coverage-шум. Знайдено `scripts/coverage_seed_diff.rb` (§B.4); фікс = видалення хука — реальний метод робить те саме, обидві спеки зелені без нього. **Мораль: стаб «відсутнього» метода — спершу `method_defined?`-перевір премісу; prepend у спеках допустимий лише для фреймворкових хелперів поза скоупом покриття (asset/route view-стаби) і лише ідемпотентний.**
