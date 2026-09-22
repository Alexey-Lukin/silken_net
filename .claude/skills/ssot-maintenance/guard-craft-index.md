# Guard-craft — thesis, design rules and the index of blindness shapes

> **Companion file of the `ssot-maintenance` skill, and the ENTRY to guard-craft.** Open it the moment the
> task is an EVENT rather than docs work: building, hardening or debugging a gate · asking whether a spec
> can fail at all · mass-deleting · narrowing a rule · running a campaign · shipping anything a human
> executes by hand. The bodies are in [`guard-craft.md`](guard-craft.md) — open them BY NUMBER from the
> index below, never whole.
>
> ⚖️ **Why this is not in `SKILL.md` (founder 2026-09-19).** The index belongs to the EVENT, while `SKILL.md`
> loads with the DOMAIN — on every docs session and in the start ritual, hours before any gate is built,
> and truncated after compaction. What fires at the moment of action is the skill's description and the
> `CLAUDE.md §2` event row, and both name these events. **Declared price:** a docs-only session no longer
> sees the leads, so a shape that bites during ordinary doc editing reaches you only if you recognise the
> event. ⚠️ The ground is the MOMENT, not rarity: `guard-craft.md` is edited on almost every working
> day (measured 2026-09-19), so few sessions never touch gate work — the move saves the start-ritual read,
> not the lookup. ⛔ Do not move the index back to buy that serendipity — reopen this verdict instead. The recipe «Add a new drift
> guard» moved here the same day on the same ground (⚖️ founder 2026-09-19): it fires on the same event.

## Add a new drift guard — the recipe

This is the point: it lets you turn **any** newly-found drift class into a permanent gate. **The bound on the skill is a MECHANISM, never a property, and it has to be operated: the body of a new blindness shape goes into `guard-craft.md`, and only its generated index line lands here** (`ruby scripts/guard_craft_index.rb --write`). Recipe, mirroring the existing `DocsLinter` methods:

0. **Name the KIND of gate first — the three kinds carry different obligations** (its home is here — `00_06 §3` partitions gates by SUBJECT and never classifies them by kind).
   1. **owned-value** — a specific value restated outside its home (Lorenz β, RTC registers, mint/carbon rate). Instrument: owner-only vocabulary inside `docs:check_refs`, with the owner doc exempt by construction.
   2. **structural / registry-sync** — doc and code must be 1:1 and the gate COUNTS rather than reads (`model_doc_sync`, `cem_canon_sync`, `governance_*_sync`, `ruby_version_sync`, `protocols_ref_check`, `code_tracker_id_check`) — plus the **meta-gates over the gates themselves** (`guard_registry_sync`, `workflow_gate_perimeter`), because a registry of gates rots one-way exactly like canon does.
   3. **semantic, with a NAMED ceiling** — where a word carries intent rather than a value (`offering_lexicon_check`). This kind MUST declare what it cannot see, or green starts to mean "not checked".
   They are not interchangeable: reaching for (1) on a (3)-shaped problem is how a noisy advisory is born, and skipping the ceiling on (3) is how a green run becomes a false attestation. ⊕ The mirror risk when READING the registry rather than writing it — canon describing a gate as *weaker* than it has become, so the reader inherits an inflated backlog — is not a gate-craft shape but a drift class; it lives in memory `feedback_vilize_sweep_method` F3, and the practical half is: measure a gate's severity by RUNNING it, never by grepping the word «advisory».
1. **Pick the owner.** Which doc canonically owns this fact (`00_06 §2`)? Everything else must only reference it. ⚖️ **Ratified 2026-09-08 — a kind-1 (owned-value) gate obliges a DECLARED home row in `00_06 §2`: verify it exists, or add it.** Nothing in CI catches a missing one; the price of that refusal is declared in §2's own intro. Exemptions: the `00_06 §2` intro — do not infer them from the kind numbers above.
2. **Write a pure function** in `lib/docs_linter.rb` — `module_function`, takes `text` (or `basename, text`), returns an array of human-readable violation strings. No Rails, no I/O.
3. **Keep false positives near zero** (heuristic linters are noisy):
   - Unicode-letter boundaries `(?<!\p{L})…(?![\p{L}])` so `звільнило`/`зарезервовано:` don't match a `вільн`/`резерв` rule.
   - Skip table rows (`line.lstrip.start_with?("|")`) and ```` ``` ```` fenced code.
   - **Exempt the owner doc** — it's *allowed* to state the fact.
4. **Unit-test it** in `spec/lib/docs_linter_spec.rb`: a positive (catches the real drift), a clean pass, and the near-misses that must *not* trip. Run `COVERAGE=0 bin/rspec spec/lib/docs_linter_spec.rb`. **Then mutation-verify** (break it → FAIL → revert). A symmetry / false-green-prone guard goes through a 2-agent review before it silences a class (`[[project_doc_t33_t34_seed]]`). Full craft → **§Guard-craft** below.
5. **Wire it into** `lib/tasks/docs.rake` `check_refs`: accumulate hits, print a report block, push a label into `failed` (advisory while you triage the existing hits → flip to **HARD** at zero UNTRIAGED). 🔴 **The flip criterion is ZERO UNTRIAGED, not zero hits — a RATIFIED ⛔ inside the perimeter makes zero unreachable** (`offering_lexicon_check`: a fee rendered from a historical record, and its seed). **A criterion that a verdict makes impossible is not a criterion.** Before promising a flip, name what inside the perimeter is deliberately immovable; if anything is, the honest form is a NAMED-CLASS exemption plus the flip, never a wait for zero. ⊕ The mirror is equally real and this skill already carries it — `guard-craft` #50 says outright that «sweep the citations to zero» is partly unverifiable by any gate.
6. **Record it** under the matching subsection of `00_06 §3` — §3 is partitioned by SUBJECT (`3.1` doc form · `3.2` `00_07` · `3.3` owner-only values · `3.4` canon⟷code · `3.5` canon⟷infra/CI · `3.6` meta-gates), not one flat table — and in the campaign memory, **not in this skill**. ⚠️ Keep the description cell under `CELL_CEILING` (`scripts/guard_registry_sync.rb`, HARD): name the mechanism here and point at the engine header for the WHY. ⚠️ Scope of that duty: §3 registers **workflow steps** — `docs_check` steps (CHECK A) plus the curated out-of-`docs.yml` allow-list (CHECK A2) — and CHECK E is the reverse axis, so a row must name a command a workflow actually runs. An **invariant spec living in the RSpec suite** is therefore NOT a §3 row: its three siblings (`spec/security/no_raw_action_cable_spec.rb`, `spec/i18n/broadcast_payload_invariance_spec.rb`, the enum-parity specs) have none, and adding one risks tripping CHECK E. Such a gate's home is the **canon section it protects** (e.g. `04_04 §8.1`) plus its own spec header. Verify which kind you built by running `guard_registry_sync` — don't infer it from this sentence. For workflow-step gates the enforcement below does apply: `guard_registry_sync` (DOC-T.40) fails CI if a new gate has no §3 row, if a §3 row names a file that no longer exists, **or if a §3 row claims a command/workflow the CI never runs** (reverse axis E — write the §3 command column exactly as the workflow runs it, and mark non-CI rows `advisory`/`on-demand`). A new `docs.rake` `failed <<` label also needs a `DOCS_RAKE_LABELS` entry in `scripts/guard_registry_sync.rb`, or CHECK B reds. Cross-file / code-reading gates go in `scripts/*.rb`, not `lib/docs_linter.rb` (which is pure-doc text); wire the new script into `docs.yml` **and** confirm its inputs are inside the `changes` filter — a gate outside it is decorative. 🔴 **A `docs_check` step must also RUN without booting the app** (UI.1, 2026-08-07): every step in that job runs without the app — no rake task in it declares **`:environment`**, so the runner installs no native image/DB stack — a step carrying `:environment` dies at `ActiveStorage::Transformers::Vips` before its first line, green locally and red in CI for a reason unrelated to what it checks. The trap is in the inference, not the config: seeing `bin/rails <task>` in the job reads as "so Rails boots here", while `bin/rails` only boots the app when the TASK declares it — grep the neighbours' `task` lines before assuming a runtime exists. (For an *unambiguous* retired string with no legit current use, skip the bespoke linter: add it to `DocsLinter::DEPRECATED_TERMS` — the general "any retired token's return is blocked" net.)

> When the **standard itself** changes (skeleton, home registry), edit `00_06` (the home) — this skill's pointers stay valid by design.

## 🛡️ A gate that actually catches

`00_06 §3` is the *registry* (which guards exist); a script's own header is the home of *why that guard is shaped the way it is* (it rots together with the code, so it cannot drift); **this file carries the craft's THESIS, its design rules and the generated index, and [`guard-craft.md`](guard-craft.md) carries the blindness shapes in full.** Instances/demonstrations live in the session memories that found them.

## The question that matters

Not "is there a gate?" but **"WHAT DOES THIS GATE NOT SEE?"** A green gate is evidence only about the class it actually inspects. Two consequences worth internalising:

- **Guards skew away from money.** Pure-doc surfaces end up well fenced while the doc⟷code *value* surface is held together by hand. The cheapest real gap is a **mirror declared in a code comment** ("edit it THERE") with no pin — most money-path holes closed by adding a row to `canonical_block_pins.yml` without touching the engine. Grep for comment-declared mirrors and ask: does each have a pin?
- **Cite a gate only for the class it truly catches.** `model_doc_sync` exiting 0 says nothing about prose — it compares *class names*. A green run quoted as proof of something adjacent is a counterfeit coin.

🔴 **And do not read a gate as a META-level: it is a CHANNEL like any other, and it catches both diseases of one.** A gate can **assert a verdict it never earned** — a CI job green on zero examples; `grafana_alerts_spec` proving every metric named in an alert expr EXISTS IN THE REGISTRY while staying green by construction on the only question that matters, whether they measure what their names promise (⛔ do NOT restate this as «proves every metric has a WRITE SITE» — that spec carries no write-site assertion in any example, and the direction it judges is the opposite one; the write-site question was a MANUAL sweep, and nothing gates it) — and it can **deliver nothing while nobody notices** — `i18n-tasks` printing ERROR and returning exit 0 (#10). Those are the same two failures the gate was built to catch, one level up, which is why "add another gate" does not terminate the regress. **The terminator is an EXTERNAL EYE**: across one full day on this axis, adversarial review caught the author three times and the gates caught him zero. Budget the outside read as part of building a gate, not as a luxury afterwards. Homes of the two diseases themselves: assertion-without-proof → memory `feedback_self_attestation`; channel-with-no-consumer → memory `feedback_mechanism_vs_its_trigger` leg 2.

## A freshly-written gate is the worst-tested code in the repo

Mutation-verify proves it catches the INTENDED — nothing about what it cannot see. Three failure shapes are worse than "blind to a class"; the first two shipped here **in the same session the gate was born**:

- **Dead scope under a green label.** `Tracker::Dashboard.stale_who` anchored on `\z` while `each_line` keeps the trailing `\n` → the match failed on EVERY line, the HARD check did not exist, and the run printed "clean". An empty scope is indistinguishable from success. **In any line-scanning linter use `\Z` (or `chomp`), never `\z`** — and write a positive spec *for every scope*, otherwise "zero violations" means "zero checks".
- **A term that is a substring of the project's most frequent noun.** `ROI` ⊂ **gyroid** made the public manifesto read as three violations. Ask both "what does this regex NOT match?" and **"what does it match that it shouldn't — judged on the real hits, not on the intent."**

- **An exemption compared against the WRONG REPRESENTATION of its own key.** `deploy_workflow_parity_spec` normalises step names (stripping ` to Canopy`/` to Production`) and then exempted the raw name `"Kamal Deploy to"` — which the normalised string can never match, so the exemption fired NEVER and the gate reddened a correct tree on its first run. **Reflex for any gate with a normalise-then-compare pipeline: write the exemption in the POST-transform vocabulary, and prove it by removing the exemption and watching the gate go red on the tree you know is correct.** ⊕ Sibling axis, same session: the older gate beside it answered *"is this mapped ANYWHERE"* across the union of both workflows AND every `env:` block inside them, when the question was *"does it reach the deploy STEP"* — that one IS a numbered shape (#8, existence-where-the-defect-is-SCOPE), and the fix followed #8's own prescription: a SECOND, narrower check rather than a wider first one.

**Precision is measured in hits and lives in the ANCHOR.** Anchoring on individual words (`required`, `deterministic` — among the most common words in this canon) yielded 19% precision: 16 hits, 3 real. Narrowing to a **collocation** (`required status check` / `required-чек` / `PR-гейт`), demanding a number adjacent to the anchor, and scrubbing `TRL`/`§`/doc-ids took it to 100%. **A noisy advisory is a disabled gate**, so triaging every hit by eye is not optional.

## Ways a gate cannot see its own surface

> **The blindness shapes live in [`guard-craft.md`](guard-craft.md) — this is their index, generated from it.**
> Below is one line per shape — the LEAD only, deliberately: it must fire on its own. **Open `guard-craft.md` for the reflex, the mechanism,
> the incident that bought it, and its bounds** — and open it not only when building or hardening a
> gate, but also when writing a spec, doing a mass delete, narrowing a rule, running a campaign, or
> shipping anything a human executes by hand: roughly half of these fire outside gate-work.
>
> ⚠️ Honest about the cost: that file is the heaviest artifact in the practice (price it with
> `memory_gate.sh --weight`, never from a number written here), so "one Read away" is true of the address, not of
> the price. The trade: the leads cost one small Read, the evidence one Read per NUMBER. Edit rules
> THERE; a hand-edit here is a second home and `--check` reds.

<!-- GUARD-CRAFT-INDEX:AUTO — generated from guard-craft.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. Decorative — the gate's INPUT sits outside the workflow's `changes:` filter, so it only ever fires on somebody else's PR
2. A whole GENRE outside every linter's namespace — «Стаття N» headings; a genre exempt BY DESIGN is where drift is densest, so a green `docs_check` ≠ correctness there
3. A noisy advisory is functionally OFF — and a semantic gate that does not name its CEILING in the script header turns green into «not checked»
4. Blind to its own prose — a gate sees its DATA, never what it SAYS about itself, so its header comment can contradict its own constant indefinitely
5. It under-implements the contract it declares — the prose is right and the code is a SUBSET, so a green run attests only the half that was actually built
6. It compares a HOMOGENEOUS pair and is blind to the seam between LAYERS
7. A config mask switches the gate OFF, and the comment above it justifies a DIFFERENT problem
8. It checks EXISTENCE where the real defect is SCOPE
9. A guard's own extraction regex silently under-collects, and the guard's ceiling section says nothing about it
10. It announces its own failure LOUDLY — and exits 0
10a. The gate must skip its own documentation — and that necessary skip leaves the HUMAN measurement permanently poisoned
11. The spec pins that the call HAPPENED, never where it POINTED
12. The spec computes its expectation with the SAME broken transform as the code
13. «Closed» for one caller is not closed for the CLASS
14. It pairs A with B and never asks whether EITHER is reachable
15. It checks that a pairing EXISTS and cannot ask who OWNS the shape flowing through it
16. The assertion runs in the one locale where the fix and the bug produce IDENTICAL output
17. The pinned CSS class exists elsewhere on the same page, so the example passes through a NEIGHBOUR
18. The session that hunts stale mirrors leaves its own
19. The idempotency spec is vacuous because the first run removed the subject from the scan scope
20. The fix silently invalidates the spec that guarded the thing it fixed
21. A scoping fix has THREE halves — the query, the CACHE KEY, and whoever DELETES that key — and mutating only the query proves one of them
22. Premises that apply identically to both branches cannot rank the branches
23. A one-home refactor BLINDS the gate that keyed on the value's literal shape — and the fix is to key on the CENTRALIZER, not to widen the shape
24. A machine-derivable attribute stands in for the human-only one that actually decides
25. A new example can be vacuous because the method under test is STUBBED elsewhere in its own file — and the neighbouring example's odd-looking setup line is the tell
26. Citing the wrong precedents is the same failure as inventing a mechanism, one level up: the EVIDENCE is borrowed rather than the reasoning
27. A gate whose bypass is CHEAP and whose miss is SILENT is aimed at the wrong population — it has NEGATIVE expected value, not merely low
28. The subject runs BEFORE the layer you would compare it against — so its own spec is structurally incapable of going red
29. Mass deletion leaves SEMANTIC tails that every link-checker blesses — the ID still resolves, so the gate stays green while the prose lies
30. A gate on the OUTCOME can be held up by a third party, so it goes green for a reason that has nothing to do with your code
31. It validates each RECORD and never asks whether two records AGREE
32. A claim about INHERITED behaviour goes stale from an edit that is invisible in the file it describes
33. The ceiling an item prescribes is a HYPOTHESIS, and the blindness is usually in BOTH halves of the compared pair
34. The registry guards the ROW, never the row's PROSE — so a gate that grows a new axis drifts from its own entry with CI green
35. A HALF-FIX is worse than none, because it splits the surface into halves that DISAGREE — and the healthy half then takes the blame
36. A One-Home invariant declared in canon PROSE has no gate behind it — and its ARCHIVE ROW is what makes it read as enforced. ✅ Closed 2026-08-07 by a DECLARATION REGISTRY, not by the forbidden-form grep this item first prescribed: that same form is CORRECT on a `status`-scan, so the obvious gate would have broken money-recovery
37. It polls a HETEROGENEOUS set with a homogeneous question — and the member that differs is the one whose failure matters most
38. A doc genre that describes the framework's CAPABILITY reads as describing OUR CONFIGURATION — and the absence of that configuration has nothing to go red on. Worse, the "proof from the build" can be the build echoing our own PROSE back at us
39. When you NARROW a rule, the mirrors to sweep are the statements of its EXCEPTION — and they contain none of the rule's vocabulary, so no grep aimed at the rule finds them
40. Before a MASS campaign, baseline EVERY gate in the repo and rehearse on a throwaway clone — the expensive findings come from gates you were not thinking about
41. A checklist, runbook, RFQ, pitch or locale file is CODE WITH NO COMPILER — nothing parses it, so its first execution is its first test, and that happens on deploy day or on a vendor's floor
42. A mutation that fails to remove the mechanism makes a LIVE case look VACUOUS — and the wrong conclusion, delete the case, is the one that reads as rigour
43. A gate with TWO STANCES — a full sweep and a hook at the moment of the write — diverges between them silently, and the PARITY detector built against that divergence inherits the hole through its own declared EXEMPTION: an exemption is a blind zone shaped exactly like the obligation it delegates
44. Two stances can be in perfect PARITY and both still be blind, because parity compares WHICH checks run and never what each check RANGES OVER — a subject narrowed at birth is invisible to a parity detector by construction
45. Mutating a COPY of the gate proves nothing — the copy can fail for reasons that have nothing to do with your mutation, and it fails in the colour you were hoping for
46. Deciding WHAT a gate pins is a separate act from building it — and the cheap default (pin the literal you happen to see) quietly widens the gate onto a second axis, where the fix costs far more than the defect
47. A guard that asks whether its TOOL is PRESENT, not whether it is FIT, converts every check behind it into a silent no-op — and the gate then prints its own default as a verdict
48. A gate that resolves EXISTENCE against the filesystem answers a question about the MACHINE, not about the code — and it fails in the direction that ships: green on the author's laptop, red in CI, identical tree
49. A gate over PROSE must anchor on the INVOCATION form, never on the referent's NAME — because naming a gate is legitimate teaching, and only calling it is a claim about your own verification
50. The reference-gate family grips a canon doc by an IDENTIFIER, and it validates that the identifier RESOLVES — never that it still denotes the same subject. So a restructure has two silent faces: renaming empties a gate's input, and re-using a freed number silently re-points every stale citation at the new occupant
51. A gate can be HARD, correct, unit-tested — and structurally unable to reach the place its class actually lives, because the same fact is WRITTEN in two forms and the gate's regex knows one
52. Mutation-verify a gate in BOTH directions — «it reds on the defect» is only half the proof, and the missing half is where an over-broad gate hides
53. A carve-out registry gates the PRESENCE of its `back:` condition, never its TRUTH — so an expired exemption looks identical to a live one, and the reader is the only check that exists
54. A guard installed in a BOOTSTRAP file covers only the processes that LOAD that file — and the colliding party is usually the one that loads a different one
55. Before building a gate, look for the record that this class was ALREADY measured and the gate ALREADY refused — and look for it in the ARTEFACT's header, because that is where such a verdict tends to live
57. A gate over DECLARATIONS makes the whole class look covered — while the oldest member is usually the one whose behaviour nothing has ever tested
56. Deleting a REDUNDANT test is not the same act as deleting a dead branch, and it needs THREE independent measurements plus a fourth pass nobody's brief asks for
58. A boot guard is usually blind to the very placeholder that exists to make it fail loudly — because `REQUIRED_SECRET_NOT_SET` is neither blank nor the sentinel, and a presence-shaped predicate reads it as a real value
59. A shrink-list exemption has TWO ways to die, and the obvious check catches only one — the other leaves an expired exemption actively PROTECTING the regression it was meant to track
61. Чи є ПОРОЖНЯ МНОЖИНА для гейта провалом чи метою — вирішує ФОРМУ доказу його живості, і переплутати їх означає або вічнозелену декорацію, або гейт, що забороняє власний успіх
62. Пиши гейт ПЕРШИМ і прожени його ЧЕРВОНИМ по всьому периметру — тоді перехід у зелене доводить РОБОТА, а не твоя правка гейта
63. «Прибрано/гейтовано на користь X» вимагає доказу, що X ПРАЦЮЄ — виміряного живим трактом, а не запланованого; найдорожча форма — зняти РОБОЧИЙ механізм тим самим комітом, на слово про наступника
64. Зрізавши щось, НЕ пояснюй його відсутність — переказ власного зрізу сам є дрейфовою поверхнею, і він народжується десятками за одну кампанію
65. A mutation that PASSES is ambiguous, and the reflex reading is the wrong one: before concluding "the pin doesn't discriminate", check that the thing you mutated is even IN the set the pin judges
66. A runtime probe can be structurally incapable of seeing the class it was built for — and its zero reads exactly like a clean tree
67. A gate that pins two of OUR OWN homes to each other proves AGREEMENT, never correctness — and it is structurally blind to both sides being wrong the same way
68. A declared ceiling can encode an UNVERIFIED PREMISE about the environment — and because a ceiling reads as rigor, nobody ever re-measures it
69. A locally-generated artifact can SHADOW the file under test, so the lane grades a snapshot instead of the tree — and unlike the loud form, this one is green
70. A class closed by MIGRATION is closed for the FILES someone edited, never for the SURFACE — the CARRIER's perimeter is a separate measurement from the FIX's
71. A registry entry can name a SUBJECT THAT DOES NOT EXIST — and every field-shaped check passes, because they interrogate the entry, never the tree
72. A mechanism's live effect can be INVISIBLE in the counter you would naturally read — so «nothing changed» is a statement about your metric, not about the mechanism
73. A detector that needs N≥2 samples to fire is disarmed by a fixture holding one — and the canon rule against that had ALREADY been written, three days before it relapsed twice
74. A registry gate enforces PARITY, never LEGALITY — so it will faithfully cement a rule VIOLATION into canon and keep it there
75. A gate that discriminates by FORM knows the spellings its author happened to use — and the population may write the same thing another way, so its zero is a statement about the author's vocabulary
76. REJECTED VOCABULARY is its own guard shape — and the thing that makes it necessary is that the term is ABSENT from the tree, not present in it
77. A gate aimed at a SHARED HOME is blind to the population that can SHADOW it — and the pair «green gate + per-object tombstone» is the exact combination under which a defect survives its own extinction notice
78. A pin on a TRANSFORM is vacuous whenever the input you happened to choose makes the transform IDENTITY — and the pin still reads as a pin
79. A mutation that reds MORE examples than you aimed at is not automatically over-broad — the extra one may be a SECOND WITNESS of your own axis, and the reflex reading («collision, narrow the mutation») destroys evidence
80. A gate can DOCUMENT the very event it exists to catch — thoroughly, in its own header — and never pin it; and the thoroughness is exactly what hides the hole
81. An item that asks for a GATE is often describing a SYMPTOM — ask what happens if you remove the CAUSE instead, because a gate over a workaround CEMENTS the workaround
82. A detector measures a LEVEL; the decay it reports is an EVENT — and shipping the level-detector feels like closing the class, which is exactly how the event stays unguarded
83. A ref-resolver that requires the section marker is blind to the WHOLE-DOC reference — and the corpus's own ref standard canonises exactly that invisible shape
84. Every gate here validates a CLAIM; the whole class of defects that lives in the RELATION between two claims is invisible to all of them at once — and both claims are TRUE, so no amount of hardening any single check will reach it
85. Before deciding WHERE a document belongs, measure what it IS — split its bytes into HOW ⊥ WHAT ⊥ WHY, because the section headings will tell you the opposite
86. «Operational HOW at a canon address» is NOT decided by the SHAPE of the text — a numbered checklist looks like HOW and usually is not one. The discriminator is COUPLING TO LOCAL STATE: count how many sibling `§` of its OWN doc the section cites
87. A mass rename breaks RANGES and HISTORICAL STATEMENTS, not refs — and neither is visible to any ref gate, because both stay syntactically valid
88. An exemption justified by the word «forever» is a time bomb whose fuse is the next free-slot occupation — and the thing that defuses it is a lantern, never the promise
89. The same detector pointed at two surfaces can measure OPPOSITE things — so «this gate works over there» is not evidence that it should be extended here
90. When the candidate class is SMALL, you can measure a gate's precision EXHAUSTIVELY before writing a line of it — and twice in two days that killed the gate for under an hour of work
91. Read a gate's DECLARED CEILING before you diagnose its false positives — the answer is often already in its own header, and re-deriving it by measurement costs real passes
92. A gate can be ENABLED, correct and green while its INPUT FILE does not exist in this project — and that zero measures the instrument, not the tree
93. A tool disabled BY ITS OWN VENDOR carries a PREMISE about your framework — and the premise is a claim, not a fact, so it ages exactly like a declared ceiling
94. A gate keyed on a FORM is blind exactly where the form goes DYNAMIC — and that is where the dangerous writer lives, so its zero is an argument AGAINST building it
95. A DERIVATION written as prose in ONE canon line has nothing to go red with — so it survives every change to its own inputs, and the fix is not a constancy-gate on the number but a MODEL that recomputes the chain
96. A mutation that lands inside a `rescue StandardError` proves NOTHING — and the pin it "verified" can be measuring an empty set
97. Ask what SHAPE your pin engine can extract before believing a canon mirror is gated — ours reads `NAME = value`, so every mirror that is not a constant assignment sits outside every gate BY CONSTRUCTION, and the tell is a doc that CERTIFIES ITSELF
98. Порахуй, скільки гейтів ЧИТАЮТЬ артефакт і скільки його ВИКОНУЮТЬ — бо на файлі, який ніхто не завантажує, зелена може бути вся батарея
99. Придушення, ключоване на ФОРМІ артефакта, а не на його ПРЕДМЕТІ, має термін придатності, якого не видно нікому — і спливає він у CI, на комміті, що нічого не зламав
100. Гейт, який на цьому комміті не БІГ, невидимий для перевірки, зробленої «по цьому комміті» — і червоне лишається на `main` рівно стільки, скільки ніхто не торкається його path-фільтра
101. Пін може атестувати конфігурацію, якої твій продакшн-шлях не виробляє НІКОЛИ — і тоді «ця властивість запінена» правдиве про дерево й хибне про світ
102. Виняток, обґрунтований ПО-ЧЛЕННО, а застосований ПО-КОНТЕЙНЕРНО, вимикає гейт на всьому, чого його підстава не торкається
103. Тригер, названий у ПРОЗІ ноги, для парсера не існує — і саме це, а не гейт, робить лічбу доступної роботи завищеною
104. Носій може ІСНУВАТИ, СПРАЦЮВАТИ — і все одно не дійти, бо його ключ дедупу є СЕСІЯ, а охороняє він МОМЕНТ
105. Пін буває вакуумним не через свій вираз, а через ФОРМУ ДИСПАТЧУ, яку ти обрав для прикладу: рядок, що він читає, у цьому світі не створюється ВЗАГАЛІ
106. Завести гейт означає ще й УВІМКНУТИ СКАНЕРИ на теку, якої вони доти не бачили — «додали компілятор» описує НАМІР, а не blast-radius
107. ФОРМ-ДРЕЙФ РОЗЗБРОЮЄ СУСІДНІЙ ГЕЙТ — і роззброєння тихіше за будь-який хибний негатив, бо гейт лишається зеленим і НА ВСЬОМУ пункті одразу
108. Коли споживач інструмента — ШУКАЧ РОБОТИ, дві його помилки мають ПРОТИЛЕЖНУ видимість, тож симетричне «підвищмо точність» тут шкідливе
109. Гейт може не ПРОПУСТИТИ дефект, а СКОНСТРУЮВАТИ його — і тоді він звинувачує корпус у тому, що склав сам
110. Дірку створюють ДВА окремо ПРАВИЛЬНІ периметри — і саме тому ревʼю кожного з них дірки не бачить
111. ЗГЕНЕРОВАНЕ дзеркало здається безпечним, бо розбіжність у ньому «структурно неможлива» — неможлива саме РОЗБІЖНІСТЬ, а не втрата при ВИДОБУВАННІ, і втрачений носій виглядає точно як здоровий рядок
112. Фікс, відвантажений БЕЗ СВІДКА, невидимий КОЖНОМУ приладу — а ловить його, коли ловить, ГРУПОВА підлога покриття, тобто збоку й випадково
113. A mutation-proof is a claim about the SUBJECT it ran against, not a property of the gate's name — so retargeting the gate and keeping the marker turns the proof into a lie about the new subject
114. A linter suppression keyed by ID+location has no expiry when the condition that justified it gets fixed — so a fix that removes the CAUSE but not the SUPPRESSION converts itself into a silencer for the next regression of the exact same defect
115. Задокументована РЕГЕНЕРАЦІЯ буває деструктором, а не синхронізатором — і жоден гейт цього не бачить, бо всі вони судять ІМЕНА й ТИПИ, ніколи ПРОЗУ
116. Path-фільтр названо за ОДНИМ концерном, а джоба несе БІЛЬШЕ (виміряно: `ruby` гейтить ПʼЯТЬ) — тож питання не «чи фільтр логічний за іменем», а «чи він покриває входи КОЖНОГО кроку джоби»
117. Конфіг, який споживає ЗОВНІШНІЙ інструмент, треба судити ЙОГО парсером — бо всі наші гейти читають такий файл ЯК ТЕКСТ, і бездоганний текст буває відкинутим єдиним споживачем, що має значення
118. Класифікація СТАНУ роботи робиться один раз і не перечитується ніколи — тож вона протухає ДВОМА протилежними способами, і обидва читаються як добросовісний облік
119. Трансформація всередині гейта, чий ЄДИНИЙ свідок — живий корпус, не перевірена рівно там, де корпус мовчить — і гейт при цьому впевнено друкує число субʼєктів
120. Файловий `match` на файлі, що оголошує КІЛЬКА ресурсів, не є твердженням про покриття — його задовольняє найменш важливий із них
120a. І друга половина, тонша за першу: у багатоекземплярному файлі ЦІЛЬ мутації вирішує, що саме доведено
121. Скрабер, що глушить хибні позитиви, робить гейт сліпим рівно на НАЙПЕРЕКОНЛИВІШІЙ формі свідчення — процитованому виводі інструмента
122. Гейт, що виправдовує свій виняток СУСІДНІМ гейтом, мусить називати, ЩО САМЕ той асертить сьогодні — інакше пара відсилань утворює діру, якої не видно з жодного боку окремо
123. Канон-реф пункту гейт РЕЗОЛВИТЬ, але не ЦІЛИТЬ — і це друга й третя виміряні інстанції однієї сліпоти
124. Інвентар по ОДНІЙ формі авторства систематично бреше — перелічуй ФОРМИ, якими на річ посилаються, а не входження однієї; і розрізняй те, що ВИКОНУЄТЬСЯ, від того, що ОПИСУЄ
125. Прилад, збудований ДО присуду про його червоні, народжується вічно червоним — і його перестають читати
126. Три оголошені стелі трьох гейтів, виміряні одним проходом — і всі три лежать поза `docs/`-периметром або поза формою, яку гейт читає
127. Пін-спека точного складу множини робить розширення множини вимірним ДО присуду — і саме тому після присуду її вимір треба знімати разом із ним
128. Bench-вердикт без `[bench:slug]` невидимий bench-day грепу, а реєстр сесій називає рівно ОДНОГО власника слага — другий, нетегований дім не є домом
129. Гейт, опущений до фазової ПІДЛОГИ, потребує явного residual-повернення — інакше підлога мовчки стає планкою
130. Вітки одного гейта доглянуті НЕРІВНО, і найгірше доглянута та, під якою людина стоїть ЗАБЛОКОВАНОЮ
131. Колонка «Статус» судить НАШ артефакт, а читається як твердження про ЧУЖИЙ — і жоден гейт цієї підміни не бачить, бо обидва прочитання внутрішньо правдиві
132. Перш ніж будувати детектор ре-декларації — спитай, чому в одному модулі його клас не завівся, і ти дістанеш ЛІК дешевший за гейт: дім, ПРИБИТИЙ ДО КОДУ, не мігрує в сусідній файл
133. Фікстура, що будує стан, НЕДОСЯЖНИЙ у проді, пінить ПРОКСІ — і саме тому переживає зміну, яка той проксі знецінила
134. СЮЇТА ВМІЄ ПРОТИВИТИСЬ ФІКСУ: приклад, що пінить НЕ ТОЙ бік, цементує дефект — і впізнати його можна ДО фікса, бо він зазвичай уже стоїть на твоєму дискримінаторі
135. ВЛАСТИВІСТЬ-КОНʼЮНКЦІЯ мусить пінитись ОДНИМ прикладом: розділивши її надвоє, дістаєш два зелені приклади при зламаній властивості
136. ACTIVATION-ГЕЙТ, побудований на `.presence`, стверджує ГОТОВНІСТЬ, якщо змінна має ДЕФОЛТ — тобто предикат гірший за його відсутність
137. `200 OK` без ефекту — ТИХИЙ УСПІХ незастосованої зміни; і найдорожча форма класу та, де відповідь приладу СИЛЬНІША за його повноваження
138. Гейт, що пінить СТАТИСТИКУ КОРПУСУ замість властивості КОДУ, червоніє, коли корпус СТАЄ КРАЩИМ — і його червоне не є звітом про дефект
139. Перш ніж будувати носія, спитай, ЯКУ величину він міряє — і чи це та сама, що ти оцінюєш НА ОКО
140. `rescue`, поставлений не довкола того виклику, що кидає, — це МЕРТВИЙ код із виглядом обробленого випадку; і мій діагноз про нього теж був хибний, розсудила мутація
141. Передумова прикладу, що живе в успадкованому `before`, падає БЕЗ ЧЕРВОНОГО — і детектором тут виявляється ПІДЛОГА ПОКРИТТЯ, а не сюїта
142. Перш ніж будувати гейт на «високоточній підмножині», зістав її з РЕАЛЬНИМИ відомими промахами — нуль улову на них є підставою ВІДМОВИТИ, хоч би якою привабливою була форма
143. Після зрізу перевіряють не СЛОВО, а ПІДСТАВУ — речення, що не містить зрізаного токена, є типовим випадком, а не винятком
144. Діагностичний зонд по ЖИВОМУ слоту є писачем у чужий потік алертів — і «я розібрався» не є підставою резолвити те, що не є шумом
145. КІЛЬЦЕ: два доми шлють один в одного ПРОТИЛЕЖНИМИ стрілками, обидва рефи зелені — і рішення не має дому взагалі
146. ВИПРАВЛЕННЯ В БІК БІДНОСТІ: реф перецілили СВІДОМО й дбайливо — у дім, що не несе нічого, — а підстава переносу сама хибна
147. МІТКА ШИРША ЗА НУМЕРОВАНУ СЕКЦІЮ: «реф не влучає» буває ХИБНИМ ПОЗИТИВОМ, і природний хід тут ламає корпус
148. ДЕТЕКТОР ЗБІГУ НА КЛАС СТРУКТУРНОГО ДУБЛЯ НЕ БУДУЄТЬСЯ — вони антикорельовані за побудовою
149. ПРАВКА ОДНОГО ЧИСЛА СТВОРЮЄ СУПЕРЕЧНІСТЬ ІЗ СУСІДНІМ ПІДСУМКОМ, ЩО З НЬОГО РАХУВАВСЯ — тобто сам фікс є джерелом свого ж класу
150. ГЕЙТ, ЩО ВИМАГАЄ ЗАПИСУ, І Є ТИСКОМ, ЯКИЙ ЦЕЙ ЗАПИС РОЗДУВАЄ — тож спинити ріст може лише він сам
151. ВИНЯТОК, СКОУПЛЕНИЙ МАШИНОЮ СТАНІВ ПО СТРУКТУРІ, скасовується зміною ФОРМИ документа, а не його змісту — і гейт починає червоніти на власних прикладах
152. МУТАЦІЯ НЕ ДІЙШЛА ДО БІНАРНИКА: зелена доводить, що BUILD не відстежує файл, який ти правив — і читається вона як «пін не дискримінує»
153. ПІДКАЗКА ГЕЙТА — НЕПІНОВАНЕ ДЗЕРКАЛО КАНОНУ, і вона протухає ПРОТИ того самого канону, який гейт стереже
154. ГЕЙТ, ЧИЯ ВЛАСНА ДОКУМЕНТАЦІЯ НАЗИВАЄ ЙОГО ЄДИНУ СПРАВЖНЮ ЦІЛЬ — І ЯКИЙ ПОРОЖНІЙ
155. ЗНАЧЕННЯ ПРАВДИВЕ, РЕФЕРЕНТ ЧУЖИЙ — і тоді зелені ВСІ форми гейта одночасно, включно з тією, що цілиться саме в цей клас
156. ДЕТЕКТОР, ЩО ЗАВЖДИ ЧЕРВОНИЙ, ДОРІВНЮЄ ВИМКНЕНОМУ — і його дві причини МАСКУЮТЬ ОДНА ОДНУ ЧЕРЕЗ EXIT-КОД
157. ГЕЙТ, ЩО ХОДИТЬ ПО ФАЙЛОВІЙ СИСТЕМІ РАЗОМ ЗАМІСТЬ `git ls-files`, БАЧИТЬ ЕФЕМЕРНУ КОПІЮ ДЕРЕВА ЯК ЧУЖЕ ТВЕРДЖЕННЯ — ОСОБЛИВО ТУ, ЩО ЇЇ ЗБУДУВАВ ВІН САМ
158. ГЕЙТ ОБІЦЯЄ У ВЛАСНІЙ ПРОЗІ ТЕ, ЧОГО НЕ МОЖНА ЗРОБИТИ — і обидві форми зелені назавжди, бо предметом є не код, а ПРИПИС
159. МУТАЦІЯ НЕ СІЛА В ФАЙЛ: інструмент підміни мовчки не влучив, і зелена читається як «жоден пін не дискримінує»
160. МНОЖИНА ПОРОЖНЯ НЕ ТОМУ, ЩО ДЕФЕКТУ НЕМА, А ТОМУ, ЩО СХЕМА НЕ ВМІЄ ЙОГО ВИСЛОВИТИ — і тоді носієм стає ОГОЛОШЕНА СТЕЛЯ наявного гейта, не новий пін і не рядок реєстру
161. ПОПУЛЯЦІЯ ПІШЛА З-ПІД ПІНА: гейта ніхто не торкався, змінився КОРПУС — і пін лишається зеленим, бо його предмета в дереві більше немає
162. ГЕЙТ СУДИТЬ ІНШЕ ВІДНОШЕННЯ, НІЖ ОБІЦЯЄ ЙОГО ВЛАСНЕ ПОВІДОМЛЕННЯ — і повідомлення є єдиним, що читає ревʼювер
163. МУТАЦІЙНИЙ ЦИКЛ ЗІЙШОВ У ОДНУ СЕКУНДУ — і `make` не перезібрав, тож кожен наступний вердикт партії читає ПОПЕРЕДНІЙ бінарник
164. ГЕЙТ, ЩО ОБМЕЖУЄ СВІЙ СКАН ЗАГОЛОВКОМ СЕКЦІЇ, ПАДАЄ ВІД ПЕРЕЙМЕНУВАННЯ — і червоніє з ПРАВИЛЬНИМ exit-кодом при НЕПРАВИЛЬНІЙ причині
165. ПІН, ЩО ПОРІВНЮЄ КОНСТАНТУ З ЛІТЕРАЛОМ, СЛІПИЙ ДО ЗРОСТАННЯ РОБОТИ, ЯКУ ТА КОНСТАНТА ПОКРИВАЄ — і саме ця форма стереже таймаути й TTL локів
166. ПІН НАД АРТЕФАКТОМ СЛІПИЙ ДО ТОГО, ЩО ЧИТАЧ РОЗУЧИВСЯ ЙОГО ЧИТАТИ — ключ лишається у файлі, а СЛОТ зникає зі схеми, і присутність-пін зелений
167. ЗАПЕРЕЧЕННЯ ІСНУВАННЯ стоїть не на прочитаному джерелі, а на НЕЗНАЙДЕНОМУ — і жоден гейт не питає, що ти відкривав
168. ПІН МІРЯЄ ЗОВНІШНЮ МЕЖУ, А ЛАМАЄТЬСЯ ВНУТРІШНЯ — обидві істинні, і зелена зовнішньої нічого не каже про вкладену
169. ПЕРЕВІРКА ПО ОГОЛОШЕНИХ ПОЛЯХ СЛІПА ДО ДВОХ НАЙГІРШИХ КЛАСІВ ОДРАЗУ — до УСПАДКОВАНИХ дефолтів і до ВИВЕДЕНИХ величин; і композитний артефакт є домом обох
170. ПІН, НАПИСАНИЙ ПІДТВЕРДИТИ ГІПОТЕЗУ, ЩО ВМОТИВУВАЛА РОБОТУ, ПРОХОДИТЬ — І ЧАСТО З ХИБНОЇ ПРИЧИНИ, бо грубе налаштування, при якому робота виглядає потрібною, є тим самим, що підробляє її результат
171. КЛЮЧ ТАКСОНОМІЇ ГРУБІШИЙ ЗА ПРЕДМЕТ — і тоді повна класифікація ТИХО промотує плейсхолдер у рішення
172. «ПІДСТАВИ НЕМАЄ» — ОКРЕМА ВІСЬ, А НЕ ЧЛЕН ТАКСОНОМІЇ; вкинута в неї як клас, вона зеленіє як чинне рішення
173. ГЕЙТ УСПАДКОВУЄ ПЕРИМЕТР ВІД РОДИНИ ФАЙЛІВ, ПРОТИ ЯКОЇ НАРОДИВСЯ — і клас, яким його обґрунтували, повертається В СУСІДНІЙ РОДИНІ, під тим самим канон-розділом
174. МАШИННА ПОЛОВИНА МАЄ МЕНШУ КАРДИНАЛЬНІСТЬ, НІЖ ТАБЛИЦЯ, ЯКУ МУСИТЬ ПІДТВЕРДЖУВАТИ — і тоді більшість рядків непідтверджувані ЗА ПОБУДОВОЮ, а лікує ІМЕНУВАННЯ артефакта, не логіка гейта
175. ПІН НА ЗНАК ЧИ НА ДЗЕРКАЛЬНУ ТОТОЖНІСТЬ ВАКУУМНИЙ ПРОТИ ПОМИЛКИ РАМКИ — пінити треба ФІЗИЧНИЙ НАСЛІДОК у рамці деталі, і в ростер мусить входити ЗБУДОВАНА деталь, не лише її маніфест
176. АРТЕФАКТ, ЩО САМ ОГОЛОШУЄ УМОВУ СВОЄЇ НЕПРАВДИВОСТІ, ПЕРЕЖИВАЄ ЇЇ СПРАЦЮВАННЯ — бо умови не читає НІЩО, і оголошення купує йому довіру замість перевірки
177. ГЕЙТ ЗВІРЯЄ ДВІ ПОЛОВИНИ, ЩО ОБИДВІ СТОЯТЬ НИЖЧЕ ЗА ТЕЧІЄЮ ВІД ТРЕТЬОГО — і коли рухається третє, пара лишається САМОУЗГОДЖЕНОЮ, тобто зеленою
178. ГЕЙТ ЧИТАЄ ПРЕДМЕТ КРІЗЬ КЕШ, ЧИЯ ІНВАЛІДАЦІЯ ГРУБША ЗА ПРАВКУ — і ритуал мутаційної перевірки є РІВНО тим сценарієм, що її підриває
179. ПІН СУДИТЬ ДРУГУ ЛАНКУ ЛАНЦЮГА, А ЧИТАЄТЬСЯ ЯК ПОКРИТТЯ ВСЬОГО — і що ГУСТІШЕ пінована друга ланка, то невидимішою стає сліпота першої
180. Гіпотези про мовчання ВЛАСНОГО гейта розділяє ПРОГІН гейта, а не читання його коду — і коштує це чотири команди
181. ГЕЙТ, ЧИЯ ЄДИНА ЗАЯВА ПРО ТЕ, ЩО ВІН ГЕЙТ, ЖИВЕ У ВЛАСНІЙ ШАПЦІ — невидимий ОБОМ напрямкам реєстр-звірки за побудовою

<!-- /GUARD-CRAFT-INDEX -->

## Design rules

- **Self-consistency, not hardcode** — derive interdependent numbers from one parameter.
- **Context-anchor, never a bare number** — the same value is legitimate against different owners (provenance-mix at meV).
- **Pin an invariant, not a growing counter.** "8 Lorenz constants" is mathematics; "9 economic ones" grows, so the gate flags honest additions and gets switched off. 🔴 **The mirror case bites harder, because the gate then punishes an IMPROVEMENT** (SEC.25, 2026-07-28): a `producers.size >= 12` liveness canary went red the moment a duplicated broadcast was extracted into one method — 12 calls became 11, and the gate reported "extractor blinded" about a pure dedup. Lowering the number just re-arms the trap. The stable form for "is the extractor still looking at the right tree" is **coverage of a curated FILE set**: immune to how many calls live inside each file, still a tripwire in both directions, and it names what to do when a file legitimately leaves (remove the row in the same commit). General rule: a canary must count something the work is not allowed to change, and *call sites* are exactly what refactoring changes.
- **Two sets with an element MIGRATING between them → compare each separately, never their union** (GOV.2: a migration leaves the union unchanged, so a union-check is blind exactly on its own class).
- **A pin is one-directional** — `canonical_block_drift` hashes only `source:`; `mirrors:` is prose, so editing a mirror does not move the gate. Ceiling recorded in `00_06 §3`.
- **The gate form prescribed inside a tracker item is itself revisable** — do not implement a bad shape because an item named it.
- 🔴 **Before building anything, ask whether the discriminator has a FORM — and whether your tool's level of STATE can grip it.** Measured over seven attempts in one day (2026-08-08): what carries is structure a machine can see — a path resolves or it does not, a link resolves or it does not, a commit happened or it did not, a string was emitted or it was not. What does *not* carry is judgement about MEANING: «is this citing history or calling me to act» scored 2.4 % over 41 candidates; «is this number about a live set» was unusable in a corpus whose content IS its cross-references, so digits and slashes are signal and noise at once. **Two operational corollaries.** (a) *«Unmeasurable» usually means «measured at the wrong granularity»* — the same zsh class scored ~2–3 % wide and **90.5 %** narrow, because the narrow shape put the discriminator in the text (a quoted multi-word loop list) instead of in the runtime. Before burying a rule in prose forever, look for a sub-shape whose tell is statically visible. (b) *Failing the second axis is not «uncarriable», it is «wrong tool tier»* — that same 90.5 % rule still cannot ship as `grep`, because «is this `$v` inside a quote opened earlier» needs parser state; stateless matching scored 33.9 % and would have nagged on correct code. Name the tool's ceiling, or a rule with a carrier one tier up gets buried as having none. Full ledger of the seven → memory `feedback_rule_needs_a_carrier`.

## Hardening checklist

`tolerance = 1 display digit, NOT 0.5` · `encoding=utf-8` · `findall == 1` ambiguity guard · coverage gaps · **a guard's CI job must be import-free stdlib** (a bare runner without numpy breaks CI in a way the author never sees locally; lib-importing guards belong in the conda job) · **propagation twins** — pinning only `SUMMARY` leaves stale twins when the path-filter never fires for them.

## Odds and ends that earned their line

A guard does not pin its own reason for existing · a golden test that validates DEFAULTS cements an off-spec number · a curated map is a tripwire (a dead entry must go RED) · science surfaces need a real guard, not `stan_audit` (symbols vs numbers — prove ingestion) · an honesty-pass that comes back POSITIVE is a preventive guard · **a skill mirror rots more quietly than canon → sweep the skills in every closing pass** · the best sort of mutation-proof is **a gate that catches its own author** (`DOC-T.15` line-refs and the vertical-list linter both bit the person writing them).

