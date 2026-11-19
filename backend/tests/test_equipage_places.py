"""Même somme pour tous les passagers d'un équipage, et plusieurs places dans une même réservation.

Kevin conduit Logpom → Bonanjo avec trois places (fixture `equipage`, voir
test_portefeuille_fin_de_course.py). Lina, Paul et un invité y réservent.
"""

from __future__ import annotations

from conftest import comme  # noqa: F401
from test_pont_node import jeton, porteur, secret_partage, table_users  # noqa: F401  (fixture)
from test_portefeuille_fin_de_course import LINA, PAUL, equipage  # noqa: F401  (fixture)

LOGPOM = {"libelle": "Logpom", "lat": 4.0846, "lon": 9.7562}
PLUS_LOIN = {"libelle": "Bonamoussadi", "lat": 4.0800, "lon": 9.7600}
BONANJO = {"libelle": "Bonanjo", "lat": 4.042, "lon": 9.689}


def demander(client, h, qui, depart, nb_places=1, prix_max=2000):
    d = client.post("/api/demandes", headers=h[qui], json={
        "depart": depart, "arrivee": BONANJO, "arrivee_au_plus_tot": "07:15", "arrivee_au_plus_tard": "08:00",
        "date_trajet": h["jour"], "prix_max_fcfa": prix_max, "cercle_max": "public", "nb_places": nb_places})
    assert d.status_code == 201, d.text
    return d.json()["id"]


def offre_du_trajet(client, h, qui, id_demande):
    offres = client.get(f"/api/moi/demandes/{id_demande}/offres", headers=h[qui]).json()
    return next((o for o in offres if o["id_trajet"] == h["id_trajet"]), None)


def reserver(client, h, qui, id_demande, offre):
    return client.post("/api/reservations", headers=h[qui], json={
        "id_demande": id_demande, "id_trajet": h["id_trajet"], "date_trajet": h["jour"],
        "prix_annonce_fcfa": offre["prix_fcfa"]})


def test_tous_les_passagers_de_l_equipage_paient_la_meme_somme(client, sql, equipage):  # noqa: F811
    h = equipage
    lina = offre_du_trajet(client, h, "lina", demander(client, h, "lina", LOGPOM))
    paul = offre_du_trajet(client, h, "paul", demander(client, h, "paul", PLUS_LOIN))
    # Points de montée différents, détours différents, même prix.
    assert lina["detour_km"] != paul["detour_km"]
    assert lina["prix_par_place_fcfa"] == paul["prix_par_place_fcfa"] and lina["prix_fcfa"] == paul["prix_fcfa"]
    assert lina["prix_fcfa"] % 25 == 0 and lina["commission_fcfa"] == lina["prix_fcfa"] // 10

    # L'ordre des réservations ne change rien non plus : le premier ne paie pas plus que le suivant.
    assert reserver(client, h, "lina", lina["id_demande"], lina).status_code == 201
    apres = offre_du_trajet(client, h, "paul", paul["id_demande"])
    assert apres["passagers_deja_a_bord"] == 1 and apres["prix_fcfa"] == lina["prix_fcfa"]


def test_reserver_plusieurs_places(client, sql, equipage):  # noqa: F811
    h = equipage
    id_demande = demander(client, h, "lina", LOGPOM, nb_places=2)
    seule = offre_du_trajet(client, h, "paul", demander(client, h, "paul", LOGPOM))
    offre = offre_du_trajet(client, h, "lina", id_demande)
    # Deux places : deux fois le prix d'une place, la commission aussi ; le budget se compare au prix d'une place.
    assert offre["nb_places"] == 2 and offre["prix_par_place_fcfa"] == seule["prix_par_place_fcfa"]
    assert offre["prix_fcfa"] == 2 * offre["prix_par_place_fcfa"]
    assert offre["commission_fcfa"] == 2 * seule["commission_fcfa"]
    assert offre["detail"][-1] == {"libelle": f"2 places × {offre['prix_par_place_fcfa']} FCFA",
                                   "montant_fcfa": offre["prix_fcfa"]}
    assert offre["dans_le_budget"] and offre["confirmable"]

    # Un prix annoncé pour une seule place ne vaut pas pour deux.
    faux = client.post("/api/reservations", headers=h["lina"], json={
        "id_demande": id_demande, "id_trajet": h["id_trajet"], "date_trajet": h["jour"],
        "prix_annonce_fcfa": offre["prix_par_place_fcfa"]})
    assert faux.status_code == 409 and faux.json()["detail"]["nouveau_prix_fcfa"] == offre["prix_fcfa"]

    r = reserver(client, h, "lina", id_demande, offre)
    assert r.status_code == 201, r.text
    assert r.json()["nb_places"] == 2 and r.json()["prix_fcfa"] == offre["prix_fcfa"]
    ligne = sql("SELECT r.nb_places, r.prix_fcfa, p.montant_fcfa, p.commission_fcfa FROM reservation r "
                "JOIN paiement p USING (id_reservation) WHERE r.id_reservation = %s", (r.json()["id_reservation"],))[0]
    assert (ligne["nb_places"], ligne["montant_fcfa"], ligne["commission_fcfa"]) == (2, offre["prix_fcfa"],
                                                                                    offre["commission_fcfa"])
    mes = client.get("/api/moi/reservations", headers=h["lina"]).json()
    assert mes[0]["nb_places"] == 2 and mes[0]["prix_fcfa"] == offre["prix_fcfa"]


def test_les_places_se_comptent_une_a_une_dans_la_voiture(client, sql, equipage):  # noqa: F811
    h = equipage                                   # trois places dans la voiture de Kevin
    id_lina = demander(client, h, "lina", LOGPOM, nb_places=2)
    assert reserver(client, h, "lina", id_lina, offre_du_trajet(client, h, "lina", id_lina)).status_code == 201

    # Il ne reste qu'une place : deux places ne sont plus proposées, avec le motif.
    id_paul = demander(client, h, "paul", LOGPOM, nb_places=2)
    assert offre_du_trajet(client, h, "paul", id_paul) is None
    diag = client.get(f"/api/moi/demandes/{id_paul}/diagnostic", headers=h["paul"]).json()
    assert any(m["code"] == "complet" for m in diag["motifs"])
    estimation = client.post("/api/prix/estimation", json={"id_demande": id_paul, "id_trajet": h["id_trajet"]},
                             headers=h["paul"])
    assert estimation.status_code == 409 and "Il ne reste que 1 place" in estimation.json()["detail"]

    # Une place seule passe ; la voiture est alors pleine.
    id_une = demander(client, h, "paul", LOGPOM, nb_places=1)
    assert reserver(client, h, "paul", id_une, offre_du_trajet(client, h, "paul", id_une)).status_code == 201
    assert sql("SELECT coalesce(sum(nb_places), 0) n FROM reservation WHERE statut = 'confirmee' "
               "AND id_trajet = %s AND date_trajet = %s", (h["id_trajet"], h["jour"]))[0]["n"] == 3
    id_trop = demander(client, h, "paul", LOGPOM, nb_places=1)
    assert offre_du_trajet(client, h, "paul", id_trop) is None


def test_la_base_refuse_plus_de_places_que_la_voiture(client, sql, equipage):  # noqa: F811
    import psycopg
    import pytest
    h = equipage
    id_demande = demander(client, h, "lina", LOGPOM, nb_places=2)
    ok = reserver(client, h, "lina", id_demande, offre_du_trajet(client, h, "lina", id_demande))
    assert ok.status_code == 201
    autre = demander(client, h, "paul", LOGPOM, nb_places=1)
    with pytest.raises(psycopg.errors.RaiseException, match="complet|place"):
        sql("INSERT INTO reservation (id_demande, id_trajet, date_trajet, heure_prise_en_charge, "
            "heure_arrivee_estimee, prix_fcfa, niveau_cercle, nb_places, statut) "
            "VALUES (%s, %s, %s, '06:55', '07:30', 100, 'public', 2, 'confirmee')",
            (autre, h["id_trajet"], h["jour"]))


def test_plus_de_places_que_l_offre_n_est_jamais_confirmable(client, equipage):  # noqa: F811
    h = equipage
    id_demande = demander(client, h, "lina", LOGPOM, nb_places=4)
    assert offre_du_trajet(client, h, "lina", id_demande) is None
    r = client.post("/api/prix/estimation", json={"id_demande": id_demande, "id_trajet": h["id_trajet"]},
                    headers=h["lina"])
    assert r.status_code == 409 and "n'offre que 3 place(s)" in r.json()["detail"]
    nulle = client.post("/api/demandes", headers=h["lina"], json={
        "depart": LOGPOM, "arrivee": BONANJO, "arrivee_au_plus_tot": "07:15", "arrivee_au_plus_tard": "08:00",
        "date_trajet": h["jour"], "prix_max_fcfa": 2000, "nb_places": 0})
    assert nulle.status_code == 422


# --- Tarif en ville : Ndokoti → Yassa, trois places ----------------------------------------------

NDOKOTI = {"libelle": "Ndokoti", "lat": 4.0440, "lon": 9.7370}
YASSA = {"libelle": "Yassa", "lat": 4.0020, "lon": 9.8030}


def test_le_prix_de_reference_ndokoti_yassa_est_de_400_fcfa_la_place(client, sql, equipage):  # noqa: F811
    from app import moteur
    from app.moteur import Demande, Trajet
    from mboaride_agents.routing import Point

    km = moteur.distance_km(NDOKOTI["lat"], NDOKOTI["lon"], YASSA["lat"], YASSA["lon"])
    assert 11.0 <= km <= 13.0                                   # le trajet de référence : environ 11,9 km
    trajet = Trajet(origine=Point(NDOKOTI["lat"], NDOKOTI["lon"]), destination=Point(YASSA["lat"], YASSA["lon"]),
                    depart_min=420, places=3, detour_max_m=3000, conso_l100=8.0, confort=frozenset(),
                    peage_fcfa=0, interurbain=False)
    demande = Demande(Point(NDOKOTI["lat"], NDOKOTI["lon"]), Point(YASSA["lat"], YASSA["lon"]), 0, 1439, frozenset())
    d = moteur.detail_prix(trajet, demande, 2)
    assert 375 <= d.prix_fcfa <= 425 and d.prix_fcfa % 25 == 0
    assert d.devis.usage_cost > 0
    assert [l["libelle"] for l in d.lignes()][1].startswith("Usure et entretien")


def test_le_coefficient_urbain_se_regle_dans_la_console_et_ne_touche_pas_l_interurbain(client, sql, equipage):  # noqa: F811
    from app import moteur, parametres
    from app.moteur import Demande, Trajet
    from mboaride_agents.routing import Point

    ville = Trajet(Point(4.088, 9.765), Point(4.042, 9.689), 410, 3, 3000, 8.0, frozenset(), 0, False)
    car = Trajet(Point(4.050, 9.698), Point(3.8667, 11.5167), 840, 4, 8000, 8.0, frozenset(), 1000, True)
    dv = Demande(Point(4.088, 9.765), Point(4.042, 9.689), 0, 1439, frozenset())
    di = Demande(Point(4.050, 9.698), Point(3.8667, 11.5167), 0, 1439, frozenset())
    avant_ville, avant_car = moteur.detail_prix(ville, dv, 2).prix_fcfa, moteur.detail_prix(car, di, 2).prix_fcfa

    sql("INSERT INTO parametre (cle, valeur) VALUES ('coefficient_urbain_pct', 100) ON CONFLICT (cle) DO UPDATE "
        "SET valeur = 100")
    parametres.invalider()
    sans = moteur.detail_prix(ville, dv, 2)
    assert sans.devis.usage_cost == 0 and sans.prix_fcfa < avant_ville
    assert moteur.detail_prix(car, di, 2).prix_fcfa == avant_car          # l'interurbain ne change pas
