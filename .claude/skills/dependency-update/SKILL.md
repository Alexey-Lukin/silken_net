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
| **JS / importmap** | `config/importmap.rb` | `bin/importmap outdated` + `bin/importmap audit` | boot + asset-compile |
| **ML conda** | `tools/ml/environment.yml` + `pyproject.toml` | `pip list --outdated` in `silken_ml` | `pytest tools/ml/tests` (librosa≡stdlib parity) + `silken-ml-gen-logmel --check` + `make -C firmware/test logmel`; `ruff check` |
| **in-silico** | `tools/in_silico/environment.yml` + **`conda-lock.yml`** (the real pin) | `pip list --outdated` in `silken_md`; `gh` latest | rebuild + **re-run DFT vs `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`**; `ruff check` |
| **firmware C** | 6 git submodules in `firmware/extern/` | `gh api repos/<org>/<repo>/releases\|tags` vs `git submodule status` | host CMSIS-parity ctest (local) + `make -C firmware/test`; ARM build + QEMU parity (**CI-only** — arm-gcc/qemu not local) |
| **Solidity** | `contracts/{foundry.toml,package.json,package-lock.json}` + `*.sol` pragmas | `gh api` OZ/solc/forge-std latest | `forge test` (local) + `forge fmt --check`; `slither` (**CI-only**) |
| **Terraform** | `terraform/*.tf` `required_providers` (+ `.terraform.lock.hcl` if present) | `gh api repos/hashicorp/terraform-provider-<p>/releases/latest` vs the `~>` pin | `terraform validate` + `terraform fmt -check`; `terraform plan` (**CI/creds-gated** — needs GCP creds + state) |

`rvm use <v>` / `mamba run -n <env>` prefixes are MANDATORY per Bash call — shell state does
not persist between calls (a fresh shell defaults to the rvm default → `RubyVersionMismatch`).

## Hard-won gotchas

- **Post-cutoff versions are real.** This repo runs ahead of the model's knowledge cutoff
  (Ruby 4.0.x, json 2.19.x, sentry 6.6.x…). Web *search* lags; fetch the gem's own
  `CHANGES.md` / `gh api .../releases` for the exact version, and trust `bundle outdated` /
  `gh` / rubygems over memory. If a changelog truly isn't retrievable, say so + classify.
- **Transitive caps block "latest" — and that's not our drift.** A bump can be held back by a
  depending gem's constraint; document the blocker, don't force it (forcing breaks the holder):
  seen this session — `eth` caps openssl `~>3.3` + bigdecimal `~>3.1`; `rbsecp256k1` caps
  rubyzip `~>2.3`; `lookbook` caps rouge `<5.0` + htmlentities `~>4.3.4`; `rspec` caps
  diff-lcs `<2.0`; **TF** caps h5py `<3.15`. Detect with `bundle update <g>` "stayed the same"
  / `pip check`. Revert the over-bump to the capped version.
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
