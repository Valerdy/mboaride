"""Agent conducteur : un appel d'offres (CFP) donne une offre (PROPOSAL) ou un refus motivé (DECLINE)."""
import asyncio
import copy
import dataclasses
import json
from datetime import datetime
from fractions import Fraction
from pathlib import Path

import pytest

from mboaride_agents import messages
from mboaride_agents.driver import DriverAgent, DriverProfile, DriverTrip
from mboaride_agents.pricing import OCCUPANTS, PricingPolicy, quote, round_half_up
from mboaride_agents.routing import Detour, EstimatedRouting, NoRouteError, Point

SCHEMAS = Path(__file__).resolve().parent.parent / "schemas"
EXAMPLES = json.loads((SCHEMAS / "examples.json").read_text(encoding="utf-8"))
NOMINAL = {m["id"]: m for m in EXAMPLES["nominal"]}

LOGPOM = Point(4.0790, 9.7740)
KOTTO = Point(4.0711, 9.7590)
BONANJO = Point(4.0440, 9.6935)

# Détour de d07 dans l'exemple nominal : prise à 7 h 08, dépose à 7 h 36.
D07_DETOUR = Detour(detour_m=1400, detour_s=240, pickup_offset_s=780, shared_distance_m=9800, shared_duration_s=1680)


class FixedRouting:
    """Itinéraire imposé par le test ; compte les appels."""

    def __init__(self, detour: Detour = D07_DETOUR, error: Exception | None = None):
        self.value, self.error, self.calls = detour, error, 0

    async def detour(self, origin, destination, pickup, dropoff):
        self.calls += 1
        if self.error:
            raise self.error
        return self.value


def d07_profile(**changes) -> DriverProfile:
    trip_changes = {k: changes.pop(k) for k in ("departure_time", "trip_kind", "tolls") if k in changes}
    trip = DriverTrip(trip_id="t-d07", origin=LOGPOM, destination=BONANJO,
                      departure_time=datetime.fromisoformat("2026-11-10T06:55:00+01:00"))
    profile = DriverProfile(driver_id="d07", trip=dataclasses.replace(trip, **trip_changes), seats_total=3,
                            max_detour_m=3000, comfort=frozenset({"AIR_CONDITIONING", "NON_SMOKING"}))
    return dataclasses.replace(profile, **changes)


def cfp(receiver="driver:d07", **body_changes) -> dict:
    message = copy.deepcopy(NOMINAL["m-5"])
    message["receiver"] = receiver
    message["body"].update(body_changes)
    return message


def answer(agent: DriverAgent, message: dict) -> dict:
    """Réponse de l'agent, tamponnée comme le ferait le bus, et vérifiée contre le schéma."""
    drafts = asyncio.run(agent.handle(message))
    assert len(drafts) == 1, "un appel d'offres reçoit exactement une réponse"
    stamped = messages.stamp(drafts[0], seq=message["seq"] + 1, sent_at=message["sent_at"])
    assert messages.validation_errors(stamped) == []
    return stamped


# --- Conformité au protocole documenté ------------------------------------------------

def test_reproduces_the_documented_proposal():
    out = answer(DriverAgent(d07_profile(), FixedRouting()), NOMINAL["m-5"])
    assert out == {**NOMINAL["m-8"], "id": out["id"], "seq": out["seq"]}


def test_reproduces_the_documented_decline():
    d12 = DriverAgent(d07_profile(driver_id="d12"), FixedRouting(dataclasses.replace(D07_DETOUR, detour_m=5200)))
    out = answer(d12, NOMINAL["m-7"])
    assert out == {**NOMINAL["m-10"], "id": out["id"], "seq": out["seq"]}


def test_reply_goes_to_the_passenger_in_the_same_conversation():
    out = answer(DriverAgent(d07_profile(), FixedRouting()), cfp())
    assert out["receiver"] == "passenger:p042"
    assert out["conversation_id"] == "r-p042-1"
    assert out["in_reply_to"] == "m-5"
    assert out["sender"] == "driver:d07"


def test_same_cfp_gives_same_answer_10_times():
    answers = [answer(DriverAgent(d07_profile(), FixedRouting()), cfp()) for _ in range(10)]
    assert all(a == answers[0] for a in answers)


# --- Chaque filtre produit son motif de refus -------------------------------------------

REFUSALS = {
    "conducteur non agréé": (dict(approved=False), {}, {}, "DRIVER_NOT_APPROVED"),
    "cercle non accepté": (dict(accepted_circles=frozenset({"ORGANIZATION"})), dict(circle="PUBLIC"), {}, "CIRCLE_NOT_ACCEPTED"),
    "élève non accepté": (dict(accepts_students=False), dict(passenger_kind="STUDENT"), {}, "STUDENT_NOT_ALLOWED"),
    "voiture pleine": ({}, {}, dict(seats_booked=3), "NO_SEAT"),
    "pas assez de places": ({}, dict(seats=2), dict(seats_booked=2), "NO_SEAT"),
    "confort obligatoire absent": ({}, dict(comfort_required=["QUIET"]), {}, "COMFORT_MISMATCH"),
    "aucun itinéraire": ({}, {}, dict(routing=FixedRouting(error=NoRouteError())), "NO_ROUTE"),
    "détour trop long": ({}, {}, dict(routing=FixedRouting(dataclasses.replace(D07_DETOUR, detour_m=3001))), "DETOUR_TOO_LONG"),
    "arrivée trop tardive": (dict(departure_time=datetime.fromisoformat("2026-11-10T07:20:00+01:00")), {}, {}, "OUTSIDE_WINDOW"),
    "arrivée trop tôt": (dict(departure_time=datetime.fromisoformat("2026-11-10T06:20:00+01:00")), {}, {}, "OUTSIDE_WINDOW"),
    "prix au-dessus du maximum": ({}, dict(max_price=160), {}, "PRICE_TOO_HIGH"),
    "prix plancher au-dessus du maximum": (dict(min_price=350), {}, {}, "PRICE_TOO_HIGH"),
}


@pytest.mark.parametrize("profile_changes, cfp_changes, agent_args, reason", REFUSALS.values(), ids=REFUSALS.keys())
def test_each_failed_filter_gives_its_reason(profile_changes, cfp_changes, agent_args, reason):
    args = {"routing": FixedRouting(), **agent_args}
    out = answer(DriverAgent(d07_profile(**profile_changes), **args), cfp(**cfp_changes))
    assert out["type"] == "DECLINE"
    assert out["body"] == {"round": 1, "reason": reason}


LIMITS_ACCEPTED = {
    "détour égal au maximum": (dict(routing=FixedRouting(dataclasses.replace(D07_DETOUR, detour_m=3000))), {}, {}),
    "arrivée à la dernière minute": ({}, dict(departure_time=datetime.fromisoformat("2026-11-10T07:09:00+01:00")), {}),
    "arrivée à la première minute": ({}, dict(departure_time=datetime.fromisoformat("2026-11-10T06:49:00+01:00")), {}),
    "prix égal au maximum": ({}, {}, dict(max_price=165)),
    "dernière place libre": (dict(seats_booked=2), {}, {}),
}


@pytest.mark.parametrize("agent_args, profile_changes, cfp_changes", LIMITS_ACCEPTED.values(), ids=LIMITS_ACCEPTED.keys())
def test_limits_are_inclusive(agent_args, profile_changes, cfp_changes):
    args = {"routing": FixedRouting(), **agent_args}
    out = answer(DriverAgent(d07_profile(**profile_changes), **args), cfp(**cfp_changes))
    assert out["type"] == "PROPOSAL"


def test_route_is_not_computed_when_a_cheap_filter_fails():
    routing = FixedRouting()
    answer(DriverAgent(d07_profile(), routing, seats_booked=3), cfp())
    assert routing.calls == 0
    answer(DriverAgent(d07_profile(), routing), cfp())
    assert routing.calls == 1


def test_offer_id_is_unique_per_round():
    agent = DriverAgent(d07_profile(), FixedRouting())
    assert answer(agent, cfp())["body"]["offer_id"] == "o-d07-r-p042-1"
    assert answer(agent, cfp(round=2))["body"]["offer_id"] == "o-d07-r-p042-1-2"


# --- Prix -------------------------------------------------------------------------------

def test_public_circle_adds_10_percent_commission():
    body = answer(DriverAgent(d07_profile(), FixedRouting()), cfp(circle="PUBLIC"))["body"]
    assert body["price_breakdown"] == {"fuel_cost": 659, "tolls": 0, "divisor": 4, "commission": 17}
    assert body["price"] == 165 + 17


def test_interurban_trip_shares_tolls_and_adds_commission():
    profile = d07_profile(trip_kind="INTERURBAN", tolls=1000,
                          departure_time=datetime.fromisoformat("2026-11-13T14:00:00+01:00"))
    routing = FixedRouting(Detour(detour_m=2000, detour_s=600, pickup_offset_s=600,
                                  shared_distance_m=240_000, shared_duration_s=14_400))
    window = {"earliest": "2026-11-13T17:30:00+01:00", "target": "2026-11-13T18:00:00+01:00",
              "latest": "2026-11-13T18:30:00+01:00"}
    body = answer(DriverAgent(profile, routing), cfp(trip_kind="INTERURBAN", arrival_window=window, max_price=6000))["body"]
    # 240 km x 8 L/100 km x 840 FCFA = 16 128 FCFA ; (16 128 + 1 000) / 4 = 4 282 ; commission 428
    assert body["price_breakdown"] == {"fuel_cost": 16128, "tolls": 1000, "divisor": 4, "commission": 428}
    assert body["price"] == 4710


def test_driver_floor_price_applies():
    body = answer(DriverAgent(d07_profile(min_price=200), FixedRouting()), cfp())["body"]
    assert body["price"] == 200
    assert body["price_breakdown"]["fuel_cost"] == 659


def test_occupants_rule_divides_by_people_on_board():
    agent = DriverAgent(d07_profile(), FixedRouting(), pricing=PricingPolicy(divisor_rule=OCCUPANTS), seats_booked=1)
    body = answer(agent, cfp())["body"]
    assert body["price_breakdown"]["divisor"] == 3   # conducteur + 1 réservé + 1 demandé
    assert body["price"] == 220                      # 659 / 3 = 219,67


@pytest.mark.parametrize("value, expected", [(Fraction(329, 2), 165), (Fraction(5, 2), 3), (Fraction(7, 2), 4),
                                             (Fraction(657, 4), 164), (Fraction(0), 0)])
def test_round_half_up(value, expected):
    assert round_half_up(value) == expected


def test_quote_matches_the_vision_document_example():
    # Logpom -> Bonanjo, 15 km, 8 L/100 km, 840 FCFA : environ 1 000 FCFA, 250 FCFA par passager à 3 passagers.
    q = quote(PricingPolicy(), shared_distance_m=15_000, consumption_l_per_100km=8, tolls=0, seats_total=3,
              seats_booked=0, seats_requested=1, min_price=0, with_commission=False)
    assert (q.fuel_cost, q.divisor, q.price) == (1008, 4, 252)


def test_unknown_divisor_rule_is_rejected():
    with pytest.raises(ValueError):
        PricingPolicy(divisor_rule="HALF")


# --- Estimateur d'itinéraire --------------------------------------------------------------

def test_estimator_gives_no_detour_for_a_passenger_on_the_driver_route():
    d = asyncio.run(EstimatedRouting().detour(LOGPOM, BONANJO, LOGPOM, BONANJO))
    assert (d.detour_m, d.detour_s, d.pickup_offset_s) == (0, 0, 0)


def test_estimator_gives_plausible_values_in_douala():
    d = asyncio.run(EstimatedRouting().detour(LOGPOM, BONANJO, KOTTO, BONANJO))
    assert 8_000 < d.shared_distance_m < 13_000          # Kotto -> Bonanjo, environ 10 km par la route
    assert d.detour_m >= 0 and d.pickup_offset_s > 0
    assert d.shared_duration_s == pytest.approx(d.shared_distance_m / (20 / 3.6), abs=1)


def test_driver_with_estimated_routing_answers_a_valid_message():
    agent = DriverAgent(d07_profile(), EstimatedRouting())
    first = answer(agent, cfp())
    assert first["type"] == "PROPOSAL"
    assert all(answer(agent, cfp()) == first for _ in range(5))


# --- Garde-fous ---------------------------------------------------------------------------

def test_message_for_another_driver_is_refused():
    with pytest.raises(ValueError):
        asyncio.run(DriverAgent(d07_profile(), FixedRouting()).handle(cfp(receiver="driver:d03")))


def test_message_types_not_handled_yet_are_refused():
    accept = copy.deepcopy(NOMINAL["m-11"])
    with pytest.raises(ValueError):
        asyncio.run(DriverAgent(d07_profile(), FixedRouting()).handle(accept))


@pytest.mark.parametrize("changes", [
    dict(seats_total=0), dict(max_detour_m=0), dict(min_price=-1), dict(consumption_l_per_100km=0),
    dict(comfort=frozenset({"JACUZZI"})), dict(accepted_circles=frozenset({"FAMILY"})),
])
def test_invalid_profile_is_rejected(changes):
    with pytest.raises(ValueError):
        d07_profile(**changes)


def test_departure_without_timezone_is_rejected():
    with pytest.raises(ValueError):
        DriverTrip(trip_id="t-1", origin=LOGPOM, destination=BONANJO, departure_time=datetime(2026, 11, 10, 6, 55))


def test_seats_booked_cannot_exceed_seats_offered():
    with pytest.raises(ValueError):
        DriverAgent(d07_profile(), FixedRouting(), seats_booked=4)


def test_performatives_match_the_schema():
    schema = json.loads(messages.SCHEMA_PATH.read_text(encoding="utf-8"))
    from_schema = {name.removeprefix("route_"): rule["then"]["properties"]["performative"]["const"]
                   for name, rule in schema["$defs"].items() if name.startswith("route_")}
    assert from_schema == messages.PERFORMATIVES
