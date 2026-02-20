# =============================================================================
# Dev Environment Configuration
# =============================================================================
# Usage: terraform plan -var-file="environments/dev.tfvars"
# =============================================================================

environment  = "dev"
project_name = "pod-monitor"
aws_region   = "eu-west-2"

# -- REQUIRED: Set these before deploying ------------------------------------
admin_email  = "your-admin@example.com"
sender_email = "pod-monitor@example.com"

# -- EKS sizing (small for dev) ---------------------------------------------
cluster_version     = "1.29"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 3

# -- AI model ----------------------------------------------------------------
bedrock_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"

# -- Networking ---------------------------------------------------------------
vpc_cidr           = "10.0.0.0/16"
enable_nat_gateway = true
