"""Identification simplifiée pour la maquette.

L'authentification complète (US01, code par SMS) fournit l'identifiant de l'utilisateur ;
ici l'interface le transmet dans l'en-tête X-Utilisateur. Les droits, eux, sont vérifiés
pour de vrai : seul un administrateur d'organisation voit sa console.
"""

from __future__ import annotations

import psycopg
from fastapi import Depends, Header, HTTPException

from .db import get_conn


def utilisateur_courant(x_utilisateur: int | None = Header(default=None),
                        conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if x_utilisateur is None:
        raise HTTPException(401, "Utilisateur non identifié")
    row = conn.execute("SELECT * FROM utilisateur WHERE id_utilisateur = %s",
                       (x_utilisateur,)).fetchone()
    if row is None:
        raise HTTPException(401, "Utilisateur inconnu")
    return row


def exiger_admin(conn: psycopg.Connection, id_utilisateur: int, id_organisation: int) -> dict:
    org = conn.execute("SELECT * FROM organisation WHERE id_organisation = %s",
                       (id_organisation,)).fetchone()
    if org is None:
        raise HTTPException(404, "Organisation introuvable")
    ok = conn.execute(
        "SELECT 1 FROM appartenance WHERE id_utilisateur = %s AND id_organisation = %s "
        "AND role = 'administrateur'", (id_utilisateur, id_organisation)).fetchone()
    if not ok:
        raise HTTPException(403, "Réservé aux administrateurs de l'organisation")
    return org
