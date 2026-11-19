"""Espace conducteur : réservé aux conducteurs ; devenir chauffeur commence par le dépôt des pièces."""

from __future__ import annotations

import pytest
from conftest import GRACE, PIECE, PNG, SERGE, comme

RESERVES = [("get", "/api/moi/conducteur/vehicule"), ("get", "/api/moi/conducteur/regles"),
            ("get", "/api/moi/conducteur/trajets"), ("get", "/api/moi/conducteur/equipage"),
            ("get", "/api/moi/conducteur/activite"), ("get", "/api/moi/conducteur/gains")]


@pytest.mark.parametrize("methode, chemin", RESERVES)
def test_un_passager_n_a_pas_acces_a_l_espace_conducteur(client, methode, chemin):
    r = getattr(client, methode)(chemin, headers=comme(GRACE))
    assert r.status_code == 403, (chemin, r.text)
    assert "devenez chauffeur" in r.json()["detail"]
    assert getattr(client, methode)(chemin, headers=comme(SERGE)).status_code == 200      # Serge conduit


def test_un_passager_ne_peut_ni_publier_ni_enregistrer_un_vehicule(client):
    assert client.put("/api/moi/conducteur/vehicule", headers=comme(GRACE), json={
        "marque_modele": "Toyota Yaris", "immatriculation": "LT 123 AB", "places_passagers": 3,
        "conso_l_100km": 7}).status_code == 403
    assert client.post("/api/moi/conducteur/trajets", headers=comme(GRACE), json={}).status_code == 403


def test_la_procedure_pour_devenir_chauffeur_reste_ouverte_au_passager(client, sql):
    vue = client.get("/api/moi/conducteur", headers=comme(GRACE)).json()
    assert vue["est_conducteur"] is False and vue["agree"] is False
    docs = client.get("/api/moi/conducteur/agrement", headers=comme(GRACE))
    assert docs.status_code == 200 and {d["statut"] for d in docs.json()["documents"]} == {"manquant"}

    # Le dépôt de la première pièce lance la procédure : l'espace conducteur s'ouvre.
    r = client.post("/api/moi/conducteur/agrement/documents/permis", headers={**comme(GRACE), **PIECE}, content=PNG)
    assert r.status_code == 200, r.text
    assert client.get("/api/moi/conducteur", headers=comme(GRACE)).json()["est_conducteur"] is True
    assert client.get("/api/moi/conducteur/vehicule", headers=comme(GRACE)).status_code != 403
