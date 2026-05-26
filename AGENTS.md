<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **silken_net** (10925 symbols, 19601 relationships, 300 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/silken_net/context` | Codebase overview, check index freshness |
| `gitnexus://repo/silken_net/clusters` | All functional areas |
| `gitnexus://repo/silken_net/processes` | All execution flows |
| `gitnexus://repo/silken_net/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |
| Work in the Maintenance area (198 symbols) | `.claude/skills/generated/maintenance/SKILL.md` |
| Work in the Models area (196 symbols) | `.claude/skills/generated/models/SKILL.md` |
| Work in the V1 area (158 symbols) | `.claude/skills/generated/v1/SKILL.md` |
| Work in the Test area (119 symbols) | `.claude/skills/generated/test/SKILL.md` |
| Work in the Ui area (114 symbols) | `.claude/skills/generated/ui/SKILL.md` |
| Work in the Previews area (112 symbols) | `.claude/skills/generated/previews/SKILL.md` |
| Work in the Scripts area (108 symbols) | `.claude/skills/generated/scripts/SKILL.md` |
| Work in the Services area (107 symbols) | `.claude/skills/generated/services/SKILL.md` |
| Work in the Codex area (99 symbols) | `.claude/skills/generated/codex/SKILL.md` |
| Work in the Workers area (57 symbols) | `.claude/skills/generated/workers/SKILL.md` |
| Work in the Fractions area (46 symbols) | `.claude/skills/generated/fractions/SKILL.md` |
| Work in the Web3 area (40 symbols) | `.claude/skills/generated/web3/SKILL.md` |
| Work in the Soldier area (37 symbols) | `.claude/skills/generated/soldier/SKILL.md` |
| Work in the Trees area (32 symbols) | `.claude/skills/generated/trees/SKILL.md` |
| Work in the Factory_flashing area (30 symbols) | `.claude/skills/generated/factory-flashing/SKILL.md` |
| Work in the Queen area (27 symbols) | `.claude/skills/generated/queen/SKILL.md` |
| Work in the Clusters area (24 symbols) | `.claude/skills/generated/clusters/SKILL.md` |
| Work in the Tree_chronicle area (23 symbols) | `.claude/skills/generated/tree-chronicle/SKILL.md` |
| Work in the Policies area (20 symbols) | `.claude/skills/generated/policies/SKILL.md` |
| Work in the Hil area (20 symbols) | `.claude/skills/generated/hil/SKILL.md` |

<!-- gitnexus:end -->
