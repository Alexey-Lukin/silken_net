---
name: dependency-update
description: "Use when updating dependencies in ANY domain of this polyglot repo — Ruby gems (Gemfile/Gemfile.lock), the Ruby version itself, bundler, CI workflow actions (.github/workflows), JS/importmap, the conda ML + in-silico envs (tools/ml, tools/in_silico), the firmware C submodules (firmware/extern), the Terraform providers (terraform/*.tf required_providers), or the Solidity/Foundry contracts (OpenZeppelin/solc/forge-std). Per-dependency: read THIS version's changelog → classify (security/breaking/behavior/routine) + grep our usage (direct vs transitive) → domain-appropriate validation (the recipe table) → capture the research in the commit body (founder bar: every dep researched, no separate doc). Knows the per-domain inventory/validation recipes, the transitive-cap gotchas (eth→openssl, TF→h5py, lookbook→rouge…), and that firmware/Solidity full validation is CI-gated. Examples: \"update the gems\", \"bump Ruby to latest\", \"what's outdated\", \"update the CI actions\", \"bump OpenZeppelin / solc\", \"update the firmware submodules\", \"update the ML / in-silico conda env\", \"bump the terraform / google provider\", \"run the dependency sweep\"."
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
| **JS / importmap** | `config/importmap.rb` **+ `vendor/javascript/` + `vendor/assets/stylesheets/`** | `bin/importmap outdated` + `bin/importmap audit` — ⚠️ бачить лише JS-піни | boot + asset-compile + `bin/rspec spec/features` (Leaflet будується в браузері) |
| **ML conda** | `tools/ml/environment.yml` + `pyproject.toml` | `pip list --outdated` in `silken_ml` | `pytest tools/ml/tests` (librosa≡stdlib parity) + `silken-ml-gen-logmel --check` + `make -C firmware/test logmel`; `ruff check` |
| **in-silico** | `tools/in_silico/environment.yml` + **`conda-lock.yml`** (the real pin) | `pip list --outdated` in `silken_md`; `gh` latest | rebuild + **re-run DFT vs `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`**; `ruff check` |
| **firmware C** | every git submodule under `firmware/extern/` — ⛔ take the count from `git submodule status`, never from prose: a hardcoded number here silently trims the newest entries off the sweep perimeter, and the newest are `subghz-phy` (radio, board-freeze gated) plus our OWN LoRaWAN fork, whose UB fix must be re-verified on every bump | `gh api repos/<org>/<repo>/releases\|tags` vs `git submodule status` | host CMSIS-parity ctest (local) + `make -C firmware/test`; ARM build + QEMU parity (**CI-only** — arm-gcc/qemu not local) |
| **Solidity** | `contracts/{foundry.toml,package.json,package-lock.json}` + `*.sol` pragmas | `gh api` OZ/solc/forge-std latest | `forge test` (local) + `forge fmt --check`; `slither` (**CI-only**) |
| **Terraform** | `terraform/*.tf` `required_providers` (+ `.terraform.lock.hcl` if present) | `gh api repos/hashicorp/terraform-provider-<p>/releases/latest` vs the `~>` pin | `terraform validate` + `terraform fmt -check`; `terraform plan` (**CI/creds-gated** — needs GCP creds + state) |

`rvm use ruby-<v>@silken_net` / `mamba run -n <env>` prefixes are MANDATORY per Bash call — shell
state does not persist between calls. Name the **full gemset** (repo pins `.ruby-gemset=silken_net`):
`rvm use ruby-<v>` *without* `@silken_net` selects the empty default gemset → `Bundler::GemNotFound`
for every gem (not `RubyVersionMismatch`); a bare `rvm use <v>` prints "Unknown ruby interpreter"
and returns non-zero, so it breaks an `&&` chain (the real command never runs). Bites
`run_in_background:` Bash hardest (the login profile's gemset auto-select isn't reliable there) —
`bundle check` before a long suite run.

## Hard-won gotchas

- 🔴 **A vendored front-end package has its version in TWO places, and the tool sees only one** [TEST.7, 2026-08-03]. `leaflet` is pinned locally: JS in `vendor/javascript/leaflet.js` (visible to `bin/importmap outdated`) **plus** CSS and 5 PNGs in `vendor/assets/stylesheets/leaflet/` — ordinary files no inventory command knows about. So a bump must be **paired**, or the halves drift silently: a mismatched CSS raises nothing, it just breaks the map's layout. Three traps around it. (a) Re-pin with the **default jspm provider** — `--from unpkg` serves UMD with no ESM exports, so `import L from "leaflet"` dies. (b) The CSS ships **relative** `url(images/*.png)`, and Propshaft rewrites those to digested paths only while the images sit next to it — keep the `images/` subdir. (c) After ANY new pin, run `RAILS_ENV=test bin/rails assets:precompile` locally: a stale `public/assets/.manifest.json` keeps Propshaft on the **Static** resolver, and then every browser example fails **at login** (asset missing → the layout stub blanks the tags → page without JS). That symptom reads as broken authentication and costs an hour.
- **Post-cutoff versions are real.** This repo runs ahead of the model's knowledge cutoff
  (a gem two majors behind what `bundle outdated` reports is the normal case — ⛔ do not pin an example version here, it is the very drift this paragraph warns about). Web *search* lags; fetch the gem's own
  `CHANGES.md` / `gh api .../releases` for the exact version, and trust `bundle outdated` /
  `gh` / rubygems over memory. If a changelog truly isn't retrievable, say so + classify.
- 🔴 **`--upgrade-package` names a target; it does NOT bound the resolution** (2026-08-06). `uv pip
  compile … --upgrade-package gitpython==3.1.57 --output-file <FRESH path>` bumped **twelve** packages,
  including `cryptography 50.0.0` at age 6 days — i.e. straight past the quarantine, under a command
  whose flag said "one package". The existing lock **is** the preference set: writing to a new path
  discards it and re-resolves everything to latest. **Always point `--output-file` at the committed
  lock** (or copy it there first), and verify by counting: `git diff <lock> | grep -E '^[+-][a-z0-9_.-]+=='`
  must yield exactly as many version lines as packages you named. Same family as "age the DIFF, not the
  PR title" — except here the stowaways come from your own command, not from Dependabot's.
- **Release-age quarantine (supply-chain).** A version published in the last ~7 days is the prime
  window for a hijacked-maintainer / malicious-postinstall compromise — these get caught and yanked
  within days, so a short wait kills most of the class for free. Default: **don't auto-take a version
  younger than ~7 days; let it age** — a security fix you actually need is the exception (take it now).
  🔴 **But the clock is a PROXY: what the quarantine actually measures is how UNEXAMINED the release is**
  (2026-08-06, founder push). `cryptography 50.0.0` was taken deliberately at **age 6 days**, and that is
  neither the exception nor a bend. The threat class (hijacked maintainer / malicious postinstall) is
  ≈nil for pyca/cryptography: PyPI trusted publishing, wheels with no postinstall scripts (Rust/C
  extension), one of the most-watched packages in the ecosystem — so 6 days there buys what 7 buys for a
  random package. **The reasoning error to avoid is ASYMMETRY:** I had measured the CVE-exploitability
  side carefully (≈0 — we never decrypt PKCS#7) and taken the release-risk side *on faith*, then let two
  ≈0 quantities decide it — while never weighing the one non-zero cost, a second pass (re-installing the
  toolchain, re-reading context, re-validating, a separate commit + CI run). And an open High alert has
  the same cost you already accept for CodeQL noise: it buries the next real one. So: weigh **both**
  sides with the same rigour, and let the package's publishing profile — not the calendar — set the bar.
  Nothing in bundler/npm enforces this out of the box (pnpm's `minimumReleaseAge` does, for pnpm
  projects) → eyeball the publish date for anything outside a trusted core dep: `npm view <pkg> time`
  (`contracts/`), rubygems.org (gems), PyPI release history (ML/in-silico). A `@vN`-pinned CI action
  also floats to fresh patches that run in CI with secrets — SHA-pin the high-blast-radius ones
  (cf. tj-actions/changed-files, 2025).
- 🔴 **The age rule cuts BOTH ways — a fresh PR can carry a long-ripe artifact** (2026-08-06). `#499`
  (`library/ruby` digest) opened that morning, i.e. "an hour old" by its title — but the digest itself
  had been pushed **23 days** earlier. Dating the artifact instead of the PR is what surfaced that we
  were three weeks behind on Ruby, and turned a one-line digest bump into a full 4.0.5→4.0.6 recipe.
  So the reflex is not only "don't take the young" but **"find out what's actually IN there"** —
  a PR's age tells you nothing in either direction. For docker tags read `tag_last_pushed` from the
  Hub API, and verify the digest **independently** via the registry manifest (`docker-content-digest`),
  not from the Hub JSON you just read. Sibling check worth one command: compare the tag's digest against
  its `-<suite>` variants (`4.0.6-slim` vs `4.0.6-slim-trixie`) — identical digests prove the base OS did
  NOT shift under you, which is what would silently move `libvips`/glibc floors. 🔴 **And the same
  measurement finds drift BEFORE Dependabot files anything** (2026-08-16): `ruby:4.0.6-slim` had been
  re-pushed 08-07 under an unchanged tag (`b6505477…` → `607bf92f…`, i.e. fresh Debian trixie patches at
  an identical Ruby version), and no docker PR existed in the open set although `docker` is one of the
  five automated ecosystems. The bot is a convenience, not the instrument — **make "read `tag_last_pushed`
  for the pinned base image" a standing step of the sweep**, because a digest bump is pure security patch
  and is invisible in every version-based inventory (`bundle outdated`, `gh api releases`) by construction.
- 🔴 **A version perimeter is WIDER than its gate, and half the hits must NOT be edited** (Ruby bump,
  2026-08-06). `git grep 4.0.5` returned **15 files** while `ruby_version_sync.rb` guards **8** mirrors.
  The rest were *historical narrative* — the PR #463 post-mortem quoted inside `ci.yml`/`docs.yml`/the
  guard's own header ("образ 4.0.6 vs Gemfile 4.0.5"), plus two measurement records in the SPDX spec
  ("measured on Ruby 4.0.5 with a negative control"). A blind `sed` would have corrupted the incident
  write-up **and lied about the conditions a measurement was taken under.** Read every hit and ask
  "is this a PIN or a STORY?" — only pins move.
- 🔴 **An owner-only drift guard watches PROSE; tool config satellites are outside it forever** (solc
  0.8.36, 2026-08-06). The tracker item warned that the 0.8.35 bump had left 9 stale `0.8.28` copies —
  and a stale copy showed up again, in `contracts/aderyn.toml` ("reads foundry.toml for solc 0.8.35").
  `solc_pragma_version_drift` only scans `docs/**`, so any `*.toml`/`*.json` that restates a version in
  a comment is invisible to it **by construction, not by oversight**. Grepping the tool configs is a
  manual step of the recipe, right next to the canon sweep.
- 🔴 **After ANY generator writes, run the WHOLE lane — it touches files your diff never named**
  (2026-08-06, reddened `main` twice). `rake docs:repin` writes via `YAML.dump`, which serialises DATA
  only — every comment is dropped, and the SPDX header of `lib/canonical_block_pins.yml` **is** a
  comment. `spdx_headers.rb --check` is a separate HARD gate in the `CI · Docs` lane, alongside
  `model_doc_sync`, linter-specs and protocols-ref. Running `check_refs`+`tracker`, getting two honest
  exit-0s and concluding "docs are green" is a perimeter substitution: the measurement was true, it just
  covered a smaller set than I decided it did. (Fixed at the tool — repin now re-inserts the header.)
- 🔴 **Measure a dependency's risk from the FILE DIFF against YOUR call path, not from the changelog**
  (CMSIS-DSP 1.17.1, 2026-08-06). The release advertises "corrected MVE float-to-Q15/Q31 conversions" —
  i.e. *numbers changing* — and the tracker rightly flagged it as a log-mel parity threat. But a
  changelog describes the whole project: `git diff v1.17.0 v1.17.1 -- Source/ Include/` showed 16 files,
  and **neither `arm_rfft_fast_f32.c` nor `arm_cfft_f32.c`** (our only call) was among them; the MVE
  paths are unreachable on Cortex-M4; and the one shared file changed a single table by adding `f`
  suffixes to literals already narrowed to `float32_t` — a table we never touch (log-mel calls libm
  `logf()`). A submodule hands you an exact diff — use it *before* deciding to be afraid.
- **Age the DIFF, not the PR title** (2026-07-16). A Dependabot PR is named for its *target* dep,
  but bundler re-resolves the target's own dependencies to latest in the same lock-diff — so a
  "ripe" PR smuggles fresh transitives past the gate. Seen: `pagy 43.5.6→43.6.0` (age 7d ✅) carried
  `json 2.20.0→2.21.1` (age **3d**) as a passenger. Read `gh pr diff <n>` and age **every changed
  line**, then weigh against the target's actual value (that pagy release only touched
  searchkick/elasticsearch paginators — `grep` said 0 uses → no-op, so zero cost to let it ripen).
- **`@dependabot rebase` changes the TARGET, not just the base** (2026-07-29) — so the quarantine
  clock **restarts**, and a PR that was ripe by its title is not. Seen the same session: `#477`
  simplecov 1.0.2 (11d ✅) came back as **1.0.3 (3d ❌)**; `#472` carried rbs 4.0.3 (41d ✅) and came
  back with **rbs 4.1.0 (0d ❌)**. This collides head-on with the row below: rebase is what ADDS a
  newly-required check, yet rebase is also what pulls fresh passengers in. **Always re-read and
  re-date `gh pr diff <n>` AFTER the rebase** — the title, and your earlier dating, are both stale.
- **A required check added AFTER the PR opened is ABSENT, not red** (2026-07-29) — `gh pr checks`
  shows all-pass and the aggregate count silently comes up short (7/8 vs 8/8). GitHub reports the
  PR `BLOCKED` with nothing visibly failing. Seen: `DCO passed` became required 07-25; six PRs based
  on 07-23 simply had no such check. Diagnose by counting the required aggregates against
  `gh api repos/<o>/<r>/branches/main/protection --jq '.required_status_checks.contexts[]'`, not by
  eyeballing for red. Fix = `@dependabot rebase` (then re-date the diff, per the row above).
- **A SHA-pinned action does NOT pin its own contents** (2026-07-29 → `00_07` OPS.21). The pin
  freezes the wrapper; a Docker-based action still installs its tool from PyPI/npm **fresh every
  run**. `crytic/slither-action@b52cc1cb` (v0.4.2) broke the required `Solidity passed` gate when
  `slither-analyzer 0.11.6` + `crytic-compile 0.4.2` shipped (both **1 day old**): 0.11.6 raised the
  floor to `crytic-compile>=0.4.2`, whose "disable Foundry dynamic test linking" calls `forge` even
  under `ignore-compile: true` — and `forge` lives on the runner, not inside the action's container
  (`FileNotFoundError: 'forge'`). Fix = pin the tool (`slither-version: 0.11.5`, which transitively
  caps `crytic-compile<0.4.0`). **The release-age quarantine has a structural blind spot here:** it
  guards `Gemfile`/`package.json`/conda, but never sees an action's image contents — a day-old
  package walked straight into the money-path gate. Prefer the shape already used elsewhere in this
  repo: `pip install --require-hashes -r requirements-*.txt` (halmos, medusa) or curl+sha256 (aderyn).
- 🔴 **Identical failure on N INDEPENDENT PRs ⇒ the root is in the BASE, not in the PRs** (2026-07-30).
  Four Dependabot PRs (aws-sdk-s3, httpx, csv, simplecov) all red on `scan_ruby`; I opened their
  diffs first and that cost the most time of the sweep. The cause was one: `main` carried
  **CVE-2026-66066** (activestorage), so `bundler-audit` failed for everyone. **One unfixed advisory
  blocks the WHOLE Ruby perimeter** — and each PR's red is then somebody else's. Reflex: with ≥2
  identical failures, ask what they SHARE before reading any diff; fix `main` first, then rebase.
  Corollary on the quarantine: it has exactly **one** exception — a security fix you actually need.
  `rails 8.1.3.1` was taken at age 1 day, deliberately, and that is the rule working, not bending.
- 🔴 **The same date-rule has a SECOND cause, and this one is YOUR OWN doing: a change to the BASE invalidates every open PR's green, and nothing marks them stale** (2026-08-22, OPS.27+OPS.22). Raising the CI Postgres major on `main` meant four Dependabot PRs opened two days earlier still displayed green from a run on the *previous* `ci.yml` — the checks were honestly earned against a CI that no longer exists. Note how this differs from the advisory-DB row below: there the world moved, here **you** moved it, so the reflex fires at a moment you control and can plan for. Two ways through, and the choice is about who validates: `@dependabot rebase` (the checks re-run on the new base — worth it when you *want* CI's verdict, e.g. to prove the base change is safe on the PR path too), or take the bump **locally** with `bundle update --conservative` and validate yourself (better when the risky part is something CI cannot see for you — here simplecov 1.1.0 rewrites the very coverage machinery our group-floor gate stands on, so the honest proof was `line 99.49 / branch 98.05` plus a fresh `.last_run.json`, i.e. evidence the gate RAN, not that the suite was green). ⚠️ After a base change, `gh pr checks` on an un-rebased PR is a statement about a workflow file you have already replaced.
- 🔴 **A PR's green check has a DATE, and the advisory DB moves independently of it — so an old green
  attests to a world where the CVE did not yet exist** (2026-08-10, same root as the row above). `#501`
  displayed `scan_ruby` SUCCESS dated 08-06; the `json` advisory (CVE-2026-71847) only landed in
  `ruby-advisory-db` on 08-08. The tick was honestly earned — *before the question was asked* — so
  merging on it means trusting a measurement that predates its own subject. Note this is the mirror of
  the identical-failure rule: there the reds were somebody else's, here the **greens** are. Two
  consequences: (a) on any PR older than a day, `gh pr checks` tells you about the base at run time,
  never about today; (b) the honest re-measure is your own full local run over the applied bump
  (`bundle update <gems> --conservative` → full `bin/rspec` + `bin/rubocop` + `bin/bundler-audit`),
  or a rebase that forces CI to run again — never re-reading the tick. ⚠️ And the same asymmetry that
  makes rebase expensive applies: re-running CI restarts the quarantine clock, while the local run
  does not, so prefer the local run when the diff is small enough to apply by hand.
- 🔴 **The RED check has a date too — and a green neighbour does not disprove it** (2026-08-16). The row
  above says a stale green attests to a world before the CVE; the mirror is that a stale **red** attests
  to a base that has since been fixed, and it is harder to spot because red reads as "this PR is broken".
  Five PRs sat red on `scan_ruby` from 08-10 while `main` already carried the fix. What made the diagnosis
  hard was that the "identical failure ⇒ root in the base" rule looked *refuted*: `#509` sentry-rails was
  **green in the same minute** as `#507` sentry-ruby was red — same bump 6.6.2→6.7.0, same upstream. The
  answer was in the lock diff's COMPOSITION: `#507` touched only sentry, so it left `json 2.21.1`
  (CVE-2026-71847) in place and reddened *honestly*; `#509` happened to drag `json 2.21.2`+erb+rbs+reline+
  zeitwerk along as passengers, and the advisory vanished with them. **So "age the DIFF, not the PR title"
  has a third face: a passenger is sometimes not a risk but an ACCIDENTAL CURE — and then the check's
  colour reports the diff's composition, not the bump's quality.** Diagnose by opening the failing job's
  LOG; a cause inferred from a neighbouring commit is a guess wearing a verdict's clothes (here I blamed
  `brakeman --ensure-latest`, which had genuinely reddened `main` three days earlier, and was wrong).
- 🔴 **`built_at` on rubygems is DEAD as an age signal — it returns `1980-01-02`** (2026-08-16). Reproducible
  builds normalise the gemspec timestamp, so all ten gems measured that day reported the same 1980 date.
  A quarantine computed from it measures a file-format artefact, not a release. Use `created_at` from
  `https://rubygems.org/api/v1/versions/<gem>.json` (the push time), and treat any age field that looks
  identical across unrelated packages as an instrument failure, not as a finding.
- 🔴 **A security patch can EXPOSE a latent debt rather than break you — read the failure that way first**
  (2026-07-30). `rails 8.1.3.1` "broke" boot; in truth we had `variant_processor = :vips`, libvips in
  the Dockerfile and `.variant()` in three live places — and **no `ruby-vips` gem**, so variant
  generation in prod had been dead *silently*. Upstream made it loud on purpose. Note the shape that
  hid it: `image_processing` **repackages** any LoadError into `"ImageProcessing::Vips requires the
  ruby-vips gem"`, and `engine.rb` matches `case error.message` on `/libvips/` and `/image_processing/`
  — neither matches (capitalised) → `else raise`, i.e. boot-crash instead of the intended warn.
  Reflex: when a bump fails, ask "what does this prove was already broken?" before reverting.
- 🔴 **Adding a NATIVE gem can make require ORDER load-bearing** (2026-07-30 → `config/application.rb`).
  glib (via `ruby-vips`) loaded BEFORE `argon2id` ⇒ `__stack_chk_fail` in `initial_hash`, **SIGABRT
  (134)**, macOS-only, CI green. Reverse order is clean — a 3-line repro without Rails settles it.
  Why Rails hit the bad branch although `argon2id` is Gemfile line 8: **`require "rails/all"` (line 4
  of `application.rb`) runs BEFORE `Bundler.require` (line 8)**, and `activestorage/engine.rb`
  mentions `ImageAnalyzer::Vips` in the class body → autoload beats Gemfile order. Diagnose order via
  `$LOADED_FEATURES` **indices** — a `Kernel#require` prepend is blind to `Bundler.require` (it calls
  the `Kernel.require` singleton). And measure a native crash from the crash report, not from an
  upstream comment: `.ips` is **JSON**, `usedImages[imageIndex]` names the exact library (here
  `argon2id.bundle` — my libxml2/nokogiri theory, borrowed from the Rails patch's own comment, was
  wrong). Take the crash report BEFORE the theory.
- **SHA==tag verification has a wrong endpoint that reads as a mismatch** (2026-07-30):
  `git/ref/tags/<tag>` returns the SHA of the **tag OBJECT** for an annotated tag. Use
  `gh api repos/<o>/<r>/commits/<tag> --jq .sha` (or deref `git/tags/<sha>`).
- 🔴 **The version COMMENT beside a SHA pin is a convention, and Dependabot preserves whichever form it
  finds — so "unifying" it is a silent convention change riding a `build(deps)` subject** (2026-08-16).
  Both forms live here on purpose-by-accident: major (`# v4`, 56×`# v7`, 15×`# v1`) and exact
  (`# v2.20.0`, `# v0.36.0`) — and the bot wrote both, proven by `e2cd58c7`, which bumped
  codeql-action's SHA and left its `# v4` untouched. A major comment does **not lie** when the SHA
  resolves to v4.37.6; it names the same action at coarser granularity, so there is nothing to fix.
  **Rule: update the comment only where its form is already exact; leave a major one as-is.** Otherwise
  a routine bump rewrites the style of 11 lines nobody asked about. Canon states the convention as
  `# vN` (`06_07`, OPS.10 paragraph), and no gate compares the comment against its pin — the same
  blind spot as the `@vN`-in-prose sweep at the bottom of this file.
- **A gate that did not RUN is not green** (2026-07-29). `Solidity passed` showed green on most PRs
  only because `dorny/paths-filter` skipped the job. The breakage above surfaced solely on the two
  PRs that touched `solidity_audit.yml` — they did not break Slither, they **made it run**. Before
  trusting an aggregate, ask whether its jobs actually executed on this diff (same family as the
  OPS.13 "ask what builds the artifact, and on which trigger" row below).
- **A green Dependabot PR can still break `main`** (2026-07-16 → OPS.13, now hard-gated). Ask what
  actually *builds* the changed artifact and on which trigger. The historical hole: the only docker
  build (`mirror-ghcr.yml`) runs on `workflow_run[branches: main]` — not `pull_request` — so a
  `library/ruby` bump touched only the Dockerfile while `Gemfile` held a hard `ruby "X.Y.Z"` pin ⇒
  `bundle install` died *after* merge (PR #463). Since 2026-07-16 two gates hold the line:
  `scripts/ruby_version_sync.rb` (version parity across ALL mirrors — the script's `MIRRORS` is the
  authoritative list; `docs.yml`) + `docker_smoke` in `ci.yml` (full image build on the PR, in the
  required `ci-ok`). **A Ruby bump is still the full every-mirror recipe (row 2 of the table) +
  `rvm install` + full suite — never a merge button; the gates make the shortcut red, not safe.**
- **Transitive caps block "latest" — and that's not our drift.** A bump can be held back by a
  depending gem's constraint; document the blocker, don't force it (forcing breaks the holder):
  seen this session — `eth` caps openssl `~>3.3` + bigdecimal `~>3.1`; `rbsecp256k1` caps
  rubyzip `~>2.3`; `lookbook` caps rouge `<5.0` + htmlentities `~>4.3.4`; `rspec` caps
  diff-lcs `<2.0`; **TF** caps h5py `<3.15`; `conda-lock` caps dulwich `<0.25` while the
  PYSEC-2026-2462..66 fix lives only in 1.2.5 (documented blocker in requirements-conda-lock.in;
  Scorecard alert → owner dismiss-with-reason — re-check on every conda-lock bump). Detect with
  `bundle update <g>` "stayed the same" / `pip check`. Revert the over-bump to the capped version.
- **Dismissing an alert via `gh api`, and the 280-char wall that eats a batch.** List:
  `gh api repos/<owner>/<repo>/code-scanning/alerts?state=open`. Dismiss: `-X PATCH -f
  state=dismissed -f dismissed_reason="won't fix" -f dismissed_comment="…"`; reopen with
  `-f state=open` when the decision flips from *accept* to *FIX*. Fixed findings auto-close on
  the tool's next scan — you dismiss only what you are deliberately **not** fixing.
  🔴 **GitHub caps `dismissed_comment` at 280 characters and answers 422 — it does not truncate
  silently.** So the failure is loud but *late*: in a batch it kills the alerts after the long
  one, leaving the sweep half-applied and looking finished. Write the reason as a tweet with an
  ID to follow (`SEC.30 / canon 04_03 §2.2б`), never as an essay, and length-check **before**
  sending. Instances → memory `project_dependabot_sweep_2026_07`.
- **Conda `>=` env vs lock.** ML env is a `>=` spec (raise floors to tested-current — esp. the
  DSP floor that protects the parity contract; read the current literal in
  `tools/ml/environment.yml`, never from here). 🔴 **And a `>=` floor plus a CACHED,
  path-gated CI job is not the guard it reads as:** the env only re-resolves when the cache
  is cold, so the first run on a new major lands on an unrelated PR, unattended. Before
  moving that floor, verify the new major BY HAND against the contract it guards — the
  bit-level comparison, not just a green suite. in-silico has a real
  `conda-lock.yml` — that's the reproducible pin the DFT ran on; the env.yml floors are loose
  on purpose. A local conda env can drift behind the lock (re-sync with `conda-lock install`).
  📌 **The GENERATOR is pinned too — `uv==0.12.3`, in the `requirements-conda-lock.in` header**
  (2026-08-16). CI only *consumes* that lock (`pip install --require-hashes`), so the only thing
  touching `uv` is a human at regeneration time, and an unpinned one rewrites row order, comments
  and marker shape across the whole 84 KB file — turning a one-line bump into an unreadable diff.
  `uv` is not on the machine by default: install it into a throwaway venv at the pinned version,
  never globally. **Verify the recipe, not just the diff: a second compile must produce a
  BYTE-IDENTICAL file** — that single check proves both the pin and that your `.in` edits (comments
  included) did not perturb resolution.
- **CI actions:** we major-pin `@vN` → latest patch auto-flows; only a *new major* needs a bump.
  Most stay current; check each with `gh api`. SHA-pinned actions update differently (Dependabot).
- **Firmware/Solidity full validation is CI-gated** (ARM build + QEMU; slither). The host gates
  (forge test, host CMSIS-parity ctest, `make -C firmware/test`) run locally; push → CI does the
  rest; `gh run watch <id> --exit-status` confirms. mruby/CMSIS-FFT bumps risk the ARM↔x86
  bit-parity / log-mel parity — keep `evm_version`/float flags pinned, lean on the parity gates.
- **Terraform provider majors are big breaking migrations** (e.g. `google` 5→7 = renamed/removed
  args across Cloud SQL/GCE/VPC/IAM). Read the per-major upgrade guide; bump the `~>` constraint +
  `terraform init -upgrade` + `terraform plan` against real state (CI/creds-gated) — never a blind
  sweep bump. (`.terraform.lock.hcl` pins the resolved provider hashes if committed.)
- **Deprecation/future-keyword warnings:** resolve in OUR code (e.g. solc `error`/`at` → rename);
  if they're in vendored code (OZ `EnumerableSet.at()`), they're upstream's — note, don't touch.
- **`db/structure.sql` / `Gemfile.lock`:** verify the diff is ONLY the intended dep (no drive-by
  churn) before committing.
- **Canon docs mirror pinned versions — sweep them too (a bump is not done at the manifest).**
  The SSOT docs pin versions in prose: `06_07 §1a` (⚠️ it holds the SHA-pinning POLICY, not the version literals — do not sweep it looking for `@vN`; the live pin is the `# vN` comment beside each SHA in `.github/workflows/**` + the foundry
  config), `05_03` (solc/pragma + OpenZeppelin), `05_04` (anchor pragma), `06_01` (Terraform
  provider `~>`, Ruby, Cloud SQL Postgres), `03_01 §12.4` (submodule tags). Code + docs drift
  apart silently — this repo's solc `0.8.28 → 0.8.35` left **9 stale doc copies** until a follow-up
  swept them. After any bump: grep the canon for the OLD literal and reconcile, then `docs:check_refs`.
  The `solc_pragma_version_drift` guard (`00_06 §3`) now holds the solc line (owner = `05_03`);
  there is no such guard for CI-action / provider / PG versions yet — grep those by hand.

- 🔴 **Dependabot pins the WRAPPER, never the payload — and this repo now carries two pins with NO bumper at all** [OPS.21, 2026-08-23]. Its `github-actions` ecosystem reads `uses:` and nothing else: an action's own `version:` INPUT is invisible to it, so `foundry-toolchain` with `version: v1.7.1` (four money-path jobs) will never get a PR. Its `docker` ecosystem is scoped to the directory you declare — ours is `/`, i.e. the `Dockerfile` — so service-container `image:` lines inside `.github/workflows/**` are invisible too, and the `postgis`/`valkey` digests sit frozen. **Both are therefore a MANUAL step of this recipe, not an automated one**, and both say so in a comment next to the pin — a pin whose staleness nobody can see is worse than the floating tag it replaced. ⚠️ Same shape as the SHA-pin lesson one level up: `crytic/slither-action` was SHA-pinned while its image installed `slither-analyzer` fresh on every run, and an upstream release blocked money-path merges for three days. **Measure a perimeter by WHO INSTALLS the tool (workflow ⊥ action image ⊥ action input), never by which job it runs in.**
- ⚠️ **Two upstream facts worth re-checking rather than re-deriving** (verified 2026-08-23, cheap to re-verify — two HTTP calls each): the `slither-analyzer` pin is still needed (upstream has shipped no fix for the `ignore-compile` Foundry path, and `crytic-compile` is unchanged since the incident); and `leaflet` has nowhere to move — its latest IS the pinned version, with only an alpha beyond. A dated negative is worth as much as a finding here: it removes suspicion until the next release of either.

## Keep this skill bounded

This is the **method + recipes**. Versions/results → git commit bodies; "what shipped" →
`git log`; the standard for SSOT docs → `ssot-maintenance`; ML parity internals →
`ml-engineering`. If you're tempted to record a specific version here, it belongs in a commit body.
