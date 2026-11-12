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

```bash
pip install -r requirements.txt
pytest
```
