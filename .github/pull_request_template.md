<!-- Keep it short — this is a checklist, not paperwork. -->

## What & why
<!-- One or two lines: the change and the reason / the 00_07 item it closes. -->

## Checklist
- [ ] **Conventional-commit title** (`feat:` / `fix:` / `chore:` / `docs:` …) — release-please reads it for the next version + CHANGELOG.
- [ ] **All 9 required aggregates** green (`CI` / `Docs` / `Solidity` / `Subgraph` / `CAD` / `ML` / `In-silico` / `IaC` / `DCO passed` — the path-gated jobs that actually ran are green).
- [ ] **SSOT:** docs updated to match the code — OR a `type:*` label set if the change is non-architectural.
      `type:chore` / `type:deps` / `type:perf` / `type:test` bypass the SSOT guard;
      `type:refactor` / `type:bugfix` still need a `docs/` update — or log the open drift in
      [`00_07`](../docs/00_07_Action_Plan_Tracker.md), which is itself a `docs/` change
      (see [`00_06 §3`](../docs/00_06_SSOT_Documentation_Standard.md)).
