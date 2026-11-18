"""Espace conducteur : programmer plusieurs trajets, retirer un trajet, le republier."""

from __future__ import annotations

from datetime import date, timedelta

import pytest

from app import config
from test_parcours_complet import prochain_jour_ouvre
from test_pont_node import jeton, porteur, secret_partage, table_users  # noqa: F401  (fixture)

KEVIN, LINA = 701, 702
RAMASSAGE = "Station Total de Logpom, côté boulangerie"


@pytest.fixture()
def comptes(client, sql, secret_partage, monkeypatch):  # noqa: F811
    monkeypatch.setattr(config, "AGREMENT_AUTO", True)
    table_users(sql, [(KEVIN, "kevin@exemple.cm", "+237690000701", "Kevin Ngando"),
                      (LINA, "lina@exemple.cm", "+237690000702", "Lina Ebolo")])
    sql("UPDATE public.users SET is_verified = TRUE")
    h = {"kevin": porteur(jeton(KEVIN)), "lina": porteur(jeton(LINA))}
    for n in h.values():
        client.post("/api/moi/profil", headers=n)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers=h["kevin"])
    client.put("/api/moi/conducteur/vehicule", headers=h["kevin"], json={
        "marque_modele": "Toyota Corolla", "immatriculation": "LT 701 AA", "places_passagers": 3, "conso_l_100km": 8})
    return h


def _trajet(depart, arrivee, heure, **extra):
    return {"depart": depart, "arrivee": arrivee, "heure_depart": heure, "places": 3, "detour_max_km": 3,
            "point_ramassage": RAMASSAGE, **extra}


def test_programmer_plusieurs_trajets_d_un_coup(client, comptes):
    kevin = comptes["kevin"]
    demain = (date.today() + timedelta(days=1)).isoformat()
    lot = client.post("/api/moi/conducteur/trajets/lot", headers=kevin, json={"trajets": [
        _trajet("Logpom", "Bonanjo", "06:50", jours_semaine=[1, 2, 3, 4, 5]),        # aller
        _trajet("Bonanjo", "Logpom", "17:30", jours_semaine=[1, 2, 3, 4, 5]),        # retour
        _trajet("Logpom", "Akwa", "09:00", date_trajet=demain),                      # ponctuel
        _trajet("Logpom", "Bonanjo", "06:50", jours_semaine=[1, 2, 3, 4, 5]),        # doublon de l'aller
        _trajet("Nulle Part", "Akwa", "08:00", jours_semaine=[6]),                   # lieu inconnu
    ]})
    assert lot.status_code == 201, lot.text
    r = lot.json()
    assert (r["publies"], r["refuses"]) == (3, 2)
    assert "déjà publié" in r["resultats"][3]["erreur"] and "Lieu inconnu" in r["resultats"][4]["erreur"]

    trajets = client.get("/api/moi/conducteur/trajets", headers=kevin).json()
    assert len(trajets) == 3 and all(t["etat"] == "actif" for t in trajets)
    retour = next(t for t in trajets if t["depart"] == "Bonanjo")
    assert retour["jours_semaine"] == [1, 2, 3, 4, 5] and retour["heure_depart"] == "17:30"
    assert retour["point_ramassage"] == RAMASSAGE and retour["prochain_depart"] is not None
    ponctuel = next(t for t in trajets if t["arrivee"] == "Akwa")
    assert ponctuel["date_unique"] == demain and ponctuel["prochain_depart"] == demain


def test_retirer_puis_republier_un_trajet(client, sql, comptes):
    kevin, lina = comptes["kevin"], comptes["lina"]
    id_trajet = client.post("/api/moi/conducteur/trajets", headers=kevin, json=_trajet(
        "Logpom", "Bonanjo", "06:50", jours_semaine=[1, 2, 3, 4, 5])).json()["id_trajet"]

    # Lina réserve et paie avec son portefeuille.
    jour = prochain_jour_ouvre().isoformat()
    id_demande = client.post("/api/demandes", headers=lina, json={
        "depart": {"libelle": "Logpom", "lat": 4.0846, "lon": 9.7562},
        "arrivee": {"libelle": "Bonanjo", "lat": 4.042, "lon": 9.689},
        "arrivee_au_plus_tot": "07:15", "arrivee_au_plus_tard": "08:00", "date_trajet": jour,
        "prix_max_fcfa": 2000, "cercle_max": "public"}).json()["id"]
    offre = next(o for o in client.get(f"/api/moi/demandes/{id_demande}/offres", headers=lina).json()
                 if o["id_trajet"] == id_trajet)
    resa = client.post("/api/reservations", headers=lina, json={
        "id_demande": id_demande, "id_trajet": id_trajet, "date_trajet": jour,
        "prix_annonce_fcfa": offre["prix_fcfa"]}).json()
    compte = client.post("/api/moi/comptes-mobile-money", headers=lina, json={
        "operateur": "mtn", "telephone": "677000702", "titulaire": "Lina Ebolo"}).json()
    client.post("/api/moi/portefeuille/recharge", headers=lina, json={
        "id_compte": compte["id_compte"], "montant_fcfa": 2000, "code_secret": "1234"})
    client.post(f"/api/paiements/{resa['id_paiement']}/portefeuille", headers=lina)

    # Retrait : plus proposé, Lina remboursée dans son portefeuille et prévenue.
    r = client.post(f"/api/moi/conducteur/trajets/{id_trajet}/retrait", headers=kevin, json={"motif": "Voiture au garage"})
    assert r.status_code == 200 and r.json()["reservations_annulees"] == 1
    assert client.post(f"/api/moi/conducteur/trajets/{id_trajet}/retrait", headers=kevin, json={}).status_code == 409
    assert client.get("/api/moi/conducteur/trajets", headers=kevin).json()[0]["etat"] == "retire"
    assert client.get("/api/moi/portefeuille", headers=lina).json()["solde_fcfa"] == 2000
    notes = client.get("/api/moi/notifications", headers=lina).json()
    assert any("annulé" in n["message"] and "Voiture au garage" in n["message"] for n in notes)
    assert all(o["id_trajet"] != id_trajet
               for o in client.get(f"/api/moi/demandes/{id_demande}/offres", headers=lina).json())

    # Republication : de nouveau proposé.
    r = client.post(f"/api/moi/conducteur/trajets/{id_trajet}/republication", headers=kevin, json={})
    assert r.status_code == 200 and r.json()["etat"] == "actif"
    assert client.post(f"/api/moi/conducteur/trajets/{id_trajet}/republication", headers=kevin,
                       json={}).status_code == 409
    assert any(o["id_trajet"] == id_trajet for o in client.get(f"/api/moi/demandes/{id_demande}/offres",
                                                                headers=lina).json())


def test_republier_un_trajet_ponctuel_a_une_nouvelle_date_et_retablir_une_date(client, sql, comptes):
    kevin = comptes["kevin"]
    hier = date.today() - timedelta(days=1)
    id_trajet = client.post("/api/moi/conducteur/trajets", headers=kevin, json=_trajet(
        "Logpom", "Akwa", "09:00", date_trajet=(date.today() + timedelta(days=2)).isoformat())).json()["id_trajet"]
    sql("UPDATE trajet SET date_unique = %s WHERE id_trajet = %s", (hier, id_trajet))       # le voyage a eu lieu
    assert client.get("/api/moi/conducteur/trajets", headers=kevin).json()[0]["etat"] == "passe"
    r = client.post(f"/api/moi/conducteur/trajets/{id_trajet}/republication", headers=kevin, json={})
    assert r.status_code == 422                                    # une nouvelle date est demandée
    nouvelle = (date.today() + timedelta(days=3)).isoformat()
    r = client.post(f"/api/moi/conducteur/trajets/{id_trajet}/republication", headers=kevin,
                    json={"date_trajet": nouvelle, "heure_depart": "10:15"})
    assert r.status_code == 200 and r.json()["date_unique"] == nouvelle and r.json()["heure_depart"] == "10:15"

    # Une date annulée d'un trajet régulier peut être rétablie.
    regulier = client.post("/api/moi/conducteur/trajets", headers=kevin, json=_trajet(
        "Bonanjo", "Logpom", "17:30", jours_semaine=[1, 2, 3, 4, 5, 6, 7])).json()["id_trajet"]
    jour = (date.today() + timedelta(days=2)).isoformat()
    client.post(f"/api/trajets/{regulier}/annulations", headers=kevin, json={"date_trajet": jour})
    t = next(t for t in client.get("/api/moi/conducteur/trajets", headers=kevin).json() if t["id_trajet"] == regulier)
    assert t["dates_annulees"] == [jour]
    assert client.delete(f"/api/moi/conducteur/trajets/{regulier}/annulations/{jour}", headers=kevin).status_code == 200
    t = next(t for t in client.get("/api/moi/conducteur/trajets", headers=kevin).json() if t["id_trajet"] == regulier)
    assert t["dates_annulees"] == []
