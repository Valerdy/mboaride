from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    corps = response.json()
    assert corps["status"] == "ok"
    # Sans serveur OSRM configuré, les itinéraires restent estimés, donc déterministes.
    assert corps["routage"] == {"mode": "estimateur"}
