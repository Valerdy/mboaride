"""Prix d'un trajet partagé (dossier de conception §5, architecture §4).

    part  = max(arrondi((coût carburant + péages) / diviseur), prix plancher du conducteur)
    prix  = part + commission

Les calculs se font en fractions exactes puis sont arrondis au FCFA, demi vers le
haut : aucun écart d'arrondi entre deux exécutions ou deux machines.

La règle du diviseur est le point ouvert du bilan développement durable (le
conducteur ne couvre que 39 % de ses frais) : elle est réglable sans toucher à
l'agent ni au format des messages.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from fractions import Fraction

FUEL_PRICE_FCFA_PER_L = 840  # prix officiel du super depuis février 2024

# Diviseur = conducteur + toutes les places offertes (voiture pleine).
# C'est la règle de l'exemple du document de vision (1 000 FCFA, 3 passagers -> 250 FCFA).
OFFERED_SEATS = "OFFERED_SEATS"
# Diviseur = conducteur + passagers déjà réservés + places demandées.
OCCUPANTS = "OCCUPANTS"


def round_half_up(value: Fraction) -> int:
    """Arrondi au plus proche, demi vers le haut (164,5 -> 165), contrairement à round()."""
    return math.floor(value + Fraction(1, 2))


@dataclass(frozen=True)
class PricingPolicy:
    fuel_price_per_l: int = FUEL_PRICE_FCFA_PER_L
    commission_rate: Fraction = Fraction(1, 10)  # réseau public et interurbain
    divisor_rule: str = OFFERED_SEATS

    def __post_init__(self):
        if self.divisor_rule not in (OFFERED_SEATS, OCCUPANTS):
            raise ValueError(f"Règle de diviseur inconnue : {self.divisor_rule}")


@dataclass(frozen=True)
class Quote:
    price: int
    fuel_cost: int
    tolls: int
    divisor: int
    commission: int

    def breakdown(self) -> dict[str, int]:
        """Champ `price_breakdown` d'un message PROPOSAL."""
        return {"fuel_cost": self.fuel_cost, "tolls": self.tolls, "divisor": self.divisor,
                "commission": self.commission}


def quote(policy: PricingPolicy, *, shared_distance_m: int, consumption_l_per_100km: float,
          tolls: int, seats_total: int, seats_booked: int, seats_requested: int,
          min_price: int, with_commission: bool) -> Quote:
    """Prix proposé à un passager."""
    fuel_exact = (Fraction(shared_distance_m, 1000) * Fraction(str(consumption_l_per_100km)) / 100
                  * policy.fuel_price_per_l)
    fuel_cost = round_half_up(fuel_exact)
    if policy.divisor_rule == OFFERED_SEATS:
        divisor = 1 + seats_total
    else:
        divisor = 1 + seats_booked + seats_requested
    share = max(round_half_up(Fraction(fuel_cost + tolls, divisor)), min_price)
    commission = round_half_up(share * policy.commission_rate) if with_commission else 0
    return Quote(price=share + commission, fuel_cost=fuel_cost, tolls=tolls, divisor=divisor,
                 commission=commission)
