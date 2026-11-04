"""Squelette des agents MboaRide (protocole Contract Net).

Règle d'or : à scénario identique, résultat identique. Tout départage utilise
des règles fixes (prix, puis détour, puis identifiant), jamais l'aléatoire.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class RideRequest:
    passenger_id: str
    origin: str
    destination: str
    arrival_deadline: str  # "HH:MM"
    max_price: int         # FCFA
    circle: str = "company"


@dataclass(frozen=True)
class Offer:
    driver_id: str
    price: int
    detour_km: float


class DriverAgent:
    def __init__(self, driver_id: str, free_seats: int, min_price: int, max_detour_km: float):
        self.driver_id = driver_id
        self.free_seats = free_seats
        self.min_price = min_price
        self.max_detour_km = max_detour_km

    def propose(self, request: RideRequest, detour_km: float) -> Offer | None:
        """Retourne une offre si la demande est compatible, sinon None."""
        if self.free_seats <= 0 or detour_km > self.max_detour_km:
            return None
        if self.min_price > request.max_price:
            return None
        return Offer(self.driver_id, self.min_price, detour_km)


class PassengerAgent:
    def __init__(self, passenger_id: str, mode: str = "manual"):
        self.passenger_id = passenger_id
        self.mode = mode  # "manual" ou "autonomous"

    def rank(self, offers: list[Offer]) -> list[Offer]:
        """Classement déterministe : prix, puis détour, puis identifiant."""
        return sorted(offers, key=lambda o: (o.price, o.detour_km, o.driver_id))


class OrganizationAgent:
    """Fixe les règles d'un cercle (entreprise, école, campus, événement)."""

    def __init__(self, circle: str, price_cap: int | None = None):
        self.circle = circle
        self.price_cap = price_cap

    def allows(self, offer: Offer) -> bool:
        return self.price_cap is None or offer.price <= self.price_cap


class CoordinatorAgent:
    def __init__(self, drivers: list[DriverAgent], organization: OrganizationAgent):
        self.drivers = drivers
        self.organization = organization

    def collect_offers(self, request: RideRequest, detours: dict[str, float]) -> list[Offer]:
        offers = []
        for driver in self.drivers:
            offer = driver.propose(request, detours.get(driver.driver_id, float("inf")))
            if offer and self.organization.allows(offer):
                offers.append(offer)
        return offers
