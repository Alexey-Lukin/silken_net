# 1. Introduction — draft (Стаття 1)

> **Draft section** (§1 of [`00_OUTLINE.md`](00_OUTLINE.md)). Voice per
> [`00_WRITING_GUIDE.md`](00_WRITING_GUIDE.md) §Voice. Citations are placeholders keyed to the
> [`00_OUTLINE.md`](00_OUTLINE.md) §6 reference scaffold — **expand to ~40–60 refs before submission**
> (the current draft under-cites; flagged inline as [REF]). Funnel: field → system → gap → contribution.

Enzymatic biofuel cells (EBFCs) convert the chemical energy of a fuel such as glucose directly into
electricity using redox enzymes as catalysts, at ambient temperature and physiological pH [REF: EBFC
reviews — Pak 2025; *Chem. Rev.* 2019]. Their low power density rules them out as bulk power sources but
makes them attractive for a niche that conventional batteries serve poorly: self-powered, implantable or
environmentally-embedded sensors that must run unattended for years on a locally available fuel [REF:
implantable EBFCs]. The work reported here is motivated by one such application — a tree-integrated
sensor powered at the metal–xylem interface — but the electron-transfer questions it raises are generic
to the EBFC anode→mediator→cathode chain.

A representative high-performance architecture, and the one modelled here, pairs an FAD-dependent glucose
dehydrogenase (FAD-GDH) anode with an osmium redox-polymer mediator and a laccase (or laccase-mimetic)
oxygen-reducing cathode [REF: Heller/Mano Os-polymer series]. FAD-GDH is oxygen-insensitive and
glucose-specific, but its catalytic flavin is buried ~1.5 nm inside the protein, too far for direct
electron transfer, so a mediator is required; the osmium polymer is tuned, empirically, to a redox
potential that trades cascade driving force against cell voltage (the experimental optimum lies near
+0.3 V) [REF: Mano/Heller potential series]. On the cathode, direct electron transfer from a metal-organic
framework nanozyme that mimics the laccase copper centres removes a second fragile enzyme [REF: ZIF
laccase-mimic ORR]. The persistent engineering challenges of such cells — interfacial electron-transfer
efficiency, direct-electron-transfer kinetics, multi-year enzyme and mediator stability, and metal-ion
leaching — are all, at root, questions about electron movement and molecular environment.

Yet the EBFC literature addresses these questions almost entirely at the experimental and macro-kinetic
level — voltammetry, impedance, and reaction–diffusion modelling — and only rarely at the level of
electronic structure [REF: design-by-DFT precedent, JPCB 2024]. The redox potentials, reorganisation
energies, electronic couplings and solvation responses that *govern* the cascade are seldom computed for
a complete, realistic system. This is the gap we address.

We report a first-principles, electronic-structure account of the electron-transfer energetics of a
complete Gen-2.0 EBFC chain, and — equally — an honest assessment of where affordable
implicit-solvation density-functional theory reaches its limit on this problem. We (i) reproduce the
proton-coupled FAD redox potential to within ~50 mV of experiment with a thermodynamic proton reference;
(ii) establish a Hammett structure–activity rule for the osmium mediator that is predictive and
rationalises the empirical optimum; (iii) compute the bimetallic-ZIF cathode direct-electron-transfer
kinetics with first-principles reorganisation energies, finding a borderline, λ-limited margin and the
design levers that relieve it; and (iv) show that the apparent uphill cascade is a *quantified* limit of
continuum solvation on charged transition-metal couples — decomposed into mediator speciation and
differential solvation, benchmarked against the known group-8 implicit-solvation error — rather than a
failure of the chemistry. The contribution is therefore both a set of mechanistic design rules and a
transferable methodological lesson; it is explicitly *not* a re-confirmation of the experimentally known
cascade. All calculations are scripted and reproducible from a version-pinned environment.
