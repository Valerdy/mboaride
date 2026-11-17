"""Mes trajets : les trajets que le passager a choisis, à confirmer ou confirmés.

Choisir une offre retient la place (réservation) et ouvre un paiement en attente ; le
trajet n'est confirmé qu'une fois payé par Mobile Money (US10). Le conducteur ne voit
dans son équipage que les passagers qui ont payé. Tant qu'il n'est pas payé, le passager
peut renoncer au trajet : la place est libérée et sa demande redevient ouverte.
"""

from __future__ import annotations

import psycopg
from fastapi import APIRouter, Depends, HTTPException

from ..db import get_conn
from ..notifications import notifier
from ..securite import utilisateur_courant
from .paiement import MAX_TENTATIVES, OPERATEURS, rembourser_ou_annuler

router = APIRouter(prefix="/api/moi", tags=["Mes trajets"])


def etat(r: dict) -> str:
    """a_confirmer (place retenue, paiement à faire), confirme (payé), annule ou termine."""
    if r["statut"] == "annulee":
        return "annule"
    if r["statut"] == "terminee":
        return "termine"
    return "confirme" if r["statut_paiement"] == "reussi" else "a_confirmer"


@router.get("/reservations")
def mes_reservations(u: dict = Depends(utilisateur_courant),
                     conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    rows = conn.execute(
        """SELECT r.id_reservation, r.statut, r.date_trajet, r.heure_prise_en_charge, r.heure_arrivee_estimee,
                  r.prix_fcfa, r.niveau_cercle, d.depart_libelle, d.arrivee_libelle,
                  t.id_trajet, uc.prenom AS conducteur, v.marque_modele, v.immatriculation,
                  p.id_paiement, p.statut AS statut_paiement, p.operateur, p.telephone_payeur,
                  p.reference_transaction, p.tentatives, p.motif_echec
             FROM reservation r JOIN demande d USING (id_demande)
             JOIN trajet t ON t.id_trajet = r.id_trajet
             JOIN vehicule v ON v.id_vehicule = t.id_vehicule
             JOIN utilisateur uc ON uc.id_utilisateur = t.id_conducteur
             LEFT JOIN paiement p ON p.id_reservation = r.id_reservation
            WHERE d.id_demandeur = %s
            ORDER BY (r.statut = 'confirmee' AND p.statut IS DISTINCT FROM 'reussi') DESC,
                     r.date_trajet DESC, r.heure_prise_en_charge, r.id_reservation DESC
            LIMIT 50""", (u["id_utilisateur"],)).fetchall()
    return [{
        "id_reservation": r["id_reservation"], "etat": etat(r), "date_trajet": r["date_trajet"],
        "trajet": f"{r['depart_libelle']} → {r['arrivee_libelle']}",
        "prise_en_charge": r["heure_prise_en_charge"].strftime("%H:%M"),
        "arrivee": r["heure_arrivee_estimee"].strftime("%H:%M"),
        "prix_fcfa": r["prix_fcfa"], "cercle": r["niveau_cercle"],
        "conducteur": r["conducteur"], "vehicule": f"{r['marque_modele']} · {r['immatriculation']}",
        "id_paiement": r["id_paiement"], "statut_paiement": r["statut_paiement"],
        "operateur": OPERATEURS.get(r["operateur"] or "", {}).get("libelle"),
        "telephone": r["telephone_payeur"], "reference": r["reference_transaction"],
        "tentatives_restantes": MAX_TENTATIVES - (r["tentatives"] or 0), "motif_echec": r["motif_echec"],
    } for r in rows]


@router.post("/reservations/{id_reservation}/annulation")
def renoncer(id_reservation: int, u: dict = Depends(utilisateur_courant),
             conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Le passager renonce à un trajet choisi : place libérée, demande rouverte, paiement remboursé."""
    r = conn.execute(
        """SELECT r.*, d.id_demandeur, t.id_conducteur, d.depart_libelle, d.arrivee_libelle
             FROM reservation r JOIN demande d USING (id_demande) JOIN trajet t ON t.id_trajet = r.id_trajet
            WHERE r.id_reservation = %s""", (id_reservation,)).fetchone()
    if r is None or r["id_demandeur"] != u["id_utilisateur"]:
        raise HTTPException(404, "Trajet introuvable")
    if r["statut"] != "confirmee":
        raise HTTPException(409, "Ce trajet est déjà annulé ou terminé")
    paiement = rembourser_ou_annuler(conn, id_reservation, u["id_utilisateur"])
    conn.execute("UPDATE reservation SET statut = 'annulee' WHERE id_reservation = %s", (id_reservation,))
    conn.execute("UPDATE demande SET statut = 'ouverte' WHERE id_demande = %s", (r["id_demande"],))
    if paiement == "rembourse":   # le conducteur comptait sur ce passager
        notifier(conn, r["id_conducteur"], "annulation",
                 f"{u['prenom']} a annulé sa place du {r['date_trajet']:%d/%m} "
                 f"({r['depart_libelle']} → {r['arrivee_libelle']}).")
    return {"id_reservation": id_reservation, "etat": "annule", "paiement": paiement}
