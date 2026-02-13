# =============================================================================
# NYT Pod Scraper - AWS Infrastructure (Terraform)
# =============================================================================
#
# Architecture Overview:
# This Terraform configuration provisions the full AWS infrastructure for the
# Pod Monitor tool, inspired by the NYT "Manosphere Report" and adapted for
# BMJ's use case. The architecture follows the BMJ serverless pattern:
#
#   CloudFront -> S3 (SPA)
#   CloudFront -> API Gateway -> Lambda (REST API)
#   EventBridge -> Step Functions -> Lambda (Processing Pipelines)
#   Cognito (Authentication)
#   Bedrock (AI/ML - Transcription & Summarisation)
#   SES (Email Delivery)
#   DynamoDB (Metadata Storage)
#   S3 (Audio, Transcripts, Summaries, Config)
#
# Data Flow:
#   1. EventBridge triggers daily podcast scraping via Step Functions
#   2. Pod-scraper Lambda fetches RSS feeds, downloads new audio to S3
#   3. Pod-transcriber Lambda sends audio to Bedrock/Whisper for transcription
#   4. Pod-summariser Lambda sends transcripts to Bedrock Claude for summaries
#   5. Daily digest pipeline collates summaries, generates email, sends via SES
#   6. Weekly digest pipeline analyses daily digests for broader themes
#   7. Admin SPA (served via CloudFront/S3) manages podcasts and distribution
#   8. API Gateway + Cognito provides authenticated REST API for the SPA
#
# Note: This configuration is for planning and architecture review purposes.
# Lambda function code is referenced as placeholder zip files. Actual
# deployment requires packaging the Lambda functions from the backend/ directory.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration for remote state storage.
  # Uncomment and configure when ready to deploy.
  # backend "s3" {
  #   bucket         = "bmj-terraform-state"
  #   key            = "pod-monitor/terraform.tfstate"
  #   region         = "eu-west-2"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Team        = "BMJ-AI"
    }
  }
}

# Secondary provider for CloudFront ACM certificates (must be us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Team        = "BMJ-AI"
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values used across multiple resources for consistent naming
locals {
  # Resource naming convention: {project}-{environment}-{resource}
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags applied to all resources in addition to provider default_tags
  common_tags = {
    Application = "pod-monitor"
    CostCentre  = "bmj-ai-initiatives"
  }

  # Account and region for IAM policy ARN construction
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}


# =============================================================================
# S3 BUCKETS
# =============================================================================
# Three buckets with distinct purposes following the separation-of-concerns
# principle. This keeps IAM policies granular and costs transparent.
# =============================================================================

# -----------------------------------------------------------------------------
# Frontend Bucket - Static Website Hosting for the Admin SPA
# -----------------------------------------------------------------------------
# Serves the React/Vue/vanilla JS single-page application. CloudFront sits
# in front of this bucket to provide HTTPS, caching, and custom domain support.
# The bucket itself is NOT publicly accessible; access is via CloudFront OAI.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend"

  tags = merge(local.common_tags, {
    Purpose = "SPA static website hosting"
  })
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html" # SPA client-side routing - all paths resolve to index.html
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAI"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.frontend.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Audio Bucket - Podcast Audio File Storage
# -----------------------------------------------------------------------------
# Stores downloaded podcast audio files (MP3, M4A, etc.). These files can be
# large (50-200MB each for long-form podcasts), so lifecycle rules move older
# audio to Intelligent-Tiering to optimise costs. Audio is retained for
# re-processing but is not frequently accessed after initial transcription.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "audio" {
  bucket = "${local.name_prefix}-audio"

  tags = merge(local.common_tags, {
    Purpose = "Podcast audio file storage"
  })
}

resource "aws_s3_bucket_versioning" "audio" {
  bucket = aws_s3_bucket.audio.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "audio" {
  bucket = aws_s3_bucket.audio.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "audio" {
  bucket = aws_s3_bucket.audio.id

  rule {
    id     = "transition-to-intelligent-tiering"
    status = "Enabled"

    # Audio files older than 30 days are unlikely to be re-accessed frequently.
    # Intelligent-Tiering automatically moves them between access tiers.
    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    # Audio older than 365 days moves to Glacier for long-term archival.
    # This is a cost optimisation; audio can be restored if re-processing
    # is needed, but it takes minutes-to-hours to retrieve from Glacier.
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

# Server-side encryption for audio files at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "audio" {
  bucket = aws_s3_bucket.audio.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Bucket - Transcripts, Summaries, and Configuration
# -----------------------------------------------------------------------------
# Stores all processed text data: transcripts (JSON), summaries (JSON/Markdown),
# digest emails (HTML), and application configuration. This bucket is accessed
# frequently by Lambda functions and the admin SPA (via signed URLs).
# Organised by key prefix:
#   transcripts/{podcast_id}/{episode_id}.json
#   summaries/{podcast_id}/{episode_id}.json
#   digests/daily/{date}.json
#   digests/weekly/{week}.json
#   config/podcasts.json
#   config/distribution_lists.json
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "data" {
  bucket = "${local.name_prefix}-data"

  tags = merge(local.common_tags, {
    Purpose = "Transcripts, summaries, and configuration"
  })
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


# =============================================================================
# CLOUDFRONT DISTRIBUTION
# =============================================================================
# CloudFront serves as the single entry point for the frontend SPA.
# Benefits over direct S3 access:
#   - HTTPS with managed certificates
#   - Global edge caching for low-latency access
#   - Custom domain support
#   - DDoS protection via AWS Shield Standard
#   - Origin Access Identity prevents direct S3 access
# =============================================================================

resource "aws_cloudfront_origin_access_identity" "frontend" {
  comment = "OAI for ${local.name_prefix} frontend SPA"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} - Admin SPA"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US, Canada, Europe only - sufficient for BMJ

  # Origin: S3 bucket hosting the SPA static assets
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path
    }
  }

  # Default cache behaviour for static assets (JS, CSS, images)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600     # 1 hour default cache
    max_ttl                = 86400    # 24 hour max cache
    compress               = true     # Gzip compression for text assets
  }

  # SPA routing: all 404s return index.html so client-side routing works.
  # The SPA framework (React Router, Vue Router, etc.) handles the actual
  # route resolution on the client side.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # No geographic restrictions needed
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # When a custom domain is added, replace with:
    # acm_certificate_arn      = aws_acm_certificate.frontend.arn
    # ssl_support_method       = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(local.common_tags, {
    Purpose = "Frontend SPA distribution"
  })
}


# =============================================================================
# DYNAMODB TABLES
# =============================================================================
# DynamoDB is used for structured metadata that requires fast lookups and
# querying. The actual content (audio, transcripts, summaries) lives in S3;
# DynamoDB stores the pointers and metadata. This follows the recommended
# pattern of using DynamoDB for hot metadata and S3 for cold/large objects.
#
# All tables use on-demand (PAY_PER_REQUEST) billing to avoid capacity
# planning during the early stages. This can be switched to provisioned
# capacity with auto-scaling once usage patterns are established.
# =============================================================================

# -----------------------------------------------------------------------------
# Podcasts Table - Podcast Feed Metadata
# -----------------------------------------------------------------------------
# Tracks which podcasts are being monitored, their RSS feed URLs, categories,
# and whether they are actively being scraped. The admin SPA manages this
# table through the API Gateway.
#
# Access patterns:
#   - Get podcast by ID (primary key lookup)
#   - List all active podcasts (scan with filter, acceptable for ~80 items)
#   - List podcasts by category (GSI)
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "podcasts" {
  name         = "${local.name_prefix}-podcasts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  attribute {
    name = "active"
    type = "S" # "true"/"false" - DynamoDB GSI keys must be scalar types
  }

  # GSI for querying podcasts by category (e.g. "politics", "health", "culture")
  global_secondary_index {
    name            = "category-index"
    hash_key        = "category"
    projection_type = "ALL"
  }

  # GSI for listing only active podcasts (avoids scanning the full table)
  global_secondary_index {
    name            = "active-index"
    hash_key        = "active"
    projection_type = "ALL"
  }

  # Point-in-time recovery for disaster recovery
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Podcast feed metadata"
  })
}

# -----------------------------------------------------------------------------
# Episodes Table - Episode Data and Processing Status
# -----------------------------------------------------------------------------
# Tracks individual podcast episodes, their processing status through the
# pipeline, and S3 keys for associated content (audio, transcript, summary).
#
# Access patterns:
#   - Get episode by ID (primary key lookup)
#   - List episodes for a podcast, sorted by published date (GSI)
#   - Find episodes by processing status (GSI for pipeline monitoring)
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "episodes" {
  name         = "${local.name_prefix}-episodes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "podcast_id"
    type = "S"
  }

  attribute {
    name = "published"
    type = "S" # ISO 8601 date string for sortable range queries
  }

  attribute {
    name = "status"
    type = "S" # "pending", "scraping", "transcribing", "summarising", "complete", "error"
  }

  # GSI for listing episodes of a specific podcast, sorted by publish date.
  # This is the primary query pattern for the admin SPA episode list view.
  global_secondary_index {
    name            = "podcast-episodes-index"
    hash_key        = "podcast_id"
    range_key       = "published"
    projection_type = "ALL"
  }

  # GSI for pipeline monitoring: find all episodes in a given processing state.
  # Used by Step Functions to identify episodes that need processing and by
  # the admin SPA to show pipeline status.
  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "published"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Episode data and processing status"
  })
}

# -----------------------------------------------------------------------------
# Distribution Lists Table - Email Distribution Management
# -----------------------------------------------------------------------------
# Manages email distribution lists for the daily and weekly digest emails.
# Simple structure: each list type (daily/weekly) has an associated set of
# email addresses. Managed through the admin SPA.
#
# Access patterns:
#   - Get distribution list by type (primary key lookup)
#   - Simple structure, no GSIs needed
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "distribution_lists" {
  name         = "${local.name_prefix}-distribution-lists"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "list_type" # "daily" or "weekly"

  attribute {
    name = "list_type"
    type = "S"
  }

  # The 'emails' attribute is a String Set (SS) stored as a non-key attribute.
  # DynamoDB does not require non-key attributes to be declared in the schema.

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Email distribution list management"
  })
}


# =============================================================================
# COGNITO - Authentication
# =============================================================================
# Cognito User Pool provides authentication for the admin SPA. This is a
# simple setup for internal BMJ editorial staff. The user pool handles:
#   - User registration (admin-invited only)
#   - Login with email/password
#   - JWT token issuance for API Gateway authorisation
#   - Password policies and MFA (optional)
#
# The admin SPA uses the Cognito Hosted UI or Amplify Auth library to handle
# the OAuth2/OIDC flow. API Gateway validates the JWT tokens using a
# Cognito authoriser.
# =============================================================================

resource "aws_cognito_user_pool" "admin" {
  name = "${local.name_prefix}-admin-pool"

  # Users can only be created by administrators (not self-registration).
  # This is appropriate for an internal editorial tool.
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Your Pod Monitor Admin Account"
      email_message = "Your username is {username} and temporary password is {####}. Please log in at the Pod Monitor admin portal to set your permanent password."
      sms_message   = "Your Pod Monitor username is {username} and temporary password is {####}."
    }
  }

  # Email-based authentication
  username_attributes = ["email"]

  # Automatically verify email addresses
  auto_verified_attributes = ["email"]

  # Password policy - strong defaults for internal tool
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # Schema attributes for user profiles
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Account recovery via email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Admin authentication"
  })
}

# App client for the SPA - no client secret (public client for browser apps)
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${local.name_prefix}-spa-client"
  user_pool_id = aws_cognito_user_pool.admin.id

  # Public client: no secret, suitable for SPA (browser-based) apps.
  # The SPA uses PKCE (Proof Key for Code Exchange) for secure auth.
  generate_secret = false

  # Explicit auth flows
  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",      # Secure Remote Password protocol
  ]

  # Token validity configuration
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevent user existence errors from leaking information
  prevent_user_existence_errors = "ENABLED"

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]
}

# Admin group for elevated permissions (e.g. managing podcasts and distribution lists)
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.admin.id
  description  = "Administrators with full access to Pod Monitor management"
}

# Read-only group for journalists who only need to view reports
resource "aws_cognito_user_group" "viewer" {
  name         = "viewer"
  user_pool_id = aws_cognito_user_pool.admin.id
  description  = "Viewers with read-only access to podcast data and reports"
}


# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================
# Follows the principle of least privilege. Each Lambda function gets its own
# execution role with only the permissions it needs. Step Functions gets a
# separate role that can invoke the Lambda functions.
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Execution Role - Shared base role for all Lambda functions
# -----------------------------------------------------------------------------
# All Lambda functions share a common assume-role trust policy but have
# individual permission policies attached for their specific needs.
# -----------------------------------------------------------------------------

# Base IAM role that Lambda functions can assume
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Lambda function execution"
  })
}

# CloudWatch Logs policy - all Lambdas need to write logs
resource "aws_iam_role_policy" "lambda_logging" {
  name = "${local.name_prefix}-lambda-logging"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      }
    ]
  })
}

# DynamoDB access policy - read/write to all pod-monitor tables
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${local.name_prefix}-lambda-dynamodb"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.podcasts.arn,
          "${aws_dynamodb_table.podcasts.arn}/index/*",
          aws_dynamodb_table.episodes.arn,
          "${aws_dynamodb_table.episodes.arn}/index/*",
          aws_dynamodb_table.distribution_lists.arn,
          "${aws_dynamodb_table.distribution_lists.arn}/index/*"
        ]
      }
    ]
  })
}

# S3 access policy - read/write to audio and data buckets
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.name_prefix}-lambda-s3"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.audio.arn,
          "${aws_s3_bucket.audio.arn}/*",
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
        ]
      }
    ]
  })
}

# Bedrock access policy - invoke models for transcription and summarisation
resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${local.name_prefix}-lambda-bedrock"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          # Claude model for summarisation
          "arn:aws:bedrock:${local.region}::foundation-model/${var.bedrock_model_id}",
          # Whisper model for transcription (if available on Bedrock)
          "arn:aws:bedrock:${local.region}::foundation-model/*"
        ]
      }
    ]
  })
}

# SES access policy - send digest emails
resource "aws_iam_role_policy" "lambda_ses" {
  name = "${local.name_prefix}-lambda-ses"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.sender_email
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Step Functions Execution Role
# -----------------------------------------------------------------------------
# Step Functions needs permission to invoke the Lambda functions that form
# the processing pipeline steps.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "step_functions_execution" {
  name = "${local.name_prefix}-sfn-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Step Functions orchestration"
  })
}

resource "aws_iam_role_policy" "step_functions_invoke_lambda" {
  name = "${local.name_prefix}-sfn-invoke-lambda"
  role = aws_iam_role.step_functions_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.pod_scraper.arn,
          aws_lambda_function.pod_transcriber.arn,
          aws_lambda_function.pod_summariser.arn,
          aws_lambda_function.pod_email_generator.arn
        ]
      },
      {
        # Step Functions needs CloudWatch Logs access for execution logging
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# EventBridge Role - Permission to start Step Functions executions
# -----------------------------------------------------------------------------
resource "aws_iam_role" "eventbridge_execution" {
  name = "${local.name_prefix}-eventbridge-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "EventBridge scheduled triggers"
  })
}

resource "aws_iam_role_policy" "eventbridge_start_sfn" {
  name = "${local.name_prefix}-eventbridge-start-sfn"
  role = aws_iam_role.eventbridge_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = [
          aws_sfn_state_machine.podcast_processing.arn,
          aws_sfn_state_machine.daily_digest.arn,
          aws_sfn_state_machine.weekly_digest.arn
        ]
      }
    ]
  })
}


# =============================================================================
# LAMBDA FUNCTIONS
# =============================================================================
# Each Lambda function handles a specific stage of the podcast processing
# pipeline. Functions are designed to be stateless and idempotent.
#
# Note: The 'filename' references placeholder zip files. In production,
# these would be built from the backend/ directory using a CI/CD pipeline
# or the `archive_file` data source. The placeholder approach allows
# Terraform planning without requiring compiled function code.
# =============================================================================

# Placeholder archive for Lambda deployment packages.
# In production, replace with actual built Lambda deployment packages.
# You can use the archive_file data source or CI/CD to build these.
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/lambda_placeholder.zip"

  source {
    content  = "# Placeholder - replace with actual Lambda function code"
    filename = "handler.py"
  }
}

# -----------------------------------------------------------------------------
# Pod Scraper Lambda
# -----------------------------------------------------------------------------
# Scrapes RSS feeds for configured podcasts, identifies new episodes, and
# downloads audio files to S3. Updates DynamoDB with episode metadata.
#
# Triggered by: Step Functions (podcast-processing-pipeline)
# Reads from: DynamoDB (podcasts table), RSS feeds (internet)
# Writes to: S3 (audio bucket), DynamoDB (episodes table)
# Timeout: 5 minutes (some podcast feeds are slow, audio downloads can be large)
# Memory: 512MB (sufficient for RSS parsing and streaming audio downloads)
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "pod_scraper" {
  function_name = "${local.name_prefix}-pod-scraper"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes
  memory_size   = 512

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      PODCASTS_TABLE      = aws_dynamodb_table.podcasts.name
      EPISODES_TABLE      = aws_dynamodb_table.episodes.name
      AUDIO_BUCKET        = aws_s3_bucket.audio.id
      DATA_BUCKET         = aws_s3_bucket.data.id
      ENVIRONMENT         = var.environment
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "RSS feed scraping and audio download"
  })
}

# -----------------------------------------------------------------------------
# Pod Transcriber Lambda
# -----------------------------------------------------------------------------
# Transcribes podcast audio using Amazon Bedrock or Amazon Transcribe.
# Takes an episode ID, retrieves audio from S3, sends to transcription
# service, and stores the resulting transcript in S3.
#
# Triggered by: Step Functions (podcast-processing-pipeline)
# Reads from: S3 (audio bucket), DynamoDB (episodes table)
# Writes to: S3 (data bucket - transcripts/), DynamoDB (episodes table - status)
# Timeout: 15 minutes (transcription of long podcasts can take several minutes)
# Memory: 1024MB (audio processing may require more memory)
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "pod_transcriber" {
  function_name = "${local.name_prefix}-pod-transcriber"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 900  # 15 minutes (max Lambda timeout)
  memory_size   = 1024

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      EPISODES_TABLE      = aws_dynamodb_table.episodes.name
      AUDIO_BUCKET        = aws_s3_bucket.audio.id
      DATA_BUCKET         = aws_s3_bucket.data.id
      BEDROCK_MODEL_ID    = var.bedrock_model_id
      ENVIRONMENT         = var.environment
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Audio transcription via Bedrock/Whisper"
  })
}

# -----------------------------------------------------------------------------
# Pod Summariser Lambda
# -----------------------------------------------------------------------------
# Generates summaries, gists, and thematic analysis of podcast transcripts
# using Amazon Bedrock (Claude). Takes an episode ID, retrieves the
# transcript from S3, sends to Claude for analysis, and stores results in S3.
#
# The prompt engineering for summarisation is critical to the tool's value.
# Summaries include: executive summary, key talking points, notable quotes,
# sentiment analysis, and thematic tags.
#
# Triggered by: Step Functions (podcast-processing-pipeline)
# Reads from: S3 (data bucket - transcripts/), DynamoDB (episodes table)
# Writes to: S3 (data bucket - summaries/), DynamoDB (episodes table - status)
# Timeout: 5 minutes (Claude responses are typically fast)
# Memory: 512MB (text processing is not memory-intensive)
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "pod_summariser" {
  function_name = "${local.name_prefix}-pod-summariser"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes
  memory_size   = 512

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      EPISODES_TABLE      = aws_dynamodb_table.episodes.name
      DATA_BUCKET         = aws_s3_bucket.data.id
      BEDROCK_MODEL_ID    = var.bedrock_model_id
      ENVIRONMENT         = var.environment
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Transcript summarisation via Bedrock Claude"
  })
}

# -----------------------------------------------------------------------------
# Pod Email Generator Lambda
# -----------------------------------------------------------------------------
# Generates and sends digest emails (daily and weekly). Collects summaries
# from S3, sends them to Claude for meta-analysis to identify cross-podcast
# themes and trends, generates an HTML email, and sends it via SES.
#
# Daily digest: Summarises all new episodes from the past 24 hours
# Weekly digest: Analyses all daily digests from the past week, identifies
#   broader trends, shifts in rhetoric, and emerging themes.
#
# Triggered by: Step Functions (daily-digest-pipeline, weekly-digest-pipeline)
# Reads from: S3 (data bucket - summaries/, digests/), DynamoDB (distribution_lists)
# Writes to: S3 (data bucket - digests/), SES (email delivery)
# Timeout: 5 minutes
# Memory: 512MB
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "pod_email_generator" {
  function_name = "${local.name_prefix}-pod-email-generator"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes
  memory_size   = 512

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      EPISODES_TABLE         = aws_dynamodb_table.episodes.name
      DISTRIBUTION_TABLE     = aws_dynamodb_table.distribution_lists.name
      DATA_BUCKET            = aws_s3_bucket.data.id
      BEDROCK_MODEL_ID       = var.bedrock_model_id
      SENDER_EMAIL           = var.sender_email
      ENVIRONMENT            = var.environment
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Digest email generation and delivery"
  })
}

# CloudWatch Log Groups for Lambda functions (explicit creation for retention control)
resource "aws_cloudwatch_log_group" "pod_scraper" {
  name              = "/aws/lambda/${aws_lambda_function.pod_scraper.function_name}"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "pod_transcriber" {
  name              = "/aws/lambda/${aws_lambda_function.pod_transcriber.function_name}"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "pod_summariser" {
  name              = "/aws/lambda/${aws_lambda_function.pod_summariser.function_name}"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "pod_email_generator" {
  name              = "/aws/lambda/${aws_lambda_function.pod_email_generator.function_name}"
  retention_in_days = 30

  tags = local.common_tags
}


# =============================================================================
# STEP FUNCTIONS - Processing Pipelines
# =============================================================================
# Step Functions orchestrates the multi-step podcast processing workflows.
# Using Step Functions rather than direct Lambda-to-Lambda invocation provides:
#   - Visual execution monitoring in the AWS Console
#   - Built-in retry logic with exponential backoff
#   - Error handling and compensation logic
#   - Execution history and audit trail
#   - Parallel processing support (process multiple episodes concurrently)
# =============================================================================

# -----------------------------------------------------------------------------
# Podcast Processing Pipeline
# -----------------------------------------------------------------------------
# Orchestrates the processing of new podcast episodes:
#   1. Scrape RSS feeds and download new audio
#   2. For each new episode (in parallel):
#      a. Transcribe audio
#      b. Summarise transcript
#   3. Update episode status to "complete"
#
# This pipeline runs on a schedule (via EventBridge) and can also be
# triggered manually from the admin SPA for on-demand processing.
# -----------------------------------------------------------------------------
resource "aws_sfn_state_machine" "podcast_processing" {
  name     = "${local.name_prefix}-podcast-processing"
  role_arn = aws_iam_role.step_functions_execution.arn

  definition = jsonencode({
    Comment = "Podcast Processing Pipeline: Scrape -> Transcribe -> Summarise"
    StartAt = "ScrapeFeeds"
    States = {
      # Step 1: Scrape all active podcast RSS feeds and download new audio
      ScrapeFeeds = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pod_scraper.arn
          Payload = {
            "action"    = "scrape_all"
            "timestamp" = "$.execution_time"
          }
        }
        ResultPath = "$.scrape_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed", "Lambda.ServiceException"]
            IntervalSeconds = 30
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleScrapeError"
            ResultPath  = "$.error"
          }
        ]
        Next = "CheckNewEpisodes"
      }

      # Check if any new episodes were found
      CheckNewEpisodes = {
        Type    = "Choice"
        Choices = [
          {
            Variable     = "$.scrape_result.Payload.new_episode_count"
            NumericGreaterThan = 0
            Next         = "ProcessEpisodes"
          }
        ]
        Default = "NoNewEpisodes"
      }

      # Step 2: Process each new episode in parallel (Map state)
      ProcessEpisodes = {
        Type       = "Map"
        ItemsPath  = "$.scrape_result.Payload.new_episodes"
        MaxConcurrency = 5  # Limit parallel processing to control costs
        Iterator = {
          StartAt = "TranscribeEpisode"
          States = {
            # Step 2a: Transcribe the episode audio
            TranscribeEpisode = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.pod_transcriber.arn
                Payload = {
                  "episode_id.$" = "$.episode_id"
                }
              }
              ResultPath = "$.transcribe_result"
              Retry = [
                {
                  ErrorEquals     = ["States.TaskFailed"]
                  IntervalSeconds = 60
                  MaxAttempts     = 2
                  BackoffRate     = 2.0
                }
              ]
              Catch = [
                {
                  ErrorEquals = ["States.ALL"]
                  Next        = "HandleEpisodeError"
                  ResultPath  = "$.error"
                }
              ]
              Next = "SummariseEpisode"
            }

            # Step 2b: Summarise the transcript
            SummariseEpisode = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.pod_summariser.arn
                Payload = {
                  "episode_id.$" = "$.episode_id"
                }
              }
              ResultPath = "$.summarise_result"
              Retry = [
                {
                  ErrorEquals     = ["States.TaskFailed"]
                  IntervalSeconds = 30
                  MaxAttempts     = 2
                  BackoffRate     = 2.0
                }
              ]
              Catch = [
                {
                  ErrorEquals = ["States.ALL"]
                  Next        = "HandleEpisodeError"
                  ResultPath  = "$.error"
                }
              ]
              End = true
            }

            # Error handler for individual episode processing failures
            HandleEpisodeError = {
              Type = "Pass"
              Parameters = {
                "episode_id.$" = "$.episode_id"
                "error.$"      = "$.error"
                "status"       = "error"
              }
              End = true
            }
          }
        }
        Next = "ProcessingComplete"
      }

      # Terminal: No new episodes found
      NoNewEpisodes = {
        Type    = "Succeed"
        Comment = "No new episodes to process"
      }

      # Terminal: All episodes processed
      ProcessingComplete = {
        Type    = "Succeed"
        Comment = "All new episodes have been processed"
      }

      # Error handler for feed scraping failures
      HandleScrapeError = {
        Type = "Fail"
        Error = "ScrapeError"
        Cause = "Failed to scrape podcast feeds after retries"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_podcast_processing.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = merge(local.common_tags, {
    Purpose = "Podcast episode processing orchestration"
  })
}

# -----------------------------------------------------------------------------
# Daily Digest Pipeline
# -----------------------------------------------------------------------------
# Generates and sends the daily digest email at 8 AM:
#   1. Collect all episode summaries from the past 24 hours
#   2. Generate a meta-summary with cross-podcast themes and trends
#   3. Format and send the digest email to the daily distribution list
#
# This mirrors the NYT "Manosphere Report" daily email workflow.
# -----------------------------------------------------------------------------
resource "aws_sfn_state_machine" "daily_digest" {
  name     = "${local.name_prefix}-daily-digest"
  role_arn = aws_iam_role.step_functions_execution.arn

  definition = jsonencode({
    Comment = "Daily Digest Pipeline: Collect summaries -> Generate digest -> Send email"
    StartAt = "CollectDailySummaries"
    States = {
      # Step 1: Collect all summaries from the past 24 hours
      CollectDailySummaries = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pod_email_generator.arn
          Payload = {
            "action"      = "collect_summaries"
            "digest_type" = "daily"
            "lookback_hours" = 24
          }
        }
        ResultPath = "$.collect_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 30
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleDigestError"
            ResultPath  = "$.error"
          }
        ]
        Next = "CheckSummariesExist"
      }

      # Check if there are any summaries to include in the digest
      CheckSummariesExist = {
        Type    = "Choice"
        Choices = [
          {
            Variable     = "$.collect_result.Payload.summary_count"
            NumericGreaterThan = 0
            Next         = "GenerateDailyDigest"
          }
        ]
        Default = "NoSummariesAvailable"
      }

      # Step 2: Generate the daily digest meta-summary using Claude
      GenerateDailyDigest = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pod_email_generator.arn
          Payload = {
            "action"       = "generate_digest"
            "digest_type"  = "daily"
            "summaries.$"  = "$.collect_result.Payload.summaries"
          }
        }
        ResultPath = "$.digest_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleDigestError"
            ResultPath  = "$.error"
          }
        ]
        Next = "SendDailyEmail"
      }

      # Step 3: Send the digest email via SES
      SendDailyEmail = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pod_email_generator.arn
          Payload = {
            "action"       = "send_email"
            "digest_type"  = "daily"
            "digest.$"     = "$.digest_result.Payload.digest"
          }
        }
        ResultPath = "$.send_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 60
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleDigestError"
            ResultPath  = "$.error"
          }
        ]
        Next = "DailyDigestComplete"
      }

      NoSummariesAvailable = {
        Type    = "Succeed"
        Comment = "No new summaries available for daily digest"
      }

      DailyDigestComplete = {
        Type    = "Succeed"
        Comment = "Daily digest email sent successfully"
      }

      HandleDigestError = {
        Type  = "Fail"
        Error = "DigestError"
        Cause = "Failed to generate or send daily digest email"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_daily_digest.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = merge(local.common_tags, {
    Purpose = "Daily digest email generation and delivery"
  })
}

# -----------------------------------------------------------------------------
# Weekly Digest Pipeline
# -----------------------------------------------------------------------------
# Generates and sends the weekly analysis email on Monday at 8 AM:
#   1. Collect all daily digests from the past 7 days
#   2. Generate a weekly analysis identifying broader trends, shifts in
#      rhetoric, emerging themes, and notable patterns across the week
#   3. Format and send the weekly analysis email
#
# The weekly digest provides a higher-level strategic view compared to the
# daily tactical summary. It is particularly useful for identifying gradual
# shifts in podcast narratives over time.
# -----------------------------------------------------------------------------
resource "aws_sfn_state_machine" "weekly_digest" {
  name     = "${local.name_prefix}-weekly-digest"
  role_arn = aws_iam_role.step_functions_execution.arn

  definition = jsonencode({
    Comment = "Weekly Digest Pipeline: Collect daily digests -> Weekly analysis -> Send email"
    StartAt = "CollectWeeklyDigests"
    States = {
      # Step 1: Collect all daily digests from the past 7 days
      CollectWeeklyDigests = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pod_email_generator.arn
          Payload = {
            "action"      = "collect_summaries"
            "digest_type" = "weekly"
            "lookback_days" = 7
          }
        }
        ResultPath = "$.collect_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 30
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleWeeklyError"
            ResultPath  = "$.error"
          }
        ]
        Next = "CheckDigestsExist"
      }

      # Check if there are daily digests to analyse
      CheckDigestsExist = {
        Type    = "Choice"
        Choices = [
          {
            Variable     = "$.collect_result.Payload.digest_count"
            NumericGreaterThan = 0
            Next         = "GenerateWeeklyAnalysis"
          }
        ]
        Default = "NoDigestsAvailable"
      }

      # Step 2: Generate weekly analysis using Claude
      GenerateWeeklyAnalysis = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pod_email_generator.arn
          Payload = {
            "action"       = "generate_digest"
            "digest_type"  = "weekly"
            "digests.$"    = "$.collect_result.Payload.digests"
          }
        }
        ResultPath = "$.digest_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleWeeklyError"
            ResultPath  = "$.error"
          }
        ]
        Next = "SendWeeklyEmail"
      }

      # Step 3: Send the weekly analysis email via SES
      SendWeeklyEmail = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pod_email_generator.arn
          Payload = {
            "action"       = "send_email"
            "digest_type"  = "weekly"
            "digest.$"     = "$.digest_result.Payload.digest"
          }
        }
        ResultPath = "$.send_result"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 60
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleWeeklyError"
            ResultPath  = "$.error"
          }
        ]
        Next = "WeeklyDigestComplete"
      }

      NoDigestsAvailable = {
        Type    = "Succeed"
        Comment = "No daily digests available for weekly analysis"
      }

      WeeklyDigestComplete = {
        Type    = "Succeed"
        Comment = "Weekly analysis email sent successfully"
      }

      HandleWeeklyError = {
        Type  = "Fail"
        Error = "WeeklyDigestError"
        Cause = "Failed to generate or send weekly digest email"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_weekly_digest.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = merge(local.common_tags, {
    Purpose = "Weekly analysis email generation and delivery"
  })
}

# CloudWatch Log Groups for Step Functions
resource "aws_cloudwatch_log_group" "sfn_podcast_processing" {
  name              = "/aws/sfn/${local.name_prefix}-podcast-processing"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "sfn_daily_digest" {
  name              = "/aws/sfn/${local.name_prefix}-daily-digest"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "sfn_weekly_digest" {
  name              = "/aws/sfn/${local.name_prefix}-weekly-digest"
  retention_in_days = 30

  tags = local.common_tags
}


# =============================================================================
# EVENTBRIDGE - Scheduled Triggers
# =============================================================================
# EventBridge rules trigger the processing pipelines on a schedule.
# All schedules use cron expressions in UTC. BMJ is in London (GMT/BST),
# so 8 AM GMT = 08:00 UTC (no offset in winter, +1 in summer).
#
# Architecture decision: EventBridge triggers Step Functions rather than
# Lambda directly. This provides the full orchestration benefits of Step
# Functions (retries, parallel processing, error handling) even for
# scheduled runs.
# =============================================================================

# -----------------------------------------------------------------------------
# Daily Podcast Scraping - Runs every 6 hours to catch new episodes promptly
# -----------------------------------------------------------------------------
# Podcasts are published on varying schedules (some daily, some weekly).
# Checking every 6 hours ensures we catch new episodes within a reasonable
# window while keeping costs manageable. The scraper is idempotent - it
# will skip episodes that have already been downloaded.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "podcast_scraping" {
  name                = "${local.name_prefix}-podcast-scraping"
  description         = "Trigger podcast RSS feed scraping every 6 hours"
  schedule_expression = "rate(6 hours)"
  state               = var.environment == "prod" ? "ENABLED" : "DISABLED"

  tags = merge(local.common_tags, {
    Purpose = "Scheduled podcast scraping"
  })
}

resource "aws_cloudwatch_event_target" "podcast_scraping" {
  rule     = aws_cloudwatch_event_rule.podcast_scraping.name
  arn      = aws_sfn_state_machine.podcast_processing.arn
  role_arn = aws_iam_role.eventbridge_execution.arn

  input = jsonencode({
    source        = "eventbridge-schedule"
    execution_time = "$.time"
  })
}

# -----------------------------------------------------------------------------
# Daily Digest Email - 8 AM UTC every day
# -----------------------------------------------------------------------------
# Generates and sends the daily podcast digest email summarising all new
# episodes from the past 24 hours. Scheduled for 8 AM UTC to arrive in
# journalists' inboxes at the start of the London working day.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "daily_digest" {
  name                = "${local.name_prefix}-daily-digest"
  description         = "Trigger daily digest email generation at 8 AM UTC"
  schedule_expression = "cron(0 8 * * ? *)" # 8:00 AM UTC every day
  state               = var.environment == "prod" ? "ENABLED" : "DISABLED"

  tags = merge(local.common_tags, {
    Purpose = "Scheduled daily digest email"
  })
}

resource "aws_cloudwatch_event_target" "daily_digest" {
  rule     = aws_cloudwatch_event_rule.daily_digest.name
  arn      = aws_sfn_state_machine.daily_digest.arn
  role_arn = aws_iam_role.eventbridge_execution.arn

  input = jsonencode({
    source     = "eventbridge-schedule"
    digest_type = "daily"
  })
}

# -----------------------------------------------------------------------------
# Weekly Digest Email - 8 AM UTC every Monday
# -----------------------------------------------------------------------------
# Generates and sends the weekly analysis email every Monday morning.
# Provides a higher-level strategic view of podcast narratives and trends
# from the past week. Monday morning delivery ensures it is available at
# the start of the editorial planning week.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "weekly_digest" {
  name                = "${local.name_prefix}-weekly-digest"
  description         = "Trigger weekly digest email generation at 8 AM UTC every Monday"
  schedule_expression = "cron(0 8 ? * MON *)" # 8:00 AM UTC every Monday
  state               = var.environment == "prod" ? "ENABLED" : "DISABLED"

  tags = merge(local.common_tags, {
    Purpose = "Scheduled weekly digest email"
  })
}

resource "aws_cloudwatch_event_target" "weekly_digest" {
  rule     = aws_cloudwatch_event_rule.weekly_digest.name
  arn      = aws_sfn_state_machine.weekly_digest.arn
  role_arn = aws_iam_role.eventbridge_execution.arn

  input = jsonencode({
    source     = "eventbridge-schedule"
    digest_type = "weekly"
  })
}


# =============================================================================
# API GATEWAY - REST API for Admin SPA
# =============================================================================
# API Gateway provides the REST API that the admin SPA uses to manage
# podcasts, view episodes, and configure distribution lists. All endpoints
# are protected by a Cognito authoriser - only authenticated users with
# valid JWT tokens can access the API.
#
# Architecture decision: REST API (not HTTP API) is used here because it
# supports Cognito authorisers natively and provides request/response
# transformation capabilities that may be useful for the admin interface.
# =============================================================================

resource "aws_api_gateway_rest_api" "admin" {
  name        = "${local.name_prefix}-admin-api"
  description = "REST API for Pod Monitor admin SPA"

  endpoint_configuration {
    types = ["REGIONAL"] # Regional endpoint; CloudFront handles edge caching
  }

  tags = merge(local.common_tags, {
    Purpose = "Admin SPA REST API"
  })
}

# Cognito authoriser for API Gateway - validates JWT tokens from the SPA
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${local.name_prefix}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.admin.id
  type            = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"

  provider_arns = [aws_cognito_user_pool.admin.arn]
}

# -----------------------------------------------------------------------------
# API Resources and Methods
# -----------------------------------------------------------------------------
# The API follows RESTful conventions:
#   GET    /podcasts            - List all podcasts
#   POST   /podcasts            - Add a new podcast
#   GET    /podcasts/{id}       - Get podcast details
#   PUT    /podcasts/{id}       - Update podcast
#   DELETE /podcasts/{id}       - Remove podcast
#   GET    /episodes            - List episodes (with filters)
#   GET    /episodes/{id}       - Get episode details
#   GET    /distribution-lists  - Get distribution lists
#   PUT    /distribution-lists  - Update distribution lists
#   POST   /trigger/scrape      - Manually trigger scraping
#   POST   /trigger/digest      - Manually trigger digest
# -----------------------------------------------------------------------------

# /podcasts resource
resource "aws_api_gateway_resource" "podcasts" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_rest_api.admin.root_resource_id
  path_part   = "podcasts"
}

# /podcasts/{id} resource
resource "aws_api_gateway_resource" "podcast_by_id" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_resource.podcasts.id
  path_part   = "{id}"
}

# /episodes resource
resource "aws_api_gateway_resource" "episodes" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_rest_api.admin.root_resource_id
  path_part   = "episodes"
}

# /episodes/{id} resource
resource "aws_api_gateway_resource" "episode_by_id" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_resource.episodes.id
  path_part   = "{id}"
}

# /distribution-lists resource
resource "aws_api_gateway_resource" "distribution_lists" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_rest_api.admin.root_resource_id
  path_part   = "distribution-lists"
}

# /trigger resource (manual pipeline triggers)
resource "aws_api_gateway_resource" "trigger" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_rest_api.admin.root_resource_id
  path_part   = "trigger"
}

# /trigger/scrape
resource "aws_api_gateway_resource" "trigger_scrape" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_resource.trigger.id
  path_part   = "scrape"
}

# /trigger/digest
resource "aws_api_gateway_resource" "trigger_digest" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_resource.trigger.id
  path_part   = "digest"
}

# -----------------------------------------------------------------------------
# GET /podcasts - List all podcasts
# -----------------------------------------------------------------------------
resource "aws_api_gateway_method" "get_podcasts" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.podcasts.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "get_podcasts" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.podcasts.id
  http_method             = aws_api_gateway_method.get_podcasts.http_method
  integration_http_method = "POST" # Lambda proxy always uses POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# POST /podcasts - Add a new podcast
resource "aws_api_gateway_method" "post_podcasts" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.podcasts.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "post_podcasts" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.podcasts.id
  http_method             = aws_api_gateway_method.post_podcasts.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# GET /podcasts/{id} - Get podcast details
resource "aws_api_gateway_method" "get_podcast_by_id" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.podcast_by_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "get_podcast_by_id" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.podcast_by_id.id
  http_method             = aws_api_gateway_method.get_podcast_by_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# PUT /podcasts/{id} - Update podcast
resource "aws_api_gateway_method" "put_podcast_by_id" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.podcast_by_id.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "put_podcast_by_id" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.podcast_by_id.id
  http_method             = aws_api_gateway_method.put_podcast_by_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# DELETE /podcasts/{id} - Remove podcast
resource "aws_api_gateway_method" "delete_podcast_by_id" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.podcast_by_id.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "delete_podcast_by_id" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.podcast_by_id.id
  http_method             = aws_api_gateway_method.delete_podcast_by_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# GET /episodes - List episodes
resource "aws_api_gateway_method" "get_episodes" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.episodes.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "get_episodes" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.episodes.id
  http_method             = aws_api_gateway_method.get_episodes.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# GET /episodes/{id} - Get episode details
resource "aws_api_gateway_method" "get_episode_by_id" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.episode_by_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "get_episode_by_id" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.episode_by_id.id
  http_method             = aws_api_gateway_method.get_episode_by_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# GET /distribution-lists - Get distribution lists
resource "aws_api_gateway_method" "get_distribution_lists" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.distribution_lists.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "get_distribution_lists" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.distribution_lists.id
  http_method             = aws_api_gateway_method.get_distribution_lists.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_email_generator.invoke_arn
}

# PUT /distribution-lists - Update distribution lists
resource "aws_api_gateway_method" "put_distribution_lists" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.distribution_lists.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "put_distribution_lists" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.distribution_lists.id
  http_method             = aws_api_gateway_method.put_distribution_lists.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_email_generator.invoke_arn
}

# POST /trigger/scrape - Manually trigger scraping
resource "aws_api_gateway_method" "post_trigger_scrape" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.trigger_scrape.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "post_trigger_scrape" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.trigger_scrape.id
  http_method             = aws_api_gateway_method.post_trigger_scrape.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_scraper.invoke_arn
}

# POST /trigger/digest - Manually trigger digest
resource "aws_api_gateway_method" "post_trigger_digest" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.trigger_digest.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "post_trigger_digest" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.trigger_digest.id
  http_method             = aws_api_gateway_method.post_trigger_digest.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pod_email_generator.invoke_arn
}

# -----------------------------------------------------------------------------
# CORS Configuration
# -----------------------------------------------------------------------------
# Enable CORS on all API endpoints so the SPA (served from CloudFront)
# can make cross-origin requests to the API Gateway.
# -----------------------------------------------------------------------------

# OPTIONS method for CORS preflight on /podcasts
resource "aws_api_gateway_method" "options_podcasts" {
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  resource_id   = aws_api_gateway_resource.podcasts.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_podcasts" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  resource_id = aws_api_gateway_resource.podcasts.id
  http_method = aws_api_gateway_method.options_podcasts.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_podcasts" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  resource_id = aws_api_gateway_resource.podcasts.id
  http_method = aws_api_gateway_method.options_podcasts.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_podcasts" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  resource_id = aws_api_gateway_resource.podcasts.id
  http_method = aws_api_gateway_method.options_podcasts.http_method
  status_code = aws_api_gateway_method_response.options_podcasts.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# -----------------------------------------------------------------------------
# API Gateway Deployment and Stage
# -----------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "admin" {
  rest_api_id = aws_api_gateway_rest_api.admin.id

  # Force redeployment when API configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.podcasts.id,
      aws_api_gateway_resource.podcast_by_id.id,
      aws_api_gateway_resource.episodes.id,
      aws_api_gateway_resource.episode_by_id.id,
      aws_api_gateway_resource.distribution_lists.id,
      aws_api_gateway_resource.trigger.id,
      aws_api_gateway_resource.trigger_scrape.id,
      aws_api_gateway_resource.trigger_digest.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.get_podcasts,
    aws_api_gateway_integration.post_podcasts,
    aws_api_gateway_integration.get_podcast_by_id,
    aws_api_gateway_integration.put_podcast_by_id,
    aws_api_gateway_integration.delete_podcast_by_id,
    aws_api_gateway_integration.get_episodes,
    aws_api_gateway_integration.get_episode_by_id,
    aws_api_gateway_integration.get_distribution_lists,
    aws_api_gateway_integration.put_distribution_lists,
    aws_api_gateway_integration.post_trigger_scrape,
    aws_api_gateway_integration.post_trigger_digest,
    aws_api_gateway_integration.options_podcasts,
  ]
}

resource "aws_api_gateway_stage" "admin" {
  deployment_id = aws_api_gateway_deployment.admin.id
  rest_api_id   = aws_api_gateway_rest_api.admin.id
  stage_name    = var.environment

  # Enable CloudWatch logging for API Gateway
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = merge(local.common_tags, {
    Purpose = "API Gateway stage"
  })
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name_prefix}-admin-api"
  retention_in_days = 30

  tags = local.common_tags
}

# Lambda permission for API Gateway to invoke Lambda functions
resource "aws_lambda_permission" "api_gateway_scraper" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pod_scraper.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.admin.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_email_generator" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pod_email_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.admin.execution_arn}/*/*"
}


# =============================================================================
# SES - Email Delivery
# =============================================================================
# Amazon SES is used to send the daily and weekly digest emails to the
# distribution lists. The sender email identity must be verified before
# emails can be sent.
#
# Note: New SES accounts start in "sandbox" mode, which limits sending to
# verified email addresses only. A production deployment requires requesting
# production access from AWS. For initial testing, add recipient email
# addresses as verified identities.
# =============================================================================

resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
}

# Optional: SES domain identity for production use.
# Uncomment when you have a verified domain.
# resource "aws_ses_domain_identity" "main" {
#   domain = "bmj.com"
# }
#
# resource "aws_ses_domain_dkim" "main" {
#   domain = aws_ses_domain_identity.main.domain
# }


# =============================================================================
# ADDITIONAL LAMBDA PERMISSIONS
# =============================================================================
# Step Functions and EventBridge need explicit permission to invoke Lambda
# functions. These are separate from the IAM role policies above.
# =============================================================================

# Allow Step Functions to invoke all Lambda functions
resource "aws_lambda_permission" "sfn_invoke_scraper" {
  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pod_scraper.function_name
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.podcast_processing.arn
}

resource "aws_lambda_permission" "sfn_invoke_transcriber" {
  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pod_transcriber.function_name
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.podcast_processing.arn
}

resource "aws_lambda_permission" "sfn_invoke_summariser" {
  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pod_summariser.function_name
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.podcast_processing.arn
}

resource "aws_lambda_permission" "sfn_invoke_email_daily" {
  statement_id  = "AllowStepFunctionsInvokeDaily"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pod_email_generator.function_name
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.daily_digest.arn
}

resource "aws_lambda_permission" "sfn_invoke_email_weekly" {
  statement_id  = "AllowStepFunctionsInvokeWeekly"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pod_email_generator.function_name
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.weekly_digest.arn
}
