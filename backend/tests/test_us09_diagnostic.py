"""US09 · Aucune offre : diagnostic par motif, élargissement du cercle, voiture complète."""

from conftest import GRACE, comme


def _demande_bonapriso(sql, cercle="organisation", jour="2026-11-18"):
    return sql("""INSERT INTO demande (id_demandeur, id_organisation, depart_libelle, depart_lat, depart_lon,
                      arrivee_libelle, arrivee_lat, arrivee_lon, arrivee_au_plus_tot, arrivee_au_plus_tard,
                      date_unique, prix_max_fcfa, cercle_max)
                  VALUES (2, 1, 'Makepe', 4.081, 9.752, 'Bonapriso', 4.033, 9.695, '06:55', '07:15', %s, 400, %s)
                  RETURNING id_demande""", (jour, cercle))[0]["id_demande"]


def test_diagnostic_et_elargissement(client, sql):
    d = _demande_bonapriso(sql)
    assert not [o for o in client.get(f"/api/moi/demandes/{d}/offres", headers=comme(GRACE)).json() if o["confirmable"]]
    diag = client.get(f"/api/moi/demandes/{d}/diagnostic", headers=comme(GRACE)).json()
    assert diag["offres_confirmables"] == 0 and "cercle" in {m["code"] for m in diag["motifs"]}
    assert diag["suggestions"][0] == {"action": "elargir", "cercle_max": "public", "offres_en_plus": 1,
                                      "message": "Élargir au cercle « public » ajoute 1 offre(s) confirmable(s)"}
    r = client.post(f"/api/moi/demandes/{d}/elargir", headers=comme(GRACE), json={"cercle_max": "public"}).json()
    assert r["offres_ajoutees"] == 1
    brice = [o for o in r["offres"] if o["confirmable"]][0]
    assert brice["conducteur"] == "Brice" and brice["commission_fcfa"] > 0
    assert client.post(f"/api/moi/demandes/{d}/elargir", headers=comme(GRACE),
                       json={"cercle_max": "partenaires"}).status_code == 422


def test_voiture_complete_ce_jour_la(client, sql):
    d = _demande_bonapriso(sql, "public", "2026-11-17")     # Brice : 2 places, déjà 2 réservations le 17
    diag = client.get(f"/api/moi/demandes/{d}/diagnostic", headers=comme(GRACE)).json()
    assert "complet" in {m["code"] for m in diag["motifs"]}
