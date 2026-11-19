"""Scénario simple : un parent, ses enfants et les organisations (docs/scenario-enfants-organisations.md).

Mireille est parente de deux collégiens (Ange et Marc, Collège B). Elle rejoint le collège avec son code,
ajoute un troisième enfant, lui réserve un voyage Douala - Yaoundé, suit son journal, retire puis rend
l'autorisation. De son côté, Hélène, administratrice de l'Entreprise A, invite un nouvel employé qui crée
son compte depuis le lien, rejoint le cercle de l'entreprise, puis le quitte.
"""

from __future__ import annotations

from datetime import date, timedelta

import psycopg
import pytest
from conftest import GRACE, HELENE, MIREILLE, comme

COLLEGE, ENTREPRISE_A = 3, 1


@pytest.fixture()
def voyage_demain(sql):
    """Le voyage Douala - Yaoundé des données d'exemple, ramené à demain : le scénario ne dépend pas de la date."""
    demain = date.today() + timedelta(days=1)
    sql("UPDATE trajet SET date_unique = %s WHERE id_trajet = 4", (demain,))
    return demain.isoformat()


def test_scenario_du_parent(client, sql, voyage_demain):
    mireille = comme(MIREILLE)

    # --- 1. Mes organisations : le parent rejoint le collège de ses enfants avec son code ------------
    assert client.get("/api/moi/organisations", headers=mireille).json() == []
    assert client.post("/api/moi/organisations/rejoindre", headers=mireille, json={"code": "XXXX-0000"}).status_code == 404
    # Une entreprise réservée à un domaine d'e-mail ne s'ouvre pas avec un simple code.
    r = client.post("/api/moi/organisations/rejoindre", headers=mireille, json={"code": "ENTA-2026"})
    assert r.status_code == 403 and "invitation" in r.json()["detail"]
    r = client.post("/api/moi/organisations/rejoindre", headers=mireille, json={"code": "colb-2026"})
    assert r.status_code == 201 and r.json()["nom"] == "Collège B (Bonapriso)"
    assert client.post("/api/moi/organisations/rejoindre", headers=mireille, json={"code": "COLB-2026"}).status_code == 409
    mes = client.get("/api/moi/organisations", headers=mireille).json()
    assert [(o["nom"], o["role"]) for o in mes] == [("Collège B (Bonapriso)", "membre")]

    # --- 2. Mes enfants : ajouter un élève dans l'un des établissements connus ------------------------
    ecoles = client.get("/api/etablissements", headers=mireille).json()
    assert {e["nom"] for e in ecoles} == {"Collège B (Bonapriso)", "Campus C"}
    assert [e["prenom"] for e in client.get("/api/moi/eleves", headers=mireille).json()] == ["Ange", "Marc"]
    lina = client.post("/api/moi/eleves", headers=mireille,
                       json={"prenom": "Lina", "age": 13, "id_etablissement": COLLEGE}).json()
    assert lina["autorisation_active"] is True and lina["etablissement"] == "Collège B (Bonapriso)"
    assert client.post("/api/moi/eleves", headers=mireille, json={"prenom": "Bébé", "age": 8}).status_code == 422

    # --- 3. Réserver un voyage pour l'enfant, puis suivre son journal ----------------------------------
    voyage = client.get(f"/api/voyages?date={voyage_demain}", headers=mireille).json()[0]
    reserve = client.post(f"/api/voyages/{voyage['id_trajet']}/reservations", headers=mireille, json={
        "id_point_depart": voyage["points_depart"][0]["id_point"], "date_trajet": voyage_demain,
        "id_eleve": lina["id_eleve"], "prix_annonce_fcfa": voyage["prix_fcfa"]})
    assert reserve.status_code == 201, reserve.text
    journal = client.get(f"/api/moi/eleves/{lina['id_eleve']}/journal", headers=mireille).json()
    assert [e["type"] for e in journal] == ["reservation"]
    # Les notifications de départ et d'arrivée sont simulées (US19) et arrivent dans le journal.
    simul = client.post(f"/api/moi/eleves/{lina['id_eleve']}/simuler-trajet", headers=mireille)
    assert simul.status_code == 201 and len(simul.json()["notifications"]) == 2
    types = {e["type"] for e in client.get(f"/api/moi/eleves/{lina['id_eleve']}/journal", headers=mireille).json()}
    assert types == {"reservation", "depart", "arrivee"}

    # --- 4. Garder la main : sans autorisation, aucune réservation n'est possible ---------------------
    r = client.put(f"/api/moi/eleves/{lina['id_eleve']}/autorisation", headers=mireille, json={"active": False})
    assert r.json()["autorisation_active"] is False
    refus = client.post(f"/api/voyages/{voyage['id_trajet']}/reservations", headers=mireille, json={
        "id_point_depart": voyage["points_depart"][1]["id_point"], "date_trajet": voyage_demain,
        "id_eleve": lina["id_eleve"]})
    assert refus.status_code == 409 and "utorisation" in refus.json()["detail"]
    client.put(f"/api/moi/eleves/{lina['id_eleve']}/autorisation", headers=mireille, json={"active": True})

    # Un autre parent ne voit ni ne réserve pour les enfants de Mireille.
    assert client.get("/api/moi/eleves", headers=comme(GRACE)).json() == []
    assert client.post(f"/api/voyages/{voyage['id_trajet']}/reservations", headers=comme(GRACE), json={
        "id_point_depart": voyage["points_depart"][0]["id_point"], "date_trajet": voyage_demain,
        "id_eleve": lina["id_eleve"]}).status_code == 404

    # --- 5. Quitter une organisation ----------------------------------------------------------------------
    assert client.delete(f"/api/moi/organisations/{COLLEGE}", headers=mireille).json()["quitte"] is True
    assert client.get("/api/moi/organisations", headers=mireille).json() == []
    assert client.delete(f"/api/moi/organisations/{COLLEGE}", headers=mireille).status_code == 404


def test_scenario_de_l_organisation(client, sql):
    helene = comme(HELENE)

    # --- 1. L'administratrice invite un employé ; une adresse d'un autre domaine est écartée --------------
    r = client.post(f"/api/organisations/{ENTREPRISE_A}/invitations", headers=helene,
                    json={"emails": ["paul.nkoa@entreprise-a.cm", "paul@autre.cm"], "service": "Logistique"})
    assert r.status_code == 201, r.text
    invitation = r.json()
    assert [e["email"] for e in invitation["envoyees"]] == ["paul.nkoa@entreprise-a.cm"]
    assert invitation["ecartees"][0]["motif"].startswith("hors du domaine")
    jeton = invitation["envoyees"][0]["lien"].rsplit("/", 1)[1]
    assert client.get(f"/api/organisations/{ENTREPRISE_A}/invitations?statut=envoyee", headers=helene).json()[0]["email"] \
        == "paul.nkoa@entreprise-a.cm"

    # --- 2. L'invité n'a pas de compte : il le crée depuis le lien et rejoint le cercle ---------------------
    lien = client.get(f"/api/invitations/{jeton}").json()
    assert lien["organisation"].startswith("Entreprise A") and lien["compte_existant"] is False
    nouveau = client.post(f"/api/invitations/{jeton}/inscription", json={
        "prenom": "Paul", "nom": "Nkoa", "telephone": "699123456", "mot_de_passe": "motdepasse1"})
    assert nouveau.status_code == 201, nouveau.text
    paul = sql("SELECT id_utilisateur FROM utilisateur WHERE email = 'paul.nkoa@entreprise-a.cm'")[0]["id_utilisateur"]
    assert [o["nom"] for o in client.get("/api/moi/organisations", headers=comme(paul)).json()] \
        == ["Entreprise A (Bonanjo)"]
    suivi = client.get(f"/api/organisations/{ENTREPRISE_A}/invitations", headers=helene).json()
    assert next(i for i in suivi if i["email"] == "paul.nkoa@entreprise-a.cm")["statut"] == "acceptee"

    # Le lien ne sert qu'une fois.
    assert client.post(f"/api/invitations/{jeton}/inscription", json={
        "prenom": "Paul", "nom": "Nkoa", "telephone": "699123457", "mot_de_passe": "motdepasse1"}).status_code in (404, 409, 410)

    # --- 3. Un membre peut quitter ; l'administratrice ne le peut pas -------------------------------------------
    assert client.delete(f"/api/moi/organisations/{ENTREPRISE_A}", headers=comme(paul)).json()["quitte"] is True
    r = client.delete(f"/api/moi/organisations/{ENTREPRISE_A}", headers=helene)
    assert r.status_code == 409 and "administrateur" in r.json()["detail"]

    # --- 4. Un collègue de l'entreprise rejoint aussi par son adresse : Grâce est déjà dans le cercle -------
    assert [o["nom"] for o in client.get("/api/moi/organisations", headers=comme(GRACE)).json()] \
        == ["Entreprise A (Bonanjo)"]
