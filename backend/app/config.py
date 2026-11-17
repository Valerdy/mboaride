"""Paramètres de l'API. Tout est surchargeable par variable d'environnement."""

from __future__ import annotations

import os
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent

# Le système multi-agents est le dossier voisin agents/ : ses règles de prix et son
# estimateur d'itinéraire sont réutilisés tels quels, pour qu'un seul calcul fasse foi.
AGENTS_DIR = Path(os.environ.get("MBOARIDE_AGENTS", RACINE.parent / "agents"))
if str(AGENTS_DIR) not in sys.path:
    sys.path.insert(0, str(AGENTS_DIR))

# Chaîne de connexion PostgreSQL (format libpq ou URL postgresql://…).
DSN = os.environ.get("MBOARIDE_DSN") or os.environ.get(
    "DATABASE_URL", "host=localhost port=5432 user=postgres dbname=mboaride")

# Serveur OSRM pour les vrais itinéraires. Vide : l'estimateur déterministe des agents
# suffit, et c'est ce que font les tests et le banc de mesure. Renseigné (par exemple
# http://localhost:5000, le conteneur OSRM de l'API Node) : les détours sont mesurés sur
# le réseau routier, avec repli automatique sur l'estimateur en cas de panne.
OSRM_URL = os.environ.get("MBOARIDE_OSRM_URL", "").strip()
OSRM_TIMEOUT_S = float(os.environ.get("MBOARIDE_OSRM_TIMEOUT_S", "3"))

# Pont avec l'API Node, qui porte l'authentification (US01). Même secret que son
# SECRET_KEY : l'API Python vérifie les jetons qu'elle émet, sans jamais en émettre.
# Vide : seul l'en-tête de démonstration X-Utilisateur identifie l'appelant.
SECRET_KEY = (os.environ.get("MBOARIDE_SECRET_KEY")
              or os.environ.get("SECRET_KEY") or "").strip()

# En-tête X-Utilisateur de la maquette. Mettre MBOARIDE_DEMO_AUTH=0 en déploiement réel :
# seul un jeton signé par l'API Node est alors accepté.
DEMO_AUTH = os.environ.get("MBOARIDE_DEMO_AUTH", "1") not in ("0", "false", "False")

# Hypothèses du bilan développement durable (mêmes valeurs que le bilan).
CONSO_REFERENCE_L100 = 8.0      # voiture que le passager aurait prise seul
CO2_KG_PAR_LITRE = 2.31         # combustion d'un litre d'essence
PART_CONDUCTEURS_SEULS = 1 / 3  # scénario prudent : 1 passager sur 3 aurait conduit seul
PRIX_TAXI_URBAIN_FCFA = 600     # taxi avec changement, document de vision
PRIX_CAR_INTERURBAIN_FCFA = 3500  # car classique Douala-Yaoundé

MAX_INVITATIONS_PAR_ENVOI = 200
MAX_RELANCES = 3
