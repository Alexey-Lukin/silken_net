# 1. Introduction — draft (Стаття 1)

> **Draft section** (§1 of [`00_OUTLINE.md`](00_OUTLINE.md)). Voice per
> [`00_WRITING_GUIDE.md`](00_WRITING_GUIDE.md) §Voice. Funnel: field → system → gap → contribution.
> Citations are **author-year**, keyed to the reference scaffold at the foot of this file (built from
> [`00_OUTLINE.md`](00_OUTLINE.md) §6 + [`00_WRITING_GUIDE.md`](00_WRITING_GUIDE.md) §7). DOIs marked
> **[verify]** are method-classics cited from domain knowledge and must be confirmed in the reference
> manager before submission; the OUTLINE §6 DOIs are carried verbatim. **Expand to ~40–60 refs**
> (ACS numbered style, via Zotero/Paperpile) at draft-freeze — do not hand-format the final list.

## Why autonomous biofuel-cell sensing

Enzymatic biofuel cells (EBFCs) convert the chemical energy of a fuel such as glucose directly into
electricity using redox enzymes as catalysts, operating at ambient temperature and physiological pH
(Pak et al., 2025; Mano & de Poulpiquet, 2018). Their power density is modest by comparison with
abiotic fuel cells, which excludes them from bulk power generation but suits a niche that conventional
batteries serve poorly: self-powered, implantable or environmentally-embedded sensors that must run
unattended for years on a fuel drawn from their surroundings (Biosensors review, 2025; Kundu, 2026).
The work reported here is motivated by one such application — a tree-integrated sensor powered at the
titanium–xylem interface, where the dilute sugars of sap are the local fuel — but the electron-transfer
questions it raises are generic to the EBFC anode→mediator→cathode chain and, we argue, are best posed
at the level of electronic structure.

## The FAD-GDH / osmium / laccase-ZIF system

The architecture modelled here, representative of the high-performance mediated designs in the
literature, pairs an FAD-dependent glucose dehydrogenase (FAD-GDH) anode with an osmium redox-polymer
mediator and an oxygen-reducing cathode (Degani & Heller, 1987; Heller–Mano wired enzymes). FAD-GDH is the
enzyme of choice for the anode because it is oxygen-insensitive and glucose-specific, unlike the
classical glucose oxidase; but its catalytic flavin sits roughly 1.5 nm below the protein surface — too
far for efficient direct electron transfer — so an electron relay is required. The osmium
poly(vinylimidazole) polymer fills that role, its redox potential tuned empirically across a wide range
(≈ +15 to +489 mV vs NHE, optimum near +0.3 V) to balance the driving force handed to the cascade
against the open-circuit voltage it costs the cell (Zafar et al., 2012). On the cathode side, direct
electron transfer to a bimetallic zeolitic-imidazolate-framework (ZIF) nanozyme that mimics the
multicopper centres of laccase removes a second fragile enzyme from the device, trading turnover for
robustness (Cu/Zn-ZIF and Cu-ZIF-67 ORR nanozymes; cf. laccase-CueO cluster studies). The recurring
engineering challenges of such cells — interfacial electron-transfer efficiency, direct-electron-transfer
kinetics at the cathode, multi-year enzyme and mediator stability, and metal-ion leaching from the
support — are, at root, the same question asked four ways: how an electron moves, and how the molecular
environment governs that motion (Chem. Rev., 2019).

## The gap: an electronic-structure account is missing

Despite that, the EBFC literature addresses these questions almost entirely at the experimental and
macro-kinetic level — cyclic voltammetry, electrochemical impedance spectroscopy, and
reaction–diffusion modelling — and only rarely at the level of electronic structure. The toolbox to do
so is mature and was built for exactly this purpose: Marcus theory relates electron-transfer rates to a
driving force and a reorganization energy (Marcus & Sutin, 1985); the Beratan–Onuchic pathway model
estimates electronic coupling through a protein from its covalent and hydrogen-bonded connectivity
(Beratan et al., 1991); the Nelsen four-point scheme computes reorganization energies from first
principles (Nelsen et al., 1987); ΔSCF total-energy differences give redox energetics where
frontier-orbital (Koopmans) estimates fail; a thermodynamic proton reference handles proton-coupled
electron transfer without the pathologies of an explicit hydronium ion in continuum solvent (Isse &
Gennaro, 2010); and cluster-continuum micro-solvation corrects the well-known shortcomings of pure
implicit solvent on small, charged species (Pliego & Riveros, 2001). Individually these methods are
standard. What is missing is their *integrated* application to a complete, realistic EBFC chain — the
redox potentials, reorganization energies, electronic couplings and solvation responses that actually
govern the cascade, computed for the same system, end to end. That integration is the gap this paper
addresses; model-driven mediator design at this level has begun for glucose oxidase (JPCB, 2024) but
not for the FAD-GDH/Os/ZIF system.

## A methodological hazard worth naming up front

A complete electronic-structure account of this chain must cross a known hazard: implicit-solvation DFT
systematically misestimates the reduction potentials of small, highly charged transition-metal complexes,
with errors approaching ~1 V for group-8 (Fe/Ru/Os) octahedra because a continuum cannot reproduce the
directional second-shell hydrogen bonding around a +2/+3 couple (group-8 octahedral benchmark, JPCC;
Pliego & Riveros, 2001). The osmium mediator at the centre of this device is precisely such a couple.
Rather than treat this as a nuisance to be absorbed into an empirical correction, we make it part of the
result — quantifying the error on a clean benchmark and decomposing the device-level discrepancy into its
physical contributions. Reproducibility is treated with the same seriousness: every calculation is
scripted, seeded, and run from a version-pinned environment, in line with current best-practice DFT
reporting (Bursch et al., 2022; Boggs, 1998).

## Contribution

We report a first-principles, electronic-structure account of the electron-transfer energetics of a
complete Gen-2.0 EBFC chain, and — equally — an honest assessment of where affordable
implicit-solvation density-functional theory reaches its limit on this problem. Specifically, we (i)
reproduce the proton-coupled FAD redox potential to within ~50 mV of experiment using a thermodynamic
proton reference, isolating the cascade discrepancy to the mediator rather than the flavin; (ii)
establish a Hammett structure–activity relationship for the osmium mediator that is predictive and
rationalizes the empirically observed optimum (Lever, 1990; DFT–Lever–Hammett correlation, 2001); (iii) compute the
bimetallic-ZIF cathode direct-electron-transfer kinetics with first-principles reorganization energies,
finding a borderline, λ-limited margin — a corrected finding, not the orders-of-magnitude artefact an
earlier geometry-and-λ error had implied — together with the design levers (a low-reorganization metal,
conductive-MOF band transport, or an acid-stable enzyme-free catalyst) that relieve it; and (iv) show
that the apparent uphill cascade is a *quantified* limitation of continuum solvation on charged
transition-metal couples — decomposed into a chloro↔bis-imidazole differential-solvation bracket and a
4,4′-dimethyl substituent term, benchmarked against the known group-8 error — rather than a failure of the chemistry. The flavin redox tuning by the
protein environment is computed in the same spirit (Bhattacharyya et al., 2007; protein-electrostatics
flavin tuning, 2025).

The contribution is therefore both a set of mechanistic design rules and a transferable methodological
lesson; it is explicitly *not* a re-confirmation of the experimentally known cascade. The scope is the
electron-transfer energetics — protein architecture and tunnelling distance, the anode redox and
reorganization energetics, the cathode direct-electron-transfer kinetics, the mediator structure–activity
series, and the solvation methodology; long-timescale matrix stability and the device-level
delta-t/impedance behaviour are deferred to companion work and enter here only as experimental-closure
predictions for the forthcoming titanium-coin measurements. All calculations are reproducible from the
accompanying version-pinned scripts.

---

## References (draft scaffold — expand to ~40–60, ACS numbered, via reference manager)

> OUTLINE §6 / WRITING_GUIDE §7 DOIs carried verbatim. **[verify]** = method-classic cited from domain
> knowledge — confirm the exact DOI/locator in the reference manager before submission. Not yet
> exhaustive: the field/challenge, Os-GcGDH experimental series, and ZIF-laccase-mimic cathode clusters
> each warrant several more primary citations (see OUTLINE §6 groupings).

**EBFC field & challenges**
- Pak, J. et al. *Adv. Funct. Mater.* **2025**. doi:10.1002/adfm.202415933
- Implantable EBFCs (review). *Biosensors* **2025**, *15*, 218. doi:10.3390/bios15040218
- Kundu, D. et al. From fundamentals to applications: a comprehensive review of enzymatic biofuel cells. *Fuel Cells* **2026**. doi:10.1002/fuce.70081
- Tackling the Challenges of Enzymatic (Bio)Fuel Cells. *Chem. Rev.* **2019**. doi:10.1021/acs.chemrev.9b00115
- Mano, N.; de Poulpiquet, A. O₂ reduction in enzymatic biofuel cells. *Chem. Rev.* **2018**, *118*, 2392. doi:10.1021/acs.chemrev.7b00220

**Os-mediated FAD-GDH (experimental anchor)**
- Degani, Y.; Heller, A. Direct electrical communication between chemically modified enzymes and metal electrodes. 1. Electron transfer from glucose oxidase via covalently bound electron relays. *J. Phys. Chem.* **1987**, *91*, 1285. doi:10.1021/j100290a001
- Ohara, T. J.; Rajagopalan, R.; Heller, A. Glucose electrodes based on cross-linked [Os(bpy)₂Cl]⁺/²⁺ complexed poly(1-vinylimidazole) films. *Anal. Chem.* **1994**. doi:10.1021/ac00071a031
- Mao, F.; Mano, N.; Heller, A. Long tethers binding redox centers to polymer backbones enhance electron transport in enzyme "wiring" hydrogels. *J. Am. Chem. Soc.* **2003**, *125*, 4951. doi:10.1021/ja029510e
- Zafar, M. N.; Ludwig, R. et al. Characterization of different FAD-dependent glucose dehydrogenases for possible use in glucose-based biosensors and biofuel cells (j_max anchor). *Anal. Bioanal. Chem.* **2011**. doi:10.1007/s00216-011-5650-7
- Zafar, M. N.; Wang, X.; Sygmund, C.; Ludwig, R.; Leech, D.; Gorton, L. Electron-transfer studies with a new FAD-dependent glucose dehydrogenase and osmium polymers of different redox potentials (GcGDH wired by six Os polymers spanning **+15 to +489 mV vs NHE** — source for the mediator potential window). *Anal. Chem.* **2012**, *84*, 334. doi:10.1021/ac202647z
- Schachinger, F.; Ma, S.; Ludwig, R. Redox potential of FAD-dependent glucose dehydrogenase. *Electrochem. Commun.* **2022**, *146*, 107405. doi:10.1016/j.elecom.2022.107405 <!-- ⚠️ scaffold мав "Sygmund, C.; Ludwig, R."; ця стаття дає E° = −265 mV (не −266) для GcGDH — звірити значення по всьому SSOT -->
- Sygmund, C.; Ludwig, R. et al. Heterologous overexpression of *Glomerella cingulata* FAD-dependent glucose dehydrogenase in *E. coli* and *P. pastoris* (our GcGDH). *Microb. Cell Fact.* **2011**, *10*, 106. doi:10.1186/1475-2859-10-106

**Mediator design precedent (genre)**
- Model-driven redox-mediator design (GOx). *J. Phys. Chem. B* **2024**. doi:10.1021/acs.jpcb.3c03740

**LFER / Lever electrochemical parametrization**
- Lever, A. B. P. *Inorg. Chem.* **1990**, *29*, 1271. doi:10.1021/ic00331a030
- DFT ↔ Lever ↔ Hammett correlation. *Inorg. Chem.* doi:10.1021/ic0105258
- Hammett, L. P. The effect of structure upon the reactions of organic compounds. Benzene derivatives. *J. Am. Chem. Soc.* **1937**, *59*, 96. doi:10.1021/ja01280a022

**Implicit-solvation redox benchmarks (the methods lesson)**
- Group-8 octahedral reduction potentials (PCM ~1 V error). *J. Phys. Chem. C*. doi:10.1021/jp406772u
- Pliego, J. R.; Riveros, J. M. Cluster-continuum model. *J. Phys. Chem. A* **2001**. doi:10.1021/jp004192w
- Multistep explicit solvation of ions. *J. Chem. Theory Comput.* **2019**. doi:10.1021/acs.jctc.8b00982

**Flavin redox & protein tuning**
- Bhattacharyya, S.; Stankovich, M. T.; Truhlar, D. G.; Gao, J. Combined QM/MM simulations of one- and two-electron reduction potentials of flavin cofactor in water, MCAD, and cholesterol oxidase. *J. Phys. Chem. A* **2007**, *111*, 5729. doi:10.1021/jp071526+ (PMC4480342)
- Protein-electrostatics tuning of flavin. *Chem. Sci.* **2025**. doi:10.1039/d5sc02960k
- Cluster vs QM/MM for protein redox. *J. Chem. Theory Comput.* doi:10.1021/acs.jctc.5c01656
- Jiang, Q. et al. Feasible cluster model method for simulating the redox potentials of laccase CueO and its variant. *Front. Bioeng. Biotechnol.* **2022**, *10*, 957694. doi:10.3389/fbioe.2022.957694

**ZIF laccase-mimic cathode**
- Glucose/O₂ enzymatic biofuel cell with a laccase-mimicking nanozyme cathode for efficient O₂ reduction (onset 841 mV). *Anal. Chem.* doi:10.1021/acs.analchem.6c00462
- Cu-doped ZIF-67 electrocatalyst for the oxygen reduction reaction. *J. Electrochem. Energy Convers. Storage* **2021**, *18*, 021001. doi:10.1115/1.4047331
- Solomon, E. I. et al. Nature of the intermediate formed in the reduction of O₂ to H₂O at the trinuclear copper cluster active site in native laccase. *J. Am. Chem. Soc.* **2001**. doi:10.1021/ja0114052

**Electron-transfer theory & methods (classics)**
- Marcus, R. A.; Sutin, N. Electron transfers in chemistry and biology. *Biochim. Biophys. Acta* **1985**, *811*, 265. doi:10.1016/0304-4173(85)90014-X
- Beratan, D. N.; Betts, J. N.; Onuchic, J. N. Protein electron transfer rates set by the bridging secondary and tertiary structure. *Science* **1991**, *252*, 1285. doi:10.1126/science.1656523
- Nelsen, S. F.; Blackstock, S. C.; Kim, Y. Estimation of inner shell Marcus terms for amino nitrogen compounds by molecular orbital calculations. *J. Am. Chem. Soc.* **1987**, *109*, 677. doi:10.1021/ja00237a007
- Isse, A. A.; Gennaro, A. Absolute potential of the standard hydrogen electrode and the problem of interconversion of potentials in different solvents. *J. Phys. Chem. B* **2010**, *114*, 7894. doi:10.1021/jp100402x
- Abramson, J. et al. Accurate structure prediction of biomolecular interactions with AlphaFold 3. *Nature* **2024**, *630*, 493. doi:10.1038/s41586-024-07487-w

**DFT best-practice & reporting standard**
- Bursch, M. et al. Best-practice DFT protocols. *Angew. Chem. Int. Ed.* **2022**. doi:10.1002/anie.202205735
- Boggs, J. E. Reporting electronic-structure calculations. *Pure Appl. Chem.* **1998**, *70*, 1015.

**DFT functionals, basis sets & solvation (computational methods)**
- Becke, A. D. Density-functional thermochemistry. III. The role of exact exchange (B3LYP). *J. Chem. Phys.* **1993**, *98*, 5648. doi:10.1063/1.464913
- Lee, C.; Yang, W.; Parr, R. G. Development of the Colle–Salvetti correlation-energy formula into a functional of the electron density (LYP). *Phys. Rev. B* **1988**, *37*, 785. doi:10.1103/PhysRevB.37.785
- Chai, J.-D.; Head-Gordon, M. Systematic optimization of long-range-corrected hybrid density functionals (ωB97X). *J. Chem. Phys.* **2008**, *128*, 084106. doi:10.1063/1.2834918
- Hehre, W. J.; Ditchfield, R.; Pople, J. A. Self-consistent molecular-orbital methods. XII. Further extensions of Gaussian-type basis sets (6-31G*). *J. Chem. Phys.* **1972**, *56*, 2257. doi:10.1063/1.1677527
- Weigend, F.; Ahlrichs, R. Balanced basis sets of split-valence, triple-zeta and quadruple-zeta valence quality for H to Rn (def2). *Phys. Chem. Chem. Phys.* **2005**, *7*, 3297. doi:10.1039/b508541a
- Hay, P. J.; Wadt, W. R. Ab initio effective core potentials for molecular calculations (LANL2DZ). *J. Chem. Phys.* **1985**, *82*, 270. doi:10.1063/1.448799
- Cossi, M.; Rega, N.; Scalmani, G.; Barone, V. Energies, structures and electronic properties of molecules in solution with the C-PCM solvation model. *J. Comput. Chem.* **2003**, *24*, 669. doi:10.1002/jcc.10189
- Sun, Q. et al. Recent developments in the PySCF program package. *J. Chem. Phys.* **2020**, *153*, 024109. doi:10.1063/5.0006074
