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


def test_reserver_plusieurs_places_dans_un_voyage(client, sql):
    v = _voyages(client)[0]
    restantes = v["places_restantes"]
    assert restantes >= 2
    # Même prix de la place quel que soit le point de montée, deux places = deux fois ce prix.
    corps = {"date_trajet": JOUR, "nb_places": 2}
    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                    json={**corps, "id_point_depart": v["points_depart"][1]["id_point"],
                          "prix_annonce_fcfa": v["prix_fcfa"]})          # prix d'une seule place : refusé
    assert r.status_code == 409 and r.json()["detail"]["nouveau_prix_fcfa"] == 2 * v["prix_fcfa"]
    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                    json={**corps, "id_point_depart": v["points_depart"][1]["id_point"],
                          "prix_annonce_fcfa": 2 * v["prix_fcfa"]})
    assert r.status_code == 201, r.text
    assert r.json()["nb_places"] == 2 and r.json()["prix_fcfa"] == 2 * v["prix_fcfa"]
    assert sql("SELECT nb_places FROM demande WHERE id_demande = %s", (r.json()["id_demande"],))[0]["nb_places"] == 2
    assert _voyages(client)[0]["places_restantes"] == restantes - 2
    assert _voyages(client)[0]["prix_fcfa"] == v["prix_fcfa"]            # le prix d'une place n'a pas bougé

    # Plus de places que ce qu'il reste : refusé, rien n'est enregistré.
    demandes = sql("SELECT count(*) n FROM demande")[0]["n"]
    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(MIREILLE),
                    json={"id_point_depart": v["points_depart"][0]["id_point"], "date_trajet": JOUR,
                          "nb_places": restantes})
    assert r.status_code == 409
    assert sql("SELECT count(*) n FROM demande")[0]["n"] == demandes


# --- Point de départ choisi par le voyageur ------------------------------------------------------

BONAMOUSSADI = {"libelle": "Bonamoussadi, carrefour Shell", "lat": 4.0850, "lon": 9.7350}
BAFOUSSAM = {"libelle": "Bafoussam", "lat": 5.4737, "lon": 10.4179}


def _verifier(client, v, lieu, uid=GRACE, nb=1):
    return client.post(f"/api/voyages/{v['id_trajet']}/depart-libre/verification", headers=comme(uid),
                       json={"depart_libre": lieu, "date_trajet": JOUR, "nb_places": nb})


def test_un_point_de_depart_libre_est_verifie_avant_de_reserver(client):
    v = _voyages(client)[0]
    ok = _verifier(client, v, BONAMOUSSADI, nb=2)
    assert ok.status_code == 200, ok.text
    corps = ok.json()
    assert corps["ok"] is True and corps["detour_km"] <= corps["detour_max_km"] == 8.0
    assert corps["prise_en_charge"] < corps["arrivee_estimee"]
    # Même prix de la place qu'à un point de montée du conducteur, deux places = deux fois ce prix.
    assert corps["prix_par_place_fcfa"] == v["prix_fcfa"] and corps["prix_fcfa"] == 2 * v["prix_fcfa"]

    loin = _verifier(client, v, BAFOUSSAM).json()
    assert loin["ok"] is False and "de détour au conducteur" in loin["message"]
    assert _verifier(client, v, {"libelle": "Paris", "lat": 48.85, "lon": 2.35}).json()["ok"] is False


def test_reserver_a_son_propre_point_de_depart(client, sql):
    v = _voyages(client)[0]
    avant = v["places_restantes"]
    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                    json={"depart_libre": BONAMOUSSADI, "date_trajet": JOUR, "prix_annonce_fcfa": v["prix_fcfa"]})
    assert r.status_code == 201, r.text
    reservation = r.json()
    assert reservation["point_depart"] == BONAMOUSSADI["libelle"] and reservation["depart_libre"] is True
    assert reservation["prix_fcfa"] == v["prix_fcfa"]                  # même prix que depuis Akwa ou Ndokoti
    demande = sql("SELECT depart_libelle, depart_lat, depart_lon FROM demande WHERE id_demande = %s",
                  (reservation["id_demande"],))[0]
    assert demande["depart_libelle"] == BONAMOUSSADI["libelle"] and float(demande["depart_lat"]) == 4.085
    assert _voyages(client)[0]["places_restantes"] == avant - 1


def test_un_point_trop_loin_ou_un_choix_ambigu_est_refuse(client, sql):
    v = _voyages(client)[0]
    demandes = sql("SELECT count(*) n FROM demande")[0]["n"]
    r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE),
                    json={"depart_libre": BAFOUSSAM, "date_trajet": JOUR})
    assert r.status_code == 422 and "de détour au conducteur" in r.json()["detail"]
    assert sql("SELECT count(*) n FROM demande")[0]["n"] == demandes

    # Il faut un point de la liste ou un point libre, pas les deux ni aucun.
    point = v["points_depart"][0]["id_point"]
    for corps in ({"date_trajet": JOUR}, {"date_trajet": JOUR, "id_point_depart": point, "depart_libre": BONAMOUSSADI}):
        r = client.post(f"/api/voyages/{v['id_trajet']}/reservations", headers=comme(GRACE), json=corps)
        assert r.status_code == 422
