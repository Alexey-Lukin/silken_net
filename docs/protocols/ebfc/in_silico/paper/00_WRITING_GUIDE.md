# How to Write This Paper — a practical guide (Стаття 1, for a first-time academic author)

> **Who this is for:** the Architect (a senior Ruby/Rails engineer, not a career academic) writing a
> first Q1 computational-chemistry paper. It explains *how* to write each part correctly, in
> software-engineering terms where that helps. The *skeleton* (sections, figures, result-map) is in
> [`00_OUTLINE.md`](00_OUTLINE.md); the *numbers* live in [`SUMMARY.md`](../SUMMARY.md); this doc is
> the *method for writing*. Target = **J. Phys. Chem. B** (JPCB).

---

## 1. The mental model: a paper is a rigorous PR to the scientific record

You already know how to ship a reviewed change. A paper is the same shape:

| Software | Paper | What the reviewer checks |
|---|---|---|
| PR description | **Abstract** (~200 words) | Is the change worth merging? |
| Issue / problem statement + prior art | **Introduction** | Is the problem real + unsolved? Did you read the codebase (literature)? |
| Implementation + README/Dockerfile | **Methods** | Could I rebuild this exactly? |
| Test output / dashboards | **Results** (+ Figures) | Are the findings real, objective, not cherry-picked? |
| Design notes / trade-offs | **Discussion** | Do you understand what it means + its limits? |
| Changelog summary | **Conclusions** | What's the takeaway? |
| Appendix / full logs + configs | **Supporting Information** | Coordinates, scripts, golden outputs |
| Dependency credits | **References** | Did you credit prior work? (under-citing = red flag) |
| PR review cycle | **Peer review** | Reviewers request changes; you respond point-by-point |

**The one acceptance rule for JPCB:** the paper must **provide new physical insight** — not re-confirm
something already known. Frame everything around the *insight*, never around "we validated X".

## 2. Our contribution framing (the most important decision)

Our honest finding is that the raw DFT cascade is uphill in every method, the cathode DET margin is
borderline, and the gap is a quantified limit of implicit solvation. A first-timer's instinct is to
hide this and claim "validation". **Do the opposite — the honesty IS the contribution.** Three real
insights to sell (all are "new physical insight"):

1. **A quantified, decomposed methods limit.** The ~1 eV cascade gap is *not* hand-waved — it
   decomposes into mediator **speciation** + **PCM differential solvation**, each computed, benchmarked
   on the [Os(H₂O)₆] group-8 ~1 V error. That is a transferable lesson for anyone doing implicit-solvent
   redox DFT on charged metal complexes.
2. **A predictive design rule.** The Hammett LFER for the Os(III/II) mediator + the cascade-alignment
   rule gives a *predictive handle* and rationalizes the known experimental optimum — predictive value
   is "especially welcome" at JPCB.
3. **An honest, mechanistic cathode finding.** The borderline λ-limited DET (a *finding*, corrected from
   an earlier artifact) + the low-λ-metal / conductive-MOF / enzyme-free design levers.

> **Rule of thumb:** every claim is one of {*positive result*, *quantified limitation*, *design rule*,
> *prediction*}. None is "validation". An honest negative, properly decomposed, is a strong paper; a
> dishonest positive gets desk-rejected or retracted.

## 3. Section-by-section how-to

### Abstract (write LAST, ~150–200 words, one paragraph)
Formula: **problem → gap → what we did (methods) → 3 headline numbers → the honest limit + its fix →
outlook.** No citations, no abbreviations on first sight. The TOC graphic (required) is a small visual
of the same story.

### Introduction (write after Methods+Results; longest lit work)
Funnel: broad → specific. (a) Why autonomous/implantable EBFC sensing matters; (b) the FAD-GDH/Os/laccase
system + its known challenges; (c) **the gap** — the field models EBFCs experimentally and with
reaction-diffusion math, *not* at the electronic-structure level; (d) **our contribution** in 2–3
sentences. End the intro by stating exactly what the paper does. ~40–60 references (you currently
under-cite — see `00_OUTLINE.md` §6 scaffold and expand). Pitfall: don't review everything; review only
what sets up *your* gap.

### Methods (write FIRST — it's the most mechanical + your strength)
Goal: **a competent reader could reproduce every number.** Report, per JPCB/Boggs (Pure Appl. Chem.
1998, 70, 1015): functional(s), basis sets + ECPs per element, solvent model + parameters, what was
optimized vs single-point, convergence criteria, software + **version**, and that geometries/coordinates
are in the SI. Your reproducibility (conda-lock env, deterministic seeded scripts, committed caches) is
a genuine selling point — say so. Draft is in [`02_methods.md`](02_methods.md). Pitfall: vague Methods
("DFT was used") is the fastest reviewer complaint.

### Results (write second; pull every number from SUMMARY)
One subsection per finding, in the OUTLINE order. Each: state what was computed → the number (→ figure/
table) → one sentence of interpretation. **Be transparent**: report the uphill raw values *and* the
verified experimental cascade; show the λ-sensitivity honestly. Figures carry the story (a reviewer
reads figures first): a cascade/Marcus diagram, the Hammett plot, the ZIF hop ladder, the
solvation-gap-closing plot. Pitfall: don't bury the honest numbers — lead with them.

### Discussion (can merge with Results at JPCB)
What the results *mean*: the methods lesson (when does implicit solvent fail, and by how much), the
design rule's reach, the cathode mitigation path, and an explicit **Limitations** paragraph (vertical
geometries, no spin-orbit on Os, single-shell solvation, QM-cluster vs QM/MM). Naming your own limits
*increases* trust — reviewers find them anyway.

### Conclusions (short, punchy)
3–5 sentences: the insight, the design rule, the methods lesson, and the experimental closure (Ti-coin
EIS predictions). No new information.

## 4. Mechanics

> **Voice & register (set 2026-06-06, by the founder's delegation):** academic-formal but clear and
> unfussy — the register of a rigorous methods paper, not a vision essay. Honest and precise: state what
> the data shows, name limits plainly (the contribution *is* the honest decomposition). **Systems-clarity**
> (the author's signature): present the EBFC as a chain (anode→mediator→cathode), each result a link, and
> let the structure carry the argument. Drawn from the author's formal-physics register (the DM-EFT work)
> + the SilkenNet systems-thinking + the honesty ethos — but the poetic "living-wood / archival-burden"
> flavour of the *vision* documents stays OUT of journal prose. (Applied in [`03_results.md`](03_results.md).)

- **Tense/voice:** past tense for what you did ("we computed"), present for established facts ("B3LYP
  over-stabilizes…"). First-person plural ("we") is standard and fine.
- **Figures > prose** for results; each must stand alone (self-contained caption). Aim ~5 figures + ~4
  tables (see OUTLINE §4). A required **TOC graphic** = the one-glance summary.
- **References:** ACS style (numbered). Cite the method originators (Marcus, Nelsen, Beratan–Onuchic,
  the Hammett/Lever LFER, the group-8 PCM benchmark) and the experimental anchors. Use a reference
  manager (Zotero/Paperpile) — do *not* hand-format.
- **Length:** JPCB Articles have no hard limit but value concision; ~6000–8000 words + figures is
  typical. Confirm current limits on the ACS author-guidelines page at draft-freeze.
- **SI:** scripts, optimized-geometry coordinates, golden outputs, the conda-lock file. This is where
  reproducibility lives.

## 5. The process (and the gates)

```
Methods → Results → Introduction → Discussion/Conclusions → Abstract + TOC + cover letter
  → internal self-review (the checklist below) → submit → peer review → revise
```

- **✅ IP posture — defensive publication:** no patent is filed (by design). The publication **IS** the
  protection — it fixes prior art (see [`08_01 §2`](../../../08_01_Joint_Publications_and_IP_Strategy.md)
  and `protocols/anchor/prior_art_landscape.md`). Submit freely; no gate.
- **Authorship/CRediT:** agree this *before* drafting (OUTLINE §0): you (Conceptualization, Methodology,
  Software, Investigation, Writing-original) + an external computational-electrochemistry collaborator TBD (the QM/MM upgrade, Writing-review).
- **Cover letter:** 1 paragraph — what's new, why JPCB, why now. Suggest 3–4 reviewers (not collaborators).
- **Peer review = the PR review:** expect "major revision". Respond to **every** comment in a point-by-point
  letter ("Comment → Response → change made, page X"). Politeness + thoroughness win; never ignore a point.

## 6. First-timer pitfalls (self-review checklist)

- [ ] No overclaiming — no "validation"/"proves"; every claim matches the data's strength.
- [ ] The honest negatives are *foregrounded* and decomposed, not hidden.
- [ ] Methods reproducible (versions, basis/ECP, solvent params, SI coordinates).
- [ ] Every number traces to SUMMARY (One-Home); change a result → change SUMMARY, not the paper twice.
- [ ] Intro funnels to a single clear gap; ~40–60 refs; prior art credited (esp. the experimental Os-GcGDH
      series and the ZIF-laccase-mimic cathodes — these are prior art, our novelty is the *integrated* system).
- [ ] Each figure stands alone; TOC graphic present.
- [ ] Limitations paragraph is explicit.
- [ ] Scope honored (L1 + L3 + L3b + mediator + solvation; L2/L4 → окремі майбутні EBFC-статті).
- [ ] IP gate respected before any external disclosure.

## 7. Key references to read (method + how-to)

- **DFT methodology rigor:** Bursch et al., *Best-Practice DFT Protocols*, Angew. Chem. Int. Ed. 2022,
  10.1002/anie.202205735 — align our functional/basis/protocol justifications with it + cite it.
- **Reporting standard (JPCB-required):** Boggs, Pure Appl. Chem. 1998, 70, 1015 — the checklist for
  reporting electronic-structure calculations.
- **JPCB author guidelines:** pubs.acs.org/page/jpcbfk/submission/authors.html — confirm structure,
  length, TOC, SI rules at draft-freeze.
- Domain method anchors + experimental anchors: see `00_OUTLINE.md` §6.
