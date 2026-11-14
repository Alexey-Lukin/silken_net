# NASA POWER hourly downward long-wave — Cherkasy point, 2001–2020

**What it is for:** the sky of `scripts/79_flange_cambium_frost.py` under cloud. `79` carries two forms of a cloudy
sky's long-wave emission — «linear» (a fully covered sky is black) and «B82» (clear sky times `1 + 0.22·c²`) — and its
frost verdict hangs on which one holds (`docs/01_04 §3.1`, «яка форма хмарного неба діє на ділянці»).
`scripts/120_sky_longwave_product.py` sets both forms, and `79`'s clear-sky formula, against this series and re-runs
`79`'s frost half under the product's own sky.

**Provenance — the query, not only the result** (fetched 2026-11-13 with `curl`, one request per calendar year
2001…2020; `{Y}` is the year):

```
https://power.larc.nasa.gov/api/temporal/hourly/point?parameters=ALLSKY_SFC_LW_DWN,CLRSKY_SFC_LW_DWN,T2M,T2MDEW,CLOUD_AMT&community=RE&longitude=32.06&latitude=49.44&start={Y}0101&end={Y}1231&format=CSV&time-standard=UTC
```

→ `hourly_2001_2020.csv.gz` (175 320 hours, none missing): the data rows of the twenty responses, concatenated in
year order under the one column line they all share; the per-response header block is dropped and quoted here
(year 2001's; the twenty headers were compared after the fetch and differ only in the dates — the raw responses
are not kept in the tree):

```
NASA/POWER Source Native Resolution Hourly Data
Dates (month/day/year): 01/01/2001 through 12/31/2001 in UTC
Location: Latitude  49.44   Longitude 32.06
Elevation from MERRA-2: Average for 0.5 x 0.625 degree lat/lon region = 116.19 meters
The value for missing source data that cannot be computed or is outside of the sources availability range: -999
Parameter(s):
ALLSKY_SFC_LW_DWN     CERES SYN1deg All Sky Surface Longwave Downward Irradiance (Wh/m^2)
CLRSKY_SFC_LW_DWN     CERES SYN1deg Clear Sky Surface Longwave Downward Irradiance (Wh/m^2)
T2M                   MERRA-2 Temperature at 2 Meters (C)
T2MDEW                MERRA-2 Dew/Frost Point at 2 Meters (C)
CLOUD_AMT             CERES SYN1deg Cloud Amount (%)
```

The point is the one the ERA5 files of `../era5_cherkasy/` were asked for (49.44 N, 32.06 E). An hourly `Wh/m^2` is
the mean flux of that hour in W/m².

**The clock.** UTC, and a stamp is the START of the hour its value averages — POWER's documentation, read
2026-11-13: «…time stamp represents the start of the hour for the whole hour» (`https://power.larc.nasa.gov/docs/faqs/other/`,
Time Information) and «Provides parameters by hour with average values»
(`https://power.larc.nasa.gov/docs/services/api/temporal/hourly/`). The ERA5 files run on a fixed UTC+3, and `79`
applies a row to the hour ENDING at it, so `120` lands each product hour one row after its stamp and refuses to
run if an hour is unmatched. What checks that pairing, and what cannot — `120`'s controls 3 and 4.

**Declared ceiling — what this series is NOT:**
- **Not a measurement at the site.** By the response's header `ALLSKY_SFC_LW_DWN` and `CLRSKY_SFC_LW_DWN` are CERES
  SYN1deg surface fluxes. That such fluxes are computed (radiative transfer on satellite cloud retrievals and
  assimilated profiles), on what cell, in which edition POWER serves them and how accurately at an hourly step has
  NOT been read from a primary here. The paper to read is Rutan et al. 2015, *J. Atmos. Oceanic Technol.*,
  doi:10.1175/JTECH-D-14-00165.1 — and which edition it validates against the one served is part of that reading.
  Until then the numbers of `120` compare forms; they do not calibrate `79`. ⊕ 2026-11-14 (`122`): the product's own data-quality summary —
  CERES_SYN1deg_Ed4A Data Quality Summary V1, updated 5/8/2025
  (`https://ceres.larc.nasa.gov/documents/DQ_summaries/CERES_SYN1deg_Ed4A_DQS.pdf`, read 2026-11-14) — says the surface fluxes use
  «six-hourly 1°×1° GEOS-5.4.1 temperature and relative humidity profiles» (§1.2.1) and that «Clear-sky fluxes are also computed
  hourly for each equal-area grid by removing clouds» (§1.2.2): the clear-sky flux is the all-sky computation without clouds, on
  GEOS-5.4.1 profiles, not on the MERRA-2 air of the same row. Which edition POWER serves, and the surface-flux accuracy summary,
  are still not read.
  ⊕ 2026-11-14 — read (the lines above are not rewritten):
  (a) EDITION. POWER's methodology page (`https://power.larc.nasa.gov/docs/methodology/data/sources_fluxes/`) lists «CERES SYN1deg
  Edition 4.2» from January 1, 2001; the Data Quality Summary's title page names «Terra-Aqua-NOAA20 Edition4B — Release Date: May 7,
  2025» and says «SYN1deg Edition4B (Edition4.2 on the ordering tool)». The API response names no edition, so «the rows are
  Edition4B» is POWER's statement about its archive, not something read from this file.
  (b) CELL. Not 1° × 1° at this latitude. The same summary, §3: «Processing is performed on a nested grid (Table 3-1) … The final
  product contains a complete 360x180 1° grid created by replication», and Table 3-1 gives the segment 45° to 70° a longitude
  extent of 2°. A probe of the POWER API around the point (2026-11-14; points and responses in the handoff corpus,
  `2026-11-14_hw6_ceres_syn1deg_primary.md`) returned one value over 49–50° N × 32–34° E; the point sits near that cell's western edge.
  (c) ACCURACY AT AN HOURLY STEP. No validation of Edition4B is published («An updated Data Quality Summary will be available
  soon»). For Edition 4A: CERES_SYN1deg_Ed4A «Surface Flux Accuracy and Validation», 4/8/2021, Table 1 («Uncertainty (k=1 or 1σ)»)
  — downward longwave, land: mean irradiance 333, hourly gridded 24, monthly gridded 10 W/m². Rutan et al. 2015 validate
  Edition 3A at a 3-hourly step (their Table 4, SYN1deg, all sites: standard deviation 20.4 W/m², 6.2 %). Neither gives a night,
  winter or snow-cover breakdown.
  (d) NIGHT CLOUD. The Data Quality Summary, §4.1: when a geostationary satellite «is upgraded to a newer generation instrument,
  the discontinuity in fluxes at the temporal boundary is more pronounced in Ed4A than in Ed3A»; the surface summary: «The
  difference in nighttime cloud properties is larger than the difference in daytime cloud properties». So the twenty winters are
  not one instrument, and `120` does not split its seasons by that boundary; which geostationary domain serves 32–34° E after
  2004 is not read.
  What this changes: the cell and the edition are named; an hourly uncertainty of that size is the scatter of single hours, not
  a statement about a median over frost nights — the numbers of `120` still compare forms and do not calibrate `79`.
- **Not on ERA5's temperature.** `T2M` and `T2MDEW` are MERRA-2's; on frost hours ERA5's air temperature at the
  same point runs warmer (`120` prints by how much). A flux in W/m² set against ERA5's black-body flux therefore
  mixes the two reanalyses; `120` judges the cloud term by the ratio all-sky / clear-sky, which no temperature
  enters on the product's side, and carries the product's sky into `79` in three named readings. `T2MDEW` is a
  «Dew/Frost Point» by the header; whether it is a frost point below 0 °C is not said there, and `120` prints its
  clear-sky comparison both ways.
- **Not ERA5's cloud.** `CLOUD_AMT` is CERES's cloud amount, not the ERA5 total cover `79` weighs its forms with;
  the two disagree hour by hour, and `120` prints the comparison under each.
- **An hour's mean beside an instant.** ERA5's temperature is the value at the hour; the product's is an hour's
  mean, placed at the hour's end — up to half an hour, which `120` declares, not corrects.
- **From 2001.** The hourly service starts there («Hourly UTC and LST time standards data are available from
  2001/01/01 to Near Real Time», the same API page), so every comparison runs on 2001–2020, not on the thirty
  years `79` caches.
