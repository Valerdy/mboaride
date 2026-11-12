"""Bus de messages déterministe (docs/architecture-multi-agents.md, section 3).

- Une seule file : chaque message reçoit un numéro `seq` croissant à l'envoi et les
  messages sont livrés dans cet ordre.
- Un message à la fois : le bus attend la fin du traitement d'un message (appel
  d'itinéraire compris) avant de livrer le suivant.
- Pas d'horloge : `sent_at` est l'heure simulée ; une réponse hérite de l'heure du
  message qui l'a provoquée.
- Tout est journalisé : le journal sert aux mesures et à l'empreinte d'exécution.
"""
from __future__ import annotations

import hashlib
import json
from collections import deque
from typing import Protocol

from . import messages


class Agent(Protocol):
    agent_id: str

    async def handle(self, message: messages.Message) -> list[messages.Message]: ...


class MessageBus:
    def __init__(self, validate: bool = False):
        """validate=True vérifie chaque message contre le schéma (tests, débogage ; plus lent)."""
        self.validate = validate
        self.agents: dict[str, Agent] = {}
        self.queue: deque[messages.Message] = deque()
        self.log: list[messages.Message] = []
        self._seq = 0

    def register(self, agent: Agent, *, replace: bool = False) -> None:
        if agent.agent_id in self.agents and not replace:
            raise ValueError(f"{agent.agent_id} est déjà inscrit sur le bus")
        self.agents[agent.agent_id] = agent

    def post(self, message_draft: messages.Message, sent_at: str) -> messages.Message:
        """Tamponne un brouillon (numéro d'ordre, identifiant, heure) et le met en file."""
        self._seq += 1
        message = messages.stamp(message_draft, seq=self._seq, sent_at=sent_at)
        if self.validate:
            errors = messages.validation_errors(message)
            if errors:
                raise ValueError(f"Message {message['type']} non conforme au schéma : {errors}")
        self.queue.append(message)
        self.log.append(message)
        return message

    async def run(self) -> int:
        """Livre les messages jusqu'à ce que la file soit vide ; renvoie le nombre de messages livrés."""
        delivered = 0
        while self.queue:
            message = self.queue.popleft()
            agent = self.agents.get(message["receiver"])
            if agent is None:
                raise ValueError(f"Destinataire inconnu sur le bus : {message['receiver']}")
            for reply in await agent.handle(message):
                self.post(reply, message["sent_at"])
            delivered += 1
        return delivered

    def fingerprint(self) -> str:
        """Empreinte SHA-256 du journal complet (JSON à clés triées) : identique d'une exécution à l'autre."""
        digest = hashlib.sha256()
        for message in self.log:
            digest.update(json.dumps(message, sort_keys=True, ensure_ascii=False).encode("utf-8"))
            digest.update(b"\n")
        return digest.hexdigest()
