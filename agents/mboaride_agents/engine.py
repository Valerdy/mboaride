"""Moteur de négociation : assemble le bus, le coordinateur et les agents.

Point d'entrée du service agents et des scénarios du banc de mesure :

    engine = Engine()
    engine.add_organization(OrganizationAgent("entreprise-test", members=[...]))
    engine.add_driver(DriverAgent(profile, EstimatedRouting()))
    conversation = engine.submit(request, requested_at)
    await engine.run()
    engine.passenger(conversation).state   # CONFIRMED, NO_CREW, ou AWAITING_USER (mode manuel)

Mode manuel (US05) : après `run()`, l'agent passager est en AWAITING_USER et
`engine.passenger(conversation).proposals` donne les trois meilleures offres ;
l'utilisateur répond avec `choose`, `widen` ou `withdraw`, suivis de `run()`.
Mode autonome (US06) : `run()` mène la négociation jusqu'à l'équipage ou à l'échec.
"""
from __future__ import annotations

import time
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime

from . import messages
from .bus import MessageBus
from .coordinator import DEFAULT_CFP_FANOUT, CoordinatorAgent, DriverListing
from .driver import DriverAgent
from .organization import OrganizationAgent
from .passenger import PassengerAgent, PassengerRequest

FINAL_TYPES = ("CREW_CONFIRMED", "NO_CREW", "REQUEST_WITHDRAWN")


@dataclass(frozen=True)
class Metrics:
    """Mesures de la grille, calculées sur le journal du bus."""

    messages: int                     # messages échangés au total
    by_type: dict[str, int]
    requests: int                     # demandes soumises
    crews: int                        # équipages formés
    no_crew: int                      # demandes sans équipage
    messages_per_crew: float | None   # moyenne des messages des conversations terminées par un équipage
    max_messages_per_crew: int | None
    rounds_per_crew: float | None     # tours d'appel d'offres moyens par équipage (« cycles »)
    elapsed_s: float                  # temps réel de traitement par le bus (convergence)
    fingerprint: str                  # empreinte du journal complet


class Engine:
    def __init__(self, *, cfp_fanout: int = DEFAULT_CFP_FANOUT, validate: bool = False):
        self.bus = MessageBus(validate=validate)
        self.coordinator = CoordinatorAgent(cfp_fanout=cfp_fanout)
        self.bus.register(self.coordinator)
        self.passengers: dict[str, PassengerAgent] = {}   # conversation -> agent passager
        self._requested_at: dict[str, str] = {}
        self._count: Counter[str] = Counter()
        self.elapsed_s = 0.0

    # --- Inscription des agents -------------------------------------------------------------

    def add_organization(self, organization: OrganizationAgent) -> None:
        self.bus.register(organization)

    def add_driver(self, driver: DriverAgent) -> None:
        self.bus.register(driver)
        self.coordinator.register_driver(DriverListing.from_agent(driver))

    # --- Demandes et actions des utilisateurs -------------------------------------------------

    def submit(self, request: PassengerRequest, requested_at: datetime) -> str:
        """Publie une demande ; renvoie l'identifiant de conversation. Lancer `run()` ensuite."""
        if requested_at.tzinfo is None:
            raise ValueError("requested_at doit porter un fuseau horaire")
        agent_id = messages.agent_id("passenger", request.passenger_id)
        current = self.bus.agents.get(agent_id)
        if current is not None and current.state not in ("CONFIRMED", "NO_CREW", "WITHDRAWN"):
            raise ValueError(f"{agent_id} a déjà une demande en cours")
        self._count[request.passenger_id] += 1
        conversation_id = f"r-{request.passenger_id}-{self._count[request.passenger_id]}"
        passenger = PassengerAgent(request, conversation_id)
        self.bus.register(passenger, replace=True)
        self.passengers[conversation_id] = passenger
        self._requested_at[conversation_id] = requested_at.isoformat(timespec="seconds")
        self.bus.post(passenger.start(), self._requested_at[conversation_id])
        return conversation_id

    def submit_many(self, requests: list[tuple[PassengerRequest, datetime]]) -> list[str]:
        """Publie un lot de demandes dans l'ordre (heure de demande, identifiant du passager)."""
        ordered = sorted(requests, key=lambda item: (item[1], item[0].passenger_id))
        return [self.submit(request, at) for request, at in ordered]

    def choose(self, conversation_id: str, offer_id: str) -> None:
        """Mode manuel : l'utilisateur choisit une des offres présentées."""
        self._post_user(conversation_id, self.passenger(conversation_id).choose(offer_id))

    def widen(self, conversation_id: str) -> None:
        """Mode manuel : l'utilisateur refuse les offres et demande d'élargir le cercle."""
        self._post_user(conversation_id, self.passenger(conversation_id).widen())

    def withdraw(self, conversation_id: str) -> None:
        """L'utilisateur abandonne sa demande."""
        self._post_user(conversation_id, self.passenger(conversation_id).withdraw())

    def passenger(self, conversation_id: str) -> PassengerAgent:
        return self.passengers[conversation_id]

    async def run(self) -> int:
        """Livre tous les messages en attente ; renvoie le nombre de messages livrés."""
        start = time.perf_counter()
        delivered = await self.bus.run()
        self.elapsed_s += time.perf_counter() - start
        return delivered

    def _post_user(self, conversation_id: str, drafts: list[messages.Message]) -> None:
        for d in drafts:
            self.bus.post(d, self._requested_at[conversation_id])

    # --- Mesures -------------------------------------------------------------------------------

    def conversation_log(self, conversation_id: str) -> list[messages.Message]:
        return [m for m in self.bus.log if m["conversation_id"] == conversation_id]

    def metrics(self) -> Metrics:
        log = self.bus.log
        per_conversation: dict[str, list[messages.Message]] = defaultdict(list)
        for m in log:
            per_conversation[m["conversation_id"]].append(m)
        crew_sizes, crew_rounds = [], []
        for conversation_id in self.passengers:
            conv_log = per_conversation[conversation_id]
            crew = next((m for m in conv_log if m["type"] == "CREW_CONFIRMED"), None)
            if crew is not None:
                crew_sizes.append(len(conv_log))
                crew_rounds.append(crew["body"]["rounds"])
        by_type = dict(sorted(Counter(m["type"] for m in log).items()))
        return Metrics(
            messages=len(log),
            by_type=by_type,
            requests=len(self.passengers),
            crews=len(crew_sizes),
            no_crew=by_type.get("NO_CREW", 0),
            messages_per_crew=sum(crew_sizes) / len(crew_sizes) if crew_sizes else None,
            max_messages_per_crew=max(crew_sizes) if crew_sizes else None,
            rounds_per_crew=sum(crew_rounds) / len(crew_rounds) if crew_rounds else None,
            elapsed_s=self.elapsed_s,
            fingerprint=self.bus.fingerprint(),
        )

    def assignments(self) -> list[tuple[str, str, str]]:
        """Affectations (passager, conducteur, heure de prise en charge), triées."""
        return sorted((m["receiver"], m["body"]["driver"], m["body"]["pickup_time"])
                      for m in self.bus.log if m["type"] == "CREW_CONFIRMED")
