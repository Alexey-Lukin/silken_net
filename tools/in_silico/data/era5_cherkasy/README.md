# ERA5 daily 2 m air temperature — Cherkasy grid point, 1991–2020

**What it is for:** the field temperature of the Arrhenius equivalence in `scripts/51_gusak_degradation_model.py`
(`arrhenius_field_temperature`). The quantity that matters is not the mean temperature but the
**Arrhenius-effective** one, `T_eff = −(Ea/k) / ln⟨exp(−Ea/kT)⟩` over the daily series: warm days dominate
the average of a rate, so `T_eff` sits well above the arithmetic mean.

**Provenance — the query, not only the result** (fetched 2026-09-24 with `curl`):

```
https://archive-api.open-meteo.com/v1/archive?latitude=49.44&longitude=32.06&start_date=1991-01-01&end_date=2020-12-31&daily=temperature_2m_mean&timezone=Europe%2FKyiv&models=era5
```

Open-Meteo Historical Weather API, reanalysis model **ERA5** pinned by `models=era5` (grid point returned:
49.5 N, 32.0 E, elevation 111 m); the variable is the daily mean of 2 m air temperature, °C. 10 958 days, no gaps.
The CSV is the `daily` block of that response, unchanged.

**Declared ceiling — what this series is NOT:**
- **Air, not stem.** The anchor sits inside a pine stem, whose temperature damps the air's extremes; damping
  lowers `T_eff`, so an air-based `T_eff` is an UPPER bound on the stem's → the field-year equivalence it
  gives is a LOWER bound.
- **Frost is counted as slow liquid, not as ice.** About a fifth of the days are below 0 °C; frozen sap
  releases even less than Arrhenius extrapolates — the same direction (more field years, not fewer).
- **A grid cell, not a site.** Reanalysis resolution (~0.25°) — the forest plot is not named here.
