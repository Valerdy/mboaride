"""Parcours complet de l'application mobile, sur la base partagée avec l'API Node.

Un conducteur et une passagère s'inscrivent sur l'API Node (simulée ici par sa table
`users`), créent leur profil métier, puis : agrément, véhicule, règles et publication côté
conducteur ; demande, offre calculée par le moteur et réservation côté passagère ; enfin
l'équipage, l'activité de l'agent, le retard, les gains et l'évaluation côté conducteur.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from conftest import PIECE, PNG

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
              "jours_semaine": [1, 2, 3, 4, 5], "places": 3, "point_ramassage": "Carrefour du quartier, devant la pharmacie", "detour_max_km": 3}
    assert client.post("/api/moi/conducteur/trajets", json=trajet, headers=kevin).status_code == 403

    for piece in ("piece_identite", "permis", "casier_judiciaire"):
        a = client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers={**kevin, **PIECE}, content=PNG).json()
    assert a["statut_agrement"] == "en_verification"
    a = client.post("/api/moi/conducteur/agrement/documents/assurance", headers={**kevin, **PIECE}, content=PNG).json()
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

    # Place retenue, mais trajet à confirmer : le conducteur ne voit pas encore Lina.
    assert client.get("/api/moi/conducteur/equipage", headers=kevin).json()["arrets"] == []
    compte = client.post("/api/moi/comptes-mobile-money", headers=lina, json={
        "operateur": "orange", "telephone": "690 00 05 02", "titulaire": "Lina Ebolo"}).json()
    client.post(f"/api/paiements/{r.json()['id_paiement']}/mobile-money", headers=lina,
                json={"id_compte": compte["id_compte"]})
    paye = client.post(f"/api/paiements/{r.json()['id_paiement']}/simulation-operateur", headers=lina,
                       json={"resultat": "valide"}).json()
    assert paye["statut"] == "reussi"

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
    # Payé par Lina mais gardé par MboaRide : versé au conducteur à la fin de la course.
    assert g["paiements"][0]["recu"] is False and g["dernier_trajet_carburant_fcfa"] > 0
    assert g["paiements"][0]["commission_fcfa"] == offre["commission_fcfa"]

    ev = client.post("/api/moi/conducteur/evaluations", headers=kevin, json={
        "id_trajet": id_trajet, "date_trajet": jour.isoformat(), "notes": [{"passager": "Lina", "note": 5}]})
    assert ev.status_code == 201 and ev.json()["evaluations"] == 1


def test_les_regles_du_conducteur_filtrent_les_offres(client, sql, comptes):
    """Prix minimal appliqué par le moteur, et refus des collègues quand il les exclut."""
    kevin, lina = comptes["kevin"], comptes["lina"]
    client.post("/api/moi/profil", headers=kevin)
    client.post("/api/moi/profil", headers=lina)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers={**kevin, **PIECE}, content=PNG)
    client.put("/api/moi/conducteur/vehicule", headers=kevin, json={
        "marque_modele": "Berline", "immatriculation": "LT 1", "places_passagers": 3, "conso_l_100km": 8})
    id_trajet = client.post("/api/moi/conducteur/trajets", headers=kevin, json={
        "depart": "Logpom", "arrivee": "Bonanjo", "heure_depart": "06:50", "jours_semaine": [1, 2, 3, 4, 5],
        "places": 3, "point_ramassage": "Carrefour du quartier, devant la pharmacie", "detour_max_km": 3}).json()["id_trajet"]
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
    assert offre()["prix_fcfa"] == 1675 and offre()["part_conducteur_fcfa"] >= 1500  # plancher + 10 %
    client.put("/api/moi/conducteur/regles", headers=kevin, json={**regles, "collegues": False, "prix_min_fcfa": 0})
    assert offre() is None


def test_un_trajet_regulier_n_est_pas_propose_un_jour_ou_il_ne_roule_pas(client, comptes):
    kevin, lina = comptes["kevin"], comptes["lina"]
    client.post("/api/moi/profil", headers=kevin)
    client.post("/api/moi/profil", headers=lina)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers={**kevin, **PIECE}, content=PNG)
    client.put("/api/moi/conducteur/vehicule", headers=kevin, json={
        "marque_modele": "Berline", "immatriculation": "LT 2", "places_passagers": 3, "conso_l_100km": 8})
    id_trajet = client.post("/api/moi/conducteur/trajets", headers=kevin, json={
        "depart": "Logpom", "arrivee": "Bonanjo", "heure_depart": "06:50", "jours_semaine": [1, 2, 3, 4, 5],
        "places": 3, "point_ramassage": "Carrefour du quartier, devant la pharmacie"}).json()["id_trajet"]
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


def test_passager_d_entreprise_et_chauffeur_sans_organisation(client, sql, secret_partage, monkeypatch):  # noqa: F811
    """Cas de l'essai sur PC : chauffeuse en gmail (aucune organisation), passager d'Entreprise A.

    Le trajet n'est visible que si le passager accepte tout MboaRide (cercle public) ; le
    diagnostic propose d'élargir, et de la bonne fenêtre quand l'horaire ne colle pas.
    Toucher deux fois les boutons ne crée ni deux trajets ni deux demandes.
    """
    monkeypatch.setattr(config, "AGREMENT_AUTO", True)
    table_users(sql, [(701, "cindy.test@gmail.com", "+237677000701", "Cindy Test"),
                      (702, "kevin.test@entreprise-a.cm", "+237699000702", "Kevin Test")])
    sql("UPDATE public.users SET is_verified = TRUE")
    cindy, kevin = porteur(jeton(701)), porteur(jeton(702))
    client.post("/api/moi/profil", headers=cindy)
    client.post("/api/moi/profil", headers=kevin)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers={**cindy, **PIECE}, content=PNG)
    client.put("/api/moi/conducteur/vehicule", headers=cindy, json={
        "marque_modele": "Mercedes", "immatriculation": "LT 701", "places_passagers": 3, "conso_l_100km": 8})
    trajet = {"depart": "Logpom", "arrivee": "Bonabéri", "heure_depart": "06:45",
              "jours_semaine": [1, 2, 3, 4, 5], "places": 3, "point_ramassage": "Carrefour du quartier, devant la pharmacie", "detour_max_km": 2}
    pub = client.post("/api/moi/conducteur/trajets", json=trajet, headers=cindy)
    assert pub.status_code == 201 and pub.json()["ouvert_public"] is True
    id_trajet = pub.json()["id_trajet"]
    deux = client.post("/api/moi/conducteur/trajets", json=trajet, headers=cindy)
    assert deux.status_code == 409 and "déjà publié" in deux.json()["detail"]

    jour = prochain_jour_ouvre().isoformat()
    demande = {"depart": {"libelle": "Logpom", "lat": 4.0846, "lon": 9.7562},
               "arrivee": {"libelle": "Bonabéri", "lat": 4.0764, "lon": 9.6644},
               "arrivee_au_plus_tot": "07:30", "arrivee_au_plus_tard": "08:00",
               "date_trajet": jour, "prix_max_fcfa": 1000}

    # Cercle « partenaires » : la chauffeuse est hors du cercle, le diagnostic le dit.
    d = client.post("/api/demandes", headers=kevin, json={**demande, "cercle_max": "partenaires"}).json()
    ids = [o["id_trajet"] for o in client.get(f"/api/moi/demandes/{d['id']}/offres", headers=kevin).json()]
    assert id_trajet not in ids

    # Même demande, cercle « tout MboaRide » : même demande mise à jour, pas de doublon.
    d2 = client.post("/api/demandes", headers=kevin, json={**demande, "cercle_max": "public"}).json()
    assert d2["id"] == d["id"] and d2["deja_demandee"] is True and d2["cercle_max"] == "public"
    offre = next(o for o in client.get(f"/api/moi/demandes/{d['id']}/offres", headers=kevin).json()
                 if o["id_trajet"] == id_trajet)
    assert offre["conducteur"] == "Cindy" and offre["cercle"] == "public"
    # Départ 06:45 : arrivée avant 07:30, l'offre est visible mais pas confirmable...
    assert offre["confirmable"] is False
    # ... et le diagnostic donne la bonne fenêtre, au nom de la conductrice.
    diag = client.get(f"/api/moi/demandes/{d['id']}/diagnostic", headers=kevin).json()
    fenetre = next(s for s in diag["suggestions"] if s["action"] == "fenetre")
    assert "Cindy" in fenetre["message"]

    d3 = client.post("/api/demandes", headers=kevin, json={
        **demande, "cercle_max": "public", "arrivee_au_plus_tot": fenetre["arrivee_au_plus_tot"],
        "arrivee_au_plus_tard": fenetre["arrivee_au_plus_tard"]}).json()
    offre = next(o for o in client.get(f"/api/moi/demandes/{d3['id']}/offres", headers=kevin).json()
                 if o["id_trajet"] == id_trajet)
    assert offre["confirmable"] is True



def test_paiement_mobile_money_et_mes_trajets(client, sql, comptes):
    """Choisir une offre retient la place ; le trajet n'est confirmé qu'une fois payé avec un
    compte Mobile Money enregistré (opérateur, numéro, titulaire, jamais de code secret)."""
    kevin, lina = comptes["kevin"], comptes["lina"]
    client.post("/api/moi/profil", headers=kevin)
    client.post("/api/moi/profil", headers=lina)
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        client.post(f"/api/moi/conducteur/agrement/documents/{piece}", headers={**kevin, **PIECE}, content=PNG)
    client.put("/api/moi/conducteur/vehicule", headers=kevin, json={
        "marque_modele": "Berline", "immatriculation": "LT 9", "places_passagers": 3, "conso_l_100km": 8})
    id_trajet = client.post("/api/moi/conducteur/trajets", headers=kevin, json={
        "depart": "Logpom", "arrivee": "Bonanjo", "heure_depart": "06:50", "jours_semaine": [1, 2, 3, 4, 5],
        "places": 3, "point_ramassage": "Carrefour du quartier, devant la pharmacie", "detour_max_km": 3}).json()["id_trajet"]
    jour = prochain_jour_ouvre().isoformat()
    id_demande = client.post("/api/demandes", headers=lina, json={
        "depart": {"libelle": "Kotto", "lat": 4.072, "lon": 9.766},
        "arrivee": {"libelle": "Bonanjo", "lat": 4.042, "lon": 9.689},
        "arrivee_au_plus_tot": "07:20", "arrivee_au_plus_tard": "07:55",
        "date_trajet": jour, "prix_max_fcfa": 800}).json()["id"]
    offre = next(o for o in client.get(f"/api/moi/demandes/{id_demande}/offres", headers=lina).json()
                 if o["id_trajet"] == id_trajet)
    resa = client.post("/api/reservations", headers=lina, json={
        "id_demande": id_demande, "id_trajet": id_trajet, "date_trajet": jour,
        "prix_annonce_fcfa": offre["prix_fcfa"]}).json()

    trajets = client.get("/api/moi/reservations", headers=lina).json()
    assert trajets[0]["etat"] == "a_confirmer" and trajets[0]["conducteur"] == "Kevin"

    # Comptes : le numéro doit appartenir à l'opérateur ; le premier compte est celui par défaut.
    faux = client.post("/api/moi/comptes-mobile-money", headers=lina, json={
        "operateur": "mtn", "telephone": "690000502", "titulaire": "Lina Ebolo"})
    assert faux.status_code == 422 and "Orange" in faux.json()["detail"]
    compte = client.post("/api/moi/comptes-mobile-money", headers=lina, json={
        "operateur": "mtn", "telephone": "677 00 05 02", "titulaire": "Lina Ebolo", "par_defaut": False}).json()
    assert compte["par_defaut"] is True and compte["telephone"] == "+237677000502"
    assert [c["operateur"] for c in client.get("/api/moi/comptes-mobile-money", headers=lina).json()] == ["mtn"]
    assert "code" not in str(sql("SELECT * FROM compte_mobile_money")).lower()

    # Paiement refusé sur le téléphone : toujours à confirmer, on peut réessayer.
    client.post(f"/api/paiements/{resa['id_paiement']}/mobile-money", headers=lina, json={"id_compte": compte["id_compte"]})
    client.post(f"/api/paiements/{resa['id_paiement']}/simulation-operateur", headers=lina, json={"resultat": "refuse"})
    assert client.get("/api/moi/reservations", headers=lina).json()[0]["etat"] == "a_confirmer"
    init = client.post(f"/api/paiements/{resa['id_paiement']}/mobile-money", headers=lina,
                       json={"id_compte": compte["id_compte"]}).json()
    assert "MTN Mobile Money" in init["message"]
    client.post(f"/api/paiements/{resa['id_paiement']}/simulation-operateur", headers=lina, json={"resultat": "valide"})
    trajet = client.get("/api/moi/reservations", headers=lina).json()[0]
    assert trajet["etat"] == "confirme" and trajet["reference"].startswith("MBR-")
    assert "payé" in client.get("/api/moi/notifications", headers=kevin).json()[0]["message"]

    # Renoncer : place libérée, paiement remboursé, demande rouverte.
    r = client.post(f"/api/moi/reservations/{resa['id_reservation']}/annulation", headers=lina).json()
    assert r["paiement"] == "rembourse"
    assert client.get("/api/moi/reservations", headers=lina).json()[0]["etat"] == "annule"
    assert client.get("/api/moi/conducteur/equipage", headers=kevin).json()["arrets"] == []
    assert sql("SELECT statut FROM demande WHERE id_demande = %s", (id_demande,))[0]["statut"] == "ouverte"
