"""US10 · Payer par Mobile Money (simulé)."""

from conftest import GRACE, JUNIOR, comme


PAIEMENT_JUNIOR = 2     # réservation 5, Ndokoti → Yaoundé, 3 200 FCFA dont 290 de commission


def test_paiement_mobile_money_reussi(client, sql):
    url = f"/api/paiements/{PAIEMENT_JUNIOR}"
    r = client.post(f"{url}/mobile-money", headers=comme(JUNIOR), json={"operateur": "orange", "telephone": "677123456"})
    assert r.status_code == 422 and "MTN" in r.json()["detail"]
    r = client.post(f"{url}/mobile-money", headers=comme(JUNIOR), json={"operateur": "orange", "telephone": "+237 699 12 34 56"})
    assert r.status_code == 200 and r.json()["etape"] == "validation_telephone"
    recu = client.post(f"{url}/simulation-operateur", headers=comme(JUNIOR), json={"resultat": "valide"}).json()
    assert recu["statut"] == "reussi" and recu["reference"].startswith("MBR-")
    assert recu["reverse_conducteur_fcfa"] == 3200 - 290 and recu["operateur"] == "Orange Money"
    assert client.post(f"{url}/mobile-money", headers=comme(JUNIOR),
                       json={"operateur": "orange", "telephone": "699123456"}).status_code == 409
    assert sql("SELECT type FROM notification WHERE id_utilisateur = %s", (JUNIOR,))[0]["type"] == "paiement"


def test_paiement_echoue_puis_tentatives_limitees(client):
    url = f"/api/paiements/{PAIEMENT_JUNIOR}"
    for resultat in ("refuse", "solde_insuffisant", "delai_depasse"):
        assert client.post(f"{url}/mobile-money", headers=comme(JUNIOR),
                           json={"operateur": "mtn", "telephone": "677123456"}).status_code == 200
        r = client.post(f"{url}/simulation-operateur", headers=comme(JUNIOR), json={"resultat": resultat}).json()
        assert r["statut"] == "echoue" and r["motif_echec"]
    assert r["tentatives_restantes"] == 0
    assert client.post(f"{url}/mobile-money", headers=comme(JUNIOR),
                       json={"operateur": "mtn", "telephone": "677123456"}).status_code == 409


def test_paiement_d_un_autre_et_sans_initiation(client):
    url = f"/api/paiements/{PAIEMENT_JUNIOR}"
    assert client.post(f"{url}/mobile-money", headers=comme(GRACE),
                       json={"operateur": "mtn", "telephone": "677123456"}).status_code == 403
    assert client.post(f"{url}/simulation-operateur", headers=comme(JUNIOR),
                       json={"resultat": "valide"}).status_code == 409
