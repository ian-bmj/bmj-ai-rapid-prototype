#----------------------------------------------------
# S3 backend for Terraform state (dev)
#----------------------------------------------------
bucket = "bmj-dev-tfstate"

key = "pod-monitor/eks/infra.tfstate"

dynamodb_table = "bmj-dev-tf"

region = "eu-west-2"
