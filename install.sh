#!/usr/bin/env bash
set -euo pipefail

echo "=== Calendarr Installer ==="
echo "Debian/Ubuntu kompatibel"
echo ""

# ── System dependencies ───────────────────────────────────
echo "[1/4] Installiere Systemabhängigkeiten..."
apt-get update -q
apt-get install -y -q python3 python3-pip python3-venv python3-dev libxml2-dev libxslt1-dev

# ── Virtual environment ───────────────────────────────────
echo "[2/4] Erstelle Python-Virtualenv..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip -q

# ── Python packages ───────────────────────────────────────
echo "[3/4] Installiere Python-Pakete..."
pip install -r requirements.txt -q

# ── Configuration ─────────────────────────────────────────
echo "[4/4] Konfiguration..."
mkdir -p data

if [ ! -f .env ]; then
    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    cat > .env <<EOF
# Calendarr Konfiguration
SECRET_KEY=${SECRET}
PORT=8080
HOST=0.0.0.0
DATA_DIR=./data
EOF
    echo "  .env Datei mit zufälligem Secret erstellt"
else
    echo "  .env Datei bereits vorhanden — wird nicht überschrieben"
fi

chmod +x start.sh

echo ""
echo "=== Installation abgeschlossen ==="
echo ""
echo "Starten mit:   ./start.sh"
echo "              oder: PORT=9000 ./start.sh"
echo ""
echo "Für systemd-Dienst:"
echo "  sudo cp calendarr.service /etc/systemd/system/"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable --now calendarr"
echo ""
