# =============================================================================
# IAM - Roles and Policies for EKS Pod Access (IRSA)
# =============================================================================
# Uses aws_iam_policy_document data sources following BMJ conventions.
# The IRSA role allows K8s pods to access S3, DynamoDB, SES, and Bedrock.
# =============================================================================

data "aws_iam_policy_document" "pod_monitor_sts_policy" {
  statement {
    sid     = "STSassumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${var.accountid}:oidc-provider/oidc.eks.${var.region}.amazonaws.com/id/${var.eks_oidc_provider_id}"]
    }
    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${var.region}.amazonaws.com/id/${var.eks_oidc_provider_id}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${var.region}.amazonaws.com/id/${var.eks_oidc_provider_id}:sub"
      values = [
        "system:serviceaccount:${var.namespace}:${var.product}",
      ]
    }
  }
}

resource "aws_iam_role" "pod_monitor" {
  name               = "${var.scope}-tool-${var.stack}-role-eks"
  assume_role_policy = data.aws_iam_policy_document.pod_monitor_sts_policy.json
}

# --- S3 Access Policy -------------------------------------------------------

data "aws_iam_policy_document" "pod_monitor_s3_policy" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    effect = "Allow"
    resources = [
      aws_s3_bucket.audio.arn,
      "${aws_s3_bucket.audio.arn}/*",
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*",
      aws_s3_bucket.frontend.arn,
      "${aws_s3_bucket.frontend.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "pod_monitor_s3" {
  name   = "${var.scope}-s3-policy-eks"
  policy = data.aws_iam_policy_document.pod_monitor_s3_policy.json
}

resource "aws_iam_role_policy_attachment" "pod_monitor_s3" {
  role       = aws_iam_role.pod_monitor.name
  policy_arn = aws_iam_policy.pod_monitor_s3.arn
}

# --- DynamoDB Access Policy --------------------------------------------------

data "aws_iam_policy_document" "pod_monitor_dynamodb_policy" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem"
    ]
    effect = "Allow"
    resources = [
      aws_dynamodb_table.podcasts.arn,
      "${aws_dynamodb_table.podcasts.arn}/index/*",
      aws_dynamodb_table.episodes.arn,
      "${aws_dynamodb_table.episodes.arn}/index/*",
      aws_dynamodb_table.distribution_lists.arn,
      "${aws_dynamodb_table.distribution_lists.arn}/index/*",
    ]
  }
}

resource "aws_iam_policy" "pod_monitor_dynamodb" {
  name   = "${var.scope}-dynamodb-policy-eks"
  policy = data.aws_iam_policy_document.pod_monitor_dynamodb_policy.json
}

resource "aws_iam_role_policy_attachment" "pod_monitor_dynamodb" {
  role       = aws_iam_role.pod_monitor.name
  policy_arn = aws_iam_policy.pod_monitor_dynamodb.arn
}

# --- SES Access Policy -------------------------------------------------------

data "aws_iam_policy_document" "pod_monitor_ses_policy" {
  statement {
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail"
    ]
    effect    = "Allow"
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.sender_email]
    }
  }
}

resource "aws_iam_policy" "pod_monitor_ses" {
  name   = "${var.scope}-ses-policy-eks"
  policy = data.aws_iam_policy_document.pod_monitor_ses_policy.json
}

resource "aws_iam_role_policy_attachment" "pod_monitor_ses" {
  role       = aws_iam_role.pod_monitor.name
  policy_arn = aws_iam_policy.pod_monitor_ses.arn
}

# --- Bedrock Access Policy ---------------------------------------------------

data "aws_iam_policy_document" "pod_monitor_bedrock_policy" {
  statement {
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:bedrock:${var.region}::foundation-model/${var.bedrock_model_id}",
      "arn:aws:bedrock:${var.region}::foundation-model/*"
    ]
  }
}

resource "aws_iam_policy" "pod_monitor_bedrock" {
  name   = "${var.scope}-bedrock-policy-eks"
  policy = data.aws_iam_policy_document.pod_monitor_bedrock_policy.json
}

resource "aws_iam_role_policy_attachment" "pod_monitor_bedrock" {
  role       = aws_iam_role.pod_monitor.name
  policy_arn = aws_iam_policy.pod_monitor_bedrock.arn
}
