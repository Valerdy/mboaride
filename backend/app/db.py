"""Accès PostgreSQL : une connexion par requête, transaction validée à la fin."""

from __future__ import annotations

from collections.abc import Iterator

import psycopg
from psycopg.rows import dict_row

from . import config


def connect() -> psycopg.Connection:
    conn = psycopg.connect(config.DSN, row_factory=dict_row)
    conn.execute("SET search_path TO mboaride")
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
