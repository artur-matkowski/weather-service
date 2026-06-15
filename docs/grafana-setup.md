# Grafana setup — Infinity datasource + dashboard

Grafana reads the cached forecast through the **Infinity** datasource
(`yesoreyeram-infinity-datasource`). Open-Meteo returns *columnar* JSON (parallel arrays:
`hourly.time[]`, `hourly.temperature_2m[]`, …), so we use a small **UQL + JSONata** query to
pivot those arrays into time-series rows.

Two ways to get going: **import the ready-made dashboard** (fastest), or **build a panel by
hand** (to understand the query). Both use the same datasource.

---

## 1. Install the Infinity plugin (if missing)

- **Managed/off-site Grafana:** *Administration → Plugins → search "Infinity" → Install*.
- **Self-hosted Grafana:** set `GF_INSTALL_PLUGINS=yesoreyeram-infinity-datasource` (or
  `grafana cli plugins install yesoreyeram-infinity-datasource`) and restart.

## 2. Add the datasource

**Via UI:** *Connections → Data sources → Add → Infinity*. Name it **`Open-Meteo Cache`**.
No auth is required. Save & test.

**Via provisioning (self-hosted):** copy
[`../grafana/provisioning/datasources/infinity.yaml`](../grafana/provisioning/datasources/infinity.yaml)
into Grafana's `provisioning/datasources/` directory and restart.

> If you put an Access List in front of the cache in NPM, set the matching
> Basic Auth / header on the datasource here.

## 3a. Import the dashboard (recommended)

*Dashboards → New → Import → Upload JSON file* →
[`../grafana/dashboards/weather-forecast.json`](../grafana/dashboards/weather-forecast.json).
When prompted, pick the **Open-Meteo Cache** datasource. Done — four panels (temperature,
precipitation, cloud cover, wind) over the next 7 days.

The dashboard's time range is `now → now+7d` (it's a forecast) and it refreshes every 30 min,
matching the cache window.

## 3b. Or build a panel by hand

New panel → **Time series** → datasource **Open-Meteo Cache**, then:

| Field   | Value     |
|---------|-----------|
| Type    | `JSON`    |
| Source  | `URL`     |
| Method  | `GET`     |
| Format  | `Time series` |
| Parser  | `UQL`     |

**URL** (one call returns every variable; all panels can reuse it → one shared cache entry):

```
https://weather.example.com/v1/forecast?latitude=52.52&longitude=13.405&hourly=temperature_2m,rain,snowfall,cloud_cover,wind_speed_10m,wind_direction_10m&forecast_days=7&timezone=GMT
```

**UQL** — pick the projection for the metric you want:

Temperature:
```
parse-json
| jsonata "$zip(hourly.time, hourly.temperature_2m).{ 'time': $[0], 'temperature': $[1] }"
| extend "time"=todatetime("time")
```

Rain + snow:
```
parse-json
| jsonata "$zip(hourly.time, hourly.rain, hourly.snowfall).{ 'time': $[0], 'rain': $[1], 'snowfall': $[2] }"
| extend "time"=todatetime("time")
```

Cloud cover:
```
parse-json
| jsonata "$zip(hourly.time, hourly.cloud_cover).{ 'time': $[0], 'clouds': $[1] }"
| extend "time"=todatetime("time")
```

Wind speed + direction:
```
parse-json
| jsonata "$zip(hourly.time, hourly.wind_speed_10m, hourly.wind_direction_10m).{ 'time': $[0], 'wind_speed': $[1], 'wind_direction': $[2] }"
| extend "time"=todatetime("time")
```

All variables at once (for a table or a multi-series panel):
```
parse-json
| jsonata "$zip(hourly.time, hourly.temperature_2m, hourly.rain, hourly.snowfall, hourly.cloud_cover, hourly.wind_speed_10m, hourly.wind_direction_10m).{ 'time': $[0], 'temperature': $[1], 'rain': $[2], 'snowfall': $[3], 'clouds': $[4], 'wind_speed': $[5], 'wind_direction': $[6] }"
| extend "time"=todatetime("time")
```

### How the query works

- `$zip(a, b, …)` (a standard JSONata function) convolves the parallel arrays element-wise:
  `[[t0, v0, …], [t1, v1, …], …]`.
- `.{ 'k': $[0], … }` maps each tuple to a row object (single quotes — required, because the
  surrounding UQL `jsonata "…"` already uses double quotes).
- `extend "time"=todatetime("time")` types the time column so Grafana plots it on the X axis.

> UQL has no native `zip`; the embedded `jsonata` command + JSONata `$zip` is the supported way.

### Set the panel time range

Because this is a forecast, set the dashboard/panel time range to **`now` to `now+7d`**
(top-right time picker → Absolute/relative → `now` … `now+7d`), otherwise you'll be looking at
an empty "past" window.

### Suggested units (Panel → Standard options → Unit)

| Series          | Unit                         |
|-----------------|------------------------------|
| temperature     | Celsius (`°C`)               |
| rain            | millimetre (`mm`)            |
| snowfall        | centimetre (`cm`) — Open-Meteo reports snow in cm |
| clouds          | Percent (0–100), min 0 max 100 |
| wind_speed      | kilometre/hour (`km/h`)      |
| wind_direction  | degree (`°`), axis = right   |

## Troubleshooting

- **Empty graph:** check the time range is `now → now+7d`, not the past.
- **All values on one timestamp / no X axis:** make sure `extend "time"=todatetime("time")`
  is present and Format is `Time series`.
- **Parse error around quotes:** keep JSONata object keys in **single** quotes; only the outer
  `jsonata "…"` wrapper and `extend "time"` use double quotes.
- **Times look shifted:** the URL uses `timezone=GMT` (UTC); Grafana converts to the
  dashboard timezone for display. Set the dashboard timezone (or your browser's) as desired.
