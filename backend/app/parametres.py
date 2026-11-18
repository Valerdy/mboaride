"""Paramètres de la plateforme réglables depuis la console d'administration.

Les valeurs sont dans la table `parametre` (migration 12), partagée avec l'API Node qui y
lit la durée de validité du code OTP. Elles sont relues au plus toutes les 15 secondes ;
la console vide le cache dès qu'elle enregistre une modification. Sans table (base plus
ancienne), les valeurs par défaut s'appliquent : ce sont celles du produit.
"""

from __future__ import annotations

import time

from . import config

DEFINITIONS: dict[str, dict] = {
    "prix_carburant_fcfa_l": {
        "groupe": "Tarifs", "libelle": "Prix du carburant", "unite": "FCFA / litre", "defaut": 840,
        "min": 300, "max": 2000, "aide": "Prix du super à la pompe, base du partage des frais."},
    "commission_pct": {
        "groupe": "Tarifs", "libelle": "Commission MboaRide", "unite": "% du prix", "defaut": 10,
        "min": 0, "max": 30, "aide": "Comprise dans le prix payé, gardée au versement de chaque course."},
    "arrondi_fcfa": {
        "groupe": "Tarifs", "libelle": "Arrondi du prix", "unite": "FCFA", "defaut": 25,
        "min": 1, "max": 500, "aide": "Le prix est arrondi au multiple supérieur (pièces de 25 FCFA)."},
    "prix_minimum_fcfa": {
        "groupe": "Tarifs", "libelle": "Prix minimum d'un trajet", "unite": "FCFA", "defaut": 100,
        "min": 0, "max": 5000, "aide": "Aucun trajet n'est proposé en dessous."},
    "validation_auto_heures": {
        "groupe": "Courses", "libelle": "Clôture automatique d'une course", "unite": "heures", "defaut": 24,
        "min": 1, "max": 168,
        "aide": "Sans validation de tous les passagers, la course est clôturée et le conducteur payé après ce délai."},
    "agrement_validite_mois": {
        "groupe": "Agréments", "libelle": "Validité d'une pièce validée", "unite": "mois", "defaut": 12,
        "min": 1, "max": 60, "aide": "Date de fin proposée quand l'équipe valide une pièce."},
    "otp_minutes": {
        "groupe": "Connexion", "libelle": "Validité du code de vérification", "unite": "minutes", "defaut": 5,
        "min": 1, "max": 30, "aide": "Lu par l'API Node à chaque envoi de code."},
}

_DUREE_CACHE_S = 15
_cache: dict = {"valeurs": None, "lu_le": 0.0}


def defauts() -> dict[str, int]:
    d = {cle: p["defaut"] for cle, p in DEFINITIONS.items()}
    # L'ancienne variable d'environnement reste le défaut de la clôture automatique.
    d["validation_auto_heures"] = config.VALIDATION_AUTO_HEURES
    return d


def valeurs() -> dict[str, int]:
    """Valeurs courantes, depuis le cache ou la base."""
    if _cache["valeurs"] is not None and time.monotonic() - _cache["lu_le"] < _DUREE_CACHE_S:
        return _cache["valeurs"]
    v = defauts()
    try:
        from .db import connect
        with connect() as conn:
            if conn.execute("SELECT to_regclass('parametre') AS t").fetchone()["t"]:
                for r in conn.execute("SELECT cle, valeur FROM parametre").fetchall():
                    if r["cle"] in v:
                        v[r["cle"]] = int(r["valeur"])
    except Exception:          # base injoignable : les valeurs par défaut gardent l'application en marche
        pass
    _cache.update(valeurs=v, lu_le=time.monotonic())
    return v


def valeur(cle: str) -> int:
    return valeurs()[cle]


def invalider() -> None:
    _cache.update(valeurs=None, lu_le=0.0)
