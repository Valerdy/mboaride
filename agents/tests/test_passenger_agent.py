"""Agent passager : classe les offres selon ses exigences, puis accepte (autonome) ou propose (manuel)."""
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
from mboaride_agents.passenger import (
    ACCEPTING, AWAITING_USER, CONFIRMED, NO_CREW, SUBMITTED, WITHDRAWN,
    ArrivalWindow, PassengerAgent, PassengerRequest, ScoreWeights, Student, offer_rejection, rank_offers, score_offer,
)
from mboaride_agents.routing import EstimatedRouting, Point

SCHEMAS = Path(__file__).resolve().parent.parent / "schemas"
EXAMPLES = json.loads((SCHEMAS / "examples.json").read_text(encoding="utf-8"))
NOMINAL = {m["id"]: m for m in EXAMPLES["nominal"]}
EXCEPTIONS = {m["id"]: m for m in EXAMPLES["exceptions"]}

# Grâce : Kotto -> Bonanjo, arrivée 7 h 30 - 7 h 50 (visée 7 h 40), 300 FCFA au plus, climatisation souhaitée.
GRACE = PassengerRequest.from_body("p042", NOMINAL["m-1"]["body"])
D07_OFFER = NOMINAL["m-8"]["body"]   # score 0,6225
D03_OFFER = NOMINAL["m-9"]["body"]   # score 0,35


def make_agent(**changes) -> PassengerAgent:
    return PassengerAgent(dataclasses.replace(GRACE, **changes), "r-p042-1")


def send(agent: PassengerAgent, message: dict) -> list[dict]:
    """Livre un message à l'agent ; renvoie ses réponses tamponnées et vérifiées contre le schéma."""
    out = []
    for i, d in enumerate(asyncio.run(agent.handle(message)), start=1):
        stamped = messages.stamp(d, seq=message["seq"] + i, sent_at=message["sent_at"])
        assert messages.validation_errors(stamped) == []
        out.append(stamped)
    return out


def user(drafts: list[dict], seq: int = 500) -> list[dict]:
    """Messages produits par une action de l'utilisateur, tamponnés et vérifiés."""
    out = [messages.stamp(d, seq=seq + i, sent_at="2026-11-10T06:16:00+01:00") for i, d in enumerate(drafts)]
    assert all(messages.validation_errors(m) == [] for m in out)
    return out


def agreed(drivers, round_=1, circle="ORGANIZATION", seq=4) -> dict:
    m = copy.deepcopy(NOMINAL["m-4"])
    m.update(id=f"m-{seq}", seq=seq)
    m["body"] = {"round": round_, "circle": circle, "cfp_sent_to": list(drivers), "expected_replies": len(drivers)}
    return m


def proposal(driver, seq, round_=1, **changes) -> dict:
    m = copy.deepcopy(NOMINAL["m-8"])
    local = driver.split(":")[1]
    m.update(id=f"m-{seq}", seq=seq, sender=driver)
    m["body"].update(offer_id=f"o-{local}-r-p042-1" + (f"-{round_}" if round_ > 1 else ""), round=round_)
    m["body"].update(changes)
    return m


def decline(driver, seq, round_=1, reason="DETOUR_TOO_LONG") -> dict:
    m = copy.deepcopy(NOMINAL["m-10"])
    m.update(id=f"m-{seq}", seq=seq, sender=driver)
    m["body"] = {"round": round_, "reason": reason}
    return m


def booking_failed(proposal_msg, seq) -> dict:
    m = copy.deepcopy(EXCEPTIONS["m-201"])
    m.update(id=f"m-{seq}", seq=seq, conversation_id="r-p042-1", in_reply_to=f"m-{seq - 1}",
             sender=proposal_msg["sender"], receiver="passenger:p042")
    m["body"] = {"offer_id": proposal_msg["body"]["offer_id"], "reason": "SEAT_TAKEN"}
    return m


def run_round(agent, replies, drivers=None, round_=1, circle="ORGANIZATION") -> list[dict]:
    """Ouvre un tour puis livre les réponses ; renvoie ce que l'agent envoie après la dernière."""
    drivers = drivers or [r["sender"] for r in replies]
    assert send(agent, agreed(drivers, round_, circle, seq=replies[0]["seq"] - 1)) == []
    for r in replies[:-1]:
        assert send(agent, r) == []
    return send(agent, replies[-1])


# --- Conformité au protocole documenté --------------------------------------------------------

def test_replays_the_documented_negotiation():
    agent = PassengerAgent(GRACE, "r-p042-1")
    assert messages.stamp(agent.start(), seq=1, sent_at=NOMINAL["m-1"]["sent_at"]) == NOMINAL["m-1"]
    assert send(agent, NOMINAL["m-4"]) == []
    assert send(agent, NOMINAL["m-8"]) == []
    assert send(agent, NOMINAL["m-9"]) == []
    out = send(agent, NOMINAL["m-10"])
    assert out == [{**NOMINAL["m-11"], "id": out[0]["id"], "seq": out[0]["seq"]}]
    assert [o.driver for o in agent.ranking] == ["driver:d07", "driver:d03"]
    assert agent.state == ACCEPTING
    assert send(agent, NOMINAL["m-13"]) == []
    assert agent.state == CONFIRMED
    assert agent.booking == NOMINAL["m-13"]["body"]


def test_documented_scores_are_exact():
    assert score_offer(GRACE, D07_OFFER) == Fraction(249, 400)   # 0,6225
    assert score_offer(GRACE, D03_OFFER) == Fraction(7, 20)      # 0,35


def test_same_negotiation_gives_same_messages_10_times():
    def run():
        agent = PassengerAgent(GRACE, "r-p042-1")
        agent.start()
        return [send(agent, NOMINAL[i]) for i in ("m-4", "m-8", "m-9", "m-10", "m-13")]
    first = run()
    assert all(run() == first for _ in range(9))


# --- Exigences du passager : contraintes dures ---------------------------------------------------

REJECTIONS = {
    "prix au-dessus du maximum": ({}, dict(price=301), "PRICE_TOO_HIGH"),
    "arrivée après la fenêtre": ({}, dict(dropoff_time="2026-11-10T07:51:00+01:00"), "OUTSIDE_WINDOW"),
    "arrivée avant la fenêtre": ({}, dict(dropoff_time="2026-11-10T07:29:00+01:00"), "OUTSIDE_WINDOW"),
    "confort obligatoire absent": (dict(comfort_required=frozenset({"QUIET"})), {}, "COMFORT_MISSING"),
    "cercle non accepté": (dict(circles=("ORGANIZATION",)), dict(circle="PUBLIC"), "CIRCLE_NOT_ACCEPTED"),
    "conducteur exclu": (dict(exclude_drivers=frozenset({"driver:d07"})), {}, "EXCLUDED_DRIVER"),
    "détour au-dessus du maximum annoncé": ({}, dict(detour_m=3100), "DETOUR_ABOVE_MAX"),
}


@pytest.mark.parametrize("request_changes, offer_changes, reason", REJECTIONS.values(), ids=REJECTIONS.keys())
def test_offer_breaking_a_requirement_is_rejected(request_changes, offer_changes, reason):
    request = dataclasses.replace(GRACE, **request_changes)
    assert offer_rejection(request, {**D07_OFFER, **offer_changes}, "driver:d07") == reason


@pytest.mark.parametrize("offer_changes", [
    dict(price=300), dict(dropoff_time="2026-11-10T07:50:00+01:00"), dict(dropoff_time="2026-11-10T07:30:00+01:00"),
    dict(detour_m=3000), dict(circle="PUBLIC"),
], ids=["prix égal au max", "dernière minute", "première minute", "détour égal au max", "cercle public accepté"])
def test_limits_are_inclusive(offer_changes):
    assert offer_rejection(GRACE, {**D07_OFFER, **offer_changes}, "driver:d07") is None


def test_rejected_offers_are_reported_with_their_reason():
    ranked, rejected = rank_offers(GRACE, [proposal("driver:d07", 8), proposal("driver:d03", 9, price=400)])
    assert [o.driver for o in ranked] == ["driver:d07"]
    assert rejected == [("driver:d03", "PRICE_TOO_HIGH")]


# --- Classement : score puis départage -------------------------------------------------------------

def test_each_score_term_favours_the_better_offer():
    better = {
        "détour": dict(detour_m=500),
        "heure": dict(dropoff_time="2026-11-10T07:40:00+01:00"),
        "prix": dict(price=100),
        "confort": dict(comfort_offered=["AIR_CONDITIONING", "QUIET"]),
        "cercle": dict(),
    }
    worse = {**D07_OFFER, "detour_m": 2000, "dropoff_time": "2026-11-10T07:48:00+01:00", "price": 250,
             "comfort_offered": [], "circle": "PARTNERS"}
    for term, change in better.items():
        improved = {**worse, **change} if term != "cercle" else {**worse, "circle": "ORGANIZATION"}
        assert score_offer(GRACE, improved) > score_offer(GRACE, worse), term


def test_time_term_never_goes_negative():
    # Heure visée décentrée : 7 h 50 est à 15 min de 7 h 35, plus que la demi-fenêtre (10 min).
    window = ArrivalWindow(*(datetime.fromisoformat(f"2026-11-10T07:{m}:00+01:00") for m in (30, 35, 50)))
    request = dataclasses.replace(GRACE, arrival_window=window, weights=ScoreWeights(0, 1, 0, 0, 0))
    assert score_offer(request, {**D07_OFFER, "dropoff_time": "2026-11-10T07:50:00+01:00"}) == 0


def test_zero_width_window_scores_exact_arrival():
    t = datetime.fromisoformat("2026-11-10T07:40:00+01:00")
    request = dataclasses.replace(GRACE, arrival_window=ArrivalWindow(t, t, t), weights=ScoreWeights(0, 1, 0, 0, 0))
    assert score_offer(request, {**D07_OFFER, "dropoff_time": "2026-11-10T07:40:00+01:00"}) == 1


def test_no_preferred_comfort_is_neutral():
    request = dataclasses.replace(GRACE, comfort_preferred=frozenset())
    assert score_offer(request, {**D07_OFFER, "comfort_offered": []}) == score_offer(request, D07_OFFER)


def test_user_weights_change_the_ranking():
    cheap_far = proposal("driver:d01", 8, price=100, detour_m=2500)
    dear_near = proposal("driver:d02", 9, price=280, detour_m=200)
    by_price = dataclasses.replace(GRACE, weights=ScoreWeights(detour=0, time=0, price=1, comfort=0, circle=0))
    by_detour = dataclasses.replace(GRACE, weights=ScoreWeights(detour=1, time=0, price=0, comfort=0, circle=0))
    assert rank_offers(by_price, [cheap_far, dear_near])[0][0].driver == "driver:d01"
    assert rank_offers(by_detour, [cheap_far, dear_near])[0][0].driver == "driver:d02"


NO_DETOUR_WEIGHT = dataclasses.replace(GRACE, weights=ScoreWeights(detour=0, time=0.25, price=0.25, comfort=0.25, circle=0.25))


def test_tie_broken_by_smallest_detour():
    a, b = proposal("driver:d05", 8, detour_m=1000), proposal("driver:d02", 9, detour_m=2000)
    ranked, _ = rank_offers(NO_DETOUR_WEIGHT, [b, a])
    assert ranked[0].score == ranked[1].score
    assert [o.driver for o in ranked] == ["driver:d05", "driver:d02"]


def test_tie_broken_by_earliest_departure():
    a = proposal("driver:d05", 8, departure_time="2026-11-10T06:50:00+01:00")
    b = proposal("driver:d02", 9, departure_time="2026-11-10T06:55:00+01:00")
    assert [o.driver for o in rank_offers(GRACE, [b, a])[0]] == ["driver:d05", "driver:d02"]


def test_tie_broken_by_smallest_driver_id():
    a, b = proposal("driver:d05", 8), proposal("driver:d02", 9)
    assert [o.driver for o in rank_offers(GRACE, [a, b])[0]] == ["driver:d02", "driver:d05"]


def test_ranking_does_not_depend_on_arrival_order():
    offers = [proposal(f"driver:d0{i}", 10 + i, price=150 + 10 * i, detour_m=300 * i) for i in range(1, 6)]
    expected = [o.driver for o in rank_offers(GRACE, offers)[0]]
    assert [o.driver for o in rank_offers(GRACE, list(reversed(offers)))[0]] == expected


# --- Décision, échecs et tours suivants -------------------------------------------------------------

def test_all_declined_asks_coordinator_to_widen():
    agent = make_agent()
    agent.start()
    out = run_round(agent, [decline("driver:d07", 5), decline("driver:d03", 6)])
    assert [(m["type"], m["receiver"], m["body"]) for m in out] == [
        ("NO_ACCEPTABLE_OFFER", "coordinator", {"round": 1, "reason": "ALL_DECLINED"})]
    assert out[0]["in_reply_to"] == "m-6"
    assert agent.state == SUBMITTED


def test_no_acceptable_offer_when_every_proposal_breaks_a_requirement():
    agent = make_agent()
    agent.start()
    out = run_round(agent, [proposal("driver:d07", 5, price=400), decline("driver:d03", 6)])
    assert out[0]["body"] == {"round": 1, "reason": "NONE_ACCEPTABLE"}
    assert agent.rejected == [("driver:d07", "PRICE_TOO_HIGH")]


def test_seat_taken_moves_to_the_next_offer_then_gives_up():
    agent = make_agent()
    agent.start()
    p07, p03 = proposal("driver:d07", 5), proposal("driver:d03", 6, **{k: D03_OFFER[k] for k in ("price", "detour_m", "dropoff_time")})
    first = run_round(agent, [p07, p03])
    assert first[0]["receiver"] == "driver:d07"
    second = send(agent, booking_failed(p07, 8))
    assert (second[0]["type"], second[0]["receiver"], second[0]["in_reply_to"]) == ("ACCEPT", "driver:d03", "m-6")
    third = send(agent, booking_failed(p03, 10))
    assert third[0]["type"] == "NO_ACCEPTABLE_OFFER" and third[0]["body"]["reason"] == "ALL_FAILED"


def test_second_round_forgets_first_round_offers():
    agent = make_agent()
    agent.start()
    run_round(agent, [proposal("driver:d07", 5, price=400)])
    out = run_round(agent, [proposal("driver:d20", 11, round_=2, circle="PARTNERS")], round_=2, circle="PARTNERS")
    assert (out[0]["type"], out[0]["receiver"], out[0]["body"]["round"]) == ("ACCEPT", "driver:d20", 2)
    assert [o.driver for o in agent.ranking] == ["driver:d20"]


def test_no_crew_ends_the_request():
    agent = make_agent()
    agent.start()
    run_round(agent, [decline("driver:d07", 5)])
    no_crew = copy.deepcopy(EXCEPTIONS["m-402"])
    no_crew.update(conversation_id="r-p042-1", receiver="passenger:p042")
    assert send(agent, no_crew) == []
    assert agent.state == NO_CREW
    assert agent.failure == no_crew["body"]


# --- Mode manuel ----------------------------------------------------------------------------------

def manual_agent_with_offers():
    agent = make_agent(mode="MANUAL")
    agent.start()
    offers = [proposal(f"driver:d0{i}", 4 + i, price=100 + 40 * i) for i in range(1, 5)]
    assert run_round(agent, offers) == []
    return agent


def test_manual_mode_shows_the_three_best_offers():
    agent = manual_agent_with_offers()
    assert agent.state == AWAITING_USER
    assert [o.driver for o in agent.proposals] == ["driver:d01", "driver:d02", "driver:d03"]


def test_manual_user_choice_is_accepted():
    agent = manual_agent_with_offers()
    out = user(agent.choose("o-d03-r-p042-1"))
    assert (out[0]["type"], out[0]["receiver"], out[0]["in_reply_to"]) == ("ACCEPT", "driver:d03", "m-7")


def test_manual_user_cannot_choose_an_offer_not_shown():
    with pytest.raises(ValueError):
        manual_agent_with_offers().choose("o-d04-r-p042-1")


def test_manual_user_can_ask_to_widen():
    out = user(manual_agent_with_offers().widen())
    assert out[0]["type"] == "NO_ACCEPTABLE_OFFER" and out[0]["body"]["reason"] == "USER_ASKED_WIDENING"


def test_manual_user_can_decline_all():
    agent = manual_agent_with_offers()
    out = user(agent.withdraw())
    assert out[0]["type"] == "REQUEST_WITHDRAWN" and out[0]["body"] == {"reason": "USER_DECLINED_ALL"}
    assert agent.state == WITHDRAWN


def test_manual_seat_taken_shows_the_remaining_offers():
    agent = manual_agent_with_offers()
    chosen = agent.proposals[0].proposal
    agent.choose(chosen["body"]["offer_id"])
    assert send(agent, booking_failed(chosen, 20)) == []
    assert [o.driver for o in agent.proposals] == ["driver:d02", "driver:d03", "driver:d04"]


def test_withdraw_before_any_offer():
    agent = make_agent()
    agent.start()
    assert user(agent.withdraw())[0]["body"] == {"reason": "USER_CANCELLED"}


# --- Demande : format et validation ----------------------------------------------------------------

@pytest.mark.parametrize("message", [NOMINAL["m-1"], EXCEPTIONS["m-904"], EXCEPTIONS["m-950"]], ids=lambda m: m["id"])
def test_request_body_round_trip(message):
    passenger = message["sender"].split(":")[1]
    assert PassengerRequest.from_body(passenger, message["body"]).to_body() == message["body"]


def test_custom_weights_round_trip():
    request = dataclasses.replace(GRACE, weights=ScoreWeights(0.1, 0.2, 0.5, 0.1, 0.1))
    assert PassengerRequest.from_body("p042", request.to_body()) == request


@pytest.mark.parametrize("changes", [
    dict(max_price=-1), dict(seats=0), dict(circles=()), dict(circles=("PUBLIC", "PUBLIC")),
    dict(circles=("FAMILY",)), dict(organization_id=None), dict(organization_id="entreprise-test"),
    dict(mode="AUTO"), dict(comfort_preferred=frozenset({"JACUZZI"})), dict(passenger_kind="STUDENT"),
    dict(student=Student(15, True)), dict(exclude_drivers=frozenset({"d07"})),
], ids=lambda c: next(iter(c)))
def test_invalid_request_is_rejected(changes):
    with pytest.raises(ValueError):
        dataclasses.replace(GRACE, **changes)


def test_public_only_passenger_needs_no_organization():
    request = dataclasses.replace(GRACE, organization_id=None, circles=("PUBLIC",))
    assert request.to_body()["organization_id"] is None


@pytest.mark.parametrize("bad", [
    ("2026-11-10T07:30:00", "2026-11-10T07:40:00+01:00", "2026-11-10T07:50:00+01:00"),
    ("2026-11-10T07:45:00+01:00", "2026-11-10T07:40:00+01:00", "2026-11-10T07:50:00+01:00"),
])
def test_invalid_window_is_rejected(bad):
    with pytest.raises(ValueError):
        ArrivalWindow(*(datetime.fromisoformat(t) for t in bad))


@pytest.mark.parametrize("weights", [(0.5, 0.5, 0.5, 0, 0), (1.2, -0.2, 0, 0, 0)])
def test_invalid_weights_are_rejected(weights):
    with pytest.raises(ValueError):
        ScoreWeights(*weights)


# --- Garde-fous du protocole ---------------------------------------------------------------------------

def started_round(drivers=("driver:d07", "driver:d03")):
    agent = make_agent()
    agent.start()
    send(agent, agreed(drivers))
    return agent


@pytest.mark.parametrize("message", [
    proposal("driver:d99", 5),                 # conducteur non sollicité
    proposal("driver:d07", 5, round_=2),       # mauvais tour
], ids=["non sollicité", "mauvais tour"])
def test_unexpected_reply_is_refused(message):
    with pytest.raises(ValueError):
        send(started_round(), message)


def test_duplicate_reply_is_refused():
    agent = started_round()
    send(agent, proposal("driver:d07", 5))
    with pytest.raises(ValueError):
        send(agent, proposal("driver:d07", 6))


def test_reply_before_agreement_is_refused():
    agent = make_agent()
    agent.start()
    with pytest.raises(ValueError):
        send(agent, proposal("driver:d07", 5))


def test_agreement_with_inconsistent_count_is_refused():
    agent = make_agent()
    agent.start()
    bad = agreed(["driver:d07"])
    bad["body"]["expected_replies"] = 2
    with pytest.raises(ValueError):
        send(agent, bad)


def test_message_for_someone_else_is_refused():
    agent = started_round()
    other = proposal("driver:d07", 5)
    other["receiver"] = "passenger:p051"
    with pytest.raises(ValueError):
        send(agent, other)
    other = proposal("driver:d07", 5)
    other["conversation_id"] = "r-p042-2"
    with pytest.raises(ValueError):
        send(agent, other)


def test_message_types_not_handled_yet_are_refused():
    with pytest.raises(ValueError):
        send(started_round(), EXCEPTIONS["m-901"])   # CREW_CANCELLED


def test_request_is_sent_only_once():
    agent = make_agent()
    agent.start()
    with pytest.raises(ValueError):
        agent.start()


# --- Avec de vrais agents conducteurs ----------------------------------------------------------------

def test_passenger_and_driver_agents_negotiate_together():
    """Le test joue le coordinateur : il diffuse l'appel d'offres et relaie les messages."""
    def driver(local, origin, departure):
        trip = DriverTrip(f"t-{local}", origin=origin, destination=Point(4.0440, 9.6935),
                          departure_time=datetime.fromisoformat(f"2026-11-10T{departure}:00+01:00"))
        profile = DriverProfile(local, trip, seats_total=3, max_detour_m=3000,
                                comfort=frozenset({"AIR_CONDITIONING"}) if local == "d07" else frozenset())
        return DriverAgent(profile, EstimatedRouting())

    drivers = [driver("d03", Point(4.0850, 9.7800), "07:00"),   # Logbessou : arrive à 7 h 41, sans climatisation
               driver("d07", Point(4.0790, 9.7740), "06:55"),   # Logpom : arrive à 7 h 33, climatisé
               driver("d12", Point(4.0700, 9.6600), "07:00")]   # Bonabéri : détour trop long
    passenger = PassengerAgent(GRACE, "r-p042-1")
    seq = 1
    request = messages.stamp(passenger.start(), seq=seq, sent_at="2026-11-10T06:15:00+01:00")

    agreement = agreed([d.agent_id for d in drivers], seq=4)
    send(passenger, agreement)
    cfp_body = {k: request["body"][k] for k in ("passenger_kind", "origin", "destination", "trip_kind",
                                                 "arrival_window", "max_price", "seats")}
    cfp_body.update(round=1, circle="ORGANIZATION", reply_to=passenger.agent_id,
                    comfort_required=request["body"]["comfort"]["required"])

    answers, seq = [], 5
    for d in drivers:
        cfp = messages.stamp(messages.draft("CFP", sender="coordinator", receiver=d.agent_id,
                                            conversation_id="r-p042-1", in_reply_to="m-3", body=cfp_body),
                             seq=seq, sent_at=request["sent_at"])
        assert messages.validation_errors(cfp) == []
        answers.append(messages.stamp(asyncio.run(d.handle(cfp))[0], seq=seq + len(drivers), sent_at=request["sent_at"]))
        seq += 1

    outputs = [send(passenger, a) for a in answers]
    assert [a["type"] for a in answers] == ["PROPOSAL", "PROPOSAL", "DECLINE"]
    # d03 arrive presque à l'heure visée (7 h 40) : ce terme l'emporte sur la climatisation de d07.
    assert [o.driver for o in passenger.ranking] == ["driver:d03", "driver:d07"]
    accept = outputs[-1][0]
    assert (accept["type"], accept["receiver"]) == ("ACCEPT", "driver:d03")
