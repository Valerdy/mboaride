"""Agent organisation : autorise ou refuse un membre dans le cercle de son organisation."""
import asyncio
import copy
import json
from pathlib import Path

import pytest

from mboaride_agents import messages
from mboaride_agents.organization import OrganizationAgent

EXAMPLES = json.loads((Path(__file__).resolve().parent.parent / "schemas" / "examples.json").read_text(encoding="utf-8"))
QUERY = next(m for m in EXAMPLES["nominal"] if m["type"] == "CIRCLE_QUERY")   # Grâce, adulte


def org(**changes) -> OrganizationAgent:
    args = dict(members=["passenger:p042", "passenger:e015", "passenger:e019"],
                partners=["organization:partenaire-01"], price_cap=500)
    args.update(changes)
    return OrganizationAgent("entreprise-test", **args)


def query(**body) -> dict:
    m = copy.deepcopy(QUERY)
    m["body"].update(body)
    return m


def answer(agent: OrganizationAgent, message: dict) -> dict:
    (reply,) = asyncio.run(agent.handle(message))
    stamped = messages.stamp(reply, seq=message["seq"] + 1, sent_at=message["sent_at"])
    assert messages.validation_errors(stamped) == []
    return stamped


def test_reproduces_the_documented_answer():
    out = answer(org(), QUERY)
    expected = next(m for m in EXAMPLES["nominal"] if m["type"] == "CIRCLE_ANSWER")
    assert out == {**expected, "id": out["id"], "seq": out["seq"]}


REFUSALS = {
    "non membre": (dict(passenger="passenger:p999"), {}, "NOT_MEMBER"),
    "membre suspendu": ({}, dict(suspended=["passenger:p042"]), "SUSPENDED"),
    "élève de moins de 12 ans": (dict(passenger="passenger:e019", passenger_kind="STUDENT",
                                      student={"age": 11, "parent_consent": True}), {}, "STUDENT_UNDER_12"),
    "élève sans autorisation parentale": (dict(passenger="passenger:e015", passenger_kind="STUDENT",
                                               student={"age": 15, "parent_consent": False}), {}, "NO_PARENTAL_CONSENT"),
}


@pytest.mark.parametrize("body, org_changes, reason", REFUSALS.values(), ids=REFUSALS.keys())
def test_refusals(body, org_changes, reason):
    out = answer(org(**org_changes), query(**body))
    assert out["body"] == {"authorized": False, "reason": reason, "price_cap": None, "partner_organizations": []}


def test_student_aged_12_with_consent_is_authorized():
    out = answer(org(), query(passenger="passenger:e015", passenger_kind="STUDENT",
                              student={"age": 12, "parent_consent": True}))
    assert out["body"]["authorized"] is True


def test_answer_goes_back_to_the_coordinator():
    out = answer(org(), QUERY)
    assert (out["receiver"], out["in_reply_to"], out["conversation_id"]) == ("coordinator", QUERY["id"], QUERY["conversation_id"])


@pytest.mark.parametrize("changes", [
    dict(members=["p042"]), dict(partners=["partenaire-01"]), dict(price_cap=-1),
    dict(partners=["organization:entreprise-test"]),
])
def test_invalid_configuration_is_rejected(changes):
    with pytest.raises(ValueError):
        org(**changes)


def test_other_messages_are_refused():
    wrong = query()
    wrong["receiver"] = "organization:autre"
    with pytest.raises(ValueError):
        asyncio.run(org().handle(wrong))
