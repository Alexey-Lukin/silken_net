# 04_05: Codex — Модуль Lore (Кодекс Архетипів)

## 🎯 Мета

Зафіксувати повну специфікацію модуля **Codex** — Lore-шару Gaia 2.0, що перетворює технічну платформу на культурно-міфологічний рух. Codex є SSOT всесвіту Silken Net (паралель до того, як `docs/00_*..09_*` є SSOT технічної архітектури).

Український термін: **«Кодекс Архетипів»**.

## ✅ Статус

- **Поточний TRL:** TRL 6 (Phase 1 Foundation + Phase 2 Community done — read-only Atlas live з 79-record seed corpus, social layer з coments + attunements + Solid Cable broadcasts, full spec coverage). Phases 3-6 в плані.
- **Стек:** Rails 8.1 · PostgreSQL 16 (`pg_trgm`, `postgis`, `pgcrypto`) · Phlex · Tailwind v4 · Sidekiq (existing 9 queues) · Pundit · ActionCable (Solid Cable).
- **Жодних нових gem-залежностей.**
- **Пов'язані модулі:**
  - Моделі → [`04_01_Data_Models_and_Entities`](04_01_Data_Models_and_Entities)
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - REST API → [`04_03_REST_API_v1_Reference`](04_03_REST_API_v1_Reference)
  - UI → [`04_04_Phlex_UI_and_Tailwind`](04_04_Phlex_UI_and_Tailwind)

---

## Зміст

1. [Архітектурні принципи (чому ескіз був неправильний)](#1-архітектурні-принципи)
2. [Таблиці та моделі](#2-таблиці-та-моделі)
3. [Зв'язки з існуючою екосистемою](#3-звязки-з-існуючою-екосистемою)
4. [Sidekiq черги](#4-sidekiq-черги)
5. [Pundit-політики](#5-pundit-політики)
6. [REST API `/api/v1/codex/*`](#6-rest-api-apiv1codex)
7. [Phlex-компоненти та Sidebar](#7-phlex-компоненти-та-sidebar)
8. [Stimulus та ActionCable](#8-stimulus-та-actioncable)
9. [Seed-дані (79 записів)](#9-seed-дані)
10. [Документаційні правки SSOT](#10-документаційні-правки-ssot)
11. [Поетапна реалізація](#11-поетапна-реалізація)
12. [Безпека, продуктивність, anti-abuse](#12-безпека-продуктивність-anti-abuse)
13. [Бізнес-вартість](#13-бізнес-вартість)
14. [📌 Implementation Tracker (status across sessions)](#14--implementation-tracker)
15. [📓 Session Log / ADR](#15--session-log--adr)

---

## 1. Архітектурні принципи

| Проблема стартового ескізу | Рішення в цьому дизайні |
|---|---|
| 4 категорії як `enum` → ригідно | `Codex::Realm` як таблиця (DAO може додати 5-ту реальність без міграції) |
| STI на одну таблицю | Один `Codex::Node` без STI; різниця між реальностями = `realm_id` + `archetype_key` registry |
| "Лайк/рейтинг" злитий з "Синхронізацією" | Розділено: `Attunement` (семантичний вибір) ≠ `Match` (Elo-турнір) |
| "Discovery" як хардкод правил | `Codex::DiscoveryRule` — DAO-керовані правила без redeploy |
| Codex живе як ізольована "вікіпедія" | `Codex::Citation` (полі) — лор вшивається у `Tree`, `Cluster`, `AiInsight`, `OracleVision`, `EwsAlert`, `NaasContract` |
| Ігнор `uplink`-черги №1 | Discovery-хук НЕ йде в `uplink`; працює лише через `default`/`low` і тільки коли є відкрита presence-сесія |
| Ігнор RBAC | Pundit-політики на кожен ресурс; `super_admin` для редагування Node, `admin+` для DiscoveryRule |
| Ігнор партиціонування | `codex_matches` партиціонований RANGE by `created_at` (потенціал 100M+ рядків) |

### Архітектурні рішення (ADR-стиль)

- **ADR-CDX-1 (PK type)**: `codex_*` таблиці використовують **bigint** PK (узгоджено з рештою моделей; `uuid` зустрічається тільки у `idempotency_token` `actuator_commands`). UUID-формати лишаються для зовнішніх ідентифікаторів (`codex_uid` як `CDX-XXX-####`).
- **ADR-CDX-2 (no STI)**: різниця між `ecosystem | unique_tree | protocol | mythos` — це data, не код. Один клас `Codex::Node` + `realm_id` FK. Нові realms (наприклад `space`, `myco`) додаються DAO-голосуванням без deploy.
- **ADR-CDX-3 (bilingual без gem)**: `title_uk/_en`, `subtitle_uk/_en` — нативні колонки, не `mobility`/`globalize`. Економимо JOIN та новий gem; UA/EN — це SSOT-мови, інші локалі — не на горизонті.
- **ADR-CDX-4 (hot path)**: жоден Codex-worker не пушиться в `uplink` (#1), `alerts` (#2), `critical` (#3), `downlink` (#4), `web3_critical` (#6). Тільки `default` (#5) та `low` (#9).
- **ADR-CDX-5 (sanitization)**: `*_md` колонки — markdown ≤ 8 KiB / 2 KiB; render через Rails sanitizer + safelist (`p, h2-h4, ul, ol, li, strong, em, blockquote, code, pre, a[href]`); НЕ рендерити raw HTML.
- **ADR-CDX-6 (cap on Node)**: 10K rows expected — не партиціонувати. Партиціонувати лише `codex_matches` (RANGE by `created_at`).

---

## 2. Таблиці та моделі

Namespace `Codex::`, table prefix `codex_`. Reuse concern `GeoLocatable` (для Node). Жодних нових concerns.

### 2.1 `Codex::Realm` — `codex_realms` (~4 рядки)

Верхня таксономія. Seed: `ecosystem`, `unique_tree`, `protocol`, `mythos`.

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint PK | |
| `slug` | citext UNIQUE | `ecosystem`, `unique_tree`, `protocol`, `mythos` |
| `name_uk` | string NOT NULL | "Екосистема", "Унікальне Дерево", "Протокол", "Міфологія" |
| `name_en` | string NOT NULL | "Ecosystem", "Unique Tree", "Protocol", "Mythos" |
| `glyph` | string NOT NULL | icon-key для sidebar/cards: `forest`, `tree`, `protocol`, `mythos` |
| `accent_token` | string NOT NULL | Tailwind токен: `gaia-primary`, `status-info`, `status-warning`, `status-neutral` |
| `description_md` | text | Короткий опис реальності (≤ 2 KiB) |
| `position` | integer NOT NULL DEFAULT 0 | Сортування в UI |
| `is_active` | boolean NOT NULL DEFAULT true | Soft-disable |
| `created_at`, `updated_at` | timestamps | |

AASM не потрібно — стан незмінний.

### 2.2 `Codex::Node` — `codex_nodes` (~10K cap)

Центральна сутність. Усі 79 seed-записів — сюди.

**Identity:**
- `id` bigint PK
- `realm_id` bigint FK NOT NULL (індекс)
- `slug` citext UNIQUE NOT NULL — normalized `[a-z0-9-]`
- `codex_uid` string UNIQUE NOT NULL — формат `CDX-ECO-0001`, `CDX-TRE-0007`, `CDX-PRT-0003`, `CDX-MYT-0010` (для цитування з аудиту/блокчейну)

**Контент (UA/EN bilingual):**
- `title_uk`, `title_en` (string NOT NULL)
- `subtitle_uk`, `subtitle_en` (string) — інженерний архетип, напр. *"Legacy Master Node"*

**Архетип:**
- `archetype_key` (string NOT NULL) — машинний слаг з registry `Codex::ARCHETYPES` (валідація inclusion). Підстава для `Fraction`-вибору. Приклади: `chaos_engineering`, `legacy_master_node`, `cold_wallet`, `network_architect`, `deep_tech_survivor`, `air_gap`, `radiation_hardened`, `quantum_routing`…

**Lore (sanitized markdown):**
- `context_md` text (≤ 8 KiB) — географія/історія
- `cyber_meaning_md` text (≤ 8 KiB) — кіберфізичний сенс
- `lore_md` text nullable (≤ 16 KiB) — опціональний deep-dive

**Geo:**
- `latitude`, `longitude` numeric nullable (concern `GeoLocatable`)
- `geo_point` PostGIS GEOGRAPHY(POINT, 4326) — обчислюється callback із lat/lng
- `geo_region` string nullable (label, напр. `cherkasy-bir`)
- GIST-індекс на `geo_point`
- Для `mythos`/`protocol` лишається NULL.

**Lifecycle:**
- `lifecycle_status` string-backed enum (prefix `lifecycle_status_`):
  - `mythical | extinct | endangered | thriving | destroyed | unknown`
- Маппиться на `StatusBadge` (див. §7).

**Медіа (ActiveStorage):**
- `cover_image` (один blob) — варіант `:thumb` (200×200) і `:hero` (1200×600)
- `gallery` `has_many_attached`

**Зовнішні референси:**
- `external_refs` JSONB DEFAULT `[]` — `[{label:, url:}]` (Wikipedia/IUCN/DOI)

**Provenance:**
- `seed_origin` string-backed enum (prefix `seed_origin_`):
  - `seed | dao_proposal | community_submission`

**Discovery hint:**
- `discoverable_after_minutes` integer nullable

**Counter caches:**
- `attunement_count`, `comments_count`, `view_count`, `discovery_count`, `citation_count` — integer NOT NULL DEFAULT 0

**Battle state:**
- `attunement_elo` integer NOT NULL DEFAULT 1500
- `match_count` integer NOT NULL DEFAULT 0

**Часи:**
- `published_at`, `created_at`, `updated_at`

**Індекси:**
- UNIQUE `slug`, UNIQUE `codex_uid`
- BTREE `(realm_id, attunement_elo DESC)`
- GIST `geo_point`
- pg_trgm GIN `(title_uk gin_trgm_ops)`, `(title_en gin_trgm_ops)` — для повнотекстового пошуку без Elasticsearch
- BTREE `lifecycle_status`, `archetype_key`

### 2.3 `Codex::Comment` — `codex_comments`

Полі-зв'язок (futureproof — наразі тільки до Node).

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint PK | |
| `commentable_type` | string NOT NULL | поки тільки `"Codex::Node"` |
| `commentable_id` | bigint NOT NULL | |
| `user_id` | bigint FK NOT NULL | |
| `parent_id` | bigint FK nullable (self) | 1 рівень вкладеності |
| `body_md` | text NOT NULL | ≤ 2 KiB |
| `flagged_at` | timestamp nullable | |
| `flag_reason` | enum nullable | `spam | abuse | offtopic | other` |
| `hidden_by_admin_id` | bigint FK nullable (users) | soft-hide, не delete |
| `hidden_at` | timestamp nullable | |
| `created_at`, `updated_at` | timestamps | |

**Індекси:** BTREE `(commentable_type, commentable_id, created_at DESC)`, BTREE `user_id`, BTREE `parent_id`.

**ActionCable:** `Codex::CommentChannel` broadcast `codex_comments_<node_id>` через Solid Cable.

**Не партиціонуємо в MVP** (достатньо BTREE). Шаблон майбутнього партиціонування — як у `audit_logs`.

### 2.4 `Codex::Attunement` — `codex_attunements` («Синхронізація»)

Семантичний акт «я налаштований на цей архетип». Не лайк — користувач робить 1–7 одночасно і вони видимі в профілі.

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint PK | |
| `user_id` | bigint FK NOT NULL | |
| `codex_node_id` | bigint FK NOT NULL | counter_cache → `attunement_count` |
| `intensity` | integer NOT NULL DEFAULT 3 | 1..5 |
| `quote` | string nullable (≤ 280 chars) | особистий девіз |
| `started_at` | timestamp NOT NULL DEFAULT now() | |

**Індекс:** UNIQUE `(user_id, codex_node_id)`.

### 2.5 `Codex::Fraction` — `codex_fractions` («Фракція / Клас»)

**Один користувач = одна активна фракція** (на відміну від множинних attunements). Окрема модель з UNIQUE `user_id`, щоб не захаращувати `users`.

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint PK | |
| `user_id` | bigint FK UNIQUE NOT NULL | |
| `codex_node_id` | bigint FK NOT NULL | |
| `archetype_key` | string NOT NULL | денормалізація з Node для фільтрів |
| `chosen_at` | timestamp NOT NULL | |
| `last_changed_at` | timestamp NOT NULL | |
| `house_color_token` | string nullable | Tailwind токен (наприклад `status-info`) |

**Service:** `Codex::FractionChangeService` — 7-денний cooldown, AuditLog (`change_fraction`).

**Asоціація:** `User#codex_fraction` (`has_one :codex_fraction, dependent: :destroy`).

### 2.6 `Codex::Match` — `codex_matches` (PARTITIONED RANGE by `created_at`)

"Battle of the Nodes" — Elo-дуелі.

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint | |
| `created_at` | timestamp NOT NULL | partition key |
| **PK** | composite `(id, created_at)` | як у `blockchain_transactions` |
| `user_id` | bigint FK NOT NULL | |
| `realm_id` | bigint FK NOT NULL | бій лише в межах одного realm |
| `left_node_id` | bigint FK NOT NULL | |
| `right_node_id` | bigint FK NOT NULL | |
| `winner_node_id` | bigint FK nullable | NULL = skip |
| `pair_seed` | string NOT NULL | HMAC-SHA256 від `(user_id|realm|timestamp)` + Redis nonce |
| `elo_delta_left` | integer NOT NULL | |
| `elo_delta_right` | integer NOT NULL | |

**Індекси:** BTREE `(user_id, created_at DESC)`, BTREE `(left_node_id, right_node_id)`, BTREE `realm_id`.

**Партиції:** створюються `PartitionMaintenanceWorker` (existing) — додати таблицю в його список. Назва партиції `codex_matches_y2026m05`. Початкові: `_default` + 6 місяців наперед.

### 2.7 `Codex::Discovery` — `codex_discoveries` («Колекція»)

Запис розблокування картки користувачем.

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint PK | |
| `user_id` | bigint FK NOT NULL | |
| `codex_node_id` | bigint FK NOT NULL | |
| `trigger_type` | enum NOT NULL | `telemetry_observation \| manual_unlock \| match_milestone \| fraction_choice \| attunement_streak \| oracle_seasonal` |
| `trigger_ref_type` | string nullable | поліморфне джерело |
| `trigger_ref_id` | bigint nullable | |
| `unlocked_at` | timestamp NOT NULL | |

**Індекс:** UNIQUE `(user_id, codex_node_id)`.

### 2.8 `Codex::DiscoveryRule` — `codex_discovery_rules`

Замість хардкоду умов розблокування — табличний реєстр. Кешується в `Rails.cache.fetch("codex.discovery_rules.v1")` з invalidation на `after_commit`.

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint PK | |
| `name` | string NOT NULL | |
| `codex_node_id` | bigint FK NOT NULL | картка-приз |
| `condition_type` | enum NOT NULL | `tree_observation_minutes \| acoustic_class_count \| cluster_visited \| match_count \| attunement_streak_days \| firmware_version_seen \| oracle_dispatched` |
| `threshold_value` | integer NOT NULL | |
| `params_json` | JSONB DEFAULT '{}' | додаткові параметри (regex для region, тощо) |
| `active` | boolean NOT NULL DEFAULT true | |
| `created_by_user_id` | bigint FK NOT NULL | |
| `created_at`, `updated_at` | timestamps | |

CRUD — admin+ через `Codex::Admin::DiscoveryRulesController`.

### 2.9 `Codex::Citation` — `codex_citations` («лор-зшивка»)

Полі-зв'язок: будь-яка операційна сутність може процитувати Node.

| Колонка | Тип | Призначення |
|---|---|---|
| `id` | bigint PK | |
| `codex_node_id` | bigint FK NOT NULL | counter_cache → `citation_count` |
| `citable_type` | string NOT NULL | `Tree | Cluster | AiInsight | EwsAlert | OracleVision | NaasContract` |
| `citable_id` | bigint NOT NULL | |
| `created_by_user_id` | bigint FK NOT NULL | |
| `note` | string (≤ 140 chars) nullable | |
| `created_at` | timestamp NOT NULL | |

**Індекси:** BTREE `(citable_type, citable_id)`, BTREE `codex_node_id`, UNIQUE `(codex_node_id, citable_type, citable_id, created_by_user_id)` — анти-дубль.

**Renderer:** `Codex::CitationPill` Phlex-компонент → у `Tree::Show`, `Cluster::Show`, `OracleVisions::ForecastCard`, `EwsAlert::Row` (Phase 6).

### 2.10 Сумарна реєстрація

Додаємо **8 нових моделей** до існуючих 26 → стає **34**. Concerns reused: `GeoLocatable`. Жодних нових concerns. Жодних нових gem.

---

## 3. Зв'язки з існуючою екосистемою

```
User
 ├── has_one  :codex_fraction
 ├── has_many :codex_attunements
 ├── has_many :codex_discoveries
 ├── has_many :codex_matches
 ├── has_many :codex_comments
 └── has_many :codex_citations,  foreign_key: :created_by_user_id

Codex::Node
 ├── has_many :citations  (counter_cache → citation_count)
 ├── has_many :attunements (counter_cache → attunement_count)
 ├── has_many :comments   (counter_cache → comments_count)
 └── has_many :discoveries(counter_cache → discovery_count)

Codex::Citation #citable polymorphic →
  Tree, Cluster, AiInsight, EwsAlert, OracleVision, NaasContract

User.oracle_executioner (system bot)
  └── seed_origin: :seed Node-ів та системних Discovery
```

**AuditLog** пишеться при:
- створенні/редагуванні Node (admin)
- зміні Fraction
- прихованні Comment (admin)
- ручному unlock Discovery (admin)

**EthereumAnchor** (опціонально, не MVP, окремий feature flag): щомісячний хеш топ-100 Elo-лідерборду як «культурний state root».

---

## 4. Sidekiq черги

Тільки існуючі 9; жодної нової.

| Worker | Черга | Trigger |
|---|---|---|
| `Codex::EloRecomputeWorker` | `low` (#9) | після кожного `Match.create` (atomic K-factor 32, decay після 30-го матчу) |
| `Codex::DiscoveryProbeWorker` | `default` (#5) | З `UnpackTelemetryWorker` finalizer **тільки якщо** `presence?(user_for_tree)` → не блокує `uplink` |
| `Codex::ContentReindexWorker` | `low` (#9) | `after_commit` на Node → варм кешу + trigram refresh |
| `Codex::AttunementBroadcastWorker` | `default` (#5) | toggle Attunement → live-counter Turbo Stream |
| `Codex::FractionAuditWorker` | `default` (#5) | зміна Fraction → AuditLog + notifier |

`PartitionMaintenanceWorker` (existing): додаємо `codex_matches` у його список.

---

## 5. Pundit-політики (`app/policies/codex/`)

| Policy | read | create | update / destroy |
|---|---|---|---|
| `Codex::NodePolicy` | all auth | super_admin | super_admin (DAO-канал — окремо) |
| `Codex::CommentPolicy` | all auth | auth user | own ≤ 24h, або admin+ (тоді `hide`, не `delete`) |
| `Codex::AttunementPolicy` | own / public counters | auth | own |
| `Codex::FractionPolicy` | own / public | auth | own (cooldown service-side) |
| `Codex::MatchPolicy` | own / leaderboard | auth (з throttle) | — |
| `Codex::DiscoveryPolicy` | own | system bot only | — |
| `Codex::DiscoveryRulePolicy` | admin+ | admin+ | admin+ |
| `Codex::CitationPolicy` | all auth | forester+ | own ≤ 24h, admin+ |

`investor` (роль 0): повний read + Attunement/Fraction/Match/Comment (соціальний шар). Citation — лише `forester+` (операційне).

---

## 6. REST API `/api/v1/codex/*`

12 нових ендпоінтів + 2 admin. Всі дотримуються конвенцій 04_03: стандартний JSON-конверт, Bearer/Session auth (крім публічних read), `Idempotency-Key` обов'язковий для всіх write JSON, Pagy 21/сторінка (battle/leaderboard — 10), Phlex Turbo Frame на frame-ендпоінтах.

| Метод | Шлях | Призначення | Roles |
|---|---|---|---|
| GET | `/api/v1/codex/realms` | список 4 realm з лічильниками | all |
| GET | `/api/v1/codex/nodes` | фільтри: `realm`, `lifecycle_status`, `q` (trigram), `near=lat,lng`, `discovered=true|false`, `archetype` | all |
| GET | `/api/v1/codex/nodes/:slug` | сторінка Show (slug, не id) | all |
| POST | `/api/v1/codex/nodes/:slug/attunements` | toggle (idempotent) | auth |
| DELETE | `/api/v1/codex/nodes/:slug/attunements/me` | прибрати | own |
| POST | `/api/v1/codex/nodes/:slug/comments` | створити коментар | auth |
| POST | `/api/v1/codex/fractions` | обрати/змінити фракцію (cooldown 7д) | auth |
| GET | `/api/v1/codex/battle/pair?realm=` | Turbo Frame з парою + `pair_seed` | auth |
| POST | `/api/v1/codex/battle/votes` | body: `pair_seed`, `winner_slug` (або `skip=true`) | auth |
| GET | `/api/v1/codex/leaderboard?realm=` | top-N Elo, Turbo Frame | all |
| GET | `/api/v1/codex/discoveries/me` | моя колекція | own |
| POST | `/api/v1/codex/citations` | прив'язати Node до Tree/Cluster/etc. | forester+ |
| POST/PATCH | `/api/v1/codex/admin/nodes` | admin Node CRUD | super_admin |
| POST/PATCH | `/api/v1/codex/admin/discovery_rules` | DAO rule CRUD | admin+ |

`Rack::Attack`: правила `60 votes / 1 minute / user` на `/codex/battle/votes`, `120 attunements / 1 hour / user`.

---

## 7. Phlex-компоненти та Sidebar

Папка `app/views/components/codex/`. Без жодного raw `bg-*`/`text-*` поза доменними; тільки токени `gaia-*` / `status-*`.

- **`Codex::Index`** — grid через `Views::Shared::UI::PhotoCard` з `ActionBadge`-overlay (колір по realm: `creative` для ecosystem, `mutative` для protocol, `neutral` для mythos, custom для unique_tree). Реюз `EmptyState`, `Pagination`.
- **`Codex::Show`** — hero (`cover_image` variant `:hero`), блок `MetaRow` × N (Realm, Archetype, Lifecycle Status через `StatusBadge`, Geo Region, Discovered By N, Cited By N), дві колонки markdown (`context_md` стандартним стилем, `cyber_meaning_md` у виділеній панелі `bg-gaia-surface-alt p-4 border-l-2 border-gaia-primary`), Citations sidebar, Comments thread, Attunement toggle button.
- **`Codex::RealmTabs`** — фільтр-стрічка зверху Index.
- **`Codex::Battle::Arena`** — Turbo Frame `id="codex_battle_arena"`, дві `PhotoCard`, "VS" розділювач, `data-controller="codex--battle"` (debounce, swap-анімація). Vote → Turbo Stream `replace` арени новою парою.
- **`Codex::Leaderboard::Table`** — `Views::Shared::UI::DataTable`, колонки: rank / cover-thumb / title / Elo / matches / lifecycle badge.
- **`Codex::Discovery::Toast`** — Turbo Stream `append` у канал `DiscoveriesChannel` у `DashboardLayout`. Анімація matrix-rain (reuse Stimulus `matrix-rain`).
- **`Codex::Fraction::Picker`** — Turbo Frame багатоступеневий wizard.
- **`Codex::CitationPill`** — інлайн-компонент (`text-mini bg-gaia-surface-alt rounded px-2`), у `Tree::Show`, `Cluster::Show`, `OracleVisions::ForecastCard`, `EwsAlert::Row`.

### Розширення `Views::Shared::UI::StatusBadge::STYLES`:

```ruby
"mythical"   => "bg-status-info text-status-info-text",
"extinct"    => "bg-status-neutral text-status-neutral-text opacity-50",
"endangered" => "bg-status-warning text-status-warning-text",
"thriving"   => "bg-status-success text-status-success-text",
"destroyed"  => "bg-status-danger text-status-danger-text line-through",
# unknown — DEFAULT_STYLE
```

### Sidebar

Нова секція `section_group("Library")` між «Strategic Insight» та «Forest Operations»:

- "Codex Atlas" → `api_v1_codex_nodes_path`, icon `book`
- "Battle Arena" → `pair_api_v1_codex_battle_path`, icon `swords`
- "My Fraction" → `api_v1_codex_fractions_path`, icon `shield`
- "Leaderboard" → `api_v1_codex_leaderboard_path`, icon `trophy`

Glyph-маппінг у `Navigation::Sidebar#render_icon`:
- `book` → "📖"
- `swords` → "⚔"
- `shield` → "🛡"
- `trophy` → "🏆"

---

## 8. Stimulus та ActionCable

Нові Stimulus (camel-case-двокрапка):
- `codex--battle` — vote-throttle, оптимістичний swap, keyboard ← →
- `codex--attune` — оптимістичний toggle UI до Turbo Stream відповіді
- `codex--reveal` — Discovery Toast анімація з matrix-rain canvas

Reuse `map` (Leaflet) для відображення `geo_point` Node-ів на існуючій Cluster-карті як layer "Lore Sites".

Solid Cable канали:
- `Codex::DiscoveryChannel` (per-user) — нові розблокування
- `Codex::AttunementChannel` (per-node) — live counter
- `Codex::CommentChannel` (per-node) — нові коментарі

---

## 9. Seed-дані

**79 записів** з нового вимагання-доповнення:
- 32 ecosystems (Черкаський бір, Холодний Яр, ..., Підземний мікоризний ліс)
- 29 unique_trees (Дуб Залізняка, Пандо, Мафусаїл, ..., Ялина-змія)
- 8 protocols (CODIT, Етиленовий Бродкаст, ..., Ультразвукова кавітація)
- 10 mythos (Цзяньму, Фусан, Іґґдрасіль, ..., Баромець)

Папка:
```
db/seeds/codex/
├── realms.yml                  (4 записи)
├── nodes/
│   ├── ecosystems.yml          (32)
│   ├── unique_trees.yml        (29)
│   ├── protocols.yml           (8)
│   └── mythos.yml              (10)
└── discovery_rules.yml         (12 початкових правил)
```

Завантаження через ідемпотентний `Codex::NodeImportService.call` (UPSERT по `slug`), викликається з `db/seeds.rb` ПІСЛЯ User/Organization. Можна перезапускати у production без дублів.

Кожен YAML-вузол має:
- стабільний `slug` (напр. `cherkasy-bir`, `mafusail`, `acacia-whistling`, `protocol-codit`, `yggdrasil`)
- `codex_uid` (`CDX-XXX-####`)
- bilingual title + subtitle
- `archetype_key` із registry
- `cyber_meaning_md` (дослівно з вимагання — це вже готовий лор)
- `lifecycle_status` (Дерево Тенере → `destroyed`, Мафусаїл → `thriving`, Іґґдрасіль → `mythical`, Аокігахара → `endangered`, etc.)
- `geo_region` (для всіх ecosystem + більшості unique_tree)
- координати для географічних об'єктів (де відомі)

### Початкові DiscoveryRule

- "Спостерігав за деревом 10 годин → unlock `roots-darwin-brain`"
- "Зафіксована подія cavitation у трьох телеметрії → unlock `protocol-ultrasonic-cavitation`"
- "Відвідав Cluster з регіоном `cherkasy-bir` → unlock `cherkasy-bir`"
- "Перший Match у realm mythos → unlock `yggdrasil`"
- (8 інших — деталі у `db/seeds/codex/discovery_rules.yml`)

---

## 10. Документаційні правки SSOT

- **Новий**: `docs/04_05_Codex_Lore_Module.md` (цей файл).
- `docs/04_01`: оновити лічильник «26 моделей» → 34, додати розділ `## 🪶 N. Codex Module` з усіма 8 таблицями.
- `docs/04_02`: додати розділ Codex Services (Import, Attunement, FractionChange, PairSelector, EloUpdater, DiscoveryEngine).
- `docs/04_03`: додати 12 ендпоінтів у повну таблицю.
- `docs/04_04`: оновити реєстр Phlex-компонентів (+ Codex piece), додати Sidebar секцію «Library», розширити `StatusBadge` мапінг lifecycle.
- Wiki-індекс — посилання на 04_05.
- README — рядок про «Lore layer».

---

## 11. Поетапна реалізація

Кожна фаза — окрема міграція (forward-compatible, без `down` для seed-записів), окремий набір RSpec, Brakeman + Rubocop чисті.

| Фаза | Що входить | Залежності |
|---|---|---|
| **1. Foundation** | `Realm`, `Node`, `Citation` + 79 seed-записів + Read-only Atlas (Index/Show) + Sidebar секція «Library» + `StatusBadge` розширення + Pundit policies + контролери Realms/Nodes + специ моделей+request | — |
| **2. Community** | `Comment`, `Attunement`, counter caches, ActionCable broadcast, Comments UI, AttunementsController | Phase 1 |
| **3. Identity** | `Fraction`, `User#codex_fraction`, profile інтеграція, `FractionChangeService`, AuditLog hook, Fraction Picker wizard | Phase 2 |
| **4. Battle** | `Match` (партиціонована), `PairSelector`, `EloRecomputeWorker`, Arena UI, Leaderboard, `Rack::Attack` ліміти, `PartitionMaintenanceWorker` patch | Phase 3 |
| **5. Discovery** | `DiscoveryRule`, `Discovery`, `DiscoveryEngine`, presence-gated telemetry hook, Toast, `DiscoveryProbeWorker` | Phase 4 |
| **6. Cross-domain stitch** | `CitationPill` у `Tree::Show`, `Cluster::Show`, `OracleVisions::ForecastCard`, `EwsAlert::Row`; адмін-CRUD для Node/DiscoveryRule; `CitationsController` для forester+ | Phase 5 |

---

## 12. Безпека, продуктивність, anti-abuse

- `body_md` / `*_md` → render через Rails sanitizer + safelist (`p, h2-h4, ul, ol, li, strong, em, blockquote, code, pre, a[href]`); довжина серверно лімітована.
- `pair_seed` Battle: HMAC-SHA256 від `(user_id|realm|timestamp)` з server secret + Redis nonce (TTL 5 хв) → не можна підмінити пару чи переголосувати.
- Rate-limits через `Rack::Attack` (вже у стеку).
- Counter caches атомарні (`counter_cache: true`) → нема race у соцлічильниках.
- Read-страниці `Show` Russian-Doll-кешовані по `(node.cache_key_with_version, realm.updated_at)`.
- `attunement_elo` оновлюється строго в worker (queue `low`), читається з 60-сек fragment-cache.
- `WEB3_STRICT_MODE` НЕ зачіпає Codex (нема Web3-залежностей у MVP). EthereumAnchor топ-100 — окремий feature flag.
- Жодної нової зовнішньої залежності (gem) — все на стандартному стеку Rails 8.1 + Phlex + PostgreSQL `pg_trgm`/PostGIS, які вже увімкнені.

---

## 13. Бізнес-вартість

- Codex стає **запалом** для UGC: кожен Tree у `Cherkasy bir` фізично пов'язаний цитатою з лор-карткою → інвестори бачать «Pando-pattern» у живій телеметрії.
- Fraction робить кожного користувача акціонером не лише гаманця, а й нарративу — підтримує retention.
- Battle Arena дає safe-mode гейміфікацію (без витрат токенів, без газу) і генерує **сигнал якості архетипів** для майбутніх DAO-голосувань.
- Discovery — найдешевший спосіб дати "wow"-моменти у нудних моментах телеметрії, без зміни hot-path `uplink`.
- Citation створює **зворотний потік**: операції → лор → операції, замість того щоб мати «вікіпедію в кутку».

---

## 14. 📌 Implementation Tracker

> **Інструкція для агентів наступних сесій:** оновлюйте цей розділ після кожного завершеного під-завдання. Чекбокс `[x]` = виконано і протестовано (RSpec/Rubocop зелені). Чекбокс `[ ]` = не зроблено. Усі рішення/відхилення документуйте у §15.

### Phase 1: Foundation 🌱 (✅ done)

**Migration & schema:**
- [x] Міграція `CreateCodexFoundationTables` (consolidated into `20260509120000_init_consolidated.rb` after migration squash) — 3 таблиці з GIST/pg_trgm/UNIQUE/FK
- [x] Оновлено `db/structure.sql`

**Models:**
- [x] `Codex::Realm` (валідації slug формат, accent_token, `name(locale)`, `ordered` scope)
- [x] `Codex::Node` (enums `lifecycle_status`+`seed_origin` з prefix, ARCHETYPES registry 79 keys, `GeoLocatable` concern, ActiveStorage `cover_image`+`gallery`, scopes `for_realm`/`search_title`/`by_archetype`/`by_lifecycle`/`ordered_by_elo`, `sync_geo_point` PostGIS hook, slug normalization, `external_refs` JSONB validator)
- [x] `Codex::Citation` (polymorphic citable, counter_cache `citation_count`, UNIQUE guard)
- [x] `Codex::ARCHETYPES` константа (frozen 79-key registry: 32 ecosystem + 29 unique_tree + 8 protocol + 10 mythos)
- [x] `Codex::MarkdownRenderer` (Rails sanitizer, `rel`/`target` safelist, javascript: scheme rewrite)

**User association add-ons:**
- [ ] `User has_many :codex_citations, foreign_key: :created_by_user_id` *(відкладено до Phase 6 — citation creation endpoint)*

**Policies:**
- [x] `Codex::ApplicationPolicy` (база: read for any authed user, write false)
- [x] `Codex::NodePolicy` (Scope ховає чернетки для не-super_admin)
- [x] `Codex::CitationPolicy`
- [x] `Codex::RealmPolicy`

**Routes:**
- [x] `namespace :codex` під `/api/v1/`: `realms#index`, `nodes#index`, `nodes#show` (param `:slug`)

**Controllers:**
- [x] `Api::V1::Codex::RealmsController#index` (JSON + HTML)
- [x] `Api::V1::Codex::NodesController#index` (filters: realm, lifecycle_status, q, archetype; Pagy 21/page)
- [x] `Api::V1::Codex::NodesController#show` (slug-based, atomic `view_count++`)

**Phlex components (read-only Atlas):**
- [x] `Views::Shared::UI::StatusBadge` — додано lifecycle мапінги (`mythical`/`extinct`/`endangered`/`thriving`/`destroyed`/`unknown`)
- [x] `Codex::Index`
- [x] `Codex::Show`
- [x] `Codex::RealmTabs`
- [x] `Codex::NodeCard`

**Navigation:**
- [x] `Navigation::Sidebar` — секція «Library» між Strategic Insight і Forest Ops з пунктом "Codex Atlas"
- [x] `render_icon` — додані необхідні гліфи

**Blueprints (для JSON):**
- [x] `Codex::RealmBlueprint`
- [x] `Codex::NodeBlueprint` (`:default`, `:show` view з лор-полями)

**Seeds (79 записів):**
- [x] `db/seeds/codex/realms.yml` (4)
- [x] `db/seeds/codex/nodes/ecosystems.yml` (32)
- [x] `db/seeds/codex/nodes/unique_trees.yml` (29)
- [x] `db/seeds/codex/nodes/protocols.yml` (8)
- [x] `db/seeds/codex/nodes/mythos.yml` (10)
- [x] `Codex::NodeImportService` (UPSERT по slug, ідемпотентний, зберігає DAO `seed_origin`)
- [x] **Production-safe rake task** `bin/rails codex:seed` (НЕ через `db:seeds.rb`, бо seeds не виконується на проді)
- [x] Hook у `db/seeds.rb` теж присутній — для dev convenience

**Specs (per docs/10_01 + docs/10_03):**
- [x] `spec/factories/codex.rb` (`:codex_realm`, `:codex_node`, `:codex_citation`)
- [x] `spec/models/codex/{realm,node,citation}_spec.rb` (38 examples)
- [x] `spec/services/codex/node_import_service_spec.rb` (7 examples)
- [x] `spec/services/codex/markdown_renderer_spec.rb` (11 examples)
- [x] `spec/policies/codex/node_policy_spec.rb` (7 examples)
- [x] `spec/requests/api/v1/codex/realms_controller_spec.rb` (3 examples)
- [x] `spec/requests/api/v1/codex/nodes_controller_spec.rb` (9 examples)
- [x] `spec/views/components/codex/node_card_spec.rb` (10 examples)

**Total: 85 examples / 0 failures**

**Docs:**
- [x] `docs/04_05_Codex_Lore_Module.md` (цей файл) створено + tracker tick-off + Session Log Phase 1 entry
- [x] `docs/04_01` — лічильник 26 → 29 моделей, додано розділ "📖 7b. Codex — Lore Layer", оновлено Карту Зв'язків, додано pg_trgm в Розширення, секція Seeds описує `bin/rails codex:seed`
- [x] `docs/04_02` — додано "📖 10b. Codex (Lore Layer) Сервіси" (NodeImportService, MarkdownRenderer)
- [x] `docs/04_03` — додано 3 ендпоінти (#86 GET realms, #87 GET nodes, #88 GET node show)
- [x] `docs/04_04` — розширено StatusBadge mapping (lifecycle), Sidebar 4→5 груп (+Library), додано "Codex (Lore Layer)" блок у §6.4
- [x] `docs/10_03` — додано рядки в §1.1 (3 моделі), §1.2 (2 сервіси), §1.4/§1.5/§1.6 (controllers/policy/view)

**Quality gates:**
- [x] `bundle exec rubocop` — зелений (5 авто-correctable RSpec/PredicateMatcher застосовано)
- [x] `bundle exec rspec spec/models/codex spec/services/codex spec/policies/codex spec/requests/api/v1/codex spec/views/components/codex` — 85 examples / 0 failures
- [x] `bundle exec brakeman` — 0 нових warnings
- [ ] `bundle exec bundler-audit check` — runs in CI; no new gem deps were added (Codex покладається на наявні: pg_trgm extension, Rails::HTML5::SafeListSanitizer, Phlex, Pagy, Pundit, Blueprinter)

**Side effects (cleanup-debt closed in Phase 1 PR):**
- [x] **Migration squash** — всі попередні incremental міграції згорнуті в єдиний `20260509120000_init_consolidated.rb`. Data-only `seed_governance_system_parameters` міграція видалена; еквівалентний idempotent UPSERT тепер у `bin/rails governance:seed_parameters`.
- [x] **Lookbook YARD noise fixed** — `config/initializers/lookbook_yard_tags.rb` реєструє `@notes` тег; flood `[warn]: Unknown tag @notes` зник з усіх `rails/rake/rspec` boots.

### Phase 2: Community 💬 (✅ done)

**Migration & schema:**
- [x] Міграція `20260509130000_create_codex_community_tables.rb` (нова форма — після squash всі нові міграції файли окремо)
- [x] `codex_comments` (polymorphic, self-FK `parent_id`, soft-hide pair, BTREE `(commentable_type, commentable_id, created_at DESC)`)
- [x] `codex_attunements` (UNIQUE `(user_id, codex_node_id)`, DB CHECK `intensity BETWEEN 1 AND 5`, `started_at` default `now()`)
- [x] Counter columns (`comments_count`, `attunement_count`) уже були на `codex_nodes` із Phase 1 — без ALTER TABLE
- [x] Оновлено `db/structure.sql` (5699 → 5908 рядків)

**Models:**
- [x] `Codex::Comment` (polymorphic `commentable`, `parent_must_be_top_level` + `parent_must_share_commentable` валідації, `BODY_MAX = 2 KiB`, `EDIT_GRACE = 24h`, `FLAG_REASONS`, scopes `visible/hidden/top_level/chronological`, `editable_by?(user)` helper)
- [x] `Codex::Attunement` (`INTENSITY_RANGE = (1..5)`, `QUOTE_MAX = 280`, counter_cache, `for_node/for_user/ordered` scopes, before_validation `default_started_at`)

**User association add-ons:**
- [x] `User has_many :codex_comments, dependent: :restrict_with_error` (модерація-trail захищена)
- [x] `User has_many :codex_attunements, dependent: :destroy`

**Policies:**
- [x] `Codex::CommentPolicy` (own ≤ 24h або admin+ → hide, не destroy; Scope ховає hidden від не-admin)
- [x] `Codex::AttunementPolicy` (read all-auth; write own-only)

**Routes:**
- [x] Nested під `nodes`: `POST /attunements`, `DELETE /attunements/me`, `POST /comments`

**Controllers:**
- [x] `Api::V1::Codex::AttunementsController#create` (`find_or_initialize_by` + counter cache)
- [x] `Api::V1::Codex::AttunementsController#destroy_me` (idempotent — no-op якщо рядка нема)
- [x] `Api::V1::Codex::CommentsController#create` (`Idempotency-Key` обов'язковий для JSON, 24h cache TTL, inline ActionCable broadcast)

**Worker:**
- [x] `Codex::AttunementBroadcastWorker` (queue `default`, retry 3) — public + private channels

**Blueprints:**
- [x] `Codex::CommentBlueprint` (з `body_html` через `MarkdownRenderer`, `replies_count`, `hidden` flag)
- [x] `Codex::AttunementBlueprint`

**Phlex components:**
- [x] `Codex::Attunements::Toggle` (POST/DELETE form, gaia-* tokens, `data-controller=codex--attune`)
- [x] `Codex::Comments::Thread` (DOM id `codex_node_<id>_comments` — Solid Cable target)
- [x] `Codex::Comments::Item` (sanitised markdown, ISO timestamp, hidden-state styling)
- [x] `Codex::Comments::Form` (textarea `maxlength: BODY_MAX`)
- [x] `Codex::Show` extended з Toggle + Thread (props: `current_user:`, `comments:`, `current_user_attuned:`)

**ActionCable broadcasts (Solid Cable топіки):**
- [x] `codex_node_<id>_comments` — нові коментарі (з blueprint payload)
- [x] `codex_node_<id>_attunements` — public attunement counter
- [x] `codex_node_<id>_attunements_user_<uid>` — private `attuned: bool` envelope

**Anti-abuse (`Rack::Attack`):**
- [x] `codex/attunements` — 120 / 1h / actor (per `docs/04_05` §12)
- [x] `codex/comments` — 60 / 10min / actor

**Specs (per docs/10_01 + docs/10_03):**
- [x] `spec/factories/codex.rb` додано `:codex_comment`, `:codex_attunement`
- [x] `spec/models/codex/comment_spec.rb` (15 examples) + `attunement_spec.rb` (10 examples)
- [x] `spec/policies/codex/comment_policy_spec.rb` (8 examples) + `attunement_policy_spec.rb` (4 examples)
- [x] `spec/requests/api/v1/codex/attunements_controller_spec.rb` (8 examples) + `comments_controller_spec.rb` (6 examples)
- [x] `spec/workers/codex/attunement_broadcast_worker_spec.rb` (5 examples)
- [x] `spec/views/components/codex/attunements/toggle_spec.rb` (8 examples) + `comments/{thread,item}_spec.rb` (6 + 5 examples)

**Total Phase 1+2: 160 examples / 0 failures**

**Docs synced:**
- [x] `docs/04_01` — model count 29 → 31, додано підрозділи `Codex::Comment` + `Codex::Attunement`
- [x] `docs/04_02` — додано `AttunementBroadcastWorker` + Phase 2 controllers note до 10b
- [x] `docs/04_03` — endpoint count 85 → 88, додано рядки #89/#90/#91 з throttle-deтalями
- [x] `docs/04_04` — додано Toggle/Thread/Item/Form у Codex Phlex-блок + ActionCable топіки
- [x] `docs/10_03` — Phase 2 моделі / policies / requests / worker / views рядки

**Quality gates:**
- [x] `bundle exec rspec` (codex slice) — 160 examples / 0 failures
- [x] `bundle exec rubocop` (codex + touched files) — clean (2 авто-correctable RSpec/ExpectChange застосовано)
- [x] `bundle exec brakeman` — 0 нових warnings
- [x] **Bug-fix from Phase 1 caught:** `Codex::Show` використовував `unsafe_raw` (не існує в Phlex 2.4); замінено на `raw safe(...)` у `show.rb` + `comments/item.rb`. Phase 1 рендер не падав тому що Show ніколи не виконувався тестами.

### Phase 3: Identity 🛡 (planned)
- [ ] Migration `CreateCodexFractions`
- [ ] Model `Codex::Fraction` + `User#codex_fraction has_one`
- [ ] `Codex::FractionChangeService` (7-day cooldown, AuditLog)
- [ ] Endpoint: `POST /api/v1/codex/fractions`
- [ ] UI: `Codex::Fraction::Picker` wizard
- [ ] `Codex::FractionAuditWorker` (queue `default`)
- [ ] Profile integration (показати фракцію у `Users::Profile`)
- [ ] Specs

### Phase 4: Battle ⚔ (planned)
- [ ] Migration `CreateCodexMatches` (PARTITIONED RANGE by created_at)
- [ ] Model `Codex::Match` (composite PK `(id, created_at)`)
- [ ] `Codex::PairSelectorService` (HMAC-SHA256 + Redis nonce)
- [ ] `Codex::EloRecomputeWorker` (queue `low`, K-factor 32)
- [ ] Endpoints: `GET /battle/pair`, `POST /battle/votes`, `GET /leaderboard`
- [ ] UI: `Codex::Battle::Arena` (Turbo Frame + Stimulus `codex--battle`)
- [ ] UI: `Codex::Leaderboard::Table`
- [ ] `Rack::Attack` rules (60 votes/min, 120 attunements/h)
- [ ] Patch `PartitionMaintenanceWorker` — додати `codex_matches`
- [ ] Specs (model, service, worker, request, system)

### Phase 5: Discovery 🔓 (planned)
- [ ] Migration `CreateCodexDiscoveries`, `CreateCodexDiscoveryRules`
- [ ] Models `Codex::Discovery`, `Codex::DiscoveryRule`
- [ ] `Codex::DiscoveryEngine` (rule evaluator, Rails.cache)
- [ ] `Codex::DiscoveryProbeWorker` (queue `default`, presence-gated)
- [ ] Hook у `UnpackTelemetryWorker` finalizer (тільки якщо `presence?(user_for_tree)`)
- [ ] Endpoint: `GET /api/v1/codex/discoveries/me`
- [ ] UI: `Codex::Discovery::Toast` + Stimulus `codex--reveal`
- [ ] ActionCable `Codex::DiscoveryChannel`
- [ ] Admin endpoint: `POST/PATCH /api/v1/codex/admin/discovery_rules`
- [ ] Seeds: 12 початкових rules
- [ ] Specs

### Phase 6: Cross-domain stitch 🪡 (planned)
- [ ] `Codex::CitationPill` Phlex-компонент
- [ ] Endpoint: `POST /api/v1/codex/citations` (forester+)
- [ ] Інтеграція у `Tree::Show`, `Cluster::Show`, `OracleVisions::ForecastCard`, `EwsAlert::Row`
- [ ] Admin endpoint: `POST/PATCH /api/v1/codex/admin/nodes`
- [ ] Документ `docs/04_02` — Codex Services розділ
- [ ] Документ `docs/04_03` — повна таблиця ендпоінтів
- [ ] Wiki update + README "Lore layer" line

---

## 15. 📓 Session Log / ADR

> Кожна сесія додає короткий запис: дата, що зроблено, що відкладено і чому, посилання на коміти.

### 2026-05-09 (Session 1) — Specification & Phase 1 setup

- **Done:**
  - Створено цей SSOT-документ `docs/04_05_Codex_Lore_Module.md` з повним дизайном модуля та tracker'ом фаз.
  - Досліджено архітектуру `app/models/cluster.rb`, `app/views/components/clusters/{grid,show}.rb`, `app/policies/`, `config/routes.rb`, `db/structure.sql` для узгодження конвенцій.
  - Підтверджено: PK = bigint (не uuid); БД консолідована у `db/structure.sql` через одну `init_consolidated.rb` міграцію + всі нові міграції додаються як окремі файли; PostGIS + pg_trgm extensions присутні; Pundit + Pagy + Phlex 2.4 + Phlex-Rails 2.4 у стеку.
- **Decisions (ADR-CDX-1..6) зафіксовано в §1** — ключове: bigint PK, no STI, no i18n gem, no hot-path queues, sanitize markdown, no partitioning Node.
- **Deferred:** Phase 1 implementation продовжиться у наступній сесії.

### 2026-05-09 (Session 2) — Phase 1 implementation, full delivery

- **Done (full Phase 1):**
  - Schema: 3 таблиці згорнуті в один `init_consolidated.rb` після squash усіх попередніх incremental міграцій (per користувацький запит — у проді бази немає).
  - Models: `Codex::Realm`, `Codex::Node`, `Codex::Citation` + `Codex::ARCHETYPES` (79 keys) + `Codex::MarkdownRenderer` (Rails sanitizer, `rel`/`target` safelist, JS-scheme rewrite).
  - Pundit policies: ApplicationPolicy/Realm/Node/Citation. NodePolicy::Scope приховує чернетки для не-super_admin.
  - Blueprints: `Codex::RealmBlueprint`, `Codex::NodeBlueprint` (`:show` view).
  - Routes + controllers: `Api::V1::Codex::Realms#index`, `Nodes#index/show` (slug param). HTML рендерить через `DashboardLayout`. JSON оборачує Pagy в `{ data, pagy }`.
  - Phlex: `Codex::Index`, `Codex::Show`, `Codex::RealmTabs`, `Codex::NodeCard`. Усі — gaia-* токени, `Shared::UI::StatusBadge` з новим lifecycle mapping.
  - `Navigation::Sidebar` отримала 5-ту групу "Library" з пунктом Codex Atlas.
  - **Seeds — повний 79-record корпус** із вхідного списку Архітектора (32 ecosystem + 29 unique_tree + 8 protocol + 10 mythos), кожен з bilingual title, archetype mapping, geo (де відомі координати), lifecycle, lore narrative.
  - **Production-safe seeding**: окрема rake-таска `bin/rails codex:seed` через `Codex::NodeImportService` (idempotent UPSERT за slug, зберігає DAO-промотовані поля). Аналогічно винесено `seed_governance_system_parameters` міграцію в `bin/rails governance:seed_parameters`.
  - **Lookbook YARD noise fix**: `config/initializers/lookbook_yard_tags.rb` реєструє `@notes` тег.
  - Specs: 85 examples (model 38 / service 18 / policy 7 / request 12 / view 10) / 0 failures, відповідно до canon `docs/10_01`.
  - Docs sync: `04_01` (model count + Codex section + Карта Зв'язків + pg_trgm), `04_02` (Codex services), `04_03` (3 endpoints), `04_04` (StatusBadge + Sidebar + Codex Phlex registry), `10_03` (coverage matrix — models/services/controllers/policies/views).
- **Bug-fixes виявлені під час спек-прогону:**
  - `Codex::Node.for_realm(nil)` повертав `none` — виправлено на `all`, аналогічно `by_lifecycle/by_archetype` (nil = no-op).
  - `Codex::MarkdownRenderer` SAFE_ATTRS додано `rel`, `target` — інакше Rails sanitizer стрипав їх з outbound links.
  - `db/structure.sql`: видалено директиву `SET transaction_timeout = 0;` (PG17-only) — на користувачевих PG16 це fail. Використовується тільки `idle_in_transaction_session_timeout`.
- **Deferred:**
  - `User has_many :codex_citations` — додасться разом із `POST /codex/citations` ендпоінтом у Phase 6.
  - Фази 3-6 ідуть окремими PR.

### 2026-05-09 (Session 3) — Phase 2 implementation, Community layer

- **Done (full Phase 2):**
  - Schema: одна нова міграція `20260509130000_create_codex_community_tables.rb` (post-squash convention) → 2 таблиці (`codex_comments` polymorphic + self-FK + soft-hide; `codex_attunements` UNIQUE per user+node з DB CHECK `intensity BETWEEN 1 AND 5`). Counter columns уже були. `db/structure.sql` оновлено (5699 → 5908 рядків).
  - Models: `Codex::Comment` з кастомними валідаціями `parent_must_be_top_level` + `parent_must_share_commentable` (одно-рівневий тред + integrity counter cache); `Codex::Attunement` з `INTENSITY_RANGE`/`QUOTE_MAX` константами та counter_cache.
  - User додано `has_many :codex_comments, dependent: :restrict_with_error` (модерація-trail) + `:codex_attunements, dependent: :destroy`.
  - Pundit: `CommentPolicy` (own ≤ 24h або admin+ → `hide?` ≠ `destroy?`; Scope ховає hidden від не-admin), `AttunementPolicy` (write own-only).
  - Routes: nested під `nodes` (`POST /attunements`, `DELETE /attunements/me`, `POST /comments`).
  - Controllers: `AttunementsController#create` (`find_or_initialize_by` → idempotent re-POST оновлює) + `#destroy_me` (no-op safe); `CommentsController#create` (Idempotency-Key обов'язковий для JSON, 24h Rails.cache TTL, inline `ActionCable.server.broadcast`).
  - Worker: `Codex::AttunementBroadcastWorker` (queue `default` per ADR-CDX-4, retry 3) → public counter + private `attuned: bool` envelope.
  - Phlex: `Attunements::Toggle` + `Comments::{Thread,Item,Form}`, інтегровано в `Codex::Show` (нові props `current_user:`, `comments:`, `current_user_attuned:`). DOM ids `codex_node_<id>_comments` / `codex_comment_<id>` / `codex_node_<id>_attunement_count` — таргети для Solid Cable broadcasts.
  - Anti-abuse: `Rack::Attack` правила `codex/attunements` (120/h/actor) + `codex/comments` (60/10min/actor).
  - Specs: +75 нових examples (model 25 / policy 12 / request 14 / worker 5 / view 19) → загалом **160 examples / 0 failures**.
- **Bug-fix from Phase 1 caught during Phase 2 view-spec rendering:**
  - `Codex::Show` використовував `unsafe_raw` (метод не існує в Phlex 2.4 — лише `raw`); замінено на `raw safe(Codex::MarkdownRenderer.render(...))` у `show.rb` + `comments/item.rb`. Phase 1 рендер ніколи не виконувався у тестах (Show не було в spec coverage), тому баг проліз. Phase 2 додає Item spec який рендерить markdown — i зловив це одразу.
- **Spec-craft notes (для майбутніх phase авторів):**
  - Phlex view component тести під `Class.new(Component)` мусять also wrap nested рендерені компоненти через override `render` (приклад: `Comments::Thread` рендерить `Comments::Form`, тому test wraps both).
  - Для Rails 8 request specs з JSON body: `params: hash, as: :json` (НЕ `params: hash.to_json`); `as: :json` додатково виставляє `format.json?` так, щоб `respond_to format.json` гілка спрацьовувала замість `format.html { redirect_to ... }` → 302.
- **Deferred to subsequent phases:**
  - Stimulus controllers `codex--attune` / `codex--comment` (data-attributes виставлені, JS файли — у Phase 3+ batch razom з Fraction Picker)
  - Comment edit / hide UI endpoints (тільки create зараз; admin-hide через Phase 6 admin CRUD).
  - Solid Cable Turbo Stream `<turbo-cable-stream-source>` тег у Show — broadcasts вже працюють, рендер subscriber-тегу разом із Phase 4 `Battle::Arena` Stimulus refactor.

---
