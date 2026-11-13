"""Scénarios simulés (dossier de conception §6), générés avec une graine fixe.

S1 : matin en entreprise. Une entreprise de Bonanjo, 20 conducteurs et 50 passagers
    qui habitent les quartiers de Douala, arrivées entre 7 h et 8 h, mode autonome.
S3 : annulations. S1, puis 3 conducteurs qui ont des passagers annulent leur trajet
    (6 h 30, 6 h 35, 6 h 40) ; leurs passagers sont réaffectés automatiquement (US07).
S5 : mode manuel. S1 où chaque passager reçoit au plus trois propositions et en choisit
    une ; le choix humain est simulé de façon déterministe (US05).
Données entièrement simulées : aucune donnée personnelle réelle.
"""
from __future__ import annotations

import dataclasses
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
    seed: int = 42
    cancellations: list[datetime] = field(default_factory=list)   # heures d'annulation (S3)
    manual_choices: bool = False                                   # utilisateurs simulés (S5)

    def build(self, *, cfp_fanout: int = 5, validate: bool = False) -> Engine:
        """Moteur prêt à tourner : agents inscrits, demandes publiées dans l'ordre."""
        engine = Engine(cfp_fanout=cfp_fanout, validate=validate)
        for organization in self.organizations:
            engine.add_organization(organization)
        for profile in self.drivers:
            engine.add_driver(DriverAgent(profile, self.routing))
        engine.submit_many(self.requests)
        return engine

    async def play(self, engine: Engine) -> dict[str, list[float]]:
        """Joue le scénario jusqu'au bout ; renvoie la durée réelle de chaque phase, en secondes."""
        await engine.run()
        phases = {"negotiation_s": [engine.last_run_s], "user_choices_s": [], "reassignment_s": []}
        if self.manual_choices:
            for _ in range(10):   # un choix peut échouer (place prise) : l'utilisateur rechoisit
                waiting = [c for c in engine.conversations() if engine.passenger(c).conversation_id == c
                           and engine.passenger(c).state == "AWAITING_USER"]
                if not waiting:
                    break
                for conversation in waiting:
                    proposals = engine.passenger(conversation).proposals
                    # Choix simulé : rang tiré du numéro du passager (p017 -> rang 17 % nombre d'offres).
                    rank = int(engine.passenger(conversation).request.passenger_id[1:]) % len(proposals)
                    engine.choose(conversation, proposals[rank].offer_id)
                await engine.run()
                phases["user_choices_s"].append(engine.last_run_s)
        if self.cancellations:
            booked = sorted(d for d, agent in engine.bus.agents.items() if d.startswith("driver:") and agent.bookings)
            chosen = sorted(random.Random(self.seed).sample(booked, min(len(self.cancellations), len(booked))))
            for driver, at in zip(chosen, self.cancellations):
                engine.cancel_trip(driver.split(":", 1)[1], at)
                await engine.run()
                phases["reassignment_s"].append(engine.last_run_s)
        return phases


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


def s3_cancellations(seed: int = 42) -> Scenario:
    scenario = s1_company_morning(seed)
    day = datetime(2026, 11, 10, tzinfo=TZ)
    return dataclasses.replace(scenario, name="S3", cancellations=[_at(day, 6 * 60 + m) for m in (30, 35, 40)])


def s5_manual(seed: int = 42) -> Scenario:
    scenario = s1_company_morning(seed)
    requests = [(dataclasses.replace(request, mode="MANUAL"), at) for request, at in scenario.requests]
    return dataclasses.replace(scenario, name="S5", requests=requests, manual_choices=True)


SCENARIOS = {"S1": s1_company_morning, "S3": s3_cancellations, "S5": s5_manual}
