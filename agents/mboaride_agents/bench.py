"""Banc de mesure : les quatre critères de la grille, par scénario (SR-28).

    python -m mboaride_agents.bench                  # S1, S3 et S5, 10 exécutions chacun
    python -m mboaride_agents.bench S1 --runs 10 --json

Pour chaque scénario, le banc rejoue `runs` exécutions complètes et mesure :
- convergence : temps réel de traitement par le bus (min, médiane, max), et nombre
  de tours d'appel d'offres par équipage (lecture « nombre de cycles » de la grille) ;
- charge de communication : messages au total, par type, par équipage formé ;
- déterminisme : empreinte du journal complet et affectations, identiques sur toutes les exécutions ;
- mémoire : pic `tracemalloc` de la 1re et de la dernière exécution, et leur écart.

Les deux exécutions mesurées avec tracemalloc (plus lentes) sont exclues des temps.
`run_scenario(...).to_dict()` donne un résultat JSON, prêt à afficher (US15).
"""
from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import sys
import tracemalloc
from dataclasses import asdict, dataclass

from .scenarios import SCENARIOS

TARGET_CONVERGENCE_S = 2.0
TARGET_MESSAGES_PER_CREW = 20
TARGET_MEMORY_GROWTH_PCT = 5.0


@dataclass(frozen=True)
class BenchReport:
    scenario: str
    runs: int
    # Convergence
    convergence_s: dict[str, float]          # min, médiane, max du temps total de traitement
    reassignment_max_s: float | None         # S3 : réaffectation la plus longue après une annulation
    rounds_per_crew: float | None
    # Charge de communication
    messages: int
    messages_per_crew: float | None
    max_messages_per_crew: int | None
    by_type: dict[str, int]
    # Résultat de la négociation
    requests: int
    crews: int
    no_crew: int
    cancelled_crews: int
    renegotiations: int
    reassigned: int
    # Déterminisme
    deterministic: bool
    distinct_fingerprints: int
    fingerprint: str
    # Mémoire
    memory_peak_kib_first: float | None
    memory_peak_kib_last: float | None
    memory_growth_pct: float | None
    # Cibles de la grille
    targets: dict[str, bool]

    def to_dict(self) -> dict:
        return asdict(self)


def _execute(scenario_name: str, traced: bool):
    scenario = SCENARIOS[scenario_name]()
    if traced:
        tracemalloc.start()
        tracemalloc.reset_peak()
    try:
        engine = scenario.build()
        phases = asyncio.run(scenario.play(engine))
        peak = tracemalloc.get_traced_memory()[1] if traced else None
    finally:
        if traced:
            tracemalloc.stop()
    return engine.metrics(), engine.assignments(), phases, peak


def run_scenario(name: str, runs: int = 10, measure_memory: bool = True) -> BenchReport:
    if name not in SCENARIOS:
        raise ValueError(f"Scénario inconnu : {name} (disponibles : {', '.join(SCENARIOS)})")
    if runs < 1:
        raise ValueError("runs doit être >= 1")
    traced_runs = {0, runs - 1} if measure_memory else set()
    results = [_execute(name, i in traced_runs) for i in range(runs)]

    metrics = [r[0] for r in results]
    timed = [m.elapsed_s for i, m in enumerate(metrics) if i not in traced_runs] or [m.elapsed_s for m in metrics]
    reassignments = [t for r in results for t in r[2]["reassignment_s"]]
    signatures = {(m.fingerprint, tuple(r[1])) for m, r in zip(metrics, results)}
    peaks = [r[3] for r in results if r[3] is not None]
    first_kib = peaks[0] / 1024 if peaks else None
    last_kib = peaks[-1] / 1024 if peaks else None
    growth = (last_kib - first_kib) / first_kib * 100 if peaks else None

    m = metrics[-1]
    convergence = {"min": min(timed), "median": statistics.median(timed), "max": max(timed)}
    targets = {
        "convergence_under_2s": convergence["max"] < TARGET_CONVERGENCE_S,
        "under_20_messages_per_crew": m.messages_per_crew is not None and m.messages_per_crew < TARGET_MESSAGES_PER_CREW,
        "deterministic": len(signatures) == 1,
        "memory_stable": growth is None or growth <= TARGET_MEMORY_GROWTH_PCT,
    }
    return BenchReport(
        scenario=name, runs=runs, convergence_s=convergence,
        reassignment_max_s=max(reassignments) if reassignments else None, rounds_per_crew=m.rounds_per_crew,
        messages=m.messages, messages_per_crew=m.messages_per_crew, max_messages_per_crew=m.max_messages_per_crew,
        by_type=m.by_type, requests=m.requests, crews=m.crews, no_crew=m.no_crew,
        cancelled_crews=m.cancelled_crews, renegotiations=m.renegotiations, reassigned=m.reassigned,
        deterministic=len(signatures) == 1, distinct_fingerprints=len({s[0] for s in signatures}),
        fingerprint=m.fingerprint, memory_peak_kib_first=first_kib, memory_peak_kib_last=last_kib,
        memory_growth_pct=growth, targets=targets,
    )


def format_report(r: BenchReport) -> str:
    ok = {True: "oui", False: "NON"}
    ms = {k: f"{v * 1000:.1f}" for k, v in r.convergence_s.items()}
    lines = [
        f"Scénario {r.scenario} ({r.runs} exécutions)",
        f"  Équipages          : {r.crews} sur {r.requests} demandes, {r.no_crew} sans équipage"
        + (f", {r.cancelled_crews} annulés, {r.reassigned} réaffectés sur {r.renegotiations}" if r.renegotiations else ""),
        f"  Convergence        : {ms['median']} ms en médiane (min {ms['min']}, max {ms['max']}),"
        f" {r.rounds_per_crew:.2f} tour(s) par équipage" if r.rounds_per_crew is not None else "  Convergence        : -",
    ]
    if r.reassignment_max_s is not None:
        lines.append(f"  Réaffectation      : {r.reassignment_max_s * 1000:.1f} ms au plus après une annulation")
    lines += [
        f"  Messages           : {r.messages} au total, {r.messages_per_crew:.1f} par équipage (max {r.max_messages_per_crew})"
        if r.messages_per_crew is not None else f"  Messages           : {r.messages} au total",
        f"  Déterminisme       : {r.distinct_fingerprints} empreinte(s) distincte(s) sur {r.runs}, {r.fingerprint[:16]}",
    ]
    if r.memory_peak_kib_first is not None:
        lines.append(f"  Mémoire (pic)      : {r.memory_peak_kib_first:.0f} Kio à la 1re exécution, "
                     f"{r.memory_peak_kib_last:.0f} Kio à la dernière ({r.memory_growth_pct:+.1f} %)")
    lines.append("  Cibles de la grille : " + ", ".join(f"{k} {ok[v]}" for k, v in r.targets.items()))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Banc de mesure du moteur multi-agents MboaRide")
    parser.add_argument("scenarios", nargs="*", default=list(SCENARIOS), help=f"parmi {', '.join(SCENARIOS)}")
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--no-memory", action="store_true", help="ne pas mesurer la mémoire (plus rapide)")
    parser.add_argument("--json", action="store_true", help="sortie JSON")
    args = parser.parse_args(argv)
    reports = [run_scenario(name, args.runs, not args.no_memory) for name in args.scenarios]
    if args.json:
        print(json.dumps([r.to_dict() for r in reports], ensure_ascii=False, indent=2))
    else:
        print("\n\n".join(format_report(r) for r in reports))
    return 0 if all(all(r.targets.values()) for r in reports) else 1


if __name__ == "__main__":
    sys.exit(main())
