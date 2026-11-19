"""Console d'administration de la plateforme : l'équipe MboaRide (pas une organisation).

Rôles (table `administrateur`) :

- `super_admin` : tout, y compris les paramètres (tarifs, délais) et l'équipe ;
- `support`     : utilisateurs, agréments, trajets et courses, signalements, organisations,
                  communication ;
- `finance`     : paiements, remboursements, versements, commissions, portefeuilles.

Le tableau de bord et le journal sont ouverts aux trois rôles. Chaque action qui modifie
quelque chose (suspension, pièce validée ou refusée, trajet retiré, remboursement,
nomination) est écrite dans `journal_admin`, avec son auteur et son motif.

L'identification est celle du reste de l'API : jeton de l'API Node (la console se
connecte par `POST /auth/login` sur Node) ou, en démonstration, en-tête `X-Utilisateur`.
"""

from __future__ import annotations

import csv
import io
import json
import secrets
from datetime import date, timedelta
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field, model_validator

from .. import config, parametres, pieces
from .. import portefeuille as pf
from ..db import get_conn
from ..notifications import envoyer_courriel, notifier
from ..securite import utilisateur_courant
from .conducteur import PIECES, retirer_trajet_entier

router = APIRouter(prefix="/api/admin", tags=["Administration de la plateforme"])

ROLES = ("super_admin", "support", "finance")
MODULES = {
    "super_admin": ["tableau", "utilisateurs", "agrements", "trajets", "signalements", "organisations",
                    "paiements", "finances", "communication", "parametres", "administrateurs", "journal"],
    "support": ["tableau", "utilisateurs", "agrements", "trajets", "signalements", "organisations",
                "communication", "journal"],
    "finance": ["tableau", "paiements", "finances", "journal"],
}


# --- Accès ---------------------------------------------------------------------------------

def admin_courant(u: dict = Depends(utilisateur_courant), conn: psycopg.Connection = Depends(get_conn)) -> dict:
    a = conn.execute("SELECT role FROM administrateur WHERE id_utilisateur = %s AND actif",
                     (u["id_utilisateur"],)).fetchone()
    if a is None:
        raise HTTPException(403, "Réservé à l'équipe MboaRide")
    return {**u, "role_admin": a["role"]}


def exiger(*roles: str):
    """Dépendance : l'administrateur a l'un de ces rôles (super_admin passe partout)."""
    def dependance(a: dict = Depends(admin_courant)) -> dict:
        if a["role_admin"] != "super_admin" and a["role_admin"] not in roles:
            raise HTTPException(403, "Votre rôle ne donne pas accès à cette partie de la console")
        return a
    return dependance


SUPPORT = Depends(exiger("support"))
FINANCE = Depends(exiger("finance"))
SUPER = Depends(exiger())


def journaliser(conn, a: dict, action: str, cible_type: str, cible_id, resume: str, **details) -> None:
    conn.execute(
        "INSERT INTO journal_admin (id_admin, action, cible_type, cible_id, resume, details) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        (a["id_utilisateur"], action, cible_type, None if cible_id is None else str(cible_id), resume[:300],
         Jsonb(details, dumps=lambda o: json.dumps(o, default=str, ensure_ascii=False))))


def _page(page: int, taille: int) -> tuple[int, int, int]:
    page, taille = max(1, page), max(1, min(taille, 100))
    return page, taille, (page - 1) * taille


def _paginer(conn, select: str, depuis: str, where: list[str], params: dict, ordre: str,
             page: int, taille: int) -> dict:
    page, taille, decalage = _page(page, taille)
    clause = (" WHERE " + " AND ".join(where)) if where else ""
    total = conn.execute(f"SELECT count(*) n {depuis}{clause}", params).fetchone()["n"]
    lignes = conn.execute(f"{select} {depuis}{clause} ORDER BY {ordre} LIMIT %(lim)s OFFSET %(off)s",
                          {**params, "lim": taille, "off": decalage}).fetchall()
    return {"total": total, "page": page, "taille": taille, "lignes": lignes}


def _motif_texte(q: str | None) -> str | None:
    q = (q or "").strip()
    return f"%{q}%" if q else None


# --- Session de la console ------------------------------------------------------------------

@router.get("/moi")
def moi(a: dict = Depends(admin_courant)) -> dict:
    return {"id_utilisateur": a["id_utilisateur"], "prenom": a["prenom"], "nom": a["nom"], "email": a["email"],
            "role": a["role_admin"], "modules": MODULES[a["role_admin"]]}


@router.get("/demo/comptes")
def comptes_demo(conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    """Administrateurs proposés à la connexion de démonstration (si l'en-tête X-Utilisateur est permis)."""
    if not config.DEMO_AUTH:
        raise HTTPException(404, "Connexion de démonstration désactivée")
    return conn.execute(
        "SELECT a.id_utilisateur, u.prenom, u.nom, a.role FROM administrateur a "
        "JOIN utilisateur u USING (id_utilisateur) WHERE a.actif ORDER BY a.role, u.prenom").fetchall()


# --- Tableau de bord -------------------------------------------------------------------------

@router.get("/tableau-de-bord")
def tableau_de_bord(jours: int = Query(30, ge=1, le=365), a: dict = Depends(admin_courant),
                    conn: psycopg.Connection = Depends(get_conn)) -> dict:
    p = {"depuis": date.today() - timedelta(days=jours - 1)}
    indicateurs = conn.execute(
        """SELECT
             (SELECT count(*) FROM utilisateur) AS utilisateurs,
             (SELECT count(*) FROM utilisateur WHERE cree_le >= %(depuis)s) AS nouveaux_utilisateurs,
             (SELECT count(*) FROM utilisateur WHERE est_conducteur AND statut_agrement = 'actif') AS conducteurs_agrees,
             (SELECT count(*) FROM utilisateur WHERE suspendu_le IS NOT NULL) AS comptes_suspendus,
             (SELECT count(DISTINCT id_utilisateur) FROM document_agrement WHERE statut = 'depose') AS agrements_en_attente,
             (SELECT count(*) FROM trajet WHERE statut = 'actif'
                 AND (date_unique IS NULL OR date_unique >= CURRENT_DATE)) AS trajets_actifs,
             (SELECT count(*) FROM reservation WHERE cree_le >= %(depuis)s) AS reservations,
             (SELECT count(*) FROM reservation WHERE cree_le >= %(depuis)s AND statut = 'annulee') AS reservations_annulees,
             (SELECT count(*) FROM course WHERE statut <> 'reglee') AS courses_en_cours,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement
                 WHERE statut IN ('reussi', 'rembourse') AND paye_le >= %(depuis)s) AS encaisse_fcfa,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM commission_mboaride WHERE preleve_le >= %(depuis)s) AS commission_fcfa,
             (SELECT coalesce(sum(montant_verse_fcfa), 0) FROM paiement WHERE verse_le >= %(depuis)s) AS verse_fcfa,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement WHERE statut = 'reussi' AND verse_le IS NULL) AS sequestre_fcfa,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement
                 WHERE statut = 'rembourse' AND rembourse_le >= %(depuis)s) AS rembourse_fcfa,
             (SELECT count(*) FROM paiement WHERE statut = 'echoue' AND initie_le >= %(depuis)s) AS paiements_echoues,
             (SELECT coalesce(sum(solde_fcfa), 0) FROM portefeuille) AS soldes_portefeuilles_fcfa,
             (SELECT count(*) FROM evaluation WHERE signalement_grave AND cree_le >= %(depuis)s) AS signalements_graves,
             (SELECT count(*) FROM evaluation WHERE signalement_grave AND traite_le IS NULL) AS signalements_a_traiter,
             (SELECT round(avg(note), 2) FROM evaluation WHERE cree_le >= %(depuis)s) AS note_moyenne""", p).fetchone()
    serie = conn.execute(
        """SELECT j::date AS jour,
                  (SELECT count(*) FROM utilisateur WHERE cree_le::date = j::date) AS inscriptions,
                  (SELECT count(*) FROM reservation WHERE cree_le::date = j::date AND statut <> 'annulee') AS reservations,
                  (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement
                      WHERE statut IN ('reussi', 'rembourse') AND paye_le::date = j::date) AS encaisse_fcfa,
                  (SELECT coalesce(sum(montant_fcfa), 0) FROM commission_mboaride
                      WHERE preleve_le::date = j::date) AS commission_fcfa
             FROM generate_series(%(depuis)s::date, CURRENT_DATE, interval '1 day') AS j
            ORDER BY 1""", p).fetchall()
    reservations_par_statut = conn.execute(
        "SELECT statut, count(*) n FROM reservation WHERE cree_le >= %(depuis)s GROUP BY statut ORDER BY n DESC",
        p).fetchall()
    trajets_par_type = conn.execute(
        "SELECT type_trajet, count(*) n FROM trajet WHERE statut = 'actif' GROUP BY type_trajet ORDER BY n DESC"
    ).fetchall()
    a_traiter = {
        "agrements": conn.execute(
            """SELECT u.id_utilisateur, u.prenom, u.nom, count(*) AS pieces, min(d.depose_le) AS depuis
                 FROM document_agrement d JOIN utilisateur u USING (id_utilisateur)
                WHERE d.statut = 'depose' GROUP BY u.id_utilisateur ORDER BY depuis LIMIT 5""").fetchall(),
        "signalements": conn.execute(
            """SELECT e.id_evaluation, e.note, e.commentaire, e.cree_le,
                      ev.id_utilisateur AS id_evalue, ev.prenom || ' ' || ev.nom AS evalue,
                      au.prenom || ' ' || au.nom AS auteur
                 FROM evaluation e JOIN utilisateur ev ON ev.id_utilisateur = e.id_evalue
                 JOIN utilisateur au ON au.id_utilisateur = e.id_auteur
                WHERE e.signalement_grave AND e.traite_le IS NULL ORDER BY e.cree_le LIMIT 5""").fetchall(),
        "paiements_echoues": conn.execute(
            """SELECT p.id_paiement, p.reference_transaction, p.montant_fcfa, p.motif_echec, p.initie_le,
                      u.prenom || ' ' || u.nom AS passager
                 FROM paiement p JOIN reservation r USING (id_reservation)
                 JOIN demande d USING (id_demande) JOIN utilisateur u ON u.id_utilisateur = d.id_demandeur
                WHERE p.statut = 'echoue' ORDER BY p.initie_le DESC NULLS LAST LIMIT 5""").fetchall(),
    }
    return {"jours": jours, "depuis": p["depuis"], "indicateurs": indicateurs, "serie": serie,
            "reservations_par_statut": reservations_par_statut, "trajets_par_type": trajets_par_type,
            "a_traiter": a_traiter}


# --- Utilisateurs ----------------------------------------------------------------------------

@router.get("/utilisateurs")
def utilisateurs(q: str | None = None,
                 role: Literal["conducteur", "passager", "admin"] | None = None,
                 statut: Literal["actif", "suspendu", "agrement_en_attente"] | None = None,
                 page: int = 1, taille: int = 25, a: dict = SUPPORT,
                 conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where, params = [], {"motif": _motif_texte(q)}
    if params["motif"]:
        where.append("(u.prenom ILIKE %(motif)s OR u.nom ILIKE %(motif)s OR (u.prenom || ' ' || u.nom) ILIKE %(motif)s"
                     " OR u.email ILIKE %(motif)s OR u.telephone ILIKE %(motif)s)")
    where += {"conducteur": ["u.est_conducteur"], "passager": ["NOT u.est_conducteur"],
              "admin": ["ad.role IS NOT NULL"], None: []}[role]
    where += {"actif": ["u.suspendu_le IS NULL"], "suspendu": ["u.suspendu_le IS NOT NULL"],
              "agrement_en_attente": ["u.statut_agrement = 'en_verification'"], None: []}[statut]
    return _paginer(
        conn,
        """SELECT u.id_utilisateur, u.prenom, u.nom, u.email, u.telephone, u.est_conducteur, u.statut_agrement,
                  u.cree_le, u.suspendu_le, ad.role AS role_admin,
                  (SELECT count(*) FROM reservation r JOIN demande d USING (id_demande)
                    WHERE d.id_demandeur = u.id_utilisateur AND r.statut <> 'annulee') AS trajets_passager,
                  (SELECT count(*) FROM trajet t WHERE t.id_conducteur = u.id_utilisateur) AS trajets_conducteur""",
        "FROM utilisateur u LEFT JOIN administrateur ad ON ad.id_utilisateur = u.id_utilisateur AND ad.actif",
        where, params, "u.cree_le DESC, u.id_utilisateur DESC", page, taille)


def _utilisateur(conn, uid: int) -> dict:
    u = conn.execute("SELECT * FROM utilisateur WHERE id_utilisateur = %s", (uid,)).fetchone()
    if u is None:
        raise HTTPException(404, "Utilisateur introuvable")
    return u


@router.get("/utilisateurs/{uid}")
def fiche_utilisateur(uid: int, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    u = _utilisateur(conn, uid)
    u.pop("mot_de_passe_hache", None)
    role = conn.execute("SELECT role FROM administrateur WHERE id_utilisateur = %s AND actif", (uid,)).fetchone()
    solde = conn.execute("SELECT solde_fcfa FROM portefeuille WHERE id_utilisateur = %s", (uid,)).fetchone()
    note = conn.execute("SELECT round(avg(note), 2) moyenne, count(*) n, count(*) FILTER (WHERE signalement_grave) "
                        "graves FROM evaluation WHERE id_evalue = %s", (uid,)).fetchone()
    return {
        "utilisateur": u,
        "role_admin": role["role"] if role else None,
        "organisations": conn.execute(
            "SELECT o.id_organisation, o.nom, a.role FROM appartenance a JOIN organisation o USING (id_organisation) "
            "WHERE a.id_utilisateur = %s ORDER BY o.nom", (uid,)).fetchall(),
        "vehicules": conn.execute("SELECT marque_modele, immatriculation, places_passagers, climatise "
                                  "FROM vehicule WHERE id_proprietaire = %s", (uid,)).fetchall(),
        "documents": _documents(conn, uid),
        "portefeuille": {
            "solde_fcfa": solde["solde_fcfa"] if solde else 0,
            "mouvements": conn.execute(
                "SELECT type, montant_fcfa, solde_apres_fcfa, libelle, cree_le FROM mouvement_portefeuille "
                "WHERE id_utilisateur = %s ORDER BY cree_le DESC, id_mouvement DESC LIMIT 10", (uid,)).fetchall(),
        },
        "evaluations": {"note_moyenne": note["moyenne"], "nombre": note["n"], "signalements_graves": note["graves"],
                        "dernieres": conn.execute(
                            "SELECT e.note, e.commentaire, e.signalement_grave, e.cree_le, "
                            "au.prenom || ' ' || au.nom AS auteur FROM evaluation e "
                            "JOIN utilisateur au ON au.id_utilisateur = e.id_auteur "
                            "WHERE e.id_evalue = %s ORDER BY e.cree_le DESC LIMIT 5", (uid,)).fetchall()},
        "trajets_conducteur": conn.execute(
            "SELECT id_trajet, depart_libelle, arrivee_libelle, to_char(heure_depart, 'HH24:MI') heure, statut, "
            "date_unique, jours_semaine FROM trajet WHERE id_conducteur = %s ORDER BY id_trajet DESC LIMIT 10",
            (uid,)).fetchall(),
        "reservations": conn.execute(
            """SELECT r.id_reservation, r.date_trajet, r.statut, r.prix_fcfa, t.depart_libelle, t.arrivee_libelle,
                      c.prenom || ' ' || c.nom AS conducteur, p.statut AS paiement
                 FROM reservation r JOIN demande d USING (id_demande) JOIN trajet t USING (id_trajet)
                 JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur
                 LEFT JOIN paiement p USING (id_reservation)
                WHERE d.id_demandeur = %s ORDER BY r.date_trajet DESC, r.id_reservation DESC LIMIT 10""",
            (uid,)).fetchall(),
        "journal": conn.execute(
            "SELECT j.action, j.resume, j.cree_le, ad.prenom || ' ' || ad.nom AS par FROM journal_admin j "
            "LEFT JOIN utilisateur ad ON ad.id_utilisateur = j.id_admin "
            "WHERE j.cible_type = 'utilisateur' AND j.cible_id = %s ORDER BY j.cree_le DESC LIMIT 10",
            (str(uid),)).fetchall(),
    }


class Motif(BaseModel):
    motif: str = Field(min_length=3, max_length=300)


class Suspension(Motif):
    retirer_trajets: bool = True


@router.post("/utilisateurs/{uid}/suspension")
def suspendre(uid: int, body: Suspension, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    u = _utilisateur(conn, uid)
    if uid == a["id_utilisateur"]:
        raise HTTPException(409, "Vous ne pouvez pas suspendre votre propre compte")
    if u["suspendu_le"] is not None:
        raise HTTPException(409, "Ce compte est déjà suspendu")
    return {"id_utilisateur": uid, "suspendu": True, **_suspendre_compte(conn, a, u, body.motif, body.retirer_trajets)}


def _retirer_trajets_de(conn, uid: int) -> tuple[int, int]:
    """Retire les trajets en ligne d'un conducteur ; renvoie (trajets, réservations annulées)."""
    retires = passagers = 0
    for t in conn.execute("SELECT id_trajet FROM trajet WHERE id_conducteur = %s AND statut = 'actif'",
                          (uid,)).fetchall():
        passagers += retirer_trajet_entier(conn, t["id_trajet"], "conducteur indisponible")
        retires += 1
    return retires, passagers


def _suspendre_compte(conn, a: dict, u: dict, motif: str, retirer_trajets: bool) -> dict:
    uid = u["id_utilisateur"]
    cible_admin = conn.execute("SELECT 1 FROM administrateur WHERE id_utilisateur = %s AND actif", (uid,)).fetchone()
    if cible_admin and a["role_admin"] != "super_admin":
        raise HTTPException(403, "Seul un super administrateur peut suspendre un membre de l'équipe")
    conn.execute("UPDATE utilisateur SET suspendu_le = now(), motif_suspension = %s WHERE id_utilisateur = %s",
                 (motif, uid))
    retires, passagers = _retirer_trajets_de(conn, uid) if retirer_trajets else (0, 0)
    notifier(conn, uid, "administration", f"Votre compte MboaRide est suspendu : {motif}")
    journaliser(conn, a, "suspension", "utilisateur", uid, f"Compte de {u['prenom']} {u['nom']} suspendu : {motif}",
                trajets_retires=retires, reservations_annulees=passagers)
    return {"trajets_retires": retires, "reservations_annulees": passagers}


@router.post("/utilisateurs/{uid}/reactivation")
def reactiver(uid: int, body: Motif, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    u = _utilisateur(conn, uid)
    if u["suspendu_le"] is None:
        raise HTTPException(409, "Ce compte n'est pas suspendu")
    conn.execute("UPDATE utilisateur SET suspendu_le = NULL, motif_suspension = NULL WHERE id_utilisateur = %s", (uid,))
    notifier(conn, uid, "administration", "Votre compte MboaRide est de nouveau actif.")
    journaliser(conn, a, "reactivation", "utilisateur", uid, f"Compte de {u['prenom']} {u['nom']} réactivé : {body.motif}")
    return {"id_utilisateur": uid, "suspendu": False}


# --- Agréments -------------------------------------------------------------------------------

def _documents(conn, uid: int) -> list[dict]:
    deposes = {r["type_document"]: r for r in conn.execute(
        """SELECT d.type_document, d.statut, d.depose_le, d.expire_le, d.motif_refus, d.verifie_le,
                  d.chemin_fichier, v.prenom || ' ' || v.nom AS verifie_par
             FROM document_agrement d LEFT JOIN utilisateur v ON v.id_utilisateur = d.verifie_par
            WHERE d.id_utilisateur = %s""", (uid,)).fetchall()}
    out = []
    for code, libelle in PIECES.items():
        d = deposes.get(code)
        out.append({"type": code, "libelle": libelle, "statut": d["statut"] if d else "manquant",
                    **({**{k: d[k] for k in ("depose_le", "expire_le", "motif_refus", "verifie_le", "verifie_par")},
                        **pieces.description(d["chemin_fichier"])} if d else {})})
    return out


@router.get("/agrements")
def agrements(statut: Literal["en_attente", "actif", "suspendu", "tous"] = "en_attente", q: str | None = None,
              page: int = 1, taille: int = 25, a: dict = SUPPORT,
              conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where = {"en_attente": ["EXISTS (SELECT 1 FROM document_agrement d WHERE d.id_utilisateur = u.id_utilisateur "
                            "AND d.statut = 'depose')"],
             "actif": ["u.statut_agrement = 'actif'"], "suspendu": ["u.statut_agrement = 'suspendu'"],
             "tous": ["(u.est_conducteur OR EXISTS (SELECT 1 FROM document_agrement d "
                      "WHERE d.id_utilisateur = u.id_utilisateur))"]}[statut]
    params = {"motif": _motif_texte(q)}
    if params["motif"]:
        where.append("((u.prenom || ' ' || u.nom) ILIKE %(motif)s OR u.telephone ILIKE %(motif)s)")
    res = _paginer(
        conn,
        """SELECT u.id_utilisateur, u.prenom, u.nom, u.telephone, u.email, u.statut_agrement, u.date_agrement,
                  (SELECT min(depose_le) FROM document_agrement d WHERE d.id_utilisateur = u.id_utilisateur
                      AND d.statut = 'depose') AS en_attente_depuis""",
        "FROM utilisateur u", where, params, "en_attente_depuis NULLS LAST, u.id_utilisateur", page, taille)
    for ligne in res["lignes"]:
        ligne["documents"] = _documents(conn, ligne["id_utilisateur"])
        ligne["vehicule"] = conn.execute(
            "SELECT marque_modele, immatriculation, places_passagers FROM vehicule WHERE id_proprietaire = %s "
            "ORDER BY id_vehicule LIMIT 1", (ligne["id_utilisateur"],)).fetchone()
    return res


class Decision(BaseModel):
    decision: Literal["valide", "refuse"]
    motif: str | None = Field(default=None, max_length=300)
    expire_le: date | None = None

    @model_validator(mode="after")
    def _coherence(self):
        if self.decision == "refuse" and not (self.motif or "").strip():
            raise ValueError("Indiquez le motif du refus : il est envoyé au conducteur")
        if self.decision == "valide" and self.expire_le is not None and self.expire_le <= date.today():
            raise ValueError("La date de validité doit être dans le futur")
        return self


def _recalculer_agrement(conn, u: dict) -> str:
    """Statut d'agrément d'après les pièces : actif quand les quatre sont valides et non expirées."""
    if u["statut_agrement"] == "suspendu":
        return "suspendu"                       # seule une décision explicite lève la suspension
    valides = conn.execute(
        "SELECT count(*) n FROM document_agrement WHERE id_utilisateur = %s AND statut = 'valide' "
        "AND (expire_le IS NULL OR expire_le >= CURRENT_DATE)", (u["id_utilisateur"],)).fetchone()["n"]
    statut = "actif" if valides == len(PIECES) else "en_verification"
    conn.execute(
        """UPDATE utilisateur SET est_conducteur = TRUE, statut_agrement = %s,
                  date_agrement = CASE WHEN %s = 'actif' THEN coalesce(date_agrement, CURRENT_DATE)
                                       ELSE date_agrement END
            WHERE id_utilisateur = %s""", (statut, statut, u["id_utilisateur"]))
    if statut == "actif" and u["statut_agrement"] != "actif":
        notifier(conn, u["id_utilisateur"], "administration",
                 "Bonne nouvelle : vos pièces sont validées, votre agrément est actif. "
                 "Vous pouvez publier vos trajets.")
    return statut


@router.post("/agrements/{uid}/documents/{type_document}")
def verifier_piece(uid: int, type_document: str, body: Decision, a: dict = SUPPORT,
                   conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if type_document not in PIECES:
        raise HTTPException(404, f"Pièce inconnue : {type_document}")
    u = _utilisateur(conn, uid)
    d = conn.execute("SELECT * FROM document_agrement WHERE id_utilisateur = %s AND type_document = %s",
                     (uid, type_document)).fetchone()
    if d is None:
        raise HTTPException(404, "Cette pièce n'a pas été déposée")
    libelle = PIECES[type_document]
    if body.decision == "valide":
        expire = body.expire_le or date.today() + timedelta(days=30 * parametres.valeur("agrement_validite_mois"))
        conn.execute("UPDATE document_agrement SET statut = 'valide', expire_le = %s, motif_refus = NULL, "
                     "verifie_par = %s, verifie_le = now() WHERE id_document = %s",
                     (expire, a["id_utilisateur"], d["id_document"]))
        resume = f"{libelle} de {u['prenom']} {u['nom']} validée (jusqu'au {expire:%d/%m/%Y})"
        restantes = len(PIECES) - conn.execute(
            "SELECT count(*) n FROM document_agrement WHERE id_utilisateur = %s AND statut = 'valide' "
            "AND (expire_le IS NULL OR expire_le >= CURRENT_DATE)", (uid,)).fetchone()["n"]
        if restantes:
            notifier(conn, uid, "administration",
                     f"{libelle} validée. Il reste {restantes} pièce{'s' if restantes > 1 else ''} "
                     f"à faire valider ou à déposer pour activer votre agrément.")
    else:
        conn.execute("UPDATE document_agrement SET statut = 'refuse', motif_refus = %s, verifie_par = %s, "
                     "verifie_le = now() WHERE id_document = %s", (body.motif, a["id_utilisateur"], d["id_document"]))
        notifier(conn, uid, "administration",
                 f"{libelle} refusée : {body.motif}. Déposez-la de nouveau depuis l'espace conducteur.")
        resume = f"{libelle} de {u['prenom']} {u['nom']} refusée : {body.motif}"
    statut = _recalculer_agrement(conn, u)
    journaliser(conn, a, f"piece_{body.decision}", "utilisateur", uid, resume, piece=type_document,
                statut_agrement=statut)
    return {"id_utilisateur": uid, "statut_agrement": statut, "documents": _documents(conn, uid)}


@router.get("/agrements/{uid}/documents/{type_document}/fichier")
def fichier_piece(uid: int, type_document: str, a: dict = SUPPORT,
                  conn: psycopg.Connection = Depends(get_conn)) -> Response:
    """Le fichier déposé par le conducteur, pour que l'administrateur le vérifie."""
    if type_document not in PIECES:
        raise HTTPException(404, f"Pièce inconnue : {type_document}")
    u = _utilisateur(conn, uid)
    d = conn.execute("SELECT chemin_fichier FROM document_agrement WHERE id_utilisateur = %s AND type_document = %s",
                     (uid, type_document)).fetchone()
    if d is None:
        raise HTTPException(404, "Cette pièce n'a pas été déposée")
    lu = pieces.lire(d["chemin_fichier"])
    if lu is None:
        raise HTTPException(404, "Aucun fichier pour cette pièce : elle a été déposée avant l'envoi de fichiers")
    contenu, mime = lu
    journaliser(conn, a, "piece_consultee", "utilisateur", uid,
                f"{PIECES[type_document]} de {u['prenom']} {u['nom']} consultée", piece=type_document)
    return Response(contenu, media_type=mime, headers={"Cache-Control": "private, no-store",
                                                       "X-Content-Type-Options": "nosniff"})


class ChangementAgrement(Motif):
    statut: Literal["actif", "suspendu"]
    retirer_trajets: bool = True


@router.post("/agrements/{uid}/statut")
def changer_agrement(uid: int, body: ChangementAgrement, a: dict = SUPPORT,
                     conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Suspendre l'agrément d'un conducteur, ou le rétablir (après un signalement, par exemple)."""
    u = _utilisateur(conn, uid)
    if body.statut == u["statut_agrement"]:
        raise HTTPException(409, "L'agrément a déjà ce statut")
    retires = passagers = 0
    if body.statut == "suspendu":
        conn.execute("UPDATE utilisateur SET statut_agrement = 'suspendu' WHERE id_utilisateur = %s", (uid,))
        if body.retirer_trajets:
            retires, passagers = _retirer_trajets_de(conn, uid)
        notifier(conn, uid, "administration", f"Votre agrément de conducteur est suspendu : {body.motif}")
    else:
        conn.execute("UPDATE utilisateur SET statut_agrement = 'en_verification' WHERE id_utilisateur = %s", (uid,))
        if _recalculer_agrement(conn, {**u, "statut_agrement": "en_verification"}) != "actif":
            raise HTTPException(409, "Les quatre pièces doivent être valides pour rétablir l'agrément")
    journaliser(conn, a, f"agrement_{body.statut}", "utilisateur", uid,
                f"Agrément de {u['prenom']} {u['nom']} : {body.statut} ({body.motif})",
                trajets_retires=retires, reservations_annulees=passagers)
    return {"id_utilisateur": uid, "statut_agrement": body.statut, "trajets_retires": retires,
            "reservations_annulees": passagers}


# --- Trajets et courses ----------------------------------------------------------------------

ETAT_TRAJET = ("CASE WHEN t.statut = 'annule' THEN 'retire' "
               "WHEN t.statut = 'termine' OR t.date_unique < CURRENT_DATE THEN 'passe' ELSE 'actif' END")


@router.get("/trajets")
def trajets(etat: Literal["actif", "retire", "passe"] | None = None,
            type_trajet: Literal["urbain", "interurbain"] | None = None, q: str | None = None,
            page: int = 1, taille: int = 25, a: dict = SUPPORT,
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where, params = [], {"motif": _motif_texte(q), "etat": etat, "type": type_trajet}
    if etat:
        where.append(f"{ETAT_TRAJET} = %(etat)s")
    if type_trajet:
        where.append("t.type_trajet = %(type)s")
    if params["motif"]:
        where.append("(t.depart_libelle ILIKE %(motif)s OR t.arrivee_libelle ILIKE %(motif)s "
                     "OR (c.prenom || ' ' || c.nom) ILIKE %(motif)s)")
    return _paginer(
        conn,
        f"""SELECT t.id_trajet, t.type_trajet, t.depart_libelle, t.arrivee_libelle,
                   to_char(t.heure_depart, 'HH24:MI') AS heure_depart, t.date_unique, t.jours_semaine,
                   t.places_offertes, t.statut, {ETAT_TRAJET} AS etat, t.cree_le,
                   c.id_utilisateur AS id_conducteur, c.prenom || ' ' || c.nom AS conducteur,
                   (SELECT count(*) FROM reservation r WHERE r.id_trajet = t.id_trajet AND r.statut = 'confirmee'
                       AND r.date_trajet >= CURRENT_DATE) AS reservations_a_venir,
                   (SELECT count(*) FROM reservation r WHERE r.id_trajet = t.id_trajet
                       AND r.statut <> 'annulee') AS reservations""",
        "FROM trajet t JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur",
        where, params, "t.id_trajet DESC", page, taille)


@router.get("/trajets/{id_trajet}")
def fiche_trajet(id_trajet: int, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    t = conn.execute(
        f"""SELECT t.*, {ETAT_TRAJET} AS etat, to_char(t.heure_depart, 'HH24:MI') AS heure,
                   c.prenom || ' ' || c.nom AS conducteur, c.telephone AS telephone_conducteur,
                   v.marque_modele, v.immatriculation
              FROM trajet t JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur
              JOIN vehicule v ON v.id_vehicule = t.id_vehicule
             WHERE t.id_trajet = %s""", (id_trajet,)).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    t.pop("heure_depart", None)
    return {
        "trajet": t,
        "reservations": conn.execute(
            """SELECT r.id_reservation, r.date_trajet, r.statut, r.prix_fcfa, r.niveau_cercle,
                      to_char(r.heure_prise_en_charge, 'HH24:MI') AS prise_en_charge, r.fin_validee_le,
                      u.id_utilisateur AS id_passager, u.prenom || ' ' || u.nom AS passager,
                      p.id_paiement, p.statut AS paiement, p.moyen
                 FROM reservation r JOIN demande d USING (id_demande)
                 JOIN utilisateur u ON u.id_utilisateur = d.id_demandeur
                 LEFT JOIN paiement p USING (id_reservation)
                WHERE r.id_trajet = %s ORDER BY r.date_trajet DESC, r.id_reservation""", (id_trajet,)).fetchall(),
        "dates_annulees": conn.execute(
            "SELECT date_trajet, motif FROM indisponibilite_trajet WHERE id_trajet = %s ORDER BY date_trajet DESC",
            (id_trajet,)).fetchall(),
        "courses": conn.execute(
            "SELECT date_trajet, statut, demarree_le, arrivee_le, reglee_le FROM course WHERE id_trajet = %s "
            "ORDER BY date_trajet DESC", (id_trajet,)).fetchall(),
    }


@router.post("/trajets/{id_trajet}/retrait")
def retirer(id_trajet: int, body: Motif, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    t = conn.execute("SELECT * FROM trajet WHERE id_trajet = %s", (id_trajet,)).fetchone()
    if t is None:
        raise HTTPException(404, "Trajet introuvable")
    if t["statut"] == "annule":
        raise HTTPException(409, "Ce trajet est déjà retiré")
    passagers = retirer_trajet_entier(conn, id_trajet, "trajet retiré par MboaRide")
    notifier(conn, t["id_conducteur"], "administration",
             f"L'équipe MboaRide a retiré votre trajet {t['depart_libelle']} → {t['arrivee_libelle']} : {body.motif}")
    journaliser(conn, a, "retrait_trajet", "trajet", id_trajet,
                f"Trajet {t['depart_libelle']} → {t['arrivee_libelle']} retiré : {body.motif}",
                reservations_annulees=passagers)
    return {"id_trajet": id_trajet, "etat": "retire", "reservations_annulees": passagers}


@router.get("/courses")
def courses(statut: Literal["en_cours", "arrivee", "reglee"] | None = None, page: int = 1, taille: int = 25,
            a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where = ["co.statut = %(statut)s"] if statut else []
    return _paginer(
        conn,
        """SELECT co.id_trajet, co.date_trajet, co.statut, co.demarree_le, co.arrivee_le, co.reglee_le,
                  t.depart_libelle, t.arrivee_libelle, c.prenom || ' ' || c.nom AS conducteur,
                  (SELECT count(*) FROM reservation r WHERE r.id_trajet = co.id_trajet
                      AND r.date_trajet = co.date_trajet AND r.statut <> 'annulee') AS passagers,
                  (SELECT count(*) FROM reservation r WHERE r.id_trajet = co.id_trajet
                      AND r.date_trajet = co.date_trajet AND r.fin_validee_le IS NOT NULL) AS fins_validees""",
        "FROM course co JOIN trajet t USING (id_trajet) JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur",
        where, {"statut": statut}, "co.demarree_le DESC", page, taille)


# --- Paiements et finances -------------------------------------------------------------------

PAIEMENTS_SELECT = """SELECT p.id_paiement, p.reference_transaction, p.montant_fcfa, p.commission_fcfa, p.moyen,
       p.operateur, p.statut, p.initie_le, p.paye_le, p.verse_le, p.montant_verse_fcfa, p.rembourse_le,
       p.motif_echec, r.id_reservation, r.date_trajet, t.id_trajet,
       t.depart_libelle || ' → ' || t.arrivee_libelle AS trajet,
       pa.id_utilisateur AS id_passager, pa.prenom || ' ' || pa.nom AS passager,
       c.id_utilisateur AS id_conducteur, c.prenom || ' ' || c.nom AS conducteur"""
PAIEMENTS_FROM = """FROM paiement p JOIN reservation r USING (id_reservation) JOIN trajet t USING (id_trajet)
       JOIN demande d USING (id_demande) JOIN utilisateur pa ON pa.id_utilisateur = d.id_demandeur
       JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur"""


def _filtres_paiements(statut, moyen, verse, q, du, au) -> tuple[list[str], dict]:
    where, params = [], {"statut": statut, "moyen": moyen, "motif": _motif_texte(q), "du": du, "au": au}
    if statut == "sequestre":
        where.append("p.statut = 'reussi' AND p.verse_le IS NULL")
    elif statut:
        where.append("p.statut = %(statut)s")
    if moyen:
        where.append("p.moyen = %(moyen)s")
    if verse is not None:
        where.append("p.verse_le IS NOT NULL" if verse else "p.verse_le IS NULL")
    if params["motif"]:
        where.append("(p.reference_transaction ILIKE %(motif)s OR (pa.prenom || ' ' || pa.nom) ILIKE %(motif)s "
                     "OR (c.prenom || ' ' || c.nom) ILIKE %(motif)s)")
    if du:
        where.append("coalesce(p.paye_le, p.initie_le)::date >= %(du)s")
    if au:
        where.append("coalesce(p.paye_le, p.initie_le)::date <= %(au)s")
    return where, params


StatutPaiement = Literal["en_attente", "reussi", "echoue", "rembourse", "sequestre"]
Moyen = Literal["mobile_money", "especes", "portefeuille"]


@router.get("/paiements")
def paiements(statut: StatutPaiement | None = None, moyen: Moyen | None = None, verse: bool | None = None,
              q: str | None = None, du: date | None = None, au: date | None = None,
              page: int = 1, taille: int = 25, a: dict = FINANCE,
              conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where, params = _filtres_paiements(statut, moyen, verse, q, du, au)
    return _paginer(conn, PAIEMENTS_SELECT, PAIEMENTS_FROM, where, params,
                    "coalesce(p.paye_le, p.initie_le) DESC NULLS LAST, p.id_paiement DESC", page, taille)


@router.get("/export/paiements.csv")
def export_paiements(statut: StatutPaiement | None = None, moyen: Moyen | None = None, verse: bool | None = None,
                     q: str | None = None, du: date | None = None, au: date | None = None, a: dict = FINANCE,
                     conn: psycopg.Connection = Depends(get_conn)) -> Response:
    """Paiements filtrés, au format CSV lisible par Excel (point-virgule, UTF-8 avec BOM)."""
    where, params = _filtres_paiements(statut, moyen, verse, q, du, au)
    clause = (" WHERE " + " AND ".join(where)) if where else ""
    lignes = conn.execute(f"{PAIEMENTS_SELECT} {PAIEMENTS_FROM}{clause} ORDER BY p.id_paiement", params).fetchall()
    colonnes = ["id_paiement", "reference_transaction", "passager", "conducteur", "trajet", "date_trajet",
                "montant_fcfa", "commission_fcfa", "moyen", "operateur", "statut", "paye_le", "verse_le",
                "montant_verse_fcfa", "rembourse_le", "motif_echec"]
    tampon = io.StringIO()
    w = csv.writer(tampon, delimiter=";", lineterminator="\r\n")
    w.writerow(colonnes)
    for ligne in lignes:
        w.writerow(["" if ligne[c] is None else ligne[c] for c in colonnes])
    journaliser(conn, a, "export", "paiement", None, f"Export CSV de {len(lignes)} paiement(s)",
                filtres={k: v for k, v in params.items() if v is not None})
    return Response("﻿" + tampon.getvalue(), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="paiements-{date.today()}.csv"'})


@router.post("/paiements/{id_paiement}/remboursement")
def rembourser(id_paiement: int, body: Motif, a: dict = FINANCE, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Rembourse un paiement réussi qui n'a pas encore été versé au conducteur (litige, erreur)."""
    p = conn.execute(f"{PAIEMENTS_SELECT}, p.id_reservation AS reservation_payee, r.statut AS statut_reservation "
                     f"{PAIEMENTS_FROM} WHERE p.id_paiement = %s FOR UPDATE OF p", (id_paiement,)).fetchone()
    if p is None:
        raise HTTPException(404, "Paiement introuvable")
    if p["statut"] != "reussi":
        raise HTTPException(409, f"Seul un paiement réussi peut être remboursé (statut : {p['statut']})")
    if p["verse_le"] is not None:
        raise HTTPException(409, "Ce paiement a déjà été versé au conducteur : il ne peut plus être remboursé ici")
    conn.execute("UPDATE paiement SET statut = 'rembourse', rembourse_le = now() WHERE id_paiement = %s", (id_paiement,))
    if p["statut_reservation"] == "confirmee":
        conn.execute("UPDATE reservation SET statut = 'annulee' WHERE id_reservation = %s", (p["id_reservation"],))
    ou = "sur votre compte Mobile Money"
    if p["moyen"] == "portefeuille":
        pf.mouvement(conn, p["id_passager"], "remboursement", p["montant_fcfa"],
                     f"Remboursement par MboaRide (réf. {p['reference_transaction']})",
                     p["reference_transaction"], p["id_reservation"])
        ou = "dans votre portefeuille MboaRide"
    notifier(conn, p["id_passager"], "remboursement",
             f"MboaRide vous a remboursé {p['montant_fcfa']} FCFA {ou} (trajet {p['trajet']} du "
             f"{p['date_trajet']:%d/%m}) : {body.motif}")
    journaliser(conn, a, "remboursement", "paiement", id_paiement,
                f"Paiement {p['reference_transaction']} de {p['passager']} remboursé ({p['montant_fcfa']} FCFA) : "
                f"{body.motif}", montant_fcfa=p["montant_fcfa"], moyen=p["moyen"])
    return {"id_paiement": id_paiement, "statut": "rembourse", "montant_fcfa": p["montant_fcfa"]}


@router.get("/finances")
def finances(du: date | None = None, au: date | None = None, a: dict = FINANCE,
             conn: psycopg.Connection = Depends(get_conn)) -> dict:
    au = au or date.today()
    du = du or au - timedelta(days=29)
    if du > au:
        raise HTTPException(422, "La date de début doit précéder la date de fin")
    p = {"du": du, "au": au}
    totaux = conn.execute(
        """SELECT
             (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement WHERE statut IN ('reussi', 'rembourse')
                 AND paye_le::date BETWEEN %(du)s AND %(au)s) AS encaisse_fcfa,
             (SELECT count(*) FROM paiement WHERE statut IN ('reussi', 'rembourse')
                 AND paye_le::date BETWEEN %(du)s AND %(au)s) AS paiements,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM commission_mboaride
                 WHERE preleve_le::date BETWEEN %(du)s AND %(au)s) AS commission_fcfa,
             (SELECT coalesce(sum(montant_verse_fcfa), 0) FROM paiement
                 WHERE verse_le::date BETWEEN %(du)s AND %(au)s) AS verse_fcfa,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement WHERE statut = 'rembourse'
                 AND rembourse_le::date BETWEEN %(du)s AND %(au)s) AS rembourse_fcfa,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement WHERE statut = 'reussi' AND verse_le IS NULL)
                 AS sequestre_fcfa,
             (SELECT coalesce(sum(solde_fcfa), 0) FROM portefeuille) AS soldes_portefeuilles_fcfa,
             (SELECT coalesce(sum(montant_fcfa), 0) FROM mouvement_portefeuille WHERE type = 'recharge'
                 AND cree_le::date BETWEEN %(du)s AND %(au)s) AS recharges_fcfa,
             (SELECT coalesce(-sum(montant_fcfa), 0) FROM mouvement_portefeuille WHERE type = 'retrait'
                 AND cree_le::date BETWEEN %(du)s AND %(au)s) AS retraits_fcfa""", p).fetchone()
    par_moyen = conn.execute(
        """SELECT moyen, count(*) AS paiements, coalesce(sum(montant_fcfa), 0) AS montant_fcfa
             FROM paiement WHERE statut IN ('reussi', 'rembourse') AND paye_le::date BETWEEN %(du)s AND %(au)s
            GROUP BY moyen ORDER BY montant_fcfa DESC""", p).fetchall()
    serie = conn.execute(
        """SELECT j::date AS jour,
                  (SELECT coalesce(sum(montant_fcfa), 0) FROM paiement WHERE statut IN ('reussi', 'rembourse')
                      AND paye_le::date = j::date) AS encaisse_fcfa,
                  (SELECT coalesce(sum(montant_fcfa), 0) FROM commission_mboaride
                      WHERE preleve_le::date = j::date) AS commission_fcfa,
                  (SELECT coalesce(sum(montant_verse_fcfa), 0) FROM paiement WHERE verse_le::date = j::date) AS verse_fcfa
             FROM generate_series(%(du)s::date, %(au)s::date, interval '1 day') AS j ORDER BY 1""", p).fetchall()
    conducteurs = conn.execute(
        """SELECT c.id_utilisateur, c.prenom || ' ' || c.nom AS conducteur, count(*) AS courses_payees,
                  sum(p.montant_verse_fcfa) AS verse_fcfa, sum(p.montant_fcfa - p.montant_verse_fcfa) AS commission_fcfa
             FROM paiement p JOIN reservation r USING (id_reservation) JOIN trajet t USING (id_trajet)
             JOIN utilisateur c ON c.id_utilisateur = t.id_conducteur
            WHERE p.verse_le::date BETWEEN %(du)s AND %(au)s
            GROUP BY c.id_utilisateur ORDER BY verse_fcfa DESC LIMIT 10""", p).fetchall()
    portefeuilles = conn.execute(
        """SELECT u.id_utilisateur, u.prenom || ' ' || u.nom AS titulaire, pf.solde_fcfa, pf.virement_auto, pf.maj_le
             FROM portefeuille pf JOIN utilisateur u USING (id_utilisateur)
            WHERE pf.solde_fcfa > 0 ORDER BY pf.solde_fcfa DESC LIMIT 10""").fetchall()
    return {"du": du, "au": au, "totaux": totaux, "par_moyen": par_moyen, "serie": serie,
            "conducteurs": conducteurs, "portefeuilles": portefeuilles}


# --- Équipe MboaRide et journal ----------------------------------------------------------------

@router.get("/administrateurs")
def administrateurs(a: dict = SUPER, conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    return conn.execute(
        """SELECT ad.id_utilisateur, u.prenom, u.nom, u.email, u.telephone, ad.role, ad.actif, ad.cree_le,
                  cp.prenom || ' ' || cp.nom AS cree_par
             FROM administrateur ad JOIN utilisateur u USING (id_utilisateur)
             LEFT JOIN utilisateur cp ON cp.id_utilisateur = ad.cree_par
            ORDER BY ad.actif DESC, ad.role, u.prenom""").fetchall()


class Nomination(BaseModel):
    identifiant: str = Field(min_length=3, max_length=120, description="E-mail ou téléphone du compte")
    role: Literal["super_admin", "support", "finance"]


@router.post("/administrateurs", status_code=201)
def nommer(body: Nomination, a: dict = SUPER, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    ident = body.identifiant.strip()
    u = conn.execute("SELECT * FROM utilisateur WHERE lower(email) = lower(%s) OR telephone = %s "
                     "OR replace(telephone, ' ', '') = replace(%s, ' ', '')", (ident, ident, ident)).fetchone()
    if u is None:
        raise HTTPException(404, "Aucun compte MboaRide avec cet e-mail ou ce téléphone")
    conn.execute(
        """INSERT INTO administrateur (id_utilisateur, role, cree_par) VALUES (%s, %s, %s)
           ON CONFLICT (id_utilisateur) DO UPDATE SET role = EXCLUDED.role, actif = TRUE""",
        (u["id_utilisateur"], body.role, a["id_utilisateur"]))
    journaliser(conn, a, "nomination", "utilisateur", u["id_utilisateur"],
                f"{u['prenom']} {u['nom']} nommé·e administrateur ({body.role})", role=body.role)
    return {"id_utilisateur": u["id_utilisateur"], "prenom": u["prenom"], "nom": u["nom"], "role": body.role}


@router.delete("/administrateurs/{uid}")
def retirer_admin(uid: int, a: dict = SUPER, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if uid == a["id_utilisateur"]:
        raise HTTPException(409, "Vous ne pouvez pas retirer vos propres droits")
    ligne = conn.execute("UPDATE administrateur SET actif = FALSE WHERE id_utilisateur = %s AND actif "
                         "RETURNING id_utilisateur", (uid,)).fetchone()
    if ligne is None:
        raise HTTPException(404, "Cet utilisateur n'est pas administrateur")
    u = _utilisateur(conn, uid)
    journaliser(conn, a, "retrait_admin", "utilisateur", uid, f"Droits d'administration de {u['prenom']} {u['nom']} retirés")
    return {"id_utilisateur": uid, "actif": False}


def _filtres_journal(cible_type, cible_id, action, id_admin, du, au, q) -> tuple[list[str], dict]:
    where, params = [], {"cible_type": cible_type, "cible_id": cible_id, "action": action, "id_admin": id_admin,
                         "du": du, "au": au, "motif": _motif_texte(q)}
    for champ in ("cible_type", "cible_id", "action", "id_admin"):
        if params[champ] is not None and params[champ] != "":
            where.append(f"j.{champ} = %({champ})s")
    if du:
        where.append("j.cree_le::date >= %(du)s")
    if au:
        where.append("j.cree_le::date <= %(au)s")
    if params["motif"]:
        where.append("j.resume ILIKE %(motif)s")
    return where, params


JOURNAL_FROM = "FROM journal_admin j LEFT JOIN utilisateur ad ON ad.id_utilisateur = j.id_admin"


@router.get("/journal")
def journal(cible_type: str | None = None, cible_id: str | None = None, action: str | None = None,
            id_admin: int | None = None, du: date | None = None, au: date | None = None, q: str | None = None,
            page: int = 1, taille: int = 50, a: dict = Depends(admin_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where, params = _filtres_journal(cible_type, cible_id, action, id_admin, du, au, q)
    return _paginer(conn, "SELECT j.*, ad.prenom || ' ' || ad.nom AS par", JOURNAL_FROM,
                    where, params, "j.cree_le DESC, j.id_entree DESC", page, taille)


@router.get("/journal/filtres")
def filtres_journal(a: dict = Depends(admin_courant), conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return {
        "actions": [r["action"] for r in conn.execute(
            "SELECT DISTINCT action FROM journal_admin ORDER BY action").fetchall()],
        "auteurs": conn.execute(
            "SELECT DISTINCT u.id_utilisateur, u.prenom || ' ' || u.nom AS nom FROM journal_admin j "
            "JOIN utilisateur u ON u.id_utilisateur = j.id_admin ORDER BY nom").fetchall(),
    }


@router.get("/export/journal.csv")
def export_journal(action: str | None = None, id_admin: int | None = None, du: date | None = None,
                   au: date | None = None, q: str | None = None, a: dict = Depends(admin_courant),
                   conn: psycopg.Connection = Depends(get_conn)) -> Response:
    where, params = _filtres_journal(None, None, action, id_admin, du, au, q)
    clause = (" WHERE " + " AND ".join(where)) if where else ""
    lignes = conn.execute(f"SELECT j.cree_le, ad.prenom || ' ' || ad.nom AS par, j.action, j.cible_type, j.cible_id, "
                          f"j.resume {JOURNAL_FROM}{clause} ORDER BY j.cree_le DESC, j.id_entree DESC", params).fetchall()
    tampon = io.StringIO()
    w = csv.writer(tampon, delimiter=";", lineterminator="\r\n")
    w.writerow(["date", "par", "action", "cible", "id_cible", "resume"])
    for l in lignes:
        w.writerow([l["cree_le"], l["par"] or "ligne de commande", l["action"], l["cible_type"], l["cible_id"] or "",
                    l["resume"]])
    return Response("\ufeff" + tampon.getvalue(), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="journal-{date.today()}.csv"'})


# --- Signalements et évaluations -----------------------------------------------------------------

EVALUATIONS_SELECT = """SELECT e.id_evaluation, e.note, e.commentaire, e.signalement_grave, e.cree_le, e.traite_le,
       e.decision, e.note_traitement, au.id_utilisateur AS id_auteur, au.prenom || ' ' || au.nom AS auteur,
       ev.id_utilisateur AS id_evalue, ev.prenom || ' ' || ev.nom AS evalue, ev.est_conducteur AS evalue_conducteur,
       ev.statut_agrement AS agrement_evalue, ev.suspendu_le AS evalue_suspendu_le,
       t.id_trajet, t.depart_libelle || ' → ' || t.arrivee_libelle AS trajet, r.date_trajet,
       tr.prenom || ' ' || tr.nom AS traite_par"""
EVALUATIONS_FROM = """FROM evaluation e JOIN utilisateur au ON au.id_utilisateur = e.id_auteur
       JOIN utilisateur ev ON ev.id_utilisateur = e.id_evalue
       JOIN reservation r USING (id_reservation) JOIN trajet t USING (id_trajet)
       LEFT JOIN utilisateur tr ON tr.id_utilisateur = e.traite_par"""


@router.get("/evaluations")
def evaluations(filtre: Literal["a_traiter", "signalements", "mauvaises", "toutes"] = "a_traiter",
                q: str | None = None, page: int = 1, taille: int = 25, a: dict = SUPPORT,
                conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where = {"a_traiter": ["e.signalement_grave AND e.traite_le IS NULL"], "signalements": ["e.signalement_grave"],
             "mauvaises": ["e.note <= 2"], "toutes": []}[filtre]
    params = {"motif": _motif_texte(q)}
    if params["motif"]:
        where.append("((au.prenom || ' ' || au.nom) ILIKE %(motif)s OR (ev.prenom || ' ' || ev.nom) ILIKE %(motif)s "
                     "OR e.commentaire ILIKE %(motif)s)")
    ordre = "e.cree_le, e.id_evaluation" if filtre == "a_traiter" else "e.cree_le DESC, e.id_evaluation DESC"
    return _paginer(conn, EVALUATIONS_SELECT, EVALUATIONS_FROM, where, params, ordre, page, taille)


@router.get("/evaluations/statistiques")
def statistiques_evaluations(a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    g = conn.execute(
        """SELECT round(avg(note), 2) AS moyenne, count(*) AS nombre,
                  count(*) FILTER (WHERE signalement_grave AND traite_le IS NULL) AS a_traiter,
                  count(*) FILTER (WHERE signalement_grave) AS signalements
             FROM evaluation""").fetchone()
    repartition = {r["note"]: r["n"] for r in conn.execute(
        "SELECT note, count(*) n FROM evaluation GROUP BY note").fetchall()}
    return {
        **g,
        "repartition": [{"note": n, "n": repartition.get(n, 0)} for n in range(5, 0, -1)],
        "a_surveiller": conn.execute(
            """SELECT v.id_utilisateur, v.prenom || ' ' || v.nom AS conducteur, v.note_moyenne, v.nb_evaluations,
                      v.nb_signalements, u.statut_agrement
                 FROM v_note_conducteur v JOIN utilisateur u USING (id_utilisateur)
                WHERE v.nb_signalements > 0 OR (v.nb_evaluations >= 2 AND v.note_moyenne < 3.5)
                ORDER BY v.nb_signalements DESC, v.note_moyenne NULLS LAST LIMIT 10""").fetchall(),
    }


class Traitement(BaseModel):
    decision: Literal["classe", "avertissement", "suspension_agrement", "suspension_compte"]
    note: str = Field(min_length=3, max_length=300)
    retablir_agrement: bool = False


@router.post("/signalements/{id_evaluation}/traitement")
def traiter_signalement(id_evaluation: int, body: Traitement, a: dict = SUPPORT,
                        conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Décision de l'équipe sur un signalement grave.

    Un signalement grave suspend aussitôt l'agrément du conducteur (déclencheur de la
    base) : « classé » avec `retablir_agrement` le lève si ses pièces sont valides."""
    e = conn.execute(f"{EVALUATIONS_SELECT} {EVALUATIONS_FROM} WHERE e.id_evaluation = %s",
                     (id_evaluation,)).fetchone()
    if e is None:
        raise HTTPException(404, "Évaluation introuvable")
    if not e["signalement_grave"]:
        raise HTTPException(409, "Cette évaluation n'est pas un signalement")
    if e["traite_le"] is not None:
        raise HTTPException(409, "Ce signalement a déjà été traité")
    evalue = _utilisateur(conn, e["id_evalue"])
    effets: dict = {}
    if body.decision in ("classe", "avertissement") and body.retablir_agrement \
            and evalue["statut_agrement"] == "suspendu":
        conn.execute("UPDATE utilisateur SET statut_agrement = 'en_verification' WHERE id_utilisateur = %s",
                     (evalue["id_utilisateur"],))
        effets["statut_agrement"] = _recalculer_agrement(conn, {**evalue, "statut_agrement": "en_verification"})
    if body.decision == "avertissement":
        notifier(conn, evalue["id_utilisateur"], "administration",
                 f"Avertissement de l'équipe MboaRide après un signalement : {body.note}")
    elif body.decision == "suspension_agrement":
        conn.execute("UPDATE utilisateur SET statut_agrement = 'suspendu' WHERE id_utilisateur = %s AND est_conducteur",
                     (evalue["id_utilisateur"],))
        effets["trajets_retires"], effets["reservations_annulees"] = _retirer_trajets_de(conn, evalue["id_utilisateur"])
        effets["statut_agrement"] = "suspendu"
        notifier(conn, evalue["id_utilisateur"], "administration",
                 f"Votre agrément de conducteur est suspendu après un signalement : {body.note}")
    elif body.decision == "suspension_compte":
        if evalue["suspendu_le"] is None:
            effets.update(_suspendre_compte(conn, a, evalue, f"Signalement : {body.note}", True))
    if body.decision == "classe" and effets.get("statut_agrement") == "actif":
        notifier(conn, evalue["id_utilisateur"], "administration",
                 "Le signalement vous concernant a été examiné, sans suite : votre agrément est rétabli.")
    conn.execute("UPDATE evaluation SET traite_le = now(), traite_par = %s, decision = %s, note_traitement = %s "
                 "WHERE id_evaluation = %s", (a["id_utilisateur"], body.decision, body.note, id_evaluation))
    notifier(conn, e["id_auteur"], "administration",
             "Merci pour votre signalement : l'équipe MboaRide l'a examiné et a pris les mesures nécessaires.")
    libelles = {"classe": "classé sans suite", "avertissement": "avertissement", "suspension_agrement":
                "agrément suspendu", "suspension_compte": "compte suspendu"}
    journaliser(conn, a, "signalement", "utilisateur", evalue["id_utilisateur"],
                f"Signalement de {e['auteur']} sur {e['evalue']} : {libelles[body.decision]} ({body.note})",
                id_evaluation=id_evaluation, **effets)
    return {"id_evaluation": id_evaluation, "decision": body.decision, **effets}


# --- Organisations ------------------------------------------------------------------------------

TypeOrganisation = Literal["entreprise", "etablissement_scolaire", "campus", "evenement"]


@router.get("/organisations")
def organisations(q: str | None = None, type_organisation: TypeOrganisation | None = None,
                  abonnement: bool | None = None, page: int = 1, taille: int = 25, a: dict = SUPPORT,
                  conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where, params = [], {"motif": _motif_texte(q), "type": type_organisation, "abonnement": abonnement}
    if params["motif"]:
        where.append("(o.nom ILIKE %(motif)s OR o.ville ILIKE %(motif)s OR o.domaine_email ILIKE %(motif)s)")
    if type_organisation:
        where.append("o.type_organisation = %(type)s")
    if abonnement is not None:
        where.append("o.abonnement_actif = %(abonnement)s")
    return _paginer(
        conn,
        """SELECT o.id_organisation, o.nom, o.type_organisation, o.ville, o.domaine_email, o.code_invitation,
                  o.abonnement_actif, o.tarif_mensuel_fcfa, o.effectif, o.objectif_adoption, o.cree_le,
                  (SELECT count(*) FROM appartenance a WHERE a.id_organisation = o.id_organisation) AS membres,
                  (SELECT count(*) FROM partenariat p WHERE o.id_organisation IN (p.id_organisation_a, p.id_organisation_b))
                      AS partenaires,
                  (SELECT count(*) FROM invitation i WHERE i.id_organisation = o.id_organisation
                      AND i.statut = 'envoyee') AS invitations_en_attente""",
        "FROM organisation o", where, params, "o.nom", page, taille)


def _organisation(conn, id_organisation: int) -> dict:
    o = conn.execute("SELECT * FROM organisation WHERE id_organisation = %s", (id_organisation,)).fetchone()
    if o is None:
        raise HTTPException(404, "Organisation introuvable")
    return o


@router.get("/organisations/{id_organisation}")
def fiche_organisation(id_organisation: int, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    o = _organisation(conn, id_organisation)
    tb = conn.execute("SELECT * FROM v_tableau_bord_organisation WHERE id_organisation = %s",
                      (id_organisation,)).fetchone()
    invitations = conn.execute(
        "SELECT statut, count(*) n FROM invitation WHERE id_organisation = %s GROUP BY statut",
        (id_organisation,)).fetchall()
    partenaires = conn.execute(
        """SELECT o.id_organisation, o.nom, o.type_organisation, p.depuis_le FROM partenariat p
             JOIN organisation o ON o.id_organisation = CASE WHEN p.id_organisation_a = %(id)s
                  THEN p.id_organisation_b ELSE p.id_organisation_a END
            WHERE %(id)s IN (p.id_organisation_a, p.id_organisation_b) ORDER BY o.nom""",
        {"id": id_organisation}).fetchall()
    deja = {p["id_organisation"] for p in partenaires} | {id_organisation}
    return {
        "organisation": o,
        "indicateurs": {**(tb or {}), "adoption": round(tb["membres"] / o["effectif"], 3)
                        if tb and o["effectif"] else None},
        "membres": conn.execute(
            """SELECT u.id_utilisateur, u.prenom || ' ' || u.nom AS nom, u.email, u.telephone, u.est_conducteur,
                      u.statut_agrement, a.role, a.service, a.date_adhesion
                 FROM appartenance a JOIN utilisateur u USING (id_utilisateur)
                WHERE a.id_organisation = %s ORDER BY a.role DESC, u.nom""", (id_organisation,)).fetchall(),
        "partenaires": partenaires,
        "autres_organisations": [r for r in conn.execute(
            "SELECT id_organisation, nom FROM organisation ORDER BY nom").fetchall() if r["id_organisation"] not in deja],
        "invitations": {r["statut"]: r["n"] for r in invitations},
        "dernieres_invitations": conn.execute(
            "SELECT email, statut, envoyee_le, acceptee_le, relances FROM invitation WHERE id_organisation = %s "
            "ORDER BY envoyee_le DESC LIMIT 10", (id_organisation,)).fetchall(),
    }


class OrganisationMaj(BaseModel):
    nom: str | None = Field(default=None, min_length=2, max_length=120)
    type_organisation: TypeOrganisation | None = None
    ville: str | None = Field(default=None, min_length=2, max_length=60)
    domaine_email: str | None = Field(default=None, max_length=120)
    effectif: int | None = Field(default=None, gt=0)
    tarif_mensuel_fcfa: int | None = Field(default=None, ge=0)
    abonnement_actif: bool | None = None
    objectif_adoption: float | None = Field(default=None, ge=0, le=1)


class NouvelleOrganisation(OrganisationMaj):
    nom: str = Field(min_length=2, max_length=120)
    type_organisation: TypeOrganisation = "entreprise"
    ville: str = Field(default="Douala", min_length=2, max_length=60)


def _domaine(conn, domaine: str | None, sauf: int | None = None) -> str | None:
    if domaine is None:
        return None
    d = domaine.strip().lower().removeprefix("@") or None
    if d and conn.execute("SELECT 1 FROM organisation WHERE lower(domaine_email) = %s AND id_organisation <> %s",
                          (d, sauf or 0)).fetchone():
        raise HTTPException(409, f"Le domaine {d} appartient déjà à une autre organisation")
    return d


@router.post("/organisations", status_code=201)
def creer_organisation(body: NouvelleOrganisation, a: dict = SUPPORT,
                       conn: psycopg.Connection = Depends(get_conn)) -> dict:
    champs = body.model_dump(exclude_none=True)
    champs["domaine_email"] = _domaine(conn, body.domaine_email)
    champs["code_invitation"] = secrets.token_hex(4).upper()
    cols = list(champs)
    o = conn.execute(f"INSERT INTO organisation ({', '.join(cols)}) VALUES ({', '.join('%s' for _ in cols)}) "
                     "RETURNING *", [champs[c] for c in cols]).fetchone()
    journaliser(conn, a, "organisation_creee", "organisation", o["id_organisation"], f"Organisation {o['nom']} créée")
    return o


@router.patch("/organisations/{id_organisation}")
def modifier_organisation(id_organisation: int, body: OrganisationMaj, a: dict = SUPPORT,
                          conn: psycopg.Connection = Depends(get_conn)) -> dict:
    o = _organisation(conn, id_organisation)
    champs = body.model_dump(exclude_unset=True)
    if "domaine_email" in champs:
        champs["domaine_email"] = _domaine(conn, champs["domaine_email"], id_organisation)
    if not champs:
        return o
    sets = ", ".join(f"{c} = %s" for c in champs)
    o2 = conn.execute(f"UPDATE organisation SET {sets} WHERE id_organisation = %s RETURNING *",
                      [*champs.values(), id_organisation]).fetchone()
    avant = {c: o[c] for c in champs}
    journaliser(conn, a, "organisation_modifiee", "organisation", id_organisation,
                f"Organisation {o2['nom']} modifiée : {', '.join(champs)}", avant=avant, apres=champs)
    return o2


class Partenaire(BaseModel):
    id_organisation: int


@router.post("/organisations/{id_organisation}/partenaires", status_code=201)
def ajouter_partenaire(id_organisation: int, body: Partenaire, a: dict = SUPPORT,
                       conn: psycopg.Connection = Depends(get_conn)) -> dict:
    o, autre = _organisation(conn, id_organisation), _organisation(conn, body.id_organisation)
    if o["id_organisation"] == autre["id_organisation"]:
        raise HTTPException(422, "Une organisation ne peut pas être sa propre partenaire")
    x, y = sorted((o["id_organisation"], autre["id_organisation"]))
    if conn.execute("INSERT INTO partenariat (id_organisation_a, id_organisation_b) VALUES (%s, %s) "
                    "ON CONFLICT DO NOTHING RETURNING 1", (x, y)).fetchone() is None:
        raise HTTPException(409, "Ces organisations sont déjà partenaires")
    journaliser(conn, a, "partenariat", "organisation", id_organisation, f"{o['nom']} et {autre['nom']} partenaires")
    return {"id_organisation": id_organisation, "partenaire": autre["id_organisation"]}


@router.delete("/organisations/{id_organisation}/partenaires/{id_autre}")
def retirer_partenaire(id_organisation: int, id_autre: int, a: dict = SUPPORT,
                       conn: psycopg.Connection = Depends(get_conn)) -> dict:
    o, autre = _organisation(conn, id_organisation), _organisation(conn, id_autre)
    x, y = sorted((id_organisation, id_autre))
    if conn.execute("DELETE FROM partenariat WHERE id_organisation_a = %s AND id_organisation_b = %s RETURNING 1",
                    (x, y)).fetchone() is None:
        raise HTTPException(404, "Ces organisations ne sont pas partenaires")
    journaliser(conn, a, "fin_partenariat", "organisation", id_organisation,
                f"Fin du partenariat entre {o['nom']} et {autre['nom']}")
    return {"id_organisation": id_organisation, "partenaire_retire": id_autre}


class Membre(BaseModel):
    identifiant: str = Field(min_length=3, max_length=120)
    role: Literal["membre", "administrateur"] = "membre"


def _par_identifiant(conn, ident: str) -> dict:
    ident = ident.strip()
    u = conn.execute("SELECT * FROM utilisateur WHERE lower(email) = lower(%s) "
                     "OR replace(telephone, ' ', '') = replace(%s, ' ', '')", (ident, ident)).fetchone()
    if u is None:
        raise HTTPException(404, "Aucun compte MboaRide avec cet e-mail ou ce téléphone")
    return u


@router.post("/organisations/{id_organisation}/membres", status_code=201)
def ajouter_membre(id_organisation: int, body: Membre, a: dict = SUPPORT,
                   conn: psycopg.Connection = Depends(get_conn)) -> dict:
    o = _organisation(conn, id_organisation)
    u = _par_identifiant(conn, body.identifiant)
    conn.execute("INSERT INTO appartenance (id_utilisateur, id_organisation, role) VALUES (%s, %s, %s) "
                 "ON CONFLICT (id_utilisateur, id_organisation) DO UPDATE SET role = EXCLUDED.role",
                 (u["id_utilisateur"], id_organisation, body.role))
    journaliser(conn, a, "membre_organisation", "organisation", id_organisation,
                f"{u['prenom']} {u['nom']} : {body.role} de {o['nom']}", id_utilisateur=u["id_utilisateur"])
    return {"id_utilisateur": u["id_utilisateur"], "nom": f"{u['prenom']} {u['nom']}", "role": body.role}


@router.delete("/organisations/{id_organisation}/membres/{uid}")
def retirer_membre(id_organisation: int, uid: int, a: dict = SUPPORT,
                   conn: psycopg.Connection = Depends(get_conn)) -> dict:
    o, u = _organisation(conn, id_organisation), _utilisateur(conn, uid)
    if conn.execute("DELETE FROM appartenance WHERE id_utilisateur = %s AND id_organisation = %s RETURNING 1",
                    (uid, id_organisation)).fetchone() is None:
        raise HTTPException(404, "Cette personne n'est pas membre de l'organisation")
    journaliser(conn, a, "membre_retire", "organisation", id_organisation,
                f"{u['prenom']} {u['nom']} retiré·e de {o['nom']}", id_utilisateur=uid)
    return {"id_organisation": id_organisation, "id_utilisateur": uid}


# --- Communication ------------------------------------------------------------------------------

Cible = Literal["tous", "conducteurs", "passagers", "organisation", "utilisateur"]


def _audience(conn, cible: str, id_organisation: int | None, id_utilisateur: int | None) -> list[dict]:
    filtre = {
        "tous": "TRUE",
        "conducteurs": "u.est_conducteur AND u.statut_agrement = 'actif'",
        "passagers": "NOT u.est_conducteur",
        "organisation": "EXISTS (SELECT 1 FROM appartenance a WHERE a.id_utilisateur = u.id_utilisateur "
                        "AND a.id_organisation = %(org)s)",
        "utilisateur": "u.id_utilisateur = %(uid)s",
    }[cible]
    return conn.execute(f"SELECT u.id_utilisateur, u.prenom, u.email FROM utilisateur u "
                        f"WHERE u.suspendu_le IS NULL AND {filtre} ORDER BY u.id_utilisateur",
                        {"org": id_organisation, "uid": id_utilisateur}).fetchall()


@router.get("/communication/audience")
def audience(cible: Cible = "tous", id_organisation: int | None = None, id_utilisateur: int | None = None,
             a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    gens = _audience(conn, cible, id_organisation, id_utilisateur)
    return {"destinataires": len(gens), "avec_email": sum(1 for g in gens if g["email"])}


class NouvelleAnnonce(BaseModel):
    cible: Cible
    id_organisation: int | None = None
    id_utilisateur: int | None = None
    message: str = Field(min_length=5, max_length=400)
    par_email: bool = False
    objet: str = Field(default="Message de l'équipe MboaRide", min_length=3, max_length=120)

    @model_validator(mode="after")
    def _cible(self):
        if self.cible == "organisation" and self.id_organisation is None:
            raise ValueError("Choisissez l'organisation destinataire")
        if self.cible == "utilisateur" and self.id_utilisateur is None:
            raise ValueError("Choisissez l'utilisateur destinataire")
        return self


@router.post("/communication/annonces", status_code=201)
def envoyer_annonce(body: NouvelleAnnonce, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    gens = _audience(conn, body.cible, body.id_organisation, body.id_utilisateur)
    if not gens:
        raise HTTPException(409, "Aucun destinataire pour ce message")
    courriels = {"envoye": 0, "simule": 0, "echec": 0}
    for g in gens:
        notifier(conn, g["id_utilisateur"], "administration", body.message)
        if body.par_email and g["email"]:
            statut = envoyer_courriel(conn, g["email"], body.objet,
                                      f"Bonjour {g['prenom']},\n\n{body.message}\n\nL'équipe MboaRide")
            courriels[statut] += 1
    conn.execute(
        "INSERT INTO annonce (cible, id_organisation, id_utilisateur, message, par_email, destinataires, courriels, "
        "envoye_par) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
        (body.cible, body.id_organisation, body.id_utilisateur, body.message, body.par_email, len(gens),
         sum(courriels.values()), a["id_utilisateur"]))
    journaliser(conn, a, "annonce", "annonce", None,
                f"Message envoyé à {len(gens)} utilisateur(s) ({body.cible}) : {body.message[:120]}",
                courriels=courriels)
    return {"destinataires": len(gens), "courriels": courriels}


@router.get("/communication/annonces")
def annonces(page: int = 1, taille: int = 20, a: dict = SUPPORT, conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return _paginer(
        conn,
        """SELECT an.*, ad.prenom || ' ' || ad.nom AS par, o.nom AS organisation,
                  u.prenom || ' ' || u.nom AS utilisateur""",
        """FROM annonce an LEFT JOIN utilisateur ad ON ad.id_utilisateur = an.envoye_par
           LEFT JOIN organisation o ON o.id_organisation = an.id_organisation
           LEFT JOIN utilisateur u ON u.id_utilisateur = an.id_utilisateur""",
        [], {}, "an.cree_le DESC, an.id_annonce DESC", page, taille)


@router.get("/communication/courriels")
def courriels(statut: Literal["envoye", "simule", "echec"] | None = None, q: str | None = None,
              page: int = 1, taille: int = 25, a: dict = SUPPORT,
              conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where, params = [], {"statut": statut, "motif": _motif_texte(q)}
    if statut:
        where.append("c.statut = %(statut)s")
    if params["motif"]:
        where.append("(c.destinataire ILIKE %(motif)s OR c.sujet ILIKE %(motif)s)")
    return _paginer(conn, "SELECT c.id_courriel, c.destinataire, c.sujet, c.statut, c.erreur, c.cree_le",
                    "FROM courriel c", where, params, "c.cree_le DESC, c.id_courriel DESC", page, taille)


@router.get("/communication/codes")
def codes_envoyes(q: str | None = None, page: int = 1, taille: int = 25, a: dict = SUPPORT,
                  conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Codes de vérification envoyés par l'API Node : canal, destination masquée, validité.

    Le code lui-même n'est jamais conservé en clair (seule son empreinte l'est, côté Node)."""
    if not conn.execute("SELECT to_regclass('public.otp_deliveries') AS t").fetchone()["t"]:
        return {"total": 0, "page": 1, "taille": taille, "lignes": [], "resume": None, "disponible": False}
    where, params = [], {"motif": _motif_texte(q)}
    if params["motif"]:
        where.append("(nu.full_name ILIKE %(motif)s OR nu.email ILIKE %(motif)s OR nu.phone ILIKE %(motif)s)")
    res = _paginer(
        conn,
        """SELECT d.id, d.channel AS canal, d.destination, d.minutes, to_timestamp(d.created_at / 1000.0) AS envoye_le,
                  nu.full_name AS nom, nu.is_verified AS verifie, cn.id_utilisateur""",
        """FROM public.otp_deliveries d JOIN public.users nu ON nu.id = d.user_id
           LEFT JOIN compte_node cn ON cn.id_compte_node = nu.id""",
        where, params, "d.created_at DESC, d.id DESC", page, taille)
    res["resume"] = conn.execute(
        """SELECT count(*) AS total,
                  count(*) FILTER (WHERE channel = 'email') AS email,
                  count(*) FILTER (WHERE channel = 'sms') AS sms,
                  count(*) FILTER (WHERE channel = 'console') AS console,
                  count(*) FILTER (WHERE to_timestamp(created_at / 1000.0) > now() - interval '1 day') AS dernieres_24h,
                  (SELECT channel FROM public.otp_deliveries ORDER BY created_at DESC, id DESC LIMIT 1) AS dernier_canal
             FROM public.otp_deliveries""").fetchone()
    res["disponible"] = True
    return res


# --- Paramètres ---------------------------------------------------------------------------------

def _liste_parametres(conn) -> list[dict]:
    stockes = {r["cle"]: r for r in conn.execute(
        "SELECT p.cle, p.maj_le, u.prenom || ' ' || u.nom AS maj_par FROM parametre p "
        "LEFT JOIN utilisateur u ON u.id_utilisateur = p.maj_par").fetchall()}
    v = parametres.valeurs()
    return [{"cle": cle, **d, "valeur": v[cle], "maj_le": stockes.get(cle, {}).get("maj_le"),
             "maj_par": stockes.get(cle, {}).get("maj_par")} for cle, d in parametres.DEFINITIONS.items()]


@router.get("/parametres")
def lire_parametres(a: dict = Depends(admin_courant), conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    parametres.invalider()
    return _liste_parametres(conn)


class Reglages(BaseModel):
    valeurs: dict[str, int] = Field(min_length=1)


def _controler(valeurs: dict[str, int]) -> None:
    for cle, val in valeurs.items():
        d = parametres.DEFINITIONS.get(cle)
        if d is None:
            raise HTTPException(422, f"Paramètre inconnu : {cle}")
        if not d["min"] <= val <= d["max"]:
            raise HTTPException(422, f"{d['libelle']} : entre {d['min']} et {d['max']} {d['unite']}")


@router.put("/parametres")
def enregistrer_parametres(body: Reglages, a: dict = SUPER, conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    _controler(body.valeurs)
    parametres.invalider()
    avant = parametres.valeurs()
    changes = {c: v for c, v in body.valeurs.items() if avant[c] != v}
    for cle, val in changes.items():
        conn.execute("INSERT INTO parametre (cle, valeur, maj_par) VALUES (%s, %s, %s) ON CONFLICT (cle) DO UPDATE "
                     "SET valeur = EXCLUDED.valeur, maj_le = now(), maj_par = EXCLUDED.maj_par",
                     (cle, val, a["id_utilisateur"]))
    if changes:
        d = parametres.DEFINITIONS
        journaliser(conn, a, "parametres", "parametre", None,
                    "Paramètres modifiés : " + ", ".join(f"{d[c]['libelle']} {avant[c]} → {v} {d[c]['unite']}"
                                                         for c, v in changes.items()),
                    avant={c: avant[c] for c in changes}, apres=changes)
    conn.commit()                 # visible par la relecture du cache, qui passe par sa propre connexion
    parametres.invalider()
    return _liste_parametres(conn)


class Simulation(BaseModel):
    valeurs: dict[str, int] = {}
    distance_km: float = Field(default=10, gt=0, le=500)
    conso_l_100km: float = Field(default=7.5, gt=0, le=30)
    passagers: int = Field(default=2, ge=1, le=8)


@router.post("/parametres/simulation")
def simuler(body: Simulation, a: dict = Depends(admin_courant)) -> dict:
    """Prix d'un trajet type avec les réglages actuels et avec ceux proposés, avant d'enregistrer."""
    _controler(body.valeurs)
    from dataclasses import replace
    from fractions import Fraction

    from mboaride_agents.pricing import quote  # type: ignore
    from .. import moteur

    def devis(v: dict) -> dict:
        pol = replace(moteur.POLITIQUE, fuel_price_per_l=v["prix_carburant_fcfa_l"],
                      commission_rate=Fraction(v["commission_pct"], 100), rounding_step=v["arrondi_fcfa"],
                      min_fare=v["prix_minimum_fcfa"])
        q = quote(pol, shared_distance_m=round(body.distance_km * 1000), detour_m=0,
                  trip_distance_m=round(body.distance_km * 1000), consumption_l_per_100km=body.conso_l_100km,
                  tolls=0, seats_total=8, seats_booked=body.passagers - 1, seats_requested=1, min_price=0,
                  with_commission=True)
        return {"prix_fcfa": q.price, "commission_fcfa": q.commission, "part_conducteur_fcfa": q.price - q.commission,
                "carburant_fcfa": q.fuel_cost}

    actuels = parametres.valeurs()
    return {"actuel": devis(actuels), "propose": devis({**actuels, **body.valeurs})}
