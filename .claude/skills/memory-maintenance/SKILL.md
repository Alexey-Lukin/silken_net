---
name: memory-maintenance
description: "Use when curating the persistent file-based memory (…/memory/MEMORY.md + per-fact *.md) — structuring/grouping the index, removing cruft or duplication, fixing stale index hooks, trimming a bloated index line, or ensuring open action-items in memory are also tracked in 00_07. The HOW lives in .claude/prompts/memory_housekeeping.md; the memory FORMAT standard lives in the system prompt (don't restate). Iron rule: NO AMNESIA — preserve wins over cleanup. Examples: \"почисти память\", \"поструктуруй memory\", \"повидаляй дублі в памяті\", \"memory housekeeping\", \"чи всі to-do з памяті є в 00_07?\""
---

# Memory Maintenance

Executable playbook for keeping the persistent memory (`~/.claude/projects/…/memory/`) **clean, structured, dedup'd — without amnesia**. This skill is the **HOW**; it does **not** restate the memory FORMAT (frontmatter / types / Why+How-to-apply / `[[<slug>]]` links / one-fact-per-file — that's in the system prompt), nor the live state (that's in the memories themselves).

## 📖 The method lives in one place (don't restate it here)

Full step-by-step playbook + founder's principles + the zero-loss scripts → **`.claude/prompts/memory_housekeeping.md`**. Read it before acting. Sister to `[[reference_deep_archival_prompt]]` (00_07 cement) — same "the prompt is the home, the skill just points" pattern as `ssot-maintenance`.

**Two modes:** (1) *housekeeping* (this skill + the prompt — de-cruft, structure, stale-hooks, action-items→00_07); (2) *4-way memory-sync* — a per-section pass bringing memory ↔ domain-skill ↔ canon ↔ 00_07 to one truth (ROUTE-not-restate, fix drift on BOTH surfaces, write gaps). The sync recipe (fan-out READ-ONLY agents + fable-holistic) lives in `[[project_memory_sync_program]]`; the §00–§08 cycle closed 2026-07-18.

## When to use
- Structuring / grouping `MEMORY.md` (by kind: 👤User / 🛠Feedback / 📚Reference / 📦Project, + sub-themes).
- Removing memory cruft / duplication; trimming a bloated index hook (detail belongs in the file).
- Fixing a stale index hook (drifted from its file).
- "Is every open to-do/check in memory also in 00_07?" → migrate the gaps.
- Integrity check (1:1 index↔files, no broken/orphan).

## Core principle — NO AMNESIA
**Preserve beats cleanup.** Before removing ANY content, verify it lives elsewhere (the file, git, canon, `00_07`). Improve/relocate, never delete what's valuable. When "remove cruft" conflicts with "don't lose what's needed" → keep. A well-curated memory's housekeeping is mostly **de-bloat + structure + stale-hook fixes**, not mass-deletion — say so honestly, don't manufacture deletions (the `ssot-maintenance` "don't manufacture moves" lesson, applied to memory).

## The loop (detail → prompt)
```
1. INVENTORY  list files (size/lines/type) + 1:1 index↔files integrity (0 broken / 0 orphan).
2. INDEX=HOOKS  trim any bloated index line — but VERIFY the detail is in the file FIRST.
3. STRUCTURE  group MEMORY.md by kind via a verbatim-reorder script; prove zero-loss
              (sorted entry-set diff == IDENTICAL).
4. DE-CRUFT   only truly-dead content; verify-before-delete; preserve lessons/decisions/
              open-items/links. Don't gut the big history file without explicit OK.
5. ACTION→00_07  any open to-do/check/follow-up not in 00_07 → add it (correct §-home;
              section-home guard) + a "Tracked in 00_07: <ID>" back-pointer in the memory.
6. STALE-HOOKS  refresh hooks that drifted from their file's state.
7. REPORT     honestly: cleaned / deliberately-kept (no amnesia) / flagged.
```

## Gotchas (hard-won, 2026-06-13)
- **Edit can't match a ~7000-char index line** → use a Ruby `lines[i] = …` replace with an `abort unless lines[i].include?("marker")` guard; `cp` backup first, `diff` after.
- **Memory is OUTSIDE the git repo** (`~/.claude/…`) → no `git revert`; your backup + zero-loss diff is the only safety net.
- **Verify-before-delete** ([[feedback_verify_canon_before_delete]]) and **no-volatile-counts** ([[feedback_no_volatile_counts]]) apply to memory too (a hook must not hold drift-prone counts; trimmed detail must already live in the file).
- **De-dup is rare** — memories cross-link via `[[<slug>]]`, not restate; the big duplication is usually index-vs-file. Two distinct facts of the same kind are NOT a duplicate.
- **The prompt's own §Durable-уроки = a 6-family frame (auto-consolidate — the method applies to itself):** a new lesson gets **melted into the fitting family as a line**, NOT glued on as a fresh date-stamped paragraph (the section already bloated into a wall once and had to be refactored). New family only if it fits none (keep ≤~7); a family past ~6 lines → compress that family the same way.

> If you're tempted to add the memory FORMAT rules or live state here, stop — format → system prompt; state → the memories; the full method → `.claude/prompts/memory_housekeeping.md`. Keep this skill a thin pointer.
