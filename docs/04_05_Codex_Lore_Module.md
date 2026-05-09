# 04_05. Codex (Lore Layer) — Design Philosophy, ADRs, Deferred Work

> **Status (Phase 7 cleanup):** Phases 1–6 are **DONE** and live in code. The implementation
> SSOT moved to the canonical docs:
>
> | Aspect | Canonical doc |
> |---|---|
> | DB tables / models / enums / partitioning | `04_01_Data_Models_and_Entities.md` § 7b |
> | Services / workers / Sidekiq queue assignment | `04_02_Business_Logic_and_Services.md` (Codex subsections) |
> | REST API `/api/v1/codex/*` (≈ 25 routes) | `04_03_REST_API_v1_Reference.md` § 4 (rows #86–#109) |
> | Phlex components / design tokens / ActionCable channels | `04_04_Phlex_UI_and_Tailwind.md` § 6.4 + § 8.1 |
> | Seed data | `db/seeds/codex/*.rb` + `lib/seeds/codex/*.yml` |
>
> This file now keeps **only** what is *not* yet in code: design philosophy
> (so future maintainers understand *why* the schema looks the way it does),
> the formal ADR registry, and the open Phase 6+ work.

---

## 1. Why a Lore Layer Exists

The Codex turns the operational telemetry stack (Tree → Cluster → Alert → Wallet)
into a **narrative substrate**. Each Tree under a forester is bound to one or
more **archetypes** (`Codex::Node`s such as `cold_wallet`, `relict_oracle`,
`chainsaw_protocol`) via a polymorphic `Codex::Citation`. The result is two-way:

- **Lore → Operations:** A `mythical` Node lights up a Cluster's badge in the UI;
  a Forester citing `chainsaw_protocol` on a `chainsaw_detected` alert turns
  the row into auditable, lore-linked forensic data.
- **Operations → Lore:** Every uplink, every match, every fraction pick can
  unlock a `Codex::Discovery` for the user — gamifying the boring middle of
  long observation windows. Discovery rules are stored in
  `codex_discovery_rules` so the **DAO can add new rules without a redeploy**.

The four Realms (`ecosystem | unique_tree | protocol | mythos`) are **data, not
code** — see ADR-CDX-2.

---

## 2. Architecture Decision Records (ADR-CDX-1 … ADR-CDX-7)

These are load-bearing decisions. Anyone touching `codex_*` MUST read them
before changing the schema or the queue assignments.

### ADR-CDX-1 — `bigint` PKs

`codex_*` tables use `bigserial` PKs (consistent with the rest of the monolith;
`uuid` is reserved for external identifiers like `idempotency_token`). The
human-readable identifier is `codex_uid` (`CDX-XXX-####`) computed from
`(realm_short_code, slug_hash)`; it is *not* the PK.

### ADR-CDX-2 — No STI, Realms are rows

`Codex::Realm` is a table (4 rows seeded). `Codex::Node` carries `realm_id +
archetype_key` instead of being subclassed. Adding a 5th realm
(`space`, `myco`, …) is a DAO proposal + an INSERT, not a deploy.

### ADR-CDX-3 — Bilingual without an i18n gem

`title_uk/_en`, `subtitle_uk/_en`, `body_md_uk/_en` are native columns.
Rationale: Ukrainian + English are the SSOT languages, additional locales are
not on the roadmap, and we save one JOIN + one gem dependency. If a third
locale ever appears, migrate by adding columns; do **not** retrofit `globalize`.

### ADR-CDX-4 — Codex never touches the hot path

No Codex worker runs in `uplink (#1)`, `alerts (#2)`, `critical (#3)`,
`downlink (#4)`, or `web3_critical (#6)`. Permitted queues:

| Worker | Queue |
|---|---|
| `Codex::AttunementBroadcastWorker` | `default (#5)` |
| `Codex::FractionAuditWorker` | `default (#5)` |
| `Codex::DiscoveryProbeWorker` | `default (#5)` |
| `Codex::EloRecomputeWorker` | `low (#9)` |

Rule of thumb: **gamification cannot starve a tree's telemetry**. If a Codex
feature ever needs a faster queue, that triggers a fresh ADR.

### ADR-CDX-5 — Markdown sanitisation

`*_md` columns are server-side rendered through `Codex::MarkdownRenderer`
(Rails `Rails::HTML5::SafeListSanitizer`) with this allow-list:
`p, h2, h3, h4, ul, ol, li, strong, em, blockquote, code, pre, a[href]`.
Hard length limits enforced in the model: `body_md_*` ≤ 8 KiB,
`subtitle_*` ≤ 2 KiB. Raw HTML never reaches the DOM.

### ADR-CDX-6 — Partition only `codex_matches`

`codex_nodes` is capped at ~10K rows (DAO governance) → unpartitioned.
`codex_matches` is RANGE-partitioned by `created_at` (Battle Arena is the
write-heavy surface, 100M+ rows expected). `PartitionMaintenanceWorker` is
responsible for monthly partitions — see `04_02` § DOC.11.

### ADR-CDX-7 — Discovery is presence-gated, fail-open

`Codex::DiscoveryProbeWorker.perform_async` is called from three places:
`EloRecomputeWorker` (match milestone), `FractionChangeService` (fraction
choice), `AttunementsController#create` (attunement streak). All three are
**fail-open**: a Sidekiq enqueue hiccup MUST NOT roll back the user-facing
operation. Probe results are read through `Codex::PresenceTracker` (Redis Set
TTL 10 min) so the worker fans out only to users who are actually online —
this keeps Discovery O(active_users), not O(all_users).

---

## 3. Open Work (Phase 6+ — not yet in code)

> Items marked `[ ]` are **deferred** by design — they don't block merge of
> the Codex module but are tracked here so they don't get lost.

### 3.1 Phase 6 — Stimulus + onboarding (frontend polish)

- [ ] **`codex--reveal` Stimulus controller** — animation for the
  `Codex::Discoveries::Toast` component. The `data-controller="codex--reveal"`
  attribute is already wired in the Phlex component; the JS file is missing.
  Without it the toast still appears via the Turbo Stream broadcast — the
  controller only adds the matrix-rain reveal effect.
- [ ] **`codex--battle` Stimulus controller** — keyboard shortcuts (`←`/`→`
  to vote, `space` to skip) and skip-cooldown UX hints. Forms work without it.
- [ ] **`codex--attune` Stimulus controller** — optimistic counter increment
  before the `attunement_count` ActionCable broadcast lands. Forms work without it.
- [ ] **`codex--fraction-picker` Stimulus controller** — realm-tab transition
  animation; non-JS fallback uses Turbo Frame navigation.
- [ ] **"Choose your fraction" onboarding wizard** — first-login modal that
  routes new users to `/api/v1/codex/fractions/picker`. Ship this *after*
  the Stimulus controllers so the wizard feels native, not a redirect chain.

### 3.2 Wiki + README

- [ ] Add a **"Lore Layer"** one-liner to the project `README.md`.
- [ ] Update the GitHub Wiki sidebar with a top-level "Codex" entry pointing
  at `04_01 §7b → 04_02 → 04_03 → 04_04 → 04_05`.

### 3.3 Sidekiq Pro hardening (cross-cuts the whole project)

Codex specifically uses `Sidekiq::Batch` callbacks in places where, today,
the `sidekiq_pro.rb` shim makes `on(:success)` a no-op. This is fine for
Phase 1–6 (no Codex code path depends on a Batch callback) but the **next**
Codex iteration that introduces multi-step Battle settlement *will* depend
on it. See the cross-project tracker in `04_02` § DOC.10.

### 3.4 Future vision (not scheduled)

- **Federated Codex** — let other forester guilds attach their own Realms
  via signed manifests (peaq DID-based attestation).
- **Cultural state-root anchor** — fold the top-100 most-cited nodes into
  the weekly Ethereum L1 anchor (`05_04`), giving Codex on-chain finality.
  Deferred beyond TRL 8.

---

## 4. Quality Gates (must stay green)

| Gate | Where | Owner |
|---|---|---|
| 449+ Codex specs (`spec/{models,services,policies,requests/api/v1,views/components,workers,blueprints}/codex/**`) | `bundle exec rspec` | Phase author |
| `bundle exec rubocop` 0 offenses on `app/**/codex/**`, `spec/**/codex/**` | CI | Phase author |
| Brakeman 0 warnings on `app/controllers/api/v1/codex/**` (citable_type allow-list lives in `Codex::CitationsController::CITABLE_CLASS_MAP`) | CI | Phase author |
| `Codex::Citation.bulk_for(targets)` used in every collection view that renders the strip (no per-row N+1) | Code review | Phase author |
| All shared Codex Phlex components use `gaia-*` / `status-*` tokens only — no raw `bg-white` / `text-gray-*` / `bg-emerald-*` | Code review | Phase author |

---

## 5. Tracker (compact)

| Phase | Status | Spec count | Notes |
|---|---|---|---|
| 1 — Foundation 🌱 (Realms, Nodes, atlas read-only) | ✅ done | ~95 | seeds: 4 realms + 79 nodes |
| 2 — Community 💬 (Comments, Attunements) | ✅ done | ~85 | soft-hide moderation |
| 3 — Identity 🛡 (Fractions, Picker, ProfileBadge) | ✅ done | ~70 | 7-day cooldown |
| 4 — Battle ⚔ (Pair selector, Vote recorder, Elo) | ✅ done | ~80 | `codex_matches` RANGE-partitioned |
| 5 — Discovery 🔓 (Engine + 5 adapters + Presence) | ✅ done | ~75 | DAO-tunable rules |
| 6 — Cross-domain stitch 🪡 (Citations, Admin CRUD, +3 adapters) | ✅ done in code | ~45 | open: Stimulus JS + onboarding wizard (§ 3.1) |
| 7 — PR cleanup pass | ✅ done | — | migration squash, N+1 fix in Alerts::Index, citation `polymorphic_type_for` |

> History of session-by-session ADR notes for Phases 1–6 is preserved in the
> git log of `docs/04_05_Codex_Lore_Module.md` (`git log -p --follow`) and in
> the merged PRs. Re-emitting it here would duplicate `04_01..04_04`.
