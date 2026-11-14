# NASA POWER hourly downward short-wave and its components — Cherkasy point, 2001–2020

**What it is for:** a SECOND sky over the stem-face light logger of `docs/protocols/ebfc/stem_face_winter_light.md`.
The sheet divides the logger's daily light by ERA5's GHI of the same day, and every rehearsal of its cover rules so
far (`scripts/117`, `scripts/118`) lit the face with the same ERA5 it then divided by. `scripts/124_stem_face_second_sky.py`
lights the face with this series instead (and with a named share of its difference from ERA5) and judges it against
ERA5 — what the disagreement of two sky products does to the daily ratio, to the dip rules and to the seasonal R. The
second AIR of the same script is the MERRA-2 temperature and dew-point columns of `../power_cherkasy_longwave/`.

**Provenance — the query, not only the result** (fetched 2026-11-14 with `curl`, one request per calendar year
2001…2020; `{Y}` is the year):

```
https://power.larc.nasa.gov/api/temporal/hourly/point?parameters=ALLSKY_SFC_SW_DWN,ALLSKY_SFC_SW_DNI,ALLSKY_SFC_SW_DIFF,CLRSKY_SFC_SW_DWN&community=RE&longitude=32.06&latitude=49.44&start={Y}0101&end={Y}1231&format=CSV&time-standard=UTC
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
ALLSKY_SFC_SW_DWN      CERES SYN1deg All Sky Surface Shortwave Downward Irradiance (Wh/m^2)
ALLSKY_SFC_SW_DNI      CERES SYN1deg All Sky Surface Shortwave Downward Direct Normal Irradiance (Wh/m^2)
ALLSKY_SFC_SW_DIFF     CERES SYN1deg All Sky Surface Shortwave Diffuse Irradiance (Wh/m^2)
CLRSKY_SFC_SW_DWN      CERES SYN1deg Clear Sky Surface Shortwave Downward Irradiance (Wh/m^2)
```

The point is the one the ERA5 files of `../era5_cherkasy/` were asked for (49.44 N, 32.06 E). An hourly `Wh/m^2` is
the mean flux of that hour in W/m².

**The clock.** UTC, and a stamp is the START of the hour its value averages — the same service and convention as
`../power_cherkasy_longwave/` (its README quotes POWER's documentation). The ERA5 files run on a fixed UTC+3 and a row
is the hour ENDING at its stamp, so `124` lands each product hour one row after its stamp; its control 1 prints the
correlation of the two GHI series at neighbouring row lags and refuses a run whose best lag is not the applied one.

**Declared ceiling — what this series is NOT:**
- **Not a measurement at the site, and not the truth the logger will see.** By the header these are CERES SYN1deg
  surface fluxes — computed from satellite cloud retrievals, on a cell that is 1° × 2° at this latitude with the point
  near its western edge, in the edition POWER serves; all of that is read and quoted in
  `../power_cherkasy_longwave/README.md` (⊕ 2026-11-14, (a)–(d)) and holds for this series as the same product. The
  product's own accuracy summary (CERES_SYN1deg_Ed4A «Surface Flux Accuracy and Validation», 4/8/2021, read
  2026-11-14): Table 1 — titled there «Uncertainty (k=1 or 1σ) in Ed4.0 EBAF-Surface irradiances», which the text
  says the SYN1deg monthly uncertainties equal —, downward shortwave, land — mean irradiance 195, hourly gridded 46,
  monthly gridded 12 W/m²; Figure 1, hourly against land sites (the panel's title says «36 Sites», the figure's
  caption «27 land sites») — RMS 84 W/m², bias −2 W/m². No daily, winter or
  mid-latitude breakdown is given there, and the validation of the edition served is not published. So the series is a
  second ESTIMATE of the sky, with an hourly error of its own that is large against a December hour; what `124`
  measures is the disagreement of two estimates, which bounds the error of neither.
- **A cell, like ERA5 — coarser.** The yard under a pine crown beside a house differs from both products; point
  against cell adds scatter that no pair of gridded products shows.
- **The direct-normal and diffuse columns are the product's split,** not a measured one; `124`'s control 2 checks
  that they close on the product's own global flux under the script's sun.
- **Twenty years are not one instrument** (the geostationary boundaries of the longwave README, (d)); `124` does not
  split its seasons by them.
- **From 2001.** The hourly service starts there, so the series covers nineteen full Dec–Feb seasons of the thirty
  the ERA5 files hold.
