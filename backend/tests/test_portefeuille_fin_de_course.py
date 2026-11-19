"""Portefeuille, point de ramassage, course et versement au conducteur à la fin de la course.

Kevin conduit Logpom → Bonanjo ; Lina et Paul réservent. Lina paie avec son portefeuille
rechargé depuis Mobile Money, Paul par Mobile Money. Le conducteur ne reçoit rien tant que
les deux n'ont pas validé la fin de la course ; ensuite il reçoit le prix moins 10 %.
"""

from __future__ import annotations

import pytest
from conftest import PIECE, PNG

from app import config
from test_parcours_complet import prochain_jour_ouvre
from test_pont_node import jeton, porteur, secret_partage, table_users  # noqa: F401  (fixture)

KEVIN, LINA, PAUL = 601, 602, 603
RAMASSAGE = "Station Total de Logpom, côté boulangerie"


@pytest.fixture()
def equipage(client, sql, secret_partage, monkeypatch):  # noqa: F811
    monkeypatch.setattr(config, "AGREMENT_AUTO", True)
    monkeypatch.setattr(config, "SIMULATION", True)
    table_users(sql, [(KEVIN, "kevin@exemple.cm", "+237690000601", "Kevin Ngando"),
                      (LINA, "lina@exemple.cm", "+237690000602", "Lina Ebolo"),
                      (PAUL, "paul@exemple.cm", "+237690000603", "Paul Mbarga")])
    sql("UPDATE public.users SET is_verified = TRUE")
    h = {n: porteur(jeton(i)) for n, i in (("kevin", KEVIN), ("lina", LINA), ("paul", PAUL))}
    for n in h.values():
        client.post("/api/moi/profil", headers=n)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers={**h["kevin"], **PIECE}, content=PNG)
    client.put("/api/moi/conducteur/vehicule", headers=h["kevin"], json={
        "marque_modele": "Toyota Corolla grise", "immatriculation": "LT 601 AA", "places_passagers": 3,
        "conso_l_100km": 8})
    trajet = {"depart": "Logpom", "arrivee": "Bonanjo", "heure_depart": "06:50", "jours_semaine": [1, 2, 3, 4, 5],
              "places": 3, "detour_max_km": 3}
    sans = client.post("/api/moi/conducteur/trajets", headers=h["kevin"], json=trajet)
    assert sans.status_code == 422                       # le point de ramassage est obligatoire
    pub = client.post("/api/moi/conducteur/trajets", headers=h["kevin"], json={
        **trajet, "point_ramassage": RAMASSAGE, "consignes_ramassage": "Je klaxonne deux fois", "attente_max_min": 5})
    assert pub.status_code == 201, pub.text
    assert pub.json()["point_ramassage"] == RAMASSAGE
    h["id_trajet"] = pub.json()["id_trajet"]
    h["jour"] = prochain_jour_ouvre().isoformat()
    return h


def _reserver(client, h, qui, depart):
    id_demande = client.post("/api/demandes", headers=h[qui], json={
        "depart": depart, "arrivee": {"libelle": "Bonanjo", "lat": 4.042, "lon": 9.689},
        "arrivee_au_plus_tot": "07:15", "arrivee_au_plus_tard": "08:00",
        "date_trajet": h["jour"], "prix_max_fcfa": 2000, "cercle_max": "public"}).json()["id"]
    offre = next(o for o in client.get(f"/api/moi/demandes/{id_demande}/offres", headers=h[qui]).json()
                 if o["id_trajet"] == h["id_trajet"])
    r = client.post("/api/reservations", headers=h[qui], json={
        "id_demande": id_demande, "id_trajet": h["id_trajet"], "date_trajet": h["jour"],
        "prix_annonce_fcfa": offre["prix_fcfa"]})
    assert r.status_code == 201, r.text
    return offre, r.json()


def test_portefeuille_course_et_versement(client, sql, equipage):
    h = equipage
    logpom = {"libelle": "Logpom", "lat": 4.0846, "lon": 9.7562}
    offre_lina, resa_lina = _reserver(client, h, "lina", logpom)
    # Le passager lit le point de ramassage et le véhicule avant de confirmer.
    assert offre_lina["point_ramassage"] == RAMASSAGE and "LT 601 AA" in offre_lina["vehicule"]
    assert offre_lina["commission_fcfa"] == offre_lina["prix_fcfa"] // 10

    # --- Portefeuille de Lina : vide, rechargé depuis MTN, puis paiement du trajet.
    vide = client.post(f"/api/paiements/{resa_lina['id_paiement']}/portefeuille", headers=h["lina"])
    assert vide.status_code == 409 and vide.json()["detail"]["manque_fcfa"] == offre_lina["prix_fcfa"]
    compte = client.post("/api/moi/comptes-mobile-money", headers=h["lina"], json={
        "operateur": "mtn", "telephone": "677000602", "titulaire": "Lina Ebolo"}).json()
    assert client.post("/api/moi/portefeuille/recharge", headers=h["lina"], json={
        "id_compte": compte["id_compte"], "montant_fcfa": 2000, "code_secret": "12"}).status_code == 422
    pf = client.post("/api/moi/portefeuille/recharge", headers=h["lina"], json={
        "id_compte": compte["id_compte"], "montant_fcfa": 2000, "code_secret": "1234"}).json()
    assert pf["solde_fcfa"] == 2000 and pf["mouvements"][0]["type"] == "recharge"
    recu = client.post(f"/api/paiements/{resa_lina['id_paiement']}/portefeuille", headers=h["lina"]).json()
    assert recu["statut"] == "reussi" and recu["moyen"] == "portefeuille" and not recu["verse_au_conducteur"]
    pf = client.get("/api/moi/portefeuille", headers=h["lina"]).json()
    assert pf["solde_fcfa"] == 2000 - offre_lina["prix_fcfa"]
    assert pf["paiements_en_sequestre_fcfa"] == offre_lina["prix_fcfa"]

    # --- Paul part de Logpom aussi : la voiture se remplit, il paie moins que s'il était seul.
    offre_paul, resa_paul = _reserver(client, h, "paul", logpom)
    assert offre_paul["passagers_deja_a_bord"] == 1 and offre_paul["prix_fcfa"] < offre_lina["prix_fcfa"]
    compte_paul = client.post("/api/moi/comptes-mobile-money", headers=h["paul"], json={
        "operateur": "orange", "telephone": "699000603", "titulaire": "Paul Mbarga"}).json()
    client.post(f"/api/paiements/{resa_paul['id_paiement']}/mobile-money", headers=h["paul"],
                json={"id_compte": compte_paul["id_compte"]})
    client.post(f"/api/paiements/{resa_paul['id_paiement']}/simulation-operateur", headers=h["paul"],
                json={"resultat": "valide"})

    # --- L'équipage du conducteur : nom complet, téléphone, point de ramassage.
    eq = client.get("/api/moi/conducteur/equipage", headers=h["kevin"]).json()
    assert eq["point_ramassage"] == RAMASSAGE and eq["statut_course"] == "a_demarrer"
    lina = next(a for a in eq["arrets"] if a["passager"] == "Lina")
    assert lina["nom"] == "Ebolo" and lina["telephone"] == "+237690000602" and not lina["fin_validee"]
    part = (offre_lina["prix_fcfa"] - offre_lina["commission_fcfa"]
            + offre_paul["prix_fcfa"] - offre_paul["commission_fcfa"])
    assert client.get("/api/moi/portefeuille", headers=h["kevin"]).json()["gains_en_attente_fcfa"] == part

    # Côté passager : suivi de la course, numéro du conducteur une fois payé.
    suivi = client.get(f"/api/moi/reservations/{resa_lina['id_reservation']}/suivi", headers=h["lina"]).json()
    assert suivi["conducteur_telephone"] == "+237690000601" and suivi["point_ramassage"] == RAMASSAGE
    assert suivi["consignes_ramassage"] == "Je klaxonne deux fois" and suivi["statut_course"] == "a_demarrer"

    # --- La course démarre puis arrive ; les passagers sont prévenus.
    jour = {"id_trajet": h["id_trajet"], "date_trajet": h["jour"]}
    assert client.post("/api/moi/conducteur/course/demarrer", headers=h["kevin"], json=jour).json()["statut"] == "en_cours"
    assert "démarré" in client.get("/api/moi/notifications/resume", headers=h["lina"]).json()["derniere"]["message"]
    assert client.post("/api/moi/conducteur/course/arrivee", headers=h["kevin"], json=jour).json()["statut"] == "arrivee"

    # --- Lina valide et note : le conducteur n'est pas encore payé, Paul n'a pas validé.
    fin = client.post(f"/api/moi/reservations/{resa_lina['id_reservation']}/fin-de-course", headers=h["lina"],
                      json={"note": 5, "commentaire": "Ponctuel et prudent"}).json()
    assert fin["message"].startswith("Merci") and fin["en_attente_de"] == ["Paul"] and not fin["conducteur_paye"]
    assert client.get("/api/moi/portefeuille", headers=h["kevin"]).json()["solde_fcfa"] == 0
    deux = client.post(f"/api/moi/reservations/{resa_lina['id_reservation']}/fin-de-course", headers=h["lina"],
                       json={"note": 4})
    assert deux.status_code == 409
    mes = client.get("/api/moi/reservations", headers=h["lina"]).json()[0]
    assert mes["etat"] == "termine" and mes["ma_note"] == 5 and mes["fin_validee"]

    # --- Paul valide : versement au conducteur, commission de 10 % gardée par MboaRide.
    fin = client.post(f"/api/moi/reservations/{resa_paul['id_reservation']}/fin-de-course", headers=h["paul"],
                      json={"note": 4}).json()
    assert fin["conducteur_paye"] and fin["en_attente_de"] == []
    pf_kevin = client.get("/api/moi/portefeuille", headers=h["kevin"]).json()
    assert pf_kevin["solde_fcfa"] == part and pf_kevin["gains_en_attente_fcfa"] == 0
    assert pf_kevin["mouvements"][0]["type"] == "gain"
    assert pf_kevin["commission_mboaride_fcfa"] == offre_lina["commission_fcfa"] + offre_paul["commission_fcfa"]
    assert sql("SELECT sum(montant_fcfa) s FROM commission_mboaride")[0]["s"] == pf_kevin["commission_mboaride_fcfa"]
    assert "versés dans votre portefeuille" in client.get(
        "/api/moi/notifications/resume", headers=h["kevin"]).json()["derniere"]["message"]
    gains = client.get("/api/moi/conducteur/gains", headers=h["kevin"]).json()
    assert gains["paiements"][0]["recu"] and gains["paiements"][0]["montant_fcfa"] == part
    assert sql("SELECT avg(note) n FROM evaluation WHERE id_evalue = (SELECT id_utilisateur FROM utilisateur "
               "WHERE prenom = 'Kevin' AND nom = 'Ngando')")[0]["n"] == 4.5

    # Retrait vers Mobile Money : le portefeuille se vide, jamais en dessous de zéro.
    client.post("/api/moi/comptes-mobile-money", headers=h["kevin"], json={
        "operateur": "orange", "telephone": "699000601", "titulaire": "Kevin Ngando"})
    trop = client.post("/api/moi/portefeuille/retrait", headers=h["kevin"], json={"montant_fcfa": part + 100})
    assert trop.status_code == 409
    assert client.post("/api/moi/portefeuille/retrait", headers=h["kevin"],
                       json={"montant_fcfa": part}).json()["solde_fcfa"] == 0


def test_virement_automatique_et_remboursement_dans_le_portefeuille(client, sql, equipage):
    h = equipage
    kotto = {"libelle": "Kotto", "lat": 4.072, "lon": 9.766}
    offre, resa = _reserver(client, h, "lina", kotto)
    compte = client.post("/api/moi/comptes-mobile-money", headers=h["lina"], json={
        "operateur": "orange", "telephone": "699000602", "titulaire": "Lina Ebolo"}).json()
    client.post("/api/moi/portefeuille/recharge", headers=h["lina"], json={
        "id_compte": compte["id_compte"], "montant_fcfa": 1000, "code_secret": "0000"})
    client.post(f"/api/paiements/{resa['id_paiement']}/portefeuille", headers=h["lina"])

    # Lina renonce : son paiement revient dans son portefeuille.
    r = client.post(f"/api/moi/reservations/{resa['id_reservation']}/annulation", headers=h["lina"]).json()
    assert r["paiement"] == "rembourse"
    pf = client.get("/api/moi/portefeuille", headers=h["lina"]).json()
    assert pf["solde_fcfa"] == 1000 and pf["mouvements"][0]["type"] == "remboursement"

    # Elle réserve de nouveau ; le conducteur a activé le virement automatique.
    assert client.put("/api/moi/portefeuille/virement-auto", headers=h["kevin"],
                      json={"actif": True}).status_code == 404          # aucun compte Mobile Money
    client.post("/api/moi/comptes-mobile-money", headers=h["kevin"], json={
        "operateur": "mtn", "telephone": "677000601", "titulaire": "Kevin Ngando"})
    assert client.put("/api/moi/portefeuille/virement-auto", headers=h["kevin"],
                      json={"actif": True}).json()["virement_auto"]
    sql("UPDATE demande SET statut = 'ouverte'")
    id_demande = sql("SELECT id_demande FROM demande d JOIN utilisateur u ON u.id_utilisateur = d.id_demandeur "
                     "WHERE u.prenom = 'Lina'")[0]["id_demande"]
    resa = client.post("/api/reservations", headers=h["lina"], json={
        "id_demande": id_demande, "id_trajet": h["id_trajet"], "date_trajet": h["jour"],
        "prix_annonce_fcfa": offre["prix_fcfa"]}).json()
    client.post(f"/api/paiements/{resa['id_paiement']}/portefeuille", headers=h["lina"])

    # Validation sans démarrage par le conducteur (mode simulation) : versement puis virement.
    fin = client.post(f"/api/moi/reservations/{resa['id_reservation']}/fin-de-course", headers=h["lina"],
                      json={"note": 3, "commentaire": "Un peu en retard"}).json()
    assert fin["conducteur_paye"]
    pf = client.get("/api/moi/portefeuille", headers=h["kevin"]).json()
    assert pf["solde_fcfa"] == 0 and [m["type"] for m in pf["mouvements"][:2]] == ["retrait", "gain"]
    assert "virés automatiquement" in client.get("/api/moi/notifications", headers=h["kevin"]).json()[0]["message"]


def test_sans_simulation_la_fin_de_course_attend_le_jour_du_trajet(client, sql, equipage, monkeypatch):
    h = equipage
    monkeypatch.setattr(config, "SIMULATION", False)
    _, resa = _reserver(client, h, "lina", {"libelle": "Logpom", "lat": 4.0846, "lon": 9.7562})
    compte = client.post("/api/moi/comptes-mobile-money", headers=h["lina"], json={
        "operateur": "mtn", "telephone": "677000602", "titulaire": "Lina Ebolo"}).json()
    # Pas encore payé : rien à valider.
    r = client.post(f"/api/moi/reservations/{resa['id_reservation']}/fin-de-course", headers=h["lina"], json={"note": 5})
    assert r.status_code == 409 and "Payez" in r.json()["detail"]
    client.post(f"/api/paiements/{resa['id_paiement']}/mobile-money", headers=h["lina"], json={"id_compte": compte["id_compte"]})
    client.post(f"/api/paiements/{resa['id_paiement']}/simulation-operateur", headers=h["lina"], json={"resultat": "valide"})
    r = client.post(f"/api/moi/reservations/{resa['id_reservation']}/fin-de-course", headers=h["lina"], json={"note": 5})
    assert r.status_code == 409 and "pas encore commencé" in r.json()["detail"]
    jour = {"id_trajet": h["id_trajet"], "date_trajet": h["jour"]}
    assert client.post("/api/moi/conducteur/course/demarrer", headers=h["kevin"], json=jour).status_code == 409

    # Le conducteur précise ensuite son point de ramassage : les passagers sont prévenus.
    r = client.put(f"/api/moi/conducteur/trajets/{h['id_trajet']}/ramassage", headers=h["kevin"],
                   json={"point_ramassage": "Pharmacie du Carrefour Logpom", "attente_max_min": 3})
    assert r.status_code == 200
    assert "Pharmacie" in client.get("/api/moi/notifications/resume", headers=h["lina"]).json()["derniere"]["message"]
