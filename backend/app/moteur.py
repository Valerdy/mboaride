"""Pont entre la base de données et le système multi-agents (`agents/mboaride_agents`).

L'API ne refait aucun calcul : le prix (US09) vient de `pricing.quote` et les horaires
de `routing.EstimatedRouting.detour`, exactement comme dans l'agent conducteur
(`driver.DriverAgent._evaluate`). Le prix affiché avant confirmation est donc celui que
les agents négocient, et changer la règle du diviseur (`PricingPolicy`) le change partout.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass

from . import config  # noqa: F401  (ajoute le dossier agents/ au chemin d'import)
from mboaride_agents.pricing import PricingPolicy, Quote, quote  # type: ignore
from mboaride_agents.routing import Detour, EstimatedRouting, Point  # type: ignore

NIVEAUX = {0: "organisation", 1: "partenaires", 2: "public"}
NIVEAU_CODE = {v: k for k, v in NIVEAUX.items()}
CERCLE_PUBLIC = 2

POLITIQUE = PricingPolicy()
ROUTAGE_URBAIN = EstimatedRouting(speed_kmh=20.0)        # heures de pointe à Douala
ROUTAGE_INTERURBAIN = EstimatedRouting(speed_kmh=60.0)   # axe Douala-Yaoundé


def minutes(t) -> float:
    return t.hour * 60 + t.minute + t.second / 60


def hhmm(m: float) -> str:
    m = int(round(m))
    return f"{m // 60:02d}:{m % 60:02d}"


def fr(x: float) -> str:
    """Nombre à une décimale au format français (virgule), sans ,0 inutile."""
    return f"{float(x):.1f}".replace(".", ",").removesuffix(",0")


@dataclass(frozen=True)
class Trajet:
    """Trajet d'un conducteur, tel que l'agent conducteur le connaît."""
    origine: Point
    destination: Point
    depart_min: float
    places: int
    detour_max_m: int
    conso_l100: float
    confort: frozenset[str]
    peage_fcfa: int
    interurbain: bool


@dataclass(frozen=True)
class Demande:
    origine: Point
    destination: Point
    au_plus_tot_min: float
    au_plus_tard_min: float
    confort_obligatoire: frozenset[str]


def driver_from_row(t: dict) -> Trajet:
    confort = set()
    if t["climatise"]:
        confort.add("AIR_CONDITIONING")
    if t["non_fumeur"]:
        confort.add("NON_SMOKING")
    return Trajet(
        origine=Point(float(t["depart_lat"]), float(t["depart_lon"])),
        destination=Point(float(t["arrivee_lat"]), float(t["arrivee_lon"])),
        depart_min=minutes(t["heure_depart"]), places=t["places_offertes"],
        detour_max_m=round(float(t["detour_max_km"]) * 1000), conso_l100=float(t["conso_l_100km"]),
        confort=frozenset(confort), peage_fcfa=int(t["peage_fcfa"]),
        interurbain=t["type_trajet"] == "interurbain")


def request_from_row(d: dict) -> Demande:
    return Demande(
        origine=Point(float(d["depart_lat"]), float(d["depart_lon"])),
        destination=Point(float(d["arrivee_lat"]), float(d["arrivee_lon"])),
        au_plus_tot_min=minutes(d["arrivee_au_plus_tot"]), au_plus_tard_min=minutes(d["arrivee_au_plus_tard"]),
        confort_obligatoire=frozenset({"AIR_CONDITIONING"} if d["clim_obligatoire"] else set()))


def _routage(interurbain: bool) -> EstimatedRouting:
    return ROUTAGE_INTERURBAIN if interurbain else ROUTAGE_URBAIN


def detour(trajet: Trajet, demande: Demande) -> Detour:
    """Détour imposé au conducteur par la prise en charge de ce passager."""
    return asyncio.run(_routage(trajet.interurbain).detour(
        trajet.origine, trajet.destination, demande.origine, demande.destination))


def distance_km(a_lat, a_lon, b_lat, b_lon, interurbain: bool = False) -> float:
    """Distance routière estimée entre deux points, avec l'estimateur des agents."""
    m, _ = _routage(interurbain).leg(Point(float(a_lat), float(a_lon)), Point(float(b_lat), float(b_lon)))
    return m / 1000


@dataclass(frozen=True)
class DetailPrix:
    distance_km: float
    conso_l100: float
    devis: Quote

    @property
    def prix_fcfa(self) -> int:
        return self.devis.price

    @property
    def commission_fcfa(self) -> int:
        return self.devis.commission

    def lignes(self) -> list[dict]:
        q = self.devis
        out = [{"libelle": f"Carburant du trajet ({fr(self.distance_km)} km × {fr(self.conso_l100)} L/100 km "
                           f"× {POLITIQUE.fuel_price_per_l} FCFA/L)", "montant_fcfa": q.fuel_cost}]
        if q.tolls:
            out.append({"libelle": "Péage", "montant_fcfa": q.tolls})
        out.append({"libelle": f"Partagé entre {q.divisor} occupants (conducteur compris)",
                    "montant_fcfa": q.price - q.commission})
        if q.commission:
            out.append({"libelle": "Commission MboaRide (10 %, trajets publics et interurbains)",
                        "montant_fcfa": q.commission})
        out.append({"libelle": "Prix du trajet", "montant_fcfa": q.price})
        return out


def detail_prix(trajet: Trajet, demande: Demande, niveau: int, places_reservees: int = 0) -> DetailPrix:
    """Devis de l'agent conducteur pour ce passager, décomposé ligne par ligne."""
    d = detour(trajet, demande)
    q = quote(POLITIQUE, shared_distance_m=d.shared_distance_m, consumption_l_per_100km=trajet.conso_l100,
              tolls=trajet.peage_fcfa if trajet.interurbain else 0, seats_total=trajet.places,
              seats_booked=places_reservees, seats_requested=1, min_price=0,
              with_commission=niveau == CERCLE_PUBLIC or trajet.interurbain)
    return DetailPrix(round(d.shared_distance_m / 1000, 2), trajet.conso_l100, q)


def horaires(trajet: Trajet, demande: Demande) -> tuple[str, str, float] | None:
    """Prise en charge, arrivée et détour (km), ou None si le détour ou la fenêtre ne conviennent pas.

    Mêmes filtres que l'agent conducteur : DETOUR_TOO_LONG puis OUTSIDE_WINDOW.
    """
    d = detour(trajet, demande)
    if d.detour_m > trajet.detour_max_m:
        return None
    prise = trajet.depart_min + d.pickup_offset_s / 60
    arrivee = prise + d.shared_duration_s / 60
    if not demande.au_plus_tot_min <= arrivee <= demande.au_plus_tard_min:
        return None
    return hhmm(prise), hhmm(arrivee), round(d.detour_m / 1000, 2)


def km_evites(depart_lat, depart_lon, arrivee_lat, arrivee_lon, detour_km, interurbain: bool = False) -> float:
    """Km que le passager n'a pas roulés seul, moins le détour imposé au conducteur."""
    return max(0.0, distance_km(depart_lat, depart_lon, arrivee_lat, arrivee_lon, interurbain)
               - float(detour_km or 0))
