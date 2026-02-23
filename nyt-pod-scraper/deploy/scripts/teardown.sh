#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Teardown / Cleanup
# =============================================================================
# Destroys all Kubernetes resources and Terraform-managed infrastructure.
# USE WITH CAUTION - this is irreversible.
#
# Usage:
#   ./teardown.sh              # Interactive (asks for confirmation)
#   ./teardown.sh --confirm    # Skip confirmation
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
ENV_FILE="$TF_DIR/environments/dev.tfvars"

echo "============================================="
echo "  BMJ Pod Monitor - TEARDOWN"
echo "============================================="
echo ""
echo "  WARNING: This will destroy ALL infrastructure:"
echo "    - EKS cluster and all pods"
echo "    - ECR repository and all images"
echo "    - S3 buckets and all data"
echo "    - DynamoDB tables and all records"
echo "    - Cognito user pool"
echo "    - VPC and networking"
echo ""

if [ "${1:-}" != "--confirm" ]; then
    read -rp "  Type 'DESTROY' to confirm: " CONFIRM
    if [ "$CONFIRM" != "DESTROY" ]; then
        echo "  Aborted."
        exit 1
    fi
fi

echo ""
echo "--- Deleting Kubernetes resources ---"
kubectl delete namespace pod-monitor --ignore-not-found=true 2>/dev/null || true
echo "  [OK] Namespace deleted"

echo ""
echo "--- Terraform Destroy ---"
cd "$TF_DIR"

if [ -f "$ENV_FILE" ]; then
    terraform destroy \
        -var-file="$ENV_FILE" \
        -var "admin_email=teardown@example.com" \
        -var "sender_email=teardown@example.com" \
        -auto-approve
else
    terraform destroy -auto-approve
fi

echo ""
echo "============================================="
echo "  Teardown complete."
echo "  All resources have been destroyed."
echo "============================================="
