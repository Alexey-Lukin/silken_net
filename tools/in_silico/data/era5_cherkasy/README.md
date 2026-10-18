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

---

# ERA5 hourly total cloud cover — same grid point, 1991–2020

**What it is for:** `scripts/79_flange_cambium_frost.py` (HW.6, the frost half of «flange → cambium»): the sign
of the cambium shift under the flange flips between the clear-sky and the overcast end, so the run weighs the two
ends by the cloud the site actually has, hour by hour.

**Provenance — the query** (fetched 2026-10-12 with `curl`; the file is that CSV response, unchanged, gzipped):

```
https://archive-api.open-meteo.com/v1/archive?latitude=49.44&longitude=32.06&start_date=1991-01-01&end_date=2020-12-31&hourly=cloud_cover&timezone=Europe%2FKyiv&models=era5&format=csv
```

→ `hourly_cloud_1991_2020.csv.gz` (262 992 hours). Same API, model pin, grid point (returned: 49.5 N, 32.0 E,
111 m) and fixed UTC+3 clock as the hourly files above; `79` refuses to run if the clocks differ.

**Declared ceiling — what this series is NOT, beyond the bullets above:**
- **Total cover, not cloud radiative properties.** One fraction for all levels: a thin high veil and a low
  stratus deck at the same percentage radiate very differently, and the long-wave formulas `79` weighs with it
  were fitted on their own cloud measures, not on reanalysis cover — the role substitution is declared there.
- **A cell average.** ERA5 cloud is a model field over ~0.25°, not an observation above one trunk.

---

# Hourly snow depth — two reanalyses near the same cell · daily snow depth at the nearest station that reports it, 1991–2020

**What it is for:** `scripts/79_flange_cambium_frost.py` (HW.6, ground-reflected light on the trunk face): the albedo under
the face switches between snow and bare ground with the snow on the ground, hour by hour.

**Why not ERA5:** on this channel ERA5 carries no snow depth — the same query with `models=era5` returns `NaN` for every
hour of `snow_depth` (probed 2026-10-17, January 2010, beside a finite `snowfall`; Open-Meteo's own variable table marks
snow depth for ERA5-Land and CERRA only). So the two series below come from other reanalyses, at other grid points.

**Provenance — the queries** (fetched 2026-10-17 with `curl`; each file is that CSV response, unchanged, gzipped):

```
https://archive-api.open-meteo.com/v1/archive?latitude=49.44&longitude=32.06&start_date=1991-01-01&end_date=2020-12-31&hourly=snow_depth&timezone=Europe%2FKyiv&models=era5_land&format=csv
https://archive-api.open-meteo.com/v1/archive?latitude=49.44&longitude=32.06&start_date=1991-01-01&end_date=2020-12-31&hourly=snow_depth&timezone=Europe%2FKyiv&models=cerra&format=csv
```

→ `hourly_snow_era5_land_1991_2020.csv.gz` (grid point returned: 49.40 N, 32.10 E, 111 m — inside the ERA5 cell of the files
above, not its centre) and `hourly_snow_cerra_1991_2020.csv.gz` (49.43 N, 32.06 E, 111 m). 262 992 hours each, no gaps,
metres, on the same fixed UTC+3 clock; `79` refuses a file whose UTC offset, zone or hour labels differ from the air file's.

**The station, for the check `79` runs against them** — GHCN-Daily, station `UPM00033377` Lubny (WMO 33377, GSN; 50.02 N,
33.00 E, 156 m — about 100 km north-east of the cell): the station file

```
https://www.ncei.noaa.gov/pub/data/ghcn/daily/by_station/UPM00033377.csv.gz
```

fetched 2026-10-17, filtered to its `SNWD` rows of 1991–2020 and nothing else changed
(`awk -F, '$3=="SNWD" && substr($2,1,4)>=1991 && substr($2,1,4)<=2020'`) → `ghcnd_UPM00033377_snwd_1991_2020.csv`
(columns as GHCN delivers them: ID, date, element, value in mm, M-, Q- and S-flags, time). Neither the GHCN-Daily readme nor
its NCEI product page states a use constraint (read 2026-10-17). The nearer station (Cherkasy, `UPM00033487`) reports no snow
depth; Chyhyryn (`UPM00033605`) does, but sparsely in the years it covers and not at all in 1999–2011.

**Declared ceiling — what these series are NOT:**
- **Not ERA5, and not the cell.** Two other reanalyses at two other points; which one holds at the cell is not known, which
  is why `79` checks both against the station and gives each end the reanalysis that end asks for, asserted from the data
  (since 2026-10-18 ERA5-Land takes both ends: the less snowy at ≥ 11 cm, the snowier at ≥ 1 cm; CERRA is the opposite at
  each depth, so it takes neither).
- **The station reports only days WITH snow** — no zero is ever recorded — so a day without a record is read as snow-free,
  the same reading a missed observation would get. Rows with a quality flag are dropped (one of them reads 1839 mm in
  October).
- **Disagreement is real and measured:** over the winters, ERA5-Land has snow (≥ 1 cm) on more days than the station
  (Open-Meteo's own note: «Snow depth in ERA5-Land tends to be overestimated»), CERRA on about as many; the check's numbers
  are in `79`'s cache, not here.
- **Depth, not cover.** Snow ≥ 10.2 cm masks the ground for the albedo (Baker et al. 1990 keep only such days; `79` counts
  ≥ 11 cm on the series' 1 cm grid); shallower snow lets the ground show, so a depth threshold — not the series alone —
  decides what counts as snow-covered.
