"""Déterminisme de la négociation (SR-45) : même scénario, même solution, à chaque fois.

Une exécution est résumée par l'empreinte SHA-256 de son journal complet : deux
exécutions identiques produisent exactement les mêmes messages, dans le même ordre.
"""
import asyncio
import json
import os
import random
import subprocess
import sys
from pathlib import Path

import pytest

from mboaride_agents.bench import main as bench_main
from mboaride_agents.bench import run_scenario
from mboaride_agents.scenarios import SCENARIOS

AGENTS_DIR = Path(__file__).resolve().parent.parent


def play(scenario):
    engine = scenario.build()
    asyncio.run(scenario.play(engine))
    return engine.metrics().fingerprint, engine.assignments()


@pytest.mark.parametrize("name", list(SCENARIOS))
def test_same_scenario_10_times_gives_the_same_solution(name):
    runs = [play(SCENARIOS[name]()) for _ in range(10)]
    assert len(set(fp for fp, _ in runs)) == 1
    assert all(assignments == runs[0][1] for _, assignments in runs)
    assert runs[0][1], "le scénario doit former au moins un équipage"


@pytest.mark.parametrize("name", list(SCENARIOS))
def test_submission_order_does_not_matter(name):
    reference = play(SCENARIOS[name]())
    scenario = SCENARIOS[name]()
    random.Random(7).shuffle(scenario.requests)   # même lot, ordre de saisie différent
    assert play(scenario) == reference


FINGERPRINTS = """
import asyncio, json
from mboaride_agents.scenarios import SCENARIOS
out = {}
for name, make in SCENARIOS.items():
    scenario = make(); engine = scenario.build(); asyncio.run(scenario.play(engine))
    out[name] = engine.metrics().fingerprint
print(json.dumps(out))
"""


def test_same_solution_in_separate_processes_with_different_hash_seeds():
    """Le hachage aléatoire de Python change l'ordre des ensembles d'un processus à l'autre :
    un parcours d'ensemble non trié dans un agent ferait diverger les empreintes."""
    results = []
    for seed in ("0", "1", "12345"):
        env = {**os.environ, "PYTHONHASHSEED": seed, "PYTHONPATH": str(AGENTS_DIR)}
        done = subprocess.run([sys.executable, "-c", FINGERPRINTS], cwd=AGENTS_DIR, env=env,
                              capture_output=True, text=True, timeout=120)
        assert done.returncode == 0, done.stderr
        results.append(json.loads(done.stdout))
    in_process = {name: play(make())[0] for name, make in SCENARIOS.items()}
    assert all(r == in_process for r in results)


def test_different_seeds_give_different_scenarios():
    assert play(SCENARIOS["S1"](42))[0] != play(SCENARIOS["S1"](43))[0]


# --- Banc de mesure (SR-28) ------------------------------------------------------------------

@pytest.mark.parametrize("name", list(SCENARIOS))
def test_bench_meets_every_grid_target(name):
    report = run_scenario(name, runs=10)
    assert report.targets == {"convergence_under_2s": True, "under_20_messages_per_crew": True,
                              "deterministic": True, "memory_stable": True}
    assert report.distinct_fingerprints == 1
    assert report.memory_peak_kib_first is not None and report.memory_peak_kib_last is not None


def test_bench_report_is_json_ready():
    report = run_scenario("S3", runs=2, measure_memory=False).to_dict()
    json.dumps(report)
    assert report["scenario"] == "S3" and report["memory_growth_pct"] is None
    assert report["cancelled_crews"] >= 1 and report["reassignment_max_s"] is not None
    assert sum(report["by_type"].values()) == report["messages"]


def test_bench_command_line(capsys):
    assert bench_main(["S1", "--runs", "2", "--no-memory", "--json"]) == 0
    assert json.loads(capsys.readouterr().out)[0]["deterministic"] is True


@pytest.mark.parametrize("args", [("S9",), ("S1", 0)])
def test_bench_rejects_bad_arguments(args):
    with pytest.raises(ValueError):
        run_scenario(*args)
