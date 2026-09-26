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

---

# ERA5 hourly 2 m air temperature · DNI · diffuse · 10 m wind — same grid point, 1991–2020

**What it is for:** the capsule thermal envelope of `scripts/71_capsule_thermal_envelope.py` (HW.37): the
hottest hour a Soldier capsule under its PEEK radome can reach, against the EDLC operating rating, and the
Arrhenius-effective temperature the EDLC ages at. Hourly, not daily, because the capsule sits OUTSIDE the
stem in air and sun — the diurnal cycle is what heats it, and a daily mean would erase exactly that.
(`51`'s daily series is right for ITS object: the anchor inside a stem that damps the diurnal swing.)

**Provenance — the query** (fetched 2026-09-26 with `curl`; the file is that CSV response, unchanged, gzipped):

```
https://archive-api.open-meteo.com/v1/archive?latitude=49.44&longitude=32.06&start_date=1991-01-01&end_date=2020-12-31&hourly=temperature_2m,direct_normal_irradiance,diffuse_radiation,wind_speed_10m&timezone=Europe%2FKyiv&models=era5&format=csv
```

Same API, model pin and grid point as the daily file above (returned: 49.5 N, 32.0 E, 111 m). 262 992 hours,
no gaps. Temperature is instantaneous at the hour; the two radiation fields are the mean of the PRECEDING
hour (Open-Meteo convention) — pairing them is a half-hour offset the script declares, not corrects.

**Declared ceiling — what this series is NOT, beyond the three bullets above:**
- **Reanalysis extremes are smoothed.** The hottest ERA5 hour here is 38.3 °C; station maxima run hotter
  by a margin this file does not know. A bound built on it is a bound on the reanalysis climate.
- **Open-field wind and open-sky radiation.** Nothing here is measured under a crown or at trunk height;
  the script brackets both rather than assuming a canopy factor.
