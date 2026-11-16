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

# Hypothèses du bilan développement durable (mêmes valeurs que le bilan).
CONSO_REFERENCE_L100 = 8.0      # voiture que le passager aurait prise seul
CO2_KG_PAR_LITRE = 2.31         # combustion d'un litre d'essence
PART_CONDUCTEURS_SEULS = 1 / 3  # scénario prudent : 1 passager sur 3 aurait conduit seul
PRIX_TAXI_URBAIN_FCFA = 600     # taxi avec changement, document de vision
PRIX_CAR_INTERURBAIN_FCFA = 3500  # car classique Douala-Yaoundé

MAX_INVITATIONS_PAR_ENVOI = 200
MAX_RELANCES = 3
