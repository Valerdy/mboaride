"""Portefeuille MboaRide : solde en FCFA et journal des mouvements.

Chaque mouvement enregistre le solde obtenu, pour que le relevé se lise sans recalcul.
Les mouvements sont simulés côté Mobile Money (aucun opérateur réel n'est appelé),
comme le paiement US10.
"""

from __future__ import annotations

import secrets

from fastapi import HTTPException

LIBELLES_TYPE = {
    "recharge": "Recharge",
    "paiement": "Paiement d'un trajet",
    "remboursement": "Remboursement",
    "gain": "Gain de course",
    "retrait": "Virement vers Mobile Money",
}


def reference(prefixe: str = "PF") -> str:
    return f"{prefixe}-{secrets.token_hex(4).upper()}"


def ouvrir(conn, id_utilisateur: int) -> dict:
    """Portefeuille de l'utilisateur, créé vide au premier usage, verrouillé pour la transaction."""
    conn.execute("INSERT INTO portefeuille (id_utilisateur) VALUES (%s) ON CONFLICT DO NOTHING", (id_utilisateur,))
    return conn.execute("SELECT * FROM portefeuille WHERE id_utilisateur = %s FOR UPDATE",
                        (id_utilisateur,)).fetchone()


def mouvement(conn, id_utilisateur: int, type_: str, montant: int, libelle: str,
              ref: str | None = None, id_reservation: int | None = None) -> dict:
    """Crédite (montant > 0) ou débite (montant < 0) le portefeuille. Refuse un solde négatif."""
    if montant == 0:
        raise HTTPException(422, "Montant nul")
    p = ouvrir(conn, id_utilisateur)
    solde = p["solde_fcfa"] + montant
    if solde < 0:
        raise HTTPException(409, {"message": f"Solde insuffisant : {p['solde_fcfa']} FCFA dans votre portefeuille "
                                             f"pour {-montant} FCFA à payer",
                                  "solde_fcfa": p["solde_fcfa"], "manque_fcfa": -solde})
    conn.execute("UPDATE portefeuille SET solde_fcfa = %s, maj_le = now() WHERE id_utilisateur = %s",
                 (solde, id_utilisateur))
    return conn.execute(
        """INSERT INTO mouvement_portefeuille (id_utilisateur, type, montant_fcfa, solde_apres_fcfa, libelle,
                                               reference, id_reservation)
           VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING *""",
        (id_utilisateur, type_, montant, solde, libelle[:200], ref, id_reservation)).fetchone()


def compte_par_defaut(conn, id_utilisateur: int) -> dict | None:
    return conn.execute("SELECT * FROM compte_mobile_money WHERE id_utilisateur = %s "
                        "ORDER BY par_defaut DESC, id_compte LIMIT 1", (id_utilisateur,)).fetchone()


def numero_lisible(telephone: str) -> str:
    n = telephone.removeprefix("+237")
    return f"+237 {n[0]} {n[1:3]} {n[3:5]} {n[5:7]} {n[7:]}" if len(n) == 9 else telephone
