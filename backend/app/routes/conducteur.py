"""Espace conducteur de l'application mobile (wireframes conducteur 1 à 12).

Agrément, véhicule, règles, publication d'un trajet, prochain équipage, activité de
l'agent, retard, gains et évaluation des passagers. L'annulation et la réaffectation
(US07) restent dans routes/annulation.py, déjà branchée sur le moteur.

Agrément en démonstration : aucun agent de MboaRide ne vérifie encore les pièces.
Avec `MBOARIDE_AGREMENT_AUTO=1` (lanceur local), une pièce déposée est validée aussitôt
et l'agrément devient actif quand les quatre le sont. Sans cette variable, les pièces
restent « déposées » et l'agrément « en vérification », comme en production.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, model_validator

from .. import config, lieux, moteur
from ..db import get_conn
from ..notifications import notifier
from ..securite import utilisateur_courant
from .prix import roule_le

router = APIRouter(prefix="/api/moi/conducteur", tags=["Espace conducteur"])

PIECES = {
    "piece_identite": "Pièce d'identité",
    "permis": "Permis de conduire",
    "casier_judiciaire": "Extrait de casier judiciaire",
    "assurance": "Assurance du véhicule",
}
JOURS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre",
        "octobre", "novembre", "décembre"]


def _hhmm(t) -> str | None:
    return t.strftime("%H:%M") if t is not None else None


def _vehicule(conn, uid: int) -> dict | None:
    return conn.execute("SELECT * FROM vehicule WHERE id_proprietaire = %s ORDER BY id_vehicule LIMIT 1",
                        (uid,)).fetchone()


# --- Vue d'ensemble et agrément ------------------------------------------------------------

@router.get("")
def vue_d_ensemble(u: dict = Depends(utilisateur_courant), conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return {"prenom": u["prenom"], "statut_agrement": u["statut_agrement"],
            "agree": u["statut_agrement"] == "actif", "automatique": u["mode_reservation"] == "autonome",
            "a_un_vehicule": _vehicule(conn, u["id_utilisateur"]) is not None}


def _agrement(conn, u: dict) -> dict:
    deposes = {r["type_document"]: r for r in conn.execute(
        "SELECT type_document, statut, depose_le, expire_le FROM document_agrement WHERE id_utilisateur = %s",
        (u["id_utilisateur"],)).fetchall()}
    documents = []
    for code, libelle in PIECES.items():
        r = deposes.get(code)
        if r is None:
            statut, detail = "manquant", None
        elif r["statut"] == "valide":
            statut = "valide"
            detail = f"Valable jusqu'au {r['expire_le']:%d/%m/%Y}" if r["expire_le"] else "Validée"
        elif r["statut"] == "depose":
            statut, detail = "depose", f"Déposée le {r['depose_le']:%d/%m/%Y}, en vérification"
        else:
            statut, detail = "manquant", f"Pièce {r['statut']} : à déposer de nouveau"
        documents.append({"type": code, "libelle": libelle, "statut": statut, "detail": detail})
    statut = conn.execute("SELECT statut_agrement FROM utilisateur WHERE id_utilisateur = %s",
                          (u["id_utilisateur"],)).fetchone()["statut_agrement"]
    return {"statut_agrement": statut, "documents": documents}


@router.get("/agrement")
def agrement(u: dict = Depends(utilisateur_courant), conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return _agrement(conn, u)


@router.post("/agrement/documents/{type_document}")
def deposer(type_document: str, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if type_document not in PIECES:
        raise HTTPException(404, f"Pièce inconnue : {type_document}")
    if u["statut_agrement"] == "suspendu":
        raise HTTPException(403, "Agrément suspendu après un signalement : contactez MboaRide")
    auto = config.AGREMENT_AUTO
    conn.execute(
        """INSERT INTO document_agrement (id_utilisateur, type_document, statut, chemin_fichier, expire_le)
           VALUES (%s, %s, %s, %s, %s)
           ON CONFLICT (id_utilisateur, type_document) DO UPDATE
              SET statut = EXCLUDED.statut, chemin_fichier = EXCLUDED.chemin_fichier,
                  depose_le = now(), expire_le = EXCLUDED.expire_le""",
        (u["id_utilisateur"], type_document, "valide" if auto else "depose",
         f"agrement/{u['id_utilisateur']}/{type_document}",
         date.today() + timedelta(days=365) if auto else None))
    valides = conn.execute("SELECT count(*) n FROM document_agrement WHERE id_utilisateur = %s AND statut = 'valide'",
                           (u["id_utilisateur"],)).fetchone()["n"]
    statut = "actif" if valides == len(PIECES) else "en_verification"
    conn.execute(
        """UPDATE utilisateur SET est_conducteur = TRUE, statut_agrement = %s,
                  date_agrement = CASE WHEN %s = 'actif' THEN CURRENT_DATE ELSE date_agrement END
            WHERE id_utilisateur = %s AND statut_agrement <> 'actif'""",
        (statut, statut, u["id_utilisateur"]))
    return _agrement(conn, u)


# --- Véhicule ----------------------------------------------------------------------------

class Vehicule(BaseModel):
    marque_modele: str = Field(min_length=2, max_length=80)
    immatriculation: str = Field(min_length=3, max_length=15)
    places_passagers: int = Field(ge=1, le=8)
    conso_l_100km: float = Field(gt=0, le=30)
    climatise: bool = False
    non_fumeur: bool = True
    accepte_bagages: bool = False


@router.get("/vehicule")
def lire_vehicule(u: dict = Depends(utilisateur_courant), conn: psycopg.Connection = Depends(get_conn)) -> dict:
    v = _vehicule(conn, u["id_utilisateur"])
    if v is None:
        raise HTTPException(404, "Aucun véhicule enregistré")
    return {**v, "conso_l_100km": float(v["conso_l_100km"])}


@router.put("/vehicule")
def enregistrer_vehicule(body: Vehicule, u: dict = Depends(utilisateur_courant),
                         conn: psycopg.Connection = Depends(get_conn)) -> dict:
    v = _vehicule(conn, u["id_utilisateur"])
    plaque = " ".join(body.immatriculation.upper().split())
    try:
        with conn.transaction():
            if v is None:
                v = conn.execute(
                    """INSERT INTO vehicule (id_proprietaire, marque_modele, immatriculation, places_passagers,
                           conso_l_100km, climatise, non_fumeur, accepte_bagages)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
                    (u["id_utilisateur"], body.marque_modele, plaque, body.places_passagers, body.conso_l_100km,
                     body.climatise, body.non_fumeur, body.accepte_bagages)).fetchone()
            else:
                v = conn.execute(
                    """UPDATE vehicule SET marque_modele = %s, immatriculation = %s, places_passagers = %s,
                           conso_l_100km = %s, climatise = %s, non_fumeur = %s, accepte_bagages = %s
                        WHERE id_vehicule = %s RETURNING *""",
                    (body.marque_modele, plaque, body.places_passagers, body.conso_l_100km, body.climatise,
                     body.non_fumeur, body.accepte_bagages, v["id_vehicule"])).fetchone()
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "Cette immatriculation est déjà enregistrée") from None
    except psycopg.errors.RaiseException as exc:   # places inférieures à celles d'un trajet publié
        raise HTTPException(409, exc.diag.message_primary) from None
    conn.execute("UPDATE utilisateur SET est_conducteur = TRUE WHERE id_utilisateur = %s", (u["id_utilisateur"],))
    return {**v, "conso_l_100km": float(v["conso_l_100km"])}


# --- Règles ------------------------------------------------------------------------------

class Regles(BaseModel):
    collegues: bool
    partenaires: bool
    public: bool
    eleves: bool
    prix_min_fcfa: int = Field(ge=0, le=20000)
    automatique: bool

    @model_validator(mode="after")
    def _un_cercle(self):
        if not (self.collegues or self.partenaires or self.public):
            raise ValueError("Acceptez au moins un cercle de passagers")
        return self


def _regles(u: dict) -> dict:
    return {"collegues": u["accepte_collegues"], "partenaires": u["accepte_partenaires"],
            "public": u["accepte_public"], "eleves": u["accepte_eleves"],
            "prix_min_fcfa": u["prix_min_fcfa"], "automatique": u["mode_reservation"] == "autonome"}


@router.get("/regles")
def lire_regles(u: dict = Depends(utilisateur_courant)) -> dict:
    return _regles(u)


@router.put("/regles")
def enregistrer_regles(body: Regles, u: dict = Depends(utilisateur_courant),
                       conn: psycopg.Connection = Depends(get_conn)) -> dict:
    u = conn.execute(
        """UPDATE utilisateur SET accepte_collegues = %s, accepte_partenaires = %s, accepte_public = %s,
               accepte_eleves = %s, prix_min_fcfa = %s, mode_reservation = %s
            WHERE id_utilisateur = %s RETURNING *""",
        (body.collegues, body.partenaires, body.public, body.eleves, body.prix_min_fcfa,
         "autonome" if body.automatique else "manuel", u["id_utilisateur"])).fetchone()
    # Les trajets actifs suivent les cercles choisis.
    conn.execute("UPDATE trajet SET ouvert_partenaires = %s, ouvert_public = %s "
                 "WHERE id_conducteur = %s AND statut = 'actif'",
                 (body.partenaires, _ouvert_public(conn, u), u["id_utilisateur"]))
    return _regles(u)


def _ouvert_public(conn, u: dict) -> bool:
    """Un conducteur sans organisation n'a que le public : sinon personne ne le verrait."""
    seul = conn.execute("SELECT 1 FROM appartenance WHERE id_utilisateur = %s",
                        (u["id_utilisateur"],)).fetchone() is None
    return bool(u["accepte_public"]) or seul


# --- Publication d'un trajet ----------------------------------------------------------------

class NouveauTrajet(BaseModel):
    type_trajet: str = Field(default="urbain", pattern="^(urbain|interurbain)$")
    depart: str = Field(min_length=1, max_length=120)
    arrivee: str = Field(min_length=1, max_length=120)
    heure_depart: time
    jours_semaine: list[int] = Field(default_factory=list, description="1 (lundi) à 7 (dimanche)")
    date_trajet: date | None = None
    places: int = Field(ge=1, le=8)
    detour_max_km: float = Field(default=2.0, ge=0, le=20)
    peage_fcfa: int = Field(default=0, ge=0)
    points_depart: list[str] = Field(default_factory=list)
    # Où et comment le conducteur prend ses passagers : obligatoire, c'est ce que le
    # passager lit pour le retrouver (« Station Total de Logpom, côté boulangerie »).
    point_ramassage: str = Field(min_length=5, max_length=160)
    consignes_ramassage: str | None = Field(default=None, max_length=300)
    attente_max_min: int = Field(default=5, ge=0, le=30)

    @model_validator(mode="after")
    def _quand(self):
        if not self.jours_semaine and self.date_trajet is None:
            raise ValueError("Choisissez au moins un jour, ou une date")
        if any(j < 1 or j > 7 for j in self.jours_semaine):
            raise ValueError("Jours de 1 (lundi) à 7 (dimanche)")
        return self


def _lieu(nom: str) -> tuple[str, float, float]:
    trouve = lieux.trouver(nom)
    if trouve is None:
        connus = ", ".join(l["nom"] for l in lieux.suggestions(limite=40))
        raise HTTPException(422, f"Lieu inconnu : « {nom} ». Lieux connus : {connus}")
    return trouve


@router.post("/trajets", status_code=201)
def publier(body: NouveauTrajet, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return _publier(conn, body, u)


def _publier(conn, body: NouveauTrajet, u: dict) -> dict:
    if u["statut_agrement"] != "actif":
        raise HTTPException(403, "Votre agrément doit être validé avant de publier un trajet")
    v = _vehicule(conn, u["id_utilisateur"])
    if v is None:
        raise HTTPException(409, "Enregistrez d'abord votre véhicule")
    if body.places > v["places_passagers"]:
        raise HTTPException(422, f"Votre véhicule n'a que {v['places_passagers']} places passagers")
    depart, arrivee = _lieu(body.depart), _lieu(body.arrivee)
    if depart[0] == arrivee[0]:
        raise HTTPException(422, "Le départ et l'arrivée sont identiques")
    jours = None
    if body.date_trajet is None:
        jours = "".join("1" if j in body.jours_semaine else "0" for j in range(1, 8))
    deja = conn.execute(
        """SELECT id_trajet FROM trajet WHERE id_conducteur = %s AND statut = 'actif'
              AND depart_libelle = %s AND arrivee_libelle = %s AND heure_depart = %s
              AND jours_semaine IS NOT DISTINCT FROM %s AND date_unique IS NOT DISTINCT FROM %s""",
        (u["id_utilisateur"], depart[0], arrivee[0], body.heure_depart, jours, body.date_trajet)).fetchone()
    if deja is not None:
        raise HTTPException(409, f"Ce trajet est déjà publié (trajet n° {deja['id_trajet']}) : "
                                 "les passagers le voient déjà")
    t = conn.execute(
        """INSERT INTO trajet (id_conducteur, id_vehicule, type_trajet, depart_libelle, depart_lat, depart_lon,
               arrivee_libelle, arrivee_lat, arrivee_lon, heure_depart, date_unique, jours_semaine,
               places_offertes, detour_max_km, peage_fcfa, ouvert_partenaires, ouvert_public,
               point_ramassage, consignes_ramassage, attente_max_min)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
           RETURNING *""",
        (u["id_utilisateur"], v["id_vehicule"], body.type_trajet, depart[0], depart[1], depart[2],
         arrivee[0], arrivee[1], arrivee[2], body.heure_depart, body.date_trajet, jours, body.places,
         body.detour_max_km, body.peage_fcfa if body.type_trajet == "interurbain" else 0,
         u["accepte_partenaires"], _ouvert_public(conn, u), body.point_ramassage.strip(),
         (body.consignes_ramassage or "").strip() or None, body.attente_max_min)).fetchone()
    if body.type_trajet == "interurbain":
        points = [depart[0], *[p for p in body.points_depart if p.strip()]]
        minute = moteur.minutes(body.heure_depart)
        for ordre, nom in enumerate(dict.fromkeys(points), start=1):
            p = _lieu(nom)
            conn.execute("""INSERT INTO point_depart (id_trajet, ordre_passage, libelle, lat, lon, heure_passage)
                            VALUES (%s, %s, %s, %s, %s, %s)""",
                         (t["id_trajet"], ordre, p[0], p[1], p[2], moteur.hhmm(minute + 20 * (ordre - 1))))
    return {"id_trajet": t["id_trajet"], "depart": depart[0], "arrivee": arrivee[0],
            "heure_depart": _hhmm(t["heure_depart"]), "jours_semaine": t["jours_semaine"],
            "date_unique": t["date_unique"], "places": t["places_offertes"],
            "ouvert_partenaires": t["ouvert_partenaires"], "ouvert_public": t["ouvert_public"],
            "point_ramassage": t["point_ramassage"], "consignes_ramassage": t["consignes_ramassage"],
            "attente_max_min": t["attente_max_min"]}


class Ramassage(BaseModel):
    point_ramassage: str = Field(min_length=5, max_length=160)
    consignes_ramassage: str | None = Field(default=None, max_length=300)
    attente_max_min: int = Field(default=5, ge=0, le=30)


@router.put("/trajets/{id_trajet}/ramassage")
def preciser_ramassage(id_trajet: int, body: Ramassage, u: dict = Depends(utilisateur_courant),
                       conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Préciser le point de ramassage d'un trajet déjà publié ; les passagers inscrits sont prévenus."""
    t = conn.execute(
        """UPDATE trajet SET point_ramassage = %s, consignes_ramassage = %s, attente_max_min = %s
            WHERE id_trajet = %s AND id_conducteur = %s RETURNING *""",
        (body.point_ramassage.strip(), (body.consignes_ramassage or "").strip() or None, body.attente_max_min,
         id_trajet, u["id_utilisateur"])).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    for r in conn.execute(
            """SELECT DISTINCT d.id_demandeur FROM reservation r JOIN demande d USING (id_demande)
                WHERE r.id_trajet = %s AND r.statut = 'confirmee' AND r.date_trajet >= CURRENT_DATE""",
            (id_trajet,)).fetchall():
        notifier(conn, r["id_demandeur"], "course",
                 f"{u['prenom']} a précisé le point de ramassage : {t['point_ramassage']}"
                 + (f" ({t['consignes_ramassage']})" if t["consignes_ramassage"] else "") + ".")
    return {"id_trajet": id_trajet, "point_ramassage": t["point_ramassage"],
            "consignes_ramassage": t["consignes_ramassage"], "attente_max_min": t["attente_max_min"]}


# --- Trajets programmés : plusieurs à la fois, retrait, republication ------------------------

class LotDeTrajets(BaseModel):
    trajets: list[NouveauTrajet] = Field(min_length=1, max_length=20)


@router.post("/trajets/lot", status_code=201)
def publier_plusieurs(body: LotDeTrajets, u: dict = Depends(utilisateur_courant),
                      conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Programme plusieurs trajets d'un coup (aller et retour, plusieurs dates ou horaires).

    Chaque trajet est publié ou refusé indépendamment des autres : un doublon ou un lieu
    inconnu n'empêche pas de publier le reste du lot."""
    resultats = []
    for i, trajet in enumerate(body.trajets):
        try:
            with conn.transaction():
                publie = _publier(conn, trajet, u)
            resultats.append({"rang": i, "publie": True, "id_trajet": publie["id_trajet"], "trajet": publie})
        except HTTPException as exc:
            resultats.append({"rang": i, "publie": False, "erreur": exc.detail})
    return {"publies": sum(r["publie"] for r in resultats), "refuses": sum(not r["publie"] for r in resultats),
            "resultats": resultats}


def _jours(t: dict) -> list[int]:
    return [i + 1 for i, c in enumerate(t["jours_semaine"] or "") if c == "1"]


def _prochain_depart(conn, t: dict, annulees: set) -> date | None:
    for i in range(0, 60):
        jour = date.today() + timedelta(days=i)
        if roule_le(t, jour) and jour not in annulees:
            return jour
    return None


@router.get("/trajets")
def mes_trajets_programmes(u: dict = Depends(utilisateur_courant),
                           conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Tous les trajets du conducteur : actifs, retirés ou passés, avec leurs dates annulées."""
    trajets = conn.execute("SELECT * FROM trajet WHERE id_conducteur = %s ORDER BY statut = 'actif' DESC, "
                           "heure_depart, id_trajet DESC", (u["id_utilisateur"],)).fetchall()
    out = []
    for t in trajets:
        annulees = {r["date_trajet"] for r in conn.execute(
            "SELECT date_trajet FROM indisponibilite_trajet WHERE id_trajet = %s AND date_trajet >= CURRENT_DATE "
            "ORDER BY date_trajet", (t["id_trajet"],)).fetchall()}
        a_venir = conn.execute(
            "SELECT count(*) n FROM reservation WHERE id_trajet = %s AND statut = 'confirmee' "
            "AND date_trajet >= CURRENT_DATE", (t["id_trajet"],)).fetchone()["n"]
        passe = t["date_unique"] is not None and t["date_unique"] < date.today()
        etat = "retire" if t["statut"] == "annule" else ("passe" if passe or t["statut"] == "termine" else "actif")
        prochain = _prochain_depart(conn, t, annulees) if etat == "actif" else None
        out.append({
            "id_trajet": t["id_trajet"], "type_trajet": t["type_trajet"], "etat": etat,
            "depart": t["depart_libelle"], "arrivee": t["arrivee_libelle"],
            "heure_depart": _hhmm(t["heure_depart"]), "jours_semaine": _jours(t), "date_unique": t["date_unique"],
            "places": t["places_offertes"], "detour_max_km": float(t["detour_max_km"]),
            "point_ramassage": t["point_ramassage"], "consignes_ramassage": t["consignes_ramassage"],
            "dates_annulees": sorted(annulees), "reservations_a_venir": a_venir, "prochain_depart": prochain,
        })
    return out


def _mon_trajet(conn, id_trajet: int, u: dict) -> dict:
    t = conn.execute("SELECT * FROM trajet WHERE id_trajet = %s AND id_conducteur = %s",
                     (id_trajet, u["id_utilisateur"])).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    return t


class Retrait(BaseModel):
    motif: str | None = Field(default=None, max_length=200)


@router.post("/trajets/{id_trajet}/retrait")
def retirer_trajet(id_trajet: int, body: Retrait, u: dict = Depends(utilisateur_courant),
                   conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Retire un trajet entier : il n'est plus proposé, et chaque passager déjà inscrit est
    prévenu, remboursé et réaffecté si possible (comme pour l'annulation d'une date)."""
    t = _mon_trajet(conn, id_trajet, u)
    if t["statut"] == "annule":
        raise HTTPException(409, "Ce trajet est déjà retiré")
    passagers = retirer_trajet_entier(conn, id_trajet, body.motif or "trajet retiré par le conducteur")
    return {"id_trajet": id_trajet, "etat": "retire", "reservations_annulees": passagers}


def retirer_trajet_entier(conn, id_trajet: int, motif: str) -> int:
    """Passe le trajet à « annulé » et libère les passagers de chaque date à venir.

    Utilisé par le conducteur et par la console d'administration. Renvoie le nombre de
    réservations annulées."""
    from .annulation import liberer_passagers

    conn.execute("UPDATE trajet SET statut = 'annule' WHERE id_trajet = %s", (id_trajet,))
    dates = [r["date_trajet"] for r in conn.execute(
        "SELECT DISTINCT date_trajet FROM reservation WHERE id_trajet = %s AND statut = 'confirmee' "
        "AND date_trajet >= CURRENT_DATE ORDER BY date_trajet", (id_trajet,)).fetchall()]
    return sum(liberer_passagers(conn, id_trajet, jour, motif)["reservations_annulees"] for jour in dates)


class Republication(BaseModel):
    # Trajet ponctuel dont la date est passée : la nouvelle date. Ignoré pour un trajet régulier.
    date_trajet: date | None = None
    heure_depart: time | None = None


@router.post("/trajets/{id_trajet}/republication")
def republier(id_trajet: int, body: Republication, u: dict = Depends(utilisateur_courant),
              conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Remet en ligne un trajet retiré (ou passé), à une nouvelle date si c'était un trajet ponctuel."""
    if u["statut_agrement"] != "actif":
        raise HTTPException(403, "Votre agrément doit être validé avant de publier un trajet")
    t = _mon_trajet(conn, id_trajet, u)
    nouvelle_date = t["date_unique"]
    if t["date_unique"] is not None:
        nouvelle_date = body.date_trajet or t["date_unique"]
        if nouvelle_date < date.today():
            raise HTTPException(422, "Choisissez une nouvelle date, aujourd'hui ou plus tard")
    elif t["statut"] == "actif":
        raise HTTPException(409, "Ce trajet est déjà en ligne")
    if t["statut"] == "actif" and nouvelle_date == t["date_unique"] and body.heure_depart is None:
        raise HTTPException(409, "Ce trajet est déjà en ligne")
    heure = body.heure_depart or t["heure_depart"]
    deja = conn.execute(
        """SELECT id_trajet FROM trajet WHERE id_conducteur = %s AND statut = 'actif' AND id_trajet <> %s
              AND depart_libelle = %s AND arrivee_libelle = %s AND heure_depart = %s
              AND jours_semaine IS NOT DISTINCT FROM %s AND date_unique IS NOT DISTINCT FROM %s""",
        (u["id_utilisateur"], id_trajet, t["depart_libelle"], t["arrivee_libelle"], heure,
         t["jours_semaine"], nouvelle_date)).fetchone()
    if deja is not None:
        raise HTTPException(409, f"Un trajet identique est déjà en ligne (trajet n° {deja['id_trajet']})")
    try:
        with conn.transaction():
            conn.execute("UPDATE trajet SET statut = 'actif', date_unique = %s, heure_depart = %s, "
                         "ouvert_partenaires = %s, ouvert_public = %s WHERE id_trajet = %s",
                         (nouvelle_date, heure, u["accepte_partenaires"], _ouvert_public(conn, u), id_trajet))
    except psycopg.errors.RaiseException as exc:   # places supérieures à celles du véhicule actuel
        raise HTTPException(409, exc.diag.message_primary) from None
    return {"id_trajet": id_trajet, "etat": "actif", "date_unique": nouvelle_date, "heure_depart": _hhmm(heure)}


@router.delete("/trajets/{id_trajet}/annulations/{date_trajet}")
def retablir_date(id_trajet: int, date_trajet: date, u: dict = Depends(utilisateur_courant),
                  conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Rétablit une date annulée : le trajet est de nouveau proposé ce jour-là."""
    t = _mon_trajet(conn, id_trajet, u)
    if date_trajet < date.today():
        raise HTTPException(422, "Cette date est passée")
    if t["statut"] != "actif":
        raise HTTPException(409, "Republiez d'abord le trajet")
    supprime = conn.execute("DELETE FROM indisponibilite_trajet WHERE id_trajet = %s AND date_trajet = %s "
                            "RETURNING date_trajet", (id_trajet, date_trajet)).fetchone()
    if supprime is None:
        raise HTTPException(404, "Ce trajet n'était pas annulé à cette date")
    return {"id_trajet": id_trajet, "date_trajet": date_trajet, "etat": "retabli"}


# --- Prochain équipage ------------------------------------------------------------------------

def _equipage(conn, t: dict, jour: date) -> dict:
    # Passagers qui ont payé leur place : nom, téléphone et note, pour que le conducteur sache
    # qui il prend et puisse l'appeler au point de ramassage.
    arrets = conn.execute(
        """SELECT r.id_reservation, u.prenom AS passager, u.nom, u.telephone, d.depart_libelle AS lieu,
                  d.depart_lat AS lat, d.depart_lon AS lon, d.arrivee_libelle AS destination,
                  r.heure_prise_en_charge, r.heure_arrivee_estimee, d.arrivee_au_plus_tard, r.prix_fcfa,
                  r.fin_validee_le, d.id_eleve, n.note_moyenne, n.nb_evaluations
             FROM reservation r JOIN demande d USING (id_demande)
             JOIN utilisateur u ON u.id_utilisateur = d.id_demandeur
             JOIN paiement p ON p.id_reservation = r.id_reservation AND p.statut = 'reussi'
             LEFT JOIN LATERAL (SELECT round(avg(e.note), 1) AS note_moyenne, count(*) AS nb_evaluations
                                  FROM evaluation e WHERE e.id_evalue = u.id_utilisateur) n ON TRUE
            WHERE r.id_trajet = %s AND r.date_trajet = %s AND r.statut IN ('confirmee', 'terminee')
            ORDER BY r.heure_prise_en_charge, r.id_reservation""", (t["id_trajet"], jour)).fetchall()
    course = conn.execute("SELECT statut FROM course WHERE id_trajet = %s AND date_trajet = %s",
                          (t["id_trajet"], jour)).fetchone()
    arrivee = max((a["heure_arrivee_estimee"] for a in arrets), default=None)
    if arrivee is None:
        km = moteur.distance_km(t["depart_lat"], t["depart_lon"], t["arrivee_lat"], t["arrivee_lon"],
                                t["type_trajet"] == "interurbain")
        vitesse = 60 if t["type_trajet"] == "interurbain" else 20
        arrivee_txt = moteur.hhmm(moteur.minutes(t["heure_depart"]) + km / vitesse * 60)
    else:
        arrivee_txt = _hhmm(arrivee)
    demain = date.today() + timedelta(days=1)
    libelle = ("Aujourd'hui" if jour == date.today() else "Demain" if jour == demain
               else f"{JOURS[jour.weekday()].capitalize()} {jour.day} {MOIS[jour.month - 1]}")
    return {
        "id_trajet": t["id_trajet"], "date_trajet": jour.isoformat(), "jour": libelle,
        "depart": t["depart_libelle"], "arrivee": t["arrivee_libelle"],
        "heure_depart": _hhmm(t["heure_depart"]), "arrivee_estimee": arrivee_txt,
        "places": t["places_offertes"],
        "point_ramassage": t.get("point_ramassage"), "consignes_ramassage": t.get("consignes_ramassage"),
        "attente_max_min": t.get("attente_max_min", 5),
        "statut_course": course["statut"] if course else "a_demarrer",
        "depart_lat": float(t["depart_lat"]), "depart_lon": float(t["depart_lon"]),
        "arrivee_lat": float(t["arrivee_lat"]), "arrivee_lon": float(t["arrivee_lon"]),
        "arrets": [{"id_reservation": a["id_reservation"], "passager": a["passager"], "lieu": a["lieu"],
                    "nom": a["nom"], "telephone": a["telephone"], "destination": a["destination"],
                    "note_moyenne": float(a["note_moyenne"]) if a["note_moyenne"] is not None else None,
                    "nb_evaluations": a["nb_evaluations"], "eleve": a["id_eleve"] is not None,
                    "fin_validee": a["fin_validee_le"] is not None,
                    "prise_en_charge": _hhmm(a["heure_prise_en_charge"]),
                    "arrivee": _hhmm(a["heure_arrivee_estimee"]),
                    "au_plus_tard": _hhmm(a["arrivee_au_plus_tard"]), "prix_fcfa": a["prix_fcfa"],
                    "lat": float(a["lat"]), "lon": float(a["lon"])} for a in arrets],
    }


@router.get("/equipage")
def prochain_equipage(u: dict = Depends(utilisateur_courant),
                      conn: psycopg.Connection = Depends(get_conn)) -> dict | None:
    """Prochain départ du conducteur, avec ses passagers.

    On regarde les sept prochains jours (aujourd'hui compris tant que le départ date de
    moins d'une heure) : le premier départ qui a déjà des passagers est montré en priorité,
    sinon le premier départ tout court, « en attente de passagers ».
    """
    trajets = conn.execute("SELECT * FROM trajet WHERE id_conducteur = %s AND statut = 'actif' ORDER BY id_trajet",
                           (u["id_utilisateur"],)).fetchall()
    maintenant = moteur.minutes(datetime.now().time())
    departs = []
    courses = {(c["id_trajet"], c["date_trajet"]): c["statut"] for c in conn.execute(
        "SELECT c.id_trajet, c.date_trajet, c.statut FROM course c JOIN trajet t USING (id_trajet) "
        "WHERE t.id_conducteur = %s AND c.date_trajet >= CURRENT_DATE - 1", (u["id_utilisateur"],)).fetchall()}
    for t in trajets:
        # Une course démarrée reste affichée jusqu'à son règlement, même après l'heure.
        en_cours = [j for (i, j), st in courses.items() if i == t["id_trajet"] and st != "reglee"]
        for jour in en_cours:
            departs.append((False, jour, t["heure_depart"], t["id_trajet"], t))
        debut = date.today()
        if moteur.minutes(t["heure_depart"]) < maintenant - 60:   # parti depuis plus d'une heure
            debut += timedelta(days=1)
        for i in range(8):
            jour = debut + timedelta(days=i)
            if jour in en_cours or courses.get((t["id_trajet"], jour)) == "reglee":
                continue
            if not roule_le(t, jour) or conn.execute(
                    "SELECT 1 FROM indisponibilite_trajet WHERE id_trajet = %s AND date_trajet = %s",
                    (t["id_trajet"], jour)).fetchone():
                continue
            pris = conn.execute("SELECT count(*) n FROM reservation r JOIN paiement p USING (id_reservation) "
                                "WHERE r.id_trajet = %s AND r.date_trajet = %s "
                                "AND r.statut IN ('confirmee', 'terminee') AND p.statut = 'reussi'", (t["id_trajet"], jour)).fetchone()["n"]
            departs.append((pris == 0, jour, t["heure_depart"], t["id_trajet"], t))
    if not departs:
        return None
    _, jour, _, _, t = min(departs, key=lambda d: d[:4])
    return _equipage(conn, t, jour)


# --- Activité de l'agent, retard, gains, évaluation ---------------------------------------------

@router.get("/activite")
def activite(u: dict = Depends(utilisateur_courant), conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Réservations obtenues par l'agent conducteur sur les trajets du conducteur, les plus récentes d'abord."""
    rows = conn.execute(
        """SELECT r.statut, r.date_trajet, r.prix_fcfa, r.niveau_cercle, u.prenom AS passager,
                  d.depart_libelle, t.arrivee_libelle, r.heure_prise_en_charge
             FROM reservation r JOIN trajet t USING (id_trajet) JOIN demande d USING (id_demande)
             JOIN utilisateur u ON u.id_utilisateur = d.id_demandeur
            WHERE t.id_conducteur = %s ORDER BY r.cree_le DESC, r.id_reservation DESC LIMIT 30""",
        (u["id_utilisateur"],)).fetchall()
    return [{"type": "reservation" if r["statut"] == "confirmee" else "annulation",
             "passager": r["passager"],
             "detail": f"{r['depart_libelle']} → {r['arrivee_libelle']} · {r['date_trajet']:%d/%m} à "
                       f"{_hhmm(r['heure_prise_en_charge'])} · {r['prix_fcfa']} FCFA · cercle {r['niveau_cercle']}"
                       + ("" if r["statut"] == "confirmee" else f" · {r['statut']}")}
            for r in rows]


class Retard(BaseModel):
    id_trajet: int
    date_trajet: date
    minutes: int = Field(ge=1, le=120)


@router.post("/retard")
def signaler_retard(body: Retard, u: dict = Depends(utilisateur_courant),
                    conn: psycopg.Connection = Depends(get_conn)) -> dict:
    t = conn.execute("SELECT * FROM trajet WHERE id_trajet = %s AND id_conducteur = %s",
                     (body.id_trajet, u["id_utilisateur"])).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    equipage = _equipage(conn, t, body.date_trajet)
    for a in equipage["arrets"]:
        demandeur = conn.execute("SELECT d.id_demandeur FROM reservation r JOIN demande d USING (id_demande) "
                                 "WHERE r.id_reservation = %s", (a["id_reservation"],)).fetchone()
        h, m = map(int, a["prise_en_charge"].split(":"))
        nouvelle = moteur.hhmm(h * 60 + m + body.minutes)
        notifier(conn, demandeur["id_demandeur"], "retard",
                 f"{u['prenom']} a {body.minutes} min de retard : prise en charge vers {nouvelle} à {a['lieu']}.")
    return {"passagers_prevenus": len(equipage["arrets"])}


@router.get("/gains")
def gains(u: dict = Depends(utilisateur_courant), conn: psycopg.Connection = Depends(get_conn)) -> dict:
    rows = conn.execute(
        """SELECT r.id_trajet, r.date_trajet, t.depart_libelle, t.arrivee_libelle, t.depart_lat, t.depart_lon,
                  t.arrivee_lat, t.arrivee_lon, t.type_trajet, v.conso_l_100km,
                  count(*) AS passagers, sum(p.montant_fcfa - p.commission_fcfa) AS montant,
                  sum(p.commission_fcfa) AS commission, bool_and(p.verse_le IS NOT NULL) AS recu
             FROM reservation r JOIN trajet t USING (id_trajet) JOIN vehicule v USING (id_vehicule)
             JOIN paiement p USING (id_reservation)
            WHERE t.id_conducteur = %s AND r.statut IN ('confirmee', 'terminee') AND p.statut = 'reussi'
            GROUP BY r.id_trajet, r.date_trajet, t.id_trajet, v.conso_l_100km
            ORDER BY r.date_trajet DESC LIMIT 20""", (u["id_utilisateur"],)).fetchall()
    paiements = [{"date": f"{r['date_trajet']:%d/%m}", "trajet": f"{r['depart_libelle']} → {r['arrivee_libelle']}",
                  "passagers": r["passagers"], "montant_fcfa": int(r["montant"] or 0),
                  "commission_fcfa": int(r["commission"] or 0), "recu": bool(r["recu"])}
                 for r in rows]
    carburant = 0
    recu_dernier = 0
    if rows:
        r = rows[0]
        km = moteur.distance_km(r["depart_lat"], r["depart_lon"], r["arrivee_lat"], r["arrivee_lon"],
                                r["type_trajet"] == "interurbain")
        carburant = round(km * float(r["conso_l_100km"]) / 100 * moteur.politique().fuel_price_per_l)
        recu_dernier = int(r["montant"] or 0)
    aujourd_hui = date.today()
    return {"mois": f"{MOIS[aujourd_hui.month - 1].capitalize()} {aujourd_hui.year}",
            "dernier_trajet_recu_fcfa": recu_dernier, "dernier_trajet_carburant_fcfa": carburant,
            "paiements": paiements}


class Note(BaseModel):
    passager: str
    note: int = Field(ge=1, le=5)


class Evaluation(BaseModel):
    id_trajet: int
    date_trajet: date
    notes: list[Note] = Field(min_length=1)
    signalements: list[str] = Field(default_factory=list)
    grave: bool = False


@router.post("/evaluations", status_code=201)
def evaluer_passagers(body: Evaluation, u: dict = Depends(utilisateur_courant),
                      conn: psycopg.Connection = Depends(get_conn)) -> dict:
    t = conn.execute("SELECT * FROM trajet WHERE id_trajet = %s AND id_conducteur = %s",
                     (body.id_trajet, u["id_utilisateur"])).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    resas = {r["prenom"]: r for r in conn.execute(
        """SELECT r.id_reservation, d.id_demandeur, us.prenom FROM reservation r JOIN demande d USING (id_demande)
             JOIN utilisateur us ON us.id_utilisateur = d.id_demandeur
            WHERE r.id_trajet = %s AND r.date_trajet = %s AND r.statut IN ('confirmee', 'terminee')""",
        (body.id_trajet, body.date_trajet)).fetchall()}
    commentaire = "; ".join(body.signalements)[:500] or None
    enregistrees = 0
    for n in body.notes:
        r = resas.get(n.passager)
        if r is None:
            continue
        conn.execute("""INSERT INTO evaluation (id_reservation, id_auteur, id_evalue, note, commentaire, signalement_grave)
                        VALUES (%s, %s, %s, %s, %s, %s)""",
                     (r["id_reservation"], u["id_utilisateur"], r["id_demandeur"], n.note, commentaire, body.grave))
        enregistrees += 1
    if not enregistrees:
        raise HTTPException(422, "Aucun de ces passagers n'a voyagé sur ce trajet à cette date")
    return {"evaluations": enregistrees}
