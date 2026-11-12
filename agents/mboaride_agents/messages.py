"""Construction des messages du protocole mboaride-cnp/1.

Un agent produit un *brouillon* (destinataire, type, corps...). Le bus de messages
le *tamponne* ensuite : il lui attribue son numéro d'ordre `seq`, son identifiant
et l'heure simulée. Le format complet est fixé par schemas/message.schema.json.
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

PROTOCOL = "mboaride-cnp/1"
SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schemas" / "message.schema.json"
COORDINATOR = "coordinator"

# Vocabulaire commun aux agents (valeurs autorisées par le schéma).
CIRCLES = ("ORGANIZATION", "PARTNERS", "PUBLIC")  # du plus proche au plus large
COMFORTS = frozenset({"AIR_CONDITIONING", "NON_SMOKING", "QUIET", "LUGGAGE_SPACE"})
TRIP_KINDS = frozenset({"URBAN", "INTERURBAN"})

# Performatif FIPA imposé par chaque type de message (identique au schéma).
PERFORMATIVES: dict[str, str] = {
    "RIDE_REQUEST": "REQUEST",
    "CIRCLE_QUERY": "QUERY_IF",
    "CIRCLE_ANSWER": "INFORM",
    "REQUEST_AGREED": "AGREE",
    "CFP": "CFP",
    "PROPOSAL": "PROPOSE",
    "DECLINE": "REFUSE",
    "ACCEPT": "ACCEPT_PROPOSAL",
    "BOOKING_CONFIRMED": "CONFIRM",
    "BOOKING_FAILED": "FAILURE",
    "CREW_CONFIRMED": "INFORM",
    "NO_ACCEPTABLE_OFFER": "INFORM",
    "NO_CREW": "FAILURE",
    "REQUEST_WITHDRAWN": "CANCEL",
    "TRIP_CANCELLED": "CANCEL",
    "CREW_CANCELLED": "INFORM",
    "DELAY_REPORTED": "INFORM",
    "ETA_UPDATED": "INFORM",
    "BOOKING_CANCELLED": "CANCEL",
    "SEAT_RELEASED": "INFORM",
}

Message = dict[str, Any]


def agent_id(role: str, local_id: str) -> str:
    """`agent_id("driver", "d07")` -> `"driver:d07"`."""
    return f"{role}:{local_id}"


def draft(type_: str, *, sender: str, receiver: str, conversation_id: str,
          in_reply_to: str | None, body: dict[str, Any]) -> Message:
    """Brouillon de message, sans `protocol`, `id`, `seq` ni `sent_at`."""
    return {
        "conversation_id": conversation_id,
        "in_reply_to": in_reply_to,
        "type": type_,
        "performative": PERFORMATIVES[type_],
        "sender": sender,
        "receiver": receiver,
        "body": body,
    }


def reply(to: Message, type_: str, *, sender: str, receiver: str, body: dict[str, Any]) -> Message:
    """Brouillon de réponse : même conversation, `in_reply_to` = message reçu."""
    return draft(type_, sender=sender, receiver=receiver, conversation_id=to["conversation_id"],
                 in_reply_to=to["id"], body=body)


def stamp(message_draft: Message, *, seq: int, sent_at: str) -> Message:
    """Message complet, tel que le bus le livre (ordre des clés fixe)."""
    return {
        "protocol": PROTOCOL,
        "id": f"m-{seq}",
        "seq": seq,
        "conversation_id": message_draft["conversation_id"],
        "in_reply_to": message_draft["in_reply_to"],
        "type": message_draft["type"],
        "performative": message_draft["performative"],
        "sender": message_draft["sender"],
        "receiver": message_draft["receiver"],
        "sent_at": sent_at,
        "body": message_draft["body"],
    }


@lru_cache(maxsize=1)
def _validator():
    from jsonschema import Draft202012Validator  # import tardif : inutile hors tests et débogage

    return Draft202012Validator(json.loads(SCHEMA_PATH.read_text(encoding="utf-8")))


def validation_errors(message: Message) -> list[str]:
    """Écarts d'un message complet au schéma (liste vide si conforme)."""
    return [error.message for error in _validator().iter_errors(message)]
