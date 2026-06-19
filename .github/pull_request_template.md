<!-- Keep it short — this is a checklist, not paperwork. -->

## What & why
<!-- One or two lines: the change and the reason / the 00_07 item it closes. -->

## Checklist
- [ ] **Conventional-commit title** (`feat:` / `fix:` / `chore:` / `docs:` …) — release-please reads it for the next version + CHANGELOG.
- [ ] **`CI passed`** + **`Docs passed`** green (the path-gated jobs that actually ran are green).
- [ ] **SSOT:** docs updated to match the code — OR a `type:*` label set if the change is non-architectural.
      `type:chore` / `type:deps` / `type:perf` / `type:test` bypass the SSOT guard;
      `type:refactor` / `type:bugfix` still need a `docs/` update or a Drift-Register entry
      (see [`00_05 §2.3`](../docs/00_05_GitHub_Projects_and_IaC_Automation.md)).
