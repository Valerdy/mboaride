"""Prix d'un trajet partagé (dossier de conception §5, architecture §4).

    part  = max(arrondi((coût carburant + péages) / diviseur), prix plancher du conducteur)
    prix  = part + commission

Les calculs se font en fractions exactes puis sont arrondis au FCFA, demi vers le
haut : aucun écart d'arrondi entre deux exécutions ou deux machines.

Deux réglages décrivent la règle de partage des frais, sans toucher à l'agent ni au
format des messages :

- la base du coût (`cost_basis`) : le seul tronçon parcouru avec le passager
  (`SHARED_LEG`), ce tronçon plus le détour que ce passager impose
  (`SHARED_LEG_PLUS_DETOUR`) ou le trajet entier du conducteur (`WHOLE_TRIP`) ;
- le diviseur (`divisor_rule`) : toutes les places offertes, voiture pleine ou non
  (`OFFERED_SEATS`), ou les seuls occupants à bord (`OCCUPANTS`).

Le bilan développement durable (SR-51) a comparé ces règles sur les scénarios du banc
de mesure : avec l'ancien réglage (tronçon commun partagé entre toutes les places
offertes), le conducteur ne couvrait que 39 % de ses frais, ce qui ne lui donne aucune
raison de continuer. La règle retenue pour le produit partage le coût du trajet commun entre les occupants
réellement à bord et met le détour à la charge de celui qui l'impose
(`SHARED_LEG_PLUS_DETOUR` + `OCCUPANTS`) : mesurée sur S1, elle porte le prix moyen à
249 FCFA, soit 42 % d'un taxi, et la couverture du conducteur à 66 %. Partager le
trajet entier du conducteur (`WHOLE_TRIP`) couvrirait davantage encore, mais ferait
payer à un passager monté pour trois kilomètres une part des vingt kilomètres du
conducteur, et la moitié des demandes ne trouveraient plus d'équipage.

Le défaut de ce module reste l'ancienne règle (`SHARED_LEG` + `OFFERED_SEATS`), celle
de l'exemple du document de vision et des messages documentés : l'application choisit
sa politique explicitement (voir `app/moteur.py`), et `scripts/comparer_regles_prix.py`
chiffre les quatre règles sur les scénarios du banc.
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

# Base du coût partagé : le seul tronçon parcouru avec le passager...
SHARED_LEG = "SHARED_LEG"
# ...ce tronçon plus le détour que ce passager impose au conducteur...
SHARED_LEG_PLUS_DETOUR = "SHARED_LEG_PLUS_DETOUR"
# ...ou le trajet entier du conducteur, détour compris (étudié dans le bilan SR-51).
WHOLE_TRIP = "WHOLE_TRIP"


def round_half_up(value: Fraction) -> int:
    """Arrondi au plus proche, demi vers le haut (164,5 -> 165), contrairement à round()."""
    return math.floor(value + Fraction(1, 2))


@dataclass(frozen=True)
class PricingPolicy:
    fuel_price_per_l: int = FUEL_PRICE_FCFA_PER_L
    commission_rate: Fraction = Fraction(1, 10)  # réseau public et interurbain
    divisor_rule: str = OFFERED_SEATS
    cost_basis: str = SHARED_LEG

    def __post_init__(self):
        if self.divisor_rule not in (OFFERED_SEATS, OCCUPANTS):
            raise ValueError(f"Règle de diviseur inconnue : {self.divisor_rule}")
        if self.cost_basis not in (SHARED_LEG, SHARED_LEG_PLUS_DETOUR, WHOLE_TRIP):
            raise ValueError(f"Base de coût inconnue : {self.cost_basis}")


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
          min_price: int, with_commission: bool, detour_m: int | None = None,
          trip_distance_m: int | None = None) -> Quote:
    """Prix proposé à un passager.

    `detour_m` est le détour imposé par ce passager et `trip_distance_m` le trajet
    réellement parcouru par le conducteur (`Detour.trip_distance_m`). Selon la règle
    de `policy.cost_basis`, le coût porte sur le tronçon commun, sur ce tronçon plus
    le détour, ou sur le trajet entier ; une valeur absente fait retomber le calcul
    sur le tronçon commun.
    """
    base_m = shared_distance_m
    if policy.cost_basis == SHARED_LEG_PLUS_DETOUR:
        base_m = shared_distance_m + (detour_m or 0)
    elif policy.cost_basis == WHOLE_TRIP and trip_distance_m:
        base_m = trip_distance_m
    fuel_exact = (Fraction(base_m, 1000) * Fraction(str(consumption_l_per_100km)) / 100
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


# Règle retenue pour le produit (SR-51) : tronçon commun + détour imposé, partagé entre
# les occupants à bord. Le service agents et l'API FastAPI l'importent d'ici, pour que
# les deux annoncent le même prix pour le même trajet.
PRODUCT_POLICY = PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=SHARED_LEG_PLUS_DETOUR)
