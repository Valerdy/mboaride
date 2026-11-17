"""Parcours complet de l'application mobile, sur la base partagée avec l'API Node.

Un conducteur et une passagère s'inscrivent sur l'API Node (simulée ici par sa table
`users`), créent leur profil métier, puis : agrément, véhicule, règles et publication côté
conducteur ; demande, offre calculée par le moteur et réservation côté passagère ; enfin
l'équipage, l'activité de l'agent, le retard, les gains et l'évaluation côté conducteur.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest

from app import config
from test_pont_node import jeton, porteur, secret_partage, table_users  # noqa: F401  (fixture)

KEVIN, LINA = 501, 502


@pytest.fixture()
def comptes(sql, secret_partage, monkeypatch):  # noqa: F811
    monkeypatch.setattr(config, "AGREMENT_AUTO", True)
    table_users(sql, [(KEVIN, "kevin@entreprise-a.cm", "+237690000501", "Kevin Ngando"),
                      (LINA, "lina@entreprise-a.cm", "+237690000502", "Lina Ebolo")])
    sql("UPDATE public.users SET is_verified = TRUE")
    return {"kevin": porteur(jeton(KEVIN)), "lina": porteur(jeton(LINA))}


def prochain_jour_ouvre() -> date:
    jour = date.today() + timedelta(days=1)
    while jour.weekday() > 4:
        jour += timedelta(days=1)
    return jour


def test_sans_profil_l_api_le_dit_puis_le_profil_est_cree(client, comptes):
    assert client.get("/api/moi/demandes", headers=comptes["lina"]).status_code == 403

    r = client.post("/api/moi/profil", headers=comptes["lina"])
    assert r.status_code == 200
    profil = r.json()
    assert profil["cree"] is True
    assert (profil["prenom"], profil["nom"]) == ("Lina", "Ebolo")
    # Même domaine d'e-mail qu'Entreprise A : rattachée à son cercle de confiance.
    assert [o["nom"] for o in profil["organisations"]] == ["Entreprise A (Bonanjo)"]

    # Idempotent : on peut le rappeler à chaque connexion.
    again = client.post("/api/moi/profil", headers=comptes["lina"]).json()
    assert again["cree"] is False and again["id_utilisateur"] == profil["id_utilisateur"]
    assert client.get("/api/moi/demandes", headers=comptes["lina"]).status_code == 200


def test_un_compte_de_demo_est_repris_et_non_duplique(client, sql, secret_partage):  # noqa: F811
    table_users(sql, [(600, "grace@entreprise-a.cm", "+237699999999", "Grâce Mbarga")])
    sql("UPDATE public.users SET is_verified = TRUE")
    r = client.post("/api/moi/profil", headers=porteur(jeton(600))).json()
    assert r["cree"] is False and r["prenom"] == "Grâce"


def test_parcours_conducteur_et_passagere(client, sql, comptes):
    kevin, lina = comptes["kevin"], comptes["lina"]
    client.post("/api/moi/profil", headers=kevin)
    client.post("/api/moi/profil", headers=lina)

    # --- Conducteur : agrément, véhicule, règles, publication ---------------------------
    trajet = {"depart": "logpom", "arrivee": "Bonanjo", "heure_depart": "06:50",
              "jours_semaine": [1, 2, 3, 4, 5], "places": 3, "detour_max_km": 3}
    assert client.post("/api/moi/conducteur/trajets", json=trajet, headers=kevin).status_code == 403

    for piece in ("piece_identite", "permis", "casier_judiciaire"):
        a = client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers=kevin).json()
    assert a["statut_agrement"] == "en_verification"
    a = client.post("/api/moi/conducteur/agrement/documents/assurance", headers=kevin).json()
    assert a["statut_agrement"] == "actif"
    assert all(d["statut"] == "valide" for d in a["documents"])

    assert client.post("/api/moi/conducteur/trajets", json=trajet, headers=kevin).status_code == 409
    v = client.put("/api/moi/conducteur/vehicule", headers=kevin, json={
        "marque_modele": "Berline 2014", "immatriculation": "lt 777 ab", "places_passagers": 3,
        "conso_l_100km": 8, "climatise": True})
    assert v.status_code == 200 and v.json()["immatriculation"] == "LT 777 AB"

    regles = client.put("/api/moi/conducteur/regles", headers=kevin, json={
        "collegues": True, "partenaires": True, "public": False, "eleves": False,
        "prix_min_fcfa": 0, "automatique": True}).json()
    assert regles["automatique"] is True

    inconnu = client.post("/api/moi/conducteur/trajets", json={**trajet, "depart": "Nulle Part"}, headers=kevin)
    assert inconnu.status_code == 422 and "Logpom" in inconnu.json()["detail"]
    pub = client.post("/api/moi/conducteur/trajets", json=trajet, headers=kevin)
    assert pub.status_code == 201, pub.text
    assert pub.json()["depart"] == "Logpom" and pub.json()["jours_semaine"] == "1111100"
    id_trajet = pub.json()["id_trajet"]

    # --- Passagère : demande, offre du moteur, réservation ---------------------------------
    jour = prochain_jour_ouvre()
    d = client.post("/api/demandes", headers=lina, json={
        "depart": {"libelle": "Kotto", "lat": 4.072, "lon": 9.766},
        "arrivee": {"libelle": "Bonanjo", "lat": 4.042, "lon": 9.689},
        "arrivee_au_plus_tot": "07:20", "arrivee_au_plus_tard": "07:55",
        "date_trajet": jour.isoformat(), "prix_max_fcfa": 800})
    assert d.status_code == 201, d.text
    id_demande = d.json()["id"]
    assert d.json()["cercle_max"] == "partenaires"

    offres = client.get(f"/api/moi/demandes/{id_demande}/offres", headers=lina).json()
    offre = next(o for o in offres if o["id_trajet"] == id_trajet)
    assert offre["confirmable"] and offre["conducteur"] == "Kevin" and offre["cercle"] == "organisation"

    r = client.post("/api/reservations", headers=lina, json={
        "id_demande": id_demande, "id_trajet": id_trajet, "date_trajet": jour.isoformat(),
        "prix_annonce_fcfa": offre["prix_fcfa"]})
    assert r.status_code == 201, r.text

    # --- Conducteur : équipage, activité, retard, gains, évaluation -----------------------
    eq = client.get("/api/moi/conducteur/equipage", headers=kevin).json()
    assert eq["id_trajet"] == id_trajet and eq["date_trajet"] == jour.isoformat()
    assert [a["passager"] for a in eq["arrets"]] == ["Lina"]
    assert eq["arrets"][0]["prix_fcfa"] == offre["prix_fcfa"]

    act = client.get("/api/moi/conducteur/activite", headers=kevin).json()
    assert act[0]["type"] == "reservation" and act[0]["passager"] == "Lina"

    assert client.post("/api/moi/conducteur/retard", headers=kevin, json={
        "id_trajet": id_trajet, "date_trajet": jour.isoformat(), "minutes": 10}).json()["passagers_prevenus"] == 1
    notes = client.get("/api/moi/notifications", headers=lina).json()
    assert notes[0]["type"] == "retard" and "Kevin" in notes[0]["message"]

    g = client.get("/api/moi/conducteur/gains", headers=kevin).json()
    assert g["paiements"][0]["recu"] is False and g["dernier_trajet_carburant_fcfa"] > 0

    ev = client.post("/api/moi/conducteur/evaluations", headers=kevin, json={
        "id_trajet": id_trajet, "date_trajet": jour.isoformat(), "notes": [{"passager": "Lina", "note": 5}]})
    assert ev.status_code == 201 and ev.json()["evaluations"] == 1


def test_les_regles_du_conducteur_filtrent_les_offres(client, sql, comptes):
    """Prix minimal appliqué par le moteur, et refus des collègues quand il les exclut."""
    kevin, lina = comptes["kevin"], comptes["lina"]
    client.post("/api/moi/profil", headers=kevin)
    client.post("/api/moi/profil", headers=lina)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers=kevin)
    client.put("/api/moi/conducteur/vehicule", headers=kevin, json={
        "marque_modele": "Berline", "immatriculation": "LT 1", "places_passagers": 3, "conso_l_100km": 8})
    id_trajet = client.post("/api/moi/conducteur/trajets", headers=kevin, json={
        "depart": "Logpom", "arrivee": "Bonanjo", "heure_depart": "06:50", "jours_semaine": [1, 2, 3, 4, 5],
        "places": 3, "detour_max_km": 3}).json()["id_trajet"]
    id_demande = client.post("/api/demandes", headers=lina, json={
        "depart": {"libelle": "Kotto", "lat": 4.072, "lon": 9.766},
        "arrivee": {"libelle": "Bonanjo", "lat": 4.042, "lon": 9.689},
        "arrivee_au_plus_tot": "07:20", "arrivee_au_plus_tard": "07:55",
        "date_trajet": prochain_jour_ouvre().isoformat(), "prix_max_fcfa": 5000}).json()["id"]

    def offre():
        return next((o for o in client.get(f"/api/moi/demandes/{id_demande}/offres", headers=lina).json()
                     if o["id_trajet"] == id_trajet), None)

    regles = {"collegues": True, "partenaires": True, "public": False, "eleves": True, "automatique": True}
    client.put("/api/moi/conducteur/regles", headers=kevin, json={**regles, "prix_min_fcfa": 1500})
    assert offre()["prix_fcfa"] == 1500
    client.put("/api/moi/conducteur/regles", headers=kevin, json={**regles, "collegues": False, "prix_min_fcfa": 0})
    assert offre() is None


def test_un_trajet_regulier_n_est_pas_propose_un_jour_ou_il_ne_roule_pas(client, comptes):
    kevin, lina = comptes["kevin"], comptes["lina"]
    client.post("/api/moi/profil", headers=kevin)
    client.post("/api/moi/profil", headers=lina)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers=kevin)
    client.put("/api/moi/conducteur/vehicule", headers=kevin, json={
        "marque_modele": "Berline", "immatriculation": "LT 2", "places_passagers": 3, "conso_l_100km": 8})
    id_trajet = client.post("/api/moi/conducteur/trajets", headers=kevin, json={
        "depart": "Logpom", "arrivee": "Bonanjo", "heure_depart": "06:50", "jours_semaine": [1, 2, 3, 4, 5],
        "places": 3}).json()["id_trajet"]
    samedi = date.today() + timedelta(days=(5 - date.today().weekday()) % 7 or 7)
    id_demande = client.post("/api/demandes", headers=lina, json={
        "depart": {"libelle": "Kotto", "lat": 4.072, "lon": 9.766},
        "arrivee": {"libelle": "Bonanjo", "lat": 4.042, "lon": 9.689},
        "arrivee_au_plus_tot": "07:20", "arrivee_au_plus_tard": "07:55",
        "date_trajet": samedi.isoformat(), "prix_max_fcfa": 800}).json()["id"]
    ids = [o["id_trajet"] for o in client.get(f"/api/moi/demandes/{id_demande}/offres", headers=lina).json()]
    assert id_trajet not in ids
    motifs = client.get(f"/api/moi/demandes/{id_demande}/diagnostic", headers=lina).json()["motifs"]
    assert "jour" in [m["code"] for m in motifs]


def test_lieux_connus(client):
    noms = [l["nom"] for l in client.get("/api/lieux?q=bon").json()]
    assert {"Bonanjo", "Bonabéri", "Bonapriso", "Bonamoussadi"} <= set(noms)
    d = client.get("/api/lieux/distance", params={"de": "Logpom", "a": "bonanjo"}).json()
    assert d["a"] == "Bonanjo" and 8 < d["distance_km"] < 20
