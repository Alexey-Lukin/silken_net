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
- **Python (in-silico / ML):** `ruff check` (config: `ruff.toml`)
- **Firmware (STM32):** `make -C firmware/test` (host x86 — no ARM toolchain needed)
- **Solidity (Foundry):** `cd contracts && npm ci && forge build --sizes && forge test -vvv`

In addition:

- **Add or update automated tests** when you add or change functionality — major
  new functionality should land with tests in the relevant suite (RSpec /
  Foundry `forge` / firmware host tests).
- Match the style of the code around you (naming, comments, idiom). Keep comments
  minimal and free of drift-prone numbers.
- The `docs/NN_NN_*.md` files are the single source of truth. If you change
  behaviour, update the relevant canon doc — see
  [`docs/00_06`](docs/00_06_SSOT_Documentation_Standard.md). Open or in-progress
  work is tracked in [`docs/00_07`](docs/00_07_Action_Plan_Tracker.md).
- Write a clear commit message; AI-assisted commits should carry the appropriate
  `Co-Authored-By` trailer.

## License of contributions

By contributing, you agree that your contributions are licensed under the
project's licenses: **AGPL-3.0-or-later** (code), **CERN-OHL-S-2.0** (hardware),
and **CC-BY-SA-4.0** (documentation). See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE) for the full zone map and third-party exceptions.
