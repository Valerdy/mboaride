"""US22 · Réserver une place dans un voyage interurbain plusieurs jours à l'avance."""

from __future__ import annotations

from datetime import date, timedelta

from conftest import GRACE, MIREILLE, comme

JOUR = "2026-11-20"          # voyage Akwa → Yaoundé des données d'exemple


def _voyages(client, uid=GRACE, jour=JOUR):
    return client.get(f"/api/voyages?date={jour}", headers=comme(uid)).json()


def test_les_voyages_du_jour_sont_listes_avec_leurs_points_de_montee(client):
    voyages = _voyages(client)
    assert len(voyages) == 1
    v = voyages[0]
    assert v["arrivee_libelle"] == "Yaoundé"
    assert v["heure_depart"] == "14:00"
    assert v["places_restantes"] >= 1
    assert [p["libelle"] for p in v["points_depart"]] == ["Akwa", "Ndokoti"]
    assert v["prix_fcfa"] > 0
    assert v["peage_fcfa"] == 1000


def test_aucun_voyage_a_une_autre_date(client):
    assert _voyages(client, jour="2026-11-21") == []


def test_reserver_une_place_cree_la_demande_et_la_reservation(client, sql):
    v = _voyages(client)[0]
    avant = v["places_restantes"]
    point = v["points_depart"][1]          # Ndokoti, départ 14:20

    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                    json={"id_point_depart": point["id_point"], "date_trajet": JOUR,
                          "prix_annonce_fcfa": None})
    assert r.status_code == 201, r.text
    reservation = r.json()
    assert reservation["point_depart"] == "Ndokoti"
    assert reservation["prix_fcfa"] > 0
    assert reservation["paiement"].startswith("en attente")

    demande = sql("SELECT * FROM demande WHERE id_demande = %s",
                  (reservation["id_demande"],))[0]
    assert demande["type_trajet"] == "interurbain"
    assert demande["depart_libelle"] == "Ndokoti"
    assert demande["arrivee_libelle"] == "Yaoundé"
    assert demande["statut"] == "satisfaite"
    assert _voyages(client)[0]["places_restantes"] == avant - 1


def test_un_prix_perime_refuse_la_reservation_sans_rien_enregistrer(client, sql):
    v = _voyages(client)[0]
    demandes = sql("SELECT count(*) n FROM demande")[0]["n"]

    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                    json={"id_point_depart": v["points_depart"][0]["id_point"],
                          "date_trajet": JOUR, "prix_annonce_fcfa": v["prix_fcfa"] + 100})
    assert r.status_code == 409
    assert r.json()["detail"]["nouveau_prix_fcfa"] == v["prix_fcfa"]
    assert sql("SELECT count(*) n FROM demande")[0]["n"] == demandes


def test_une_date_passee_ou_un_point_inconnu_sont_refuses(client):
    v = _voyages(client)[0]
    hier = (date.today() - timedelta(days=1)).isoformat()
    assert client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                       json={"id_point_depart": v["points_depart"][0]["id_point"],
                             "date_trajet": hier}).status_code == 422
    assert client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                       json={"id_point_depart": 999, "date_trajet": JOUR}).status_code == 422


def test_un_parent_reserve_pour_son_eleve_si_l_autorisation_est_active(client, sql):
    v = _voyages(client, uid=MIREILLE)[0]
    id_marc = sql("SELECT id_eleve FROM compte_eleve WHERE prenom = 'Marc'")[0]["id_eleve"]
    corps = {"id_point_depart": v["points_depart"][0]["id_point"], "date_trajet": JOUR,
             "id_eleve": id_marc}

    client.put(f"/api/moi/eleves/{id_marc}/autorisation", headers=comme(MIREILLE),
               json={"active": False})
    refus = client.post(f"/api/voyages/{v['id_trajet']}/reservations",
                        headers=comme(MIREILLE), json=corps)
    assert refus.status_code == 409 and "utorisation" in refus.text

    client.put(f"/api/moi/eleves/{id_marc}/autorisation", headers=comme(MIREILLE),
               json={"active": True})
    ok = client.post(f"/api/voyages/{v['id_trajet']}/reservations",
                     headers=comme(MIREILLE), json=corps)
    assert ok.status_code == 201, ok.text
    assert ok.json()["id_eleve"] == id_marc


def test_un_eleve_d_un_autre_parent_est_refuse(client, sql):
    v = _voyages(client)[0]
    id_marc = sql("SELECT id_eleve FROM compte_eleve WHERE prenom = 'Marc'")[0]["id_eleve"]
    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                    json={"id_point_depart": v["points_depart"][0]["id_point"],
                          "date_trajet": JOUR, "id_eleve": id_marc})
    assert r.status_code == 404
