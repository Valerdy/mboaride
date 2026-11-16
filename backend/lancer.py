"""Lance MboaRide en local sans rien installer à la main.

Démarre un PostgreSQL embarqué (paquet pgserver) dans le dossier .pgdata, crée la base au
premier lancement (schéma, données d'exemple, migration du sprint 2, données de démo),
puis démarre l'API et ouvre le navigateur sur http://localhost:8000.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path

import pgserver
import psycopg
import uvicorn

APP = Path(__file__).resolve().parent
RACINE = APP.parent
PGDATA = APP / ".pgdata"
SCRIPTS_SQL = [APP / "sql" / n for n in
               ("01_schema.sql", "02_donnees_exemple.sql", "04_sprint2.sql", "05_sprint3.sql")]
PORT = 8000


def main() -> None:
    print("1/3  Démarrage de la base de données…")
    serveur = pgserver.get_server(PGDATA, cleanup_mode="stop")
    uri = serveur.get_uri()
    dsn = uri.replace("/postgres?", "/mboaride?")
    os.environ["MBOARIDE_DSN"] = dsn

    with psycopg.connect(uri, autocommit=True) as c:
        existe = c.execute("SELECT 1 FROM pg_database WHERE datname = 'mboaride'").fetchone()
        if not existe:
            c.execute("CREATE DATABASE mboaride")

    if not existe:
        print("2/3  Premier lancement : création des tables et des données de démo…")
        with psycopg.connect(dsn, autocommit=True) as c:
            for f in SCRIPTS_SQL:
                print(f"     {f.name}")
                c.execute(f.read_text(encoding="utf-8"))
        subprocess.run([sys.executable, "scripts/seed_demo.py"], cwd=APP, check=True,
                       env={**os.environ, "PYTHONPATH": str(APP)})
    else:
        with psycopg.connect(dsn, autocommit=True) as c:     # mise à niveau d'une base créée avant le sprint 3
            if not c.execute("SELECT to_regclass('mboaride.courriel')").fetchone()[0]:
                print("2/3  Mise à niveau de la base (sprint 3)…")
                c.execute((APP / "sql" / "05_sprint3.sql").read_text(encoding="utf-8"))
                subprocess.run([sys.executable, "scripts/seed_demo.py"], cwd=APP, check=True,
                               env={**os.environ, "PYTHONPATH": str(APP)})
            else:
                print("2/3  Base déjà prête (supprime le dossier .pgdata pour repartir de zéro)")

    print(f"3/3  Appli disponible sur http://localhost:{PORT}  (Ctrl+C pour arrêter)")
    threading.Timer(2.0, webbrowser.open, args=[f"http://localhost:{PORT}"]).start()
    sys.path.insert(0, str(APP))
    uvicorn.run("app.main:app", host="127.0.0.1", port=PORT, log_level="warning")


if __name__ == "__main__":
    main()
