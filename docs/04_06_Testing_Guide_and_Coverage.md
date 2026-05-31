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
- **Відкрите:** test-coverage gaps / відкриті ризики (§B.4) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`04_04` — Phlex UI and Tailwind](04_04_Phlex_UI_and_Tailwind) | Phlex UI (Частина A — view-component best practices) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Сервіси (Частина B — service coverage) |
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | Моделі (B.1.1 model coverage) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (coverage gaps, §B.4) |

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
- [B.1 RSpec Coverage Matrix](#b1-rspec-coverage-matrix)
- [B.2 Firmware Test Coverage](#b2-firmware-test-coverage)
- [B.3 Solidity Test Coverage (Foundry)](#b3-solidity-test-coverage-foundry)
- [B.4 Відомі обмеження та відкриті ризики](#b4-відомі-обмеження-та-відкриті-ризики)
- [B.5 Рекомендації для нових фіч](#b5-рекомендації-для-нових-фіч)
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

# Частина B — Test Coverage Matrix & Gap Analysis

## B.1 RSpec Coverage Matrix

> **Конвенція:** покриття фіксується статусом (🟢/✅) + нотатками про охоплені кейси, **без** лічильників кількості прикладів/тестів — такі числа дрейфують з кожним доданим прикладом і їх неможливо тримати в правильному стані. Числові значення лишаємо лише структурні/порогові (напр. «min 8 examples», «ratio ≥ 1.5×», пороги SimpleCov).

### B.1.1 Models

| Модель | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| Tree | ✅ | 🟢 Повне | AASM, scopes, associations, bio_status enum |
| Wallet | ✅ | 🟢 Повне | lock_and_mint!, credit!, pessimistic lock |
| BlockchainTransaction | ✅ | 🟢 Повне | AASM transitions, partition pruning |
| User | ✅ | 🟢 Повне | Argon2, roles, OAuth, MFA |
| Gateway | ✅ | 🟢 Повне | AASM, mark_seen!, online? |
| HardwareKey | ✅ | 🟢 Повне | AES key encryption, LRU cache, **[SEC.11] `lorenz_seed_hex` validation, `binary_lorenz_seed` AR Encryption non-deterministic** |
| EwsAlert | ✅ | 🟢 Повне | Alert types, severity levels |
| TelemetryLog | ✅ | 🟢 **Повне** | **oracle_status enum, associations, in_timeframe/vandalized scopes, bio_status enum** |
| TreeFamily | ✅ | 🟢 **Повне** | **attractor_thresholds (optimal key FW.8), effective_optimal_z_target, biological_properties** |
| Cluster | ✅ | 🟢 **Повне** | **lorenz_overrides_by_species validation (FW.8), lorenz_overrides_for, Associations, store_accessor validations, recalculate_health_index! with AiInsight, alphabetical scope** |
| AuditLog | ✅ | 🟢 **Повне** | **chain_payload determinism, metadata ordering, tamper detection, deleted record chain break, bulk advisory lock** |
| **Firmwareable (concern)** | ✅ | 🟢 **Повне** | **AASM transitions тестуються: всі 7 подій, invalid transitions, lifecycle** |
| **Codex::Realm** [Codex Phase 1] | ✅ | 🟢 **Нове** | **`ordered` scope, bilingual `name(locale)`, slug uniqueness, accent_token validation, has_many :nodes** |
| **Codex::Node** [Codex Phase 1] | ✅ | 🟢 **Нове** | **slug normalization (downcase, `_` → `-`), CODEX_UID format guard (CDX-{ECO\|TRE\|PRT\|MYT}-NNNN), bilingual title helpers, lifecycle/seed_origin enums (prefix), `for_realm`/`search_title` (pg_trgm ILIKE)/`by_archetype`/`by_lifecycle`/`ordered_by_elo` scopes, `sync_geo_point` PostGIS hook (lat/lng → SRID=4326 POINT), `external_refs` array-of-hashes validator, archetype_key inclusion in `Codex::ARCHETYPES` (79 keys), Active Storage `cover_image`+`gallery`** |
| **Codex::Citation** [Codex Phase 1] | ✅ | 🟢 **Нове** | **polymorphic citable, anti-dup unique index (codex_node_id, citable_type, citable_id), counter cache → Codex::Node.citation_count** |
| **Codex::Comment** [Codex Phase 2] | ✅ | 🟢 **Нове** | **polymorphic commentable, BODY_MAX (2 KiB) cap, FLAG_REASONS allow-list, parent_must_be_top_level (rejects reply-to-reply), parent_must_share_commentable (rejects cross-node parent), counter cache → comments_count, scopes (visible/hidden/top_level/chronological), `editable_by?(user)` 24h grace, soft-hide via hidden_at + hidden_by_admin** |
| **Codex::Attunement** [Codex Phase 2] | ✅ | 🟢 **Нове** | **INTENSITY_RANGE (1..5) валідація + DB CHECK, QUOTE_MAX (280) length, UNIQUE (user_id, codex_node_id) на model + DB, counter cache → attunement_count, before_validation default_started_at, scopes (for_node/for_user/ordered)** |
| **Codex::Fraction** [Codex Phase 3] | ✅ | 🟢 **Нове** | **UNIQUE user_id (DB-level race-proof), node_lifecycle_pickable validator (rejects destroyed/extinct, allows mythical), `COOLDOWN = 7.days`, helpers cooldown_active?/cooldown_until/seconds_until_unlocked, scopes ordered/by_archetype, archetype_key denormalisation** |
| **Codex::Match** [Codex Phase 4] | ✅ | 🟢 **Нове** | **Composite PK `(id, created_at)` (RANGE-partitioned), 4 валідатори (winner_in_pair, left ≠ right, same-realm, pair_seed presence), scopes for_user/for_realm/recent, skip? helper, FKs without cascade (audit-grade)** |
| **Codex::Discovery** [Codex Phase 5] | ✅ | 🟢 **Нове** | **valid factory, UNIQUE `(user_id, codex_node_id)` validation message, `trigger_type` enum prefix `triggered_by_*`, polymorphic `trigger_ref` (loose, no FK), `before_validation :default_unlocked_at on: :create`, scopes `for_user`/`recent`, counter_cache increments `codex_nodes.discovery_count`** |
| **Codex::DiscoveryRule** [Codex Phase 5] | ✅ | 🟢 **Нове** | **valid factory, presence + `≥ 1` threshold validation, `params_must_be_hash` rejects non-Hash, scopes `active_only`/`for_condition`, `cached_active_by_condition` lazy `Rails.cache.fetch` returns rules grouped by condition_type (active-only), `after_commit :bust_cache` invalidates the cache** |

### B.1.2 Services

| Сервіс | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| BlockchainMintingService | ✅ | 🟢 Повне | batchMint, guard clauses, binary search |
| TelemetryUnpackerService | ✅ | 🟢 **Повне** | **check_z_divergence! (effective_lorenz_thresholds FW.8), update_health_streak!, boundary sensors, acoustic overflow, [FW.5] delta_t/vcap β-perturbation, [SEC.11] per-tree warm/cold dispatch, lorenz_state persist, MissingLorenzSeedError, cold_start_flag, [FW.31] numeric tolerance band feature-flag, [SEC.10] panic Frame Counter anti-replay (fresh accept, replay reject via Redis SETNX, distinct counters/DIDs accepted, non-panic skip, legacy counter=0 skip, FW.22 firmware_id coexistence, TTL ≈ 25h guard), [FW.2 / ARCH.42, 2026-05-24] CCM 25-byte path (feature-flagged `ENV TELEMETRY_CCM_ENABLED`: happy decrypt, MIC tamper, CT tamper, FC replay reject, cross-DID FC reuse accept, Queen sentinel drop, short chunk skip, sensor noise reject, growth_points credit, feature flag off → ECB fallback, ENV roundtrip)** |
| InsightGeneratorService | ✅ | 🟢 Повне | Fraud guard, cleanup_old_logs! |
| SilkenNet::Attractor | ✅ | 🟢 Повне | Float precision, deterministic chaos, **[FW.5] perturb_beta, parity-fuzz 500 cases (0 mismatches), [SEC.11] sole `calculate_z_from_state` API (legacy `calculate_z(seed,…)` removed)** |
| **SilkenNet::SeedDerivation** [SEC.11] | ✅ | 🟢 **Нове** | **HKDF-SHA256 (RFC 5869) + HMAC-SHA256 + signed-unit-float unpack; raises `SecurityError` без `PROVISIONING_MASTER_KEY`; firmware-equivalence vectors з `firmware/test/test_seed_derivation.c`; daily epoch_day rotation; (x₀,y₀,z₀) ∈ [-1,+1]³ deterministic** |
| **Cryptography::LoraCcm** [FW.2 / ARCH.42] 🆕 | ✅ | 🟢 **Нове (2026-05-24)** | **AES-128-CCM encrypt/decrypt helper для LoRa Soldier↔Queen 24B packet. Golden vector parity з firmware host tests (`test_ccm.c`). Input validation (key 16B, DID 4B, FC uint32, payload 8B, MIC 8B). Tamper rejection: MIC, ciphertext, AAD DID, AAD FC, wrong key. 12-byte nonce = DID‖FC‖4×0x00; 8-byte AAD = DID‖FC; 8-byte tag (NIST SP 800-38C `t=8`).** |
| BlockchainBurningService | ✅ | 🟢 **Повне** | **SLASHER_KEY fallback (E.2), Prometheus SCC_SLASHED_TOTAL, AiInsight+source_tree combined ratio, damage_ratio cap** |
| Treasury::MonitorService | ✅ | 🟢 **Повне** | **build_config, missing credentials, humanize edge cases, multiple alerts** |
| TreeChronicleService | ✅ | 🟢 **Повне** | **Pagination edges, nil wallet, boundary stress_index, mixed sources** |
| Chainlink::OracleDispatchService | ✅ | 🟢 **Повне** | **WEB3_STRICT_MODE, missing DON_ID, nil payload fields, ABI validation, [S6.15] Web3::ChainlinkRouterVersion delegation + bytecode probe + graceful fallback + probe-disabled mode** |
| **Web3::ChainlinkRouterVersion** [S6.15] | ✅ | 🟢 **Нове** | **active_version (default v1, blank ENV, unsupported raise), abi_for(:v1) shape + 5 inputs, selector_for(:v1) = `0x461d2762`, signature_for canonical, fallback_for(:v1) = nil (oldest), selector_present_in_code? (case-insensitive substring, blank/nil tolerant), supported?** |
| AlertDispatchService | ✅ | 🟢 **Повне** | **Adaptive thresholds, silence keys, rate limiting (SEC.10), voltage/fire boundaries, EmergencyResponseService call** |
| HardwareKeyService | ✅ | 🟢 **Повне** | **HKDF SHA256/info/salt params, key length, derive_device_key logging, provision conflict** |
| MintingRollbackService | ✅ | 🟢 **Повне** | **Solana tx status, receipt edge cases, Celo routing, locked_points nil fallback, invalid ISO8601** |
| EmergencyResponseService | ✅ | 🟢 **Повне** | **Mixed valve+siren fire response, command attributes (org_id, idempotency, priority, expires_at), online/offline gateway filter** |
| OtaPackagerService | ✅ | 🟢 **Повне** | **[FW.8] build_threshold_config_block (CMD_SET_THRESHOLDS 0x9A, CRC16, species_id, effective_lorenz_thresholds); [FW.23] compute_hmac_tag (deterministic + anti-replay через version_id + anti-truncation через total_chunks + per-cluster K_ota isolation), build_hmac_trailer_chunks (3× 16-byte LoRa-формат, 0x9B marker, seg_idx 1/2/3 BE, payload reconstructs 32-byte HMAC), prepare(cluster_id:) opt-in (3 trailer chunks appended, manifest exposes lora_total_chunks/hmac_signed/hmac_cluster_id, backward-compat без cluster_id); LoRa MTU chunks, single-byte payload, exact block-size, CRC16 known vectors, manifest format** |
| **OtaHmacKeyService [FW.23]** | ✅ | 🟢 **Нове** | **HKDF-SHA256 derivation з info `"silken-ota-hmac-v1"` (domain separation від HardwareKeyService AES key); deterministic per cluster_id; ArgumentError на blank cluster_id; SecurityError без `PROVISIONING_MASTER_KEY` (SEC.11 hard cutover, no SecureRandom fallback); fetch_binary_for повертає 32-byte ASCII-8BIT** |
| Etherisc::ClaimService | ✅ | 🟢 **Повне** | **nil policy_id, missing ENV keys, ABI validation** |
| Ed25519Crypto::SigningService | ✅ | 🟢 **Повне** | **Empty/large messages, hex validation edges, uppercase hex, nil/integer message coercion** |
| **Codex::NodeImportService** [Codex Phase 1] | ✅ | 🟢 **Нове** | **empty seed dir Result success?, minimal YAML upsert, idempotent re-run (no duplicates), DAO `seed_origin` preservation, per-file error isolation, full 79-record corpus load (4 realms + 79 nodes from default SEED_ROOT)** |
| **Codex::MarkdownRenderer** [Codex Phase 1] | ✅ | 🟢 **Нове** | **nil/blank → html_safe empty, paragraphs, h1/h2/h3 → h2/h3/h4 mapping, bold/italic/code/lists/blockquotes, safe http(s) links з `rel="noopener noreferrer" target="_blank"`, `javascript:` scheme rewrite to `#`, `<script>` tag stripping via `Rails::HTML5::SafeListSanitizer`, raw HTML escape-then-transform** |
| **Codex::FractionChangeService** [Codex Phase 3] | ✅ | 🟢 **Нове** | **happy path initial pick (denorm archetype_key + house_color_token, enqueue audit, chosen_at = last_changed_at), happy path re-pick (chosen_at immutable, last_changed_at refreshed, previous_node_id captured), cooldown_blocked Result-struct API, lifecycle rejection (extinct/destroyed), unsaved user/node guards** |
| **Codex::EloMath** [Codex Phase 4] | ✅ | 🟢 **Нове** | **expected(left, right) win probability (0.5 для рівних, > 0.6 при +200 Elo), zero-sum deltas, upset reward (delta_underdog > delta_favourite), decay threshold (K halves once both nodes pass match_count > 30), ArgumentError for bad winner symbol** |
| **Codex::PairSelectorService** [Codex Phase 4] | ✅ | 🟢 **Нове** | **happy path (HMAC seed shape `\A[0-9a-f]{64}\z` + same-realm distinct nodes), Redis seed storage під codex:pair_seed:<seed> + TTL 5 хв, default realm fallback, < 2 pickable nodes failure, no-realm failure, unsaved user, Elo bucketing invariant (для cluster anchors діє ±200)** |
| **Codex::VoteRecorderService** [Codex Phase 4] | ✅ | 🟢 **Нове** | **winner pick → Match.create + EloRecomputeWorker enqueue + zero-sum deltas, skip recording (0/0 deltas + row), replay protection (seed DEL on first use, second call → seed_invalid_or_consumed), missing seed, winner_not_in_pair, seed_user_mismatch (stolen-seed defence)** |
| **Codex::PresenceTracker** [Codex Phase 5] | ✅ | 🟢 **Нове** | **touch + observers SET semantics (idempotent on duplicate), `leave`, TTL refresh (between 1 and `TTL.to_i` seconds), Redis `CannotConnectError` resilience (returns `[]`/`false`, never raises), blank-input no-op** |
| **Codex::DiscoveryEngine** [Codex Phase 5] | ✅ | 🟢 **Нове** | **no-rules baseline → `[]`, `match_count` adapter happy + below-threshold + `realm_slug` filter, idempotent skip when Discovery already exists, unknown `condition_type` → no-op (no raise), guard rail: unsaved user → `[]`** |
| **Codex::DiscoveryRuleImportService** [Codex Phase 5] | ✅ | 🟢 **Нове** | **missing YAML returns zeros, idempotent UPSERT-by-name (re-run flips created → updated counter, no row count change), unknown `node_slug` skipped + warn-logged, fallback to `User.oracle_executioner` коли `created_by_user_email` не знайдений** |

### B.1.3 Workers

| Воркер | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| UnpackTelemetryWorker | ✅ | 🟢 **Повне** | **Sentry tags, broadcast_raw_hex format, gateway.mark_seen! IP/timestamp, sidekiq config** |
| Governance::ParameterSyncWorker | ✅ | 🟢 Повне | |
| InsurancePayoutWorker | ✅ | 🟢 **Повне** | **Sidekiq config, satellite mixed alert types, severe_drought block, Etherisc recovery** |
| ActuatorCommandWorker | ✅ | 🟢 **Повне** | **dispatch! AASM transition, mark_active!, encryption roundtrip, ResetActuatorStateWorker scheduling, sidekiq config** |
| **Web3CircuitBreaker (concern)** | ✅ | 🟢 **Повне** | **transient_cause?, reset_circuit!, remaining_open_seconds, all error types, record_failure! threshold** |
| **CoapEncryption (concern)** | ✅ | 🟢 **Повне** | **[FW.20] TIME_SYNC envelope (0x9C marker + ts:4 big-endian), All mod-16 payload sizes (1,15,17,31,32,33), binary data, null-byte padding, IV uniqueness** |
| **Codex::AttunementBroadcastWorker** [Codex Phase 2] | ✅ | 🟢 **Нове** | **sidekiq_options queue=`default` retry=3, public broadcast `codex_node_<id>_attunements` з пост-commit лічильником, private envelope `codex_node_<id>_attunements_user_<uid>` з `attuned: bool`, no-op для unknown node, `attuned: false` після видалення attunement** |
| **Codex::FractionAuditWorker** [Codex Phase 3] | ✅ | 🟢 **Нове** | **sidekiq_options queue=`default` retry=3, AuditLog write з action="codex.fraction.chosen" + auditable_type=Codex::Fraction + metadata (codex_node_id, archetype_key, previous_node_id, changed_at), no-op для users without organization_id (per-org ledger guarantee), no-op для unknown user/fraction id** |
| **Codex::EloRecomputeWorker** [Codex Phase 4] | ✅ | 🟢 **Нове** | **sidekiq_options queue=`low` retry=3 (ADR-CDX-4 — Battle never blocks Proof-of-Growth), atomic `UPDATE … SET col = col + ?` для обох nodes у транзакції (no SELECT-then-UPDATE race), sequential calls accumulate коректно, unknown id no-op (update_all returns 0)** |
| **Codex::DiscoveryProbeWorker** [Codex Phase 5] | ✅ | 🟢 **Нове** | **sidekiq_options queue=`default` retry=3 (ADR-CDX-4 — Discovery cosmetic), no-op коли Engine returns `[]` (Discovery.count unchanged), happy path → `find_or_create_by` Discovery + ActionCable broadcast on `codex:discoveries:user:<id>` з payload `{slug, title_en, title_uk, archetype_key, trigger_type, unlocked_at}` + payload polymorphic ref persisted, race-safe idempotency через `previously_new_record?` (no double-broadcast при concurrent perform), unknown user_id swallowed without raise** |

### B.1.4 Controllers

Усі API v1 контролерів мають відповідні request spec файли. Покриття: 🟢 Повне.

**Codex Phase 1 (нове):**
- `Api::V1::Codex::RealmsController#index` — 401 без token, ordered by `position`, bilingual JSON shape
- `Api::V1::Codex::NodesController#index` — 401 guard, sorted `attunement_elo DESC`, фільтри `realm` / `lifecycle_status` / `q` (trigram)
- `Api::V1::Codex::NodesController#show` — slug-routing, atomic `view_count` increment, 404 для unknown slug + draft-приховування для не-super_admin

**Codex Phase 2 (нове):**
- `Api::V1::Codex::AttunementsController#create` — 401 guard, idempotent re-POST оновлює row (не дублює), counter cache інкремент, worker enqueue, validation 422 для intensity > 5, 404 для unknown slug
- `Api::V1::Codex::AttunementsController#destroy` — DELETE removes own + broadcasts; safe no-op коли немає рядка; ніколи не видаляє чужий attunement
- `Api::V1::Codex::CommentsController#create` — 401 guard, comments_count інкремент, ActionCable broadcast у `codex_node_<id>_comments`, body_html у відповіді (sanitised markdown), `Idempotency-Key` 400 коли пропущено для JSON, retry з тим же ключем повертає cached response, 422 для body > BODY_MAX, parent_id support

**Codex Phase 3 (нове):**
- `Api::V1::Codex::FractionsController#create` — 401 guard, 201 + Blueprint на initial pick, FractionAuditWorker enqueue, 429 + cooldown_until ISO коли cooldown active, 404 unknown slug, 422 на extinct/destroyed lifecycle
- `Api::V1::Codex::FractionsController#me` — 401 guard, 204 коли fraction nil, 200 + Blueprint payload коли set
- `Api::V1::Codex::FractionsController#picker` — 401 guard, HTML frame render з активним realm + node title

**Codex Phase 4 (нове):**
- `Api::V1::Codex::MatchesController#new` — 401 guard, frame render з hidden `pair_seed` 64-hex, empty-state 422 коли realm < 2 pickable nodes
- `Api::V1::Codex::MatchesController#create` — 401 guard, 201 + Blueprint + EloRecomputeWorker enqueue + Match.count change, 403 `seed_invalid_or_consumed` на replay, skip=true support
- `Api::V1::Codex::LeaderboardController#index` — public (no auth), JSON sorted by Elo desc, HTML table render, limit clamp

**Codex Phase 5 (нове):**
- `Api::V1::Codex::DiscoveriesController#me` — 401 guard, JSON sorted by `unlocked_at DESC` (own-only via Pundit Scope), HTML render з `codex_discoveries_collection` DOM id, empty-state copy "Nothing unlocked yet"
- `Api::V1::Codex::Admin::DiscoveryRulesController` — index 403 для non-admin / 200 для admin, create 403 / 201 + JSONB `params` round-trip + `created_by_user_id` set / 422 на invalid `threshold_value`, update 200 + cache bust verified (engine returns no rules після `active=false`), destroy 204

### B.1.5 Policies

Усі Pundit policies покриті. Покриття: 🟢 Повне.

**Codex base (нове):**
- `Codex::ApplicationPolicy` — read-all default для будь-якого autenticated, anonymous deny на index?/show?, `create?/update?/destroy?` deny-by-default для всіх ролей включно з super_admin (потребує opt-in від subclass), `Scope#resolve` повертає `scope.all` без неявного фільтра, наслідує `::ApplicationPolicy::Scope` initializer
- `Codex::RealmPolicy` — read auth-only, `Scope#resolve` ховає `is_active = false` realm'и в т.ч. від super_admin (no admin escape hatch у Phase 1), writes inherited deny defaults
- `Codex::CitationPolicy` — read auth-only / anonymous deny, `create?` обмежений forester+ (operational-tier guard, investor deny), `update?/destroy?` owner-within-24h grace OR admin+ override (стара цитата без admin → deny, чужа цитата без admin → deny, admin bypass на foreign + post-grace), документує: anonymous user не повинен досягати policy в production (controller `:authenticate_user!` короткозамикає 401)

**Codex Phase 1 (нове):** `Codex::NodePolicy` — index?/show? для будь-якого автентифікованого, anonymous deny, write-операції тільки для super_admin, `Scope#resolve` приховує чернетки (`published_at IS NULL`) для не-super_admin.

**Codex Phase 2 (нове):**
- `Codex::CommentPolicy` — index/show only for auth, hidden ховається від не-admin, create для всіх auth, update/destroy для автора в межах EDIT_GRACE або admin+, hide? тільки admin+, Scope ховає hidden від non-admin
- `Codex::AttunementPolicy` — read для auth, write own-only, anonymous deny на create

**Codex Phase 3 (нове):** `Codex::FractionPolicy` — index/show/create для будь-якого автентифікованого, anonymous deny, update/destroy own-only. Cooldown business-rule НЕ в policy (живе в `FractionChangeService`).

**Codex Phase 4 (нове):** `Codex::MatchPolicy` — index/create для будь-якого autenticated; anonymous deny на index/create; show only on own record; Scope ховає чужі матчі та returns none для anonymous. Throttling — Rack::Attack, не policy.

**Codex Phase 5 (нове):**
- `Codex::DiscoveryPolicy` — index? auth-only, show? own-only, create?/manual? admin+ only, Scope returns own collection / none для anonymous
- `Codex::DiscoveryRulePolicy` — usual / admin / super_admin × index/show/create/update/destroy → 403 для non-admin, 200 для admin+, Scope returns all для admin / none для non-admin / none для anonymous

### B.1.6 Views

Усі Phlex-компоненти покриті згідно з Частиною A цього документа.

**Codex Atlas page-level components (нове):**
- `Codex::RealmTabs` — `aria-label="Codex realm filter"` `<nav>` shell, `All`-tab count = sum(nodes_counts.values), per-realm tabs link to `api_v1_codex_nodes_path(realm: slug)`, active-state `aria-current="page"` + `border-gaia-primary`/`text-gaia-primary` token swap, default counts to `0` для realm'ів відсутніх у `nodes_counts`, empty-realm collection renders just `All`-tab, design system compliance (no `bg-white`/`text-gray-*`), `focus-visible:ring-2 focus-visible:ring-gaia-primary` on every anchor (a11y)
- `Codex::Index` — header (`Lore Layer` eyebrow + `Codex of Archetypes` heading + `<n> archetypes catalogued` from `pagy.count`), EmptyState branch ("Codex is silent…", grid suppressed), populated grid (`grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4` + one `Codex::NodeCard` per node), RealmTabs sub-component wired with both realms + active slug, `realm_counts` fallback to `Codex::Node.group(:codex_realm_id).count` when `nodes_counts: nil`, design-system tokens compliance (`border-gaia-border`)
- `Codex::Show` — hero (codex_uid eyebrow, bilingual title `title_uk`/`title_en`, `subtitle_en` opt-out when blank, `realm.name_en` watermark), three-column lore (`Context`/`Cyber Meaning`/`Lore` headings only when `*_md` present, transforms via `Codex::MarkdownRenderer` → `<strong>` + `rel="noopener noreferrer"`), aside metadata panel (`Realm`/`Archetype`/`Geo Region`/`Discovered`/`Cited By`/`Attunement`/`Elo` rows + em-dash коли `geo_region` blank), external_refs list (`<a target="_blank" rel="noopener noreferrer">` per ref, label-or-URL fallback, block hidden when array empty), `Codex::Attunements::Toggle` wiring (`Attune` ↔ `Attuned` label switch driven by `current_user_attuned`, `attunement_count` round-trip), gaia-* tokens compliance (`border-gaia-border`, `bg-gaia-surface`, no raw `bg-white`)

**Codex Phase 1 (нове):** `Codex::NodeCard` — bilingual title rendering, codex_uid + realm pill + lifecycle badge (status-* token), slug-based href, footer (Elo + geo_region), edge cases (placeholder glyph коли `cover_image` не attached, `—` коли `geo_region` blank, suppress subtitle), design system compliance (no raw `bg-white`/`text-gray-*`, custom text-scale `mini`/`tiny`/`micro`, `focus-visible:ring-2`).

**Codex Phase 2 (нове):**
- `Codex::Attunements::Toggle` — DOM id `codex_node_<id>_attunement_count`, "Attune"/"Attuned" label switch + POST/DELETE method override, Stimulus `codex--attune` data values, success token коли attuned, focus-visible accessibility, no raw `bg-white`/`text-gray-*`
- `Codex::Comments::Thread` — DOM id `codex_node_<id>_comments` (broadcast target), empty-state copy, composer renders only коли current_user present, Stimulus controller wiring, gaia-* tokens
- `Codex::Comments::Item` — DOM id `codex_comment_<id>`, sanitised markdown render, ISO timestamp, hidden-state notice (без body), gaia-* tokens

**Codex Phase 3 (нове):**
- `Codex::Fractions::Card` — empty-state CTA коли fraction nil, filled state з archetype + Since-date + "Change" + Cooldown pill, gaia-* tokens compliance (no `bg-white`/`text-gray-*`)
- `Codex::Fractions::Picker` — header/realm-tabs/grid render, active realm highlight (`bg-gaia-primary`), Current marker для own fraction, disable-button + "Locked" коли cooldown active на іншому node, empty-state для пустого realm, tokens compliance

**Codex Phase 4 (нове):**
- `Codex::Battle::Arena` — frame render з двома cards + VS divider + hidden seed inputs + Elo & match counters, error-state pill коли service signals "not enough nodes" (без winner_slug форм), gaia-* tokens compliance, Stimulus `codex--battle` controller + `card`/`form`/`skip` targets wired
- `Codex::Leaderboard::Table` — header + Top-N caption + ordered rows ("Apex" before "Mid"), empty-state copy ("No ranked nodes yet."), gaia-* tokens compliance

**Codex Phase 5 (нове):**
- `Codex::Discoveries::Toast` — title + archetype_key + trigger label dispatch + `data-controller="codex--reveal"` data-attribute + slug-based href + `HH:MM UTC` formatted unlocked_at; gaia-* tokens compliance (no `bg-white`/`text-gray-*`); each trigger_type → label mapping (Observed/Battle/Pact/Streak/Oracle/Granted)
- `Codex::Discoveries::List` — empty-state copy ("Nothing unlocked yet — observe a tree, vote in the Arena, choose a fraction") + `Unlocked: 0` counter, populated grid renders title/archetype/trigger_type per discovery card + `Unlocked: 2` counter, gaia-* tokens compliance

**Codex Phase 6 (нове):**
- `Codex::Citation` — `for_target` polymorphic scope, `bulk_for(targets)` N+1-free Hash[[type, id]], `within_edit_grace?` 24 h boundary (nil-safe), User has_many :codex_citations restrict_with_error
- `Codex::CitationBlueprint` — denormalised node_slug/title_en/archetype_key, defensive nil-safe коли `citation.node` зник
- `Codex::Admin::NodePolicy` — index/show admin+ allow / forester+investor deny, update? admin+ allow, create?/destroy? super_admin only (admin denied), Scope returns all для admin / none для investor/forester/anonymous
- `Api::V1::Codex::Citations` — unauthenticated 401, investor 403, forester+ 201 з broadcast `codex_citations:Tree:<id>` + counter increment, replay 200 з cached payload, Idempotency-Key 400, bogus citable_type 400, DB-UNIQUE 422, DELETE own ≤24h 204 + broadcast op:remove, non-author forester 403, admin+ bypass past grace
- `Api::V1::Codex::Admin::Nodes` — forester GET 403, admin GET 200 list, admin PATCH 200 update, invalid lifecycle 422 (Rails 8 enum ArgumentError rescued), forester PATCH 403, plain admin POST 403 (super_admin only), super_admin POST 201 з seed_origin: dao_proposal, plain admin DELETE 403
- `Codex::Citations::Pill` — slug-href anchor + title + archetype glyph, aria-label з note, defensive nil-node noop, gaia-* tokens (no `bg-white`/`text-gray-*`), focus-visible:ring-2
- `Codex::Citations::Strip` — empty-state copy + DOM id `codex_citations_<type>_<id>`, populated render Pills with slug-href, gaia-* tokens compliance
- `Codex::DiscoveryEngine` — `acoustic_class_count` inert when no organization_id, `cluster_visited` inert when params['cluster_name'] missing, `firmware_version_seen` inert when no firmware row matches version, replaced "unknown condition_type" gate з "inert below-threshold" + ADAPTERS-stubbed missing-adapter path
- `Codex::EloRecomputeWorker` — Phase 6 cross-domain probe enqueues match_milestone з most-recent Match resolved by left/right id, no-op коли немає Match, swallows Redis::CannotConnectError (Elo update is the contract)
- `Codex::FractionChangeService` — Phase 6 fraction_choice probe on initial pick (previous_node_id: nil), carries previous_node_id on re-pick, swallows Redis::CannotConnectError
- `Api::V1::Codex::Attunements` — Phase 6 attunement_streak probe enqueued alongside AttunementBroadcastWorker

### B.1.7 Integration Tests

| Тест | Покриття | Критичність |
|------|----------|------------|
| telemetry_ingestion_pipeline | 🟢 | Proof of Growth uplink |
| blockchain_minting_burning_flow | 🟢 | SCC minting + slashing |
| wallet_tokenomics_flow | 🟢 | Growth points → SCC |
| proof_of_growth_chaos_engineering | 🟢 | Fault tolerance |
| ota_firmware_flow | 🟢 | OTA lifecycle + **[FW.23] e2e dual-gate** (backend-signs trailer chunks, manifest lora_total_chunks cross-check, HMAC reconstruct backend↔soldier match, magic+hmac both-pass acceptance, anti-tamper bytecode flip rejection, anti-replay version_id mismatch, anti-truncation total_chunks mismatch) |
| gateway_lifecycle | 🟢 | Gateway AASM |
| user_auth_lifecycle | 🟢 | Auth + MFA + OAuth |
| emergency_response_flow | 🟢 | EWS pipeline |
| audit_log_chain_integrity | 🟢 | Audit tamper detection |
| **fw8_threshold_governance** [FW.8] | 🟢 **Нове** | **3-tier effective_lorenz_thresholds, cluster override > tree_family > global, build_threshold_config_block CRC16, lorenz_overrides_by_species validation, coap_encryption FW.20 envelope** |
| **provisioning_e2e** [FW.1] | 🟢 **Нове** | **HKDF determinism (firmware-equivalence), atomic Tree/HardwareKey/MaintenanceRecord, Ed25519 persist, TRL4 vs HKDF response shape, SEC.11 production guard, FW.24 magic guard, duplicate UID без mocks `HardwareKeyService`** |

---

## B.2 Firmware Test Coverage

### B.2.1 Soldier (test_soldier_logic.c)

| Область | Покриття |
|---------|----------|
| Payload Pack/Unpack | 🟢 Повне |
| Mesh Dedup (Anti-pingpong, 3-slot FW.21) | 🟢 Повне |
| OTA Chunk Assembly + CRC32 | 🟢 Повне |
| Bio-Contract Byte Parse | 🟢 Повне |
| Panic Payload | 🟢 Повне — **[FW.29]** `test_panic_flag_set_in_emergency_payload`, `test_normal_payload_panic_flag_clear`, **[FW.29 follow-up]** `test_fw29_status_byte_panic_with_max_growth_points` (0xFF boundary masking), `test_fw29_panic_does_not_corrupt_acoustic_saturation` (saturation @ 255 + panic flag незалежні) |
| OnRxDone Size Validation | 🟢 Повне |
| Lorenz State Persistence (FW.6) | 🟢 Повне |
| Acoustic Saturating Increment (FW.22) | 🟢 Повне — включаючи atomic snapshot (FW.28) |
| RSSI Clamping | 🟢 Повне |
| EMA Filter (FW.21) | 🟢 Повне |
| **[FW.5 B+] EMA → mruby args[5..6]** | 🟢 **Нове** — cold-boot baseline defaults (60 s / 3300 mV), warmup-phase defaults, post-warmup EMA forwarding, boundary clamps (vcap=5500, dt=1, zero-input) |
| DID Generation (FW.24) | 🟢 Повне — **[FW.24]** `test_did_hrng_fallback_not_magic` |
| **[FW.1] Flash Key Loading** | 🟢 **Нове** | `Load_AES_Key()` magic check, key-not-provisioned → Error_Handler, FLASH_KEY_ADDR 0x0803E000 |
| **[SEC.11 / FW.30] Flash Seed Loading** | 🟢 **Нове** — `Load_Lorenz_Seed()` magic check ("LSED"), provisioned/unprovisioned/wrong magic/zero seed, non-fatal (без Error_Handler) |
| **[SEC.11 / FW.30] Cold-Start Derivation** | 🟢 **Нове** — `Derive_Cold_Start_State()` coordinates ∈ [-1,+1], deterministic, date-sensitive, seed-sensitive |
| **[FW.30] C-Bridge 7-Arg Signature** | 🟢 **Нове** — Lorenz iteration з 7-arg сигнатурою produces finite coords |
| **[SEC.10] Panic Frame Counter Anti-Replay** | 🟢 **Нове (2026-05-03)** — DR0 packed pack/unpack roundtrip + independence; counter increments before TX; BE order у PAD[14..15]; saturating @ 0xFFFF; cold-boot HRNG reseed (range 0x0001..0xFFFF); zero-HRNG fallback не дає 0; warm-boot preserve; counter не перетинається з DID/PANIC_FLAG/firmware_id; two panics distinct counters |
| **[ARCH.21] Brownout PVD Lorenz Save** | 🟢 **Нове (2026-05-03)** — `HAL_PWR_PVDCallback` saves Lorenz state (DR16-DR19 + magic), packed DR0 preserved (counter+acoustic), last_wakeup persists for delta_t continuity, lorenz_invalid skips magic write, save→reboot roundtrip |
| **[ARCH.27] Node Role Differentiation** | 🟢 **Нове (2026-05-03)** — `Load_Node_Role()` SOLD magic / PROV magic / unprovisioned 0xFFFFFFFF / zero / corrupted magic → all fallback paths to ROLE_SOLDIER |
| **[FW.20-S2] Authoritativeness Flag (Soldier RX)** | 🟢 **Нове (2026-05-03)** — beacon byte 9 bit 7: authoritative beacon sets flag, relay beacon clears, legacy byte9=0 clears |
| **[FW.20-S2] Drift-Monitor + Panic Sync Request** | 🟢 **Нове (2026-05-03)** — `Soldier_Should_Request_Time_Sync` cold-boot grace silence (10 хв), cold-boot post-grace request, warm recently-synced silence (1 год), warm past-threshold trigger (>12 год), cooldown suppression + post-cooldown release (1 год); `Soldier_Seconds_Since_Last_Sync` zero-when-never-synced + warm-computed; `Build_Time_Sync_Request_Payload` layout (0x56 marker + DID BE + secs BE + PANIC_TTL + magic 'S' + PAD zeroed); marker disambiguation від OTA_REQ (0x55/'R') |
| **[FW.20-S2] Mesh-Relay Per-Hop Drift Compensation** | 🟢 **Нове (2026-05-03)** — `Soldier_Try_Relay_Time_Beacon` freeze-contract: happy path drift +5 sec; zero-hold ts unchanged; TDMA-резерв (bytes 5..8) + padding (11..15) pass-through; 6 reason'ів дропу через `BeaconRelayResult` enum (NOT_PROVISIONER, BAD_FRAME×2 marker+magic, NULL_TS, NOT_AUTHORITATIVE anti-storm, TTL_EXHAUSTED, HOP_TOO_LONG); boundary hold == 3600 sec passes; HAL_GetTick wrap-overflow safety (modular arithmetic); two-hop chain (relayed beacon's auth=0 → reject повторного relay'у — критичний anti-storm інваріант) |
| **[FW.20-S2 #5] Gossip-Piggyback (freeze-contract)** | 🟢 **Нове (2026-05-03)** — `Soldier_Pack_Gossip_Ts_Byte`: zero ts→0, low-byte extraction для `1714000000` (0x80) і `0xDEADBEEF` (0xEF); `Soldier_Try_Apply_Gossip_Ts`: cold-boot returns 0, within-window refines (drift -72 sec → bumps to neighbour's ts), drift cap (>127 sec → returns local unchanged), prev-window selection при clock-jump (256 sec ahead, beyond cap → no change), next-window selection при near-boundary local (LSB=0x7A → gossip 0x05 → +139 sec wraps to candidate@-117 sec wins as closest), drift -60 sec corrects to +60. Активація потребує hot-path вшивання у Phase 2 + RX-обробник. SSOT: [`03_02 §5а`](03_02_Queen_Gateway_Firmware). |
| **[FW.27 follow-up] OTA edge cases (anti-tamper + STOP2 cross-cycle)** | 🟢 **Нове (2026-05-03)** — duplicate з ІНШИМ payload не перезаписує оригінал (anti-tamper guard `!ota_chunk_received[chunk_idx]`); STOP2 simulation з out-of-order chunks (0/2/1 + offset integrity); duplicate after sleep still rejected (counter не подвоюється); total_chunks=0 malformed rejected gracefully (defence-in-depth для CRC32) |
| **[FW.27 follow-up] HMAC trailer cross-cycle persistence** | 🟢 **Нове (2026-05-03)** — bitmask survives simulated STOP2 between segments (1→3→2 OR-aggregates to 0x07); duplicate same-segment idempotent (counter stays bit 0, bytes intact) |
| **[FW.10 follow-up] TX deferral edge cases** | 🟢 **Нове (2026-05-03)** — extreme cold (-40°C) + battery-backed vcap (5500 mV) → NOT defer; warm (-5°C) + low vcap (1000 mV) → NOT defer (threshold -15°C); exact boundary @ -15°C з 0 mV → NOT defer (`<` strict, freeze-contract). SSOT: [`03_01 §1.8а`](03_01_Firmware_Lifecycle_and_DMA) |
| **[FW.29] Follow-up boundary (StatusByte + panic/saturation)** | 🟢 **Нове (2026-05-03)** — Pack_BioContract(3,63)=0xFF: normal payload masks bit 7 → 0x7F, panic payload sets exact PANIC_FLAG_BIT (0x80) без residual gp; FW.22 saturation @ 255 в acoustic_events + панічна плоть byte 7 = 0xFF marker — два незалежні поля без перетину |

### B.2.2 Queen (test_queen_logic.c)

| Область | Покриття |
|---------|----------|
| DJB2 Hash | 🟢 Повне |
| Command Dedup (Ring Buffer) | 🟢 Повне |
| CIFO EdgeCache | 🟢 Повне |
| Binary Batch Packing | 🟢 Повне |
| OTA Chunk Assembly + Bitmap | 🟢 Повне |
| Queen UID Flash Read | 🟢 Повне |
| RSSI Clamping | 🟢 Повне |
| ECB/CBC Restoration | 🟢 Повне |
| HRNG IV Generation | 🟢 Повне |
| **CoAP Retry (FW.9)** | 🟢 **Нове** — `test_coap_retry_constants`, константи `COAP_MAX_RETRIES`, `UART_RX_BUF_SIZE` |
| **[FW.1] Flash Key Loading** | 🟢 **Нове** | `Load_AES_Key()` magic check, key-not-provisioned → Error_Handler, FLASH_KEY_ADDR 0x0803E000 |
| **[FW.3] LoRa RX Ring Buffer** | 🟢 **Нове** (2026-05-02) — single-producer FIFO, capacity 15, переповнення → drop counter (existing voices preserved), drain+refill wraps, RSSI passthrough, ISR simulator size/RSSI clamp, **25-сек flush сценарій** (30 ISR пакетів → 15 уцілілих + 15 видимих втрат). Закриває BLOCKER-2 part-1: `incoming_lora_payload`+`lora_rx_flag` → ring. |
| **[FW.20-S2] Authoritativeness Flag (Queen TX)** | 🟢 **Нове (2026-05-03)** — `Build_Time_Beacon_Plaintext` byte 9 = `BEACON_BYTE9_AUTHORITATIVE` (0x81 = auth bit \| TTL=1); regression-точка на exact byte value |
| **[E.8] CIFO SNR Tiebreaker** | 🟢 **Нове (2026-05-03)** — `LoRaRxSlot.snr` + `EdgeCache.snr` plumbing + tiebreaker logic у `Process_And_Cache_Data` коли два non-critical записи мають однаковий RSSI: persisted у cache, dedup updates SNR, tiebreaker triggers on equal RSSI, doesn't override worse RSSI (RSSI primary, SNR tiebreaker), respects critical priority (status≠0 captain rule undisturbed), fallback path tiebreaker (all-critical scenario), ring carries SNR ISR→consumer end-to-end. SX1262 SNR більше не `(void)snr` |

### B.2.3 Bio-Contract (test_bio_contract.c)

| Область | Покриття |
|---------|----------|
| Sigma/Rho Clamping | 🟢 Повне |
| Z-Axis Lorenz | 🟢 Повне |
| Constants Verification | 🟢 Повне |
| StatusByte Encoding | 🟢 Повне |
| Growth Points Logic | 🟢 Повне |
| Evaluate & Pack Integration | 🟢 Повне |
| Boundary Conditions | 🟢 Повне |
| **[FW.5] β-Perturbation** | 🟢 **Нове** — `test_beta_nominal_no_perturbation`, `test_beta_fast_charge_increases_beta`, `test_beta_high_vcap_increases_beta`, `test_beta_clamp_upper_limit` |

### B.2.4 Encryption (test_encryption.c)

| Область | Покриття | ⚠️ |
|---------|----------|-----|
| ECB/CBC Mode Switch | 🟢 | Mock AES (not real CRYP) |
| ECB Restore After Flush | 🟢 | |
| Error Recovery (FW.16) | 🟢 | |
| IV Handling | 🟢 | |
| Encrypt/Decrypt Verify | 🟢 | Mock HAL |
| **[FW.1] Flash Key Integration** | 🟢 **Нове** | `Load_AES_Key()` → CRYP init integration, key-zero rejection, magic validation |

### B.2.5 Seed Derivation Host-Parity (test_seed_derivation.c) [SEC.11] 🆕

| Область | Покриття |
|---------|----------|
| HKDF-SHA256 RFC 5869 known-vector (simple UID) | 🟢 OpenSSL ↔ mbedTLS байт-ідентично |
| `derive_initial_state` bounds (x₀,y₀,z₀ ∈ [-1,+1]) | 🟢 По кожній координаті окремо |
| Epoch rotation (`epoch_day +1` змінює всі координати) | 🟢 Forward secrecy ≤ 24 год |
| Determinism (same `K_seed`, same `epoch_day` → bit-identical state) | 🟢 Повторювальність |
| `bytes_to_signed_unit_float` boundary (zero → -1, max → +1, mid → ~0) | 🟢 IEEE-754 unpack |
| Mixed-seed shape (різні `K_seed` → різні координати) | 🟢 Distinct seeds → distinct trajectories |
| Initial state shape для відомого `(K_seed, epoch_day)` (mixed seed) | 🟢 Backend-firmware parity vector |

### B.2.7 AES-128-CCM LoRa Packet (test_ccm.c) [FW.2 / ARCH.42 Variant B] 🆕

> **Freeze-contract (2026-05-24):** Soldier emit + Queen decrypt написано як гілка під `#define FW2_CCM_ENABLED 0` (production не активна до hardware bench `CRYP_AES_CCM` верифікації). Host-тести через **libcrypto-backed mock HAL** (`HAL_CRYPEx_AESCCM_Encrypt/Decrypt` у `hal_mock.h` гейтнуто `#define HAL_MOCK_CCM_ENABLED`, лінкується через `pkg-config openssl`). SSOT для packet layout + RTC FC packing — `firmware/common/lora_ccm.h`. Byte-level parity з Rails `Cryptography::LoraCcm` (та сама OpenSSL EVP CCM на обох сторонах).

| Область | Покриття |
|---------|----------|
| Golden vector encrypt (DID=0x01020304, FC=5, zero key) | 🟢 ciphertext `08ceca97bbf4fdc5` + tag `a6d8e20ce0deeae9` — identичний до Rails spec |
| Golden vector decrypt round-trip | 🟢 Тот же вектор у зворотний бік |
| RTC_BKP_DR15 `[FW2_FC_MAGIC:8 \| frame_counter:24]` pack/unpack | 🟢 Magic `0x46` ('F') у high byte, 24-bit FC у low |
| Cold-boot invalid magic detection | 🟢 DR15=0 або wrong magic → Unpack returns 0 (caller reseeds) |
| HRNG reseed clamps to `[FW2_FC_HRNG_MIN, FW2_FC_HRNG_MAX]` | 🟢 0→0x000001, 0xFFFFFFFF→0xFFFFFE, in-band passthrough |
| Sensor payload pack/unpack (Vcap/temp/acoustic/dt/status/mesh_ctrl) | 🟢 Roundtrip + bitfield extraction (mesh_ctrl TTL:4 + fw_nibble:4) |
| Full Soldier → Queen 24B packet roundtrip | 🟢 Sensor data byte-identична після decrypt |
| MIC tamper detection (flip bit у MIC) | 🟢 `HAL_CRYPEx_AESCCM_Decrypt` returns HAL_ERROR |
| AAD DID tamper detection (flip DID byte) | 🟢 Nonce + AAD divergence → MIC fail |
| AAD FC tamper detection (flip FC byte) | 🟢 Same |
| Ciphertext tamper detection (flip ct byte) | 🟢 MIC fail |
| Wrong key rejection (encrypt key ≠ decrypt key) | 🟢 MIC fail |
| **[FW.29]** Panic flag inside encrypted payload (bit 7 of byte 14 flip) | 🟢 MIC fail — закриває pre-CCM bit-flip атаку на panic broadcast |
| mesh_ctrl bitfield (TTL high nibble + fw_nibble low nibble) | 🟢 Roundtrip + extraction macros |
| **TOTAL** | 🟢 **All passing** |

**Інструментарій:** `make -C firmware/test ccm`. CI gate включено в `make all`. Cross-platform: macOS Homebrew + Linux apt-get openssl через `pkg-config`.

### B.2.6 TinyML Pipeline (test_tinyml_pipeline.c)

| Область | Покриття | ⚠️ |
|---------|----------|-----|
| Audio Normalization | 🟢 | |
| Confidence Threshold (legacy 0.80 binary) | 🟢 | Mock inference |
| Event Classification | 🟢 | |
| Saturation (FW.22) | 🟢 | |
| Vibration Guard (FW.11) | 🟢 | |
| **[FW.18] Dual-Threshold Zones** | 🟢 **Нове** | SILENCE/WARNING/CRITICAL + escalation 3× для chainsaw, no-escalation для cavitation, counter reset |
| **[FW.18] Threshold Validation & RTC Roundtrip** | 🟢 **Нове** | range/NaN/cold-boot/inversion fallbacks + IEEE 754 bit-exact roundtrip через DR13/DR14 |
| **[FW.18] OTA CMD dispatcher (`0x9D`)** | 🟢 **Нове** | downlink-CMD framework на Soldier'і — frame layout / CRC16 / range / inversion / short_frame; опкод-карта `0x99=OTA / 0x9A=Lorenz Z / 0x9B=HMAC trailer / 0x9C=TIME_SYNC / 0x9D=audio thresholds` |
| **[FW.27-B] Magic Re-Request — Soldier bitmap** | 🟢 **Нове** | Build_OTA_ReRequest_Payload: full/partial/edge/cap@72 + DID/total BE-pack + 5-хв timeout trigger |
| **[FW.27-B] Magic Re-Request — Queen handler** | 🟢 **Нове** | Process_LoRa_RX accepts/rejects; cmd_dedup_ring replay-protection; різні bitmap'и не дедуплюються (`djb2_hash_bytes` length-strict NUL-safe); REREQUEST не потрапляє у CIFO/CoAP path; total_chunks mismatch reject |
| **[FW.23] HMAC trailer parser + dual-gate (Soldier)** | 🟢 **Нове** | 3-чанковий збір печатки (in-order/out-of-order), reject seg_idx>3/wrong marker/short, dual-gate: magic-fail / hmac-fail / both-pass / cleanup-on-failure / constant-time first-byte / constant-time last-byte |
| **[FW.23] HMAC trailer relay (Queen)** | 🟢 **Нове** | 3 segments assemble, seg_idx=4 reject, wrong marker reject, overwrite same segment |

---

## B.3 Solidity Test Coverage (Foundry)

| Контракт | Покриття | Примітки |
|----------|----------|----------|
| SilkenCarbonCoin (SCC) | 🟢 Повне | mint, batchMint, slash, pause bypass, MAX_SUPPLY |
| SilkenForestCoin (SFC) | 🟢 Повне | ERC20Votes, auto-delegation, nonces override |
| StateRootAnchor | 🟢 Повне | MIN_ANCHOR_INTERVAL, fuzz tests |
| ProtocolParameters | 🟢 Повне | Governance parameter store |
| SilkenGovernor | 🟢 Повне | Proposal lifecycle |
| SilkenTimelock | 🟢 Повне | Delay enforcement |

---

## B.4 Відомі обмеження та відкриті ризики

### B.4.1 Firmware

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Mock AES | 🔴 CRITICAL | `hal_mock.h` копіює plaintext→ciphertext; реальна AES верифікація неможлива без ARM HW |
| Mock TinyML | 🟠 HIGH | `Run_Inference()` повертає фіксовані класи; реальна модель не тестується |
| AT Command UART | 🟡 MEDIUM | SIM7070G modem I/O не тестується повністю (апаратна залежність). Константи retry та таймаутів верифіковані `test_coap_retry_constants` (FW.9) |
| DMA Audio Timing | 🟠 HIGH | 512-sample DMA transfer timing не верифікується на host |

### B.4.2 Solidity

| Ризик | Серйозність | Опис |
|-------|------------|------|
| ERC20Permit | 🟡 MEDIUM | Permit/signature tests є базовими; cross-chain replay не тестується |
| Governor Integration | 🟡 MEDIUM | Governor + SCC mint interaction тестується окремо |

### B.4.3 Backend

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Concurrent State | 🟡 MEDIUM | Race conditions у AASM transitions не тестуються (потребують multi-thread test) |
| Live Web3 RPC | 🟡 MEDIUM | Всі Web3 виклики заглушені; live RPC тестування потребує staging env |

---

## B.5 Рекомендації для нових фіч

1. **Кожен новий Service/Worker** ПОВИНЕН мати spec файл з ratio ≥ 1.5x.
2. **AASM state machines** ПОВИННІ тестувати всі transitions + invalid transitions.
3. **Web3 сервіси** ПОВИННІ тестувати: stub mode, strict mode, missing credentials, RPC errors.
4. **Phlex компоненти** — слідувати Частині A цього документа (min 8 examples).
5. **Firmware** — кожна нова функція потребує host-based test у `firmware/test/`.
6. **Solidity** — naming: `test_` (happy), `testRevert_` (error), `testFuzz_` (fuzz).
7. **Per-group SimpleCov tripwire** — окрім глобального гейту (line ≥ 96 %, branch ≥ 85 %), `spec/spec_helper.rb` `SimpleCov.at_exit` падає, якщо покриття групи `Services` / `Models` < 90 % або `Workers` < 85 %. Пороги консервативні (фактично заміряно line ≈ 99 %); ціль — ловити випадкове видалення спек у hot path-ах. Підняти пороги до фактичного рівня — окремий PR після стабільного CI run.
