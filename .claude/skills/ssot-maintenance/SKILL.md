---
name: ssot-maintenance
description: "Use when working on the SSOT docs (docs/NN_NN_*.md) — editing or creating a canon doc, hunting or fixing SSOT drift, adding a docs linter / CI gate, checking where a fact canonically lives, or publishing canon to the GitHub wiki. Operational playbook for docs:check_refs / docs:toc / tracker:check / wiki:sync; defers the STANDARD itself to 00_02 + 00_06. Examples: \"edit 03_05\", \"is this value consistent across the docs?\", \"add a drift linter\", \"publish the docs to the wiki\", \"where does the Lorenz constant live?\""
---

# SSOT Maintenance

The *executable playbook* for keeping `docs/NN_NN_*.md` (and the firmware/backend they mirror) internally consistent. This skill is the **HOW**; it does **not** restate the standard or track state — those live elsewhere (see below). "SSOT drift slowly kills" — this skill is the antidote, and the engine for evolving better defenses.

## 📖 Read first — SSOT, do NOT restate here

These are the canonical homes. Read them before acting; never copy their content into this skill (that would itself be drift).

| Source | Owns |
|---|---|
| `docs/00_02_AI_Native_Engineering_and_TRL` | **Philosophy**: NASA TRL (1-9, never 10-12), the AI Pipeline + 🚦 **Validation Gate** (LLM proposes a *hypothesis*, it does NOT compute physics), Intent-First, golden rule: *no code/solder until the spec is approved in the Wiki*. |
| `docs/00_06 §1` | **Canonical doc skeleton** (🎯 Мета / ✅ Статус / 🔗 Cross-references / 📑 auto-ToC / Content; blockers→00_07; no volatile counts). |
| `docs/00_06 §2` | **Canonical-home registry** — *одна річ, один дім*. The table of which fact lives where (TRL matrix→00_03 §1, AES modes→03_05 §3.7, Lorenz→03_04 §4.1, …). |
| `docs/00_06 §3` | **Drift-prevention tooling** — the CI-enforced guard table. Add new guards here. |
| `docs/00_00` | SSOT index + reading order. |

**State** (what's done / next) lives in memory, not here: `[[ssot-stabilization-campaign]]`, `[[post-sweep-backlog]]`, plus `[[feedback_no_volatile_counts]]`, `[[feedback_ssot_review_workflow]]`, `[[project_wiki_sync]]`.

## When to use

- Editing or creating any `docs/NN_NN_*.md` canon doc.
- "Is this value/fact consistent across the docs?" / suspect drift.
- Adding or tuning a docs linter / CI gate.
- "Where should fact X live?" (→ 00_06 §2 registry).
- Publishing canon to the GitHub wiki.

## Core principle

**Every fact has ONE canonical home (00_06 §2); everything else references it, never restates.** When a fact changes, edit it *only* at its home — references stay valid. A mirror must be labelled "значення тут — дзеркало SSOT, правити там". The linters below enforce *owner-only vocabulary* (e.g. RTC register availability words may appear only in 03_01).

## Workflow — hunt → automate → fix

The loop that stabilises the SSOT (repeat per drift class):

```
1. HUNT     Find a fact restated inconsistently across docs/code
            (same value, two numbers; same string, two spellings).
            Identify its canonical OWNER (00_06 §2).
2. AUTOMATE Write a precise, low-false-positive linter (recipe below)
            so the drift can never silently return.
3. FIX      Clean every off-home restatement → make it a reference.
            Re-run the gate until green; the gate now holds the line.
```

> Before editing any symbol the docs describe, honour the repo's GitNexus rule (CLAUDE.md): `gitnexus_impact` first. Docs edits are low-risk, but value changes that mirror code are not.

### Deep-archiving a 00_07 item (cement code + SSOT + tracker together)

A heavier, specialised loop for *retiring* a tracker item. Walk **every** code/doc site of the ID — forward **and** inbound refs, **semantic terms** (service names, constants, opcodes), not just the ID, across **all** `00_01..08_03` + code + spec + `.github`. Verify each `✅` against real code + `git log` (don't trust prose-claims-done). Canonize what lives only in 00_07 prose **before** trimming (migrate-first); fix any drift found along the thread; then **cement-trim** (open residual stays) or **archive** (fully done → §🗄️ table). Follow the breadcrumbs (`[DOC.N]`/`[FW.N]` tags, Cross-ref lines, `00_06 §2` home-registry). Commit each ID separately. 🔴 **Founder disciplines (2026-06-09):** ONE edit at a time (verify between — no batching, even non-glue); **READ canon to confirm a fact is canonized BEFORE collapsing/thinning** it (esp. a Присуд/verdict — never delete un-canonized analysis); **orphan-ID sweep** (`comm -23` referenced-vs-00_07-homed → a resolved+cited fix with no `####`/table row needs a §🗄️ row); **re-audit already-cemented items** to the deeper standard. Full 18-step playbook + breadcrumbs + anti-patterns lives in **`.claude/prompts/deep_archival.md`** — this skill only points (One-Home).

## Commands

All via binstubs — **`bin/rails` / `bin/rspec`**, never `bundle exec` (`[[feedback_rubocop_binstub]]`).

| Command | Does | Engine |
|---|---|---|
| `bin/rails docs:check_refs` | The omnibus gate: dangling `NN_NN` links (HARD) · §-label drift (advisory) · TRL presence (HARD) · TRL single-value (HARD) · blocker-hygiene (HARD) · standard-conformance (HARD) · ToC sync (HARD) · RTC reg-map drift (HARD) · Lorenz-formula drift (HARD) · deprecated terms (HARD). | `lib/docs_linter.rb`, `lib/docs_toc.rb` |
| `bin/rails docs:toc` | Regenerate the `📑 Зміст` auto-ToC between `<!-- TOC:AUTO:START/END -->` from current `## ` headings (curated `— descriptions` preserved). Run after changing headings. | `lib/docs_toc.rb` |
| `bin/rails tracker:check` | 00_07 DRY: duplicate IDs, meta-line conformance, canon-ref resolution. | `lib/tracker/dashboard.rb` |
| `bin/rails docs:graph` | _(on-demand audit, NOT a CI gate)_ ref-graph view: orphan / dead-end pages, in/out-degree skew, one-way sibling links, comprehensive `#anchor` + linked-`§X` resolution. The graph lens the per-line gates can't give (GitNexus models code, not `NN_NN` links). | `lib/docs_graph.rb` |
| `bin/rails wiki:sync` | **Dry-run** (default): clone wiki, transform links + carry images, show `--stat` diff + unresolved links. Publishes nothing. | `lib/wiki_link_normalizer.rb` |
| `bin/rails wiki:sync PUSH=1` | Commit + push the canon `NN_NN` pages to the GitHub wiki (SSH to `*.wiki.git`). | ↑ |
| `COVERAGE=0 bin/rspec spec/lib/docs_linter_spec.rb spec/lib/docs_toc_spec.rb spec/lib/docs_graph_spec.rb` | Unit-test the linter / ToC / ref-graph engines (pure functions — `spec_helper`, **no Rails/DB**; `COVERAGE=0` skips the whole-suite coverage gate on a subset run). | — |
| `ruby scripts/docs_check.rb [refs\|tracker]` | **Fast local** alias — runs `docs:check_refs` + `tracker:check` with **no Rails boot** (~0.3s vs ~1.2s; no `bundle`/DB — only `ruby`+`rake`). Reuses the exact rake bodies → cannot drift from CI. Read-only (ToC regen stays `bin/rails docs:toc`). Ideal for a pre-commit hook / non-Rails contributor. | reuses `lib/tasks/docs.rake` + `tracker.rake` |

CI: `docs.yml` is the **single home** for the doc gates — triggers on `docs/**`, `**.md`, the lib-docs engines/specs, and `.github/**` (so the external-doc-path guard sees `.github/`+root-md changes). The duplicate steps were removed from `ci.yml` (2026-06-02), so a mixed code+docs PR no longer double-runs them; `ci.yml` (code CI) `paths-ignore`s `**.md`/`docs/**`. `main` is currently **unprotected** — when protection lands, mark `docs_check` required (a docs-only PR skips `ci.yml`).

## Add a new drift guard — *how this skill evolves*

This is the point: the skill stays small, but it lets you turn **any** newly-found drift class into a permanent gate. The defenses grow; the skill doesn't. Recipe, mirroring the existing `DocsLinter` methods:

1. **Pick the owner.** Which doc canonically owns this fact (00_06 §2)? Everything else must only reference it.
2. **Write a pure function** in `lib/docs_linter.rb` — `module_function`, takes `text` (or `basename, text`), returns an array of human-readable violation strings. No Rails, no I/O.
3. **Keep false positives near zero** (heuristic linters are noisy):
   - Unicode-letter boundaries `(?<!\p{L})…(?![\p{L}])` so `звільнило`/`зарезервовано:` don't match a `вільн`/`резерв` rule.
   - Skip table rows (`line.lstrip.start_with?("|")`) and ```` ``` ```` fenced code.
   - **Exempt the owner doc** — it's *allowed* to state the fact.
4. **Unit-test it** in `spec/lib/docs_linter_spec.rb`: a positive (catches the real drift), a clean pass, and the near-misses that must *not* trip. Run `bin/rspec spec/lib/docs_linter_spec.rb`.
5. **Wire it into** `lib/tasks/docs.rake` `check_refs`: accumulate hits, print a report block, push a label into `failed` (advisory while you clean the existing drift → flip to **HARD** once it's at 0).
6. **Record it** in the `00_06 §3` guard table and the campaign memory — **not in this skill**. (For an *unambiguous* retired string with no legit current use, skip the bespoke linter: add it to `DocsLinter::DEPRECATED_TERMS` — the general "any retired token's return is blocked" net.)

> When the **standard itself** changes (skeleton, home registry), edit `00_06` (the home) — this skill's pointers stay valid by design.

### Worked example (a real loop, 2026-05-30)

```
HUNT     FW.2 claimed RTC_BKP_DR15, but 03_02/00_07/03_03 still read
         "DR15 наразі резерв". Owner of register allocation = 03_01 §2.
AUTOMATE DocsLinter.rtc_register_allocation_drift(basename, text):
         match (?<![A-Za-z])DR(\d{1,2})\b near an availability word,
         skip tables/fences, exempt 03_01 + 03_05. Tuned out false hits
         on "звільнило" / "reserved:8". Specs in docs_linter_spec.rb.
FIX      Reworded the 3 stale lines → "зайнято FW.2"; gate flipped HARD.
         Later, the stale HKDF string "silkennet-v1-aes256" was an
         UNAMBIGUOUS retired token → added to DEPRECATED_TERMS instead
         of a bespoke linter. Both now green; drift can't return.
```

### Worked example #2 — module restructure (2026-05-30)

A z-divergence wording fix in 07_01 §6.5 snowballed into extracting two
oversized, scattered topics into their own canon pages: slashing (07_01 §6,
~half the vision page) → `05_05`, governance (05_03 §749, ~156 lines) → `05_06`.
Repeatable shape (now canon in `00_06 §4`):

```
MIGRATE-FIRST  fill new home with FULL substance + verify present, THEN cut source
STUB+POINTER   source keeps a thin vision/ref-stub → new home; mechanics reference
SWEEP ANCHORED re-point §X refs anchored on a token (e.g. "07_01") so other docs'
               internal §X (01_01/02_03/04_04 each have their own §6.x!) survive;
               Ruby script-FILE, dry-run + presence-check, never inline -e
AUTOMATE       turn the manual owner-violation hunt into a guard —
               DocsLinter.lorenz_formula_drift (β assignment outside 03_04)
GATE per-phase docs:check_refs + tracker:check + zero-loss set-diff + wiki dry-run
```

## Checklists

**Before merge** (any docs change):

```
- [ ] bin/rails docs:check_refs           → green
- [ ] bin/rails tracker:check             → green (if 00_07 touched)
- [ ] bin/rails docs:toc                  → run if headings changed, then check_refs green
- [ ] linter/ToC specs green              → if lib/docs_*.rb touched
- [ ] fact edited ONLY at its home (§8.2); mirrors labelled
- [ ] no volatile counts · no blocker section in canon · Cross-references at top
```

**Before wiki publish:**

```
- [ ] docs committed (wiki:sync mirrors the working tree)
- [ ] bin/rails wiki:sync                 → review --stat + "unresolved links"
- [ ] fix any unresolved (usually a stale source link)
- [ ] bin/rails wiki:sync PUSH=1
```

## Gotchas (hard-won)

- **Subset `bin/rspec` runs trip the SimpleCov coverage gate** ("Models 0% < 90%" / `minimum_coverage`). That's an **artifact** of a partial resultset, not a real failure. The linter/ToC specs are pure units (`spec_helper`, no Rails/DB) — run them gate-free with `COVERAGE=0 bin/rspec spec/lib/docs_*_spec.rb`; for app-coverage truth run the full `bin/rspec` (`[[project_post_sweep_backlog]]`).
- **`db/structure.sql`**: never stage drive-by Postgres-version line diffs — restore from HEAD (`[[feedback_structure_sql]]`).
- **No volatile counts in prose** (test/line tallies drift every commit). Reference the source or generate it (`[[feedback_no_volatile_counts]]`).
- **`wiki:sync` needs SSH access** to the `*.wiki.git` repo; **always dry-run first**; read its "unresolved links" — they're often stale source links worth fixing.
- **`.c` firmware comments stay Ukrainian + the file's poetic house style** (`[[feedback_c_comments_ukrainian]]`).
- **zsh**: `status` is read-only; quote globs (`[[feedback_zsh_bash_gotchas]]`).
- **Required-check caveat**: if `ci.yml` jobs are *required* status checks, also mark `docs.yml`'s gate required — else a docs-only PR (which skips `ci.yml`) could merge without the gate enforced.

## Keep this skill bounded

This file is the **method**. It must not accumulate: the *standard* → `00_06`; *state / backlog* → memory; a *new guard's definition* → `lib/docs_linter.rb` + `00_06 §3`. If you're tempted to add a fact here, it belongs in one of those homes — that discipline is the very thing this skill enforces.
