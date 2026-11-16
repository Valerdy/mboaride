"""US09 · Connaître le prix avant de confirmer."""

from app import moteur
from conftest import GRACE, JUNIOR, NADEGE, comme


def _attendu(sql, id_demande, id_trajet, niveau):
    d = sql("SELECT * FROM demande WHERE id_demande = %s", (id_demande,))[0]
    t = sql("""SELECT t.*, v.conso_l_100km, v.climatise, v.non_fumeur FROM trajet t
                JOIN vehicule v USING (id_vehicule) WHERE id_trajet = %s""", (id_trajet,))[0]
    return moteur.detail_prix(moteur.driver_from_row(t), moteur.request_from_row(d), niveau).prix_fcfa


def test_prix_detaille_identique_au_moteur(client, sql):
    r = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(GRACE))
    assert r.status_code == 200
    e = r.json()
    assert e["cercle"] == "organisation"
    assert e["prix_fcfa"] == _attendu(sql, 1, 1, 0)
    assert e["commission_fcfa"] == 0
    libelles = [l["libelle"] for l in e["detail"]]
    assert libelles[0].startswith("Carburant du trajet") and "Partagé entre 4 occupants" in libelles[1]
    assert e["detail"][-1]["montant_fcfa"] == e["prix_fcfa"]
    assert e["dans_le_budget"] and e["horaires_compatibles"] and e["confirmable"]
    assert e["prise_en_charge"] < e["arrivee_estimee"]


def test_interurbain_peage_et_commission(client, sql):
    e = client.post("/api/prix/estimation", json={"id_demande": 5, "id_trajet": 2}, headers=comme(JUNIOR)).json()
    assert e["cercle"] == "public"
    assert e["prix_fcfa"] == _attendu(sql, 5, 2, 2)
    assert any(l["libelle"] == "Péage" and l["montant_fcfa"] == 1000 for l in e["detail"])
    assert e["commission_fcfa"] > 0
    assert abs(e["commission_fcfa"] - e["prix_fcfa"] * 0.1 / 1.1) <= 1


def test_offre_hors_du_cercle_refusee(client):
    # Grâce s'arrête aux partenaires, Brice (trajet 3) n'est que dans le réseau public.
    r = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 3}, headers=comme(GRACE))
    assert r.status_code == 422 and "cercle" in r.json()["detail"]


def test_demande_d_un_autre_utilisateur(client):
    r = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(NADEGE))
    assert r.status_code == 403


def test_confirmation_au_prix_annonce(client, sql):
    e = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(GRACE)).json()
    r = client.post("/api/reservations", headers=comme(GRACE), json={
        "id_demande": 1, "id_trajet": 1, "date_trajet": "2026-11-18", "prix_annonce_fcfa": e["prix_fcfa"]})
    assert r.status_code == 201, r.text
    res = sql("""SELECT r.prix_fcfa, r.niveau_cercle, p.montant_fcfa, p.statut FROM reservation r
                  JOIN paiement p USING (id_reservation) WHERE r.id_reservation = %s""",
              (r.json()["id_reservation"],))[0]
    assert res["prix_fcfa"] == res["montant_fcfa"] == e["prix_fcfa"]
    assert res["niveau_cercle"] == "organisation" and res["statut"] == "en_attente"


def test_prix_modifie_entre_affichage_et_confirmation(client, sql):
    e = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(GRACE)).json()
    sql("UPDATE vehicule SET conso_l_100km = 12 WHERE id_vehicule = 1")      # le conducteur change de voiture
    r = client.post("/api/reservations", headers=comme(GRACE), json={
        "id_demande": 1, "id_trajet": 1, "date_trajet": "2026-11-18", "prix_annonce_fcfa": e["prix_fcfa"]})
    assert r.status_code == 409
    assert r.json()["detail"]["nouveau_prix_fcfa"] > e["prix_fcfa"]
    assert sql("SELECT count(*) n FROM reservation WHERE date_trajet = '2026-11-18'")[0]["n"] == 0


def test_prix_superieur_au_maximum(client, sql):
    sql("UPDATE demande SET prix_max_fcfa = 100 WHERE id_demande = 1")
    e = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(GRACE)).json()
    assert not e["dans_le_budget"] and not e["confirmable"]
    r = client.post("/api/reservations", headers=comme(GRACE), json={
        "id_demande": 1, "id_trajet": 1, "date_trajet": "2026-11-18", "prix_annonce_fcfa": e["prix_fcfa"]})
    assert r.status_code == 422


def test_pas_deux_reservations_le_meme_jour(client):
    e = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(GRACE)).json()
    r = client.post("/api/reservations", headers=comme(GRACE), json={
        "id_demande": 1, "id_trajet": 1, "date_trajet": "2026-11-17", "prix_annonce_fcfa": e["prix_fcfa"]})
    assert r.status_code == 409


def test_liste_des_offres_triee(client):
    offres = client.get("/api/moi/demandes/1/offres", headers=comme(GRACE)).json()
    assert offres and all(o["cercle"] in ("organisation", "partenaires") for o in offres)
    confirmables = [o["prix_fcfa"] for o in offres if o["confirmable"]]
    assert confirmables == sorted(confirmables)
