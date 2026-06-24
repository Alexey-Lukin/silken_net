# Project Governance

This document describes how the **Silken Net** software project is governed — how
decisions are made and who makes them.

> **Not to be confused with the on-chain DAO.** This page is about governance of the
> *software project* (this repository). The protocol's *on-chain* parameter governance
> — the SFC DAO / `SilkenGovernor` + 48 h Timelock — is a separate, product-level
> mechanism that governs the deployed protocol, not the development of this repo. It is
> documented in [`docs/05_06`](docs/05_06_Governance_and_DAO.md).

## Model — single maintainer (benevolent dictator)

Silken Net is currently led by its founder and sole maintainer, **Oleksii Lukin**
([@Alexey-Lukin](https://github.com/Alexey-Lukin)), who makes all final technical,
architectural and release decisions. This single-maintainer ("benevolent dictator")
model is appropriate for the project's current early stage; as a FLOSS project, anyone
is of course free to fork.

## How decisions are made

- **Day-to-day changes** land via the contribution process in
  [`CONTRIBUTING.md`](CONTRIBUTING.md): fork → topic branch → pull request → review.
- **Review & merge authority:** the maintainer reviews and merges pull requests; review
  ownership is recorded in [`.github/CODEOWNERS`](.github/CODEOWNERS), and `main` is
  protected by required CI status checks.
- **Architecture & specifications** are decided *documentation-first*: the canonical
  design lives in the SSOT docs (`docs/NN_NN_*.md`) and a change in behaviour is agreed
  in the docs before code is written (see
  [`docs/00_02`](docs/00_02_AI_Native_Engineering_and_TRL.md)). Open work and decisions
  are tracked in [`docs/00_07`](docs/00_07_Action_Plan_Tracker.md).
- **Security decisions** follow [`SECURITY.md`](SECURITY.md).
- **Disputes** are resolved by the maintainer.

## Roles

| Role | Who | Responsibility |
|------|-----|----------------|
| Maintainer / Lead | Oleksii Lukin ([@Alexey-Lukin](https://github.com/Alexey-Lukin)) | Final decisions, code review, releases, security response |
| Contributors | anyone | Propose changes via pull requests (see `CONTRIBUTING.md`) |

## Evolution

As the contributor base grows, the project intends to move toward **shared
maintainership** (multiple maintainers with review/merge rights). Any change to this
governance model is made by the current maintainer and recorded in this file's history.
