"""Scénarios S2 (ville mixte, montée en charge) et S4 (interurbain) du dossier de conception."""
import asyncio
from collections import Counter

import pytest

from mboaride_agents.scenarios import SCENARIOS, s2_city_mix, s4_interurban


@pytest.fixture(scope="module")
def s2():
    scenario = s2_city_mix()
    engine = scenario.build()
    asyncio.run(scenario.play(engine))
    return scenario, engine


@pytest.fixture(scope="module")
def s4():
    scenario = s4_interurban()
    engine = scenario.build(validate=True)
    asyncio.run(scenario.play(engine))
    return scenario, engine


def test_all_design_scenarios_are_available():
    assert list(SCENARIOS) == ["S1", "S2", "S3", "S4", "S5"]


# --- S2 : ville mixte ---------------------------------------------------------------------------

def test_s2_has_the_documented_size(s2):
    scenario, _ = s2
    assert (len(scenario.drivers), len(scenario.requests), len(scenario.organizations)) == (80, 200, 4)


def test_s2_converges_in_less_than_two_seconds(s2):
    # La grille fixe la cible de convergence sur S1 et S2.
    _, engine = s2
    m = engine.metrics()
    assert m.elapsed_s < 2
    assert m.messages_per_crew < 20


def test_s2_explores_every_circle(s2):
    _, engine = s2
    circles = Counter(m["body"]["circle"] for m in engine.bus.log if m["type"] == "REQUEST_AGREED")
    assert set(circles) == {"ORGANIZATION", "PARTNERS", "PUBLIC"}


def test_s2_school_refuses_exactly_the_three_invalid_students(s2):
    _, engine = s2
    refusals = sorted((m["receiver"], m["body"]["organization_reason"]) for m in engine.bus.log
                      if m["type"] == "NO_CREW" and m["body"]["reason"] == "REFUSED_BY_ORGANIZATION")
    assert refusals == [("passenger:e001", "STUDENT_UNDER_12"), ("passenger:e002", "STUDENT_UNDER_12"),
                        ("passenger:e003", "NO_PARENTAL_CONSENT")]


def test_s2_students_only_ride_with_drivers_who_accept_them(s2):
    scenario, engine = s2
    accepts = {f"driver:{d.driver_id}": d.accepts_students for d in scenario.drivers}
    for m in engine.bus.log:
        if m["type"] == "CREW_CONFIRMED" and m["receiver"].startswith("passenger:e"):
            assert accepts[m["body"]["driver"]]


def test_s2_partners_circle_only_reaches_partner_companies(s2):
    scenario, engine = s2
    driver_org = {f"driver:{d.driver_id}": d.organization_id for d in scenario.drivers}
    passenger_org = {f"passenger:{r.passenger_id}": r.organization_id for r, _ in scenario.requests}
    partners = {"organization:entreprise-a": "organization:entreprise-b", "organization:entreprise-b": "organization:entreprise-a"}
    for m in engine.bus.log:
        if m["type"] == "CFP" and m["body"]["circle"] == "PARTNERS":
            assert driver_org[m["receiver"]] == partners[passenger_org[m["body"]["reply_to"]]]


# --- S4 : interurbain -------------------------------------------------------------------------------

def test_s4_is_interurban_end_to_end(s4):
    _, engine = s4
    cfps = [m for m in engine.bus.log if m["type"] == "CFP"]
    assert cfps and all(m["body"]["trip_kind"] == "INTERURBAN" for m in cfps)


def test_s4_prices_include_tolls_and_commission(s4):
    _, engine = s4
    offers = [m["body"] for m in engine.bus.log if m["type"] == "PROPOSAL"]
    assert offers
    for o in offers:
        b = o["price_breakdown"]
        assert b["tolls"] == 1000 and b["commission"] > 0
        assert o["price"] == max((b["fuel_cost"] + b["tolls"] + b["divisor"] // 2) // b["divisor"], 0) + b["commission"]


def test_s4_road_distance_matches_douala_yaounde(s4):
    # Environ 240 km de route : la distance partagée d'une offre est de cet ordre.
    _, engine = s4
    shared = [m["body"]["shared_distance_m"] for m in engine.bus.log if m["type"] == "PROPOSAL"]
    assert all(220_000 < d < 260_000 for d in shared)
