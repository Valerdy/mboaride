"""US02 · Renseigner mes exigences de confort et mon cercle de confiance."""

import psycopg
import pytest

from conftest import GRACE, comme


def test_lecture_des_preferences(client):
    r = client.get("/api/moi/preferences", headers=comme(GRACE))
    assert r.status_code == 200
    p = r.json()
    assert p["confort"] == {"climatisation": True, "non_fumeur": False, "silence": False}
    assert p["prix_max_fcfa"] == 400 and p["cercle"] == "partenaires"
    assert p["mode"] == "manuel" and p["priorite"] == "heure"


def test_enregistrement_et_traduction_pour_le_moteur(client, sql):
    corps = {"confort": {"climatisation": True, "non_fumeur": True, "silence": True},
             "prix_max_fcfa": 350, "cercle": "public", "mode": "autonome", "priorite": "prix"}
    r = client.put("/api/moi/preferences", json=corps, headers=comme(GRACE))
    assert r.status_code == 200
    m = r.json()["parametres_moteur"]
    assert m == {"levels": [0, 1, 2], "comfort_wanted": ["clim", "non_fumeur", "silence"],
                 "max_price": 350, "mode": "auto", "priority": "prix"}
    row = sql("SELECT accepte_partenaires, accepte_public, prix_max_defaut_fcfa, mode_reservation, "
              "preferences_maj_le FROM utilisateur WHERE id_utilisateur = %s", (GRACE,))[0]
    assert row["accepte_partenaires"] and row["accepte_public"]
    assert row["prix_max_defaut_fcfa"] == 350 and row["mode_reservation"] == "autonome"
    assert row["preferences_maj_le"] is not None
    # relecture : ce qui est enregistré est bien ce qui est relu
    assert client.get("/api/moi/preferences", headers=comme(GRACE)).json()["cercle"] == "public"


@pytest.mark.parametrize("cercle, attendu", [("organisation", [0]), ("partenaires", [0, 1])])
def test_cercles_emboites(client, cercle, attendu):
    corps = {"confort": {}, "prix_max_fcfa": 500, "cercle": cercle, "mode": "manuel", "priorite": "heure"}
    r = client.put("/api/moi/preferences", json=corps, headers=comme(GRACE))
    assert r.json()["parametres_moteur"]["levels"] == attendu


@pytest.mark.parametrize("champ, valeur", [("prix_max_fcfa", 10), ("prix_max_fcfa", 50000),
                                            ("cercle", "amis"), ("mode", "auto"), ("priorite", "confort")])
def test_valeurs_refusees(client, champ, valeur):
    corps = {"confort": {}, "prix_max_fcfa": 500, "cercle": "partenaires", "mode": "manuel", "priorite": "heure"}
    corps[champ] = valeur
    assert client.put("/api/moi/preferences", json=corps, headers=comme(GRACE)).status_code == 422


def test_identification_obligatoire(client):
    assert client.get("/api/moi/preferences").status_code == 401
    assert client.get("/api/moi/preferences", headers=comme(9999)).status_code == 401


def test_la_base_interdit_public_sans_partenaires(sql):
    with pytest.raises(psycopg.errors.CheckViolation):
        sql("UPDATE utilisateur SET accepte_partenaires = FALSE, accepte_public = TRUE "
            "WHERE id_utilisateur = %s", (GRACE,))
