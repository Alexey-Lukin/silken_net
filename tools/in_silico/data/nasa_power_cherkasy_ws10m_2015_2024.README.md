# `nasa_power_cherkasy_ws10m_2015_2024.json` — MERRA-2 daily mean 10 m wind, the input of `62`

**What it is for:** `scripts/62_wind_duty_cycle.py` (HW.43) — the share of days whose mean wind reaches each Beaufort
anchor. The file is the API response, unchanged.

**Provenance — the query** (fetched 2026-09-09; the URL is also in `62`'s cache, `source_url`):

```
https://power.larc.nasa.gov/api/temporal/daily/point?parameters=WS10M&community=RE&longitude=32.06&latitude=49.44&start=20150101&end=20241231&format=JSON
```

The request names no `time-standard`, so the response is in the API's default: its header says `"time_standard": "LST"`.
At this longitude a day of that file is the UTC day shifted by two hours — measured, not read from the API's
documentation, and only on the years the hourly series shares with the file: the mean of MERRA-2's hourly `WS10M` over
days of UTC + 2 h reproduces the file to its rounding on every day of 2015–2020, and UTC days miss it by up to 0.8 m/s (`scripts/123_wind_reanalyses_station.py`, control 3; the hourly
series is in `station_cherkasy/`). 3 653 daily values, none missing.

**Declared ceiling.** MERRA-2 is one reanalysis of a 0.5° × 0.625° cell, open terrain at 10 m — not the wind under a
canopy. Against the Cherkasy station's own daily mean it puts MORE days above each of `62`'s anchors than the station
does, and ERA5 fewer (`123`; the numbers are in `SUMMARY.md`, not here) — an ordering of three series of open wind,
which says nothing of the wind under a canopy.
