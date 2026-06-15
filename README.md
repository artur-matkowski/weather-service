# weather-service — Open-Meteo caching proxy for Grafana

A tiny **nginx reverse proxy that caches [Open-Meteo](https://open-meteo.com) forecast
responses**, so a Grafana dashboard always has an up-to-date 7-day forecast without hitting
Open-Meteo's free-tier rate limits.

Forecast target: **Berlin, DE** (`lat 52.52, lon 13.405`) — temperature, rain/snow,
cloud cover and wind, **hourly**, metric units.

## Why

Open-Meteo's free API is rate-limited (≈10k calls/day, 5k/hour, 600/min) and its model data
only refreshes every 1–6 hours. A Grafana panel that polls every few minutes would waste
calls and risk `429`s. This proxy caches each unique forecast URL for **30 minutes** and,
crucially, **keeps serving the last good response if Open-Meteo returns an error or rate-limits
us** (`proxy_cache_use_stale`). One upstream call every 30 min ≈ 48/day — far under the cap.

## Architecture

```
Grafana (Infinity datasource)
   │  HTTPS GET /v1/forecast?...
   ▼
Nginx Proxy Manager   weather.example.com   (TLS, web-UI managed)
   │  http://weather-cache:8080   (shared docker network: nginx_proxy_net)
   ▼
weather-cache (this repo, nginx proxy_cache)
   │  HTTPS GET /v1/forecast?...   (cache MISS only)
   ▼
api.open-meteo.com
```

## Quickstart

```bash
# The shared proxy network must exist on the host (one-time):
docker network create nginx_proxy_net   # ignore error if it already exists

docker compose up -d
docker compose ps          # weather-cache should be healthy
```

Then point Nginx Proxy Manager at `weather-cache:8080` and add the Grafana datasource +
dashboard. Full walkthroughs:

- **[docs/nginx-caching.md](docs/nginx-caching.md)** — how the cache works, verifying HIT/MISS, tuning the TTL.
- **[docs/npm-setup.md](docs/npm-setup.md)** — Nginx Proxy Manager proxy host + TLS, click by click.
- **[docs/grafana-setup.md](docs/grafana-setup.md)** — Infinity datasource, the UQL query, and the importable dashboard.

## Local test (no NPM)

Uncomment the `ports: ["8080:8080"]` block in `docker-compose.yml`, `docker compose up -d`, then:

```bash
curl -s http://localhost:8080/health   # -> ok

URL='http://localhost:8080/v1/forecast?latitude=52.52&longitude=13.405&hourly=temperature_2m,rain,snowfall,cloud_cover,wind_speed_10m,wind_direction_10m&forecast_days=7&timezone=GMT'
curl -s -D - "$URL" -o /dev/null | grep -i x-cache-status   # 1st request -> MISS
curl -s -D - "$URL" -o /dev/null | grep -i x-cache-status   # 2nd request -> HIT
```

## Layout

```
nginx/nginx.conf                              # the cache (proxy_cache) — core of the service
docker-compose.yml                            # weather-cache container on nginx_proxy_net
.env.example                                  # canonical values (location, TTL, hostname)
grafana/provisioning/datasources/infinity.yaml  # datasource (for self-hosted Grafana)
grafana/dashboards/weather-forecast.json         # importable 4-panel dashboard
docs/                                         # nginx / NPM / Grafana guides
```

## Changing the location

The cache is location-agnostic — it caches whatever `/v1/*` URL is requested. To change the
forecast point, edit the `latitude`/`longitude` in the Grafana query URL (in the dashboard
JSON and `docs/grafana-setup.md`). Adding more locations = more Grafana queries; nginx caches
each unique URL automatically, no config change needed.
