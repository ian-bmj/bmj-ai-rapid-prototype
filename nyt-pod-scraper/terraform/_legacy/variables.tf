# =============================================================================
# NYT Pod Scraper - Terraform Variables
# =============================================================================
#
# Input variables for the Pod Monitor infrastructure. These allow the same
# Terraform configuration to be deployed across multiple environments
# (dev, staging, prod) with different settings.
#
# Usage:
#   terraform plan -var-file="environments/dev.tfvars"
#   terraform plan -var-file="environments/prod.tfvars"
#
# Or set via environment variables:
#   export TF_VAR_admin_email="editor@bmj.com"
#   export TF_VAR_sender_email="pod-monitor@bmj.com"
# =============================================================================

# -----------------------------------------------------------------------------
# Core Infrastructure Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = <<-EOT
    AWS region for all resources. Defaults to eu-west-2 (London) as BMJ is
    London-based. This region provides the lowest latency for BMJ editorial
    staff and keeps data within the UK for compliance purposes.

    Note: Amazon Bedrock model availability varies by region. Ensure the
    chosen region supports the required Bedrock models (Claude, Whisper).
    As of 2025, eu-west-2 supports Anthropic Claude models on Bedrock.
  EOT
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^(eu|us|ap)-(west|east|central|south|north|southeast|northeast)-[1-3]$", var.aws_region))
    error_message = "The aws_region must be a valid AWS region identifier (e.g. eu-west-2, us-east-1)."
  }
}

variable "environment" {
  description = <<-EOT
    Deployment environment. Used for resource naming, tagging, and
    environment-specific behaviour:

    - dev:     Development environment. EventBridge schedules are DISABLED
               by default to avoid unnecessary costs. Reduced log retention.
    - staging: Pre-production environment for integration testing.
               EventBridge schedules are DISABLED by default.
    - prod:    Production environment. All schedules ENABLED.
               Full monitoring and alerting.
  EOT
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "The environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = <<-EOT
    Project name used as a prefix for all AWS resource names. This ensures
    resources are easily identifiable and avoids naming collisions when
    multiple projects share the same AWS account.

    Resource naming convention: {project_name}-{environment}-{resource}
    Example: pod-monitor-dev-frontend, pod-monitor-prod-episodes
  EOT
  type        = string
  default     = "pod-monitor"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "The project_name must be 3-21 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

# -----------------------------------------------------------------------------
# Authentication Variables
# -----------------------------------------------------------------------------

variable "admin_email" {
  description = <<-EOT
    Email address for the initial Cognito admin user. This user will be
    created automatically when the infrastructure is first deployed and
    will receive a temporary password via email.

    This user is added to the 'admin' Cognito group with full access to
    the Pod Monitor admin SPA (podcast management, distribution lists,
    manual pipeline triggers).

    Additional users can be added through the AWS Console or via the
    Cognito Admin API after initial deployment.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "The admin_email must be a valid email address."
  }
}

# -----------------------------------------------------------------------------
# Email Configuration Variables
# -----------------------------------------------------------------------------

variable "sender_email" {
  description = <<-EOT
    Email address used as the 'From' address for all digest emails sent
    by the Pod Monitor tool. This email must be verified in Amazon SES
    before emails can be sent.

    For production use, consider using a domain identity (e.g. @bmj.com)
    rather than a single email address, as it provides better deliverability
    and allows sending from any address at that domain.

    Note: New SES accounts are in sandbox mode. In sandbox mode, both
    sender and recipient email addresses must be verified. Request
    production access from AWS to send to unverified recipients.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "The sender_email must be a valid email address."
  }
}

# -----------------------------------------------------------------------------
# AI/ML Configuration Variables
# -----------------------------------------------------------------------------

variable "bedrock_model_id" {
  description = <<-EOT
    Amazon Bedrock model identifier used for transcript summarisation and
    digest generation. The model must be available in the configured
    AWS region and enabled in the Bedrock console.

    Recommended models:
    - anthropic.claude-3-5-sonnet-20241022-v2:0  (Best balance of quality and cost)
    - anthropic.claude-3-5-haiku-20241022-v1:0   (Faster, lower cost, good for summaries)
    - anthropic.claude-3-opus-20240229-v1:0      (Highest quality, highest cost)

    The summariser Lambda uses this model for:
    1. Episode transcript summarisation (key points, themes, notable quotes)
    2. Daily digest meta-analysis (cross-podcast theme identification)
    3. Weekly trend analysis (rhetorical shifts, emerging narratives)

    Model selection impacts both quality and cost. For ~80 podcasts with
    daily processing, Sonnet provides the best quality-to-cost ratio.
    Haiku can be used for dev/staging to reduce costs during testing.
  EOT
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"

  validation {
    condition     = can(regex("^[a-z0-9.-]+:[0-9]+$", var.bedrock_model_id))
    error_message = "The bedrock_model_id must be a valid Bedrock model identifier (e.g. anthropic.claude-3-5-sonnet-20241022-v2:0)."
  }
}

# -----------------------------------------------------------------------------
# Optional Configuration Variables
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = <<-EOT
    Number of days to retain CloudWatch logs for Lambda functions, Step
    Functions, and API Gateway. Longer retention is useful for debugging
    and audit purposes but increases CloudWatch costs.

    Recommended values:
    - dev:     7 days   (minimal retention for development)
    - staging: 14 days  (enough for integration testing cycles)
    - prod:    30 days  (compliance and debugging window)
  EOT
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "The log_retention_days must be a valid CloudWatch Logs retention period."
  }
}

variable "scrape_interval_hours" {
  description = <<-EOT
    How frequently (in hours) to scrape podcast RSS feeds for new episodes.
    Lower values catch new episodes faster but increase costs (Lambda
    invocations, Bedrock API calls).

    Recommended values:
    - 4 hours:  For time-sensitive monitoring (e.g. breaking news podcasts)
    - 6 hours:  Good balance of timeliness and cost (default)
    - 12 hours: Sufficient for daily digest workflows
    - 24 hours: Minimum viable for weekly analysis workflows
  EOT
  type        = number
  default     = 6

  validation {
    condition     = var.scrape_interval_hours >= 1 && var.scrape_interval_hours <= 24
    error_message = "The scrape_interval_hours must be between 1 and 24."
  }
}

variable "max_concurrent_transcriptions" {
  description = <<-EOT
    Maximum number of podcast episodes to transcribe concurrently in the
    Step Functions processing pipeline. Higher concurrency processes
    episodes faster but increases Bedrock API costs and may hit
    service quotas.

    This value maps to the Step Functions Map state MaxConcurrency setting.
    Consider Bedrock API rate limits when setting this value.
  EOT
  type        = number
  default     = 5

  validation {
    condition     = var.max_concurrent_transcriptions >= 1 && var.max_concurrent_transcriptions <= 20
    error_message = "The max_concurrent_transcriptions must be between 1 and 20."
  }
}

variable "enable_point_in_time_recovery" {
  description = <<-EOT
    Enable DynamoDB point-in-time recovery (PITR) for all tables. PITR
    provides continuous backups of DynamoDB data for the last 35 days,
    allowing restoration to any second within that window.

    Recommended: true for staging and prod, false for dev to reduce costs.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = <<-EOT
    Additional tags to apply to all resources. These are merged with the
    default tags (Project, Environment, ManagedBy, Team) defined in the
    provider configuration.

    Example:
    tags = {
      CostCentre = "BMJ-AI-2025"
      Owner      = "editorial-team"
    }
  EOT
  type        = map(string)
  default     = {}
}
