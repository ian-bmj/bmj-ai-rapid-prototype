#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Add Science Podcasts
# =============================================================================
# Adds three real science/health podcasts to the deployed Pod Monitor
# using the REST API. These are genuine, freely available RSS feeds.
#
# Podcasts added:
#   1. Nature Podcast       - Weekly from Nature journal
#   2. The Lancet Voice     - From The Lancet medical journal
#   3. Science Friday       - NPR's popular science radio show
#
# Usage:
#   ./05-add-podcasts.sh                               # Auto-detect ALB URL
#   ./05-add-podcasts.sh http://my-alb-url.amazonaws.com  # Manual URL
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================="
echo "  BMJ Pod Monitor - Add Science Podcasts"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Determine API URL
# ---------------------------------------------------------------------------

if [ -n "${1:-}" ]; then
    API_BASE="$1"
else
    # Auto-detect from Kubernetes ingress
    ALB_HOST=$(kubectl get ingress pod-monitor-ingress -n pod-monitor \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [ -n "$ALB_HOST" ]; then
        API_BASE="http://${ALB_HOST}"
    else
        # Fallback: port-forward
        echo "  ALB not found. Using kubectl port-forward..."
        kubectl port-forward svc/pod-monitor-api -n pod-monitor 5001:80 &
        PF_PID=$!
        trap 'kill $PF_PID 2>/dev/null || true' EXIT
        sleep 3
        API_BASE="http://localhost:5001"
    fi
fi

API_URL="${API_BASE}/api"
echo "  API URL: ${API_URL}"
echo ""

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

echo "--- Health Check ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "  API is healthy [200 OK]"
else
    echo "  ERROR: API returned HTTP $HTTP_CODE"
    echo "  Check pod status: kubectl get pods -n pod-monitor"
    exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# Add Podcast 1: Nature Podcast
# ---------------------------------------------------------------------------

echo "--- Adding Podcast 1: Nature Podcast ---"
RESPONSE=$(curl -s -X POST "${API_URL}/podcasts" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Nature Podcast",
        "url": "https://feeds.nature.com/nature/podcast/current",
        "category": "Science & Research",
        "description": "Weekly science news and research highlights from Nature, one of the worlds leading scientific journals. Covers breakthrough discoveries across biology, physics, medicine, and environmental science.",
        "active": true
    }')
echo "  Response: $RESPONSE"
echo ""

# ---------------------------------------------------------------------------
# Add Podcast 2: The Lancet Voice
# ---------------------------------------------------------------------------

echo "--- Adding Podcast 2: The Lancet Voice ---"
RESPONSE=$(curl -s -X POST "${API_URL}/podcasts" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "The Lancet Voice",
        "url": "https://feeds.acast.com/public/shows/the-lancet-voice",
        "category": "Medical Science",
        "description": "The Lancet Voice features discussions on the latest medical research, global health policy, and clinical medicine from editors and researchers at The Lancet, the worlds oldest and most prestigious medical journal.",
        "active": true
    }')
echo "  Response: $RESPONSE"
echo ""

# ---------------------------------------------------------------------------
# Add Podcast 3: Science Friday
# ---------------------------------------------------------------------------

echo "--- Adding Podcast 3: Science Friday ---"
RESPONSE=$(curl -s -X POST "${API_URL}/podcasts" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Science Friday",
        "url": "https://feeds.megaphone.fm/sciencefriday",
        "category": "General Science",
        "description": "NPRs Science Friday covers the latest in science, technology, and the environment. Hosted by Ira Flatow, it brings accessible science journalism to a broad audience with interviews from leading researchers.",
        "active": true
    }')
echo "  Response: $RESPONSE"
echo ""

# ---------------------------------------------------------------------------
# Verify podcasts were added
# ---------------------------------------------------------------------------

echo "--- Verifying Podcasts ---"
PODCASTS=$(curl -s "${API_URL}/podcasts")
COUNT=$(echo "$PODCASTS" | jq 'if type == "array" then length else .podcasts | length end' 2>/dev/null || echo "?")
echo "  Total podcasts: $COUNT"
echo "$PODCASTS" | jq -r '
    if type == "array" then .[]
    else .podcasts[]
    end |
    "  - \(.name) [\(.category)] (active: \(.active))"
' 2>/dev/null || echo "  (Raw response: $PODCASTS)"

echo ""

# ---------------------------------------------------------------------------
# Trigger initial scrape
# ---------------------------------------------------------------------------

echo "--- Triggering Initial Scrape ---"
echo "  This will fetch RSS feeds and download the latest episodes..."
RESPONSE=$(curl -s -X POST "${API_URL}/scrape-all" --max-time 120 2>/dev/null || echo '{"error": "timeout - scrape running in background"}')
echo "  Response: $RESPONSE"

echo ""
echo "============================================="
echo "  Science podcasts added successfully!"
echo ""
echo "  Podcasts:"
echo "    1. Nature Podcast       (Nature journal)"
echo "    2. The Lancet Voice     (The Lancet)"
echo "    3. Science Friday       (NPR)"
echo ""
echo "  An initial scrape has been triggered."
echo "  Episodes will appear in the admin dashboard shortly."
echo ""
echo "  Admin App: ${API_BASE}"
echo ""
echo "  Next step: ./06-validate.sh"
echo "============================================="
