---
name: in-silico
description: "Use when working on the silken_net in-silico surface — the EBFC Gen 2.0 Zero-Lab DFT+MD pipeline (tools/in_silico/, silken_md conda env): L1 AlphaFold-3 protein architecture, L2 OpenMM MD, L3 PySCF quantum-chemistry (ΔSCF redox cascade, Hammett mediator series, ZIF-cathode DET, cluster-continuum solvation), L4 kinetics/EIS, plus the Стаття 1 computes, and the 50–56 anchor-mechanics series (Lamé press-fit/thermal stress, pogo Z-stack RSS tolerance, Arrhenius EDLC aging + Kirkendall, bus buckling, per-alloy oxide-DET — lib/mechanics, §02/HW.* machine-half). Operational playbook — the script dependency graph, the hard-won DFT/MD gotchas (no density_fit for Os/Ce, level_shift=0.3 for open-shell metals, never two heavy DFT jobs per CPU, 10K MD pre-relaxation, thermodynamic proton reference for PCET), the conda-lock env, and the cache-is-SSOT discipline; routes to the 01_03 §3.4 + protocols/ebfc/in_silico canon, does not restate results. Examples: \"run or add a DFT/MD script\", \"why does the Os(III) SCF oscillate forever\", \"the FADH2->Os cascade comes out uphill\", \"set up the in-silico env\", \"why is density_fit slower for Ce\", \"add a ligand to the pipeline\", \"check the cascade verdict\", \"порахуй Z-stack tolerance\", \"онови Arrhenius aging модель\", \"press-fit Lamé для Zone1↔2\"."
---

# In-Silico Pipeline (EBFC Gen 2.0 Zero-Lab Proof)

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md §3.4` | Pipeline spec, TRL gate, L1-L4 definitions, artifact table |
| `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md` | Live status: running/queued/completed scripts, decision matrix |
| `docs/protocols/ebfc/in_silico/SUMMARY.md` | All L1-L4 results in one page |
| `docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md` | DFT details, cascade methods comparison, ΔSCF, L3b cathode |
| `docs/protocols/ebfc/in_silico/L1_protein_architecture.md` | AlphaFold 3 results, d_FAD distance |
| `docs/07_03_Academic_Integration_and_IP.md` §1 | Мінаєв (DFT) + ЧМА Бушуєва (enzymes/EIS) validation; xylem sap (bio hub) — реєстр партнерів |
| `docs/07_03_Academic_Integration_and_IP.md` §2 | Publication plan — Стаття 1 (honest reframe 2026-06-05) |
| `docs/00_07_Action_Plan_Tracker.md` | HW.5.IS section — operational task status |
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
```

## Critical Rules

1. **Shared lib is SSOT** — all constants, paths, banner() from `lib/`. Never redefine locally (19 local banners eliminated in refactoring).
2. **SMILES fixes cascade** — fixing a SMILES in 02-08 → rerun ALL downstream MD using that ligand. Check GAFF cache too.
3. **DFT: NEVER two heavy jobs on same CPU** — cache thrashing makes both 2× slower (observed: a 92-min solo job took 190+ min alongside another). Small molecules (H₂O, lumiflavin) OK to parallelize; MD-on-GPU alongside a CPU DFT job is fine (different hardware) — the hazard is two CPU-bound DFT jobs sharing cache.
4. **No density_fit() for Os/Ce** — auto-generated aux basis for heavy metals is 3× SLOWER than standard integrals.
5. **level_shift=0.3 for open-shell transition metals** — UKS on Os(III), Co-Ce, Ce without it → SCF oscillates forever (60h+ observed).
6. **MD NaN at NVT ramp** — 10K pre-relaxation (1000 steps at 10K) + start NVT from 50K + ramp step 10K (not 5K). Especially at high T (313K) and with many ligands. Use `maxIterations=10000` for minimization.
7. **MD trajectories gitignored** — only JSON/PNG summaries in `cache/dft/` and `cache/kinetics/` committed.
8. **CI smoke test** — `in_silico_smoke.yml`: CPU-only, padding 0.5nm, 500 min iterations, 40 min timeout. Deterministic anti-NaN gate (b8b506f): `seed=42` on BOTH the velocity draw and the Langevin thermostat + a 1000-step 10K pre-relax before the 298K run (the script-12-14 house pattern). The flaky `Particle coordinate is NaN` was unseeded RNG on a 500-iter-truncated box, NOT a regression — re-running the same code passes. Verify a touch here locally with the exact CI env (`SILKEN_FORCE_PLATFORM=CPU SILKEN_WATER_PADDING=0.5 SILKEN_MIN_ITERATIONS=500 SILKEN_MD_STEPS=100`).

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
- **L2 10ns RMSD ~4 Å is normal** — AF3 structures relax 3-5 Å under AMBER ff14SB for large enzymes. Check **Rg** (radius of gyration) — if stable → protein folded, RMSD is just conformational relaxation. Full equilibration needs 20-50 ns.
- **25GB DCD files** — use `stride=10` or `stride=100` when loading with mdtraj. Full load kills memory.
- **PBC unwrap for ensemble graph analysis (CHEM.16 / 28b)** — a PBC-wrapped protein/cofactor splits a contact graph (artificial >cutoff gaps) → Dijkstra returns NaN. `make_molecules_whole()` makes each molecule whole but leaves a SEPARATE non-covalent cofactor (FAD) in a *different periodic image* → still disconnected (verified 1/15 frames). Use `traj.image_molecules(inplace=True)` (default anchor = largest molecule = protein) to co-locate everything into the protein's image (15/15 frames). Apply on the FULL topology, before `atom_slice`.

## Cascade Verdict Summary

**Verdict, no magnitudes:** cascade FAD→Os is verified **downhill** from measured E°s, while raw DFT comes out **uphill in every method** — that contradiction is a method limit, not a physics one. The gap is decomposed by ② into a **chloro↔+2/+3 differential-solvation bracket** (functional-robust; the internal aqua↔bis-Im order is functional-sensitive) + the **4,4'-dimethyl substituent**; rigorous closure = QM/MM (Мінаєв).

**The cascade VERDICT lives here; its magnitudes, its citations and the all-methods table live in `SUMMARY.md` §Cascade + `L3_quantum_chemistry.md`.** ⚠️ **That is a claim about THIS SECTION, not about the file** — and the distinction is load-bearing, because the wider version of this sentence was false the moment it was written (2026-08-22): `+309`/Zafar stand at the DFT-gotchas bullet, `−265` in the citations block, `+1.03` in the drift-sweep example. Those are legitimate — a gotcha narrative carries its value inline — but each one is a MIRROR, so it must name its home in the same breath. 🔴 **The lesson is about the FIX, not the file: cutting the instance while WIDENING the declaration is worse than leaving both**, because the reader then reads every other number here as native. Verify a value against `SUMMARY.md` before quoting it onward; `tools/in_silico/tests/test_doc_cache_sync.py` pins SUMMARY/PIPELINE/01_03 and does NOT reach this file. 🔴 **The magnitudes were CUT from the paragraph above on 2026-08-22, and that is the point of this note rather than tidiness: they stood two lines ABOVE this sentence, under a heading whose own words («check the cascade verdict») are the trigger that brings a reader here — so the reader took the number and never reached the line saying it is not kept here.** The declaration was flawless, the block was flawless, and only their RELATION was wrong; no check of either half can see that. It had already fired twice — the block silently carried the old +200/+465/−0.47 + plain-bpy ΔSCF until the 2026-06-18 dimethyl recompute, then "Schachinger 2022" until the 2026-06-19 Crossref fix → published-print 2023. **A router may carry the DIRECTION of a verdict (downhill / uphill / blocked); the moment it carries the number, it is a mirror, and this one feeds a TRL judgement.** Verified before the cut: `SUMMARY.md` §Cascade carries all six values and `L3_quantum_chemistry.md` 15 more.

## Paper Citations (DOI-verify)

Founder fully delegates citations/Zotero («все на тобі», no Zotero in his workflow) → **Crossref IS the arbiter; verify every DOI end-to-end.**
- **Recipe:** the Bash network is sandboxed (curl times out) → **WebFetch `https://api.crossref.org/works/<DOI>`** (URL-encode a trailing `+` as `%2B`); prompt for family-names / issued-year / title / journal / vol / page + **«NOT FOUND if error, NO outside knowledge»** — that guard is the HARD self-review gate against the model citing from its own memory (the #1 fabrication risk).
- **🔑 Crossref `issued` = the ONLINE year; a citation uses the ISSUE/volume year** → online/issue splits are NOT errors (Zafar 2012, Mano 2018 kept at issue-yr). A **DOI-suffix year is the acceptance year, NOT pub-yr** (`elecom.2022.107405` = Schachinger **2023** print, vol 146) — a classic mis-read.
- Catches: wrong-year, wrong-author (Solomon was LAST author → cite Lee et al.), mis-attribution (the FAD-GDH −265 mV scaffold said «Sygmund/Bioelectrochem»; truth = Schachinger/Ma/Ludwig, *Electrochem. Commun.*). Стаття-1 Intro = 41 DOIs, all Crossref-verified, zero fabrications. Final ACS-numbered list = a mechanical last pass in a reference manager (founder's step).

## When Modifying

- **Adding a ligand**: script 0N (parameterize) → add to gaff_cache → SDF to ligands/ → add test → rerun downstream MD
- **Changing a constant**: `tools/in_silico/lib/constants.py` ONLY → check which cached JSON uses it
- **After any change**: `pytest tools/in_silico/tests/` → commit → update all the SSOT docs above
- **Drift-proof comments/constants** — never hardcode a mirror of another script's result (crude t_ij, single-snapshot β·d, an E°); LOAD it from that script's cache JSON at runtime (24b/28b do this) so it can't silently diverge. A **DERIVED aggregate (a Hammett LFER slope / fit) must ALSO be computed INTO the cache** (21e writes a `lfer` block), else cache-vs-doc tooling has nothing to diff against; and **read the canonical fit-set from the GENERATOR** — `60_paper_figures.py` excludes cf3 → slope −0.92, r²=1.00; blindly including cf3 gives −0.90 (a trap «тільки ретельно» caught)
- **Verify a doc value against its cache** — the cache JSON is ground truth; any computed number in SUMMARY/PIPELINE/01_03 must match it (caught SUMMARY §Cathode "Ce 0.87" = the *computed* λ, lit = 1.0). **A MODEL-SWAP recompute (plain bpy → dimethyl) leaves a SELF-CONSISTENT stale pocket that new-vs-old `rg` CANNOT catch** — no "+200 vs +309" to grep; the whole pocket (L3 §B frontier table + Marcus-verdict + L3→L4 gate-row + ωB97X-prose + PIPELINE 21b) was internally consistent on the OLD model (Os LUMO −4.23, Koopmans Δε −0.909, +0.808 shift). Only cache-vs-doc caught it: `os_complex.json` = dimethyl −4.086 ≠ doc −4.23. So **dump every headline cache (`json.load`) and diff vs the doc** — `rg` is necessary-not-sufficient; graphify saw the bpy↔dmbpy nodes but flagged 0 conflicts. [→ `98ba17d`, 2026-06-19] **[NOW AUTOMATED + CI-GATED]** `tools/in_silico/tests/test_doc_cache_sync.py` pins each headline number to its OWNER cache, **context-anchored** (regex on the surrounding label, NEVER a bare number — the SAME value is legit against different owners: cascade Δ −1.051 = `comparison.json` [script 22] vs −1.054 = `microsolvation_dmbpy.json` k0 [script 34]). Wired in `in_silico_smoke.yml` (`cache_doc_sync` job, stdlib-only). **Add a CHECKS row when you add a headline number**; manual dump-and-diff still for numbers not yet in CHECKS. Note: the substituent term ① is **method-dependent** — +0.142 Koopmans (dmbpy −1.0514 − bpy −0.909) vs +0.149 adiabatic (EA_plain 4.392 − EA_dmbpy 4.243); a stale +0.146 (unsourceable) masked a same-table clash until 2026-07-14.
- **Cache co-write hazard [RESOLVED 2026-06-19]** — `os_complex.json` was written by THREE scripts (`21` NH₃ + `21b` plain + `21f` B5 dimethyl — the tracker/PIPELINE said two), run-order-dependent → re-running the "wrong" one silently reverts the cascade verdict (a PAPER number: raw Δε −1.051 + the ① substituent decomposition). Fix pattern: **one cache per model** (21→`os_complex_nh3.json`, 21b→`os_complex_plain.json`, `os_complex.json` = 21f sole owner) + an **identity-guard** in the downstream reader (`22` asserts `osj["ligand"] == OS_DEVICE_MEDIATOR_LIGAND` from `tools/in_silico/lib/constants.py`; `60` already had a numeric `_close` guard) + a test pin. **Detect by scan, not eyeball** — a per-script out-path regex (`json.dump`/`.write_text` targets) lists every multi-writer file; a cache fed downstream (22/comparison/60) must have ONE owner. **Cousin bug — provenance drift:** the model-swap also left *attribution* stale — L3/PIPELINE kept crediting `os_complex.json` / the −4.09 dmbpy value to `21b` (or `21`) after `21f` took ownership; a value-only cache-vs-doc audit (98ba17d) misses it, only a script→cache ownership grep catches it. [→ 00_07 HW.5.IS, 2026-06-19]
- **Post-recompute drift sweep** — after a recompute moves a headline number (e.g. dimethyl Os ΔSCF +0.88→+1.03, 2026-06-17), the cache + SUMMARY headline update but stale copies LAG in four spots: paper prose / fig-captions that contradict their own tables (`03_results` led +0.88 while its Table 2 had +1.034), unflipped status annotations ("dimethyl pending B1" after B1 done), ASCII dep-graph labels ("BASELINE 60s" after →36s), and gate-summary lines. `rg` BOTH the new AND the old value across ALL of SUMMARY/PIPELINE/L3/01_03/07_03 + every `paper/*.md`. zsh gotcha: pass explicit file args — a space-joined `$VAR` is NOT word-split → "No such file", and a `||`-fallback then masks that error as "clean"; escape patterns, no bare `+` after `|`. This cache-vs-doc grep IS the numeric-drift tool — an LLM knowledge-graph (graphify) flagged **0** numeric drift on this same corpus (nav-only; the +0.88↔+1.034 conflict sat in two chunks it never compared). [5 lags caught → `e90071a`, 2026-06-18]
- **Re-gen an artifact after editing its generator** — a committed PNG/table can lag its script: changing a hardcoded anchor in `60`/`61`/`fig1` and committing without re-running ships a stale asset (the fig1 graphical-abstract carried the old +200/+465 anchors after a commit changed only the script — caught + re-genned 2026-06-18). Re-run the generator + `git status` the artifact before commit.
- **Script-list One-Home** — README = inventory (what + cost) · SUMMARY = results · PIPELINE_STATUS = per-script status + volatile counts. Update the RIGHT one; never mirror numbers across them (a past drift source: README ↔ SUMMARY both listed scripts)
- **Don't `git add -A` a still-warm background-compute output** — read + sanity-check it first (physical? expected range? n_valid? ≈ a reference?) before staging
- **New DFT script**: import from `lib.constants` + `lib.utils` + `lib.dft_utils`. Use `level_shift=0.3` for UKS. No density_fit for heavy metals.
- **New MD script**: import from `lib.constants` + `lib.geometry` + `lib.utils`. Use 10K pre-relaxation + 10K ramp step + `maxIterations=10000`.
- **New script — the number is a shared namespace**: `ls scripts/` for the next free N before creating `NN_*.py` (50–56 = anchor mechanics: 50 thermal · 51 gusak · 52 z_stack · 53 oxide-DET · 54 thermal-bridge · 55 bus-mech · 56 unified-Lamé). A blind `52_unified…` collided with the existing `52_z_stack_tolerance` → rename + ref-chase cost. [2026-06-22]
- **A model-feeding FORMULA can be wrong, not just a stale mirror** — when a canon claim rests on an in-silico number, verify the formula/model, not only re-run the value. `50`'s thermal Lamé divided by `(k²−1)` (a dropped rigid-outer-shell residual) → over-stated σ_t **4.3×** and propped up the canon "wall is CTE-limited / SF 3.4×"; it hid because the value looked plausible. **Tell:** a SIBLING formula in the same file (`contact_pressure`) used the correct rigid-inner denominator → the mismatch was the flag. Hoisted 50/51/56 onto `tools/in_silico/lib/mechanics.py`. [→ HW.3.IS, `b226ff3a`, 2026-06-22]
