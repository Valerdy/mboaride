# Service agents MboaRide : uvicorn mboaride_agents.service:app
FROM python:3.11-slim
WORKDIR /agents
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY mboaride_agents ./mboaride_agents
COPY schemas ./schemas
ENV PYTHONUNBUFFERED=1
EXPOSE 8001
# Définir AGENTS_SERVICE_KEY au lancement pour exiger l'en-tête X-Service-Key.
CMD ["uvicorn", "mboaride_agents.service:app", "--host", "0.0.0.0", "--port", "8001"]
