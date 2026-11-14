"""US02 · Renseigner mes exigences de confort et mon cercle de confiance.

Critères d'acceptation :
  1. L'utilisateur lit et modifie ses souhaits de confort (climatisation, non-fumeur,
     silence), son prix maximal par défaut, son cercle, son mode et sa priorité.
  2. Le cercle est emboîté : choisir « public » inclut les partenaires ; les collègues
     sont toujours inclus.
  3. Les valeurs hors bornes sont refusées avec un message clair (422).
  4. Les préférences sont traduites dans les paramètres du moteur multi-agents (cercles
     autorisés, confort souhaité, prix maximal, mode, poids du score) et servent à
     pré-remplir le formulaire de demande de trajet (US04).
"""

from __future__ import annotations

from typing import Literal

import psycopg
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..db import get_conn
from ..securite import utilisateur_courant

router = APIRouter(prefix="/api/moi", tags=["US02 · Préférences"])

Cercle = Literal["organisation", "partenaires", "public"]


class Confort(BaseModel):
    climatisation: bool = False
    non_fumeur: bool = False
    silence: bool = False


class Preferences(BaseModel):
    confort: Confort
    prix_max_fcfa: int = Field(ge=50, le=20000)
    cercle: Cercle
    mode: Literal["manuel", "autonome"]
    priorite: Literal["heure", "prix"]


def lire(u: dict) -> Preferences:
    cercle = "public" if u["accepte_public"] else (
        "partenaires" if u["accepte_partenaires"] else "organisation")
    return Preferences(
        confort=Confort(climatisation=u["souhaite_clim"], non_fumeur=u["souhaite_non_fumeur"],
                        silence=u["souhaite_silence"]),
        prix_max_fcfa=u["prix_max_defaut_fcfa"], cercle=cercle,
        mode=u["mode_reservation"], priorite=u["priorite"])


def vers_moteur(p: Preferences) -> dict:
    """Paramètres de la demande envoyée au moteur multi-agents (model.Request)."""
    niveaux = {"organisation": (0,), "partenaires": (0, 1), "public": (0, 1, 2)}[p.cercle]
    souhaits = {k for k, v in (("clim", p.confort.climatisation),
                               ("non_fumeur", p.confort.non_fumeur),
                               ("silence", p.confort.silence)) if v}
    return {"levels": niveaux, "comfort_wanted": sorted(souhaits),
            "max_price": p.prix_max_fcfa, "mode": "auto" if p.mode == "autonome" else "manuel",
            "priority": p.priorite}


@router.get("/preferences")
def get_preferences(u: dict = Depends(utilisateur_courant)) -> dict:
    p = lire(u)
    return {**p.model_dump(), "parametres_moteur": vers_moteur(p),
            "maj_le": u["preferences_maj_le"]}


@router.put("/preferences")
def put_preferences(p: Preferences, u: dict = Depends(utilisateur_courant),
                    conn: psycopg.Connection = Depends(get_conn)) -> dict:
    row = conn.execute(
        """UPDATE utilisateur SET souhaite_clim = %s, souhaite_non_fumeur = %s,
               souhaite_silence = %s, prix_max_defaut_fcfa = %s,
               accepte_partenaires = %s, accepte_public = %s,
               mode_reservation = %s, priorite = %s, preferences_maj_le = now()
           WHERE id_utilisateur = %s RETURNING *""",
        (p.confort.climatisation, p.confort.non_fumeur, p.confort.silence, p.prix_max_fcfa,
         p.cercle != "organisation", p.cercle == "public", p.mode, p.priorite,
         u["id_utilisateur"])).fetchone()
    q = lire(row)
    return {**q.model_dump(), "parametres_moteur": vers_moteur(q), "maj_le": row["preferences_maj_le"]}
