---
name: memory-maintenance
description: "Use when curating the persistent file-based memory (…/memory/MEMORY.md + per-fact *.md) — structuring/grouping the index, removing cruft or duplication, fixing stale index hooks, trimming a bloated index line, or ensuring open action-items in memory are also tracked in 00_07. The HOW lives in .claude/prompts/memory_housekeeping.md; the memory FORMAT standard lives in the system prompt (don't restate). Iron rule: NO AMNESIA — preserve wins over cleanup. Examples: \"почисти память\", \"поструктуруй memory\", \"повидаляй дублі в памяті\", \"memory housekeeping\", \"чи всі to-do з памяті є в 00_07?\""
---

# Memory Maintenance

Executable playbook for keeping the persistent memory (`~/.claude/projects/…/memory/`) **clean, structured, dedup'd — without amnesia**. This skill is the **HOW**; it does **not** restate the memory FORMAT (frontmatter / types / Why+How-to-apply / `[[<slug>]]` links / one-fact-per-file — that's in the system prompt), nor the live state (that's in the memories themselves).

## 📖 The method lives in one place (don't restate it here)

Full step-by-step playbook + founder's principles + the zero-loss scripts → **`.claude/prompts/memory_housekeeping.md`**. Read it before acting. Sister to `[[reference_deep_archival_prompt]]` (00_07 cement) — same "the prompt is the home, the skill just points" pattern as `ssot-maintenance`.

**Three modes:** (1) *housekeeping* (this skill + the prompt — de-cruft, structure, stale-hooks, action-items→00_07); (2) *4-way memory-sync* — a per-section pass bringing memory ↔ domain-skill ↔ canon ↔ 00_07 to one truth (ROUTE-not-restate, fix drift on BOTH surfaces, write gaps). The sync recipe (fan-out READ-ONLY agents + fable-holistic) lives in `[[project_memory_sync_program]]`; the §00–§08 cycle closed 2026-07-18. (3) **class-home consolidation** — a theme scattered as a side-note across 15–35 files, each time in a DIFFERENT vocabulary, gets one home; grep cannot find it *by construction*, so the inventory is READ-based fan-out. Built in waves, each one paying part of the previous wave's phase-2 debt; the **7-step recipe and its traps live in `[[log_perimeter_prep]]` — read it BEFORE consolidating another**, and the live tally of homes + outstanding debt is `00_07` DOC-T.59, never a number here.

### Traps before you consolidate — each one cost a wave

*(This list said «three» while carrying six, for two weeks — a header is a claim, and it drifts like any mirror. It is now eight; the count is deliberately absent from the header.)*

**(1) Scout counts run LOW.** A scout agent's carrier count is systematically LOW (it reads big files; most carriers are short clauses in mid-sized ones) — and it is not a model tier but a QUESTION SHAPE: on DOC-T.58 the low count came from the *adversarial*, which sampled ten examples instead of inventorying, and undercounted **tenfold**.

**(2) A «half-home» may be a duplicate.** "This class already has two half-homes" is often not coverage but a **duplicate** — compare their texts before believing it.

**(3) One-way strings fake homelessness.** 🔴 **A section can read as a live homeless class purely because its string is ONE-WAY.** The home was built by extraction FROM that section and cites it as provenance, but phase 2 never left a router back — so the source's reader never learns the rule already has an address, and the next pass re-derives the whole class from scratch. The systematic hole: the recipe says "in EVERY source file", and in practice it got applied to the `project_*` file while its `log_*` twin kept the rule in full. **Before declaring any theme homeless, grep the candidate homes for a `[[string]] pointing AT this file` — a home that cites you is a home you already have.**

**(4) Machine dedup is capped at verbatim.** 🔴 **Any machine measure of duplication in this corpus is capped at VERBATIM, and the gap is an order of magnitude.** The corpus is bilingual, so a rule written in English in the journal and in Ukrainian in its home is invisible to grep AND to shingles: on the worst offender a READ-based inventory found ~80 doubled rules where grep saw 7 and the shingle gate saw 2. Start from `--audit` to get the verbatim ones for free, then inventory by READING — never treat a green overlap as "no duplicate homes", only as "no verbatim ones".

**(5) Declare the UNIT first.** 🔴 **"Debt weight" and "what an excision returns" are different quantities, and the difference is in the SIGN — so declare the UNIT before the pass.** In a `project_*` file the debt sits in the MISSING ROUTER, not in duplicated prose: the instance is load-bearing and the generalisation is one sentence, so replacing it with a `[[string]]` costs the same or more, and the file GROWS. A phase-2 pass over `project_*` is therefore **router placement, measured by COVERAGE (inbound files), never by bytes**; only `log_*` journals, which restate rules in full, give bytes back. The tell is readable before you start — a clause shaped "instance + one sentence of rule" returns zero. Same failure at the counting level: asked without a declared unit, one inventory answered **3** and **14** for the same corpus.

**(6) Mechanism ⊥ frame.** 🔴 **"Does this have a home" is TWO questions, and the second decides: is the MECHANISM in the corpus ⊥ is there a FRAME over it.** A mature class can have its mechanism written verbatim (under a name the tracker never used), its gate-side half in a skill, and its remedy in another home — and still lack the frame; building a file then buys a FOURTH address, while the right move is a **dispatch** (write the frame into the best existing home + strings back). Before deciding, enumerate what is already covered — instance, mechanism, remedy, or frame — because the homeless one is almost always the frame, and grep cannot find it: grep finds instances. Corollary on debt: the phase-2 rubrics DUPLICATE/ROUTED split by whether a string exists, which silently merges "done" with a third state — **the router is there AND the restatement stayed next to it**. That state reads as the cheapest excision in the corpus and no rubric names it, so ask the third question explicitly. 🔴 **But "cheapest" is only half true, measured on all 14 of them (2026-08-04): a string cannot be lost, yet the address can be WRONG and the home INCOMPLETE.** 3 of 14 routers pointed at the wrong place (a numbered skill item when the rule sat in the unnumbered paragraph beside it; `§3` when the rule was in `§4`; the instance's home when the rule's home was a different file) — that is disinformation, not debt, and it is invisible precisely because the link resolves. And 4 of 14 restatements carried a half the home did not have, so excising as planned would have been amnesia four times over; the fix is MIGRATE-FIRST (write the missing half into the home, verify, then cut) or leave it with an explicit "this is the only copy" marker. **So this class costs the same READ as an ordinary duplicate: verify the router's TARGET and the home's COMPLETENESS, never just the presence of `[[brackets]]`.** Measured numbers → `00_07` DOC-T.59.

**(7) An excision that TRANSLATES pays the bytes back — and looks like honest work while doing it.** 🔴 Measured 2026-08-04: shortening two English clauses and rewriting the remainder in Ukrainian produced **+40 B** across both; redoing the same two in the ORIGINAL language returned **−648 B**. Cyrillic costs 2 B/char, so the clause genuinely shrinks in characters while growing in bytes — the tell is invisible unless you measure in the unit the ceiling counts. **Keep the clause in the language it was written in**; the choice is a unit of measurement, not style. The sibling one level up: an excision's own INVENTORY costs about what the excision returns (seven cuts plus a refreshed header came to −35 B net), so **never report this work in bytes** — report how many rules stopped living in two homes.

**(9) «All three surfaces» is FOUR — the index is one of them.** 🔴 A class was declared homeless twice, with the formula "zero hits across memory · skills · canon", while its home sat in `project_sec07_legal_campaign` **under the tracker's own literal wording** — and that same wording was a line in `MEMORY.md`, the file loaded into every single session (DOC-T.59, 2026-08-04). This is not the vocabulary trap of #3: the words matched. The index escapes the sweep because it is read as *navigation* rather than as content, so a three-surface pass walks past the one surface that is always already in context. **Before any "homeless" verdict, grep `MEMORY.md` itself** — and note the asymmetry that makes this expensive: a hook is one line, so the home it points at is exactly what a class-search is looking for, and finding it costs one grep against a wave of consolidation work.

**(8) Measure the RECEIVER's headroom, not just the source's debt.** 🔴 MIGRATE-FIRST requires writing the missing half INTO the home, and a saturated home has nowhere to put it. Measured 2026-08-04: five rule-homes sit at 35.7–36.0 kB against a 36 kB WARN, i.e. the phase-2 receivers hit the ceiling as a GROUP, not one fat outlier — one edit pushed a home past WARN mid-session and an instance had to be evicted before the migration could proceed. The lever is eviction into the `log_*` twin (what the gate's own CAP line advises), never prose dieting (~2% at the ceiling); check the twin EXISTS first — one of the five has none. Order the work by *which home the next wave must write into*, not by which is fattest. 🔴 **Two corrections measured 2026-08-04, both about the instrument rather than the size.** (a) `WARN` is not a warning: `--audit` ends in `[ -z "$out" ]`, so a single WARN line makes the whole battery EXIT 1 — the working ceiling is the WARN, and the CAP is only where the advice changes. (b) **Before asking "where do I migrate this half", ask whether it is ONE rule at all.** A clause whose two halves belong to two different homes is cured by a PAIR of routers and needs no headroom anywhere — that is what unblocked a migration into a home with 36 B left. And when you do evict, the direction matters more than the byte count: move INSTANCES down into the journal, never the generalised rule, however verbatim the twin repeats it — a rule that lives only in a dated journal paragraph is findable only by someone who already knows the incident.

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
1. INVENTORY  memory_gate.sh --audit — run it, do NOT enumerate its axes here: a
              list-by-example rots with every axis added (four so far), while a
              pointer at the live source stays true. One axis is worth knowing by
              name: OVERLAP names phase-2 debt directly — silent when the copy
              carries a router home, loud when it restates with no pointer, so
              its output IS the worklist.
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
