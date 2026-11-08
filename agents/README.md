# Agents

Système multi-agents : agent conducteur, passager, organisation et coordinateur,
selon le protocole d'appel d'offres (Contract Net).

Exigences à mesurer : convergence en moins de 2 secondes pour 100 utilisateurs,
moins de 20 messages par équipage, résultat identique sur 10 exécutions, mémoire stable.

Architecture, diagrammes du protocole et règles de déterminisme :
[`docs/architecture-multi-agents.md`](../docs/architecture-multi-agents.md).
Le format des messages est fixé par [`schemas/message.schema.json`](schemas/message.schema.json)
(exemples de référence dans [`schemas/examples.json`](schemas/examples.json)) et vérifié par
`tests/test_message_schema.py`.

## Modules

| Module | Rôle |
|---|---|
| `messages.py` | brouillons de messages (`draft`, `reply`), tampon du bus (`stamp`), validation contre le schéma |
| `driver.py` | agent conducteur : répond à un appel d'offres (CFP) par une offre (PROPOSAL) ou un refus motivé (DECLINE) |
| `passenger.py` | agent passager : publie la demande, écarte les offres contraires à ses exigences, classe les autres par score, puis accepte (autonome) ou présente les 3 meilleures (manuel) |
| `pricing.py` | prix d'un trajet partagé (carburant, péages, diviseur, prix plancher, commission) |
| `routing.py` | interface `RoutingService` et estimateur de détour local et déterministe |
| `agents.py` | squelette initial (organisation, coordinateur), à remplacer |

```python
import asyncio
from datetime import datetime
from mboaride_agents import DriverAgent, DriverProfile, DriverTrip, EstimatedRouting, Point

trip = DriverTrip("t-d07", origin=Point(4.0790, 9.7740), destination=Point(4.0440, 9.6935),
                  departure_time=datetime.fromisoformat("2026-11-10T06:55:00+01:00"))
driver = DriverAgent(DriverProfile("d07", trip, seats_total=3, max_detour_m=3000), EstimatedRouting())
replies = asyncio.run(driver.handle(cfp_message))   # [brouillon PROPOSAL ou DECLINE]
```

```bash
pip install -r requirements.txt
pytest
```
