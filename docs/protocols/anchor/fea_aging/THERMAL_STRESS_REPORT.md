# HW.3.IS — Thermal Stress & PEEK Long-Term Integrity Report

> **Date:** 2026-05-28 | **Method:** Analytical Lamé + **stress relaxation** (constant strain) | **Script:** `tools/in_silico/scripts/50_thermal_stress_lame.py`

## Summary

Ti-6Al-4V ↔ PEEK 450G press-fit survives **20+ years** of seasonal cycling (-30°C to +40°C). Thermal stress stays ≪ PEEK yield (10× margin). Under constant-strain press-fit, contact pressure **relaxes toward a semicrystalline floor** (≈65% of initial), it does **not** collapse to zero. The **primary hermetic seal is an elastomer O-ring** (FKM/EPDM); PEEK is a structural isolator + backup contact pressure; barbs/retaining ring handle axial pull-out + anti-rotation only.

> ⚠️ **Correction (2026-05-28):** The earlier version used a **Findley creep** model (constant *stress*) and reported a "76 µm gap loss". That was the wrong physics — a press-fit is **constant *strain***, so the correct model is **stress relaxation** (σ decays, the geometry does not open a gap). The old number even exceeded the interference (unphysical). Re-derived below.

## Materials

| Property | Ti-6Al-4V | PEEK 450G | Mismatch |
|----------|-----------|-----------|----------|
| CTE α (1/K) | 8.6×10⁻⁶ | 47×10⁻⁶ | **5.5×** |
| Young's modulus E (GPa) | 110 | 3.6 | 30× |
| Yield stress (MPa) | 880 | 100 | — |
| Poisson's ratio ν | 0.33 | 0.40 | — |

## Geometry

Coaxial press-fit: Ti shaft (inner r=3mm) → PEEK sleeve → outer Ti flange (r=8mm).

## Results

### 1. Thermal Stress (Lamé Thick-Walled Cylinder)

| Temperature | ΔT (K) | σ_t (MPa) | Safety Factor |
|-------------|--------|-----------|---------------|
| -30°C (winter) | -50 | -10.11 | **9.9×** |
| -10°C | -30 | -6.07 | 16.5× |
| +20°C (assembly) | 0 | 0 | ∞ |
| +40°C (summer) | +20 | +4.04 | 24.7× |

**Worst case:** -30°C → σ_t = 10.1 MPa, safety factor 9.9× vs PEEK yield (100 MPa). Thermal stress is **not** a failure mode.

### 2. Press-Fit Contact Pressure — Stress Relaxation (constant strain)

Initial interference ~50 µm → **P_c(0) = 34.7 MPa**. Under constant strain, PEEK stress relaxes toward a floor (semicrystalline phase retains a permanent elastic network → P_c does not reach zero):

| Time | P_c (MPa) | vs sap (0.5 MPa) |
|------|-----------|------------------|
| 0 yr | 34.7 | seal holds |
| 1 yr | 27.1 | seal holds |
| 5 yr | 22.7 | seal holds |
| 20 yr | **22.6** | seal holds |

Model: `P_c(t) = P_c(0)·[E∞/E0 + (1−E∞/E0)·exp(−t/τ)]`, E∞/E0 ≈ 0.65, τ ≈ 1 yr. **These are literature-grounded estimates — a proper Prony-series (Maxwell-Wiechert) fit is requested from школа Гусака (`08_01 §1.2`).** Failure metric = residual P_c vs sap pressure (not "gap loss").

### 3. Winter Cold-Leak — OUTER Interface (the weak link)

PEEK has 5.5× the CTE of Ti, so on cooling it shrinks more. At the **inner** bore it grips the Ti shaft tighter (good); at the **outer** interface it pulls away from the Ti shell (interference lost):

`δ_eff = δ_init − r·(α_PEEK − α_Ti)·|ΔT|`

At -30°C (ΔT=50K), r=8mm: loss = **15.4 µm** → effective interference = 50 − 15.4 = **34.6 µm residual**. The outer interface survives winter, but it is the **weakest sealing link** and is exactly why the elastomer O-ring (not PEEK contact) is the primary seal.

## Conclusions

1. **Thermal stress is not a problem** — 10× safety margin at extreme temperature.
2. **Press-fit relaxes, not creeps** — contact pressure decays 34.7 → 22.6 MPa over 20 yr toward a semicrystalline floor; it does **not** open a gap. Residual P_c (22.6 MPa) ≫ sap pressure.
3. **Sealing = elastomer O-ring** (FKM/EPDM, rubber-elastic → immune to PEEK relaxation). PEEK = structural isolator + backup P_c.
4. **Barbs/retaining ring = axial pull-out + anti-rotation only** — they do **not** seal. (Earlier "barbs mandatory to compensate creep" conflated sealing with mechanical retention.)
5. **Winter weak link = outer interface** — survives (34.6 µm residual) but justifies the O-ring.
6. **No FEA needed** for the axisymmetric stress; FEA only for barb-tip stress concentration.

## Remaining Tasks

- [ ] **Prony-series stress-relaxation fit** for PEEK 450G (Maxwell-Wiechert) — replaces the 2-term E∞/τ estimate (школа Гусака, `08_01 §1.2`).
- [ ] FEA (CalculiX): stress concentration at annular barb tips.
- [ ] **MD ion-permeation** of Ti²⁺/V³⁺ through PEEK matrix via MSD (classical MD, like script 13 for glucose) — NOT DFT (DFT can't model macroscopic diffusion; only single-jump barriers via NEB).

## Cross-References

- Coaxial topology + mechanical lock → `docs/01_01 §4.3`
- O-ring seal + Flush Mount → `docs/01_04 §3.1`
- Ti metallurgy → `docs/01_02 §1.3`
- Prony-series creep/relaxation request → `docs/08_01 §1.2` (школа Гусака)
- ~~MD strain cycling~~ → ✅ DONE (script 16, pseudoplastic) — see `PIPELINE_STATUS.md`
- Script → `tools/in_silico/scripts/50_thermal_stress_lame.py` · Cache → `cache/kinetics/thermal_stress_lame.json`
