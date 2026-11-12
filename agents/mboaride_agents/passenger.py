"""Agent passager : publie la demande, classe les offres reçues selon ses exigences, puis décide.

Voir docs/architecture-multi-agents.md, sections 4 (protocole et score) et 5.
- Il revérifie les contraintes dures de chaque offre (prix max, fenêtre d'arrivée,
  confort obligatoire, cercle accepté, détour) : il ne fait pas confiance aveuglément.
- Il classe les offres restantes par score, en fractions exactes, puis départage par
  le plus petit détour, le départ le plus tôt et le plus petit identifiant de conducteur.
- Mode autonome : il accepte la meilleure offre. Mode manuel : il présente les trois
  meilleures à l'utilisateur, qui choisit, demande d'élargir ou abandonne.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from fractions import Fraction
from typing import Any

from . import messages
from .messages import CIRCLES, COMFORTS, COORDINATOR, TRIP_KINDS
from .routing import Point

MODES = frozenset({"AUTONOMOUS", "MANUAL"})
PASSENGER_KINDS = frozenset({"ADULT", "STUDENT"})
CIRCLE_PROXIMITY = {"ORGANIZATION": Fraction(1), "PARTNERS": Fraction(1, 2), "PUBLIC": Fraction(0)}
MANUAL_CHOICES = 3

# États de l'agent (cycle de vie d'une demande, architecture §5.7).
NEW = "NEW"                        # demande pas encore envoyée
SUBMITTED = "SUBMITTED"            # en attente d'un accord du coordinateur (ou d'un échec)
CALLING = "CALLING"                # appel d'offres en cours, réponses attendues
AWAITING_USER = "AWAITING_USER"    # mode manuel : trois offres présentées à l'utilisateur
ACCEPTING = "ACCEPTING"            # acceptation envoyée, confirmation attendue
CONFIRMED = "CONFIRMED"            # équipage confirmé
NO_CREW = "NO_CREW"                # aucun équipage trouvé
WITHDRAWN = "WITHDRAWN"            # demande retirée par l'utilisateur


def _aware(moment: datetime, name: str) -> None:
    if moment.tzinfo is None:
        raise ValueError(f"{name} doit porter un fuseau horaire")


def _iso(moment: datetime) -> str:
    return moment.isoformat(timespec="seconds")


@dataclass(frozen=True)
class ScoreWeights:
    """Poids du score ; leur somme vaut exactement 1 (dossier de conception §5)."""

    detour: float = 0.30
    time: float = 0.25
    price: float = 0.25
    comfort: float = 0.10
    circle: float = 0.10

    def __post_init__(self):
        values = self.fractions()
        if any(not 0 <= v <= 1 for v in values):
            raise ValueError("Chaque poids doit être entre 0 et 1")
        if sum(values) != 1:
            raise ValueError(f"La somme des poids doit valoir 1, pas {float(sum(values))}")

    def fractions(self) -> tuple[Fraction, ...]:
        return tuple(Fraction(str(v)) for v in (self.detour, self.time, self.price, self.comfort, self.circle))

    def to_json(self) -> dict[str, float]:
        return {"detour": self.detour, "time": self.time, "price": self.price, "comfort": self.comfort,
                "circle": self.circle}

    @classmethod
    def from_json(cls, data: dict[str, float]) -> ScoreWeights:
        return cls(**data)


@dataclass(frozen=True)
class ArrivalWindow:
    earliest: datetime
    target: datetime
    latest: datetime

    def __post_init__(self):
        for name in ("earliest", "target", "latest"):
            _aware(getattr(self, name), name)
        if not self.earliest <= self.target <= self.latest:
            raise ValueError("La fenêtre doit vérifier earliest <= target <= latest")

    def contains(self, moment: datetime) -> bool:
        return self.earliest <= moment <= self.latest

    @property
    def half_width_s(self) -> Fraction:
        """Δt du score : demi-largeur de la fenêtre, en secondes."""
        return Fraction(int((self.latest - self.earliest).total_seconds()), 2)

    def to_json(self) -> dict[str, str]:
        return {"earliest": _iso(self.earliest), "target": _iso(self.target), "latest": _iso(self.latest)}

    @classmethod
    def from_json(cls, data: dict[str, str]) -> ArrivalWindow:
        return cls(*(datetime.fromisoformat(data[k]) for k in ("earliest", "target", "latest")))


@dataclass(frozen=True)
class Student:
    age: int
    parent_consent: bool


@dataclass(frozen=True)
class PassengerRequest:
    """Exigences du passager pour un trajet."""

    passenger_id: str
    origin: Point
    destination: Point
    arrival_window: ArrivalWindow
    max_price: int                                   # FCFA
    circles: tuple[str, ...]                         # du plus proche au plus large
    organization_id: str | None = None               # "organization:<id>", ou None (réseau public seul)
    mode: str = "AUTONOMOUS"
    seats: int = 1
    comfort_required: frozenset[str] = field(default_factory=frozenset)
    comfort_preferred: frozenset[str] = field(default_factory=frozenset)
    trip_kind: str = "URBAN"
    passenger_kind: str = "ADULT"
    student: Student | None = None
    weights: ScoreWeights | None = None              # None : poids par défaut
    exclude_drivers: frozenset[str] = field(default_factory=frozenset)  # "driver:<id>"
    parent_request_id: str | None = None             # renégociation après annulation

    def __post_init__(self):
        if self.max_price < 0:
            raise ValueError("max_price doit être positif ou nul")
        if not 1 <= self.seats <= 4:
            raise ValueError("seats doit être entre 1 et 4")
        if not self.circles or len(set(self.circles)) != len(self.circles) or not set(self.circles) <= set(CIRCLES):
            raise ValueError(f"circles doit être une liste non vide et sans doublon de {CIRCLES}")
        if self.organization_id is None and set(self.circles) != {"PUBLIC"}:
            raise ValueError("Sans organisation, seul le cercle PUBLIC est possible")
        if self.organization_id is not None and not self.organization_id.startswith("organization:"):
            raise ValueError("organization_id doit être de la forme organization:<id>")
        if self.mode not in MODES:
            raise ValueError(f"mode inconnu : {self.mode}")
        if not (self.comfort_required | self.comfort_preferred) <= COMFORTS:
            raise ValueError("Critère de confort inconnu")
        if self.trip_kind not in TRIP_KINDS:
            raise ValueError(f"trip_kind inconnu : {self.trip_kind}")
        if self.passenger_kind not in PASSENGER_KINDS:
            raise ValueError(f"passenger_kind inconnu : {self.passenger_kind}")
        if (self.passenger_kind == "STUDENT") != (self.student is not None):
            raise ValueError("student est obligatoire pour un élève, et interdit sinon")
        if any(not d.startswith("driver:") for d in self.exclude_drivers):
            raise ValueError("exclude_drivers contient des identifiants driver:<id>")

    @property
    def score_weights(self) -> ScoreWeights:
        return self.weights or ScoreWeights()

    def to_body(self) -> dict[str, Any]:
        """Corps du message RIDE_REQUEST."""
        body: dict[str, Any] = {"passenger_kind": self.passenger_kind}
        if self.student is not None:
            body["student"] = {"age": self.student.age, "parent_consent": self.student.parent_consent}
        body.update({
            "organization_id": self.organization_id,
            "origin": self.origin.to_json(),
            "destination": self.destination.to_json(),
            "trip_kind": self.trip_kind,
            "arrival_window": self.arrival_window.to_json(),
            "max_price": self.max_price,
            "seats": self.seats,
            "comfort": {"required": sorted(self.comfort_required), "preferred": sorted(self.comfort_preferred)},
            "circles": list(self.circles),
            "mode": self.mode,
            "exclude_drivers": sorted(self.exclude_drivers),
        })
        if self.weights is not None:
            body["weights"] = self.weights.to_json()
        if self.parent_request_id is not None:
            body["parent_request_id"] = self.parent_request_id
        return body

    @classmethod
    def from_body(cls, passenger_id: str, body: dict[str, Any]) -> PassengerRequest:
        """Reconstruit une demande depuis le corps d'un RIDE_REQUEST."""
        student = body.get("student")
        return cls(
            passenger_id=passenger_id,
            origin=Point.from_json(body["origin"]),
            destination=Point.from_json(body["destination"]),
            arrival_window=ArrivalWindow.from_json(body["arrival_window"]),
            max_price=body["max_price"],
            circles=tuple(body["circles"]),
            organization_id=body["organization_id"],
            mode=body["mode"],
            seats=body["seats"],
            comfort_required=frozenset(body["comfort"]["required"]),
            comfort_preferred=frozenset(body["comfort"]["preferred"]),
            trip_kind=body["trip_kind"],
            passenger_kind=body["passenger_kind"],
            student=Student(student["age"], student["parent_consent"]) if student else None,
            weights=ScoreWeights.from_json(body["weights"]) if "weights" in body else None,
            exclude_drivers=frozenset(body["exclude_drivers"]),
            parent_request_id=body.get("parent_request_id"),
        )


# --- Classement des offres -----------------------------------------------------------------

def _clamp(value: Fraction) -> Fraction:
    return max(Fraction(0), min(Fraction(1), value))


def offer_rejection(request: PassengerRequest, offer: dict[str, Any], driver: str) -> str | None:
    """Motif pour lequel le passager écarte une offre, ou None si elle respecte ses exigences."""
    if driver in request.exclude_drivers:
        return "EXCLUDED_DRIVER"
    if offer["circle"] not in request.circles:
        return "CIRCLE_NOT_ACCEPTED"
    if offer["price"] > request.max_price:
        return "PRICE_TOO_HIGH"
    if not request.arrival_window.contains(datetime.fromisoformat(offer["dropoff_time"])):
        return "OUTSIDE_WINDOW"
    if not request.comfort_required <= set(offer["comfort_offered"]):
        return "COMFORT_MISSING"
    if offer["detour_m"] > offer["max_detour_m"]:
        return "DETOUR_ABOVE_MAX"
    return None


def score_offer(request: PassengerRequest, offer: dict[str, Any]) -> Fraction:
    """Score entre 0 et 1 (1 = meilleur cas pour chaque terme), en fraction exacte.

    S = w_d (1 - d/d_max) + w_t (1 - |t - t_cible|/Δt) + w_p (1 - p/p_max) + w_c c + w_k k
    """
    w_detour, w_time, w_price, w_comfort, w_circle = request.score_weights.fractions()
    window = request.arrival_window

    detour = 1 - Fraction(offer["detour_m"], offer["max_detour_m"])

    gap_s = abs(int((datetime.fromisoformat(offer["dropoff_time"]) - window.target).total_seconds()))
    half = window.half_width_s
    time = (1 - gap_s / half) if half else Fraction(1 if gap_s == 0 else 0)

    price = (1 - Fraction(offer["price"], request.max_price)) if request.max_price else Fraction(1)

    preferred = request.comfort_preferred
    comfort = Fraction(len(preferred & set(offer["comfort_offered"])), len(preferred)) if preferred else Fraction(1)

    circle = CIRCLE_PROXIMITY[offer["circle"]]

    return (w_detour * _clamp(detour) + w_time * _clamp(time) + w_price * _clamp(price)
            + w_comfort * comfort + w_circle * circle)


@dataclass(frozen=True)
class RankedOffer:
    proposal: messages.Message   # message PROPOSAL reçu
    score: Fraction

    @property
    def driver(self) -> str:
        return self.proposal["sender"]

    @property
    def offer_id(self) -> str:
        return self.proposal["body"]["offer_id"]

    def sort_key(self) -> tuple:
        """Meilleur score d'abord ; à égalité : plus petit détour, départ le plus tôt, plus petit identifiant."""
        body = self.proposal["body"]
        return (-self.score, body["detour_m"], datetime.fromisoformat(body["departure_time"]), self.driver)


def rank_offers(request: PassengerRequest, proposals: list[messages.Message]) -> tuple[list[RankedOffer], list[tuple[str, str]]]:
    """(offres classées de la meilleure à la moins bonne, offres écartées [(conducteur, motif)])."""
    ranked, rejected = [], []
    for proposal in sorted(proposals, key=lambda m: m["sender"]):
        reason = offer_rejection(request, proposal["body"], proposal["sender"])
        if reason:
            rejected.append((proposal["sender"], reason))
        else:
            ranked.append(RankedOffer(proposal, score_offer(request, proposal["body"])))
    ranked.sort(key=RankedOffer.sort_key)
    return ranked, rejected


# --- Agent ------------------------------------------------------------------------------------

class PassengerAgent:
    def __init__(self, request: PassengerRequest, conversation_id: str):
        self.request = request
        self.conversation_id = conversation_id
        self.state = NEW
        self.round = 0
        self.expected: tuple[str, ...] = ()           # conducteurs sollicités dans le tour en cours
        self.replies: dict[str, messages.Message] = {}
        self.ranking: list[RankedOffer] = []          # offres restantes, de la meilleure à la moins bonne
        self.rejected: list[tuple[str, str]] = []     # offres écartées dans le tour en cours
        self.pending: RankedOffer | None = None       # offre acceptée, en attente de confirmation
        self.booking: dict[str, Any] | None = None    # corps de CREW_CONFIRMED
        self.failure: dict[str, Any] | None = None    # corps de NO_CREW
        self._last_reply: messages.Message | None = None

    @property
    def agent_id(self) -> str:
        return messages.agent_id("passenger", self.request.passenger_id)

    @property
    def proposals(self) -> list[RankedOffer]:
        """Mode manuel : les offres présentées à l'utilisateur (trois au plus)."""
        return self.ranking[:MANUAL_CHOICES] if self.state == AWAITING_USER else []

    # Messages envoyés à l'initiative du passager ou de l'utilisateur.

    def start(self) -> messages.Message:
        """Brouillon du RIDE_REQUEST qui ouvre la négociation."""
        self._require(NEW)
        self.state = SUBMITTED
        return messages.draft("RIDE_REQUEST", sender=self.agent_id, receiver=COORDINATOR,
                              conversation_id=self.conversation_id, in_reply_to=None, body=self.request.to_body())

    def choose(self, offer_id: str) -> list[messages.Message]:
        """Mode manuel : l'utilisateur choisit une des offres présentées."""
        self._require(AWAITING_USER)
        chosen = next((o for o in self.proposals if o.offer_id == offer_id), None)
        if chosen is None:
            raise ValueError(f"L'offre {offer_id} ne fait pas partie des offres présentées")
        return [self._accept(chosen)]

    def widen(self) -> list[messages.Message]:
        """Mode manuel : l'utilisateur refuse les offres et demande d'élargir le cercle."""
        self._require(AWAITING_USER)
        return [self._give_up(self._last_reply, "USER_ASKED_WIDENING")]

    def withdraw(self) -> list[messages.Message]:
        """L'utilisateur abandonne sa demande."""
        self._require(SUBMITTED, CALLING, AWAITING_USER)
        reason = "USER_DECLINED_ALL" if self.state == AWAITING_USER else "USER_CANCELLED"
        self.state = WITHDRAWN
        return [messages.draft("REQUEST_WITHDRAWN", sender=self.agent_id, receiver=COORDINATOR,
                               conversation_id=self.conversation_id, in_reply_to=None, body={"reason": reason})]

    # Messages reçus du bus.

    async def handle(self, message: messages.Message) -> list[messages.Message]:
        """Traite un message reçu du bus et renvoie les brouillons à envoyer."""
        if message["receiver"] != self.agent_id:
            raise ValueError(f"{self.agent_id} a reçu un message destiné à {message['receiver']}")
        if message["conversation_id"] != self.conversation_id:
            raise ValueError(f"Conversation inattendue : {message['conversation_id']}")
        handler = {
            "REQUEST_AGREED": self._on_agreed,
            "PROPOSAL": self._on_reply,
            "DECLINE": self._on_reply,
            "BOOKING_FAILED": self._on_booking_failed,
            "CREW_CONFIRMED": self._on_crew_confirmed,
            "NO_CREW": self._on_no_crew,
        }.get(message["type"])
        if handler is None:
            raise ValueError(f"L'agent passager ne traite pas encore les messages {message['type']}")
        return handler(message)

    def _on_agreed(self, message: messages.Message) -> list[messages.Message]:
        self._require(SUBMITTED)
        body = message["body"]
        if body["round"] <= self.round:
            raise ValueError(f"Tour {body['round']} déjà passé")
        if body["expected_replies"] != len(body["cfp_sent_to"]):
            raise ValueError("expected_replies ne correspond pas au nombre de conducteurs sollicités")
        self.round = body["round"]
        self.expected = tuple(body["cfp_sent_to"])
        self.replies, self.ranking, self.rejected = {}, [], []
        self.state = CALLING
        return []

    def _on_reply(self, message: messages.Message) -> list[messages.Message]:
        self._require(CALLING)
        driver = message["sender"]
        if message["body"]["round"] != self.round:
            raise ValueError(f"Réponse du tour {message['body']['round']} reçue pendant le tour {self.round}")
        if driver not in self.expected:
            raise ValueError(f"{driver} n'a pas été sollicité")
        if driver in self.replies:
            raise ValueError(f"{driver} a déjà répondu")
        self.replies[driver] = message
        self._last_reply = message
        if len(self.replies) < len(self.expected):
            return []
        return self._decide(message)

    def _decide(self, last: messages.Message) -> list[messages.Message]:
        proposals = [m for m in self.replies.values() if m["type"] == "PROPOSAL"]
        self.ranking, self.rejected = rank_offers(self.request, proposals)
        if not self.ranking:
            return [self._give_up(last, "NONE_ACCEPTABLE" if proposals else "ALL_DECLINED")]
        if self.request.mode == "AUTONOMOUS":
            return [self._accept(self.ranking[0])]
        self.state = AWAITING_USER
        return []

    def _on_booking_failed(self, message: messages.Message) -> list[messages.Message]:
        self._require(ACCEPTING)
        if self.pending is None or message["body"]["offer_id"] != self.pending.offer_id:
            raise ValueError("Échec reçu pour une offre qui n'était pas en attente")
        self.ranking.remove(self.pending)
        self.pending = None
        if not self.ranking:
            return [self._give_up(message, "ALL_FAILED")]
        if self.request.mode == "AUTONOMOUS":
            return [self._accept(self.ranking[0])]
        self.state = AWAITING_USER
        return []

    def _on_crew_confirmed(self, message: messages.Message) -> list[messages.Message]:
        self._require(ACCEPTING)
        if message["body"]["offer_id"] != self.pending.offer_id:
            raise ValueError("Confirmation reçue pour une autre offre que celle acceptée")
        self.booking = message["body"]
        self.state = CONFIRMED
        return []

    def _on_no_crew(self, message: messages.Message) -> list[messages.Message]:
        self._require(SUBMITTED)
        self.failure = message["body"]
        self.state = NO_CREW
        return []

    # Outils.

    def _accept(self, offer: RankedOffer) -> messages.Message:
        self.pending = offer
        self.state = ACCEPTING
        return messages.reply(offer.proposal, "ACCEPT", sender=self.agent_id, receiver=offer.driver,
                              body={"offer_id": offer.offer_id, "round": self.round})

    def _give_up(self, last: messages.Message, reason: str) -> messages.Message:
        self.state = SUBMITTED   # le coordinateur répond par un nouveau tour ou par NO_CREW
        return messages.reply(last, "NO_ACCEPTABLE_OFFER", sender=self.agent_id, receiver=COORDINATOR,
                              body={"round": self.round, "reason": reason})

    def _require(self, *states: str) -> None:
        if self.state not in states:
            raise ValueError(f"Action impossible dans l'état {self.state} (attendu : {', '.join(states)})")
