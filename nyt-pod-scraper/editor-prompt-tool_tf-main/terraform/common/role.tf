resource "aws_iam_role" "editor_prompt" {
  name               = "${var.scope}-tool-${var.stack}-bucket-role-eks"
  assume_role_policy = data.aws_iam_policy_document.editor_prompt_sts_policy.json
}

data "aws_iam_policy_document" "editor_prompt_sts_policy" {
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
        "system:serviceaccount:editor-prompt:editor-prompt-tool",
      ]
    }
  }
}

resource "aws_iam_policy" "editor_prompt_bucket_policy" {
  name   = "editor_prompt-bucket-policy-eks"
  policy = data.aws_iam_policy_document.editor_prompt_bucket_policy.json
}

data "aws_iam_policy_document" "editor_prompt_bucket_policy" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:ListObject",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    effect = "Allow"
    resources = [
      "${aws_s3_bucket.editor_prompt_tool_bucket.arn}/*",
      aws_s3_bucket.editor_prompt_tool_bucket.arn,
    ]
  }
}

resource "aws_iam_role_policy_attachment" "editor_prompt" {
  role       = aws_iam_role.editor_prompt.name
  policy_arn = aws_iam_policy.editor_prompt_bucket_policy.arn
}