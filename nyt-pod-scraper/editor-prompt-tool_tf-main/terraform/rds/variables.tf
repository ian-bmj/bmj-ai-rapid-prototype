variable "accountid" {
  description = "Account id"
  type        = string
  default     = "109227185188"
}

variable "costcentre" {
  description = "Cost centre"
  type        = string
  default     = "editor-prompt"
}

variable "creator" {
  description = "Creator"
  type        = string
  default     = "terraform"
}

variable "env" {
  description = "Name for the alias"
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
  default     = "contributor"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "contributor"
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

variable "domain" {
  description = "Domain to be used for the tests"
  type        = string
  default     = "terraform-aws-modules.modules.tf"
}

variable "vpc_id" {
  description = "VPC ID to use for the RDS security group"
  type        = string
}

variable "rds_subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

##############################################################
###   RDS Configuration
##############################################################

variable "rds_domain_prefix" {
  description = "Prefix for the RDS domain name"
  type        = string
}

variable "rds_instance_class" {
  description = "Instance type of database"
  type        = string
  default     = "db.t3.small"
}
variable "rds_allocated_storage" {
  description = "Storage of database"
  type        = number
  default     = 20
}
variable "db_engine_version" {
  description = "RDS Engine"
  type        = string
  default     = "15.12"
}

variable "rds_multi_az" {
  description = "RDS Multi AZ"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "RDS Backup Retention Period"
  type        = number
  default     = 7
}

variable "cyclestate" {
  type        = string
  default     = "false" # set per-env in *.tfvars if you prefer
  description = "CycleState tag value used on dev/stg"
}
