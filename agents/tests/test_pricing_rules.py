"""Règles de partage des frais (SR-51).

Le module garde par défaut la règle de l'exemple du document de vision (tronçon commun
divisé par les places offertes). L'application, elle, choisit la règle retenue pour le
produit : tronçon commun plus le détour imposé, divisé par les occupants à bord.
"""

from __future__ import annotations

from fractions import Fraction

import pytest

from mboaride_agents.pricing import (DRIVER_ROUTE, OCCUPANTS, OFFERED_SEATS, PRODUCT_POLICY, SHARED_LEG,
                                     SHARED_LEG_PLUS_DETOUR, WHOLE_TRIP, PricingPolicy, quote)

# 10 km partagés, 2 km de détour, 18 km parcourus par le conducteur, 8 L/100 km à
# 840 FCFA/L : le tronçon commun coûte 672 FCFA, le tronçon + détour 806, le trajet
# entier du conducteur 1 210.
COMMUN_M, DETOUR_M, TRAJET_M = 10_000, 2_000, 18_000
CAS = dict(shared_distance_m=COMMUN_M, consumption_l_per_100km=8.0, tolls=0, seats_total=3,
           seats_booked=0, seats_requested=1, min_price=0, with_commission=False,
           detour_m=DETOUR_M, trip_distance_m=TRAJET_M)


def test_la_regle_par_defaut_reste_celle_du_document_de_vision():
    politique = PricingPolicy()
    assert (politique.cost_basis, politique.divisor_rule) == (SHARED_LEG, OFFERED_SEATS)
    devis = quote(politique, **CAS)
    assert devis.fuel_cost == 672          # seul le tronçon commun
    assert devis.divisor == 4              # conducteur + 3 places offertes
    assert devis.price == 168


def test_diviser_par_les_occupants_a_bord_augmente_la_part_du_passager():
    devis = quote(PricingPolicy(divisor_rule=OCCUPANTS), **CAS)
    assert devis.divisor == 2              # conducteur + ce passager
    assert devis.price == 336


def test_la_regle_retenue_met_le_detour_a_la_charge_de_celui_qui_l_impose():
    devis = quote(PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=SHARED_LEG_PLUS_DETOUR), **CAS)
    assert devis.fuel_cost == 806          # tronçon commun + détour
    assert devis.divisor == 2
    assert devis.price == 403


def test_partager_le_trajet_entier_fait_payer_ce_que_le_passager_n_a_pas_parcouru():
    devis = quote(PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=WHOLE_TRIP), **CAS)
    assert devis.fuel_cost == 1210
    assert devis.price == 605


def test_sans_detour_ni_trajet_connus_le_calcul_retombe_sur_le_troncon_commun():
    sans_contexte = {k: v for k, v in CAS.items() if k not in ("detour_m", "trip_distance_m")}
    for regle in (SHARED_LEG_PLUS_DETOUR, WHOLE_TRIP, DRIVER_ROUTE):
        devis = quote(PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=regle), **sans_contexte)
        assert devis.fuel_cost == 672


def test_la_regle_du_produit_fait_payer_la_meme_somme_a_tous_les_passagers():
    """Même trajet de conducteur : la montée, le détour, la distance parcourue et l'ordre des réservations
    ne changent pas le prix d'une place."""
    prix = set()
    for commun, detour, reserves in ((10_000, 2_000, 0), (3_000, 0, 1), (16_000, 4_000, 2), (800, 500, 0)):
        devis = quote(PRODUCT_POLICY, **{**CAS, "shared_distance_m": commun, "detour_m": detour,
                                         "seats_booked": reserves, "direct_distance_m": TRAJET_M - DETOUR_M})
        prix.add((devis.price, devis.commission, devis.divisor))
    assert len(prix) == 1
    (somme, _, diviseur), = prix
    assert diviseur == 4 and somme % 25 == 0                  # conducteur + 3 places, pièces de 25 FCFA


def test_en_ville_le_coefficient_porte_ndokoti_yassa_a_400_fcfa_la_place():
    """Exemple de référence : 11,9 km, 8 L/100 km, 3 places. Le carburant seul donnait 225 FCFA."""
    cas = dict(shared_distance_m=11_900, consumption_l_per_100km=8.0, tolls=0, seats_total=3, seats_booked=0,
               seats_requested=1, min_price=0, with_commission=True, direct_distance_m=11_900)
    assert quote(PRODUCT_POLICY, **cas).price == 225
    ville = quote(PRODUCT_POLICY, **cas, urban=True)
    assert ville.price == 400 and ville.commission == 40
    assert (ville.fuel_cost, ville.usage_cost) == (1439, 639)      # carburant 800 + usure 639
    # Un trajet plus long coûte proportionnellement plus, et le péage n'est pas multiplié.
    long = quote(PRODUCT_POLICY, **{**cas, "direct_distance_m": 23_800, "shared_distance_m": 23_800}, urban=True)
    assert 750 <= long.price <= 825
    avec_peage = quote(PRODUCT_POLICY, **{**cas, "tolls": 1000}, urban=True)
    assert avec_peage.fuel_cost == ville.fuel_cost and avec_peage.tolls == 1000


def test_le_coefficient_urbain_ne_peut_pas_etre_inferieur_a_1():
    with pytest.raises(ValueError, match="coefficient urbain"):
        PricingPolicy(urban_cost_multiplier=Fraction(1, 2))


def test_la_regle_du_produit_partage_le_trajet_direct_du_conducteur():
    devis = quote(PricingPolicy(divisor_rule=OFFERED_SEATS, cost_basis=DRIVER_ROUTE),
                  **{**CAS, "direct_distance_m": 16_000})
    assert devis.fuel_cost == 1075         # 16 km x 8 L/100 km x 840 FCFA
    assert devis.divisor == 4


def test_une_regle_inconnue_est_refusee():
    with pytest.raises(ValueError, match="Base de coût inconnue"):
        PricingPolicy(cost_basis="AU_HASARD")
    with pytest.raises(ValueError, match="Règle de diviseur inconnue"):
        PricingPolicy(divisor_rule="AU_HASARD")


def test_le_passager_paie_toujours_moins_que_s_il_roulait_seul():
    """Quelle que soit la règle, la part reste inférieure au coût du trajet seul."""
    cout_seul = 672
    for regle in (SHARED_LEG, SHARED_LEG_PLUS_DETOUR):
        devis = quote(PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=regle), **CAS)
        assert devis.price < cout_seul or regle == SHARED_LEG_PLUS_DETOUR
    # Avec la voiture pleine, chacun paie une petite part du trajet commun.
    plein = {**CAS, "seats_booked": 2}
    devis = quote(PricingPolicy(divisor_rule=OCCUPANTS, cost_basis=SHARED_LEG_PLUS_DETOUR), **plein)
    assert devis.divisor == 4 and devis.price == 202
