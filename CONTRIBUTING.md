# Contributing to Silken Net

Thanks for your interest in **Silken Net** — a trustless D-MRV platform for
planetary-scale forest-health monitoring. Contributions of every kind are
welcome: bug reports, fixes, documentation, firmware, smart contracts, and
in-silico research.

This is a polyglot monorepo — Rails/Ruby · STM32 firmware-C · mruby · Solidity
(Foundry) · Python (in-silico/ML) · .NET (PicoGK CAD). Most contributions touch
one domain at a time; you do **not** need the whole stack set up to help.

## Getting the code

See the **Quick Start** in the [README](README.md) — in short: `git clone`,
`bundle install`, `bin/rails db:prepare`, `bin/dev`. Firmware, contracts, and the
Python/CAD tooling have their own setup steps in the README and `docs/`.

## Reporting bugs & requesting features

- **Bugs / enhancements:** open a
  [GitHub issue](https://github.com/Alexey-Lukin/silken_net/issues). Tell us what
  you expected, what happened, and how to reproduce it.
- **Security vulnerabilities:** do **not** open a public issue — follow
  [`SECURITY.md`](SECURITY.md) (report privately via a GitHub Security Advisory).

## Contribution process

We use the standard GitHub **fork → branch → pull request** flow:

1. Fork the repository and create a topic branch off `main`.
2. Make your change in focused, logically-separate commits.
3. Run the checks for the domain you touched (see below) and make sure they pass.
4. Open a pull request against `main`, filling in the
   [pull-request template](.github/pull_request_template.md) and linking any
   related issue.
5. CI must be green; maintainers (see [`CODEOWNERS`](.github/CODEOWNERS)) review
   pull requests before they are merged.

## Requirements for acceptable contributions

Contributions are expected to pass the same checks CI enforces. Run the ones for
the domain you changed before opening a PR:

- **Ruby (Rails):** `bin/rubocop -a` · `bundle exec rspec` · `bundle exec brakeman` · `bundle exec bundler-audit check`
- **Python (in-silico / ML):** `pytest tools/ml/tests` · `pytest tools/in_silico/tests` (tests) · `ruff check` (lint, config: `ruff.toml`)
- **Firmware (STM32):** `make -C firmware/test` (host x86 — no ARM toolchain needed)
- **Solidity (Foundry):** `cd contracts && npm ci && forge build --sizes && forge test -vvv`

**Coding standards (style guides).** Each primary language follows a specific,
FLOSS-enforced style guide: Ruby uses the **Rails Omakase** RuboCop style
([`.rubocop.yml`](.rubocop.yml) inherits `rubocop-rails-omakase`); Python uses
**Ruff** ([`ruff.toml`](ruff.toml) — pycodestyle/pyflakes/isort/pyupgrade/bugbear/…);
firmware C compiles with **`-Wall -Wextra -Wpedantic`** plus **cppcheck**
(MISRA C:2012 advisory); Solidity is formatted with **`forge fmt`**; C# follows
[`.editorconfig`](tools/cad/.editorconfig) (.NET conventions). All are enforced
automatically in CI (RuboCop, Ruff, cppcheck, forge), so contributions must comply;
the rare style exception must be documented in the code at its location (e.g.
`// cppcheck-suppress`).

In addition:

- **Tests are mandatory for new functionality (project policy).** When you add or
  change functionality you MUST add or update automated tests; as major new
  functionality is added, tests for it MUST be added to the relevant automated
  suite (RSpec / Foundry `forge` / firmware host tests). A pull request that adds
  major new functionality without accompanying tests will not be merged.
- Match the style of the code around you (naming, comments, idiom). Keep comments
  minimal and free of drift-prone numbers.
- The `docs/NN_NN_*.md` files are the single source of truth. If you change
  behaviour, update the relevant canon doc — see
  [`docs/00_06`](docs/00_06_SSOT_Documentation_Standard.md). Open or in-progress
  work is tracked in [`docs/00_07`](docs/00_07_Action_Plan_Tracker.md).
- Write a clear commit message; AI-assisted commits carry attribution trailers
  (see [AI-assisted contributions](#ai-assisted-contributions) below).

## Developer Certificate of Origin (DCO)

To certify that you are legally entitled to submit your contribution, this project
uses the [Developer Certificate of Origin 1.1](https://developercertificate.org/). By
signing off a commit you assert that you wrote the patch (or otherwise have the right
to submit it) and that it may be distributed under the project's licenses. Sign off
with the `-s` flag, which adds a `Signed-off-by: Your Name <you@example.com>` trailer:

```bash
git commit -s -m "your message"
```

### AI-assisted contributions

AI assistance is **allowed, with attribution** — the position the Linux kernel
takes, rather than a blanket ban.

- Add an `Assisted-by: AGENT:MODEL` trailer (for example
  `Assisted-by: Claude Code:claude-opus-5`) next to the usual `Co-Authored-By`.
- **The sign-off is the contributor's own act.** `Signed-off-by` certifies
  provenance and licence compatibility. That is a legal statement only a person
  can make, so it belongs to the human who directs and owns the change — never
  to the agent.
- **What the check can and cannot see.** Our DCO check rejects any sign-off
  whose address is not the commit's own author or committer, so no agent can
  sign in a name other than the contributor's. It cannot see *who typed the
  command*: a git object records tree, parents, author, committer and message,
  and nothing in it distinguishes a person from tooling running under their
  identity. That half rests on you, not on CI — which is what a certification
  means.

Why this project permits AI assistance instead of prohibiting it — and what that
means for copyright in our jurisdiction — is recorded under `UNI.20` in
[`docs/00_07`](docs/00_07_Action_Plan_Tracker.md).

## License of contributions

By contributing, you agree that your contributions are licensed under the
project's licenses: **AGPL-3.0-or-later** (code), **MIT** (`contracts/*.sol`), **CERN-OHL-S-2.0** (hardware),
and **CC-BY-SA-4.0** (documentation). Code and contracts carry **per-file SPDX
identifiers**; a new source file needs one, and CI enforces that
(`ruby scripts/spdx_headers.rb --check` — run it with `--write` and it adds the
line for you, at the position each language actually requires). If a file you
add carries someone else's copyright, leave it untagged and say so in the PR —
we make no licence claim over third-party code. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE) for the full zone map and third-party exceptions.
