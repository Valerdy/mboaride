"""Lieux connus : quartiers de Douala et villes des voyages interurbains.

Le conducteur publie son trajet par des noms de lieux (« Logpom → Bonanjo ») ; le moteur
a besoin de coordonnées. Les mêmes centres de quartiers servent aux données de démo
(`scripts/seed_demo.py`) et à l'écran de demande de l'application, pour qu'un même nom
désigne partout le même point.
"""

from __future__ import annotations

import unicodedata

# Centres approximatifs (latitude, longitude).
QUARTIERS: dict[str, tuple[float, float]] = {
    "Akwa": (4.0511, 9.7011),
    "Bassa": (4.0290, 9.7580),
    "Bépanda": (4.0610, 9.7230),
    "Bonabéri": (4.0764, 9.6644),
    "Bonamoussadi": (4.0960, 9.7420),
    "Bonanjo": (4.0420, 9.6890),
    "Bonapriso": (4.0267, 9.7019),
    "Cité des Palmiers": (4.0700, 9.7420),
    "Deido": (4.0630, 9.7050),
    "Kotto": (4.0720, 9.7660),
    "Logbessou": (4.1020, 9.7800),
    "Logpom": (4.0880, 9.7650),
    "Makepe": (4.0810, 9.7520),
    "Ndogbong": (4.0570, 9.7480),
    "Ndokoti": (4.0440, 9.7370),
    "New Bell": (4.0380, 9.7120),
    "PK14": (4.0900, 9.8150),
    "Village": (4.0320, 9.7440),
    "Yassa": (4.0086, 9.8114),
}

VILLES: dict[str, tuple[float, float]] = {
    "Douala": (4.0511, 9.7679),
    "Yaoundé": (3.8667, 11.5167),
    "Édéa": (3.8000, 10.1333),
    "Kribi": (2.9400, 9.9100),
    "Limbé": (4.0167, 9.2000),
    "Buéa": (4.1550, 9.2410),
    "Bafoussam": (5.4778, 10.4176),
}

LIEUX = {**QUARTIERS, **VILLES}


def _cle(nom: str) -> str:
    sans_accents = unicodedata.normalize("NFKD", nom).encode("ascii", "ignore").decode()
    return " ".join(sans_accents.lower().replace("-", " ").split())


_INDEX = {_cle(nom): nom for nom in LIEUX}


def trouver(nom: str) -> tuple[str, float, float] | None:
    """Nom officiel et coordonnées d'un lieu, sans tenir compte des accents ni de la casse."""
    officiel = _INDEX.get(_cle(nom or ""))
    if officiel is None:
        return None
    lat, lon = LIEUX[officiel]
    return officiel, lat, lon


def suggestions(debut: str = "", limite: int = 30) -> list[dict]:
    q = _cle(debut)
    noms = sorted(LIEUX, key=_cle)
    retenus = [n for n in noms if not q or _cle(n).startswith(q) or q in _cle(n)]
    return [{"nom": n, "lat": LIEUX[n][0], "lon": LIEUX[n][1],
             "type": "ville" if n in VILLES else "quartier"} for n in retenus[:limite]]
