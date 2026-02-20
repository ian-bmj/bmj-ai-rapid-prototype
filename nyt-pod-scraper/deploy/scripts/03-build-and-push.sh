#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Build & Push Docker Image to ECR
# =============================================================================
# Builds the backend Docker image and pushes it to the ECR repository
# created by Terraform.
#
# Usage:
#   ./03-build-and-push.sh                # Uses 'latest' tag
#   ./03-build-and-push.sh v1.0.0         # Custom tag
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../../"
OUTPUTS_FILE="$SCRIPT_DIR/../terraform-outputs.json"
IMAGE_TAG="${1:-latest}"

echo "============================================="
echo "  BMJ Pod Monitor - Build & Push"
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

ECR_URL=$(jq -r '.ecr_repository_url.value' "$OUTPUTS_FILE")
AWS_REGION=$(jq -r '.k8s_config.value.aws_region' "$OUTPUTS_FILE")
REGISTRY_ID=$(jq -r '.ecr_registry_id.value' "$OUTPUTS_FILE")

echo "  ECR Repository: $ECR_URL"
echo "  Image Tag:      $IMAGE_TAG"
echo "  Region:         $AWS_REGION"
echo ""

# ---------------------------------------------------------------------------
# Authenticate Docker to ECR
# ---------------------------------------------------------------------------

echo "--- ECR Login ---"
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "${REGISTRY_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo ""

# ---------------------------------------------------------------------------
# Build the Docker image
# ---------------------------------------------------------------------------

echo "--- Building Docker Image ---"
cd "$PROJECT_DIR"

docker build \
    -f deploy/docker/Dockerfile \
    -t "${ECR_URL}:${IMAGE_TAG}" \
    -t "${ECR_URL}:$(git rev-parse --short HEAD 2>/dev/null || echo 'dev')" \
    .

echo ""

# ---------------------------------------------------------------------------
# Push to ECR
# ---------------------------------------------------------------------------

echo "--- Pushing to ECR ---"
docker push "${ECR_URL}:${IMAGE_TAG}"
docker push "${ECR_URL}:$(git rev-parse --short HEAD 2>/dev/null || echo 'dev')"

echo ""
echo "============================================="
echo "  Image pushed successfully!"
echo ""
echo "  Full image:  ${ECR_URL}:${IMAGE_TAG}"
echo ""
echo "  Next step: ./04-deploy-k8s.sh"
echo "============================================="
