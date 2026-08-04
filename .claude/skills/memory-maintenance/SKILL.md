---
name: memory-maintenance
description: "Use when curating the persistent file-based memory (…/memory/MEMORY.md + per-fact *.md) — structuring/grouping the index, removing cruft or duplication, fixing stale index hooks, trimming a bloated index line, or ensuring open action-items in memory are also tracked in 00_07. The HOW lives in .claude/prompts/memory_housekeeping.md; the memory FORMAT standard lives in the system prompt (don't restate). Iron rule: NO AMNESIA — preserve wins over cleanup. Examples: \"почисти память\", \"поструктуруй memory\", \"повидаляй дублі в памяті\", \"memory housekeeping\", \"чи всі to-do з памяті є в 00_07?\""
---

# Memory Maintenance

Executable playbook for keeping the persistent memory (`~/.claude/projects/…/memory/`) **clean, structured, dedup'd — without amnesia**. This skill is the **HOW**; it does **not** restate the memory FORMAT (frontmatter / types / Why+How-to-apply / `[[<slug>]]` links / one-fact-per-file — that's in the system prompt), nor the live state (that's in the memories themselves).

## 📖 The method lives in one place (don't restate it here)

Full step-by-step playbook + founder's principles + the zero-loss scripts → **`.claude/prompts/memory_housekeeping.md`**. Read it before acting. Sister to `[[reference_deep_archival_prompt]]` (00_07 cement) — same "the prompt is the home, the skill just points" pattern as `ssot-maintenance`.

**Three modes:** (1) *housekeeping* (this skill + the prompt — de-cruft, structure, stale-hooks, action-items→00_07); (2) *4-way memory-sync* — a per-section pass bringing memory ↔ domain-skill ↔ canon ↔ 00_07 to one truth (ROUTE-not-restate, fix drift on BOTH surfaces, write gaps). The sync recipe (fan-out READ-ONLY agents + fable-holistic) lives in `[[project_memory_sync_program]]`; the §00–§08 cycle closed 2026-07-18. (3) **class-home consolidation** — a theme scattered as a side-note across 15–35 files, each time in a DIFFERENT vocabulary, gets one home; grep cannot find it *by construction*, so the inventory is READ-based fan-out. Built in waves, each one paying part of the previous wave's phase-2 debt; the **7-step recipe and its traps live in `[[log_perimeter_prep]]` — read it BEFORE consolidating another**, and the live tally of homes + outstanding debt is `00_07` DOC-T.59, never a number here. Three traps worth knowing before you start. (1) A scout agent's carrier count is systematically LOW (it reads big files; most carriers are short clauses in mid-sized ones) — and it is not a model tier but a QUESTION SHAPE: on DOC-T.58 the low count came from the *adversarial*, which sampled ten examples instead of inventorying, and undercounted **tenfold**. (2) "This class already has two half-homes" is often not coverage but a **duplicate** — compare their texts before believing it. (3) 🔴 **A section can read as a live homeless class purely because its string is ONE-WAY.** The home was built by extraction FROM that section and cites it as provenance, but phase 2 never left a router back — so the source's reader never learns the rule already has an address, and the next pass re-derives the whole class from scratch. The systematic hole: the recipe says "in EVERY source file", and in practice it got applied to the `project_*` file while its `log_*` twin kept the rule in full. **Before declaring any theme homeless, grep the candidate homes for a `[[string]] pointing AT this file` — a home that cites you is a home you already have.** (4) 🔴 **Any machine measure of duplication in this corpus is capped at VERBATIM, and the gap is an order of magnitude.** The corpus is bilingual, so a rule written in English in the journal and in Ukrainian in its home is invisible to grep AND to shingles: on the worst offender a READ-based inventory found ~80 doubled rules where grep saw 7 and the shingle gate saw 2. Start from `--audit` to get the verbatim ones for free, then inventory by READING — never treat a green overlap as "no duplicate homes", only as "no verbatim ones".

## When to use
- Structuring / grouping `MEMORY.md` (by kind: 👤User / 🛠Feedback / 📚Reference / 📦Project, + sub-themes).
- Removing memory cruft / duplication; trimming a bloated index hook (detail belongs in the file).
- Fixing a stale index hook (drifted from its file).
- "Is every open to-do/check in memory also in 00_07?" → migrate the gaps.
- Integrity check (1:1 index↔files, no broken/orphan).

## Core principle — NO AMNESIA
**Preserve beats cleanup.** Before removing ANY content, verify it lives elsewhere (the file, git, canon, `00_07`). Improve/relocate, never delete what's valuable. When "remove cruft" conflicts with "don't lose what's needed" → keep. A well-curated memory's housekeeping is mostly **de-bloat + structure + stale-hook fixes**, not mass-deletion — say so honestly, don't manufacture deletions (the `ssot-maintenance` "don't manufacture moves" lesson, applied to memory).

## The gate is the home of the mechanics — not this file, not the prompt
`.claude/hooks/memory_gate.sh` runs the whole step-1 battery (`--audit`, exit 0 = clean; `--genre` = chronicle detector alone) **and** rides `PostToolUse` on every write into the corpus, so it fires at the moment a wall gets built rather than when someone remembers to clean. Found a new blindness class? **Patch the script** — it is live on the next write, and the separate "carry the lesson into the gate" step that failed before no longer exists. Thresholds are curated constants inside it; the corpus is outside git but the gate is not, so a bump is a visible decision.

## The loop (detail → prompt)
```
1. INVENTORY  memory_gate.sh --audit (index ratchet · description-layer ratchet ·
              file ceiling · chronicle · integrity · block-OVERLAP incl. journals ·
              SECREF dead §-address). OVERLAP names phase-2 debt directly: it stays
              silent when the copy carries a router to its home, and fires when it
              restates the rule with no pointer — so its output IS the worklist.
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
