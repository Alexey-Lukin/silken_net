# Counter-Rules and Carriers

**What a self-applied failure taxonomy needs in order to fire — nine classes with membership
tests and bounds, a carrier thesis with a measured base rate, and three negative results about
measuring any of it.**

*Released as a defensive publication. No patent is or will be sought on any method described
here; this document is intended to constitute prior art.*

> **Author:** Oleksii Lukin (SilkenNet) · **Public repository:** `github.com/Alexey-Lukin/silken_net`
> **First published in the public repository:** 2026-08-08 · **Status:** submission-ready (arXiv cs.SE/cs.AI).
>
> **Venue note.** The IP posture that governs this file is defensive-publication-first
> ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)), and its canonical channel for the
> *inventive core* is Technical Disclosure Commons — a patent-blocking venue. This artifact is a
> **methods paper**, not an invention: nobody patents a taxonomy of reasoning failure, so
> anti-capture is not the function here. Its function is citation, and its entire prior art lives
> on arXiv — so arXiv is the primary channel and this repository is the timestamp. Same posture,
> different operation; conflating the two would publish correctly and be read by no one.
>
> **Review before this landed:** two independent adversarial passes — one per-example safety audit
> (which rejected the first draft outright: four illustrations pointed at defects still open) and one
> reconstruction audit (what a reader could rebuild from this document plus the public repository).
> Prior art was checked by an agent briefed to abandon the paper if the taxonomy proved a
> rediscovery; three of the nine classes are conceded as exactly that, in §1.

---

## Note on illustration: no example points at a live defect

**No worked example below is a defect report about a running system.** Each is constructed,
drawn from published literature, or generalised from an incident already closed in this
practice's public record — identifying particulars removed, mechanism and measured quantity
kept. This is a design decision, made for two reasons, and we state it up front because it
changes how the examples should be read.

The first reason is that the practice which produced this corpus operates a live system, and a
worked example drawn from a live system is a pointer to that system's open defects. Publication
is one-way — which is the subject of class **C9** below, and it would be incoherent to argue
that irreversibility raises the proof bar and then ship instances because they happened to be
the ones at hand.

The second reason is methodological, and it is the stronger one. **A synthetic example is
sharper than a real one for this purpose**, because it can be built to isolate exactly the
membership test and nothing else. Real instances always arrive with confounds — a defect that
belongs to three classes at once teaches none of them cleanly. Where the published literature
already carries a better-measured instance than anything we could offer (false success rates,
supplementary-fix rates, visible-versus-held-out test gaps), we cite theirs rather than
construct our own.

Where the third mode is used it buys concreteness at exactly the price the paragraph above
names: a generalised real incident arrives with the confounds it had, and the text does not
tell the reader which membership test it was chosen to isolate. We take that trade only where
the real mechanism is sharper than anything we could invent — a default that silently resolves
to a queue which happens to exist, a boolean field that cannot express *not measured* — and we
name the mode here rather than let *constructed* carry a load it was not built for. The safety
property is the one stated above and it is unconditional: the incident is closed before it is
written, so nothing in these pages is a pointer to an open defect.

What this costs the reader: the examples are not evidence. They are definitions in worked form.
The evidence in this document is confined to §3 (three negative results) and §4 (base rates),
both of which are measurements over the corpus itself rather than over any codebase, and both
of which are reported with their error bars and their instrument defects in §7.

---

## Abstract

We report what nine classes of automated-reasoner self-deception look like when each is
required to carry three things: a **one-line membership test** applicable mid-task, an explicit
**counter-rule** bounding its own over-application, and a **carrier** — a runnable check
standing at the moment of action rather than a rule stored in a document.

**Most of the taxonomy is not new, and we say which parts up front (§1).** Three of the nine
classes are rediscoveries of published work under other names; two are known
software-engineering classes restated for agents. This document is positioned in particular
against Wu's *When Errors Become Narratives* (arXiv:2606.14589), which derives a five-class
mechanism-oriented taxonomy of silent failures from 22 production incidents over eight weeks in
a single agent runtime operated by one human plus one AI collaborator — the same method shape
and the same one-human-plus-agent provenance as ours, published two months earlier. Our classes
C2, C3 and C8 overlap its classes C, D and E substantially.

**The findings we could not locate any precedent for are negative, and we lead with them (§3).**
A regular expression for the event *"a prescribed form survived"* returns **0 hits across 16,893
assistant blocks** of the corpus. A form that works executes silently; only failures generate
prose. Therefore **a statistic whose denominator event is never uttered cannot be anything other
than 100%** — and the corpus's own headline "15 of 15 prescribed forms fell" is a property of
the genre, not a measurement. The true rate, estimated against an independent denominator, is
roughly 5–8%.

This constrains every published claim of the form *"we catalogued N failure modes from our
agent's memory"*, including Wu's own ≥28-manifestation meta-pattern counter, and including
everything in this document. Two further negative results follow: a salience marker cannot be
retrospectively repurposed as a measurement instrument, and the instrument that read the corpus
was itself found defective mid-run.

Provenance is n=1: one engineer, one agent, one repository; 42 days of corpus and a 32-day
measured window. This is a field report, not a study. §8 states what would falsify it.

---

## 1. What is new here, and what is not

Stated first rather than in a late related-work section, because a reader who discovers the
overlaps on page nine is entitled to distrust everything before them.

| Class | Status | Closest published work |
|---|---|---|
| **C1** Perimeter of a class | **Rediscovery** | Supplementary-bug-fix literature: 22–33% of bugs require more than one fix; only 9–26% of supplementary patches resemble their initial patch by ≥5 lines; ~15% of supplementary change locations fall outside the original patch's direct neighbourhood |
| **C2** Self-attestation | **Rediscovery** | False-success taxonomy (arXiv:2606.09863): 9,876 + 1,879 trajectories, false success 3%–75.8% of failures by environment; Wu's *fail-plausible* class; the Entropy-Principle report (arXiv:2606.08162) that a failing component self-reports as operational |
| **C3** Mechanism ⟷ its trigger | **Mostly rediscovery** | Wu class E (declared state ≠ runtime state); the gray-failure and fail-slow literature. The *prospective* leg — no lever without a measured puller — is thinner |
| **C4** Measurement substitution | **Partially novel** | Goodhart, verification gaps, reward hacking (SpecBench, arXiv:2605.21384) measure the *consequence* far better than we can. The inward-turned half — *I* substitute my own measurement — is less covered |
| **C5** Verdict ≠ its grounds | **Novel; no precedent located** | Nearest neighbour is unfaithful chain-of-thought, a different layer: stated reasoning diverging from internal computation, not a correct action resting on a false premise recorded in durable artefacts |
| **C6** Computation as honesty engine | **Novel as a named class** | The direction-without-magnitude mechanism has no home we could find |
| **C7** One token, two domains | **Rediscovery** | Unit confusion; ErrorAtlas carries *Unit Conversion Error* among 17 top-level categories |
| **C8** Silent default | **Partially novel** | Implicit-default configuration bugs are known; "guard an emptiness → enumerate the real set and demand a declaration per member" is an operationalisation, not a discovery |
| **C9** Irreversibility sets the proof bar | **Novel as a taxonomy entry** | Reversibility appears as a safety desideratum, not as an operational proof-bar with a membership test, a default-branch rule and a timing rule |

**Method-level contributions, which is where we think the value is:**

1. **Per-class counter-rules.** We could find no failure taxonomy in this space that pairs each
   class with an explicit bound on its own over-application. Independent evidence that the
   problem is real and unsolved: work on checklist-based LLM evaluation reports that 50–81% of
   false positives come from flagging omissions that were, in fact, supplementary — precisely
   the failure a per-class bound exists to prevent.
2. **The carrier thesis with a measured base rate** (§6, §4).
3. **The three negative results about self-measurement** (§3).

**Positioning against Wu specifically.** The difference in unit of analysis is real but must be
argued rather than assumed. Wu classifies why an operated *system* fails without anyone
noticing; we classify why the *reasoner working on* a system concludes wrongly and feels
verified. Wu's unit is the production incident; ours is the epistemic move — the step at which a
false thing acquired the standing of a verified thing. This drives the one-line membership
tests: a test requiring a completed trajectory or a closed postmortem is useless to the agent
halfway through the work. But the overlap in C2/C3/C8 is substantial, Wu's *fail-plausible*
class is a genuine contribution we do not duplicate, and Wu's paper is the prior art a reader
should consult first.

---

## 2. What this is, and what it is not

**It is:** an operational vocabulary for the specific failure mode where an automated reasoner
produces a false belief *that feels verified*. Not hallucination — the reasoner has checked
something. The defect is in **what** was checked, **when** the checking word was recorded, or
**whether the check could have failed at all**.

**It is not:** a controlled study; a benchmark; a model-level claim; or a claim about
introspection in the mechanistic sense. We measured artefacts of a practice, not internals of a
network. Where these classes bear on published model-level findings — verbalised-confidence
overconfidence, task-specific metacognitive ability, metacognitive-self-report validity,
mechanistic introspection — they do so only as downstream engineering symptoms, and we make no
claims at that layer.

---

## 3. Three negative results about measuring any of this

These are the findings we consider most portable, because they apply to **any** self-reflective
agent memory system that reports statistics about its own failures — including this one.

### 3.1 The denominator that is never uttered

The corpus had accumulated a headline: *"15 of 15 prescribed forms fell."* A regular expression
for the complementary event — *a prescribed form **survived / held / worked***, across both
working languages of the corpus, stemmed before inflection — returns **0 hits across 16,893
assistant blocks.**

> **A form that works executes silently. Only failures generate prose. A statistic whose
> denominator event is never uttered cannot be anything other than 100%.**

Estimating the denominator from an independent source — closed work items in the same window —
puts the true fall rate at roughly **5–8%**, with a firm lower bound and an unknown upper one.

There is also a **sign correction** the raw count hides. Of 56 narrated falls, **20 were
explicitly caught before any code was written** and 2 after shipping. At minimum 20 of these
entries therefore record a design-review save, not a shipped defect — so the register
systematically reads as a catalogue of damage when a third of it is a catalogue of prevention.

The general form: **a self-documenting corpus is a biased instrument in a knowable direction,
and the bias is not noise — it is a hard 100% ceiling on every rate the corpus reports about
itself.** Any published claim of the form "we catalogued N failure modes from our agent's
memory" is subject to this and should either state its denominator or decline to state a rate.
This includes Wu's ≥28-manifestation counter for the silent-failure meta-pattern, which is
reported honestly as a shape rather than a rate — and which, on this analysis, could not have
been a rate.

### 3.2 The marker that measures nothing

The corpus marks significant findings with a glyph. An obvious downstream use is to count
glyphs per review type and thereby measure which kind of review is most productive.

Measured: the marker **does not distinguish adversarial review from ordinary reconnaissance at
all** — 22.6% versus 29.1%, with *ordinary* higher. Any claim about adversarial yield resting
on that counter measures nothing.

> **A marker adopted for salience cannot later be repurposed as a measurement instrument
> without validation**, because the property it was adopted to mark is not the property you now
> want to count.

This is class **C4** turned on the corpus's own bookkeeping.

### 3.3 The instrument that read the corpus was defective mid-run

During the measurement, the analysis found a bug in its **own** regular expression: a greedy
`\w*` preceding a lazy gap silently zeroes a match family in the engine used — 0 hits with it,
60 without. An isolated reproduction was recorded.

> *An instrument's silence reads as a fact about the world.* No error was raised. The family
> simply returned empty, and empty was about to be reported as "this never happens."

A second bias surfaced in the same sweep: reconnaissance conducted "by large files" undercounted
one class **threefold** — a claimed 13 carriers against roughly 36 — because more than half the
carriers were short clauses inside medium-sized files. **The reconnaissance strategy was itself
a member of the class it was counting.**

---

## 4. Base rates, with their error bars

Measured by a full pass — not a sample — over 226 sessions, ~132,000 events, **16,893 assistant
blocks**, spanning **32 days**. All figures are from that single sweep, performed by the same
agent whose behaviour they describe, using the instrument found defective in §3.3. They have not
been independently reproduced.

### Carrier firings versus self-relapses: ≈212 versus ≈29 — a raw ratio of about **7:1 in
favour of the rule**

Both families were precision-audited by reading 15 random hits each. The relapse family is
**40% precise** (the remainder are relapses of *systems* rather than of rules, and twice they
are cases where the record *prevented* a relapse). The firing family is **93% precise**.

Precision correction moves the ratio *up*, to roughly 16:1 — but **recall is unmeasured on both
sides**, so this is a ratio of two differently-biased counts and **not a rate**. Treat the
direction as informative and the magnitude as soft. If a single number is wanted, prefer the
split verdict below to the ratio.

**The substantive result is a split verdict on the practice's own prior.** The corpus had
asserted that "probability of relapse does not correlate with the quality of the record; it
correlates with the presence of a check at the boundary." The measurement shows the second half
is right and the first half is false *as a generalisation*:

- For rules that **have** a carrier, the base rate is the opposite of what the register
  suggests — they fire, and they catch the author.
- For rules **without** a carrier the original claim stands, and starkly: **one** explicit
  preventive firing in 32 days, flagged by its own author as the first of its genre.

> **Consequence for reading any such corpus: the density of failure entries measures not the
> author's unreliability but the fact that falls are narrated and firings are not.**

### Adversarial review: **30.2%** of claims directly overturned; **47.4%** overturned or
substantially corrected; **65 of 91** rounds returned mixed verdicts

The practice's description of adversarial review as "the most valuable agent in the cycle"
therefore rests on roughly **one in three**, not on nine in ten.

Rounds differ by **frame**, not by depth. A review aimed at a plan finds mute failure paths; at
a diff, API regressions and invented mechanisms; at the fixes, vacuous tests that the fix has
just de-energised; at the fixes-of-fixes, new unverified numbers and under-implemented claims of
one's own — because *nobody re-reads the prose of a correction*.

### Direction of self-corrections: ≈**49%** "raised a false alarm" versus ≈**51%** "missed
something real"

35 versus 37; precision 85% and 90% on 20+20 hand-adjudicated hits. The prior had been that the
practice was skewed toward over-caution. It is not. **The register is skewed**, because both
directions are recorded with the same marker or with none, and no marker family exists at all
for "withdrew my own false alarm."

---

## 5. Why membership tests and counter-rules, rather than descriptions

Two design constraints, both arrived at by repeated failure rather than from theory.

**A description does not fire; a test does.** A class stated as prose — "the agent may assert
completion prematurely" — never converted into a caught defect in this corpus. The same class
stated as a question with a yes-or-no answer — *"was the result-word written at the attempt or
at the confirmation?"* — did.

**A taxonomy without bounds becomes a false-positive engine.** Every one of the nine classes has
a degenerate reading that "fixes" deliberate design. *Every default is a disease* breaks
fail-safes. *Everything inert is dead code* disarms deliberate interlocks. *Unify everything
that shares a word* collapses concepts that were separated on purpose. We therefore treat the
counter-rule as **part of the class definition, not an appendix**.

Each class below gives: **membership test**, **synthetic illustration**, **counter-rule**, and
**prior art**.

---

## 6. The nine classes

### C1 — Perimeter of a class

> **Membership test:** *Have I named the real member-set of this fix — and is any member
> defended differently from its siblings?*

Every fix, gate, sweep, claim and campaign has a real member-set, and it is systematically
narrower than the declared one. The work is not done until the perimeter is named.

**Why asymmetry beats search.** When the defect is the **absence** of a line, "no code" does not
grep. A missing guard, a missing exclusion, a missing declaration — none of these can be found by
searching for themselves. They can only be found by comparing members of a class against each
other, which is why the operative detector is not a query but a **contrast**: locate the pattern
that *is* present across the class, then ask which member does not carry it.

**Measured instance, from the literature rather than from us.** This class has been quantified far
better than any single practice could manage, in work on incomplete fixes: **22–33% of bugs
require more than one fix**; only **9–26% of supplementary patches resemble their initial patch by
five or more lines** — so similarity detection against the original patch is insufficient by
construction; and **~15% of supplementary change locations fall outside the direct neighbourhood of
the original patch.** That last figure is the perimeter claim in externally measured form: for
roughly one incomplete fix in seven, the remaining member sits somewhere the author of the first
fix would not have thought to look.

**An abstract tell, cheap and often present.** A test file that constructs fixtures it never uses
is a planted-but-unwritten test. It does not say what is wrong, but it marks a place where somebody
once knew a check was needed and did not finish — and the unfinished half is a candidate member of
whatever class those fixtures belong to.

**Counter-rule.** Some asymmetries are deliberate, and the corpus gives no basis for stating
what fraction — so do not state one.
- *Lopsided defence can be correct ordering.* Hardening one link while another remains immature
  can be a deliberate sequencing decision rather than an oversight — though it remains an
  honesty gap for any external claim of uniform strength.
- *Adjacency is not membership.* Classifying candidate members by file was wrong in 4 of 4
  historical cases in this corpus. Membership is shared blocker, shared executor or shared
  build — not shared topic.
- *"Unreachable" is not "deliberately unbuilt."* A member not reachable today is either a mine
  on a safety catch or genuinely dead, and the difference is whether anybody decided.
- *The lens discriminates; it does not stamp.* The question is not "could a guard go here" but
  "has this class already bitten" — otherwise you are writing a guard with no customer.

**Prior art.** Substantially the supplementary-bug-fix literature. We claim only the
asymmetry-as-detector framing and the counter-rule set.

---

### C2 — Self-attestation

> **Membership test:** *Does a record assert the result — and was it written at the moment of
> the ATTEMPT rather than the CONFIRMATION?*

The mechanism is healthy and running. What breaks is the moment at which the result-word is
committed.

**Synthetic illustration.** A worker calls `transport.send(message)` and, on the following line,
writes `log.info("delivered")` — without inspecting the return value, and without waiting for an
acknowledgement. The transport may be perfectly functional. The defect is not in the transport;
it is that the word "delivered" was committed at the attempt. During any later investigation
that log line is evidence, and it is false evidence.

**A second carrier: the metric.** A counter named `widgets_shipped_total`, incremented at
enqueue time and never decremented on failure, answers the question "how many shipped" while
measuring "how many were attempted." The name states a result; the increment sits on an attempt;
nothing reconciles them.

**The quietest carrier: the health probe**, because it lies in the *negative* direction. Consider
a probe that reports a dependency "healthy" by opening a TCP connection to `127.0.0.1` on the
port that dependency conventionally uses. If the dependency speaks UDP, the probe measures the
wrong protocol. If it runs on another host, the probe measures the wrong machine. And if it is
simply not configured, the probe cannot say so — it can only say "unhealthy."

Three substitutions, **nested**, each surviving a fix of the previous one. The generalisable
questions: ask not "what is this measuring wrongly" but ***"how many layers stand between the
instrument and its subject"***; and note that **a boolean field cannot express "not measured"**
— the remedy is a distinct *state* (`not_configured` as separate from `unreachable`), not
another flag. The worst outcome of such a probe is not a false red; it is that it trains
operators to discount red on the exact panel they consult during an incident.

**From the literature.** False success — an agent asserting completion where the environment
state indicates failure — has been measured across 9,876 trajectories from 8 model families and
1,879 from 4 more, ranging from **3% to 75.8% of failures** depending on environment and
architecture. That variation is itself important: it is strong evidence that single-setting
rates for this class do not transfer.

**Boundary.** Routinely confused with **C3**. The difference is what the channel does at the
moment of failure: in C3 the channel is **silent** (the mechanism never fired, so it produced no
reading); here the channel **speaks**. A dead path carrying a "delivered" log must be read first
as C3 (revive the path) and only then as C2 (ground the word).

**Counter-rule.** *An intent marker written deliberately before the action is the cure, not the
disease.* Persisting a `pending` record **before** an irreversible external call is required —
otherwise a crash-and-retry performs the action twice. This is the same axis in the opposite
direction, and a rule of "never write before confirmation" would break it.

> **What distinguishes them is not the timing but the NAME of the state:** an intent
> (`pending`, `sent`) versus a result (`confirmed`, `delivered`). *An intent recorded early is
> insurance; a result recorded early is a lie.*

Two further bounds. An honestly unfinished feature — the interface exists, the backend does not
— asserts nothing about delivery, and treating it as self-attestation is a membership error. And
a line that names the **state of the channel** rather than the result — "channel not configured"
— is the correct wording, not a softened one; demanding silence from it would trade a lie for an
invisibility.

**Prior art.** Substantially published as *false success* and as Wu's *fail-plausible* class. We
claim the attempt-versus-confirmation membership test and the intent-versus-result counter-rule.

---

### C3 — Mechanism ⟷ its trigger

> **Membership test, prospective:** *Can I write a test that FAILS without this change? If not,
> do not build the lever — find the puller first.*
> **Membership test, retrospective:** not "is the gate green?" but ***"did it run?"***

A mechanism and the event that pulls it are two independent things, and each fails separately.

**Synthetic illustration (retrospective).** A branch-protection rule requires status check *X*.
*X*'s workflow carries a path filter. For any change touching no matching path, *X* never runs —
and a required check that never ran can resolve to success by default. Nobody defeated the
analyser; they prevented it from running.

> **A gate that did not run is not green.**

The same class one level deeper: a source file that is not in the build's compile set at all.
Every check over that build is green with respect to a file it has never seen. Ask not "does the
gate pass" but ***"is this file even in the set the gate can see?"***

**Synthetic illustration (prospective).** A threshold is measured — on a staging replica whose
input distribution differs from production. This is the quietest form of the class precisely
because a measurement *was* taken, so nobody asks a second time. The general shape: a threshold
is a lever, and a lever built without a *measured* puller is a number with a decimal point and
no evidence.

**From the literature.** SpecBench quantifies the same shape in its own terms: every frontier
agent saturates the visible test suite while the held-out suite continues to expose reward
hacking, and the gap grows by roughly 28 percentage points per tenfold increase in code size.
Green against the checks that ran is not validation.

**A mirror worth naming, because nobody looks for it.** Registers *under*-report as often as they
over-report: a document declares a capability "does not exist" while the foundation is already
in the code. The disease is identical — trusting the register instead of the path — but this
direction costs wasted work rather than a missed defect, which is why it is quieter. It also
corrupts the **form** of the remedy: a prescription to "extract X from Y" written against code
that does not exist is not cured by extraction at all.

> **Read the code before classifying anything as absent.**

**Counter-rule.** *Deliberate inertness is a named pattern, not a hole.* Landing correctness in
code while activation remains an owner's toggle — *wire-but-inert* — is the named pattern for
shipping a high-consequence path safely: zero live risk while shipping. But the same inertness
can equally be **a mine on a safety catch** rather than dead code. The difference is not the
state; it is whether anybody decided.

> **The test that separates them:** deliberate inertness carries a **named activation
> condition** and a **decision owner**. Forgotten inertness carries neither. Ask not "does it
> run" but ***"who turns it on, under what condition, and is that written down?"***

One further bound: *"left ready for X" is a claim, not a state.* It requires proof exactly as
much as "removed in favour of X" does. And a named activation condition justifies inertness
without preserving **content** — before reviving something declared ready, check it against
decisions taken after it was written, because it may carry a pattern the system has since
rejected.

**Prior art.** The retrospective leg overlaps Wu class E and the gray-failure literature. The
prospective leg is less covered.

---

### C4 — Measurement substitution

> **Membership test:** *Would a SOUND instrument, aimed at the same world, give a DIFFERENT
> reading?*

The reading is false **because of the instrument**, not because of the world — which is exactly
why it looks like a fact. The cost is asymmetric in a specific way: a fabricated "this is dead"
erases genuine debt, because it looks more urgent than the debt does; and a claim of
impossibility removes an option from consideration permanently.

**Synthetic illustration — verify the conclusion, not the premises.** An agent declares a
blocking defect: *"the mail queue has no listener."* Three premises are checked and all are
true: the queue name appears in no worker configuration; no application setting overrides it;
none of the launchers requests it. The **bridge** is false — the framework's default resolves the
delivery queue name to nil, which routes the job to a queue that *is* configured. The verdict
was measurable in a single runtime call, and that call was never made.

> *When a chain of premises leads to a loud verdict, ask whether the verdict itself can be
> measured — and measure that, not the links.*

**Synthetic illustration — absence is a property of the instrument.** "The realtime layer is
unreachable" rests on four verified absences: no handler directory, no mount line in the route
file, no client-side dependency pin, no client connection code. All four true; the conclusion false,
because the framework's engine mounts its own endpoint from an initialisation hook and marks the
route internal, so the route-listing tool hides it *by design*. **Both ways of looking were
false-negative by construction.**

> *When a verdict rests on an ABSENCE, ask what instrument you looked with and what that
> instrument does not show by design — then go and find affirmative evidence.*

**Synthetic illustration — the probe measures your own harness.** A test harness drives a system
by polling it, then records the observed timings as facts about the system. If the system drains
its work at one rate and the harness polls at another, the recorded chronology is a property of
the harness. The verdict may still stand while the *mechanism* is invented — and the invented
mechanism is the part that gets written into permanent documentation.

> *A probe measures only what you did not set yourself. Before calling a result a measurement,
> write down which parameters of the loop you chose, and check each against its real source.*

**A fourth form, about confirmation rather than denial.** A search hit can "confirm" a mechanism
through **name collision**. Libraries routinely name an API after the mechanism it *replaces* —
the classic being a `listen` that is internally a polling `sleep`. Taken together with the three
above, this gives the complete pair: *absence of a trace is not absence of a mechanism, and
presence of a NAME is not presence of a mechanism.*

**Inward-turned half — the same class applied to one's own work**, where it costs most because
the error changes the **action**:

- *An invented justification carried with the confidence of a fact.* The most durable form is a
  comment explaining a constant: it has no gate, it closes the question for the next reader, and
  it outlives the code it explains.
- *Verify the CLOSING link first.* The longer the chain of verified links, the stronger the
  illusion of proof — and the closing link is almost always the cheapest, because it is on the
  surface. Once a chain takes the form "therefore the defect is live," ask **"what single check
  would cancel all of this?"** and do that one first.
- *N supports that converge may answer the wrong question.* Here every indicator is correct and
  the **question** was substituted — so more supports make the error more convincing rather than
  more visible. After listing supports, ask what question each one answers. If they all answer
  the same one, you have not yet measured.
- *Replacing a working weak instrument with a broken one, and calling it an improvement.*
  A crude threshold check is removed in favour of a cross-check against a supposedly independent
  source — which is empty by construction, because both sides descend from the same ancestor and
  pass through the same filter. **"Independent source" is a claim, not a property:** write down
  the assumption both sides share, then break the shared component. If the check stays green,
  you have built a tautology. And when removing an old check, ask what it actually caught — the
  replacement may be strictly weaker.

**Counter-rule.** *Two honestly measured contradictory readings are not "one of them is false."*
They are a hidden variable that separates the cases — and that variable is the fact worth
keeping. Suppose two documents disagree about which status code a framework returns when content
negotiation fails, and both are marked "measured." The temptation is to pick a winner.
Reproducing both inputs may show each is right under a different condition, and **the separating
condition is the actual finding**. Cutting either side leaves a partial mechanism that looks
complete.

Separately, and cheaply: *"it has been sitting for ten days" is not "it is broken."* Cadence is
not a defect, and inferring one from the other is a narrative, not a measurement.

**Prior art.** The outward half is the metrology of Goodhart, verification gaps and reward
hacking, measured far better elsewhere. The inward half is thinner in the literature.

---

### C5 — Verdict ≠ its grounds

> **Membership test:** *Does the error change the ACTION? If yes → C4. If no — the action is
> right and the RECORD lies — it belongs here.*

A conclusion and the ground beneath it are two independent variables. **A correct action on a
false ground reddens nothing**: tests green, gates green, behaviour correct — and the untruth
settles exactly where no detector exists, in the commit message, the work-item body, the "why"
of a design document.

**Why it is more expensive than a false verdict.** A false verdict is caught by tests, by gates,
by adversarial review, by the owner. A false ground is caught by nobody, and it becomes the
template for the next decision. The next reader will check the *state* against the code and will
**re-derive and believe** the ground. In this corpus the ground was overturned by an external
reviewer at least three times running, and by the author zero times.

**Synthetic illustration.** An agent records — in a work item, a design document, and six commit
messages — that a given code path "has no test at all." It has one: green for years, asserting
only an HTTP status code and nothing about content. The conclusion (an assertion on *content* is
needed) survives intact. The ground is false.

The corrected version turns out to be **sharper** than the original: both halves of a contract
were being exercised and nobody was comparing them, and the existing smoke test was manufacturing
an appearance of coverage. But the instructive part is *how such a thing gets caught* — in the
constructed case, by a style linter that was not looking for it, because the new test context had
been named identically to the existing one. That is: the ground was overturned by an instrument
with no interest in it, after it had already settled into three documents and six commit
messages.

> *A statement of the form "this does not exist" / "there is none anywhere" must be placed on
> AFFIRMATIVE evidence — list what IS there — because a negative is confirmed only by the
> completeness of your query, and you do not control that.*

**A costlier subtype: the ground that justifies what was NOT done.** A decision to write only
positive assertions is justified by "with a fail-closed default, a negative example is blind."
The statement is true — for exactly one mutation — and is read as a licence to write no negative
at all. A different mutation then restores the original defect completely while leaving every
positive assertion green. *A well-formed explanation stood exactly where the missing proof should
have been, and looked more convincing than the proof would have.* Mutation testing cannot catch
this, because there is nothing to mutate.

> **Reflex: when a ground explains why something need NOT be done, ask which scenario it covers,
> and whether that is one of many.** "X is blind" almost always means "X is blind to Y," not "X
> is useless."

**Counter-rule — and this is the one place the corpus recorded a rule *holding* rather than
failing.** An item was deliberately recorded **without** a diagnosis, annotated to the effect
that the ground was undetermined and that an item with a false ground is worse than no item. A
plausible hypothesis was sitting right beside it, unwritten. A day later a deterministic
measurement showed the hypothesis was not needed at all — the real mechanism was simpler, and
worse. **Recording "ground undetermined" cost nothing and saved the item from a ground that would
later have had to be refuted.**

> *An item with no stated ground is better than one with a manufactured ground. Do not invent a
> ground in order to complete a form.*

A second half, costlier: the same item also prescribed a **form of measurement**, and that form
was wrong — the prescribed experiment would have returned green and "proved" the absence of a
defect that was real. *Review a prescribed measurement as sceptically as a prescribed fix. A
measurement that cannot discriminate is worse than no measurement, because it comes back
carrying a verdict.*

**Prior art.** We found none. The nearest neighbour, unfaithful chain-of-thought, is a different
layer.

---

### C6 — Computation as honesty engine (the instrument is sound; the prose lies)

> **Membership test:** *Would a sound instrument give the SAME reading? If yes — the instrument
> was right and the PROSE is wrong — it belongs here.*

Specification prose carries systematic aspiration drift: statements written without grounding
that *sound* right and remain internally self-consistent, so document-versus-document review
never catches them. Only forcing the specification through a deterministic computation exposes
it. Any deterministic computation over a specification is a **grounding pass** on the prose that
specification is written in — and it is the only kind of review that can catch a document which
agrees with itself and is uniformly wrong.

**Worked illustration — a rule stated as a DIRECTION with no MAGNITUDE.** A documented rule
states that a test-coverage ratchet "punishes deletion of covered code too." The **sign** is
correct and provable: removing covered lines lowers the ratio if the removed lines were covered
at above the current rate. The **magnitude** is never computed. For coverage *p*, the penalty for
deleting covered code scales as roughly 1/(1−p) relative to the penalty for adding an uncovered
branch — at *p* ≈ 0.98 that is a factor of about **50 in the other direction**.

Because no number sat beside the claim, the next reader converts it into "this deletion will
redden the build" and parks a legitimate cleanup on a constraint that does not exist. A second
document then cites the first, so the false coupling becomes self-confirming and **every gate
stays green: all links resolve; only the clause lies.** Every word of the original sentence was
true, which is why this is the hardest form of prose drift to catch.

> *When writing a rule about a cost, a penalty, a risk or a limit, compute ONE number for it in
> the same sentence.* "True but negligible" and "true and binding" are different rules, and prose
> alone cannot distinguish them. On the reading side, before letting a documented sentence block
> work: **"what is the magnitude, and did anyone measure it?"**

**Counter-rule — the empty catch must be recorded.** An adversarial review that finds nothing is
worth as much as one that finds something, and must be **written down**: naming what it attacked
and failed to break defines a proven perimeter. Without that line the next pass re-checks the
same ground, and what was verified reads as unverified — **zero findings silently converts into
zero information.**

But record **what** withstood and **against what**. "No findings, therefore clean" is a verdict,
not a measurement, and it belongs to C4.

Two further bounds: *report honest negatives and borderline results; never canonise a favourable
artefact as a result.* And *reject motivated-reasoning fixes* that chase a better number — re-running
an analysis with different settings until a margin clears, applying a model outside its validity
domain, specifying a tolerance the process cannot hold. The honest result stands.

**Prior art.** The general problem is documentation drift, well known. We found no taxonomy entry
for direction-without-magnitude as a distinct blocking mechanism, nor for the
empty-catch-must-be-recorded rule.

---

### C7 — One token, two domains

> **Membership test:** *Are there TWO sides reading ONE token, each correct in its own coordinate
> system?*

A token — a number, a name, a key, an identifier, a path — does not carry its own coordinate
system. Two sides of a system can therefore read it differently and **neither is lying**. The
instrument is sound, the world unchanged, the reading true; what is false is the silent
assumption that the scale is shared.

**Why the gate is blind by construction.** A shared lookup keyed only by the *value* silently
merges domains that happen to share a word. The collision is invisible until two owners disagree
about meaning — and then it is invisible again to every parity check, **because both sides are
"present."** Nothing is absent, nothing is broken, both sides resolve. This is why the class
survives gates written specifically against it.

**Synthetic illustration (numeric).** A status page shows "fraction of units in a degraded
state." Three degrees of freedom hide inside that one number:
- the **threshold** at which the display changes;
- the **unit of count** — if the numerator counts *rows* while two rows per unit are legitimate,
  it double-counts;
- the **denominator's population** — if the denominator counts *all* units while the numerator is
  drawn from *active* ones, then retired units dilute the figure indefinitely.

Each component is individually correct. The composite answers a question nobody asked.

> **The rule extracted from choosing between candidate repairs matters more than the winning
> formula: align the SIZE to the TRIGGER, not the reverse.** The trigger decides whether the
> event occurs at all, so the trigger defines the population — and anything outside it needs its
> own explicit treatment rather than silent inclusion.

**Synthetic illustration (name).** A table stores a measurement in one column and **the unit of
that measurement in a sibling column of the same row**: `value = 500, unit = "mg"` in one row,
`value = 500, unit = "mL"` in the next. A display path renders the value and hardcodes the unit
string. Every row now reads correctly for whichever unit the author had in mind and incorrectly for
all the others — and nothing fires: the value is present, the unit column is present, both resolve,
and the two sides never meet.

This shape is chosen deliberately because it admits **no legitimate hardcode**. Where the unit is
named per row, a constant unit in the display is wrong by construction. Contrast a field that is
single-valued by construction, where the identical literal *is* correct and a global replacement
would break working code: telling those two cases apart is precisely the counter-rule's job, and an
illustration that cannot be distinguished from its own false positive teaches neither the class nor
the bound.

Two further properties are worth having separately:
1. **The class is kept quietest by the CORRECT half beside it.** If a neighbouring module reads the
   unit column properly, the eye is reassured by the code that happens to be right.
2. **An invariant's upper home can lie outside the language entirely** — a schema, an interface
   definition, a declaration in another toolchain — so parity must be *derived from that source*
   rather than hand-written, or the hand-written copy simply becomes a third domain for the same
   token.

**Synthetic illustration (addressing).** The same `#N` notation used both for an item number and
for a line number. The insidious property is that a line-number reference **is correct on the day
it is written**, so nothing looks broken; the first edit above it shifts the reference silently. A
third form is worse still: an address pointing *inside its own file* at a section that never
carried the rule. No link checker examines it — it is not a link — and the act of citing creates
the impression that the rule is homed elsewhere, so it never gets written where it is needed.

> *Ask not "does the address resolve" but "does the TARGET carry what I am attributing to it" —
> and ask it first when the target is in the same file.*

**Counter-rule.** *Divergence is often deliberate.*
- Two thresholds can be two concepts — 0.9 for one consumer and 0.8 for another, documented as
  different things — and unifying them breaks a design.
- Two representations of one quantity can be deliberately different types: a monetary value in
  arbitrary-precision decimal and a numerical simulation state in IEEE-754 double, because
  bit-exact reproduction of a reference implementation is required. Identical types would be the
  bug.
- An external label can be deliberately distinct from an internal one.
- A guard against a near-identical literal must explicitly exclude its legitimate neighbour, or
  the gate itself becomes the source of false positives.

> **The test that separates them:** deliberate divergence has a **named concept on both sides**
> and a reason to differ. Accidental divergence has only a shared word and an assumption of
> shared meaning.

*The best cure is structural, not vigilance.* Where two scales can be made unrepresentable in a
single type, do that instead of adopting a convention. And translate **at the boundary, where
both scales are still visible** — never in a final consumer that knows only one of them.

**Prior art.** Unit confusion is textbook, and ErrorAtlas carries *Unit Conversion Error* among
its 17 categories. Our contribution is the gate-blindness argument and the counter-rule test.

---

### C8 — Silent default

> **Membership test:** *Who decided — the owner, or the filler-of-the-unspecified? If the answer
> is "nobody decided; it just came out that way" → here.*

Where a value is not set, the decision is made by `= "…"`. A default is always somebody's verdict;
the only question is whether anybody made it consciously.

**Why this class is unique among the nine: you are guarding an emptiness.** The defect is the
**absence of a line**, and "no code" does not grep. Neither search nor an ordinary gate can see
it *by construction*.

**The strongest statement of the symptom, which also explains the invisibility:**

> **A default that narrows is indistinguishable from a check that passes.**

**Synthetic illustration.** A test generator derives cases from a route table. For each entry it
reads `verbs || ["GET"]`. One entry's `verbs` field is unset — so two POST routes generate zero
test cases. Now delete a load-bearing group from the generator's own pattern: **the entire suite
stays green**, because the missing data resolves to a default that quietly produces nothing.
Nothing failed. Nothing could have.

**Present-but-empty is a separate animal, and worse than absence.** `ENV.fetch("X") { fallback }`
on a variable that is *present and empty* returns `""`, not the fallback — because the empty
string is a value, not an absence. An empty injected variable therefore silently overrides an
auto-derivation that would have been correct. *To preserve an auto-derivation, omit the variable
entirely; never inject an empty or placeholder value.*

**Someone else's default can make YOUR gate vacuous.** A translation-parity gate asserting "this
label exists in all four locales" is **green with three empty files**, if the framework's
existence check follows the fallback chain by default and fallbacks are enabled in every
environment. Disarming a foreign default inside your own gate is not a detail; it *is* the gate.

**The same class at the level of a check's own inputs.** An aggregate guard tests whether any
dependency reported `failure` or `cancelled`. Four results are possible; the two undeclared ones
resolve silently to "OK." For one of them that is correct. For the other it depends on the
member — and that question was never asked, because the set of members was **non-uniform**.

Note the remedy that the class's own detector dictates: not "add the missing value to the list,"
which would break the members for whom it is legitimate, but **split the set by who may
legitimately produce it.** Note also the counter-intuitive discriminator: the most natural
experiment produces a *different* result value, one the original guard *did* catch — so it would
have returned green and "proved" the absence of the defect.

**Counter-rule — a default is frequently the right answer.** Without this entry the class
degenerates into "every default is a disease," and deliberately designed fail-safes get "fixed"
toward risk.

An operational rule about **proportion**: *"nine of ten disabled" is not a verdict; it is a
reason to judge each of the ten on its merits.* Some may be disabled entirely correctly — a
static-analysis rule that fires on an intentional language-level safety construct is not a
defect, and the sweeping verdict sounds convincing precisely because it requires opening none of
the ten.

**The sharpest pair is the SAME default on both sides.** A translation fallback chain is a
**defect** inside a parity gate and **correct behaviour** in the catalogue itself: copying a
source-language string into another locale file is worse than leaving a gap, because the chain is
transparent and self-documenting while a copied string *pretends* to be a translation and nobody
will ever re-read it.

> **What distinguishes them is not the default but WHO reads the result:** a machine issuing a
> "covered" verdict → defect; a human seeing a transparent gap → correct.

**The one detector form that works.** There is no class-level gate and there cannot be, because
the subject is an emptiness. But six independent instance detectors in this corpus turned out to
be **one form**, invented independently at least three times:

> **Enumerate the REAL set and require a declaration for every member.**

A gate that iterates the actual state machine rather than a hand-written list; a schema-parity
rule requiring every new column to be classified; an environment guard requiring every deployed
variable to be either in the guard set or explicitly documented as exempt.

**Three questions asked at the moment of action:**
1. Who decided — the owner, or `= "…"`?
2. What happens if the key is absent — and can I distinguish that outcome from a successful
   check?
3. Whose default is this — ours, a library's, a vendor's, a toolchain's, or a legal system's?
   Because it must be verified **in its own home**, not in our configuration.

**Prior art.** Implicit-default configuration bugs are known. The "guard an emptiness" framing and
the single detector form are an operationalisation rather than a discovery.

---

### C9 — Irreversibility sets the proof bar

> **Membership test:** not *"how frightening is this?"* but ***"WHO holds a copy if I am
> wrong?"***

Irreversibility is not a property of risk; it is an **input parameter of the decision**. Once an
action cannot be rolled back it changes three things at once, and in this corpus all three were
re-decided from scratch every time they arose.

**(a) Which branch is DEFAULT — always the recoverable one.** An irreversible penalty versus a
recoverable hold: the wrong irreversible penalty cannot be undone, while the wrong hold costs one
review. So on indeterminate magnitude the default is the hold, not the maximum.

Crucially this is an **explicit trade with a named price**: deterrent power is paid for
false-positive safety. It is not a free lunch, and stating the price is what keeps the rule from
degenerating into timidity.

Note the mirror, without which the rule reads as "strict is safe": **fail-closed is not always
the safer side.** When the failure mode of a mitigation is itself irreversible for the honest
party, "stricter" is worse — and such a mitigation can carry **negative expected value**. Ask not
whether the mitigation works, but *what happens when it fires*.

**(b) How much proof — one axis for recoverable, N converged independent axes for irreversible.**
And when the first axis is structurally blind to the property that actually matters, make at
least one of the N deliberately **non-machine-checkable**. An automated build proves that
something compiles; it does not prove that it behaves, and for a one-way operation the difference
is the whole question.

There is a consequence for **artefact choice**, not only for checks: a machine-regenerated file
cannot satisfy a requirement of "committed and reviewed" *by construction*, while a hand-written
equivalent can — because review and commit apply to what is in version control, not to what a
generator will re-emit tomorrow.

A **claim of impossibility** belongs in this section, because it is an irreversible act performed
on somebody else's work: it removes an option from consideration permanently and settles as a
ceiling on future effort. The worse form is *"no such lever exists,"* because it does not close a
direction — it **legitimises an expensive alternative**.

**(c) WHEN — while the window is still plastic.** This half is the most numerous in the corpus
and the least connected, because it is encoded each time in a domain-specific word rather than in
the word "irreversible." The strongest general form: an infrastructure attribute that forces
resource replacement is zero-cost before the first deployment and a full replacement after it —
therefore add it *pre-deployment*. **A deferred irreversible action does not get cheaper; it gets
more expensive.** The mirror also holds: do not build the consuming half of a contract while the
interface is still unfrozen.

**Counter-rule — when the bar is deliberately LOWERED.** Without this entry the class becomes a
brake and "justifies" paralysis where rollback is in fact cheap.
- Do not over-archive: a zero-inbound duplicate is deleted outright, because history holds the
  when and the why.
- A disproven hypothesis is **deleted**, not hedged with "we used to think."
- A dead branch is **removed**, not tested.
- Standing authorisation to act without review can be granted broadly — with point carve-outs
  exactly where the doors are one-way.
- Sometimes irreversible-and-fast **is** the cure: choosing publication, which permanently
  forecloses a patent route, as a deliberate act precisely in order to unblock work.

> **The rule this yields, which the corpus never stated in one sentence:** the bar drops exactly
> where an **EXTERNAL undo layer** exists — version control holds the deletion, a registry holds
> the package version, the repository is already public. It stays high exactly where no such
> layer exists — a corpus outside version control, a device after a one-way lock, an irreversible
> settlement, a letter a person has already read. **The first question is not "how bad is this"
> but "who holds a copy if I am wrong."**

**Prior art.** Reversibility appears as a safety desideratum in AI safety writing. We found no
formulation of it as an operational proof bar with a membership test, a default-branch rule and a
timing rule.

---

## 7. The carrier thesis

> **A written rule does not fire. A rule exists exactly where its carrier stands at the moment of
> action.**

This is the practice's central operational finding, and it is orthogonal to the taxonomy: it
concerns whether *any* of the nine classes can be acted upon at all.

Outside the moment of action a rule loses to economics, because at the moment of action the
cheaper road wins **every time**. Appending is O(1) while consolidating is O(n). Remembering a
flag must happen O(n) times, while a single check before publication happens once. Truncating a
long command output *feels* like hygiene precisely when the run is long. Therefore:

> **A relapse into a rule you wrote yourself is not carelessness. It is a diagnosis of the rule's
> FORM — the rule is lying in the wrong moment.** The remedy is to move the carrier, not to
> rewrite the text. Another paragraph in the same file is another copy of what already failed to
> fire.

**Taxonomy of carriers by moment of action:**

| Moment | Carrier |
|---|---|
| before publishing work | a hook on the publication step itself — not "a set of commands to run beforehand" |
| every session, before the first write | an always-read preamble (the one file read every time) |
| during audit or review | a **runnable detector** — a command whose output you see, instead of a rule you must remember |
| in a change request | a gate whose inputs lie **inside** the change filter (otherwise decorative) |
| classes the author is structurally blind to | an external eye / adversarial reviewer |
| a campaign | a gate built from the same engine that ran the campaign, so the guard cannot diverge from what it guards |

**The test that exposes a fake carrier, in one question:** *will it fire if I do not think of
it?* If no, it is not a carrier, whatever it is called.

This corpus named one item's carrier for a month before an inventory found the carrier **did not
exist as a thing** — there was no hook, nothing invoked the check from any runner, and the one
existing check operated over a surface that the actual workflow did not pass through. What had
been recorded as a carrier was, on inspection, *another rule to remember*, sitting in a file that
opens with "knowing a rule is not executing it."

> **Inventory your own carrier table as sceptically as somebody else's code.** A declared carrier
> does not self-attest, and a falsely declared one is worse than none, because it removes the
> alarm. (This is **C2** applied to the practice's own method — and the mutation check on the
> replacement was itself green on an **empty set** on its first run, which is **C8**.)

**A form more expensive than "no carrier": a rule that declares an obligation without providing a
TOOL for most of its cases.** Suppose an invariant says "delegate to the shared helper; do not
duplicate." Measurement shows the helper covers one of four cases, and the dominant workload is a
case it does not cover. Every site then writes the logic by hand — not from negligence, but
because there was nowhere to delegate to — and the same hand-written form gets independently
reinvented several times.

> **The diagnosis differs accordingly: ask not "why did they forget the rule" but "could anyone
> have obeyed it?"** If not, build the primitive first and gate afterwards — otherwise the gate
> demands the impossible and is removed by the first person it obstructs.

The tell, visible from outside: **repetition of the form by conscientious sites.** A hand-written
copy carrying a correct comment and correct logic is not a discipline debt; it is a missing
primitive.

**Base rate.** §4 — the one place this corpus has a measured denominator, and it overturns the
practice's own prior in one direction while confirming it in the other.

---

## 8. Limitations

Stated at length deliberately. A field report whose limitations section is short is making a
stronger claim than its evidence.

1. **n = 1, and not a random 1.** One human engineer, one agent, one repository, one architectural
   style, one documentation discipline. Corpus span 2026-06-27 to 2026-08-08 (42 days); measured
   transcript window 32 days.
2. **No inter-annotator agreement, and none is possible.** Classification was performed by the
   same pair that produced the failures. Compare MAST, which reports Cohen's κ = 0.88 from six
   independent annotators over 1,600+ traces. We have nothing of the sort, and the nine classes
   are therefore **not validated as discriminable by third parties**.
3. **Selection by narration, not by occurrence.** §3.1 makes this precise: only failures generate
   prose. Every rate in §4 inherits a 100% ceiling from this.
4. **Single model family.** All agent behaviour observed comes from one vendor's models over one
   release window. Whether these classes generalise across model families is untested — and the
   published false-success work, reporting 3% to 75.8% **by environment and architecture**, is
   strong evidence that single-setting rates for this family of phenomena do not transfer.
5. **The classes are not orthogonal, and we did not measure how much they overlap.** The explicit
   boundary statements in Appendix B are evidence that the boundaries were *contested repeatedly*
   — not evidence that they are clean. Several classes were split out of others when a home
   outgrew its name.
6. **Survivorship in the taxonomy itself.** Classes that proved useful were reinforced and
   elaborated; classes noticed once and never recurring may simply have been forgotten. We cannot
   distinguish "this class is real and general" from "this class is what this pair happens to
   notice."
7. **Numbers not independently reproduced.** The sweep in §4 was performed once, by the same agent
   whose behaviour it measures, using an instrument found defective mid-run (§3.3). No
   replication.
8. **All illustrations are synthetic**, by the design stated in the front-matter note. They
   demonstrate the membership tests; they are not evidence that the classes are frequent,
   important, or correctly individuated.
9. **Domain skew.** The originating practice spans web backend, embedded systems, contract code,
   scientific computation and infrastructure. Classes with an obvious home in one of those (C9,
   in embedded and settlement work) may be over-represented relative to a general software
   practice.
10. **The counter-rules are under-evidenced relative to the classes.** Each class has many
    documented instances; several counter-rules rest on one or two. They were written to prevent
    over-application, and the corpus explicitly declines to state what fraction of flagged
    asymmetries turned out to be deliberate — because it does not know.

---

## 9. What would falsify this, and what a real study would look like

The load-bearing empirical claims, in decreasing order of our confidence:

1. **The success event is never uttered in a self-documenting agent corpus** (§3.1). Falsified by
   finding any comparable corpus with a non-trivial rate of explicit "the rule held" narration.
   This is cheap to test against any published agent memory corpus, and we invite it.
2. **Rules with carriers fire; rules without carriers essentially do not** (§7, §4). Falsified by
   a practice showing preventive firings of carrierless rules at a rate comparable to
   carrier-backed ones. Testable prospectively with a pre-registered marker for preventive
   firings — exactly the marker this corpus lacked, which is why §4's numbers are a ratio and not
   a rate.
3. **The counter-rule is necessary rather than decorative** — that is, taxonomies without
   per-class bounds produce materially higher false-positive rates in use. This is the most
   valuable open question here and we cannot answer it at n=1. The existing finding that 50–81%
   of checklist false positives come from flagging legitimate supplementary omissions suggests
   the effect is real and large.
4. **The nine classes are discriminable by independent annotators.** Untested. The obvious study
   is MAST's method applied to our unit: give annotators trajectories plus the nine membership
   tests and measure κ. **If κ is low, these classes are one practice's private vocabulary and
   should be described as such** — and we would consider that a useful result rather than a
   refutation of the method.

A properly designed successor study would recruit ≥5 human–agent pairs across ≥2 model families;
pre-register both failure *and* success markers so that a denominator exists; have the membership
tests applied by annotators who did not produce the failures; and report per-class precision and
recall for each membership test. We are not in a position to run it.

---

## Appendix A — Six modes in which a delegated agent reports confidently and wrongly

Observed while fanning out sub-agents for review and audit. These are not "it sometimes makes
mistakes" — they are distinct modes, each requiring its own reflex. Ordered by cost. Illustrations
are generic by the same policy as the body.

1. **Fabricates.** Asserts that a field does not exist when it does; states a property backwards.
   *Reflex: verify load-bearing facts yourself.*
2. **Inverts the direction of the conclusion.** "Twelve of thirteen policies define this method,
   therefore the blast radius is wider." The opposite follows: whatever *defines* the method does
   not depend on the default. *Reflex: check the CLASS of the diagnosis and its DIRECTION, not
   merely whether the underlying fact exists.*
3. **Under-estimates what is there.** Reports "no blockers" where a blocker is present. *Reflex: a
   standing record beats a fresh agent report on questions of what exists.*
4. **Over-estimates — the mirror of 3.** Two false steps in one report, both toward "worse than it
   is": an analogy weaker than claimed (it sounds like proof of an oversight, but the mechanism
   differs), and a triage that does not survive its own arithmetic. *Reflex: check not only whether
   a fact exists but whether it BEARS the weight claimed — and check the analogy separately,
   because the analogy carries the verdict, not the fact.*
5. **"X is actually Y" — where acting on it would CORRUPT the correct thing.** An agent reports
   that a record names something by the wrong path and supplies the "real" one. A runtime parse
   shows the opposite: the record was right and the *documentation* was wrong. Accepting the
   finding would rewrite a correct line into an incorrect one and cement it in a commit. Modes 1–4
   cost missed work; this one costs **injected falsehood in the record.** *Reflex: when an agent
   says "X is actually Y," verify BOTH — what it refutes and what it proposes — and for paths,
   names and numbers use a runtime evaluation rather than a reading.*
6. **Explains its own STALE observation with a GENERAL LAW.** An agent searches for a phrase, does
   not find it, and derives a methodological rule about why the search tool is unreliable. The
   phrase existed; it had been edited during the agent's own run. The observation was a **race
   artefact** and the law built on it looked useful enough to be adopted permanently. Both
   directions occur and **the false positive is costlier**: an edit made during the run comes back
   as a verbatim quotation "proving" a fact was already documented. A false negative costs
   redundant work; a false positive **licenses deletion.** *Reflex: while a verifier is reading the
   corpus, do not write to the corpus — and check any "already covered" evidence against the
   pre-session revision.*

Two cross-cutting rules. **The verification bar is ALL findings, not the sharpest ones** — a
selective bar does not hold, because missed findings have nobody to strike them. And **recount your
OWN counters**: an adversarial reviewer catches those regularly, since an author's own numbers are
treated as measured while having been obtained the cheapest way available.

---

## Appendix B — The class boundary graph

The corpus maintains an explicit boundary statement between every pair of adjacent classes. These
exist because the pairs were confused repeatedly; they are the practical content of the taxonomy,
more so than the class names are.

- **C2 Self-attestation ⟷ C3 Mechanism/trigger** — *what does the channel do at the moment of
  failure?* In C3 it is **silent** (the mechanism never fired; test: "did it run?"); in C2 it
  **speaks** (test: "show me the acknowledgement"). A dead path with a "delivered" log is read
  first as C3, then as C2.
- **C4 Measurement substitution ⟷ C5 Verdict/grounds** — *does the error change the ACTION?*
  Yes → C4. No (action correct, the record lies) → C5.
- **C4 ⟷ C6 Computation as honesty engine** — *would a sound instrument give a different reading?*
  Yes → C4 (the instrument lies). No → C6 (the instrument was right; the prose lies).
- **C4 ⟷ C7 One token, two domains** — in C4 there is an **instrument** and it gave a false
  reading; in C7 there may be no instrument at all — two sides of the system diverge and each is
  right in its own coordinates. A search hit that "confirms" a mechanism through name collision
  stays in C4, because there the *checking tool* is what lies.
- **C1 Perimeter ⟷ C7** — C1 asks *"which of N are members?"*; C7 asks *"do both sides share a
  scale?"* "Shared word ≠ fit" is a **membership** error and belongs to C1.
- **C8 Silent default ⟷ C3** — in C3 the mechanism exists but no event pulls it; in C8 the value is
  simply unset and somebody else fills it. Defaults are frequently the green thing that masks
  inertness.
- **C8 ⟷ C7** — in C7 the token is set and the coordinate systems diverge; in C8 there is no token
  at all.
- **C9 Irreversibility ⟷ C5** — C5 holds the general "one axis is not a verdict"; C9 explains *why*
  irreversibility raises the bar, and how it sets the default branch and the timing.
- **C1 ⟷ C3** — when many masks are present and the question becomes "which one still hides a
  member," it is a perimeter question, not a trigger question.

A closing observation about the graph itself: **an artefact describing a disease most often
suffers from it.** Three instances in this corpus were found in the artefacts of the method
itself — a health check whose character class was blind to exactly the link form the same document
described a paragraph below; a file that wrote its own diagnosis ("this has crossed its ceiling;
the disease is the FORM") and then received two more sections in that same form; and a rule that
was fixed not by text but by a **command**, which immediately found a second instance that
size-based triage had missed.

---

## References

**Read in full:**
- Wu, W. *When Errors Become Narratives: A Longitudinal Taxonomy of Silent Failures in a
  Production LLM Agent Runtime.* arXiv:2606.14589.

**Read at abstract, HTML-extract or search-result depth only** — marked because a uniform citation
list would imply uniform depth, which would itself be an instance of C4:
- Cemri, M., Pan, M. Z., Yang, S., et al. *Why Do Multi-Agent LLM Systems Fail?* arXiv:2503.13657
  (NeurIPS 2025).
- *From Confident Closing to Silent Failure: Characterizing False Success in LLM Agents.*
  arXiv:2606.09863.
- *SpecBench: Measuring Reward Hacking in Long-Horizon Coding Agents.* arXiv:2605.21384.
- *AgentLens: Revealing The Lucky Pass Problem in SWE-Agent Evaluation.* arXiv:2605.12925.
- *The Verification Horizon: No Silver Bullet for Coding Agent Rewards.* arXiv:2606.26300.
- *Silent Failure in LLM Agent Systems: The Entropy Principle.* arXiv:2606.08162.
- *Failure Modes in LLM Systems: A System-Level Taxonomy for Reliable AI Applications.*
  arXiv:2511.19933.
- Microsoft AI Red Team. *Taxonomy of Failure Mode in Agentic AI Systems.* Whitepaper, 2025.
- *ErrorMap and ErrorAtlas: Charting LLM Failure Modes.* OpenReview.
- *From Sycophancy to Deception: A Unified Taxonomy for LLM Spontaneous Misalignment.*
  arXiv:2604.04788.
- *Mechanisms of Introspective Awareness.* arXiv:2603.21396.
- *LLMs Show No Signs Of Individuated Metacognition.* arXiv:2605.24299.
- *Before You Interpret the Profile: Validity Scaling for LLM Metacognitive Self-Report.*
  arXiv:2604.17707.
- *MIRROR: A Hierarchical Benchmark for Metacognitive Calibration in Large Language Models.*
  arXiv:2604.19809.
- Park, J., Kim, M., Ray, B., Bae, D.-H. *An Empirical Study of Supplementary Bug Fixes.* MSR 2012.
- Yue, R., Meng, N., et al. *A Characterization Study of Repeated Bug Fixes.* ICSME 2017.
- *An Empirical Study of Supplementary Patches in Open Source Projects.* Empirical Software
  Engineering, 2016.
- Krakovna, V., et al. *Specification gaming examples in AI.* Collected list, 2020.
