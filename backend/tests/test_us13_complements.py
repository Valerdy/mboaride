"""US13 et US14 · Services, courriels, inscription depuis le lien, export CSV."""

from conftest import GRACE, HELENE, comme

ORG = 1


def test_invitation_avec_service_et_courriel_trace(client, sql):
    r = client.post(f"/api/organisations/{ORG}/invitations", headers=comme(HELENE), json={
        "emails": ["paul@entreprise-a.cm ; Logistique", "rita@entreprise-a.cm"], "service": "Finance"}).json()
    assert [(e["email"], e["service"], e["courriel"]) for e in r["envoyees"]] == [
        ("paul@entreprise-a.cm", "Logistique", "simule"), ("rita@entreprise-a.cm", "Finance", "simule")]
    assert "simulé" in r["note"]
    mails = sql("SELECT destinataire, corps FROM courriel ORDER BY id_courriel")
    assert [m["destinataire"] for m in mails] == ["paul@entreprise-a.cm", "rita@entreprise-a.cm"]
    assert "/rejoindre/" in mails[0]["corps"]


def test_inscription_depuis_le_lien(client, sql):
    lien = client.post(f"/api/organisations/{ORG}/invitations", headers=comme(HELENE), json={
        "emails": ["paul@entreprise-a.cm;Logistique"]}).json()["envoyees"][0]["lien"]
    jeton = lien.rsplit("/", 1)[1]
    info = client.get(f"/api/invitations/{jeton}").json()
    assert info["organisation"].startswith("Entreprise A") and not info["compte_existant"]
    corps = {"prenom": "Paul", "nom": "Nkoa", "telephone": "6 99 11 22 33", "mot_de_passe": "secret123"}
    assert client.post(f"/api/invitations/{jeton}/inscription", json={**corps, "telephone": "12345"}).status_code == 422
    r = client.post(f"/api/invitations/{jeton}/inscription", json=corps)
    assert r.status_code == 201
    uid = r.json()["id_utilisateur"]
    row = sql("""SELECT u.email, u.telephone, u.mot_de_passe_hache, a.service FROM utilisateur u
                 JOIN appartenance a USING (id_utilisateur) WHERE u.id_utilisateur = %s""", (uid,))[0]
    assert row["email"] == "paul@entreprise-a.cm" and row["telephone"] == "+237699112233"
    assert row["mot_de_passe_hache"].startswith("pbkdf2_sha256$") and "secret123" not in row["mot_de_passe_hache"]
    assert row["service"] == "Logistique"
    assert client.post(f"/api/invitations/{jeton}/inscription", json=corps).status_code == 409


def test_adoption_par_service(client, sql):
    client.post(f"/api/organisations/{ORG}/invitations", headers=comme(HELENE),
                json={"emails": ["paul@entreprise-a.cm;Finance"]})
    a = client.get(f"/api/organisations/{ORG}/adoption", headers=comme(HELENE)).json()
    services = {s["service"]: s for s in a["par_service"]}
    assert services["Finance"]["membres"] == 1 and services["Finance"]["invitations_en_attente"] == 1
    assert services["Ressources humaines"]["membres"] == 1 and services["Technique"]["membres"] == 1


def test_export_csv(client):
    r = client.get(f"/api/organisations/{ORG}/impact.csv?du=2026-11-01&au=2026-11-30", headers=comme(HELENE))
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    assert "attachment" in r.headers["content-disposition"]
    texte = r.content.decode("utf-8-sig")
    assert "Total;2;" in texte and "Économies employés (FCFA)" in texte
    assert client.get(f"/api/organisations/{ORG}/impact.csv", headers=comme(GRACE)).status_code == 403
