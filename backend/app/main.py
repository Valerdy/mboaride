"""MboaRide · API des sprints 2 et 3 (US02, US09, US10, US13, US14, scénarios de démo).

    uvicorn app.main:app --reload        puis http://127.0.0.1:8000
    Documentation interactive de l'API :  http://127.0.0.1:8000/docs
"""

from __future__ import annotations

import psycopg
from fastapi import Depends, FastAPI

from .db import get_conn
from .routes import paiement, preferences, prix
from .securite import utilisateur_courant

app = FastAPI(title="MboaRide", version="0.3.0",
              description="Préférences (US02), prix avant confirmation (US09), paiement Mobile Money "
                          "simulé (US10), invitations et adoption (US13), économies et CO2 (US14), "
                          "annulation et réaffectation, scénarios de démonstration.")
app.include_router(preferences.router)
app.include_router(prix.router)
app.include_router(paiement.router)


@app.get("/health", tags=["Santé"])
def health() -> dict:
    return {"status": "ok"}


@app.get("/api/demo/utilisateurs", tags=["Démo"])
def utilisateurs_demo(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Comptes de démonstration (remplace l'écran de connexion US01 dans la maquette)."""
    return conn.execute(
        """SELECT u.id_utilisateur, u.prenom, u.nom, u.email,
                  bool_or(a.role = 'administrateur') AS administrateur,
                  (SELECT count(*) FROM demande d WHERE d.id_demandeur = u.id_utilisateur
                      AND d.statut = 'ouverte') AS demandes_ouvertes
             FROM utilisateur u LEFT JOIN appartenance a USING (id_utilisateur)
            GROUP BY u.id_utilisateur
           HAVING bool_or(a.role = 'administrateur')
               OR (SELECT count(*) FROM demande d WHERE d.id_demandeur = u.id_utilisateur
                      AND d.statut = 'ouverte') > 0
               OR u.id_utilisateur <= 9
            ORDER BY administrateur DESC NULLS LAST, demandes_ouvertes DESC, u.id_utilisateur
            LIMIT 14""").fetchall()


@app.get("/api/demo/utilisateur/{uid}", tags=["Démo"])
def utilisateur_demo(uid: int, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Pour basculer sur un compte qui n'est pas dans la liste (conducteur, nouvel inscrit)."""
    return conn.execute("SELECT id_utilisateur, prenom, nom, email FROM utilisateur WHERE id_utilisateur = %s",
                        (uid,)).fetchone() or {}


@app.get("/api/moi/demandes", tags=["Démo"])
def mes_demandes(u: dict = Depends(utilisateur_courant),
                 conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return conn.execute(
        """SELECT id_demande, depart_libelle, arrivee_libelle, type_trajet, statut, prix_max_fcfa,
                  to_char(arrivee_au_plus_tot, 'HH24:MI') AS arrivee_au_plus_tot,
                  to_char(arrivee_au_plus_tard, 'HH24:MI') AS arrivee_au_plus_tard,
                  date_unique, jours_semaine, cercle_max, mode_reservation
             FROM demande WHERE id_demandeur = %s
            ORDER BY (statut = 'ouverte') DESC, id_demande DESC""", (u["id_utilisateur"],)).fetchall()

