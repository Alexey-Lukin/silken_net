# Paper Outline / Writing Plan — Стаття 1 (EBFC quantum chemistry)

> **This is the writing plan / skeleton**, not a number source. All numerical results
> live in [`SUMMARY.md`](../SUMMARY.md) (One-Home) — this doc *references* them, never
> restates. The canonical publication plan (title, journals, authors, IP posture) lives in
> [`00_02 Стаття 1`](../../../../00_02_Academic_Integration_and_IP.md); keep them in sync.
> Built 2026-06-05 while ① runs; sections tagged **[READY]** / **[PENDING ②/③/④]**.

## 0. Front matter

- **Working title (EN):** *"Computational Electron-Transfer Energetics of a FAD–Osmium Enzymatic Biofuel Cell: PCET Redox Potentials, Mediator Structure–Activity, ZIF-Nanozyme Direct Electron Transfer, and the Limits of Implicit-Solvation DFT."* (base = 00_02 canon title; the **"Mediator Structure–Activity"** clause is **new**, earned by ①'s Hammett LFER — if kept, update 00_02 too.)
- **Type:** purely computational quantum-chemistry paper (no wet experiment yet — Ti-coin = Stage 2). Sells on **mechanistic + methodological** novelty, NOT "validation."
- **Target:** *J. Phys. Chem. B* (primary) · *PCCP* (fallback) · *Bioelectrochemistry* (applied backup). IMRaD identical across the first two.
- **Authors / CRediT:** Architect (Silken Net) — Conceptualization, Methodology, Software, Investigation, Writing-original-draft. External computational-electrochemistry collaborator (TBD) — Methodology (explicit-water QM/MM, §3.5 upgrade), Investigation, Writing-review. Corresponding = founder's call.
- **✅ IP — defensive publication** (00_01 §8): **публікація = захист** (prior art) → submission-ready, без патентного гейту. Prior-art landscape: `protocols/anchor/prior_art_landscape.md`.

## 1. Thesis (honest, one paragraph)

We compute the first-principles electron-transfer energetics of the Gen 2.0 EBFC anode→mediator→cathode chain. The **PCET redox potential of the FAD cofactor** is reproduced well by implicit-solvation DFT; the **direct-electron-transfer kinetics through the bimetallic ZIF cathode**, computed with Nelsen reorganization energies, expose a **λ-sensitive, borderline DET margin** and a low-λ-metal design rule (the earlier large margin was a geometry+λ artifact); a **Hammett structure–activity rule** for the Os(III/II) mediator gives a predictive design handle and rationalizes the experimental optimum; and the **anode→mediator cascade thermodynamics expose a quantified ~1 eV limit of implicit (PCM) solvation** for group-8 octahedral redox couples, which explicit-water micro-solvation (and, ultimately, QM/MM) resolves. The contribution is mechanistic insight + a solvation-methodology lesson — not a re-confirmation of the experimentally-known cascade.

## 2. Abstract (structured, ~200 words) — [draft last]

problem (autonomous EBFC sensing; ET is the bottleneck) → gap (field models EBFCs experimentally + macro-kinetically, not at the electronic-structure level) → methods (DFT/ΔSCF + PCET proton-reference + Beratan-Onuchic + ZIF ΔSCF + cluster-continuum) → 3 headline numbers (PCET E°; mediator LFER slope; k_DET) → the honest PCM-limit + its fix → outlook (Ti-coin EIS predictions). Numbers → SUMMARY.

## 3. Section-by-section outline

| § | Content | Result map (→SUMMARY/scripts) | Figure | Status |
|---|---|---|---|---|
| **1 Introduction** | EBFC for autonomous/implantable sensing (SilkenNet); FAD-GDH/Os/laccase-ZIF system; field challenges (ET efficiency, DET, stability, mediator leaching); **gap = molecular-level ET energetics under-explored** (field uses experimental + reaction-diffusion math, not DFT); our contribution | lit only (~40–60 refs) | — | **[READY]** scaffold §6 |
| **2 Computational Methods** | AF3 (L1); B3LYP/6-31G(d)+LANL2DZ(Os) + ωB97X/def2-TZVP; ΔSCF vertical+adiabatic; PCET thermodynamic proton-reference; Beratan-Onuchic; ΔSCF-UKS ZIF + computed λ; cluster-continuum; QM-cluster protein E°. **Reproducibility = our strength** (conda-lock pinned env, deterministic scripts `tools/in_silico`) | methods exist; script refs | — | **[READY]**; ②③④ method detail folds in |
| **3.1 Architecture & tunneling** | d_FAD < tunneling range; through-bond path FAD→ALA261→THR260→THR283→THR288, β·d=2.05; exit residues rigid (pLDDT≫80); MD-ensemble β·d=2.02±0.13 (gating 1.03× → thermally robust) | L1 + script 28/28b | Fig 2 | **[READY]** |
| **3.2 Anode PCET potential** | proton-reference recovers E°(FAD/FADH₂) within ~50 mV of exp free-flavin — clean positive result | script 32 | Fig 3a | **[READY]** |
| **3.3 Mediator structure–activity** | Hammett LFER: E°(Os III/II) linear in σ_para (slope ≈ −0.92 eV/σ, r²=1.00); **cascade-Δ design rule** — electron-withdrawing 4,4'-bpy improves FADH₂→Os alignment; triangulated DFT↔Lever↔Hammett. **Realistic optimum = SO₂CF₃** (cascade −0.227 ≈ NO₂'s −0.232 but electrochemically inert — NO₂ degrades NO₂→NH₂ on Os cycling → collapses cascade to the −1.5 worst case; CHEM.23). **Caveat:** max cascade-Δ ≠ *optimal* EBFC mediator — higher E°(Os) → **lowers OCV**; rule is cascade *thermodynamics*, exp Os opt (~+309 mV, Zafar 2012) balances driving-force vs overpotential | ① `os_mediator_series.json` | Fig 3b, Table 4 | **[① DONE]** |
| **3.4 Cathode DET (ZIF)** | bimetallic Cu-Co-Ce hopping; geom-fixed t_ij + **computed λ** (Nelsen, not assumed) → k_DET **borderline** (Cu-Co bottleneck ~turnover, ×1–30 not ×10⁵); honest λ-sensitivity + Ru/cMOF/enzyme-free mitigation — a *finding*, not a failure; **FO-DFT (24b) confirms borderline robust to coupling method** (t_ij ~4× crude + 0.18 eV site-gap) | scripts 24/24b/25/35 | Fig 4, Table 3 | **[③ DONE]** |
| **3.5 Cascade & the PCM limit** | raw cascade uphill in *every* method; the gap **decomposes** (computed, ②) into a **chloro↔bis-Im differential-solvation bracket** (chloro +1/+2 +0.21 ↔ bis-Im +2/+3 +0.55 eV, dimethyl) + **4,4'-dimethyl substituent** (+0.142 ①); [Os(H₂O)₆] benchmark recovers the ~1 V group-8 PCM error (+0.98 eV); QM/MM of the chloro species (external follow-up) = rigorous capstone | scripts 21f/21g/33 + **34/34b ②** | Fig 5, Table 2 | **[② dimethyl recompute]** + external QM/MM follow-up |
| **3.6 Protein environment on E°** | bound FAD-GDH E° = **−265 mV vs SHE** (verified, Schachinger, Ma, Ludwig 2023) — protein tunes free −208 → bound −265 (−58 mV, *better* donor → larger cascade driving force); active-site model from AF3 PDB (isoalloxazine + catalytic HIS537 / charged GLU61 / backbone amides). Rigorous QM-cluster E° = follow-up capstone (external computational-electrochemistry collaboration; bundled w/ the cascade QM/MM) | ④ (canon fixed; QM-cluster deferred) | — | **[④ canon ✅ · QM-cluster → capstone]** |
| *(3.x brief)* thermal robustness | MD→DFT ensemble: FAD HOMO σ≪0.3 eV | script 27 | — | **[READY]** |
| *(3.x brief)* anode reorganization energy | FADH⁻/FADH• Nelsen 4-point → inner-sphere λ_i 0.39 eV (the physically-correct deprotonated couple rescues the script-29 radical-cation pathology); ≈ lit 0.7–0.8 w/ outer-sphere — *computed*, not assumed, parallels the cathode metal-λ | script 29b (CHEM.21) | — | **[CHEM.21 DONE]** |
| **4 Conclusion & Outlook** | cascade ET validated mechanistically; predictive mediator design rule; honest solvation lesson; EIS predictions for Ti-coin experimental closure; QM/MM capstone | SUMMARY L4c | — | **[READY]** |
| Back matter | CRediT · **Data availability** (repo + conda-lock — strong) · Funding · Conflicts · SI = scripts/goldens | — | — | **[READY]** |

## 4. Figure & table plan

> Data figures are built by [`tools/in_silico/scripts/60_paper_figures.py`](../../../../../tools/in_silico/scripts/60_paper_figures.py)
> (cache-only, no DFT recompute; every headline number asserted vs SUMMARY at build time) → `paper/figures/`.
> Captions drafted in [`03_results.md §Figures`](03_results.md). The two molecular/art figures (Fig 1, Fig 2)
> are **not** cache-derivable → separate visualisation pass.

- **Fig 1** (graphical abstract): the anode→Os→cathode cascade overlaid on the 3-zone gyroid anchor (metal↔xylem interface). — 🟡 **code-schematic DRAFT built** (`fig1_graphical_abstract_draft.png` via `fig1_graphical_abstract_draft.py`; layout + both synergies + canon numbers −265/+309/+574) → 👤 BioRender/Illustrator finalize (art); same schematic seeds the **TOC graphic**
- **Fig 2**: AF3 structure + FAD depth + Beratan-Onuchic tunneling path (resSeq labels). — ✅ **PyMOL cartoon built** (`fig2_structure_path_pymol.png` via `fig2_pymol_cartoon.py`, `pymol_tmp` env); 2D-PCA DRAFT (`fig2_structure_path.png`, via 60, d_FAD 16 Å asserted) kept too — founder picks the final / GUI-polish (label de-overlap); β·d *data* → Fig S1
- **Fig 3**: (a) MO/Marcus cascade diagram + PCET E°; (b) **① LFER** — E°(Os) & cascade-Δ vs Hammett σ (the design-rule plot). — ✅ **built** (`fig3_cascade_lfer.png`)
- **Fig 4**: ZIF Cu-Co-Ce hops + k_ET ladder (with computed λ, ③). — ✅ **built** (`fig4_cathode_det.png`)
- **Fig 5** (methods centerpiece): PCM vs cluster-continuum solvation closing the cascade gap (②). — ✅ **built** (`fig5_solvation_pcm.png`)
- **Fig S1** (SI): tunnelling β·d, static AF3 vs MD-ensemble — thermal robustness. — ✅ **built** (`figS1_betad_ensemble.png`)
- **Tables**: T1 levels of theory · T2 cascade energetics (all methods) · T3 DET hops + λ · T4 mediator series E°/cascade-Δ vs σ. — ✅ **built** (`06_tables.md` via `61_paper_tables.py`, cache-only + canon-asserted)

## 5. Scope boundary

L1 (distance/path) + L3 (anode) + L3b (cathode) + mediator series + solvation methodology. **Out of scope** (→ окремі майбутні EBFC-статті): L2 MD stability; L4 delta_t/EIS (cited here only as experimental-closure predictions).

## 6. Introduction reference scaffold (key anchors; expand to ~40–60)

- **EBFC reviews / field + challenges:** Pak et al. 2025 *Adv. Funct. Mater.* 10.1002/adfm.202415933; *Biosensors* 2025 (implantable EBFCs) 10.3390/bios15040218; Kundu 2026 *Fuel Cells*; "Tackling the Challenges of Enzymatic (Bio)Fuel Cells" *Chem. Rev.* 10.1021/acs.chemrev.9b00115.
- **Os-mediated FAD-GDH (experimental anchor):** Degani & Heller 1987 → GcGDH Os-polymer window **+15…+489 mV vs NHE** = **Zafar, Wang, Sygmund, Ludwig, Leech, Gorton, *Anal. Chem.* 2012, 84, 334, doi:10.1021/ac202647z** (the "Electron-Transfer Studies… Os polymers of different redox potentials" paper). **E°(Os) = +309 mV vs NHE** = the device mediator `[Os(4,4'-dimethyl-2,2'-bipyridine)₂(PVI)₁₀Cl]⁺` — the best-performing of the six (E°'=+21 mV vs Ag/AgCl 0.1 M KCl + the paper's +288 mV conversion); driving force +574 mV. (Old +200 mV was an under-specified early anchor with no standalone source — superseded by the verified value.) Mao 2003 = electron-transport, not the potential range.
- **Mediator design precedent (genre):** JPCB 10.1021/acs.jpcb.3c03740 (model-driven redox-mediator design, GOx).
- **Lever LFER:** Lever 1990 *Inorg. Chem.* 10.1021/ic00331a030; DFT↔Lever↔Hammett correlation *Inorg. Chem.* 10.1021/ic0105258.
- **Implicit-solvation redox benchmarks (methods lesson):** group-8 octahedral reduction potentials *JPCC* 10.1021/jp406772u; cluster-continuum Pliego-Riveros *JPCA* 10.1021/jp004192w; multistep explicit solvation *JCTC* 10.1021/acs.jctc.8b00982.
- **Flavin redox / protein tuning (④):** QM/MM flavin reduction potentials PMC4480342; protein-electrostatics flavin tuning RSC 10.1039/d5sc02960k; cluster vs QM/MM for protein redox *JCTC* 10.1021/acs.jctc.5c01656; laccase-CueO cluster precedent (Frontiers).
- **ZIF laccase-mimic cathode (③ context):** Cu/Zn-ZIF & Cu-ZIF-67 ORR nanozymes.

## 7. Writing workflow

Methods (strongest, reproducible) → Results (fill as ①②③④ land) → Introduction (longest, lit) → Discussion/Conclusion → Abstract + cover letter last → internal review → **IP gate** → submit. Pull every number from `SUMMARY.md` at draft time; if a result changes, change SUMMARY, not the paper twice.
