"""Le pont app.moteur donne exactement le devis et les horaires des agents (agents/mboaride_agents)."""

from datetime import time

from app import moteur
from mboaride_agents.pricing import PRODUCT_POLICY, quote
from mboaride_agents.routing import ESTIMATORS

TRAJET = {"depart_lat": 4.088, "depart_lon": 9.765, "arrivee_lat": 4.042, "arrivee_lon": 9.689,
          "heure_depart": time(6, 50), "places_offertes": 3, "detour_max_km": 3.0, "conso_l_100km": 7.5,
          "climatise": True, "non_fumeur": False, "peage_fcfa": 0, "type_trajet": "urbain"}
DEMANDE = {"depart_lat": 4.072, "depart_lon": 9.766, "arrivee_lat": 4.042, "arrivee_lon": 9.689,
           "arrivee_au_plus_tot": time(7, 30), "arrivee_au_plus_tard": time(7, 50), "clim_obligatoire": True}


def test_prix_identique_au_devis_des_agents():
    t, d = moteur.driver_from_row(TRAJET), moteur.request_from_row(DEMANDE)
    det = moteur.detour(t, d)
    # Même politique que l'application : trajet direct du conducteur, partagé à parts égales entre
    # le conducteur et toutes ses places, donc le même prix pour tous les passagers.
    attendu = quote(moteur.POLITIQUE, shared_distance_m=det.shared_distance_m,
                    detour_m=det.detour_m, trip_distance_m=det.trip_distance_m,
                    direct_distance_m=det.direct_distance_m,
                    consumption_l_per_100km=7.5, tolls=0, seats_total=3, seats_booked=0,
                    seats_requested=1, min_price=0, with_commission=False)
    detail = moteur.detail_prix(t, d, 0)
    assert detail.prix_fcfa == attendu.price and detail.commission_fcfa == attendu.commission
    assert detail.lignes()[-1]["montant_fcfa"] == attendu.price
    # Tarif : commission de 10 % du prix sur tous les cercles, prix rond (25 FCFA), et le
    # conducteur reçoit au moins sa part des frais.
    assert detail.prix_fcfa % 25 == 0 and detail.commission_fcfa == detail.prix_fcfa // 10
    assert attendu.divisor == 4                      # conducteur + 3 places offertes
    frais = attendu.fuel_cost / attendu.divisor
    assert detail.prix_fcfa - detail.commission_fcfa >= frais
    public = moteur.detail_prix(t, d, 2)
    assert public.prix_fcfa == detail.prix_fcfa and public.commission_fcfa == detail.commission_fcfa
    # La voiture se remplit : le prix d'une place ne bouge pas.
    assert moteur.detail_prix(t, d, 0, places_reservees=2).prix_fcfa == detail.prix_fcfa
    # Ni le point de montée ni le détour ne changent la somme demandée.
    autre = {**DEMANDE, "depart_lat": 4.0775, "depart_lon": 9.7625}
    assert moteur.detail_prix(t, moteur.request_from_row(autre), 0).prix_fcfa == detail.prix_fcfa


def test_horaires_et_filtres_des_agents():
    t, d = moteur.driver_from_row(TRAJET), moteur.request_from_row(DEMANDE)
    prise, arrivee, detour_km = moteur.horaires(t, d)
    assert "06:50" < prise < arrivee <= "07:50" and detour_km <= 3.0
    assert moteur.horaires(moteur.driver_from_row({**TRAJET, "detour_max_km": 0.001}), d) is None      # DETOUR_TOO_LONG
    assert moteur.horaires(moteur.driver_from_row({**TRAJET, "heure_depart": time(5, 0)}), d) is None  # OUTSIDE_WINDOW


def test_memes_regles_que_le_service_agents():
    # L'API Node passe par le service agents : les deux doivent annoncer le même prix et les mêmes horaires.
    assert moteur.POLITIQUE is PRODUCT_POLICY
    assert moteur.ROUTAGE_URBAIN is ESTIMATORS["URBAN"]
    assert moteur.ROUTAGE_INTERURBAIN is ESTIMATORS["INTERURBAN"]
