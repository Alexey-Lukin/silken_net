---
name: ssot-maintenance
description: "Use when working on the SSOT docs (docs/NN_NN_*.md) — editing or creating a canon doc, hunting or fixing SSOT drift, adding or hardening a docs linter / CI gate, checking where a fact canonically lives, or publishing canon to the GitHub wiki. Operational playbook for docs:check_refs / docs:toc / tracker:check / wiki:sync, plus §Guard-craft — the home of how to build a gate that actually catches (what a gate cannot see, the five blindness shapes incl. a gate that under-implements its own declared contract, precision-in-the-anchor, mutation-verify pitfalls, hardening checklist). Defers the STANDARD itself to 00_02 + 00_06. Examples: \"edit 03_05\", \"is this value consistent across the docs?\", \"add a drift linter\", \"why is my guard green when it shouldn't be\", \"publish the docs to the wiki\", \"where does the Lorenz constant live?\""
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

**State** (what's done / next) lives in memory, not here: `[[project_ssot_campaign_history]]` (Gen1 SSOT-standardization campaign, DORMANT) + `[[feedback_vilize_sweep_method]]` (the LIVE method — 00_07 tracker-hygiene + 7-family guard-craft) + `[[project_vilize_00]]` / `[[project_doc_t33_t34_seed]]` (§00-tooling: field_canon_sync, markers, stan_audit), plus `[[feedback_no_volatile_counts]]`, `[[feedback_ssot_review_workflow]]`, `[[project_wiki_sync]]`.

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

> Before editing any symbol the docs describe, honour the repo's blast-radius rule (CLAUDE.md §2): trace the symbol's callers first. Docs edits are low-risk, but value changes that mirror code are not.

### Deep-archiving a 00_07 item (cement code + SSOT + tracker together)

A heavier, specialised loop for *retiring* a tracker item. Walk **every** code/doc site of the ID — forward **and** inbound refs, **semantic terms** (service names, constants, opcodes), not just the ID, across **all** `00_01..07_03` + code + spec + `.github`. Verify each `✅` against real code + `git log` (don't trust prose-claims-done). Canonize what lives only in 00_07 prose **before** trimming (migrate-first); fix any drift found along the thread; then **cement-trim** (open residual stays) or **archive** (fully done → §🗄️ table). Follow the breadcrumbs (`[DOC.N]`/`[FW.N]` tags, Cross-ref lines, `00_06 §2` home-registry). Commit each ID separately. 🔴 **Founder disciplines (2026-06-09):** ONE edit at a time (verify between — no batching, even non-glue); **READ the FULL canon section — in EVERY doc the fact lives in — BEFORE collapsing/thinning** (a grep hit is NOT confirmation; esp. a Присуд/verdict — never delete un-canonized analysis; an "all clean, nothing found" sweep is a signal to dig deeper, not to stop). This is the one rule with **no gate behind it** — the zero-loss set-diff is itself grep-based, so a fact that is present-by-token but gutted-in-substance passes green; **orphan-ID sweep** (`comm -23` referenced-vs-00_07-homed → a resolved+cited fix with no `####`/table row needs a §🗄️ row); **re-audit already-cemented items** to the deeper standard. Full 18-step playbook + breadcrumbs + anti-patterns lives in **`.claude/prompts/deep_archival.md`** — this skill only points (One-Home).

## Commands

All via binstubs — **`bin/rails` / `bin/rspec`**, never `bundle exec` (`[[feedback_local_verify]]`).

| Command | Does | Engine |
|---|---|---|
| `bin/rails docs:check_refs` | The omnibus gate: dangling `NN_NN` links (HARD) · §-label drift (**HARD** since 2026-07-25, DOC-T.48 — it was the last advisory of the 34 categories) · TRL presence (HARD) · TRL single-value (HARD) · blocker-hygiene (HARD) · standard-conformance (HARD, **incl. H1** — DOC-T.49, checked before the skeleton exemptions) · ToC sync (HARD) · RTC reg-map drift (HARD) · Lorenz-formula drift (HARD) · deprecated terms (HARD). **Every category is now HARD** — a hit fails the build, so "advisory while you clean the drift" (the recipe below) is a *transient* state, not a resting one. | `lib/docs_linter.rb`, `lib/docs_toc.rb` |
| `bin/rails docs:toc` | Regenerate the `📑 Зміст` auto-ToC between `<!-- TOC:AUTO:START/END -->` from current `## ` headings (curated `— descriptions` preserved). Run after changing headings. | `lib/docs_toc.rb` |
| `bin/rails tracker:check` | 00_07 DRY: duplicate IDs, meta-line conformance, canon-ref resolution — plus **item visibility** (DOC-T.49): every `#### ` item must sit INSIDE a registry section (`## §NN` / `## 🔀`), because `parse` cannot see one that doesn't, and then every other check here iterates a set that silently lacks it. | `lib/tracker/dashboard.rb` |
| `ruby scripts/code_doc_section_refs.rb` | **HARD gate** (docs.yml, DOC-T.48): every `NN_NN §X` cited in a CODE comment (`app`/`spec`/`lib` `*.rb`) or a `.claude` routing file still resolves. Closes the structural blind spot that `docs:check_refs` scans `docs/**` and never reads code. ~44 s over 926 files — the priciest step in `docs_check`, so run it deliberately, not in a tight loop. | `scripts/code_doc_section_refs.rb` |
| `bin/rails docs:graph` | _(on-demand audit, NOT a CI gate)_ ref-graph view: orphan / dead-end pages, in/out-degree skew, one-way sibling links, comprehensive `#anchor` + linked-`§X` resolution. The graph lens the per-line gates can't give (they check refs flat, not the `NN_NN` link graph). | `lib/docs_graph.rb` |
| `bin/rails wiki:sync` | **Dry-run** (default): clone wiki, transform links + carry images, show `--stat` diff + unresolved links. Publishes nothing. | `lib/wiki_link_normalizer.rb` |
| `bin/rails wiki:sync PUSH=1` | Commit + push the canon `NN_NN` pages to the GitHub wiki (SSH to `*.wiki.git`). | ↑ |
| `COVERAGE=0 bin/rspec spec/lib/docs_linter_spec.rb spec/lib/docs_toc_spec.rb spec/lib/docs_graph_spec.rb` | Unit-test the linter / ToC / ref-graph engines (pure functions — `spec_helper`, **no Rails/DB**; `COVERAGE=0` skips the whole-suite coverage gate on a subset run). | — |
| `ruby scripts/docs_check.rb [refs\|tracker]` | **Fast local** alias — runs `docs:check_refs` + `tracker:check` with **no Rails boot** (~0.3s vs ~1.2s; no `bundle`/DB — only `ruby`+`rake`). Reuses the exact rake bodies → cannot drift from CI. Read-only (ToC regen stays `bin/rails docs:toc`). Ideal for a pre-commit hook / non-Rails contributor. | reuses `lib/tasks/docs.rake` + `tracker.rake` |
| `ruby scripts/stan_audit.rb` | _(advisory, on-demand — ганяти на цемент/vilize-сесіях, НЕ CI-gate)_ три осі по registry-айтемах 00_07 — третя = **[x]-staleness** (чекнутий бокс із датою `✅ YYYY-MM-DD` старший ~14 днів → цементуй у Стан/канон і зрізай; бездатні = лічильник). Дві осі по `**Стан:**`-рядках: **canon-claim** (код-символ ∉ заявлені канон-доми айтема — ловить «Механіка — `NN_NN §X`» без змісту; FP-класи вбиті historical sweep'ом DOC-T.37 — повний exempt-перелік у шапці скрипта) + **volatile-numbers** (число+лічильне слово, класи A/B/C/D очима). Кожен хіт розібрати очима: FP / wrong-дім → Стан-реф-дожим / діра → канонізувати-migrate; новий повторюваний FP-клас → вбити В СКРИПТ. Метод/історія → `00_06 §3` | `scripts/stan_audit.rb` (standalone; реюзить `Tracker::Dashboard`-парсинг) |
| `ruby scripts/model_doc_sync.rb` | **code↔doc registry gate** (HARD, CI `docs.yml`): `04_01` ⟷ `app/models/` (model files ⟷ `### Model` headings §2..§7b 1:1 · concerns ⟷ §1 · `PARTITIONED_TABLES` ⟷ §0/§11) **+ `04_02` ⟷ `app/services/**`+`app/workers/**`** (every class mentioned). Replaced the manual «§12/§13b SSOT Drift Register» (silently stale: 35 models for 36 files; missed the whole FactoryFlashing::* namespace). Run it (or rely on CI) after adding a model/service/worker. Pure Ruby, no Rails. Method/why → `00_06 §3`. | `scripts/model_doc_sync.rb` (standalone) |

CI: `docs.yml` is the **single home** for the doc gates. Its `changes` filter covers `docs/**` + `**.md` + **every source tree** — deliberately wide, because two gates scan them tree-wide (external doc-path drift + `code_tracker_id_check`) and the pin/model-sync/FIELDS gates read specific files inside them. **A gate whose input sits outside that filter is decorative** — it only ever runs on someone else's PR (the `bio_contract.rb` hole, DOC-T.40 CHECK D); `guard_registry_sync` now enforces that for pinned sources. The duplicate steps were removed from `ci.yml` (2026-06-02), so a mixed code+docs PR no longer double-runs them; `ci.yml` (code CI) `paths-ignore`s `**.md`/`docs/**`. `main` **is** branch-protected: the required check is the always-on aggregate **`docs-ok` («Docs passed»)** — a path-gated `docs_check` cannot be required directly (it would block code-only PRs that skip it). Canon → `06_07 §2`.

## Add a new drift guard — *how this skill evolves*

This is the point: the skill stays small, but it lets you turn **any** newly-found drift class into a permanent gate. The defenses grow; the skill doesn't. Recipe, mirroring the existing `DocsLinter` methods:

1. **Pick the owner.** Which doc canonically owns this fact (00_06 §2)? Everything else must only reference it.
2. **Write a pure function** in `lib/docs_linter.rb` — `module_function`, takes `text` (or `basename, text`), returns an array of human-readable violation strings. No Rails, no I/O.
3. **Keep false positives near zero** (heuristic linters are noisy):
   - Unicode-letter boundaries `(?<!\p{L})…(?![\p{L}])` so `звільнило`/`зарезервовано:` don't match a `вільн`/`резерв` rule.
   - Skip table rows (`line.lstrip.start_with?("|")`) and ```` ``` ```` fenced code.
   - **Exempt the owner doc** — it's *allowed* to state the fact.
4. **Unit-test it** in `spec/lib/docs_linter_spec.rb`: a positive (catches the real drift), a clean pass, and the near-misses that must *not* trip. Run `bin/rspec spec/lib/docs_linter_spec.rb`. **Then mutation-verify** (break it → FAIL → revert). A symmetry / false-green-prone guard goes through a 2-agent review before it silences a class (`[[project_doc_t33_t34_seed]]`). Full craft → **§Guard-craft** below.
5. **Wire it into** `lib/tasks/docs.rake` `check_refs`: accumulate hits, print a report block, push a label into `failed` (advisory while you clean the existing drift → flip to **HARD** once it's at 0).
6. **Record it** in the `00_06 §3` guard table and the campaign memory — **not in this skill**. This is now *enforced*, not remembered: `guard_registry_sync` (DOC-T.40) fails CI if a new gate has no §3 row, if a §3 row names a file that no longer exists, **or if a §3 row claims a command/workflow the CI never runs** (reverse axis E — write the §3 command column exactly as the workflow runs it, and mark non-CI rows `advisory`/`on-demand`). Cross-file / code-reading gates go in `scripts/*.rb`, not `lib/docs_linter.rb` (which is pure-doc text); wire the new script into `docs.yml` **and** confirm its inputs are inside the `changes` filter — a gate outside it is decorative. (For an *unambiguous* retired string with no legit current use, skip the bespoke linter: add it to `DocsLinter::DEPRECATED_TERMS` — the general "any retired token's return is blocked" net.)

> When the **standard itself** changes (skeleton, home registry), edit `00_06` (the home) — this skill's pointers stay valid by design.

## 🛡️ Guard-craft — a gate that actually catches

**This is the home of guard-craft.** `00_06 §3` is the *registry* (which guards exist), a script's own header is the home of *why that guard is shaped the way it is* (it rots together with the code, so it cannot drift), and this section is the *craft* — what to ask before, during and after writing one. Instances/demonstrations live in the session memories that found them.

### The question that matters

Not "is there a gate?" but **"WHAT DOES THIS GATE NOT SEE?"** A green gate is evidence only about the class it actually inspects. Two consequences worth internalising:

- **Guards skew away from money.** Pure-doc surfaces end up well fenced while the doc⟷code *value* surface is held together by hand. The cheapest real gap is a **mirror declared in a code comment** ("edit it THERE") with no pin — most money-path holes closed by adding a row to `canonical_block_pins.yml` without touching the engine. Grep for comment-declared mirrors and ask: does each have a pin?
- **Cite a gate only for the class it truly catches.** `model_doc_sync` exiting 0 says nothing about prose — it compares *class names*. A green run quoted as proof of something adjacent is a counterfeit coin.

### A freshly-written gate is the worst-tested code in the repo

Mutation-verify proves it catches the INTENDED — nothing about what it cannot see. Two failure shapes are worse than "blind to a class", and both have shipped here **in the same session the gate was born**:

- **Dead scope under a green label.** `Tracker::Dashboard.stale_machine_who` anchored on `\z` while `each_line` keeps the trailing `\n` → the match failed on EVERY line, the HARD check did not exist, and the run printed "clean". An empty scope is indistinguishable from success. **In any line-scanning linter use `\Z` (or `chomp`), never `\z`** — and write a positive spec *for every scope*, otherwise "zero violations" means "zero checks".
- **A term that is a substring of the project's most frequent noun.** `ROI` ⊂ **gyroid** made the public manifesto read as three violations. Ask both "what does this regex NOT match?" and **"what does it match that it shouldn't — judged on the real hits, not on the intent."**

**Precision is measured in hits and lives in the ANCHOR.** Anchoring on individual words (`required`, `deterministic` — among the most common words in this canon) yielded 19% precision: 16 hits, 3 real. Narrowing to a **collocation** (`required status check` / `required-чек` / `PR-гейт`), demanding a number adjacent to the anchor, and scrubbing `TRL`/`§`/doc-ids took it to 100%. **A noisy advisory is a disabled gate**, so triaging every hit by eye is not optional.

### Ways a gate cannot see its own surface

1. **Decorative** — its INPUT sits outside the workflow's `changes:` filter, so it only ever fires on somebody else's PR (the `bio_contract.rb` hole; `.claude/**` repeated it later on a different gate). Reflex: **input ⊆ trigger-filter?** `guard_registry_sync` CHECK D now enforces this for pinned sources and mirror trees — but it is scoped to those, not to every guard tree.
2. **A whole GENRE outside every linter's namespace** — "Стаття N" headings; `08_03` carried `§1.1–§1.5` pointing at subsections that never existed, green for years. A genre exempt **by design** (`manifest.md`) is where drift is densest.
3. **A noisy advisory** — functionally off. Fix by narrowing the scope to one unit of work and grouping output (one line per file, detail behind `--verbose`), and by **naming the ceiling in the script header**: a semantic gate must declare what it cannot see, or green reads as "not checked".
4. **Blind to its own prose.** `workflow_gate_perimeter` read the workflows and its own Ruby constant, so its header comment could contradict that constant ("all eight" on line 6 vs "flip-pending" on line 10) and live that way until a prose-check was added. A gate sees data; it does not see what it says about itself.
5. **It under-implements the contract it declares.** Worse than #4, because the prose is *right* and the code is a subset. `stale_machine_who` stated its contract as a UNION in three homes (rake comment, spec comment, §3 row) and implemented one direction — it caught meta OVERSTATING and was structurally blind to meta UNDERSTATING, the costlier half (the meta-line is the scan layer, so a pure-👤 meta over machine work reads as "nothing here for me"). **Reflex: read what the gate SAYS it enforces, then check each direction of that sentence separately.** A bidirectional word — *union*, *parity*, *symmetric*, *round-trip*, *1:1* — is a promise of ≥2 checks; count them.

6. **It compares a HOMOGENEOUS pair and is blind to the seam between LAYERS** (I18N.1, 2026-07-26). The most reassuring gates compare like with like — locale↔locale, doc↔doc, workflow↔workflow — and a green run gets read as "this whole surface is fine". `i18n-tasks missing` compares every locale to every other and is structurally incapable of noticing that the *model's enum* grew while the YAML stood still: a display enum reached 14 values while the formatter knew 9, green the whole way. The sibling shape is worse — the pair that **no** gate compares: broadcast producers vs `turbo_stream_from` subscribers both live in the repo, nobody compares them, and eight producers were shipping into streams with zero listeners. **Reflex: name the two sets a gate compares, then ask which OTHER set this artifact must agree with — and whether anything checks that pair.** The cross-layer gate is usually a cheap spec (`Model.enum.keys` vs the locale file), not a linter. Corollary for such a spec: check the **base** locale only — cost then does not grow with the catalogue, and a newly-added, still-untranslated locale does not turn it red.

7. **A config mask switches the gate OFF, and the comment above it justifies a DIFFERENT problem** (I18N.1, 2026-07-26). `ignore_inconsistent_interpolations: ['*']` meant the CI step `i18n-tasks check-consistent-interpolations` could never fail — a green line in every build, checking nothing. The comment above it explained the mask with "UK has pluralisation forms en does not need", which is about the set of **keys**, not about `%{}` **variables**: a true sentence excusing an unrelated setting, which is exactly why nobody re-read it. It let a real bug through — a locale value carrying literal `#id` where every other locale had `#%{id}`. **Two reflexes.** (a) For every ignore/exempt/skip entry in a gate's config, ask *what would fail if I deleted this line* — here the answer was "nothing", the corpus was already clean and the mask was pure cost. (b) Read the justification against the setting, not against the code: a plausible sentence is not evidence that it describes THIS knob. A `'*'`-shaped exemption is never a tuning — it is a disabled gate wearing a config's clothes.

**Two traps specific to writing the second half** (both shipped, both caught by adversarial review the same day — the session's real yield):
- **Your exemption may rest on a premise your own code refutes.** The reverse-axis guard exempted three-executor items as "physically unsatisfiable in two slots" — while the `⚖️ ⊂ 👤` line three lines below collapsed the triple onto a legal pair. The exemption silenced the gate on ~12% of the corpus, including three instances of the exact pathology it was written for: **the fix legalised the disease it diagnosed.** Before writing `next if …`, construct the case you are excusing and run it.
- **Match on the LEADING token, never `include?` over the line.** A residual tagged `👤` may *cite* closed machine work in prose ("§5.3 вже 🤖-verified"); an `include?` scan reads that as open 🤖 and the "fix" writes a phantom claim into the meta-line — manufacturing the very drift the sibling gate guards. Both gates carried the defect, so they blinded each other and both stayed green. Anchor first, then count.

### Design rules

- **Self-consistency, not hardcode** — derive interdependent numbers from one parameter.
- **Context-anchor, never a bare number** — the same value is legitimate against different owners (provenance-mix at meV).
- **Pin an invariant, not a growing counter.** "8 Lorenz constants" is mathematics; "9 economic ones" grows, so the gate flags honest additions and gets switched off.
- **Two sets with an element MIGRATING between them → compare each separately, never their union** (GOV.2: a migration leaves the union unchanged, so a union-check is blind exactly on its own class).
- **A pin is one-directional** — `canonical_block_drift` hashes only `source:`; `mirrors:` is prose, so editing a mirror does not move the gate. Ceiling recorded in `00_06 §3`.
- **The gate form prescribed inside a tracker item is itself revisable** — do not implement a bad shape because an item named it.

### Mutation-verify: the pitfalls

- `git checkout` also reverts an UNCOMMITTED fix → mutate with a reverse `Edit`, not a checkout.
- **A money-path constant is its own hazard**: editing `GAMMA` tripped the permission classifier, and rightly — an interrupted session would have left the tree broken. Make the pin engine a **pure function** and mutate **in memory**.
- A mutation that fails to apply, or breaks syntax, proves **nothing** — check that it landed (and that the file still parses) before reading the result.
- **Verify by EXIT CODE after every batch**, never by `| tail` (a cut-off FAILED header reads green).

### Hardening checklist

`tolerance = 1 display digit, NOT 0.5` · `encoding=utf-8` · `findall == 1` ambiguity guard · coverage gaps · **a guard's CI job must be import-free stdlib** (a bare runner without numpy breaks CI in a way the author never sees locally; lib-importing guards belong in the conda job) · **propagation twins** — pinning only `SUMMARY` leaves stale twins when the path-filter never fires for them.

### Odds and ends that earned their line

A guard does not pin its own reason for existing · a golden test that validates DEFAULTS cements an off-spec number · a curated map is a tripwire (a dead entry must go RED) · science surfaces need a real guard, not `stan_audit` (symbols vs numbers — prove ingestion) · an honesty-pass that comes back POSITIVE is a preventive guard · **a skill mirror rots more quietly than canon → sweep the skills in every closing pass** · the best sort of mutation-proof is **a gate that catches its own author** (`DOC-T.15` line-refs and the vertical-list linter both bit the person writing them).

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
- [ ] ruby scripts/docs_check.rb          → green (fast: check_refs + tracker:check, no Rails)
- [ ] bin/rails docs:toc                  → run if headings changed, then re-check green
- [ ] ruby scripts/model_doc_sync.rb      → green (if 04_01/04_02 or app/models touched)
- [ ] ruby scripts/guard_registry_sync.rb → green (if a guard / 00_06 §3 / docs.yml touched)
- [ ] ruby scripts/workflow_gate_perimeter.rb → green (if .github/workflows/** touched — CI gate-perimeter, OPS.14: every PR-workflow classified required/advisory-by-design/flip_pending)
- [ ] ruby scripts/field_canon_sync.rb    → green (if github_bootstrap.rb / 00_05 §1.1 / labels.yml touched)
- [ ] ruby scripts/governance_key_sync.rb / governance_bounds_sync.rb → green (if contracts/** · app/** · db/seeds.rb touched — GOV.2/GOV.3 param parity)
- [ ] ruby scripts/code_tracker_id_check.rb → green (if code cites a tracker-ID, or 00_07 IDs moved)
- [ ] linter/ToC specs green              → if lib/docs_*.rb touched
- [ ] fact edited ONLY at its home (§8.2); mirrors labelled
- [ ] no volatile counts · no blocker section in canon · Cross-references at top
```

**Wiki publish — ZERO-TOUCH** (since 2026-06-24): `.github/workflows/wiki.yml` publishes on every push to `main` touching `docs/**` (off-switch: repo var `DISABLE_WIKI_AUTOSYNC=true`). Do **NOT** run `wiki:sync PUSH=1` by hand after a normal canon-push — it RACES the CI run (non-fast-forward reject). A manual `bin/rails wiki:sync` (dry-run) stays a useful link-check before a big restructure. Detail → `[[project_wiki_sync]]`.

## Gotchas (hard-won)

- **Subset `bin/rspec` runs trip the SimpleCov coverage gate** ("Models 0% < 90%" / `minimum_coverage`). That's an **artifact** of a partial resultset, not a real failure. The linter/ToC specs are pure units (`spec_helper`, no Rails/DB) — run them gate-free with `COVERAGE=0 bin/rspec spec/lib/docs_*_spec.rb`; for app-coverage truth run the full `bin/rspec` (`[[feedback_local_verify]]`).
- **`db/structure.sql`**: never stage drive-by Postgres-version line diffs — restore from HEAD (`[[feedback_structure_sql]]`).
- **No volatile counts in prose** (test/line tallies drift every commit). Reference the source or generate it (`[[feedback_no_volatile_counts]]`).
- **`wiki:sync` needs SSH access** to the `*.wiki.git` repo; **always dry-run first**; read its "unresolved links" — they're often stale source links worth fixing. **Run it PLAIN** — never prepend `/usr/bin` to PATH (shadows the rvm ruby shim → system Ruby 2.6 → bundler crash); a `Gem::Resolver…GemParser` trace can also be a SentinelOne-eaten shim (`[[project_rvm_env_repair]]`).
- **A missing closing ` ``` ` fence silently desyncs EVERY fence-aware guard** (the `in_fence` toggle runs in ~9 `DocsLinter` methods) + truncates the ToC — one unclosed fence disables them all at once. **Now HARD-gated**: `DocsLinter.unbalanced_code_fences` (DOC-T.45, 2026-07-18) counts fences by the SAME `line.start_with?` predicate the guards use, so `docs:check_refs` aborts on an odd count (reporting the opening line) — a mirror gate, self-consistent with what it protects.
- **A freshly-written guard can be pure decoration, and a green baseline HIDES it** — the `\z`-vs-`\Z` dead-scope class (DOC-T.52). Full account, with the other blindness shapes, in **§Guard-craft** above; it is the reason recipe step 4 is not optional.
- **Homoglyph / mixed-script drift** — a Cyrillic letter hiding inside a Latin word (`geniпin`-class) passes every ASCII gate. Detector = a perl per-letter-run scan flagging any `\p{L}+` run that carries Latin+Cyrillic TOGETHER; run it after chemistry-name work (ligand / enzyme names are the usual carriers).
- **`.c` firmware comments stay Ukrainian + the file's poetic house style** (`[[feedback_comment_style]]`).
- **zsh**: `status` is read-only; quote globs (`[[feedback_zsh_bash_gotchas]]`).
- **Required-check caveat**: if `ci.yml` jobs are *required* status checks, also mark `docs.yml`'s gate required — else a docs-only PR (which skips `ci.yml`) could merge without the gate enforced.

## Keep this skill bounded

This file is the **method**. It must not accumulate: the *standard* → `00_06`; *state / backlog* → memory; a *new guard's definition* → `lib/docs_linter.rb` + `00_06 §3`. If you're tempted to add a fact here, it belongs in one of those homes — that discipline is the very thing this skill enforces.
