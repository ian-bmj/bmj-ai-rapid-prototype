#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Terraform Init & Apply
# =============================================================================
# Initializes Terraform and provisions the EKS cluster plus supporting
# AWS infrastructure (VPC, ECR, S3, DynamoDB, SES, Cognito).
#
# Usage:
#   ./02-terraform-init.sh                    # Uses dev.tfvars defaults
#   ./02-terraform-init.sh plan               # Plan only (no apply)
#   ADMIN_EMAIL=x@y.com SENDER_EMAIL=z@y.com ./02-terraform-init.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
ENV_FILE="$TF_DIR/environments/dev.tfvars"

ACTION="${1:-apply}"

echo "============================================="
echo "  BMJ Pod Monitor - Terraform ${ACTION^}"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

if [ -z "${ADMIN_EMAIL:-}" ]; then
    read -rp "  Admin email address: " ADMIN_EMAIL
fi
if [ -z "${SENDER_EMAIL:-}" ]; then
    read -rp "  Sender email (SES): " SENDER_EMAIL
fi

echo ""
echo "  Admin email:  $ADMIN_EMAIL"
echo "  Sender email: $SENDER_EMAIL"
echo "  Terraform:    $TF_DIR"
echo "  Env file:     $ENV_FILE"
echo ""

# ---------------------------------------------------------------------------
# Terraform init
# ---------------------------------------------------------------------------

echo "--- Terraform Init ---"
cd "$TF_DIR"
terraform init -upgrade

echo ""

# ---------------------------------------------------------------------------
# Terraform plan / apply
# ---------------------------------------------------------------------------

if [ "$ACTION" = "plan" ]; then
    echo "--- Terraform Plan ---"
    terraform plan \
        -var-file="$ENV_FILE" \
        -var "admin_email=$ADMIN_EMAIL" \
        -var "sender_email=$SENDER_EMAIL"
else
    echo "--- Terraform Apply ---"
    terraform apply \
        -var-file="$ENV_FILE" \
        -var "admin_email=$ADMIN_EMAIL" \
        -var "sender_email=$SENDER_EMAIL" \
        -auto-approve

    echo ""
    echo "--- Configuring kubectl ---"
    CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
    AWS_REGION=$(terraform output -json k8s_config | jq -r '.aws_region')

    aws eks update-kubeconfig \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION"

    echo ""
    echo "--- Saving outputs ---"
    terraform output -json > "$SCRIPT_DIR/../terraform-outputs.json"
    echo "  Outputs saved to: terraform-outputs.json"

    echo ""
    echo "--- Cluster Status ---"
    kubectl cluster-info
    kubectl get nodes

    echo ""
    echo "============================================="
    echo "  Terraform apply complete!"
    echo ""
    echo "  EKS Cluster: $CLUSTER_NAME"
    echo "  Region:      $AWS_REGION"
    echo ""
    echo "  Next step: ./03-build-and-push.sh"
    echo "============================================="
fi
