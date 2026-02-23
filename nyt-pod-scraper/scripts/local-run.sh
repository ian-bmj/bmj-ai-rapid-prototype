#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Local Development (Mac / Linux)
# =============================================================================
# Usage:
#   Option A (Python - recommended for development):
#     ./scripts/local-run.sh
#     ./scripts/local-run.sh --seed    # seed demo data on startup
#
#   Option B (Docker - closer to production):
#     ./scripts/local-run.sh --docker
#     ./scripts/local-run.sh --docker --seed
#
# Prerequisites:
#   - Python 3.10+ (Option A) or Docker (Option B)
#   - Optional: LLM API key for AI features
#       export ANTHROPIC_API_KEY=sk-ant-xxx
#       export OPENAI_API_KEY=sk-xxx
#       export GOOGLE_API_KEY=AIza-xxx
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"
VENV_DIR="$BACKEND_DIR/venv"
USE_DOCKER=false
SEED=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --docker) USE_DOCKER=true ;;
    --seed) SEED=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

echo "========================================"
echo "  BMJ Pod Monitor - Local Development"
echo "========================================"
echo ""

# ---------------------------------------------------------------
# Docker mode
# ---------------------------------------------------------------
if [ "$USE_DOCKER" = true ]; then
  if ! command -v docker &>/dev/null; then
    echo "Error: Docker is required for --docker mode"
    exit 1
  fi

  echo "Starting with Docker Compose..."
  cd "$PROJECT_DIR"

  docker compose up --build -d

  if [ "$SEED" = true ]; then
    echo "Waiting for container to be healthy..."
    sleep 5
    echo "Seeding demo data..."
    curl -s -X POST http://localhost:5001/api/demo/seed | python3 -m json.tool 2>/dev/null || echo "(seeding - container may still be starting)"
  fi

  echo ""
  echo "  Admin App: http://localhost:5001"
  echo "  API:       http://localhost:5001/api"
  echo ""
  echo "  Logs:      docker compose logs -f"
  echo "  Stop:      docker compose down"
  echo ""
  exit 0
fi

# ---------------------------------------------------------------
# Python venv mode (default)
# ---------------------------------------------------------------

# Check Python
if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required but not found."
  echo "  macOS: brew install python3"
  echo "  Linux: apt install python3 python3-venv"
  exit 1
fi

# Check Python version
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "Python version: $PYVER"

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
if [ "$SEED" = true ]; then
  echo ""
  echo "Seeding demo data..."
  cd "$BACKEND_DIR"
  python3 -c "
from app import app, seed_demo_data
with app.app_context():
    seed_demo_data()
    print('Demo data seeded successfully!')
"
fi

# Start the server
echo ""
echo "Starting Pod Monitor backend..."
echo ""
echo "  Admin App: http://localhost:${FLASK_PORT:-5001}"
echo "  API:       http://localhost:${FLASK_PORT:-5001}/api"
echo ""

# Detect LLM provider
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "  LLM:       Anthropic Claude (API key detected)"
elif [ -n "${OPENAI_API_KEY:-}" ]; then
  echo "  LLM:       OpenAI GPT (API key detected)"
elif [ -n "${GOOGLE_API_KEY:-}" ]; then
  echo "  LLM:       Google Gemini (API key detected)"
else
  echo "  LLM:       None configured (set ANTHROPIC_API_KEY, OPENAI_API_KEY, or GOOGLE_API_KEY)"
fi

echo ""
echo "Press Ctrl+C to stop."
echo ""

cd "$BACKEND_DIR"
python3 app.py
