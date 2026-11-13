"""Agent coordinateur : présélection des K conducteurs (SR-26) et parcours des cercles (SR-27)."""
import dataclasses
import json
from datetime import datetime
from pathlib import Path

import pytest

from mboaride_agents.coordinator import Conversation, CoordinatorAgent, DriverListing
from mboaride_agents.routing import Point

EXAMPLES = json.loads((Path(__file__).resolve().parent.parent / "schemas" / "examples.json").read_text(encoding="utf-8"))
REQUEST = EXAMPLES["nominal"][0]["body"]   # Grâce : Kotto -> Bonanjo, arrivée 7 h 30 - 7 h 50

LOGPOM, BONANJO = Point(4.0790, 9.7740), Point(4.0440, 9.6935)
ORG, PARTNER = "organization:entreprise-test", "organization:partenaire-01"


def listing(agent_id="driver:d07", **changes) -> DriverListing:
    base = DriverListing(agent_id=agent_id, organization_id=ORG, accepted_circles=frozenset({"ORGANIZATION", "PARTNERS", "PUBLIC"}),
                         accepts_students=True, approved=True, comfort=frozenset({"AIR_CONDITIONING"}),
                         origin=LOGPOM, destination=BONANJO,
                         departure_time=datetime.fromisoformat("2026-11-10T06:55:00+01:00"), trip_kind="URBAN",
                         max_detour_m=3000, seats_free=3)
    return dataclasses.replace(base, **changes)


def conversation(**request_changes) -> Conversation:
    request = {**REQUEST, **request_changes}
    return Conversation(passenger="passenger:p042", request=request, max_price=request["max_price"],
                        partners=frozenset({PARTNER}))


def coordinator(*listings, k=5) -> CoordinatorAgent:
    c = CoordinatorAgent(cfp_fanout=k)
    for item in listings:
        c.register_driver(item)
    return c


def test_compatible_driver_is_preselected():
    assert coordinator(listing()).preselect(conversation(), "ORGANIZATION") == ["driver:d07"]


EXCLUSIONS = {
    "non agréé": dict(approved=False),
    "plus de place": dict(seats_free=0),
    "cercle refusé par le conducteur": dict(accepted_circles=frozenset({"PUBLIC"})),
    "autre organisation": dict(organization_id="organization:autre"),
    "sans organisation": dict(organization_id=None),
    "trajet interurbain": dict(trip_kind="INTERURBAN"),
    "part trop tôt": dict(departure_time=datetime.fromisoformat("2026-11-10T06:00:00+01:00")),
    "part trop tard": dict(departure_time=datetime.fromisoformat("2026-11-10T07:45:00+01:00")),
    "trop loin": dict(origin=Point(4.0700, 9.6600)),   # Bonabéri
}


@pytest.mark.parametrize("changes", EXCLUSIONS.values(), ids=EXCLUSIONS.keys())
def test_incompatible_driver_is_not_preselected(changes):
    assert coordinator(listing(**changes)).preselect(conversation(), "ORGANIZATION") == []


def test_students_go_only_to_drivers_who_accept_them():
    c = coordinator(listing(accepts_students=False))
    student = conversation(passenger_kind="STUDENT", student={"age": 15, "parent_consent": True})
    assert c.preselect(student, "ORGANIZATION") == []


def test_required_comfort_is_checked_before_soliciting():
    conv = conversation(comfort={"required": ["QUIET"], "preferred": []})
    assert coordinator(listing()).preselect(conv, "ORGANIZATION") == []


def test_excluded_and_already_solicited_drivers_are_skipped():
    c = coordinator(listing("driver:d01"), listing("driver:d02"))
    conv = conversation(exclude_drivers=["driver:d01"])
    conv.solicited.add("driver:d02")
    assert c.preselect(conv, "ORGANIZATION") == []


def test_circles_follow_the_driver_organization():
    c = coordinator(listing("driver:d01"), listing("driver:d02", organization_id=PARTNER),
                    listing("driver:d03", organization_id=None))
    conv = conversation()
    assert c.preselect(conv, "ORGANIZATION") == ["driver:d01"]
    assert c.preselect(conv, "PARTNERS") == ["driver:d02"]
    assert c.preselect(conv, "PUBLIC") == ["driver:d01", "driver:d02", "driver:d03"]


def test_at_most_k_drivers_sorted_by_estimated_detour_then_id():
    # Même trajet pour d05 et d06 (égalité), d01 part de plus loin : il passe après.
    far = Point(4.0850, 9.7800)
    c = coordinator(listing("driver:d06"), listing("driver:d05"), listing("driver:d01", origin=far), k=2)
    assert c.preselect(conversation(), "ORGANIZATION") == ["driver:d05", "driver:d06"]


def test_fanout_must_be_positive():
    with pytest.raises(ValueError):
        CoordinatorAgent(cfp_fanout=0)


def test_driver_registered_twice_is_refused():
    c = coordinator(listing())
    with pytest.raises(ValueError):
        c.register_driver(listing())
