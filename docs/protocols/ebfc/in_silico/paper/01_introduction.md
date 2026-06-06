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
mediator and an oxygen-reducing cathode (Degani & Heller, 1989; Heller–Mano wired enzymes). FAD-GDH is the
enzyme of choice for the anode because it is oxygen-insensitive and glucose-specific, unlike the
classical glucose oxidase; but its catalytic flavin sits roughly 1.5 nm below the protein surface — too
far for efficient direct electron transfer — so an electron relay is required. The osmium
poly(vinylimidazole) polymer fills that role, its redox potential tuned empirically across a wide range
(≈ +15 to +489 mV vs Ag/AgCl, optimum near +0.3 V) to balance the driving force handed to the cascade
against the open-circuit voltage it costs the cell (Mano et al., 2003). On the cathode side, direct
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
transition-metal couples — decomposed into mediator speciation and differential solvation and benchmarked
against the known group-8 error — rather than a failure of the chemistry. The flavin redox tuning by the
protein environment is computed in the same spirit (QM/MM flavin studies, 2015; protein-electrostatics
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
- Degani, Y.; Heller, A. *J. Phys. Chem.* **1989**. [DOI: verify] <!-- ⚠️ конфлікт журнал/рік: JPC-стаття = 1987, 91, 1285 (doi:10.1021/j100290a001); 1989-а — це JACS 111, 2357 (redox polymers). Уточнити, який пейпер цитуємо -->
- Heller, A.; Mano, N. Os redox polymers (wired enzymes). [DOI: verify]
- Mao, F.; Mano, N.; Heller, A. Long tethers binding redox centers to polymer backbones enhance electron transport in enzyme "wiring" hydrogels. *J. Am. Chem. Soc.* **2003**, *125*, 4951. doi:10.1021/ja029510e
- Electron-Transfer Studies with FAD-GDH and Os polymers of different redox potentials. [DOI: verify]
- Schachinger, F.; Ma, S.; Ludwig, R. Redox potential of FAD-dependent glucose dehydrogenase. *Electrochem. Commun.* **2022**, *146*, 107405. doi:10.1016/j.elecom.2022.107405 <!-- ⚠️ scaffold мав "Sygmund, C.; Ludwig, R."; ця стаття дає E° = −265 mV (не −266) для GcGDH — звірити значення по всьому SSOT -->

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
- Combined QM/MM simulations of one- and two-electron reduction potentials of flavin cofactor in water, medium-chain acyl-CoA dehydrogenase, and cholesterol oxidase. **2007**. PMC4480342 (PMID 17567113) [author + locator: verify] <!-- scaffold мав "2015"; PMID date = 2007 -->
- Protein-electrostatics tuning of flavin. *Chem. Sci.* **2025**. doi:10.1039/d5sc02960k
- Cluster vs QM/MM for protein redox. *J. Chem. Theory Comput.* doi:10.1021/acs.jctc.5c01656
- Jiang, Q. et al. Feasible cluster model method for simulating the redox potentials of laccase CueO and its variant. *Front. Bioeng. Biotechnol.* **2022**, *10*, 957694. doi:10.3389/fbioe.2022.957694

**ZIF laccase-mimic cathode**
- Cu/Zn-ZIF ORR nanozyme. [DOI: verify]
- Cu-ZIF-67 ORR nanozyme. [DOI: verify]

**Electron-transfer theory & methods (classics)**
- Marcus, R. A.; Sutin, N. Electron transfers in chemistry and biology. *Biochim. Biophys. Acta* **1985**, *811*, 265. doi:10.1016/0304-4173(85)90014-X
- Beratan, D. N.; Betts, J. N.; Onuchic, J. N. Protein electron transfer rates set by the bridging secondary and tertiary structure. *Science* **1991**, *252*, 1285. doi:10.1126/science.1656523
- Nelsen, S. F.; Blackstock, S. C.; Kim, Y. Estimation of inner shell Marcus terms for amino nitrogen compounds by molecular orbital calculations. *J. Am. Chem. Soc.* **1987**, *109*, 677. doi:10.1021/ja00237a007
- Isse, A. A.; Gennaro, A. Absolute potential of the standard hydrogen electrode and the problem of interconversion of potentials in different solvents. *J. Phys. Chem. B* **2010**, *114*, 7894. doi:10.1021/jp100402x
- Abramson, J. et al. Accurate structure prediction of biomolecular interactions with AlphaFold 3. *Nature* **2024**, *630*, 493. doi:10.1038/s41586-024-07487-w

**DFT best-practice & reporting standard**
- Bursch, M. et al. Best-practice DFT protocols. *Angew. Chem. Int. Ed.* **2022**. doi:10.1002/anie.202205735
- Boggs, J. E. Reporting electronic-structure calculations. *Pure Appl. Chem.* **1998**, *70*, 1015.
