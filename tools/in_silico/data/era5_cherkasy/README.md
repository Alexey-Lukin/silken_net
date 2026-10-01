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

---

# ERA5 daily precipitation · hourly dew point, RH and soil temperature — same grid point, 1991–2020

**What it is for:** `scripts/74_site_rain_dew.py` — the site climate two open legs asked for and had only a
route to: rain and dew for the HW.25 rain/dew stand (`docs/protocols/anchor/gdl_rain_dew_stand.md` §7 pp. 3–4)
and the dates at which published xylogenesis thresholds are crossed, for the HW.6 install season
(`docs/01_04_CODIT_and_Xylemointegration.md` §3.5). Air temperature is NOT re-fetched: `74` joins these
hours with the committed `hourly_1991_2020.csv.gz` and refuses to run if the two clocks differ.

**Provenance — the queries** (fetched 2026-10-01 with `curl`; each file is that CSV response, unchanged —
the hourly one gzipped):

```
https://archive-api.open-meteo.com/v1/archive?latitude=49.44&longitude=32.06&start_date=1991-01-01&end_date=2020-12-31&daily=precipitation_sum,precipitation_hours&timezone=Europe%2FKyiv&models=era5&format=csv
https://archive-api.open-meteo.com/v1/archive?latitude=49.44&longitude=32.06&start_date=1991-01-01&end_date=2020-12-31&hourly=dew_point_2m,relative_humidity_2m,soil_temperature_0_to_7cm,soil_temperature_7_to_28cm&timezone=Europe%2FKyiv&models=era5&format=csv
```

→ `daily_precip_1991_2020.csv` (10 958 days) and `hourly_dew_rh_soil_1991_2020.csv.gz` (262 992 hours).
Same API, model pin and grid point as the files above (returned: 49.5 N, 32.0 E, 111 m). The soil fields are
ERA5's first two layers (0–7 and 7–28 cm): layer means, not depths.

**Declared ceiling — what these series are NOT, beyond the bullets above:**
- **Rain is a cell average.** Convective downpours are smoothed and drizzle is over-produced, so intensity
  percentiles are LOW and a ≥ 0.1 mm wet-day fraction is HIGH; `precipitation_hours` makes «intensity» a
  daily mean per wet hour, never a peak.
- **Dew from the air, not from a surface.** T2m − Td and RH at 2 m say when the AIR is near saturation;
  a radiating coupon face or bark gets dew on more nights than that.
- **Open-field soil.** Forest soil under canopy and litter warms later in spring than a reanalysis cell.
- **A fixed UTC+3 clock, not civil Kyiv time.** The queries ask for `timezone=Europe/Kyiv`, but the response
  applies one offset to all 30 years: both CSV headers here (and the older hourly file's) say
  `utc_offset_seconds` 10800 · `GMT+3`, and the hours run through the DST-change days with no gap and no
  repeat (2010-03-28T03:00 is present, 2010-10-31 has no doubled hour). So `74`'s night window 20:00–06:59
  is UTC+3 — civil 19:00–05:59 in winter — and every day of these two files is cut at UTC+3 midnight. The
  stamps are used as delivered, not converted.
