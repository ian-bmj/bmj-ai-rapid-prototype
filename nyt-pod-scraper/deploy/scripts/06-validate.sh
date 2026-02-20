#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Deployment Validation
# =============================================================================
# Comprehensive validation of the entire deployment:
#   - Kubernetes resources healthy
#   - API endpoints responding
#   - Podcasts loaded
#   - AWS services accessible
#   - CronJobs scheduled
#
# Usage:
#   ./06-validate.sh                                    # Auto-detect URL
#   ./06-validate.sh http://my-alb-url.amazonaws.com    # Manual URL
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUTS_FILE="$SCRIPT_DIR/../terraform-outputs.json"

PASS=0
FAIL=0
WARN=0

echo "============================================="
echo "  BMJ Pod Monitor - Deployment Validation"
echo "============================================="
echo ""

check_pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
check_fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
check_warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }

# ---------------------------------------------------------------------------
# 1. Kubernetes Cluster
# ---------------------------------------------------------------------------

echo "--- 1. Kubernetes Cluster ---"

if kubectl cluster-info &>/dev/null; then
    check_pass "kubectl connected to cluster"
else
    check_fail "kubectl cannot connect to cluster"
fi

NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -ge 1 ]; then
    check_pass "EKS nodes ready: $NODE_COUNT node(s)"
else
    check_fail "No EKS nodes found"
fi

READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo 0)
if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    check_pass "All nodes in Ready state"
else
    check_warn "Only $READY_NODES/$NODE_COUNT nodes Ready"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Namespace & Pods
# ---------------------------------------------------------------------------

echo "--- 2. Pod Monitor Namespace ---"

if kubectl get namespace pod-monitor &>/dev/null; then
    check_pass "Namespace 'pod-monitor' exists"
else
    check_fail "Namespace 'pod-monitor' not found"
fi

POD_COUNT=$(kubectl get pods -n pod-monitor --no-headers 2>/dev/null | wc -l)
if [ "$POD_COUNT" -ge 1 ]; then
    check_pass "Pods running: $POD_COUNT pod(s)"
else
    check_fail "No pods found in pod-monitor namespace"
fi

RUNNING_PODS=$(kubectl get pods -n pod-monitor --no-headers 2>/dev/null | grep -c "Running" || echo 0)
if [ "$RUNNING_PODS" -ge 1 ]; then
    check_pass "Pods in Running state: $RUNNING_PODS"
else
    check_fail "No pods in Running state"
fi

# Check deployment
REPLICAS=$(kubectl get deployment pod-monitor-api -n pod-monitor -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED=$(kubectl get deployment pod-monitor-api -n pod-monitor -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
if [ "$REPLICAS" = "$DESIRED" ]; then
    check_pass "Deployment replicas: $REPLICAS/$DESIRED ready"
else
    check_fail "Deployment replicas: $REPLICAS/$DESIRED ready"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Services & Ingress
# ---------------------------------------------------------------------------

echo "--- 3. Services & Ingress ---"

if kubectl get svc pod-monitor-api -n pod-monitor &>/dev/null; then
    check_pass "ClusterIP service exists"
else
    check_fail "ClusterIP service not found"
fi

ALB_HOST=$(kubectl get ingress pod-monitor-ingress -n pod-monitor \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$ALB_HOST" ]; then
    check_pass "ALB provisioned: $ALB_HOST"
    API_BASE="http://${ALB_HOST}"
else
    check_warn "ALB not yet provisioned (may still be creating)"
    # Fallback to port-forward for API tests
    kubectl port-forward svc/pod-monitor-api -n pod-monitor 5001:80 &>/dev/null &
    PF_PID=$!
    trap 'kill $PF_PID 2>/dev/null || true' EXIT
    sleep 3
    API_BASE="http://localhost:5001"
fi

# Override with CLI arg if provided
API_BASE="${1:-$API_BASE}"

echo ""

# ---------------------------------------------------------------------------
# 4. API Endpoints
# ---------------------------------------------------------------------------

echo "--- 4. API Endpoints ---"

API_URL="${API_BASE}/api"

# Health check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/health" --max-time 10 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    check_pass "GET /api/health -> 200"
else
    check_fail "GET /api/health -> $HTTP_CODE"
fi

# Podcasts endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/podcasts" --max-time 10 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    check_pass "GET /api/podcasts -> 200"
    PODCAST_COUNT=$(curl -s "${API_URL}/podcasts" --max-time 10 2>/dev/null | \
        jq 'if type == "array" then length else .podcasts | length end' 2>/dev/null || echo "0")
    if [ "$PODCAST_COUNT" -ge 3 ]; then
        check_pass "Podcasts configured: $PODCAST_COUNT"
    elif [ "$PODCAST_COUNT" -ge 1 ]; then
        check_warn "Only $PODCAST_COUNT podcast(s) configured (expected 3+)"
    else
        check_warn "No podcasts configured yet (run 05-add-podcasts.sh)"
    fi
else
    check_fail "GET /api/podcasts -> $HTTP_CODE"
fi

# Config endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/config" --max-time 10 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    check_pass "GET /api/config -> 200"
else
    check_warn "GET /api/config -> $HTTP_CODE (may require auth)"
fi

# Admin SPA
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_BASE}/" --max-time 10 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    check_pass "GET / (Admin SPA) -> 200"
else
    check_warn "GET / (Admin SPA) -> $HTTP_CODE"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. CronJobs
# ---------------------------------------------------------------------------

echo "--- 5. CronJobs ---"

for cj in pod-scraper pod-daily-digest pod-weekly-digest; do
    if kubectl get cronjob "$cj" -n pod-monitor &>/dev/null; then
        SCHEDULE=$(kubectl get cronjob "$cj" -n pod-monitor -o jsonpath='{.spec.schedule}')
        check_pass "CronJob '$cj' scheduled: $SCHEDULE"
    else
        check_fail "CronJob '$cj' not found"
    fi
done

echo ""

# ---------------------------------------------------------------------------
# 6. HPA
# ---------------------------------------------------------------------------

echo "--- 6. Autoscaling ---"

if kubectl get hpa pod-monitor-api-hpa -n pod-monitor &>/dev/null; then
    HPA_MIN=$(kubectl get hpa pod-monitor-api-hpa -n pod-monitor -o jsonpath='{.spec.minReplicas}')
    HPA_MAX=$(kubectl get hpa pod-monitor-api-hpa -n pod-monitor -o jsonpath='{.spec.maxReplicas}')
    check_pass "HPA configured: min=$HPA_MIN max=$HPA_MAX"
else
    check_warn "HPA not found"
fi

echo ""

# ---------------------------------------------------------------------------
# 7. AWS Resources (from Terraform outputs)
# ---------------------------------------------------------------------------

echo "--- 7. AWS Resources ---"

if [ -f "$OUTPUTS_FILE" ]; then
    S3_AUDIO=$(jq -r '.s3_audio_bucket.value' "$OUTPUTS_FILE")
    S3_DATA=$(jq -r '.s3_data_bucket.value' "$OUTPUTS_FILE")

    if aws s3 ls "s3://${S3_AUDIO}" &>/dev/null; then
        check_pass "S3 audio bucket accessible: $S3_AUDIO"
    else
        check_fail "S3 audio bucket not accessible: $S3_AUDIO"
    fi

    if aws s3 ls "s3://${S3_DATA}" &>/dev/null; then
        check_pass "S3 data bucket accessible: $S3_DATA"
    else
        check_fail "S3 data bucket not accessible: $S3_DATA"
    fi

    DDB_TABLE=$(jq -r '.dynamodb_podcasts_table.value' "$OUTPUTS_FILE")
    if aws dynamodb describe-table --table-name "$DDB_TABLE" &>/dev/null; then
        check_pass "DynamoDB podcasts table accessible: $DDB_TABLE"
    else
        check_fail "DynamoDB podcasts table not accessible: $DDB_TABLE"
    fi

    COGNITO_POOL=$(jq -r '.cognito_user_pool_id.value' "$OUTPUTS_FILE")
    if aws cognito-idp describe-user-pool --user-pool-id "$COGNITO_POOL" &>/dev/null; then
        check_pass "Cognito user pool accessible: $COGNITO_POOL"
    else
        check_fail "Cognito user pool not accessible: $COGNITO_POOL"
    fi
else
    check_warn "terraform-outputs.json not found - skipping AWS checks"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

TOTAL=$((PASS + FAIL + WARN))

echo "============================================="
echo "  Validation Summary"
echo "============================================="
echo ""
echo "  Total checks: $TOTAL"
echo "  Passed:       $PASS"
echo "  Failed:       $FAIL"
echo "  Warnings:     $WARN"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "  STATUS: ALL CHECKS PASSED"
    echo ""
    if [ -n "$ALB_HOST" ]; then
        echo "  Your Pod Monitor is live at:"
        echo "    Admin App:  http://${ALB_HOST}"
        echo "    API:        http://${ALB_HOST}/api"
    fi
else
    echo "  STATUS: $FAIL CHECK(S) FAILED"
    echo "  Review the failures above and re-run validation."
fi

echo ""
echo "============================================="

exit "$FAIL"
