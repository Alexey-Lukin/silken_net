# 04_05: Codex (Шар Лору) — Філософія дизайну та ADR

## 🎯 Мета

Зберегти **філософію дизайну** та формальний **реєстр архітектурних рішень (ADR)**
Codex Lore Layer — пояснити *чому* схема, черги й межі безпеки виглядають саме так
(для майбутніх мейнтейнерів, партнерів та ШІ-агентів). Реалізація («як воно є» —
моделі, сервіси, API, UI) живе у канонічних домах Модуля 04 і **реферується**
звідси, а не дублюється.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Codex повністю реалізований і живе у коді; доми
  реалізації (моделі / сервіси / API / UI) — у 🔗 Cross-references нижче.
  Відкритих блокерів немає.
- Майбутні напрями (поза TRL 8, **не заплановані**) — §3; це design vision, а не
  tracked backlog, тому **без** запису в [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | DB-таблиці / моделі / enum / партиціювання (§7b) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Сервіси / воркери / призначення черг Sidekiq (§10b) |
| [`04_03` — REST API v1 Reference](04_03_REST_API_v1_Reference) | REST API `/api/v1/codex/*` (§4, таблиця ендпоінтів) |
| [`04_04` — Phlex UI and Tailwind](04_04_Phlex_UI_and_Tailwind) | Phlex-компоненти / дизайн-токени (§6.4) · Turbo/ActionCable (§8.1) |
| [`05_04` — Ethereum L1 State Anchor](05_04_Ethereum_L1_State_Anchor) | Cultural state-root anchor — майбутній напрям (§3) |

> **One-Home.** Реалізація Codex («як воно є» — моделі, сервіси, API, UI) живе у
> домах Модуля 04 вище; цей документ тримає **тільки** *чому*: філософію (§1) та
> ADR (§2). Seed-корпус (4 Realm + Node) — `db/seeds/codex/` (`realms.yml` ·
> `discovery_rules.yml` · `nodes/`), ідемпотентний імпорт через
> `Codex::NodeImportService` ([`04_02 §10b`](04_02_Business_Logic_and_Services)).

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Навіщо існує Шар Лору](#1-навіщо-існує-шар-лору)
- [2. Architecture Decision Records (ADR-CDX-1 … ADR-CDX-11)](#2-architecture-decision-records-adr-cdx-1--adr-cdx-11)
- [3. Майбутні напрями (поза TRL 8, не заплановані)](#3-майбутні-напрями-поза-trl-8-не-заплановані)
<!-- TOC:AUTO:END -->

---

## 1. Навіщо існує Шар Лору

Codex перетворює операційний стек телеметрії (Tree → Cluster → Alert → Wallet)
на **наративний субстрат**. Кожне Дерево лісника прив'язане до одного чи
кількох **архетипів** (`Codex::Node`, наприклад `cold_wallet`, `relict_oracle`,
`chainsaw_protocol`) через поліморфний `Codex::Citation`. Результат двосторонній:

- **Лор → Операції:** `mythical` Node підсвічує бейдж Cluster у UI;
  лісник, який цитує `chainsaw_protocol` на `chainsaw_detected` алерті,
  перетворює рядок на аудитовані, лор-пов'язані форензик-дані.
- **Операції → Лор:** Кожен uplink, кожен матч, кожен вибір фракції може
  відкрити `Codex::Discovery` для користувача — гейміфікує нудну середину
  довгих вікон спостереження. Правила discovery зберігаються в
  `codex_discovery_rules`, тому **DAO може додавати нові правила без редеплою**.

Чотири Realm'и (`ecosystem | unique_tree | protocol | mythos`) — це **дані, не
код** — див. ADR-CDX-2.

> **N+1-інваріант.** Кожен collection-view, що рендерить citation-strip, вантажить
> цитати через `Codex::Citation.bulk_for(targets)` — один запит на сторінку, ніколи
> не per-row. Це контракт API цитат, а не оптимізація навздогін.

---

## 2. Architecture Decision Records (ADR-CDX-1 … ADR-CDX-11)

Це несучі рішення. Будь-хто, хто чіпає `codex_*`, МУСИТЬ прочитати їх
перед зміною схеми або призначення черг.

### ADR-CDX-1 — `bigint` PK

Таблиці `codex_*` використовують `bigserial` PK (консистентно з рештою моноліту;
`uuid` зарезервований для зовнішніх ідентифікаторів типу `idempotency_token`).
Людино-читабельний ідентифікатор — `codex_uid` (`CDX-{ECO|TRE|PRT|MYT}-####`,
`Codex::Node::CODEX_UID_FORMAT`); це *не* PK. Значення виписане вручну в seed-YAML
(послідовний лічильник за realm-префіксом), `NodeImportService` лише пропускає його
through — жодної hash-функції з `realm_short_code` не існує (`Codex::Realm` не має
колонки `short_code`).

### ADR-CDX-2 — Без STI, Realm'и — це рядки таблиці

`Codex::Realm` — це таблиця (4 рядки seed). `Codex::Node` тримає `realm_id +
archetype_key` замість наслідування. Додавання 5-го realm'у
(`space`, `myco`, …) — це DAO-пропозиція + INSERT, не деплой.

### ADR-CDX-3 — Двомовність без i18n-гему

`title_uk/_en`, `subtitle_uk/_en` — двомовні нативні колонки; лор-тіло
(`context_md`, `cyber_meaning_md`, `lore_md`) монолінгвальне.
Обґрунтування: українська + англійська — це SSOT-мови, додаткові локалі
не заплановані, і ми економимо один JOIN + одну залежність від гему. Якщо
з'явиться третя мова — мігрувати додаванням колонок; **не** ретрофітити `globalize`.

### ADR-CDX-4 — Codex ніколи не чіпає гарячий шлях

Жоден Codex-воркер не працює в чергах `uplink (#1)`, `alerts (#2)`, `critical (#3)`,
`downlink (#4)`, або `web3_critical (#6)`. Дозволені черги:

| Воркер | Черга |
|---|---|
| `Codex::FractionAuditWorker` | `default (#5)` |
| `Codex::DiscoveryProbeWorker` | `default (#5)` |
| `Codex::EloRecomputeWorker` | `low (#9)` |

Правило: **гейміфікація не може голодувати телеметрію дерева**. Якщо Codex-фічі
колись знадобиться швидша черга — це тригерить новий ADR.

### ADR-CDX-5 — Санітизація Markdown

`*_md` колонки рендеряться на сервері через `Codex::MarkdownRenderer`
(Rails `Rails::HTML5::SafeListSanitizer`) з allow-list:
`p, h2, h3, h4, ul, ol, li, strong, em, blockquote, code, pre, a[href], br`.
Жорсткі ліміти довжини в моделі: `context_md`/`cyber_meaning_md` ≤ 8 КіБ,
`lore_md` ≤ 16 КіБ, `subtitle_*` ≤ 200 символів. Сирий HTML ніколи не потрапляє в DOM.

### ADR-CDX-6 — Партиціювання тільки `codex_matches`

`codex_nodes` обмежено ~10K рядків (DAO governance) → без партицій.
`codex_matches` партиціюється RANGE по `created_at` (Battle Arena — write-heavy
поверхня, очікується 100M+ рядків). `PartitionMaintenanceWorker` відповідає
за щомісячні партиції — див. [`04_02`](04_02_Business_Logic_and_Services) DOC-R.11.

### ADR-CDX-7 — Discovery gated by presence, fail-open

`Codex::DiscoveryProbeWorker.perform_async` викликається з трьох місць:
`EloRecomputeWorker` (milestone матчу), `FractionChangeService` (вибір фракції),
`AttunementsController#create` (streak attunement). Усі три —
**fail-open**: збій enqueue у Sidekiq НЕ ПОВИНЕН відкочувати user-facing операцію.
Результати probe читаються через `Codex::PresenceTracker` (Redis Set TTL 10 хв),
тому воркер розсилає тільки онлайн-користувачам — це тримає Discovery
O(active_users), не O(all_users).

### ADR-CDX-8 — Stimulus-мінімалізм (Turbo-first)

Codex-UI тримає рівно **два** Stimulus-контролери, кожен дає UX, якого сервер дати
не може:

- `codex--reveal` — авто-dismiss Discovery-тоста через 8 с + пауза на hover (без JS
  тост висить вічно).
- `codex--comment` — Cmd/Ctrl+Enter submit + scroll-to-new + reset textarea
  (індустріальний стандарт Slack/GitHub/Linear).

Решту кандидатів **прибрано на користь Turbo/HTML** — optimistic-UI лише дублював
авторитетний серверний стан і додавав поверхню для багів (race conditions):

- ~~`codex--attune`~~ → 🔴 **це рішення виявилось помилковим і 2026-07-27 скасоване.**
  ADR стверджував, що лічильник оновлює «Turbo Stream broadcast» — насправді
  `AttunementBroadcastWorker` слав СИРИЙ `ActionCable.server.broadcast`, не Turbo;
  підписника не існувало ніколи; і навіть названий тут топік був не той
  (`…_attunement_count` — це DOM-id, а канал звався `…_attunements`). Тобто
  optimistic-UI прибрали на користь механізму, якого не було. Воркер знято разом
  з усім сирим ActionCable (SEC: `/cable` монтується движком сам, тож канал без
  авторизації підписки = латентний крос-тенантний IDOR). **Урок ADR-рівня:
  «прибрано на користь X» вимагає доказу, що X працює, а не що X заплановано.**
  Лічильник зараз приходить із контролера в момент рендеру; хочемо живий —
  спершу підписаний Turbo-стрім.
- `codex--fraction-picker` → нативний `data-turbo-confirm`; cooldown-валідація
  лишається серверною й авторитетною.
- `codex--battle` → **відкладено** до появи видимої клавіатурної легенди
  (шорткати без підказки = discoverability-fail; arena працює і без них — §3).

Правило: Stimulus-контролер мусить *заробити* місце UX-ом, недосяжним для сервера.
Дзеркало рішення `codex--attune` — [`04_04 §6.4`](04_04_Phlex_UI_and_Tailwind).

### ADR-CDX-9 — Allow-list поліморфної цілі цитати

`Codex::Citation#citable_type` НЕ резолвиться вільним `constantize` з params — лише
через явний `Codex::CitationsController::CITABLE_CLASS_MAP` allow-list
(джерело істини = `Codex::Citation::ALLOWED_CITABLE_TYPES`: Tree / Cluster / AiInsight /
EwsAlert / OracleVision / NaasContract). Тип поза мапою → **400**, ніколи не торкається
ORM. Це закриває object-injection / arbitrary-class-lookup вектор (Brakeman-clean)
і робить набір citable-моделей **свідомим** рішенням, а не наслідком user-input.

⚠️ **Цей ADR захищає КЛАС цілі, і рівно тому довго читався як повний.** Про скоуп
самого ЗАПИСУ він не казав нічого — і поверхня півтора місяця приймала чужий
`citable_id`. Інваріант тенант-ізоляції цитати живе в сусідньому **ADR-CDX-11**;
розділяй ці два питання, бо allow-list на них не відповідає.

### ADR-CDX-10 — Codex терпить Sidekiq Pro shim (fire-and-forget воркери)

Усі три Codex-воркери (`FractionAudit`, `DiscoveryProbe`,
`EloRecompute`) — **fire-and-forget**: жоден не залежить від `Sidekiq::Batch`
`on(:success)` callback. Тому Codex **байдужий** до того, що `sidekiq-pro` поки не в
Gemfile, а `config/initializers/sidekiq_pro.rb` робить `on(:success)` no-op — Codex
мерджиться **незалежно** від production-hardening треку. Сам cross-cutting стан Pro
(інші воркери моноліту вже використовують `Sidekiq::Batch` / `Limiter` / `expires_in:`;
ліцензія + 4-process split + `super_fetch` / `reliable_push` + Redis pool) живе в
[`04_02`](04_02_Business_Logic_and_Services) DOC-R.10 — звідси лише реф, без дублю.

**Межа:** перша Codex-фіча, що зламає це припущення — **multi-step Battle settlement**
(наступна ітерація поза TRL 8): вона **вимагатиме** справжнього Batch `on(:success)`.
Саме тоді — і не раніше — Codex-merge слід ув'язати з Pro-hardening треком (DOC-R.10).

### ADR-CDX-11 — Цитата org-скоуплена, хоч лор глобальний [SEC.26]

Лор **читається** глобально (ADR-CDX-2), але цитата — не читання: вона **пише в
операційний простір** і проступає на дашборді власника цілі (`Clusters::Show`,
`Trees::Show`, `Alerts::Row`, `OracleVisions::ForecastCard` рендерять
`Citation.for_target`). Тому `Codex::CitationsController` — **єдиний** codex-контролер,
що читає `acting_organization!`, і це не виняток із правила, а наслідок того, що
організація тут визначається **дією**, а не шаром.

**Форма (`create`):** `CITABLE_CLASS_MAP` віддає не клас, а вже **org-скоуплений
relation** (`org.trees` · `org.clusters` · `org.ews_alerts` · `org.naas_contracts` ·
`AiInsight.for_organization`). Скоуп живе в САМІЙ мапі, а не окремою перевіркою після
`find` — інакше «не існує» і «чуже» дали б різні коди, тобто ендпоінт лишався б
**existence-оракулом** по всій платформі навіть із закритим записом.

**Форма (`destroy`) — вісь АВТОР, а не ціль,** і це не симетрія заради симетрії:
`citable` поліморфний і FK-каскаду не має, тож ціль може бути вже знищена. Скоуп по
цілі зробив би осиротілу цитату **невидалимою назавжди** — тобто вдарив би по
чесному власнику, лишивши атакера недоторканим. `created_by_user_id` — `NOT NULL`,
тож вісь автора визначена завжди, а після скоупу `create` обидві осі збігаються.
Гард стоїть **перед** `authorize` (404, не 403 — та сама причина, що вище).

**Чому це не забирає модерацію:** сусідній `Codex::CommentPolicy` уже зафіксував, що
глобальне втручання в чужий лор — це `hide?`, **ніколи** `destroy`. У цитат
прихованого стану немає, тож глобального дієслова тут просто нема чого успадковувати.

**Одна названа стеля.** **Читання не фільтрує** — `for_target`/`bulk_for` не несуть
org-умови й тримаються на тому, що ціль уже скоупив контролер вище; після закриття
запису живого вектора немає, але додавання нової поверхні рендеру цю передумову
успадковує мовчки.

⚠️ **Друга стеля ЗНЯТА присудом ⚖️ 2026-07-30** — тут стояло, що
`TreePolicy::Scope`/`EwsAlertPolicy::Scope` кажуть протилежне (`OR cluster_id IS NULL`
= «сирота видимий КОЖНІЙ організації») і що дві семантики співіснують. Більше не
співіснують: осиротілий вузол не має екстенсіоналу (заведення вимагає кластер
криптографічно — без нього не деривується `K_ota`), `Cluster has_many :trees` став
`restrict_with_error`, а `OR ... IS NULL` знято з усіх чотирьох політик. Семантика
одна: **безкластерний запис не належить нікому**. Розбір і підстава —
[`00_07`](00_07_Action_Plan_Tracker) SEC.26 + ARCH.76.

---

## 3. Майбутні напрями (поза TRL 8, не заплановані)

> Це **design vision**, а не tracked backlog — тому без запису в
> [`00_07`](00_07_Action_Plan_Tracker). Git-історія тримає посесійні нотатки
> реалізації Phase 1–8 (`git log -p --follow`); дублювати їх тут = дублювати
> `04_01..04_04`.

- **Federated Codex** — інші гільдії лісників підключають власні Realm'и через
  підписані маніфести (peaq DID attestation).
- **Forester-Guild economic-layer ↔ Codex** — `Codex::Citation` (`chainsaw_protocol`/vandalism
  на `EwsAlert`) як cause-forensic overlay для Field-Audit (вхід C→A класифікації);
  `Codex::DiscoveryRule` (DAO-editable `condition_type`) гейміфікує bond/reputation-шлях
  форестера. **ADR-CDX-4: overlay, НЕ control** — slashing-guard лишається операційним,
  Codex його лише документує. Дизайн → [`04_02 §Forester Guild`](04_02_Business_Logic_and_Services)
  (BIZ.13/SLASH-1).
- **Cultural state-root anchor** — топ-N найцитованіших nodes у тижневий Ethereum L1
  anchor ([`05_04`](05_04_Ethereum_L1_State_Anchor)) → on-chain finality для Codex.
- **`codex--battle` re-enable** — повернути keyboard-шорткати Battle Arena, щойно
  з'явиться видима легенда/tooltip (ADR-CDX-8).
- **Multi-step Battle settlement** — наступна ітерація Battle Arena поза TRL 8;
  саме вона зв'яже Codex із Sidekiq-Pro hardening треком (ADR-CDX-10).
