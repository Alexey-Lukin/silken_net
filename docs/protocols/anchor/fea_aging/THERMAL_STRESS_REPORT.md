# HW.3.IS — Thermal Stress & PEEK Creep Report

> **Date:** 2026-05-27 | **Method:** Analytical Lamé + Findley | **Script:** `tools/in_silico/scripts/50_thermal_stress_lame.py`

## Summary

Ti-6Al-4V ↔ PEEK 450G press-fit interface survives **20+ years** of seasonal temperature cycling (-30°C to +40°C) with adequate safety margin. Annular barbs (mechanical lock) are **mandatory** to compensate for long-term PEEK creep.

## Materials

| Property | Ti-6Al-4V | PEEK 450G | Mismatch |
|----------|-----------|-----------|----------|
| CTE α (1/K) | 8.6×10⁻⁶ | 47×10⁻⁶ | **5.5×** |
| Young's modulus E (GPa) | 110 | 3.6 | 30× |
| Yield stress (MPa) | 880 | 100 | — |
| Poisson's ratio ν | 0.33 | 0.40 | — |

## Geometry

Coaxial press-fit: Zone 1 Ti (r=3mm) → Zone 2 PEEK (r=5mm interface) → Zone 3 Ti (r=8mm outer).

## Results

### Thermal Stress (Lamé Thick-Walled Cylinder)

| Temperature | ΔT (K) | σ_t (MPa) | Safety Factor |
|-------------|--------|-----------|---------------|
| -30°C (winter) | -50 | -10.11 | **9.9×** |
| -10°C | -30 | -6.07 | 16.5× |
| 0°C | -20 | -4.04 | 24.7× |
| +20°C (assembly) | 0 | 0 | ∞ |
| +40°C (summer) | +20 | +4.04 | 24.7× |

**Worst case:** -30°C → σ_t = 10.1 MPa, safety factor 9.9× vs PEEK yield (100 MPa).

### PEEK Creep (Findley Power Law)

At worst-case stress 10.1 MPa:

| Time | Total Strain | Gap Loss |
|------|-------------|----------|
| 1 year | 1.07% | 53.5 µm |
| 5 years | 1.29% | 64.3 µm |
| 10 years | 1.40% | 69.8 µm |
| 20 years | 1.52% | **75.9 µm** |

Press-fit interference ~50 µm → **20-year creep exceeds interference**. Annular barbs + DIN 471 retaining ring mandatory per `01_01 §4.3`.

## Conclusions

1. **Thermal stress is NOT a problem** — 10× safety margin at extreme temperature
2. **PEEK creep IS the limiting factor** — 76 µm gap loss over 20 years
3. **Mechanical lock mandatory** — annular barbs + retaining ring prevent PEEK from cold-flowing out of press-fit
4. **No FEA needed** — axisymmetric Lamé has closed-form solution; FEA only needed for complex geometries (barb stress concentration, non-axisymmetric loads)

## Remaining Tasks

- [ ] FEA (CalculiX): stress concentration at annular barb tips
- [ ] DFT ion barrier: Ti²⁺/V³⁺ diffusion through PEEK matrix
- [ ] MD strain cycling: genipin-chitosan-CNC matrix under tidal deformation

## Cross-References

- Coaxial topology → `docs/01_01 §4.3` (PEEK mechanical lock)
- Ti metallurgy → `docs/01_02 §1.3` (EAAE + dehydrogenation)
- PEEK creep simulation request → `docs/08_01 §1.2` (школа Гусака)
- Script → `tools/in_silico/scripts/50_thermal_stress_lame.py`
- Cache → `tools/in_silico/cache/kinetics/thermal_stress_lame.json`
