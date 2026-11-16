"""US17 · Comptes élèves et autorisation parentale. US19 · Notifications au parent."""

from __future__ import annotations

from conftest import GRACE, MIREILLE, comme


def test_le_parent_ne_voit_que_ses_eleves(client):
    mes = client.get("/api/moi/eleves", headers=comme(MIREILLE)).json()
    assert [e["prenom"] for e in mes] == ["Ange", "Marc"]
    assert all(e["autorisation_active"] for e in mes)
    assert client.get("/api/moi/eleves", headers=comme(GRACE)).json() == []


def test_un_eleve_de_moins_de_12_ans_est_refuse(client):
    r = client.post("/api/moi/eleves", headers=comme(MIREILLE),
                    json={"prenom": "Lina", "age": 10})
    assert r.status_code == 422
    assert "12" in r.text


def test_creation_d_un_compte_eleve(client):
    r = client.post("/api/moi/eleves", headers=comme(MIREILLE),
                    json={"prenom": "Lina", "age": 13, "id_etablissement": 3})
    assert r.status_code == 201
    cree = r.json()
    assert cree["prenom"] == "Lina" and cree["age"] == 13
    assert cree["autorisation_active"] is True
    assert cree["etablissement"]
    assert len(client.get("/api/moi/eleves", headers=comme(MIREILLE)).json()) == 3


def test_un_eleve_d_un_autre_parent_est_invisible(client, sql):
    id_ange = sql("SELECT id_eleve FROM compte_eleve WHERE prenom = 'Ange'")[0]["id_eleve"]
    assert client.get(f"/api/moi/eleves/{id_ange}/journal",
                      headers=comme(GRACE)).status_code == 404
    assert client.put(f"/api/moi/eleves/{id_ange}/autorisation", headers=comme(GRACE),
                      json={"active": False}).status_code == 404


def test_retirer_l_autorisation_empeche_toute_reservation(client, sql):
    id_marc = sql("SELECT id_eleve FROM compte_eleve WHERE prenom = 'Marc'")[0]["id_eleve"]
    r = client.put(f"/api/moi/eleves/{id_marc}/autorisation", headers=comme(MIREILLE),
                   json={"active": False})
    assert r.status_code == 200 and r.json()["autorisation_active"] is False

    # La base elle-même refuse la réservation : c'est le déclencheur, pas seulement l'API.
    sql("""INSERT INTO demande (id_demandeur, id_eleve, type_trajet, depart_libelle, depart_lat,
               depart_lon, arrivee_libelle, arrivee_lat, arrivee_lon, arrivee_au_plus_tot,
               arrivee_au_plus_tard, date_unique, prix_max_fcfa, cercle_max)
           VALUES (%s, %s, 'urbain', 'Makepe', 4.081, 9.752, 'Bonapriso', 4.033, 9.695,
                   '07:00', '08:00', '2026-11-20', 2000, 'public')""", (MIREILLE, id_marc))
    id_demande = sql("SELECT max(id_demande) m FROM demande")[0]["m"]
    try:
        sql("""INSERT INTO reservation (id_demande, id_trajet, date_trajet, heure_prise_en_charge,
                   heure_arrivee_estimee, prix_fcfa, niveau_cercle)
               VALUES (%s, 3, '2026-11-20', '06:40', '07:05', 500, 'public')""", (id_demande,))
        raise AssertionError("la réservation aurait dû être refusée")
    except Exception as exc:                        # psycopg.errors.RaiseException
        assert "utorisation" in str(exc)

    client.put(f"/api/moi/eleves/{id_marc}/autorisation", headers=comme(MIREILLE),
               json={"active": True})
    sql("""INSERT INTO reservation (id_demande, id_trajet, date_trajet, heure_prise_en_charge,
               heure_arrivee_estimee, prix_fcfa, niveau_cercle)
           VALUES (%s, 3, '2026-11-20', '06:40', '07:05', 500, 'public')""", (id_demande,))


def test_journal_et_notifications_de_depart_et_d_arrivee(client, sql):
    id_ange = sql("SELECT id_eleve FROM compte_eleve WHERE prenom = 'Ange'")[0]["id_eleve"]
    id_lina = client.post("/api/moi/eleves", headers=comme(MIREILLE),
                          json={"prenom": "Lina", "age": 13}).json()["id_eleve"]
    # Un élève sans trajet n'a pas de journal et rien à simuler
    assert client.get(f"/api/moi/eleves/{id_lina}/journal",
                      headers=comme(MIREILLE)).json() == []
    assert client.post(f"/api/moi/eleves/{id_lina}/simuler-trajet",
                       headers=comme(MIREILLE)).status_code == 409

    sql("""INSERT INTO demande (id_demandeur, id_eleve, type_trajet, depart_libelle, depart_lat,
               depart_lon, arrivee_libelle, arrivee_lat, arrivee_lon, arrivee_au_plus_tot,
               arrivee_au_plus_tard, date_unique, prix_max_fcfa, cercle_max)
           VALUES (%s, %s, 'urbain', 'Makepe', 4.081, 9.752, 'Bonapriso', 4.033, 9.695,
                   '07:00', '08:00', '2026-11-20', 2000, 'public')""", (MIREILLE, id_ange))
    id_demande = sql("SELECT max(id_demande) m FROM demande")[0]["m"]
    sql("""INSERT INTO reservation (id_demande, id_trajet, date_trajet, heure_prise_en_charge,
               heure_arrivee_estimee, prix_fcfa, niveau_cercle)
           VALUES (%s, 3, '2026-11-20', '06:40', '07:05', 500, 'public')""", (id_demande,))

    r = client.post(f"/api/moi/eleves/{id_ange}/simuler-trajet", headers=comme(MIREILLE))
    assert r.status_code == 201 and len(r.json()["notifications"]) == 2

    journal = client.get(f"/api/moi/eleves/{id_ange}/journal", headers=comme(MIREILLE)).json()
    types = [ligne["type"] for ligne in journal]
    assert "reservation" in types and "depart" in types and "arrivee" in types
    arrivee = next(ligne for ligne in journal if ligne["type"] == "arrivee")
    assert "Ange" in arrivee["libelle"] and "Bonapriso" in arrivee["libelle"]
    # Les notifications du parent sont aussi dans sa boîte d'alertes
    alertes = client.get("/api/moi/notifications", headers=comme(MIREILLE)).json()
    assert any(a["type"] == "depart" for a in alertes)
