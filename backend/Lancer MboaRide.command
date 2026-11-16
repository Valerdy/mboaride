#!/bin/bash
# Double-clique sur ce fichier pour lancer MboaRide (macOS).
cd "$(dirname "$0")" || exit 1
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv >/dev/null 2>&1; then
  echo "Installation de uv (gestionnaire Python, une seule fois)…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

uv run --quiet --python 3.12 \
  --with fastapi --with uvicorn --with "psycopg[binary]" --with pydantic --with jsonschema --with pgserver \
  python lancer.py 2>&1 | tee lancement.log

echo
read -r -p "MboaRide est arrêté. Appuie sur Entrée pour fermer cette fenêtre."
