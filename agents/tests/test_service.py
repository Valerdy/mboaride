"""Service agents : le moteur exposé en HTTP, tel que l'API de l'application l'appelle."""
import asyncio
import json
from dataclasses import replace
from pathlib import Path

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("httpx")
from fastapi.testclient import TestClient  # noqa: E402

from mboaride_agents import messages  # noqa: E402
from mboaride_agents.pricing import (DRIVER_ROUTE, OCCUPANTS, OFFERED_SEATS, PRODUCT_POLICY,  # noqa: E402
                                     SHARED_LEG, SHARED_LEG_PLUS_DETOUR, PricingPolicy, quote)
from mboaride_agents.routing import ESTIMATORS, Point  # noqa: E402
from mboaride_agents.service import create_app, pricing_from_env  # noqa: E402

EXAMPLES = json.loads((Path(__file__).resolve().parent.parent / "schemas" / "examples.json").read_text(encoding="utf-8"))
# Kotto -> Bonanjo, 7 h 30 - 7 h 50, mode autonome. Budget porté à 600 FCFA (prix d'un taxi) : avec la
# règle du produit, le prix d'une place (trajet du conducteur partagé entre toutes ses places) peut
# dépasser les 300 FCFA de l'exemple du protocole.
GRACE = {**EXAMPLES["nominal"][0]["body"], "max_price": 600}
AT = "2026-11-10T06:15:00+01:00"
ORG = "organization:entreprise-test"


def driver(driver_id, lat, lng, departure, **changes):
    body = {"driver_id": driver_id, "organization_id": ORG, "seats_total": 3, "max_detour_m": 3000,
            "trip": {"trip_id": f"t-{driver_id}", "origin": {"lat": lat, "lng": lng},
                     "destination": {"lat": 4.0440, "lng": 9.6935},
                     "departure_time": f"2026-11-10T{departure}:00+01:00"}}
    body.update(changes)
    return body


D07 = driver("d07", 4.0790, 9.7740, "06:55", comfort=["AIR_CONDITIONING"])   # Logpom, arrive à 7 h 33
D03 = driver("d03", 4.0850, 9.7800, "07:00")                                  # Logbessou, arrive à 7 h 41


@pytest.fixture
def client():
    c = TestClient(create_app())
    assert c.post("/organizations", json={"organization_id": "entreprise-test",
                                          "members": ["passenger:p042", "passenger:p043"]}).status_code == 201
    for d in (D07, D03):
        assert c.post("/drivers", json=d).status_code == 201
    return c


def negotiate(client, passenger="p042", **request_changes):
    return client.post("/negotiations", json={"passenger_id": passenger, "requested_at": AT,
                                              "request": {**GRACE, **request_changes}})


def test_health(client):
    assert client.get("/health").json() == {"status": "ok", "protocol": "mboaride-cnp/1"}


# --- Mode autonome (US06) ---------------------------------------------------------------------

def test_autonomous_request_returns_the_crew(client):
    r = negotiate(client)
    assert r.status_code == 201
    body = r.json()
    assert (body["conversation_id"], body["state"], body["round"]) == ("r-p042-1", "CONFIRMED", 1)
    assert body["crew"]["driver"] == "driver:d03"
    assert body["messages"] == 7 + 2 * 2
    assert client.get("/negotiations/r-p042-1").json() == body


def test_conversation_messages_follow_the_protocol(client):
    negotiate(client)
    log = client.get("/negotiations/r-p042-1/messages").json()
    assert [m["type"] for m in log] == ["RIDE_REQUEST", "CIRCLE_QUERY", "CIRCLE_ANSWER", "REQUEST_AGREED", "CFP", "CFP",
                                        "PROPOSAL", "PROPOSAL", "ACCEPT", "BOOKING_CONFIRMED", "CREW_CONFIRMED"]
    assert all(messages.validation_errors(m) == [] for m in log)


# --- Mode manuel (US05) ------------------------------------------------------------------------

def test_manual_request_returns_three_proposals_then_books_the_choice(client):
    body = negotiate(client, mode="MANUAL").json()
    assert body["state"] == "AWAITING_USER"
    assert [p["driver"] for p in body["proposals"]] == ["driver:d03", "driver:d07"]
    assert body["proposals"][0]["score"] > body["proposals"][1]["score"]
    chosen = body["proposals"][1]["offer_id"]
    after = client.post("/negotiations/r-p042-1/choice", json={"action": "choose", "offer_id": chosen}).json()
    assert (after["state"], after["crew"]["driver"], after["proposals"]) == ("CONFIRMED", "driver:d07", [])


def test_manual_user_can_withdraw(client):
    negotiate(client, mode="MANUAL")
    assert client.post("/negotiations/r-p042-1/choice", json={"action": "withdraw"}).json()["state"] == "WITHDRAWN"


def test_manual_user_can_ask_to_widen(client):
    negotiate(client, mode="MANUAL")
    body = client.post("/negotiations/r-p042-1/choice", json={"action": "widen"}).json()
    assert body["state"] == "NO_CREW"   # ni partenaire ni conducteur public dans ce jeu
    assert body["failure"]["reason"] == "NO_DRIVER_FOUND"


# --- Annulation et réaffectation (US07) ---------------------------------------------------------

def test_cancellation_reassigns_the_passenger(client):
    negotiate(client)
    r = client.post("/drivers/d03/cancellation", json={"at": "2026-11-10T06:30:00+01:00"})
    assert r.status_code == 200
    body = r.json()
    assert body["reassignment_ms"] < 2000
    (passenger,) = body["passengers"]
    assert (passenger["conversation_id"], passenger["state"]) == ("r-p042-2", "CONFIRMED")
    assert passenger["crew"]["driver"] == "driver:d07"
    assert passenger["cancelled_bookings"][0]["driver"] == "driver:d03"
    assert client.get("/negotiations/r-p042-1").json()["conversation_id"] == "r-p042-2"


def test_cancellation_errors(client):
    assert client.post("/drivers/d99/cancellation", json={"at": AT}).status_code == 404
    assert client.post("/drivers/d07/cancellation", json={"at": AT}).status_code == 200
    assert client.post("/drivers/d07/cancellation", json={"at": AT}).status_code == 409
    assert client.post("/drivers/d03/cancellation", json={"at": "2026-11-10T06:30:00"}).status_code == 422


# --- Mesures et banc -----------------------------------------------------------------------------

def test_metrics_cover_everything_processed(client):
    negotiate(client)
    m = client.get("/metrics").json()
    assert (m["requests"], m["crews"], m["messages"]) == (1, 1, 11)
    assert len(m["fingerprint"]) == 64


def test_same_calls_give_the_same_fingerprint():
    def session():
        c = TestClient(create_app())
        c.post("/organizations", json={"organization_id": "entreprise-test", "members": ["passenger:p042"]})
        for d in (D07, D03):
            c.post("/drivers", json=d)
        negotiate(c)
        return c.get("/metrics").json()["fingerprint"]
    assert len({session() for _ in range(5)}) == 1


def test_bench_endpoint(client):
    (report,) = client.post("/bench/runs", json={"scenarios": ["S1"], "runs": 2, "measure_memory": False}).json()
    assert report["scenario"] == "S1" and report["deterministic"] is True
    assert client.post("/bench/runs", json={"scenarios": ["S9"]}).status_code == 422


def test_reset_starts_from_an_empty_engine(client):
    negotiate(client)
    assert client.post("/reset").status_code == 204
    assert client.get("/negotiations/r-p042-1").status_code == 404
    assert client.get("/metrics").json()["messages"] == 0


# --- Erreurs et sécurité ---------------------------------------------------------------------------

@pytest.mark.parametrize("change, code", [
    ({"request": {**GRACE, "circles": []}}, 422),                 # demande invalide
    ({"request": {"origin": {"lat": 4.0, "lng": 9.7}}}, 422),    # champs manquants
    ({"requested_at": "2026-11-10T06:15:00"}, 422),               # heure sans fuseau
])
def test_invalid_requests_are_rejected(client, change, code):
    payload = {"passenger_id": "p042", "requested_at": AT, "request": GRACE, **change}
    assert client.post("/negotiations", json=payload).status_code == code


def test_second_request_while_one_is_pending_is_a_conflict(client):
    negotiate(client, mode="MANUAL")
    assert negotiate(client).status_code == 409


def test_choice_errors(client):
    assert client.post("/negotiations/r-x-1/choice", json={"action": "widen"}).status_code == 404
    negotiate(client)   # autonome : rien à choisir
    assert client.post("/negotiations/r-p042-1/choice", json={"action": "widen"}).status_code == 409
    assert client.post("/negotiations/r-p042-1/choice", json={"action": "choose"}).status_code == 422


def test_registration_errors(client):
    assert client.post("/drivers", json=D07).status_code == 409                        # déjà inscrit
    assert client.post("/drivers", json=driver("d09", 4.07, 9.75, "06:50", comfort=["JACUZZI"])).status_code == 422
    assert client.post("/organizations", json={"organization_id": "entreprise-test"}).status_code == 409
    assert client.post("/organizations", json={"organization_id": "o2", "members": ["p042"]}).status_code == 422


def test_service_key_is_required_when_configured():
    c = TestClient(create_app(service_key="secret-de-test"))
    assert c.get("/health").status_code == 200   # sonde de santé toujours ouverte
    assert c.get("/metrics").status_code == 401
    assert c.get("/metrics", headers={"X-Service-Key": "mauvaise"}).status_code == 401
    assert c.get("/metrics", headers={"X-Service-Key": "secret-de-test"}).status_code == 200


# --- Règle de prix : la même que l'API FastAPI ------------------------------------------------------

def first_offer(client):
    negotiate(client)
    return next(m["body"] for m in client.get("/negotiations/r-p042-1/messages").json() if m["type"] == "PROPOSAL")


def direct_route_m(offer, origin):
    """Trajet direct du conducteur (de son départ à Bonanjo), tel que l'estimateur le mesure."""
    pickup = Point.from_json(offer["pickup_point"])
    drop = Point(GRACE["destination"]["lat"], GRACE["destination"]["lng"])
    return asyncio.run(ESTIMATORS["URBAN"].detour(origin, drop, pickup, drop)).direct_distance_m


def expected_price(offer, policy, origin=None):
    return quote(policy, shared_distance_m=offer["shared_distance_m"], detour_m=offer["detour_m"],
                 direct_distance_m=direct_route_m(offer, origin) if origin else None,
                 consumption_l_per_100km=8.0, tolls=0, seats_total=3, seats_booked=0, seats_requested=1,
                 min_price=0, with_commission=False).price


def test_service_applies_the_product_pricing_rule_by_default(client):
    offer = first_offer(client)
    assert offer["price_breakdown"]["divisor"] == 4          # conducteur + les 3 places offertes
    # La première offre est celle de d07 (Logpom), qui part de 4.0790, 9.7740.
    assert offer["price"] == expected_price(offer, PRODUCT_POLICY, Point(4.0790, 9.7740))


def test_every_passenger_of_a_crew_pays_the_same_price(client):
    """Deux passagers qui montent à des endroits différents paient chacun la même somme."""
    def prices(passenger, **changes):
        negotiate(client, passenger=passenger, mode="MANUAL", **changes)
        log = client.get(f"/negotiations/r-{passenger}-1/messages").json()
        return sorted(m["body"]["price"] for m in log if m["type"] == "PROPOSAL")

    kotto = prices("p042")
    plus_loin = prices("p043", origin={"lat": 4.0745, "lng": 9.7655})
    assert len(kotto) == 2 and kotto == plus_loin


def test_old_pricing_rule_is_still_available():
    c = TestClient(create_app(pricing=PricingPolicy()))
    c.post("/organizations", json={"organization_id": "entreprise-test", "members": ["passenger:p042"]})
    for d in (D07, D03):
        c.post("/drivers", json=d)
    offer = first_offer(c)
    assert offer["price_breakdown"]["divisor"] == 4          # conducteur + 3 places offertes
    assert offer["price"] == expected_price(offer, PricingPolicy())


def test_sr51_rule_is_still_selectable():
    c = TestClient(create_app(pricing=replace(PRODUCT_POLICY, cost_basis=SHARED_LEG_PLUS_DETOUR,
                                              divisor_rule=OCCUPANTS)))
    c.post("/organizations", json={"organization_id": "entreprise-test", "members": ["passenger:p042"]})
    for d in (D07, D03):
        c.post("/drivers", json=d)
    offer = first_offer(c)
    assert offer["price_breakdown"]["divisor"] == 2          # conducteur + le seul passager à bord


def test_pricing_rule_can_be_set_by_environment(monkeypatch):
    assert pricing_from_env() == PRODUCT_POLICY
    monkeypatch.setenv("AGENTS_PRICING_COST_BASIS", SHARED_LEG)
    monkeypatch.setenv("AGENTS_PRICING_DIVISOR", OFFERED_SEATS)
    assert pricing_from_env() == replace(PRODUCT_POLICY, cost_basis=SHARED_LEG, divisor_rule=OFFERED_SEATS)
    monkeypatch.setenv("AGENTS_PRICING_DIVISOR", "AU_HASARD")
    with pytest.raises(ValueError):
        pricing_from_env()


def test_product_rule_is_the_one_measured_in_sr51():
    assert (PRODUCT_POLICY.divisor_rule, PRODUCT_POLICY.cost_basis) == (OFFERED_SEATS, DRIVER_ROUTE)
