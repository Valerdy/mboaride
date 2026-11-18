"""Console d'administration de la plateforme : rôles, utilisateurs, agréments, trajets, paiements."""

from __future__ import annotations

import pytest

from conftest import GRACE, HELENE, MIREILLE, SERGE, comme

PAUL = 7
CHEF, SUPPORT, FINANCE = HELENE, MIREILLE, 6      # 6 : Junior, nommé à la finance


@pytest.fixture()
def equipe(sql):
    sql("INSERT INTO administrateur (id_utilisateur, role) VALUES (%s, 'super_admin'), (%s, 'support'), "
        "(%s, 'finance')", (CHEF, SUPPORT, FINANCE))
    return sql


def test_acces_reserve_a_l_equipe_et_par_role(client, equipe):
    assert client.get("/api/admin/moi", headers=comme(GRACE)).status_code == 403
    moi = client.get("/api/admin/moi", headers=comme(SUPPORT)).json()
    assert moi["role"] == "support" and "paiements" not in moi["modules"]
    assert client.get("/api/admin/paiements", headers=comme(SUPPORT)).status_code == 403
    assert client.get("/api/admin/utilisateurs", headers=comme(FINANCE)).status_code == 403
    assert client.get("/api/admin/paiements", headers=comme(FINANCE)).status_code == 200
    assert client.get("/api/admin/administrateurs", headers=comme(SUPPORT)).status_code == 403
    assert len(client.get("/api/admin/administrateurs", headers=comme(CHEF)).json()) == 3
    assert {c["id_utilisateur"] for c in client.get("/api/admin/demo/comptes").json()} == {CHEF, SUPPORT, FINANCE}


def test_tableau_de_bord(client, equipe):
    r = client.get("/api/admin/tableau-de-bord?jours=7", headers=comme(FINANCE))
    assert r.status_code == 200, r.text
    tb = r.json()
    assert len(tb["serie"]) == 7
    assert tb["indicateurs"]["utilisateurs"] >= 9
    assert tb["indicateurs"]["conducteurs_agrees"] >= 3
    assert {"agrements", "signalements", "paiements_echoues"} <= tb["a_traiter"].keys()


def test_recherche_et_fiche_utilisateur(client, equipe):
    res = client.get("/api/admin/utilisateurs?q=kamga", headers=comme(SUPPORT)).json()
    assert res["total"] == 1 and res["lignes"][0]["id_utilisateur"] == SERGE
    conducteurs = client.get("/api/admin/utilisateurs?role=conducteur&taille=2", headers=comme(SUPPORT)).json()
    assert conducteurs["total"] >= 3 and len(conducteurs["lignes"]) == 2
    fiche = client.get(f"/api/admin/utilisateurs/{SERGE}", headers=comme(SUPPORT)).json()
    assert "mot_de_passe_hache" not in fiche["utilisateur"]
    assert fiche["trajets_conducteur"] and len(fiche["documents"]) == 4


def test_suspendre_puis_reactiver_un_compte(client, equipe):
    trajets = equipe("SELECT id_trajet FROM trajet WHERE id_conducteur = %s AND statut = 'actif'", (SERGE,))
    a_venir = equipe("SELECT count(*) n FROM reservation r JOIN trajet t USING (id_trajet) WHERE t.id_conducteur = %s "
                     "AND r.statut = 'confirmee' AND r.date_trajet >= CURRENT_DATE", (SERGE,))[0]["n"]
    assert client.post(f"/api/admin/utilisateurs/{SERGE}/suspension", json={"motif": "x"},
                       headers=comme(SUPPORT)).status_code == 422          # motif trop court
    r = client.post(f"/api/admin/utilisateurs/{SERGE}/suspension", json={"motif": "Comportement dangereux"},
                    headers=comme(SUPPORT))
    assert r.status_code == 200, r.text
    assert r.json()["trajets_retires"] == len(trajets) and r.json()["reservations_annulees"] == a_venir
    # Le compte suspendu n'a plus accès à l'application.
    bloque = client.get("/api/moi/notifications", headers=comme(SERGE))
    assert bloque.status_code == 403 and "suspendu" in bloque.json()["detail"]
    assert client.post(f"/api/admin/utilisateurs/{SERGE}/suspension", json={"motif": "Encore"},
                       headers=comme(SUPPORT)).status_code == 409
    # Un membre du support ne suspend pas un collègue, ni lui-même.
    assert client.post(f"/api/admin/utilisateurs/{FINANCE}/suspension", json={"motif": "Essai"},
                       headers=comme(SUPPORT)).status_code == 403
    assert client.post(f"/api/admin/utilisateurs/{SUPPORT}/suspension", json={"motif": "Essai"},
                       headers=comme(SUPPORT)).status_code == 409

    assert client.post(f"/api/admin/utilisateurs/{SERGE}/reactivation", json={"motif": "Explications reçues"},
                       headers=comme(SUPPORT)).status_code == 200
    notifs = client.get("/api/moi/notifications", headers=comme(SERGE)).json()
    assert [n["type"] for n in notifs[:2]] == ["administration", "administration"]
    actions = [e["action"] for e in client.get("/api/admin/journal", headers=comme(CHEF)).json()["lignes"]]
    assert actions[:2] == ["reactivation", "suspension"]


def test_verification_des_pieces_d_agrement(client, equipe):
    for piece in ("piece_identite", "permis", "casier_judiciaire", "assurance"):
        equipe("INSERT INTO document_agrement (id_utilisateur, type_document, chemin_fichier) VALUES (%s, %s, 'f') "
               "ON CONFLICT (id_utilisateur, type_document) DO UPDATE SET statut = 'depose', expire_le = NULL",
               (PAUL, piece))
    attente = client.get("/api/admin/agrements", headers=comme(SUPPORT)).json()
    paul = next(l for l in attente["lignes"] if l["id_utilisateur"] == PAUL)
    assert {d["statut"] for d in paul["documents"]} == {"depose"}

    url = f"/api/admin/agrements/{PAUL}/documents"
    assert client.post(f"{url}/permis", json={"decision": "refuse"}, headers=comme(SUPPORT)).status_code == 422
    r = client.post(f"{url}/permis", json={"decision": "refuse", "motif": "Photo illisible"}, headers=comme(SUPPORT))
    assert r.json()["statut_agrement"] == "en_verification"
    for piece in ("piece_identite", "casier_judiciaire", "assurance"):
        r = client.post(f"{url}/{piece}", json={"decision": "valide"}, headers=comme(SUPPORT))
        assert r.status_code == 200, r.text
    assert r.json()["statut_agrement"] == "en_verification"
    refus = equipe("SELECT message FROM notification WHERE id_utilisateur = %s AND type = 'administration'", (PAUL,))
    assert "Photo illisible" in refus[0]["message"]

    r = client.post(f"{url}/permis", json={"decision": "valide", "expire_le": "2030-01-31"}, headers=comme(SUPPORT))
    assert r.json()["statut_agrement"] == "actif"
    permis = next(d for d in r.json()["documents"] if d["type"] == "permis")
    assert permis["verifie_par"] == "Mireille Fotso" and permis["motif_refus"] is None
    assert equipe("SELECT date_agrement FROM utilisateur WHERE id_utilisateur = %s", (PAUL,))[0]["date_agrement"]

    # Suspendre l'agrément, puis le rétablir (les quatre pièces sont valides).
    r = client.post(f"/api/admin/agrements/{PAUL}/statut", json={"statut": "suspendu", "motif": "Signalement"},
                    headers=comme(SUPPORT))
    assert r.json()["statut_agrement"] == "suspendu"
    r = client.post(f"/api/admin/agrements/{PAUL}/statut", json={"statut": "actif", "motif": "Levée"},
                    headers=comme(SUPPORT))
    assert r.status_code == 200 and r.json()["statut_agrement"] == "actif"


def test_retablir_un_agrement_exige_quatre_pieces(client, equipe):
    equipe("UPDATE utilisateur SET statut_agrement = 'suspendu' WHERE id_utilisateur = %s", (PAUL,))
    r = client.post(f"/api/admin/agrements/{PAUL}/statut", json={"statut": "actif", "motif": "Levée"},
                    headers=comme(SUPPORT))
    assert r.status_code == 409
    assert equipe("SELECT statut_agrement FROM utilisateur WHERE id_utilisateur = %s", (PAUL,))[0][
        "statut_agrement"] == "suspendu"


def test_retirer_un_trajet(client, equipe):
    liste = client.get("/api/admin/trajets?etat=actif&q=Logpom", headers=comme(SUPPORT)).json()
    assert [t["id_trajet"] for t in liste["lignes"]] == [1]
    fiche = client.get("/api/admin/trajets/1", headers=comme(SUPPORT)).json()
    assert fiche["trajet"]["conducteur"] == "Armand Essomba" and fiche["reservations"]

    r = client.post("/api/admin/trajets/1/retrait", json={"motif": "Véhicule non conforme"}, headers=comme(SUPPORT))
    assert r.status_code == 200, r.text
    assert client.post("/api/admin/trajets/1/retrait", json={"motif": "Encore"},
                       headers=comme(SUPPORT)).status_code == 409
    assert equipe("SELECT statut FROM trajet WHERE id_trajet = 1")[0]["statut"] == "annule"
    message = equipe("SELECT message FROM notification WHERE id_utilisateur = 1 AND type = 'administration'")
    assert "Véhicule non conforme" in message[0]["message"]


def test_rembourser_un_paiement_par_le_portefeuille(client, equipe):
    equipe("INSERT INTO paiement (id_reservation, montant_fcfa, commission_fcfa, moyen, reference_transaction, "
           "statut, paye_le) VALUES (2, 175, 17, 'portefeuille', 'PF-TEST', 'reussi', now())")
    liste = client.get("/api/admin/paiements?statut=sequestre", headers=comme(FINANCE)).json()
    ligne = next(p for p in liste["lignes"] if p["reference_transaction"] == "PF-TEST")
    assert ligne["passager"] == "Grâce Mbarga" and ligne["conducteur"] == "Armand Essomba"

    url = f"/api/admin/paiements/{ligne['id_paiement']}/remboursement"
    r = client.post(url, json={"motif": "Conducteur absent"}, headers=comme(FINANCE))
    assert r.status_code == 200, r.text
    assert client.post(url, json={"motif": "Encore"}, headers=comme(FINANCE)).status_code == 409
    assert equipe("SELECT solde_fcfa FROM portefeuille WHERE id_utilisateur = %s", (GRACE,))[0]["solde_fcfa"] == 175
    assert equipe("SELECT statut FROM reservation WHERE id_reservation = 2")[0]["statut"] == "annulee"


def test_un_paiement_deja_verse_ne_se_rembourse_pas(client, equipe):
    equipe("UPDATE paiement SET verse_le = now(), montant_verse_fcfa = 158 WHERE reference_transaction = 'MM-0001'")
    pid = equipe("SELECT id_paiement FROM paiement WHERE reference_transaction = 'MM-0001'")[0]["id_paiement"]
    r = client.post(f"/api/admin/paiements/{pid}/remboursement", json={"motif": "Litige"}, headers=comme(FINANCE))
    assert r.status_code == 409 and "versé" in r.json()["detail"]


def test_export_csv_et_finances(client, equipe):
    r = client.get("/api/admin/export/paiements.csv", headers=comme(FINANCE))
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    lignes = r.content.decode("utf-8-sig").splitlines()
    assert lignes[0].startswith("id_paiement;reference_transaction;passager")
    assert len(lignes) == 3                                   # en-tête et les deux paiements d'exemple
    f = client.get("/api/admin/finances?du=2026-11-01&au=2026-11-30", headers=comme(FINANCE)).json()
    assert len(f["serie"]) == 30
    assert f["totaux"]["encaisse_fcfa"] >= 175
    assert client.get("/api/admin/finances?du=2026-11-30&au=2026-11-01", headers=comme(FINANCE)).status_code == 422


def test_nommer_et_retirer_un_administrateur(client, equipe):
    r = client.post("/api/admin/administrateurs", json={"identifiant": "GRACE@entreprise-a.cm", "role": "support"},
                    headers=comme(CHEF))
    assert r.status_code == 201 and r.json()["id_utilisateur"] == GRACE
    assert client.get("/api/admin/moi", headers=comme(GRACE)).json()["role"] == "support"
    assert client.post("/api/admin/administrateurs", json={"identifiant": "inconnu@x.cm", "role": "support"},
                       headers=comme(CHEF)).status_code == 404
    assert client.delete(f"/api/admin/administrateurs/{CHEF}", headers=comme(CHEF)).status_code == 409
    assert client.delete(f"/api/admin/administrateurs/{GRACE}", headers=comme(CHEF)).status_code == 200
    assert client.get("/api/admin/moi", headers=comme(GRACE)).status_code == 403
