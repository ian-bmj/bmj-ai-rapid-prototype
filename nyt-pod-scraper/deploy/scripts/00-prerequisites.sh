#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - Prerequisites Check
# =============================================================================
# Verifies all required tools are installed before deployment.
# Run this first to catch any missing dependencies early.
# =============================================================================

set -euo pipefail

echo "============================================="
echo "  BMJ Pod Monitor - Prerequisites Check"
echo "============================================="
echo ""

ERRORS=0

check_command() {
    local cmd="$1"
    local name="$2"
    local install_hint="$3"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" --version 2>&1 | head -1 || echo "unknown")
        printf "  %-20s %-10s %s\n" "$name" "[OK]" "$version"
    else
        printf "  %-20s %-10s %s\n" "$name" "[MISSING]" "Install: $install_hint"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "--- Required Tools ---"
check_command "aws"       "AWS CLI"      "https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
check_command "terraform" "Terraform"    "https://developer.hashicorp.com/terraform/install"
check_command "kubectl"   "kubectl"      "https://kubernetes.io/docs/tasks/tools/"
check_command "docker"    "Docker"       "https://docs.docker.com/get-docker/"
check_command "helm"      "Helm"         "https://helm.sh/docs/intro/install/"
check_command "jq"        "jq"           "apt-get install jq / brew install jq"
check_command "curl"      "curl"         "apt-get install curl / brew install curl"
echo ""

echo "--- AWS Configuration ---"
if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    REGION=$(aws configure get region 2>/dev/null || echo "not set")
    printf "  %-20s %s\n" "Account ID:" "$ACCOUNT_ID"
    printf "  %-20s %s\n" "Identity:" "$USER_ARN"
    printf "  %-20s %s\n" "Region:" "$REGION"
else
    echo "  [ERROR] AWS CLI not configured or credentials invalid"
    echo "  Run: aws configure"
    ERRORS=$((ERRORS + 1))
fi
echo ""

echo "--- Docker Daemon ---"
if docker info &>/dev/null; then
    echo "  Docker daemon:     [RUNNING]"
else
    echo "  Docker daemon:     [NOT RUNNING] Start Docker Desktop or dockerd"
    ERRORS=$((ERRORS + 1))
fi
echo ""

echo "--- Version Requirements ---"

# Check Terraform >= 1.5
if command -v terraform &>/dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo "0.0.0")
    TF_MAJOR=$(echo "$TF_VERSION" | cut -d. -f1)
    TF_MINOR=$(echo "$TF_VERSION" | cut -d. -f2)
    if [ "$TF_MAJOR" -ge 1 ] && [ "$TF_MINOR" -ge 5 ]; then
        echo "  Terraform >= 1.5:  [OK] v${TF_VERSION}"
    else
        echo "  Terraform >= 1.5:  [FAIL] v${TF_VERSION} (need >= 1.5.0)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check AWS CLI v2
if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | grep -oP 'aws-cli/\K[0-9]+')
    if [ "$AWS_VERSION" -ge 2 ]; then
        echo "  AWS CLI v2:        [OK]"
    else
        echo "  AWS CLI v2:        [FAIL] (v1 detected, need v2)"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

if [ "$ERRORS" -gt 0 ]; then
    echo "============================================="
    echo "  FAILED: $ERRORS issue(s) found"
    echo "  Fix the above issues before proceeding."
    echo "============================================="
    exit 1
else
    echo "============================================="
    echo "  All prerequisites met!"
    echo "  Next step: ./01-iam-setup.sh"
    echo "============================================="
    exit 0
fi
