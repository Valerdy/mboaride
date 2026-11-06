# Prépare les données OSRM (carte du Cameroun, dont Douala).
# Prérequis : Docker Desktop démarré. À lancer depuis le dossier du projet :
#   powershell -ExecutionPolicy Bypass -File scripts\osrm-prepare.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "osrm"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$pbf = Join-Path $dir "cameroon-latest.osm.pbf"
$image = "ghcr.io/project-osrm/osrm-backend"

if (-not (Test-Path $pbf)) {
  Write-Host "1/4 Téléchargement de la carte du Cameroun (Geofabrik)..."
  Invoke-WebRequest -Uri "https://download.geofabrik.de/africa/cameroon-latest.osm.pbf" -OutFile $pbf
} else { Write-Host "1/4 Carte déjà téléchargée." }

Write-Host "2/4 Extraction du réseau routier (profil voiture)..."
docker run --rm -v "${dir}:/data" $image osrm-extract -p /opt/car.lua /data/cameroon-latest.osm.pbf
Write-Host "3/4 Partitionnement..."
docker run --rm -v "${dir}:/data" $image osrm-partition /data/cameroon-latest.osrm
Write-Host "4/4 Personnalisation..."
docker run --rm -v "${dir}:/data" $image osrm-customize /data/cameroon-latest.osrm

Write-Host "Terminé. Lancez : docker compose --profile osrm up -d osrm"
