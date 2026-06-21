# HW.3.IS — Thermal Stress & PEEK Long-Term Integrity Report

> **Date:** 2026-05-28 · **synced to frozen geometry + 3 fixes 2026-06-21** | **Method:** Analytical Lamé
> + **stress relaxation** (constant strain) | **Script:** `tools/in_silico/scripts/50_thermal_stress_lame.py`
> (+ `51_gusak_degradation_model.py` for the H7/s6 window) | **Geometry: FROZEN Ø11 / 2 mm wall (HW.33)**.

## Summary

Ti-6Al-4V ↔ PEEK 450G press-fit survives **20+ years** of seasonal cycling (-30°C to +40°C). Thermal
mismatch stress stays below PEEK yield (**SF 3.4×** at the 2 mm frozen wall — the wall thickness is
**CTE-limited**, not press-fit-limited; thinner than 2 mm → SF < 3). The press-fit contact pressure is far
lower than previously reported (see the 2026-06-21 correction): at the **minimum** H7/s6 interference the
relaxed P_c can fall **at or below** the sap pressure — so the **elastomer O-ring is the ESSENTIAL hermetic
seal**, not a redundancy. PEEK is a structural/thermal isolator + (at max fit) a backup contact pressure;
barbs/retaining ring handle axial pull-out + anti-rotation only.

> ⚠️ **Correction A (2026-05-28):** earlier used a **Findley creep** model (constant *stress*) reporting a
> "76 µm gap loss" — wrong physics. A press-fit is **constant *strain*** → **stress relaxation** (σ decays,
> geometry does not open a gap). Re-derived as stress relaxation.
>
> ⚠️ **Correction B (HW.3.IS, 2026-06-21) — geometry sync + 3 fixes (this is a large, honest correction):**
> 1. **Geometry** was on the stale baseline (Ø10 shaft / 3 mm wall); synced to the **frozen Ø11 / 2 mm**
>    (HW.33). σ_t @ -30°C: 10.1 → **29.7 MPa**, SF 9.9× → **3.4×**.
> 2. **contact_pressure bug:** P_c was computed at the wrong contact radius (`b = R_INNER` = the gyroid bus
>    bore, ~Ø1.6) instead of `R_INTERFACE` (the Ti shaft surface, Ø11) — over-stating P_c ~2.6×
>    (Shigley/RoyMech: `b` = the interface/bore radius). Fixed.
> 3. **Interference** was an unsourced 50 µm placeholder, inconsistent with the H7/s6 fit; replaced with the
>    **ISO 286 H7/s6 band** (Ø11 → 5-34 µm diametral). E_PEEK refined 3.6 → **4.0 GPa** (Victrex datasheet).
>
> Net: the headline P_c fell from a (buggy) **34.7 → 22.6 MPa** to an honest **0.49-3.32 → 0.32-2.16 MPa**.
> The 20-year verdict still holds (thermal 3.4× margin + the O-ring seal), but the PEEK backup pressure is
> **marginal at min fit**, not comfortable — which is exactly why the O-ring is primary.

## Materials

| Property | Ti-6Al-4V | PEEK 450G | Mismatch |
|----------|-----------|-----------|----------|
| CTE α (1/K) | 8.6×10⁻⁶ | 47×10⁻⁶ | **5.5×** |
| Young's modulus E (GPa) | 110 | **4.0** (Victrex 450G datasheet, 23°C) | 27× |
| Yield stress (MPa) | 880 | ~98-100 | — |
| Poisson's ratio ν | 0.33 | 0.40 | — |

## Geometry (FROZEN, HW.33)

Coaxial press-fit: Ti shaft Ø11 (interface r = **5.5 mm**) → PEEK sleeve 2 mm wall (outer r = **7.5 mm**,
OD/wound Ø15). The PEEK OD sits in the **tree** (compliant wood + callus), **not** a rigid outer Ti shell —
Zone 3 is the **axial** cathode flange, not a coaxial outer cylinder (see §3).

## Results

### 1. Thermal Stress (Lamé Thick-Walled Cylinder)

| Temperature | ΔT (K) | σ_t (MPa) | Safety Factor |
|-------------|--------|-----------|---------------|
| -30°C (winter) | -50 | -29.73 | **3.4×** |
| -10°C | -30 | -17.84 | 5.6× |
| +20°C (assembly) | 0 | 0 | ∞ |
| +40°C (summer) | +20 | +11.89 | 8.4× |

**Worst case:** -30°C → σ_t = 29.7 MPa, SF **3.4×** vs PEEK yield (100 MPa). The 2 mm wall is **CTE-limited**
(SF must stay > 3); at < 2 mm SF drops below 3. Thermal stress is not a failure mode, but the margin is
3.4×, not the baseline's 9.9× (which was on the thicker 3 mm wall).

### 2. Press-Fit Contact Pressure — Stress Relaxation (constant strain)

Contact pressure from the **H7/s6 fit** (ISO 286, Ø11 → 5-34 µm diametral), at the bug-fixed contact radius
`b = R_INTERFACE` = 5.5 mm. P_c spans the fit band; the **minimum** interference governs sealing:

| Time | P_c min (MPa) | P_c max (MPa) | min vs sap (0.5 MPa) |
|------|---------------|---------------|----------------------|
| 0 yr | 0.49 | 3.32 | ≈ sap |
| 1 yr | 0.38 | 2.58 | ≤ sap → O-ring |
| 20 yr | **0.32** | **2.16** | ≤ sap → **O-ring carries the seal** |

Model: `P_c(t) = P_c(0)·[E∞/E0 + (1−E∞/E0)·exp(−t/τ)]`, E∞/E0 ≈ 0.65, τ ≈ 1 yr — an **INTERIM
literature-Prony** estimate (the 2-term structure is validated by published PEEK 450G ISV models — MDPI
Polymers 2021 PMC8199459, two relaxing components — and kept **conservative**: at forest temps (≪ Tg 143°C)
PEEK relaxation is slow → real retention likely > 0.65, so this **under-states** residual P_c). The
authoritative multi-term Maxwell-Wiechert fit stays with **школа Гусака** (`08_01 Стаття 2`).

**The H7/s6 band is well-bounded:** at MIN fit the relaxed PEEK P_c (0.32 MPa) ≤ sap → the O-ring is
essential; at MAX fit the press-fit hoop stress (script 51: σ_hoop ≈ 40 MPa @ -30°C + max interference,
thin-wall) stays < PEEK yield (SF ≈ 2.5× thin-wall / higher thick-wall). Both ends acceptable.

### 3. Winter behaviour — inner interface tightens; outer = tree

PEEK has 5.5× the CTE of Ti, so on cooling it shrinks more → at the **inner** Ti↔PEEK interface it grips
the shaft **tighter** (good; interference increases). A *hypothetical* rigid outer Ti shell would lose
≈ 14 µm of interference at -30°C — but the frozen anchor's PEEK OD is the **wound in the tree** (compliant
wood + callus), not a Ti shell, so the old "outer Ti cold-leak" was a **baseline modelling artifact**. The
hermetic seal is the **axial O-ring at the flange** (immune to this).

## Conclusions

1. **Thermal stress is not a failure mode** — SF **3.4×** at the frozen 2 mm wall (the wall is CTE-limited).
2. **Press-fit relaxes, not creeps** — P_c decays toward a semicrystalline floor. But the honest frozen P_c
   (0.49-3.32 → 0.32-2.16 MPa) is **far lower** than the old buggy 34.7→22.6; at MIN fit relaxed P_c ≤ sap.
3. **Sealing = elastomer O-ring** (FKM/EPDM) — **essential**, not redundant (PEEK backup is marginal at min fit).
4. **Barbs/retaining ring = axial pull-out + anti-rotation only** — they do not seal.
5. **Winter:** inner interface tightens; the "outer interface" is the tree, not a Ti shell (artifact dropped).
6. **No mesh-FEA** for the axisymmetric stress (analytic Lamé); barb-tip stress-concentration → Гусак.

## Remaining Tasks

- [ ] **Prony-series stress-relaxation fit** for PEEK 450G (Maxwell-Wiechert, measured creep data) — the
  authoritative multi-term fit replacing the interim conservative 2-term estimate (школа Гусака, `08_01 Стаття 2`).
- [ ] **Barb-tip stress-concentration FEA** → школа Гусака (heavy mesh-FEA outsourced, `00_02 §4a`). 👤 — but
  if Гусак stays unresponsive, a **self-own** light bound is a future-candidate (00_07 HW.3.IS).
- [ ] **MD ion-permeation** of Ti²⁺/V³⁺ through PEEK via MSD (classical MD, like script 13) — NOT DFT.
  🤖 self-own, ~2-3 weeks GPU (00_07 HW.3.IS); separate milestone, not part of this geometry sync.
- [ ] **(refinement, future)** a unified thick-wall Lamé combining interference + thermal stress in one model
  (scripts 50/51 currently compute the two components separately) — a Гусак/future nicety, not blocking.

## Cross-References

- Coaxial topology + mechanical lock → `docs/01_01 §4.3`
- Frozen dims + ΔCTE window (SF 3.4×) → `docs/01_01 §1` + `§4.2`
- O-ring seal + Flush Mount → `docs/01_04 §3.1`
- Prony-series / barb-FEA outsource boundary → `docs/00_02 §4a`, `docs/08_01 Стаття 2` (школа Гусака)
- Script → `tools/in_silico/scripts/50_thermal_stress_lame.py` + `51_…` · Cache → `cache/kinetics/{thermal_stress_lame,gusak_degradation}.json`
