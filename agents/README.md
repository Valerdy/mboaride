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
| `bus.py` | bus de messages déterministe : file unique, numéro d'ordre, journal, empreinte |
| `coordinator.py` | agent coordinateur : présélection des K conducteurs, élargissement des cercles, confirmation de l'équipage |
| `organization.py` | agent organisation : autorise ou refuse un membre dans son cercle |
| `driver.py` | agent conducteur : offre ou refus à un appel d'offres, réservation à l'acceptation |
| `passenger.py` | agent passager : classe les offres, accepte (autonome) ou présente les 3 meilleures (manuel) |
| `engine.py` | moteur : assemble les agents, soumet les demandes, relaie les choix de l'utilisateur, calcule les mesures |
| `pricing.py` | prix d'un trajet partagé (carburant, péages, diviseur, prix plancher, commission) |
| `routing.py` | interface `RoutingService` et estimateur de détour local et déterministe |
| `scenarios.py` | scénarios simulés à graine fixe (S1 : matin en entreprise) |

```python
import asyncio
from mboaride_agents.scenarios import s1_company_morning

engine = s1_company_morning().build()      # 20 conducteurs, 50 passagers, graine 42
asyncio.run(engine.run())
print(engine.metrics())                    # équipages, messages par équipage, temps, empreinte
```

Mode manuel : après `engine.run()`, `engine.passenger(conversation).proposals` donne les trois
meilleures offres ; l'utilisateur répond avec `engine.choose(conversation, offer_id)`,
`engine.widen(conversation)` ou `engine.withdraw(conversation)`, puis `engine.run()`.

```bash
pip install -r requirements.txt
pytest
```
