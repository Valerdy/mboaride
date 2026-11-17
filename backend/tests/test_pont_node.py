"""Pont avec l'API Node : l'API Python vérifie les jetons qu'elle signe.

L'authentification reste chez Node (US01). Ce qui est vérifié ici, c'est que l'API
Python accepte exactement les jetons de Node, refuse tout le reste, et retrouve le bon
utilisateur métier dans la base partagée.
"""

from __future__ import annotations

import time

import jwt
import pytest

from app import config
from conftest import GRACE, comme

SECRET = "secret-de-test-avec-au-moins-32-caracteres"


@pytest.fixture()
def secret_partage(monkeypatch):
    monkeypatch.setattr(config, "SECRET_KEY", SECRET)
    return SECRET


def jeton(sub, *, type_="access", secret=SECRET, expire_dans=900, algo="HS256") -> str:
    """Jeton identique à ceux de `createAccessToken` de l'API Node."""
    charge = {"sub": str(sub), "type": type_, "exp": int(time.time()) + expire_dans}
    return jwt.encode(charge, secret, algorithm=algo)


def porteur(valeur: str) -> dict:
    return {"Authorization": f"Bearer {valeur}"}


def table_users(sql, lignes):
    """Table `users` de l'API Node, telle qu'elle existe vraiment : dans le schéma
    `public` de la même base, alors que le métier vit dans le schéma `mboaride`."""
    sql("""CREATE TABLE IF NOT EXISTS public.users (
               id SERIAL PRIMARY KEY, email VARCHAR(254) UNIQUE, phone VARCHAR(20) UNIQUE,
               full_name VARCHAR(120) NOT NULL, password_hash VARCHAR(255) NOT NULL,
               is_verified BOOLEAN NOT NULL DEFAULT FALSE, company_id INTEGER,
               created_at BIGINT NOT NULL)""")
    for id_, email, phone, nom in lignes:
        sql("""INSERT INTO public.users (id, email, phone, full_name, password_hash, created_at)
               VALUES (%s, %s, %s, %s, 'argon2id$factice', 0)""", (id_, email, phone, nom))


def test_un_jeton_de_node_identifie_son_utilisateur(client, sql, secret_partage):
    grace = sql("SELECT email, prenom FROM utilisateur WHERE id_utilisateur = %s", (GRACE,))[0]
    table_users(sql, [(77, grace["email"], "+237690000077", "Grâce Ndongo")])

    r = client.get("/api/moi/preferences", headers=porteur(jeton(77)))
    assert r.status_code == 200

    # Le rapprochement est fait une fois, sur l'e-mail, puis gardé.
    lien = sql("SELECT * FROM compte_node WHERE id_compte_node = 77")
    assert len(lien) == 1
    assert lien[0]["id_utilisateur"] == GRACE and lien[0]["lie_par"] == "email"
    assert client.get("/api/moi/preferences", headers=porteur(jeton(77))).status_code == 200


def test_le_rapprochement_se_fait_aussi_sur_le_telephone(client, sql, secret_partage):
    grace = sql("SELECT telephone FROM utilisateur WHERE id_utilisateur = %s", (GRACE,))[0]
    table_users(sql, [(78, None, grace["telephone"], "Grâce Ndongo")])

    assert client.get("/api/moi/demandes", headers=porteur(jeton(78))).status_code == 200
    assert sql("SELECT lie_par FROM compte_node WHERE id_compte_node = 78")[0]["lie_par"] == "telephone"


@pytest.mark.parametrize("mauvais, attendu, motif", [
    (lambda: jeton(1, secret="un-autre-secret-de-32-caracteres-au-moins"), 401, "invalide"),
    (lambda: jeton(1, expire_dans=-60), 401, "expir"),
    (lambda: jeton(1, type_="refresh"), 401, "accès"),
    (lambda: "pas-du-tout-un-jeton", 401, "invalide"),
    (lambda: jwt.encode({"type": "access"}, SECRET, algorithm="HS256"), 401, "utilisateur"),
])
def test_tout_le_reste_est_refuse(client, secret_partage, mauvais, attendu, motif):
    r = client.get("/api/moi/preferences", headers=porteur(mauvais()))
    assert r.status_code == attendu
    assert motif.lower() in r.json()["detail"].lower()


def test_un_jeton_valide_sans_profil_metier_le_dit_clairement(client, sql, secret_partage):
    table_users(sql, [(99, "inconnu@entreprise-a.cm", "+237690000099", "Nouveau Venu")])
    r = client.get("/api/moi/preferences", headers=porteur(jeton(99)))
    assert r.status_code == 403
    assert "inscription" in r.json()["detail"].lower()


def test_sans_secret_partage_aucun_jeton_n_est_accepte(client, monkeypatch):
    monkeypatch.setattr(config, "SECRET_KEY", "")
    r = client.get("/api/moi/preferences", headers=porteur(jeton(77)))
    assert r.status_code == 401 and "secret" in r.json()["detail"].lower()


def test_l_entete_de_demonstration_marche_puis_se_coupe(client, monkeypatch):
    assert client.get("/api/moi/preferences", headers=comme(GRACE)).status_code == 200

    # En déploiement réel, MBOARIDE_DEMO_AUTH=0 : seul un jeton signé passe.
    monkeypatch.setattr(config, "DEMO_AUTH", False)
    r = client.get("/api/moi/preferences", headers=comme(GRACE))
    assert r.status_code == 401 and "jeton" in r.json()["detail"].lower()


def test_sans_rien_la_requete_est_refusee(client):
    assert client.get("/api/moi/preferences").status_code == 401


def test_le_pont_est_annonce_par_la_route_de_sante(client, secret_partage):
    corps = client.get("/health").json()
    assert corps["jeton_node"] is True
    assert corps["auth_demo"] is True
