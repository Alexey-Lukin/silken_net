# Prior Art Search Query Set for TISC ЧНУ

> **Purpose:** Pre-prepared patent search queries for TISC (Technology and Innovation Support Center) at ЧНУ. To be used during WIPO PATENTSCOPE / Espacenet prior art search **before filing**.
> **Cross-ref:** [`patent_filing_readiness.md`](patent_filing_readiness.md) (зведений filing-readiness packet: novelty-матриця + checklist) · [`patent_claims_draft.md`](patent_claims_draft.md) (claims + synergy-defence) · [`08_01 §2.1`](../../08_01_Joint_Publications_and_IP_Strategy.md) — TISC engagement plan

---

## ⚠️ Methodology First — Patentability ≠ FTO (read before searching)

This is a **patentability / novelty** search, not a Freedom-to-Operate search. The two have **opposite** rules — mixing them produces a dangerous false-positive "we're novel" result:

| | **Patentability (this doc)** | Freedom-to-Operate (later, pre-launch) |
|---|---|---|
| **Date filter** | ❌ **NONE.** Prior art has no time limit — a 1975 paper or expired patent still destroys novelty. | ✅ Last 20 yr (only *active* patents you could infringe) |
| **Search scope** | ✅ **Full text** (description, drawings, abstract). A feature merely *mentioned* anywhere is prior art. | Claims only (what's legally enforced) |
| **Terms** | ✅ **Broadest possible** + wildcards + synonyms (patent attorneys deliberately use generic language) | Narrow/specific |
| **Sources** | Patents **+ non-patent literature** (papers, theses, conference proceedings) | Patents only |

**Three things must hold for patentability, not one:**
1. **Novelty** — no single document discloses our exact combination.
2. **Inventive step (non-obviousness)** — the examiner WILL combine Patent A (gyroid) + B (EBFC) + C (LoRa) and argue "obvious to combine known elements". Our defence must be an **unexpected synergistic effect** (e.g. EBFC simultaneously powers AND senses with zero instrumental noise; gyroid macroporosity enables xylem-integration *and* isoelastic stress matching), and/or documented **"teaching away"** (literature saying these can't/shouldn't be combined) that we overcame.
3. **Industrial applicability** — trivial here.

**Query syntax conventions** (PATENTSCOPE / Espacenet):
- `*` = truncation/wildcard (`sensor*` matches sensor, sensors, sensing).
- `NEARn` = proximity (terms within n words). PATENTSCOPE: `NEARn`; Espacenet Classic: `prox/distance<n>`; Google Patents: use `NEAR` or quoted phrases. **Always use proximity instead of bare `AND`** — bare `AND` across a 50-page patent is ~90% noise.
- Group every OR-set in its own parentheses so `AND`/`OR` precedence can't silently break the logic.

---

## Query Set 1: Coaxial Gyroid Anchor (Geometry + Material)

**Target:** Novelty of Ti-6Al-4V TPMS gyroid implant in living plant (woody) tissue.

```
("gyroid" OR "TPMS" OR "triply periodic minimal surface") NEAR15 ("titanium" OR "Ti-6Al-4V" OR "Ti alloy") AND (implant* OR anchor* OR scaffold*)
```
```
("gyroid" OR "TPMS" OR lattice*) NEAR15 (tree* OR plant* OR wood* OR xylem OR trunk*) AND (sensor* OR monitor* OR implant* OR IoT)
```
```
(coaxial OR multilayer* OR (("three" OR "tri*") NEAR3 (zone* OR part* OR layer*))) NEAR15 (implant* OR insert*) AND (titanium OR "Ti alloy") AND (polymer* OR PEEK)
```

**CPC classes (corrected):**
- **A01G 7/00** — Botany in general (plant physiology devices) ← primary
- **A01G 29/00** — Root/trunk treatment, injecting into plants ← primary
- ~~A01G 23/00~~ — *forestry = logging/felling, NOT plant-care; dropped*
- A61L 27/06 — Macromolecular/metal materials for implants (Ti)
- B33Y 80/00 — Products of additive manufacturing (DMLS/SLM)
- B33Y 70/00 — Materials for additive manufacturing

---

## Query Set 2: EBFC Mediator Chemistry

**Target:** Novelty of dgrFAD-GDH + Os-PVI MET anode + genipin-chitosan-CNC matrix + laccase/ZIF DET cathode.

```
("enzymatic biofuel cell" OR "enzymatic fuel cell" OR "biofuel cell") NEAR20 (tree* OR plant* OR xylem OR sap OR phloem)
```
```
(("flavin adenine dinucleotide" NEAR5 "glucose dehydrogenase") OR "FAD-GDH" OR "FAD dependent glucose dehydrogenase") AND (osmium OR "Os polymer" OR "redox mediator" OR "redox polymer")
```
```
(genipin) AND (chitosan) AND ("cellulose nanocrystal" OR CNC OR nanocellulose) AND (("enzyme immobili*") OR "hydrogel matrix")
```
```
(laccase OR "bilirubin oxidase") NEAR15 (ZIF OR "zeolitic imidazolate" OR "metal organic framework" OR MOF OR nanozyme*) AND ("oxygen reduction" OR ORR OR cathode*)
```

**CPC classes (corrected):**
- **G01N 27/327** — Electrochemical biosensors (enzyme electrodes) ← primary modern class
- H01M 8/16 — Biochemical/biofuel cells
- C12N 9/04 — Oxidoreductases (dehydrogenases)
- ~~C12Q 1/004~~ — *too narrow; kept only as secondary*

> 🔎 **Known prior art to expect (2026-06 literature scan — pre-empt these):** the EBFC component chemistry is **heavily published**, so Query Set 2 *will* hit — frame novelty accordingly:
> - **Os-mediated FAD-GDH is established** (Degani & Heller 1989 →): Os redox polymers wired to *the same GcGDH* across **+15…+489 mV vs NHE**, optimum ≈ **+309 mV** (Mano/Heller school). → the FADH₂→Os cascade and its potential-tuning are **prior art**; tuning the Os potential to the enzyme is additionally *obvious* via Lever's additive E_L scheme (Inorg. Chem. 1990). **Do not claim the cascade or mediator-potential tuning per se.**
> - **ZIF laccase-mimic cathodes are published** (Cu/Zn-ZIF; Cu-doped ZIF-67 for ORR, incl. O₂-binding DFT). → the laccase/ZIF cathode concept is **prior art**.
> - **Where novelty survives:** the *integrated Gen 2.0 architecture as a whole* — coaxial **gyroid Ti-6Al-4V ↔ xylem** interface hosting the EBFC + dgrFAD-GDH/Os-PVI-in-genipin-chitosan-CNC + Nafion-g-PSBMA + **Cu-Co-Ce trimetallic** ZIF cathode — and the **synergy** (EBFC is *simultaneously* power source and zero-noise homeostasis sensor; gyroid does xylem-integration + isoelastic matching + the metal↔xylem EBFC interface). Frame claims on the synergy, not the parts.
> - **Embargo coupling:** the planned Стаття 1 (comp-only) still discloses the cascade/PCET mechanism → it must be **filed before journal submission** ([`08_01 §2`](../../08_01_Joint_Publications_and_IP_Strategy.md)).

---

## Query Set 3: LoRa Mesh + Bio-Powered Forest Monitoring

**Target:** Novelty of self-powered (tree-energy) LoRa mesh with chaotic-dynamics health analytics.

```
(LoRa OR LoRaWAN OR LPWAN OR "low power wide area") NEAR15 (forest* OR tree* OR vegetation OR woodland*) AND (monitor* OR sensor* OR IoT)
```
```
("self-powered" OR "energy harvest*" OR "biofuel cell" OR "plant microbial") NEAR15 (sensor* OR node* OR "wireless") AND (tree* OR plant* OR forest*)
```
```
("non-linear" OR nonlinear OR chaotic OR "strange attractor" OR "Lorenz" OR "dynamical system*") NEAR15 (sensor* OR monitor* OR diagnos*) AND (health OR status OR homeostasis OR anomaly)
```
```
("carbon credit*" OR "carbon offset*" OR "measurement, reporting and verification" OR "digital MRV" OR dMRV) AND (blockchain OR token* OR "distributed ledger") AND (forest* OR tree* OR vegetation)
```

> ⚠️ **Do NOT search only "Lorenz attractor"** — attorneys write broad ("non-linear chaotic temporal analysis", "strange attractor"). A bare "Lorenz attractor" query returns ~0 and falsely signals a clear field. Likewise spell out **"measurement, reporting and verification"** — the bare acronym "MRV" collides with Magnetic Resonance Venography etc.

**CPC classes:**
- G06Q 50/02 — Agriculture (digital monitoring)
- H04W 84/18 — Ad-hoc / mesh networks
- H02J 7/00 / H10N — Energy harvesting / power management
- G16Y — IoT specifically

---

## Query Set 4: Self-Healing Coating on Ti Implant

```
("self-healing" OR "self healing" OR "autonomous repair" OR "self-repair*") NEAR15 (coating* OR film* OR microcapsule*) AND (titanium OR "Ti-6Al-4V" OR "Ti alloy")
```
```
("8-hydroxyquinoline" OR oxine OR oxyquinoline OR "8-HQ" OR "corrosion inhibitor*") NEAR15 (microcapsule* OR coating* OR "controlled release") AND (titanium OR metal*)
```

**CPC classes:**
- C09D 5/08 — Anti-corrosive coatings
- C23C 28/00 — Multilayer metal coatings
- B01J 13/02 — Microcapsule manufacture

---

## Query Set 5: Anti-Biofouling Zwitterionic Membrane

```
(zwitterion* OR sulfobetaine OR SBMA OR PSBMA OR "poly(sulfobetaine*)") NEAR15 (Nafion OR "proton exchange membrane" OR "ion exchange membrane" OR PEM)
```
```
("antifoul*" OR "anti-foul*" OR "anti-biofoul*" OR "low fouling") NEAR15 (membrane* OR "polymer brush" OR coating*) AND (implant* OR sensor* OR biomedical OR "biofuel cell")
```
```
(UCST OR "upper critical solution temperature") NEAR10 (membrane* OR "polymer brush" OR hydrogel*)
```

**CPC classes:**
- C08J 5/22 / H01M 8/1067 — Ion-exchange membranes
- A61L 27/34 / A61L 33/00 — Anti-fouling biomaterial surfaces

---

## Usage Notes (patentability search)

1. Run every set on **PATENTSCOPE** (WIPO) + **Espacenet** (EPO) + **Google Patents** + **at least one non-patent-literature source** (Scholar / Lens.org) — papers and theses are prior art too.
2. **No date filter.** (Date-limit only later, in the separate FTO pass.)
3. Search **full text** (title + abstract + description + claims), not claims-only.
4. For every hit, log: number, title, assignee, **which of our features it discloses** (even in passing), and whether it would support a **novelty** objection vs an **inventive-step** objection.
5. Build the inventive-step defence explicitly: for each near-hit, note the **unexpected synergy** our system has that the reference lacks, and any **"teaching away"** we overcame.
6. A hit disclosing one component is expected and fine — the question is whether the **claimed synergistic combination** survives both novelty *and* non-obviousness.

> **Silken Net positioning:** Each individual component (gyroid implant, FAD-GDH/Os EBFC, laccase/ZIF cathode, LoRa mesh, blockchain MRV) has prior art. The patentability case rests on the **synergistic combination** producing effects no single reference teaches — e.g. the EBFC being *simultaneously* the power source and a zero-instrumental-noise bio-sensor (delta_t → chaotic-dynamics health signal), and the gyroid simultaneously enabling xylem-integration, isoelastic stress-matching, and the EBFC metal-xylem interface. **Frame claims around the synergy, not the parts list** — that is what defeats an obviousness rejection.
