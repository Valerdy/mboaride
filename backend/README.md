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

## Variables d'environnement

| Variable | Rôle |
|---|---|
| `MBOARIDE_DSN` (ou `DATABASE_URL`) | connexion PostgreSQL de l'API |
| `MBOARIDE_TEST_PG` | serveur PostgreSQL des tests |
| `MBOARIDE_AGENTS` | chemin du dossier `agents/` s'il n'est pas voisin de `backend/` |
| `MBOARIDE_SMTP_HOST`, `MBOARIDE_SMTP_PORT`, `MBOARIDE_SMTP_USER`, `MBOARIDE_SMTP_PASSWORD` | envoi réel des e-mails d'invitation ; sans elles, l'envoi est simulé et tracé |
| `MBOARIDE_URL` | adresse publique utilisée dans les liens d'invitation |
