# =============================================================================
# BMJ Pod Monitor - EKS Deployment Outputs
# =============================================================================

# --- EKS Cluster -------------------------------------------------------------

output "eks_cluster_name" {
  description = "EKS cluster name. Use with: aws eks update-kubeconfig --name <name>"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = aws_eks_cluster.main.version
}

# --- ECR ---------------------------------------------------------------------

output "ecr_repository_url" {
  description = "ECR repository URL for the backend image."
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_registry_id" {
  description = "ECR registry ID (AWS account ID)."
  value       = aws_ecr_repository.backend.registry_id
}

# --- S3 Buckets --------------------------------------------------------------

output "s3_audio_bucket" {
  description = "S3 bucket for podcast audio files."
  value       = aws_s3_bucket.audio.id
}

output "s3_data_bucket" {
  description = "S3 bucket for transcripts, summaries, config."
  value       = aws_s3_bucket.data.id
}

output "s3_frontend_bucket" {
  description = "S3 bucket for admin SPA static assets."
  value       = aws_s3_bucket.frontend.id
}

# --- DynamoDB -----------------------------------------------------------------

output "dynamodb_podcasts_table" {
  description = "DynamoDB table for podcast metadata."
  value       = aws_dynamodb_table.podcasts.name
}

output "dynamodb_episodes_table" {
  description = "DynamoDB table for episode metadata."
  value       = aws_dynamodb_table.episodes.name
}

output "dynamodb_distribution_lists_table" {
  description = "DynamoDB table for email distribution lists."
  value       = aws_dynamodb_table.distribution_lists.name
}

# --- Cognito ------------------------------------------------------------------

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for admin authentication."
  value       = aws_cognito_user_pool.admin.id
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID for the SPA."
  value       = aws_cognito_user_pool_client.spa.id
}

# --- SES ----------------------------------------------------------------------

output "ses_sender_email" {
  description = "SES sender email (must be verified before sending)."
  value       = aws_ses_email_identity.sender.email
}

# --- IRSA Role ----------------------------------------------------------------

output "irsa_role_arn" {
  description = "IAM role ARN for pod-monitor Kubernetes service account (IRSA)."
  value       = aws_iam_role.pod_monitor_irsa.arn
}

# --- VPC / Networking ---------------------------------------------------------

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS workers)."
  value       = aws_subnet.private[*].id
}

# --- Convenience: Kubernetes Config -------------------------------------------

output "k8s_config" {
  description = "Values needed for Kubernetes manifest templating."
  value = {
    namespace          = local.k8s_namespace
    service_account    = local.k8s_sa_name
    irsa_role_arn      = aws_iam_role.pod_monitor_irsa.arn
    ecr_repository_url = aws_ecr_repository.backend.repository_url
    aws_region         = var.aws_region
    s3_audio_bucket    = aws_s3_bucket.audio.id
    s3_data_bucket     = aws_s3_bucket.data.id
    dynamodb_podcasts  = aws_dynamodb_table.podcasts.name
    dynamodb_episodes  = aws_dynamodb_table.episodes.name
    ses_sender_email   = var.sender_email
    bedrock_model_id   = var.bedrock_model_id
    cognito_pool_id    = aws_cognito_user_pool.admin.id
    cognito_client_id  = aws_cognito_user_pool_client.spa.id
  }
}
