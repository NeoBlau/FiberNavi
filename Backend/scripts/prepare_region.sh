#!/usr/bin/env bash
# Готовит данные региона для docker-compose: OSM для Valhalla, PMTiles (Planetiler), базу Photon.
# Повторный запуск пропускает то, что уже скачано. FORCE=1 перекачивает всё.
#
# Нужны: curl, tar, bzip2, docker. Опционально: osmium (обрезка PBF по bbox).
set -euo pipefail

cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Нет Backend/.env — скопируй из .env.example" >&2; exit 1; }
set -a; source .env; set +a

DATA=data
mkdir -p "$DATA"/{valhalla,photon,tiles,cache}

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
need() { [[ "${FORCE:-0}" == 1 || ! -e "$1" ]]; }

check_url() {
  if ! curl -fsSIL -o /dev/null "$1"; then
    echo "URL недоступен: $1" >&2
    echo "Проверь значение в Backend/.env" >&2
    exit 1
  fi
}

# --- 1. OSM -> Valhalla ------------------------------------------------------
RAW_PBF="$DATA/cache/source.osm.pbf"
REGION_PBF="$DATA/valhalla/$REGION_NAME.osm.pbf"

if need "$RAW_PBF"; then
  log "Скачиваю OSM: $OSM_PBF_URL"
  check_url "$OSM_PBF_URL"
  curl -fL --retry 3 -o "$RAW_PBF.part" "$OSM_PBF_URL" && mv "$RAW_PBF.part" "$RAW_PBF"
fi

if need "$REGION_PBF"; then
  if command -v osmium >/dev/null; then
    log "Обрезаю PBF по bbox $REGION_BBOX"
    osmium extract --bbox "$REGION_BBOX" --strategy smart --overwrite -o "$REGION_PBF" "$RAW_PBF"
  else
    log "osmium не найден — Valhalla получит выгрузку целиком (дольше сборка, больше граф)"
    cp "$RAW_PBF" "$REGION_PBF"
  fi
  # Граф строится заново при следующем старте контейнера.
  rm -rf "$DATA/valhalla/valhalla_tiles" "$DATA/valhalla/valhalla_tiles.tar"
fi

# --- 2. PMTiles (схема OpenMapTiles, как у OpenFreeMap) ---------------------------
# Planetiler строит тайлы прямо из обрезанного PBF. Стили приложения рассчитаны на эту схему.
TILES="$DATA/tiles/$REGION_NAME.pmtiles"
if need "$TILES"; then
  log "Строю PMTiles через Planetiler (maxzoom $PMTILES_MAXZOOM)"
  docker run --rm -v "$PWD/$DATA:/data" "$PLANETILER_IMAGE" \
    "--osm-path=/data/valhalla/$REGION_NAME.osm.pbf" \
    "--output=/data/tiles/$REGION_NAME.pmtiles" \
    "--bounds=$REGION_BBOX" "--maxzoom=$PMTILES_MAXZOOM" \
    --download --force
fi

# --- 3. Photon -----------------------------------------------------------------
if need "$DATA/photon/photon.jar"; then
  log "Скачиваю Photon $PHOTON_VERSION"
  check_url "$PHOTON_JAR_URL"
  curl -fL --retry 3 -o "$DATA/photon/photon.jar" "$PHOTON_JAR_URL"
fi

if need "$DATA/photon/photon_data"; then
  if [[ -z "${PHOTON_DUMP_URL:-}" ]]; then
    echo "PHOTON_DUMP_URL пуст. Найди дамп под Photon ${PHOTON_VERSION%%.*}.x на https://download1.graphhopper.com/public/ и впиши в .env" >&2
    exit 1
  fi
  log "Скачиваю базу Photon: $PHOTON_DUMP_URL"
  check_url "$PHOTON_DUMP_URL"
  # Распаковываем рядом и подменяем целиком, чтобы не смешать старую и новую базу.
  rm -rf "$DATA/photon/photon_data.new" && mkdir -p "$DATA/photon/photon_data.new"
  decompress=bzip2; command -v pbzip2 >/dev/null && decompress=pbzip2
  curl -fL --retry 3 "$PHOTON_DUMP_URL" | "$decompress" -cd | tar x -C "$DATA/photon/photon_data.new"
  rm -rf "$DATA/photon/photon_data"
  mv "$DATA/photon/photon_data.new/photon_data" "$DATA/photon/photon_data"
  rm -rf "$DATA/photon/photon_data.new"
fi

log "Готово. Запуск: docker compose up -d, затем ./scripts/smoke_test.sh"
