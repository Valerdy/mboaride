"""Négociation complète sur le bus : coordinateur (SR-26), cercles (SR-27), mode manuel (US05), mode autonome (US06)."""
import asyncio
import dataclasses
import json
from datetime import datetime
from pathlib import Path

import pytest

from mboaride_agents import messages
from mboaride_agents.bus import MessageBus
from mboaride_agents.driver import DriverAgent, DriverProfile, DriverTrip
from mboaride_agents.engine import Engine
from mboaride_agents.organization import OrganizationAgent
from mboaride_agents.passenger import AWAITING_USER, CONFIRMED, NO_CREW, WITHDRAWN, PassengerRequest, Student
from mboaride_agents.routing import EstimatedRouting, Point
from mboaride_agents.scenarios import s1_company_morning

EXAMPLES = json.loads((Path(__file__).resolve().parent.parent / "schemas" / "examples.json").read_text(encoding="utf-8"))
GRACE = PassengerRequest.from_body("p042", EXAMPLES["nominal"][0]["body"])   # Kotto -> Bonanjo, 7 h 30 - 7 h 50, 300 FCFA
AT = datetime.fromisoformat("2026-11-10T06:15:00+01:00")

ORG, PARTNER = "organization:entreprise-test", "organization:partenaire-01"
LOGPOM, LOGBESSOU, BONABERI = Point(4.0790, 9.7740), Point(4.0850, 9.7800), Point(4.0700, 9.6600)
BONANJO = Point(4.0440, 9.6935)


def driver(local, origin=LOGPOM, departure="06:55", organization=ORG, **changes) -> DriverAgent:
    trip = DriverTrip(f"t-{local}", origin=origin, destination=BONANJO,
                      departure_time=datetime.fromisoformat(f"2026-11-10T{departure}:00+01:00"))
    profile = DriverProfile(local, trip, seats_total=3, max_detour_m=3000, organization_id=organization)
    return DriverAgent(dataclasses.replace(profile, **changes), EstimatedRouting())


def engine(*drivers, members=("passenger:p042", "passenger:p043", "passenger:e019"), **org_args) -> Engine:
    e = Engine(validate=True)   # chaque message est vérifié contre le schéma
    e.add_organization(OrganizationAgent("entreprise-test", members=members, partners=[PARTNER], **org_args))
    e.add_organization(OrganizationAgent("partenaire-01", members=[]))
    for d in drivers:
        e.add_driver(d)
    return e


def run(e: Engine) -> None:
    asyncio.run(e.run())


def types(e: Engine, conversation: str) -> list[str]:
    return [m["type"] for m in e.conversation_log(conversation)]


def d07():   # Logpom, arrive à 7 h 33, climatisé
    return driver("d07", comfort=frozenset({"AIR_CONDITIONING"}))


def d03():   # Logbessou, arrive à 7 h 41
    return driver("d03", LOGBESSOU, "07:00")


# --- Mode autonome (US06) --------------------------------------------------------------------

def test_autonomous_mode_books_the_best_offer_without_user():
    e = engine(d07(), d03(), driver("d12", BONABERI, "07:00"))
    conv = e.submit(GRACE, AT)
    run(e)
    passenger = e.passenger(conv)
    assert passenger.state == CONFIRMED
    assert passenger.booking["driver"] == "driver:d03"   # arrivée la plus proche de 7 h 40
    assert types(e, conv) == ["RIDE_REQUEST", "CIRCLE_QUERY", "CIRCLE_ANSWER", "REQUEST_AGREED", "CFP", "CFP",
                              "PROPOSAL", "PROPOSAL", "ACCEPT", "BOOKING_CONFIRMED", "CREW_CONFIRMED"]


def test_far_driver_is_not_even_solicited():
    e = engine(d07(), d03(), driver("d12", BONABERI, "07:00"))
    conv = e.submit(GRACE, AT)
    run(e)
    agreed = next(m for m in e.conversation_log(conv) if m["type"] == "REQUEST_AGREED")
    assert agreed["body"]["cfp_sent_to"] == ["driver:d07", "driver:d03"]   # écart estimé croissant


def test_message_budget_is_7_plus_2k():
    e = engine(d07(), d03())
    conv = e.submit(GRACE, AT)
    run(e)
    k = next(m for m in e.conversation_log(conv) if m["type"] == "REQUEST_AGREED")["body"]["expected_replies"]
    assert len(e.conversation_log(conv)) == 7 + 2 * k


def test_seats_are_updated_on_both_sides():
    e = engine(d07(), d03())
    e.submit(GRACE, AT)
    run(e)
    assert e.bus.agents["driver:d03"].seats_free == 2
    assert e.coordinator.drivers["driver:d03"].seats_free == 2


# --- Mode manuel (US05) ----------------------------------------------------------------------

def manual() -> tuple[Engine, str]:
    e = engine(d07(), d03())
    conv = e.submit(dataclasses.replace(GRACE, mode="MANUAL"), AT)
    run(e)
    return e, conv


def test_manual_mode_waits_for_the_user():
    e, conv = manual()
    passenger = e.passenger(conv)
    assert passenger.state == AWAITING_USER
    assert [o.driver for o in passenger.proposals] == ["driver:d03", "driver:d07"]
    assert "ACCEPT" not in types(e, conv)


def test_manual_user_choice_is_booked():
    e, conv = manual()
    e.choose(conv, "o-d07-r-p042-1")   # l'utilisateur préfère la climatisation
    run(e)
    assert e.passenger(conv).state == CONFIRMED
    assert e.passenger(conv).booking["driver"] == "driver:d07"


def test_manual_user_can_decline_everything():
    e, conv = manual()
    e.withdraw(conv)
    run(e)
    assert e.passenger(conv).state == WITHDRAWN
    assert e.coordinator.conversations[conv].status == "WITHDRAWN"


def test_manual_user_can_ask_to_widen_the_circle():
    e = engine(d07(), d03(), driver("d20", organization=PARTNER, departure="06:57"))
    conv = e.submit(dataclasses.replace(GRACE, mode="MANUAL"), AT)
    run(e)
    e.widen(conv)
    run(e)
    passenger = e.passenger(conv)
    assert (passenger.state, passenger.round) == (AWAITING_USER, 2)
    assert [o.driver for o in passenger.proposals] == ["driver:d20"]


# --- Élargissement progressif des cercles (SR-27) ------------------------------------------------

def test_empty_circle_is_skipped_without_messages():
    # Aucun collègue disponible : le premier tour se fait directement chez les partenaires.
    e = engine(driver("d20", organization=PARTNER))
    conv = e.submit(GRACE, AT)
    run(e)
    agreed = [m["body"] for m in e.conversation_log(conv) if m["type"] == "REQUEST_AGREED"]
    assert [(a["round"], a["circle"]) for a in agreed] == [(1, "PARTNERS")]
    assert e.passenger(conv).state == CONFIRMED


def test_circle_widens_after_no_acceptable_offer():
    # Le collègue et le partenaire sont trop chers (prix plancher) : c'est le réseau public qui répond.
    e = engine(driver("d01", min_price=400), driver("d20", organization=PARTNER, min_price=400),
               driver("d30", organization=None, departure="06:56"))
    conv = e.submit(GRACE, AT)
    run(e)
    log = e.conversation_log(conv)
    assert [(m["body"]["round"], m["body"]["circle"]) for m in log if m["type"] == "REQUEST_AGREED"] == [
        (1, "ORGANIZATION"), (2, "PARTNERS"), (3, "PUBLIC")]
    assert [m["body"]["reason"] for m in log if m["type"] == "NO_ACCEPTABLE_OFFER"] == ["ALL_DECLINED", "ALL_DECLINED"]
    crew = next(m for m in log if m["type"] == "CREW_CONFIRMED")["body"]
    assert (crew["driver"], crew["rounds"]) == ("driver:d30", 3)
    assert e.passenger(conv).booking == crew


def test_only_accepted_circles_are_explored():
    e = engine(driver("d30", organization=None))
    conv = e.submit(dataclasses.replace(GRACE, circles=("ORGANIZATION", "PARTNERS")), AT)
    run(e)
    no_crew = e.conversation_log(conv)[-1]
    assert no_crew["type"] == "NO_CREW"
    assert no_crew["body"] == {"rounds_tried": 0, "reason": "NO_DRIVER_FOUND", "organization_reason": None,
                               "suggestion": "WIDEN_CIRCLES"}


def test_driver_refusing_public_circle_is_not_solicited_there():
    e = engine(driver("d30", organization=None, accepted_circles=frozenset({"ORGANIZATION", "PARTNERS"})))
    conv = e.submit(GRACE, AT)
    run(e)
    assert e.passenger(conv).state == NO_CREW
    assert e.conversation_log(conv)[-1]["body"]["suggestion"] == "WIDEN_WINDOW"


def test_public_only_passenger_skips_the_organization():
    e = engine(driver("d30", organization=None))
    request = dataclasses.replace(GRACE, organization_id=None, circles=("PUBLIC",))
    conv = e.submit(request, AT)
    run(e)
    assert types(e, conv)[:2] == ["RIDE_REQUEST", "REQUEST_AGREED"]
    assert len(e.conversation_log(conv)) == 5 + 2 * 1
    assert e.passenger(conv).state == CONFIRMED


def test_organization_price_cap_lowers_the_maximum_price():
    e = engine(d07(), price_cap=150)
    conv = e.submit(GRACE, AT)
    run(e)
    cfp = next(m for m in e.conversation_log(conv) if m["type"] == "CFP")
    assert cfp["body"]["max_price"] == 150


@pytest.mark.parametrize("passenger, student, reason", [
    ("e019", Student(11, True), "STUDENT_UNDER_12"),
    ("p999", None, "NOT_MEMBER"),
])
def test_refusal_by_the_organization_ends_in_4_messages(passenger, student, reason):
    e = engine(d07())
    request = dataclasses.replace(GRACE, passenger_id=passenger, passenger_kind="STUDENT" if student else "ADULT",
                                  student=student)
    conv = e.submit(request, AT)
    run(e)
    assert types(e, conv) == ["RIDE_REQUEST", "CIRCLE_QUERY", "CIRCLE_ANSWER", "NO_CREW"]
    assert e.conversation_log(conv)[-1]["body"]["organization_reason"] == reason
    assert e.passenger(conv).state == NO_CREW


# --- Arbitrage : deux passagers pour une seule place ---------------------------------------------

def two_passengers_one_seat(order):
    e = engine(driver("d07", seats_total=1))
    requests = {p: dataclasses.replace(GRACE, passenger_id=p, max_price=400) for p in ("p042", "p043")}
    conversations = e.submit_many([(requests[p], AT) for p in order])
    run(e)
    return e, conversations


def test_last_seat_goes_to_the_first_request_and_the_other_is_told():
    e, _ = two_passengers_one_seat(["p042", "p043"])
    assert e.passenger("r-p042-1").state == CONFIRMED
    assert e.passenger("r-p043-1").state == NO_CREW
    loser = types(e, "r-p043-1")
    assert "BOOKING_FAILED" in loser and loser[-1] == "NO_CREW"


def test_arbitration_does_not_depend_on_submission_order():
    a, _ = two_passengers_one_seat(["p042", "p043"])
    b, _ = two_passengers_one_seat(["p043", "p042"])
    assert a.metrics().fingerprint == b.metrics().fingerprint


# --- Moteur et bus --------------------------------------------------------------------------------

def test_a_second_request_waits_for_the_first_to_finish():
    e = engine(d07())
    e.submit(GRACE, AT)
    with pytest.raises(ValueError):
        e.submit(GRACE, AT)
    run(e)
    assert e.submit(GRACE, AT) == "r-p042-2"


def test_naive_request_time_is_refused():
    with pytest.raises(ValueError):
        engine(d07()).submit(GRACE, datetime(2026, 11, 10, 6, 15))


def test_bus_refuses_unknown_receivers_and_duplicate_agents():
    bus = MessageBus()
    bus.register(d07())
    with pytest.raises(ValueError):
        bus.register(d07())
    bus.post(messages.draft("CFP", sender="coordinator", receiver="driver:inconnu", conversation_id="r-x-1",
                            in_reply_to=None, body={}), "2026-11-10T06:15:00+01:00")
    with pytest.raises(ValueError):
        asyncio.run(bus.run())


# --- Scénario S1 : déterminisme et performance ------------------------------------------------------

def run_s1(validate=False):
    e = s1_company_morning().build(validate=validate)
    run(e)
    return e


def test_s1_messages_are_all_valid():
    run_s1(validate=True)


def test_s1_gives_the_same_result_10_times():
    first = run_s1()
    reference = (first.metrics().fingerprint, first.assignments())
    for _ in range(9):
        e = run_s1()
        assert (e.metrics().fingerprint, e.assignments()) == reference


def test_s1_meets_the_grid_targets():
    m = run_s1().metrics()
    assert m.crews > 0
    assert m.elapsed_s < 2                 # convergence en moins de 2 secondes
    assert m.messages_per_crew < 20        # moins de 20 messages par équipage
    assert m.crews + m.no_crew == m.requests


# --- Réaffectation automatique quand le conducteur annule (US07) -------------------------------------

CANCEL_AT = datetime.fromisoformat("2026-11-10T06:30:00+01:00")


def booked_with_d03():
    """Grâce réserve chez d03 (meilleure offre) ; d07 reste disponible."""
    e = engine(d07(), d03())
    conv = e.submit(GRACE, AT)
    run(e)
    assert e.passenger(conv).booking["driver"] == "driver:d03"
    return e, conv


def test_passenger_is_reassigned_when_the_driver_cancels():
    e, conv = booked_with_d03()
    e.cancel_trip("d03", CANCEL_AT)
    run(e)
    assert types(e, conv)[-1] == "CREW_CANCELLED"
    passenger = e.passenger(conv)
    assert passenger.history == ["r-p042-1", "r-p042-2"]
    assert (passenger.state, passenger.booking["driver"]) == (CONFIRMED, "driver:d07")
    relaunch = e.conversation_log("r-p042-2")
    cancelled = e.conversation_log(conv)[-1]
    assert relaunch[0]["type"] == "RIDE_REQUEST" and relaunch[0]["in_reply_to"] == cancelled["id"]
    assert relaunch[0]["body"]["exclude_drivers"] == ["driver:d03"]
    assert relaunch[0]["body"]["parent_request_id"] == "r-p042-1"
    assert relaunch[-1]["type"] == "CREW_CONFIRMED"


def test_reassignment_takes_less_than_two_seconds():
    e, _ = booked_with_d03()
    e.cancel_trip("d03", CANCEL_AT)
    run(e)
    assert e.last_run_s < 2
    m = e.metrics()
    assert (m.cancelled_crews, m.renegotiations, m.reassigned, m.crews) == (1, 1, 1, 1)


def test_cancelled_driver_is_never_solicited_again():
    e, _ = booked_with_d03()
    e.cancel_trip("d03", CANCEL_AT)
    run(e)
    e.submit(dataclasses.replace(GRACE, passenger_id="p043"), AT)
    run(e)
    after = e.bus.log[[m["type"] for m in e.bus.log].index("TRIP_CANCELLED"):]
    assert all("driver:d03" not in m["body"].get("cfp_sent_to", []) for m in after)


def test_only_the_cancelled_driver_passengers_renegotiate():
    e = engine(d07(), d03(), driver("d05", departure="06:56", comfort=frozenset({"AIR_CONDITIONING"})))
    # p043 exclut d03 : les deux passagers ont des conducteurs différents.
    convs = e.submit_many([(GRACE, AT),
                           (dataclasses.replace(GRACE, passenger_id="p043", exclude_drivers=frozenset({"driver:d03"})), AT)])
    run(e)
    drivers = {c: e.passenger(c).booking["driver"] for c in convs}
    assert drivers[convs[0]] != drivers[convs[1]]
    cancelled_driver = drivers[convs[0]]
    e.cancel_trip(cancelled_driver.split(":")[1], CANCEL_AT)
    start = len(e.bus.log)
    run(e)
    concerned = {f"t-{cancelled_driver.split(':')[1]}"}
    for c in convs:
        if drivers[c] == cancelled_driver:
            concerned.update(e.passenger(c).history)
    assert {m["conversation_id"] for m in e.bus.log[start - 1:]} <= concerned


def test_second_cancellation_excludes_both_drivers():
    e, conv = booked_with_d03()
    e.cancel_trip("d03", CANCEL_AT)
    run(e)
    e.cancel_trip("d07", CANCEL_AT)
    run(e)
    passenger = e.passenger(conv)
    assert passenger.history == ["r-p042-1", "r-p042-2", "r-p042-3"]
    third = e.conversation_log("r-p042-3")
    assert third[0]["body"]["exclude_drivers"] == ["driver:d03", "driver:d07"]
    assert passenger.state == NO_CREW   # plus aucun conducteur


def test_driver_without_passengers_cancels_silently():
    e = engine(d07())
    e.cancel_trip("d07", CANCEL_AT)
    run(e)
    assert [m["type"] for m in e.bus.log] == ["TRIP_CANCELLED"]


def test_trip_cannot_be_cancelled_twice():
    e = engine(d07())
    e.cancel_trip("d07", CANCEL_AT)
    with pytest.raises(ValueError):
        e.cancel_trip("d07", CANCEL_AT)


def test_user_actions_refer_to_the_current_request():
    e = engine(d07(), d03(), driver("d05", departure="06:56"))
    conv = e.submit(dataclasses.replace(GRACE, mode="MANUAL"), AT)
    run(e)
    e.choose(conv, e.passenger(conv).proposals[0].offer_id)
    run(e)
    e.cancel_trip(e.passenger(conv).booking["driver"].split(":")[1], CANCEL_AT)
    run(e)
    assert e.passenger(conv).conversation_id == "r-p042-2"
    with pytest.raises(ValueError):
        e.withdraw(conv)          # l'ancienne demande est close
    e.withdraw("r-p042-2")
    run(e)
    assert e.passenger(conv).state == WITHDRAWN
