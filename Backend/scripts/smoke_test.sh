#!/usr/bin/env bash
# Проверяет поднятый бэкенд и время построения маршрута (критерий: < 2 с).
set -euo pipefail

HOST="${1:-http://localhost}"
REGION_NAME="${REGION_NAME:-moscow}"
fail=0

check() {
  local name=$1; shift
  if "$@"; then echo "OK   $name"; else echo "FAIL $name"; fail=1; fi
}

# Кремль -> Шереметьево, авто.
ROUTE='{"locations":[{"lat":55.7520,"lon":37.6175},{"lat":55.9726,"lon":37.4146}],
"costing":"auto","alternates":2,"units":"kilometers","language":"en-US"}'

route_ok() {
  local t
  t=$(curl -fsS -o /tmp/fibernavi_route.json -w '%{time_total}' \
        -H 'Content-Type: application/json' -d "$ROUTE" "$HOST:8002/route") || return 1
  echo "     маршрут построен за ${t} с"
  awk -v t="$t" 'BEGIN { exit !(t < 2.0) }'
}

check "valhalla /status" curl -fsS -o /dev/null "$HOST:8002/status"
check "valhalla /route < 2 s" route_ok
check "photon /api" curl -fsS -o /dev/null -G --data-urlencode "q=Тверская" -d limit=1 "$HOST:2322/api"
check "pmtiles TileJSON" curl -fsS -o /dev/null "$HOST:8080/$REGION_NAME.json"

exit $fail
