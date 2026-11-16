"""SR-51 · Compare les règles de partage des frais sur les scénarios du banc de mesure.

    python3 scripts/comparer_regles_prix.py            # S1, S3 et S5
    python3 scripts/comparer_regles_prix.py S1 --json

Pour chaque règle, le scénario est rejoué entièrement, puis on mesure, par conducteur :

    coût       = (trajet direct + détours acceptés) x consommation / 100 x prix du litre
    reçu       = somme des parts payées par ses passagers, commission exclue
    couverture = reçu / coût

La couverture est la question du bilan développement durable : un conducteur qui ne
couvre pas ses frais finit par arrêter, et le covoiturage s'éteint. Le prix moyen, lui,
doit rester nettement sous le taxi (600 FCFA en ville) pour que le passager y gagne.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import statistics as stats
import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mboaride_agents.pricing import (FUEL_PRICE_FCFA_PER_L, OCCUPANTS, OFFERED_SEATS,
                                     SHARED_LEG, SHARED_LEG_PLUS_DETOUR, WHOLE_TRIP,
                                     PricingPolicy)
from mboaride_agents.scenarios import SCENARIOS

PRIX_TAXI_FCFA = 600

REGLES = {
    "A": ("tronçon commun ÷ places offertes (ancienne règle)",
          PricingPolicy(divisor_rule=OFFERED_SEATS, cost_basis=SHARED_LEG)),
    "B": ("tronçon commun ÷ occupants à bord",
          PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=SHARED_LEG)),
    "C": ("tronçon commun + détour ÷ occupants à bord",
          PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=SHARED_LEG_PLUS_DETOUR)),
    "D": ("trajet entier du conducteur ÷ occupants à bord",
          PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=WHOLE_TRIP)),
}


def mesurer(nom: str, politique: PricingPolicy) -> dict:
    scenario = SCENARIOS[nom]()
    engine = scenario.build(pricing=politique)
    asyncio.run(scenario.play(engine))

    log = engine.bus.log
    annulees = {m["conversation_id"] for m in log if m["type"] == "CREW_CANCELLED"}
    propositions = {m["body"]["offer_id"]: m["body"] for m in log if m["type"] == "PROPOSAL"}
    acceptees = [m["body"]["offer_id"] for m in log
                 if m["type"] == "ACCEPT" and m["conversation_id"] not in annulees]

    profils = {d.driver_id: d for d in scenario.drivers}
    par_conducteur: dict[str, list[dict]] = {}
    for offer_id in acceptees:
        offre = propositions.get(offer_id)
        if offre is None:
            continue
        par_conducteur.setdefault(offer_id.split("-")[1], []).append(offre)

    prix, couvertures = [], []
    for conducteur, offres in par_conducteur.items():
        profil = profils.get(conducteur)
        if profil is None:
            continue
        fcfa_par_km = Fraction(str(profil.consumption_l_per_100km)) / 100 * FUEL_PRICE_FCFA_PER_L
        direct_m = max(o["shared_distance_m"] + o["detour_m"] for o in offres)
        km = Fraction(direct_m + sum(o["detour_m"] for o in offres), 1000)
        cout = float(km * fcfa_par_km)
        recu = sum(o["price"] - o["price_breakdown"]["commission"] for o in offres)
        prix += [o["price"] for o in offres]
        if cout > 0:
            couvertures.append(min(1.0, recu / cout))
    hors_budget = sum(1 for m in log if m["type"] == "DECLINE"
                      and m["body"].get("reason") == "PRICE_TOO_HIGH")

    metriques = engine.metrics()
    return {
        "scenario": nom,
        "equipages": metriques.crews,
        "sans_equipage": metriques.no_crew,
        "demandes": metriques.requests,
        "prix_moyen_fcfa": round(stats.mean(prix)) if prix else 0,
        "prix_median_fcfa": round(stats.median(prix)) if prix else 0,
        "part_du_taxi": round(stats.mean(prix) / PRIX_TAXI_FCFA, 3) if prix else 0,
        "couverture_moyenne": round(stats.mean(couvertures), 3) if couvertures else 0,
        "couverture_min": round(min(couvertures), 3) if couvertures else 0,
        "couverture_max": round(max(couvertures), 3) if couvertures else 0,
        "offres_hors_budget": hors_budget,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenarios", nargs="*", default=[])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    noms = args.scenarios or list(SCENARIOS)
    inconnus = [n for n in noms if n not in SCENARIOS]
    if inconnus:
        parser.error(f"scénario inconnu : {', '.join(inconnus)} "
                     f"(disponibles : {', '.join(SCENARIOS)})")

    resultats = []
    for nom in noms:
        for code, (libelle, politique) in REGLES.items():
            resultats.append({"regle": code, "libelle": libelle, **mesurer(nom, politique)})

    if args.json:
        print(json.dumps(resultats, ensure_ascii=False, indent=2))
        return
    for nom in noms:
        print(f"\nScénario {nom}")
        for r in (r for r in resultats if r["scenario"] == nom):
            print(f"  {r['regle']}  {r['libelle']}")
            print(f"       équipages {r['equipages']}/{r['demandes']}"
                  f"   prix moyen {r['prix_moyen_fcfa']} FCFA"
                  f" ({r['part_du_taxi']:.0%} du taxi)"
                  f"   couverture conducteur {r['couverture_moyenne']:.0%}"
                  f" (de {r['couverture_min']:.0%} à {r['couverture_max']:.0%})"
                  f"   refus hors budget {r['offres_hors_budget']}")


if __name__ == "__main__":
    main()
