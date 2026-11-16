"""Scénarios simulés (dossier de conception §6), générés avec une graine fixe.

S1 : matin en entreprise. Une entreprise de Bonanjo, 20 conducteurs et 50 passagers
    qui habitent les quartiers de Douala, arrivées entre 7 h et 8 h, mode autonome.
S2 : ville mixte. 80 conducteurs et 200 passagers : 3 entreprises (A et B partenaires),
    1 collège (élèves de 11 à 17 ans, dont deux de moins de 12 ans et un sans
    autorisation parentale) et le réseau public. Montée en charge et cercles.
S3 : annulations. S1, puis 3 conducteurs qui ont des passagers annulent leur trajet
    (6 h 30, 6 h 35, 6 h 40) ; leurs passagers sont réaffectés automatiquement (US07).
S4 : voyage interurbain. 10 conducteurs et 30 passagers de Douala vers Yaoundé, le vendredi
    après-midi, réservés à l'avance, péage compris, réseau public.
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
from .pricing import PricingPolicy
from .organization import OrganizationAgent
from .passenger import ArrivalWindow, PassengerRequest, Student
from .routing import EstimatedRouting, Point

# Centres approximatifs des quartiers (simulation).
QUARTERS = {
    "Kotto": Point(4.0711, 9.7590), "Logpom": Point(4.0790, 9.7740), "Makepe": Point(4.0760, 9.7480),
    "Bonamoussadi": Point(4.0920, 9.7400), "Logbessou": Point(4.0850, 9.7800), "Ndokoti": Point(4.0470, 9.7340),
    "Bepanda": Point(4.0600, 9.7200), "Deido": Point(4.0580, 9.7050), "Bonaberi": Point(4.0700, 9.6600),
}
BONANJO = Point(4.0440, 9.6935)
AKWA = Point(4.0510, 9.7000)
BONAPRISO = Point(4.0320, 9.6985)
BONABERI_ZI = Point(4.0780, 9.6650)
YAOUNDE = Point(3.8480, 11.5021)
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

    def build(self, *, cfp_fanout: int = 5, validate: bool = False,
              pricing: PricingPolicy | None = None) -> Engine:
        """Moteur prêt à tourner : agents inscrits, demandes publiées dans l'ordre.

        `pricing` permet de rejouer le même scénario avec une autre règle de partage
        des frais, ce dont se sert `scripts/comparer_regles_prix.py` (SR-51).
        """
        engine = Engine(cfp_fanout=cfp_fanout, validate=validate)
        for organization in self.organizations:
            engine.add_organization(organization)
        for profile in self.drivers:
            engine.add_driver(DriverAgent(profile, self.routing, pricing=pricing))
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


def _commuter(rng: random.Random, routing: EstimatedRouting, driver_id: str, destination: Point, arrival: datetime,
              *, trip_kind: str = "URBAN", tolls: int = 0, **profile) -> DriverProfile:
    """Conducteur qui part de chez lui (un quartier de Douala) pour arriver vers `arrival`."""
    home = _near(rng, QUARTERS[rng.choice(sorted(QUARTERS))], 0.006)
    _, direct_s = routing.leg(home, destination)
    departure = (arrival - timedelta(seconds=direct_s + rng.randrange(0, 301))).replace(second=0)
    defaults = dict(seats_total=rng.randint(2, 4), max_detour_m=rng.choice((2000, 2500, 3000, 3500, 4000)),
                    comfort=frozenset(c for c in COMFORTS if rng.random() < 0.5))
    trip = DriverTrip(f"t-{driver_id}", origin=home, destination=destination, departure_time=departure,
                      trip_kind=trip_kind, tolls=tolls)
    return DriverProfile(driver_id=driver_id, trip=trip, **{**defaults, **profile})


def s2_city_mix(seed: int = 42) -> Scenario:
    rng = random.Random(seed)
    routing = EstimatedRouting()
    day = datetime(2026, 11, 10, tzinfo=TZ)
    companies = {"entreprise-a": BONANJO, "entreprise-b": AKWA, "entreprise-c": BONABERI_ZI}
    partners = {"entreprise-a": ["organization:entreprise-b"], "entreprise-b": ["organization:entreprise-a"],
                "entreprise-c": []}
    districts = (BONANJO, AKWA, BONAPRISO)
    all_circles = frozenset({"ORGANIZATION", "PARTNERS", "PUBLIC"})

    drivers: list[DriverProfile] = []

    def add_driver(destination: Point, arrival_from: int, arrival_to: int, **profile) -> None:
        driver_id = f"d{len(drivers) + 1:02d}"
        arrival = _at(day, arrival_from + rng.randrange(0, arrival_to - arrival_from + 1))
        drivers.append(_commuter(rng, routing, driver_id, _near(rng, destination, 0.002), arrival, **profile))

    for org, office in companies.items():   # 20 + 20 + 15 salariés conducteurs
        for _ in range(15 if org == "entreprise-c" else 20):
            add_driver(office, 7 * 60 + 5, 7 * 60 + 55, organization_id=f"organization:{org}",
                       accepted_circles=all_circles, accepts_students=rng.random() < 0.4)
    for _ in range(5):                      # parents et enseignants qui vont au collège
        add_driver(BONAPRISO, 6 * 60 + 55, 7 * 60 + 20, organization_id="organization:college-bonapriso",
                   accepted_circles=frozenset({"ORGANIZATION", "PUBLIC"}), accepts_students=True)
    for _ in range(20):                     # réseau public : conducteurs agréés sans organisation
        add_driver(rng.choice(districts), 7 * 60 + 5, 7 * 60 + 55, accepted_circles=frozenset({"PUBLIC"}),
                   accepts_students=rng.random() < 0.3)

    requests: list[tuple[PassengerRequest, datetime]] = []
    members: dict[str, list[str]] = {org: [] for org in [*companies, "college-bonapriso"]}

    def add_request(destination: Point, target_from: int, target_to: int, organization: str | None,
                    circles: tuple[str, ...], max_prices: tuple[int, ...], passenger_id: str | None = None,
                    **request) -> None:
        passenger_id = passenger_id or f"p{len(requests) + 1:03d}"
        if organization:
            members[organization].append(f"passenger:{passenger_id}")
        target = _at(day, target_from + rng.randrange(0, target_to - target_from + 1, 5))
        requests.append((PassengerRequest(
            passenger_id=passenger_id,
            origin=_near(rng, QUARTERS[rng.choice(sorted(QUARTERS))], 0.006),
            destination=_near(rng, destination, 0.002),
            arrival_window=ArrivalWindow(target - timedelta(minutes=10), target, target + timedelta(minutes=10)),
            max_price=rng.choice(max_prices),
            circles=circles,
            organization_id=f"organization:{organization}" if organization else None,
            comfort_required=frozenset({"NON_SMOKING"}) if rng.random() < 0.1 else frozenset(),
            comfort_preferred=frozenset(c for c in COMFORTS if rng.random() < 0.3),
            **request,
        ), _at(day, 6 * 60 + rng.randrange(0, 31))))

    for org, office in companies.items():   # 45 + 45 + 30 salariés passagers
        for _ in range(30 if org == "entreprise-c" else 45):
            add_request(office, 7 * 60, 8 * 60, org, ("ORGANIZATION", "PARTNERS", "PUBLIC"), (200, 250, 300, 350, 400))
    for i in range(30):                     # élèves : deux de moins de 12 ans, un sans autorisation parentale
        age = 11 if i < 2 else rng.randint(12, 17)
        add_request(BONAPRISO, 6 * 60 + 50, 7 * 60 + 20, "college-bonapriso", ("ORGANIZATION", "PUBLIC"),
                    (200, 250, 300), passenger_id=f"e{i + 1:03d}", passenger_kind="STUDENT",
                    student=Student(age=age, parent_consent=i != 2))
    for _ in range(50):                     # réseau public
        add_request(rng.choice(districts), 7 * 60, 8 * 60, None, ("PUBLIC",), (250, 300, 350, 400, 500))

    organizations = [OrganizationAgent(org, members=members[org], partners=partners[org]) for org in companies]
    organizations.append(OrganizationAgent("college-bonapriso", members=members["college-bonapriso"], price_cap=250))
    return Scenario(name="S2", organizations=organizations, drivers=drivers, requests=requests, routing=routing)


def s4_interurban(seed: int = 42) -> Scenario:
    rng = random.Random(seed)
    # Douala-Yaoundé : environ 200 km à vol d'oiseau pour 240 km de route, d'où un facteur 1,2.
    routing = EstimatedRouting(speed_kmh=60, road_factor=1.2)
    friday = datetime(2026, 11, 13, tzinfo=TZ)
    drivers = [
        _commuter(rng, routing, f"d{i:02d}", _near(rng, YAOUNDE, 0.01), _at(friday, 17 * 60 + rng.randrange(0, 181, 15)),
                  trip_kind="INTERURBAN", tolls=1000, max_detour_m=rng.choice((5000, 6000, 8000)),
                  accepted_circles=frozenset({"PUBLIC"}))
        for i in range(1, 11)
    ]
    requests = []
    for i in range(1, 31):
        target = _at(friday, 17 * 60 + rng.randrange(0, 181, 30))
        requests.append((PassengerRequest(
            passenger_id=f"v{i:03d}",
            origin=_near(rng, QUARTERS[rng.choice(sorted(QUARTERS))], 0.006),
            destination=_near(rng, YAOUNDE, 0.01),
            arrival_window=ArrivalWindow(target - timedelta(minutes=45), target, target + timedelta(minutes=45)),
            max_price=rng.choice((3500, 4000, 4500, 5000, 6000)),
            circles=("PUBLIC",),
            trip_kind="INTERURBAN",
            comfort_preferred=frozenset(c for c in COMFORTS if rng.random() < 0.3),
        ), _at(datetime(2026, 11, 11, tzinfo=TZ), 18 * 60 + rng.randrange(0, 24 * 60))))
    return Scenario(name="S4", drivers=drivers, requests=requests, routing=routing)


SCENARIOS = {"S1": s1_company_morning, "S2": s2_city_mix, "S3": s3_cancellations, "S4": s4_interurban,
             "S5": s5_manual}
