#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Turnkey AWS Deployment
# =============================================================================
# Usage:
#   export AWS_ACCESS_KEY_ID=<your-key>
#   export AWS_SECRET_ACCESS_KEY=<your-secret>
#   export AWS_REGION=eu-west-2          # optional, defaults to eu-west-2
#   export ADMIN_EMAIL=you@bmj.com       # required
#   export SENDER_EMAIL=pods@bmj.com     # required
#
#   ./scripts/deploy-aws.sh
#
# This script:
#   1. Checks prerequisites (aws, terraform, kubectl, docker, helm)
#   2. Deploys EKS cluster via Terraform (terraform/eks/)
#   3. Deploys supporting AWS resources via Terraform (terraform/common/)
#   4. Builds and pushes the Docker image to ECR
#   5. Applies Kustomize K8s manifests (k8s/overlays/dev/)
#   6. Seeds demo data
#   7. Validates the deployment
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK="${STACK:-dev}"
REGION="${AWS_REGION:-eu-west-2}"

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# =============================================================================
# Step 0: Prerequisites
# =============================================================================
log "Checking prerequisites..."

for cmd in aws terraform kubectl docker helm jq; do
  if ! command -v "$cmd" &>/dev/null; then
    fail "$cmd is not installed. Please install it first."
  fi
done

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  fail "AWS credentials are not configured. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ok "AWS credentials valid (Account: $ACCOUNT_ID)"

# Check required env vars
: "${ADMIN_EMAIL:?'ADMIN_EMAIL must be set (e.g. export ADMIN_EMAIL=you@bmj.com)'}"
: "${SENDER_EMAIL:?'SENDER_EMAIL must be set (e.g. export SENDER_EMAIL=pods@bmj.com)'}"

ok "Prerequisites passed"

# =============================================================================
# Step 1: Deploy EKS Cluster
# =============================================================================
log "Step 1/6: Deploying EKS cluster via Terraform..."

cd "$PROJECT_DIR/terraform/eks"

# Use local backend for turnkey deployment (no pre-existing S3 state bucket needed)
cat > backend_override.tf <<'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF

terraform init -reconfigure

terraform apply -auto-approve \
  -var="accountid=$ACCOUNT_ID" \
  -var="region=$REGION" \
  -var="stack=$STACK"

# Capture outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
OIDC_PROVIDER_ID=$(terraform output -raw oidc_provider_id)

# Configure kubectl
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

ok "EKS cluster deployed: $CLUSTER_NAME"

# =============================================================================
# Step 2: Deploy Supporting AWS Resources (S3, DynamoDB, Cognito, SES, IRSA)
# =============================================================================
log "Step 2/6: Deploying supporting AWS resources..."

cd "$PROJECT_DIR/terraform/common"

cat > backend_override.tf <<'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF

terraform init -reconfigure

terraform apply -auto-approve \
  -var="accountid=$ACCOUNT_ID" \
  -var="region=$REGION" \
  -var="stack=$STACK" \
  -var="sender_email=$SENDER_EMAIL" \
  -var="admin_email=$ADMIN_EMAIL" \
  -var="eks_oidc_provider_id=$OIDC_PROVIDER_ID"

IRSA_ROLE_ARN=$(terraform output -raw irsa_role_arn)
AUDIO_BUCKET=$(terraform output -raw s3_audio_bucket)
DATA_BUCKET=$(terraform output -raw s3_data_bucket)
PODCASTS_TABLE=$(terraform output -raw dynamodb_podcasts_table)
EPISODES_TABLE=$(terraform output -raw dynamodb_episodes_table)
DIST_TABLE=$(terraform output -raw dynamodb_distribution_lists_table)

ok "Supporting resources deployed"

# =============================================================================
# Step 3: Build and Push Docker Image
# =============================================================================
log "Step 3/6: Building and pushing Docker image to ECR..."

cd "$PROJECT_DIR"

aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REPO_URL"

docker build -f deploy/docker/Dockerfile -t pod-monitor:latest .
docker tag pod-monitor:latest "$ECR_REPO_URL:latest"
docker push "$ECR_REPO_URL:latest"

ok "Docker image pushed to ECR"

# =============================================================================
# Step 4: Deploy to Kubernetes
# =============================================================================
log "Step 4/6: Deploying to Kubernetes..."

cd "$PROJECT_DIR"

# Patch the dev overlay with actual values
cat > k8s/overlays/dev/env-patch.yaml <<ENVEOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: pod-monitor-config
  namespace: pod-monitor
data:
  AWS_REGION: "$REGION"
  ENVIRONMENT: "$STACK"
  FLASK_PORT: "5001"
  FLASK_DEBUG: "0"
  AUDIO_BUCKET: "$AUDIO_BUCKET"
  DATA_BUCKET: "$DATA_BUCKET"
  PODCASTS_TABLE: "$PODCASTS_TABLE"
  EPISODES_TABLE: "$EPISODES_TABLE"
  DISTRIBUTION_TABLE: "$DIST_TABLE"
  BEDROCK_MODEL_ID: "anthropic.claude-3-5-sonnet-20241022-v2:0"
  SENDER_EMAIL: "$SENDER_EMAIL"
ENVEOF

cat > k8s/overlays/dev/serviceaccount-patch.yaml <<SAEOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-monitor
  namespace: pod-monitor
  annotations:
    eks.amazonaws.com/role-arn: "$IRSA_ROLE_ARN"
SAEOF

# Update kustomization.yaml with actual ECR URL
cat > k8s/overlays/dev/kustomization.yaml <<KUSTEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: pod-monitor

bases:
  - ../../base

images:
  - name: "REPLACE_ECR_URL"
    newName: "$ECR_REPO_URL"
    newTag: "latest"

patches:
  - path: env-patch.yaml
  - path: serviceaccount-patch.yaml
  - path: replicas-patch.yaml
KUSTEOF

# Apply via kustomize
kubectl apply -k k8s/overlays/dev/

# Wait for deployment to be ready
log "Waiting for deployment to roll out..."
kubectl rollout status deployment/pod-monitor -n pod-monitor --timeout=300s

ok "Kubernetes deployment complete"

# =============================================================================
# Step 5: Seed Demo Data
# =============================================================================
log "Step 5/6: Seeding demo data..."

# Wait for pods to be ready
sleep 10

POD_NAME=$(kubectl get pods -n pod-monitor -l component=api -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n pod-monitor "$POD_NAME" -- \
  python -c "from backend.app import app, seed_demo_data; app.app_context().__enter__(); seed_demo_data()" 2>/dev/null || \
  warn "Demo data seeding via exec failed (you can seed manually via the API)"

ok "Demo data seeded"

# =============================================================================
# Step 6: Validate
# =============================================================================
log "Step 6/6: Validating deployment..."

# Get the ALB URL
for i in {1..30}; do
  ALB_URL=$(kubectl get ingress pod-monitor -n pod-monitor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$ALB_URL" ]; then
    break
  fi
  sleep 10
done

echo ""
echo "============================================="
echo "  BMJ Pod Monitor - Deployment Complete"
echo "============================================="
echo ""
echo "  Cluster:    $CLUSTER_NAME"
echo "  Region:     $REGION"
echo "  Account:    $ACCOUNT_ID"
echo ""

if [ -n "$ALB_URL" ]; then
  echo "  Admin App:  http://$ALB_URL"
  echo "  API:        http://$ALB_URL/api/podcasts"
else
  warn "ALB URL not yet available. Check with:"
  echo "  kubectl get ingress -n pod-monitor"
fi

echo ""
echo "  Useful commands:"
echo "    kubectl get pods -n pod-monitor"
echo "    kubectl logs -l component=api -n pod-monitor -f"
echo "    kubectl get cronjobs -n pod-monitor"
echo ""
echo "  To tear down:"
echo "    ./scripts/teardown-aws.sh"
echo ""
