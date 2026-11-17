"""Choix du routage par configuration : estimateur par défaut, OSRM si configuré."""

from __future__ import annotations

import importlib

import httpx


def _recharge(monkeypatch, url: str):
    from app import config, moteur
    monkeypatch.setattr(config, "OSRM_URL", url)
    return importlib.reload(moteur)


def test_sans_osrm_tout_reste_estime_et_deterministe(monkeypatch):
    from mboaride_agents.routing import EstimatedRouting

    moteur = _recharge(monkeypatch, "")
    try:
        assert isinstance(moteur.ROUTAGE_URBAIN, EstimatedRouting)
        assert moteur.routage_actif() == {"mode": "estimateur"}
    finally:
        _recharge(monkeypatch, "")


def test_avec_osrm_les_detours_sont_mesures_et_annonces(monkeypatch):
    from mboaride_agents.osrm import OsrmRouting

    moteur = _recharge(monkeypatch, "http://osrm:5000")
    try:
        assert isinstance(moteur.ROUTAGE_URBAIN, OsrmRouting)
        assert isinstance(moteur.ROUTAGE_INTERURBAIN, OsrmRouting)
        etat = moteur.routage_actif()
        assert etat["mode"] == "osrm" and etat["serveur"] == "http://osrm:5000"
        # Les vitesses de repli restent celles de la ville et de l'axe interurbain.
        assert moteur.ROUTAGE_URBAIN.fallback is moteur.ESTIMATEUR_URBAIN
        assert moteur.ROUTAGE_INTERURBAIN.fallback is moteur.ESTIMATEUR_INTERURBAIN
    finally:
        _recharge(monkeypatch, "")


def test_une_panne_d_osrm_ne_fait_pas_echouer_une_offre(monkeypatch, client, sql):
    """Le serveur de routage tombe : l'offre est calculée avec l'estimateur."""
    from conftest import GRACE, comme

    moteur = _recharge(monkeypatch, "http://osrm-en-panne:5000")
    try:
        vrai_client = httpx.AsyncClient

        def client_en_panne(*args, **kwargs):
            def refuser(requete: httpx.Request) -> httpx.Response:
                raise httpx.ConnectError("serveur injoignable", request=requete)
            kwargs["transport"] = httpx.MockTransport(refuser)
            return vrai_client(*args, **kwargs)

        monkeypatch.setattr(httpx, "AsyncClient", client_en_panne)

        offres = client.get(f"/api/moi/demandes/1/offres", headers=comme(GRACE))
        assert offres.status_code == 200
        assert offres.json(), "une offre reste proposée malgré la panne du routage"
        assert moteur.ROUTAGE_URBAIN.stats["replis"] > 0
    finally:
        _recharge(monkeypatch, "")
