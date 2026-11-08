"""Calcul des détours pour les agents conducteurs.

Les agents dépendent de l'interface `RoutingService`, pas d'une implémentation :
- `EstimatedRouting` : estimateur local et déterministe (vol d'oiseau x facteur
  routier, vitesse moyenne). Sert aux tests et aux scénarios du banc de mesure,
  qui ne doivent pas dépendre du réseau.
- une implémentation qui appelle l'API Node (`POST /routes/detours`, OSRM) viendra
  avec l'intégration ; elle renverra le même `Detour`.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Protocol

EARTH_RADIUS_M = 6_371_000


@dataclass(frozen=True)
class Point:
    lat: float
    lng: float

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Point:
        return cls(lat=data["lat"], lng=data["lng"])

    def to_json(self) -> dict[str, float]:
        return {"lat": self.lat, "lng": self.lng}


@dataclass(frozen=True)
class Detour:
    """Effet de la prise d'un passager sur le trajet du conducteur.

    Mêmes grandeurs que `computeDetour` de l'API Node : le trajet direct A -> B est
    comparé au trajet A -> prise en charge -> dépose -> B.
    """

    detour_m: int            # distance ajoutée au trajet du conducteur
    detour_s: int            # temps ajouté au trajet du conducteur
    pickup_offset_s: int     # temps entre le départ du conducteur et la prise en charge
    shared_distance_m: int   # distance parcourue avec le passager : base du prix
    shared_duration_s: int   # durée parcourue avec le passager


class NoRouteError(Exception):
    """Aucun itinéraire entre ces points."""


class RoutingService(Protocol):
    async def detour(self, origin: Point, destination: Point, pickup: Point, dropoff: Point) -> Detour: ...


def haversine_m(a: Point, b: Point) -> float:
    """Distance à vol d'oiseau en mètres."""
    phi1, phi2 = math.radians(a.lat), math.radians(b.lat)
    dphi, dlmb = phi2 - phi1, math.radians(b.lng - a.lng)
    h = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


class EstimatedRouting:
    """Estimateur déterministe : distance routière = vol d'oiseau x `road_factor`.

    Par défaut, 20 km/h de moyenne : circulation aux heures de pointe à Douala.
    Pour un axe interurbain, créer une instance avec `speed_kmh=60`.
    """

    def __init__(self, speed_kmh: float = 20.0, road_factor: float = 1.3):
        if speed_kmh <= 0 or road_factor < 1:
            raise ValueError("speed_kmh doit être > 0 et road_factor >= 1")
        self.speed_m_per_s = speed_kmh * 1000 / 3600
        self.road_factor = road_factor

    def leg(self, a: Point, b: Point) -> tuple[float, float]:
        """(distance en m, durée en s) d'un tronçon."""
        distance = haversine_m(a, b) * self.road_factor
        return distance, distance / self.speed_m_per_s

    async def detour(self, origin: Point, destination: Point, pickup: Point, dropoff: Point) -> Detour:
        direct_m, direct_s = self.leg(origin, destination)
        to_pickup_m, to_pickup_s = self.leg(origin, pickup)
        shared_m, shared_s = self.leg(pickup, dropoff)
        to_end_m, to_end_s = self.leg(dropoff, destination)
        return Detour(
            detour_m=max(0, _round(to_pickup_m + shared_m + to_end_m - direct_m)),
            detour_s=max(0, _round(to_pickup_s + shared_s + to_end_s - direct_s)),
            pickup_offset_s=_round(to_pickup_s),
            shared_distance_m=_round(shared_m),
            shared_duration_s=_round(shared_s),
        )


def _round(value: float) -> int:
    """Arrondi au plus proche, demi vers le haut (valeurs positives)."""
    return math.floor(value + 0.5)
