"""Console d'administration de la plateforme : l'équipe MboaRide (pas une organisation).

Rôles (table `administrateur`) :

- `super_admin` : tout, y compris nommer ou retirer d'autres administrateurs ;
- `support`     : utilisateurs, agréments, trajets et courses ;
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
from datetime import date, timedelta
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field, model_validator

from .. import config
from .. import portefeuille as pf
from ..db import get_conn
from ..notifications import notifier
from ..securite import utilisateur_courant
from .conducteur import PIECES, retirer_trajet_entier

router = APIRouter(prefix="/api/admin", tags=["Administration de la plateforme"])

ROLES = ("super_admin", "support", "finance")
MODULES = {
    "super_admin": ["tableau", "utilisateurs", "agrements", "trajets", "paiements", "finances",
                    "administrateurs", "journal"],
    "support": ["tableau", "utilisateurs", "agrements", "trajets", "journal"],
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
                WHERE e.signalement_grave ORDER BY e.cree_le DESC LIMIT 5""").fetchall(),
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
    cible_admin = conn.execute("SELECT 1 FROM administrateur WHERE id_utilisateur = %s AND actif", (uid,)).fetchone()
    if cible_admin and a["role_admin"] != "super_admin":
        raise HTTPException(403, "Seul un super administrateur peut suspendre un membre de l'équipe")
    conn.execute("UPDATE utilisateur SET suspendu_le = now(), motif_suspension = %s WHERE id_utilisateur = %s",
                 (body.motif, uid))
    retires, passagers = 0, 0
    if body.retirer_trajets:
        for t in conn.execute("SELECT id_trajet FROM trajet WHERE id_conducteur = %s AND statut = 'actif'",
                              (uid,)).fetchall():
            passagers += retirer_trajet_entier(conn, t["id_trajet"], "conducteur indisponible")
            retires += 1
    notifier(conn, uid, "administration", f"Votre compte MboaRide est suspendu : {body.motif}")
    journaliser(conn, a, "suspension", "utilisateur", uid, f"Compte de {u['prenom']} {u['nom']} suspendu : {body.motif}",
                trajets_retires=retires, reservations_annulees=passagers)
    return {"id_utilisateur": uid, "suspendu": True, "trajets_retires": retires, "reservations_annulees": passagers}


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
                  v.prenom || ' ' || v.nom AS verifie_par
             FROM document_agrement d LEFT JOIN utilisateur v ON v.id_utilisateur = d.verifie_par
            WHERE d.id_utilisateur = %s""", (uid,)).fetchall()}
    out = []
    for code, libelle in PIECES.items():
        d = deposes.get(code)
        out.append({"type": code, "libelle": libelle, "statut": d["statut"] if d else "manquant",
                    **({k: d[k] for k in ("depose_le", "expire_le", "motif_refus", "verifie_le", "verifie_par")}
                       if d else {})})
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
        expire = body.expire_le or date.today() + timedelta(days=365)
        conn.execute("UPDATE document_agrement SET statut = 'valide', expire_le = %s, motif_refus = NULL, "
                     "verifie_par = %s, verifie_le = now() WHERE id_document = %s",
                     (expire, a["id_utilisateur"], d["id_document"]))
        resume = f"{libelle} de {u['prenom']} {u['nom']} validée (jusqu'au {expire:%d/%m/%Y})"
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
            for t in conn.execute("SELECT id_trajet FROM trajet WHERE id_conducteur = %s AND statut = 'actif'",
                                  (uid,)).fetchall():
                passagers += retirer_trajet_entier(conn, t["id_trajet"], "conducteur indisponible")
                retires += 1
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


@router.get("/journal")
def journal(cible_type: str | None = None, cible_id: str | None = None, action: str | None = None,
            page: int = 1, taille: int = 50, a: dict = Depends(admin_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    where, params = [], {"cible_type": cible_type, "cible_id": cible_id, "action": action}
    for champ in ("cible_type", "cible_id", "action"):
        if params[champ]:
            where.append(f"j.{champ} = %({champ})s")
    return _paginer(
        conn, "SELECT j.*, ad.prenom || ' ' || ad.nom AS par",
        "FROM journal_admin j LEFT JOIN utilisateur ad ON ad.id_utilisateur = j.id_admin",
        where, params, "j.cree_le DESC, j.id_entree DESC", page, taille)
