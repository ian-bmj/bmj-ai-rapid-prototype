#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Deploy Kubernetes Manifests
# =============================================================================
# Applies Kubernetes manifests with values substituted from Terraform outputs.
# Deploys: namespace, service account, configmap, deployment, service,
#          ingress, cronjobs, and HPA.
#
# Usage:
#   ./04-deploy-k8s.sh                # Uses 'latest' image tag
#   ./04-deploy-k8s.sh v1.0.0         # Custom image tag
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../k8s"
OUTPUTS_FILE="$SCRIPT_DIR/../terraform-outputs.json"
IMAGE_TAG="${1:-latest}"

echo "============================================="
echo "  BMJ Pod Monitor - Kubernetes Deploy"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Load Terraform outputs
# ---------------------------------------------------------------------------

if [ ! -f "$OUTPUTS_FILE" ]; then
    echo "ERROR: terraform-outputs.json not found."
    echo "Run 02-terraform-init.sh first."
    exit 1
fi

K8S_CONFIG=$(jq -r '.k8s_config.value' "$OUTPUTS_FILE")

ECR_URL=$(jq -r '.ecr_repository_url.value' "$OUTPUTS_FILE")
IRSA_ROLE_ARN=$(echo "$K8S_CONFIG" | jq -r '.irsa_role_arn')
AWS_REGION=$(echo "$K8S_CONFIG" | jq -r '.aws_region')
S3_AUDIO=$(echo "$K8S_CONFIG" | jq -r '.s3_audio_bucket')
S3_DATA=$(echo "$K8S_CONFIG" | jq -r '.s3_data_bucket')
DDB_PODCASTS=$(echo "$K8S_CONFIG" | jq -r '.dynamodb_podcasts')
DDB_EPISODES=$(echo "$K8S_CONFIG" | jq -r '.dynamodb_episodes')
SES_SENDER=$(echo "$K8S_CONFIG" | jq -r '.ses_sender_email')
BEDROCK_MODEL=$(echo "$K8S_CONFIG" | jq -r '.bedrock_model_id')
COGNITO_POOL=$(echo "$K8S_CONFIG" | jq -r '.cognito_pool_id')
COGNITO_CLIENT=$(echo "$K8S_CONFIG" | jq -r '.cognito_client_id')

FULL_IMAGE="${ECR_URL}:${IMAGE_TAG}"

echo "  Image:         $FULL_IMAGE"
echo "  IRSA Role:     $IRSA_ROLE_ARN"
echo "  Audio Bucket:  $S3_AUDIO"
echo "  Data Bucket:   $S3_DATA"
echo ""

# ---------------------------------------------------------------------------
# Create temp directory with substituted manifests
# ---------------------------------------------------------------------------

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "--- Substituting values in manifests ---"

for file in "$K8S_DIR"/*.yaml; do
    basename=$(basename "$file")
    sed \
        -e "s|IRSA_ROLE_ARN_PLACEHOLDER|${IRSA_ROLE_ARN}|g" \
        -e "s|ECR_IMAGE_PLACEHOLDER|${FULL_IMAGE}|g" \
        -e "s|S3_AUDIO_BUCKET_PLACEHOLDER|${S3_AUDIO}|g" \
        -e "s|S3_DATA_BUCKET_PLACEHOLDER|${S3_DATA}|g" \
        -e "s|DYNAMODB_PODCASTS_PLACEHOLDER|${DDB_PODCASTS}|g" \
        -e "s|DYNAMODB_EPISODES_PLACEHOLDER|${DDB_EPISODES}|g" \
        -e "s|SES_SENDER_PLACEHOLDER|${SES_SENDER}|g" \
        -e "s|COGNITO_POOL_PLACEHOLDER|${COGNITO_POOL}|g" \
        -e "s|COGNITO_CLIENT_PLACEHOLDER|${COGNITO_CLIENT}|g" \
        -e "s|eu-west-2|${AWS_REGION}|g" \
        "$file" > "$TEMP_DIR/$basename"
    echo "  [OK] $basename"
done

echo ""

# ---------------------------------------------------------------------------
# Apply manifests in order
# ---------------------------------------------------------------------------

echo "--- Applying Kubernetes manifests ---"

# 1. Namespace first
kubectl apply -f "$TEMP_DIR/namespace.yaml"
echo "  [OK] namespace"

# 2. Service account (with IRSA)
kubectl apply -f "$TEMP_DIR/service-account.yaml"
echo "  [OK] service-account"

# 3. ConfigMap
kubectl apply -f "$TEMP_DIR/configmap.yaml"
echo "  [OK] configmap"

# 4. Deployment
kubectl apply -f "$TEMP_DIR/deployment.yaml"
echo "  [OK] deployment"

# 5. Service
kubectl apply -f "$TEMP_DIR/service.yaml"
echo "  [OK] service"

# 6. Ingress (ALB)
kubectl apply -f "$TEMP_DIR/ingress.yaml"
echo "  [OK] ingress"

# 7. CronJobs
kubectl apply -f "$TEMP_DIR/cronjob-scraper.yaml"
echo "  [OK] cronjobs"

# 8. HPA
kubectl apply -f "$TEMP_DIR/hpa.yaml"
echo "  [OK] hpa"

echo ""

# ---------------------------------------------------------------------------
# Wait for deployment
# ---------------------------------------------------------------------------

echo "--- Waiting for pods to be ready ---"
kubectl rollout status deployment/pod-monitor-api -n pod-monitor --timeout=300s

echo ""
echo "--- Pod Status ---"
kubectl get pods -n pod-monitor -o wide

echo ""
echo "--- Services ---"
kubectl get svc -n pod-monitor

echo ""
echo "--- Ingress (ALB URL) ---"
echo "  Waiting for ALB provisioning (this can take 2-3 minutes)..."
sleep 10

for i in $(seq 1 30); do
    ALB_URL=$(kubectl get ingress pod-monitor-ingress -n pod-monitor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$ALB_URL" ]; then
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 10
done

echo ""
if [ -n "$ALB_URL" ]; then
    echo "============================================="
    echo "  Deployment complete!"
    echo ""
    echo "  Admin App:  http://${ALB_URL}"
    echo "  API:        http://${ALB_URL}/api"
    echo "  Health:     http://${ALB_URL}/api/health"
    echo ""
    echo "  Next step: ./05-add-podcasts.sh"
    echo "============================================="
else
    echo "============================================="
    echo "  Deployment complete but ALB not ready yet."
    echo "  Check ALB status with:"
    echo "    kubectl get ingress -n pod-monitor"
    echo ""
    echo "  Next step: ./05-add-podcasts.sh"
    echo "============================================="
fi
