variable "accountid" {
  description = "Account id"
  type        = string
  default     = "385562404581"
}

variable "costcentre" {
  description = "Cost centre"
  type        = string
  default     = "bestpractice"
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
  default     = "eu-west-1"
}

variable "scope" {
  description = "Project scope"
  type        = string
  default     = "editor-prompt"
}


variable "stack" {
  description = "Project stack"
  type        = string
  default     = "dev"
}

variable "product" {
  description = "Product name"
  type        = string
  default     = "editor-prompt-tool"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "editor-prompt"
}

variable "namespace" {
  description = "Namespace of EKS"
  type        = string
  default     = "editor-prompt"
}

variable "zone_name_suffix" {
  description = "Zone name suffix for the domain"
  type        = string
  default     = "eks.bmjgroup.com"
}

variable "domain_name_suffix" {
  description = "Domain name suffix for the wildcard certificate"
  type        = string
  default     = "eks.bmjgroup.com"
}

variable "learning_subject_alternative_names" {
  description = "Subject alternative names for learning"
  type        = list(any)
  default     = []
}

variable "dns_zone_id" {
  description = "The ID of the DNS hosted zone to use for validation records."
  type        = string
}

variable "use_existing_route53_zone" {
  description = "Use existing (via data source) or create new zone (will fail validation, if zone is not reachable)"
  type        = bool
  default     = true
}

variable "eks_oidc_provider_id" {
  description = "EKS OIDC Provider id"
  type        = string
}