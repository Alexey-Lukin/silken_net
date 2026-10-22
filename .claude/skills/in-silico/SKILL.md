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
| `docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md §2.1` | Synthetic xylem sap — the RATIFIED recipe point and pH setpoint; owner-script `67`, doc↔cache pinned, and every salt concentration in `docs/protocols/` held to the live point by `test_sap_recipe_mirrors_match_the_live_point` — a moved point reds every letter that still carries the old one |
| `docs/00_02_Academic_Integration_and_IP.md` §1 | Partner registry: DFT-redox is self-owned (Стаття 1 goes WITHOUT an external collaborator — ⚖️ founder 2026-09-23, explicit-water QM/MM is its named limit; a collaborator is a follow-up option only) · in-vitro EBFC enzymology = profile biochemist/electrochemist, TBD · xylem-sap composition — no partner: the recipe point is ratified (pH from a primary source; the ions re-anchored ⚖️ 2026-10-18 on measured conifer sap — Norway spruce, not Scots pine — `01_02 §2.1`; our pine's own sap comes from the log-day logs, `00_07` HW.3) |
| `docs/00_02_Academic_Integration_and_IP.md` §2 | Publication plan — Стаття 1 |
| `docs/00_07_Action_Plan_Tracker.md` | HW.5.IS section — operational task status |
| `01_01 §1.4` / `01_01 §4.2` · `02_02 §2.2` / `02_02 §3.5` · `01_02 §2.2` · `00_07` HW.3 / HW.33 / HW.34 / HW.43 | Anchor-mechanics canon (ratified verdicts live THERE) + the open-work items: `50`/`51`/`56` → the Zone1↔2 band window (§4.2, HW.3) · `55`/`68` → the bus wire and its liner (§1.4, HW.34) · `52` → the Z-stack and the O-ring gland (`02_02 §3.5`, HW.33) · `59` → contact-part endurance (`02_02 §2.2` + `01_02 §2.2`, HW.43) |
| `tools/in_silico/README.md` | Setup, quickstart, GPU notes, GAFF explanation |

## Critical Rules

**Bodies live in `rules.md` — open it before running or changing DFT/MD, declaring an anchor dimension,
or quoting a literature constant or a source.** #19–#35 are the DFT and MD gotchas, #36–#46 the citation rules (§Paper Citations below routes there). Below is one generated line per rule: the line is the CARRIER; the
mechanism, the incident and the bounds are in the companion. Numbering is append-only — cite
`in-silico §Critical Rules #N` (the section name disambiguates from §When Modifying).

<!-- INSILICO-RULES-INDEX:AUTO — generated from rules.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

0. `conda env list` in a non-interactive shell answers about ITSELF, not about the machine — ask the FILESYSTEM
1. Shared lib is SSOT — every SHARED or canon-mirrored constant, every cache root and `banner()` come from `lib/` and are never redefined locally
2. A SMILES fix cascades — fixing one in 02-08 means rerunning ALL downstream MD that uses that ligand
3. DFT: NEVER two heavy jobs on same CPU
4. No density_fit() for Os/Ce — the auto-generated aux basis for heavy metals is 3× SLOWER than standard integrals
5. Open-shell transition metals can oscillate forever — `level_shift=0.3` stops UKS on Os(III), Co-Ce and Ce; it steers the PATH an SCF takes (hence possibly the state it lands on), not the orbital energies a converged run reports, so switch it on only where the SCF oscillates
6. MD goes NaN at the NVT ramp unless it pre-relaxes at 10K and ramps from 50K in 10K steps
7. MD trajectories are gitignored — commit only the JSON/PNG summaries
8. The CI smoke MD went NaN from BOX SIZE, not RNG — shrink the box (drop disordered tails), never just re-run or raise the iteration cap
9. Declaring an anchor dimension: name the REFERENT, not the number — and if canon gives a RANGE, say which end you took and why
10. A literature constant can be the right NUMBER in the wrong ROLE and of the wrong FORM — and the two errors compound silently
11. A part that enters a stack budget is judged on EVERY axis the envelope constrains, not on the axis the script was built for
12. Two scripts that model ONE physical part describe the same hardware only if they cite the same part number — each can agree with its own document while the pair describes two different parts
13. A THIRD-PARTY instrument writes "I did not measure this" with the SAME value it writes measurements — and nothing in our tree can see it, because the sentinel lives in that tool's code
14. A converged SCF certifies a STATIONARY POINT, not the ground state — the Newton rescue in `dft_singlepoint` converges from wherever the failed SCF stopped, and on an open shell that can be a spin-contaminated state the cache records as `converged: true`
15. A model of how a load TRAVELS between two parts is a list of paths before it is a number — inventory every coupling canon already defines between the two ends, and every load that does not depend on the one you set out to price, before computing any of them
16. A reduced-cofactor SMILES is a TAUTOMER claim, and the formula cannot check it — before a cascade runs on it, verify WHERE the hydrogens sit against the species the text names
17. A coupling taken as half the difference of two SCF solutions is a coupling only if the two states are CHARGE-LOCALISED and their difference clears the SCF tolerance — both halves fail silently, and the rate they feed is squared in the first and meaningless in the second
18. A converged GEOMETRY certifies a STATIONARY POINT, not a minimum — and a symmetric start has no gradient out of its symmetry plane, so it converges to the symmetric stationary point, which only a Hessian classifies
19. PySCF has no SDD basis — take `lanl2dz` for Cu and Co and `stuttgart_rsc` for Ce, which `lanl2dz` does not carry
20. PySCF does not run `wb97x-d` — use plain `wb97x`, whose range separation carries the fix; dispersion is the small part
21. ωB97X Koopmans orbital energies are not redox potentials — compare molecules by total energies (ΔSCF), never by their LUMOs
22. Adiabatic ΔSCF here is a composite — geometry at B3LYP/def2-SVP, single point at ωB97X/def2-TZVP — orders of magnitude cheaper than a full ωB97X optimisation
23. Cl on the Os complex's flat PES never meets the GAU displacement criterion, and a loosely converged minimum is read against the crystal ranges and every measured series
24. A PySCF version gap far above the SCF tolerance on a metal-in-PCM cache is a different Hamiltonian, not numerics — read every release in between before naming a cause
25. Optimise geometry only through `lib/dft_utils.dft_optimize` — PySCF's gradient omits the grid response by default and its own optimiser drops the convergence flag
26. Spin parity follows the electron count — an odd count takes an odd 2S, and `spin = mol.nelectron % 2` is only the fallback
27. Never put H⁺ or H₃O⁺ in PCM — a proton-coupled couple takes the thermodynamic proton reference that `32` and `33` share, not explicit water
28. GAFF renames FAD to «UNK» with suffixed atom names, and a truncated flavin fragment can come out odd — set its charge from the electron count
29. The Os axial ligand moves E°(III/II) by hundreds of meV, and the chloro↔{aqua, bis-Im} bracket is functional-robust while the aqua↔bis-Im order is not — quote ① WITH its method
30. `lo.PM` / `lo.Boys` crash on PySCF's `lib.einsum` bug — for the two-orbital FO-DFT localisation diagonalise the metal-projected population matrix instead
31. Fibonacci-sphere placement is deterministic yet can make a bad contact at one temperature — cure it with Critical Rule #6, never by dropping a temperature
32. `GAFFTemplateGenerator` matches a molecule by its graph structure, so one `Molecule` per unique chemical species is enough
33. A few-Å RMSD over an L2 run is normal relaxation of an AF3 structure — judge folding by Rg, and do not re-propose a bit-level trajectory pin
34. A full DCD load kills memory — read trajectories through mdtraj with a stride, never whole
35. A PBC-wrapped cofactor splits a contact graph — `traj.image_molecules(inplace=True)` on the FULL topology before `atom_slice`, not `make_molecules_whole()`
36. Verify every DOI end-to-end against Crossref, and when a fetch reads it, demand «NOT FOUND if error, NO outside knowledge» — the guard against citing from memory
37. 🔑 Crossref `issued` = the ONLINE year; a citation uses the ISSUE/volume year
38. A constant read from a SCANNED primary: read the page image, never the text layer — and make the script hold the transcription to the source
39. An HTML primary hides the same trap one layer deeper: an inline FORMULA can be an IMAGE, and the text layer drops it without a trace
40. A phrase you put in QUOTATION MARKS must be `grep`ed in the retrieved text before it ships — zero hits means the phrase does not exist, never «it is somewhere in the PDF»
41. A multi-column table is read by its HEADER on every lookup, not once
42. A set collected by a DELEGATED agent arrives without its PROVENANCE unless the brief demands it — the provenance is the QUERY, not the result
43. A number cited to ref N must have been read IN ref N — a sister paper of the same group that restates it is a DIFFERENT source, and an abstract sentence you matched is not the body
44. A DATA attribution with no DOI and no artifact in the tree is an ASSUMPTION and is labelled one
45. The same question for an INSTRUMENT: a canon number that cites a script must have its run in the tree — ask «where are its script and its cache?»
46. Check each reference for the error classes already caught here — a wrong year, a wrong lead author, a result credited to the wrong group

<!-- /INSILICO-RULES-INDEX -->

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
21a. An overnight SCF needs `caffeinate -i`, or macOS idle-sleep kills it — and the loss is silent
22. A new DFT script imports `lib.constants` + `lib.utils` + `lib.dft_utils` and runs its SCF through `dft_singlepoint`, whose defaults already carry Critical Rules #4 and #5
23. A new MD script imports `lib.constants` + `lib.geometry` + `lib.utils`, protonates through `lib.md_utils.prepare_protein` and follows Critical Rule #6 for minimisation, pre-relax and ramp
24. New script — the number is a shared namespace (take the next free N from `ls scripts/`, never a remembered range), and the lattice's elastic knockdown is not this half's to compute
25. A model-feeding FORMULA can be wrong, not just a stale mirror
26. In a stochastic pipeline the noise floor measured from REFERENCE replicates under-estimates the pipeline's own scatter — and the cheapest independent estimate sits where the perturbation does NOT act
27. A cluster BUILDER can orient a ligand by a quantity that is not the bond it must form — the accident holds only for the ligand it was tuned on, and CORRECTING it is where the real damage happens
28. A number you derive to CHECK a claim inherits an idealization, and the idealization — not the arithmetic — is what must be justified. Both instances below were MINE, both were arithmetically right, and one of them shipped into canon before I caught it
29. The SI manifest (`72`) hashes every committed file of its sections S1–S7 (env · scripts · lib · tests · caches · inputs · geometries · figures), so it is re-rendered LAST — after the final edit to anything it lists, including a file that did not exist when it last ran
30. A seasonal crossing counted as «the first run ≥ threshold from 1 January» calls a winter thaw spring — make the crossing SUSTAINED and declare that rule as ours, on BOTH edges
31. A pin over a numeric GENERATOR holds only in the environment that wrote its reference — and this pipeline now runs in THREE: the recorded osx-arm64 env writes the files, the lock pins a DIFFERENT RDKit on linux-64 than on osx-arm64, and CI runs the linux-64 one
32. A count against a threshold on QUANTIZED input has ties — and an iterative solver's tolerance decides them silently: return the degenerate root EXACTLY, and keep a control that equates the no-forcing run with its input
33. A cross-check that changes TWO things at once and AGREES may be two effects cancelling — before calling it robustness, look for the intermediate tier, which may already sit in another script's cache
34. An overnight run of NEW code is rehearsed before it is launched — every write target with a stubbed SCF, the geometry check BEFORE the SCF, and an adversary on the RUN PATH, not only on the record — and a chained link stays editable only until it STARTS, so fix inside that window and freeze what the run reads
35. Comparing a computed series with a measured one: on the SAME points, pair by pair first — a slope over several points restates the pair with the most leverage, and a «bracket» built on a point the other series lacks is not a comparison
36. Eliminating a cause with one-knob variants: declare the threshold before the data and count a move only TOWARD the measured; add a BOUND run that says whether the knob's whole family could carry the effect at all; and name the assumption under which «what remains» is what remains
37. A cache kept frozen ON PURPOSE stays frozen when one of its inputs moves — measure the sign once, write it beside the record, and repoint every LIVE reader of that input away from the record's module
38. A resolution control run on the LARGEST contact patch is blind to the smallest — the edge transition narrows with the load, so check the peak at BOTH ends of the load sweep; and where the number scatters with the grid for a reason you can name, gate the VERDICT it feeds, not the number
39. Judging your rows against ANOTHER script's threshold: compute its quantity for YOUR rows with ITS formula, inputs and pick — «my mean and my amplitude are each below its inputs» is not the threshold, and its inputs may sit at another play, geometry or definition of «mean»
40. When a quantity your verdict stands on has a COMPUTED and an ASSUMED value that disagree, the verdict is CONDITIONAL on it — publish the threshold at which it flips, per named reading, instead of picking the kind value and calling the other one an artefact
41. Before you apply a closed form to numbers taken from ANOTHER script's cache, name the two BODIES of that script's contact (or of whatever pair the formula is about) from ITS OWN `MODEL` section — never from the wording of the leg you are closing, and never from your mental picture of the part
42. A new script in this package must declare an English `SI_DESCRIPTION`, or the paper-SI generator refuses to render and the doc↔cache pin reds with it
43. A threshold quoted in a one-sided sentence is rounded toward the side that keeps the sentence TRUE, and the sentence is written so that side is the conservative one; and the statistic behind a physical «never» is checked for what it can SEE before it becomes the claim
44. A cap on a SERIES route is its WEAKEST link, and so is what follows from ONE part's limit («how far before it yields»); a link's give-way threshold needs THAT link's own compliance, or it comes out an order of magnitude low
45. «Conservative», «overstates», «the adverse end» is a claim about the DIRECTION of an error, and it needs a ground of its own — check that it does not rest on the datum you excluded, or on the input's extremes standing in for the output's
46. A sign claim over N cells that share one functional, one continuum, one reference convention and one relativistic treatment is ONE claim, not N — set its smallest margin against every shared term of known sign, the ones your own limits paragraph names included, before calling the sign robust
47. A design or precision table's degrees of freedom are an analysis READING, not a given — estimate the spread per contrast (robust if the arms differ) ⊥ pooled over the arms that measure the SAME quantity (licensed by a one-spread assumption the model already makes): publish both, and pool only across one quantity
48. A bound is about PHASES and bounds stiffness, not response

<!-- /INSILICO-MODIFYING-INDEX -->

## Cascade Verdict Summary

**Direction only:** the cascade FAD→Os is verified **downhill** from measured E°s. Raw DFT on the 1,5-dihydro FADH₂ (the chain's donor since 2026-10-15 — Critical Rule #16) comes out **downhill on the B3LYP-Koopmans offset (programmatic geometry; ≈ 0 on Os(III)'s own minimum), uphill on the adiabatic and the vertical ΔSCF and the PCET route** (the adiabatic ΔSCF read downhill only on the saddle its chain's planar start converged to — re-run from the minimum 2026-10-19; the Koopmans offset stands on the planar MMFF flavin, the shape that run shows to be a DFT saddle) — and none of these one-electron readings is like-for-like with the verified two-electron, two-proton driving force, so none of them measures «the gap». ⛔ «Uphill in every method» was a 4a,5-dihydro artefact — do not quote it (on the minimum its only counterexample left is the +0.068 programmatic-geometry Koopmans offset, −0.003 on Os(III)'s own minimum — and the like-for-like result does not rest on it); ⛔ nor read a Koopmans offset or a bare ΔSCF against −0.574 eV as a gap. The like-for-like comparison (2e⁻/2H⁺ FAD against each Os form on one SHE scale, `95`) is the paper's cascade result: **downhill in every form at every donor level within the protocol — spin–orbit coupling on Os, which it omits, reverses the device couple on one flavin level at the size ref 63 computes for [Os(bpy)₃] (the reading taken, ⚖️ founder 2026-10-20; the octahedral value is the upper count), so the protocol does not determine its sign (`95` `shared_shifts`) — its magnitude method-dependent, the gap attributed to no side, near-exact agreements named cancellations** (⚖️ founder 2026-10-16 «напрямок + таблиця»); the old decomposition of the 4a,5 one-electron gap into a solvation bracket + a substituent term is withdrawn; the magnitude needs explicit-water QM/MM, spin–orbit coupling on Os and a film model, a follow-up. **The verdict's home is `SUMMARY.md` §Anode («Conclusion») + `01_03 §3.4`; its magnitudes, its citations and the like-for-like table live there and in `L3_quantum_chemistry.md`.**

🔴 **A router may carry the DIRECTION of a verdict (downhill / uphill / blocked); the moment it carries the number it is a mirror — and this one feeds a TRL judgement.** A number set beside the verdict is taken from here, and the reader never reaches the line saying it is not kept here. Verify any value against `SUMMARY.md` before quoting it onward; the doc↔cache pins are `CHECKS` in `tools/in_silico/tests/test_doc_cache_sync.py`, and they reach the docs, never this skill.

## Paper Citations (DOI-verify)

Founder fully delegates citations/Zotero («все на тобі», no Zotero in his workflow) → **Crossref IS the arbiter; verify every DOI end-to-end.**

The rules are Critical Rules #36–#46 above (bodies in `rules.md`); cite them by that number.

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
  21f · 21d (the ωB97X Os caches) → 21g (adiabatic ΔSCF) · 33 (PCET cascade) · 21e `wb97x` (the centre pair of `vs_b3lyp`)
  34b (its chloro forms — ωB97X with the small basis) + its FORMS row (importlib) → 21e `wb97x` (`centre_decomposition`)
  21e `wb97x-631gd` (34b's tier at the axis ends; own cache) → 21e `wb97x` · `wb97x-compare` (`ends_decomposition`, read when it exists;
     `wb97x-compare` rewrites `vs_b3lyp` from the caches alone, no SCF)
  21e (default · os_mediator_series.json) → 21e `b3lyp-osdef2` (the same protocol, def2-TZVP/ECP on Os; own cache, `vs_lanl2dz`) · `b3lyp-iefpcm` ·
     `b3lyp-uffcavity` · `b3lyp-gas` (one knob each — the continuum's formulation · its radii · none; own caches, `vs_series`)
     · `b3lyp-pyaxial` (the axial N-donor) · `b3lyp-relaxed-os2` (the geometry: lib/dft_utils.dft_optimize, geomeTRIC)
  21e `b3lyp-relaxed-os2` (os_mediator_series_relaxed_os2.json — its accepted Os(II) point and geometry) → 21e `b3lyp-relaxed-os3`
     (Os(III) relaxed from it; own cache, `vs_vertical`; a moved Os(II) energy discards the record)
  21e (SERIES σ table, importlib · os_mediator_series.json) · 21f · 21d (the ωB97X centre caches) · 21e `b3lyp-osdef2`, the three
     continuum variants, `b3lyp-pyaxial`, `b3lyp-relaxed-os2` and `b3lyp-relaxed-os3` (read when each exists and holds its comparison; the donor reading
     needs every DONOR's adiabatic row, an acceptor is read only once both its rows exist — block `acceptors`) → 83 (computed ⊥ three measured series — ref 8's PVI polymers · MeCN · aqueous; writes os_series_vs_measured.json)
  lib/os_geometry.build_os_complex → 21e (Hammett ①) · 21f · 34 (cluster-continuum ②) · 34b (ωB97X ② cross-check) · 75 · 76 (`close_chelate=True` — the only caller)
  21f (importlib TIERS + os_complex.json) · 34 (ligands/os_hexaaqua.xyz) → 75 (lock-gap attribution; + reproduction/lock_rerun_2026-10-01.json)
  21f (importlib TIERS) · reproduction/lock_rerun_2026-10-01.json (the base) → 76 (C-min; writes reproduction/, runs ONLY in silken_lock)
  29 (Nelsen λ) standalone · 29b (semiquinone λ) → 29c (outer-sphere λ)
  32 (E°(FAD) · SHE_abs · the measured free flavin) · 21f · 34 · 21e relaxed (the dmbpy ΔE_red of each Os form) → 95
     (cascade_like_for_like.json — the cascade like-for-like, no SCF; a change to any of them re-runs 95)
  95 (`shared_shifts.terms.spin_orbit_os.first_flip_at_V`) · lib.constants OS_SOC_SHIFT_V · OS3_SOC_SPLIT_CM1 ·
     SRNEC_TABLE_S2_OS (ref 63's SI Table S2 Os rows — the calibration set) → 94 (os_soc_quenching_model.json — the t2g
     splitting that keeps every cell downhill with a quenched SOC, held to that table; no SCF); lib.constants
     OS_SOC_SHIFT_BIPY_V (the table's [Os(bipy)₃] row, ⚖️ (к) 2026-10-20 — the reading taken) → 95's `spin_orbit_os_ref63_bipy`
  20 (importlib: the RDKit/MMFF builder, checked against ligands/lumiflavin_{ox,red}.xyz) · 32 (importlib: the proton
     reference and SHE) → 32b (pcet_redox_potential_thermo.json + ligands/lumiflavin_*_opt.xyz); 32b → 95 (the donor at its four levels; 95 refuses when 32b's MMFF level is not 32's)
  lib/dft_utils.relax_to_minimum (the saddle escape: Hessian → step off → re-optimise; ONE home) → 32b · and through `relax_checked`
     → 21g · 33 · 29b — a change to the loop or its gates re-runs all four; 32b (pcet_redox_potential_thermo.json: the reduced
     flavin's minimum) → 33 (its FADH₂ control — same builder, protocol and escape)
  21e relaxed (os_mediator_series_relaxed_os2/os3.json — the dmbpy geometries, energies and acceptance) · 21e (importlib:
     _acceptance, OS3_MIN_OS_SPIN, VARIANT_MAX_CYCLE) · 32 (importlib: SHE) → 96 (os_couple_thermo.json — the Os couple
     at electronic · + ZPE · RRHO); 96 → 95 (`both_sided`, read when 96's cache exists) — a re-run of 21e relaxed re-runs 96, then 95
  28 (tunneling, PDB only) → 28b (CHEM.16) · 69 (CHEM.11)
  11 (DCD) → 27 · 28b
  69 → `69 --ratified` (own out-path, own reference sample; reads 69's OWN cache for the
     tie-built twin, so the ordered gene and the published build sit in ONE sample)
  70 (CHEM.11 site conservation) standalone — reads committed alignments in `data/chem11_conservation/`,
     never the network; it is the SECOND axis of CHEM.11 and is never merged into 69's patch score
  21 · 21b · 21c write their own caches; nothing downstream reads them — but 21b's LIGAND does travel:
     21b (its own copy of the Os constants, not lib/os_geometry) → ligands/os_bpy_im_cl.xyz → 21c · 21d

L3b DFT cathode (CPU):
  23 (ZIF clusters) → 24 · 24b      24 → 24b (FO-DFT, CHEM.14)      24 · 24b · 35 (metal λ) → 25 (k_ET vs λ ③)
  24 (importlib) + 25 → 24c → 24d      25 + 31 → 31b

L4 kinetics (CPU, seconds):
  lib/kinetics (MM + the [S]-dependent pH-ratio form; ONE home) → 30 · 30b · 85 — a change re-runs all three
  lib J_MAX_25C → 30 · 30b · 31 · 57      22 · 30 · 30b · 31 → 40
  67 (speciation, importlib) · lib J_MAX_25C · KM_GLUCOSE · ph_current_ratio → 85 (electrode_interfacial_ph.json — the pH at
     the coin electrodes' faces; a change to 67's speciation or to the L4 anchor re-runs 85) · tools/cad/cem → 85 (the
     anchor anode's envelope and its bore, at runtime — a change to anchor_zone1 or zone2_sleeve re-runs 85)

Paper: 60 (figures) · 61 (tables) read the L3/L3b caches — re-run them after any upstream change

Anchor mechanics (CPU):
  lib/mechanics → 50 · 51 · 55 · 56 · 77      lib/beam_contact (ONE contact solver) → 55 · 68 — a solver change re-runs BOTH
  tools/cad/cem → 52 (o_ring of cathode_flange + radome; refuses a mismatch — ⊕ since 2026-09-22 also the
     radome's `bell_radius_mm`, the SAME field that DRIVES the CAD crown, so the two machine halves share one
     number instead of each typing it) · 54 · 55 (spans read at runtime)
  55 → 68 (importlib + bus_mechanical.json)      54 → 64 (importlib + anchor_thermal_bridge.json)
  55 (importlib: endurance, SF line) · 68 (bus_contact_equilibrium.json) → 86 (coaxiality priced as a Soderberg mean; 55's cache is its control)
  55 (importlib: geometry, member EI, pogo force, µ sweep; bus_mechanical.json: the wear rows) · 68 (bus_contact_equilibrium.json:
     the coaxial bracket and the plays) → 91 (liner_exit_contact.json — the exit contact as an elastic layer; a change to 55's
     member or to either cache re-runs 91, and its cache test reads both CURRENT caches)
  91 (importlib: its kernels, rod and sweeps; liner_exit_contact.json — the no-offset control) · 55 (importlib: geometry, offsets,
     the flow-constraint sweep) · 68 (bus_contact_equilibrium.json — the offset and reversing tables its rigid control reproduces)
     → 92 (liner_mouth_contact.json — the mouth under an axis offset, two patches; a change to 91's kernels re-runs 92 too)
  92 (importlib: `solve(with_field=True)`, `drag_path`, TOLERANCE_OFFSET_UM — through it 91's kernels and rod, 55's geometry) · 86 (its
     Soderberg line, the form) → 97 (wire_under_liner_edges.json — the wire under the edges as an elastic half-space under the layer; a
     change to 92's solve or path re-runs 97, and its cache test re-reads 92's shipped-shank row)
  55 (importlib: spans from the CEMs, the liner, SF; bus_mechanical.json: the grip rows) · 86 (importlib: soderberg;
     coaxiality_allocation.json) · 87 (pogo_sway_transfer.json: the shift) · 90 (importlib: DAILY_*; pogo_thermal_gap.json:
     the L1 margins) · 77 (anchor_torque_path.json) · 78 · 79 (flange_cambium_heat/frost.json: the cambium extremes) → 102
     (wire_liner_shear_lag.json — the wire in its liner, root load and pad travel per share, on both spans)
  102 (importlib: Pair, soderberg_k; its cache: the grid, the flip CTEs, the hot preload per span) · 55 (importlib: spans,
     CEM shank Ø and length) · 77 · 78 · 86 · 87 → 103 (anchor_wood_share.json — the wood's share per bond state, the flange
     on the bark and on a Zone-3 fit); a change to 102's closed form or to the flange CEM re-runs 103
  102 (importlib: Pair, soderberg_k; its cache: temperatures, the share-0 seam control, the sway shift) · 103 (its cache:
     the composite, the shares, the (CTE, share) fronts, the seam corners it controls against) · 52 (importlib: TOL_PZ ·
     SPACER_STEP · SPACER_STEP_FINE · POGO_TRAVEL_TOL · rss; its cache: the L3 rung's residual) · 55 (importlib: spans, liner, CEM flange shank Ø; bus_mechanical.json: the grip rows)
     · 77 (anchor_torque_path.json: the sleeve section) · 86 · 90 (pogo_thermal_gap.json: the L1/L2 margins and residuals) →
     104 (pad_travel_remedies.json — the remedies' prices for the centre pad's travel, held and with the sway); a re-run of
     52, 90, 102 or 103, or a change to the flange CEM, re-runs 104
  87 (pogo_sway_transfer.json: the stem readings, the mass ceiling, the capsule envelope as the lever) · 102
     (wire_liner_shear_lag.json: the sway shift) · 103 (anchor_wood_share.json: its share caps, reproduced from its
     closed forms on its own depth grid; the sleeve stiffnesses, the bond bracket, the bearing area, the geometry and
     Zone-3 fit; the air-dry share read raw, not reproduced) · 52 (z_stack_tolerance.json: the applied gland) · 86
     (importlib: soderberg; through it 55's endurance markers, wrought derate and SF line) ·
     tools/cad/cache/fea/anchor_zone1_pine.json (the voxel-FE ratios, re-measured on the HW.33 geometry 2026-10-22 — 105 still reads the pre-verdict ones until its re-run; both Richardson readings in doubt both ways, the sweep itself not monotone — `00_07` HW.23) · tools/cad/cem (lock, flange, sleeve, pine
     anode) → 105 (printed_part_sway_stress.json — the sway stress in the anchor's titanium parts); a re-run of 87,
     102, 103, 52 or the FEA sweep, or a change to those CEMs, re-runs 105
  105 (importlib: richardson_p1, rms_factor, NU_SOLID; printed_part_sway_stress.json: the Richardson FE readings — the
     axial one in doubt from above, the radial neither shown nor excluded; the open leg `00_07` HW.23 re-measures both on a
     finer sweep, then sets how `105`/`106` read them (while they disagree, a bracket of named readings with the consumer's ceiling at
     the adverse one — §When Modifying #11) —, the solid
     fraction, the binds-above cells, the stem readings) · tools/cad/cache/fea/anchor_zone1_pine.json (ν and the rows
     105's readings are held to) · lib ALLOY_PROPERTIES → 106 (gyroid_wood_strain_share.json — the share t_L of the
     wood's strain the bonded gyroid takes; the Scots pine constants and the green Pinaceae proxies' transcriptions live
     in the script, a separate group from the Scots pine one); a re-run of 105 or the FEA
     sweep re-runs 106
  73 → 52 (collar_wall_inversion.json: the lug-root capacity the rim-clamp requirement is checked against)
  52 (importlib: POGO_TRAVEL · POGO_WIN; z_stack_tolerance.json `rim_datum_creep` · `applied_gland` rim cavity) · 55 (importlib: MU_SWEEP · D_BUS · INFINITE_LIFE_SF; bus_mechanical.json `interference_window.cold_press_fit`, the liner wall's ceiling) · 86 (importlib: soderberg; coaxiality_allocation.json, the seam k it carries the ceiling onto) · 77 (anchor_torque_path.json:
     the depth span) · tools/cad/cem (radome envelope) → 87 (pogo_sway_transfer.json); 59 quotes 87 by name only (its
     `missing_datum` string), never its cache
  52 (z_stack_tolerance.json: squeeze window, groove, `rim_datum_creep`) · 73 (collar_wall_inversion.json: lug-root rows) · 87
     (pogo_sway_transfer.json: the end-of-life O-ring need) → 88 (oring_reaction_band.json; the Parker Figure 2-4 transcription
     lives in the script) — 52 and 73 still read lib `GENEROUS_ORING_BOUND_N` until they re-run with the root package (00_07 HW.9)
  55 → 77 (bus_mechanical.json: the lock insertion window) · tools/cad/cem → 77 (gyroid · sleeve geometry at runtime)
  62 → wind_duty_cycle.json → 55 · 59 (cycle budget; 55 prints NOT COMPUTED without it)
  66 → tools/cad TopologyCrossChecks (a C# consumer: no Python re-run reaches it)
  51 → 71 (importlib: `capacitor_life_hours` — a kernel change re-runs 71 too) · tools/cad/cem → 71 (radome geometry at runtime)
  71 → 78 (importlib: the hourly capsule balance, checked against capsule_envelope.json) · 58 → 78 (importlib: layer
     properties + the cambium gate) · tools/cad/cem → 78 (flange Ø at runtime) — a change to 58's or 71's model re-runs 78
  71 · 74 · 78 → 79 (importlib: 71's convection kernels and hourly loader · 74's dew-point loader · 78's column grid and
     bark bracket) · tools/cad/cem → 79 (flange Ø and thickness, sleeve OD at runtime) · data/era5_cherkasy hourly cloud → 79
     (the real-cloud block, 2026-10-12) · 71's hourly DNI and the data header's grid point and clock → 79 (the beam block,
     2026-10-14) · data/era5_cherkasy hourly snow depth (ERA5-Land · CERRA) and the GHCN Lubny station file → 79 (ground-
     reflected light, 2026-10-17) — a change to any of them re-runs 79; ⚠️ 81 loads its weather through
     `S79.load_weather`, so the cloud file is 81's runtime input too (it does not use the cover)
  71 · 79 → 81 (importlib: 71's lump — geometry, convection kernels, loader · 79's sky emissivity and weather join, which
     carries 74's dew point; 79's cache is control 1, 71's control 3) — a change to 71's lump or 79's sky re-runs 81
  52 · 71 (importlib: POGO constants · the hourly capsule temperature, checked against 71's cache) · 82 → 90 (the pogo
     gap's thermal travel; radome CEM pocket floor) — a change to 52's chain, 71's lump or lib's CTEs re-runs 90
  71 → 98 (importlib: 71's hourly loader — the ERA5 10 m wind, fixed UTC+3; the field strain campaign's length replayed
     year by year per start month and its battery trips, power figures read in the two TreeMMoSys primaries) — a change to
     71's loader or the ERA5 file re-runs 98
  21e (importlib: SERIES; lib/os_geometry builder; os_mediator_series.json · _gas.json · _relaxed_os2/os3.json — their
     timed SCFs and relaxations) · 21f's ωB97X extremes (os_mediator_series_wb97x.json) · 34 (microsolvation_dmbpy.json —
     the open-shell upper reading) · 96 (os_couple_thermo.json — the RKS Hessian ratio) → 99 (coating_cluster_cost.json —
     basis sizes of coating clusters, SCF, relaxation and Hessian cost extrapolated from them, no SCF); a re-run of any re-runs 99
  52 · 71 · 73 · 82 · 88 → 89 (caches only, plus 88's `wall_for_force` by importlib and the radome CEM's lock-groove span:
     the bayonet clamp over its fit and temperature) — a change to any of the five re-runs 89
  52 · 71 · 73 · 81 → 82 (caches only: 73's socket band Ø · 52's collar chain and print floor · 71's capsule requirement ·
     81's cold edge; tools/cad/cem → 82, the slot clearance) — a change to any of the four caches re-runs 82
  52 (z_stack_tolerance.json: the RF-deck rows over the flange) · tools/cad/cem (cathode_flange's thickness) ·
     firmware/common/lora_phy.h (the carrier) · lib DBH_MIN_CM · BARK_DEAD_RIDGE_DBH38_MM → 107 (radio/stem_radio_shadow.json
     — the stem's radio shadow at 868 MHz; its permittivity readings live in the script); a re-run of 52 re-runs 107
  58 (T_PHLOEM, importlib — never its frozen L_A_INSERT, §When Modifying #37) · 78 (`bark_bracket`, importlib) · 31 · 31b (eis_model.json · cathode_det_rct.json — the
     electrodes' own R_int readings) · tools/cad/cem (anode, lock shank, sleeve, flange at runtime) → 84 (cathode_ionic_path.json —
     the R_Ω requirements; a change to any of them re-runs 84)
```
