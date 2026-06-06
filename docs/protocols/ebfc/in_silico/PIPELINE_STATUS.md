# In-Silico Pipeline — Operational Status & Dependencies

> **Last updated:** 2026-06-05 (② micro-solvation, script 34)
> **TRL 3→4 Gate:** ✅ PASSED (2026-05-25)

---

## Script Execution Status

> **Nothing running.** All scripts below are complete or closed. Volatile
> counts live here only (other docs link, not duplicate).

### ✅ Completed (numeric order — results in cache)

| # | Script | Result | Cache |
|---|--------|--------|-------|
| 01 | `smoke_test_water_box` | Engine works | — |
| 02 | `parameterize_fad` | FAD.sdf + GAFF | `gaff_cache.json` |
| 03 | `parameterize_genipin` | genipin.sdf | `gaff_cache.json` |
| 04 | `parameterize_chitosan` | chitosan_trimer.sdf | `gaff_cache.json` |
| 05 | `parameterize_cnc` | cellobiose.sdf | `gaff_cache.json` |
| 06 | `parameterize_ppy` | ppy_pentamer.sdf | `gaff_cache.json` |
| 07 | `parameterize_pvi` | pvi_trimer.sdf | `gaff_cache.json` |
| 08 | `parameterize_sbma` | sbma_monomer.sdf | `gaff_cache.json` |
| 10 | `genipin_stability_md` | **RMSD 1.20 Å** (correct C₁₁ genipin) | `runs/` |
| 11 | `full_matrix_md` | **RMSD 1.22 Å** (100ps); 10ns 4.02 Å, **Rg stable** → AF3 relaxation, not denaturation | `runs/` |
| 12 | `temperature_sweep_md` | **4/4 temps** 0.76–1.47 Å, all ≪3Å STABLE (313K NaN fixed) | `kinetics/temperature_sweep.json` |
| 13 | `psbma_diffusion_md` | D_eff=5.1e-4 cm²/s (monomer; L4 uses lit. 2e-6) | — |
| 14 | `xylem_sap_sweep_md` | **6/6 species** stable (pH 4.2–5.8) | `kinetics/xylem_sap_sweep.json` |
| 15 | `pvi_coverage_md` | RMSD 1.10 Å → PVI brush safe, no denaturation | `runs/` |
| 16 | `strain_cycling_md` | pseudoplastic (compress<stretch), PE drift 1.0% | `kinetics/strain_cycling.json` |
| 20 | `dft_lumiflavin` | HOMO(FADH₂) = -5.14 eV | `dft/lumiflavin.json` |
| 21b | `dft_os_bpy_full` | LUMO(Os III) = -4.23 eV (π-backbonding) | `dft/os_complex.json` |
| 21d | `dft_os_bpy_wb97xd` | **Adiabatic ΔSCF +0.884 eV** (uphill — raw DFT; verified cascade +466 mV → SUMMARY) | `dft/os_complex_wb97xd.json` |
| 22 | `compare_homo_lumo` | cascade Δε = -0.91 raw (uphill); verified −0.47 eV (→ SUMMARY) | `dft/comparison.json` |
| 23 | `build_zif_clusters` | 3 ZIF cluster XYZ | `ligands/` |
| 24 | `dft_hopping_integrals` | **3/3 pairs ✅** (geom-fixed) → k_DET **borderline** ×1–30 (λ-sensitive, scripts 25/35) | `dft/zif_hopping.json` |
| 27 | `md_dft_ensemble` | FAD HOMO **-5.589 ± 0.058 eV** (thermally robust, σ≪0.3) | `dft/md_dft_ensemble.json` |
| 28 | `electron_tunneling_pathway` | Beratan-Onuchic FAD→THR288, **β·d=2.05** (feasible) | `dft/tunneling_pathway.json` |
| 30 | `kinetics_delta_t` | delta_t = 36s healthy / 190s stressed | `kinetics/delta_t_lookup.json` |
| 30b | `kinetics_monte_carlo` | 90% CI: 14–120s | `kinetics/monte_carlo.json` |
| 31 | `eis_impedance_model` | Rct=130Ω, Rs=100Ω | `kinetics/eis_model.json` |
| 32 | `pcet_redox_potential` | E°(FAD/FADH₂) **-158 mV** (Δ50 mV vs free-flavin exp) — PCET valid w/ implicit solvent | `dft/pcet_redox_potential.json` |
| 33 | `pcet_cascade_semiquinone` | PCET cost +5.87 eV → cascade +1.48 eV, **does NOT flip downhill** (~1 eV = PCM solvation limit) | `dft/pcet_cascade.json` |
| 34 | `dft_microsolvation` | **② cluster-continuum**: [Os(H₂O)₆] n6→n18 **+0.98 eV** (benchmark), Cl⁻-solvation **+0.20 eV** (3 H₂O), speciation **aqua +0.51 / bis-Im +0.30 eV** → cascade gap = decomposed method limit | `dft/microsolvation.json` |
| 40 | `validate_vs_experiment` | predictions ready for Ti-coin CV/EIS | `kinetics/validation_report.json` |
| 50 | `thermal_stress_lame` | safety 9.9× at -30°C; press-fit P_c 34.7→22.6 MPa (stress relaxation, not creep); O-ring seals, barbs axial-only | `kinetics/thermal_stress_lame.json` |
| 51 | `gusak_degradation_model` | Arrhenius + Kirkendall V=1.12 µg/cm²/yr + H7/s6 | `kinetics/gusak_degradation.json` |

### ❌ Terminated / Closed

| # | Script | Why | Resolution |
|---|--------|-----|------------|
| 21 | `dft_os_bipy_complex` | NH₃ surrogate (no π-backbonding) | Superseded by 21b full bpy model |
| 21c | `dft_os_bpy_geomopt` | Cl displacement never converges (flat PES) | Programmatic geometry (21b) sufficient — LUMO Δ<0.002 eV |
| 29 | `dft_reorganization_energy` | λ: two methods both give E(n@R_cation) +160 eV — **FADH₂•⁺ radical-cation geometry pathological in implicit solvent** | **✅ RESCUED by 29b** (`semiquinone_lambda.json`): FADH⁻/FADH• couple → inner-sphere λ_i = **0.39 eV**, total ~0.7–0.8 w/ outer-sphere ≈ lit → L3 Nelsen-λ row |
| 29b | `dft_semiquinone_lambda` | **anode inner-sphere λ from first principles** — FADH•/FADH⁻ Nelsen 4-point (rescues 29) → **λ_i = 0.39 eV** (λ₁ 0.17 + λ₂ 0.22, site N18) | `dft/semiquinone_lambda.json` |

---

## Dependency Graph

```
Parameterization (CPU, done):
  02 (FAD) ──┐
  03 (GEN) ──┼── 10 (baseline MD) ──→ results
  04 (CSO) ──┼── 11 (full matrix MD) ──→ results
  05 (CLB) ──┘   12 (temp sweep) ──→ results
  06 (PPy) ──────── future: PPy steric test
  07 (PVI) ──────── future: PVI coverage test
  08 (SBMA) ─── 13 (PSBMA diffusion) ──→ D_eff
                14 (xylem sap sweep) ──→ species stability

DFT (CPU, done):
  20 (FAD HOMO/LUMO) ──┐
  21b (Os full bpy) ───┼── 22 (cascade comparison) ──→ verdict
                       │
  23 (ZIF clusters) ───┤
  24 (hopping ΔSCF) ───┘── L3b verdict (geom-fixed t_ij; k_DET borderline, λ-sensitive — scripts 25/35)

Kinetics (CPU, done):
  30 (delta_t) ──→ BASELINE 60s validated
  30b (Monte Carlo) ──→ 90% CI
  31 (EIS) ──→ Nyquist predictions

Validation:
  40 (vs experiment) ──→ ready for Ti-coin data
```

---

## Results Summary for Decisions

### ✅ Sufficient for Ti-coin Order (Stage 2)?

| Question | Answer | Evidence |
|----------|--------|----------|
| Does the enzyme fold correctly? | ✅ YES | L1: d_FAD = 15.998 Å < tunneling 18-20 Å |
| Does the matrix denature the protein? | ✅ NO (qualified) | L2 100ps: RMSD 1.11 Å. L2 10ns: RMSD 4.02 Å but **Rg stable** (-0.1%) → conformational relaxation from AF3, not denaturation. Needs 20-50 ns for full equilibration. |
| Does the electron cascade flow? | ✅ YES (verified) | +466 mV / −0.47 eV downhill (verified E°s); raw DFT uphill = method limit (②) |
| Is cathode DET fast enough? | 🟡 BORDERLINE | L3b geom-fixed t_ij + realistic λ → Cu-Co bottleneck ~turnover (×1–30, NOT the old ×10⁵); SUMMARY §Cathode |
| Is delta_t physically meaningful? | ✅ YES | L4: healthy 36s, stressed 190s, baseline 60s justified |
| Can we predict EIS results? | ✅ YES | L4c: Rct=130Ω, Cdl=50µF/cm² |

**Verdict: ✅ YES — sufficient to order Ti-coins.** Anode thermodynamic + kinetic proofs pass. Remaining in-silico items now done (L3b geom-fixed, genipin/deprotonation rerun, species sweep). The cathode-DET **borderline** finding (§Cathode) refines confidence — it does NOT block Ti-coins; rather it makes the Ti-coin **EIS the decisive empirical test** of the real cathode margin.

### ✅ Sufficient for Стаття (Q1 Publication)?

| Component | Status | What's Missing |
|-----------|--------|----------------|
| L1 protein architecture | ✅ Complete | — |
| L2 stability MD | ✅ Complete | Genipin ✅, temp sweep ✅ (4/4), PSBMA ✅, xylem sap ✅ (6/6), PVI ✅, strain ✅ |
| L3 anode DFT | ✅ Complete | ωB97X/def2-TZVP ✅ (adiabatic ΔSCF +0.884 eV); tunneling ✅; MD ensemble HOMO robust ✅ |
| L3b cathode DET | ✅ Complete (geom-fixed) | k_DET borderline (×1–30, λ-sensitive — a real finding, motivates Ru/cMOF/enzyme-free) |
| L4 kinetics | ✅ Complete | — |
| L4b Monte Carlo | ✅ Complete | — |
| L4c EIS | ✅ Complete | — |

**Verdict: ✅ Ready.** Q1 publication (школа Мінаєва): ωB97X/def2-TZVP adiabatic ΔSCF complete (B3LYP corrected -0.07 eV best estimate); L3b cathode complete (geom-fixed; k_DET borderline at realistic λ — a clean paper finding, motivates Ru/cMOF/enzyme-free); MD→DFT ensemble confirms thermal robustness; PCET via thermodynamic proton reference (script 32) validates the FAD/FADH₂ potential (within 50 mV of free-flavin). Closed limitations (both clean "limitations of implicit solvation" points for the paper): (a) Nelsen λ — script-29 (FADH₂•⁺) radical-cation pathological, **rescued by 29b** (FADH⁻/FADH• couple) → computed inner-sphere λ_i = **0.39 eV**, total ~0.7-0.8 w/ outer-sphere ≈ lit (→ L3 Nelsen-λ row); (b) PCET cascade reframing (script 33) does NOT flip the ΔSCF cascade downhill — the ~1.3 eV gap is mediator speciation + PCM differential-solvation (decomposed by ②, script 34), not proton coupling. **Authoritative cascade verdict = verified E°s (+466 mV / −0.47 eV downhill, Sygmund & Ludwig 2022); raw DFT uphill = quantified method limit (the «−0.07 ≈ −0.14» claim was withdrawn — built on a +60 mV FAD artifact).**

### ✅ Sufficient for Pitch / Investor Meeting?

**Verdict: ✅ YES.** SUMMARY.md has all numbers. Key claims:
- "EBFC Gen 2.0 validated in silico across 4 levels"
- "BASELINE_DELTA_T_S = 60s physically justified (Monte Carlo 90% CI: 14-120s)"
- "Electrode cascade E°(Os) − E°(FAD-GDH) = +466 mV (verified E°s, Sygmund & Ludwig 2022); raw DFT uphill = method limit decomposed by ②"
- "ZIF cathode DET computed at the electronic-structure level — borderline at realistic λ, with a clear low-λ-metal (Ru) / conductive-MOF improvement path"

### ✅ Sufficient for Мінаєв Meeting?

**Verdict: ✅ YES.** Key pitch points:
1. Pipeline PySCF+B3LYP+PCM runs end-to-end ✅
2. Full bpy model (54 atoms) closes π-backbonding gap ✅; ωB97X/def2-TZVP adiabatic ΔSCF **done ourselves** (+0.884 eV)
3. **Ask:** QM/MM with explicit solvation shell to overcome the **~1 eV PCM differential-solvation limit** we established via ωB97X adiabatic ΔSCF (raw DOWNHILL is unreachable with implicit solvent — proven, not pending)
4. **Ask:** CDFT hopping integrals for the full periodic ZIF lattice (our 24 used cluster ΔSCF; multi-week project)
5. Co-authored Q1 paper: "In Silico Design of Long-Lived Enzymatic Bio-Fuel Cells" — incl. a "limitations of implicit solvation" section (λ + cascade)

---

## What's Actually Blocking vs Nice-to-Have

### Blocking Nothing (all gates passed):
- ~~L3 geom opt~~ — terminated, sufficient
- ~~L4 Cantera~~ — replaced by scipy analytical model, validated

### Nice-to-Have (improve confidence, needed for publication):
- ✅ ~~Genipin rerun (scripts 10-11)~~ — DONE (RMSD 1.20/1.22 Å)
- ✅ ~~Temperature sweep (script 12)~~ — DONE 4/4 temps (263K-313K all stable, ≪3Å)
- ✅ ~~PSBMA diffusion (script 13)~~ — DONE (model limitation noted)
- ✅ ~~Xylem sap sweep (script 14)~~ — DONE 6/6 species (pH 4.2-5.8 all stable)
- ✅ ~~ωB97X DFT (script 21d)~~ — DONE. Koopmans Δε=-5.88 eV (RSH artifact). Adiabatic ΔSCF +0.884 eV (uphill — raw DFT; verified cascade +466 mV → SUMMARY).
- ✅ ~~L3b Co-Ce + Ce-graphene (script 24)~~ — DONE (geom-fixed t_ij; k_DET borderline ×1–30, scripts 24/25/35)
- ✅ ~~PCET potential + cascade (scripts 32, 33)~~ — DONE (potential -158 mV valid; cascade does not flip — PCM limit)

### Future (publication-grade, needs external compute / collaboration):
- QM/MM explicit-solvation shell (школа Мінаєв) — to resolve the ~1 eV PCM differential-solvation gap on the cascade + enable a true 4-point λ
- **FO-DFT coupling (CHEM.14):** in-house upgrade of script-24's crude State-A/B t_ij to a fragment-orbital H_ab (dimer-Fock projection) for the Cu-Co cathode bottleneck — no new dependency; the next ③-coupling rigor step (full CDFT needs PyCDFT = capstone).
- **Dynamic-tunneling ensemble (CHEM.16):** ✅ **done** (script **28b**) — the Beratan–Onuchic pathway (script 28) replayed over 15 MD frames gives β·d = **2.02 ± 0.13** ≈ the AF3 single-snapshot 2.05, with a conformational-gating factor of **1.03×** (modest). The path is **thermally robust**: the static single-snapshot is representative of the thermal ensemble (validates the §3.1 analysis), no significant thermal gating. PBC handled by mdtraj `image_molecules` (anchor = protein) — it co-locates the FAD cofactor (a separate non-covalent molecule) into the protein's image; `make_molecules_whole` alone leaves the FAD in a different image (1/15 frames only).
- **②-gap closers, COSMO-RS / MACE (CHEM.22/5):** verified **NOT** clean replacements for QM/MM on the charged Os(III/II) couple — openCOSMO-RS is neutral-molecule-validated (charged-metal blind spot); MACE-MP is a fixed-charge sampling MLIP, not a redox-ΔG method (it could only accelerate the sampling *within* a QM/MM). → don't add a dependency just for ②.

---

## Cross-References

| Document | What It Covers |
|----------|---------------|
| [`SUMMARY.md`](SUMMARY.md) | All L1-L4 results in one page |
| [`01_03 §3.4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | Pipeline spec + TRL gate |
| [`00_07`](../../../00_07_Action_Plan_Tracker.md) | Operational tracker |
| [`L3_quantum_chemistry.md`](L3_quantum_chemistry.md) | DFT details + L3b |
| [`L1_protein_architecture.md`](L1_protein_architecture.md) | AlphaFold 3 results |
| [`08_02`](../../../08_02_Academic_Institutions_Registry.md) | Synthetic sap protocol (bio hub) |
