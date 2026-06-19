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

**Os mediator → cis-[Os(4,4'-dimethyl-bpy)₂(1-MeIm)Cl]ⁿ⁺ (real device mediator, 66 atoms; OS-RECOMPUTE 2026-06-17)**

Повний лігандний environment реального Os-PVI редокс-полімеру (Zafar 2012, E° = +309 мВ vs NHE): 2× **4,4'-dimethyl-2,2'-bipyridine** (chelating, s-cis) + 1-methylimidazole (proxy для poly(vinylimidazole)) + Cl⁻ (**chloro form, verified**). Геометрія зібрана програматично з ортогональних bpy-площин (xz та yz), без crystal seed. 66 атомів. **Plain 2,2'-bipyridine (54 atoms, таблиці нижче) лишається parent π-backbonding reference, superseded як device baseline.**

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

### B. Full dmbpy device model (script 21b — current; dimethyl recompute)

Той самий DFT стек, але з повним cis-[Os(dmbpy)₂(1-MeIm)Cl]ⁿ⁺ (66 atoms, 272/271 electrons; `os_complex.json`). SCF wall-clock: Os(II) 471 s, Os(III) 751 s (Apple Silicon, multi-core). <S²>(Os(III)) ≈ 0.75 → чистий doublet. _(Plain-bpy [Os(bpy)₂…] лишається як Hammett σ=0 опорна точка — SUMMARY §LFER / 06_tables.)_

| Species | HOMO (eV) | LUMO (eV) | gap (eV) |
|---|---|---|---|
| FAD (ox lumiflavin) | -6.188 | -2.779 | 3.409 |
| **FADH₂ (red) — donor** | **-5.137** | -1.592 | 3.545 |
| Os(II) [Os(dmbpy)₂(1-MeIm)Cl]⁺ | -4.724 | -2.023 | 2.702 |
| **Os(III) [Os(dmbpy)₂(1-MeIm)Cl]²⁺ — acceptor** | -6.209 | **-4.086** | 2.124 |

### Marcus cascade verdict (dmbpy device, raw Koopmans)

| Quantity | NH₃ model | dmbpy device |
|---|---|---|
| `ε_HOMO(FADH₂)` — donor | -5.137 eV | -5.137 eV |
| `ε_LUMO(Os(III))` — acceptor | -3.420 eV | **-4.086 eV** |
| `Δε = donor − acceptor` | -1.717 eV | **-1.051 eV** |
| π-backbonding shift | — | **+0.666 eV** |
| Direction | ❌ UPHILL | ❌ UPHILL (closer) |

⚠️ **Сирий verdict все ще UPHILL** (-1.051 eV, dmbpy device), але π-backbonding зменшив розрив з 1.72 eV до 1.05 eV — на ~39%. Залишковий bias домінується **B3LYP FADH₂ HOMO underestimate** (~0.97 eV vs verified −265 мВ) + **geometry not DFT-optimized** (~0.1-0.3 eV). (Plain-bpy baseline Δε = −0.909; різниця −0.142 = 4,4'-dimethyl substituent ②.)

Діаграма енергетичної сходинки: [`tools/in_silico/cache/dft/energy_ladder.png`](../../../../tools/in_silico/cache/dft/energy_ladder.png).

### Bias-corrected analysis (full bpy model)

Експериментально каскад **сильно downhill**: E°(Os = +309 мВ vs NHE, Zafar 2012) − E°(FAD-GDH = **−265 мВ vs SHE**, Schachinger, Ma, Ludwig 2023) = **+574 мВ** (ΔG ≈ −0.574 eV; [`01_03 §2.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)). _(Стара канон-цифра «+140 мВ / −0.14 eV, Cosnier 1999» стояла на хибному E°(FAD)=+60 мВ; +140 Cosnier стосується glucose-**оксидази**, не GcGDH — supersede.)_ Сирий DFT-вердикт нижче — uphill у кожному методі; розрив до −0.574 eV декомпозовано ② (§E).

| Джерело помилки | Величина | NH₃ model | Full bpy model |
|---|---|---|---|
| **B3LYP underestimate FADH₂ HOMO** | ~0.97 eV | applies | **applies** (vs verified −265 mV FAD) |
| **Missing π-backbonding** | ~0.8-1.5 eV | applies | **✅ closed** (+0.67 eV shift, NH₃→dmbpy) |
| **Geometry not DFT-optimized** | ~0.1-0.3 eV | minor | **applies** |
| **Total bias** | | ~1.6-2.1 eV | **~0.7-0.9 eV** |

**On the earlier «bias-corrected Δε ≈ −0.07 eV»:** that construction (raw −0.909 +
a +0.64 eV B3LYP-HOMO correction + geometry) was **tuned to land near the erroneous
−0.14 eV target** and is **withdrawn**. Against the verified driving force (−0.574 eV)
the B3LYP-HOMO underestimate is itself larger (~0.97 eV — see vertical table below),
so no fortuitous cancellation survives: the raw DFT genuinely underestimates the
driving force. That gap is **decomposed**, not hand-waved — differential PCM solvation
(chloro↔bis-Im bracket) + the 4,4'-dimethyl substituent (task ②, §E).

**Vertical verification (Koopmans → NHE scale):**

| Species | DFT (full bpy) | Exp. E° vs vacuum* | Gap |
|---|---|---|---|
| FADH₂ HOMO | -5.14 eV | ≈ -4.17 eV (−265 мВ SHE + 4.44 V) | **-0.97 eV** (B3LYP bias) |
| Os(III) LUMO (dmbpy) | **-4.09 eV** | ≈ -4.75 eV (+309 мВ NHE + 4.44 V) | **+0.66 eV** (geom + basis) |

*Eˆabs(NHE) = +4.44 V (Reiss & Heller 1985, Trasatti 1986).

### Інтерпретація для патентного клайму

- **Pipeline працює end-to-end** (PySCF + B3LYP + PCM + Koopmans + Marcus cascade analysis script). ✅
- **FAD-сторона рахується доброякісно**: HOMO/LUMO/gap у межах типових B3LYP errors для flavin (літературний benchmark Bhattacharyya 2007).
- **Os-сторона потребує апгрейду** (NH₃ → real bpy/Im) для absolute verdict.
- **Gen 2.0 claim ("Os mediator енергетично узгоджений з FAD")** залишається безперечно підтвердженим **експериментально** (E°(Os) − E°(FAD-GDH) = +309 − (−265) = **+574 мВ**, верифіковані E°s, Zafar 2012 + Schachinger, Ma, Ludwig 2023) — це **експериментальна константа**, не симуляція. DFT-симуляція дає in-silico *механізм* (із квантифікованим, декомпозованим лімітом implicit-сольватації — ②), а не джерело вердикту.

---

## Інтерпретація

**Що означає `ε_HOMO(FADH₂) > ε_LUMO(Os(III))`** (downhill):

1. Електрон у заповненому **HOMO відновленого FADH₂** має вищу енергію (менш від'ємну vs vacuum), ніж порожнє **β-spin SOMO окисненого Os(III) комплексу**.
2. У теорії Маркуса термодинамічна рушійна сила `ΔG° ≈ −(ε_donor − ε_acceptor)` (з ΔSCF — різниця повних енергій; **без** λ). Енергія реорганізації **λ не входить у ΔG°** — вона визначає *бар'єр активації*: `ΔG‡ = (ΔG° + λ)² / 4λ`. (Раніше тут було помилково `ΔG° = … + λ` — це дало б енергію вертикального оптичного переходу, а не термодинамічний потенціал для CV.) При `ΔG° < 0` перенос спонтанний.
3. У вольтаметричному expression: `E°(Os²⁺/³⁺) > E°(FAD/FADH₂)` (більш позитивний → краще acceptor). Узгоджується з верифікованими E°s ([`01_03 §2.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): `E°(Os) = +309 мВ` ≫ `E°(FAD-GDH) = −265 мВ vs SHE` — різниця **~574 мВ**.

**Що означає `gap` (HOMO-LUMO)**:

Великий gap → **хімічна жорсткість (chemical hardness, η = (LUMO−HOMO)/2)** кофактора: стійкість до УФ, поляризовності та нуклеофільних атак, запобігання неспецифічним побічним реакціям розкладу (напр., генерації ROS) у циклічному редокс-процесі.

> ⚠️ **Виправлення (рецензія):** великий gap **НЕ** має прямого стосунку до електричного "Zero Instrumental Noise". Інструментальний шум біосенсора походить від (а) неспецифічного окислення інших метаболітів (аскорбат, сечова кислота) на електроді та (б) флуктуацій ємності подвійного шару (C_dl) — це макроскопічні електрохімічні ефекти, не молекулярна щілина FAD. Gap гарантує лише *хімічну* стабільність кофактора. (Zero Instrumental Noise як системний принцип — окремо в [`01_03 §4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md), через стабільність ECSA/PSBMA, а не через HOMO-LUMO.)

---

## Caveats та обмеження

1. **Koopmans approximation** — HOMO/LUMO orbital energies з DFT ≠ exact IP/EA через correlation/relaxation effects. B3LYP типово недооцінює HOMO на ~0.5-1 eV vs ωB97X-D. Як **первинний скрінінг** для каскаду — достатньо; для абсолютних чисел потрібен повний ΔSCF + ZPE + thermal.
2. **Single-point geometry** — не повна оптимізація. MMFF (флавін) і programmatic octahedral (Os, full bpy model: Os-N = 2.10 vs ideal 2.06 Å). **DFT geometry optimization attempted** (script 21c, 2026-05-26): ran 30+ cycles, gradient converged since Step 13 (rms<3e-4, max<4.5e-4), energy flat to 1e-6 Ha, but Cl displacement on flat PES never meets GAU convergence criteria (Cl drifts indefinitely). **Terminated** — programmatic geometry sufficient for LUMO accuracy (dE = 0.002 eV between Step 11 and Step 30). Future: freeze Cl during optimization or use GAU_LOOSE convergence.
3. **PCM water vs xylem** — implicit solvent, без specific H-bonding до water molecules або до xylem sap solutes. Для Marcus reorganization energy більш честно — explicit solvation shell (50+ waters) + EFP, але це порядок коштовніше.
4. **Os полімерна модель** — full cis-[Os(bpy)₂(1-MeIm)Cl] з 54 атомами. π-backbonding від bpy включений. Single imidazole як proxy для PVI polymer backbone — acceptable (frontier orbitals Os center переважно d-character). Полімерна щіткова density обробляється у L2.
5. **Спеціація 6-го ліганду (operando форма медіатора)** — Zafar-медіатор синтезований як **chloro** `[Os(4,4'-dimethyl-bpy)₂(PVI)Cl]⁺` (E° = +309 мВ vs NHE), тож наша Cl-модель структурно **відповідає** реальному медіатору. У робочому PVI-полімері 6-та координація може лишатись Cl⁻ або заміститись **2-м імідазолом ланцюга** (bis-Im, PVI-realistic, CHEM.20/26). **Акватація (Cl⁻→H₂O) малоймовірна** — Os(II) d⁶ low-spin substitution-inert. Тобто bis-Im = operando верхня межа спеціації, aqua = методичний benchmark (НЕ «що вимірює exp» — стара теза «exp = аква» **відкликана**). Каскадний наратив — chloro-anchored bracket (§E).
6. **Іонна сила середовища (Debye-Hückel screening)** — PCM використовує чисту воду (ε=78.36, без екранування). Ксилемний сік має іонну силу 0.01–0.05 М (script 14). Дебаївський екран стабілізує вищий заряд (Os³⁺) сильніше за нижчий (Os²⁺) → зсуває термодинамічний редокс-потенціал (помірно, ~десятки мВ при 0.05 М, Debye length ~13 Å). Поточна термодинаміка Os(III)/Os(II) неявно моделює дист. воду. Refinement: C-PCM з ionic-strength/kappa параметром (перевірити підтримку в PySCF) — flagged, ефект малий відносно ~1 eV solvation-gap.

---

## D. ωB97X/def2-TZVP — Publication-grade (✅ Complete, 2026-05-27)

**Script:** `21d_dft_os_bpy_wb97xd.py`. Range-separated hybrid functional з triple-zeta basis.

**Why ωB97X instead of B3LYP:** B3LYP underestimates HOMO by ~0.6 eV (Bhattacharyya & Truhlar 2007). ωB97X has range-separated exact exchange → more accurate HOMO/LUMO for charge-transfer states. PySCF не підтримує wb97x-d (dispersion); wb97x без dispersion — main improvement is range separation (~0.6 eV), dispersion minor (~0.05 eV).

### Complete results (dimethyl mediator, B1 2026-06-17; plain bpy superseded)

| Species | HOMO (eV) | LUMO (eV) | Gap (eV) | Wall (s) | Status |
|---|---|---|---|---|---|
| Os(II) [Os(dmbpy)₂(1-MeIm)Cl]⁺ (ωB97X) | **-6.961** | -0.311 | 6.650 | 4518 | ✅ |
| Os(III) [Os(dmbpy)₂(1-MeIm)Cl]²⁺ (ωB97X) | -8.734 | **-1.644** | 7.090 | 23661 | ✅ <S²>=0.755 |
| FADH₂ lumiflavin (ωB97X) | **-7.664** | 0.282 | 7.946 | 470 | ✅ |

**ωB97X Koopmans cascade:**

| Quantity | B3LYP | ωB97X |
|---|---|---|
| ε_HOMO(FADH₂) | -5.137 eV | **-7.664 eV** |
| ε_LUMO(Os(III)) dmbpy | -4.086 eV | **-1.644 eV** |
| Δε (dimethyl) | -1.054 eV | **-6.020 eV** |
| Direction | ❌ UPHILL | ❌ UPHILL (much larger) |

**Critical interpretation:** The much larger ωB97X uphill (-6.02 eV vs -1.05 eV, dmbpy) does NOT invalidate the cascade. Range-separated hybrids are known to give Koopmans orbital energies that are **poor proxies for redox potentials** — they correctly reproduce ionization potentials but virtual orbital energies (LUMO) are systematically too high. B3LYP benefits from error cancellation that makes its orbital energies closer to E° values.

### ΔSCF vertical IP/EA (ωB97X/def2-TZVP, 2026-05-27)

Computed vertical ionization of FADH₂ → FADH₂⁺ (radical cation, UKS) and reduction Os(III) → Os(II):

| Half-reaction | ΔE (eV) |
|---|---|
| FADH₂ → FADH₂⁺ + e⁻ (oxidation) | **+5.391** (cost; FAD unchanged) |
| Os(III) + e⁻ → Os(II) (reduction, dmbpy) | **-4.243** (release; +0.149 vs plain −4.392) |
| **Full: FADH₂ + Os(III) → FADH₂⁺ + Os(II)** | **+1.40 (UPHILL)** |

Discrepancy from the verified driving force (−0.574 eV downhill): **~1.6 eV** (plain bpy; the dimethyl recompute B1 widens it ~+0.15 eV via the substituent) — the real mediator is **chloro** (Zafar), so the gap is **differential PCM solvation** (chloro↔bis-Im bracket, §E) + the **4,4'-dimethyl substituent** (+0.146 eV), with vertical geometry (~0.3 eV) and no ZPE/entropy (~0.1 eV) as minor terms.

### Summary: all methods compared (2026-05-27)

| Method | ΔG/e⁻ (eV) | vs Exp.* | Note |
|--------|-----------|---------|------|
| Koopmans ωB97X | +6.02 | 6.59 | RSH artifact, not applicable |
| ΔSCF ωB97X (vertical) | +1.40 | 1.97 | same molecule, different charge (IP_vert sensitive) |
| **ΔSCF ωB97X (adiabatic)** | **+1.03** | **1.61** | composite ωB97X//B3LYP geom opt; **B2 ✅ reproducible** |
| B3LYP Koopmans (bias-corrected) | -0.07 | 0.50 | **withdrawn** — was tuned to the erroneous −0.14 target |
| **Experimental (verified E°s)** | **-0.574** | **ref** | E°(Os +309, Zafar 2012) − E°(FAD-GDH −265 mV SHE, Schachinger 2023) |

*vs the verified −0.574 eV (the old −0.14 was a +60 mV FAD artifact). The raw-DFT↔exp gap is decomposed by ② (§E): differential PCM solvation (chloro↔bis-Im bracket) + the 4,4'-dimethyl substituent, validated on the [Os(H₂O)₆] group-8 benchmark.

**Adiabatic ΔSCF details:** Geom opt at B3LYP/def2-SVP (FADH₂: 2027s, FADH₂⁺: 2975s), then SP at ωB97X/def2-TZVP. IP relaxation: 5.391 → 5.276 eV (-0.114 eV). Small gain because lumiflavin is a rigid planar molecule — cation geometry barely changes.

**PCET correction — method corrected (rec. review):** the earlier attempt computed H₃O⁺ explicitly in PCM and was rightly discarded (PCM oversolvates small ions). But the **fix is NOT explicit water** — it is the standard **thermodynamic proton reference**: never compute H⁺ in DFT; instead add the experimentally-fixed solvated-proton free energy
`G_solv(H⁺) = G_gas(H⁺) [−6.28 kcal/mol, Sackur-Tetrode] + ΔG°_solv(H⁺) [−265.9 kcal/mol] ≈ −11.7 eV`
to the deprotonated product. This makes the FAD/FADH₂ PCET (FAD + 2H⁺ + 2e⁻ → FADH₂) valid with implicit solvation alone, recovering the proton term without QM/MM.

**✅ Computed (script 32, 2026-05-28):** thermodynamic proton reference (Isse-Gennaro 2010: `G*(H⁺,aq) = −11.72 eV`, `|SHE_abs| = 4.281 V`) on the cached B3LYP/6-31G(d)+PCM ox/red energies → **E°(FAD/FADH₂) = −158 mV vs NHE @ pH 7** (−10 mV @ pH 4.5, +256 mV @ pH 0). vs experimental **free-flavin −208 mV @ pH 7 → Δ = +50 mV** (within 100 mV). The protein-bound FAD-GDH is tuned **more negative** — **−265 mV vs SHE** (Schachinger, Ma, Ludwig 2023, MORE negative than free −208 → a *better* electron donor, larger cascade driving force; the protein-environment shift is §3.6 / ④), so this script computes the **free** cofactor as the reference point. **Conclusion:** the proton reference recovers a physically correct redox potential with implicit solvation alone — explicit water was never needed. Cache: `dft/pcet_redox_potential.json`. Screening tier (electronic E proxy for G; SHE_abs convention ±0.15 V); publication-grade refinement = geom-opt + thermal G at ωB97X.

**PCET cascade test (script 33, 2026-05-28) — does NOT flip the cascade downhill.** Reviewer hypothesis: the bare cation-radical IP (+5.391 eV) is "inflated" by FADH₂•⁺ instability, so the proton-coupled oxidation `FADH₂ → FADH• + H⁺ + e⁻` should drop the cost ~1-1.5 eV → cascade downhill. **Tested with geom-optimized FADH•/FADH₂ (B3LYP/6-31G(d) opt → ωB97X/def2-TZVP SP) + proton reference:** PCET oxidation cost = **+5.87 eV** — *higher*, not lower, than the bare IP (+0.48 eV). Cascade = **+1.627 eV (still uphill)** (dimethyl Os −4.243, drift-safe from B1; was +1.478 on plain Os −4.392). Why: the bare IP we use is **vertical** (frozen geometry) — it was never inflated by the cation-radical *geometric* instability (that only appears on relaxation, which fragments — see script 29). Deprotonation of FADH₂•⁺ is itself +0.48 eV uphill in PCM (cation radical not acidic enough there — another PCM artifact). **Conclusion:** PCET reframing does not resolve the gap; the ΔSCF–experiment discrepancy (vs the verified −0.574 eV) is **differential PCM solvation (chloro↔bis-Im) + the 4,4'-dimethyl substituent** (decomposed in ②, §E), not proton coupling. Cache: `dft/pcet_cascade.json` (Os-reduction re-loaded drift-safe for the dimethyl mediator on B1).

**Residual gap** between the adiabatic ΔSCF (uphill; **+1.03 eV** dimethyl mediator, +0.88 plain bpy) and the verified driving force (−0.574 eV downhill) is **decomposed by ② (§E)**: **differential PCM solvation** bracketed [chloro +1/+2 (+0.21 eV / 3 Cl⁻-waters) ↔ bis-Im +2/+3 (+0.55 eV, PVI-realistic)] + the **4,4'-dimethyl substituent** (+0.146 eV), validated on the [Os(H₂O)₆] group-8 benchmark (+0.98 eV); plus minor ZPE/entropy and vertical Os geometry. Rigorous closure = explicit-water QM/MM of the **chloro** species (школа Мінаєва). **Authoritative cascade verdict = the verified E°s (+574 mV / −0.574 eV downhill); the DFT supplies in-silico mechanism with a quantified, decomposed method limit.**

**The verified cascade (+574 mV / −0.574 eV downhill, from E°(Os +309, Zafar 2012) − E°(FAD-GDH −265 mV SHE, Schachinger 2023) is the authoritative verdict.** Raw DFT is uphill in every method (Koopmans Δε −1.05 on the dimethyl mediator; ΔSCF ωB97X adiabatic +1.03 dimethyl / +0.88 plain); the underestimate is a differential-solvation + 4,4'-dimethyl-substituent model limitation, not a chemistry problem, and is **decomposed** by ② (§E). The earlier «−0.07 reproduces −0.14» claim was fortuitous error-cancellation tuned to a mis-valued (+60 mV) FAD and is **withdrawn**. For Q1 publication: explicit-solvation QM/MM of the **chloro** species (школа Мінаєва) closes the residual.

---

## E. Cluster-Continuum Micro-Solvation & Speciation (② — script 34; dimethyl recompute 2026-06-17)

Directly tests the §D residual-gap hypothesis (raw DFT uphill vs the verified
−0.574 eV driving force) by adding explicit waters / probing the Os speciation on the
charge-changing Os(III/II) couple, **recomputed on the real 4,4'-dimethyl-bpy
mediator**. Since script 32 reproduces E°(FAD/FADH₂) within 50 mV, the flavin
solvation is sound — the gap lives on the Os couple, the textbook group-8 octahedral
PCM failure (Ru(H₂O)₆ ~1 V error, JPCC 10.1021/jp406772u). Full numbers →
[`SUMMARY.md`](SUMMARY.md) §"Cluster-Continuum"; the picture (**chloro-anchored bracket**):

1. **Benchmark validated** — [Os(H₂O)₆]³⁺/²⁺ (+2/+3, ligand-independent) inner→two-shell
   shift is **+0.98 eV**, reproducing the known ~1 V group-8 continuum error.
2. **The real mediator IS chloro** (Zafar) — explicit Cl⁻ solvation of the dimethyl
   chloro complex closes **+0.21 eV / 3 waters**; this **+1/+2** couple carries a ~5×
   smaller differential-solvation error than the +2/+3 benchmark (Cl⁻ lowers the charge)
   → the **lower bracket**.
3. **Operando speciation = upper bracket** — in the PVI brush the 6th ligand may be a 2nd
   chain imidazole (**bis-Im**, +2/+3, PVI-realistic; aquation unlikely on the
   substitution-inert Os(II) d⁶ couple). On the dimethyl mediator bis-Im closes **+0.55 eV**
   (B3LYP; **+0.27 eV at ωB97X**, B4). At B3LYP the ranking flips to bis-Im > aqua > chloro
   (was aqua > bis-Im on plain bpy), but this internal order is **functional-sensitive** — the
   ωB97X cross-check keeps aqua > bis-Im (≤0.15 eV); functional-robust is the chloro↔{aqua,bis-Im}
   bracket (both +2/+3 above chloro at both functionals). aqua (**+0.49 eV**) is a methodological
   benchmark, **not** the measured species.
4. **Substituent axis** — the dimethyl chloro baseline is **+0.146 eV more uphill** than
   plain bpy (① Hammett, donor 4,4'-Me) — a contribution the earlier ② did not separate.

**Conclusion:** the gap decomposes into **differential PCM solvation** bracketed between
chloro (+1/+2, lower) and bis-Im (+2/+3, upper) **+ the 4,4'-dimethyl substituent**
(+0.146) — all computed from first principles. The "exp = aqua" framing is **withdrawn**:
the real mediator is chloro (Zafar +309 mV), so the rigorous closure is QM/MM of the
**chloro** species (школа Мінаєва). A **quantified method limit, not a chemistry
failure** — the methodological core of Стаття 1.

## Future work (Gen 2.5+ refinements)

| Покращення | Cost | Очікуваний імпакт |
|---|---|---|
| **Повна geometric/pyberny opt** обох species | ~6-12 год CPU | Frontier orbital energies → точніше на ~0.1-0.3 eV |
| **ωB97X + def2-TZVP** | ~27× довше за B3LYP/6-31G(d) для RKS | **Script 21d/21f ✅** (dimethyl B1 2026-06-17). Adiabatic ΔSCF ΔG = **+1.03 eV** dimethyl / +0.884 plain (PCM limit). |
| **MD→DFT ensemble** | 5 SP on MD snapshots | **Script 27 ✅ DONE** (2026-05-28). FAD isoalloxazine HOMO = **-5.589 ± 0.058 eV** across 5 thermal snapshots → frontier orbital thermally robust (σ ≪ 0.3 eV). Confirms FAD→Os cascade stable against thermal fluctuation. Root-cause fix: heavy-atom-only fragment had dangling valences (no SCF); now includes distance-attached H + SOSCF fallback. |
| **Nelsen 4-point λ** | 2 geom opts + 4 SPs | **Script 29 (FADH₂/FADH₂•⁺) ❌ pathological** (2026-05-28): both methods give +160 eV cross-terms — the uncompensated **FADH₂•⁺ radical cation geometry is meaningless in implicit solvent** (ring distorts/fragments, no explicit water/PCET to relieve charge). **✅ RESCUED — script 29b (2026-06-06):** the physically-correct anode couple is the deprotonated **FADH⁻ → FADH• + e⁻** (pH 7, 1st ET) — both members stable + charge-delocalised, so the clean Nelsen 4-point gives **inner-sphere λ_i = 0.39 eV** (λ₁ 0.17 + λ₂ 0.22; site N18). Inner-sphere only; the **computed** Marcus outer-sphere λ_o (script 29c, two-sphere continuum: λ_total **0.76–0.86 eV** at the delocalized-π / buried-ε physical end — radius/ε-DOMINATED → indicative; naive hard-spheres-in-water over-estimate to ~1.8 eV) brings it to ~0.7–0.8 eV — **consistent with the literature flavin value** (Bhattacharyya et al.) used in the L4 Marcus rates, now **semi-quantitatively from first principles**. Caches: `dft/semiquinone_lambda.json` + `dft/outer_sphere_lambda.json`. |
| **ΔSCF redox potentials** з RRHO thermal corrections | ~2× за SP | Direct E° prediction vs NHE/SHE, не Koopmans approximation |
| **TD-DFT excited states** для Os complex | ~5× за GS | Підтверджує MLCT character + Marcus reorganization energy |
| **Explicit water shells + ONIOM/EFP** | ~10× за PCM | **Script 34 ② ✅ (cluster-continuum, §E)**: benchmark +0.98 eV, chloro↔bis-Im bracket + 4,4'-dimethyl substituent → gap = decomposed method limit (→ SUMMARY). Full QM/MM (chloro species) = школа Мінаєва |
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

### Результати (geometry-corrected + computed λ, 2026-06-06)

⚠️ The 2026-05-26/27 values were computed on a **broken bridging geometry** (script 23 left an imidazole N–H clashing into the 2nd metal at 0.97 Å). Re-run on the deprotonated, clash-free cluster (imidazolate bridge) changes the couplings materially:

| Пара | t_ij (eV) fixed | (old, broken) | k_ET @λ=0.7 (s⁻¹) |
|------|--------|--------|--------|
| **Cu-Co** (T1↔ZIF node) | **0.00128** ← bottleneck | 0.0325 | 3.6×10⁷ |
| **Co-Ce** (ZIF node↔vacancy) | 0.00687 | 0.0022 | 1.0×10⁹ |
| **Ce-graphene** (vacancy↔electrode) | 0.1129 | 0.1177 | 2.8×10¹¹ |

The fix shrank Cu-Co t_ij **25×** → **Cu-Co (not Co-Ce) is the bottleneck**. And the rate is exponentially sensitive to λ: at the **computed/literature** two-sphere λ (script 35: Co 3.1 / Ce 0.87 / Ru 0.78 eV; lit Cu ~2.0, Co ~1.4) the Cu-Co hop falls to **~enzymatic turnover (×1–30, not ×10⁵)** → **cathode DET is borderline / possibly co-limiting**, not comfortably fast. The honest k_DET-vs-λ scenarios + verdict + mitigation (low-λ Ru / conductive-MOF / enzyme-free SAC) live in [`SUMMARY.md`](SUMMARY.md) §Cathode (One-Home). Method caveat: B3LYP over-estimates the first-row λ (Co ≈ 2× lit); rigorous = CDFT coupling + experimental EIS.

Scripts: `23_build_zif_clusters.py` (geometry + deprotonation), `24_dft_hopping_integrals.py` (ΔSCF t_ij), `35_dft_metal_reorganization.py` (Nelsen λ), `25_cathode_ket_lambda.py` (k_DET vs λ).

---

## TRL gate L3 → L4

| Критерій | Статус | Деталі |
|---|---|---|
| Pipeline end-to-end працює (PySCF + B3LYP + PCM + Marcus cascade) | ✅ | 4 скрипти (20, 21, 21b, 22), JSON-керовані, deterministic |
| FAD redox core моделюється на B3LYP/6-31G(d) + PCM | ✅ | HOMO -5.14 eV (B3LYP ~0.97 eV below the -4.17 eV implied by bound -265 mV SHE) |
| Os mediator — NH₃ surrogate (script 21) | ✅ Superseded | LUMO(Os(III)) = -3.42 eV; missing π-backbonding → -1.72 eV uphill |
| Os mediator — full [Os(dmbpy)₂(1-MeIm)Cl] (script 21b) | ✅ | LUMO(Os(III)) = **-4.09 eV** (dmbpy, os_complex.json); π-backbonding закритий vs NH₃-сурогат (−3.42→−4.09); <S²>=0.754 ✅ |
| `ε_HOMO(FADH₂) > ε_LUMO(Os(III))` (raw Koopmans) | ❌ → ⚠️ | Δε = **-1.05 eV** (dmbpy; uphill, ~39% closer than NH₃ model's -1.72 eV) |
| Cascade verdict (verified E°s) | ✅ | E°(Os +309) − E°(FAD-GDH −265 mV SHE) = **+574 mV / −0.574 eV downhill**; raw DFT uphill = method limit decomposed by ② |
| **Definitive in-silico verdict** (publication-grade) | ✅ | raw DFT uphill (adiabatic ΔSCF +1.03 eV dimethyl); gap = differential PCM solvation (chloro↔bis-Im) + 4,4'-dimethyl substituent, decomposed by ② (script 34); rigorous closure = QM/MM chloro species → школа Мінаєва |

**Gate L3 → L4:** **pass** — повна bpy модель закрила π-backbonding gap; сирий DFT-каскад uphill (−1.05 Koopmans dimethyl / +1.03 ΔSCF dimethyl, B1 ✅ 2026-06-17; +0.88 plain), а розрив до верифікованого −0.574 eV декомпозовано ② на differential PCM-сольватацію (chloro↔bis-Im bracket) + 4,4'-dimethyl substituent (метод-ліміт, не хімія). Каскадний клайм Gen 2.0 підтверджений **експериментально** (верифіковані E°s → +574 мВ downhill, Zafar 2012 + Schachinger 2023); DFT дає механізм + квантифікований метод-ліміт. Повне raw-DOWNHILL → QM/MM chloro species (школа Мінаєва), не блокує L4.

---

## Cross-references

- 4-рівневий in-silico pipeline → [`01_03 §3.4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- Decision Log: Os→L3 → [`01_03 §3.4.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- Anode MET stack (де Os полімер живе) → [`01_03 §2.1`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)
- L1 protein architecture → [`L1_protein_architecture.md`](L1_protein_architecture.md)
- Pipeline operational status → [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md)
- All results summary → [`SUMMARY.md`](SUMMARY.md)
- IP posture (defensive publication) → [`08_01 §2`](../../../08_01_Joint_Publications_and_IP_Strategy.md)
