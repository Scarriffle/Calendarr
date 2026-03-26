#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

export PORT="${PORT:-8080}"
export HOST="${HOST:-0.0.0.0}"
export DATA_DIR="${DATA_DIR:-./data}"

echo "Starte Calendarr auf http://${HOST}:${PORT}"

# Activate venv
if [ -f venv/bin/activate ]; then
    source venv/bin/activate
else
    echo "Fehler: Virtualenv nicht gefunden. Bitte zuerst ./install.sh ausführen." >&2
    exit 1
fi

cd "$(dirname "$0")"
python3 backend/main.py
