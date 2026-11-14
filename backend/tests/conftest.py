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

SCRIPTS = ["01_schema.sql", "02_donnees_exemple.sql", "04_sprint2.sql", "05_sprint3.sql"]


@pytest.fixture()
def base():
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
