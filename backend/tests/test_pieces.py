"""Pièces d'agrément : vrai fichier déposé par le futur conducteur, relu et jugé dans la console."""

from __future__ import annotations

import pytest
from conftest import GRACE, HELENE, MIREILLE, PIECE, PNG, comme

from app import config

AGREMENT = "/api/moi/conducteur/agrement/documents"
ADMIN = "/api/admin/agrements"
PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF"


@pytest.fixture()
def equipe(sql):
    sql("INSERT INTO administrateur (id_utilisateur, role) VALUES (%s, 'super_admin'), (%s, 'support')",
        (HELENE, MIREILLE))
    return sql


def deposer(client, piece, contenu=PNG, type_="image/png", uid=GRACE):
    return client.post(f"{AGREMENT}/{piece}", headers={**comme(uid), "Content-Type": type_}, content=contenu)


def messages(sql, uid=GRACE):
    return [r["message"] for r in sql("SELECT message FROM notification WHERE id_utilisateur = %s "
                                      "AND type = 'administration' ORDER BY id_notification", (uid,))]


def test_le_depot_exige_un_vrai_fichier(client):
    assert client.post(f"{AGREMENT}/permis", headers={**comme(GRACE), **PIECE}).status_code == 422
    r = deposer(client, "permis", b"ceci n'est pas une image", "image/png")
    assert r.status_code == 422 and "Format" in r.json()["detail"]
    assert deposer(client, "inconnue").status_code == 404
    r = deposer(client, "permis", b"\x89PNG\r\n\x1a\n" + b"0" * (config.TAILLE_MAX_PIECE + 1))
    assert r.status_code == 413
    docs = client.get("/api/moi/conducteur/agrement", headers=comme(GRACE)).json()["documents"]
    assert {d["statut"] for d in docs} == {"manquant"}


def test_le_fichier_depose_est_relu_par_l_administrateur(client, equipe):
    r = deposer(client, "permis")
    assert r.status_code == 200, r.text
    assert next(d for d in r.json()["documents"] if d["type"] == "permis")["statut"] == "depose"
    assert any(config.STOCKAGE.rglob("permis-*.png"))

    # Le dossier apparaît à traiter, avec le descriptif du fichier.
    file = client.get(ADMIN, headers=comme(MIREILLE)).json()["lignes"]
    ligne = next(x for x in file if x["id_utilisateur"] == GRACE)
    permis = next(d for d in ligne["documents"] if d["type"] == "permis")
    assert permis["fichier"] is True and permis["type_mime"] == "image/png" and permis["taille_octets"] == len(PNG)

    lu = client.get(f"{ADMIN}/{GRACE}/documents/permis/fichier", headers=comme(MIREILLE))
    assert lu.status_code == 200 and lu.content == PNG and lu.headers["content-type"] == "image/png"
    assert lu.headers["cache-control"] == "private, no-store"
    # Réservé à l'équipe, et la consultation est tracée.
    assert client.get(f"{ADMIN}/{GRACE}/documents/permis/fichier", headers=comme(GRACE)).status_code == 403
    assert client.get(f"{ADMIN}/{GRACE}/documents/assurance/fichier", headers=comme(MIREILLE)).status_code == 404
    trace = client.get("/api/admin/journal?action=piece_consultee", headers=comme(HELENE)).json()
    assert trace["total"] == 1


def test_un_pdf_est_accepte(client, equipe):
    assert deposer(client, "assurance", PDF, "application/pdf").status_code == 200
    lu = client.get(f"{ADMIN}/{GRACE}/documents/assurance/fichier", headers=comme(MIREILLE))
    assert lu.headers["content-type"] == "application/pdf" and lu.content == PDF


def test_decision_et_notification_du_conducteur(client, equipe, sql):
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        assert deposer(client, piece).status_code == 200
    verifier = lambda piece, **corps: client.post(f"{ADMIN}/{GRACE}/documents/{piece}", json=corps,  # noqa: E731
                                                  headers=comme(MIREILLE))

    # Un refus : le motif est transmis, la pièce redevient à déposer.
    r = verifier("permis", decision="refuse", motif="Photo floue")
    assert r.status_code == 200, r.text
    assert any("Photo floue" in m for m in messages(sql))
    docs = client.get("/api/moi/conducteur/agrement", headers=comme(GRACE)).json()["documents"]
    permis = next(d for d in docs if d["type"] == "permis")
    assert permis["statut"] == "refuse" and "Photo floue" in permis["detail"]
    ancien = next(config.STOCKAGE.rglob("permis-*.png"))

    # Il dépose de nouveau : l'ancien fichier est effacé, la pièce repart en vérification.
    assert deposer(client, "permis", PDF, "application/pdf").status_code == 200
    assert not ancien.exists() and any(config.STOCKAGE.rglob("permis-*.pdf"))
    permis = next(d for d in client.get("/api/moi/conducteur/agrement", headers=comme(GRACE)).json()["documents"]
                  if d["type"] == "permis")
    assert permis["statut"] == "depose"

    # Les validations préviennent à chaque pièce ; la dernière active l'agrément.
    for piece in ("piece_identite", "permis", "casier_judiciaire"):
        assert verifier(piece, decision="valide").status_code == 200
    assert any("Il reste 1 pièce" in m for m in messages(sql))
    r = verifier("assurance", decision="valide")
    assert r.json()["statut_agrement"] == "actif"
    assert any("agrément est actif" in m for m in messages(sql))
    # Une pièce validée n'est plus remplacée par un dépôt.
    assert deposer(client, "assurance").status_code == 409


def test_piece_ancienne_sans_fichier(client, equipe, sql):
    # Comptes créés avant l'envoi de fichiers : la pièce existe, pas son fichier.
    sql("INSERT INTO document_agrement (id_utilisateur, type_document, statut, chemin_fichier) "
        "VALUES (%s, 'permis', 'depose', 'agrement/2/permis')", (GRACE,))
    ligne = next(x for x in client.get(ADMIN, headers=comme(MIREILLE)).json()["lignes"]
                 if x["id_utilisateur"] == GRACE)
    assert next(d for d in ligne["documents"] if d["type"] == "permis")["fichier"] is False
    r = client.get(f"{ADMIN}/{GRACE}/documents/permis/fichier", headers=comme(MIREILLE))
    assert r.status_code == 404 and "avant l'envoi de fichiers" in r.json()["detail"]
