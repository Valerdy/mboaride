#!/usr/bin/env bash
# Prépare les données OSRM (carte du Cameroun, dont Douala). Prérequis : Docker.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/osrm"
IMAGE="ghcr.io/project-osrm/osrm-backend"
mkdir -p "$DIR"
[ -f "$DIR/cameroon-latest.osm.pbf" ] || curl -L -o "$DIR/cameroon-latest.osm.pbf" https://download.geofabrik.de/africa/cameroon-latest.osm.pbf
docker run --rm -v "$DIR:/data" $IMAGE osrm-extract -p /opt/car.lua /data/cameroon-latest.osm.pbf
docker run --rm -v "$DIR:/data" $IMAGE osrm-partition /data/cameroon-latest.osrm
docker run --rm -v "$DIR:/data" $IMAGE osrm-customize /data/cameroon-latest.osrm
echo "Terminé. Lancez : docker compose --profile osrm up -d osrm"
