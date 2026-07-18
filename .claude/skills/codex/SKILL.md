---
name: codex
description: "Use when working on the Codex Lore Layer of silken_net (app/**/codex/**, codex_* tables) — the gamified read-only narrative layer over telemetry (Realms/Nodes/Citations, Battle Arena Elo, Discovery, Fractions). Routes to the canon docs and the load-bearing ADR invariants."
---

# Codex (Lore Layer)

Read-only наративний шар над операційною телеметрією (Tree → Cluster → Alert →
Wallet): архетипи (Realms × Nodes), поліморфні `Codex::Citation`, Battle Arena
(Elo), Discovery, Fractions. Гейміфікація, що **ніколи не торкається гарячого
шляху телеметрії дерева**.

## Канон — читати ПЕРЕД зміною `codex_*`

SSOT One-Home: цей skill лише **маршрутизує**; факти живуть у `docs/`. Не дублюй
сюди значення/сигнатури і **не хардкодь `file:line`** — воно дрейфує (стале вже за
комітом). Посилайся на стабільні якорі: канон-§ + імена символів.

| Що треба | Канон-дім |
|---|---|
| **Чому** так — філософія + 10 ADR (CDX-1…10) | `docs/04_05_Codex_Lore_Module.md` ← read-first |
| Моделі / таблиці / enum / партиціювання | `04_01 §7b` |
| Сервіси / воркери / призначення черг | `04_02 §10b` (+ DOC-R.10/DOC-R.11) |
| REST `/api/v1/codex/*` | `04_03 §4` |
| Phlex-компоненти / токени / Turbo-ActionCable | `04_04 §6.4`, §8.1 |
| Seed-корпус (4 Realm + Node) | `db/seeds/codex/` (`realms.yml` · `discovery_rules.yml` · `nodes/`) |

## Несучі інваріанти (ADR — `04_05 §2`)

Будь-хто, хто чіпає `codex_*`, МУСИТЬ це знати:

- **Hot-path-free (ADR-CDX-4):** жоден Codex-воркер не в `uplink/alerts/critical/downlink/web3_critical`; лише `default`/`low`. Гейміфікація не голодує телеметрію.
- **Realms = дані, не код (ADR-CDX-2):** 5-й Realm — DAO INSERT, не деплой. Без STI.
- **Discovery fail-open (ADR-CDX-7):** збій enqueue probe НЕ відкочує user-facing операцію. Presence-gated (Redis TTL 10 хв) → O(active_users), не O(all_users).
- **Markdown-санітизація (ADR-CDX-5):** через `Codex::MarkdownRenderer` allow-list; сирий HTML ніколи в DOM.
- **Citation allow-list (ADR-CDX-9):** `citable_type` лише через `CITABLE_CLASS_MAP` — без `constantize` з params (object-injection guard).
- **Stimulus-мінімалізм (ADR-CDX-8):** рівно 2 контролери (`codex--reveal`, `codex--comment`); решта — нативний `data-turbo-confirm`. ⚠️ **Broadcast-half живості (attunement-counter · live-comments · citation-pills · discovery-toast) наразі DEAD-on-arrival** — шлють сирий `ActionCable.server.broadcast` без жодного consumer'а (нема `@rails/actioncable`-pin / `app/channels/` / `subscriptions.create` у репо). Робочий патерн живості = `turbo_stream_from` + `Turbo::StreamsChannel.broadcast_*_to` (як telemetry/burn/wallet), НЕ raw broadcast. Wire-vs-descope = відкрите ⚖️ → [`00_07` UI.2](00_07_Action_Plan_Tracker).
- **N+1:** citation-strip завжди через `Codex::Citation.bulk_for(targets)`.
- **Партиціювання (ADR-CDX-6):** лише `codex_matches` (RANGE/місяць, write-heavy); `codex_nodes` ~10K → без партицій.
- **bigint PK + `codex_uid` (ADR-CDX-1):** `CDX-XXX-####` — людино-читабельний, НЕ PK.
- **Двомовність без гему (ADR-CDX-3):** `*_uk` / `*_en` нативні колонки.
- **Sidekiq Pro shim OK (ADR-CDX-10):** усі 4 воркери fire-and-forget → Codex не залежить від `on(:success)` Batch і мерджиться незалежно від Pro-hardening (`04_02` DOC-R.10). Перша фіча, що це зламає — multi-step Battle settlement.

## Карта коду

| Шар | Шлях |
|---|---|
| Namespace + моделі | `app/models/codex.rb` · `app/models/codex/` (Realm, Node, Citation, Comment, Attunement, Fraction, Match, Discovery, DiscoveryRule) |
| Контролери | `app/controllers/api/v1/codex/` (+ `admin/`) |
| Сервіси | `app/services/codex/` (DiscoveryEngine, EloMath, PairSelector, VoteRecorder, FractionChange, PresenceTracker, MarkdownRenderer, NodeImport, DiscoveryRuleImport) |
| Воркери | `app/workers/codex/` (AttunementBroadcast, DiscoveryProbe, EloRecompute, FractionAudit) |
| Phlex | `app/views/components/codex/` |
| Policies (Pundit) | `app/policies/codex/` |
| Blueprints | `app/blueprints/codex/` |
| Stimulus | `app/javascript/controllers/codex/` (reveal, comment) |
| Seeds / rake | `db/seeds/codex/` · `lib/tasks/codex.rake` |

## Робочі правила

1. **Docs-first.** Прочитай `04_05` (саме *чому*) перед зміною схеми чи призначення черги — ADR несучі.
2. **Торкаєш код → онови його канон-дім** (`04_01`–`04_04`), НЕ `04_05`. `04_05` тримає лише філософію + ADR; **нова несуча зміна → новий `ADR-CDX-N`** там, не прозовий патч у тілі.
3. **Blast-radius перед редагуванням символу** (правило CLAUDE.md §2). Простеж викликачів/залежності символу (grep/read живих локацій) — на відміну від хардкодженого `file:line`.
4. **Новий сервіс/воркер/компонент** → онови покриття `04_06` + відповідний `04_0x`-дім.
5. SSOT-правки веди скілом `ssot-maintenance` (гейти `docs:check_refs` + `tracker:check`).
