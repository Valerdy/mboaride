"""Chaque test repart d'une base neuve : schéma (01), données d'exemple (02), migration (04)."""

from __future__ import annotations

import os
from pathlib import Path

import psycopg
import psycopg.conninfo
import pytest

RACINE = Path(__file__).resolve().parent.parent
SQL = RACINE / "sql"
# Serveur PostgreSQL des tests (base d'administration) ; la base de test est recréée à chaque test.
PG = os.environ.get("MBOARIDE_TEST_PG", "host=localhost port=5432 user=postgres dbname=postgres")
BASE_TEST = "mboaride_test"
os.environ["MBOARIDE_DSN"] = psycopg.conninfo.make_conninfo(PG, dbname=BASE_TEST)

from fastapi.testclient import TestClient  # noqa: E402

from app.db import connect  # noqa: E402
from app.main import app  # noqa: E402

# Une vraie image PNG de 1 pixel : le dépôt d'une pièce d'agrément exige un fichier.
PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478"
                    "9c6360f8cfc0f01f0005000201a3d8b4a60000000049454e44ae426082")
PIECE = {"Content-Type": "image/png"}

SCRIPTS = ["01_schema.sql", "02_donnees_exemple.sql", "04_sprint2.sql", "05_sprint3.sql",
           "06_sprint3_eleves.sql", "07_pont_node.sql", "08_parcours_complet.sql",
           "09_comptes_mobile_money.sql", "10_portefeuille_fin_de_course.sql", "11_administration.sql",
           "12_administration_suite.sql", "13_places_multiples.sql"]


@pytest.fixture(autouse=True)
def stockage(tmp_path, monkeypatch):
    """Les fichiers déposés pendant un test vont dans un dossier temporaire, effacé ensuite."""
    from app import config
    monkeypatch.setattr(config, "STOCKAGE", tmp_path / "stockage")


@pytest.fixture(autouse=True)
def reglages_propres():
    """Les réglages de la console sont mis en cache : un test qui en change un ne doit pas
    influencer le suivant, même s'il n'utilise pas la base."""
    import time

    from app import parametres
    # Valeurs par défaut du produit en cache : un test qui n'ouvre pas la base ne lit pas les réglages
    # laissés par un test précédent. Ceux qui utilisent la base (fixture `base`) relisent la base.
    parametres._cache.update(valeurs=parametres.defauts(), lu_le=time.monotonic())
    yield
    parametres.invalider()


@pytest.fixture()
def base():
    from app import parametres
    parametres.invalider()          # chaque test repart des réglages par défaut
    with psycopg.connect(PG, autocommit=True) as admin:
        admin.execute(f"DROP DATABASE IF EXISTS {BASE_TEST} WITH (FORCE)")
        admin.execute(f"CREATE DATABASE {BASE_TEST}")
    with psycopg.connect(os.environ["MBOARIDE_DSN"], autocommit=True) as c:
        for nom in SCRIPTS:
            c.execute((SQL / nom).read_text(encoding="utf-8"))
    yield


@pytest.fixture()
def client(base):
    return TestClient(app)


@pytest.fixture()
def sql(base):
    conn = connect()
    conn.commit()
    conn.autocommit = True

    def run(q, params=None):
        cur = conn.execute(q, params)
        return cur.fetchall() if cur.description else None
    yield run
    conn.close()


def comme(uid: int) -> dict:
    return {"X-Utilisateur": str(uid)}


GRACE, MIREILLE, SERGE, NADEGE, JUNIOR, BRICE, HELENE, ARMAND = 2, 3, 4, 5, 6, 8, 9, 1
