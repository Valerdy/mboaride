"""Profil métier d'un compte créé dans l'application mobile.

L'inscription (US01) se fait sur l'API Node : nom, e-mail, téléphone, mot de passe,
code de vérification. Le compte existe alors dans `users` (schéma public de la base
partagée), mais pas encore dans `utilisateur`, où vivent préférences, demandes, trajets
et réservations. Juste après la connexion, l'application appelle `POST /api/moi/profil` :

- si le compte est déjà lié, ou si un utilisateur métier a le même e-mail ou le même
  téléphone, on le reprend (cas des comptes de démonstration) ;
- sinon on crée l'utilisateur métier à partir du compte Node, et on le rattache à
  l'organisation dont le domaine correspond à son e-mail (cercle de confiance).

L'appel est idempotent : on peut le refaire à chaque connexion.
"""

from __future__ import annotations

import psycopg
from fastapi import APIRouter, Depends, Header, HTTPException

from ..db import get_conn
from ..securite import _compte_node, id_compte_du_jeton, utilisateur_courant

router = APIRouter(prefix="/api/moi", tags=["US01 · Profil métier du compte mobile"])


def _profil(conn: psycopg.Connection, u: dict) -> dict:
    orgs = conn.execute(
        """SELECT o.id_organisation, o.nom, a.role FROM appartenance a JOIN organisation o USING (id_organisation)
            WHERE a.id_utilisateur = %s ORDER BY o.id_organisation""", (u["id_utilisateur"],)).fetchall()
    return {
        "id_utilisateur": u["id_utilisateur"], "prenom": u["prenom"], "nom": u["nom"],
        "email": u["email"], "telephone": u["telephone"],
        "est_conducteur": u["est_conducteur"], "statut_agrement": u["statut_agrement"],
        "organisations": orgs,
    }


def _decouper(nom_complet: str) -> tuple[str, str]:
    mots = nom_complet.split()
    if not mots:
        return "Utilisateur", "MboaRide"
    if len(mots) == 1:
        return mots[0][:60], mots[0][:60]
    return mots[0][:60], " ".join(mots[1:])[:60]


@router.post("/profil")
def creer_profil(authorization: str | None = Header(default=None),
                 conn: psycopg.Connection = Depends(get_conn)) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Connectez-vous d'abord (jeton de l'API Node)")
    id_compte = id_compte_du_jeton(authorization)

    existant = _compte_node(conn, id_compte)
    if existant is not None:
        return {**_profil(conn, existant), "cree": False}

    if not conn.execute("SELECT to_regclass('users')").fetchone()["to_regclass"]:
        raise HTTPException(503, "Comptes de l'API Node introuvables : les deux API doivent partager la base")
    compte = conn.execute("SELECT id, email, phone, full_name, is_verified FROM users WHERE id = %s",
                          (id_compte,)).fetchone()
    if compte is None or not compte["is_verified"]:
        raise HTTPException(403, "Compte inconnu ou non vérifié")
    if not compte["phone"]:
        raise HTTPException(422, "Ajoutez un numéro de téléphone à votre compte pour utiliser MboaRide")

    prenom, nom = _decouper(compte["full_name"] or "")
    u = conn.execute(
        """INSERT INTO utilisateur (nom, prenom, telephone, email, mot_de_passe_hache, consentement_position)
           VALUES (%s, %s, %s, %s, %s, TRUE) RETURNING *""",
        # Le mot de passe reste chez l'API Node : rien d'utilisable n'est stocké ici.
        (nom, prenom, compte["phone"], compte["email"], "gere-par-api-node")).fetchone()
    conn.execute("INSERT INTO compte_node (id_compte_node, id_utilisateur, lie_par) VALUES (%s, %s, 'creation')",
                 (id_compte, u["id_utilisateur"]))
    if compte["email"]:
        org = conn.execute("SELECT id_organisation FROM organisation WHERE lower(domaine_email) = lower(%s)",
                           (compte["email"].split("@", 1)[1],)).fetchone()
        if org:
            conn.execute("INSERT INTO appartenance (id_utilisateur, id_organisation) VALUES (%s, %s) "
                         "ON CONFLICT DO NOTHING", (u["id_utilisateur"], org["id_organisation"]))
    return {**_profil(conn, u), "cree": True}


@router.get("/profil")
def lire_profil(u: dict = Depends(utilisateur_courant),
                conn: psycopg.Connection = Depends(get_conn)) -> dict:
    return _profil(conn, u)
