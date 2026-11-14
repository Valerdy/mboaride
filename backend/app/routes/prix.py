"""US09 · Connaître le prix avant de confirmer.

Critères d'acceptation :
  1. Avant toute confirmation, le passager voit le prix total et son détail : distance,
     carburant, péage éventuel, nombre d'occupants, commission éventuelle, arrondi.
  2. Le prix est calculé par la même fonction que celle du moteur multi-agents.
  3. Le prix est comparé au prix maximal de la demande ; une offre trop chère n'est
     pas confirmable.
  4. La confirmation porte le prix annoncé : s'il a changé entre l'affichage et la
     confirmation, la réservation est refusée (409) avec le nouveau prix, jamais
     débitée en silence.
  5. Une offre hors du cercle du passager ou que le conducteur n'ouvre pas à ce cercle
     n'est pas proposée.

Compléments (SR-47, scénarios « aucune offre » et « élargissement ») :
  6. Quand aucune offre ne convient, le passager voit pourquoi (cercle, horaires, budget,
     confort, trajet complet ou annulé ce jour-là) et ce qui débloquerait la situation.
  7. Il peut élargir le cercle de sa demande (organisation, puis partenaires, puis public)
     et voit aussitôt les offres qui s'ajoutent.
"""

from __future__ import annotations

from datetime import date

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .. import moteur
from ..db import get_conn
from ..securite import utilisateur_courant

router = APIRouter(prefix="/api", tags=["US09 · Prix avant confirmation"])


class Refus(HTTPException):
    """Offre écartée, avec un code exploitable par le diagnostic « aucune offre »."""

    def __init__(self, code: str, message: str, status: int = 422):
        super().__init__(status, message)
        self.code = code


MOTIFS = {
    "cercle": "hors de votre cercle de confiance",
    "ferme": "conducteur qui n'ouvre pas son trajet à votre cercle",
    "type": "type de trajet différent",
    "confort": "confort obligatoire non respecté",
    "indisponible": "trajet annulé ce jour-là par le conducteur",
    "complet": "voiture déjà complète ce jour-là",
    "horaires": "arrivée hors de votre fenêtre ou détour trop long",
    "budget": "prix au-dessus de votre maximum",
}


class Estimation(BaseModel):
    id_demande: int
    id_trajet: int


class Confirmation(Estimation):
    date_trajet: date
    prix_annonce_fcfa: int = Field(ge=0)


class Elargissement(BaseModel):
    cercle_max: str = Field(pattern="^(organisation|partenaires|public)$")


def _demande(conn, id_demande: int, u: dict) -> dict:
    d = conn.execute("SELECT * FROM demande WHERE id_demande = %s", (id_demande,)).fetchone()
    if d is None:
        raise HTTPException(404, "Demande introuvable")
    if d["id_demandeur"] != u["id_utilisateur"]:
        raise HTTPException(403, "Cette demande appartient à un autre utilisateur")
    return d


def _trajet(conn, id_trajet: int) -> dict:
    t = conn.execute(
        """SELECT t.*, v.conso_l_100km, v.climatise, v.non_fumeur,
                  u.prenom AS conducteur_prenom
             FROM trajet t JOIN vehicule v USING (id_vehicule)
             JOIN utilisateur u ON u.id_utilisateur = t.id_conducteur
            WHERE t.id_trajet = %s""", (id_trajet,)).fetchone()
    if t is None or t["statut"] != "actif":
        raise HTTPException(404, "Trajet introuvable ou inactif")
    return t


def niveau_cercle(conn, id_passager: int, id_conducteur: int) -> int:
    """0 si collègues, 1 si leurs organisations sont partenaires, 2 sinon."""
    meme = conn.execute(
        """SELECT 1 FROM appartenance a JOIN appartenance b USING (id_organisation)
            WHERE a.id_utilisateur = %s AND b.id_utilisateur = %s""",
        (id_passager, id_conducteur)).fetchone()
    if meme:
        return 0
    partenaires = conn.execute(
        """SELECT 1 FROM appartenance a, appartenance b, partenariat p
            WHERE a.id_utilisateur = %s AND b.id_utilisateur = %s
              AND ((p.id_organisation_a, p.id_organisation_b) = (a.id_organisation, b.id_organisation)
                OR (p.id_organisation_a, p.id_organisation_b) = (b.id_organisation, a.id_organisation))""",
        (id_passager, id_conducteur)).fetchone()
    return 1 if partenaires else 2


def places_restantes(conn, t: dict, jour: date) -> int:
    pris = conn.execute("SELECT count(*) n FROM reservation WHERE id_trajet = %s AND date_trajet = %s "
                        "AND statut = 'confirmee'", (t["id_trajet"], jour)).fetchone()["n"]
    return t["places_offertes"] - pris


def evaluer(conn, d: dict, t: dict, jour: date | None = None) -> dict:
    """Prix et horaires d'une offre. Lève Refus avec un code si l'offre n'est pas visible."""
    niveau = niveau_cercle(conn, d["id_demandeur"], t["id_conducteur"])
    max_demande = moteur.NIVEAU_CODE[d["cercle_max"]]
    if niveau > max_demande:
        raise Refus("cercle", f"Ce conducteur est hors de votre cercle "
                              f"({moteur.NIVEAUX[niveau]} au-delà de {d['cercle_max']})")
    if (niveau == 1 and not t["ouvert_partenaires"]) or (niveau == 2 and not t["ouvert_public"]):
        raise Refus("ferme", "Le conducteur n'ouvre pas ce trajet à votre cercle")
    if d["type_trajet"] != t["type_trajet"]:
        raise Refus("type", "Type de trajet différent (urbain ou interurbain)")

    drv, req = moteur.driver_from_row(t), moteur.request_from_row(d)
    if not req.confort_obligatoire <= drv.confort:
        raise Refus("confort", "Le véhicule ne respecte pas votre confort obligatoire (climatisation)")
    jour = jour or d["date_unique"]
    if jour is not None:
        if conn.execute("SELECT 1 FROM indisponibilite_trajet WHERE id_trajet = %s AND date_trajet = %s",
                        (t["id_trajet"], jour)).fetchone():
            raise Refus("indisponible", "Le conducteur a annulé ce trajet pour cette date", 409)
        if places_restantes(conn, t, jour) <= 0:
            raise Refus("complet", "La voiture est déjà complète pour cette date", 409)
    det = moteur.detail_prix(drv, req, niveau)
    h = moteur.horaires(drv, req)
    return {
        "id_demande": d["id_demande"], "id_trajet": t["id_trajet"],
        "conducteur": t["conducteur_prenom"],
        "trajet": f"{d['depart_libelle']} → {d['arrivee_libelle']}",
        "cercle": moteur.NIVEAUX[niveau],
        "prix_fcfa": det.prix_fcfa,
        "detail": det.lignes(),
        "distance_km": det.distance_km,
        "commission_fcfa": det.commission_fcfa,
        "prix_max_fcfa": d["prix_max_fcfa"],
        "dans_le_budget": det.prix_fcfa <= d["prix_max_fcfa"],
        "prise_en_charge": h[0] if h else None,
        "arrivee_estimee": h[1] if h else None,
        "detour_km": h[2] if h else None,
        "horaires_compatibles": h is not None,
        "confirmable": det.prix_fcfa <= d["prix_max_fcfa"] and h is not None,
        "formule": "distance × consommation / 100 × prix du litre (+ péage) ÷ occupants"
                   " (+ 10 % public/interurbain), arrondi au FCFA",
        "niveau": niveau,
    }


def offres_valides(conn, d: dict, exclure: set[int] = frozenset(), jour: date | None = None) -> list[dict]:
    ids = conn.execute("SELECT id_trajet FROM trajet WHERE statut = 'actif' AND id_conducteur <> %s "
                       "ORDER BY id_trajet", (d["id_demandeur"],)).fetchall()
    out = []
    for r in ids:
        if r["id_trajet"] in exclure:
            continue
        try:
            out.append(evaluer(conn, d, _trajet(conn, r["id_trajet"]), jour))
        except HTTPException:
            continue
    return sorted(out, key=lambda o: (not o["confirmable"], o["prix_fcfa"], o["id_trajet"]))


@router.post("/prix/estimation")
def estimation(body: Estimation, u: dict = Depends(utilisateur_courant),
               conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return evaluer(conn, _demande(conn, body.id_demande, u), _trajet(conn, body.id_trajet))


@router.get("/moi/demandes/{id_demande}/offres")
def offres(id_demande: int, u: dict = Depends(utilisateur_courant),
           conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Toutes les offres visibles pour une demande, avec leur prix, triées du moins cher."""
    return offres_valides(conn, _demande(conn, id_demande, u))


@router.get("/moi/demandes/{id_demande}/diagnostic")
def diagnostic(id_demande: int, u: dict = Depends(utilisateur_courant),
               conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Pourquoi les trajets existants ne conviennent pas, et ce qui débloquerait la demande."""
    d = _demande(conn, id_demande, u)
    ids = conn.execute("SELECT id_trajet FROM trajet WHERE statut = 'actif' AND id_conducteur <> %s "
                       "ORDER BY id_trajet", (d["id_demandeur"],)).fetchall()
    motifs: dict[str, int] = {}
    confirmables = 0
    budget_min = None
    for r in ids:
        try:
            e = evaluer(conn, d, _trajet(conn, r["id_trajet"]))
        except Refus as exc:
            motifs[exc.code] = motifs.get(exc.code, 0) + 1
            continue
        if not e["horaires_compatibles"]:
            motifs["horaires"] = motifs.get("horaires", 0) + 1
        elif not e["dans_le_budget"]:
            motifs["budget"] = motifs.get("budget", 0) + 1
            budget_min = min(budget_min or e["prix_fcfa"], e["prix_fcfa"])
        else:
            confirmables += 1

    suggestions = []
    actuel = moteur.NIVEAU_CODE[d["cercle_max"]]
    for niveau in range(actuel + 1, 3):
        cercle = moteur.NIVEAUX[niveau]
        n = sum(1 for o in offres_valides(conn, {**d, "cercle_max": cercle})
                if o["confirmable"] and o["niveau"] > actuel)
        if n:
            suggestions.append({"action": "elargir", "cercle_max": cercle,
                                "message": f"Élargir au cercle « {cercle} » ajoute {n} offre(s) confirmable(s)",
                                "offres_en_plus": n})
            break
    if budget_min:
        suggestions.append({"action": "budget", "prix_max_fcfa": budget_min,
                            "message": f"Avec un maximum de {budget_min} FCFA, une offre devient confirmable"})
    if motifs.get("horaires"):
        suggestions.append({"action": "fenetre",
                            "message": "Élargir votre fenêtre d'arrivée de 10 à 15 minutes peut rendre "
                                       "des trajets compatibles"})
    return {"id_demande": id_demande, "trajets_examines": len(ids), "offres_confirmables": confirmables,
            "motifs": [{"code": k, "libelle": MOTIFS[k], "trajets": v}
                       for k, v in sorted(motifs.items(), key=lambda kv: -kv[1])],
            "suggestions": suggestions}


@router.post("/moi/demandes/{id_demande}/elargir")
def elargir(id_demande: int, body: Elargissement, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    d = _demande(conn, id_demande, u)
    if moteur.NIVEAU_CODE[body.cercle_max] <= moteur.NIVEAU_CODE[d["cercle_max"]]:
        raise HTTPException(422, "Le nouveau cercle doit être plus large que l'actuel")
    avant = {o["id_trajet"] for o in offres_valides(conn, d) if o["confirmable"]}
    conn.execute("UPDATE demande SET cercle_max = %s WHERE id_demande = %s", (body.cercle_max, id_demande))
    d = {**d, "cercle_max": body.cercle_max}
    offres = offres_valides(conn, d)
    nouvelles = [o for o in offres if o["confirmable"] and o["id_trajet"] not in avant]
    return {"cercle_max": body.cercle_max, "offres_ajoutees": len(nouvelles), "offres": offres}


@router.post("/reservations", status_code=201)
def confirmer(body: Confirmation, u: dict = Depends(utilisateur_courant),
              conn: psycopg.Connection = Depends(get_conn)) -> dict:
    d = _demande(conn, body.id_demande, u)
    if d["date_unique"] and body.date_trajet != d["date_unique"]:
        raise HTTPException(422, f"Cette demande porte sur le {d['date_unique']:%d/%m/%Y}")
    e = evaluer(conn, d, _trajet(conn, body.id_trajet), body.date_trajet)
    if e["prix_fcfa"] != body.prix_annonce_fcfa:
        raise HTTPException(409, {"message": "Le prix a changé depuis l'affichage, merci de "
                                             "valider le nouveau prix.",
                                  "nouveau_prix_fcfa": e["prix_fcfa"], "detail": e["detail"]})
    if not e["dans_le_budget"]:
        raise HTTPException(422, f"Prix de {e['prix_fcfa']} FCFA supérieur à votre maximum "
                                 f"de {d['prix_max_fcfa']} FCFA")
    if not e["horaires_compatibles"]:
        raise HTTPException(422, "Arrivée hors de votre fenêtre ou détour trop long pour le conducteur")
    return reserver(conn, d, e, body.date_trajet)


def reserver(conn, d: dict, e: dict, jour: date) -> dict:
    """Enregistre la réservation au prix évalué et le paiement en attente."""
    try:
        with conn.transaction():          # point de reprise : un refus n'annule pas le reste
            r = conn.execute(
            """INSERT INTO reservation (id_demande, id_trajet, date_trajet, heure_prise_en_charge,
                   heure_arrivee_estimee, prix_fcfa, detour_km, niveau_cercle, statut)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'confirmee') RETURNING id_reservation""",
            (d["id_demande"], e["id_trajet"], jour, e["prise_en_charge"],
             e["arrivee_estimee"], e["prix_fcfa"], e["detour_km"], e["cercle"])).fetchone()
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "Vous avez déjà une réservation confirmée pour cette date")
    except psycopg.errors.RaiseException as exc:   # trajet complet, autorisation élève
        raise HTTPException(409, exc.diag.message_primary)
    p = conn.execute(
        """INSERT INTO paiement (id_reservation, montant_fcfa, commission_fcfa, moyen, statut)
           VALUES (%s, %s, %s, 'mobile_money', 'en_attente') RETURNING id_paiement""",
        (r["id_reservation"], e["prix_fcfa"], e["commission_fcfa"])).fetchone()
    conn.execute("UPDATE demande SET statut = 'satisfaite' WHERE id_demande = %s", (d["id_demande"],))
    return {"id_reservation": r["id_reservation"], "id_paiement": p["id_paiement"], "prix_fcfa": e["prix_fcfa"],
            "prise_en_charge": e["prise_en_charge"], "arrivee_estimee": e["arrivee_estimee"],
            "paiement": "en attente : payez par Mobile Money"}
