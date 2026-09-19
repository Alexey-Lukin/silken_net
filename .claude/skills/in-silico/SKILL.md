---
name: in-silico
description: "Use when working on the silken_net in-silico surface — the EBFC Gen 2.0 Zero-Lab DFT+MD pipeline (tools/in_silico/, silken_md conda env): L1 AlphaFold-3 protein architecture, L2 OpenMM MD, L3 PySCF quantum chemistry (ΔSCF redox cascade, Hammett mediator series, ZIF-cathode DET, cluster-continuum solvation), L4 kinetics/EIS, the Стаття 1 computes, and the anchor-mechanics series (Lamé press-fit and thermal stress, pogo Z-stack tolerance, EDLC aging + Kirkendall, bus mechanics and contact, per-alloy oxide-DET, PTFE-GDL breakthrough, the thermal-install cambium field, gyroid ligament thickness, sap saturation and its recipe window; the roster is `ls scripts/`; §01/§02/HW.* machine-half). Operational playbook: the script dependency graph, the critical rules (rules.md) and the when-modifying discipline (modifying.md) behind one-line indexes, the DFT/MD gotchas, the conda-lock env and the cache-is-SSOT discipline; routes to the 01_03 §3.4 + protocols/ebfc/in_silico canon, does not restate results. Examples: \"run or add a DFT/MD script\", \"why does the Os(III) SCF oscillate forever\", \"the FADH2->Os cascade comes out uphill\", \"set up the in-silico env\", \"why is density_fit slower for Ce\", \"add a ligand to the pipeline\", \"check the cascade verdict\", \"порахуй Z-stack tolerance\", \"онови Arrhenius aging модель\", \"press-fit Lamé для Zone1↔2\"."
---

# In-Silico Pipeline (EBFC Gen 2.0 Zero-Lab Proof)

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md §3.4` | Pipeline spec, TRL gate, L1-L4 definitions, artifact table |
| `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md` | Live status: running/queued/completed scripts, decision matrix |
| `docs/protocols/ebfc/in_silico/SUMMARY.md` | All L1-L4 results in one page |
| `docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md` | DFT details, cascade methods comparison, ΔSCF, L3b cathode |
| `docs/protocols/ebfc/in_silico/L1_protein_architecture.md` | AlphaFold 3 results, d_FAD distance; §2 = the CHEM.11 freeze design (N→Q sequons, the 600 aa invariant, compensating substitutions) |
| `docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md §2.1` | Synthetic xylem sap — the RATIFIED recipe point and pH setpoint; owner-script `67`, doc↔cache pinned |
| `docs/00_02_Academic_Integration_and_IP.md` §1 | Partner registry: Мінаєв = spin-forbidden O₂-activation kinetics, NOT DFT-redox (that is self-owned; an explicit-water collaborator is TBD) · ЧМА Бушуєва = gel-matrix stabilisation · xylem-sap composition = ЧНУ bio hub |
| `docs/00_02_Academic_Integration_and_IP.md` §2 | Publication plan — Стаття 1 |
| `docs/00_07_Action_Plan_Tracker.md` | HW.5.IS section — operational task status |
| `01_01 §1.4` / `01_01 §4.2` · `02_02 §2.2` / `02_02 §3.5` · `01_02 §2.2` · `00_07` HW.3 / HW.33 / HW.34 / HW.43 | Anchor-mechanics canon (ratified verdicts live THERE) + the open-work items: `50`/`51`/`56` → the Zone1↔2 band window (§4.2, HW.3) · `55`/`68` → the bus wire and its liner (§1.4, HW.34) · `52` → the Z-stack and the O-ring gland (`02_02 §3.5`, HW.33) · `59` → contact-part endurance (`02_02 §2.2` + `01_02 §2.2`, HW.43) |
| `tools/in_silico/README.md` | Setup, quickstart, GPU notes, GAFF explanation |

## Script Dependency Graph

Edges only — `A → B` means B reads A's cache, imports A, or loads A's ligand. The roster is `ls scripts/`
and per-script status is `PIPELINE_STATUS`; a change re-runs everything downstream of it (§When Modifying #15).

```
Parameterization (CPU) → L2 MD (GPU), via ligand SDF + gaff_cache:
  02 FAD · 03 GEN · 04 CSO · 05 CLB · 06 PPy · 07 PVI · 08 SBMA
  10 ← 02,03 · 11 · 12 · 14 ← 02-05 · 13 ← 08 · 15 ← 02,03,07 · 16 ← 03,04,05
  lib/md_utils.prepare_protein → 10 · 11 · 12 · 14 · 15      lib/xylem_sap → 14

L3 DFT anode (CPU):
  20 (FAD, lumiflavin.json) → 21b · 21c · 21e · 21f · 22 · 32 · 34
  21f (Os dimethyl; SOLE owner of os_complex.json) → 22 (cascade) → 21d (ωB97X; reads comparison.json)
  21f · 21d (the ωB97X Os caches) → 21g (adiabatic ΔSCF) · 33 (PCET cascade)
  lib/os_geometry.build_os_complex → 21e (Hammett ①) · 21f · 34 (cluster-continuum ②) · 34b (ωB97X ② cross-check)
  29 (Nelsen λ) standalone · 29b (semiquinone λ) → 29c (outer-sphere λ)
  28 (tunneling, PDB only) → 28b (CHEM.16) · 69 (CHEM.11)      11 (DCD) → 27 · 28b
  70 (CHEM.11 site conservation) standalone — reads committed alignments in `data/chem11_conservation/`,
     never the network; it is the SECOND axis of CHEM.11 and is never merged into 69's patch score
  21 · 21b · 21c write their own caches; nothing downstream reads them

L3b DFT cathode (CPU):
  23 (ZIF clusters) → 24 · 24b      24 → 24b (FO-DFT, CHEM.14)      24 · 24b · 35 (metal λ) → 25 (k_ET vs λ ③)
  24 (importlib) + 25 → 24c → 24d      25 + 31 → 31b

L4 kinetics (CPU, seconds):
  lib J_MAX_25C → 30 · 30b · 31 · 57      22 · 30 · 30b · 31 → 40

Paper: 60 (figures) · 61 (tables) read the L3/L3b caches — re-run them after any upstream change

Anchor mechanics (CPU):
  lib/mechanics → 50 · 51 · 55 · 56      lib/beam_contact (ONE contact solver) → 55 · 68 — a solver change re-runs BOTH
  tools/cad/cem → 52 (o_ring of cathode_flange + radome; refuses a mismatch) · 54 · 55 (spans read at runtime)
  55 → 68 (importlib + bus_mechanical.json)      54 → 64 (importlib + anchor_thermal_bridge.json)
  62 → wind_duty_cycle.json → 55 · 59 (cycle budget; 55 prints NOT COMPUTED without it)
  66 → tools/cad TopologyCrossChecks (a C# consumer: no Python re-run reaches it)
```

## Critical Rules

**Bodies live in `rules.md` — open it before running or changing DFT/MD, declaring an anchor dimension,
or quoting a literature constant.** Below is one generated line per rule: the line is the CARRIER; the
mechanism, the incident and the bounds are in the companion. Numbering is append-only — cite
`in-silico §Critical Rules #N` (the section name disambiguates from §When Modifying).

<!-- INSILICO-RULES-INDEX:AUTO — generated from rules.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

0. `conda env list` in a non-interactive shell answers about ITSELF, not about the machine — ask the FILESYSTEM
1. Shared lib is SSOT — every SHARED or canon-mirrored constant, every cache root and `banner()` come from `lib/` and are never redefined locally
2. A SMILES fix cascades — fixing one in 02-08 means rerunning ALL downstream MD that uses that ligand
3. DFT: NEVER two heavy jobs on same CPU
4. No density_fit() for Os/Ce — the auto-generated aux basis for heavy metals is 3× SLOWER than standard integrals
5. Open-shell transition metals can oscillate forever — `level_shift=0.3` stops UKS on Os(III), Co-Ce and Ce, but it biases the reported LUMO, so switch it on only where the SCF oscillates and then read E_total, not LUMO
6. MD goes NaN at the NVT ramp unless it pre-relaxes at 10K and ramps from 50K in 10K steps
7. MD trajectories are gitignored — commit only the JSON/PNG summaries
8. The CI smoke MD went NaN from BOX SIZE, not RNG — shrink the box (drop disordered tails), never just re-run or raise the iteration cap
9. Declaring an anchor dimension: name the REFERENT, not the number — and if canon gives a RANGE, say which end you took and why
10. A literature constant can be the right NUMBER in the wrong ROLE and of the wrong FORM — and the two errors compound silently

<!-- /INSILICO-RULES-INDEX -->

## DFT Gotchas (Hard-Won Lessons)

- **PySCF no SDD** — use `lanl2dz` for Cu/Co, `stuttgart_rsc` for Ce (Ce not in lanl2dz)
- **wb97x-d not supported** — use `wb97x` (range separation is the main fix, dispersion ~0.05 eV)
- **ωB97X Koopmans orbital energies ≠ redox potentials** — RSH gives accurate IPs but LUMO systematically too high for inter-molecular comparisons. Use ΔSCF (total energies) instead. B3LYP Koopmans works better due to error cancellation.
- **Adiabatic ΔSCF** — composite approach: geom opt at B3LYP/def2-SVP, SP at ωB97X/def2-TZVP. Saves orders of magnitude vs full ωB97X opt.
- **Cl on flat PES** — geometry optimization never converges GAU displacement criterion for Cl in Os complex. Programmatic octahedral geometry sufficient (LUMO diff < 0.002 eV after 30 cycles).
- **Spin parity** — odd electrons → odd spin (2S). Auto-detect: `spin = mol.nelectron % 2` as fallback.
- **PCET: never put H⁺ / H₃O⁺ in PCM** — PCM oversolvates small ions (H₃O⁺ by ~7 eV). A proton-coupled couple takes the **thermodynamic proton reference** (Isse & Gennaro 2010 — the constant `32` and `33` share), NOT explicit water.
- **FAD in MD topology** — GAFF renames FAD to "UNK", all atoms have "x" suffix. 86 atoms total, 53 heavy, neutral with an EVEN electron count (`ligands/FAD.sdf`). A TRUNCATED fragment can come out odd: `27` cuts the isoalloxazine ring out of the MD frames and sets `mol.charge = n_electrons % 2`.
- **Os mediator speciation matters (② / script 34)** — the axial ligand (chloro vs aqua vs bis-imidazole) moves E°(Os III/II) by a large fraction of the cascade gap; on the dimethyl device mediator ② is a **chloro(+1/+2)↔{aqua,bis-Im}(+2/+3) differential-solvation bracket** (the +2/+3 couples carry the larger group-8 PCM bias) — **functional-ROBUST, while the internal aqua↔bis-Im order is functional-SENSITIVE** (34b). Decompose the cascade gap into speciation + solvation **+ the 4,4'-dimethyl substituent ①**, and quote ① WITH its method (Koopmans ≠ adiabatic), never as one blended value — an unsourceable blend once masked a same-table clash. Magnitudes: `SUMMARY.md` §Cluster-Continuum.
- **lo.PM / lo.Boys crash (PySCF `lib.einsum` version bug)** — `ValueError: not enough values to unpack (expected 4, got 3)` in `pipek.py`. For the 2-orbital FO-DFT localisation (24b) skip PySCF `lo` entirely: diagonalise the metal-projected 2×2 Mulliken population matrix in the {i,j} MO basis → rotation `R` → `H_ab` = off-diagonal of `Rᵀ·diag(εᵢ,εⱼ)·R` (Mulliken-Hush diabatisation, pure numpy; F is diagonal = ε in the orthonormal MO basis).

## MD Gotchas (Hard-Won Lessons)

- **Fibonacci sphere placement** — deterministic (seed=42) but can create bad contacts at specific positions; 313K (40°C) is the vulnerable case. The cure is Critical Rule #6 (full minimisation + 10 K pre-relax), never dropping a temperature — `test_temperature_sweep_all_stable` requires all four stable.
- **GAFF matching** — `GAFFTemplateGenerator` matches by graph structure. One `Molecule` per unique chemical species is enough.
- **L2 10ns RMSD ~4 Å is normal** — AF3 structures relax 3-5 Å under AMBER ff14SB for large enzymes. Check **Rg** (radius of gyration) — if stable → protein folded, RMSD is just conformational relaxation. Full equilibration needs 20-50 ns. ⛔ A regression test pinning this against Apple's OpenCL fast-math was MEASURED and DECLINED (2026-06-06): our claims rest on Rg staying flat, not on bit-level trajectory reproducibility — don't re-propose it unless a claim starts depending on exact trajectory values.
- **25GB DCD files** — use `stride=10` or `stride=100` when loading with mdtraj. Full load kills memory.
- **PBC unwrap for ensemble graph analysis (CHEM.16 / 28b)** — a PBC-wrapped protein/cofactor splits a contact graph (artificial >cutoff gaps) → Dijkstra returns NaN. `make_molecules_whole()` makes each molecule whole but leaves a SEPARATE non-covalent cofactor (FAD) in a *different periodic image* → still disconnected (verified 1/15 frames). Use `traj.image_molecules(inplace=True)` (default anchor = largest molecule = protein) to co-locate everything into the protein's image (15/15 frames). Apply on the FULL topology, before `atom_slice`.

## Cascade Verdict Summary

**Direction only:** the cascade FAD→Os is verified **downhill** from measured E°s, while raw DFT comes out **uphill in every method** — that contradiction is a method limit, not a physics one. ② decomposes the gap into a **chloro↔+2/+3 differential-solvation bracket** (functional-robust; the internal aqua↔bis-Im order is functional-sensitive) + the **4,4'-dimethyl substituent**; rigorous closure = explicit-water QM/MM — ⛔ NOT Minaev's school (their angle is spin-orbit / O₂ activation, `00_02 §2.1`): own follow-up or a specialist computational-electrochemistry collaboration, TBD. **The verdict's home is `SUMMARY.md` §Anode («Conclusion») + `01_03 §3.4`; its magnitudes, its citations and the all-methods table live there and in `L3_quantum_chemistry.md`.**

🔴 **A router may carry the DIRECTION of a verdict (downhill / uphill / blocked); the moment it carries the number it is a mirror — and this one feeds a TRL judgement.** A number set beside the verdict is taken from here, and the reader never reaches the line saying it is not kept here. Verify any value against `SUMMARY.md` before quoting it onward; the doc↔cache pins are `CHECKS` in `tools/in_silico/tests/test_doc_cache_sync.py`, and they reach the docs, never this skill.

## Paper Citations (DOI-verify)

Founder fully delegates citations/Zotero («все на тобі», no Zotero in his workflow) → **Crossref IS the arbiter; verify every DOI end-to-end.**
- **Recipe:** try `curl` first — it has reached Crossref, NEA, NIST and GitHub directly, which you need to grep a full text; when the Bash network is sandboxed (curl times out) → **WebFetch `https://api.crossref.org/works/<DOI>`** (URL-encode a trailing `+` as `%2B`); prompt for family-names / issued-year / title / journal / vol / page + **«NOT FOUND if error, NO outside knowledge»** — that guard is the HARD self-review gate against the model citing from its own memory (the #1 fabrication risk).
- **🔑 Crossref `issued` = the ONLINE year; a citation uses the ISSUE/volume year** → online/issue splits are NOT errors (Zafar 2012, Mano 2018 kept at issue-yr). A **DOI-suffix year is the acceptance year, NOT pub-yr** (`elecom.2022.107405` = Schachinger **2023** print, vol 146) — a classic mis-read.
- **A constant read from a SCANNED primary: read the page image, never the text layer — and make the script hold the transcription to the source.** An OCR'd scan can shift a digit into a perfectly plausible value (the NBS scan of Eden & Bates 1959 did it to malic acid's pK₁); where a source prints a formula and its value, pin one to the other — `67`'s `malate_check()` asserts the 25 °C constants against the equations and `test_cache_integrity` repeats it on the CACHE. ⚠️ **Same trap one level up — the COLUMN:** NEA-TDB tables print an as-reported and a re-evaluated `log K` side by side, and a research agent handed over the as-reported value as an end of the NEA spread; read the column header and the table's footnotes yourself before a number becomes a bound.
- **A set collected by a DELEGATED agent arrives without its PROVENANCE unless the brief demands it — the provenance is the QUERY, not the result.** When you delegate collection, require the command/URL/filters/date back with the data and commit them beside it. ⛔ Never reconstruct a plausible query after the fact: say in the data's README that it is missing, as `tools/in_silico/data/chem11_conservation/README.md` does.
- **A DATA attribution with no DOI and no artifact in the tree is an ASSUMPTION and is labelled one** (as `tools/in_silico/lib/xylem_sap.py` now labels its Pinus sylvestris profile).
- **The same question for an INSTRUMENT: a canon number that cites a script must have its run in the tree — ask «where are its script and its cache?»**
- Catches: wrong-year, wrong-author (Solomon was LAST author → cite Lee et al.), mis-attribution (the FAD-GDH E° scaffold said «Sygmund/Bioelectrochem»; truth = Schachinger/Ma/Ludwig, *Electrochem. Commun.*). Final ACS-numbered list = a mechanical last pass in a reference manager (founder's step).

## When Modifying

**Bodies live in `modifying.md` — open it before editing a script, a shared constant, a cache or a doc
that quotes one.** One generated line per item below; numbered 2026-09-18 in the pre-split order,
append-only since — cite `in-silico §When Modifying #N`.

<!-- INSILICO-MODIFYING-INDEX:AUTO — generated from modifying.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. Adding a ligand is a five-step chain, and skipping the last step leaves downstream MD stale
2. Change a SHARED or canon-mirrored constant only in `tools/in_silico/lib/constants.py`, then find every cached JSON that used it — a coefficient private to one script's model changes in that script
3. After any change run the in-silico tests, commit, then update every SSOT doc that quotes the result
4. Drift-proof comments/constants — never hardcode a mirror of another script's result; LOAD it from that script's cache JSON at runtime
5. A cache PROSE field (`verdict`, notes) is what docs quote — build every factual clause from the computed data, never type it
6. Its numeric twin: a cache NUMBER rounded for display is OUTPUT — never compute FROM that row
7. A contact station read off the FREE shape at FULL load is not an equilibrium
8. A control that cannot fail is not a control — say in the docstring what each assert CAN and CANNOT catch
9. A solver loop needs an explicit non-convergence branch (`for … else: raise`, plus a cycle detector on an active set), and its tolerances come from the MEASURED solve precision
10. A literature constant that does not EXIST at your conditions is not a number to pick — bound it by SIGN, then price it
11. Two primary readings that DISAGREE are a bracket of NAMED readings, never a pick — and a consumer's ceiling is the ADVERSE reading, cited
12. When a VERDICT replaces the canon premise a script priced, the script does not become stale — its premise does, and the two need different treatment
13. Applying a ratified NOMINAL is a MODEL change, not a key swap — and it can change WHICH extreme is binding
14. An input nudged to keep a model well-formed is a HYPOTHESIS about configuration — and it travels as a CLAIM on the output
15. Regenerating a cache is proven by a field-by-field diff against a backup — and when a swept coefficient becomes the operating point, the numbers must move linearly and boringly, and only the FLAGS may be interesting
16. Verify a doc value against its cache — the cache JSON is ground truth, and any computed number in a doc must match it
17. One cache per model — a cache written by several scripts silently reverts a verdict depending on run order
18. Post-recompute drift sweep: grep BOTH the new and the old value, because stale copies lag in four places
19. Re-gen a committed artifact after editing its generator, and `git status` it before the commit
20. Script-list One-Home: README = inventory (what + cost), SUMMARY = results, PIPELINE_STATUS = per-script status and volatile counts
21. Don't `git add -A` a still-warm background-compute output
22. A new DFT script imports `lib.constants` + `lib.utils` + `lib.dft_utils` and runs its SCF through `dft_singlepoint`, whose defaults already carry Critical Rules #4 and #5
23. A new MD script imports `lib.constants` + `lib.geometry` + `lib.utils`, protonates through `lib.md_utils.prepare_protein` and follows Critical Rule #6 for minimisation, pre-relax and ramp
24. New script — the number is a shared namespace (take the next free N from `ls scripts/`, never a remembered range), and the lattice's elastic knockdown is not this half's to compute
25. A model-feeding FORMULA can be wrong, not just a stale mirror

<!-- /INSILICO-MODIFYING-INDEX -->
