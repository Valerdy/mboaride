"""US22 · Réserver une place dans un voyage interurbain plusieurs jours à l'avance.

Critères d'acceptation :
  1. Le voyageur voit les voyages interurbains publiés pour une date future, avec les
     places restantes, les points de montée et le prix de la place.
  2. Le prix vient du moteur multi-agents, comme pour les trajets urbains : distance
     partagée, consommation du véhicule, péage réparti entre les occupants, puis
     commission de la plateforme sur l'interurbain.
  3. Réserver crée la demande correspondante et la réservation ; le point de montée
     choisi devient le départ de la demande.
  4. Si le prix a changé depuis l'affichage, rien n'est réservé et le nouveau prix est
     renvoyé (409), comme à la confirmation d'un trajet urbain (US09).
  5. Un parent peut réserver pour l'un de ses élèves ; sans autorisation parentale
     active, la base refuse la réservation (409).
"""

from __future__ import annotations

from datetime import date as Date, time as Time, timedelta

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .. import moteur
from ..db import get_conn
from ..securite import utilisateur_courant
from .prix import Refus, evaluer, places_restantes, reserver

router = APIRouter(prefix="/api", tags=["US22 · Voyages interurbains"])

# Fenêtre d'arrivée laissée au moteur pour un voyage interurbain : la durée dépend de
# la distance, on accepte donc une arrivée entre 30 minutes et 12 heures après le départ.
FENETRE_MIN_H, FENETRE_MAX_H = 0.5, 12.0


class Reservation(BaseModel):
    id_point_depart: int
    date_trajet: Date
    id_eleve: int | None = None
    nb_places: int = Field(default=1, ge=1, le=8, description="Places réservées ensemble")
    prix_annonce_fcfa: int | None = Field(
        default=None, description="Prix total affiché au voyageur (places comprises) ; un écart renvoie un 409")


def _voyage(conn: psycopg.Connection, id_trajet: int) -> dict:
    row = conn.execute(
        """SELECT t.*, v.conso_l_100km, v.climatise, v.non_fumeur, u.prenom AS conducteur_prenom
             FROM trajet t JOIN vehicule v USING (id_vehicule)
             JOIN utilisateur u ON u.id_utilisateur = t.id_conducteur
            WHERE t.id_trajet = %s AND t.type_trajet = 'interurbain' AND t.statut = 'actif'""",
        (id_trajet,)).fetchone()
    if row is None:
        raise HTTPException(404, "Voyage interurbain introuvable")
    return row


def _points(conn: psycopg.Connection, id_trajet: int) -> list[dict]:
    return conn.execute(
        """SELECT id_point, ordre_passage, libelle, lat, lon, heure_passage
             FROM point_depart WHERE id_trajet = %s ORDER BY ordre_passage""",
        (id_trajet,)).fetchall()


def _demande_virtuelle(voyage: dict, point: dict | None, jour: Date, id_demandeur: int,
                       nb_places: int = 1) -> dict:
    """Demande telle qu'elle sera enregistrée : du point de montée à l'arrivée du voyage."""
    depart = point["heure_passage"] if point else voyage["heure_depart"]
    base = depart.hour * 60 + depart.minute
    tot = min(23 * 60 + 58, int(base + FENETRE_MIN_H * 60))
    tard = min(23 * 60 + 59, int(base + FENETRE_MAX_H * 60))
    if tard <= tot:
        tot, tard = 23 * 60 + 58, 23 * 60 + 59
    return {
        "id_demande": None, "id_demandeur": id_demandeur, "id_eleve": None,
        "id_organisation": None, "type_trajet": "interurbain", "nb_places": nb_places,
        "depart_libelle": point["libelle"] if point else voyage["depart_libelle"],
        "depart_lat": point["lat"] if point else voyage["depart_lat"],
        "depart_lon": point["lon"] if point else voyage["depart_lon"],
        "arrivee_libelle": voyage["arrivee_libelle"],
        "arrivee_lat": voyage["arrivee_lat"], "arrivee_lon": voyage["arrivee_lon"],
        "arrivee_au_plus_tot": Time(tot // 60, tot % 60),
        "arrivee_au_plus_tard": Time(tard // 60, tard % 60),
        "date_unique": jour, "jours_semaine": None,
        "prix_max_fcfa": 10_000_000, "clim_obligatoire": False,
        "mode_reservation": "manuel", "cercle_max": "public", "statut": "ouverte",
    }


def _prix_place(conn: psycopg.Connection, voyage: dict, point: dict | None,
                jour: Date, id_demandeur: int) -> int:
    """Prix d'une place, calculé par le moteur : le même pour tous les voyageurs du voyage."""
    virtuelle = _demande_virtuelle(voyage, point, jour, id_demandeur)
    occupants = voyage["places_offertes"] - places_restantes(conn, voyage, jour)
    detail = moteur.detail_prix(moteur.driver_from_row(voyage),
                               moteur.request_from_row(virtuelle),
                               moteur.NIVEAU_CODE["public"], places_reservees=occupants)
    return detail.prix_fcfa


def _circule(voyage: dict, jour: Date) -> bool:
    if voyage["date_unique"] is not None:
        return voyage["date_unique"] == jour
    return voyage["jours_semaine"][jour.weekday()] == "1"


@router.get("/voyages")
def voyages(date: Date | None = None, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Voyages interurbains publiés pour cette date (demain par défaut)."""
    cherchee = date or Date.today() + timedelta(days=1)
    rows = conn.execute(
        """SELECT t.*, v.conso_l_100km, v.climatise, v.non_fumeur, u.prenom AS conducteur_prenom
             FROM trajet t JOIN vehicule v USING (id_vehicule)
             JOIN utilisateur u ON u.id_utilisateur = t.id_conducteur
            WHERE t.type_trajet = 'interurbain' AND t.statut = 'actif'
            ORDER BY t.heure_depart, t.id_trajet""").fetchall()
    resultat = []
    for voyage in rows:
        if not _circule(voyage, cherchee):
            continue
        if conn.execute("SELECT 1 FROM indisponibilite_trajet WHERE id_trajet = %s AND date_trajet = %s",
                        (voyage["id_trajet"], cherchee)).fetchone():
            continue
        points = _points(conn, voyage["id_trajet"])
        confort = ([m for m, actif in (("Climatisation", voyage["climatise"]),
                                       ("Non-fumeur", voyage["non_fumeur"])) if actif])
        resultat.append({
            "id_trajet": voyage["id_trajet"], "conducteur": voyage["conducteur_prenom"],
            "depart_libelle": voyage["depart_libelle"], "arrivee_libelle": voyage["arrivee_libelle"],
            "date_trajet": cherchee.isoformat(),
            "heure_depart": voyage["heure_depart"].strftime("%H:%M"),
            "places_restantes": places_restantes(conn, voyage, cherchee),
            "prix_fcfa": _prix_place(conn, voyage, points[0] if points else None,
                                     cherchee, u["id_utilisateur"]),
            "peage_fcfa": voyage["peage_fcfa"],
            "confort": confort,
            "points_depart": [{"id_point": p["id_point"], "libelle": p["libelle"],
                               "heure": p["heure_passage"].strftime("%H:%M")} for p in points],
        })
    return resultat


@router.post("/voyages/{id_trajet}/reservations", status_code=201)
def reserver_place(id_trajet: int, body: Reservation, u: dict = Depends(utilisateur_courant),
                   conn: psycopg.Connection = Depends(get_conn)) -> dict:
    voyage = _voyage(conn, id_trajet)
    jour = body.date_trajet
    if not _circule(voyage, jour):
        raise HTTPException(422, "Ce voyage ne circule pas à cette date")
    if jour < Date.today():
        raise HTTPException(422, "Cette date est passée")
    points = _points(conn, id_trajet)
    point = next((p for p in points if p["id_point"] == body.id_point_depart), None)
    if point is None and points:
        raise HTTPException(422, "Point de montée inconnu pour ce voyage")
    if body.id_eleve is not None and not conn.execute(
            "SELECT 1 FROM compte_eleve WHERE id_eleve = %s AND id_parent = %s",
            (body.id_eleve, u["id_utilisateur"])).fetchone():
        raise HTTPException(404, "Élève introuvable dans vos comptes")

    virtuelle = _demande_virtuelle(voyage, point, jour, u["id_utilisateur"], body.nb_places)
    prix = _prix_place(conn, voyage, point, jour, u["id_utilisateur"])
    if body.prix_annonce_fcfa is not None and body.prix_annonce_fcfa != prix * body.nb_places:
        raise HTTPException(409, {"message": "Le prix a changé depuis l'affichage, merci de "
                                             "valider le nouveau prix.",
                                  "nouveau_prix_fcfa": prix * body.nb_places, "detail": []})

    d = conn.execute(
        """INSERT INTO demande (id_demandeur, id_eleve, type_trajet,
               depart_libelle, depart_lat, depart_lon, arrivee_libelle, arrivee_lat, arrivee_lon,
               arrivee_au_plus_tot, arrivee_au_plus_tard, date_unique, prix_max_fcfa,
               mode_reservation, cercle_max, statut, nb_places)
           VALUES (%(dem)s, %(ele)s, 'interurbain', %(dl)s, %(dla)s, %(dlo)s, %(al)s, %(ala)s, %(alo)s,
                   %(tot)s, %(tard)s, %(jour)s, %(prix)s, 'manuel', 'public', 'ouverte', %(nb)s)
           RETURNING *""",
        {"dem": u["id_utilisateur"], "ele": body.id_eleve,
         "dl": virtuelle["depart_libelle"], "dla": virtuelle["depart_lat"],
         "dlo": virtuelle["depart_lon"], "al": virtuelle["arrivee_libelle"],
         "ala": virtuelle["arrivee_lat"], "alo": virtuelle["arrivee_lon"],
         "tot": virtuelle["arrivee_au_plus_tot"], "tard": virtuelle["arrivee_au_plus_tard"],
         "jour": jour, "prix": prix, "nb": body.nb_places}).fetchone()
    try:
        e = evaluer(conn, d, voyage, jour)
    except Refus:
        conn.execute("DELETE FROM demande WHERE id_demande = %s", (d["id_demande"],))
        raise
    if not e["horaires_compatibles"]:
        conn.execute("DELETE FROM demande WHERE id_demande = %s", (d["id_demande"],))
        raise HTTPException(422, "Le moteur n'a pas pu placer cette montée dans l'itinéraire")
    reservation = reserver(conn, d, e, jour)
    return {**reservation, "id_demande": d["id_demande"], "id_trajet": id_trajet,
            "point_depart": virtuelle["depart_libelle"],
            "heure_depart": e["prise_en_charge"], "date_trajet": jour.isoformat(),
            "id_eleve": body.id_eleve}
