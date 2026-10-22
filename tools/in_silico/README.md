# `tools/in_silico/` — Zero-Lab Computational Stack (L1 → L4)

This directory hosts the **Python-based simulation environment** for the EBFC
in-silico validation pipeline described in
[`docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md §3.4`](../../docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).

| Level | Tool | What we model |
|-------|------|---------------|
| **L1** | AlphaFold 3 (ESMFold — only if the AF3 licence position changes, `/NOTICE`) | Protein architecture — ✅ Passed 2026-05-24 (`d_FAD = 15.998 Å`) |
| **L2** | **OpenMM** (Python API) | Molecular dynamics — water box, pH 4.5, genipin/Os-polymer/CNC stability |
| **L3** | PySCF | DFT — HOMO/LUMO of Os redox polymer vs FAD cofactor + cathode DET hopping |
| **L4** | Python (scipy/numpy) | Reaction kinetics + EIS impedance → `delta_t` + Nyquist predictions |

SSOT artifacts (PDB structures, validation results, papers) live in
`docs/protocols/ebfc/in_silico/`. Scripts live in `scripts/` here.

## Scripts in `scripts/` (ordered)

> **Inventory only** (what each script does + cost). Per-script **status + result numbers** live in
> [`SUMMARY.md`](../../docs/protocols/ebfc/in_silico/SUMMARY.md) (results) and
> [`PIPELINE_STATUS.md`](../../docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md) (status) — this table
> links there, it does **not** mirror the numbers (SSOT One-Home; the mirror was a drift source).

| # | Script | What it does | Cost |
|---|--------|--------------|------|
| 01 | `01_smoke_test_water_box.py` | Engine sanity check — load protein (N-terminal tail dropped), water box, 1000 steps | ~70 s CI |
| 02 | `02_parameterize_fad.py` | AF3 PDB + CCD SMILES → `FAD.sdf` + cached GAFF params | ~4 min |
| 03 | `03_parameterize_genipin.py` | SMILES → `genipin.sdf` + cached GAFF params | ~7 s |
| 04 | `04_parameterize_chitosan.py` | Chitosan trimer (3×GlcN) → `chitosan_trimer.sdf` + GAFF cache | ~43 s |
| 05 | `05_parameterize_cnc.py` | Cellobiose (CNC proxy) → `cellobiose.sdf` + GAFF cache | ~15 s |
| 06 | `06_parameterize_ppy.py` | Polypyrrole pentamer (conductive copolymer) → GAFF cache | ~49 s |
| 07 | `07_parameterize_pvi.py` | Poly(vinylimidazole) trimer (Os-polymer backbone, no metal) → GAFF cache | ~106 s |
| 08 | `08_parameterize_sbma.py` | SBMA monomer (zwitterionic anti-biofouling) → GAFF cache | ~1 min |
| 10 | `10_genipin_stability_md.py` | Full L2 stability MD: protein + FAD + N×genipin in water, RMSD analysis | varies |
| 11 | `11_full_matrix_md.py` | L2-extended: protein + FAD + genipin + chitosan + CNC full matrix MD | varies |
| 12 | `12_temperature_sweep_md.py` | L2: full matrix at -10, 5, 25, 40°C → RMSD(T) curve | ~2.5 h GPU |
| 13 | `13_psbma_diffusion_md.py` | L2: glucose diffusion through SBMA slab → D_eff from MSD | ~1-2 h GPU |
| 14 | `14_xylem_sap_sweep_md.py` | L2: enzyme stability across 6 tree species (pH 4.2-6.0) | ~3-4 h GPU |
| 15 | `15_pvi_coverage_md.py` | L2 Gen 2.5+: PVI backbone steric (brush) test | ~1 h GPU |
| 16 | `16_strain_cycling_md.py` | HW.3.IS: cyclic ±5% strain on the genipin-chitosan-CNC matrix | ~30 min GPU |
| 20 | `20_dft_lumiflavin.py` | L3 DFT: FAD/FADH₂ frontier orbitals (B3LYP/6-31G(d)+PCM) | ~2 min |
| 21 | `21_dft_os_bipy_complex.py` | L3 DFT: Os mediator — NH₃ surrogate (baseline, superseded by 21b) | ~30 s |
| 21b | `21b_dft_os_bpy_full.py` | L3 DFT: Os mediator — full [Os(bpy)₂(1-MeIm)Cl] with π-backbonding | ~15-30 min |
| 21c | `21c_dft_os_bpy_geomopt.py` | L3 DFT: Os mediator — geometry optimization via PySCF + geomeTRIC (terminated — Cl flat PES) | ~6-12 h |
| 21d | `21d_dft_os_bpy_wb97xd.py` | L3 DFT: publication-grade ωB97X/def2-TZVP Os complex (adiabatic ΔSCF cross-check) | ~hours |
| 21e | `21e_dft_os_mediator_series.py` | L3 ①: Os 4,4'-substituent Hammett series (10× vertical ΔSCF) → LFER mediator design rule; `wb97x [names]` — ωB97X/def2-TZVP on the σ-axis ends + the `vs_b3lyp` comparison; `wb97x-631gd [names]` — the same at 34b's 6-31G(d) basis, own cache; one-knob variants of the B3LYP series protocol on bpy · dmbpy · ome · cl (the two relaxed ones also on no2; acceptors by name), each its own cache with a per-pair comparison — `b3lyp-osdef2` (def2-TZVP/ECP on Os), `b3lyp-iefpcm` (IEF-PCM), `b3lyp-uffcavity` (UFF ×1.1 cavity radii), `b3lyp-gas` (no continuum), `b3lyp-pyaxial` (pyridine for 1-MeIm as the axial N-donor), `b3lyp-relaxed-os2` (each point's Os(II) geometry relaxed with geomeTRIC, both states then at it; restarts from the saved geometry), `b3lyp-relaxed-os3` (each point's Os(III) relaxed from its relaxed Os(II) — adiabatic ΔE_red and λ_III, own cache) | ~30-60 min (B3LYP) · ~8–27 h per complex (`wb97x`; ×14–46 the B3LYP pair over six) · ~2–3 h per complex (`wb97x-631gd`) · ~80 min per continuum variant, ~50 min gas (four points, 2026-10-11) · ~1.5 h `b3lyp-pyaxial` · 3.4–10.0 h a point `b3lyp-relaxed-os2` (21.7 h the three, 2026-10-12; Cl 3.8 h · NO₂ 5.8 h, 2026-10-14) · 2.6–12.2 h a point `b3lyp-relaxed-os3` (16.1 h of optimisation the three donors, 2026-10-13; Cl 2.6 h, 2026-10-14; NO₂ 12.2 h in 53 steps, 2026-10-15) |
| 22 | `22_compare_homo_lumo.py` | L3 aggregator: Marcus cascade diagram + verdict | ~1 s |
| 23 | `23_build_zif_clusters.py` | L3b: bimetallic ZIF cluster models for DET hopping pathway | < 1 s |
| 24 | `24_dft_hopping_integrals.py` | L3b DFT: ΔSCF hopping integrals, crude State-A/B (Marcus ET rates through ZIF) | ~3-4 h |
| 24b | `24b_fodft_coupling.py` | L3b: FO-DFT two-state coupling t_ij for the Cu-Co hop (rigor upgrade of 24; loads zif_hopping cache for comparison) | ~hours |
| 24c | `24c_cu_ru_coupling.py` | L3b CHEM.32: Cu-Ru crude ΔSCF (Co→Ru @identical geom) + Cu-Co control; t_ij non-physical (see 24d) | ~2 h |
| 24d | `24d_fodft_cu_ru.py` | L3b CHEM.32: Cu-Ru FO-DFT diabatisation → t_ij NON-PHYSICAL (frontier all-Ru, no Cu-d partner); coupling-boost CDFT-pending | ~15 min |
| 25 | `25_cathode_ket_lambda.py` | L3b ③: Marcus k_ET vs **computed** λ — honest DET margin bracket — gap sign × λ(Cu) reading (reads 24 t_ij + 35 λ) | ~1 s |
| 27 | `27_md_dft_ensemble.py` | L3/L2 bridge: FAD HOMO across 5 MD snapshots (thermal-robustness check) | ~30 min |
| 28 | `28_electron_tunneling_pathway.py` | L3: contact-graph shortest path from the first FAD atoms (NOT a Beratan–Onuchic pathway — self-review cluster 6), single snapshot | < 1 s |
| 28b | `28b_tunneling_ensemble.py` | L3 (CHEM.16): a contact-graph cost over MD frames from script 27's GAFF-prefix sources (not 28's start; no path recorded — cluster 6; image_molecules PBC unwrap) | ~few min |
| 29 | `29_dft_reorganization_energy.py` | L3: Nelsen λ for FADH₂/FADH₂•⁺ — radical-cation pathological in PCM on the 4a,5-dihydro tautomer it ran on (superseded by 29b) | ~1-2 h |
| 29b | `29b_dft_semiquinone_lambda.py` | L3: Nelsen λ for the FADH⁻/FADH• anode couple (rescues 29 → inner-sphere λ_i 0.46 eV); geometries through lib `relax_checked` (Hessian per species, saddle escape) | hours (CPU) |
| 29c | `29c_outer_sphere_lambda.py` | L3: outer-sphere λ_o (Marcus two-sphere, analytical) → total anode λ; radius/ε-dominated → INDICATIVE | ~1 s |
| 32 | `32_pcet_redox_potential.py` | L3: PCET E°(FAD/FADH₂) via thermodynamic proton reference | < 1 s |
| 32b | `32b_pcet_redox_thermo.py` | L3 (HW.5.IS, the like-for-like revision): E°(FAD/FADH₂) with B3LYP/6-31G(d)+C-PCM relaxed geometries and harmonic thermochemistry (analytic C-PCM Hessian), one knob at a time — geometry · ZPE · RRHO free energy; the shared protocol is first checked against 20's cache; a saddle met on the way is escaped along its imaginary modes and kept in the record with its height over the minimum; `--rehearse <dir>` runs the whole path at STO-3G writing only into `<dir>`. Writes `cache/dft/pcet_redox_potential_thermo.json` and `ligands/lumiflavin_{ox,red}_opt.xyz` | hours (CPU, sequential) |
| 33 | `33_pcet_cascade_semiquinone.py` | L3: PCET-corrected cascade via neutral semiquinone (does not flip downhill; a one-electron route, not like-for-like, and the paper draws no conclusion from it); geometries through lib `relax_checked` (Hessian per species, saddle escape) | hours (CPU) |
| 34 | `34_dft_microsolvation.py` | L3 ②: cluster-continuum micro-solvation + speciation (chloro/aqua/bis-Im + [Os(H₂O)₆] second shell) → the Os forms of the like-for-like cascade (95) and the size of the continuum error on a small +2/+3 couple (the gap decomposition is withdrawn) | ~hours |
| 34b | `34b_wb97x_speciation.py` | L3: ωB97X ΔSCF cross-check of the ② speciation trend (functional-robustness) | ~hours |
| 35 | `35_dft_metal_reorganization.py` | L3b ③: computed inner-sphere λ for the ZIF metal hops (Nelsen 4-point on [M(H₂O)₆]) | ~hours |
| 30 | `30_kinetics_delta_t.py` | L4: EBFC kinetics → delta_t(glucose, temp) → growth_points directly (NOT β-perturbation — reversed, 00_07 E.63) | ~1 s |
| 30b | `30b_kinetics_monte_carlo.py` | L4b: Monte Carlo uncertainty (10k samples) → 90% CI for delta_t **at the pH-7.4 ceiling**, with the sap-pH 5.5 band printed beside it (⚖️ 2026-09-18 shape, applied here 2026-09-21) | ~1 s |
| 31 | `31_eis_impedance_model.py` | L4c: EIS Randles circuit → Nyquist/Bode predictions for Ti-coin tests | ~1 s |
| 31b | `31b_cathode_det_rct.py` | L4c ③: cathode DET R_ct band (the k_DET bracket's corners × unknown Γ) → kinetic competition, not a fixed Rct; INDICATIVE | ~1 s |
| 40 | `40_validate_vs_experiment.py` | Ti-coin Stage 2: compare in-silico predictions vs experimental CV/EIS (MM `j_max`, area-normalised `R_ct`) + the `V_OC`/`R_int` acceptance gates + the per-arm gates C · D · E (geometric mean judged, lower bound printed; E against full recovery minus the lab's repeatability band) | ~1 s |
| 50 | `50_thermal_stress_lame.py` | HW.3 anchor: Lamé thermal stress + Findley creep | ~1 s |
| 51 | `51_gusak_degradation_model.py` | HW.3 anchor: Arrhenius aging + Kirkendall V/Al/Nb/Zr diffusion (Nb, Zr on a placeholder D) + H7/s6 window | ~1 s |
| 52 | `52_z_stack_tolerance.py` | HW.8.7 anchor: 2-spring blind-mate Z-stack tolerance (pogo, O-ring) | ~1 s |
| 53 | `53_oxide_det_per_alloy.py` | HW.24 coin: per-alloy native-oxide DET feasibility (Ta DET-risk pre-coin) | ~1 s |
| 54 | `54_anchor_thermal_bridge.py` | HW.34 anchor: central bus thermal bridge through the PEEK break (Cu vs Ti-monolithic) | ~1 s |
| 55 | `55_bus_mechanical.py` | HW.34 anchor: bus rod buckling + sway fatigue (supported-by-liner vs bare, per alloy) | ~1 s |
| 56 | `56_unified_press_fit_lame.py` | HW.3.IS anchor: unified thick-wall Lamé — combined thermal + press-fit (SF 5.6×) | ~1 s |
| 57 | `57_gdl_breakthrough.py` | HW.25 cathode: PTFE-GDL liquid-entry pressure (Young–Laplace) + O₂ diffusion budget | < 1 s |
| 58 | `58_thermal_install_field.py` | HW.6 install: 2D axisymmetric thermal field → cambium safety + generator for the 1D orphan cache | ~13 min |
| 59 | `59_contact_endurance_check.py` | HW.43: endurance-limit literature review for the three contact/elastic parts (pogo spring, genipin matrix, PEEK barbs) — closed form, no FEA; the question is the acceptance unit | < 1 s |
| 60 | `60_paper_figures.py` | Стаття 1 figures from cache (+PDB for Fig 2): Fig 2 DRAFT / 3 / 4 / 5 + S1; canon-asserted → `paper/figures/` | ~4 s |
| 61 | `61_paper_tables.py` | Стаття 1 Tables T1–T4 from cache (canon-asserted, no DFT) → `paper/06_tables.md` | ~1 s |
| 62 | `62_wind_duty_cycle.py` | HW.43: wind duty-cycle for the Cherkasy pine forest from the committed NASA POWER record (daily WS10M) — bounds the trunk-sway cycle count | < 1 s |
| 63 | `63_delta_t_aux_power_sensitivity.py` | HW.42: does a second (TEG) power source on the shared BQ25570 rail contaminate `delta_t` — closed-form P_aux 10-200 µW sensitivity bracket | ~1 s |
| 64 | `64_teg_across_peek_break.py` | HW.21: may a Bi₂Te₃ TEG be mounted ACROSS the Zone-2 PEEK break instead of glued to bark — imports script 54's ladder + a `G_TEG` branch, thermal gate vs own Seebeck output | ~2 s |
| 65 | `65_zif_radiosensitization.py` | HW.22: does the ZIF nanozyme radiosensitise the enzymes under Co-60 — closed-form Compton/CSDA transport, no DFT | < 1 s |
| 66 | `66_gyroid_ligament_thickness.py` | HW.33: thinnest printed feature of a gyroid per topology (sheet vs network) at fixed porosity → minimum printable period | ~2 min |
| 67 | `67_sap_recipe_saturation.py` | HW.3: calcium oxalate saturation of the `01_02 §2.1` synthetic sap — corner scan per test band, admissible Ca × oxalate window on a constant-free hard bound, base and buffer prices; the live pine point (Q7) and the broadleaf point for `85` (Q8, beech trunk-base sap transcribed from Glavac 1990, with oak's own *Q. rubra* reading) | ~13 s |
| 68 | `68_bus_contact_equilibrium.py` | HW.34 / HW.23: bus rod in the cathode channel solved as unilateral contact (FE + active set) — where the wall is met under pogo drag, and what a channel off the root axis costs, swept over the Zone-1 insertion placeholder and lock window | ~10 s |
| 69 | `69_chem11_aggregation_compensation.py` | CHEM.11: the hydrophobic-SASA proxy `L1 §2` cites but never had — declared, swept over radius and residue set, and read against the whole protein surface; then per hotspot the admissible Asp/Ser compensations, each built with pdbfixer and minimised side-chain-only, with the FAD-pocket / electron-path / burial / DSSP refusals priced in Å² | ~9 min |
| 69 | `… --ratified` | CHEM.11: the ORDERED gene (`L1 §2` mirror in `lib/constants.py`) built as ONE sequence with the tie-built twin beside it in the same protonation sample, against its own reference replicates — own cache, because the flag swaps the model | ~2 min |
| 70 | `70_chem11_site_conservation.py` | CHEM.11: residue conservation at the freeze positions (70 · 80 · 401 · 405) of the aglycosylated dgrFAD-GDH over a committed homolog selection — the catalytic His537/His580 as the instrument's positive control, the 401 reading checked for clade locality, gap-penalty robustness and against an external MSA; position 201 carried as a `refused_candidate` so a burial-threshold refusal is judged on the same axis that lifted the `I401S` hold | ~10 s |
| 71 | `71_capsule_thermal_envelope.py` | HW.37: the hottest hour of a Soldier capsule under its PEEK radome over 30 ERA5 hourly Cherkasy years (lumped balance; α swept — the finish is specified as α ≤ 0.5 since 2026-09-27, `02_01 §5.2`; this sweep is its first basis, the cambium under the flange (`78`) the second) against the EDLC operating rating, the temperature the EDLC ages at (life via `51`'s kernel) and the cold hours under its floor | ~9 s |
| 72 | `72_paper_supporting_information.py` | Стаття 1 Supporting Information — a generated MANIFEST of the committed tree (recorded env + lock · every script/lib/test · every committed cache · input data · coordinates incl. the AF3 carve-out · figures with their renderer), sha256 per file; `--bundle out/si [--zip]` copies the set for upload; pinned to its output by `test_paper_si_matches_its_generator` | ~1 s |
| 73 | `73_collar_wall_inversion.py` | HW.33: what wall the bayonet collar needs — by INVERSION, because the retention FORCE has no home in canon (02_02 §4.1 lists requirements without one, and the 100 N in `lib.constants`, shared with `52`, is a deliberately generous BOUND, not a measurement). Three load cases: collar ring in axial tension · lug-root shear · CONFINED ICE at its self-limiting ceiling (ice I/III/liquid triple point). Verdict: static does not size the wall (printability does — ⊕ 2026-10-13: at the nominal squeeze; at the window top `88` asks more, a conditional root-package member, and `89` grows it with the loop's stiffness), ice does — and not by thickness, so drainage is the only lever | ~1 s |
| 74 | `74_site_rain_dew.py` | HW.25 + HW.6: site climate of the Cherkasy ERA5 grid point 1991–2020 — wet-day share and wet-day intensity, dew nights and hours (air criterion) for the rain/dew stand, and the dates at which published xylogenesis thresholds (soil 3.5 °C, air 8–9 °C) are crossed SUSTAINEDLY (a winter thaw is not spring, a warm wave after weeks of cold is not the end of the season), for the install season; an orientation and an input, never a stand regime or a window | ~1 s |
| 75 | `75_pcm_ecp_radius_attribution.py` | HW.5.IS: attributes the conda-lock gap of the metal-in-PCM couples to the PCM ECP-radius fix of PySCF 2.13.0 (PR #3159) — the `21f` B3LYP couple in the recorded 2.11.0 with the fix EMULATED, and [Os(H2O)6]2+/3+ as 2.11.0 as-is ⊥ fix emulated ⊥ the lock interpreter; reads `cache/reproduction/lock_rerun_2026-10-01.json`, writes `cache/reproduction/pcm_ecp_radius_attribution.json`; needs `--lock-python` | ~36 min |
| 76 | `76_os_chelate_sensitivity.py` | HW.5.IS C-min: the `21f` B3LYP couple (its own tier, imported) with both bpy chelates CLOSED onto the builder's targets (`build_os_complex(close_chelate=True)` — refuses an unrealised chelate), against the lock re-run of the default pair; runs in `silken_lock` and refuses another PySCF or a default geometry other than the committed one; reads `cache/reproduction/lock_rerun_2026-10-01.json`, writes `cache/reproduction/os_chelate_sensitivity.json` + `ligands/os_dmbpy_meim_cl_closed.xyz` | ~27 min |
| 77 | `77_anchor_torque_path.py` | HW.26: the torque path onto the anchor's OWN axis — the measurement that decided the anti-rotation fork `01_01 §4.3` C on its wind ground. Analytic: stem bending puts no rotation gradient along a radial anchor, stem TORSION does (ω_r = −½·r·φ′), and against the rigid-inclusion turning stiffness 4πGa² the wood modulus cancels; inverted for the stem-surface torsional shear stress τ_s* at which the shank↔sleeve press-fit slips (Lamé P_c from `lib.mechanics`, relaxed, at 20 °C and +40 °C; μ bracketed — unmeasured). Q2 estimates the demand at its CAP (green shear strength, Wood Handbook 2010 pines — species means, directions declared): the slip at the shank surface at the centroids and its peak at the sleeve's bark end (the sleeve's torsional decay length on wood, a few mm, says it follows its local wood), the rigid-part demand (compliant parts lower it), and the clearance below which a hex key would engage, beside the PEEK↔Ti swing of that clearance. Reads the CEM manifests and `55`'s lock window; writes `cache/mechanical/anchor_torque_path.json` | ~1 s |
| 78 | `78_flange_cambium_heat.py` | HW.6: the flange → cambium path under the flange ring Ø15–Ø29.8 since the 2026-10-03 seat on faced dead bark. 1D Crank–Nicolson column (dead bark → phloem → sapwood; layer properties and the cambium gate from `58`) driven by `71`'s hourly capsule temperature — recomputed with `71`'s own code (importlib) and checked against `capsule_envelope.json` — over `71`'s α sweep, both of its cases and two winds; a closed-form scheme check (24 h wave on a half-space) runs first. Inverts the finish α and the dead-bark floor at which the cambium reaches the gate. Writes `cache/thermal/flange_cambium_heat.json` | ~3–4 min |
| 79 | `79_flange_cambium_frost.py` | HW.6: the frost half of the flange → cambium path. `78`'s grid with a surface energy balance in place of an imposed temperature — convection (`71`'s Churchill–Bernstein and Churchill–Chu, called with |ΔT|; a vertical-plate Churchill–Chu for the stem), long-wave exchange with a clear (Brutsaert 1975 from the ERA5 dew point) or overcast sky, and optionally ERA5 diffuse sun — stepped fully implicit (Crank–Nicolson rings on a balanced surface half-cell), one banded factor per bark side shared through Sherman–Morrison; runtime gates: a step against Incropera eq. 5.60, a diurnal wave against Crank–Nicolson, the substep count against 6× on the coldest real window and on three beam windows, and over the whole 30-year series against 3× (Richardson). Sky × sun × coupling ends; reports the daily-minimum shift against bark without the flange, a mechanism block and three sensitivities; ⊕ a real-cloud block (2026-10-12) — ERA5 hourly cover from `data/era5_cherkasy/hourly_cloud_1991_2020.csv.gz` mixing the sky ends through two long-wave forms, with a month-by-month split; ⊕ a beam block (2026-10-14) — ERA5 DNI on a trunk face swept over eight azimuths through NOAA GML's solar position, the data clock checked against the DNI itself, hours of cambium above ≈ 13 °C counted beside the shift; ⊕ ground-reflected light (2026-10-18) riding with the beam — snow on the ground from `data/era5_cherkasy/hourly_snow_era5_land_1991_2020.csv.gz` and `hourly_snow_cerra_1991_2020.csv.gz` checked against the GHCN Lubny station file, albedo from Baker et al. (a mean and a sample cutoff), two ends of the input. Writes `cache/thermal/flange_cambium_frost.json` | ≈ 6.4 h beside a DFT Hessian (16 substeps/h, 2026-10-18); alone not re-measured |
| 82 | `82_collar_running_clearance.py` | HW.33 · HW.9 root package (crown-pause exception, ⚖️ 2026-10-05): the radial running clearance of the bayonet collar in the radome's socket band — the member `52` §collar_radial_budget has no number for. Reads `73` (interface Ø), `52` (chain, print floor), `71` (capsule requirement) and `81` (cold edge); thermal closing with the PEEK band outside the Ti collar (isothermal, model edge, a gradient bound with the Ti at 20 °C, a CTE sensitivity), ISO 286 grades computed from the standard's formula, three manufacturing routes (ours) → design clearance and the board ceiling through `52`'s chain. Three controls (ISO table · the chain against `52`'s cache · the sign). Writes `cache/mechanical/collar_running_clearance.json` | < 1 s |
| 83 | `83_os_series_vs_measured.py` | L3 ① against MEASURED series: the substituent shift of E°(Os III/II) per 4,4'-substituent, computed (21e B3LYP; ωB97X centre caches; the def2-on-Os check, the three continuum variants, the axial donor and both geometry relaxations — Os(II), then Os(III), the donors in one block and the acceptors, each once both its states are relaxed, in theirs (`acceptors`) — when their caches exist) ⊥ three measured series, each transcribed with provenance and read pair by pair — paper ref 8's own Os polymers [Os(X2-bpy)2(PVI)Cl]+ (Zafar 2012 Anal. Chem., Table 1; X = OMe · Me · H · Cl, our core and N-donor), the homoleptic MeCN series of Goldschmid et al., ChemRxiv 2021 (donors only; assumptions A1–A4) and the aqueous [Os(X2-bpy)2Cl(ampy)]+ series of Montón-Vicente et al., Langmuir 2026 (X = OMe · Me · Cl, with the source's own relaxed B3LYP). Imports 21e's σ table, so it runs in `silken_md`. Writes `cache/dft/os_series_vs_measured.json` | < 1 s |
| 84 | `84_cathode_ionic_path.py` | HW.53: series ionic resistance anode → cathode through the tree — sapwood (the anode as an equipotential cylinder under the insulating PEEK sleeve, over a conducting cambium plane, axisymmetric finite volumes, in two states — sap in the ≈ 2 mm gap of the Ø15 bore ⊥ wood grown into it; controls: the exact sphere above a plane, grid convergence, monotonicity; also the share of layer 1 a V+ in the wood leaves out) · living inner bark (sheet) · dead bark (radial) · water film over the buffer · the entry into the catalyst layer — each a material value × a factor of the canon geometry (CEM manifests, `58`, `78`); returns the value each layer must have per kΩ of cold-start budget (02_03 §1.5 ceiling − the electrodes' own R_int, for both canon readings: models `31`/`31b` ⊥ the unsourced prose estimate) and places the published readings beside it (Bieker & Rust 2010 · Losso 2020 · Lehtonen 1976 · Beijer via Blocken 2013). Reads `cache/kinetics/eis_model.json` and `cathode_det_rct.json`; writes `cache/kinetics/cathode_ionic_path.json`; the bench it serves — `docs/protocols/ebfc/cathode_ionic_path_bench.md` | ~1 s |
| 85 | `85_electrode_interfacial_ph.py` | HW.5.IS (coin half of the ΔpH leg): the pH at each coin electrode's face under its own current, in the Stage-2 letter's media — a steady Nernst film over `67`'s speciation of the ratified sap (importlib); the cathode as the δ-free fraction of its O₂ transport limit at which the face reaches pH 6, the anode as the diffusion-layer thickness L4's current (`J_MAX_25C`, `ph_current_ratio`) tolerates before its face leaves the measured band; controls: `67`'s titration · Liu et al. 2026's FEM point; the anchor anode per Zone-1 part in the sap assigned to it (beech Q8 for broadleaf and oak, both as proxies; pine Q7 for the rest — tropical and mangrove sap not modelled). Writes `cache/kinetics/electrode_interfacial_ph.json` | seconds |
| 86 | `86_coaxiality_allocation.py` | HW.34: the channel-to-root coaxiality priced as a Soderberg MEAN stress over `68`'s and `55`'s caches — seam break-even `k` and wire SF per allowed offset, per alloy and geometry. Seconds, stdlib + caches. |
| 87 | `87_pogo_sway_transfer.py` | HW.43: how trunk sway reaches the pogo pins — the rim-friction condition (the O-ring reaction each clamp design needs; the reaction is `88`'s), the board stack's inertia as a force ratio and at a part-by-part mass estimate, and a mass-independent centre-pad Poisson ceiling per 1000 µε of stem strain; stem input from Schindler & Kolbe 2020 Fig. 9. Seconds; imports `52` and `55`, reads `52`'s and `77`'s caches and the radome CEM. |
| 88 | `88_oring_reaction_band.py` | HW.33 · HW.43: the O-ring's own compression reaction — Parker ORD 5700 Figure 2-4 (.070 section, 70 Shore A) transcribed from the PDF's vector paths, in the part of the bar Table 2-3 gives a ring under 1″, interpolated over `52`'s squeeze window on the seal length of the AS568-019 ring; against it `52`'s rim-clamp requirement between assembly and 20 years, `73`'s lug-root capacity (the share of its reaction the ring must lose, the squeeze at which a non-relaxing ring binds the lug, the collar wall strength asks, the share the ring must have lost by each year) and `87`'s two rim needs (assembly temperature only). Seconds; reads `52`'s, `73`'s and `87`'s caches. |
| 89 | `89_bayonet_thermal_clamp.py` | HW.33: the bayonet clamp over its interference tolerance and temperature — the collar wall as a function of the loop stiffness k (closed form; δ, Δα and temperature readings), the k each wall tolerates, the PEEK-only ceiling and the force-controlled limit; the consumer is the conditional root-package member «collar wall by strength». Seconds; imports `88` (`wall_for_force`), reads `52`'s, `73`'s, `82`'s, `88`'s and `71`'s caches and the radome CEM. |
| 90 | `90_pogo_thermal_gap.py` | HW.43: the pogo gap's thermal travel — the radome PEEK column minus the hanging board stack (lib CTEs: PEEK, FR-4 Z, steels) and, for the working stroke, the pin's brass body over its free length (C36000), the seasonal swing against `52`'s mitigations, and from `71`'s hourly capsule temperature the daily stroke, force ratio and radial slide (PEEK and FR-4 in-plane). ~1 s; imports `52` (pogo constants) and `71` (hourly capsule temperature, checked against its own cache), reads `52`'s, `82`'s and `71`'s caches and the radome CEM. |
| 91 | `91_liner_exit_contact.py` | HW.34 · HW.23: the liner's exit contact as an elastic-layer problem coupled to the rod, read over the drag cycle — PEEK layer on the rigid wire (plane-strain Navier kernel, bonded ⊥ frictionless base), Ti half-space (Love), Polonsky–Keer on a DC-FFT, the rod through the exact Mohr flexibility of `55`'s piecewise EI, a pad couple, lumped contact friction (loading and unloading), each figure beside a rigid wall at the same edge. Controls (kernel limits and table · padding · Hertz · thin-layer Winkler asymptote · Mohr ⊥ FE touchdown · rigid limit = `68` · rigid point ⊥ LCP at a rounded edge · the pad couple ⊥ 68 (d) · the peak on the rigid touchdown value · the smallest radius's edge peak at two steps · the in-layer sharp edge's ρ^(−½) growth). Imports `55`, reads `68`'s and `55`'s caches. Writes `cache/mechanical/liner_exit_contact.json` | ~15 min (two threads) |
| 92 | `92_liner_mouth_contact.py` | HW.34 · HW.23: the liner at the channel mouth under an axis offset — `91`'s kernels and rod with two patches (mouth and exit), a Newton on the rod's pose per window; controls against `68`'s tables, `91`'s exit row and edge peaks, and the rigid limit; the static edge peak (offset × entry radius, two or three square grids); the mouth-edge peak over the drag CYCLE on three Zone-3 shanks at 50–100 µm and the exit-edge peak over the cycle by exit radius (coaxial and at the ⌀0.10 limit), in parallel workers; the beam's swing on the rigid same-edge model, dense in offset, with the elastic correction where cheap and the entry radius's effect; base/modulus brackets; the shank sweep. `--resummarise` re-derives the summary from the cached rows. Writes `cache/mechanical/liner_mouth_contact.json` | ~2 h on 2 workers beside a DFT |
| 93 | `93_malate_metal_chelation.py` | HW.5.IS (`01_03 §3.5` weakest link): the side-reaction coefficient α of trace Cu(II) · Co(II) · Ce(III) in the cathode medium (malic acid 10 mM, the sap's salts, pH 4.5) — every constant set read in its source (NIST SRD 46 · Zabiszak 2021 · Buzko 2004), pH read three ways, the free malate from `67`'s speciation of `85`'s medium (importlib), Ca/Mg competition over `67`'s readings; equilibrium, not a leaching rate. Writes `cache/chemistry/malate_metal_chelation.json` | seconds |
| 94 | `94_os_soc_quenching_model.py` | L3 (HW.5.IS, the SOC submission of 2026-10-19): how far a low-symmetry t2g splitting quenches the spin–orbit shift of the Os(II/III) couple — one-hole t2g model, ζ from the literature Os³⁺ splitting, the splitting that keeps every like-for-like cell (95) downhill, under three normalisations checked against the six Os couples of ref 63's SI Table S2 (only the stabilisation itself at the upper ζ reproduces them) and three patterns, with the literature analogues read; no SCF. Writes `cache/dft/os_soc_quenching_model.json` | < 1 s |
| 95 | `95_cascade_like_for_like.py` | L3 (HW.5.IS, the like-for-like revision): the anode cascade like-for-like — the 2e⁻/2H⁺ FAD potential at 32b's four levels (the first = 32) against the Os(III/II) couple of each computed form (21f · 34 · 21e relaxed; 96's both-sided row for the adiabatic chloro form) on one SHE scale, the distance to the measured cascade split by side and every agreement by cancellation named; no SCF. Writes `cache/dft/cascade_like_for_like.json` | < 1 s |
| 96 | `96_os_couple_thermo.py` | L3 (HW.5.IS, the like-for-like revision, ⚖️ founder 2026-10-16 «порахувати»): the Os(III/II) couple's harmonic thermochemistry — analytic C-PCM Hessians of both relaxed states of the dmbpy chloro form (21e `b3lyp-relaxed-os2` · `b3lyp-relaxed-os3`), E°(Os) at electronic · + ZPE · RRHO, so 95 carries one row corrected on BOTH sides. Writes `cache/dft/os_couple_thermo.json` | 32.3 h measured (2026-10-17→18: Hessians 12.7 h Os(II) · 17.3 h Os(III), part of it beside a `79` run) |
| 97 | `97_wire_under_liner_edges.py` | HW.34: the bus wire under the liner's edges — `92`'s contact pressure carried through the PEEK layer onto an elastic Ti half-space (bonded ⊥ frictionless base), added to the wire's nominal bending along `92`'s drag path, read on `86`'s Soderberg line (drawn wire at the stations, the welded root with its seam `k`); `--summary-only` re-derives the verdict from a written cache, no solve. Writes `cache/mechanical/wire_under_liner_edges.json` | ~1 h (CPU, two workers) |
| 98 | `98_field_strain_campaign.py` | HW.43: the field strain campaign's length from the 30-year hourly ERA5 10 m wind (`71`'s loader, fixed UTC+3) — per month the hours per day at Beaufort 4 / 5 and the hourly p99, the Beaufort-5 storms and the years without one, and the replay of every start month over each of the 30 years to 10 h at ≥ 8 m/s (median / p75 / p90 as actual years); battery trips (installation, swaps, removal) for two strain sensors and one tilt sensor on one receiver (power from the TreeMMoSys primaries, checked against their 152 h); the battery type for the ratified set — AGM ⊥ LiFePO4 over the capped December campaign with the ERA5 2 m air (discharge floors, AGM freezing for 10 … 14-day swaps and every first-swap day, humidity, battery days and trips on the makers' cold readings, swap calendars). Writes `cache/mechanical/field_strain_campaign.json` | seconds |
| 99 | `99_coating_cluster_cost.py` | HW.40: basis size of model coating clusters (Zn-HAp, PEDOT:PSS polaron, alone and on a (TiO₂)₁₆ cluster) at three tiers, measured; one SCF, a relaxation and an RKS Hessian estimated as brackets of named readings from the pipeline's own timed runs (the 21e series rebuilt by its builder via importlib, 21f's ωB97X extremes, 34's micro-solvated pairs, 21e's relaxed caches, 96's Hessian) — no SCF; which dispersion options the env carries. Writes `cache/dft/coating_cluster_cost.json` | seconds |
| 100 | `100_coin_replicate_power.py` | HW.24: Stage-2 coin statistical design under an ASSUMED log-normal coupon-to-coupon CV — two-arm detectable ratio (pooled t on logs, incl. one coupon against n), gate margins and the largest passing CV under three readings of «≥ threshold», the selection gap among the four Zone-1 candidates, the coupon budget and C channel-days per n — the spread estimated per contrast ⊥ pooled over the arms of one quantity; Monte Carlo check of every closed form. Writes `cache/kinetics/coin_replicate_power.json` | seconds |
| 101 | `101_bus_torsion_budget.py` | HW.26: elastic twist angle of the welded bus wire to first surface yield over the weld-root → liner-grip run (`55`'s spans), per alloy, von Mises ⊥ Tresca and liner slipping ⊥ sharing the torque; the wire's yield torque against the liner tube's torsional first yield and grip (`55`, nominal and creep-relaxed) with the wire yield at which that order flips, and the wind's rotation and torque at the sleeve's bark end (`77`); second-route control. Writes `cache/mechanical/bus_torsion_budget.json` | seconds |
| 102 | `102_wire_liner_shear_lag.py` | HW.43: the bus wire in its press-fitted PEEK liner as a shear-lag pair with Coulomb slip — root axial force and centre-pad travel vs the share of `87`'s sway shift and the sleeve's thermal growth, per `55` tolerance part and μ; `86`'s seam requirement on them, `90`'s L1 margins against the pad; independent FE control. Writes `cache/mechanical/wire_liner_shear_lag.json` | seconds |
| 103 | `103_anchor_wood_share.py` | HW.43: the share of the stem's radial shift the wood imposes on the anchor per bond state (anode free · anode bonded with the sleeve free below the bark · a rigid callus tie of the sleeve with the bark bearing), on one three-node solver; the bark bearing's stiffness and the tie's depth as axes, with the bearing at which each state-2 conclusion is reached at both ends of the bond bracket, the tie depth at which each mature-state one is reached with no bearing, and the span's lowest effective CTE against the pad travel's sign change; the seam on `102`'s closed form with its hot preload; all of it twice — the flange located by the bark, and by a rigid Zone-3 fit (the shank's run as Ti bonded to PEEK), the reduction checked against a chain of short elements; and per premise the (CTE, share) front `104` reads. Writes `cache/mechanical/anchor_wood_share.json` | seconds |
| 104 | `104_pad_travel_remedies.py` | HW.43: the prices of the remedies for the centre pad's thermal travel — how far it passes `90`'s L1 margin on both of `102`'s spans over every grip (the Zone-3 shank bonded on 18 mm), held and with the sway on top (`103`'s (CTE, share) front), and what each remedy buys: the PEEK run's length or effective CTE (bisected to close the need), a longer pin stroke, a smaller `52` residual (bayonet hard-stop · CNC tolerance class · spacer step · their combination); the seam's hot preload and `86`'s requirement with `103`'s sway corners; the need's sensitivity to the placeholder shank; controls hold `102`'s pad travel, `102`/`103`'s seam requirements, `90`'s residuals and `55`'s geometry. Writes `cache/mechanical/pad_travel_remedies.json` | seconds |
| 105 | `105_printed_part_sway_stress.py` | HW.23: the cyclic stress the stem's sway puts into the anchor's titanium parts, path by path (the full path list with each one's status is in the cache): an energy LOWER bound on the bonded gyroid's ligament stress — strain-controlled, so σ_e/E_s is the alloy's figure of merit at t_L = 1 (the share is `106`'s) — given as the stem surface strain above which it alone reaches SF 2 per alloy, FE reading (axial in doubt from above, radial neither shown nor excluded — `00_07` HW.23), stress-state reading and sensor reference; the anode's bond force and the bearing force from `103`'s closed forms (held to its cached caps on its own grid); the nominal stress, K_f at SF 2 per cycle reading and route, and the mean at SF 2 in the Zone 1 and Zone 3 shanks, barbs and the flange disc (an annular Kirchhoff plate in `103`'s state 2, held to an independent FD solve); the junction's mismatch and the mass path. Writes `cache/mechanical/printed_part_sway_stress.json` | ~1 s |
| 106 | `106_gyroid_wood_strain_share.py` | HW.23: the share t_L of the wood's in-plane strain the bonded gyroid takes — an orthotropic Eshelby circular cylinder (Mura's integral) in Scots pine sapwood on Güntekin & Akar 2019's measured constants (four moisture groups, three symmetrisation readings, the non-positive-definite ones excluded), the lattice's C11/C12 from `105`'s two voxel-FE ratios (axial in doubt from above, radial neither shown nor excluded — `00_07` HW.23) read as one homogeneous cubic body, C44 swept to Voigt's ceiling, the install angle and three pore readings (bare lattice ⊥ additive ⊥ Voigt phase bound) swept; the Zener ratio at which t_L crosses 1, the moisture counts per reading, the θ = 0 share range and `105`'s binds-above strains at its lowest (the tensor's own E[100] ⊥ `105`'s lower reading), and the off-axis threshold factor and modulus under the same tensor. Controls: isotropic cylinder, Lekhnitskii's hole, covariance under a rotation, Goodier's inclusion. Writes `cache/mechanical/gyroid_wood_strain_share.json` | ~1 s |
| 81 | `81_capsule_cold_edge_sky.py` | HW.37: the cold edge `71` leaves open. `71`'s isolated lump hourly over the ERA5 record with `79`'s sky term (Brutsaert clear sky from the ERA5 dew point ⊥ overcast), natural convection called with |ΔT|, long-wave at full T⁴, solved per hour by vectorised bisection with the air returned EXACTLY where no gain meets no deficit (ERA5 air sits ON the floor in 0.1 K steps). Sky × sun × wind ends; four controls (`79`'s reference hour · overcast without sun = the air on every hour · the air count = `71`'s · an unbroken hourly clock). Reports hours, days and the longest spell below the EDLC floor, hours below the capsule requirement and the coldest hour per run, the edges selected from the runs, and ERA5's own sunshine share (WMO DNI threshold) and wind on the cold days against the whole winter. Writes `cache/thermal/capsule_cold_edge_sky.json` | ~5 s |
| 80 | `80_chem11_a3d_crosscheck.py` | HW.5.IS / CHEM.11: reads the committed Aggrescan3D output (`data/chem11_a3d/`, third-party and OUTSIDE the CC-BY-SA grant — `/NOTICE`) against script 69's proxy, and answers the half of the `L1 §2` recipe that gated the gene freeze. Re-aims the recipe's own criterion, which is not answerable as written (A3D scores a Gln negative by construction), onto the NEIGHBOUR of each site; ranks the three ratified compensations inside A3D's own mature-chain ranking; and censuses A3D's exposure-gate SENTINEL — the `0.000` it writes for 42 % of residues, which is 'buried', not 'measured'. Writes `cache/chemistry/chem11_a3d_crosscheck.json` | < 1 s |

Numeric prefixes encode the pipeline DAG and group: 02-08 prep (GAFF),
10-16 L2 MD, 20-35 L3 DFT (23-25 + 24b L3b cathode DET; 27-35 advanced L3 —
tunneling/λ/PCET/micro-solvation/speciation),
30-31 L4 kinetics/EIS, 40 validation; from 50 up, lab-gated desk models tied to the tracker item each row
names (not part of the L1-L4 enzyme DAG), except 60-61, the paper assets (figures + tables, cache-only
renderers). Rows are listed in execution order; 09 is reserved for a future ligand.

## Why the GAFF detour (script 02 + 03)?

The `amber14-all.xml` bundle we load ships templates for proteins
(20 amino acids + protonation variants HID/HIE/HIP, CYX, GLH/ASH +
N-/C-caps), nucleic acids, lipids, sugars, and the standard monatomic
ions (Na+, Cl-, K+, …). It does **not** ship templates for
small-molecule cofactors (FAD, NAD, heme, …) or custom organic ligands
like genipin. The moment `forcefield.createSystem()` walks the topology
and hits an unknown residue, it raises
`ValueError: No template found for residue N (FAD)`. So before any real
L2 run you must parameterize each non-standard residue once. We do this
via the GAFF (General Amber Force Field) pipeline shipped in
`openmmforcefields`:

1. RDKit reads the molecule (PDB coords + SMILES bond orders / pure SMILES).
2. `openff.toolkit.Molecule` wraps it with chemistry-aware metadata.
3. `GAFFTemplateGenerator` shells out to AmberTools' `antechamber` →
   AM1-BCC charges, GAFF atom types, then `parmchk2` for missing FF terms.
4. Result is serialized to `cache/gaff_cache.json`. Re-running scripts
   that touch the same ligand is a cache hit (seconds, not minutes).

The cache file is committed (small, deterministic). MD trajectories under
`cache/runs/` are not.

Re-run records live under `cache/reproduction/` (e.g. `lock_rerun_2026-09-30.json`):
field-by-field deltas of a committed cache re-computed under another environment (the
conda-lock). They back the paper's §2.7 reproducibility statement and are listed in the SI
manifest; only `75` (to attribute the gap) and `76` (C-min, against its base) read one of them (`lock_rerun_2026-10-01.json`) and write their own record beside it — `76`'s record lives here although it is no re-run, because it ran under the lock and every cache outside this directory is computed in the recorded environment; the committed caches stay untouched.

---

## CI gate

`.github/workflows/in_silico_smoke.yml` has three working jobs, all gated by its `changes`
paths-filter (the path list lives in the workflow, not here):

- **`lock_sync`** — fail-fast: `conda-lock.yml` must still match `environment.yml`
  (`conda-lock --check-input-hash` + `git diff`). Edit `environment.yml` without
  regenerating the lock and this job fails (see *Adding a new dependency* below).
- **`smoke`** — runs `01_smoke_test_water_box.py` with `SILKEN_FORCE_PLATFORM=CPU`
  (deterministic on hosted runners), in the env built from the **pinned**
  `conda-lock.yml`. Cached by `mamba-org/setup-micromamba@v3` keyed on the lock
  hash, so cold runs take ~10 min, cached runs ~3 min.
- **`cache_doc_sync`** — no conda env: hash-pinned pytest on the runner's `python3`, running
  `test_doc_cache_sync.py` plus the unit tests whose import chain is stdlib-only
  (`test_validate_vs_experiment.py`, `test_unified_lame.py`). A test that imports numpy
  belongs in `smoke`, not here — run it under a bare `python3` before adding it.

> **Why the lock (resolved 2026-06-04):** `environment.yml` uses `>=` specifiers,
> so a bare `conda env create` picks the latest compatible build each solve — a
> breaking transitive conda-forge release could red CI on code nobody touched and,
> worse, silently shift the numbers behind a TRL-evidence run. The committed
> `conda-lock.yml` pins exact versions + hashes per platform (`linux-64` +
> `osx-arm64`) → bit-reproducible envs. Repo-wide pin-policy home:
> [`docs/03_01_Firmware_Lifecycle_and_DMA.md §12.5`](../../docs/03_01_Firmware_Lifecycle_and_DMA.md).

## L1 protein structure (AlphaFold 3)

> **Gen 2.0 — NOT GOx.** The anode enzyme is **deglycosylated FAD-GDH**
> (dgrGcGDH from *Glomerella cingulata*), not the rejected Gen 1.0 GOx.

L1 uses AlphaFold 3 Server to predict the deglycosylated FAD-GDH + FAD
cofactor structure. The result PDB is stored in
`docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb` and used as input for all
L2 MD simulations.

1. Go to [AlphaFold 3 Server](https://alphafoldserver.com/) and sign in
   with a Google account (free for academic/non-commercial use).
2. Build the dgr-mutant sequence: run [`deglycosylate.rb`](../../docs/protocols/ebfc/in_silico/deglycosylate.rb)
   on UniProt **G8E4B5** (FAD-GDH *G. cingulata*, 600 aa) → mutates 11
   N-X-S/T sequons N→Q.
   > **Why mutate, not just "skip sugars":** AF3 does not model glycans
   > unless you explicitly add sugar ligands — feeding it the wild-type
   > sequence already yields a bare (unglycosylated) fold. So the N→Q edits
   > are **not** "removing sugars from the model." Their real purpose is
   > twofold: (a) they ARE the production gene design (dgr-mutant) so
   > *Pichia* physically can't glycosylate those sites (`01_03 §3.7`); and
   > (b) we fold the mutant to confirm the 11 point mutations themselves
   > don't destabilize the globule or perturb the FAD active site.
3. Create a new AF3 job:
   - **Protein**: paste the dgr-mutant sequence (600 aa, monomer)
   - **Ligand**: add FAD (CCD code `FAD`)
4. Submit and wait (~5 min). Download the top-ranked PDB → `dgrGcGDH_AF3.pdb`.

Current result: **`d_FAD = 15.998 Å`** (FAD N5 → Tyr90 OH), confirmed in UCSF
ChimeraX — a BURIAL DEPTH, i.e. a lower bound on the donor–acceptor separation,
against the ≈20 Å centre-to-centre ceiling for single-step tunnelling through
protein (Gray & Winkler, PNAS 2005; the former «18–20 Å» had no source). The
distance does not exclude MET and does not prove it, and the flavin→mediator
coupling that would carry it is not computed (script 28 is a contact-graph search,
not a pathway analysis — self-review cluster 6). See
[`L1_protein_architecture.md`](../../docs/protocols/ebfc/in_silico/L1_protein_architecture.md)
and `01_03 §3.4` for validation.

## Quickstart (one-time setup)

```bash
# 1. Install Miniforge (conda-forge native arm64 builds)
curl -L -o /tmp/Miniforge3.sh \
  "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh"
bash /tmp/Miniforge3.sh -b -p "$HOME/miniforge3"
"$HOME/miniforge3/bin/conda" init zsh
# → restart shell, or `source ~/.zshrc`

# 2. Create the project env from spec
conda env create -f tools/in_silico/environment.yml

# 3. Activate
conda activate silken_md

# 4. Verify
python -m openmm.testInstallation
```

## Reproducible install (pinned lock)

`conda env create -f environment.yml` (above) re-solves and grabs the latest
compatible builds — fine for day-to-day dev. For the **exact** env CI uses, install
from the committed `conda-lock.yml` instead — a REPRODUCTION env, not the one the
numbers came from: that is the recorded env, `environment.computed.explicit.txt`
(PySCF 2.11.0, while the lock resolves 2.13.1 — paper §2.7). ⛔ On the machine whose
`silken_md` is that record, install the lock under its own name (`silken_lock`), never
over it (`00_07` OPS.22). Needs `conda-lock` once (`pipx install conda-lock`, or
`conda install -n base -c conda-forge conda-lock`):

```bash
conda-lock install -n silken_lock tools/in_silico/conda-lock.yml
```

`environment.yml` stays the human-editable source; `conda-lock.yml` is the
generated pinned artifact (versions + hashes, `linux-64` + `osx-arm64`). Pin
rationale: `docs/03_01 §12.5`.

## Daily use

```bash
conda activate silken_md
python tools/in_silico/scripts/<script>.py
```

## Linting (`ruff`)

Python style/bug linter — аналог RuboCop для Ruby-боку. Конфіг: root `ruff.toml`
(спільний з `tools/ml/`). Standalone, conda не потрібна. CI-гейт: `ci.yml › python_lint`.

```bash
pip install ruff       # one-time
ruff check .           # лінт
ruff check . --fix     # + безпечні авто-фікси
```

## Python version policy

Pinned to **Python 3.12** in `environment.yml`. This is the highest version
with full conda-forge coverage for the L2-L4 stack as of 2026-Q2
(`openmm 8.3+`, `pdbfixer`, `mdtraj`, `pyscf`, `scipy/numpy`). When 3.13 ships
stable builds for all dependencies, bump and refresh `environment.yml`.

## GPU notes (macOS arm64)

OpenMM ships four platforms: `Reference`, `CPU`, `OpenCL`, `CUDA`. On Apple
Silicon **`OpenCL` is the GPU platform to use** — despite Apple's "deprecated"
label, OpenMM 8.x runs on the Apple GPU through it. **Verified on this project:**
our L2 production MD (467k-atom system) auto-selects `OpenCL` and sustains
**~10–11 ns/day** on the M-series GPU. `CUDA` is Nvidia-only; `CPU`/`Reference`
are ~10–20× slower and reserved for CI determinism and tiny sanity runs.

Scripts auto-select the fastest available platform; force one with
`SILKEN_FORCE_PLATFORM=CPU` (CI uses this for reproducibility).

**This means**: the Mac (OpenCL) handles development **and** the short-to-medium
production runs we actually do (single MD trajectories up to ~10 ns ≈ a day).
Reach for cloud GPU only for **large/parallel campaigns** (100+ ns, or many
trajectories at once) per `docs/01_03 §3.4`:

- GCP `g2-standard-12` (1× L4) — ~$1–2/h
- AWS `g5.2xlarge` (1× A10G) — ~$1.20/h
- AWS `p5.2xlarge` (1× H100) — ~$30/h (heavy MD only)

## Adding a new dependency

1. Edit `environment.yml`, append under `dependencies:`.
2. Regenerate the lock (re-solves both platforms):
   ```bash
   conda-lock lock -f tools/in_silico/environment.yml \
     --lockfile tools/in_silico/conda-lock.yml -p linux-64 -p osx-arm64
   ```
3. Sync your local env to the new lock:
   `conda-lock install -n silken_md tools/in_silico/conda-lock.yml` — ⛔ where `silken_md`
   is the record, sync `silken_lock` instead (see *Reproducible install*).
4. Commit **both** `environment.yml` and `conda-lock.yml` (the `lock_sync` CI job
   fails if they drift apart).

Never `pip install` directly into the env without recording it in
`environment.yml` — that breaks reproducibility for the rest of the team
and the AI agents that consume this stack.

## Why not GROMACS / NAMD?

See `docs/01_03 §3.4` for the full rationale. TL;DR: OpenMM is Python-first,
so AI agents (Claude, Copilot) can generate runnable simulation scripts
end-to-end without us hand-writing GROMACS `.mdp` files.
