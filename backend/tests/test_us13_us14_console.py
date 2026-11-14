"""US13 · Inviter les employés et suivre l'adoption · US14 · Économies et CO2 évité."""

import pytest

from app import config, moteur
from conftest import ARMAND, GRACE, HELENE, NADEGE, comme

ORG = 1   # Entreprise A, domaine entreprise-a.cm, effectif 250, administratrice Hélène


# --------------------------------------------------------------------------- US13
def test_console_reservee_aux_administrateurs(client):
    for chemin in ("adoption", "invitations", "impact"):
        assert client.get(f"/api/organisations/{ORG}/{chemin}", headers=comme(GRACE)).status_code == 403
    assert client.get("/api/organisations/99/adoption", headers=comme(HELENE)).status_code == 404


def test_invitations_triees_avec_motifs(client, sql):
    emails = ["Paul.Nkoa@entreprise-a.cm", "paul.nkoa@entreprise-a.cm", "pas-une-adresse",
              "x@autre.cm", "grace@entreprise-a.cm", " rita@entreprise-a.cm "]
    r = client.post(f"/api/organisations/{ORG}/invitations", json={"emails": emails}, headers=comme(HELENE))
    assert r.status_code == 201
    out = r.json()
    assert [e["email"] for e in out["envoyees"]] == ["paul.nkoa@entreprise-a.cm", "rita@entreprise-a.cm"]
    assert all(e["lien"].startswith("/rejoindre/") for e in out["envoyees"])
    motifs = {e["email"]: e["motif"] for e in out["ecartees"]}
    assert motifs == {"paul.nkoa@entreprise-a.cm": "doublon dans la liste",
                      "pas-une-adresse": "adresse invalide",
                      "x@autre.cm": "hors du domaine entreprise-a.cm",
                      "grace@entreprise-a.cm": "déjà membre"}
    # deuxième envoi : la personne déjà invitée est écartée, pas réinvitée en double
    r2 = client.post(f"/api/organisations/{ORG}/invitations", json={"emails": ["rita@entreprise-a.cm"]},
                     headers=comme(HELENE)).json()
    assert r2["envoyees"] == [] and "relance" in r2["ecartees"][0]["motif"]
    assert sql("SELECT count(*) n FROM invitation")[0]["n"] == 2


def test_relances_limitees(client):
    client.post(f"/api/organisations/{ORG}/invitations", json={"emails": ["rita@entreprise-a.cm"]},
                headers=comme(HELENE))
    inv = client.get(f"/api/organisations/{ORG}/invitations", headers=comme(HELENE)).json()[0]
    url = f"/api/organisations/{ORG}/invitations/{inv['id_invitation']}/relance"
    for n in (1, 2, 3):
        assert client.post(url, headers=comme(HELENE)).json()["relances"] == n
    assert client.post(url, headers=comme(HELENE)).status_code == 409


def _inviter_et_creer(client, sql, email):
    lien = client.post(f"/api/organisations/{ORG}/invitations", json={"emails": [email]},
                       headers=comme(HELENE)).json()["envoyees"][0]["lien"]
    uid = sql("""INSERT INTO utilisateur (nom, prenom, telephone, email, mot_de_passe_hache)
                 VALUES ('Nkoa', 'Paul', '+237611111111', %s, 'x') RETURNING id_utilisateur""", (email,))[0]
    return lien.rsplit("/", 1)[1], uid["id_utilisateur"]


def test_acceptation_par_le_lien(client, sql):
    jeton, uid = _inviter_et_creer(client, sql, "paul.nkoa@entreprise-a.cm")
    assert client.post(f"/api/invitations/{jeton}/accepter", headers=comme(NADEGE)).status_code == 403
    r = client.post(f"/api/invitations/{jeton}/accepter", headers=comme(uid))
    assert r.status_code == 200 and "Entreprise A" in r.json()["message"]
    assert sql("SELECT role FROM appartenance WHERE id_utilisateur = %s AND id_organisation = %s",
               (uid, ORG))[0]["role"] == "membre"
    assert client.post(f"/api/invitations/{jeton}/accepter", headers=comme(uid)).status_code == 409
    assert client.post("/api/invitations/" + "0" * 32 + "/accepter", headers=comme(uid)).status_code == 404


def test_invitation_expiree(client, sql):
    jeton, uid = _inviter_et_creer(client, sql, "paul.nkoa@entreprise-a.cm")
    sql("UPDATE invitation SET expire_le = now() - INTERVAL '1 day'")
    assert client.post(f"/api/invitations/{jeton}/accepter", headers=comme(uid)).status_code == 410
    st = client.get(f"/api/organisations/{ORG}/invitations?statut=expiree", headers=comme(HELENE)).json()
    assert [i["email"] for i in st] == ["paul.nkoa@entreprise-a.cm"]


def test_tableau_d_adoption(client, sql):
    jeton, uid = _inviter_et_creer(client, sql, "paul.nkoa@entreprise-a.cm")
    client.post(f"/api/organisations/{ORG}/invitations", json={"emails": ["rita@entreprise-a.cm"]},
                headers=comme(HELENE))
    client.post(f"/api/invitations/{jeton}/accepter", headers=comme(uid))
    a = client.get(f"/api/organisations/{ORG}/adoption", headers=comme(HELENE)).json()
    assert a["effectif"] == 250 and a["membres"] == 4            # Armand, Grâce, Hélène, Paul
    assert a["taux_adoption"] == pytest.approx(4 / 250, abs=1e-3)
    assert a["objectif_adoption"] == 0.3 and not a["objectif_atteint"]
    assert a["manque_pour_objectif"] == 75 - 4
    assert a["conducteurs_agrees"] == 1                            # Armand
    assert a["invitations"] == {"envoyees": 2, "acceptees": 1, "en_attente": 1, "expirees": 0,
                                "taux_acceptation": 0.5}
    assert a["par_mois"][-1]["membres_cumules"] == 4


# --------------------------------------------------------------------------- US14
def test_economies_et_co2(client, sql):
    r = client.get(f"/api/organisations/{ORG}/impact?du=2026-11-01&au=2026-11-30", headers=comme(HELENE))
    assert r.status_code == 200
    i = r.json()
    # Réservations 1 et 2 : Grâce, Kotto → Bonanjo, 175 FCFA, détour 1,2 km
    assert i["trajets_partages"] == 2
    km = 2 * moteur.km_evites(4.072, 9.766, 4.042, 9.689, 1.2)
    assert i["km_voiture_evites"] == pytest.approx(km, abs=0.1)
    litres = km * config.CONSO_REFERENCE_L100 / 100
    assert i["co2_evite_kg"]["haut"] == pytest.approx(litres * 2.31, abs=0.1)
    assert i["co2_evite_kg"]["prudent"] == pytest.approx(litres * 2.31 / 3, abs=0.1)
    assert i["economies_employes_fcfa"] == 2 * (600 - 175)
    assert i["abonnement"]["cout_fcfa"] == 3 * 1500             # 3 membres en novembre
    assert i["par_mois"][0]["mois"] == "2026-11"
    assert "hypotheses" in i


def test_impact_exclut_les_autres_organisations_et_les_annulations(client, sql):
    sql("UPDATE reservation SET statut = 'annulee' WHERE id_reservation = 2")
    i = client.get(f"/api/organisations/{ORG}/impact?du=2026-11-01&au=2026-11-30", headers=comme(HELENE)).json()
    assert i["trajets_partages"] == 1


def test_periode_invalide(client):
    r = client.get(f"/api/organisations/{ORG}/impact?du=2026-12-01&au=2026-11-01", headers=comme(HELENE))
    assert r.status_code == 422


def test_conducteur_membre_ne_voit_pas_la_console(client):
    assert client.get(f"/api/organisations/{ORG}/impact", headers=comme(ARMAND)).status_code == 403
