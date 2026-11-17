"""Accès PostgreSQL : une connexion par requête, transaction validée à la fin."""

from __future__ import annotations

from collections.abc import Iterator

import psycopg
from psycopg.rows import dict_row

from . import config


def connect() -> psycopg.Connection:
    conn = psycopg.connect(config.DSN, row_factory=dict_row)
    # Le schéma métier d'abord, puis public : l'API Node pose ses propres tables
    # (`users`, `refresh_tokens`, ...) dans public quand les deux services partagent
    # la même base, et le pont d'authentification a besoin de les lire.
    conn.execute("SET search_path TO mboaride, public")
    return conn


def get_conn() -> Iterator[psycopg.Connection]:
    conn = connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
