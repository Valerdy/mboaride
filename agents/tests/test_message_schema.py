"""Le format des messages entre agents est fixé par schemas/message.schema.json.

Ces tests vérifient que le schéma est valide, que les exemples de référence le
respectent, que la conversation nominale suit le protocole documenté
(docs/architecture-multi-agents.md) et que les messages mal formés sont refusés.
"""
import copy
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

SCHEMAS = Path(__file__).resolve().parent.parent / "schemas"
SCHEMA = json.loads((SCHEMAS / "message.schema.json").read_text(encoding="utf-8"))
EXAMPLES = json.loads((SCHEMAS / "examples.json").read_text(encoding="utf-8"))
VALIDATOR = Draft202012Validator(SCHEMA)
ALL_EXAMPLES = EXAMPLES["nominal"] + EXAMPLES["exceptions"]


def errors(message: dict) -> list[str]:
    return [e.message for e in VALIDATOR.iter_errors(message)]


def test_schema_is_valid_draft_2020_12():
    Draft202012Validator.check_schema(SCHEMA)


@pytest.mark.parametrize("message", ALL_EXAMPLES, ids=lambda m: f"{m['id']}-{m['type']}")
def test_reference_examples_are_valid(message):
    assert errors(message) == []


def test_every_message_type_has_a_route_and_an_example():
    types = set(SCHEMA["properties"]["type"]["enum"])
    routes = {k.removeprefix("route_") for k in SCHEMA["$defs"] if k.startswith("route_")}
    assert routes == types
    assert {m["type"] for m in ALL_EXAMPLES} == types


def test_message_ids_are_unique():
    ids = [m["id"] for m in ALL_EXAMPLES]
    assert len(ids) == len(set(ids))


class TestNominalConversation:
    conv = EXAMPLES["nominal"]

    def test_single_conversation_in_bus_order(self):
        assert {m["conversation_id"] for m in self.conv} == {"r-p042-1"}
        seqs = [m["seq"] for m in self.conv]
        assert seqs == sorted(seqs) and len(set(seqs)) == len(seqs)

    def test_replies_point_to_earlier_messages(self):
        seen = set()
        for m in self.conv:
            assert m["in_reply_to"] is None or m["in_reply_to"] in seen
            seen.add(m["id"])

    def test_steps_follow_the_protocol(self):
        types = [m["type"] for m in self.conv]
        assert types[:4] == ["RIDE_REQUEST", "CIRCLE_QUERY", "CIRCLE_ANSWER", "REQUEST_AGREED"]
        assert types[-3:] == ["ACCEPT", "BOOKING_CONFIRMED", "CREW_CONFIRMED"]

    def test_each_solicited_driver_gets_one_cfp_and_answers_once(self):
        agreed = next(m for m in self.conv if m["type"] == "REQUEST_AGREED")["body"]
        drivers = agreed["cfp_sent_to"]
        assert agreed["expected_replies"] == len(drivers)
        cfp_to = [m["receiver"] for m in self.conv if m["type"] == "CFP"]
        replies_from = [m["sender"] for m in self.conv if m["type"] in ("PROPOSAL", "DECLINE")]
        assert cfp_to == drivers
        assert sorted(replies_from) == sorted(drivers)

    def test_message_budget_is_7_plus_2k(self):
        k = next(m for m in self.conv if m["type"] == "REQUEST_AGREED")["body"]["expected_replies"]
        assert len(self.conv) == 7 + 2 * k
        assert len(self.conv) < 20

    def test_accepted_offer_is_the_one_confirmed(self):
        accept = next(m for m in self.conv if m["type"] == "ACCEPT")
        confirmed = next(m for m in self.conv if m["type"] == "CREW_CONFIRMED")
        offer = next(m for m in self.conv if m["type"] == "PROPOSAL" and m["body"]["offer_id"] == accept["body"]["offer_id"])
        assert accept["receiver"] == offer["sender"] == confirmed["body"]["driver"]
        assert confirmed["body"]["price"] == offer["body"]["price"]

    def test_proposal_price_matches_breakdown(self):
        for m in self.conv:
            if m["type"] == "PROPOSAL":
                b = m["body"]["price_breakdown"]
                expected = (b["fuel_cost"] + b["tolls"] + b["divisor"] // 2) // b["divisor"] + b["commission"]
                assert m["body"]["price"] == expected


def _example(type_: str) -> dict:
    return copy.deepcopy(next(m for m in ALL_EXAMPLES if m["type"] == type_))


def _mutate(type_, fn):
    message = _example(type_)
    fn(message)
    return message


INVALID = {
    "type inconnu": _mutate("CFP", lambda m: m.update(type="HELLO")),
    "propriété d'enveloppe en trop": _mutate("CFP", lambda m: m.update(priority=1)),
    "champ de corps en trop": _mutate("ACCEPT", lambda m: m["body"].update(note="vite")),
    "mauvaise version de protocole": _mutate("CFP", lambda m: m.update(protocol="mboaride-cnp/2")),
    "performative incohérente": _mutate("PROPOSAL", lambda m: m.update(performative="INFORM")),
    "PROPOSAL envoyé par le coordinateur": _mutate("PROPOSAL", lambda m: m.update(sender="coordinator")),
    "CFP adressé à un passager": _mutate("CFP", lambda m: m.update(receiver="passenger:p042")),
    "identifiant d'agent invalide": _mutate("ACCEPT", lambda m: m.update(sender="passager p042")),
    "prix décimal": _mutate("PROPOSAL", lambda m: m["body"].update(price=164.75)),
    "prix négatif": _mutate("RIDE_REQUEST", lambda m: m["body"].update(max_price=-1)),
    "date sans fuseau": _mutate("CFP", lambda m: m.update(sent_at="2026-11-10T06:15:00")),
    "champ obligatoire absent": _mutate("PROPOSAL", lambda m: m["body"].pop("detour_m")),
    "cercle inconnu": _mutate("CFP", lambda m: m["body"].update(circle="FAMILY")),
    "cercles en double": _mutate("RIDE_REQUEST", lambda m: m["body"].update(circles=["PUBLIC", "PUBLIC"])),
    "aucun cercle": _mutate("RIDE_REQUEST", lambda m: m["body"].update(circles=[])),
    "élève sans bloc élève": _mutate(
        "RIDE_REQUEST", lambda m: m["body"].update(passenger_kind="STUDENT")),
    "adulte avec bloc élève": _mutate(
        "RIDE_REQUEST", lambda m: m["body"].update(student={"age": 30, "parent_consent": True})),
    "motif de refus inconnu": _mutate("DECLINE", lambda m: m["body"].update(reason="TOO_FAR")),
    "tour 4": _mutate("ACCEPT", lambda m: m["body"].update(round=4)),
    "accord sans conducteur": _mutate("REQUEST_AGREED", lambda m: m["body"].update(cfp_sent_to=[])),
}


@pytest.mark.parametrize("message", INVALID.values(), ids=INVALID.keys())
def test_malformed_messages_are_rejected(message):
    assert errors(message) != []
