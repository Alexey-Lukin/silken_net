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
> `Codex::NodeImportService` ([`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) §10b).

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Навіщо існує Шар Лору](#1-навіщо-існує-шар-лору)
- [2. Architecture Decision Records (ADR-CDX-1 … ADR-CDX-10)](#2-architecture-decision-records-adr-cdx-1--adr-cdx-10)
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

## 2. Architecture Decision Records (ADR-CDX-1 … ADR-CDX-10)

Це несучі рішення. Будь-хто, хто чіпає `codex_*`, МУСИТЬ прочитати їх
перед зміною схеми або призначення черг.

### ADR-CDX-1 — `bigint` PK

Таблиці `codex_*` використовують `bigserial` PK (консистентно з рештою моноліту;
`uuid` зарезервований для зовнішніх ідентифікаторів типу `idempotency_token`).
Людино-читабельний ідентифікатор — `codex_uid` (`CDX-XXX-####`), обчислюється з
`(realm_short_code, slug_hash)`; це *не* PK.

### ADR-CDX-2 — Без STI, Realm'и — це рядки таблиці

`Codex::Realm` — це таблиця (4 рядки seed). `Codex::Node` тримає `realm_id +
archetype_key` замість наслідування. Додавання 5-го realm'у
(`space`, `myco`, …) — це DAO-пропозиція + INSERT, не деплой.

### ADR-CDX-3 — Двомовність без i18n-гему

`title_uk/_en`, `subtitle_uk/_en`, `body_md_uk/_en` — нативні колонки.
Обґрунтування: українська + англійська — це SSOT-мови, додаткові локалі
не заплановані, і ми економимо один JOIN + одну залежність від гему. Якщо
з'явиться третя мова — мігрувати додаванням колонок; **не** ретрофітити `globalize`.

### ADR-CDX-4 — Codex ніколи не чіпає гарячий шлях

Жоден Codex-воркер не працює в чергах `uplink (#1)`, `alerts (#2)`, `critical (#3)`,
`downlink (#4)`, або `web3_critical (#6)`. Дозволені черги:

| Воркер | Черга |
|---|---|
| `Codex::AttunementBroadcastWorker` | `default (#5)` |
| `Codex::FractionAuditWorker` | `default (#5)` |
| `Codex::DiscoveryProbeWorker` | `default (#5)` |
| `Codex::EloRecomputeWorker` | `low (#9)` |

Правило: **гейміфікація не може голодувати телеметрію дерева**. Якщо Codex-фічі
колись знадобиться швидша черга — це тригерить новий ADR.

### ADR-CDX-5 — Санітизація Markdown

`*_md` колонки рендеряться на сервері через `Codex::MarkdownRenderer`
(Rails `Rails::HTML5::SafeListSanitizer`) з allow-list:
`p, h2, h3, h4, ul, ol, li, strong, em, blockquote, code, pre, a[href], br`.
Жорсткі ліміти довжини в моделі: `body_md_*` ≤ 8 КіБ,
`subtitle_*` ≤ 2 КіБ. Сирий HTML ніколи не потрапляє в DOM.

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

- `codex--attune` → лічильник оновлює Turbo Stream broadcast
  (`AttunementBroadcastWorker`, target `codex_node_<id>_attunement_count`).
- `codex--fraction-picker` → нативний `data-turbo-confirm`; cooldown-валідація
  лишається серверною й авторитетною.
- `codex--battle` → **відкладено** до появи видимої клавіатурної легенди
  (шорткати без підказки = discoverability-fail; arena працює і без них — §3).

Правило: Stimulus-контролер мусить *заробити* місце UX-ом, недосяжним для сервера.
Дзеркало рішення `codex--attune` — [`04_04`](04_04_Phlex_UI_and_Tailwind) §6.4.

### ADR-CDX-9 — Allow-list поліморфної цілі цитати

`Codex::Citation#citable_type` НЕ резолвиться вільним `constantize` з params — лише
через явний `Codex::CitationsController::CITABLE_CLASS_MAP` allow-list
(Tree / Cluster / Alert / Wallet / …). Тип поза мапою → 422, ніколи не торкається
ORM. Це закриває object-injection / arbitrary-class-lookup вектор (Brakeman-clean)
і робить набір citable-моделей **свідомим** рішенням, а не наслідком user-input.

### ADR-CDX-10 — Codex терпить Sidekiq Pro shim (fire-and-forget воркери)

Усі чотири Codex-воркери (`AttunementBroadcast`, `FractionAudit`, `DiscoveryProbe`,
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

---

## 3. Майбутні напрями (поза TRL 8, не заплановані)

> Це **design vision**, а не tracked backlog — тому без запису в
> [`00_07`](00_07_Action_Plan_Tracker). Git-історія тримає посесійні нотатки
> реалізації Phase 1–8 (`git log -p --follow`); дублювати їх тут = дублювати
> `04_01..04_04`.

- **Federated Codex** — інші гільдії лісників підключають власні Realm'и через
  підписані маніфести (peaq DID attestation).
- **Cultural state-root anchor** — топ-N найцитованіших nodes у тижневий Ethereum L1
  anchor ([`05_04`](05_04_Ethereum_L1_State_Anchor)) → on-chain finality для Codex.
- **`codex--battle` re-enable** — повернути keyboard-шорткати Battle Arena, щойно
  з'явиться видима легенда/tooltip (ADR-CDX-8).
- **Multi-step Battle settlement** — наступна ітерація Battle Arena поза TRL 8;
  саме вона зв'яже Codex із Sidekiq-Pro hardening треком (ADR-CDX-10).
