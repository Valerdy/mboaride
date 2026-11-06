# Itinéraires : OSRM + OpenStreetMap (Douala)

Tâche Jira : « Installer OSRM + OpenStreetMap pour Douala et exposer le calcul d'itinéraire et de détour ».

OSRM est un moteur d'itinéraires qui calcule distance, durée et tracé à partir des données OpenStreetMap.
L'API MboaRide l'appelle et expose trois routes simples au front (carte) et aux agents (négociation).

## Option A : serveur local avec Docker (recommandé pour la démo)
Prérequis : **Docker Desktop** installé et démarré (Windows : WSL 2 activé). Prévoir quelques Go d'espace disque et 2 à 4 Go de mémoire pour Docker.

```powershell
# 1. Préparer la carte (téléchargement + calcul, une seule fois, quelques minutes)
powershell -ExecutionPolicy Bypass -File scripts\osrm-prepare.ps1
# 2. Démarrer le serveur d'itinéraires
docker compose --profile osrm up -d osrm
# 3. Dans .env : OSRM_URL=http://localhost:5000, puis relancer l'API
npm run dev
# 4. Vérifier
Invoke-RestMethod http://localhost:8000/routes/status
```
Réponse attendue : `osrm : ok`. Si l'étape 1 échoue par manque de mémoire, augmentez la mémoire de Docker Desktop (Settings, Resources).

Avantage : aucun accès internet n'est nécessaire pendant la soutenance, et les temps de réponse sont courts.

## Option B : dépannage avec le serveur public (sans Docker)
Pour avancer sans attendre, mettez dans `.env` : `OSRM_URL=https://router.project-osrm.org`.
C'est un serveur de démonstration de la communauté OSRM : usage léger uniquement, sans garantie de disponibilité, et **à ne pas utiliser pour le test de charge ni pour la soutenance**.

## Routes exposées
Les routes `/routes/*` demandent une session (`Authorization: Bearer <access_token>`), sauf `/routes/status`.
Les coordonnées sont envoyées en `lat` / `lng` et doivent être dans la zone de service (Douala et environs, réglable par `AREA_*` dans `.env`).

| Route | Rôle | Utilisée par |
|---|---|---|
| `GET /routes/status` | Vérifie qu'OSRM répond | Équipe, démo |
| `POST /routes/route` | Distance, durée et tracé GeoJSON entre deux points | Carte Leaflet (US08) |
| `POST /routes/detour` | Détour d'un conducteur pour prendre un passager, ETA de prise en charge, km partagés | Agent conducteur (US03, US05), prix (US09) |
| `POST /routes/detours` | Compare jusqu'à 50 conducteurs pour un passager, classés par détour croissant | Agent coordinateur (US05, US06) |

Exemple (PowerShell) :
```powershell
$h = @{ Authorization = "Bearer <access_token>" }
$body = '{"driver":{"origin":{"lat":4.03,"lng":9.74},"destination":{"lat":4.09,"lng":9.74}},"pickup":{"lat":4.05,"lng":9.74},"dropoff":{"lat":4.07,"lng":9.74},"max_detour_s":600}'
Invoke-RestMethod -Uri http://localhost:8000/routes/detour -Method Post -ContentType "application/json" -Headers $h -Body $body
```
Réponse : `detour_s`, `detour_m`, `detour_pct`, `pickup_eta_s`, `shared_distance_m` (base du prix), `within_limit` (si `max_detour_s` est fourni).

Le détour se calcule ainsi : durée de (départ → passager → arrivée du passager → arrivée du conducteur) moins durée du trajet direct du conducteur.

## Performance
Un cache mémoire de 10 minutes évite de recalculer les mêmes trajets. Un appel `/routes/detours` fait au plus 5 calculs OSRM en parallèle.
Mesurez le temps réel sur votre machine avant le test de charge (objectif : convergence < 2 s).
