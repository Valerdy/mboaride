"""SR-47 · Annulation par le conducteur, réaffectation, scénarios de démonstration."""

from conftest import ARMAND, GRACE, NADEGE, comme


def test_annulation_rembourse_et_previent(client, sql):
    # Réservation 2 : Grâce avec Armand le 17/11, payée.
    sql("""INSERT INTO paiement (id_reservation, montant_fcfa, operateur, reference_transaction, statut, paye_le)
           VALUES (2, 175, 'mtn', 'MBR-TEST', 'reussi', now())""")
    assert client.post("/api/trajets/1/annulations", headers=comme(GRACE),
                       json={"date_trajet": "2026-11-17"}).status_code == 403
    r = client.post("/api/trajets/1/annulations", headers=comme(ARMAND),
                    json={"date_trajet": "2026-11-17", "motif": "panne"}).json()
    assert r["reservations_annulees"] == 1 and r["passagers"][0]["paiement"] == "rembourse"
    assert sql("SELECT statut FROM reservation WHERE id_reservation = 2")[0]["statut"] == "annulee"
    assert {n["type"] for n in sql("SELECT type FROM notification WHERE id_utilisateur = %s", (GRACE,))} >= {
        "annulation", "remboursement"}
    assert client.post("/api/trajets/1/annulations", headers=comme(ARMAND),
                       json={"date_trajet": "2026-11-17"}).status_code == 409
    # Le trajet annulé n'est plus réservable ce jour-là.
    e = client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(GRACE)).json()
    r = client.post("/api/reservations", headers=comme(GRACE), json={
        "id_demande": 1, "id_trajet": 1, "date_trajet": "2026-11-17", "prix_annonce_fcfa": e["prix_fcfa"]})
    assert r.status_code == 409 and "annulé" in r.json()["detail"]


def test_reaffectation_automatique_en_mode_autonome(client, sql):
    # Deux conducteurs collègues sur le même axe ; Grâce en mode autonome, placée avec Armand.
    sql("""INSERT INTO utilisateur (nom, prenom, telephone, email, mot_de_passe_hache, est_conducteur,
               statut_agrement, date_agrement) VALUES ('Mbida', 'Eric', '+237611110000', 'eric@entreprise-a.cm',
               'x', TRUE, 'actif', '2026-10-01')""")
    eric = sql("SELECT id_utilisateur FROM utilisateur WHERE prenom = 'Eric'")[0]["id_utilisateur"]
    sql("INSERT INTO appartenance (id_utilisateur, id_organisation) VALUES (%s, 1)", (eric,))
    sql("""INSERT INTO vehicule (id_proprietaire, marque_modele, immatriculation, places_passagers, conso_l_100km,
               climatise) VALUES (%s, 'Berline', 'LT-777-EE', 3, 7.0, TRUE)""", (eric,))
    sql("""INSERT INTO trajet (id_conducteur, id_vehicule, depart_libelle, depart_lat, depart_lon, arrivee_libelle,
               arrivee_lat, arrivee_lon, heure_depart, jours_semaine, places_offertes, detour_max_km)
           SELECT %s, id_vehicule, 'Logpom', 4.088, 9.765, 'Bonanjo', 4.042, 9.689, '06:52', '1111100', 3, 2.0
             FROM vehicule WHERE immatriculation = 'LT-777-EE'""", (eric,))
    sql("UPDATE demande SET mode_reservation = 'autonome' WHERE id_demande = 1")
    r = client.post("/api/trajets/1/annulations", headers=comme(ARMAND), json={"date_trajet": "2026-11-17"}).json()
    p = r["passagers"][0]
    assert p["reaffecte"] and p["nouveau_conducteur"] == "Eric"
    nouvelle = sql("SELECT r.statut, t.id_conducteur FROM reservation r JOIN trajet t USING (id_trajet) "
                   "WHERE r.id_reservation = %s", (p["id_reservation"],))[0]
    assert nouvelle["statut"] == "confirmee" and nouvelle["id_conducteur"] == eric
    assert sql("SELECT count(*) n FROM notification WHERE id_utilisateur = %s AND type = 'reaffectation'",
               (GRACE,))[0]["n"] == 1


def test_scenarios_de_demo_disponibles(client):
    codes = [s["code"] for s in client.get("/api/demo/scenarios").json()]
    assert codes == ["nominal", "annulation", "aucune_offre", "elargissement"]
    r = client.post("/api/demo/scenarios/aucune_offre").json()
    assert r["utilisateur"] == NADEGE and r["etapes"]
    r = client.post("/api/demo/scenarios/elargissement").json()
    assert r["utilisateur"] == GRACE
    diag = client.get(f"/api/moi/demandes/{r['id_demande']}/diagnostic", headers=comme(GRACE)).json()
    assert diag["suggestions"][0]["action"] == "elargir"
    assert client.post("/api/demo/scenarios/inconnu").status_code == 404
