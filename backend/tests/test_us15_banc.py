"""US15 · Banc de mesure du moteur multi-agents exposé par l'API."""

from __future__ import annotations


def test_les_scenarios_mesurables_sont_listes(client):
    scenarios = client.get("/api/demo/banc").json()
    codes = [s["code"] for s in scenarios]
    assert "S1" in codes
    assert all(s["titre"] for s in scenarios)


def test_une_mesure_donne_les_quatre_criteres_de_la_grille(client):
    r = client.post("/api/demo/banc/S1?runs=3")
    assert r.status_code == 200, r.text
    rapport = r.json()
    assert rapport["scenario"] == "S1" and rapport["runs"] == 3
    assert set(rapport["targets"]) == {"convergence_under_2s", "under_20_messages_per_crew",
                                       "deterministic", "memory_stable"}
    assert rapport["convergence_s"]["max"] < 2.0
    assert rapport["targets"]["convergence_under_2s"] is True
    assert rapport["deterministic"] is True and rapport["distinct_fingerprints"] == 1
    assert rapport["messages"] > 0 and rapport["by_type"]
    assert rapport["crews"] >= 1
    assert rapport["memory_peak_kib_first"] and rapport["memory_peak_kib_last"]


def test_un_scenario_inconnu_est_refuse(client):
    r = client.post("/api/demo/banc/S9")
    assert r.status_code == 404 and "S1" in r.text


def test_le_nombre_d_executions_est_borne(client):
    assert client.post("/api/demo/banc/S1?runs=0").status_code == 422
    assert client.post("/api/demo/banc/S1?runs=99").status_code == 422
