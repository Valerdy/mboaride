"""Annulation d'un trajet par le conducteur et réaffectation des passagers (scénario SR-47).

  1. Le conducteur annule une date de son trajet ; les réservations de ce jour sont annulées,
     les paiements réussis remboursés, les passagers prévenus.
  2. Pour chaque passager, les autres offres compatibles ce jour-là sont recalculées
     (le trajet annulé est exclu).
  3. En mode autonome, le passager est réaffecté automatiquement à la meilleure offre selon
     sa priorité (heure ou prix) ; en mode manuel, il reçoit les offres et choisit.
  4. S'il n'existe aucune offre, la demande repasse « ouverte » et le passager est prévenu.
"""

from __future__ import annotations

from datetime import date

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .. import moteur
from ..db import get_conn
from ..notifications import notifier
from ..securite import utilisateur_courant
from .paiement import rembourser_ou_annuler
from .prix import offres_valides, reserver

router = APIRouter(prefix="/api", tags=["SR-47 · Annulation et réaffectation"])


class Annulation(BaseModel):
    date_trajet: date
    motif: str | None = Field(default=None, max_length=200)


def _minutes(hhmm: str) -> int:
    h, m = hhmm.split(":")[:2]
    return int(h) * 60 + int(m)


def meilleure_offre(d: dict, offres: list[dict]) -> dict | None:
    ok = [o for o in offres if o["confirmable"]]
    if not ok:
        return None
    if d.get("priorite") == "prix":
        return min(ok, key=lambda o: (o["prix_fcfa"], o["id_trajet"]))
    cible = (moteur.minutes(d["arrivee_au_plus_tot"]) + moteur.minutes(d["arrivee_au_plus_tard"])) / 2
    return min(ok, key=lambda o: (abs(_minutes(o["arrivee_estimee"]) - cible), o["prix_fcfa"], o["id_trajet"]))


@router.post("/trajets/{id_trajet}/annulations")
def annuler(id_trajet: int, body: Annulation, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    t = conn.execute("SELECT * FROM trajet WHERE id_trajet = %s", (id_trajet,)).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    if t["id_conducteur"] != u["id_utilisateur"]:
        raise HTTPException(403, "Seul le conducteur peut annuler son trajet")
    if conn.execute("SELECT 1 FROM indisponibilite_trajet WHERE id_trajet = %s AND date_trajet = %s",
                    (id_trajet, body.date_trajet)).fetchone():
        raise HTTPException(409, "Ce trajet est déjà annulé pour cette date")
    conn.execute("INSERT INTO indisponibilite_trajet (id_trajet, date_trajet, motif) VALUES (%s, %s, %s)",
                 (id_trajet, body.date_trajet, body.motif))
    touchees = conn.execute(
        """UPDATE reservation SET statut = 'annulee'
            WHERE id_trajet = %s AND date_trajet = %s AND statut = 'confirmee'
        RETURNING id_reservation, id_demande""", (id_trajet, body.date_trajet)).fetchall()

    resultats = []
    for r in touchees:
        d = conn.execute(
            """SELECT d.*, us.priorite, us.prenom FROM demande d
                 JOIN utilisateur us ON us.id_utilisateur = d.id_demandeur
                WHERE d.id_demande = %s""", (r["id_demande"],)).fetchone()
        notifier(conn, d["id_demandeur"], "annulation",
                 f"Votre conducteur a annulé le trajet du {body.date_trajet:%d/%m}"
                 + (f" ({body.motif})" if body.motif else "") + ".")
        paiement = rembourser_ou_annuler(conn, r["id_reservation"], d["id_demandeur"])
        offres = offres_valides(conn, d, exclure={id_trajet}, jour=body.date_trajet)
        res = {"id_demande": d["id_demande"], "passager": d["prenom"], "mode": d["mode_reservation"],
               "paiement": paiement, "offres_disponibles": sum(o["confirmable"] for o in offres)}
        choix = meilleure_offre(d, offres) if d["mode_reservation"] == "autonome" else None
        if choix:
            nouvelle = reserver(conn, d, choix, body.date_trajet)
            notifier(conn, d["id_demandeur"], "reaffectation",
                     f"Réaffecté automatiquement : {choix['conducteur']} vous prend à "
                     f"{choix['prise_en_charge']}, arrivée {choix['arrivee_estimee']}, "
                     f"{choix['prix_fcfa']} FCFA (paiement à effectuer).")
            res.update(reaffecte=True, nouveau_conducteur=choix["conducteur"],
                       id_reservation=nouvelle["id_reservation"], prix_fcfa=choix["prix_fcfa"])
        elif res["offres_disponibles"]:
            if d["date_unique"]:
                conn.execute("UPDATE demande SET statut = 'ouverte' WHERE id_demande = %s", (d["id_demande"],))
            notifier(conn, d["id_demandeur"], "offres",
                     f"{res['offres_disponibles']} autre(s) offre(s) disponible(s) pour le "
                     f"{body.date_trajet:%d/%m} : choisissez dans l'onglet Prix et confirmation.")
            res.update(reaffecte=False)
        else:
            if d["date_unique"]:
                conn.execute("UPDATE demande SET statut = 'ouverte' WHERE id_demande = %s", (d["id_demande"],))
            notifier(conn, d["id_demandeur"], "offres",
                     f"Aucune autre offre pour le {body.date_trajet:%d/%m} pour l'instant : "
                     f"votre demande reste ouverte et vous serez prévenu.")
            res.update(reaffecte=False)
        resultats.append(res)
    return {"id_trajet": id_trajet, "date_trajet": body.date_trajet,
            "reservations_annulees": len(touchees), "passagers": resultats}


@router.get("/moi/notifications")
def mes_notifications(marquer: bool = True, u: dict = Depends(utilisateur_courant),
                      conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    rows = conn.execute(
        "SELECT * FROM notification WHERE id_utilisateur = %s ORDER BY cree_le DESC, id_notification DESC "
        "LIMIT 20", (u["id_utilisateur"],)).fetchall()
    if marquer:
        conn.execute("UPDATE notification SET lue = TRUE WHERE id_utilisateur = %s AND NOT lue",
                     (u["id_utilisateur"],))
    return rows


@router.get("/moi/trajets")
def mes_trajets(u: dict = Depends(utilisateur_courant),
                conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Trajets du conducteur et leurs réservations à venir, pour pouvoir annuler une date."""
    return conn.execute(
        """SELECT t.id_trajet, t.depart_libelle, t.arrivee_libelle, to_char(t.heure_depart, 'HH24:MI') heure,
                  r.date_trajet, count(r.*) AS passagers
             FROM trajet t LEFT JOIN reservation r ON r.id_trajet = t.id_trajet AND r.statut = 'confirmee'
            WHERE t.id_conducteur = %s AND t.statut = 'actif'
            GROUP BY t.id_trajet, r.date_trajet ORDER BY t.id_trajet, r.date_trajet""",
        (u["id_utilisateur"],)).fetchall()
