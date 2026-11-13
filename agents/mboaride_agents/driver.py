"""Agent conducteur : répond à un appel d'offres (CFP) par une offre ou un refus.

Voir docs/architecture-multi-agents.md, sections 2 (filtres) et 4 (protocole).
L'agent répond toujours, une seule fois par appel d'offres : PROPOSAL si tous les
filtres passent, sinon DECLINE avec le motif du premier filtre qui échoue. Les
filtres sont testés du moins coûteux au plus coûteux ; l'itinéraire n'est calculé
que si les filtres sans itinéraire passent.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from . import messages
from .messages import COMFORTS, TRIP_KINDS
from .pricing import PricingPolicy, quote
from .routing import NoRouteError, Point, RoutingService

CIRCLES = frozenset(messages.CIRCLES)


@dataclass(frozen=True)
class DriverTrip:
    """Trajet que le conducteur fait de toute façon."""

    trip_id: str
    origin: Point
    destination: Point
    departure_time: datetime   # avec fuseau horaire
    trip_kind: str = "URBAN"
    tolls: int = 0             # péages du trajet, en FCFA (interurbain)

    def __post_init__(self):
        if self.departure_time.tzinfo is None:
            raise ValueError("departure_time doit porter un fuseau horaire")
        if self.trip_kind not in TRIP_KINDS:
            raise ValueError(f"trip_kind inconnu : {self.trip_kind}")
        if self.tolls < 0:
            raise ValueError("tolls doit être positif ou nul")


@dataclass(frozen=True)
class DriverProfile:
    """Exigences du conducteur, telles qu'il les a déclarées."""

    driver_id: str
    trip: DriverTrip
    seats_total: int                    # places offertes aux passagers
    max_detour_m: int                   # détour maximal accepté
    min_price: int = 0                  # prix plancher par passager, en FCFA
    comfort: frozenset[str] = field(default_factory=frozenset)       # confort offert
    accepted_circles: frozenset[str] = CIRCLES
    accepts_students: bool = True
    approved: bool = True               # agrément MboaRide (pièces vérifiées)
    consumption_l_per_100km: float = 8.0
    organization_id: str | None = None  # "organization:<id>" : cercle ORGANIZATION du conducteur

    def __post_init__(self):
        if self.organization_id is not None and not self.organization_id.startswith("organization:"):
            raise ValueError("organization_id doit être de la forme organization:<id>")
        if not 1 <= self.seats_total <= 8:
            raise ValueError("seats_total doit être entre 1 et 8")
        if self.max_detour_m < 1:
            raise ValueError("max_detour_m doit être >= 1")
        if self.min_price < 0:
            raise ValueError("min_price doit être positif ou nul")
        if self.consumption_l_per_100km <= 0:
            raise ValueError("consumption_l_per_100km doit être > 0")
        if not set(self.comfort) <= COMFORTS:
            raise ValueError(f"Critère de confort inconnu : {sorted(set(self.comfort) - COMFORTS)}")
        if not set(self.accepted_circles) <= CIRCLES:
            raise ValueError(f"Cercle inconnu : {sorted(set(self.accepted_circles) - CIRCLES)}")


class DriverAgent:
    def __init__(self, profile: DriverProfile, routing: RoutingService,
                 pricing: PricingPolicy | None = None, seats_booked: int = 0):
        if not 0 <= seats_booked <= profile.seats_total:
            raise ValueError("seats_booked doit être entre 0 et seats_total")
        self.profile = profile
        self.routing = routing
        self.pricing = pricing or PricingPolicy()
        self.seats_booked = seats_booked
        # Offres en cours, non engageantes : offer_id -> passager, places demandées, corps de l'offre.
        self.offers: dict[str, dict[str, Any]] = {}
        # Réservations confirmées : booking_id -> détails.
        self.bookings: dict[str, dict[str, Any]] = {}
        self.cancelled = False   # trajet annulé par le conducteur

    @property
    def agent_id(self) -> str:
        return messages.agent_id("driver", self.profile.driver_id)

    @property
    def seats_free(self) -> int:
        return self.profile.seats_total - self.seats_booked

    async def handle(self, message: messages.Message) -> list[messages.Message]:
        """Traite un message reçu du bus et renvoie les brouillons à envoyer."""
        if message["receiver"] != self.agent_id:
            raise ValueError(f"{self.agent_id} a reçu un message destiné à {message['receiver']}")
        if message["type"] == "CFP":
            return [await self.on_cfp(message)]
        if message["type"] == "ACCEPT":
            return [self.on_accept(message)]
        raise ValueError(f"L'agent conducteur ne traite pas encore les messages {message['type']}")

    def cancel_trip(self, reason: str = "DRIVER_CANCELLED") -> messages.Message:
        """Le conducteur annule son trajet : brouillon TRIP_CANCELLED pour le coordinateur (US07).

        Le coordinateur prévient chaque passager réservé, dont l'agent relance aussitôt
        une négociation sans ce conducteur. Les offres en cours sont retirées.
        """
        if self.cancelled:
            raise ValueError(f"Le trajet de {self.agent_id} est déjà annulé")
        self.cancelled = True
        self.offers.clear()
        return messages.draft("TRIP_CANCELLED", sender=self.agent_id, receiver=messages.COORDINATOR,
                              conversation_id=self.profile.trip.trip_id, in_reply_to=None,
                              body={"trip_id": self.profile.trip.trip_id, "bookings": sorted(self.bookings),
                                    "reason": reason})

    async def on_cfp(self, cfp: messages.Message) -> messages.Message:
        body = cfp["body"]
        if self.cancelled:   # appel d'offres croisé avec l'annulation : plus aucune place à offrir
            return messages.reply(cfp, "DECLINE", sender=self.agent_id, receiver=body["reply_to"],
                                  body={"round": body["round"], "reason": "NO_SEAT"})
        reason, offer = await self._evaluate(cfp["conversation_id"], body)
        if reason:
            return messages.reply(cfp, "DECLINE", sender=self.agent_id, receiver=body["reply_to"],
                                  body={"round": body["round"], "reason": reason})
        self.offers[offer["offer_id"]] = {"passenger": body["reply_to"], "seats": body["seats"], "offer": offer}
        return messages.reply(cfp, "PROPOSAL", sender=self.agent_id, receiver=body["reply_to"], body=offer)

    def on_accept(self, accept: messages.Message) -> messages.Message:
        """Acceptation d'une offre : réserve la place si elle est encore libre.

        Les offres n'engagent pas le conducteur : si plusieurs passagers acceptent la
        dernière place, le premier traité par le bus l'obtient, les suivants reçoivent
        BOOKING_FAILED (SEAT_TAKEN) et passent à leur offre suivante.
        """
        offer_id = accept["body"]["offer_id"]
        if self.cancelled:
            return self._booking_failed(accept, offer_id, "TRIP_CANCELLED")
        pending = self.offers.get(offer_id)
        if pending is None or pending["passenger"] != accept["sender"]:
            return self._booking_failed(accept, offer_id, "OFFER_UNKNOWN")
        if pending["seats"] > self.seats_free:
            del self.offers[offer_id]
            return self._booking_failed(accept, offer_id, "SEAT_TAKEN")

        del self.offers[offer_id]
        self.seats_booked += pending["seats"]
        booking_id = f"b-{self.profile.driver_id}-{len(self.bookings) + 1}"
        offer = pending["offer"]
        self.bookings[booking_id] = {"passenger": pending["passenger"], "seats": pending["seats"],
                                     "conversation_id": accept["conversation_id"], "offer": offer}
        return messages.reply(accept, "BOOKING_CONFIRMED", sender=self.agent_id, receiver=messages.COORDINATOR, body={
            "booking_id": booking_id,
            "offer_id": offer_id,
            "passenger": pending["passenger"],
            "price": offer["price"],
            "pickup_point": offer["pickup_point"],
            "pickup_time": offer["pickup_time"],
            "dropoff_time": offer["dropoff_time"],
            "seats_left": self.seats_free,
        })

    def _booking_failed(self, accept: messages.Message, offer_id: str, reason: str) -> messages.Message:
        return messages.reply(accept, "BOOKING_FAILED", sender=self.agent_id, receiver=accept["sender"],
                              body={"offer_id": offer_id, "reason": reason})

    async def _evaluate(self, conversation_id: str, cfp: dict[str, Any]) -> tuple[str | None, dict | None]:
        """(motif de refus, None) ou (None, corps de l'offre)."""
        p = self.profile

        # 1. Filtres sans itinéraire, du moins coûteux au plus coûteux.
        if not p.approved:
            return "DRIVER_NOT_APPROVED", None
        if cfp["circle"] not in p.accepted_circles:
            return "CIRCLE_NOT_ACCEPTED", None
        if cfp["passenger_kind"] == "STUDENT" and not p.accepts_students:
            return "STUDENT_NOT_ALLOWED", None
        if cfp["seats"] > self.seats_free:
            return "NO_SEAT", None
        if not set(cfp["comfort_required"]) <= p.comfort:
            return "COMFORT_MISMATCH", None

        # 2. Itinéraire : détour imposé par la prise en charge du passager.
        pickup, dropoff = Point.from_json(cfp["origin"]), Point.from_json(cfp["destination"])
        try:
            detour = await self.routing.detour(p.trip.origin, p.trip.destination, pickup, dropoff)
        except NoRouteError:
            return "NO_ROUTE", None
        if detour.detour_m > p.max_detour_m:
            return "DETOUR_TOO_LONG", None

        # 3. Horaire : le passager doit arriver dans sa fenêtre.
        pickup_time = p.trip.departure_time + timedelta(seconds=detour.pickup_offset_s)
        dropoff_time = pickup_time + timedelta(seconds=detour.shared_duration_s)
        window = cfp["arrival_window"]
        if not datetime.fromisoformat(window["earliest"]) <= dropoff_time <= datetime.fromisoformat(window["latest"]):
            return "OUTSIDE_WINDOW", None

        # 4. Prix.
        q = quote(
            self.pricing,
            shared_distance_m=detour.shared_distance_m,
            consumption_l_per_100km=p.consumption_l_per_100km,
            tolls=p.trip.tolls if p.trip.trip_kind == "INTERURBAN" else 0,
            seats_total=p.seats_total,
            seats_booked=self.seats_booked,
            seats_requested=cfp["seats"],
            min_price=p.min_price,
            with_commission=cfp["circle"] == "PUBLIC" or p.trip.trip_kind == "INTERURBAN",
        )
        if q.price > cfp["max_price"]:
            return "PRICE_TOO_HIGH", None

        offer_id = f"o-{p.driver_id}-{conversation_id}"
        if cfp["round"] > 1:
            offer_id += f"-{cfp['round']}"
        return None, {
            "offer_id": offer_id,
            "round": cfp["round"],
            "circle": cfp["circle"],
            "departure_time": _iso(p.trip.departure_time),
            "pickup_point": pickup.to_json(),
            "pickup_time": _iso(pickup_time),
            "dropoff_time": _iso(dropoff_time),
            "detour_m": detour.detour_m,
            "detour_s": detour.detour_s,
            "max_detour_m": p.max_detour_m,
            "shared_distance_m": detour.shared_distance_m,
            "price": q.price,
            "price_breakdown": q.breakdown(),
            "comfort_offered": sorted(p.comfort),
        }


def _iso(moment: datetime) -> str:
    return moment.isoformat(timespec="seconds")
