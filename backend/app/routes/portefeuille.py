"""Portefeuille de l'utilisateur, passager comme conducteur.

  1. Le passager recharge son portefeuille depuis son compte Mobile Money (validation par
     code secret, simulée) et paie ses trajets avec, sans repasser par l'opérateur.
  2. Le paiement d'un trajet reste chez MboaRide jusqu'à la fin de la course ; un trajet
     annulé est remboursé dans le portefeuille s'il avait été payé avec.
  3. Le conducteur reçoit dans son portefeuille le prix de chaque passager moins la
     commission de 10 %, quand tout l'équipage a validé la fin de la course
     (routes/course.py). Avec le virement automatique, ses gains partent aussitôt vers son
     compte Mobile Money par défaut.
  4. Le solde peut être viré vers un compte Mobile Money à tout moment (retrait).
"""

from __future__ import annotations

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .. import portefeuille as pf
from ..db import get_conn
from ..notifications import notifier
from ..securite import utilisateur_courant
from .course import regler_courses_echues
from .paiement import OPERATEURS

router = APIRouter(prefix="/api/moi/portefeuille", tags=["Portefeuille"])


class Recharge(BaseModel):
    id_compte: int
    montant_fcfa: int = Field(ge=100, le=500_000)
    # Code secret Mobile Money saisi sur le téléphone : vérifié pour la forme, jamais enregistré.
    code_secret: str = Field(pattern=r"^\d{4,5}$")


class Retrait(BaseModel):
    id_compte: int | None = None
    montant_fcfa: int = Field(ge=100)


class VirementAuto(BaseModel):
    actif: bool


def _compte(conn, u: dict, id_compte: int | None) -> dict:
    if id_compte is None:
        c = pf.compte_par_defaut(conn, u["id_utilisateur"])
    else:
        c = conn.execute("SELECT * FROM compte_mobile_money WHERE id_compte = %s AND id_utilisateur = %s",
                         (id_compte, u["id_utilisateur"])).fetchone()
    if c is None:
        raise HTTPException(404, "Enregistrez d'abord un compte Mobile Money")
    return c


def _etat(conn, u: dict) -> dict:
    uid = u["id_utilisateur"]
    p = pf.ouvrir(conn, uid)
    attente = conn.execute(
        """SELECT coalesce(sum(p.montant_fcfa - p.commission_fcfa), 0) AS montant, count(*) AS passagers
             FROM paiement p JOIN reservation r USING (id_reservation) JOIN trajet t ON t.id_trajet = r.id_trajet
            WHERE t.id_conducteur = %s AND p.statut = 'reussi' AND p.verse_le IS NULL
              AND r.statut IN ('confirmee', 'terminee')""", (uid,)).fetchone()
    sequestre = conn.execute(
        """SELECT coalesce(sum(p.montant_fcfa), 0) AS montant
             FROM paiement p JOIN reservation r USING (id_reservation) JOIN demande d USING (id_demande)
            WHERE d.id_demandeur = %s AND p.statut = 'reussi' AND p.verse_le IS NULL
              AND r.statut IN ('confirmee', 'terminee')""", (uid,)).fetchone()
    commission = conn.execute(
        """SELECT coalesce(sum(c.montant_fcfa), 0) AS montant
             FROM commission_mboaride c JOIN paiement p USING (id_paiement)
             JOIN reservation r USING (id_reservation) JOIN trajet t ON t.id_trajet = r.id_trajet
            WHERE t.id_conducteur = %s""", (uid,)).fetchone()
    compte = pf.compte_par_defaut(conn, uid)
    mouvements = conn.execute(
        "SELECT * FROM mouvement_portefeuille WHERE id_utilisateur = %s ORDER BY cree_le DESC, id_mouvement DESC "
        "LIMIT 30", (uid,)).fetchall()
    return {
        "solde_fcfa": p["solde_fcfa"],
        "virement_auto": p["virement_auto"],
        "compte_par_defaut": None if compte is None else {
            "id_compte": compte["id_compte"], "operateur": compte["operateur"],
            "operateur_libelle": OPERATEURS[compte["operateur"]]["libelle"],
            "telephone": compte["telephone"], "titulaire": compte["titulaire"]},
        # Conducteur : courses payées par les passagers, versées à la fin de la course.
        "gains_en_attente_fcfa": int(attente["montant"]),
        "passagers_en_attente": attente["passagers"],
        # Passager : trajets payés, gardés par MboaRide jusqu'à la fin de la course.
        "paiements_en_sequestre_fcfa": int(sequestre["montant"]),
        "commission_mboaride_fcfa": int(commission["montant"]),
        "mouvements": [{
            "id_mouvement": m["id_mouvement"], "type": m["type"], "type_libelle": pf.LIBELLES_TYPE[m["type"]],
            "montant_fcfa": m["montant_fcfa"], "solde_apres_fcfa": m["solde_apres_fcfa"],
            "libelle": m["libelle"], "reference": m["reference"], "id_reservation": m["id_reservation"],
            "cree_le": m["cree_le"]} for m in mouvements],
    }


@router.get("")
def mon_portefeuille(u: dict = Depends(utilisateur_courant), conn: psycopg.Connection = Depends(get_conn)) -> dict:
    regler_courses_echues(conn, id_conducteur=u["id_utilisateur"])
    return _etat(conn, u)


@router.post("/recharge")
def recharger(body: Recharge, u: dict = Depends(utilisateur_courant),
              conn: psycopg.Connection = Depends(get_conn)) -> dict:
    c = _compte(conn, u, body.id_compte)
    op = OPERATEURS[c["operateur"]]["libelle"]
    ref = pf.reference("RCH")
    pf.mouvement(conn, u["id_utilisateur"], "recharge", body.montant_fcfa,
                 f"Recharge depuis {op} {pf.numero_lisible(c['telephone'])}", ref)
    notifier(conn, u["id_utilisateur"], "portefeuille",
             f"Portefeuille rechargé de {body.montant_fcfa} FCFA depuis {op} (réf. {ref}).")
    return _etat(conn, u)


@router.post("/retrait")
def retirer(body: Retrait, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    c = _compte(conn, u, body.id_compte)
    op = OPERATEURS[c["operateur"]]["libelle"]
    ref = pf.reference("VIR")
    pf.mouvement(conn, u["id_utilisateur"], "retrait", -body.montant_fcfa,
                 f"Virement vers {op} {pf.numero_lisible(c['telephone'])}", ref)
    notifier(conn, u["id_utilisateur"], "portefeuille",
             f"{body.montant_fcfa} FCFA virés vers votre compte {op} (réf. {ref}).")
    return _etat(conn, u)


@router.put("/virement-auto")
def virement_automatique(body: VirementAuto, u: dict = Depends(utilisateur_courant),
                         conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if body.actif:
        _compte(conn, u, None)            # un compte Mobile Money est nécessaire
    pf.ouvrir(conn, u["id_utilisateur"])
    conn.execute("UPDATE portefeuille SET virement_auto = %s, maj_le = now() WHERE id_utilisateur = %s",
                 (body.actif, u["id_utilisateur"]))
    return _etat(conn, u)
