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
| `docs/00_02_Academic_Integration_and_IP.md` §1 | Мінаєв (DFT) + ЧМА Бушуєва (enzymes/EIS) validation; xylem sap (bio hub) — реєстр партнерів |
| `docs/00_02_Academic_Integration_and_IP.md` §2 | Publication plan — Стаття 1 (honest reframe 2026-06-05) |
| `docs/00_07_Action_Plan_Tracker.md` | HW.5.IS section — operational task status |
| `01_01 §1.4` / `01_01 §4.2` · `02_02 §2.2` · `00_07` HW.3 / HW.34 / HW.43 | Anchor-mechanics canon + verdict homes: `50`/`51`/`56` → the Zone1↔2 band window (§4.2, HW.3) · `55`/`68` → the bus wire and its liner (§1.4, HW.34) · `52`/`59` → the pogo contact (§2.2, HW.43) |
| `tools/in_silico/README.md` | Setup, quickstart, GPU notes, GAFF explanation |

**After completing ANY task in this pipeline — update ALL the SSOT docs above.**

## Script Dependency Graph

```
Parameterization (CPU, ~minutes):
  02 FAD → 03 GEN → 04 CSO → 05 CLB → 06 PPy → 07 PVI → 08 SBMA
           ↓
L2 MD (GPU):            ↓ SMILES change → rerun ALL downstream
  10 (baseline) ← 02,03
  11 (full matrix) ← 02-05    → 11* (10ns extended)
  12 (temp sweep) ← 02-05     → 4 temperatures
  13 (PSBMA diffusion) ← 08   → D_eff
  14 (xylem sap) ← 02-05      → 6 species

L3 DFT anode (CPU):
  20 (FAD) ──┐
  21f (Os B3LYP dimethyl, os_complex.json) ─┼── 22 (cascade verdict) ← rerun after 21f
  21d (Os ωB97X) ──┘
  28 (tunneling pathway) ← PDB only, no DFT deps
  29 (Nelsen λ) ← standalone (FADH₂•⁺ pathological → metal hops = ③) · 29b ← rescues 29 (FADH⁻/FADH• couple → anode inner-sphere λ_i 0.39 eV)
  21e (Os mediator Hammett series ①) ← 21b geometry
  32 (PCET E°) → 33 (PCET cascade) ← lumiflavin
  34 (micro-solvation ② cluster-continuum) ← 21b geom + hexaaqua + aqua/bis-Im speciation → 34b (ωB97X ΔSCF cross-check)

L3b DFT cathode (CPU):
  23 (ZIF clusters) → 24 (hopping t_ij, 3 pairs) → 25 (k_ET vs λ ③) ← 35 (metal λ, Nelsen 4-pt)
  24b (FO-DFT two-state coupling) = rigor upgrade of 24's crude t_ij → re-ran 25 [CHEM.14 ✅: t_ij 0.00546 eV + 0.18 eV site-gap → borderline robust to coupling, ×10⁵ excluded]

L4 Kinetics (CPU, seconds):
  30 (delta_t) → 30b (Monte Carlo) → 31 (EIS) → 40 (validation)

Bridge:
  27 (MD→DFT ensemble, FAD HOMO) ← 11 (DCD trajectory) + DFT
  28b (CHEM.16 tunneling ensemble ✅) ← 11 (DCD) + 28 (Beratan-Onuchic over frames) → β·d 2.02±0.13, thermally robust

Anchor mechanics (CPU; EDGES only — the roster is ls scripts/, never a list here):
  tools/cad/cem cathode_flange + zone2_sleeve → 55 (spans read at runtime) → 68 (importlib; 68 imports 55)
  55 + 68 share lib/beam_contact.py (one contact solver) → a solver change re-runs BOTH
  cem o_ring block (cathode_flange + radome) ↔ 52 (reads it back, refuses a mismatch)
  62 → wind_duty_cycle.json → 59 · 55 (cycle budget; 55 prints NOT COMPUTED without it)
```

## Critical Rules

**Bodies live in `rules.md` — open it before running or changing DFT/MD, declaring an anchor dimension,
or quoting a literature constant.** Below is one generated line per rule: the line is the CARRIER; the
mechanism, the incident and the bounds are in the companion. Numbering is append-only — cite
`in-silico §Critical Rules #N` (the section name disambiguates from §When Modifying).

<!-- INSILICO-RULES-INDEX:AUTO — generated from rules.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

0. `conda env list` in a non-interactive shell answers about ITSELF, not about the machine — ask the FILESYSTEM
1. Shared lib is SSOT — every constant, path and banner() comes from `lib/` and is never redefined locally
2. A SMILES fix cascades — fixing one in 02-08 means rerunning ALL downstream MD that uses that ligand
3. DFT: NEVER two heavy jobs on same CPU
4. No density_fit() for Os/Ce — the auto-generated aux basis for heavy metals is 3× SLOWER than standard integrals
5. Use level_shift=0.3 for open-shell transition metals — without it UKS on Os(III), Co-Ce and Ce oscillates forever
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
- **PCET with H₃O⁺/PCM** — PCM oversolvates small ions (H₃O⁺ by ~7 eV). Don't use for proton transfer corrections. Need explicit water for meaningful PCET.
- **FAD in MD topology** — GAFF renames FAD to "UNK", all atoms have "x" suffix. 86 atoms total, 53 heavy. Full FAD has odd electron count — set charge=1 for even.
- **Os mediator speciation matters (② / script 34)** — chloro vs aqua vs bis-imidazole shifts E°(Os III/II) by ~0.5 eV. On the **dimethyl device mediator** (+309 mV, Zafar 2012; OS-RECOMPUTE 2026-06-17) the ② frame is a **chloro(+1/+2)↔{aqua,bis-Im}(+2/+3) differential-solvation bracket**: chloro +0.21 (3 Cl⁻-waters, lower) ↔ bis-Im +0.55 / aqua +0.49 (upper), on the [Os(H₂O)₆] n6→n18 **+0.98 eV** benchmark; the +2/+3 couples carry the larger group-8 PCM bias. Decompose the cascade gap into speciation + solvation **+ the 4,4'-dimethyl substituent ① (+0.142 Koopmans / +0.149 adiabatic — method-dependent, NOT a stale +0.146)**; don't lump it. **chloro↔+2/+3 bracket is functional-ROBUST; the internal aqua↔bis-Im order is functional-SENSITIVE** (34b: ωB97X aqua>bis-Im, B3LYP-dimethyl bis-Im>aqua, <0.15 eV). No `density_fit` for Os, `level_shift=0.3` for the Os(III) UKS doublet. (Pre-recompute plain-bpy values −0.91/−0.61/−0.40 + the "+200 mV / aqua>bis-Im>chloro" framing are superseded.)
- **lo.PM / lo.Boys crash (PySCF `lib.einsum` version bug)** — `ValueError: not enough values to unpack (expected 4, got 3)` in `pipek.py`. For the 2-orbital FO-DFT localisation (24b) skip PySCF `lo` entirely: diagonalise the metal-projected 2×2 Mulliken population matrix in the {i,j} MO basis → rotation `R` → `H_ab` = off-diagonal of `Rᵀ·diag(εᵢ,εⱼ)·R` (Mulliken-Hush diabatisation, pure numpy; F is diagonal = ε in the orthonormal MO basis).

## MD Gotchas (Hard-Won Lessons)

- **10K pre-relaxation mandatory** — 500-1000 steps at 10K before NVT ramp. Without it → NaN on ~50% of runs with multiple ligands.
- **Fibonacci sphere placement** — deterministic (seed=42) but can create bad contacts at specific positions. 313K (40°C) particularly vulnerable — skip if NaN persists after 3 attempts (3/4 temps sufficient).
- **GAFF matching** — `GAFFTemplateGenerator` matches by graph structure. One `Molecule` per unique chemical species is enough.
- **L2 10ns RMSD ~4 Å is normal** — AF3 structures relax 3-5 Å under AMBER ff14SB for large enzymes. Check **Rg** (radius of gyration) — if stable → protein folded, RMSD is just conformational relaxation. Full equilibration needs 20-50 ns. ⛔ **A regression test pinning this against Apple's OpenCL fast-math was MEASURED and DECLINED** (2026-06-06, migrated here from `00_07` HW.5.IS on 2026-09-17): nice-to-have, and not needed for the RMSD-stability claims we actually make — the claims are about Rg staying flat, not about bit-level reproducibility of the trajectory. Recorded so the idea is not re-proposed as new work; it becomes live only if a claim starts depending on exact trajectory values.
- **25GB DCD files** — use `stride=10` or `stride=100` when loading with mdtraj. Full load kills memory.
- **PBC unwrap for ensemble graph analysis (CHEM.16 / 28b)** — a PBC-wrapped protein/cofactor splits a contact graph (artificial >cutoff gaps) → Dijkstra returns NaN. `make_molecules_whole()` makes each molecule whole but leaves a SEPARATE non-covalent cofactor (FAD) in a *different periodic image* → still disconnected (verified 1/15 frames). Use `traj.image_molecules(inplace=True)` (default anchor = largest molecule = protein) to co-locate everything into the protein's image (15/15 frames). Apply on the FULL topology, before `atom_slice`.

## Cascade Verdict Summary

**Verdict, no magnitudes:** cascade FAD→Os is verified **downhill** from measured E°s, while raw DFT comes out **uphill in every method** — that contradiction is a method limit, not a physics one. The gap is decomposed by ② into a **chloro↔+2/+3 differential-solvation bracket** (functional-robust; the internal aqua↔bis-Im order is functional-sensitive) + the **4,4'-dimethyl substituent**; rigorous closure = explicit-water QM/MM — ⛔ NOT Minaev's school (their angle is spin-orbit / O₂ activation, `00_02 §2.1`): own follow-up or a specialist computational-electrochemistry collaboration, TBD.

**The cascade VERDICT lives here; its magnitudes, its citations and the all-methods table live in `SUMMARY.md` §Cascade + `L3_quantum_chemistry.md`.** ⚠️ **That is a claim about THIS SECTION, not about the file** — and the distinction is load-bearing, because the wider version of this sentence was false the moment it was written (2026-08-22): `+309`/Zafar stand at the DFT-gotchas bullet, `−265` in the citations block, `+1.03` in the drift-sweep example. Those are legitimate — a gotcha narrative carries its value inline — but each one is a MIRROR, so it must name its home in the same breath. 🔴 **The lesson is about the FIX, not the file: cutting the instance while WIDENING the declaration is worse than leaving both**, because the reader then reads every other number here as native. Verify a value against `SUMMARY.md` before quoting it onward; `tools/in_silico/tests/test_doc_cache_sync.py` pins SUMMARY/PIPELINE/01_03 and does NOT reach this file. 🔴 **The magnitudes were CUT from the paragraph above on 2026-08-22, and that is the point of this note rather than tidiness: they stood two lines ABOVE this sentence, under a heading whose own words («check the cascade verdict») are the trigger that brings a reader here — so the reader took the number and never reached the line saying it is not kept here.** The declaration was flawless, the block was flawless, and only their RELATION was wrong; no check of either half can see that. It had already fired twice — the block silently carried the old +200/+465/−0.47 + plain-bpy ΔSCF until the 2026-06-18 dimethyl recompute, then "Schachinger 2022" until the 2026-06-19 Crossref fix → published-print 2023. **A router may carry the DIRECTION of a verdict (downhill / uphill / blocked); the moment it carries the number, it is a mirror, and this one feeds a TRL judgement.** Verified before the cut: `SUMMARY.md` §Cascade carries all six values and `L3_quantum_chemistry.md` 15 more.

## Paper Citations (DOI-verify)

Founder fully delegates citations/Zotero («все на тобі», no Zotero in his workflow) → **Crossref IS the arbiter; verify every DOI end-to-end.**
- **Recipe:** when the Bash network is sandboxed (curl times out) → **WebFetch `https://api.crossref.org/works/<DOI>`** (on 2026-09-13 `curl` reached NEA, NIST and GitHub directly — try it first when you need a full text to grep) (URL-encode a trailing `+` as `%2B`); prompt for family-names / issued-year / title / journal / vol / page + **«NOT FOUND if error, NO outside knowledge»** — that guard is the HARD self-review gate against the model citing from its own memory (the #1 fabrication risk).
- **🔑 Crossref `issued` = the ONLINE year; a citation uses the ISSUE/volume year** → online/issue splits are NOT errors (Zafar 2012, Mano 2018 kept at issue-yr). A **DOI-suffix year is the acceptance year, NOT pub-yr** (`elecom.2022.107405` = Schachinger **2023** print, vol 146) — a classic mis-read.
- **A constant read from a SCANNED primary: read the page image, never the text layer — and make the script hold the transcription to the source.** The NBS scan of Eden & Bates 1959 (malic acid) OCRs `1358.85` / `1658.53` as `1355.85` / `1655.53`, a 0.01 shift in pK₁ that looks perfectly plausible; the abstract prints the 25 °C constants beside the equations, so `67`'s `malate_check()` asserts one against the other and `test_cache_integrity` repeats it on the CACHE. Where a source prints a formula and its value, pin one to the other. ⚠️ **Same trap one level up — the COLUMN:** NEA-TDB tables print an as-reported and a re-evaluated `log K` side by side (Table VI-14), and a research agent handed over the as-reported `−8.77` as an end of the NEA spread; read the column header and the table's footnotes yourself before a number becomes a bound.
- **A set collected by a DELEGATED agent arrives without its PROVENANCE unless the brief demands it — the provenance is the QUERY, not the result.** Measured 2026-09-18 porting the CHEM.11 conservation instrument: the 332-homolog selection (BLAST · reviewed GMC family · UniRef50 · genus scan) came back as FASTA, and the exact REST queries survive in no transcript — so the sets are re-runnable AS COMMITTED and the recipe that produced them is not reproducible from the tree. ⛔ Do not reconstruct a plausible query after the fact: say in the data's README that it is missing, and say the same about any subset whose selection rule was never recorded (here: the 85 accessions the external MSA aligns). **When you delegate collection, require the command/URL/filters/date back with the data and commit them beside it.**
- **A DATA attribution with no DOI and no artifact in the tree is an ASSUMPTION and is labelled one** — `tools/in_silico/lib/xylem_sap.py` credited its Pinus sylvestris profile to «Spriahailo data» that exists nowhere, the ЧНУ bio-hub measurement still being pending (`00_07` HW.3, relabelled 2026-09-14).
- **The same question for an INSTRUMENT: a canon number that cites a script must have its run in the tree — ask «where are its script and its cache?»** CHEM.11 gated the enzyme order for ~3.5 months (06-06 → 09-17) on a proxy verdict whose script existed nowhere (`00_07` HW.5.IS).
- Catches: wrong-year, wrong-author (Solomon was LAST author → cite Lee et al.), mis-attribution (the FAD-GDH −265 mV scaffold said «Sygmund/Bioelectrochem»; truth = Schachinger/Ma/Ludwig, *Electrochem. Commun.*). Стаття-1 Intro = 41 DOIs, all Crossref-verified, zero fabrications. Final ACS-numbered list = a mechanical last pass in a reference manager (founder's step).

## When Modifying

**Bodies live in `modifying.md` — open it before editing a script, a shared constant, a cache or a doc
that quotes one.** One generated line per item below; numbered 2026-09-18 in the pre-split order,
append-only since — cite `in-silico §When Modifying #N`.

<!-- INSILICO-MODIFYING-INDEX:AUTO — generated from modifying.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. Adding a ligand is a five-step chain, and skipping the last step leaves downstream MD stale
2. Change a constant ONLY in `tools/in_silico/lib/constants.py`, then find every cached JSON that used it
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
15. When a swept coefficient becomes the operating point, diff the cache field by field: the numbers must move linearly and boringly, and only the FLAGS may be interesting
16. Verify a doc value against its cache — the cache JSON is ground truth, and any computed number in a doc must match it
17. One cache per model — a cache written by several scripts silently reverts a verdict depending on run order
18. Post-recompute drift sweep: grep BOTH the new and the old value, because stale copies lag in four places
19. Re-gen a committed artifact after editing its generator, and `git status` it before the commit
20. Script-list One-Home: README = inventory (what + cost), SUMMARY = results, PIPELINE_STATUS = per-script status and volatile counts
21. Don't `git add -A` a still-warm background-compute output
22. A new DFT script imports `lib.constants` + `lib.utils` + `lib.dft_utils`, uses `level_shift=0.3` for UKS and no density_fit for heavy metals
23. A new MD script imports `lib.constants` + `lib.geometry` + `lib.utils` and uses 10K pre-relaxation, a 10K ramp step and `maxIterations=10000`
24. New script — the number is a shared namespace
25. A model-feeding FORMULA can be wrong, not just a stale mirror

<!-- /INSILICO-MODIFYING-INDEX -->
