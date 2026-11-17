"""US04 · Demander un trajet, depuis l'application mobile.

L'écran de demande (carte de Douala, départ, arrivée, fenêtre d'arrivée, prix maximal,
confort) enregistre ici la demande ; les offres se lisent ensuite sur
`GET /api/moi/demandes/{id}/offres`, calculées par le moteur d'agents (routes/prix.py).
"""

from __future__ import annotations

from datetime import date, time

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, model_validator

from .. import lieux, moteur
from ..db import get_conn
from ..securite import utilisateur_courant

router = APIRouter(prefix="/api", tags=["US04 · Demande de trajet"])

# Zone de service, identique à l'application et à l'API Node.
ZONE = {"lat": (3.85, 4.25), "lon": (9.45, 10.0)}


class Lieu(BaseModel):
    libelle: str = Field(min_length=1, max_length=120)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class NouvelleDemande(BaseModel):
    depart: Lieu
    arrivee: Lieu
    arrivee_au_plus_tot: time
    arrivee_au_plus_tard: time
    date_trajet: date
    prix_max_fcfa: int = Field(ge=100, le=20000)
    clim_obligatoire: bool = False
    cercle_max: str | None = Field(default=None, pattern="^(organisation|partenaires|public)$")
    mode_reservation: str | None = Field(default=None, pattern="^(manuel|autonome)$")

    @model_validator(mode="after")
    def _coherence(self):
        if self.arrivee_au_plus_tot >= self.arrivee_au_plus_tard:
            raise ValueError("La fin de la fenêtre d'arrivée doit suivre son début")
        return self


def _dans_la_zone(l: Lieu) -> bool:
    return ZONE["lat"][0] <= l.lat <= ZONE["lat"][1] and ZONE["lon"][0] <= l.lon <= ZONE["lon"][1]


def cercle_par_defaut(conn: psycopg.Connection, u: dict) -> str:
    """Cercle le plus large que l'utilisateur accepte dans ses préférences (US02).

    Sans organisation, le seul cercle possible est le public : sinon aucune offre
    ne pourrait jamais lui être proposée.
    """
    a_une_org = conn.execute("SELECT 1 FROM appartenance WHERE id_utilisateur = %s",
                             (u["id_utilisateur"],)).fetchone()
    if not a_une_org or u["accepte_public"]:
        return "public"
    return "partenaires" if u["accepte_partenaires"] else "organisation"


@router.post("/demandes", status_code=201)
def creer(body: NouvelleDemande, u: dict = Depends(utilisateur_courant),
          conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if not (_dans_la_zone(body.depart) and _dans_la_zone(body.arrivee)):
        raise HTTPException(422, "Départ ou arrivée hors de la zone de service (Douala et environs)")
    if moteur.distance_km(body.depart.lat, body.depart.lon, body.arrivee.lat, body.arrivee.lon) < 0.3:
        raise HTTPException(422, "Le départ et l'arrivée sont trop proches")
    if body.date_trajet < date.today():
        raise HTTPException(422, "La date du trajet est déjà passée")
    org = conn.execute("SELECT id_organisation FROM appartenance WHERE id_utilisateur = %s "
                       "ORDER BY id_organisation LIMIT 1", (u["id_utilisateur"],)).fetchone()
    d = conn.execute(
        """INSERT INTO demande (id_demandeur, id_organisation, type_trajet, depart_libelle, depart_lat, depart_lon,
               arrivee_libelle, arrivee_lat, arrivee_lon, arrivee_au_plus_tot, arrivee_au_plus_tard,
               date_unique, prix_max_fcfa, clim_obligatoire, mode_reservation, cercle_max)
           VALUES (%s, %s, 'urbain', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
           RETURNING id_demande, statut, cercle_max""",
        (u["id_utilisateur"], org["id_organisation"] if org else None,
         body.depart.libelle, round(body.depart.lat, 6), round(body.depart.lon, 6),
         body.arrivee.libelle, round(body.arrivee.lat, 6), round(body.arrivee.lon, 6),
         body.arrivee_au_plus_tot, body.arrivee_au_plus_tard, body.date_trajet, body.prix_max_fcfa,
         body.clim_obligatoire or u["souhaite_clim"],
         body.mode_reservation or u["mode_reservation"],
         body.cercle_max or cercle_par_defaut(conn, u))).fetchone()
    return {"id": d["id_demande"], "id_demande": d["id_demande"], "status": d["statut"],
            "cercle_max": d["cercle_max"]}


@router.get("/lieux", tags=["Lieux"])
def chercher_lieux(q: str = "") -> list[dict]:
    """Quartiers de Douala et villes connus, pour l'autocomplétion."""
    return lieux.suggestions(q)


@router.get("/lieux/distance", tags=["Lieux"])
def distance(de: str, a: str, interurbain: bool | None = None) -> dict:
    """Distance routière estimée entre deux lieux connus, avec l'estimateur du moteur.

    Sans précision, le trajet est interurbain quand les deux lieux sont des villes.
    """
    p, q = lieux.trouver(de), lieux.trouver(a)
    if p is None or q is None:
        raise HTTPException(422, f"Lieu inconnu : {de if p is None else a}")
    if interurbain is None:
        interurbain = p[0] in lieux.VILLES and q[0] in lieux.VILLES
    return {"de": p[0], "a": q[0], "distance_km": round(moteur.distance_km(p[1], p[2], q[1], q[2], interurbain), 2)}
