# =============================================================================
# BMJ Pod Monitor - EKS Deployment Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Core Infrastructure
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources. eu-west-2 (London) for BMJ."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^(eu|us|ap)-(west|east|central|south|north|southeast|northeast)-[1-3]$", var.aws_region))
    error_message = "Must be a valid AWS region (e.g. eu-west-2, us-east-1)."
  }
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name prefix for all AWS resources."
  type        = string
  default     = "pod-monitor"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "Must be 3-21 lowercase alphanumeric characters or hyphens."
  }
}

# -----------------------------------------------------------------------------
# EKS Configuration
# -----------------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones. Defaults to 2 AZs in the region."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Application Configuration
# -----------------------------------------------------------------------------

variable "admin_email" {
  description = "Email for the initial admin user (Cognito)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Must be a valid email address."
  }
}

variable "sender_email" {
  description = "Email used as the From address for digest emails (SES verified)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "Must be a valid email address."
  }
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock model ID for summarisation."
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet internet access. Required for EKS workers in private subnets."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for all resources."
  type        = map(string)
  default     = {}
}
