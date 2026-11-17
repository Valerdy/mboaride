# Backend

API FastAPI de MboaRide, branchée sur PostgreSQL et sur le système multi-agents du dossier
[`agents/`](../agents) : le prix et les horaires affichés viennent de `mboaride_agents.pricing.quote`
et de `mboaride_agents.routing.EstimatedRouting`, via le pont `app/moteur.py`. L'API ne refait aucun calcul.

| Ticket | User story | Module |
|---|---|---|
| SR-31 | US02 Exigences de confort et cercle de confiance | `app/routes/preferences.py` |
| SR-38 | US09 Connaître le prix avant de confirmer | `app/routes/prix.py` |
| SR-39 | US10 Payer par Mobile Money (simulé) | `app/routes/paiement.py` |
| SR-40 | US13 Inviter les employés et suivre l'adoption | `app/routes/organisation.py` |
| SR-41 | US14 Économies et CO2 évité | `app/routes/organisation.py` |
| SR-47 | Scénarios de démo, annulation et réaffectation | `app/routes/annulation.py`, `app/routes/demo.py` |
| US17 US19 | Comptes élèves, autorisation parentale, notifications au parent | `app/routes/eleves.py`, `sql/06_sprint3_eleves.sql` |
| US22 | Place dans un voyage interurbain, réservée à l'avance | `app/routes/voyages.py` |
| US15 | Banc de mesure du moteur exposé à l'écran de démonstration | `app/routes/banc.py` |

## Démarrage

```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows : .venv\Scripts\activate
pip install -r requirements.txt
createdb mboaride
for f in 01_schema 02_donnees_exemple 04_sprint2 05_sprint3; do psql -d mboaride -f sql/$f.sql; done
export MBOARIDE_DSN="host=localhost user=postgres dbname=mboaride"
uvicorn app.main:app --reload        # http://127.0.0.1:8000, documentation sur /docs
```

La connexion est simulée par l'en-tête `X-Utilisateur` (identifiant de l'utilisateur) en attendant
l'authentification (US01) ; les droits d'administrateur d'organisation sont vérifiés côté serveur.

## Tests

Les tests recréent une base `mboaride_test` avant chaque test, sur le serveur désigné par
`MBOARIDE_TEST_PG` (par défaut `host=localhost port=5432 user=postgres dbname=postgres`).

```bash
pytest
```

## Les deux API ensemble

L'authentification (US01) appartient à l'API Node, qui vit dans `mboaride-api-node(1)/`.
L'API Python ne l'a pas réécrite : elle vérifie les jetons que Node signe, avec le même
secret et le même algorithme, et les deux services partagent une seule base PostgreSQL.
Node y tient ses tables dans le schéma `public`, le métier reste dans `mboaride`, et la
table `compte_node` dit quel compte Node correspond à quel utilisateur, rapprochement
fait tout seul sur l'e-mail puis sur le téléphone à la première requête authentifiée.

```bash
createdb mboaride
for f in sql/0{1,2,4,5,6,7}*.sql; do psql -v ON_ERROR_STOP=1 -d mboaride -f "$f"; done

export SECRET_KEY="un-secret-partage-de-32-caracteres-minimum"

# API Node, authentification et itinéraires (port 8101)
cd "mboaride-api-node(1)" && npm install
DATABASE_URL="postgresql://postgres@127.0.0.1:5432/mboaride" PORT=8101 npm run dev

# API Python, métier et moteur multi-agents (port 8000)
export MBOARIDE_DSN="host=127.0.0.1 port=5432 user=postgres dbname=mboaride"
export MBOARIDE_SECRET_KEY="$SECRET_KEY"   # le même que celui de Node
export MBOARIDE_DEMO_AUTH=0                # refuse l'en-tête X-Utilisateur
uvicorn app.main:app --reload
```

Le parcours complet se vérifie en trois appels : `POST /auth/register` puis
`POST /auth/verify` sur le port 8101 donnent un `access_token`, et ce jeton ouvre
directement les routes de l'API Python, par exemple `GET /api/moi/demandes`. La route
`/health` de l'API Python annonce d'ailleurs si le secret est en place et si l'en-tête
de démonstration est encore accepté.

Pour de vrais itinéraires, lancer le serveur OSRM que l'API Node utilise déjà, puis
donner son adresse à l'API Python avec `MBOARIDE_OSRM_URL` :

```bash
docker run -p 5000:5000 osrm/osrm-backend osrm-routed /data/cameroon.osrm
export MBOARIDE_OSRM_URL="http://localhost:5000"
```

Les détours sont alors mesurés sur le réseau routier, et l'estimateur devient le repli :
si le serveur tombe ou répond trop lentement, la négociation continue avec une
estimation, aucun conducteur n'est écarté pour une panne réseau. Sans cette variable,
tout reste estimé et déterministe, ce dont les tests et le banc de mesure ont besoin.

## Variables d'environnement

| Variable | Rôle |
|---|---|
| `MBOARIDE_DSN` (ou `DATABASE_URL`) | connexion PostgreSQL de l'API |
| `MBOARIDE_SECRET_KEY` (ou `SECRET_KEY`) | secret partagé avec l'API Node, pour vérifier ses jetons |
| `MBOARIDE_DEMO_AUTH` | `0` refuse l'en-tête de démonstration `X-Utilisateur` |
| `MBOARIDE_OSRM_URL`, `MBOARIDE_OSRM_TIMEOUT_S` | serveur OSRM des itinéraires réels, et son délai limite |
| `MBOARIDE_TEST_PG` | serveur PostgreSQL des tests |
| `MBOARIDE_AGENTS` | chemin du dossier `agents/` s'il n'est pas voisin de `backend/` |
| `MBOARIDE_SMTP_HOST`, `MBOARIDE_SMTP_PORT`, `MBOARIDE_SMTP_USER`, `MBOARIDE_SMTP_PASSWORD` | envoi réel des e-mails d'invitation ; sans elles, l'envoi est simulé et tracé |
| `MBOARIDE_URL` | adresse publique utilisée dans les liens d'invitation |
