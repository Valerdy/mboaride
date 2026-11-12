"""Scénarios simulés (dossier de conception §6), générés avec une graine fixe.

S1 : matin en entreprise. Une entreprise de Bonanjo, 20 conducteurs et 50 passagers
qui habitent les quartiers de Douala, arrivées entre 7 h et 8 h, mode autonome.
Données entièrement simulées : aucune donnée personnelle réelle.
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from .driver import DriverAgent, DriverProfile, DriverTrip
from .engine import Engine
from .organization import OrganizationAgent
from .passenger import ArrivalWindow, PassengerRequest
from .routing import EstimatedRouting, Point

# Centres approximatifs des quartiers (simulation).
QUARTERS = {
    "Kotto": Point(4.0711, 9.7590), "Logpom": Point(4.0790, 9.7740), "Makepe": Point(4.0760, 9.7480),
    "Bonamoussadi": Point(4.0920, 9.7400), "Logbessou": Point(4.0850, 9.7800), "Ndokoti": Point(4.0470, 9.7340),
    "Bepanda": Point(4.0600, 9.7200), "Deido": Point(4.0580, 9.7050), "Bonaberi": Point(4.0700, 9.6600),
}
BONANJO = Point(4.0440, 9.6935)
COMFORTS = ("AIR_CONDITIONING", "NON_SMOKING", "QUIET")
TZ = datetime.fromisoformat("2026-11-10T00:00:00+01:00").tzinfo


@dataclass
class Scenario:
    name: str
    organizations: list[OrganizationAgent] = field(default_factory=list)
    drivers: list[DriverProfile] = field(default_factory=list)
    requests: list[tuple[PassengerRequest, datetime]] = field(default_factory=list)
    routing: EstimatedRouting = field(default_factory=EstimatedRouting)

    def build(self, *, cfp_fanout: int = 5, validate: bool = False) -> Engine:
        """Moteur prêt à tourner : agents inscrits, demandes publiées dans l'ordre."""
        engine = Engine(cfp_fanout=cfp_fanout, validate=validate)
        for organization in self.organizations:
            engine.add_organization(organization)
        for profile in self.drivers:
            engine.add_driver(DriverAgent(profile, self.routing))
        engine.submit_many(self.requests)
        return engine


def _near(rng: random.Random, center: Point, spread: float) -> Point:
    return Point(round(center.lat + rng.uniform(-spread, spread), 5), round(center.lng + rng.uniform(-spread, spread), 5))


def _at(day: datetime, minutes: int) -> datetime:
    return day + timedelta(minutes=minutes)


def s1_company_morning(seed: int = 42, n_drivers: int = 20, n_passengers: int = 50) -> Scenario:
    rng = random.Random(seed)
    routing = EstimatedRouting()
    day = datetime(2026, 11, 10, tzinfo=TZ)
    org = "organization:entreprise-s1"
    quarters = sorted(QUARTERS)

    drivers = []
    for i in range(1, n_drivers + 1):
        home = _near(rng, QUARTERS[rng.choice(quarters)], 0.006)
        office = _near(rng, BONANJO, 0.002)
        _, direct_s = routing.leg(home, office)
        arrival = _at(day, 7 * 60 + rng.randrange(5, 56))
        departure = (arrival - timedelta(seconds=direct_s + rng.randrange(0, 301))).replace(second=0)
        drivers.append(DriverProfile(
            driver_id=f"d{i:02d}",
            trip=DriverTrip(f"t-d{i:02d}", origin=home, destination=office, departure_time=departure),
            seats_total=rng.randint(2, 4),
            max_detour_m=rng.choice((2000, 2500, 3000, 3500, 4000)),
            comfort=frozenset(c for c in COMFORTS if rng.random() < 0.5),
            organization_id=org,
        ))

    requests, members = [], []
    for i in range(1, n_passengers + 1):
        passenger_id = f"p{i:03d}"
        members.append(f"passenger:{passenger_id}")
        target = _at(day, 7 * 60 + rng.randrange(0, 61, 5))
        window = ArrivalWindow(target - timedelta(minutes=10), target, target + timedelta(minutes=10))
        requests.append((PassengerRequest(
            passenger_id=passenger_id,
            origin=_near(rng, QUARTERS[rng.choice(quarters)], 0.006),
            destination=_near(rng, BONANJO, 0.002),
            arrival_window=window,
            max_price=rng.choice((200, 250, 300, 350, 400)),
            circles=("ORGANIZATION", "PARTNERS", "PUBLIC"),
            organization_id=org,
            comfort_required=frozenset({"NON_SMOKING"}) if rng.random() < 0.1 else frozenset(),
            comfort_preferred=frozenset(c for c in COMFORTS if rng.random() < 0.3),
        ), _at(day, 6 * 60 + rng.randrange(0, 31))))

    return Scenario(name="S1", organizations=[OrganizationAgent("entreprise-s1", members=members)],
                    drivers=drivers, requests=requests, routing=routing)
