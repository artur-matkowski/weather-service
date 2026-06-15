# Nginx Proxy Manager — exposing the cache

NPM provides the TLS + routing layer (via its web UI); the `weather-cache` container does the
actual caching. NPM reaches the container **by name** over the shared `nginx_proxy_net`
network, so deploy this stack on the **same Docker host as your NPM instance**.

## 0. Prerequisites

- `weather-cache` is running and joined to `nginx_proxy_net`:
  ```bash
  docker network create nginx_proxy_net    # one-time, ignore "already exists"
  docker compose up -d
  docker network inspect nginx_proxy_net --format '{{range .Containers}}{{.Name}} {{end}}'
  # -> should list both your NPM container and weather-cache
  ```

## 1. Add the Proxy Host

In NPM: **Hosts → Proxy Hosts → Add Proxy Host**

**Details tab**

| Field              | Value                       |
|--------------------|-----------------------------|
| Domain Names       | `weather.example.com` |
| Scheme             | `http`                      |
| Forward Hostname   | `weather-cache`             |
| Forward Port       | `8080`                      |
| Cache Assets       | **off** (this nginx already caches) |
| Block Common Exploits | on                       |
| Websockets Support | off                         |

**SSL tab**

| Field                     | Value                         |
|---------------------------|-------------------------------|
| SSL Certificate           | *Request a new SSL Certificate* (Let's Encrypt) |
| Force SSL                 | on                            |
| HTTP/2 Support            | on                            |
| Email / agree to ToS      | fill in / tick                |

Save.

## 2. DNS

Point `weather.example.com` at the NPM box, following your existing homelab pattern:

- **LAN:** add an A record in your local DNS server → NPM box IP.
- **Public (for Let's Encrypt / off-site Grafana):** add an A/CNAME at your DNS provider → NPM box public IP.

## 3. Verify

```bash
# From a machine that resolves the domain:
curl -s 'https://weather.example.com/health'    # -> ok
curl -s -D - 'https://weather.example.com/v1/forecast?latitude=52.52&longitude=13.405&hourly=temperature_2m&forecast_days=7&timezone=GMT' -o /dev/null \
  | grep -iE 'HTTP/|x-cache-status'
# -> HTTP/2 200  and  x-cache-status: MISS  (then HIT on the next call)
```

## Optional: restrict access

The cache exposes only `/health` and `/v1/*` (read-only GETs), but if you want to limit who
can reach it, use NPM's **Access List** (Basic Auth or IP allow-list) on the proxy host —
then add the matching credentials to the Grafana datasource (see docs/grafana-setup.md).
