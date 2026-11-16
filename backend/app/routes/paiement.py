"""US10 · Payer par Mobile Money (simulé).

Critères d'acceptation :
  1. Après confirmation, le passager paie le montant annoncé par Mobile Money, en choisissant
     son opérateur et son numéro ; le numéro doit appartenir à l'opérateur choisi.
  2. Le paiement passe par une demande de validation sur le téléphone du payeur (simulée) :
     il est réussi quand le payeur valide, échoué s'il refuse, si son solde est insuffisant
     ou s'il ne répond pas dans le délai.
  3. Un paiement échoué peut être relancé, trois tentatives au plus ; un paiement réussi ne
     peut pas être payé deux fois.
  4. Le reçu indique la référence, le montant, la part reversée au conducteur et la
     commission éventuelle.
  5. Si la réservation est annulée par le conducteur, un paiement réussi est remboursé.
Aucun opérateur réel n'est appelé : la validation sur le téléphone est simulée dans
l'interface, et l'API reproduit le cycle de vie d'un vrai paiement (initiation, attente,
confirmation par l'opérateur).
"""

from __future__ import annotations

import re
import secrets

import psycopg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..db import get_conn
from ..notifications import notifier
from ..securite import utilisateur_courant

router = APIRouter(prefix="/api", tags=["US10 · Paiement Mobile Money (simulé)"])

MAX_TENTATIVES = 3

# Préfixes des numéros mobiles camerounais (9 chiffres commençant par 6).
OPERATEURS = {
    "mtn": {"libelle": "MTN Mobile Money", "prefixes": ("67", "650", "651", "652", "653", "654",
                                                        "680", "681", "682", "683", "684")},
    "orange": {"libelle": "Orange Money", "prefixes": ("69", "655", "656", "657", "658", "659",
                                                       "685", "686", "687", "688", "689")},
}
RESULTATS = {
    "valide": None,
    "refuse": "Paiement refusé sur le téléphone du payeur",
    "solde_insuffisant": "Solde Mobile Money insuffisant",
    "delai_depasse": "Pas de validation dans le délai de 2 minutes",
}


class Initiation(BaseModel):
    operateur: str = Field(pattern="^(mtn|orange)$")
    telephone: str


class Reponse(BaseModel):
    """Ce que l'opérateur renvoie après l'action du payeur sur son téléphone (simulé)."""
    resultat: str = Field(pattern="^(valide|refuse|solde_insuffisant|delai_depasse)$")


def normaliser(telephone: str) -> str:
    chiffres = re.sub(r"[\s.()-]", "", telephone)
    m = re.fullmatch(r"(?:\+?237)?(6\d{8})", chiffres)
    if not m:
        raise HTTPException(422, "Numéro camerounais attendu : 6 suivi de 8 chiffres")
    return m.group(1)


def _paiement(conn, id_paiement: int, u: dict) -> dict:
    p = conn.execute(
        """SELECT p.*, r.id_reservation, r.statut AS statut_reservation, r.date_trajet,
                  d.id_demandeur, d.depart_libelle, d.arrivee_libelle, uc.prenom AS conducteur
             FROM paiement p JOIN reservation r USING (id_reservation)
             JOIN demande d ON d.id_demande = r.id_demande
             JOIN trajet t ON t.id_trajet = r.id_trajet
             JOIN utilisateur uc ON uc.id_utilisateur = t.id_conducteur
            WHERE p.id_paiement = %s""", (id_paiement,)).fetchone()
    if p is None:
        raise HTTPException(404, "Paiement introuvable")
    if p["id_demandeur"] != u["id_utilisateur"]:
        raise HTTPException(403, "Ce paiement concerne la réservation d'un autre utilisateur")
    return p


def recu(p: dict) -> dict:
    op = OPERATEURS.get(p["operateur"] or "", {}).get("libelle", p["operateur"])
    return {
        "id_paiement": p["id_paiement"], "id_reservation": p["id_reservation"],
        "trajet": f"{p['depart_libelle']} → {p['arrivee_libelle']}", "date_trajet": p["date_trajet"],
        "conducteur": p["conducteur"],
        "statut": p["statut"], "reference": p["reference_transaction"],
        "operateur": op, "telephone": p["telephone_payeur"],
        "montant_fcfa": p["montant_fcfa"], "commission_fcfa": p["commission_fcfa"],
        "reverse_conducteur_fcfa": p["montant_fcfa"] - p["commission_fcfa"],
        "tentatives": p["tentatives"], "tentatives_restantes": MAX_TENTATIVES - p["tentatives"],
        "motif_echec": p["motif_echec"], "paye_le": p["paye_le"], "rembourse_le": p["rembourse_le"],
    }


@router.get("/moi/paiements")
def mes_paiements(u: dict = Depends(utilisateur_courant),
                  conn: psycopg.Connection = Depends(get_conn)) -> list[dict]:
    ids = conn.execute(
        """SELECT p.id_paiement FROM paiement p JOIN reservation r USING (id_reservation)
             JOIN demande d USING (id_demande)
            WHERE d.id_demandeur = %s ORDER BY r.date_trajet DESC, p.id_paiement DESC LIMIT 20""",
        (u["id_utilisateur"],)).fetchall()
    return [recu(_paiement(conn, r["id_paiement"], u)) for r in ids]


@router.post("/paiements/{id_paiement}/mobile-money")
def initier(id_paiement: int, body: Initiation, u: dict = Depends(utilisateur_courant),
            conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Le passager lance le paiement : l'opérateur envoie une demande de validation au téléphone."""
    p = _paiement(conn, id_paiement, u)
    if p["statut"] == "reussi":
        raise HTTPException(409, "Ce trajet est déjà payé")
    if p["statut"] == "rembourse" or p["statut_reservation"] == "annulee":
        raise HTTPException(409, "Réservation annulée : rien à payer")
    if p["tentatives"] >= MAX_TENTATIVES:
        raise HTTPException(409, "Nombre maximal de tentatives atteint : contactez le support")
    numero = normaliser(body.telephone)
    op = OPERATEURS[body.operateur]
    if not numero.startswith(op["prefixes"]):
        autre = next((o["libelle"] for k, o in OPERATEURS.items() if numero.startswith(o["prefixes"])), None)
        raise HTTPException(422, f"Ce numéro n'est pas un numéro {op['libelle']}"
                                 + (f" (il semble être {autre})" if autre else ""))
    reference = "MBR-" + secrets.token_hex(4).upper()
    conn.execute(
        """UPDATE paiement SET operateur = %s, telephone_payeur = %s, reference_transaction = %s,
               statut = 'en_attente', initie_le = now(), tentatives = tentatives + 1, motif_echec = NULL
           WHERE id_paiement = %s""", (body.operateur, "+237" + numero, reference, id_paiement))
    return {**recu(_paiement(conn, id_paiement, u)),
            "etape": "validation_telephone",
            "message": f"Une demande de paiement de {p['montant_fcfa']} FCFA a été envoyée au "
                       f"+237 {numero[0]} {numero[1:3]} {numero[3:5]} {numero[5:7]} {numero[7:]}. "
                       f"Validez-la avec votre code secret {op['libelle']}."}


@router.post("/paiements/{id_paiement}/simulation-operateur")
def reponse_operateur(id_paiement: int, body: Reponse, u: dict = Depends(utilisateur_courant),
                      conn: psycopg.Connection = Depends(get_conn)) -> dict:
    """Simule la réponse de l'opérateur après l'action du payeur sur son téléphone."""
    p = _paiement(conn, id_paiement, u)
    if p["statut"] != "en_attente" or p["initie_le"] is None:
        raise HTTPException(409, "Aucun paiement en cours de validation")
    motif = RESULTATS[body.resultat]
    if motif is None:
        conn.execute("UPDATE paiement SET statut = 'reussi', paye_le = now() WHERE id_paiement = %s",
                     (id_paiement,))
        notifier(conn, u["id_utilisateur"], "paiement",
                 f"Paiement de {p['montant_fcfa']} FCFA reçu (réf. {p['reference_transaction']}).")
    else:
        conn.execute("UPDATE paiement SET statut = 'echoue', motif_echec = %s WHERE id_paiement = %s",
                     (motif, id_paiement))
    return recu(_paiement(conn, id_paiement, u))


def rembourser_ou_annuler(conn, id_reservation: int, id_passager: int) -> str | None:
    """Appelé quand une réservation est annulée : rembourse un paiement réussi."""
    p = conn.execute("SELECT * FROM paiement WHERE id_reservation = %s", (id_reservation,)).fetchone()
    if p is None:
        return None
    if p["statut"] == "reussi":
        conn.execute("UPDATE paiement SET statut = 'rembourse', rembourse_le = now() WHERE id_paiement = %s",
                     (p["id_paiement"],))
        notifier(conn, id_passager, "remboursement",
                 f"Votre paiement de {p['montant_fcfa']} FCFA (réf. {p['reference_transaction']}) "
                 f"vous a été remboursé sur votre compte Mobile Money.")
        return "rembourse"
    if p["statut"] == "en_attente":
        conn.execute("UPDATE paiement SET statut = 'echoue', motif_echec = 'Réservation annulée par le "
                     "conducteur' WHERE id_paiement = %s", (p["id_paiement"],))
        return "annule"
    return p["statut"]
