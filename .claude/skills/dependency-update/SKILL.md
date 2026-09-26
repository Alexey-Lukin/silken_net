---
name: dependency-update
description: "Use when updating dependencies in ANY domain of this polyglot repo — Ruby gems (Gemfile/Gemfile.lock), the Ruby version itself, bundler, CI workflow actions (.github/workflows), JS/importmap, the conda ML + in-silico envs (tools/ml, tools/in_silico), the firmware C submodules (firmware/extern), the Terraform providers (terraform/*.tf required_providers), the .NET NuGet pins of tools/cad (Directory.Packages.props — PicoGK), the Solidity/Foundry contracts (OpenZeppelin/solc/forge-std), the subgraph toolchain (subgraph/package.json), or the runtime images (Dockerfile base digest, Kamal accessory images). Per-dependency: read THIS version's changelog → classify (security/breaking/behavior/routine) + grep our usage (direct vs transitive) → domain-appropriate validation (the recipe table) → capture the research in the commit body (founder bar: every dep researched, no separate doc). Knows the per-domain inventory/validation recipes; the hard-won gotchas (release-age quarantine, transitive caps, CI-gated firmware/Solidity validation, …) are indexed one line each and written in full in gotchas.md, which loads on demand — open it before merging, bumping, pinning or quarantining a dependency. Examples: \"update the gems\", \"bump Ruby to latest\", \"what's outdated\", \"update the CI actions\", \"bump OpenZeppelin / solc\", \"update the firmware submodules\", \"update the ML / in-silico conda env\", \"bump the terraform / google provider\", \"run the dependency sweep\"."
---

# Dependency Update (every manifest, every domain)

The *executable playbook* for updating dependencies anywhere in this polyglot repo —
Ruby gems, Ruby itself, bundler, CI actions + their payload pins, JS/importmap, the conda
ML + in-silico envs, the firmware C and CAD git submodules, the Terraform providers, the
.NET CAD NuGet pins, the Solidity/Foundry contracts, the subgraph npm toolchain, and the
runtime images. This skill is the **HOW +
the per-domain recipes**; it does **not** restate versions or track which bump shipped
(that lives in git commit bodies + `bundle outdated`/`gh` at run time).

> **Founder bar (load-bearing):** *every dependency is researched individually* — read
> its release notes / CHANGELOG, classify the change, decide, validate — **before** the
> bump. "No one comes back to those changelogs a second time", so the research is captured
> **in the commit body** (NOT a separate doc). Security fixes and breaking changes are the
> findings that matter; routine patches still get a one-line classification.

## Core loop (per dependency)

```
0. ALERTS     read the OPEN security alerts FIRST — they are a channel no
              "outdated" command covers, and nothing else in the repo forces
              you to open them: `gh api repos/:owner/:repo/dependabot/
              alerts --paginate -q '.[] | select(.state=="open")'`.
              🔑 These alerts read the GitHub Advisory DB; `Sec · Gem Audit`
              (daily) and `scan_ruby` read ruby-advisory-db. No lane reads this
              channel but you (why two bases → `06_07 §1a`, OPS.26).
              🔴 An alert's `first_patched_version` is the GitHub DB's knowledge,
              not upstream's. Before taking the «smallest sufficient» version,
              read the package's OWN advisories (`gh api repos/<o>/<r>/
              security-advisories`): GitPython 3.1.59 closed all five open
              alerts and was itself hit by four advisories upstream had already
              published — one of them on 3.1.59 alone [OPS.22, 2026-09-13].
              🔴 Default gems (`resolv`, `json`, `erb`, `net-*` …) are in NEITHER
              channel until pinned in the Gemfile — read the ruby-lang security
              news by hand: `resolv` CVEs sat 23 days with zero alerts (`#47`).
1. INVENTORY  what's behind: the domain's "outdated" command (table below).
2. RESEARCH   read THIS version's changelog/release-notes (web/gh). Classify:
              security(CVE) · breaking · behavior/default · feature · routine/regen.
              Does it touch OUR code/usage? (grep the symbol — direct vs transitive.)
3. DECIDE     bump unless a transitive cap blocks it or the risk outweighs the benefit.
              In-silico/physics: bump if it gives MORE-CORRECT/better results, not just "newer".
              Release-age quarantine: a version <~7d old waits unless a needed security
              fix OR an examined publisher profile discharges it (`#4`, `#16`).
4. VALIDATE   the domain's gate (table). Deprecation warnings → RESOLVE (`#40`).
              🔴 A green suite does NOT prove the call-sites were fixed: a spec that
              patches the gem's OWN API outside the RSpec mock-API makes the bump
              unverifiable. Measured on Pagy 43 (TEST.12): the base class lost its
              constructor (`Pagy::Offset.new` now), ONE of two call-sites was migrated,
              and `Pagy.define_singleton_method(:new) { |**_kwargs| … }` in a component
              spec kept the other one green while it 500'd in production. So after any
              MAJOR bump also grep `spec/` for `define_singleton_method`/`define_method`
              on that gem's constants or instances, and for `OpenStruct` twins of its
              objects — `allow(Gem).to receive(:x)` is safe (it goes
              through `verify_partial_doubles` and reddens when the method disappears),
              a raw singleton definition is not. And the cheapest tell that a migration
              is HALF-done is asymmetry: two call-sites, one on the new API.
5. CAPTURE    commit `-s` (standing founder authorization: commit+push main when
              validated; the wiki publishes itself via `wiki.yml` — never run
              `wiki:sync` by hand). Commit body = the per-dep research. Separate
              concerns into separate commits where sensible.
```

## Ripe-merge loop (draining the OPEN Dependabot PR queue)

The loop above bumps ONE dependency; this one drains the queue someone else opened. ⚖️ **Cadence is a founder decision: a MANUAL pass — never cron, never a cloud agent.** Quarantine and cap judgement do not automate, and a handful of low-value PRs does not pay for auto-merge infrastructure. Do not propose a cron for it.

```
1. gh pr list --state open --label type:deps     re-confirm the open set.
                                                 ⛔ NOT the whole queue: lock-only
                                                 transitives never get a PR (`#48`).
2. STALE BASE → `@dependabot rebase` FIRST       green on an old base proves nothing (`#17`).
3. FIVE per-PR gates, all of them:
     · release-age ≥7 d measured AFTER the rebase (`#4`, `#5`)
     · CI green LIVE-verified — `gh pr checks`, read the `CI passed` line;
       ⛔ NEVER `| tail`, it hides a FAILED header. Judge by STATE, not colour (`#25`)
     · changelog read BY VERSION, not by gem (`#20`)
     · the diff dated LINE BY LINE — a ripe title can carry a 3-day passenger (`#11`)
     · SHA pin == tag (`#30`)
4. gh pr merge <n> --squash --delete-branch
4a. A HELD package goes back in the queue WITH ITS VERDICT, not just its ripen date:
     a date, once passed, reads as a MANDATE, so the next pass takes the package
     «because it ripened» and does sincere work worth nothing. Write the REFUSAL
     beside the date (transitive · ceiling satisfied by the old version · no gain),
     and ⛔ never a COUNT of held packages — the queue grows (`no-volatile-counts`).
5. CANON SWEEP — re-grep the OLD version literals for every gem/action the docs quote (`#42`).
   No gate compares a `@vN` written in prose against `.github/`; this step is the only carrier.
```

## Domains — inventory + validation recipes

⚙️ **What Dependabot watches, and what it deliberately does NOT** (`.github/dependabot.yml` is the SSOT — read it, this is the shape): **five automated ecosystems** (bundler · docker · github-actions incl. the composite dir · npm in `contracts` · terraform) and **two kept MANUAL on purpose** — **conda**, because `conda-lock.yml` exists for reproducibility and a bot bump would defeat it, and the **firmware submodules**, whose cadence is the bench and whose validation is QEMU-parity. ⛔ A domain absent from that file is not "unwatched by oversight": several here have no ecosystem at all (NuGet/.NET, `#44`'s payload pins), so the inventory perimeter is the table below, never the bot's config.

| Domain | Manifest(s) | "What's behind" | Validate (+ linter) |
|---|---|---|---|
| **Ruby gems** | `Gemfile` / `Gemfile.lock` | `bundle outdated` | full `bin/rspec` under the project Ruby; `bin/rubocop` |
| **Ruby itself** | `.ruby-version` (SSOT) + every file in `MIRRORS` (`scripts/ruby_version_sync.rb`) + `Gemfile.lock` `RUBY VERSION` (bundler rewrites it; not a `MIRRORS` entry) — ⛔ never an `ARG`-indirected `FROM` (why → `06_07 §1a`) | `rvm install`; web changelog | `rvm use ruby-<v>@silken_net` then full `bin/rspec`; then read the parity gate's HEADER, not only its `MIRRORS` — it is the checklist of what the gate does NOT judge: the digest behind the tag (verify via the registry) and `docker_smoke` as the build half (confirm on `main` that the job RAN, not skipped) |
| **bundler** | `Gemfile.lock` BUNDLED WITH | `gem list bundler --remote --exact` | `bundle update --bundler=<v>` |
| **CI actions** | `.github/workflows/*.yml` + `.github/actions/*/action.yml` (every `uses:` is SHA-pinned) | per action: `gh api repos/<org>/<repo>/releases/latest` vs the `# vN` label beside the SHA; resolve the new tag's SHA per `#30` | actionlint (`workflow_lint` in `ci.yml`) + the action's changelog (breaking inputs); payload pins → `#43`/`#44` |
| **JS / importmap** | `config/importmap.rb` **+ `vendor/javascript/` + `vendor/assets/stylesheets/`** + 🔴 **нотіс-шар [UNI.3]: `vendor/javascript/LICENSE-leaflet.txt` (ОДИН дім тексту; у CSS-теці покажчик, не копія) + рядки в `THIRD_PARTY_NOTICES` і `/NOTICE`** | `bin/importmap outdated` + `bin/importmap audit` — ⚠️ бачить лише JS-піни; ⛔ **вендорені байти не бачить ЖОДЕН маніфест-інструмент**: кореневого `package.json` нема, Leaflet приходить голим `pin`, а `spdx_headers.rb` свідомо DENY-листить `vendor/` | boot + asset-compile + `bin/rspec spec/features` (Leaflet будується в браузері) + `COVERAGE=0 bin/rspec spec/quality/vendored_component_inventory_spec.rb` — червонить БУДЬ-який новий компонент у `vendor/**` без рядка в інвентарі. ⚠️ Бампаючи версію, звір copyright-рядок нотіса проти `@preserve`-банера НОВОГО бандла: він єдине джерело, що їде разом із кодом |
| **ML conda** | `tools/ml/environment.yml` + `pyproject.toml` | `mamba run -n silken_ml python -m pip list --outdated` (pip subset; conda-forge packages → ask the channel, `#18`) | `pytest tools/ml/tests` (librosa≡stdlib parity) + `silken-ml-gen-logmel --check` + `make -C firmware/test logmel`; `ruff check` |
| **in-silico** | `tools/in_silico/environment.yml` + **`conda-lock.yml`** (the real pin) + `requirements-conda-lock.{in,txt}` (`#3`, `#36`) + `requirements-pytest.{in,txt}` | `mamba run -n silken_md python -m pip list --outdated` (bare `pip list` returns 0 rows here) for the pip subset; conda-forge packages → ask the channel (`#18`) against `conda-lock.yml` | rebuild + **re-run DFT vs `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`** + `conda-lock lock --check-input-hash` (the `lock_sync` job); `ruff check` |
| **firmware C** | every git submodule under `firmware/extern/` — ⛔ take the count from `git submodule status`, never from prose: a hardcoded number here silently trims the newest entries off the sweep perimeter, and the newest are `subghz-phy` (radio, board-freeze gated) plus our OWN LoRaWAN fork, whose UB fix must be re-verified on every bump | `gh api repos/<org>/<repo>/releases\|tags` vs `git submodule status` | host CMSIS-parity ctest (local) + `make -C firmware/test`; ARM build + QEMU parity (**CI-only** — arm-gcc/qemu not local) |
| **Solidity** | `contracts/{foundry.toml,package.json,package-lock.json}` + `*.sol` pragmas + `contracts/requirements-{halmos,crytic}.{in,txt}` (hash-locked CI tools) + the aderyn/medusa `ver=`+sha256 steps in `solidity_audit.yml` | `gh api` OZ/solc/forge-std latest | `forge test` (local) + `forge fmt --check`; `slither` (**CI-only**) |
| **Terraform** | `terraform/*.tf` `required_providers` **+ `.terraform.lock.hcl`** (a manifest of this domain — refresh only as in `#39`) | `gh api repos/hashicorp/terraform-provider-<p>/releases/latest` vs the exact `version` in `.terraform.lock.hcl` (and the `~>` range in `main.tf`) | `terraform validate` + `terraform fmt -check`; `terraform plan` (**CI/creds-gated** — needs GCP creds + state) |
| **.NET CAD (NuGet + submodules)** | `tools/cad/Directory.Packages.props` (central pins — no Dependabot ecosystem is CONFIGURED for it: `.github/dependabot.yml` has no `nuget`/`dotnet-sdk` entry, so bumps are by hand) + `tools/cad/global.json` (SDK) + git submodules `tools/cad/extern/LEAP71_{ShapeKernel,LatticeLibrary}` (source-only) | `dotnet list tools/cad/SilkenCad.sln package --outdated`; submodules: `git ls-remote` vs `git submodule status` (`#10`) | `dotnet build` 0W/0E + `dotnet test` (skill `picogk`, Local-verify). 🔴 **A `PicoGK` bump is a KERNEL change, and two measured verdicts rest on the kernel version: re-run `dotnet run -- probe 0.34` / `probe 0.33` (`picogk` #1) and the `00_07` HW.49 raw ⊥ normalised porosity re-measure (`picogk` #4)** |
| **Subgraph (The Graph)** | `subgraph/{package.json,package-lock.json}` — `@graphprotocol/graph-cli` + `graph-ts` + `matchstick-as`, усі пінені ТОЧНО (без `^`): саме CLI вирішує, який `specVersion`/`apiVersion` приймається, а діапазон був би чужим рішенням про наш контракт; **плюс блок `overrides`** — його дім тут, бо JSON коментарів не має. 🔑 **ПІДСТАВА блоку, без якої наступний свіп зніме його як «зайві піни» [OPS.35]:** `gluegun@5.2.0` пінить `cross-spawn`/`ejs`/`semver` ТОЧНИМИ версіями, тож npm не міг задедуплікувати їх із патченими копіями, що вже стояли в цьому ж дереві; `overrides` лише ДОЗВОЛЯЄ дедуп, нових версій не тягне (виміряно: `npm audit` 15 → 4, алерти 44 → 4). ⛔ Альтернативи виміряно й відкинуто: апстрім не лікує (`latest` = наша версія, `alpha` тягне той самий `decompress`, `audit fix --force` = відкат на сім мінорів), `--ignore-scripts` порожній (install-хуків у дереві нуль). ⛔ Залишкові (`decompress` · `uuid` · `stream-json`) НЕ чіпаємо, і підстава — не «dev-scope» і не одна на всіх (`tolerable_risk` ⊥ `not_used`, `#35`): `decompress` кличе лише `graph node`, якої CI не викликає; `uuid` — через `jayson`, який кличе тільки `v4()` без буфера, а адвізорі стосується `v3`/`v5`/`v6` з `buf` (так само `stream-json`: `jayson` бере `StreamValues`+`Verifier`, не вразливі path-фільтри) — клас → `#46`; тому бампу `uuid` 8→11 через `overrides` не робити. 🔑 **Алерти дивляться на дерево ПАКЕТІВ, а виконується дерево ВИКОНАННЯ** [OPS.35]: `@oclif/plugin-warn-if-update-available` — `init`-хук на КОЖНІЙ команді `graph`, detached spawn, що читає npm-креденшл і йде на реєстр нативним `https` — єдиний мережевий виклик збірки, невидимий жодному сканеру. Бампаючи будь-що в цій теці, **міряй дельту на КЛОНІ** (`cp package.json package-lock.json` у scratchpad → `npm i --package-lock-only` → `npm audit --package-lock-only`); два devDep не є одним класом лише тому, що обидва devDep | `npm view @graphprotocol/graph-cli dist-tags` (⚠️ `latest` буває = наша версія, а «свіжіше» — лише `alpha`/`rc` → карантин за невідомістю); `npm audit` ⊥ `gh api …/dependabot/alerts` — **дві РІЗНІ бази**, числа розходяться в рази | `npm ci` → `sh ./validate_addresses.sh` → `npx graph codegen` → `npx graph build` → `npx graph test` (`build` компілює проти `generated/`, тож `codegen` перед ним несучий). ⚠️ Перш ніж стверджувати тотожність із `subgraph.yml`, перечитай його `run:`-кроки: локальний рецепт, що заявляє рівність із воркфлоу, стає вужчим того дня, коли там додається крок |
| **Runtime images** | `Dockerfile` `FROM` tag+digest · Kamal `accessories.*.image` in `config/deploy*.yml` (no Dependabot lane reads the accessories) | Hub `tag_last_pushed` + registry `docker-content-digest` (`#5`) — a digest re-push is invisible to every version-based inventory | `docker_smoke` (in `ci.yml`, required); accessories by hand on the deploy path |

`rvm use ruby-<v>@silken_net` / `mamba run -n <env>` prefixes are MANDATORY per Bash call — shell
state does not persist between calls. Name the **full gemset** (repo pins `.ruby-gemset=silken_net`):
`rvm use ruby-<v>` *without* `@silken_net` selects the empty default gemset → `Bundler::GemNotFound`
for every gem (not `RubyVersionMismatch`); a bare `rvm use <v>` prints "Unknown ruby interpreter"
and returns non-zero, so it breaks an `&&` chain (the real command never runs). Bites
`run_in_background:` Bash hardest (the login profile's gemset auto-select isn't reliable there) —
`bundle check` before a long suite run.

## Hard-won gotchas

**Bodies live in [`gotchas.md`](gotchas.md) — open it before you merge, bump, pin or quarantine a
dependency.** One generated line per gotcha below: the line is the CARRIER, meant to stop you
mid-action; the mechanism, the incident and the bounds are in the companion. Numbered 2026-09-19 in
the pre-split order, append-only since — cite `dependency-update #N`.

<!-- DEPUPDATE-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. A vendored front-end package has its version in TWO places, and the tool sees only one
2. Post-cutoff versions are real. This repo runs ahead of the model's knowledge cutoff
3. `--upgrade-package` names a target; it does NOT bound the resolution
4. Release-age quarantine: a version younger than ~7 days waits — but the clock is a PROXY for how UNEXAMINED the release is, so weigh the publisher profile, not the calendar
5. The age rule cuts BOTH ways — a fresh PR can carry a long-ripe artifact
6. A version perimeter is WIDER than its gate, and half the hits must NOT be edited
7. An owner-only drift guard watches PROSE; tool config satellites are outside it forever
8. After ANY generator writes, run the WHOLE lane — it touches files your diff never named
9. Measure a dependency's risk from the FILE DIFF against YOUR call path, not from the changelog
10. A «bump needed» verdict on a git-pinned dependency is unverified until `git ls-remote` shows a newer ref — a dormant upstream means STUCK, not BEHIND
11. Age the DIFF, not the PR title: a PR named for one ripe dependency can carry fresh transitives in the same lock-diff
12. A PR can be green BECAUSE something MASKS its breaking passenger — and then a green suite is evidence of the mask, not of compatibility
13. `@dependabot rebase` changes the TARGET, not just the base
14. A required check added AFTER the PR opened is ABSENT, not red
15. A SHA-pinned action does NOT pin its own contents
16. Identical failure on N INDEPENDENT PRs ⇒ the root is in the BASE, not in the PRs
17. A change YOU make to the BASE invalidates every open PR's green, and nothing marks them stale
18. A floor may only name what the CHANNEL can serve — and a resolver's «does not exist» is a claim about the INDEX it loaded, not about the channel
19. A «minor» can rework the very mechanism your GATE stands on — and then «suite green» is not the validation
20. Read a scary changelog line against OUR call, not against its own framing
21. A changelog line that reads as housekeeping can still change what LEAVES the building — for every major, scan the notes for «default-on» / «removed the flag» before the API diff
22. The SAME failure on N INDEPENDENT PRs means the root is on `main`, not in any diff
23. «This major touches OUR call-sites» is a claim about a FILE — open it before writing the carve-out
24. A PR's green check has a DATE, and the advisory DB moves independently of it — so an old green attests to a world where the CVE did not yet exist
25. Judge the checks on the NEW head by STATE, never by colour — `SKIPPED` wears the same green as `SUCCESS`
26. The RED check has a date too — and a green neighbour does not disprove it
27. `built_at` on rubygems is DEAD as an age signal — it returns `1980-01-02`
28. A security patch can EXPOSE a latent debt rather than break you — read the failure that way first
29. Adding a NATIVE gem can make require ORDER load-bearing
30. SHA==tag verification has a wrong endpoint that reads as a mismatch
31. The version COMMENT beside a SHA pin is a convention, and Dependabot preserves whichever form it finds — so "unifying" it is a silent convention change riding a `build(deps)` subject
32. A gate that did not RUN is not green
33. A green Dependabot PR can still break `main`
34. Transitive caps block "latest" — and that's not our drift
35. GitHub caps `dismissed_comment` at 280 and answers 422 — send dismissals one by one, ≤280 BYTES, or one long reason half-applies the batch
36. Conda `>=` env vs lock: the ML env is a loose `>=` floor spec, while in-silico runs on a real `conda-lock.yml`
37. CI actions are SHA-pinned with a `# vN` label — nothing auto-flows; every bump, patch included, arrives as a Dependabot PR and is dated like any other
38. Firmware/Solidity full validation is CI-gated (ARM build + QEMU; slither) — locally only the host gates run
39. Terraform provider majors are big breaking migrations — read the per-major upgrade guide, never blind-bump
40. Deprecation/future-keyword warnings: resolve them in OUR code; in vendored code they are upstream's — note, don't touch
41. `db/structure.sql` / `Gemfile.lock`: verify the diff is ONLY the intended dep (no drive-by churn) before committing
42. Canon docs mirror pinned versions — sweep them too (a bump is not done at the manifest)
43. Dependabot pins the WRAPPER, never the payload — so every payload pin in this repo is bumper-less BY CONSTRUCTION
44. Enumerate payload pins from source with one grep, and draw a hardening perimeter by WHO INSTALLS the tool (workflow ⊥ action image ⊥ action input), never by which job it runs in
45. The `slither-version` pin and the leaflet version are dated upstream NEGATIVES — re-check each with two HTTP calls before re-deriving either
46. Ask a transitive advisory whether it names the API our consumer ACTUALLY calls — non-applicability outlives the upstream fix
47. A DEFAULT gem is invisible to BOTH advisory channels until it is pinned in the `Gemfile` — so step 0 must read the ruby-lang security feed by hand
48. A DAILY-release gem makes `latest` almost never ripe — and `bundle update --conservative` fetches exactly `latest`
49. Before "update the tool", ask whether the needed version is ALREADY in the tree by another path
50. A ZERO from an inventory command is a claim about the INSTRUMENT until a positive control says otherwise
51. `pip-compile` resolves markers for the platform that COMPILES, and a flag that names a target may bound nothing
52. "How many vulnerabilities do we have" is a choice of INSTRUMENT, not a fact — and severity is the wrong third axis
53. A dismissal whose alert KEY carries a version is a treadmill — the next bump reopens it under a new number, so fix the SOURCE, not the instance
54. A scanner's declared filter can be INERT on one output path — read the wrapper action's entrypoint at the pinned SHA, not its input list

<!-- /DEPUPDATE-GOTCHAS-INDEX -->

## Keep this skill bounded

This is the **method + recipes**. Versions/results → git commit bodies; "what shipped" →
`git log`; the standard for SSOT docs → `ssot-maintenance`; ML parity internals →
`ml-engineering`. If you're tempted to record a specific version here, it belongs in a commit body.
