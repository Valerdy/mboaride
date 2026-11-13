"""Agent coordinateur : diffuse les demandes, élargit les cercles, confirme les équipages.

Voir docs/architecture-multi-agents.md, sections 2 à 5.
- Diffusion : pour chaque tour, il présélectionne au plus K conducteurs (`cfp_fanout`)
  avec des tests bon marché, sans itinéraire, et leur envoie l'appel d'offres (CFP),
  après avoir annoncé au passager qui a été sollicité (REQUEST_AGREED).
- Élargissement : il parcourt les cercles acceptés par le passager, du plus proche au
  plus large (ORGANIZATION, PARTNERS, PUBLIC). Un cercle sans conducteur présélectionné
  est sauté sans message. Plus aucun cercle : NO_CREW.
- Arbitrage : les conflits (deux passagers pour une place) sont réglés par l'ordre du
  bus, côté conducteur ; le coordinateur met à jour les places restantes à chaque
  confirmation.
- Déterminisme : conducteurs parcourus et triés par identifiant, départage de la
  présélection par écart estimé puis identifiant, aucune horloge ni aléa.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from . import messages
from .messages import COORDINATOR
from .routing import EstimatedRouting, Point, haversine_m

DEFAULT_CFP_FANOUT = 5
# Estimateurs locaux (sans OSRM) pour la présélection : vitesse moyenne selon le type de trajet.
DEFAULT_ESTIMATORS = {"URBAN": EstimatedRouting(speed_kmh=20), "INTERURBAN": EstimatedRouting(speed_kmh=60)}
# Marge sur l'heure de dépose estimée : l'estimation diffère de l'itinéraire réel (OSRM).
DEFAULT_TIME_TOLERANCE = timedelta(minutes=15)

OPEN, CONFIRMED, NO_CREW, WITHDRAWN = "OPEN", "CONFIRMED", "NO_CREW", "WITHDRAWN"


@dataclass
class DriverListing:
    """Ce que le coordinateur sait d'un conducteur actif (copie de la base de l'API)."""

    agent_id: str
    organization_id: str | None
    accepted_circles: frozenset[str]
    accepts_students: bool
    approved: bool
    comfort: frozenset[str]
    origin: Point
    destination: Point
    departure_time: datetime
    trip_kind: str
    max_detour_m: int
    seats_free: int

    @classmethod
    def from_agent(cls, driver) -> DriverListing:
        p = driver.profile
        return cls(agent_id=driver.agent_id, organization_id=p.organization_id,
                   accepted_circles=frozenset(p.accepted_circles), accepts_students=p.accepts_students,
                   approved=p.approved, comfort=frozenset(p.comfort), origin=p.trip.origin, destination=p.trip.destination,
                   departure_time=p.trip.departure_time, trip_kind=p.trip.trip_kind,
                   max_detour_m=p.max_detour_m, seats_free=driver.seats_free)


@dataclass
class Conversation:
    """État d'une demande de trajet suivie par le coordinateur."""

    passenger: str
    request: dict[str, Any]                  # corps du RIDE_REQUEST
    status: str = OPEN
    round: int = 0
    next_circle: int = 0                     # indice du prochain cercle à essayer
    max_price: int = 0                       # prix maximal effectif (plafond de l'organisation compris)
    partners: frozenset[str] = frozenset()
    solicited: set[str] = field(default_factory=set)


class CoordinatorAgent:
    def __init__(self, cfp_fanout: int = DEFAULT_CFP_FANOUT, *,
                 estimators: dict[str, EstimatedRouting] | None = None,
                 time_tolerance: timedelta = DEFAULT_TIME_TOLERANCE):
        if cfp_fanout < 1:
            raise ValueError("cfp_fanout doit être >= 1")
        self.cfp_fanout = cfp_fanout
        self.estimators = estimators or DEFAULT_ESTIMATORS
        self.time_tolerance = time_tolerance
        self.drivers: dict[str, DriverListing] = {}
        self.conversations: dict[str, Conversation] = {}

    agent_id = COORDINATOR

    def register_driver(self, listing: DriverListing) -> None:
        if listing.agent_id in self.drivers:
            raise ValueError(f"{listing.agent_id} est déjà inscrit")
        self.drivers[listing.agent_id] = listing

    async def handle(self, message: messages.Message) -> list[messages.Message]:
        if message["receiver"] != COORDINATOR:
            raise ValueError(f"Le coordinateur a reçu un message destiné à {message['receiver']}")
        handler = {
            "RIDE_REQUEST": self._on_request,
            "CIRCLE_ANSWER": self._on_circle_answer,
            "NO_ACCEPTABLE_OFFER": self._on_no_acceptable_offer,
            "BOOKING_CONFIRMED": self._on_booking_confirmed,
            "REQUEST_WITHDRAWN": self._on_withdrawn,
        }.get(message["type"])
        if handler is None:
            raise ValueError(f"Le coordinateur ne traite pas encore les messages {message['type']}")
        return handler(message)

    # --- Messages reçus ------------------------------------------------------------------

    def _on_request(self, message: messages.Message) -> list[messages.Message]:
        conversation_id = message["conversation_id"]
        if conversation_id in self.conversations:
            raise ValueError(f"La conversation {conversation_id} existe déjà")
        body = message["body"]
        conv = Conversation(passenger=message["sender"], request=body, max_price=body["max_price"])
        self.conversations[conversation_id] = conv
        organization = body["organization_id"]
        if organization is None:
            return self._next_round(conv, message)
        query = {"passenger": conv.passenger, "passenger_kind": body["passenger_kind"]}
        if "student" in body:
            query["student"] = body["student"]
        return [messages.reply(message, "CIRCLE_QUERY", sender=COORDINATOR, receiver=organization, body=query)]

    def _on_circle_answer(self, message: messages.Message) -> list[messages.Message]:
        conv = self._open(message)
        answer = message["body"]
        if not answer["authorized"]:
            return [self._no_crew(conv, message, reason="REFUSED_BY_ORGANIZATION",
                                  organization_reason=answer["reason"], suggestion=None)]
        if answer["price_cap"] is not None:
            conv.max_price = min(conv.max_price, answer["price_cap"])
        conv.partners = frozenset(answer["partner_organizations"])
        return self._next_round(conv, message)

    def _on_no_acceptable_offer(self, message: messages.Message) -> list[messages.Message]:
        conv = self._open(message)
        if message["body"]["round"] != conv.round:
            raise ValueError(f"Fin du tour {message['body']['round']} reçue pendant le tour {conv.round}")
        return self._next_round(conv, message)

    def _on_booking_confirmed(self, message: messages.Message) -> list[messages.Message]:
        conv = self._open(message)
        body = message["body"]
        if body["passenger"] != conv.passenger:
            raise ValueError("Réservation confirmée pour un autre passager que celui de la conversation")
        self.drivers[message["sender"]].seats_free = body["seats_left"]
        conv.status = CONFIRMED
        crew = {
            "booking_id": body["booking_id"],
            "driver": message["sender"],
            "offer_id": body["offer_id"],
            "pickup_point": body.get("pickup_point", conv.request["origin"]),
            "pickup_time": body["pickup_time"],
            "dropoff_time": body["dropoff_time"],
            "price": body["price"],
            "rounds": conv.round,
        }
        return [messages.reply(message, "CREW_CONFIRMED", sender=COORDINATOR, receiver=conv.passenger, body=crew)]

    def _on_withdrawn(self, message: messages.Message) -> list[messages.Message]:
        self._open(message).status = WITHDRAWN
        return []

    # --- Tours d'appel d'offres -----------------------------------------------------------

    def _next_round(self, conv: Conversation, trigger: messages.Message) -> list[messages.Message]:
        """Ouvre le tour suivant dans le premier cercle qui a des conducteurs, ou conclut NO_CREW."""
        circles = conv.request["circles"]
        while conv.next_circle < len(circles):
            circle = circles[conv.next_circle]
            conv.next_circle += 1
            drivers = self.preselect(conv, circle)
            if not drivers:
                continue
            conv.round += 1
            conv.solicited.update(drivers)
            agreed = messages.reply(trigger, "REQUEST_AGREED", sender=COORDINATOR, receiver=conv.passenger, body={
                "round": conv.round, "circle": circle, "cfp_sent_to": drivers, "expected_replies": len(drivers)})
            cfp_body = self._cfp_body(conv, circle)
            cfps = [messages.reply(trigger, "CFP", sender=COORDINATOR, receiver=d, body=cfp_body) for d in drivers]
            return [agreed, *cfps]
        suggestion = "WIDEN_CIRCLES" if len(circles) < 3 else "WIDEN_WINDOW"
        return [self._no_crew(conv, trigger, reason="NO_DRIVER_FOUND", organization_reason=None, suggestion=suggestion)]

    def preselect(self, conv: Conversation, circle: str) -> list[str]:
        """Au plus K conducteurs, triés par écart estimé croissant puis par identifiant."""
        req = conv.request
        pickup, dropoff = Point.from_json(req["origin"]), Point.from_json(req["destination"])
        window = req["arrival_window"]
        earliest, latest = datetime.fromisoformat(window["earliest"]), datetime.fromisoformat(window["latest"])
        excluded = set(req["exclude_drivers"]) | conv.solicited
        required_comfort = set(req["comfort"]["required"])
        candidates = []
        for agent_id in sorted(self.drivers):
            d = self.drivers[agent_id]
            if agent_id in excluded or not d.approved or d.seats_free < req["seats"]:
                continue
            if circle not in d.accepted_circles or not self._in_circle(d, conv, circle):
                continue
            if req["passenger_kind"] == "STUDENT" and not d.accepts_students:
                continue
            if d.trip_kind != req["trip_kind"] or not required_comfort <= d.comfort:
                continue
            # Heure de dépose estimée : départ + trajet jusqu'au passager + trajet partagé.
            estimator = self.estimators[d.trip_kind]
            dropoff_at = d.departure_time + timedelta(
                seconds=estimator.leg(d.origin, pickup)[1] + estimator.leg(pickup, dropoff)[1])
            if not earliest - self.time_tolerance <= dropoff_at <= latest + self.time_tolerance:
                continue
            # Détour à vol d'oiseau : borne optimiste, sans appel d'itinéraire.
            estimate = (haversine_m(d.origin, pickup) + haversine_m(pickup, dropoff)
                        + haversine_m(dropoff, d.destination) - haversine_m(d.origin, d.destination))
            if estimate > d.max_detour_m:
                continue
            candidates.append((round(estimate), agent_id))
        return [agent_id for _, agent_id in sorted(candidates)[:self.cfp_fanout]]

    def _in_circle(self, driver: DriverListing, conv: Conversation, circle: str) -> bool:
        if circle == "ORGANIZATION":
            return driver.organization_id is not None and driver.organization_id == conv.request["organization_id"]
        if circle == "PARTNERS":
            return driver.organization_id in conv.partners
        return True  # PUBLIC : tout conducteur agréé qui accepte ce cercle

    def _cfp_body(self, conv: Conversation, circle: str) -> dict[str, Any]:
        req = conv.request
        return {
            "round": conv.round,
            "circle": circle,
            "reply_to": conv.passenger,
            "passenger_kind": req["passenger_kind"],
            "origin": req["origin"],
            "destination": req["destination"],
            "trip_kind": req["trip_kind"],
            "arrival_window": req["arrival_window"],
            "max_price": conv.max_price,
            "seats": req["seats"],
            "comfort_required": req["comfort"]["required"],
        }

    # --- Outils ------------------------------------------------------------------------------

    def _no_crew(self, conv: Conversation, trigger: messages.Message, *, reason: str,
                 organization_reason: str | None, suggestion: str | None) -> messages.Message:
        conv.status = NO_CREW
        return messages.reply(trigger, "NO_CREW", sender=COORDINATOR, receiver=conv.passenger, body={
            "rounds_tried": conv.round, "reason": reason, "organization_reason": organization_reason,
            "suggestion": suggestion})

    def _open(self, message: messages.Message) -> Conversation:
        conv = self.conversations.get(message["conversation_id"])
        if conv is None:
            raise ValueError(f"Conversation inconnue : {message['conversation_id']}")
        if conv.status != OPEN:
            raise ValueError(f"La conversation {message['conversation_id']} est close ({conv.status})")
        return conv
