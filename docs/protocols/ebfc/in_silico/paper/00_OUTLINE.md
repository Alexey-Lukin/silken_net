# Paper Outline / Writing Plan — Стаття 1 (EBFC quantum chemistry)

> **This is the writing plan / skeleton**, not a number source. All numerical results
> live in [`SUMMARY.md`](../SUMMARY.md) (One-Home) — this doc *references* them, never
> restates. The canonical publication plan (title, journals, authors, embargo) lives in
> [`08_01 §Стаття 1`](../../../08_01_Joint_Publications_and_IP_Strategy.md); keep them in sync.
> Built 2026-06-05 while ① runs; sections tagged **[READY]** / **[PENDING ②/③/④]**.

## 0. Front matter

- **Working title (EN):** *"Computational Electron-Transfer Energetics of a FAD–Osmium Enzymatic Biofuel Cell: PCET Redox Potentials, Mediator Structure–Activity, ZIF-Nanozyme Direct Electron Transfer, and the Limits of Implicit-Solvation DFT."* (base = 08_01 canon title; the **"Mediator Structure–Activity"** clause is **new**, earned by ①'s Hammett LFER — if kept, update 08_01 too.)
- **Type:** purely computational quantum-chemistry paper (no wet experiment yet — Ti-coin = Stage 2). Sells on **mechanistic + methodological** novelty, NOT "validation."
- **Target:** *J. Phys. Chem. B* (primary) · *PCCP* (fallback) · *Bioelectrochemistry* (applied backup). IMRaD identical across the first two.
- **Authors / CRediT:** Architect (Silken Net) — Conceptualization, Methodology, Software, Investigation, Writing-original-draft. Школа Мінаєва (ЧНУ) — Methodology (explicit-water QM/MM, §3.5 upgrade), Investigation, Writing-review. Corresponding = founder's call.
- **🛑 Embargo gate:** patent NOT filed → **draft freely, HOLD submission** until priority date (08_01 §2; prior-art `protocols/anchor/prior_art_queries.md`). Disclosing the cascade/PCET = patent-relevant.

## 1. Thesis (honest, one paragraph)

We compute the first-principles electron-transfer energetics of the Gen 2.0 EBFC anode→mediator→cathode chain. The **PCET redox potential of the FAD cofactor** is reproduced well by implicit-solvation DFT; the **direct-electron-transfer kinetics through the bimetallic ZIF cathode**, computed with Nelsen reorganization energies, expose a **λ-sensitive, borderline DET margin** and a low-λ-metal design rule (the earlier large margin was a geometry+λ artifact); a **Hammett structure–activity rule** for the Os(III/II) mediator gives a predictive design handle and rationalizes the experimental optimum; and the **anode→mediator cascade thermodynamics expose a quantified ~1 eV limit of implicit (PCM) solvation** for group-8 octahedral redox couples, which explicit-water micro-solvation (and, ultimately, QM/MM) resolves. The contribution is mechanistic insight + a solvation-methodology lesson — not a re-confirmation of the experimentally-known cascade.

## 2. Abstract (structured, ~200 words) — [draft last]

problem (autonomous EBFC sensing; ET is the bottleneck) → gap (field models EBFCs experimentally + macro-kinetically, not at the electronic-structure level) → methods (DFT/ΔSCF + PCET proton-reference + Beratan-Onuchic + ZIF ΔSCF + cluster-continuum) → 3 headline numbers (PCET E°; mediator LFER slope; k_DET) → the honest PCM-limit + its fix → outlook (Ti-coin EIS predictions). Numbers → SUMMARY.

## 3. Section-by-section outline

| § | Content | Result map (→SUMMARY/scripts) | Figure | Status |
|---|---|---|---|---|
| **1 Introduction** | EBFC for autonomous/implantable sensing (SilkenNet); FAD-GDH/Os/laccase-ZIF system; field challenges (ET efficiency, DET, stability, mediator leaching); **gap = molecular-level ET energetics under-explored** (field uses experimental + reaction-diffusion math, not DFT); our contribution | lit only (~40–60 refs) | — | **[READY]** scaffold §6 |
| **2 Computational Methods** | AF3 (L1); B3LYP/6-31G(d)+LANL2DZ(Os) + ωB97X/def2-TZVP; ΔSCF vertical+adiabatic; PCET thermodynamic proton-reference; Beratan-Onuchic; ΔSCF-UKS ZIF + computed λ; cluster-continuum; QM-cluster protein E°. **Reproducibility = our strength** (conda-lock pinned env, deterministic scripts `tools/in_silico`) | methods exist; script refs | — | **[READY]**; ②③④ method detail folds in |
| **3.1 Architecture & tunneling** | d_FAD < tunneling range; through-bond path FAD→ALA261→THR260→THR283→THR288, β·d=2.05; exit residues rigid (pLDDT≫80) | L1 + script 28 | Fig 2 | **[READY]** |
| **3.2 Anode PCET potential** | proton-reference recovers E°(FAD/FADH₂) within ~50 mV of exp free-flavin — clean positive result | script 32 | Fig 3a | **[READY]** |
| **3.3 Mediator structure–activity** | Hammett LFER: E°(Os III/II) linear in σ_para (slope ≈ −0.93 eV/σ); **cascade-Δ design rule** — electron-withdrawing 4,4'-bpy improves FADH₂→Os alignment; triangulated DFT↔Lever↔Hammett. **Realistic optimum = SO₂CF₃** (cascade −0.227 ≈ NO₂'s −0.232 but electrochemically inert — NO₂ degrades NO₂→NH₂ on Os cycling → collapses cascade to the −1.5 worst case; CHEM.23). **Caveat:** max cascade-Δ ≠ *optimal* EBFC mediator — higher E°(Os) → **lowers OCV**; rule is cascade *thermodynamics*, exp Os opt (~+309 mV, Mano/Heller) balances driving-force vs overpotential | ① `os_mediator_series.json` | Fig 3b, Table 4 | **[① DONE]** |
| **3.4 Cathode DET (ZIF)** | bimetallic Cu-Co-Ce hopping; geom-fixed t_ij + **computed λ** (Nelsen, not assumed) → k_DET **borderline** (Cu-Co bottleneck ~turnover, ×1–30 not ×10⁵); honest λ-sensitivity + Ru/cMOF/enzyme-free mitigation — a *finding*, not a failure | scripts 24/25/35 | Fig 4, Table 3 | **[③ DONE]** |
| **3.5 Cascade & the PCM limit** | raw cascade uphill in *every* method; the ~1 eV gap **decomposes** (computed, ②) into **speciation** (chloro→aqua +0.51, bis-Im +0.30 eV) + **explicit solvation** (+0.20 eV / 3 Cl⁻-H₂O → full shell); [Os(H₂O)₆] benchmark recovers the ~1 V group-8 PCM error (n6→n18 +0.98 eV); QM/MM (Минаєв) = rigorous capstone | scripts 21/21d/33 + **34 ②** | Fig 5, Table 2 | **[② DONE]** + Minaev |
| **3.6 Protein environment on E°** | bound FAD-GDH E° = **−266 mV vs SHE** (verified, Sygmund & Ludwig 2022) — protein tunes free −208 → bound −266 (−58 mV, *better* donor → larger cascade driving force); active-site model from AF3 PDB (isoalloxazine + catalytic HIS537 / charged GLU61 / backbone amides). Rigorous QM-cluster E° = Мінаєв capstone (bundled w/ the cascade QM/MM) | ④ (canon fixed; QM-cluster deferred) | — | **[④ canon ✅ · QM-cluster → capstone]** |
| *(3.x brief)* thermal robustness | MD→DFT ensemble: FAD HOMO σ≪0.3 eV | script 27 | — | **[READY]** |
| *(3.x brief)* anode reorganization energy | FADH⁻/FADH• Nelsen 4-point → inner-sphere λ_i 0.39 eV (the physically-correct deprotonated couple rescues the script-29 radical-cation pathology); ≈ lit 0.7–0.8 w/ outer-sphere — *computed*, not assumed, parallels the cathode metal-λ | script 29b (CHEM.21) | — | **[CHEM.21 DONE]** |
| **4 Conclusion & Outlook** | cascade ET validated mechanistically; predictive mediator design rule; honest solvation lesson; EIS predictions for Ti-coin experimental closure; QM/MM capstone | SUMMARY L4c | — | **[READY]** |
| Back matter | CRediT · **Data availability** (repo + conda-lock — strong) · Funding · Conflicts · SI = scripts/goldens | — | — | **[READY]** |

## 4. Figure & table plan

- **Fig 1** (graphical abstract): the anode→Os→cathode cascade overlaid on the 3-zone gyroid anchor (metal↔xylem interface). [new art]
- **Fig 2**: AF3 structure + FAD depth + Beratan-Onuchic tunneling path (resSeq labels).
- **Fig 3**: (a) MO/Marcus cascade diagram + PCET E°; (b) **① LFER** — E°(Os) & cascade-Δ vs Hammett σ (the design-rule plot).
- **Fig 4**: ZIF Cu-Co-Ce hops + k_ET ladder (with computed λ, ③).
- **Fig 5** (methods centerpiece): PCM vs cluster-continuum solvation closing the cascade gap (②).
- **Tables**: T1 levels of theory · T2 cascade energetics (all methods) · T3 DET hops + λ · T4 mediator series E°/cascade-Δ vs σ.

## 5. Scope boundary

L1 (distance/path) + L3 (anode) + L3b (cathode) + mediator series + solvation methodology. **Out of scope** (→ other Статті): L2 MD stability → Стаття 2; L4 delta_t/EIS → Стаття 3 (cited here only as experimental-closure predictions).

## 6. Introduction reference scaffold (key anchors; expand to ~40–60)

- **EBFC reviews / field + challenges:** Pak et al. 2025 *Adv. Funct. Mater.* 10.1002/adfm.202415933; *Biosensors* 2025 (implantable EBFCs) 10.3390/bios15040218; Kundu 2026 *Fuel Cells*; "Tackling the Challenges of Enzymatic (Bio)Fuel Cells" *Chem. Rev.* 10.1021/acs.chemrev.9b00115.
- **Os-mediated FAD-GDH (experimental anchor):** Degani & Heller 1989 → Mano/Heller Os-polymers (+15…+489 mV, opt ~+309 mV); "Electron-Transfer Studies with FAD-GDH and Os polymers of different redox potentials."
- **Mediator design precedent (genre):** JPCB 10.1021/acs.jpcb.3c03740 (model-driven redox-mediator design, GOx).
- **Lever LFER:** Lever 1990 *Inorg. Chem.* 10.1021/ic00331a030; DFT↔Lever↔Hammett correlation *Inorg. Chem.* 10.1021/ic0105258.
- **Implicit-solvation redox benchmarks (methods lesson):** group-8 octahedral reduction potentials *JPCC* 10.1021/jp406772u; cluster-continuum Pliego-Riveros *JPCA* 10.1021/jp004192w; multistep explicit solvation *JCTC* 10.1021/acs.jctc.8b00982.
- **Flavin redox / protein tuning (④):** QM/MM flavin reduction potentials PMC4480342; protein-electrostatics flavin tuning RSC 10.1039/d5sc02960k; cluster vs QM/MM for protein redox *JCTC* 10.1021/acs.jctc.5c01656; laccase-CueO cluster precedent (Frontiers).
- **ZIF laccase-mimic cathode (③ context):** Cu/Zn-ZIF & Cu-ZIF-67 ORR nanozymes.

## 7. Writing workflow

Methods (strongest, reproducible) → Results (fill as ①②③④ land) → Introduction (longest, lit) → Discussion/Conclusion → Abstract + cover letter last → internal review → **IP gate** → submit. Pull every number from `SUMMARY.md` at draft time; if a result changes, change SUMMARY, not the paper twice.
