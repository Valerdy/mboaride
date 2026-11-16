"""Le pont app.moteur donne exactement le devis et les horaires des agents (agents/mboaride_agents)."""

from datetime import time

from app import moteur
from mboaride_agents.pricing import PricingPolicy, quote

TRAJET = {"depart_lat": 4.088, "depart_lon": 9.765, "arrivee_lat": 4.042, "arrivee_lon": 9.689,
          "heure_depart": time(6, 50), "places_offertes": 3, "detour_max_km": 3.0, "conso_l_100km": 7.5,
          "climatise": True, "non_fumeur": False, "peage_fcfa": 0, "type_trajet": "urbain"}
DEMANDE = {"depart_lat": 4.072, "depart_lon": 9.766, "arrivee_lat": 4.042, "arrivee_lon": 9.689,
           "arrivee_au_plus_tot": time(7, 30), "arrivee_au_plus_tard": time(7, 50), "clim_obligatoire": True}


def test_prix_identique_au_devis_des_agents():
    t, d = moteur.driver_from_row(TRAJET), moteur.request_from_row(DEMANDE)
    det = moteur.detour(t, d)
    attendu = quote(PricingPolicy(), shared_distance_m=det.shared_distance_m, consumption_l_per_100km=7.5,
                    tolls=0, seats_total=3, seats_booked=0, seats_requested=1, min_price=0, with_commission=False)
    detail = moteur.detail_prix(t, d, 0)
    assert detail.prix_fcfa == attendu.price and detail.commission_fcfa == 0
    assert detail.lignes()[-1]["montant_fcfa"] == attendu.price
    public = moteur.detail_prix(t, d, 2)
    assert public.commission_fcfa > 0 and public.prix_fcfa == detail.prix_fcfa + public.commission_fcfa


def test_horaires_et_filtres_des_agents():
    t, d = moteur.driver_from_row(TRAJET), moteur.request_from_row(DEMANDE)
    prise, arrivee, detour_km = moteur.horaires(t, d)
    assert "06:50" < prise < arrivee <= "07:50" and detour_km <= 3.0
    assert moteur.horaires(moteur.driver_from_row({**TRAJET, "detour_max_km": 0.001}), d) is None      # DETOUR_TOO_LONG
    assert moteur.horaires(moteur.driver_from_row({**TRAJET, "heure_depart": time(5, 0)}), d) is None  # OUTSIDE_WINDOW
