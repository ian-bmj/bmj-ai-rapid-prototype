output "s3_audio_bucket" {
  description = "S3 bucket name for podcast audio files"
  value       = aws_s3_bucket.audio.id
}

output "s3_data_bucket" {
  description = "S3 bucket name for transcripts, summaries, config"
  value       = aws_s3_bucket.data.id
}

output "s3_frontend_bucket" {
  description = "S3 bucket name for the admin SPA static assets"
  value       = aws_s3_bucket.frontend.id
}

output "dynamodb_podcasts_table" {
  description = "Name of the DynamoDB podcasts table"
  value       = aws_dynamodb_table.podcasts.name
}

output "dynamodb_episodes_table" {
  description = "Name of the DynamoDB episodes table"
  value       = aws_dynamodb_table.episodes.name
}

output "dynamodb_distribution_lists_table" {
  description = "Name of the DynamoDB distribution lists table"
  value       = aws_dynamodb_table.distribution_lists.name
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.admin.id
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID for the SPA"
  value       = aws_cognito_user_pool_client.spa.id
}

output "ses_sender_email" {
  description = "Verified SES sender email identity"
  value       = aws_ses_email_identity.sender.email
}

output "irsa_role_arn" {
  description = "IAM Role ARN for IRSA (pod service account annotation)"
  value       = aws_iam_role.pod_monitor.arn
}
