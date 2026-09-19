---
name: dependency-update
description: "Use when updating dependencies in ANY domain of this polyglot repo — Ruby gems (Gemfile/Gemfile.lock), the Ruby version itself, bundler, CI workflow actions (.github/workflows), JS/importmap, the conda ML + in-silico envs (tools/ml, tools/in_silico), the firmware C submodules (firmware/extern), the Terraform providers (terraform/*.tf required_providers), the .NET NuGet pins of tools/cad (Directory.Packages.props — PicoGK), or the Solidity/Foundry contracts (OpenZeppelin/solc/forge-std). Per-dependency: read THIS version's changelog → classify (security/breaking/behavior/routine) + grep our usage (direct vs transitive) → domain-appropriate validation (the recipe table) → capture the research in the commit body (founder bar: every dep researched, no separate doc). Knows the per-domain inventory/validation recipes; the hard-won gotchas (release-age quarantine, transitive caps, CI-gated firmware/Solidity validation, …) are indexed one line each and written in full in gotchas.md, which loads on demand — open it before merging, bumping, pinning or quarantining a dependency. Examples: \"update the gems\", \"bump Ruby to latest\", \"what's outdated\", \"update the CI actions\", \"bump OpenZeppelin / solc\", \"update the firmware submodules\", \"update the ML / in-silico conda env\", \"bump the terraform / google provider\", \"run the dependency sweep\"."
---

# Dependency Update (every manifest, every domain)

The *executable playbook* for updating dependencies anywhere in this polyglot repo —
Ruby gems, Ruby itself, CI actions, JS/importmap, the conda ML + in-silico envs, the
firmware C submodules, and the Solidity/Foundry contracts. This skill is the **HOW +
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
              🔑 Why this step survives even though a scheduled `bundler-audit`
              now exists (`Sec · Gem Audit`, daily — OPS.26 ratified the split):
              the two channels read DIFFERENT databases. `bundler-audit` reads
              ruby-advisory-db; these alerts read the GitHub Advisory DB. So the
              scheduled lane covers the base that blocks merges, and NOTHING
              covers this one but you. ⚠️ Still true, and narrower than it used
              to be: a green `main` alone says nothing, because the in-CI
              `bundler-audit` lives in the path-gated `scan_ruby` job — an
              advisory against an UNCHANGED lock is invisible to *that* job
              until someone opens a code PR. The daily lane is what closes that
              window; the PR lane never did.
              🔴 An alert's `first_patched_version` is the GitHub DB's knowledge,
              not upstream's. Before taking the «smallest sufficient» version,
              read the package's OWN advisories (`gh api repos/<o>/<r>/
              security-advisories`): GitPython 3.1.59 closed all five open
              alerts and was itself hit by four advisories upstream had already
              published — one of them on 3.1.59 alone [OPS.22, 2026-09-13].
1. INVENTORY  what's behind: the domain's "outdated" command (table below).
2. RESEARCH   read THIS version's changelog/release-notes (web/gh). Classify:
              security(CVE) · breaking · behavior/default · feature · routine/regen.
              Does it touch OUR code/usage? (grep the symbol — direct vs transitive.)
3. DECIDE     bump unless a transitive cap blocks it or the risk outweighs the benefit.
              In-silico/physics: bump if it gives MORE-CORRECT/better results, not just "newer".
              Release-age quarantine: skip a version <~7d old unless it's a needed security fix (gotchas).
4. VALIDATE   the domain's gate (table). Deprecation warnings → RESOLVE, don't leave
              (rename identifiers, fix call-sites) — unless they're in vendored code.
              🔴 A green suite does NOT prove the call-sites were fixed: a spec that
              patches the gem's OWN API outside the RSpec mock-API makes the bump
              unverifiable. Measured on Pagy 43 (TEST.12): the base class lost its
              constructor (`Pagy::Offset.new` now), ONE of two call-sites was migrated,
              and `Pagy.define_singleton_method(:new) { |**_kwargs| … }` in a component
              spec kept the other one green while it 500'd in production. So after any
              MAJOR bump also grep `spec/` for `define_singleton_method`/`define_method`
              on that gem's constants — `allow(Gem).to receive(:x)` is safe (it goes
              through `verify_partial_doubles` and reddens when the method disappears),
              a raw singleton definition is not. And the cheapest tell that a migration
              is HALF-done is asymmetry: two call-sites, one on the new API.
5. CAPTURE    commit (standing founder authorization: commit+push main + wiki:sync when
              the work is validated). Commit body = the per-dep research. Separate
              concerns into separate commits where sensible.
```

## Domains — inventory + validation recipes

| Domain | Manifest(s) | "What's behind" | Validate (+ linter) |
|---|---|---|---|
| **Ruby gems** | `Gemfile` / `Gemfile.lock` | `bundle outdated` | full `bin/rspec` under the project Ruby; `bin/rubocop` |
| **Ruby itself** | `.ruby-version`·`Gemfile`·`Gemfile.lock`·`Dockerfile`·AGENTS.md·CLAUDE.md·copilot·.rvmrc·06_01 — ⛔ the authoritative list is `MIRRORS` in `scripts/ruby_version_sync.rb`, not this cell; and ⛔ NEVER introduce an `ARG`-indirected `FROM`: Dependabot cannot bump a tag through it (dependabot-core #4597), so the tag stays literal | `rvm install`; web changelog | `rvm use <v>` then full `bin/rspec` |
| **bundler** | `Gemfile.lock` BUNDLED WITH | `gem list bundler --remote --exact` | `bundle update --bundler=<v>` |
| **CI actions** | `.github/workflows/*.yml` | per action: `gh api repos/<org>/<repo>/releases/latest` (or `/tags`) vs our `@vN` | YAML parse; the action's changelog (breaking inputs) |
| **JS / importmap** | `config/importmap.rb` **+ `vendor/javascript/` + `vendor/assets/stylesheets/`** + 🔴 **нотіс-шар [UNI.3]: `vendor/javascript/LICENSE-leaflet.txt` (ОДИН дім тексту; у CSS-теці покажчик, не копія) + рядки в `THIRD_PARTY_NOTICES` і `/NOTICE`** | `bin/importmap outdated` + `bin/importmap audit` — ⚠️ бачить лише JS-піни; ⛔ **вендорені байти не бачить ЖОДЕН маніфест-інструмент**: кореневого `package.json` нема, Leaflet приходить голим `pin`, а `spdx_headers.rb` свідомо DENY-листить `vendor/` | boot + asset-compile + `bin/rspec spec/features` (Leaflet будується в браузері) + `COVERAGE=0 bin/rspec spec/quality/vendored_component_inventory_spec.rb` — червонить БУДЬ-який новий компонент у `vendor/**` без рядка в інвентарі. ⚠️ Бампаючи версію, звір copyright-рядок нотіса проти `@preserve`-банера НОВОГО бандла: він єдине джерело, що їде разом із кодом |
| **ML conda** | `tools/ml/environment.yml` + `pyproject.toml` | `pip list --outdated` in `silken_ml` | `pytest tools/ml/tests` (librosa≡stdlib parity) + `silken-ml-gen-logmel --check` + `make -C firmware/test logmel`; `ruff check` |
| **in-silico** | `tools/in_silico/environment.yml` + **`conda-lock.yml`** (the real pin) | `pip list --outdated` in `silken_md`; `gh` latest | rebuild + **re-run DFT vs `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`**; `ruff check` |
| **firmware C** | every git submodule under `firmware/extern/` — ⛔ take the count from `git submodule status`, never from prose: a hardcoded number here silently trims the newest entries off the sweep perimeter, and the newest are `subghz-phy` (radio, board-freeze gated) plus our OWN LoRaWAN fork, whose UB fix must be re-verified on every bump | `gh api repos/<org>/<repo>/releases\|tags` vs `git submodule status` | host CMSIS-parity ctest (local) + `make -C firmware/test`; ARM build + QEMU parity (**CI-only** — arm-gcc/qemu not local) |
| **Solidity** | `contracts/{foundry.toml,package.json,package-lock.json}` + `*.sol` pragmas | `gh api` OZ/solc/forge-std latest | `forge test` (local) + `forge fmt --check`; `slither` (**CI-only**) |
| **Terraform** | `terraform/*.tf` `required_providers` **+ `.terraform.lock.hcl` (COMMITTED since 2026-09-06 — it is a manifest of this domain, not an optional extra; ⛔ refresh only via `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`)** | `gh api repos/hashicorp/terraform-provider-<p>/releases/latest` vs the `~>` pin | `terraform validate` + `terraform fmt -check`; `terraform plan` (**CI/creds-gated** — needs GCP creds + state) |
| **.NET CAD (NuGet)** | `tools/cad/Directory.Packages.props` (central pins — no Dependabot ecosystem reads it, so bumps are by hand) + `tools/cad/global.json` (SDK) | `dotnet list tools/cad/SilkenCad.sln package --outdated` | `dotnet build` 0W/0E + `dotnet test` (skill `picogk`, Local-verify). 🔴 **A `PicoGK` bump is a KERNEL change, and two measured verdicts rest on the kernel version: re-run `dotnet run -- probe 0.34` / `probe 0.33` (`picogk` #1) and the `00_07` HW.49 raw ⊥ normalised porosity re-measure (`picogk` #4a)** |
| **Subgraph (The Graph)** | `subgraph/{package.json,package-lock.json}` — `@graphprotocol/graph-cli` + `graph-ts`, обидва пінені ТОЧНО (без `^`), бо саме CLI вирішує, який `specVersion`/`apiVersion` приймається; **плюс блок `overrides`** — його дім тут, бо JSON коментарів не має. 🔑 **ПІДСТАВА блоку, без якої наступний свіп зніме його як «зайві піни» [OPS.35, 2026-08-27]:** корінь був не в старому CLI, а в тому, що `gluegun@5.2.0` пінить `cross-spawn`/`ejs`/`semver` **ТОЧНИМИ** версіями, тож npm не міг задедуплікувати їх із патченими копіями, що вже стояли в ЦЬОМУ Ж дереві іншим шляхом; `overrides` лише дозволяє дедуп — не тягне нових версій. Заміряно на копії поза репо, потім у репо: `npm audit` 15 → 4, GitHub-алерти 44 → 4, і всі фікси, крім axios, у межах того самого major. ⛔ Дві очевидні альтернативи виміряно й відкинуто: апстрім не лікує (`0.98.1` = `latest`, `0.99.0-alpha` тягне той самий `decompress`, а `audit fix --force` пропонує відкат на СІМ мінорів), а `--ignore-scripts` є порожньою дією (install-хуків у дереві нуль — `hasInstallScript` теж нуль). ⛔ Два залишкові НЕ чіпаємо, і підстава сильніша за «dev-scope» — ДОСЯЖНІСТЬ: `decompress` імпортується рівно в `command-helpers/local-node.js`, а кличе його лише `graph node`, якої CI не викликає; `uuid` іде через `jayson`, досяжний лише з `deploy`/`create`/`remove`. 🔑 **І в `uuid` вісь НЕ ОДНА — друга виміряна 2026-08-30 і сильніша, бо переживає зміну досяжності: адвізорі стосується РІВНО `v3()`/`v5()`/`v6()` з переданим `buf`, а `jayson` кличе тільки `v4` і жодного разу з буфером** (три сайти: `lib/generateRequest.js` · `lib/utils.js` · `lib/client/browser/index.js`, усі `require('uuid').v4`) — сам текст GHSA-w5hq-g745-h8pq пише, що `v4()` кидає `RangeError` на невалідних межах, тобто НЕ вражений. ⛔ Отже бампу `uuid` 8→11 (ТРИ мажори через `overrides`) не робити: це чистий ризик API-несумісності заради функцій, яких наш шлях не викликає. Перевимір — три `grep -rn "require('uuid')" node_modules/jayson/lib` плюс перечитати, які саме API-методи називає адвізорі; це той рід підстави, що не тухне від релізу. 🔑 **І ТА САМА вісь виміряна для `stream-json` 2026-09-07 — тобто це вже КЛАС, не збіг:** GHSA-528h-pc64-c93x описує DoS рівно в path-фільтрах `pick`/`ignore`/`filter`/`replace` (O(depth²)), а `jayson` імпортує зі `stream-json` РІВНО ДВІ речі — `streamers/StreamValues` і `utils/Verifier` (`lib/utils.js:3-4`), тобто жодного вразливого фільтра. **Отже перше питання до транзитивного алерта не «чи є патч» і навіть не «чи досяжний пакет», а «чи адвізорі стосується того API, яке наш споживач СПРАВДІ кличе» — воно дешеве (`grep` по споживачу + читання, який саме символ називає адвізорі) і дає найдовговічнішу відповідь: незастосовність переживає апстрім-фікс, тоді як несумісність зникає разом із ним.** ⛔ І не плутай дві підстави: «фікс ламає споживача» означає, що ми НЕСЕМО ризик, поки чекаємо; «адвізорі не про наш виклик» означає, що ризику немає й чекати нема на що. ⊕ **Тест-шар мапінгу ВІДВАНТАЖЕНО 2026-08-28 [OPS.36]** — `matchstick-as` **0.6.0** (пін ТОЧНИЙ, як у сусідів: діапазон тут був би чужим рішенням про наш контракт), `subgraph/tests/`, крок `npx graph test` третім у `subgraph.yml`. `libpq` на Linux-раннері НЕ знадобився — перший CI-прогін зелений, `-d/--docker` теж. 🔑 **Ціна входу виміряна на КЛОНІ ПЕРЕД дією: +2 ЛИСТОВІ пакети (`matchstick-as` + `wabt`), 501→503, дельта алертів НУЛЬ**. ⚠️ Приписаний нозі blast-radius (дерево, яке [OPS.35] стиснув із 44 алертів до 4) її НЕ стосувався — вимір це спростував, тож не переказуй його як чинний. Форма, що лишається: **бампаючи будь-що в цій теці, міряй дельту на КЛОНІ** (`cp package.json package-lock.json` у scratchpad → `npm i --package-lock-only` → `npm audit --package-lock-only`), а не в дереві — і памʼятай, що два devDep не є одним класом лише тому, що обидва devDep. ⊕ **Знахідка, що не має стосунку до жодного алерта й тому не видима жодному сканеру [OPS.35]:** `@oclif/plugin-warn-if-update-available` — це `init`-хук, тобто біжить на КОЖНІЙ команді `graph`, робить **detached spawn**, який переживає саму команду, читає npm-креденшл через `registry-auth-token` і шле запит на реєстр. Іде він нативним `https` (`http-call`), НЕ через axios і не через undici — тобто єдиний реальний мережевий виклик збірки сидить не на тому дереві, куди дивляться алерти. 🔑 Клас ширший за пакет: **алерти дивляться на дерево ПАКЕТІВ, а виконується дерево ВИКОНАННЯ** | `npm view @graphprotocol/graph-cli dist-tags` (⚠️ `latest` буває = наша версія, а «свіжіше» = лише `alpha`/`rc` → карантин за невідомістю); `npm audit` ⊥ `gh api …/dependabot/alerts` — **дві РІЗНІ бази**, і числа розходяться в рази | `npm ci` → `npx graph codegen` → `npx graph build` → `npx graph test` (порядок перших двох несучий: `build` компілює проти `generated/`) — те саме, що робить `subgraph.yml`. ⚠️ Четвертий крок дописано 2026-08-28: доти рецепт стверджував ТОТОЖНІСТЬ із воркфлоу, будучи ВУЖЧИМ за нього — тобто локальна валідація давала зелене, слабше за CI, і саме заява про рівність робила це невидимим. ✅ `graph test`/matchstick у дереві **Є з 2026-08-28** (тест-шар `subgraph/tests/` + третій крок воркфлоу) → `00_07` OPS.36 |

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
4. Release-age quarantine (supply-chain). A version published in the last ~7 days is the prime window for a hijacked-maintainer / malicious-postinstall compromise
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
17. The same date-rule has a SECOND cause, and this one is YOUR OWN doing: a change to the BASE invalidates every open PR's green, and nothing marks them stale
18. A floor may only name what the CHANNEL can serve — and a resolver's «does not exist» is a claim about the INDEX it loaded, not about the channel
19. A «minor» can rework the very mechanism your GATE stands on — and then «suite green» is not the validation
20. Read a scary changelog line against OUR call, not against its own framing
21. The MIRROR of that row, and it is the more dangerous direction: a changelog line that does NOT read as scary can still change what LEAVES the building — and «default-on» is the tell
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
35. Dismissing an alert via `gh api`, and the 280-char wall that eats a batch
36. Conda `>=` env vs lock: the ML env is a loose `>=` floor spec, while in-silico runs on a real `conda-lock.yml`
37. CI actions: we major-pin `@vN` → latest patch auto-flows; only a *new major* needs a bump
38. Firmware/Solidity full validation is CI-gated (ARM build + QEMU; slither) — locally only the host gates run
39. Terraform provider majors are big breaking migrations — read the per-major upgrade guide, never blind-bump
40. Deprecation/future-keyword warnings: resolve them in OUR code; in vendored code they are upstream's — note, don't touch
41. `db/structure.sql` / `Gemfile.lock`: verify the diff is ONLY the intended dep (no drive-by churn) before committing
42. Canon docs mirror pinned versions — sweep them too (a bump is not done at the manifest)
43. Dependabot pins the WRAPPER, never the payload — so every payload pin in this repo is bumper-less BY CONSTRUCTION
44. And the reflex that decides the PERIMETER, migrated out of the tracker 2026-09-07 because it lived nowhere else: measure a hardening pass by WHO INSTALLS the tool — workflow ⊥ the action's own Docker IMAGE ⊥ the action's INPUT — never by which job it runs in
45. Two upstream facts worth re-checking rather than re-deriving

<!-- /DEPUPDATE-GOTCHAS-INDEX -->

## Keep this skill bounded

This is the **method + recipes**. Versions/results → git commit bodies; "what shipped" →
`git log`; the standard for SSOT docs → `ssot-maintenance`; ML parity internals →
`ml-engineering`. If you're tempted to record a specific version here, it belongs in a commit body.
