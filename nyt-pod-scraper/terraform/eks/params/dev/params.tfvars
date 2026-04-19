accountid           = "REPLACE_WITH_ACCOUNT_ID"
platform            = "aws"
product             = "pod-monitor"
project             = "pod-monitor"
stack               = "dev"
env                 = "dev"
scope               = "pod-monitor"
costcentre          = "bmj-ai"
creator             = "terraform"
namespace           = "pod-monitor"
region              = "eu-west-2"

# VPC
vpc_cidr            = "10.0.0.0/16"
enable_nat_gateway  = true

# EKS
cluster_version     = "1.29"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 4
