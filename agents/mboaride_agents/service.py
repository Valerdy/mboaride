"""Service agents : le moteur multi-agents exposé en HTTP (docs/architecture-multi-agents.md, section 8).

    cd agents
    uvicorn mboaride_agents.service:app --port 8001

L'API de l'application (Node ou FastAPI) appelle ce service ; il n'est pas destiné à
être exposé sur Internet. Si la variable d'environnement AGENTS_SERVICE_KEY est
définie, chaque requête doit porter l'en-tête `X-Service-Key` correspondant.

Un seul moteur en mémoire, et un verrou : les opérations sont traitées une par une,
dans l'ordre d'arrivée, comme les messages sur le bus. La base de l'API reste la
référence : au démarrage, l'API réinscrit les organisations et les conducteurs.

Formats : la demande d'un passager a exactement le format du corps d'un message
RIDE_REQUEST (schemas/message.schema.json) ; heures ISO 8601 avec fuseau.
"""
from __future__ import annotations

import asyncio
import hmac
import os
from datetime import datetime
from typing import Any, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from pydantic import BaseModel, Field

from . import messages
from .bench import run_scenario
from .driver import DriverAgent, DriverProfile, DriverTrip
from .engine import Engine
from .organization import OrganizationAgent
from .passenger import PassengerAgent, PassengerRequest
from .routing import EstimatedRouting, Point
from .scenarios import SCENARIOS

ESTIMATORS = {"URBAN": EstimatedRouting(speed_kmh=20), "INTERURBAN": EstimatedRouting(speed_kmh=60)}


# --- Corps des requêtes -------------------------------------------------------------------------

class PointIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class OrganizationIn(BaseModel):
    organization_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,40}$", description="identifiant local, sans le préfixe")
    members: list[str] = Field(default_factory=list, description="passenger:<id>")
    partners: list[str] = Field(default_factory=list, description="organization:<id>")
    price_cap: int | None = Field(default=None, ge=0)
    suspended: list[str] = Field(default_factory=list)


class TripIn(BaseModel):
    trip_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")
    origin: PointIn
    destination: PointIn
    departure_time: datetime
    trip_kind: Literal["URBAN", "INTERURBAN"] = "URBAN"
    tolls: int = Field(default=0, ge=0)


class DriverIn(BaseModel):
    driver_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,40}$")
    trip: TripIn
    seats_total: int = Field(ge=1, le=8)
    max_detour_m: int = Field(ge=1)
    min_price: int = Field(default=0, ge=0)
    comfort: list[str] = Field(default_factory=list)
    accepted_circles: list[str] = Field(default_factory=lambda: ["ORGANIZATION", "PARTNERS", "PUBLIC"])
    accepts_students: bool = True
    approved: bool = True
    consumption_l_per_100km: float = Field(default=8.0, gt=0)
    organization_id: str | None = None


class NegotiationIn(BaseModel):
    passenger_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,40}$")
    requested_at: datetime
    request: dict[str, Any] = Field(description="corps d'un message RIDE_REQUEST")


class ChoiceIn(BaseModel):
    action: Literal["choose", "widen", "withdraw"]
    offer_id: str | None = None


class CancellationIn(BaseModel):
    at: datetime
    reason: Literal["DRIVER_CANCELLED", "VEHICLE_BREAKDOWN", "OTHER"] = "DRIVER_CANCELLED"


class BenchIn(BaseModel):
    scenarios: list[str] = Field(default_factory=lambda: list(SCENARIOS))
    runs: int = Field(default=10, ge=1, le=50)
    measure_memory: bool = True


# --- Réponses ----------------------------------------------------------------------------------------

def passenger_status(engine: Engine, passenger: PassengerAgent) -> dict[str, Any]:
    """État de la demande en cours d'un passager, tel que l'application l'affiche."""
    conversation = passenger.conversation_id
    return {
        "conversation_id": conversation,
        "passenger": passenger.agent_id,
        "state": passenger.state,
        "history": list(passenger.history),
        "round": passenger.round,
        "crew": passenger.booking,
        "proposals": [{
            "offer_id": o.offer_id,
            "driver": o.driver,
            "score": round(float(o.score), 4),
            **{k: o.proposal["body"][k] for k in ("circle", "price", "price_breakdown", "pickup_point", "pickup_time",
                                                   "dropoff_time", "departure_time", "detour_m", "comfort_offered")},
        } for o in passenger.proposals],
        "failure": passenger.failure,
        "cancelled_bookings": list(passenger.cancelled_bookings),
        "messages": len(engine.conversation_log(conversation)),
    }


# --- Application -----------------------------------------------------------------------------------

def create_app(*, service_key: str | None = None, cfp_fanout: int = 5) -> FastAPI:
    """Application FastAPI. `service_key` : clé exigée dans l'en-tête X-Service-Key (None : aucune)."""
    app = FastAPI(title="MboaRide · service agents", version="1.0.0",
                  description="Moteur multi-agents MboaRide (protocole mboaride-cnp/1).")
    state = {"engine": Engine(cfp_fanout=cfp_fanout)}
    lock = asyncio.Lock()

    def authorize(x_service_key: str | None = Header(default=None)) -> None:
        if service_key and not (x_service_key and hmac.compare_digest(x_service_key, service_key)):
            raise HTTPException(401, "Clé de service absente ou invalide")

    def engine() -> Engine:
        return state["engine"]

    def require_timezone(moment: datetime, name: str) -> None:
        if moment.tzinfo is None:
            raise HTTPException(422, f"{name} doit porter un fuseau horaire (ex. 2026-11-10T06:15:00+01:00)")

    def passenger_or_404(conversation_id: str) -> PassengerAgent:
        try:
            return engine().passenger(conversation_id)
        except KeyError:
            raise HTTPException(404, f"Conversation inconnue : {conversation_id}") from None

    async def run() -> None:
        await engine().run()

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {"status": "ok", "protocol": messages.PROTOCOL}

    @app.post("/organizations", status_code=201, dependencies=[Depends(authorize)])
    async def add_organization(body: OrganizationIn) -> dict[str, str]:
        async with lock:
            try:
                org = OrganizationAgent(body.organization_id, members=body.members, partners=body.partners,
                                        price_cap=body.price_cap, suspended=body.suspended)
                engine().add_organization(org)
            except ValueError as e:
                raise HTTPException(409 if "déjà inscrit" in str(e) else 422, str(e)) from None
        return {"agent_id": org.agent_id}

    @app.post("/drivers", status_code=201, dependencies=[Depends(authorize)])
    async def add_driver(body: DriverIn) -> dict[str, str]:
        async with lock:
            try:
                t = body.trip
                trip = DriverTrip(t.trip_id, origin=Point(t.origin.lat, t.origin.lng),
                                  destination=Point(t.destination.lat, t.destination.lng),
                                  departure_time=t.departure_time, trip_kind=t.trip_kind, tolls=t.tolls)
                profile = DriverProfile(
                    driver_id=body.driver_id, trip=trip, seats_total=body.seats_total, max_detour_m=body.max_detour_m,
                    min_price=body.min_price, comfort=frozenset(body.comfort),
                    accepted_circles=frozenset(body.accepted_circles), accepts_students=body.accepts_students,
                    approved=body.approved, consumption_l_per_100km=body.consumption_l_per_100km,
                    organization_id=body.organization_id)
                driver = DriverAgent(profile, ESTIMATORS[t.trip_kind])
                engine().add_driver(driver)
            except ValueError as e:
                raise HTTPException(409 if "déjà inscrit" in str(e) else 422, str(e)) from None
        return {"agent_id": driver.agent_id}

    @app.post("/negotiations", status_code=201, dependencies=[Depends(authorize)])
    async def submit(body: NegotiationIn) -> dict[str, Any]:
        """Soumet une demande et mène la négociation : équipage, échec, ou trois offres (mode manuel)."""
        require_timezone(body.requested_at, "requested_at")
        try:
            request = PassengerRequest.from_body(body.passenger_id, body.request)
        except (KeyError, TypeError, ValueError) as e:
            raise HTTPException(422, f"Demande invalide : {e!r}") from None
        async with lock:
            try:
                conversation = engine().submit(request, body.requested_at)
            except ValueError as e:
                raise HTTPException(409, str(e)) from None
            await run()
            return passenger_status(engine(), engine().passenger(conversation))

    @app.get("/negotiations/{conversation_id}", dependencies=[Depends(authorize)])
    async def status(conversation_id: str) -> dict[str, Any]:
        """État de la demande ; après une annulation, c'est la demande relancée qui est renvoyée."""
        async with lock:
            return passenger_status(engine(), passenger_or_404(conversation_id))

    @app.post("/negotiations/{conversation_id}/choice", dependencies=[Depends(authorize)])
    async def choice(conversation_id: str, body: ChoiceIn) -> dict[str, Any]:
        """Mode manuel : choisir une offre, demander d'élargir le cercle, ou retirer la demande."""
        async with lock:
            passenger = passenger_or_404(conversation_id)
            try:
                if body.action == "choose":
                    if not body.offer_id:
                        raise HTTPException(422, "offer_id est obligatoire pour choisir une offre")
                    engine().choose(conversation_id, body.offer_id)
                elif body.action == "widen":
                    engine().widen(conversation_id)
                else:
                    engine().withdraw(conversation_id)
            except ValueError as e:
                raise HTTPException(409, str(e)) from None
            await run()
            return passenger_status(engine(), passenger)

    @app.post("/drivers/{driver_id}/cancellation", dependencies=[Depends(authorize)])
    async def cancel(driver_id: str, body: CancellationIn) -> dict[str, Any]:
        """Le conducteur annule son trajet (US07) : ses passagers sont réaffectés automatiquement."""
        require_timezone(body.at, "at")
        async with lock:
            agent_id = messages.agent_id("driver", driver_id)
            driver = engine().bus.agents.get(agent_id)
            if driver is None:
                raise HTTPException(404, f"Conducteur inconnu : {driver_id}")
            passengers = sorted({b["passenger"] for b in driver.bookings.values()})
            try:
                engine().cancel_trip(driver_id, body.at, body.reason)
            except ValueError as e:
                raise HTTPException(409, str(e)) from None
            await run()
            return {"driver": agent_id, "reassignment_ms": round(engine().last_run_s * 1000, 3),
                    "passengers": [passenger_status(engine(), engine().passengers[p]) for p in passengers]}

    @app.get("/negotiations/{conversation_id}/messages", dependencies=[Depends(authorize)])
    async def conversation_messages(conversation_id: str) -> list[dict[str, Any]]:
        """Journal des messages d'une conversation (démonstration, US15)."""
        async with lock:
            passenger_or_404(conversation_id)
            return engine().conversation_log(conversation_id)

    @app.get("/metrics", dependencies=[Depends(authorize)])
    async def metrics() -> dict[str, Any]:
        """Mesures de la grille sur tout ce que le service a traité depuis son démarrage."""
        async with lock:
            m = engine().metrics()
            return {**m.__dict__, "elapsed_ms": round(m.elapsed_s * 1000, 3)}

    @app.post("/bench/runs", dependencies=[Depends(authorize)])
    async def bench(body: BenchIn) -> list[dict[str, Any]]:
        """Rejoue des scénarios simulés (S1, S3, S5) et renvoie les quatre mesures de la grille."""
        unknown = [s for s in body.scenarios if s not in SCENARIOS]
        if unknown:
            raise HTTPException(422, f"Scénario inconnu : {', '.join(unknown)} (disponibles : {', '.join(SCENARIOS)})")
        async with lock:   # le banc mesure le temps : pas d'autre traitement pendant ce temps
            # Le banc lance ses propres boucles asyncio : il tourne dans un fil à part.
            reports = await asyncio.to_thread(
                lambda: [run_scenario(name, body.runs, body.measure_memory) for name in body.scenarios])
            return [r.to_dict() for r in reports]

    @app.post("/reset", status_code=204, response_class=Response, dependencies=[Depends(authorize)])
    async def reset() -> Response:
        """Repart d'un moteur vide (démonstration, tests). L'API doit ensuite réinscrire ses agents."""
        async with lock:
            state["engine"] = Engine(cfp_fanout=cfp_fanout)
        return Response(status_code=204)

    return app


app = create_app(service_key=os.environ.get("AGENTS_SERVICE_KEY") or None)
