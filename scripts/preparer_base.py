"""Crée ou met à niveau la base PostgreSQL partagée par l'API Node et l'API Python.

    python scripts/preparer_base.py            (appelé par scripts/lancer_tout.ps1)

Variables lues : PG_HOST, PG_PORT, PG_USER, PG_PASSWORD, PG_DATABASE (défaut mboaride).

Premier passage : création de la base, du schéma métier `mboaride` (scripts sql/ dans
l'ordre), des données d'exemple et des données de démonstration de la console.
Passages suivants : seules les migrations idempotentes (07, 08) sont rejouées.
Les tables de l'API Node (`users`, `otp_codes`...) sont créées par Node lui-même, dans
le schéma `public`, à son premier démarrage.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo

RACINE = Path(__file__).resolve().parent.parent
BACKEND = RACINE / "backend"
SQL = BACKEND / "sql"
CREATION = ["01_schema.sql", "02_donnees_exemple.sql", "04_sprint2.sql", "05_sprint3.sql",
            "06_sprint3_eleves.sql"]
MIGRATIONS = ["07_pont_node.sql", "08_parcours_complet.sql", "09_comptes_mobile_money.sql"]


def conninfo(dbname: str) -> str:
    return make_conninfo(host=os.environ.get("PG_HOST", "127.0.0.1"), port=os.environ.get("PG_PORT", "5432"),
                         user=os.environ.get("PG_USER", "postgres"), password=os.environ.get("PG_PASSWORD", ""),
                         dbname=dbname)


def main() -> int:
    base = os.environ.get("PG_DATABASE", "mboaride")
    try:
        with psycopg.connect(conninfo("postgres"), autocommit=True) as admin:
            existe = admin.execute("SELECT 1 FROM pg_database WHERE datname = %s", (base,)).fetchone()
            if not existe:
                print(f"     création de la base {base}")
                admin.execute(sql.SQL("CREATE DATABASE {} ENCODING 'UTF8' TEMPLATE template0")
                              .format(sql.Identifier(base)))
    except psycopg.OperationalError as exc:
        print(f"Connexion à PostgreSQL impossible : {exc}".strip())
        print("Vérifiez PG_HOST, PG_PORT, PG_USER et PG_PASSWORD dans .env.local.")
        return 1

    dsn = conninfo(base)
    with psycopg.connect(dsn, autocommit=True) as c:
        neuf = not c.execute("SELECT to_regclass('mboaride.utilisateur')").fetchone()[0]
        for nom in (CREATION if neuf else []) + MIGRATIONS:
            print(f"     {nom}")
            c.execute((SQL / nom).read_text(encoding="utf-8"))
    if neuf:
        print("     données de démonstration de la console")
        subprocess.run([sys.executable, "scripts/seed_demo.py"], cwd=BACKEND, check=True,
                       env={**os.environ, "PYTHONPATH": str(BACKEND), "MBOARIDE_DSN": dsn})
    else:
        print("     base déjà créée : migrations à jour")
    return 0


if __name__ == "__main__":
    sys.exit(main())
