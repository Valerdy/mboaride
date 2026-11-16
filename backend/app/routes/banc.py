"""US15 · Lancer un scénario simulé et afficher convergence, messages et mémoire.

Le banc de mesure vit dans le moteur multi-agents (`mboaride_agents.bench`) : il rejoue
le scénario complet plusieurs fois et mesure les quatre critères de la grille Maquette
(convergence sous deux secondes, charge de communication, déterminisme, mémoire). Cette
route n'est qu'une enveloppe HTTP autour de `run_scenario(...).to_dict()`, pour que
l'écran de démonstration montre les mêmes chiffres que la ligne de commande.

Critères d'acceptation :
  1. La liste des scénarios mesurables est lisible sans rien lancer.
  2. Une mesure renvoie convergence, messages échangés par type, empreinte du résultat
     et pic de mémoire, avec les cibles de la grille déjà évaluées.
  3. Le nombre d'exécutions est borné (1 à 50) pour qu'une démonstration reste courte.
  4. Un scénario inconnu est refusé avec la liste des scénarios disponibles (404).
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

router = APIRouter(prefix="/api/demo", tags=["US15 · Banc de mesure"])

TITRES = {
    "S1": "Matin ordinaire en entreprise",
    "S2": "Ville mixte, cercles emboîtés",
    "S3": "Annulation du conducteur et réaffectation",
    "S4": "Voyage interurbain",
    "S5": "Charge : beaucoup de demandes",
}


def _banc():
    try:
        from mboaride_agents import bench
    except ImportError as exc:                      # pragma: no cover - dépend du déploiement
        raise HTTPException(503, "Moteur multi-agents introuvable : vérifiez MBOARIDE_AGENTS") from exc
    return bench


@router.get("/banc")
def scenarios() -> list[dict]:
    bench = _banc()
    return [{"code": code, "titre": TITRES.get(code, code)}
            for code in bench.SCENARIOS]


@router.post("/banc/{code}")
def mesurer(code: str, runs: int = Query(default=10, ge=1, le=50)) -> dict:
    bench = _banc()
    if code not in bench.SCENARIOS:
        raise HTTPException(404, f"Scénario inconnu : {code} "
                                 f"(disponibles : {', '.join(bench.SCENARIOS)})")
    rapport = bench.run_scenario(code, runs=runs)
    return {**rapport.to_dict(), "titre": TITRES.get(code, code)}
