"""Identification de l'appelant : jeton de l'API Node, ou en-tête de démonstration.

L'authentification (US01 : inscription, code à six chiffres, mot de passe Argon2id)
appartient à l'API Node de l'équipe. L'API Python ne l'a pas réécrite et n'émet aucun
jeton : elle **vérifie** ceux que Node signe, avec le même secret et le même algorithme
(HS256, charge utile `{"sub": <users.id>, "type": "access"}`). Les deux services
partagent la même base PostgreSQL, donc la correspondance entre un compte Node et un
utilisateur métier se lit dans `compte_node`, et se fait toute seule la première fois,
sur l'e-mail puis sur le téléphone.

Ordre de priorité, pour que la maquette reste démontrable sans lancer Node :

1. `Authorization: Bearer <jeton>` : vérifié, c'est la voie normale.
2. `X-Utilisateur: <id>` : sélecteur « Connecté en tant que » de la maquette, accepté
   seulement tant que `MBOARIDE_DEMO_AUTH` le permet. En déploiement réel, mettre
   `MBOARIDE_DEMO_AUTH=0` : l'en-tête est alors refusé et seul un jeton signé passe.

Un jeton invalide, expiré, d'un autre type ou signé avec un autre secret est refusé en
401, et un jeton valide dont le compte n'a pas de contrepartie métier le dit clairement
plutôt que de laisser passer une requête anonyme.
"""

from __future__ import annotations

import logging

import jwt
import psycopg
from fastapi import Depends, Header, HTTPException

from . import config
from .db import get_conn

logger = logging.getLogger(__name__)


def _compte_node(conn: psycopg.Connection, id_compte: int) -> dict | None:
    """Utilisateur métier correspondant à un compte Node, rapproché si besoin.

    Le rapprochement se fait sur l'e-mail puis sur le téléphone, et il est enregistré
    pour que la requête suivante n'ait plus rien à chercher. Si la table `users` de
    l'API Node n'est pas dans cette base (API Python lancée seule), on ne tente rien.
    """
    lien = conn.execute(
        "SELECT u.* FROM compte_node c JOIN utilisateur u USING (id_utilisateur) "
        "WHERE c.id_compte_node = %s", (id_compte,)).fetchone()
    if lien is not None:
        return lien
    if not conn.execute("SELECT to_regclass('users')").fetchone()["to_regclass"]:
        return None

    compte = conn.execute("SELECT id, email, phone, full_name FROM users WHERE id = %s",
                          (id_compte,)).fetchone()
    if compte is None:
        return None
    for colonne, valeur, motif in (("email", compte["email"], "email"),
                                   ("telephone", compte["phone"], "telephone")):
        if not valeur:
            continue
        u = conn.execute(
            f"SELECT * FROM utilisateur WHERE lower({colonne}) = lower(%s)", (valeur,)).fetchone()
        if u is None:
            continue
        conn.execute(
            "INSERT INTO compte_node (id_compte_node, id_utilisateur, lie_par) VALUES (%s, %s, %s) "
            "ON CONFLICT (id_utilisateur) DO UPDATE SET id_compte_node = EXCLUDED.id_compte_node",
            (id_compte, u["id_utilisateur"], motif))
        logger.info("Compte Node %s rapproché de l'utilisateur %s par %s",
                    id_compte, u["id_utilisateur"], motif)
        return u
    return None


def id_compte_du_jeton(entete: str) -> int:
    """Identifiant du compte Node porté par un jeton d'accès valide, ou 401."""
    if not config.SECRET_KEY:
        raise HTTPException(401, "Aucun secret partagé avec l'API Node : jeton non vérifiable")
    jeton = entete.split(" ", 1)[1].strip()
    try:
        charge = jwt.decode(jeton, config.SECRET_KEY, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "Session expirée, reconnectez-vous") from None
    except jwt.InvalidTokenError:
        raise HTTPException(401, "Jeton de session invalide") from None
    if charge.get("type") != "access":
        raise HTTPException(401, "Ce jeton n'est pas un jeton d'accès")
    try:
        id_compte = int(charge["sub"])
    except (KeyError, TypeError, ValueError):
        raise HTTPException(401, "Jeton de session sans utilisateur") from None
    return id_compte


def _depuis_jeton(conn: psycopg.Connection, entete: str) -> dict:
    id_compte = id_compte_du_jeton(entete)
    utilisateur = _compte_node(conn, id_compte)
    if utilisateur is None:
        raise HTTPException(403, "Compte authentifié mais sans profil MboaRide : "
                                 "terminez votre inscription (POST /api/moi/profil)")
    return utilisateur


def utilisateur_courant(authorization: str | None = Header(default=None),
                        x_utilisateur: int | None = Header(default=None),
                        conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if authorization and authorization.lower().startswith("bearer "):
        return _depuis_jeton(conn, authorization)
    if x_utilisateur is not None:
        if not config.DEMO_AUTH:
            raise HTTPException(401, "Authentification par jeton requise")
        row = conn.execute("SELECT * FROM utilisateur WHERE id_utilisateur = %s",
                           (x_utilisateur,)).fetchone()
        if row is None:
            raise HTTPException(401, "Utilisateur inconnu")
        return row
    raise HTTPException(401, "Utilisateur non identifié")


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
