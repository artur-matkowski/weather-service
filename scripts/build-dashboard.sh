#!/usr/bin/env bash
#
# build-dashboard.sh — render the Grafana dashboard from its template using the
# location settings in .env.
#
# The committed source of truth is grafana/dashboards/weather-forecast.json.template
# (with {{TOKEN}} placeholders). This script injects your real values and writes
# grafana/dashboards/weather-forecast.json (gitignored), which you then import
# into Grafana.
#
# Usage:  ./scripts/build-dashboard.sh
#
set -euo pipefail

# --- Resolve paths relative to this script (so it runs from anywhere) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="$ROOT_DIR/.env"
TEMPLATE="$ROOT_DIR/grafana/dashboards/weather-forecast.json.template"
OUTPUT="$ROOT_DIR/grafana/dashboards/weather-forecast.json"

# --- Require .env --------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found." >&2
    echo "       Create it first:  cp .env.example .env  then set your coordinates." >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "ERROR: template not found: $TEMPLATE" >&2
    exit 1
fi

# --- Load .env (only the vars we need; ignore the rest) ------------------------
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

# --- Validate required vars ----------------------------------------------------
REQUIRED=(LATITUDE LONGITUDE PUBLIC_HOST FORECAST_DAYS TIMEZONE)
missing=()
for var in "${REQUIRED[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        missing+=("$var")
    fi
done
if (( ${#missing[@]} > 0 )); then
    echo "ERROR: missing/empty in $ENV_FILE: ${missing[*]}" >&2
    exit 1
fi

# --- Substitute tokens (bash param expansion — safe with JSONata's '$') --------
content="$(<"$TEMPLATE")"
content="${content//'{{LATITUDE}}'/$LATITUDE}"
content="${content//'{{LONGITUDE}}'/$LONGITUDE}"
content="${content//'{{PUBLIC_HOST}}'/$PUBLIC_HOST}"
content="${content//'{{FORECAST_DAYS}}'/$FORECAST_DAYS}"
content="${content//'{{TIMEZONE}}'/$TIMEZONE}"

# --- Safety: no placeholders left behind ---------------------------------------
if leftover="$(grep -oE '\{\{[A-Z_]+\}\}' <<<"$content" | sort -u)"; [[ -n "$leftover" ]]; then
    echo "ERROR: unsubstituted token(s) remain in template:" >&2
    echo "$leftover" >&2
    exit 1
fi

# --- Write output --------------------------------------------------------------
printf '%s\n' "$content" >"$OUTPUT"

# --- Optional JSON validation --------------------------------------------------
if command -v jq >/dev/null 2>&1; then
    jq empty "$OUTPUT" || { echo "ERROR: generated file is not valid JSON" >&2; exit 1; }
elif command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$OUTPUT" >/dev/null || { echo "ERROR: generated file is not valid JSON" >&2; exit 1; }
fi

# --- Summary -------------------------------------------------------------------
echo "Built dashboard:"
echo "  location     : ${LATITUDE}, ${LONGITUDE}"
echo "  host         : ${PUBLIC_HOST}"
echo "  forecast_days: ${FORECAST_DAYS}"
echo "  timezone     : ${TIMEZONE}"
echo "  output       : ${OUTPUT#"$ROOT_DIR"/}"
echo
echo "Next: import that JSON into Grafana (Dashboards -> Import)."
