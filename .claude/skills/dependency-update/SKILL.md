---
name: dependency-update
description: "Use when updating dependencies in ANY domain of this polyglot repo — Ruby gems (Gemfile/Gemfile.lock), the Ruby version itself, bundler, CI workflow actions (.github/workflows), JS/importmap, the conda ML + in-silico envs (tools/ml, tools/in_silico), the firmware C submodules (firmware/extern), or the Solidity/Foundry contracts (OpenZeppelin/solc/forge-std). Per-dependency: read THIS version's changelog → classify (security/breaking/behavior/routine) + grep our usage (direct vs transitive) → domain-appropriate validation (the recipe table) → capture the research in the commit body (founder bar: every dep researched, no separate doc). Knows the per-domain inventory/validation recipes, the transitive-cap gotchas (eth→openssl, TF→h5py, lookbook→rouge…), and that firmware/Solidity full validation is CI-gated. Examples: \"update the gems\", \"bump Ruby to latest\", \"what's outdated\", \"update the CI actions\", \"bump OpenZeppelin / solc\", \"update the firmware submodules\", \"update the ML / in-silico conda env\", \"run the dependency sweep\"."
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
1. INVENTORY  what's behind: the domain's "outdated" command (table below).
2. RESEARCH   read THIS version's changelog/release-notes (web/gh). Classify:
              security(CVE) · breaking · behavior/default · feature · routine/regen.
              Does it touch OUR code/usage? (grep the symbol — direct vs transitive.)
3. DECIDE     bump unless a transitive cap blocks it or the risk outweighs the benefit.
              In-silico/physics: bump if it gives MORE-CORRECT/better results, not just "newer".
              Release-age quarantine: skip a version <~7d old unless it's a needed security fix (gotchas).
4. VALIDATE   the domain's gate (table). Deprecation warnings → RESOLVE, don't leave
              (rename identifiers, fix call-sites) — unless they're in vendored code.
5. CAPTURE    commit (standing founder authorization: commit+push main + wiki:sync when
              the work is validated). Commit body = the per-dep research. Separate
              concerns into separate commits where sensible.
```

## Domains — inventory + validation recipes

| Domain | Manifest(s) | "What's behind" | Validate (+ linter) |
|---|---|---|---|
| **Ruby gems** | `Gemfile` / `Gemfile.lock` | `bundle outdated` | full `bin/rspec` under the project Ruby; `bin/rubocop` |
| **Ruby itself** | `.ruby-version`·`Gemfile`·`Gemfile.lock`·`Dockerfile`(ARG)·README·CLAUDE.md·copilot·.cursorrules·.rvmrc·06_01 | `rvm install`; web changelog | `rvm use <v>` then full `bin/rspec` |
| **bundler** | `Gemfile.lock` BUNDLED WITH | `gem list bundler --remote --exact` | `bundle update --bundler=<v>` |
| **CI actions** | `.github/workflows/*.yml` | per action: `gh api repos/<org>/<repo>/releases/latest` (or `/tags`) vs our `@vN` | YAML parse; the action's changelog (breaking inputs) |
| **JS / importmap** | `config/importmap.rb` **+ `vendor/javascript/` + `vendor/assets/stylesheets/`** | `bin/importmap outdated` + `bin/importmap audit` — ⚠️ бачить лише JS-піни | boot + asset-compile + `bin/rspec spec/features` (Leaflet будується в браузері) |
| **ML conda** | `tools/ml/environment.yml` + `pyproject.toml` | `pip list --outdated` in `silken_ml` | `pytest tools/ml/tests` (librosa≡stdlib parity) + `silken-ml-gen-logmel --check` + `make -C firmware/test logmel`; `ruff check` |
| **in-silico** | `tools/in_silico/environment.yml` + **`conda-lock.yml`** (the real pin) | `pip list --outdated` in `silken_md`; `gh` latest | rebuild + **re-run DFT vs `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`**; `ruff check` |
| **firmware C** | 6 git submodules in `firmware/extern/` | `gh api repos/<org>/<repo>/releases\|tags` vs `git submodule status` | host CMSIS-parity ctest (local) + `make -C firmware/test`; ARM build + QEMU parity (**CI-only** — arm-gcc/qemu not local) |
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
  (Ruby 4.0.x, json 2.19.x, sentry 6.6.x…). Web *search* lags; fetch the gem's own
  `CHANGES.md` / `gh api .../releases` for the exact version, and trust `bundle outdated` /
  `gh` / rubygems over memory. If a changelog truly isn't retrievable, say so + classify.
- **Release-age quarantine (supply-chain).** A version published in the last ~7 days is the prime
  window for a hijacked-maintainer / malicious-postinstall compromise — these get caught and yanked
  within days, so a short wait kills most of the class for free. Default: **don't auto-take a version
  younger than ~7 days; let it age** — a security fix you actually need is the exception (take it now).
  Nothing in bundler/npm enforces this out of the box (pnpm's `minimumReleaseAge` does, for pnpm
  projects) → eyeball the publish date for anything outside a trusted core dep: `npm view <pkg> time`
  (`contracts/`), rubygems.org (gems), PyPI release history (ML/in-silico). A `@vN`-pinned CI action
  also floats to fresh patches that run in CI with secrets — SHA-pin the high-blast-radius ones
  (cf. tj-actions/changed-files, 2025).
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
- **Conda `>=` env vs lock.** ML env is a `>=` spec (raise floors to tested-current — esp. a
  DSP floor like `librosa>=0.11` that protects the parity contract). in-silico has a real
  `conda-lock.yml` — that's the reproducible pin the DFT ran on; the env.yml floors are loose
  on purpose. A local conda env can drift behind the lock (re-sync with `conda-lock install`).
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
  The SSOT docs pin versions in prose: `00_05` (CI-action `@vN` like `checkout@v6` + the foundry
  config), `05_03` (solc/pragma + OpenZeppelin), `05_04` (anchor pragma), `06_01` (Terraform
  provider `~>`, Ruby, Cloud SQL Postgres), `03_01 §12.4` (submodule tags). Code + docs drift
  apart silently — this repo's solc `0.8.28 → 0.8.35` left **9 stale doc copies** until a follow-up
  swept them. After any bump: grep the canon for the OLD literal and reconcile, then `docs:check_refs`.
  The `solc_pragma_version_drift` guard (`00_06 §3`) now holds the solc line (owner = `05_03`);
  there is no such guard for CI-action / provider / PG versions yet — grep those by hand.

## Keep this skill bounded

This is the **method + recipes**. Versions/results → git commit bodies; "what shipped" →
`git log`; the standard for SSOT docs → `ssot-maintenance`; ML parity internals →
`ml-engineering`. If you're tempted to record a specific version here, it belongs in a commit body.
