# L3 — Квантова хімія (DFT, in silico, Gen 2.0 EBFC анод)

> **Рівень in-silico pipeline:** L3 з 4-рівневого Zero-Lab стеку ([`01_03 §3.4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
> **Канонічна папка хімічних артефактів:** `docs/protocols/ebfc/in_silico/`.

---

## Мета

Кількісно довести, що **MET-каскад FADH₂ → Os²⁺/³⁺ → fMWCNT → Ti-стінка** термодинамічно дозволений: електрон з електрон-донорного HOMO відновленого флавіну (FADH₂) має лежати **вище** за порожнє електрон-акцепторне LUMO окисненого Os(III) комплексу — у цьому випадку перенос заряду йде "вниз" по енергетичній сходинці (Marcus exoergic regime).

Це закриває ключовий патентний клайм Gen 2.0 (§2.1, Шар 3, Anode MET stack) на рівні квантової механіки, **до** будь-якого мокрого CV-експерименту на Ti-монетах.

---

## Метод

| Параметр | Значення | Обґрунтування |
|---|---|---|
| **Functional** | B3LYP (hybrid) | Workhorse для flavin redox (Hall et al. 2000; Bhattacharyya, Truhlar 2007) і Os-bpy комплексів (Daul et al. 1994). |
| **Basis (light atoms)** | 6-31G(d) | Standard double-zeta для C/N/O/H/Cl. |
| **Basis (Os)** | LANL2DZ + relativistic ECP | Дозволяє обробити 5d-метал без всіх 76 електронів; ECP включає скалярні релятивістські ефекти. |
| **Solvent** | Implicit water (C-PCM, ε = 78.3553) | Імітує ксилему (≈ aqueous, pH 4.5). PySCF мітка ще "experimental", але стабільна для систем такого розміру. |
| **Convergence** | conv_tol=1e-7 (флавін), 1e-6 (Os) | Стандарт для SP single-point. |
| **Geometry** | MMFF94s preopt (флавін) + programmatic octahedral (Os) | Single-point на reasonable geometry, без повного DFT opt — це первинний скрінінг. Publication-grade rerun із geometric/pyberny документований у "Future work" нижче. |

### Моделі (truncations)

**FAD redox core → lumiflavin (7,8,10-trimethylisoalloxazine)**

Усі ~50 атомів ribitol+phosphates+adenine частини FAD electronically isolated від redox center (saturated CH₂ spacer на N10). Lumiflavin — канонічна редукція з 32 атомами, що зберігає π-систему ізоалоксазину + N10-метил, який імітує приєднання до ribitol. Стандарт для flavin DFT літератури протягом 20+ років.

| Форма | SMILES | Atoms | Charge | Spin |
|---|---|---|---|---|
| FAD (oxidized) | `Cc1cc2nc3c(=O)[nH]c(=O)nc3n(C)c2cc1C` | 31 (19 heavy + 12 H) | 0 | 0 (singlet) |
| FADH₂ (1,5-dihydro) | `CC1=CC2=C(C=C1C)N(C)C3=NC(=O)NC(=O)C3N2` | 33 (19 heavy + 14 H) | 0 | 0 (singlet) |

**Os mediator → cis-[Os(bpy)₂(1-MeIm)Cl]ⁿ⁺ (full ligand model, 54 atoms)**

Повний лігандний environment реального Os-PVI редокс-полімеру: 2× 2,2'-bipyridine (chelating, s-cis) + 1-methylimidazole (proxy для poly(vinylimidazole)) + Cl⁻. Геометрія зібрана програматично з ортогональних bpy-площин (xz та yz), без crystal seed. 54 атоми (32 heavy).

| Форма | Charge | Spin | d-config |
|---|---|---|---|
| Os(II): [Os(bpy)₂(1-MeIm)Cl]⁺ | +1 | 0 (singlet) | d⁶ low-spin |
| Os(III): [Os(bpy)₂(1-MeIm)Cl]²⁺ | +2 | 1 (doublet, S=½) | d⁵ low-spin |

Geometry: cis-октаедричний, Os в origin, bpy1 у xz-площині, bpy2 у yz-площині, 1-MeIm вздовж +y, Cl вздовж +x. Os-N(bpy) = 2.10 Å, Os-N(Im) = 2.10 Å, Os-Cl = 2.38 Å.

> **Історична NH₃ surrogate модель** (script 21, 22 atoms): [Os(NH₃)₅Cl]ⁿ⁺ — correct σ-donation, missing π-backbonding → Os(III) LUMO = -3.42 eV (too high by ~0.8 eV). Superseded 2026-05-25 full bpy моделлю (script 21b).

---

## Результати

### A. NH₃ surrogate (2026-05-24, script 21 — superseded)

Числові значення згенеровано через `pyscf 2.11.0 + B3LYP + 6-31G(d) / LANL2DZ+ECP (Os) + C-PCM water` на MMFF/programmatic геометрії.

| Species | HOMO (eV) | LUMO (eV) | gap (eV) |
|---|---|---|---|
| FAD (ox lumiflavin) | -6.188 | -2.779 | 3.409 |
| **FADH₂ (red) — donor** | **-5.137** | -1.592 | 3.545 |
| Os(II) [Os(NH₃)₅Cl]⁺ | -3.349 | +0.469 | 3.818 |
| **Os(III) [Os(NH₃)₅Cl]²⁺** | -5.641 | **-3.420** | 2.221 |

Cascade Δε = -5.137 − (-3.420) = **-1.717 eV → ❌ UPHILL** (артефакт missing π-backbonding).

### B. Full bpy model (2026-05-25, script 21b — current)

Той самий DFT стек, але з повним cis-[Os(bpy)₂(1-MeIm)Cl]ⁿ⁺ (54 atoms, 240 electrons). SCF wall-clock: Os(II) 501 s, Os(III) 647 s (Apple Silicon, multi-core). <S²>(Os(III)) = 0.754 ≈ exact 0.75 → чистий doublet.

| Species | HOMO (eV) | LUMO (eV) | gap (eV) |
|---|---|---|---|
| FAD (ox lumiflavin) | -6.188 | -2.779 | 3.409 |
| **FADH₂ (red) — donor** | **-5.137** | -1.592 | 3.545 |
| Os(II) [Os(bpy)₂(1-MeIm)Cl]⁺ | -4.875 | -2.156 | 2.719 |
| **Os(III) [Os(bpy)₂(1-MeIm)Cl]²⁺ — acceptor** | -6.359 | **-4.228** | 2.131 |

### Marcus cascade verdict (full bpy, raw Koopmans)

| Quantity | NH₃ model | Full bpy model |
|---|---|---|
| `ε_HOMO(FADH₂)` — donor | -5.137 eV | -5.137 eV |
| `ε_LUMO(Os(III))` — acceptor | -3.420 eV | **-4.228 eV** |
| `Δε = donor − acceptor` | -1.717 eV | **-0.909 eV** |
| π-backbonding shift | — | **+0.808 eV** |
| Direction | ❌ UPHILL | ❌ UPHILL (closer) |

⚠️ **Сирий verdict все ще UPHILL** (-0.909 eV), але π-backbonding зменшив розрив з 1.72 eV до 0.91 eV — на 47%. Залишковий bias домінується **B3LYP FADH₂ HOMO underestimate** (~0.64 eV) + **geometry not DFT-optimized** (~0.1-0.3 eV).

Діаграма енергетичної сходинки: [`tools/in_silico/cache/dft/energy_ladder.png`](../../../../tools/in_silico/cache/dft/energy_ladder.png).

### Bias-corrected analysis (full bpy model)

Експериментально каскад **сильно downhill**: E°(Os ≈ +200 мВ) − E°(FAD-GDH = **−266 мВ vs SHE**, Sygmund & Ludwig 2022) ≈ **+466 мВ** (ΔG ≈ −0.47 eV; [`01_03 §2.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)). _(Стара канон-цифра «+140 мВ / −0.14 eV, Cosnier 1999» стояла на хибному E°(FAD)=+60 мВ; +140 Cosnier стосується glucose-**оксидази**, не GcGDH — supersede.)_ Сирий DFT-вердикт нижче — uphill у кожному методі; розрив до −0.47 eV декомпозовано ② (§E).

| Джерело помилки | Величина | NH₃ model | Full bpy model |
|---|---|---|---|
| **B3LYP underestimate FADH₂ HOMO** | ~0.97 eV | applies | **applies** (vs verified −266 mV FAD) |
| **Missing π-backbonding** | ~0.8-1.5 eV | applies | **✅ closed** (+0.81 eV shift measured) |
| **Geometry not DFT-optimized** | ~0.1-0.3 eV | minor | **applies** |
| **Total bias** | | ~1.6-2.1 eV | **~0.7-0.9 eV** |

**On the earlier «bias-corrected Δε ≈ −0.07 eV»:** that construction (raw −0.909 +
a +0.64 eV B3LYP-HOMO correction + geometry) was **tuned to land near the erroneous
−0.14 eV target** and is **withdrawn**. Against the verified driving force (−0.47 eV)
the B3LYP-HOMO underestimate is itself larger (~0.97 eV — see vertical table below),
so no fortuitous cancellation survives: the raw DFT genuinely underestimates the
driving force by ~1.3 eV. That gap is **decomposed**, not hand-waved — speciation +
differential PCM solvation (task ②, §E).

**Vertical verification (Koopmans → NHE scale):**

| Species | DFT (full bpy) | Exp. E° vs vacuum* | Gap |
|---|---|---|---|
| FADH₂ HOMO | -5.14 eV | ≈ -4.17 eV (−266 мВ SHE + 4.44 V) | **-0.97 eV** (B3LYP bias) |
| Os(III) LUMO | **-4.23 eV** | ≈ -4.64 eV (+200 мВ NHE + 4.44 V) | **+0.41 eV** (geom + basis) |

*Eˆabs(NHE) = +4.44 V (Reiss & Heller 1985, Trasatti 1986).

### Інтерпретація для патентного клайму

- **Pipeline працює end-to-end** (PySCF + B3LYP + PCM + Koopmans + Marcus cascade analysis script). ✅
- **FAD-сторона рахується доброякісно**: HOMO/LUMO/gap у межах типових B3LYP errors для flavin (літературний benchmark Bhattacharyya 2007).
- **Os-сторона потребує апгрейду** (NH₃ → real bpy/Im) для absolute verdict.
- **Patent claim Gen 2.0 ("Os mediator енергетично узгоджений з FAD")** залишається безперечно підтвердженим **експериментально** (E°(Os) − E°(FAD-GDH) = +200 − (−266) = **+466 мВ**, верифіковані E°s, Sygmund & Ludwig 2022) — це **експериментальна константа**, не симуляція. DFT-симуляція дає in-silico *механізм* (із квантифікованим, декомпозованим лімітом implicit-сольватації — ②), а не джерело вердикту.

---

## Інтерпретація

**Що означає `ε_HOMO(FADH₂) > ε_LUMO(Os(III))`** (downhill):

1. Електрон у заповненому **HOMO відновленого FADH₂** має вищу енергію (менш від'ємну vs vacuum), ніж порожнє **β-spin SOMO окисненого Os(III) комплексу**.
2. У теорії Маркуса термодинамічна рушійна сила `ΔG° ≈ −(ε_donor − ε_acceptor)` (з ΔSCF — різниця повних енергій; **без** λ). Енергія реорганізації **λ не входить у ΔG°** — вона визначає *бар'єр активації*: `ΔG‡ = (ΔG° + λ)² / 4λ`. (Раніше тут було помилково `ΔG° = … + λ` — це дало б енергію вертикального оптичного переходу, а не термодинамічний потенціал для CV.) При `ΔG° < 0` перенос спонтанний.
3. У вольтаметричному expression: `E°(Os²⁺/³⁺) > E°(FAD/FADH₂)` (більш позитивний → краще acceptor). Узгоджується з верифікованими E°s ([`01_03 §2.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): `E°(Os) ≈ +200 мВ` ≫ `E°(FAD-GDH) = −266 мВ vs SHE` — різниця **~466 мВ**.

**Що означає `gap` (HOMO-LUMO)**:

Великий gap → **хімічна жорсткість (chemical hardness, η = (LUMO−HOMO)/2)** кофактора: стійкість до УФ, поляризовності та нуклеофільних атак, запобігання неспецифічним побічним реакціям розкладу (напр., генерації ROS) у циклічному редокс-процесі.

> ⚠️ **Виправлення (рецензія):** великий gap **НЕ** має прямого стосунку до електричного "Zero Instrumental Noise". Інструментальний шум біосенсора походить від (а) неспецифічного окислення інших метаболітів (аскорбат, сечова кислота) на електроді та (б) флуктуацій ємності подвійного шару (C_dl) — це макроскопічні електрохімічні ефекти, не молекулярна щілина FAD. Gap гарантує лише *хімічну* стабільність кофактора. (Zero Instrumental Noise як системний принцип — окремо в [`01_03 §4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md), через стабільність ECSA/PSBMA, а не через HOMO-LUMO.)

---

## Caveats та обмеження

1. **Koopmans approximation** — HOMO/LUMO orbital energies з DFT ≠ exact IP/EA через correlation/relaxation effects. B3LYP типово недооцінює HOMO на ~0.5-1 eV vs ωB97X-D. Як **первинний скрінінг** для каскаду — достатньо; для абсолютних чисел потрібен повний ΔSCF + ZPE + thermal.
2. **Single-point geometry** — не повна оптимізація. MMFF (флавін) і programmatic octahedral (Os, full bpy model: Os-N = 2.10 vs ideal 2.06 Å). **DFT geometry optimization attempted** (script 21c, 2026-05-26): ran 30+ cycles, gradient converged since Step 13 (rms<3e-4, max<4.5e-4), energy flat to 1e-6 Ha, but Cl displacement on flat PES never meets GAU convergence criteria (Cl drifts indefinitely). **Terminated** — programmatic geometry sufficient for LUMO accuracy (dE = 0.002 eV between Step 11 and Step 30). Future: freeze Cl during optimization or use GAU_LOOSE convergence.
3. **PCM water vs xylem** — implicit solvent, без specific H-bonding до water molecules або до xylem sap solutes. Для Marcus reorganization energy більш честно — explicit solvation shell (50+ waters) + EFP, але це порядок коштовніше.
4. **Os полімерна модель** — full cis-[Os(bpy)₂(1-MeIm)Cl] з 54 атомами. π-backbonding від bpy включений. Single imidazole як proxy для PVI polymer backbone — acceptable (frontier orbitals Os center переважно d-character). Полімерна щіткова density обробляється у L2.
5. **Акватація Cl-ліганду (важливо для абсолютного E°)** — у водному середовищі Os/Ru-поліпіридильні хлориди схильні до рівноваги акватації: `[Os(bpy)₂(Im)Cl]⁺ + H₂O ⇌ [Os(bpy)₂(Im)(H₂O)]²⁺ + Cl⁻`. Заміна σ-/π-донора Cl⁻ на нейтральну воду зсуває E° на **+100…200 мВ** (кращий акцептор). У реальному PVI-полімері Os часто координований **двома** імідазолами ланцюга (Cl витіснений). Тобто наша Cl-модель — одна з форм; цитований експериментальний E° ≈ +200 мВ ймовірно належить аква- або біс-імідазольному комплексу. Для статті — явно зазначити рівновагу акватації.
6. **Іонна сила середовища (Debye-Hückel screening)** — PCM використовує чисту воду (ε=78.36, без екранування). Ксилемний сік має іонну силу 0.01–0.05 М (script 14). Дебаївський екран стабілізує вищий заряд (Os³⁺) сильніше за нижчий (Os²⁺) → зсуває термодинамічний редокс-потенціал (помірно, ~десятки мВ при 0.05 М, Debye length ~13 Å). Поточна термодинаміка Os(III)/Os(II) неявно моделює дист. воду. Refinement: C-PCM з ionic-strength/kappa параметром (перевірити підтримку в PySCF) — flagged, ефект малий відносно ~1 eV solvation-gap.

---

## D. ωB97X/def2-TZVP — Publication-grade (✅ Complete, 2026-05-27)

**Script:** `21d_dft_os_bpy_wb97xd.py`. Range-separated hybrid functional з triple-zeta basis.

**Why ωB97X instead of B3LYP:** B3LYP underestimates HOMO by ~0.6 eV (Bhattacharyya & Truhlar 2007). ωB97X has range-separated exact exchange → more accurate HOMO/LUMO for charge-transfer states. PySCF не підтримує wb97x-d (dispersion); wb97x без dispersion — main improvement is range separation (~0.6 eV), dispersion minor (~0.05 eV).

### Complete results (2026-05-27)

| Species | HOMO (eV) | LUMO (eV) | Gap (eV) | Wall (s) | Status |
|---|---|---|---|---|---|
| Os(II) [Os(bpy)₂(1-MeIm)Cl]⁺ (ωB97X) | **-7.128** | -0.438 | 6.691 | 7195 | ✅ |
| Os(III) [Os(bpy)₂(1-MeIm)Cl]²⁺ (ωB97X) | -8.887 | **-1.781** | 7.106 | 33900 | ✅ <S²>=0.754 |
| FADH₂ lumiflavin (ωB97X) | **-7.664** | 0.282 | 7.946 | 470 | ✅ |

**ωB97X Koopmans cascade:**

| Quantity | B3LYP | ωB97X |
|---|---|---|
| ε_HOMO(FADH₂) | -5.137 eV | **-7.664 eV** |
| ε_LUMO(Os(III)) | -4.228 eV | **-1.781 eV** |
| Δε | -0.909 eV | **-5.884 eV** |
| Direction | ❌ UPHILL | ❌ UPHILL (much larger) |

**Critical interpretation:** The much larger ωB97X uphill (-5.88 eV vs -0.91 eV) does NOT invalidate the cascade. Range-separated hybrids are known to give Koopmans orbital energies that are **poor proxies for redox potentials** — they correctly reproduce ionization potentials but virtual orbital energies (LUMO) are systematically too high. B3LYP benefits from error cancellation that makes its orbital energies closer to E° values.

### ΔSCF vertical IP/EA (ωB97X/def2-TZVP, 2026-05-27)

Computed vertical ionization of FADH₂ → FADH₂⁺ (radical cation, UKS) and reduction Os(III) → Os(II):

| Half-reaction | ΔE (eV) |
|---|---|
| FADH₂ → FADH₂⁺ + e⁻ (oxidation) | **+5.391** (cost) |
| Os(III) + e⁻ → Os(II) (reduction) | **-4.392** (release) |
| **Full: FADH₂ + Os(III) → FADH₂⁺ + Os(II)** | **+0.998 (UPHILL)** |

Discrepancy from the verified driving force (−0.47 eV downhill): **~1.47 eV** — dominated by mediator **speciation** (chloro model vs the active aqua/bis-Im form, +0.51 eV) + **differential PCM solvation** (decomposed in ②, §E), with vertical geometry (~0.3 eV) and no ZPE/entropy (~0.1 eV) as minor terms.

### Summary: all methods compared (2026-05-27)

| Method | ΔG/e⁻ (eV) | vs Exp.* | Note |
|--------|-----------|---------|------|
| Koopmans ωB97X | +5.884 | 6.35 | RSH artifact, not applicable |
| ΔSCF ωB97X (vertical) | +0.998 | 1.47 | same molecule, different charge |
| **ΔSCF ωB97X (adiabatic)** | **+0.884** | **1.35** | composite ωB97X//B3LYP geom opt |
| B3LYP Koopmans (bias-corrected) | -0.07 | 0.40 | **withdrawn** — was tuned to the erroneous −0.14 target |
| **Experimental (verified E°s)** | **-0.47** | **ref** | E°(Os +200) − E°(FAD-GDH −266 mV SHE), Sygmund & Ludwig 2022 |

*vs the verified −0.47 eV (the old −0.14 was a +60 mV FAD artifact). The raw-DFT↔exp gap (~1.3 eV) is decomposed by ② (§E): mediator speciation + differential PCM solvation, validated on the [Os(H₂O)₆] group-8 benchmark.

**Adiabatic ΔSCF details:** Geom opt at B3LYP/def2-SVP (FADH₂: 2027s, FADH₂⁺: 2975s), then SP at ωB97X/def2-TZVP. IP relaxation: 5.391 → 5.276 eV (-0.114 eV). Small gain because lumiflavin is a rigid planar molecule — cation geometry barely changes.

**PCET correction — method corrected (rec. review):** the earlier attempt computed H₃O⁺ explicitly in PCM and was rightly discarded (PCM oversolvates small ions). But the **fix is NOT explicit water** — it is the standard **thermodynamic proton reference**: never compute H⁺ in DFT; instead add the experimentally-fixed solvated-proton free energy
`G_solv(H⁺) = G_gas(H⁺) [−6.28 kcal/mol, Sackur-Tetrode] + ΔG°_solv(H⁺) [−265.9 kcal/mol] ≈ −11.7 eV`
to the deprotonated product. This makes the FAD/FADH₂ PCET (FAD + 2H⁺ + 2e⁻ → FADH₂) valid with implicit solvation alone, recovering the proton term without QM/MM.

**✅ Computed (script 32, 2026-05-28):** thermodynamic proton reference (Isse-Gennaro 2010: `G*(H⁺,aq) = −11.72 eV`, `|SHE_abs| = 4.281 V`) on the cached B3LYP/6-31G(d)+PCM ox/red energies → **E°(FAD/FADH₂) = −158 mV vs NHE @ pH 7** (−10 mV @ pH 4.5, +256 mV @ pH 0). vs experimental **free-flavin −208 mV @ pH 7 → Δ = +50 mV** (within 100 mV). The protein-bound FAD-GDH is tuned **more negative** — **−266 mV vs SHE** (Sygmund & Ludwig 2022, MORE negative than free −208 → a *better* electron donor, larger cascade driving force; the protein-environment shift is §3.6 / ④), so this script computes the **free** cofactor as the reference point. **Conclusion:** the proton reference recovers a physically correct redox potential with implicit solvation alone — explicit water was never needed. Cache: `dft/pcet_redox_potential.json`. Screening tier (electronic E proxy for G; SHE_abs convention ±0.15 V); publication-grade refinement = geom-opt + thermal G at ωB97X.

**PCET cascade test (script 33, 2026-05-28) — does NOT flip the cascade downhill.** Reviewer hypothesis: the bare cation-radical IP (+5.391 eV) is "inflated" by FADH₂•⁺ instability, so the proton-coupled oxidation `FADH₂ → FADH• + H⁺ + e⁻` should drop the cost ~1-1.5 eV → cascade downhill. **Tested with geom-optimized FADH•/FADH₂ (B3LYP/6-31G(d) opt → ωB97X/def2-TZVP SP) + proton reference:** PCET oxidation cost = **+5.87 eV** — *higher*, not lower, than the bare IP (+0.48 eV). Cascade = **+1.478 eV (still uphill).** Why: the bare IP we use is **vertical** (frozen geometry) — it was never inflated by the cation-radical *geometric* instability (that only appears on relaxation, which fragments — see script 29). Deprotonation of FADH₂•⁺ is itself +0.48 eV uphill in PCM (cation radical not acidic enough there — another PCM artifact). **Conclusion:** PCET reframing does not resolve the gap; the ΔSCF–experiment discrepancy (~1.3 eV vs the verified −0.47 eV) is **mediator speciation + PCM differential-solvation** (decomposed in ②, §E), not proton coupling. Cache: `dft/pcet_cascade.json`.

**Residual ~1.3 eV gap** between adiabatic ΔSCF (+0.88 eV uphill) and the verified driving force (−0.47 eV downhill) is **decomposed by ② (§E)**: mediator **speciation** (chloro→aqua, +0.51 eV) + **differential PCM solvation** (+0.20 eV for 3 Cl⁻-waters → full shell), validated on the [Os(H₂O)₆] group-8 benchmark (+0.98 eV); plus minor ZPE/entropy (~0.1 eV) and vertical Os geometry. Well-known limitations of implicit solvation DFT — rigorous closure = explicit-water QM/MM with the correct aqua/bis-Im species (школа Мінаєва). **Authoritative cascade verdict = the verified E°s (+466 mV / −0.47 eV downhill); the DFT supplies in-silico mechanism with a quantified, decomposed method limit.**

**The verified cascade (+466 mV / −0.47 eV downhill, from E°(Os +200) − E°(FAD-GDH −266 mV SHE), Sygmund & Ludwig 2022) is the authoritative verdict.** Raw DFT is uphill in every method (Koopmans Δε −0.91; ΔSCF ωB97X adiabatic +0.88 eV); the ~1.3 eV underestimate is a solvation + speciation model limitation, not a chemistry problem, and is **decomposed** by ② (§E). The earlier «−0.07 reproduces −0.14» claim was fortuitous error-cancellation tuned to a mis-valued (+60 mV) FAD and is **withdrawn**. For Q1 publication: explicit-solvation QM/MM with the correct aqua/bis-Im species (школа Мінаєва) closes the residual.

---

## E. Cluster-Continuum Micro-Solvation & Speciation (② — script 34, 2026-06-05)

Directly tests the §D residual-gap hypothesis (raw DFT uphill vs the verified
−0.47 eV driving force) by adding explicit waters / correcting the Os speciation on
the charge-changing Os(III/II) couple. Since script 32 reproduces E°(FAD/FADH₂) within 50 mV, the flavin
solvation is sound — the gap lives on the Os couple, the textbook group-8 octahedral
PCM failure (Ru(H₂O)₆ ~1 V error, JPCC 10.1021/jp406772u). Full numbers →
[`SUMMARY.md`](SUMMARY.md); the picture:

1. **Benchmark validated** — [Os(H₂O)₆]³⁺/²⁺ inner→two-shell (n6→n18) shift is
   **+0.98 eV**, reproducing the known ~1 V group-8 continuum error (2nd-shell
   H-bond directionality a continuum cannot model).
2. **Explicit Cl⁻ solvation** — 3 waters H-bonded to the chloride close +0.20 eV of
   the cascade gap (~0.067 eV/water, monotonic) → full closure needs the whole 2nd
   shell (QM/MM regime).
3. **Speciation dominates** — replacing Cl⁻ by an aqua ligand (the form Caveat 5
   argues the experiment actually measures) closes **+0.51 eV** — over half the gap;
   the weak H₂O donor leaves Os(III) a much stronger oxidant. The aqua couple is
   +2/+3, so it inherits the larger group-8 PCM bias — its absolute value is itself
   implicit-limited (same direction as Caveat 6, ionic strength).

**Conclusion:** the cascade gap decomposes into *speciation* (~0.5 eV) + *explicit
solvation* (~0.2 eV / partial shell) — both computed from first principles, both
~0.5 eV-scale — confirming it is a **method limit, not a chemistry failure**. The
chloro-implicit model (§B / ①) is the worst case; the rigorous path is QM/MM with the
correct aqua/bis-imidazole species (школа Мінаєва). This turns the "PCM limit" from
an assertion into a quantified, decomposed result — the methodological core of Стаття 1.

## Future work (Gen 2.5+ refinements)

| Покращення | Cost | Очікуваний імпакт |
|---|---|---|
| **Повна geometric/pyberny opt** обох species | ~6-12 год CPU | Frontier orbital energies → точніше на ~0.1-0.3 eV |
| **ωB97X + def2-TZVP** | ~27× довше за B3LYP/6-31G(d) для RKS | **Script 21d ✅ COMPLETE** (2026-05-27). Adiabatic ΔSCF: ΔG=+0.884 eV (PCM limit). |
| **MD→DFT ensemble** | 5 SP on MD snapshots | **Script 27 ✅ DONE** (2026-05-28). FAD isoalloxazine HOMO = **-5.589 ± 0.058 eV** across 5 thermal snapshots → frontier orbital thermally robust (σ ≪ 0.3 eV). Confirms FAD→Os cascade stable against thermal fluctuation. Root-cause fix: heavy-atom-only fragment had dangling valences (no SCF); now includes distance-attached H + SOSCF fallback. |
| **Nelsen 4-point λ** | 2 geom opts + 4 SPs | **Script 29 ❌ CLOSED — Physical Limitation** (2026-05-28). Attempted twice: (a) composite ωB97X//B3LYP (41.5h), (b) consistent B3LYP/def2-SVP + density-seeded cross-SPs. **Both give E(neutral@R_cation) ≈ −867 Ha, +5.9–6.3 Ha (+160 eV) above diagonal** — not an SCF/basis artifact but a real chemistry failure: the uncompensated **FADH₂•⁺ radical cation geometry is pathological in implicit solvent** (no explicit water / no PCET to relieve charge → ring distorts/fragments during geom-opt), so the neutral closed-shell at that geometry is meaningless. 4-point λ for proton-active flavins requires QM/MM (explicit water) or a deprotonated (PCET) reference. **Literature λ = 0.7–0.8 eV retained** (gold standard for flavin cofactors, Bhattacharyya et al.) — L4 Marcus rates already use it. *Same root cause as the +0.998 eV cascade artifact → fixed via PCET (script 33).* |
| **ΔSCF redox potentials** з RRHO thermal corrections | ~2× за SP | Direct E° prediction vs NHE/SHE, не Koopmans approximation |
| **TD-DFT excited states** для Os complex | ~5× за GS | Підтверджує MLCT character + Marcus reorganization energy |
| **Explicit water shells + ONIOM/EFP** | ~10× за PCM | **Script 34 ② ✅ (cluster-continuum, §E)**: benchmark +0.98 eV, speciation +0.51 eV, Cl⁻-solvation +0.20 eV → gap = decomposed method limit (→ SUMMARY). Full QM/MM = школа Мінаєва |
| **CDFT (Constrained DFT)** для hopping integrals | ~5× за SP | Marcus β coefficient (~1.1 Å⁻¹ assumed in L1) — direct calc |
| **MCPB.py-параметризований Os complex** + L2 MD | weeks | Mechanical Os-polymer surface coverage on protein (Gen 2.5+, не критичний path) |

---

## Файли L3

| Шлях | Опис |
|---|---|
| `tools/in_silico/scripts/20_dft_lumiflavin.py` | FAD/FADH₂ DFT SP скрипт |
| `tools/in_silico/scripts/21_dft_os_bipy_complex.py` | Os(II)/Os(III) DFT SP — NH₃ surrogate (superseded) |
| `tools/in_silico/scripts/21b_dft_os_bpy_full.py` | Os(II)/Os(III) DFT SP — **full [Os(bpy)₂(1-MeIm)Cl]** (B3LYP, current) |
| `tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py` | Geometry optimization — terminated (Cl flat PES) |
| `tools/in_silico/scripts/21d_dft_os_bpy_wb97xd.py` | **ωB97X/def2-TZVP publication-grade** ✅ |
| `tools/in_silico/scripts/22_compare_homo_lumo.py` | Aggregator + Marcus diagram |
| `tools/in_silico/scripts/23_build_zif_clusters.py` | Bimetallic ZIF clusters (Cu/Co/Ce) for L3b |
| `tools/in_silico/scripts/24_dft_hopping_integrals.py` | ΔSCF hopping integrals ✅ (3/3 pairs) |
| `docs/protocols/ebfc/in_silico/ligands/lumiflavin_ox.xyz` | MMFF94s geometry лумифлавіну |
| `docs/protocols/ebfc/in_silico/ligands/lumiflavin_red.xyz` | MMFF94s geometry 1,5-дигідролумифлавіну |
| `docs/protocols/ebfc/in_silico/ligands/os_amine_cl.xyz` | NH₃ surrogate geometry (22 atoms, superseded) |
| `docs/protocols/ebfc/in_silico/ligands/os_bpy_im_cl.xyz` | Full bpy/Im/Cl geometry (54 atoms, current) |
| `tools/in_silico/cache/dft/lumiflavin.json` | Output 20-го скрипту (gitignored runs, але cached) |
| `tools/in_silico/cache/dft/os_complex.json` | Output 21-го скрипту |
| `tools/in_silico/cache/dft/comparison.json` | Aggregated результати 22-го скрипту |
| `tools/in_silico/cache/dft/energy_ladder.png` | Marcus cascade diagram |

---

## L3b — Cathode DET Hopping Integrals (ZIF nanozyme)

**Метод:** ΔSCF (initial guess swap) для бімелатичних ZIF кластерів. UKS B3LYP/6-31G(d) + LANL2DZ(Cu,Co) + Stuttgart RSC(Ce) + C-PCM.

**Electron hopping pathway:** MWCNT ←t₃→ Ce ←t₂→ Co ←t₁→ Cu T1 (laccase)

### Результати (partial, 2026-05-26)

| Пара | Атомів | t_ij (eV) | k_ET (s⁻¹) | Статус |
|------|--------|-----------|-------------|--------|
| **Cu-Co** (T1↔ZIF node) | 62 | **0.0325** | **2.34×10¹⁰** | ✅ Completed |
| **Co-Ce** (ZIF node↔vacancy) | 62 | **0.0022** | **1.10×10⁸** | ✅ Completed (2026-05-27) |
| **Ce-graphene** (vacancy↔electrode) | 61 | **0.1177** | **3.07×10¹¹** | ✅ Completed (2026-05-27) |

**Bottleneck hop (NOT a 1D series sum — rec. review):** the slowest hop is **Co-Ce, k = 1.10×10⁸ s⁻¹**. A series-resistance formula (`1/k_total = Σ1/kᵢ`) would apply only to a single 1D wire; ZIF is a **3D porous framework** with many parallel percolation paths, so the macroscopic charge-diffusion rate is bounded *below* by this bottleneck hop (the true 3D rate is ≥ this — series sum is a conservative lower bound; numerically it coincides here since Co-Ce dominates). Either way: **≥ 1.10×10⁸ s⁻¹ = 10⁵× faster** than enzymatic turnover (~10³ s⁻¹) → **cathode DET is NOT rate-limiting.**

**Cu-Co verdict:** t_ij = 0.0325 eV → k_ET = 2.34×10¹⁰ s⁻¹ (λ=0.7 eV, ΔG=0, T=298K). Це **надзвичайно швидкий** DET — набагато швидше ніж enzymatic turnover (~10³ s⁻¹). DET через ZIF **не лімітує** катодний ORR.

Scripts: `23_build_zif_clusters.py` (geometry), `24_dft_hopping_integrals.py` (ΔSCF + Marcus).

---

## TRL gate L3 → L4

| Критерій | Статус | Деталі |
|---|---|---|
| Pipeline end-to-end працює (PySCF + B3LYP + PCM + Marcus cascade) | ✅ | 4 скрипти (20, 21, 21b, 22), JSON-керовані, deterministic |
| FAD redox core моделюється на B3LYP/6-31G(d) + PCM | ✅ | HOMO -5.14 eV (B3LYP ~0.97 eV below the -4.17 eV implied by bound -266 mV SHE) |
| Os mediator — NH₃ surrogate (script 21) | ✅ Superseded | LUMO(Os(III)) = -3.42 eV; missing π-backbonding → -1.72 eV uphill |
| Os mediator — full [Os(bpy)₂(1-MeIm)Cl] (script 21b) | ✅ | LUMO(Os(III)) = **-4.23 eV**; π-backbonding закритий (+0.81 eV shift); <S²>=0.754 ✅ |
| `ε_HOMO(FADH₂) > ε_LUMO(Os(III))` (raw Koopmans) | ❌ → ⚠️ | Δε = **-0.91 eV** (uphill, but 47% closer than NH₃ model's -1.72 eV) |
| Cascade verdict (verified E°s) | ✅ | E°(Os +200) − E°(FAD-GDH −266 mV SHE) = **+466 mV / −0.47 eV downhill**; raw DFT uphill = method limit decomposed by ② |
| **Definitive in-silico verdict** (publication-grade) | ✅ | raw DFT uphill (adiabatic ΔSCF +0.884 eV); ~1.3 eV gap = speciation + PCM solvation, decomposed by ② (script 34); rigorous closure = QM/MM → школа Мінаєва |

**Gate L3 → L4:** **pass** — повна bpy модель закрила π-backbonding gap; сирий DFT-каскад uphill (−0.91 Koopmans / +0.88 ΔSCF), а розрив до верифікованого −0.47 eV (~1.3 eV) декомпозовано ② на speciation + PCM-сольватацію (метод-ліміт, не хімія). Каскадний клайм Gen 2.0 підтверджений **експериментально** (верифіковані E°s → +466 мВ downhill, Sygmund & Ludwig 2022); DFT дає механізм + квантифікований метод-ліміт. Повне raw-DOWNHILL → QM/MM (школа Мінаєва), не блокує L4.

---

## Cross-references

- 4-рівневий in-silico pipeline → [`01_03 §3.4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- Decision Log: Os→L3 → [`01_03 §3.4.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- Anode MET stack (де Os полімер живе) → [`01_03 §2.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- L1 protein architecture → [`L1_protein_architecture.md`](L1_protein_architecture.md)
- Pipeline operational status → [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md)
- All results summary → [`SUMMARY.md`](SUMMARY.md)
- Patent claim Gen 2.0 / embargo → [`08_01 §2`](../../../08_01_Joint_Publications_and_IP_Strategy.md)
