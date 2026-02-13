#!/usr/bin/env bash
# BMJ Pod Monitor - Local Development Launcher
# Usage: ./run.sh [--seed]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
VENV_DIR="$BACKEND_DIR/venv"

echo "================================"
echo "  BMJ Pod Monitor - Local Dev"
echo "================================"
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not found."
    exit 1
fi

# Create virtual environment if needed
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate venv
source "$VENV_DIR/bin/activate"

# Install dependencies
echo "Installing dependencies..."
pip install -q -r "$BACKEND_DIR/requirements.txt"

# Load .env if it exists
if [ -f "$BACKEND_DIR/.env" ]; then
    echo "Loading .env file..."
    set -a
    source "$BACKEND_DIR/.env"
    set +a
fi

# Seed demo data if requested
if [ "$1" = "--seed" ]; then
    echo ""
    echo "Starting server and seeding demo data..."
    cd "$BACKEND_DIR"
    python -c "
from app import app, seed_demo_data
with app.app_context():
    seed_demo_data()
    print('Demo data seeded successfully!')
"
fi

# Start the server
echo ""
echo "Starting Pod Monitor backend..."
echo "  Admin App: http://localhost:${FLASK_PORT:-5001}"
echo "  API:       http://localhost:${FLASK_PORT:-5001}/api"
echo ""
echo "Press Ctrl+C to stop."
echo ""

cd "$BACKEND_DIR"
python app.py
