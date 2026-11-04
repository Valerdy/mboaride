from fastapi import FastAPI

app = FastAPI(title="MboaRide API", version="0.1.0")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
