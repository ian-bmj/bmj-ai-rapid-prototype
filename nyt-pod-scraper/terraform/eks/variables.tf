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

# --- VPC Configuration -------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (empty = auto-detect first 2)"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for private subnet internet access"
  type        = bool
  default     = true
}

# --- EKS Configuration -------------------------------------------------------

variable "cluster_version" {
  description = "EKS cluster Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}
