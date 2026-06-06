# 3. Results and Discussion — draft (Стаття 1)

> **Draft section** (prose for §3 of [`00_OUTLINE.md`](00_OUTLINE.md)). Numbers are pulled from
> [`SUMMARY.md`](../SUMMARY.md) (One-Home) at draft time — if a value changes, change SUMMARY first,
> then re-pull here. Voice: academic-formal, honest, systems-clear (see
> [`00_WRITING_GUIDE.md`](00_WRITING_GUIDE.md) §Voice). EN (J. Phys. Chem. B).

We follow the electron from the buried flavin to the external circuit — anode → mediator → cathode —
treating each step as a link whose energetics we can compute and test against experiment.

## 3.1 Architecture and the tunnelling pathway

The AlphaFold 3 model places the FAD N5 atom **16.0 Å** below the protein surface (Tyr90 OH as the
nearest exit), inside the 18–20 Å window over which biological electron tunnelling remains efficient.
A Beratan–Onuchic pathway analysis identifies a dominant through-bond route, FAD → Ala261 → Thr260 →
Thr288 (PDB residue numbering), with an effective decay **β·d = 2.05** — feasible for the mediated
transfer the architecture requires. The exit residues are well-ordered in the prediction (pLDDT ≫ 80),
so the path is a structural feature, not a disordered artefact. The deglycosylated production variant
(eleven N→Q substitutions) preserves this geometry.

## 3.2 Anode PCET: the FAD redox potential

Treating the FAD/FADH₂ couple with a thermodynamic proton reference (rather than an explicit, and in
implicit solvent grossly over-stabilised, hydronium ion) recovers **E°(FAD/FADH₂) = −158 mV vs NHE** —
within ~50 mV of the experimental free-flavin value. This is the paper's clean positive result: a
proton-coupled redox potential of a biological cofactor, reproduced by implicit-solvation DFT once the
proton is handled correctly. It also isolates the cascade discrepancy discussed in §3.5 to the
mediator side of the chain, not the flavin.

The inner-sphere reorganisation energy of the first anode oxidation was likewise computed, not assumed.
The naïve FADH₂/FADH₂•⁺ radical-cation is geometrically pathological in continuum solvent (it
fragments on relaxation); the physically correct, pH-7 first electron transfer is the deprotonated
**FADH⁻ → FADH• + e⁻** couple, whose Nelsen four-point analysis gives an inner-sphere **λ_i = 0.39 eV**.
With the Marcus outer-sphere term this is consistent with the literature flavin value (0.7–0.8 eV) —
now from first principles.

## 3.3 A structure–activity rule for the osmium mediator

Varying the 4,4′-bipyridine substituents across the experimental potential range gives a clean **Hammett
linear free-energy relationship**: the Os(III/II) reduction energy is linear in σ_para with slope
≈ **−0.93 eV per σ unit**, triangulated against the additive Lever E_L scheme and the measured series.
Electron-withdrawing substituents raise E°(Os) and improve the FADH₂→Os cascade alignment, giving a
predictive design handle rather than a one-off optimisation.

The rule also exposes a practical subtlety. The maximal cascade driving force is reached by strongly
electron-withdrawing groups, but the strongest (NO₂) is electrochemically **unstable** at the operating
pH (it reduces to the amine on cycling, collapsing the cascade to its worst case). The realistic
optimum is therefore the inert high-σ **SO₂CF₃** (cascade −0.227 eV, matching NO₂'s −0.232 eV but
without the degradation), with CF₃ a milder inert alternative. Crucially, the cascade-thermodynamic
optimum is *not* the cell optimum: a higher E°(Os) lowers the open-circuit voltage, so the experimental
optimum (~+309 mV) balances driving force against overpotential.

## 3.4 Direct electron transfer through the ZIF cathode

Inter-metal couplings in the bimetallic Cu–Co–Ce nanozyme were obtained from charge-localised ΔSCF on
clash-free cluster geometries (a bridging imidazole that had collided with the second metal was
deprotonated to the imidazolate, restoring physical coordination). With reorganisation energies
computed by the two-sphere Nelsen method rather than assumed, the **Cu–Co hop is the bottleneck**, and
its rate sits at **~enzymatic turnover** — a margin of order ×1–30, not the orders of magnitude an
earlier (geometry- and λ-) artefact had suggested.

This is a finding, not a failure, and we present it with its sensitivity. The rate depends
exponentially on λ: at the literature first-row values the Cu–Co hop is borderline (≈ ×1.4 over
turnover); B3LYP over-estimates the first-row λ (the Co couple by ≈ 2×, a spin-crossover artefact),
which would push it lower; and a low-λ metal removes the limitation entirely — replacing Co by **Ru**
(computed λ 0.78 eV vs Co ≈ 3 eV) restores a ~×31 margin. The honest reading is a borderline,
possibly co-limiting cathode whose three design levers — a low-λ metal, conductive-MOF band transport,
or an acid-stable enzyme-free single-atom catalyst — are set out and ranked by their viability at the
acidic Zone 3 (pH ≈ 4.5). The cathode EIS of the forthcoming Ti-coin experiment is the decisive
empirical test.

## 3.5 The cascade and the limits of implicit solvation

The raw computed cascade FADH₂→Os is **uphill in every method** (Koopmans Δε −0.91 eV; adiabatic ΔSCF
ωB97X +0.88 eV), whereas the experimentally anchored driving force is **downhill, +466 mV / −0.47 eV**
(from the verified E°s, §3.2 and §3.6). The ~1.3 eV discrepancy is the paper's methodological core, and
we decompose rather than excuse it.

Two computed contributions account for it. **Mediator speciation** — the cited experimental potential
and the real Os–PVI polymer correspond to the aqua or bis-imidazole complex, not the chloro model used
to define the cascade — shifts the redox energy by **+0.51 eV (aqua)** and **+0.30 eV (bis-imidazole)**;
the stronger σ-donor imidazole lowers E°(Os) relative to the weakly-donating aqua ligand, reproducing
the experimental ordering of osmium-imidazole potentials. **Differential solvation** of the
charge-changing octahedral couple adds a further ~0.20 eV for three explicit chloride-shell waters and
trends toward the full shell; benchmarked on [Os(H₂O)₆]³⁺/²⁺, where adding the second hydration shell
shifts the potential by **+0.98 eV**, reproducing the known ~1 V group-8 implicit-solvation error. The
residual is thus a quantified, transferable limitation of continuum solvent on charged transition-metal
redox couples — not a chemistry problem — whose rigorous closure is explicit-water QM/MM of the correct
species.

## 3.6 The protein environment on the FAD potential

The bound enzyme potential is **E°(FAD-GDH) = −266 mV vs SHE** (an experimentally verified value); the
protein shifts the cofactor from the free-flavin −208 mV to a more negative −266 mV, i.e. makes FAD a
*better* electron donor and enlarges the cascade driving force — a mechanistic gain, not a gap. An
active-site cluster (isoalloxazine plus the catalytic His537, the charged Glu61 and the backbone amide
contacts within ~5 Å) is defined from the AF3 structure; the rigorous QM-cluster potential, sensitive
to His/Glu protonation, is reserved for the explicit-solvent QM/MM capstone.

## 3.7 Thermal robustness (brief)

Across a molecular-dynamics ensemble the FAD frontier orbital is thermally stable (HOMO −5.59 ± 0.06 eV,
σ ≪ 0.3 eV), so the single-geometry redox energetics above are representative of the room-temperature
ensemble rather than of one fortuitous snapshot.
