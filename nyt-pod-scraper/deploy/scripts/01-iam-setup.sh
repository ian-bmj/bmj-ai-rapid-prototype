#!/usr/bin/env bash
# =============================================================================
# BMJ Pod Monitor - IAM Setup Script
# =============================================================================
# Creates IAM users, groups, and policies for deploying and operating the
# Pod Monitor EKS infrastructure. Run this with root/admin AWS credentials.
#
# Usage:
#   ./01-iam-setup.sh
#
# Prerequisites:
#   - AWS CLI v2 installed and configured with root/admin credentials
#   - jq installed
#
# This script creates:
#   1. pod-monitor-deployer   - IAM user for CI/CD and initial deployment
#   2. pod-monitor-operator   - IAM user for day-to-day operations
#   3. pod-monitor-readonly   - IAM user for monitoring/read-only access
#   4. Corresponding IAM groups and policies
#   5. Terraform state S3 bucket and DynamoDB lock table
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PROJECT_NAME="${PROJECT_NAME:-pod-monitor}"
AWS_REGION="${AWS_REGION:-eu-west-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="${PROJECT_NAME}-terraform-state-${ACCOUNT_ID}"
LOCK_TABLE="${PROJECT_NAME}-terraform-locks"

echo "============================================="
echo "  BMJ Pod Monitor - IAM Setup"
echo "============================================="
echo ""
echo "  AWS Account:  ${ACCOUNT_ID}"
echo "  Region:       ${AWS_REGION}"
echo "  Project:      ${PROJECT_NAME}"
echo ""

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

create_user_if_not_exists() {
    local username="$1"
    if aws iam get-user --user-name "$username" &>/dev/null; then
        echo "  [EXISTS] IAM user: $username"
    else
        aws iam create-user --user-name "$username" > /dev/null
        echo "  [CREATED] IAM user: $username"
    fi
}

create_group_if_not_exists() {
    local group="$1"
    if aws iam get-group --group-name "$group" &>/dev/null; then
        echo "  [EXISTS] IAM group: $group"
    else
        aws iam create-group --group-name "$group" > /dev/null
        echo "  [CREATED] IAM group: $group"
    fi
}

add_user_to_group() {
    local username="$1"
    local group="$2"
    aws iam add-user-to-group --user-name "$username" --group-name "$group" 2>/dev/null || true
    echo "  [OK] $username -> $group"
}

# ---------------------------------------------------------------------------
# Step 1: Create Terraform State Backend
# ---------------------------------------------------------------------------

echo "--- Step 1: Terraform State Backend ---"

# S3 bucket for state
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
    echo "  [EXISTS] S3 bucket: $STATE_BUCKET"
else
    aws s3api create-bucket \
        --bucket "$STATE_BUCKET" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null
    aws s3api put-bucket-versioning \
        --bucket "$STATE_BUCKET" \
        --versioning-configuration Status=Enabled
    aws s3api put-bucket-encryption \
        --bucket "$STATE_BUCKET" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    aws s3api put-public-access-block \
        --bucket "$STATE_BUCKET" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    echo "  [CREATED] S3 bucket: $STATE_BUCKET (versioned, encrypted)"
fi

# DynamoDB table for state locking
if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" &>/dev/null; then
    echo "  [EXISTS] DynamoDB table: $LOCK_TABLE"
else
    aws dynamodb create-table \
        --table-name "$LOCK_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" > /dev/null
    echo "  [CREATED] DynamoDB table: $LOCK_TABLE"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Create IAM Policies
# ---------------------------------------------------------------------------

echo "--- Step 2: IAM Policies ---"

# -- Deployer Policy: Full access to deploy EKS + supporting infra -----------

DEPLOYER_POLICY_NAME="${PROJECT_NAME}-deployer-policy"
DEPLOYER_POLICY_DOC=$(cat <<'POLICY'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EKSFullAccess",
            "Effect": "Allow",
            "Action": [
                "eks:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EC2ForEKS",
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "autoscaling:*",
                "elasticloadbalancing:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "IAMForEKS",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:GetRole",
                "iam:GetRolePolicy",
                "iam:ListRolePolicies",
                "iam:ListAttachedRolePolicies",
                "iam:PassRole",
                "iam:CreateServiceLinkedRole",
                "iam:CreateOpenIDConnectProvider",
                "iam:DeleteOpenIDConnectProvider",
                "iam:GetOpenIDConnectProvider",
                "iam:TagRole",
                "iam:UntagRole",
                "iam:TagOpenIDConnectProvider",
                "iam:ListInstanceProfilesForRole",
                "iam:CreateInstanceProfile",
                "iam:DeleteInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3FullAccess",
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        },
        {
            "Sid": "DynamoDBFullAccess",
            "Effect": "Allow",
            "Action": "dynamodb:*",
            "Resource": "*"
        },
        {
            "Sid": "ECRFullAccess",
            "Effect": "Allow",
            "Action": "ecr:*",
            "Resource": "*"
        },
        {
            "Sid": "CognitoFullAccess",
            "Effect": "Allow",
            "Action": "cognito-idp:*",
            "Resource": "*"
        },
        {
            "Sid": "SESFullAccess",
            "Effect": "Allow",
            "Action": "ses:*",
            "Resource": "*"
        },
        {
            "Sid": "BedrockAccess",
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream",
                "bedrock:ListFoundationModels",
                "bedrock:GetFoundationModel"
            ],
            "Resource": "*"
        },
        {
            "Sid": "CloudWatchLogs",
            "Effect": "Allow",
            "Action": "logs:*",
            "Resource": "*"
        },
        {
            "Sid": "KMSForEKS",
            "Effect": "Allow",
            "Action": [
                "kms:CreateGrant",
                "kms:DescribeKey",
                "kms:CreateKey",
                "kms:ListAliases"
            ],
            "Resource": "*"
        },
        {
            "Sid": "STSForEKS",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity",
                "sts:AssumeRole"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
)

DEPLOYER_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${DEPLOYER_POLICY_NAME}"
if aws iam get-policy --policy-arn "$DEPLOYER_POLICY_ARN" &>/dev/null; then
    echo "  [EXISTS] Policy: $DEPLOYER_POLICY_NAME"
    # Update the policy with a new version
    aws iam create-policy-version \
        --policy-arn "$DEPLOYER_POLICY_ARN" \
        --policy-document "$DEPLOYER_POLICY_DOC" \
        --set-as-default > /dev/null 2>&1 || true
else
    aws iam create-policy \
        --policy-name "$DEPLOYER_POLICY_NAME" \
        --policy-document "$DEPLOYER_POLICY_DOC" > /dev/null
    echo "  [CREATED] Policy: $DEPLOYER_POLICY_NAME"
fi

# -- Operator Policy: Manage k8s, ECR push, trigger pipelines ----------------

OPERATOR_POLICY_NAME="${PROJECT_NAME}-operator-policy"
OPERATOR_POLICY_DOC=$(cat <<'POLICY'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EKSAccess",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:AccessKubernetesApi"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECRPushPull",
            "Effect": "Allow",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:GetAuthorizationToken",
                "ecr:DescribeRepositories",
                "ecr:ListImages"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3DataAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": "*"
        },
        {
            "Sid": "DynamoDBAccess",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SESAccess",
            "Effect": "Allow",
            "Action": [
                "ses:SendEmail",
                "ses:SendRawEmail",
                "ses:GetIdentityVerificationAttributes"
            ],
            "Resource": "*"
        },
        {
            "Sid": "CognitoAdmin",
            "Effect": "Allow",
            "Action": [
                "cognito-idp:AdminCreateUser",
                "cognito-idp:AdminSetUserPassword",
                "cognito-idp:ListUsers",
                "cognito-idp:DescribeUserPool"
            ],
            "Resource": "*"
        },
        {
            "Sid": "CloudWatchRead",
            "Effect": "Allow",
            "Action": [
                "logs:GetLogEvents",
                "logs:FilterLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
)

OPERATOR_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${OPERATOR_POLICY_NAME}"
if aws iam get-policy --policy-arn "$OPERATOR_POLICY_ARN" &>/dev/null; then
    echo "  [EXISTS] Policy: $OPERATOR_POLICY_NAME"
    aws iam create-policy-version \
        --policy-arn "$OPERATOR_POLICY_ARN" \
        --policy-document "$OPERATOR_POLICY_DOC" \
        --set-as-default > /dev/null 2>&1 || true
else
    aws iam create-policy \
        --policy-name "$OPERATOR_POLICY_NAME" \
        --policy-document "$OPERATOR_POLICY_DOC" > /dev/null
    echo "  [CREATED] Policy: $OPERATOR_POLICY_NAME"
fi

# -- Read-Only Policy --------------------------------------------------------

READONLY_POLICY_NAME="${PROJECT_NAME}-readonly-policy"
READONLY_POLICY_DOC=$(cat <<'POLICY'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EKSReadOnly",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:ListNodegroups",
                "eks:DescribeNodegroup"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3ReadOnly",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": "*"
        },
        {
            "Sid": "DynamoDBReadOnly",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:DescribeTable"
            ],
            "Resource": "*"
        },
        {
            "Sid": "CloudWatchRead",
            "Effect": "Allow",
            "Action": [
                "logs:GetLogEvents",
                "logs:FilterLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "cloudwatch:GetMetricData",
                "cloudwatch:ListMetrics"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECRRead",
            "Effect": "Allow",
            "Action": [
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
)

READONLY_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${READONLY_POLICY_NAME}"
if aws iam get-policy --policy-arn "$READONLY_POLICY_ARN" &>/dev/null; then
    echo "  [EXISTS] Policy: $READONLY_POLICY_NAME"
    aws iam create-policy-version \
        --policy-arn "$READONLY_POLICY_ARN" \
        --policy-document "$READONLY_POLICY_DOC" \
        --set-as-default > /dev/null 2>&1 || true
else
    aws iam create-policy \
        --policy-name "$READONLY_POLICY_NAME" \
        --policy-document "$READONLY_POLICY_DOC" > /dev/null
    echo "  [CREATED] Policy: $READONLY_POLICY_NAME"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Create IAM Groups
# ---------------------------------------------------------------------------

echo "--- Step 3: IAM Groups ---"

create_group_if_not_exists "${PROJECT_NAME}-deployers"
create_group_if_not_exists "${PROJECT_NAME}-operators"
create_group_if_not_exists "${PROJECT_NAME}-readonly"

# Attach policies to groups
aws iam attach-group-policy --group-name "${PROJECT_NAME}-deployers" \
    --policy-arn "$DEPLOYER_POLICY_ARN" 2>/dev/null || true
echo "  [OK] ${PROJECT_NAME}-deployers <- deployer-policy"

aws iam attach-group-policy --group-name "${PROJECT_NAME}-operators" \
    --policy-arn "$OPERATOR_POLICY_ARN" 2>/dev/null || true
echo "  [OK] ${PROJECT_NAME}-operators <- operator-policy"

aws iam attach-group-policy --group-name "${PROJECT_NAME}-readonly" \
    --policy-arn "$READONLY_POLICY_ARN" 2>/dev/null || true
echo "  [OK] ${PROJECT_NAME}-readonly <- readonly-policy"

echo ""

# ---------------------------------------------------------------------------
# Step 4: Create IAM Users
# ---------------------------------------------------------------------------

echo "--- Step 4: IAM Users ---"

create_user_if_not_exists "${PROJECT_NAME}-deployer"
create_user_if_not_exists "${PROJECT_NAME}-operator"
create_user_if_not_exists "${PROJECT_NAME}-readonly"

add_user_to_group "${PROJECT_NAME}-deployer" "${PROJECT_NAME}-deployers"
add_user_to_group "${PROJECT_NAME}-operator" "${PROJECT_NAME}-operators"
add_user_to_group "${PROJECT_NAME}-readonly" "${PROJECT_NAME}-readonly"

echo ""

# ---------------------------------------------------------------------------
# Step 5: Create Access Keys (only for new users)
# ---------------------------------------------------------------------------

echo "--- Step 5: Access Keys ---"

CREDS_DIR="./iam-credentials"
mkdir -p "$CREDS_DIR"

for user in "${PROJECT_NAME}-deployer" "${PROJECT_NAME}-operator" "${PROJECT_NAME}-readonly"; do
    EXISTING_KEYS=$(aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
    if [ -n "$EXISTING_KEYS" ] && [ "$EXISTING_KEYS" != "None" ]; then
        echo "  [SKIP] $user already has access keys"
    else
        KEY_OUTPUT=$(aws iam create-access-key --user-name "$user" --output json)
        ACCESS_KEY=$(echo "$KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
        SECRET_KEY=$(echo "$KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')

        cat > "${CREDS_DIR}/${user}.env" <<EOF
# AWS credentials for ${user}
# KEEP THESE SECURE - do not commit to version control
AWS_ACCESS_KEY_ID=${ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${SECRET_KEY}
AWS_DEFAULT_REGION=${AWS_REGION}
EOF
        chmod 600 "${CREDS_DIR}/${user}.env"
        echo "  [CREATED] Access key for $user -> ${CREDS_DIR}/${user}.env"
    fi
done

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "============================================="
echo "  IAM Setup Complete"
echo "============================================="
echo ""
echo "  Users created:"
echo "    ${PROJECT_NAME}-deployer   - Full deploy access (Terraform + EKS)"
echo "    ${PROJECT_NAME}-operator   - Day-to-day operations (k8s, ECR, data)"
echo "    ${PROJECT_NAME}-readonly   - Monitoring and read-only access"
echo ""
echo "  Terraform state backend:"
echo "    S3 Bucket:      ${STATE_BUCKET}"
echo "    DynamoDB Table:  ${LOCK_TABLE}"
echo ""
echo "  Credentials saved to: ${CREDS_DIR}/"
echo ""
echo "  IMPORTANT:"
echo "  1. Distribute credentials securely (never email/Slack/commit)"
echo "  2. Add ${CREDS_DIR}/ to .gitignore"
echo "  3. For the deployer user, configure AWS CLI:"
echo "     aws configure --profile ${PROJECT_NAME}-deployer"
echo ""
echo "  Next step: Run 00-prerequisites.sh to verify the environment"
echo "============================================="
