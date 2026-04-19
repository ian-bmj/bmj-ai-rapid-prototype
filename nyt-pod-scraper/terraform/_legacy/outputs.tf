# =============================================================================
# NYT Pod Scraper - Terraform Outputs
# =============================================================================
#
# Output values that are needed after deployment for:
#   - Configuring the admin SPA (API URL, Cognito IDs)
#   - Connecting CI/CD pipelines (S3 bucket names, CloudFront ID)
#   - Monitoring and debugging (ARNs for AWS Console navigation)
#   - Integration testing (endpoint URLs, resource identifiers)
#
# These outputs can be consumed by:
#   - Other Terraform configurations (via terraform_remote_state)
#   - CI/CD pipelines (via terraform output -json)
#   - Developers (via terraform output)
#
# Usage:
#   terraform output                         # Show all outputs
#   terraform output cloudfront_url          # Show specific output
#   terraform output -json > config.json     # Export as JSON for SPA config
# =============================================================================

# =============================================================================
# CloudFront / Frontend
# =============================================================================

output "cloudfront_distribution_id" {
  description = <<-EOT
    CloudFront distribution ID. Used to invalidate the CDN cache when
    deploying new versions of the admin SPA:
      aws cloudfront create-invalidation --distribution-id <ID> --paths "/*"
  EOT
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_url" {
  description = <<-EOT
    CloudFront distribution URL for the admin SPA. This is the primary
    URL users will use to access the Pod Monitor admin interface.
    Format: https://d1234567890.cloudfront.net

    When a custom domain is configured, this will be replaced by the
    custom domain URL (e.g. https://pod-monitor.bmj.com).
  EOT
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (without https:// prefix)."
  value       = aws_cloudfront_distribution.frontend.domain_name
}

# =============================================================================
# API Gateway
# =============================================================================

output "api_gateway_url" {
  description = <<-EOT
    Base URL for the Pod Monitor REST API. The admin SPA uses this URL
    to make API calls. All endpoints require a valid Cognito JWT token
    in the Authorization header.

    Example API calls:
      GET  {api_url}/podcasts          - List podcasts
      POST {api_url}/podcasts          - Add podcast
      GET  {api_url}/episodes          - List episodes
      POST {api_url}/trigger/scrape    - Manual scrape trigger
      POST {api_url}/trigger/digest    - Manual digest trigger
  EOT
  value       = aws_api_gateway_stage.admin.invoke_url
}

output "api_gateway_id" {
  description = "API Gateway REST API ID. Used for API management and monitoring."
  value       = aws_api_gateway_rest_api.admin.id
}

output "api_gateway_stage_name" {
  description = "API Gateway stage name (matches the environment: dev/staging/prod)."
  value       = aws_api_gateway_stage.admin.stage_name
}

# =============================================================================
# Cognito Authentication
# =============================================================================

output "cognito_user_pool_id" {
  description = <<-EOT
    Cognito User Pool ID. Required by the admin SPA for authentication
    configuration. This value is typically set in the SPA's environment
    configuration file (e.g. .env or config.js).

    Format: eu-west-2_xxxxxxxxx
  EOT
  value       = aws_cognito_user_pool.admin.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN. Used for IAM policy references."
  value       = aws_cognito_user_pool.admin.arn
}

output "cognito_app_client_id" {
  description = <<-EOT
    Cognito App Client ID for the SPA. Required by the admin SPA for
    authentication. This is a public client (no secret) suitable for
    browser-based applications using PKCE.

    Configure in the SPA alongside the User Pool ID:
      COGNITO_USER_POOL_ID = <cognito_user_pool_id>
      COGNITO_APP_CLIENT_ID = <cognito_app_client_id>
  EOT
  value       = aws_cognito_user_pool_client.spa.id
}

output "cognito_user_pool_endpoint" {
  description = <<-EOT
    Cognito User Pool endpoint URL. Used by the SPA's authentication
    library (e.g. AWS Amplify Auth) to communicate with Cognito.
    Format: cognito-idp.eu-west-2.amazonaws.com/eu-west-2_xxxxxxxxx
  EOT
  value       = aws_cognito_user_pool.admin.endpoint
}

# =============================================================================
# S3 Buckets
# =============================================================================

output "s3_frontend_bucket" {
  description = <<-EOT
    S3 bucket name for the admin SPA static assets. CI/CD pipelines
    deploy the built SPA to this bucket:
      aws s3 sync ./dist s3://<bucket_name> --delete
  EOT
  value       = aws_s3_bucket.frontend.id
}

output "s3_frontend_bucket_arn" {
  description = "S3 frontend bucket ARN. Used for IAM policy references."
  value       = aws_s3_bucket.frontend.arn
}

output "s3_audio_bucket" {
  description = <<-EOT
    S3 bucket name for podcast audio files. Audio files are stored with
    the key pattern: {podcast_id}/{episode_id}.{extension}

    Lifecycle rules:
      - 30 days: Transition to Intelligent-Tiering
      - 365 days: Transition to Glacier
  EOT
  value       = aws_s3_bucket.audio.id
}

output "s3_audio_bucket_arn" {
  description = "S3 audio bucket ARN. Used for IAM policy references."
  value       = aws_s3_bucket.audio.arn
}

output "s3_data_bucket" {
  description = <<-EOT
    S3 bucket name for transcripts, summaries, digests, and config.
    Key prefix structure:
      transcripts/{podcast_id}/{episode_id}.json
      summaries/{podcast_id}/{episode_id}.json
      digests/daily/{YYYY-MM-DD}.json
      digests/weekly/{YYYY-Wnn}.json
      config/podcasts.json
      config/distribution_lists.json
  EOT
  value       = aws_s3_bucket.data.id
}

output "s3_data_bucket_arn" {
  description = "S3 data bucket ARN. Used for IAM policy references."
  value       = aws_s3_bucket.data.arn
}

# =============================================================================
# Step Function ARNs
# =============================================================================

output "sfn_podcast_processing_arn" {
  description = <<-EOT
    ARN of the Podcast Processing Pipeline Step Function.
    Pipeline stages: Scrape RSS -> Transcribe Audio -> Summarise Transcript

    Can be triggered manually:
      aws stepfunctions start-execution --state-machine-arn <arn> \
        --input '{"source": "manual"}'
  EOT
  value       = aws_sfn_state_machine.podcast_processing.arn
}

output "sfn_podcast_processing_name" {
  description = "Name of the Podcast Processing Pipeline Step Function."
  value       = aws_sfn_state_machine.podcast_processing.name
}

output "sfn_daily_digest_arn" {
  description = <<-EOT
    ARN of the Daily Digest Pipeline Step Function.
    Pipeline stages: Collect Summaries -> Generate Digest -> Send Email
    Scheduled: Daily at 8 AM UTC via EventBridge

    Can be triggered manually:
      aws stepfunctions start-execution --state-machine-arn <arn> \
        --input '{"source": "manual", "digest_type": "daily"}'
  EOT
  value       = aws_sfn_state_machine.daily_digest.arn
}

output "sfn_daily_digest_name" {
  description = "Name of the Daily Digest Pipeline Step Function."
  value       = aws_sfn_state_machine.daily_digest.name
}

output "sfn_weekly_digest_arn" {
  description = <<-EOT
    ARN of the Weekly Digest Pipeline Step Function.
    Pipeline stages: Collect Daily Digests -> Weekly Analysis -> Send Email
    Scheduled: Monday at 8 AM UTC via EventBridge

    Can be triggered manually:
      aws stepfunctions start-execution --state-machine-arn <arn> \
        --input '{"source": "manual", "digest_type": "weekly"}'
  EOT
  value       = aws_sfn_state_machine.weekly_digest.arn
}

output "sfn_weekly_digest_name" {
  description = "Name of the Weekly Digest Pipeline Step Function."
  value       = aws_sfn_state_machine.weekly_digest.name
}

# =============================================================================
# Lambda Functions
# =============================================================================

output "lambda_scraper_arn" {
  description = "ARN of the Pod Scraper Lambda function."
  value       = aws_lambda_function.pod_scraper.arn
}

output "lambda_transcriber_arn" {
  description = "ARN of the Pod Transcriber Lambda function."
  value       = aws_lambda_function.pod_transcriber.arn
}

output "lambda_summariser_arn" {
  description = "ARN of the Pod Summariser Lambda function."
  value       = aws_lambda_function.pod_summariser.arn
}

output "lambda_email_generator_arn" {
  description = "ARN of the Pod Email Generator Lambda function."
  value       = aws_lambda_function.pod_email_generator.arn
}

# =============================================================================
# DynamoDB Tables
# =============================================================================

output "dynamodb_podcasts_table" {
  description = "Name of the DynamoDB podcasts table."
  value       = aws_dynamodb_table.podcasts.name
}

output "dynamodb_episodes_table" {
  description = "Name of the DynamoDB episodes table."
  value       = aws_dynamodb_table.episodes.name
}

output "dynamodb_distribution_lists_table" {
  description = "Name of the DynamoDB distribution lists table."
  value       = aws_dynamodb_table.distribution_lists.name
}

# =============================================================================
# SES
# =============================================================================

output "ses_sender_email" {
  description = <<-EOT
    Verified SES sender email identity. This is the 'From' address for
    all digest emails. Ensure this identity is verified in SES before
    attempting to send emails.

    Check verification status:
      aws ses get-identity-verification-attributes \
        --identities <email>
  EOT
  value       = aws_ses_email_identity.sender.email
}

output "ses_sender_arn" {
  description = "ARN of the SES email identity."
  value       = aws_ses_email_identity.sender.arn
}

# =============================================================================
# Convenience Outputs - SPA Configuration
# =============================================================================
# These outputs are formatted specifically for use in the admin SPA's
# environment configuration. They can be exported directly:
#   terraform output -json spa_config > admin-app/config.json

output "spa_config" {
  description = <<-EOT
    Complete configuration object for the admin SPA. Export this as JSON
    and use it to configure the SPA's AWS service connections.

    Usage:
      terraform output -json spa_config > admin-app/js/aws-config.json
  EOT
  value = {
    region           = var.aws_region
    api_url          = aws_api_gateway_stage.admin.invoke_url
    user_pool_id     = aws_cognito_user_pool.admin.id
    app_client_id    = aws_cognito_user_pool_client.spa.id
    cloudfront_url   = "https://${aws_cloudfront_distribution.frontend.domain_name}"
    environment      = var.environment
  }
}

# =============================================================================
# Convenience Outputs - AWS Console URLs
# =============================================================================
# Direct links to the AWS Console for monitoring and debugging.

output "console_urls" {
  description = "Direct URLs to AWS Console pages for monitoring and management."
  value = {
    step_functions = "https://${var.aws_region}.console.aws.amazon.com/states/home?region=${var.aws_region}#/statemachines"
    lambda         = "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions"
    dynamodb       = "https://${var.aws_region}.console.aws.amazon.com/dynamodbv2/home?region=${var.aws_region}#tables"
    cloudfront     = "https://us-east-1.console.aws.amazon.com/cloudfront/v4/home#/distributions/${aws_cloudfront_distribution.frontend.id}"
    api_gateway    = "https://${var.aws_region}.console.aws.amazon.com/apigateway/main/apis/${aws_api_gateway_rest_api.admin.id}/resources?region=${var.aws_region}"
    cognito        = "https://${var.aws_region}.console.aws.amazon.com/cognito/v2/idp/user-pools/${aws_cognito_user_pool.admin.id}/users?region=${var.aws_region}"
    ses            = "https://${var.aws_region}.console.aws.amazon.com/ses/home?region=${var.aws_region}#/identities"
  }
}
