"""Implémentation de `RoutingService` qui interroge un serveur OSRM.

Les agents conducteurs dépendent de l'interface `RoutingService` (voir `routing.py`),
jamais d'une implémentation : brancher de vraies routes ne change donc rien à leur code
ni au format des messages. Cette classe compare, comme `computeDetour` de l'API Node,
le trajet direct A -> B au trajet A -> prise en charge -> dépose -> B, en une requête
`/route` par trajet, et renvoie le même `Detour`.

Deux garde-fous, parce qu'un serveur de routage tombe ou répond lentement :

- **repli** : à la moindre erreur, réponse illisible, délai dépassé ou position hors du
  réseau, le détour est recalculé par `EstimatedRouting`, l'estimateur déterministe.
  L'appel ne lève jamais : un conducteur n'est pas écarté d'une négociation parce que
  le réseau a hoqueté, il est évalué avec une estimation un peu moins précise.
- **cache** : les mêmes quatre points reviennent sans cesse pendant une négociation
  (un appel d'offres interroge plusieurs conducteurs sur les mêmes points), les
  coordonnées sont donc arrondies à cinq décimales, environ un mètre, et le résultat
  est gardé.

Le banc de mesure et les tests gardent l'estimateur : leurs mesures de convergence,
de messages et de déterminisme ne doivent rien devoir au réseau.
"""
from __future__ import annotations

import logging
from collections import OrderedDict

from .routing import Detour, EstimatedRouting, Point, _round

logger = logging.getLogger(__name__)

# Précision du cache : 5 décimales de degré, environ un mètre à cette latitude.
PRECISION = 5


class OsrmRouting:
    """`RoutingService` adossé à un serveur OSRM, avec repli sur l'estimateur."""

    def __init__(self, base_url: str, *, fallback: EstimatedRouting | None = None,
                 timeout_s: float = 3.0, profile: str = "driving", cache_size: int = 4096):
        self.base_url = base_url.rstrip("/")
        self.fallback = fallback or EstimatedRouting()
        self.timeout_s = timeout_s
        self.profile = profile
        self.cache_size = cache_size
        self._cache: OrderedDict[tuple, Detour] = OrderedDict()
        self.calls = 0        # requêtes envoyées au serveur
        self.fallbacks = 0    # détours recalculés par l'estimateur
        self.hits = 0         # détours servis par le cache

    # L'estimateur reste la référence pour un tronçon simple : la distance affichée
    # dans l'application n'a pas besoin d'un appel réseau par ligne de tableau.
    def leg(self, a: Point, b: Point) -> tuple[float, float]:
        return self.fallback.leg(a, b)

    async def detour(self, origin: Point, destination: Point,
                     pickup: Point, dropoff: Point) -> Detour:
        cle = tuple(_arrondi(p) for p in (origin, destination, pickup, dropoff))
        if cle in self._cache:
            self._cache.move_to_end(cle)
            self.hits += 1
            return self._cache[cle]

        resultat = await self._depuis_osrm(origin, destination, pickup, dropoff)
        if resultat is None:
            self.fallbacks += 1
            resultat = await self.fallback.detour(origin, destination, pickup, dropoff)

        self._cache[cle] = resultat
        self._cache.move_to_end(cle)
        while len(self._cache) > self.cache_size:
            self._cache.popitem(last=False)
        return resultat

    async def _depuis_osrm(self, origin: Point, destination: Point,
                           pickup: Point, dropoff: Point) -> Detour | None:
        """Détour mesuré par OSRM, ou None si le serveur n'a pas pu répondre."""
        try:
            import httpx
        except ImportError:                     # pragma: no cover - dépend du déploiement
            logger.warning("httpx absent : OSRM ignoré, estimateur utilisé")
            return None

        direct = self._url(origin, destination)
        avec = self._url(origin, pickup, dropoff, destination)
        try:
            async with httpx.AsyncClient(timeout=self.timeout_s) as client:
                self.calls += 2
                r_direct, r_avec = (await client.get(direct)), (await client.get(avec))
            trajet_direct = _itineraire(r_direct)
            trajet_avec = _itineraire(r_avec)
        except Exception as exc:                # réseau, délai, JSON illisible
            logger.info("OSRM indisponible (%s) : estimateur utilisé", exc)
            return None
        if trajet_direct is None or trajet_avec is None or len(trajet_avec["legs"]) != 3:
            logger.info("Réponse OSRM inutilisable : estimateur utilisé")
            return None

        direct_m, direct_s = trajet_direct["distance"], trajet_direct["duration"]
        vers_prise, commun, vers_fin = trajet_avec["legs"]
        total_m = trajet_avec["distance"]
        total_s = trajet_avec["duration"]
        if min(direct_m, total_m) <= 0:
            return None
        return Detour(
            detour_m=max(0, _round(total_m - direct_m)),
            detour_s=max(0, _round(total_s - direct_s)),
            pickup_offset_s=_round(vers_prise["duration"]),
            shared_distance_m=_round(commun["distance"]),
            shared_duration_s=_round(commun["duration"]),
            direct_distance_m=_round(direct_m),
        )

    def _url(self, *points: Point) -> str:
        # OSRM attend les coordonnées en longitude, latitude.
        trace = ";".join(f"{p.lng:.6f},{p.lat:.6f}" for p in points)
        return (f"{self.base_url}/route/v1/{self.profile}/{trace}"
                f"?overview=false&alternatives=false&steps=false&annotations=false")

    @property
    def stats(self) -> dict[str, int]:
        """Compteurs utiles en démonstration : appels, replis, cache."""
        return {"appels": self.calls, "replis": self.fallbacks, "cache": self.hits}


def _arrondi(point: Point) -> tuple[float, float]:
    return (round(point.lat, PRECISION), round(point.lng, PRECISION))


def _itineraire(reponse) -> dict | None:
    """Premier itinéraire d'une réponse OSRM, ou None si elle n'est pas exploitable."""
    if reponse.status_code != 200:
        return None
    corps = reponse.json()
    if corps.get("code") != "Ok" or not corps.get("routes"):
        return None
    route = corps["routes"][0]
    route.setdefault("legs", [])
    return route
