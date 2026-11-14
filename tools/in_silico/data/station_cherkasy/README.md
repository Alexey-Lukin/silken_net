# Cherkasy synoptic station — daily minimum temperature and wind; and MERRA-2 for the same point

**What it is for:** `scripts/121_cold_edge_station.py` (HW.37) — whether the reanalysis the cold edge stands on (ERA5,
`../era5_cherkasy/`) runs warm on cold nights, on two station records that share no day, and what a second reanalysis
gives for the same edge. And `scripts/123_wind_reanalyses_station.py` (HW.43) — which of the two reanalyses the station's
own wind sits nearer to.

**Provenance — the queries, not only the results** (all fetched 2026-11-13 with `curl`; each file is the response,
unchanged, gzipped):

`ghcnd_UPM00033487_2000_2009.csv.gz` — NOAA NCEI, GHCN-Daily:

```
https://www.ncei.noaa.gov/access/services/data/v1?dataset=daily-summaries&stations=UPM00033487&startDate=1991-01-01&endDate=2020-12-31&dataTypes=TMIN,TMAX,TAVG&format=csv&units=metric&includeAttributes=true&includeStationName=true&includeStationLocation=true
```

Station as returned: «CERKASSY, UP», 49.4 N 32.1 E, 105 m. Asked for 1991–2020, the record carries 2000-01-01 … 2009-06-17
only: 3 004 rows, TMIN on 2 558 of them. `*_ATTRIBUTES` is «measurement flag, quality flag, source flag». Every value's
source flag is `u`; of the TMIN values 2 483 have a blank quality flag, 74 carry `I` and one `G`. The flag meanings are
from the GHCN-Daily readme (`https://www.ncei.noaa.gov/pub/data/ghcn/daily/readme.txt`, read 2026-11-13): «Blank = did
not fail any quality assurance check», «G = failed gap check», «I = failed internal consistency check»,
«u = Ukraine update». Temperatures are °C here (`units=metric`).

`gsod_33487099999_1991_1998.csv.gz` — NOAA NCEI, Global Summary of the Day:

```
https://www.ncei.noaa.gov/access/services/data/v1?dataset=global-summary-of-the-day&stations=33487099999&startDate=1991-01-01&endDate=2020-12-31&format=csv&includeAttributes=true&includeStationName=true&includeStationLocation=true
```

Station as returned: «CHERKASY, UP», 49.4166666 N 32.05 E, 107.0 m. Asked for 1991–2020, the record carries 1991 … 1998:
1 695 rows, dense in 1991–1994 (345–362 rows a year), thin after (148 · 56 · 46 · 25). **Units are the product's own, not
metric: temperatures in °F, wind in knots, missing = `9999.9` / `999.9`.** A request with `units=metric` converts the wind
columns only (and turns the missing wind value into 514.4) and leaves the temperatures in °F — seen on this station on
2026-11-13 by fetching the same ten days both ways; this file is the request WITHOUT `units`. `MIN_ATTRIBUTES`: blank on
1 019 rows — one of them carries the missing value, so 1 018 explicit minima — and `*` on 676. The product's readme (`https://www.ncei.noaa.gov/data/global-summary-of-the-day/doc/readme.txt`,
dated 10/28/2020, read 2026-11-13): «MIN - Minimum temperature reported during the day in Fahrenheit to tenths. Missing
= 9999.9»; «Blank indicates minimum temperature was taken from the explicit minimum temperature report and not from the
'hourly' data»; «* indicates minimum temperature was derived from the hourly data»; «Time of minimum temperature report
varies by country and region»; «The data are reported and summarized based on Greenwich Mean Time (GMT, 0000Z - 2359Z)».

`power_merra2_daily_1991_2020.csv.gz` — NASA POWER Daily API:

```
https://power.larc.nasa.gov/api/temporal/daily/point?parameters=T2M_MIN,T2M_MAX,T2M,WS10M,WS10M_MAX&community=RE&longitude=32.06&latitude=49.44&start=19910101&end=20201231&format=CSV&time-standard=UTC
```

Header of the response, verbatim: «NASA/POWER Source Native Resolution Daily Data», «Dates (month/day/year): 01/01/1991
through 12/31/2020 in UTC», «Location: latitude  49.44   longitude 32.06», «elevation from MERRA-2: Average for 0.5 x
0.625 degree lat/lon region = 116.19 meters», «T2M_MIN       MERRA-2 Temperature at 2 Meters Minimum (C)». 10 958 days,
no missing value in T2M_MIN or T2M_MAX. The point is the one the ERA5 files were asked for.

`power_merra2_hourly_wind_2001_2020.csv.tar.gz` — NASA POWER Hourly API, one request per year, the twenty responses
unchanged (fetched 2026-11-13 with `curl`; the tarball was re-packed on 2026-11-14 without the archiver's `._*`
side files — the members are byte-identical):

```
https://power.larc.nasa.gov/api/temporal/hourly/point?parameters=WS10M,WS50M,T2M&community=RE&longitude=32.06&latitude=49.44&start=<YEAR>0101&end=<YEAR>1231&format=CSV&time-standard=UTC
```

Header of each response, verbatim: «NASA/POWER Source Native Resolution Hourly Data», «in UTC», «WS10M     MERRA-2 Wind
Speed at 10 Meters (m/s)». 175 320 hours, no missing value in `WS10M`. `123` checks it against the daily file above
(the daily mean and maximum are the mean and maximum of these hours over the UTC day) and against the file `62` reads
(`../nasa_power_cherkasy_ws10m_2015_2024.json`, whose days are POWER's LST — UTC + 2 h here).

**Declared ceiling — what these series are NOT:**
- **One station, and not the forest plot.** A synoptic site at a town against reanalysis cells of 0.25° and
  0.5° × 0.625°: part of any gap is siting — cold-air pooling, snow under the screen — not reanalysis error.
- **Not one instrument across the two records.** They share no day; different archives, different station metadata
  (105 m and 107 m, 32.1 E and 32.05 E as printed). Nothing here says the screen did not move between them.
- **The station's «day» is a reporting window.** A reported minimum belongs to a synoptic window, not to the UTC day
  or to the ERA5 file's clock day; `121` takes ERA5's minimum over those two and over the night from 18:00 UTC of the previous
  day to 06:00 UTC (13 hourly values), and reports all three. Which window the station used is not read from a station manual.
- **A `*` minimum is a ceiling on the minimum, not the minimum:** the coldest of a handful of hourly reports sits at or
  above the true one. `121` keeps those days apart.
- **MERRA-2's daily minimum is the minimum of its hourly field on a UTC day** — checked by `121` against the hourly
  2 m temperature of `../power_cherkasy_longwave/` on every day of 2001–2020 (control 5); hourly MEANS, so it sits at
  or above the continuous minimum, as ERA5's lowest of 24 instants does.
- **The wind columns** (GSOD `WDSP` · `MXSPD`, MERRA-2 `WS10M` · `WS10M_MAX`) are read by
  `scripts/123_wind_reanalyses_station.py` (HW.43). GSOD's wind is in knots and the station's reports are whole metres
  per second (every `MXSPD` lands on that grid — `123`, control 2), so a station threshold is a threshold on an integer;
  `WDSP_ATTRIBUTES` is the number of reports behind the day's mean, four to ten. The product's readme (same file as
  above): «WDSP - Mean wind speed for the day in knots to tenths. Missing = 999.9»; «MXSPD - Maximum sustained wind speed
  reported for the day in knots to tenths. Missing = 999.9». The anemometer's height, type and averaging time are not
  read from a station manual.
