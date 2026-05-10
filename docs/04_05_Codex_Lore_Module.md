# 04_05. Codex (Шар Лору) — Філософія дизайну, ADR, відкладена робота

> **Статус (Phase 8 — Stimulus-аудит + баг-фікси + REST/CoC рефактор):** Фази 1–7 — **DONE**, живуть у коді.
> SSOT реалізації переніс у канонічні docs:
>
> | Аспект | Канонічний документ |
> |---|---|
> | DB-таблиці / моделі / enum'и / партиціювання | `04_01_Data_Models_and_Entities.md` § 7b |
> | Сервіси / воркери / призначення черг Sidekiq | `04_02_Business_Logic_and_Services.md` (підрозділи Codex) |
> | REST API `/api/v1/codex/*` (≈ 25 маршрутів) | `04_03_REST_API_v1_Reference.md` § 4 (рядки #86–#109) |
> | Phlex-компоненти / дизайн-токени / ActionCable-канали | `04_04_Phlex_UI_and_Tailwind.md` § 6.4 + § 8.1 |
> | Seed-дані | `db/seeds/codex/*.rb` + `lib/seeds/codex/*.yml` |
>
> Тут залишається **тільки** те, чого *ще немає* в коді: філософія дизайну
> (щоб майбутні мейнтейнери розуміли *чому* схема виглядає саме так),
> реєстр формальних ADR, та відкладена робота Phase 6+.

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

---

## 2. Architecture Decision Records (ADR-CDX-1 … ADR-CDX-7)

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
`p, h2, h3, h4, ul, ol, li, strong, em, blockquote, code, pre, a[href]`.
Жорсткі ліміти довжини в моделі: `body_md_*` ≤ 8 КіБ,
`subtitle_*` ≤ 2 КіБ. Сирий HTML ніколи не потрапляє в DOM.

### ADR-CDX-6 — Партиціювання тільки `codex_matches`

`codex_nodes` обмежено ~10K рядків (DAO governance) → без партицій.
`codex_matches` партиціюється RANGE по `created_at` (Battle Arena — write-heavy
поверхня, очікується 100M+ рядків). `PartitionMaintenanceWorker` відповідає
за щомісячні партиції — див. `04_02` § DOC.11.

### ADR-CDX-7 — Discovery gated by presence, fail-open

`Codex::DiscoveryProbeWorker.perform_async` викликається з трьох місць:
`EloRecomputeWorker` (milestone матчу), `FractionChangeService` (вибір фракції),
`AttunementsController#create` (streak attunement). Усі три —
**fail-open**: збій enqueue у Sidekiq НЕ ПОВИНЕН відкочувати user-facing операцію.
Результати probe читаються через `Codex::PresenceTracker` (Redis Set TTL 10 хв),
тому воркер розсилає тільки онлайн-користувачам — це тримає Discovery
O(active_users), не O(all_users).

---

## 3. Відкрита робота (Phase 6+ — ще не в коді)

> Пункти з `[ ]` — **відкладені** навмисно — не блокують merge Codex-модуля,
> але трекаються тут, щоб не загубилися.

### 3.1 Phase 6 — Stimulus + onboarding (фронтенд полірування)

**Аудит Stimulus (Phase 8):** проведено повний аналіз чи кожен контролер
виправданий. Результат:

- [x] **`codex--reveal`** — ✅ залишений. Авто-dismiss тоста через 8 с + пауза
  на hover. Без JS тост залишається назавжди — це broken UX.
  Файл: `app/javascript/controllers/codex/reveal_controller.js`.
- [x] **`codex--comment`** — ✅ залишений. Cmd/Ctrl+Enter submit + scroll-to-new +
  reset textarea. Індустріальний стандарт (Slack/GitHub/Linear).
  Файл: `app/javascript/controllers/codex/comment_controller.js`.
- [x] **`codex--attune`** — ❌ видалений. Turbo Stream broadcast від
  `AttunementBroadcastWorker` оновлює лічильник за <100мс. Optimistic UI =
  over-engineering + bug surface (race conditions, код з помилкою
  `method = "post" : "post"`). `data-controller` знятий з `Toggle`.
- [x] **`codex--fraction-picker`** — ❌ видалений. Замінений на нативний
  `data-turbo-confirm="..."` на кнопці Pick — 1 атрибут замість 64 рядків JS.
  Серверна cooldown-валідація залишається авторитетною.
- [x] **`codex--battle`** — ❌ видалений (deferred). Keyboard-шорткати (←/→/space)
  без видимої підказки = discoverability fail. Повернути коли буде tooltip/legend.
- [x] **"Choose your Fraction" onboarding wizard** — рендериться як банер у
  `DashboardLayout` (`Codex::Fractions::OnboardingWizard`) для будь-якого
  юзера з `organization_id` і без `codex_fraction`. Server-only; натискання
  CTA виконує нативну Turbo-Drive навігацію на
  `GET /api/v1/codex/fractions/picker` — без нового Stimulus-контролера
  (узгоджено з результатами Phase-8 audit вище). Layout-хук обгорнутий у
  `rescue StandardError` згідно з ADR-CDX-7 fail-open: збій рендеру
  Codex-шару НІКОЛИ не валить дашборд (помилка лишається у Rails logger
  для подальшого Sentry-звіту, не «глитається» тихо).

### 3.2 Wiki + README

- [x] Додано **"Lore Layer (Codex)"** one-liner до `README.md` (під
  Proof of Growth Pipeline, з прямим лінком на цей документ).
- [x] Оновлено `docs/00_00_SSOT_Index.md` — Модуль 04 тепер містить
  явне посилання на `04_05_Codex_Lore_Module`. Sidebar GitHub Wiki
  оновлюється з тієї ж SSOT-сторінки.

### 3.3 Sidekiq Pro (cross-cuts весь проєкт)

Codex використовує `Sidekiq::Batch` callbacks там, де сьогодні
`config/initializers/sidekiq_pro.rb` shim робить `on(:success)` no-op.
Це ОК для Phase 1–8 (жоден Codex-шлях не залежить від Batch callback —
`AttunementBroadcastWorker`, `FractionAuditWorker`,
`DiscoveryProbeWorker`, `EloRecomputeWorker` усі fire-and-forget),
але інші воркери моноліту вже **активно використовують** Pro-фічі
(`Sidekiq::Batch` у `InsightGeneratorOrchestratorWorker` /
`TokenomicsEvaluatorWorker`, `Sidekiq::Limiter` для web3-RPC, `expires_in:`
TTL у hot-path uplink). Це проєктне рішення, не бюджетне:
ліцензія `sidekiq-pro` додається у Gemfile + `BUNDLE_GEMS__CONTRIBSYS__COM`
як частина production hardening (повний чекліст у `04_02` § DOC.10:
розщеплення на 4 процеси, `super_fetch`, `reliable_push`, Redis pool +5).
Codex-фази не блокують це — просто отримають `on(:success)` коли він
з'явиться. Multi-step Battle settlement (наступна ітерація Codex поза
TRL 8) **буде** вимагати справжнього Batch callback — тоді й слід
ув'язати Codex-merge із production hardening треком.

### 3.4 Майбутнє бачення (не заплановано)

- **Federated Codex** — інші гільдії лісників можуть підключати свої Realm'и
  через підписані маніфести (peaq DID-based attestation).
- **Культурний state-root anchor** — включити топ-100 найбільш цитованих nodes
  у тижневий Ethereum L1 anchor (`05_04`), даючи Codex on-chain finality.
  Відкладено за межі TRL 8.

---

## 4. Quality Gates (мають залишатися зеленими)

| Gate | Де | Власник |
|---|---|---|
| 300+ Codex specs (`spec/{models,services,policies,requests/api/v1,views/components,workers,blueprints}/codex/**`) | `bundle exec rspec` | Автор фази |
| `bundle exec rubocop` 0 offenses на `app/**/codex/**`, `spec/**/codex/**` | CI | Автор фази |
| Brakeman 0 warnings на `app/controllers/api/v1/codex/**` (`citable_type` allow-list у `Codex::CitationsController::CITABLE_CLASS_MAP`) | CI | Автор фази |
| `Codex::Citation.bulk_for(targets)` використано в кожному collection view, що рендерить strip (без per-row N+1) | Code review | Автор фази |
| Усі shared Codex Phlex-компоненти використовують тільки `gaia-*` / `status-*` токени — без `bg-white` / `text-gray-*` / `bg-emerald-*` | Code review | Автор фази |

---

## 5. Трекер (компактний)

| Фаза | Статус | Кількість спеків | Нотатки |
|---|---|---|---|
| 1 — Foundation 🌱 (Realms, Nodes, atlas read-only) | ✅ done | ~95 | seeds: 4 realms + 79 nodes |
| 2 — Community 💬 (Comments, Attunements) | ✅ done | ~85 | soft-hide модерація |
| 3 — Identity 🛡 (Fractions, Picker, ProfileBadge) | ✅ done | ~70 | 7-денний cooldown |
| 4 — Battle ⚔ (Pair selector, Vote recorder, Elo) | ✅ done | ~80 | `codex_matches` RANGE-partitioned |
| 5 — Discovery 🔓 (Engine + 5 адаптерів + Presence) | ✅ done | ~75 | DAO-tunable правила |
| 6 — Cross-domain stitch 🪡 (Citations, Admin CRUD, +3 адаптери) | ✅ done | ~45 | Stimulus: 2 залишено, 3 видалено (§ 3.1) |
| 7 — PR cleanup pass | ✅ done | — | migration squash, N+1 fix, citation `polymorphic_type_for` |
| 8 — Stimulus-аудит + баг-фікси | ✅ done | — | EloMath `\|\|`, Redis GETDEL, PII, TOCTOU fraction, nil-safe audit |
| 8a — REST/CoC рефактор | ✅ done | — | `BattleController` → `MatchesController#new/#create`; `destroy_me` → `destroy`; `me` → `index`/`show`; Phlex `Codex::Battle::Arena` UI-назва лишилась |
| 8b — Onboarding wizard + Wiki/README | ✅ done | +6 (`Codex::Fractions::OnboardingWizard`) | First-login банер у `DashboardLayout`, Lore Layer one-liner у `README.md`, `04_05` посилання у `00_00_SSOT_Index.md` (Модуль 04) |

> Історія посесійних ADR-нотаток для Phases 1–6 зберігається в git log
> `docs/04_05_Codex_Lore_Module.md` (`git log -p --follow`) та в merged PR.
> Дублювати тут — означає дублювати `04_01..04_04`.
