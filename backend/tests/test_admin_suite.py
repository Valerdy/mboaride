"""Console d'administration, 2e partie : paramètres, signalements, organisations, communication, journal."""

from __future__ import annotations

import pytest

from conftest import ARMAND, GRACE, HELENE, MIREILLE, comme

CHEF, SUPPORT, FINANCE = HELENE, MIREILLE, 6
PIECES = ("piece_identite", "permis", "casier_judiciaire", "assurance")


@pytest.fixture()
def equipe(sql):
    sql("INSERT INTO administrateur (id_utilisateur, role) VALUES (%s, 'super_admin'), (%s, 'support'), "
        "(%s, 'finance')", (CHEF, SUPPORT, FINANCE))
    return sql


def _estimation(client):
    return client.post("/api/prix/estimation", json={"id_demande": 1, "id_trajet": 1}, headers=comme(GRACE)).json()


# --- Paramètres ------------------------------------------------------------------------------

def test_les_parametres_changent_le_prix(client, equipe):
    liste = client.get("/api/admin/parametres", headers=comme(FINANCE)).json()
    assert {p["cle"]: p["valeur"] for p in liste}["commission_pct"] == 10
    avant = _estimation(client)
    assert avant["commission_fcfa"] == avant["prix_fcfa"] // 10

    corps = {"valeurs": {"commission_pct": 20, "arrondi_fcfa": 50}}
    assert client.put("/api/admin/parametres", json=corps, headers=comme(SUPPORT)).status_code == 403
    sim = client.post("/api/admin/parametres/simulation", json=corps, headers=comme(SUPPORT)).json()
    assert sim["propose"]["prix_fcfa"] > sim["actuel"]["prix_fcfa"] and sim["propose"]["prix_fcfa"] % 50 == 0

    r = client.put("/api/admin/parametres", json=corps, headers=comme(CHEF))
    assert r.status_code == 200, r.text
    regle = {p["cle"]: p for p in r.json()}
    assert regle["commission_pct"]["valeur"] == 20 and regle["commission_pct"]["maj_par"] == "Hélène Ekwalla"

    apres = _estimation(client)
    assert apres["prix_fcfa"] % 50 == 0 and apres["commission_fcfa"] == apres["prix_fcfa"] // 5
    assert any("20 % du prix" in l["libelle"] for l in apres["detail"])
    assert "commission MboaRide de 20 %" in apres["formule"]
    journal = client.get("/api/admin/journal?action=parametres", headers=comme(CHEF)).json()["lignes"]
    assert "Commission MboaRide 10 → 20" in journal[0]["resume"]


def test_parametres_hors_limites(client, equipe):
    for valeurs in ({"commission_pct": 80}, {"inconnu": 3}, {"arrondi_fcfa": 0}):
        assert client.put("/api/admin/parametres", json={"valeurs": valeurs}, headers=comme(CHEF)).status_code == 422


# --- Signalements -----------------------------------------------------------------------------

def _signaler(sql):
    """Grâce signale Armand : le déclencheur de la base suspend aussitôt son agrément."""
    sql("INSERT INTO evaluation (id_reservation, id_auteur, id_evalue, note, commentaire, signalement_grave) "
        "VALUES (2, %s, %s, 1, 'Conduite dangereuse', TRUE)", (GRACE, ARMAND))
    return sql("SELECT id_evaluation FROM evaluation WHERE signalement_grave")[0]["id_evaluation"]


def test_classer_un_signalement_retablit_l_agrement(client, equipe):
    for piece in PIECES:
        equipe("INSERT INTO document_agrement (id_utilisateur, type_document, statut, chemin_fichier, expire_le) "
               "VALUES (%s, %s, 'valide', 'f', CURRENT_DATE + 300) ON CONFLICT (id_utilisateur, type_document) "
               "DO UPDATE SET statut = 'valide', expire_le = CURRENT_DATE + 300", (ARMAND, piece))
    ide = _signaler(equipe)
    assert equipe("SELECT statut_agrement FROM utilisateur WHERE id_utilisateur = %s", (ARMAND,))[0][
        "statut_agrement"] == "suspendu"
    a_traiter = client.get("/api/admin/evaluations", headers=comme(SUPPORT)).json()
    assert [e["id_evaluation"] for e in a_traiter["lignes"]] == [ide]
    stats = client.get("/api/admin/evaluations/statistiques", headers=comme(SUPPORT)).json()
    assert stats["a_traiter"] == 1 and stats["a_surveiller"][0]["id_utilisateur"] == ARMAND

    r = client.post(f"/api/admin/signalements/{ide}/traitement",
                    json={"decision": "classe", "note": "Témoins contactés : rien à reprocher", "retablir_agrement": True},
                    headers=comme(SUPPORT))
    assert r.status_code == 200, r.text and r.json()["statut_agrement"] == "actif"
    assert r.json()["statut_agrement"] == "actif"
    assert client.post(f"/api/admin/signalements/{ide}/traitement", json={"decision": "classe", "note": "encore"},
                       headers=comme(SUPPORT)).status_code == 409
    assert client.get("/api/admin/evaluations", headers=comme(SUPPORT)).json()["total"] == 0
    merci = equipe("SELECT message FROM notification WHERE id_utilisateur = %s AND type = 'administration'", (GRACE,))
    assert "Merci pour votre signalement" in merci[0]["message"]


def test_suspendre_le_compte_apres_un_signalement(client, equipe):
    ide = _signaler(equipe)
    r = client.post(f"/api/admin/signalements/{ide}/traitement",
                    json={"decision": "suspension_compte", "note": "Faits confirmés"}, headers=comme(SUPPORT))
    assert r.status_code == 200, r.text
    assert r.json()["trajets_retires"] >= 1
    assert client.get("/api/moi/notifications", headers=comme(ARMAND)).status_code == 403
    traite = client.get("/api/admin/evaluations?filtre=signalements", headers=comme(SUPPORT)).json()["lignes"][0]
    assert traite["decision"] == "suspension_compte" and traite["traite_par"] == "Mireille Fotso"


# --- Organisations ----------------------------------------------------------------------------

def test_gerer_une_organisation(client, equipe):
    assert client.get("/api/admin/organisations", headers=comme(FINANCE)).status_code == 403
    r = client.post("/api/admin/organisations", json={"nom": "Brasseries du Littoral", "domaine_email": "@brasseries.cm",
                                                       "effectif": 200, "tarif_mensuel_fcfa": 50000},
                    headers=comme(SUPPORT))
    assert r.status_code == 201, r.text
    org = r.json()
    assert org["domaine_email"] == "brasseries.cm" and len(org["code_invitation"]) == 8
    assert client.post("/api/admin/organisations", json={"nom": "Doublon", "domaine_email": "brasseries.cm"},
                       headers=comme(SUPPORT)).status_code == 409

    oid = org["id_organisation"]
    r = client.patch(f"/api/admin/organisations/{oid}", json={"abonnement_actif": True}, headers=comme(SUPPORT))
    assert r.json()["abonnement_actif"] is True
    assert client.post(f"/api/admin/organisations/{oid}/partenaires", json={"id_organisation": 1},
                       headers=comme(SUPPORT)).status_code == 201
    assert client.post(f"/api/admin/organisations/1/partenaires", json={"id_organisation": oid},
                       headers=comme(SUPPORT)).status_code == 409
    r = client.post(f"/api/admin/organisations/{oid}/membres",
                    json={"identifiant": "grace@entreprise-a.cm", "role": "administrateur"}, headers=comme(SUPPORT))
    assert r.status_code == 201 and r.json()["id_utilisateur"] == GRACE

    fiche = client.get(f"/api/admin/organisations/{oid}", headers=comme(SUPPORT)).json()
    assert [m["id_utilisateur"] for m in fiche["membres"]] == [GRACE]
    assert [p["id_organisation"] for p in fiche["partenaires"]] == [1]
    assert fiche["indicateurs"]["adoption"] == 0.005
    assert all(o["id_organisation"] not in (1, oid) for o in fiche["autres_organisations"])

    assert client.delete(f"/api/admin/organisations/{oid}/partenaires/1", headers=comme(SUPPORT)).status_code == 200
    assert client.delete(f"/api/admin/organisations/{oid}/membres/{GRACE}", headers=comme(SUPPORT)).status_code == 200
    liste = client.get("/api/admin/organisations?q=brasseries", headers=comme(SUPPORT)).json()
    assert liste["total"] == 1 and liste["lignes"][0]["membres"] == 0


# --- Communication ----------------------------------------------------------------------------

def test_envoyer_un_message_a_une_organisation(client, equipe):
    aud = client.get("/api/admin/communication/audience?cible=organisation&id_organisation=1",
                     headers=comme(SUPPORT)).json()
    assert aud["destinataires"] >= 3 and aud["avec_email"] >= 2
    assert client.post("/api/admin/communication/annonces", json={"cible": "organisation", "message": "Bonjour"},
                       headers=comme(SUPPORT)).status_code == 422      # organisation non choisie
    r = client.post("/api/admin/communication/annonces",
                    json={"cible": "organisation", "id_organisation": 1, "par_email": True,
                          "message": "Nouvelle ligne Logpom → Bonanjo dès lundi."}, headers=comme(SUPPORT))
    assert r.status_code == 201, r.text
    assert r.json()["destinataires"] == aud["destinataires"]
    assert r.json()["courriels"]["simule"] == aud["avec_email"]
    notif = client.get("/api/moi/notifications", headers=comme(GRACE)).json()[0]
    assert notif["type"] == "administration" and "Logpom" in notif["message"]
    historique = client.get("/api/admin/communication/annonces", headers=comme(SUPPORT)).json()["lignes"]
    assert historique[0]["organisation"] and historique[0]["par"] == "Mireille Fotso"
    courriels = client.get("/api/admin/communication/courriels?q=entreprise-a", headers=comme(SUPPORT)).json()
    assert courriels["total"] >= 2


def test_codes_de_verification_envoyes(client, equipe):
    assert client.get("/api/admin/communication/codes", headers=comme(SUPPORT)).json()["disponible"] is False
    # Tables de l'API Node, telles qu'elle les crée dans le schéma public.
    equipe("CREATE TABLE IF NOT EXISTS public.users (id SERIAL PRIMARY KEY, email TEXT, phone TEXT, full_name TEXT, "
           "is_verified BOOLEAN DEFAULT FALSE)")
    equipe("CREATE TABLE public.otp_deliveries (id SERIAL PRIMARY KEY, user_id INTEGER, channel TEXT, "
           "destination TEXT, minutes INTEGER, created_at BIGINT)")
    uid = equipe("INSERT INTO public.users (email, phone, full_name) VALUES ('lina@x.cm', '+237690000001', 'Lina') "
                 "RETURNING id")[0]["id"]
    equipe("INSERT INTO public.otp_deliveries (user_id, channel, destination, minutes, created_at) VALUES "
           "(%s, 'console', 'console du serveur', 5, extract(epoch FROM now()) * 1000), "
           "(%s, 'email', 'li***@x.cm', 5, extract(epoch FROM now()) * 1000 + 1)", (uid, uid))
    r = client.get("/api/admin/communication/codes", headers=comme(SUPPORT)).json()
    assert r["disponible"] and r["total"] == 2
    assert r["lignes"][0]["canal"] == "email" and r["lignes"][0]["nom"] == "Lina"
    assert r["resume"]["console"] == 1 and r["resume"]["dernier_canal"] == "email"
    equipe("DROP TABLE public.otp_deliveries")


# --- Journal ----------------------------------------------------------------------------------

def test_journal_filtrable_et_exportable(client, equipe):
    client.post("/api/admin/organisations", json={"nom": "Lycée de Japoma", "type_organisation": "etablissement_scolaire"},
                headers=comme(SUPPORT))
    client.put("/api/admin/parametres", json={"valeurs": {"otp_minutes": 10}}, headers=comme(CHEF))
    filtres = client.get("/api/admin/journal/filtres", headers=comme(CHEF)).json()
    assert {"organisation_creee", "parametres"} <= set(filtres["actions"])
    assert {a["id_utilisateur"] for a in filtres["auteurs"]} == {CHEF, SUPPORT}
    par_support = client.get(f"/api/admin/journal?id_admin={SUPPORT}", headers=comme(CHEF)).json()
    assert [l["action"] for l in par_support["lignes"]] == ["organisation_creee"]
    assert client.get("/api/admin/journal?q=Japoma", headers=comme(CHEF)).json()["total"] == 1
    csv = client.get("/api/admin/export/journal.csv", headers=comme(CHEF)).content.decode("utf-8-sig").splitlines()
    assert csv[0] == "date;par;action;cible;id_cible;resume" and len(csv) == 3
