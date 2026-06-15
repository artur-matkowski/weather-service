# nginx caching — how it works & how to tune it

The whole service is one nginx `server` block in [`../nginx/nginx.conf`](../nginx/nginx.conf).
This page explains the moving parts and how to verify/tune them.

## What gets cached

Any request to `/v1/*` is proxied to `https://api.open-meteo.com/v1/*` and the response is
cached. The **cache key is `$request_method$request_uri`** — i.e. the full path **and query
string**. So these are independent cache entries:

```
/v1/forecast?latitude=52.52&longitude=13.405&hourly=temperature_2m&forecast_days=7
/v1/forecast?latitude=48.21&longitude=16.37&hourly=temperature_2m&forecast_days=7
```

This is why adding a second Grafana location needs **no config change** — it's just a
different URL, which becomes its own cache entry.

> Tip: keep every Grafana panel pointed at the **same full URL** (all hourly variables in one
> request). Open-Meteo returns all variables in a single response, so all panels share **one**
> cache entry and **one** upstream call.

## The freshness window (TTL)

```nginx
proxy_cache_valid 200 30m;
```

A cached `200` is considered **fresh for 30 minutes**. Within that window every request is a
`HIT` served from disk — zero upstream calls. After 30 min the next request triggers a
background refresh.

Open-Meteo's models only update every 1–6h, so 30 min keeps the forecast current while keeping
upstream calls to ~48/day per URL (limit: <10k/day, 5k/hour, 600/min).

**To change it:** edit that one line. Examples:
- `proxy_cache_valid 200 15m;` — fresher (≈96 calls/day per URL)
- `proxy_cache_valid 200 1h;` — leaner (≈24 calls/day per URL)

After editing: `docker compose restart weather-cache`.

## Rate-limit / outage resilience (the important bit)

```nginx
proxy_cache_use_stale error timeout updating
                      http_429 http_500 http_502 http_503 http_504;
proxy_cache_background_update on;
proxy_cache_lock on;
```

- **`use_stale ... http_429 ...`** — if Open-Meteo rate-limits us (`429`) or errors out, nginx
  serves the **last good cached copy** instead of failing. Grafana keeps showing a forecast.
- **`background_update on`** — when an entry goes stale, nginx serves the stale copy
  *immediately* and refreshes it in the background (no request waits on upstream).
- **`lock on`** — if several requests miss at once, only **one** goes upstream; the rest wait
  for it. Prevents a thundering herd against Open-Meteo.

## Verifying HIT / MISS

The response carries an `X-Cache-Status` header (`MISS`, `HIT`, `STALE`, `UPDATING`,
`EXPIRED`). With `ports: ["8080:8080"]` temporarily enabled:

```bash
URL='http://localhost:8080/v1/forecast?latitude=52.52&longitude=13.405&hourly=temperature_2m,rain,snowfall,cloud_cover,wind_speed_10m,wind_direction_10m&forecast_days=7&timezone=GMT'

curl -s -D - "$URL" -o /dev/null | grep -i x-cache-status   # MISS (first time)
curl -s -D - "$URL" -o /dev/null | grep -i x-cache-status   # HIT
```

You can also watch the access log, which prints `cache=HIT|MISS|...`:

```bash
docker compose logs -f weather-cache
```

## Cache storage

```nginx
proxy_cache_path /var/cache/nginx/openmeteo
    levels=1:2 keys_zone=openmeteo:10m max_size=100m inactive=24h use_temp_path=off;
```

Cached bodies live on the `openmeteo_cache` Docker volume, so they **survive container
restarts** (warm cache on boot). `max_size=100m` caps disk use; `inactive=24h` evicts entries
not requested for a day. Forecast responses are a few KB each, so 100 MB is plenty.

To wipe the cache:

```bash
docker compose down
docker volume rm weather-service_openmeteo_cache
docker compose up -d
```

## Notes

- **`Accept-Encoding ""`** is set so Open-Meteo returns uncompressed JSON. The cache key does
  not vary on encoding, so forcing identity avoids serving a gzipped body to a client that did
  not ask for it.
- **`resolver` + variable `proxy_pass`** — `api.open-meteo.com` is re-resolved at runtime
  (DNS cached 5 min) instead of being pinned at startup.
- **`timezone=GMT`** in the URL makes Open-Meteo return UTC timestamps; Grafana then renders
  them in the dashboard's timezone. (See docs/grafana-setup.md.)
