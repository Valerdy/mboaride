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
Annulation d'un conducteur (US07) : `cancel_trip` puis `run()` ; chaque passager du
conducteur relance automatiquement une demande (nouvelle conversation) sans lui.
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
from .passenger import FINAL_STATES, PassengerAgent, PassengerRequest, conversation_id_for


@dataclass(frozen=True)
class Metrics:
    """Mesures de la grille, calculées sur le journal du bus."""

    messages: int                     # messages échangés au total
    by_type: dict[str, int]
    requests: int                     # demandes soumises par les utilisateurs
    renegotiations: int               # demandes relancées automatiquement après une annulation
    crews: int                        # équipages en place (confirmés et non annulés)
    cancelled_crews: int              # équipages annulés par leur conducteur
    reassigned: int                   # renégociations terminées par un nouvel équipage
    no_crew: int                      # demandes sans équipage
    messages_per_crew: float | None   # moyenne des messages des conversations terminées par un équipage
    max_messages_per_crew: int | None
    rounds_per_crew: float | None     # tours d'appel d'offres moyens par équipage (« cycles »)
    elapsed_s: float                  # temps réel cumulé de traitement par le bus (convergence)
    last_run_s: float                 # temps réel du dernier `run()` (par exemple la réaffectation)
    fingerprint: str                  # empreinte du journal complet


class Engine:
    def __init__(self, *, cfp_fanout: int = DEFAULT_CFP_FANOUT, validate: bool = False):
        self.bus = MessageBus(validate=validate)
        self.coordinator = CoordinatorAgent(cfp_fanout=cfp_fanout)
        self.bus.register(self.coordinator)
        self.passengers: dict[str, PassengerAgent] = {}   # agent passager -> agent
        self.submitted: list[str] = []                     # conversations ouvertes par les utilisateurs
        self.elapsed_s = 0.0
        self.last_run_s = 0.0

    # --- Inscription des agents -------------------------------------------------------------

    def add_organization(self, organization: OrganizationAgent) -> None:
        self.bus.register(organization)

    def add_driver(self, driver: DriverAgent) -> None:
        self.bus.register(driver)
        self.coordinator.register_driver(DriverListing.from_agent(driver))

    # --- Demandes et actions des utilisateurs -------------------------------------------------

    def submit(self, request: PassengerRequest, requested_at: datetime) -> str:
        """Publie une demande ; renvoie l'identifiant de conversation. Lancer `run()` ensuite."""
        sent_at = _iso(requested_at)
        agent_id = messages.agent_id("passenger", request.passenger_id)
        passenger = self.passengers.get(agent_id)
        if passenger is None:
            passenger = PassengerAgent(request, conversation_id_for(request.passenger_id, 1))
            self.bus.register(passenger)
            self.passengers[agent_id] = passenger
            draft = passenger.start()
        elif passenger.state in FINAL_STATES:
            draft = passenger.renew(request)
        else:
            raise ValueError(f"{agent_id} a déjà une demande en cours")
        self.submitted.append(passenger.conversation_id)
        self.bus.post(draft, sent_at)
        return passenger.conversation_id

    def submit_many(self, requests: list[tuple[PassengerRequest, datetime]]) -> list[str]:
        """Publie un lot de demandes dans l'ordre (heure de demande, identifiant du passager)."""
        ordered = sorted(requests, key=lambda item: (item[1], item[0].passenger_id))
        return [self.submit(request, at) for request, at in ordered]

    def choose(self, conversation_id: str, offer_id: str) -> None:
        """Mode manuel : l'utilisateur choisit une des offres présentées."""
        self._post_user(conversation_id, self._current(conversation_id).choose(offer_id))

    def widen(self, conversation_id: str) -> None:
        """Mode manuel : l'utilisateur refuse les offres et demande d'élargir le cercle."""
        self._post_user(conversation_id, self._current(conversation_id).widen())

    def withdraw(self, conversation_id: str) -> None:
        """L'utilisateur abandonne sa demande."""
        self._post_user(conversation_id, self._current(conversation_id).withdraw())

    def cancel_trip(self, driver_id: str, at: datetime, reason: str = "DRIVER_CANCELLED") -> None:
        """Le conducteur annule son trajet (US07). Lancer `run()` ensuite."""
        driver = self.bus.agents[messages.agent_id("driver", driver_id)]
        self.bus.post(driver.cancel_trip(reason), _iso(at))

    def passenger(self, conversation_id: str) -> PassengerAgent:
        """Agent passager qui a ouvert cette conversation (ou l'une de ses suivantes)."""
        for passenger in self.passengers.values():
            if conversation_id in passenger.history:
                return passenger
        raise KeyError(f"Conversation inconnue : {conversation_id}")

    def conversations(self) -> list[str]:
        """Toutes les conversations de passagers, demandes relancées comprises, triées."""
        return sorted(c for p in self.passengers.values() for c in p.history)

    async def run(self) -> int:
        """Livre tous les messages en attente ; renvoie le nombre de messages livrés."""
        start = time.perf_counter()
        delivered = await self.bus.run()
        self.last_run_s = time.perf_counter() - start
        self.elapsed_s += self.last_run_s
        return delivered

    def _current(self, conversation_id: str) -> PassengerAgent:
        passenger = self.passenger(conversation_id)
        if passenger.conversation_id != conversation_id:
            raise ValueError(f"La conversation {conversation_id} est terminée ; la demande en cours est {passenger.conversation_id}")
        return passenger

    def _post_user(self, conversation_id: str, drafts: list[messages.Message]) -> None:
        sent_at = next(m["sent_at"] for m in self.bus.log if m["conversation_id"] == conversation_id)
        for d in drafts:
            self.bus.post(d, sent_at)

    # --- Mesures -------------------------------------------------------------------------------

    def conversation_log(self, conversation_id: str) -> list[messages.Message]:
        return [m for m in self.bus.log if m["conversation_id"] == conversation_id]

    def metrics(self) -> Metrics:
        log = self.bus.log
        per_conversation: dict[str, list[messages.Message]] = defaultdict(list)
        for m in log:
            per_conversation[m["conversation_id"]].append(m)
        crew_sizes, crew_rounds = [], []
        renegotiations = reassigned = 0
        for conversation_id in self.conversations():
            conv_log = per_conversation[conversation_id]
            types = {m["type"] for m in conv_log}
            relaunched = "parent_request_id" in conv_log[0]["body"]
            renegotiations += relaunched
            if "CREW_CONFIRMED" in types and "CREW_CANCELLED" not in types:
                crew = next(m for m in conv_log if m["type"] == "CREW_CONFIRMED")
                crew_sizes.append(len(conv_log))
                crew_rounds.append(crew["body"]["rounds"])
                reassigned += relaunched
        by_type = dict(sorted(Counter(m["type"] for m in log).items()))
        return Metrics(
            messages=len(log),
            by_type=by_type,
            requests=len(self.submitted),
            renegotiations=renegotiations,
            crews=len(crew_sizes),
            cancelled_crews=by_type.get("CREW_CANCELLED", 0),
            reassigned=reassigned,
            no_crew=by_type.get("NO_CREW", 0),
            messages_per_crew=sum(crew_sizes) / len(crew_sizes) if crew_sizes else None,
            max_messages_per_crew=max(crew_sizes) if crew_sizes else None,
            rounds_per_crew=sum(crew_rounds) / len(crew_rounds) if crew_rounds else None,
            elapsed_s=self.elapsed_s,
            last_run_s=self.last_run_s,
            fingerprint=self.bus.fingerprint(),
        )

    def assignments(self) -> list[tuple[str, str, str]]:
        """Équipages en place (passager, conducteur, heure de prise en charge), triés."""
        cancelled = {m["conversation_id"] for m in self.bus.log if m["type"] == "CREW_CANCELLED"}
        return sorted((m["receiver"], m["body"]["driver"], m["body"]["pickup_time"])
                      for m in self.bus.log if m["type"] == "CREW_CONFIRMED" and m["conversation_id"] not in cancelled)


def _iso(moment: datetime) -> str:
    if moment.tzinfo is None:
        raise ValueError("L'heure doit porter un fuseau horaire")
    return moment.isoformat(timespec="seconds")
