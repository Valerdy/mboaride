"""Agent organisation : autorise ou refuse un membre dans le cercle de son organisation.

Une organisation est une entreprise, une école partenaire, un campus ou un événement.
Elle répond à CIRCLE_QUERY par CIRCLE_ANSWER, avec son plafond de prix et la liste de
ses organisations partenaires (utilisée par le coordinateur pour le cercle PARTNERS).
Voir docs/architecture-multi-agents.md, section 2.
"""
from __future__ import annotations

from collections.abc import Iterable

from . import messages

MIN_STUDENT_AGE = 12


class OrganizationAgent:
    def __init__(self, organization_id: str, *, members: Iterable[str], partners: Iterable[str] = (),
                 price_cap: int | None = None, suspended: Iterable[str] = ()):
        """
        organization_id : identifiant local ("entreprise-test") ;
        members, suspended : identifiants d'agents passagers ("passenger:p042") ;
        partners : identifiants d'agents organisations ("organization:partenaire-01").
        """
        self.organization_id = organization_id
        self.members = frozenset(members)
        self.partners = tuple(sorted(set(partners)))
        self.price_cap = price_cap
        self.suspended = frozenset(suspended)
        if price_cap is not None and price_cap < 0:
            raise ValueError("price_cap doit être positif ou nul")
        if any(not m.startswith("passenger:") for m in self.members | self.suspended):
            raise ValueError("members et suspended contiennent des identifiants passenger:<id>")
        if any(not p.startswith("organization:") for p in self.partners):
            raise ValueError("partners contient des identifiants organization:<id>")
        if self.agent_id in self.partners:
            raise ValueError("Une organisation ne peut pas être sa propre partenaire")

    @property
    def agent_id(self) -> str:
        return messages.agent_id("organization", self.organization_id)

    async def handle(self, message: messages.Message) -> list[messages.Message]:
        if message["receiver"] != self.agent_id:
            raise ValueError(f"{self.agent_id} a reçu un message destiné à {message['receiver']}")
        if message["type"] != "CIRCLE_QUERY":
            raise ValueError(f"L'agent organisation ne traite pas les messages {message['type']}")
        reason = self.refusal(message["body"])
        body = {
            "authorized": reason is None,
            "reason": reason,
            "price_cap": self.price_cap if reason is None else None,
            "partner_organizations": list(self.partners) if reason is None else [],
        }
        return [messages.reply(message, "CIRCLE_ANSWER", sender=self.agent_id, receiver=message["sender"], body=body)]

    def refusal(self, query: dict) -> str | None:
        """Motif de refus du passager, ou None s'il est autorisé."""
        passenger = query["passenger"]
        if passenger in self.suspended:
            return "SUSPENDED"
        if passenger not in self.members:
            return "NOT_MEMBER"
        if query["passenger_kind"] == "STUDENT":
            student = query["student"]
            if student["age"] < MIN_STUDENT_AGE:
                return "STUDENT_UNDER_12"
            if not student["parent_consent"]:
                return "NO_PARENTAL_CONSENT"
        return None
