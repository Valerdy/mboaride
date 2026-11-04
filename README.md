# MboaRide

Plateforme web de covoiturage organisé pour le Cameroun (ville pilote : Douala).
Un système multi-agents forme les équipages : chaque conducteur et chaque passager
est représenté par un agent qui négocie trajet, horaire, prix et confort, puis
renégocie en cas d'imprévu.

Projet Smart Realization - UCAC-ICAM.

## Modes de fonctionnement
- **Autonome** : la plateforme forme l'équipage et réserve seule.
- **Manuel** : la plateforme propose les meilleures correspondances, l'utilisateur décide.

## Structure du dépôt
```
backend/    API (FastAPI), base de données, authentification, itinéraires
agents/     Système multi-agents (conducteur, passager, organisation, coordinateur)
frontend/   Application web responsive (carte de Douala)
docs/       Document de vision, décisions d'architecture, menaces de sécurité
scripts/    Scripts utilitaires
.github/    Modèles de PR et d'issues, intégration continue
```

## Démarrage rapide

### Prérequis
Python 3.11+, Node.js 20+, Git.

### Backend
```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows : .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```
L'API répond sur http://127.0.0.1:8000 (documentation : `/docs`).

### Agents
```bash
cd agents
pip install -r requirements.txt
pytest
```

### Frontend
Voir `frontend/README.md`.

## Équipe
| Membre | Rôle |
|---|---|
| NGUIMBI Valerdy | Chef de projet |
| KOUEDEU Cindy | à définir |
| DJEGUE Wilfried | à définir |
| NGAPEPOUE Karl | à définir |

## Contribuer
Lire [CONTRIBUTING.md](CONTRIBUTING.md) avant toute modification. Personne ne pousse directement sur `main`.
