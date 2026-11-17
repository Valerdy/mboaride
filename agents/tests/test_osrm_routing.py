"""Routage réel par OSRM, avec repli sur l'estimateur (intégration SR-?).

Les agents ne doivent rien perdre quand le serveur de routage tombe : le détour est
alors recalculé par l'estimateur, et aucun conducteur n'est écarté de la négociation
pour une panne réseau.
"""

from __future__ import annotations

import asyncio

import httpx
import pytest

from mboaride_agents.osrm import OsrmRouting
from mboaride_agents.routing import EstimatedRouting, Point

AKWA = Point(4.0511, 9.7085)
BONANJO = Point(4.0400, 9.6920)
MAKEPE = Point(4.0810, 9.7520)
BONAPRISO = Point(4.0330, 9.6950)


def _reponse(distance: float, duration: float, legs: list[tuple[float, float]]) -> dict:
    return {"code": "Ok", "routes": [{"distance": distance, "duration": duration,
                                      "legs": [{"distance": d, "duration": t} for d, t in legs]}]}


def _serveur(appels: list[str], direct: dict, avec: dict) -> httpx.MockTransport:
    def repondre(requete: httpx.Request) -> httpx.Response:
        appels.append(str(requete.url))
        # Le trajet direct a deux points, le trajet avec passager en a quatre.
        points = str(requete.url).split("/driving/")[1].split("?")[0].split(";")
        return httpx.Response(200, json=direct if len(points) == 2 else avec)
    return httpx.MockTransport(repondre)


def _brancher(monkeypatch, transport: httpx.MockTransport) -> None:
    vrai_client = httpx.AsyncClient

    def client(*args, **kwargs):
        kwargs["transport"] = transport
        return vrai_client(*args, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", client)


def test_le_detour_vient_des_distances_mesurees_par_osrm(monkeypatch):
    appels: list[str] = []
    direct = _reponse(5_000, 900, [(5_000, 900)])
    avec = _reponse(8_200, 1_500, [(2_000, 400), (4_200, 800), (2_000, 300)])
    _brancher(monkeypatch, _serveur(appels, direct, avec))

    routage = OsrmRouting("http://osrm:5000", fallback=EstimatedRouting())
    d = asyncio.run(routage.detour(AKWA, BONANJO, MAKEPE, BONAPRISO))

    assert d.direct_distance_m == 5_000
    assert d.detour_m == 3_200            # 8 200 avec le passager, 5 000 sans
    assert d.detour_s == 600
    assert d.pickup_offset_s == 400       # premier tronçon : aller chercher le passager
    assert d.shared_distance_m == 4_200   # tronçon parcouru ensemble
    assert d.shared_duration_s == 800
    assert d.trip_distance_m == 8_200     # base de la règle de partage des frais
    assert len(appels) == 2
    # OSRM attend longitude puis latitude : l'inverse enverrait les voitures en mer.
    assert "9.708500,4.051100" in appels[0]


def test_les_memes_points_ne_sont_demandes_qu_une_fois(monkeypatch):
    appels: list[str] = []
    direct = _reponse(5_000, 900, [(5_000, 900)])
    avec = _reponse(8_200, 1_500, [(2_000, 400), (4_200, 800), (2_000, 300)])
    _brancher(monkeypatch, _serveur(appels, direct, avec))

    routage = OsrmRouting("http://osrm:5000")
    premier = asyncio.run(routage.detour(AKWA, BONANJO, MAKEPE, BONAPRISO))
    second = asyncio.run(routage.detour(AKWA, BONANJO, MAKEPE, BONAPRISO))

    assert premier == second
    assert len(appels) == 2 and routage.stats == {"appels": 2, "replis": 0, "cache": 1}


@pytest.mark.parametrize("panne", ["erreur", "delai", "json", "hors_reseau", "legs"])
def test_une_panne_du_serveur_fait_repli_sur_l_estimateur(monkeypatch, panne):
    def repondre(requete: httpx.Request) -> httpx.Response:
        if panne == "erreur":
            return httpx.Response(502, text="bad gateway")
        if panne == "delai":
            raise httpx.ReadTimeout("trop lent", request=requete)
        if panne == "json":
            return httpx.Response(200, text="<html>pas du json</html>")
        if panne == "hors_reseau":
            return httpx.Response(200, json={"code": "NoRoute", "routes": []})
        return httpx.Response(200, json=_reponse(8_200, 1_500, [(8_200, 1_500)]))
    _brancher(monkeypatch, httpx.MockTransport(repondre))

    estimateur = EstimatedRouting()
    routage = OsrmRouting("http://osrm:5000", fallback=estimateur)

    mesure = asyncio.run(routage.detour(AKWA, BONANJO, MAKEPE, BONAPRISO))
    attendu = asyncio.run(estimateur.detour(AKWA, BONANJO, MAKEPE, BONAPRISO))

    assert mesure == attendu
    assert routage.stats["replis"] == 1


def test_un_troncon_simple_reste_estime_sans_appel_reseau(monkeypatch):
    def refuser(requete: httpx.Request) -> httpx.Response:
        raise AssertionError("aucun appel réseau attendu pour un tronçon simple")
    _brancher(monkeypatch, httpx.MockTransport(refuser))

    routage = OsrmRouting("http://osrm:5000")
    assert routage.leg(AKWA, BONANJO) == EstimatedRouting().leg(AKWA, BONANJO)


def test_le_service_respecte_l_interface_attendue_par_les_agents():
    """Même signature que `RoutingService.detour` : un agent conducteur ne voit
    aucune différence entre l'estimateur et le routage réel."""
    import inspect

    from mboaride_agents.routing import RoutingService

    attendue = inspect.signature(RoutingService.detour)
    assert inspect.signature(OsrmRouting.detour) == attendue
    assert inspect.signature(EstimatedRouting.detour) == attendue
    assert inspect.iscoroutinefunction(OsrmRouting.detour)
