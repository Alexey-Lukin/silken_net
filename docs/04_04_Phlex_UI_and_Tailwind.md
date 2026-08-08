# 04_04: Phlex UI & Tailwind (SSOT Дизайн-Системи)

## 🎯 Мета

Зафіксувати повну специфікацію дизайн-системи SilkenNet як Єдине Джерело Істини (SSOT). Документ описує **Phlex-компоненти**, **Tailwind CSS токени**, **Stimulus-контролери**, **Turbo-інтеграцію** та правила доступності. Слугує єдиним авторитетним джерелом для всіх UI-рішень в межах Rails 8.1 моноліту.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — рушій (Phlex + `@theme`-токени + `tokens()`) production-grade; **дизайн-система ≠ повністю мігрована**: shared-компоненти чисті, але raw-Tailwind у прикладних компонентах лишається (токен-міграція UI.1-3), а `gaia:lint_tokens` **enforced у CI з 2026-08-07 — але рівно на shared-поверхні**, де §3.5 сиру Tailwind забороняє; доменні компоненти §3.5 явно дозволяє, тож їх міграція лишається косметичною роботою UI.1, не гейтом. Потребує production verification.
- **Стек:** Rails 8.1 · Phlex · Tailwind CSS 4 · TailwindMerge · Stimulus · Turbo 8
- **Відкрите:** production verification (UI на живому деплої) — [`06_01 §DEPLOY-DAY`](06_01_Deployment_Kamal_Terraform); UI-беклог (токен-міграція / a11y / i18n) → [`00_07`](00_07_Action_Plan_Tracker) UI.1/UI.2/UI.3, I18N.1.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | Моделі (дані для компонентів) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (сервіси) |
| [`04_03` — REST API v1 Reference](04_03_REST_API_v1_Reference) | REST API (Turbo Frame ендпоінти) |
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Прошивка (OTA progress streams) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (UI.1/UI.2/UI.3, I18N.1) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Огляд Архітектури](#1-огляд-архітектури)
- [2. ApplicationComponent — Базовий Клас](#2-applicationcomponent--базовий-клас)
- [3. Tailwind Дизайн-Токени](#3-tailwind-дизайн-токени)
- [4. Шкала Типографіки](#4-шкала-типографіки)
- [5. TailwindMerge та патерн `tokens](#5-tailwindmerge-та-патерн-tokens)
- [6. Реєстр Компонентів](#6-реєстр-компонентів)
- [7. Stimulus Контролери](#7-stimulus-контролери)
- [8. Інтеграція Turbo (Streams & Frames)](#8-інтеграція-turbo-streams--frames)
- [9. Чекліст Доступності](#9-чекліст-доступності)
- [10. Lookbook (Дослідник Компонентів)](#10-lookbook-дослідник-компонентів)
- [Додаткові Матеріали](#додаткові-матеріали)
- [11. Міграція з ActionController::API на ActionController::Base](#11-міграція-з-actioncontrollerapi-на-actioncontrollerbase)
- [12. Інтернаціоналізація та Локалізація (i18n)](#12-інтернаціоналізація-та-локалізація-i18n)
- [13. Mobile Drawer (Phase 2)](#13-mobile-drawer-phase-2)
- [14. Animations & Motion (Phase 3)](#14-animations--motion-phase-3)
- [15. Native HTML over Stimulus (де доречно)](#15-native-html-over-stimulus-де-доречно)
- [16. Codemod-Driven Migration (Phase 4)](#16-codemod-driven-migration-phase-4)
- [17. Responsive Tables — CSS-only Card Flip (Phase 5)](#17-responsive-tables--css-only-card-flip-phase-5)
- [18. Industry Standards (SSOT) + Per-PR Definition of Done](#18-industry-standards-ssot--per-pr-definition-of-done)
<!-- TOC:AUTO:END -->

---

## 1. Огляд Архітектури

SilkenNet використовує підхід **Ruby-first, utility-CSS**: всі в'юшки — це Phlex Ruby-класи (без `.erb` шаблонів для доменної логіки), стилізовані виключно Tailwind utility-класами, об'єднаними без конфліктів через TailwindMerge.

Дизайн-система побудована за принципом **dark-first** — термінальна/кіберпанк естетика з emerald-акцентами (`#10b981`) на майже-чорних поверхнях (`--gaia-surface-base` `#050607` / `--gaia-surface` `#0b0f0e`; сирий `bg-black` = `#000000` — легасі-форма, що мігрує геть, §3.5).

⚖️ **Присуд founder-а 2026-08-07: dark — типова тема, але світла ПІДТРИМУВАНА, не факультативна.** Тумблер, що дає чорне на чорному, — зламана обіцянка в UI, і платформа, чия місія — свідчити правдиво, не має права возити такий тумблер. Тобто:

- **Кожен екран, до якого тема дотягується, мусить працювати в обох.** Сира палітрова утиліта на поверхні чи тексті — дефект теми, а не естетичний вибір (§3.5).
- **Екран має право бути свідомо однотемним, лише якщо він це ОГОЛОШУЄ.** Тихо ламатись — не «однотемність», а поломка. ⚠️ **Прикладом тут доти стояв `AuthLayout` (`html(class: "h-full dark")`) — його знято присудом 08-08 разом із тумблером,** бо після переходу на `prefers-color-scheme` цей хардкод лишався ЄДИНИМ місцем, що опиралось середовищу: людина зі світлою ОС діставала темний екран входу й світлу решту. Тобто оголошена однотемність лишається легальною формою, але **живих екземплярів у дереві зараз нуль**, і новий заводиться присудом, а не успадкуванням.
- Доти тут стояло «Світлий режим — вторинний, **висококонтрастний** варіант». Друге слово **спростовано виміром** (2026-08-07): на гібридних панелях світла тема давала 1.11–1.13:1, тобто текст фізично невидимий. Стан міграції → [`00_07`](00_07_Action_Plan_Tracker) UI.1.

⚖️ **Присуд founder-а 2026-08-08 — ТУМБЛЕР ЗНЯТО, дві палітри лишаються під керуванням СЕРЕДОВИЩА (`prefers-color-scheme`).** Це не реверс присуду вище, а його уточнення: «світла підтримувана» лишається чинним, змінюється рівно те, **ХТО** її вмикає. Ухвалено після восьмивекторного дослідження (ціна · глядачі · доступність · рамка питання · масштаб · енергія · adversarial · форма).

- 🔴 **Знімається ОРГАН ВИБОРУ, бо він не витримав жодної перевірки.** Тумблер народився на 17-й день життя репо — раніше за майже всі екрани, тобто був шаблонним очікуванням, а не відповіддю на потребу. У коді він **однобічний храповик**: після першого кліку `handleSystemChange` виходить на `localStorage.getItem("theme")` і ОС не слухається **ніколи**; стану «system» не існує. Тобто як інструмент вибору він **гірший за той, що вже є в операційній системі** — і при цьому дублює рішення, яке людина вже ухвалила один раз для всіх застосунків.
- 🔴 **І він ламав ВІДТВОРЮВАНІСТЬ — критерій місії, не зручність** ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap)). Клієнтський theme-стан робить рендер недетермінованим: скріншот, який аудитор чи рецензент зробить зі сторінки, залежить від його `localStorage`. Для D-MRV-платформи, чиє призначення — свідчити відтворювано, це не косметика.
- ✅ **Дві палітри ЛИШАЮТЬСЯ, і причина не естетична — вимірювальна.** Друга тема є **mutation-тестом дизайн-системи**: будь-який хардкод ламається видимо хоча б в одній із них. Це не теорія — саме контраст-робота над дуальністю знайшла фантомний `--gaia-primary-text` (токен не існував → **1.98:1 на кнопках у ТЕМНІЙ**, єдиній, якою користуються) і клас «відсутнє перевизначення» (`--gaia-label` протікав із `:root`). При одній темі обидва дефекти лишились би невидимими назавжди.
- ✅ **Ergonomічна підстава для другої палітри — ambient, якого сервер не бачить.** Прилади темні тому, що диспетчерські темні, а не тому, що темне краще: у фотопічних умовах підтверджена перевага **позитивної** полярності, і вона найбільша саме на дрібних кеглях — а наша шкала це `micro`/`mini`/`tiny` (8–10px, §4). Інженер уночі й аудитор удень у скляному офісі — різна фізика зіниці. ОС знає про це більше за нас (авто-яскравість, датчик, нічний режим), тому рішення віддається їй.
- **Ціна названа чесно:** людина, чия ОС стоїть у світлому режимі, отримує світлу тему — і доти, доки триває міграція UI.1, вона побачить її незавершеною. Це свідомо прийнято: обіцянка «ми даємо тобі вибір» замінена на «ми поважаємо вибір, який ти вже зробив».
- 🔴 **Що НЕ змінюється, і це половина присуду: токен-шар лишається ОБОВ'ЯЗКОВИМ.** «Тем менше» ≠ «токени зайві»: `status-*` мапують стани на **ролі**, `#10b981` уже стоїть літералом у ~24 місцях (ребренд без токенів = обхід 55+ файлів), вимірювач контрасту адресує **пари токенів**, `gaia-primary`/`gaia-primary-text` — контракт 7.04:1, а 4-tier глибина — граматика. **Легалізація сирої палітри є єдиною справді незворотною дією в цій темі** — усе інше git повертає за годину.
- ⚠️ **Режим власної відмови — «невидима друга палітра»:** тему, на яку ніхто не дивиться щодня, ніхто й не помічає, коли вона гниє. Сторож проти цього — не дисципліна, а прилад: браузерний контраст-пін ходить **обома** темами (`spec/features/contrast_root_tokens_spec.rb`), і його вартість — єдина причина, чому дуальність лишається дешевою.

**Тема перемикається РІВНО однією шафою — медіа-запитом `prefers-color-scheme`**, і застосовує її чистий CSS. Класу теми на `<html>` немає, клієнтського стану немає, кроку JS у цьому ланцюгу немає взагалі. Механіка того, чому шафа саме одна, — §3.

✅ **Демонтаж ВІДВАНТАЖЕНО — присуд і код тепер збігаються.** Знято: `ThemeSwitcher`, `theme_controller.js`, FOUC-скрипт у `<head>`, ключ `theme.toggle_label` ×4 локалі, CSS-блок `::view-transition` (його єдиним тригером був `startViewTransition` у тому ж контролері) і хардкод теми в `AuthLayout`. Токени переїхали з селектора `.dark` у `@media screen and (prefers-color-scheme: dark)`, а `@custom-variant dark` перевизначено на ТОЙ САМИЙ запит — тобто обидві половини шафи (семантичні токени й сирі `dark:`-утиліти) тепер гейтуються одним рядком.

- 🔴 **`screen and` в обох половинах — несуче, не косметика.** Дефолт Tailwind v4 — медіа-запит БЕЗ `screen`, тож варіант без нього дав би темні `dark:`-утиліти на світлому друкованому аркуші: та сама «дві шафи», лише в print-контексті, і невидима для будь-якого екранного піна. Носій — `spec/features/theme_shaft_spec.rb`, приклад про `screen and`; він судить ДЖЕРЕЛО, бо `app/assets/builds/` у `.gitignore` (гейт по ньому був би зелений на порожній множині).
- 🔴 **Браузером цю половину довести НЕ можна, і це виміряно:** `Emulation.setEmulatedMedia` з `media: "print"` оновлює `matchMedia` (складений запит чесно стає `false`), але обчислені стилі вже відрендереної сторінки Chrome не перераховує — фон лишається темним при запиті, який більше не матчиться. Браузерний приклад тут міряв би момент рестайлу в рушії, а не наш CSS, і був би червоним на правильному коді.
- ⚠️ **Зникнення FOUC-скрипта закрило суміжну міну:** він рендерився інлайном **без nonce**, тоді як `content_security_policy.rb` оголошує `script_src :self` і nonce-генератор. Під `CSP_ENFORCE=true` (плановий операторський тумблер — [`06_04 §1`](06_04_Secrets_Checklist)) скрипт було б заблоковано, клас не поставився б, і **весь флот отримав би світлу тему**, яку §3 описує як ще не мігровану. Тепер тема не залежить від виконання JS у принципі.

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
│   ├── ui/                     # Домен-агностичні елементи — ТІЛЬКИ токени, сирий Tailwind заборонено (§3.5)
│   ├── iot/                    # Hardware-специфічні відображення (значення сенсора)
│   └── web3/                   # Blockchain-специфічні відображення (адреса, tx)
│
└── app/views/components/       # Доменні компоненти рівня сторінки — сирий Tailwind ДОЗВОЛЕНО (§3.5)
    ├── navigation/             # Sidebar: меню, фільтроване роллю актора [UI.5]
    ├── dashboard/              # Головна, Leaflet-мапа, стрічка подій
    ├── trees/                  # Картка дерева, хроніка
    ├── wallets/                # Баланс, журнал транзакцій, lazy-фрейми
    ├── alerts/                 # EWS-тривоги
    ├── telemetry/              # Live-HUD, декодований рядок пакета
    ├── oracle_visions/         # Прогноз Лоренца, what-if симуляція
    ├── clusters/               # Кластери дерев
    ├── gateways/               # Королеви (шлюзи)
    ├── actuators/              # Виконавчі механізми + черга команд
    ├── firmwares/              # OTA: завантаження, викотка, прогрес
    ├── maintenance/            # Записи обслуговування + фотодокази
    ├── contracts/              # NaaS-контракти
    ├── blockchain_transactions/ # Аудиторський on-chain леджер
    ├── reports/                # Карбон, фінанси
    ├── tree_families/          # Довідник видів
    ├── codex/                  # Lore Layer (read-only наратив) — власний канон 04_05
    ├── organizations/          # Реєстр кланів + перемикач контексту [UI.6]
    ├── users/                  # Список, профіль
    ├── audit_logs/             # Журнал привілейованих дій
    ├── system_audits/          # Платформенні fraud-сигнали
    ├── system_health/          # Стан підсистем
    ├── provisioning/           # Реєстрація пристрою
    ├── account_security/       # Пароль, сесії, MFA
    ├── notifications/          # Налаштування сповіщень
    ├── settings/               # Налаштування тенанта
    ├── errors/                 # Сторінки помилок + карантин без організації
    ├── sessions/               # Логін
    └── passwords/              # Відновлення пароля
```

> **Дерево показує ЯРУСИ й неймспейси, а не листки — це свідомо.** Поіменний реєстр компонентів має рівно один дім: §6.1–6.3 (shared) і §6.4 (доменні). Доти дерево дублювало обидва й тихо старіло швидше за них — на момент введення гейта воно рекламувало два вже видалені компоненти й мовчало про чотири нові. Звірку тримає `component_doc_sync` [UI.12]: **неймспейси** тут ⟷ директорії `app/views/components/*`, **листки** — у §6.


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
            └─► render_auth_page(title:, component:, status: :ok)
                    └─► render AuthLayout.new(title:, content: component)
                            └─► AuthLayout.view_template
                                    └─► render @content  ← Auth Component (Sessions::New, Errors::NoOrganization, etc.)
```

> **⚠️ Важливо:** Content component передається як параметр `content:` — **НЕ через блок**.
> Ruby closure блоку виконується в контексті контролера, тому `render` всередині блоку
> викликає `ActionController::Base#render` (DoubleRenderError), а не `Phlex::HTML#render`.

### Layout Компоненти

| Layout | Файл | Включає | Призначення |
|---|---|---|---|
| `DashboardLayout` | `app/views/layouts/dashboard_layout.rb` | `Phlex::Rails::Layout` | Основний layout з sidebar, top bar, breadcrumbs, **flash-регіонами** (↓). Топ-бар несе **індикатор робочого контексту** (`acting_organization:`, super_admin-only) — і це не оздоба, але причина вужча, ніж тут стояла: доти писалось «`switch` flash не ставить, тож індикатор — ЄДИНИЙ канал», і це знято 2026-08-01 (перемикач тепер ставить `success`, [SEC.25 Ф3]). Індикатор лишається несучим тому, що показує стан **постійно**, тоді як повідомлення живе один запит [UI.6]. ⚠️ Тут доти стояло ще й «цей layout `flash` не рендерить **узагалі**» — правда до [SEC.25], знято 2026-08-01 разом із появою поверхні. Станів свідомо два («обрано X» / «не обрано»): дім формули розходження (`Current#switched_context?`) **амбієнтний**, а `Current` як джерело даних у в'ю заборонений його ж шапкою; третій стан має сенс лише для super_admin із домашньою організацією й додається одним рядком, коли такий зʼявиться. ⚠️ Назва організації інтерпольована в `aria-label` — інакше він замінив би доступне імʼя цілком і SR-користувач чув би «змінити організацію», ніколи — яку саме ([UI.3] у сайдбарі) |
| `AuthLayout` | `app/views/layouts/auth_layout.rb` | `Phlex::Rails::Layout` | Легкий layout для login/password сторінок; несе ті самі **flash-регіони** (↓) |

#### Flash-поверхня [SEC.25]

**Обидва** layout'и рендерять `Views::Shared::UI::FlashMessages`, а `flash` приходить **явним kwarg'ом** із `render_dashboard`/`render_auth_page` — це єдина точка його читання в дереві. Компонент навмисно не звертається до `helpers.flash` (попри те, що `Phlex::Rails::Helpers::Flash` існує): поза request-контекстом `helpers` = `nil`, тож амбієнтне читання зробило б layout нерендерабельним у компонентних спеках, які йдуть через `ApplicationController.renderer`. Та сама причина, що й у `current_user`/`ews_alert_count` — layout **приймає** дані, а не ходить по них сам.

🔴 **Обидва live-regions присутні в DOM ЗАВЖДИ, навіть порожні.** Це не стиль, а умова роботи скрінрідера: регіон, вставлений у DOM разом зі своїм вмістом, AT не оголошує — вона слухає зміни всередині вже відомого їй регіону.

✅ **Категорій ЧОТИРИ, регіонів ДВА (шипнуто 2026-08-01).** Це не той самий список під двома іменами: регіон тримає **a11y-контракт** (скільки оголошень знає AT і як голосно кожне говорить), категорія — **семантику й тон**. Мапінг: `error` + `security` → assertive (`role="alert"`), `success` + `pending` → polite (`role="status"`). Розширювати можна лише категорії — четверо регіонів зробили б «ощадливе assertive» неможливим, а APG вимагає саме ощадливості.

- **Id називає РЕГІОН, не категорію** — `flash_assertive` / `flash_polite`. Доти вони звались `flash_alert`/`flash_notice`, і після розширення таке ім'я брехало б: у «notice»-регіоні сидів би `pending`, а в «alert» — `security`, яка помилкою не є. Старі імена не збережено свідомо: єдиний пін, що їх тримав, був **вакуумний** (обидва регіони рендеряться завжди, тож `include('id=…')` істинне для будь-якої сторінки), тобто платою за нього була б постійна двомовність.
- **Регіон перебирає ВСІ свої категорії.** `flash` за побудовою може нести і змете з попереднього запиту, і поставлене в поточному, тож `success` разом із `pending` — легальний стан; читання одного значення на регіон мовчки з'їдало б друге повідомлення.
- **Тон призначено так, щоб гучність і вигляд не розходились.** Найтонше місце — `security`: вона їде в assertive, тож спокійний синій дав би зрячому м'яку плашку там, де незрячому обривають фразу; бурштин (`status-warning`) узгоджує обидва канали, лишаючись НЕ помилкою. Дзеркально `pending` дістає синій (`status-info`) — «прийнято, результату ще нема» — нейтральна інформація, не тривога.
- ✅ **Це і є форма закриття a11y-залишку.** Усе, що МУСИТЬ бути почуте (відмова · зміна безпекового стану), потрапляє в assertive, який AT озвучує й тоді, коли вузол приходить разом зі вмістом — **без жодного JS**. Ціна названа чесно й прийнята: буденне «збережено» для незрячого може лишитись тихим.

🔴 **Категорія мусить бути ЗАРЕЄСТРОВАНА, інакше гине на два шари вище за компонент.** `ActionController::Flash#redirect_to` перебирає ЛИШЕ `_flash_types` і робить `delete` тільки для них; невідомий kwarg їде далі в `Redirecting`, де читають самий `:status` — ні винятку, ні логу. Тому `add_flash_types :success, :error, :pending, :security` стоїть у **двох** коренях (`Api::V1::BaseController` і `ApplicationController`): спільного предка вони не мають — `BaseController` успадковує `ActionController::Base` напряму, — тож реєстрація в одному місці покрила б лише `locales_controller`. ⚠️ **Наслідок для будь-якого майбутнього сторожа цієї осі:** статичний AST-сторож, що звіряє імена категорій із мапою компонента, у сценарії забутої реєстрації **ЗЕЛЕНИЙ** (усі імена «відомі»), і гучний `raise` у компоненті теж (хеш приїжджає порожнім — дропати нема чого). Ловить лише наскрізний приклад із `follow_redirect!` — дім доказу `spec/requests/api/v1/flash_categories_spec.rb`, по одному на категорію, мутація-перевірено (зняття реєстрації червонить усі чотири).

⚠️ **`flash.*` — НЕ простір flash-повідомлень.** Ключі живуть у **двох** домах (`config/locales/flash/` + `config/locales/defaults/`), і чимала їх частина адресує виключно JSON-відповіді — актуатори, телеметрія, ланцюг. Не бери імʼя неймспейса за периметр роботи. ⚠️ **Лічильника тут свідомо немає, і це куплено:** він стояв, протух мовчки (кожна хвиля flash-роботи додає ключі — власний `context_switched` з Ф3 у тому числі, — а речення за ними не встигає) і був спійманий лише окремим свіпом. Міряй грепом у момент питання, не цитатою.

⚠️ **Свідомо без таймера й без кнопки закриття.** WCAG **2.2.1** («Timing Adjustable», рівень A) — критерій про *часові ліміти*; поки ліміту немає, вимога «дай вимкнути / подовжити» не виникає взагалі. Auto-dismiss створив би зобов'язання, яких зараз не існує, а на мобільному (`hover: none`) механізму паузи фізично немає — тобто пауза захищала б лише тих, хто й так за столом. Повідомлення живе до наступної навігації.

⚠️ **Морф і flash:** вузол, якого немає у свіжій відповіді, Idiomorph видаляє — але Turbo **перехоплює** це, підставляючи власний колбек (`beforeNodeRemoved = node => this.beforeNodeMorphed(node)` → cancelable `turbo:before-morph-element`, гард `instanceof Element`). Тобто утримати повідомлення через морф **можливо**, і для наших регіонів навіть простіше: вони рендеряться завжди, тож при морфі мають пару й подія приходить штатним шляхом. ⛔ **Але утримувати його ми свідомо НЕ будемо (won't-do 2026-08-01):** редиректів «на ту саму адресу» серед усіх flash-сайтів рівно три, і flash на morph-підписаній сторінці садять два рядки одного контролера. (⚠️ Загальне число сайтів тут навмисно не називається — воно дрейфує з кожною хвилею: Ф3+Ф4 додали чотири нові; несуча величина — саме «три same-location», і вона від них не змінилась.) Гард ще й виробляв би БРЕХЛИВЕ підтвердження при роботі пачкою (утримана плашка першої дії лишалась би за другу) і осідав у кеші снапшотів, тобто «Назад» оголошував би дію десятихвилинної давнини. 🔴 **І дві підстави, видимі лише з коду, а не з дизайну — саме вони роблять «просто додай гард» пасткою.** (а) `beforeNodeRemoved` кличе `beforeNodeMorphed(node)` з ОДНИМ аргументом, тож `detail.newElement` буває `undefined`: предикат, написаний по ньому, кинув би `TypeError`, а виняток у слухачі `defaultPrevented` **не ставить** — вузол зникає все одно, лишаючи по собі самий шум у консолі. (б) Селектор за РОЛЛЮ колізує живо: `Alerts::Row` несе `role="status"` двічі, тож гард заморозив би рівно той канал, який на цій сторінці й визнано правильним. ⚠️ Якщо колись знадобиться — селектор рівно `#flash_assertive, #flash_polite` (не за роллю), предикат по `newElement`, а `data-turbo-temporary` на **ВНУТРІШНЬОМУ** `div`, ніколи на самому регіоні: інакше зникає регіон, і падає a11y-інваріант «обидва присутні завжди». Канал підтвердження на таких сторінках — **СТАН** (як `Alerts::Row` уже робить), не повідомлення.

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

  CUSTOM_TEXT_SCALE = %w[micro mini tiny compact display-sm display-md display-lg].freeze

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
- **`@custom-variant dark (@media screen and (prefers-color-scheme: dark))`** — рядок, що прив'язує варіант `dark:` до ТОГО САМОГО медіа-запиту, під яким стоять семантичні токени. Дефолт Tailwind v4 (`@media (prefers-color-scheme: dark)`, без `screen`) відрізняється рівно на друк: без `screen and` утиліти лишились би темними на аркуші, поки токени світлішають — «дві шафи», що живуть лише в print-контексті. ⚠️ Доти тут стояла **класова** форма (`&:where(.dark, .dark *)`), потрібна, поки тему обирав тумблер; після присуду 08-08 клас із ланцюга зник, і класова форма зробила б `dark:`-утиліти мертвими (жоден вузол більше не несе `.dark`).
  - **Носій — `spec/features/theme_shaft_spec.rb`**, і він дво­шаровий за потребою: два браузерні приклади доводять, що при кожній емульованій перевазі ОС токен і `dark:`-утиліта опиняються в ОДНОМУ стані (доводиться ЗБІГ, бо клієнтського важеля для розведення більше не існує), а третій — статичний — стереже `screen and` у кожному media-запиті теми. Статичний саме тому, що браузером ця половина недоказовна: `Emulation.setEmulatedMedia` з `media: "print"` оновлює `matchMedia`, але не перераховує стилі вже відрендереної сторінки (виміряно), тож поведінковий приклад червонів би на правильному коді.

> `config/tailwind.config.js` видалено — він порушував SSOT, дублюючи кожен токен на рівні JS.

### 3.1 Поверхневі, Текстові та Основні Токени (`gaia-*`)

> **Phase 1 of the frontend overhaul (Tailwind v4 SSOT).** Палітра розширена
> до 4-tier surface depth scale (Material 3 elevation pattern) і 3-level text
> hierarchy для адекватного контрасту в light/dark. Перемикання теми тепер
> змінює усі поверхні, а не лише текст. Legacy `--gaia-surface-alt` видалено —
> усі call-sites мігровано на `--gaia-surface-sunken`.

#### Surfaces (4-tier depth)

| Токен | Tailwind Клас | Light `#` | Dark `#` | Призначення |
|---|---|---|---|---|
| `--color-gaia-surface-base` | `bg-gaia-surface-base` | `#fafafa` | `#050607` | Page background (під `<body>`) |
| `--color-gaia-surface` | `bg-gaia-surface` | `#ffffff` | `#0b0f0e` | Картки, панелі, форми |
| `--color-gaia-surface-elevated` | `bg-gaia-surface-elevated` | `#ffffff` (+`shadow-lg`) | `#11161a` | Modals, popovers, dropdowns |
| `--color-gaia-surface-sunken` | `bg-gaia-surface-sunken` | `#f3f4f6` | `#070a09` | Table-row alt, code blocks, input bg, table headers |

#### Text (4-рівнева ієрархія)

| Токен | Tailwind Клас | Light `#` | Dark `#` | Призначення |
|---|---|---|---|---|
| `--color-gaia-text-strong` | `text-gaia-text-strong` | `#0f172a` | `#e6fff4` | Headings, primary numbers |
| `--color-gaia-text` | `text-gaia-text` | `#1f2937` | `#a7f3d0` | Body |
| `--color-gaia-text-muted` | `text-gaia-text-muted` | `#52525b` | `#6ee7b7` | Labels, metadata |
| `--color-gaia-text-subtle` | `text-gaia-text-subtle` | `#5f6875` | `rgba(52,211,153,0.68)` | Найтихіший рівень **живого контенту** — хлібні крихти, заголовки секцій меню, `thead`, підписи одиниць. ⚠️ **НЕ декорація:** доти тут стояло «Placeholders, watermarks, disabled», і цей опис **легалізував дефект** — декорація й `disabled` є нормативними винятками з 1.4.3, тож рядок читався як дозвіл стояти нижче AA. Реальні watermark'и несуть власний `text-emerald-900/5` + `aria-hidden`, а не цей токен |

> 🔬 **Значення обох текстових «тихих» токенів (`text-subtle`, `gaia-label`) — не смак, а вимір.** Світлий `subtle` є проміжним між Tailwind-500 і -600 свідомо: жоден палітровий «500» не тримає AA на `--gaia-surface-sunken`, а «600» дорівнює `--gaia-text-muted` і зламав би ієрархію. У темній роль контрасту несе **альфа**, бо всі темні поверхні майже-чорні й обмеження односпрямоване. Числа живуть у носії `spec/features/contrast_root_tokens_spec.rb`, не в цій таблиці — тут лише значення.
>
> 🧱 **Передумова, без якої світла половина недосяжна В ПРИНЦИПІ:** доки під токенізованим текстом лежить **сира тем-інваріантна темна поверхня** (`bg-black`, `bg-zinc-950`, градієнт `to-black`), скаляр мусить бути одночасно темнішим за стелю світлих `gaia`-поверхонь і світлішим за підлогу чорної панелі — смуга порожня, значення **не існує**. Тому міграція таких поверхонь на `gaia-*` не є сусідньою прибиранкою: вона передумова. Це та сама арифметика, що зупинила `gaia-primary` (§1 ⚖️-блок), лише там суперечність несе роль, а тут — поверхня.

#### Primary + borders

| Токен | Tailwind Клас | Light `#` | Dark `#` | Призначення |
|---|---|---|---|---|
| `--color-gaia-primary` | `text-gaia-primary` / `bg-gaia-primary` | `#10b981` | `#10b981` | Бренд-emerald (однаковий) |
| `--color-gaia-primary-text` | `text-gaia-primary-text` | `#0f172a` | `#0f172a` | **Текст НА `bg-gaia-primary`** (7.04:1). Тем-інваріантний, бо сам primary не фліпається — пара мусить триматись в обох. ⚠️ Не плутати з `text-gaia-primary` (бренд-акцент НА поверхні); ці два токени стоять по різні боки одного фону |
| `--color-gaia-primary-hover` | `hover:bg-gaia-primary-hover` | `#059669` | `#34d399` | Hover primary |
| `--color-gaia-primary-soft` | `bg-gaia-primary-soft` | `#d1fae5` | `rgba(16,185,129,0.12)` | Chips, pills, low-emphasis bg, active-nav highlight |
| `--color-gaia-border` | `border-gaia-border` | `#e5e7eb` | `rgba(16,185,129,0.18)` | Default межі |
| `--color-gaia-border-strong` | `border-gaia-border-strong` | `#cbd5e1` | `rgba(16,185,129,0.40)` | Hover-borders, dividers, focus-ring backup |

> **Legacy-кольори `gaia-green`, `gaia-dark`, `gaia-muted` видалені.** Семантичні токени `gaia-primary`, `gaia-text-muted`, `gaia-text` залишаються.

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
| `--color-gaia-label` | `text-gaia-label` | `#6b7280` | `#7d8590` |

> ⚠️ **Темне значення зʼявилось 2026-08-08, і дефект був не в ньому, а у ВІДСУТНОСТІ рядка:** `.dark` цього токена не перевизначав узагалі, тож мітка полів читалась світлим значенням, що протекло з `:root` (3.99:1 на `gaia-surface`). Світле лишилось як було. ⚠️ Латентна межа, названа виміром: `#6b7280` на `--gaia-surface-sunken` дає **4.39** — сьогодні жодна форма туди не переїхала (усі три на `bg-gaia-surface`, 4.83 ✅), тож носій чесно зелений, але токен за один крок «перенести форму на sunken» від червоного.

### 3.5 Правила Використання Кольорів

| ✅ Правильно | ❌ Заборонено |
|---|---|
| `bg-gaia-surface` | `bg-white` / `bg-black` (у shared-компонентах) |
| `text-gaia-text` | `text-gray-900` / `text-emerald-400` (у shared-компонентах) |
| `border-gaia-border` | `border-gray-200` / `border-emerald-900` (у shared-компонентах) |
| `bg-status-danger text-status-danger-text` | `bg-red-100 text-red-800` |
| `shadow-sm dark:shadow-none` | `shadow-lg` скрізь |

> 🔴 **Виняток ЗВУЖЕНО 2026-08-07 (⚖️ присуд §1: світла тема підтримувана).** Доти тут стояло: «Доменні page-компоненти можуть використовувати raw Tailwind кольори … для кіберпанк-естетики, **оскільки вони не переповикористовуються** у різних контекстах». Дозвіл спирався на вісь **ПЕРЕВИКОРИСТАННЯ**, а надавався на вісь **ТЕМИ** — а це різні речі: колір, зашитий на одноразовій сторінці, так само тем-мертвий, як і в спільному компоненті. Саме цей рядок легалізував екрани, на яких тумблер не працює.
>
> **Чинне правило:** сире палітрове значення дозволене лише там, де воно **тем-інваріантне за задумом**, і такий ужиток мусить бути **оголошений**. Два визнані класи: (а) бренд-глоу декорація — вичерпний перелік у §16.4 (`animate-ping`/`animate-pulse`/`animate-spin` акценти); (б) значення, що мусить лишатись тим самим в обох темах, як `backdrop:bg-black/60` — scrim під мобільною шухлядою, який поверхневий токен зробив би блідим у світлій. Сира поверхня (`bg-black`, `bg-zinc-950`) чи сирий текст (`text-emerald-400`) на доменній сторінці — **дефект теми**, не естетичний вибір.
>
> ⚠️ Правило сьогодні строгіше за периметр гейта: `gaia:lint_tokens` тримає `app/views/shared/**` HARD (§16.1), а доменні компоненти заводяться порційно, кожне розширення — після власної migrate-хвилі. Залишок міряй командою, не числом із доки: `COMPONENTS=app/views/components/ bin/rails gaia:lint_tokens`. Стан і черга → [`00_07`](00_07_Action_Plan_Tracker) UI.1.

### 3.6 Tailwind v3 → v4 Cheatsheet [DOC.11]

> **Контекст:** Проект використовує **Tailwind CSS v4** (нативно, без PostCSS-плагіна). Якщо ви прийшли з v3-кодової бази (зокрема старого fork'а / зовнішнього прикладу), нижче — найкритичніші відмінності, які впливають на наші файли.

| Аспект | Tailwind v3 (legacy) | Tailwind v4 (поточний) |
|--------|---------------------|------------------------|
| **Конфігурація** | `tailwind.config.js` (JS-об'єкт `theme.extend.colors`) | `@theme { --color-*: ... }` блок у CSS, **видалено** `tailwind.config.js` |
| **Tokens SSOT** | JS дублює CSS-змінні | CSS — єдина точка істини; Tailwind v4 автогенерує utility-класи з `@theme` змінних |
| **Підключення** | `@tailwind base; @tailwind components; @tailwind utilities;` (3 директиви) | `@import "tailwindcss";` (1 рядок) |
| **Кастомні утиліти** | `@layer utilities { .my-class { ... } }` | `@utility my-class { ... }` (нова синтаксис, працює як first-class) |
| **Темні режими** | `darkMode: 'class'` у JS-конфігу + `dark:` префікс | **`@custom-variant dark (&:where(.dark, .dark *))`** у CSS + `dark:` префікс (без JS-конфігу). Директива саме `@custom-variant` — `@variant` лише ВЖИВАЄ варіант усередині правила. Дефолт без цього рядка = `@media (prefers-color-scheme)`, тобто ОС, а не клас (§3) |
| **Opacity-модифікатори** | `bg-red-500/50` (потребує JIT) | `bg-red-500/50` (нативно, працює завжди) |
| **CSS-змінні в utility** | потрібен arbitrary-value: `bg-[var(--my-color)]` | автоматично: будь-який `--color-X` у `@theme` → `bg-X` |
| **Container queries** | потрібен плагін | вбудовано: `@container`, `@max-md:`, `@min-lg:` |
| **PostCSS-залежність** | потрібен `postcss.config.js` + `tailwindcss/nesting` | необов'язково (CLI або Vite-плагін достатньо) |
| **Браузери** | IE11/legacy via `target: 'modern'` | Chrome 111+, Safari 16.4+, Firefox 128+ (немає legacy fallback) |

**Конкретні наслідки для нашого репо:**
- `config/tailwind.config.js` **видалено** (S1.7). Якщо ви бачите цей файл у старому fork'у — НЕ копіювати назад.
- `app/assets/tailwind/application.css` — **єдиний** файл-джерело для дизайн-токенів. `@theme { --color-gaia-*: ... }` блок є SSOT.
- 🔴 **Урок, куплений цим самим рядком таблиці (2026-08-07):** він описував конфігурацію темного режиму так, ніби це наш стан, — а рядка `@custom-variant` у CSS **не існувало взагалі**, і `dark:`-утиліти місяцями їхали на ОС. Cheatsheet за жанром пише «ось як у v4 робиться», а читається як «ось як у нас зроблено», і **відсутності рядка не було на чому почервоніти**. Тому будь-яке твердження цієї секції про НАШУ конфігурацію мусить називати файл і мати носія — не лишатись описом можливостей фреймворку.
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
| `--font-size-display-sm` | `text-display-sm` | `clamp(1.25rem, 1.6vw + 0.5rem, 1.5rem)` | — | Responsive H3 / section headers |
| `--font-size-display-md` | `text-display-md` | `clamp(1.5rem, 2vw + 0.75rem, 2rem)` | — | Responsive H2 / page sub-titles |
| `--font-size-display-lg` | `text-display-lg` | `clamp(1.875rem, 3vw + 1rem, 2.75rem)` | — | Responsive H1 / hero titles |

> ¹ px-значення розраховані при root font-size = 16px (стандарт браузера). Оскільки токени задані у `rem`, вони масштабуються разом з налаштуваннями доступності браузера.
>
> ² **`text-display-*` через `clamp()`** — fluid typography (Google Web Vitals
> friendly: уникає CLS-перерозкладок при зміні vw). Реєструються в
> `ApplicationComponent::CUSTOM_TEXT_SCALE` як font-size (а не як text-color).

Стандартні розміри Tailwind продовжують застосовуватись для більшого тексту (наприклад, `text-xs`, `text-sm`, `text-2xl`) — вони співіснують з кастомною шкалою. Кастомні токени зокрема усувають довільні значення на кшталт `text-[9px]` для розмірів менших за `text-xs`.

### Motion Tokens (Phase 1)

| CSS Токен | Значення | Призначення |
|---|---|---|
| `--motion-fast` | `150ms` | Hover/focus transitions |
| `--motion-base` | `220ms` | Standard UI transitions (drawers, modals) |
| `--motion-slow` | `320ms` | Page-level entrances |
| `--ease-out-soft` | `cubic-bezier(0.22, 0.61, 0.36, 1)` | Default easing для UI |
| `--ease-spring` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Playful overshoot (badges, micro-interactions) |

**Глобальний `prefers-reduced-motion`** (WCAG 2.3.3) — у `@layer base`:
усі `animation-duration` та `transition-duration` примусово зводяться до 0.01ms,
коли OS повідомляє про reduced-motion. Для CSS-анімації сторінкам нічого додавати
не треба — правило діє автоматично. ⚠️ **Виняток — canvas/`requestAnimationFrame`:**
CSS-гейт глушить лише `*-duration`, НЕ JS rAF-цикл, тож JS-контролери руху
(`matrix-rain`, `reveal`) мусять САМІ перевіряти
`matchMedia("(prefers-reduced-motion: reduce)")` у `connect()` і виходити (реалізовано).

**`@utility animate-fade-in`** — keyframe `gaia-fade-in` (translateY 4px → 0 +
opacity 0 → 1) тривалістю `--motion-base`. Використовуйте для entrance-анімацій
карток / алертів.

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

Це будівельні блоки рівня фреймворку, що використовуються у всіх доменних в'юшках. ⚠️ **Один виняток, виміряний 2026-07-27: `DataTable` не вживається НІДЕ** — нуль викликачів на весь застосунок (усі 23 таблиці рукописні). Доля «знести чи дотягнути» — відкрите ⚖️ в [`00_07`](00_07_Action_Plan_Tracker) UI.4.

| Компонент | Файл | Ключові Props | Призначення |
|---|---|---|---|
| **FlashMessages** | `flash_messages.rb` | `messages:` | **Два** live-regions (`flash_assertive`→`role=alert`, `flash_polite`→`role=status`) для **чотирьох** категорій (`error`+`security`→assertive, `success`+`pending`→polite); рендериться в ОБОХ layoutʼах, дані приходять kwargʼом із `render_dashboard`/`render_auth_page`. ⚠️ Регіони присутні **завжди, навіть порожні** — умова оголошення скрінрідером; без таймера (WCAG 2.2.1 — критерій про часові ліміти). ⚠️ Id називає РЕГІОН, не категорію; регіон перебирає ВСІ свої категорії (дві одночасно — легальний стан `flash`) [SEC.25] |
| **ErrorSummary** | `error_summary.rb` | `messages:`, `title:` | Зведення причин відмови для форми, що перемалювалась на 422 (`role="alert"`). ⚠️ **Третій жанр повідомлення, не дубль двох інших:** `FlashMessages` несе те, що пережило редирект, `flash_alert:`/`password_error:` в auth-компонентах — ОДНУ наперед відому помилку сабміту, а це — СПИСОК причин від моделі, з якими людина лишається у формі. ⚠️ Рендер **умовний** (дзеркально до `FlashMessages`): відповідь на 422 є повним рендером, вузол приходить новим разом із текстом, і `role="alert"` AT озвучує саме так — порожня коробка тут чутності не додала б. ⚠️ Заголовок — параметр: `provisioning/new` називає інший АКТ («ініціалізація не вдалася»), бо більшість причин там не з валідації моделі, а з guard-клауз контролера [SEC.25] |
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
| **LocaleSwitcher** | `locale_switcher.rb` | `current_locale: nil` | Вибір мови в top-bar: нативний `<select>` + auto-submit (`onchange="this.form.requestSubmit()"`), із видимою submit-кнопкою як progressive-enhancement для no-JS. Перелік мов має ОДИН дім — `config.i18n.available_locales`; `SHORT_CODE_OVERRIDES` тримає рівно ті коди, де мова розходиться з очікуваною країною (`uk`→«UA») [I18N.3]. Форма несе `data-turbo-action="advance"` — без нього same-path редирект став би morph-рефрешем і зніс би полотно Leaflet [UI.11] |
| **MobileNavToggle** | `mobile_nav_toggle.rb` | `target_id: "mobile-nav-drawer"` | Мобільний гамбургер, що відкриває off-canvas-шухляду. Сама шухляда — нативний `<dialog>` у `DashboardLayout`, тож focus-trap, Escape і `::backdrop` дає браузер; Stimulus `mobile-nav` лишається тонким шимом на `showModal()` |

#### StatusBadge — Маппінг Станів

| AASM Стани | Семантичний Стиль |
|---|---|
| `pending`, `dormant`, `maintenance_needed`, `endangered` (Codex lifecycle) | `bg-status-warning text-status-warning-text` |
| `processing`, `updating` | `+ animate-pulse` |
| `manual_review` | `bg-status-warning text-status-warning-text + animate-pulse` — **[DOUBLE-SPEND GUARD]**: tx_hash існує або стан невідомий, потребує ручної звірки |
| **`active`**, `confirmed`, `fulfilled`, `thriving` (Codex lifecycle) | `bg-status-success text-status-success-text` |
| `sent`, `maintenance` | `bg-status-info text-status-info-text` |
| `failed`, `breached`, `deceased`, `faulty`, `destroyed` (Codex lifecycle) | `bg-status-danger text-status-danger-text` |
| `mythical` (Codex lifecycle) | `bg-status-active text-status-active-text` |
| `idle`, `draft`, `offline`, `cancelled`, `removed`, `unknown` (Codex lifecycle), `extinct` (Codex lifecycle) | `bg-status-neutral text-status-neutral-text` |
| `cancelled`, `removed`, `extinct` (Codex) | `+ opacity-50` (застосовується через модифікатор) |

> 🔴 **Примітка щодо `active` — і виправлення того, що тут стояло раніше.** `STYLES` ключований **самим рядком-значенням**, тож фізично не може віддати два стилі на одне слово. `"active"` у ньому **явно перелічений** — як danger, бо його вписав `EwsAlert` (нерозвʼязаний сигнал = погано). Отже будь-яка сутність, передана в `StatusBadge` зі станом `active`, дістає **червоне** — включно зі здоровим `Tree`/`Gateway`/`NaasContract`/`Actuator`, для яких те саме слово означає «все гаразд».
>
> ⚠️ Доти тут писалось, що для них `active` «відповідає `DEFAULT_STYLE`, оскільки `StatusBadge` маппить лише явно перелічені стани». Передумова правдива, висновок — ні: слово перелічене, тому fallback не спрацьовує. Таблиця вище це знала (рядок danger прямо каже «`active` (EwsAlert)»), тобто док суперечив сам собі через дві лінійки — і саме ця примітка запевняла б виконавця дротування, що пастки немає. Доменні компоненти тримають власну inline-логіку кольорів **через цю колізію**, а не тому, що спільна мапа для них нейтральна.
>
> ✅ **Колізію РОЗВʼЯЗАНО 2026-08-05 разом із дротуванням.** `active` = `bg-status-success`, бо всі пʼять живих власників слова (`Tree` · `Gateway` · `NaasContract` · `Actuator` · `ParametricInsurance`) кажуть ним «усе гаразд»; носій протилежного значення зник разом із `Alerts::Badge` (§8.3), а решта UI тривог ходить булевими предикатами (`status_resolved?`), не словом. Пін фальсифіковний і мутація-перевірений — `spec/views/shared/ui/status_badge_spec.rb`, «maps active to the success token, never danger».
>
> ⚠️ **«Мертвих записів 27 із 33» було фотографією стану, а не властивістю мапи** — і саме тому зняття треба було робити ОДНИМ проходом із дротуванням, а не перед ним. Двадцять шість із тридцяти трьох належали рівно тим шести родинам, які дротування й оживило; справді мертвих виявилось **сім**, і кожен помер із власної причини: `issued`/`acknowledged` — `ActuatorCommand` обслуговується ВЛАСНИМ бейджем (`actuators.command_status_badge`, свої мітки), `resolved`/`ignored` — `EwsAlert` не рендерить статус словом ніде, `triggered`/`paid`/`expired` — `ParametricInsurance` не рендериться взагалі. Знято разом із мітками `ui.status.*` у чотирьох локалях: `enum_label_parity_spec` двобічний, тож осиротіла мітка червонить так само, як відсутня.
>
> 🔴 **Урок, ширший за цей запис:** плаский bag, ключований самим ЗНАЧЕННЯМ, не може віддати два стилі на одне слово — тож перед дротуванням спільного рендерера питай не «чи є запис», а **чи не означає це слово протилежне в іншому домені** (клас → `CLAUDE.md §6`, механіка → §12.14). І окремо: примітка, яка ПОЯСНЮЄ, чому щось безпечне, гниє в бік заспокоєння — саме тут вона двічі поспіль запевняла виконавця, що пастки нема.

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
| `Navigation::Sidebar` | `navigation/sidebar.rb` | `current_path:`, `ews_alert_count:`, `current_user:` | Навігаційна бічна панель з 5 групами секцій (Strategic Insight, **Library** (Codex), Forest Ops, Neural Network, Administration), виділенням активного стану, бейджем EWS-сигналів, пульсуючим статусом. Пункти роле-гейтовані — див. нижче |

> 🔒 **Видимість пункту меню = гард його контролера. Це інваріант, не оформлення [UI.5].** Доти сайдбар не приймав користувача взагалі, тож фільтру за роллю не було ДЕ жити: investor бачив повне меню платформи, і кожен із **одинадцяти** гейтованих пунктів віддавав йому сирий JSON-блоб `render_forbidden`. Це не «виняток на дашборді», а штатний шлях звичайного користувача — тому корінь одноклікових 403 сидить тут, а не в error-рендерерах ([`04_03 §2.2`](04_03_REST_API_v1_Reference)). Один пункт (`clan_hierarchy`) блобив навіть адміну, бо гард там `authorize_super_admin!`.
>
> **Форма:** рівень стоїть у РЯДКУ самого пункту (`nav_item(..., min_role: :admin)`), а не в окремій таблиці — розходження меню з гардом мусить бути видно оком. Правило при цьому тут НЕ живе: `visible_to_actor?` — диспетчер, кожна гілка якого кличе предикат `User` (`forest_commander?` · `admin_or_above?` · `super_admin?`), тобто те саме джерело, що читають `authorize_forester!`/`authorize_admin!`/`authorize_super_admin!`. Інакше меню стало б четвертим домом RBAC-формул — а `admin_or_above?` саме через це переїхав у модель ([`04_03 §3`](04_03_REST_API_v1_Reference)).
>
> ⚖️ **Ховати, а не показувати-й-дизейблити — присуд founder'а 2026-07-31.** Другий варіант чесніший до оператора, який про фічу знає («пункт видно, потрібна роль X»), і саме тому його розглядали всерйоз. Переважили два аргументи: повне меню розкриває **мапу можливостей платформи** будь-якій ролі, а це multi-tenant NaaS, де сусідній тенант цілком може бути конкурентом; і ціна форми — дизейблений пункт коштує стану + підказки + `aria-disabled` + власних локаль-рядків проти одного предиката видимості. Ціна рішення названа чесно: прихований пункт не пояснює, ЧОМУ його нема, тож питання «а де фіча» переїжджає в онбординг, а не в UI. ⚠️ Тому не «полагоджуй» це назад на дизейбл без нового присуду — вибір зважений, а не стандартний.
>
> ⚠️ **Дефолт `current_user: nil` — fail-CLOSED, і з нього випливає несуча тестова стеля.** Забутий kwarg у шарі вище звужує меню, а не роздає гейтоване. Наслідок: **негативний** приклад («investor не бачить X») до забутої проводки СЛІПИЙ — без актора пункт схований в усіх, тож пін лишається зеленим. Проводку стереже лише **позитивне** твердження («admin бачить X»), і живе воно в request-спеці, бо компонентна конструює сайдбар повз `DashboardLayout`. Обидві половини mutation-verified: мутація фільтра червонить компонентні піни, мутація проводки — рівно один request-приклад.
>
> 🔒 **Той самий інваріант діє на ДІЇ всередині сторінки, не лише на меню [UI.6].** Фільтр сайдбара закрив вхід, але гарди з `only:` сидять ГЛИБШЕ за дію, якою пункт відкривається: сторінка видима легально, а кнопка на ній веде в 403. Свіп дав **клас із семи місць у чотирьох компонентах**, не три випадки. Закрито чотири роль-предикатні: `TreeFamilies::Index` ×2 (найгостріше — блобило **адміну**, бо мутації там super_admin-only), `Alerts::Row` (найбуденніше — бойову кнопку бачив кожен investor), `OracleVisions::Index` (цілий пульт симуляції показувався форестеру). ✅ **Запис-залежну половину закрито 2026-07-31 — і закриваючи, довелось виправити ОБИДВА твердження, якими її доти відкладали.** (1) Точок не три, а **чотири**: `verify` і `edit` рендеряться по два рази кожен, тож рахувалися ДІЇ, а проводити треба САЙТИ — та сама лічильна помилка, що й у `Alerts::Row` із його трьома місцями народження. (2) «Посадка мʼяка» була властивістю того конкретного гарда, а не класу: роль-предикатні місця блобили JSON, а `authorize_record_mutation!` — ні. ⚠️ **Уточнення 2026-08-01, бо цей рядок доти казав «`render_forbidden`/`render_forbidden_pundit` `respond_to` не мають узагалі»:** асиметрія була реальна, але однобока — pundit-гілка HTML дістала ще з SEC.25, а голий `render_forbidden` ні, і саме він лишався коренем для **12** контролерів із класовим гардом. ✅ Закрито [UI.9]: обидва тепер `respond_to` з dashboard-шаблоном, JSON-половина — один спільний `render_forbidden_json`. ⚠️ Локальні `respond_to` в `maintenance_records`/`maintenance_record_photos` при цьому НЕ зайві й знімати їх не можна: там посадка свідомо м'яка (назад на сусідню сторінку, де й живе кнопка), тобто інше **дієслово**, а не дубль. ⚠️ **Тут доти стояло, що підставу «інакше буде регрес UX» вживати НЕ можна, бо `DashboardLayout` `flash` не рендерить і мʼяка посадка фактично МОВЧАЗНА — знято 2026-08-01: поверхня зʼявилась (§8), тож `alert:` цих латок тепер видно, і заборона на цю підставу відпала разом із причиною.** Підстав тепер дві, і місце приземлення лишається сильнішою: воно тримається й для того, хто повідомлення не бачить. 🔴 **Але підстава «інакше вийшов би вкладений `respond_to`, і це зламалось би» — хибна, знята adversarial-проходом:** `RespondToMismatchError` кидається лише коли формат УЖЕ відрендерено в інший тип, тож json-у-json проходить — і доказ у цьому ж файлі, `render_validation_error` має власний `respond_to` при семи викликачах усередині `format.json`. Спільний `render_forbidden_json` виправданий як ОДИН дім JSON-половини, не як захист від неіснуючої поломки. ⚠️ Виміряний побічний факт: на екзотичному `Accept` (напр. `application/xml`) будь-який `respond_to`-екшен віддає **406**, і це не властивість error-рендерерів — успішний дашборд-шлях поводиться так само; `Accept: */*` (усі реальні клієнти) негоціює нормально.
>
> 🔴 **І під цією поверхнею лежав не UX-борг, а мутація без авторизації.** Вкладений `MaintenanceRecordPhotosController#destroy` мутує ТОЙ САМИЙ запис, а гарда автора не мав зовсім (коміт, що закрив «Forester #2 within the same org» на `edit`/`update`/`verify`, цього шляху не торкнувся) — тобто кнопку «×» бачив кожен форестер організації, і дія **проходила**: незворотно (`purge_later` → S3) і безслідно (`MaintenanceRecord` поза `Auditable`-периметром → [`SEC.28`](00_07_Action_Plan_Tracker)). Заразом виявилось, що сторінка запису **з будь-яким фото віддавала 500**: зайвий `as:` у вкладеному `resources` подвоював префікс, тож маршрут-хелпер кнопки не існував, а чотири компонентні спеки `prepend`-или модуль, який його ВИЗНАЧАВ — тобто пінили світ, у якому дефект неможливий.
>
> **Форма для запис-залежного гарда — предикат на МОДЕЛІ** (`MaintenanceRecord#mutable_by?`), а не `min_role:` і не політика: правило мусять читати троє — гард батька, гард вкладеного контролера і компонент. ⚠️ **Це свідомий відступ від канонічного поділу ідіомів, а не його застосування:** [`04_03 §3`](04_03_REST_API_v1_Reference) віддає «роль × авторство» саме **Pundit**, і читати цей абзац як дозвіл — помилка (вона вже була написана тут і знята adversarial-проходом). Підстава відступу одна й вузька: єдиний споживач, заради якого правило й переїжджало, — **Phlex-компонент, а він Pundit не торкається ніде в дереві**, тож політика як дім змусила б або інстансувати політику у в'юсі (нуль прецедентів), або пре-обчислювати булеан у контролері (розщеплення точки обчислення). Про організацію предикат свідомо мовчить — приналежність тримає асоціативний скоуп у викликача. ⚠️ Три шари пінів не заміняють одне одного: формулу пінить model-спека, послух компонента предикату — компонентна, а те, що актор реально доїжджає, — **request**-спека (при fail-closed дефолті негативний приклад сліпий до забутої проводки).
>
> ⚠️ **Спільного хелпера `visible_to?` на `ApplicationComponent` НЕ будуємо.** Він покрив би лише роль-предикатні місця, тоді як запис-залежним потрібні і актор, і сам запис; до того ж базовий клас навмисно не тримає користувача — компоненти отримують дані явно. Форма лишається та сама: явний kwarg + предикат `User`, той самий, що читає гард.
>
> 🔴 **Проводка дій дорожча за проводку меню, і побачити це можна лише свіпом:** `Alerts::Row` народжується у ТРЬОХ місцях (список · show-сторінка · Turbo-відповідь після `resolve`), тож забути можна кожне окремо. Третє найпідступніше: без актора рядок після УСПІШНОГО гасіння перерендерився б без кнопки навіть у форестера — тобто fail-closed дав би видимий регрес саме тому, хто має право.
>
> 🔒 **Дзеркальний інваріант: право без переходу — теж дефект, і шукається він ІНШИМ питанням [UI.6].** Роле-фільтр питає «чи має глядач право на цю кнопку». Цей клас питає протилежне: «чи має ця здатність бодай одні двері в UI». `organizations#switch` — уся Ф2 SEC.25 — був повністю реалізований на бекенді й **не мав жодної кнопки в `app/views`**, тобто перемикання контексту існувало лише для того, хто вміє слати POST руками. Три уроки цього закриття переносяться на будь-яку наступну «готову, але безкнопкову» здатність:
> - **Непінена гілка — не метрика, а адреса.** `switch` мав `format.html`, і рівно тому, що жоден приклад його не виконував, там роками жив `redirect_to root_path` при корені, оголошеному всередині `namespace :api → :v1`: хелпера не існує, `rescue_from StandardError` перетворював `NoMethodError` на 500. Дія проходила (аудит, сесія, сокети), користувач бачив помилку.
> - **Периметр шукається не там, де дію ХОЧУТЬ, а там, куди користувач ПОТРАПЛЯЄ.** Двох очевидних поверхонь (топ-бар · реєстр) було мало: на критичному шляху лежала третя — карантинна сторінка, куди org-less super_admin падає **першим екраном після логіну**, без жодного кліка.
> - **Індикатор і кнопка — одна зміна.** Кнопка без індикатора створює стан «дивлюсь чужі дані, і на екрані про це нічого». ⚠️ Тут доти стояло «а `DashboardLayout` `flash` не рендерить, тож іншого каналу підтвердження не існує» — знято 2026-08-01 разом із flash-поверхнею (§8). Індикатор лишається несучим із **іншої** причини: він показує стан **постійно**, тоді як flash живе один запит. ✅ Друга половина цього рядка («`switch` не ставить жодного повідомлення, тож для скрінрідера перемикання не оголошується взагалі») закрита 2026-08-01: перемикач ставить `flash.organizations.context_switched` категорії **`success`** — polite, а не `security`, бо перемикання контексту для super_admin'а рутинне, і assertive перебивав би мовлення на кожному кліку всупереч APG-правилу, записаному в §8 [SEC.25 Ф3].
>
> ⚠️ **Коли гард КЛАСОВИЙ (`before_action` без `only:`), роле-предикат у компоненті НЕ потрібен** — дія не глибша за сторінку, і додавати його означало б лікувати неіснуючу вісь. Саме тому `Organizations::Index` приймає `acting_organization:` (стан), але не актора (право).
>
> ⚙️ **Перемикання робочого контексту йде звичайним Turbo-візитом — `data: { turbo: "false" }` знято 2026-08-01 (UI.11 крок 2) РАЗОМ із причиною.** Тут доти стояло «повним перезавантаженням, і причина одна-єдина: десктопний сайдбар позначений `data-turbo-permanent`, тобто переживає візит разом зі своїм org-скоупленим лічильником тривог». Правда рівно доти, доки сайдбар був permanent; атрибут із нього знято тим самим кроком, тож Turbo віддає свіжу розмітку сам. ⚠️ Друга хибна підстава, яку тут теж писали: «інакше не оживуть вебсокети». Неправда й вона — `Subscriptions#add` кличе `ensureActiveConnection`, тож новий `<turbo-cable-stream-source>` у заміненому body піднімає сокет сам, попри `drop_open_sockets!` із `reconnect: false`. **Обидві опори цього рядка впали незалежно одна від одної — тримай це як зразок класу «вердикт вистояв, підстава ні»**, а не як історичну примітку.
>
> 🏷️ **«Яка організація» — ДВА різні питання, і мітки мусять їх розводити.** `reports/*` і `settings/show` показують **acting**-організацію (чиї це дані), `users/profile` — **домашню** (членство, зокрема й для чужого профілю: «в якій організації ця людина»), топ-бар — **контекст**. ⚠️ Зводити до однієї не можна: кожне значення правильне для свого питання, і зведення зробило б профіль брехливим. Лік — розводити СЛОВА, а не джерела (звідси «домашня організація» в профілі).

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
| `Trees::Show` | `trees/show.rb` | `tree:`, `latest_log:`, `recent_logs:`, `maintenance_history:` | Повна деталізація дерева: біометрична матриця (радіальний SVG), графік історії імпедансу, економічна панель, сховище безпеки обладнання, журнал технічного обслуговування. Містить lazy-loading Turbo Frame `tree_chronicle_{id}`, що підвантажує `Trees::Chronicle` з `/trees/:id/chronicle`. |
| `Trees::Chronicle` | `trees/chronicle.rb` | `tree:`, `entries:` (Array\<TreeChronicleService::Entry>), `pagy:` | Хронологічний список подій дерева. Рендериться у Turbo Frame (`tree_chronicle_{id}`). Підтримує пагінацію `Shared::UI::Pagination`, порожній стан `Shared::UI::EmptyState`. Стилізація severity через inline CSS-класи (`stable/info/warning/critical`). Skeleton-завантаження через `Shared::UI::Skeleton`. |

#### Гаманці

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Wallets::Index` | `wallets/index.rb` | `wallets:`, `pagy:` | Пагінований список гаманців |
| `Wallets::Show` | `wallets/show.rb` | `wallet:`, `transactions:`, `pagy: nil` | Деталізація гаманця з lazy-завантаженими фреймами балансу й blockchain-identity + журнал транзакцій. ⚠️ Панель «on-chain дії» знято [UI.7] 2026-08-06: обидві її кнопки були голими `<button>` без цілі (`Sync Polygon` — сервісу не існує; `Export CSV` — патерн `ReportsController` є, але не дротований). Тіло в git; повертається разом із дротуванням CSV |
| `Wallets::BalanceDisplay` | `wallets/balance_display.rb` | `wallet:` | Картка балансу SCC з розбивкою locked/available/ESG-retired; Turbo target `wallet_balance_{id}` |
| `Wallets::BalanceFrame` | `wallets/balance_frame.rb` | `wallet:` | Turbo Frame обгортка для lazy-завантаження балансу — тут фрейм СТОРІНКИ несе `src` (баланс дорогий), на відміну від `Actuators::CommandStatusFrame` (§6.4 «Інші»), де дані вже в контролері |
| `Wallets::BalanceFrameStub` | `wallets/balance_frame_stub.rb` | `wallet_id:`, `src:` | Locale-вільний payload броадкасту балансу: той самий id `wallet_balance_frame_{id}`, зі `src`, порожній. **Прецедент класу 2** — `BalanceDisplay` несе шість `t()`, тож надіслати його `html:` означало б розіслати всім підписникам локаль ТОГО, ХТО КЛАЦНУВ (рендер їде eagerly в процесі-продюсера, де `LocaleSettable` не відпрацював) |
| `Wallets::MetadataFrame` | `wallets/metadata_frame.rb` | `wallet:` | Turbo Frame обгортка для метаданих blockchain-ідентичності |
| `Wallets::TransactionRow` | `wallets/transaction_row.rb` | `tx:`, `status_src: nil` | Рядок on-chain транзакції. Чіп несе ТІКЕР (locale-інваріантний, дім — `ERC20(…, symbol)`), сума — голе число: деномінація стоїть один раз. `status_src` = контекст рендеру, не оздоблення: `nil` — сторінка (бейдж одразу), рядок — броадкаст (стаб зі `src`, §8.1а клас 2) |
| `Wallets::TransactionStatusFrame` | `wallets/transaction_status_frame.rb` | `tx:` | Комірка статусу: `<turbo-frame>` БЕЗ `src` зі `StatusBadge` усередині. Дім target-id — `.dom_id(tx_id)`, який кличуть обидва боки тракту |
| `Wallets::TransactionStatusFrameStub` | `wallets/transaction_status_frame_stub.rb` | `tx_id:`, `src:` | Locale-вільний payload тієї ж комірки для броадкасту: той самий id, зі `src`, пульс-плейсхолдер без жодного слова |

#### Телеметрія

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Telemetry::LiveStream` | `telemetry/live_stream.rb` | `organization:` | Live telemetry HUD: Matrix Rain canvas (Stimulus), sticky `<thead>`, `turbo_stream_from TurboStreams::Name.org(:telemetry, org)` (org — це скоуп стріму, не декорація; епоха в імені = відкликання, §8.1) |
| `Telemetry::LogEntry` | `telemetry/log_entry.rb` | `log:` | Один декодований рядок телеметрії, вставлений `UnpackTelemetryWorker` |

#### Oracle Visions

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `OracleVisions::Index` | `oracle_visions/index.rb` | `visions:`, `emission_forecast:`, `clusters:`, `current_user: nil` | Список AI-прогнозів + панель симуляції (остання — лише `admin_or_above?`, [UI.6] fail-closed) |
| `OracleVisions::ForecastCard` | `oracle_visions/forecast_card.rb` | `insight:` | Окрема картка прогнозу атрактора Лоренца. ⚠️ Футер із кнопками `Deploy Shield`/`Ignore` знято [UI.7] 2026-08-06 — бекенду під ними не існувало (слова «shield» немає в жодній моделі/сервісі; `AiInsight` не має ні `dismissed_at`, ні скоупа) |
| `OracleVisions::SimulationPanel` | `oracle_visions/simulation_panel.rb` | `clusters:` | What-If форма симуляції з повзунками діапазону; надсилає до `simulate_oracle_visions_path` у Turbo Frame |

#### Firmware OTA

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Firmwares::Index` | `firmwares/index.rb` | `firmwares:`, `inventory_stats:`, `pagy:`, `active_ota_gateways:` | Список прошивок + інвентар версій + секція живих OTA-кампаній [SEC.20] |
| `Firmwares::New` | `firmwares/new.rb` | — | Форма завантаження нової прошивки |
| `Firmwares::Form` | `firmwares/form.rb` | `firmware:` | Поля форми прошивки |
| `Firmwares::Row` | `firmwares/row.rb` | `firmware:` | Один рядок списку прошивок |
| `Firmwares::OtaProgressBar` | `firmwares/ota_progress_bar.rb` | `uid:`, `percent:`, `current:`, `total:`, `status:` | Анімований прогрес-бар OTA; Turbo target `ota_progress_{uid}` |

#### Codex (Lore Layer)

| Компонент | Файл | Props | Опис |
|---|---|---|---|
| `Codex::Index` | `codex/index.rb` | `nodes:`, `pagy:`, `realms:`, `active_realm_slug:` | Сторінка-каталог lore-вузлів (Atlas). Сітка карток (`NodeCard`), вкладки шарів (`RealmTabs`), пагінація `Shared::UI::Pagination`, порожній стан `Shared::UI::EmptyState` |
| `Codex::Show` | `codex/show.rb` | `node:`, `current_user:`, `comments:`, `current_user_attuned:` | Детальна сторінка lore-вузла. Bilingual title/subtitle, 3 markdown-блоки (`context_md` → `Codex::MarkdownRenderer`), `Shared::UI::StatusBadge` для `lifecycle_status`, зовнішні посилання, мета-рядки (Elo, view_count). Phase 2: рендерить `Codex::Attunements::Toggle` + `Codex::Comments::Thread`. |
| `Codex::RealmTabs` | `codex/realm_tabs.rb` | `realms:`, `active_slug:` | Горизонтальні вкладки шарів. Active token: `bg-gaia-primary text-gaia-primary-text` |
| `Codex::NodeCard` | `codex/node_card.rb` | `node:` | Картка одного lore-вузла. ActiveStorage `cover_image` з placeholder-гліфом per realm, lifecycle-бейдж, footer з Elo+geo_region. Linkable до `/codex/nodes/:slug`. |
| `Codex::Attunements::Toggle` | `codex/attunements/toggle.rb` | `node:`, `current_user_attuned:`, `count:` | **Phase 2.** Кнопка "Attune"/"Attuned" + лічильник. 🔴 **ДВІ дії — ДВА маршрути, і цей рядок доти стверджував протилежне** («POST/DELETE на nested-route»): колекційний шлях зареєстровано лише під `POST`, зняття живе окремим `attunements/me`, а компонент слав обидві гілки на перший — тобто «відвʼязатись» летіло в 404 назавжди, і канон-дім описував дефект як робочу поведінку ([UI.7], 2026-07-31). Форма — `button_to`, і це не стиль: він бере ціль із гілки, кладе `authenticity_token` (рукописна `<form>` його не мала → без JS гілка attune падала на CSRF; Turbo маскував це тим, що додає заголовок сам) і дає валідний `method="post"`+`_method` замість невалідного `method="delete"`. Успішний un-attune віддає **303**, не 302 — `fetch` конвертує 301/302 у GET лише для POST, тож на 302 браузер перевидав би DELETE на сторінку вузла. 🔴 **Лічильник НЕ живий** — приходить із рендером контролера й освіжається перезавантаженням. Обіцяний «Turbo Stream broadcast» ним ніколи не був (сирий ActionCable без підписника), а на силі тієї обіцянки видалили робочий Stimulus-фолбек `codex--attune`; воркер знято 2026-07-27 ([`UI.2`](00_07_Action_Plan_Tracker), присуд ADR-CDX-8 → [`04_05 §2`](04_05_Codex_Lore_Module)). |
| `Codex::Comments::Thread` | `codex/comments/thread.rb` | `node:`, `comments:`, `current_user:` | **Phase 2.** Список коментарів (хронологічно) + composer (тільки для авторизованих). DOM id `codex_node_<id>_comments` — стабільний **якір списку**, продюсера НЕМА (inline-броадкаст знято 2026-07-27, [`UI.2`](00_07_Action_Plan_Tracker)). Stimulus `codex--comment`. |
| `Codex::Comments::Item` | `codex/comments/item.rb` | `comment:` | **Phase 2.** Один рядок коментаря (sanitised markdown через `MarkdownRenderer`, ISO timestamp). Hidden-state — italic + opacity-50 + повідомлення модератора. DOM id `codex_comment_<id>`. |
| `Codex::Comments::Form` | `codex/comments/form.rb` | `node:` | **Phase 2.** Composer (textarea + Post). `maxlength: Codex::Comment::BODY_MAX`. Stimulus targets `codex--comment.body` / `.form`. |
| `Codex::Fractions::Card` | `codex/fractions/card.rb` | `fraction:`, `current_user:` | **Phase 3.** Read-only summary ідентичності caller'а. Empty-state CTA коли fraction nil; "Change →" + Cooldown pill коли set. DOM id `codex_fraction_card`. |
| `Codex::Fractions::Cooldown` | `codex/fractions/cooldown.rb` | `fraction:` | **Phase 3.** Status pill ("Open" / "Locked · Nd Mh"). Tokens: `status-success` / `status-warning`. |
| `Codex::Fractions::Picker` | `codex/fractions/picker.rb` | `realms:`, `active_realm:`, `nodes:`, `current_fraction:` | **Phase 3.** Turbo Frame grid pickable nodes для активного realm. Realm tabs (active = `bg-gaia-primary`), node cards з POST формою на `/codex/fractions`, disable button під час cooldown. DOM id `codex_fraction_picker`. |
| `Codex::Fractions::ProfileBadge` | `codex/fractions/profile_badge.rb` | `fraction:` | **Phase 3.** 1-row teaser для `Users::Profile`. Embed live в `render_codex_fraction` секцію. Стоїть на gaia-* tokens — не торкає legacy emerald palette профілю. |
| `Codex::Fractions::OnboardingWizard` | `codex/fractions/onboarding_wizard.rb` | `current_user:` | **Phase 8.** First-login банер у `DashboardLayout` — рендериться лише коли `current_user.codex_fraction.blank?`, з двома CTA: «Choose your Fraction →» (`/codex/fractions/picker`) та «Browse the Codex» (`/codex/realms`). Без Stimulus — нативна Turbo-Drive навігація (узгоджено з § 15 Native HTML over Stimulus). Layout-хук обгорнутий у `rescue StandardError` (ADR-CDX-7 fail-open). DOM id `codex_onboarding_wizard`. |
| `Codex::Battle::Arena` | `codex/battle/arena.rb` | `left:`, `right:`, `pair_seed:`, `realm:`, `error:` | **Phase 4.** Turbo Frame `id="codex_battle_arena"` з двома cards (Title + Archetype + `Elo: N · Mm`) + VS-divider + Skip. POST форми на `/codex/matches` (`MatchesController#create`; один winner_slug per форма + окрема skip-форма). UI-назва "Battle Arena" — UX label, REST-ресурс — `Codex::Match`. Error-state pill при `not enough nodes`. |
| `Codex::Leaderboard::Table` | `codex/leaderboard/table.rb` | `realm:`, `nodes:`, `limit:` | **Phase 4.** Read-only top-N Elo board. HTML `<table>` з колонками rank / Title / Elo / Matches / Lifecycle. Рендериться публічно (`/codex/leaderboard` без auth). Empty-state copy коли `nodes.empty?`. |
| `Codex::Discoveries::List` | `codex/discoveries/list.rb` | `discoveries:`, `pagy:` | **Phase 5.** Paginated 3-col grid of own unlocked nodes (rendered by `GET /codex/discoveries/me` HTML format). Empty-state copy "Nothing unlocked yet — observe a tree, vote in the Arena, choose a fraction." Кожна card показує title / archetype_key / `trigger_type · unlocked_at`. gaia-* tokens only. |
| `Codex::Citations::Pill` | `codex/citations/pill.rb` | `citation:` | **Phase 6.** Single inline citation chip — `« Title · archetype_key »`. Slug-href anchor до `/codex/nodes/:slug`, hover-title зі 140-char note, `aria-label` для screen readers, `focus-visible:ring-2`. gaia-* tokens (`bg-gaia-surface-sunken`, `border-gaia-border`, `hover:border-gaia-primary`). Defensive nil-safe — рендерить порожньо якщо `citation.node` зник. |
| `Codex::Citations::Strip` | `codex/citations/strip.rb` | `target:`, `citations:`, `current_user:` | **Phase 6.** Wrap-flex container з усіма pills прив'язаними до операційної цілі (`Tree`/`Cluster`/`AiInsight`/`EwsAlert`/`OracleVision`/`NaasContract`). DOM id `codex_citations_<type_underscore>_<id>` (продюсера НЕМА — сирий ActionCable знято 2026-07-27; живим тракт стане лише через підписаний Turbo-стрім). Empty-state copy "No lore citations yet." щоб freshly-cited entity мав стабільний DOM target. Інтегровано в `Trees::Show`, `Clusters::Show`, `Alerts::Row`, `OracleVisions::ForecastCard` через приватний `render_codex_citations` що early-return'ить на `defined?(Codex::Citation)` гарду + `for_target(target).includes(:node)`. |

> ⚠️ **Сирий ActionCable знято 2026-07-27** (UI.2 descope + SEC). Підписника не існувало ніколи, а `/cable` монтується движком САМ (`after_initialize`, `internal: true` — його не видно в `bin/rails routes`), тож канал без авторизації підписки був латентним крос-тенантним IDOR при послідовних ID. Realtime — лише через ПІДПИСАНІ Turbo-стріми, бо їх ім'я дістається тільки тому, кому сторінка вже відрендерилась. Заборону тримає `spec/security/no_raw_action_cable_spec.rb`.

#### Інші Доменні Компоненти

| Простір імен | Компоненти | Ключові Props |
|---|---|---|
| `Alerts` | `Index`, `Row` | `alert:` (`Badge` знято 2026-07-27 — UI без жодного рендерера) |
| `Clusters` | `Grid`, `Item`, `Show` | `cluster:`, `trees:` |
| `Gateways` | `Index`, `Item`, `Show` | `gateway:` |
| `Actuators` | `Index`, `Show`, `Card`, `CommandRow`, `CommandStatusBadge`, `CommandStatusFrame`, `CommandStatusFrameStub` | `actuator:`, `command:` · **`CommandStatusFrame`/`CommandStatusFrameStub` = пара класу 2 «viewer-driven pull» [I18N.2]** (`command_id:`+`src:` у стаба): id фрейма НАВМИСНО ≠ id бейджа всередині (`command_status_frame_{id}` обгортає `command_status_{id}`) — збіг дав би дубль id у DOM, а ціллю броадкасту мусить бути саме ФРЕЙМ, бо `src` несе він. ⚠️ Відхилення від прецеденту гаманця свідоме: там сторінка теж ставить `src` (lazy-load дорогого балансу), тут — НІ, бо дані вже в `@commands`, а рядків до 20, тобто двадцять GET на перше відкриття заради того, що вже в пам'яті. Стаб рендерить пульс-плейсхолдер, а не `Views::Shared::UI::Skeleton` — той локалізований (`t(".loading")`), тобто зламав би саме ту інваріантність, заради якої існує · `Card` і `Index` беруть останню команду ПАРАМЕТРОМ (`last_command:` / `last_commands:` = мапа `actuator_id ⇒ команда`, яку збирає контролер із преloaded асоціації). Доти `Card` мала фолбек `@actuator.commands.last` у конструкторі — порушення §6.4, що ще й віддавало РІЗНУ «останню команду» на двох сторінках: на `index` асоціація преloaded, тож `.last` брав останній у порядку БД, а на `show` летів окремий `ORDER BY id DESC`. Фікстура спеки навмисно вибухає на `commands` — повернення фолбека червонить кожен приклад |
| `Maintenance` | `Index`, `Show`, `Form`, `PhotoGallery`, `PhotosPage` | `record:`, `photos:` |
| `Contracts` | `Index`, `Show` | `contract:` |
| `BlockchainTransactions` | `Index`, `Show`, `OnChainFrame` | `tx:` |
| `Reports` | `Index`, `CarbonAbsorption`, `FinancialSummary` | `data:` |
| `TreeFamilies` | `Index`, `Show`, `Form` | `family:` |
| `Organizations` | `Index`, `Show` | `organization:` · `Index` додатково `acting_organization:` — перемикач контексту [UI.6]: окрема колонка дії (мутуючий POST під заголовком «Audit» брехав би скрін-рідеру), `aria-current`-маркер замість кнопки на поточному рядку, `data: { turbo: "false" }` на `button_to`. Роле-предиката тут НЕМА свідомо: гард контролера класовий, тож дія не глибша за сторінку |
| `Users` | `Index`, `Profile` | `user:` |
| `AuditLogs` | `Index`, `Show` | `log:` |
| `SystemAudits` | `Index` | `audits:` |
| `SystemHealth` | `Show` | `health:` |
| `Provisioning` | `New` | `hardware_key:` (`Success` знято 2026-08-03 — мертвий компонент, нуль рендерерів; історія його `@device.did`-бага лишається в §11) |
| `AccountSecurity` | `Show` | `user:` |
| `Notifications` | `Settings` | `settings:` |
| `Settings` | `Show` | `organization:` — налаштування тенанта. 🔴 **Рукописна `form(action: settings_path, method: "post")` з hidden `_method=patch` і РУКОПИСНИМ `authenticity_token`** — тобто рівно той тракт, де клас UI.7 уже стріляв, коли токен забули зовсім; тут він явний, і саме тому цю форму пінить браузерний приклад окремо від `form_with`-механізму ([`04_06 §B.1.4`](04_06_Testing_Guide_and_Coverage)). Причини відмови їдуть через `Views::Shared::UI::ErrorSummary` з `@organization.errors` — окремого kwarg'а немає, помилки приїжджають на самому записі |
| `Sessions` | `New` | `flash_alert:` — рендериться через `AuthLayout`. 🔴 **Це ІНШЕ дієслово, ніж `FlashMessages` (§1), і паралельність тут свідома:** kwarg несе помилку **поточного сабміту** (401/429), яку сторінка показує НА МІСЦІ зі збереженим статусом і біля поля, що його треба перевводити; `FlashMessages` натомість несе повідомлення, яке **пережило редирект**. Плутати їх не можна в жоден бік: flash на 401 вимагав би редиректу (відкинуто — [`00_07`](00_07_Action_Plan_Tracker) SEC.25), а kwarg після редиректу не заповнює ніхто. ⚠️ `flash_notice:` знято 2026-08-03 — нуль викликачів у дереві, гілку тримала лише власна спека [SEC.25] |
| `Passwords` | `Forgot`, `Reset` | `Reset` — `token:` + `flash_alert:` (валідація нового пароля: `too_short`/`mismatch`, 422 на місці; та сама inline-форма, що в `Sessions::New`). ⚠️ `Forgot` kwarg'ів **не має взагалі** — обидва його шляхи (rate-limit, протермінований токен) приходять **редиректом**, тож повідомлення несе `FlashMessages`; доти компонент мав обидва kwarg'и й чесно їх рендерив при нулі викликачів [SEC.25] |
| `Errors` | `NoOrganization` | `current_user:` (fail-closed `nil`) — Quarantine-сторінка для користувачів без організації, рендериться через `AuthLayout`. ⚠️ Це не рідкісний кут, а **перший екран платформеного адміністратора**: за seeds обидва super_admin без організації, логін веде на `dashboard#index`, той кличе `acting_organization!`. Тому другий абзац і вихід роле-залежні [UI.6]: «зверніться до адміністратора» адресовано тому, кого забули додати, а super_admin і є той адміністратор — йому потрібен реєстр кланів, а не порада. Для решти ролей лінка немає й по суті: реєстр за `authorize_super_admin!` |
| `Errors` | `Page` | `heading:`, `message:`, `tone:` — спільна сторінка для error-рендерерів `BaseController` (404 · Pundit-403 · 500). 🔴 **Свідомо БЕЗ власних `t()`:** працює зсередини `rescue_from`, а `raise_on_missing_translations` перетворив би забутий ключ на виняток, якого Rails там уже не переловить — тобто сторінка помилки впала б від власної. Лягає в ОБИДВА layout'и: 404/403 → `DashboardLayout` (глядач автентифікований, навігація чесна), 500 → `AuthLayout` (єдиний шлях із `current_user = nil`) |

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
| **clipboard** | `clipboard_controller.js` | `clipboard` | Копіювання в буфер обміну для Web3-адрес |
| **map** | `map_controller.js` | `map` | Геопросторова карта дерев Leaflet.js |
| **matrix-rain** | `matrix_rain_controller.js` | `matrix-rain` | Canvas-ефект Matrix digital rain |
| **mobile-nav** | `mobile_nav_controller.js` | `mobile-nav` | Шим `<dialog>` мобільної навігації (backdrop-click + scroll-lock Safari) — § 15.2 |
| **codex--comment** | `codex/comment_controller.js` | `codex--comment` | Codex thread — inline reply / broadcast (`Codex::Comments::Thread`) |
| **reveal** ⚠️ | `reveal_controller.js` | `reveal` | Appear-on-scroll (IntersectionObserver) — § 14.3. **Наразі 0 консюмерів** (`data-controller="reveal"` ніде): scaffold, який авто-реєструється |

> **⚠️ Важливо:** Будь-який `*_controller.js` у директорії автоматично реєструється через `eagerLoadControllersFrom` — **не залишайте scaffold-файли в production** (пор. `reveal` вище: авто-зареєстрований, але без жодного консюмера).

### 7.1 Контролер `clipboard`

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

### 7.2 Контролер `map`

**Targets:** `node`

Ініціалізує Leaflet.js карту з тайлами CartoDB Dark Matter (кіберпанк-естетика). Підтримує хеш `markers` (`DID → L.Marker`) для інкрементальних оновлень.

**Ключовий lifecycle:**

- `connect()` — делегує в `ensureMap()`; сама ініціалізація (центр за замовчуванням — Черкаси: 49.4444, 32.0598; `this.markers = {}` — DID рядок → `L.Marker` instance; `this.markerLayer = L.layerGroup()`) живе в `ensureMap()` і **ідемпотентна**
- 🔴 `ensureMap()` — **не «зайва» обгортка, а лік реального дефекту** ([`TEST.7`](00_07_Action_Plan_Tracker), 2026-08-03). Stimulus піднімає `targetObserver` **ДО** виклику `controller.connect()`, тож для вузлів, уже присутніх у серверній розмітці, `nodeTargetConnected` приходить **першим**. Доки ініціалізація стояла просто в `connect()`, перше ж геолоковане дерево ловило `this.markers` як `undefined`, а виняток валив **реєстрацію всього контролера** — тобто мапа не будувалась саме тоді, коли їй було що показати, і в проді була зламана постійно. Тому ініціалізація кличеться з ОБОХ входів. **Клас ширший за Leaflet:** будь-який контролер, що тримає стан у `connect()` і має `*TargetConnected`, мусить бути стійким до зворотного порядку — інакше він працює лише на порожній сторінці
- `disconnect()` — викликає `this.map.off()`, `this.map.remove()`, встановлює `this.map = null`, `this.markerLayer = null`, скидає `this.markers = {}`, очищає `this.resizeTimeout`. **Turbo Drive Cache fix:** видаляє всі дочірні вузли (`replaceChildren()`) та Leaflet CSS-класи (`leaflet-*`) зі свого DOM-елемента — гарантує, що `connect()` ініціалізує карту з повністю чистого стану після відновлення зі snapshot-кешу Turbo.
- `nodeTargetConnected(element)` — викликається автоматично Turbo/Stimulus коли `<div data-map-target="node">` додається до DOM через Turbo Stream; витягує `data-lat/lng/did/stress/charge` та викликає `updateMarker()`

**Логіка кольору маркера:**

| Умова | Колір | Свічення |
|---|---|---|
| `stress > 0.8` або `status === "removed"` | `#ef4444` (червоний) | `rgba(239,68,68,0.8)` |
| `stress > 0.4` або `charge < 30` | `#eab308` (жовтий) | `rgba(234,179,8,0.6)` |
| За замовчуванням (здорове) | `#10b981` (emerald) | `rgba(16,185,129,0.5)` |

**Phlex-використання:** `data: { controller: "map" }` на map `<div>` у `Dashboard::Map`. Приховані `<div data-map-target="node">` елементи стрімляться через Turbo з `Dashboard::MapNode`.

### 7.3 Контролер `matrix-rain`

Canvas-ефект Matrix digital rain з hex-символами (`0-9A-F`). Canvas-елемент отримує `transform-gpu will-change-transform` для GPU-compositing (апаратне прискорення).

- `connect()` — отримує canvas 2D контекст, запускає rAF-цикл (`requestAnimationFrame`) з throttle до ~16 fps (`FRAME_INTERVAL = 60ms`); цикл автоматично призупиняється при неактивній вкладці
- `disconnect()` — скасовує rAF через `cancelAnimationFrame(this.rafId)`, видаляє resize-слухач
- `resize()` — підганяє canvas під батьківський елемент, переініціалізує масив `drops[]`

**Phlex-використання:** `canvas(data: { controller: "matrix-rain" }, class: "absolute inset-0 z-0 opacity-20 pointer-events-none w-full h-full transform-gpu will-change-transform")` всередині `Telemetry::LiveStream`.

---

## 8. Інтеграція Turbo (Streams & Frames)

### 8.1 Turbo Streams

Оновлення DOM в реальному часі через `ActionCable` (Solid Cable).

Реєстр звірено з кодом по ОБИДВА боки — і продюсери, і підписники (UI.4, 2026-07-27).

> 🔴 **Двох боків НЕ досить — є третя вісь, і саме вона пропустила дефект.** «Продюсер існує» ⊕ «підписник існує» обидва резолвляться чисто для тракту, чия сторінка **недосяжна жодним маршрутом**: компонент-підписник просто ніхто не рендерить. Так прожив `"geospatial_matrix"` — `Dashboard::Map` не рендерився ЖОДНОГО разу за всю історію репо, а `Dashboard::Home` малював на його місці вічний спінер. Тобто повний контракт живого тракту — **продюсер ⟷ підписник ⟷ маршрут**, і третю ланку не бачить ані звірка реєстру, ані планований гейт пари.
>
> ✅ **Тракт дотягнуто (2026-07-27, ⚖️ власника).** `Dashboard::Home` рендерить `Dashboard::Map` замість спінера; дані — `org.trees.geolocated` з контролера, лише для html-гілки (JSON-споживач мапи не рендерить і за цей SELECT не платить). 🔴 **Дротування без скоупу було б НЕ фіксом, а вмиканням витоку:** ім'я стріму детерміноване, тож голий `"geospatial_matrix"` посадив би всіх глядачів застосунку в один канал і роздав координати й DID чужого флоту — рівно клас SEC.25. Тому продюсер і підписник пішли на `geospatial_matrix_org_{id}` одночасно з рендером, не після нього. Скоуп деривується `cluster&.organization_id`, і `return unless org_id` тут не перестраховка: `Cluster has_many :trees, dependent: :restrict_with_error` (⚖️ 2026-07-30 — доти `:nullify`), тож дерева без кластера як штатного стану більше немає, і адреси стріму в нього немає. Ліміт першого рендеру (`MAP_NODE_LIMIT`) — свідома стеля: понад неї сторінка показує підмножину флоту, бо кластеризація маркерів = нова JS-залежність (→ [`00_07`](00_07_Action_Plan_Tracker) UI.4). Живі оновлення ліміту не знають — `broadcast_replace` у ціль, якої нема в DOM, Turbo тихо ігнорує.
>
> 🔴 **І вісь СКОУПУ ортогональна всім трьом.** `"telemetry_stream"` був голим глобальним рядком: продюсер є, підписник є, маршрут є — тракт «здоровий» за будь-якою з осей вище, і при цьому віддавав кожному автентифікованому глядачу `uid`, IP та сирий payload шлюзів УСІХ організацій. Полагоджено org-скоупом (2026-07-27, [`00_07`](00_07_Action_Plan_Tracker) SEC.25). Чому цього не бачить REST/Pundit-аудит: HTTP-відповідь `/telemetry/live` тенант-даних не несе взагалі — це хром сторінки й порожній плейсхолдер, а витік приїжджає вебсокетом **після** підписки. Тож перевіряти скоуп стріму мусить окремий гейт, і `SEC.16` тут не сусід, а інша вісь.
>
> ✅ **Гейт осі скоупу шипнуто (2026-07-28): `spec/security/turbo_stream_scope_spec.rb` + AST-екстрактор `lib/turbo_stream_inventory.rb`.** Форма — **диспетчер обовʼязку доказу**, а не перевірка сама: клас першого аргументу підписки каже, ЯКИЙ доказ мусить існувати (AR-запис → спека крос-фетч-відмови · `TurboStreams::Name.org(...)` → two-subject пін імені · `TurboStreams::Name.gateway_ota(...)`, тобто імʼя без org-токена → пін РІВНОСТІ МНОЖИНИ · голе глобальне імʼя → червоне), і реєстр обовʼязків живий у два боки: новий стрім без запису червоніє, мертвий запис червоніє, а **зміна класу імені** (напр. `derived_org` → `bare_string` = повернення витоку) червоніє окремим прикладом. Заразом гейт закрив інваріант, який доти жив лише прозою: успадкований `broadcast_*` моделі (без `_to`) адресує стрім самим записом і в цьому репо кидає `MissingTemplate` — тепер це не рекомендація, а червоне.
>
> 🔒 **Чому екстрактор на AST, і чому набір методів дериваний із ГЕМА** — обидва рішення куплені виміряними помилками, не стилем. Регекс сусіднього гейта (§8.1а) вимагає багаторядкового виклику, тож однорядковий `broadcast_*_to(...)` для нього не існує. А будь-який патерн на іменах хибний в ОБИДВА боки: `broadcast_\w*_to` пропускає не-`_to` форми, а `broadcast_\w+` загрібає власні приватні хелпери застосунку, яких у дереві вдвічі більше за самі гем-виклики. Тому набір беруть із `Turbo::Streams::Broadcasts` ∪ `Turbo::Broadcastable` у рантаймі — апгрейд turbo-rails покривається без правки гейта. І окрема пастка, знайдена мутацією вже після «зеленого»: **безаргументний** виклик (`broadcast_refresh`) дає Ripper-форму `:vcall`, яку перший walker не обробляв — тобто гейт був сліпий рівно до найідіоматичнішої форми того, що забороняє. Стелі гейта названі в шапці спеки (пінить ІМʼЯ приклада-доказу, не його доказовість · походження org-токена статично невидиме · підписка в обхід хелпера невидима · **клас із форми ІМЕНІ, а форма доказу — з КАРДИНАЛЬНОСТІ сторінки**, чого екстрактор не бачить у принципі). Останню стелю купив реальний промах: `Gateways::Show` був зареєстрований на приклад крос-org-404, який іде `as: :json` — тобто HTML-гілки зі стрімом не рендерить, і сторінка спокійно віддавала б чуже імʼя каналу (доведено мутацією: підміна на `Gateway.last.uid` лишалась зеленою). Скоуп там доведений транзитивно — org-скоуплений `find` стоїть ПЕРЕД `respond_to`, — а недоведеним лишалось саме імʼя; тепер обидва сайти цього класу пінені рівністю множини на HTML-гілці.

> 🧱 **Імена стрімів виводить ОДИН дім — `lib/turbo_streams/name.rb`, і кличуть його обидві сторони тракту** (2026-07-28). Таблиця нижче — читабельне дзеркало, а не джерело: правити імена там. 🔴 Чому це несуче, а не косметика: до цього кожне з чотирьох рядкових імен було написане руками **одинадцять разів** через два шари (5 підписок + 6 броадкастів), і сторони не звіряло ніщо. Один символ різниці дає або тихо мертвий тракт, або — якщо втрачено саме токен `_org_` — живий крос-тенант витік. ⚠️ **Чесно про доказову базу:** розходжень самого ІМЕНІ СТРІМУ репо ще не відвантажувало (прецедентів нуль), а три відомі катастрофи цього роду (`wallet` проти `[wallet, :transactions]` · `transaction_{id}` проти `blockchain_transaction_{id}` · `actuator_card_{id}` проти `actuator_{id}`) сиділи на **сусідній осі — target-id і record-форма**, якої дім імен не накриває. Виправдання дому інше й вужче: найбільший радіус ураження (втрата `_org_` = витік, чого жодна з тих трьох дати не могла) плюс здешевлення гейт-пари ↓. **Сусідня поверхня — target-id — досі рукописна по обидва боки, і дому в неї немає** (інвентар, межа класу й чому `dom_id` тут НЕ безкоштовний → [`00_07`](00_07_Action_Plan_Tracker) UI.4; механіка — §8.3). ⚠️ Числа сайтів тут свідомо НЕ стоїть: воно вже двічі розійшлося між домами, а відтворюється лише під визначенням скоупу, якого жоден із них не проговорював — за ширшим читанням («рукописний id, що мусить збігтися у двох незалежних місцях») клас удвічі більший. Лічильник тут карав би за кожен майбутній дедуп; інвентар живе в трекері, правило — тут. Тобто дім прибирає клас **конструктивно**, замість ловити його постфактум, і заразом здешевлює планований гейт-пару з [`UI.4`](00_07_Action_Plan_Tracker): обидві сторони тепер буквально кличуть ту саму функцію. ⚠️ Що дім НЕ робить: він не доводить, що передана організація — глядачева. Це питання «чи МОЖЕ це зʼєднання слухати цей стрім», і обидва факти разом існують лише в `subscribed` власного каналу (→ [`00_07`](00_07_Action_Plan_Tracker) SEC.25 Ф1). Render-time assert свідомо відкинуто: він тавтологічний (усі три контролери виводять org тим самим виразом, з яким його б і порівнювали) і недосяжний для компонент-спек-харнеса, що рендерить через `ApplicationController.renderer`, де `current_user` хелпером не оголошений.
>
> Гейт тримає це трьома окремими інваріантами понад скоуп: **рядкове імʼя, зібране руками, — червоне як ФОРМА** (навіть з правильним скоупом: воно виведене окремою копією); **на боці ПІДПИСКИ легальні лише два джерела** — дім або сам AR-запис; і **на боці ПРОДЮСЕРА непрозора адреса легальна лише за походженням**. Усі три mutation-verified.
>
> 🔴 **Третій інваріант (2026-07-30) закрив найдорожчу поблажку гейта, і тут доти стояло протилежне — «на боці продюсера локал лишається нормою».** Вимір проти історичного коду показав, що саме ця норма і є фактичною популяцією дефектів поверхні: **сім** сайтів, знятих як «продюсер у порожнечу», адресували стрім непрозоро — параметром методу (`broadcast_final_state(command, organization)` ×2 · `broadcast_slashing_event(contract, …)`), локалом з `||`-ланцюга (×2), ланцюгом викликів (`insurance.cluster.organization`) і голим `self` (`Wallet` слав у ВЛАСНИЙ стрім, тоді як підписник слухав `[wallet, :transactions]`). Правило тепер: локал легальний лише тоді, коли **присвоєний із дому імен** — тобто гейт розрізняє ПОХОДЖЕННЯ адреси й ніколи не резолвить її значення (одна передача по AST, не інтерпретатор). Живий легітимний випадок рівно один: `UnpackTelemetryWorker` вживає імʼя двічі, тож тримає його в змінній. ⚠️ Стеля названа: скоуп **файловий**, не методний — однойменний локал в іншому методі того ж файлу пройде.
>
> 🚫 **А ось «гейт-пара продюсер ⟷ підписник» ВІДКИНУТА виміром, і це важливо знати перед тим, як її запропонувати знову** (детальний присуд → [`00_07`](00_07_Action_Plan_Tracker) UI.4). Дім імен, прибравши рукописні літерали, заразом **осліпив** би її: екстрактор віддає лише клас аргументу, тож пара порівнювала б класи, а не адреси. Плюс вона приїхала б із вбудованим винятком у день ноль — tombstone ротації адресує ПОКИНУТУ епоху за призначенням, тобто підписника не має й не повинен мати. Улов пари — 1 із 12 історичних дефектів чистого приросту проти семи в інваріанта вище.

> 🔒 **Скоуп імені відповідає «хто МОЖЕ підписатись зараз», але не «назавжди» — і три дешевих на вигляд важелі відкликання тут не працюють.** Підписане імʼя = `Base64(JSON)--HMAC` на **`Turbo.signed_stream_verifier_key`**: **непідробне, але прозоре** (org-id читається відкритим текстом) і **детерміноване** — чистий `MessageVerifier`, без TTL і без `purpose`. ⚠️ Ключ тут **власний ключ гема, а не `secret_key_base`** — і різниця несуча, бо саме вона дає окремий важіль (стеля (3) ↓). `turbo.rb` бере `config.turbo.signed_stream_verifier_key`, а якщо його не задано — деривує `key_generator.generate_key("turbo/signed_stream_verifier_key")` (`turbo-rails/lib/turbo/engine.rb`). Ми його **не задаємо**, тож сьогодні він деривований, і ротація `secret_key_base` тягне його за собою; від'єднання робить його ротовним окремо. ActionCable підписку **не ре-авторизує**: верифікатор читають один раз у `subscribed`, далі `stream_from` тримає її за вже відкритим імʼям. Наслідки, кожен виміряний:
> - **(а) Ротація ключа не рве відкритий сокет.** Вона блокує лише НОВІ підписки — і водночас глобальна (вилогінює всіх + ламає CSRF), тобто дорога рівно там, де не допомагає.
> - **(б) `remote_connections…disconnect` був не «невживаний», а НЕРОБОЧИЙ — ✅ полагоджено 2026-07-28.** Штатний Rails-примітив відкликання спирається на `identified_by`; поки власного `ApplicationCable::Connection` не існувало, набір `identifiers` був порожній → `connection_identifier` = `""` → `subscribe_to_internal_channel` за порожнього не підписується взагалі, тож broadcast відкликання летів у канал, якого ніхто не слухає. Це було не «ми його не викликаємо» — його виклик нічого б не досяг. Тепер зʼєднання ідентифіковане (`app/channels/application_cable/connection.rb`), і примітив живий. ⚠️ Гранулярність — **per-device, не per-user**, і це навмисне: cookie-сесія несе стабільний `session_id` (`CookieStore#write_session` кладе його в самі дані сесії), тож `identified_by :current_user, :session_id` рве саме той пристрій, що перемкнув контекст, а не всі сесії акаунта. Тут доти стояло, що per-device «неможливий у принципі» — хибно, спростовано джерелом.
> - **(в) TTL доступний, але відкинутий — і не за ціною, а за режимом власної відмови.** `expires_in:` стоковий верифікатор шанує навіть без `purpose`; проблема на клієнті: конструктор `Subscription` **заморожує** ідентифікатор, `Subscriptions#reload()` на `welcome` шле СТАРИЙ токен не перечитуючи DOM, а `<turbo-cable-stream-source>` не визначає колбека `rejected` взагалі. Тобто прострочений токен після сну ноутбука вбиває живі оновлення **назавжди й безшумно** — ні ретраю, ні помилки в консолі. Morph-рефреш годинник скидає, тож жертва — саме ІДЛЬНА сторінка. Стопгеп, що коштує дорожче за діру, яку обмежує.
>
> 🔴 **І четверте обмеження, яке скасовує присуд трьох попередніх: авторизація на `subscribe` у ВЛАСНОМУ каналі теж не закриває клас** (виміряно 2026-07-28, джерелом обох гемів). Тут довго стояло «клас закриває лише авторизація на subscribe у власному каналі — те, що гем документує сам»; обидві половини цього речення хибні.
> - **Клас каналу вибирає КЛІЄНТ, і підпис його не накриває.** `ActionCable::Connection::Subscriptions#add` бере `id_options[:channel].safe_constantize` з клієнтського JSON-ідентифікатора, а єдина перевірка — `ActionCable::Channel::Base > subscription_klass`, тобто «будь-який нащадок». Turbo ж підписує САМЕ ІМʼЯ: у `turbo_stream_from` `channel` лишається звичайним атрибутом, а HMAC накриває `signed-stream-name`. І `<turbo-cable-stream-source>` тримає `channel` в `observedAttributes` з `attributeChangedCallback` → `disconnectedCallback(); connectedCallback()`, тож зміна атрибута перепідписує елемент САМА. Наслідок: власний авторизований канал обходиться одним рядком у devtools із тим самим валідним токеном — і слухають його лише ті, хто й так грав чесно. Проти навмисного актора (а residual описує саме його) ця форма дає нуль.
> - **`subscription_allowed?` — не хук гема, а приклад у докблоці** (два входження на весь turbo-rails 2.0.23, обидва в коментарі `streams_channel.rb`). Гем його ніде не викликає.
> - **А `reject` як fail-closed має ВІД'ЄМНУ цінність.** Клієнтський `reject()` кличе `forget(subscription)` — підписка зникає зі списку, тож `reload()` на реконекті її вже не перевідправить, — а колбека `rejected` елемент не визначає взагалі. Тобто відмова тиха й незворотна до повного ре-рендеру: **той самий режим, за який відкинуто TTL у (в)**, тільки детермінований і на першому ж рендері. Спрацьовує вона недосяжно для зловмисника (він на іншому каналі) і калічить рівно легітимного глядача, чиє імʼя резолвер не впізнав — а це не крайній випадок: `clusters.organization_id`, `wallets.organization_id`, `trees.cluster_id`, `ews_alerts.cluster_id`, `gateways.uid` усі NULLABLE, тож «нема шляху до організації» — звичайний стан даних.
>
> Тож субскрайб-авторизація можлива лише як переозброєння **самого** `Turbo::StreamsChannel` (він єдиний константизовний стрім-канал у дереві) — ціною мавпячої латки, що тихо злітає на апгрейді гема. Форма, імунна до обох класів відмови за побудовою, інша: **org-epoch у самому імені стріму** — вона переносить enforcement із «гейтити підписника» на **покинути адресу**, а нове імʼя атакеру недоступне, бо теж підписане. Стан і фазування → [`00_07`](00_07_Action_Plan_Tracker) SEC.25.

> ✅ **Епоха шипнута (2026-07-29, SEC.25 Ф3) — відкликання існує.** `organizations.stream_epoch` (integer, default 1, NOT NULL) входить в імʼя: `telemetry_stream_org_7_e1`. Важіль — `Organization#rotate_stream_epoch!`: запамʼятати попередню епоху → `increment!` → штовхнути **tombstone** (`broadcast_refresh_to`) у ПОКИНУТУ адресу → лишити слід ARCH.57 (`stream_epoch_rotated`). Порядок несучий: постав tombstone першим — і релоуд відрендерить ще стару епоху, тобто глядач осяде рівно на тій адресі, яку ми кидаємо. Tombstone теж несучий: без нього bump = тиха втрата живості для чесних, тобто той самий режим відмови, за який відкинуто TTL у (в).
>
> 🔒 **Чотири стелі, названі чесно — інакше «відкликання є» прочитається ширше, ніж воно є.**
> - **(1) Tombstone доїжджає лише до ПІДКЛЮЧЕНИХ.** Solid Cable ставить точку приєднання нової підписки на поточний максимум (`add_channel`), тож backlog не реплеїться: вкладка, що спала під час bump'а, після реконекту ре-підпишеться на мертве імʼя з ще не перезавантаженого DOM — і виглядатиме `connected`, будучи глухою. Тому повторний поштовх — **штатна дія оператора**, а не crash-recovery, і в неї є власне імʼя (`broadcast_stream_tombstone!(epoch)`), а не інструкція в коментарі. Відкликання це не послаблює — платить лише живість. ⚠️ Точне формулювання, бо тут спокусливо написати «стара адреса мертва для продюсерів»: `broadcast_refresh_later_to` обчислює імʼя на **ENQUEUE**, до дебаунсу, тож джоби, поставлені в чергу до bump'а, ще адресують стару епоху. Витоку це не дає — вони несуть лише сигнал, не payload, — і фактично працюють як додатковий tombstone. Отже правильно: стара адреса мертва для **НОВИХ** броадкастів.
> - **(2) `:map` із tombstone'а ВИКЛЮЧЕНО, і це не пропуск.** `DashboardLayout` вмикає morph глобально, а `#geospatial_map_canvas` навмисно без `data-turbo-permanent` (той експеримент уже виміряний і знятий — §8.1б). Морф лишає сам вузол, але зносить його дітей, яких немає в серверному HTML, — тобто панелі Leaflet; `disconnect()` при цьому НЕ спрацьовує, бо вузол не видалявся, отже `map_controller` не переініціалізується ніколи. Дашборд не отримував refresh-сигналів за всю історію репо, і ротація не стає першим. Ціна: після bump'а відкритий дашборд мовчки перестає діставати живі вузли мапи до наступної навігації. ✅ **Присуд 2026-07-31 — морф-стійкість контролера НЕ будуємо (won't-do), і механізм тепер доведений джерелом, а не переказом.** Idiomorph знімає дітей без пари хвостовим циклом `morphChildren`, а Stimulus `ElementObserver.processRemovedNodes` не бачить контейнер, бо той у `removedNodes` не потрапляє — отже `connect()` не покличеться. Але морф вмикає лише візит із `action:"replace"` на ту саму адресу, а таких на сторінці з мапою нема: `broadcast_refresh` у `:map` не шле ніхто (виключення запінене — `organization_spec.rb` «never tombstones the map stream»), `Tree#broadcast_map_update` іде `broadcast_replace_to`, а єдиний same-location redirect застосунку (`LocalesController#update`) стоїть за формою з `data-turbo="false"`. ⚠️ Тобто це важіль без пускача — **перш ніж будувати реініт, грепни пускач**. ⚠️ І пастка на той випадок, коли він з'явиться (виміряна, не виведена): `map#connect()` не має idempotency-гарда, а `_leaflet_id` лишається на контейнері після морфу, тож наївний повторний `connect()` упаде «Map container is already initialized» — реініт мусить спершу знищити зомбі-інстанс. Стан → [`00_07`](00_07_Action_Plan_Tracker) UI.4.
> - **(3) Епоха накриває ТРИ імені з семи — але рахувати адреси тут неправильно, і перша редакція цієї стелі саме це й робила.** Record-form (`[wallet, :transactions]`, `[cluster, :alerts]`, `[actuator, :commands]`) і `ota_channel_{uid}` лишаються безстроковими токенами свого запису. Питання не «скільки адрес непокрито», а **що по них тече**, і вимір дає ОДИН: `[wallet, :transactions]` (суми SCC, tx-хеші, статуси — `Wallets::TransactionRow`). Решта три не доставляють даних у принципі: обидва продюсери `[cluster, :alerts]` — чистий `broadcast_refresh_later_to` (нуль байтів, приймач переграє власний запит через HTTP, де скоуп доводиться заново), `[actuator, :commands]` несе `CommandStatusFrameStub` (клас 2), чий `src` ре-авторизується org-скоупленим `find` у `actuators_controller#set_command`, а `ota_channel_{uid}` розкриває прогрес кампанії поверх `uid`, який **уже стоїть у самому імені**. Дзеркально й на власну шкоду: серед ТРЬОХ покритих епохою один (`ews_alerts_org_*`) — теж чистий сигнал, тобто епоха вже витрачена на нульовий payload, поки money-адреса лишилась без неї.
>   - **Справжня ціна закриття — не lookup.** Для `[cluster, :alerts]` він безкоштовний (`EwsAlert` уже тримає `cluster.organization` у руці), для гаманця це один денормалізований PK-SELECT. Дорого інше: без tombstone bump = тиха втрата живості для чесних (той самий режим, за який відкинуто TTL у (в)), а tombstone для record-form має кардинальність **записів** — `Tree after_create :build_default_wallet`, тобто гаманців рівно стільки, скільки дерев. Ротація стала б `2 + N_кластерів + N_гаманців + N_актуаторів` броадкастів, майже все — нікому. Це той самий заборонений клас, що й фан-аут по каталогу локалей (§8.1а): там віссю каталогу були мови, тут — записи. Плюс `wallets.organization_id` **NULLABLE** штатно (`Tree#build_default_wallet` → `cluster&.organization`, а `Cluster has_many :trees, dependent: :restrict_with_error` (⚖️ 2026-07-30)), тож fail-closed дому імен дав би на сторінці гаманця не «нема живих оновлень», а виняток.
>   - ✅ **Важіль на всі СІМ імен ШИПНУТО (2026-07-30, ⚖️ founder'а): `config/initializers/turbo_stream_verifier.rb`** ставить `config.turbo.signed_stream_verifier_key` з `ENV["TURBO_SIGNED_STREAM_KEY"]`, тож ключ підпису більше не деривується з `secret_key_base`, коли секрет заведено. Ротація одного секрета знецінює кожне видане імʼя, не чіпаючи сесій, `api_access`, CSRF і ActiveStorage — доведено рантаймом, а не виведено з конфігу (ім'я, підписане процесом зі старим секретом, у процесі з новим дає `nil`, тоді як `message_verifier` іншої поверхні лишається валідним). Ops-рецепт → [`06_04 §5.9`](06_04_Secrets_Checklist), піни → `spec/initializers/turbo_stream_verifier_spec.rb`.
>     - 🔒 **Три стелі, і третя знайдена виміром уже після того, як я мало не записав протилежне.** (1) важіль **глобальний по організаціях** — тупіший за епоху, тобто відповідь на «злили щось, і ми не знаємо що», а не заміна їй; (2) лишає чесним ту саму тиху глухоту до наступної навігації, якої tombstone post-hoc не лікує — їх уже відреджектило; (3) 🔴 **діє лише з РЕСТАРТОМ процесів**, бо `Turbo.signed_stream_verifier` мемоїзований (`@signed_stream_verifier ||=`) — підміна ключа в живому процесі не робить нічого, і перша спроба це «довести» дала хибно-позитивний результат саме через мемо. Отже в рецепті він мусить стояти як «оновити секрет + прокотити рестарт», ніколи як консольна дія.
>     - ⚠️ **Свідомо БЕЗ boot-guard'а**, на відміну від AR-encryption ключів: за відсутності ENV гем деривує ключ як раніше, тож поведінка не змінюється й забутий секрет не валить застосунок. Ціна названа: він дає не падіння, а **мовчазну відсутність важеля**, і тому живе в deploy-чеклісті ([`06_04 §5.9`](06_04_Secrets_Checklist)), а не в коді. Дзеркально й на власну шкоду: у тестовому середовищі ENV порожній, тож наявність ініціалізатора й його відсутність дають ІДЕНТИЧНИЙ ключ — три поведінкові піни цього не бачать у принципі, і четвертий пінить саму проводку, чесно названий слабким.
> - **(4) Ротація НЕ тригериться перемиканням контексту.** Bump — подія рівня організації (підозра на злив, offboard), тож switch одного адміна перезавантажив би всіх її глядачів заради гігієни одного. Плюс межа привілею там і не перетинається: super_admin має легітимний доступ до обох організацій. Тобто збережений токен переживає switch — свідомий компроміс, дім присуду → [`04_03 §3.1`](04_03_REST_API_v1_Reference).
>
> ⚠️ **Вікно рендеру.** HTTP-відповідь, що почала рендеритись до коміту `increment!`, віддасть сторінку зі старою епохою, і другого tombstone для неї не буде. Ширина — тривалість одного запиту, тригер ручний і рідкісний; закриває це та сама дія (1), повторний поштовх.
>
> 🚫 **Два елементи прописаного плану відкинуто ВИМІРОМ, не за ціною.** (а) **Дворівневий резолвер (in-process memo → Redis)** — базова лінія була взята не та: продюсери вже платять 1–2 SELECT'и на броадкаст, а сам броадкаст іде раз на конверт, не на запис. Гірше — memo живе окремо в Puma й у Sidekiq: у його вікні сторінка рендериться з новою епохою, продюсер пише в стару, тож чесний глядач не дістає **нічого**, а відкликаний — **усе**. Мітигація інвертувала б себе. Замість двох гілок резолву — одна: дім імен лишається **чистою функцією**, а продюсери передають сам запис (`cluster.organization`), не `organization_id`. (б) **Client-side jitter** — машинерія під натовп, якого нема (глядачів на організацію нуль, а `broadcast_refresh_later_to` уже дебаунситься `Turbo::ThreadDebouncer`); стеля названа, код не писаний. (в) **Per-session стемп в імені** (дзеркало `session[:ps]`) — заборонений клас: імʼя спільне для всіх глядачів організації, тож персональне імʼя дало б фан-аут по ПІДПИСНИКАХ, а §8.1а вимагає, щоб ціна масштабувалася попитом, а не множником на кожного. Стемп на `connect` — так (він і стоїть, Ф1); стемп в АДРЕСІ — ні.

| Stream | Підписка у | Продюсер(и) |
|---|---|---|
| `"telemetry_stream_org_{id}_e{epoch}"` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` (черга `uplink` — firehose) |
| `[wallet, :transactions]` | `Wallets::Show` | `BlockchainTransaction#broadcast_new_transaction` (**поява** рядка — `prepend` + зняття плейсхолдера, СИНХРОННО) · `#broadcast_status_change` (**зміна** рядка) · `Wallet#broadcast_balance_update` (frame-заглушка балансу, клас 2 §8.1а) |
| `"ota_channel_{uid}"` | `Gateways::Show` · `Firmwares::Index` | `Downlink::PendingQueueService` [SEC.20] — живий FW.60 poll-тракт; `OtaTransmissionWorker` теж пише сюди, але сам **не має енкʼюера** (superseded) |
| `[cluster, :alerts]` | `Clusters::Show` | `EwsAlert#broadcast_new_alert` · `#broadcast_alert_update` — **сигнал** (`broadcast_refresh_later_to`), не фрагмент: §8.1б |
| `"ews_alerts_org_{id}_e{epoch}"` | `Alerts::Index` | `EwsAlert#broadcast_new_alert` · `#broadcast_alert_update` — обидва **сигнал** (§8.1б): сторінка має фільтри й пагінацію, а `Alerts::Row` тягне локаль ще й через `TextFormatter` |
| `"geospatial_matrix_org_{id}_e{epoch}"` | `Dashboard::Map` (рендериться `Dashboard::Home`) | `Tree#broadcast_map_update` |
| `[actuator, :commands]` | `Actuators::Show` | `ActuatorCommandWorker.broadcast_command_state_static` — ЄДИНА реалізація на весь тракт: `ResetActuatorStateWorker` і `Downlink::PendingQueueService` (успіх **і** обидва fail-шляхи) кличуть саме її. Payload = клас 2, `CommandStatusFrameStub` |

> 🔴 **Стріми з підписником ≠ робочий тракт — ціль теж мусить існувати в DOM тієї сторінки.** Саме тут ховались усі знайдені дефекти, і жоден із них не був видимий із коду продюсера. Три приклади, кожен іншого роду: `Wallet#broadcast_balance_update` слав у голий `wallet`-стрім (підписник був — на ІНШИЙ, композитний); `BlockchainMintingService` цілив у `transaction_{id}`, тоді як `Wallets::TransactionRow` рендерить `dom_id` = `blockchain_transaction_{id}`; `ResetActuatorStateWorker` цілив у `actuator_card_{id}`, а `Actuators::Card` рендерить `actuator_{id}` (і той самий контролер у синхронному шляху вживав ПРАВИЛЬНИЙ id).
>
> ✅ **Продюсерів у порожнечу знято пʼять** (2026-07-27, ⚖️ власника після інтент-археології — [`00_07`](00_07_Action_Plan_Tracker) UI.4). Присуд розділив їх за ПОХОДЖЕННЯМ, не за симптомом: `recent_commands_feed` та `insurance_card_{id}` цілили в Phlex-класи, яких на момент написання **не існувало** — обидва `NameError`или шість днів, доки coverage-PR не створив ці класи, щоб зупинити падіння; `contract_status_badge_{id}` був інлайн-`<span>`, доданий побіжно комітом про чергу, з коментарем «якщо Архітектор дивиться на нього»; `events_feed` мав **живий** компонент і org-скоуповані дані, але слав у ГЛОБАЛЬНИЙ стрім `"global_events"` без org-скоупу — тобто дротування розсилало б страхові виплати однієї організації на дашборди всіх; `actuator_card_{id}` був справжньою однорядковою опискою, АЛЕ `Card#render_controls` має гард на відсутність request-контексту, тож картка з воркера приходить БЕЗ кнопок Execute — виправлення самого рядка відвантажило б регресію у вигляді фічі.
>
> ✅ **Трактів у порожнечу більше немає** (2026-07-27). Останній — `command_status` — дотягнуто повністю: `Actuators::Show` рендерить ціль і підписана на `[actuator, :commands]`, продюсери звужені з голого `Organization` на той самий стрім, payload мігровано на клас 2. Заразом зник другий, розійдений рендерер стану (сторінка малювала `border-*`, компонент `bg-*` — ті самі стани різними кольорами) і ДРУГА, незалежна реалізація самого броадкасту в `ResetActuatorStateWorker`.
>
> 🔴 **Fail-шляхи закрито тим самим ходом — і без них дротування було б регресією.** Місця, що валять команду (`Downlink::PendingQueueService` TTL/oversized), броадкасту не робили взагалі; єдині, що робили, сидять у мертвому push-тракті. З живою підпискою бейдж провалених команд застигав би на «виконується» до перезавантаження: **живість, що бреше, гірша за чесну статику**. Лишились свідомо не покриті збої, що йдуть повз AASM-колбеки (`update_all` override-cancel, `update_columns` pre-dispatch). ⚠️ Точне формулювання коштувало виправлення: назвати їх «до-диспетчерськими» неправильно — `cancel_pending_for_actuator!` бʼє по скоупу `.pending`, а це `[:issued, :sent]`, тобто **і після** `dispatch!`. І «не бреше» теж завелике: бейдж скасованої команди застигає на «видано», хоча в БД вона вже `failed`, а Reset-джоби для неї не існує — тобто ніщо пізніше цього не вилікує. Чесно: він бреше **пасивним** станом, не активним (не стверджує, що клапан відкритий), і саме тому це прийнятний борг, а не безпечний нуль.
>
**Патерн:**

```ruby
# Підписка (у view_template компонента)
turbo_stream_from @wallet, :transactions

# Broadcast (у worker/service) — рендер ЗАВЖДИ через `html:` + Phlex-компонент
Turbo::StreamsChannel.broadcast_replace_later_to(
  [ @wallet, :transactions ],
  target: ActionView::RecordIdentifier.dom_id(tx),
  html: Wallets::TransactionRow.new(tx: tx).call
)
```

> ⚠️ **`partial:`/`locals:` тут не спрацюють — і голий `Turbo::Broadcastable` теж.** Партіалів моделей у репо НЕМА (`app/views/` тримає лише мейлери, layouts і Phlex-компоненти), тому успадковані `model.broadcast_update`/`broadcast_replace`, які дефолтяться на `to_partial_path`, кидають `ActionView::MissingTemplate` — синхронно, у виклику. Броадкастити лише явним `Turbo::StreamsChannel.broadcast_*_to` з `html:`. Прецедент — [`00_07`](00_07_Action_Plan_Tracker) ARCH.67: такий виклик у money-path-сервісі обривав батч-цикл, лишаючи `locked_balance` решти транзакцій замороженим.

> ⚠️ **Broadcast не має локалі глядача — і структурно не може мати (⊥, не баг).** `html:` — звичайний аргумент, тож Phlex-рендер відбувається **eagerly в процесі-продюсері**; `_later_` відкладає лише доставку. `LocaleSettable` — це `before_action`, тож у Sidekiq його нема, а `ApplicationController.renderer` `before_action`-ланцюг не проганяє: рендер бере `I18n.locale` **поточного треда**. Наслідок двоякий — продюсер із контролера (`resolve!` → `after_update_commit` → `broadcast_alert_update`) віддає локаль **того, хто клацнув** («латвієць бачить український рядок, бо українець натиснув Підтвердити»), а з воркера — `default_locale`. Глибше: один HTML летить у **спільний** stream N підписникам із різними локалями, тож єдиної правильної локалі там не існує в принципі. Reload лікує.

### 8.1а Правило: payload броадкасту не несе локаль-залежної прози

> 🧱 **Інваріант (фундамент, не оптимізація): вартість live-оновлення масштабується ПОПИТОМ (глядачі), НІКОЛИ каталогом (локалі).**
>
> Кількість локалей — це число, яке ми хочемо нарощувати вільно й дешево; кількість глядачів — реальний попит, за який платити не шкода. Будь-який дизайн, у якому додавання **невживаної** мови робить кожну наступну подію дорожчою, оподатковує саму амбіцію бути багатомовними.
>
> Тому «розкласти broadcast по локалях» (по стріму на мову) — **заборонений клас**, а не дорогий варіант. Ціна: на кожну подію — по Phlex-рендеру, по `INSERT` у `solid_cable_messages` і по `NOTIFY` **на кожну локаль каталогу**, з `message_retention: 1.day`. Solid Cable — Postgres, і хоч БД окрема (`_cable`), інстанс той самий, що обслуговує money-path: фан-аут по каталогу = множник на записи, що ділять IOPS і пул зʼєднань із мінтингом. І головне — переважна більшість тих рядків не доставляється **нікому**: робота не просто дорога, вона доказово змарнована.
>
> 🔴 **Класів відмови ДВА, і другий не має симптомів узагалі.** Опис вище («латвієць бачить український рядок») — це **недетермінізм**, і він правдивий лише там, де продюсера тягне КОНТРОЛЕР. Для компонента, чий увесь граф викликів — Sidekiq, наслідок протилежний: детермінована **стала `default_locale` назавжди**, тобто переклади в uk/lv/lt не були досяжні жодному користувачеві ЖОДНОГО разу з дня шипменту. Це **мертвий переклад**, не витік локалі: недетермінізм користувач бачить і зрештою повідомляє, а мертвий переклад невидимий для всіх — англомовний рев'ювер не помічає нічого дивного, `i18n-tasks` бачить УЖИТИЙ ключ, локаль-файли виглядають здоровими в усіх мовах.
>
> 🔒 Перевіряти це **механічно**, а не оком: `I18n.locale` у цьому дереві виставляється рівно з трьох місць (`LocaleSettable#before_action` · `locales_controller` · `ApplicationMailer#in_locale_of`), усі три — request- або mailer-звʼязані, і жодного Sidekiq-middleware чи ініціалізатора з локаллю немає. Отже **будь-який `t()`, досяжний лише з `app/workers/**`, є мертвим перекладом за побудовою** — це властивість графа викликів, а не здогад.
>
> ⚠️ **І перед тим як рахувати обсяг міграції, відсій locale-ІНВАРІАНТНІ ключі.** Значення, байт-у-байт однакове в усіх локалях (`ip_label: 'IP: %{ip}'`, `unknown_ip: "?.?.?.?"`), — це **дані, а не переклад**: YAML-дім змушує тримати N однакових копій і N зобовʼязань парності назавжди, і кожну копію перекладач може «виправити». Той самий клас, що ендоніми й емодзі-мапи (`ALERT_ICONS` — [`04_02`](04_02_Business_Logic_and_Services)). Наслідок практичний: компонент із вісьмома `t()` може нести лише дві справді перекладені фрази, і саме ця цифра, а не загальна, визначає ціну класу 1.
>
> **Два дозволені класи:**
> 1. **Locale-invariant payload** (найкращий) — броадкаст несе лише те, що однакове в усіх мовах: числа, ID, хеші, timestamp, `data-*`. Еталон уже в репо — `Dashboard::MapNode` (нуль `t()`). Підписи живуть у хромі сторінки, відрендереному один раз у запиті, де локаль відома.
> 2. **Viewer-driven pull** — броадкаст несе локаль-вільну заглушку (`turbo_frame` зі `src`), і кожен клієнт тягне фрагмент **своїм** запитом, де `LocaleSettable` уже відпрацював. Ціна — O(фактичних глядачів), нуль залежності від каталогу. Для рідкісних подій (OTA-прогрес) це прийнятно; для firehose (телеметрія) обовʼязковий клас 1.
>
> **Як обрати між класами — читай ЗНАЧЕННЯ, не міркуй про них.** Клас 1 виглядає дешевшим завжди, тож спокуса вибрати його за замовчуванням; чесний критерій один — **що саме зникне з не-англійських локалей**. Відкрий усі мовні файли для цих ключів і подивись очима. Якщо «переклад» виявиться транслітерацією англійського токена (`ЧАНК`, `OTA_ЛІНК` — випадок `Firmwares::OtaProgressBar`), клас 1 не втрата, а **усунення фальші**: англійською нічого не змінюється, українською стає чесніше. Якщо ж це живі слова (випадок `Actuators::CommandStatusBadge`), клас 1 — чиста втрата, яка до того ж **лягає лише на не-англійців**: у базовій локалі мітка часто дорівнює сирому токену (`issued: issued`), тож англомовний глядач не побачить різниці й дефект пройде ревʼю. Прецедент OTA — **не шаблон**, а один зі стану даних; переносити його рішення без перечитування значень означає вгадувати.
>
> ⚠️ Другий критерій — **частота події проти ціни round-trip**. Клас 2 коштує один додатковий запит на глядача на кожне оновлення; для рідкісних подій (баланс, OTA — хвилини) це непомітно, для секундних переходів статусу глядач може встигнути побачити заглушку в польоті. Тобто вибір не «який клас правильніший узагалі», а «що дешевше саме на ЦІЙ частоті».
>
> 🧩 **Другий шипнутий приклад класу 2 — `Actuators::CommandStatusFrame(Stub)`, і він свідомо ВІДХИЛЯЄТЬСЯ від першого.** У гаманця `src` ставить і сторінка (lazy-load дорогого балансу), і броадкаст. Тут сторінка рендерить фрейм **без** `src`: дані вже в `@commands` контролера, а рядків до 20 — двадцять lazy-фреймів дали б двадцять GET на першому ж відкритті заради того, що вже в пам'яті. Тобто **прецедент копіюється не цілком, а по ролях**: «стаб зі `src`» — з броадкасту, «фрейм без `src`» — з відповіді ендпоінта, а сторінковий фрейм отримує `src` лише тоді, коли його вміст справді дорогий.
>
> ⚠️ Дві дрібниці, що коштували б налагодження. **id фрейма ≠ id його вмісту** (`command_status_frame_{id}` обгортає `command_status_{id}`) — інакше дубль id у DOM, а ціллю мусить бути саме фрейм, бо він несе `src`. І **заглушка не порожня**: `animate-pulse`-плашка тримає місце бейджа, поки летить фетч, лишаючись locale-інваріантною — готовий `Skeleton` тут НЕ годиться, бо він локалізований (`t(".loading")`), тобто повернув би в payload рівно те, що клас 2 звідти прибирає.
>
> 🔴 **Третій критерій, який пояснює, чому боргові компоненти залишились саме ці: клас 2 непридатний для РЯДКА таблиці.** Заглушка класу 2 — це `<turbo-frame>`, а `<tbody>` за HTML-парсингом приймає лише `<tr>`: сторонній елемент туди не вкладається, парсер виносить його за таблицю (foster parenting). Обидва шипнуті прецеденти це підтверджують структурно — `Actuators::CommandStatusFrame` живе **всередині `<td>`**, `Wallets::BalanceFrameStub` — узагалі поза таблицею; жоден не заміняє рядок. Тому для обох боргових компонентів (`Alerts::Row` і `Telemetry::LogEntry` — обидва `<tr>`) вибір звужувався до «клас 1» або «сигнал» (§8.1б), і розводить їх **частота**. `Alerts::Row` пішов сигналом і зі списку вибув (тривоги рідкісні, а сам рядок несе десять `t()` плюс `TextFormatter`, тобто клас 1 означав би ампутацію прози; про реальну частоту сигналів — застереження в §8.1б, «тротлений» там лише шлях оновлення). `Telemetry::LogEntry` лишається — там firehose, де сигнал = перезапит сторінки на кожен пакет, тож **обовʼязковий клас 1**. ⚠️ Межа чесності: сама поведінка парсера в цьому репо **браузером не перевірена** ⚠️ (підстава застаріла 2026-07-31: `spec/features/` не порожня від 07-30, а живий JS-прогін став можливий — [`00_07`](00_07_Action_Plan_Tracker) TEST.7; сам парсер від того перевіреним НЕ став, тож твердження лишається сильною підставою, але тепер його МОЖНА виміряти), тож це сильна підстава, а не власний вимір.
>
> 🔴 **Але цей самий критерій закриває опцію, яку його ВЛАСНИЙ доказ відкриває — виправлено 2026-08-05.** Речення «`Actuators::CommandStatusFrame` живе всередині `<td>`» наведене вище як доказ, що клас 2 не заміняє РЯДОК. Воно ж є доказом, що клас 2 **заміняє КОМІРКУ**: `actuators/show.rb` рендерить цей фрейм усередині `td(...)`, і саме туди летить `CommandStatusFrameStub`. Тобто для `<tr>`-боржника вибір не «клас 1 або сигнал», а **«клас 1, сигнал, або клас 2 на одну комірку»** — перетаргетити продюсера з `dom_id(record)` на id фрейму в потрібній `<td>`, лишивши решту рядка інваріантною. Ціна названа чесно: новий маршрут + дія + `authorize` (питання контуру [`ARCH.77`](00_07_Action_Plan_Tracker)), один GET на глядача на кожен змінений рядок **без дебаунсера** (`broadcast_replace_later_to` не дебаунситься — дебаунсер має лише `broadcast_refresh_later_to`), і закриває воно рівно ту комірку, а не рядок. **Урок про сам док: абзац, що ПЕРЕЛІЧУЄ прецеденти на підтвердження заборони, треба перечитати ще раз питанням «а що ці ж прецеденти ДОЗВОЛЯЮТЬ» — інакше канон закриває напрямок власним доказом його відкритості.**
>
> ✅ **Третій шипнутий приклад класу 2 — і саме він, «на комірці», 2026-08-06** (`Wallets::TransactionStatusFrame(Stub)`, [`00_07`](00_07_Action_Plan_Tracker) I18N.2). Форма вийшла НЕ такою, як приписував пункт, і різницю варто тримати: пункт казав «перетаргетити продюсера з `dom_id(record)` на фрейм у статус-`<td>`», а вимір показав, що переходом статусу міняються ДВІ комірки — статус і хеш (`mark_as_sent` є єдиним у застосунку писальником `tx_hash`). Дослівне виконання заморозило б хеш на `PENDING_BLOCK` назавжди, тобто «фікс» відвантажив би дефект того самого класу, який лікує. Шипнута форма: **рядок лишається одиницею броадкасту, а локаль-залежна КОМІРКА всередині нього стає фреймом** — решта комірок (тікер · сума · хеш · час) locale-інваріантні й їдуть у payload'і як є. ⚠️ Другу локаль-залежну комірку зняли не міграцією, а виправленням ОДИНИЦІ: чіп типу токена тепер несе ТІКЕР (locale-інваріантні дані з `ERC20(…, symbol)`), а не сире значення enum'а, і суфікс із суми пішов — деномінація в рядку стояла ДВІЧІ (⚖️ founder 2026-08-06). **Тобто перш ніж будувати клас 2 для комірки, спитай, чи не є її вміст насправді locale-ІНВАРІАНТНИМ фактом, записаним не тією мовою.**
>
> 🔒 **І доказ тут довелось СТВОРИТИ, а не успадкувати від гейта.** `broadcast_payload_invariance_spec` рахує `t()` лише у власному джерелі broadcast-компонента: `Wallets::TransactionRow` має нуль `t()` і мав би нуль навіть із дротованим бейджем усередині, тож порушення лишилось би ТИХИМ. Носії — `transaction_status_frame_spec` (побайтова тотожність стаба в усіх налаштованих локалях ⊥ навмисна РІЗНІСТЬ фрейма між локалями: пара показує, що межа проходить рівно тут) плюс request-приклади на новий маршрут, включно з крос-тенант-відмовою й 404 на транзакцію ЧУЖОГО гаманця (другу вісь дає асоціація, не політика).
>
> 🔴 **Четвертий критерій, і він може заблокувати клас 1 повністю: CSS-only card-flip (§17) вимагає, щоб переклад ФІЗИЧНО стояв у кожному broadcast-`<td>`.** Мобільна картка малює мітку колонки через `content: attr(data-label)`, тобто мітка — це літерал на самому елементі, а не текст, який сторінка рендерить один раз. На десктопі її дає `<thead>` (локаль глядача, усе гаразд), але на мобільному `<thead>` схований — і працює саме `data-label`, що приїхав із процесу-продюсера. Хроми-якоря для нього немає там, де **ВСІ** рядки таблиці народжуються з броадкасту (у телеметрії `tbody` містить лише спінер-плейсхолдер; для порівняння `Alerts::Index` рендерив реальні рядки сервером і тому мав вихід). Три чесні варіанти, усі з ціною: CSS custom property, яку сторінка ставить раз і успадковують пізніше вставлені рядки (**у репо не вживається жодного разу** — тобто нова машинерія) · відмова від card-flip саме для цієї таблиці · Stimulus-гідрація. Вибір — ⚖️, стан → [`00_07`](00_07_Action_Plan_Tracker) I18N.2. ⚠️ Клас не специфічний для телеметрії: його успадковує **будь-яка** `gaia-responsive-table`, чиї рядки приходять броадкастом.
>
> 🧭 **Порядок робіт: спершу ЗНЯТИ мертве, потім мігрувати живе — і це економія, не стиль.** Міграція payload'а коштує роботи; зняття продюсера, який ні до кого не доїжджає, коштує рядка. Доказ — не темп, а склад: із шести боргових компонентів закрилось пʼять, і **справжньою міграцією payload'а була рівно ОДНА** (`CommandStatusBadge` → клас 2). Три відпали разом зі своїми продюсерами, ще один — разом із присудом про власність форми (§8.1б), тобто чотири з пʼяти не коштували міграції взагалі. ⚠️ Біжучий лічильник тут не тримаємо (він уже застарівав щоразу, коли список рухався) — тримаємо пропорцію, бо саме вона і є аргументом. Дзеркально: мігрувати ДО того, як з'ясовано, чи має продюсер підписника, означає платити за локалізацію payload'а, який нікуди не летить. Тож перед міграцією — звірка реєстру §8.1/§8.3, а не навпаки.
>
> **Гейт, що це тримає** — `spec/i18n/broadcast_payload_invariance_spec.rb`, форма «курована мапа як tripwire»: він **авто-виявляє** компоненти, які реально рендеряться в `broadcast_*`-сайтах (константа витягується з `html:`), тож новий broadcast-компонент потрапляє під перевірку **за замовчуванням** — вписувати нікуди не треба; свідомий виняток — іменований запис зі списку, що тільки скорочується, і мертвий запис у ньому червоніє.
>
> ⚠️ **Перевірка СТАТИЧНА — рахує `t(`/`I18n.t(` у джерелі компонента.** Це варто знати точно, бо тут довго стояв опис ІНШОГО механізму («зрендерити двічі у двох локалях і звірити байт-у-байт»). Той абзац написали як **прогноз** — до того, як гейт існував, — а коміт, що збудував гейт, канону не торкнувся; розбіжність прожила непоміченою, бо обидва формулювання звучать однаково правдоподібно. Рендер-порівняння в репо таки є, і **у двох місцях, не в одному**: `command_status_frame_spec.rb` ітерує ВСІ налаштовані локалі на рівні компонента, а `wallet_spec.rb` робить справді ДВОМОВНЕ побайтове порівняння на рівні ПРОДЮСЕРА (гонить реальний `broadcast_balance_update` у двох локалях) і додає сильнішу половину — асершн, що заглушка порожня, бо «однаково у двох локалях» саме по собі означало б лише «переклад ще не додано». ⚠️ Тут доти стояло «лише в спеці стабів, і не дві» — обидві клаузи хибні; показово, що це той самий абзац, який існує заради виправлення попереднього хибного опису механізму.
>
> 🔒 **Три речі, яких цей гейт не бачить** (стеля названа й у шапці спеки): (1) локаль-залежність, сховану в СЕРВІСІ, а не в компоненті — напр. `TextFormatter.alert_title`; (2) ДОЧІРНІ компоненти — payload тягне їхні `t()` за собою, тож запис зі списку знімається лише після читання дерева (демонстрація класу: `Codex::Citations::Pill` сидів двома рівнями нижче `Alerts::Row` і їхав у payload'і, поки той броадкастився — сам приклад уже неактивний, бо рядок мігрував на сигнал, але сліпота гейта лишається); (3) **однорядковий** `broadcast_*_to(...)` — регекс-екстрактор вимагає багаторядкової форми, і це виміряно, не припущено (бачить 1 із 2 викликів у `unpack_telemetry_worker.rb`). Перед реюзом машинерії для гейта, якому потрібен ПОВНИЙ набір продюсерів, її треба переписати на AST — інакше пропущений виклик = хибно-зелений.
>
> Міграція наявних поверхонь → [`00_07`](00_07_Action_Plan_Tracker) I18N.2 (той самий ratchet-порядок, що в UI.1: спершу migrate-to-green, потім HARD).

### 8.1б Хто володіє формою: рядок проти сигналу

> 🧱 **П'ята вісь контракту (2026-07-27).** До «продюсер ⟷ підписник ⟷ маршрут ⟷ скоуп» додається **власність форми**: у пари стрім+ціль рівно ОДИН власник — сторінка, що рендерить ціль, — і саме вона визначає форму payload'а. Продюсер має два легальні ходи: (а) штовхнути HTML, відрендерений **тим самим компонентом, яким сторінка-власник сама малює цю ціль**; (б) штовхнути **без-форменний сигнал** (`broadcast_refresh_*_to` або frame-stub) і дати кожному глядачу дотягнути своє.
>
> 🔴 **Момент, коли ДРУГА сторінка хоче оновлень тієї ж сутності, — це момент, коли push-HTML перестає бути легальним.** Саме тут ховався дефект `[cluster, :alerts]`: `EwsAlert` штовхав `Alerts::Row` (`<tr>` на шість колонок) в ОБИДВА стріми, тоді як `Clusters::Show` тримає власну компактну `<div>`-панель на три поля. Наслідок був не косметичний — оновлена тривога **міняла тег посеред сторінки**, лишаючи сусідні `<div>`-и як є.
>
> ⚠️ **І «привести контейнер до таблиці» цього НЕ лікує — бо дієслова різні.** Панель кластера показує лише `unresolved.limit(5)`, тож коректна операція при розвʼязанні тривоги там — **прибрати рядок і підтягнути шосту**, а на `Alerts::Index` — замінити рядок стилем «погашено». Фіксований HTML-фрагмент не виражає двох різних дієслів у принципі, тому спільний рядок-компонент цей клас не закрив би навіть теоретично. Це і є причина, чому «один компонент на сутність» тут — **хибна ціль**: компактний дайджест і повний worklist — різні продукти тих самих даних.
>
> ✅ **Сигнал закриває чотири речі одним відʼємним діфом:** форма лишається у власника · семантика «прибрати + підтягнути наступну» стає безкоштовною (сторінка переграє власний запит) · рендер їде в локалі **глядача**, тож поверхня зникає з міграції I18N.2 сама · спец-кейс `citations: []` випаровується разом із push'ем.
>
> ⚠️ **Але ОДИНИЦЯ вартості при цьому виросла з фрагмента до СТОРІНКИ, і це треба тримати в голові.** Старий шлях коштував один рендер + N доставок готового `<tr>`. Новий коштує N **повних GET** сторінки з боку глядачів — для `Clusters::Show` це шлюзи, нерозвʼязані тривоги, контракт і Codex-посилання. Інваріант §8.1а («ціна масштабується попитом, не каталогом») тримається — платять лише реальні глядачі, — але сигнал НЕ є універсально дешевшим за push, і саме тому §8.1а вимагає зважати на **частоту**. ⚠️ І не називай цей тракт «тротленим» цілком: 5-секундний `should_broadcast?` сидить ЛИШЕ в `broadcast_alert_update`; шлях створення тривоги обмежений тільки `Turbo::ThreadDebouncer` (0,5 с **на тред продюсера**), тож батч у Sidekiq дебаунситься приблизно до 2 сигналів/с, а не до одного на 5 с. Для рідких тривог це прийнятно; для firehose — ні, і саме там обовʼязковий клас 1.
>
> ⚠️ **Умова придатності — morph.** `broadcast_refresh_*_to` без `<meta name="turbo-refresh-method" content="morph">` дає не оновлення на місці, а повний Turbo-візит зі скидом скролу — на потоці тривог це гірше за дефект, який лікуємо. Метатеги стоять у `DashboardLayout`.
>
> 🔴 **І цієї умови НЕ ДОСИТЬ — друга половина знайдена 2026-08-05, і без неї сигнал ламає сторінку тихо.** На сторінці, що несе `turbo_frame` зі `src` (lazy-load), morph **ревертає фрейм у його плейсхолдер і не перезавантажує його**. Механізм у джерелі, не за правдоподібністю: Turbo кличе `reload()` на фреймі лише коли `shouldReloadWithMorph()` — а той вимагає `this.src && "morph" === this.refresh`, тобто **атрибута `refresh="morph"` на самому фреймі**. Без нього `beforeNodeMorphed` повертає `true`, фрейм морфиться разом із рештою DOM, підвантажений вміст замінюється назад на `Skeleton`, і ніщо його не тягне: `complete` не входить у `observedAttributes`, а lazy-обсервер чекає на ЗМІНУ перетину, якої не буде — фрейм із вьюпорта не виходив. `Wallets::Show` несе рівно два такі фрейми (баланс і blockchain-identity), тож сигнал на цій сторінці перетворив би обидві панелі на вічні пульсуючі заглушки — **на грошовому екрані, рівно в мить, коли мінт долітає**. ⚠️ І це не гонка: `broadcast_status_change` синхронно оновлює баланс, а рефреш іде через `Concurrent::ScheduledTask` із затримкою, тобто сигнал **надійно затирає щойно оновлений баланс**. Лік — `refresh="morph"` на КОЖНОМУ lazy-фреймі сторінки, і його ціна входить у кошторис: один сигнал = 1 GET сторінки **плюс по GET на кожен фрейм**, на кожного глядача. **Рефлекс перед будь-якою міграцією на сигнал: перелічи `turbo_frame`-и зі `src` на сторінці-власнику — умова «метатеги в лейауті» про них не знає нічого.** Клас ширший за Leaflet-пастку нижче: там morph нищив КЛІЄНТСЬКИЙ стан, тут — серверний вміст, відкочений у власну заглушку.
>
> 🔴 **А от `data-turbo-permanent` як «зворотний бік morph» — пастка, і ми на неї наступили.** Спокуса очевидна: morph зберігає DOM-вузли, тож вузол, чий стан **будує клієнт, а сервер віддає порожнім** (полотно Leaflet), хочеться позначити permanent. Але атрибут вмикається **на будь-якому Turbo-рендері**, не лише на morph (`preservingPermanentElements`), тоді як сам morph вимагає ще й `action === "replace"` — звичайний клік по пункту меню його НЕ дає. На такому візиті Turbo **пересаджує** вузол, Stimulus кличе `disconnect()`, і якщо контролер там прибирає за собою (`replaceChildren()`), він зносить разом із клієнтським DOM ще й **серверний контент усередині того самого вузла**. У `Dashboard::Map` це `#map_data_nodes` — тобто мапа лишилась би порожньою, а всі наступні `broadcast_replace` летіли б у неіснуючі id. Атрибут знято; правило — **не позначати permanent вузол, усередину якого сервер рендерить дані**, і перевіряти, що робить `disconnect()` контролера.
>
> 🔴 **«Дані» включають АТРИБУТИ, і саме ця половина правила пережила два попередні зняття (UI.11 крок 3, 2026-08-06).** Мапа й сайдбар були випадками серверного ВМІСТУ — його видно оком. Останній permanent-вузол дерева, `#theme-switcher`, не мав видимого тексту взагалі: усередині нього стояв `aria_label: t("theme.toggle_label")`, тобто локалізований рядок в **атрибуті**. Наслідок був такий самий (Turbo пересаджує старий вузол, morph permanent пропускає взагалі — `MorphingPageRenderer#preservingPermanentElements` просто виконує колбек без Bardo), але дефект був невидимий для зрячого QA і платив за себе **чужим обходом**: `LocaleSwitcher` мусив ходити повним перезавантаженням, інакше ім'я тумблера застрягало мовою першого візиту. **Рефлекс: питай не «чи видно там серверні дані», а «чи є в цьому піддереві бодай один рядок, який породив сервер» — включно з `aria-*`, `title`, `alt`, `value` і `data-label`.**
>
> ✅ **Станом на 2026-08-06 permanent-вузлів у дереві НЕМАЄ ЖОДНОГО**, і це міняє форму майбутнього гейта: замість allowlist'а дозволених id (реєстр, що гниє тихо) інваріант записується як заборона з іменованим винятком-нулем. Носій сьогодні — компонентна спека `theme_switcher_spec` (пін на ВІДСУТНІСТЬ атрибута) плюс браузерний приклад, що пінить сам інваріант — «ім'я тумблера дорівнює мові сторінки після перемикання» (mutation-verified: повернення атрибута червонить його поіменно). Ратифікація політики цілком — [`00_07`](00_07_Action_Plan_Tracker) UI.11.

> ⚠️ Раніше тут стояла нота, що `[cluster, :alerts]` має «розбіжність форми, вставка структурно невалідна». Присуд виявився глибшим за симптом (див. §8.1б): проблема не в тегу, а в тому, що продюсер узагалі диктував форму двом власникам одразу.

### 8.2 Turbo Frames (Lazy Loading)

Використовуються для відкладення дорогих запитів до бази даних до моменту після першого рендерингу сторінки.

| Frame | Використовується у | URL джерела |
|---|---|---|
| `wallet_balance_frame_{id}` | `Wallets::Show` | `balance_wallet_path(@wallet)` |
| `wallet_metadata_frame_{id}` | `Wallets::Show` | `metadata_wallet_path(@wallet)` |
| `simulation_results` | `OracleVisions::SimulationPanel` | Turbo form target |

**Патерн Skeleton:**

```ruby
turbo_frame_tag "wallet_balance_frame_#{@wallet.id}",
                src: balance_wallet_path(@wallet),
                loading: :lazy do
  render Views::Shared::UI::Skeleton.new(variant: :balance)
end
```

### 8.3 Turbo Target IDs (для Worker Broadcasts)

Іменовані DOM-цілі, що використовуються Sidekiq workers для інжекції контенту в реальному часі:

> 🧱 **Target-id — це та сама двостороння угода, що й імʼя стріму, але дому в неї ще немає, і саме на ній репо реально відвантажувало баги.** Розходження імені СТРІМУ прецедентів не має жодного; розходження ЦІЛІ дало три (`transaction_{id}` проти `dom_id` · `actuator_card_{id}` проти `actuator_{id}` · голий `wallet` проти композитного `[wallet, :transactions]`). Симптом завжди однаковий і безшумний: Turbo мовчки ігнорує `broadcast_replace` у ціль, якої в DOM немає.
>
> ⚠️ **«Просто вживай `dom_id`» — пастка, записана тут ПІСЛЯ виміру.** `dom_id(record, prefix)` завжди вставляє `param_key` МІЖ префіксом і id, тобто `dom_id(tree, :map_node)` дає `map_node_tree_42`, а не `map_node_42`. Безкоштовна заміна лише там, де рукописний рядок уже дорівнює `{param_key}_{id}` без описового слова (`actuator_{id}`, `blockchain_transaction_{id}`, `ews_alert_{id}` — усі троє вже на `dom_id`). З описовим префіксом це **координоване перейменування обох боків**, а там, де id ключується на не-PK колонку (`ota_progress_{uid}`), `dom_id` непридатний у принципі.
>
> ✅ **Форма, яку треба узагальнювати, уже є в репо:** `Actuators::CommandStatusFrame.dom_id(command_id)` — спільний метод класу, який кличуть ОБИДВА боки (сторінка, заглушка броадкасту й продюсер), тобто дзеркало `TurboStreams::Name` для цілей; для статичних синглтонів (`telemetry_feed`, `feed_placeholder`) — спільна константа. ⚠️ І третій шар дублювання, який робить клас підступним: **спеки пінять по ОДНОМУ боку кожна**, тож координовано-хибна правка (рядок у продюсері + його спека, без рендерера) лишає все зеленим. Стан → [`00_07`](00_07_Action_Plan_Tracker) UI.4.

| Target ID | Компонент | Оновлюється ким |
|---|---|---|
| `wallet_balance_frame_{id}` | `Wallets::BalanceFrameStub` → після фетчу `Wallets::BalanceFrame` | `Wallet#broadcast_balance_update`. ⚠️ Ціль — сам **turbo-frame**, а не `wallet_balance_{id}` усередині нього: payload = локаль-вільна заглушка зі `src`, фрагмент кожен глядач тягне своїм запитом (клас 2, §8.1а) |
| `blockchain_transaction_{id}` | `Wallets::TransactionRow` | `BlockchainTransaction#broadcast_status_change` (`dom_id`, не рукописний рядок). ⚠️ РЯДОК лишається одиницею броадкасту свідомо: локаль-залежна в ньому рівно одна комірка (статус, ↓), а комірка ХЕША змінюється тим самим переходом (`mark_as_sent` — єдиний у застосунку писальник `tx_hash`), тож перетаргетити продюсера на саму комірку означало б заморозити хеш на `PENDING_BLOCK` назавжди |
| `tx_status_frame_{id}` | `Wallets::TransactionStatusFrameStub` → після фетчу `Wallets::TransactionStatusFrame` (з `StatusBadge` усередині) | той самий продюсер: стаб їде ВСЕРЕДИНІ рядка. Клас 2 на КОМІРЦІ (§8.1а) — сторінка рендерить фрейм БЕЗ `src` (дані вже в `@transactions`; 50 lazy-фреймів дали б 50 GET на першому паінті), броадкаст підставляє стаб зі `src`, ендпоінт `GET /wallets/:wallet_id/transactions/:id/status` віддає фрейм знову без `src`. Дім адреси — `Wallets::TransactionStatusFrame.dom_id` |
| `transactions_ledger` · `empty_ledger` | `Wallets::Show` — константи `LEDGER_TARGET` / `EMPTY_PLACEHOLDER_TARGET` (обидва боки тракту кличуть їх, а не рядок) | `BlockchainTransaction#broadcast_new_transaction`: `prepend` свіжого рядка + `remove` плейсхолдера. Дієслово диктує сортування (`created_at: :desc`), тому `prepend`, не `append`. ⚠️ Стабільну адресу сторінка віддає **лише на першій сторінці** пагінації — `prepend` коректний тільки там, де рендериться початок списку, тож поза нею цілі свідомо не існує й тракт тихо вимикається. ⚠️ Форма броадкасту СИНХРОННА (не `_later_`): дві незалежні джоби не мають гарантії порядку, і при інверсії `replace` влучив би в ціль, якої ще немає, а `prepend` слідом посадив би рядок зі старим статусом. ⚠️ І саме тому обидва виклики **rescue-ізольовані**: виняток із `after_*_commit` пролітає нагору з `create!` — `commit_records` має `ensure`, але НЕ `rescue` (доведено мутацією, бектрейс іде крізь `create!`), — а на сайтах створення це коштувало б необоротно: KlimaDAO вже виконав on-chain `retire` до транзакції й пішов би на другий по Sidekiq-retry, slash і Solana осіли б у `manual_review` через збій кабелю. Тим самим проходом ізольовано й `#broadcast_status_change`: дірка там та сама, а її пускачі (`mark_as_sent!`/`confirm!`/`fail!`) — усі money-переходи |
| `telemetry_feed` · `feed_placeholder` | `Telemetry::LiveStream` | `UnpackTelemetryWorker` |
| `ews_alert_{id}` | `Alerts::Row` | **лише синхронний** `AlertsController#resolve` (turbo_stream replace у `dom_id`). Обидва броадкасти `EwsAlert` мігрували на сигнал (§8.1б), тож push-продюсера в цієї цілі більше немає. Ціль `alerts_list` вибула звідси разом із ними: її тримають `Alerts::Index` (`tbody`) і `Clusters::Show` (`div`) як власний якір списку, а не як приймач броадкасту |
| `map_node_{id}` | `Dashboard::MapNode` (у `Dashboard::Map` ← `Dashboard::Home`) | `Tree#broadcast_map_update` — **еталон класу 1** (нуль `t()`); стрім org-скоуплений, продюсер fail-closed без кластера |
| `ota_progress_{uid}` | `Firmwares::OtaProgressBar` | `Downlink::PendingQueueService` [SEC.20]: hint → 0% · chunk-fetch → `ch+1/total` · `fw=` → COMPLETE (Rails бачить кожен fetch Королеви; initial-render = `Gateways::Show` + `Firmwares::Index`). ⚠️ Продюсерів **два**: сюди ж пише `OtaTransmissionWorker`, у якого немає енкʼюера (superseded push-ера) — §8.1 це називає, і тут теж має стояти, інакше таблиці одного доку суперечать одна одній |
| `command_status_frame_{id}` | `Actuators::CommandStatusFrameStub` → після фетчу `Actuators::CommandStatusFrame` (з бейджем усередині) | `ActuatorCommandWorker.broadcast_command_state_static` — успіх і fail однаково. ⚠️ Ціль — сам **turbo-frame**, а не `command_status_{id}` бейджа всередині: payload = локаль-вільна заглушка зі `src`, фрагмент кожен глядач тягне своїм запитом (клас 2, §8.1а) |

> ✅ **Цілей без сторінки більше немає** (2026-07-27) — і жодного продюсера в порожнечу теж. Останній тракт (`command_status`) дотягнуто; решту пʼять знято того ж дня разом із їхніми продюсерами.
>
> 🧭 **Два дефекти, які легко сплутати, бо симптом однаковий («нічого не оновлюється»).** «Нікуди» = сторінка не рендерить `target`; «нікому» = ніхто не підписаний на стрім. Тут довелось закрити ОБИДВА, послідовно: спершу сторінка почала рендерити ціль, і лише тоді підписка стала осмисленою. Гейта на жодну з цих осей поки НЕМА (він — відкритий пункт [`00_07`](00_07_Action_Plan_Tracker) UI.4); а коли зʼявиться, він за побудовою бачитиме лише другий: пара «продюсер ⟷ підписник» відповідає на «чи є кому слухати», і структурно не може відповісти на «чи рендериться ціль». Тобто вісь «ціль існує в DOM» лишається на читанні навіть після того гейта.
>
> `Alerts::Badge` тут більше немає — і компонента теж немає ніде: разом із його єдиним продовим рендерером (`EwsAlert#broadcast_status_change`, тракт із ціллю, якої не існувало в DOM жодної сторінки) 2026-07-27 знято сам клас, його спеку, Lookbook-preview і 4-локальний скоуп `alerts.badge.*`. ⚠️ Тут довго стояло «лишається змонтованим лише в Lookbook — доля відкрита в UI.4»: обидві половини були хибні, і вказівник вів у пункт, де такого рішення немає. Наслідок зняття, який лишається чинним: із `StatusBadge::STYLES` зник **носій колізії** `active` (див. §6.1), тож прибирання мертвих записів звідти безпечне.

---

## 9. Чекліст Доступності

Всі компоненти перевіряються за цим чеклістом:

| Правило | Реалізація |
|---|---|
| `role` на семантичних елементах | `role="table"` на таблицях, `role="status"` на бейджах, `role="navigation"` на бічній панелі, `role="group"` на StatCard |
| `aria-label` на інтерактивних елементах | `<button>` та icon-only `<a>` мають описовий `aria_label:`. **Виняток [UI.3]:** лінки з видимим текстом + динамічним дочірнім контентом (nav-item + EWS-badge у `Navigation::Sidebar`) — БЕЗ `aria_label` (він перекриває дочірній текст для SR, badge стає нечутним); такі читаються дочірнім текстом + `aria-current` |
| `aria-current="page"` | Активні елементи навігації у `Navigation::Sidebar` |
| `scope="col"` на `<th>` | Всі заголовки таблиць |
| `focus-visible:` а не `focus:` | 100% відповідність у всьому дереві компонентів. ⚠️ Числа тут немає свідомо — нижня межа «83+» стояла з 07-2026 і не рухалась, поки дерево росло; перевірка = греп за голим `focus:` (без `-visible`/`-within`) по `app/views/**`, і сьогодні він дає нуль |
| `aria-hidden="true"` на декоративних елементах | Іконки бічної панелі, фонові текстові водяні знаки |
| Клавіатурно-навіговані focus rings | `focus-visible:ring-2 focus-visible:ring-gaia-primary` на всіх інтерактивних елементах |
| Контрастність кольорів | ⚠️ **НЕ гарантована автоматично — токен придатний для ПОВЕРХНІ, а не «взагалі».** Семантичні токени дають тем-парність, але не контраст: пару `text-*` × `bg-*` треба міряти на тій поверхні, де вона реально стоїть. Зокрема `gaia-primary` — бренд-акцент (§3.1), і як ТЕКСТ на світлих `gaia-*`-поверхнях він AA не тримає; для тексту НА ньому існує парний `gaia-primary-text`. **Статичним сканом це невимірне** — фактичний фон часто приходить від батьківського компонента або з `<body>`, — тож гейт `spec/quality/design_token_existence_spec.rb` судить ІСНУВАННЯ токена й ніколи придатність. ✅ **Але машинний ПРИЛАД відтепер є (2026-08-07):** `lib/silken_net/contrast.rb` (WCAG-арифметика, pure Ruby, оракули з WebAIM + W3C ACT) + `spec/support/contrast_audit.rb` (браузерний збирач через cuprite). Він розв'язує фактичну пару в рендері, компонує стек напівпрозорих шарів і судить кожну тему окремо. ⚠️ Це **інструмент, не гейт**: гейт ставиться лише після ліку кореневих токенів, інакше червонить на `dashboard_layout` з дня народження. Виміряні числа й черга → [`00_07` UI.3](00_07_Action_Plan_Tracker) |
| `disabled:opacity-50 disabled:cursor-not-allowed` | Всі відключені кнопки (наприклад, видалення PhotoCard) |
| `role="status" aria-label="Loading…"` | Компонент `Skeleton` |
| Причина відмови форми оголошується | Форма, що рендериться на 422, віддає причини через `Views::Shared::UI::ErrorSummary` (`role="alert"`) — і блок стоїть **перед** полями. ⚠️ Роль тут несуча: сторінка просто перемальовується, тож без неї незряча людина не має жодного сигналу, що сабміт не пройшов. ⚠️ Дзеркальна вимога до контролера: HTML-гілка мусить віддати саме 4xx — на `200` Turbo відповідь викидає, і блок не доїде взагалі [SEC.25] |

### Стандартний Патерн Фокусу

```ruby
# ✅ Канонічне focus ring для всіх інтерактивних елементів
class: "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"

# ✅ Патерн переходу
class: "transition-all duration-200 ease-in-out"
class: "transition-colors duration-300"   # перемикання теми
```

---

## 10. Lookbook (Дослідник Компонентів)

> **Тести view-компонентів** — конвенції написання спек + карта покриття (який spec що верифікує) живуть у [`04_06`](04_06_Testing_Guide_and_Coverage) (Testing Guide: Частина A — конвенції, §A.10 — карта покриття). One-Home: 04_06 володіє view-component-тестуванням; цей документ — реєстр компонентів ([§6](#6-реєстр-компонентів)) + Lookbook-explorer нижче.

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
| `SkeletonPreview` | Default (balance), Text, Card, Stats, Table, Map, Custom lines, Interactive |
| `WalletTransactionRowPreview` | Confirmed carbon, Pending forest, Failed, Processing, Interactive |
| `WalletBalanceDisplayPreview` | Tree wallet, Locked funds, Org wallet, Zero balance, Interactive |
| `ClusterItemPreview` | Healthy, Under threat, Low health, Interactive |
| `ActuatorCommandStatusBadgePreview` | All command statuses, Interactive |
| `ActuatorCommandRowPreview` | Confirmed open, Issued activate, Failed close, Interactive |
| `PhotoCardPreview` | Image photo, File fallback |

---

## Додаткові Матеріали

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
  url_helper: ->(page:) { helpers.cluster_trees_path(@cluster, page: page) }
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

---

## 11. Міграція з ActionController::API на ActionController::Base

### Контекст

`Api::V1::BaseController` раніше успадковував `ActionController::API`. Це було змінено на `ActionController::Base`
(з `layout false`), оскільки `ActionController::API` не надає `ActionView::Rendering` з `view_context`,
необхідним для Phlex `render_in`. При `ActionController::API` Phlex-компоненти повертали порожній body
з HTTP 200 — тести проходили, бо перевіряли лише `have_http_status(:ok)`, не вміст відповіді.

### Виявлені та виправлені баги

Після переходу Phlex-компоненти почали реально рендеритись, що виявило приховані помилки:

| Компонент | Баг | Виправлення |
|-----------|-----|-------------|
| `Gateways::Show` | (1) `@gateway.firmware_hash` — колонка не існує; (2) `hardware_key&.uid` — HardwareKey має `device_uid`, не `uid` | (2) `.device_uid`. 🔴 **(1) `try(:firmware_hash)` було НЕ виправленням, а тихим замовчуванням**, і саме тому запис тут протух: fallback давав `nil` ЗАВЖДИ, тобто рядок стверджував спроможність, недосяжну за побудовою, а «покривав» її лише мок, що поле вигадував. Сьогодні компонент малює літеральне `—` з поіменним `[UI.10]`-коментарем; присуд «дротувати ХЕШ чи зняти рядок» відкритий у [`00_07`](00_07_Action_Plan_Tracker) UI.10 |
| `Provisioning::Success` | `@device.did` — Gateway має `uid`, не `did` | Замінено на `@device.try(:did) \|\| @device.try(:uid)`. Компонент знято 2026-08-03 при переході на PRG-редирект; урок лишається живим у `device_path_after_provisioning` (`app/controllers/api/v1/provisioning_controller.rb`) |
| `Maintenance::Show` | `edit_maintenance_record_path` — маршрут `:edit` не існував | Додано маршрут `:edit` та дію контролера `edit` |
| `Views::Shared::UI::PhotoCard` | `maintenance_record_photo_path` не існував: зайвий `as:` у вкладеному `resources` подвоював префікс, тож сторінка запису **з будь-яким фото** падала в 500 | Знято `as:` (природне ім'я вкладеного ресурсу). 🔴 Чому пережило рядок вище: чотири спеки `prepend`-или модуль, який ВИЗНАЧАВ відсутній хелпер, а request-приклада на HTML-`show` із фото не існувало — стаби знято, приклад додано |

### CI: Компіляція Tailwind CSS

Tailwind CSS повинен бути скомпільований перед тестами. Крок `bin/rails tailwindcss:build`
додано до CI workflow перед запуском rspec (обидва jobs: `test` та `feature-test`).
Layout-компоненти (`AuthLayout`, `DashboardLayout`) використовують `stylesheet_link_tag "tailwind"`,
що вимагає наявності скомпільованого `tailwind.css` у `app/assets/builds/`.

### Правила

1. **Компоненти НЕ ПОВИННІ звертатись до методів/колонок моделей, що не існують** — навіть якщо
   компонент "працював" під `ActionController::API`, перехід на `ActionController::Base` виявить
   баг як `NoMethodError` під час рендерингу.
2. **Тести view-компонентів повинні використовувати моки з полями, що відповідають реальній схемі БД**
   (наприклад, `device_uid`, а не `uid` для HardwareKey).
3. **`bin/rails tailwindcss:build` обов'язковий перед тестами**, якщо layout-компоненти посилаються
   на скомпільовані CSS-файли.

> **CSRF** — `protect_from_forgery with: :exception` + Bearer-bypass через `handle_unverified_request`: дім опису — §1 (архітектура контролера).

---

## 12. Інтернаціоналізація та Локалізація (i18n)

> SSOT для чотиримовного UI (EN — default; UA/LV/LT — auto-detect через
> Accept-Language або explicit cookie; розширюваний до N мов додаванням рядка
> в `config.i18n.available_locales` + одного YAML-набору) та для Phlex
> `t(".key")` autoscope, CI-гейтів, controller/backend локалізації.
> Об'єднує колишні §12 (Phase 1-2) та §19 (Convention over Configuration).

### 12.1 Архітектурні правила (foundational)

1. **Жодних hardcoded user-facing strings.** Все, що користувач бачить (UI текст, flash, error JSON, mailer body) — через `I18n.t`. Hardcoded UA/EN рядки у `app/views/components/**/*.rb` та `app/controllers/api/v1/**/*.rb` **мають** блокуватись CI. ⚠️ **Фактично не блокуються:** job `i18n_check` (`ci.yml`) ганяє лише `i18n-tasks missing` / `check-consistent-interpolations` / `check-normalized` — усі три звіряють **парність ІСНУЮЧИХ `t()`-ключів** між локалями; сканера сирих строкових літералів у репо немає, тож хардкод у «захищеній» зоні проходить зеленим. Робота → [`00_07`](00_07_Action_Plan_Tracker) I18N.1.
2. **Per-domain YAML layout.** Файли локалізації лежать як `config/locales/<domain>/<locale>.yml`. Кожен «домен» = верхньокореневий namespace (`wallets`, `codex`, `actuators`, `flash`, `errors`, ...). Масштабовано до десятків доменів без monolithic `en.yml`. Детальна структура — §12.3.
3. **Class-name autoscope для Phlex.** `ApplicationComponent` override'ить `t` (від `Phlex::Rails::Helpers::Translate`):
   - `t(".key")` всередині `Codex::Show` резолвить у `I18n.t("codex.show.key")`
   - Абсолютний ключ (`t("flash.errors.unauthorized")`) працює без autoscope
   - Працює як у controller-render контексті, так і в `Component.new(...).call` (specs/Turbo broadcasts)
   - Для анонімних subclasses (`Class.new(Component)` у тестах) scope обчислюється по першому named ancestor
   - **Міграція завершена:** всі компоненти переведені на `t(".key")` relative-lookup. Абсолютні `t("codex.fractions.current")` залишаються тільки для cross-scope ключів (ключ із сусіднього компонента). `I18n.t()` у view-шарі повністю замінено на `t()` — 0 залишків. Detail-pattern та приклади — §12.6.
4. **Controller-side strings.** Flash, error JSON, redirect notice — всі через `I18n.t("flash.<controller>.<action>")` / `I18n.t("errors.api.<code>")`. Hardcoded UA рядки у контролерах = CI failure. Детальний мапінг доменів — §12.8.
5. **Mailer та service-worker.** Mailer templates (`app/views/<mailer>/*.erb`) та `pwa/service-worker.js` поки **out of scope** для авто-перевірки — їх локалізують вручну за тим самим патерном (`config/locales/mailers/...`, `pwa/...`). Service-worker не йде через I18n (це JS у браузері). Поточний backlog — §12.13.

### 12.2 Конфігурація

`config/application.rb`:
```ruby
config.i18n.available_locales = %i[uk en lv lt]
config.i18n.default_locale    = :en
config.i18n.fallbacks         = true    # локаль-НЕЗАЛЕЖНИЙ ланцюг, див. нижче
config.i18n.load_path        += Dir[Rails.root.join("config/locales/**/*.yml")]
```

**`fallbacks = true` — не «увімкнути», а САМЕ локаль-незалежна форма.** Railtie
(`ActiveSupport::I18nRailtie#init_fallbacks`) приймає чотири форми — `true`,
Array, Hash і `OrderedOptions`; з `true` він будує `Fallbacks.new(default_locale)`,
тобто хвіст `[:en]` для **будь-якої** локалі, зокрема ще не існуючої, а
регіональні дістають ще й parent-ланку: `pt-BR → [:pt-BR, :pt, :en]`. Саме це
й означає обіцянка «розширюваний до N мов додаванням рядка» — жодна нова мова
не потребує запису у fallback-конфізі.

> ⚠️ **Чому НЕ поіменний хеш** (стояв тут до 2026-07-26). Hash — єдина з чотирьох
> форм, яка кладе всі локалі в `@map` і лишає `defaults` **порожнім**: п'ята
> локаль не діставала `:en` взагалі. І гірше — `production.rb` (Rails-скаффолд)
> мав власний `config.i18n.fallbacks = true`, а environment-файли вантажаться
> ПІСЛЯ тіла `Application`, тож railtie бачив лише останнє значення: прод жив на
> локаль-незалежному ланцюгу, dev/test — на хеші. Розбіжність тиха, але кусюча:
> у test ще й `raise_on_missing_translations`, тож нова локаль валила б спеки там,
> де прод спокійно віддавав би англійську. Дім тепер один — `application.rb`.
> **Пріоритет вибору мови (без збереженої cookie):**
> `request.preferred_language(available_locales)` читає `Accept-Language`
> браузера — `uk` → `:uk`, `lv` → `:lv`, `lt` → `:lt`, будь-що інше → `:en`.
> Тобто українець, латвієць і литовець отримують свою мову автоматично;
> решта світу — English. Явний вибір через switcher зберігається у постійній
> cookie і має найвищий пріоритет.
>
> **Чому `uk`, а не `ua`?** `uk` — IETF BCP 47 / ISO 639-1 код **мови**
> (Ukrainian). `ua` — ISO 3166-1 код **країни** Україна. `<html lang="uk">`
> — єдиний валідний варіант для browser/screen-reader negotiation. UI-label
> для користувача — `UA · Українська`, де довга назва береться з
> `locale.available.<code>` у YAML, а дволітерний префікс **деривується** як
> `code.upcase`.
>
> 🧱 **Мапа коротких кодів несе рівно ОДИН запис — і це теж one-home, а не
> економія.** `LocaleSwitcher::SHORT_CODE_OVERRIDES` перелічує лише локалі, чий
> код розходиться з очікуваним написом, тобто саме `uk → UA`; решта каталогу
> дістає префікс деривацією й у код не вписується. Раніше хеш ніс усі чотири
> локалі, з яких три дослівно дорівнювали власному фолбеку — тобто був **другим
> реєстром локалей**, який на орієнтирі 150+ мов запрошував дописувати кожну
> нову. Обидва рецидиви (надлишковий запис · запис, що пережив свою локаль)
> червонять `spec/views/shared/ui/locale_switcher_spec.rb` — курована мапа як
> tripwire ([`00_06 §3`](00_06_SSOT_Documentation_Standard)).
>
> 🧱 **Ендоніми живуть ЛИШЕ в базовій локалі — і це не економія, а тип даних.**
> «Українська» однакова в будь-якому UI: користувач шукає в перемикачі власну
> назву своєї мови, не її переклад. Тобто таблиця локаль-**інваріантна**, і
> кожна зайва копія — не переклад, а запрошення її «виправити». Копії росли як
> N×N (чотири мови = 16 рядків, при орієнтирі 150+ — 22 500), тож решта каталогу
> тепер бере значення fallback-ланцюгом. Ruby-мапа з §12.14 тут НЕ потрібна саме
> тому, що `i18n-tasks missing` цей скоуп і так ігнорує (динамічний ключ) —
> механізм, яким §12.14 обґрунтовує заморожену мапу, на цю поверхню не діяв.
> Вісь тримає `spec/i18n/locale_catalog_invariance_spec.rb`: базова визначає
> ендонім для КОЖНОЇ налаштованої локалі · жодна не-базова не має власної копії
> (`fallback: false`) · усі UI-локалі резолвлять однаково. Спека ітерує
> `available_locales`, тож п'ята мова не потребує правки спеки, але одразу
> потрапляє під неї.

> 🧱 **Базовий шар перекладів дає гем `rails-i18n` — і він МУСИТЬ лишатись у
> головній групі `Gemfile`.** Власні YAML під `config/locales/` покривають лише
> НАШІ рядки; усе, що малює сам Rails — `errors.messages.*` (валідація),
> `date.*`/`time.*` (формати, назви днів і місяців), `number.*` (роздільники,
> валютний символ), `helpers.submit.*`, `datetime.distance_in_words.*` — живе в
> цьому гемі, і він же вмикає **правила плюралізації** (без них українська йде
> за дефолтним `one/other`, тож форми `few`/`many` не можуть бути обрані ніколи,
> хоч би скільки їх було в YAML).
>
> ⚠️ **Пастка, що вже спрацювала (2026-07-26).** Гем був у `Gemfile.lock` —
> але лише **транзитивно**, як залежність `i18n-tasks`, оголошеного в групі
> `development, test` та ще й з `require: false`. `Bundler.require` не брав його
> в ЖОДНОМУ середовищі → `RailsI18n::Railtie` не спрацьовував → локалі гема не
> доїжджали в `I18n.load_path`, і uk/lv/lt мовчки падали на англійський fallback:
> українець бачив `can't be blank`, `Sunday` і символ `$`. Присутність у
> lock-файлі **не означає завантаження** — умова саме `Bundler.require`, тож
> перевіряти треба рантаймом (`I18n.load_path.grep(/rails-i18n/)`), не грепом по
> `Gemfile.lock`.
>
> 🔴 **Наслідок-пастка, яку варто знати ДО наступного i18n-аудиту: «приклеєний
> хвіст».** Локалізоване ядро з хардкодною обгорткою читається як **одна
> послідовна помилка**, доки ядро зламане — і тому не викликає підозри. Живий
> випадок: `shared/ui/relative_time` конкатенував сире `" ago"` до locale-aware
> `time_ago_in_words`; поки гем не вантажився, обидві половини були англійські й
> компонент виглядав цілісним. Щойно проміжок став перекладатись, вийшло «3
> хвилини **ago**» — тобто **фікс фундаменту зробив симптом ГІРШИМ, і саме це
> його виявило**. Правило звідси двояке: (1) полюй на такі хвости ПІСЛЯ будь-якої
> зміни фундаменту, не до неї; (2) конкатенація локалізованого зі статичним —
> завжди підозра, бо в іншій мові маркер може стояти з іншого боку (в `ago`-ключі
> він стоїть ПІСЛЯ проміжку в en/uk і ПЕРЕД ним у lv/lt — конкатенацією це не
> виражається взагалі).

### 12.3 Структура локалей (per-domain, не файли-портянки)

```
config/locales/
├── defaults/<locale>.yml       # app-shell: name, theme, locale-switcher, accessibility
├── components/<locale>.yml     # cross-cutting UI components
├── navigation/<locale>.yml     # sidebar, top bar, breadcrumb
├── sessions/<locale>.yml       # login screen
├── dashboard/<locale>.yml      # dashboard home
├── trees/<locale>.yml          # tree show page
├── wallets/<locale>.yml        # wallet page
├── flash/<locale>.yml          # controller flash messages
└── errors/<locale>.yml         # error JSON
```

Один домен = одна папка × **по файлу на кожну налаштовану локаль**. Nesting тримати shallow (≤ 4 рівнів). Fallback-ланцюжок (§12.2) гарантує, що частково перекладений файл не ламає UI. Додавання нового домену — повний набір файлів, `i18n-tasks missing` має лишатися зеленим.

> 🧱 **Роздрібнення локалей у цьому документі НЕ повторюється — і це навмисно.** Єдиний дім переліку — `config.i18n.available_locales` (§12.2); канон називає **правило** («по файлу на локаль»), а не **реєстр**. Причина емпірична: коли документ носив `{uk,en}`, роздрібнення застаріло мовчки при доданні lv/lt — і рецепт §16.2 почав радити створити два файли там, де HARD-гейт парності вимагає всі. Реєстр, скопійований у прозу, старіє рівно тоді, коли каталог росте, тобто саме тоді, коли на нього дивляться. Це той самий one-home-борг, що трекається [`00_07`](00_07_Action_Plan_Tracker) I18N.3 — тут він закритий тим, що дублю просто немає.

### 12.4 Resolution priority (`LocaleSettable` concern)

```
params[:locale] → cookies[:locale] → request.preferred_language → I18n.default_locale
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^ 🔴 МЕРТВИЙ ЩАБЕЛЬ
```

> 🔴 **Третій щабель не спрацьовує НІКОЛИ, і виміряно це рантаймом 2026-08-06, не виведено з коду:** `ActionDispatch::Request` не має методу `preferred_language` (він приходить із гема `http_accept_language`, якого в `Gemfile` немає — `respond_to?(:preferred_language)` віддає `false`). Сам концерн має гард `return nil unless request.respond_to?(:preferred_language)`, тож щабель провалюється **мовчки**: помилки немає, лог чистий, а `Accept-Language` браузера не читається взагалі. Наслідок практичний і б'є саме по орієнтиру 150+ мов: **перший візит будь-якої людини — завжди `default_locale`**, доки вона сама не клацне перемикач; для гостя, який приходить із пошуку українською, сайт відкривається англійською. Клас — «мовчазний дефолт»: дефект тут не в тому, що написано, а в тому, чого НЕ написано (відсутній гем), тож жоден греп по коду його не показує. Стан і присуд (додати гем ⊥ розібрати заголовок самим ⊥ визнати щабель зайвим і зняти його з документації) → [`00_07`](00_07_Action_Plan_Tracker) I18N.3.

Усі джерела whitelist'яться проти `I18n.available_locales` — adversarial input просто провалюється на default. Concern підмішаний у **обидва** `ApplicationController` і `Api::V1::BaseController` — інакше після POST `/locale` + redirect Dashboard ігнорує щойно записану cookie і відкочується на `default_locale` (legacy 2-кліки-щоб-змінити-locale bug, фікснутий саме інклудом у обох контролерах).

### 12.5 LocaleSwitcher (`Views::Shared::UI::LocaleSwitcher`)

Native `<form>` + `<select>` + `onchange="this.form.requestSubmit()"` — Rails-canonical pattern. Браузер сам обробляє позиціонування, keyboard navigation, focus management та accessibility — **нуль custom JS**, **без Stimulus**, **без Popover API**. Коли JS вимкнено, `<noscript>` показує submit button — форма працює end-to-end.

```ruby
# layout
render Views::Shared::UI::LocaleSwitcher.new
```

Endpoint: `POST /locale` → cookie `locale=<en|uk|lv|lt>` (httponly, same_site=lax, secure-in-prod), open-redirect guard перевіряє `request.host == referer.host`, відповідь `303 See Other`. Форма йде Turbo-візитом із **явною дією `data-turbo-action="advance"`**: `data-turbo="false"` знято 2026-08-06 (UI.11 крок 3). Тут доти стояло, що обхід потрібен, «щоб `data-turbo-permanent` sidebar теж перерендерився новою мовою» — сайдбар перестав бути permanent ще кроком 1, тобто рядок пережив власну підставу на пʼять днів.

> 🔴 **Але зняти обхід «просто так» НЕ МОЖНА, і це виміряно браузером, а не виведено.** Ендпоінт редиректить на ТОЙ САМИЙ шлях, а `PageView#isPageRefresh` вимагає ПАРИ умов — той самий `pathname` **і** `visit.action === "replace"`, — тож дефолтна дія зробила б перемикання мови morph-рефрешем. Морф же `<body>` не заміняє: Stimulus не переграється, а Idiomorph зносить дітей без пари в новій розмітці, тобто **полотно Leaflet, збудоване клієнтом**. Прогін показав це дослівно: після перемикання мови `.leaflet-pane` зникав ЦІЛКОМ. `getVisitAction(submitter, formElement)` має пріоритет над дефолтом, тож `advance` вимикає морф за побудовою; ціна — зайвий запис в історії навігації. **Урок ширший за цей рядок: обхід можна знімати лише разом із вимірюванням того, що він насправді тримав — тут стара причина (permanent) справді померла, а на її місці стояла інша, жива, і плану вона не була видима.**

> 🔒 **Що саме робить перемикання мови безпечним під Turbo — виміряно в джерелі гема, не виведено.** `PageRenderer#prepareToRender` кличе `#setLanguage()`, який копіює `lang`/`dir` із НОВОГО снапшоту на `document.documentElement` (`turbo.js` 2.0.23), а `MorphingPageRenderer` успадковує це від нього. Тобто `<html lang>` їде за локаллю сторінки без жодного нашого коду — і гіпотеза «Turbo замінює лише `<body>`, тож `lang` застрягне» **хибна**. Перевіряй такі твердження джерелом: вони звучать як факт про фреймворк і тому проходять без доказу.

> **Історія еволюції (для контексту, не для повторення).** Ранні ітерації використовували `<details>`+`<summary>` + Stimulus `locale` controller (outside-click/Escape handlers), потім HTML Popover API. Popover був видалений, бо він промотує dropdown у top-layer і відриває його від нормального containing block — CSS `position: relative` на wrapper'і не може анкорити dropdown поруч з тригером без re-positioning JS (Stimulus з `getBoundingClientRect`). Це fragile (resize/scroll handlers, z-index edge cases, focus quirks) для меню з 2 опцій. Натомість нативний `<select>` — obvious correct primitive. Повний rationale-блок зафіксовано у `app/views/shared/ui/locale_switcher.rb`. Cross-ref у §15.1 (Native HTML over Stimulus) — Popover API лишається рекомендацією для майбутніх dropdown patterns, але в проекті ще не застосований.

### 12.6 Phlex `t(".key")` pattern — як додати нову локалізовану строку

```ruby
# app/views/components/wallets/show.rb
module Wallets
  class Show < ApplicationComponent
    def view_template
      h2 { t(".heading") }                          # → "wallets.show.heading"
      p  { t(".intro", balance: @wallet.balance) }  # interpolation
    end
  end
end
```

```yaml
# config/locales/wallets/en.yml
en:
  wallets:
    show:
      heading: "Wallet"
      intro: "Current balance: %{balance} SCC"
```

```yaml
# config/locales/wallets/uk.yml
uk:
  wallets:
    show:
      heading: "Гаманець"
      intro: "Поточний баланс: %{balance} SCC"
```

Cross-scope keys (потрібен ключ із сусіднього компонента) — використовуйте абсолютний `t("codex.fractions.current")`. Не вводьте `tr()` private helper — це попередній паттерн, замінений на `t(".key")` (537+ викликів у проекті vs 5 legacy `tr` визначень).

### 12.7 Pluralization

**Набір форм визначає МОВА, не ми** — CLDR-правила, а не наша домовленість. Живий
приклад у репо, `maintenance.photo_gallery.photo_count` (той самий ключ, чотири файли):

```yaml
en:  { one: "1 Photo",        other: "%{count} Photos" }        # 2 форми
lv:  { one: "1 fotogrāfija",  other: "%{count} fotogrāfijas" }  # 2 форми
lt:  { one: "1 nuotrauka",    few: "%{count} nuotraukos",       # 3 форми
       other: "%{count} nuotraukų" }
uk:  { one: "1 фото", few: "%{count} фото",                     # 4 форми
       many: "%{count} фото", other: "%{count} фото" }
```

Різна кількість форм між локалями — нормально й **не валить** гейт парності:
`i18n-tasks` знає про plural-піддерева, а `check-consistent-interpolations` дивиться
на `%{}`, не на набір ключів. Обов'язок локалі — покрити форми **своєї** мови.

> ⚠️ **Правила плюралізації приходять із `rails-i18n` (§12.2) — без нього форми
> `few`/`many` НЕДОСЯЖНІ.** Дефолтний бекенд I18n знає рівно два випадки
> (`one` для `count == 1`, `other` для решти), тож українські `few`/`many` лежать
> у YAML мертвим вантажем, а `t(count: 3)` віддає `other`. Помилка тиха: ключ
> існує, гейт парності зелений, рендериться просто не та форма. Саме так воно й
> жило до 2026-07-26 — гем був у lock-файлі, але не завантажувався.
>
> Перевірка — рантайм, не греп: `I18n.t("...", count: 3, locale: :uk)` мусить
> дати САМЕ `few`-рядок. Побічний доказ, що бекенд живий:
> `I18n.t("datetime.distance_in_words.x_minutes", count: 3, locale: :uk)` →
> `"3 хвилини"` (не `"3 хвилин"`).

### 12.8 Backend localization

Усі рядки у `app/controllers/api/v1/**/*.rb` йдуть через `I18n.t`:

| Domain | YAML файл | Приклад ключа |
|---|---|---|
| Flash messages | `flash/{en,uk}.yml` | `flash.sessions.signed_in` |
| Error JSON | `errors/{en,uk}.yml` | `errors.api.forbidden` |
| Account Security | `account_security/{en,uk}.yml` | `account_security.mfa.enabled` |
| Passwords | `passwords/{en,uk}.yml` | `passwords.reset.email_sent` |
| M2M auth | `m2m_auth/<locale>.yml` | `m2m_auth.token.issued` |
| **Заголовок сторінки** | `<domain>/<locale>.yml` | `wallets.index_title` · `trees.show_title` (інтерполяція — `%{name}`/`%{uid}`/`%{id}`) |

> 🧱 **`title:` — не «рядок десь у кутку», а ім'я сторінки.** Аргумент `render_dashboard(title:)` стає ОДРАЗУ двома речами: `<title>` вкладки (а отже й запис в історії браузера) і видимий `<h1>` (`DashboardLayout`). Тому конвенція жорстка: плоский ключ `<domain>.<action>_title` (виняток — домен `codex`, який уже має власні під-скоупи й лишається на `page_title` усередині них).
>
> 🧱 **Ім'я сторінки живе в ОДНОМУ місці — `title:` контролера.** `DashboardLayout` малює його як `h1` у верхній панелі, тож компонент, який малює власний заголовок сторінки нижче, дублює ім'я — а на сторінці з ОДНІЄЮ секцією ще й дає ДВА різні імені одного екрана. Перевірка проста: якщо `h3` компонента називає ту саму сутність, що `title:`, — його місце порожнє. Якщо називає одну з кількох секцій (`oracle_visions`) або є заголовком ФОРМИ («Register Intervention Ritual» проти «New Maintenance Ritual») — лишається, це різні речі.
>
> ⚠️ **Інтерпольований заголовок мусить лишати змінну в НАЗИВНОМУ.** У ній сидить власна назва або ID, які не відмінюються, тож рамка «Профіль %{name}» у відмінюваних мовах ламається, а «Профіль // %{name}» — ні. Усі 52 мігровані заголовки тримають змінну після роздільника (`//`, `:`, `#`) саме з цієї причини.
>
> Клас стереже `spec/i18n/controller_title_literals_spec.rb`: **жодного строкового літерала одразу після `title:`** у `app/controllers/**`. Гейта на це не мав ніхто, і не випадково — `i18n-tasks` бачить лише ІСНУЮЧІ `t()`-ключі, а сирий літерал для нього не існує взагалі; `raise_on_missing_translations` теж мовчить, бо ніхто нічого не шукає. Саме тому клас доріс до 56 сайтів у 25 контролерах непоміченим.

#### Пошта: локаль виставляється на МЕЖІ ДОСТАВКИ

🧱 **І межа ця — всередині методу мейлера, а не біля `deliver_later`.** Джоба лягає в Sidekiq, тож сам метод виконується вже там, де немає ані запиту, ані `LocaleSettable`, і `I18n.locale` дорівнює `default_locale` **завжди**. А `mail()` рендерить і subject, і тіло синхронно — отже обгортка мусить стояти навколо нього: `ApplicationMailer#in_locale_of(record)`.

**Джерело локалі — persisted-колонка, і адресатів ДВА, не один.** `users.locale` (PasswordMailer шле конкретному User) ⊥ `organizations.locale` (AlertMailer шле на `billing_email`, за яким може не стояти жоден User-запис) — це не дублювання, а різні адресати. `NULL` означає «не обрано» → базова локаль; невідома мітка мови → теж базова, **fail-safe навмисно**: `I18n.with_locale` на локалі поза каталогом кидає `InvalidLocale`, а лист не сміє загинути через мітку мови.

⚠️ **Ключі мейлера — нативна Rails-конвенція, не власна вигадка:** scope деривується зі шляху шаблону (`app/views/alert_mailer/critical_notification` → `alert_mailer.critical_notification`), а `default_i18n_subject(...)` бере `.subject` із того ж скоупу — тобто тему листа не треба будувати рядком узагалі. Щоб це бачив і гейт, `config/i18n-tasks.yml` несе `app/views` **другим** `relative_roots` (вужчий `components` — першим, інакше компонентні ключі дістали б зайвий сегмент). 🔴 До того сканер писав `Cannot resolve relative key` і **виходив з кодом 0** — помилка сканування виглядала як успішна перевірка.

🔴 **Клас, який видно лише коли прочитати лист ЦІЛКОМ.** До цієї роботи пошта була не мономовною, а **тихо двомовною**: рамка — український хардкод, а `alert_title` і `EwsAlert#message` уже ходили через `I18n.t` і в Sidekiq виходили **англійськими** всередині неї. Жоден гейт такого не бачить (кожен фрагмент окремо коректний), і жодна спека — теж: одна асертила українську тему, інша англійську мітку, обидві були зелені. Бренд-рядки (тагляйн, підпис) свідомо лишаються літералами в шаблоні — вони однакові в усіх мовах, а в YAML parity-гейт вимагав би копію в кожній локалі каталогу (§12.14).

### 12.9 Spec convention

**Базова локаль застосунку — `:en` (§12.2), тож специ рендеряться англійською без жодного хука.** Єдине, що для цього робить `spec/rails_helper.rb`, — гасить *витік*: ендпоінт `LocalesController#update` мутує `I18n.locale` глобально (thread-local), тож без скидання один POST-спек фарбував би всі наступні приклади.

```ruby
config.after { I18n.locale = I18n.default_locale }   # after, НЕ before — щоб per-example `around { I18n.with_locale(:uk) }` лишався чинним
```

Спека, що перевіряє НЕ базову локаль, обгортається в `I18n.with_locale(:uk) { … }` явно.

> ⚠️ **Назва прикладу мусить казати, що він реально пінить.** `it "… in Ukrainian by default"` з тілом `I18n.with_locale(:uk) { … }` — самосуперечність: ім'я обіцяє пін на **дефолтну поведінку**, а тіло фіксує поведінку **конкретної локалі**. Такий приклад лишиться зеленим, якщо `default_locale` завтра стане будь-чим іншим, тобто читається як сторож і ним не є. Сам дефолт пінить один рядок у `spec/requests/api/v1/locales_controller_spec.rb` — і це правильний дім для нього. (Формулювання «дефолт = `:uk`» пережило в цьому документі перемикання дефолту на `:en`; клас — той самий, що в §12.3: скопійований у прозу стан старіє мовчки.)

### 12.10 CI-гейт

`.github/workflows/ci.yml` запускає job `i18n_check`:

```bash
bundle exec i18n-tasks missing                          # ключ у одній locale, відсутній в іншій
bundle exec i18n-tasks check-consistent-interpolations  # %{var} drift між locales
bundle exec i18n-tasks check-normalized                 # YAML не у нормалізованій формі
```

Перші два → red build напряму. ⚠️ **`check-normalized` завжди виходить з нульовим кодом** (upstream-quirk), тож його гейтить грепом по виводу — exit-code там не доводить нічого ані в CI, ані локально (деталь — §12.14). Runtime safety net (test env): `config.i18n.raise_on_missing_translations = true` — будь-який spec, що проходить по missing-ключу, валить CI.

> 🔒 **Периметр i18n-гейтів як МНОЖИНА — бо поодинці кожен зелений і на своїй осі, а разом вони не покривають того, що здається покритим.** CLI-кроки вище тримають парність каталогу; решту осей тримають спеки в `spec/i18n/`, і жодна секція доти не називала їх разом: `enum_label_parity_spec` (джерело значень ⟷ базова локаль, двобічно) · `label_distinctness_spec` (мітки мусять РІЗНИТИСЬ там, де стани операційно різні — єдиний гейт, що свідомо ходить по всіх локалях) · `pluralization_gate_spec` (наявність plural-блоку; критерій звільнення англоцентричний — стеля в шапці) · `broadcast_payload_invariance_spec` (payload без локаль-залежної прози, §8.1а) · `controller_title_literals_spec` (жодного рядкового літерала після `title:`) · `locale_catalog_invariance_spec` (locale-інваріантні дані не множаться по локалях) · `i18n_tasks_config_spec` (шов «конфіг гейта ⟷ конфіг Rails») · `spec/quality/token_ticker_parity_spec` (єдиний ПОЗА `spec/i18n/`: базова мітка мусить дорівнювати назві з `ERC20("…")` — вісь «локаль ⟷ чуже джерело», а не «локаль ⟷ локаль»). Додаючи гейт на нову вісь — допиши рядок сюди, інакше наступний читач вирішить, що осей рівно стільки, скільки CLI-кроків. ⚠️ Ця сітка **не покриває Phlex** (§12.14): `ApplicationComponent#t` для абсолютних ключів кличе голий `I18n.t`, якого цей конфіг не хукає.

Конфіг: `config/i18n-tasks.yml` (base locale `:en`, scan `app/` + `lib/`, `app/javascript` + `app/assets` excluded). **Перелік локалей там не дублюється** — деривується з `available_locales` (§12.2) через Erubi, fail-closed; шов «конфіг гейта ⟷ конфіг Rails» пінить `spec/i18n/i18n_tasks_config_spec.rb`, бо поодинці обидва боки лишаються зеленими навіть розійшовшись.

#### Політика повноти: «завершені» проти «наздоганяючих» (founder 2026-07-27)

Парність — захист, поки локалей чотири, і **блокатор онбордингу**, щойно їх більше: неповний переклад робить CI червоним, тож додати мову інкрементально стає неможливо. Розділення обов'язків:

| Клас | Обов'язок | Механізм |
|---|---|---|
| **Базова** (`en`) | ключ мусить існувати завжди | вона й є еталон diff'у |
| **Завершені** (`uk`, `lv`, `lt`) | повна парність, HARD | входять у `-l`-субсет CI |
| **Наздоганяючі** (кожна нова) | нічого; fallback легальний | не входять у `-l`, але лишаються в `locales:` |

Мова переїжджає з «наздоганяючих» у «завершені» **однією правкою `-l`-списку в CI**, коли переклад дороблено. Ключ, доданий лише в наздоганяючу локаль, гейт усе одно спіймає — зворотний diff обходить усі локалі з `locales:`, а не лише субсет.

> 🔴 **«Очевидний» шлях — пастка, і вона мовчазна.** Напрошується `ignore_missing:` з per-locale хешем (у самому гемі навіть є коментар `# ignore per locale`). Але перевірка `missing` **не передає локаль** у `ignore_pattern`, тож селектор вироджується в `/\b\b/`, матчить кожен ключ і **вимикає гейт для ВСІХ локалей одразу**, лишаючись зеленим (i18n-tasks 1.1.2; per-locale scoping реально працює лише для `ignore_eq_base`). Це рідний брат маски `ignore_inconsistent_interpolations: ['*']`, яка тут уже одного разу вимкнула цілий CI-крок: **конфіг-виключення здатне зняти гейт, не лишивши жодного сліду в його виводі.** Тому субсет — на боці CLI (`-l`), де він видимий у логах білда.
>
> Поки «завершені» = усі налаштовані локалі, прапорець `-l` **не додається**: він був би незадіяною машинерією, а незадіяний гейт-шлях ніхто не перевіряє. Політика чинна як рішення, вмикається першою ж наздоганяючою мовою. Стан → [`00_07`](00_07_Action_Plan_Tracker) I18N.3.

Запуск авто-нормалізації локально:
```bash
bundle exec i18n-tasks normalize    # сортує ключі, фіксить indent
bundle exec i18n-tasks unused       # довідково: не gated у CI (false positives від dynamic keys)
```

### 12.11 Rack deprecation: `:unprocessable_entity` → `:unprocessable_content`

Усі `render status: :unprocessable_entity` замінено на `:unprocessable_content` (RFC 9110 / Rack 3.2+). Старий символ deprecation-warning'ить і буде видалений у Rack 4.0.

### 12.12 Чек-ліст для нових компонентів

- [ ] Всі user-facing strings проходять через `t(".key")` (relative-lookup), `tr()` helper не використовувати
- [ ] YAML-ключ є в **кожній** налаштованій локалі — `i18n-tasks missing` сьогодні HARD-гейт парності по всьому каталогу (§12.10). ⚠️ Саме це й робить його блокатором онбордингу нової мови; політика «завершені проти тих, що наздоганяють» — відкрите ⚖️ [`00_07`](00_07_Action_Plan_Tracker) I18N.3, доти правило вище чинне без винятків
- [ ] ARIA-label з `t(...)` (бо screen-reader читає його)
- [ ] Зарезервовані ключі не перетинаються (`:locale`, `:scope`, `:default` — не використовувати як interpolation)
- [ ] Pluralization через `t(..., count:)` + CLDR rules (UA — 4 форми, EN — 2)
- [ ] Spec покриває обидві локалі через `I18n.with_locale(:en) { ... }` / `I18n.with_locale(:uk) { ... }`

### 12.13 Backlog: що ще не локалізовано (інкрементально)

CI-гейт ловить майбутні regressions. Класи, що лишаються нелокалізованими (пооб'єктний реєстр — [`00_07`](00_07_Action_Plan_Tracker) I18N.1, тут лише класи):
- `app/views/pwa/service-worker.js` — manifest + offline сторінка JS-string'и (не через Rails I18n)
- **Сирі enum'и як видимий текст** — клас, який §12.14 закрив для `alert_type` і `severity` й лишив відкритим для решти. 🔴 **«Дротування» тут — це ДВІ роботи з різною ціною, і плаский перелік їх зливав:** частина родин **уже має повні мітки** в `ui.status.*` у всіх локалях і потребує лише перенаправлення рендер-сайтів (`Tree#status` · `Gateway#state` · `NaasContract#status` · `Actuator#state` · `Codex::Node#lifecycle_status` · `BlockchainTransaction#status`), а частина **не має жодної мітки в жодній локалі** (`MaintenanceRecord#action_type` — найбільша родина · `Actuator#device_type` · `User#role` · `AiInsight#insight_type` · `blockchain_network`), тобто це **net-new authoring ×N локалей**, і планувати його треба окремо. ✅ `BlockchainTransaction#token_type` із цього переліку **вибув** — його мітки шипнули разом із власним верхнім домом (`§12.14` ↓). Перевіряй цю тезу **per-родину**: колись вона була правдива рівно для половини.
- **Сусіди того ж дефекту, які НЕ є enum'ами — тому гейт на `Model.enum.keys` їх не бачить за визначенням:** `AuditLog#action` (вільний varchar; родини генеруються інтерполяцією ЧУЖИХ AASM-станів, тож пласка мапа вимагала б комбінаторного перебору — ліки нижче) · `Identity#provider` (`inclusion`-валідований рядок, рендериться `.titleize`) · `TreeChronicleService::Entry#event_type` (синтетичний символ сервісу, у БД його немає взагалі) · breadcrumb-сегменти (це сегменти URL, тож їхнім джерелом істини є `Rails.application.routes`, а не модель)
- **`.humanize` псує ідентифікатори** (`0xAbC123` → `0xabc123`), тож для хешів/DID/slug'ів він не «англійський фолбек», а пошкодження даних
- **Проза, записана в БД сервісом** (`resolution_notes`, `MaintenanceRecord#notes`, `*.error_message`) — не `t()`-заміна, а редизайн «ключ + параметри замість готового рядка». ✅ `EwsAlert#message` цей редизайн уже пройшов — колонки в схемі НЕМА, у БД лежать `message_key` + `message_params`, фраза збирається в момент показу, — тож він стоїть тут як **прецедент**, а не як борг
- Окремі inline UA коментарі у `.rb` файлах — не user-facing, не блокують гейт

### 12.14 Enum-мітки: контракт «модель ↔ локаль»

Значення enum'а, показане користувачеві (`alert_type`, `status`, `action_type`), — це **мітка**, і її дім — локаль-файл, а не `case` у Ruby й не `.humanize` (останній — англійський Rails-метод: він мовчки віддає англійську в усіх чотирьох локалях).

Еталон — `EwsAlert#alert_type` (дім реалізації [`04_02`](04_02_Business_Logic_and_Services), `TreeChronicle::TextFormatter`):

```ruby
ALERT_TYPE_SCOPE = "alerts.types"        # ← ОДНА деривація ключа на застосунок

def alert_title(alert)
  type = alert.alert_type.to_s
  I18n.t("#{ALERT_TYPE_SCOPE}.#{type}", default: type.humanize)   # fail-open
end
```

Викликачі (`Alerts::Row` тощо) ходять **через цей метод**, а не будують ключ самі: дві деривації означають, що друкарська помилка в одній із них лишається зеленою назавжди.

**Другий живий еталон — інша ФОРМА того самого правила: `Views::Shared::UI::StatusBadge::SCOPE` + `.label(status)`** (2026-08-05). Тут дім деривації — публічний метод класу самого КОМПОНЕНТА, а не константа сервісу, бо споживач буває двох родів: сам бейдж (мітка + колір) і поверхня, якій потрібна ЛИШЕ мітка без бейджа — рядок таблиці деталей, матриця стану актуатора, колонка лідерборду. Доти така поверхня писала `t("ui.status.#{value}")` від себе, тобто деривацій було дві. **Правило вибору форми:** константа-скоуп + метод сервісу — коли значення форматує доменний сервіс (`TextFormatter`); class-метод компонента — коли рендерер і є домом мапи, і частина викликачів хоче тільки текст. ⚠️ Обидві форми зобов'язані лишатись **fail-open** (`default:` = сире значення): новий AASM-стан мусить рендеритись ще до того, як мітка доїде в локалі.

**Скоуп належить домену МОДЕЛІ, а не компонента, який першим його показав.** Мітки `severity` спершу жили під `alerts.badge.severities` — бо `Alerts::Badge` вивів їх перший. Щойно з'явився другий викликач (`Alerts::Row`), цей шлях став брехнею про власника: значення належать `EwsAlert`, а не бейджу. Тому дім — `alerts.severities` поруч із `alerts.types`, а деривація — `TreeChronicle::TextFormatter::SEVERITY_SCOPE` + `alert_severity_label`. **Поріг простий: константа потрібна там, де викликачів ДВА і більше** — доти локальний `t(".key")` чесний і дешевший (саме тому `alerts.badge.statuses` свідомо лишився на місці: викликач один).

> ⚠️ **Сире значення enum'а, інтерпольоване в ПЕРЕКЛАДЕНЕ речення, — гірший різновид промаху, ніж просто сирий текст.** Фраза виглядає локалізованою, тож при вичитці її пропускають: `t(".threat", type: @event.alert_type)` давало «⚠ Загроза: fire_detected у Карпати-7». Той самий підвид — англійський `aria_label`, зібраний із перекладеного шаблону й сирого значення: скрін-рідер читає англійський токен усередині української фрази, а очима це не видно взагалі. Обидва випадки шукаються не по `.humanize`, а по інтерполяції атрибута моделі в `t(...)`.

**Locale-інваріантні значення (емодзі, гліфи) у YAML НЕ кладуться.** `i18n-tasks missing` — HARD-гейт парності, тож один емодзі перетворився б на по копії в **кожній** локалі каталогу, які перекладач може «виправити». Аргумент масштабується в гірший бік: чим більше локалей, тим дорожча помилка. Їхній дім — заморожена Ruby-мапа поруч зі scope-константою.

> 🔴 **Другий робочий приклад того самого правила — і він додає виток, якого емодзі не мали: інваріантне значення буває ЧУЖИМ.** `BlockchainTransaction::TOKEN_TICKERS` (`SCC`/`SFC`/`cUSD`) — теж заморожена Ruby-мапа з тієї самої причини (тікер однаковий у всіх мовах), але його **верхній дім — Solidity**: `contracts/SilkenCarbonCoin.sol` оголошує `ERC20(…, "SCC")`, `SilkenForestCoin.sol` — `"SFC"`. Тобто винісши значення з YAML, ми не отримали один дім, а створили **другий дім чужого значення**, і розходження між ними невидиме для будь-якого i18n-гейта за побудовою: обидві сторони «present», перекладати нема чого. Тримає вісь `spec/quality/token_ticker_parity_spec.rb`, і форма його варта копіювання: **перелік символів деривується з `contracts/*.sol`, а не переписується руками** (скопійований перелік членів — дзеркало, і гниє на першій зміні), плюс окремий liveness-приклад на непорожність множини, бо інакше протухлий екстрактор зробив би всі решта перевірок вакуумними.
>
> 🔴 **Продовження тієї самої осі: НАЗВА токена має той самий верхній дім, що й символ, бо `ERC20(name, symbol)` оголошує їх ОДНИМ конструктором.** Тому мітка `token_type` не є вільним authoring'ом: **базова локаль мусить дослівно дорівнювати `ERC20("…")`**, і це стереже той самий `spec/quality/token_ticker_parity_spec.rb` (обидва аргументи витягуються одним проходом — два екстрактори розійшлися б тихо). Різниця з тікером лише в тому, ДЕ живе наша копія: символ locale-інваріантний і лежить у Ruby-мапі, назва перекладається й лежить у локалях, тож гейт на неї свідомо **base-locale-only** — uk/lv/lt перекладають вільно, їхню парність тримає `i18n-tasks missing`. Дім деривації — `BlockchainTransaction::TOKEN_TYPE_LABEL_SCOPE` + `.token_type_label` (класовий метод, бо легенда реєстру рендерить мітки з `token_types.keys`, не маючи запису під рукою); повнота набору — рядок у `enum_label_parity_spec`. `cusd` — carve-out на **обох** осях, бо зовнішній Celo-токен контракту в цьому репо не має.
>
> ⚠️ **Чим це куплено (2026-08-05):** усі чотири UI-сайти підписували СУМУ транзакції зашитим рядком «SCC», тоді як `token_type` має три значення й SFC-транзакції законно потрапляють у леджер гаманця — страхова виплата бере тип із контракту (`insurance_payout_worker`), а `wallets_controller` віддає `@wallet.blockchain_transactions` **без фільтра за типом**. Тобто виплата в лісовій монеті малювалась як SCC, і поруч стояв бейдж «forest_coin» — рядок суперечив сам собі на грошовому екрані. 🔴 **Урок ширший за i18n: перш ніж перекладати сире значення, перевір, чи не бреше вже ОДИНИЦЯ поруч із ним** — переклад бейджа без цього фіксу зробив би суперечність лише читабельнішою («Лісова монета» ⟷ «SCC»), тобто приписаний порядок робіт («дай мітки сирому enum'у») був неповним у бік, що псує. Заразом знято межу, яку легко переплутати: «SCC» у балансі гаманця (`wallets/index`, `balance_display`, `metadata_frame`, `trees/show`) — **правильний** хардкод, бо `Wallet#balance` за побудовою деномінований у SCC (`wallet.rb`, `scc_balance`); дефект жив рівно там, де сума **транзакції**, чий тип змінний.

**Гейт свідомо перевіряє ЛИШЕ базову локаль — і саме тому масштабується.** Вартість перевірки не залежить від розміру каталогу локалей, а нова локаль із ще-порожнім YAML **не робить спеку червоною**: fallback-ланцюг (§12.2) віддає базову мітку, UI лишається справним. Обов'язок «мати мітку» лежить на базовій локалі, обов'язок «наздогнати переклад» — на самій локалі. Це поділ, який тримає і на чотирьох мовах, і на ста п'ятдесяти.

> ⚠️ **Чого CI тут НЕ бачить — і чому вісь тримає спека.** `i18n-tasks missing` звіряє **локаль з локаллю** і структурно сліпий до «enum виріс, YAML лишився» (саме так `alert_type` доріс до 14 значень, поки формат знав 9). `raise_on_missing_translations` (test-env) **не покриває Phlex**: `ApplicationComponent#t` для абсолютних ключів кличе голий `I18n.t`, якого цей конфіг не хукає. А `default:` глушить залишок. Тож вісь «джерело значень → базова локаль» тримають **лише спеки**, і вона двобічна: «немає мітки для значення» ⊕ «є мітка без значення». Другий бік важливіший, бо **не має симптомів** — зайвий рядок просто ніколи не читається (так `alerts.badge.severities.high` прожив у всіх чотирьох локалях, хоч `EwsAlert.severity` = low/medium/critical).
>
> Дім осі — `spec/i18n/enum_label_parity_spec.rb`: **курована мапа як tripwire**, по рядку на пару «джерело → скоуп»: `EwsAlert#alert_type`, `EwsAlert#severity`, `ActuatorCommand#status`, `StatusBadge::STYLES`. ⚠️ `EwsAlert#status` тут БІЛЬШЕ НЕМА — і це не пропуск: разом із `Alerts::Badge` (UI.4, 2026-07-27) зник єдиний UI, що показував цей стан словом, тож і скоуп для нього зник. Якщо колись зʼявиться новий такий UI, скоуп заводиться наново, і дім його — модель, не компонент. Новий user-visible enum додає рядок туди; **мертвий рядок мусить червоніти** — окрема перевірка ловить нерезолвний скоуп і порожнє джерело, інакше «0 порушень» означало б «0 перевірок». `text_formatter_parity_spec` лишається при своєму: icon-мапа + пін «резолвиться через YAML, не через `humanize`-фолбек».
>
> 🔒 Стеля обох спек названа в їхніх шапках: перевіряється **лише базова локаль** (ціна не росте з каталогом) і **лише зареєстровані пари** — enum, що рендериться сирим і скоупа не має взагалі, гейт не бачить; і жодна з них не перевіряє, що викликач ходить ЧЕРЕЗ спільну константу.
>
> ⚠️ **`I18n.exists?` у такій спеці — ОБОВ'ЯЗКОВО з `fallback: false`.** `config.i18n.fallbacks` (§12.2) діє в **усіх** середовищах, тож без прапорця порожня `lv` «існує» через `en`, і перевірка мовчки стає вакуумною на трьох локалях із чотирьох.
>
> ⚠️ **`check-normalized` завжди виходить з нульовим кодом** (upstream-quirk) — CI гейтить грепом по виводу (`ci.yml`). Локально перевіряй так само, exit-code тут нічого не доводить.

🔴 **Парність доводить, що мітки Є; ніщо не доводить, що вони РІЗНІ — і це окрема вісь, а не пропущений рядок реєстру.** `i18n-tasks missing` і `enum_label_parity_spec` питають «чи мітка існує», ніколи «чи вона відрізняється від сусідньої». Обидва ключі присутні, обидва перекладені, всі локалі узгоджені — зелено скрізь, а користувач тієї мови втрачає інформацію, яку має англомовний. Живий випадок (2026-07-27): `actuators.command_status_badge` рендерив `acknowledged` і `confirmed` ОДНИМ словом у всіх трьох неанглійських локалях, тоді як модель каже, що це різні **фізичні** стани — `acknowledge` = момент, коли дія починається (клапан відкривається, сирена вмикається), `confirm` виставляє `completed_at`. Тобто оператор українською не відрізняв «сирена виє» від «сирена замовкла».

Вісь тримає `spec/i18n/label_distinctness_spec.rb` — курована мапа наборів, які користувач бачить у тому самому місці й мусить розрізняти.

> ⚠️ **Цей гейт свідомо перевіряє ВСІ налаштовані локалі, а не лише базову** — єдиний обґрунтований виняток із правила вище. Дефект живе саме в перекладі: базова локаль тут завжди зелена (`acknowledged` ≠ `confirmed` як токени), тож base-only перевірка не знайшла б **нічого**. Ціна лишається мізерною (порівняння рядків), а нова, ще не перекладена локаль не червоніє — fallback-ланцюг віддає базові мітки, які вже різні.
>
> 🔴 **Спільний bag ламається не лише по осі ЗНАЧЕННЯ, а й по осі РОДУ — і це друга, окрема межа моделі «один мішок на всі домени».** `ui.status.active` = «активний», `dormant` = «сплячий» — чоловічий рід, правильний для шлюзу, контракту, актуатора й вузла Кодексу, і **неправильний для дерева** (середній: «активне», «спляче»). Це не помилка перекладу: ключ спільний, а узгодження — властивість пари «слово + іменник, до якого воно стоїть». Дві чесні відповіді: сутність дістає власний доменний скоуп, або приймається конвенція «мітка в колонці таблиці стоїть у нейтральній формі». **Рішення мовне, не інженерне**, і воно системне на орієнтирі 150+ локалей: у кожній мові з родом кожна нова сутність, що ділить мішок, — новий шанс на неузгодження.
>
> 🧩 **Коли значення — не enum, а згенерований композит, мітка збирається з ДІЄСЛОВА + окремо резолвленого стану.** `AuditLog#action` — вільний varchar, де три родини народжуються інтерполяцією чужих AASM-станів (`naas_contract_to_<to>`, `actuator_to_<to>`, `blockchain_tx_<event>` ⊕ `blockchain_tx_to_<state>` — форм ДВІ, і будь-яке рішення мусить тримати обидві). Пласка мапа тут вимагала б комбінаторного перебору, але перебирати нічого не треба: **`metadata` кожної з трьох родин уже несе `from`/`to` окремими полями**, тож стан беруть звідти й женуть крізь наявний `ui.status.*`, а нових ключів лишається жменя «дієслів». Прецедент рендер-половини живий і повний — `EwsAlert#message_key` + `message_params` (перевизначений READER, `I18n.t` у момент показу, fail-open).
>
> ⚠️ **Спільний `ui.status` — bag на кілька моделей, і повний його набір розрізняти НЕ зобов'язаний** (різні доми можуть законно ділити слово). Тому в реєстрі для нього стоїть ЯВНИЙ підсписок життєвого циклу команди, а не `enum.keys`. Це ж пояснює **асиметрію перекладу**, яка інакше виглядала б як недогляд: `ui.status.confirmed` належить `BlockchainTransaction` («підтверджено мережею»), тож там лишається «підтверджено», тоді як у доменному бейджі актуатора те саме слово мусить значити «завершено». Два доми, два власники, два правильні переклади.
>
> 🔒 Стеля: гейт судить лише РІЗНІСТЬ, не правильність — дві різні, але однаково хибні мітки він пропустить (це робота нативного ревʼю, `protocols/i18n/`). І знайдено цей клас **боком**, при проєктуванні дротування бейджа, а не мовним аудитом: аудит читає кожен ключ проти власної мови й ніколи не питає, від чого цей ключ мусить **відрізнятись**.

---

## 13. Mobile Drawer (Phase 2)

> Off-canvas mobile-only sidebar drawer з backdrop, scroll-lock,
> focus-trap, Escape-to-close. Сумісний з `prefers-reduced-motion`
> через motion tokens.

### 13.1 Архітектура

| Шар | Файл | Відповідальність |
|---|---|---|
| Trigger | `Views::Shared::UI::MobileNavToggle` | Бургер-кнопка `<button>` (mobile-only, `md:hidden`) |
| Drawer | `DashboardLayout#render_mobile_drawer` | `<aside role="dialog">` slide-in panel + `<div>` backdrop |
| Behaviour | `app/javascript/controllers/mobile_nav_controller.js` | open/close, scroll-lock, focus-trap, Escape, Turbo-visit close |

### 13.2 Поведінка

- **Open/close** — translate-x-full ↔ translate-x-0 (CSS transform, GPU).
- **Backdrop** — `bg-black/60` + `opacity-0 ↔ opacity-100`, fade-in.
- **Scroll-lock** — `body.style.overflow = "hidden"` поки drawer відкритий.
- **Focus management:**
  - на open → фокус на перший focusable у drawer
  - на close → фокус повертається на trigger (WCAG 2.4.3)
  - Tab/Shift+Tab закільцьовуються всередині drawer (focus-trap)
- **Escape** → close.
- **Backdrop click** → close.
- **Turbo `turbo:visit`** → close (щоб наступна сторінка не успадкувала open-state).

### 13.3 Адаптивність

| Viewport | Sidebar | Toggle |
|---|---|---|
| `< md` (mobile) | Hidden, відкривається через drawer | Visible (`md:hidden`) |
| `≥ md` (tablet+) | Static visible (`hidden md:block`) | Hidden |

Обидва — звичайний рендер. ⚠️ Тут доти стояло «Десктопний sidebar — Turbo-permanent (не перерендериться між сторінками)»: атрибут знято 2026-08-01 (UI.11 крок 1), бо він морозив у сайдбарі два серверні значення — бейдж тривог і підсвітку активного пункту. Саме розбіжність між viewport'ами (мобільний drawer рендерить ТОЙ САМИЙ компонент без атрибута й лишався свіжим) і була діагностичним сигналом.

---

## 14. Animations & Motion (Phase 3)

> Узагальнена motion-система побудована поверх токенів з § 4 (motion tokens).
> WCAG 2.3.3 / Web Vitals friendly — усі анімації автоматично вимикаються
> під `prefers-reduced-motion: reduce`.

### 14.1 Fluid base typography

`@layer base` тепер використовує `clamp()` для `<h1..h3>`, замість фіксованих
rem-розмірів. Заголовки масштабуються плавно між мобайлом і десктопом без
`@media`-сходинок. Зніжує CLS до нуля при зміні vw.

```css
h1 { font-size: clamp(1.5rem,  2.5vw + 0.75rem, 1.875rem); }
h2 { font-size: clamp(1.25rem, 1.6vw + 0.5rem,  1.5rem);   }
h3 { font-size: clamp(1.125rem, 1vw + 0.5rem,   1.25rem);  }
```

Для page-level hero-заголовків — використовуйте `text-display-*` токени
(`display-sm/md/lg`, див. § 4) явно через клас.

### 14.2 View Transitions API — знято разом із тумблером

🗄️ **Секція описувала crossfade між темами й більше не має предмета.** Її єдиним тригером був `document.startViewTransition()` усередині `theme_controller.toggle()`; після присуду 08-08 (§1) тему обирає середовище, перемикання «в один момент» не існує, і парний CSS-блок `::view-transition-*` знято з `application.css` тим самим кроком.

⚠️ Сам API не відкинуто як інструмент — просто в цьому дереві він більше нічим не викликається. Заводити його наново варто лише під конкретний DOM-перехід із названим тригером, а не «щоб було плавно».

### 14.3 `reveal_controller` (appear-on-scroll)

> **Наразі без консюмерів** — референс-патерн; жоден view не ставить `data-controller="reveal"` (§ 15.2).

Stimulus controller, який скидає `opacity-0 translate-y-2` коли елемент
вперше з'являється у viewport. One-shot (`unobserve` після першого спрацювання).

```html
<article data-controller="reveal"
         class="opacity-0 translate-y-2 transition-all
                duration-[var(--motion-slow)] ease-[var(--ease-out-soft)]">
  ...
</article>
```

Поведінка:
- **`prefers-reduced-motion: reduce`** → reveal негайно, observer не створюється
- **No IntersectionObserver** (старі браузери) → reveal негайно
- **Поріг видимості:** 15% (тюниться через `data-reveal-threshold-value`)
- **Root margin:** `0px 0px -10% 0px` — спрацьовує трохи раніше за повний enter

### 14.4 Анімаційний бюджет

| Тип | Тривалість | Easing | Приклад |
|---|---|---|---|
| Hover/focus | `--motion-fast` (150ms) | `--ease-out-soft` | LocaleSwitcher hover |
| UI transitions | `--motion-base` (220ms) | `--ease-out-soft` | Mobile drawer slide-in, theme crossfade |
| Page entrance | `--motion-slow` (320ms) | `--ease-out-soft` | `reveal_controller` |
| Micro-bounces | `--motion-base` | `--ease-spring` | Badge "new!" pop, error shake |

> Не плодьте кастомні durations / easings — використовуйте токени.

---

## 15. Native HTML over Stimulus (де доречно)

> **Filozofia:** використовуй Web Platform де він уже дозрів — це менше JS,
> менше bugs, краща a11y "з коробки", forward-compatible. Stimulus залишай
> для речей, де нативу або немає, або він ще не Baseline.

### 15.1 Що використовуємо нативно (без JS)

| Нативний API | Що дає | Замість чого | Підтримка |
|---|---|---|---|
| **HTML Popover API** (`popover="auto"`, `popovertarget`) | Outside-click close, Escape close, top-layer стек, focus restore | Рекомендований default для нових dropdown / menu / tooltip patterns; **у проекті ще не застосований** — `locale_controller` був видалений, але locale switcher використовує нативний `<select>` (top-layer detachment Popover ламав CSS anchor positioning для 2-опцій-кейсу, див. §12.5) | Baseline 2024 — Chromium 114+, Safari 17+, Firefox 125+ |
| **`<dialog>` + `.showModal()`** | Focus-trap, Escape, top-layer, `::backdrop`, inert page below, focus restore | Manual focus-trap код у `mobile_nav_controller` (~150→~25 рядків) | Baseline 2022 — всі evergreen |
| **`@starting-style` CSS** | "From"-frame для transition без JS-flush reflow | Manual rAF в JS | Baseline 2024 |
| **View Transitions API** (`document.startViewTransition`) | Smooth crossfade між DOM-станами | Manual CSS transitions на кожному елементі | Chromium 111+, Safari 18+ (graceful fallback). ⚠️ У дереві **не вживається** — єдиний консюмер пішов разом із тумблером теми (§14.2) |
| **`prefers-reduced-motion`** (CSS) | Глобально вимикає анімації | JS feature-detection у кожному компоненті | Baseline |
| **`<details>` / `<summary>`** | Disclosure pattern + keyboard | Custom accordion JS | Baseline |

### 15.2 Що залишилось у Stimulus (виправдано)

| Controller | Чому не нативно |
|---|---|
| `mobile_nav_controller` (тонкий шим) | Native `<dialog>` не закривається на backdrop-click + scroll-lock у Safari через `.showModal()` не завжди — лишаємо ~25 рядків шіма. |
| `reveal_controller` ⚠️ | CSS `animation-timeline: view()` ще НЕ Baseline (Safari/Firefox в роботі) — IntersectionObserver лишається оптимальним до ~2027. **Наразі 0 консюмерів** (`data-controller="reveal"` ніде) — scaffold-патерн задокументовано (§ 14.3), але ще не застосовано (дзеркало Popover-чесності § 15.1). |
| `clipboard_controller`, `map_controller`, `matrix_rain_controller`, `codex/*` | Інтеграція з 3rd-party / Canvas / складна логіка. |

### 15.3 Чек-ліст: коли можна **не** писати Stimulus controller

Перш ніж писати новий Stimulus controller — пройдіть цей список. Якщо
**будь-яке** "так" — спробуйте нативний шлях:

- [ ] Це dropdown / menu / tooltip → **HTML Popover API** (`popover="auto"`)
- [ ] Це modal / dialog / sheet / off-canvas drawer → **`<dialog>`** + `.showModal()`
- [ ] Це collapsible accordion → **`<details>`** з опційним `name="..."` для exclusive
- [ ] Це form submission з UI feedback → **Turbo Forms** + Turbo Stream response
- [ ] Це validation помилки → **Constraint Validation API** + `:user-invalid` CSS
- [ ] Це date/time picker → **`<input type="date">`**, **`type="time">`**
- [ ] Це color picker → **`<input type="color">`**
- [ ] Це search з autocomplete → **`<input list>` + `<datalist>`**
- [ ] Це auto-resize textarea → **`field-sizing: content`** CSS (Baseline 2024)
- [ ] Це smooth scroll / scroll-snap → **`scroll-behavior: smooth`** + `scroll-snap-*`
- [ ] Це responsive container — →  **CSS container queries** `@container`

Якщо **жодне** не підходить — Stimulus це нормальний вибір.

---

## 16. Codemod-Driven Migration (Phase 4)

> Page-component migration from raw Tailwind to gaia tokens is automated
> through a deterministic Ruby codemod. The migration is **incremental**:
> each PR migrates a domain (trees / wallets / alerts / …), the codemod
> guarantees consistent mapping, and the CI lint task prevents regressions.

### 16.1 Tooling

| Tool | Purpose |
|---|---|
| `bin/migrate-tailwind-tokens` | Word-boundary `gsub` codemod with `--dry-run` and `--report` modes. Mapping table mirrors § 3.1 (4-tier surfaces + 3-level text + primary tokens). |
| `bin/rails gaia:lint_tokens` | Compliance-перевірка — `exit 1` на сирій Tailwind-утиліті кольору; brand-glow allowlist усередині (див. джерело). **HARD-гейт у `docs.yml` з 2026-08-07**, і його периметр за замовчуванням — `app/views/shared/**`. 🔴 **Доти периметр був ІНВЕРТОВАНИЙ:** дефолт стояв на `app/views/components/`, де §3.5 сиру Tailwind явно ДОЗВОЛЯЄ, тобто сторож патрулював поверхню з м'яким правилом і на сувору не дивився взагалі — а та виявилась чистою, що й зробило гейт підключабельним без міграції. Міграційний бек-лог доменних компонентів лишається у [`00_07`](00_07_Action_Plan_Tracker) UI.1 і ганяється на вимогу через `COMPONENTS=`. |

### 16.2 Migration workflow per domain

```bash
# 1. preview
bin/migrate-tailwind-tokens --dry-run app/views/components/wallets/

# 2. apply
bin/migrate-tailwind-tokens app/views/components/wallets/

# 3. add i18n — по файлу на КОЖНУ налаштовану локаль (перелік: available_locales, §12.2).
#    Створювати підмножину = червоний `i18n-tasks missing` (§12.10).
mkdir -p config/locales/wallets
for f in config/locales/defaults/*.yml; do touch "config/locales/wallets/$(basename "$f")"; done
# … use t(".key") in each component (see § 12.6)

# 4. update specs
# базова локаль = :en, тож англійські assertions працюють без обгортки (§12.9)
# перевіряєш ІНШУ локаль — явний `I18n.with_locale(:uk) { … }`, і назви приклад по локалі, не «by default»

# 5. verify
bundle exec rspec spec/views/components/wallets/
COMPONENTS=app/views/components/wallets/ bin/rails gaia:lint_tokens
```

### 16.3 Mapping table (codemod)

| Raw Tailwind | Gaia token | Notes |
|---|---|---|
| `bg-black`, `bg-white` | `bg-gaia-surface` | Card / panel base |
| `bg-gray-50` | `bg-gaia-surface-base` | Page background |
| `bg-gray-100`, `bg-emerald-950/{10,20}` | `bg-gaia-surface-sunken` | Inset rows / hover backdrop |
| `bg-gray-900` | `bg-gaia-surface-elevated` | Modal / popover surface |
| `border-gray-200`, `border-emerald-900` | `border-gaia-border` | Default panel border |
| `border-gray-300`, `border-emerald-{700,800,900}/50` | `border-gaia-border-strong` | Hover/focus border |
| `text-gray-900`, `text-white` | `text-gaia-text-strong` | Headings, primary copy |
| `text-gray-700`, `text-emerald-400` | `text-gaia-text` | Body |
| `text-gray-{500,600}`, `text-emerald-700` | `text-gaia-text-muted` | Labels, captions |
| `text-gray-{300,400}`, `text-emerald-{800,900}` | `text-gaia-text-subtle` | Найтихіший рівень живого контенту (НЕ декорація — §3.1) |
| `text-emerald-500` | `text-gaia-primary` | Brand accent |
| `text-emerald-600` | `text-gaia-primary-hover` | Brand hover |

### 16.4 Allowlist — what stays raw on purpose

Brand-glow / decorative Tailwind utilities never go through the codemod:

- `bg-emerald-500/10`, `bg-emerald-500/20` — login submit + impedance bar fill
- `bg-emerald-500` (with `animate-ping` / `animate-pulse`) — pulse accents
- `border-emerald-500/20` (with `animate-spin`) — spinner ring

These encode brand expression, not theme intent — leave them alone.

### 16.5 i18n locale-file convention

```
config/locales/
├── defaults/      # app-shell, accessibility, theme, locale-switcher
├── components/    # cross-cutting UI components
├── navigation/    # sidebar, top bar, breadcrumb
├── sessions/      # login screen
├── dashboard/     # dashboard home
└── trees/         # tree show page
```

Each domain = one folder × two files (`uk.yml` + `en.yml`). Keep nesting
shallow (≤ 4 levels). See § 12.2 — same rules for new domains.

---

## 17. Responsive Tables — CSS-only Card Flip (Phase 5)

> Tables that work as a real `<table>` on desktop and become a stack of
> labelled cards on mobile — without JS, without dual-render, without
> losing semantics. Pattern crystallised in Phase 5 to ship `Alerts::Index`
> and `Telemetry::LiveStream` to mobile users without breaking Turbo
> Streams or screen readers.

### 17.1 Why not JavaScript?

Three options were evaluated:

| Option | Verdict |
|---|---|
| **Heavy refactor on `DataTable` shared component** with `mobile_layout:` prop | Rejected — `DataTable` is orphan (⚠️ переміряно 2026-07-27: не «один споживач, що його обходить», а **нуль викликачів**; доля → [`00_07`](00_07_Action_Plan_Tracker) UI.4). Would require rewriting Turbo-Stream wiring + bulk citation lookup. |
| **JS-driven dual-render** (Stimulus controller swaps markup) | Rejected — duplicates the source of truth, ships extra JS, breaks `prefers-reduced-motion` simplicity, fights Turbo Stream row replace. |
| **CSS-only flip via `attr(data-label)`** ✅ | Single semantic HTML, 0 JS, 0 new components, screen reader friendly, Turbo Streams keep working unchanged. |

The chosen pattern is documented in [A11Y Project — Accessible Data Tables](https://www.a11yproject.com/posts/accessible-data-tables/) and Heydon Pickering's *Inclusive Components* (Responsive Tables chapter).

### 17.2 Markup contract

```ruby
# Wrap any <table> with `gaia-responsive-table`. Mark <thead> with
# `gaia-sticky-thead` for sticky headers on desktop. Each <td> gets
# `data-label` matching its column header — that becomes the visible
# label on mobile.
table(class: "gaia-responsive-table w-full text-left font-mono", role: "table") do
  thead(class: "gaia-sticky-thead bg-gaia-surface-sunken text-gaia-text-subtle uppercase") do
    tr do
      th(scope: "col", class: "p-4") { t("table.severity") }
      # …
    end
  end
  tbody do
    @alerts.each do |alert|
      tr do
        td(class: "p-4", data_label: t("table.severity")) { severity_badge }
        # …
        # Action cells WITHOUT data_label collapse into a centred footer
        # block on mobile (no duplicate column heading).
        td(class: "p-4 text-right") { action_button }
      end
    end
  end
end
```

CSS lives in `app/assets/tailwind/application.css` § "Responsive Table Pattern".

### 17.3 What changes on mobile (`< 768px`)

- `<thead>` is **visually hidden** (clip-path), not removed — assistive tech in browse mode still sees the real table.
- Each `<tr>` becomes a bordered card (`bg-gaia-surface`, `border-gaia-border`).
- Each `<td>` becomes a flex row with `attr(data-label)` rendered via `::before` as the left-side label and the cell value on the right.
- Cells without `data-label` (action buttons) become centred footer blocks.
- The `md:min-w-[640px]` and `md:overflow-x-auto` classes on the wrapper drop the horizontal-scroll fallback on mobile so the card layout occupies full width.

### 17.4 Sticky-bottom pagination on mobile

Pair the responsive table with `Views::Shared::UI::Pagination.new(sticky_mobile: true)` to stick prev/next to the bottom of the viewport on mobile, honouring iOS notch / Android gesture bar via `env(safe-area-inset-bottom)`.

```ruby
render Views::Shared::UI::Pagination.new(
  pagy: @pagy,
  url_helper: ->(page:) { alerts_path(page: page) },
  sticky_mobile: true   # adds `gaia-pagination-sticky` CSS class
)
```

### 17.5 i18n

The mobile labels come from `data-label`, which itself is i18n'd through the standard `t("table.severity")` helper. Switch `:en` ↔ `:uk` and the card labels switch with the desktop column headers — no parallel translation surface.

---

## 18. Industry Standards (SSOT) + Per-PR Definition of Done

> Перенесено з тимчасового `docs/plans/frontend_overhaul_plan.md` (Phase 6,
> retire-plan consolidation; сам файл видалено після переїзду evergreen-знань).
> Розділ — SSOT для рев'юверів: кожен фронтенд-PR
> посилається на конкретний пункт замість винаходу власних правил.

### 18.1 Accessibility — WCAG 2.2 AA + WAI-ARIA 1.2

- **Контрастність:** мінімум 4.5:1 для тексту, 3:1 для UI-елементів та non-text — **вимога, в обох темах.** 🔴 Доти цей рядок казав «**Перевіряємо** обидві теми через Lighthouse / axe DevTools» — заява про практику, якої не існує: ані Lighthouse, ані axe у дереві немає, жодного прогону не було, і саме під цим реченням жили виміряні 1.11–1.13:1 у світлій темі. Чинний стан: вимога є, машинного вимірювача **немає** — статичним сканом він і неможливий (фактичний фон приходить від батьківського компонента або з `<body>`, §9). Доступний шлях — браузерний: cuprite уже підключений, тож пару fg/bg можна читати з `getComputedStyle` у зібраній сторінці. Черга → [`00_07`](00_07_Action_Plan_Tracker) UI.3 (axe-runner) + UI.1 (міграція тем).
- **Focus visible:** `focus-visible:ring-2 focus-visible:ring-gaia-primary` на всіх інтерактивних елементах (canon WCAG 2.4.7).
- **Reduced motion:** глобальний `@media (prefers-reduced-motion: reduce)` у `application.css` — § 14.4.
- **Semantic landmarks:** `<header role="banner">`, `<nav role="navigation">`, `<main role="main">`, `<aside>`, `<footer role="contentinfo">`.
- **ARIA patterns:** офіційний APG (Authoring Practices Guide) для menu, dialog, disclosure. `LocaleSwitcher` — нативний `<select>` з auto-submit (`onchange` → `requestSubmit`), sr-only `<label>` + `aria-label` (без Popover/Stimulus — § 12.5).
- **Keyboard nav:** Escape, Tab order, focus-trap (для drawer — забезпечується нативним `<dialog>.showModal()`, § 13.1).
- **Touch targets:** мінімум 24×24 CSS px (WCAG 2.5.8), цільовий 44×44 (Apple HIG) для primary actions.
- **Responsive tables:** `data-label` per `<td>` + `gaia-responsive-table` CSS — § 17 — зберігає семантику для AT, доступний на mobile.

### 18.2 Internationalization — Rails I18n + Unicode CLDR

- **Файлова структура** за доменом (`config/locales/<domain>/<locale>.yml`) — Rails Guide "Lazy Lookup" pattern, § 12.3.
- **Pluralization:** `t(..., count:)` + CLDR rules (UA — 4 форми: one/few/many/other; EN — one/other).
- **Інтерполяція:** ніяких зарезервованих ключів (`:locale`, `:scope`, `:default`).
- **`<html lang>`:** SEO + screen readers (W3C HTML 5.2). Виставляється у `dashboard_layout`/`auth_layout` через `I18n.locale`.
- **No hardcoded strings** у view-shared компонентах — `bin/migrate-tailwind-tokens` + `t(".key")` lazy-lookup pattern (§ 12.5).
- **Locale = `uk`, не `ua`** — ISO-639-1 (§ 12.1).

### 18.3 Security — OWASP ASVS L2 + GitHub Security

- **CSRF:** Rails default `protect_from_forgery` — `LocaleSwitcher` submit це звичайна form з authenticity token.
- **Open-redirect guard:** `LocalesController#sanitized_referer` валідує `request.host == referer.host`.
- **Cookie flags:** `httponly: true`, `same_site: :lax`, `secure: production?`.
- **CSP:** дотримуємося існуючої політики (`csp_meta_tag`); inline-стилі заборонені.
- **HSTS / X-Frame-Options:** Rails defaults.
- **Dependency scanning:** GitHub Dependabot + `bundle audit` + `gh-advisory-database` на кожен PR (DoD § 18.9).
- **Secret scanning:** GitHub native secret-scanning + push-protection (у CI).

### 18.4 Performance — Google Web Vitals + Core Performance budgets

- **LCP < 2.5 s** на 4G/Slow Mobile — fluid `clamp()` typography уникає CLS-перерозкладок при зміні vw (§ 14.1).
- **CLS < 0.1** — `Skeleton` варіанти займають той самий простір, що й контент.
- **INP < 200 ms** — Stimulus controllers без важких synchronous блоків; `matrix-rain` throttle ~16 fps (`requestAnimationFrame`).
- **Lazy-load** через Turbo Frames `loading: :lazy` для дорогих фрагментів (Wallet balance/metadata).
- **Resource hints:** `<link rel="preconnect">` для CDN тайлів Leaflet (CartoDB).
- **Bundle budget:** importmap (no bundler) — кожен Stimulus controller ≤ 5 KB gzipped (manual budget).

### 18.5 Design tokens — W3C DTCG + Material 3 + Tailwind v4

- Naming convention `--<group>-<role>-<modifier>` (наприклад `--gaia-text-strong`) — узгоджено з W3C Design Tokens Community Group draft.
- Tier-1 (raw colors) → Tier-2 (semantic tokens) — у нас лише Tier-2 (semantic), що відповідає Material 3 "system tokens".
- Surface elevation (4-tier: `base` / `surface` / `elevated` / `sunken`) — Material 3 "elevation tokens" (§ 3.1).
- SSOT для токенів — `@theme` блок у `app/assets/tailwind/application.css`. `tailwind.config.js` не існує (§ 3).

### 18.6 Code quality — Google Style Guide + GitHub Engineering

- **Convention over configuration:** Phlex namespacing віддзеркалює routes (Rails-way).
- **Small PRs / atomic commits:** Conventional Commits (`docs:`, `feat:`, `fix:`, `refactor:`, `test:`, `chore:`) — DORA "small batch size".
- **Code review:** `parallel_validation` (Code Review + CodeQL) перед merge.
- **Comments:** "explain why, not what" (Google C++ Style Guide §3.5). Уникаємо tautological comments.
- **Naming:** Ruby — `snake_case`, Phlex class — `CamelCase` з namespace, Stimulus controller — `kebab-case` файл + `camelCase` target/values.

### 18.7 DORA metrics — DevOps Research & Assessment

- **Deployment frequency:** фази → окремі PR-и (≥ 1 на фазу) — досягнуто.
- **Lead time for changes:** малий surface → швидкий review.
- **Change failure rate:** `parallel_validation` + CodeQL + повний RSpec прогін перед merge.
- **MTTR:** Sentry DSN підключено через `.kamal/secrets-common` → стек-трейси в production.

### 18.8 Rails-specific — Rails Doctrine + The Rails Way

- **Convention over Configuration:** `LocaleSettable` — concern, не базовий клас.
- **Beautiful code over the easy code:** малі methods у Phlex (`render_summary`, `render_menu`, `render_option`).
- **Optimize for programmer happiness:** Phlex API natural Ruby vs ERB strings.
- **Push complexity downwards:** `I18n.t` у view, не у controller; cookie writing у controller, не у model.

### 18.9 Per-PR Definition of Done (фронтенд-зміни)

Кожен PR із змінами у `app/views/` має у description checklist:

- [ ] WCAG AA contrast verified у обох темах (axe DevTools / Lighthouse), мінімум 4.5:1 для тексту
- [ ] Keyboard reachable — Tab + Escape, focus order логічний
- [ ] `prefers-reduced-motion` поважається (без важких decorative animations при reduce)
- [ ] `focus-visible:ring-2 focus-visible:ring-gaia-primary` на нових інтерактивних елементах
- [ ] No hardcoded EN/UK strings у `app/views/components/` чи `app/views/shared/` — `t(".key")` lazy-lookup
- [ ] Cookie flags `secure / httponly / same_site` встановлені де писали cookie
- [ ] No open-redirect — `referer` валідується проти `request.host`
- [ ] Conventional Commit message (`feat(scope):` / `fix(scope):` / `docs(scope):`)
- [ ] `bundle exec rubocop && bundle exec rspec spec/views/ spec/requests/<changed>` зелено
- [ ] `bin/rails gaia:lint_tokens` зелено (§ 16) — дефолт покриває `shared/`, а торкнуті доменні файли ганяй через `COMPONENTS=`
- [ ] `parallel_validation` (Code Review + CodeQL) пройшов або addressed

Sandbox-обмеження: автоматичний прогін axe-core / Lighthouse у CI потребує headless Chromium з мережевим доступом. Поки що це **manual gate** для рев'ювера. Коли `cuprite` тести отримають axe-runner — переведемо у автомат і відмітимо чек-бокс програмно.

### 18.10 Authoring micro-conventions (Phlex + Tailwind)

Дрібні, але обов'язкові правила написання розмітки (доповнюють §3.5 кольори / §4 типографіку / §9 a11y):

- **Без `@apply` у Phlex** — композиція класів лише Ruby (`tokens()` + приватні методи), не CSS-`@apply`.
- **`gap-*` замість `space-x/y`** у flex/grid контейнерах.
- **`grid` для 2D-розкладок, `flex` для 1D.**
- **Порядок класів:** Layout → Spacing → Type → Visual → Interactive (стабільний read/diff).
- **Довгі рядки класів** — виносити у приватні методи компонента, особливо у shared/ui (не inline-портянки).
- **SVG — `stroke="currentColor"`** (успадковує колір тексту → працює з токенами/темами).
- **`tracking-widest`** для uppercase-міток; **`leading-tight`** для заголовків.
- **`group` / `group-hover:`** для вкладених hover-взаємодій (PhotoCard, Sidebar).

