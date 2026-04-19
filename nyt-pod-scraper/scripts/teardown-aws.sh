#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Teardown All AWS Resources
# =============================================================================
# WARNING: This destroys all infrastructure including data. Irreversible.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_REGION:-eu-west-2}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}"
echo "============================================="
echo "  WARNING: DESTROYING ALL POD MONITOR INFRA"
echo "============================================="
echo -e "${NC}"
echo ""
read -rp "Type 'destroy' to confirm: " CONFIRM
if [ "$CONFIRM" != "destroy" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Step 1: Removing Kubernetes resources..."
kubectl delete -k "$PROJECT_DIR/k8s/overlays/dev/" --ignore-not-found 2>/dev/null || true

echo ""
echo "Step 2: Destroying common Terraform resources..."
cd "$PROJECT_DIR/terraform/common"
if [ -f terraform.tfstate ]; then
  terraform destroy -auto-approve || true
fi

echo ""
echo "Step 3: Destroying EKS Terraform resources..."
cd "$PROJECT_DIR/terraform/eks"
if [ -f terraform.tfstate ]; then
  terraform destroy -auto-approve || true
fi

echo ""
echo -e "${GREEN}Teardown complete.${NC}"
echo "Note: Terraform state files remain locally in terraform/eks/ and terraform/common/"
