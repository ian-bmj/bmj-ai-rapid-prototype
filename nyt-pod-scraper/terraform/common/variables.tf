variable "accountid" {
  description = "AWS Account ID"
  type        = string
}

variable "costcentre" {
  description = "Cost centre"
  type        = string
  default     = "bmj-ai"
}

variable "creator" {
  description = "Creator"
  type        = string
  default     = "terraform"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "platform" {
  description = "Platform"
  type        = string
  default     = "aws"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "scope" {
  description = "Project scope"
  type        = string
  default     = "pod-monitor"
}

variable "stack" {
  description = "Project stack (environment)"
  type        = string
  default     = "dev"
}

variable "product" {
  description = "Product name"
  type        = string
  default     = "pod-monitor"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "pod-monitor"
}

variable "namespace" {
  description = "Namespace for EKS"
  type        = string
  default     = "pod-monitor"
}

variable "sender_email" {
  description = "Email address for SES sender identity"
  type        = string
}

variable "admin_email" {
  description = "Email address for the initial Cognito admin user"
  type        = string
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock model ID for summarisation"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}

variable "eks_oidc_provider_id" {
  description = "EKS OIDC Provider ID for IRSA role trust policy"
  type        = string
}
