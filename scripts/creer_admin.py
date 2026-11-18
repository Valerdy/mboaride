"""Nomme un administrateur de la plateforme (console http://127.0.0.1:8000/admin).

    python scripts/creer_admin.py adresse@exemple.com                (super administrateur)
    python scripts/creer_admin.py +237690000000 --role support
    python scripts/creer_admin.py adresse@exemple.com --retirer

Le compte doit déjà exister dans l'application (inscription faite depuis le téléphone).
Ensuite, la console se connecte avec le même identifiant et le même mot de passe.
Les autres administrateurs peuvent ensuite être nommés depuis la console elle-même.

Connexion à PostgreSQL : variables PG_HOST, PG_PORT, PG_USER, PG_PASSWORD, PG_DATABASE,
lues dans l'environnement ou, à défaut, dans .env.local à la racine du dépôt.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import psycopg
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

RACINE = Path(__file__).resolve().parent.parent


def reglages() -> dict[str, str]:
    conf = {}
    fichier = RACINE / ".env.local"
    if fichier.exists():
        for ligne in fichier.read_text(encoding="utf-8").splitlines():
            ligne = ligne.strip()
            if ligne and not ligne.startswith("#") and "=" in ligne:
                cle, valeur = ligne.split("=", 1)
                conf[cle.strip()] = valeur.strip().strip('"').strip("'")
    for cle in ("PG_HOST", "PG_PORT", "PG_USER", "PG_PASSWORD", "PG_DATABASE"):
        if os.environ.get(cle):
            conf[cle] = os.environ[cle]
    return conf


def main() -> int:
    p = argparse.ArgumentParser(description="Nomme un administrateur de la plateforme MboaRide.")
    p.add_argument("identifiant", help="e-mail ou téléphone du compte")
    p.add_argument("--role", choices=["super_admin", "support", "finance"], default="super_admin")
    p.add_argument("--retirer", action="store_true", help="retire les droits d'administration")
    args = p.parse_args()

    c = reglages()
    dsn = make_conninfo(host=c.get("PG_HOST", "127.0.0.1"), port=c.get("PG_PORT", "5432"),
                        user=c.get("PG_USER", "postgres"), password=c.get("PG_PASSWORD", ""),
                        dbname=c.get("PG_DATABASE", "mboaride"))
    with psycopg.connect(dsn, row_factory=dict_row) as conn:
        conn.execute("SET search_path TO mboaride, public")
        ident = args.identifiant.strip()
        u = conn.execute("SELECT id_utilisateur, prenom, nom FROM utilisateur WHERE lower(email) = lower(%s) "
                         "OR replace(telephone, ' ', '') = replace(%s, ' ', '')", (ident, ident)).fetchone()
        if u is None:
            print(f"Aucun compte MboaRide avec l'identifiant {ident}.")
            print("Inscrivez-vous d'abord dans l'application, puis relancez cette commande.")
            return 1
        nom = f"{u['prenom']} {u['nom']}"
        if args.retirer:
            conn.execute("UPDATE administrateur SET actif = FALSE WHERE id_utilisateur = %s", (u["id_utilisateur"],))
            print(f"Droits d'administration retirés à {nom}.")
            return 0
        conn.execute(
            """INSERT INTO administrateur (id_utilisateur, role) VALUES (%s, %s)
               ON CONFLICT (id_utilisateur) DO UPDATE SET role = EXCLUDED.role, actif = TRUE""",
            (u["id_utilisateur"], args.role))
        conn.execute(
            "INSERT INTO journal_admin (id_admin, action, cible_type, cible_id, resume) "
            "VALUES (NULL, 'nomination', 'utilisateur', %s, %s)",
            (str(u["id_utilisateur"]), f"{nom} nommé·e administrateur ({args.role}) en ligne de commande"))
    print(f"{nom} est administrateur ({args.role}). Console : http://127.0.0.1:8000/admin")
    return 0


if __name__ == "__main__":
    sys.exit(main())
