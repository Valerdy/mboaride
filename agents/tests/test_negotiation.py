from mboaride_agents import CoordinatorAgent, DriverAgent, OrganizationAgent, PassengerAgent
from mboaride_agents.agents import RideRequest


def run_scenario():
    drivers = [
        DriverAgent("d2", free_seats=3, min_price=300, max_detour_km=5),
        DriverAgent("d1", free_seats=3, min_price=250, max_detour_km=5),
        DriverAgent("d3", free_seats=0, min_price=200, max_detour_km=5),
    ]
    coordinator = CoordinatorAgent(drivers, OrganizationAgent("company"))
    request = RideRequest("p1", "Logpom", "Bonanjo", "08:00", max_price=400)
    offers = coordinator.collect_offers(request, {"d1": 2.0, "d2": 1.0, "d3": 0.5})
    return PassengerAgent("p1").rank(offers)


def test_best_offer_is_cheapest():
    assert run_scenario()[0].driver_id == "d1"


def test_full_driver_gives_no_offer():
    assert all(o.driver_id != "d3" for o in run_scenario())


def test_deterministic_over_10_runs():
    results = [run_scenario() for _ in range(10)]
    assert all(r == results[0] for r in results)
